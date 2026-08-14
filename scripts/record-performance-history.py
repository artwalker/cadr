#!/usr/bin/env python3
"""Append one verified bench run to the performance time series.

Does not change fail-closed thresholds (Goal 20 Part A still needs
user-adjudicated drift limits). Goal 20 Part B: the numbers must be
written by a script, never hand-edited into docs/performance.md.
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


def _point_at_n(metric: dict, n: int) -> dict:
    for point in metric.get("points") or []:
        if point.get("n") == n:
            return point
    return {}


def extract(bench: dict) -> dict:
    metrics = bench.get("metrics") or {}
    frame = _point_at_n(metrics.get("frame_render") or {}, 5000)
    cold = bench.get("cold_start") or {}
    provenance = bench.get("provenance") or {}
    return {
        "recordedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "label": bench.get("label") or provenance.get("label"),
        "gitHead": (
            (bench.get("git") or {}).get("head")
            or bench.get("commit")
            or provenance.get("source_revision")
        ),
        "machine": (bench.get("machine") or {}).get("machine_instance")
        or (bench.get("machine") or {}).get("hostname"),
        "coldStartMedianUs": cold.get("median_us"),
        "frame5000MedianUs": frame.get("median_us"),
        "frame5000MedianBytes": frame.get("median_bytes"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bench", type=Path, required=True)
    parser.add_argument(
        "--history",
        type=Path,
        default=Path("docs/benchmarks/performance-history.json"),
    )
    args = parser.parse_args()
    bench = json.loads(args.bench.read_text(encoding="utf-8"))
    row = extract(bench)
    if args.history.is_file():
        history = json.loads(args.history.read_text(encoding="utf-8"))
    else:
        history = {"schemaVersion": 1, "entries": []}
    history.setdefault("entries", []).append(row)
    args.history.parent.mkdir(parents=True, exist_ok=True)
    args.history.write_text(
        json.dumps(history, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(
        "performance-history: "
        f"entries={len(history['entries'])} "
        f"cold={row.get('coldStartMedianUs')} "
        f"frame5000={row.get('frame5000MedianUs')} "
        f"output={args.history}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
