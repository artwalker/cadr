#!/usr/bin/env python3
"""Generate and apply render-diff disposition drafts from analysis artifacts."""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "test/fixtures/render-diff/scenarios.json"
DEFAULT_DISPOSITIONS = ROOT / "test/fixtures/render-diff/dispositions.json"
DEFAULT_ANALYSIS = Path("/tmp/goal21-render-diff-analysis")
DEFAULT_DRAFT = Path("/tmp/goal21-disposition-draft.json")
DEFAULT_REPORT = Path("/tmp/goal21-disposition-sync-report.json")

KEY_RE = re.compile(r"^([^/]+)/([^/]+)/([^/]+)$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--analysis", type=Path, default=DEFAULT_ANALYSIS)
    parser.add_argument("--dispositions", type=Path, default=DEFAULT_DISPOSITIONS)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--draft", type=Path, default=DEFAULT_DRAFT)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--auto-apply", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def expanded_keys(data: dict[str, Any]) -> set[str]:
    keys: set[str] = set()
    for entry in data.get("entries", []):
        scenario = entry["scenario"]
        checkpoint = entry["checkpoint"]
        for dimension in entry["dimensions"]:
            keys.add(f"{scenario}/{dimension}/{checkpoint}")
    return keys


def parse_key(key: str) -> tuple[str, str, str]:
    match = KEY_RE.fullmatch(key)
    if match is None:
        raise ValueError(f"invalid render-diff key: {key}")
    return match.group(1), match.group(2), match.group(3)


def suggest_classes(group: list[dict[str, Any]]) -> tuple[list[str] | None, str, str]:
    if all(row["automaticDisposition"] == "intentional-terminal-protocol" for row in group):
        scenario, _, checkpoint = parse_key(group[0]["key"])
        note = (
            f"At {scenario}/{checkpoint} ["
            + "+".join(sorted({parse_key(row['key'])[1] for row in group}))
            + "] the visible text is identical to pi; the raw ANSI update segmentation/teardown differs (I01)."
        )
        return ["I01"], note, "auto-i01-terminal-protocol"

    if all(row["automaticDisposition"] == "requires-disposition" for row in group) and all(
        row.get("textGeometryEqual", True) for row in group
    ):
        scenario, _, checkpoint = parse_key(group[0]["key"])
        note = (
            f"At {scenario}/{checkpoint} ["
            + "+".join(sorted({parse_key(row['key'])[1] for row in group}))
            + "] the visible text matches pi under identity substitution; remaining differences are adjudicated I04 substitutions and terminal protocol (I01)."
        )
        return ["I01", "I04"], note, "auto-i01-i04-text-geometry-equal"

    scenario, _, checkpoint = parse_key(group[0]["key"])
    return (
        None,
        f"Needs review: {scenario}/{checkpoint} has visible text/geometry differences requiring a text-covering class.",
        "needs-review",
    )


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


def remove_stale_keys(data: dict[str, Any], stale: set[str]) -> list[str]:
    removed: list[str] = []
    new_entries: list[dict[str, Any]] = []
    for entry in data.get("entries", []):
        scenario = entry["scenario"]
        checkpoint = entry["checkpoint"]
        keep_dimensions: list[str] = []
        screen_pairs = dict(entry.get("screenSha256", {}))
        for dimension in entry.get("dimensions", []):
            key = f"{scenario}/{dimension}/{checkpoint}"
            if key in stale:
                removed.append(key)
                screen_pairs.pop(dimension, None)
            else:
                keep_dimensions.append(dimension)
        if not keep_dimensions:
            continue
        updated = dict(entry)
        updated["dimensions"] = keep_dimensions
        updated["screenSha256"] = screen_pairs
        new_entries.append(updated)
    data["entries"] = new_entries
    return removed


def merge_draft_entries(
    data: dict[str, Any], drafts: list[dict[str, Any]]
) -> list[str]:
    added: list[str] = []
    by_target: dict[tuple[str, str], dict[str, Any]] = {
        (entry["scenario"], entry["checkpoint"]): entry for entry in data.get("entries", [])
    }
    for draft in drafts:
        target = (draft["scenario"], draft["checkpoint"])
        existing = by_target.get(target)
        if existing is None:
            data.setdefault("entries", []).append(draft)
            by_target[target] = draft
            for dimension in draft["dimensions"]:
                added.append(f"{draft['scenario']}/{dimension}/{draft['checkpoint']}")
            continue
        for dimension in draft["dimensions"]:
            key = f"{draft['scenario']}/{dimension}/{draft['checkpoint']}"
            if dimension in existing.get("dimensions", []):
                continue
            existing.setdefault("dimensions", []).append(dimension)
            existing["dimensions"] = sorted(set(existing["dimensions"]))
            existing.setdefault("screenSha256", {})[dimension] = draft["screenSha256"][dimension]
            added.append(key)
        if set(existing.get("classes", [])) != set(draft["classes"]):
            existing["classes"] = draft["classes"]
            existing["note"] = draft["note"]
    return added


def main() -> int:
    args = parse_args()
    summary_path = args.analysis / "summary.json"
    pending_path = args.analysis / "pending-dispositions.json"
    if not summary_path.is_file():
        print(f"goal21-render-diff-sync: missing {summary_path}", file=sys.stderr)
        return 2

    results = load_json(summary_path)
    if pending_path.is_file():
        pending = load_json(pending_path)
        missing = list(pending.get("missing", []))
        stale = list(pending.get("stale", []))
    else:
        data = load_json(args.dispositions)
        expanded = expanded_keys(data)
        required = {
            row["key"]
            for row in results
            if row.get("automaticDisposition") != "aligned"
        }
        missing = sorted(required - expanded)
        stale = sorted(expanded - required)

    grouped: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    by_key = {row["key"]: row for row in results}
    for key in missing:
        if key not in by_key:
            continue
        scenario, _, checkpoint = parse_key(key)
        grouped[(scenario, checkpoint)].append(by_key[key])

    auto_drafts: list[dict[str, Any]] = []
    review_drafts: list[dict[str, Any]] = []
    for group in grouped.values():
        classes, note, kind = suggest_classes(group)
        draft = build_entry(group, classes or ["I04"], note)
        draft["syncKind"] = kind
        if classes is None:
            review_drafts.append(draft)
        else:
            auto_drafts.append(draft)

    draft_payload = {
        "autoApply": auto_drafts,
        "needsReview": review_drafts,
        "missing": missing,
        "stale": stale,
    }
    args.draft.write_text(json.dumps(draft_payload, indent=2) + "\n", encoding="utf-8")

    report: dict[str, Any] = {
        "missing": missing,
        "stale": stale,
        "autoApplyCount": len(auto_drafts),
        "needsReviewCount": len(review_drafts),
        "applied": False,
        "removedStale": [],
        "addedKeys": [],
    }

    if args.auto_apply and not args.dry_run and (auto_drafts or stale):
        data = load_json(args.dispositions)
        if stale:
            report["removedStale"] = remove_stale_keys(data, set(stale))
        if auto_drafts:
            report["addedKeys"] = merge_draft_entries(data, auto_drafts)
        args.dispositions.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        report["applied"] = True

    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        "goal21-render-diff-sync: "
        f"missing={len(missing)} stale={len(stale)} "
        f"auto={len(auto_drafts)} review={len(review_drafts)} "
        f"applied={report['applied']} draft={args.draft}"
    )
    if review_drafts and not auto_drafts and not report["applied"]:
        return 1
    if missing and not report["applied"] and not review_drafts:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
