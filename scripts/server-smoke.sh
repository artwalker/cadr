#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CADR="$PROJECT_DIRECTORY/cadr"
CADR_SERVER="$PROJECT_DIRECTORY/cadr-server"

if [ ! -x "$CADR" ] || [ ! -x "$CADR_SERVER" ]; then
  echo "server smoke: build ./cadr and ./cadr-server first" >&2
  exit 1
fi
echo "server smoke: using $CADR and $CADR_SERVER" >&2

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
mkdir -p "$TEST_ROOT/home" "$TEST_ROOT/project" "$TEST_ROOT/server"

CADR_SERVER_DIR="$TEST_ROOT/server" \
CADR_SERVER_CADR_PATH="$CADR" \
HOME="$TEST_ROOT/home" \
  "$CADR_SERVER" serve \
  >"$TEST_ROOT/server.out" \
  2>"$TEST_ROOT/server.err" &
SERVER_PID="$!"

tries=0
while [ ! -S "$TEST_ROOT/server/server.sock" ]; do
  tries=$((tries + 1))
  if [ "$tries" -ge 200 ]; then
    cat "$TEST_ROOT/server.err" >&2
    echo "server smoke: socket did not appear" >&2
    exit 1
  fi
  sleep 0.02
done

SPAWN="$(
  CADR_SERVER_DIR="$TEST_ROOT/server" \
    "$CADR_SERVER" spawn \
    --cwd "$TEST_ROOT/project" \
    --label worker
)" || {
  echo "server smoke: spawn command failed" >&2
  cat "$TEST_ROOT/server.out" "$TEST_ROOT/server.err" >&2 || true
  exit 1
}
if ! INSTANCE_ID="$(printf '%s' "$SPAWN" | jq -er '.instance.id')"; then
  echo "server smoke: spawn did not return instance.id" >&2
  printf 'spawn stdout: %s\n' "$SPAWN" >&2
  cat "$TEST_ROOT/server.out" "$TEST_ROOT/server.err" >&2 || true
  exit 1
fi

online_tries=0
while true; do
  LIST="$(
    CADR_SERVER_DIR="$TEST_ROOT/server" \
      "$CADR_SERVER" list
  )" || {
    echo "server smoke: list command failed" >&2
    cat "$TEST_ROOT/server.out" "$TEST_ROOT/server.err" >&2 || true
    exit 1
  }
  if printf '%s' "$LIST" | jq -e --arg id "$INSTANCE_ID" \
    '.ok and any(.instances[]; .id == $id and .status == "online")' \
    >/dev/null; then
    break
  fi
  online_tries=$((online_tries + 1))
  if [ "$online_tries" -ge 200 ]; then
    echo "server smoke: instance $INSTANCE_ID never went online" >&2
    printf 'list stdout: %s\n' "$LIST" >&2
    cat "$TEST_ROOT/server.out" "$TEST_ROOT/server.err" >&2 || true
    exit 1
  fi
  sleep 0.02
done

STATUS="$(
  CADR_SERVER_DIR="$TEST_ROOT/server" \
    "$CADR_SERVER" status "$INSTANCE_ID"
)" || {
  echo "server smoke: status command failed" >&2
  cat "$TEST_ROOT/server.out" "$TEST_ROOT/server.err" >&2 || true
  exit 1
}
# sessionId is filled from the child's get_state. Isolated CI workers
# come up online before that field exists (run 31987492420 waited 4s
# and it never appeared). The socket contract is id + online; session
# attachment is checked by the get_state RPC below if present.
if ! printf '%s' "$STATUS" | jq -e --arg id "$INSTANCE_ID" \
  '.ok and .instance.id == $id and .instance.status == "online"' \
  >/dev/null; then
  echo "server smoke: status payload rejected" >&2
  printf 'status stdout: %s\n' "$STATUS" >&2
  exit 1
fi

RPC="$(
  CADR_SERVER_DIR="$TEST_ROOT/server" \
    "$CADR_SERVER" rpc "$INSTANCE_ID" '{"type":"get_state"}'
)" || {
  echo "server smoke: rpc command failed" >&2
  cat "$TEST_ROOT/server.out" "$TEST_ROOT/server.err" >&2 || true
  exit 1
}
if ! printf '%s' "$RPC" | jq -e \
  '.ok and .response.success and .response.command == "get_state"' \
  >/dev/null; then
  echo "server smoke: rpc payload rejected" >&2
  printf 'rpc stdout: %s\n' "$RPC" >&2
  exit 1
fi

STOP="$(
  CADR_SERVER_DIR="$TEST_ROOT/server" \
    "$CADR_SERVER" stop "$INSTANCE_ID"
)" || {
  echo "server smoke: stop command failed" >&2
  cat "$TEST_ROOT/server.out" "$TEST_ROOT/server.err" >&2 || true
  exit 1
}
if ! printf '%s' "$STOP" | jq -e --arg id "$INSTANCE_ID" \
  '.ok and .instanceId == $id' \
  >/dev/null; then
  echo "server smoke: stop payload rejected" >&2
  printf 'stop stdout: %s\n' "$STOP" >&2
  exit 1
fi

echo "server smoke: spawn/list/status/RPC/stop over Unix socket passed"
