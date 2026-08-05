import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { Type } from "typebox";
import {
	fauxAssistantMessage,
	fauxToolCall,
	registerFauxProvider,
} from "@earendil-works/pi-ai/compat";
import { AuthStorage } from "./src/core/auth-storage.ts";
import type { AgentSessionRuntime } from "./src/core/agent-session-runtime.ts";
import { ModelRuntime } from "./src/core/model-runtime.ts";
import { DefaultResourceLoader } from "./src/core/resource-loader.ts";
import { SessionManager } from "./src/core/session-manager.ts";
import { SettingsManager } from "./src/core/settings-manager.ts";
import { createAgentSession, type ToolDefinition } from "./src/core/sdk.ts";
import { runPrintMode } from "./src/modes/print-mode.ts";
import { runRpcMode } from "./src/modes/rpc/rpc-mode.ts";

type JsonObject = Record<string, unknown>;

interface ResponseBlock {
	type: "text" | "toolCall";
	text?: string;
	name?: string;
	id?: string;
	arguments?: JsonObject;
}

interface ResponseSpec {
	content: ResponseBlock[];
	stopReason?: "stop" | "toolUse" | "error" | "aborted";
	errorMessage?: string;
}

interface SeedMessage {
	role: "user" | "assistant";
	text: string;
}

interface Scenario {
	name: string;
	action: string;
	prompt: string;
	responses: ResponseSpec[];
	seedMessages?: SeedMessage[];
	contextWindow?: number;
	retry?: { enabled: boolean; maxRetries: number; baseDelayMs: number };
	compaction?: { reserveTokens: number; keepRecentTokens: number };
	stream?: { tokensPerSecond?: number; tokenSize?: number };
}

const FIXED_TIMESTAMP = 1_700_000_000_000;

function loadScenario(path: string, name: string): Scenario {
	const manifest = JSON.parse(readFileSync(path, "utf8")) as { scenarios: Scenario[] };
	const scenario = manifest.scenarios.find((candidate) => candidate.name === name);
	if (!scenario) throw new Error(`Unknown event-diff scenario: ${name}`);
	return scenario;
}

function responseFromSpec(spec: ResponseSpec) {
	const content = spec.content.map((block) => {
		if (block.type === "text") return { type: "text" as const, text: block.text ?? "" };
		return fauxToolCall(block.name ?? "", block.arguments ?? {}, { id: block.id });
	});
	return fauxAssistantMessage(content, {
		stopReason: spec.stopReason,
		errorMessage: spec.errorMessage,
		responseId: "event-diff-response",
		timestamp: FIXED_TIMESTAMP,
	});
}

function appendSeedMessages(session: SessionManager, messages: readonly SeedMessage[]): void {
	for (const [index, message] of messages.entries()) {
		if (message.role === "user") {
			session.appendMessage({ role: "user", content: message.text, timestamp: FIXED_TIMESTAMP + index });
		} else {
			session.appendMessage(
				fauxAssistantMessage(message.text, {
					responseId: `event-seed-${index}`,
					timestamp: FIXED_TIMESTAMP + index,
				}),
			);
		}
	}
}

function fixtureTool(): ToolDefinition {
	return {
		name: "fixture_fail",
		label: "Fixture Fail",
		description: "Deterministically fails for event differential coverage.",
		parameters: Type.Object({ value: Type.String() }),
		execute: async () => {
			throw new Error("fixture tool failure");
		},
	};
}

function writeSidecar(path: string, count: number): void {
	writeFileSync(path, `${JSON.stringify({ toolCallErrorHooks: count })}\n`, "utf8");
}

async function main(): Promise<void> {
	const [manifestPath, scenarioName, mode, cwd, agentDir, _sessionDir, sidecarPath] = process.argv.slice(2);
	if (!manifestPath || !scenarioName || !mode || !cwd || !agentDir || !sidecarPath) {
		throw new Error("usage: pi-driver.ts MANIFEST SCENARIO MODE CWD AGENT_DIR SESSION_DIR SIDECAR");
	}
	const scenario = loadScenario(manifestPath, scenarioName);
	writeSidecar(sidecarPath, 0);
	process.env.PI_OFFLINE = "1";
	const originalNow = Date.now;
	Date.now = () => FIXED_TIMESTAMP;

	const tokenSize = scenario.stream?.tokenSize ?? 4096;
	const faux = registerFauxProvider({
		api: "event-diff-faux",
		provider: "faux",
		tokensPerSecond: scenario.stream?.tokensPerSecond ?? 0,
		tokenSize: { min: tokenSize, max: tokenSize },
		models: [
			{
				id: "faux-1",
				name: "Faux Model",
				reasoning: false,
				contextWindow: scenario.contextWindow ?? 128_000,
				maxTokens: 16_384,
			},
		],
	});
	faux.setResponses(scenario.responses.map(responseFromSpec));

	const authStorage = AuthStorage.inMemory();
	await authStorage.modify("faux", async () => ({ type: "api_key", key: "event-diff-key" }));
	const modelRuntime = await ModelRuntime.create({
		credentials: authStorage,
		modelsPath: resolve(agentDir, "models.json"),
	});
	const model = faux.getModel();
	modelRuntime.registerProvider("faux", {
		baseUrl: model.baseUrl,
		apiKey: "event-diff-key",
		api: model.api,
		models: [
			{
				id: model.id,
				name: model.name,
				api: model.api,
				reasoning: false,
				input: model.input,
				cost: model.cost,
				contextWindow: model.contextWindow,
				maxTokens: model.maxTokens,
				baseUrl: model.baseUrl,
			},
		],
	});
	await modelRuntime.refresh({ allowNetwork: false });
	const settingsManager = SettingsManager.inMemory({
		retry: scenario.retry ?? { enabled: false, maxRetries: 0, baseDelayMs: 0 },
		compaction: {
			enabled: scenario.action.includes("compaction"),
			reserveTokens: scenario.compaction?.reserveTokens ?? 16,
			keepRecentTokens: scenario.compaction?.keepRecentTokens ?? 16,
		},
	});
	const resourceLoader = new DefaultResourceLoader({
		cwd,
		agentDir,
		settingsManager,
		noExtensions: true,
		noSkills: true,
		noPromptTemplates: true,
		noThemes: true,
		noContextFiles: true,
		systemPrompt: "Event differential fixed system prompt.",
	});
	await resourceLoader.reload();
	const sessionManager = SessionManager.inMemory(cwd, { id: "event-diff-session" });
	appendSeedMessages(sessionManager, scenario.seedMessages ?? []);
	const { session } = await createAgentSession({
		cwd,
		agentDir,
		modelRuntime,
		settingsManager,
		resourceLoader,
		sessionManager,
		model,
		thinkingLevel: "off",
		noTools: "all",
		customTools: [fixtureTool()],
		tools: ["fixture_fail"],
	});

	const runtimeHost = {
		session,
		setRebindSession: () => undefined,
		dispose: async () => session.dispose(),
		newSession: async () => {
			throw new Error("event-diff runtime does not support new_session");
		},
		fork: async () => {
			throw new Error("event-diff runtime does not support fork");
		},
		switchSession: async () => {
			throw new Error("event-diff runtime does not support switch_session");
		},
	} as unknown as AgentSessionRuntime;

	if (scenario.action === "abort" && mode === "json") {
		let requested = false;
		session.subscribe((event) => {
			if (
				!requested &&
				event.type === "message_update" &&
				event.assistantMessageEvent.type === "text_delta"
			) {
				requested = true;
				void session.abort();
			}
		});
	}

	try {
		if (mode === "rpc") {
			await runRpcMode(runtimeHost);
		}
		if (scenario.action === "manual-compaction") {
			const header = session.sessionManager.getHeader();
			if (header) process.stdout.write(`${JSON.stringify(header)}\n`);
			const unsubscribe = session.subscribe((event) => {
				process.stdout.write(`${JSON.stringify(event)}\n`);
			});
			await session.compact();
			unsubscribe();
			session.dispose();
			return;
		}
		const status = await runPrintMode(runtimeHost, {
			mode: "json",
			initialMessage: scenario.prompt,
		});
		if (status !== 0 && scenario.action !== "prompt") process.exitCode = status;
	} finally {
		Date.now = originalNow;
		faux.unregister();
	}
}

void main().catch((error: unknown) => {
	process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
	process.exit(1);
});
