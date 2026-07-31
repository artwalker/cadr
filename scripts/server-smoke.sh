#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CADR="$PROJECT_DIRECTORY/cadr"
CADR_SERVER="$PROJECT_DIRECTORY/cadr-server"

if [ ! -x "$CADR" ] || [ ! -x "$CADR_SERVER" ]; then
  echo "server smoke: build ./cadr and ./cadr-server first" >&2
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
)"
INSTANCE_ID="$(printf '%s' "$SPAWN" | jq -er '.instance.id')"

CADR_SERVER_DIR="$TEST_ROOT/server" \
  "$CADR_SERVER" list |
  jq -e --arg id "$INSTANCE_ID" \
    '.ok and any(.instances[]; .id == $id and .status == "online")' \
    >/dev/null

CADR_SERVER_DIR="$TEST_ROOT/server" \
  "$CADR_SERVER" status "$INSTANCE_ID" |
  jq -e --arg id "$INSTANCE_ID" \
    '.ok and .instance.id == $id and .instance.sessionId != null' \
    >/dev/null

CADR_SERVER_DIR="$TEST_ROOT/server" \
  "$CADR_SERVER" rpc "$INSTANCE_ID" '{"type":"get_state"}' |
  jq -e \
    '.ok and .response.success and .response.command == "get_state"' \
    >/dev/null

CADR_SERVER_DIR="$TEST_ROOT/server" \
  "$CADR_SERVER" stop "$INSTANCE_ID" |
  jq -e --arg id "$INSTANCE_ID" \
    '.ok and .instanceId == $id' \
    >/dev/null

echo "server smoke: spawn/list/status/RPC/stop over Unix socket passed"
