#!/usr/bin/env python3
"""Fail closed when an upstream product identity lacks an exact disposition."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


SCAN_DIRECTORIES = ("src", "examples", "scripts", ".github")
SCAN_ROOT_FILES = ("README.md", "CHANGELOG.md")
ROOT_PATTERNS = ("*.asd", "build*.sh", "build*.lisp")
LEGACY_ENVIRONMENT = re.compile(r"(?<![A-Za-z0-9_])PI_[A-Z0-9_]+(?![A-Za-z0-9_])")
UPSTREAM_ORGANIZATION = re.compile(r"badlogic|earendil-works", re.IGNORECASE)
PRODUCT_TOKEN_PATTERN = re.compile(
    r"(?<![A-Za-z0-9])pi(?=$|[^A-Za-z0-9])", re.IGNORECASE
)
VALID_KINDS = frozenset(("legacy-env", "upstream-org", "pi-token"))
HEX_DIGEST = re.compile(r"[0-9a-f]{64}")


class GateError(Exception):
    pass


@dataclass(frozen=True, order=True)
class Finding:
    path: str
    kind: str
    token: str
    line: str


def valid_relative_file(value: object) -> str:
    if not isinstance(value, str) or not value:
        raise GateError("disposition path must be an exact repository-relative file")
    path = Path(value)
    if (
        path.is_absolute()
        or ".." in path.parts
        or path.as_posix() != value
        or any(character in value for character in "*?[]")
    ):
        raise GateError(
            f"disposition path must be an exact repository-relative file: {value}"
        )
    return value


def read_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise GateError(f"cannot read identity allowlist {path}: {error}") from error


def load_manifest(
    path: Path,
) -> tuple[int, Counter[Finding], dict[Finding, str], dict[str, tuple[str, str]]]:
    document = read_json(path)
    if not isinstance(document, dict) or document.get("schema") != 1:
        raise GateError("product identity allowlist schema must be 1")
    expected = document.get("expected_findings")
    if not isinstance(expected, int) or isinstance(expected, bool) or expected < 0:
        raise GateError("expected_findings must be a non-negative integer")

    raw_allow = document.get("allow")
    raw_opaque = document.get("opaque_files")
    if not isinstance(raw_allow, list) or not isinstance(raw_opaque, list):
        raise GateError("allow and opaque_files must be arrays")

    allowed: Counter[Finding] = Counter()
    reasons: dict[Finding, str] = {}
    for index, entry in enumerate(raw_allow, start=1):
        if not isinstance(entry, dict):
            raise GateError(f"disposition {index} must be an object")
        path_value = valid_relative_file(entry.get("path"))
        kind = entry.get("kind")
        token = entry.get("token")
        line = entry.get("line")
        occurrences = entry.get("occurrences")
        reason = entry.get("reason")
        if kind not in VALID_KINDS:
            raise GateError(f"disposition {index} has invalid kind: {kind}")
        if not isinstance(token, str) or not token:
            raise GateError(f"disposition {index} requires a non-empty token")
        if not isinstance(line, str) or not line:
            raise GateError(f"disposition {index} requires an exact non-empty line")
        if (
            not isinstance(occurrences, int)
            or isinstance(occurrences, bool)
            or occurrences <= 0
        ):
            raise GateError(f"disposition {index} occurrences must be positive")
        if not isinstance(reason, str) or not reason.strip():
            raise GateError(f"disposition {index} requires a non-empty reason")
        finding = Finding(path_value, kind, token, line)
        if finding in allowed:
            raise GateError(
                f"duplicate disposition: {path_value} {kind} {token!r}"
            )
        allowed[finding] = occurrences
        reasons[finding] = reason.strip()

    opaque: dict[str, tuple[str, str]] = {}
    for index, entry in enumerate(raw_opaque, start=1):
        if not isinstance(entry, dict):
            raise GateError(f"opaque file {index} must be an object")
        path_value = valid_relative_file(entry.get("path"))
        digest = entry.get("sha256")
        reason = entry.get("reason")
        if not isinstance(digest, str) or not HEX_DIGEST.fullmatch(digest):
            raise GateError(f"opaque file {path_value} requires a lowercase SHA-256")
        if not isinstance(reason, str) or not reason.strip():
            raise GateError(f"opaque file {path_value} requires a non-empty reason")
        if path_value in opaque:
            raise GateError(f"duplicate opaque file disposition: {path_value}")
        opaque[path_value] = (digest, reason.strip())

    overlap = sorted({finding.path for finding in allowed} & set(opaque))
    if overlap:
        raise GateError(f"opaque files cannot also have line dispositions: {overlap[0]}")
    allowed_total = sum(allowed.values())
    if expected != allowed_total:
        raise GateError(
            f"expected_findings {expected} does not equal allowlist total {allowed_total}"
        )
    return expected, allowed, reasons, opaque


def scanned_files(root: Path) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for relative in SCAN_DIRECTORIES:
        directory = root / relative
        if not directory.is_dir():
            raise GateError(f"identity scan directory is missing: {directory}")
        for path in sorted(directory.rglob("*")):
            if path.is_symlink():
                raise GateError(f"identity scan symlink requires explicit policy: {path}")
            if not path.is_file() or "__pycache__" in path.parts or path.suffix == ".pyc":
                continue
            result[path.relative_to(root).as_posix()] = path
    for relative in SCAN_ROOT_FILES:
        path = root / relative
        if not path.is_file():
            raise GateError(f"identity scan root file is missing: {path}")
        result[relative] = path
    for pattern in ROOT_PATTERNS:
        for path in sorted(root.glob(pattern)):
            if path.is_symlink():
                raise GateError(f"identity scan symlink requires explicit policy: {path}")
            if path.is_file():
                result[path.relative_to(root).as_posix()] = path
    return dict(sorted(result.items()))


def line_findings(path: str, line: str) -> list[Finding]:
    findings: list[Finding] = []
    occupied: list[tuple[int, int]] = []
    for kind, pattern in (
        ("legacy-env", LEGACY_ENVIRONMENT),
        ("upstream-org", UPSTREAM_ORGANIZATION),
    ):
        for match in pattern.finditer(line):
            findings.append(Finding(path, kind, match.group(0), line))
            occupied.append(match.span())
    for match in PRODUCT_TOKEN_PATTERN.finditer(line):
        if any(match.start() < end and match.end() > start for start, end in occupied):
            continue
        findings.append(Finding(path, "pi-token", match.group(0), line))
    return findings


def collect_findings(
    root: Path,
    files: dict[str, Path],
    opaque: dict[str, tuple[str, str]],
) -> Counter[Finding]:
    unknown_opaque = sorted(set(opaque) - set(files))
    if unknown_opaque:
        raise GateError(f"stale opaque file disposition: {unknown_opaque[0]}")
    findings: Counter[Finding] = Counter()
    for relative, path in files.items():
        try:
            payload = path.read_bytes()
        except OSError as error:
            raise GateError(f"cannot read identity scan file {path}: {error}") from error
        if relative in opaque:
            expected_digest, _reason = opaque[relative]
            actual_digest = hashlib.sha256(payload).hexdigest()
            if actual_digest != expected_digest:
                raise GateError(
                    f"opaque file digest mismatch: {relative} expected "
                    f"{expected_digest} got {actual_digest}"
                )
            continue
        try:
            text = payload.decode("utf-8")
        except UnicodeError as error:
            raise GateError(
                f"non-UTF-8 scan input requires an exact opaque disposition: {relative}"
            ) from error
        for line in text.splitlines():
            findings.update(line_findings(relative, line))
    return findings


def render_finding(finding: Finding, count: int) -> str:
    line = finding.line
    if len(line) > 180:
        line = f"{line[:177]}..."
    return (
        f"{finding.path} [{finding.kind}:{finding.token}] "
        f"x{count}: {line}"
    )


def run(root: Path, manifest: Path) -> int:
    root = root.resolve()
    expected, allowed, _reasons, opaque = load_manifest(manifest.resolve())
    files = scanned_files(root)
    findings = collect_findings(root, files, opaque)

    failures: list[str] = []
    for finding in sorted(set(findings) - set(allowed)):
        failures.append(
            f"unapproved identity: {render_finding(finding, findings[finding])}"
        )
    for finding in sorted(set(allowed) - set(findings)):
        failures.append(
            f"stale disposition: {render_finding(finding, allowed[finding])}"
        )
    for finding in sorted(set(findings) & set(allowed)):
        if findings[finding] != allowed[finding]:
            failures.append(
                "identity occurrence count mismatch: "
                f"{render_finding(finding, findings[finding])}; "
                f"allowed {allowed[finding]}"
            )

    actual_total = sum(findings.values())
    if actual_total != expected:
        failures.append(
            f"real finding total {actual_total} does not equal recorded {expected}"
        )
    if failures:
        for failure in failures:
            print(f"product identity gate: {failure}", file=sys.stderr)
        return 1

    print(
        "Product identity gate: "
        f"{actual_total} findings, {len(allowed)} exact dispositions, "
        f"{len(opaque)} digest-locked opaque files; real tree and allowlist agree."
    )
    return 0


def inventory(root: Path) -> int:
    root = root.resolve()
    files = scanned_files(root)
    findings = collect_findings(root, files, {})
    entries = []
    for finding in sorted(findings):
        entries.append(
            {
                "path": finding.path,
                "kind": finding.kind,
                "token": finding.token,
                "line": finding.line,
                "occurrences": findings[finding],
            }
        )
    json.dump(
        {"findings": sum(findings.values()), "entries": entries},
        sys.stdout,
        ensure_ascii=False,
        indent=2,
    )
    sys.stdout.write("\n")
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--inventory", action="store_true")
    arguments = parser.parse_args()
    if not arguments.inventory and arguments.manifest is None:
        parser.error("--manifest is required unless --inventory is used")
    return arguments


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.inventory:
            return inventory(arguments.root)
        return run(arguments.root, arguments.manifest)
    except GateError as error:
        print(f"product identity gate: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
