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
    "settings_load.project_trust",
    "settings_load.config_value",
    "settings_load.http_idle",
    "resource_loader.reload",
    "package_manager.resolve",
    "session_discovery.header_probe",
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
    "cli_extensions_install.llama_url",
    "cli_extensions_install.hf_token",
    "cli_extensions_install.llama_catalog",
    "evals_harness.summarize",
    "evals_harness.group_key",
    "evals_harness.artifact_persist",
    "evals_harness.format",
    "ai_crypto_model_data.manifest",
    "ai_crypto.hmac",
    "cli_models_rest.pattern_match",
    "cli_models_rest.auth_command",
    "image_runtime.dimensions",
    "image_runtime.mime_type",
    "image_runtime.lookup",
    "image_runtime.dimension_note",
    "image_runtime.api_provider",
    "cli_print_rpc.jsonl_line",
    "cli_print_rpc.jsonl_read",
    "cli_print_rpc.clamp_thinking",
    "cli_print_rpc.session_stats",
    "tui_latex.render",
    "tui_mermaid.render",
    "tui_mermaid.source_box",
    "tui_mermaid.transform",
    "tui_editor_helpers.fuzzy_match",
    "tui_theme_overlay.osc11_bg",
    "ai_support.estimate_text",
    "ai_support.context_overflow",
    "ai_support.grammar_delta",
    "ai_support.uuid_v7",
    "ai_support.auth_guidance",
    "tui_select_settings_loaders.filter",
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
    "skill_prompt_load.build_prompt",
    "cli_bootstrap_sessions.coding_tools",
    "ai_runtime_faux.blocks",
    "http_transport.parse_url",
    "session_pipeline.session_load",
    "session_pipeline.context_walk",
    "storage_journal.journal_read",
    "storage_journal.journal_append",
    "sqlite_session.open_walk",
    "tool_read.text_file",
    "tool_grep.context_file",
    "agent_tool_loop.roundtrip",
    "agent_tool_loop.tool_path",
    "agent_tool_loop.line_ending",
    "session_compact.compact",
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
