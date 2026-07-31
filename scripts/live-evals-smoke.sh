#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
AUTH_FILE="${CADR_AUTH_FILE:-$HOME/.cadr/auth.json}"
QUICKLISP_SETUP="${QUICKLISP_SETUP:-$HOME/quicklisp/setup.lisp}"
export QUICKLISP_SETUP

if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  echo "live evals: DEEPSEEK_API_KEY is not set" >&2
  exit 2
fi
if [ ! -f "$QUICKLISP_SETUP" ]; then
  echo "live evals: Quicklisp setup not found at $QUICKLISP_SETUP" >&2
  exit 2
fi
if [ ! -f "$AUTH_FILE" ]; then
  echo "live evals: run /login openai first" >&2
  exit 2
fi

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/deepseek-home" "$TEST_ROOT/codex-home/.cadr"

umask 077
jq '
  if has("openai-codex") then
    {"openai-codex": .["openai-codex"]}
  elif has("openai") then
    {"openai-codex": .openai}
  else
    empty
  end
' "$AUTH_FILE" >"$TEST_ROOT/codex-home/.cadr/auth.json"
if [ ! -s "$TEST_ROOT/codex-home/.cadr/auth.json" ]; then
  echo "live evals: no OpenAI Codex OAuth credential found" >&2
  exit 2
fi

HOME="$TEST_ROOT/deepseek-home" \
  "$PROJECT_DIRECTORY/scripts/run-evals.sh" \
  --provider deepseek \
  --model deepseek-v4-flash \
  >"$TEST_ROOT/deepseek.json"

HOME="$TEST_ROOT/codex-home" \
  "$PROJECT_DIRECTORY/scripts/run-evals.sh" \
  --provider openai-codex \
  --model gpt-5.5 \
  >"$TEST_ROOT/codex.json"

jq -e '
  .output == "Paris" and
  .usage.totalTokens > 0 and
  .usage.provider == "deepseek"
' "$TEST_ROOT/deepseek.json" >/dev/null

jq -e '
  .output == "Paris" and
  .usage.totalTokens > 0 and
  .usage.provider == "openai-codex"
' "$TEST_ROOT/codex.json" >/dev/null

echo "live evals: DeepSeek and OpenAI Codex smoke suites passed"
