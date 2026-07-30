#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CADR="$PROJECT_DIRECTORY/cadr"

if [ ! -x "$CADR" ]; then
  echo "live smoke: build ./cadr first" >&2
  exit 1
fi

if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  echo "live smoke: DEEPSEEK_API_KEY is not set" >&2
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
    --system-prompt \
    "Follow the requested output format exactly and do not call tools." \
    >"$OUTPUT" <<'EOF'
Reply with exactly DEEPSEEK_OK and nothing else.
EOF
)

if ! grep -Fq "assistant> DEEPSEEK_OK" "$OUTPUT"; then
  echo "live smoke: DeepSeek streamed response did not match" >&2
  sed -n '1,120p' "$OUTPUT" >&2
  exit 1
fi

echo "live smoke: DeepSeek Chat Completions streaming passed"
