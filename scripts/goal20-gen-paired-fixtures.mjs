#!/usr/bin/env node

// Goal 20 Part H fixture generator.
//
// Emits the byte-identical inputs that both sides of every paired path
// consume.  The generator is deterministic: no clocks, no randomness, no
// host paths.  Regenerating on any machine must reproduce the checked-in
// bytes, which is what makes "same fixture bytes" checkable rather than
// asserted.
//
// usage: node scripts/goal20-gen-paired-fixtures.mjs [--check]
//
// --check re-derives the bytes and fails if the checked-in files differ.

import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { crc32 } from "node:zlib";

const projectDirectory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const fixtureDirectory = path.join(projectDirectory, "test/fixtures/goal20-paired-paths");
const checkOnly = process.argv.includes("--check");

// A synthetic cwd keeps the session fixture free of the generating host's
// paths, so the same bytes load on every machine.
const FIXTURE_CWD = "/goal20-paired-paths";
// The write pair needs a cwd that exists on disk: cadr canonicalises a new
// session's cwd through TRUENAME, so a synthetic path cannot be used there.
// Both benches create this directory and pass the resolved path, which keeps
// the header bytes they write identical.
const JOURNAL_CWD = "/tmp/goal20-part-h-journal-cwd";
const SESSION_ID = "019f0000-0000-7000-8000-00000000cadr";
const SESSION_TIMESTAMP = "2026-08-14T00:00:00.000Z";
const SESSION_ENTRY_COUNT = 512;
const PROVIDER_MESSAGE_COUNT = 96;
const SSE_TEXT_DELTA_COUNT = 384;

const EPOCH_MS = Date.UTC(2026, 7, 14, 0, 0, 0, 0);

// Session *entry* timestamps are ISO-8601 strings; the *message* timestamps
// nested inside a message entry are unix milliseconds.  Both loaders enforce
// that split, so the fixture keeps the two helpers distinct.
function isoTimestamp(index) {
	return new Date(EPOCH_MS + index * 1000).toISOString();
}

function millisecondTimestamp(index) {
	return EPOCH_MS + index * 1000;
}

function entryId(index) {
	return `e${String(index).padStart(5, "0")}`;
}

// ---------------------------------------------------------------------------
// Session journal fixture (pairs 3 and 4)
// ---------------------------------------------------------------------------

function textBlock(text) {
	return { type: "text", text };
}

function usage(input, output) {
	return {
		input,
		output,
		cacheRead: 0,
		cacheWrite: 0,
		totalTokens: input + output,
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
	};
}

function userMessage(index) {
	return {
		role: "user",
		content: [
			textBlock(
				`Request ${index}: explain **cache behavior** for 中文输入 and emoji 🚀 without changing observable output.`,
			),
		],
		timestamp: millisecondTimestamp(index),
	};
}

function assistantMessage(index) {
	return {
		role: "assistant",
		content: [
			{ type: "thinking", thinking: `Considering entry ${index} across a wrapped paragraph.` },
			textBlock(
				`Entry ${index} keeps markdown, \`inline code\`, and a wrapped paragraph stable across reloads.`,
			),
		],
		api: "openai-completions",
		provider: "goal20faux",
		model: "goal20-paired-1",
		usage: usage(1200 + index, 64 + (index % 17)),
		stopReason: "stop",
		timestamp: millisecondTimestamp(index),
	};
}

function toolCallMessage(index) {
	return {
		role: "assistant",
		content: [
			{
				type: "toolCall",
				id: `call_${entryId(index)}`,
				name: "read",
				arguments: { path: `docs/example-${index}.md`, offset: 1, limit: 4 },
			},
		],
		api: "openai-completions",
		provider: "goal20faux",
		model: "goal20-paired-1",
		usage: usage(1300 + index, 32),
		stopReason: "toolUse",
		timestamp: millisecondTimestamp(index),
	};
}

function toolResultMessage(index) {
	return {
		role: "toolResult",
		toolCallId: `call_${entryId(index - 1)}`,
		toolName: "read",
		content: [textBlock("alpha\nbeta\ngamma\ndelta")],
		isError: false,
		timestamp: millisecondTimestamp(index),
	};
}

function buildSessionFileEntries() {
	const fileEntries = [
		{
			type: "session",
			version: 3,
			id: SESSION_ID,
			timestamp: SESSION_TIMESTAMP,
			cwd: FIXTURE_CWD,
		},
	];
	let parentId = null;
	// The compaction boundary must land inside the walked path so that both
	// sides exercise the compaction-aware branch of the entry walk rather
	// than the trivial root-to-leaf case.
	const compactionIndex = Math.floor(SESSION_ENTRY_COUNT / 2);
	const firstKeptIndex = compactionIndex - 64;
	for (let index = 0; index < SESSION_ENTRY_COUNT; index += 1) {
		const id = entryId(index);
		const timestamp = isoTimestamp(index);
		const base = { id, parentId, timestamp };
		let entry;
		if (index === compactionIndex) {
			entry = {
				type: "compaction",
				...base,
				summary: `Compacted the first ${firstKeptIndex} entries into a single summary.`,
				firstKeptEntryId: entryId(firstKeptIndex),
				tokensBefore: 128000,
				usage: usage(4096, 512),
			};
		} else if (index % 64 === 17) {
			entry = { type: "model_change", ...base, provider: "goal20faux", modelId: "goal20-paired-1" };
		} else if (index % 64 === 18) {
			entry = { type: "thinking_level_change", ...base, thinkingLevel: "medium" };
		} else if (index % 64 === 19) {
			entry = {
				type: "custom_message",
				...base,
				customType: "goal20-note",
				content: [textBlock(`Injected context note ${index}.`)],
				display: true,
			};
		} else if (index % 64 === 20) {
			entry = { type: "custom", ...base, customType: "goal20-state", data: { cursor: index } };
		} else if (index % 4 === 0) {
			entry = { type: "message", ...base, message: userMessage(index) };
		} else if (index % 4 === 1) {
			entry = { type: "message", ...base, message: assistantMessage(index) };
		} else if (index % 4 === 2) {
			entry = { type: "message", ...base, message: toolCallMessage(index) };
		} else {
			entry = { type: "message", ...base, message: toolResultMessage(index) };
		}
		fileEntries.push(entry);
		parentId = id;
	}
	// Trailing metadata entries: a label plus a display name, both of which
	// the loaders index separately from the message chain.
	fileEntries.push({
		type: "label",
		id: entryId(SESSION_ENTRY_COUNT),
		parentId,
		timestamp: isoTimestamp(SESSION_ENTRY_COUNT),
		targetId: entryId(SESSION_ENTRY_COUNT - 1),
		label: "goal20-leaf",
	});
	fileEntries.push({
		type: "session_info",
		id: entryId(SESSION_ENTRY_COUNT + 1),
		parentId: entryId(SESSION_ENTRY_COUNT),
		timestamp: isoTimestamp(SESSION_ENTRY_COUNT + 1),
		name: "goal20 paired paths",
	});
	return fileEntries;
}

// ---------------------------------------------------------------------------
// Provider fixtures (pair 2)
// ---------------------------------------------------------------------------

function buildProviderContext() {
	const messages = [];
	for (let index = 0; index < PROVIDER_MESSAGE_COUNT; index += 1) {
		if (index % 4 === 0) {
			messages.push({
				role: "user",
				content: [textBlock(`Turn ${index}: 请解释 caching 与 emoji 🚀。`)],
				timestamp: millisecondTimestamp(index),
			});
		} else if (index % 4 === 1) {
			messages.push({
				role: "assistant",
				content: [
					{ type: "thinking", thinking: `Reasoning about turn ${index}.` },
					textBlock(`Answer ${index} with \`inline code\` and a wrapped paragraph.`),
				],
				api: "openai-completions",
				provider: "goal20faux",
				model: "goal20-paired-1",
				usage: usage(900 + index, 48),
				stopReason: "stop",
				timestamp: millisecondTimestamp(index),
			});
		} else if (index % 4 === 2) {
			messages.push({
				role: "assistant",
				content: [
					{
						type: "toolCall",
						id: `call_p${String(index).padStart(4, "0")}`,
						name: "read",
						arguments: { path: `src/example-${index}.ts`, offset: 1, limit: 40 },
					},
				],
				api: "openai-completions",
				provider: "goal20faux",
				model: "goal20-paired-1",
				usage: usage(950 + index, 24),
				stopReason: "toolUse",
				timestamp: millisecondTimestamp(index),
			});
		} else {
			messages.push({
				role: "toolResult",
				toolCallId: `call_p${String(index - 1).padStart(4, "0")}`,
				toolName: "read",
				content: [textBlock("export const alpha = 1;\nexport const beta = 2;")],
				isError: false,
				timestamp: millisecondTimestamp(index),
			});
		}
	}
	return {
		systemPrompt:
			"You are a paired-path benchmark fixture. Answer briefly and never change observable output.",
		messages,
		tools: [
			{
				name: "read",
				description: "Read a file from disk with an optional line window.",
				parameters: {
					type: "object",
					properties: {
						path: { type: "string", description: "Path to read." },
						offset: { type: "number", description: "First line, 1-based." },
						limit: { type: "number", description: "Line count." },
					},
					required: ["path"],
				},
			},
			{
				name: "bash",
				description: "Run a shell command and return its combined output.",
				parameters: {
					type: "object",
					properties: {
						command: { type: "string", description: "Command to run." },
						timeout: { type: "number", description: "Timeout in milliseconds." },
					},
					required: ["command"],
				},
			},
		],
	};
}

function buildGoogleSseFixture() {
	const lines = [];
	const push = (payload) => {
		lines.push(`data: ${JSON.stringify(payload)}`, "");
	};
	const usage = (output) => ({
		promptTokenCount: 4096,
		candidatesTokenCount: output,
		totalTokenCount: 4096 + output,
	});
	for (let index = 0; index < SSE_TEXT_DELTA_COUNT; index += 1) {
		push({
			candidates: [
				{
					content: {
						parts: [
							{
								text: index % 8 === 7 ? `chunk-${index} 中文 🚀 ` : `chunk-${index} `,
							},
						],
						role: "model",
					},
					index: 0,
				},
			],
			usageMetadata: usage(1),
			responseId: "goal20-google",
		});
	}
	push({
		candidates: [
			{
				content: {
					parts: [
						{
							functionCall: {
								name: "read",
								args: { path: "docs/example.md", offset: 1, limit: 4 },
								id: "call_goal20_read",
							},
						},
					],
					role: "model",
				},
				index: 0,
			},
		],
		usageMetadata: usage(8),
		responseId: "goal20-google",
	});
	push({
		candidates: [
			{
				content: { parts: [{ text: "" }], role: "model" },
				finishReason: "STOP",
				index: 0,
			},
		],
		usageMetadata: usage(512),
		responseId: "goal20-google",
	});
	return `${lines.join("\n")}\n`;
}

function u32be(value) {
	const buffer = Buffer.alloc(4);
	buffer.writeUInt32BE(value >>> 0);
	return buffer;
}

function awsEventStreamHeader(name, value) {
	const nameBytes = Buffer.from(name, "utf8");
	const valueBytes = Buffer.from(value, "utf8");
	return Buffer.concat([
		Buffer.from([nameBytes.length]),
		nameBytes,
		Buffer.from([7]),
		Buffer.from([(valueBytes.length >> 8) & 0xff, valueBytes.length & 0xff]),
		valueBytes,
	]);
}

function awsEventStreamFrame(eventType, payload) {
	const headers = Buffer.concat([
		awsEventStreamHeader(":message-type", "event"),
		awsEventStreamHeader(":event-type", eventType),
		awsEventStreamHeader(":content-type", "application/json"),
	]);
	const payloadBytes = Buffer.from(JSON.stringify(payload), "utf8");
	const totalLength = 16 + headers.length + payloadBytes.length;
	const preludeBody = Buffer.concat([u32be(totalLength), u32be(headers.length)]);
	const prelude = Buffer.concat([preludeBody, u32be(crc32(preludeBody))]);
	const withoutMessageCrc = Buffer.concat([prelude, headers, payloadBytes]);
	return Buffer.concat([withoutMessageCrc, u32be(crc32(withoutMessageCrc))]);
}

function buildBedrockEventStreamFixture() {
	const frames = [];
	frames.push(awsEventStreamFrame("messageStart", { role: "assistant" }));
	for (let index = 0; index < SSE_TEXT_DELTA_COUNT; index += 1) {
		const text = index % 8 === 7 ? `chunk-${index} 中文 🚀 ` : `chunk-${index} `;
		frames.push(
			awsEventStreamFrame("contentBlockDelta", {
				contentBlockIndex: 0,
				delta: { text },
			}),
		);
	}
	frames.push(awsEventStreamFrame("contentBlockStop", { contentBlockIndex: 0 }));
	frames.push(
		awsEventStreamFrame("contentBlockStart", {
			contentBlockIndex: 1,
			start: {
				toolUse: { toolUseId: "call_goal20_read", name: "read" },
			},
		}),
	);
	frames.push(
		awsEventStreamFrame("contentBlockDelta", {
			contentBlockIndex: 1,
			delta: {
				toolUse: {
					input: JSON.stringify({ path: "docs/example.md", offset: 1, limit: 4 }),
				},
			},
		}),
	);
	frames.push(awsEventStreamFrame("contentBlockStop", { contentBlockIndex: 1 }));
	frames.push(awsEventStreamFrame("messageStop", { stopReason: "tool_use" }));
	frames.push(
		awsEventStreamFrame("metadata", {
			usage: {
				inputTokens: 4096,
				outputTokens: 512,
				totalTokens: 4608,
			},
		}),
	);
	return Buffer.concat(frames);
}

function buildAnthropicSseFixture() {
	const lines = [];
	const event = (name, payload) => {
		lines.push(`event: ${name}`, `data: ${JSON.stringify(payload)}`, "");
	};
	event("message_start", {
		type: "message_start",
		message: {
			model: "goal20-paired-1",
			id: "msg_goal20",
			type: "message",
			role: "assistant",
			content: [],
			stop_reason: null,
			stop_sequence: null,
			usage: { input_tokens: 4096, output_tokens: 1 },
		},
	});
	event("content_block_start", {
		type: "content_block_start",
		index: 0,
		content_block: { type: "text", text: "" },
	});
	for (let index = 0; index < SSE_TEXT_DELTA_COUNT; index += 1) {
		event("content_block_delta", {
			type: "content_block_delta",
			index: 0,
			delta: {
				type: "text_delta",
				text: index % 8 === 7 ? `chunk-${index} 中文 🚀 ` : `chunk-${index} `,
			},
		});
	}
	event("content_block_stop", { type: "content_block_stop", index: 0 });
	event("content_block_start", {
		type: "content_block_start",
		index: 1,
		content_block: {
			type: "tool_use",
			id: "toolu_goal20_read",
			name: "read",
			input: {},
		},
	});
	for (const fragment of ['{"path":', '"docs/', 'example.md"', ',"offset":1', ',"limit":4}']) {
		event("content_block_delta", {
			type: "content_block_delta",
			index: 1,
			delta: { type: "input_json_delta", partial_json: fragment },
		});
	}
	event("content_block_stop", { type: "content_block_stop", index: 1 });
	event("message_delta", {
		type: "message_delta",
		delta: { stop_reason: "tool_use", stop_sequence: null },
		usage: { output_tokens: 512 },
	});
	event("message_stop", { type: "message_stop" });
	return `${lines.join("\n")}\n`;
}

function buildSseFixture() {
	const lines = [];
	const push = (payload) => {
		lines.push(`data: ${JSON.stringify(payload)}`, "");
	};
	const base = {
		id: "chatcmpl-goal20",
		object: "chat.completion.chunk",
		created: 1786665600,
		model: "goal20-paired-1",
	};
	push({ ...base, choices: [{ index: 0, delta: { role: "assistant", content: "" }, finish_reason: null }] });
	for (let index = 0; index < SSE_TEXT_DELTA_COUNT; index += 1) {
		push({
			...base,
			choices: [
				{
					index: 0,
					delta: { content: index % 8 === 7 ? `chunk-${index} 中文 🚀 ` : `chunk-${index} ` },
					finish_reason: null,
				},
			],
		});
	}
	push({
		...base,
		choices: [
			{
				index: 0,
				delta: {
					tool_calls: [
						{
							index: 0,
							id: "call_goal20_read",
							type: "function",
							function: { name: "read", arguments: "" },
						},
					],
				},
				finish_reason: null,
			},
		],
	});
	for (const fragment of ['{"path":', '"docs/', 'example.md"', ',"offset":1', ',"limit":4}']) {
		push({
			...base,
			choices: [
				{
					index: 0,
					delta: { tool_calls: [{ index: 0, function: { arguments: fragment } }] },
					finish_reason: null,
				},
			],
		});
	}
	push({ ...base, choices: [{ index: 0, delta: {}, finish_reason: "tool_calls" }] });
	push({
		...base,
		choices: [],
		usage: { prompt_tokens: 4096, completion_tokens: 512, total_tokens: 4608 },
	});
	lines.push("data: [DONE]", "");
	return `${lines.join("\n")}\n`;
}

// ---------------------------------------------------------------------------
// CLI fixtures (pair 1)
// ---------------------------------------------------------------------------

function buildModelsJson() {
	const models = [];
	for (let index = 0; index < 24; index += 1) {
		models.push({
			id: `goal20-paired-${index}`,
			name: `Goal 20 Paired ${index}`,
			reasoning: index % 3 === 0,
			input: index % 2 === 0 ? ["text", "image"] : ["text"],
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
			contextWindow: 128000 + index * 1000,
			maxTokens: 16384 + index * 16,
		});
	}
	return {
		providers: {
			goal20faux: {
				name: "Goal 20 Faux",
				api: "openai-completions",
				baseUrl: "http://127.0.0.1:1/v1",
				models,
			},
		},
	};
}

function buildAuthJson() {
	return {
		goal20faux: { type: "api_key", key: "goal20-paired-paths-not-a-real-key" },
	};
}

function buildSettingsGlobal() {
	return {
		theme: "dark",
		defaultProvider: "anthropic",
		defaultModel: "claude-sonnet-4-5",
		defaultProjectTrust: "ask",
		compaction: {
			enabled: true,
			reserveTokens: 16384,
			keepRecentTokens: 20000,
		},
		retry: {
			enabled: true,
			maxRetries: 3,
			baseDelayMs: 2000,
		},
	};
}

function buildSettingsProject() {
	return {
		theme: "light",
		compaction: {
			reserveTokens: 8192,
		},
		httpIdleTimeoutMs: 42,
	};
}

function buildCliArgv() {
	return {
		list_models: ["--list-models", "goal20"],
		parse: [
			"--provider",
			"goal20faux",
			"--model",
			"goal20-paired-3",
			"--thinking",
			"medium",
			"--append-system-prompt",
			"be terse",
			"--append-system-prompt",
			"cite files",
			"--tools",
			"read,bash,edit",
			"--exclude-tools",
			"web_search,fetch",
			"--session-dir",
			"/goal20-paired-paths/sessions",
			"--mode",
			"json",
			"--no-themes",
			"--no-context-files",
			"--verbose",
			"--list-models",
			"goal20",
			"explain the paired path benchmark",
			"@docs/performance.md",
		],
	};
}

// ---------------------------------------------------------------------------

const artifacts = new Map([
	[
		"session.jsonl",
		`${buildSessionFileEntries()
			.map((entry) => JSON.stringify(entry))
			.join("\n")}\n`,
	],
	["provider-context.json", `${JSON.stringify(buildProviderContext(), null, "\t")}\n`],
	["openai-completions.sse", buildSseFixture()],
	["anthropic-messages.sse", buildAnthropicSseFixture()],
	["google-generative-ai.sse", buildGoogleSseFixture()],
	["bedrock-converse-stream.bin", buildBedrockEventStreamFixture()],
	["settings-global.json", `${JSON.stringify(buildSettingsGlobal(), null, "\t")}\n`],
	["settings-project.json", `${JSON.stringify(buildSettingsProject(), null, "\t")}\n`],
	["models.json", `${JSON.stringify(buildModelsJson(), null, "\t")}\n`],
	["auth.json", `${JSON.stringify(buildAuthJson(), null, "\t")}\n`],
	["cli-argv.json", `${JSON.stringify(buildCliArgv(), null, "\t")}\n`],
]);

mkdirSync(fixtureDirectory, { recursive: true });

const digests = {};
const mismatches = [];
for (const [name, text] of artifacts) {
	const target = path.join(fixtureDirectory, name);
	const bytes = Buffer.isBuffer(text) ? text : Buffer.from(text, "utf8");
	digests[name] = createHash("sha256").update(bytes).digest("hex");
	if (checkOnly) {
		let current;
		try {
			current = readFileSync(target);
		} catch {
			mismatches.push(`${name}: missing`);
			continue;
		}
		if (!current.equals(bytes)) mismatches.push(`${name}: differs from generated bytes`);
	} else {
		writeFileSync(target, bytes);
	}
}

const manifest = `${JSON.stringify(
	{
		kind: "goal20-part-h-fixture-manifest",
		generator: "scripts/goal20-gen-paired-fixtures.mjs",
		parameters: {
			session_entry_count: SESSION_ENTRY_COUNT,
			provider_message_count: PROVIDER_MESSAGE_COUNT,
			sse_text_delta_count: SSE_TEXT_DELTA_COUNT,
			fixture_cwd: FIXTURE_CWD,
			journal_cwd: JOURNAL_CWD,
			session_id: SESSION_ID,
		},
		sha256: digests,
	},
	null,
	"\t",
)}\n`;
const manifestPath = path.join(fixtureDirectory, "manifest.json");
if (checkOnly) {
	let current;
	try {
		current = readFileSync(manifestPath, "utf8");
	} catch {
		mismatches.push("manifest.json: missing");
	}
	if (current !== undefined && current !== manifest) {
		mismatches.push("manifest.json: differs from generated bytes");
	}
	if (mismatches.length > 0) {
		process.stderr.write(`goal20 fixture drift:\n${mismatches.map((line) => `  ${line}`).join("\n")}\n`);
		process.exit(1);
	}
	process.stderr.write("goal20 fixtures match the generator\n");
} else {
	writeFileSync(manifestPath, manifest, "utf8");
	process.stderr.write(`goal20 fixtures written to ${fixtureDirectory}\n`);
}
