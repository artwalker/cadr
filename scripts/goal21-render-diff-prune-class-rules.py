#!/usr/bin/env python3
"""Prune ledger dispositions fully covered by disposition-class-rules.json."""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "test/fixtures/render-diff/scenarios.json"
DEFAULT_DISPOSITIONS = ROOT / "test/fixtures/render-diff/dispositions.json"
DEFAULT_CLASS_RULES = ROOT / "test/fixtures/render-diff/disposition-class-rules.json"
DEFAULT_ANALYSIS = Path("/tmp/goal21-render-diff-analysis")
DEFAULT_REPORT = Path("/tmp/goal21-disposition-prune-report.json")

ALLOWED_PRUNE_CLASSES = frozenset({"I01", "I04"})


def load_render_diff() -> Any:
    spec = importlib.util.spec_from_file_location("render_diff", ROOT / "scripts/render-diff.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load scripts/render-diff.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--dispositions", type=Path, default=DEFAULT_DISPOSITIONS)
    parser.add_argument("--class-rules", type=Path, default=DEFAULT_CLASS_RULES)
    parser.add_argument("--analysis", type=Path, default=DEFAULT_ANALYSIS)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def entry_keys(entry: dict[str, Any]) -> list[str]:
    scenario = entry["scenario"]
    checkpoint = entry["checkpoint"]
    return [f"{scenario}/{dimension}/{checkpoint}" for dimension in entry["dimensions"]]


def entry_prunable(
    entry: dict[str, Any],
    by_key: dict[str, dict[str, Any]],
    rules: list[dict[str, Any]],
    rd: Any,
) -> bool:
    classes = set(entry.get("classes", []))
    if not classes or classes - ALLOWED_PRUNE_CLASSES:
        return False
    for key in entry_keys(entry):
        row = by_key.get(key)
        if row is None:
            return False
        if rd.matching_class_rule(row, rules) is None:
            return False
    return True


def main() -> int:
    args = parse_args()
    rd = load_render_diff()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    data = json.loads(args.dispositions.read_text(encoding="utf-8"))
    rules = rd.load_disposition_class_rules(args.class_rules.resolve())

    summary_path = args.analysis / "summary.json"
    if not summary_path.is_file():
        print(
            f"goal21-render-diff-prune-class-rules: missing {summary_path} "
            "(run render-diff analyze first)",
            file=sys.stderr,
        )
        return 2

    results = json.loads(summary_path.read_text(encoding="utf-8"))
    by_key = {row["key"]: row for row in results}

    prunable: list[dict[str, Any]] = []
    kept: list[dict[str, Any]] = []
    for entry in data.get("entries", []):
        if entry_prunable(entry, by_key, rules, rd):
            prunable.append(entry)
        else:
            kept.append(entry)

    pruned_keys = sorted(
        key for entry in prunable for key in entry_keys(entry)
    )
    report = {
        "entryCount": len(data.get("entries", [])),
        "prunableEntries": len(prunable),
        "keptEntries": len(kept),
        "prunedKeys": pruned_keys,
        "applied": False,
    }
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        "goal21-render-diff-prune-class-rules: "
        f"entries={report['entryCount']} prunable={report['prunableEntries']} "
        f"keys={len(pruned_keys)} report={args.report}"
    )

    if not prunable:
        return 0

    if args.apply and not args.dry_run:
        data["entries"] = kept
        rd.expand_dispositions(data, manifest)
        args.dispositions.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        report["applied"] = True
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"goal21-render-diff-prune-class-rules: removed {len(prunable)} entries")

    elif not args.dry_run:
        print("goal21-render-diff-prune-class-rules: dry-run only (pass --apply to write)")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
