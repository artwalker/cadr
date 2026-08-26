#!/usr/bin/env bash
# Fast gate checks before full verify.sh.
#
# Default: image-derived mapping freshness (~1 min).
# Optional: GOAL21_PREFLIGHT_RENDER_DIFF=1 runs render-diff core (~15 min).
#
# usage:
#   scripts/goal21-gate-preflight.sh
#   scripts/goal21-gate-preflight.sh --fail-log /tmp/goal21-gate-preflight-fail.txt
#
# Skipped when GOAL21_SKIP_PREFLIGHT=1.
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FAIL_LOG="${GOAL21_GATE_PREFLIGHT_FAIL_LOG:-/tmp/goal21-gate-preflight-fail.txt}"
SBCL_COMMAND="${SBCL:-sbcl}"
PI_BASELINE_CACHE="/tmp/cadr-render-diff-pi-$(cut -d' ' -f1 "$PROJECT_DIRECTORY/BASELINE" | cut -c1-9)"
RENDER_DIFF_ANALYSIS="${GOAL21_RENDER_DIFF_ANALYSIS:-/tmp/goal21-render-diff-analysis}"
RENDER_DIFF_OUTPUT="${GOAL21_RENDER_DIFF_OUTPUT:-/tmp/goal21-render-diff-output}"
TAIL_LINES="${GOAL21_GATE_FAIL_TAIL:-160}"

while [ "$#" -gt 0 ]; do
	case "$1" in
	--fail-log)
		FAIL_LOG="${2:?}"
		shift 2
		;;
	*)
		echo "usage: $0 [--fail-log PATH]" >&2
		exit 2
		;;
	esac
done

cd "$PROJECT_DIRECTORY"
LOG="${GOAL21_GATE_PREFLIGHT_LOG:-/tmp/goal21-gate-preflight.log}"
: >"$LOG"

stage() {
	printf '\n==> %s\n' "$1" | tee -a "$LOG"
}

fail() {
	if [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-render-diff-brief.sh" ]; then
		GOAL21_RENDER_DIFF_ANALYSIS="$RENDER_DIFF_ANALYSIS" \
			"$PROJECT_DIRECTORY/scripts/goal21-gate-render-diff-brief.sh" \
			"$RENDER_DIFF_ANALYSIS" "$FAIL_LOG" >/dev/null 2>&1 || true
	fi
	{
		tail -n "$TAIL_LINES" "$LOG"
		if [ -f "${GOAL21_RENDER_DIFF_BRIEF:-/tmp/goal21-render-diff-brief.txt}" ]; then
			echo ""
			cat "${GOAL21_RENDER_DIFF_BRIEF:-/tmp/goal21-render-diff-brief.txt}"
		fi
	} >"$FAIL_LOG"
	echo "goal21-gate-preflight: FAILED $1 (log $FAIL_LOG)" >&2
	exit 1
}

stage "image-derived mapping freshness"
if ! "$SBCL_COMMAND" --script scripts/derive-source-parity-mappings.lisp --check >>"$LOG" 2>&1; then
	fail "image-derived mapping freshness"
fi

if [ "${GOAL21_PREFLIGHT_RENDER_DIFF:-0}" = 1 ]; then
	stage "render-diff gate (core)"
	mkdir -p "$RENDER_DIFF_ANALYSIS" "$RENDER_DIFF_OUTPUT"
	if ! python3 -u test/render-diff-gate-test.py >>"$LOG" 2>&1; then
		fail "render-diff-gate-test"
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
		fail "render-diff gate (core)"
	fi
fi

rm -f "$FAIL_LOG"
echo "goal21-gate-preflight: PASS"
exit 0
