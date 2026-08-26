#!/usr/bin/env bash
# Fast Goal 21 gate tier for development iteration (~2-5 min).
# Uses cached render-diff analyze instead of full capture gate.
#
# usage:
#   scripts/goal21-gate-fast.sh
#   scripts/goal21-gate-fast.sh --fail-log /tmp/goal21-gate-fast-fail.txt
#
# Full acceptance still requires GOAL21_GATE_MODE=full (default in goal21-gate-run.sh).
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FAIL_LOG="${GOAL21_GATE_FAST_FAIL_LOG:-/tmp/goal21-gate-fast-fail.txt}"
PROGRESS="${GOAL21_GATE_PROGRESS:-/tmp/goal21-gate-progress}"
RUN_LOG="${GOAL21_GATE_FAST_RUN_LOG:-/tmp/goal21-gate-fast-run.log}"
TAIL_LINES="${GOAL21_GATE_FAIL_TAIL:-160}"
RENDER_DIFF_ANALYSIS="${GOAL21_RENDER_DIFF_ANALYSIS:-/tmp/goal21-render-diff-analysis}"
RENDER_DIFF_OUTPUT="${GOAL21_RENDER_DIFF_OUTPUT:-/tmp/goal21-render-diff-output}"
PI_BASELINE_CACHE="/tmp/cadr-render-diff-pi-$(cut -d' ' -f1 "$PROJECT_DIRECTORY/BASELINE" | cut -c1-9)"

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

heartbeat() {
	printf '%s\t%s\n' "$(date -Iseconds)" "$*"
	echo "goal21-gate-fast: $*"
}

cd "$PROJECT_DIRECTORY"
: >"$RUN_LOG"
heartbeat "start" >"$PROGRESS"

fail() {
	tail -n "$TAIL_LINES" "$RUN_LOG" >"$FAIL_LOG"
	heartbeat "fail $1" >"$PROGRESS"
	echo "goal21-gate-fast: FAILED $1 (log $FAIL_LOG)" >&2
	exit 1
}

heartbeat "ensure-root-binary" >"$PROGRESS"
if ! "$PROJECT_DIRECTORY/scripts/ensure-root-binary.sh" \
	--project-directory "$PROJECT_DIRECTORY" >>"$RUN_LOG" 2>&1; then
	fail "ensure-root-binary"
fi

heartbeat "baseline-anchor" >"$PROGRESS"
if ! python3 scripts/baseline-anchor.py check >>"$RUN_LOG" 2>&1; then
	fail "baseline-anchor"
fi

heartbeat "preflight" >"$PROGRESS"
if ! GOAL21_PREFLIGHT_RENDER_DIFF=1 \
	"$PROJECT_DIRECTORY/scripts/goal21-gate-preflight.sh" --fail-log "$FAIL_LOG" >>"$RUN_LOG" 2>&1; then
	fail "preflight"
fi

heartbeat "disposition-audit" >"$PROGRESS"
if ! python3 scripts/goal21-render-diff-audit-dispositions.py \
	--analysis "$RENDER_DIFF_ANALYSIS" \
	--validate-only >>"$RUN_LOG" 2>&1; then
	fail "disposition-audit"
fi

heartbeat "compile-check" >"$PROGRESS"
if ! "$PROJECT_DIRECTORY/scripts/cadr-compile-check.sh" >>"$RUN_LOG" 2>&1; then
	fail "cadr-compile-check"
fi

if [ -d "$RENDER_DIFF_OUTPUT" ] && [ "$(ls -1 "$RENDER_DIFF_OUTPUT"/*.pi.normalized.raw 2>/dev/null | wc -l)" -gt 0 ]; then
	heartbeat "render-diff-analyze" >"$PROGRESS"
	mkdir -p "$RENDER_DIFF_ANALYSIS"
	if ! python3 -u scripts/render-diff.py analyze \
		--pi-repo "$PROJECT_DIRECTORY" \
		--manifest test/fixtures/render-diff/scenarios.json \
		--dispositions test/fixtures/render-diff/dispositions.json \
		--tier core \
		--baseline-cache "$PI_BASELINE_CACHE" \
		--timeout 60 \
		--output "$RENDER_DIFF_OUTPUT" \
		--analysis-output "$RENDER_DIFF_ANALYSIS" >>"$RUN_LOG" 2>&1; then
		fail "render-diff-analyze"
	fi
else
	echo "goal21-gate-fast: no cached captures — skipping render-diff analyze" >>"$RUN_LOG"
fi

rm -f "$FAIL_LOG"
heartbeat "pass" >"$PROGRESS"
echo "goal21-gate-fast: PASS"
exit 0
