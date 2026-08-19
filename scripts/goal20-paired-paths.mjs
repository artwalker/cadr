#!/usr/bin/env node

// Goal 20 Part H: pi side of the non-TUI paired benchmarks.
//
// Goal 11 paired cadr against pi on three TUI-input ratios only (mouse
// drag, wheel, continuous alt input).  Everything outside the renderer had
// zero paired coverage, so "no worse than pi" was unfalsifiable for the
// CLI, provider, agent-session, and storage layers.  This script measures
// the pi half of four such paths; scripts/goal20-paired-paths.lisp measures
// the cadr half over the *same fixture bytes*, and
// scripts/goal20-paired-paths.py pairs them using the existing
// same_machine hostname compare from goal11-performance-gate.py.
//
// Pairs (each one same-input, same-machine, no network):
//   1. cli_dispatch      argv parse, help render, --list-models dispatch
//   2. provider_stream   request assembly + SSE response parse
//   3. session_pipeline  session load + context entry walk
//   4. storage_journal   journal read + journal append
//   5. sqlite_session    SQLite open + read-all + leaf walk
//   6. tool_read         production read vs createReadToolDefinition.execute
//
// usage:
//   node scripts/goal20-paired-paths.mjs BASELINE_WORKTREE [options]
//     --output PATH     write JSON here instead of stdout
//     --samples N        samples per metric (default 5)
//     --warmups N        warmup rounds per metric (default 1)
//     --quick            1 sample, no warmup, reduced repetitions
//
// Run it through the baseline's own tsx so the pi sources load unbuilt.
// BASELINE_WORKTREE is the render-diff cache for the commit pinned in
// BASELINE (/tmp/cadr-render-diff-pi-<short-sha>):
//   "$BASELINE_WORKTREE/node_modules/.bin/tsx" \
//     scripts/goal20-paired-paths.mjs "$BASELINE_WORKTREE"

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
	copyFileSync,
	mkdirSync,
	mkdtempSync,
	readFileSync,
	realpathSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { hostname, tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const projectDirectory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const fixtureDirectory = path.join(projectDirectory, "test/fixtures/goal20-paired-paths");

// The BASELINE anchor file owns the pinned pi commit (goal 18 L2.1);
// scripts/baseline-anchor.py check rejects a literal hash here.
const EXPECTED_REVISION = readFileSync(path.join(projectDirectory, "BASELINE"), "ascii")
	.trim()
	.split(/\s+/)[0];

function parseOptions(argv) {
	const options = {
		samples: 5,
		warmups: 1,
		quick: false,
		output: "-",
		baseline: undefined,
		keepJournal: undefined,
	};
	for (let index = 0; index < argv.length; index += 1) {
		const argument = argv[index];
		if (argument === "--quick") options.quick = true;
		else if (argument === "--samples") options.samples = Number(argv[++index]);
		else if (argument === "--warmups") options.warmups = Number(argv[++index]);
		else if (argument === "--output") options.output = argv[++index];
		else if (argument === "--keep-journal") options.keepJournal = argv[++index];
		else if (argument.startsWith("--")) throw new Error(`unknown option: ${argument}`);
		else if (options.baseline === undefined) options.baseline = argument;
		else throw new Error(`unexpected argument: ${argument}`);
	}
	if (!options.baseline) {
		throw new Error("usage: goal20-paired-paths.mjs BASELINE_WORKTREE [--quick] [--output PATH]");
	}
	if (options.quick) {
		options.samples = 1;
		options.warmups = 0;
	}
	if (!Number.isInteger(options.samples) || options.samples < 1) throw new Error("--samples must be >= 1");
	if (!Number.isInteger(options.warmups) || options.warmups < 0) throw new Error("--warmups must be >= 0");
	return options;
}

const options = parseOptions(process.argv.slice(2));
const baselineDirectory = path.resolve(options.baseline);

// The render-diff baseline cache is an extracted tree, not a git checkout:
// scripts/render-diff.py writes .goal15-render-baseline and separately
// verifies every tracked blob against the commit.  Read that marker rather
// than shelling out to git, and fall back to git only for a real checkout.
function readBaselineRevision(directory) {
	const marker = path.join(directory, ".goal15-render-baseline");
	try {
		return { revision: readFileSync(marker, "utf8").trim(), source: ".goal15-render-baseline" };
	} catch {
		return {
			revision: execFileSync("git", ["-C", directory, "rev-parse", "HEAD"], {
				encoding: "utf8",
			}).trim(),
			source: "git rev-parse HEAD",
		};
	}
}

const { revision, source: revisionSource } = readBaselineRevision(baselineDirectory);
if (revision !== EXPECTED_REVISION) {
	throw new Error(`expected baseline ${EXPECTED_REVISION.slice(0, 9)}, got ${revision}`);
}

// Repetition counts are per metric so that every inner loop lasts long
// enough to clear timer granularity without making the whole run slow.
// The cadr script uses the same table; the pairing gate rejects a run whose
// repetition counts disagree, because a ratio between differently sized
// batches is not a comparison.
const REPETITIONS = {
	"cli_dispatch.argv_parse": 2000,
	"cli_dispatch.help_render": 500,
	"cli_dispatch.list_models_registry": 20,
	"cli_dispatch.list_models_render": 100,
	"provider_stream.stream_roundtrip": 10,
	"session_pipeline.session_load": 3,
	"session_pipeline.context_walk": 50,
	"storage_journal.journal_read": 5,
	"storage_journal.journal_append": 3,
	"sqlite_session.open_walk": 3,
	"tool_read.text_file": 5,
	"tool_grep.context_file": 5,
	"text_truncation.truncate_head": 50,
	"text_truncation.truncate_tail": 50,
	"render_slicing.slice_ansi_clip": 200,
	"render_slicing.slice_plain_clip": 200,
};
const QUICK_DIVISOR = 20;

function repetitionsFor(name) {
	const base = REPETITIONS[name];
	if (base === undefined) throw new Error(`no repetition count for ${name}`);
	return options.quick ? Math.max(1, Math.floor(base / QUICK_DIVISOR)) : base;
}

// ---------------------------------------------------------------------------
// Statistics: same shape as scripts/goal11-bench.lisp / goal11-pi-baseline-bench.mjs
// ---------------------------------------------------------------------------

function median(values) {
	const sorted = [...values].sort((left, right) => left - right);
	const middle = Math.floor(sorted.length / 2);
	return sorted.length % 2 === 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function medianAbsoluteDeviation(values, center) {
	return median(values.map((value) => Math.abs(value - center)));
}

function statistics(name, samplesUs) {
	const center = median(samplesUs);
	return {
		median_us: center,
		mad_us: medianAbsoluteDeviation(samplesUs, center),
		samples_us: samplesUs,
		repetitions: repetitionsFor(name),
	};
}

async function collect(name, prepare) {
	const countPerSample = repetitionsFor(name);
	const run = async () => {
		const operation = await prepare();
		globalThis.gc?.();
		const started = process.hrtime.bigint();
		for (let index = 0; index < countPerSample; index += 1) await operation(index);
		const elapsed = Number(process.hrtime.bigint() - started) / 1000;
		return elapsed / countPerSample;
	};
	for (let index = 0; index < options.warmups; index += 1) await run();
	const samplesUs = [];
	for (let index = 0; index < options.samples; index += 1) samplesUs.push(await run());
	return statistics(name, samplesUs);
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const fixtureNames = [
	"auth.json",
	"cli-argv.json",
	"manifest.json",
	"models.json",
	"openai-completions.sse",
	"provider-context.json",
	"session.jsonl",
];
const fixtureDigests = {};
for (const name of fixtureNames) {
	fixtureDigests[name] = createHash("sha256")
		.update(readFileSync(path.join(fixtureDirectory, name)))
		.digest("hex");
}

const sessionFixturePath = path.join(fixtureDirectory, "session.jsonl");
const sseFixturePath = path.join(fixtureDirectory, "openai-completions.sse");
const cliArgv = JSON.parse(readFileSync(path.join(fixtureDirectory, "cli-argv.json"), "utf8"));
const providerContext = JSON.parse(
	readFileSync(path.join(fixtureDirectory, "provider-context.json"), "utf8"),
);
const fixtureManifest = JSON.parse(readFileSync(path.join(fixtureDirectory, "manifest.json"), "utf8"));

// The write pair's cwd comes from the manifest so both sides read one
// declared value.  cadr resolves a new session's cwd through TRUENAME, so the
// directory has to exist and both sides have to pass the resolved path for
// the header bytes they write to match.
const journalCwd = fixtureManifest.parameters.journal_cwd;
mkdirSync(journalCwd, { recursive: true });
const resolvedJournalCwd = realpathSync(journalCwd);

// A staged agent directory keeps the fixture tree read-only: the model
// runtime writes models-store.json next to models.json.  The staged bytes
// are digested so the pairing report can prove both sides read the same
// models.json and auth.json rather than merely claiming it.
const scratch = mkdtempSync(path.join(tmpdir(), "goal20-pi-paired-"));
const agentDirectory = path.join(scratch, "agent");
mkdirSync(agentDirectory, { recursive: true });
for (const name of ["models.json", "auth.json"]) {
	copyFileSync(path.join(fixtureDirectory, name), path.join(agentDirectory, name));
}
const stagedDigests = {
	"models.json": createHash("sha256")
		.update(readFileSync(path.join(agentDirectory, "models.json")))
		.digest("hex"),
	"auth.json": createHash("sha256")
		.update(readFileSync(path.join(agentDirectory, "auth.json")))
		.digest("hex"),
};

// Provider keys in the operator's environment make extra models "available"
// and would silently change the observed model set from host to host, so the
// fixture auth.json is the only credential either side can see.
const SCRUBBED_ENVIRONMENT_PATTERN = /(^|_)(API_KEY|AUTH_TOKEN|OAUTH_TOKEN|ACCESS_TOKEN)$/;

function scrubProviderEnvironment() {
	const removed = [];
	for (const name of Object.keys(process.env)) {
		if (!SCRUBBED_ENVIRONMENT_PATTERN.test(name)) continue;
		delete process.env[name];
		removed.push(name);
	}
	return removed.sort();
}

const scrubbedEnvironment = scrubProviderEnvironment();

// ---------------------------------------------------------------------------
// pi module loading
// ---------------------------------------------------------------------------

const moduleUrl = (relativePath) => pathToFileURL(path.join(baselineDirectory, relativePath)).href;

const argsModule = await import(moduleUrl("packages/coding-agent/src/cli/args.ts"));
const listModelsModule = await import(moduleUrl("packages/coding-agent/src/cli/list-models.ts"));
const modelRuntimeModule = await import(moduleUrl("packages/coding-agent/src/core/model-runtime.ts"));
const sessionModule = await import(moduleUrl("packages/coding-agent/src/core/session-manager.ts"));
const sqliteModule = await import(moduleUrl("packages/session-backends/sqlite-node/src/index.ts"));
const nodeEnvModule = await import(moduleUrl("packages/agent/src/harness/env/nodejs.ts"));
const completionsModule = await import(moduleUrl("packages/ai/src/api/openai-completions.ts"));
const truncateModule = await import(moduleUrl("packages/coding-agent/src/core/tools/truncate.ts"));
const readModule = await import(moduleUrl("packages/coding-agent/src/core/tools/read.ts"));
const grepModule = await import(moduleUrl("packages/coding-agent/src/core/tools/grep.ts"));
const tuiUtilsModule = await import(moduleUrl("packages/tui/src/utils.ts"));

// Both sides render into a sink that only counts, so neither pays terminal
// I/O and neither can win by writing less.
function withCapturedStdout(body) {
	const originalLog = console.log;
	const originalError = console.error;
	let characters = 0;
	let lines = 0;
	const sink = (...parts) => {
		for (const part of parts) characters += [...String(part ?? "")].length;
		// console.log appends the newline that cadr's stream writer emits
		// inline, so counting it keeps the two character counts comparable.
		characters += 1;
		lines += 1;
	};
	console.log = sink;
	console.error = sink;
	try {
		return { value: body(), characters, lines };
	} finally {
		console.log = originalLog;
		console.error = originalError;
	}
}

async function withCapturedStdoutAsync(body) {
	const originalLog = console.log;
	const originalError = console.error;
	let characters = 0;
	let lines = 0;
	const sink = (...parts) => {
		for (const part of parts) characters += [...String(part ?? "")].length;
		// console.log appends the newline that cadr's stream writer emits
		// inline, so counting it keeps the two character counts comparable.
		characters += 1;
		lines += 1;
	};
	console.log = sink;
	console.error = sink;
	try {
		return { value: await body(), characters, lines };
	} finally {
		console.log = originalLog;
		console.error = originalError;
	}
}

// ---------------------------------------------------------------------------
// Pair 1: CLI startup / command dispatch
// ---------------------------------------------------------------------------

function createModelRuntime() {
	return modelRuntimeModule.ModelRuntime.create({
		authPath: path.join(agentDirectory, "auth.json"),
		modelsPath: path.join(agentDirectory, "models.json"),
		modelsStorePath: path.join(agentDirectory, "models-store.json"),
		allowModelNetwork: false,
	});
}

async function measureCliDispatch() {
	const parsed = argsModule.parseArgs(cliArgv.parse);
	const helpShape = withCapturedStdout(() => argsModule.printHelp());
	const runtime = await createModelRuntime();
	const available = await runtime.getAvailable();
	const listShape = await withCapturedStdoutAsync(() =>
		listModelsModule.listModels(runtime, cliArgv.list_models[1]),
	);

	return {
		argv: cliArgv.parse,
		argv_parse: await collect("cli_dispatch.argv_parse", () => {
			return () => argsModule.parseArgs(cliArgv.parse);
		}),
		help_render: await collectHelpRender(),
		list_models_registry: await collect("cli_dispatch.list_models_registry", () => {
			return () => createModelRuntime();
		}),
		list_models_render: await collect("cli_dispatch.list_models_render", () => {
			const originalLog = console.log;
			return async () => {
				console.log = () => {};
				try {
					await listModelsModule.listModels(runtime, cliArgv.list_models[1]);
				} finally {
					console.log = originalLog;
				}
			};
		}),
		observed: {
			parsed_provider: parsed.provider,
			parsed_model: parsed.model,
			parsed_thinking: parsed.thinking,
			parsed_tools: parsed.tools ?? [],
			parsed_exclude_tools: parsed.excludeTools ?? [],
			parsed_messages: parsed.messages,
			parsed_file_args: parsed.fileArgs,
			parsed_list_models: parsed.listModels,
			parsed_unknown_flag_count: parsed.unknownFlags.size,
			parsed_diagnostic_count: parsed.diagnostics.length,
			help_characters: helpShape.characters,
			available_model_count: available.length,
			available_providers: [...new Set(available.map((model) => model.provider))].sort(),
			list_models_characters: listShape.characters,
			list_models_lines: listShape.lines,
		},
	};
}

// Kept separate so the help-render loop can restore console.log exactly once
// per sample instead of once per repetition.
async function collectHelpRender() {
	return collect("cli_dispatch.help_render", () => {
		const originalLog = console.log;
		console.log = () => {};
		let remaining = repetitionsFor("cli_dispatch.help_render");
		return () => {
			argsModule.printHelp();
			remaining -= 1;
			if (remaining <= 0) console.log = originalLog;
		};
	});
}

// ---------------------------------------------------------------------------
// Pair 2: provider request assembly + response parse
// ---------------------------------------------------------------------------

const providerModel = {
	id: "goal20-paired-1",
	name: "Goal 20 Paired 1",
	api: "openai-completions",
	provider: "goal20faux",
	baseUrl: "http://127.0.0.1:1/v1",
	reasoning: true,
	input: ["text", "image"],
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
	contextWindow: 128000,
	maxTokens: 16384,
};

// pi's documented transport seam is ProviderRequestOptions.fetch; cadr's is
// cadr-ai:*http-request-function*.  Both replace only the socket: request
// assembly, status handling, SSE decoding, event reduction, and final
// message assembly all stay on the production path.  Both re-read the
// fixture from the filesystem per call so neither side gets a free ride on
// a pre-parsed buffer.
async function runProviderStream(collectEvents) {
	const events = collectEvents ? [] : undefined;
	let payload;
	const stream = completionsModule.stream(providerModel, providerContext, {
		apiKey: "goal20-paired-paths-not-a-real-key",
		maxRetries: 0,
		fetch: async () =>
			new Response(readFileSync(sseFixturePath), {
				status: 200,
				headers: { "content-type": "text/event-stream" },
			}),
		onPayload: (value) => {
			payload = value;
			return undefined;
		},
	});
	for await (const event of stream) events?.push(event.type);
	const message = await stream.result();
	return { events, message, payload };
}

async function measureProviderStream() {
	const observed = await runProviderStream(true);
	if (observed.message.stopReason !== "toolUse") {
		throw new Error(`fixture stream produced stopReason ${observed.message.stopReason}`);
	}
	const text = observed.message.content
		.filter((block) => block.type === "text")
		.map((block) => block.text)
		.join("");
	return {
		stream_roundtrip: await collect("provider_stream.stream_roundtrip", () => {
			return () => runProviderStream(false);
		}),
		observed: {
			// Keys are taken after a JSON round-trip: buildParams leaves
			// inapplicable fields as `undefined`, which JS keeps as own
			// properties but never puts on the wire.  cadr assembles a JSON
			// object directly, so the serialised key set is the comparable one.
			payload_keys: Object.keys(JSON.parse(JSON.stringify(observed.payload))).sort(),
			payload_message_count: observed.payload.messages.length,
			payload_tool_count: observed.payload.tools?.length ?? 0,
			payload_stream: observed.payload.stream === true,
			event_count: observed.events.length,
			event_kinds: [...new Set(observed.events)].sort(),
			event_kind_counts: countKinds(observed.events),
			content_block_types: observed.message.content.map((block) => block.type),
			// Code points, not UTF-16 units: JS string length counts an
			// astral emoji twice and a Lisp character count does not, which
			// would show up as a phantom text divergence.
			text_characters: [...text].length,
			tool_call_count: observed.message.content.filter((block) => block.type === "toolCall").length,
			stop_reason: observed.message.stopReason,
			usage_input: observed.message.usage.input,
			usage_output: observed.message.usage.output,
		},
	};
}

// ---------------------------------------------------------------------------
// Pair 3: agent session load + event pipeline
// ---------------------------------------------------------------------------

function openSessionFixture() {
	return sessionModule.SessionManager.open(sessionFixturePath, path.join(scratch, "sessions"));
}

async function measureSessionPipeline() {
	const manager = openSessionFixture();
	const entries = manager.getEntries();
	const leafId = manager.getLeafId();
	const context = sessionModule.buildSessionContext(entries, leafId);
	const contextEntries = sessionModule.buildContextEntries(entries, leafId);

	return {
		session_load: await collect("session_pipeline.session_load", () => {
			return () => openSessionFixture();
		}),
		context_walk: await collect("session_pipeline.context_walk", () => {
			return () => sessionModule.buildSessionContext(entries, leafId);
		}),
		observed: {
			entry_count: entries.length,
			leaf_id: leafId,
			session_id: manager.getSessionId(),
			session_name: manager.getSessionName() ?? null,
			context_entry_count: contextEntries.length,
			context_message_count: context.messages.length,
			context_thinking_level: context.thinkingLevel,
			context_model: context.model,
			context_message_roles: countRoles(context.messages),
		},
	};
}

function countRoles(messages) {
	return countKinds(messages.map((message) => message.role ?? "unknown"));
}

function countKinds(names) {
	const counts = {};
	for (const name of names) counts[name] = (counts[name] ?? 0) + 1;
	return Object.fromEntries(Object.entries(counts).sort(([left], [right]) => left.localeCompare(right)));
}

// ---------------------------------------------------------------------------
// Pair 4: storage read/write
// ---------------------------------------------------------------------------

const JOURNAL_APPEND_ENTRY_COUNT = 128;

// The append fixture is the first N message entries of the shared session
// fixture, replayed into a fresh journal.  Both sides therefore write the
// same logical entries in the same order.
const journalAppendMessages = (() => {
	const raw = sessionModule.loadEntriesFromFile(sessionFixturePath);
	const messages = [];
	for (const entry of raw) {
		if (entry.type !== "message") continue;
		messages.push(entry.message);
		if (messages.length === JOURNAL_APPEND_ENTRY_COUNT) break;
	}
	if (messages.length < JOURNAL_APPEND_ENTRY_COUNT) {
		throw new Error("session fixture has too few message entries for the append pair");
	}
	return messages;
})();

let journalWriteIndex = 0;
function appendJournalOnce() {
	journalWriteIndex += 1;
	const directory = path.join(scratch, "journal", String(journalWriteIndex));
	const manager = sessionModule.SessionManager.create(resolvedJournalCwd, directory, {
		id: `019f0000-0000-7000-8000-${String(journalWriteIndex).padStart(12, "0")}`,
	});
	for (const message of journalAppendMessages) manager.appendMessage(message);
	return manager;
}

async function measureStorageJournal() {
	const raw = sessionModule.loadEntriesFromFile(sessionFixturePath);
	const written = appendJournalOnce();
	const writtenPath = written.getSessionFile();
	const writtenText = readFileSync(writtenPath, "utf8");
	const writtenBytes = Buffer.byteLength(writtenText, "utf8");
	const writtenEntries = sessionModule.loadEntriesFromFile(writtenPath).length;
	// The header line carries the cwd and a wall-clock timestamp, so the body
	// is what the two sides can compare byte for byte.
	const headerLength = Buffer.byteLength(`${writtenText.split("\n", 1)[0]}\n`, "utf8");
	if (options.keepJournal) copyFileSync(writtenPath, options.keepJournal);

	return {
		journal_read: await collect("storage_journal.journal_read", () => {
			return () => sessionModule.loadEntriesFromFile(sessionFixturePath);
		}),
		journal_append: await collect("storage_journal.journal_append", () => {
			return () => appendJournalOnce();
		}),
		observed: {
			read_file_entry_count: raw.length,
			append_entry_count: JOURNAL_APPEND_ENTRY_COUNT,
			journal_cwd: written.getCwd(),
			written_file_entry_count: writtenEntries,
			written_bytes: writtenBytes,
			written_body_bytes: writtenBytes - headerLength,
		},
	};
}

function sqliteEnv(root) {
	return new nodeEnvModule.NodeExecutionEnv({ cwd: root });
}

function provisionedFromV3(entry) {
	const id = entry.id;
	switch (entry.type) {
		case "message":
			return { type: "message", id, message: entry.message };
		case "model_change":
			return { type: "model_change", id, provider: entry.provider, modelId: entry.modelId };
		case "thinking_level_change":
			return { type: "thinking_level_change", id, thinkingLevel: entry.thinkingLevel };
		case "compaction":
			return {
				type: "compaction",
				id,
				summary: entry.summary,
				tokensBefore: entry.tokensBefore,
				retainedTail: entry.retainedTail ?? [],
				...(entry.details !== undefined ? { details: entry.details } : {}),
				...(entry.usage !== undefined ? { usage: entry.usage } : {}),
			};
		case "branch_summary":
			return {
				type: "branch_summary",
				id,
				fromId: entry.fromId,
				summary: entry.summary,
				...(entry.details !== undefined ? { details: entry.details } : {}),
				...(entry.usage !== undefined ? { usage: entry.usage } : {}),
			};
		case "custom":
			return {
				type: "custom",
				id,
				customType: entry.customType,
				...(entry.data !== undefined ? { data: entry.data } : {}),
			};
		case "custom_message":
			return {
				type: "custom",
				id,
				customType: "custom_message",
				data: { content: entry.content, display: entry.display, customType: entry.customType },
			};
		case "label":
			return { type: "custom", id, customType: "label", data: { targetId: entry.targetId, label: entry.label } };
		case "session_info":
			return { type: "custom", id, customType: "session_info", data: { name: entry.name } };
		default:
			throw new Error(`unhandled session.jsonl entry type: ${entry.type}`);
	}
}

async function ingestSqliteFromSessionJsonl(databasePath) {
	const raw = sessionModule.loadEntriesFromFile(sessionFixturePath);
	const header = raw[0];
	if (!header || header.type !== "session") {
		throw new Error("session.jsonl is missing a session header");
	}
	mkdirSync(path.dirname(databasePath), { recursive: true });
	const repo = new sqliteModule.SqliteSessionRepository({
		env: sqliteEnv(scratch),
		sqlite: sqliteModule.createNodeSqliteFactory(),
		databasePath,
	});
	const session = await repo.create({ cwd: resolvedJournalCwd, id: header.id });
	for (const entry of raw.slice(1)) {
		await session.appendEntry(provisionedFromV3(entry), "main");
	}
	const metadata = await session.getMetadata();
	const ingested = raw.length - 1;
	const sourceLeafId = raw[raw.length - 1].id;
	await repo.close();
	return { metadata, ingested, sourceLeafId, sessionId: header.id };
}

async function sqliteOpenReadWalk(databasePath, metadata) {
	const repo = new sqliteModule.SqliteSessionRepository({
		env: sqliteEnv(scratch),
		sqlite: sqliteModule.createNodeSqliteFactory(),
		databasePath,
	});
	try {
		const session = await repo.open(metadata);
		const entries = await session.findEntries({ order: "oldestFirst" });
		const leafId = await session.getLeafId();
		const branch = leafId === null ? [] : await session.findEntriesOnBranch({ start: leafId });
		return { entryCount: entries.length, leafId, branchEntryCount: branch.length };
	} finally {
		await repo.close();
	}
}

async function measureSqliteSession() {
	const databasePath = path.join(scratch, "sqlite", "sessions.sqlite");
	const ingested = await ingestSqliteFromSessionJsonl(databasePath);
	const observed = await sqliteOpenReadWalk(databasePath, ingested.metadata);
	return {
		open_walk: await collect("sqlite_session.open_walk", () => {
			return () => sqliteOpenReadWalk(databasePath, ingested.metadata);
		}),
		observed: {
			entry_count: observed.entryCount,
			leaf_id: observed.leafId,
			branch_entry_count: observed.branchEntryCount,
			ingested_entry_count: ingested.ingested,
			session_id: ingested.sessionId,
			source_leaf_id: ingested.sourceLeafId,
		},
	};
}

async function measureTextTruncation() {
	const lines = [];
	for (let i = 1; i <= 4000; i++) {
		lines.push(i % 2 === 1 ? "x".repeat(220) : "é🙂中文 mixed tail line");
	}
	const content = `${lines.join("\n")}\n`;
	const head = truncateModule.truncateHead(content);
	const tail = truncateModule.truncateTail(content);
	return {
		truncate_head: await collect("text_truncation.truncate_head", () => {
			return () => truncateModule.truncateHead(content);
		}),
		truncate_tail: await collect("text_truncation.truncate_tail", () => {
			return () => truncateModule.truncateTail(content);
		}),
		observed: {
			content_bytes: Buffer.byteLength(content, "utf8"),
			head_output_lines: head.outputLines,
			head_output_bytes: head.outputBytes,
			head_truncated_by: head.truncatedBy ?? "null",
			head_first_line_exceeds: head.firstLineExceedsLimit ? 1 : 0,
			tail_output_lines: tail.outputLines,
			tail_output_bytes: tail.outputBytes,
			tail_truncated_by: tail.truncatedBy ?? "null",
			tail_last_line_partial: tail.lastLinePartial ? 1 : 0,
		},
	};
}

async function measureToolRead() {
	const lines = [];
	for (let i = 1; i <= 4000; i++) {
		lines.push(i % 2 === 1 ? "x".repeat(220) : "é🙂中文 mixed tail line");
	}
	const content = `${lines.join("\n")}\n`;
	const dir = path.join(scratch, "read");
	mkdirSync(dir, { recursive: true });
	const filename = "read-fixture.txt";
	writeFileSync(path.join(dir, filename), content, "utf8");
	const def = readModule.createReadToolDefinition(dir);
	const once = await def.execute("", { path: filename });
	const text = once.content[0].text;
	return {
		text_file: await collect("tool_read.text_file", () => {
			return () => def.execute("", { path: filename });
		}),
		observed: {
			line_count: content.split("\n").length,
			output_chars: text.length,
			truncated: once.details?.truncation?.truncated ? 1 : 0,
		},
	};
}

async function measureToolGrep() {
	const lines = [];
	for (let i = 1; i <= 4000; i++) {
		lines.push(i % 2 === 1 ? "x".repeat(220) : "é🙂中文 mixed tail line");
	}
	const content = `${lines.join("\n")}\n`;
	const dir = path.join(scratch, "grep");
	mkdirSync(dir, { recursive: true });
	const filename = "grep-fixture.txt";
	writeFileSync(path.join(dir, filename), content, "utf8");
	const def = grepModule.createGrepToolDefinition(dir);
	const args = {
		pattern: "mixed tail",
		path: filename,
		literal: true,
		context: 2,
		limit: 100,
	};
	const once = await def.execute("", args);
	const text = once.content[0].text;
	return {
		context_file: await collect("tool_grep.context_file", () => {
			return () => def.execute("", args);
		}),
		observed: {
			match_limit: once.details?.matchLimitReached ?? 0,
			output_chars: text.length,
			truncated: once.details?.truncation?.truncated ? 1 : 0,
		},
	};
}

async function measureRenderSlicing() {
	const dense = Array.from(
		{ length: 200 },
		(_, i) => `\x1b[38;2;${(i * 37) % 256};${(i * 91) % 256};${(i * 53) % 256}mword${i}\x1b[0m `,
	).join("");
	const plain = "a".repeat(4000);
	const denseClip = tuiUtilsModule.sliceWithWidth(dense, 40, 60, true);
	const denseHead = tuiUtilsModule.sliceWithWidth(dense, 0, 80, true);
	const plainClip = tuiUtilsModule.sliceWithWidth(plain, 100, 60, true);
	return {
		slice_ansi_clip: await collect("render_slicing.slice_ansi_clip", () => {
			return () => tuiUtilsModule.sliceWithWidth(dense, 40, 60, true);
		}),
		slice_plain_clip: await collect("render_slicing.slice_plain_clip", () => {
			return () => tuiUtilsModule.sliceWithWidth(plain, 100, 60, true);
		}),
		observed: {
			dense_clip_text: denseClip.text,
			dense_clip_width: denseClip.width,
			dense_head_text: denseHead.text,
			dense_head_width: denseHead.width,
			plain_clip_text: plainClip.text,
			plain_clip_width: plainClip.width,
		},
	};
}

// ---------------------------------------------------------------------------

process.stderr.write("goal20 pi paired paths: cli_dispatch\n");
const cliDispatch = await measureCliDispatch();
process.stderr.write("goal20 pi paired paths: provider_stream\n");
const providerStream = await measureProviderStream();
process.stderr.write("goal20 pi paired paths: session_pipeline\n");
const sessionPipeline = await measureSessionPipeline();
process.stderr.write("goal20 pi paired paths: storage_journal\n");
const storageJournal = await measureStorageJournal();
process.stderr.write("goal20 pi paired paths: sqlite_session\n");
const sqliteSession = await measureSqliteSession();
process.stderr.write("goal20 pi paired paths: text_truncation\n");
const textTruncation = await measureTextTruncation();
process.stderr.write("goal20 pi paired paths: tool_read\n");
const toolRead = await measureToolRead();
process.stderr.write("goal20 pi paired paths: tool_grep\n");
const toolGrep = await measureToolGrep();
process.stderr.write("goal20 pi paired paths: render_slicing\n");
const renderSlicing = await measureRenderSlicing();

const result = {
	schema_version: 1,
	kind: "pi-goal20-part-h-paired-paths",
	provenance: {
		source_revision: revision,
		source_revision_from: revisionSource,
		baseline_directory: baselineDirectory,
		fixture_sha256: fixtureDigests,
		staged_agent_dir_sha256: stagedDigests,
		entry_points: {
			"cli_dispatch.argv_parse": "packages/coding-agent/src/cli/args.ts parseArgs",
			"cli_dispatch.help_render": "packages/coding-agent/src/cli/args.ts printHelp",
			"cli_dispatch.list_models_registry":
				"packages/coding-agent/src/core/model-runtime.ts ModelRuntime.create",
			"cli_dispatch.list_models_render": "packages/coding-agent/src/cli/list-models.ts listModels",
			"provider_stream.stream_roundtrip": "packages/ai/src/api/openai-completions.ts stream",
			"session_pipeline.session_load":
				"packages/coding-agent/src/core/session-manager.ts SessionManager.open",
			"session_pipeline.context_walk":
				"packages/coding-agent/src/core/session-manager.ts buildSessionContext",
			"storage_journal.journal_read":
				"packages/coding-agent/src/core/session-manager.ts loadEntriesFromFile",
			"storage_journal.journal_append":
				"packages/coding-agent/src/core/session-manager.ts SessionManager.create + appendMessage",
			"sqlite_session.open_walk":
				"packages/session-backends/sqlite-node SqliteSessionRepository.open + findEntries + findEntriesOnBranch",
			"tool_read.text_file":
				"packages/coding-agent/src/core/tools/read.ts createReadToolDefinition.execute",
			"tool_grep.context_file":
				"packages/coding-agent/src/core/tools/grep.ts createGrepToolDefinition.execute",
			"text_truncation.truncate_head":
				"packages/coding-agent/src/core/tools/truncate.ts truncateHead",
			"text_truncation.truncate_tail":
				"packages/coding-agent/src/core/tools/truncate.ts truncateTail",
			"render_slicing.slice_ansi_clip": "packages/tui/src/utils.ts sliceWithWidth",
			"render_slicing.slice_plain_clip": "packages/tui/src/utils.ts sliceWithWidth",
		},
	},
	parameters: {
		samples: options.samples,
		warmups: options.warmups,
		quick: options.quick,
		repetitions: Object.fromEntries(Object.keys(REPETITIONS).map((name) => [name, repetitionsFor(name)])),
		journal_append_entry_count: JOURNAL_APPEND_ENTRY_COUNT,
		transport_stub: "ProviderRequestOptions.fetch returns the SSE fixture; no socket is opened",
		terminal_sink: "count-only",
		scrubbed_environment: scrubbedEnvironment,
	},
	machine: {
		hostname: hostname(),
		node_version: process.version,
	},
	metrics: {
		cli_dispatch: cliDispatch,
		provider_stream: providerStream,
		session_pipeline: sessionPipeline,
		storage_journal: storageJournal,
		sqlite_session: sqliteSession,
		text_truncation: textTruncation,
		tool_read: toolRead,
		tool_grep: toolGrep,
		render_slicing: renderSlicing,
	},
};

rmSync(scratch, { recursive: true, force: true });

const text = `${JSON.stringify(result, null, 2)}\n`;
if (options.output === "-") process.stdout.write(text);
else writeFileSync(options.output, text, "utf8");
