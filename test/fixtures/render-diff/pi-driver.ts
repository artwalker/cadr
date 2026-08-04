import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import {
	fauxAssistantMessage,
	fauxThinking,
	fauxToolCall,
	registerFauxProvider,
} from "@earendil-works/pi-ai/compat";
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
import { InteractiveMode } from "../src/modes/interactive/interactive-mode.ts";
import { initTheme } from "../src/modes/interactive/theme/theme.ts";

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

interface ScenarioSetup {
	persistentSession?: boolean;
	projectTrusted?: boolean;
	seedMessages?: SeedMessage[];
	crashAfterMs?: number;
	extensionSurfaces?: boolean;
}

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

function createFixedSessionFile(sessionDir: string, cwd: string, id: string, suffix: string): string {
	mkdirSync(sessionDir, { recursive: true });
	const path = join(sessionDir, `2023-11-14T22-13-20-000Z_${suffix}.jsonl`);
	writeFileSync(
		path,
		`${JSON.stringify({
			type: "session",
			version: 3,
			id,
			timestamp: "2023-11-14T22:13:20.000Z",
			cwd,
		})}\n`,
		"utf8",
	);
	return path;
}

function appendSeedMessages(session: SessionManager, messages: readonly SeedMessage[]): void {
	for (const [index, message] of messages.entries()) {
		if (message.role === "user") {
			session.appendMessage({
				role: "user",
				content: message.text,
				timestamp: 1_700_000_000_000 + index,
			});
		} else {
			const assistant = fauxAssistantMessage(message.text, {
					timestamp: 1_700_000_000_000 + index,
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

function createSessionManager(cwd: string, sessionDir: string, scenario: Scenario): SessionManager {
	const setup = scenario.setup ?? {};
	if (!setup.persistentSession) {
		const session = SessionManager.inMemory(cwd, { id: "render-session" });
		appendSeedMessages(session, setup.seedMessages ?? []);
		return session;
	}

	const currentPath = createFixedSessionFile(sessionDir, cwd, "render-session", "render-session");
	const session = SessionManager.open(currentPath, sessionDir, cwd);
	appendSeedMessages(session, setup.seedMessages ?? []);

	const otherPath = createFixedSessionFile(sessionDir, cwd, "other-session", "other-session");
	const other = SessionManager.open(otherPath, sessionDir, cwd);
	appendSeedMessages(other, [
		{ role: "user", text: "other session question" },
		{ role: "assistant", text: "other session answer" },
	]);
	return session;
}

async function registerComparisonProviders(modelRuntime: ModelRuntime, scenario: Scenario): Promise<void> {
	if (["overlays-core", "overlays-secondary"].includes(scenario.id)) {
		modelRuntime.registerProvider("other", {
			name: "Other Provider",
			baseUrl: "https://render.invalid/v1",
			apiKey: "render-other-key",
			api: "openai-completions",
			models: [
				{
					id: "other-1",
					name: "Other Model",
					reasoning: false,
					input: ["text"],
					cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
					contextWindow: 64_000,
					maxTokens: 8_192,
				},
			],
		});
	}

	if (scenario.id.startsWith("overlays-auth") || scenario.id === "overlays-logout") {
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
	const model = faux.getModel();
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
			noExtensions: true,
			noSkills: true,
			noPromptTemplates: true,
			noThemes: true,
			noContextFiles: true,
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
				tools: ["read", "bash", "edit", "write", "grep", "find", "ls"],
				scopedModels:
					["overlays-core", "overlays-secondary"].includes(scenario.id) && otherModel
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
	const mode = new InteractiveMode(runtime, { verbose: false, alt: false });
	try {
		await mode.init();
		const readyPath = process.env.RENDER_DIFF_READY_PATH;
		if (readyPath) writeFileSync(readyPath, "ready\n", { encoding: "utf8" });
		if (scenario.setup?.crashAfterMs !== undefined) {
			setTimeout(() => {
				throw new Error("render-diff crash sentinel");
			}, scenario.setup.crashAfterMs);
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
		await mode.run();
	} finally {
		mode.stop();
		await runtime.dispose();
		faux.unregister();
	}
}

void main().catch((error: unknown) => {
	process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
	process.exit(1);
});
