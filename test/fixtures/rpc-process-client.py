#!/usr/bin/env python3
import json
import os
import subprocess
import sys


def send(process, value):
    process.stdin.write(json.dumps(value, separators=(",", ":")) + "\n")
    process.stdin.flush()


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
    while not saw_agent_end:
        line = process.stdout.readline()
        if not line:
            raise RuntimeError("RPC process closed before agent_end")
        record = json.loads(line)
        records.append(record)
        if record.get("type") == "extension_ui_request":
            method = record.get("method")
            if eof_mode and method in {"select", "confirm", "input", "editor"}:
                process.stdin.close()
                return_code = process.wait(timeout=10)
                stderr = process.stderr.read()
                if return_code != 0:
                    raise RuntimeError(
                        f"RPC EOF cleanup exited {return_code}: {stderr}"
                    )
                print('{"eof_cleanup":true}')
                return
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
        saw_agent_end = record.get("type") == "agent_end"

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
    if len(sys.argv) == 4:
        methods = {
            record.get("method")
            for record in records
            if record.get("type") == "extension_ui_request"
        }
        expected = {
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
        missing = expected - methods
        if missing:
            raise AssertionError(
                "extension_ui_request missing "
                + ", ".join(sorted(str(name) for name in missing))
                + "; got "
                + ", ".join(sorted(str(name) for name in methods))
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
