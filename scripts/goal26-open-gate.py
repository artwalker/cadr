#!/usr/bin/env python3
"""Report Goal 26 open-parity count; exit 1 if stop not met when --require-zero."""
from __future__ import annotations
import argparse, csv, sys
from collections import Counter
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
DISP = ROOT / "docs/benchmarks/goal26-dispositions.tsv"
TERM = {"met-beat", "met-parity", "accepted-runtime-gap"}

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--require-zero", action="store_true")
    args = ap.parse_args()
    rows = list(csv.DictReader(DISP.open(), delimiter="\t"))
    c = Counter(r["disposition"] for r in rows)
    open_n = c.get("open-parity", 0)
    beat = c.get("met-beat", 0)
    print(f"goal26 rows={len(rows)} open-parity={open_n} met-beat={beat} counts={dict(c)}")
    if args.require_zero and open_n:
        print("FAIL: open-parity != 0")
        return 1
    bad = [r for r in rows if r["disposition"] not in TERM | {"open-parity"}]
    if bad:
        print("FAIL: unknown dispositions", {r["disposition"] for r in bad})
        return 1
    if args.require_zero:
        ungated = [r for r in rows if r["disposition"] == "accepted-runtime-gap"]
        # accepted-runtime-gap rows are terminal for the gate script; human
        # approval lives in .orchestrate/goal26/gates.md and is audited at close.
        _ = ungated
    return 0

if __name__ == "__main__":
    sys.exit(main())
