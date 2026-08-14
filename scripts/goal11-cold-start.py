#!/usr/bin/env python3
import errno
import fcntl
import os
import pty
import re
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time


READY_MARKER = b"cadr v"
CSI_SEQUENCE = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]")
OSC_SEQUENCE = re.compile(rb"\x1b\].*?(?:\x07|\x1b\\)", re.DOTALL)


def visible_terminal_text(transcript):
    return CSI_SEQUENCE.sub(b"", OSC_SEQUENCE.sub(b"", bytes(transcript)))


def sanitized_environment(home):
    environment = os.environ.copy()
    environment.pop("NO_COLOR", None)
    environment.pop("FORCE_COLOR", None)
    environment.update(
        {
            "COLUMNS": "100",
            "HOME": home,
            "LC_ALL": environment.get("LC_ALL", "C.UTF-8"),
            "LINES": "40",
            "TERM": "xterm-256color",
            "FORCE_COLOR": "3",
            "XDG_CACHE_HOME": os.path.join(home, ".cache"),
            "XDG_CONFIG_HOME": os.path.join(home, ".config"),
            "XDG_DATA_HOME": os.path.join(home, ".local", "share"),
        }
    )
    for name in tuple(environment):
        if (
            name.endswith("_API_KEY")
            or name.endswith("_TOKEN")
            or name
            in {
                "CADR_HOME",
                "CODEX_HOME",
                "PI_CODING_AGENT_DIR",
                "TMUX",
            }
        ):
            environment.pop(name, None)
    return environment


def read_until_ready(master_fd, process, timeout_seconds):
    transcript = bytearray()
    deadline = time.monotonic() + timeout_seconds
    while READY_MARKER not in visible_terminal_text(transcript):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError("timed out waiting for the first TUI frame")
        readable, _, _ = select.select(
            [master_fd], [], [], min(0.1, remaining)
        )
        if readable:
            try:
                chunk = os.read(master_fd, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    chunk = b""
                else:
                    raise
            if chunk:
                transcript.extend(chunk)
                continue
        status = process.poll()
        if status is not None:
            tail = bytes(transcript[-2000:]).decode(
                "utf-8", errors="backslashreplace"
            )
            raise RuntimeError(
                f"cadr exited {status} before its first frame: {tail}"
            )


def measure(binary):
    master_fd, slave_fd = pty.openpty()
    process = None
    try:
        fcntl.ioctl(
            slave_fd,
            termios.TIOCSWINSZ,
            struct.pack("HHHH", 40, 100, 0, 0),
        )
        with tempfile.TemporaryDirectory(prefix="cadr-goal11-cold-") as home:
            environment = sanitized_environment(home)

            def establish_controlling_terminal():
                os.setsid()
                fcntl.ioctl(0, termios.TIOCSCTTY, 0)

            started_at = time.perf_counter_ns()
            process = subprocess.Popen(
                [binary],
                stdin=slave_fd,
                stdout=slave_fd,
                stderr=slave_fd,
                cwd=os.path.dirname(binary),
                env=environment,
                close_fds=True,
                preexec_fn=establish_controlling_terminal,
            )
            read_until_ready(master_fd, process, 10.0)
            elapsed_microseconds = (time.perf_counter_ns() - started_at) / 1000
            os.write(master_fd, b"/quit\r")
            try:
                process.wait(timeout=5.0)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
                raise RuntimeError("cadr did not exit after /quit")
            if process.returncode != 0:
                raise RuntimeError(
                    f"cadr exited {process.returncode} after the first frame"
                )
            return elapsed_microseconds
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        os.close(master_fd)
        os.close(slave_fd)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: goal11-cold-start.py /absolute/path/to/cadr")
    print(f"{measure(os.path.abspath(sys.argv[1])):.3f}")


if __name__ == "__main__":
    main()
