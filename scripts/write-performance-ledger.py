#!/usr/bin/env python3
"""Regenerate the Goal 20 Part B time series in docs/performance.md.

Reads docs/benchmarks/performance-history.json and the adjudicated Part A
drift bands from docs/benchmarks/goal20-part-a-noise-bands.json. Never
hand-edits numbers.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

START = "<!-- GOAL20_PERF_HISTORY_START -->"
END = "<!-- GOAL20_PERF_HISTORY_END -->"


def format_us(value: float | None) -> str:
    if value is None:
        return "—"
    return f"{value:,.1f}"


def format_bytes(value: float | None) -> str:
    if value is None:
        return "—"
    return f"{value:,.0f}"


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
        "| recordedAt (UTC) | label | machine | git | cold start µs | N=5000 frame µs | N=5000 frame bytes |",
        "|---|---|---|---|---:|---:|---:|",
    ]
    for entry in entries:
        git = str(entry.get("gitHead") or "—")
        hexish = git.lower().startswith(tuple("0123456789abcdef")) and len(git) >= 40
        if hexish:
            git = git[:12]
        lines.append(
            "| {at} | {label} | {machine} | `{git}` | {cold} | {frame} | {alloc} |".format(
                at=entry.get("recordedAt") or "—",
                label=entry.get("label") or "—",
                machine=entry.get("machine") or "—",
                git=git,
                cold=format_us(entry.get("coldStartMedianUs")),
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


def replace_section(markdown: str, section: str) -> str:
    if START in markdown and END in markdown:
        before, rest = markdown.split(START, 1)
        _, after = rest.split(END, 1)
        return before.rstrip() + "\n\n" + section + after.lstrip("\n")
    return markdown.rstrip() + "\n\n" + section


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
    args = parser.parse_args()
    history = json.loads(args.history.read_text(encoding="utf-8"))
    try:
        bands = json.loads(args.bands.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        bands = None
    markdown = args.ledger.read_text(encoding="utf-8")
    args.ledger.write_text(
        replace_section(markdown, render_section(history, bands)), encoding="utf-8"
    )
    print(
        "performance-ledger: "
        f"entries={len(history.get('entries') or [])} "
        f"output={args.ledger}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
