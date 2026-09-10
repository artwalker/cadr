#!/usr/bin/env python3
"""Promote Goal 28 fixed rows with goal28 FiveAM evidence to match."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADJ = ROOT / "docs/benchmarks/goal28-adjudications.tsv"


def main() -> None:
    lines = ADJ.read_text(encoding="utf-8").splitlines()
    out = [lines[0]]
    promoted = 0
    for line in lines[1:]:
        parts = line.split("\t")
        if len(parts) != 5:
            out.append(line)
            continue
        cls, name, status, evidence, note = parts
        if (
            status == "fixed"
            and "goal28-" in evidence
            and evidence.endswith("-test.lisp")
        ):
            out.append(
                f"{cls}\t{name}\tmatch\t{evidence}\t"
                f"pin-named behavior asserted in {Path(evidence).name}"
            )
            promoted += 1
        else:
            out.append(line)
    ADJ.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"promoted={promoted}")


if __name__ == "__main__":
    main()
