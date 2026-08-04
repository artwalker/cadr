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
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "test/fixtures/render-diff/scenarios.json"
DEFAULT_DISPOSITIONS = ROOT / "test/fixtures/render-diff/dispositions.json"
PI_DRIVER = ROOT / "test/fixtures/render-diff/pi-driver.ts"
CADR_DRIVER = ROOT / "test/fixtures/render-diff/cadr-driver.lisp"
PI_AI_MODEL_DATA_PACKAGE = "@earendil-works/pi-ai@0.83.0"
PI_AI_MODEL_DATA_SHA256 = "f983c28a21209305ed9c274977e29130fa4d8848df6cdf37e9094d95cc7bc6d4"
KEYS = {
    "enter": b"\r",
    "escape": b"\x1b",
    "ctrl+c": b"\x03",
    "ctrl+d": b"\x04",
    "alt+enter": b"\x1b\r",
    "alt+up": b"\x1bp",
    "up": b"\x1b[A",
    "down": b"\x1b[B",
    "left": b"\x1b[D",
    "right": b"\x1b[C",
    "tab": b"\t",
    "space": b" ",
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
    "slash-export",
    "slash-login",
    "slash-reload",
    "post-exit-resume",
}


class HarnessFailure(RuntimeError):
    pass


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
    return data


def expand_dispositions(
    data: dict[str, Any], manifest: dict[str, Any]
) -> dict[str, dict[str, Any]]:
    classes = data["classes"]
    dimensions = {dimension["id"] for dimension in manifest["dimensions"]}
    scenarios = {
        scenario["id"]: {
            action["checkpoint"]
            for action in scenario["actions"]
            if "checkpoint" in action
        }
        | {"process-exit"}
        for scenario in manifest["scenarios"]
    }
    expanded: dict[str, dict[str, Any]] = {}
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
            or any(dimension not in dimensions for dimension in entry_dimensions)
        ):
            raise HarnessFailure(
                f"invalid render-diff disposition dimensions: {scenario}/{checkpoint}"
            )
        if (
            not isinstance(entry_classes, list)
            or not entry_classes
            or any(class_id not in classes for class_id in entry_classes)
        ):
            raise HarnessFailure(
                f"invalid render-diff disposition classes: {scenario}/{checkpoint}"
            )
        for dimension in entry_dimensions:
            key = f"{scenario}/{dimension}/{checkpoint}"
            if key in expanded:
                raise HarnessFailure(f"duplicate render-diff disposition: {key}")
            expanded[key] = {
                "classes": entry_classes,
                "kinds": sorted({classes[class_id]["kind"] for class_id in entry_classes}),
                "note": entry.get("note", ""),
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


def ensure_baseline(pi_repo: Path, commit: str, cache: Path) -> Path:
    marker = cache / ".goal15-render-baseline"
    if marker.is_file() and marker.read_text(encoding="ascii").strip() == commit:
        hydrate_baseline_model_data(cache)
        shutil.copy2(PI_DRIVER, cache / "packages/coding-agent/test/goal15-render-driver.ts")
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
) -> None:
    deadline = time.monotonic() + timeout
    while needle not in output:
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
) -> None:
    deadline = time.monotonic() + timeout
    while output.count(needle) < minimum:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            tail = bytes(output[-4000:]).decode("utf-8", errors="backslashreplace")
            raise HarnessFailure(
                f"timed out waiting for occurrence {minimum} of {needle!r}; "
                f"transcript tail:\n{tail}"
            )
        read_ready(fd, output, min(0.1, remaining), process)


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


def fixed_environment(home: Path, columns: int, rows: int, ready_path: Path) -> dict[str, str]:
    env = os.environ.copy()
    for key in ("TMUX", "TMUX_PANE", "WT_SESSION", "KITTY_WINDOW_ID", "SSH_TTY"):
        env.pop(key, None)
    for key in tuple(env):
        if credential_environment_variable_p(key):
            env.pop(key, None)
    env.update(
        {
            "HOME": str(home),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "COLORFGBG": "15;0",
            "COLUMNS": str(columns),
            "LINES": str(rows),
            "NO_COLOR": "",
            "PI_OFFLINE": "1",
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
) -> tuple[list[str], Path]:
    if side == "pi":
        command = [
            str(baseline / "node_modules/.bin/tsx"),
            "test/goal15-render-driver.ts",
            str(manifest),
            scenario_id,
            str(cwd),
            str(agent_dir),
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
) -> None:
    for index, action in enumerate(actions, start=1):
        try:
            if "waitFor" in action:
                wait_for(master_fd, output, action["waitFor"].encode(), timeout, process)
            elif "waitForNext" in action:
                needle = action["waitForNext"].encode()
                wait_for_count(
                    master_fd,
                    output,
                    needle,
                    output.count(needle) + 1,
                    timeout,
                    process,
                )
            elif "waitForHex" in action:
                wait_for(master_fd, output, bytes.fromhex(action["waitForHex"]), timeout, process)
            elif "waitForSide" in action:
                wait_for(master_fd, output, action["waitForSide"][side].encode(), timeout, process)
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
                    read_ready(master_fd, output, min(0.01, deadline - time.monotonic()), process)
            elif "checkpoint" in action:
                read_ready(master_fd, output, 0.02, process)
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
) -> tuple[bytes, list[dict[str, Any]]]:
    home = sandbox / side / "home"
    cwd = sandbox / side / "workspace"
    agent_dir = home / (".pi/agent" if side == "pi" else ".cadr")
    home.mkdir(parents=True)
    cwd.mkdir(parents=True)
    agent_dir.mkdir(parents=True)
    (cwd / "sample.txt").write_text("alpha\n中文🙂\nomega\n", encoding="utf-8")
    (cwd / "notes").mkdir()
    (cwd / "notes/alpha.txt").write_text("needle alpha\n", encoding="utf-8")
    (cwd / "notes/beta.md").write_text("needle beta\n", encoding="utf-8")
    if scenario.get("setup", {}).get("projectTrusted") is False:
        config_dir = cwd / (".pi" if side == "pi" else ".cadr")
        config_dir.mkdir()
        (config_dir / "settings.json").write_text("{}\n", encoding="utf-8")
    ready_path = sandbox / side / "ready"
    command, process_cwd = driver_command(
        side, baseline, manifest_path, scenario["id"], cwd, agent_dir
    )
    master_fd, slave_fd = os.openpty()
    set_winsize(slave_fd, dimension["columns"], dimension["rows"])
    output = bytearray()
    checkpoints: list[dict[str, Any]] = []
    process: subprocess.Popen[bytes] | None = None
    try:
        process = subprocess.Popen(
            command,
            cwd=process_cwd,
            env=fixed_environment(home, dimension["columns"], dimension["rows"], ready_path),
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            close_fds=True,
            preexec_fn=establish_controlling_terminal,
        )
        os.close(slave_fd)
        slave_fd = -1
        run_actions(
            side, scenario["actions"], master_fd, output, process, timeout, checkpoints
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
        (b" pi --session ", b" <PRODUCT> --session "),
        (b" cadr --session ", b" <PRODUCT> --session "),
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
        rb"(?<=cadr-crash-)[0-9]+-[0-9]+-[0-9]+(?=\.log)",
        b"<CRASH_ID>",
        result,
    )
    return result


def normalized(data: bytes, side: str, sandbox: Path) -> bytes:
    """Apply only adjudication-candidate value substitutions; preserve layout and ANSI."""
    result = data
    for old, new in (
        (str(sandbox / side / "home").encode(), b"<HOME>"),
        (str(sandbox / side / "workspace").encode(), b"<CWD>"),
        (str(sandbox / side).encode(), b"<SANDBOX>"),
    ):
        result = result.replace(old, new)
    return normalize_fixed_values(result)


def normalized_screen(data: bytes, side: str) -> bytes:
    """Normalize a terminal-emulated screen without changing replay geometry."""
    escaped_side = re.escape(side.encode())
    prefix = rb"/tmp/cadr-render-diff-[^/\r\n]+/" + escaped_side
    result = re.sub(prefix + rb"/home", b"<HOME>", data)
    result = re.sub(prefix + rb"/workspace", b"<CWD>", result)
    result = re.sub(prefix, b"<SANDBOX>", result)
    return normalize_fixed_values(result)


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
        baseline = ensure_baseline(
            args.pi_repo.resolve(), commit, args.baseline_cache.resolve()
        )
        captures: dict[str, bytes] = {}
        sides = ("pi", "cadr") if args.side == "both" else (args.side,)
        for side in sides:
            raw, checkpoints = capture_side(
                side, baseline, manifest_path, scenario, dimension, sandbox, args.timeout
            )
            captures[side] = raw
            annotate_normalized_offsets(checkpoints, raw, side, sandbox)
            write_capture(args.output.resolve(), scenario["id"], args.dimension, side, raw)
            write_checkpoints(
                args.output.resolve(), scenario["id"], args.dimension, side, checkpoints
            )
            write_capture(
                args.output.resolve(), scenario["id"], args.dimension, f"{side}.normalized",
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


def tmux_screen(data: bytes, columns: int, rows: int, temporary: Path) -> bytes:
    if shutil.which("tmux") is None:
        raise HarnessFailure("tmux is required for semantic render-diff analysis")
    temporary.mkdir(parents=True, exist_ok=True)
    input_path = temporary / "terminal.raw"
    input_path.write_bytes(data)
    socket = f"cadr-rd-{os.getpid()}-{time.monotonic_ns()}"
    tmux = ["tmux", "-L", socket]
    command = (
        "stty -echo; exec tail -c +1 -f -- "
        + shlex.quote(str(input_path))
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


def analyze(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest.resolve())
    disposition_data = load_dispositions(
        args.dispositions.resolve(), manifest["baselineCommit"]
    )
    dispositions = expand_dispositions(disposition_data, manifest)
    capture_root = args.output.resolve()
    analysis_root = args.analysis_output.resolve()
    analysis_root.mkdir(parents=True, exist_ok=True)
    results: list[dict[str, Any]] = []
    for dimension in manifest["dimensions"]:
        dimension_id = dimension["id"]
        for scenario in manifest["scenarios"]:
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
                for side in ("pi", "cadr"):
                    path = analysis_root / f"{scenario_id}.{dimension_id}.{checkpoint_id}.{side}.screen"
                    path.write_bytes(screens[side])
                raw_summary = raw_difference_summary(segments["pi"], segments["cadr"])
                screen_equal = screens["pi"] == screens["cadr"]
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
                        "automaticDisposition": automatic_disposition,
                        "adjudication": dispositions.get(key),
                    }
                )
                previous = offsets
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
    return 0


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
        screen = tmux_screen(
            b"\x1b[2J\x1b[H\x1b[31mred\x1b[0m", 12, 4, sandbox / "tmux"
        )
        if b"red" not in screen or b"<CURSOR 3,0,1>" not in screen:
            raise HarnessFailure("tmux semantic replay lost text or cursor state")
        raw_path = b"/tmp/cadr-render-diff-fixed/pi/workspace"
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


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)
    for name in ("capture", "self-test", "analyze", "replay-check"):
        command = subparsers.add_parser(name)
        command.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
        command.add_argument("--pi-repo", type=Path, default=Path("/root/projects/pi-mono"))
        command.add_argument("--output", type=Path, default=ROOT / ".tmp/render-diff")
        command.add_argument(
            "--baseline-cache",
            type=Path,
            default=Path("/tmp/cadr-render-diff-pi-74caa2649"),
        )
        command.add_argument("--timeout", type=float, default=20.0)
        if name == "capture":
            command.add_argument("--scenario", required=True)
            command.add_argument("--dimension", choices=("wide", "narrow"), required=True)
            command.add_argument("--side", choices=("pi", "cadr", "both"), default="both")
        if name == "replay-check":
            command.add_argument("--scenario", required=True)
            command.add_argument("--dimension", choices=("wide", "narrow"), required=True)
        if name == "analyze":
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
    if args.command == "capture":
        return capture(args)
    if args.command == "analyze":
        return analyze(args)
    if args.command == "replay-check":
        return replay_check(args)
    return self_test(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (HarnessFailure, subprocess.CalledProcessError) as error:
        print(f"render-diff: {error}", file=sys.stderr)
        raise SystemExit(2)
