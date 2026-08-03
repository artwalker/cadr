import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
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

interface Scenario {
	id: string;
	responses: ResponseSpec[];
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

async function main(): Promise<void> {
	const [manifestPath, scenarioId, cwd, agentDir] = process.argv.slice(2);
	if (!manifestPath || !scenarioId || !cwd || !agentDir) {
		throw new Error("usage: pi-driver.ts MANIFEST SCENARIO CWD AGENT_DIR");
	}

	process.env.PI_OFFLINE = "1";
	const scenario = loadScenario(manifestPath, scenarioId);
	const faux = registerFauxProvider({
		api: "faux",
		provider: "faux",
		tokensPerSecond: 0,
		tokenSize: { min: 4096, max: 4096 },
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
		api: model.api,
		models: [{
			id: model.id,
			name: model.name,
			api: model.api,
			reasoning: true,
			input: model.input,
			cost: model.cost,
			contextWindow: model.contextWindow,
			maxTokens: model.maxTokens,
			baseUrl: model.baseUrl,
		}],
	});

	const settingsManager = SettingsManager.inMemory({
		theme: "dark",
		quietStartup: false,
		showHardwareCursor: false,
		terminal: { showTerminalProgress: false },
		collapseChangelog: true,
	});
	const runtimeOptions = {
		agentDir,
		modelRuntime,
		settingsManager,
		model,
		resourceLoaderOptions: {
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
			})),
			services,
			diagnostics: services.diagnostics,
		};
	};
	const runtime = await createAgentSessionRuntime(createRuntime, {
		cwd,
		agentDir,
		sessionManager: SessionManager.inMemory(cwd),
	});

	initTheme("dark", false);
	const mode = new InteractiveMode(runtime, { verbose: true, alt: false });
	try {
		await mode.init();
		const readyPath = process.env.RENDER_DIFF_READY_PATH;
		if (readyPath) writeFileSync(readyPath, "ready\n", { encoding: "utf8" });
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
