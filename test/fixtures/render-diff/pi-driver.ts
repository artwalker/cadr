import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { ToolResultMessage } from "@earendil-works/pi-ai";
import { fauxAssistantMessage, fauxThinking, fauxToolCall, registerFauxProvider } from "@earendil-works/pi-ai/compat";
import { getCapabilities, setCapabilities } from "@earendil-works/pi-tui";
import {
	type CreateAgentSessionRuntimeFactory,
	createAgentSessionFromServices,
	createAgentSessionRuntime,
	createAgentSessionServices,
} from "../src/core/agent-session-runtime.ts";
import { AuthStorage } from "../src/core/auth-storage.ts";
import { ModelRuntime } from "../src/core/model-runtime.ts";
import { SessionManager } from "../src/core/session-manager.ts";
import { SettingsManager } from "../src/core/settings-manager.ts";
import { ProjectTrustStore } from "../src/core/trust-manager.ts";
import { InteractiveMode } from "../src/modes/interactive/interactive-mode.ts";
import { initTheme } from "../src/modes/interactive/theme/theme.ts";
import { printHelp } from "../src/cli/args.ts";
import { handleConfigCommand, handlePackageCommand } from "../src/package-manager-cli.ts";
import { main as baselineMain } from "../src/main.ts";

type JsonObject = Record<string, unknown>;

interface ResponseBlock {
	type: "text" | "thinking" | "toolCall";
	text?: string;
	name?: string;
	arguments?: JsonObject;
	id?: string;
}

interface ResponseSpec {
	content: ResponseBlock[];
	stopReason?: "stop" | "length" | "toolUse" | "error" | "aborted";
	errorMessage?: string;
}

interface SeedMessage {
	role: "user" | "assistant";
	text: string;
	provider?: string;
	model?: string;
	responseModel?: string;
	usage?: {
		input?: number;
		output?: number;
		cacheRead?: number;
		cacheWrite?: number;
		cost?: {
			input?: number;
			output?: number;
			cacheRead?: number;
			cacheWrite?: number;
			total?: number;
		};
	};
}

interface SeedEntryBase {
	/** Scenario-local handle used by entries that refer to an earlier entry. */
	key?: string;
}

interface SeedUserEntry extends SeedEntryBase {
	type: "user";
	text: string;
}

interface SeedAssistantEntry extends SeedEntryBase {
	type: "assistant";
	/** Omit both content and text to construct an assistant message with no blocks. */
	content?: ResponseBlock[];
	text?: string;
	stopReason?: "stop" | "length" | "toolUse" | "error" | "aborted";
	errorMessage?: string;
	provider?: string;
	model?: string;
	responseModel?: string;
}

interface SeedToolResultEntry extends SeedEntryBase {
	type: "toolResult";
	toolCallId: string;
	toolName: string;
	text: string;
	isError?: boolean;
	details?: unknown;
	addedToolNames?: string[];
}

interface SeedCompactionEntry extends SeedEntryBase {
	type: "compaction";
	summary: string;
	firstKept: string;
	tokensBefore?: number;
	details?: unknown;
	fromHook?: boolean;
}

interface SeedBranchSummaryEntry extends SeedEntryBase {
	type: "branchSummary";
	from: string;
	summary: string;
	details?: unknown;
	fromHook?: boolean;
}

interface SeedModelChangeEntry extends SeedEntryBase {
	type: "modelChange";
	provider: string;
	modelId: string;
}

interface SeedThinkingLevelChangeEntry extends SeedEntryBase {
	type: "thinkingLevelChange";
	thinkingLevel: string;
}

interface SeedCustomEntry extends SeedEntryBase {
	type: "custom";
	customType: string;
	data?: unknown;
}

interface SeedCustomMessageEntry extends SeedEntryBase {
	type: "customMessage";
	customType: string;
	content: string;
	display?: boolean;
	details?: unknown;
}

interface SeedLabelEntry extends SeedEntryBase {
	type: "label";
	target: string;
	label?: string;
}

interface SeedTitleEntry extends SeedEntryBase {
	type: "title";
	name: string;
}

type SeedEntry =
	| SeedUserEntry
	| SeedAssistantEntry
	| SeedToolResultEntry
	| SeedCompactionEntry
	| SeedBranchSummaryEntry
	| SeedModelChangeEntry
	| SeedThinkingLevelChangeEntry
	| SeedCustomEntry
	| SeedCustomMessageEntry
	| SeedLabelEntry
	| SeedTitleEntry;

interface ScenarioSetup {
	persistentSession?: boolean;
	projectTrusted?: boolean;
	seedMessages?: SeedMessage[];
	seedEntries?: SeedEntry[];
	crashAfterMs?: number;
	extensionSurfaces?: boolean;
	injectedCompactionReason?: "manual" | "threshold" | "overflow";
	fixtureFiles?: FixtureFile[];
	extraSessions?: ExtraSessionFixture[];
	resources?: ResourceFixtureOptions;
	startup?: StartupFixtureOptions;
	runtimeActions?: RuntimeAction[];
	comparisonProviders?: boolean;
	comparisonModelCount?: number;
	enabledModelIds?: string[];
	supportsImages?: boolean;
	hyperlinks?: boolean;
	trustSavedDecision?: { scope: "current" | "parent"; decision: boolean };
	authProvider?: boolean;
	entrypoint?: "interactive" | "config" | "cli-help" | "cli-errors" | "main";
	mainArgv?: string[];
	pickerSessions?: ExtraSessionFixture[];
	updateNotifications?: boolean;
	exampleExtensions?: string[];
}

interface FixtureFile {
	root: "workspace" | "agent" | "sessions" | "projectConfig";
	path: string;
	content: string;
}

interface ResourceFixtureOptions {
	skills?: boolean;
	promptTemplates?: boolean;
	themes?: boolean;
	contextFiles?: boolean;
	extensions?: boolean;
}

interface StartupFixtureOptions {
	migratedProviders?: string[];
	modelFallbackMessage?: string;
}

interface ExtraSessionFixture {
	id: string;
	cwd?: string;
	name?: string;
	ageSeconds?: number;
	messages?: SeedMessage[];
}

type RuntimeAction =
	| { type: "pause"; milliseconds: number }
	| { type: "prompt"; text: string; background?: boolean }
	| { type: "steer"; text: string }
	| { type: "followUp"; text: string }
	| { type: "compact"; customInstructions?: string; background?: boolean }
	| { type: "abort" }
	| { type: "waitForIdle" };

interface Scenario {
	id: string;
	group: string;
	responses: ResponseSpec[];
	setup?: ScenarioSetup;
	stream?: {
		tokensPerSecond?: number;
		chunkCharacters?: number;
	};
}

function loadScenario(path: string, id: string): Scenario {
	const manifest = JSON.parse(readFileSync(path, "utf8")) as { scenarios: Scenario[] };
	const scenario = manifest.scenarios.find((candidate) => candidate.id === id);
	if (!scenario) throw new Error(`Unknown render-diff scenario: ${id}`);
	return scenario;
}

function fixtureRoot(root: FixtureFile["root"], cwd: string, agentDir: string, sessionDir: string): string {
	if (root === "workspace") return cwd;
	if (root === "agent") return agentDir;
	if (root === "sessions") return sessionDir;
	return join(cwd, ".pi");
}

function resolveFixturePath(root: string, path: string): string {
	if (!path || isAbsolute(path)) throw new Error(`Render fixture path must be relative: ${path}`);
	const resolvedRoot = resolve(root);
	const resolvedPath = resolve(resolvedRoot, path);
	const fromRoot = relative(resolvedRoot, resolvedPath);
	if (fromRoot === ".." || fromRoot.startsWith(`..${process.platform === "win32" ? "\\" : "/"}`) || isAbsolute(fromRoot)) {
		throw new Error(`Render fixture path escapes its root: ${path}`);
	}
	return resolvedPath;
}

function materializeFixtureFiles(
	files: readonly FixtureFile[],
	cwd: string,
	agentDir: string,
	sessionDir: string,
): void {
	for (const file of files) {
		const path = resolveFixturePath(fixtureRoot(file.root, cwd, agentDir, sessionDir), file.path);
		mkdirSync(dirname(path), { recursive: true });
		writeFileSync(path, file.content, "utf8");
	}
}

function applyExampleHarnessDeterminism(name: string, source: string): string {
	let text = `Math.random = () => 0;\n${source}`;
	text = text.replaceAll(
		"this.interval = setInterval(",
		"this.interval = process.env.RENDER_DIFF_READY_PATH ? (null as never) : setInterval(",
	);
	if (name === "snake") {
		const needle =
			"\t\t} else if (matchesKey(data, \"left\") || data === \"a\" || data === \"A\") {\n" +
			"\t\t\tif (this.state.direction !== \"right\") this.state.nextDirection = \"left\";\n" +
			"\t\t}";
		const replacement =
			`${needle}\n` +
			"\t\tif (process.env.RENDER_DIFF_READY_PATH && !this.state.gameOver) {\n" +
			"\t\t\tthis.tick();\n" +
			"\t\t\tthis.version++;\n" +
			"\t\t\tthis.tui.requestRender();\n" +
			"\t\t}";
		if (!text.includes(needle)) {
			throw new Error("snake.ts handleInput shape changed; cannot apply harness tick hook");
		}
		text = text.replace(needle, replacement);
	}
	return text;
}

function exampleExtensionToolNames(names: readonly string[]): string[] {
	const toolsByExample: Record<string, readonly string[]> = {
		hello: ["hello"],
		todo: ["todo"],
		"reload-runtime": ["reload_runtime"],
	};
	return names.flatMap((name) => [...(toolsByExample[name] ?? [])]);
}

function materializeExampleExtensions(names: readonly string[], agentDir: string): void {
	if (names.length === 0) {
		return;
	}
	const sourceDirectory = join(
		dirname(fileURLToPath(import.meta.url)),
		"..",
		"examples",
		"extensions",
	);
	const destinationDirectory = join(agentDir, "extensions");
	mkdirSync(destinationDirectory, { recursive: true });
	for (const name of names) {
		const source = join(sourceDirectory, `${name}.ts`);
		if (!existsSync(source)) {
			throw new Error(`Unknown baseline example extension: ${source}`);
		}
		let text = readFileSync(source, "utf8");
		if (process.env.RENDER_DIFF_READY_PATH) {
			text = applyExampleHarnessDeterminism(name, text);
		}
		writeFileSync(join(destinationDirectory, `${name}.ts`), text, "utf8");
	}
}

async function runRuntimeActions(
	session: Awaited<ReturnType<typeof createAgentSessionRuntime>>["session"],
	actions: readonly RuntimeAction[],
): Promise<void> {
	const background = new Set<Promise<void>>();
	const start = (operation: Promise<unknown>): void => {
		const tracked = operation.then(() => {}).finally(() => background.delete(tracked));
		background.add(tracked);
	};
	for (const action of actions) {
		switch (action.type) {
			case "pause":
				await new Promise((resolvePause) => setTimeout(resolvePause, action.milliseconds));
				break;
			case "prompt": {
				const operation = session.prompt(action.text);
				if (action.background) start(operation);
				else await operation;
				break;
			}
			case "steer":
				await session.steer(action.text);
				break;
			case "followUp":
				await session.followUp(action.text);
				break;
			case "compact": {
				const operation = session.compact(action.customInstructions);
				if (action.background) start(operation);
				else await operation;
				break;
			}
			case "abort":
				await session.abort();
				break;
			case "waitForIdle":
				await session.waitForIdle();
				break;
		}
	}
	await Promise.all(background);
}

function responseFromSpec(spec: ResponseSpec) {
	const blocks = spec.content.map((block) => {
		if (block.type === "text") return { type: "text" as const, text: block.text ?? "" };
		if (block.type === "thinking") return fauxThinking(block.text ?? "");
		return fauxToolCall(block.name ?? "", block.arguments ?? {}, { id: block.id });
	});
	return fauxAssistantMessage(blocks, {
		stopReason: spec.stopReason,
		errorMessage: spec.errorMessage,
		timestamp: 1_700_000_000_000,
		responseId: "render-diff-response",
	});
}

function createFixedSessionFile(
	sessionDir: string,
	cwd: string,
	id: string,
	suffix: string,
	timestampMs = 1_700_000_000_000,
): string {
	mkdirSync(sessionDir, { recursive: true });
	const path = join(sessionDir, `2023-11-14T22-13-20-000Z_${suffix}.jsonl`);
	writeFileSync(
		path,
		`${JSON.stringify({
			type: "session",
			version: 3,
			id,
			timestamp: new Date(timestampMs).toISOString(),
			cwd,
		})}\n`,
		"utf8",
	);
	return path;
}

function appendSeedMessages(
	session: SessionManager,
	messages: readonly SeedMessage[],
	baseTimestampMs = 1_700_000_000_000,
): void {
	for (const [index, message] of messages.entries()) {
		if (message.role === "user") {
			session.appendMessage({
				role: "user",
				content: message.text,
				timestamp: baseTimestampMs + index,
			});
		} else {
			const assistant = fauxAssistantMessage(message.text, {
					timestamp: baseTimestampMs + index,
					responseId: `render-seed-${index}`,
				});
			assistant.provider = message.provider ?? assistant.provider;
			assistant.model = message.model ?? assistant.model;
			assistant.responseModel = message.responseModel;
			if (message.usage) {
				assistant.usage = {
					input: message.usage.input ?? 0,
					output: message.usage.output ?? 0,
					cacheRead: message.usage.cacheRead ?? 0,
					cacheWrite: message.usage.cacheWrite ?? 0,
					totalTokens:
						(message.usage.input ?? 0) +
						(message.usage.output ?? 0) +
						(message.usage.cacheRead ?? 0) +
						(message.usage.cacheWrite ?? 0),
					cost: {
						input: message.usage.cost?.input ?? 0,
						output: message.usage.cost?.output ?? 0,
						cacheRead: message.usage.cost?.cacheRead ?? 0,
						cacheWrite: message.usage.cost?.cacheWrite ?? 0,
						total: message.usage.cost?.total ?? 0,
					},
				};
			}
			session.appendMessage(assistant);
		}
	}
}

function appendSeedEntries(session: SessionManager, entries: readonly SeedEntry[]): void {
	const ids = new Map<string, string>();
	const resolveEntry = (key: string): string => {
		const id = ids.get(key);
		if (!id) throw new Error(`Unknown seed entry reference: ${key}`);
		return id;
	};

	for (const [index, entry] of entries.entries()) {
		const timestamp = 1_700_000_100_000 + index;
		if (entry.key !== undefined) {
			if (entry.key.length === 0) throw new Error("Seed entry key must not be empty");
			if (ids.has(entry.key)) throw new Error(`Duplicate seed entry key: ${entry.key}`);
		}
		let id: string;
		switch (entry.type) {
			case "user":
				id = session.appendMessage({ role: "user", content: entry.text, timestamp });
				break;
			case "assistant": {
				const content =
					entry.content !== undefined
						? entry.content.map((block) => {
								if (block.type === "text") return { type: "text" as const, text: block.text ?? "" };
								if (block.type === "thinking") return fauxThinking(block.text ?? "");
								return fauxToolCall(block.name ?? "", block.arguments ?? {}, { id: block.id });
							})
						: entry.text !== undefined
							? entry.text
							: [];
				const message = fauxAssistantMessage(content, {
					stopReason: entry.stopReason,
					errorMessage: entry.errorMessage,
					timestamp,
					responseId: `render-seed-entry-${index}`,
				});
				message.provider = entry.provider ?? message.provider;
				message.model = entry.model ?? message.model;
				message.responseModel = entry.responseModel;
				id = session.appendMessage(message);
				break;
			}
			case "toolResult": {
				const message: ToolResultMessage = {
					role: "toolResult",
					toolCallId: entry.toolCallId,
					toolName: entry.toolName,
					content: [{ type: "text", text: entry.text }],
					details: entry.details,
					addedToolNames: entry.addedToolNames,
					isError: entry.isError ?? false,
					timestamp,
				};
				id = session.appendMessage(message);
				break;
			}
			case "compaction":
				id = session.appendCompaction(
					entry.summary,
					resolveEntry(entry.firstKept),
					entry.tokensBefore ?? 0,
					entry.details,
					entry.fromHook,
				);
				break;
			case "branchSummary":
				id = session.branchWithSummary(resolveEntry(entry.from), entry.summary, entry.details, entry.fromHook);
				break;
			case "modelChange":
				id = session.appendModelChange(entry.provider, entry.modelId);
				break;
			case "thinkingLevelChange":
				id = session.appendThinkingLevelChange(entry.thinkingLevel);
				break;
			case "custom":
				id = session.appendCustomEntry(entry.customType, entry.data);
				break;
			case "customMessage":
				id = session.appendCustomMessageEntry(
					entry.customType,
					entry.content,
					entry.display ?? false,
					entry.details,
				);
				break;
			case "label":
				id = session.appendLabelChange(resolveEntry(entry.target), entry.label);
				break;
			case "title":
				id = session.appendSessionInfo(entry.name);
				break;
		}
		if (entry.key !== undefined) {
			ids.set(entry.key, id);
		}
	}
}

function createSessionManager(cwd: string, sessionDir: string, scenario: Scenario): SessionManager {
	const setup = scenario.setup ?? {};
	if (!setup.persistentSession) {
		const session = SessionManager.inMemory(cwd, { id: "render-session" });
		appendSeedMessages(session, setup.seedMessages ?? []);
		appendSeedEntries(session, setup.seedEntries ?? []);
		return session;
	}

	const currentPath = createFixedSessionFile(sessionDir, cwd, "render-session", "render-session");
	const session = SessionManager.open(currentPath, sessionDir, cwd);
	appendSeedMessages(session, setup.seedMessages ?? []);
	appendSeedEntries(session, setup.seedEntries ?? []);

	const otherPath = createFixedSessionFile(sessionDir, cwd, "other-session", "other-session");
	const other = SessionManager.open(otherPath, sessionDir, cwd);
	appendSeedMessages(other, [
		{ role: "user", text: "other session question" },
		{ role: "assistant", text: "other session answer" },
	]);
	for (const [index, fixture] of (setup.extraSessions ?? []).entries()) {
		if (!/^[A-Za-z0-9_-]+$/.test(fixture.id)) {
			throw new Error(`Invalid render session fixture id: ${fixture.id}`);
		}
		const timestampMs =
			fixture.ageSeconds === undefined ? 1_700_000_000_000 + index + 1 : Date.now() - fixture.ageSeconds * 1000;
		const path = createFixedSessionFile(
			sessionDir,
			fixture.cwd ?? cwd,
			fixture.id,
			`extra-${index.toString().padStart(2, "0")}-${fixture.id}`,
			timestampMs,
		);
		const extra = SessionManager.open(path, sessionDir, fixture.cwd ?? cwd);
		appendSeedMessages(extra, fixture.messages ?? [], timestampMs);
		if (fixture.name) extra.appendSessionInfo(fixture.name);
	}
	return session;
}

function comparisonProvidersEnabled(scenario: Scenario): boolean {
	return (
		scenario.setup?.comparisonProviders === true ||
		["overlays-core", "overlays-secondary", "local-status-sweep"].includes(scenario.id)
	);
}

function authProviderEnabled(scenario: Scenario): boolean {
	return (
		scenario.setup?.authProvider === true ||
		scenario.id.startsWith("overlays-auth") ||
		scenario.id === "overlays-logout"
	);
}

async function registerComparisonProviders(modelRuntime: ModelRuntime, scenario: Scenario): Promise<void> {
	if (comparisonProvidersEnabled(scenario)) {
		const modelCount = scenario.setup?.comparisonModelCount ?? 1;
		if (!Number.isInteger(modelCount) || modelCount < 1) {
			throw new Error(`comparisonModelCount must be a positive integer: ${modelCount}`);
		}
		modelRuntime.registerProvider("other", {
			name: "Other Provider",
			baseUrl: "https://render.invalid/v1",
			apiKey: "render-other-key",
			api: "openai-completions",
			models: Array.from({ length: modelCount }, (_, index) => {
				const ordinal = index + 1;
				return {
					id: `other-${ordinal}`,
					name: modelCount === 1 ? "Other Model" : `Other Model ${ordinal}`,
					reasoning: false,
					input: ["text"],
					cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
					contextWindow: 64_000,
					maxTokens: 8_192,
				};
			}),
		});
	}

	if (authProviderEnabled(scenario)) {
		modelRuntime.registerProvider("render-auth", {
			name: "Render Auth",
			baseUrl: "https://render.invalid/v1",
			apiKey: "render-api-key",
			api: "openai-completions",
			oauth: {
				name: "Render Auth account",
				login: async (callbacks) => {
					callbacks.onAuth({
						url: "https://auth.invalid/authorize?state=render-fixed",
						instructions: "A browser window should open. Complete login to finish.",
					});
					if (!callbacks.onManualCodeInput) {
						throw new Error("render auth manual-code callback is unavailable");
					}
					await callbacks.onManualCodeInput();
					return {
						access: "render-access",
						refresh: "render-refresh",
						expires: 1_800_000_000_000,
					};
				},
				refreshToken: async (credential) => credential,
				getApiKey: (credential) => credential.access,
			},
					models: [
						{
							id: "render-auth-1",
							name: "Render Auth Model",
							reasoning: false,
							input: ["text"],
							cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
							contextWindow: 64_000,
							maxTokens: 8_192,
						},
					],
				});
				modelRuntime.registerProvider("render-device", {
					name: "Render Device",
					baseUrl: "https://render.invalid/v1",
					apiKey: "render-api-key",
					api: "openai-completions",
					oauth: {
						name: "Render Device account",
						login: async (callbacks) => {
							callbacks.onDeviceCode({
								userCode: "RENDER-42",
								verificationUri: "https://auth.invalid/device",
							});
							await new Promise((_resolve, reject) => {
								if (callbacks.signal?.aborted) reject(new Error("Login cancelled"));
								callbacks.signal?.addEventListener("abort", () => reject(new Error("Login cancelled")), { once: true });
							});
							throw new Error("render device login never completes in the fixture");
						},
						refreshToken: async (credential) => credential,
						getApiKey: (credential) => credential.access,
					},
					models: [
						{
							id: "render-device-1",
							name: "Render Device Model",
							reasoning: false,
							input: ["text"],
							cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
							contextWindow: 64_000,
							maxTokens: 8_192,
						},
					],
				});
			}

			if (authProviderEnabled(scenario)) {
				modelRuntime.registerProvider("render-loopback", {
					name: "Render Loopback",
					baseUrl: "https://render.invalid/v1",
					apiKey: "render-api-key",
					api: "openai-completions",
					oauth: {
						name: "Render Loopback account",
						login: async (callbacks) => {
							// Browser-callback flow: listen on a fixed loopback
							// port and complete when the harness delivers it.
							let resolveCode!: () => void;
							let rejectLogin!: (error: Error) => void;
							const done = new Promise<void>((resolve, reject) => {
								resolveCode = resolve;
								rejectLogin = reject;
							});
							const server = createServer((request, response) => {
								response.writeHead(200, { "content-type": "text/plain" });
								response.end("render loopback login received\n");
								resolveCode();
							});
							server.on("error", (error) => rejectLogin(error as Error));
							await new Promise<void>((resolveListen) => {
								server.listen(1459, "127.0.0.1", resolveListen);
							});
							callbacks.onProgress?.("Listening for OAuth callback on http://127.0.0.1:1459/callback");
							callbacks.onAuth({
								url: "https://auth.invalid/authorize?state=render-loopback",
								instructions: "Continue in your browser.",
							});
							try {
								if (callbacks.signal?.aborted) throw new Error("Login cancelled");
								callbacks.signal?.addEventListener(
									"abort",
									() => rejectLogin(new Error("Login cancelled")),
									{ once: true },
								);
								await done;
								return {
									access: "render-access",
									refresh: "render-refresh",
									expires: 1_800_000_000_000,
								};
							} finally {
								server.close();
							}
						},
						refreshToken: async (credential) => credential,
						getApiKey: (credential) => credential.access,
					},
					models: [
						{
							id: "render-loopback-1",
							name: "Render Loopback Model",
							reasoning: false,
							input: ["text"],
							cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
							contextWindow: 64_000,
							maxTokens: 8_192,
						},
					],
				});
			}

	await modelRuntime.refresh({ allowNetwork: false });
}

async function main(): Promise<void> {
	const [manifestPath, scenarioId, cwd, agentDir, sessionDir] = process.argv.slice(2);
	if (!manifestPath || !scenarioId || !cwd || !agentDir || !sessionDir) {
		throw new Error("usage: pi-driver.ts MANIFEST SCENARIO CWD AGENT_DIR SESSION_DIR");
	}

	process.env.PI_OFFLINE = "1";
	const scenario = loadScenario(manifestPath, scenarioId);
	materializeFixtureFiles(scenario.setup?.fixtureFiles ?? [], cwd, agentDir, sessionDir);
	materializeExampleExtensions(scenario.setup?.exampleExtensions ?? [], agentDir);
	if (scenario.setup?.trustSavedDecision) {
		const decision = scenario.setup.trustSavedDecision;
		new ProjectTrustStore(agentDir).set(decision.scope === "parent" ? dirname(cwd) : cwd, decision.decision);
	}
	if (scenario.setup?.entrypoint === "cli-help") {
		process.chdir(cwd);
		printHelp([{ name: "render-flag", type: "string", description: "Render differential extension flag", extensionPath: "render-diff" }]);
		for (const command of ["install", "remove", "update", "list"] as const) {
			await handlePackageCommand([command, "--help"]);
		}
		await handleConfigCommand(["config", "--help"]);
		return;
	}
	if (scenario.setup?.entrypoint === "config") {
		process.chdir(cwd);
		await handleConfigCommand(["config", "--approve"]);
		return;
	}
	if (scenario.setup?.entrypoint === "cli-errors") {
		// Goal 18 I7: drive the baseline's CLI error/warning paths through
		// the real main() so every fixed error literal is exercised with its
		// production wording, color, stream, and exit status.
		process.chdir(cwd);
		// Seed a local session so --fork onto an existing id reports the
		// baseline "Session already exists" error (main.ts:324-330).
		createFixedSessionFile(
			join(agentDir, "sessions", `--${cwd.replace(/^[/\\]/, "").replace(/[/\\:]/g, "-")}--`),
			cwd,
			"sweep-existing",
			"sweep-existing",
		);
		const realExit = process.exit;
		const cases: string[][] = [
			// Startup content migrations (migrations.ts:144,214) run before
			// the metadata commands; this case must stay first.
			["--list-models"],
			["--fork", "x", "--session", "y"],
			["--fork", "x", "--no-session"],
			["--fork", "x", "--session", "y", "--continue"],
			["--session-id", "abc", "--continue"],
			["--session-id", "BAD ID!"],
			["--name", ""],
			["--mode", "rpc", "@foo.txt"],
			["--fork", "nonexistent-session"],
			["--session", "nonexistent-session"],
			["--export", "/nonexistent-session.jsonl"],
			["auth", "bogus"],
			["auth", "print-api-key", "--provider", "bogus", "--model", "gpt-5.5"],
			["install"],
			["config", "--bogus"],
			["remove", "nonexistent-package"],
			["update", "--all", "--self"],
			["install", "x", "y"],
			["update", "--extension"],
			["-p", "@/nonexistent-file.txt"],
			["install", "--bogus"],
			["config", "-l"],
			["install", "-l", "./x"],
			["--fork", "x", "--session-id", "sweep-existing"],
			["--session-id", "fresh-sweep-1", "-p", "hi"],
		];
		for (const argv of cases) {
			process.exitCode = undefined;
			process.exit = ((code?: number) => {
				throw new Error(`__render_diff_exit_${code ?? 0}`);
			}) as never;
			try {
				await baselineMain(argv);
			} catch (error) {
				if (!(error instanceof Error && error.message.startsWith("__render_diff_exit_"))) throw error;
			}
		}
		process.env.PI_STARTUP_BENCHMARK = "1";
		process.exitCode = undefined;
		process.exit = ((code?: number) => {
			throw new Error(`__render_diff_exit_${code ?? 0}`);
		}) as never;
		try {
			await baselineMain(["-p", "hi"]);
		} catch (error) {
			if (!(error instanceof Error && error.message.startsWith("__render_diff_exit_"))) throw error;
		}
		delete process.env.PI_STARTUP_BENCHMARK;
		process.exit = realExit;
		process.exitCode = undefined;
		// Goal 18 I7: corrupt models.json warns and falls back to the
		// empty availability guidance (list-models.ts:30-33,40-42).  Runs
		// after the benchmark case so the failure modes stay isolated.
		const stubbedExit = (async (argv: string[]) => {
			process.exitCode = undefined;
			process.exit = ((code?: number) => {
				throw new Error(`__render_diff_exit_${code ?? 0}`);
			}) as never;
			try {
				await baselineMain(argv);
			} catch (error) {
				if (!(error instanceof Error && error.message.startsWith("__render_diff_exit_"))) throw error;
			} finally {
				process.exit = realExit;
				process.exitCode = undefined;
			}
		});
		writeFileSync(join(agentDir, "models.json"), "{ not valid json ");
		await stubbedExit(["--list-models"]);
		writeFileSync(
			join(agentDir, "models.json"),
			JSON.stringify({ providers: {} }, null, 2),
		);
		// Goal 18 I7: a broken extension is a fatal startup diagnostic
		// with the -ne hint (main.ts:843-849).
		mkdirSync(join(agentDir, "extensions", "broken"), { recursive: true });
		writeFileSync(
			join(agentDir, "extensions", "broken", "index.ts"),
			"export default function () { throw new Error(\"render-drive-broken\"); }\n",
		);
		await stubbedExit(["-p", "hi"]);
		return;
	}
	if (scenario.setup?.entrypoint === "main") {
		// Goal 18 adjudicated main()-path surfaces: the pre-TUI resume
		// picker (cli/session-picker.ts) and the bare-environment
		// no-model sentinel (model-resolver.ts:650-651) only exist on the
		// real main() path, so drive baselineMain directly — no faux
		// provider, no registered auth, real process.exit.
		process.chdir(cwd);
		const pickerSessions = scenario.setup.pickerSessions ?? [];
		if (pickerSessions.length > 0) {
			const slug = `--${cwd.replace(/^[/\\]/, "").replace(/[/\\:]/g, "-")}--`;
			const pickerDir = join(agentDir, "sessions", slug);
			for (const [index, fixture] of pickerSessions.entries()) {
				const timestampMs = 1_700_000_000_000 + index * 60_000;
				const path = createFixedSessionFile(
					pickerDir,
					fixture.cwd ?? cwd,
					fixture.id,
					`picker-${index.toString().padStart(2, "0")}-${fixture.id}`,
					timestampMs,
				);
				const session = SessionManager.open(path, pickerDir, fixture.cwd ?? cwd);
				appendSeedMessages(session, fixture.messages ?? [], timestampMs);
				if (fixture.name) session.appendSessionInfo(fixture.name);
			}
		}
		await baselineMain(scenario.setup.mainArgv ?? []);
		return;
	}
	const chunkCharacters = scenario.stream?.chunkCharacters ?? 4096;
	const faux = registerFauxProvider({
		api: "faux",
		provider: "faux",
		tokensPerSecond: scenario.stream?.tokensPerSecond ?? 0,
		tokenSize: {
			min: Math.max(1, Math.ceil(chunkCharacters / 4)),
			max: Math.max(1, Math.ceil(chunkCharacters / 4)),
		},
	});
	faux.setResponses(scenario.responses.map(responseFromSpec));

	const authStorage = AuthStorage.inMemory();
	await authStorage.modify("faux", async () => ({ type: "api_key", key: "render-diff-key" }));
	const modelRuntime = await ModelRuntime.create({
		credentials: authStorage,
		modelsPath: resolve(agentDir, "models.json"),
	});
	const baseModel = faux.getModel();
	const model = scenario.id === "local-status-sweep" ? { ...baseModel, reasoning: true } : baseModel;
	modelRuntime.registerProvider(model.provider, {
		baseUrl: model.baseUrl,
		apiKey: "render-diff-key",
		api: model.api,
		models: [
			{
				id: model.id,
				name: model.name,
				api: model.api,
				reasoning: true,
				input: model.input,
				cost: model.cost,
				contextWindow: model.contextWindow,
				maxTokens: model.maxTokens,
				baseUrl: model.baseUrl,
			},
		],
	});
	await registerComparisonProviders(modelRuntime, scenario);
	const otherModel = modelRuntime.getModel("other", "other-1");

	const settingsManager = SettingsManager.inMemory(
		{
			theme: "dark",
			quietStartup: false,
			showHardwareCursor: false,
			terminal: { showTerminalProgress: false },
			collapseChangelog: true,
			enabledModels: scenario.setup?.enabledModelIds,
		},
		{ projectTrusted: scenario.setup?.projectTrusted ?? true },
	);
	const runtimeOptions = {
		agentDir,
		modelRuntime,
		settingsManager,
		model,
		resourceLoaderOptions: {
			systemPrompt: "Render differential fixed system prompt.",
			noExtensions: !(
				(scenario.setup?.resources?.extensions ?? false) ||
				((scenario.setup?.exampleExtensions?.length ?? 0) > 0)
			),
			noSkills: !(scenario.setup?.resources?.skills ?? false),
			noPromptTemplates: !(scenario.setup?.resources?.promptTemplates ?? false),
			noThemes: !(scenario.setup?.resources?.themes ?? false),
			noContextFiles: !(scenario.setup?.resources?.contextFiles ?? false),
		},
	};
	const createRuntime: CreateAgentSessionRuntimeFactory = async ({ sessionManager, sessionStartEvent }) => {
		const services = await createAgentSessionServices({ ...runtimeOptions, cwd });
		return {
			...(await createAgentSessionFromServices({
				services,
				sessionManager,
				sessionStartEvent,
				model,
				thinkingLevel: "high",
				tools: [
					"read",
					"bash",
					"edit",
					"write",
					"grep",
					"find",
					"ls",
					...exampleExtensionToolNames(scenario.setup?.exampleExtensions ?? []),
				],
				scopedModels:
					scenario.setup?.enabledModelIds === undefined && comparisonProvidersEnabled(scenario) && otherModel
						? [{ model }, { model: otherModel }]
						: [],
			})),
			services,
			diagnostics: services.diagnostics,
		};
	};
	const runtime = await createAgentSessionRuntime(createRuntime, {
		cwd,
		agentDir,
		sessionManager: createSessionManager(cwd, sessionDir, scenario),
	});

	initTheme("dark", false);
	const mode = new InteractiveMode(runtime, {
		verbose: false,
		alt: false,
		migratedProviders: scenario.setup?.startup?.migratedProviders,
		modelFallbackMessage: scenario.setup?.startup?.modelFallbackMessage,
	});
	let unsubscribeSettled: (() => void) | undefined;
	try {
		await mode.init();
		const readyPath = process.env.RENDER_DIFF_READY_PATH;
		unsubscribeSettled = runtime.session.subscribe((event) => {
			if (event.type === "agent_settled" && readyPath) {
				appendFileSync(readyPath, "agent-settled\n", { encoding: "utf8" });
			}
		});
		if (scenario.setup?.supportsImages !== undefined || scenario.setup?.hyperlinks !== undefined) {
			const capabilities = getCapabilities();
			setCapabilities({
				...capabilities,
				images: scenario.setup.supportsImages ? "kitty" : capabilities.images,
				hyperlinks: scenario.setup.hyperlinks ?? capabilities.hyperlinks,
			});
		}
		if (scenario.setup?.updateNotifications) {
			setTimeout(() => {
				mode.showNewVersionNotification({ version: "9.9.9", note: "Release note" });
				mode.showPackageUpdateNotification(["alpha", "beta"]);
			}, 100);
		}
		if (scenario.setup?.injectedCompactionReason) {
			const eventConsumer = mode as unknown as {
				handleEvent(event: { type: "compaction_start"; reason: "manual" | "threshold" | "overflow" }): Promise<void>;
			};
			await eventConsumer.handleEvent({
				type: "compaction_start",
				reason: scenario.setup.injectedCompactionReason,
			});
		}
		if (readyPath) writeFileSync(readyPath, "ready\n", { encoding: "utf8" });
		if (scenario.setup?.crashAfterMs !== undefined) {
			setTimeout(() => {
				throw new Error("render-diff crash sentinel");
			}, scenario.setup.crashAfterMs);
		}
		if (readyPath) {
			const crashTrigger = `${readyPath}.crash`;
			const crashPoll = setInterval(() => {
				if (existsSync(crashTrigger)) {
					clearInterval(crashPoll);
					throw new Error("render-diff crash sentinel");
				}
			}, 20);
		}
		if (scenario.setup?.extensionSurfaces) {
			const extensionUi = mode as unknown as {
				showExtensionSelector(title: string, options: string[]): Promise<string | undefined>;
				showExtensionInput(title: string, placeholder?: string): Promise<string | undefined>;
				showExtensionEditor(title: string, prefill?: string): Promise<string | undefined>;
			};
			void (async () => {
				await extensionUi.showExtensionSelector("Extension Select", ["alpha", "beta"]);
				await extensionUi.showExtensionInput("Extension Input", "type here");
				await extensionUi.showExtensionEditor("Extension Editor", "prefill");
			})();
		}
		if (scenario.setup?.runtimeActions?.length) {
			void runRuntimeActions(runtime.session, scenario.setup.runtimeActions);
		}
		await mode.run();
	} finally {
		unsubscribeSettled?.();
		mode.stop();
		await runtime.dispose();
		faux.unregister();
	}
}

void main().catch((error: unknown) => {
	process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
	process.exit(1);
});
