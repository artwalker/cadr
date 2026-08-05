#!/usr/bin/env python3
"""Fail-closed Pi/Cadr JSONL and RPC event differential gate."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "test" / "fixtures" / "event-diff"
DEFAULT_BASELINE_COMMIT = "74caa2649f10ed71b4378ce69f5d9fbfd2466ca5"
REQUIRED_SCENARIOS = {
    "normal",
    "transient-retry",
    "deterministic-error",
    "abort",
    "manual-compaction",
    "summarization-transient-retry",
    "threshold-compaction",
    "overflow-compaction",
    "tool-failure",
    "tool-call-error-sidecar",
}
VALID_DISPOSITIONS = {"approved-difference", "baseline-bug", "cadr-bug"}


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def value_sha256(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def pointer_escape(value: str) -> str:
    return value.replace("~", "~0").replace("/", "~1")


def pointer_tokens(pointer: str) -> list[str]:
    if pointer == "":
        return []
    if not pointer.startswith("/"):
        raise ValueError(f"JSON pointer must start with '/': {pointer!r}")
    return [token.replace("~1", "/").replace("~0", "~") for token in pointer[1:].split("/")]


def replace_at_pointer(document: Any, pointer: str, replacement: Any) -> Any:
    tokens = pointer_tokens(pointer)
    if not tokens:
        return replacement
    target = document
    for token in tokens[:-1]:
        if isinstance(target, list):
            try:
                target = target[int(token)]
            except (ValueError, IndexError) as error:
                raise KeyError(pointer) from error
        elif isinstance(target, dict) and token in target:
            target = target[token]
        else:
            raise KeyError(pointer)
    leaf = tokens[-1]
    if isinstance(target, list):
        try:
            target[int(leaf)] = replacement
        except (ValueError, IndexError) as error:
            raise KeyError(pointer) from error
    elif isinstance(target, dict) and leaf in target:
        target[leaf] = replacement
    else:
        raise KeyError(pointer)
    return document


def value_at_pointer(document: Any, pointer: str) -> Any:
    target = document
    for token in pointer_tokens(pointer):
        if isinstance(target, list):
            try:
                target = target[int(token)]
            except (ValueError, IndexError) as error:
                raise KeyError(pointer) from error
        elif isinstance(target, dict) and token in target:
            target = target[token]
        else:
            raise KeyError(pointer)
    return target


def normalize_records(records: list[Any], rules: Iterable[dict[str, Any]]) -> tuple[list[Any], list[dict[str, Any]]]:
    normalized = copy.deepcopy(records)
    trace: list[dict[str, Any]] = []
    seen: set[str] = set()
    for rule in rules:
        pointer = rule.get("pointer")
        if not isinstance(pointer, str) or pointer in seen:
            raise ValueError(f"normalization pointer must be unique and exact: {pointer!r}")
        if "*" in pointer or "?" in pointer:
            raise ValueError(f"normalization pointer contains wildcard: {pointer!r}")
        seen.add(pointer)
        try:
            before = value_at_pointer(normalized, pointer)
        except KeyError as error:
            raise ValueError(f"normalization pointer does not exist: {pointer}") from error
        replacement = rule.get("replacement")
        replace_at_pointer(normalized, pointer, replacement)
        trace.append(
            {
                "pointer": pointer,
                "before_sha256": value_sha256(before),
                "after_sha256": value_sha256(replacement),
                "reason": rule.get("reason", "declared volatile field"),
            }
        )
    return normalized, trace


def _difference(pointer: str, kind: str, expected: Any, actual: Any) -> dict[str, Any]:
    first = pointer_tokens(pointer)[0] if pointer else "0"
    return {
        "ordinal": int(first) if first.isdigit() else 0,
        "pointer": pointer,
        "kind": kind,
        "expected_sha256": value_sha256(expected),
        "actual_sha256": value_sha256(actual),
        "expected": expected,
        "actual": actual,
    }


def compare_records(expected: list[Any], actual: list[Any]) -> list[dict[str, Any]]:
    differences: list[dict[str, Any]] = []

    def record_key(record: Any) -> tuple[Any, ...]:
        if not isinstance(record, dict):
            return (type(record).__name__,)
        event_type = record.get("type")
        if event_type == "message_update":
            nested = record.get("assistantMessageEvent")
            return (event_type, nested.get("type") if isinstance(nested, dict) else None)
        if event_type == "response":
            return (event_type, record.get("id"), record.get("command"))
        if event_type in {"compaction_start", "compaction_end", "compaction_error"}:
            return (event_type, record.get("reason"))
        return (event_type,)

    def aligned_pairs(left: list[Any], right: list[Any]) -> list[tuple[int | None, int | None]]:
        left_keys = [record_key(record) for record in left]
        right_keys = [record_key(record) for record in right]
        rows = len(left_keys) + 1
        columns = len(right_keys) + 1
        lengths = [[0] * columns for _ in range(rows)]
        for left_index in range(len(left_keys) - 1, -1, -1):
            for right_index in range(len(right_keys) - 1, -1, -1):
                if left_keys[left_index] == right_keys[right_index]:
                    lengths[left_index][right_index] = 1 + lengths[left_index + 1][right_index + 1]
                else:
                    lengths[left_index][right_index] = max(
                        lengths[left_index + 1][right_index], lengths[left_index][right_index + 1]
                    )
        pairs: list[tuple[int | None, int | None]] = []
        left_index = 0
        right_index = 0
        while left_index < len(left) and right_index < len(right):
            if left_keys[left_index] == right_keys[right_index]:
                pairs.append((left_index, right_index))
                left_index += 1
                right_index += 1
            elif lengths[left_index + 1][right_index] >= lengths[left_index][right_index + 1]:
                pairs.append((left_index, None))
                left_index += 1
            else:
                pairs.append((None, right_index))
                right_index += 1
        pairs.extend((index, None) for index in range(left_index, len(left)))
        pairs.extend((None, index) for index in range(right_index, len(right)))
        return pairs

    def visit(left: Any, right: Any, pointer: str) -> None:
        if (
            isinstance(left, (int, float))
            and not isinstance(left, bool)
            and isinstance(right, (int, float))
            and not isinstance(right, bool)
        ):
            if left != right:
                differences.append(_difference(pointer, "value-mismatch", left, right))
            return
        if type(left) is not type(right):
            differences.append(_difference(pointer, "type-mismatch", left, right))
            return
        if isinstance(left, dict):
            for key in sorted(set(left) | set(right)):
                child = f"{pointer}/{pointer_escape(key)}"
                if key not in left:
                    differences.append(_difference(child, "unexpected-field", None, right[key]))
                elif key not in right:
                    differences.append(_difference(child, "missing-field", left[key], None))
                else:
                    visit(left[key], right[key], child)
            return
        if isinstance(left, list) and pointer == "":
            for left_index, right_index in aligned_pairs(left, right):
                if left_index is None:
                    differences.append(
                        _difference(f"/actual/{right_index}", "unexpected-event", None, right[right_index])
                    )
                elif right_index is None:
                    differences.append(
                        _difference(f"/{left_index}", "missing-event", left[left_index], None)
                    )
                else:
                    visit(left[left_index], right[right_index], f"/{left_index}")
            return
        if isinstance(left, list):
            common = min(len(left), len(right))
            for index in range(common):
                visit(left[index], right[index], f"{pointer}/{index}")
            for index in range(common, len(left)):
                differences.append(_difference(f"{pointer}/{index}", "missing-item", left[index], None))
            for index in range(common, len(right)):
                differences.append(_difference(f"{pointer}/{index}", "unexpected-item", None, right[index]))
            return
        if left != right:
            differences.append(_difference(pointer, "value-mismatch", left, right))

    visit(expected, actual, "")
    return differences


def write_raw_artifact(
    artifact_root: Path, scenario: str, mode: str, side: str, payload: bytes
) -> dict[str, Any]:
    relative = Path(scenario) / mode / f"{side}.raw.jsonl"
    path = artifact_root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    return {
        "path": relative.as_posix(),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "bytes": len(payload),
    }


def parse_jsonl(payload: bytes, label: str) -> list[Any]:
    records: list[Any] = []
    for line_number, raw_line in enumerate(payload.splitlines(), 1):
        if not raw_line.strip():
            continue
        try:
            records.append(json.loads(raw_line))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ValueError(f"{label} line {line_number} is not JSON: {error}") from error
    return records


def validate_scenario_matrix(manifest: dict[str, Any]) -> None:
    if manifest.get("baselineCommit") != DEFAULT_BASELINE_COMMIT:
        raise ValueError("scenario manifest baselineCommit is not the fixed audited baseline")
    scenarios = manifest.get("scenarios")
    if not isinstance(scenarios, list):
        raise ValueError("scenario manifest must contain a scenarios array")
    names = [scenario.get("name") for scenario in scenarios if isinstance(scenario, dict)]
    if len(names) != len(set(names)):
        raise ValueError("scenario names must be unique")
    if set(names) != REQUIRED_SCENARIOS:
        missing = sorted(REQUIRED_SCENARIOS - set(names))
        extra = sorted(set(names) - REQUIRED_SCENARIOS)
        raise ValueError(f"scenario coverage mismatch: missing={missing} extra={extra}")
    for scenario in scenarios:
        if set(scenario.get("modes", [])) != {"json", "rpc"}:
            raise ValueError(f"scenario {scenario.get('name')} must cover json and rpc")
        if not isinstance(scenario.get("prompt"), str):
            raise ValueError(f"scenario {scenario.get('name')} is missing a prompt")


def validate_normalization_rules(
    rules_document: dict[str, Any], manifest: dict[str, Any]
) -> None:
    rules = rules_document.get("rules")
    if not isinstance(rules, list):
        raise ValueError("normalization rules must contain a rules array")
    matrix = {
        scenario["name"]: set(scenario.get("modes", []))
        for scenario in manifest["scenarios"]
    }
    seen: set[tuple[str, str, str, str]] = set()
    for index, rule in enumerate(rules):
        if not isinstance(rule, dict):
            raise ValueError(f"normalization rule {index} must be an object")
        scenario = rule.get("scenario")
        mode = rule.get("mode")
        side = rule.get("side")
        pointer = rule.get("pointer")
        if scenario not in matrix:
            raise ValueError(
                f"normalization rule {index} has unknown scenario: {scenario!r}"
            )
        if mode not in matrix[scenario]:
            raise ValueError(
                f"normalization rule {index} has unknown mode for {scenario}: {mode!r}"
            )
        if side not in {"pi", "cadr"}:
            raise ValueError(
                f"normalization rule {index} has unknown side: {side!r}"
            )
        if not isinstance(pointer, str) or not pointer.startswith("/"):
            raise ValueError(
                f"normalization rule {index} has invalid pointer: {pointer!r}"
            )
        if "*" in pointer or "?" in pointer:
            raise ValueError(
                f"normalization rule {index} pointer contains wildcard: {pointer!r}"
            )
        if not isinstance(rule.get("reason"), str) or not rule["reason"].strip():
            raise ValueError(f"normalization rule {index} reason must be non-empty")
        key = (scenario, mode, side, pointer)
        if key in seen:
            raise ValueError(f"duplicate normalization rule coordinate: {key}")
        seen.add(key)


def disposition_key(entry: dict[str, Any]) -> tuple[Any, ...]:
    return (
        entry.get("scenario"),
        entry.get("mode"),
        entry.get("ordinal"),
        entry.get("pointer"),
        entry.get("kind"),
        entry.get("expected_sha256"),
        entry.get("actual_sha256"),
    )


def apply_dispositions(
    differences: list[dict[str, Any]], dispositions: dict[str, Any], baseline_commit: str
) -> dict[str, list[dict[str, Any]]]:
    if dispositions.get("baselineCommit") != baseline_commit:
        raise ValueError("disposition baselineCommit does not match the gate baseline")
    entries = dispositions.get("entries")
    if not isinstance(entries, list):
        raise ValueError("dispositions must contain an entries array")
    indexed: dict[tuple[Any, ...], dict[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError("disposition entry must be an object")
        for field in ("scenario", "mode", "pointer", "kind", "expected_sha256", "actual_sha256"):
            value = entry.get(field)
            if isinstance(value, str) and ("*" in value or "?" in value):
                raise ValueError(f"disposition {field} contains wildcard: {value!r}")
        if entry.get("disposition") not in VALID_DISPOSITIONS:
            raise ValueError(f"invalid disposition: {entry.get('disposition')!r}")
        if not isinstance(entry.get("reason"), str) or not entry["reason"].strip():
            raise ValueError("disposition reason must be non-empty")
        key = disposition_key(entry)
        if key in indexed:
            raise ValueError(f"duplicate disposition: {key}")
        indexed[key] = entry

    resolved: list[dict[str, Any]] = []
    unresolved: list[dict[str, Any]] = []
    matched: set[tuple[Any, ...]] = set()
    for difference in differences:
        key = disposition_key(difference)
        entry = indexed.get(key)
        if entry is None:
            unresolved.append(difference)
        else:
            resolved.append({"difference": difference, "disposition": entry})
            matched.add(key)
    stale = [entry for key, entry in indexed.items() if key not in matched]
    blocking = [
        entry
        for entry in resolved
        if entry["disposition"].get("disposition") != "approved-difference"
    ]
    return {"resolved": resolved, "unresolved": unresolved, "stale": stale, "blocking": blocking}


def selected_rules(
    rules_document: dict[str, Any], scenario: str, mode: str, side: str
) -> list[dict[str, Any]]:
    selected = []
    for rule in rules_document.get("rules", []):
        if (
            rule.get("scenario") == scenario
            and rule.get("mode") == mode
            and rule.get("side") == side
        ):
            selected.append(
                {
                    "pointer": rule.get("pointer"),
                    "replacement": rule.get("replacement"),
                    "reason": rule.get("reason"),
                }
            )
    return selected


def run_checked(command: list[str], *, cwd: Path, env: dict[str, str], stdin: bytes | None = None) -> bytes:
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        input=stdin,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        stderr = result.stderr.decode("utf-8", "replace")
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(command)}\n{stderr}")
    if result.stderr:
        stderr = result.stderr.decode("utf-8", "replace")
        raise RuntimeError(f"driver leaked stderr: {' '.join(command)}\n{stderr}")
    return result.stdout


class DriverInvocation:
    def __init__(self, command: list[str], cwd: Path, env: dict[str, str]) -> None:
        self.command = command
        self.cwd = cwd
        self.env = env


def make_invocation(
    side: str,
    baseline_repo: Path,
    manifest_path: Path,
    scenario: str,
    mode: str,
    run_root: Path,
) -> DriverInvocation:
    cwd = run_root / "shared" / scenario / mode / "cwd"
    agent_dir = run_root / side / scenario / mode / "agent"
    session_dir = run_root / side / scenario / mode / "sessions"
    sidecar = run_root / side / scenario / f"{mode}-sidecar.json"
    for directory in (cwd, agent_dir, session_dir):
        directory.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.update(
        {
            "HOME": str(run_root / side / "home"),
            "PI_OFFLINE": "1",
            "CADR_OFFLINE": "1",
            "EVENT_DIFF_SIDECAR": str(sidecar),
        }
    )
    Path(env["HOME"]).mkdir(parents=True, exist_ok=True)
    if side == "pi":
        package_dir = baseline_repo / "packages" / "coding-agent"
        driver = package_dir / ".event-diff-driver.ts"
        shutil.copyfile(FIXTURES / "pi-driver.ts", driver)
        command = [
            str(baseline_repo / "node_modules" / ".bin" / "tsx"),
            str(driver),
            str(manifest_path),
            scenario,
            mode,
            str(cwd),
            str(agent_dir),
            str(session_dir),
            str(sidecar),
        ]
        return DriverInvocation(command, package_dir, env)
    quicklisp = os.environ.get("QUICKLISP_SETUP", str(Path.home() / "quicklisp" / "setup.lisp"))
    command = [
        os.environ.get("SBCL", "sbcl"),
        "--noinform",
        "--disable-debugger",
        "--script",
        str(FIXTURES / "cadr-driver.lisp"),
        str(ROOT),
        quicklisp,
        str(manifest_path),
        scenario,
        mode,
        str(cwd),
        str(agent_dir),
        str(session_dir),
        str(sidecar),
    ]
    return DriverInvocation(command, ROOT, env)


def run_rpc(invocation: DriverInvocation, scenario: dict[str, Any]) -> bytes:
    process = subprocess.Popen(
        invocation.command,
        cwd=invocation.cwd,
        env=invocation.env,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
    )
    assert process.stdin is not None
    assert process.stdout is not None
    assert process.stderr is not None
    output: list[bytes] = []
    stderr_chunks: list[bytes] = []
    reader_error: list[BaseException] = []
    done = threading.Event()

    def stderr_reader() -> None:
        while True:
            chunk = process.stderr.read(4096)
            if not chunk:
                return
            stderr_chunks.append(chunk)

    stderr_thread = threading.Thread(target=stderr_reader, daemon=True)
    stderr_thread.start()

    try:
        command_type = "compact" if scenario.get("action") == "manual-compaction" else "prompt"
        command: dict[str, Any] = {"id": "event-command", "type": command_type}
        if command_type == "prompt":
            command["message"] = scenario["prompt"]
        process.stdin.write(canonical_bytes(command) + b"\n")
        process.stdin.flush()
        abort_sent = False
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            line = process.stdout.readline()
            if not line:
                break
            output.append(line)
            record = json.loads(line)
            if scenario.get("action") == "abort" and not abort_sent:
                update = record.get("assistantMessageEvent") if isinstance(record, dict) else None
                if isinstance(update, dict) and update.get("type") == "text_delta":
                    process.stdin.write(canonical_bytes({"id": "abort-command", "type": "abort"}) + b"\n")
                    process.stdin.flush()
                    abort_sent = True
            if command_type == "compact":
                if record.get("type") == "response" and record.get("id") == "event-command":
                    done.set()
                    break
            elif record.get("type") == "agent_settled":
                done.set()
                break
        if not done.is_set():
            raise RuntimeError(f"RPC driver did not reach a protocol completion for {scenario['name']}")
        process.stdin.close()
        process.stdin = None
        remainder = process.stdout.read()
        if remainder:
            output.append(remainder)
        return_code = process.wait(timeout=15)
        stderr_thread.join(timeout=2)
        if return_code != 0:
            raise RuntimeError(
                f"RPC driver failed ({return_code}): {b''.join(stderr_chunks).decode('utf-8', 'replace')}"
            )
        if stderr_chunks:
            raise RuntimeError(f"RPC driver leaked stderr: {b''.join(stderr_chunks).decode('utf-8', 'replace')}")
        return b"".join(output)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


def capture_side(
    side: str,
    baseline_repo: Path,
    manifest_path: Path,
    scenario: dict[str, Any],
    mode: str,
    run_root: Path,
) -> tuple[bytes, Any]:
    invocation = make_invocation(side, baseline_repo, manifest_path, scenario["name"], mode, run_root)
    if mode == "rpc":
        payload = run_rpc(invocation, scenario)
    else:
        payload = run_checked(invocation.command, cwd=invocation.cwd, env=invocation.env)
    sidecar_path = Path(invocation.env["EVENT_DIFF_SIDECAR"])
    sidecar = json.loads(sidecar_path.read_text()) if sidecar_path.exists() else {"toolCallErrorHooks": 0}
    return payload, sidecar


def execute_gate(arguments: argparse.Namespace) -> int:
    manifest_path = arguments.manifest.resolve()
    manifest = json.loads(manifest_path.read_text())
    validate_scenario_matrix(manifest)
    rules = json.loads(arguments.normalization_rules.read_text())
    validate_normalization_rules(rules, manifest)
    dispositions = json.loads(arguments.dispositions.read_text())
    baseline_repo = arguments.baseline_repo.resolve()
    marker = baseline_repo / ".goal15-render-baseline"
    if (baseline_repo / ".git").exists():
        actual_commit = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=baseline_repo, text=True
        ).strip()
    elif marker.is_file():
        actual_commit = marker.read_text().strip()
    else:
        raise ValueError("baseline checkout has neither Git metadata nor an immutable commit marker")
    if actual_commit != manifest["baselineCommit"]:
        raise ValueError(
            f"baseline checkout is {actual_commit}, expected {manifest['baselineCommit']}"
        )

    selected_names = set(arguments.scenario or REQUIRED_SCENARIOS)
    selected_modes = set(arguments.mode or ("json", "rpc"))
    artifact_root = arguments.artifacts.resolve()
    artifact_root.mkdir(parents=True, exist_ok=True)
    raw_manifest: list[dict[str, Any]] = []
    all_differences: list[dict[str, Any]] = []
    sidecars: list[dict[str, Any]] = []

    with tempfile.TemporaryDirectory(prefix="cadr-event-diff-") as temp_dir:
        run_root = Path(temp_dir)
        for scenario in manifest["scenarios"]:
            name = scenario["name"]
            if name not in selected_names:
                continue
            for mode in scenario["modes"]:
                if mode not in selected_modes:
                    continue
                captures: dict[str, tuple[bytes, Any]] = {}
                for side in ("pi", "cadr"):
                    captures[side] = capture_side(
                        side, baseline_repo, manifest_path, scenario, mode, run_root
                    )
                    raw_manifest.append(
                        {
                            "scenario": name,
                            "mode": mode,
                            "side": side,
                            **write_raw_artifact(artifact_root, name, mode, side, captures[side][0]),
                        }
                    )
                    sidecars.append(
                        {
                            "scenario": name,
                            "mode": mode,
                            "side": side,
                            "value": captures[side][1],
                        }
                    )

                normalized: dict[str, list[Any]] = {}
                traces: dict[str, list[dict[str, Any]]] = {}
                for side in ("pi", "cadr"):
                    records = parse_jsonl(captures[side][0], f"{name}/{mode}/{side}")
                    normalized[side], traces[side] = normalize_records(
                        records, selected_rules(rules, name, mode, side)
                    )
                    output_dir = artifact_root / name / mode
                    (output_dir / f"{side}.normalized.json").write_text(
                        json.dumps(normalized[side], ensure_ascii=False, indent=2) + "\n"
                    )
                    (output_dir / f"{side}.normalization-trace.json").write_text(
                        json.dumps(traces[side], ensure_ascii=False, indent=2) + "\n"
                    )
                differences = compare_records(normalized["pi"], normalized["cadr"])
                for difference in differences:
                    difference["scenario"] = name
                    difference["mode"] = mode
                all_differences.extend(differences)
                (artifact_root / name / mode / "differences.json").write_text(
                    json.dumps(differences, ensure_ascii=False, indent=2) + "\n"
                )

    sidecar_differences: list[dict[str, Any]] = []
    for record in sidecars:
        if record["scenario"] != "tool-call-error-sidecar":
            continue
        expected = {"toolCallErrorHooks": 0}
        if record["side"] == "cadr":
            expected = {"toolCallErrorHooks": 1}
        if record["value"] != expected:
            sidecar_differences.append(
                {
                    "scenario": record["scenario"],
                    "mode": record["mode"],
                    "ordinal": 0,
                    "pointer": "/sidecar/toolCallErrorHooks",
                    "kind": "sidecar-contract-mismatch",
                    "expected_sha256": value_sha256(expected),
                    "actual_sha256": value_sha256(record["value"]),
                    "expected": expected,
                    "actual": record["value"],
                }
            )
    all_differences.extend(sidecar_differences)
    disposition_result = apply_dispositions(
        all_differences, dispositions, manifest["baselineCommit"]
    )
    report = {
        "baselineCommit": manifest["baselineCommit"],
        "rawArtifacts": raw_manifest,
        "sidecars": sidecars,
        "differences": all_differences,
        **disposition_result,
    }
    (artifact_root / "report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    )
    print(
        "event differential: "
        f"{len(raw_manifest)} raw artifacts, "
        f"{len(all_differences)} differences, "
        f"{len(disposition_result['resolved'])} resolved, "
        f"{len(disposition_result['unresolved'])} unresolved, "
        f"{len(disposition_result['stale'])} stale dispositions, "
        f"{len(disposition_result['blocking'])} blocking dispositions"
    )
    return (
        0
        if not disposition_result["unresolved"]
        and not disposition_result["stale"]
        and not disposition_result["blocking"]
        else 1
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--baseline-repo",
        type=Path,
        default=Path("/tmp/cadr-render-diff-pi-74caa2649"),
    )
    parser.add_argument("--manifest", type=Path, default=FIXTURES / "scenarios.json")
    parser.add_argument(
        "--normalization-rules", type=Path, default=FIXTURES / "normalization-rules.json"
    )
    parser.add_argument("--dispositions", type=Path, default=FIXTURES / "dispositions.json")
    parser.add_argument("--artifacts", type=Path, default=ROOT / ".tmp" / "event-diff")
    parser.add_argument("--scenario", action="append", choices=sorted(REQUIRED_SCENARIOS))
    parser.add_argument("--mode", action="append", choices=("json", "rpc"))
    return parser.parse_args()


def main() -> int:
    try:
        return execute_gate(parse_args())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"event differential gate failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
