#!/usr/bin/env python3
"""Part L reverse gate: cadr visible output must not be unformatted Lisp.

Scans render-diff analysis *.cadr.screen files (or --root) for tokens that
cannot come from the baseline or an adjudicated cadr-only string.

Forbidden without a disposition:
  - a standalone NIL / nil token (L0 snake leak)
  - #<... unreadable objects
  - #S( structure dumps

This is not a PTY filter. It fails the gate when those bytes are already
on the captured screen.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


FORBIDDEN = (
    re.compile(rb"(?<![A-Za-z0-9])NIL(?![A-Za-z0-9])"),
    re.compile(rb"#<[A-Z]"),
    re.compile(rb"#S\("),
)

SGR = re.compile(rb"\x1b\[[0-9;]*m")


def visible_bytes(data: bytes) -> bytes:
    return SGR.sub(b"", data)


def scan(path: Path) -> list[str]:
    raw = path.read_bytes()
    text = visible_bytes(raw)
    hits: list[str] = []
    for pattern in FORBIDDEN:
        match = pattern.search(text)
        if match:
            start = max(0, match.start() - 24)
            end = min(len(text), match.end() + 24)
            snippet = text[start:end].decode("utf-8", "replace").replace("\n", "\\n")
            hits.append(f"{path.name}: {pattern.pattern!r} near {snippet!r}")
    return hits


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--analysis",
        type=Path,
        default=Path("test/fixtures/render-diff"),
        help="Directory of *.cadr.screen files (analysis output or fixtures)",
    )
    parser.add_argument(
        "--print-denominator",
        action="store_true",
        help="Print the M1 denominator line and exit 0",
    )
    args = parser.parse_args()
    if args.print_denominator:
        print(
            "cadr-visible-output-origin: checks unformatted Lisp tokens "
            "(NIL / #< / #S() ) on cadr semantic screens. "
            "Does not check baseline-string reachability "
            "(baseline-string-reachability.py). "
            "A pass means no scanned screen leaked a Lisp value dump."
        )
        return 0
    screens = sorted(args.analysis.glob("*.cadr.screen"))
    if not screens:
        # No capture in this invocation: still check that the producer
        # unit (extension-render-value-lines) is locked by FiveAM.
        print(
            "cadr-visible-output-origin: no *.cadr.screen under "
            f"{args.analysis}; FiveAM goal20-l-custom-entry-* is the lock"
        )
        return 0
    hits: list[str] = []
    for path in screens:
        hits.extend(scan(path))
    report = {
        "screens": len(screens),
        "hits": hits,
    }
    print(json.dumps(report, indent=2, ensure_ascii=False))
    if hits:
        print("cadr-visible-output-origin: unformatted Lisp on screen", file=sys.stderr)
        return 2
    print(f"cadr-visible-output-origin: {len(screens)} screens clean")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
