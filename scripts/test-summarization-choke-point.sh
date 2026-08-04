#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/cadr-summary-choke-point.XXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/src"
cp -R "$PROJECT_DIRECTORY/src/cadr-agent" "$TEST_ROOT/src/cadr-agent"

"$PROJECT_DIRECTORY/scripts/check-summarization-choke-point.sh" "$TEST_ROOT"

printf '\n(defun bypass-summary-policy (agent)\n  (agent-stream-function agent))\n' \
  >> "$TEST_ROOT/src/cadr-agent/compaction.lisp"

if "$PROJECT_DIRECTORY/scripts/check-summarization-choke-point.sh" \
    "$TEST_ROOT" >/dev/null 2>&1; then
  echo "summarization choke point self-test: bypass was accepted" >&2
  exit 1
fi

echo "summarization choke point self-test: PASS"
