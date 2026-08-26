#!/usr/bin/env bash
# Classify the last gate failure for targeted postfix checks.
#
# usage: scripts/goal21-gate-classify-failure.sh [fail-log]
# prints one of: render-diff | source-parity | product-identity | goal20-ledger | fiveam | unknown
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

if printf '%s' "$BLOB" | rg -q 'goal20 unpaired paths: denominator drifted|DETERMINISTIC-TEST-ENTRYPOINT-ACCOUNTS-FOR-ALL-NINE-SUITES.*goal20 unpaired'; then
	echo "goal20-ledger"
elif printf '%s' "$BLOB" | rg -qi 'product identity gate[[:space:]]+FAIL|unapproved identity'; then
	echo "product-identity"
elif printf '%s' "$BLOB" | rg -q 'fixed-baseline render differential|render-diff gate \(core\)|render differential prerequisite|goal21-gate-preflight: FAILED render-diff'; then
	echo "render-diff"
elif printf '%s' "$BLOB" | rg -qi 'source-parity|source parity|image-derived mapping freshness[[:space:]]+FAIL|derive-source-parity'; then
	echo "source-parity"
elif printf '%s' "$BLOB" | rg -qi 'deterministic FiveAM[[:space:]]+FAIL|cadr-cli tests failed|fail test-cl'; then
	echo "fiveam"
elif printf '%s' "$BLOB" | rg -q 'goal21-gate-preflight: FAILED|fail preflight'; then
	echo "source-parity"
else
	echo "unknown"
fi
