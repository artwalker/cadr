#!/usr/bin/env bash
# Classify the last gate failure for targeted postfix checks.
#
# usage: scripts/goal21-gate-classify-failure.sh [fail-log]
# prints one of: render-diff | source-parity | product-identity | fiveam | unknown
set -euo pipefail

FAIL_LOG="${1:-${GOAL21_GATE_FAIL_LOG:-/tmp/goal21-gate-fail.txt}}"
PROGRESS="${GOAL21_GATE_PROGRESS:-/tmp/goal21-gate-progress}"

if [ ! -f "$FAIL_LOG" ]; then
	echo "unknown"
	exit 0
fi

BLOB="$(cat "$FAIL_LOG" 2>/dev/null || true)"
if [ -f "$PROGRESS" ]; then
	BLOB="${BLOB}
$(cat "$PROGRESS" 2>/dev/null || true)"
fi

if printf '%s' "$BLOB" | rg -q 'fixed-baseline render differential|render-diff gate|render differential prerequisite'; then
	echo "render-diff"
elif printf '%s' "$BLOB" | rg -qi 'product identity'; then
	echo "product-identity"
elif printf '%s' "$BLOB" | rg -qi 'source-parity|source parity|image-derived mapping|derive-source-parity'; then
	echo "source-parity"
elif printf '%s' "$BLOB" | rg -qi 'FiveAM|fiveam'; then
	echo "fiveam"
elif printf '%s' "$BLOB" | rg -q 'goal21-gate-preflight: FAILED render-diff'; then
	echo "render-diff"
elif printf '%s' "$BLOB" | rg -q 'goal21-gate-preflight: FAILED|fail preflight'; then
	echo "source-parity"
else
	echo "unknown"
fi
