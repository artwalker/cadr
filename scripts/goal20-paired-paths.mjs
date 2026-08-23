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
import { createHash, createHmac } from "node:crypto";
import {
	copyFileSync,
	mkdirSync,
	mkdtempSync,
	existsSync,
	readFileSync,
	readdirSync,
	realpathSync,
	rmSync,
	utimesSync,
	writeFileSync,
} from "node:fs";
import { hostname, homedir, tmpdir } from "node:os";
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
	"settings_load.project_trust": 20,
	"settings_load.config_value": 50,
	"settings_load.http_idle": 50,
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
	"oauth_pkce_device.poll": 50,
	"oauth_pkce_device.auth_json": 50,
	"oauth_pkce_device.copilot_url": 50,
	"oauth_pkce_device.cloudflare_url": 50,
	"oauth_pkce_device.radius_gateway": 50,
	"oauth_pkce_device.copilot_auth": 50,
	"cli_extensions_install.llama_url": 50,
	"cli_extensions_install.hf_token": 50,
	"cli_extensions_install.llama_catalog": 50,
	"evals_harness.summarize": 20,
	"evals_harness.group_key": 50,
	"evals_harness.artifact_persist": 3,
	"evals_harness.format": 20,
	"ai_crypto_model_data.manifest": 50,
	"ai_crypto.hmac": 50,
	"cli_models_rest.pattern_match": 50,
	"cli_models_rest.auth_command": 50,
	"image_runtime.dimensions": 50,
	"image_runtime.mime_type": 50,
	"image_runtime.lookup": 50,
	"image_runtime.dimension_note": 50,
	"image_runtime.api_provider": 50,
	"cli_print_rpc.jsonl_line": 50,
	"cli_print_rpc.jsonl_read": 50,
	"cli_print_rpc.clamp_thinking": 50,
	"cli_print_rpc.session_stats": 20,
	"tui_latex.render": 20,
	"tui_mermaid.render": 20,
	"tui_mermaid.source_box": 20,
	"tui_mermaid.transform": 20,
	"tui_editor_helpers.fuzzy_match": 50,
	"tui_theme_overlay.osc11_bg": 50,
	"ai_support.estimate_text": 50,
	"ai_support.context_overflow": 50,
	"ai_support.grammar_delta": 50,
	"ai_support.uuid_v7": 50,
	"ai_support.auth_guidance": 50,
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
	"ai_capabilities.deferred_tools": 50,
	"ai_capabilities.event_stream": 50,
	"ai_capabilities.http_proxy": 50,
	"ai_capabilities.session_resources": 50,
	"cli_support.strip_ansi": 50,
	"cli_support.normalize_path": 50,
	"cli_support.timings": 50,
	"cli_support.event_bus": 50,
	"cli_support.attribution_headers": 50,
	"cli_support.shell_config": 50,
	"cli_support.sanitize_output": 50,
	"cli_support.git_source": 50,
	"cli_support.user_agent": 50,
	"cli_support.parse_changelog": 50,
	"cli_support.experimental": 50,
	"cli_interactive_controller.decode_entity": 50,
	"cli_interactive_controller.wayland": 50,
	"cli_interactive_controller.cwd_footer": 50,
	"cli_interactive_controller.auth_type": 50,
	"cli_interactive_controller.parse_auto_theme": 50,
	"cli_interactive_controller.resolve_theme": 50,
	"cli_selectors.session_search": 50,
	"cli_selectors.key_text": 50,
	"cli_selectors.fuzzy_filter": 50,
	"cli_selectors.delete_query": 50,
	"cli_selectors.visible_slice": 50,
	"cli_selectors.move_index": 50,
	"cli_selectors.align_left_right": 50,
	"cli_selectors.fit_line": 50,
	"cli_selectors.border_line": 50,
	"cli_selectors.selected_line": 50,
	"cli_selectors.muted_line": 50,
	"cli_selectors.dim_line": 50,
	"cli_selectors.modified_cursor_key": 50,
	"cli_selectors.title_line": 50,
	"cli_selectors.overlay_title_line": 50,
	"cli_selectors.input_line": 50,
	"cli_selectors.keybinding_text": 50,
	"cli_selectors.keybinding_hint": 50,
	"cli_selectors.session_format_age": 50,
	"cli_selectors.session_record_label": 50,
	"cli_selectors.session_shorten_path": 50,
	"cli_selectors.session_quoted_search": 50,
	"cli_selectors.session_thread_records": 50,
	"cli_selectors.session_binding_label": 50,
	"cli_selectors.session_same_path": 50,
	"cli_selectors.session_quoted_p": 50,
	"cli_selectors.session_named_p": 50,
	"cli_selectors.settings_thinking_description": 50,
	"cli_selectors.settings_display_value": 50,
	"cli_selectors.settings_automatic_theme_setting": 50,
	"cli_selectors.settings_active_automatic_theme": 50,
	"cli_selectors.settings_cycle": 50,
	"cli_selectors.settings_apply_filter": 50,
	"cli_selectors.tree_entry_filtered": 50,
	"cli_selectors.tree_query_matches": 50,
	"cli_selectors.tree_entry_search_text": 50,
	"cli_selectors.tree_settings_entry_p": 50,
	"cli_selectors.tree_normalize_display_text": 50,
	"cli_selectors.tree_status_labels": 50,
	"cli_selectors.tree_shorten_path": 50,
	"cli_selectors.tree_foldable_p": 50,
	"cli_selectors.tree_tool_argument": 50,
	"cli_selectors.tree_cycle_filter": 50,
	"cli_selectors.tree_format_label_timestamp": 50,
	"cli_selectors.tree_iso_timestamp": 50,
	"cli_selectors.tree_format_tool_call": 50,
	"cli_selectors.tree_entry_display_text": 50,
	"cli_selectors.tree_prefix": 50,
	"cli_selectors.tree_visual_nodes": 50,
	"cli_selectors.tree_horizontal_viewport": 50,
	"cli_selectors.tree_help_keys": 50,
	"cli_selectors.tree_help_key": 50,
	"cli_selectors.tree_app_key_p": 50,
	"cli_selectors.tree_help_lines": 50,
	"cli_selectors.tree_active_path": 50,
	"cli_selectors.tree_nearest_visible_id": 50,
	"cli_selectors.tree_prioritize_active": 50,
	"cli_selectors.tree_entry_map": 50,
	"cli_selectors.tree_order_entries": 50,
	"cli_selectors.tree_rebuild_visible_maps": 50,
	"cli_selectors.tree_apply_filter": 50,
	"cli_selectors.tree_render_lines": 20,
	"cli_selectors.tree_move": 50,
	"cli_selectors.tree_fold_or_up": 50,
	"cli_selectors.tree_unfold_or_down": 50,
	"cli_selectors.tree_branch_segment_id": 50,
	"cli_selectors.tree_set_query": 50,
	"cli_selectors.tree_set_filter": 50,
	"cli_selectors.tree_copy_selected": 50,
	"cli_selectors.tree_toggle_label_timestamps": 50,
	"cli_selectors.tree_start_label_edit": 50,
	"cli_selectors.tree_confirm_label": 50,
	"cli_selectors.tree_cancel_label": 50,
	"cli_selectors.tree_handle_raw_input": 50,
	"cli_selectors.tree_handle_event": 50,
	"cli_selectors.tree_handle_label_event": 50,
	"cli_selectors.tree_selected_entry": 50,
	"cli_selectors.tree_selected_id": 50,
	"cli_selectors.tree_select_id": 50,
	"cli_selectors.tree_visible_ids": 50,
	"cli_selectors.project_trust_options": 50,
	"cli_selectors.trust_selector_selection": 50,
	"cli_selectors.trust_decision_description": 50,
	"cli_selectors.trust_selector_move": 50,
	"cli_selectors.trust_selector_handle_event": 50,
	"cli_selectors.trust_selector_handle_raw_input": 50,
	"cli_selectors.trust_selector_ui_state": 50,
	"websocket_stream.stream_roundtrip": 10,
	"cli_sdk.version_newer": 50,
	"cli_sdk.cache_miss": 50,
	"cli_sdk.cache_waste": 50,
	"cli_sdk.thinking_level": 50,
	"cli_sdk.session_list": 5,
	"cli_sdk.agent_session": 5,
	"cli_sdk.session_services": 5,
	"cli_sdk.model_runtime": 5,
	"provider_registry_defs.lookup": 50,
	"skill_prompt_load.build_prompt": 50,
	"cli_bootstrap_sessions.coding_tools": 50,
	"ai_runtime_faux.blocks": 50,
	"http_transport.parse_url": 50,
	"session_pipeline.session_load": 3,
	"session_pipeline.context_walk": 50,
	"storage_journal.journal_read": 5,
	"storage_journal.journal_append": 3,
	"sqlite_session.open_walk": 3,
	"tool_read.text_file": 5,
	"tool_grep.context_file": 5,
	"agent_tool_loop.roundtrip": 3,
	"agent_tool_loop.tool_path": 50,
	"agent_tool_loop.line_ending": 50,
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

// goal20-paired-paths.sh exports NO_COLOR=1 so chalk modifiers are off, but
// cadr theme-bold still emits SGR in the bench harness. Isolate chalk like
// scripts/render-diff.py so theme.bold matches selector-title-line output.
delete process.env.NO_COLOR;
process.env.FORCE_COLOR = "3";

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
const evalsTableModule = await import(
	moduleUrl("packages/evals/src/vitest-evals/harness-table.ts")
);
const evalsArtifactsModule = await import(
	moduleUrl("packages/evals/src/vitest-evals/artifacts.ts")
);
const modelDataModule = await import(moduleUrl("packages/ai/scripts/model-data.ts"));
const modelResolverModule = await import(
	moduleUrl("packages/coding-agent/src/core/model-resolver.ts")
);
const authCommandModule = await import(
	moduleUrl("packages/coding-agent/src/cli/auth-command.ts")
);
const validationModule = await import(moduleUrl("packages/ai/src/utils/validation.ts"));
const jsonlModule = await import(moduleUrl("packages/agent/src/harness/session/jsonl.ts"));
const rpcJsonlModule = await import(moduleUrl("packages/coding-agent/src/modes/rpc/jsonl.ts"));
process.env.PI_TIMING = "1";
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
const deviceCodeModule = await import(
	moduleUrl("packages/ai/src/auth/oauth/device-code.ts")
);
const githubCopilotOAuthModule = await import(
	moduleUrl("packages/ai/src/auth/oauth/github-copilot.ts")
);
const cloudflareStreamModule = await import(
	moduleUrl("packages/ai/src/providers/cloudflare-stream.ts")
);
const radiusConfigModule = await import(
	moduleUrl("packages/ai/src/providers/radius-config.ts")
);
const authStorageModule = await import(
	moduleUrl("packages/coding-agent/src/core/auth-storage.ts")
);
const llamaClientModule = await import(
	moduleUrl("packages/coding-agent/src/extensions/llama/client.ts")
);
const llamaHfModule = await import(
	moduleUrl("packages/coding-agent/src/extensions/llama/huggingface.ts")
);
const llamaProviderModule = await import(
	moduleUrl("packages/coding-agent/src/extensions/llama/provider.ts")
);
const settingsModule = await import(moduleUrl("packages/coding-agent/src/core/settings-manager.ts"));
const projectTrustModule = await import(
	moduleUrl("packages/coding-agent/src/core/project-trust.ts")
);
const resolveConfigValueModule = await import(
	moduleUrl("packages/coding-agent/src/core/resolve-config-value.ts")
);
const httpDispatcherModule = await import(
	moduleUrl("packages/coding-agent/src/core/http-dispatcher.ts")
);
const trustManagerModule = await import(
	moduleUrl("packages/coding-agent/src/core/trust-manager.ts")
);
const resourceLoaderModule = await import(moduleUrl("packages/coding-agent/src/core/resource-loader.ts"));
const packageManagerModule = await import(moduleUrl("packages/coding-agent/src/core/package-manager.ts"));
const truncateModule = await import(moduleUrl("packages/coding-agent/src/core/tools/truncate.ts"));
const readModule = await import(moduleUrl("packages/coding-agent/src/core/tools/read.ts"));
const grepModule = await import(moduleUrl("packages/coding-agent/src/core/tools/grep.ts"));
const toolPathModule = await import(moduleUrl("packages/coding-agent/src/core/tools/path-utils.ts"));
const editDiffModule = await import(moduleUrl("packages/coding-agent/src/core/tools/edit-diff.ts"));
const tuiUtilsModule = await import(moduleUrl("packages/tui/src/utils.ts"));
const terminalImageModule = await import(moduleUrl("packages/tui/src/terminal-image.ts"));
const mimeModule = await import(moduleUrl("packages/coding-agent/src/utils/mime.ts"));
const imageModelsModule = await import(moduleUrl("packages/ai/src/image-models.ts"));
const aiModelsModule = await import(moduleUrl("packages/ai/src/models.ts"));
const imageResizeModule = await import(
	moduleUrl("packages/coding-agent/src/utils/image-resize.ts")
);
const imageApiRegistryModule = await import(
	moduleUrl("packages/ai/src/images-api-registry.ts")
);
const latexModule = await import(moduleUrl("packages/tui/src/latex.ts"));
const grokMermaidModule = await import(
	pathToFileURL(path.join(baselineDirectory, "node_modules/grok-mermaid/dist/index.js")).href
);
const mermaidTransformModule = await import(
	moduleUrl("packages/coding-agent/src/modes/interactive/components/mermaid.ts")
);
const sessionSelectorSearchModule = await import(
	moduleUrl("packages/coding-agent/src/modes/interactive/components/session-selector-search.ts")
);
const keybindingHintsModule = await import(
	moduleUrl("packages/coding-agent/src/modes/interactive/components/keybinding-hints.ts")
);
const themeModule = await import(
	moduleUrl("packages/coding-agent/src/modes/interactive/theme/theme.ts")
);
const keysModule = await import(moduleUrl("packages/tui/src/keys.ts"));
const dynamicBorderModule = await import(
	moduleUrl("packages/coding-agent/src/modes/interactive/components/dynamic-border.ts")
);
const treeSelectorModule = await import(
	moduleUrl("packages/coding-agent/src/modes/interactive/components/tree-selector.ts")
);
themeModule.initTheme("dark", false);
const fuzzyModule = await import(moduleUrl("packages/tui/src/fuzzy.ts"));
const terminalColorsModule = await import(moduleUrl("packages/tui/src/terminal-colors.ts"));
const estimateModule = await import(moduleUrl("packages/ai/src/utils/estimate.ts"));
const uuidModule = await import(moduleUrl("packages/ai/src/utils/uuid.ts"));
const authGuidanceModule = await import(
	moduleUrl("packages/coding-agent/src/core/auth-guidance.ts")
);
const overflowModule = await import(moduleUrl("packages/ai/src/utils/overflow.ts"));
const grammarModule = await import(moduleUrl("packages/ai/src/api/constrained-sampling.ts"));
const selectListModule = await import(moduleUrl("packages/tui/src/components/select-list.ts"));
const wordNavigationModule = await import(moduleUrl("packages/tui/src/word-navigation.ts"));
const tuiModule = await import(moduleUrl("packages/tui/src/tui.ts"));
const killRingModule = await import(moduleUrl("packages/tui/src/kill-ring.ts"));
const undoStackModule = await import(moduleUrl("packages/tui/src/undo-stack.ts"));
const autocompleteModule = await import(moduleUrl("packages/tui/src/autocomplete.ts"));
const keybindingsModule = await import(moduleUrl("packages/tui/src/keybindings.ts"));
const appKeybindingsModule = await import(
	moduleUrl("packages/coding-agent/src/core/keybindings.ts"),
);
const stdinBufferModule = await import(moduleUrl("packages/tui/src/stdin-buffer.ts"));
const inputModule = await import(moduleUrl("packages/tui/src/components/input.ts"));
const nativeModifiersModule = await import(moduleUrl("packages/tui/src/native-modifiers.ts"));
const settingsListModule = await import(moduleUrl("packages/tui/src/components/settings-list.ts"));
const hashModule = await import(moduleUrl("packages/ai/src/utils/hash.ts"));
const deferredToolsModule = await import(
	moduleUrl("packages/ai/src/utils/deferred-tools.ts")
);
const eventStreamModule = await import(
	moduleUrl("packages/ai/src/utils/event-stream.ts")
);
const nodeHttpProxyModule = await import(
	moduleUrl("packages/ai/src/utils/node-http-proxy.ts")
);
const sessionResourcesModule = await import(
	moduleUrl("packages/ai/src/session-resources.ts")
);
const ansiModule = await import(moduleUrl("packages/coding-agent/src/utils/ansi.ts"));
const pathsModule = await import(moduleUrl("packages/coding-agent/src/utils/paths.ts"));
const timingsModule = await import(moduleUrl("packages/coding-agent/src/core/timings.ts"));
const experimentalModule = await import(moduleUrl("packages/coding-agent/src/core/experimental.ts"));
const eventBusModule = await import(moduleUrl("packages/coding-agent/src/core/event-bus.ts"));
const attributionModule = await import(
	moduleUrl("packages/coding-agent/src/core/provider-attribution.ts")
);
const shellModule = await import(moduleUrl("packages/coding-agent/src/utils/shell.ts"));
const gitModule = await import(moduleUrl("packages/coding-agent/src/utils/git.ts"));
const userAgentModule = await import(
	moduleUrl("packages/coding-agent/src/utils/pi-user-agent.ts")
);
const changelogModule = await import(
	moduleUrl("packages/coding-agent/src/utils/changelog.ts")
);
const htmlEntityModule = await import(moduleUrl("packages/coding-agent/src/utils/html.ts"));
const clipboardImageModule = await import(
	moduleUrl("packages/coding-agent/src/utils/clipboard-image.ts")
);
const footerModule = await import(
	moduleUrl("packages/coding-agent/src/modes/interactive/components/footer.ts")
);
const oauthSelectorModule = await import(
	moduleUrl("packages/coding-agent/src/modes/interactive/components/oauth-selector.ts")
);
const versionCheckModule = await import(moduleUrl("packages/coding-agent/src/utils/version-check.ts"));
const cacheStatsModule = await import(
	moduleUrl("packages/coding-agent/src/core/cache-stats.ts")
);
const builtinProvidersModule = await import(moduleUrl("packages/ai/src/providers/all.ts"));
const systemPromptModule = await import(moduleUrl("packages/coding-agent/src/core/system-prompt.ts"));
const codingToolsModule = await import(moduleUrl("packages/coding-agent/src/core/tools/index.ts"));
const fauxProviderModule = await import(moduleUrl("packages/ai/src/providers/faux.ts"));
const agentModule = await import(moduleUrl("packages/agent/src/agent.ts"));
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

function dummyProjectTrustContext(cwd) {
	return {
		cwd,
		mode: "rpc",
		hasUI: false,
		ui: {
			select: async () => undefined,
			confirm: async () => false,
			input: async () => "",
			notify: () => {},
		},
	};
}

function stageSettingsLoadTrust() {
	const empty = path.join(scratch, "trust-empty");
	const project = path.join(scratch, "trust-project");
	const agent = path.join(scratch, "trust-agent");
	mkdirSync(empty, { recursive: true });
	mkdirSync(path.join(project, ".cadr"), { recursive: true });
	mkdirSync(path.join(project, ".pi"), { recursive: true });
	mkdirSync(agent, { recursive: true });
	writeFileSync(path.join(project, ".cadr", "settings.json"), "{}", "utf8");
	writeFileSync(path.join(project, ".pi", "settings.json"), "{}", "utf8");
	return { empty, project, agent };
}

async function runSettingsLoadProjectTrust(empty, project, agent) {
	const store = new trustManagerModule.ProjectTrustStore(agent);
	const ctxEmpty = dummyProjectTrustContext(empty);
	const ctxProject = dummyProjectTrustContext(project);
	const rsEmpty = await projectTrustModule.resolveProjectTrusted({
		cwd: empty,
		trustStore: store,
		defaultProjectTrust: "ask",
		projectTrustContext: ctxEmpty,
	});
	const rsAsk = await projectTrustModule.resolveProjectTrusted({
		cwd: project,
		trustStore: store,
		defaultProjectTrust: "ask",
		projectTrustContext: ctxProject,
	});
	const rsAlways = await projectTrustModule.resolveProjectTrusted({
		cwd: project,
		trustStore: store,
		defaultProjectTrust: "always",
		projectTrustContext: ctxProject,
	});
	const rsNever = await projectTrustModule.resolveProjectTrusted({
		cwd: project,
		trustStore: store,
		defaultProjectTrust: "never",
		projectTrustContext: ctxProject,
	});
	const rsOvYes = await projectTrustModule.resolveProjectTrusted({
		cwd: project,
		trustStore: store,
		trustOverride: true,
		projectTrustContext: ctxProject,
	});
	const rsOvNo = await projectTrustModule.resolveProjectTrusted({
		cwd: project,
		trustStore: store,
		trustOverride: false,
		projectTrustContext: ctxProject,
	});
	return {
		tr_empty: trustManagerModule.hasTrustRequiringProjectResources(empty) ? 1 : 0,
		tr_proj: trustManagerModule.hasTrustRequiringProjectResources(project) ? 1 : 0,
		rs_empty: rsEmpty ? 1 : 0,
		rs_ask: rsAsk ? 1 : 0,
		rs_always: rsAlways ? 1 : 0,
		rs_never: rsNever ? 1 : 0,
		rs_ov_yes: rsOvYes ? 1 : 0,
		rs_ov_no: rsOvNo ? 1 : 0,
	};
}

function runSettingsLoadConfigValue() {
	const env = { GOAL20_CV_FOO: "bar" };
	const equals = (config, expected) =>
		resolveConfigValueModule.resolveConfigValue(config, env) === expected ? 1 : 0;
	return {
		cv_lit: equals("abc", "abc"),
		cv_dol: equals("$GOAL20_CV_FOO", "bar"),
		cv_brace: equals("${GOAL20_CV_FOO}", "bar"),
		cv_esc: equals("$$x", "$x"),
		cv_bang: equals("$!x", "!x"),
		cv_miss: resolveConfigValueModule.resolveConfigValue("$GOAL20_CV_NOPE", env) ? 0 : 1,
		cv_mix: equals("pre-$GOAL20_CV_FOO-post", "pre-bar-post"),
		cv_cmd: resolveConfigValueModule.isCommandConfigValue("!echo hi") ? 1 : 0,
	};
}

function httpIdleLabelFlag(timeoutMs, expected) {
	return httpDispatcherModule.formatHttpIdleTimeoutMs(timeoutMs) === expected ? 1 : 0;
}

function runSettingsLoadHttpIdle() {
	return {
		ht_30: httpIdleLabelFlag(30000, "30 sec"),
		ht_1m: httpIdleLabelFlag(60000, "1 min"),
		ht_2m: httpIdleLabelFlag(120000, "2 min"),
		ht_5m: httpIdleLabelFlag(300000, "5 min"),
		ht_off: httpIdleLabelFlag(0, "disabled"),
	};
}

async function measureSettingsLoad() {
	const { empty, project, agent } = stageSettingsLoadTrust();
	const trust = await runSettingsLoadProjectTrust(empty, project, agent);
	const config = runSettingsLoadConfigValue();
	const idle = runSettingsLoadHttpIdle();
	return {
		project_trust: await collect("settings_load.project_trust", () => {
			return () => runSettingsLoadProjectTrust(empty, project, agent);
		}),
		config_value: await collect("settings_load.config_value", () => {
			return () => runSettingsLoadConfigValue();
		}),
		http_idle: await collect("settings_load.http_idle", () => {
			return () => runSettingsLoadHttpIdle();
		}),
		observed: { ...trust, ...config, ...idle },
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

function toolPathFlag(cwd, path, expected) {
	return toolPathModule.resolveToCwd(path, cwd) === expected ? 1 : 0;
}

function runAgentToolLoopToolPath() {
	const cwd = "/tmp/goal20-tp/cwd";
	const nbsp = "a\u00a0b.txt";
	return {
		tp_rel: toolPathFlag(cwd, "foo.txt", "/tmp/goal20-tp/cwd/foo.txt"),
		tp_abs: toolPathFlag(cwd, "/tmp/abs/bar", "/tmp/abs/bar"),
		tp_at: toolPathFlag(cwd, "@rel.txt", "/tmp/goal20-tp/cwd/rel.txt"),
		tp_nbsp: toolPathFlag(cwd, nbsp, "/tmp/goal20-tp/cwd/a b.txt"),
		tp_parent: toolPathFlag(cwd, "../x", "/tmp/goal20-tp/x"),
	};
}

function lineEndingFlag(text, expected) {
	return editDiffModule.detectLineEnding(text) === expected ? 1 : 0;
}

function runAgentToolLoopLineEnding() {
	return {
		le_lf: lineEndingFlag("a\nb", "\n"),
		le_crlf: lineEndingFlag("a\r\nb", "\r\n"),
		le_none: lineEndingFlag("ab", "\n"),
		le_empty: lineEndingFlag("", "\n"),
	};
}

async function measureAgentToolLoop() {
	const once = await runPairedToolLoop();
	const messages = once.agent.state.messages;
	const last = messages[messages.length - 1];
	const result = messages[2];
	const paths = runAgentToolLoopToolPath();
	const endings = runAgentToolLoopLineEnding();
	return {
		roundtrip: await collect("agent_tool_loop.roundtrip", () => {
			return () => runPairedToolLoop();
		}),
		tool_path: await collect("agent_tool_loop.tool_path", () => {
			return () => runAgentToolLoopToolPath();
		}),
		line_ending: await collect("agent_tool_loop.line_ending", () => {
			return () => runAgentToolLoopLineEnding();
		}),
		observed: {
			final_text: last.content[0].text,
			message_count: messages.length,
			tool_error: result.isError ? 1 : 0,
			tool_value: once.executed.value,
			...paths,
			...endings,
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

function evalGroupKeyFlag(input, repetition, expectedId, expectedRep) {
	try {
		const parsed = JSON.parse(evalsTableModule.deriveEvalGroupKey(input, repetition));
		return Array.isArray(parsed) && parsed[0] === expectedId && parsed[1] === expectedRep ? 1 : 0;
	} catch {
		return 0;
	}
}

function runEvalsHarnessGroupKey() {
	const ok = {
		schemaVersion: 1,
		evalSet: "set-a",
		groupKey: '["case-1",1]',
		harness: "cadr",
		baseline: "base",
		candidates: ["cand"],
		repetition: 1,
	};
	const bad = { ...ok, schemaVersion: 2 };
	return {
		gk_id: evalGroupKeyFlag({ id: "case-1" }, 1, "case-1", 1),
		gk_trim: evalGroupKeyFlag({ id: "  case-2  " }, 2, "case-2", 2),
		art_ok: evalsTableModule.parseEvalHarnessIterationArtifact(ok) ? 1 : 0,
		art_bad: evalsTableModule.parseEvalHarnessIterationArtifact(bad) ? 1 : 0,
	};
}

const evalArtifactDirectory = path.join(scratch, "eval-artifacts");

async function runEvalsHarnessArtifactPersist() {
	mkdirSync(evalArtifactDirectory, { recursive: true });
	const refs = await evalsArtifactsModule.persistEvalArtifactReferences(
		[
			{
				type: "@earendil-works/pi-evals:session",
				runId: "run-1",
				attachments: [
					{
						name: "session.jsonl",
						contentType: "application/jsonl",
						body: "session-body",
						bodyEncoding: "utf-8",
					},
				],
			},
			{
				type: "@earendil-works/pi-evals:source",
				runId: "run-1",
				attachments: [
					{
						name: "source.txt",
						contentType: "text/plain",
						body: "source-body",
						bodyEncoding: "utf-8",
					},
				],
			},
		],
		"run-1",
		evalArtifactDirectory,
	);
	const session = refs.find((ref) => ref.name === "session.jsonl");
	const source = refs.find((ref) => ref.name === "source.txt");
	const exists = (relative) => (relative && existsSync(path.join(evalArtifactDirectory, relative)) ? 1 : 0);
	return {
		ap_n: refs.length,
		ap_sess: session ? 1 : 0,
		ap_src: source ? 1 : 0,
		ap_sess_prefix: session?.path.startsWith("sessions/") ? 1 : 0,
		ap_src_prefix: source?.path.startsWith("sources/") ? 1 : 0,
		ap_sess_file: exists(session?.path),
		ap_src_file: exists(source?.path),
	};
}

function evalsFormatFlags(text) {
	const stripped = ansiModule.stripAnsi(text);
	return {
		empty: stripped === "" ? 1 : 0,
		hdr: stripped.includes("Eval Comparisons") ? 1 : 0,
		base: stripped.includes("Baseline") ? 1 : 0,
		pass: stripped.includes("Pass rate") ? 1 : 0,
	};
}

function runEvalsHarnessFormat(emptyReport, report) {
	const empty = evalsFormatFlags(
		evalsSummaryModule.formatHarnessComparisonReport(emptyReport),
	);
	const full = evalsFormatFlags(
		evalsSummaryModule.formatHarnessComparisonReport(report),
	);
	return {
		fmt_empty: empty.empty,
		fmt_empty_hdr: empty.hdr,
		fmt_hdr: full.hdr,
		fmt_base: full.base,
		fmt_pass: full.pass,
	};
}

async function measureEvalsHarness() {
	const emptyReport = evalsSummaryModule.summarizeHarnessComparisons([]);
	const report = evalsSummaryModule.summarizeHarnessComparisons(
		evalsHarnessObservations(),
	);
	const observed = {
		...runEvalsHarnessSummarize(),
		...runEvalsHarnessGroupKey(),
		...(await runEvalsHarnessArtifactPersist()),
		...runEvalsHarnessFormat(emptyReport, report),
	};
	return {
		summarize: await collect("evals_harness.summarize", () => {
			return () => runEvalsHarnessSummarize();
		}),
		group_key: await collect("evals_harness.group_key", () => {
			return () => runEvalsHarnessGroupKey();
		}),
		artifact_persist: await collect("evals_harness.artifact_persist", () => {
			return () => runEvalsHarnessArtifactPersist();
		}),
		format: await collect("evals_harness.format", () => {
			return () => evalsSummaryModule.formatHarnessComparisonReport(report);
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

function liveAbortSignal() {
	return new AbortController().signal;
}

async function runOauthPkceDevicePoll() {
	const ok = await deviceCodeModule.pollOAuthDeviceCodeFlow({
		intervalSeconds: 5,
		expiresInSeconds: 900,
		poll: async () => ({ status: "complete", value: "tok" }),
		signal: liveAbortSignal(),
	});
	let fail = 0;
	try {
		await deviceCodeModule.pollOAuthDeviceCodeFlow({
			intervalSeconds: 5,
			expiresInSeconds: 900,
			poll: async () => ({ status: "failed", message: "nope" }),
			signal: liveAbortSignal(),
		});
	} catch {
		fail = 1;
	}
	let cancel = 0;
	const aborted = new AbortController();
	aborted.abort();
	try {
		await deviceCodeModule.pollOAuthDeviceCodeFlow({
			intervalSeconds: 5,
			expiresInSeconds: 900,
			poll: async () => ({ status: "pending" }),
			signal: aborted.signal,
		});
	} catch {
		cancel = 1;
	}
	return {
		dc_ok: ok === "tok" ? 1 : 0,
		dc_fail: fail,
		dc_cancel: cancel,
	};
}

const OAUTH_AUTH_JSON_FIXTURE =
	'{"openai":{"type":"api_key","key":"sk-test"},"anthropic":{"type":"oauth","access":"acc","refresh":"ref","expires":9999999999}}';

function writeOauthAuthJsonFile(name, text) {
	const root = path.join(scratch, "oauth-auth-json");
	mkdirSync(root, { recursive: true });
	const filePath = path.join(root, name);
	writeFileSync(filePath, text, "utf8");
	return filePath;
}

async function runOauthPkceDeviceAuthJson() {
	const good = writeOauthAuthJsonFile("auth.json", OAUTH_AUTH_JSON_FIXTURE);
	const bad = writeOauthAuthJsonFile("bad.json", "[");
	const storage = new authStorageModule.ReadOnlyAuthStorage(good);
	const ak = await storage.read("openai");
	const oa = await storage.read("anthropic");
	const miss = await storage.read("github");
	let authBad = 0;
	try {
		await new authStorageModule.ReadOnlyAuthStorage(bad).read("openai");
	} catch {
		authBad = 1;
	}
	return {
		ak_ok: ak?.type === "api_key" ? 1 : 0,
		ak_len: ak?.type === "api_key" && typeof ak.key === "string" && ak.key.length === 7 ? 1 : 0,
		oa_ok: oa?.type === "oauth" ? 1 : 0,
		oa_len: oa?.type === "oauth" && typeof oa.access === "string" && oa.access.length === 3 ? 1 : 0,
		auth_miss: miss ? 0 : 1,
		auth_bad: authBad,
	};
}

function copilotOauthCredential(access, enterpriseUrl) {
	return {
		type: "oauth",
		access,
		refresh: "r",
		expires: 1,
		...(enterpriseUrl ? { enterpriseUrl } : {}),
	};
}

async function runOauthPkceDeviceCopilotUrl() {
	const toAuth = githubCopilotOAuthModule.githubCopilotOAuth.toAuth;
	const def = await toAuth(copilotOauthCredential(""));
	const ind = await toAuth(
		copilotOauthCredential("tid=test;exp=1;proxy-ep=proxy.individual.githubcopilot.com;"),
	);
	const ent = await toAuth(
		copilotOauthCredential("tid=test;exp=1;proxy-ep=proxy.enterprise.githubcopilot.com;"),
	);
	const dom = await toAuth(copilotOauthCredential("", "example.com"));
	return {
		gc_def: def.baseUrl === "https://api.individual.githubcopilot.com" ? 1 : 0,
		gc_ind: ind.baseUrl === "https://api.individual.githubcopilot.com" ? 1 : 0,
		gc_ent: ent.baseUrl === "https://api.enterprise.githubcopilot.com" ? 1 : 0,
		gc_dom: dom.baseUrl === "https://copilot-api.example.com" ? 1 : 0,
	};
}

async function runOauthPkceDeviceCopilotAuth() {
	const toAuth = githubCopilotOAuthModule.githubCopilotOAuth.toAuth;
	const def = await toAuth(copilotOauthCredential(""));
	const ind = await toAuth(
		copilotOauthCredential("tid=test;exp=1;proxy-ep=proxy.individual.githubcopilot.com;"),
	);
	const ent = await toAuth(
		copilotOauthCredential("tid=test;exp=1;proxy-ep=proxy.enterprise.githubcopilot.com;"),
	);
	const dom = await toAuth(copilotOauthCredential("", "example.com"));
	const keyed = await toAuth(copilotOauthCredential("tok"));
	return {
		ga_def: def.baseUrl === "https://api.individual.githubcopilot.com" ? 1 : 0,
		ga_ind: ind.baseUrl === "https://api.individual.githubcopilot.com" ? 1 : 0,
		ga_ent: ent.baseUrl === "https://api.enterprise.githubcopilot.com" ? 1 : 0,
		ga_dom: dom.baseUrl === "https://copilot-api.example.com" ? 1 : 0,
		ga_key: keyed.apiKey === "tok" ? 1 : 0,
	};
}

const CLOUDFLARE_GATEWAY_TEMPLATE =
	"https://gateway.ai.cloudflare.com/v1/{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}/openai";

function cloudflareModel(baseUrl) {
	return {
		id: "cf",
		name: "cf",
		api: "openai-completions",
		provider: "cloudflare-ai-gateway",
		baseUrl,
		reasoning: false,
		input: ["text"],
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		contextWindow: 1,
		maxTokens: 1,
	};
}

function runOauthPkceDeviceCloudflareUrl() {
	const env = { CLOUDFLARE_ACCOUNT_ID: "acct", CLOUDFLARE_GATEWAY_ID: "gw" };
	const plain = cloudflareStreamModule.resolveCloudflareModel(
		cloudflareModel("https://api.example.com/v1"),
		env,
	);
	const ok = cloudflareStreamModule.resolveCloudflareModel(
		cloudflareModel(CLOUDFLARE_GATEWAY_TEMPLATE),
		env,
	);
	const gw = cloudflareStreamModule.resolveCloudflareModel(
		cloudflareModel("https://x/{CLOUDFLARE_GATEWAY_ID}"),
		env,
	);
	return {
		cf_plain: plain.baseUrl === "https://api.example.com/v1" ? 1 : 0,
		cf_ok: ok.baseUrl === "https://gateway.ai.cloudflare.com/v1/acct/gw/openai" ? 1 : 0,
		cf_gw: gw.baseUrl === "https://x/gw" ? 1 : 0,
	};
}

function runOauthPkceDeviceRadiusGateway() {
	const equals = (value, expected) =>
		radiusConfigModule.normalizeRadiusGatewayUrl(value) === expected ? 1 : 0;
	return {
		rg_slash: equals("https://radius.example.com/", "https://radius.example.com"),
		rg_plain: equals("https://radius.example.com", "https://radius.example.com"),
		rg_http: equals("http://localhost:8080/", "http://localhost:8080"),
	};
}

async function measureOauthPkceDevice() {
	const poll = await runOauthPkceDevicePoll();
	const auth = await runOauthPkceDeviceAuthJson();
	const copilot = await runOauthPkceDeviceCopilotUrl();
	const cloudflare = runOauthPkceDeviceCloudflareUrl();
	const radius = runOauthPkceDeviceRadiusGateway();
	const copilotAuth = await runOauthPkceDeviceCopilotAuth();
	return {
		poll: await collect("oauth_pkce_device.poll", () => {
			return () => runOauthPkceDevicePoll();
		}),
		auth_json: await collect("oauth_pkce_device.auth_json", () => {
			return () => runOauthPkceDeviceAuthJson();
		}),
		copilot_url: await collect("oauth_pkce_device.copilot_url", () => {
			return () => runOauthPkceDeviceCopilotUrl();
		}),
		cloudflare_url: await collect("oauth_pkce_device.cloudflare_url", () => {
			return () => runOauthPkceDeviceCloudflareUrl();
		}),
		radius_gateway: await collect("oauth_pkce_device.radius_gateway", () => {
			return () => runOauthPkceDeviceRadiusGateway();
		}),
		copilot_auth: await collect("oauth_pkce_device.copilot_auth", () => {
			return () => runOauthPkceDeviceCopilotAuth();
		}),
		observed: { ...poll, ...auth, ...copilot, ...cloudflare, ...radius, ...copilotAuth },
	};
}

function llamaUrlOk(value, expected) {
	try {
		return llamaClientModule.normalizeLlamaServerUrl(value) === expected ? 1 : 0;
	} catch {
		return 0;
	}
}

function llamaUrlError(value) {
	try {
		llamaClientModule.normalizeLlamaServerUrl(value);
		return 0;
	} catch {
		return 1;
	}
}

function runCliExtensionsLlamaUrl() {
	let infOk = 0;
	try {
		infOk =
			llamaClientModule.llamaInferenceUrl("http://127.0.0.1:8080/v1/") ===
			"http://127.0.0.1:8080/v1"
				? 1
				: 0;
	} catch {
		infOk = 0;
	}
	return {
		nu_local: llamaUrlOk("http://127.0.0.1:8080/v1/", "http://127.0.0.1:8080"),
		nu_https: llamaUrlOk("https://example.com/foo/v1?x=1#h", "https://example.com/foo"),
		nu_file: llamaUrlError("file:///tmp/llama"),
		inf_ok: infOk,
		fb_b: llamaClientModule.formatBytes(512) === "512 B" ? 1 : 0,
		fb_k: llamaClientModule.formatBytes(1024).includes("KiB") ? 1 : 0,
	};
}

function ensureHfLookupFixtures() {
	const root = path.join(scratch, "hf-lookup");
	const emptyHome = path.join(root, "empty-home");
	const hfHome = path.join(root, "hf-home");
	const tokenPath = path.join(root, "token-path");
	mkdirSync(emptyHome, { recursive: true });
	mkdirSync(hfHome, { recursive: true });
	writeFileSync(tokenPath, "from-path", "utf8");
	writeFileSync(path.join(hfHome, "token"), "from-home", "utf8");
	return { emptyHome, tokenPath, hfHome };
}

async function withIsolatedHome(emptyHome, thunk) {
	const previous = process.env.HOME;
	process.env.HOME = emptyHome;
	try {
		return await thunk();
	} finally {
		if (previous === undefined) delete process.env.HOME;
		else process.env.HOME = previous;
	}
}

async function runCliExtensionsHfToken() {
	const { emptyHome, tokenPath, hfHome } = ensureHfLookupFixtures();
	return withIsolatedHome(emptyHome, async () => {
		const envHit = await llamaHfModule.findHuggingFaceToken({
			HF_TOKEN: "  tok  ",
		});
		const pathHit = await llamaHfModule.findHuggingFaceToken({
			HF_TOKEN_PATH: tokenPath,
		});
		const homeHit = await llamaHfModule.findHuggingFaceToken({
			HF_HOME: hfHome,
		});
		const miss = await llamaHfModule.findHuggingFaceToken({});
		const blank = await llamaHfModule.findHuggingFaceToken({
			HF_TOKEN: "   ",
		});
		return {
			hf_env: envHit === "tok" ? 1 : 0,
			hf_path: pathHit === "from-path" ? 1 : 0,
			hf_home: homeHit === "from-home" ? 1 : 0,
			hf_miss: miss ? 0 : 1,
			hf_blank: blank ? 0 : 1,
		};
	});
}

function runCliExtensionsLlamaCatalog() {
	const controller = llamaProviderModule.createLlamaProvider();
	controller.setCatalog(
		[
			{ id: "loaded-text", status: { value: "loaded" }, meta: { n_ctx: 4096 } },
			{
				id: "loaded-img",
				status: { value: "loaded" },
				architecture: { input_modalities: ["image"] },
				meta: { n_ctx: 8192 },
			},
			{ id: "fb", status: { value: "loaded" } },
			{ id: "sleeping", status: { value: "sleeping" }, meta: { n_ctx: 4096 } },
			{ id: "unloaded", status: { value: "unloaded" } },
		],
		"http://127.0.0.1:8080/",
	);
	const models = controller.provider.getModels();
	const text = models.find((model) => model.id === "loaded-text");
	const img = models.find((model) => model.id === "loaded-img");
	const fb = models.find((model) => model.id === "fb");
	return {
		lc_n: models.length,
		lc_img: img?.input?.includes("image") ? 1 : 0,
		lc_ctx: text?.contextWindow === 4096 ? 1 : 0,
		lc_url: img?.baseUrl === "http://127.0.0.1:8080/v1" ? 1 : 0,
		lc_sleep: models.some((model) => model.id === "sleeping") ? 1 : 0,
		lc_fb: fb?.contextWindow === 128000 ? 1 : 0,
	};
}

async function measureCliExtensionsInstall() {
	const url = runCliExtensionsLlamaUrl();
	const token = await runCliExtensionsHfToken();
	const catalog = runCliExtensionsLlamaCatalog();
	return {
		llama_url: await collect("cli_extensions_install.llama_url", () => {
			return () => runCliExtensionsLlamaUrl();
		}),
		hf_token: await collect("cli_extensions_install.hf_token", () => {
			return () => runCliExtensionsHfToken();
		}),
		llama_catalog: await collect("cli_extensions_install.llama_catalog", () => {
			return () => runCliExtensionsLlamaCatalog();
		}),
		observed: { ...url, ...token, ...catalog },
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

function hmacHex(key, message) {
	return createHmac("sha256", key).update(message).digest("hex");
}

function runAiCryptoHmac() {
	return {
		fox: hmacHex("key", "The quick brown fox jumps over the lazy dog"),
		empty: hmacHex("key", ""),
		long: hmacHex("a".repeat(70), "msg"),
	};
}

async function measureAiCryptoHmac() {
	const observed = runAiCryptoHmac();
	return {
		hmac: await collect("ai_crypto.hmac", () => {
			return () => runAiCryptoHmac();
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

function authCommandErrorP(args) {
	try {
		authCommandModule.parseAuthCommand(args);
		return 0;
	} catch {
		return 1;
	}
}

function runCliModelsRestAuthCommand() {
	const skip = authCommandModule.parseAuthCommand(["models"]);
	const api = authCommandModule.parseAuthCommand([
		"auth",
		"print-api-key",
		"--provider",
		"openai",
	]);
	const bearer = authCommandModule.parseAuthCommand([
		"auth",
		"print-bearer-token",
		"--min-expiry",
		"30m",
	]);
	const check = authCommandModule.parseAuthCommand([
		"auth",
		"check",
		"--json",
		"--credentials",
		"--no-refresh",
		"--provider",
		"openai",
	]);
	return {
		ac_skip: skip ? 1 : 0,
		ac_api: api?.kind === "api_key" ? 1 : 0,
		ac_api_prov:
			api?.args?.[0] === "--provider" && api?.args?.[1] === "openai" ? 1 : 0,
		ac_bearer: bearer?.kind === "bearer_token" ? 1 : 0,
		ac_exp: bearer?.minExpiryMs ?? 0,
		ac_check: check?.kind === "check" ? 1 : 0,
		ac_json: check?.json ? 1 : 0,
		ac_cred: check?.credentials ? 1 : 0,
		ac_noref: check?.noRefresh ? 1 : 0,
		ac_chk_prov:
			check?.args?.[0] === "--provider" && check?.args?.[1] === "openai" ? 1 : 0,
		ac_min_api: authCommandErrorP([
			"auth",
			"print-api-key",
			"--min-expiry",
			"30m",
		]),
		ac_unknown: authCommandErrorP(["auth", "unknown"]),
		ac_help: authCommandModule.isAuthCommandHelp(["auth", "--help"]) ? 1 : 0,
		ac_help2: authCommandModule.isAuthCommandHelp([
			"auth",
			"print-api-key",
			"--help",
		])
			? 1
			: 0,
	};
}

async function measureCliModelsRest() {
	const runtime = await createModelRuntime();
	const models = await runtime.getAvailable();
	const observed = {
		...cliModelsRestObserved(runCliModelsRest(models)),
		...runCliModelsRestAuthCommand(),
	};
	return {
		pattern_match: await collect("cli_models_rest.pattern_match", () => {
			return () => runCliModelsRest(models);
		}),
		auth_command: await collect("cli_models_rest.auth_command", () => {
			return () => runCliModelsRestAuthCommand();
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

function mimeOrEmpty(bytes) {
	return mimeModule.detectSupportedImageMimeType(bytes) ?? "";
}

function runImageRuntimeMime() {
	return {
		png_mime: mimeOrEmpty(Buffer.from(PNG_1X1_B64, "base64")),
		jpeg_mime: mimeOrEmpty(Uint8Array.from([0xff, 0xd8, 0xff, 0xe0])),
		gif_mime: mimeOrEmpty(Buffer.from("GIF89a")),
		webp_mime: mimeOrEmpty(Buffer.from("RIFF....WEBP")),
		miss_mime: mimeOrEmpty(Buffer.from("hello")),
	};
}

function imageLookupFlag(id) {
	return imageModelsModule.getImageModel("openrouter", id) ? 1 : 0;
}

function runImageRuntimeLookup() {
	return {
		gemini: imageLookupFlag("google/gemini-2.5-flash-image"),
		flux: imageLookupFlag("black-forest-labs/flux.2-pro"),
		unknown: imageLookupFlag("nope"),
	};
}

function dimNoteResult(originalWidth, originalHeight, width, height, wasResized) {
	return {
		data: "AA==",
		mimeType: "image/png",
		originalWidth,
		originalHeight,
		width,
		height,
		wasResized,
	};
}

function dimNoteOrEmpty(result) {
	return imageResizeModule.formatDimensionNote(result) ?? "";
}

function runImageRuntimeDimensionNote() {
	return {
		note_resized: dimNoteOrEmpty(dimNoteResult(2000, 1000, 1000, 500, true)),
		note_half: dimNoteOrEmpty(dimNoteResult(1000, 800, 400, 320, true)),
		note_plain: dimNoteOrEmpty(dimNoteResult(64, 64, 64, 64, false)),
	};
}

function ensureFixtureImagesApiProvider() {
	if (imageApiRegistryModule.getImagesApiProvider("fixture-images")) return;
	imageApiRegistryModule.registerImagesApiProvider(
		{
			api: "fixture-images",
			generateImages: async () => ({
				api: "fixture-images",
				provider: "fixture",
				model: "x",
				output: [],
			}),
		},
		"goal20-pair",
	);
}

function imageApiProviderFlag(api) {
	return imageApiRegistryModule.getImagesApiProvider(api) ? 1 : 0;
}

function runImageRuntimeApiProvider() {
	ensureFixtureImagesApiProvider();
	return {
		api_fixture: imageApiProviderFlag("fixture-images"),
		api_unknown: imageApiProviderFlag("nope"),
	};
}

async function measureImageRuntime() {
	const dims = runImageRuntime();
	const mime = runImageRuntimeMime();
	const lookup = runImageRuntimeLookup();
	const notes = runImageRuntimeDimensionNote();
	const api = runImageRuntimeApiProvider();
	return {
		dimensions: await collect("image_runtime.dimensions", () => {
			return () => runImageRuntime();
		}),
		mime_type: await collect("image_runtime.mime_type", () => {
			return () => runImageRuntimeMime();
		}),
		lookup: await collect("image_runtime.lookup", () => {
			return () => runImageRuntimeLookup();
		}),
		dimension_note: await collect("image_runtime.dimension_note", () => {
			return () => runImageRuntimeDimensionNote();
		}),
		api_provider: await collect("image_runtime.api_provider", () => {
			return () => runImageRuntimeApiProvider();
		}),
		observed: { ...dims, ...mime, ...lookup, ...notes, ...api },
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

const RPC_JSONL_READ_FIXTURE = '{"id":"1"}\n{"id":"2"}\r\nlast\n';

async function runCliPrintRpcRead() {
	const lines = [];
	const stream = Readable.from([RPC_JSONL_READ_FIXTURE]);
	stream.pause();
	rpcJsonlModule.attachJsonlLineReader(stream, (line) => {
		lines.push(line);
	});
	const ended = new Promise((resolve) => {
		stream.once("end", resolve);
	});
	stream.resume();
	await ended;
	return {
		line_count: lines.length,
		first: lines[0] ?? "",
		second: lines[1] ?? "",
		last_line: lines[2] ?? "",
	};
}

function measureCliPrintRpcObserved(line, readLines) {
	const newline = line.endsWith("\n") ? 1 : 0;
	return {
		line_chars: line.length,
		newline,
		payload: newline ? line.slice(0, -1) : line,
		...readLines,
	};
}

function clampThinkingFixtureModel(thinkingLevelMap) {
	return {
		id: "goal20-clamp",
		name: "goal20-clamp",
		api: "openai-completions",
		provider: "openai",
		baseUrl: "http://localhost",
		reasoning: true,
		thinkingLevelMap,
		input: ["text"],
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		contextWindow: 128000,
		maxTokens: 4096,
	};
}

function runCliPrintRpcClampThinking() {
	const full = clampThinkingFixtureModel({ xhigh: "x", max: "m" });
	const shortened = clampThinkingFixtureModel(undefined);
	return {
		tl_off: aiModelsModule.clampThinkingLevel(full, "off"),
		tl_high: aiModelsModule.clampThinkingLevel(full, "high"),
		tl_xh: aiModelsModule.clampThinkingLevel(full, "xhigh"),
		tl_max: aiModelsModule.clampThinkingLevel(full, "max"),
		tl_xh_down: aiModelsModule.clampThinkingLevel(shortened, "xhigh"),
		tl_unk: aiModelsModule.clampThinkingLevel(full, "nope"),
		tl_full_n: aiModelsModule.getSupportedThinkingLevels(full).length,
		tl_short_n: aiModelsModule.getSupportedThinkingLevels(shortened).length,
	};
}

const RPC_STATS_SESSION_ID = "019f0000-0000-7000-8000-00000000cadr";

async function stageCliPrintRpcSessionStats() {
	const cwdDir = path.join(scratch, "rpc-stats-cwd");
	const agentDir = path.join(scratch, "rpc-stats-agent");
	mkdirSync(cwdDir, { recursive: true });
	mkdirSync(agentDir, { recursive: true });
	mkdirSync(path.join(cwdDir, ".cadr"), { recursive: true });
	mkdirSync(path.join(cwdDir, ".pi"), { recursive: true });
	const cwd = realpathSync(cwdDir);
	const resolvedAgent = realpathSync(agentDir);
	const dest = path.join(scratch, "rpc-stats", "session.jsonl");
	rewriteSessionJsonlCwd(path.join(fixtureDirectory, "session.jsonl"), dest, cwd);
	const settings = settingsModule.SettingsManager.create(cwd, resolvedAgent);
	const loader = new resourceLoaderModule.DefaultResourceLoader({
		cwd,
		agentDir: resolvedAgent,
		settingsManager: settings,
	});
	await loader.reload();
	const modelRuntime = await modelRuntimeModule.ModelRuntime.create({
		authPath: path.join(resolvedAgent, "auth.json"),
		modelsPath: path.join(resolvedAgent, "models.json"),
	});
	const sessionManager = sessionModule.SessionManager.open(dest, path.dirname(dest), cwd);
	const { getModel } = await import(moduleUrl("packages/ai/src/compat.ts"));
	const { createAgentSession } = await import(
		moduleUrl("packages/coding-agent/src/core/sdk.ts")
	);
	const model = getModel("openai", "gpt-4o-mini");
	return createAgentSession({
		cwd,
		agentDir: resolvedAgent,
		settingsManager: settings,
		resourceLoader: loader,
		modelRuntime,
		sessionManager,
		model,
		noTools: "all",
	});
}

function measureCliPrintRpcSessionStatsObserved(stats) {
	return {
		ss_user: stats.userMessages,
		ss_asst: stats.assistantMessages,
		ss_tool: stats.toolResults,
		ss_calls: stats.toolCalls,
		ss_total: stats.totalMessages,
		ss_id: stats.sessionId === RPC_STATS_SESSION_ID ? 1 : 0,
	};
}

async function measureCliPrintRpc() {
	const staged = await stageCliPrintRpcSessionStats();
	try {
		const observed = {
			...measureCliPrintRpcObserved(runCliPrintRpc(), await runCliPrintRpcRead()),
			...runCliPrintRpcClampThinking(),
			...measureCliPrintRpcSessionStatsObserved(staged.session.getSessionStats()),
		};
		return {
			jsonl_line: await collect("cli_print_rpc.jsonl_line", () => {
				return () => runCliPrintRpc();
			}),
			jsonl_read: await collect("cli_print_rpc.jsonl_read", () => {
				return () => runCliPrintRpcRead();
			}),
			clamp_thinking: await collect("cli_print_rpc.clamp_thinking", () => {
				return () => runCliPrintRpcClampThinking();
			}),
			session_stats: await collect("cli_print_rpc.session_stats", () => {
				return () => staged.session.getSessionStats();
			}),
			observed,
		};
	} finally {
		staged.session?.dispose();
	}
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

const MERMAID_LR = "flowchart LR\n  A-->B";
const MERMAID_CJK = "flowchart LR\n  A[你好世界]-->B[测试]";

function mermaidArt(src) {
	return grokMermaidModule.render(src);
}

function runTuiMermaid() {
	const lr = mermaidArt(MERMAID_LR);
	const empty = mermaidArt("");
	const unk = mermaidArt("notadiagram");
	const cjk = mermaidArt(MERMAID_CJK);
	return {
		mm_lr_w: lr ? lr.width : 0,
		mm_lr_first: lr && Array.isArray(lr.plain) ? (lr.plain[0] ?? "") : "",
		mm_lr_rows: lr && Array.isArray(lr.plain) ? lr.plain.length : 0,
		mm_empty: empty ? 0 : 1,
		mm_unk: unk ? 0 : 1,
		mm_cjk_w: cjk ? cjk.width : 0,
	};
}

function mermaidBox(src, maxWidth) {
	return grokMermaidModule.sourceBox(src, maxWidth);
}

function runTuiMermaidSourceBox() {
	const wide = mermaidBox(MERMAID_LR, 80);
	const narrow = mermaidBox(MERMAID_LR, 12);
	const empty = mermaidBox("", 80);
	return {
		sb_wide_w: wide ? wide.width : 0,
		sb_wide_first: wide && Array.isArray(wide.plain) ? (wide.plain[0] ?? "") : "",
		sb_narrow_rows: narrow && Array.isArray(narrow.plain) ? narrow.plain.length : 0,
		sb_empty_w: empty ? empty.width : 0,
	};
}

const MERMAID_MD = "```mermaid\nflowchart LR\n  A-->B\n```\n";

function mermaidTransformContext(over = {}) {
	return {
		messageType: "assistant",
		isStreaming: false,
		availableWidth: 80,
		...over,
	};
}

function runTuiMermaidTransform() {
	const streaming = mermaidTransformModule.createMermaidMarkdownTransformer({
		getMode: () => "streaming",
	});
	const off = mermaidTransformModule.createMermaidMarkdownTransformer({
		getMode: () => "off",
	});
	const ok = streaming(MERMAID_MD, mermaidTransformContext());
	const offOut = off(MERMAID_MD, mermaidTransformContext());
	const think = streaming(
		MERMAID_MD,
		mermaidTransformContext({ messageType: "assistant-thinking" }),
	);
	const wide = streaming(MERMAID_MD, mermaidTransformContext({ availableWidth: 5 }));
	return {
		tf_ok: ok.startsWith("`") && !ok.includes("```mermaid") ? 1 : 0,
		tf_art: ok.includes("──") ? 1 : 0,
		tf_off: offOut === MERMAID_MD ? 1 : 0,
		tf_think: think === MERMAID_MD ? 1 : 0,
		tf_wide: wide === MERMAID_MD ? 1 : 0,
		tf_len: ok.length,
	};
}

async function measureTuiMermaid() {
	const observed = {
		...runTuiMermaid(),
		...runTuiMermaidSourceBox(),
		...runTuiMermaidTransform(),
	};
	return {
		render: await collect("tui_mermaid.render", () => {
			return () => runTuiMermaid();
		}),
		source_box: await collect("tui_mermaid.source_box", () => {
			return () => runTuiMermaidSourceBox();
		}),
		transform: await collect("tui_mermaid.transform", () => {
			return () => runTuiMermaidTransform();
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

function overflowErrorMessage(errorMessage) {
	return {
		role: "assistant",
		content: [],
		api: "openai-completions",
		provider: "ollama",
		model: "qwen",
		usage: {
			input: 0,
			output: 0,
			cacheRead: 0,
			cacheWrite: 0,
			totalTokens: 0,
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
		},
		stopReason: "error",
		errorMessage,
		timestamp: 0,
	};
}

function overflowUsageMessage(stopReason, input, output) {
	return {
		role: "assistant",
		content: [],
		api: "openai-completions",
		provider: "ollama",
		model: "qwen",
		usage: {
			input,
			output,
			cacheRead: 0,
			cacheWrite: 0,
			totalTokens: input + output,
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
		},
		stopReason,
		timestamp: 0,
	};
}

function runAiSupportContextOverflow() {
	return {
		prompt: overflowModule.isContextOverflow(overflowErrorMessage("prompt is too long")) ? 1 : 0,
		rate: overflowModule.isContextOverflow(overflowErrorMessage("rate limit")) ? 1 : 0,
		silent: overflowModule.isContextOverflow(overflowUsageMessage("stop", 100, 0), 50) ? 1 : 0,
		length: overflowModule.isContextOverflow(overflowUsageMessage("length", 100, 0), 100) ? 1 : 0,
	};
}

function runAiSupportGrammarDelta() {
	const buffer = { input: "", started: false, closed: false };
	const d1 = grammarModule.appendGrammarToolInputJsonDelta(buffer, "input", "hel", false) ?? "";
	const d2 = grammarModule.appendGrammarToolInputJsonDelta(buffer, "input", "hello", false) ?? "";
	const d3 = grammarModule.appendGrammarToolInputJsonDelta(buffer, "input", "hello", true) ?? "";
	return {
		d1,
		d2,
		d3,
		started: buffer.started ? 1 : 0,
		closed: buffer.closed ? 1 : 0,
	};
}

function uuidV7Shape(id) {
	return {
		uuid_len: id.length,
		uuid_hyphens: (id.match(/-/g) || []).length,
		uuid_version: id[14] === "7" ? 7 : 0,
		uuid_variant: "89ab".includes(id[19]) ? 1 : 0,
	};
}

function runAiSupportUuidV7() {
	const first = uuidModule.uuidv7();
	const second = uuidModule.uuidv7();
	return {
		...uuidV7Shape(first),
		uuid_neq: first === second ? 0 : 1,
	};
}

async function measureAiSupportEstimate() {
	const estimate = runAiSupportEstimate();
	const overflow = runAiSupportContextOverflow();
	const grammar = runAiSupportGrammarDelta();
	const uuid = runAiSupportUuidV7();
	const auth = runAiSupportAuthGuidance();
	return {
		estimate_text: await collect("ai_support.estimate_text", () => {
			return () => runAiSupportEstimate();
		}),
		context_overflow: await collect("ai_support.context_overflow", () => {
			return () => runAiSupportContextOverflow();
		}),
		grammar_delta: await collect("ai_support.grammar_delta", () => {
			return () => runAiSupportGrammarDelta();
		}),
		uuid_v7: await collect("ai_support.uuid_v7", () => {
			return () => runAiSupportUuidV7();
		}),
		auth_guidance: await collect("ai_support.auth_guidance", () => {
			return () => runAiSupportAuthGuidance();
		}),
		observed: { ...estimate, ...overflow, ...grammar, ...uuid, ...auth },
	};
}

function authPrefix(text, count) {
	return text.length >= count ? text.slice(0, count) : text;
}

function runAiSupportAuthGuidance() {
	const models = authGuidanceModule.formatNoModelsAvailableMessage();
	const selected = authGuidanceModule.formatNoModelSelectedMessage();
	const key = authGuidanceModule.formatNoApiKeyFoundMessage("openai");
	const unknown = authGuidanceModule.formatNoApiKeyFoundMessage("unknown");
	return {
		no_models: authPrefix(models, 21),
		no_selected: authPrefix(selected, 18),
		no_key: authPrefix(key, 28),
		no_unknown: authPrefix(unknown, 40),
		has_login: models.includes("Use /login") ? 1 : 0,
		has_providers: models.includes("providers.md") ? 1 : 0,
		has_models: models.includes("models.md") ? 1 : 0,
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

function deferredToolsFixture() {
	const emptyUsage = {
		input: 0,
		output: 0,
		cacheRead: 0,
		cacheWrite: 0,
		totalTokens: 0,
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
	};
	const emptySchema = { type: "object", properties: {} };
	return {
		messages: [
			{
				role: "assistant",
				content: [{ type: "toolCall", id: "1", name: "bash", arguments: {} }],
				api: "openai-completions",
				provider: "openai",
				model: "x",
				usage: emptyUsage,
				stopReason: "toolUse",
				timestamp: 0,
			},
			{
				role: "toolResult",
				toolCallId: "1",
				toolName: "bash",
				content: [],
				addedToolNames: ["read"],
				isError: false,
				timestamp: 0,
			},
		],
		tools: [
			{ name: "grep", description: "", parameters: emptySchema },
			{ name: "bash", description: "", parameters: emptySchema },
			{ name: "read", description: "", parameters: emptySchema },
		],
	};
}

function deferredToolsShape(enabled) {
	const split = deferredToolsModule.splitDeferredTools(deferredToolsFixture(), enabled);
	return {
		imm: split.immediate.length,
		def: split.deferred.size,
		first: split.immediate[0]?.name ?? "",
		second: split.immediate[1]?.name ?? "",
		read: split.deferred.has("read") ? 1 : 0,
	};
}

function runAiCapabilitiesDeferredTools() {
	const off = deferredToolsShape(false);
	const on = deferredToolsShape(true);
	return {
		off_imm: off.imm,
		off_def: off.def,
		off_first: off.first,
		off_second: off.second,
		off_read: off.read,
		on_imm: on.imm,
		on_def: on.def,
		on_first: on.first,
		on_second: on.second,
		on_read: on.read,
	};
}

async function runAiCapabilitiesEventStream() {
	const stream = new eventStreamModule.EventStream(
		(event) => event === "end",
		(event) => event,
	);
	stream.push("a");
	stream.push("b");
	stream.push("end");
	const out = [];
	for await (const event of stream) out.push(event);
	return {
		ev_first: out[0] ?? "",
		ev_second: out[1] ?? "",
		ev_third: out[2] ?? "",
		ev_result: await stream.result(),
	};
}

function resolveProxyOrEmpty(target, env) {
	try {
		const resolved = nodeHttpProxyModule.resolveHttpProxyUrlForTarget(target, env);
		return resolved ? resolved.href : "";
	} catch {
		return "ERR";
	}
}

function runAiCapabilitiesHttpProxy() {
	const hit = {
		HTTPS_PROXY: "http://proxy.local:8080/",
		NO_PROXY: "none.invalid",
	};
	const star = {
		HTTPS_PROXY: "http://proxy.local:8080/",
		NO_PROXY: "*",
	};
	const skip = {
		HTTPS_PROXY: "http://proxy.local:8080/",
		NO_PROXY: "example.com",
	};
	const keep = {
		HTTPS_PROXY: "http://proxy.local:8080/",
		NO_PROXY: "other.com",
	};
	const socks = {
		HTTPS_PROXY: "socks://127.0.0.1:1080/",
		NO_PROXY: "none.invalid",
	};
	return {
		px_hit: resolveProxyOrEmpty("https://keep.example.com/x", hit),
		px_star: resolveProxyOrEmpty("https://keep.example.com/x", star),
		px_skip: resolveProxyOrEmpty("https://example.com/x", skip),
		px_keep: resolveProxyOrEmpty("https://keep.example.com/x", keep),
		px_socks: resolveProxyOrEmpty("https://keep.example.com/x", socks) === "ERR" ? 1 : 0,
	};
}

function runAiCapabilitiesSessionResources() {
	const recorded = [];
	const unreg = sessionResourcesModule.registerSessionResourceCleanup((sessionId) => {
		recorded.push(sessionId ?? "");
	});
	sessionResourcesModule.cleanupSessionResources("sess-1");
	const n1 = recorded.length;
	unreg();
	sessionResourcesModule.cleanupSessionResources("sess-2");
	const n2 = recorded.length;
	const unregErr = sessionResourcesModule.registerSessionResourceCleanup(() => {
		throw new Error("boom");
	});
	let err = 0;
	try {
		sessionResourcesModule.cleanupSessionResources("sess-err");
	} catch {
		err = 1;
	} finally {
		unregErr();
	}
	return {
		sr_first: recorded[0] ?? "",
		sr_n1: n1,
		sr_n2: n2,
		sr_err: err,
	};
}

async function measureAiCapabilitiesShortHash() {
	const hash = runAiCapabilitiesShortHash();
	const deferred = runAiCapabilitiesDeferredTools();
	const events = await runAiCapabilitiesEventStream();
	const proxy = runAiCapabilitiesHttpProxy();
	const resources = runAiCapabilitiesSessionResources();
	return {
		short_hash: await collect("ai_capabilities.short_hash", () => {
			return () => runAiCapabilitiesShortHash();
		}),
		deferred_tools: await collect("ai_capabilities.deferred_tools", () => {
			return () => runAiCapabilitiesDeferredTools();
		}),
		event_stream: await collect("ai_capabilities.event_stream", () => {
			return () => runAiCapabilitiesEventStream();
		}),
		http_proxy: await collect("ai_capabilities.http_proxy", () => {
			return () => runAiCapabilitiesHttpProxy();
		}),
		session_resources: await collect("ai_capabilities.session_resources", () => {
			return () => runAiCapabilitiesSessionResources();
		}),
		observed: { ...hash, ...deferred, ...events, ...proxy, ...resources },
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

function runCliSupportNormalizePath() {
	return {
		trim: pathsModule.normalizePath("  /tmp/foo  ", { trim: true, expandTilde: false }),
		at: pathsModule.normalizePath("@rel", { stripAtPrefix: true, expandTilde: false }),
		nbsp: pathsModule.normalizePath("a\u00a0b", {
			normalizeUnicodeSpaces: true,
			expandTilde: false,
		}),
		tilde: pathsModule.normalizePath("~/x", { homeDir: "/tmp/home" }),
		file: pathsModule.normalizePath("file:///tmp/z", { expandTilde: false }),
	};
}

function timingFieldMs(text, label) {
	const match = text.match(new RegExp(`  ${label}: (\\d+)ms`));
	return match ? Number(match[1]) : -1;
}

function runCliSupportTimings() {
	let now = 0;
	const originalNow = Date.now;
	Date.now = () => {
		now += 10;
		return now;
	};
	const lines = [];
	const originalError = console.error;
	console.error = (message) => {
		lines.push(String(message));
	};
	try {
		timingsModule.resetTimings();
		timingsModule.time("boot");
		timingsModule.time("load");
		timingsModule.printTimings();
	} finally {
		Date.now = originalNow;
		console.error = originalError;
	}
	const text = lines.join("\n");
	return {
		time_title: text.includes("Startup Timings: main") ? 1 : 0,
		time_boot: timingFieldMs(text, "boot"),
		time_load: timingFieldMs(text, "load"),
		time_total: timingFieldMs(text, "TOTAL"),
	};
}

function runCliSupportEventBus() {
	const recorded = [];
	const bus = eventBusModule.createEventBus();
	const originalError = console.error;
	console.error = () => {};
	try {
		const unsub = bus.on("ch", (data) => {
			recorded.push(data);
		});
		bus.emit("ch", "a");
		bus.emit("other", "b");
		const n1 = recorded.length;
		unsub();
		bus.emit("ch", "c");
		const n2 = recorded.length;
		bus.on("boom", () => {
			throw new Error("boom");
		});
		let throwOk = 0;
		try {
			bus.emit("boom", "x");
			throwOk = 1;
		} catch {
			throwOk = 0;
		}
		bus.clear();
		bus.emit("ch", "d");
		return {
			eb_first: recorded[0] ?? "",
			eb_n1: n1,
			eb_n2: n2,
			eb_n3: recorded.length,
			eb_throw: throwOk,
		};
	} finally {
		console.error = originalError;
	}
}

function attributionFlag(headers, name) {
	return headers && Object.prototype.hasOwnProperty.call(headers, name) ? 1 : 0;
}

function attributionVal(headers, name) {
	return headers && headers[name] != null ? String(headers[name]) : "";
}

function mergeAttribution(model, telemetry, sessionId, ...sources) {
	const previous = process.env.PI_TELEMETRY;
	process.env.PI_TELEMETRY = telemetry ? "1" : "0";
	try {
		return (
			attributionModule.mergeProviderAttributionHeaders(
				model,
				{ getEnableInstallTelemetry: () => telemetry },
				sessionId,
				...sources,
			) ?? {}
		);
	} finally {
		if (previous === undefined) delete process.env.PI_TELEMETRY;
		else process.env.PI_TELEMETRY = previous;
	}
}

function runCliSupportAttributionHeaders() {
	const orOn = mergeAttribution(
		{ provider: "openrouter", baseUrl: "https://openrouter.ai/api/v1" },
		true,
		undefined,
	);
	const orOff = mergeAttribution(
		{ provider: "openrouter", baseUrl: "https://openrouter.ai/api/v1" },
		false,
		undefined,
	);
	const nv = mergeAttribution(
		{ provider: "nvidia", baseUrl: "https://integrate.api.nvidia.com/v1" },
		true,
		undefined,
	);
	const cf = mergeAttribution(
		{ provider: "cloudflare-workers-ai", baseUrl: "https://api.cloudflare.com/client/v4" },
		true,
		undefined,
	);
	const oc = mergeAttribution(
		{ provider: "opencode", baseUrl: "https://opencode.ai/api" },
		false,
		"sess-1",
	);
	const ov = mergeAttribution(
		{ provider: "openrouter", baseUrl: "https://openrouter.ai/api/v1" },
		true,
		undefined,
		{ "X-OpenRouter-Title": "custom" },
	);
	return {
		at_or_ref: attributionFlag(orOn, "HTTP-Referer"),
		at_or_title: attributionFlag(orOn, "X-OpenRouter-Title"),
		at_or_cat: attributionVal(orOn, "X-OpenRouter-Categories"),
		at_or_off: attributionFlag(orOff, "HTTP-Referer"),
		at_nv: attributionFlag(nv, "X-BILLING-INVOKE-ORIGIN"),
		at_cf: attributionFlag(cf, "User-Agent"),
		at_oc_sess: attributionVal(oc, "x-opencode-session"),
		at_oc_client: attributionFlag(oc, "x-opencode-client"),
		at_ov: attributionVal(ov, "X-OpenRouter-Title"),
	};
}

function shellConfigShape(config) {
	return {
		shell: config.shell,
		arg: config.args?.[0] ?? "",
		stdin: config.commandTransport === "stdin" ? 1 : 0,
	};
}

function runCliSupportShellConfig() {
	const def = shellConfigShape(shellModule.getShellConfig());
	const custom = shellConfigShape(shellModule.getShellConfig("/bin/bash"));
	let miss = 0;
	try {
		shellModule.getShellConfig("/tmp/cadr-no-such-shell");
	} catch {
		miss = 1;
	}
	return {
		sh_def: def.shell,
		sh_arg: def.arg,
		sh_stdin: def.stdin,
		sh_custom: custom.shell,
		sh_carg: custom.arg,
		sh_cstdin: custom.stdin,
		sh_miss: miss,
	};
}

function runCliSupportSanitizeOutput() {
	return {
		sz_plain: shellModule.sanitizeBinaryOutput("hello"),
		sz_ctl: shellModule.sanitizeBinaryOutput("a\x00b\x07c"),
		sz_tnr: shellModule.sanitizeBinaryOutput("a\tb\nc\rd"),
		sz_fmt: shellModule.sanitizeBinaryOutput("x\uFFF9y"),
		sz_esc: shellModule.sanitizeBinaryOutput("p\x1bq"),
	};
}

function gitSourceShape(source) {
	const parsed = gitModule.parseGitUrl(source);
	if (!parsed) {
		return { host: "", path: "", ref: "", pin: 0 };
	}
	return {
		host: parsed.host,
		path: parsed.path,
		ref: parsed.ref ?? "",
		pin: parsed.pinned ? 1 : 0,
	};
}

function runCliSupportGitSource() {
	const https = gitSourceShape("https://github.com/user/repo@v1.0.0");
	const ssh = gitSourceShape("git:git@github.com:user/repo");
	const short = gitSourceShape("git:github.com/user/repo");
	return {
		gs_https_host: https.host,
		gs_https_path: https.path,
		gs_https_ref: https.ref,
		gs_https_pin: https.pin,
		gs_ssh_host: ssh.host,
		gs_ssh_path: ssh.path,
		gs_ssh_pin: ssh.pin,
		gs_short_host: short.host,
		gs_short_path: short.path,
		gs_bare: gitModule.parseGitUrl("git@github.com:user/repo") ? 1 : 0,
		gs_dotdot: gitModule.parseGitUrl("git:git@evil.example:../../victim/repo") ? 1 : 0,
		gs_abs: gitModule.parseGitUrl("git:git@evil.example:/absolute/repo") ? 1 : 0,
	};
}

function userAgentShape(ua) {
	return {
		ua_ver: ua.includes("1.2.3") ? 1 : 0,
		ua_paren: ua.includes("(") && ua.includes(")") ? 1 : 0,
		ua_semi: (ua.match(/;/g) || []).length,
	};
}

function runCliSupportUserAgent() {
	return userAgentShape(userAgentModule.getPiUserAgent("1.2.3"));
}

const pairedChangelogText = `# Changelog

## [0.2.0] - 2026-01-02

New.

## malformed
ignored

## 0.1.0

Old.
`;

function writePairedChangelog() {
	const changelogPath = path.join(scratch, "changelog.md");
	writeFileSync(changelogPath, pairedChangelogText, "utf8");
	return changelogPath;
}

function changelogEntryVersion(entry) {
	if (!entry) return "";
	return `${entry.major}.${entry.minor}.${entry.patch}`;
}

function experimentalFlag(value) {
	const previous = process.env.PI_EXPERIMENTAL;
	if (value === null) delete process.env.PI_EXPERIMENTAL;
	else process.env.PI_EXPERIMENTAL = value;
	try {
		return experimentalModule.areExperimentalFeaturesEnabled() ? 1 : 0;
	} finally {
		if (previous === undefined) delete process.env.PI_EXPERIMENTAL;
		else process.env.PI_EXPERIMENTAL = previous;
	}
}

function runCliSupportExperimental() {
	return {
		ex_on: experimentalFlag("1"),
		ex_empty: experimentalFlag(""),
		ex_zero: experimentalFlag("0"),
		ex_true: experimentalFlag("true"),
		ex_nil: experimentalFlag(null),
	};
}

function runCliSupportParseChangelog() {
	const changelogPath = path.join(scratch, "changelog.md");
	const entries = changelogModule.parseChangelog(changelogPath);
	const first = entries[0];
	const second = entries[1];
	const missing = changelogModule.parseChangelog(
		path.join(scratch, "no-such-changelog.md"),
	);
	return {
		cl_n: entries.length,
		cl_first: changelogEntryVersion(first),
		cl_hdr: first?.content?.includes("## [0.2.0]") ? 1 : 0,
		cl_second: changelogEntryVersion(second),
		cl_miss: missing.length,
	};
}

async function measureCliSupportStripAnsi() {
	const ansi = runCliSupportStripAnsi();
	const paths = runCliSupportNormalizePath();
	const timings = runCliSupportTimings();
	const bus = runCliSupportEventBus();
	const headers = runCliSupportAttributionHeaders();
	const shell = runCliSupportShellConfig();
	const sanitize = runCliSupportSanitizeOutput();
	const git = runCliSupportGitSource();
	const ua = runCliSupportUserAgent();
	writePairedChangelog();
	const changelog = runCliSupportParseChangelog();
	const experimental = runCliSupportExperimental();
	return {
		strip_ansi: await collect("cli_support.strip_ansi", () => {
			return () => runCliSupportStripAnsi();
		}),
		normalize_path: await collect("cli_support.normalize_path", () => {
			return () => runCliSupportNormalizePath();
		}),
		timings: await collect("cli_support.timings", () => {
			return () => runCliSupportTimings();
		}),
		event_bus: await collect("cli_support.event_bus", () => {
			return () => runCliSupportEventBus();
		}),
		attribution_headers: await collect("cli_support.attribution_headers", () => {
			return () => runCliSupportAttributionHeaders();
		}),
		shell_config: await collect("cli_support.shell_config", () => {
			return () => runCliSupportShellConfig();
		}),
		sanitize_output: await collect("cli_support.sanitize_output", () => {
			return () => runCliSupportSanitizeOutput();
		}),
		git_source: await collect("cli_support.git_source", () => {
			return () => runCliSupportGitSource();
		}),
		user_agent: await collect("cli_support.user_agent", () => {
			return () => runCliSupportUserAgent();
		}),
		parse_changelog: await collect("cli_support.parse_changelog", () => {
			return () => runCliSupportParseChangelog();
		}),
		experimental: await collect("cli_support.experimental", () => {
			return () => runCliSupportExperimental();
		}),
		observed: {
			...ansi,
			...paths,
			...timings,
			...bus,
			...headers,
			...shell,
			...sanitize,
			...git,
			...ua,
			...changelog,
			...experimental,
		},
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

function waylandSessionFlag(env) {
	return clipboardImageModule.isWaylandSession(env) ? 1 : 0;
}

function runCliInteractiveWayland() {
	return {
		wl_disp: waylandSessionFlag({ WAYLAND_DISPLAY: "wayland-0" }),
		wl_type: waylandSessionFlag({ XDG_SESSION_TYPE: "wayland" }),
		wl_x11: waylandSessionFlag({ XDG_SESSION_TYPE: "x11" }),
		wl_none: waylandSessionFlag({ FOO: "1" }),
	};
}

function cwdFooterFlag(cwd, home, expected) {
	return footerModule.formatCwdForFooter(cwd, home) === expected ? 1 : 0;
}

function runCliInteractiveCwdFooter() {
	return {
		cf_home: cwdFooterFlag("/home/u", "/home/u", "~"),
		cf_proj: cwdFooterFlag("/home/u/proj", "/home/u", "~/proj"),
		cf_out: cwdFooterFlag("/tmp", "/home/u", "/tmp"),
		cf_slash: cwdFooterFlag("/home/u/proj/", "/home/u/", "~/proj"),
	};
}

function authTypeLabelFlag(authType, expected) {
	return oauthSelectorModule.formatAuthSelectorProviderType(authType) === expected ? 1 : 0;
}

function runCliInteractiveAuthType() {
	return {
		al_oauth: authTypeLabelFlag("oauth", "subscription"),
		al_key: authTypeLabelFlag("api_key", "API key"),
	};
}

function parseAutoThemeEncoded(setting) {
	const parsed = themeModule.parseAutoThemeSetting(setting);
	return parsed ? `${parsed.lightTheme}|${parsed.darkTheme}` : "";
}

function runCliInteractiveParseAutoTheme() {
	return {
		pat_valid: parseAutoThemeEncoded("  light / dark  "),
		pat_empty_left: parseAutoThemeEncoded(" /dark"),
		pat_empty_right: parseAutoThemeEncoded("light/  "),
		pat_nil: parseAutoThemeEncoded(undefined),
		pat_double: parseAutoThemeEncoded("light/dark/extra"),
		pat_fixed: parseAutoThemeEncoded("dark"),
	};
}

function resolveThemeStr(setting, terminalTheme) {
	const resolved = themeModule.resolveThemeSetting(setting, terminalTheme);
	return resolved ?? "";
}

function runCliInteractiveResolveTheme() {
	return {
		rts_auto_light: resolveThemeStr("  light / dark  ", "light"),
		rts_auto_dark: resolveThemeStr("  light / dark  ", "dark"),
		rts_fixed: resolveThemeStr("solarized", "light"),
		rts_bad: resolveThemeStr("light/dark/extra", "dark"),
		rts_nil: resolveThemeStr(undefined, "light"),
	};
}

async function measureCliInteractiveDecodeEntity() {
	const observed = {
		...runCliInteractiveDecodeEntity(),
		...runCliInteractiveWayland(),
		...runCliInteractiveCwdFooter(),
		...runCliInteractiveAuthType(),
		...runCliInteractiveParseAutoTheme(),
		...runCliInteractiveResolveTheme(),
	};
	return {
		decode_entity: await collect("cli_interactive_controller.decode_entity", () => {
			return () => runCliInteractiveDecodeEntity();
		}),
		wayland: await collect("cli_interactive_controller.wayland", () => {
			return () => runCliInteractiveWayland();
		}),
		cwd_footer: await collect("cli_interactive_controller.cwd_footer", () => {
			return () => runCliInteractiveCwdFooter();
		}),
		auth_type: await collect("cli_interactive_controller.auth_type", () => {
			return () => runCliInteractiveAuthType();
		}),
		parse_auto_theme: await collect("cli_interactive_controller.parse_auto_theme", () => {
			return () => runCliInteractiveParseAutoTheme();
		}),
		resolve_theme: await collect("cli_interactive_controller.resolve_theme", () => {
			return () => runCliInteractiveResolveTheme();
		}),
		observed,
	};
}

function sessionSearchFixtureRecords() {
	return [
		{
			id: "019f0000-0000-7000-8000-00000000cadr",
			name: "alpha",
			cwd: "/tmp/a",
			allMessagesText: "hello cadr world",
			modified: new Date(3),
		},
		{
			id: "other-id",
			name: undefined,
			cwd: "/tmp/b",
			allMessagesText: "nope",
			modified: new Date(2),
		},
		{
			id: "named-sess",
			name: "  named  ",
			cwd: "/proj",
			allMessagesText: "foo",
			modified: new Date(1),
		},
	];
}

function sessionSearchCount(query, nameFilter = "all") {
	return sessionSelectorSearchModule.filterAndSortSessions(
		sessionSearchFixtureRecords(),
		query,
		"recent",
		nameFilter,
	).length;
}

const SESSION_FORMAT_AGE_NOW_MS = 1_700_000_000_000;

function formatSessionDatePi(modifiedMs, nowMs = SESSION_FORMAT_AGE_NOW_MS) {
	const diffMs = nowMs - modifiedMs;
	const diffMins = Math.floor(diffMs / 60_000);
	const diffHours = Math.floor(diffMs / 3_600_000);
	const diffDays = Math.floor(diffMs / 86_400_000);
	if (diffMins < 1) return "now";
	if (diffMins < 60) return `${diffMins}m`;
	if (diffHours < 24) return `${diffHours}h`;
	if (diffDays < 7) return `${diffDays}d`;
	if (diffDays < 30) return `${Math.floor(diffDays / 7)}w`;
	if (diffDays < 365) return `${Math.floor(diffDays / 30)}mo`;
	return `${Math.floor(diffDays / 365)}y`;
}

function runCliSelectorsSessionFormatAge() {
	const now = SESSION_FORMAT_AGE_NOW_MS;
	return {
		sfa_now: formatSessionDatePi(now, now),
		sfa_sec: formatSessionDatePi(now - 45_000, now),
		sfa_min: formatSessionDatePi(now - 120_000, now),
		sfa_hour: formatSessionDatePi(now - 3_600_000, now),
		sfa_day: formatSessionDatePi(now - 86_400_000, now),
		sfa_week: formatSessionDatePi(now - 10 * 86_400_000, now),
	};
}

function sessionRecordLabelFixtureSessions() {
	const escape = String.fromCharCode(27);
	const del = String.fromCharCode(127);
	return [
		{
			id: "named",
			name: "My Session",
			firstMessage: "ignored",
		},
		{
			id: "first",
			firstMessage: "hello world",
		},
		{
			id: "empty",
			firstMessage: "(no messages)",
		},
		{
			id: "ctrl",
			firstMessage: `first\nsecond\ttab${escape}[2Jclear${del}end`,
		},
		{
			id: "name-ctrl",
			name: `bad${del}name`,
			firstMessage: "ignored",
		},
	];
}

function sessionRecordLabelPi(session) {
	const displayText = session.name ?? session.firstMessage;
	return displayText.replace(/[\x00-\x1f\x7f]/g, " ").trim();
}

function runCliSelectorsSessionRecordLabel() {
	const labels = sessionRecordLabelFixtureSessions().map(sessionRecordLabelPi);
	return {
		srl_named: labels[0],
		srl_first: labels[1],
		srl_empty: labels[2],
		srl_ctrl: labels[3],
		srl_name_ctrl: labels[4],
	};
}

function shortenPathPi(path) {
	const home = homedir();
	if (!path) {
		return path;
	}
	if (path.startsWith(home)) {
		return `~${path.slice(home.length)}`;
	}
	return path;
}

function runCliSelectorsSessionShortenPath() {
	const home = homedir();
	return {
		ssp_home: shortenPathPi(home),
		ssp_prefix: shortenPathPi(`${home}land/session.jsonl`),
		ssp_abs: shortenPathPi("/tmp/session.jsonl"),
		ssp_proj: shortenPathPi(`${home}projects/pi-mono/README.md`),
		ssp_empty: shortenPathPi(""),
	};
}

function normalizedSearchTextPi(text) {
	return (text ?? "").toLowerCase().replace(/\s+/g, " ");
}

function getSessionSearchTextPi(session) {
	return `${session.id} ${session.name ?? ""} ${session.allMessagesText} ${session.cwd}`;
}

function quotedSearchPi(query) {
	return query.length >= 2 && query[0] === '"' && query[query.length - 1] === '"';
}

function searchRecordPositionPi(session, query) {
	const haystack = normalizedSearchTextPi(getSessionSearchTextPi(session));
	if (query.startsWith("re:")) {
		const pattern = query.slice(3);
		try {
			const idx = haystack.search(new RegExp(pattern, "i"));
			return idx < 0 ? -1 : idx;
		} catch {
			return -1;
		}
	}
	const needle = normalizedSearchTextPi(
		quotedSearchPi(query) ? query.slice(1, -1) : query,
	);
	if (needle.length === 0) {
		return 0;
	}
	const idx = haystack.indexOf(needle);
	return idx < 0 ? -1 : idx;
}

function sessionQuotedSearchFixtureSessions() {
	return [
		{
			id: "019f0000-0000-7000-8000-00000000cadr",
			name: "alpha",
			cwd: "/tmp/a",
			allMessagesText: "hello cadr world",
			modified: new Date(3),
		},
		{
			id: "other-id",
			name: null,
			cwd: "/tmp/b",
			allMessagesText: "nope",
			modified: new Date(2),
		},
	];
}

function runCliSelectorsSessionQuotedSearch() {
	const [hit, miss] = sessionQuotedSearchFixtureSessions();
	return {
		sqs_cadr: searchRecordPositionPi(hit, '"cadr"'),
		sqs_phrase: searchRecordPositionPi(hit, '"hello cadr"'),
		sqs_miss: searchRecordPositionPi(hit, '"not-found"'),
		sqs_other_miss: searchRecordPositionPi(miss, '"cadr"'),
		sqs_name: searchRecordPositionPi(hit, '"alpha"'),
		sqs_other_hit: searchRecordPositionPi(hit, '"nope"'),
	};
}

function canonicalizePathPi(path) {
	return path ?? undefined;
}

function sessionThreadFixtureSessions() {
	return [
		{ id: "parent", path: "/tmp/goal20/parent.jsonl", modified: new Date(10) },
		{
			id: "child1",
			path: "/tmp/goal20/child1.jsonl",
			parentSessionPath: "/tmp/goal20/parent.jsonl",
			modified: new Date(8),
		},
		{
			id: "grand",
			path: "/tmp/goal20/grand.jsonl",
			parentSessionPath: "/tmp/goal20/child1.jsonl",
			modified: new Date(7),
		},
		{
			id: "child2",
			path: "/tmp/goal20/child2.jsonl",
			parentSessionPath: "/tmp/goal20/parent.jsonl",
			modified: new Date(6),
		},
		{ id: "root2", path: "/tmp/goal20/root2.jsonl", modified: new Date(5) },
	];
}

function buildSessionTreePi(sessions) {
	const byPath = new Map();
	for (const session of sessions) {
		const sessionPath = canonicalizePathPi(session.path) ?? session.path;
		byPath.set(sessionPath, {
			session,
			children: [],
			latestActivity: session.modified.getTime(),
		});
	}
	const roots = [];
	for (const session of sessions) {
		const sessionPath = canonicalizePathPi(session.path) ?? session.path;
		const node = byPath.get(sessionPath);
		const parentPath = canonicalizePathPi(session.parentSessionPath);
		if (parentPath && byPath.has(parentPath)) {
			byPath.get(parentPath).children.push(node);
		} else {
			roots.push(node);
		}
	}
	const updateLatestActivity = (node) => {
		let latestActivity = node.session.modified.getTime();
		for (const child of node.children) {
			latestActivity = Math.max(latestActivity, updateLatestActivity(child));
		}
		node.latestActivity = latestActivity;
		return latestActivity;
	};
	for (const root of roots) {
		updateLatestActivity(root);
	}
	const sortNodes = (nodes) => {
		nodes.sort((a, b) => b.latestActivity - a.latestActivity);
		for (const node of nodes) {
			sortNodes(node.children);
		}
	};
	sortNodes(roots);
	return roots;
}

function flattenSessionTreePi(roots) {
	const result = [];
	const walk = (node, depth, ancestorContinues, isLast) => {
		result.push({ session: node.session, depth, isLast, ancestorContinues });
		for (let i = 0; i < node.children.length; i++) {
			const childIsLast = i === node.children.length - 1;
			const continues = depth > 0 ? !isLast : false;
			walk(node.children[i], depth + 1, [...ancestorContinues, continues], childIsLast);
		}
	};
	for (let i = 0; i < roots.length; i++) {
		walk(roots[i], 0, [], i === roots.length - 1);
	}
	return result;
}

function runCliSelectorsSessionThreadRecords() {
	const flat = flattenSessionTreePi(buildSessionTreePi(sessionThreadFixtureSessions()));
	return {
		str_count: flat.length,
		str_depths: flat.map((node) => node.depth).join(","),
		str_ids: flat.map((node) => node.session.id).join(","),
	};
}

function makeSessionSelectorKeybindingsPi(userBindings) {
	return new keybindingsModule.KeybindingsManager(appKeybindingsModule.KEYBINDINGS, userBindings);
}

function sessionBindingLabelPi(manager, name) {
	const keys = manager.getKeys(name);
	return keys.length > 0 ? keys[0] : name;
}

function runCliSelectorsSessionBindingLabel() {
	const defaultManager = makeSessionSelectorKeybindingsPi();
	const customManager = makeSessionSelectorKeybindingsPi({
		"app.session.toggleSort": "ctrl+k",
	});
	return {
		sbl_confirm: sessionBindingLabelPi(defaultManager, "tui.select.confirm"),
		sbl_delete: sessionBindingLabelPi(defaultManager, "app.session.delete"),
		sbl_noninvasive: sessionBindingLabelPi(defaultManager, "app.session.deleteNoninvasive"),
		sbl_fallback: sessionBindingLabelPi(defaultManager, "app.session.not-a-binding"),
		sbl_custom: sessionBindingLabelPi(customManager, "app.session.toggleSort"),
	};
}

function sessionSamePathPi(left, right) {
	if (!left || !right) {
		return false;
	}
	return pathsModule.canonicalizePath(left) === pathsModule.canonicalizePath(right);
}

function sessionSamePathInt(left, right) {
	return sessionSamePathPi(left, right) ? 1 : 0;
}

function runCliSelectorsSessionSamePath() {
	return {
		ssp_same: sessionSamePathInt("/tmp/goal20/session-a.jsonl", "/tmp/goal20/session-a.jsonl"),
		ssp_diff: sessionSamePathInt("/tmp/goal20/session-a.jsonl", "/tmp/goal20/session-b.jsonl"),
		ssp_nil_left: sessionSamePathInt(null, "/tmp/goal20/session-a.jsonl"),
		ssp_nil_right: sessionSamePathInt("/tmp/goal20/session-a.jsonl", null),
		ssp_nil_both: sessionSamePathInt(null, null),
	};
}

function quotedSearchPInt(query) {
	return quotedSearchPi(query) ? 1 : 0;
}

function runCliSelectorsSessionQuotedP() {
	return {
		sqp_phrase: quotedSearchPInt('"cadr"'),
		sqp_words: quotedSearchPInt('"hello world"'),
		sqp_plain: quotedSearchPInt("cadr"),
		sqp_empty: quotedSearchPInt(""),
		sqp_one: quotedSearchPInt('"'),
		sqp_open: quotedSearchPInt('"open'),
	};
}

function namedSessionPInt(name) {
	return sessionSelectorSearchModule.hasSessionName({ name }) ? 1 : 0;
}

function runCliSelectorsSessionNamedP() {
	return {
		snp_named: namedSessionPInt("alpha"),
		snp_whitespace: namedSessionPInt("   "),
		snp_empty: namedSessionPInt(""),
		snp_nil: namedSessionPInt(null),
	};
}

const thinkingDescriptionsPi = {
	off: "No reasoning",
	minimal: "Very brief reasoning (~1k tokens)",
	low: "Light reasoning (~2k tokens)",
	medium: "Moderate reasoning (~8k tokens)",
	high: "Deep reasoning (~16k tokens)",
	xhigh: "Extra-high reasoning (~32k tokens)",
	max: "Maximum reasoning",
};

function settingsThinkingDescriptionPi(level) {
	return thinkingDescriptionsPi[level] ?? "";
}

function runCliSelectorsSettingsThinkingDescription() {
	return {
		std_off: settingsThinkingDescriptionPi("off"),
		std_minimal: settingsThinkingDescriptionPi("minimal"),
		std_low: settingsThinkingDescriptionPi("low"),
		std_medium: settingsThinkingDescriptionPi("medium"),
		std_high: settingsThinkingDescriptionPi("high"),
		std_xhigh: settingsThinkingDescriptionPi("xhigh"),
		std_max: settingsThinkingDescriptionPi("max"),
		std_unknown: settingsThinkingDescriptionPi("bogus"),
	};
}

function settingsDisplayValuePi(value) {
	if (value === true) {
		return "true";
	}
	if (value === false || value == null) {
		return "false";
	}
	if (typeof value === "object" && value !== null && "__lispSymbol" in value) {
		return value.__lispSymbol.toLowerCase();
	}
	return String(value);
}

function runCliSelectorsSettingsDisplayValue() {
	return {
		sdv_true: settingsDisplayValuePi(true),
		sdv_false: settingsDisplayValuePi(null),
		sdv_symbol: settingsDisplayValuePi({ __lispSymbol: "MEDIUM" }),
		sdv_int: settingsDisplayValuePi(42),
		sdv_string: settingsDisplayValuePi("hello"),
	};
}

function automaticThemeSettingPi(light, dark) {
	return `${light}/${dark}`;
}

function runCliSelectorsSettingsAutomaticThemeSetting() {
	return {
		sats_solarized: automaticThemeSettingPi("solarized", "dark"),
		sats_same: automaticThemeSettingPi("dark", "dark"),
		sats_light_dark: automaticThemeSettingPi("light", "dark"),
	};
}

function activeAutomaticThemePi(light, dark, terminalTheme) {
	return terminalTheme === "light" ? light : dark;
}

function runCliSelectorsSettingsActiveAutomaticTheme() {
	return {
		saat_light_term: activeAutomaticThemePi("solarized", "dark", "light"),
		saat_dark_term: activeAutomaticThemePi("solarized", "dark", "dark"),
		saat_light_pair: activeAutomaticThemePi("light", "dark", "light"),
	};
}

function cycleSettingEncodedPi(id, values, currentValue) {
	const currentIndex = values.indexOf(currentValue);
	const nextIndex = (currentIndex + 1) % values.length;
	return `${id}|${values[nextIndex]}`;
}

function runCliSelectorsSettingsCycle() {
	return {
		ssc_true: cycleSettingEncodedPi("auto-compact", ["true", "false"], "true"),
		ssc_transport: cycleSettingEncodedPi("transport", ["sse", "websocket", "auto"], "sse"),
		ssc_wrap: cycleSettingEncodedPi("mode", ["a", "b"], "b"),
		ssc_missing: cycleSettingEncodedPi("flag", ["true", "false"], "bogus"),
	};
}

function settingsApplyFilterEncodedPi(labels, query) {
	const items = labels.map((label) => ({ label }));
	const filtered =
		query.length === 0
			? items
			: fuzzyModule.fuzzyFilter(items, query, (item) => item.label);
	return `${filtered.length}|0`;
}

function runCliSelectorsSettingsApplyFilter() {
	return {
		sap_empty: settingsApplyFilterEncodedPi(["auto-compact", "transport", "theme"], ""),
		sap_trans: settingsApplyFilterEncodedPi(["auto-compact", "transport", "theme"], "trans"),
		sap_none: settingsApplyFilterEncodedPi(["auto-compact", "transport", "theme"], "zzz"),
		sap_app: settingsApplyFilterEncodedPi(["apple", "application", "banana"], "app"),
	};
}

function isTreeSettingsEntry(type) {
	return (
		type === "label" ||
		type === "custom" ||
		type === "model_change" ||
		type === "thinking_level_change" ||
		type === "session_info"
	);
}

function treeAssistantHiddenPi(entry, currentLeafId) {
	if (entry.type !== "message" || entry.role !== "assistant") {
		return false;
	}
	if (entry.id === currentLeafId) {
		return false;
	}
	const text = entry.text ?? "";
	const stopReason = entry.stopReason;
	const isErrorOrAborted =
		stopReason && stopReason !== "stop" && stopReason !== "toolUse";
	return text.length === 0 && !isErrorOrAborted;
}

function treeEntryFilteredPi(entry, filter, currentLeafId) {
	if (treeAssistantHiddenPi(entry, currentLeafId)) {
		return false;
	}
	switch (filter) {
		case "user-only":
			return entry.type === "message" && entry.role === "user";
		case "no-tools":
			return (
				!isTreeSettingsEntry(entry.type) &&
				!(entry.type === "message" && entry.role === "toolResult")
			);
		case "labeled-only":
			return entry.label !== undefined;
		case "all":
			return true;
		default:
			return !isTreeSettingsEntry(entry.type);
	}
}

function treeEntryFilteredEncodedPi(entry, filter, currentLeafId) {
	return treeEntryFilteredPi(entry, filter, currentLeafId) ? "t" : "";
}

function runCliSelectorsTreeEntryFiltered() {
	return {
		tef_user_def: treeEntryFilteredEncodedPi(
			{ id: "u1", type: "message", role: "user", text: "hello" },
			"default",
			"leaf",
		),
		tef_label_def: treeEntryFilteredEncodedPi(
			{ id: "l1", type: "label", label: "bookmark" },
			"default",
			"leaf",
		),
		tef_user_uo: treeEntryFilteredEncodedPi(
			{ id: "u1", type: "message", role: "user", text: "hello" },
			"user-only",
			"leaf",
		),
		tef_tool_nt: treeEntryFilteredEncodedPi(
			{ id: "t1", type: "message", role: "toolResult", text: "ok" },
			"no-tools",
			"leaf",
		),
		tef_labeled_lo: treeEntryFilteredEncodedPi(
			{ id: "m1", type: "message", role: "user", text: "hi", label: "pin" },
			"labeled-only",
			"leaf",
		),
		tef_all_label: treeEntryFilteredEncodedPi(
			{ id: "l1", type: "label", label: "bookmark" },
			"all",
			"leaf",
		),
	};
}

function treeEntrySearchText(entry) {
	return [
		entry.label,
		entry.role,
		entry.text,
		entry.summary,
		entry.name,
		entry.modelId,
		entry.thinkingLevel,
		entry.customType,
	]
		.filter((part) => part !== undefined && part !== null)
		.join(" ");
}

function treeQueryMatchesPi(entry, query) {
	const haystack = treeEntrySearchText(entry).toLowerCase();
	const tokens = query
		.toLowerCase()
		.split(/\s+/)
		.filter(Boolean);
	return tokens.every((token) => haystack.includes(token));
}

function treeQueryMatchesEncodedPi(entry, query) {
	return treeQueryMatchesPi(entry, query) ? "t" : "";
}

function runCliSelectorsTreeEntrySearchText() {
	return {
		tese_sparse: treeEntrySearchText({ label: "alpha", text: "beta" }),
		tese_label: treeEntrySearchText({ label: "solo" }),
		tese_empty: treeEntrySearchText({}),
		tese_full: treeEntrySearchText({
			label: "L",
			text: "T",
			summary: "S",
			name: "N",
			modelId: "M",
			thinkingLevel: "H",
			customType: "C",
		}),
		tese_text: treeEntrySearchText({ text: "only" }),
	};
}

function runCliSelectorsTreeQueryMatches() {
	const entry = { label: "alpha", role: "user", text: "hello world" };
	return {
		tqm_hit: treeQueryMatchesEncodedPi(entry, "hello"),
		tqm_miss: treeQueryMatchesEncodedPi(entry, "nope"),
		tqm_multi: treeQueryMatchesEncodedPi(entry, "hello world"),
		tqm_partial: treeQueryMatchesEncodedPi(entry, "hello beta"),
		tqm_empty: treeQueryMatchesEncodedPi(entry, ""),
	};
}

function treeSettingsEntryEncodedPi(type) {
	return isTreeSettingsEntry(type) ? "t" : "";
}

function runCliSelectorsTreeSettingsEntryP() {
	return {
		tsep_label: treeSettingsEntryEncodedPi("label"),
		tsep_user: treeSettingsEntryEncodedPi("message"),
		tsep_custom: treeSettingsEntryEncodedPi("custom"),
		tsep_model: treeSettingsEntryEncodedPi("model_change"),
		tsep_think: treeSettingsEntryEncodedPi("thinking_level_change"),
		tsep_session: treeSettingsEntryEncodedPi("session_info"),
	};
}

function treeNormalizeDisplayTextPi(text) {
	return (text ?? "").replace(/[\n\t]/g, " ").trim();
}

function runCliSelectorsTreeNormalizeDisplayText() {
	return {
		tnd_hello: treeNormalizeDisplayTextPi("hello"),
		tnd_spaced: treeNormalizeDisplayTextPi("  spaced  "),
		tnd_newline: treeNormalizeDisplayTextPi("\nfoo\tbar\n"),
		tnd_empty: treeNormalizeDisplayTextPi(null),
		tnd_ws: treeNormalizeDisplayTextPi("   \t\n  "),
	};
}

function treeStatusLabelsPi(filterMode, showLabelTimestamps) {
	let labels = "";
	switch (filterMode) {
		case "no-tools":
			labels += " [no-tools]";
			break;
		case "user-only":
			labels += " [user]";
			break;
		case "labeled-only":
			labels += " [labeled]";
			break;
		case "all":
			labels += " [all]";
			break;
	}
	if (showLabelTimestamps) {
		labels += " [+label time]";
	}
	return labels;
}

function runCliSelectorsTreeStatusLabels() {
	return {
		tsl_empty: treeStatusLabelsPi("default", false),
		tsl_notools: treeStatusLabelsPi("no-tools", false),
		tsl_user: treeStatusLabelsPi("user-only", false),
		tsl_labeled: treeStatusLabelsPi("labeled-only", false),
		tsl_all: treeStatusLabelsPi("all", false),
		tsl_time: treeStatusLabelsPi("default", true),
		tsl_both: treeStatusLabelsPi("no-tools", true),
	};
}

function treeShortenPathPi(path) {
	const home = process.env.HOME || process.env.USERPROFILE || "";
	if (home && path.startsWith(home)) {
		return `~${path.slice(home.length)}`;
	}
	return path;
}

function runCliSelectorsTreeShortenPath() {
	const home = (process.env.HOME || process.env.USERPROFILE || "").replace(/\/$/, "");
	return {
		tsp_home: treeShortenPathPi(home),
		tsp_prefix: treeShortenPathPi(`${home}/land/session.jsonl`),
		tsp_abs: treeShortenPathPi("/tmp/session.jsonl"),
		tsp_proj: treeShortenPathPi(`${home}/projects/pi-mono/README.md`),
		tsp_empty: treeShortenPathPi(""),
	};
}

function treeFoldableStateWithMaps(childrenEntries, parentEntries) {
	const childrenMap = new Map(childrenEntries);
	const parentMap = new Map(parentEntries);
	return { childrenMap, parentMap };
}

function treeFoldablePi(childrenMap, parentMap, entryId) {
	const children = childrenMap.get(entryId);
	if (!children || children.length === 0) return false;
	const parentId = parentMap.get(entryId);
	if (parentId === null || parentId === undefined) return true;
	const siblings = childrenMap.get(parentId);
	return siblings !== undefined && siblings.length > 1;
}

function treeFoldableEncodedPi(childrenEntries, parentEntries, entryId) {
	const { childrenMap, parentMap } = treeFoldableStateWithMaps(childrenEntries, parentEntries);
	return treeFoldablePi(childrenMap, parentMap, entryId) ? "t" : "";
}

function runCliSelectorsTreeFoldableP() {
	return {
		tfp_root: treeFoldableEncodedPi([["r", ["a"]]], [["a", "r"]], "r"),
		tfp_leaf: treeFoldableEncodedPi([], [], "x"),
		tfp_only_child: treeFoldableEncodedPi(
			[
				["r", ["p"]],
				["p", ["c"]],
			],
			[
				["p", "r"],
				["c", "p"],
			],
			"p",
		),
		tfp_branch: treeFoldableEncodedPi(
			[
				["p", ["a", "b"]],
				["a", ["x"]],
			],
			[
				["a", "p"],
				["b", "p"],
				["x", "a"],
			],
			"a",
		),
	};
}

function treeToolArgumentPi(args, name, fallback) {
	if (!args) return "";
	if (args[name] != null && args[name] !== undefined) return String(args[name]);
	if (fallback && args[fallback] != null && args[fallback] !== undefined) return String(args[fallback]);
	return "";
}

function runCliSelectorsTreeToolArgument() {
	return {
		tta_path: treeToolArgumentPi({ path: "/tmp/foo" }, "path", "file_path"),
		tta_file: treeToolArgumentPi({ file_path: "/tmp/bar" }, "path", "file_path"),
		tta_prio: treeToolArgumentPi({ path: "/prio", file_path: "/alt" }, "path", "file_path"),
		tta_miss: treeToolArgumentPi({ offset: 5 }, "path", "file_path"),
		tta_nil: treeToolArgumentPi(null, "path", "file_path"),
	};
}

const TREE_FILTER_MODES = ["default", "no-tools", "user-only", "labeled-only", "all"];

function treeCycleFilterPi(start, direction) {
	const index = TREE_FILTER_MODES.indexOf(start);
	const currentIndex = index >= 0 ? index : 0;
	return TREE_FILTER_MODES[(currentIndex + direction + TREE_FILTER_MODES.length) % TREE_FILTER_MODES.length];
}

function runCliSelectorsTreeCycleFilter() {
	return {
		tcf_def_fwd: treeCycleFilterPi("default", 1),
		tcf_nt_back: treeCycleFilterPi("no-tools", -1),
		tcf_all_fwd: treeCycleFilterPi("all", 1),
		tcf_user_fwd: treeCycleFilterPi("user-only", 1),
	};
}

const TREE_FORMAT_LABEL_TIMESTAMP_NOW_MS = Date.UTC(2026, 7, 2, 15, 0, 0);

const TREE_FORMAT_LABEL_TIMESTAMP_INPUTS = [
	"2026-08-02T09:07:11.000Z",
	"2026-03-28T14:32:00.000Z",
	"2025-12-31T23:59:00.000Z",
	"2026-08-02T10:00:00+02:30",
	"not-a-date",
];

function formatLabelTimestampPi(timestamp, nowMs) {
	const date = new Date(timestamp);
	const now = new Date(nowMs);
	const hours = date.getHours().toString().padStart(2, "0");
	const minutes = date.getMinutes().toString().padStart(2, "0");
	const time = `${hours}:${minutes}`;

	if (
		date.getFullYear() === now.getFullYear() &&
		date.getMonth() === now.getMonth() &&
		date.getDate() === now.getDate()
	) {
		return time;
	}

	const month = date.getMonth() + 1;
	const day = date.getDate();
	if (date.getFullYear() === now.getFullYear()) {
		return `${month}/${day} ${time}`;
	}

	const year = date.getFullYear().toString().slice(-2);
	return `${year}/${month}/${day} ${time}`;
}

function runCliSelectorsTreeFormatLabelTimestamp() {
	process.env.TZ = "UTC";
	const now = TREE_FORMAT_LABEL_TIMESTAMP_NOW_MS;
	const observed = {};
	for (const input of TREE_FORMAT_LABEL_TIMESTAMP_INPUTS) {
		const formatted = formatLabelTimestampPi(input, now);
		observed[formatted] = formatted;
	}
	return observed;
}

// Lisp universal time epoch offset: (encode-universal-time 0 0 0 1 1 1970 0)
const LISP_UNIX_EPOCH = 2208988800;

function lispEncodeUniversalTime(second, minute, hour, day, month, year) {
	return Math.floor(Date.UTC(year, month - 1, day, hour, minute, second) / 1000) + LISP_UNIX_EPOCH;
}

/** Local ISO timestamp YYYY-MM-DDTHH:MM:SS (no Z/ms); pair tree-selector-iso-timestamp. */
function treeIsoTimestampPi(universalSeconds) {
	const date = new Date((universalSeconds - LISP_UNIX_EPOCH) * 1000);
	const year = date.getFullYear();
	const month = date.getMonth() + 1;
	const day = date.getDate();
	const hour = date.getHours();
	const minute = date.getMinutes();
	const second = date.getSeconds();
	return `${String(year).padStart(4, "0")}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}T${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}:${String(second).padStart(2, "0")}`;
}

function runCliSelectorsTreeIsoTimestamp() {
	process.env.TZ = "UTC";
	return {
		tis_afternoon: treeIsoTimestampPi(lispEncodeUniversalTime(0, 0, 15, 2, 8, 2026)),
		tis_epoch: treeIsoTimestampPi(lispEncodeUniversalTime(0, 0, 0, 1, 1, 1970)),
		tis_eoy: treeIsoTimestampPi(lispEncodeUniversalTime(59, 59, 23, 31, 12, 2025)),
		tis_midnight: treeIsoTimestampPi(lispEncodeUniversalTime(0, 0, 0, 1, 6, 2024)),
		tis_noon: treeIsoTimestampPi(lispEncodeUniversalTime(0, 0, 12, 15, 3, 2023)),
	};
}

function formatToolCallPi(name, args) {
	switch (name) {
		case "read": {
			const path = shortenPathPi(String(args.path || args.file_path || ""));
			const offset = args.offset;
			const limit = args.limit;
			let display = path;
			if (offset !== undefined || limit !== undefined) {
				const start = offset ?? 1;
				const end = limit !== undefined ? start + limit - 1 : "";
				display += `:${start}${end ? `-${end}` : ""}`;
			}
			return `[read: ${display}]`;
		}
		case "write": {
			const path = shortenPathPi(String(args.path || args.file_path || ""));
			return `[write: ${path}]`;
		}
		case "edit": {
			const path = shortenPathPi(String(args.path || args.file_path || ""));
			return `[edit: ${path}]`;
		}
		case "bash": {
			const rawCmd = String(args.command || "");
			const cmd = rawCmd
				.replace(/[\n\t]/g, " ")
				.trim()
				.slice(0, 50);
			return `[bash: ${cmd}${rawCmd.length > 50 ? "..." : ""}]`;
		}
		case "grep": {
			const pattern = String(args.pattern || "");
			const path = shortenPathPi(String(args.path || "."));
			return `[grep: /${pattern}/ in ${path}]`;
		}
		case "find": {
			const pattern = String(args.pattern || "");
			const path = shortenPathPi(String(args.path || "."));
			return `[find: ${pattern} in ${path}]`;
		}
		case "ls": {
			const path = shortenPathPi(String(args.path || "."));
			return `[ls: ${path}]`;
		}
		default: {
			const argsStr = JSON.stringify(args).slice(0, 40);
			return `[${name}: ${argsStr}${JSON.stringify(args).length > 40 ? "..." : ""}]`;
		}
	}
}

function runCliSelectorsTreeFormatToolCall() {
	const longBash = "a".repeat(55);
	return {
		tfc_read: formatToolCallPi("read", { path: "/tmp/foo" }),
		tfc_read_rng: formatToolCallPi("read", { path: "/tmp/foo", offset: 10, limit: 5 }),
		tfc_read_off: formatToolCallPi("read", { path: "/tmp/foo", offset: 3 }),
		tfc_write: formatToolCallPi("write", { path: "/tmp/out" }),
		tfc_edit: formatToolCallPi("edit", { file_path: "/tmp/edit" }),
		tfc_bash: formatToolCallPi("bash", { command: "echo hi" }),
		tfc_bash_long: formatToolCallPi("bash", { command: longBash }),
		tfc_grep: formatToolCallPi("grep", { pattern: "needle", path: "/tmp" }),
		tfc_find: formatToolCallPi("find", { pattern: "*.ts", path: "/src" }),
		tfc_ls: formatToolCallPi("ls", { path: "/var" }),
		tfc_custom: formatToolCallPi("mytool", { alpha: 1, beta: "two" }),
	};
}

function treeEntryDisplayTextPi(entry, isSelected) {
	const theme = themeModule.theme;
	const normalize = (text) => (text ?? "").replace(/[\n\t]/g, " ").trim();
	let result = "";

	switch (entry.type) {
		case "message": {
			const role = entry.role;
			if (role === "user") {
				result = theme.fg("accent", "user: ") + normalize(entry.text);
			} else if (role === "assistant") {
				const textContent = normalize(entry.text);
				if (textContent) {
					result = theme.fg("success", "assistant: ") + textContent;
				} else if (entry.stopReason === "aborted") {
					result = theme.fg("success", "assistant: ") + theme.fg("muted", "(aborted)");
				} else if (entry.errorMessage) {
					const errMsg = normalize(entry.errorMessage).slice(0, 80);
					result = theme.fg("success", "assistant: ") + theme.fg("error", errMsg);
				} else {
					result = theme.fg("success", "assistant: ") + theme.fg("muted", "(no content)");
				}
			} else if (role === "toolResult") {
				if (entry.toolCall) {
					result = theme.fg("muted", formatToolCallPi(entry.toolCall.name, entry.toolCall.arguments));
				} else {
					result = theme.fg("muted", `[${entry.toolName ?? "tool"}]`);
				}
			} else if (role === "bashExecution") {
				result = theme.fg("dim", `[bash]: ${normalize(entry.command)}`);
			} else {
				result = theme.fg("dim", `[${role}]`);
			}
			break;
		}
		case "custom_message":
			result =
				theme.fg("customMessageLabel", `[${entry.customType}]: `) + normalize(entry.text);
			break;
		case "compaction":
			result = theme.fg("borderAccent", `[compaction: ${Math.round(entry.tokensBefore / 1000)}k tokens]`);
			break;
		case "branch_summary":
			result = theme.fg("warning", "[branch summary]: ") + normalize(entry.text);
			break;
		case "model_change":
			result = theme.fg("dim", `[model: ${entry.modelId}]`);
			break;
		case "thinking_level_change":
			result = theme.fg("dim", `[thinking: ${entry.thinkingLevel}]`);
			break;
		case "custom":
			result = theme.fg("dim", `[custom: ${entry.customType}]`);
			break;
		case "label":
			result = theme.fg("dim", `[label: ${entry.label ?? "(cleared)"}]`);
			break;
		case "session_info":
			result = entry.name
				? [theme.fg("dim", "[title: "), theme.fg("dim", entry.name), theme.fg("dim", "]")].join("")
				: [theme.fg("dim", "[title: "), theme.italic(theme.fg("dim", "empty")), theme.fg("dim", "]")].join("");
			break;
		default:
			result = "";
	}

	return isSelected ? theme.bold(result) : result;
}

function runCliSelectorsTreeEntryDisplayText() {
	return {
		ted_user: treeEntryDisplayTextPi({ type: "message", role: "user", text: "hello" }, false),
		ted_asst: treeEntryDisplayTextPi({ type: "message", role: "assistant", text: "reply text" }, false),
		ted_empty: treeEntryDisplayTextPi({ type: "message", role: "assistant", text: "" }, false),
		ted_abort: treeEntryDisplayTextPi(
			{ type: "message", role: "assistant", stopReason: "aborted", text: "" },
			false,
		),
		ted_bash: treeEntryDisplayTextPi(
			{ type: "message", role: "bashExecution", command: "echo hi" },
			false,
		),
		ted_compact: treeEntryDisplayTextPi({ type: "compaction", tokensBefore: 42000 }, false),
		ted_branch: treeEntryDisplayTextPi({ type: "branch_summary", text: "summary text" }, false),
		ted_label: treeEntryDisplayTextPi({ type: "label", label: "bookmark" }, false),
		ted_tool: treeEntryDisplayTextPi(
			{
				type: "message",
				role: "toolResult",
				toolCall: { name: "read", arguments: { path: "/tmp/foo" } },
			},
			false,
		),
		ted_custom: treeEntryDisplayTextPi(
			{ type: "custom_message", customType: "note", text: "body" },
			false,
		),
		ted_sel: treeEntryDisplayTextPi({ type: "message", role: "user", text: "selected" }, true),
	};
}

function treePrefixPi(flatNode, multipleRoots, folded, foldable) {
	const displayIndent = multipleRoots ? Math.max(0, flatNode.indent - 1) : flatNode.indent;
	const connector =
		flatNode.showConnector && !flatNode.isVirtualRootChild ? (flatNode.isLast ? "└─ " : "├─ ") : "";
	const connectorPosition = connector ? displayIndent - 1 : -1;
	const totalChars = displayIndent * 3;
	const prefixChars = [];
	for (let i = 0; i < totalChars; i++) {
		const level = Math.floor(i / 3);
		const posInLevel = i % 3;
		const gutter = flatNode.gutters.find((g) => g.position === level);
		if (gutter) {
			if (posInLevel === 0) {
				prefixChars.push(gutter.show ? "│" : " ");
			} else {
				prefixChars.push(" ");
			}
		} else if (connector && level === connectorPosition) {
			if (posInLevel === 0) {
				prefixChars.push(flatNode.isLast ? "└" : "├");
			} else if (posInLevel === 1) {
				prefixChars.push(folded ? "⊞" : foldable ? "⊟" : "─");
			} else {
				prefixChars.push(" ");
			}
		} else {
			prefixChars.push(" ");
		}
	}
	return prefixChars.join("");
}

function runCliSelectorsTreePrefix() {
	return {
		tp_branch: treePrefixPi(
			{ indent: 1, showConnector: true, isVirtualRootChild: false, isLast: false, gutters: [] },
			false,
			false,
			false,
		),
		tp_last: treePrefixPi(
			{ indent: 1, showConnector: true, isVirtualRootChild: false, isLast: true, gutters: [] },
			false,
			false,
			false,
		),
		tp_open: treePrefixPi(
			{ indent: 1, showConnector: true, isVirtualRootChild: false, isLast: false, gutters: [] },
			false,
			false,
			true,
		),
		tp_fold: treePrefixPi(
			{ indent: 1, showConnector: true, isVirtualRootChild: false, isLast: false, gutters: [] },
			false,
			true,
			true,
		),
		tp_gutter: treePrefixPi(
			{
				indent: 2,
				showConnector: true,
				isVirtualRootChild: false,
				isLast: true,
				gutters: [{ position: 0, show: true }],
			},
			false,
			false,
			false,
		),
		tp_deep: treePrefixPi(
			{
				indent: 2,
				showConnector: true,
				isVirtualRootChild: false,
				isLast: false,
				gutters: [{ position: 0, show: false }],
			},
			false,
			false,
			false,
		),
		tp_vroot: treePrefixPi(
			{ indent: 1, showConnector: false, isVirtualRootChild: true, isLast: false, gutters: [] },
			true,
			false,
			false,
		),
	};
}

function treeGuttersEncoded(gutters) {
	if (!gutters || gutters.length === 0) {
		return "";
	}
	return [...gutters]
		.sort((a, b) => a.position - b.position)
		.map((g) => `${g.position}:${g.show ? "1" : "0"}`)
		.join(",");
}

function treeVisualNodeEncoded(visual) {
	return [
		visual.indent,
		visual.showConnector ? "1" : "0",
		visual.isLast ? "1" : "0",
		treeGuttersEncoded(visual.gutters),
		visual.isVirtualRootChild ? "1" : "0",
	].join(",");
}

function treeVisualNodesPi(visibleChildren) {
	const visibleRootIds = visibleChildren.get(null) ?? [];
	const multipleRoots = visibleRootIds.length > 1;
	const visuals = new Map();
	const stack = [];
	for (let i = visibleRootIds.length - 1; i >= 0; i--) {
		const isLast = i === visibleRootIds.length - 1;
		stack.push([
			visibleRootIds[i],
			multipleRoots ? 1 : 0,
			multipleRoots,
			multipleRoots,
			isLast,
			[],
			multipleRoots,
		]);
	}
	while (stack.length > 0) {
		const [
			nodeId,
			indent,
			justBranched,
			showConnector,
			isLast,
			gutters,
			isVirtualRootChild,
		] = stack.pop();
		visuals.set(nodeId, {
			indent,
			showConnector,
			isLast,
			gutters,
			isVirtualRootChild,
		});
		const children = visibleChildren.get(nodeId) ?? [];
		const multipleChildren = children.length > 1;
		let childIndent;
		if (multipleChildren) {
			childIndent = indent + 1;
		} else if (justBranched && indent > 0) {
			childIndent = indent + 1;
		} else {
			childIndent = indent;
		}
		const connectorDisplayed = showConnector && !isVirtualRootChild;
		const currentDisplayIndent = multipleRoots ? Math.max(0, indent - 1) : indent;
		const connectorPosition = Math.max(0, currentDisplayIndent - 1);
		const childGutters = connectorDisplayed
			? [...gutters, { position: connectorPosition, show: !isLast }]
			: gutters;
		for (let i = children.length - 1; i >= 0; i--) {
			const childIsLast = i === children.length - 1;
			stack.push([
				children[i],
				childIndent,
				multipleChildren,
				multipleChildren,
				childIsLast,
				childGutters,
				false,
			]);
		}
	}
	return { visuals, multipleRoots };
}

function treeVisualNodesEncoded(visibleChildren) {
	const { visuals, multipleRoots } = treeVisualNodesPi(visibleChildren);
	const ids = [...visuals.keys()].sort();
	const body = ids.map((id) => `${id}=${treeVisualNodeEncoded(visuals.get(id))}`).join(";");
	return `${multipleRoots ? "1" : "0"}|${body}`;
}

function runCliSelectorsTreeVisualNodes() {
	return {
		tvn_single: treeVisualNodesEncoded(
			new Map([
				[null, ["r"]],
				["r", ["a"]],
			]),
		),
		tvn_branch: treeVisualNodesEncoded(
			new Map([
				[null, ["p"]],
				["p", ["a", "b"]],
			]),
		),
		tvn_multi: treeVisualNodesEncoded(new Map([[null, ["a", "b"]]])),
		tvn_chain: treeVisualNodesEncoded(
			new Map([
				[null, ["a"]],
				["a", ["b"]],
				["b", ["c"]],
			]),
		),
		tvn_deep: treeVisualNodesEncoded(
			new Map([
				[null, ["r"]],
				["r", ["p"]],
				["p", ["a", "b"]],
			]),
		),
	};
}

const TREE_GUTTER_WIDTH = 2;
const MIN_VISIBLE_ANCHOR_CONTENT_WIDTH = 4;
const MAX_VISIBLE_ANCHOR_CONTENT_WIDTH = 20;
const MIN_ANCHOR_CONTEXT_WIDTH = 2;
const MAX_ANCHOR_CONTEXT_WIDTH = 12;

function renderHorizontalViewportPi(rows, width) {
	const viewportWidth = Math.max(0, width - TREE_GUTTER_WIDTH);
	const maxBodyWidth = rows.reduce((max, row) => Math.max(max, row.bodyWidth), 0);
	const maxHorizontalScroll = Math.max(0, maxBodyWidth - viewportWidth);
	const selectedRow = rows.find((row) => row.isSelected);

	let horizontalScroll = 0;
	if (selectedRow && maxHorizontalScroll > 0) {
		const minVisibleAnchorContentWidth = Math.min(
			MAX_VISIBLE_ANCHOR_CONTENT_WIDTH,
			Math.max(MIN_VISIBLE_ANCHOR_CONTENT_WIDTH, Math.floor(viewportWidth / 3)),
		);
		if (selectedRow.anchorCol > viewportWidth - minVisibleAnchorContentWidth) {
			const anchorContextWidth = Math.min(
				MAX_ANCHOR_CONTEXT_WIDTH,
				Math.max(MIN_ANCHOR_CONTEXT_WIDTH, Math.floor(viewportWidth / 4)),
			);
			horizontalScroll = Math.min(
				maxHorizontalScroll,
				selectedRow.anchorCol - anchorContextWidth,
			);
		}
	}

	return rows.map((row) => {
		const line =
			horizontalScroll > 0
				? `${row.gutter}${tuiUtilsModule.sliceByColumn(row.body, horizontalScroll, viewportWidth, true)}\x1b[0m`
				: row.gutter + row.body;
		return tuiUtilsModule.truncateToWidth(line, width, "");
	});
}

function treeHorizontalViewportEncoded(rows, width) {
	return renderHorizontalViewportPi(rows, width).join("|");
}

function runCliSelectorsTreeHorizontalViewport() {
	const longBody = "x".repeat(50);
	const ansiBody = `\x1b[31mred text padding\x1b[0m${"y".repeat(30)}`;
	return {
		thv_short: treeHorizontalViewportEncoded(
			[
				{
					gutter: "> ",
					body: "hello",
					anchorCol: 2,
					bodyWidth: 5,
					isSelected: false,
				},
				{
					gutter: "  ",
					body: "world",
					anchorCol: 2,
					bodyWidth: 5,
					isSelected: true,
				},
			],
			40,
		),
		thv_scroll: treeHorizontalViewportEncoded(
			[
				{
					gutter: "> ",
					body: longBody,
					anchorCol: 25,
					bodyWidth: 50,
					isSelected: true,
				},
			],
			30,
		),
		thv_narrow: treeHorizontalViewportEncoded(
			[
				{
					gutter: "> ",
					body: "hello world text",
					anchorCol: 2,
					bodyWidth: 16,
					isSelected: true,
				},
			],
			12,
		),
		thv_noselect: treeHorizontalViewportEncoded(
			[
				{
					gutter: "> ",
					body: longBody,
					anchorCol: 2,
					bodyWidth: 50,
					isSelected: false,
				},
			],
			30,
		),
		thv_ansi: treeHorizontalViewportEncoded(
			[
				{
					gutter: "> ",
					body: ansiBody,
					anchorCol: 25,
					bodyWidth: 50,
					isSelected: true,
				},
			],
			30,
		),
	};
}

function makeTreeSelectorKeybindingsPi(userBindings) {
	return new keybindingsModule.KeybindingsManager(
		appKeybindingsModule.KEYBINDINGS,
		userBindings,
	);
}

function compactRawKeysPi(keys) {
	if (keys.length === 1) {
		return keys[0];
	}
	const parts = keys.map((key) => {
		const separatorIndex = key.lastIndexOf("+");
		return separatorIndex === -1
			? { prefix: "", suffix: key }
			: { prefix: key.slice(0, separatorIndex + 1), suffix: key.slice(separatorIndex + 1) };
	});
	const prefix = parts[0].prefix;
	return prefix && parts.every((part) => part.prefix === prefix)
		? `${prefix}${parts.map((part) => part.suffix).join("/")}`
		: keys.join("/");
}

function formatHelpKeysPi(keybindings, manager) {
	const keys = [];
	for (const keybinding of keybindings) {
		const key = manager.getKeys(keybinding)[0];
		if (key !== undefined) {
			keys.push(key);
		}
	}
	if (keys.length === 0) {
		return "";
	}
	return keybindingHintsModule
		.formatKeyText(compactRawKeysPi(keys))
		.replace(/\bpageUp\b/g, "pgup")
		.replace(/\bpageDown\b/g, "pgdn")
		.replace(/\bup\b/g, "↑")
		.replace(/\bdown\b/g, "↓")
		.replace(/\bleft\b/g, "←")
		.replace(/\bright\b/g, "→");
}

const TREE_HELP_KEY_FALLBACKS = {
	"tui.select.up": "up",
	"tui.select.down": "down",
	"tui.editor.cursorLeft": "left",
	"tui.editor.cursorRight": "right",
};

function treeHelpKeyPi(name, manager) {
	const keys = manager.getKeys(name);
	if (keys.length > 0 && keys[0] !== undefined) {
		return keys[0];
	}
	const fallback = TREE_HELP_KEY_FALLBACKS[name];
	return fallback !== undefined ? fallback : "null";
}

function runCliSelectorsTreeHelpKeys() {
	const defaultManager = makeTreeSelectorKeybindingsPi();
	const customManager = makeTreeSelectorKeybindingsPi({ "tui.select.up": "ctrl+k" });
	return {
		thk_move: formatHelpKeysPi(["tui.select.up", "tui.select.down"], defaultManager),
		thk_page: formatHelpKeysPi(
			["tui.editor.cursorLeft", "tui.editor.cursorRight"],
			defaultManager,
		),
		thk_branch: formatHelpKeysPi(
			["app.tree.foldOrUp", "app.tree.unfoldOrDown"],
			defaultManager,
		),
		thk_copy: formatHelpKeysPi(["app.message.copy"], defaultManager),
		thk_filters: formatHelpKeysPi(
			[
				"app.tree.filter.default",
				"app.tree.filter.noTools",
				"app.tree.filter.userOnly",
				"app.tree.filter.labeledOnly",
				"app.tree.filter.all",
			],
			defaultManager,
		),
		thk_cycle: formatHelpKeysPi(
			["app.tree.filter.cycleForward", "app.tree.filter.cycleBackward"],
			defaultManager,
		),
		thk_custom: formatHelpKeysPi(["tui.select.up", "tui.select.down"], customManager),
	};
}

function runCliSelectorsTreeHelpKey() {
	const defaultManager = makeTreeSelectorKeybindingsPi();
	const customManager = makeTreeSelectorKeybindingsPi({ "tui.select.up": "ctrl+k" });
	return {
		thkey_up: treeHelpKeyPi("tui.select.up", defaultManager),
		thkey_fold: treeHelpKeyPi("app.tree.foldOrUp", defaultManager),
		thkey_filter_all: treeHelpKeyPi("app.tree.filter.all", defaultManager),
		thkey_left: treeHelpKeyPi("tui.editor.cursorLeft", defaultManager),
		thkey_custom_up: treeHelpKeyPi("tui.select.up", customManager),
		thkey_missing: treeHelpKeyPi("unknown.binding", defaultManager),
	};
}

function splitKeyIdPi(keyId) {
	const parts = keyId.toLowerCase().split("+");
	let key = parts[parts.length - 1];
	if (key === "esc") {
		key = "escape";
	} else if (key === "return") {
		key = "enter";
	}
	let mask = 0;
	for (let index = 0; index < parts.length - 1; index += 1) {
		switch (parts[index]) {
			case "shift":
				mask |= 1;
				break;
			case "alt":
				mask |= 2;
				break;
			case "ctrl":
				mask |= 4;
				break;
			case "super":
				mask |= 8;
				break;
		}
	}
	return { key, mask };
}

function canonicalKeyIdPi(keyId) {
	const { key, mask } = splitKeyIdPi(keyId);
	return `${mask}:${key}`;
}

function selectorModifiedCursorKeyPi(data) {
	const match = data.match(/^\x1b\[1;(\d+)([ABCD])$/);
	if (!match) {
		return undefined;
	}
	const mask = 1 - Number(match[1]);
	const direction =
		match[2] === "A"
			? "up"
			: match[2] === "B"
				? "down"
				: match[2] === "C"
					? "right"
					: match[2] === "D"
						? "left"
						: undefined;
	if (!direction) {
		return undefined;
	}
	const mods = [];
	if (mask & 1) mods.push("shift");
	if (mask & 4) mods.push("ctrl");
	if (mask & 2) mods.push("alt");
	if (mask & 8) mods.push("super");
	mods.push(direction);
	return mods.join("+");
}

function selectorKeybindingMatchesPi(manager, data, name) {
	if (manager.matches(data, name)) {
		return true;
	}
	const parsed = selectorModifiedCursorKeyPi(data);
	if (!parsed) {
		return false;
	}
	const parsedCanonical = canonicalKeyIdPi(parsed);
	for (const key of manager.getKeys(name)) {
		if (canonicalKeyIdPi(key) === parsedCanonical) {
			return true;
		}
	}
	return false;
}

function treeAppKeyPEncodedPi(data, name) {
	const manager = makeTreeSelectorKeybindingsPi();
	return selectorKeybindingMatchesPi(manager, data, name) ? "true" : "false";
}

function runCliSelectorsTreeAppKeyP() {
	const manager = makeTreeSelectorKeybindingsPi();
	const copyData = manager.getKeys("app.message.copy")[0];
	const upData = manager.getKeys("tui.select.up")[0];
	const filterData = manager.getKeys("app.tree.filter.all")[0];
	return {
		tapk_copy_hit: treeAppKeyPEncodedPi(copyData, "app.message.copy"),
		tapk_copy_miss: treeAppKeyPEncodedPi(copyData, "app.tree.foldOrUp"),
		tapk_up_hit: treeAppKeyPEncodedPi(upData, "tui.select.up"),
		tapk_filter_hit: treeAppKeyPEncodedPi(filterData, "app.tree.filter.all"),
		tapk_csi_up: treeAppKeyPEncodedPi("\x1b[1;1A", "tui.select.up"),
		tapk_garbage: treeAppKeyPEncodedPi("x", "app.message.copy"),
	};
}

const TREE_HELP_ITEMS_PI = [
	{ keys: ["tui.select.up", "tui.select.down"], label: "move" },
	{ keys: ["tui.editor.cursorLeft", "tui.editor.cursorRight"], label: "page" },
	{ keys: ["app.tree.foldOrUp", "app.tree.unfoldOrDown"], label: "branch" },
	{ keys: ["app.message.copy"], label: "copy" },
	{ keys: ["app.tree.editLabel"], label: "label" },
	{ keys: ["app.tree.toggleLabelTimestamp"], label: "label time" },
	{
		keys: [
			"app.tree.filter.default",
			"app.tree.filter.noTools",
			"app.tree.filter.userOnly",
			"app.tree.filter.labeledOnly",
			"app.tree.filter.all",
		],
		label: "filters",
		labelFirst: true,
	},
	{
		keys: ["app.tree.filter.cycleForward", "app.tree.filter.cycleBackward"],
		label: "cycle",
		labelFirst: true,
	},
];

function formatTreeHelpLinesPi(width) {
	const manager = makeTreeSelectorKeybindingsPi();
	const items = TREE_HELP_ITEMS_PI.map(({ keys, label, labelFirst }) => {
		const text = formatHelpKeysPi(keys, manager);
		if (!text) {
			return label;
		}
		return labelFirst ? `${label} ${text}` : `${text} ${label}`;
	});
	const availableWidth = Math.max(1, width);
	const indent = "  ";
	const separator = " · ";
	const lines = [];
	let currentLine = "";
	for (const item of items) {
		const candidate = currentLine
			? `${currentLine}${separator}${item}`
			: tuiUtilsModule.visibleWidth(`${indent}${item}`) <= availableWidth
				? `${indent}${item}`
				: item;
		if (!currentLine || tuiUtilsModule.visibleWidth(candidate) <= availableWidth) {
			currentLine = candidate;
			continue;
		}
		lines.push(...tuiUtilsModule.wrapTextWithAnsi(currentLine.trimEnd(), availableWidth));
		currentLine =
			tuiUtilsModule.visibleWidth(`${indent}${item}`) <= availableWidth ? `${indent}${item}` : item;
	}
	if (currentLine) {
		lines.push(...tuiUtilsModule.wrapTextWithAnsi(currentLine.trimEnd(), availableWidth));
	}
	return lines.map((line) => themeModule.theme.fg("muted", line));
}

function treeHelpLinesEncodedPi(width) {
	return formatTreeHelpLinesPi(width).join("|");
}

function runCliSelectorsTreeHelpLines() {
	return {
		thl_w80: treeHelpLinesEncodedPi(80),
		thl_w50: treeHelpLinesEncodedPi(50),
		thl_w30: treeHelpLinesEncodedPi(30),
		thl_w20: treeHelpLinesEncodedPi(20),
		thl_w12: treeHelpLinesEncodedPi(12),
	};
}

const TREE_ACTIVE_PATH_BRANCHING_ENTRIES = [
	{ id: "user-1", parentId: null, type: "message", role: "user", text: "first message" },
	{ id: "asst-1", parentId: "user-1", type: "message", role: "assistant", text: "response 1" },
	{ id: "user-2", parentId: "asst-1", type: "message", role: "user", text: "second message" },
	{ id: "asst-2", parentId: "user-2", type: "message", role: "assistant", text: "response 2" },
	{ id: "user-3a", parentId: "asst-2", type: "message", role: "user", text: "branch A start" },
	{ id: "asst-3a", parentId: "user-3a", type: "message", role: "assistant", text: "branch A response" },
	{ id: "user-4a", parentId: "asst-3a", type: "message", role: "user", text: "branch A deep" },
	{ id: "asst-4a", parentId: "user-4a", type: "message", role: "assistant", text: "branch A leaf" },
	{ id: "user-3b", parentId: "asst-2", type: "message", role: "user", text: "branch B start" },
	{ id: "asst-3b", parentId: "user-3b", type: "message", role: "assistant", text: "branch B response" },
	{ id: "user-4b", parentId: "asst-3b", type: "message", role: "user", text: "branch B deep" },
];

function treeActivePathEncodedPi(entries, leafId) {
	const byId = new Map(entries.map((entry) => [entry.id, entry]));
	const ids = [];
	let current = leafId;
	while (current) {
		const entry = byId.get(current);
		if (!entry) {
			break;
		}
		ids.push(current);
		current = entry.parentId ?? null;
	}
	return ids.sort().join(",");
}

function runCliSelectorsTreeActivePath() {
	const entries = TREE_ACTIVE_PATH_BRANCHING_ENTRIES;
	return {
		tap_leaf: treeActivePathEncodedPi(entries, "asst-4a"),
		tap_mid: treeActivePathEncodedPi(entries, "user-2"),
		tap_root: treeActivePathEncodedPi(entries, "user-1"),
		tap_nil: treeActivePathEncodedPi(entries, null),
		tap_missing: treeActivePathEncodedPi(entries, "missing"),
	};
}

function treeNearestVisibleIdPi(entries, visibleIds, target) {
	const byId = new Map(entries.map((entry) => [entry.id, entry]));
	const visibleSet = new Set(visibleIds);
	let current = target;
	while (current) {
		if (visibleSet.has(current)) {
			return current;
		}
		const entry = byId.get(current);
		if (!entry) {
			break;
		}
		current = entry.parentId ?? null;
	}
	return visibleIds.length > 0 ? visibleIds[visibleIds.length - 1] : null;
}

function runCliSelectorsTreeNearestVisibleId() {
	const entries = TREE_ACTIVE_PATH_BRANCHING_ENTRIES;
	return {
		tnvi_hit: treeNearestVisibleIdPi(entries, ["asst-4a"], "asst-4a"),
		tnvi_ancestor: treeNearestVisibleIdPi(entries, ["user-1", "user-4a"], "asst-4a"),
		tnvi_branch: treeNearestVisibleIdPi(entries, ["user-1", "asst-1"], "asst-4a"),
		tnvi_fallback: treeNearestVisibleIdPi(entries, ["user-3b"], "asst-4a"),
		tnvi_missing: treeNearestVisibleIdPi(entries, ["user-3b"], "missing"),
		tnvi_nil: treeNearestVisibleIdPi(entries, ["user-3b"], null),
	};
}

function treeActivePathSetPi(entries, leafId) {
	const byId = new Map(entries.map((entry) => [entry.id, entry]));
	const active = new Set();
	let current = leafId;
	while (current) {
		const entry = byId.get(current);
		if (!entry) {
			break;
		}
		active.add(current);
		current = entry.parentId ?? null;
	}
	return active;
}

function treePrioritizeActivePi(entries, activePath) {
	const prioritized = entries.filter((entry) => activePath.has(entry.id));
	const rest = entries.filter((entry) => !activePath.has(entry.id));
	return [...prioritized, ...rest];
}

function treePrioritizeActiveEncodedPi(entries, leafId) {
	const active = treeActivePathSetPi(entries, leafId);
	return treePrioritizeActivePi(entries, active)
		.map((entry) => entry.id)
		.join(",");
}

function treeOrderEntriesPi(entries, leafId) {
	const known = new Map(entries.map((entry) => [entry.id, entry]));
	const activePath = treeActivePathSetPi(entries, leafId);
	const children = new Map();
	const roots = [];
	for (const entry of entries) {
		const parentId = entry.parentId ?? null;
		if (parentId !== null && known.has(parentId)) {
			const list = children.get(parentId) ?? [];
			list.push(entry);
			children.set(parentId, list);
		} else {
			roots.push(entry);
		}
	}
	const result = [];
	const stack = [...treePrioritizeActivePi(roots, activePath)];
	while (stack.length > 0) {
		const entry = stack.pop();
		result.push(entry);
		const entryChildren = children.get(entry.id) ?? [];
		const prioritizedChildren = treePrioritizeActivePi(entryChildren, activePath);
		for (let i = prioritizedChildren.length - 1; i >= 0; i--) {
			stack.push(prioritizedChildren[i]);
		}
	}
	return result;
}

function treeOrderEntriesEncodedPi(entries, leafId) {
	return treeOrderEntriesPi(entries, leafId)
		.map((entry) => entry.id)
		.join(",");
}

function runCliSelectorsTreeOrderEntries() {
	return {
		toe_leaf_a: treeOrderEntriesEncodedPi(TREE_ACTIVE_PATH_BRANCHING_ENTRIES, "asst-4a"),
		toe_leaf_b: treeOrderEntriesEncodedPi(TREE_ACTIVE_PATH_BRANCHING_ENTRIES, "user-4b"),
		toe_root: treeOrderEntriesEncodedPi(TREE_ACTIVE_PATH_BRANCHING_ENTRIES, "user-1"),
		toe_nil: treeOrderEntriesEncodedPi(TREE_ACTIVE_PATH_BRANCHING_ENTRIES, null),
		toe_filter: treeOrderEntriesEncodedPi(TREE_APPLY_FILTER_ENTRIES, "user-3"),
	};
}

function runCliSelectorsTreePrioritizeActive() {
	const entries = TREE_ACTIVE_PATH_BRANCHING_ENTRIES;
	return {
		tpa_leaf_a: treePrioritizeActiveEncodedPi(entries, "asst-4a"),
		tpa_leaf_b: treePrioritizeActiveEncodedPi(entries, "user-4b"),
		tpa_root: treePrioritizeActiveEncodedPi(entries, "user-1"),
		tpa_nil: treePrioritizeActiveEncodedPi(entries, null),
	};
}

function treeEntryMapEncodedPi(entries) {
	const entryMap = new Map(entries.map((entry) => [entry.id, entry]));
	return [...entryMap.keys()]
		.sort()
		.map((id) => {
			const entry = entryMap.get(id);
			const parent = entry.parentId ?? "null";
			return `${id}|${entry.type}|${parent}`;
		})
		.join(";");
}

function runCliSelectorsTreeEntryMap() {
	return {
		tem_branching: treeEntryMapEncodedPi(TREE_ACTIVE_PATH_BRANCHING_ENTRIES),
		tem_filter: treeEntryMapEncodedPi(TREE_APPLY_FILTER_ENTRIES),
		tem_empty: treeEntryMapEncodedPi([]),
		tem_solo: treeEntryMapEncodedPi([
			{ id: "solo", parentId: null, type: "message", role: "user", text: "only" },
		]),
		tem_single: treeEntryMapEncodedPi([TREE_APPLY_FILTER_ENTRIES[0]]),
	};
}

function treeVisibleEntriesByIds(ids) {
	const idSet = new Set(ids);
	return TREE_ACTIVE_PATH_BRANCHING_ENTRIES.filter((entry) => idSet.has(entry.id));
}

function treeFindVisibleAncestorPi(entries, visibleIds, nodeId) {
	const byId = new Map(entries.map((entry) => [entry.id, entry]));
	let currentId = byId.get(nodeId)?.parentId ?? null;
	while (currentId !== null) {
		if (visibleIds.has(currentId)) {
			return currentId;
		}
		currentId = byId.get(currentId)?.parentId ?? null;
	}
	return null;
}

function treeChildrenKeyPi(parentId) {
	return parentId === null ? "null" : parentId;
}

function treeParentMapEncodedPi(visibleParent, entryIds) {
	return [...entryIds]
		.sort()
		.map((id) => {
			const parent = visibleParent.get(id) ?? null;
			return `${id}=${parent ?? "null"}`;
		})
		.join(";");
}

function treeChildrenMapEncodedPi(visibleChildren) {
	const parentKeys = [...visibleChildren.keys()];
	return parentKeys
		.map((parentId) => {
			const children = visibleChildren.get(parentId) ?? [];
			return `${treeChildrenKeyPi(parentId)}=${children.join(",")}`;
		})
		.sort()
		.join(";");
}

function treeRebuildVisibleMapsEncodedPi(visibleIds) {
	const entries = TREE_ACTIVE_PATH_BRANCHING_ENTRIES;
	const visibleEntries = treeVisibleEntriesByIds(visibleIds);
	const visibleIdSet = new Set(visibleIds);
	const visibleParent = new Map();
	const visibleChildren = new Map();
	visibleChildren.set(null, []);
	for (const entry of visibleEntries) {
		const nodeId = entry.id;
		const ancestorId = treeFindVisibleAncestorPi(entries, visibleIdSet, nodeId);
		visibleParent.set(nodeId, ancestorId);
		if (!visibleChildren.has(ancestorId)) {
			visibleChildren.set(ancestorId, []);
		}
		visibleChildren.get(ancestorId).push(nodeId);
	}
	return `${treeParentMapEncodedPi(visibleParent, visibleIds)}|${treeChildrenMapEncodedPi(visibleChildren)}`;
}

function runCliSelectorsTreeRebuildVisibleMaps() {
	return {
		trvm_full: treeRebuildVisibleMapsEncodedPi([
			"user-1",
			"asst-1",
			"user-2",
			"asst-2",
			"user-3a",
			"asst-3a",
			"user-4a",
			"asst-4a",
			"user-3b",
			"asst-3b",
			"user-4b",
		]),
		trvm_sparse: treeRebuildVisibleMapsEncodedPi(["user-1", "user-3a", "asst-4a"]),
		trvm_branch_b: treeRebuildVisibleMapsEncodedPi([
			"user-1",
			"user-2",
			"user-3b",
			"asst-3b",
			"user-4b",
		]),
		trvm_single: treeRebuildVisibleMapsEncodedPi(["user-1"]),
		trvm_siblings: treeRebuildVisibleMapsEncodedPi(["user-1", "user-3a", "user-3b"]),
	};
}

const TREE_APPLY_FILTER_ENTRIES = [
	{ id: "user-1", parentId: null, type: "message", role: "user", text: "root message" },
	{ id: "label-1", parentId: "user-1", type: "label", label: "bookmark" },
	{ id: "asst-1", parentId: "user-1", type: "message", role: "assistant", text: "response" },
	{ id: "user-2", parentId: "asst-1", type: "message", role: "user", text: "branch query" },
	{ id: "tool-1", parentId: "user-2", type: "message", role: "toolResult", text: "tool output" },
	{ id: "user-3", parentId: "tool-1", type: "message", role: "user", text: "leaf text", label: "pinned" },
	{ id: "asst-empty", parentId: "user-3", type: "message", role: "assistant", text: "" },
];

function treeApplyFilterPi({
	filter = "default",
	query = "",
	foldedIds = [],
	selectedId = null,
	preservedId = null,
}) {
	const entries = TREE_APPLY_FILTER_ENTRIES;
	const currentLeafId = "user-3";
	const foldedSet = new Set(foldedIds);
	const skipSet = new Set();
	const visible = [];
	for (const entry of entries) {
		const { id, parentId } = entry;
		if (parentId && (foldedSet.has(parentId) || skipSet.has(parentId))) {
			skipSet.add(id);
			continue;
		}
		if (
			!skipSet.has(id) &&
			treeEntryFilteredPi(entry, filter, currentLeafId) &&
			treeQueryMatchesPi(entry, query)
		) {
			visible.push(entry);
		}
	}
	const visibleIds = visible.map((entry) => entry.id);
	const visibleSet = new Set(visibleIds);
	const target = preservedId ?? selectedId ?? currentLeafId;
	const nearest = treeNearestVisibleIdPi(entries, visibleIds, target);
	const selected = nearest ?? null;
	const preserved = nearest ? null : target;
	return {
		visibleIds,
		selectedId: selected,
		preservedId: preserved,
	};
}

function treeApplyFilterEncodedPi(options) {
	const result = treeApplyFilterPi(options);
	return `${result.visibleIds.join(",")}|${result.selectedId ?? "null"}|${result.preservedId ?? "null"}`;
}

function runCliSelectorsTreeApplyFilter() {
	return {
		taf_default: treeApplyFilterEncodedPi({ filter: "default" }),
		taf_user_only: treeApplyFilterEncodedPi({ filter: "user-only" }),
		taf_no_tools: treeApplyFilterEncodedPi({ filter: "no-tools" }),
		taf_query: treeApplyFilterEncodedPi({ filter: "default", query: "branch" }),
		taf_fold: treeApplyFilterEncodedPi({ filter: "default", foldedIds: ["user-2"] }),
		taf_reselect: treeApplyFilterEncodedPi({ filter: "user-only", selectedId: "tool-1" }),
	};
}

function treeFlatEntryToSessionEntry(entry) {
	const base = {
		id: entry.id,
		parentId: entry.parentId ?? null,
		timestamp: "2026-01-01T00:00:00.000Z",
	};
	if (entry.type === "message") {
		return {
			...base,
			type: "message",
			message: {
				role: entry.role,
				content: entry.text ?? "",
			},
		};
	}
	return base;
}

function flatEntriesToSessionTree(flatEntries) {
	const nodes = new Map();
	for (const entry of flatEntries) {
		nodes.set(entry.id, {
			entry: treeFlatEntryToSessionEntry(entry),
			children: [],
			label: entry.label,
		});
	}
	const roots = [];
	for (const entry of flatEntries) {
		const node = nodes.get(entry.id);
		if (entry.parentId && nodes.has(entry.parentId)) {
			nodes.get(entry.parentId).children.push(node);
		} else {
			roots.push(node);
		}
	}
	return roots;
}

function treeRenderLinesPi({
	entries = TREE_ACTIVE_PATH_BRANCHING_ENTRIES,
	currentLeafId = "asst-4a",
	width,
	maxVisibleLines = 8,
	initialSelectedId,
	initialFilterMode = "default",
	foldedIds = [],
}) {
	const tree = entries.length === 0 ? [] : flatEntriesToSessionTree(entries);
	const component = new treeSelectorModule.TreeSelectorComponent(
		tree,
		currentLeafId,
		Math.max(10, maxVisibleLines * 2),
		() => {},
		() => {},
		undefined,
		initialSelectedId ?? currentLeafId,
		initialFilterMode,
	);
	const treeList = component.getTreeList();
	if (foldedIds.length > 0) {
		for (const id of foldedIds) {
			treeList.foldedNodes.add(id);
		}
		treeList.applyFilter();
	}
	return treeList.render(width).join("|");
}

function runCliSelectorsTreeRenderLines() {
	return {
		trl_wide: treeRenderLinesPi({ width: 80 }),
		trl_mid: treeRenderLinesPi({ width: 60, initialSelectedId: "user-2" }),
		trl_narrow: treeRenderLinesPi({ width: 28 }),
		trl_fold: treeRenderLinesPi({ width: 70, foldedIds: ["asst-2"] }),
		trl_empty: treeRenderLinesPi({
			entries: [],
			currentLeafId: null,
			width: 40,
			maxVisibleLines: 5,
			initialSelectedId: undefined,
		}),
		trl_short: treeRenderLinesPi({ width: 50, maxVisibleLines: 5 }),
	};
}

function treeMoveEncodedPi(selectedId, delta, { empty = false } = {}) {
	if (empty) {
		return "null";
	}
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(TREE_ACTIVE_PATH_BRANCHING_ENTRIES),
		"asst-4a",
		16,
		() => {},
		() => {},
		undefined,
		selectedId ?? "asst-4a",
		"default",
	);
	const treeList = component.getTreeList();
	const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
	if (ids.length === 0) {
		return "null";
	}
	const current = Math.max(0, ids.indexOf(selectedId));
	const next = moveIndex(current, ids.length, delta);
	return ids[next] ?? "null";
}

function runCliSelectorsTreeMove() {
	return {
		tm_down: treeMoveEncodedPi("user-1", 1),
		tm_up: treeMoveEncodedPi("user-2", -1),
		tm_wrap_up: treeMoveEncodedPi("user-1", -1),
		tm_wrap_down: treeMoveEncodedPi("asst-4a", 1),
		tm_page: treeMoveEncodedPi("user-2", 10),
		tm_page_neg: treeMoveEncodedPi("user-2", -10),
		tm_empty: treeMoveEncodedPi(null, 1, { empty: true }),
	};
}

function treeFoldOrUpEncodedPi(selectedId, { preFoldedIds = [] } = {}) {
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(TREE_ACTIVE_PATH_BRANCHING_ENTRIES),
		"asst-4a",
		16,
		() => {},
		() => {},
		undefined,
		selectedId ?? "asst-4a",
		"default",
	);
	const treeList = component.getTreeList();
	const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
	const index = ids.indexOf(selectedId);
	if (index >= 0) {
		treeList.selectedIndex = index;
	}
	for (const id of preFoldedIds) {
		treeList.foldedNodes.add(id);
	}
	if (preFoldedIds.length > 0) {
		treeList.applyFilter();
		const visibleIds = treeList.filteredNodes.map((node) => node.node.entry.id);
		const nextIndex = visibleIds.indexOf(selectedId);
		if (nextIndex >= 0) {
			treeList.selectedIndex = nextIndex;
		}
	}
	const currentId = treeList.filteredNodes[treeList.selectedIndex]?.node.entry.id;
	if (currentId && treeList.isFoldable(currentId) && !treeList.foldedNodes.has(currentId)) {
		treeList.foldedNodes.add(currentId);
		treeList.applyFilter();
	} else {
		treeList.selectedIndex = treeList.findBranchSegmentStart("up");
	}
	const selected = treeList.filteredNodes[treeList.selectedIndex]?.node.entry.id ?? "null";
	const visible = treeList.filteredNodes.map((node) => node.node.entry.id).join(",");
	return `${selected}|${visible}`;
}

function runCliSelectorsTreeFoldOrUp() {
	return {
		tfo_fold: treeFoldOrUpEncodedPi("asst-2"),
		tfo_leaf: treeFoldOrUpEncodedPi("asst-4a"),
		tfo_mid: treeFoldOrUpEncodedPi("user-4a"),
		tfo_prefold: treeFoldOrUpEncodedPi("user-3a", { preFoldedIds: ["asst-2"] }),
		tfo_root: treeFoldOrUpEncodedPi("user-1"),
		tfo_branch_b: treeFoldOrUpEncodedPi("user-4b"),
	};
}

function treeUnfoldOrDownEncodedPi(selectedId, { preFoldedIds = [] } = {}) {
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(TREE_ACTIVE_PATH_BRANCHING_ENTRIES),
		"asst-4a",
		16,
		() => {},
		() => {},
		undefined,
		selectedId ?? "asst-4a",
		"default",
	);
	const treeList = component.getTreeList();
	const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
	const index = ids.indexOf(selectedId);
	if (index >= 0) {
		treeList.selectedIndex = index;
	}
	for (const id of preFoldedIds) {
		treeList.foldedNodes.add(id);
	}
	if (preFoldedIds.length > 0) {
		treeList.applyFilter();
		const visibleIds = treeList.filteredNodes.map((node) => node.node.entry.id);
		const nextIndex = visibleIds.indexOf(selectedId);
		if (nextIndex >= 0) {
			treeList.selectedIndex = nextIndex;
		}
	}
	const currentId = treeList.filteredNodes[treeList.selectedIndex]?.node.entry.id;
	if (currentId && treeList.foldedNodes.has(currentId)) {
		treeList.foldedNodes.delete(currentId);
		treeList.applyFilter();
	} else {
		treeList.selectedIndex = treeList.findBranchSegmentStart("down");
	}
	const selected = treeList.filteredNodes[treeList.selectedIndex]?.node.entry.id ?? "null";
	const visible = treeList.filteredNodes.map((node) => node.node.entry.id).join(",");
	return `${selected}|${visible}`;
}

function runCliSelectorsTreeUnfoldOrDown() {
	return {
		tuod_unfold: treeUnfoldOrDownEncodedPi("asst-2", { preFoldedIds: ["asst-2"] }),
		tuod_leaf: treeUnfoldOrDownEncodedPi("asst-4a"),
		tuod_mid: treeUnfoldOrDownEncodedPi("user-4a"),
		tuod_prefold: treeUnfoldOrDownEncodedPi("user-3a", { preFoldedIds: ["asst-2"] }),
		tuod_root: treeUnfoldOrDownEncodedPi("user-1"),
		tuod_branch_b: treeUnfoldOrDownEncodedPi("user-4b"),
	};
}

function treeBranchSegmentEncodedPi(selectedId, direction) {
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(TREE_ACTIVE_PATH_BRANCHING_ENTRIES),
		"asst-4a",
		16,
		() => {},
		() => {},
		undefined,
		selectedId ?? "asst-4a",
		"default",
	);
	const treeList = component.getTreeList();
	const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
	const index = ids.indexOf(selectedId);
	if (index >= 0) {
		treeList.selectedIndex = index;
	}
	const segmentIndex = treeList.findBranchSegmentStart(direction);
	return treeList.filteredNodes[segmentIndex]?.node.entry.id ?? "null";
}

function runCliSelectorsTreeBranchSegmentId() {
	return {
		tbs_down_branch: treeBranchSegmentEncodedPi("asst-2", "down"),
		tbs_down_leaf: treeBranchSegmentEncodedPi("asst-4a", "down"),
		tbs_down_mid: treeBranchSegmentEncodedPi("user-4a", "down"),
		tbs_up_mid: treeBranchSegmentEncodedPi("user-4a", "up"),
		tbs_up_root: treeBranchSegmentEncodedPi("user-1", "up"),
		tbs_up_branch_b: treeBranchSegmentEncodedPi("user-4b", "up"),
	};
}

function treeSetQueryEncodedPi({ query = "", foldedIds = [], selectedId = null } = {}) {
	const entries = TREE_APPLY_FILTER_ENTRIES;
	const currentLeafId = "user-3";
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(entries),
		currentLeafId,
		16,
		() => {},
		() => {},
		undefined,
		selectedId ?? currentLeafId,
		"default",
	);
	const treeList = component.getTreeList();
	if (selectedId) {
		const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
		const index = ids.indexOf(selectedId);
		if (index >= 0) {
			treeList.selectedIndex = index;
		}
	}
	for (const id of foldedIds) {
		treeList.foldedNodes.add(id);
	}
	if (foldedIds.length > 0) {
		treeList.applyFilter();
	}
	treeList.searchQuery = query;
	treeList.foldedNodes.clear();
	treeList.applyFilter();
	const visibleIds = treeList.filteredNodes.map((node) => node.node.entry.id);
	const selected = treeList.filteredNodes[treeList.selectedIndex]?.node.entry.id ?? null;
	const preserved = selected ? null : (selectedId ?? currentLeafId);
	return `${visibleIds.join(",")}|${selected ?? "null"}|${preserved ?? "null"}`;
}

function runCliSelectorsTreeSetQuery() {
	return {
		tsq_empty: treeSetQueryEncodedPi({ query: "" }),
		tsq_branch: treeSetQueryEncodedPi({ query: "branch" }),
		tsq_fold_clear: treeSetQueryEncodedPi({ query: "branch", foldedIds: ["user-2"] }),
		tsq_miss: treeSetQueryEncodedPi({ query: "zzzzz" }),
		tsq_pinned: treeSetQueryEncodedPi({ query: "pinned" }),
		tsq_multi: treeSetQueryEncodedPi({ query: "branch query" }),
	};
}

function treeSetFilterEncodedPi({ filter = "default", foldedIds = [], selectedId = null } = {}) {
	const entries = TREE_APPLY_FILTER_ENTRIES;
	const currentLeafId = "user-3";
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(entries),
		currentLeafId,
		16,
		() => {},
		() => {},
		undefined,
		selectedId ?? currentLeafId,
		"default",
	);
	const treeList = component.getTreeList();
	if (selectedId) {
		const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
		const index = ids.indexOf(selectedId);
		if (index >= 0) {
			treeList.selectedIndex = index;
		}
	}
	for (const id of foldedIds) {
		treeList.foldedNodes.add(id);
	}
	if (foldedIds.length > 0) {
		treeList.applyFilter();
	}
	treeList.filterMode = filter;
	treeList.foldedNodes.clear();
	treeList.applyFilter();
	const visibleIds = treeList.filteredNodes.map((node) => node.node.entry.id);
	const selected = treeList.filteredNodes[treeList.selectedIndex]?.node.entry.id ?? null;
	const preserved = selected ? null : (selectedId ?? currentLeafId);
	return `${visibleIds.join(",")}|${selected ?? "null"}|${preserved ?? "null"}`;
}

function runCliSelectorsTreeSetFilter() {
	return {
		tsf_default: treeSetFilterEncodedPi({ filter: "default" }),
		tsf_user_only: treeSetFilterEncodedPi({ filter: "user-only" }),
		tsf_no_tools: treeSetFilterEncodedPi({ filter: "no-tools" }),
		tsf_fold_clear: treeSetFilterEncodedPi({ filter: "user-only", foldedIds: ["user-2"] }),
		tsf_labeled_only: treeSetFilterEncodedPi({ filter: "labeled-only" }),
		tsf_reselect: treeSetFilterEncodedPi({ filter: "user-only", selectedId: "tool-1" }),
	};
}

function treeCopySelectedEncodedPi(selectedId, { empty = false } = {}) {
	const entries = empty ? [] : TREE_APPLY_FILTER_ENTRIES;
	const currentLeafId = empty ? null : "user-3";
	let copied = "null";
	const component = new treeSelectorModule.TreeSelectorComponent(
		entries.length === 0 ? [] : flatEntriesToSessionTree(entries),
		currentLeafId,
		16,
		() => {},
		() => {},
		undefined,
		selectedId ?? currentLeafId ?? undefined,
		"default",
	);
	component.onCopy = (text) => {
		copied = text ?? "null";
	};
	const treeList = component.getTreeList();
	if (selectedId && !empty) {
		const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
		const index = ids.indexOf(selectedId);
		if (index >= 0) {
			treeList.selectedIndex = index;
		}
	}
	if (empty) {
		treeList.selectedIndex = -1;
	}
	treeList.copySelected();
	return copied;
}

function runCliSelectorsTreeCopySelected() {
	return {
		tcs_user: treeCopySelectedEncodedPi("user-1"),
		tcs_assistant: treeCopySelectedEncodedPi("asst-1"),
		tcs_tool: treeCopySelectedEncodedPi("tool-1"),
		tcs_empty: treeCopySelectedEncodedPi("asst-empty"),
		tcs_label: treeCopySelectedEncodedPi("label-1"),
		tcs_none: treeCopySelectedEncodedPi(null, { empty: true }),
	};
}

function treeToggleLabelTimestampsEncodedPi({ toggles = 0, filter = "default" } = {}) {
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(TREE_APPLY_FILTER_ENTRIES),
		"user-3",
		16,
		() => {},
		() => {},
		undefined,
		"user-3",
		filter,
	);
	const treeList = component.getTreeList();
	for (let index = 0; index < toggles; index++) {
		treeList.showLabelTimestamps = !treeList.showLabelTimestamps;
	}
	return `${treeList.showLabelTimestamps}|${treeStatusLabelsPi(filter, treeList.showLabelTimestamps)}`;
}

function runCliSelectorsTreeToggleLabelTimestamps() {
	return {
		ttlt_off: treeToggleLabelTimestampsEncodedPi({ toggles: 0 }),
		ttlt_on: treeToggleLabelTimestampsEncodedPi({ toggles: 1 }),
		ttlt_twice: treeToggleLabelTimestampsEncodedPi({ toggles: 2 }),
		ttlt_notools: treeToggleLabelTimestampsEncodedPi({ toggles: 1, filter: "no-tools" }),
		ttlt_labeled: treeToggleLabelTimestampsEncodedPi({ toggles: 1, filter: "labeled-only" }),
		ttlt_thrice: treeToggleLabelTimestampsEncodedPi({ toggles: 3 }),
	};
}

function treeStartLabelEditEncodedPi(selectedId, { empty = false, noSelect = false } = {}) {
	const entries = empty ? [] : TREE_APPLY_FILTER_ENTRIES;
	const currentLeafId = empty ? null : "user-3";
	const component = new treeSelectorModule.TreeSelectorComponent(
		entries.length === 0 ? [] : flatEntriesToSessionTree(entries),
		currentLeafId,
		16,
		() => {},
		() => {},
		undefined,
		noSelect ? undefined : (selectedId ?? currentLeafId),
		"default",
	);
	const treeList = component.getTreeList();
	if (!empty && !noSelect && selectedId) {
		const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
		const index = ids.indexOf(selectedId);
		if (index >= 0) {
			treeList.selectedIndex = index;
		}
	}
	if (noSelect && !empty) {
		treeList.selectedIndex = -1;
	}
	const selected = treeList.filteredNodes[treeList.selectedIndex]?.node;
	if (selected) {
		component.showLabelInput(selected.entry.id, selected.label);
	}
	const labelInput = component.labelInput;
	const mode = labelInput ? "label" : "list";
	const editId = labelInput?.entryId ?? "null";
	const input = labelInput?.input?.getValue?.() ?? "";
	return `${mode}|${editId}|${input}`;
}

function runCliSelectorsTreeStartLabelEdit() {
	return {
		tsle_pinned: treeStartLabelEditEncodedPi("user-3"),
		tsle_plain: treeStartLabelEditEncodedPi("user-1"),
		tsle_assistant: treeStartLabelEditEncodedPi("asst-1"),
		tsle_bookmark: treeStartLabelEditEncodedPi("label-1"),
		tsle_empty: treeStartLabelEditEncodedPi(null, { empty: true }),
		tsle_noselect: treeStartLabelEditEncodedPi(null, { noSelect: true }),
	};
}

function treeConfirmLabelEncodedPi(selectedId, input, { nop = false } = {}) {
	const entries = TREE_APPLY_FILTER_ENTRIES;
	const currentLeafId = "user-3";
	let callbackId = "null";
	let callbackLabel = "null";
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(entries),
		currentLeafId,
		16,
		() => {},
		() => {},
		(id, label) => {
			callbackId = id;
			callbackLabel = label ?? "null";
		},
		selectedId ?? currentLeafId,
		"default",
	);
	const treeList = component.getTreeList();
	if (!nop) {
		const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
		const index = ids.indexOf(selectedId);
		if (index >= 0) {
			treeList.selectedIndex = index;
		}
		const selected = treeList.filteredNodes[treeList.selectedIndex]?.node;
		if (selected) {
			component.showLabelInput(selected.entry.id, selected.label);
			component.labelInput.input.setValue(input);
			const value = component.labelInput.input.getValue().trim();
			component.labelInput.onSubmit?.(component.labelInput.entryId, value || undefined);
		}
	}
	let timestampSet = "false";
	for (const flatNode of treeList.flatNodes) {
		if (flatNode.node.entry.id === selectedId) {
			timestampSet = flatNode.node.labelTimestamp ? "true" : "false";
			break;
		}
	}
	return `list|${callbackId}|${callbackLabel}|${timestampSet}`;
}

function runCliSelectorsTreeConfirmLabel() {
	return {
		tclf_set: treeConfirmLabelEncodedPi("user-1", "newtag"),
		tclf_rename: treeConfirmLabelEncodedPi("user-3", "renamed"),
		tclf_clear: treeConfirmLabelEncodedPi("user-3", ""),
		tclf_trim: treeConfirmLabelEncodedPi("user-1", "  spaced  "),
		tclf_whitespace: treeConfirmLabelEncodedPi("user-1", "   "),
		tclf_nop: treeConfirmLabelEncodedPi("user-1", "", { nop: true }),
	};
}

function treeCancelLabelEncodedPi(selectedId, { dirtyInput = null, nop = false } = {}) {
	const entries = TREE_APPLY_FILTER_ENTRIES;
	const currentLeafId = "user-3";
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(entries),
		currentLeafId,
		16,
		() => {},
		() => {},
		undefined,
		selectedId ?? currentLeafId,
		"default",
	);
	const treeList = component.getTreeList();
	if (!nop) {
		const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
		const index = ids.indexOf(selectedId);
		if (index >= 0) {
			treeList.selectedIndex = index;
		}
		const selected = treeList.filteredNodes[treeList.selectedIndex]?.node;
		if (selected) {
			component.showLabelInput(selected.entry.id, selected.label);
			if (dirtyInput !== null) {
				component.labelInput.input.setValue(dirtyInput);
			}
			component.labelInput.onCancel?.();
		}
	} else {
		component.hideLabelInput();
	}
	const mode = component.labelInput ? "label" : "list";
	const editId = component.labelInput?.entryId ?? "null";
	let label = "null";
	for (const flatNode of treeList.flatNodes) {
		if (flatNode.node.entry.id === selectedId) {
			label = flatNode.node.label ?? "null";
			break;
		}
	}
	return `${mode}|${editId}|${label}`;
}

function runCliSelectorsTreeCancelLabel() {
	return {
		tclc_pinned: treeCancelLabelEncodedPi("user-3"),
		tclc_plain: treeCancelLabelEncodedPi("user-1"),
		tclc_assistant: treeCancelLabelEncodedPi("asst-1"),
		tclc_bookmark: treeCancelLabelEncodedPi("label-1"),
		tclc_dirty: treeCancelLabelEncodedPi("user-3", { dirtyInput: "newtag" }),
		tclc_nop: treeCancelLabelEncodedPi("user-1", { nop: true }),
	};
}

function treeRawInputKeyDataPi(keyName) {
	return makeTreeSelectorKeybindingsPi().getKeys(keyName)[0];
}

function treeHandleRawInputEncodedCopyPi(selectedId) {
	const entries = TREE_APPLY_FILTER_ENTRIES;
	let copied = "null";
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(entries),
		"user-3",
		16,
		() => {},
		() => {},
		undefined,
		selectedId,
		"default",
	);
	component.onCopy = (text) => {
		copied = text ?? "null";
	};
	const treeList = component.getTreeList();
	const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
	const index = ids.indexOf(selectedId);
	if (index >= 0) {
		treeList.selectedIndex = index;
	}
	treeList.handleInput(treeRawInputKeyDataPi("app.message.copy"));
	return copied;
}

function treeHandleRawInputEncodedEditPi(selectedId) {
	const entries = TREE_APPLY_FILTER_ENTRIES;
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(entries),
		"user-3",
		16,
		() => {},
		() => {},
		undefined,
		selectedId,
		"default",
	);
	const treeList = component.getTreeList();
	const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
	const index = ids.indexOf(selectedId);
	if (index >= 0) {
		treeList.selectedIndex = index;
	}
	treeList.handleInput(treeRawInputKeyDataPi("app.tree.editLabel"));
	const labelInput = component.labelInput;
	const mode = labelInput ? "label" : "list";
	const editId = labelInput?.entryId ?? "null";
	const input = labelInput?.input?.getValue?.() ?? "";
	return `${mode}|${editId}|${input}`;
}

function treeHandleRawInputEncodedFoldPi(selectedId) {
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(TREE_ACTIVE_PATH_BRANCHING_ENTRIES),
		"asst-4a",
		16,
		() => {},
		() => {},
		undefined,
		selectedId ?? "asst-4a",
		"default",
	);
	const treeList = component.getTreeList();
	const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
	const index = ids.indexOf(selectedId);
	if (index >= 0) {
		treeList.selectedIndex = index;
	}
	treeList.handleInput(treeRawInputKeyDataPi("app.tree.foldOrUp"));
	const selected = treeList.filteredNodes[treeList.selectedIndex]?.node.entry.id ?? "null";
	const visible = treeList.filteredNodes.map((node) => node.node.entry.id).join(",");
	return `${selected}|${visible}`;
}

function treeHandleRawInputEncodedNotoolsPi(selectedId) {
	const entries = TREE_APPLY_FILTER_ENTRIES;
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(entries),
		"user-3",
		16,
		() => {},
		() => {},
		undefined,
		selectedId,
		"default",
	);
	const treeList = component.getTreeList();
	const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
	const index = ids.indexOf(selectedId);
	if (index >= 0) {
		treeList.selectedIndex = index;
	}
	treeList.handleInput(treeRawInputKeyDataPi("app.tree.filter.noTools"));
	const visible = treeList.filteredNodes.map((node) => node.node.entry.id).join(",");
	const selected = treeList.filteredNodes[treeList.selectedIndex]?.node.entry.id ?? "null";
	const preserved = "null";
	return `${visible}|${selected}|${preserved}`;
}

function treeHandleRawInputEncodedLabelCancelPi(selectedId, dirtyInput) {
	const entries = TREE_APPLY_FILTER_ENTRIES;
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(entries),
		"user-3",
		16,
		() => {},
		() => {},
		undefined,
		selectedId,
		"default",
	);
	const treeList = component.getTreeList();
	const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
	const index = ids.indexOf(selectedId);
	if (index >= 0) {
		treeList.selectedIndex = index;
	}
	const selected = treeList.filteredNodes[treeList.selectedIndex]?.node;
	if (selected) {
		component.showLabelInput(selected.entry.id, selected.label);
		component.labelInput.input.setValue(dirtyInput);
		component.handleInput(treeRawInputKeyDataPi("tui.select.cancel"));
	}
	let label = "null";
	for (const flatNode of treeList.flatNodes) {
		if (flatNode.node.entry.id === selectedId) {
			label = flatNode.node.label ?? "null";
			break;
		}
	}
	return `list|null|${label}`;
}

function treeHandleRawInputEncodedNopPi(selectedId) {
	const entries = TREE_APPLY_FILTER_ENTRIES;
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(entries),
		"user-3",
		16,
		() => {},
		() => {},
		undefined,
		selectedId,
		"default",
	);
	const treeList = component.getTreeList();
	const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
	const index = ids.indexOf(selectedId);
	if (index >= 0) {
		treeList.selectedIndex = index;
	}
	treeList.handleInput("q");
	return "noop";
}

function runCliSelectorsTreeHandleRawInput() {
	return {
		thri_copy: treeHandleRawInputEncodedCopyPi("user-1"),
		thri_edit: treeHandleRawInputEncodedEditPi("user-3"),
		thri_fold: treeHandleRawInputEncodedFoldPi("asst-2"),
		thri_notools: treeHandleRawInputEncodedNotoolsPi("user-3"),
		thri_lcancel: treeHandleRawInputEncodedLabelCancelPi("user-3", "newtag"),
		thri_nop: treeHandleRawInputEncodedNopPi("user-1"),
	};
}

function treeHandleEventEncodedPi(selectedId, eventKind, { text = null, query = "" } = {}) {
	const entries = TREE_APPLY_FILTER_ENTRIES;
	let selectId = "null";
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(entries),
		"user-3",
		16,
		(id) => {
			selectId = id;
		},
		() => {},
	);
	const treeList = component.getTreeList();
	const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
	const index = ids.indexOf(selectedId);
	if (index >= 0) {
		treeList.selectedIndex = index;
	}
	if (query) {
		treeList.searchQuery = query;
		treeList.foldedNodes.clear();
		treeList.applyFilter();
		const visibleIds = treeList.filteredNodes.map((node) => node.node.entry.id);
		const nextIndex = visibleIds.indexOf(selectedId);
		if (nextIndex >= 0) {
			treeList.selectedIndex = nextIndex;
		}
	}
	const manager = makeTreeSelectorKeybindingsPi();
	const keyFor = (name) => manager.getKeys(name)[0];
	switch (eventKind) {
		case "up":
			treeList.handleInput(keyFor("tui.select.up"));
			break;
		case "down":
			treeList.handleInput(keyFor("tui.select.down"));
			break;
		case "enter":
			treeList.handleInput(keyFor("tui.select.confirm"));
			break;
		case "escape":
			treeList.handleInput(keyFor("tui.select.cancel"));
			break;
		case "backspace":
			treeList.handleInput(keyFor("tui.editor.deleteCharBackward"));
			break;
		case "text":
			treeList.handleInput(text ?? "");
			break;
		default:
			break;
	}
	let action = "null";
	let value = "null";
	if (eventKind === "enter") {
		action = "select";
		value = selectId;
	} else if (eventKind === "escape" && !query) {
		action = "cancel";
	} else if (eventKind !== "tab") {
		action = "changed";
	}
	const selected = treeList.filteredNodes[treeList.selectedIndex]?.node.entry.id ?? "null";
	return `${action}|${value}|${selected}|${treeList.searchQuery}`;
}

function runCliSelectorsTreeHandleEvent() {
	return {
		the_down: treeHandleEventEncodedPi("user-1", "down"),
		the_up: treeHandleEventEncodedPi("user-2", "up"),
		the_enter: treeHandleEventEncodedPi("user-3", "enter"),
		the_text: treeHandleEventEncodedPi("user-3", "text", { text: "pin" }),
		the_esc_clear: treeHandleEventEncodedPi("user-3", "escape", { query: "branch" }),
		the_nop: treeHandleEventEncodedPi("user-1", "tab"),
	};
}

function treeHandleLabelEventEncodedPi(selectedId, eventKind, { text = null, initialInput = null } = {}) {
	const entries = TREE_APPLY_FILTER_ENTRIES;
	let callbackId = "null";
	let callbackLabel = "null";
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(entries),
		"user-3",
		16,
		() => {},
		() => {},
		(id, label) => {
			callbackId = id;
			callbackLabel = label ?? "null";
		},
		selectedId,
		"default",
	);
	const treeList = component.getTreeList();
	const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
	const index = ids.indexOf(selectedId);
	if (index >= 0) {
		treeList.selectedIndex = index;
	}
	const selected = treeList.filteredNodes[treeList.selectedIndex]?.node;
	if (selected) {
		component.showLabelInput(selected.entry.id, selected.label);
		if (initialInput !== null) {
			component.labelInput.input.setValue(initialInput);
		}
		const manager = makeTreeSelectorKeybindingsPi();
		const keyFor = (name) => manager.getKeys(name)[0];
		switch (eventKind) {
			case "text":
				component.handleInput(text ?? "");
				break;
			case "backspace":
				component.handleInput(keyFor("tui.editor.deleteCharBackward"));
				break;
			case "enter":
				component.handleInput(keyFor("tui.select.confirm"));
				break;
			case "escape":
				component.handleInput(keyFor("tui.select.cancel"));
				break;
			default:
				break;
		}
	}
	if (component.labelInput) {
		return `label|${component.labelInput.entryId}|${component.labelInput.input.getValue()}`;
	}
	let label = "null";
	for (const flatNode of treeList.flatNodes) {
		if (flatNode.node.entry.id === selectedId) {
			label = flatNode.node.label ?? "null";
			break;
		}
	}
	if (eventKind === "escape") {
		return `list|null|${label}`;
	}
	let timestampSet = "false";
	for (const flatNode of treeList.flatNodes) {
		if (flatNode.node.entry.id === selectedId) {
			timestampSet = flatNode.node.labelTimestamp ? "true" : "false";
			break;
		}
	}
	return `list|${callbackId}|${callbackLabel}|${timestampSet}`;
}

function runCliSelectorsTreeHandleLabelEvent() {
	return {
		thle_text: treeHandleLabelEventEncodedPi("user-3", "text", { text: "x" }),
		thle_bs: treeHandleLabelEventEncodedPi("user-3", "backspace", { initialInput: "abcd" }),
		thle_enter: treeHandleLabelEventEncodedPi("user-3", "enter", { initialInput: "newtag" }),
		thle_escape: treeHandleLabelEventEncodedPi("user-3", "escape", { initialInput: "newtag" }),
		thle_nop: treeHandleLabelEventEncodedPi("user-3", "tab"),
	};
}

function treeRoleEncodedPi(role) {
	if (!role) {
		return "null";
	}
	return role.replace(/([A-Z])/g, "-$1").toLowerCase();
}

function treeSelectedEntryEncodedPi(selectedId, { noSelect = false } = {}) {
	const entries = TREE_APPLY_FILTER_ENTRIES;
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(entries),
		"user-3",
		16,
		() => {},
		() => {},
		undefined,
		noSelect ? undefined : (selectedId ?? "user-3"),
		"default",
	);
	const treeList = component.getTreeList();
	if (!noSelect && selectedId) {
		const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
		const index = ids.indexOf(selectedId);
		if (index >= 0) {
			treeList.selectedIndex = index;
		}
	}
	if (noSelect) {
		treeList.selectedIndex = -1;
	}
	const node = treeList.getSelectedNode();
	if (!node) {
		return "null|null|null|null|null";
	}
	const { entry } = node;
	const label = node.label ?? "null";
	const text = entry.text ?? "";
	return `${entry.id}|${entry.type}|${treeRoleEncodedPi(entry.role)}|${label}|${text}`;
}

function runCliSelectorsTreeSelectedEntry() {
	return {
		tse_pinned: treeSelectedEntryEncodedPi("user-3"),
		tse_plain: treeSelectedEntryEncodedPi("user-1"),
		tse_assistant: treeSelectedEntryEncodedPi("asst-1"),
		tse_label: treeSelectedEntryEncodedPi("label-1"),
		tse_empty: treeSelectedEntryEncodedPi("asst-empty"),
		tse_noselect: treeSelectedEntryEncodedPi(null, { noSelect: true }),
	};
}

function treeSelectedIdEncodedPi(selectedId, { noSelect = false } = {}) {
	const entries = TREE_APPLY_FILTER_ENTRIES;
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(entries),
		"user-3",
		16,
		() => {},
		() => {},
		undefined,
		noSelect ? undefined : (selectedId ?? "user-3"),
		"default",
	);
	const treeList = component.getTreeList();
	if (!noSelect && selectedId) {
		const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
		const index = ids.indexOf(selectedId);
		if (index >= 0) {
			treeList.selectedIndex = index;
		}
	}
	if (noSelect) {
		treeList.selectedIndex = -1;
	}
	const node = treeList.getSelectedNode();
	return node?.entry.id ?? "null";
}

function runCliSelectorsTreeSelectedId() {
	return {
		tslid_pinned: treeSelectedIdEncodedPi("user-3"),
		tslid_plain: treeSelectedIdEncodedPi("user-1"),
		tslid_assistant: treeSelectedIdEncodedPi("asst-1"),
		tslid_label: treeSelectedIdEncodedPi("label-1"),
		tslid_empty: treeSelectedIdEncodedPi("asst-empty"),
		tslid_noselect: treeSelectedIdEncodedPi(null, { noSelect: true }),
	};
}

function treeSelectIdEncodedPi({ selectedId, targetId, filter = "default", foldedIds = [] } = {}) {
	const entries = TREE_APPLY_FILTER_ENTRIES;
	const component = new treeSelectorModule.TreeSelectorComponent(
		flatEntriesToSessionTree(entries),
		"user-3",
		16,
		() => {},
		() => {},
		undefined,
		selectedId,
		filter,
	);
	const treeList = component.getTreeList();
	if (selectedId) {
		const ids = treeList.filteredNodes.map((node) => node.node.entry.id);
		const index = ids.indexOf(selectedId);
		if (index >= 0) {
			treeList.selectedIndex = index;
		}
	}
	for (const id of foldedIds) {
		treeList.foldedNodes.add(id);
	}
	if (foldedIds.length > 0) {
		treeList.applyFilter();
		const visibleIds = treeList.filteredNodes.map((node) => node.node.entry.id);
		const index = visibleIds.indexOf(selectedId);
		if (index >= 0) {
			treeList.selectedIndex = index;
		}
	}
	const visibleIds = treeList.filteredNodes.map((node) => node.node.entry.id);
	if (visibleIds.includes(targetId)) {
		treeList.selectedIndex = visibleIds.indexOf(targetId);
	}
	const selected = treeList.filteredNodes[treeList.selectedIndex]?.node.entry.id ?? "null";
	return `${selected}|null`;
}

function runCliSelectorsTreeSelectId() {
	return {
		tsid_hit: treeSelectIdEncodedPi({ selectedId: "user-3", targetId: "user-1" }),
		tsid_same: treeSelectIdEncodedPi({ selectedId: "user-3", targetId: "user-3" }),
		tsid_miss: treeSelectIdEncodedPi({ selectedId: "user-3", targetId: "missing" }),
		tsid_label: treeSelectIdEncodedPi({ selectedId: "user-1", targetId: "label-1" }),
		tsid_filter_miss: treeSelectIdEncodedPi({
			selectedId: "user-3",
			targetId: "asst-1",
			filter: "labeled-only",
		}),
		tsid_fold_miss: treeSelectIdEncodedPi({
			selectedId: "user-1",
			targetId: "user-3",
			foldedIds: ["user-2"],
		}),
	};
}

function treeVisibleIdsEncodedPi(options = {}) {
	return treeApplyFilterEncodedPi(options).split("|")[0];
}

function runCliSelectorsTreeVisibleIds() {
	return {
		tvi_default: treeVisibleIdsEncodedPi({ filter: "default" }),
		tvi_user_only: treeVisibleIdsEncodedPi({ filter: "user-only" }),
		tvi_no_tools: treeVisibleIdsEncodedPi({ filter: "no-tools" }),
		tvi_query: treeVisibleIdsEncodedPi({ filter: "default", query: "branch" }),
		tvi_fold: treeVisibleIdsEncodedPi({ filter: "default", foldedIds: ["user-2"] }),
		tvi_all: treeVisibleIdsEncodedPi({ filter: "all" }),
	};
}

function stageProjectTrustOptionsFixtures() {
	const parent = path.join(scratch, "trust-pto-parent");
	const child = path.join(scratch, "trust-pto-parent", "child");
	const single = path.join(scratch, "trust-pto-single");
	mkdirSync(parent, { recursive: true });
	mkdirSync(child, { recursive: true });
	mkdirSync(single, { recursive: true });
	return { parent, child, single };
}

function encodeTrustDecision(decision) {
	if (decision === true) {
		return "true";
	}
	if (decision === false) {
		return "false";
	}
	return "null";
}

function encodeTrustPath(path) {
	if (!path) {
		return "null";
	}
	const normalized = path.replace(/[/\\]+$/, "");
	const marker = "trust-pto-";
	const idx = normalized.indexOf(marker);
	return idx >= 0 ? normalized.slice(idx) : "scratch-root";
}

function encodeTrustUpdates(updates) {
	return updates
		.map((update) => `${encodeTrustPath(update.path)}=${encodeTrustDecision(update.decision)}`)
		.join(",");
}

function encodeProjectTrustOption(option) {
	const savedPath = option.savedPath ? encodeTrustPath(option.savedPath) : "null";
	return `${option.trusted ? "true" : "false"}|${savedPath}|${encodeTrustUpdates(option.updates)}`;
}

function encodeProjectTrustOptions(options) {
	return options.map(encodeProjectTrustOption).join(";");
}

function runCliSelectorsProjectTrustOptions() {
	const { child, single } = stageProjectTrustOptionsFixtures();
	return {
		pto_child: encodeProjectTrustOptions(trustManagerModule.getProjectTrustOptions(child)),
		pto_single: encodeProjectTrustOptions(trustManagerModule.getProjectTrustOptions(single)),
	};
}

function encodeTrustSelectorSelection(option) {
	if (!option) {
		return "null";
	}
	return `${option.trusted ? "true" : "false"}|${encodeTrustUpdates(option.updates)}`;
}

function runCliSelectorsTrustSelectorSelection() {
	const { child, single } = stageProjectTrustOptionsFixtures();
	const childOptions = trustManagerModule.getProjectTrustOptions(child);
	const singleOptions = trustManagerModule.getProjectTrustOptions(single);
	return {
		tss_child_trust: encodeTrustSelectorSelection(childOptions[0]),
		tss_child_parent: encodeTrustSelectorSelection(childOptions[1]),
		tss_child_distrust: encodeTrustSelectorSelection(childOptions[2]),
		tss_single_trust: encodeTrustSelectorSelection(singleOptions[0]),
		tss_single_distrust: encodeTrustSelectorSelection(singleOptions[2]),
	};
}

function encodeTrustDecisionDescription(cwd, savedDecision) {
	if (savedDecision === null) {
		return "none";
	}
	const options = trustManagerModule.getProjectTrustOptions(cwd);
	const trustPath = options[0]?.savedPath;
	const label = savedDecision.decision ? "trusted" : "untrusted";
	const entryPath = encodeTrustPath(savedDecision.path);
	if (savedDecision.path !== trustPath) {
		return `${label} (inherited from ${entryPath})`;
	}
	return `${label} (${entryPath})`;
}

function runCliSelectorsTrustDecisionDescription() {
	const { child, parent, single } = stageProjectTrustOptionsFixtures();
	return {
		tdd_none: encodeTrustDecisionDescription(child, null),
		tdd_child_local: encodeTrustDecisionDescription(child, { path: child, decision: true }),
		tdd_child_inherited: encodeTrustDecisionDescription(child, { path: parent, decision: true }),
		tdd_single_untrusted: encodeTrustDecisionDescription(single, { path: single, decision: false }),
	};
}

function trustSelectorMoveEncoded(cwd, selected, delta) {
	const count = trustManagerModule.getProjectTrustOptions(cwd).length;
	return String(moveIndex(selected, count, delta));
}

function runCliSelectorsTrustSelectorMove() {
	const { child, single } = stageProjectTrustOptionsFixtures();
	return {
		tsm_child_down: trustSelectorMoveEncoded(child, 0, 1),
		tsm_child_up: trustSelectorMoveEncoded(child, 1, -1),
		tsm_child_wrap_up: trustSelectorMoveEncoded(child, 0, -1),
		tsm_child_wrap_down: trustSelectorMoveEncoded(child, 2, 1),
		tsm_child_page: trustSelectorMoveEncoded(child, 1, 10),
		tsm_single_down: trustSelectorMoveEncoded(single, 0, 1),
		tsm_single_wrap: trustSelectorMoveEncoded(single, 1, 1),
	};
}

function trustHandleEventEncoded(cwd, selected, eventKind, { text = null } = {}) {
	const options = trustManagerModule.getProjectTrustOptions(cwd);
	let selectedIndex = selected;
	let action = "null";
	let value = "null";
	switch (eventKind) {
		case "up":
			selectedIndex = moveIndex(selected, options.length, -1);
			action = "changed";
			break;
		case "down":
			selectedIndex = moveIndex(selected, options.length, 1);
			action = "changed";
			break;
		case "enter":
		case "submit": {
			const option = options[selected];
			action = "select";
			value = encodeTrustSelectorSelection(option);
			break;
		}
		case "escape":
		case "cancel":
			action = "cancel";
			break;
		case "text":
			if (text === "k") {
				selectedIndex = moveIndex(selected, options.length, -1);
				action = "changed";
			} else if (text === "j") {
				selectedIndex = moveIndex(selected, options.length, 1);
				action = "changed";
			}
			break;
		default:
			break;
	}
	return `${action}|${value}|${selectedIndex}`;
}

function runCliSelectorsTrustSelectorHandleEvent() {
	const { child } = stageProjectTrustOptionsFixtures();
	return {
		tshe_child_down: trustHandleEventEncoded(child, 0, "down"),
		tshe_child_up: trustHandleEventEncoded(child, 1, "up"),
		tshe_child_enter: trustHandleEventEncoded(child, 0, "enter"),
		tshe_child_k: trustHandleEventEncoded(child, 1, "text", { text: "k" }),
		tshe_child_bad: trustHandleEventEncoded(child, 0, "text", { text: "pin" }),
		tshe_child_esc: trustHandleEventEncoded(child, 1, "escape"),
		tshe_child_nop: trustHandleEventEncoded(child, 0, "tab"),
	};
}

function trustRawInputKeyDataPi(keyName) {
	return new keybindingsModule.KeybindingsManager(keybindingsModule.TUI_KEYBINDINGS).getKeys(keyName)[0];
}

function trustHandleRawInputEncoded(cwd, selected, data) {
	const manager = new keybindingsModule.KeybindingsManager(keybindingsModule.TUI_KEYBINDINGS);
	const options = trustManagerModule.getProjectTrustOptions(cwd);
	let selectedIndex = selected;
	let action = "null";
	let value = "null";
	let consumed = "false";

	if (data === "k" || selectorKeybindingMatchesPi(manager, data, "tui.select.up")) {
		selectedIndex = moveIndex(selected, options.length, -1);
		action = "changed";
		consumed = "true";
	} else if (data === "j" || selectorKeybindingMatchesPi(manager, data, "tui.select.down")) {
		selectedIndex = moveIndex(selected, options.length, 1);
		action = "changed";
		consumed = "true";
	} else if (data === "\n" || selectorKeybindingMatchesPi(manager, data, "tui.select.confirm")) {
		action = "select";
		value = encodeTrustSelectorSelection(options[selected]);
		consumed = "true";
	} else if (selectorKeybindingMatchesPi(manager, data, "tui.select.cancel")) {
		action = "cancel";
		consumed = "true";
	}

	return `${action}|${value}|${selectedIndex}|${consumed}`;
}

function runCliSelectorsTrustSelectorHandleRawInput() {
	const { child } = stageProjectTrustOptionsFixtures();
	return {
		tshri_child_down: trustHandleRawInputEncoded(child, 0, trustRawInputKeyDataPi("tui.select.down")),
		tshri_child_k: trustHandleRawInputEncoded(child, 1, "k"),
		tshri_child_enter: trustHandleRawInputEncoded(child, 0, "\n"),
		tshri_child_esc: trustHandleRawInputEncoded(child, 1, trustRawInputKeyDataPi("tui.select.cancel")),
		tshri_child_bad: trustHandleRawInputEncoded(child, 0, "q"),
		tshri_child_j: trustHandleRawInputEncoded(child, 1, "j"),
		tshri_child_confirm: trustHandleRawInputEncoded(child, 0, trustRawInputKeyDataPi("tui.select.confirm")),
	};
}

function encodeTrustOptionLabel(option) {
	if (option.label.includes("parent folder")) {
		return `Trust parent folder (${encodeTrustPath(option.savedPath)})`;
	}
	return option.label;
}

function trustSelectorUiEncoded(cwd, { savedDecision = null, projectTrusted = false } = {}) {
	const options = trustManagerModule.getProjectTrustOptions(cwd);
	const selectedIndex = Math.max(
		0,
		options.findIndex(
			(option) =>
				option.savedPath !== undefined &&
				savedDecision?.decision === option.trusted &&
				savedDecision?.path === option.savedPath,
		),
	);
	const rows = options.map((option, index) => {
		const saved =
			option.savedPath !== undefined &&
			savedDecision?.decision === option.trusted &&
			savedDecision?.path === option.savedPath;
		const selected = index === selectedIndex ? "sel" : "nosel";
		const savedFlag = saved ? "saved" : "nosaved";
		return `${encodeTrustOptionLabel(option)}|${selected}|${savedFlag}`;
	});
	return `${encodeTrustDecisionDescription(cwd, savedDecision)}|${projectTrusted ? "trusted" : "untrusted"}|${rows.join(";")}`;
}

function runCliSelectorsTrustSelectorUiState() {
	const { child, parent, single } = stageProjectTrustOptionsFixtures();
	return {
		rts_child_default: trustSelectorUiEncoded(child),
		rts_child_saved: trustSelectorUiEncoded(child, {
			savedDecision: { path: child, decision: true },
			projectTrusted: true,
		}),
		rts_child_inherited: trustSelectorUiEncoded(child, {
			savedDecision: { path: parent, decision: true },
			projectTrusted: true,
		}),
		rts_child_distrust: trustSelectorUiEncoded(child, {
			savedDecision: { path: child, decision: false },
			projectTrusted: false,
		}),
		rts_single: trustSelectorUiEncoded(single),
	};
}

function runCliSelectorsSessionSearch() {
	return {
		ss_empty: sessionSearchCount(""),
		ss_hit: sessionSearchCount("cadr"),
		ss_miss: sessionSearchCount("no-such-session-zz"),
		ss_re: sessionSearchCount("re:cadr"),
		ss_badre: sessionSearchCount("re:["),
		ss_named: sessionSearchCount("", "named"),
	};
}

function runCliSelectorsKeyText() {
	return {
		kt_ctrl: keybindingHintsModule.formatKeyText("ctrl+c"),
		kt_slash: keybindingHintsModule.formatKeyText("ctrl+c/escape"),
		kt_shift: keybindingHintsModule.formatKeyText("shift+tab"),
		kt_cap: keybindingHintsModule.formatKeyText("ctrl+c", { capitalize: true }),
		kt_empty: keybindingHintsModule.formatKeyText(""),
	};
}

function fuzzyFilterJoin(items, query, getText) {
	return fuzzyModule.fuzzyFilter(items, query, getText).join(",");
}

function runCliSelectorsFuzzyFilter() {
	const items = ["apple", "banana", "cherry"];
	const apps = ["a_p_p", "app", "application"];
	const cls = ["clone", "cl"];
	const model = [{ id: "gpt-5.5", provider: "openai-codex" }];
	return {
		ff_empty: fuzzyModule.fuzzyFilter(items, "", (item) => item).length,
		ff_an: fuzzyFilterJoin(items, "an", (item) => item),
		ff_app: fuzzyFilterJoin(apps, "app", (item) => item),
		ff_cl: fuzzyFilterJoin(cls, "cl", (item) => item),
		ff_slash: fuzzyModule.fuzzyFilter(model, "openai-codex/gpt-5.5", (entry) => `${entry.id} ${entry.provider}`)
			.length,
	};
}

function deleteQueryChar(value) {
	if (value.length === 0) {
		return value;
	}
	const segmenter = tuiUtilsModule.getGraphemeSegmenter();
	const graphemes = [...segmenter.segment(value)];
	const lastGrapheme = graphemes[graphemes.length - 1];
	const graphemeLength = lastGrapheme ? lastGrapheme.segment.length : 1;
	return value.slice(0, value.length - graphemeLength);
}

function runCliSelectorsDeleteQuery() {
	return {
		dq_empty: deleteQueryChar(""),
		dq_a: deleteQueryChar("a"),
		dq_abc: deleteQueryChar("abc"),
		dq_cafe: deleteQueryChar("café"),
		dq_emoji: deleteQueryChar("a🙂b"),
		dq_combining: deleteQueryChar(`e\u0301`),
	};
}

function visibleSliceSummary(count, selected, maximum) {
	const start = Math.max(0, Math.min(selected - Math.floor(maximum / 2), count - maximum));
	const end = Math.min(start + maximum, count);
	return [start, end, end - start, count];
}

function runCliSelectorsVisibleSlice() {
	const fixtures = [
		[0, 0, 8],
		[5, 2, 8],
		[20, 10, 8],
		[20, 0, 8],
		[20, 19, 8],
		[3, 1, 8],
	];
	return fixtures.map((fixture) => visibleSliceSummary(...fixture));
}

function moveIndex(selected, count, delta) {
	if (count <= 0) {
		return 0;
	}
	return ((selected + delta) % count + count) % count;
}

function runCliSelectorsMoveIndex() {
	const fixtures = [
		[0, 0, 1],
		[0, 5, -1],
		[4, 5, 1],
		[2, 5, 3],
		[2, 5, -2],
		[1, 5, 10],
	];
	return fixtures.map((fixture) => moveIndex(...fixture));
}

function alignLeftRight(left, right, width) {
	const rightText = tuiUtilsModule.truncateToWidth(right, Math.max(0, width), "");
	const availableLeft = Math.max(0, width - tuiUtilsModule.visibleWidth(rightText) - 1);
	const leftText = tuiUtilsModule.truncateToWidth(left, availableLeft, "");
	const spacing = Math.max(
		0,
		width - tuiUtilsModule.visibleWidth(leftText) - tuiUtilsModule.visibleWidth(rightText),
	);
	return `${leftText}${" ".repeat(spacing)}${rightText}`;
}

function runCliSelectorsAlignLeftRight() {
	const fixtures = [
		["Title", "Sort: Recent", 40],
		["Very Long Left Title Here", "Right", 20],
		["Left", "Very Long Right Side Text", 20],
		["ABCDEFGHIJ", "KLMNOPQRST", 10],
		["", "Right Only", 15],
		["Left Only", "", 15],
	];
	return fixtures.map(([left, right, w]) => alignLeftRight(left, right, w));
}

function fitLine(line, width, { pad = false, ellipsis = "" } = {}) {
	const available = Math.max(0, width);
	const limited = tuiUtilsModule.truncateToWidth(line, available, ellipsis);
	const padding = pad
		? Math.max(0, available - tuiUtilsModule.visibleWidth(limited))
		: 0;
	return `${limited}${" ".repeat(padding)}`;
}

function runCliSelectorsFitLine() {
	return [
		fitLine("hello", 10),
		fitLine("hello world", 5),
		fitLine("hello", 10, { pad: true }),
		fitLine("hello world", 8, { ellipsis: "..." }),
		fitLine("café🙂", 4),
		fitLine("", 5, { pad: true }),
	];
}

function borderLinePi(width, colorName = "border") {
	const border = new dynamicBorderModule.DynamicBorder((segment) =>
		themeModule.theme.fg(colorName, segment),
	);
	return border.render(width)[0];
}

function runCliSelectorsBorderLine() {
	return [
		borderLinePi(40),
		borderLinePi(40, "accent"),
		borderLinePi(1),
		borderLinePi(80),
		borderLinePi(10, "accent"),
		borderLinePi(20),
	];
}

function selectedLinePi(line, width) {
	return themeModule.theme.bg("selectedBg", fitLine(line, width, { pad: true }));
}

function runCliSelectorsSelectedLine() {
	return [
		selectedLinePi("hello", 10),
		selectedLinePi("hello world", 8),
		selectedLinePi("café🙂", 6),
		selectedLinePi("", 5),
		selectedLinePi("item", 20),
		selectedLinePi("ABCDEFGHIJ", 5),
	];
}

function mutedLinePi(line, width) {
	return fitLine(themeModule.theme.fg("muted", line), width);
}

function runCliSelectorsMutedLine() {
	return [
		mutedLinePi("hello", 10),
		mutedLinePi("hello world", 8),
		mutedLinePi("café🙂", 6),
		mutedLinePi("", 5),
		mutedLinePi("item", 20),
		mutedLinePi("ABCDEFGHIJ", 5),
	];
}

function dimLinePi(line, width) {
	return fitLine(themeModule.theme.fg("dim", line), width);
}

function runCliSelectorsDimLine() {
	return [
		dimLinePi("hello", 10),
		dimLinePi("hello world", 8),
		dimLinePi("café🙂", 6),
		dimLinePi("", 5),
		dimLinePi("item", 20),
		dimLinePi("ABCDEFGHIJ", 5),
	];
}

function csiModifiedArrow(modifier, direction) {
	return `\x1b[1;${modifier}${direction}`;
}

function runCliSelectorsModifiedCursorKey() {
	return [
		keysModule.parseKey(csiModifiedArrow(1, "A")),
		keysModule.parseKey(csiModifiedArrow(2, "B")),
		keysModule.parseKey(csiModifiedArrow(5, "C")),
		keysModule.parseKey(csiModifiedArrow(3, "D")),
		keysModule.parseKey(csiModifiedArrow(6, "A")),
		keysModule.parseKey(csiModifiedArrow(9, "B")),
	];
}

function componentTextLine(line, width, paddingX = 1) {
	const margin = " ".repeat(Math.max(0, paddingX));
	return fitLine(`${margin}${line}${margin}`, width, { pad: true });
}

function selectorBoldTitle(title) {
	// chalk.bold("") is a no-op; cadr theme-bold still emits SGR wrappers.
	if (title.length === 0) {
		return "\x1b[1m\x1b[22m";
	}
	return themeModule.theme.bold(title);
}

function titleLinePi(title, width) {
	return componentTextLine(themeModule.theme.fg("accent", selectorBoldTitle(title)), width);
}

function runCliSelectorsTitleLine() {
	return [
		titleLinePi("Resume Session", 40),
		titleLinePi("Very Long Title Here That Truncates", 20),
		titleLinePi("", 10),
		titleLinePi("café", 15),
		titleLinePi("A", 5),
		titleLinePi("Models", 30),
	];
}

function runCliSelectorsOverlayTitleLine() {
	return [
		titleLinePi("Select provider to configure:", 40),
		titleLinePi("Very Long Auth Overlay Title That Truncates", 20),
		titleLinePi("", 10),
		titleLinePi("café", 15),
		titleLinePi("A", 5),
		titleLinePi("Project trust", 30),
	];
}

function selectorInputLinePi(value, width) {
	const input = new inputModule.Input();
	for (const ch of value) {
		input.handleInput(ch);
	}
	input.focused = false;
	return input.render(width)[0];
}

function runCliSelectorsInputLine() {
	return [
		selectorInputLinePi("", 20),
		selectorInputLinePi("hello", 20),
		selectorInputLinePi("ab", 12),
		selectorInputLinePi("你🙂a", 10),
		selectorInputLinePi("你🙂a", 3),
		selectorInputLinePi("가나다라마바사아자차카타파하", 20),
	];
}

function selectorKeybindingTextPi(manager, name) {
	return manager.getKeys(name).join("/");
}

function runCliSelectorsKeybindingText() {
	const defaultManager = new keybindingsModule.KeybindingsManager(keybindingsModule.TUI_KEYBINDINGS);
	const customManager = new keybindingsModule.KeybindingsManager(keybindingsModule.TUI_KEYBINDINGS, {
		"tui.select.confirm": "ctrl+x",
		"tui.select.cancel": ["alt+x", "ctrl+c"],
	});
	return [
		selectorKeybindingTextPi(defaultManager, "tui.select.confirm"),
		selectorKeybindingTextPi(defaultManager, "tui.select.cancel"),
		selectorKeybindingTextPi(defaultManager, "tui.editor.cursorLeft"),
		selectorKeybindingTextPi(defaultManager, "tui.editor.historyPrevious"),
		selectorKeybindingTextPi(customManager, "tui.select.confirm"),
		selectorKeybindingTextPi(customManager, "tui.select.cancel"),
	];
}

function selectorKeybindingHintPi(manager, name, description) {
	return keybindingHintsModule.rawKeyHint(selectorKeybindingTextPi(manager, name), description);
}

function runCliSelectorsKeybindingHint() {
	const defaultManager = new keybindingsModule.KeybindingsManager(keybindingsModule.TUI_KEYBINDINGS);
	const customManager = new keybindingsModule.KeybindingsManager(keybindingsModule.TUI_KEYBINDINGS, {
		"tui.select.confirm": "ctrl+x",
		"tui.select.cancel": ["alt+x", "ctrl+c"],
	});
	return [
		selectorKeybindingHintPi(defaultManager, "tui.select.confirm", "confirm"),
		selectorKeybindingHintPi(defaultManager, "tui.select.cancel", "cancel"),
		selectorKeybindingHintPi(defaultManager, "tui.editor.cursorLeft", "left"),
		selectorKeybindingHintPi(defaultManager, "tui.editor.historyPrevious", "prev"),
		selectorKeybindingHintPi(customManager, "tui.select.confirm", "save"),
		selectorKeybindingHintPi(customManager, "tui.select.cancel", "cancel"),
	];
}

async function measureCliSelectorsSessionSearch() {
	const visibleSlice = runCliSelectorsVisibleSlice();
	const moveIndexResults = runCliSelectorsMoveIndex();
	const alignLeftRightResults = runCliSelectorsAlignLeftRight();
	const fitLineResults = runCliSelectorsFitLine();
	const borderLineResults = runCliSelectorsBorderLine();
	const selectedLineResults = runCliSelectorsSelectedLine();
	const mutedLineResults = runCliSelectorsMutedLine();
	const dimLineResults = runCliSelectorsDimLine();
	const modifiedCursorKeyResults = runCliSelectorsModifiedCursorKey();
	const titleLineResults = runCliSelectorsTitleLine();
	const overlayTitleLineResults = runCliSelectorsOverlayTitleLine();
	const inputLineResults = runCliSelectorsInputLine();
	const keybindingTextResults = runCliSelectorsKeybindingText();
	const keybindingHintResults = runCliSelectorsKeybindingHint();
	const sessionFormatAgeResults = runCliSelectorsSessionFormatAge();
	const sessionRecordLabelResults = runCliSelectorsSessionRecordLabel();
	const sessionShortenPathResults = runCliSelectorsSessionShortenPath();
	const sessionQuotedSearchResults = runCliSelectorsSessionQuotedSearch();
	const sessionThreadRecordsResults = runCliSelectorsSessionThreadRecords();
	const sessionBindingLabelResults = runCliSelectorsSessionBindingLabel();
	const sessionSamePathResults = runCliSelectorsSessionSamePath();
	const sessionQuotedPResults = runCliSelectorsSessionQuotedP();
	const sessionNamedPResults = runCliSelectorsSessionNamedP();
	const settingsThinkingDescriptionResults = runCliSelectorsSettingsThinkingDescription();
	const settingsDisplayValueResults = runCliSelectorsSettingsDisplayValue();
	const settingsAutomaticThemeSettingResults = runCliSelectorsSettingsAutomaticThemeSetting();
	const settingsActiveAutomaticThemeResults = runCliSelectorsSettingsActiveAutomaticTheme();
	const settingsCycleResults = runCliSelectorsSettingsCycle();
	const settingsApplyFilterResults = runCliSelectorsSettingsApplyFilter();
	const treeEntryFilteredResults = runCliSelectorsTreeEntryFiltered();
	const treeQueryMatchesResults = runCliSelectorsTreeQueryMatches();
	const treeEntrySearchTextResults = runCliSelectorsTreeEntrySearchText();
	const treeSettingsEntryPResults = runCliSelectorsTreeSettingsEntryP();
	const treeNormalizeDisplayTextResults = runCliSelectorsTreeNormalizeDisplayText();
	const treeStatusLabelsResults = runCliSelectorsTreeStatusLabels();
	const treeShortenPathResults = runCliSelectorsTreeShortenPath();
	const treeFoldablePResults = runCliSelectorsTreeFoldableP();
	const treeToolArgumentResults = runCliSelectorsTreeToolArgument();
	const treeCycleFilterResults = runCliSelectorsTreeCycleFilter();
	const treeFormatLabelTimestampResults = runCliSelectorsTreeFormatLabelTimestamp();
	const treeIsoTimestampResults = runCliSelectorsTreeIsoTimestamp();
	const treeFormatToolCallResults = runCliSelectorsTreeFormatToolCall();
	const treeEntryDisplayTextResults = runCliSelectorsTreeEntryDisplayText();
	const treePrefixResults = runCliSelectorsTreePrefix();
	const treeVisualNodesResults = runCliSelectorsTreeVisualNodes();
	const treeHorizontalViewportResults = runCliSelectorsTreeHorizontalViewport();
	const treeHelpKeysResults = runCliSelectorsTreeHelpKeys();
	const treeHelpKeyResults = runCliSelectorsTreeHelpKey();
	const treeAppKeyPResults = runCliSelectorsTreeAppKeyP();
	const treeHelpLinesResults = runCliSelectorsTreeHelpLines();
	const treeActivePathResults = runCliSelectorsTreeActivePath();
	const treeNearestVisibleIdResults = runCliSelectorsTreeNearestVisibleId();
	const treePrioritizeActiveResults = runCliSelectorsTreePrioritizeActive();
	const treeEntryMapResults = runCliSelectorsTreeEntryMap();
	const treeOrderEntriesResults = runCliSelectorsTreeOrderEntries();
	const treeRebuildVisibleMapsResults = runCliSelectorsTreeRebuildVisibleMaps();
	const treeApplyFilterResults = runCliSelectorsTreeApplyFilter();
	const treeRenderLinesResults = runCliSelectorsTreeRenderLines();
	const treeMoveResults = runCliSelectorsTreeMove();
	const treeFoldOrUpResults = runCliSelectorsTreeFoldOrUp();
	const treeUnfoldOrDownResults = runCliSelectorsTreeUnfoldOrDown();
	const treeBranchSegmentIdResults = runCliSelectorsTreeBranchSegmentId();
	const treeSetQueryResults = runCliSelectorsTreeSetQuery();
	const treeSetFilterResults = runCliSelectorsTreeSetFilter();
	const treeCopySelectedResults = runCliSelectorsTreeCopySelected();
	const treeToggleLabelTimestampsResults = runCliSelectorsTreeToggleLabelTimestamps();
	const treeStartLabelEditResults = runCliSelectorsTreeStartLabelEdit();
	const treeConfirmLabelResults = runCliSelectorsTreeConfirmLabel();
	const treeCancelLabelResults = runCliSelectorsTreeCancelLabel();
	const treeHandleRawInputResults = runCliSelectorsTreeHandleRawInput();
	const treeHandleEventResults = runCliSelectorsTreeHandleEvent();
	const treeHandleLabelEventResults = runCliSelectorsTreeHandleLabelEvent();
	const treeSelectedEntryResults = runCliSelectorsTreeSelectedEntry();
	const treeSelectedIdResults = runCliSelectorsTreeSelectedId();
	const treeSelectIdResults = runCliSelectorsTreeSelectId();
	const treeVisibleIdsResults = runCliSelectorsTreeVisibleIds();
	const projectTrustOptionsResults = runCliSelectorsProjectTrustOptions();
	const trustSelectorSelectionResults = runCliSelectorsTrustSelectorSelection();
	const trustDecisionDescriptionResults = runCliSelectorsTrustDecisionDescription();
	const trustSelectorMoveResults = runCliSelectorsTrustSelectorMove();
	const trustSelectorHandleEventResults = runCliSelectorsTrustSelectorHandleEvent();
	const trustSelectorHandleRawInputResults = runCliSelectorsTrustSelectorHandleRawInput();
	const trustSelectorRenderLinesResults = runCliSelectorsTrustSelectorUiState();
	const observed = {
		...runCliSelectorsSessionSearch(),
		...runCliSelectorsKeyText(),
		...runCliSelectorsFuzzyFilter(),
		...runCliSelectorsDeleteQuery(),
		vs0: visibleSlice[0][0],
		vs0_end: visibleSlice[0][1],
		vs0_vis: visibleSlice[0][2],
		vs5: visibleSlice[1][0],
		vs5_vis: visibleSlice[1][2],
		vs20_mid: visibleSlice[2][0],
		vs20_mid_vis: visibleSlice[2][2],
		vs20_top: visibleSlice[3][0],
		vs20_bot: visibleSlice[4][0],
		vs20_bot_vis: visibleSlice[4][2],
		vs3_vis: visibleSlice[5][2],
		mi_empty: moveIndexResults[0],
		mi_wrap_up: moveIndexResults[1],
		mi_wrap_dn: moveIndexResults[2],
		mi_fwd: moveIndexResults[3],
		mi_back: moveIndexResults[4],
		mi_big: moveIndexResults[5],
		alr_wide: alignLeftRightResults[0],
		alr_trunc_left: alignLeftRightResults[1],
		alr_trunc_right: alignLeftRightResults[2],
		alr_narrow: alignLeftRightResults[3],
		alr_empty_left: alignLeftRightResults[4],
		alr_empty_right: alignLeftRightResults[5],
		fl_short: fitLineResults[0],
		fl_trunc: fitLineResults[1],
		fl_pad: fitLineResults[2],
		fl_ellipsis: fitLineResults[3],
		fl_wide: fitLineResults[4],
		fl_empty: fitLineResults[5],
		bl_w40: borderLineResults[0],
		bl_w40_acc: borderLineResults[1],
		bl_w1: borderLineResults[2],
		bl_w80: borderLineResults[3],
		bl_w10_acc: borderLineResults[4],
		bl_w20: borderLineResults[5],
		sl_short: selectedLineResults[0],
		sl_trunc: selectedLineResults[1],
		sl_wide: selectedLineResults[2],
		sl_empty: selectedLineResults[3],
		sl_pad20: selectedLineResults[4],
		sl_narrow: selectedLineResults[5],
		ml_short: mutedLineResults[0],
		ml_trunc: mutedLineResults[1],
		ml_wide: mutedLineResults[2],
		ml_empty: mutedLineResults[3],
		ml_item20: mutedLineResults[4],
		ml_narrow: mutedLineResults[5],
		dl_short: dimLineResults[0],
		dl_trunc: dimLineResults[1],
		dl_wide: dimLineResults[2],
		dl_empty: dimLineResults[3],
		dl_item20: dimLineResults[4],
		dl_narrow: dimLineResults[5],
		mck_up: modifiedCursorKeyResults[0],
		mck_shift_dn: modifiedCursorKeyResults[1],
		mck_ctrl_rt: modifiedCursorKeyResults[2],
		mck_alt_lt: modifiedCursorKeyResults[3],
		mck_ctrl_shift_up: modifiedCursorKeyResults[4],
		mck_super_dn: modifiedCursorKeyResults[5],
		tl_short: titleLineResults[0],
		tl_trunc: titleLineResults[1],
		tl_empty: titleLineResults[2],
		tl_wide: titleLineResults[3],
		tl_narrow: titleLineResults[4],
		tl_normal: titleLineResults[5],
		otl_short: overlayTitleLineResults[0],
		otl_trunc: overlayTitleLineResults[1],
		otl_empty: overlayTitleLineResults[2],
		otl_wide: overlayTitleLineResults[3],
		otl_narrow: overlayTitleLineResults[4],
		otl_normal: overlayTitleLineResults[5],
		il_empty: inputLineResults[0],
		il_short: inputLineResults[1],
		il_ab12: inputLineResults[2],
		il_grapheme: inputLineResults[3],
		il_narrow: inputLineResults[4],
		il_scroll: inputLineResults[5],
		kbt_confirm: keybindingTextResults[0],
		kbt_cancel: keybindingTextResults[1],
		kbt_left: keybindingTextResults[2],
		kbt_empty: keybindingTextResults[3],
		kbt_custom_confirm: keybindingTextResults[4],
		kbt_custom_cancel: keybindingTextResults[5],
		kbh_confirm: keybindingHintResults[0],
		kbh_cancel: keybindingHintResults[1],
		kbh_left: keybindingHintResults[2],
		kbh_empty: keybindingHintResults[3],
		kbh_custom_save: keybindingHintResults[4],
		kbh_custom_cancel: keybindingHintResults[5],
		sfa_now: sessionFormatAgeResults.sfa_now,
		sfa_sec: sessionFormatAgeResults.sfa_sec,
		sfa_min: sessionFormatAgeResults.sfa_min,
		sfa_hour: sessionFormatAgeResults.sfa_hour,
		sfa_day: sessionFormatAgeResults.sfa_day,
		sfa_week: sessionFormatAgeResults.sfa_week,
		srl_named: sessionRecordLabelResults.srl_named,
		srl_first: sessionRecordLabelResults.srl_first,
		srl_empty: sessionRecordLabelResults.srl_empty,
		srl_ctrl: sessionRecordLabelResults.srl_ctrl,
		srl_name_ctrl: sessionRecordLabelResults.srl_name_ctrl,
		ssp_home: sessionShortenPathResults.ssp_home,
		ssp_prefix: sessionShortenPathResults.ssp_prefix,
		ssp_abs: sessionShortenPathResults.ssp_abs,
		ssp_proj: sessionShortenPathResults.ssp_proj,
		ssp_empty: sessionShortenPathResults.ssp_empty,
		sqs_cadr: sessionQuotedSearchResults.sqs_cadr,
		sqs_phrase: sessionQuotedSearchResults.sqs_phrase,
		sqs_miss: sessionQuotedSearchResults.sqs_miss,
		sqs_other_miss: sessionQuotedSearchResults.sqs_other_miss,
		sqs_name: sessionQuotedSearchResults.sqs_name,
		sqs_other_hit: sessionQuotedSearchResults.sqs_other_hit,
		str_count: sessionThreadRecordsResults.str_count,
		str_depths: sessionThreadRecordsResults.str_depths,
		str_ids: sessionThreadRecordsResults.str_ids,
		sbl_confirm: sessionBindingLabelResults.sbl_confirm,
		sbl_delete: sessionBindingLabelResults.sbl_delete,
		sbl_noninvasive: sessionBindingLabelResults.sbl_noninvasive,
		sbl_fallback: sessionBindingLabelResults.sbl_fallback,
		sbl_custom: sessionBindingLabelResults.sbl_custom,
		ssp_same: sessionSamePathResults.ssp_same,
		ssp_diff: sessionSamePathResults.ssp_diff,
		ssp_nil_left: sessionSamePathResults.ssp_nil_left,
		ssp_nil_right: sessionSamePathResults.ssp_nil_right,
		ssp_nil_both: sessionSamePathResults.ssp_nil_both,
		sqp_phrase: sessionQuotedPResults.sqp_phrase,
		sqp_words: sessionQuotedPResults.sqp_words,
		sqp_plain: sessionQuotedPResults.sqp_plain,
		sqp_empty: sessionQuotedPResults.sqp_empty,
		sqp_one: sessionQuotedPResults.sqp_one,
		sqp_open: sessionQuotedPResults.sqp_open,
		snp_named: sessionNamedPResults.snp_named,
		snp_whitespace: sessionNamedPResults.snp_whitespace,
		snp_empty: sessionNamedPResults.snp_empty,
		snp_nil: sessionNamedPResults.snp_nil,
		std_off: settingsThinkingDescriptionResults.std_off,
		std_minimal: settingsThinkingDescriptionResults.std_minimal,
		std_low: settingsThinkingDescriptionResults.std_low,
		std_medium: settingsThinkingDescriptionResults.std_medium,
		std_high: settingsThinkingDescriptionResults.std_high,
		std_xhigh: settingsThinkingDescriptionResults.std_xhigh,
		std_max: settingsThinkingDescriptionResults.std_max,
		std_unknown: settingsThinkingDescriptionResults.std_unknown,
		sdv_true: settingsDisplayValueResults.sdv_true,
		sdv_false: settingsDisplayValueResults.sdv_false,
		sdv_symbol: settingsDisplayValueResults.sdv_symbol,
		sdv_int: settingsDisplayValueResults.sdv_int,
		sdv_string: settingsDisplayValueResults.sdv_string,
		sats_solarized: settingsAutomaticThemeSettingResults.sats_solarized,
		sats_same: settingsAutomaticThemeSettingResults.sats_same,
		sats_light_dark: settingsAutomaticThemeSettingResults.sats_light_dark,
		saat_light_term: settingsActiveAutomaticThemeResults.saat_light_term,
		saat_dark_term: settingsActiveAutomaticThemeResults.saat_dark_term,
		saat_light_pair: settingsActiveAutomaticThemeResults.saat_light_pair,
		ssc_true: settingsCycleResults.ssc_true,
		ssc_transport: settingsCycleResults.ssc_transport,
		ssc_wrap: settingsCycleResults.ssc_wrap,
		ssc_missing: settingsCycleResults.ssc_missing,
		sap_empty: settingsApplyFilterResults.sap_empty,
		sap_trans: settingsApplyFilterResults.sap_trans,
		sap_none: settingsApplyFilterResults.sap_none,
		sap_app: settingsApplyFilterResults.sap_app,
		tef_user_def: treeEntryFilteredResults.tef_user_def,
		tef_label_def: treeEntryFilteredResults.tef_label_def,
		tef_user_uo: treeEntryFilteredResults.tef_user_uo,
		tef_tool_nt: treeEntryFilteredResults.tef_tool_nt,
		tef_labeled_lo: treeEntryFilteredResults.tef_labeled_lo,
		tef_all_label: treeEntryFilteredResults.tef_all_label,
		tqm_hit: treeQueryMatchesResults.tqm_hit,
		tqm_miss: treeQueryMatchesResults.tqm_miss,
		tqm_multi: treeQueryMatchesResults.tqm_multi,
		tqm_partial: treeQueryMatchesResults.tqm_partial,
		tqm_empty: treeQueryMatchesResults.tqm_empty,
		tese_sparse: treeEntrySearchTextResults.tese_sparse,
		tese_label: treeEntrySearchTextResults.tese_label,
		tese_empty: treeEntrySearchTextResults.tese_empty,
		tese_full: treeEntrySearchTextResults.tese_full,
		tese_text: treeEntrySearchTextResults.tese_text,
		tsep_label: treeSettingsEntryPResults.tsep_label,
		tsep_user: treeSettingsEntryPResults.tsep_user,
		tsep_custom: treeSettingsEntryPResults.tsep_custom,
		tsep_model: treeSettingsEntryPResults.tsep_model,
		tsep_think: treeSettingsEntryPResults.tsep_think,
		tsep_session: treeSettingsEntryPResults.tsep_session,
		tnd_hello: treeNormalizeDisplayTextResults.tnd_hello,
		tnd_spaced: treeNormalizeDisplayTextResults.tnd_spaced,
		tnd_newline: treeNormalizeDisplayTextResults.tnd_newline,
		tnd_empty: treeNormalizeDisplayTextResults.tnd_empty,
		tnd_ws: treeNormalizeDisplayTextResults.tnd_ws,
		tsl_empty: treeStatusLabelsResults.tsl_empty,
		tsl_notools: treeStatusLabelsResults.tsl_notools,
		tsl_user: treeStatusLabelsResults.tsl_user,
		tsl_labeled: treeStatusLabelsResults.tsl_labeled,
		tsl_all: treeStatusLabelsResults.tsl_all,
		tsl_time: treeStatusLabelsResults.tsl_time,
		tsl_both: treeStatusLabelsResults.tsl_both,
		tsp_home: treeShortenPathResults.tsp_home,
		tsp_prefix: treeShortenPathResults.tsp_prefix,
		tsp_abs: treeShortenPathResults.tsp_abs,
		tsp_proj: treeShortenPathResults.tsp_proj,
		tsp_empty: treeShortenPathResults.tsp_empty,
		tfp_root: treeFoldablePResults.tfp_root,
		tfp_leaf: treeFoldablePResults.tfp_leaf,
		tfp_only_child: treeFoldablePResults.tfp_only_child,
		tfp_branch: treeFoldablePResults.tfp_branch,
		tta_path: treeToolArgumentResults.tta_path,
		tta_file: treeToolArgumentResults.tta_file,
		tta_prio: treeToolArgumentResults.tta_prio,
		tta_miss: treeToolArgumentResults.tta_miss,
		tta_nil: treeToolArgumentResults.tta_nil,
		tcf_def_fwd: treeCycleFilterResults.tcf_def_fwd,
		tcf_nt_back: treeCycleFilterResults.tcf_nt_back,
		tcf_all_fwd: treeCycleFilterResults.tcf_all_fwd,
		tcf_user_fwd: treeCycleFilterResults.tcf_user_fwd,
		...treeFormatLabelTimestampResults,
		...treeIsoTimestampResults,
		...treeFormatToolCallResults,
		...treeEntryDisplayTextResults,
		...treePrefixResults,
		...treeVisualNodesResults,
		...treeHorizontalViewportResults,
		...treeHelpKeysResults,
		...treeHelpKeyResults,
		...treeAppKeyPResults,
		...treeHelpLinesResults,
		...treeActivePathResults,
		...treeNearestVisibleIdResults,
		...treePrioritizeActiveResults,
		...treeEntryMapResults,
		...treeOrderEntriesResults,
		...treeRebuildVisibleMapsResults,
		...treeApplyFilterResults,
		...treeRenderLinesResults,
		...treeMoveResults,
		...treeFoldOrUpResults,
		...treeUnfoldOrDownResults,
		...treeBranchSegmentIdResults,
		...treeSetQueryResults,
		...treeSetFilterResults,
		...treeCopySelectedResults,
		...treeToggleLabelTimestampsResults,
		...treeStartLabelEditResults,
		...treeConfirmLabelResults,
		...treeCancelLabelResults,
		...treeHandleRawInputResults,
		...treeHandleEventResults,
		...treeHandleLabelEventResults,
		...treeSelectedEntryResults,
		...treeSelectedIdResults,
		...treeSelectIdResults,
		...treeVisibleIdsResults,
		...projectTrustOptionsResults,
		...trustSelectorSelectionResults,
		...trustDecisionDescriptionResults,
		...trustSelectorMoveResults,
		...trustSelectorHandleEventResults,
		...trustSelectorHandleRawInputResults,
		...trustSelectorRenderLinesResults,
	};
	return {
		session_search: await collect("cli_selectors.session_search", () => {
			return () => runCliSelectorsSessionSearch();
		}),
		key_text: await collect("cli_selectors.key_text", () => {
			return () => runCliSelectorsKeyText();
		}),
		fuzzy_filter: await collect("cli_selectors.fuzzy_filter", () => {
			return () => runCliSelectorsFuzzyFilter();
		}),
		delete_query: await collect("cli_selectors.delete_query", () => {
			return () => runCliSelectorsDeleteQuery();
		}),
		visible_slice: await collect("cli_selectors.visible_slice", () => {
			return () => runCliSelectorsVisibleSlice();
		}),
		move_index: await collect("cli_selectors.move_index", () => {
			return () => runCliSelectorsMoveIndex();
		}),
		align_left_right: await collect("cli_selectors.align_left_right", () => {
			return () => runCliSelectorsAlignLeftRight();
		}),
		fit_line: await collect("cli_selectors.fit_line", () => {
			return () => runCliSelectorsFitLine();
		}),
		border_line: await collect("cli_selectors.border_line", () => {
			return () => runCliSelectorsBorderLine();
		}),
		selected_line: await collect("cli_selectors.selected_line", () => {
			return () => runCliSelectorsSelectedLine();
		}),
		muted_line: await collect("cli_selectors.muted_line", () => {
			return () => runCliSelectorsMutedLine();
		}),
		dim_line: await collect("cli_selectors.dim_line", () => {
			return () => runCliSelectorsDimLine();
		}),
		modified_cursor_key: await collect("cli_selectors.modified_cursor_key", () => {
			return () => runCliSelectorsModifiedCursorKey();
		}),
		title_line: await collect("cli_selectors.title_line", () => {
			return () => runCliSelectorsTitleLine();
		}),
		overlay_title_line: await collect("cli_selectors.overlay_title_line", () => {
			return () => runCliSelectorsOverlayTitleLine();
		}),
		input_line: await collect("cli_selectors.input_line", () => {
			return () => runCliSelectorsInputLine();
		}),
		keybinding_text: await collect("cli_selectors.keybinding_text", () => {
			return () => runCliSelectorsKeybindingText();
		}),
		keybinding_hint: await collect("cli_selectors.keybinding_hint", () => {
			return () => runCliSelectorsKeybindingHint();
		}),
		session_format_age: await collect("cli_selectors.session_format_age", () => {
			return () => runCliSelectorsSessionFormatAge();
		}),
		session_record_label: await collect("cli_selectors.session_record_label", () => {
			return () => runCliSelectorsSessionRecordLabel();
		}),
		session_shorten_path: await collect("cli_selectors.session_shorten_path", () => {
			return () => runCliSelectorsSessionShortenPath();
		}),
		session_quoted_search: await collect("cli_selectors.session_quoted_search", () => {
			return () => runCliSelectorsSessionQuotedSearch();
		}),
		session_thread_records: await collect("cli_selectors.session_thread_records", () => {
			return () => runCliSelectorsSessionThreadRecords();
		}),
		session_binding_label: await collect("cli_selectors.session_binding_label", () => {
			return () => runCliSelectorsSessionBindingLabel();
		}),
		session_same_path: await collect("cli_selectors.session_same_path", () => {
			return () => runCliSelectorsSessionSamePath();
		}),
		session_quoted_p: await collect("cli_selectors.session_quoted_p", () => {
			return () => runCliSelectorsSessionQuotedP();
		}),
		session_named_p: await collect("cli_selectors.session_named_p", () => {
			return () => runCliSelectorsSessionNamedP();
		}),
		settings_thinking_description: await collect(
			"cli_selectors.settings_thinking_description",
			() => {
				return () => runCliSelectorsSettingsThinkingDescription();
			},
		),
		settings_display_value: await collect("cli_selectors.settings_display_value", () => {
			return () => runCliSelectorsSettingsDisplayValue();
		}),
		settings_automatic_theme_setting: await collect(
			"cli_selectors.settings_automatic_theme_setting",
			() => {
				return () => runCliSelectorsSettingsAutomaticThemeSetting();
			},
		),
		settings_active_automatic_theme: await collect(
			"cli_selectors.settings_active_automatic_theme",
			() => {
				return () => runCliSelectorsSettingsActiveAutomaticTheme();
			},
		),
		settings_cycle: await collect("cli_selectors.settings_cycle", () => {
			return () => runCliSelectorsSettingsCycle();
		}),
		settings_apply_filter: await collect("cli_selectors.settings_apply_filter", () => {
			return () => runCliSelectorsSettingsApplyFilter();
		}),
		tree_entry_filtered: await collect("cli_selectors.tree_entry_filtered", () => {
			return () => runCliSelectorsTreeEntryFiltered();
		}),
		tree_query_matches: await collect("cli_selectors.tree_query_matches", () => {
			return () => runCliSelectorsTreeQueryMatches();
		}),
		tree_entry_search_text: await collect("cli_selectors.tree_entry_search_text", () => {
			return () => runCliSelectorsTreeEntrySearchText();
		}),
		tree_settings_entry_p: await collect("cli_selectors.tree_settings_entry_p", () => {
			return () => runCliSelectorsTreeSettingsEntryP();
		}),
		tree_normalize_display_text: await collect("cli_selectors.tree_normalize_display_text", () => {
			return () => runCliSelectorsTreeNormalizeDisplayText();
		}),
		tree_status_labels: await collect("cli_selectors.tree_status_labels", () => {
			return () => runCliSelectorsTreeStatusLabels();
		}),
		tree_shorten_path: await collect("cli_selectors.tree_shorten_path", () => {
			return () => runCliSelectorsTreeShortenPath();
		}),
		tree_foldable_p: await collect("cli_selectors.tree_foldable_p", () => {
			return () => runCliSelectorsTreeFoldableP();
		}),
		tree_tool_argument: await collect("cli_selectors.tree_tool_argument", () => {
			return () => runCliSelectorsTreeToolArgument();
		}),
		tree_cycle_filter: await collect("cli_selectors.tree_cycle_filter", () => {
			return () => runCliSelectorsTreeCycleFilter();
		}),
		tree_format_label_timestamp: await collect("cli_selectors.tree_format_label_timestamp", () => {
			return () => runCliSelectorsTreeFormatLabelTimestamp();
		}),
		tree_iso_timestamp: await collect("cli_selectors.tree_iso_timestamp", () => {
			return () => runCliSelectorsTreeIsoTimestamp();
		}),
		tree_format_tool_call: await collect("cli_selectors.tree_format_tool_call", () => {
			return () => runCliSelectorsTreeFormatToolCall();
		}),
		tree_entry_display_text: await collect("cli_selectors.tree_entry_display_text", () => {
			return () => runCliSelectorsTreeEntryDisplayText();
		}),
		tree_prefix: await collect("cli_selectors.tree_prefix", () => {
			return () => runCliSelectorsTreePrefix();
		}),
		tree_visual_nodes: await collect("cli_selectors.tree_visual_nodes", () => {
			return () => runCliSelectorsTreeVisualNodes();
		}),
		tree_horizontal_viewport: await collect("cli_selectors.tree_horizontal_viewport", () => {
			return () => runCliSelectorsTreeHorizontalViewport();
		}),
		tree_help_keys: await collect("cli_selectors.tree_help_keys", () => {
			return () => runCliSelectorsTreeHelpKeys();
		}),
		tree_help_key: await collect("cli_selectors.tree_help_key", () => {
			return () => runCliSelectorsTreeHelpKey();
		}),
		tree_app_key_p: await collect("cli_selectors.tree_app_key_p", () => {
			return () => runCliSelectorsTreeAppKeyP();
		}),
		tree_help_lines: await collect("cli_selectors.tree_help_lines", () => {
			return () => runCliSelectorsTreeHelpLines();
		}),
		tree_active_path: await collect("cli_selectors.tree_active_path", () => {
			return () => runCliSelectorsTreeActivePath();
		}),
		tree_nearest_visible_id: await collect("cli_selectors.tree_nearest_visible_id", () => {
			return () => runCliSelectorsTreeNearestVisibleId();
		}),
		tree_prioritize_active: await collect("cli_selectors.tree_prioritize_active", () => {
			return () => runCliSelectorsTreePrioritizeActive();
		}),
		tree_entry_map: await collect("cli_selectors.tree_entry_map", () => {
			return () => runCliSelectorsTreeEntryMap();
		}),
		tree_order_entries: await collect("cli_selectors.tree_order_entries", () => {
			return () => runCliSelectorsTreeOrderEntries();
		}),
		tree_rebuild_visible_maps: await collect("cli_selectors.tree_rebuild_visible_maps", () => {
			return () => runCliSelectorsTreeRebuildVisibleMaps();
		}),
		tree_apply_filter: await collect("cli_selectors.tree_apply_filter", () => {
			return () => runCliSelectorsTreeApplyFilter();
		}),
		tree_render_lines: await collect("cli_selectors.tree_render_lines", () => {
			return () => runCliSelectorsTreeRenderLines();
		}),
		tree_move: await collect("cli_selectors.tree_move", () => {
			return () => runCliSelectorsTreeMove();
		}),
		tree_fold_or_up: await collect("cli_selectors.tree_fold_or_up", () => {
			return () => runCliSelectorsTreeFoldOrUp();
		}),
		tree_unfold_or_down: await collect("cli_selectors.tree_unfold_or_down", () => {
			return () => runCliSelectorsTreeUnfoldOrDown();
		}),
		tree_branch_segment_id: await collect("cli_selectors.tree_branch_segment_id", () => {
			return () => runCliSelectorsTreeBranchSegmentId();
		}),
		tree_set_query: await collect("cli_selectors.tree_set_query", () => {
			return () => runCliSelectorsTreeSetQuery();
		}),
		tree_set_filter: await collect("cli_selectors.tree_set_filter", () => {
			return () => runCliSelectorsTreeSetFilter();
		}),
		tree_copy_selected: await collect("cli_selectors.tree_copy_selected", () => {
			return () => runCliSelectorsTreeCopySelected();
		}),
		tree_toggle_label_timestamps: await collect("cli_selectors.tree_toggle_label_timestamps", () => {
			return () => runCliSelectorsTreeToggleLabelTimestamps();
		}),
		tree_start_label_edit: await collect("cli_selectors.tree_start_label_edit", () => {
			return () => runCliSelectorsTreeStartLabelEdit();
		}),
		tree_confirm_label: await collect("cli_selectors.tree_confirm_label", () => {
			return () => runCliSelectorsTreeConfirmLabel();
		}),
		tree_cancel_label: await collect("cli_selectors.tree_cancel_label", () => {
			return () => runCliSelectorsTreeCancelLabel();
		}),
		tree_handle_raw_input: await collect("cli_selectors.tree_handle_raw_input", () => {
			return () => runCliSelectorsTreeHandleRawInput();
		}),
		tree_handle_event: await collect("cli_selectors.tree_handle_event", () => {
			return () => runCliSelectorsTreeHandleEvent();
		}),
		tree_handle_label_event: await collect("cli_selectors.tree_handle_label_event", () => {
			return () => runCliSelectorsTreeHandleLabelEvent();
		}),
		tree_selected_entry: await collect("cli_selectors.tree_selected_entry", () => {
			return () => runCliSelectorsTreeSelectedEntry();
		}),
		tree_selected_id: await collect("cli_selectors.tree_selected_id", () => {
			return () => runCliSelectorsTreeSelectedId();
		}),
		tree_select_id: await collect("cli_selectors.tree_select_id", () => {
			return () => runCliSelectorsTreeSelectId();
		}),
		tree_visible_ids: await collect("cli_selectors.tree_visible_ids", () => {
			return () => runCliSelectorsTreeVisibleIds();
		}),
		project_trust_options: await collect("cli_selectors.project_trust_options", () => {
			return () => runCliSelectorsProjectTrustOptions();
		}),
		trust_selector_selection: await collect("cli_selectors.trust_selector_selection", () => {
			return () => runCliSelectorsTrustSelectorSelection();
		}),
		trust_decision_description: await collect("cli_selectors.trust_decision_description", () => {
			return () => runCliSelectorsTrustDecisionDescription();
		}),
		trust_selector_move: await collect("cli_selectors.trust_selector_move", () => {
			return () => runCliSelectorsTrustSelectorMove();
		}),
		trust_selector_handle_event: await collect("cli_selectors.trust_selector_handle_event", () => {
			return () => runCliSelectorsTrustSelectorHandleEvent();
		}),
		trust_selector_handle_raw_input: await collect("cli_selectors.trust_selector_handle_raw_input", () => {
			return () => runCliSelectorsTrustSelectorHandleRawInput();
		}),
		trust_selector_ui_state: await collect("cli_selectors.trust_selector_ui_state", () => {
			return () => runCliSelectorsTrustSelectorUiState();
		}),
		observed,
	};
}

const websocketRecordedEvents = [
	{ type: "response.created", response: { id: "resp-1" } },
	{
		type: "response.output_item.added",
		output_index: 0,
		item: { type: "message" },
	},
	{
		type: "response.content_part.added",
		part: { type: "output_text", text: "" },
	},
	{ type: "response.output_text.delta", output_index: 0, delta: "Hello" },
	{
		type: "response.output_item.done",
		output_index: 0,
		item: {
			type: "message",
			id: "msg-resp-1",
			content: [{ type: "output_text", text: "Hello" }],
		},
	},
	{
		type: "response.completed",
		response: {
			id: "resp-1",
			status: "completed",
			usage: {
				input_tokens: 1,
				output_tokens: 1,
				input_tokens_details: { cached_tokens: 0 },
			},
		},
	},
];

class Goal20MockWebSocket {
	static OPEN = 1;
	readyState = Goal20MockWebSocket.OPEN;
	#listeners = new Map();

	constructor(_url, _protocols) {
		queueMicrotask(() => this.#dispatch("open", {}));
	}

	addEventListener(type, listener) {
		let listeners = this.#listeners.get(type);
		if (!listeners) {
			listeners = new Set();
			this.#listeners.set(type, listeners);
		}
		listeners.add(listener);
	}

	removeEventListener(type, listener) {
		this.#listeners.get(type)?.delete(listener);
	}

	send(_data) {
		queueMicrotask(() => {
			for (const event of websocketRecordedEvents) {
				this.#dispatch("message", { data: JSON.stringify(event) });
			}
		});
	}

	close() {}

	#dispatch(type, event) {
		for (const listener of this.#listeners.get(type) ?? []) listener(event);
	}
}

const websocketModel = {
	id: "gpt-5.5",
	name: "Goal 20 Codex WS",
	api: "openai-codex-responses",
	provider: "openai-codex",
	baseUrl: "https://chatgpt.com/backend-api",
	reasoning: false,
	input: ["text"],
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
	contextWindow: 128000,
	maxTokens: 4096,
};

const websocketContext = {
	systemPrompt: "You are a helpful assistant.",
	messages: [{ role: "user", content: "Say hello", timestamp: 1 }],
};

function installGoal20MockWebSocket() {
	globalThis.WebSocket = Goal20MockWebSocket;
}

async function runWebsocketStream(collectEvents) {
	const events = collectEvents ? [] : undefined;
	const stream = openaiCodexModule.stream(websocketModel, websocketContext, {
		apiKey: openaiCodexOauthToken,
		transport: "websocket",
		fetch: async () => {
			throw new Error("websocket pair must not use fetch");
		},
	});
	for await (const event of stream) events?.push(event.type);
	const message = await stream.result();
	return { events, message };
}

async function measureWebsocketStream() {
	installGoal20MockWebSocket();
	const observed = await runWebsocketStream(true);
	if (observed.message.stopReason !== "stop") {
		throw new Error(
			`websocket fixture stream produced stopReason ${observed.message.stopReason}`,
		);
	}
	const text = observed.message.content
		.filter((block) => block.type === "text")
		.map((block) => block.text)
		.join("");
	return {
		stream_roundtrip: await collect("websocket_stream.stream_roundtrip", () => {
			return () => runWebsocketStream(false);
		}),
		observed: {
			ws_text: text,
			stop_reason: observed.message.stopReason,
			text_characters: [...text].length,
			usage_input: observed.message.usage.input,
			usage_output: observed.message.usage.output,
		},
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

const pairedCacheModels = { getModel: () => ({ cost: { cacheRead: 0.3 } }) };

function pairedCacheAssistant({
	input = 0,
	cacheRead = 0,
	cacheWrite = 0,
	cost = {},
	model = "test-model",
	timestamp = 0,
} = {}) {
	return {
		role: "assistant",
		content: [],
		api: "anthropic-messages",
		provider: "test",
		model,
		usage: {
			input,
			output: 10,
			cacheRead,
			cacheWrite,
			totalTokens: 0,
			cost: {
				input: 0,
				output: 0,
				cacheRead: 0,
				cacheWrite: 0,
				total: 0,
				...cost,
			},
		},
		stopReason: "stop",
		timestamp,
	};
}

function pairedCacheEntry(message) {
	return { type: "message", id: "x", parentId: null, timestamp: "", message };
}

function cacheMissShape(miss) {
	if (!miss) return { tok: 0, idle: 0, chg: 0, hit: 0 };
	return {
		tok: miss.missedTokens,
		idle: miss.idleMs,
		chg: miss.modelChanged ? 1 : 0,
		hit: 1,
	};
}

function runCliSdkCacheMiss() {
	const turn1 = pairedCacheAssistant({
		cacheWrite: 100_000,
		cost: { cacheWrite: 0.375 },
		timestamp: 0,
	});
	const turn2 = pairedCacheAssistant({
		cacheRead: 100_000,
		cacheWrite: 5_000,
		cost: { cacheRead: 0.03, cacheWrite: 0.019 },
		timestamp: 60_000,
	});
	const entries = [pairedCacheEntry(turn1), pairedCacheEntry(turn2)];
	const miss = cacheStatsModule.detectCacheMiss(
		entries,
		pairedCacheAssistant({
			cacheWrite: 110_000,
			cost: { cacheWrite: 0.4125 },
			timestamp: 600_000,
		}),
		pairedCacheModels,
	);
	const switched = cacheStatsModule.detectCacheMiss(
		entries,
		pairedCacheAssistant({
			cacheWrite: 110_000,
			cost: { cacheWrite: 0.4125 },
			model: "other-model",
			timestamp: 120_000,
		}),
		pairedCacheModels,
	);
	const healthy = cacheStatsModule.detectCacheMiss(
		entries,
		pairedCacheAssistant({
			cacheRead: 105_000,
			cacheWrite: 2_000,
			cost: { cacheRead: 0.0315, cacheWrite: 0.0075 },
			timestamp: 120_000,
		}),
		pairedCacheModels,
	);
	const empty = cacheStatsModule.detectCacheMiss([], turn1, pairedCacheModels);
	const missShape = cacheMissShape(miss);
	const switchedShape = cacheMissShape(switched);
	return {
		cm_tok: missShape.tok,
		cm_idle: missShape.idle,
		cm_chg: missShape.chg,
		cm_hit: missShape.hit,
		sw_tok: switchedShape.tok,
		sw_idle: switchedShape.idle,
		sw_chg: switchedShape.chg,
		sw_hit: switchedShape.hit,
		healthy_hit: healthy ? 1 : 0,
		empty_hit: empty ? 1 : 0,
	};
}

function runCliSdkCacheWaste() {
	const turn1 = pairedCacheAssistant({
		cacheWrite: 100_000,
		cost: { cacheWrite: 0.375 },
		timestamp: 0,
	});
	const turn2 = pairedCacheAssistant({
		cacheRead: 100_000,
		cacheWrite: 5_000,
		cost: { cacheRead: 0.03, cacheWrite: 0.019 },
		timestamp: 60_000,
	});
	const turn3 = pairedCacheAssistant({
		cacheWrite: 110_000,
		cost: { cacheWrite: 0.4125 },
		timestamp: 120_000,
	});
	const afterReset = pairedCacheAssistant({
		cacheWrite: 20_000,
		cost: { cacheWrite: 0.075 },
		timestamp: 180_000,
	});
	const switched = pairedCacheAssistant({
		cacheWrite: 100_000,
		cost: { cacheWrite: 0.375 },
		model: "other-model",
		timestamp: 60_000,
	});
	const nocacheA = pairedCacheAssistant({ input: 100_000, timestamp: 0 });
	const nocacheB = pairedCacheAssistant({ input: 110_000, timestamp: 60_000 });
	const compaction = { type: "compaction", id: "c", parentId: null, timestamp: "" };
	const miss = cacheStatsModule.computeCacheWaste(
		[pairedCacheEntry(turn1), pairedCacheEntry(turn2), pairedCacheEntry(turn3)],
		pairedCacheModels,
	);
	const healthy = cacheStatsModule.computeCacheWaste(
		[pairedCacheEntry(turn1), pairedCacheEntry(turn2)],
		pairedCacheModels,
	);
	const reset = cacheStatsModule.computeCacheWaste(
		[pairedCacheEntry(turn1), compaction, pairedCacheEntry(afterReset)],
		pairedCacheModels,
	);
	const switchedWaste = cacheStatsModule.computeCacheWaste(
		[pairedCacheEntry(turn1), pairedCacheEntry(switched)],
		pairedCacheModels,
	);
	const nocache = cacheStatsModule.computeCacheWaste(
		[pairedCacheEntry(nocacheA), pairedCacheEntry(nocacheB)],
		pairedCacheModels,
	);
	return {
		cw_tok: miss.missedTokens,
		cw_n: miss.missCount,
		cw_healthy: healthy.missedTokens,
		cw_reset: reset.missedTokens,
		cw_sw_tok: switchedWaste.missedTokens,
		cw_sw_n: switchedWaste.missCount,
		cw_nocache: nocache.missedTokens,
	};
}

function runCliSdkThinkingLevel() {
	return {
		tl_off: argsModule.isValidThinkingLevel("off") ? 1 : 0,
		tl_min: argsModule.isValidThinkingLevel("minimal") ? 1 : 0,
		tl_low: argsModule.isValidThinkingLevel("low") ? 1 : 0,
		tl_med: argsModule.isValidThinkingLevel("medium") ? 1 : 0,
		tl_high: argsModule.isValidThinkingLevel("high") ? 1 : 0,
		tl_xhigh: argsModule.isValidThinkingLevel("xhigh") ? 1 : 0,
		tl_max: argsModule.isValidThinkingLevel("max") ? 1 : 0,
		tl_miss: argsModule.isValidThinkingLevel("nope") ? 1 : 0,
	};
}

const SDK_SESSION_LIST_ID = "019f0000-0000-7000-8000-00000000cadr";

function rewriteSessionJsonlCwd(source, dest, cwd) {
	const text = readFileSync(source, "utf8");
	const nl = text.indexOf("\n");
	const header = JSON.parse(text.slice(0, nl));
	header.cwd = cwd;
	mkdirSync(path.dirname(dest), { recursive: true });
	writeFileSync(dest, `${JSON.stringify(header)}${text.slice(nl)}`, "utf8");
}

function stageCliSdkSessionList() {
	const cwdDir = path.join(scratch, "sdk-cwd");
	const sessionDir = path.join(scratch, "sdk-sessions");
	const emptyDir = path.join(scratch, "sdk-sessions-empty");
	mkdirSync(cwdDir, { recursive: true });
	mkdirSync(sessionDir, { recursive: true });
	mkdirSync(emptyDir, { recursive: true });
	const cwd = realpathSync(cwdDir);
	const directory = realpathSync(sessionDir);
	const empty = realpathSync(emptyDir);
	for (let index = 0; index < 2; index += 1) {
		rewriteSessionJsonlCwd(
			path.join(fixtureDirectory, "session.jsonl"),
			path.join(directory, `sess-${index}.jsonl`),
			cwd,
		);
	}
	return { cwd, directory, empty };
}

async function runCliSdkSessionList() {
	const { cwd, directory, empty } = stageCliSdkSessionList();
	const listed = await sessionModule.SessionManager.list(cwd, directory);
	const missing = await sessionModule.SessionManager.list(cwd, empty);
	return {
		sl_n: listed.length,
		sl_id: listed.some((session) => session.id === SDK_SESSION_LIST_ID) ? 1 : 0,
		sl_empty: missing.length,
	};
}

function stageCliSdkAgentSession() {
	const cwdDir = path.join(scratch, "sdk-agent-cwd");
	const agentDir = path.join(scratch, "sdk-agent-dir");
	mkdirSync(cwdDir, { recursive: true });
	mkdirSync(agentDir, { recursive: true });
	mkdirSync(path.join(cwdDir, ".cadr"), { recursive: true });
	mkdirSync(path.join(cwdDir, ".pi"), { recursive: true });
	return { cwd: realpathSync(cwdDir), agentDir: realpathSync(agentDir) };
}

async function runCliSdkAgentSession() {
	const { cwd, agentDir } = stageCliSdkAgentSession();
	const settings = settingsModule.SettingsManager.create(cwd, agentDir);
	const loader = new resourceLoaderModule.DefaultResourceLoader({
		cwd,
		agentDir,
		settingsManager: settings,
	});
	await loader.reload();
	const modelRuntime = await modelRuntimeModule.ModelRuntime.create({
		authPath: path.join(agentDir, "auth.json"),
		modelsPath: path.join(agentDir, "models.json"),
	});
	const sessionManager = sessionModule.SessionManager.inMemory(cwd);
	const { getModel } = await import(moduleUrl("packages/ai/src/compat.ts"));
	const { createAgentSession } = await import(moduleUrl("packages/coding-agent/src/core/sdk.ts"));
	const model = getModel("openai", "gpt-4o-mini");
	const result = await createAgentSession({
		cwd,
		agentDir,
		settingsManager: settings,
		resourceLoader: loader,
		modelRuntime,
		sessionManager,
		model,
		noTools: "all",
	});
	try {
		return {
			as_ok: result.session ? 1 : 0,
			as_model: result.session.model ? 1 : 0,
			as_fb: typeof result.modelFallbackMessage === "string" ? 1 : 0,
		};
	} finally {
		result.session?.dispose();
	}
}

async function runCliSdkSessionServices() {
	const { cwd, agentDir } = stageCliSdkAgentSession();
	const settings = settingsModule.SettingsManager.create(cwd, agentDir);
	const modelRuntime = await modelRuntimeModule.ModelRuntime.create({
		authPath: path.join(agentDir, "auth.json"),
		modelsPath: path.join(agentDir, "models.json"),
	});
	const { createAgentSessionServices } = await import(
		moduleUrl("packages/coding-agent/src/core/agent-session-services.ts")
	);
	const services = await createAgentSessionServices({
		cwd,
		agentDir,
		settingsManager: settings,
		modelRuntime,
	});
	return {
		ss_ok: services ? 1 : 0,
		ss_cwd: services.cwd.replace(/\/+$/u, "") === cwd.replace(/\/+$/u, "") ? 1 : 0,
		ss_snap: services.resourceLoader ? 1 : 0,
	};
}

async function runCliSdkModelRuntime() {
	const { agentDir } = stageCliSdkAgentSession();
	const runtime = await modelRuntimeModule.ModelRuntime.create({
		authPath: path.join(agentDir, "auth.json"),
		modelsPath: path.join(agentDir, "models.json"),
	});
	const ids = runtime.getProviders().map((provider) => provider.id);
	return {
		mr_oa: ids.includes("openai") ? 1 : 0,
		mr_an: ids.includes("anthropic") ? 1 : 0,
		mr_missp: ids.includes("no-such-provider") ? 1 : 0,
		mr_gpt: runtime.getModel("openai", "gpt-4o-mini") ? 1 : 0,
		mr_missm: runtime.getModel("openai", "no-such") ? 1 : 0,
	};
}

async function measureCliSdkVersionNewer() {
	const observed = {
		...runCliSdkVersionNewer(),
		...runCliSdkCacheMiss(),
		...runCliSdkCacheWaste(),
		...runCliSdkThinkingLevel(),
		...(await runCliSdkSessionList()),
		...(await runCliSdkAgentSession()),
		...(await runCliSdkSessionServices()),
		...(await runCliSdkModelRuntime()),
	};
	return {
		version_newer: await collect("cli_sdk.version_newer", () => {
			return () => runCliSdkVersionNewer();
		}),
		cache_miss: await collect("cli_sdk.cache_miss", () => {
			return () => runCliSdkCacheMiss();
		}),
		cache_waste: await collect("cli_sdk.cache_waste", () => {
			return () => runCliSdkCacheWaste();
		}),
		thinking_level: await collect("cli_sdk.thinking_level", () => {
			return () => runCliSdkThinkingLevel();
		}),
		session_list: await collect("cli_sdk.session_list", () => {
			return () => runCliSdkSessionList();
		}),
		agent_session: await collect("cli_sdk.agent_session", () => {
			return () => runCliSdkAgentSession();
		}),
		session_services: await collect("cli_sdk.session_services", () => {
			return () => runCliSdkSessionServices();
		}),
		model_runtime: await collect("cli_sdk.model_runtime", () => {
			return () => runCliSdkModelRuntime();
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

function runSkillPromptBuild() {
	const cwd = "/tmp/proj";
	const custom = systemPromptModule.buildSystemPrompt({
		customPrompt: "hello",
		cwd,
		selectedTools: ["read"],
	});
	const appended = systemPromptModule.buildSystemPrompt({
		customPrompt: "hello",
		cwd,
		appendSystemPrompt: "extra",
		selectedTools: ["read"],
	});
	const withCtx = systemPromptModule.buildSystemPrompt({
		customPrompt: "hello",
		cwd,
		selectedTools: ["read"],
		contextFiles: [{ path: "AGENTS.md", content: "be careful" }],
	});
	return {
		custom_len: custom.length,
		append_len: appended.length,
		ctx_len: withCtx.length,
		has_cwd: custom.includes("Current working directory: /tmp/proj") ? 1 : 0,
		has_extra: appended.includes("extra") ? 1 : 0,
		has_agents: withCtx.includes("AGENTS.md") ? 1 : 0,
	};
}

async function measureSkillPromptBuild() {
	const observed = runSkillPromptBuild();
	return {
		build_prompt: await collect("skill_prompt_load.build_prompt", () => {
			return () => runSkillPromptBuild();
		}),
		observed,
	};
}

function runCliBootstrapCodingTools() {
	const tools = codingToolsModule.createCodingTools("/tmp/proj");
	const names = tools.map((tool) => tool.name);
	return {
		count: names.length,
		baseline: names.join(",") === "read,bash,edit,write" ? 1 : 0,
		snippet_count: names.length,
		read_first: names[0] === "read" ? 1 : 0,
	};
}

async function measureCliBootstrapCodingTools() {
	const observed = runCliBootstrapCodingTools();
	return {
		coding_tools: await collect("cli_bootstrap_sessions.coding_tools", () => {
			return () => runCliBootstrapCodingTools();
		}),
		observed,
	};
}

function runAiRuntimeFauxBlocks() {
	const text = fauxProviderModule.fauxText("hello");
	const think = fauxProviderModule.fauxThinking("hmm");
	return {
		text_len: text.text.length,
		text: text.text,
		think_len: think.thinking.length,
		think: think.thinking,
	};
}

async function measureAiRuntimeFauxBlocks() {
	const observed = runAiRuntimeFauxBlocks();
	return {
		blocks: await collect("ai_runtime_faux.blocks", () => {
			return () => runAiRuntimeFauxBlocks();
		}),
		observed,
	};
}

function runHttpTransportParseUrl() {
	const https = new URL("https://example.com/foo");
	const http = new URL("http://localhost:8080/bar");
	return {
		https_scheme: https.protocol.replace(":", ""),
		https_host: https.hostname,
		https_path: https.pathname,
		http_scheme: http.protocol.replace(":", ""),
		http_host: http.hostname,
		http_port: Number(http.port),
		http_path: http.pathname,
	};
}

async function measureHttpTransportParseUrl() {
	const observed = runHttpTransportParseUrl();
	return {
		parse_url: await collect("http_transport.parse_url", () => {
			return () => runHttpTransportParseUrl();
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
process.stderr.write("goal20 pi paired paths: settings_load\n");
const settingsLoad = await measureSettingsLoad();
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
process.stderr.write("goal20 pi paired paths: oauth_pkce_device\n");
const oauthPkceDevice = await measureOauthPkceDevice();
process.stderr.write("goal20 pi paired paths: cli_extensions_install\n");
const cliExtensionsInstall = await measureCliExtensionsInstall();
process.stderr.write("goal20 pi paired paths: evals_harness\n");
const evalsHarness = await measureEvalsHarness();
process.stderr.write("goal20 pi paired paths: ai_crypto_model_data\n");
const aiCryptoModelData = await measureAiCryptoModelData();
process.stderr.write("goal20 pi paired paths: ai_crypto\n");
const aiCrypto = await measureAiCryptoHmac();
process.stderr.write("goal20 pi paired paths: cli_models_rest\n");
const cliModelsRest = await measureCliModelsRest();
process.stderr.write("goal20 pi paired paths: image_runtime\n");
const imageRuntime = await measureImageRuntime();
process.stderr.write("goal20 pi paired paths: cli_print_rpc\n");
const cliPrintRpc = await measureCliPrintRpc();
process.stderr.write("goal20 pi paired paths: tui_latex\n");
const tuiLatex = await measureTuiLatex();
process.stderr.write("goal20 pi paired paths: tui_mermaid\n");
const tuiMermaid = await measureTuiMermaid();
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
process.stderr.write("goal20 pi paired paths: cli_selectors\n");
const cliSelectors = await measureCliSelectorsSessionSearch();
process.stderr.write("goal20 pi paired paths: cli_sdk\n");
const cliSdk = await measureCliSdkVersionNewer();
process.stderr.write("goal20 pi paired paths: provider_registry_defs\n");
const providerRegistryDefs = await measureProviderRegistryDefs();
process.stderr.write("goal20 pi paired paths: skill_prompt_load\n");
const skillPromptLoad = await measureSkillPromptBuild();
process.stderr.write("goal20 pi paired paths: cli_bootstrap_sessions\n");
const cliBootstrap = await measureCliBootstrapCodingTools();
process.stderr.write("goal20 pi paired paths: ai_runtime_faux\n");
const aiRuntimeFaux = await measureAiRuntimeFauxBlocks();
process.stderr.write("goal20 pi paired paths: http_transport\n");
const httpTransport = await measureHttpTransportParseUrl();
process.stderr.write("goal20 pi paired paths: render_slicing\n");
const renderSlicing = await measureRenderSlicing();
process.stderr.write("goal20 pi paired paths: websocket_stream\n");
const websocketStream = await measureWebsocketStream();

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
			"settings_load.project_trust":
				"packages/coding-agent/src/core/project-trust.ts resolveProjectTrusted",
			"settings_load.config_value":
				"packages/coding-agent/src/core/resolve-config-value.ts resolveConfigValue",
			"settings_load.http_idle":
				"packages/coding-agent/src/core/http-dispatcher.ts formatHttpIdleTimeoutMs",
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
			"oauth_pkce_device.poll":
				"packages/ai/src/auth/oauth/device-code.ts pollOAuthDeviceCodeFlow",
			"oauth_pkce_device.auth_json":
				"packages/coding-agent/src/core/auth-storage.ts ReadOnlyAuthStorage.read",
			"oauth_pkce_device.copilot_url":
				"packages/ai/src/auth/oauth/github-copilot.ts githubCopilotOAuth.toAuth",
			"oauth_pkce_device.cloudflare_url":
				"packages/ai/src/providers/cloudflare-stream.ts resolveCloudflareModel",
			"oauth_pkce_device.radius_gateway":
				"packages/ai/src/providers/radius-config.ts normalizeRadiusGatewayUrl",
			"oauth_pkce_device.copilot_auth":
				"packages/ai/src/auth/oauth/github-copilot.ts githubCopilotOAuth.toAuth",
			"cli_extensions_install.llama_url":
				"packages/coding-agent/src/extensions/llama/client.ts normalizeLlamaServerUrl",
			"cli_extensions_install.hf_token":
				"packages/coding-agent/src/extensions/llama/huggingface.ts findHuggingFaceToken",
			"cli_extensions_install.llama_catalog":
				"packages/coding-agent/src/extensions/llama/provider.ts createLlamaProvider.setCatalog",
			"evals_harness.summarize":
				"packages/evals/src/vitest-evals/summary.ts summarizeHarnessComparisons",
			"evals_harness.group_key":
				"packages/evals/src/vitest-evals/harness-table.ts deriveEvalGroupKey",
			"evals_harness.artifact_persist":
				"packages/evals/src/vitest-evals/artifacts.ts persistEvalArtifactReferences",
			"evals_harness.format":
				"packages/evals/src/vitest-evals/summary.ts formatHarnessComparisonReport",
			"ai_crypto_model_data.manifest":
				"packages/ai/scripts/model-data.ts createModelDataManifest",
			"ai_crypto.hmac": "node:crypto createHmac sha256",
			"cli_models_rest.pattern_match":
				"packages/coding-agent/src/core/model-resolver.ts parseModelPattern",
			"cli_models_rest.auth_command":
				"packages/coding-agent/src/cli/auth-command.ts parseAuthCommand",
			"image_runtime.dimensions":
				"packages/tui/src/terminal-image.ts getImageDimensions",
			"image_runtime.mime_type":
				"packages/coding-agent/src/utils/mime.ts detectSupportedImageMimeType",
			"image_runtime.lookup":
				"packages/ai/src/image-models.ts getImageModel",
			"image_runtime.dimension_note":
				"packages/coding-agent/src/utils/image-resize.ts formatDimensionNote",
			"image_runtime.api_provider":
				"packages/ai/src/images-api-registry.ts getImagesApiProvider",
			"cli_print_rpc.jsonl_line":
				"packages/coding-agent/src/modes/rpc/jsonl.ts serializeJsonLine",
			"cli_print_rpc.jsonl_read":
				"packages/coding-agent/src/modes/rpc/jsonl.ts attachJsonlLineReader",
			"cli_print_rpc.clamp_thinking":
				"packages/ai/src/models.ts clampThinkingLevel",
			"cli_print_rpc.session_stats":
				"packages/coding-agent/src/core/agent-session.ts AgentSession.getSessionStats",
			"tui_latex.render": "packages/tui/src/latex.ts renderLatex",
			"tui_mermaid.render": "grok-mermaid render (dist/index.js)",
			"tui_mermaid.source_box": "grok-mermaid sourceBox (dist/source-box.js)",
			"tui_mermaid.transform":
				"packages/coding-agent/src/modes/interactive/components/mermaid.ts createMermaidMarkdownTransformer",
			"tui_editor_helpers.fuzzy_match": "packages/tui/src/fuzzy.ts fuzzyMatch",
			"tui_theme_overlay.osc11_bg":
				"packages/tui/src/terminal-colors.ts parseOsc11BackgroundColor",
			"ai_support.estimate_text":
				"packages/ai/src/utils/estimate.ts estimateTextTokens",
			"ai_support.context_overflow":
				"packages/ai/src/utils/overflow.ts isContextOverflow",
			"ai_support.grammar_delta":
				"packages/ai/src/api/constrained-sampling.ts appendGrammarToolInputJsonDelta",
			"ai_support.uuid_v7": "packages/ai/src/utils/uuid.ts uuidv7",
			"ai_support.auth_guidance":
				"packages/coding-agent/src/core/auth-guidance.ts formatNoModelsAvailableMessage",
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
			"ai_capabilities.deferred_tools":
				"packages/ai/src/utils/deferred-tools.ts splitDeferredTools",
			"ai_capabilities.event_stream":
				"packages/ai/src/utils/event-stream.ts EventStream",
			"ai_capabilities.http_proxy":
				"packages/ai/src/utils/node-http-proxy.ts resolveHttpProxyUrlForTarget",
			"ai_capabilities.session_resources":
				"packages/ai/src/session-resources.ts registerSessionResourceCleanup + cleanupSessionResources",
			"cli_support.strip_ansi": "packages/coding-agent/src/utils/ansi.ts stripAnsi",
			"cli_support.normalize_path":
				"packages/coding-agent/src/utils/paths.ts normalizePath",
			"cli_support.timings":
				"packages/coding-agent/src/core/timings.ts resetTimings + time + printTimings",
			"cli_support.event_bus":
				"packages/coding-agent/src/core/event-bus.ts createEventBus",
			"cli_support.attribution_headers":
				"packages/coding-agent/src/core/provider-attribution.ts mergeProviderAttributionHeaders",
			"cli_support.shell_config":
				"packages/coding-agent/src/utils/shell.ts getShellConfig",
			"cli_support.sanitize_output":
				"packages/coding-agent/src/utils/shell.ts sanitizeBinaryOutput",
			"cli_support.git_source":
				"packages/coding-agent/src/utils/git.ts parseGitUrl",
			"cli_support.user_agent":
				"packages/coding-agent/src/utils/pi-user-agent.ts getPiUserAgent",
			"cli_support.parse_changelog":
				"packages/coding-agent/src/utils/changelog.ts parseChangelog",
			"cli_support.experimental":
				"packages/coding-agent/src/core/experimental.ts areExperimentalFeaturesEnabled",
			"cli_interactive_controller.decode_entity":
				"packages/coding-agent/src/utils/html.ts decodeHtmlEntity",
			"cli_interactive_controller.wayland":
				"packages/coding-agent/src/utils/clipboard-image.ts isWaylandSession",
			"cli_interactive_controller.cwd_footer":
				"packages/coding-agent/src/modes/interactive/components/footer.ts formatCwdForFooter",
			"cli_interactive_controller.auth_type":
				"packages/coding-agent/src/modes/interactive/components/oauth-selector.ts formatAuthSelectorProviderType",
			"cli_interactive_controller.parse_auto_theme":
				"packages/coding-agent/src/modes/interactive/theme/theme.ts parseAutoThemeSetting",
			"cli_interactive_controller.resolve_theme":
				"packages/coding-agent/src/modes/interactive/theme/theme.ts resolveThemeSetting",
			"cli_selectors.session_search":
				"packages/coding-agent/src/modes/interactive/components/session-selector-search.ts filterAndSortSessions",
			"cli_selectors.session_format_age":
				"packages/coding-agent/src/modes/interactive/components/session-selector.ts formatSessionDate",
			"cli_selectors.session_record_label":
				"packages/coding-agent/src/modes/interactive/components/session-selector.ts session list label",
			"cli_selectors.session_shorten_path":
				"packages/coding-agent/src/modes/interactive/components/session-selector.ts shortenPath",
			"cli_selectors.session_quoted_search":
				"packages/coding-agent/src/modes/interactive/components/session-selector-search.ts phrase indexOf",
			"cli_selectors.session_thread_records":
				"packages/coding-agent/src/modes/interactive/components/session-selector.ts buildSessionTree flattenSessionTree",
			"cli_selectors.session_binding_label":
				"packages/coding-agent/src/core/keybindings.ts KeybindingsManager.getKeys first-or-name",
			"cli_selectors.session_same_path":
				"packages/coding-agent/src/utils/paths.ts canonicalizePath equality",
			"cli_selectors.session_quoted_p":
				"packages/coding-agent/src/modes/interactive/components/session-selector-search.ts quoted phrase predicate",
			"cli_selectors.session_named_p":
				"packages/coding-agent/src/modes/interactive/components/session-selector-search.ts hasSessionName",
			"cli_selectors.settings_thinking_description":
				"packages/coding-agent/src/modes/interactive/components/settings-selector.ts THINKING_DESCRIPTIONS",
			"cli_selectors.settings_display_value":
				"packages/coding-agent/src/modes/interactive/components/settings-selector.ts currentValue boolean formatting",
			"cli_selectors.settings_automatic_theme_setting":
				"packages/coding-agent/src/modes/interactive/components/settings-selector.ts ThemeSubmenu getAutomaticThemeSetting",
			"cli_selectors.settings_active_automatic_theme":
				"packages/coding-agent/src/modes/interactive/components/settings-selector.ts ThemeSubmenu getActiveAutomaticTheme",
			"cli_selectors.settings_cycle":
				"packages/tui/src/components/settings-list.ts SettingsList cycle values",
			"cli_selectors.settings_apply_filter":
				"packages/tui/src/components/settings-list.ts SettingsList applyFilter",
			"cli_selectors.tree_entry_filtered":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts filter mode predicate",
			"cli_selectors.tree_query_matches":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts search token predicate",
			"cli_selectors.tree_entry_search_text":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts getSearchableText field join",
			"cli_selectors.tree_settings_entry_p":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts isSettingsEntry predicate",
			"cli_selectors.tree_normalize_display_text":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts getEntryDisplayText normalize",
			"cli_selectors.tree_status_labels":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts getStatusLabels",
			"cli_selectors.tree_shorten_path":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts formatToolCall shortenPath",
			"cli_selectors.tree_foldable_p":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts isFoldable",
			"cli_selectors.tree_tool_argument":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts formatToolCall args.path || args.file_path",
			"cli_selectors.tree_cycle_filter":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts filter cycle keybindings modes array index math",
			"cli_selectors.tree_format_label_timestamp":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts formatLabelTimestamp",
			"cli_selectors.tree_iso_timestamp":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts updateNodeLabel labelTimestamp toISOString; pair standalone local ISO timestamp formatter without Z/ms",
			"cli_selectors.tree_format_tool_call":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts formatToolCall",
			"cli_selectors.tree_entry_display_text":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts getEntryDisplayText",
			"cli_selectors.tree_prefix":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts render prefix char loop",
			"cli_selectors.tree_visual_nodes":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts recalculateVisualStructure DFS",
			"cli_selectors.tree_horizontal_viewport":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts renderHorizontalViewport",
			"cli_selectors.tree_help_keys":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts formatHelpKeys",
			"cli_selectors.tree_help_key":
				"packages/coding-agent/src/core/keybindings.ts KeybindingsManager.getKeys first-or-fallback",
			"cli_selectors.tree_app_key_p":
				"packages/tui/src/keybindings.ts KeybindingsManager.matches + CSI modified-arrow canonical compare (selector-keybinding-matches-p parity)",
			"cli_selectors.tree_help_lines":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts TreeHelp.render",
			"cli_selectors.tree_active_path":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts buildActivePath",
			"cli_selectors.tree_nearest_visible_id":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts findNearestVisibleIndex id walk",
			"cli_selectors.tree_prioritize_active":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts flattenTree active-branch ordering",
			"cli_selectors.tree_entry_map":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts entry id map",
			"cli_selectors.tree_order_entries":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts flattenTree entry ordering",
			"cli_selectors.tree_rebuild_visible_maps":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts recalculateVisualStructure visible parent/children maps",
			"cli_selectors.tree_apply_filter":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts applyFilter",
			"cli_selectors.tree_render_lines":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts TreeList.render",
			"cli_selectors.tree_move":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts TreeList selection index wrap",
			"cli_selectors.tree_fold_or_up":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts foldOrUp handleInput",
			"cli_selectors.tree_unfold_or_down":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts unfoldOrDown handleInput",
			"cli_selectors.tree_branch_segment_id":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts findBranchSegmentStart",
			"cli_selectors.tree_set_query":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts TreeList searchQuery + applyFilter",
			"cli_selectors.tree_set_filter":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts TreeList filterMode + applyFilter",
			"cli_selectors.tree_copy_selected":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts copySelected",
			"cli_selectors.tree_toggle_label_timestamps":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts showLabelTimestamps toggle",
			"cli_selectors.tree_start_label_edit":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts showLabelInput",
			"cli_selectors.tree_confirm_label":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts LabelInput onSubmit",
			"cli_selectors.tree_cancel_label":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts LabelInput onCancel",
			"cli_selectors.tree_handle_raw_input":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts TreeList.handleInput",
			"cli_selectors.tree_handle_event":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts TreeList.handleInput (structured events)",
			"cli_selectors.tree_handle_label_event":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts LabelInput.handleInput",
			"cli_selectors.tree_selected_entry":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts TreeList.getSelectedNode",
			"cli_selectors.tree_selected_id":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts TreeList.filteredNodes selected id",
			"cli_selectors.tree_select_id":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts TreeList filteredNodes index by id",
			"cli_selectors.tree_visible_ids":
				"packages/coding-agent/src/modes/interactive/components/tree-selector.ts TreeList.filteredNodes ids",
			"cli_selectors.project_trust_options":
				"packages/coding-agent/src/core/trust-manager.ts getProjectTrustOptions",
			"cli_selectors.trust_selector_selection":
				"packages/coding-agent/src/core/trust-manager.ts getProjectTrustOptions index selection",
			"cli_selectors.trust_decision_description":
				"packages/coding-agent/src/modes/interactive/components/trust-selector.ts formatDecision",
			"cli_selectors.trust_selector_move":
				"packages/tui/src/components/select-list.ts wrap selection index on getProjectTrustOptions count",
			"cli_selectors.trust_selector_handle_event":
				"packages/coding-agent/src/modes/interactive/components/trust-selector.ts trust-selector-handle-event dispatch",
			"cli_selectors.trust_selector_handle_raw_input":
				"packages/coding-agent/src/modes/interactive/components/trust-selector.ts trust-selector-handle-raw-input dispatch",
			"cli_selectors.trust_selector_ui_state":
				"packages/coding-agent/src/modes/interactive/components/trust-selector.ts TrustSelectorComponent UI state",
			"cli_selectors.key_text":
				"packages/coding-agent/src/modes/interactive/components/keybinding-hints.ts formatKeyText",
			"cli_selectors.fuzzy_filter": "packages/tui/src/fuzzy.ts fuzzyFilter",
			"cli_selectors.delete_query":
				"packages/tui/src/components/input.ts Input.handleInput backspace grapheme delete",
			"cli_selectors.visible_slice":
				"packages/coding-agent/src/modes/interactive/components/oauth-selector.ts viewport slice (same formula in session/model/tree selectors)",
			"cli_selectors.move_index":
				"packages/tui/src/components/select-list.ts wrap selection index (up/down)",
			"cli_selectors.align_left_right":
				"packages/coding-agent/src/modes/interactive/components/session-selector.ts header left/right align",
			"cli_selectors.fit_line":
				"packages/tui/src/utils.ts truncateToWidth + visibleWidth pad (selector-fit-line sites)",
			"cli_selectors.border_line":
				"packages/coding-agent/src/modes/interactive/components/dynamic-border.ts DynamicBorder.render",
			"cli_selectors.selected_line":
				"packages/coding-agent/src/modes/interactive/components/session-selector.ts theme.bg selectedBg + truncateToWidth pad",
			"cli_selectors.muted_line":
				"packages/coding-agent/src/modes/interactive/components/session-selector.ts theme.fg muted + truncateToWidth",
			"cli_selectors.dim_line":
				"packages/coding-agent/src/modes/interactive/components/session-selector.ts theme.fg dim + truncateToWidth",
			"cli_selectors.modified_cursor_key":
				"packages/tui/src/keys.ts parseKey (CSI modified arrows)",
			"cli_selectors.title_line":
				"packages/coding-agent/src/modes/interactive/components/oauth-selector.ts theme.fg accent theme.bold TruncatedText margins",
			"cli_selectors.overlay_title_line":
				"packages/coding-agent/src/modes/interactive/components/oauth-selector.ts theme.fg accent theme.bold TruncatedText margins",
			"cli_selectors.input_line":
				"packages/tui/src/components/input.ts Input.render",
			"cli_selectors.keybinding_text":
				"packages/tui/src/keybindings.ts KeybindingsManager.getKeys join",
			"cli_selectors.keybinding_hint":
				"packages/coding-agent/src/modes/interactive/components/keybinding-hints.ts rawKeyHint",
			"websocket_stream.stream_roundtrip":
				"packages/ai/src/api/openai-codex-responses.ts stream (websocket)",
			"cli_sdk.version_newer":
				"packages/coding-agent/src/utils/version-check.ts isNewerPackageVersion",
			"cli_sdk.cache_miss":
				"packages/coding-agent/src/core/cache-stats.ts detectCacheMiss",
			"cli_sdk.cache_waste":
				"packages/coding-agent/src/core/cache-stats.ts computeCacheWaste",
			"cli_sdk.thinking_level":
				"packages/coding-agent/src/cli/args.ts isValidThinkingLevel",
			"cli_sdk.session_list":
				"packages/coding-agent/src/core/session-manager.ts SessionManager.list",
			"cli_sdk.agent_session":
				"packages/coding-agent/src/core/sdk.ts createAgentSession",
			"cli_sdk.session_services":
				"packages/coding-agent/src/core/agent-session-services.ts createAgentSessionServices",
			"cli_sdk.model_runtime":
				"packages/coding-agent/src/core/model-runtime.ts ModelRuntime.getProviders + getModel",
			"provider_registry_defs.lookup":
				"packages/ai/src/providers/all.ts getBuiltinProviders",
			"skill_prompt_load.build_prompt":
				"packages/coding-agent/src/core/system-prompt.ts buildSystemPrompt",
			"cli_bootstrap_sessions.coding_tools":
				"packages/coding-agent/src/core/tools/index.ts createCodingTools",
			"ai_runtime_faux.blocks":
				"packages/ai/src/providers/faux.ts fauxText + fauxThinking",
			"http_transport.parse_url":
				"WHATWG URL (https://example.com/foo + http://localhost:8080/bar)",
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
			"agent_tool_loop.tool_path":
				"packages/coding-agent/src/core/tools/path-utils.ts resolveToCwd",
			"agent_tool_loop.line_ending":
				"packages/coding-agent/src/core/tools/edit-diff.ts detectLineEnding",
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
		settings_load: settingsLoad,
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
		oauth_pkce_device: oauthPkceDevice,
		cli_extensions_install: cliExtensionsInstall,
		evals_harness: evalsHarness,
		ai_crypto_model_data: aiCryptoModelData,
		ai_crypto: aiCrypto,
		cli_models_rest: cliModelsRest,
		image_runtime: imageRuntime,
		cli_print_rpc: cliPrintRpc,
		tui_latex: tuiLatex,
		tui_mermaid: tuiMermaid,
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
		cli_selectors: cliSelectors,
		cli_sdk: cliSdk,
		provider_registry_defs: providerRegistryDefs,
		skill_prompt_load: skillPromptLoad,
		cli_bootstrap_sessions: cliBootstrap,
		ai_runtime_faux: aiRuntimeFaux,
		http_transport: httpTransport,
		render_slicing: renderSlicing,
		websocket_stream: websocketStream,
	},
};

rmSync(scratch, { recursive: true, force: true });

const text = `${JSON.stringify(result, null, 2)}\n`;
if (options.output === "-") process.stdout.write(text);
else writeFileSync(options.output, text, "utf8");
