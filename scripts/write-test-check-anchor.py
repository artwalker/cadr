#!/usr/bin/env python3
"""Write or verify the Goal 20 FiveAM check-count ledger comment.

Goal 20 Part B: the check count is a CI product, not a hand-edited number.
scripts/test-cl.sh writes the comment after a green nine-system run;
--strict fails when the committed comment drifted from this run.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

COMMENT_RE = re.compile(
    r"<!-- GOAL20_TEST_CHECKS systems=\d+ checks=\d+ "
    r"pass=\d+ skip=\d+ fail=\d+ -->"
)
SUMMARY_RE = re.compile(
    r"systems=(\d+) checks=(\d+) pass=(\d+) skip=(\d+) fail=(\d+)\s*$"
)
FIELD_RE = re.compile(
    r"GOAL20_TEST_CHECKS systems=(\d+) checks=(\d+) "
    r"pass=(\d+) skip=(\d+) fail=(\d+)"
)


def parse_summary(text: str) -> dict[str, int]:
    match = SUMMARY_RE.search(text.strip())
    if match is None:
        raise ValueError(f"unparseable FiveAM summary: {text!r}")
    fields = {
        "systems": int(match.group(1)),
        "checks": int(match.group(2)),
        "passed": int(match.group(3)),
        "skip": int(match.group(4)),
        "fail": int(match.group(5)),
    }
    validate_fields(fields)
    return fields


def parse_comment(markdown: str) -> dict[str, int]:
    match = COMMENT_RE.search(markdown)
    if match is None:
        raise ValueError("docs/test-matrix.md is missing GOAL20_TEST_CHECKS")
    fields_match = FIELD_RE.search(match.group(0))
    if fields_match is None:
        raise ValueError(f"unparseable GOAL20_TEST_CHECKS: {match.group(0)!r}")
    fields = {
        "systems": int(fields_match.group(1)),
        "checks": int(fields_match.group(2)),
        "passed": int(fields_match.group(3)),
        "skip": int(fields_match.group(4)),
        "fail": int(fields_match.group(5)),
    }
    validate_fields(fields)
    return fields


def validate_fields(fields: dict[str, int]) -> None:
    if fields["systems"] != 9:
        raise ValueError(f"expected systems=9, got {fields['systems']}")
    if fields["fail"] != 0:
        raise ValueError(f"expected fail=0, got {fields['fail']}")
    if fields["checks"] != fields["passed"] + fields["skip"] + fields["fail"]:
        raise ValueError(
            "checks must equal pass+skip+fail: "
            f"{fields['checks']} != {fields['passed']}+{fields['skip']}+{fields['fail']}"
        )
    if fields["checks"] < 1:
        raise ValueError("checks must be positive")


def render_comment(fields: dict[str, int]) -> str:
    return (
        "<!-- GOAL20_TEST_CHECKS "
        f"systems={fields['systems']} checks={fields['checks']} "
        f"pass={fields['passed']} skip={fields['skip']} "
        f"fail={fields['fail']} -->"
    )


def apply_comment(markdown: str, fields: dict[str, int]) -> str:
    comment = render_comment(fields)
    if COMMENT_RE.search(markdown):
        return COMMENT_RE.sub(comment, markdown, count=1)
    lines = markdown.splitlines(keepends=True)
    if not lines:
        return comment + "\n"
    return lines[0] + "\n" + comment + "\n" + "".join(lines[1:])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--summary", help="cadr test summary line from test-cl.sh")
    parser.add_argument(
        "--ledger",
        type=Path,
        default=Path("docs/test-matrix.md"),
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="write the comment and exit 1 when the file changed",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="check the committed comment is well-formed; do not write",
    )
    args = parser.parse_args()
    try:
        markdown = args.ledger.read_text(encoding="utf-8")
        if args.verify:
            fields = parse_comment(markdown)
            if args.summary:
                live = parse_summary(args.summary)
                if fields != live:
                    print(
                        "test-check-anchor: GOAL20_TEST_CHECKS does not match "
                        f"this run (ledger checks={fields['checks']}, "
                        f"live checks={live['checks']})",
                        file=sys.stderr,
                    )
                    return 1
            print(
                "test-check-anchor: "
                f"systems={fields['systems']} checks={fields['checks']} "
                f"pass={fields['passed']} skip={fields['skip']} "
                f"fail={fields['fail']}"
            )
            return 0
        if not args.summary:
            raise ValueError("--summary is required unless --verify")
        live = parse_summary(args.summary)
        try:
            previous = parse_comment(markdown)
        except ValueError:
            previous = None
        if (
            previous is not None
            and previous["checks"] >= 1000
            and live["checks"] * 10 < previous["checks"]
        ):
            raise ValueError(
                f"refusing to drop GOAL20_TEST_CHECKS from {previous['checks']} "
                f"to {live['checks']}; set CADR_TEST_CHECK_LEDGER to a fixture "
                "file for synthetic test-cl.sh runs"
            )
        updated = apply_comment(markdown, live)
        changed = updated != markdown
        if changed:
            args.ledger.write_text(updated, encoding="utf-8")
        print(
            "test-check-anchor: "
            f"systems={live['systems']} checks={live['checks']} "
            f"pass={live['passed']} skip={live['skip']} "
            f"fail={live['fail']} changed={'yes' if changed else 'no'} "
            f"output={args.ledger}"
        )
        if args.strict and changed:
            print(
                "test-check-anchor: GOAL20_TEST_CHECKS drifted; "
                f"wrote {args.ledger} — commit that file and re-run",
                file=sys.stderr,
            )
            return 1
        return 0
    except (OSError, ValueError) as error:
        print(f"test-check-anchor: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
