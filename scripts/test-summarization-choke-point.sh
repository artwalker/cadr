#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/cadr-summary-choke-point.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/src"

fresh_source() {
  rm -rf -- "$TEST_ROOT/src/cadr-agent"
  cp -R "$PROJECT_DIRECTORY/src/cadr-agent" "$TEST_ROOT/src/cadr-agent"
}

expect_rejected() {
  local label="$1"
  if "$PROJECT_DIRECTORY/scripts/check-summarization-choke-point.sh" \
      "$TEST_ROOT" >/dev/null 2>&1; then
    echo "summarization choke point self-test: $label was accepted" >&2
    exit 1
  fi
}

fresh_source

"$PROJECT_DIRECTORY/scripts/check-summarization-choke-point.sh" "$TEST_ROOT"

printf '\n(defun bypass-summary-policy (agent)\n  (agent-stream-function agent))\n' \
  >> "$TEST_ROOT/src/cadr-agent/compaction.lisp"
expect_rejected "external bypass"

fresh_source
printf '\n(defun second-summary-owner (agent)\n  (agent-stream-function agent))\n' \
  >> "$TEST_ROOT/src/cadr-agent/summarization.lisp"
expect_rejected "second owner"

fresh_source
sed -i \
  '/The single owner of retry, cache, and routing policy/a\  (agent-stream-function agent)' \
  "$TEST_ROOT/src/cadr-agent/summarization.lisp"
expect_rejected "owner-internal bypass"

echo "summarization choke point self-test: PASS"
