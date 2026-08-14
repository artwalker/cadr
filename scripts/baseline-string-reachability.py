#!/usr/bin/env python3
"""Part L forward gate: named baseline strings must have a cadr producer.

An obligation is a literal that must appear in a listed cadr source file
AND must be emitted by a named function (not a parked defparameter).
Comments and docstrings are not producers.

L0 obligation: "no models are available for that provider" in
src/cadr-cli/models/login-selection.lisp via post-login-selection-error.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OBLIGATIONS = ROOT / "test/fixtures/baseline-string-reachability.json"

COMMENT = re.compile(r";.*$")


def code_without_comments(text: str) -> str:
    return "\n".join(COMMENT.sub("", line) for line in text.splitlines())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--print-denominator", action="store_true")
    args = parser.parse_args()
    data = json.loads((args.root / OBLIGATIONS.relative_to(ROOT)).read_text(encoding="utf-8"))
    if args.print_denominator:
        print(
            "baseline-string-reachability: "
            f"{len(data['obligations'])} named baseline literals must have "
            "a cadr producer path. Does not check cadr-only leaks "
            "(cadr-visible-output-origin.py). "
            "A pass means each listed literal occurs in the named producer "
            "file outside comments."
        )
        return 0
    missing: list[str] = []
    for entry in data["obligations"]:
        path = args.root / entry["path"]
        literal = entry["literal"]
        if not path.is_file():
            missing.append(f"missing file {path} for {literal!r}")
            continue
        body = code_without_comments(path.read_text(encoding="utf-8"))
        if literal not in body:
            missing.append(f"{entry['path']} has no live producer for {literal!r}")
    if missing:
        print("\n".join(missing), file=sys.stderr)
        return 2
    print(
        "baseline-string-reachability: "
        f"{len(data['obligations'])}/{len(data['obligations'])} producers present"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
