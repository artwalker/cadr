#!/usr/bin/env python3
"""Fail closed when an oversized production file lacks a reviewed reason."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


class GateError(Exception):
    pass


def physical_line_count(path: Path) -> int:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise GateError(f"cannot read UTF-8 production file {path}: {error}") from error
    return len(text.splitlines())


def load_manifest(path: Path) -> tuple[int, str, dict[str, str]]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise GateError(f"cannot read organization manifest {path}: {error}") from error

    if not isinstance(document, dict) or document.get("schema") != 1:
        raise GateError("organization manifest schema must be 1")
    threshold = document.get("threshold")
    if not isinstance(threshold, dict):
        raise GateError("organization manifest requires a threshold object")
    lines = threshold.get("lines")
    if not isinstance(lines, int) or isinstance(lines, bool) or lines <= 0:
        raise GateError("organization threshold lines must be a positive integer")
    if threshold.get("comparison") != "at-or-above":
        raise GateError("organization threshold comparison must be at-or-above")
    basis = threshold.get("basis")
    if not isinstance(basis, str) or not basis.strip():
        raise GateError("organization threshold requires a non-empty Part A basis")

    raw_exemptions = document.get("exemptions")
    if not isinstance(raw_exemptions, list):
        raise GateError("organization manifest exemptions must be an array")
    exemptions: dict[str, str] = {}
    for index, entry in enumerate(raw_exemptions, start=1):
        if not isinstance(entry, dict):
            raise GateError(f"exemption {index} must be an object")
        path_value = entry.get("path")
        reason = entry.get("reason")
        if not isinstance(path_value, str) or not path_value.startswith("src/"):
            raise GateError(f"exemption {index} path must be repository-relative under src/")
        relative = Path(path_value)
        if relative.is_absolute() or ".." in relative.parts or relative.as_posix() != path_value:
            raise GateError(f"invalid exemption path: {path_value}")
        if path_value in exemptions:
            raise GateError(f"duplicate exemption path: {path_value}")
        if not isinstance(reason, str) or not reason.strip():
            raise GateError(f"exemption {path_value} requires a non-empty reason")
        exemptions[path_value] = reason.strip()
    return lines, basis.strip(), exemptions


def scan_sources(root: Path) -> dict[str, int]:
    source_root = root / "src"
    if not source_root.is_dir():
        raise GateError(f"production source directory is missing: {source_root}")
    result: dict[str, int] = {}
    for path in sorted(source_root.rglob("*")):
        if path.is_symlink():
            raise GateError(f"production source symlink requires explicit policy: {path}")
        if path.is_file():
            relative = path.relative_to(root).as_posix()
            result[relative] = physical_line_count(path)
    return result


# The user-level path layout is decided once in cadr-core/paths.lisp and
# migrated once in cadr-cli/migration.lisp; no other production file may
# re-decide it with a ".cadr/ literal.
PATH_LITERAL_ALLOWED = frozenset(
    {
        "src/cadr-core/paths.lisp",
        "src/cadr-cli/migration.lisp",
    }
)


def scan_path_literals(root: Path) -> list[str]:
    violations: list[str] = []
    for path in sorted((root / "src").rglob("*.lisp")):
        relative = path.relative_to(root).as_posix()
        if relative in PATH_LITERAL_ALLOWED:
            continue
        for line_number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(), start=1
        ):
            if '".cadr/' in line:
                violations.append(f"{relative}:{line_number}")
    return violations


def run(root: Path, manifest: Path) -> int:
    root = root.resolve()
    manifest = manifest.resolve()
    threshold, _basis, exemptions = load_manifest(manifest)
    sources = scan_sources(root)
    literal_violations = scan_path_literals(root)
    if literal_violations:
        for violation in literal_violations:
            print(
                "code organization gate: "
                f'path literal outside the owner: {violation} contains ".cadr/"',
                file=sys.stderr,
            )
        return 1
    oversized = {
        path: lines for path, lines in sources.items() if lines >= threshold
    }

    failures: list[str] = []
    for path in sorted(set(oversized) - set(exemptions)):
        failures.append(
            f"unreviewed oversized file: {path} ({oversized[path]} lines)"
        )
    for path in sorted(set(exemptions) - set(oversized)):
        if path not in sources:
            failures.append(f"stale exemption: {path} does not exist")
        else:
            failures.append(
                f"stale exemption: {path} is {sources[path]} lines, below {threshold}"
            )
    if failures:
        for failure in failures:
            print(f"code organization gate: {failure}", file=sys.stderr)
        print(
            "code organization gate: this is a symptom detector only; "
            "review ownership before changing the exemption list",
            file=sys.stderr,
        )
        return 1

    print(
        "Code organization gate: "
        f"{len(sources)} production files, threshold >= {threshold} lines, "
        f"{len(exemptions)} reviewed exemptions; symptom detector only."
    )
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        return run(arguments.root, arguments.manifest)
    except GateError as error:
        print(f"code organization gate: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
