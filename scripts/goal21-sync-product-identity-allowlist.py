#!/usr/bin/env python3
"""Sync docs/product-identity-allowlist.json with the current identity scan."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "docs/product-identity-allowlist.json"

GOAL21_REASON = (
    "Goal 21 gate orchestration cites upstream baseline contracts; "
    "not shipped Cadr identity."
)
RENDER_DIFF_HARNESS_REASON = (
    "Fixed-baseline differential harness must name upstream pi artifacts, "
    "identity strings, paths, CLI, and side keys exactly; none define Cadr identity."
)
VERIFY_BASELINE_ENV_REASON = (
    "Internal fixed-baseline harness name or normalization marker; "
    "it is not a Cadr runtime environment variable."
)
VERIFY_PI_REPO_REASON = (
    "Verification passes the repository to the fixed-baseline differential "
    "through its --pi-repo contract."
)


def finding_key(entry: dict[str, object]) -> tuple[str, str, str, str]:
    return (
        str(entry["path"]),
        str(entry["kind"]),
        str(entry["token"]),
        str(entry["line"]),
    )


def default_reason(path: str, kind: str, token: str, line: str) -> str:
    if path.startswith("scripts/goal21-"):
        return GOAL21_REASON
    if path == "scripts/render-diff.py":
        return RENDER_DIFF_HARNESS_REASON
    if path == "scripts/verify.sh":
        if kind == "legacy-env":
            return VERIFY_BASELINE_ENV_REASON
        if "pi-repo" in line:
            return VERIFY_PI_REPO_REASON
        return RENDER_DIFF_HARNESS_REASON
    if kind == "legacy-env":
        return VERIFY_BASELINE_ENV_REASON
    return RENDER_DIFF_HARNESS_REASON


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def load_inventory() -> dict[str, object]:
    output = subprocess.check_output(
        [
            "python3",
            str(ROOT / "scripts/check-product-identity.py"),
            "--root",
            str(ROOT),
            "--inventory",
        ],
        text=True,
    )
    document = json.loads(output)
    if not isinstance(document, dict):
        raise RuntimeError("inventory output must be an object")
    return document


def load_manifest(path: Path) -> dict[str, object]:
    document = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(document, dict) or document.get("schema") != 1:
        raise RuntimeError("product identity allowlist schema must be 1")
    return document


def main() -> int:
    args = parse_args()
    manifest_path = args.manifest.resolve()
    document = load_manifest(manifest_path)
    inventory = load_inventory()
    entries = inventory.get("entries")
    if not isinstance(entries, list):
        print("goal21-sync-product-identity-allowlist: invalid inventory entries", file=sys.stderr)
        return 2

    allow = document.get("allow")
    if not isinstance(allow, list):
        print("goal21-sync-product-identity-allowlist: invalid allow array", file=sys.stderr)
        return 2

    opaque_paths: set[str] = set()
    opaque_files = document.get("opaque_files")
    if isinstance(opaque_files, list):
        for entry in opaque_files:
            if isinstance(entry, dict) and isinstance(entry.get("path"), str):
                opaque_paths.add(entry["path"])

    reason_by_exact: dict[tuple[str, str, str, str], str] = {}
    reason_by_path_kind_token: dict[tuple[str, str, str], str] = {}
    old_keys: set[tuple[str, str, str, str]] = set()
    for entry in allow:
        if not isinstance(entry, dict):
            continue
        key = finding_key(entry)
        old_keys.add(key)
        reason = str(entry.get("reason", "")).strip()
        if reason:
            reason_by_exact[key] = reason
            reason_by_path_kind_token.setdefault(
                (str(entry["path"]), str(entry["kind"]), str(entry["token"])),
                reason,
            )

    new_allow: list[dict[str, object]] = []
    added = 0
    new_keys: set[tuple[str, str, str, str]] = set()
    total = 0
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        key = finding_key(entry)
        if key[0] in opaque_paths:
            continue
        new_keys.add(key)
        count = entry.get("occurrences")
        if not isinstance(count, int) or isinstance(count, bool) or count <= 0:
            print(f"goal21-sync-product-identity-allowlist: bad occurrences for {key[0]}", file=sys.stderr)
            return 2
        total += count
        if key in reason_by_exact:
            reason = reason_by_exact[key]
        else:
            reason = reason_by_path_kind_token.get(
                (key[0], key[1], key[2]),
                default_reason(key[0], key[1], key[2], key[3]),
            )
            added += 1
        new_allow.append(
            {
                "path": key[0],
                "kind": key[1],
                "token": key[2],
                "line": key[3],
                "occurrences": count,
                "reason": reason,
            }
        )

    removed = len(old_keys - new_keys)
    print(
        "goal21-sync-product-identity-allowlist: "
        f"findings={total} entries={len(new_allow)} "
        f"added={added} removed={removed} "
        f"expected_findings {document.get('expected_findings')} -> {total}"
    )

    if not args.apply:
        if args.dry_run:
            return 0
        print("goal21-sync-product-identity-allowlist: pass --apply to write", file=sys.stderr)
        return 1

    document["expected_findings"] = total
    document["allow"] = new_allow
    manifest_path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    print(f"goal21-sync-product-identity-allowlist: wrote {manifest_path}")

    verify = subprocess.run(
        [
            "python3",
            str(ROOT / "scripts/check-product-identity.py"),
            "--root",
            str(ROOT),
            "--manifest",
            str(manifest_path),
        ],
        check=False,
    )
    return verify.returncode


if __name__ == "__main__":
    raise SystemExit(main())
