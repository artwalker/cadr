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
import select
import shutil
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
    "alt+up": b"\x1b[1;3A",
}


class HarnessFailure(RuntimeError):
    pass


def load_manifest(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 1:
        raise HarnessFailure("render-diff manifest schemaVersion must be 1")
    return data


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
            raise HarnessFailure(
                f"timed out waiting for occurrence {minimum} of {needle!r}"
            )
        read_ready(fd, output, min(0.1, remaining), process)


def wait_exit(fd: int, output: bytearray, process: subprocess.Popen[bytes], timeout: float) -> int:
    deadline = time.monotonic() + timeout
    while process.poll() is None:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            process.kill()
            process.wait()
            raise HarnessFailure("render-diff driver did not exit")
        read_ready(fd, output, min(0.1, remaining), process)
    drain(fd, output)
    return process.returncode


def fixed_environment(home: Path, columns: int, rows: int, ready_path: Path) -> dict[str, str]:
    env = os.environ.copy()
    for key in ("TMUX", "TMUX_PANE", "WT_SESSION", "KITTY_WINDOW_ID", "SSH_TTY"):
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
) -> None:
    for action in actions:
        if "waitFor" in action:
            wait_for(master_fd, output, action["waitFor"].encode(), timeout, process)
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
        elif "pauseMs" in action:
            deadline = time.monotonic() + action["pauseMs"] / 1000
            while time.monotonic() < deadline:
                read_ready(master_fd, output, min(0.01, deadline - time.monotonic()), process)
        else:
            raise HarnessFailure(f"unknown action: {action}")


def capture_side(
    side: str,
    baseline: Path,
    manifest_path: Path,
    scenario: dict[str, Any],
    dimension: dict[str, int],
    sandbox: Path,
    timeout: float,
) -> bytes:
    home = sandbox / side / "home"
    cwd = sandbox / side / "workspace"
    agent_dir = home / (".pi/agent" if side == "pi" else ".cadr")
    home.mkdir(parents=True)
    cwd.mkdir(parents=True)
    agent_dir.mkdir(parents=True)
    (cwd / "sample.txt").write_text("alpha\n中文🙂\nomega\n", encoding="utf-8")
    ready_path = sandbox / side / "ready"
    command, process_cwd = driver_command(
        side, baseline, manifest_path, scenario["id"], cwd, agent_dir
    )
    master_fd, slave_fd = os.openpty()
    set_winsize(slave_fd, dimension["columns"], dimension["rows"])
    output = bytearray()
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
        run_actions(side, scenario["actions"], master_fd, output, process, timeout)
        status = wait_exit(master_fd, output, process, timeout)
        if status != 0:
            tail = bytes(output[-4000:]).decode("utf-8", errors="backslashreplace")
            raise HarnessFailure(f"{side} driver exited {status}; transcript tail:\n{tail}")
        return bytes(output)
    finally:
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        os.close(master_fd)
        if slave_fd >= 0:
            os.close(slave_fd)


def normalized(data: bytes, side: str, sandbox: Path) -> bytes:
    """Apply only adjudication-candidate value substitutions; preserve layout and ANSI."""
    replacements = [
        (str(sandbox / side / "home").encode(), b"<HOME>"),
        (str(sandbox / side / "workspace").encode(), b"<CWD>"),
        (b"pi v0.83.0", b"<PRODUCT> v<VERSION>"),
        (b"cadr v0.2.0", b"<PRODUCT> v<VERSION>"),
        (b"Pi can explain its own features", b"<PRODUCT_TITLE> can explain its own features"),
        (b"Cadr can explain its own features", b"<PRODUCT_TITLE> can explain its own features"),
        (b"extend Pi.", b"extend <PRODUCT_TITLE>."),
        (b"extend Cadr.", b"extend <PRODUCT_TITLE>."),
        (b" pi --session ", b" <PRODUCT> --session "),
        (b" cadr --session ", b" <PRODUCT> --session "),
    ]
    result = data
    for old, new in replacements:
        result = result.replace(old, new)
    return result


def write_capture(output_dir: Path, scenario_id: str, dimension_id: str, side: str, data: bytes) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    stem = f"{scenario_id}.{dimension_id}.{side}"
    (output_dir / f"{stem}.raw").write_bytes(data)
    (output_dir / f"{stem}.sha256").write_text(hashlib.sha256(data).hexdigest() + "\n", encoding="ascii")


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
            raw = capture_side(
                side, baseline, manifest_path, scenario, dimension, sandbox, args.timeout
            )
            captures[side] = raw
            write_capture(args.output.resolve(), scenario["id"], args.dimension, side, raw)
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


def self_test(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest.resolve())
    if len(manifest["dimensions"]) < 2:
        raise HarnessFailure("manifest must retain narrow and wide dimensions")
    sample = b" \x1b[38;2;1;2;3mcolor\x1b[0m \n"
    with tempfile.TemporaryDirectory(prefix="cadr-render-diff-normalize-") as temporary:
        sandbox = Path(temporary)
        if normalized(sample, "pi", sandbox) != sample:
            raise HarnessFailure("normalization altered whitespace or ANSI color bytes")
    replay_roots = [args.output / "replay-1", args.output / "replay-2"]
    for replay_root in replay_roots:
        subprocess.run(
            [sys.executable, __file__, "capture", "--manifest", str(args.manifest),
             "--pi-repo", str(args.pi_repo), "--scenario", "plain-text",
             "--dimension", "wide", "--output", str(replay_root),
             "--side", "both", "--baseline-cache", str(args.baseline_cache),
             "--timeout", str(args.timeout)],
            check=True,
        )
        raw_files = list(replay_root.glob("plain-text.wide.*.raw"))
        if len(raw_files) != 4:
            raise HarnessFailure(
                f"expected four raw/normalized captures, found {len(raw_files)}"
            )
        for path in raw_files:
            if b"\x1b[" not in path.read_bytes():
                raise HarnessFailure(f"capture omitted ANSI bytes: {path}")
    for side in ("pi", "cadr"):
        name = f"plain-text.wide.{side}.normalized.raw"
        if (replay_roots[0] / name).read_bytes() != (replay_roots[1] / name).read_bytes():
            raise HarnessFailure(f"normalized {side} capture is not self-replay deterministic")
    print("render-diff self-test: PASS")
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)
    for name in ("capture", "self-test"):
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
    return result


def main() -> int:
    args = parser().parse_args()
    if args.command == "capture":
        return capture(args)
    return self_test(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (HarnessFailure, subprocess.CalledProcessError) as error:
        print(f"render-diff: {error}", file=sys.stderr)
        raise SystemExit(2)
