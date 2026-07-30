#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CADR="$PROJECT_DIRECTORY/cadr"
AUTH_FILE="${CADR_AUTH_FILE:-$HOME/.cadr/auth.json}"

if [ ! -x "$CADR" ]; then
  echo "OAuth live smoke: build ./cadr first" >&2
  exit 1
fi

if [ ! -f "$AUTH_FILE" ]; then
  echo "OAuth live smoke: run /login openai first" >&2
  exit 2
fi

if [ "$(stat -c '%a' "$AUTH_FILE")" != "600" ]; then
  echo "OAuth live smoke: auth.json mode is not 0600" >&2
  exit 1
fi

SMOKE_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$SMOKE_ROOT"' EXIT
mkdir -p "$SMOKE_ROOT/home/.cadr" "$SMOKE_ROOT/project"

# Older cadr builds stored the Codex credential under "openai". The baseline
# provider identity is "openai-codex"; normalize only the isolated smoke copy.
umask 077
jq '
  if has("openai-codex") then
    {"openai-codex": .["openai-codex"]}
  elif has("openai") then
    {"openai-codex": .openai}
  else
    empty
  end
' "$AUTH_FILE" >"$SMOKE_ROOT/home/.cadr/auth.json"
if [ ! -s "$SMOKE_ROOT/home/.cadr/auth.json" ]; then
  echo "OAuth live smoke: no OpenAI Codex OAuth credential found" >&2
  exit 2
fi

OUTPUT="$SMOKE_ROOT/output.txt"
(
  cd "$SMOKE_ROOT/project"
  HOME="$SMOKE_ROOT/home" "$CADR" \
    --no-tui \
    --provider openai-codex \
    --model gpt-5.5 \
    --system-prompt \
    "Follow the requested output format exactly and do not call tools." \
    >"$OUTPUT" <<'EOF'
Reply with exactly OAUTH_OK and nothing else.
EOF
)

if ! grep -Fq "assistant> OAUTH_OK" "$OUTPUT"; then
  echo "OAuth live smoke: streamed response did not match" >&2
  sed -n '1,120p' "$OUTPUT" >&2
  exit 1
fi

echo "OAuth live smoke: OpenAI Codex Responses streaming passed"
