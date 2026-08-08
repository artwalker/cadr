#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CADR="$PROJECT_DIRECTORY/cadr"

if [ ! -x "$CADR" ]; then
  echo "acceptance smoke: build ./cadr first" >&2
  exit 1
fi

SMOKE_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$SMOKE_ROOT"' EXIT
mkdir -p "$SMOKE_ROOT/home" "$SMOKE_ROOT/project"

HOME="$SMOKE_ROOT/home" "$CADR" --help >/dev/null

(
  cd "$SMOKE_ROOT/project"
  HOME="$SMOKE_ROOT/home" ANTHROPIC_API_KEY="offline-smoke" \
    "$CADR" --provider anthropic </dev/null >/dev/null
)

SESSION_COUNT="$(
  find "$SMOKE_ROOT/home/.cadr/agent/sessions" \
    -maxdepth 1 -type f -name '*.jsonl' | wc -l
)"

if [ "$SESSION_COUNT" -ne 0 ]; then
  echo "acceptance smoke: empty run persisted a session" >&2
  exit 1
fi

SESSION_ID="acceptance-seed"
SESSION_PATH="$SMOKE_ROOT/home/.cadr/agent/sessions/$SESSION_ID.jsonl"
PROJECT_CWD="$SMOKE_ROOT/project/"
printf '%s\n' \
  "{\"type\":\"session\",\"version\":3,\"id\":\"$SESSION_ID\",\"timestamp\":\"2026-07-30T00:00:00.000Z\",\"cwd\":\"$PROJECT_CWD\"}" \
  '{"type":"message","id":"00000001","parentId":null,"timestamp":"2026-07-30T00:00:01.000Z","message":{"role":"assistant","content":[{"type":"text","text":"seed"}],"api":"anthropic-messages","provider":"anthropic","model":"offline","usage":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0},"stopReason":"stop","timestamp":1785369601000}}' \
  >"$SESSION_PATH"

(
  cd "$SMOKE_ROOT/project"
  HOME="$SMOKE_ROOT/home" ANTHROPIC_API_KEY="offline-smoke" \
    "$CADR" --provider anthropic --continue </dev/null >/dev/null
)

CONTINUE_SESSION_COUNT="$(
  find "$SMOKE_ROOT/home/.cadr/agent/sessions" \
    -maxdepth 1 -type f -name '*.jsonl' | wc -l
)"

if [ "$CONTINUE_SESSION_COUNT" -ne 1 ]; then
  echo "acceptance smoke: --continue changed the seeded session count" >&2
  exit 1
fi

(
  cd "$SMOKE_ROOT/project"
  HOME="$SMOKE_ROOT/home" ANTHROPIC_API_KEY="offline-smoke" \
    "$CADR" --provider anthropic --resume "$SESSION_ID" \
    </dev/null >/dev/null
)

RESUME_SESSION_COUNT="$(
  find "$SMOKE_ROOT/home/.cadr/agent/sessions" \
    -maxdepth 1 -type f -name '*.jsonl' | wc -l
)"

if [ "$RESUME_SESSION_COUNT" -ne 1 ]; then
  echo "acceptance smoke: --resume created a second session" >&2
  exit 1
fi

echo "acceptance smoke: delayed persistence, --continue, and exact --resume passed"
