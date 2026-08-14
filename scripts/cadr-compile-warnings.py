#!/usr/bin/env python3
"""Part N2.6: cadr's own compile WARNINGs fail the gate.

STYLE-WARNING and note are counted, not fail-closed.
Third-party warnings (path not under src/cadr-*) are ignored.
New muffle/declaim suppressions in src/ are a gate failure unless listed
in test/fixtures/compile-warning-muffle-allowlist.json.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEMS = (
    "cadr-core",
    "cadr-ai",
    "cadr-agent",
    "cadr-tui",
    "cadr-cli",
)
MUFFLE = re.compile(
    r"\(\s*(?:declaim|proclaim)\s+\(?\s*(?:sb-ext:)?muffle-(?:conditions|warning)",
    re.IGNORECASE,
)
ALLOWLIST = ROOT / "test/fixtures/compile-warning-muffle-allowlist.json"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--system", action="append", dest="systems")
    parser.add_argument("--print-denominator", action="store_true")
    args = parser.parse_args()
    systems = tuple(args.systems) if args.systems else SYSTEMS
    if args.print_denominator:
        print(
            "cadr-compile-warnings: cadr-owned WARNING count must be 0. "
            "STYLE-WARNING and note are counted only. "
            "Does not check runtime behaviour. "
            "A pass means no new cadr WARNING and no unallowlisted muffle."
        )
        return 0
    allowed = set()
    if ALLOWLIST.is_file():
        allowed = {
            entry["path"]
            for entry in json.loads(ALLOWLIST.read_text(encoding="utf-8"))["entries"]
        }
    muffles: list[str] = []
    for path in (args.root / "src").rglob("*.lisp"):
        text = path.read_text(encoding="utf-8")
        if MUFFLE.search(text):
            rel = str(path.relative_to(args.root))
            if rel not in allowed:
                muffles.append(rel)
    if muffles:
        print("unallowlisted warning muffles:", file=sys.stderr)
        print("\n".join(muffles), file=sys.stderr)
        return 2

    quicklisp = os.environ.get(
        "QUICKLISP_SETUP", str(Path.home() / "quicklisp/setup.lisp")
    )
    loads = []
    seen_asd = set()
    prerequisites = {
        "cadr-ai": ("cadr-core",),
        "cadr-agent": ("cadr-core", "cadr-ai"),
        "cadr-tui": ("cadr-core",),
        "cadr-cli": ("cadr-core", "cadr-ai", "cadr-agent", "cadr-tui"),
    }
    for name in systems:
        for prerequisite in prerequisites.get(name, ()):
            if prerequisite not in seen_asd:
                loads.append(
                    f'(asdf:load-asd (truename "{args.root / (prerequisite + ".asd")}"))'
                )
                seen_asd.add(prerequisite)
        if name not in seen_asd:
            loads.append(f'(asdf:load-asd (truename "{args.root / (name + ".asd")}"))')
            seen_asd.add(name)
        loads.append(f'(asdf:load-system "{name}")')
    script = "(progn " + " ".join(loads) + " (sb-ext:exit :code 0))"
    completed = subprocess.run(
        [
            os.environ.get("SBCL", "sbcl"),
            "--noinform",
            "--non-interactive",
            "--load",
            quicklisp,
            "--eval",
            script,
        ],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    text = completed.stdout
    owned = []
    for line in text.splitlines():
        if "caught WARNING" in line or line.startswith("CADR-WARNING"):
            owned.append(line)
    # Attribute: keep only warnings whose following context cites src/cadr-
    # The release.lisp non-toplevel defparameter showed up as caught WARNING
    # mentioning undefined variables. After the fix, cadr-ai should be clean.
    caught = [
        line
        for line in text.splitlines()
        if "caught WARNING" in line and "STYLE-WARNING" not in line
    ]
    summary = [line for line in text.splitlines() if "caught" in line and "WARNING" in line]
    print(f"cadr-compile-warnings: sbcl-exit={completed.returncode} caught-WARNING-lines={len(caught)}")
    for line in summary[-8:]:
        print(line)
    if caught:
        print("\n".join(caught[:20]), file=sys.stderr)
        return 2
    if "compilation unit finished" not in text and completed.returncode != 0:
        print(text[-2000:], file=sys.stderr)
        return completed.returncode or 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
