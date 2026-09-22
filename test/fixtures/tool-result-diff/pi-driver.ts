import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
	type AssistantMessage,
	type AssistantMessageEvent,
	EventStream,
	type Message,
	type Model,
	type ToolResultMessage,
} from "@earendil-works/pi-ai";
import { agentLoop } from "./packages/agent/src/agent-loop.ts";
import type {
	AgentContext,
	AgentLoopConfig,
	AgentMessage,
} from "./packages/agent/src/types.ts";
import { createAllTools } from "./packages/coding-agent/src/core/tools/index.ts";
import { createReadTool } from "./packages/coding-agent/src/core/tools/read.ts";

type Scenario = {
	id: string;
	tool: string;
	arguments: Record<string, unknown>;
	contract?: string;
};

class FixedAssistantStream extends EventStream<AssistantMessageEvent, AssistantMessage> {
	constructor() {
		super(
			(event) => event.type === "done" || event.type === "error",
			(event) => {
				if (event.type === "done") return event.message;
				if (event.type === "error") return event.error;
				throw new Error("unexpected fixed stream event");
			},
		);
	}
}

function model(): Model<"openai-responses"> {
	return {
		id: "tool-result-diff",
		name: "tool-result-diff",
		api: "openai-responses",
		provider: "fixed",
		baseUrl: "https://invalid.example",
		reasoning: false,
		input: ["text"],
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		contextWindow: 8192,
		maxTokens: 2048,
	};
}

function usage() {
	return {
		input: 0,
		output: 0,
		cacheRead: 0,
		cacheWrite: 0,
		totalTokens: 0,
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
	};
}

function assistant(scenario: Scenario): AssistantMessage {
	return {
		role: "assistant",
		content: [
			{
				type: "toolCall",
				id: `call-${scenario.id}`,
				name: scenario.tool,
				arguments: scenario.arguments,
			},
		],
		api: "openai-responses",
		provider: "fixed",
		model: "tool-result-diff",
		usage: usage(),
		stopReason: "toolUse",
		timestamp: 1_700_000_000_000,
	};
}

function encodeText(text: string): string {
	return Buffer.from(text, "utf8").toString("base64url");
}

async function serializeResult(scenario: Scenario, result: ToolResultMessage) {
	const details = result.details as { fullOutputPath?: unknown } | undefined;
	const fullOutputPath = details?.fullOutputPath;
	const fullOutputSha256 =
		typeof fullOutputPath === "string"
			? createHash("sha256").update(await readFile(fullOutputPath)).digest("hex")
			: undefined;
	return {
		scenarioId: scenario.id,
		isError: result.isError,
		content: result.content.map((block) => {
			if (block.type === "text") {
				return { type: "text", utf8Base64: encodeText(block.text) };
			}
			if (block.type === "image") {
				return {
					type: "image",
					mimeType: block.mimeType,
					dataBase64: block.data,
				};
			}
			throw new Error(`unsupported pi tool-result content block: ${block.type}`);
		}),
		...(typeof fullOutputPath === "string"
			? {
					typedFullOutputPath: fullOutputPath,
					typedFullOutputSha256: fullOutputSha256,
				}
			: {}),
	};
}

async function runScenario(workspace: string, scenario: Scenario) {
	const cwd = join(workspace, scenario.id);
	const allTools = createAllTools(cwd);
	if (scenario.contract === "permission-denied") {
		const path = join(cwd, String(scenario.arguments.path));
		allTools.read = createReadTool(cwd, {
			operations: {
				access: async () => {
					throw new Error(`EACCES: permission denied, access '${path}'`);
				},
				readFile: async () => Buffer.alloc(0),
			},
		});
	}
	const tools = Object.values(allTools);
	const context: AgentContext = {
		systemPrompt: "fixed tool-result differential",
		messages: [],
		tools,
	};
	const config: AgentLoopConfig = {
		model: model(),
		convertToLlm: (messages: AgentMessage[]) =>
			messages.filter(
				(message) =>
					message.role === "user" ||
					message.role === "assistant" ||
					message.role === "toolResult",
			) as Message[],
		finishTurn: async ({ toolResults }) =>
			toolResults.length > 0 ? { action: "end" as const } : undefined,
	};
	const response = assistant(scenario);
	const stream = agentLoop(
		[{ role: "user", content: "execute fixed tool call", timestamp: 1_700_000_000_000 }],
		context,
		config,
		undefined,
		() => {
			const fixed = new FixedAssistantStream();
			queueMicrotask(() => {
				fixed.push({ type: "done", reason: "toolUse", message: response });
			});
			return fixed;
		},
	);
	for await (const _event of stream) {
		// Consumption is required for the real agent event path to settle.
	}
	const messages = await stream.result();
	const result = messages.find(
		(message): message is ToolResultMessage => message.role === "toolResult",
	);
	if (!result) throw new Error(`pi produced no tool result for ${scenario.id}`);
	return serializeResult(scenario, result);
}

async function main() {
	const [baseline, manifestPath, workspace, outputPath] = process.argv.slice(2);
	if (!baseline || !manifestPath || !workspace || !outputPath) {
		throw new Error("usage: pi-driver.ts BASELINE MANIFEST WORKSPACE OUTPUT");
	}
	const manifest = JSON.parse(await readFile(manifestPath, "utf8")) as {
		baselineCommit: string;
		scenarios: Scenario[];
	};
	const results = [];
	for (const scenario of manifest.scenarios) {
		results.push(await runScenario(workspace, scenario));
	}
	await writeFile(
		outputPath,
		JSON.stringify({
			implementation: "pi",
			baselineCommit: manifest.baselineCommit,
			baselinePath: baseline,
			node: process.version,
			results,
		}),
		"utf8",
	);
}

void main().catch((error: unknown) => {
	console.error(error);
	process.exitCode = 1;
});
