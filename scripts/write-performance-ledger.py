#!/usr/bin/env python3
"""Regenerate the Goal 20 Part B time series in docs/performance.md.

Reads docs/benchmarks/performance-history.json. Never hand-edits numbers.
Does not enable Part A fail-closed drift thresholds.
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


def render_section(history: dict) -> str:
    entries = list(history.get("entries") or [])
    lines = [
        START,
        "",
        "## Goal 20 self-history (script-written)",
        "",
        "Produced by `scripts/write-performance-ledger.py` from",
        "`docs/benchmarks/performance-history.json`. Do not edit the table",
        "by hand. Part A drift percents are **not** fail-closed until the",
        "user adjudicates `docs/proposals/goal20-part-a-regression-thresholds.md`.",
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
    args = parser.parse_args()
    history = json.loads(args.history.read_text(encoding="utf-8"))
    markdown = args.ledger.read_text(encoding="utf-8")
    args.ledger.write_text(
        replace_section(markdown, render_section(history)), encoding="utf-8"
    )
    print(
        "performance-ledger: "
        f"entries={len(history.get('entries') or [])} "
        f"output={args.ledger}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
