#!/usr/bin/env python3
"""Classify Goal 20 invent-pause ledger rows into Goal 24 drain buckets.

Reads docs/benchmarks/goal20-paired-over-1x.md table rows. Emits TSV.
Does not invent. Reviewer re-runs this script.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / "docs/benchmarks/goal20-paired-over-1x.md"
OUT = ROOT / "docs/benchmarks/goal24-invent-pause-inventory.tsv"

ROW = re.compile(r"^\|\s*`([^`]+)`\s*\|(.*)$")


def bucket(note: str, leftover: str = "") -> str:
    blob = f"{note} {leftover}"
    n = blob.lower()
    if "待本质提案" in blob or ("待" in note and "本质" in note):
        return "needs-proposal"
    if "抬天花板" in blob or "over ceiling" in n or "ratio > named ceiling" in n:
        return "ceiling-or-variance"
    if "variance floor" in n or "sub-µs" in n or "sub-us" in n:
        return "variance-floor"
    if "shape gap" in n or "size gap" in n or "count gap" in n:
        return "shape-gap"
    if "measure-only" in n:
        return "measure-only-floor"
    if "invent keep" in note:
        return "keep-pending-remount"
    if "invent pause" in note or "地板优化另刀" in note:
        return "floor-invent"
    return "other"


def main() -> int:
    lines = LEDGER.read_text(encoding="utf-8").splitlines()
    rows: list[tuple[str, str, str]] = []
    for line in lines:
        m = ROW.match(line)
        if not m:
            continue
        metric = m.group(1).strip()
        rest = m.group(2)
        cells = [c.strip() for c in rest.split("|") if c.strip()]
        if not cells:
            continue
        note = cells[-1]
        leftover = cells[-2] if len(cells) >= 2 else ""
        if (
            "invent pause" not in note
            and "地板" not in note
            and "invent keep" not in note
            and "待" not in note
        ):
            continue
        rows.append(
            (metric, bucket(note, leftover), note.replace("\t", " ")[:240])
        )

    by_metric: dict[str, tuple[str, str]] = {}
    for metric, b, note in rows:
        by_metric[metric] = (b, note)

    with OUT.open("w", encoding="utf-8") as fh:
        fh.write("metric\tbucket\tnote\n")
        for metric in sorted(by_metric):
            b, note = by_metric[metric]
            fh.write(f"{metric}\t{b}\t{note}\n")

    counts: dict[str, int] = {}
    for b, _ in by_metric.values():
        counts[b] = counts.get(b, 0) + 1
    print(f"wrote {OUT} metrics={len(by_metric)}")
    for k in sorted(counts):
        print(f"  {k}: {counts[k]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
