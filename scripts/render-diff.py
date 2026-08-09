#!/usr/bin/env python3
"""Capture and compare fixed-baseline pi and Cadr terminal byte streams."""

from __future__ import annotations

import argparse
import errno
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import select
import shutil
import shlex
import signal
import struct
import subprocess
import sys
import tarfile
import tempfile
import termios
import time
import urllib.request
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "test/fixtures/render-diff/scenarios.json"
DEFAULT_INTERFACE_REGISTRY = ROOT / "test/fixtures/render-diff/reachable-interfaces.json"
DEFAULT_BASELINE_INVENTORY = ROOT / "test/fixtures/render-diff/baseline-interface-inventory.json"
DEFAULT_VISIBLE_STRING_INVENTORY = ROOT / "test/fixtures/render-diff/baseline-visible-strings.json"
DEFAULT_VISIBLE_STRING_EXEMPTIONS = ROOT / "test/fixtures/render-diff/visible-string-exemptions.json"
DEFAULT_DISPOSITIONS = ROOT / "test/fixtures/render-diff/dispositions.json"
PI_DRIVER = ROOT / "test/fixtures/render-diff/pi-driver.ts"
CADR_DRIVER = ROOT / "test/fixtures/render-diff/cadr-driver.lisp"
VISIBLE_STRING_EXTRACTOR = ROOT / "test/fixtures/render-diff/baseline-visible-strings.ts"
VISIBLE_STRING_CONSTRUCTION_DRIVER = ROOT / "test/fixtures/render-diff/baseline-visible-construction.ts"
VISIBLE_STRING_ENVIRONMENT_CONSTRUCTION_DRIVER = (
    ROOT / "test/fixtures/render-diff/baseline-visible-environment-construction.ts"
)
PI_AI_MODEL_DATA_PACKAGE = "@earendil-works/pi-ai@0.83.0"
PI_AI_MODEL_DATA_SHA256 = "f983c28a21209305ed9c274977e29130fa4d8848df6cdf37e9094d95cc7bc6d4"
KEYS = {
    "enter": b"\r",
    "escape": b"\x1b",
    "ctrl+c": b"\x03",
    "ctrl+d": b"\x04",
    "ctrl+a": b"\x01",
    "ctrl+l": b"\x0c",
    "ctrl+r": b"\x12",
    "ctrl+o": b"\x0f",
    "ctrl+p": b"\x10",
    "ctrl+t": b"\x14",
    "ctrl+u": b"\x15",
    "ctrl+x": b"\x18",
    "ctrl+z": b"\x1a",
    "shift+tab": b"\x1b[Z",
    "alt+enter": b"\x1b\r",
    "alt+up": b"\x1bp",
    "up": b"\x1b[A",
    "down": b"\x1b[B",
    "left": b"\x1b[D",
    "right": b"\x1b[C",
    "tab": b"\t",
    "space": b" ",
    "shift+l": b"L",
}

REQUIRED_COVERAGE = {
    "startup-first",
    "startup-existing",
    "startup-untrusted",
    "plain-text",
    "markdown",
    "code-block",
    "cjk-emoji",
    "bash-multiline",
    "read-range",
    "edit",
    "write",
    "grep",
    "find",
    "ls",
    "tool-failure",
    "bash-nonzero",
    "bash-timeout",
    "overlay-model",
    "overlay-session",
    "overlay-fork",
    "overlay-tree",
    "overlay-settings",
    "overlay-trust",
    "overlay-auth-method",
    "overlay-login-provider",
    "overlay-login-dialog",
    "stream-interrupt",
    "busy-queue",
    "provider-error",
    "fatal-crash",
    "tool-invalid-arguments",
    "compaction-manual",
    "compaction-threshold",
    "compaction-overflow",
    "settings-state-sweep",
    "slash-export",
    "slash-login",
    "slash-reload",
    "post-exit-resume",
}

REQUIRED_SIGNIFICANT_STATE_DOMAINS = {
    "bash-output": [
        "bash-output-line-limit",
        "bash-output-byte-limit",
        "bash-output-overlong-line",
        "bash-output-empty",
    ],
    "bash-terminal": ["bash-nonzero-exit", "bash-timeout"],
    "tool-batch": ["parallel-tool-calls"],
    "tool-validation": ["tool-invalid-arguments"],
    "agent-compaction": [
        "compaction-manual",
        "compaction-threshold",
        "compaction-overflow",
    ],
}


class HarnessFailure(RuntimeError):
    pass


def scenario_checkpoint_ids(scenario: dict[str, Any]) -> list[str]:
    ids: list[str] = []
    for action in scenario["actions"]:
        if "checkpoint" in action:
            ids.append(action["checkpoint"])
        specification = action.get("sendRepeated")
        if isinstance(specification, dict) and specification.get("checkpointPrefix"):
            ids.extend(
                f"{specification['checkpointPrefix']}-{index:02d}"
                for index in range(1, specification["count"] + 1)
            )
    return ids


def git_blob(repo: Path, commit: str, path: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), "show", f"{commit}:{path}"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        raise HarnessFailure(
            f"cannot read fixed-baseline source {commit}:{path}: {result.stderr.strip()}"
        )
    return result.stdout


def git_repository_has_commit(repo: Path, commit: str) -> bool:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo), "cat-file", "-e", f"{commit}^{{commit}}"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return False
    return result.returncode == 0


def extract_baseline_slash_commands(repo: Path, commit: str) -> list[str]:
    source = git_blob(
        repo, commit, "packages/coding-agent/src/core/slash-commands.ts"
    )
    match = re.search(
        r"BUILTIN_SLASH_COMMANDS[^=]*=\s*\[(.*?)\n\];", source, re.DOTALL
    )
    if match is None:
        raise HarnessFailure("cannot locate fixed-baseline slash-command registry")
    return re.findall(r'\{\s*name:\s*"([^"]+)"', match.group(1))


def baseline_interactive_sources(repo: Path, commit: str) -> dict[str, str]:
    prefix = "packages/coding-agent/src/modes/interactive"
    result = subprocess.run(
        ["git", "-C", str(repo), "ls-tree", "-r", "--name-only", commit, "--", prefix],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        raise HarnessFailure(
            f"cannot enumerate fixed-baseline interactive sources: {result.stderr.strip()}"
        )
    paths = [path for path in result.stdout.splitlines() if path.endswith(".ts")]
    if not paths:
        raise HarnessFailure("fixed-baseline interactive source tree is empty")
    return {path: git_blob(repo, commit, path) for path in paths}


def baseline_interface_pattern() -> re.Pattern[str]:
    return re.compile(
        r"new\s+([A-Z][A-Za-z0-9]*(?:Selector|Dialog|Input|Editor)Component|"
        r"SelectSubmenu|ThemeSubmenu|WarningSettingsSubmenu)\b"
    )


def extract_baseline_interface_constructors(repo: Path, commit: str) -> list[str]:
    sources = baseline_interactive_sources(repo, commit)
    pattern = baseline_interface_pattern()
    return sorted({match for source in sources.values() for match in pattern.findall(source)})


def extract_baseline_interface_sites(repo: Path, commit: str) -> list[str]:
    sources = baseline_interactive_sources(repo, commit)
    pattern = baseline_interface_pattern()
    sites: list[str] = []
    for path, source in sources.items():
        for match in pattern.finditer(source):
            line = source.count("\n", 0, match.start()) + 1
            sites.append(f"{path}:{line}:{match.group(1)}")
    return sorted(sites)


def load_baseline_interface_inventory(
    path: Path, repo: Path, commit: str
) -> dict[str, Any]:
    if not path.is_file():
        raise HarnessFailure(f"fixed-baseline interface inventory is missing: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 1:
        raise HarnessFailure("fixed-baseline interface inventory schemaVersion must be 1")
    if data.get("baselineCommit") != commit:
        raise HarnessFailure("fixed-baseline interface inventory commit does not match manifest")
    for field in ("slashCommands", "interfaceIds", "constructors", "constructorSites"):
        values = data.get(field)
        if (
            not isinstance(values, list)
            or not values
            or not all(isinstance(value, str) and value for value in values)
            or len(values) != len(set(values))
        ):
            raise HarnessFailure(f"invalid fixed-baseline interface inventory field: {field}")

    verified_from_git = git_repository_has_commit(repo, commit)
    if verified_from_git:
        extracted = {
            "slashCommands": extract_baseline_slash_commands(repo, commit),
            "constructors": extract_baseline_interface_constructors(repo, commit),
            "constructorSites": extract_baseline_interface_sites(repo, commit),
        }
        for field, values in extracted.items():
            if data[field] != values:
                raise HarnessFailure(
                    f"fixed-baseline interface inventory drift: {field}"
                )
    result = dict(data)
    result["verifiedFromGit"] = verified_from_git
    return result


def extract_cadr_overlay_kinds(repo: Path) -> list[str]:
    source = (repo / "src/cadr-cli/interactive/controller.lisp").read_text(
        encoding="utf-8"
    )
    kinds = set(re.findall(r"overlay-kind\s+:([a-z0-9-]+)", source))
    kinds.update(re.findall(r"open-selector\s+:([a-z0-9-]+)", source))
    return sorted(kinds)


def manifest_checkpoints(manifest: dict[str, Any]) -> set[tuple[str, str]]:
    return {
        (scenario["id"], checkpoint_id)
        for scenario in manifest["scenarios"]
        for checkpoint_id in scenario_checkpoint_ids(scenario)
    } | {(scenario["id"], "process-exit") for scenario in manifest["scenarios"]}


def validate_interface_registry(
    data: dict[str, Any], manifest: dict[str, Any], repo: Path
) -> dict[str, Any]:
    if data.get("schemaVersion") != 1:
        raise HarnessFailure("reachable-interface registry schemaVersion must be 1")
    commit = manifest["baselineCommit"]
    if data.get("baselineCommit") != commit:
        raise HarnessFailure(
            "reachable-interface registry baseline commit does not match manifest"
        )
    baseline_inventory = load_baseline_interface_inventory(
        DEFAULT_BASELINE_INVENTORY, repo, commit
    )
    captures = manifest_checkpoints(manifest)

    commands = data.get("slashCommands")
    if not isinstance(commands, list):
        raise HarnessFailure("reachable-interface registry must list slashCommands")
    registered_commands = [entry.get("name") for entry in commands]
    baseline_commands = baseline_inventory["slashCommands"]
    missing_commands = [name for name in baseline_commands if name not in registered_commands]
    stale_commands = [name for name in registered_commands if name not in baseline_commands]
    if missing_commands:
        raise HarnessFailure(
            "unregistered baseline slash command: " + ", ".join(missing_commands)
        )
    if stale_commands:
        raise HarnessFailure("stale slash command registration: " + ", ".join(stale_commands))
    if registered_commands != baseline_commands:
        raise HarnessFailure("slash command registry order differs from fixed baseline")

    interfaces = data.get("interfaces")
    if not isinstance(interfaces, list) or not interfaces:
        raise HarnessFailure("reachable-interface registry must list interfaces")
    ids: set[str] = set()
    uncovered: list[str] = []
    for entry in [*commands, *interfaces]:
        capture = entry.get("capture")
        if not isinstance(capture, dict):
            uncovered.append(str(entry.get("id") or entry.get("name")))
            continue
        target = (capture.get("scenario"), capture.get("checkpoint"))
        if target not in captures:
            uncovered.append(str(entry.get("id") or entry.get("name")))
    for entry in interfaces:
        interface_id = entry.get("id")
        if not isinstance(interface_id, str) or not interface_id:
            raise HarnessFailure("reachable interface must have a non-empty id")
        if interface_id in ids:
            raise HarnessFailure(f"duplicate reachable interface id: {interface_id}")
        ids.add(interface_id)
        evidence = entry.get("baselineEvidence")
        if not isinstance(evidence, dict):
            raise HarnessFailure(f"missing baseline evidence for interface {interface_id}")
        path = evidence.get("path")
        token = evidence.get("token")
        if not isinstance(path, str) or not path or not isinstance(token, str) or not token:
            raise HarnessFailure(
                f"invalid baseline evidence for reachable interface {interface_id}"
            )
        if baseline_inventory["verifiedFromGit"] and token not in git_blob(repo, commit, path):
            raise HarnessFailure(
                f"stale baseline evidence for reachable interface {interface_id}"
            )
    if uncovered:
        raise HarnessFailure(
            "uncaptured reachable interface: " + ", ".join(sorted(uncovered))
        )
    if sorted(ids) != sorted(baseline_inventory["interfaceIds"]):
        missing = sorted(set(baseline_inventory["interfaceIds"]) - ids)
        stale = sorted(ids - set(baseline_inventory["interfaceIds"]))
        raise HarnessFailure(
            "reachable interface inventory drift: "
            f"unregistered={missing} stale={stale}"
        )
    constructor_map = data.get("baselineConstructors")
    if not isinstance(constructor_map, dict):
        raise HarnessFailure("reachable-interface registry must map baselineConstructors")
    discovered_constructors = baseline_inventory["constructors"]
    if sorted(constructor_map) != discovered_constructors:
        missing = sorted(set(discovered_constructors) - set(constructor_map))
        stale = sorted(set(constructor_map) - set(discovered_constructors))
        raise HarnessFailure(
            "baseline interface constructor registry drift: "
            f"unregistered={missing} stale={stale}"
        )
    for constructor, interface_ids in constructor_map.items():
        if not isinstance(interface_ids, list) or not interface_ids:
            raise HarnessFailure(
                f"baseline constructor {constructor} has no reachable interface mapping"
            )
        unknown = sorted(set(interface_ids) - ids)
        if unknown:
            raise HarnessFailure(
                f"baseline constructor {constructor} maps unknown interfaces: {unknown}"
            )

    site_map = data.get("baselineConstructorSites")
    if not isinstance(site_map, dict):
        raise HarnessFailure("reachable-interface registry must map baselineConstructorSites")
    discovered_sites = baseline_inventory["constructorSites"]
    if sorted(site_map) != discovered_sites:
        missing = sorted(set(discovered_sites) - set(site_map))
        stale = sorted(set(site_map) - set(discovered_sites))
        raise HarnessFailure(
            "baseline interface construction-site registry drift: "
            f"unregistered={missing} stale={stale}"
        )
    for site, interface_ids in site_map.items():
        if not isinstance(interface_ids, list) or not interface_ids:
            raise HarnessFailure(
                f"baseline construction site {site} has no reachable interface mapping"
            )
        unknown = sorted(set(interface_ids) - ids)
        if unknown:
            raise HarnessFailure(
                f"baseline construction site {site} maps unknown interfaces: {unknown}"
            )

    overlay_map = data.get("cadrOverlayKinds")
    if not isinstance(overlay_map, dict):
        raise HarnessFailure("reachable-interface registry must map cadrOverlayKinds")
    discovered_overlays = extract_cadr_overlay_kinds(repo)
    if sorted(overlay_map) != discovered_overlays:
        missing = sorted(set(discovered_overlays) - set(overlay_map))
        stale = sorted(set(overlay_map) - set(discovered_overlays))
        raise HarnessFailure(
            "Cadr overlay-kind registry drift: "
            f"unregistered={missing} stale={stale}"
        )
    for kind, interface_ids in overlay_map.items():
        if not isinstance(interface_ids, list) or not interface_ids:
            raise HarnessFailure(f"Cadr overlay kind {kind} has no interface mapping")
        unknown = sorted(set(interface_ids) - ids)
        if unknown:
            raise HarnessFailure(
                f"Cadr overlay kind {kind} maps unknown interfaces: {unknown}"
            )

    state_domains = data.get("significantStateDomains")
    if state_domains != REQUIRED_SIGNIFICANT_STATE_DOMAINS:
        raise HarnessFailure(
            "significant-state domain registry drift"
        )
    required_state_ids: list[str] = []
    for domain, states in state_domains.items():
        if (
            not isinstance(domain, str)
            or not domain
            or not isinstance(states, list)
            or not states
            or not all(isinstance(state, str) and state for state in states)
            or len(states) != len(set(states))
        ):
            raise HarnessFailure(f"invalid significant-state domain: {domain}")
        required_state_ids.extend(states)
    if len(required_state_ids) != len(set(required_state_ids)):
        raise HarnessFailure("significant-state ids overlap across domains")

    significant_states = data.get("significantStates")
    if not isinstance(significant_states, list) or not significant_states:
        raise HarnessFailure("reachable-interface registry must list significantStates")
    registered_state_ids = [entry.get("id") for entry in significant_states]
    if registered_state_ids != required_state_ids:
        missing = sorted(set(required_state_ids) - set(registered_state_ids))
        stale = sorted(set(registered_state_ids) - set(required_state_ids))
        raise HarnessFailure(
            "significant-state registry drift: "
            f"unregistered={missing} stale={stale}"
        )
    uncovered_states: list[str] = []
    accepted_exclusions: list[dict[str, str]] = []
    for entry in significant_states:
        state_id = entry.get("id")
        trigger = entry.get("trigger")
        if not isinstance(trigger, str) or not trigger.strip():
            raise HarnessFailure(f"missing trigger for significant state {state_id}")
        evidence = entry.get("baselineEvidence")
        if not isinstance(evidence, dict):
            raise HarnessFailure(
                f"missing baseline evidence for significant state {state_id}"
            )
        path = evidence.get("path")
        token = evidence.get("token")
        if (
            not isinstance(path, str)
            or not path
            or not isinstance(token, str)
            or not token
        ):
            raise HarnessFailure(
                f"invalid baseline evidence for significant state {state_id}"
            )
        if baseline_inventory["verifiedFromGit"] and token not in git_blob(
            repo, commit, path
        ):
            raise HarnessFailure(
                f"stale baseline evidence for significant state {state_id}"
            )
        capture = entry.get("capture")
        reason = entry.get("notCapturedReason")
        if isinstance(capture, dict) and isinstance(reason, str) and reason.strip():
            raise HarnessFailure(
                f"significant state {state_id} cannot be both captured and excluded"
            )
        if isinstance(capture, dict):
            target = (capture.get("scenario"), capture.get("checkpoint"))
            if target not in captures:
                uncovered_states.append(str(state_id))
        elif isinstance(reason, str) and reason.strip():
            accepted_exclusions.append({"id": str(state_id), "reason": reason.strip()})
        else:
            uncovered_states.append(str(state_id))
    if uncovered_states:
        raise HarnessFailure(
            "uncaptured significant state: "
            + ", ".join(sorted(uncovered_states))
        )

    result = dict(data)
    result["uncoveredInterfaces"] = []
    result["uncoveredSignificantStates"] = []
    result["excludedSignificantStates"] = accepted_exclusions
    return result


def load_interface_registry(
    path: Path, manifest: dict[str, Any], repo: Path
) -> dict[str, Any]:
    if not path.is_file():
        raise HarnessFailure(f"reachable-interface registry is missing: {path}")
    return validate_interface_registry(
        json.loads(path.read_text(encoding="utf-8")), manifest, repo
    )


def load_manifest(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 1:
        raise HarnessFailure("render-diff manifest schemaVersion must be 1")
    scenario_ids: set[str] = set()
    coverage: set[str] = set()
    for scenario in data.get("scenarios", []):
        scenario_id = scenario.get("id")
        if not isinstance(scenario_id, str) or not scenario_id:
            raise HarnessFailure("every render-diff scenario must have a non-empty id")
        if scenario_id in scenario_ids:
            raise HarnessFailure(f"duplicate render-diff scenario id: {scenario_id}")
        scenario_ids.add(scenario_id)
        scenario_coverage = scenario.get("coverage")
        if not isinstance(scenario_coverage, list) or not scenario_coverage:
            raise HarnessFailure(f"scenario {scenario_id} must declare coverage")
        if not all(isinstance(item, str) and item for item in scenario_coverage):
            raise HarnessFailure(f"scenario {scenario_id} has invalid coverage labels")
        coverage.update(scenario_coverage)
    missing = sorted(REQUIRED_COVERAGE - coverage)
    if missing:
        raise HarnessFailure(f"render-diff manifest misses required coverage: {', '.join(missing)}")
    load_interface_registry(DEFAULT_INTERFACE_REGISTRY, data, ROOT)
    return data


def load_dispositions(path: Path, baseline_commit: str) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 1:
        raise HarnessFailure("render-diff dispositions schemaVersion must be 1")
    if data.get("baselineCommit") != baseline_commit:
        raise HarnessFailure("render-diff dispositions baseline commit does not match manifest")
    classes = data.get("classes")
    if not isinstance(classes, dict) or not classes:
        raise HarnessFailure("render-diff dispositions must define difference classes")
    for class_id, definition in classes.items():
        if not isinstance(class_id, str) or not isinstance(definition, dict):
            raise HarnessFailure("invalid render-diff difference class")
        if definition.get("kind") not in {"cadr-defect", "intentional-difference"}:
            raise HarnessFailure(f"invalid disposition kind for {class_id}")
        if not isinstance(definition.get("summary"), str) or not definition["summary"]:
            raise HarnessFailure(f"missing disposition summary for {class_id}")
        if not isinstance(definition.get("textCovering"), bool):
            raise HarnessFailure(
                f"disposition class {class_id} must declare textCovering"
            )
    return data


def text_covering_disposition_classes(data: dict[str, Any]) -> frozenset[str]:
    return frozenset(
        class_id
        for class_id, definition in data["classes"].items()
        if definition.get("textCovering")
    )


def expand_dispositions(
    data: dict[str, Any], manifest: dict[str, Any]
) -> dict[str, dict[str, Any]]:
    classes = data["classes"]
    dimensions = {dimension["id"] for dimension in manifest["dimensions"]}
    scenarios = {
        scenario["id"]: set(scenario_checkpoint_ids(scenario)) | {"process-exit"}
        for scenario in manifest["scenarios"]
    }
    expanded: dict[str, dict[str, Any]] = {}
    seen_notes: dict[str, str] = {}
    for entry in data.get("entries", []):
        scenario = entry.get("scenario")
        checkpoint = entry.get("checkpoint")
        entry_dimensions = entry.get("dimensions")
        entry_classes = entry.get("classes")
        if scenario not in scenarios or checkpoint not in scenarios[scenario]:
            raise HarnessFailure(
                f"stale render-diff disposition target: {scenario}/{checkpoint}"
            )
        if (
            not isinstance(entry_dimensions, list)
            or not entry_dimensions
            or len(entry_dimensions) != len(set(entry_dimensions))
            or any(dimension not in dimensions for dimension in entry_dimensions)
        ):
            raise HarnessFailure(
                f"invalid render-diff disposition dimensions: {scenario}/{checkpoint}"
            )
        if (
            not isinstance(entry_classes, list)
            or not entry_classes
            or len(entry_classes) != len(set(entry_classes))
            or any(class_id not in classes for class_id in entry_classes)
        ):
            raise HarnessFailure(
                f"invalid render-diff disposition classes: {scenario}/{checkpoint}"
            )
        note_text = entry.get("note", "")
        if isinstance(note_text, str) and note_text.strip():
            note_key = note_text.strip()
            prior = seen_notes.get(note_key)
            if prior is not None:
                raise HarnessFailure(
                    "duplicate disposition note text between "
                    f"{prior} and {scenario}/{checkpoint}: notes must record "
                    "per-entry judgement"
                )
            seen_notes[note_key] = f"{scenario}/{checkpoint}"
        screen_pairs = entry.get("screenSha256")
        screen_classes = set(entry_classes) - {"I01"}
        if (
            not isinstance(screen_pairs, dict)
            or set(screen_pairs) != set(entry_dimensions)
            or any(
                not isinstance(pair, dict)
                or set(pair) != {"pi", "cadr"}
                or any(
                    not isinstance(value, str)
                    or not re.fullmatch(r"[0-9a-f]{64}", value)
                    for value in pair.values()
                )
                for pair in screen_pairs.values()
            )
        ):
            raise HarnessFailure(
                "screen disposition must bind every declared dimension to "
                f"an exact Pi/Cadr SHA-256 pair: {scenario}/{checkpoint}"
            )
        for dimension in entry_dimensions:
            key = f"{scenario}/{dimension}/{checkpoint}"
            if key in expanded:
                raise HarnessFailure(f"duplicate render-diff disposition: {key}")
            expanded[key] = {
                "classes": entry_classes,
                "kinds": sorted({classes[class_id]["kind"] for class_id in entry_classes}),
                "note": entry.get("note", ""),
                "screenSha256": (
                    screen_pairs.get(dimension)
                    if isinstance(screen_pairs, dict)
                    else None
                ),
            }
    return expanded


def find_scenario(manifest: dict[str, Any], scenario_id: str) -> dict[str, Any]:
    for scenario in manifest["scenarios"]:
        if scenario["id"] == scenario_id:
            return scenario
    raise HarnessFailure(f"unknown scenario: {scenario_id}")


def find_dimension(manifest: dict[str, Any], dimension_id: str) -> dict[str, int]:
    for dimension in manifest["dimensions"]:
        if dimension["id"] == dimension_id:
            return dimension
    raise HarnessFailure(f"unknown dimension: {dimension_id}")


def extract_baseline(pi_repo: Path, commit: str, destination: Path) -> None:
    archive = subprocess.run(
        ["git", "-C", str(pi_repo), "archive", "--format=tar", commit],
        check=True,
        stdout=subprocess.PIPE,
    ).stdout
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as stream:
        stream.extractall(destination, filter="data")
    target = destination / "packages/coding-agent/test/goal15-render-driver.ts"
    shutil.copy2(PI_DRIVER, target)
    visible_target = destination / "packages/coding-agent/test/goal17-visible-strings.ts"
    shutil.copy2(VISIBLE_STRING_EXTRACTOR, visible_target)
    construction_target = destination / "packages/coding-agent/test/goal17-visible-construction.ts"
    shutil.copy2(VISIBLE_STRING_CONSTRUCTION_DRIVER, construction_target)


def hydrate_baseline_model_data(baseline: Path) -> None:
    destination = baseline / "packages/ai/src/providers/data"
    if (destination / ".manifest.json").is_file():
        return
    with tempfile.TemporaryDirectory(prefix="cadr-render-diff-model-data-") as temporary:
        packed = subprocess.run(
            [
                "npm",
                "pack",
                PI_AI_MODEL_DATA_PACKAGE,
                "--ignore-scripts",
                "--json",
                "--pack-destination",
                temporary,
            ],
            check=True,
            stdout=subprocess.PIPE,
            text=True,
        )
        records = json.loads(packed.stdout)
        if len(records) != 1 or not records[0].get("filename"):
            raise HarnessFailure("npm pack did not return one pi-ai artifact")
        archive = Path(temporary) / records[0]["filename"]
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        if digest != PI_AI_MODEL_DATA_SHA256:
            raise HarnessFailure(
                f"pi-ai model-data artifact SHA-256 mismatch: {digest}"
            )
        destination.mkdir(parents=True)
        prefix = "package/dist/providers/data/"
        with tarfile.open(archive, mode="r:gz") as stream:
            members = [member for member in stream.getmembers() if member.name.startswith(prefix)]
            if not members:
                raise HarnessFailure("pi-ai artifact contains no provider model data")
            for member in members:
                relative = member.name.removeprefix(prefix)
                if not relative or "/" in relative or not member.isfile():
                    continue
                source = stream.extractfile(member)
                if source is None:
                    raise HarnessFailure(f"cannot extract model data member: {member.name}")
                (destination / relative).write_bytes(source.read())


def verify_baseline_cache_contents(pi_repo: Path, commit: str, cache: Path) -> None:
    """Require the reused baseline cache to match the immutable git blobs.

    The marker alone only records a commit string; it cannot prove the
    /tmp cache still contains that commit (the directory is not a git
    checkout and the harness writes into it).  The expected content comes
    from the repository's own object store — never from the cache — so a
    modified or partially damaged cache fails closed.  Only git-tracked
    files under packages/ are checked; node_modules is `npm ci`-derived
    from the verified lockfile, and the harness-written driver copies and
    hydrated model data are untracked by the baseline commit.
    """
    listing = subprocess.run(
        ["git", "-C", str(pi_repo), "ls-tree", "-r", commit, "--", "packages"],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    ).stdout
    expected: list[tuple[str, str, str]] = []
    for line in listing.splitlines():
        meta, _, path = line.partition("\t")
        parts = meta.split()
        if len(parts) == 3 and parts[1] == "blob" and path:
            expected.append((parts[0], parts[2], path))
    if not expected:
        raise HarnessFailure(
            f"baseline commit {commit} lists no tracked files under packages/"
        )
    for mode, blob, path in expected:
        target = cache / path
        if mode == "120000":
            if not target.is_symlink():
                raise HarnessFailure(
                    f"baseline cache lost a tracked symlink: {path}"
                )
            actual = os.readlink(target).encode()
        else:
            if not target.is_file() or target.is_symlink():
                raise HarnessFailure(
                    f"baseline cache is missing a tracked file: {path}"
                )
            actual = target.read_bytes()
        digest = hashlib.sha1(b"blob %d\0" % len(actual) + actual).hexdigest()
        if digest != blob:
            raise HarnessFailure(
                f"baseline cache content no longer matches {commit}: {path}"
            )


def ensure_baseline(pi_repo: Path, commit: str, cache: Path) -> Path:
    marker = cache / ".goal15-render-baseline"
    if marker.is_file() and marker.read_text(encoding="ascii").strip() == commit:
        verify_baseline_cache_contents(pi_repo, commit, cache)
        hydrate_baseline_model_data(cache)
        shutil.copy2(PI_DRIVER, cache / "packages/coding-agent/test/goal15-render-driver.ts")
        shutil.copy2(
            VISIBLE_STRING_EXTRACTOR,
            cache / "packages/coding-agent/test/goal17-visible-strings.ts",
        )
        shutil.copy2(
            VISIBLE_STRING_CONSTRUCTION_DRIVER,
            cache / "packages/coding-agent/test/goal17-visible-construction.ts",
        )
        return cache
    if cache.exists():
        raise HarnessFailure(
            f"baseline cache exists without the expected immutable marker: {cache}"
        )
    cache.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f".{cache.name}-", dir=cache.parent))
    try:
        extract_baseline(pi_repo, commit, temporary)
        subprocess.run(
            ["npm", "ci", "--ignore-scripts"],
            cwd=temporary,
            check=True,
        )
        hydrate_baseline_model_data(temporary)
        (temporary / marker.name).write_text(commit + "\n", encoding="ascii")
        temporary.rename(cache)
    except BaseException:
        shutil.rmtree(temporary)
        raise
    return cache


def prepare_instrumented_baseline(
    baseline: Path, commit: str, destination: Path
) -> Path:
    if destination.exists():
        raise HarnessFailure(
            f"instrumented baseline destination already exists: {destination}"
        )
    destination.mkdir(parents=True)
    subprocess.run(
        ["cp", "-a", "-l", f"{baseline}/.", str(destination)],
        check=True,
    )
    result = subprocess.run(
        [
            str(baseline / "node_modules/.bin/tsx"),
            "packages/coding-agent/test/goal17-visible-strings.ts",
            str(baseline),
            commit,
            "--instrument",
            str(destination),
        ],
        cwd=baseline,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    inventory = json.loads(result.stdout)
    validate_visible_string_inventory(inventory, commit)
    (destination / ".goal17-visible-baseline").write_text(
        commit + "\n", encoding="ascii"
    )
    shutil.copy2(
        VISIBLE_STRING_CONSTRUCTION_DRIVER,
        destination / "packages/coding-agent/test/goal17-visible-construction.ts",
    )
    shutil.copy2(
        VISIBLE_STRING_ENVIRONMENT_CONSTRUCTION_DRIVER,
        destination
        / "packages/coding-agent/test/goal17-visible-environment-construction.ts",
    )
    return destination


def run_visible_string_construction_suite(
    baseline: Path, output: Path, timeout: float
) -> Path:
    marker_path = output / "baseline-construction.pi.visible.raw"
    marker_path.unlink(missing_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="cadr-render-visible-construction-home-"
    ) as temporary:
        root = Path(temporary)
        environment = fixed_environment(root, 100, 32, root / "ready")
        environment["RENDER_DIFF_VISIBLE_CONSTRUCTS"] = "1"
        environment["RENDER_DIFF_VISIBLE_CONSTRUCTS_PATH"] = str(marker_path)
        environment["PI_TIMING"] = "1"
        result = subprocess.run(
            [
                str(baseline / "node_modules/.bin/tsx"),
                "packages/coding-agent/test/goal17-visible-construction.ts",
            ],
            cwd=baseline,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
        if result.returncode == 0:
            forced_environment = environment.copy()
            forced_environment["RENDER_DIFF_FORCE_BUN_BINARY"] = "1"
            forced_environment["RENDER_DIFF_FORCE_GH_PROBE_THROW"] = "1"
            result = subprocess.run(
                [
                    str(baseline / "node_modules/.bin/tsx"),
                    "packages/coding-agent/test/goal17-visible-environment-construction.ts",
                ],
                cwd=baseline,
                env=forced_environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout,
            )
        if result.returncode == 0:
            session_file = root / "export-session.jsonl"
            session_file.write_text(
                json.dumps(
                    {
                        "type": "session",
                        "version": 3,
                        "id": "goal17-export",
                        "timestamp": "2026-01-01T00:00:00.000Z",
                        "cwd": str(root),
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    str(baseline / "node_modules/.bin/tsx"),
                    "packages/coding-agent/src/cli.ts",
                    "--export",
                    str(session_file),
                    str(root / "export.html"),
                ],
                cwd=baseline,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout,
            )
        if result.returncode == 0:
            no_session_environment = environment.copy()
            no_session_environment["RENDER_DIFF_FORCE_NO_SESSION"] = "1"
            result = subprocess.run(
                [
                    str(baseline / "node_modules/.bin/tsx"),
                    "packages/coding-agent/src/cli.ts",
                    "--resume",
                    "--offline",
                ],
                cwd=baseline,
                env=no_session_environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout,
            )
        if result.returncode == 0:
            session_directory = root / "sessions"
            session_directory.mkdir()
            foreign_session = session_directory / "foreign.jsonl"
            foreign_session.write_text(
                json.dumps(
                    {
                        "type": "session",
                        "version": 3,
                        "id": "goal17-foreign",
                        "timestamp": "2026-01-01T00:00:00.000Z",
                        "cwd": str(root / "foreign-project"),
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            abort_environment = environment.copy()
            abort_environment["PI_CODING_AGENT_SESSION_DIR"] = str(
                session_directory
            )
            result = subprocess.run(
                [
                    str(baseline / "node_modules/.bin/tsx"),
                    "packages/coding-agent/src/cli.ts",
                    "--session",
                    "goal17-foreign",
                    "--offline",
                ],
                cwd=baseline,
                env=abort_environment,
                input=b"n\n",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout,
            )
    if result.returncode != 0:
        raise HarnessFailure(
            "baseline visible-string construction suite failed: "
            + result.stderr.decode("utf-8", errors="backslashreplace")[-4000:]
        )
    if not marker_path.is_file() or not marker_path.read_bytes():
        raise HarnessFailure(
            "baseline visible-string construction suite emitted no sink markers"
        )
    visible_branch_effects(marker_path.read_bytes(), str(marker_path))
    return marker_path


def generate_visible_string_inventory(baseline: Path, commit: str) -> dict[str, Any]:
    result = subprocess.run(
        [
            str(baseline / "node_modules/.bin/tsx"),
            "packages/coding-agent/test/goal17-visible-strings.ts",
            str(baseline),
            commit,
        ],
        cwd=baseline,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return json.loads(result.stdout)


def validate_visible_string_inventory(data: dict[str, Any], commit: str) -> None:
    if data.get("schemaVersion") != 3:
        raise HarnessFailure("visible-string inventory schemaVersion must be 3")
    if data.get("baselineCommit") != commit:
        raise HarnessFailure("visible-string inventory commit does not match manifest")
    unresolved_dataflow = data.get("unresolvedDataflow")
    if not isinstance(unresolved_dataflow, list):
        raise HarnessFailure("visible-string inventory unresolvedDataflow must be a list")
    if unresolved_dataflow:
        raise HarnessFailure(
            "visible-string inventory contains unresolved dataflow: "
            + ", ".join(
                f"{item.get('path')}:{item.get('line')}:{item.get('expression')}"
                for item in unresolved_dataflow
                if isinstance(item, dict)
            )
        )
    entries = data.get("entries")
    if not isinstance(entries, list) or not entries:
        raise HarnessFailure("visible-string inventory must contain entries")
    ids: set[str] = set()
    sites: set[tuple[Any, ...]] = set()
    obligations: set[tuple[str, str]] = set()
    for entry in entries:
        entry_id = entry.get("id")
        if not isinstance(entry_id, str) or not entry_id:
            raise HarnessFailure("visible-string inventory entry has no id")
        if entry_id in ids:
            raise HarnessFailure(f"duplicate visible-string inventory entry: {entry_id}")
        site = entry.get("site")
        sink = entry.get("sink")
        if (
            not isinstance(site, dict)
            or not isinstance(site.get("path"), str)
            or not isinstance(site.get("line"), int)
            or not isinstance(site.get("column"), int)
            or not isinstance(site.get("start"), int)
            or not isinstance(site.get("end"), int)
            or not isinstance(site.get("kind"), str)
            or not re.fullmatch(r"[0-9a-f]{64}", str(site.get("nodeSha256", "")))
        ):
            raise HarnessFailure(f"invalid visible-string site for {entry_id}")
        if (
            not isinstance(sink, dict)
            or sink.get("kind") != site.get("kind")
            or sink.get("channel")
            not in {"printable-visible", "terminal-protocol"}
        ):
            raise HarnessFailure(f"invalid visible-string sink contract for {entry_id}")
        site_key = (site["path"], site["start"], site["end"], site["kind"])
        if site_key in sites:
            raise HarnessFailure(f"duplicate visible-string site: {site_key}")
        sites.add(site_key)
        branches = entry.get("branches")
        if not isinstance(branches, list) or not branches:
            raise HarnessFailure(f"visible-string entry {entry_id} has no branches")
        branch_ids: set[str] = set()
        branch_signatures: set[tuple[tuple[str, ...], tuple[tuple[str, tuple[str, ...]], ...]]] = set()
        for branch in branches:
            branch_id = branch.get("id") if isinstance(branch, dict) else None
            segments = branch.get("segments") if isinstance(branch, dict) else None
            conditions = branch.get("conditions") if isinstance(branch, dict) else None
            runtime_choices = (
                branch.get("runtimeChoices") if isinstance(branch, dict) else None
            )
            if (
                not isinstance(branch_id, str)
                or not re.fullmatch(r"B-[0-9a-f]{12}", branch_id)
                or branch_id in branch_ids
                or not isinstance(conditions, list)
                or not all(isinstance(condition, str) for condition in conditions)
                or not isinstance(runtime_choices, list)
                or not all(
                    isinstance(choice, str)
                    and re.fullmatch(r"C-[0-9a-f]{12}:(?:true|false)", choice)
                    for choice in runtime_choices
                )
                or len(runtime_choices) != len(set(runtime_choices))
                or not isinstance(segments, list)
                or len(segments) != 1
                or not isinstance(segments[0], dict)
                or segments[0].get("kind") != "literal"
                or not isinstance(segments[0].get("text"), str)
                or segments[0]["text"] == ""
                or not isinstance(segments[0].get("stylePath"), list)
                or not all(
                    isinstance(value, str) for value in segments[0]["stylePath"]
                )
                or conditions
                or runtime_choices
            ):
                raise HarnessFailure(
                    f"invalid visible-string fixed-fragment obligation for {entry_id}"
                )
            visible_fingerprint = tuple(
                (
                    str(segment.get("text", "")) if segment.get("kind") == "literal" else "<slot>",
                    tuple(str(value) for value in segment.get("stylePath", [])),
                )
                for segment in segments
            )
            signature = (tuple(runtime_choices), visible_fingerprint)
            if signature in branch_signatures:
                raise HarnessFailure(
                    f"duplicate visible-string runtime branch for {entry_id}: "
                    + ",".join(runtime_choices)
                )
            branch_signatures.add(signature)
            branch_ids.add(branch_id)
            obligations.add((entry_id, branch_id))
        ids.add(entry_id)

    if len(obligations) != sum(len(entry["branches"]) for entry in entries):
        raise HarnessFailure("duplicate visible-string site/branch obligation")


def load_visible_string_exemptions(
    path: Path, commit: str
) -> dict[tuple[str, str], dict[str, Any]]:
    if not path.is_file():
        raise HarnessFailure(f"visible-string exemption registry is missing: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 3:
        raise HarnessFailure("visible-string exemptions schemaVersion must be 3")
    if data.get("baselineCommit") != commit:
        raise HarnessFailure("visible-string exemptions commit does not match manifest")
    result: dict[tuple[str, str], dict[str, Any]] = {}
    for entry in data.get("entries", []):
        entry_id = entry.get("id")
        branch_id = entry.get("branchId")
        reason = entry.get("reason")
        obstacle_kind = entry.get("obstacleKind")
        evidence = entry.get("baselineEvidence")
        probe = entry.get("probe")
        decision = entry.get("userDecisionId")
        if (
            not isinstance(entry_id, str)
            or not entry_id
            or not isinstance(branch_id, str)
            or not re.fullmatch(r"B-[0-9a-f]{12}", branch_id)
            or not isinstance(reason, str)
            or not reason.strip()
            or obstacle_kind
            not in {
                "unavailable-physical-device",
                "unavailable-operating-system",
                "unavailable-terminal-capability",
            }
            or not isinstance(evidence, dict)
            or not isinstance(evidence.get("path"), str)
            or not re.fullmatch(r"packages/(?:coding-agent|tui)/src/.+", evidence["path"])
            or not isinstance(evidence.get("line"), int)
            or evidence["line"] < 1
            or not isinstance(probe, dict)
            or not isinstance(probe.get("command"), list)
            or not probe["command"]
            or not all(isinstance(part, str) and part for part in probe["command"])
            or not isinstance(probe.get("expected"), str)
            or not probe["expected"]
            or not isinstance(probe.get("observed"), str)
            or not probe["observed"]
            or not isinstance(decision, str)
            or not re.fullmatch(
                r"USER-[0-9]{4}-[0-9]{2}-[0-9]{2}-[A-Z0-9][A-Z0-9-]*",
                decision,
            )
        ):
            raise HarnessFailure("invalid visible-string structured exemption")
        obligation = (entry_id, branch_id)
        if obligation in result:
            raise HarnessFailure(
                f"duplicate visible-string exemption: {entry_id}/{branch_id}"
            )
        result[obligation] = {
            "reason": reason.strip(),
            "obstacleKind": obstacle_kind,
            "baselineEvidence": evidence,
            "probe": probe,
            "userDecisionId": decision,
        }
    return result


def validate_checked_visible_string_inventory(
    baseline: Path, commit: str, inventory_path: Path
) -> dict[str, Any]:
    if not inventory_path.is_file():
        raise HarnessFailure(f"visible-string inventory is missing: {inventory_path}")
    checked = json.loads(inventory_path.read_text(encoding="utf-8"))
    validate_visible_string_inventory(checked, commit)
    generated = generate_visible_string_inventory(baseline, commit)
    validate_visible_string_inventory(generated, commit)
    if generated != checked:
        raise HarnessFailure(
            "fixed-baseline visible-string inventory drift; run render-diff.py inventory"
        )
    return checked


def screen_text_and_geometry(data: bytes) -> bytes:
    """Remove styling only; retain every visible byte, cell space, line, and cursor record."""
    result = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", data)
    lines = []
    for line in result.splitlines(keepends=True):
        ending = b"\n" if line.endswith(b"\n") else b""
        body = line[:-1] if ending else line
        if b"<PRODUCT" in body:
            body = body.rstrip(b" ")
        lines.append(body + ending)
    result = b"".join(lines)
    return re.sub(rb"<CURSOR [0-9]+,[0-9]+,0>", b"<CURSOR hidden>", result)


VISIBLE_SITE_MARKER = re.compile(
    rb"\x1b\]777;cadr-visible-branch;phase=(begin|end|construct);"
    rb"site=(VS-[0-9a-f]{16});"
    rb"branch=(B-[0-9a-f]{12})\x07"
)


def visible_branch_ids(data: bytes, label: str) -> list[tuple[str, str]]:
    return [
        obligation
        for obligation, _effect in visible_branch_effects(data, label)
    ]


def visible_branch_effects(
    data: bytes, label: str
) -> list[tuple[tuple[str, str], bool | None]]:
    markers = list(VISIBLE_SITE_MARKER.finditer(data))
    if data.count(b"\x1b]777;cadr-visible-branch;") != len(markers):
        raise HarnessFailure(f"malformed visible-site branch marker in {label}")

    def has_terminal_cell_effect(start: int, end: int) -> bool:
        cursor = start
        while cursor < end:
            value = data[cursor]
            if value == 0x1B:
                if cursor + 1 >= end:
                    return False
                introducer = data[cursor + 1]
                if introducer == ord("["):
                    match = re.match(rb"\x1b\[[0-?]*[ -/]*[@-~]", data[cursor:end])
                    if match:
                        cursor += len(match.group(0))
                        continue
                elif introducer == ord("]"):
                    match = re.match(rb"\x1b\].*?(?:\x07|\x1b\\)", data[cursor:end], re.DOTALL)
                    if match:
                        cursor += len(match.group(0))
                        continue
                elif introducer in b"P_X^":
                    match = re.match(rb"\x1b[P_X^].*?\x1b\\", data[cursor:end], re.DOTALL)
                    if match:
                        cursor += len(match.group(0))
                        continue
                cursor += 2
                continue
            if value >= 0x20 and value != 0x7F:
                return True
            if value in b"\t\n\r\b":
                return True
            cursor += 1
        return False

    active: list[dict[str, Any]] = []
    result: list[tuple[tuple[str, str], bool]] = []
    offset = 0
    for marker in markers:
        if has_terminal_cell_effect(offset, marker.start()):
            for frame in active:
                frame["effect"] = True
        phase, site_id, branch_id = (
            value.decode("ascii") for value in marker.groups()
        )
        obligation = (site_id, branch_id)
        if phase == "construct":
            result.append((obligation, None))
        elif phase == "begin":
            active.append({"obligation": obligation, "effect": False})
        else:
            matching_index = next(
                (
                    index
                    for index, frame in enumerate(active)
                    if frame["obligation"] == obligation
                ),
                None,
            )
            if matching_index is None:
                raise HarnessFailure(
                    f"unmatched visible-site branch end marker in {label}: "
                    + "/".join(obligation)
                )
            # Nested typed string producers can emit crossing lifetimes: the
            # deepest producer begins first, while its caller ends first. Match
            # the exact site/branch instead of imposing a stack shape that the
            # instrumented baseline does not promise.
            frame = active.pop(matching_index)
            result.append((obligation, bool(frame["effect"])))
        offset = marker.end()
    if has_terminal_cell_effect(offset, len(data)):
        for frame in active:
            frame["effect"] = True
    if active:
        raise HarnessFailure(
            f"unterminated visible-site branch marker in {label}: "
            + ", ".join("/".join(frame["obligation"]) for frame in active)
        )
    return result


def analyze_visible_string_coverage(
    inventory: dict[str, Any], manifest: dict[str, Any],
    marker_streams: dict[str, bytes], exemptions_path: Path, analysis_root: Path,
) -> None:
    exemptions = load_visible_string_exemptions(
        exemptions_path, manifest["baselineCommit"]
    )
    all_inventory_site_branches = {
        (entry["id"], branch["id"])
        for entry in inventory["entries"]
        for branch in entry["branches"]
    }
    inventory_branches = {
        branch["id"]
        for entry in inventory["entries"]
        if entry["sink"]["channel"] == "printable-visible"
        for branch in entry["branches"]
    }
    exempted_branches = {branch_id for _entry_id, branch_id in exemptions}
    if len(exempted_branches) != len(exemptions):
        raise HarnessFailure(
            "duplicate global visible-string fragment exemptions"
        )
    unknown_exemptions = sorted(
        obligation for obligation in exemptions
        if obligation not in all_inventory_site_branches
        or obligation[1] not in inventory_branches
    )
    if unknown_exemptions:
        raise HarnessFailure(
            "stale visible-string exemptions: "
            + ", ".join(f"{site}/{branch}" for site, branch in unknown_exemptions)
        )
    channels = {
        (entry["id"], branch["id"]): entry["sink"]["channel"]
        for entry in inventory["entries"]
        for branch in entry["branches"]
    }
    captures: dict[str, list[str]] = {}
    terminal_captures: dict[str, list[str]] = {}
    constructed_captures: dict[str, list[str]] = {}
    effectless_printable_markers: dict[tuple[str, str], list[str]] = {}
    for key, stream in marker_streams.items():
        for obligation, has_effect in visible_branch_effects(stream, key):
            if obligation not in all_inventory_site_branches:
                raise HarnessFailure(
                    "instrumented capture emitted unknown site/branch: "
                    + "/".join(obligation)
                )
            branch_id = obligation[1]
            if has_effect is None:
                constructed_captures.setdefault(branch_id, []).append(key)
                captures.setdefault(branch_id, []).append(key)
                continue
            if channels[obligation] == "printable-visible" and not has_effect:
                effectless_printable_markers.setdefault(obligation, []).append(key)
                continue
            terminal_captures.setdefault(branch_id, []).append(key)
            captures.setdefault(branch_id, []).append(key)
    effectless_only = {
        obligation: keys
        for obligation, keys in effectless_printable_markers.items()
        if obligation[1] not in captures
    }
    if effectless_only:
        raise HarnessFailure(
            "printable visible-site marker reached the PTY without a terminal "
            "cell/effect: "
            + ", ".join(
                f"{site}/{branch}@{key}"
                for (site, branch), keys in sorted(effectless_only.items())
                for key in keys[:1]
            )
        )
    covered_exemptions = sorted(
        obligation for obligation in exemptions if obligation[1] in captures
    )
    if covered_exemptions:
        raise HarnessFailure(
            "visible-string exemptions now have real captures: "
            + ", ".join(
                f"{site}/{branch}" for site, branch in covered_exemptions
            )
        )
    missing = sorted(
        branch_id for branch_id in inventory_branches
        if branch_id not in captures and branch_id not in exempted_branches
    )
    report = []
    branches_by_id: dict[str, dict[str, Any]] = {}
    sources_by_branch: dict[str, list[dict[str, Any]]] = {}
    for entry in inventory["entries"]:
        for branch in entry["branches"]:
            branches_by_id.setdefault(branch["id"], branch)
            sources_by_branch.setdefault(branch["id"], []).append(
                {"id": entry["id"], "site": entry["site"], "sink": entry["sink"]}
            )
    exemptions_by_branch = {
        branch_id: exemptions[(entry_id, branch_id)]
        for entry_id, branch_id in exemptions
    }
    for branch_id in sorted(branches_by_id):
        observed = sorted(set(captures.get(branch_id, [])))
        report.append(
            {
                "branchId": branch_id,
                "branch": branches_by_id[branch_id],
                "sources": sources_by_branch[branch_id],
                "captures": observed,
                "terminalCaptures": sorted(set(terminal_captures.get(branch_id, []))),
                "constructedCaptures": sorted(set(constructed_captures.get(branch_id, []))),
                "exemption": exemptions_by_branch.get(branch_id),
            }
        )
    report_path = analysis_root / "visible-string-coverage.json"
    report_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    if missing:
        previews = []
        for branch_id in missing[:20]:
            source = sources_by_branch[branch_id][0]
            previews.append(
                f"{branch_id}={source['site']['path']}:{source['site']['line']}"
            )
        raise HarnessFailure(
            "uncaptured baseline visible-string branches "
            f"({len(missing)} of {len(inventory_branches)}; "
            f"captured={len(captures)}): "
            + ", ".join(previews)
            + f"; report={report_path}"
        )
    printable_captures = sum(branch_id in captures for branch_id in inventory_branches)
    protocol_branches = {
        branch["id"]
        for entry in inventory["entries"]
        if entry["sink"]["channel"] == "terminal-protocol"
        for branch in entry["branches"]
    }
    protocol_captures = sum(branch_id in captures for branch_id in protocol_branches)
    print(
        "visible-string coverage: "
        f"printable_sites={sum(entry['sink']['channel'] == 'printable-visible' for entry in inventory['entries'])} "
        f"printable_branches={len(inventory_branches)} "
        f"printable_terminal_or_sink_captures={printable_captures} "
        f"structured_exemptions={len(exemptions)} "
        f"protocol_sites={sum(entry['sink']['channel'] == 'terminal-protocol' for entry in inventory['entries'])} "
        f"protocol_branches={len(protocol_branches)} "
        f"protocol_observed={protocol_captures} report={report_path}"
    )


def set_winsize(fd: int, columns: int, rows: int) -> None:
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))


def establish_controlling_terminal() -> None:
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)
    os.tcsetpgrp(0, os.getpgrp())


def credential_environment_variable_p(key: str) -> bool:
    upper = key.upper()
    return upper.endswith(
        ("_API_KEY", "_TOKEN", "_SECRET", "_CREDENTIALS")
    ) or upper in {
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "AWS_SESSION_TOKEN",
        "GH_TOKEN",
        "GITHUB_TOKEN",
        "GOOGLE_APPLICATION_CREDENTIALS",
    }


def read_ready(fd: int, output: bytearray, timeout: float, process: subprocess.Popen[bytes]) -> None:
    ready, _, _ = select.select([fd], [], [], timeout)
    if not ready:
        if process.poll() is not None:
            drain(fd, output)
            raise HarnessFailure(f"driver exited early with status {process.returncode}")
        return
    try:
        chunk = os.read(fd, 65536)
    except OSError as error:
        if error.errno == errno.EIO:
            return
        raise
    output.extend(chunk)


def drain(fd: int, output: bytearray) -> None:
    while True:
        ready, _, _ = select.select([fd], [], [], 0)
        if not ready:
            return
        try:
            chunk = os.read(fd, 65536)
        except OSError as error:
            if error.errno == errno.EIO:
                return
            raise
        if not chunk:
            return
        output.extend(chunk)


def wait_for(
    fd: int,
    output: bytearray,
    needle: bytes,
    timeout: float,
    process: subprocess.Popen[bytes],
    *,
    semantic: bool = False,
) -> None:
    deadline = time.monotonic() + timeout
    while needle not in (
        VISIBLE_SITE_MARKER.sub(b"", bytes(output)) if semantic else output
    ):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            tail = bytes(output[-4000:]).decode("utf-8", errors="backslashreplace")
            raise HarnessFailure(f"timed out waiting for {needle!r}; transcript tail:\n{tail}")
        read_ready(fd, output, min(0.1, remaining), process)


def wait_for_count(
    fd: int,
    output: bytearray,
    needle: bytes,
    minimum: int,
    timeout: float,
    process: subprocess.Popen[bytes],
    *,
    semantic: bool = False,
) -> None:
    deadline = time.monotonic() + timeout
    while (
        VISIBLE_SITE_MARKER.sub(b"", bytes(output)).count(needle)
        if semantic
        else output.count(needle)
    ) < minimum:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            tail = bytes(output[-4000:]).decode("utf-8", errors="backslashreplace")
            raise HarnessFailure(
                f"timed out waiting for occurrence {minimum} of {needle!r}; "
                f"transcript tail:\n{tail}"
            )
        read_ready(fd, output, min(0.1, remaining), process)


def wait_for_complete_render(
    fd: int,
    output: bytearray,
    timeout: float,
    process: subprocess.Popen[bytes],
) -> None:
    render_begin = b"\x1b[?2026h"
    render_end = b"\x1b[?2026l"
    deadline = time.monotonic() + timeout
    while True:
        drain(fd, output)
        open_frames = output.count(render_begin) - output.count(render_end)
        if open_frames <= 0:
            return
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise HarnessFailure("timed out waiting for synchronized render frame end")
        wait_for_count(
            fd,
            output,
            render_end,
            output.count(render_end) + open_frames,
            remaining,
            process,
        )


def wait_exit(fd: int, output: bytearray, process: subprocess.Popen[bytes], timeout: float) -> int:
    deadline = time.monotonic() + timeout
    while process.poll() is None:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            process.kill()
            process.wait()
            drain(fd, output)
            tail = bytes(output[-4000:]).decode("utf-8", errors="backslashreplace")
            raise HarnessFailure(
                f"render-diff driver did not exit; transcript tail:\n{tail}"
            )
        read_ready(fd, output, min(0.1, remaining), process)
    drain(fd, output)
    return process.returncode


def install_fake_github_cli(home: Path) -> Path:
    binary_directory = home / "render-diff-bin"
    binary_directory.mkdir(parents=True, exist_ok=True)
    binary = binary_directory / "gh"
    binary.write_text(
        "#!/usr/bin/env python3\n"
        "import sys\n"
        "arguments = sys.argv[1:]\n"
        "if arguments == ['auth', 'status']:\n"
        "    raise SystemExit(0)\n"
        "if arguments[:2] == ['gist', 'create']:\n"
        "    print('https://gist.github.com/render/render-gist-fixed')\n"
        "    raise SystemExit(0)\n"
        "print('unexpected render-diff gh arguments', file=sys.stderr)\n"
        "raise SystemExit(2)\n",
        encoding="utf-8",
    )
    binary.chmod(0o700)
    return binary_directory


def fixed_environment(home: Path, columns: int, rows: int, ready_path: Path) -> dict[str, str]:
    env = os.environ.copy()
    for key in ("TMUX", "TMUX_PANE", "WT_SESSION", "KITTY_WINDOW_ID", "SSH_TTY"):
        env.pop(key, None)
    for key in tuple(env):
        if credential_environment_variable_p(key):
            env.pop(key, None)
    fake_binary_directory = install_fake_github_cli(home)
    env.update(
        {
            "HOME": str(home),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            # Both products shell out to rg with identical arguments and no
            # --sort, so result order follows rg's parallel walker, which is
            # scheduling-dependent and flips under gate load.  Pin every
            # captured rg invocation to the deterministic single-threaded
            # walker; the config file applies equally to pi and Cadr.
            "RIPGREP_CONFIG_PATH": str(DEFAULT_MANIFEST.parent / "ripgrep.conf"),
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "COLORFGBG": "15;0",
            "COLUMNS": str(columns),
            "LINES": str(rows),
            "NO_COLOR": "",
            "PI_OFFLINE": "1",
            "PATH": str(fake_binary_directory) + os.pathsep + env.get("PATH", ""),
            "RENDER_DIFF_READY_PATH": str(ready_path),
        }
    )
    return env


def driver_command(
    side: str,
    baseline: Path,
    manifest: Path,
    scenario_id: str,
    cwd: Path,
    agent_dir: Path,
    session_dir: Path,
) -> tuple[list[str], Path]:
    if side == "pi":
        command = [
            str(baseline / "node_modules/.bin/tsx"),
            "test/goal15-render-driver.ts",
            str(manifest),
            scenario_id,
            str(cwd),
            str(agent_dir),
            str(session_dir),
        ]
        return command, baseline / "packages/coding-agent"
    quicklisp = Path(os.environ.get("QUICKLISP_SETUP", Path.home() / "quicklisp/setup.lisp"))
    command = [
        os.environ.get("SBCL", "sbcl"),
        "--noinform",
        "--disable-debugger",
        "--script",
        str(CADR_DRIVER),
        str(ROOT),
        str(quicklisp),
        str(manifest),
        scenario_id,
        str(cwd),
        str(agent_dir),
        str(session_dir),
    ]
    return command, ROOT


def run_actions(
    side: str,
    actions: list[dict[str, Any]],
    master_fd: int,
    output: bytearray,
    process: subprocess.Popen[bytes],
    timeout: float,
    checkpoints: list[dict[str, Any]],
    ready_path: Path | None = None,
) -> None:
    settled_target = 0
    for index, action in enumerate(actions, start=1):
        try:
            if "waitFor" in action:
                wait_for(
                    master_fd,
                    output,
                    action["waitFor"].encode(),
                    timeout,
                    process,
                    semantic=True,
                )
            elif "waitForNext" in action:
                needle = action["waitForNext"].encode()
                semantic_output = VISIBLE_SITE_MARKER.sub(b"", bytes(output))
                wait_for_count(
                    master_fd,
                    output,
                    needle,
                    semantic_output.count(needle) + 1,
                    timeout,
                    process,
                    semantic=True,
                )
            elif "waitForHex" in action:
                wait_for(master_fd, output, bytes.fromhex(action["waitForHex"]), timeout, process)
            elif "waitForSide" in action:
                wait_for(
                    master_fd,
                    output,
                    action["waitForSide"][side].encode(),
                    timeout,
                    process,
                    semantic=True,
                )
            elif "sendText" in action:
                render_end = b"\x1b[?2026l"
                for character in action["sendText"]:
                    before = output.count(render_end)
                    os.write(master_fd, character.encode())
                    wait_for_count(
                        master_fd, output, render_end, before + 1, timeout, process
                    )
            elif "send" in action:
                try:
                    os.write(master_fd, KEYS[action["send"]])
                except KeyError as error:
                    raise HarnessFailure(f"unknown key: {action['send']}") from error
            elif "sendRepeated" in action:
                specification = action["sendRepeated"]
                key = specification.get("key")
                count = specification.get("count")
                checkpoint_prefix = specification.get("checkpointPrefix")
                if key not in KEYS or not isinstance(count, int) or count < 1:
                    raise HarnessFailure(f"invalid repeated key action: {specification!r}")
                if checkpoint_prefix is not None and (
                    not isinstance(checkpoint_prefix, str) or not checkpoint_prefix
                ):
                    raise HarnessFailure(
                        f"invalid repeated checkpoint prefix: {specification!r}"
                    )
                render_end = b"\x1b[?2026l"
                for repeated_index in range(1, count + 1):
                    before = output.count(render_end)
                    os.write(master_fd, KEYS[key])
                    wait_for_count(
                        master_fd, output, render_end, before + 1, timeout, process
                    )
                    if checkpoint_prefix:
                        checkpoints.append(
                            {
                                "id": f"{checkpoint_prefix}-{repeated_index:02d}",
                                "offset": len(output),
                            }
                        )
            elif "sendSide" in action:
                key = action["sendSide"].get(side)
                if key is not None:
                    try:
                        os.write(master_fd, KEYS[key])
                    except KeyError as error:
                        raise HarnessFailure(f"unknown key for {side}: {key}") from error
            elif "pauseMs" in action:
                deadline = time.monotonic() + action["pauseMs"] / 1000
                while time.monotonic() < deadline:
                    read_ready(
                        master_fd,
                        output,
                        max(0.0, min(0.01, deadline - time.monotonic())),
                        process,
                    )
            elif "fetchUrl" in action:
                # Deliver an HTTP request on behalf of the scenario (e.g. the
                # browser callback in a loopback OAuth login flow).
                url = action["fetchUrl"]
                try:
                    with urllib.request.urlopen(url, timeout=10) as response:
                        response.read()
                except Exception as error:
                    raise HarnessFailure(
                        f"fetchUrl failed for {url}: {error}"
                    ) from error
            elif "triggerCrash" in action:
                if action["triggerCrash"] is not True or ready_path is None:
                    raise HarnessFailure(
                        "triggerCrash requires the driver ready channel"
                    )
                # Both drivers poll for this file and raise the sentinel on
                # their own main thread; a signal cannot reach the real
                # process through the tsx launcher, and SBCL reserves the
                # user signals for its own runtime.
                Path(str(ready_path) + ".crash").write_text(
                    "crash\n", encoding="ascii"
                )
            elif "waitForAgentSettled" in action:
                if action["waitForAgentSettled"] is not True or ready_path is None:
                    raise HarnessFailure(
                        f"invalid agent-settled action or missing side channel: {action!r}"
                    )
                settled_target += 1
                deadline = time.monotonic() + timeout
                while True:
                    try:
                        settled_count = ready_path.read_text(
                            encoding="utf-8"
                        ).splitlines().count("agent-settled")
                    except FileNotFoundError:
                        settled_count = 0
                    if settled_count >= settled_target:
                        drain(master_fd, output)
                        remaining = deadline - time.monotonic()
                        if remaining <= 0:
                            raise HarnessFailure(
                                "timed out waiting for settled render frame"
                            )
                        wait_for_complete_render(
                            master_fd,
                            output,
                            max(0.0, deadline - time.monotonic()),
                            process,
                        )
                        break
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise HarnessFailure(
                            "timed out waiting for agent-settled side-channel event "
                            f"{settled_target}"
                        )
                    read_ready(
                        master_fd,
                        output,
                        min(0.05, remaining),
                        process,
                    )
            elif "checkpoint" in action:
                wait_for_complete_render(master_fd, output, timeout, process)
            else:
                raise HarnessFailure(f"unknown action: {action}")
        except (HarnessFailure, OSError) as error:
            tail = bytes(output[-4000:]).decode("utf-8", errors="backslashreplace")
            raise HarnessFailure(
                f"{side} action {index} failed ({action!r}): {error}; "
                f"transcript tail:\n{tail}"
            ) from error
        checkpoint = action.get("checkpoint")
        if checkpoint:
            checkpoints.append({"id": checkpoint, "offset": len(output)})


def capture_side(
    side: str,
    baseline: Path,
    manifest_path: Path,
    scenario: dict[str, Any],
    dimension: dict[str, int],
    sandbox: Path,
    timeout: float,
    cadr_cache: Path | None = None,
    visible_sites: bool = False,
) -> tuple[bytes, list[dict[str, Any]]]:
    side_root = sandbox / ("pi00" if side == "pi" else "cadr")
    home = side_root / "home"
    cwd = side_root / "workspace"
    agent_dir = home / (".pi/agent" if side == "pi" else ".cadr/agent")
    session_dir = render_side_session_directory(sandbox, side)
    home.mkdir(parents=True)
    cwd.mkdir(parents=True)
    agent_dir.mkdir(parents=True)
    session_dir.mkdir(parents=True)
    (cwd / "sample.txt").write_text("alpha\n中文🙂\nomega\n", encoding="utf-8")
    (cwd / "notes").mkdir()
    (cwd / "notes/alpha.txt").write_text("needle alpha\n", encoding="utf-8")
    (cwd / "notes/beta.md").write_text("needle beta\n", encoding="utf-8")
    if scenario.get("setup", {}).get("projectTrusted") is False:
        config_dir = cwd / (".pi" if side == "pi" else ".cadr")
        config_dir.mkdir()
        (config_dir / "settings.json").write_text("{}\n", encoding="utf-8")
    ready_path = side_root / "ready"
    command, process_cwd = driver_command(
        side, baseline, manifest_path, scenario["id"], cwd, agent_dir, session_dir
    )
    master_fd, slave_fd = os.openpty()
    set_winsize(slave_fd, dimension["columns"], dimension["rows"])
    output = bytearray()
    checkpoints: list[dict[str, Any]] = []
    process: subprocess.Popen[bytes] | None = None
    try:
        environment = fixed_environment(
            home, dimension["columns"], dimension["rows"], ready_path
        )
        if visible_sites:
            if side != "pi":
                raise HarnessFailure("visible-site instrumentation is baseline-only")
            environment["RENDER_DIFF_VISIBLE_SITES"] = "1"
            environment["RENDER_DIFF_VISIBLE_CONSTRUCTS"] = "1"
        if side == "cadr":
            environment["RENDER_DIFF_REFERENCE_CHANGELOG"] = str(
                baseline / "packages/coding-agent/CHANGELOG.md"
            )
        if side == "cadr" and cadr_cache is not None:
            cadr_cache.mkdir(parents=True, exist_ok=True)
            environment["XDG_CACHE_HOME"] = str(cadr_cache)
            environment["ASDF_OUTPUT_TRANSLATIONS"] = f"/:{cadr_cache}/"
        process = subprocess.Popen(
            command,
            cwd=process_cwd,
            env=environment,
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            close_fds=True,
            preexec_fn=establish_controlling_terminal,
        )
        os.close(slave_fd)
        slave_fd = -1
        run_actions(
            side,
            scenario["actions"],
            master_fd,
            output,
            process,
            timeout,
            checkpoints,
            ready_path,
        )
        status = wait_exit(master_fd, output, process, timeout)
        expected_exit = scenario.get("expectedExit", 0)
        if isinstance(expected_exit, dict):
            expected_exit = expected_exit[side]
        if status != expected_exit:
            tail = bytes(output[-4000:]).decode("utf-8", errors="backslashreplace")
            raise HarnessFailure(
                f"{side} driver exited {status}, expected {expected_exit}; transcript tail:\n{tail}"
            )
        checkpoints.append({"id": "process-exit", "offset": len(output), "status": status})
        return bytes(output), checkpoints
    finally:
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        os.close(master_fd)
        if slave_fd >= 0:
            os.close(slave_fd)


def normalize_fixed_values(data: bytes) -> bytes:
    replacements = [
        (str(Path("/tmp/cadr-render-diff-pi-74caa2649")).encode(), b"<PI_BASELINE>"),
        (
            b"pi\x1b[39m\x1b[22m\x1b[38;2;102;102;102m v0.83.0",
            b"<PRODUCT>\x1b[39m\x1b[22m\x1b[38;2;102;102;102m v<VERSION>",
        ),
        (
            b"pi\x1b[0m\x1b[38;2;102;102;102m v0.83.0",
            b"<PRODUCT>\x1b[0m\x1b[38;2;102;102;102m v<VERSION>",
        ),
        (
            b"cadr\x1b[0m\x1b[38;2;102;102;102m v0.2.0",
            b"<PRODUCT>\x1b[0m\x1b[38;2;102;102;102m v<VERSION>",
        ),
        (b"cadr v0.2.0\x1b[22m", b"<PRODUCT> v<VERSION>\x1b[22m"),
        (b"pi v0.83.0", b"<PRODUCT> v<VERSION>"),
        (b"cadr v0.2.0", b"<PRODUCT> v<VERSION>"),
        (b"\x1b]0;\xcf\x80 - ", b"\x1b]0;<PRODUCT> - "),
        (b"\x1b]0;cadr - ", b"\x1b]0;<PRODUCT> - "),
        (b"Pi can explain its own features", b"<PRODUCT_TITLE> can explain its own features"),
        (b"Cadr can explain its own features", b"<PRODUCT_TITLE> can explain its own features"),
        (b"extend Pi.", b"extend <PRODUCT_TITLE>."),
        (b"extend Cadr.", b"extend <PRODUCT_TITLE>."),
        (b"Project .pi resources", b"Project <PRODUCT_CONFIG> resources"),
        (b"Project .cadr resources", b"Project <PRODUCT_CONFIG> resources"),
        (b"restart pi.", b"restart <PRODUCT>."),
        (b"restart cadr.", b"restart <PRODUCT>."),
        (b"<HOME>/.pi/agent/", b"<HOME>/<PRODUCT_CONFIG>/"),
        (b"<HOME>/.cadr/agent/", b"<HOME>/<PRODUCT_CONFIG>/"),
        (b"<HOME>/.cadr/", b"<HOME>/<PRODUCT_CONFIG>/"),
        (b"To resume this session: pi ", b"To resume this session: <PRODUCT> "),
        (b"To resume this session: cadr ", b"To resume this session: <PRODUCT> "),
        (
            b"To resume this session:\x1b[0m pi ",
            b"To resume this session:\x1b[0m <PRODUCT> ",
        ),
        (
            b"To resume this session:\x1b[39m cadr ",
            b"To resume this session:\x1b[39m <PRODUCT> ",
        ),
        (
            b"\x1b[2mTo resume this session:\x1b[22m pi ",
            b"\x1b[2mTo resume this session:\x1b[22m <PRODUCT> ",
        ),
        (
            b"\x1b[2mTo resume this session:\x1b[22m cadr ",
            b"\x1b[2mTo resume this session:\x1b[22m <PRODUCT> ",
        ),
        (b" pi --session ", b" <PRODUCT> --session "),
        (b" cadr --session ", b" <PRODUCT> --session "),
        (b" pi --session-dir ", b" <PRODUCT> --session-dir "),
        (b" cadr --session-dir ", b" <PRODUCT> --session-dir "),
        (
            b"pi-session-2023-11-14T22-13-20-000Z_render-session.html",
            b"<PRODUCT>-session-<FIXED_TIME>_<SESSION_ID>.html",
        ),
        (
            b"cadr-session-2023-11-14T22-13-20-000Z_render-session.html",
            b"<PRODUCT>-session-<FIXED_TIME>_<SESSION_ID>.html",
        ),
    ]
    result = data
    for old, new in replacements:
        result = result.replace(old, new)
    result = re.sub(rb"(?<=Took )[0-9]+(?:\.[0-9]+)?(?=s)", b"<ELAPSED>", result)
    result = re.sub(
        rb"(?<=\x1b\[38;2;138;190;183m)"
        rb"\xe2[\xa0-\xa3][\x80-\xbf]"
        rb"(?=\x1b\[39m \x1b\[38;2;128;128;128mWorking\.\.\.)",
        "⠋".encode("utf-8"),
        result,
    )
    result = re.sub(
        rb"(?<=\x1b\[38;2;138;190;183m)"
        rb"\xe2[\xa0-\xa3][\x80-\xbf]"
        rb"(?=\x1b\[39m \x1b\[38;2;128;128;128m(?:"
        rb"Compacting context\.\.\.|"
        rb"Auto-compacting\.\.\. \(escape to cancel\)|"
        rb"Context overflow detected, Auto-compacting\.\.\. \(escape to cancel\)"
        rb"))",
        "⠋".encode("utf-8"),
        result,
    )
    result = re.sub(
        rb"(?<=\x1b\[38;2;181;189;104m)"
        rb"\xe2[\xa0-\xa3][\x80-\xbf]"
        rb"(?=\x1b\[39m \x1b\[38;2;128;128;128m"
        rb"Running\.\.\. \(escape/ctrl\+c to cancel\))",
        "⠋".encode("utf-8"),
        result,
    )
    result = re.sub(
        rb"(?<=cadr-crash-)[0-9]+-[0-9]+-[0-9]+(?=\.log)",
        b"<CRASH_ID>",
        result,
    )
    resume_prefixes = (
        b"To resume this session: <PRODUCT> ",
        b"To resume this session:\x1b[0m <PRODUCT> ",
        b"To resume this session:\x1b[39m <PRODUCT> ",
        b"\x1b[2mTo resume this session:\x1b[22m <PRODUCT> ",
    )
    session_uuid = (
        rb"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
    )
    for prefix in resume_prefixes:
        for command_prefix in (
            b"--session ",
            b"--session-dir <SESSION_DIR> --session ",
        ):
            bounded_resume = (
                screen_wrapped_literal_pattern(prefix)
                + screen_wrapped_literal_pattern(command_prefix)
            )
            result = re.sub(
                b"(" + bounded_resume + b")" + session_uuid,
                rb"\1<SESSION_ID>",
                result,
            )
    result = re.sub(
        rb"/tmp/(?:pi|cadr)-bash-[0-9a-f-]+\.log",
        b"/tmp/<PRODUCT>-bash-<OUTPUT_ID>.log",
        result,
    )
    return result


def render_side_session_directory(sandbox: Path, side: str) -> Path:
    if side not in {"pi", "cadr"}:
        raise HarnessFailure(f"unknown render side: {side}")
    return sandbox / ("pi00" if side == "pi" else "cadr") / "render-sessions"


def normalized(data: bytes, side: str, sandbox: Path) -> bytes:
    """Apply only adjudication-candidate value substitutions; preserve layout and ANSI."""
    result = data
    side_root = sandbox / ("pi00" if side == "pi" else "cadr")
    for old, new in (
        (
            str(render_side_session_directory(sandbox, side)).encode(),
            b"<SESSION_DIR>",
        ),
        (str(side_root / "home").encode(), b"<HOME>"),
        (str(side_root / "workspace").encode(), b"<CWD>"),
        (str(side_root).encode(), b"<SANDBOX>"),
    ):
        result = result.replace(old, new)
    return normalize_fixed_values(result)


def screen_wrapped_literal_pattern(value: bytes) -> bytes:
    """Match one fixed terminal string with optional hard wraps between bytes."""
    separator = rb"(?:\r?\n)?"
    return separator.join(re.escape(value[index : index + 1]) for index in range(len(value)))


def normalized_screen(data: bytes, side: str) -> bytes:
    """Normalize a terminal-emulated screen without changing replay geometry."""
    escaped_side = re.escape(("pi00" if side == "pi" else "cadr").encode())
    prefix = rb"/tmp/cadr-render-diff-[^/\r\n]+/" + escaped_side
    separator = rb"(?:\r?\n)?"
    temporary_suffix = rb"[a-z0-9_]" + (separator + rb"[a-z0-9_]") * 7
    wrapped_session_directory = (
        screen_wrapped_literal_pattern(b"/tmp/cadr-render-diff-")
        + separator
        + temporary_suffix
        + separator
        + screen_wrapped_literal_pattern(
            b"/" + (b"pi00" if side == "pi" else b"cadr") + b"/render-sessions"
        )
    )
    result = re.sub(wrapped_session_directory, b"<SESSION_DIR>", data)
    if side == "cadr":
        wrapped_digits = rb"[0-9](?:(?:\r?\n)?[0-9])*"
        # A hard wrap can land between a dash and a digit ("-\n0"), so each
        # dash tolerates a wrap on both sides.
        wrapped_dash = (
            separator + screen_wrapped_literal_pattern(b"-") + separator
        )
        wrapped_crash_path = (
            screen_wrapped_literal_pattern(b"/tmp/cadr-render-diff-")
            + separator
            + temporary_suffix
            + separator
            + screen_wrapped_literal_pattern(
                b"/cadr/home/.cadr/agent/crash/cadr-crash-"
            )
            + wrapped_digits
            + wrapped_dash
            + wrapped_digits
            + wrapped_dash
            + wrapped_digits
            + separator
            + screen_wrapped_literal_pattern(b".log")
        )
        result = re.sub(
            wrapped_crash_path,
            b"<HOME>/<PRODUCT_CONFIG>/crash/cadr-crash-<CRASH_ID>.log",
            result,
        )
    else:
        wrapped_driver_location = (
            screen_wrapped_literal_pattern(
                b"/tmp/cadr-render-diff-pi-74caa2649/"
                b"packages/coding-agent/test/goal15-render-driver.ts:"
            )
            + rb"[0-9](?:(?:\r?\n)?[0-9])*"
            + separator
            + screen_wrapped_literal_pattern(b":")
            + rb"[0-9](?:(?:\r?\n)?[0-9])*"
        )
        result = re.sub(
            wrapped_driver_location,
            b"<PI_BASELINE>/packages/coding-agent/test/"
            b"goal15-render-driver.ts:<DRIVER_LINE>:<DRIVER_COLUMN>",
            result,
        )
    result = re.sub(prefix + rb"/home", b"<HOME>", result)
    result = re.sub(prefix + rb"/workspace", b"<CWD>", result)
    result = re.sub(prefix, b"<SANDBOX>", result)
    result = normalize_fixed_values(result)
    # Cadr and Pi both hide the hardware cursor while drawing their own editor
    # cell.  tmux retains the hidden cursor's last internal coordinates, but
    # those coordinates are not terminal-visible state.  Preserve every
    # visible cursor coordinate and reduce only an explicitly hidden cursor to
    # its observable state.
    return re.sub(
        rb"<CURSOR [0-9]+,[0-9]+,0>",
        b"<CURSOR hidden>",
        result,
    )


def write_capture(output_dir: Path, scenario_id: str, dimension_id: str, side: str, data: bytes) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    stem = f"{scenario_id}.{dimension_id}.{side}"
    (output_dir / f"{stem}.raw").write_bytes(data)
    (output_dir / f"{stem}.sha256").write_text(hashlib.sha256(data).hexdigest() + "\n", encoding="ascii")


def write_checkpoints(
    output_dir: Path,
    scenario_id: str,
    dimension_id: str,
    side: str,
    checkpoints: list[dict[str, Any]],
) -> None:
    stem = f"{scenario_id}.{dimension_id}.{side}"
    (output_dir / f"{stem}.checkpoints.json").write_text(
        json.dumps(checkpoints, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def annotate_normalized_offsets(
    checkpoints: list[dict[str, Any]], data: bytes, side: str, sandbox: Path
) -> None:
    for checkpoint in checkpoints:
        checkpoint["normalizedOffset"] = len(
            normalized(data[: checkpoint["offset"]], side, sandbox)
        )


def capture(args: argparse.Namespace) -> int:
    manifest_path = args.manifest.resolve()
    manifest = load_manifest(manifest_path)
    scenario = find_scenario(manifest, args.scenario)
    dimension = find_dimension(manifest, args.dimension)
    commit = manifest["baselineCommit"]
    with tempfile.TemporaryDirectory(prefix="cadr-render-diff-") as temporary:
        sandbox = Path(temporary)
        baseline_override = getattr(args, "baseline_override", None)
        baseline = (
            Path(baseline_override).resolve()
            if baseline_override is not None
            else ensure_baseline(
                args.pi_repo.resolve(), commit, args.baseline_cache.resolve()
            )
        )
        visible_sites = bool(getattr(args, "visible_sites", False))
        captures: dict[str, bytes] = {}
        sides = ("pi", "cadr") if args.side == "both" else (args.side,)
        for side in sides:
            raw, checkpoints = capture_side(
                side,
                baseline,
                manifest_path,
                scenario,
                dimension,
                sandbox,
                args.timeout,
                getattr(args, "cadr_cache", None),
                visible_sites,
            )
            captures[side] = raw
            annotate_normalized_offsets(checkpoints, raw, side, sandbox)
            artifact_side = "pi.visible" if visible_sites and side == "pi" else side
            write_capture(
                args.output.resolve(), scenario["id"], args.dimension, artifact_side, raw
            )
            write_checkpoints(
                args.output.resolve(), scenario["id"], args.dimension, artifact_side, checkpoints
            )
            write_capture(
                args.output.resolve(), scenario["id"], args.dimension,
                f"{artifact_side}.normalized",
                normalized(raw, side, sandbox),
            )
        if args.side == "both":
            same = normalized(captures["pi"], "pi", sandbox) == normalized(captures["cadr"], "cadr", sandbox)
            print(
                f"{scenario['id']} {args.dimension}: pi={len(captures['pi'])} bytes "
                f"cadr={len(captures['cadr'])} bytes normalized_equal={str(same).lower()}"
            )
        else:
            print(f"{scenario['id']} {args.dimension}: {args.side}={len(captures[args.side])} bytes")
        return 0


def raw_difference_summary(left: bytes, right: bytes) -> dict[str, Any]:
    prefix = 0
    for prefix, (left_byte, right_byte) in enumerate(zip(left, right), start=1):
        if left_byte != right_byte:
            prefix -= 1
            break
    else:
        prefix = min(len(left), len(right))
    suffix = 0
    suffix_limit = min(len(left), len(right)) - prefix
    while suffix < suffix_limit and left[-1 - suffix] == right[-1 - suffix]:
        suffix += 1
    left_end = len(left) - suffix if suffix else len(left)
    right_end = len(right) - suffix if suffix else len(right)
    return {
        "equal": left == right,
        "commonPrefixBytes": prefix,
        "commonSuffixBytes": suffix,
        "piChangedBytes": left_end - prefix,
        "cadrChangedBytes": right_end - prefix,
        "piPreview": repr(left[prefix : min(left_end, prefix + 160)]),
        "cadrPreview": repr(right[prefix : min(right_end, prefix + 160)]),
    }


def wait_for_path(path: Path, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while not path.is_file():
        if time.monotonic() >= deadline:
            raise HarnessFailure(f"terminal replay handshake timed out: {path}")
        time.sleep(0.01)


RENDER_TMUX_SOCKET_PREFIX = "cadr-rd-"
RENDER_SCREEN_TEMP_PREFIX = "cadr-render-screen-"
# Leftovers younger than this may belong to a live concurrent run; never
# touch them.  Older entries can only be crashed-run residue.
STALE_RESOURCE_AGE_SECONDS = 3600


def sweep_stale_render_resources(now: float | None = None) -> list[str]:
    """Remove render-diff tmux servers and replay dirs left by killed runs.

    Live cleanup is owned by ``tmux_screen``'s ``finally`` block; a hard kill
    (outer timeout, SIGKILL) skips it, so this sweeper is the single owner of
    stale-resource cleanup and runs once at process start.  A tmux socket is
    stale when the pid embedded in its name (``cadr-rd-<pid>-<ns>``) is dead;
    replay dirs are stale after ``STALE_RESOURCE_AGE_SECONDS``.  Returns the
    removed entries for test visibility.
    """
    removed: list[str] = []
    now = time.time() if now is None else now
    socket_dir = Path(tempfile.gettempdir()) / f"tmux-{os.getuid()}"
    if socket_dir.is_dir():
        for socket in sorted(socket_dir.iterdir()):
            if not socket.name.startswith(RENDER_TMUX_SOCKET_PREFIX):
                continue
            parts = socket.name[len(RENDER_TMUX_SOCKET_PREFIX):].split("-", 1)
            try:
                owner_pid = int(parts[0])
            except (ValueError, IndexError):
                continue
            try:
                os.kill(owner_pid, 0)
                continue  # owning run is still alive; leave it alone
            except ProcessLookupError:
                pass
            except PermissionError:
                continue
            subprocess.run(
                ["tmux", "-L", socket.name, "kill-server"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if socket.exists():
                try:
                    socket.unlink()
                except OSError:
                    continue
            removed.append(str(socket))
    temporary_root = Path(tempfile.gettempdir())
    for entry in sorted(temporary_root.glob(f"{RENDER_SCREEN_TEMP_PREFIX}*")):
        try:
            age = now - entry.stat().st_mtime
        except OSError:
            continue
        if age < STALE_RESOURCE_AGE_SECONDS:
            continue
        shutil.rmtree(entry, ignore_errors=True)
        if not entry.exists():
            removed.append(str(entry))
    return removed


def tmux_screen(data: bytes, columns: int, rows: int, temporary: Path) -> bytes:
    if shutil.which("tmux") is None:
        raise HarnessFailure("tmux is required for semantic render-diff analysis")
    temporary.mkdir(parents=True, exist_ok=True)
    input_path = temporary / "terminal.raw"
    input_path.write_bytes(data)
    done_path = temporary / "terminal.done"
    replay_path = temporary / "replay.py"
    replay_path.write_text(
        "import os, pathlib, signal, sys, tty\n"
        "tty.setraw(0)\n"
        "os.write(1, pathlib.Path(sys.argv[1]).read_bytes())\n"
        "os.write(1, b'\\x1b[6n')\n"
        "response = b''\n"
        "while not response.endswith(b'R'):\n"
        "    response += os.read(0, 64)\n"
        "pathlib.Path(sys.argv[2]).touch()\n"
        "while True:\n"
        "    signal.pause()\n",
        encoding="utf-8",
    )
    socket = f"cadr-rd-{os.getpid()}-{time.monotonic_ns()}"
    # User tmux hooks/plugins are outside the fixed render contract and can
    # both alter the screen and keep the client capture pipe open indefinitely.
    tmux = ["tmux", "-L", socket, "-f", "/dev/null"]
    command = shlex.join(
        (sys.executable, str(replay_path), str(input_path), str(done_path))
    )
    environment = os.environ.copy()
    environment.update({"TERM": "xterm-256color", "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"})
    try:
        subprocess.run(
            tmux
            + [
                "new-session",
                "-d",
                "-s",
                "screen",
                "-x",
                str(columns),
                "-y",
                str(rows),
                command,
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            env=environment,
        )
        wait_for_path(done_path, 5.0)
        previous: bytes | None = None
        current = b""
        for _ in range(100):
            current = subprocess.run(
                tmux + ["capture-pane", "-p", "-e", "-N", "-t", "screen"],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=environment,
            ).stdout
            if current == previous:
                break
            previous = current
            time.sleep(0.01)
        else:
            raise HarnessFailure("tmux screen replay did not settle")
        cursor = subprocess.run(
            tmux
            + [
                "display-message",
                "-p",
                "-t",
                "screen",
                "#{cursor_x},#{cursor_y},#{cursor_flag}",
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        ).stdout
        return current + b"<CURSOR " + cursor.rstrip(b"\n") + b">\n"
    finally:
        subprocess.run(
            tmux + ["kill-server"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=environment,
        )


BOILERPLATE_DISPOSITION_NOTES = frozenset(
    {
        "Exact approved semantic screen pair; no product defect is admitted.",
    }
)


def validate_result_adjudications(
    results: list[dict[str, Any]],
    text_covering_classes: frozenset[str] = frozenset(),
) -> None:
    for result in results:
        adjudication = result.get("adjudication")
        if not adjudication:
            continue
        if "cadr-defect" in adjudication.get("kinds", []):
            raise HarnessFailure(
                "cadr-defect disposition remains a gate failure: " + result["key"]
            )
        classes = set(adjudication.get("classes", []))
        note = adjudication.get("note")
        if (
            not isinstance(note, str)
            or not note.strip()
            or note.strip() in BOILERPLATE_DISPOSITION_NOTES
        ):
            raise HarnessFailure(
                "disposition lacks a specific difference note: " + result["key"]
            )
        expected_pair = adjudication.get("screenSha256")
        if not isinstance(expected_pair, dict) or set(expected_pair) != {"pi", "cadr"}:
            raise HarnessFailure(
                "disposition lacks an exact semantic screen pair: " + result["key"]
            )
        actual_pair = {
            "pi": result.get("piScreenSha256"),
            "cadr": result.get("cadrScreenSha256"),
        }
        if actual_pair != expected_pair:
            class_label = "/".join(sorted(classes - {"I01"})) or "I01"
            raise HarnessFailure(
                "semantic screen pair drifted outside the exact "
                f"{class_label} disposition: {result['key']}"
            )
        screen_classes = classes - {"I01"}
        if result.get("screenEqual"):
            if screen_classes:
                raise HarnessFailure(
                    "screen-equal result carries a stale semantic disposition: "
                    + result["key"]
                )
            continue
        if not screen_classes:
            raise HarnessFailure(
                "terminal-protocol-only disposition cannot admit screen differences: "
                + result["key"]
            )
        if not result.get("textGeometryEqual", True) and not (
            classes & text_covering_classes
        ):
            raise HarnessFailure(
                "visible text/geometry difference admitted by a non-text "
                "disposition class: " + result["key"]
            )


def analyze(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest.resolve())
    baseline = ensure_baseline(
        args.pi_repo.resolve(),
        manifest["baselineCommit"],
        args.baseline_cache.resolve(),
    )
    visible_inventory = validate_checked_visible_string_inventory(
        baseline,
        manifest["baselineCommit"],
        args.visible_string_inventory.resolve(),
    )
    disposition_data = load_dispositions(
        args.dispositions.resolve(), manifest["baselineCommit"]
    )
    scenario_ids = {
        scenario["id"]
        for scenario in manifest["scenarios"]
        if args.tier == "full" or scenario.get("tier", "core") == "core"
    }
    scenarios = [
        scenario for scenario in manifest["scenarios"]
        if scenario["id"] in scenario_ids
    ]
    dispositions = {
        key: value
        for key, value in expand_dispositions(disposition_data, manifest).items()
        if key.split("/", 1)[0] in scenario_ids
    }
    capture_root = args.output.resolve()
    analysis_root = args.analysis_output.resolve()
    analysis_root.mkdir(parents=True, exist_ok=True)
    results: list[dict[str, Any]] = []
    pi_screens: dict[str, bytes] = {}
    visible_marker_streams: dict[str, bytes] = {}
    if args.tier == "full":
        construction_path = capture_root / "baseline-construction.pi.visible.raw"
        if not construction_path.is_file():
            raise HarnessFailure(
                "missing baseline visible-string construction artifact: "
                + str(construction_path)
            )
        visible_marker_streams["production-sink-construction"] = construction_path.read_bytes()
    for dimension in manifest["dimensions"]:
        dimension_id = dimension["id"]
        for scenario in scenarios:
            scenario_id = scenario["id"]
            raw_streams: dict[str, bytes] = {}
            normalized_streams: dict[str, bytes] = {}
            checkpoints_by_side: dict[str, list[dict[str, Any]]] = {}
            for side in ("pi", "cadr"):
                stem = f"{scenario_id}.{dimension_id}.{side}"
                raw_path = capture_root / f"{stem}.raw"
                stream_path = capture_root / f"{stem}.normalized.raw"
                checkpoint_path = capture_root / f"{stem}.checkpoints.json"
                if (
                    not raw_path.is_file()
                    or not stream_path.is_file()
                    or not checkpoint_path.is_file()
                ):
                    raise HarnessFailure(f"missing render-diff capture artifact: {stem}")
                raw_streams[side] = raw_path.read_bytes()
                normalized_streams[side] = stream_path.read_bytes()
                checkpoints_by_side[side] = json.loads(
                    checkpoint_path.read_text(encoding="utf-8")
                )
            pi_ids = [item["id"] for item in checkpoints_by_side["pi"]]
            cadr_ids = [item["id"] for item in checkpoints_by_side["cadr"]]
            if pi_ids != cadr_ids:
                raise HarnessFailure(
                    f"checkpoint mismatch for {scenario_id}/{dimension_id}: "
                    f"pi={pi_ids!r} cadr={cadr_ids!r}"
                )
            if args.tier == "full":
                visible_stem = f"{scenario_id}.{dimension_id}.pi.visible"
                visible_raw_path = capture_root / f"{visible_stem}.raw"
                visible_checkpoint_path = (
                    capture_root / f"{visible_stem}.checkpoints.json"
                )
                if not visible_raw_path.is_file() or not visible_checkpoint_path.is_file():
                    raise HarnessFailure(
                        f"missing instrumented visible-site capture: {visible_stem}"
                    )
                visible_raw = visible_raw_path.read_bytes()
                visible_checkpoints = json.loads(
                    visible_checkpoint_path.read_text(encoding="utf-8")
                )
                if [record["id"] for record in visible_checkpoints] != pi_ids:
                    raise HarnessFailure(
                        f"instrumented checkpoint mismatch for {scenario_id}/{dimension_id}"
                    )
                # A render call can begin before a checkpoint byte offset and finish
                # after it, so marker pairing is only sound over the complete PTY
                # stream. The scenario still identifies the exercised state family.
                visible_marker_streams[f"{scenario_id}/{dimension_id}"] = visible_raw
            previous = {"pi": 0, "cadr": 0}
            for index, checkpoint_id in enumerate(pi_ids):
                records = {
                    side: checkpoints_by_side[side][index] for side in ("pi", "cadr")
                }
                if any("normalizedOffset" not in record for record in records.values()):
                    raise HarnessFailure(
                        f"capture predates normalized checkpoint offsets: "
                        f"{scenario_id}/{dimension_id}/{checkpoint_id}"
                    )
                offsets = {
                    side: records[side]["normalizedOffset"] for side in ("pi", "cadr")
                }
                segments = {
                    side: normalized_streams[side][previous[side] : offsets[side]]
                    for side in ("pi", "cadr")
                }
                with tempfile.TemporaryDirectory(prefix="cadr-render-screen-") as temporary:
                    replay_root = Path(temporary)
                    screens = {
                        side: normalized_screen(
                            tmux_screen(
                                raw_streams[side][: records[side]["offset"]],
                                dimension["columns"],
                                dimension["rows"],
                                replay_root / side,
                            ),
                            side,
                        )
                        for side in ("pi", "cadr")
                    }
                key = f"{scenario_id}/{dimension_id}/{checkpoint_id}"
                pi_screens[key] = screens["pi"]
                for side in ("pi", "cadr"):
                    path = analysis_root / f"{scenario_id}.{dimension_id}.{checkpoint_id}.{side}.screen"
                    path.write_bytes(screens[side])
                raw_summary = raw_difference_summary(segments["pi"], segments["cadr"])
                screen_equal = screens["pi"] == screens["cadr"]
                text_geometry_equal = (
                    screen_text_and_geometry(screens["pi"])
                    == screen_text_and_geometry(screens["cadr"])
                )
                if raw_summary["equal"]:
                    automatic_disposition = "aligned"
                elif screen_equal:
                    automatic_disposition = "intentional-terminal-protocol"
                else:
                    automatic_disposition = "requires-disposition"
                results.append(
                    {
                        "key": key,
                        "scenario": scenario_id,
                        "dimension": dimension_id,
                        "checkpoint": checkpoint_id,
                        "raw": raw_summary,
                        "piScreenSha256": hashlib.sha256(screens["pi"]).hexdigest(),
                        "cadrScreenSha256": hashlib.sha256(screens["cadr"]).hexdigest(),
                        "screenEqual": screen_equal,
                        "textGeometryEqual": text_geometry_equal,
                        "automaticDisposition": automatic_disposition,
                        "adjudication": dispositions.get(key),
                    }
                )
                previous = offsets
    validate_result_adjudications(
        results, text_covering_disposition_classes(disposition_data)
    )
    required_keys = {
        result["key"]
        for result in results
        if result["automaticDisposition"] != "aligned"
    }
    missing = sorted(required_keys - dispositions.keys())
    stale = sorted(dispositions.keys() - required_keys)
    if missing:
        raise HarnessFailure(
            "render-diff differences lack dispositions: " + ", ".join(missing)
        )
    if stale:
        raise HarnessFailure(
            "render-diff dispositions no longer describe a difference: " + ", ".join(stale)
        )
    summary_path = analysis_root / "summary.json"
    summary_path.write_text(
        json.dumps(results, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    counts: dict[str, int] = {}
    for result in results:
        disposition = result["automaticDisposition"]
        counts[disposition] = counts.get(disposition, 0) + 1
    print(
        "render-diff analysis: "
        + " ".join(f"{name}={count}" for name, count in sorted(counts.items()))
        + f" adjudicated={len(dispositions)}"
        + f" summary={summary_path}"
    )
    if args.tier == "full":
        coverage_manifest = dict(manifest)
        coverage_manifest["scenarios"] = scenarios
        analyze_visible_string_coverage(
            visible_inventory,
            coverage_manifest,
            visible_marker_streams,
            args.visible_string_exemptions.resolve(),
            analysis_root,
        )
    else:
        print(
            "visible-string coverage: deferred to --tier full "
            f"inventory={len(visible_inventory['entries'])}"
        )
    return 0


def gate(args: argparse.Namespace) -> int:
    """Capture the complete real manifest, then apply the fail-closed analyzer."""
    manifest = load_manifest(args.manifest.resolve())
    cadr_cache = args.output.resolve() / ".cadr-cache"
    captures = 0
    scenarios = [
        scenario for scenario in manifest["scenarios"]
        if args.tier == "full" or scenario.get("tier", "core") == "core"
    ]
    instrumented_temporary: tempfile.TemporaryDirectory[str] | None = None
    instrumented_baseline: Path | None = None
    try:
        if args.tier == "full":
            baseline = ensure_baseline(
                args.pi_repo.resolve(),
                manifest["baselineCommit"],
                args.baseline_cache.resolve(),
            )
            instrumented_temporary = tempfile.TemporaryDirectory(
                prefix="cadr-render-visible-baseline-"
            )
            instrumented_baseline = prepare_instrumented_baseline(
                baseline,
                manifest["baselineCommit"],
                Path(instrumented_temporary.name) / "baseline",
            )
        for dimension in manifest["dimensions"]:
            for scenario in scenarios:
                capture_arguments = argparse.Namespace(
                    manifest=args.manifest,
                    pi_repo=args.pi_repo,
                    output=args.output,
                    baseline_cache=args.baseline_cache,
                    timeout=args.timeout,
                    scenario=scenario["id"],
                    dimension=dimension["id"],
                    side="both",
                    cadr_cache=cadr_cache,
                )
                capture(capture_arguments)
                if instrumented_baseline is not None:
                    visible_values = dict(vars(capture_arguments))
                    visible_values.update(
                        side="pi",
                        visible_sites=True,
                        baseline_override=instrumented_baseline,
                    )
                    visible_arguments = argparse.Namespace(**visible_values)
                    capture(visible_arguments)
                captures += 1
        if instrumented_baseline is not None:
            run_visible_string_construction_suite(
                instrumented_baseline,
                args.output.resolve(),
                args.timeout,
            )
    finally:
        if instrumented_temporary is not None:
            instrumented_temporary.cleanup()
    print(
        "render-diff gate: "
        f"tier={args.tier} "
        f"captured={captures}/{len(scenarios) * len(manifest['dimensions'])} "
        f"scenarios={len(scenarios)} dimensions={len(manifest['dimensions'])}"
    )
    return analyze(args)


def self_test(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest.resolve())
    if len(manifest["dimensions"]) < 2:
        raise HarnessFailure("manifest must retain narrow and wide dimensions")
    sample = b" \x1b[38;2;1;2;3mcolor\x1b[0m \n"
    with tempfile.TemporaryDirectory(prefix="cadr-render-diff-normalize-") as temporary:
        sandbox = Path(temporary)
        isolated = fixed_environment(sandbox, 12, 4, sandbox / "ready")
        if any(credential_environment_variable_p(key) for key in isolated):
            raise HarnessFailure("fixed environment retained a provider credential variable")
        fake_share = subprocess.run(
            ["gh", "gist", "create", "--public=false", "/tmp/render.html"],
            env=isolated,
            check=True,
            stdout=subprocess.PIPE,
            text=True,
        ).stdout.strip()
        if fake_share != "https://gist.github.com/render/render-gist-fixed":
            raise HarnessFailure("render-diff fake GitHub CLI contract drifted")
        if normalized(sample, "pi", sandbox) != sample:
            raise HarnessFailure("normalization altered whitespace or ANSI color bytes")
        pi_header = b"pi\x1b[0m\x1b[38;2;102;102;102m v0.83.0"
        cadr_header = b"cadr\x1b[0m\x1b[38;2;102;102;102m v0.2.0"
        expected_header = b"<PRODUCT>\x1b[0m\x1b[38;2;102;102;102m v<VERSION>"
        if normalize_fixed_values(pi_header) != expected_header:
            raise HarnessFailure("pi styled product header normalization drifted")
        if normalize_fixed_values(cadr_header) != expected_header:
            raise HarnessFailure("cadr styled product header normalization drifted")
        if normalize_fixed_values(b"\x1b]0;\xcf\x80 - work\x07") != normalize_fixed_values(
            b"\x1b]0;cadr - work\x07"
        ):
            raise HarnessFailure("terminal-title product normalization drifted")
        resume_id = b"To resume this session: cadr --session 019fcc98-34ce-7166-84e3-ee03d1bfb3b2"
        if not normalize_fixed_values(resume_id).endswith(b"--session <SESSION_ID>"):
            raise HarnessFailure("resume-session UUID normalization drifted")
        wrapped_resume_id = b"To resume this session: cadr --ses\nsion 019fcc98-34ce-7166-84e3-ee03d1bfb3b2"
        if not normalize_fixed_values(wrapped_resume_id).endswith(b"sion <SESSION_ID>"):
            raise HarnessFailure("wrapped resume-session UUID normalization drifted")
        baseline_output = b"Full output: /tmp/pi-bash-2ccded83dc83b1f8.log"
        cadr_output = b"Full output: /tmp/cadr-bash-3994869173-466576989544909805.log"
        if normalize_fixed_values(baseline_output) != normalize_fixed_values(cadr_output):
            raise HarnessFailure("bash-output path normalization drifted")
        unrelated_output = b"Full output: /tmp/custom-bash-2ccded83dc83b1f8.log"
        if normalize_fixed_values(unrelated_output) != unrelated_output:
            raise HarnessFailure("bash-output path normalization escaped its grammar")
        screen = tmux_screen(
            b"\x1b[2J\x1b[H\x1b[31mred\x1b[0m", 12, 4, sandbox / "tmux"
        )
        if b"red" not in screen or b"<CURSOR 3,0,1>" not in screen:
            raise HarnessFailure("tmux semantic replay lost text or cursor state")
        raw_path = b"/tmp/cadr-render-diff-fixed/pi00/workspace"
        path_screen = normalized_screen(
            tmux_screen(
                b"\x1b[2J\x1b[H" + raw_path,
                80,
                4,
                sandbox / "tmux-path",
            ),
            "pi",
        )
        expected_cursor = f"<CURSOR {len(raw_path)},0,1>".encode()
        if b"<CWD>" not in path_screen or expected_cursor not in path_screen:
            raise HarnessFailure(
                "screen normalization changed terminal replay geometry"
            )
    replay_roots = [args.output / "replay-1", args.output / "replay-2"]
    for replay_root in replay_roots:
        subprocess.run(
            [sys.executable, __file__, "capture", "--manifest", str(args.manifest),
             "--pi-repo", str(args.pi_repo), "--scenario", "conversation-content",
             "--dimension", "wide", "--output", str(replay_root),
             "--side", "both", "--baseline-cache", str(args.baseline_cache),
             "--timeout", str(args.timeout)],
            check=True,
        )
        raw_files = list(replay_root.glob("conversation-content.wide.*.raw"))
        if len(raw_files) != 4:
            raise HarnessFailure(
                f"expected four raw/normalized captures, found {len(raw_files)}"
            )
        for path in raw_files:
            if b"\x1b[" not in path.read_bytes():
                raise HarnessFailure(f"capture omitted ANSI bytes: {path}")
    raw_equal = compare_replays(
        manifest,
        find_scenario(manifest, "conversation-content"),
        find_dimension(manifest, "wide"),
        replay_roots,
    )
    print(
        "render-diff self-test: PASS "
        f"pi_raw_equal={str(raw_equal['pi']).lower()} "
        f"cadr_raw_equal={str(raw_equal['cadr']).lower()} semantic_equal=true"
    )
    return 0


def compare_replays(
    manifest: dict[str, Any],
    scenario: dict[str, Any],
    dimension: dict[str, Any],
    replay_roots: list[Path],
) -> dict[str, bool]:
    raw_equal: dict[str, bool] = {}
    for side in ("pi", "cadr"):
        stem = f"{scenario['id']}.{dimension['id']}.{side}"
        normalized_name = f"{stem}.normalized.raw"
        raw_equal[side] = (
            (replay_roots[0] / normalized_name).read_bytes()
            == (replay_roots[1] / normalized_name).read_bytes()
        )
        checkpoint_sets = [
            json.loads(
                (root / f"{stem}.checkpoints.json").read_text(encoding="utf-8")
            )
            for root in replay_roots
        ]
        if [item["id"] for item in checkpoint_sets[0]] != [
            item["id"] for item in checkpoint_sets[1]
        ]:
            raise HarnessFailure(f"self-replay checkpoint mismatch for {side}")
        raw_streams = [
            (root / f"{stem}.raw").read_bytes() for root in replay_roots
        ]
        for index, checkpoint in enumerate(checkpoint_sets[0]):
            screens = []
            for replay_index, root in enumerate(replay_roots):
                with tempfile.TemporaryDirectory(
                    prefix="cadr-render-replay-screen-"
                ) as temporary:
                    screens.append(
                        normalized_screen(
                            tmux_screen(
                                raw_streams[replay_index][
                                    : checkpoint_sets[replay_index][index]["offset"]
                                ],
                                dimension["columns"],
                                dimension["rows"],
                                Path(temporary) / side,
                            ),
                            side,
                        )
                    )
            if screens[0] != screens[1]:
                raise HarnessFailure(
                    f"semantic self-replay differs: {side}/{checkpoint['id']}"
                )
    return raw_equal


def replay_check(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest.resolve())
    scenario = find_scenario(manifest, args.scenario)
    dimension = find_dimension(manifest, args.dimension)
    replay_roots = [args.output / "replay-1", args.output / "replay-2"]
    for replay_root in replay_roots:
        subprocess.run(
            [
                sys.executable,
                __file__,
                "capture",
                "--manifest",
                str(args.manifest),
                "--pi-repo",
                str(args.pi_repo),
                "--scenario",
                args.scenario,
                "--dimension",
                args.dimension,
                "--output",
                str(replay_root),
                "--side",
                "both",
                "--baseline-cache",
                str(args.baseline_cache),
                "--timeout",
                str(args.timeout),
            ],
            check=True,
        )
    raw_equal = compare_replays(manifest, scenario, dimension, replay_roots)
    print(
        f"render-diff replay-check: PASS scenario={args.scenario} "
        f"dimension={args.dimension} pi_raw_equal={str(raw_equal['pi']).lower()} "
        f"cadr_raw_equal={str(raw_equal['cadr']).lower()} semantic_equal=true"
    )
    return 0


def inventory(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest.resolve())
    baseline = ensure_baseline(
        args.pi_repo.resolve(),
        manifest["baselineCommit"],
        args.baseline_cache.resolve(),
    )
    data = generate_visible_string_inventory(baseline, manifest["baselineCommit"])
    validate_visible_string_inventory(data, manifest["baselineCommit"])
    output = args.visible_string_inventory.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(
        "visible-string inventory: "
        f"sites={len(data['entries'])} "
        f"branches={sum(len(entry['branches']) for entry in data['entries'])} "
        f"output={output}"
    )
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)
    for name in ("capture", "self-test", "analyze", "replay-check", "gate", "inventory"):
        command = subparsers.add_parser(name)
        command.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
        command.add_argument("--pi-repo", type=Path, default=ROOT)
        command.add_argument("--output", type=Path, default=ROOT / ".tmp/render-diff")
        command.add_argument(
            "--baseline-cache",
            type=Path,
            default=Path("/tmp/cadr-render-diff-pi-74caa2649"),
        )
        command.add_argument("--timeout", type=float, default=60.0)
        command.add_argument(
            "--visible-string-inventory",
            type=Path,
            default=DEFAULT_VISIBLE_STRING_INVENTORY,
        )
        command.add_argument(
            "--visible-string-exemptions",
            type=Path,
            default=DEFAULT_VISIBLE_STRING_EXEMPTIONS,
        )
        if name == "capture":
            command.add_argument("--scenario", required=True)
            command.add_argument("--dimension", choices=("wide", "narrow"), required=True)
            command.add_argument("--side", choices=("pi", "cadr", "both"), default="both")
        if name == "replay-check":
            command.add_argument("--scenario", required=True)
            command.add_argument("--dimension", choices=("wide", "narrow"), required=True)
        if name in {"analyze", "gate"}:
            command.add_argument(
                "--tier", choices=("core", "full"), default="core"
            )
            command.add_argument(
                "--dispositions",
                type=Path,
                default=DEFAULT_DISPOSITIONS,
            )
            command.add_argument(
                "--analysis-output",
                type=Path,
                default=ROOT / ".tmp/render-diff-analysis",
            )
    return result


def main() -> int:
    args = parser().parse_args()
    if args.command in {"capture", "analyze", "gate", "self-test", "replay-check"}:
        sweep_stale_render_resources()
    if args.command == "capture":
        return capture(args)
    if args.command == "analyze":
        return analyze(args)
    if args.command == "gate":
        return gate(args)
    if args.command == "replay-check":
        return replay_check(args)
    if args.command == "inventory":
        return inventory(args)
    return self_test(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (HarnessFailure, subprocess.CalledProcessError) as error:
        print(f"render-diff: {error}", file=sys.stderr)
        raise SystemExit(2)
