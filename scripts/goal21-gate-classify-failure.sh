#!/usr/bin/env bash
# Classify the last gate failure for targeted postfix checks.
#
# usage: scripts/goal21-gate-classify-failure.sh [fail-log]
# prints one of: render-diff | event-diff | baseline-anchor | source-parity | product-identity | goal20-ledger | fiveam | liveness | goal11 | unknown
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
elif printf '%s' "$BLOB" | rg -q 'statistical liveness[[:space:]]+FAIL'; then
	echo "liveness"
elif printf '%s' "$BLOB" | rg -q 'Goal 11 performance and stability gate[[:space:]]+FAIL'; then
	echo "goal11"
elif printf '%s' "$BLOB" | rg -q 'fixed-baseline render differential[[:space:]]+FAIL|render-diff gate \(core\)[[:space:]]+FAIL|goal21-gate-preflight: FAILED render-diff'; then
	echo "render-diff"
elif printf '%s' "$BLOB" | rg -q 'fixed-baseline event differential[[:space:]]+FAIL|event differential:.*[[:space:]]+[1-9][0-9]* unresolved'; then
	echo "event-diff"
elif printf '%s' "$BLOB" | rg -qi 'goal21-gate-preflight: FAILED image-derived mapping freshness|goal 21 source parity enumeration[[:space:]]+FAIL|real source parity ledger[[:space:]]+FAIL|source parity drift self-test[[:space:]]+FAIL|cadr-side mapping existence[[:space:]]+FAIL|image-derived mapping freshness[[:space:]]+FAIL|goal21-gate-preflight: FAILED source-parity|derive-source-parity.*FAIL|goal21-gate-preflight: FAILED|fail preflight'; then
	echo "source-parity"
elif printf '%s' "$BLOB" | rg -qi 'fail baseline-anchor|goal21-gate-run: FAILED baseline-anchor|goal21-gate-preflight: FAILED baseline-anchor|baseline anchor:.*hardcodes the baseline commit'; then
	echo "baseline-anchor"
elif printf '%s' "$BLOB" | rg -qi 'deterministic FiveAM[[:space:]]+FAIL|cadr-cli tests failed|fail test-cl'; then
	echo "fiveam"
else
	echo "unknown"
fi
