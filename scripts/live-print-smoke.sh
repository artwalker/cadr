#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CADR="$PROJECT_DIRECTORY/cadr"

if [ ! -x "$CADR" ]; then
  echo "print live smoke: build ./cadr first" >&2
  exit 1
fi

if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  echo "print live smoke: DEEPSEEK_API_KEY is not set" >&2
  exit 2
fi

SMOKE_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$SMOKE_ROOT"' EXIT
mkdir -p "$SMOKE_ROOT/home" "$SMOKE_ROOT/project"

OUTPUT="$SMOKE_ROOT/output.txt"
(
  cd "$SMOKE_ROOT/project"
  env -u CADR_MODEL HOME="$SMOKE_ROOT/home" \
    "$CADR" \
    --provider deepseek \
    --model deepseek-v4-flash \
    --print \
    --system-prompt \
    "Follow the requested output format exactly and do not call tools." \
    "Reply with exactly DEEPSEEK_PRINT_OK and nothing else." \
    >"$OUTPUT"
)

if [ "$(cat "$OUTPUT")" != "DEEPSEEK_PRINT_OK" ]; then
  echo "print live smoke: stdout was not the exact final response" >&2
  sed -n '1,120p' "$OUTPUT" >&2
  exit 1
fi

echo "print live smoke: DeepSeek one-shot text mode passed"
