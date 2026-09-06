#!/usr/bin/env python3
"""Ensure disposition skeleton entries from manifest + render-diff analysis."""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "test/fixtures/render-diff/scenarios.json"
DEFAULT_DISPOSITIONS = ROOT / "test/fixtures/render-diff/dispositions.json"
DEFAULT_CLASS_RULES = ROOT / "test/fixtures/render-diff/disposition-class-rules.json"
DEFAULT_ANALYSIS = Path("/tmp/goal21-render-diff-analysis")
KEY_RE = re.compile(r"^([^/]+)/([^/]+)/([^/]+)$")


def load_render_diff() -> Any:
    spec = importlib.util.spec_from_file_location("render_diff", ROOT / "scripts/render-diff.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load scripts/render-diff.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_key(key: str) -> tuple[str, str, str]:
    match = KEY_RE.fullmatch(key)
    if match is None:
        raise ValueError(f"invalid render-diff key: {key}")
    return match.group(1), match.group(2), match.group(3)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--dispositions", type=Path, default=DEFAULT_DISPOSITIONS)
    parser.add_argument("--analysis", type=Path, default=DEFAULT_ANALYSIS)
    parser.add_argument("--class-rules", type=Path, default=DEFAULT_CLASS_RULES)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def build_entry(group: list[dict[str, Any]], classes: list[str], note: str) -> dict[str, Any]:
    scenario, _, checkpoint = parse_key(group[0]["key"])
    dimensions = sorted({parse_key(row["key"])[1] for row in group})
    screen_sha256: dict[str, dict[str, str]] = {}
    for row in group:
        _, dimension, _ = parse_key(row["key"])
        screen_sha256[dimension] = {
            "pi": row["piScreenSha256"],
            "cadr": row["cadrScreenSha256"],
        }
    return {
        "scenario": scenario,
        "checkpoint": checkpoint,
        "dimensions": dimensions,
        "classes": classes,
        "screenSha256": screen_sha256,
        "note": note,
    }


def main() -> int:
    args = parse_args()
    rd = load_render_diff()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    data = json.loads(args.dispositions.read_text(encoding="utf-8"))
    expanded = rd.expand_dispositions(data, manifest)
    rules = rd.load_disposition_class_rules(args.class_rules.resolve())

    summary_path = args.analysis / "summary.json"
    if not summary_path.is_file():
        print(f"goal21-render-diff-ensure-skeletons: missing {summary_path}", file=sys.stderr)
        return 2

    results = json.loads(summary_path.read_text(encoding="utf-8"))
    by_key = {row["key"]: row for row in results}
    missing = [
        row["key"]
        for row in results
        if row.get("automaticDisposition") != "aligned" and row["key"] not in expanded
    ]

    grouped: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for key in missing:
        if key not in by_key:
            continue
        scenario, _, checkpoint = parse_key(key)
        grouped[(scenario, checkpoint)].append(by_key[key])

    drafts: list[dict[str, Any]] = []
    skipped_class_rules = 0
    for group in grouped.values():
        if all(rd.matching_class_rule(row, rules) is not None for row in group):
            skipped_class_rules += len(group)
            continue
        row = group[0]
        if row.get("automaticDisposition") == "intentional-terminal-protocol":
            classes = ["I01"]
            note = (
                f"At {row['scenario']}/{row['checkpoint']} ["
                + "+".join(sorted({parse_key(item['key'])[1] for item in group}))
                + "] skeleton from manifest sync: I01 terminal protocol."
            )
        elif row.get("textGeometryEqual"):
            classes = ["I01", "I04"]
            note = (
                f"At {row['scenario']}/{row['checkpoint']} ["
                + "+".join(sorted({parse_key(item['key'])[1] for item in group}))
                + "] skeleton from manifest sync: I01+I04 text-geometry equal."
            )
        else:
            classes = ["I04"]
            note = (
                f"At {row['scenario']}/{row['checkpoint']} needs review — "
                "skeleton from manifest sync (visible text/geometry differs)."
            )
        drafts.append(build_entry(group, classes, note))

    if skipped_class_rules:
        print(
            "goal21-render-diff-ensure-skeletons: "
            f"skipped {skipped_class_rules} keys covered by class rules"
        )

    if not drafts:
        print("goal21-render-diff-ensure-skeletons: no skeletons needed")
        return 0

    if args.apply and not args.dry_run:
        by_target = {
            (entry["scenario"], entry["checkpoint"]): entry
            for entry in data.get("entries", [])
        }
        added = 0
        merged = 0
        for draft in drafts:
            target = (draft["scenario"], draft["checkpoint"])
            existing = by_target.get(target)
            if existing is None:
                data.setdefault("entries", []).append(draft)
                by_target[target] = draft
                added += 1
                continue
            # Wide-only pins must grow when a new dimension starts differing.
            screens = existing.setdefault("screenSha256", {})
            dims = list(existing.get("dimensions") or [])
            new_dims = [
                dim
                for dim in (draft.get("screenSha256") or {})
                if dim not in screens
            ]
            if not new_dims:
                continue
            for dim in new_dims:
                screens[dim] = draft["screenSha256"][dim]
                dims.append(dim)
            existing["dimensions"] = sorted(set(dims))
            classes = set(existing.get("classes") or []) | set(
                draft.get("classes") or []
            )
            existing["classes"] = sorted(classes, key=lambda value: int(value[1:]))
            note = (existing.get("note") or "").rstrip()
            existing["note"] = (
                note + f" Merged dimensions {new_dims} from skeleton sync."
            )
            merged += 1
        if added or merged:
            args.dispositions.write_text(
                json.dumps(data, indent=2) + "\n", encoding="utf-8"
            )
        print(
            "goal21-render-diff-ensure-skeletons: "
            f"applied {added} skeleton entries, merged {merged} dimension sets"
        )
        return 0

    print(f"goal21-render-diff-ensure-skeletons: would add {len(drafts)} skeleton entries (use --apply)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
