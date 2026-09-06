#!/usr/bin/env python3
"""Refresh stale screenSha256 pins in dispositions.json from analysis artifacts."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ANALYSIS = Path("/tmp/goal21-render-diff-analysis")
DEFAULT_DISPOSITIONS = ROOT / "test/fixtures/render-diff/dispositions.json"
CAPTURE_RE = re.compile(r"^(.+)\.([^.]+)\.([^.]+)\.(pi|cadr)\.screen$")
KEY_RE = re.compile(r"^([^/]+)/([^/]+)/([^/]+)$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--analysis", type=Path, default=DEFAULT_ANALYSIS)
    parser.add_argument("--dispositions", type=Path, default=DEFAULT_DISPOSITIONS)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def find_entry(entries: list[dict], scenario: str, checkpoint: str, dimension: str) -> dict | None:
    for entry in entries:
        if entry.get("scenario") != scenario or entry.get("checkpoint") != checkpoint:
            continue
        if dimension in (entry.get("dimensions") or []):
            return entry
    return None


def refresh_from_captures(analysis: Path, entries: list[dict]) -> list[str]:
    updated: list[str] = []
    for path in sorted(analysis.glob("*.screen")):
        match = CAPTURE_RE.match(path.name)
        if match is None or match.group(4) != "pi":
            continue
        scenario, dimension, checkpoint, _ = match.groups()
        cadr_path = analysis / f"{scenario}.{dimension}.{checkpoint}.cadr.screen"
        if not cadr_path.is_file():
            continue
        pi_hash = sha256_file(path)
        cadr_hash = sha256_file(cadr_path)
        entry = find_entry(entries, scenario, checkpoint, dimension)
        if entry is None:
            continue
        screen = entry.setdefault("screenSha256", {})
        current = screen.get(dimension, {})
        if current.get("pi") == pi_hash and current.get("cadr") == cadr_hash:
            continue
        screen[dimension] = {"pi": pi_hash, "cadr": cadr_hash}
        classes = set(entry.get("classes") or [])
        if pi_hash != cadr_hash:
            classes.add("I04")
        entry["classes"] = sorted(classes, key=lambda value: int(value[1:]))
        updated.append(f"{scenario}/{dimension}/{checkpoint}")
    return updated


def refresh_from_summary(summary: list[dict], entries: list[dict]) -> list[str]:
    updated: list[str] = []
    for row in summary:
        adjudication = row.get("adjudication")
        if not isinstance(adjudication, dict):
            continue
        expected = adjudication.get("screenSha256")
        if not isinstance(expected, dict):
            continue
        actual = {
            "pi": row.get("piScreenSha256"),
            "cadr": row.get("cadrScreenSha256"),
        }
        if actual["pi"] is None or actual["cadr"] is None or actual == expected:
            continue
        key = row.get("key", "")
        key_match = KEY_RE.fullmatch(key)
        if key_match is None:
            continue
        scenario, dimension, checkpoint = key_match.groups()
        entry = find_entry(entries, scenario, checkpoint, dimension)
        if entry is None:
            continue
        screen = entry.setdefault("screenSha256", {})
        screen[dimension] = actual
        classes = set(entry.get("classes") or [])
        if actual["pi"] != actual["cadr"]:
            classes.add("I04")
        entry["classes"] = sorted(classes, key=lambda value: int(value[1:]))
        updated.append(key)
    return updated


def clear_stale_i04_when_all_dims_equal(entries: list[dict]) -> list[str]:
    """Remove I04 when every pinned dimension is screen-equal."""
    cleared: list[str] = []
    for entry in entries:
        screens = entry.get("screenSha256") or {}
        dims = entry.get("dimensions") or []
        if not screens or not dims:
            continue
        if any(
            not isinstance(screens.get(dim), dict)
            or screens[dim].get("pi") != screens[dim].get("cadr")
            or not screens[dim].get("pi")
            for dim in dims
        ):
            continue
        classes = set(entry.get("classes") or [])
        if "I04" not in classes:
            continue
        classes.discard("I04")
        entry["classes"] = sorted(classes, key=lambda value: int(value[1:]))
        cleared.append(f"{entry.get('scenario')}/{entry.get('checkpoint')}")
    return cleared


def main() -> int:
    args = parse_args()
    if not args.dispositions.is_file():
        print(f"goal21-gate-refresh-hashes: missing {args.dispositions}", file=sys.stderr)
        return 2
    data = json.loads(args.dispositions.read_text(encoding="utf-8"))
    entries = data.get("entries", [])
    updated: list[str] = []

    summary_path = args.analysis / "summary.json"
    if summary_path.is_file():
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
        if isinstance(summary, list):
            updated.extend(refresh_from_summary(summary, entries))

    if args.analysis.is_dir():
        updated.extend(refresh_from_captures(args.analysis, entries))

    unique = sorted(set(updated))
    cleared = clear_stale_i04_when_all_dims_equal(entries)
    if cleared:
        unique = sorted(set(unique) | {f"clear-I04:{key}" for key in cleared})
    if not unique:
        print("goal21-gate-refresh-hashes: no hash updates needed")
        return 0
    if args.dry_run:
        print("goal21-gate-refresh-hashes: would update", ", ".join(unique))
        return 0
    args.dispositions.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"goal21-gate-refresh-hashes: updated {len(unique)} keys")
    for key in unique[:20]:
        print(f"  {key}")
    if len(unique) > 20:
        print(f"  ... and {len(unique) - 20} more")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
