#!/usr/bin/env bash
# Fast targeted validation after a gate fix — before the next full verify.sh run.
#
# usage:
#   scripts/goal21-gate-postfix-check.sh [failure-type]
#   scripts/goal21-gate-postfix-check.sh --from-fail-log [/path/to/fail.txt]
#
# Skipped when GOAL21_SKIP_POSTFIX=1.
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FAIL_LOG="${GOAL21_GATE_FAIL_LOG:-/tmp/goal21-gate-fail.txt}"
FAILURE_TYPE="${GOAL21_GATE_FAILURE_TYPE:-}"
PI_BASELINE_CACHE="/tmp/cadr-render-diff-pi-$(cut -d' ' -f1 "$PROJECT_DIRECTORY/BASELINE" | cut -c1-9)"
RENDER_DIFF_ANALYSIS="${GOAL21_RENDER_DIFF_ANALYSIS:-/tmp/goal21-render-diff-analysis}"
RENDER_DIFF_OUTPUT="${GOAL21_RENDER_DIFF_OUTPUT:-/tmp/goal21-render-diff-output}"
LOG="${GOAL21_GATE_POSTFIX_LOG:-/tmp/goal21-gate-postfix.log}"

cd "$PROJECT_DIRECTORY"
: >"$LOG"

stage() {
	printf '\n==> %s\n' "$1" | tee -a "$LOG"
}

if [ "${GOAL21_SKIP_POSTFIX:-0}" = 1 ]; then
	echo "goal21-gate-postfix: SKIP (GOAL21_SKIP_POSTFIX=1)"
	exit 0
fi

FROM_FAIL_LOG=0
if [ "${1:-}" = "--from-fail-log" ]; then
	FROM_FAIL_LOG=1
	FAIL_LOG="${2:-$FAIL_LOG}"
	FAILURE_TYPE="$("$PROJECT_DIRECTORY/scripts/goal21-gate-classify-failure.sh" "$FAIL_LOG")"
elif [ -n "${1:-}" ]; then
	FAILURE_TYPE="$1"
elif [ -z "$FAILURE_TYPE" ]; then
	FAILURE_TYPE="$("$PROJECT_DIRECTORY/scripts/goal21-gate-classify-failure.sh" "$FAIL_LOG")"
fi

echo "goal21-gate-postfix: checking failure-type=${FAILURE_TYPE}"

case "$FAILURE_TYPE" in
render-diff)
	stage "render-diff gate (core)"
	mkdir -p "$RENDER_DIFF_ANALYSIS" "$RENDER_DIFF_OUTPUT"
	if ! python3 -u test/render-diff-gate-test.py >>"$LOG" 2>&1; then
		"$PROJECT_DIRECTORY/scripts/goal21-gate-render-diff-brief.sh" \
			"$RENDER_DIFF_ANALYSIS" "$FAIL_LOG" >/dev/null 2>&1 || true
		echo "goal21-gate-postfix: FAILED render-diff-gate-test" >&2
		exit 1
	fi
	if ! python3 -u scripts/render-diff.py gate \
		--pi-repo "$PROJECT_DIRECTORY" \
		--manifest test/fixtures/render-diff/scenarios.json \
		--dispositions test/fixtures/render-diff/dispositions.json \
		--tier core \
		--baseline-cache "$PI_BASELINE_CACHE" \
		--timeout 60 \
		--output "$RENDER_DIFF_OUTPUT" \
		--analysis-output "$RENDER_DIFF_ANALYSIS" >>"$LOG" 2>&1; then
		"$PROJECT_DIRECTORY/scripts/goal21-gate-render-diff-brief.sh" \
			"$RENDER_DIFF_ANALYSIS" "$FAIL_LOG" >/dev/null 2>&1 || true
		echo "goal21-gate-postfix: FAILED render-diff core (see /tmp/goal21-render-diff-brief.txt)" >&2
		exit 1
	fi
	;;
source-parity)
	stage "image-derived mapping freshness"
	if ! "${SBCL:-sbcl}" --script scripts/derive-source-parity-mappings.lisp --check >>"$LOG" 2>&1; then
		echo "goal21-gate-postfix: FAILED source-parity mapping check" >&2
		exit 1
	fi
	;;
product-identity)
	stage "product identity gate"
	if ! python3 -u test/product-identity-gate-test.py >>"$LOG" 2>&1; then
		echo "goal21-gate-postfix: FAILED product-identity-gate-test" >&2
		exit 1
	fi
	;;
fiveam)
	stage "cadr compile check"
	if ! "$PROJECT_DIRECTORY/scripts/cadr-compile-check.sh" >>"$LOG" 2>&1; then
		echo "goal21-gate-postfix: FAILED cadr-compile-check" >&2
		exit 1
	fi
	;;
unknown | *)
	stage "default preflight (source-parity)"
	if ! "${SBCL:-sbcl}" --script scripts/derive-source-parity-mappings.lisp --check >>"$LOG" 2>&1; then
		echo "goal21-gate-postfix: FAILED default preflight" >&2
		exit 1
	fi
	;;
esac

echo "goal21-gate-postfix: PASS (${FAILURE_TYPE})"
exit 0
