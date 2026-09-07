#!/usr/bin/env python3
"""Fail if Goal 24 durable-evidence invariants regress."""
from __future__ import annotations

import csv
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DISP = ROOT / "docs/benchmarks/goal24-dispositions.tsv"
INV = ROOT / "docs/benchmarks/goal24-invent-pause-inventory.tsv"
EV = ROOT / "docs/benchmarks/goal24-evidence"
P5 = EV / "p5-verify.log"

OPENISH_PREFIXES = ("open-", "needs-")


def main() -> int:
    errors: list[str] = []
    rows = list(csv.DictReader(DISP.open(), delimiter="\t"))
    inv = list(csv.DictReader(INV.open(), delimiter="\t"))
    if len(rows) != len(inv):
        errors.append(f"disposition/inventory count mismatch {len(rows)} vs {len(inv)}")
    disp_metrics = {r["metric"] for r in rows}
    inv_metrics = {r["metric"] for r in inv}
    if disp_metrics != inv_metrics:
        errors.append(
            f"metric set mismatch missing={sorted(inv_metrics - disp_metrics)[:5]} "
            f"extra={sorted(disp_metrics - inv_metrics)[:5]}"
        )
    c = Counter(r["disposition"] for r in rows)
    for key in ("open-floor-invent", "open-remount", "needs-proposal", "needs-ceiling-ruling"):
        if c.get(key, 0):
            errors.append(f"{key}={c[key]} (want 0)")
    for r in rows:
        if any(r["disposition"].startswith(p) for p in OPENISH_PREFIXES):
            errors.append(f"openish disposition {r['metric']}={r['disposition']}")
        ev = r["evidence"]
        if "/tmp/" in ev:
            errors.append(f"tmp evidence {r['metric']} -> {ev}")
        if "/tmp/" in r.get("note", ""):
            errors.append(f"tmp note {r['metric']} -> {r['note'][:80]}")
        for part in ev.split():
            if part.startswith("docs/benchmarks/goal24-evidence/"):
                path = ROOT / part
                if not path.is_file():
                    errors.append(f"missing evidence file {part}")
    if not P5.is_file() or P5.stat().st_size < 100:
        errors.append(f"missing or tiny Part5 verify log {P5}")
    if errors:
        print("goal24-evidence-gate FAIL")
        for e in errors:
            print(" -", e)
        return 1
    print(
        "goal24-evidence-gate PASS "
        f"rows={len(rows)} dispositions={dict(c)} evidence_dirs="
        f"{sum(1 for p in EV.iterdir() if p.is_dir())}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
