#!/usr/bin/env python3
"""Generate the Lisp golden data file from the goal 19 Part A golden.

Reads test/fixtures/mermaid-golden/reference.json (produced by
scripts/grok-mermaid-golden.mjs from the checked-in grok-mermaid@0.2.2
fixture) and writes test/cadr-tui/mermaid-golden-data.lisp.  The data file
carries every corpus entry (id, input, null, width, warnings, plain, styled)
so the FiveAM golden test needs no JSON parser at test time and no cadr-ai
dependency.

The generator is fail-closed: it rejects any structural drift in the golden
(missing/unknown keys, wrong types, control characters that cannot be written
as Lisp string escapes, or a result count that changes).  `--check` mode
regenerates to a temp file and compares byte-for-byte with the checked-in
file; verify.sh uses it as the consistency gate so a hand-edit of the Lisp
data cannot silently diverge from the golden.

Usage:
  scripts/gen-mermaid-golden-data.py            # rewrite the data file
  scripts/gen-mermaid-golden-data.py --check    # consistency gate
"""

import argparse
import hashlib
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GOLDEN = ROOT / "test/fixtures/mermaid-golden/reference.json"
OUT = ROOT / "test/cadr-tui/mermaid-golden-data.lisp"

EXPECTED_RESULTS = 47
REQUIRED_KEYS = {"id", "input", "null"}
NULL_ONLY_KEYS = {"id", "input", "null"}
RENDERED_KEYS = {"id", "input", "null", "width", "warnings", "plain", "styled"}


def lisp_string(value: str) -> str:
    """Escape a string for a Lisp double-quoted literal."""
    out = []
    for ch in value:
        o = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            # A real newline byte inside the quoted literal: CL does not
            # treat "\\n" as an escape, it would read as a literal "n".
            out.append("\n")
        elif ch == "\r":
            out.append("\r")
        elif ch == "\t":
            out.append("\t")
        elif o < 0x20 or o == 0x7F or o in (0x2028, 0x2029):
            raise ValueError(
                f"character U+{o:04X} cannot be represented as a Lisp "
                f"string escape"
            )
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def render_case(case: dict) -> list[str]:
    case_id = case["id"]
    lines = [f'   (list :id {lisp_string(case_id)}', f"         :input {lisp_string(case['input'])}"]
    if case["null"]:
        lines.append("         :null t")
        lines.append("   )")
        return lines
    lines.append("         :null nil")
    lines.append(f"         :width {case['width']}")
    warnings = case["warnings"]
    if warnings:
        lines.append(
            "         :warnings '("
            + " ".join(lisp_string(w) for w in warnings)
            + ")"
        )
    else:
        lines.append("         :warnings nil")
    plain = case["plain"]
    lines.append("         :plain '(")
    for row in plain:
        lines.append(f"                 {lisp_string(row)}")
    lines.append("                 )")
    styled = case["styled"]
    lines.append("         :styled '(")
    for row in styled:
        spans = " ".join(f"({lisp_string(t)} {lisp_string(c)})" for t, c in row)
        lines.append(f"                 ({spans})")
    lines.append("                 )")
    lines.append("   )")
    return lines


def generate() -> str:
    golden = json.loads(GOLDEN.read_text(encoding="utf-8"))
    results = golden["results"]
    if len(results) != EXPECTED_RESULTS:
        raise ValueError(
            f"golden result count changed: expected {EXPECTED_RESULTS}, "
            f"got {len(results)}"
        )
    golden_sha = hashlib.sha256(
        GOLDEN.read_bytes()
    ).hexdigest()

    null_count = 0
    rendered_count = 0
    seen_ids = set()
    body = []
    for case in results:
        keys = set(case)
        if keys != NULL_ONLY_KEYS and keys != RENDERED_KEYS:
            raise ValueError(f"case {case.get('id')!r} has unexpected keys {sorted(keys)}")
        for key in REQUIRED_KEYS:
            if key not in case:
                raise ValueError(f"case missing required key {key!r}")
        case_id = case["id"]
        if case_id in seen_ids:
            raise ValueError(f"duplicate case id {case_id!r}")
        seen_ids.add(case_id)
        if not isinstance(case["input"], str):
            raise ValueError(f"case {case_id!r} input is not a string")
        if case["null"]:
            if keys != NULL_ONLY_KEYS:
                raise ValueError(f"null case {case_id!r} carries render fields")
            null_count += 1
        else:
            if keys != RENDERED_KEYS:
                raise ValueError(f"rendered case {case_id!r} is missing render fields")
            if not isinstance(case["width"], int):
                raise ValueError(f"case {case_id!r} width is not an integer")
            if not isinstance(case["warnings"], list) or not all(
                isinstance(w, str) for w in case["warnings"]
            ):
                raise ValueError(f"case {case_id!r} warnings are not a string list")
            if not isinstance(case["plain"], list) or not all(
                isinstance(row, str) for row in case["plain"]
            ):
                raise ValueError(f"case {case_id!r} plain is not a string list")
            if not isinstance(case["styled"], list):
                raise ValueError(f"case {case_id!r} styled is not a list")
            for row in case["styled"]:
                if not isinstance(row, list):
                    raise ValueError(f"case {case_id!r} styled row is not a list")
                for span in row:
                    if (
                        not isinstance(span, list)
                        or len(span) != 2
                        or not all(isinstance(x, str) for x in span)
                    ):
                        raise ValueError(f"case {case_id!r} styled span is malformed")
            rendered_count += 1
        body.extend(render_case(case))

    header = [
        ";;; Generated by scripts/gen-mermaid-golden-data.py from",
        ";;; test/fixtures/mermaid-golden/reference.json.",
        ";;; DO NOT EDIT BY HAND -- rerun the generator and commit the result.",
        ";;;",
        ";;; Golden output derived from grok-mermaid@0.2.2 (Apache-2.0):",
        ";;;   Copyright 2023-2026 SpaceXAI",
        ";;;   Copyright 2026 Alexey Zaytsev",
        ";;; License text: docs/third-party/grok-mermaid-LICENSE.txt",
        ";;;",
        f";;; golden generator: {golden['generator']}",
        f";;; golden artifactSha256: {golden['artifactSha256']}",
        f";;; golden generatorScript: {golden['generatorScript']}",
        f";;; reference.json sha256: {golden_sha}",
        f";;; results: {len(results)} ({rendered_count} rendered, {null_count} null)",
        ";;;",
        ";;; Each entry is (list :id <id> :input <src> :null <bool>",
        ";;;   :width <cols> :warnings <list> :plain <list of rows>",
        ";;;   :styled <list of rows, each a list of (text cls) spans>).",
        ";;; Null entries carry only :id/:input/:null.",
        "(in-package #:cadr-tui/tests)",
        "",
        "(defparameter +mermaid-golden-results+",
        "  (list",
    ]
    return "\n".join(header + body + ["  ))"]) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="regenerate to a temp file and compare with the checked-in file",
    )
    args = parser.parse_args()

    generated = generate()
    if not args.check:
        fd, tmp = tempfile.mkstemp(prefix=".mermaid-golden-data.", dir=OUT.parent)
        try:
            with open(fd, "w", encoding="utf-8") as fh:
                fh.write(generated)
            Path(tmp).replace(OUT)
        finally:
            if Path(tmp).exists():
                Path(tmp).unlink()
        print(f"wrote {OUT}")
        return 0

    current = OUT.read_text(encoding="utf-8")
    if current == generated:
        print(f"mermaid golden data consistency: {OUT} matches reference.json")
        return 0
    print(
        f"mermaid golden data consistency: {OUT} differs from "
        f"reference.json; rerun scripts/gen-mermaid-golden-data.py",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
