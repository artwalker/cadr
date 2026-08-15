#!/usr/bin/env python3
"""Goal 20, queue 11c: fail-closed existence check for cadr-side mappings.

docs/source-parity.md maps every fixed-baseline source file to cadr
`file:line` pointers.  108 of those pointers rotted over ten days because
no gate checked that the cadr-side path still exists (root cause recorded
in the ledger's own section 0).  This script is that check, in gate form:
the currently rotten set is recorded in
docs/source-parity-rotten-mappings.json, and the gate fails when the
measured rotten set differs from the recorded set in EITHER direction —
new rot fails, and a healed mapping fails until the record is updated in
the same commit.  The record may only shrink.

usage:
  python3 scripts/check-source-parity-cadr-paths.py          # gate
  python3 scripts/check-source-parity-cadr-paths.py --write  # re-record
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

PROJECT_DIRECTORY = Path(__file__).resolve().parents[1]
LEDGER = PROJECT_DIRECTORY / "docs/source-parity.md"
RECORD = PROJECT_DIRECTORY / "docs/source-parity-rotten-mappings.json"

# The same extraction the ledger's section 0 documents for its recompute
# command; keep the two in agreement or the numbers stop being comparable.
MAPPING_PATTERN = re.compile(
    r"((?:src|test|examples|scripts)/[a-zA-Z0-9/_.-]+\.(?:lisp|sexp|asd|py|sh)):\d+"
)


def measure() -> tuple[list[str], int, int]:
    rows = [
        line
        for line in LEDGER.read_text(encoding="utf-8").splitlines()
        if line.startswith("| `packages/")
    ]
    total = 0
    rotten: set[str] = set()
    rotten_occurrences = 0
    for line in rows:
        for path in MAPPING_PATTERN.findall(line):
            total += 1
            if not (PROJECT_DIRECTORY / path).exists():
                rotten.add(path)
                rotten_occurrences += 1
    return sorted(rotten), total, rotten_occurrences


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true",
                        help="re-record the measured rotten set as the expected one")
    args = parser.parse_args()

    rotten, total, rotten_occurrences = measure()
    if args.write:
        RECORD.write_text(
            json.dumps(
                {
                    "comment": "Distinct rotten cadr-side paths in docs/source-parity.md. rottenOccurrences matches the ledger section-0 recompute count (one path can rot many rows).",
                    "rottenOccurrences": rotten_occurrences,
                    "rottenMappings": rotten,
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        print(
            f"source-parity cadr paths: recorded {len(rotten)} rotten paths "
            f"({rotten_occurrences} occurrences) of {total}"
        )
        return 0

    if not RECORD.is_file():
        print(f"source-parity cadr paths: record missing: {RECORD}", file=sys.stderr)
        return 2
    recorded = json.loads(RECORD.read_text(encoding="utf-8"))["rottenMappings"]
    recorded_set = set(recorded)
    rotten_set = set(rotten)
    new_rot = sorted(rotten_set - recorded_set)
    healed = sorted(recorded_set - rotten_set)
    if new_rot:
        print("source-parity cadr paths: NEW rotten mappings:", file=sys.stderr)
        for path in new_rot:
            print(f"  {path}", file=sys.stderr)
    if healed:
        print(
            "source-parity cadr paths: recorded mappings healed; "
            "re-run with --write and commit the smaller record:",
            file=sys.stderr,
        )
        for path in healed:
            print(f"  {path}", file=sys.stderr)
    if new_rot or healed:
        return 1
    print(
        f"source-parity cadr paths: {len(rotten)} recorded rotten paths "
        f"({rotten_occurrences} occurrences) of {total} mappings, no drift"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
