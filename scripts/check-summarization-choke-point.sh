#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE_ROOT="${1:-$PROJECT_DIRECTORY}"

mapfile -t STREAM_CALLERS < <(
  rg -l -F '(agent-stream-function agent)' \
    "$SOURCE_ROOT/src/cadr-agent" | sort
)

EXPECTED_CALLERS=(
  "$SOURCE_ROOT/src/cadr-agent/loop/turns.lisp"
  "$SOURCE_ROOT/src/cadr-agent/summarization.lisp"
)

if [ "${STREAM_CALLERS[*]}" != "${EXPECTED_CALLERS[*]}" ]; then
  echo "summarization choke point: unexpected agent stream callers" >&2
  printf 'expected: %s\n' "${EXPECTED_CALLERS[*]}" >&2
  printf 'actual:   %s\n' "${STREAM_CALLERS[*]}" >&2
  exit 1
fi

for summary_path in \
  "$SOURCE_ROOT/src/cadr-agent/compaction.lisp" \
  "$SOURCE_ROOT/src/cadr-agent/branch-summarization.lisp"; do
  if ! rg -q -F '(complete-summarization' "$summary_path"; then
    echo "summarization choke point: missing owner call in $summary_path" >&2
    exit 1
  fi
done

echo "summarization choke point: PASS"
