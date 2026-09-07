#!/usr/bin/env python3
"""Report Goal 25 open-hillclimb count; exit 1 if stop not met when --require-zero."""
from __future__ import annotations
import argparse, csv, sys
from collections import Counter
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
DISP = ROOT / "docs/benchmarks/goal25-dispositions.tsv"
TERM = {"met-hillclimb", "frozen-leftover-ruler", "frozen-subus-floor", "frozen-unreachable"}

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--require-zero", action="store_true")
    args = ap.parse_args()
    rows = list(csv.DictReader(DISP.open(), delimiter="\t"))
    c = Counter(r["disposition"] for r in rows)
    open_n = c.get("open-hillclimb", 0)
    print(f"goal25 rows={len(rows)} open-hillclimb={open_n} counts={dict(c)}")
    if args.require_zero and open_n:
        print("FAIL: open-hillclimb != 0")
        return 1
    bad = [r for r in rows if r["disposition"] not in TERM | {"open-hillclimb"}]
    if bad:
        print("FAIL: unknown dispositions", {r["disposition"] for r in bad})
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
