#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PI_CL="$PROJECT_DIRECTORY/pi-cl"

if [ ! -x "$PI_CL" ]; then
  echo "acceptance smoke: build ./pi-cl first" >&2
  exit 1
fi

"$PI_CL" --help >/dev/null

SMOKE_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$SMOKE_ROOT"' EXIT
mkdir -p "$SMOKE_ROOT/home" "$SMOKE_ROOT/project"

(
  cd "$SMOKE_ROOT/project"
  HOME="$SMOKE_ROOT/home" ANTHROPIC_API_KEY="offline-smoke" \
    "$PI_CL" --provider anthropic </dev/null >/dev/null
  HOME="$SMOKE_ROOT/home" ANTHROPIC_API_KEY="offline-smoke" \
    "$PI_CL" --provider anthropic --continue </dev/null >/dev/null
)

SESSION_COUNT="$(
  find "$SMOKE_ROOT/home/.pi-cl/sessions" \
    -maxdepth 1 -type f -name '*.jsonl' | wc -l
)"

if [ "$SESSION_COUNT" -ne 1 ]; then
  echo "acceptance smoke: --continue created a second session" >&2
  exit 1
fi

SESSION_PATH="$(
  find "$SMOKE_ROOT/home/.pi-cl/sessions" \
    -maxdepth 1 -type f -name '*.jsonl'
)"
SESSION_FILENAME="${SESSION_PATH##*/}"
SESSION_ID="${SESSION_FILENAME%.jsonl}"

(
  cd "$SMOKE_ROOT/project"
  HOME="$SMOKE_ROOT/home" ANTHROPIC_API_KEY="offline-smoke" \
    "$PI_CL" --provider anthropic --resume "$SESSION_ID" \
    </dev/null >/dev/null
)

RESUME_SESSION_COUNT="$(
  find "$SMOKE_ROOT/home/.pi-cl/sessions" \
    -maxdepth 1 -type f -name '*.jsonl' | wc -l
)"

if [ "$RESUME_SESSION_COUNT" -ne 1 ]; then
  echo "acceptance smoke: --resume created a second session" >&2
  exit 1
fi

echo "acceptance smoke: executable help, --continue, and exact --resume passed"
