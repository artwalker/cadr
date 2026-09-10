#!/usr/bin/env bash
# First-run smoke for a stranger-ready CADR tip.
# usage: scripts/smoke-first-run.sh
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CADR_BIN="${CADR_BIN:-$ROOT/cadr}"

fail() {
  echo "smoke-first-run: $*" >&2
  exit 1
}

[ -x "$CADR_BIN" ] || fail "missing executable $CADR_BIN"

version_out="$("$CADR_BIN" --version 2>&1)"
printf '%s\n' "$version_out" | rg -q '^cadr ' || fail "unexpected --version: $version_out"

help_out="$("$CADR_BIN" --help 2>&1)"
printf '%s\n' "$help_out" | rg -q 'Usage:' || fail "--help missing Usage"
printf '%s\n' "$help_out" | rg -q -- '--print' || fail "--help missing --print"

no_key_out="$(
  env -u ANTHROPIC_API_KEY -u OPENAI_API_KEY -u GEMINI_API_KEY \
      -u DEEPSEEK_API_KEY -u OPENROUTER_API_KEY -u XAI_API_KEY \
      CADR_OFFLINE=1 \
      "$CADR_BIN" -p "hi" --provider deepseek 2>&1 || true
)"
printf '%s\n' "$no_key_out" | rg -q 'No API key found' \
  || fail "offline no-key path did not report missing key: $no_key_out"

if [ "${CADR_SMOKE_SKIP_PRINT:-0}" = "1" ]; then
  echo "smoke-first-run: skipped -p (CADR_SMOKE_SKIP_PRINT=1)"
else
  print_out="$("$CADR_BIN" -p "Say exactly: ok" 2>&1)"
  printf '%s\n' "$print_out" | rg -q '^ok$' \
    || fail "print-mode expected lone ok, got: $print_out"
fi

"$ROOT/scripts/check-root-binary.sh" >/tmp/smoke-first-run-binary.txt 2>&1 \
  || fail "root binary not fresh; see /tmp/smoke-first-run-binary.txt"
rg -q 'root cadr binary is fresh' /tmp/smoke-first-run-binary.txt \
  || fail "freshness line missing"

echo "smoke-first-run: PASS"
