#!/usr/bin/env python3
import json
import os
import select
import subprocess
import sys
import time

EXPECTED_UI_METHODS = {
    "notify",
    "setStatus",
    "setWidget",
    "setTitle",
    "set_editor_text",
    "select",
    "confirm",
    "input",
    "editor",
}
UI_DRAIN_SECONDS = 2.0


def send(process, value):
    process.stdin.write(json.dumps(value, separators=(",", ":")) + "\n")
    process.stdin.flush()


def ui_methods(records):
    return {
        record.get("method")
        for record in records
        if record.get("type") == "extension_ui_request"
    }


def answer_ui_request(process, record, eof_mode):
    method = record.get("method")
    if eof_mode and method in {"select", "confirm", "input", "editor"}:
        return "eof"
    if method == "select":
        send(
            process,
            {
                "type": "extension_ui_response",
                "id": record["id"],
                "value": "beta",
            },
        )
    elif method == "confirm":
        send(
            process,
            {
                "type": "extension_ui_response",
                "id": record["id"],
                "cancelled": True,
            },
        )
    elif method == "input":
        if record.get("title") != "Timeout":
            send(
                process,
                {
                    "type": "extension_ui_response",
                    "id": record["id"],
                    "value": "typed",
                },
            )
    elif method == "editor":
        send(
            process,
            {
                "type": "extension_ui_response",
                "id": record["id"],
                "value": "after",
            },
        )
    return "ok"


def main():
    if len(sys.argv) < 3:
        raise SystemExit(
            "usage: rpc-process-client.py CADR BASE_URL [EXTENSION [eof]]"
        )
    command = [
        sys.argv[1],
        "--provider",
        "openai",
        "--model",
        "gpt-4o-mini",
        "--base-url",
        sys.argv[2],
        "--mode",
        "rpc",
    ]
    if len(sys.argv) >= 4:
        command.extend(["--extension", sys.argv[3]])
    process = subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env={**os.environ, "OPENAI_API_KEY": "test"},
    )
    eof_mode = len(sys.argv) == 5 and sys.argv[4] == "eof"
    send(
        process,
        {
            "type": "extension_ui_response",
            "id": "missing-ui-request",
            "cancelled": True,
        },
    )
    send(process, {"id": "unknown-1", "type": "unknown"})
    send(process, {"id": "prompt-1", "type": "prompt", "message": "hello"})
    send(process, {"id": "steer-1", "type": "steer", "message": "second"})

    records = []
    saw_agent_end = False
    ui_mode = len(sys.argv) == 4
    while not saw_agent_end:
        line = process.stdout.readline()
        if not line:
            raise RuntimeError("RPC process closed before agent_end")
        record = json.loads(line)
        records.append(record)
        if record.get("type") == "extension_ui_request":
            print(
                f"rpc-ui-diag: client recv {record.get('method')}",
                file=sys.stderr,
                flush=True,
            )
            if answer_ui_request(process, record, eof_mode) == "eof":
                process.stdin.close()
                return_code = process.wait(timeout=10)
                stderr = process.stderr.read()
                if return_code != 0:
                    raise RuntimeError(
                        f"RPC EOF cleanup exited {return_code}: {stderr}"
                    )
                print('{"eof_cleanup":true}')
                return
        saw_agent_end = record.get("type") == "agent_end"

    # First agent_end can precede confirm/editor if another turn settles
    # while the :input hook is still writing dialogs. Keep stdin open and
    # drain for a bound so those requests are answered.
    if ui_mode and not EXPECTED_UI_METHODS.issubset(ui_methods(records)):
        print(
            "rpc-ui-diag: drain start methods="
            + ",".join(sorted(str(name) for name in ui_methods(records))),
            file=sys.stderr,
            flush=True,
        )
        deadline = time.monotonic() + UI_DRAIN_SECONDS
        while time.monotonic() < deadline:
            if EXPECTED_UI_METHODS.issubset(ui_methods(records)):
                break
            remaining = deadline - time.monotonic()
            ready, _, _ = select.select(
                [process.stdout], [], [], max(0.0, remaining)
            )
            if not ready:
                break
            line = process.stdout.readline()
            if not line:
                break
            record = json.loads(line)
            records.append(record)
            if record.get("type") == "extension_ui_request":
                print(
                    f"rpc-ui-diag: client recv {record.get('method')} (drain)",
                    file=sys.stderr,
                    flush=True,
                )
                answer_ui_request(process, record, eof_mode)
        print(
            "rpc-ui-diag: drain end methods="
            + ",".join(sorted(str(name) for name in ui_methods(records))),
            file=sys.stderr,
            flush=True,
        )

    process.stdin.close()
    return_code = process.wait(timeout=10)
    stderr = process.stderr.read()
    if return_code != 0:
        raise RuntimeError(f"RPC exited {return_code}: {stderr}")

    responses = {
        record.get("id"): record
        for record in records
        if record.get("type") == "response"
    }
    assert responses["unknown-1"]["success"] is False
    assert responses["unknown-1"]["command"] == "unknown"
    assert responses["prompt-1"]["success"] is True
    assert responses["steer-1"]["success"] is True
    assert responses["missing-ui-request"]["success"] is False
    assert responses["missing-ui-request"]["command"] == "extension_ui_response"
    assert sum(
        1
        for record in records
        if record.get("id") == "prompt-1"
        and record.get("type") == "response"
    ) == 1
    assert any(record.get("type") == "message_update" for record in records)
    assert any(record.get("type") == "agent_end" for record in records)
    if ui_mode:
        methods = ui_methods(records)
        missing = EXPECTED_UI_METHODS - methods
        if missing:
            tail = [
                f"{record.get('type')}:{record.get('method')}"
                for record in records[-8:]
            ]
            raise AssertionError(
                "extension_ui_request missing "
                + ", ".join(sorted(str(name) for name in missing))
                + "; got "
                + ", ".join(sorted(str(name) for name in methods))
                + "; tail "
                + " ".join(tail)
            )
    print(
        json.dumps(
            {
                "records": len(records),
                "agent_end": True,
                "ui": len(sys.argv) == 4,
            },
            separators=(",", ":"),
        )
    )


if __name__ == "__main__":
    main()
