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
    "evals_harness.summarize",
    "ai_crypto_model_data.manifest",
    "cli_models_rest.pattern_match",
    "image_runtime.dimensions",
    "cli_print_rpc.jsonl_line",
    "tui_latex.render",
    "tui_editor_helpers.fuzzy_match",
    "tui_theme_overlay.osc11_bg",
    "ai_support.estimate_text",
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
    "cli_support.strip_ansi",
    "session_pipeline.session_load",
    "session_pipeline.context_walk",
    "storage_journal.journal_read",
    "storage_journal.journal_append",
    "sqlite_session.open_walk",
    "tool_read.text_file",
    "tool_grep.context_file",
    "agent_tool_loop.roundtrip",
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
