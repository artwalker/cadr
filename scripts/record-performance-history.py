#!/usr/bin/env python3
"""Append one verified bench run to the performance time series.

The fail-closed Part A drift bands live in
docs/benchmarks/goal20-part-a-noise-bands.json (adjudicated 2026-08-14)
and are enforced by scripts/goal11-performance-gate.py; this script only
appends history rows. Goal 20 Part B: the numbers must be written by a
script, never hand-edited into docs/performance.md.
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


def native_image_bytes_from(value: object) -> int | None:
    """Accept a real stat size only. Omit when absent. Never invent 20884056."""
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    if value < 0:
        return None
    return value


def extract(bench: dict, native_image_bytes: int | None = None) -> dict:
    metrics = bench.get("metrics") or {}
    frame = _point_at_n(metrics.get("frame_render") or {}, 5000)
    cold = bench.get("cold_start") or {}
    provenance = bench.get("provenance") or {}
    if native_image_bytes is None:
        native_image_bytes = native_image_bytes_from(bench.get("nativeImageBytes"))
    row = {
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
    if native_image_bytes is not None:
        row["nativeImageBytes"] = native_image_bytes
    return row


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bench", type=Path, required=True)
    parser.add_argument(
        "--history",
        type=Path,
        default=Path("docs/benchmarks/performance-history.json"),
    )
    parser.add_argument(
        "--native-image",
        type=Path,
        default=None,
        help="cadr image used for this bench; size comes from stat, omitted if absent",
    )
    args = parser.parse_args()
    bench = json.loads(args.bench.read_text(encoding="utf-8"))
    native_bytes = None
    if args.native_image is not None:
        try:
            native_bytes = args.native_image.stat().st_size
        except OSError:
            native_bytes = None
    row = extract(bench, native_image_bytes=native_bytes)
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
        f"nativeImageBytes={row.get('nativeImageBytes', '—')} "
        f"frame5000={row.get('frame5000MedianUs')} "
        f"output={args.history}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
