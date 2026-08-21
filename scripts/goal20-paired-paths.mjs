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
	readdirSync,
	realpathSync,
	rmSync,
	utimesSync,
	writeFileSync,
} from "node:fs";
import { hostname, tmpdir } from "node:os";
import { Readable } from "node:stream";
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
	"provider_anthropic.stream_roundtrip": 10,
	"provider_google.stream_roundtrip": 10,
	"provider_bedrock.stream_roundtrip": 10,
	"provider_mistral.stream_roundtrip": 10,
	"provider_openai_responses.stream_roundtrip": 10,
	"provider_azure_openai.stream_roundtrip": 10,
	"provider_vertex.stream_roundtrip": 10,
	"provider_codex.stream_roundtrip": 10,
	"provider_pi_messages.stream_roundtrip": 10,
	"cli_settings.create": 5,
	"resource_loader.reload": 3,
	"package_manager.resolve": 5,
	"session_discovery.header_probe": 20,
	"session_export_html.to_html": 3,
	"protocol_cbor.roundtrip": 50,
	"agent_schema.validate_ok_fail": 50,
	"harness_storage.open_walk": 3,
	"protocol_codec.roundtrip": 50,
	"agent_proxy.stream_roundtrip": 10,
	"oauth_pkce.challenge_urls": 50,
	"evals_harness.summarize": 20,
	"ai_crypto_model_data.manifest": 50,
	"cli_models_rest.pattern_match": 50,
	"image_runtime.dimensions": 50,
	"cli_print_rpc.jsonl_line": 50,
	"tui_latex.render": 20,
	"tui_editor_helpers.fuzzy_match": 50,
	"tui_theme_overlay.osc11_bg": 50,
	"ai_support.estimate_text": 50,
	"tui_select_settings_loaders.filter": 50,
	"tui_word_navigation.step": 50,
	"tui_overlay.composite_line": 50,
	"tui_kill_ring.push_peek": 50,
	"tui_undo_stack.push_pop": 50,
	"tui_autocomplete.suggest_apply": 50,
	"tui_keybindings.resolve_match": 50,
	"tui_stdin_buffer.process": 50,
	"tui_input_component.edit": 50,
	"tui_native_modifiers.pressed": 50,
	"tui_settings_list.apply_filter": 50,
	"ai_capabilities.short_hash": 50,
	"cli_support.strip_ansi": 50,
	"cli_interactive_controller.decode_entity": 50,
	"cli_sdk.version_newer": 50,
	"provider_registry_defs.lookup": 50,
	"session_pipeline.session_load": 3,
	"session_pipeline.context_walk": 50,
	"storage_journal.journal_read": 5,
	"storage_journal.journal_append": 3,
	"sqlite_session.open_walk": 3,
	"tool_read.text_file": 5,
	"tool_grep.context_file": 5,
	"agent_tool_loop.roundtrip": 3,
	"session_compact.compact": 3,
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
	"anthropic-messages.sse",
	"google-generative-ai.sse",
	"bedrock-converse-stream.bin",
	"mistral-conversations.sse",
	"openai-responses.sse",
	"azure-openai-responses.sse",
	"google-vertex.sse",
	"vertex-adc.json",
	"openai-codex-responses.sse",
	"pi-messages.sse",
	"settings-global.json",
	"settings-project.json",
	"resource-skill-global.md",
	"resource-skill-project.md",
	"resource-prompt-global.md",
	"resource-prompt-project.md",
	"resource-agents.md",
	"package-manifest.json",
	"package-skill.md",
	"package-prompt.md",
	"package-theme.json",
	"package-extension.js",
	"package-settings-global.json",
	"package-settings-project.json",
	"resource-system.md",
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
const anthropicSsePath = path.join(fixtureDirectory, "anthropic-messages.sse");
const googleSsePath = path.join(fixtureDirectory, "google-generative-ai.sse");
const bedrockEventStreamPath = path.join(fixtureDirectory, "bedrock-converse-stream.bin");
const mistralSsePath = path.join(fixtureDirectory, "mistral-conversations.sse");
const openaiResponsesSsePath = path.join(fixtureDirectory, "openai-responses.sse");
const azureOpenaiSsePath = path.join(fixtureDirectory, "azure-openai-responses.sse");
const vertexSsePath = path.join(fixtureDirectory, "google-vertex.sse");
const vertexAdc = JSON.parse(
	readFileSync(path.join(fixtureDirectory, "vertex-adc.json"), "utf8"),
);
const openaiCodexSsePath = path.join(fixtureDirectory, "openai-codex-responses.sse");
const piMessagesSsePath = path.join(fixtureDirectory, "pi-messages.sse");
const openaiCodexOauthToken =
	"eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL2F1dGgiOnsiY2hhdGdwdF9hY2NvdW50X2lkIjoiZ29hbDIwLWNvZGV4LWFjY291bnQifX0.sig";
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
const exportHtmlModule = await import(moduleUrl("packages/coding-agent/src/core/export-html/index.ts"));
const cborModule = await import(moduleUrl("packages/protocol/src/cbor/index.ts"));
const protocolCodecModule = await import(moduleUrl("packages/protocol/src/codec.ts"));
const proxyModule = await import(moduleUrl("packages/agent/src/proxy.ts"));
const evalsSummaryModule = await import(
	moduleUrl("packages/evals/src/vitest-evals/summary.ts")
);
const modelDataModule = await import(moduleUrl("packages/ai/scripts/model-data.ts"));
const modelResolverModule = await import(
	moduleUrl("packages/coding-agent/src/core/model-resolver.ts")
);
const validationModule = await import(moduleUrl("packages/ai/src/utils/validation.ts"));
const jsonlModule = await import(moduleUrl("packages/agent/src/harness/session/jsonl.ts"));
const rpcJsonlModule = await import(moduleUrl("packages/coding-agent/src/modes/rpc/jsonl.ts"));
const sqliteModule = await import(moduleUrl("packages/session-backends/sqlite-node/src/index.ts"));
const nodeEnvModule = await import(moduleUrl("packages/agent/src/harness/env/nodejs.ts"));
const completionsModule = await import(moduleUrl("packages/ai/src/api/openai-completions.ts"));
const anthropicModule = await import(moduleUrl("packages/ai/src/api/anthropic-messages.ts"));
const googleModule = await import(moduleUrl("packages/ai/src/api/google-generative-ai.ts"));
const bedrockModule = await import(moduleUrl("packages/ai/src/api/bedrock-converse-stream.ts"));
const mistralModule = await import(moduleUrl("packages/ai/src/api/mistral-conversations.ts"));
const openaiResponsesModule = await import(moduleUrl("packages/ai/src/api/openai-responses.ts"));
const azureOpenaiModule = await import(moduleUrl("packages/ai/src/api/azure-openai-responses.ts"));
const vertexModule = await import(moduleUrl("packages/ai/src/api/google-vertex.ts"));
const openaiCodexModule = await import(moduleUrl("packages/ai/src/api/openai-codex-responses.ts"));
const piMessagesModule = await import(moduleUrl("packages/ai/src/api/pi-messages.ts"));
const settingsModule = await import(moduleUrl("packages/coding-agent/src/core/settings-manager.ts"));
const resourceLoaderModule = await import(moduleUrl("packages/coding-agent/src/core/resource-loader.ts"));
const packageManagerModule = await import(moduleUrl("packages/coding-agent/src/core/package-manager.ts"));
const truncateModule = await import(moduleUrl("packages/coding-agent/src/core/tools/truncate.ts"));
const readModule = await import(moduleUrl("packages/coding-agent/src/core/tools/read.ts"));
const grepModule = await import(moduleUrl("packages/coding-agent/src/core/tools/grep.ts"));
const tuiUtilsModule = await import(moduleUrl("packages/tui/src/utils.ts"));
const terminalImageModule = await import(moduleUrl("packages/tui/src/terminal-image.ts"));
const latexModule = await import(moduleUrl("packages/tui/src/latex.ts"));
const fuzzyModule = await import(moduleUrl("packages/tui/src/fuzzy.ts"));
const terminalColorsModule = await import(moduleUrl("packages/tui/src/terminal-colors.ts"));
const estimateModule = await import(moduleUrl("packages/ai/src/utils/estimate.ts"));
const selectListModule = await import(moduleUrl("packages/tui/src/components/select-list.ts"));
const wordNavigationModule = await import(moduleUrl("packages/tui/src/word-navigation.ts"));
const tuiModule = await import(moduleUrl("packages/tui/src/tui.ts"));
const killRingModule = await import(moduleUrl("packages/tui/src/kill-ring.ts"));
const undoStackModule = await import(moduleUrl("packages/tui/src/undo-stack.ts"));
const autocompleteModule = await import(moduleUrl("packages/tui/src/autocomplete.ts"));
const keybindingsModule = await import(moduleUrl("packages/tui/src/keybindings.ts"));
const stdinBufferModule = await import(moduleUrl("packages/tui/src/stdin-buffer.ts"));
const inputModule = await import(moduleUrl("packages/tui/src/components/input.ts"));
const nativeModifiersModule = await import(moduleUrl("packages/tui/src/native-modifiers.ts"));
const settingsListModule = await import(moduleUrl("packages/tui/src/components/settings-list.ts"));
const hashModule = await import(moduleUrl("packages/ai/src/utils/hash.ts"));
const ansiModule = await import(moduleUrl("packages/coding-agent/src/utils/ansi.ts"));
const htmlEntityModule = await import(moduleUrl("packages/coding-agent/src/utils/html.ts"));
const versionCheckModule = await import(moduleUrl("packages/coding-agent/src/utils/version-check.ts"));
const builtinProvidersModule = await import(moduleUrl("packages/ai/src/providers/all.ts"));
const agentModule = await import(moduleUrl("packages/agent/src/agent.ts"));
const eventStreamModule = await import(moduleUrl("packages/ai/src/utils/event-stream.ts"));
const { createRequire } = await import("node:module");
const baselineRequire = createRequire(path.join(baselineDirectory, "package.json"));
const { Type } = baselineRequire("typebox");
const { NodeHttpHandler, NodeHttp2Handler } = baselineRequire("@smithy/node-http-handler");
const compactionModule = await import(
	moduleUrl("packages/coding-agent/src/core/compaction/compaction.ts")
);

const settingsAgentDirectory = path.join(scratch, "settings-agent");
const settingsCwdDirectory = path.join(scratch, "settings-cwd");
mkdirSync(settingsAgentDirectory, { recursive: true });
mkdirSync(path.join(settingsCwdDirectory, ".pi"), { recursive: true });
copyFileSync(
	path.join(fixtureDirectory, "settings-global.json"),
	path.join(settingsAgentDirectory, "settings.json"),
);
copyFileSync(
	path.join(fixtureDirectory, "settings-project.json"),
	path.join(settingsCwdDirectory, ".pi", "settings.json"),
);

const packageAgentDirectory = path.join(scratch, "package-agent");
const packageCwdDirectory = path.join(scratch, "package-cwd");
const packageRoot = path.join(packageAgentDirectory, "pkg");
mkdirSync(path.join(packageRoot, "skills", "goal20"), { recursive: true });
mkdirSync(path.join(packageRoot, "prompts"), { recursive: true });
mkdirSync(path.join(packageRoot, "themes"), { recursive: true });
mkdirSync(path.join(packageCwdDirectory, ".pi"), { recursive: true });
mkdirSync(path.join(packageCwdDirectory, ".cadr"), { recursive: true });
copyFileSync(path.join(fixtureDirectory, "package-manifest.json"), path.join(packageRoot, "package.json"));
copyFileSync(
	path.join(fixtureDirectory, "package-skill.md"),
	path.join(packageRoot, "skills", "goal20", "SKILL.md"),
);
copyFileSync(path.join(fixtureDirectory, "package-prompt.md"), path.join(packageRoot, "prompts", "goal20.md"));
copyFileSync(path.join(fixtureDirectory, "package-theme.json"), path.join(packageRoot, "themes", "goal20.json"));
copyFileSync(path.join(fixtureDirectory, "package-extension.js"), path.join(packageRoot, "extension.js"));
copyFileSync(
	path.join(fixtureDirectory, "package-settings-global.json"),
	path.join(packageAgentDirectory, "settings.json"),
);
copyFileSync(
	path.join(fixtureDirectory, "package-settings-project.json"),
	path.join(packageCwdDirectory, ".pi", "settings.json"),
);
copyFileSync(
	path.join(fixtureDirectory, "package-settings-project.json"),
	path.join(packageCwdDirectory, ".cadr", "settings.json"),
);

const resourceAgentDirectory = path.join(scratch, "resource-agent");
const resourceCwdDirectory = path.join(scratch, "resource-cwd");
const resourceAgentSkill = path.join(resourceAgentDirectory, "skills", "shared");
const resourceProjectSkillPi = path.join(resourceCwdDirectory, ".pi", "skills", "shared");
const resourceProjectSkillCadr = path.join(resourceCwdDirectory, ".cadr", "skills", "shared");
const resourceAgentPrompt = path.join(resourceAgentDirectory, "prompts");
const resourceProjectPromptPi = path.join(resourceCwdDirectory, ".pi", "prompts");
const resourceProjectPromptCadr = path.join(resourceCwdDirectory, ".cadr", "prompts");
for (const directory of [
	resourceAgentSkill,
	resourceProjectSkillPi,
	resourceProjectSkillCadr,
	resourceAgentPrompt,
	resourceProjectPromptPi,
	resourceProjectPromptCadr,
	path.join(resourceCwdDirectory, ".pi"),
	path.join(resourceCwdDirectory, ".cadr"),
]) {
	mkdirSync(directory, { recursive: true });
}
copyFileSync(path.join(fixtureDirectory, "resource-skill-global.md"), path.join(resourceAgentSkill, "SKILL.md"));
copyFileSync(
	path.join(fixtureDirectory, "resource-skill-project.md"),
	path.join(resourceProjectSkillPi, "SKILL.md"),
);
copyFileSync(
	path.join(fixtureDirectory, "resource-skill-project.md"),
	path.join(resourceProjectSkillCadr, "SKILL.md"),
);
copyFileSync(path.join(fixtureDirectory, "resource-prompt-global.md"), path.join(resourceAgentPrompt, "review.md"));
copyFileSync(
	path.join(fixtureDirectory, "resource-prompt-project.md"),
	path.join(resourceProjectPromptPi, "review.md"),
);
copyFileSync(
	path.join(fixtureDirectory, "resource-prompt-project.md"),
	path.join(resourceProjectPromptCadr, "review.md"),
);
copyFileSync(path.join(fixtureDirectory, "resource-agents.md"), path.join(resourceCwdDirectory, "AGENTS.md"));
copyFileSync(path.join(fixtureDirectory, "resource-system.md"), path.join(resourceCwdDirectory, ".pi", "SYSTEM.md"));
copyFileSync(path.join(fixtureDirectory, "resource-system.md"), path.join(resourceCwdDirectory, ".cadr", "SYSTEM.md"));

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

const anthropicModel = {
	id: "goal20-paired-1",
	name: "Goal 20 Paired 1",
	api: "anthropic-messages",
	provider: "anthropic",
	baseUrl: "https://api.anthropic.com",
	reasoning: false,
	input: ["text", "image"],
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
	contextWindow: 128000,
	maxTokens: 16384,
};

async function runProviderAnthropic(collectEvents) {
	const events = collectEvents ? [] : undefined;
	let payload;
	const stream = anthropicModule.stream(anthropicModel, providerContext, {
		apiKey: "goal20-paired-paths-not-a-real-key",
		maxRetries: 0,
		fetch: async () =>
			new Response(readFileSync(anthropicSsePath), {
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

async function measureProviderAnthropic() {
	const observed = await runProviderAnthropic(true);
	if (observed.message.stopReason !== "toolUse") {
		throw new Error(`anthropic fixture stream produced stopReason ${observed.message.stopReason}`);
	}
	const text = observed.message.content
		.filter((block) => block.type === "text")
		.map((block) => block.text)
		.join("");
	return {
		stream_roundtrip: await collect("provider_anthropic.stream_roundtrip", () => {
			return () => runProviderAnthropic(false);
		}),
		observed: {
			content_block_types: observed.message.content.map((block) => block.type),
			stop_reason: observed.message.stopReason,
			text_characters: [...text].length,
			tool_call_count: observed.message.content.filter((block) => block.type === "toolCall").length,
			usage_input: observed.message.usage.input,
			usage_output: observed.message.usage.output,
			payload_stream: observed.payload?.stream === true,
			payload_tool_count: observed.payload?.tools?.length ?? 0,
		},
	};
}

const googleModel = {
	id: "gemini-3.6-flash",
	name: "Goal 20 Google",
	api: "google-generative-ai",
	provider: "google",
	baseUrl: "https://generativelanguage.googleapis.com/v1beta",
	reasoning: false,
	input: ["text", "image"],
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
	contextWindow: 128000,
	maxTokens: 16384,
};

async function runProviderGoogle(collectEvents) {
	// google-generative-ai.ts throws if options.fetch !== globalThis.fetch.
	// Stub the global so generateContentStream still hits recorded SSE
	// (same alt=sse path as cadr) without a live socket.
	const events = collectEvents ? [] : undefined;
	let payload;
	const originalFetch = globalThis.fetch;
	globalThis.fetch = async () =>
		new Response(readFileSync(googleSsePath), {
			status: 200,
			headers: { "content-type": "text/event-stream" },
		});
	try {
		const stream = googleModule.stream(googleModel, providerContext, {
			apiKey: "goal20-paired-paths-not-a-real-key",
			maxRetries: 0,
			onPayload: (value) => {
				payload = value;
				return undefined;
			},
		});
		for await (const event of stream) events?.push(event.type);
		const message = await stream.result();
		return { events, message, payload };
	} finally {
		globalThis.fetch = originalFetch;
	}
}

async function measureProviderGoogle() {
	const observed = await runProviderGoogle(true);
	if (observed.message.stopReason !== "toolUse") {
		throw new Error(`google fixture stream produced stopReason ${observed.message.stopReason}`);
	}
	const text = observed.message.content
		.filter((block) => block.type === "text")
		.map((block) => block.text)
		.join("");
	const tools = observed.payload?.config?.tools ?? observed.payload?.tools;
	return {
		stream_roundtrip: await collect("provider_google.stream_roundtrip", () => {
			return () => runProviderGoogle(false);
		}),
		observed: {
			content_block_types: observed.message.content.map((block) => block.type),
			stop_reason: observed.message.stopReason,
			text_characters: [...text].length,
			tool_call_count: observed.message.content.filter((block) => block.type === "toolCall").length,
			usage_input: observed.message.usage.input,
			usage_output: observed.message.usage.output,
			payload_tool_count: Array.isArray(tools) ? tools.length : 0,
		},
	};
}

const bedrockModel = {
	id: "us.anthropic.claude-sonnet-4-5",
	name: "Goal 20 Bedrock",
	api: "bedrock-converse-stream",
	provider: "amazon-bedrock",
	baseUrl: "https://bedrock-runtime.us-east-1.amazonaws.com",
	reasoning: false,
	input: ["text", "image"],
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
	contextWindow: 128000,
	maxTokens: 16384,
};

function recordedBedrockHttpHandle() {
	return {
		response: {
			statusCode: 200,
			headers: {
				"content-type": "application/vnd.amazon.eventstream",
				"x-amzn-requestid": "goal20-bedrock",
			},
			body: Readable.from([readFileSync(bedrockEventStreamPath)]),
		},
	};
}

async function runProviderBedrock(collectEvents) {
	// stream() builds BedrockRuntimeClient internally. Stub Smithy HTTP
	// so ConverseStream still deserializes recorded event-stream bytes
	// without a live AWS socket.
	const events = collectEvents ? [] : undefined;
	let payload;
	const originalHttp1 = NodeHttpHandler.prototype.handle;
	const originalHttp2 = NodeHttp2Handler.prototype.handle;
	NodeHttpHandler.prototype.handle = recordedBedrockHttpHandle;
	NodeHttp2Handler.prototype.handle = recordedBedrockHttpHandle;
	try {
		const stream = bedrockModule.stream(bedrockModel, providerContext, {
			apiKey: "goal20-paired-paths-not-a-real-key",
			maxRetries: 0,
			env: { AWS_BEDROCK_FORCE_HTTP1: "1" },
			onPayload: (value) => {
				payload = value;
				return undefined;
			},
		});
		for await (const event of stream) events?.push(event.type);
		const message = await stream.result();
		return { events, message, payload };
	} finally {
		NodeHttpHandler.prototype.handle = originalHttp1;
		NodeHttp2Handler.prototype.handle = originalHttp2;
	}
}

async function measureProviderBedrock() {
	const observed = await runProviderBedrock(true);
	if (observed.message.stopReason !== "toolUse") {
		throw new Error(`bedrock fixture stream produced stopReason ${observed.message.stopReason}`);
	}
	const text = observed.message.content
		.filter((block) => block.type === "text")
		.map((block) => block.text)
		.join("");
	const tools = observed.payload?.toolConfig?.tools;
	return {
		stream_roundtrip: await collect("provider_bedrock.stream_roundtrip", () => {
			return () => runProviderBedrock(false);
		}),
		observed: {
			content_block_types: observed.message.content.map((block) => block.type),
			stop_reason: observed.message.stopReason,
			text_characters: [...text].length,
			tool_call_count: observed.message.content.filter((block) => block.type === "toolCall").length,
			usage_input: observed.message.usage.input,
			usage_output: observed.message.usage.output,
			payload_tool_count: Array.isArray(tools) ? tools.length : 0,
		},
	};
}

const mistralModel = {
	id: "mistral-small-latest",
	name: "Goal 20 Mistral",
	api: "mistral-conversations",
	provider: "mistral",
	baseUrl: "https://api.mistral.ai",
	reasoning: false,
	input: ["text", "image"],
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
	contextWindow: 128000,
	maxTokens: 16384,
};

async function runProviderMistral(collectEvents) {
	const events = collectEvents ? [] : undefined;
	let payload;
	const stream = mistralModule.stream(mistralModel, providerContext, {
		apiKey: "goal20-paired-paths-not-a-real-key",
		maxRetries: 0,
		fetch: async () =>
			new Response(readFileSync(mistralSsePath), {
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

async function measureProviderMistral() {
	const observed = await runProviderMistral(true);
	if (observed.message.stopReason !== "toolUse") {
		throw new Error(`mistral fixture stream produced stopReason ${observed.message.stopReason}`);
	}
	const text = observed.message.content
		.filter((block) => block.type === "text")
		.map((block) => block.text)
		.join("");
	return {
		stream_roundtrip: await collect("provider_mistral.stream_roundtrip", () => {
			return () => runProviderMistral(false);
		}),
		observed: {
			content_block_types: observed.message.content.map((block) => block.type),
			stop_reason: observed.message.stopReason,
			text_characters: [...text].length,
			tool_call_count: observed.message.content.filter((block) => block.type === "toolCall").length,
			usage_input: observed.message.usage.input,
			usage_output: observed.message.usage.output,
			payload_stream: observed.payload?.stream === true,
			payload_tool_count: observed.payload?.tools?.length ?? 0,
		},
	};
}

const openaiResponsesModel = {
	id: "gpt-4.1",
	name: "Goal 20 OpenAI Responses",
	api: "openai-responses",
	provider: "openai",
	baseUrl: "https://api.openai.com",
	reasoning: false,
	input: ["text", "image"],
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
	contextWindow: 128000,
	maxTokens: 16384,
};

async function runProviderOpenaiResponses(collectEvents) {
	const events = collectEvents ? [] : undefined;
	let payload;
	const stream = openaiResponsesModule.stream(openaiResponsesModel, providerContext, {
		apiKey: "goal20-paired-paths-not-a-real-key",
		maxRetries: 0,
		fetch: async () =>
			new Response(readFileSync(openaiResponsesSsePath), {
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

async function measureProviderOpenaiResponses() {
	const observed = await runProviderOpenaiResponses(true);
	if (observed.message.stopReason !== "toolUse") {
		throw new Error(
			`openai-responses fixture stream produced stopReason ${observed.message.stopReason}`,
		);
	}
	const text = observed.message.content
		.filter((block) => block.type === "text")
		.map((block) => block.text)
		.join("");
	return {
		stream_roundtrip: await collect("provider_openai_responses.stream_roundtrip", () => {
			return () => runProviderOpenaiResponses(false);
		}),
		observed: {
			content_block_types: observed.message.content.map((block) => block.type),
			stop_reason: observed.message.stopReason,
			text_characters: [...text].length,
			tool_call_count: observed.message.content.filter((block) => block.type === "toolCall").length,
			usage_input: observed.message.usage.input,
			usage_output: observed.message.usage.output,
			payload_stream: observed.payload?.stream === true,
			payload_tool_count: observed.payload?.tools?.length ?? 0,
		},
	};
}

const azureOpenaiModel = {
	id: "gpt-4.1",
	name: "Goal 20 Azure OpenAI",
	api: "azure-openai-responses",
	provider: "azure-openai-responses",
	baseUrl: "https://goal20.openai.azure.com/openai/v1",
	reasoning: false,
	input: ["text", "image"],
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
	contextWindow: 128000,
	maxTokens: 16384,
};

async function runProviderAzureOpenai(collectEvents) {
	const events = collectEvents ? [] : undefined;
	let payload;
	const stream = azureOpenaiModule.stream(azureOpenaiModel, providerContext, {
		apiKey: "goal20-paired-paths-not-a-real-key",
		maxRetries: 0,
		fetch: async () =>
			new Response(readFileSync(azureOpenaiSsePath), {
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

async function measureProviderAzureOpenai() {
	const observed = await runProviderAzureOpenai(true);
	if (observed.message.stopReason !== "toolUse") {
		throw new Error(
			`azure-openai fixture stream produced stopReason ${observed.message.stopReason}`,
		);
	}
	const text = observed.message.content
		.filter((block) => block.type === "text")
		.map((block) => block.text)
		.join("");
	return {
		stream_roundtrip: await collect("provider_azure_openai.stream_roundtrip", () => {
			return () => runProviderAzureOpenai(false);
		}),
		observed: {
			content_block_types: observed.message.content.map((block) => block.type),
			stop_reason: observed.message.stopReason,
			text_characters: [...text].length,
			tool_call_count: observed.message.content.filter((block) => block.type === "toolCall").length,
			usage_input: observed.message.usage.input,
			usage_output: observed.message.usage.output,
			payload_stream: observed.payload?.stream === true,
			payload_tool_count: observed.payload?.tools?.length ?? 0,
		},
	};
}

const vertexModel = {
	id: "gemini-3.6-flash",
	name: "Goal 20 Vertex",
	api: "google-vertex",
	provider: "google-vertex",
	baseUrl: "https://aiplatform.googleapis.com/v1",
	reasoning: false,
	input: ["text", "image"],
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
	contextWindow: 128000,
	maxTokens: 16384,
};

async function runProviderVertex(collectEvents) {
	// google-vertex.ts throws if options.fetch !== globalThis.fetch.
	// Stub the global so generateContentStream still hits recorded SSE
	// without a live socket. API key avoids google-auth-library ADC
	// exchange (gaxios / node https, not fetch).
	const events = collectEvents ? [] : undefined;
	let payload;
	const originalFetch = globalThis.fetch;
	globalThis.fetch = async () =>
		new Response(readFileSync(vertexSsePath), {
			status: 200,
			headers: { "content-type": "text/event-stream" },
		});
	try {
		const stream = vertexModule.stream(vertexModel, providerContext, {
			apiKey: "goal20-paired-paths-not-a-real-key",
			maxRetries: 0,
			project: "goal20-vertex-project",
			location: "us-east1",
			env: {
				GOOGLE_CLOUD_PROJECT: "goal20-vertex-project",
				GOOGLE_CLOUD_LOCATION: "us-east1",
				GOOGLE_APPLICATION_CREDENTIALS: path.join(fixtureDirectory, "vertex-adc.json"),
			},
			onPayload: (value) => {
				payload = value;
				return undefined;
			},
		});
		for await (const event of stream) events?.push(event.type);
		const message = await stream.result();
		return { events, message, payload };
	} finally {
		globalThis.fetch = originalFetch;
	}
}

async function measureProviderVertex() {
	const observed = await runProviderVertex(true);
	if (observed.message.stopReason !== "toolUse") {
		throw new Error(`vertex fixture stream produced stopReason ${observed.message.stopReason}`);
	}
	const text = observed.message.content
		.filter((block) => block.type === "text")
		.map((block) => block.text)
		.join("");
	const tools = observed.payload?.config?.tools ?? observed.payload?.tools;
	return {
		stream_roundtrip: await collect("provider_vertex.stream_roundtrip", () => {
			return () => runProviderVertex(false);
		}),
		observed: {
			content_block_types: observed.message.content.map((block) => block.type),
			stop_reason: observed.message.stopReason,
			text_characters: [...text].length,
			tool_call_count: observed.message.content.filter((block) => block.type === "toolCall").length,
			usage_input: observed.message.usage.input,
			usage_output: observed.message.usage.output,
			payload_tool_count: Array.isArray(tools) ? tools.length : 0,
			adc_type: vertexAdc.type,
		},
	};
}

const openaiCodexModel = {
	id: "gpt-5.5",
	name: "Goal 20 OpenAI Codex",
	api: "openai-codex-responses",
	provider: "openai-codex",
	baseUrl: "https://chatgpt.com/backend-api",
	reasoning: false,
	input: ["text", "image"],
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
	contextWindow: 128000,
	maxTokens: 16384,
};

async function runProviderCodex(collectEvents) {
	const events = collectEvents ? [] : undefined;
	let payload;
	const stream = openaiCodexModule.stream(openaiCodexModel, providerContext, {
		apiKey: openaiCodexOauthToken,
		maxRetries: 0,
		transport: "sse",
		fetch: async () =>
			new Response(readFileSync(openaiCodexSsePath), {
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

async function measureProviderCodex() {
	const observed = await runProviderCodex(true);
	if (observed.message.stopReason !== "toolUse") {
		throw new Error(`codex fixture stream produced stopReason ${observed.message.stopReason}`);
	}
	const text = observed.message.content
		.filter((block) => block.type === "text")
		.map((block) => block.text)
		.join("");
	return {
		stream_roundtrip: await collect("provider_codex.stream_roundtrip", () => {
			return () => runProviderCodex(false);
		}),
		observed: {
			content_block_types: observed.message.content.map((block) => block.type),
			stop_reason: observed.message.stopReason,
			text_characters: [...text].length,
			tool_call_count: observed.message.content.filter((block) => block.type === "toolCall").length,
			usage_input: observed.message.usage.input,
			usage_output: observed.message.usage.output,
			payload_stream: observed.payload?.stream === true,
			payload_tool_count: observed.payload?.tools?.length ?? 0,
		},
	};
}

const piMessagesModel = {
	id: "pi-goal20",
	name: "Goal 20 pi-messages",
	api: "pi-messages",
	provider: "pi",
	baseUrl: "https://goal20.pi.example/v1",
	reasoning: false,
	input: ["text", "image"],
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
	contextWindow: 128000,
	maxTokens: 16384,
};

async function runProviderPiMessages(collectEvents) {
	const events = collectEvents ? [] : undefined;
	let payload;
	const stream = piMessagesModule.stream(piMessagesModel, providerContext, {
		apiKey: "goal20-paired-paths-not-a-real-key",
		fetch: async () =>
			new Response(readFileSync(piMessagesSsePath), {
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

async function measureProviderPiMessages() {
	const observed = await runProviderPiMessages(true);
	if (observed.message.stopReason !== "toolUse") {
		throw new Error(`pi-messages fixture stream produced stopReason ${observed.message.stopReason}`);
	}
	const text = observed.message.content
		.filter((block) => block.type === "text")
		.map((block) => block.text)
		.join("");
	const tools = observed.payload?.context?.tools;
	return {
		stream_roundtrip: await collect("provider_pi_messages.stream_roundtrip", () => {
			return () => runProviderPiMessages(false);
		}),
		observed: {
			content_block_types: observed.message.content.map((block) => block.type),
			stop_reason: observed.message.stopReason,
			text_characters: [...text].length,
			tool_call_count: observed.message.content.filter((block) => block.type === "toolCall").length,
			usage_input: observed.message.usage.input,
			usage_output: observed.message.usage.output,
			payload_tool_count: Array.isArray(tools) ? tools.length : 0,
		},
	};
}

function runCliSettings() {
	return settingsModule.SettingsManager.create(settingsCwdDirectory, settingsAgentDirectory, {
		projectTrusted: true,
	});
}

async function measureCliSettings() {
	const manager = runCliSettings();
	return {
		create: await collect("cli_settings.create", () => {
			return () => runCliSettings();
		}),
		observed: {
			theme: manager.getThemeSetting() ?? "",
			default_model: manager.getDefaultModel() ?? "",
			default_provider: manager.getDefaultProvider() ?? "",
			compaction_reserve_tokens: manager.getCompactionReserveTokens(),
			default_project_trust: manager.getDefaultProjectTrust(),
			http_idle_timeout_ms: manager.getHttpIdleTimeoutMs(),
			project_trusted: manager.isProjectTrusted(),
		},
	};
}

async function runResourceLoader() {
	const loader = new resourceLoaderModule.DefaultResourceLoader({
		cwd: resourceCwdDirectory,
		agentDir: resourceAgentDirectory,
		noExtensions: true,
		noSkills: true,
		noPromptTemplates: true,
		noThemes: true,
		additionalSkillPaths: [resourceProjectSkillPi, resourceAgentSkill],
		additionalPromptTemplatePaths: [resourceProjectPromptPi, resourceAgentPrompt],
		settingsManager: settingsModule.SettingsManager.create(resourceCwdDirectory, resourceAgentDirectory, {
			projectTrusted: true,
		}),
	});
	await loader.reload();
	return loader;
}

async function measureResourceLoader() {
	const loader = await runResourceLoader();
	const skills = loader.getSkills().skills;
	const prompts = loader.getPrompts().prompts;
	return {
		reload: await collect("resource_loader.reload", () => {
			return () => runResourceLoader();
		}),
		observed: {
			skill_count: skills.length,
			prompt_count: prompts.length,
			skill_names: [...skills.map((skill) => skill.name)].sort(),
			prompt_names: [...prompts.map((prompt) => prompt.name)].sort(),
			skill_from_project: skills.some((skill) => skill.description.includes("project overlay")) ? 1 : 0,
			prompt_from_project: prompts.some((prompt) => prompt.content.includes("project review")) ? 1 : 0,
			context_file_count: loader.getAgentsFiles().agentsFiles.length,
			system_prompt: loader.getSystemPrompt() ? 1 : 0,
		},
	};
}

function makePackageManager() {
	process.env.PI_OFFLINE = "1";
	const settings = settingsModule.SettingsManager.create(packageCwdDirectory, packageAgentDirectory, {
		projectTrusted: true,
	});
	return new packageManagerModule.DefaultPackageManager({
		cwd: packageCwdDirectory,
		agentDir: packageAgentDirectory,
		settingsManager: settings,
	});
}

async function measurePackageManager() {
	const manager = makePackageManager();
	const resolved = await manager.resolve();
	const fromPackage = (entries) =>
		entries.filter((entry) => entry.enabled && entry.metadata?.origin === "package").length;
	return {
		resolve: await collect("package_manager.resolve", () => {
			return () => manager.resolve();
		}),
		observed: {
			package_count: manager.listConfiguredPackages().length,
			skill_count: fromPackage(resolved.skills),
			prompt_count: fromPackage(resolved.prompts),
			theme_count: fromPackage(resolved.themes),
			extension_count: fromPackage(resolved.extensions),
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

function pairedMockModel() {
	return {
		id: "mock",
		name: "mock",
		api: "openai-responses",
		provider: "openai",
		baseUrl: "https://example.invalid",
		reasoning: false,
		input: ["text"],
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		contextWindow: 8192,
		maxTokens: 2048,
	};
}

function pairedAssistantMessage(content, stopReason) {
	return {
		role: "assistant",
		content,
		api: "openai-responses",
		provider: "openai",
		model: "mock",
		usage: {
			input: 0,
			output: 0,
			cacheRead: 0,
			cacheWrite: 0,
			totalTokens: 0,
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
		},
		stopReason,
		timestamp: 1,
	};
}

function pairedEchoTool(executed) {
	const schema = Type.Object({ value: Type.String() });
	return {
		name: "echo",
		label: "Echo",
		description: "Echo",
		parameters: schema,
		executionMode: "parallel",
		async execute(_id, params) {
			executed.value = params.value;
			return {
				content: [{ type: "text", text: "echoed" }],
				details: {},
			};
		},
	};
}

function pairedToolLoopStream() {
	let callIndex = 0;
	return () => {
		const stream = new eventStreamModule.AssistantMessageEventStream();
		queueMicrotask(() => {
			if (callIndex === 0) {
				stream.push({
					type: "done",
					reason: "toolUse",
					message: pairedAssistantMessage(
						[{ type: "toolCall", id: "call_1", name: "echo", arguments: { value: "hello" } }],
						"toolUse",
					),
				});
			} else {
				stream.push({
					type: "done",
					reason: "stop",
					message: pairedAssistantMessage([{ type: "text", text: "done" }], "stop"),
				});
			}
			callIndex += 1;
		});
		return stream;
	};
}

async function runPairedToolLoop() {
	const executed = { value: "" };
	const agent = new agentModule.Agent({
		streamFn: pairedToolLoopStream(),
		convertToLlm: (messages) =>
			messages.filter(
				(message) =>
					message.role === "user" || message.role === "assistant" || message.role === "toolResult",
			),
		initialState: {
			model: pairedMockModel(),
			tools: [pairedEchoTool(executed)],
			thinkingLevel: "off",
			systemPrompt: "",
		},
	});
	await agent.prompt("echo");
	return { agent, executed };
}

async function measureAgentToolLoop() {
	const once = await runPairedToolLoop();
	const messages = once.agent.state.messages;
	const last = messages[messages.length - 1];
	const result = messages[2];
	return {
		roundtrip: await collect("agent_tool_loop.roundtrip", () => {
			return () => runPairedToolLoop();
		}),
		observed: {
			final_text: last.content[0].text,
			message_count: messages.length,
			tool_error: result.isError ? 1 : 0,
			tool_value: once.executed.value,
		},
	};
}

function pairedCompactMessageEntry(id, parentId, message) {
	return {
		type: "message",
		id,
		parentId,
		timestamp: "2026-08-20T00:00:00.000Z",
		message,
	};
}

function pairedCompactUser(text) {
	return { role: "user", content: text, timestamp: 1 };
}

function pairedCompactAssistant(text) {
	return {
		role: "assistant",
		content: [{ type: "text", text }],
		api: "openai-responses",
		provider: "openai",
		model: "tiny",
		usage: {
			input: 60,
			output: 20,
			cacheRead: 0,
			cacheWrite: 0,
			totalTokens: 80,
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
		},
		stopReason: "stop",
		timestamp: 1,
	};
}

function pairedCompactEntries() {
	const discardedUser = `discarded context ${"d".repeat(40)}`;
	const discardedAnswer = `discarded answer ${"e".repeat(40)}`;
	const oldUser = `old context ${"x".repeat(120)}`;
	const oldAnswer = `old answer ${"y".repeat(120)}`;
	return [
		pairedCompactMessageEntry("e1", null, pairedCompactUser(discardedUser)),
		pairedCompactMessageEntry("e2", "e1", pairedCompactAssistant(discardedAnswer)),
		pairedCompactMessageEntry("e3", "e2", pairedCompactUser(oldUser)),
		pairedCompactMessageEntry("e4", "e3", pairedCompactAssistant(oldAnswer)),
		pairedCompactMessageEntry("e5", "e4", pairedCompactUser("current request")),
	];
}

function pairedCompactStream() {
	return () => {
		const stream = new eventStreamModule.AssistantMessageEventStream();
		queueMicrotask(() => {
			stream.push({
				type: "done",
				reason: "stop",
				message: pairedAssistantMessage([{ type: "text", text: "SUMMARY" }], "stop"),
			});
		});
		return stream;
	};
}

async function runPairedCompact() {
	const entries = pairedCompactEntries();
	const preparation = compactionModule.prepareCompaction(entries, {
		enabled: true,
		reserveTokens: 21,
		keepRecentTokens: 40,
	});
	if (!preparation) return null;
	const model = {
		id: "tiny",
		name: "tiny",
		api: "openai-responses",
		provider: "openai",
		baseUrl: "https://example.invalid",
		reasoning: false,
		input: ["text"],
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		contextWindow: 100,
		maxTokens: 32,
	};
	return compactionModule.compact(
		preparation,
		model,
		undefined,
		undefined,
		undefined,
		undefined,
		undefined,
		pairedCompactStream(),
	);
}

async function measureSessionCompact() {
	const once = await runPairedCompact();
	const summary = once?.summary ?? "";
	return {
		compact: await collect("session_compact.compact", () => {
			return () => runPairedCompact();
		}),
		observed: {
			compacted: once ? 1 : 0,
			first_kept: once?.firstKeptEntryId ? 1 : 0,
			summary_chars: summary.length,
		},
	};
}

const SESSION_DISCOVERY_FILE_COUNT = 32;

function stageSessionDiscovery() {
	const dir = path.join(scratch, "discovery-sessions");
	mkdirSync(dir, { recursive: true });
	for (let index = 0; index < SESSION_DISCOVERY_FILE_COUNT; index += 1) {
		const dest = path.join(dir, `sess-${String(index).padStart(2, "0")}.jsonl`);
		copyFileSync(sessionFixturePath, dest);
		const stamp = 1_700_000_000 + index;
		utimesSync(dest, stamp, stamp);
	}
	return dir;
}

function sessionDiscoveryProbe(dir) {
	return sessionModule.findMostRecentSession(dir);
}

const CBOR_ROUNDTRIP_HEX = [
	"f6",
	"f4",
	"f5",
	"00",
	"01",
	"0a",
	"17",
	"1818",
	"1864",
	"1903e8",
	"20",
	"29",
	"626869",
	"60",
	"80",
	"a0",
];

function protocolCborRoundtrip() {
	return CBOR_ROUNDTRIP_HEX.map((hex) => {
		const octets = Uint8Array.from(Buffer.from(hex, "hex"));
		const value = cborModule.decodeCbor(octets);
		const encoded = cborModule.encodeCbor(value);
		return Buffer.from(encoded).toString("hex");
	});
}

const AGENT_SCHEMA_TOOL = {
	name: "edit",
	description: "Edit",
	parameters: {
		type: "object",
		properties: {
			path: { type: "string", minLength: 1 },
			edits: {
				type: "array",
				minItems: 1,
				items: {
					type: "object",
					properties: {
						oldText: { type: "string" },
						newText: { type: "string" },
					},
					required: ["oldText", "newText"],
					additionalProperties: false,
				},
			},
		},
		required: ["path", "edits"],
		additionalProperties: false,
	},
};

function agentSchemaGoodArguments() {
	return {
		path: "README.md",
		edits: [{ oldText: "old", newText: "new" }],
	};
}

function agentSchemaBadArguments() {
	return {
		path: "README.md",
		edits: [{ oldText: "old" }],
	};
}

function agentSchemaValidateOkFail() {
	validationModule.validateToolArguments(AGENT_SCHEMA_TOOL, {
		type: "toolCall",
		id: "call-1",
		name: "edit",
		arguments: agentSchemaGoodArguments(),
	});
	try {
		validationModule.validateToolArguments(AGENT_SCHEMA_TOOL, {
			type: "toolCall",
			id: "call-2",
			name: "edit",
			arguments: agentSchemaBadArguments(),
		});
		return 0;
	} catch {
		return 1;
	}
}

async function ingestJsonlFromSessionJsonl(sessionsRoot) {
	const raw = sessionModule.loadEntriesFromFile(sessionFixturePath);
	const header = raw[0];
	if (!header || header.type !== "session") {
		throw new Error("session.jsonl is missing a session header");
	}
	mkdirSync(sessionsRoot, { recursive: true });
	const repo = new jsonlModule.JsonlSessionRepo({
		fs: sqliteEnv(scratch),
		sessionsRoot,
	});
	const session = await repo.create({ cwd: resolvedJournalCwd, id: header.id });
	for (const entry of raw.slice(1)) {
		await session.appendEntry(provisionedFromV3(entry), "main");
	}
	const metadata = await session.getMetadata();
	const ingested = raw.length - 1;
	const sourceLeafId = raw[raw.length - 1].id;
	return { repo, metadata, ingested, sourceLeafId, sessionId: header.id };
}

async function jsonlOpenReadWalk(repo, metadata) {
	const session = await repo.open(metadata);
	const entries = await session.findEntries({ order: "oldestFirst" });
	const leafId = await session.getLeafId();
	const branch = leafId === null ? [] : await session.findEntriesOnBranch({ start: leafId });
	return { entryCount: entries.length, leafId, branchEntryCount: branch.length };
}

const PROTOCOL_CODEC_LIST_REQUEST = {
	type: "request",
	id: "request-1",
	request: { command: "list" },
};

function protocolCodecRoundtrip() {
	const frame = protocolCodecModule.encodeClientMessage(PROTOCOL_CODEC_LIST_REQUEST);
	const decoder = protocolCodecModule.createClientMessageDecoder();
	const messages = decoder.push(frame);
	decoder.end();
	const decoded = messages[0] || {};
	const request = decoded.request || {};
	return {
		frame_bytes: frame.byteLength,
		message_count: messages.length,
		type: decoded.type || "",
		id: decoded.id || "",
		command: request.command || "",
	};
}

const AGENT_PROXY_EVENTS = [
	{ type: "start" },
	{ type: "text_start", contentIndex: 0 },
	{ type: "text_delta", contentIndex: 0, delta: "ok" },
	{ type: "text_end", contentIndex: 0 },
	{
		type: "done",
		reason: "stop",
		usage: {
			input: 1,
			output: 2,
			cacheRead: 0,
			cacheWrite: 0,
			totalTokens: 3,
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
		},
	},
];

const AGENT_PROXY_SSE_BODY = AGENT_PROXY_EVENTS.map(
	(event) => `data: ${JSON.stringify(event)}\n\n`,
).join("");

const AGENT_PROXY_MODEL = {
	id: "proxy",
	name: "proxy",
	api: "openai-responses",
	provider: "openai",
	baseUrl: "https://example.invalid",
	reasoning: false,
	input: ["text"],
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
	contextWindow: 1000,
	maxTokens: 100,
};

async function runAgentProxy() {
	const previousFetch = globalThis.fetch;
	globalThis.fetch = async () =>
		new Response(AGENT_PROXY_SSE_BODY, {
			status: 200,
			headers: { "Content-Type": "text/event-stream" },
		});
	try {
		const stream = proxyModule.streamProxy(
			AGENT_PROXY_MODEL,
			{
				systemPrompt: "system",
				messages: [{ role: "user", content: "hi", timestamp: 0 }],
			},
			{ authToken: "secret", proxyUrl: "https://proxy.invalid" },
		);
		let eventCount = 0;
		for await (const event of stream) {
			if (event) eventCount += 1;
		}
		const result = await stream.result();
		const textBlock = result.content.find((block) => block.type === "text");
		return {
			event_count: eventCount,
			text: textBlock && "text" in textBlock ? textBlock.text : "",
			usage_total: result.usage?.totalTokens ?? 0,
		};
	} finally {
		globalThis.fetch = previousFetch;
	}
}

const OAUTH_PKCE_VERIFIER = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
const OAUTH_PKCE_STATE = "goal20-oauth-state";

function base64urlEncode(bytes) {
	let binary = "";
	for (const byte of bytes) binary += String.fromCharCode(byte);
	return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

async function oauthPkceChallenge(verifier) {
	const hashBuffer = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
	return base64urlEncode(new Uint8Array(hashBuffer));
}

function openaiAuthorizationUrl(challenge, state) {
	const url = new URL("https://auth.openai.com/oauth/authorize");
	url.searchParams.set("response_type", "code");
	url.searchParams.set("client_id", "app_EMoamEEZ73f0CkXaXp7hrann");
	url.searchParams.set("redirect_uri", "http://localhost:1455/auth/callback");
	url.searchParams.set("scope", "openid profile email offline_access");
	url.searchParams.set("code_challenge", challenge);
	url.searchParams.set("code_challenge_method", "S256");
	url.searchParams.set("state", state);
	url.searchParams.set("id_token_add_organizations", "true");
	url.searchParams.set("codex_cli_simplified_flow", "true");
	url.searchParams.set("originator", "pi");
	return url.toString();
}

function anthropicAuthorizationUrl(challenge, state) {
	const params = new URLSearchParams({
		code: "true",
		client_id: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
		response_type: "code",
		redirect_uri: "http://localhost:53692/callback",
		scope:
			"org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload",
		code_challenge: challenge,
		code_challenge_method: "S256",
		state,
	});
	return `https://claude.ai/oauth/authorize?${params.toString()}`;
}

async function runOauthPkce() {
	const challenge = await oauthPkceChallenge(OAUTH_PKCE_VERIFIER);
	const openai = openaiAuthorizationUrl(challenge, OAUTH_PKCE_STATE);
	const anthropic = anthropicAuthorizationUrl(challenge, OAUTH_PKCE_STATE);
	return {
		challenge,
		openai_has_challenge: openai.includes(challenge) ? 1 : 0,
		anthropic_has_challenge: anthropic.includes(challenge) ? 1 : 0,
		openai_prefix: openai.split("?")[0],
		anthropic_prefix: anthropic.split("?")[0],
	};
}

function evalsHarnessObservation(harness, testName, score, extras = {}) {
	return {
		evalSet: "tool access",
		groupKey: `["${testName}",1]`,
		testName,
		file: "src/tool-access.eval.ts",
		harness,
		baseline: "without-tools",
		candidates: ["with-tools"],
		repetition: 1,
		outcome: "scored",
		score,
		...extras,
	};
}

function evalsHarnessObservations() {
	return [
		evalsHarnessObservation("without-tools", "create", 0, {
			totalTokens: 100,
			totalMs: 1000,
			estimatedCostUsd: 0.01,
		}),
		evalsHarnessObservation("with-tools", "create", 1, {
			totalTokens: 120,
			totalMs: 800,
			estimatedCostUsd: 0.02,
		}),
		evalsHarnessObservation("without-tools", "inspect", 1, { totalTokens: 200 }),
		evalsHarnessObservation("with-tools", "inspect", 1, { totalTokens: 180 }),
	];
}

function runEvalsHarnessSummarize() {
	const report = evalsSummaryModule.summarizeHarnessComparisons(evalsHarnessObservations());
	const comparison = report.evalSets[0]?.comparisons[0];
	const correctness = comparison?.correctness;
	return {
		eval_sets: report.evalSets.length,
		comparisons: report.evalSets[0]?.comparisons.length ?? 0,
		candidate_wins: correctness?.candidateWins ?? 0,
		ties: correctness?.ties ?? 0,
	};
}

async function measureEvalsHarness() {
	const observed = runEvalsHarnessSummarize();
	return {
		summarize: await collect("evals_harness.summarize", () => {
			return () => runEvalsHarnessSummarize();
		}),
		observed,
	};
}

async function measureOauthPkce() {
	const observed = await runOauthPkce();
	return {
		challenge_urls: await collect("oauth_pkce.challenge_urls", () => {
			return () => runOauthPkce();
		}),
		observed,
	};
}

const MODEL_DATA_GENERATED_AT = "2026-01-01T00:00:00.000Z";

function modelDataStructure() {
	return {
		anthropic: { "claude-3-opus": "anthropic-messages" },
		openai: { "gpt-4o": "openai-completions", "gpt-4o-mini": "openai-completions" },
	};
}

function modelDataFileContents() {
	return {
		"anthropic.json": '{"anthropic-messages":{"claude-3-opus":{"id":"claude-3-opus"}}}',
		"openai.json":
			'{"openai-completions":{"gpt-4o":{"id":"gpt-4o"},"gpt-4o-mini":{"id":"gpt-4o-mini"}}}',
	};
}

function runAiCryptoModelData() {
	const manifest = modelDataModule.createModelDataManifest(
		modelDataStructure(),
		modelDataFileContents(),
		MODEL_DATA_GENERATED_AT,
	);
	return {
		schema_version: manifest.schemaVersion,
		structure_hash: manifest.structureHash,
		generated_at: manifest.generatedAt,
		file_count: Object.keys(manifest.files).length,
		openai_json_hash: manifest.files["openai.json"],
		anthropic_json_hash: manifest.files["anthropic.json"],
	};
}

async function measureAiCryptoModelData() {
	const observed = runAiCryptoModelData();
	return {
		manifest: await collect("ai_crypto_model_data.manifest", () => {
			return () => runAiCryptoModelData();
		}),
		observed,
	};
}

const MODEL_MATCH_PATTERNS = [
	"goal20faux/goal20-paired-0",
	"goal20-paired-1",
	"paired-2",
	"goal20-paired-3:high",
	"does-not-exist-xyzzy",
];

function runCliModelsRest(models) {
	return MODEL_MATCH_PATTERNS.map((pattern) => {
		const result = modelResolverModule.parseModelPattern(pattern, models);
		return {
			pattern,
			id: result.model?.id ?? "",
			provider: result.model?.provider ?? "",
			thinking: result.thinkingLevel ?? "",
		};
	});
}

function cliModelsRestObserved(rows) {
	const [exact, bare, partial, scoped, missing] = rows;
	return {
		exact_id: exact.id,
		exact_provider: exact.provider,
		bare_id: bare.id,
		partial_id: partial.id,
		scoped_id: scoped.id,
		scoped_thinking: scoped.thinking,
		miss: missing.id === "" ? 1 : 0,
	};
}

async function measureCliModelsRest() {
	const runtime = await createModelRuntime();
	const models = await runtime.getAvailable();
	const observed = cliModelsRestObserved(runCliModelsRest(models));
	return {
		pattern_match: await collect("cli_models_rest.pattern_match", () => {
			return () => runCliModelsRest(models);
		}),
		observed,
	};
}

const PNG_1X1_B64 =
	"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC";
const GIF_2X3_B64 = "R0lGODlhAgADAAAAADs=";

function imageDimPair(base64, mime) {
	const dims = terminalImageModule.getImageDimensions(base64, mime);
	return { width: dims?.widthPx ?? 0, height: dims?.heightPx ?? 0 };
}

function runImageRuntime() {
	const png = imageDimPair(PNG_1X1_B64, "image/png");
	const gif = imageDimPair(GIF_2X3_B64, "image/gif");
	const miss = imageDimPair("not-an-image", "image/png");
	return {
		png_width: png.width,
		png_height: png.height,
		gif_width: gif.width,
		gif_height: gif.height,
		miss: miss.width === 0 && miss.height === 0 ? 1 : 0,
	};
}

async function measureImageRuntime() {
	const observed = runImageRuntime();
	return {
		dimensions: await collect("image_runtime.dimensions", () => {
			return () => runImageRuntime();
		}),
		observed,
	};
}

function rpcJsonlObject() {
	return {
		command: "get_state",
		id: "rpc-1",
		success: true,
		type: "response",
	};
}

function runCliPrintRpc() {
	return rpcJsonlModule.serializeJsonLine(rpcJsonlObject());
}

function measureCliPrintRpcObserved(line) {
	const newline = line.endsWith("\n") ? 1 : 0;
	return {
		line_chars: line.length,
		newline,
		payload: newline ? line.slice(0, -1) : line,
	};
}

async function measureCliPrintRpc() {
	const observed = measureCliPrintRpcObserved(runCliPrintRpc());
	return {
		jsonl_line: await collect("cli_print_rpc.jsonl_line", () => {
			return () => runCliPrintRpc();
		}),
		observed,
	};
}

function latexText(source, display) {
	return latexModule.renderLatex(source, { display }) ?? "";
}

function runTuiLatex() {
	const fracDisplay = latexText("\\frac{1}{2}", true);
	return {
		e_mc2: latexText("E = mc^2", false),
		frac_inline: latexText("\\frac{1}{2}", false),
		greek: latexText("\\alpha + \\beta \\times \\gamma", false),
		frac_display_newlines: (fracDisplay.match(/\n/g) || []).length,
		unknown_miss: latexText("\\unknowncmd{x}", false) === "" ? 1 : 0,
	};
}

async function measureTuiLatex() {
	const observed = runTuiLatex();
	return {
		render: await collect("tui_latex.render", () => {
			return () => runTuiLatex();
		}),
		observed,
	};
}

function fuzzyHit(query, text) {
	return fuzzyModule.fuzzyMatch(query, text).matches ? 1 : 0;
}

function runTuiFuzzy() {
	return {
		gpt: fuzzyHit("gpt", "gpt-4o"),
		id_suffix: fuzzyHit("4o", "gpt-4o"),
		swapped: fuzzyHit("g4", "gpt-4o"),
		miss: fuzzyHit("xyzzy", "gpt-4o"),
		empty: fuzzyHit("", "anything"),
	};
}

async function measureTuiFuzzy() {
	const observed = runTuiFuzzy();
	return {
		fuzzy_match: await collect("tui_editor_helpers.fuzzy_match", () => {
			return () => runTuiFuzzy();
		}),
		observed,
	};
}

function osc11Report(body, terminator) {
	return `\x1b]11;${body}${terminator}`;
}

function rgbTriple(color) {
	return color ? [color.r, color.g, color.b] : [-1, -1, -1];
}

function runTuiThemeOverlay() {
	const bell = "\x07";
	const st = "\x1b\\";
	const rgb = rgbTriple(
		terminalColorsModule.parseOsc11BackgroundColor(osc11Report("rgb:ffff/8000/0000", bell)),
	);
	const hex6 = rgbTriple(
		terminalColorsModule.parseOsc11BackgroundColor(osc11Report("#112233", st)),
	);
	const hex12 = rgbTriple(
		terminalColorsModule.parseOsc11BackgroundColor(osc11Report("#ffff80000000", bell)),
	);
	const miss = terminalColorsModule.parseOsc11BackgroundColor(
		`prefix${osc11Report("#112233", bell)}`,
	);
	const scheme = terminalColorsModule.parseTerminalColorSchemeReport("\x1b[?997;1n");
	return {
		rgb_r: rgb[0],
		rgb_g: rgb[1],
		rgb_b: rgb[2],
		hex6_r: hex6[0],
		hex6_g: hex6[1],
		hex6_b: hex6[2],
		hex12_r: hex12[0],
		miss: miss ? 0 : 1,
		scheme_dark: scheme === "dark" ? 1 : 0,
	};
}

async function measureTuiThemeOverlay() {
	const observed = runTuiThemeOverlay();
	return {
		osc11_bg: await collect("tui_theme_overlay.osc11_bg", () => {
			return () => runTuiThemeOverlay();
		}),
		observed,
	};
}

const ESTIMATE_EMPTY = "";
const ESTIMATE_HELLO = "hello world";
const ESTIMATE_BLOCK = "a".repeat(100);

function runAiSupportEstimate() {
	return {
		empty: estimateModule.estimateTextTokens(ESTIMATE_EMPTY),
		hello: estimateModule.estimateTextTokens(ESTIMATE_HELLO),
		block: estimateModule.estimateTextTokens(ESTIMATE_BLOCK),
	};
}

async function measureAiSupportEstimate() {
	const observed = runAiSupportEstimate();
	return {
		estimate_text: await collect("ai_support.estimate_text", () => {
			return () => runAiSupportEstimate();
		}),
		observed,
	};
}

const SELECT_LIST_THEME = {
	selectedPrefix: (text) => text,
	selectedText: (text) => text,
	description: (text) => text,
	scrollInfo: (text) => text,
	noMatch: (text) => text,
};

function selectListFixture() {
	return new selectListModule.SelectList(
		[
			{ label: "Hello", value: "hello" },
			{ label: "Help", value: "help" },
			{ label: "World", value: "world" },
		],
		5,
		SELECT_LIST_THEME,
	);
}

function runTuiSelectList() {
	const list = selectListFixture();
	list.setFilter("he");
	const heItems = list.filteredItems;
	list.setFilter("wo");
	const woItems = list.filteredItems;
	list.setFilter("zz");
	const zzItems = list.filteredItems;
	return {
		he_count: heItems.length,
		he_first: heItems[0]?.value ?? "",
		wo_count: woItems.length,
		zz_count: zzItems.length,
	};
}

async function measureTuiSelectList() {
	const observed = runTuiSelectList();
	return {
		filter: await collect("tui_select_settings_loaders.filter", () => {
			return () => runTuiSelectList();
		}),
		observed,
	};
}

const WORD_NAV_TEXT = "hello world";

function runTuiWordNavigation() {
	return {
		back_from_space: wordNavigationModule.findWordBackward(WORD_NAV_TEXT, 11),
		fwd_from_o: wordNavigationModule.findWordForward(WORD_NAV_TEXT, 5),
		back_start: wordNavigationModule.findWordBackward(WORD_NAV_TEXT, 0),
		fwd_end: wordNavigationModule.findWordForward(WORD_NAV_TEXT, WORD_NAV_TEXT.length),
	};
}

async function measureTuiWordNavigation() {
	const observed = runTuiWordNavigation();
	return {
		step: await collect("tui_word_navigation.step", () => {
			return () => runTuiWordNavigation();
		}),
		observed,
	};
}

const OVERLAY_BASE = "hello world this is a long line";
const OVERLAY_TEXT = "OVER";

function runTuiOverlay() {
	const line = tuiModule.compositeTuiLine(OVERLAY_BASE, OVERLAY_TEXT, 6, 4, 40);
	return {
		line_chars: line.length,
		visible_width: tuiUtilsModule.visibleWidth(line),
		has_reset: line.includes("\x1b[0m") ? 1 : 0,
	};
}

async function measureTuiOverlay() {
	const observed = runTuiOverlay();
	return {
		composite_line: await collect("tui_overlay.composite_line", () => {
			return () => runTuiOverlay();
		}),
		observed,
	};
}

function runTuiKillRing() {
	const empty = new killRingModule.KillRing();
	const ring = new killRingModule.KillRing();
	ring.push("aa", { prepend: false });
	ring.push("bbb", { prepend: false });
	const peekTwo = (ring.peek() || "").length;
	ring.rotate();
	const acc = new killRingModule.KillRing();
	acc.push("ab", { prepend: false });
	acc.push("c", { prepend: false, accumulate: true });
	const pre = new killRingModule.KillRing();
	pre.push("yz", { prepend: false });
	pre.push("x", { prepend: true, accumulate: true });
	return {
		empty_len: empty.length,
		ring_len: ring.length,
		peek_two: peekTwo,
		peek_rot: (ring.peek() || "").length,
		acc_append: (acc.peek() || "").length,
		acc_prepend: (pre.peek() || "").length,
	};
}

async function measureTuiKillRing() {
	const observed = runTuiKillRing();
	return {
		push_peek: await collect("tui_kill_ring.push_peek", () => {
			return () => runTuiKillRing();
		}),
		observed,
	};
}

function runTuiUndoStack() {
	const empty = new undoStackModule.UndoStack();
	const stack = new undoStackModule.UndoStack();
	const state = { text: "hello", n: 1 };
	stack.push(state);
	state.n = 99;
	stack.push({ text: "world", n: 2 });
	const afterTwo = stack.length;
	const popped = stack.pop();
	const popN = popped?.n ?? -1;
	const afterPop = stack.length;
	const first = stack.pop();
	const cloneN = first?.n ?? -1;
	stack.clear();
	return {
		empty_len: empty.length,
		after_two: afterTwo,
		pop_n: popN,
		after_pop: afterPop,
		clone_n: cloneN,
		after_clear: stack.length,
	};
}

async function measureTuiUndoStack() {
	const observed = runTuiUndoStack();
	return {
		push_pop: await collect("tui_undo_stack.push_pop", () => {
			return () => runTuiUndoStack();
		}),
		observed,
	};
}

function writeAutocompleteFixture() {
	const root = path.join(scratch, "autocomplete");
	mkdirSync(path.join(root, "src"), { recursive: true });
	writeFileSync(path.join(root, "hello.txt"), "x", "utf8");
	writeFileSync(path.join(root, "help.md"), "x", "utf8");
	writeFileSync(path.join(root, "src", "a.ts"), "x", "utf8");
	return root;
}

function makePairedAutocompleteProvider(root) {
	return new autocompleteModule.CombinedAutocompleteProvider(
		[
			{ name: "help", description: "Show help" },
			{ name: "hello", description: "Hi" },
		],
		root,
		null,
	);
}

async function runTuiAutocomplete(provider) {
	const signal = new AbortController().signal;
	const slash = await provider.getSuggestions(["/he"], 0, 3, { signal, force: false });
	const slashValues = (slash?.items ?? []).map((item) => item.value);
	const quoted = await provider.getSuggestions(['"hel'], 0, 4, { signal, force: false });
	const force = await provider.getSuggestions(["he"], 0, 2, { signal, force: true });
	const forceLabels = (force?.items ?? []).map((item) => item.label);
	const at = await provider.getSuggestions(["@he"], 0, 3, { signal, force: false });
	const applied = provider.applyCompletion(["/he"], 0, 3, { value: "help", label: "help" }, "/he");
	return {
		slash_count: slashValues.length,
		slash_help: slashValues.includes("help") ? 1 : 0,
		slash_hello: slashValues.includes("hello") ? 1 : 0,
		slash_prefix: slash?.prefix?.length ?? 0,
		quote_count: quoted?.items?.length ?? 0,
		quote_first_len: (quoted?.items?.[0]?.value ?? "").length,
		force_count: force?.items?.length ?? 0,
		force_hello: forceLabels.includes("hello.txt") ? 1 : 0,
		force_help: forceLabels.includes("help.md") ? 1 : 0,
		at_count: at?.items?.length ?? 0,
		apply_col: applied.cursorCol,
		apply_len: (applied.lines[0] ?? "").length,
	};
}

async function measureTuiAutocomplete() {
	const root = writeAutocompleteFixture();
	const provider = makePairedAutocompleteProvider(root);
	const observed = await runTuiAutocomplete(provider);
	return {
		suggest_apply: await collect("tui_autocomplete.suggest_apply", () => {
			return () => runTuiAutocomplete(provider);
		}),
		observed,
	};
}

function runTuiKeybindings() {
	const manager = new keybindingsModule.KeybindingsManager(keybindingsModule.TUI_KEYBINDINGS, {
		"tui.editor.yank": "ctrl+k",
		"tui.editor.deleteToLineEnd": "ctrl+k",
	});
	const left = manager.getKeys("tui.editor.cursorLeft");
	const hist = manager.getKeys("tui.editor.historyPrevious");
	const conflicts = manager.getConflicts();
	return {
		left_count: left.length,
		left_ctrl_b: left.includes("ctrl+b") ? 1 : 0,
		hist_count: hist.length,
		enter_submit: manager.matches("\r", "tui.input.submit") ? 1 : 0,
		tab_tab: manager.matches("\t", "tui.input.tab") ? 1 : 0,
		enter_undo: manager.matches("\r", "tui.editor.undo") ? 1 : 0,
		conflict_count: conflicts.length,
		conflict_key_len: (conflicts[0]?.key ?? "").length,
	};
}

async function measureTuiKeybindings() {
	const observed = runTuiKeybindings();
	return {
		resolve_match: await collect("tui_keybindings.resolve_match", () => {
			return () => runTuiKeybindings();
		}),
		observed,
	};
}

function runTuiStdinBuffer() {
	const buffer = new stdinBufferModule.StdinBuffer({ timeout: 50 });
	const data = [];
	const pastes = [];
	buffer.on("data", (sequence) => data.push(sequence));
	buffer.on("paste", (text) => pastes.push(text));
	buffer.process("hello");
	const helloCount = data.length;
	buffer.process("\x1b[");
	const leftover = buffer.getBuffer().length;
	buffer.process("A");
	const upLen = (data[data.length - 1] ?? "").length;
	buffer.process("\x1b[200~hi\x1b[201~x");
	const pasteLen = (pastes[0] ?? "").length;
	const tailCount = data[data.length - 1] === "x" ? 1 : 0;
	buffer.destroy();
	return {
		hello_count: helloCount,
		leftover,
		up_len: upLen,
		paste_len: pasteLen,
		tail_count: tailCount,
	};
}

async function measureTuiStdinBuffer() {
	const observed = runTuiStdinBuffer();
	return {
		process: await collect("tui_stdin_buffer.process", () => {
			return () => runTuiStdinBuffer();
		}),
		observed,
	};
}

function runTuiInputComponent() {
	const input = new inputModule.Input();
	for (const ch of "hello world") input.handleInput(ch);
	const afterInsert = input.getValue().length;
	input.handleInput("\x7f");
	const afterBs = input.getValue().length;
	input.handleInput("\x15");
	const afterKill = input.getValue().length;
	input.handleInput("\x19");
	const value = input.getValue();
	return {
		after_insert: afterInsert,
		after_bs: afterBs,
		after_kill: afterKill,
		after_yank: value.length,
		last_code: value.length ? value.charCodeAt(value.length - 1) : 0,
	};
}

async function measureTuiInputComponent() {
	const observed = runTuiInputComponent();
	return {
		edit: await collect("tui_input_component.edit", () => {
			return () => runTuiInputComponent();
		}),
		observed,
	};
}

function runTuiNativeModifiers() {
	return {
		shift: nativeModifiersModule.isNativeModifierPressed("shift") ? 1 : 0,
		control: nativeModifiersModule.isNativeModifierPressed("control") ? 1 : 0,
		option: nativeModifiersModule.isNativeModifierPressed("option") ? 1 : 0,
		command: nativeModifiersModule.isNativeModifierPressed("command") ? 1 : 0,
	};
}

async function measureTuiNativeModifiers() {
	const observed = runTuiNativeModifiers();
	return {
		pressed: await collect("tui_native_modifiers.pressed", () => {
			return () => runTuiNativeModifiers();
		}),
		observed,
	};
}

const SETTINGS_LIST_THEME = {
	label: (text) => text,
	value: (text) => text,
	description: (text) => text,
	cursor: "→ ",
	hint: (text) => text,
};

function settingsListFixture() {
	return new settingsListModule.SettingsList(
		[
			{ id: "hello", label: "Hello", currentValue: "on" },
			{ id: "help", label: "Help", currentValue: "on" },
			{ id: "world", label: "World", currentValue: "off" },
		],
		5,
		SETTINGS_LIST_THEME,
		() => {},
		() => {},
		{ enableSearch: true },
	);
}

function settingsListApplyQuery(list, query) {
	list.searchInput.setValue(query);
	list.applyFilter(query);
	return list.filteredItems;
}

function settingsListHasLabel(items, label) {
	return items.some((item) => item.label === label) ? 1 : 0;
}

function runTuiSettingsList() {
	const list = settingsListFixture();
	const he = settingsListApplyQuery(list, "he");
	const heCount = he.length;
	const heHello = settingsListHasLabel(he, "Hello");
	const heHelp = settingsListHasLabel(he, "Help");
	const heSelected = list.selectedIndex;
	const woCount = settingsListApplyQuery(list, "wo").length;
	const zzCount = settingsListApplyQuery(list, "zz").length;
	return {
		he_count: heCount,
		he_hello: heHello,
		he_help: heHelp,
		wo_count: woCount,
		zz_count: zzCount,
		he_selected: heSelected,
	};
}

async function measureTuiSettingsList() {
	const observed = runTuiSettingsList();
	return {
		apply_filter: await collect("tui_settings_list.apply_filter", () => {
			return () => runTuiSettingsList();
		}),
		observed,
	};
}

function runAiCapabilitiesShortHash() {
	return {
		empty: hashModule.shortHash(""),
		abc: hashModule.shortHash("abc"),
		cjk: hashModule.shortHash("中文😀"),
	};
}

async function measureAiCapabilitiesShortHash() {
	const observed = runAiCapabilitiesShortHash();
	return {
		short_hash: await collect("ai_capabilities.short_hash", () => {
			return () => runAiCapabilitiesShortHash();
		}),
		observed,
	};
}

const STRIP_ANSI_CSI_OSC =
	"a\x1b[31mred\x1b[0m\x1b]8;;https://example.com\x07link\x1b]8;;\x07z";

function runCliSupportStripAnsi() {
	return {
		csi_osc: ansiModule.stripAnsi(STRIP_ANSI_CSI_OSC),
		ris: ansiModule.stripAnsi("\x1bcdone"),
		single: ansiModule.stripAnsi("\x1bmok"),
		plain: ansiModule.stripAnsi("hello"),
	};
}

async function measureCliSupportStripAnsi() {
	const observed = runCliSupportStripAnsi();
	return {
		strip_ansi: await collect("cli_support.strip_ansi", () => {
			return () => runCliSupportStripAnsi();
		}),
		observed,
	};
}

function decodeHtmlOrEmpty(entity) {
	return htmlEntityModule.decodeHtmlEntity(entity) ?? "";
}

function runCliInteractiveDecodeEntity() {
	return {
		amp: decodeHtmlOrEmpty("amp"),
		lt: decodeHtmlOrEmpty("lt"),
		gt: decodeHtmlOrEmpty("gt"),
		quot: decodeHtmlOrEmpty("quot"),
		apos: decodeHtmlOrEmpty("apos"),
		hash65: decodeHtmlOrEmpty("#65"),
		miss: htmlEntityModule.decodeHtmlEntity("nope") === undefined ? 0 : 1,
	};
}

async function measureCliInteractiveDecodeEntity() {
	const observed = runCliInteractiveDecodeEntity();
	return {
		decode_entity: await collect("cli_interactive_controller.decode_entity", () => {
			return () => runCliInteractiveDecodeEntity();
		}),
		observed,
	};
}

function runCliSdkVersionNewer() {
	return {
		beta: versionCheckModule.comparePackageVersions("5.0.0-beta.20", "5.0.0-beta.9"),
		eq: versionCheckModule.comparePackageVersions("1.2.3", "1.2.3"),
		older: versionCheckModule.comparePackageVersions("1.2.3", "1.3.0"),
		newer_flag: versionCheckModule.isNewerPackageVersion("1.2.4", "1.2.3") ? 1 : 0,
		equal_flag: versionCheckModule.isNewerPackageVersion("1.2.3", "1.2.3") ? 1 : 0,
	};
}

async function measureCliSdkVersionNewer() {
	const observed = runCliSdkVersionNewer();
	return {
		version_newer: await collect("cli_sdk.version_newer", () => {
			return () => runCliSdkVersionNewer();
		}),
		observed,
	};
}

function runProviderRegistryDefs() {
	const providers = builtinProvidersModule.getBuiltinProviders();
	return {
		openai: providers.includes("openai") ? 1 : 0,
		anthropic: providers.includes("anthropic") ? 1 : 0,
		google: providers.includes("google") ? 1 : 0,
		unknown: providers.includes("no-such-provider") ? 1 : 0,
	};
}

async function measureProviderRegistryDefs() {
	const observed = runProviderRegistryDefs();
	return {
		lookup: await collect("provider_registry_defs.lookup", () => {
			return () => runProviderRegistryDefs();
		}),
		observed,
	};
}

async function measureAgentProxy() {
	const observed = await runAgentProxy();
	return {
		stream_roundtrip: await collect("agent_proxy.stream_roundtrip", () => {
			return () => runAgentProxy();
		}),
		observed,
	};
}

async function measureProtocolCodec() {
	const observed = protocolCodecRoundtrip();
	return {
		roundtrip: await collect("protocol_codec.roundtrip", () => {
			return () => protocolCodecRoundtrip();
		}),
		observed,
	};
}

async function measureHarnessStorage() {
	const sessionsRoot = path.join(scratch, "jsonl-sessions");
	const ingested = await ingestJsonlFromSessionJsonl(sessionsRoot);
	const observed = await jsonlOpenReadWalk(ingested.repo, ingested.metadata);
	return {
		open_walk: await collect("harness_storage.open_walk", () => {
			return () => jsonlOpenReadWalk(ingested.repo, ingested.metadata);
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

async function measureAgentSchema() {
	const fail = agentSchemaValidateOkFail();
	return {
		validate_ok_fail: await collect("agent_schema.validate_ok_fail", () => {
			return () => agentSchemaValidateOkFail();
		}),
		observed: {
			ok: 1,
			fail,
			tool: "edit",
		},
	};
}

async function measureProtocolCbor() {
	const hexes = protocolCborRoundtrip();
	return {
		roundtrip: await collect("protocol_cbor.roundtrip", () => {
			return () => protocolCborRoundtrip();
		}),
		observed: {
			vector_count: hexes.length,
			roundtrip_hex: hexes.join(""),
			match: hexes.every((hex, index) => hex === CBOR_ROUNDTRIP_HEX[index]) ? 1 : 0,
		},
	};
}

async function measureSessionExportHtml() {
	const dest = path.join(scratch, "export", "session.html");
	mkdirSync(path.dirname(dest), { recursive: true });
	const manager = sessionModule.SessionManager.open(sessionFixturePath);
	await exportHtmlModule.exportSessionToHtml(manager, undefined, {
		outputPath: dest,
		themeName: "dark",
	});
	const html = readFileSync(dest, "utf8");
	return {
		to_html: await collect("session_export_html.to_html", () => {
			return () =>
				exportHtmlModule.exportSessionToHtml(manager, undefined, {
					outputPath: dest,
					themeName: "dark",
				});
		}),
		observed: {
			html_chars: html.length,
			has_accent: html.includes("--accent:") ? 1 : 0,
			theme: "dark",
		},
	};
}

async function measureSessionDiscovery() {
	const dir = stageSessionDiscovery();
	const found = sessionDiscoveryProbe(dir);
	const files = readdirSync(dir).filter((name) => name.endsWith(".jsonl"));
	let sessionId = "";
	if (found) {
		const firstLine = readFileSync(found, "utf8").split("\n", 1)[0];
		sessionId = JSON.parse(firstLine).id;
	}
	return {
		header_probe: await collect("session_discovery.header_probe", () => {
			return () => sessionDiscoveryProbe(dir);
		}),
		observed: {
			file_count: files.length,
			header_count: files.length,
			found: found ? 1 : 0,
			session_id: sessionId,
			most_recent_name: found ? path.basename(found) : "",
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
process.stderr.write("goal20 pi paired paths: agent_tool_loop\n");
const agentToolLoop = await measureAgentToolLoop();
process.stderr.write("goal20 pi paired paths: session_compact\n");
const sessionCompact = await measureSessionCompact();
process.stderr.write("goal20 pi paired paths: provider_anthropic\n");
const providerAnthropic = await measureProviderAnthropic();
process.stderr.write("goal20 pi paired paths: provider_google\n");
const providerGoogle = await measureProviderGoogle();
process.stderr.write("goal20 pi paired paths: provider_bedrock\n");
const providerBedrock = await measureProviderBedrock();
process.stderr.write("goal20 pi paired paths: provider_mistral\n");
const providerMistral = await measureProviderMistral();
process.stderr.write("goal20 pi paired paths: provider_openai_responses\n");
const providerOpenaiResponses = await measureProviderOpenaiResponses();
process.stderr.write("goal20 pi paired paths: provider_azure_openai\n");
const providerAzureOpenai = await measureProviderAzureOpenai();
process.stderr.write("goal20 pi paired paths: provider_vertex\n");
const providerVertex = await measureProviderVertex();
process.stderr.write("goal20 pi paired paths: provider_codex\n");
const providerCodex = await measureProviderCodex();
process.stderr.write("goal20 pi paired paths: provider_pi_messages\n");
const providerPiMessages = await measureProviderPiMessages();
process.stderr.write("goal20 pi paired paths: cli_settings\n");
const cliSettings = await measureCliSettings();
process.stderr.write("goal20 pi paired paths: resource_loader\n");
const resourceLoader = await measureResourceLoader();
process.stderr.write("goal20 pi paired paths: package_manager\n");
const packageManager = await measurePackageManager();
process.stderr.write("goal20 pi paired paths: session_discovery\n");
const sessionDiscovery = await measureSessionDiscovery();
process.stderr.write("goal20 pi paired paths: session_export_html\n");
const sessionExportHtml = await measureSessionExportHtml();
process.stderr.write("goal20 pi paired paths: protocol_cbor\n");
const protocolCbor = await measureProtocolCbor();
process.stderr.write("goal20 pi paired paths: agent_schema\n");
const agentSchema = await measureAgentSchema();
process.stderr.write("goal20 pi paired paths: harness_storage\n");
const harnessStorage = await measureHarnessStorage();
process.stderr.write("goal20 pi paired paths: protocol_codec\n");
const protocolCodec = await measureProtocolCodec();
process.stderr.write("goal20 pi paired paths: agent_proxy\n");
const agentProxy = await measureAgentProxy();
process.stderr.write("goal20 pi paired paths: oauth_pkce\n");
const oauthPkce = await measureOauthPkce();
process.stderr.write("goal20 pi paired paths: evals_harness\n");
const evalsHarness = await measureEvalsHarness();
process.stderr.write("goal20 pi paired paths: ai_crypto_model_data\n");
const aiCryptoModelData = await measureAiCryptoModelData();
process.stderr.write("goal20 pi paired paths: cli_models_rest\n");
const cliModelsRest = await measureCliModelsRest();
process.stderr.write("goal20 pi paired paths: image_runtime\n");
const imageRuntime = await measureImageRuntime();
process.stderr.write("goal20 pi paired paths: cli_print_rpc\n");
const cliPrintRpc = await measureCliPrintRpc();
process.stderr.write("goal20 pi paired paths: tui_latex\n");
const tuiLatex = await measureTuiLatex();
process.stderr.write("goal20 pi paired paths: tui_editor_helpers\n");
const tuiEditorHelpers = await measureTuiFuzzy();
process.stderr.write("goal20 pi paired paths: tui_theme_overlay\n");
const tuiThemeOverlay = await measureTuiThemeOverlay();
process.stderr.write("goal20 pi paired paths: ai_support\n");
const aiSupport = await measureAiSupportEstimate();
process.stderr.write("goal20 pi paired paths: tui_select_settings_loaders\n");
const tuiSelectSettings = await measureTuiSelectList();
process.stderr.write("goal20 pi paired paths: tui_word_navigation\n");
const tuiWordNavigation = await measureTuiWordNavigation();
process.stderr.write("goal20 pi paired paths: tui_overlay\n");
const tuiOverlay = await measureTuiOverlay();
process.stderr.write("goal20 pi paired paths: tui_kill_ring\n");
const tuiKillRing = await measureTuiKillRing();
process.stderr.write("goal20 pi paired paths: tui_undo_stack\n");
const tuiUndoStack = await measureTuiUndoStack();
process.stderr.write("goal20 pi paired paths: tui_autocomplete\n");
const tuiAutocomplete = await measureTuiAutocomplete();
process.stderr.write("goal20 pi paired paths: tui_keybindings\n");
const tuiKeybindings = await measureTuiKeybindings();
process.stderr.write("goal20 pi paired paths: tui_stdin_buffer\n");
const tuiStdinBuffer = await measureTuiStdinBuffer();
process.stderr.write("goal20 pi paired paths: tui_input_component\n");
const tuiInputComponent = await measureTuiInputComponent();
process.stderr.write("goal20 pi paired paths: tui_native_modifiers\n");
const tuiNativeModifiers = await measureTuiNativeModifiers();
process.stderr.write("goal20 pi paired paths: tui_settings_list\n");
const tuiSettingsList = await measureTuiSettingsList();
process.stderr.write("goal20 pi paired paths: ai_capabilities\n");
const aiCapabilities = await measureAiCapabilitiesShortHash();
process.stderr.write("goal20 pi paired paths: cli_support\n");
const cliSupport = await measureCliSupportStripAnsi();
process.stderr.write("goal20 pi paired paths: cli_interactive_controller\n");
const cliInteractive = await measureCliInteractiveDecodeEntity();
process.stderr.write("goal20 pi paired paths: cli_sdk\n");
const cliSdk = await measureCliSdkVersionNewer();
process.stderr.write("goal20 pi paired paths: provider_registry_defs\n");
const providerRegistryDefs = await measureProviderRegistryDefs();
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
			"provider_anthropic.stream_roundtrip": "packages/ai/src/api/anthropic-messages.ts stream",
			"provider_google.stream_roundtrip": "packages/ai/src/api/google-generative-ai.ts stream",
			"provider_bedrock.stream_roundtrip": "packages/ai/src/api/bedrock-converse-stream.ts stream",
			"provider_mistral.stream_roundtrip": "packages/ai/src/api/mistral-conversations.ts stream",
			"provider_openai_responses.stream_roundtrip": "packages/ai/src/api/openai-responses.ts stream",
			"provider_azure_openai.stream_roundtrip": "packages/ai/src/api/azure-openai-responses.ts stream",
			"provider_vertex.stream_roundtrip": "packages/ai/src/api/google-vertex.ts stream",
			"provider_codex.stream_roundtrip": "packages/ai/src/api/openai-codex-responses.ts stream",
			"provider_pi_messages.stream_roundtrip": "packages/ai/src/api/pi-messages.ts stream",
			"cli_settings.create": "packages/coding-agent/src/core/settings-manager.ts SettingsManager.create",
			"resource_loader.reload": "packages/coding-agent/src/core/resource-loader.ts DefaultResourceLoader.reload",
			"package_manager.resolve": "packages/coding-agent/src/core/package-manager.ts DefaultPackageManager.resolve",
			"session_discovery.header_probe":
				"packages/coding-agent/src/core/session-manager.ts findMostRecentSession",
			"session_export_html.to_html":
				"packages/coding-agent/src/core/export-html/index.ts exportSessionToHtml",
			"protocol_cbor.roundtrip": "packages/protocol/src/cbor encodeCbor + decodeCbor",
			"agent_schema.validate_ok_fail":
				"packages/ai/src/utils/validation.ts validateToolArguments",
			"harness_storage.open_walk":
				"packages/agent/src/harness/session/jsonl JsonlSessionRepo.open + findEntries + findEntriesOnBranch",
			"protocol_codec.roundtrip":
				"packages/protocol/src/codec.ts encodeClientMessage + createClientMessageDecoder",
			"agent_proxy.stream_roundtrip": "packages/agent/src/proxy.ts streamProxy",
			"oauth_pkce.challenge_urls":
				"packages/ai/src/auth/oauth/pkce.ts SHA-256 challenge + openai-codex/anthropic authorize URLs",
			"evals_harness.summarize":
				"packages/evals/src/vitest-evals/summary.ts summarizeHarnessComparisons",
			"ai_crypto_model_data.manifest":
				"packages/ai/scripts/model-data.ts createModelDataManifest",
			"cli_models_rest.pattern_match":
				"packages/coding-agent/src/core/model-resolver.ts parseModelPattern",
			"image_runtime.dimensions":
				"packages/tui/src/terminal-image.ts getImageDimensions",
			"cli_print_rpc.jsonl_line":
				"packages/coding-agent/src/modes/rpc/jsonl.ts serializeJsonLine",
			"tui_latex.render": "packages/tui/src/latex.ts renderLatex",
			"tui_editor_helpers.fuzzy_match": "packages/tui/src/fuzzy.ts fuzzyMatch",
			"tui_theme_overlay.osc11_bg":
				"packages/tui/src/terminal-colors.ts parseOsc11BackgroundColor",
			"ai_support.estimate_text":
				"packages/ai/src/utils/estimate.ts estimateTextTokens",
			"tui_select_settings_loaders.filter":
				"packages/tui/src/components/select-list.ts SelectList.setFilter",
			"tui_word_navigation.step":
				"packages/tui/src/word-navigation.ts findWordBackward + findWordForward",
			"tui_overlay.composite_line":
				"packages/tui/src/tui.ts compositeTuiLine",
			"tui_kill_ring.push_peek":
				"packages/tui/src/kill-ring.ts KillRing.push + peek + rotate",
			"tui_undo_stack.push_pop":
				"packages/tui/src/undo-stack.ts UndoStack.push + pop + clear",
			"tui_autocomplete.suggest_apply":
				"packages/tui/src/autocomplete.ts CombinedAutocompleteProvider.getSuggestions + applyCompletion",
			"tui_keybindings.resolve_match":
				"packages/tui/src/keybindings.ts KeybindingsManager / getKeybindings",
			"tui_stdin_buffer.process":
				"packages/tui/src/stdin-buffer.ts StdinBuffer.process",
			"tui_input_component.edit":
				"packages/tui/src/components/input.ts Input.handleInput",
			"tui_native_modifiers.pressed":
				"packages/tui/src/native-modifiers.ts isNativeModifierPressed",
			"tui_settings_list.apply_filter":
				"packages/tui/src/components/settings-list.ts SettingsList.applyFilter",
			"ai_capabilities.short_hash": "packages/ai/src/utils/hash.ts shortHash",
			"cli_support.strip_ansi": "packages/coding-agent/src/utils/ansi.ts stripAnsi",
			"cli_interactive_controller.decode_entity":
				"packages/coding-agent/src/utils/html.ts decodeHtmlEntity",
			"cli_sdk.version_newer":
				"packages/coding-agent/src/utils/version-check.ts isNewerPackageVersion",
			"provider_registry_defs.lookup":
				"packages/ai/src/providers/all.ts getBuiltinProviders",
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
			"agent_tool_loop.roundtrip":
				"packages/agent/src/agent.ts Agent.prompt + packages/agent/src/agent-loop.ts runAgentLoop",
			"session_compact.compact":
				"packages/coding-agent/src/core/compaction/compaction.ts prepareCompaction + compact",
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
		agent_tool_loop: agentToolLoop,
		session_compact: sessionCompact,
		provider_anthropic: providerAnthropic,
		provider_google: providerGoogle,
		provider_bedrock: providerBedrock,
		provider_mistral: providerMistral,
		provider_openai_responses: providerOpenaiResponses,
		provider_azure_openai: providerAzureOpenai,
		provider_vertex: providerVertex,
		provider_codex: providerCodex,
		provider_pi_messages: providerPiMessages,
		cli_settings: cliSettings,
		resource_loader: resourceLoader,
		package_manager: packageManager,
		session_discovery: sessionDiscovery,
		session_export_html: sessionExportHtml,
		protocol_cbor: protocolCbor,
		agent_schema: agentSchema,
		harness_storage: harnessStorage,
		protocol_codec: protocolCodec,
		agent_proxy: agentProxy,
		oauth_pkce: oauthPkce,
		evals_harness: evalsHarness,
		ai_crypto_model_data: aiCryptoModelData,
		cli_models_rest: cliModelsRest,
		image_runtime: imageRuntime,
		cli_print_rpc: cliPrintRpc,
		tui_latex: tuiLatex,
		tui_editor_helpers: tuiEditorHelpers,
		tui_theme_overlay: tuiThemeOverlay,
		ai_support: aiSupport,
		tui_select_settings_loaders: tuiSelectSettings,
		tui_word_navigation: tuiWordNavigation,
		tui_overlay: tuiOverlay,
		tui_kill_ring: tuiKillRing,
		tui_undo_stack: tuiUndoStack,
		tui_autocomplete: tuiAutocomplete,
		tui_keybindings: tuiKeybindings,
		tui_stdin_buffer: tuiStdinBuffer,
		tui_input_component: tuiInputComponent,
		tui_native_modifiers: tuiNativeModifiers,
		tui_settings_list: tuiSettingsList,
		ai_capabilities: aiCapabilities,
		cli_support: cliSupport,
		cli_interactive_controller: cliInteractive,
		cli_sdk: cliSdk,
		provider_registry_defs: providerRegistryDefs,
		render_slicing: renderSlicing,
	},
};

rmSync(scratch, { recursive: true, force: true });

const text = `${JSON.stringify(result, null, 2)}\n`;
if (options.output === "-") process.stdout.write(text);
else writeFileSync(options.output, text, "utf8");
