#!/usr/bin/env python3
import argparse
import errno
import fcntl
import os
import select
import signal
import subprocess
import sys
import termios
import tempfile
import time


ESC = b"\x1b"
BRACKETED_PASTE_ON = ESC + b"[?2004h"
BRACKETED_PASTE_OFF = ESC + b"[?2004l"
CURSOR_HIDE = ESC + b"[?25l"
CURSOR_SHOW = ESC + b"[?25h"
READY = b"GOAL9_A2_READY"
RESUMED = b"GOAL9_A2_RESUMED"


class GateFailure(RuntimeError):
    pass


def lisp_string(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def stty_token(fd):
    result = subprocess.run(
        ["stty", "-g"],
        stdin=fd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        text=True,
    )
    if result.returncode != 0:
        raise GateFailure(f"stty -g failed: {result.stderr.strip()}")
    return result.stdout.strip()


def echo_enabled(fd):
    return bool(termios.tcgetattr(fd)[3] & termios.ECHO)


def canonical_enabled(fd):
    return bool(termios.tcgetattr(fd)[3] & termios.ICANON)


def read_available(master_fd, transcript):
    while True:
        ready, _, _ = select.select([master_fd], [], [], 0)
        if not ready:
            return
        try:
            chunk = os.read(master_fd, 65536)
        except OSError as error:
            if error.errno == errno.EIO:
                return
            raise
        if not chunk:
            return
        transcript.extend(chunk)


def read_until(master_fd, transcript, marker, timeout, process):
    deadline = time.monotonic() + timeout
    while marker not in transcript:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise GateFailure(f"timed out waiting for {marker!r}")
        ready, _, _ = select.select([master_fd], [], [], min(0.1, remaining))
        if ready:
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
            read_available(master_fd, transcript)
            raise GateFailure(
                f"process exited {status} before marker {marker!r}"
            )


def state_lines(path):
    try:
        with open(path, encoding="utf-8") as stream:
            return stream.read().splitlines()
    except FileNotFoundError:
        return []


def wait_for_child_pid(path, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for line in state_lines(path):
            if line.startswith("PID:"):
                return int(line.removeprefix("PID:"))
        time.sleep(0.01)
    raise GateFailure("PTY supervisor did not report the child pid")


def wait_for_supervisor_state(path, prefix, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        matches = [
            line for line in state_lines(path) if line.startswith(prefix)
        ]
        if matches:
            return matches[-1]
        time.sleep(0.01)
    raise GateFailure(f"PTY supervisor did not report {prefix}")


def wait_for_exit(process, timeout):
    try:
        return process.wait(timeout=timeout)
    except subprocess.TimeoutExpired as error:
        process.kill()
        process.wait()
        raise GateFailure("process did not exit") from error


def assert_runtime_is_raw(slave_fd, before_stty, phase):
    current = stty_token(slave_fd)
    if current == before_stty:
        raise GateFailure(f"{phase}: stty did not enter raw mode")
    if echo_enabled(slave_fd):
        raise GateFailure(f"{phase}: ECHO remained enabled")
    if canonical_enabled(slave_fd):
        raise GateFailure(f"{phase}: ICANON remained enabled")


def assert_terminal_restored(slave_fd, before_stty, phase):
    current = stty_token(slave_fd)
    if current != before_stty:
        raise GateFailure(
            f"{phase}: stty mismatch: before={before_stty} after={current}"
        )
    if not echo_enabled(slave_fd):
        raise GateFailure(f"{phase}: ECHO was not restored")


def assert_sequence_contract(transcript, cycles):
    expected_counts = {
        BRACKETED_PASTE_ON: cycles,
        BRACKETED_PASTE_OFF: cycles,
        CURSOR_HIDE: cycles,
        CURSOR_SHOW: cycles,
    }
    for sequence, expected in expected_counts.items():
        actual = transcript.count(sequence)
        if actual != expected:
            raise GateFailure(
                f"{sequence!r}: expected {expected}, observed {actual}"
            )

    offset = 0
    for cycle in range(cycles):
        on = transcript.find(BRACKETED_PASTE_ON, offset)
        hide = transcript.find(CURSOR_HIDE, on + 1)
        show = transcript.find(CURSOR_SHOW, hide + 1)
        off = transcript.find(BRACKETED_PASTE_OFF, show + 1)
        if min(on, hide, show, off) < 0:
            raise GateFailure(
                f"terminal sequence cycle {cycle + 1} is incomplete"
            )
        if not (on < hide < show < off):
            raise GateFailure(
                f"terminal sequence cycle {cycle + 1} is out of order"
            )
        offset = off + len(BRACKETED_PASTE_OFF)


def child_command(project, sbcl, quicklisp):
    command = [
        sbcl,
        "--noinform",
        "--disable-debugger",
        "--load",
        quicklisp,
    ]
    for system in ("cadr-ai", "cadr-agent", "cadr-tui", "cadr-cli"):
        command.extend(
            [
                "--eval",
                "(asdf:load-asd (truename "
                + lisp_string(os.path.join(project, f"{system}.asd"))
                + "))",
            ]
        )
    command.extend(
        [
            "--eval",
            '(asdf:load-system "cadr-cli")',
            "--load",
            os.path.join(
                project, "test/cadr-cli/goal9-a2-pty-harness.lisp"
            ),
            "--quit",
        ]
    )
    return command


def append_supervisor_state(path, value):
    with open(path, "a", encoding="utf-8") as stream:
        stream.write(value + "\n")
        stream.flush()
        os.fsync(stream.fileno())


def supervise(state_path, command):
    signal.signal(signal.SIGTTOU, signal.SIG_IGN)
    child_pid = os.fork()
    if child_pid == 0:
        os.setpgid(0, 0)
        for signum in (
            signal.SIGCONT,
            signal.SIGTSTP,
            signal.SIGTTIN,
            signal.SIGTTOU,
        ):
            signal.signal(signum, signal.SIG_DFL)
        os.execvpe(command[0], command, os.environ)

    try:
        os.setpgid(child_pid, child_pid)
    except (PermissionError, ProcessLookupError):
        pass
    os.tcsetpgrp(0, child_pid)
    append_supervisor_state(state_path, f"PID:{child_pid}")

    while True:
        _, status = os.waitpid(
            child_pid, os.WUNTRACED | os.WCONTINUED
        )
        if os.WIFSTOPPED(status):
            append_supervisor_state(
                state_path, f"STOPPED:{os.WSTOPSIG(status)}"
            )
            continue
        if os.WIFCONTINUED(status):
            append_supervisor_state(state_path, "CONTINUED")
            continue
        if os.WIFEXITED(status):
            code = os.WEXITSTATUS(status)
            append_supervisor_state(state_path, f"EXIT:{code}")
            return code
        if os.WIFSIGNALED(status):
            signum = os.WTERMSIG(status)
            append_supervisor_state(state_path, f"SIGNAL:{signum}")
            return 128 + signum


def transcript_tail(transcript):
    tail = bytes(transcript[-4000:])
    return tail.decode("utf-8", errors="backslashreplace")


def run_scenario(name, input_bytes, project, sbcl, quicklisp):
    master_fd, slave_fd = os.openpty()
    process = None
    child_pid = None
    transcript = bytearray()
    with tempfile.TemporaryDirectory(
        prefix="cadr-goal9-a2-pty-"
    ) as temporary:
        state_path = os.path.join(temporary, "supervisor.state")
        try:
            before_stty = stty_token(slave_fd)
            if not echo_enabled(slave_fd):
                raise GateFailure("PTY baseline unexpectedly has ECHO disabled")
            env = os.environ.copy()
            env.update(
                {
                    "COLUMNS": "80",
                    "LINES": "24",
                    "TERM": "xterm-256color",
                    "LC_ALL": env.get("LC_ALL", "C.UTF-8"),
                }
            )
            for variable in (
                "KITTY_WINDOW_ID",
                "ITERM_SESSION_ID",
                "TMUX",
                "TERM_PROGRAM",
            ):
                env.pop(variable, None)

            def establish_controlling_terminal():
                os.setsid()
                fcntl.ioctl(0, termios.TIOCSCTTY, 0)

            application_command = child_command(
                project, sbcl, quicklisp
            )
            process = subprocess.Popen(
                [
                    sys.executable,
                    os.path.abspath(__file__),
                    "--supervise",
                    state_path,
                    "--",
                    *application_command,
                ],
                stdin=slave_fd,
                stdout=slave_fd,
                stderr=slave_fd,
                env=env,
                close_fds=True,
                preexec_fn=establish_controlling_terminal,
            )
            child_pid = wait_for_child_pid(state_path, 5)
            read_until(master_fd, transcript, READY, 45, process)
            assert_runtime_is_raw(
                slave_fd, before_stty, f"{name} running"
            )

            if name != "suspend-resume":
                os.write(master_fd, input_bytes)
                status = wait_for_exit(process, 10)
                read_available(master_fd, transcript)
                if status != 0:
                    raise GateFailure(f"process exited {status}")
                expected_exit = (
                    b"GOAL9_A2_EXIT:CTRL-C"
                    if name == "ctrl-c"
                    else b"GOAL9_A2_EXIT:NORMAL"
                )
                if expected_exit not in transcript:
                    raise GateFailure(f"missing {expected_exit!r}")
                assert_terminal_restored(
                    slave_fd, before_stty, f"{name} exit"
                )
                assert_sequence_contract(transcript, 1)
            else:
                os.write(master_fd, b"\x1a")
                stopped = wait_for_supervisor_state(
                    state_path, "STOPPED:", 10
                )
                if stopped != f"STOPPED:{signal.SIGTSTP}":
                    raise GateFailure(
                        f"process reported {stopped}, expected SIGTSTP"
                    )
                read_available(master_fd, transcript)
                assert_terminal_restored(
                    slave_fd, before_stty, "SIGTSTP stopped state"
                )
                if transcript.count(CURSOR_SHOW) != 1:
                    raise GateFailure(
                        "SIGTSTP did not show the cursor before stopping"
                    )
                if transcript.count(BRACKETED_PASTE_OFF) != 1:
                    raise GateFailure(
                        "SIGTSTP did not disable bracketed paste before stopping"
                    )
                os.kill(child_pid, signal.SIGCONT)
                wait_for_supervisor_state(
                    state_path, "CONTINUED", 10
                )
                read_until(
                    master_fd, transcript, RESUMED, 10, process
                )
                assert_runtime_is_raw(
                    slave_fd, before_stty, "SIGCONT resumed state"
                )
                os.write(master_fd, b"q")
                status = wait_for_exit(process, 10)
                read_available(master_fd, transcript)
                if status != 0:
                    raise GateFailure(f"process exited {status}")
                if (
                    b"GOAL9_A2_EXIT:SUSPEND-RESUME"
                    not in transcript
                ):
                    raise GateFailure(
                        "missing suspend-resume exit marker"
                    )
                assert_terminal_restored(
                    slave_fd, before_stty, "suspend-resume exit"
                )
                assert_sequence_contract(transcript, 2)

            print(
                f"{name}: PASS stty-restored echo-restored "
                f"cursor-cycles={1 if name != 'suspend-resume' else 2} "
                f"bracketed-paste-cycles="
                f"{1 if name != 'suspend-resume' else 2}"
            )
        except BaseException as error:
            if child_pid is not None:
                try:
                    os.kill(child_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            if process is not None and process.poll() is None:
                process.kill()
                process.wait()
            raise GateFailure(
                f"{name}: {error}\n--- transcript tail ---\n"
                f"{transcript_tail(transcript)}"
            ) from error
        finally:
            os.close(master_fd)
            os.close(slave_fd)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--sbcl", required=True)
    parser.add_argument("--quicklisp", required=True)
    arguments = parser.parse_args()

    cases = (
        ("normal", b"q"),
        ("ctrl-c", b"\x03"),
        ("suspend-resume", b"\x1a"),
    )
    for name, input_bytes in cases:
        run_scenario(
            name,
            input_bytes,
            arguments.project,
            arguments.sbcl,
            arguments.quicklisp,
        )
    print("goal9 A2 PTY lifecycle: 3/3 passed")


if __name__ == "__main__":
    if len(sys.argv) >= 5 and sys.argv[1] == "--supervise":
        if sys.argv[3] != "--":
            raise SystemExit("invalid PTY supervisor command")
        raise SystemExit(supervise(sys.argv[2], sys.argv[4:]))
    else:
        try:
            main()
        except GateFailure as error:
            print(
                f"goal9 A2 PTY lifecycle: FAIL: {error}",
                file=sys.stderr,
            )
            raise SystemExit(1)
