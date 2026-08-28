#!/usr/bin/env python3
"""Regenerate the Goal 20 Part B time series in docs/performance.md.

Reads docs/benchmarks/performance-history.json, the adjudicated Part A
drift bands from docs/benchmarks/goal20-part-a-noise-bands.json, and
docs/benchmarks/goal20-paired-paths.json. Never hand-edits numbers.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

START = "<!-- GOAL20_PERF_HISTORY_START -->"
END = "<!-- GOAL20_PERF_HISTORY_END -->"
PAIRED_START = "<!-- GOAL20_PAIRED_PATHS_START -->"
PAIRED_END = "<!-- GOAL20_PAIRED_PATHS_END -->"

METRIC_KEYS = (
    "cli_dispatch.argv_parse",
    "cli_dispatch.help_render",
    "cli_dispatch.list_models_registry",
    "cli_dispatch.list_models_render",
    "provider_stream.stream_roundtrip",
    "provider_anthropic.stream_roundtrip",
    "provider_google.stream_roundtrip",
    "provider_bedrock.stream_roundtrip",
    "provider_mistral.stream_roundtrip",
    "provider_openai_responses.stream_roundtrip",
    "provider_azure_openai.stream_roundtrip",
    "provider_vertex.stream_roundtrip",
    "provider_codex.stream_roundtrip",
    "provider_pi_messages.stream_roundtrip",
    "cli_settings.create",
    "cli_settings.reload",
    "cli_settings.enabled_models",
    "cli_settings.block_images",
    "cli_settings.default_model",
    "cli_settings.default_provider",
    "cli_settings.output_padding",
    "agent_conditions.error_probe",
    "execution_env.exists_remove_temps",
    "execution_env.absolute_path",
    "execution_env.join_path",
    "execution_env.file_info",
    "file_mutation_queue.with_queue",
    "file_mutation_queue.queue_key",
    "file_mutation_queue.lock",
    "file_mutation_queue.register",
    "file_mutation_queue.wait_turn",
    "file_mutation_queue.release_turn",
    "file_mutation_queue.ensure_state",
    "file_mutation_queue.call_with",
    "file_mutation_queue.make_state",
    "file_mutation_queue.state_key",
    "file_mutation_queue.pending_count",
    "file_mutation_queue.next_ticket",
    "file_mutation_queue.serving_ticket",
    "harness_events.emit",
    "bash_tool.strip_exit_footer",
    "bash_tool.append_status",
    "bash_tool.truncation_notice",
    "output_accumulator.append",
    "output_accumulator.snapshot",
    "output_accumulator.finish",
    "harness_events.on",
    "harness_events.watch",
    "harness_events.make_start",
    "harness_events.make_end",
    "harness_events.event_type",
    "harness_events.make_bus",
    "find_tool.pattern_match",
    "find_tool.find_files",
    "find_tool.make_tool",
    "write_tool.ensure_parent",
    "write_tool.write_utf8",
    "write_tool.make_tool",
    "grep_tool.match_event",
    "grep_tool.line_text",
    "grep_tool.make_tool",
    "ls_tool.directory_entry_name",
    "ls_tool.list_directory",
    "ls_tool.make_tool",
    "tool_manager.get_tool_path",
    "tool_manager.ensure_tool",
    "tool_manager.cleanup_quarantine",
    "tool_manager.release_asset",
    "tool_manager.find_binary",
    "tool_manager.quarantine_native",
    "powershell_tool.utf8_prefix",
    "powershell_tool.prefix_command",
    "powershell_tool.make_tool",
    "settings_load.project_trust",
    "settings_load.config_value",
    "settings_load.http_idle",
    "settings_load.stored_auth_secrets",
    "settings_load.config_paths",
    "resource_loader.reload",
    "resource_loader.dedupe_by_name",
    "resource_loader.context_from_dir",
    "resource_loader.project_context",
    "resource_loader.nearest_config",
    "package_manager.resolve",
    "package_manager.manifest_parse",
    "package_manager.package_source",
    "session_discovery.header_probe",
    "session_discovery.session_list_probe",
    "session_export_html.to_html",
    "protocol_cbor.roundtrip",
    "agent_schema.validate_ok_fail",
    "harness_storage.open_walk",
    "protocol_codec.roundtrip",
    "agent_proxy.stream_roundtrip",
    "oauth_pkce.challenge_urls",
    "oauth_pkce_device.poll",
    "oauth_pkce_device.auth_json",
    "oauth_pkce_device.copilot_url",
    "oauth_pkce_device.cloudflare_url",
    "oauth_pkce_device.radius_gateway",
    "oauth_pkce_device.copilot_auth",
    "oauth_pkce_device.percent_decode",
    "oauth_pkce_device.parse_query",
    "oauth_pkce_device.parse_authorization_input",
    "oauth_pkce_device.provider_key",
    "oauth_pkce_device.http_status_text",
    "oauth_pkce_device.parse_callback_request",
    "cli_extensions_install.llama_url",
    "cli_extensions_install.hf_token",
    "cli_extensions_install.llama_catalog",
    "cli_extensions_install.extension_discovery",
    "evals_harness.summarize",
    "evals_harness.group_key",
    "evals_harness.artifact_persist",
    "evals_harness.format",
    "evals_harness.normalize_steps",
    "evals_harness.resolve_selection",
    "evals_harness.transcript",
    "evals_harness.last_assistant",
    "evals_harness.step_value",
    "evals_harness.usage",
    "evals_harness.result_json",
    "evals_harness.eval_environment",
    "evals_harness.prompt_step",
    "evals_harness.reload_step",
    "evals_harness.make_eval_root",
    "evals_harness.normalize_step_type",
    "evals_harness.selected_eval_tools",
    "evals_harness.prompt_eval_agent",
    "evals_harness.reload_shutdown",
    "evals_harness.run_coding_agent_eval",
    "oauth_pkce_device.base64url_value",
    "oauth_pkce_device.base64url_decode",
    "oauth_pkce_device.account_id",
    "evals_harness.content_text",
    "evals_harness.transcript_event",
    "evals_harness.elapsed",
    "core_rest.cancellation_make",
    "core_rest.cancellation_aborted",
    "core_rest.cancellation_set",
    "evals_harness.release_extensions",
    "evals_harness.agent_tools",
    "evals_harness.extension_paths",
    "edit_tool.normalize_line_endings",
    "edit_tool.restore_line_endings",
    "edit_tool.make_tool",
    "evals_harness.argument_prefix",
    "evals_harness.parse_arguments",
    "evals_harness.validate_smoke",
    "oauth_pkce_device.error_detail",
    "oauth_pkce_device.ensure_success",
    "oauth_pkce_device.notify_device",
    "evals_harness.eval_result",
    "evals_harness.root_observer",
    "evals_harness.model_resolver",
    "ai_crypto_model_data.manifest",
    "ai_crypto.hmac",
    "cli_models_rest.pattern_match",
    "cli_models_rest.auth_command",
    "cli_models_rest.login_selection",
    "image_runtime.dimensions",
    "image_runtime.mime_type",
    "image_runtime.lookup",
    "image_runtime.dimension_note",
    "image_runtime.api_provider",
    "image_runtime.output_modalities",
    "image_runtime.openrouter_content",
    "image_runtime.parse_data_image",
    "image_runtime.openrouter_usage",
    "image_runtime.parse_openrouter_images",
    "image_runtime.error_result",
    "cli_print_rpc.jsonl_line",
    "cli_print_rpc.jsonl_read",
    "cli_print_rpc.clamp_thinking",
    "cli_print_rpc.session_stats",
    "tui_latex.render",
    "tui_latex.normalize_output",
    "tui_mermaid.render",
    "tui_mermaid.source_box",
    "tui_mermaid.transform",
    "tui_editor_helpers.fuzzy_match",
    "tui_theme_overlay.osc11_bg",
    "tui_theme_overlay.rgb_to_ansi_256",
    "tui_theme_overlay.parse_hex_color",
    "tui_theme_overlay.theme_foreground_ansi",
    "ai_support.estimate_text",
    "ai_support.context_overflow",
    "ai_support.grammar_delta",
    "ai_support.uuid_v7",
    "ai_support.auth_guidance",
    "tui_select_settings_loaders.filter",
    "tui_select_settings_loaders.loader_frames",
    "tui_select_settings_loaders.loader_interval",
    "tui_select_settings_loaders.loader_step",
    "tui_word_navigation.step",
    "tui_overlay.composite_line",
    "tui_kill_ring.push_peek",
    "tui_undo_stack.push_pop",
    "tui_autocomplete.suggest_apply",
    "tui_keybindings.resolve_match",
    "tui_stdin_buffer.process",
    "tui_input_component.edit",
    "tui_native_modifiers.pressed",
    "tui_settings_list.apply_filter",
    "ai_capabilities.short_hash",
    "ai_capabilities.deferred_tools",
    "ai_capabilities.event_stream",
    "ai_capabilities.http_proxy",
    "ai_capabilities.session_resources",
    "cli_support.strip_ansi",
    "cli_support.normalize_path",
    "cli_support.timings",
    "cli_support.event_bus",
    "cli_support.attribution_headers",
    "cli_support.shell_config",
    "cli_support.sanitize_output",
    "cli_support.git_source",
    "cli_support.user_agent",
    "cli_support.parse_changelog",
    "cli_support.experimental",
    "cli_interactive_controller.decode_entity",
    "cli_interactive_controller.wayland",
    "cli_interactive_controller.cwd_footer",
    "cli_interactive_controller.auth_type",
    "cli_interactive_controller.parse_auto_theme",
    "cli_interactive_controller.resolve_theme",
    "cli_selectors.session_search",
    "cli_selectors.key_text",
    "cli_selectors.fuzzy_filter",
    "cli_selectors.delete_query",
    "cli_selectors.visible_slice",
    "cli_selectors.move_index",
    "cli_selectors.align_left_right",
    "cli_selectors.fit_line",
    "cli_selectors.border_line",
    "cli_selectors.selected_line",
    "cli_selectors.muted_line",
    "cli_selectors.dim_line",
    "cli_selectors.modified_cursor_key",
    "cli_selectors.title_line",
    "cli_selectors.overlay_title_line",
    "cli_selectors.input_line",
    "cli_selectors.keybinding_text",
    "cli_selectors.keybinding_hint",
    "cli_selectors.session_format_age",
    "cli_selectors.session_record_label",
    "cli_selectors.session_shorten_path",
    "cli_selectors.session_quoted_search",
    "cli_selectors.session_thread_records",
    "cli_selectors.session_binding_label",
    "cli_selectors.session_same_path",
    "cli_selectors.session_quoted_p",
    "cli_selectors.session_named_p",
    "cli_selectors.settings_thinking_description",
    "cli_selectors.settings_display_value",
    "cli_selectors.settings_automatic_theme_setting",
    "cli_selectors.settings_active_automatic_theme",
    "cli_selectors.settings_cycle",
    "cli_selectors.settings_apply_filter",
    "cli_selectors.tree_entry_filtered",
    "cli_selectors.tree_query_matches",
    "cli_selectors.tree_entry_search_text",
    "cli_selectors.tree_settings_entry_p",
    "cli_selectors.tree_normalize_display_text",
    "cli_selectors.tree_status_labels",
    "cli_selectors.tree_shorten_path",
    "cli_selectors.tree_foldable_p",
    "cli_selectors.tree_tool_argument",
    "cli_selectors.tree_cycle_filter",
    "cli_selectors.tree_format_label_timestamp",
    "cli_selectors.tree_format_tool_call",
    "cli_selectors.tree_entry_display_text",
    "cli_selectors.tree_prefix",
    "cli_selectors.tree_visual_nodes",
    "cli_selectors.tree_horizontal_viewport",
    "cli_selectors.tree_help_keys",
    "cli_selectors.tree_help_key",
    "cli_selectors.tree_app_key_p",
    "cli_selectors.tree_help_lines",
    "cli_selectors.tree_active_path",
    "cli_selectors.tree_nearest_visible_id",
    "cli_selectors.tree_prioritize_active",
    "cli_selectors.tree_entry_map",
    "cli_selectors.tree_order_entries",
    "cli_selectors.tree_iso_timestamp",
    "cli_selectors.tree_rebuild_visible_maps",
    "cli_selectors.tree_apply_filter",
    "cli_selectors.tree_render_lines",
    "cli_selectors.tree_move",
    "cli_selectors.tree_fold_or_up",
    "cli_selectors.tree_unfold_or_down",
    "cli_selectors.tree_branch_segment_id",
    "cli_selectors.tree_set_query",
    "cli_selectors.tree_set_filter",
    "cli_selectors.tree_copy_selected",
    "cli_selectors.tree_toggle_label_timestamps",
    "cli_selectors.tree_start_label_edit",
    "cli_selectors.tree_confirm_label",
    "cli_selectors.tree_cancel_label",
    "cli_selectors.tree_handle_raw_input",
    "cli_selectors.tree_handle_event",
    "cli_selectors.tree_handle_label_event",
    "cli_selectors.tree_selected_entry",
    "cli_selectors.tree_selected_id",
    "cli_selectors.tree_select_id",
    "cli_selectors.tree_visible_ids",
    "cli_selectors.project_trust_options",
    "cli_selectors.trust_selector_selection",
    "cli_selectors.trust_decision_description",
    "cli_selectors.trust_selector_move",
    "cli_selectors.trust_selector_handle_event",
    "cli_selectors.trust_selector_handle_raw_input",
    "cli_selectors.trust_selector_ui_state",
    "cli_selectors.oauth_option_status_label",
    "cli_selectors.oauth_option_status_rendered",
    "cli_selectors.credential_entry_auth_type",
    "cli_selectors.oauth_environment_source_p",
    "cli_selectors.oauth_selector_selection",
    "cli_selectors.oauth_selector_apply_filter",
    "cli_selectors.oauth_selector_handle_event",
    "cli_selectors.oauth_selector_handle_raw_input",
    "cli_selectors.oauth_selector_search_text",
    "cli_selectors.login_auth_type_route",
    "cli_selectors.login_provider_options",
    "cli_selectors.logout_provider_options",
    "cli_selectors.login_method_selector_handle_event",
    "cli_selectors.oauth_selector_move",
    "cli_selectors.api_key_input_state_handle_event",
    "cli_selectors.login_method_selector_ui_state",
    "cli_selectors.api_key_input_ui_state",
    "cli_selectors.oauth_selector_ui_state",
    "cli_selectors.model_selector_search_text",
    "cli_selectors.qualified_model_id",
    "cli_selectors.model_selector_apply_filter",
    "cli_selectors.model_selector_move",
    "cli_selectors.model_selector_handle_event",
    "cli_selectors.model_selector_handle_raw_input",
    "cli_selectors.model_selector_set_query",
    "cli_selectors.model_selector_selected_model",
    "cli_selectors.model_selector_toggle_scope",
    "cli_selectors.model_selector_ui_state",
    "cli_selectors.scoped_models_selector_set_query",
    "cli_selectors.scoped_models_selector_move",
    "cli_selectors.scoped_models_selector_handle_event",
    "cli_selectors.scoped_models_selector_handle_raw_input",
    "cli_selectors.scoped_models_selector_ui_state",
    "cli_selectors.scoped_models_selector_sorted_ids",
    "cli_selectors.scoped_models_selector_counts",
    "cli_selectors.scoped_models_selector_toggle_selected",
    "cli_selectors.scoped_models_selector_target_ids",
    "cli_selectors.scoped_models_selector_enable_all",
    "cli_selectors.scoped_models_selector_toggle_provider",
    "cli_selectors.scoped_models_selector_clear_all",
    "cli_selectors.scoped_models_selector_reorder",
    "cli_selectors.scoped_models_selector_persist",
    "cli_selectors.scoped_models_selector_provider_count",
    "websocket_stream.stream_roundtrip",
    "cli_sdk.version_newer",
    "cli_sdk.cache_miss",
    "cli_sdk.cache_waste",
    "cli_sdk.thinking_level",
    "cli_sdk.session_list",
    "cli_sdk.agent_session",
    "cli_sdk.session_services",
    "cli_sdk.model_runtime",
    "provider_registry_defs.lookup",
    "provider_registry_defs.definition_ids",
    "provider_registry_defs.merge_environment",
    "provider_registry_defs.runtime_models",
    "provider_registry_defs.structured_api_key_login",
    "provider_registry_defs.api_key_strategy",
    "provider_registry_defs.provider_options",
    "provider_registry_defs.strip_runtime_options",
    "core_rest.cancellation_abort",
    "core_rest.redacted_secrets",
    "core_rest.threads_cleanup",
    "core_rest.cancellation_predicate",
    "core_rest.redacted_register",
    "core_rest.redacted_replace",
    "skill_prompt_load.build_prompt",
    "cli_bootstrap_sessions.coding_tools",
    "cli_bootstrap_sessions.bootstrap_auth",
    "ai_runtime_faux.blocks",
    "http_transport.parse_url",
    "core_rest.cancellation_wait",
    "core_rest.redacted_types",
    "core_rest.threads_join",
    "session_pipeline.session_load",
    "session_pipeline.context_walk",
    "session_pipeline.session_leaf_id",
    "storage_journal.journal_read",
    "storage_journal.journal_append",
    "storage_journal.journal_entry_count",
    "sqlite_session.open_walk",
    "tool_read.text_file",
    "tool_grep.context_file",
    "agent_tool_loop.roundtrip",
    "agent_tool_loop.tool_path",
    "agent_tool_loop.line_ending",
    "agent_tool_loop.tool_result_digest",
    "agent_tool_loop.runtime",
    "session_compact.compact",
    "session_compact.branch_summarize",
    "session_compact.prepare_branch_entries",
    "text_truncation.truncate_middle",
)

HISTORY_RATIO_KEYS = (
    "storage_journal.journal_append",
    "storage_journal.journal_read",
    "session_pipeline.session_load",
    "cli_dispatch.list_models_render",
)


def format_us(value: float | None) -> str:
    if value is None:
        return "—"
    return f"{value:,.1f}"


def format_bytes(value: float | None) -> str:
    if value is None:
        return "—"
    return f"{value:,.0f}"


def format_ratio(value: float | None) -> str:
    if value is None:
        return "—"
    return f"{value:.2f}×"


def short_git(value: object) -> str:
    git = str(value or "—")
    hexish = git.lower().startswith(tuple("0123456789abcdef")) and len(git) >= 40
    if hexish:
        return git[:12]
    return git


def render_band_lines(bands: dict | None) -> list[str]:
    if not bands:
        return [
            "The adjudicated bands file",
            "`docs/benchmarks/goal20-part-a-noise-bands.json` was not readable",
            "when this section was generated; the drift gate fails closed",
            "without it.",
        ]
    lines = [
        "Part A drift bands (adjudicated 2026-08-14, shape `max(floor, 6*MAD)`,",
        "written by `scripts/goal20-part-a-noise-bands.py` to",
        "`docs/benchmarks/goal20-part-a-noise-bands.json`, enforced by",
        f"`scripts/goal11-performance-gate.py` on machine `{bands.get('machine')}`):",
        "",
    ]
    for name, metric in (bands.get("metrics") or {}).items():
        band = metric.get("band_us") or metric.get("band_bytes")
        unit = "µs" if "band_us" in metric else "B"
        if metric.get("enforcement") == "fail-closed":
            lines.append(
                f"- `{name}`: fail-closed, band {band:,.0f}{unit} "
                f"(n={metric.get('n')}, MAD={metric.get('mad_us', metric.get('mad_bytes', 0)):,.1f})"
            )
        else:
            lines.append(
                f"- `{name}`: informational — {metric.get('reason')}"
            )
    return lines


def render_section(history: dict, bands: dict | None) -> str:
    entries = list(history.get("entries") or [])
    lines = [
        START,
        "",
        "## Goal 20 self-history (script-written)",
        "",
        "Produced by `scripts/write-performance-ledger.py` from",
        "`docs/benchmarks/performance-history.json`. Do not edit the table",
        "by hand.",
        "",
        *render_band_lines(bands),
        "",
        "Native image bytes are recorded only when",
        "`record-performance-history.py --native-image` stats the cadr used",
        "for that bench. Older rows show —. The first cell appears on the",
        "next isolated verify that records history; do not hand-fill.",
        "",
        "| recordedAt (UTC) | label | machine | git | cold start µs | native image B | N=5000 frame µs | N=5000 frame bytes |",
        "|---|---|---|---|---:|---:|---:|---:|",
    ]
    for entry in entries:
        lines.append(
            "| {at} | {label} | {machine} | `{git}` | {cold} | {image} | {frame} | {alloc} |".format(
                at=entry.get("recordedAt") or "—",
                label=entry.get("label") or "—",
                machine=entry.get("machine") or "—",
                git=short_git(entry.get("gitHead")),
                cold=format_us(entry.get("coldStartMedianUs")),
                image=format_bytes(entry.get("nativeImageBytes")),
                frame=format_us(entry.get("frame5000MedianUs")),
                alloc=format_bytes(entry.get("frame5000MedianBytes")),
            )
        )
    if len(entries) >= 2:
        previous, current = entries[-2], entries[-1]
        lines.extend(
            [
                "",
                f"Latest vs previous: `{current.get('label')}` "
                f"({current.get('recordedAt')}) versus "
                f"`{previous.get('label')}` ({previous.get('recordedAt')}).",
            ]
        )
    elif entries:
        only = entries[-1]
        lines.extend(
            [
                "",
                f"Only one history row (`{only.get('label')}`). "
                "A second `record-performance-history.py` run is required "
                "before the ledger can show a delta.",
            ]
        )
    else:
        lines.extend(["", "History file has no entries yet."])
    lines.extend(["", END, ""])
    return "\n".join(lines)


def render_run_line(entry: dict) -> str:
    quick = "yes" if entry.get("quick") else "no"
    return (
        f"`{entry.get('label') or '—'}` ({entry.get('recordedAt') or '—'}) "
        f"on `{entry.get('machine') or '—'}`, git `{short_git(entry.get('gitHead'))}`, "
        f"ratio_gate=`{entry.get('ratioGate') or '—'}`, quick={quick}, "
        f"samples={entry.get('samples') if entry.get('samples') is not None else '—'}"
    )


def render_paired_section(history: dict) -> str:
    entries = list(history.get("entries") or [])
    lines = [
        PAIRED_START,
        "",
        "## Goal 20 paired paths (script-written)",
        "",
        "Produced by `scripts/write-performance-ledger.py` from",
        "`docs/benchmarks/goal20-paired-paths.json`. Do not edit the table",
        "by hand. `quick=yes` / `ratio_gate=informational-quick-run` is a",
        "booking, not an enforced same-machine full sample. Part O uses a",
        "non-quick run on this host before claiming a ratio moved.",
        "",
    ]
    if not entries:
        lines.extend(["History file has no entries yet.", "", PAIRED_END, ""])
        return "\n".join(lines)

    current = entries[-1]
    previous = entries[-2] if len(entries) >= 2 else None
    current_metrics = current.get("metrics") or {}
    previous_metrics = (previous.get("metrics") or {}) if previous else {}

    lines.extend(["Current: " + render_run_line(current), ""])
    if previous:
        lines.extend(["Previous: " + render_run_line(previous), ""])
    else:
        lines.extend(
            [
                "Previous: none. A second `record-paired-paths.py` run is",
                "required before the ledger can show a delta.",
                "",
            ]
        )

    lines.extend(
        [
            "| metric | cadr µs | baseline µs | ratio | previous ratio | ceiling |",
            "|---|---:|---:|---:|---:|---:|",
        ]
    )
    for key in METRIC_KEYS:
        metric = current_metrics.get(key) or {}
        prior = previous_metrics.get(key) or {}
        lines.append(
            "| `{key}` | {cadr} | {baseline} | {ratio} | {previous} | {ceiling} |".format(
                key=key,
                cadr=format_us(metric.get("cadrMedianUs")),
                baseline=format_us(metric.get("baselineMedianUs")),
                ratio=format_ratio(metric.get("ratio")),
                previous=format_ratio(prior.get("ratio")),
                ceiling=format_ratio(metric.get("ceiling")),
            )
        )

    lines.extend(
        [
            "",
            "| recordedAt (UTC) | label | git | quick | ratio_gate | append | read | load | list_models_render |",
            "|---|---|---|---|---|---:|---:|---:|---:|",
        ]
    )
    for entry in entries:
        metrics = entry.get("metrics") or {}
        cells = [
            format_ratio((metrics.get(key) or {}).get("ratio"))
            for key in HISTORY_RATIO_KEYS
        ]
        lines.append(
            "| {at} | {label} | `{git}` | {quick} | {gate} | {append} | {read} | {load} | {render} |".format(
                at=entry.get("recordedAt") or "—",
                label=entry.get("label") or "—",
                git=short_git(entry.get("gitHead")),
                quick="yes" if entry.get("quick") else "no",
                gate=entry.get("ratioGate") or "—",
                append=cells[0],
                read=cells[1],
                load=cells[2],
                render=cells[3],
            )
        )
    lines.extend(["", PAIRED_END, ""])
    return "\n".join(lines)


def replace_marked_section(
    markdown: str, start: str, end: str, section: str
) -> str:
    if start in markdown and end in markdown:
        before, rest = markdown.split(start, 1)
        _, after = rest.split(end, 1)
        return before.rstrip() + "\n\n" + section + after.lstrip("\n")
    return markdown.rstrip() + "\n\n" + section


def replace_section(markdown: str, section: str) -> str:
    return replace_marked_section(markdown, START, END, section)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--history",
        type=Path,
        default=Path("docs/benchmarks/performance-history.json"),
    )
    parser.add_argument(
        "--ledger",
        type=Path,
        default=Path("docs/performance.md"),
    )
    parser.add_argument(
        "--bands",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "docs/benchmarks/goal20-part-a-noise-bands.json",
    )
    parser.add_argument(
        "--paired",
        type=Path,
        default=Path("docs/benchmarks/goal20-paired-paths.json"),
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if the committed ledger differs from a regeneration; do not write",
    )
    args = parser.parse_args()
    history = json.loads(args.history.read_text(encoding="utf-8"))
    try:
        bands = json.loads(args.bands.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        bands = None
    markdown = args.ledger.read_text(encoding="utf-8")
    regenerated = replace_marked_section(
        markdown, START, END, render_section(history, bands)
    )
    paired_count = 0
    if args.paired.is_file():
        paired = json.loads(args.paired.read_text(encoding="utf-8"))
        paired_count = len(paired.get("entries") or [])
        regenerated = replace_marked_section(
            regenerated, PAIRED_START, PAIRED_END, render_paired_section(paired)
        )
    if args.check:
        if regenerated != markdown:
            print(
                "performance-ledger: docs/performance.md differs from a "
                "regeneration of its marked sections; record with "
                "write-performance-ledger.py (no --check) and commit",
                file=sys.stderr,
            )
            return 1
        print(
            "performance-ledger: committed ledger matches regeneration "
            f"(entries={len(history.get('entries') or [])} paired={paired_count})"
        )
        return 0
    args.ledger.write_text(regenerated, encoding="utf-8")
    print(
        "performance-ledger: "
        f"entries={len(history.get('entries') or [])} "
        f"paired={paired_count} "
        f"output={args.ledger}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
