#!/usr/bin/env python3
"""Run byte-exact tool-result parity against the fixed pi baseline."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "test/fixtures/tool-result-diff"
EXPECTED_BASELINE = "74caa2649f10ed71b4378ce69f5d9fbfd2466ca5"
EXPECTED_TOOLS = ["read", "bash", "edit", "write", "grep", "find", "ls"]
REQUIRED_FAILURE_CONTRACTS = {
    "path-not-found",
    "permission-denied",
    "nonzero-exit",
    "timeout",
    "output-over-limit",
    "invalid-arguments",
}
PLACEHOLDER = "<FULL_OUTPUT_PATH>"
NOISE_MARKERS = (b"Broken pipe", b"EPIPE", b"write error")


class GateFailure(RuntimeError):
    pass


def _b64encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _b64decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def text_block(text: str) -> dict[str, str]:
    return {"type": "text", "utf8Base64": _b64encode(text.encode("utf-8"))}


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise GateFailure(f"cannot read tool-result manifest {path}: {error}") from error
    if manifest.get("baselineCommit") != EXPECTED_BASELINE:
        raise GateFailure("tool-result manifest baseline commit drift")
    if manifest.get("builtinTools") != EXPECTED_TOOLS:
        raise GateFailure("tool-result manifest builtin tool set drift")
    scenarios = manifest.get("scenarios")
    if not isinstance(scenarios, list) or not scenarios:
        raise GateFailure("tool-result manifest has no scenarios")
    seen: set[str] = set()
    coverage: set[tuple[str, str]] = set()
    for case in scenarios:
        if not isinstance(case, dict):
            raise GateFailure("tool-result manifest scenario is not an object")
        scenario_id = case.get("id")
        tool = case.get("tool")
        outcome = case.get("outcome")
        if not isinstance(scenario_id, str) or not scenario_id:
            raise GateFailure("tool-result manifest scenario lacks id")
        if scenario_id in seen:
            raise GateFailure(f"duplicate tool-result scenario: {scenario_id}")
        seen.add(scenario_id)
        if tool not in EXPECTED_TOOLS or outcome not in ("success", "failure"):
            raise GateFailure(f"invalid tool-result scenario classification: {scenario_id}")
        if not isinstance(case.get("arguments"), dict):
            raise GateFailure(f"tool-result scenario lacks arguments: {scenario_id}")
        coverage.add((tool, outcome))
    missing = [
        f"{tool}/{outcome}"
        for tool in EXPECTED_TOOLS
        for outcome in ("success", "failure")
        if (tool, outcome) not in coverage
    ]
    if missing:
        raise GateFailure(f"tool-result scenario coverage missing: {', '.join(missing)}")
    broken_pipe = [case for case in scenarios if case.get("contract") == "broken-pipe"]
    if len(broken_pipe) != 1 or broken_pipe[0]["tool"] != "bash":
        raise GateFailure("tool-result manifest must contain one bash broken-pipe scenario")
    contracts = {
        case.get("contract")
        for case in scenarios
        if isinstance(case.get("contract"), str)
    }
    missing_contracts = sorted(REQUIRED_FAILURE_CONTRACTS - contracts)
    if missing_contracts:
        raise GateFailure(
            "tool-result failure contracts missing: " + ", ".join(missing_contracts)
        )
    return manifest


def _typed_path_sha(path_text: str, side: str, scenario_id: str) -> str:
    path = Path(path_text)
    if not path.is_file():
        raise GateFailure(
            f"{side}/{scenario_id}: typed fullOutputPath does not name a file: {path_text}"
        )
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_result_file(
    path: Path, scenarios: list[dict[str, Any]], side: str
) -> dict[str, dict[str, Any]]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise GateFailure(f"cannot read {side} result file {path}: {error}") from error
    results = payload.get("results")
    if not isinstance(results, list):
        raise GateFailure(f"{side} result matrix is not an array")
    indexed: dict[str, dict[str, Any]] = {}
    for result in results:
        scenario_id = result.get("scenarioId") if isinstance(result, dict) else None
        if not isinstance(scenario_id, str):
            raise GateFailure(f"{side} result matrix contains an invalid row")
        if scenario_id in indexed:
            raise GateFailure(f"{side} result matrix contains duplicate {scenario_id}")
        typed = result.get("typedFullOutputPath")
        if typed is not None:
            if not isinstance(typed, str) or not typed:
                raise GateFailure(f"{side}/{scenario_id}: invalid typed fullOutputPath")
            actual_sha = _typed_path_sha(typed, side, scenario_id)
            recorded_sha = result.get("typedFullOutputSha256")
            if recorded_sha != actual_sha:
                raise GateFailure(
                    f"{side}/{scenario_id}: typed fullOutputPath SHA mismatch: "
                    f"recorded {recorded_sha!r}, actual {actual_sha}"
                )
        indexed[scenario_id] = result
    expected = [case["id"] for case in scenarios]
    if list(indexed) != expected:
        raise GateFailure(
            f"{side} result matrix mismatch: expected {expected}, got {list(indexed)}"
        )
    return indexed


def normalize_result(raw: dict[str, Any]) -> dict[str, Any]:
    result = json.loads(json.dumps(raw))
    typed_path = result.get("typedFullOutputPath")
    if typed_path is None:
        return result
    if not isinstance(typed_path, str) or not typed_path:
        raise GateFailure("typed fullOutputPath is not a non-empty string")
    needle = typed_path.encode("utf-8")
    replacements = 0
    for block in result.get("content", []):
        if block.get("type") != "text":
            continue
        data = _b64decode(block["utf8Base64"])
        count = data.count(needle)
        replacements += count
        if count:
            block["utf8Base64"] = _b64encode(data.replace(needle, PLACEHOLDER.encode()))
    if replacements != 1:
        raise GateFailure(
            f"typed fullOutputPath must occur exactly once in text content, got {replacements}"
        )
    result["typedFullOutputPath"] = PLACEHOLDER
    return result


def _canonical_result(raw: dict[str, Any]) -> dict[str, Any]:
    allowed = {
        "isError": raw.get("isError"),
        "content": raw.get("content"),
    }
    if "typedFullOutputPath" in raw:
        allowed["typedFullOutputPath"] = raw["typedFullOutputPath"]
        allowed["typedFullOutputSha256"] = raw.get("typedFullOutputSha256")
    return allowed


def compare_result(
    scenario_id: str, pi_raw: dict[str, Any], cadr_raw: dict[str, Any]
) -> list[str]:
    pi = _canonical_result(normalize_result(pi_raw))
    cadr = _canonical_result(normalize_result(cadr_raw))
    differences: list[str] = []
    if pi.get("isError") != cadr.get("isError"):
        differences.append(
            f"{scenario_id}: isError pi={pi.get('isError')!r} cadr={cadr.get('isError')!r}"
        )
    if pi.get("content") != cadr.get("content"):
        differences.append(f"{scenario_id}: content blocks differ byte-for-byte")
    if pi.get("typedFullOutputPath") != cadr.get("typedFullOutputPath"):
        differences.append(f"{scenario_id}: typed fullOutputPath presence differs")
    if pi.get("typedFullOutputSha256") != cadr.get("typedFullOutputSha256"):
        differences.append(f"{scenario_id}: full output bytes differ")
    return differences


def validate_scenario_contract(
    scenario: dict[str, Any], pi_result: dict[str, Any], cadr_result: dict[str, Any]
) -> None:
    expected_error = scenario.get("outcome") == "failure"
    for side, result in (("pi", pi_result), ("cadr", cadr_result)):
        if result.get("isError") is not expected_error:
            raise GateFailure(
                f"{side}/{scenario['id']}: expected isError={expected_error}, "
                f"got {result.get('isError')!r}"
            )
    if scenario.get("contract") != "broken-pipe":
        return
    for side, result in (("pi", pi_result), ("cadr", cadr_result)):
        text = b"".join(
            _b64decode(block["utf8Base64"])
            for block in result.get("content", [])
            if block.get("type") == "text"
        )
        marker = next((entry for entry in NOISE_MARKERS if entry.lower() in text.lower()), None)
        if marker is not None:
            raise GateFailure(
                f"{side}/{scenario['id']}: broken-pipe noise leaked: {marker.decode()}; "
                f"result={text.decode('utf-8', 'backslashreplace')!r}"
            )


def _safe_relative(path_text: str) -> Path:
    path = Path(path_text)
    if path.is_absolute() or ".." in path.parts:
        raise GateFailure(f"unsafe fixture path: {path_text}")
    return path


def _write_fixture_file(path: Path, spec: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if "base64" in spec:
        data = base64.b64decode(spec["base64"])
    else:
        data = spec.get("text", "").encode("utf-8")
    path.write_bytes(data)
    path.chmod(int(spec.get("mode", "0666"), 8))


def materialize_workspace(root: Path, scenarios: list[dict[str, Any]]) -> None:
    root.mkdir(parents=True, mode=0o777, exist_ok=True)
    root.chmod(0o777)
    expected = {scenario["id"] for scenario in scenarios}
    for child in root.iterdir():
        if child.name not in expected:
            if child.is_dir() and not child.is_symlink():
                shutil.rmtree(child)
            else:
                child.unlink()
    for scenario in scenarios:
        cwd = root / scenario["id"]
        if cwd.exists() and (not cwd.is_dir() or cwd.is_symlink()):
            cwd.unlink()
        cwd.mkdir(mode=0o777, exist_ok=True)
        cwd.chmod(0o777)
        for child in cwd.iterdir():
            if child.is_dir() and not child.is_symlink():
                shutil.rmtree(child)
            else:
                child.unlink()
        setup = scenario.get("setup", {})
        for directory in setup.get("directories", []):
            target = cwd / _safe_relative(directory["path"])
            target.mkdir(parents=True, exist_ok=True)
            target.chmod(int(directory.get("mode", "0777"), 8))
        for file_spec in setup.get("files", []):
            _write_fixture_file(cwd / _safe_relative(file_spec["path"]), file_spec)


def _fixed_environment(home: Path, private_bin: Path) -> dict[str, str]:
    home.mkdir(parents=True, exist_ok=True)
    home.chmod(0o777)
    private_bin.mkdir(parents=True, exist_ok=True)
    node = shutil.which("node")
    sbcl = shutil.which("sbcl")
    if node is None or sbcl is None:
        raise GateFailure("node and sbcl are required for the differential gate")
    for name, source in {
        "node": Path(node),
        "sbcl": Path(sbcl),
        "bash": Path("/usr/bin/bash"),
        "setsid": Path("/usr/bin/setsid"),
        "rg": Path("/usr/bin/rg"),
        "fd": Path("/usr/bin/fdfind"),
        "grep": Path("/usr/bin/grep"),
        "head": Path("/usr/bin/head"),
        "sleep": Path("/usr/bin/sleep"),
        "yes": Path("/usr/bin/yes"),
        "seq": Path("/usr/bin/seq"),
        "tr": Path("/usr/bin/tr"),
        "cat": Path("/usr/bin/cat"),
        "rm": Path("/usr/bin/rm"),
    }.items():
        if not source.exists():
            raise GateFailure(f"required fixed tool is unavailable: {source}")
        link = private_bin / name
        if not link.exists():
            link.symlink_to(source)
    # ripgrep emits matches in traversal-completion order when it uses its
    # default worker pool.  That order is intentionally unspecified, so two
    # consecutive executions over identical files can disagree even when both
    # implementations invoke the same binary with the same arguments.  A
    # one-worker config removes scheduler order from this byte-exact oracle;
    # product arguments still remain authoritative and are compared unchanged.
    ripgrep_config = home / "ripgrep.conf"
    ripgrep_config.write_text("--threads=1\n", encoding="ascii")
    env = {
        "HOME": str(home),
        "TMPDIR": str(home / "tmp"),
        "PATH": str(private_bin),
        "SHELL": "/bin/bash",
        "LC_ALL": "C.UTF-8",
        "LANG": "C.UTF-8",
        "TZ": "UTC",
        "TERM": "xterm-256color",
        "COLUMNS": "80",
        "LINES": "24",
        "PI_OFFLINE": "1",
        "RIPGREP_CONFIG_PATH": str(ripgrep_config),
    }
    (home / "tmp").mkdir(mode=0o777)
    (home / "tmp").chmod(0o777)
    return env


def _run(
    command: list[str], env: dict[str, str], timeout: float, label: str
) -> None:
    completed = subprocess.run(
        command,
        cwd=ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        umask=0o022,
        check=False,
    )
    if completed.returncode != 0:
        output = completed.stdout.decode("utf-8", "replace")
        raise GateFailure(f"{label} driver failed ({completed.returncode}):\n{output}")


def validate_baseline(baseline: Path) -> None:
    head = subprocess.run(
        ["git", "-C", str(baseline), "rev-parse", "HEAD"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if head.returncode == 0 and head.stdout.strip() == EXPECTED_BASELINE:
        return
    marker = baseline / ".goal15-render-baseline"
    if marker.is_file() and marker.read_text(encoding="ascii").strip() == EXPECTED_BASELINE:
        return
    raise GateFailure(f"baseline checkout is not {EXPECTED_BASELINE}: {baseline}")


def run_pi(
    baseline: Path,
    manifest_path: Path,
    workspace: Path,
    output: Path,
    env: dict[str, str],
    timeout: float,
) -> None:
    validate_baseline(baseline)
    tsx = baseline / "node_modules/.bin/tsx"
    if not tsx.exists():
        raise GateFailure(f"fixed baseline dependencies are unavailable: {tsx}")
    stage = output.parent / "pi-stage"
    stage.mkdir(mode=0o755)
    driver = stage / "pi-driver.ts"
    shutil.copyfile(FIXTURES / "pi-driver.ts", driver)
    (stage / "package.json").symlink_to(baseline / "package.json")
    (stage / "tsconfig.json").symlink_to(baseline / "tsconfig.json")
    (stage / "tsconfig.base.json").symlink_to(baseline / "tsconfig.base.json")
    (stage / "packages").symlink_to(baseline / "packages", target_is_directory=True)
    (stage / "node_modules").symlink_to(
        baseline / "node_modules", target_is_directory=True
    )
    _run(
        [
            str(tsx),
            "--tsconfig",
            str(stage / "tsconfig.json"),
            str(driver),
            str(baseline),
            str(manifest_path),
            str(workspace),
            str(output),
        ],
        env,
        timeout,
        "pi",
    )


def run_cadr(
    manifest_path: Path,
    workspace: Path,
    output: Path,
    env: dict[str, str],
    timeout: float,
) -> None:
    quicklisp = os.environ.get("QUICKLISP_SETUP", "/root/quicklisp/setup.lisp")
    driver = FIXTURES / "cadr-driver.lisp"
    _run(
        [
            "sbcl",
            "--noinform",
            "--disable-debugger",
            "--script",
            str(driver),
            str(ROOT),
            quicklisp,
            str(manifest_path),
            str(workspace),
            str(output),
        ],
        env,
        timeout,
        "cadr",
    )


def gate(arguments: argparse.Namespace) -> int:
    manifest_path = arguments.manifest.resolve()
    manifest = load_manifest(manifest_path)
    scenarios = manifest["scenarios"]
    baseline = arguments.baseline.resolve()
    with tempfile.TemporaryDirectory(prefix="cadr-tool-result-diff-") as temporary:
        temp = Path(temporary)
        os.chmod(temp, 0o755)
        workspace = temp / "workspace"
        output_directory = temp / "output"
        output_directory.mkdir(mode=0o777)
        output_directory.chmod(0o777)
        home = temp / "home"
        private_bin = temp / "bin"
        env = _fixed_environment(home, private_bin)
        pi_output = output_directory / "pi.json"
        cadr_output = output_directory / "cadr.json"

        materialize_workspace(workspace, scenarios)
        run_pi(baseline, manifest_path, workspace, pi_output, env, arguments.timeout)
        pi_results = load_result_file(pi_output, scenarios, "pi")

        materialize_workspace(workspace, scenarios)
        run_cadr(manifest_path, workspace, cadr_output, env, arguments.timeout)
        cadr_results = load_result_file(cadr_output, scenarios, "cadr")

        if arguments.artifacts is not None:
            artifacts = arguments.artifacts.resolve()
            artifacts.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(pi_output, artifacts / "pi.json")
            shutil.copyfile(cadr_output, artifacts / "cadr.json")

        differences: list[str] = []
        for scenario in scenarios:
            scenario_id = scenario["id"]
            try:
                validate_scenario_contract(
                    scenario, pi_results[scenario_id], cadr_results[scenario_id]
                )
            except GateFailure as error:
                differences.append(f"{scenario_id}: contract failure: {error}")
            differences.extend(
                compare_result(
                    scenario_id,
                    pi_results[scenario_id],
                    cadr_results[scenario_id],
                )
            )
        if differences:
            failed = {difference.split(":", 1)[0] for difference in differences}
            raise GateFailure(
                f"{len(scenarios)} scenarios, {len(scenarios) - len(failed)} pass, "
                f"{len(failed)} fail:\n" + "\n".join(differences)
            )
    print(
        f"Tool-result differential: {len(scenarios)} scenarios, "
        f"{len(scenarios)} pass, 0 fail; baseline {EXPECTED_BASELINE[:10]}"
    )
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument(
        "--manifest",
        type=Path,
        default=FIXTURES / "scenarios.json",
    )
    result.add_argument(
        "--baseline",
        type=Path,
        default=Path("/tmp/cadr-parity-74caa2649"),
    )
    result.add_argument("--timeout", type=float, default=180.0)
    result.add_argument("--artifacts", type=Path)
    return result


def main() -> int:
    try:
        return gate(parser().parse_args())
    except (GateFailure, subprocess.TimeoutExpired) as error:
        print(f"tool-result differential: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
