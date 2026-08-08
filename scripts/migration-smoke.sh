#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CADR="$PROJECT_DIRECTORY/cadr"

if [ ! -x "$CADR" ]; then
  echo "migration smoke: build ./cadr first" >&2
  exit 1
fi

if ! command -v script >/dev/null 2>&1; then
  echo "migration smoke: util-linux script is required" >&2
  exit 1
fi

SMOKE_ROOT="$(mktemp -d)"
SERVER_PID=""
cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf -- "$SMOKE_ROOT"
}
trap cleanup EXIT

LEGACY_NAME="$(printf '%s%s-cl' p i)"
HOME_DIRECTORY="$SMOKE_ROOT/home"
PROJECT="$SMOKE_ROOT/project"
OLD_DIRECTORY="$HOME_DIRECTORY/.$LEGACY_NAME"
NEW_DIRECTORY="$HOME_DIRECTORY/.cadr"
mkdir -p "$HOME_DIRECTORY" "$PROJECT"

PORT_FILE="$SMOKE_ROOT/port"
python3 "$PROJECT_DIRECTORY/test/fixtures/openai-sse-server.py" \
  "$PORT_FILE" &
SERVER_PID="$!"
tries=0
while [ ! -s "$PORT_FILE" ]; do
  tries=$((tries + 1))
  if [ "$tries" -ge 100 ]; then
    echo "migration smoke: provider stub did not start" >&2
    exit 1
  fi
  sleep 0.02
done
PORT="$(tr -d '\r\n' <"$PORT_FILE")"
BASE_URL="http://127.0.0.1:$PORT"

(
  cd "$PROJECT"
  HOME="$HOME_DIRECTORY" OPENAI_API_KEY=test \
    "$CADR" --provider openai --model gpt-4o-mini \
    --base-url "$BASE_URL" --print "seed" >/dev/null
)
# Rebuild a pure pre-agent-layer legacy tree: the seeded session moves to
# the flat layout, and the seeded (current-layout) directory is discarded.
mkdir -p "$OLD_DIRECTORY"
mv -- "$NEW_DIRECTORY/agent/sessions" "$OLD_DIRECTORY/sessions"
rm -rf -- "$NEW_DIRECTORY"
mkdir -p "$OLD_DIRECTORY/extensions/example"
printf '%s\n' \
  '(define-command "legacy" (lambda (context) (declare (ignore context)) "ok"))' \
  >"$OLD_DIRECTORY/extensions/example/extension.lisp"
printf '%s\n' '{}' >"$OLD_DIRECTORY/auth.json"
chmod 644 "$OLD_DIRECTORY/auth.json"

set +e
NONINTERACTIVE_OUTPUT="$(
  HOME="$HOME_DIRECTORY" "$CADR" --version </dev/null 2>&1
)"
NONINTERACTIVE_STATUS=$?
set -e

if [ "$NONINTERACTIVE_STATUS" -eq 0 ]; then
  echo "migration smoke: noninteractive migration did not fail closed" >&2
  exit 1
fi

if ! printf '%s' "$NONINTERACTIVE_OUTPUT" | grep -q "Run manually: mv --"; then
  echo "migration smoke: refusal omitted the manual move command" >&2
  exit 1
fi

if [ ! -d "$OLD_DIRECTORY" ] || [ -e "$NEW_DIRECTORY" ]; then
  echo "migration smoke: refusal changed user data" >&2
  exit 1
fi

COMMAND="cd '$PROJECT' && HOME='$HOME_DIRECTORY' OPENAI_API_KEY='test' '$CADR' --provider openai --model gpt-4o-mini --base-url '$BASE_URL' --continue --no-tui"
printf 'yes\n' | script -qefc "$COMMAND" /dev/null >/dev/null

if [ -e "$OLD_DIRECTORY" ] || [ ! -d "$NEW_DIRECTORY" ]; then
  echo "migration smoke: interactive migration did not move the tree" >&2
  exit 1
fi

if [ ! -f "$NEW_DIRECTORY/agent/extensions/example/extension.lisp" ]; then
  echo "migration smoke: extension did not land in the agent layer" >&2
  exit 1
fi

if [ "$(stat -c '%a' "$NEW_DIRECTORY/agent/auth.json")" != "600" ]; then
  echo "migration smoke: migrated auth.json is not mode 0600" >&2
  exit 1
fi

SESSION_COUNT="$(
  find "$NEW_DIRECTORY/agent/sessions" \
    -maxdepth 1 -type f -name '*.jsonl' | wc -l
)"

if [ "$SESSION_COUNT" -ne 1 ]; then
  echo "migration smoke: --continue did not resume the migrated session" >&2
  exit 1
fi

echo "migration smoke: refusal, full move, auth mode, and --continue passed"
