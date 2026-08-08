#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CADR="$PROJECT_DIRECTORY/cadr"

if [ ! -x "$CADR" ]; then
  echo "wave2 process modes: build ./cadr first" >&2
  exit 1
fi

TEST_ROOT="$(mktemp -d)"
SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT
mkdir -p "$TEST_ROOT/home" "$TEST_ROOT/project"

PORT_FILE="$TEST_ROOT/port"
REQUEST_MARKER="$TEST_ROOT/request-marker"
CADR_STUB_DELAY=0.15 \
  CADR_STUB_REQUEST_MARKER="$REQUEST_MARKER" \
  python3 "$PROJECT_DIRECTORY/test/fixtures/openai-sse-server.py" \
  "$PORT_FILE" &
SERVER_PID="$!"

tries=0
while [ ! -s "$PORT_FILE" ]; do
  tries=$((tries + 1))
  if [ "$tries" -ge 100 ]; then
    echo "wave2 process modes: provider stub did not start" >&2
    exit 1
  fi
  sleep 0.02
done

PORT="$(tr -d '\r\n' <"$PORT_FILE")"
BASE_URL="http://127.0.0.1:$PORT"

if ! (
  cd "$TEST_ROOT/project"
  HOME="$TEST_ROOT/home" OPENAI_API_KEY=test \
    "$CADR" --provider openai --model gpt-4o-mini \
    --base-url "$BASE_URL" --print "hello"
) >"$TEST_ROOT/text.out" 2>"$TEST_ROOT/text.err"; then
  cat "$TEST_ROOT/text.err" >&2
  exit 1
fi
if [ "$(cat "$TEST_ROOT/text.out")" != "stub-ok" ]; then
  echo "wave2 process modes: text print output was not clean" >&2
  exit 1
fi

if ! (
  cd "$TEST_ROOT/project"
  printf 'stdin prompt\n' |
    HOME="$TEST_ROOT/home" OPENAI_API_KEY=test \
      "$CADR" --provider openai --model gpt-4o-mini \
      --base-url "$BASE_URL"
) >"$TEST_ROOT/stdin.out" 2>"$TEST_ROOT/stdin.err"; then
  cat "$TEST_ROOT/stdin.err" >&2
  exit 1
fi
if [ "$(cat "$TEST_ROOT/stdin.out")" != "stub-ok" ]; then
  echo "wave2 process modes: non-TTY stdin did not select text mode" >&2
  exit 1
fi

if ! (
  cd "$TEST_ROOT/project"
  HOME="$TEST_ROOT/home" OPENAI_API_KEY=test \
    "$CADR" --provider openai --model gpt-4o-mini \
    --base-url "$BASE_URL" --mode json "hello"
) >"$TEST_ROOT/json.out" 2>"$TEST_ROOT/json.err"; then
  cat "$TEST_ROOT/json.err" >&2
  exit 1
fi
python3 - "$TEST_ROOT/json.out" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    records = [json.loads(line) for line in stream if line.strip()]
assert records
assert records[-1]["type"] == "agent_settled"
assert any(record["type"] == "agent_end" for record in records)
assert any(record["type"] == "message_update" for record in records)
PY

(
  cd "$TEST_ROOT/project"
  HOME="$TEST_ROOT/home" \
    python3 "$PROJECT_DIRECTORY/test/fixtures/rpc-process-client.py" \
    "$CADR" "$BASE_URL"
) >"$TEST_ROOT/rpc.out"

(
  cd "$TEST_ROOT/project"
  HOME="$TEST_ROOT/home" \
    python3 "$PROJECT_DIRECTORY/test/fixtures/rpc-process-client.py" \
    "$CADR" "$BASE_URL" \
    "$PROJECT_DIRECTORY/test/fixtures/extensions/rpc-ui.lisp"
) >"$TEST_ROOT/rpc-ui.out"

(
  cd "$TEST_ROOT/project"
  HOME="$TEST_ROOT/home" \
    python3 "$PROJECT_DIRECTORY/test/fixtures/rpc-process-client.py" \
    "$CADR" "$BASE_URL" \
    "$PROJECT_DIRECTORY/test/fixtures/extensions/rpc-ui.lisp" eof
) >"$TEST_ROOT/rpc-ui-eof.out"

SHUTDOWN_MARKER="$TEST_ROOT/shutdown-marker"
REQUESTS_BEFORE="$(wc -l <"$REQUEST_MARKER")"
(
  cd "$TEST_ROOT/project"
  HOME="$TEST_ROOT/signal-home" OPENAI_API_KEY=test \
    CADR_SHUTDOWN_MARKER="$SHUTDOWN_MARKER" \
    "$CADR" --provider openai --model gpt-4o-mini \
    --base-url "$BASE_URL" --print \
    --extension \
    "$PROJECT_DIRECTORY/test/fixtures/extensions/shutdown-marker.lisp" \
    "signal test"
) >"$TEST_ROOT/signal.out" 2>"$TEST_ROOT/signal.err" &
SIGNAL_PID="$!"
tries=0
while [ ! -d "$TEST_ROOT/signal-home/.cadr/agent/sessions" ]; do
  tries=$((tries + 1))
  if [ "$tries" -ge 100 ]; then
    echo "wave2 process modes: signal test did not initialize" >&2
    exit 1
  fi
  sleep 0.01
done
tries=0
while [ "$(wc -l <"$REQUEST_MARKER")" -le "$REQUESTS_BEFORE" ]; do
  tries=$((tries + 1))
  if [ "$tries" -ge 100 ]; then
    echo "wave2 process modes: signal request did not start" >&2
    exit 1
  fi
  sleep 0.01
done
kill -TERM "$SIGNAL_PID"
set +e
wait "$SIGNAL_PID"
SIGNAL_STATUS="$?"
set -e
if [ "$SIGNAL_STATUS" -ne 143 ]; then
  cat "$TEST_ROOT/signal.err" >&2
  echo "wave2 process modes: SIGTERM exit was $SIGNAL_STATUS, expected 143" >&2
  exit 1
fi
if [ "$(cat "$SHUTDOWN_MARKER")" != "shutdown" ]; then
  echo "wave2 process modes: SIGTERM skipped session_shutdown" >&2
  exit 1
fi

echo "wave2 process modes: text, auto-stdin, JSONL, RPC intervention/UI/EOF, and SIGTERM cleanup passed"
