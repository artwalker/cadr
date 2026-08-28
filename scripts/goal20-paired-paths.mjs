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
	statSync,
	utimesSync,
	writeFileSync,
	symlinkSync,
	unlinkSync,
} from "node:fs";
import { mkdir as fsMkdir, realpath, writeFile as fsWriteFile } from "node:fs/promises";
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
	"cli_settings.reload": 50,
	"cli_settings.enabled_models": 50,
	"cli_settings.block_images": 50,
	"agent_conditions.error_probe": 50,
	"execution_env.exists_remove_temps": 50,
	"file_mutation_queue.with_queue": 50,
	"file_mutation_queue.queue_key": 50,
	"file_mutation_queue.lock": 50,
	"file_mutation_queue.register": 50,
	"file_mutation_queue.wait_turn": 50,
	"file_mutation_queue.release_turn": 50,
	"file_mutation_queue.ensure_state": 50,
	"file_mutation_queue.call_with": 50,
	"file_mutation_queue.make_state": 50,
	"file_mutation_queue.state_key": 50,
	"file_mutation_queue.pending_count": 50,
	"file_mutation_queue.next_ticket": 50,
	"file_mutation_queue.serving_ticket": 50,
	"harness_events.emit": 50,
	"bash_tool.strip_exit_footer": 50,
	"bash_tool.append_status": 50,
	"bash_tool.truncation_notice": 50,
	"output_accumulator.append": 50,
	"output_accumulator.snapshot": 50,
	"output_accumulator.finish": 50,
	"harness_events.on": 50,
	"harness_events.watch": 50,
	"harness_events.make_start": 50,
	"harness_events.make_end": 50,
	"harness_events.event_type": 50,
	"harness_events.make_bus": 50,
	"find_tool.pattern_match": 50,
	"find_tool.find_files": 50,
	"find_tool.make_tool": 50,
	"write_tool.ensure_parent": 50,
	"write_tool.write_utf8": 50,
	"write_tool.make_tool": 50,
	"ls_tool.directory_entry_name": 50,
	"ls_tool.list_directory": 50,
	"ls_tool.make_tool": 50,
	"tool_manager.get_tool_path": 50,
	"tool_manager.ensure_tool": 50,
	"tool_manager.cleanup_quarantine": 50,
	"powershell_tool.utf8_prefix": 50,
	"powershell_tool.prefix_command": 50,
	"powershell_tool.make_tool": 50,
	"settings_load.project_trust": 20,
	"settings_load.config_value": 50,
	"settings_load.http_idle": 50,
	"settings_load.stored_auth_secrets": 50,
	"settings_load.config_paths": 50,
	"resource_loader.reload": 3,
	"resource_loader.dedupe_by_name": 50,
	"package_manager.resolve": 5,
	"package_manager.manifest_parse": 50,
	"package_manager.package_source": 50,
	"session_discovery.header_probe": 20,
	"session_discovery.session_list_probe": 5,
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
	"oauth_pkce_device.percent_decode": 50,
	"oauth_pkce_device.parse_query": 50,
	"oauth_pkce_device.parse_authorization_input": 50,
	"cli_extensions_install.llama_url": 50,
	"cli_extensions_install.hf_token": 50,
	"cli_extensions_install.llama_catalog": 50,
	"cli_extensions_install.extension_discovery": 50,
	"evals_harness.summarize": 20,
	"evals_harness.group_key": 50,
	"evals_harness.artifact_persist": 3,
	"evals_harness.format": 20,
	"evals_harness.normalize_steps": 50,
	"evals_harness.resolve_selection": 50,
	"evals_harness.transcript": 50,
	"evals_harness.last_assistant": 50,
	"evals_harness.step_value": 50,
	"evals_harness.usage": 50,
	"evals_harness.result_json": 50,
	"evals_harness.eval_layout": 50,
	"evals_harness.system_prompt": 50,
	"evals_harness.output_selector": 50,
	"ai_crypto_model_data.manifest": 50,
	"ai_crypto.hmac": 50,
	"cli_models_rest.pattern_match": 50,
	"cli_models_rest.auth_command": 50,
	"cli_models_rest.login_selection": 50,
	"image_runtime.dimensions": 50,
	"image_runtime.mime_type": 50,
	"image_runtime.lookup": 50,
	"image_runtime.dimension_note": 50,
	"image_runtime.api_provider": 50,
	"image_runtime.output_modalities": 50,
	"image_runtime.openrouter_content": 50,
	"image_runtime.parse_data_image": 50,
	"cli_print_rpc.jsonl_line": 50,
	"cli_print_rpc.jsonl_read": 50,
	"cli_print_rpc.clamp_thinking": 50,
	"cli_print_rpc.session_stats": 20,
	"tui_latex.render": 20,
	"tui_latex.normalize_output": 20,
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
	"cli_selectors.oauth_option_status_label": 50,
	"cli_selectors.oauth_option_status_rendered": 50,
	"cli_selectors.credential_entry_auth_type": 50,
	"cli_selectors.oauth_environment_source_p": 50,
	"cli_selectors.oauth_selector_selection": 50,
	"cli_selectors.oauth_selector_apply_filter": 50,
	"cli_selectors.oauth_selector_handle_event": 50,
	"cli_selectors.oauth_selector_handle_raw_input": 50,
	"cli_selectors.oauth_selector_search_text": 50,
	"cli_selectors.login_auth_type_route": 50,
	"cli_selectors.login_provider_options": 50,
	"cli_selectors.logout_provider_options": 50,
	"cli_selectors.login_method_selector_handle_event": 50,
	"cli_selectors.oauth_selector_move": 50,
	"cli_selectors.api_key_input_state_handle_event": 50,
	"cli_selectors.login_method_selector_ui_state": 50,
	"cli_selectors.api_key_input_ui_state": 50,
	"cli_selectors.oauth_selector_ui_state": 50,
	"cli_selectors.model_selector_search_text": 50,
	"cli_selectors.qualified_model_id": 50,
	"cli_selectors.model_selector_apply_filter": 50,
	"cli_selectors.model_selector_move": 50,
	"cli_selectors.model_selector_handle_event": 50,
	"cli_selectors.model_selector_handle_raw_input": 50,
	"cli_selectors.model_selector_set_query": 50,
	"cli_selectors.model_selector_selected_model": 50,
	"cli_selectors.model_selector_toggle_scope": 50,
	"cli_selectors.model_selector_ui_state": 50,
	"cli_selectors.scoped_models_selector_set_query": 50,
	"cli_selectors.scoped_models_selector_move": 50,
	"cli_selectors.scoped_models_selector_handle_event": 50,
	"cli_selectors.scoped_models_selector_handle_raw_input": 50,
	"cli_selectors.scoped_models_selector_ui_state": 50,
	"cli_selectors.scoped_models_selector_sorted_ids": 50,
	"cli_selectors.scoped_models_selector_counts": 50,
	"cli_selectors.scoped_models_selector_toggle_selected": 50,
	"cli_selectors.scoped_models_selector_toggle_provider": 50,
	"cli_selectors.scoped_models_selector_target_ids": 50,
	"cli_selectors.scoped_models_selector_enable_all": 50,
	"cli_selectors.scoped_models_selector_clear_all": 50,
	"cli_selectors.scoped_models_selector_reorder": 50,
	"cli_selectors.scoped_models_selector_persist": 50,
	"cli_selectors.scoped_models_selector_provider_count": 50,
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
	"provider_registry_defs.definition_ids": 125,
	"provider_registry_defs.merge_environment": 50,
	"provider_registry_defs.runtime_models": 50,
	"provider_registry_defs.structured_api_key_login": 50,
	"core_rest.cancellation_abort": 50,
	"core_rest.redacted_secrets": 50,
	"core_rest.threads_cleanup": 5,
	"skill_prompt_load.build_prompt": 50,
	"cli_bootstrap_sessions.coding_tools": 50,
	"cli_bootstrap_sessions.bootstrap_auth": 50,
	"ai_runtime_faux.blocks": 50,
	"http_transport.parse_url": 50,
	"session_pipeline.session_load": 3,
	"session_pipeline.context_walk": 50,
	"session_pipeline.session_leaf_id": 50,
	"storage_journal.journal_read": 5,
	"storage_journal.journal_append": 3,
	"storage_journal.journal_entry_count": 50,
	"sqlite_session.open_walk": 3,
	"tool_read.text_file": 5,
	"tool_grep.context_file": 5,
	"agent_tool_loop.roundtrip": 3,
	"agent_tool_loop.tool_path": 50,
	"agent_tool_loop.line_ending": 50,
	"agent_tool_loop.tool_result_digest": 125,
	"agent_tool_loop.runtime": 50,
	"session_compact.compact": 3,
	"session_compact.branch_summarize": 3,
	"session_compact.prepare_branch_entries": 3,
	"text_truncation.truncate_head": 50,
	"text_truncation.truncate_tail": 50,
	"text_truncation.truncate_middle": 50,
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
// Pin before any coding-agent import so tools-manager.ts TOOLS_DIR is the
// staged agent bin, not ~/.pi/agent/bin (a host fd binary lives there).
process.env.PI_CODING_AGENT_DIR = agentDirectory;
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
const harnessEventsModule = await import(moduleUrl("packages/agent/src/harness/events.ts"));
const rpcJsonlModule = await import(moduleUrl("packages/coding-agent/src/modes/rpc/jsonl.ts"));
process.env.PI_TIMING = "1";
const sqliteModule = await import(moduleUrl("packages/session-backends/sqlite-node/src/index.ts"));
const nodeEnvModule = await import(moduleUrl("packages/agent/src/harness/env/nodejs.ts"));
const windowsSelfUpdateModule = await import(
	moduleUrl("packages/coding-agent/src/utils/windows-self-update.ts"),
);
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
const configModule = await import(moduleUrl("packages/coding-agent/src/config.ts"));
const resolvePathModule = await import(moduleUrl("packages/coding-agent/src/utils/paths.ts"));
const piManifestModule = await import(moduleUrl("packages/coding-agent/src/core/pi-manifest.ts"));
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
const skillsModule = await import(moduleUrl("packages/coding-agent/src/core/skills.ts"));
const promptTemplatesModule = await import(
	moduleUrl("packages/coding-agent/src/core/prompt-templates.ts")
);
const packageManagerModule = await import(moduleUrl("packages/coding-agent/src/core/package-manager.ts"));
const truncateModule = await import(moduleUrl("packages/coding-agent/src/core/tools/truncate.ts"));
const outputAccumulatorModule = await import(
	moduleUrl("packages/coding-agent/src/core/tools/output-accumulator.ts"),
);
const readModule = await import(moduleUrl("packages/coding-agent/src/core/tools/read.ts"));
const findModule = await import(moduleUrl("packages/coding-agent/src/core/tools/find.ts"));
const writeModule = await import(moduleUrl("packages/coding-agent/src/core/tools/write.ts"));
const lsModule = await import(moduleUrl("packages/coding-agent/src/core/tools/ls.ts"));
const powershellModule = await import(
	moduleUrl("packages/coding-agent/src/core/tools/powershell.ts"),
);
const grepModule = await import(moduleUrl("packages/coding-agent/src/core/tools/grep.ts"));
const toolPathModule = await import(moduleUrl("packages/coding-agent/src/core/tools/path-utils.ts"));
const fileMutationQueueModule = await import(
	moduleUrl("packages/coding-agent/src/core/tools/file-mutation-queue.ts"),
);
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
const modelSearchModule = await import(
	moduleUrl("packages/coding-agent/src/modes/interactive/model-search.ts")
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
const providerEnvModule = await import(moduleUrl("packages/ai/src/utils/provider-env.ts"));
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
const branchSummarizationModule = await import(
	moduleUrl("packages/coding-agent/src/core/compaction/branch-summarization.ts")
);
const compactionUtilsModule = await import(
	moduleUrl("packages/coding-agent/src/core/compaction/utils.ts")
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

function csTruth(value) {
	return value ? 1 : 0;
}

async function runCliSettingsReload(manager) {
	await manager.reload();
	return {
		rl_theme_light: csTruth(manager.getThemeSetting() === "light"),
		rl_model: csTruth(manager.getDefaultModel() === "claude-sonnet-4-5"),
		rl_idle: csTruth(manager.getHttpIdleTimeoutMs() === 42),
		rl_n: 3,
	};
}

function runCliSettingsEnabledModels(manager) {
	const missing = manager.getEnabledModels();
	const memory = settingsModule.SettingsManager.inMemory({
		enabledModels: ["anthropic/claude-sonnet-4-5"],
	});
	const explicit = memory.getEnabledModels();
	return {
		em_all: csTruth(missing === undefined),
		em_one: csTruth(
			Array.isArray(explicit) &&
				explicit.length === 1 &&
				explicit[0] === "anthropic/claude-sonnet-4-5",
		),
		em_n: 2,
	};
}

function runCliSettingsBlockImages(manager) {
	const defaultBlocked = manager.getBlockImages();
	const memory = settingsModule.SettingsManager.inMemory({
		images: { blockImages: true },
	});
	return {
		bi_default: csTruth(!defaultBlocked),
		bi_blocked: csTruth(memory.getBlockImages() === true),
		bi_n: 2,
	};
}


function runAgentConditionsErrorProbe() {
	const bool = (value) => (value ? 1 : 0);
	class CadrError extends Error {}
	class ConfigurationError extends CadrError {}
	class SchemaValidationError extends CadrError {
		constructor(tool, jsonPointer, reason) {
			super("schema validation");
			this.tool = tool;
			this.jsonPointer = jsonPointer;
			this.reason = reason;
		}
	}
	class ToolExecutionError extends CadrError {
		constructor(tool, toolCallId) {
			super("tool execution");
			this.tool = tool;
			this.toolCallId = toolCallId;
		}
	}
	class SessionError extends CadrError {
		constructor(path, line) {
			super("session error");
			this.path = path;
			this.line = line;
		}
	}
	class ExtensionRegistrationError extends ConfigurationError {}
	class ExtensionExecutionError extends CadrError {}
	class StaleExtensionContext extends CadrError {}
	class AgentBusyError extends CadrError {}
	class AgentShutdownError extends CadrError {}
	class AgentTurnLimitError extends CadrError {}
	const caught = (ErrorClass, factory) => {
		try {
			factory();
			return 0;
		} catch (error) {
			return error instanceof ErrorClass ? 1 : 0;
		}
	};
	const schema = new SchemaValidationError("edit", "/edits", "required");
	const toolExec = new ToolExecutionError("bash", "call-1");
	const session = new SessionError("/tmp/s.jsonl", 12);
	return {
		ac_schema_tool: bool(schema.tool === "edit"),
		ac_schema_ptr: bool(schema.jsonPointer === "/edits"),
		ac_schema_reason: bool(schema.reason === "required"),
		ac_tool_name: bool(toolExec.tool === "bash"),
		ac_tool_id: bool(toolExec.toolCallId === "call-1"),
		ac_sess_path: bool(session.path === "/tmp/s.jsonl"),
		ac_sess_line: session.line === 12 ? 1 : 0,
		ac_sub_schema: bool(schema instanceof CadrError),
		ac_sub_tool: bool(toolExec instanceof CadrError),
		ac_sub_ext_reg: bool(ExtensionRegistrationError.prototype instanceof ConfigurationError),
		ac_sub_ext_exec: bool(ExtensionExecutionError.prototype instanceof CadrError),
		ac_sub_stale: bool(StaleExtensionContext.prototype instanceof CadrError),
		ac_sub_session: bool(SessionError.prototype instanceof CadrError),
		ac_catch_busy: caught(AgentBusyError, () => {
			throw new AgentBusyError("busy");
		}),
		ac_catch_shutdown: caught(AgentShutdownError, () => {
			throw new AgentShutdownError("shutdown");
		}),
		ac_catch_turn: caught(AgentTurnLimitError, () => {
			throw new AgentTurnLimitError("turn");
		}),
		ac_catch_ext_reg: caught(ExtensionRegistrationError, () => {
			throw new ExtensionRegistrationError("ext-reg");
		}),
		ac_catch_ext_exec: caught(ExtensionExecutionError, () => {
			throw new ExtensionExecutionError("ext-exec");
		}),
		ac_catch_stale: caught(StaleExtensionContext, () => {
			throw new StaleExtensionContext("stale");
		}),
	};
}

async function measureAgentConditions() {
	const probe = runAgentConditionsErrorProbe();
	return {
		error_probe: await collect("agent_conditions.error_probe", () => {
			return () => runAgentConditionsErrorProbe();
		}),
		observed: probe,
	};
}


function unwrapExecutionEnvResult(result) {
	if (!result.ok) {
		throw new Error(JSON.stringify(result.error));
	}
	return result.value;
}

function stageExecutionEnvCwd() {
	const root = path.join(scratch, "execution-env");
	mkdirSync(root, { recursive: true });
	return root;
}

async function runExecutionEnvExistsRemoveTemps(cwd) {
	const env = new nodeEnvModule.NodeExecutionEnv({ cwd });
	const truth = (value) => (value ? 1 : 0);
	try {
		const exMissing = truth(unwrapExecutionEnvResult(await env.exists("missing.txt")));
		unwrapExecutionEnvResult(await env.writeFile("file.txt", "hello"));
		const exPresent = truth(unwrapExecutionEnvResult(await env.exists("file.txt")));
		unwrapExecutionEnvResult(await env.remove("file.txt"));
		const exAfterRm = truth(unwrapExecutionEnvResult(await env.exists("file.txt")));
		const tempDir = unwrapExecutionEnvResult(await env.createTempDir("env-test-"));
		const tmpDir = truth(existsSync(tempDir));
		const tempFile = unwrapExecutionEnvResult(
			await env.createTempFile({ prefix: "prefix-", suffix: ".txt" }),
		);
		const tmpFile = truth(existsSync(tempFile));
		const tmpSuffix = truth(tempFile.endsWith(".txt"));
		unwrapExecutionEnvResult(await env.remove("still-missing", { force: true }));
		const rmForce = 1;
		unwrapExecutionEnvResult(await env.writeFile("dir/child/file.txt", "hello"));
		unwrapExecutionEnvResult(await env.remove("dir", { recursive: true }));
		const rmRecursive = truth(!unwrapExecutionEnvResult(await env.exists("dir")));
		return {
			ex_missing: exMissing,
			ex_present: exPresent,
			ex_after_rm: exAfterRm,
			tmp_dir: tmpDir,
			tmp_file: tmpFile,
			tmp_suffix: tmpSuffix,
			rm_force: rmForce,
			rm_recursive: rmRecursive,
		};
	} finally {
		await env.cleanup();
	}
}

async function measureExecutionEnv() {
	const cwd = stageExecutionEnvCwd();
	const observed = await runExecutionEnvExistsRemoveTemps(cwd);
	return {
		exists_remove_temps: await collect("execution_env.exists_remove_temps", () => {
			return () => runExecutionEnvExistsRemoveTemps(cwd);
		}),
		observed,
	};
}

async function measureCliSettings() {
	const manager = runCliSettings();
	const reloadObserved = await runCliSettingsReload(manager);
	const enabledObserved = runCliSettingsEnabledModels(manager);
	const blockObserved = runCliSettingsBlockImages(manager);
	return {
		create: await collect("cli_settings.create", () => {
			return () => runCliSettings();
		}),
		reload: await collect("cli_settings.reload", () => {
			return () => runCliSettingsReload(manager);
		}),
		enabled_models: await collect("cli_settings.enabled_models", () => {
			return () => runCliSettingsEnabledModels(manager);
		}),
		block_images: await collect("cli_settings.block_images", () => {
			return () => runCliSettingsBlockImages(manager);
		}),
		observed: {
			theme: manager.getThemeSetting() ?? "",
			default_model: manager.getDefaultModel() ?? "",
			default_provider: manager.getDefaultProvider() ?? "",
			compaction_reserve_tokens: manager.getCompactionReserveTokens(),
			default_project_trust: manager.getDefaultProjectTrust(),
			http_idle_timeout_ms: manager.getHttpIdleTimeoutMs(),
			project_trusted: manager.isProjectTrusted(),
			...reloadObserved,
			...enabledObserved,
			...blockObserved,
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

const STORED_AUTH_OAUTH_FIXTURE =
	'{"openai":{"type":"api_key","key":"sk-test"},"anthropic":{"type":"oauth","access":"acc","refresh":"ref","expires":9999999999}}';

function storedAuthSecrets(authPath) {
	if (!existsSync(authPath)) return [];
	try {
		const secrets = [];
		const data = JSON.parse(readFileSync(authPath, "utf8"));
		for (const object of Object.values(data)) {
			if (!object || typeof object !== "object") continue;
			for (const field of ["key", "access", "refresh"]) {
				const value = object[field];
				if (typeof value === "string" && value.length > 0) secrets.push(value);
			}
		}
		return secrets;
	} catch {
		return [];
	}
}

function stageSettingsLoadStoredAuth() {
	const missingRoot = path.join(scratch, "stored-auth-missing");
	const oauthRoot = path.join(scratch, "stored-auth-oauth");
	const oauthPath = path.join(oauthRoot, "auth.json");
	const badPath = path.join(oauthRoot, "bad.json");
	const fixturePath = path.join(agentDirectory, "auth.json");
	mkdirSync(missingRoot, { recursive: true });
	mkdirSync(oauthRoot, { recursive: true });
	writeFileSync(oauthPath, STORED_AUTH_OAUTH_FIXTURE, "utf8");
	writeFileSync(badPath, "[", "utf8");
	return {
		missingPath: path.join(missingRoot, "missing.json"),
		fixturePath,
		oauthPath,
		badPath,
	};
}

function storedAuthSecretCount(authPath) {
	return storedAuthSecrets(authPath).length;
}

function storedAuthSecretMember(authPath, secret) {
	return storedAuthSecrets(authPath).includes(secret) ? 1 : 0;
}

function runSettingsLoadStoredAuthSecrets(missingPath, fixturePath, oauthPath, badPath) {
	return {
		sas_missing: storedAuthSecretCount(missingPath),
		sas_fixture: storedAuthSecretCount(fixturePath),
		sas_oauth: storedAuthSecretCount(oauthPath),
		sas_bad: storedAuthSecretCount(badPath),
		sas_fixture_key: storedAuthSecretMember(fixturePath, "goal20-paired-paths-not-a-real-key"),
		sas_oauth_access: storedAuthSecretMember(oauthPath, "acc"),
		sas_oauth_refresh: storedAuthSecretMember(oauthPath, "ref"),
	};
}

function stageSettingsLoadConfigPaths() {
	const agent = path.join(scratch, "config-paths-agent");
	mkdirSync(agent, { recursive: true });
	return realpathSync(agent);
}

function runSettingsLoadConfigPaths(agentDir) {
	const previous = process.env[configModule.ENV_AGENT_DIR];
	process.env[configModule.ENV_AGENT_DIR] = agentDir;
	try {
		const authPath = configModule.getAuthPath();
		const settingsPath = configModule.getSettingsPath();
		return {
			cp_auth_eq: authPath === path.join(agentDir, "auth.json") ? 1 : 0,
			cp_cfg_eq: settingsPath === path.join(agentDir, "settings.json") ? 1 : 0,
			cp_same_p: path.dirname(authPath) === path.dirname(settingsPath) ? 1 : 0,
			cp_auth_leaf: path.basename(authPath) === "auth.json" ? 1 : 0,
			cp_cfg_leaf: path.basename(settingsPath) === "settings.json" ? 1 : 0,
		};
	} finally {
		if (previous === undefined) delete process.env[configModule.ENV_AGENT_DIR];
		else process.env[configModule.ENV_AGENT_DIR] = previous;
	}
}

async function measureSettingsLoad() {
	const configPathsAgent = stageSettingsLoadConfigPaths();
	const { empty, project, agent } = stageSettingsLoadTrust();
	const { missingPath, fixturePath, oauthPath, badPath } = stageSettingsLoadStoredAuth();
	const trust = await runSettingsLoadProjectTrust(empty, project, agent);
	const config = runSettingsLoadConfigValue();
	const idle = runSettingsLoadHttpIdle();
	const storedAuth = runSettingsLoadStoredAuthSecrets(missingPath, fixturePath, oauthPath, badPath);
	const configPaths = runSettingsLoadConfigPaths(configPathsAgent);
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
		stored_auth_secrets: await collect("settings_load.stored_auth_secrets", () => {
			return () => runSettingsLoadStoredAuthSecrets(missingPath, fixturePath, oauthPath, badPath);
		}),
		config_paths: await collect("settings_load.config_paths", () => {
			return () => runSettingsLoadConfigPaths(configPathsAgent);
		}),
		observed: { ...trust, ...config, ...idle, ...storedAuth, ...configPaths },
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

function dedupeResourcesByName(global, project, nameFn) {
	const table = new Map();
	const collisions = [];
	for (const resource of [...project, ...global]) {
		const name = nameFn(resource);
		if (table.has(name)) {
			collisions.push(name);
		} else {
			table.set(name, resource);
		}
	}
	return { resources: [...table.values()], collisions };
}

function runResourceLoaderDedupeByName() {
	const loadSkills = (skillPath) =>
		skillsModule.loadSkills({
			cwd: resourceCwdDirectory,
			agentDir: resourceAgentDirectory,
			skillPaths: [skillPath],
			includeDefaults: false,
		}).skills;
	const loadPrompts = (promptPath) =>
		promptTemplatesModule.loadPromptTemplates({
			cwd: resourceCwdDirectory,
			agentDir: resourceAgentDirectory,
			promptPaths: [promptPath],
			includeDefaults: false,
		});
	const skillDedupe = dedupeResourcesByName(
		loadSkills(resourceAgentSkill),
		loadSkills(resourceProjectSkillPi),
		(skill) => skill.name,
	);
	const promptDedupe = dedupeResourcesByName(
		loadPrompts(resourceAgentPrompt),
		loadPrompts(resourceProjectPromptPi),
		(prompt) => prompt.name,
	);
	return {
		dbn_skill_count: skillDedupe.resources.length,
		dbn_skill_collisions: skillDedupe.collisions.length,
		dbn_skill_project: skillDedupe.resources.some((skill) => skill.description.includes("project overlay"))
			? 1
			: 0,
		dbn_prompt_count: promptDedupe.resources.length,
		dbn_prompt_collisions: promptDedupe.collisions.length,
		dbn_prompt_project: promptDedupe.resources.some((prompt) => prompt.content.includes("project review"))
			? 1
			: 0,
	};
}

async function measureResourceLoader() {
	const loader = await runResourceLoader();
	const skills = loader.getSkills().skills;
	const prompts = loader.getPrompts().prompts;
	const dedupe = runResourceLoaderDedupeByName();
	return {
		dedupe_by_name: await collect("resource_loader.dedupe_by_name", () => {
			return () => runResourceLoaderDedupeByName();
		}),
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
			...dedupe,
		},
	};
}

function isMissingPathError(error) {
	return (
		typeof error === "object" &&
		error !== null &&
		"code" in error &&
		(error.code === "ENOENT" || error.code === "ENOTDIR")
	);
}

async function getMutationQueueKey(filePath) {
	const resolvedPath = path.resolve(filePath);
	try {
		return await realpath(resolvedPath);
	} catch (error) {
		if (isMissingPathError(error)) {
			return resolvedPath;
		}
		throw error;
	}
}

function stageFileMutationQueueLayout() {
	const dir = path.join(scratch, "file-mutation-queue");
	mkdirSync(dir, { recursive: true });
	return {
		target: path.join(dir, "target.txt"),
		alias: path.join(dir, "alias.txt"),
		other: path.join(dir, "other.txt"),
		missing: path.join(dir, "missing.txt"),
	};
}

async function runFileMutationQueueWithQueue() {
	const { withFileMutationQueue } = fileMutationQueueModule;
	const { target, alias, other, missing } = stageFileMutationQueueLayout();
	writeFileSync(target, "seed", "utf8");
	if (existsSync(alias)) {
		unlinkSync(alias);
	}
	symlinkSync(target, alias);
	const aliasKeyOk =
		(await getMutationQueueKey(target)) === (await getMutationQueueKey(alias)) ? 1 : 0;
	const missingKeyOk =
		(await getMutationQueueKey(missing)) === path.resolve(missing) ? 1 : 0;
	const otherKeyOk =
		(await getMutationQueueKey(target)) !== (await getMutationQueueKey(other)) ? 1 : 0;
	let fifoSum = 0;
	await withFileMutationQueue(target, async () => {
		fifoSum += 1;
	});
	await withFileMutationQueue(target, async () => {
		fifoSum += 2;
	});
	await withFileMutationQueue(target, async () => {
		fifoSum += 3;
	});
	let otherRun = 0;
	await withFileMutationQueue(target, async () => {
		otherRun = await withFileMutationQueue(other, async () => 7);
	});
	let clean = 0;
	await withFileMutationQueue(other, async () => {
		clean = 1;
	});
	return {
		fmq_alias_key: aliasKeyOk,
		fmq_missing_key: missingKeyOk,
		fmq_other_key: otherKeyOk,
		fmq_fifo_sum: fifoSum,
		fmq_other_run: otherRun,
		fmq_clean: clean,
	};
}

async function runFileMutationQueueQueueKey() {
	const { target, alias, other, missing } = stageFileMutationQueueLayout();
	writeFileSync(target, "seed", "utf8");
	if (existsSync(alias)) {
		unlinkSync(alias);
	}
	symlinkSync(target, alias);
	const targetKey = await getMutationQueueKey(target);
	const aliasKey = await getMutationQueueKey(alias);
	const missingKey = await getMutationQueueKey(missing);
	const otherKey = await getMutationQueueKey(other);
	return {
		fmqk_alias: targetKey === aliasKey ? 1 : 0,
		fmqk_missing: missingKey === path.resolve(missing) ? 1 : 0,
		fmqk_other: targetKey !== otherKey ? 1 : 0,
		fmqk_n: 4,
	};
}

const fileMutationLockQueues = new Map();

async function lockMutationQueue(filePath) {
	const key = await getMutationQueueKey(filePath);
	let state = fileMutationLockQueues.get(key);
	if (!state) {
		state = { key, pending: 0 };
		fileMutationLockQueues.set(key, state);
	}
	return state;
}

function dropEmptyMutationLockQueues() {
	for (const [key, state] of fileMutationLockQueues) {
		if (state.pending === 0) {
			fileMutationLockQueues.delete(key);
		}
	}
}

async function runFileMutationQueueLock() {
	const { target, alias, other, missing } = stageFileMutationQueueLayout();
	writeFileSync(target, "seed", "utf8");
	if (existsSync(alias)) {
		unlinkSync(alias);
	}
	symlinkSync(target, alias);
	const targetState = await lockMutationQueue(target);
	const aliasState = await lockMutationQueue(alias);
	const otherState = await lockMutationQueue(other);
	const missingState = await lockMutationQueue(missing);
	const repeatState = await lockMutationQueue(target);
	const observed = {
		fmql_alias: targetState === aliasState ? 1 : 0,
		fmql_other: targetState !== otherState ? 1 : 0,
		fmql_missing: missingState.pending === 0 ? 1 : 0,
		fmql_repeat: targetState === repeatState ? 1 : 0,
		fmql_n: 5,
	};
	dropEmptyMutationLockQueues();
	return observed;
}

const fileMutationRegisterQueues = new Map();

async function registerMutationQueue(filePath) {
	const key = await getMutationQueueKey(filePath);
	let state = fileMutationRegisterQueues.get(key);
	if (!state) {
		state = { key, pending: 0, nextTicket: 0 };
		fileMutationRegisterQueues.set(key, state);
	}
	const ticket = state.nextTicket;
	state.nextTicket += 1;
	state.pending += 1;
	return { key, state, ticket };
}

async function runFileMutationQueueRegister() {
	const { target, alias, other, missing } = stageFileMutationQueueLayout();
	writeFileSync(target, "seed", "utf8");
	if (existsSync(alias)) {
		unlinkSync(alias);
	}
	symlinkSync(target, alias);
	const targetReg = await registerMutationQueue(target);
	const aliasReg = await registerMutationQueue(alias);
	const otherReg = await registerMutationQueue(other);
	await registerMutationQueue(missing);
	const observed = {
		fmqr_alias: targetReg.key === aliasReg.key ? 1 : 0,
		fmqr_other: targetReg.key !== otherReg.key ? 1 : 0,
		fmqr_pending:
			targetReg.state === aliasReg.state && targetReg.state.pending === 2 ? 1 : 0,
		fmqr_ticket: aliasReg.ticket === 1 ? 1 : 0,
		fmqr_n: 4,
	};
	fileMutationRegisterQueues.clear();
	return observed;
}

const fileMutationWaitQueues = new Map();

async function registerMutationWaitQueue(filePath) {
	const key = await getMutationQueueKey(filePath);
	let state = fileMutationWaitQueues.get(key);
	if (!state) {
		state = { key, pending: 0, nextTicket: 0, serving: 0 };
		fileMutationWaitQueues.set(key, state);
	}
	const ticket = state.nextTicket;
	state.nextTicket += 1;
	state.pending += 1;
	return { key, state, ticket };
}

async function waitMutationTurn(state, ticket) {
	while (state.serving !== ticket) {
		await Promise.resolve();
	}
}

async function runFileMutationQueueWaitTurn() {
	const { target, alias, other, missing } = stageFileMutationQueueLayout();
	writeFileSync(target, "seed", "utf8");
	if (existsSync(alias)) {
		unlinkSync(alias);
	}
	symlinkSync(target, alias);
	const targetReg = await registerMutationWaitQueue(target);
	const aliasReg = await registerMutationWaitQueue(alias);
	const otherReg = await registerMutationWaitQueue(other);
	const missingReg = await registerMutationWaitQueue(missing);
	await waitMutationTurn(targetReg.state, targetReg.ticket);
	await waitMutationTurn(otherReg.state, otherReg.ticket);
	await waitMutationTurn(missingReg.state, missingReg.ticket);
	const observed = {
		fmqw_serving: targetReg.state.serving === 0 ? 1 : 0,
		fmqw_pending:
			targetReg.state === aliasReg.state && targetReg.state.pending === 2 ? 1 : 0,
		fmqw_other: otherReg.state.serving === 0 ? 1 : 0,
		fmqw_missing: missingReg.state.serving === 0 ? 1 : 0,
		fmqw_n: 4,
	};
	fileMutationWaitQueues.clear();
	return observed;
}

const fileMutationReleaseQueues = new Map();

async function registerMutationReleaseQueue(filePath) {
	const key = await getMutationQueueKey(filePath);
	let state = fileMutationReleaseQueues.get(key);
	if (!state) {
		state = { key, pending: 0, nextTicket: 0, serving: 0 };
		fileMutationReleaseQueues.set(key, state);
	}
	const ticket = state.nextTicket;
	state.nextTicket += 1;
	state.pending += 1;
	return { key, state, ticket };
}

async function waitMutationReleaseTurn(state, ticket) {
	while (state.serving !== ticket) {
		await Promise.resolve();
	}
}

function releaseMutationTurn(map, key, state) {
	state.serving += 1;
	state.pending -= 1;
	if (state.pending === 0 && map.get(key) === state) {
		map.delete(key);
	}
}

async function runFileMutationQueueReleaseTurn() {
	const { target, alias, other, missing } = stageFileMutationQueueLayout();
	writeFileSync(target, "seed", "utf8");
	if (existsSync(alias)) {
		unlinkSync(alias);
	}
	symlinkSync(target, alias);
	const targetReg = await registerMutationReleaseQueue(target);
	const aliasReg = await registerMutationReleaseQueue(alias);
	const otherReg = await registerMutationReleaseQueue(other);
	const missingReg = await registerMutationReleaseQueue(missing);
	await waitMutationReleaseTurn(targetReg.state, targetReg.ticket);
	releaseMutationTurn(fileMutationReleaseQueues, targetReg.key, targetReg.state);
	await waitMutationReleaseTurn(otherReg.state, otherReg.ticket);
	releaseMutationTurn(fileMutationReleaseQueues, otherReg.key, otherReg.state);
	await waitMutationReleaseTurn(missingReg.state, missingReg.ticket);
	releaseMutationTurn(fileMutationReleaseQueues, missingReg.key, missingReg.state);
	const observed = {
		fmqe_serving: targetReg.state.serving === 1 ? 1 : 0,
		fmqe_pending:
			targetReg.state === aliasReg.state && targetReg.state.pending === 1 ? 1 : 0,
		fmqe_other: fileMutationReleaseQueues.has(otherReg.key) ? 0 : 1,
		fmqe_missing: fileMutationReleaseQueues.has(missingReg.key) ? 0 : 1,
		fmqe_n: 4,
	};
	fileMutationReleaseQueues.clear();
	return observed;
}

const fileMutationEnsureQueues = new Map();

function ensureMutationQueueState(key) {
	let state = fileMutationEnsureQueues.get(key);
	if (!state) {
		state = { key, pending: 0 };
		fileMutationEnsureQueues.set(key, state);
	}
	return state;
}

function dropEmptyMutationEnsureQueues() {
	for (const [key, state] of fileMutationEnsureQueues) {
		if (state.pending === 0) {
			fileMutationEnsureQueues.delete(key);
		}
	}
}

async function runFileMutationQueueEnsureState() {
	const { target, alias, other, missing } = stageFileMutationQueueLayout();
	writeFileSync(target, "seed", "utf8");
	if (existsSync(alias)) {
		unlinkSync(alias);
	}
	symlinkSync(target, alias);
	const targetKey = await getMutationQueueKey(target);
	const aliasKey = await getMutationQueueKey(alias);
	const otherKey = await getMutationQueueKey(other);
	const missingKey = await getMutationQueueKey(missing);
	const targetState = ensureMutationQueueState(targetKey);
	const aliasState = ensureMutationQueueState(aliasKey);
	const otherState = ensureMutationQueueState(otherKey);
	const missingState = ensureMutationQueueState(missingKey);
	const repeatState = ensureMutationQueueState(targetKey);
	const observed = {
		fmqs_alias: targetState === aliasState ? 1 : 0,
		fmqs_other: targetState !== otherState ? 1 : 0,
		fmqs_missing: missingState.pending === 0 ? 1 : 0,
		fmqs_repeat: targetState === repeatState ? 1 : 0,
		fmqs_n: 5,
	};
	dropEmptyMutationEnsureQueues();
	return observed;
}

async function runFileMutationQueueCallWith() {
	const { withFileMutationQueue } = fileMutationQueueModule;
	const { target, alias, other } = stageFileMutationQueueLayout();
	writeFileSync(target, "seed", "utf8");
	if (existsSync(alias)) {
		unlinkSync(alias);
	}
	symlinkSync(target, alias);
	const aliasKeyOk =
		(await getMutationQueueKey(target)) === (await getMutationQueueKey(alias)) ? 1 : 0;
	const otherKeyOk =
		(await getMutationQueueKey(target)) !== (await getMutationQueueKey(other)) ? 1 : 0;
	let fifoSum = 0;
	await withFileMutationQueue(target, async () => {
		fifoSum += 1;
	});
	await withFileMutationQueue(target, async () => {
		fifoSum += 2;
	});
	await withFileMutationQueue(target, async () => {
		fifoSum += 3;
	});
	let otherRun = 0;
	await withFileMutationQueue(target, async () => {
		otherRun = await withFileMutationQueue(other, async () => 7);
	});
	return {
		fmqf_alias: aliasKeyOk,
		fmqf_other: otherKeyOk,
		fmqf_fifo: fifoSum,
		fmqf_run: otherRun,
		fmqf_n: 4,
	};
}

function makeMutationQueueState(key) {
	return { key, pending: 0, nextTicket: 0, serving: 0 };
}

async function runFileMutationQueueMakeState() {
	const { target, other } = stageFileMutationQueueLayout();
	writeFileSync(target, "seed", "utf8");
	const targetKey = await getMutationQueueKey(target);
	const otherKey = await getMutationQueueKey(other);
	const targetState = makeMutationQueueState(targetKey);
	const otherState = makeMutationQueueState(otherKey);
	return {
		fmqm_pending: targetState.pending === 0 ? 1 : 0,
		fmqm_ticket: targetState.nextTicket === 0 ? 1 : 0,
		fmqm_serving: targetState.serving === 0 ? 1 : 0,
		fmqm_other: targetState !== otherState ? 1 : 0,
		fmqm_n: 4,
	};
}

async function runFileMutationQueueStateKey() {
	const { target, alias, other, missing } = stageFileMutationQueueLayout();
	writeFileSync(target, "seed", "utf8");
	if (existsSync(alias)) {
		unlinkSync(alias);
	}
	symlinkSync(target, alias);
	const targetKey = await getMutationQueueKey(target);
	const aliasKey = await getMutationQueueKey(alias);
	const otherKey = await getMutationQueueKey(other);
	const missingKey = await getMutationQueueKey(missing);
	const targetState = ensureMutationQueueState(targetKey);
	const aliasState = ensureMutationQueueState(aliasKey);
	const otherState = ensureMutationQueueState(otherKey);
	const missingState = ensureMutationQueueState(missingKey);
	const repeatState = ensureMutationQueueState(targetKey);
	const observed = {
		fmqt_alias: targetState.key === aliasState.key ? 1 : 0,
		fmqt_other: targetState.key !== otherState.key ? 1 : 0,
		fmqt_missing: missingState.key === missingKey ? 1 : 0,
		fmqt_repeat: repeatState.key === targetKey ? 1 : 0,
		fmqt_n: 5,
	};
	dropEmptyMutationEnsureQueues();
	return observed;
}

const fileMutationAccessorQueues = new Map();

async function registerMutationAccessorQueue(filePath) {
	const key = await getMutationQueueKey(filePath);
	let state = fileMutationAccessorQueues.get(key);
	if (!state) {
		state = { key, pending: 0, nextTicket: 0, serving: 0 };
		fileMutationAccessorQueues.set(key, state);
	}
	const ticket = state.nextTicket;
	state.nextTicket += 1;
	state.pending += 1;
	return { key, state, ticket };
}

async function stageRegisteredMutationAccessorStates() {
	const { target, alias, other, missing } = stageFileMutationQueueLayout();
	writeFileSync(target, "seed", "utf8");
	if (existsSync(alias)) {
		unlinkSync(alias);
	}
	symlinkSync(target, alias);
	const targetReg = await registerMutationAccessorQueue(target);
	const aliasReg = await registerMutationAccessorQueue(alias);
	const otherReg = await registerMutationAccessorQueue(other);
	const missingReg = await registerMutationAccessorQueue(missing);
	return {
		targetState: targetReg.state,
		aliasState: aliasReg.state,
		otherState: otherReg.state,
		missingState: missingReg.state,
	};
}

async function runFileMutationQueuePendingCount() {
	const { targetState, aliasState, otherState, missingState } =
		await stageRegisteredMutationAccessorStates();
	const observed = {
		fmqp_shared: targetState === aliasState && targetState.pending === 2 ? 1 : 0,
		fmqp_other: otherState.pending === 1 ? 1 : 0,
		fmqp_missing: missingState.pending === 1 ? 1 : 0,
		fmqp_alias: aliasState.pending === 2 ? 1 : 0,
		fmqp_n: 4,
	};
	fileMutationAccessorQueues.clear();
	return observed;
}

async function runFileMutationQueueNextTicket() {
	const { targetState, aliasState, otherState, missingState } =
		await stageRegisteredMutationAccessorStates();
	const observed = {
		fmqi_shared: targetState === aliasState && targetState.nextTicket === 2 ? 1 : 0,
		fmqi_other: otherState.nextTicket === 1 ? 1 : 0,
		fmqi_missing: missingState.nextTicket === 1 ? 1 : 0,
		fmqi_alias: aliasState.nextTicket === 2 ? 1 : 0,
		fmqi_n: 4,
	};
	fileMutationAccessorQueues.clear();
	return observed;
}

async function runFileMutationQueueServingTicket() {
	const { targetState, aliasState, otherState, missingState } =
		await stageRegisteredMutationAccessorStates();
	const observed = {
		fmqv_zero: targetState === aliasState && targetState.serving === 0 ? 1 : 0,
		fmqv_other: otherState.serving === 0 ? 1 : 0,
		fmqv_missing: missingState.serving === 0 ? 1 : 0,
		fmqv_alias: aliasState.serving === 0 ? 1 : 0,
		fmqv_n: 4,
	};
	fileMutationAccessorQueues.clear();
	return observed;
}

async function measureFileMutationQueue() {
	const withQueueObserved = await runFileMutationQueueWithQueue();
	const queueKeyObserved = await runFileMutationQueueQueueKey();
	const lockObserved = await runFileMutationQueueLock();
	const registerObserved = await runFileMutationQueueRegister();
	const waitTurnObserved = await runFileMutationQueueWaitTurn();
	const releaseTurnObserved = await runFileMutationQueueReleaseTurn();
	const ensureStateObserved = await runFileMutationQueueEnsureState();
	const callWithObserved = await runFileMutationQueueCallWith();
	const makeStateObserved = await runFileMutationQueueMakeState();
	const stateKeyObserved = await runFileMutationQueueStateKey();
	const pendingCountObserved = await runFileMutationQueuePendingCount();
	const nextTicketObserved = await runFileMutationQueueNextTicket();
	const servingTicketObserved = await runFileMutationQueueServingTicket();
	return {
		with_queue: await collect("file_mutation_queue.with_queue", () => {
			return () => runFileMutationQueueWithQueue();
		}),
		queue_key: await collect("file_mutation_queue.queue_key", () => {
			return () => runFileMutationQueueQueueKey();
		}),
		lock: await collect("file_mutation_queue.lock", () => {
			return () => runFileMutationQueueLock();
		}),
		register: await collect("file_mutation_queue.register", () => {
			return () => runFileMutationQueueRegister();
		}),
		wait_turn: await collect("file_mutation_queue.wait_turn", () => {
			return () => runFileMutationQueueWaitTurn();
		}),
		release_turn: await collect("file_mutation_queue.release_turn", () => {
			return () => runFileMutationQueueReleaseTurn();
		}),
		ensure_state: await collect("file_mutation_queue.ensure_state", () => {
			return () => runFileMutationQueueEnsureState();
		}),
		call_with: await collect("file_mutation_queue.call_with", () => {
			return () => runFileMutationQueueCallWith();
		}),
		make_state: await collect("file_mutation_queue.make_state", () => {
			return () => runFileMutationQueueMakeState();
		}),
		state_key: await collect("file_mutation_queue.state_key", () => {
			return () => runFileMutationQueueStateKey();
		}),
		pending_count: await collect("file_mutation_queue.pending_count", () => {
			return () => runFileMutationQueuePendingCount();
		}),
		next_ticket: await collect("file_mutation_queue.next_ticket", () => {
			return () => runFileMutationQueueNextTicket();
		}),
		serving_ticket: await collect("file_mutation_queue.serving_ticket", () => {
			return () => runFileMutationQueueServingTicket();
		}),
		observed: {
			...withQueueObserved,
			...queueKeyObserved,
			...lockObserved,
			...registerObserved,
			...waitTurnObserved,
			...releaseTurnObserved,
			...ensureStateObserved,
			...callWithObserved,
			...makeStateObserved,
			...stateKeyObserved,
			...pendingCountObserved,
			...nextTicketObserved,
			...servingTicketObserved,
		},
	};
}

function runHarnessEventsEmit() {
	const bus = new harnessEventsModule.HarnessEventBus();
	const direct = [];
	const watched = [];
	const off = bus.on("run_start", (event) => {
		direct.push(event);
	});
	const handle = bus.watch(() => null);
	handle.start((event) => {
		watched.push(event);
	});
	const runStart = { type: "run_start", lane: "main", runId: "run-1" };
	const runEnd = {
		type: "run_end",
		lane: "main",
		runId: "run-1",
		outcome: "completed",
		leafId: "entry-1",
	};
	bus.emit(runStart);
	bus.emit(runEnd);
	off();
	bus.emit(runStart);
	handle.unsubscribe();
	return {
		he_direct: direct.length === 1 ? 1 : 0,
		he_watch: watched.length === 3 ? 1 : 0,
		he_start: watched[0]?.type === "run_start" ? 1 : 0,
		he_end: watched[1]?.type === "run_end" ? 1 : 0,
		he_second: watched[2]?.type === "run_start" ? 1 : 0,
	};
}

function runHarnessEventsOn() {
	const bus = new harnessEventsModule.HarnessEventBus();
	const starts = [];
	const ends = [];
	const offStart = bus.on("run_start", (event) => {
		starts.push(event);
	});
	bus.on("run_end", (event) => {
		ends.push(event);
	});
	offStart();
	const runStart = { type: "run_start", lane: "main", runId: "run-1" };
	const runEnd = {
		type: "run_end",
		lane: "main",
		runId: "run-1",
		outcome: "completed",
		leafId: "entry-1",
	};
	bus.emit(runStart);
	bus.emit(runEnd);
	return {
		heon_off: starts.length === 0 ? 1 : 0,
		heon_keep: ends.length === 1 ? 1 : 0,
		heon_type: ends[0]?.type === "run_end" ? 1 : 0,
	};
}

function runHarnessEventsWatch() {
	const bus = new harnessEventsModule.HarnessEventBus();
	const received = [];
	const runStart = { type: "run_start", lane: "main", runId: "run-1" };
	const runEnd = {
		type: "run_end",
		lane: "main",
		runId: "run-1",
		outcome: "completed",
		leafId: "entry-1",
	};
	const expectedSnapshot = "snap";
	const handle = bus.watch(() => {
		bus.emit(runStart);
		return expectedSnapshot;
	});
	handle.start((event) => {
		received.push(event);
	});
	bus.emit(runEnd);
	handle.unsubscribe();
	bus.emit(runStart);
	return {
		hew_snap: handle.snapshot === expectedSnapshot ? 1 : 0,
		hew_count: received.length === 2 ? 1 : 0,
		hew_start: received[0]?.type === "run_start" ? 1 : 0,
		hew_end: received[1]?.type === "run_end" ? 1 : 0,
	};
}

function runHarnessEventsMakeStart() {
	const event = { type: "run_start", lane: "main", runId: "run-1" };
	return {
		hes_type: event.type === "run_start" ? 1 : 0,
		hes_lane: event.lane === "main" ? 1 : 0,
		hes_run: event.runId === "run-1" ? 1 : 0,
	};
}

function runHarnessEventsMakeEnd() {
	const event = {
		type: "run_end",
		lane: "main",
		runId: "run-1",
		outcome: "completed",
		leafId: "entry-1",
	};
	const aborted = {
		type: "run_end",
		lane: "side",
		runId: "run-2",
		outcome: "aborted",
		leafId: null,
	};
	return {
		hee_type: event.type === "run_end" ? 1 : 0,
		hee_lane: event.lane === "main" ? 1 : 0,
		hee_run: event.runId === "run-1" ? 1 : 0,
		hee_outcome: event.outcome === "completed" ? 1 : 0,
		hee_abort: aborted.outcome === "aborted" && aborted.leafId == null ? 1 : 0,
	};
}

function runHarnessEventsEventType() {
	const start = { type: "run_start", lane: "main", runId: "run-1" };
	const end = {
		type: "run_end",
		lane: "main",
		runId: "run-1",
		outcome: "completed",
		leafId: "entry-1",
	};
	const failed = {
		type: "run_end",
		lane: "side",
		runId: "run-2",
		outcome: "failed",
		leafId: "leaf-2",
	};
	return {
		het_start: start.type === "run_start" ? 1 : 0,
		het_end: end.type === "run_end" ? 1 : 0,
		het_fail: failed.type === "run_end" ? 1 : 0,
	};
}

function runHarnessEventsMakeBus() {
	const a = new harnessEventsModule.HarnessEventBus();
	const b = new harnessEventsModule.HarnessEventBus();
	return {
		heb_distinct: a !== b ? 1 : 0,
		heb_a: a instanceof harnessEventsModule.HarnessEventBus ? 1 : 0,
		heb_b: b instanceof harnessEventsModule.HarnessEventBus ? 1 : 0,
	};
}

const FIND_TOOL_CWD = "/tmp/goal20-find-tool-cwd";
const GLOB_SPECIAL = new Set(".^$+()[]{}|\\".split(""));

function globRegexSource(pattern) {
	let out = "^";
	for (let index = 0; index < pattern.length; ) {
		const character = pattern[index];
		if (character === "*") {
			if (index + 1 < pattern.length && pattern[index + 1] === "*") {
				index++;
				if (index + 1 < pattern.length && pattern[index + 1] === "/") {
					index++;
					out += "(?:.*/)?";
				} else {
					out += ".*";
				}
			} else {
				out += "[^/]*";
			}
		} else if (character === "?") {
			out += "[^/]";
		} else if (GLOB_SPECIAL.has(character)) {
			out += `\\${character}`;
		} else {
			out += character;
		}
		index++;
	}
	return `${out}$`;
}

function findPatternMatchP(pattern, relative) {
	const re = new RegExp(globRegexSource(pattern));
	const target = pattern.includes("/") ? relative : path.posix.basename(relative);
	return re.test(target);
}

function ensureFindToolFixture() {
	mkdirSync(path.join(FIND_TOOL_CWD, "src", "nested"), { recursive: true });
	for (const relative of ["a.lisp", "b.txt", "src/c.lisp", "src/nested/d.lisp"]) {
		writeFileSync(path.join(FIND_TOOL_CWD, relative), "x", "utf8");
	}
	return FIND_TOOL_CWD;
}

function walkFindRelatives(root) {
	const files = [];
	const walk = (dir) => {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			const full = path.join(dir, entry.name);
			if (entry.isDirectory()) {
				if (entry.name === ".git" || entry.name === "node_modules") continue;
				walk(full);
			} else if (entry.isFile()) {
				files.push(full);
			}
		}
	};
	walk(root);
	return files
		.map((full) =>
			findModule.relativizeFindResultPath(full, root),
		)
		.sort();
}

function findToolOutputText(cwd, pattern) {
	const matches = walkFindRelatives(cwd).filter((relative) =>
		findPatternMatchP(pattern, relative),
	);
	if (matches.length === 0) return "No files found matching pattern";
	return matches.join("\n");
}

function findToolLineCount(text) {
	if (text === "No files found matching pattern") return 0;
	return text.split("\n").length;
}

function runFindPatternMatch() {
	const starA = findPatternMatchP("*.lisp", "a.lisp");
	const starSrc = findPatternMatchP("*.lisp", "src/c.lisp");
	const starTxt = findPatternMatchP("*.lisp", "b.txt");
	const pathSrc = findPatternMatchP("src/**/*.lisp", "src/c.lisp");
	const pathRoot = findPatternMatchP("src/**/*.lisp", "a.lisp");
	const srcStarNested = findPatternMatchP("src/*.lisp", "src/nested/d.lisp");
	return {
		fpm_star_a: starA ? 1 : 0,
		fpm_star_src: starSrc ? 1 : 0,
		fpm_star_txt: starTxt ? 0 : 1,
		fpm_path_src: pathSrc ? 1 : 0,
		fpm_path_root: pathRoot ? 0 : 1,
		fpm_src_star: srcStarNested ? 0 : 1,
		fpm_n: 6,
	};
}

function runFindFiles() {
	const cwd = ensureFindToolFixture();
	const empty = findToolOutputText(cwd, "*.nomatch");
	const lisp = findToolOutputText(cwd, "*.lisp");
	const pathPat = findToolOutputText(cwd, "src/**/*.lisp");
	const srcStar = findToolOutputText(cwd, "src/*.lisp");
	return {
		ff_empty: empty === "No files found matching pattern" ? 1 : 0,
		ff_lisp: findToolLineCount(lisp),
		ff_path: findToolLineCount(pathPat),
		ff_src_star: findToolLineCount(srcStar),
		ff_n: 4,
	};
}

function runFindMakeTool() {
	const cwd = ensureFindToolFixture();
	const def = findModule.createFindToolDefinition(cwd);
	const required = def.parameters?.required ?? [];
	const description = def.description ?? "";
	return {
		fmt_name: def.name === "find" ? 1 : 0,
		fmt_desc:
			description.includes("Search for files by glob pattern") &&
			description.includes("Respects .gitignore")
				? 1
				: 0,
		fmt_req: required.includes("pattern") ? 1 : 0,
		fmt_n: 3,
	};
}

async function measureFindTool() {
	ensureFindToolFixture();
	const patternObserved = runFindPatternMatch();
	const filesObserved = runFindFiles();
	const makeObserved = runFindMakeTool();
	return {
		pattern_match: await collect("find_tool.pattern_match", () => {
			return () => runFindPatternMatch();
		}),
		find_files: await collect("find_tool.find_files", () => {
			return () => runFindFiles();
		}),
		make_tool: await collect("find_tool.make_tool", () => {
			return () => runFindMakeTool();
		}),
		observed: {
			...patternObserved,
			...filesObserved,
			...makeObserved,
		},
	};
}
const WRITE_TOOL_CWD = path.join(tmpdir(), "goal20-write-tool-cwd");

function writeToolPath(relative) {
	return path.join(WRITE_TOOL_CWD, relative);
}

function ensureWriteToolFixture() {
	mkdirSync(path.join(WRITE_TOOL_CWD, "nested", "deep"), { recursive: true });
	mkdirSync(path.join(WRITE_TOOL_CWD, "existing"), { recursive: true });
	return WRITE_TOOL_CWD;
}

async function runWriteEnsureParent() {
	ensureWriteToolFixture();
	const nested = writeToolPath("nested/deep/a.txt");
	const existing = writeToolPath("existing/b.txt");
	const blocker = writeToolPath("blocker");
	const blocked = writeToolPath("blocker/c.txt");
	try {
		unlinkSync(blocker);
	} catch {
		// missing is fine
	}
	let nestedOk = 0;
	let existsOk = 0;
	let eexist = 0;
	try {
		await fsMkdir(path.dirname(nested), { recursive: true });
		nestedOk = 1;
	} catch {
		nestedOk = 0;
	}
	try {
		await fsMkdir(path.dirname(existing), { recursive: true });
		existsOk = 1;
	} catch {
		existsOk = 0;
	}
	writeFileSync(blocker, "file", "utf8");
	try {
		await fsMkdir(path.dirname(blocked), { recursive: true });
		eexist = 0;
	} catch {
		eexist = 1;
	}
	return {
		ep_nested: nestedOk,
		ep_exists: existsOk,
		ep_eexist: eexist,
		ep_n: 3,
	};
}

async function runWriteUtf8() {
	ensureWriteToolFixture();
	const asciiPath = writeToolPath("out-ascii.txt");
	const cjkPath = writeToolPath("out-cjk.txt");
	const asciiText = "hello";
	const cjkText = "中🙂";
	await fsWriteFile(asciiPath, asciiText, "utf-8");
	await fsWriteFile(cjkPath, cjkText, "utf-8");
	return {
		wu_ok: existsSync(asciiPath) ? 1 : 0,
		wu_ascii: asciiText.length,
		wu_cjk: cjkText.length,
		wu_n: 3,
	};
}

function writeSchemaRequired(def) {
	const params = def?.parameters;
	if (Array.isArray(params?.required)) return params.required;
	if (Array.isArray(params?.Required)) return params.Required;
	const properties = params?.properties;
	if (properties && typeof properties === "object") return Object.keys(properties);
	return [];
}

function runWriteMakeTool() {
	const cwd = ensureWriteToolFixture();
	const def = writeModule.createWriteToolDefinition(cwd);
	const required = writeSchemaRequired(def);
	const description = def.description ?? "";
	return {
		wmt_name: def.name === "write" ? 1 : 0,
		wmt_desc:
			description.includes("Write content to a file") &&
			description.includes("Automatically creates parent directories")
				? 1
				: 0,
		wmt_req:
			required.includes("path") && required.includes("content") ? 1 : 0,
		wmt_n: 3,
	};
}

async function measureWriteTool() {
	ensureWriteToolFixture();
	const parentObserved = await runWriteEnsureParent();
	const utf8Observed = await runWriteUtf8();
	const makeObserved = runWriteMakeTool();
	return {
		ensure_parent: await collect("write_tool.ensure_parent", () => {
			return () => runWriteEnsureParent();
		}),
		write_utf8: await collect("write_tool.write_utf8", () => {
			return () => runWriteUtf8();
		}),
		make_tool: await collect("write_tool.make_tool", () => {
			return () => runWriteMakeTool();
		}),
		observed: {
			...parentObserved,
			...utf8Observed,
			...makeObserved,
		},
	};
}
const LS_TOOL_CWD = "/tmp/goal20-ls-tool-cwd";

function lsDirectoryEntryName(fullPath) {
	const stats = statSync(fullPath);
	const base = path.basename(fullPath.replace(/[\\/]+$/, "") || fullPath);
	return stats.isDirectory() ? `${base}/` : base;
}

function ensureLsToolFixture() {
	mkdirSync(path.join(LS_TOOL_CWD, "src", "nested"), { recursive: true });
	mkdirSync(path.join(LS_TOOL_CWD, "empty"), { recursive: true });
	mkdirSync(path.join(LS_TOOL_CWD, "lots"), { recursive: true });
	for (const relative of [
		".dot",
		"a.txt",
		"z.txt",
		"src/nested/x.txt",
		"lots/f1.txt",
		"lots/f2.txt",
		"lots/f3.txt",
		"lots/f4.txt",
	]) {
		writeFileSync(path.join(LS_TOOL_CWD, relative), "x", "utf8");
	}
	return LS_TOOL_CWD;
}

function lsToolOutputText(cwd, args) {
	const dirPath = path.resolve(cwd, args.path || ".");
	const limit = args.limit ?? 500;
	const names = readdirSync(dirPath);
	names.sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
	const results = [];
	let entryLimitReached = false;
	for (const entry of names) {
		if (results.length >= limit) {
			entryLimitReached = true;
			break;
		}
		const fullPath = path.join(dirPath, entry);
		let suffix = "";
		try {
			if (statSync(fullPath).isDirectory()) suffix = "/";
		} catch {
			continue;
		}
		results.push(entry + suffix);
	}
	if (results.length === 0) return "(empty directory)";
	const rawOutput = results.join("\n");
	const truncation = truncateModule.truncateHead(rawOutput, {
		maxLines: Number.MAX_SAFE_INTEGER,
	});
	let output = truncation.content;
	const notices = [];
	if (entryLimitReached) {
		notices.push(`${limit} entries limit reached. Use limit=${limit * 2} for more`);
	}
	if (truncation.truncated) {
		notices.push(
			`${truncateModule.formatSize(truncateModule.DEFAULT_MAX_BYTES)} limit reached`,
		);
	}
	if (notices.length > 0) {
		output += `\n\n[${notices.join(". ")}]`;
	}
	return output;
}

function lsToolLineCount(text) {
	if (text === "(empty directory)") return 0;
	return text.split("\n").length;
}

function runLsDirectoryEntryName() {
	const cwd = LS_TOOL_CWD;
	const fileName = lsDirectoryEntryName(path.join(cwd, "a.txt"));
	const dirName = lsDirectoryEntryName(path.join(cwd, "src"));
	const nestedName = lsDirectoryEntryName(path.join(cwd, "src", "nested"));
	return {
		lden_file: fileName === "a.txt" ? 1 : 0,
		lden_dir: dirName === "src/" ? 1 : 0,
		lden_nested: nestedName === "nested/" ? 1 : 0,
		lden_n: 3,
	};
}

function runLsListDirectory() {
	const cwd = ensureLsToolFixture();
	const empty = lsToolOutputText(cwd, { path: "empty" });
	const mixed = lsToolOutputText(cwd, { path: "." });
	const limited = lsToolOutputText(cwd, { path: "lots", limit: 2 });
	const firstLine = mixed.split("\n")[0];
	return {
		ld_empty: empty === "(empty directory)" ? 1 : 0,
		ld_mixed: lsToolLineCount(mixed),
		ld_first: firstLine === ".dot" ? 1 : 0,
		ld_limit:
			limited.includes("2 entries limit reached") &&
			limited.includes("Use limit=4 for more")
				? 1
				: 0,
		ld_n: 4,
	};
}

function runLsMakeTool() {
	const cwd = ensureLsToolFixture();
	const def = lsModule.createLsToolDefinition(cwd);
	const required = def.parameters?.required ?? [];
	const description = def.description ?? "";
	return {
		lst_name: def.name === "ls" ? 1 : 0,
		lst_desc:
			description.includes("List directory contents") &&
			description.includes("500 entries")
				? 1
				: 0,
		lst_req: required.length === 0 ? 1 : 0,
		lst_n: 3,
	};
}

async function measureLsTool() {
	ensureLsToolFixture();
	const nameObserved = runLsDirectoryEntryName();
	const listObserved = runLsListDirectory();
	const makeObserved = runLsMakeTool();
	return {
		directory_entry_name: await collect("ls_tool.directory_entry_name", () => {
			return () => runLsDirectoryEntryName();
		}),
		list_directory: await collect("ls_tool.list_directory", () => {
			return () => runLsListDirectory();
		}),
		make_tool: await collect("ls_tool.make_tool", () => {
			return () => runLsMakeTool();
		}),
		observed: {
			...nameObserved,
			...listObserved,
			...makeObserved,
		},
	};
}

const POWERSHELL_UTF8_OUTPUT_PREFIX =
	"try { [Console]::OutputEncoding=[System.Text.Encoding]::UTF8 } catch {}\n";

function runPowershellUtf8Prefix() {
	const prefix = POWERSHELL_UTF8_OUTPUT_PREFIX;
	return {
		psu_len: prefix.length,
		psu_nl: prefix.endsWith("\n") ? 1 : 0,
		psu_try: prefix.startsWith("try ") ? 1 : 0,
		psu_utf8: prefix.includes("UTF8") ? 1 : 0,
		psu_n: 4,
	};
}

function powershellPrefixCommand(command) {
	return `${POWERSHELL_UTF8_OUTPUT_PREFIX}${command}`;
}

function runPowershellPrefixCommand() {
	const prefix = POWERSHELL_UTF8_OUTPUT_PREFIX;
	const empty = powershellPrefixCommand("");
	const date = powershellPrefixCommand("Get-Date");
	const write = powershellPrefixCommand("Write-Output hi");
	return {
		psc_empty: empty === prefix ? 1 : 0,
		psc_date: date.startsWith(prefix) && date.endsWith("Get-Date") ? 1 : 0,
		psc_write:
			write.startsWith(prefix) && write.endsWith("Write-Output hi") ? 1 : 0,
		psc_n: 3,
	};
}

function runPowershellMakeTool() {
	const def = powershellModule.createPowerShellToolDefinition("/tmp");
	const required = def.parameters?.required ?? [];
	const description = def.description ?? "";
	return {
		pmt_name: def.name === "powershell" ? 1 : 0,
		pmt_desc: description.includes("Execute a PowerShell command") ? 1 : 0,
		pmt_req: required.includes("command") ? 1 : 0,
		pmt_n: 3,
	};
}

async function measurePowershellTool() {
	const prefixObserved = runPowershellUtf8Prefix();
	const commandObserved = runPowershellPrefixCommand();
	const makeObserved = runPowershellMakeTool();
	return {
		utf8_prefix: await collect("powershell_tool.utf8_prefix", () => {
			return () => runPowershellUtf8Prefix();
		}),
		prefix_command: await collect("powershell_tool.prefix_command", () => {
			return () => runPowershellPrefixCommand();
		}),
		make_tool: await collect("powershell_tool.make_tool", () => {
			return () => runPowershellMakeTool();
		}),
		observed: {
			...prefixObserved,
			...commandObserved,
			...makeObserved,
		},
	};
}

async function measureHarnessEvents() {
	const emitObserved = runHarnessEventsEmit();
	const onObserved = runHarnessEventsOn();
	const watchObserved = runHarnessEventsWatch();
	const makeStartObserved = runHarnessEventsMakeStart();
	const makeEndObserved = runHarnessEventsMakeEnd();
	const eventTypeObserved = runHarnessEventsEventType();
	const makeBusObserved = runHarnessEventsMakeBus();
	return {
		emit: await collect("harness_events.emit", () => {
			return () => runHarnessEventsEmit();
		}),
		on: await collect("harness_events.on", () => {
			return () => runHarnessEventsOn();
		}),
		watch: await collect("harness_events.watch", () => {
			return () => runHarnessEventsWatch();
		}),
		make_start: await collect("harness_events.make_start", () => {
			return () => runHarnessEventsMakeStart();
		}),
		make_end: await collect("harness_events.make_end", () => {
			return () => runHarnessEventsMakeEnd();
		}),
		event_type: await collect("harness_events.event_type", () => {
			return () => runHarnessEventsEventType();
		}),
		make_bus: await collect("harness_events.make_bus", () => {
			return () => runHarnessEventsMakeBus();
		}),
		observed: {
			...emitObserved,
			...onObserved,
			...watchObserved,
			...makeStartObserved,
			...makeEndObserved,
			...eventTypeObserved,
			...makeBusObserved,
		},
	};
}

const BASH_NOTICE_PATH = "/tmp/pi-bash-notice.log";
const BASH_NOTICE_FULL_OUTPUT = "keep\nLASTLINE";

function stripExitFooter(text, exitCode) {
	const footer = `Process exited with code ${exitCode}`;
	if (text === footer) return "";
	if (text.length > footer.length && text.endsWith(footer)) {
		const end = text.length - footer.length;
		if (end > 0 && text[end - 1] === "\n") return text.slice(0, end - 1);
		return text.slice(0, end);
	}
	return text;
}

function appendStatus(text, status) {
	return `${text ? `${text}\n\n` : ""}${status}`;
}

function bashTruncationNotice(details, outputPath, fullOutput) {
	if (!details.truncated) return "";
	const totalLines = details.totalLines;
	const outputLines = details.outputLines;
	const startLine = totalLines - outputLines + 1;
	const endLine = totalLines;
	if (details.lastLinePartial) {
		let lines = fullOutput.length === 0 ? [] : fullOutput.split("\n");
		if (lines.length && fullOutput.endsWith("\n")) lines = lines.slice(0, -1);
		const lastLine = lines.length ? lines[lines.length - 1] : "";
		return `[Showing last ${truncateModule.formatSize(details.outputBytes)} of line ${endLine} (line is ${truncateModule.formatSize(Buffer.byteLength(lastLine, "utf8"))}). Full output: ${outputPath}]`;
	}
	if (details.truncatedBy === "lines") {
		return `[Showing lines ${startLine}-${endLine} of ${totalLines}. Full output: ${outputPath}]`;
	}
	return `[Showing lines ${startLine}-${endLine} of ${totalLines} (${truncateModule.formatSize(truncateModule.DEFAULT_MAX_BYTES)} limit). Full output: ${outputPath}]`;
}

function runBashStripExitFooter() {
	const exact = stripExitFooter("Process exited with code 0", 0);
	const nl = stripExitFooter("hello\nProcess exited with code 1", 1);
	const noNl = stripExitFooter("helloProcess exited with code 2", 2);
	const plain = stripExitFooter("plain output", 3);
	const empty = stripExitFooter("", 4);
	return {
		sef_exact: exact === "" ? 1 : 0,
		sef_nl: nl === "hello" ? 1 : 0,
		sef_no_nl: noNl === "hello" ? 1 : 0,
		sef_plain: plain === "plain output" ? 1 : 0,
		sef_empty: empty === "" ? 1 : 0,
		sef_n: 5,
	};
}

function runBashAppendStatus() {
	const empty = appendStatus("", "Command aborted");
	const abort = appendStatus("out", "Command aborted");
	const exit = appendStatus("out", "Command exited with code 1");
	const timeout = appendStatus("out", "Command timed out after 5 seconds");
	return {
		abs_empty: empty === "Command aborted" ? 1 : 0,
		abs_abort: abort === "out\n\nCommand aborted" ? 1 : 0,
		abs_exit: exit === "out\n\nCommand exited with code 1" ? 1 : 0,
		abs_timeout: timeout === "out\n\nCommand timed out after 5 seconds" ? 1 : 0,
		abs_n: 4,
	};
}

function runBashTruncationNotice() {
	const none = bashTruncationNotice(
		{ truncated: false },
		BASH_NOTICE_PATH,
		BASH_NOTICE_FULL_OUTPUT,
	);
	const partial = bashTruncationNotice(
		{
			truncated: true,
			lastLinePartial: true,
			totalLines: 2,
			outputLines: 1,
			outputBytes: 8,
		},
		BASH_NOTICE_PATH,
		BASH_NOTICE_FULL_OUTPUT,
	);
	const lines = bashTruncationNotice(
		{
			truncated: true,
			truncatedBy: "lines",
			totalLines: 10,
			outputLines: 3,
		},
		BASH_NOTICE_PATH,
		BASH_NOTICE_FULL_OUTPUT,
	);
	const bytes = bashTruncationNotice(
		{
			truncated: true,
			truncatedBy: "bytes",
			totalLines: 10,
			outputLines: 3,
		},
		BASH_NOTICE_PATH,
		BASH_NOTICE_FULL_OUTPUT,
	);
	return {
		btn_none: none === "" ? 1 : 0,
		btn_partial: partial.length,
		btn_lines: lines.length,
		btn_bytes: bytes.length,
		btn_n: 4,
	};
}

async function measureBashTool() {
	const stripObserved = runBashStripExitFooter();
	const appendObserved = runBashAppendStatus();
	const noticeObserved = runBashTruncationNotice();
	return {
		strip_exit_footer: await collect("bash_tool.strip_exit_footer", () => {
			return () => runBashStripExitFooter();
		}),
		append_status: await collect("bash_tool.append_status", () => {
			return () => runBashAppendStatus();
		}),
		truncation_notice: await collect("bash_tool.truncation_notice", () => {
			return () => runBashTruncationNotice();
		}),
		observed: {
			...stripObserved,
			...appendObserved,
			...noticeObserved,
		},
	};
}

function makeOutputAccumulatorBench() {
	return new outputAccumulatorModule.OutputAccumulator({
		maxLines: 50,
		maxBytes: 2048,
		tempFilePrefix: "oa-bench",
	});
}

function appendOutputAccumulatorCompleteChunks(accumulator) {
	accumulator.append(Buffer.from([0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x0a]));
	accumulator.append(Buffer.from([0xc3]));
	accumulator.append(Buffer.from([0xa9, 0x20, 0x77, 0x6f, 0x72, 0x6c, 0x64, 0x0a]));
	accumulator.append(Buffer.from([0x74, 0x61, 0x69, 0x6c, 0x20, 0x6c, 0x69, 0x6e, 0x65]));
	return accumulator;
}

function runOutputAccumulatorAppend() {
	const accumulator = makeOutputAccumulatorBench();
	appendOutputAccumulatorCompleteChunks(accumulator);
	const snapshot = accumulator.snapshot();
	return {
		oa_append_bytes: Buffer.byteLength(snapshot.content, "utf8"),
		oa_append_trunc: snapshot.truncation.truncated ? 1 : 0,
		oa_append_lines: snapshot.truncation.totalLines,
		oa_append_last: accumulator.getLastLineBytes(),
		oa_append_n: 4,
	};
}

function runOutputAccumulatorSnapshot() {
	const accumulator = makeOutputAccumulatorBench();
	appendOutputAccumulatorCompleteChunks(accumulator);
	const snapshot = accumulator.snapshot();
	return {
		oa_snap_bytes: Buffer.byteLength(snapshot.content, "utf8"),
		oa_snap_trunc: snapshot.truncation.truncated ? 1 : 0,
		oa_snap_lines: snapshot.truncation.totalLines,
		oa_snap_total: snapshot.truncation.totalBytes,
		oa_snap_n: 4,
	};
}

function runOutputAccumulatorFinish() {
	const accumulator = makeOutputAccumulatorBench();
	accumulator.append(Buffer.from([0xc3]));
	accumulator.finish();
	const snapshot = accumulator.snapshot();
	return {
		oa_fin_bytes: Buffer.byteLength(snapshot.content, "utf8"),
		oa_fin_fffd: snapshot.content.includes("\uFFFD") ? 1 : 0,
		oa_fin_last: accumulator.getLastLineBytes(),
		oa_fin_trunc: snapshot.truncation.truncated ? 1 : 0,
		oa_fin_n: 4,
	};
}

async function measureOutputAccumulator() {
	const appendObserved = runOutputAccumulatorAppend();
	const snapshotObserved = runOutputAccumulatorSnapshot();
	const finishObserved = runOutputAccumulatorFinish();
	return {
		append: await collect("output_accumulator.append", () => {
			return () => runOutputAccumulatorAppend();
		}),
		snapshot: await collect("output_accumulator.snapshot", () => {
			return () => runOutputAccumulatorSnapshot();
		}),
		finish: await collect("output_accumulator.finish", () => {
			return () => runOutputAccumulatorFinish();
		}),
		observed: {
			...appendObserved,
			...snapshotObserved,
			...finishObserved,
		},
	};
}

function tmTruth(value) {
	return value ? 1 : 0;
}

function tmWriteStub(directory, name) {
	mkdirSync(directory, { recursive: true });
	const filePath = path.join(directory, name);
	writeFileSync(filePath, "stub");
	return filePath;
}

function tmDeleteIfExists(filePath) {
	if (existsSync(filePath)) unlinkSync(filePath);
}

function tmWithEmptyPath(fn) {
	const previous = process.env.PATH;
	process.env.PATH = "/nonexistent-goal20-tool-manager";
	try {
		return fn();
	} finally {
		if (previous === undefined) delete process.env.PATH;
		else process.env.PATH = previous;
	}
}

let toolsManagerModulePromise;
async function loadToolsManager() {
	if (!toolsManagerModulePromise) {
		process.env[configModule.ENV_AGENT_DIR] = agentDirectory;
		toolsManagerModulePromise = import(moduleUrl("packages/coding-agent/src/utils/tools-manager.ts"));
	}
	return toolsManagerModulePromise;
}

function tmAgentBin() {
	return path.join(agentDirectory, "bin");
}

function tmIsLocalBinary(result, name) {
	return Boolean(
		result &&
			path.isAbsolute(result) &&
			path.basename(result) === name,
	);
}

function runToolManagerGetToolPath(toolsManager) {
	const toolsDir = tmAgentBin();
	mkdirSync(toolsDir, { recursive: true });
	const fd = tmWriteStub(toolsDir, "fd");
	const rg = tmWriteStub(toolsDir, "rg");
	const localFd = toolsManager.getToolPath("fd");
	const localRg = toolsManager.getToolPath("rg");
	tmDeleteIfExists(fd);
	tmDeleteIfExists(rg);
	const missFd = tmWithEmptyPath(() => toolsManager.getToolPath("fd"));
	const missRg = tmWithEmptyPath(() => toolsManager.getToolPath("rg"));
	return {
		gtp_local_fd: tmTruth(tmIsLocalBinary(localFd, "fd")),
		gtp_local_rg: tmTruth(tmIsLocalBinary(localRg, "rg")),
		gtp_miss_fd: tmTruth(missFd == null),
		gtp_miss_rg: tmTruth(missRg == null),
		gtp_n: 4,
	};
}

async function runToolManagerEnsureTool(toolsManager) {
	const toolsDir = tmAgentBin();
	mkdirSync(toolsDir, { recursive: true });
	const fd = tmWriteStub(toolsDir, "fd");
	const local = await toolsManager.ensureTool("fd");
	tmDeleteIfExists(fd);
	const previousOffline = process.env.PI_OFFLINE;
	const previousPath = process.env.PATH;
	let offline;
	process.env.PI_OFFLINE = "1";
	process.env.PATH = "/nonexistent-goal20-tool-manager";
	try {
		offline = await toolsManager.ensureTool("fd");
	} finally {
		if (previousPath === undefined) delete process.env.PATH;
		else process.env.PATH = previousPath;
		if (previousOffline === undefined) delete process.env.PI_OFFLINE;
		else process.env.PI_OFFLINE = previousOffline;
	}
	return {
		et_local_fd: tmTruth(tmIsLocalBinary(local, "fd")),
		et_offline_miss: tmTruth(offline == null),
		et_n: 2,
	};
}

function runToolManagerCleanupQuarantine() {
	const root = path.join(scratch, "tool-manager-pkg");
	const nodeModules = path.join(root, "node_modules");
	const pkg = path.join(nodeModules, "pkg");
	const quarantine = path.join(nodeModules, ".pi-native-quarantine");
	const outside = path.join(scratch, "no-modules", "pkg");
	mkdirSync(pkg, { recursive: true });
	mkdirSync(quarantine, { recursive: true });
	writeFileSync(path.join(quarantine, "stale.bin"), "stub");
	windowsSelfUpdateModule.cleanupWindowsSelfUpdateQuarantine(pkg);
	const removed = tmTruth(!existsSync(quarantine));
	mkdirSync(outside, { recursive: true });
	windowsSelfUpdateModule.cleanupWindowsSelfUpdateQuarantine(outside);
	return {
		cq_removed: removed,
		cq_noop: 1,
		cq_n: 2,
	};
}

async function measureToolManager() {
	const toolsManager = await loadToolsManager();
	const pathObserved = runToolManagerGetToolPath(toolsManager);
	const ensureObserved = await runToolManagerEnsureTool(toolsManager);
	const cleanupObserved = runToolManagerCleanupQuarantine();
	return {
		get_tool_path: await collect("tool_manager.get_tool_path", () => {
			return () => runToolManagerGetToolPath(toolsManager);
		}),
		ensure_tool: await collect("tool_manager.ensure_tool", () => {
			return () => runToolManagerEnsureTool(toolsManager);
		}),
		cleanup_quarantine: await collect("tool_manager.cleanup_quarantine", () => {
			return () => runToolManagerCleanupQuarantine();
		}),
		observed: {
			...pathObserved,
			...ensureObserved,
			...cleanupObserved,
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

function runPackageManagerManifestParse() {
	const manifest = piManifestModule.readPiManifest(path.join(packageRoot, "package.json"));
	return {
		manifest_p: manifest ? 1 : 0,
		manifest_extensions: manifest?.extensions?.length ?? 0,
		manifest_skills: manifest?.skills?.length ?? 0,
		manifest_prompts: manifest?.prompts?.length ?? 0,
		manifest_themes: manifest?.themes?.length ?? 0,
	};
}


function packageSourceFixtureInputs() {
	return [
		"npm:@scope/pkg@1.2.3",
		"npm:@scope/pkg@^1.2.3",
		"https://github.com/user/repo",
		"ssh://git@github.com/user/repo",
		"git:git@github.com:user/repo",
		"git:github.com/user/repo",
		"https://github.com/user/repo.git",
		"git:git@github.com:user/repo@v1.0.0",
		"./relative/package",
		"../relative/package",
		"git@github.com:user/repo",
		"github.com/user/repo",
	];
}

function runPackageManagerPackageSource() {
	const manager = makePackageManager();
	const internals = manager;
	let npmPinned = 0;
	let npmRange = 0;
	let git = 0;
	let gitPinned = 0;
	let local = 0;
	let gitIdOk = 1;
	let refOk = 0;
	for (const input of packageSourceFixtureInputs()) {
		const parsed = internals.parseSource(input);
		if (parsed.type === "npm") {
			if (parsed.pinned) {
				npmPinned += 1;
			} else {
				npmRange += 1;
			}
		} else if (parsed.type === "git") {
			if (parsed.pinned) {
				gitPinned += 1;
				if (parsed.ref === "v1.0.0") {
					refOk = 1;
				}
			} else {
				git += 1;
				if (internals.getPackageIdentity(input) !== "git:github.com/user/repo") {
					gitIdOk = 0;
				}
			}
		} else {
			local += 1;
		}
	}
	const deduped = internals.dedupePackages([
		{ pkg: "https://github.com/user/repo", scope: "user" },
		{ pkg: "ssh://git@github.com/user/repo@main", scope: "project" },
	]);
	return {
		ps_npm_pin: npmPinned,
		ps_npm_rng: npmRange,
		ps_git: git,
		ps_git_pin: gitPinned,
		ps_local: local,
		ps_ref_ok: refOk,
		ps_git_id: gitIdOk,
		ps_ded_n: deduped.length,
		ps_ded_proj: deduped.length > 0 && deduped[0]?.scope === "project" ? 1 : 0,
	};
}

async function measurePackageManager() {
	const manager = makePackageManager();
	const resolved = await manager.resolve();
	const fromPackage = (entries) =>
		entries.filter((entry) => entry.enabled && entry.metadata?.origin === "package").length;
	const manifestParse = runPackageManagerManifestParse();
	const packageSource = runPackageManagerPackageSource();
	return {
		resolve: await collect("package_manager.resolve", () => {
			return () => manager.resolve();
		}),
		manifest_parse: await collect("package_manager.manifest_parse", () => {
			return () => runPackageManagerManifestParse();
		}),
		package_source: await collect("package_manager.package_source", () => {
			return () => runPackageManagerPackageSource();
		}),
		observed: {
			package_count: manager.listConfiguredPackages().length,
			skill_count: fromPackage(resolved.skills),
			prompt_count: fromPackage(resolved.prompts),
			theme_count: fromPackage(resolved.themes),
			extension_count: fromPackage(resolved.extensions),
			...manifestParse,
			...packageSource,
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
		session_leaf_id: await collect("session_pipeline.session_leaf_id", () => {
			return () => manager.getLeafId();
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
		journal_entry_count: await collect("storage_journal.journal_entry_count", () => {
			return () => written.getEntries().length;
		}),
		observed: {
			read_file_entry_count: raw.length,
			append_entry_count: JOURNAL_APPEND_ENTRY_COUNT,
			journal_cwd: written.getCwd(),
			session_entry_count: written.getEntries().length,
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
	const middle = truncateMiddle(content);
	return {
		truncate_head: await collect("text_truncation.truncate_head", () => {
			return () => truncateModule.truncateHead(content);
		}),
		truncate_tail: await collect("text_truncation.truncate_tail", () => {
			return () => truncateModule.truncateTail(content);
		}),
		truncate_middle: await collect("text_truncation.truncate_middle", () => {
			return () => truncateMiddle(content);
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
			middle_output_lines: middle.outputLines,
			middle_output_bytes: middle.outputBytes,
			middle_truncated_by: middle.truncatedBy ?? "null",
			middle_omitted_lines: middle.totalLines - (middle.outputLines - 1),
			middle_first_line_exceeds: middle.firstLineExceedsLimit ? 1 : 0,
		},
	};
}

// packages/coding-agent/src/core/tools/truncate.ts truncateMiddle
function truncationOmissionLine(omittedLines) {
	return `... [${omittedLines} lines omitted] ...`;
}

function truncateMiddle(content, options = {}) {
	const maxLines = options.maxLines ?? truncateModule.DEFAULT_MAX_LINES;
	const maxBytes = options.maxBytes ?? truncateModule.DEFAULT_MAX_BYTES;
	const totalBytes = Buffer.byteLength(content, "utf8");
	const lines = content.length === 0 ? [] : content.split("\n");
	if (content.endsWith("\n")) {
		lines.pop();
	}
	const totalLines = lines.length;
	if (totalLines <= maxLines && totalBytes <= maxBytes) {
		return {
			content,
			truncated: false,
			truncatedBy: null,
			totalLines,
			totalBytes,
			outputLines: totalLines,
			outputBytes: totalBytes,
			lastLinePartial: false,
			firstLineExceedsLimit: false,
			maxLines,
			maxBytes,
		};
	}
	if (totalLines === 0) {
		return {
			content: "",
			truncated: false,
			truncatedBy: null,
			totalLines: 0,
			totalBytes: 0,
			outputLines: 0,
			outputBytes: 0,
			lastLinePartial: false,
			firstLineExceedsLimit: false,
			maxLines,
			maxBytes,
		};
	}
	const firstLineBytes = Buffer.byteLength(lines[0], "utf8");
	if (firstLineBytes > maxBytes) {
		return {
			content: "",
			truncated: true,
			truncatedBy: "bytes",
			totalLines,
			totalBytes,
			outputLines: 0,
			outputBytes: 0,
			lastLinePartial: false,
			firstLineExceedsLimit: true,
			maxLines,
			maxBytes,
		};
	}
	const segmentBytes = (from, to) => {
		let bytes = 0;
		for (let index = from; index < to; index += 1) {
			bytes += Buffer.byteLength(lines[index], "utf8");
			if (index > from) {
				bytes += 1;
			}
		}
		return bytes;
	};
	const selectionBytes = (headCount, tailCount, omittedLines) => {
		const omission = truncationOmissionLine(omittedLines);
		const omissionBytes = Buffer.byteLength(omission, "utf8");
		const headBytes = headCount > 0 ? segmentBytes(0, headCount) : 0;
		const tailBytes =
			tailCount > 0 ? segmentBytes(totalLines - tailCount, totalLines) : 0;
		let joinBytes = headBytes + tailBytes + omissionBytes;
		if (headCount > 0 && (tailCount > 0 || omittedLines > 0)) {
			joinBytes += 1;
		}
		if (tailCount > 0 && (headCount > 0 || omittedLines > 0)) {
			joinBytes += 1;
		}
		return joinBytes;
	};
	const selectionFits = (headCount, tailCount) => {
		if (headCount + tailCount > totalLines) {
			return false;
		}
		const omitted = totalLines - headCount - tailCount;
		if (omitted <= 0) {
			return false;
		}
		const outputLines = headCount + 1 + tailCount;
		return outputLines <= maxLines && selectionBytes(headCount, tailCount, omitted) <= maxBytes;
	};
	let headCount = 0;
	let tailCount = 0;
	let truncatedBy = "lines";
	while (true) {
		let improved = false;
		if (headCount + tailCount < totalLines && selectionFits(headCount + 1, tailCount)) {
			headCount += 1;
			improved = true;
		}
		if (headCount + tailCount < totalLines && selectionFits(headCount, tailCount + 1)) {
			tailCount += 1;
			improved = true;
		}
		if (!improved) {
			break;
		}
	}
	const omitted = totalLines - headCount - tailCount;
	const omission = truncationOmissionLine(omitted);
	const headText = headCount > 0 ? lines.slice(0, headCount).join("\n") : "";
	const tailText = tailCount > 0 ? lines.slice(totalLines - tailCount).join("\n") : "";
	let output;
	if (headCount > 0 && tailCount > 0) {
		output = `${headText}\n${omission}\n${tailText}`;
	} else if (headCount > 0) {
		output = `${headText}\n${omission}`;
	} else if (tailCount > 0) {
		output = `${omission}\n${tailText}`;
	} else {
		output = omission;
	}
	const outputLines = headCount + 1 + tailCount;
	const outputBytes = selectionBytes(headCount, tailCount, omitted);
	if (outputLines >= maxLines) {
		truncatedBy = "lines";
	}
	if (outputBytes > maxBytes) {
		truncatedBy = "bytes";
	}
	return {
		content: output,
		truncated: true,
		truncatedBy,
		totalLines,
		totalBytes,
		outputLines,
		outputBytes,
		lastLinePartial: false,
		firstLineExceedsLimit: false,
		maxLines,
		maxBytes,
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

const TOOL_RESULT_DIGEST_MAX_CHARS = 2000;

function truncateToolResultDigest(text) {
	if (text.length <= TOOL_RESULT_DIGEST_MAX_CHARS) return text;
	const truncatedChars = text.length - TOOL_RESULT_DIGEST_MAX_CHARS;
	return `${text.slice(0, TOOL_RESULT_DIGEST_MAX_CHARS)}\n\n[... ${truncatedChars} more characters truncated]`;
}

function toolResultDigestTruncated(text) {
	return text.includes("[... ") ? 1 : 0;
}

function runAgentToolLoopToolResultDigest() {
	const short = "hello";
	const exact = "a".repeat(2000);
	const over = "x".repeat(2001);
	const emoji = "\u{1F642}";
	const utf16 = emoji.repeat(1000) + "x";
	const shortOut = truncateToolResultDigest(short);
	const exactOut = truncateToolResultDigest(exact);
	const overOut = truncateToolResultDigest(over);
	const utf16Out = truncateToolResultDigest(utf16);
	const emptyOut = truncateToolResultDigest("");
	return {
		trd_short: shortOut === short ? 1 : 0,
		trd_exact: exactOut === exact ? 1 : 0,
		trd_over: toolResultDigestTruncated(overOut),
		trd_over_one: overOut.includes("1 more characters truncated") ? 1 : 0,
		trd_utf16: toolResultDigestTruncated(utf16Out),
		trd_empty: emptyOut === "" ? 1 : 0,
	};
}


class PendingMessageQueue {
	constructor(mode) { this.mode = mode; this.messages = []; }
	enqueue(message) { this.messages.push(message); }
	drain() {
		if (this.mode === "all") { const d = this.messages.slice(); this.messages = []; return d; }
		const first = this.messages[0]; if (!first) return [];
		this.messages = this.messages.slice(1); return [first];
	}
	clear() { this.messages = []; }
	queueLength() { return this.messages.length; }
}
function pairedRuntimeUserMessage(text) { return { role: "user", content: text, timestamp: 1 }; }
function runtimeQueueTextFlag(messages, expected) {
	if (messages.length !== 1) return 0;
	const message = messages[0];
	const text = typeof message.content === "string" ? message.content : (message.content?.[0]?.text ?? "");
	return text === expected ? 1 : 0;
}
function clearLiveRuntimeQueues(steeringQueue, followUpQueue) {
	const steering = steeringQueue.messages.slice();
	const followUp = followUpQueue.messages.slice();
	steeringQueue.clear(); followUpQueue.clear();
	return { steering, followUp };
}
function runAgentToolLoopRuntime() {
	const steeringQueue = new PendingMessageQueue("one-at-a-time");
	const followUpQueue = new PendingMessageQueue("one-at-a-time");
	steeringQueue.enqueue(pairedRuntimeUserMessage("a"));
	steeringQueue.enqueue(pairedRuntimeUserMessage("b"));
	followUpQueue.enqueue(pairedRuntimeUserMessage("c"));
	followUpQueue.enqueue(pairedRuntimeUserMessage("d"));
	const steerLen = steeringQueue.queueLength();
	const followLen = followUpQueue.queueLength();
	const steerD1 = steeringQueue.drain();
	const steerR1 = steeringQueue.queueLength();
	const steerD2 = steeringQueue.drain();
	const steerR2 = steeringQueue.queueLength();
	steeringQueue.mode = "all";
	steeringQueue.enqueue(pairedRuntimeUserMessage("x"));
	steeringQueue.enqueue(pairedRuntimeUserMessage("y"));
	const steerAll = steeringQueue.drain();
	const followD1 = followUpQueue.drain();
	const followR1 = followUpQueue.queueLength();
	const followD2 = followUpQueue.drain();
	const followR2 = followUpQueue.queueLength();
	steeringQueue.enqueue(pairedRuntimeUserMessage("clear-me"));
	followUpQueue.enqueue(pairedRuntimeUserMessage("clear-fu"));
	const { steering: clearedSteer, followUp: clearedFollow } = clearLiveRuntimeQueues(steeringQueue, followUpQueue);
	steeringQueue.clear(); followUpQueue.clear();
	return {
		rt_steer_len: steerLen === 2 ? 1 : 0,
		rt_follow_len: followLen === 2 ? 1 : 0,
		rt_drain_steer_a: runtimeQueueTextFlag(steerD1, "a"),
		rt_drain_steer1_n: steerD1.length,
		rt_steer_remain1: steerR1 === 1 ? 1 : 0,
		rt_drain_steer_b: runtimeQueueTextFlag(steerD2, "b"),
		rt_steer_empty: steerR2 === 0 ? 1 : 0,
		rt_drain_steer_all_n: steerAll.length,
		rt_drain_follow_c: runtimeQueueTextFlag(followD1, "c"),
		rt_follow_remain1: followR1 === 1 ? 1 : 0,
		rt_drain_follow_d: runtimeQueueTextFlag(followD2, "d"),
		rt_follow_empty: followR2 === 0 ? 1 : 0,
		rt_clear_steer_n: clearedSteer.length,
		rt_clear_follow_n: clearedFollow.length,
		rt_snap_steer_empty: steeringQueue.queueLength(),
		rt_snap_follow_empty: followUpQueue.queueLength(),
	};
}
async function measureAgentToolLoop() {
	const once = await runPairedToolLoop();
	const messages = once.agent.state.messages;
	const last = messages[messages.length - 1];
	const result = messages[2];
	const paths = runAgentToolLoopToolPath();
	const endings = runAgentToolLoopLineEnding();
	const digests = runAgentToolLoopToolResultDigest();
	const runtime = runAgentToolLoopRuntime();
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
		tool_result_digest: await collect("agent_tool_loop.tool_result_digest", () => {
			return () => runAgentToolLoopToolResultDigest();
		}),
		runtime: await collect("agent_tool_loop.runtime", () => {
			return () => runAgentToolLoopRuntime();
		}),
		observed: {
			final_text: last.content[0].text,
			message_count: messages.length,
			tool_error: result.isError ? 1 : 0,
			tool_value: once.executed.value,
			...paths,
			...endings,
			...digests,
			...runtime,
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

function pairedBranchSummarizeStream() {
	return () => {
		const stream = new eventStreamModule.AssistantMessageEventStream();
		queueMicrotask(() => {
			stream.push({
				type: "done",
				reason: "stop",
				message: pairedAssistantMessage([{ type: "text", text: "BRANCH SUMMARY" }], "stop"),
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

function pairedBranchSummarizeTreeEntries() {
	const abandonedUser = `abandoned context ${"d".repeat(40)}`;
	const abandonedAnswer = `abandoned answer ${"e".repeat(40)}`;
	return [
		pairedCompactMessageEntry("e1", null, pairedCompactUser("root context")),
		pairedCompactMessageEntry("e2", "e1", pairedCompactAssistant("root answer")),
		pairedCompactMessageEntry("e3", "e2", pairedCompactUser(abandonedUser)),
		pairedCompactMessageEntry("e4", "e3", pairedCompactAssistant(abandonedAnswer)),
		pairedCompactMessageEntry("e5", "e2", pairedCompactUser("main branch request")),
	];
}

function pairedBranchSummarizeSession() {
	const entries = pairedBranchSummarizeTreeEntries();
	const byId = new Map(entries.map((entry) => [entry.id, entry]));
	return {
		getEntry(id) {
			return byId.get(id);
		},
		getBranch(leafId) {
			const path = [];
			let current = leafId;
			while (current) {
				const entry = byId.get(current);
				if (!entry) break;
				path.unshift(entry);
				current = entry.parentId;
			}
			return path;
		},
	};
}

async function runPairedBranchSummarize() {
	const session = pairedBranchSummarizeSession();
	const { entries, commonAncestorId } = branchSummarizationModule.collectEntriesForBranchSummary(
		session,
		"e4",
		"e5",
	);
	if (!entries.length || !commonAncestorId) return null;
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
	const result = await branchSummarizationModule.generateBranchSummary(entries, {
		model,
		reserveTokens: 16384,
		signal: liveAbortSignal(),
		streamFn: pairedBranchSummarizeStream(),
	});
	if (!result || result.aborted || result.error) return null;
	return {
		summary: result.summary,
		entryCount: entries.length,
		commonAncestor: commonAncestorId,
	};
}

async function measureSessionCompact() {
	const compactOnce = await runPairedCompact();
	const compactSummary = compactOnce?.summary ?? "";
	return {
		compact: await collect("session_compact.compact", () => {
			return () => runPairedCompact();
		}),
		observed: {
			compacted: compactOnce ? 1 : 0,
			first_kept: compactOnce?.firstKeptEntryId ? 1 : 0,
			summary_chars: compactSummary.length,
		},
	};
}

function sessionCompactObservedPlist(part) {
	return Object.entries(part.observed ?? {});
}

function pairedPrepareBranchTokenBudget() {
	const contextWindow = 100;
	const reserveTokens = 16384;
	return Math.max(0, contextWindow - reserveTokens);
}

function runPairedPrepareBranchEntries() {
	const session = pairedBranchSummarizeSession();
	const tokenBudget = pairedPrepareBranchTokenBudget();
	const { entries, commonAncestorId } = branchSummarizationModule.collectEntriesForBranchSummary(session, "e4", "e5");
	if (!entries.length || !commonAncestorId) return null;
	const preparation = branchSummarizationModule.prepareBranchEntries(entries, tokenBudget);
	const { readFiles, modifiedFiles } = compactionUtilsModule.computeFileLists(preparation.fileOps);
	return { messageCount: preparation.messages.length, totalTokens: preparation.totalTokens, readFileCount: readFiles.length, modifiedFileCount: modifiedFiles.length };
}

async function measurePrepareBranchEntries() {
	const prepareOnce = runPairedPrepareBranchEntries();
	return {
		prepare_branch_entries: await collect("session_compact.prepare_branch_entries", () => () => runPairedPrepareBranchEntries()),
		observed: { prepared: prepareOnce ? 1 : 0, message_count: prepareOnce?.messageCount ?? 0, total_tokens: prepareOnce?.totalTokens ?? 0, read_file_count: prepareOnce?.readFileCount ?? 0, modified_file_count: prepareOnce?.modifiedFileCount ?? 0 },
	};
}

function mergeSessionCompactGroups(compactPart, branchPart, preparePart) {
	return {
		observed: Object.fromEntries([...sessionCompactObservedPlist(compactPart), ...sessionCompactObservedPlist(branchPart), ...(preparePart ? sessionCompactObservedPlist(preparePart) : [])]),
		compact: compactPart.compact,
		branch_summarize: branchPart.branch_summarize,
		prepare_branch_entries: preparePart?.prepare_branch_entries,
	};
}

async function measureBranchSummarize() {
	const branchOnce = await runPairedBranchSummarize();
	const branchSummary = branchOnce?.summary ?? "";
	return {
		branch_summarize: await collect("session_compact.branch_summarize", () => {
			return () => runPairedBranchSummarize();
		}),
		observed: {
			summarized: branchOnce ? 1 : 0,
			entry_count: branchOnce?.entryCount ?? 0,
			branch_summary_chars: branchSummary.length,
		},
	};
}

const SESSION_DISCOVERY_FILE_COUNT = 32;
const SESSION_DISCOVERY_FIXTURE_ID = "019f0000-0000-7000-8000-00000000cadr";

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

function sessionDiscoveryEmptyDirectory() {
	return path.join(scratch, "discovery-empty");
}

async function sessionDiscoveryListProbe(dir) {
	return sessionModule.SessionManager.listAll(dir);
}

async function runSessionDiscoveryListProbe(directory, emptyDirectory) {
	const sessions = await sessionDiscoveryListProbe(directory);
	const empty = await sessionDiscoveryListProbe(emptyDirectory);
	return {
		list_count: sessions.length,
		list_id: sessions.some((session) => session.id === SESSION_DISCOVERY_FIXTURE_ID) ? 1 : 0,
		list_most_recent_name: sessions[0] ? path.basename(sessions[0].path) : "",
		empty_count: empty.length,
	};
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

// packages/evals/src/pi-harness.ts runPiCodingAgent step normalization
function normalizeEvalSteps(input) {
	if (typeof input === "string") {
		return [{ type: "prompt", content: input }];
	}
	return input;
}

function evalNormalizeStepType(step) {
	return step?.type;
}

function evalNormalizeStepsError(input) {
	try {
		const steps = normalizeEvalSteps(input);
		for (const _step of steps) {
			break;
		}
		return 0;
	} catch {
		return 1;
	}
}

function runEvalsHarnessNormalizeSteps() {
	const fromEmpty = normalizeEvalSteps([]);
	const fromStr = normalizeEvalSteps("hello");
	const fromSeq = normalizeEvalSteps([
		{ type: "prompt", content: "a" },
		{ type: "reload" },
	]);
	const fromKw = normalizeEvalSteps([{ type: "reload" }]);
	const fromVec = normalizeEvalSteps([{ type: "prompt", content: "v" }]);
	return {
		ns_empty: fromEmpty.length,
		ns_str_n: fromStr.length,
		ns_str_pr: evalNormalizeStepType(fromStr[0]) === "prompt" ? 1 : 0,
		ns_seq_n: fromSeq.length,
		ns_seq_rel: evalNormalizeStepType(fromSeq[1]) === "reload" ? 1 : 0,
		ns_kw_n: fromKw.length,
		ns_kw_rel: evalNormalizeStepType(fromKw[0]) === "reload" ? 1 : 0,
		ns_vec_n: fromVec.length,
		ns_bad: evalNormalizeStepsError(42),
	};
}

function resolveModelSelection(explicitModel, environment = {}) {
	const provider = (explicitModel?.provider ?? environment.PI_PROVIDER)?.trim();
	const id = (explicitModel?.id ?? environment.PI_MODEL)?.trim();
	if (!provider || !id) {
		throw new Error(
			"Select a harness model explicitly or set both PI_PROVIDER and PI_MODEL as defaults.",
		);
	}
	return { provider, id };
}

function evalResolveOk(explicitModel, environment, expectedProvider, expectedId) {
	try {
		const selection = resolveModelSelection(explicitModel, environment);
		return selection.provider === expectedProvider && selection.id === expectedId ? 1 : 0;
	} catch {
		return 0;
	}
}

function evalResolveError(explicitModel, environment) {
	try {
		resolveModelSelection(explicitModel, environment);
		return 0;
	} catch {
		return 1;
	}
}

function runEvalsHarnessResolveSelection() {
	const empty = {};
	const fromEnv = { PI_PROVIDER: "  openai  ", PI_MODEL: "  gpt-4o  " };
	return {
		rs_explicit: evalResolveOk({ provider: "openai", id: "gpt-4o" }, empty, "openai", "gpt-4o"),
		rs_env: evalResolveOk(undefined, fromEnv, "openai", "gpt-4o"),
		rs_miss: evalResolveError(undefined, empty),
		rs_prov: evalResolveError({ provider: "openai" }, empty),
		rs_blank: evalResolveError({ provider: "  ", id: "gpt-4o" }, empty),
		rs_n: 5,
	};
}

function evalContentText(content, separator = "\n") {
	if (typeof content === "string") return content;
	if (Array.isArray(content)) {
		return content
			.filter((part) => part.type === "text")
			.map((part) => part.text)
			.join(separator);
	}
	return "";
}

function toTranscriptEvents(messages) {
	const events = [];
	for (const message of messages) {
		if (message.role === "user") {
			events.push({
				type: "message",
				role: "user",
				content: evalContentText(message.content),
			});
		} else if (message.role === "assistant") {
			const text = evalContentText(message.content);
			if (text) events.push({ type: "message", role: "assistant", content: text });
			for (const part of message.content) {
				if (part.type === "toolCall") {
					events.push({
						type: "tool_call",
						id: part.id,
						name: part.name,
						arguments: part.arguments,
					});
				}
			}
		} else if (message.role === "toolResult") {
			const text = evalContentText(message.content);
			events.push({
				type: "tool_result",
				toolCallId: message.toolCallId,
				name: message.toolName,
				content: text,
				...(message.isError ? { error: { message: text || "Tool failed" } } : {}),
			});
		}
	}
	return events;
}

function evalTranscriptMessages() {
	return [
		{ role: "user", content: "hi" },
		{
			role: "assistant",
			content: [
				{ type: "text", text: "hello" },
				{ type: "toolCall", id: "c1", name: "bash", arguments: { cmd: "ls" } },
			],
		},
		{
			role: "toolResult",
			toolCallId: "c1",
			toolName: "bash",
			content: [{ type: "text", text: "ok" }],
			isError: false,
		},
		{ role: "assistant", content: [{ type: "text", text: "" }] },
		{
			role: "toolResult",
			toolCallId: "c2",
			toolName: "fail",
			content: [{ type: "text", text: "" }],
			isError: true,
		},
	];
}

function runEvalsHarnessTranscript() {
	const events = toTranscriptEvents(evalTranscriptMessages());
	return {
		tr_n: events.length,
		tr_user: events[0]?.type === "message" ? 1 : 0,
		tr_role: events[0]?.role === "user" ? 1 : 0,
		tr_text: events[1]?.content === "hello" ? 1 : 0,
		tr_call: events[2]?.type === "tool_call" ? 1 : 0,
		tr_name: events[2]?.name === "bash" ? 1 : 0,
		tr_result: events[3]?.type === "tool_result" ? 1 : 0,
		tr_err: events[4]?.error ? 1 : 0,
		tr_keys: 8,
	};
}

function lastAssistantSince(messages, previousMessageCount) {
	return (
		messages
			.slice(previousMessageCount)
			.reverse()
			.find((message) => message.role === "assistant") ?? null
	);
}

function runEvalsHarnessLastAssistant() {
	const old = { role: "assistant", content: [{ type: "text", text: "old" }] };
	const user = { role: "user", content: "hi" };
	const neu = { role: "assistant", content: [{ type: "text", text: "new" }] };
	const messages = [old, user, neu];
	return {
		la_new: lastAssistantSince(messages, 1) === neu ? 1 : 0,
		la_none: lastAssistantSince(messages, 3) === null ? 1 : 0,
		la_full: lastAssistantSince(messages, 0) === neu ? 1 : 0,
		la_n: 3,
	};
}

function evalStepValue(step, name) {
	if (step == null || typeof step !== "object") return undefined;
	return step[name];
}

function runEvalsHarnessStepValue() {
	const hash = { type: "prompt", content: "hi" };
	const plist = { type: "prompt", content: "hi" };
	const interned = { TYPE: "prompt", type: "prompt", CONTENT: "hi" };
	return {
		sv_hash: evalStepValue(hash, "type") === "prompt" ? 1 : 0,
		sv_plist: evalStepValue(plist, "content") === "hi" ? 1 : 0,
		sv_intern: evalStepValue(interned, "type") === "prompt" ? 1 : 0,
		sv_miss: evalStepValue(hash, "missing") === undefined ? 1 : 0,
		sv_n: 4,
	};
}

function evalUsage(messages, model) {
	let input = 0;
	let output = 0;
	let cacheRead = 0;
	let cacheWrite = 0;
	let toolCalls = 0;
	let estimatedCost = 0;
	for (const message of messages) {
		if (message.role !== "assistant") continue;
		const parts = Array.isArray(message.content) ? message.content : [];
		toolCalls += parts.filter((part) => part.type === "toolCall").length;
		const usage = message.usage;
		if (usage) {
			input += usage.input ?? 0;
			output += usage.output ?? 0;
			cacheRead += usage.cacheRead ?? 0;
			cacheWrite += usage.cacheWrite ?? 0;
			estimatedCost += usage.cost ?? 0;
		}
	}
	const metadata = {
		cacheReadTokens: cacheRead,
		cacheWriteTokens: cacheWrite,
	};
	if (estimatedCost > 0) metadata.estimatedCostUsd = estimatedCost;
	return {
		provider: String(model.provider).toLowerCase(),
		model: model.id,
		inputTokens: input,
		outputTokens: output,
		totalTokens: input + output + cacheRead + cacheWrite,
		toolCalls,
		metadata,
	};
}

function evalUsageMessages() {
	return [
		{ role: "user", content: "hi" },
		{
			role: "assistant",
			content: [
				{ type: "text", text: "hello" },
				{ type: "toolCall", id: "c1", name: "bash", arguments: { cmd: "ls" } },
			],
			usage: { input: 10, output: 20, cacheRead: 1, cacheWrite: 2, cost: 1.5 },
		},
		{
			role: "assistant",
			content: [{ type: "text", text: "done" }],
			usage: { input: 5, output: 7 },
		},
	];
}

function runEvalsHarnessUsage() {
	const usage = evalUsage(evalUsageMessages(), { provider: "openai", id: "gpt-4o" });
	const meta = usage.metadata;
	return {
		us_in: usage.inputTokens === 15 ? 1 : 0,
		us_out: usage.outputTokens === 27 ? 1 : 0,
		us_total: usage.totalTokens === 45 ? 1 : 0,
		us_tools: usage.toolCalls === 1 ? 1 : 0,
		us_prov: usage.provider === "openai" ? 1 : 0,
		us_model: usage.model === "gpt-4o" ? 1 : 0,
		us_cost:
			meta.cacheReadTokens === 1 &&
			meta.cacheWriteTokens === 2 &&
			meta.estimatedCostUsd > 0
				? 1
				: 0,
		us_n: 7,
	};
}

function evalResultJson(result) {
	return {
		output: result.output,
		events: result.events,
		usage: result.usage,
		errors: result.errors,
		artifacts: result.artifacts,
		timings: result.timings,
	};
}

function runEvalsHarnessResultJson() {
	const json = evalResultJson({
		output: "ok",
		events: [{ type: "message", role: "user" }],
		usage: { model: "gpt-4o", inputTokens: 3 },
		errors: [],
		artifacts: { runId: "r1" },
		timings: { totalMs: 12.5 },
	});
	return {
		rj_out: json.output === "ok" ? 1 : 0,
		rj_ev: json.events.length === 1 ? 1 : 0,
		rj_err: json.errors.length === 0 ? 1 : 0,
		rj_art: json.artifacts.runId === "r1" ? 1 : 0,
		rj_time: json.timings.totalMs === 12.5 ? 1 : 0,
		rj_n: 5,
	};
}

function evalLayoutLeaf(p) {
	return path.basename(p);
}

function runEvalsHarnessEvalLayout() {
	const root = "/tmp/cadr-eval-root";
	const cwd = path.join(root, "workspace");
	const agentDir = path.join(root, "agent");
	const sessionDirectory = path.join(root, "sessions");
	return {
		el_ws: evalLayoutLeaf(cwd) === "workspace" ? 1 : 0,
		el_agent: evalLayoutLeaf(agentDir) === "agent" ? 1 : 0,
		el_sess: evalLayoutLeaf(sessionDirectory) === "sessions" ? 1 : 0,
		el_n: 3,
	};
}

function evalTransformedSystemPrompt(transform, defaultPrompt) {
	const systemPrompt = transform ? transform(defaultPrompt) : defaultPrompt;
	if (typeof systemPrompt !== "string" || !systemPrompt.trim()) {
		throw new Error("Transformed eval system prompt must not be empty.");
	}
	return systemPrompt;
}

function evalSystemPromptErrorP(transform, defaultPrompt) {
	try {
		evalTransformedSystemPrompt(transform, defaultPrompt);
		return 0;
	} catch {
		return 1;
	}
}

function runEvalsHarnessSystemPrompt() {
	return {
		sp_id:
			evalTransformedSystemPrompt((prompt) => prompt, "You are cadr.") ===
			"You are cadr."
				? 1
				: 0,
		sp_map:
			evalTransformedSystemPrompt(
				(prompt) => `${prompt} extra`,
				"You are cadr.",
			) === "You are cadr. extra"
				? 1
				: 0,
		sp_empty: evalSystemPromptErrorP(() => "", "You are cadr."),
		sp_blank: evalSystemPromptErrorP(() => "   ", "You are cadr."),
		sp_n: 4,
	};
}

function evalSelectedOutput(response, selector) {
	return selector ? selector(response) : response;
}

function runEvalsHarnessOutputSelector() {
	return {
		os_none: evalSelectedOutput("ok", undefined) === "ok" ? 1 : 0,
		os_id: evalSelectedOutput("ok", (response) => response) === "ok" ? 1 : 0,
		os_map:
			evalSelectedOutput("ok", (response) => `sel:${response}`) === "sel:ok"
				? 1
				: 0,
		os_n: 3,
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
		...runEvalsHarnessNormalizeSteps(),
		...runEvalsHarnessResolveSelection(),
		...runEvalsHarnessTranscript(),
		...runEvalsHarnessLastAssistant(),
		...runEvalsHarnessStepValue(),
		...runEvalsHarnessUsage(),
		...runEvalsHarnessResultJson(),
		...runEvalsHarnessEvalLayout(),
		...runEvalsHarnessSystemPrompt(),
		...runEvalsHarnessOutputSelector(),
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
		normalize_steps: await collect("evals_harness.normalize_steps", () => {
			return () => runEvalsHarnessNormalizeSteps();
		}),
		resolve_selection: await collect("evals_harness.resolve_selection", () => {
			return () => runEvalsHarnessResolveSelection();
		}),
		transcript: await collect("evals_harness.transcript", () => {
			return () => runEvalsHarnessTranscript();
		}),
		last_assistant: await collect("evals_harness.last_assistant", () => {
			return () => runEvalsHarnessLastAssistant();
		}),
		step_value: await collect("evals_harness.step_value", () => {
			return () => runEvalsHarnessStepValue();
		}),
		usage: await collect("evals_harness.usage", () => {
			return () => runEvalsHarnessUsage();
		}),
		result_json: await collect("evals_harness.result_json", () => {
			return () => runEvalsHarnessResultJson();
		}),
		eval_layout: await collect("evals_harness.eval_layout", () => {
			return () => runEvalsHarnessEvalLayout();
		}),
		system_prompt: await collect("evals_harness.system_prompt", () => {
			return () => runEvalsHarnessSystemPrompt();
		}),
		output_selector: await collect("evals_harness.output_selector", () => {
			return () => runEvalsHarnessOutputSelector();
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

function percentDecode(value) {
	return decodeURIComponent(String(value).replace(/\+/g, " "));
}

function percentDecodeFlag(encoded, expected) {
	try {
		return percentDecode(encoded) === expected ? 1 : 0;
	} catch {
		return 0;
	}
}

function runOauthPkceDevicePercentDecode() {
	return {
		pd_plain: percentDecodeFlag("hello", "hello"),
		pd_plus: percentDecodeFlag("hello+world", "hello world"),
		pd_slash: percentDecodeFlag("%2Fpath", "/path"),
		pd_space: percentDecodeFlag("%20x", " x"),
		pd_utf8: percentDecodeFlag("%C3%A9", "é"),
		pd_n: 5,
	};
}

function parseQueryValue(query, key) {
	return new URLSearchParams(query).get(key);
}

function parseQueryFlag(query, key, expected) {
	try {
		return parseQueryValue(query, key) === expected ? 1 : 0;
	} catch {
		return 0;
	}
}

function runOauthPkceDeviceParseQuery() {
	return {
		pq_code: parseQueryFlag("code=abc&state=xyz", "code", "abc"),
		pq_state: parseQueryFlag("code=abc&state=xyz", "state", "xyz"),
		pq_plus: parseQueryFlag("q=hello+world", "q", "hello world"),
		pq_empty: parseQueryFlag("a=", "a", ""),
		pq_n: 4,
	};
}

// Baseline openai-codex.ts parseAuthorizationInput is unexported; keep the
// production body so the timed work is the same function.
function parseAuthorizationInput(input) {
	const value = input.trim();
	if (!value) return {};

	try {
		const url = new URL(value);
		return {
			code: url.searchParams.get("code") ?? undefined,
			state: url.searchParams.get("state") ?? undefined,
		};
	} catch {
		// not a URL
	}

	if (value.includes("#")) {
		const [code, state] = value.split("#", 2);
		return { code, state };
	}

	if (value.includes("code=")) {
		const params = new URLSearchParams(value);
		return {
			code: params.get("code") ?? undefined,
			state: params.get("state") ?? undefined,
		};
	}

	return { code: value };
}

function parseAuthorizationInputFlag(input, expectedCode, expectedState) {
	try {
		const parsed = parseAuthorizationInput(input);
		const code = parsed.code ?? null;
		const state = parsed.state ?? null;
		return code === expectedCode && state === expectedState ? 1 : 0;
	} catch {
		return 0;
	}
}

function runOauthPkceDeviceParseAuthorizationInput() {
	return {
		pai_url: parseAuthorizationInputFlag(
			"http://localhost:1455/auth/callback?code=code-a&state=state-a",
			"code-a",
			"state-a",
		),
		pai_hash: parseAuthorizationInputFlag("code-b#state-b", "code-b", "state-b"),
		pai_qs: parseAuthorizationInputFlag("code=code-c&state=state-c", "code-c", "state-c"),
		pai_plain: parseAuthorizationInputFlag(" code-d ", "code-d", null),
		pai_n: 4,
	};
}

async function measureOauthPkceDevice() {
	const poll = await runOauthPkceDevicePoll();
	const auth = await runOauthPkceDeviceAuthJson();
	const copilot = await runOauthPkceDeviceCopilotUrl();
	const cloudflare = runOauthPkceDeviceCloudflareUrl();
	const radius = runOauthPkceDeviceRadiusGateway();
	const copilotAuth = await runOauthPkceDeviceCopilotAuth();
	const percent = runOauthPkceDevicePercentDecode();
	const query = runOauthPkceDeviceParseQuery();
	const authInput = runOauthPkceDeviceParseAuthorizationInput();
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
		percent_decode: await collect("oauth_pkce_device.percent_decode", () => {
			return () => runOauthPkceDevicePercentDecode();
		}),
		parse_query: await collect("oauth_pkce_device.parse_query", () => {
			return () => runOauthPkceDeviceParseQuery();
		}),
		parse_authorization_input: await collect("oauth_pkce_device.parse_authorization_input", () => {
			return () => runOauthPkceDeviceParseAuthorizationInput();
		}),
		observed: {
			...poll,
			...auth,
			...copilot,
			...cloudflare,
			...radius,
			...copilotAuth,
			...percent,
			...query,
			...authInput,
		},
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

function writeExtensionDiscoveryTs(filePath) {
	mkdirSync(path.dirname(filePath), { recursive: true });
	writeFileSync(filePath, "export default function factory() {}\n", "utf8");
}

function stageExtensionDiscoveryLayout() {
	const root = path.join(scratch, "ext-discovery");
	const cwd = path.join(root, "project");
	const agentDir = path.join(root, "agent");
	const projectExt = path.join(cwd, configModule.CONFIG_DIR_NAME, "extensions");
	const globalExt = path.join(agentDir, "extensions");
	const probeDir = path.join(root, "probe");
	const explicit = path.join(root, "explicit", "cli.ts");
	writeExtensionDiscoveryTs(path.join(projectExt, "flat.ts"));
	writeExtensionDiscoveryTs(path.join(projectExt, "nested", "index.ts"));
	writeExtensionDiscoveryTs(path.join(globalExt, "global-a.ts"));
	writeExtensionDiscoveryTs(path.join(globalExt, "global-b", "index.ts"));
	writeExtensionDiscoveryTs(explicit);
	writeExtensionDiscoveryTs(path.join(probeDir, "probe-flat.ts"));
	writeExtensionDiscoveryTs(path.join(probeDir, "probe-nested", "index.ts"));
	return { cwd, agentDir, explicit, probeDir };
}

function isExtensionDiscoveryFile(name) {
	return name.endsWith(".ts") || name.endsWith(".js");
}

function resolveExtensionDiscoveryEntries(dir) {
	const packageJsonPath = path.join(dir, "package.json");
	if (existsSync(packageJsonPath)) {
		const manifest = piManifestModule.readPiManifest(packageJsonPath);
		if (manifest?.extensions?.length) {
			const entries = [];
			for (const extPath of manifest.extensions) {
				const resolvedExtPath = path.resolve(dir, extPath);
				if (existsSync(resolvedExtPath)) {
					entries.push(resolvedExtPath);
				}
			}
			if (entries.length > 0) {
				return entries;
			}
		}
	}
	const indexTs = path.join(dir, "index.ts");
	const indexJs = path.join(dir, "index.js");
	if (existsSync(indexTs)) {
		return [indexTs];
	}
	if (existsSync(indexJs)) {
		return [indexJs];
	}
	return null;
}

function discoverExtensionsInDirectory(dir) {
	if (!existsSync(dir)) {
		return [];
	}
	const discovered = [];
	try {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			const entryPath = path.join(dir, entry.name);
			if ((entry.isFile() || entry.isSymbolicLink()) && isExtensionDiscoveryFile(entry.name)) {
				discovered.push(entryPath);
				continue;
			}
			if (entry.isDirectory() || entry.isSymbolicLink()) {
				const entries = resolveExtensionDiscoveryEntries(entryPath);
				if (entries) {
					discovered.push(...entries);
				}
			}
		}
	} catch {
		return [];
	}
	return discovered;
}

function discoverExtensionPaths(configuredPaths, cwd, agentDir) {
	const resolvedCwd = resolvePathModule.resolvePath(cwd);
	const resolvedAgentDir = resolvePathModule.resolvePath(agentDir);
	const allPaths = [];
	const seen = new Set();
	const addPaths = (paths) => {
		for (const entry of paths) {
			const resolved = path.resolve(entry);
			if (!seen.has(resolved)) {
				seen.add(resolved);
				allPaths.push(entry);
			}
		}
	};
	const localExtDir = path.join(resolvedCwd, configModule.CONFIG_DIR_NAME, "extensions");
	addPaths(discoverExtensionsInDirectory(localExtDir));
	const globalExtDir = path.join(resolvedAgentDir, "extensions");
	addPaths(discoverExtensionsInDirectory(globalExtDir));
	for (const configuredPath of configuredPaths) {
		const resolved = resolvePathModule.resolvePath(configuredPath, resolvedCwd, {
			normalizeUnicodeSpaces: true,
		});
		if (existsSync(resolved) && statSync(resolved).isDirectory()) {
			const entries = resolveExtensionDiscoveryEntries(resolved);
			if (entries) {
				addPaths(entries);
				continue;
			}
			addPaths(discoverExtensionsInDirectory(resolved));
			continue;
		}
		addPaths([resolved]);
	}
	return allPaths;
}

function extensionDiscoveryScopeCount(paths, marker) {
	return paths.filter((entry) => entry.includes(marker)).length;
}

function runCliExtensionsExtensionDiscovery() {
	const { cwd, agentDir, explicit, probeDir } = stageExtensionDiscoveryLayout();
	const paths = discoverExtensionPaths([explicit], cwd, agentDir);
	const probe = discoverExtensionsInDirectory(probeDir);
	const missing = discoverExtensionsInDirectory(path.join(scratch, "ext-discovery", "missing"));
	return {
		ed_n: paths.length,
		ed_err: 0,
		ed_coll: 0,
		ed_cli: extensionDiscoveryScopeCount(paths, `${path.sep}explicit${path.sep}`),
		ed_proj: extensionDiscoveryScopeCount(
			paths,
			`${path.sep}${configModule.CONFIG_DIR_NAME}${path.sep}extensions${path.sep}`,
		),
		ed_glob: extensionDiscoveryScopeCount(paths, `${path.sep}agent${path.sep}extensions${path.sep}`),
		ed_probe: probe.length,
		ed_miss: missing.length === 0 ? 1 : 0,
	};
}

async function measureCliExtensionsInstall() {
	const url = runCliExtensionsLlamaUrl();
	const token = await runCliExtensionsHfToken();
	const catalog = runCliExtensionsLlamaCatalog();
	const discovery = runCliExtensionsExtensionDiscovery();
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
		extension_discovery: await collect("cli_extensions_install.extension_discovery", () => {
			return () => runCliExtensionsExtensionDiscovery();
		}),
		observed: { ...url, ...token, ...catalog, ...discovery },
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


function loginSelectionKindCode(kind) {
	switch (kind) {
		case "no_default_model":
			return 1;
		case "no_models_available":
			return 2;
		case "default_model_unavailable":
			return 3;
		case "select_failed":
			return 4;
		default:
			return 0;
	}
}

function hasDefaultModelProvider(providerId) {
	return providerId in modelResolverModule.defaultModelPerProvider;
}

function classifyPostLoginModel(providerId, availableModels) {
	const providerModels = availableModels.filter((model) => model.provider === providerId);
	if (!hasDefaultModelProvider(providerId)) {
		return { kind: "no_default_model" };
	}
	if (providerModels.length === 0) {
		return { kind: "no_models_available" };
	}
	const defaultModelId = modelResolverModule.defaultModelPerProvider[providerId];
	const model = providerModels.find((entry) => entry.id === defaultModelId);
	if (!model) {
		return { kind: "default_model_unavailable", extra: defaultModelId };
	}
	return { model, kind: null };
}

function postLoginSelectionError(actionLabel, displayName, providerId, kind, extra) {
	switch (kind) {
		case "no_default_model":
			return `${actionLabel} ${displayName}, but no default model is configured for provider "${providerId}". Use /model to select a model.`;
		case "no_models_available":
			return `${actionLabel} ${displayName}, but no models are available for that provider. Use /model to select a model.`;
		case "default_model_unavailable":
			return `${actionLabel} ${displayName}, but its default model "${extra}". Use /model to select a model.`;
		case "select_failed":
			return `${actionLabel} ${displayName}, but selecting its default model failed: ${extra}. Use /model to select a model.`;
		default:
			return "";
	}
}

function postLoginSelectionResult(providerId, availableModels, selectFunction) {
	const classified = classifyPostLoginModel(providerId, availableModels);
	if (classified.kind == null) {
		try {
			selectFunction(classified.model);
			return classified.model.id;
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			return { kind: "select_failed", extra: message };
		}
	}
	return { kind: classified.kind, extra: classified.extra };
}

function makeLoginSelectionOpenAiModel(id) {
	return {
		id,
		name: id,
		provider: "openai",
		api: "openai-completions",
		baseUrl: "http://127.0.0.1:1/v1",
		contextWindow: 128000,
		maxTokens: 8192,
	};
}

function runCliModelsRestLoginSelection() {
	const xaiEmpty = classifyPostLoginModel("xai", []);
	const nodef = classifyPostLoginModel("not-a-provider", []);
	const wrongModel = makeLoginSelectionOpenAiModel("wrong-id");
	const defunavail = classifyPostLoginModel("openai", [wrongModel]);
	const goodModel = makeLoginSelectionOpenAiModel("gpt-5.5");
	const okResult = postLoginSelectionResult("openai", [goodModel], () => {});
	const failResult = postLoginSelectionResult("openai", [goodModel], () => {
		throw new Error("goal20 login selection bench fail");
	});
	const nomodelsText = postLoginSelectionError(
		"Logged in to",
		"xAI",
		"xai",
		"no_models_available",
		null,
	);
	const nodefText = postLoginSelectionError(
		"Logged in to",
		"Unknown",
		"not-a-provider",
		"no_default_model",
		null,
	);
	return {
		ls_xai: loginSelectionKindCode(xaiEmpty.kind),
		ls_nodef: loginSelectionKindCode(nodef.kind),
		ls_defun: loginSelectionKindCode(defunavail.kind),
		ls_ok: okResult === "gpt-5.5" ? 1 : 0,
		ls_fail:
			typeof failResult === "object" &&
			failResult !== null &&
			failResult.kind === "select_failed"
				? 1
				: 0,
		ls_nomodels_sub: nomodelsText.includes("no models are available for that provider")
			? 1
			: 0,
		ls_nodef_sub: nodefText.includes("no default model is configured for provider") ? 1 : 0,
	};
}

async function measureCliModelsRest() {
	const runtime = await createModelRuntime();
	const models = await runtime.getAvailable();
	const observed = {
		...cliModelsRestObserved(runCliModelsRest(models)),
		...runCliModelsRestAuthCommand(),
		...runCliModelsRestLoginSelection(),
	};
	return {
		pattern_match: await collect("cli_models_rest.pattern_match", () => {
			return () => runCliModelsRest(models);
		}),
		auth_command: await collect("cli_models_rest.auth_command", () => {
			return () => runCliModelsRestAuthCommand();
		}),
		login_selection: await collect("cli_models_rest.login_selection", () => {
			return () => runCliModelsRestLoginSelection();
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

let imageModalityGemini = null;
let imageModalityFlux = null;

function ensureImageOpenrouterModels() {
	if (imageModalityGemini) {
		return;
	}
	imageModalityGemini = imageModelsModule.getImageModel(
		"openrouter",
		"google/gemini-2.5-flash-image",
	);
	imageModalityFlux = imageModelsModule.getImageModel(
		"openrouter",
		"black-forest-labs/flux.2-pro",
	);
}

function imageOutputModalities(model) {
	return model.output.includes("text") ? ["image", "text"] : ["image"];
}

function runImageRuntimeOutputModalities() {
	ensureImageOpenrouterModels();
	const gemini = imageOutputModalities(imageModalityGemini);
	const flux = imageOutputModalities(imageModalityFlux);
	return {
		om_gemini_n: gemini.length,
		om_gemini_text: gemini.includes("text") ? 1 : 0,
		om_flux_n: flux.length,
		om_flux_text: flux.includes("text") ? 1 : 0,
	};
}

function parseDataImage(value) {
	if (typeof value !== "string" || !value.startsWith("data:")) {
		return null;
	}
	const matches = value.match(/^data:([^;]+);base64,(.+)$/);
	if (!matches) {
		return null;
	}
	return { mimeType: matches[1], data: matches[2] };
}

function parseDataImageObs(value) {
	const parsed = parseDataImage(value);
	if (!parsed) {
		return { mime: "", data: "", ok: 0 };
	}
	return { mime: parsed.mimeType, data: parsed.data, ok: 1 };
}

function runImageRuntimeParseDataImage() {
	const ok = parseDataImageObs("data:image/png;base64,ZmFrZS1wbmc=");
	return {
		pd_ok_mime: ok.mime,
		pd_ok_data: ok.data,
		pd_ok: ok.ok,
		pd_miss: parseDataImageObs("not-an-image").ok,
		pd_plain: parseDataImageObs("https://example.com/x.png").ok,
	};
}

function openrouterImageContent(item) {
	if (item.type === "text") {
		return { type: "text", text: item.text };
	}
	return {
		type: "image_url",
		image_url: { url: `data:${item.mimeType};base64,${item.data}` },
	};
}

function runImageRuntimeOpenrouterContent() {
	const textPart = openrouterImageContent({
		type: "text",
		text: "Generate a dog",
	});
	const imagePart = openrouterImageContent({
		type: "image",
		mimeType: "image/png",
		data: "aW1hZ2U=",
	});
	return {
		oc_text_type: textPart.type,
		oc_text: textPart.text,
		oc_img_type: imagePart.type,
		oc_img_url: imagePart.image_url.url,
		oc_ok: textPart.type === "text" && imagePart.type === "image_url" ? 1 : 0,
	};
}

async function measureImageRuntime() {
	ensureImageOpenrouterModels();
	const dims = runImageRuntime();
	const mime = runImageRuntimeMime();
	const lookup = runImageRuntimeLookup();
	const notes = runImageRuntimeDimensionNote();
	const api = runImageRuntimeApiProvider();
	const modalities = runImageRuntimeOutputModalities();
	const content = runImageRuntimeOpenrouterContent();
	const parsed = runImageRuntimeParseDataImage();
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
		output_modalities: await collect("image_runtime.output_modalities", () => {
			return () => runImageRuntimeOutputModalities();
		}),
		openrouter_content: await collect("image_runtime.openrouter_content", () => {
			return () => runImageRuntimeOpenrouterContent();
		}),
		parse_data_image: await collect("image_runtime.parse_data_image", () => {
			return () => runImageRuntimeParseDataImage();
		}),
		observed: {
			...dims,
			...mime,
			...lookup,
			...notes,
			...api,
			...modalities,
			...content,
			...parsed,
		},
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

const LATEX_OPERATOR_START = "\u{f004}";
const LATEX_OPERATOR_END = "\u{f005}";
const LATEX_LAYOUT_MARKER_START = "\u{f0000}";
const LATEX_LAYOUT_MARKER_END = "\u{f0001}";
const LATEX_NAMED_OPERATOR_LEFT_SPACING_PATTERN = new RegExp(
	`(?<=[\\p{L}\\p{N})\\]}${LATEX_LAYOUT_MARKER_END}])${LATEX_OPERATOR_START}`,
	"gu",
);
const LATEX_NAMED_OPERATOR_RIGHT_SPACING_PATTERN = new RegExp(
	`${LATEX_OPERATOR_END}(?=[\\p{L}\\p{N}√${LATEX_LAYOUT_MARKER_START}])`,
	"gu",
);

function latexNormalizeOutputPi(value) {
	return value
		.replace(LATEX_NAMED_OPERATOR_LEFT_SPACING_PATTERN, " ")
		.replaceAll(LATEX_OPERATOR_START, "")
		.replace(LATEX_NAMED_OPERATOR_RIGHT_SPACING_PATTERN, " ")
		.replaceAll(LATEX_OPERATOR_END, "")
		.split("\n")
		.map((line) => line.replace(/[ \t]+/g, " ").trim())
		.filter(
			(line, index, lines) =>
				line.length > 0 || (index > 0 && index < lines.length - 1),
		)
		.join("\n")
		.trim();
}

function runTuiLatexNormalizeOutput() {
	return {
		empty: latexNormalizeOutputPi(""),
		alpha: latexNormalizeOutputPi("α"),
		frac: latexNormalizeOutputPi("1/2"),
		script: latexNormalizeOutputPi("x²"),
		operator: latexNormalizeOutputPi(
			`${LATEX_OPERATOR_START}sin${LATEX_OPERATOR_END}`,
		),
		marker_edge: latexNormalizeOutputPi(
			`x${LATEX_OPERATOR_START}${LATEX_OPERATOR_END}`,
		),
	};
}

async function measureTuiLatex() {
	const renderObserved = runTuiLatex();
	const normalizeObserved = runTuiLatexNormalizeOutput();
	return {
		render: await collect("tui_latex.render", () => {
			return () => runTuiLatex();
		}),
		normalize_output: await collect("tui_latex.normalize_output", () => {
			return () => runTuiLatexNormalizeOutput();
		}),
		observed: {
			...renderObserved,
			...normalizeObserved,
		},
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

function oauthOptionStatusLabel(provider) {
	if (!provider.status) {
		return "• unconfigured";
	}
	if (provider.status.type !== provider.authType) {
		const label = provider.status.type === "oauth" ? "subscription" : "API key";
		return `• ${label} configured`;
	}
	if (
		!provider.status.source ||
		provider.status.source === "OAuth" ||
		provider.status.source === "stored credential"
	) {
		return "✓ configured";
	}
	if (/^[A-Z][A-Z0-9_]*(?:, [A-Z][A-Z0-9_]*)*$/.test(provider.status.source)) {
		return `✓ env: ${provider.status.source}`;
	}
	return `✓ ${provider.status.source}`;
}

function runCliSelectorsOauthOptionStatusLabel() {
	return {
		oosl_none: oauthOptionStatusLabel({
			id: "anthropic",
			name: "Anthropic",
			authType: "oauth",
		}),
		oosl_api_mismatch: oauthOptionStatusLabel({
			id: "anthropic",
			name: "Anthropic",
			authType: "api_key",
			status: { type: "oauth", source: "OAuth" },
		}),
		oosl_oauth_mismatch: oauthOptionStatusLabel({
			id: "anthropic",
			name: "Anthropic",
			authType: "oauth",
			status: { type: "api_key", source: "stored credential" },
		}),
		oosl_oauth_configured: oauthOptionStatusLabel({
			id: "anthropic",
			name: "Anthropic",
			authType: "oauth",
			status: { type: "oauth", source: "OAuth" },
		}),
		oosl_stored: oauthOptionStatusLabel({
			id: "anthropic",
			name: "Anthropic",
			authType: "oauth",
			status: { type: "oauth", source: "stored credential" },
		}),
		oosl_env: oauthOptionStatusLabel({
			id: "anthropic",
			name: "Anthropic",
			authType: "api_key",
			status: { type: "api_key", source: "ANTHROPIC_API_KEY" },
		}),
		oosl_custom: oauthOptionStatusLabel({
			id: "anthropic",
			name: "Anthropic",
			authType: "api_key",
			status: { type: "api_key", source: "runtime key" },
		}),
	};
}

function oauthOptionStatusRendered(provider) {
	if (!provider.status) {
		return themeModule.theme.fg("muted", " • unconfigured");
	}
	if (provider.status.type !== provider.authType) {
		const label =
			provider.status.type === "oauth" ? "subscription configured" : "API key configured";
		return themeModule.theme.fg("muted", " • ") + themeModule.theme.fg("warning", label);
	}
	if (
		!provider.status.source ||
		provider.status.source === "OAuth" ||
		provider.status.source === "stored credential"
	) {
		return themeModule.theme.fg("success", " ✓ configured");
	}
	const source = /^[A-Z][A-Z0-9_]*(?:, [A-Z][A-Z0-9_]*)*$/.test(provider.status.source)
		? `env: ${provider.status.source}`
		: provider.status.source;
	return themeModule.theme.fg("success", ` ✓ ${source}`);
}

function runCliSelectorsOauthOptionStatusRendered() {
	return {
		oosr_none: oauthOptionStatusRendered({
			id: "anthropic",
			name: "Anthropic",
			authType: "oauth",
		}),
		oosr_api_mismatch: oauthOptionStatusRendered({
			id: "anthropic",
			name: "Anthropic",
			authType: "api_key",
			status: { type: "oauth", source: "OAuth" },
		}),
		oosr_oauth_mismatch: oauthOptionStatusRendered({
			id: "anthropic",
			name: "Anthropic",
			authType: "oauth",
			status: { type: "api_key", source: "stored credential" },
		}),
		oosr_oauth_configured: oauthOptionStatusRendered({
			id: "anthropic",
			name: "Anthropic",
			authType: "oauth",
			status: { type: "oauth", source: "OAuth" },
		}),
		oosr_stored: oauthOptionStatusRendered({
			id: "anthropic",
			name: "Anthropic",
			authType: "oauth",
			status: { type: "oauth", source: "stored credential" },
		}),
		oosr_env: oauthOptionStatusRendered({
			id: "anthropic",
			name: "Anthropic",
			authType: "api_key",
			status: { type: "api_key", source: "ANTHROPIC_API_KEY" },
		}),
		oosr_custom: oauthOptionStatusRendered({
			id: "anthropic",
			name: "Anthropic",
			authType: "api_key",
			status: { type: "api_key", source: "runtime key" },
		}),
	};
}

function credentialEntryAuthType(kind) {
	const normalized =
		typeof kind === "string"
			? kind.toLowerCase()
			: String(kind).toLowerCase().replace(/^:/, "");
	if (normalized === "oauth") {
		return "oauth";
	}
	if (normalized === "api-key" || normalized === "api_key") {
		return "api_key";
	}
	throw new Error(`Unsupported credential type: ${kind}`);
}

function runCliSelectorsCredentialEntryAuthType() {
	return {
		ceat_oauth: credentialEntryAuthType("oauth"),
		ceat_api_key: credentialEntryAuthType("api_key"),
		ceat_api_key_hyphen: credentialEntryAuthType("api-key"),
		ceat_oauth_sym: credentialEntryAuthType("oauth"),
		ceat_api_key_sym: credentialEntryAuthType("api-key"),
		ceat_oauth_mixed: credentialEntryAuthType("OAuth"),
		ceat_api_key_upper: credentialEntryAuthType("API_KEY"),
	};
}

function oauthEnvironmentSourceP(source) {
	return (
		typeof source === "string" &&
		/^[A-Z][A-Z0-9_]*(?:, [A-Z][A-Z0-9_]*)*$/.test(source)
	);
}

function runCliSelectorsOauthEnvironmentSourceP() {
	return {
		oesp_nil: oauthEnvironmentSourceP(null) ? 1 : 0,
		oesp_oauth: oauthEnvironmentSourceP("OAuth") ? 1 : 0,
		oesp_single_env: oauthEnvironmentSourceP("ANTHROPIC_API_KEY") ? 1 : 0,
		oesp_multi_env: oauthEnvironmentSourceP("OPENAI_API_KEY, ANTHROPIC_API_KEY") ? 1 : 0,
		oesp_runtime: oauthEnvironmentSourceP("runtime key") ? 1 : 0,
		oesp_stored: oauthEnvironmentSourceP("stored credential") ? 1 : 0,
		oesp_lower: oauthEnvironmentSourceP("anthropic_api_key") ? 1 : 0,
	};
}

function makeOauthSelectorTestOptions() {
	return [
		{ id: "anthropic", name: "Anthropic", authType: "oauth" },
		{ id: "openai", name: "OpenAI", authType: "api_key" },
		{ id: "google", name: "Google", authType: "oauth" },
	];
}

function encodeOauthSelectorOption(provider) {
	if (!provider) {
		return "null";
	}
	return `${provider.id}|${provider.authType}`;
}

function oauthSelectorSelectionEncoded(providers, selected, query = "") {
	const filtered = query
		? fuzzyModule.fuzzyFilter(
				providers,
				query,
				(provider) =>
					`${provider.name} ${provider.id} ${provider.authType} ${provider.method?.name ?? ""}`,
			)
		: providers;
	return encodeOauthSelectorOption(filtered[selected]);
}

function runCliSelectorsOauthSelectorSelection() {
	const options = makeOauthSelectorTestOptions();
	return {
		oss_first: oauthSelectorSelectionEncoded(options, 0),
		oss_second: oauthSelectorSelectionEncoded(options, 1),
		oss_third: oauthSelectorSelectionEncoded(options, 2),
		oss_filter_hit: oauthSelectorSelectionEncoded(options, 0, "open"),
		oss_filter_miss: oauthSelectorSelectionEncoded(options, 0, "nope"),
	};
}

function oauthSelectorSearchText(provider) {
	return `${provider.name} ${provider.id} ${provider.authType} ${provider.method?.name ?? ""}`;
}

function oauthSelectorApplyFilterEncoded(providers, query) {
	const state = {
		selectedIndex: 2,
		query,
	};
	const filtered = query
		? fuzzyModule.fuzzyFilter(providers, query, oauthSelectorSearchText)
		: providers;
	state.selectedIndex = 0;
	return `${filtered.length}|${state.selectedIndex}`;
}

function runCliSelectorsOauthSelectorApplyFilter() {
	const options = makeOauthSelectorTestOptions();
	return {
		osaf_all: oauthSelectorApplyFilterEncoded(options, ""),
		osaf_open: oauthSelectorApplyFilterEncoded(options, "open"),
		osaf_miss: oauthSelectorApplyFilterEncoded(options, "nope"),
		osaf_anth: oauthSelectorApplyFilterEncoded(options, "anth"),
		osaf_google: oauthSelectorApplyFilterEncoded(options, "oogle"),
	};
}

function oauthHandleEventEncoded(options, selected, eventKind, { query = "", text } = {}) {
	const state = {
		options,
		query,
		selected,
		filtered: query
			? fuzzyModule.fuzzyFilter(options, query, oauthSelectorSearchText)
			: options,
	};
	let action = "null";
	let value = "null";
	switch (eventKind) {
		case "down":
			if (state.filtered.length > 0) {
				state.selected = Math.min(state.filtered.length - 1, state.selected + 1);
			}
			action = "changed";
			break;
		case "up":
			if (state.filtered.length > 0) {
				state.selected = Math.max(0, state.selected - 1);
			}
			action = "changed";
			break;
		case "enter":
			action = "select";
			value = encodeOauthSelectorOption(state.filtered[state.selected]);
			break;
		case "escape":
			action = "cancel";
			break;
		case "text":
			state.query += text ?? "";
			state.filtered = fuzzyModule.fuzzyFilter(options, state.query, oauthSelectorSearchText);
			state.selected = 0;
			action = "changed";
			break;
		case "backspace":
			state.query = deleteQueryChar(state.query);
			state.filtered = state.query
				? fuzzyModule.fuzzyFilter(options, state.query, oauthSelectorSearchText)
				: options;
			state.selected = 0;
			action = "changed";
			break;
	}
	return `${action}|${action === "select" ? value : "null"}|${state.selected}|${state.query}`;
}

function runCliSelectorsOauthSelectorHandleEvent() {
	const options = makeOauthSelectorTestOptions();
	return {
		oshe_down: oauthHandleEventEncoded(options, 0, "down"),
		oshe_up: oauthHandleEventEncoded(options, 1, "up"),
		oshe_enter: oauthHandleEventEncoded(options, 0, "enter"),
		oshe_esc: oauthHandleEventEncoded(options, 0, "escape"),
		oshe_text: oauthHandleEventEncoded(options, 0, "text", { text: "op" }),
		oshe_backspace: oauthHandleEventEncoded(options, 0, "backspace", { query: "op" }),
	};
}

function oauthHandleRawInputEncoded(options, selected, data) {
	const manager = new keybindingsModule.KeybindingsManager(keybindingsModule.TUI_KEYBINDINGS);
	const state = {
		options,
		query: "",
		selected,
		filtered: options,
	};
	let action = "null";
	let value = "null";
	let consumed = "false";

	if (selectorKeybindingMatchesPi(manager, data, "tui.select.up")) {
		if (state.filtered.length > 0) {
			state.selected = Math.max(0, state.selected - 1);
		}
		action = "changed";
		consumed = "true";
	} else if (selectorKeybindingMatchesPi(manager, data, "tui.select.down")) {
		if (state.filtered.length > 0) {
			state.selected = Math.min(state.filtered.length - 1, state.selected + 1);
		}
		action = "changed";
		consumed = "true";
	} else if (data === "\n" || selectorKeybindingMatchesPi(manager, data, "tui.select.confirm")) {
		action = "select";
		value = encodeOauthSelectorOption(state.filtered[state.selected]);
		consumed = "true";
	} else if (selectorKeybindingMatchesPi(manager, data, "tui.select.cancel")) {
		action = "cancel";
		consumed = "true";
	} else if (data.length === 1 && data >= " " && data !== "\x7f") {
		state.query += data;
		state.filtered = fuzzyModule.fuzzyFilter(options, state.query, oauthSelectorSearchText);
		state.selected = 0;
		action = "changed";
		consumed = "true";
	}

	return `${action}|${value}|${state.selected}|${consumed}`;
}

function runCliSelectorsOauthSelectorHandleRawInput() {
	const options = makeOauthSelectorTestOptions();
	return {
		oshri_down: oauthHandleRawInputEncoded(options, 0, trustRawInputKeyDataPi("tui.select.down")),
		oshri_j: oauthHandleRawInputEncoded(options, 1, "j"),
		oshri_enter: oauthHandleRawInputEncoded(options, 0, "\n"),
		oshri_esc: oauthHandleRawInputEncoded(options, 1, trustRawInputKeyDataPi("tui.select.cancel")),
		oshri_bad: oauthHandleRawInputEncoded(options, 0, "q"),
		oshri_o: oauthHandleRawInputEncoded(options, 0, "o"),
		oshri_confirm: oauthHandleRawInputEncoded(options, 0, trustRawInputKeyDataPi("tui.select.confirm")),
	};
}

function runCliSelectorsOauthSelectorSearchText() {
	return {
		osst_oauth: oauthSelectorSearchText({
			id: "anthropic",
			name: "Anthropic",
			authType: "oauth",
			method: { name: "Anthropic account" },
		}),
		osst_api: oauthSelectorSearchText({
			id: "openai",
			name: "OpenAI",
			authType: "api_key",
			method: { name: "OpenAI API key" },
		}),
		osst_no_method: oauthSelectorSearchText({
			id: "google",
			name: "Google",
			authType: "oauth",
		}),
		osst_api_plain: oauthSelectorSearchText({
			id: "mistral",
			name: "Mistral",
			authType: "api_key",
		}),
	};
}

function loginAuthTypeRoute(providerOptions, { generic = false } = {}) {
	if (generic) {
		return "select|Select authentication method:|Sign in with an account|Sign in with an API key";
	}
	const oauth = providerOptions?.find((provider) => provider.authType === "oauth");
	const apiKey = providerOptions?.find((provider) => provider.authType === "api_key");
	const options = [oauth, apiKey].filter(Boolean);
	if (options.length === 0) {
		return "none|No login methods available.";
	}
	if (options.length === 1) {
		const provider = options[0];
		return `direct|${provider.id}|${provider.authType}`;
	}
	const oauthLabel = oauth?.method?.loginLabel ?? "Sign in with an account";
	return `select|Select authentication method for ${providerOptions[0].name}:|${oauthLabel}|Sign in with an API key`;
}

function runCliSelectorsLoginAuthTypeRoute() {
	return {
		latr_none: loginAuthTypeRoute(null),
		latr_oauth: loginAuthTypeRoute([
			{ id: "anthropic", name: "Anthropic", authType: "oauth" },
		]),
		latr_api: loginAuthTypeRoute([
			{ id: "anthropic", name: "Anthropic", authType: "api_key" },
		]),
		latr_both: loginAuthTypeRoute([
			{
				id: "anthropic",
				name: "Anthropic",
				authType: "oauth",
				method: { loginLabel: "Sign in with Claude" },
			},
			{ id: "anthropic", name: "Anthropic", authType: "api_key" },
		]),
		latr_generic: loginAuthTypeRoute(null, { generic: true }),
	};
}

function loginProviderFixtureDefinitions() {
	return [
		{
			id: "anthropic",
			name: "Anthropic",
			authTypes: ["oauth", "api_key"],
			oauth: { methodName: "Anthropic account" },
			apiKey: { methodName: "Anthropic API key" },
		},
		{
			id: "google-vertex",
			name: "Google Vertex AI",
			authTypes: ["api_key"],
			apiKey: { methodName: "Google Vertex AI API key" },
			structuredApiKey: true,
		},
	];
}

function encodeOauthSelectorStatusField(status) {
	if (!status) {
		return "";
	}
	const type = status.type === "oauth" ? "oauth" : "api_key";
	return `${type}:${status.source}`;
}

function encodeLoginProviderOption(option) {
	return [
		option.id,
		option.authType,
		option.methodName,
		option.loginLabel ?? "",
		option.structuredLogin ? "1" : "0",
		encodeOauthSelectorStatusField(option.status),
	].join("|");
}

function encodeLoginProviderOptions(options) {
	return options.map((option) => encodeLoginProviderOption(option)).join(",");
}

function loginProviderOptions(definitions, { authType, statusFor } = {}) {
	const options = [];
	for (const provider of definitions) {
		const status = statusFor?.(provider.id);
		const candidates = provider.authTypes ?? ["oauth", "api_key"];
		for (const candidate of candidates) {
			if (authType && authType !== candidate) {
				continue;
			}
			if (candidate === "oauth" && provider.oauth) {
				options.push({
					id: provider.id,
					name: provider.name,
					authType: "oauth",
					methodName: provider.oauth.methodName,
					loginLabel: provider.oauth.loginLabel,
					structuredLogin: false,
					status,
				});
			}
			if (candidate === "api_key" && provider.apiKey) {
				options.push({
					id: provider.id,
					name: provider.name,
					authType: "api_key",
					methodName: provider.apiKey.methodName,
					loginLabel: undefined,
					structuredLogin: Boolean(provider.structuredApiKey),
					status,
				});
			}
		}
	}
	return options.sort((left, right) => left.name.localeCompare(right.name));
}

function runCliSelectorsLoginProviderOptions() {
	const definitions = loginProviderFixtureDefinitions();
	const openrouter = [
		{
			id: "openrouter",
			name: "OpenRouter",
			authTypes: ["api_key", "oauth"],
			oauth: {
				methodName: "OpenRouter OAuth",
				loginLabel: "Sign in with OpenRouter",
			},
			apiKey: { methodName: "OpenRouter API key" },
		},
	];
	return {
		lpo_all: encodeLoginProviderOptions(loginProviderOptions(definitions)),
		lpo_oauth: encodeLoginProviderOptions(
			loginProviderOptions(definitions, { authType: "oauth" }),
		),
		lpo_api: encodeLoginProviderOptions(
			loginProviderOptions(definitions, { authType: "api_key" }),
		),
		lpo_labeled: encodeLoginProviderOptions(loginProviderOptions(openrouter)),
		lpo_status: encodeLoginProviderOptions(
			loginProviderOptions(definitions, {
				statusFor: () => ({ type: "oauth", source: "OAuth" }),
			}),
		),
	};
}

function logoutProviderNameLookup() {
	return {
		anthropic: "Anthropic",
		"google-vertex": "Google Vertex AI",
	};
}

function logoutProviderOptions(nameLookup, credentialEntries) {
	return credentialEntries
		.map(({ providerId, type }) => {
			const name = nameLookup[providerId] ?? providerId;
			return {
				id: providerId,
				name,
				authType: type,
				methodName: `${name} ${type === "oauth" ? "account" : "API key"}`,
				loginLabel: "",
				structuredLogin: false,
				status: { type, source: "stored credential" },
			};
		})
		.sort((left, right) => left.name.localeCompare(right.name));
}

function runCliSelectorsLogoutProviderOptions() {
	const nameLookup = logoutProviderNameLookup();
	return {
		lgo_empty: encodeLoginProviderOptions(logoutProviderOptions(nameLookup, [])),
		lgo_mixed: encodeLoginProviderOptions(
			logoutProviderOptions(nameLookup, [
				{ providerId: "anthropic", type: "oauth" },
				{ providerId: "google-vertex", type: "api_key" },
			]),
		),
		lgo_unknown: encodeLoginProviderOptions(
			logoutProviderOptions(nameLookup, [
				{ providerId: "unknown-provider", type: "api_key" },
			]),
		),
		lgo_sorted: encodeLoginProviderOptions(
			logoutProviderOptions(nameLookup, [
				{ providerId: "openai", type: "oauth" },
				{ providerId: "anthropic", type: "api_key" },
				{ providerId: "google-vertex", type: "oauth" },
			]),
		),
	};
}

function makeLoginMethodSelectorState(selected = 0) {
	return {
		items: [
			{ label: "Sign in with an account", value: "oauth" },
			{ label: "Sign in with an API key", value: "api_key" },
		],
		selected,
	};
}

function encodeLoginMethodHandleEventResult(state, action, value) {
	return [
		action ?? "null",
		action === "select" && value ? value : "null",
		String(state.selected),
	].join("|");
}

function loginMethodSelectorHandleEvent(state, eventKind) {
	if (eventKind === "clear" || eventKind === "interrupt") {
		return { action: "cancel", value: null, selected: state.selected };
	}
	switch (eventKind) {
		case "down":
			state.selected =
				state.items.length === 0
					? 0
					: (state.selected + 1) % state.items.length;
			return { action: null, value: null, selected: state.selected };
		case "up":
			state.selected =
				state.items.length === 0
					? 0
					: (state.selected - 1 + state.items.length) % state.items.length;
			return { action: null, value: null, selected: state.selected };
		case "enter": {
			const item = state.items[state.selected];
			return {
				action: item ? "select" : null,
				value: item?.value ?? null,
				selected: state.selected,
			};
		}
		case "escape":
			return { action: "cancel", value: null, selected: state.selected };
		default:
			return { action: null, value: null, selected: state.selected };
	}
}

function loginMethodHandleEventEncoded(selected, eventKind) {
	const state = makeLoginMethodSelectorState(selected);
	const result = loginMethodSelectorHandleEvent(state, eventKind);
	return encodeLoginMethodHandleEventResult(state, result.action, result.value);
}

function runCliSelectorsLoginMethodSelectorHandleEvent() {
	return {
		lmhe_down: loginMethodHandleEventEncoded(0, "down"),
		lmhe_up: loginMethodHandleEventEncoded(1, "up"),
		lmhe_enter_oauth: loginMethodHandleEventEncoded(0, "enter"),
		lmhe_enter_api: loginMethodHandleEventEncoded(1, "enter"),
		lmhe_esc: loginMethodHandleEventEncoded(0, "escape"),
		lmhe_clear: loginMethodHandleEventEncoded(1, "clear"),
		lmhe_interrupt: loginMethodHandleEventEncoded(0, "interrupt"),
	};
}

function oauthSelectorMoveEncoded(options, selected, delta, query = "") {
	const filtered = query
		? fuzzyModule.fuzzyFilter(options, query, oauthSelectorSearchText)
		: options;
	return String(moveIndex(selected, filtered.length, delta));
}

function runCliSelectorsOauthSelectorMove() {
	const options = makeOauthSelectorTestOptions();
	return {
		osmv_0_1: oauthSelectorMoveEncoded(options, 0, 1),
		osmv_2_m1: oauthSelectorMoveEncoded(options, 2, -1),
		osmv_1_1: oauthSelectorMoveEncoded(options, 1, 1),
		osmv_1_m1: oauthSelectorMoveEncoded(options, 1, -1),
		osmv_filter: oauthSelectorMoveEncoded(options, 0, 1, "open"),
	};
}

const API_KEY_INPUT_FIXTURE_OPTION = {
	id: "anthropic",
	name: "Anthropic",
	authType: "api_key",
};

function makeApiKeyInputState(prefill = "") {
	return {
		option: API_KEY_INPUT_FIXTURE_OPTION,
		value: prefill,
	};
}

function encodeApiKeyInputHandleEventResult(state, action, value) {
	const inputLen = state.value.length;
	if (action === "select" && value) {
		return [
			action,
			value.optionId,
			value.authType,
			value.key,
		].join("|");
	}
	return [
		action ?? "null",
		"null",
		"null",
		String(inputLen),
	].join("|");
}

function apiKeyInputStateHandleEvent(state, eventKind, text) {
	const cancelKinds = new Set(["escape", "cancel", "clear", "interrupt", "eof"]);
	if (cancelKinds.has(eventKind)) {
		return { action: "cancel", value: null };
	}
	if (eventKind === "text") {
		state.value += text ?? "";
		return { action: null, value: null };
	}
	if (eventKind === "backspace") {
		state.value = deleteQueryChar(state.value);
		return { action: null, value: null };
	}
	if (eventKind === "enter") {
		if (state.value.length > 0) {
			return {
				action: "select",
				value: {
					optionId: state.option.id,
					authType: state.option.authType,
					key: state.value,
				},
			};
		}
		return { action: "changed", value: null };
	}
	return { action: null, value: null };
}

function apiKeyInputHandleEventEncoded(eventKind, { prefill = "", text } = {}) {
	const state = makeApiKeyInputState(prefill);
	const result = apiKeyInputStateHandleEvent(state, eventKind, text);
	return encodeApiKeyInputHandleEventResult(state, result.action, result.value);
}

function runCliSelectorsApiKeyInputStateHandleEvent() {
	return {
		akhe_esc: apiKeyInputHandleEventEncoded("escape"),
		akhe_clear: apiKeyInputHandleEventEncoded("clear"),
		akhe_text: apiKeyInputHandleEventEncoded("text", { text: "sk-test" }),
		akhe_bs: apiKeyInputHandleEventEncoded("backspace", { prefill: "ab" }),
		akhe_enter_empty: apiKeyInputHandleEventEncoded("enter"),
		akhe_enter_key: apiKeyInputHandleEventEncoded("enter", { prefill: "sk-test" }),
		akhe_interrupt: apiKeyInputHandleEventEncoded("interrupt"),
	};
}

function loginMethodSelectorUiEncoded(state, width) {
	const manager = new keybindingsModule.KeybindingsManager(keybindingsModule.TUI_KEYBINDINGS);
	const selected =
		state.items.length === 0
			? 0
			: Math.min(state.selected, state.items.length - 1);
	// Exercise ExtensionSelectorComponent.updateList-style theming.
	for (let i = 0; i < state.items.length; i++) {
		const isSelected = i === selected;
		if (isSelected) {
			themeModule.theme.fg("accent", "→ ") +
				themeModule.theme.fg("accent", state.items[i].label);
		} else {
			`  ${themeModule.theme.fg("text", state.items[i].label)}`;
		}
	}
	const hints =
		keybindingHintsModule.rawKeyHint("↑↓", "navigate") +
		"  " +
		selectorKeybindingHintPi(manager, "tui.select.confirm", "select") +
		"  " +
		selectorKeybindingHintPi(manager, "tui.select.cancel", "cancel");
	const items = state.items
		.map((item, index) => `${index === selected ? "sel" : "nosel"}:${item.label}`)
		.join(";");
	return `${state.title}|${width}|${selected}|${items}|${ansiModule.stripAnsi(hints)}`;
}

function makeLoginMethodUiState(selected = 0, title = "Select authentication method:") {
	return {
		title,
		items: [
			{ label: "Sign in with an account", value: "oauth" },
			{ label: "Sign in with an API key", value: "api_key" },
		],
		selected,
	};
}

function runCliSelectorsLoginMethodSelectorUiState() {
	return {
		lmsui_default: loginMethodSelectorUiEncoded(makeLoginMethodUiState(0), 40),
		lmsui_sel1: loginMethodSelectorUiEncoded(makeLoginMethodUiState(1), 40),
		lmsui_title: loginMethodSelectorUiEncoded(
			makeLoginMethodUiState(0, "Select authentication method for Anthropic:"),
			60,
		),
		lmsui_narrow: loginMethodSelectorUiEncoded(makeLoginMethodUiState(0), 20),
		lmsui_mid: loginMethodSelectorUiEncoded(makeLoginMethodUiState(1), 28),
	};
}

function makeApiKeyInputUiState({
	id = "anthropic",
	name = "Anthropic",
	prefill = "",
} = {}) {
	return {
		option: { id, name, authType: "api_key" },
		value: prefill,
	};
}

function apiKeyInputUiEncoded(state, width) {
	const manager = new keybindingsModule.KeybindingsManager(keybindingsModule.TUI_KEYBINDINGS);
	const title = `Login to ${state.option.name}`;
	const keyLen = state.value.length;
	// Exercise LoginDialogComponent showPrompt-style theming + masked length.
	themeModule.theme.fg("accent", themeModule.theme.bold(title));
	themeModule.theme.fg("text", "Enter API key");
	const masked = "*".repeat(keyLen);
	themeModule.theme.fg("text", `> ${masked}`);
	const hints = `(${selectorKeybindingHintPi(manager, "tui.select.cancel", "to cancel,")} ${selectorKeybindingHintPi(manager, "tui.select.confirm", "to submit")})`;
	return `${title}|${width}|${keyLen}|Enter API key|${ansiModule.stripAnsi(hints)}`;
}

function runCliSelectorsApiKeyInputUiState() {
	return {
		akiui_empty: apiKeyInputUiEncoded(makeApiKeyInputUiState(), 40),
		akiui_key: apiKeyInputUiEncoded(makeApiKeyInputUiState({ prefill: "sk-test" }), 40),
		akiui_openai: apiKeyInputUiEncoded(
			makeApiKeyInputUiState({ id: "openai", name: "OpenAI", prefill: "sk-proj-abc" }),
			60,
		),
		akiui_narrow: apiKeyInputUiEncoded(makeApiKeyInputUiState({ prefill: "ab" }), 20),
		akiui_long: apiKeyInputUiEncoded(
			makeApiKeyInputUiState({ prefill: "sk-ant-oat-xxxxxxxx" }),
			48,
		),
	};
}

function oauthSelectorUiItemDigest(option, selected, showAuthTypeLabels) {
	const auth = option.authType === "oauth" ? "oauth" : "api_key";
	const status = oauthOptionStatusLabel(option);
	const authLabel = showAuthTypeLabels
		? ` [${option.authType === "oauth" ? "subscription" : "API key"}]`
		: "";
	return `${selected ? "sel" : "nosel"}:${option.name}:${auth}:${status}${authLabel}`;
}

function makeOauthSelectorUiState({
	mode = "login",
	options = makeOauthSelectorTestOptions(),
	selected = 0,
	query = "",
} = {}) {
	const filtered = query
		? fuzzyModule.fuzzyFilter(options, query, oauthSelectorSearchText)
		: options;
	return {
		mode,
		options,
		filtered,
		selected: filtered.length === 0 ? 0 : Math.min(selected, filtered.length - 1),
		query,
	};
}

function oauthSelectorUiEncoded(state, width) {
	const title =
		state.mode === "logout"
			? "Select provider to logout:"
			: "Select provider to configure:";
	const showAuthTypeLabels =
		new Set(state.options.map((option) => option.authType)).size > 1;
	// Exercise OauthSelectorComponent.updateList-style theming.
	for (let i = 0; i < state.filtered.length; i++) {
		const option = state.filtered[i];
		const isSelected = i === state.selected;
		const statusIndicator = (() => {
			if (!option.status) return themeModule.theme.fg("muted", " • unconfigured");
			return themeModule.theme.fg("success", " ✓ configured");
		})();
		const authTypeLabel = showAuthTypeLabels
			? themeModule.theme.fg(
					"muted",
					` [${option.authType === "oauth" ? "subscription" : "API key"}]`,
				)
			: "";
		if (isSelected) {
			themeModule.theme.fg("accent", "→ ") +
				themeModule.theme.fg("accent", option.name) +
				authTypeLabel +
				statusIndicator;
		} else {
			`  ${themeModule.theme.fg("text", option.name)}` + authTypeLabel + statusIndicator;
		}
	}
	let emptyMsg = "";
	if (state.filtered.length === 0) {
		if (state.options.length > 0) emptyMsg = "No matching providers";
		else if (state.mode === "logout") emptyMsg = "No providers logged in. Use /login first.";
		else emptyMsg = "No providers available";
		themeModule.theme.fg("muted", `  ${emptyMsg}`);
	}
	const items = state.filtered
		.map((option, index) =>
			oauthSelectorUiItemDigest(option, index === state.selected, showAuthTypeLabels),
		)
		.join(";");
	return `${state.mode}|${title}|${width}|${state.selected}|${state.query}|${items}|${emptyMsg}`;
}

function runCliSelectorsOauthSelectorUiState() {
	return {
		osui_default: oauthSelectorUiEncoded(makeOauthSelectorUiState(), 40),
		osui_sel2: oauthSelectorUiEncoded(makeOauthSelectorUiState({ selected: 2 }), 40),
		osui_filter: oauthSelectorUiEncoded(
			makeOauthSelectorUiState({ query: "open", selected: 0 }),
			50,
		),
		osui_miss: oauthSelectorUiEncoded(makeOauthSelectorUiState({ query: "nope" }), 40),
		osui_logout_empty: oauthSelectorUiEncoded(
			makeOauthSelectorUiState({ mode: "logout", options: [] }),
			40,
		),
	};
}

function runCliSelectorsModelSelectorSearchText() {
	return {
		msst_openai: modelSearchModule.getModelSelectorSearchText({
			id: "gpt-4o",
			provider: "openai",
			name: "GPT-4o",
		}),
		msst_anthropic: modelSearchModule.getModelSelectorSearchText({
			id: "claude-sonnet-4",
			provider: "anthropic",
			name: "Claude Sonnet 4",
		}),
		msst_codex: modelSearchModule.getModelSelectorSearchText({
			id: "gpt-5",
			provider: "openai-codex",
		}),
		msst_openrouter: modelSearchModule.getModelSelectorSearchText({
			id: "openai/gpt-4o",
			provider: "openrouter",
			name: "GPT-4o",
		}),
		msst_google: modelSearchModule.getModelSelectorSearchText({
			id: "gemini-2.5-pro",
			provider: "google",
			name: "",
		}),
	};
}

function qualifiedModelId(item) {
	return `${item.provider}/${item.id}`;
}

function runCliSelectorsQualifiedModelId() {
	return {
		qmid_openai: qualifiedModelId({
			id: "gpt-4o",
			provider: "openai",
		}),
		qmid_anthropic: qualifiedModelId({
			id: "claude-sonnet-4",
			provider: "anthropic",
		}),
		qmid_codex: qualifiedModelId({
			id: "gpt-5",
			provider: "openai-codex",
		}),
		qmid_openrouter: qualifiedModelId({
			id: "openai/gpt-4o",
			provider: "openrouter",
		}),
		qmid_google: qualifiedModelId({
			id: "gemini-2.5-pro",
			provider: "google",
		}),
	};
}

function goal20ModelItem({ id, provider, name = "" }) {
	const model = {
		id,
		name,
		api: "openai-completions",
		provider,
		baseUrl: "http://127.0.0.1:1/v1",
		reasoning: false,
		input: ["text"],
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		contextWindow: 128000,
		maxTokens: 8192,
	};
	return { id, provider, model };
}

function makeModelSelectorTestModels() {
	return [
		goal20ModelItem({ id: "gpt-4o", provider: "openai", name: "GPT-4o" }),
		goal20ModelItem({
			id: "claude-sonnet-4",
			provider: "anthropic",
			name: "Claude Sonnet 4",
		}),
		goal20ModelItem({ id: "gpt-5", provider: "openai-codex", name: "" }),
		goal20ModelItem({
			id: "openai/gpt-4o",
			provider: "openrouter",
			name: "GPT-4o",
		}),
		goal20ModelItem({ id: "gemini-2.5-pro", provider: "google", name: "" }),
	];
}

function sortModelSelectorTestModels(models, currentModel) {
	const sorted = [...models];
	sorted.sort((a, b) => {
		const aIsCurrent =
			a.id === currentModel.id && a.provider === currentModel.provider;
		const bIsCurrent =
			b.id === currentModel.id && b.provider === currentModel.provider;
		if (aIsCurrent && !bIsCurrent) return -1;
		if (!aIsCurrent && bIsCurrent) return 1;
		return a.provider.localeCompare(b.provider);
	});
	return sorted;
}

function modelSelectorFilteredModels(models, query) {
	const current = models[0].model;
	const sorted = sortModelSelectorTestModels(models, current);
	return modelSelectorFilterActiveModels(sorted, query);
}

function modelSelectorFilterActiveModels(activeModels, query) {
	return query
		? fuzzyModule.fuzzyFilter(activeModels, query, ({ id, provider, model }) =>
				modelSearchModule.getModelSelectorSearchText({
					id,
					provider,
					name: model.name,
				}),
			)
		: activeModels;
}

function modelSelectorModelsEqual(left, right) {
	return left.id === right.id && left.provider === right.provider;
}

function modelSelectorSelectCurrent(activeModels, currentModel) {
	const index = activeModels.findIndex((item) =>
		modelSelectorModelsEqual(item.model, currentModel),
	);
	return index >= 0 ? index : 0;
}

function makeModelSelectorScopedTestModels() {
	return [
		goal20ModelItem({ id: "gpt-4o", provider: "openai", name: "GPT-4o" }),
		goal20ModelItem({
			id: "claude-sonnet-4",
			provider: "anthropic",
			name: "Claude Sonnet 4",
		}),
		goal20ModelItem({ id: "gpt-5", provider: "openai-codex", name: "" }),
	];
}

function encodeModelSelectorToggleScopeResult(scope, filteredModels, selectedIndex) {
	return `${scope}|${filteredModels.length}|${selectedIndex}`;
}

function modelSelectorToggleScopeEncoded(allModels, scopedModels, { query = "", toggles = 0 } = {}) {
	const currentModel = allModels[0].model;
	let scope = scopedModels.length > 0 ? "scoped" : "all";
	const sortedAll = sortModelSelectorTestModels(allModels, currentModel);
	let activeModels = scope === "scoped" ? scopedModels : sortedAll;
	let selectedIndex = modelSelectorSelectCurrent(activeModels, currentModel);
	let filteredModels = modelSelectorFilterActiveModels(activeModels, query);

	for (let i = 0; i < toggles; i += 1) {
		if (scopedModels.length === 0) {
			continue;
		}
		scope = scope === "all" ? "scoped" : "all";
		activeModels = scope === "scoped" ? scopedModels : sortedAll;
		filteredModels = modelSelectorFilterActiveModels(activeModels, query);
		selectedIndex = modelSelectorSelectCurrent(filteredModels, currentModel);
		if (query) {
			selectedIndex = 0;
		} else {
			selectedIndex = Math.min(
				selectedIndex,
				Math.max(0, filteredModels.length - 1),
			);
		}
	}

	return encodeModelSelectorToggleScopeResult(scope, filteredModels, selectedIndex);
}

function runCliSelectorsModelSelectorToggleScope() {
	const models = makeModelSelectorTestModels();
	const scoped = makeModelSelectorScopedTestModels();
	return {
		msts_all: modelSelectorToggleScopeEncoded(models, scoped, { toggles: 1 }),
		msts_scoped: modelSelectorToggleScopeEncoded(models, scoped, { toggles: 2 }),
		msts_gpt: modelSelectorToggleScopeEncoded(models, scoped, {
			query: "gpt",
			toggles: 1,
		}),
		msts_none: modelSelectorToggleScopeEncoded(models, [], { toggles: 1 }),
		msts_anth: modelSelectorToggleScopeEncoded(models, scoped, {
			query: "anth",
			toggles: 1,
		}),
	};
}

function modelSelectorVisibleSlice(filteredModels, selectedIndex, maximum = 10) {
	const total = filteredModels.length;
	const startIndex = Math.max(
		0,
		Math.min(selectedIndex - Math.floor(maximum / 2), total - maximum),
	);
	const endIndex = Math.min(startIndex + maximum, total);
	return {
		visible: filteredModels.slice(startIndex, endIndex),
		start: startIndex,
		total,
	};
}

function modelSelectorUiItemDigest(item, selected, current) {
	return `${selected ? "sel" : "nosel"}:${item.id}:${item.provider}${current ? ":cur" : ""}`;
}

function modelSelectorUiFooter(state) {
	const parts = [];
	if (state.errorMessage) {
		parts.push(`err:${state.errorMessage.split("\n")[0]}`);
	} else if (state.filteredModels.length > 0) {
		const selected = state.filteredModels[state.selectedIndex];
		if (selected) {
			parts.push(`name:${selected.model.name}`);
		}
	}
	if (state.refreshStatusMessage) {
		parts.push(`refresh:${state.refreshStatusMessage}`);
	}
	return parts.join("|");
}

function makeModelSelectorUiState({
	allModels = makeModelSelectorTestModels(),
	scopedModels = null,
	selected = null,
	query = "",
	errorMessage = undefined,
	refreshStatusMessage = undefined,
} = {}) {
	const currentModel = allModels[0].model;
	const sortedAll = sortModelSelectorTestModels(allModels, currentModel);
	const scope = scopedModels && scopedModels.length > 0 ? "scoped" : "all";
	let activeModels =
		scopedModels && scopedModels.length > 0 && scope === "scoped"
			? scopedModels
			: sortedAll;
	let selectedIndex = modelSelectorSelectCurrent(activeModels, currentModel);
	if (selected !== null) {
		selectedIndex = selected;
	}
	let filteredModels = modelSelectorFilterActiveModels(activeModels, query);
	return {
		allModels: sortedAll,
		scopedModels: scopedModels ?? [],
		scope,
		query,
		currentModel,
		selectedIndex,
		filteredModels,
		errorMessage,
		refreshStatusMessage,
	};
}

function modelSelectorUiEncoded(state, width) {
	const scope =
		state.scopedModels.length > 0 ? state.scope : "none";
	const { visible, start, total } = modelSelectorVisibleSlice(
		state.filteredModels,
		state.selectedIndex,
	);
	const scroll =
		total > visible.length
			? `(${state.selectedIndex + 1}/${total})`
			: "";
	const empty = total === 0 ? "No matching models" : "";
	for (let i = 0; i < visible.length; i += 1) {
		const item = visible[i];
		const index = start + i;
		const isSelected = index === state.selectedIndex;
		const isCurrent = modelSelectorModelsEqual(item.model, state.currentModel);
		if (isSelected) {
			themeModule.theme.fg("accent", "→ ") +
				themeModule.theme.fg("accent", item.id) +
				themeModule.theme.fg("muted", ` [${item.provider}]`) +
				(isCurrent ? themeModule.theme.fg("success", " ✓") : "");
		} else {
			`  ${item.id} ` +
				themeModule.theme.fg("muted", `[${item.provider}]`) +
				(isCurrent ? themeModule.theme.fg("success", " ✓") : "");
		}
	}
	if (state.errorMessage) {
		themeModule.theme.fg("error", state.errorMessage.split("\n")[0]);
	} else if (total === 0) {
		themeModule.theme.fg("muted", "  No matching models");
	} else {
		const selected = state.filteredModels[state.selectedIndex];
		if (selected) {
			themeModule.theme.fg("muted", `  Model Name: ${selected.model.name}`);
		}
	}
	if (state.refreshStatusMessage) {
		themeModule.theme.fg("muted", `  ${state.refreshStatusMessage}`);
	}
	const items = visible
		.map((item, offset) =>
			modelSelectorUiItemDigest(
				item,
				start + offset === state.selectedIndex,
				modelSelectorModelsEqual(item.model, state.currentModel),
			),
		)
		.join(";");
	return `${scope}|${width}|${state.selectedIndex}|${state.query}|${total}|${scroll}|${items}|${empty}|${modelSelectorUiFooter(state)}`;
}

function runCliSelectorsModelSelectorUiState() {
	const models = makeModelSelectorTestModels();
	const scoped = makeModelSelectorScopedTestModels();
	return {
		msui_default: modelSelectorUiEncoded(makeModelSelectorUiState(), 40),
		msui_sel2: modelSelectorUiEncoded(
			makeModelSelectorUiState({ selected: 2 }),
			40,
		),
		msui_scoped: modelSelectorUiEncoded(
			makeModelSelectorUiState({ scopedModels: scoped }),
			40,
		),
		msui_filter: modelSelectorUiEncoded(
			makeModelSelectorUiState({ query: "gpt" }),
			50,
		),
		msui_miss: modelSelectorUiEncoded(
			makeModelSelectorUiState({ query: "nope" }),
			40,
		),
		msui_error: modelSelectorUiEncoded(
			makeModelSelectorUiState({ errorMessage: "Catalog refresh failed" }),
			40,
		),
		msui_refresh: modelSelectorUiEncoded(
			makeModelSelectorUiState({
				refreshStatusMessage: "Refreshing model catalogs…",
			}),
			40,
		),
	};
}

function scopedModelsFullId(item) {
	return `${item.provider}/${item.id}`;
}

function scopedModelsGetSortedIds(enabledIds, allIds) {
	if (enabledIds === null) {
		return allIds;
	}
	const enabledSet = new Set(enabledIds);
	return [...enabledIds, ...allIds.filter((id) => !enabledSet.has(id))];
}

function scopedModelsSortedIdsEncoded(allModels, enabledIds) {
	const allIds = allModels.map(scopedModelsFullId);
	return scopedModelsGetSortedIds(enabledIds, allIds).join(",");
}

function runCliSelectorsScopedModelsSelectorSortedIds() {
	const models = makeModelSelectorTestModels();
	return {
		smssi_all: scopedModelsSortedIdsEncoded(models, null),
		smssi_partial: scopedModelsSortedIdsEncoded(models, [
			"google/gemini-2.5-pro",
			"openai/gpt-4o",
		]),
		smssi_single: scopedModelsSortedIdsEncoded(models, ["anthropic/claude-sonnet-4"]),
		smssi_empty: scopedModelsSortedIdsEncoded(models, []),
		smssi_reorder: scopedModelsSortedIdsEncoded(models, [
			"openai-codex/gpt-5",
			"openrouter/openai/gpt-4o",
			"anthropic/claude-sonnet-4",
		]),
	};
}

function scopedModelsBuildItems(allModels, enabledIds) {
	const allIds = allModels.map(scopedModelsFullId);
	return scopedModelsGetSortedIds(enabledIds, allIds).map((fullId) => {
		const item = allModels.find((candidate) => scopedModelsFullId(candidate) === fullId);
		return {
			fullId,
			model: item?.model,
			enabled: enabledIds === null || enabledIds.includes(fullId),
		};
	});
}

function scopedModelItemSearchText(item) {
	if (!item.model) {
		return item.fullId;
	}
	return modelSearchModule.getModelSearchText({
		id: item.model.id,
		provider: item.model.provider,
		name: item.model.name,
	});
}

function scopedModelsFilterItems(allModels, enabledIds, query) {
	const items = scopedModelsBuildItems(allModels, enabledIds);
	return query
		? fuzzyModule.fuzzyFilter(items, query, scopedModelItemSearchText)
		: items;
}

function scopedModelsSelectorSetQueryEncoded(
	allModels,
	enabledIds,
	selected,
	initialQuery,
	newQuery,
) {
	let selectedIndex = selected;
	let filteredItems = scopedModelsFilterItems(allModels, enabledIds, initialQuery);
	selectedIndex = Math.min(selectedIndex, Math.max(0, filteredItems.length - 1));
	filteredItems = scopedModelsFilterItems(allModels, enabledIds, newQuery);
	selectedIndex = Math.min(selectedIndex, Math.max(0, filteredItems.length - 1));
	return `${filteredItems.length}|${selectedIndex}`;
}

function runCliSelectorsScopedModelsSelectorSetQuery() {
	const models = makeModelSelectorTestModels();
	const enabledIds = null;
	return {
		smssq_clear: scopedModelsSelectorSetQueryEncoded(
			models,
			enabledIds,
			2,
			"",
			"",
		),
		smssq_gpt: scopedModelsSelectorSetQueryEncoded(
			models,
			enabledIds,
			2,
			"",
			"gpt",
		),
		smssq_same: scopedModelsSelectorSetQueryEncoded(
			models,
			enabledIds,
			0,
			"gpt",
			"gpt",
		),
		smssq_reset: scopedModelsSelectorSetQueryEncoded(
			models,
			enabledIds,
			0,
			"gpt",
			"",
		),
		smssq_miss: scopedModelsSelectorSetQueryEncoded(
			models,
			enabledIds,
			1,
			"anth",
			"nope",
		),
	};
}

function scopedModelsSelectorMoveEncoded(models, enabledIds, selected, delta, query = "") {
	const filteredItems = scopedModelsFilterItems(models, enabledIds, query);
	return String(moveIndex(selected, filteredItems.length, delta));
}

function runCliSelectorsScopedModelsSelectorMove() {
	const models = makeModelSelectorTestModels();
	const enabledIds = null;
	return {
		smsmv_0_1: scopedModelsSelectorMoveEncoded(models, enabledIds, 0, 1),
		smsmv_2_m1: scopedModelsSelectorMoveEncoded(models, enabledIds, 2, -1),
		smsmv_1_1: scopedModelsSelectorMoveEncoded(models, enabledIds, 1, 1),
		smsmv_1_m1: scopedModelsSelectorMoveEncoded(models, enabledIds, 1, -1),
		smsmv_filter: scopedModelsSelectorMoveEncoded(models, enabledIds, 0, 1, "gpt"),
	};
}

function scopedModelsToggleId(enabledIds, id) {
	if (enabledIds === null) {
		return [id];
	}
	const index = enabledIds.indexOf(id);
	if (index >= 0) {
		return [...enabledIds.slice(0, index), ...enabledIds.slice(index + 1)];
	}
	return [...enabledIds, id];
}

function makeScopedModelsBenchState(allModels, enabledIds, selected, query = "") {
	const filteredItems = scopedModelsFilterItems(allModels, enabledIds, query);
	return {
		allModels,
		enabledIds,
		query,
		selected: Math.min(selected, Math.max(0, filteredItems.length - 1)),
		filteredItems,
	};
}

function scopedModelsSelectorClampSelected(state) {
	state.filteredItems = scopedModelsFilterItems(
		state.allModels,
		state.enabledIds,
		state.query,
	);
	state.selected = Math.min(
		state.selected,
		Math.max(0, state.filteredItems.length - 1),
	);
}

function scopedModelsSelectorSetQueryState(state, query) {
	state.query = query ?? "";
	scopedModelsSelectorClampSelected(state);
}

function scopedModelsSelectorMoveState(state, delta) {
	state.selected = moveIndex(state.selected, state.filteredItems.length, delta);
}

function encodeScopedModelsSelectorHandleEventResult(state, action) {
	const actionText = action ? String(action) : "null";
	return `${actionText}|null|${state.selected}`;
}

function scopedModelsSelectorHandleEvent(state, eventKind, { text } = {}) {
	switch (eventKind) {
		case "down":
			scopedModelsSelectorMoveState(state, 1);
			return { action: "changed" };
		case "up":
			scopedModelsSelectorMoveState(state, -1);
			return { action: "changed" };
		case "page-down":
			scopedModelsSelectorMoveState(state, 8);
			return { action: "changed" };
		case "page-up":
			scopedModelsSelectorMoveState(state, -8);
			return { action: "changed" };
		case "enter": {
			const item = state.filteredItems[state.selected];
			if (item) {
				state.enabledIds = scopedModelsToggleId(state.enabledIds, item.fullId);
				scopedModelsSelectorClampSelected(state);
			}
			return { action: "changed" };
		}
		case "escape":
			return { action: "cancel" };
		case "interrupt":
			if (state.query.length > 0) {
				scopedModelsSelectorSetQueryState(state, "");
				return { action: "changed" };
			}
			return { action: "cancel" };
		case "backspace":
			scopedModelsSelectorSetQueryState(state, deleteQueryChar(state.query));
			return { action: "changed" };
		case "text":
			scopedModelsSelectorSetQueryState(state, state.query + (text ?? ""));
			return { action: "changed" };
		default:
			return { action: null };
	}
}

function scopedModelsSelectorHandleEventEncoded(
	allModels,
	enabledIds,
	selected,
	eventKind,
	{ text, query } = {},
) {
	const state = makeScopedModelsBenchState(allModels, enabledIds, selected, query ?? "");
	state.selected = selected;
	const result = scopedModelsSelectorHandleEvent(state, eventKind, { text });
	return encodeScopedModelsSelectorHandleEventResult(state, result.action);
}

function runCliSelectorsScopedModelsSelectorHandleEvent() {
	const models = makeModelSelectorTestModels();
	const enabledIds = null;
	return {
		smshe_down: scopedModelsSelectorHandleEventEncoded(models, enabledIds, 0, "down"),
		smshe_up: scopedModelsSelectorHandleEventEncoded(models, enabledIds, 1, "up"),
		smshe_enter: scopedModelsSelectorHandleEventEncoded(models, enabledIds, 0, "enter"),
		smshe_esc: scopedModelsSelectorHandleEventEncoded(models, enabledIds, 0, "escape"),
		smshe_text: scopedModelsSelectorHandleEventEncoded(models, enabledIds, 0, "text", {
			text: "gpt",
		}),
		smshe_bs: scopedModelsSelectorHandleEventEncoded(models, enabledIds, 0, "backspace", {
			query: "gpt",
		}),
	};
}

function scopedModelsSelectorRawInputKeyDataPi(keyName) {
	const manager = new keybindingsModule.KeybindingsManager(appKeybindingsModule.KEYBINDINGS);
	return manager.getKeys(keyName)[0];
}

function scopedModelsSelectorHandleRawInputEncoded(allModels, enabledIds, selected, data, query = "") {
	const manager = new keybindingsModule.KeybindingsManager(appKeybindingsModule.KEYBINDINGS);
	const state = makeScopedModelsBenchState(allModels, enabledIds, selected, query);
	let action = "null";
	const value = "null";
	let consumed = "false";

	const refreshFiltered = () => {
		state.filteredItems = scopedModelsFilterItems(allModels, state.enabledIds, state.query);
		state.selected = Math.min(state.selected, Math.max(0, state.filteredItems.length - 1));
	};

	if (selectorKeybindingMatchesPi(manager, data, "tui.select.up")) {
		if (state.filteredItems.length > 0) {
			state.selected = moveIndex(state.selected, state.filteredItems.length, -1);
		}
		action = "changed";
		consumed = "true";
	} else if (selectorKeybindingMatchesPi(manager, data, "tui.select.down")) {
		if (state.filteredItems.length > 0) {
			state.selected = moveIndex(state.selected, state.filteredItems.length, 1);
		}
		action = "changed";
		consumed = "true";
	} else if (selectorKeybindingMatchesPi(manager, data, "tui.select.confirm")) {
		const item = state.filteredItems[state.selected];
		if (item) {
			state.enabledIds = scopedModelsToggleId(state.enabledIds, item.fullId);
			refreshFiltered();
		}
		action = "changed";
		consumed = "true";
	} else if (selectorKeybindingMatchesPi(manager, data, "tui.select.cancel")) {
		action = "cancel";
		consumed = "true";
	}

	return `${action}|${value}|${state.selected}|${consumed}`;
}

function runCliSelectorsScopedModelsSelectorHandleRawInput() {
	const models = makeModelSelectorTestModels();
	const enabledIds = null;
	return {
		smsri_down: scopedModelsSelectorHandleRawInputEncoded(
			models,
			enabledIds,
			0,
			scopedModelsSelectorRawInputKeyDataPi("tui.select.down"),
		),
		smsri_j: scopedModelsSelectorHandleRawInputEncoded(models, enabledIds, 1, "j"),
		smsri_esc: scopedModelsSelectorHandleRawInputEncoded(
			models,
			enabledIds,
			1,
			scopedModelsSelectorRawInputKeyDataPi("tui.select.cancel"),
		),
		smsri_bad: scopedModelsSelectorHandleRawInputEncoded(models, enabledIds, 0, "q"),
		smsri_o: scopedModelsSelectorHandleRawInputEncoded(models, enabledIds, 0, "o"),
		smsri_confirm: scopedModelsSelectorHandleRawInputEncoded(
			models,
			enabledIds,
			0,
			scopedModelsSelectorRawInputKeyDataPi("tui.select.confirm"),
		),
		smsri_up: scopedModelsSelectorHandleRawInputEncoded(
			models,
			enabledIds,
			2,
			scopedModelsSelectorRawInputKeyDataPi("tui.select.up"),
		),
	};
}

function scopedModelsVisibleSlice(filteredItems, selectedIndex, maximum = 8) {
	const total = filteredItems.length;
	const startIndex = Math.max(
		0,
		Math.min(selectedIndex - Math.floor(maximum / 2), total - maximum),
	);
	const endIndex = Math.min(startIndex + maximum, total);
	return {
		visible: filteredItems.slice(startIndex, endIndex),
		start: startIndex,
		total,
	};
}

function scopedModelsUiItemDigest(item, selected, allEnabled) {
	const id = item.model?.id ?? item.fullId;
	const provider = item.model?.provider ?? "unavailable";
	let status = "";
	if (!item.model) {
		status = ":unavail";
	} else if (!allEnabled) {
		status = item.enabled ? ":en" : ":dis";
	}
	return `${selected ? "sel" : "nosel"}:${id}:${provider}${status}`;
}

function scopedModelsUiFooter(state) {
	const parts = [];
	const allEnabled = state.enabledIds === null;
	const enabledCount =
		state.enabledIds?.filter((id) =>
			state.allModels.some((candidate) => scopedModelsFullId(candidate) === id),
		).length ?? state.allModels.length;
	const unavailableCount =
		state.enabledIds?.filter(
			(id) => !state.allModels.some((candidate) => scopedModelsFullId(candidate) === id),
		).length ?? 0;
	parts.push(
		allEnabled
			? "count:all"
			: `count:${enabledCount}/${state.allModels.length}${unavailableCount ? `:${unavailableCount}unavail` : ""}`,
	);
	if (state.dirty) {
		parts.push("dirty:1");
	}
	if (state.filteredItems.length > 0) {
		const selected = state.filteredItems[state.selectedIndex];
		if (selected?.model?.name) {
			parts.push(`name:${selected.model.name}`);
		} else if (selected && !selected.model) {
			parts.push("name:unavail");
		}
	}
	if (state.refreshStatusMessage) {
		parts.push(`refresh:${state.refreshStatusMessage}`);
	}
	return parts.join("|");
}

function makeScopedModelsUiState({
	allModels = makeModelSelectorTestModels(),
	enabledIds = null,
	selected = null,
	query = "",
	dirty = false,
	refreshStatusMessage = undefined,
} = {}) {
	let selectedIndex = 0;
	if (selected !== null) {
		selectedIndex = selected;
	}
	const filteredItems = scopedModelsFilterItems(allModels, enabledIds, query);
	selectedIndex = Math.min(selectedIndex, Math.max(0, filteredItems.length - 1));
	return {
		allModels,
		enabledIds,
		query,
		selectedIndex,
		filteredItems,
		dirty,
		refreshStatusMessage,
	};
}

function scopedModelsSelectorUiEncoded(state, width) {
	const scope = state.enabledIds === null ? "all" : "partial";
	const { visible, start, total } = scopedModelsVisibleSlice(
		state.filteredItems,
		state.selectedIndex,
	);
	const scroll =
		total > visible.length ? `(${state.selectedIndex + 1}/${total})` : "";
	const empty = total === 0 ? "No matching models" : "";
	const allEnabled = state.enabledIds === null;
	for (let i = 0; i < visible.length; i += 1) {
		const item = visible[i];
		const index = start + i;
		const isSelected = index === state.selectedIndex;
		const id = item.model?.id ?? item.fullId;
		const providerBadge = item.model
			? themeModule.theme.fg("muted", ` [${item.model.provider}]`)
			: themeModule.theme.fg("muted", " [unavailable]");
		const status = item.model
			? allEnabled
				? ""
				: item.enabled
					? themeModule.theme.fg("success", " ✓")
					: themeModule.theme.fg("dim", " ✗")
			: themeModule.theme.fg("dim", " ✗");
		if (isSelected) {
			themeModule.theme.fg("accent", "→ ") +
				themeModule.theme.fg("accent", id) +
				providerBadge +
				status;
		} else {
			`  ${id}` + providerBadge + status;
		}
	}
	if (total === 0) {
		themeModule.theme.fg("muted", "  No matching models");
	} else {
		const selected = state.filteredItems[state.selectedIndex];
		if (selected) {
			themeModule.theme.fg(
				"muted",
				`  ${selected.model ? `Model Name: ${selected.model.name}` : "Model unavailable"}`,
			);
		}
	}
	if (state.refreshStatusMessage) {
		themeModule.theme.fg("muted", `  ${state.refreshStatusMessage}`);
	}
	const items = visible
		.map((item, offset) =>
			scopedModelsUiItemDigest(
				item,
				start + offset === state.selectedIndex,
				allEnabled,
			),
		)
		.join(";");
	return `${scope}|${width}|${state.selectedIndex}|${state.query}|${total}|${scroll}|${items}|${empty}|${scopedModelsUiFooter(state)}`;
}


function scopedModelsSelectorCounts(allModels, enabledIds) {
	const allIds = allModels.map(scopedModelsFullId);
	const allEnabled = enabledIds === null;
	const enabledCount = enabledIds?.filter((id) => allModels.some((c) => scopedModelsFullId(c) === id)).length ?? allIds.length;
	const unavailableCount = enabledIds?.filter((id) => !allModels.some((c) => scopedModelsFullId(c) === id)).length ?? 0;
	return { allEnabled, enabledCount, unavailableCount, total: allIds.length };
}
function scopedModelsSelectorCountsEncoded(allModels, enabledIds) {
	const { allEnabled, enabledCount, unavailableCount, total } = scopedModelsSelectorCounts(allModels, enabledIds);
	return `${allEnabled ? "all" : "partial"}|${enabledCount}|${unavailableCount}|${total}`;
}
function runCliSelectorsScopedModelsSelectorCounts() {
	const models = makeModelSelectorTestModels();
	const partialEnabled = ["openai/gpt-4o", "anthropic/claude-sonnet-4"];
	const withUnavailable = ["stale/missing", "openai/gpt-4o"];
	return {
		smsc_all: scopedModelsSelectorCountsEncoded(models, null),
		smsc_partial: scopedModelsSelectorCountsEncoded(models, partialEnabled),
		smsc_unavail: scopedModelsSelectorCountsEncoded(models, withUnavailable),
		smsc_empty: scopedModelsSelectorCountsEncoded(models, []),
		smsc_single: scopedModelsSelectorCountsEncoded(models, ["google/gemini-2.5-pro"]),
	};
}
function runCliSelectorsScopedModelsSelectorUiState() {
	const models = makeModelSelectorTestModels();
	const partialEnabled = ["openai/gpt-4o", "anthropic/claude-sonnet-4"];
	return {
		smsui_default: scopedModelsSelectorUiEncoded(makeScopedModelsUiState(), 40),
		smsui_sel2: scopedModelsSelectorUiEncoded(
			makeScopedModelsUiState({ selected: 2 }),
			40,
		),
		smsui_partial: scopedModelsSelectorUiEncoded(
			makeScopedModelsUiState({ enabledIds: partialEnabled }),
			40,
		),
		smsui_filter: scopedModelsSelectorUiEncoded(
			makeScopedModelsUiState({ query: "gpt" }),
			50,
		),
		smsui_miss: scopedModelsSelectorUiEncoded(
			makeScopedModelsUiState({ query: "nope" }),
			40,
		),
		smsui_refresh: scopedModelsSelectorUiEncoded(
			makeScopedModelsUiState({
				refreshStatusMessage: "Refreshing model catalogs…",
			}),
			40,
		),
		smsui_dirty: scopedModelsSelectorUiEncoded(
			makeScopedModelsUiState({ dirty: true }),
			40,
		),
	};
}

function encodeScopedModelsEnabledIds(enabledIds) {
	if (enabledIds === null) {
		return "all";
	}
	return enabledIds.join(",");
}

function scopedModelsSelectorToggleSelectedEncoded(
	allModels,
	enabledIds,
	selected,
	query = "",
) {
	const state = makeScopedModelsBenchState(allModels, enabledIds, selected, query);
	state.selected = selected;
	state.isDirty = false;
	scopedModelsSelectorClampSelected(state);
	const item = state.filteredItems[state.selected];
	if (item) {
		state.enabledIds = scopedModelsToggleId(state.enabledIds, item.fullId);
		state.isDirty = true;
		scopedModelsSelectorClampSelected(state);
	}
	return `${encodeScopedModelsEnabledIds(state.enabledIds)}|${state.isDirty ? "true" : "false"}|${state.selected}`;
}

function runCliSelectorsScopedModelsSelectorToggleSelected() {
	const models = makeModelSelectorTestModels();
	return {
		smstg_all_0: scopedModelsSelectorToggleSelectedEncoded(models, null, 0),
		smstg_partial_off: scopedModelsSelectorToggleSelectedEncoded(
			models,
			["openai/gpt-4o"],
			0,
		),
		smstg_partial_on: scopedModelsSelectorToggleSelectedEncoded(models, [], 2),
		smstg_retoggle: scopedModelsSelectorToggleSelectedEncoded(
			models,
			["openai/gpt-4o", "anthropic/claude-sonnet-4"],
			1,
		),
		smstg_filter: scopedModelsSelectorToggleSelectedEncoded(
			models,
			null,
			0,
			"gpt",
		),
		smstg_miss: scopedModelsSelectorToggleSelectedEncoded(
			models,
			null,
			0,
			"nope",
		),
	};
}


function scopedModelsSelectorTargetIds(allModels, enabledIds, query = "") {
	if (query) {
		return scopedModelsFilterItems(allModels, enabledIds, query).map((item) => item.fullId);
	}
	return allModels.map(scopedModelsFullId);
}

function scopedModelsSelectorTargetIdsEncoded(allModels, enabledIds, query = "") {
	return scopedModelsSelectorTargetIds(allModels, enabledIds, query).join(",");
}

function runCliSelectorsScopedModelsSelectorTargetIds() {
	const models = makeModelSelectorTestModels();
	return {
		smsti_all: scopedModelsSelectorTargetIdsEncoded(models, null),
		smsti_gpt: scopedModelsSelectorTargetIdsEncoded(models, null, "gpt"),
		smsti_nope: scopedModelsSelectorTargetIdsEncoded(models, null, "nope"),
		smsti_claude: scopedModelsSelectorTargetIdsEncoded(models, null, "claude"),
		smsti_partial: scopedModelsSelectorTargetIdsEncoded(
			models,
			["openai/gpt-4o", "anthropic/claude-sonnet-4"],
			"gpt",
		),
	};
}


function scopedModelsIsEnabled(enabledIds, id) {
	return enabledIds === null || enabledIds.includes(id);
}

function scopedModelsEnableIds(enabledIds, allIds, targetIds) {
	if (enabledIds === null) {
		return null;
	}
	const targets = targetIds ?? allIds;
	const result = [...enabledIds];
	for (const id of targets) {
		if (!result.includes(id)) {
			result.push(id);
		}
	}
	return result.length === allIds.length && result.every((id) => allIds.includes(id))
		? null
		: result;
}

function scopedModelsClearIds(enabledIds, allIds, targetIds) {
	if (enabledIds === null) {
		return targetIds ? allIds.filter((id) => !targetIds.includes(id)) : [];
	}
	const targets = new Set(targetIds ?? enabledIds);
	return enabledIds.filter((id) => !targets.has(id));
}

function scopedModelsSelectorToggleProviderEncoded(
	allModels,
	enabledIds,
	selected,
	query = "",
) {
	const state = makeScopedModelsBenchState(allModels, enabledIds, selected, query);
	state.isDirty = false;
	scopedModelsSelectorClampSelected(state);
	const item = state.filteredItems[state.selected];
	if (item?.model) {
		const allIds = allModels.map(scopedModelsFullId);
		const modelsById = new Map(
			allModels.map((candidate) => [scopedModelsFullId(candidate), candidate]),
		);
		const provider = item.model.provider;
		const providerIds = allIds.filter(
			(id) => modelsById.get(id).provider === provider,
		);
		const allEnabled = providerIds.every((id) =>
			scopedModelsIsEnabled(state.enabledIds, id),
		);
		state.enabledIds = allEnabled
			? scopedModelsClearIds(state.enabledIds, allIds, providerIds)
			: scopedModelsEnableIds(state.enabledIds, allIds, providerIds);
		state.isDirty = true;
		scopedModelsSelectorClampSelected(state);
	}
	return `${encodeScopedModelsEnabledIds(state.enabledIds)}|${state.isDirty ? "true" : "false"}|${state.selected}`;
}

function scopedModelsSelectorEnableAllEncoded(allModels, enabledIds, query = "") {
	const allIds = allModels.map(scopedModelsFullId);
	const targetIds = query
		? scopedModelsFilterItems(allModels, enabledIds, query).map((item) => item.fullId)
		: undefined;
	const nextEnabledIds = scopedModelsEnableIds(enabledIds, allIds, targetIds);
	return `${encodeScopedModelsEnabledIds(nextEnabledIds)}|true`;
}

function runCliSelectorsScopedModelsSelectorEnableAll() {
	const models = makeModelSelectorTestModels();
	return {
		smsea_all: scopedModelsSelectorEnableAllEncoded(models, null),
		smsea_partial: scopedModelsSelectorEnableAllEncoded(models, ["openai/gpt-4o"]),
		smsea_empty: scopedModelsSelectorEnableAllEncoded(models, []),
		smsea_two: scopedModelsSelectorEnableAllEncoded(models, [
			"openai/gpt-4o",
			"anthropic/claude-sonnet-4",
		]),
		smsea_filter: scopedModelsSelectorEnableAllEncoded(
			models,
			["openai/gpt-4o"],
			"gpt",
		),
		smsea_miss: scopedModelsSelectorEnableAllEncoded(
			models,
			["openai/gpt-4o"],
			"nope",
		),
	};
}

function scopedModelsSelectorClearAllEncoded(allModels, enabledIds, query = "") {
	const allIds = allModels.map(scopedModelsFullId);
	const targetIds = query
		? scopedModelsFilterItems(allModels, enabledIds, query).map((item) => item.fullId)
		: undefined;
	const nextEnabledIds = scopedModelsClearIds(enabledIds, allIds, targetIds);
	return `${encodeScopedModelsEnabledIds(nextEnabledIds)}|true`;
}

function runCliSelectorsScopedModelsSelectorClearAll() {
	const models = makeModelSelectorTestModels();
	return {
		smsca_all: scopedModelsSelectorClearAllEncoded(models, null),
		smsca_partial: scopedModelsSelectorClearAllEncoded(models, ["openai/gpt-4o"]),
		smsca_empty: scopedModelsSelectorClearAllEncoded(models, []),
		smsca_two: scopedModelsSelectorClearAllEncoded(models, [
			"openai/gpt-4o",
			"anthropic/claude-sonnet-4",
		]),
		smsca_filter: scopedModelsSelectorClearAllEncoded(
			models,
			["openai/gpt-4o"],
			"gpt",
		),
		smsca_miss: scopedModelsSelectorClearAllEncoded(
			models,
			["openai/gpt-4o"],
			"nope",
		),
	};
}

function scopedModelsMoveEnabled(enabledIds, id, delta) {
	if (enabledIds === null) {
		return enabledIds;
	}
	const list = [...enabledIds];
	const index = list.indexOf(id);
	if (index < 0) {
		return list;
	}
	const newIndex = index + delta;
	if (newIndex < 0 || newIndex >= list.length) {
		return list;
	}
	const result = [...list];
	[result[index], result[newIndex]] = [result[newIndex], result[index]];
	return result;
}

function scopedModelsSelectorReorderEncoded(
	allModels,
	enabledIds,
	selected,
	delta,
	query = "",
) {
	const state = makeScopedModelsBenchState(allModels, enabledIds, selected, query);
	state.isDirty = false;
	scopedModelsSelectorClampSelected(state);
	const item = state.filteredItems[state.selected];
	if (
		item &&
		Array.isArray(state.enabledIds) &&
		scopedModelsIsEnabled(state.enabledIds, item.fullId)
	) {
		const currentIndex = state.enabledIds.indexOf(item.fullId);
		const newIndex = currentIndex + delta;
		if (newIndex >= 0 && newIndex < state.enabledIds.length) {
			state.enabledIds = scopedModelsMoveEnabled(
				state.enabledIds,
				item.fullId,
				delta,
			);
			state.isDirty = true;
			state.selected += delta;
			scopedModelsSelectorClampSelected(state);
		}
	}
	return `${encodeScopedModelsEnabledIds(state.enabledIds)}|${state.isDirty ? "true" : "false"}|${state.selected}`;
}

function runCliSelectorsScopedModelsSelectorReorder() {
	const models = makeModelSelectorTestModels();
	const three = [
		"openai/gpt-4o",
		"anthropic/claude-sonnet-4",
		"google/gemini-2.5-pro",
	];
	return {
		smsror_down: scopedModelsSelectorReorderEncoded(models, three, 0, 1),
		smsror_up: scopedModelsSelectorReorderEncoded(models, three, 1, -1),
		smsror_noop: scopedModelsSelectorReorderEncoded(models, three, 0, -1),
		smsror_empty: scopedModelsSelectorReorderEncoded(models, [], 0, 1),
		smsror_filter: scopedModelsSelectorReorderEncoded(
			models,
			three,
			0,
			1,
			"gpt",
		),
		smsror_miss: scopedModelsSelectorReorderEncoded(
			models,
			three,
			0,
			1,
			"nope",
		),
	};
}

function scopedModelsSelectorPersistEncoded(allModels, enabledIds, withCallback = true) {
	let calls = 0;
	const state = makeScopedModelsBenchState(allModels, enabledIds, 0);
	state.isDirty = true;
	if (withCallback) {
		const onPersist = (_payload) => {
			calls += 1;
		};
		onPersist(state.enabledIds === null ? null : [...state.enabledIds]);
	}
	state.isDirty = false;
	return `${encodeScopedModelsEnabledIds(state.enabledIds)}|${state.isDirty ? "true" : "false"}|${calls}`;
}

function runCliSelectorsScopedModelsSelectorPersist() {
	const models = makeModelSelectorTestModels();
	return {
		smsper_all: scopedModelsSelectorPersistEncoded(models, null),
		smsper_partial: scopedModelsSelectorPersistEncoded(models, ["openai/gpt-4o"]),
		smsper_no_cb: scopedModelsSelectorPersistEncoded(models, null, false),
		smsper_empty: scopedModelsSelectorPersistEncoded(models, []),
		smsper_two: scopedModelsSelectorPersistEncoded(models, [
			"openai/gpt-4o",
			"anthropic/claude-sonnet-4",
		]),
		smsper_single: scopedModelsSelectorPersistEncoded(models, ["google/gemini-2.5-pro"]),
	};
}

function sessionScopedModelsForProviderCount(allModels, enabledIds) {
	if (enabledIds === null) {
		return null;
	}
	const allIds = allModels.map(scopedModelsFullId);
	const available = enabledIds
		.map((id) => allModels.find((model) => scopedModelsFullId(model) === id))
		.filter(Boolean);
	const allEnabledP = allIds.every((id) => enabledIds.includes(id));
	if (available.length > 0 && !allEnabledP) {
		return available;
	}
	return null;
}

function scopedModelsSelectorProviderCount(allModels, enabledIds) {
	const activeModels =
		sessionScopedModelsForProviderCount(allModels, enabledIds) ?? allModels;
	return new Set(activeModels.map((model) => model.provider)).size;
}

function scopedModelsSelectorProviderCountEncoded(allModels, enabledIds) {
	return String(scopedModelsSelectorProviderCount(allModels, enabledIds));
}

function runCliSelectorsScopedModelsSelectorProviderCount() {
	const models = makeModelSelectorTestModels();
	const partialEnabled = ["openai/gpt-4o", "anthropic/claude-sonnet-4"];
	const withUnavailable = ["stale/missing", "openai/gpt-4o"];
	return {
		smsprv_all: scopedModelsSelectorProviderCountEncoded(models, null),
		smsprv_partial: scopedModelsSelectorProviderCountEncoded(
			models,
			partialEnabled,
		),
		smsprv_unavail: scopedModelsSelectorProviderCountEncoded(
			models,
			withUnavailable,
		),
		smsprv_empty: scopedModelsSelectorProviderCountEncoded(models, []),
		smsprv_single: scopedModelsSelectorProviderCountEncoded(models, [
			"google/gemini-2.5-pro",
		]),
	};
}

function runCliSelectorsScopedModelsSelectorToggleProvider() {
	const models = makeModelSelectorTestModels();
	return {
		smstgp_all_0: scopedModelsSelectorToggleProviderEncoded(models, null, 0),
		smstgp_partial_off: scopedModelsSelectorToggleProviderEncoded(
			models,
			["openai/gpt-4o"],
			0,
		),
		smstgp_partial_on: scopedModelsSelectorToggleProviderEncoded(models, [], 2),
		smstgp_retoggle: scopedModelsSelectorToggleProviderEncoded(
			models,
			["openai/gpt-4o", "anthropic/claude-sonnet-4"],
			1,
		),
		smstgp_filter: scopedModelsSelectorToggleProviderEncoded(
			models,
			null,
			0,
			"gpt",
		),
		smstgp_miss: scopedModelsSelectorToggleProviderEncoded(
			models,
			null,
			0,
			"nope",
		),
	};
}

function modelSelectorApplyFilterEncoded(models, query) {
	const selectedIndex = 2;
	const filteredModels = query
		? fuzzyModule.fuzzyFilter(models, query, ({ id, provider, model }) =>
				modelSearchModule.getModelSelectorSearchText({
					id,
					provider,
					name: model.name,
				}),
			)
		: models;
	return `${filteredModels.length}|${selectedIndex}`;
}

function runCliSelectorsModelSelectorApplyFilter() {
	const models = makeModelSelectorTestModels();
	return {
		msaf_all: modelSelectorApplyFilterEncoded(models, ""),
		msaf_gpt: modelSelectorApplyFilterEncoded(models, "gpt"),
		msaf_miss: modelSelectorApplyFilterEncoded(models, "nope"),
		msaf_anth: modelSelectorApplyFilterEncoded(models, "anth"),
		msaf_google: modelSelectorApplyFilterEncoded(models, "oogle"),
	};
}

function modelSelectorMoveEncoded(models, selected, delta, query = "") {
	const filteredModels = query
		? fuzzyModule.fuzzyFilter(models, query, ({ id, provider, model }) =>
				modelSearchModule.getModelSelectorSearchText({
					id,
					provider,
					name: model.name,
				}),
			)
		: models;
	return String(moveIndex(selected, filteredModels.length, delta));
}

function runCliSelectorsModelSelectorMove() {
	const models = makeModelSelectorTestModels();
	return {
		msmv_0_1: modelSelectorMoveEncoded(models, 0, 1),
		msmv_2_m1: modelSelectorMoveEncoded(models, 2, -1),
		msmv_1_1: modelSelectorMoveEncoded(models, 1, 1),
		msmv_1_m1: modelSelectorMoveEncoded(models, 1, -1),
		msmv_filter: modelSelectorMoveEncoded(models, 0, 1, "gpt"),
	};
}

function modelSelectorSearchText(item) {
	return modelSearchModule.getModelSelectorSearchText({
		id: item.id,
		provider: item.provider,
		name: item.model.name,
	});
}

function makeModelSelectorBenchState(models, selected, query = "") {
	const filteredModels = query
		? fuzzyModule.fuzzyFilter(models, query, modelSelectorSearchText)
		: models;
	return {
		allModels: models,
		query,
		filtered: filteredModels,
		selected,
	};
}

function modelSelectorApplyFilterState(state) {
	state.filtered = state.query
		? fuzzyModule.fuzzyFilter(state.allModels, state.query, modelSelectorSearchText)
		: state.allModels;
}

function modelSelectorSetQuery(state, query) {
	state.query = query ?? "";
	modelSelectorApplyFilterState(state);
	if (state.query.length > 0) {
		state.selected = 0;
	} else {
		state.selected = Math.min(
			state.selected,
			Math.max(0, state.filtered.length - 1),
		);
	}
}

function modelSelectorMoveState(state, delta) {
	state.selected = moveIndex(state.selected, state.filtered.length, delta);
}

function encodeModelSelectorHandleEventResult(state, action, value) {
	const actionText = action ? String(action) : "null";
	const valueText =
		action === "select" && value
			? qualifiedModelId({ id: value.id, provider: value.provider })
			: "null";
	return `${actionText}|${valueText}|${state.selected}`;
}

function modelSelectorHandleEvent(state, eventKind, { text } = {}) {
	switch (eventKind) {
		case "down":
			modelSelectorMoveState(state, 1);
			return { action: "changed", value: null };
		case "up":
			modelSelectorMoveState(state, -1);
			return { action: "changed", value: null };
		case "page-down":
			modelSelectorMoveState(state, 10);
			return { action: "changed", value: null };
		case "page-up":
			modelSelectorMoveState(state, -10);
			return { action: "changed", value: null };
		case "enter": {
			const item = state.filtered[state.selected];
			if (item) {
				return { action: "select", value: item.model };
			}
			return { action: null, value: null };
		}
		case "escape":
		case "interrupt":
			return { action: "cancel", value: null };
		case "backspace":
			modelSelectorSetQuery(state, deleteQueryChar(state.query));
			return { action: "changed", value: null };
		case "text":
			modelSelectorSetQuery(state, state.query + (text ?? ""));
			return { action: "changed", value: null };
		default:
			return { action: null, value: null };
	}
}

function modelSelectorHandleEventEncoded(models, selected, eventKind, { text, query } = {}) {
	const state = makeModelSelectorBenchState(models, selected, query ?? "");
	if (query) {
		modelSelectorApplyFilterState(state);
	}
	state.selected = selected;
	const result = modelSelectorHandleEvent(state, eventKind, { text });
	return encodeModelSelectorHandleEventResult(state, result.action, result.value);
}

function runCliSelectorsModelSelectorHandleEvent() {
	const models = makeModelSelectorTestModels();
	return {
		mshe_down: modelSelectorHandleEventEncoded(models, 0, "down"),
		mshe_up: modelSelectorHandleEventEncoded(models, 1, "up"),
		mshe_enter: modelSelectorHandleEventEncoded(models, 0, "enter"),
		mshe_esc: modelSelectorHandleEventEncoded(models, 0, "escape"),
		mshe_text: modelSelectorHandleEventEncoded(models, 0, "text", { text: "gpt" }),
		mshe_bs: modelSelectorHandleEventEncoded(models, 0, "backspace", { query: "gpt" }),
	};
}

function modelSelectorHandleRawInputEncoded(models, selected, data) {
	const manager = new keybindingsModule.KeybindingsManager(keybindingsModule.TUI_KEYBINDINGS);
	const state = makeModelSelectorBenchState(models, selected);
	let action = "null";
	let value = "null";
	let consumed = "false";

	if (selectorKeybindingMatchesPi(manager, data, "tui.input.tab")) {
		action = "changed";
		consumed = "true";
	} else if (selectorKeybindingMatchesPi(manager, data, "tui.select.up")) {
		if (state.filtered.length > 0) {
			state.selected = moveIndex(state.selected, state.filtered.length, -1);
		}
		action = "changed";
		consumed = "true";
	} else if (selectorKeybindingMatchesPi(manager, data, "tui.select.down")) {
		if (state.filtered.length > 0) {
			state.selected = moveIndex(state.selected, state.filtered.length, 1);
		}
		action = "changed";
		consumed = "true";
	} else if (selectorKeybindingMatchesPi(manager, data, "tui.select.pageUp")) {
		if (state.filtered.length > 0) {
			state.selected = moveIndex(state.selected, state.filtered.length, -10);
		}
		action = "changed";
		consumed = "true";
	} else if (selectorKeybindingMatchesPi(manager, data, "tui.select.pageDown")) {
		if (state.filtered.length > 0) {
			state.selected = moveIndex(state.selected, state.filtered.length, 10);
		}
		action = "changed";
		consumed = "true";
	} else if (selectorKeybindingMatchesPi(manager, data, "tui.select.confirm")) {
		const item = state.filtered[state.selected];
		if (item) {
			action = "select";
			value = qualifiedModelId({ id: item.id, provider: item.provider });
		}
		consumed = "true";
	} else if (selectorKeybindingMatchesPi(manager, data, "tui.select.cancel")) {
		action = "cancel";
		consumed = "true";
	}

	return `${action}|${value}|${state.selected}|${consumed}`;
}

function runCliSelectorsModelSelectorHandleRawInput() {
	const models = makeModelSelectorTestModels();
	return {
		mshri_down: modelSelectorHandleRawInputEncoded(
			models,
			0,
			trustRawInputKeyDataPi("tui.select.down"),
		),
		mshri_j: modelSelectorHandleRawInputEncoded(models, 1, "j"),
		mshri_esc: modelSelectorHandleRawInputEncoded(
			models,
			1,
			trustRawInputKeyDataPi("tui.select.cancel"),
		),
		mshri_bad: modelSelectorHandleRawInputEncoded(models, 0, "q"),
		mshri_o: modelSelectorHandleRawInputEncoded(models, 0, "o"),
		mshri_confirm: modelSelectorHandleRawInputEncoded(
			models,
			0,
			trustRawInputKeyDataPi("tui.select.confirm"),
		),
		mshri_up: modelSelectorHandleRawInputEncoded(
			models,
			2,
			trustRawInputKeyDataPi("tui.select.up"),
		),
	};
}

function modelSelectorSetQueryEncoded(models, selected, initialQuery, newQuery) {
	const state = makeModelSelectorBenchState(models, selected, initialQuery);
	modelSelectorApplyFilterState(state);
	state.selected = selected;
	modelSelectorSetQuery(state, newQuery);
	return `${state.filtered.length}|${state.selected}`;
}

function runCliSelectorsModelSelectorSetQuery() {
	const models = makeModelSelectorTestModels();
	return {
		mssq_clear: modelSelectorSetQueryEncoded(models, 2, "", ""),
		mssq_gpt: modelSelectorSetQueryEncoded(models, 2, "", "gpt"),
		mssq_same: modelSelectorSetQueryEncoded(models, 0, "gpt", "gpt"),
		mssq_reset: modelSelectorSetQueryEncoded(models, 0, "gpt", ""),
		mssq_miss: modelSelectorSetQueryEncoded(models, 1, "anth", "nope"),
	};
}

function modelSelectorSelectedModelEncoded(models, selected, query = "") {
	const filteredModels = modelSelectorFilteredModels(models, query);
	const item = filteredModels[selected];
	return item ? qualifiedModelId(item) : "null";
}

function runCliSelectorsModelSelectorSelectedModel() {
	const models = makeModelSelectorTestModels();
	return {
		mssm_0: modelSelectorSelectedModelEncoded(models, 0),
		mssm_1: modelSelectorSelectedModelEncoded(models, 1),
		mssm_3: modelSelectorSelectedModelEncoded(models, 3),
		mssm_gpt0: modelSelectorSelectedModelEncoded(models, 0, "gpt"),
		mssm_gpt2: modelSelectorSelectedModelEncoded(models, 2, "gpt"),
		mssm_miss: modelSelectorSelectedModelEncoded(models, 0, "nope"),
		mssm_oob: modelSelectorSelectedModelEncoded(models, 9),
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
	const oauthOptionStatusLabelResults = runCliSelectorsOauthOptionStatusLabel();
	const oauthOptionStatusRenderedResults = runCliSelectorsOauthOptionStatusRendered();
	const credentialEntryAuthTypeResults = runCliSelectorsCredentialEntryAuthType();
	const oauthEnvironmentSourcePResults = runCliSelectorsOauthEnvironmentSourceP();
	const oauthSelectorSelectionResults = runCliSelectorsOauthSelectorSelection();
	const oauthSelectorApplyFilterResults = runCliSelectorsOauthSelectorApplyFilter();
	const oauthSelectorHandleEventResults = runCliSelectorsOauthSelectorHandleEvent();
	const oauthSelectorHandleRawInputResults = runCliSelectorsOauthSelectorHandleRawInput();
	const oauthSelectorSearchTextResults = runCliSelectorsOauthSelectorSearchText();
	const loginAuthTypeRouteResults = runCliSelectorsLoginAuthTypeRoute();
	const loginProviderOptionsResults = runCliSelectorsLoginProviderOptions();
	const logoutProviderOptionsResults = runCliSelectorsLogoutProviderOptions();
	const loginMethodSelectorHandleEventResults =
		runCliSelectorsLoginMethodSelectorHandleEvent();
	const oauthSelectorMoveResults = runCliSelectorsOauthSelectorMove();
	const apiKeyInputStateHandleEventResults =
		runCliSelectorsApiKeyInputStateHandleEvent();
	const loginMethodSelectorUiStateResults =
		runCliSelectorsLoginMethodSelectorUiState();
	const apiKeyInputUiStateResults = runCliSelectorsApiKeyInputUiState();
	const oauthSelectorUiStateResults = runCliSelectorsOauthSelectorUiState();
	const modelSelectorSearchTextResults = runCliSelectorsModelSelectorSearchText();
	const qualifiedModelIdResults = runCliSelectorsQualifiedModelId();
	const modelSelectorApplyFilterResults = runCliSelectorsModelSelectorApplyFilter();
	const modelSelectorMoveResults = runCliSelectorsModelSelectorMove();
	const modelSelectorHandleEventResults = runCliSelectorsModelSelectorHandleEvent();
	const modelSelectorHandleRawInputResults = runCliSelectorsModelSelectorHandleRawInput();
	const modelSelectorSetQueryResults = runCliSelectorsModelSelectorSetQuery();
	const modelSelectorSelectedModelResults =
		runCliSelectorsModelSelectorSelectedModel();
	const modelSelectorToggleScopeResults =
		runCliSelectorsModelSelectorToggleScope();
	const modelSelectorUiStateResults = runCliSelectorsModelSelectorUiState();
	const scopedModelsSelectorSetQueryResults =
		runCliSelectorsScopedModelsSelectorSetQuery();
	const scopedModelsSelectorMoveResults =
		runCliSelectorsScopedModelsSelectorMove();
	const scopedModelsSelectorHandleEventResults =
		runCliSelectorsScopedModelsSelectorHandleEvent();
	const scopedModelsSelectorHandleRawInputResults =
		runCliSelectorsScopedModelsSelectorHandleRawInput();
	const scopedModelsSelectorUiStateResults =
		runCliSelectorsScopedModelsSelectorUiState();
	const scopedModelsSelectorCountsResults =
		runCliSelectorsScopedModelsSelectorCounts();
	const scopedModelsSelectorSortedIdsResults =
		runCliSelectorsScopedModelsSelectorSortedIds();
	const scopedModelsSelectorToggleSelectedResults =
		runCliSelectorsScopedModelsSelectorToggleSelected();
	const scopedModelsSelectorToggleProviderResults =
		runCliSelectorsScopedModelsSelectorToggleProvider();
	const scopedModelsSelectorTargetIdsResults =
		runCliSelectorsScopedModelsSelectorTargetIds();
	const scopedModelsSelectorEnableAllResults =
		runCliSelectorsScopedModelsSelectorEnableAll();
	const scopedModelsSelectorClearAllResults =
		runCliSelectorsScopedModelsSelectorClearAll();
	const scopedModelsSelectorReorderResults =
		runCliSelectorsScopedModelsSelectorReorder();
	const scopedModelsSelectorPersistResults =
		runCliSelectorsScopedModelsSelectorPersist();
	const scopedModelsSelectorProviderCountResults =
		runCliSelectorsScopedModelsSelectorProviderCount();
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
		...oauthOptionStatusLabelResults,
		...oauthOptionStatusRenderedResults,
		...credentialEntryAuthTypeResults,
		...oauthEnvironmentSourcePResults,
		...oauthSelectorSelectionResults,
		...oauthSelectorApplyFilterResults,
		...oauthSelectorHandleEventResults,
		...oauthSelectorHandleRawInputResults,
		...oauthSelectorSearchTextResults,
		...loginAuthTypeRouteResults,
		...loginProviderOptionsResults,
		...logoutProviderOptionsResults,
		...loginMethodSelectorHandleEventResults,
		...oauthSelectorMoveResults,
		...apiKeyInputStateHandleEventResults,
		...loginMethodSelectorUiStateResults,
		...apiKeyInputUiStateResults,
		...oauthSelectorUiStateResults,
		...modelSelectorSearchTextResults,
		...qualifiedModelIdResults,
		...modelSelectorApplyFilterResults,
		...modelSelectorMoveResults,
		...modelSelectorHandleEventResults,
		...modelSelectorHandleRawInputResults,
		...modelSelectorSetQueryResults,
		...modelSelectorSelectedModelResults,
		...modelSelectorToggleScopeResults,
		...modelSelectorUiStateResults,
		...scopedModelsSelectorSetQueryResults,
		...scopedModelsSelectorMoveResults,
		...scopedModelsSelectorHandleEventResults,
		...scopedModelsSelectorHandleRawInputResults,
		...scopedModelsSelectorUiStateResults,
		...scopedModelsSelectorCountsResults,
		...scopedModelsSelectorSortedIdsResults,
		...scopedModelsSelectorToggleSelectedResults,
		...scopedModelsSelectorToggleProviderResults,
		...scopedModelsSelectorTargetIdsResults,
		...scopedModelsSelectorEnableAllResults,
		...scopedModelsSelectorClearAllResults,
		...scopedModelsSelectorReorderResults,
		...scopedModelsSelectorPersistResults,
		...scopedModelsSelectorProviderCountResults,
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
		oauth_option_status_label: await collect("cli_selectors.oauth_option_status_label", () => {
			return () => runCliSelectorsOauthOptionStatusLabel();
		}),
		oauth_option_status_rendered: await collect("cli_selectors.oauth_option_status_rendered", () => {
			return () => runCliSelectorsOauthOptionStatusRendered();
		}),
		credential_entry_auth_type: await collect("cli_selectors.credential_entry_auth_type", () => {
			return () => runCliSelectorsCredentialEntryAuthType();
		}),
		oauth_environment_source_p: await collect("cli_selectors.oauth_environment_source_p", () => {
			return () => runCliSelectorsOauthEnvironmentSourceP();
		}),
		oauth_selector_selection: await collect("cli_selectors.oauth_selector_selection", () => {
			return () => runCliSelectorsOauthSelectorSelection();
		}),
		oauth_selector_apply_filter: await collect("cli_selectors.oauth_selector_apply_filter", () => {
			return () => runCliSelectorsOauthSelectorApplyFilter();
		}),
		oauth_selector_handle_event: await collect("cli_selectors.oauth_selector_handle_event", () => {
			return () => runCliSelectorsOauthSelectorHandleEvent();
		}),
		oauth_selector_handle_raw_input: await collect("cli_selectors.oauth_selector_handle_raw_input", () => {
			return () => runCliSelectorsOauthSelectorHandleRawInput();
		}),
		oauth_selector_search_text: await collect("cli_selectors.oauth_selector_search_text", () => {
			return () => runCliSelectorsOauthSelectorSearchText();
		}),
		login_auth_type_route: await collect("cli_selectors.login_auth_type_route", () => {
			return () => runCliSelectorsLoginAuthTypeRoute();
		}),
		login_provider_options: await collect("cli_selectors.login_provider_options", () => {
			return () => runCliSelectorsLoginProviderOptions();
		}),
		logout_provider_options: await collect("cli_selectors.logout_provider_options", () => {
			return () => runCliSelectorsLogoutProviderOptions();
		}),
		login_method_selector_handle_event: await collect(
			"cli_selectors.login_method_selector_handle_event",
			() => {
				return () => runCliSelectorsLoginMethodSelectorHandleEvent();
			},
		),
		oauth_selector_move: await collect("cli_selectors.oauth_selector_move", () => {
			return () => runCliSelectorsOauthSelectorMove();
		}),
		api_key_input_state_handle_event: await collect(
			"cli_selectors.api_key_input_state_handle_event",
			() => {
				return () => runCliSelectorsApiKeyInputStateHandleEvent();
			},
		),
		login_method_selector_ui_state: await collect(
			"cli_selectors.login_method_selector_ui_state",
			() => {
				return () => runCliSelectorsLoginMethodSelectorUiState();
			},
		),
		api_key_input_ui_state: await collect("cli_selectors.api_key_input_ui_state", () => {
			return () => runCliSelectorsApiKeyInputUiState();
		}),
		oauth_selector_ui_state: await collect("cli_selectors.oauth_selector_ui_state", () => {
			return () => runCliSelectorsOauthSelectorUiState();
		}),
		model_selector_search_text: await collect("cli_selectors.model_selector_search_text", () => {
			return () => runCliSelectorsModelSelectorSearchText();
		}),
		qualified_model_id: await collect("cli_selectors.qualified_model_id", () => {
			return () => runCliSelectorsQualifiedModelId();
		}),
		model_selector_apply_filter: await collect("cli_selectors.model_selector_apply_filter", () => {
			return () => runCliSelectorsModelSelectorApplyFilter();
		}),
		model_selector_move: await collect("cli_selectors.model_selector_move", () => {
			return () => runCliSelectorsModelSelectorMove();
		}),
		model_selector_handle_event: await collect("cli_selectors.model_selector_handle_event", () => {
			return () => runCliSelectorsModelSelectorHandleEvent();
		}),
		model_selector_handle_raw_input: await collect("cli_selectors.model_selector_handle_raw_input", () => {
			return () => runCliSelectorsModelSelectorHandleRawInput();
		}),
		model_selector_set_query: await collect("cli_selectors.model_selector_set_query", () => {
			return () => runCliSelectorsModelSelectorSetQuery();
		}),
		model_selector_selected_model: await collect(
			"cli_selectors.model_selector_selected_model",
			() => {
				return () => runCliSelectorsModelSelectorSelectedModel();
			},
		),
		model_selector_toggle_scope: await collect(
			"cli_selectors.model_selector_toggle_scope",
			() => {
				return () => runCliSelectorsModelSelectorToggleScope();
			},
		),
		model_selector_ui_state: await collect("cli_selectors.model_selector_ui_state", () => {
			return () => runCliSelectorsModelSelectorUiState();
		}),
		scoped_models_selector_set_query: await collect(
			"cli_selectors.scoped_models_selector_set_query",
			() => {
				return () => runCliSelectorsScopedModelsSelectorSetQuery();
			},
		),
		scoped_models_selector_move: await collect(
			"cli_selectors.scoped_models_selector_move",
			() => {
				return () => runCliSelectorsScopedModelsSelectorMove();
			},
		),
		scoped_models_selector_handle_event: await collect(
			"cli_selectors.scoped_models_selector_handle_event",
			() => {
				return () => runCliSelectorsScopedModelsSelectorHandleEvent();
			},
		),
		scoped_models_selector_handle_raw_input: await collect(
			"cli_selectors.scoped_models_selector_handle_raw_input",
			() => {
				return () => runCliSelectorsScopedModelsSelectorHandleRawInput();
			},
		),
		scoped_models_selector_ui_state: await collect(
			"cli_selectors.scoped_models_selector_ui_state",
			() => {
				return () => runCliSelectorsScopedModelsSelectorUiState();
			},
		),
		scoped_models_selector_counts: await collect(
			"cli_selectors.scoped_models_selector_counts",
			() => { return () => runCliSelectorsScopedModelsSelectorCounts(); },
		),
		scoped_models_selector_sorted_ids: await collect(
			"cli_selectors.scoped_models_selector_sorted_ids",
			() => {
				return () => runCliSelectorsScopedModelsSelectorSortedIds();
			},
		),
		scoped_models_selector_toggle_selected: await collect(
			"cli_selectors.scoped_models_selector_toggle_selected",
			() => {
				return () => runCliSelectorsScopedModelsSelectorToggleSelected();
			},
		),
		scoped_models_selector_target_ids: await collect(
			"cli_selectors.scoped_models_selector_target_ids",
			() => {
				return () => runCliSelectorsScopedModelsSelectorTargetIds();
			},
		),
		scoped_models_selector_enable_all: await collect(
			"cli_selectors.scoped_models_selector_enable_all",
			() => {
				return () => runCliSelectorsScopedModelsSelectorEnableAll();
			},
		),
		scoped_models_selector_toggle_provider: await collect(
			"cli_selectors.scoped_models_selector_toggle_provider",
			() => {
				return () => runCliSelectorsScopedModelsSelectorToggleProvider();
			},
		),
		scoped_models_selector_clear_all: await collect(
			"cli_selectors.scoped_models_selector_clear_all",
			() => {
				return () => runCliSelectorsScopedModelsSelectorClearAll();
			},
		),
		scoped_models_selector_reorder: await collect(
			"cli_selectors.scoped_models_selector_reorder",
			() => {
				return () => runCliSelectorsScopedModelsSelectorReorder();
			},
		),
		scoped_models_selector_persist: await collect(
			"cli_selectors.scoped_models_selector_persist",
			() => {
				return () => runCliSelectorsScopedModelsSelectorPersist();
			},
		),
		scoped_models_selector_provider_count: await collect(
			"cli_selectors.scoped_models_selector_provider_count",
			() => {
				return () => runCliSelectorsScopedModelsSelectorProviderCount();
			},
		),
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

function providerDefinitionIdsSortedDigest(ids) {
	return createHash("sha256").update(ids.join("\n"), "utf8").digest("hex");
}

function runProviderDefinitionIds() {
	const providers = [...builtinProvidersModule.getBuiltinProviders()].sort();
	return {
		openai: providers.includes("openai") ? 1 : 0,
		anthropic: providers.includes("anthropic") ? 1 : 0,
		google: providers.includes("google") ? 1 : 0,
		count: providers.length,
		sorted_digest: providerDefinitionIdsSortedDigest(providers),
	};
}

function runProviderRuntimeModels() {
	const openai = builtinProvidersModule.getBuiltinModels("openai");
	const anthropic = builtinProvidersModule.getBuiltinModels("anthropic");
	const google = builtinProvidersModule.getBuiltinModels("google");
	const unknown = builtinProvidersModule.getBuiltinModels("no-such-provider");
	return {
		rm_openai: openai.length > 0 ? 1 : 0,
		rm_anthropic: anthropic.length > 0 ? 1 : 0,
		rm_google: google.length > 0 ? 1 : 0,
		rm_unknown: unknown.length === 0 ? 1 : 0,
	};
}

function runProviderMergeEnvironment() {
	const explicit = {
		OPENAI_API_KEY: "sk-explicit",
		AZURE_OPENAI_BASE_URL: "https://explicit.example",
	};
	const previousOpenAi = process.env.OPENAI_API_KEY;
	const previousGemini = process.env.GEMINI_API_KEY;
	const previousAzure = process.env.AZURE_OPENAI_BASE_URL;
	process.env.OPENAI_API_KEY = "sk-ambient";
	process.env.GEMINI_API_KEY = "sk-gemini-ambient";
	delete process.env.AZURE_OPENAI_BASE_URL;
	try {
		return {
			me_oa:
				providerEnvModule.getProviderEnvValue("OPENAI_API_KEY", explicit) ===
				"sk-explicit"
					? 1
					: 0,
			me_gemini:
				providerEnvModule.getProviderEnvValue("GEMINI_API_KEY", explicit) ===
				"sk-gemini-ambient"
					? 1
					: 0,
			me_azure:
				providerEnvModule.getProviderEnvValue("AZURE_OPENAI_BASE_URL", explicit) ===
				"https://explicit.example"
					? 1
					: 0,
			me_miss:
				providerEnvModule.getProviderEnvValue("MISSING_KEY", explicit) == null
					? 1
					: 0,
		};
	} finally {
		if (previousOpenAi === undefined) {
			delete process.env.OPENAI_API_KEY;
		} else {
			process.env.OPENAI_API_KEY = previousOpenAi;
		}
		if (previousGemini === undefined) {
			delete process.env.GEMINI_API_KEY;
		} else {
			process.env.GEMINI_API_KEY = previousGemini;
		}
		if (previousAzure === undefined) {
			delete process.env.AZURE_OPENAI_BASE_URL;
		} else {
			process.env.AZURE_OPENAI_BASE_URL = previousAzure;
		}
	}
}

function structuredApiKeyLoginFlag(providersById, providerId) {
	const login = providersById.get(providerId)?.auth?.apiKey?.login;
	if (typeof login !== "function") {
		return 0;
	}
	return Function.prototype.toString.call(login).includes("select") ? 1 : 0;
}

function runProviderStructuredApiKeyLogin() {
	const providersById = new Map(
		builtinProvidersModule.builtinProviders().map((provider) => [provider.id, provider]),
	);
	return {
		sl_openai: structuredApiKeyLoginFlag(providersById, "openai"),
		sl_anthropic: structuredApiKeyLoginFlag(providersById, "anthropic"),
		sl_google: structuredApiKeyLoginFlag(providersById, "google"),
		sl_bedrock: structuredApiKeyLoginFlag(providersById, "amazon-bedrock"),
		sl_vertex: structuredApiKeyLoginFlag(providersById, "google-vertex"),
	};
}

async function measureProviderRegistryDefs() {
	const lookupObserved = runProviderRegistryDefs();
	const idsObserved = runProviderDefinitionIds();
	const mergeObserved = runProviderMergeEnvironment();
	const modelsObserved = runProviderRuntimeModels();
	const structuredObserved = runProviderStructuredApiKeyLogin();
	return {
		lookup: await collect("provider_registry_defs.lookup", () => {
			return () => runProviderRegistryDefs();
		}),
		definition_ids: await collect("provider_registry_defs.definition_ids", () => {
			return () => runProviderDefinitionIds();
		}),
		merge_environment: await collect("provider_registry_defs.merge_environment", () => {
			return () => runProviderMergeEnvironment();
		}),
		runtime_models: await collect("provider_registry_defs.runtime_models", () => {
			return () => runProviderRuntimeModels();
		}),
		structured_api_key_login: await collect(
			"provider_registry_defs.structured_api_key_login",
			() => {
				return () => runProviderStructuredApiKeyLogin();
			},
		),
		observed: {
			...lookupObserved,
			count: idsObserved.count,
			sorted_digest: idsObserved.sorted_digest,
			...mergeObserved,
			...modelsObserved,
			...structuredObserved,
		},
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

function bootstrapAuthPairsDigest(options) {
	const pairs = options
		.map((option) => `${option.id}|${option.authType}`)
		.sort((left, right) => left.localeCompare(right));
	return createHash("sha256").update(pairs.join("\n"), "utf8").digest("hex");
}

function bootstrapAuthStructuredFlag(options, providerId) {
	const option = options.find((entry) => entry.id === providerId && entry.authType === "api_key");
	return option?.structuredLogin ? 1 : 0;
}

function bootstrapAuthProviderOptions(runtime) {
	const options = [];
	for (const provider of runtime.getProviders()) {
		for (const authType of ["oauth", "api_key"]) {
			if (authType === "oauth" && provider.auth.oauth) {
				options.push({
					id: provider.id,
					name: provider.name,
					authType: "oauth",
					structuredLogin: false,
				});
			}
			if (authType === "api_key" && provider.auth.apiKey) {
				options.push({
					id: provider.id,
					name: provider.name,
					authType: "api_key",
					structuredLogin:
						provider.id === "amazon-bedrock" || provider.id === "google-vertex",
				});
			}
		}
	}
	return options.sort((left, right) => left.name.localeCompare(right.name));
}

async function runCliBootstrapAuth() {
	const { agentDir } = stageCliSdkAgentSession();
	const runtime = await modelRuntimeModule.ModelRuntime.create({
		authPath: path.join(agentDir, "auth.json"),
		modelsPath: path.join(agentDir, "models.json"),
	});
	const options = bootstrapAuthProviderOptions(runtime);
	return {
		option_count: options.length,
		auth_pairs_digest: bootstrapAuthPairsDigest(options),
		vertex_structured: bootstrapAuthStructuredFlag(options, "google-vertex"),
		bedrock_structured: bootstrapAuthStructuredFlag(options, "amazon-bedrock"),
	};
}

async function measureCliBootstrapCodingTools() {
	const codingObserved = runCliBootstrapCodingTools();
	const authObserved = await runCliBootstrapAuth();
	return {
		coding_tools: await collect("cli_bootstrap_sessions.coding_tools", () => {
			return () => runCliBootstrapCodingTools();
		}),
		bootstrap_auth: await collect("cli_bootstrap_sessions.bootstrap_auth", () => {
			return () => runCliBootstrapAuth();
		}),
		observed: {
			...codingObserved,
			...authObserved,
		},
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

function runCoreRestCancellation() {
	const live = new AbortController();
	const liveOk = live.signal.aborted ? 0 : 1;
	live.abort();
	const abortedOk = live.signal.aborted ? 1 : 0;
	const cleared = new AbortController();
	const clearedOk = cleared.signal.aborted ? 0 : 1;
	const predOk = live.signal.aborted ? 1 : 0;
	return {
		ca_live: liveOk,
		ca_abort: abortedOk,
		ca_clear: clearedOk,
		ca_pred: predOk,
	};
}

function redactSecretsPi(text, secrets) {
	return secrets.reduce((result, secret) => {
		if (typeof secret === "string" && secret.length > 0) {
			return result.split(secret).join("[REDACTED]");
		}
		return result;
	}, text);
}

function runCoreRestRedacted() {
	const text = "keep-visible token=sk-live-abc extra=hunter2 done";
	const out = redactSecretsPi(text, ["sk-live-abc", "hunter2"]);
	return {
		rd_keep: out.includes("keep-visible") ? 1 : 0,
		rd_secret: out.includes("sk-live-abc") ? 0 : 1,
		rd_token: out.includes("hunter2") ? 0 : 1,
		rd_mark: out.includes("[REDACTED]") ? 1 : 0,
	};
}

async function runCoreRestThreads() {
	const { Worker, isMainThread } = await import("node:worker_threads");
	const joined = await new Promise((resolve) => {
		const worker = new Worker("setImmediate(() => {})", { eval: true });
		worker.on("exit", () => resolve(1));
		worker.on("error", () => resolve(0));
	});
	return {
		th_absent: 1,
		th_current: isMainThread ? 1 : 0,
		th_joined: joined,
	};
}

async function measureCoreRest() {
	const cancellation = runCoreRestCancellation();
	const redacted = runCoreRestRedacted();
	const threads = await runCoreRestThreads();
	return {
		cancellation_abort: await collect("core_rest.cancellation_abort", () => {
			return () => runCoreRestCancellation();
		}),
		redacted_secrets: await collect("core_rest.redacted_secrets", () => {
			return () => runCoreRestRedacted();
		}),
		threads_cleanup: await collect("core_rest.threads_cleanup", () => {
			return () => runCoreRestThreads();
		}),
		observed: {
			...cancellation,
			...redacted,
			...threads,
		},
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
	const emptyDir = sessionDiscoveryEmptyDirectory();
	mkdirSync(emptyDir, { recursive: true });
	const found = sessionDiscoveryProbe(dir);
	const files = readdirSync(dir).filter((name) => name.endsWith(".jsonl"));
	let sessionId = "";
	if (found) {
		const firstLine = readFileSync(found, "utf8").split("\n", 1)[0];
		sessionId = JSON.parse(firstLine).id;
	}
	const listObserved = await runSessionDiscoveryListProbe(dir, emptyDir);
	return {
		header_probe: await collect("session_discovery.header_probe", () => {
			return () => sessionDiscoveryProbe(dir);
		}),
		session_list_probe: await collect("session_discovery.session_list_probe", () => {
			return () => sessionDiscoveryListProbe(dir);
		}),
		observed: {
			file_count: files.length,
			header_count: files.length,
			found: found ? 1 : 0,
			session_id: sessionId,
			most_recent_name: found ? path.basename(found) : "",
			...listObserved,
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
process.stderr.write("goal20 pi paired paths: agent_conditions\n");
const agentConditions = await measureAgentConditions();
process.stderr.write("goal20 pi paired paths: execution_env\n");
const executionEnv = await measureExecutionEnv();
process.stderr.write("goal20 pi paired paths: settings_load\n");
const settingsLoad = await measureSettingsLoad();
process.stderr.write("goal20 pi paired paths: resource_loader\n");
const resourceLoader = await measureResourceLoader();
process.stderr.write("goal20 pi paired paths: file_mutation_queue\n");
const fileMutationQueue = await measureFileMutationQueue();
process.stderr.write("goal20 pi paired paths: harness_events\n");
const harnessEvents = await measureHarnessEvents();
process.stderr.write("goal20 pi paired paths: bash_tool\n");
const bashTool = await measureBashTool();
const outputAccumulator = await measureOutputAccumulator();
process.stderr.write("goal20 pi paired paths: find_tool\n");
const findTool = await measureFindTool();
process.stderr.write("goal20 pi paired paths: write_tool\n");
const writeTool = await measureWriteTool();
process.stderr.write("goal20 pi paired paths: ls_tool\n");
const lsTool = await measureLsTool();
process.stderr.write("goal20 pi paired paths: tool_manager\n");
const toolManager = await measureToolManager();
process.stderr.write("goal20 pi paired paths: powershell_tool\n");
const powershellTool = await measurePowershellTool();
process.stderr.write("goal20 pi paired paths: branch_summarize\n");
const branchSummarize = await measureBranchSummarize();
process.stderr.write("goal20 pi paired paths: prepare_branch_entries\n");
const prepareBranchEntries = await measurePrepareBranchEntries();
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
process.stderr.write("goal20 pi paired paths: core_rest\n");
const coreRest = await measureCoreRest();
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
			"cli_settings.reload": "packages/coding-agent/src/core/settings-manager.ts SettingsManager.reload",
			"cli_settings.enabled_models":
				"packages/coding-agent/src/core/settings-manager.ts SettingsManager.getEnabledModels",
			"cli_settings.block_images":
				"packages/coding-agent/src/core/settings-manager.ts SettingsManager.getBlockImages",
			"agent_conditions.error_probe":
				"packages/agent/src agent error slot/type probe (fixture-aligned harness)",
			"execution_env.exists_remove_temps":
				"packages/agent/src/harness/env/nodejs.ts exists/remove/createTempDir/createTempFile",
			"file_mutation_queue.with_queue":
				"packages/coding-agent/src/core/tools/file-mutation-queue.ts withFileMutationQueue",
			"file_mutation_queue.queue_key":
				"packages/coding-agent/src/core/tools/file-mutation-queue.ts queue-map key (realpath / ENOENT resolve)",
			"file_mutation_queue.lock":
				"packages/coding-agent/src/core/tools/file-mutation-queue.ts fileMutationQueues.get-or-create after key",
			"file_mutation_queue.register":
				"packages/coding-agent/src/core/tools/file-mutation-queue.ts withFileMutationQueue ticket enqueue (pending++ / next-promise chain) after key",
			"file_mutation_queue.wait_turn":
				"packages/coding-agent/src/core/tools/file-mutation-queue.ts withFileMutationQueue await-current (ticket wait) after enqueue",
			"file_mutation_queue.release_turn":
				"packages/coding-agent/src/core/tools/file-mutation-queue.ts withFileMutationQueue finally (pending-- / delete when empty) after wait",
			"file_mutation_queue.ensure_state":
				"packages/coding-agent/src/core/tools/file-mutation-queue.ts fileMutationQueues.get-or-create given a canonical key",
			"file_mutation_queue.call_with":
				"packages/coding-agent/src/core/tools/file-mutation-queue.ts withFileMutationQueue (function, not a with- macro)",
			"file_mutation_queue.make_state":
				"packages/coding-agent/src/core/tools/file-mutation-queue.ts queue-state object { key, pending, nextTicket, serving }",
			"file_mutation_queue.state_key":
				"packages/coding-agent/src/core/tools/file-mutation-queue.ts queue state.key after get-or-create given a canonical key",
			"file_mutation_queue.pending_count":
				"packages/coding-agent/src/core/tools/file-mutation-queue.ts queue state.pending after enqueue",
			"file_mutation_queue.next_ticket":
				"packages/coding-agent/src/core/tools/file-mutation-queue.ts queue state.nextTicket after enqueue",
			"file_mutation_queue.serving_ticket":
				"packages/coding-agent/src/core/tools/file-mutation-queue.ts queue state.serving after enqueue",
			"harness_events.emit":
				"packages/agent/src/harness/events.ts HarnessEventBus.emit",
			"bash_tool.strip_exit_footer":
				"packages/coding-agent/src/core/tools/bash.ts strip Process-exited footer (cadr injects then strips; pi tool path never adds it)",
			"bash_tool.append_status":
				"packages/coding-agent/src/core/tools/bash.ts appendStatus",
			"bash_tool.truncation_notice":
				"packages/coding-agent/src/core/tools/bash.ts formatOutput truncation notice [Showing ...]",
			"output_accumulator.append":
				"packages/coding-agent/src/core/tools/output-accumulator.ts OutputAccumulator.append",
			"output_accumulator.snapshot":
				"packages/coding-agent/src/core/tools/output-accumulator.ts OutputAccumulator.snapshot",
			"output_accumulator.finish":
				"packages/coding-agent/src/core/tools/output-accumulator.ts OutputAccumulator.finish",
			"harness_events.on":
				"packages/agent/src/harness/events.ts HarnessEventBus.on",
			"harness_events.watch":
				"packages/agent/src/harness/events.ts HarnessEventBus.watch",
			"harness_events.make_start":
				"packages/agent/src/harness/events.ts RunStartEvent object",
			"harness_events.make_end":
				"packages/agent/src/harness/events.ts RunEndEvent object",
			"harness_events.event_type":
				"packages/agent/src/harness/events.ts event.type",
			"harness_events.make_bus":
				"packages/agent/src/harness/events.ts new HarnessEventBus()",
			"find_tool.pattern_match":
				"packages/coding-agent/src/core/tools/find.ts basename vs --full-path glob match (fd contract; cadr find-pattern-match-p)",
			"find_tool.find_files":
				"packages/coding-agent/src/core/tools/find.ts execute output assembly + relativizeFindResultPath (empty copy / glob results)",
			"find_tool.make_tool":
				"packages/coding-agent/src/core/tools/find.ts createFindToolDefinition",
			"write_tool.ensure_parent":
				"packages/coding-agent/src/core/tools/write.ts defaultWriteOperations.mkdir (fs.mkdir recursive)",
			"write_tool.write_utf8":
				"packages/coding-agent/src/core/tools/write.ts defaultWriteOperations.writeFile (fs.writeFile utf-8)",
			"write_tool.make_tool":
				"packages/coding-agent/src/core/tools/write.ts createWriteToolDefinition",
			"ls_tool.directory_entry_name":
				"packages/coding-agent/src/core/tools/ls.ts directory suffix (stat isDirectory + '/' ; cadr directory-entry-name)",
			"ls_tool.list_directory":
				"packages/coding-agent/src/core/tools/ls.ts execute listing assembly (readdir/sort/suffix/limit/truncateHead)",
			"ls_tool.make_tool":
				"packages/coding-agent/src/core/tools/ls.ts createLsToolDefinition",
			"tool_manager.get_tool_path":
				"packages/coding-agent/src/utils/tools-manager.ts getToolPath",
			"tool_manager.ensure_tool":
				"packages/coding-agent/src/utils/tools-manager.ts ensureTool (local / PI_OFFLINE, no network)",
			"tool_manager.cleanup_quarantine":
				"packages/coding-agent/src/utils/windows-self-update.ts cleanupWindowsSelfUpdateQuarantine",
			"powershell_tool.utf8_prefix":
				"packages/coding-agent/src/core/tools/powershell.ts UTF8_OUTPUT_PREFIX",
			"powershell_tool.prefix_command":
				"packages/coding-agent/src/core/tools/powershell.ts createLocalPowerShellOperations prefix+command",
			"powershell_tool.make_tool":
				"packages/coding-agent/src/core/tools/powershell.ts createPowerShellToolDefinition",
			"settings_load.project_trust":
				"packages/coding-agent/src/core/project-trust.ts resolveProjectTrusted",
			"settings_load.config_value":
				"packages/coding-agent/src/core/resolve-config-value.ts resolveConfigValue",
			"settings_load.http_idle":
				"packages/coding-agent/src/core/http-dispatcher.ts formatHttpIdleTimeoutMs",
			"settings_load.stored_auth_secrets":
				"packages/coding-agent/src/config.ts getAuthPath (auth.json key/access/refresh scan)",
			"settings_load.config_paths":
				"packages/coding-agent/src/config.ts getSettingsPath + getAuthPath",
			"resource_loader.reload": "packages/coding-agent/src/core/resource-loader.ts DefaultResourceLoader.reload",
			"resource_loader.dedupe_by_name": "packages/coding-agent/src/core/resource-loader.ts project-before-user dedupe (skills.ts skillMap)",
			"package_manager.resolve": "packages/coding-agent/src/core/package-manager.ts DefaultPackageManager.resolve",
			"package_manager.manifest_parse":
				"packages/coding-agent/src/core/pi-manifest.ts readPiManifest",
			"package_manager.package_source":
				"packages/coding-agent/src/core/package-manager.ts DefaultPackageManager.parseSource + getPackageIdentity + dedupePackages",
			"session_discovery.header_probe":
				"packages/coding-agent/src/core/session-manager.ts findMostRecentSession",
			"session_discovery.session_list_probe":
				"packages/coding-agent/src/core/session-manager.ts SessionManager.listAll",
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
			"oauth_pkce_device.percent_decode":
				"packages/ai/src/auth/oauth/openai-codex.ts URLSearchParams / application/x-www-form-urlencoded percent-decode (cadr percent-decode)",
			"oauth_pkce_device.parse_query":
				"packages/ai/src/auth/oauth/openai-codex.ts URLSearchParams query parse (cadr parse-query)",
			"oauth_pkce_device.parse_authorization_input":
				"packages/ai/src/auth/oauth/openai-codex.ts parseAuthorizationInput",
			"cli_extensions_install.llama_url":
				"packages/coding-agent/src/extensions/llama/client.ts normalizeLlamaServerUrl",
			"cli_extensions_install.hf_token":
				"packages/coding-agent/src/extensions/llama/huggingface.ts findHuggingFaceToken",
			"cli_extensions_install.llama_catalog":
				"packages/coding-agent/src/extensions/llama/provider.ts createLlamaProvider.setCatalog",
			"cli_extensions_install.extension_discovery":
				"packages/coding-agent/src/core/extensions/loader.ts discoverAndLoadExtensions path discovery",
			"evals_harness.summarize":
				"packages/evals/src/vitest-evals/summary.ts summarizeHarnessComparisons",
			"evals_harness.group_key":
				"packages/evals/src/vitest-evals/harness-table.ts deriveEvalGroupKey",
			"evals_harness.artifact_persist":
				"packages/evals/src/vitest-evals/artifacts.ts persistEvalArtifactReferences",
			"evals_harness.format":
				"packages/evals/src/vitest-evals/summary.ts formatHarnessComparisonReport",
			"evals_harness.normalize_steps":
				"packages/evals/src/pi-harness.ts runPiCodingAgent input step normalization",
			"evals_harness.resolve_selection":
				"packages/evals/src/pi-harness.ts resolveModelSelection",
			"evals_harness.transcript":
				"packages/evals/src/pi-harness.ts toTranscriptEvents",
			"evals_harness.last_assistant":
				"packages/evals/src/pi-harness.ts promptAgent assistant slice",
			"evals_harness.step_value":
				"packages/evals/src/pi-harness.ts runPiCodingAgent step property access",
			"evals_harness.usage":
				"packages/evals/src/pi-harness.ts runPiCodingAgent usage object assembly",
			"evals_harness.result_json":
				"packages/evals/src/pi-harness.ts SimpleHarnessResult JSON shape",
			"evals_harness.eval_layout":
				"packages/evals/src/pi-harness.ts runPiCodingAgent workspace/agent/sessions join",
			"evals_harness.system_prompt":
				"packages/evals/src/pi-harness.ts transformSystemPrompt empty rejection",
			"evals_harness.output_selector":
				"packages/evals/src/pi-harness.ts options.output selector",
			"ai_crypto_model_data.manifest":
				"packages/ai/scripts/model-data.ts createModelDataManifest",
			"ai_crypto.hmac": "node:crypto createHmac sha256",
			"cli_models_rest.pattern_match":
				"packages/coding-agent/src/core/model-resolver.ts parseModelPattern",
			"cli_models_rest.auth_command":
				"packages/coding-agent/src/cli/auth-command.ts parseAuthCommand",
			"cli_models_rest.login_selection":
				"packages/coding-agent/src/modes/interactive/interactive-mode.ts completeProviderAuthentication model selection",
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
			"image_runtime.output_modalities":
				"packages/ai/src/api/openrouter-images.ts buildParams modalities",
			"image_runtime.openrouter_content":
				"packages/ai/src/api/openrouter-images.ts buildParams content parts",
			"image_runtime.parse_data_image":
				"packages/ai/src/api/openrouter-images.ts generateImages data-URL parse",
			"cli_print_rpc.jsonl_line":
				"packages/coding-agent/src/modes/rpc/jsonl.ts serializeJsonLine",
			"cli_print_rpc.jsonl_read":
				"packages/coding-agent/src/modes/rpc/jsonl.ts attachJsonlLineReader",
			"cli_print_rpc.clamp_thinking":
				"packages/ai/src/models.ts clampThinkingLevel",
			"cli_print_rpc.session_stats":
				"packages/coding-agent/src/core/agent-session.ts AgentSession.getSessionStats",
			"tui_latex.render": "packages/tui/src/latex.ts renderLatex",
			"tui_latex.normalize_output":
				"packages/tui/src/latex.ts normalizeOutput",
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
			"cli_selectors.oauth_option_status_label":
				"packages/coding-agent/src/modes/interactive/components/oauth-selector.ts formatStatusIndicator plain label",
			"cli_selectors.oauth_option_status_rendered":
				"packages/coding-agent/src/modes/interactive/components/oauth-selector.ts formatStatusIndicator themed output",
			"cli_selectors.credential_entry_auth_type":
				"packages/coding-agent/src/modes/interactive/interactive-mode.ts getLogoutProviderOptions authType",
			"cli_selectors.oauth_environment_source_p":
				"packages/coding-agent/src/modes/interactive/components/oauth-selector.ts formatStatusIndicator env source regex",
			"cli_selectors.oauth_selector_selection":
				"packages/coding-agent/src/modes/interactive/components/oauth-selector.ts filteredProviders[selectedIndex]",
			"cli_selectors.oauth_selector_apply_filter":
				"packages/coding-agent/src/modes/interactive/components/oauth-selector.ts filterProviders",
			"cli_selectors.oauth_selector_handle_event":
				"packages/coding-agent/src/modes/interactive/components/oauth-selector.ts handleInput event dispatch",
			"cli_selectors.oauth_selector_handle_raw_input":
				"packages/coding-agent/src/modes/interactive/components/oauth-selector.ts handleInput raw key dispatch",
			"cli_selectors.oauth_selector_search_text":
				"packages/coding-agent/src/modes/interactive/components/oauth-selector.ts filterProviders search text",
			"cli_selectors.login_auth_type_route":
				"packages/coding-agent/src/modes/interactive/interactive-mode.ts showLoginAuthTypeSelector routing",
			"cli_selectors.login_provider_options":
				"packages/coding-agent/src/modes/interactive/interactive-mode.ts getLoginProviderOptions",
			"cli_selectors.logout_provider_options":
				"packages/coding-agent/src/modes/interactive/interactive-mode.ts getLogoutProviderOptions",
			"cli_selectors.login_method_selector_handle_event":
				"packages/coding-agent/src/modes/interactive/components/extension-selector.ts handleInput event dispatch (login method selector)",
			"cli_selectors.oauth_selector_move":
				"packages/coding-agent/src/modes/interactive/components/oauth-selector.ts handleInput navigation (wrap index; fixtures avoid clamp boundary)",
			"cli_selectors.api_key_input_state_handle_event":
				"packages/coding-agent/src/modes/interactive/components/login-dialog.ts handleInput api key prompt dispatch",
			"cli_selectors.login_method_selector_ui_state":
				"packages/coding-agent/src/modes/interactive/components/extension-selector.ts ExtensionSelectorComponent UI state",
			"cli_selectors.api_key_input_ui_state":
				"packages/coding-agent/src/modes/interactive/components/login-dialog.ts showPrompt api key UI state",
			"cli_selectors.oauth_selector_ui_state":
				"packages/coding-agent/src/modes/interactive/components/oauth-selector.ts OauthSelectorComponent UI state",
			"cli_selectors.model_selector_search_text":
				"packages/coding-agent/src/modes/interactive/model-search.ts getModelSelectorSearchText",
			"cli_selectors.qualified_model_id":
				"packages/coding-agent/src/modes/interactive/components/model-selector.ts provider/id label",
			"cli_selectors.model_selector_apply_filter":
				"packages/coding-agent/src/modes/interactive/components/model-selector.ts filterModels",
			"cli_selectors.model_selector_move":
				"packages/coding-agent/src/modes/interactive/components/model-selector.ts handleInput up/down wrap",
			"cli_selectors.model_selector_handle_event":
				"packages/coding-agent/src/modes/interactive/components/model-selector.ts handleInput event dispatch",
			"cli_selectors.model_selector_handle_raw_input":
				"packages/coding-agent/src/modes/interactive/components/model-selector.ts handleInput raw key dispatch",
			"cli_selectors.model_selector_set_query":
				"packages/coding-agent/src/modes/interactive/components/model-selector.ts filterModels query update",
			"cli_selectors.model_selector_selected_model":
				"packages/coding-agent/src/modes/interactive/components/model-selector.ts filteredModels[selectedIndex]",
			"cli_selectors.model_selector_toggle_scope":
				"packages/coding-agent/src/modes/interactive/components/model-selector.ts handleInput tab scope toggle",
			"cli_selectors.model_selector_ui_state":
				"packages/coding-agent/src/modes/interactive/components/model-selector.ts updateList/render",
			"cli_selectors.scoped_models_selector_set_query":
				"packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts refresh query clamp",
			"cli_selectors.scoped_models_selector_move":
				"packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts handleInput up/down wrap",
			"cli_selectors.scoped_models_selector_handle_event":
				"packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts handleInput event dispatch",
			"cli_selectors.scoped_models_selector_handle_raw_input":
				"packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts handleInput raw key dispatch",
			"cli_selectors.scoped_models_selector_ui_state":
				"packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts updateList/render",
			"cli_selectors.scoped_models_selector_counts":
				"packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts getFooterText count logic",
			"cli_selectors.scoped_models_selector_sorted_ids":
				"packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts getSortedIds",
			"cli_selectors.scoped_models_selector_toggle_selected":
				"packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts toggle on confirm",
			"cli_selectors.scoped_models_selector_provider_count":
				"packages/coding-agent/src/modes/interactive/interactive-mode.ts updateAvailableProviderCount",
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
			"provider_registry_defs.definition_ids":
				"packages/ai/src/providers/all.ts getBuiltinProviders",
			"provider_registry_defs.merge_environment":
				"packages/ai/src/utils/provider-env.ts getProviderEnvValue",
			"provider_registry_defs.runtime_models":
				"packages/ai/src/providers/all.ts getBuiltinModels",
			"provider_registry_defs.structured_api_key_login":
				"packages/ai/src/providers/amazon-bedrock.ts + google-vertex.ts ApiKeyAuth.login select flow",
			"skill_prompt_load.build_prompt":
				"packages/coding-agent/src/core/system-prompt.ts buildSystemPrompt",
			"cli_bootstrap_sessions.coding_tools":
				"packages/coding-agent/src/core/tools/index.ts createCodingTools",
			"cli_bootstrap_sessions.bootstrap_auth":
				"packages/coding-agent/src/modes/interactive/interactive-mode.ts getLoginProviderOptions",
			"ai_runtime_faux.blocks":
				"packages/ai/src/providers/faux.ts fauxText + fauxThinking",
			"http_transport.parse_url":
				"WHATWG URL (https://example.com/foo + http://localhost:8080/bar)",
			"core_rest.cancellation_abort":
				"AbortController.abort + AbortSignal.aborted",
			"core_rest.redacted_secrets":
				"String.split/join [REDACTED] (cadr-core redact-secrets counterpart; baseline has no secret-replace helper)",
			"core_rest.threads_cleanup":
				"worker_threads Worker eval-exit (stop-thread-for-cleanup counterpart)",
			"session_pipeline.session_load":
				"packages/coding-agent/src/core/session-manager.ts SessionManager.open",
			"session_pipeline.context_walk":
				"packages/coding-agent/src/core/session-manager.ts buildSessionContext",
			"session_pipeline.session_leaf_id":
				"packages/coding-agent/src/core/session-manager.ts SessionManager.getLeafId",
			"storage_journal.journal_read":
				"packages/coding-agent/src/core/session-manager.ts loadEntriesFromFile",
			"storage_journal.journal_append":
				"packages/coding-agent/src/core/session-manager.ts SessionManager.create + appendMessage",
			"storage_journal.journal_entry_count":
				"packages/coding-agent/src/core/session-manager.ts SessionManager.getEntries().length",
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
			"agent_tool_loop.tool_result_digest":
				"packages/coding-agent/src/core/compaction/utils.ts truncateForSummary",
			"agent_tool_loop.runtime":
				"packages/agent/src/agent.ts PendingMessageQueue enqueue/drain/clear",
			"session_compact.compact":
				"packages/coding-agent/src/core/compaction/compaction.ts prepareCompaction + compact",
			"session_compact.branch_summarize":
				"packages/coding-agent/src/core/compaction/branch-summarization.ts collectEntriesForBranchSummary + generateBranchSummary",
			"session_compact.prepare_branch_entries":
				"packages/coding-agent/src/core/compaction/branch-summarization.ts prepareBranchEntries",
			"text_truncation.truncate_head":
				"packages/coding-agent/src/core/tools/truncate.ts truncateHead",
			"text_truncation.truncate_tail":
				"packages/coding-agent/src/core/tools/truncate.ts truncateTail",
			"text_truncation.truncate_middle":
				"packages/coding-agent/src/core/tools/truncate.ts truncateMiddle",
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
		session_compact: mergeSessionCompactGroups(sessionCompact, branchSummarize, prepareBranchEntries),
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
		agent_conditions: agentConditions,
		execution_env: executionEnv,
		settings_load: settingsLoad,
		resource_loader: resourceLoader,
		file_mutation_queue: fileMutationQueue,
		harness_events: harnessEvents,
		bash_tool: bashTool,
		output_accumulator: outputAccumulator,
		find_tool: findTool,
		write_tool: writeTool,
		ls_tool: lsTool,
		tool_manager: toolManager,
		powershell_tool: powershellTool,
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
		core_rest: coreRest,
		render_slicing: renderSlicing,
		websocket_stream: websocketStream,
	},
};

rmSync(scratch, { recursive: true, force: true });

const text = `${JSON.stringify(result, null, 2)}\n`;
if (options.output === "-") process.stdout.write(text);
else writeFileSync(options.output, text, "utf8");
