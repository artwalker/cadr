#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE_ROOT="${1:-$PROJECT_DIRECTORY}"

AGENT_ROOT="$SOURCE_ROOT/src/cadr-agent"
TURN_PATH="$AGENT_ROOT/loop/turns.lisp"
OWNER_PATH="$AGENT_ROOT/summarization.lisp"

mapfile -t STREAM_CALLS < <(
  rg -n --no-heading -F '(agent-stream-function' "$AGENT_ROOT" | sort
)
mapfile -t TURN_STREAM_CALLS < <(
  rg -n --no-heading -F '(agent-stream-function' "$TURN_PATH" || true
)
mapfile -t OWNER_STREAM_CALLS < <(
  rg -n --no-heading -F '(agent-stream-function' "$OWNER_PATH" || true
)

if [ "${#STREAM_CALLS[@]}" -ne 3 ] ||
   [ "${#TURN_STREAM_CALLS[@]}" -ne 2 ] ||
   [ "${#OWNER_STREAM_CALLS[@]}" -ne 1 ]; then
  echo "summarization choke point: direct stream-call cardinality changed" >&2
  printf 'expected: total=3 turn-owner=2 summary-owner=1\n' >&2
  printf 'actual:   total=%s turn-owner=%s summary-owner=%s\n' \
    "${#STREAM_CALLS[@]}" "${#TURN_STREAM_CALLS[@]}" \
    "${#OWNER_STREAM_CALLS[@]}" >&2
  printf 'calls:\n%s\n' "${STREAM_CALLS[*]:-<none>}" >&2
  exit 1
fi

extract_defun() {
  local path="$1"
  local name="$2"
  awk -v owner="$name" '
    $0 ~ "^\\(defun " owner "([[:space:]]|$)" { inside = 1 }
    inside && $0 ~ /^\(defun / && $0 !~ "^\\(defun " owner "([[:space:]]|$)" { exit }
    inside { print }
  ' "$path"
}

TURN_OWNER="$(extract_defun "$TURN_PATH" stream-assistant)"
SUMMARY_OWNER="$(extract_defun "$OWNER_PATH" complete-summarization)"

if [ "$(grep -F -c '(agent-stream-function' <<<"$TURN_OWNER")" -ne 2 ] ||
   [ "$(grep -F -c '(agent-stream-function' <<<"$SUMMARY_OWNER")" -ne 1 ]; then
  echo "summarization choke point: direct stream call escaped its unique owner" >&2
  exit 1
fi

for invariant in \
  'cadr-ai:retry-assistant-call' \
  ':cache-retention :none' \
  ':session-id session-id'; do
  if ! grep -F -q "$invariant" <<<"$SUMMARY_OWNER"; then
    echo "summarization choke point: owner lost invariant $invariant" >&2
    exit 1
  fi
done

mapfile -t OWNER_SITES < <(
  rg -n --no-heading -F 'complete-summarization' "$AGENT_ROOT" | sort
)
if [ "${#OWNER_SITES[@]}" -ne 4 ] ||
   [ "$(rg -c -F '(complete-summarization' "$AGENT_ROOT/compaction.lisp")" -ne 2 ] ||
   [ "$(rg -c -F '(complete-summarization' "$AGENT_ROOT/branch-summarization.lisp")" -ne 1 ] ||
   [ "$(rg -c -F '(defun complete-summarization' "$OWNER_PATH")" -ne 1 ]; then
  echo "summarization choke point: owner definition/call graph changed" >&2
  printf 'sites:\n%s\n' "${OWNER_SITES[*]:-<none>}" >&2
  exit 1
fi

echo "summarization choke point: PASS"
