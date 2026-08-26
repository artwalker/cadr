#!/usr/bin/env bash
# Run Goal 21 gate verification without a cursor-agent session.
# Writes progress heartbeat and a failure excerpt for the fix agent.
#
# usage:
#   scripts/goal21-gate-run.sh
#   scripts/goal21-gate-run.sh --fail-log /tmp/goal21-gate-fail.txt
#
# exit 0 = all green; non-zero = failure (excerpt in --fail-log)
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FAIL_LOG="${GOAL21_GATE_FAIL_LOG:-/tmp/goal21-gate-fail.txt}"
PROGRESS="${GOAL21_GATE_PROGRESS:-/tmp/goal21-gate-progress}"
RUN_LOG="${GOAL21_GATE_RUN_LOG:-/tmp/goal21-gate-run.log}"
FAILURE_TYPE_FILE="${GOAL21_GATE_FAILURE_TYPE_FILE:-/tmp/goal21-gate-failure-type}"
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

heartbeat() {
	printf '%s\t%s\n' "$(date -Iseconds)" "$*" >"$PROGRESS"
	echo "goal21-gate-run: $*"
}

cd "$PROJECT_DIRECTORY"
: >"$RUN_LOG"
heartbeat "start"

set +e
heartbeat "ensure-root-binary"
"$PROJECT_DIRECTORY/scripts/ensure-root-binary.sh" \
	--project-directory "$PROJECT_DIRECTORY" >>"$RUN_LOG" 2>&1
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
	heartbeat "fail ensure-root-binary rc=$RC"
	tail -n "$TAIL_LINES" "$RUN_LOG" >"$FAIL_LOG"
	echo "goal21-gate-run: FAILED ensure-root-binary (log $FAIL_LOG)" >&2
	exit "$RC"
fi

set +e
heartbeat "baseline-anchor"
python3 scripts/baseline-anchor.py check >>"$RUN_LOG" 2>&1
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
	heartbeat "fail baseline-anchor rc=$RC"
	tail -n "$TAIL_LINES" "$RUN_LOG" >"$FAIL_LOG"
	echo "goal21-gate-run: FAILED baseline-anchor (log $FAIL_LOG)" >&2
	exit "$RC"
fi

if [ "${GOAL21_SKIP_PREFLIGHT:-0}" != 1 ]; then
	if [ "${GOAL21_PREFLIGHT_RENDER_DIFF:-0}" != 1 ] \
		&& [ -f "$FAILURE_TYPE_FILE" ] \
		&& [ "$(cat "$FAILURE_TYPE_FILE")" = "render-diff" ]; then
		export GOAL21_PREFLIGHT_RENDER_DIFF=1
		heartbeat "preflight (auto render-diff core — last failure was render-diff)"
	fi
	set +e
	heartbeat "preflight"
	"$PROJECT_DIRECTORY/scripts/goal21-gate-preflight.sh" --fail-log "$FAIL_LOG" >>"$RUN_LOG" 2>&1
	RC=$?
	set -e
	if [ "$RC" -ne 0 ]; then
		heartbeat "fail preflight rc=$RC"
		tail -n "$TAIL_LINES" "$RUN_LOG" >"$FAIL_LOG"
		echo "goal21-gate-run: FAILED preflight (log $FAIL_LOG)" >&2
		exit "$RC"
	fi
fi

set +e
heartbeat "verify.sh"
./scripts/verify.sh >>"$RUN_LOG" 2>&1
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
	heartbeat "fail verify.sh rc=$RC"
	tail -n "$TAIL_LINES" "$RUN_LOG" >"$FAIL_LOG"
	"$PROJECT_DIRECTORY/scripts/goal21-gate-classify-failure.sh" "$FAIL_LOG" >"$FAILURE_TYPE_FILE" 2>/dev/null || true
	echo "goal21-gate-run: FAILED verify.sh (log $FAIL_LOG)" >&2
	exit "$RC"
fi

set +e
heartbeat "test-cl.sh"
./scripts/test-cl.sh >>"$RUN_LOG" 2>&1
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
	heartbeat "fail test-cl.sh rc=$RC"
	tail -n "$TAIL_LINES" "$RUN_LOG" >"$FAIL_LOG"
	echo "goal21-gate-run: FAILED test-cl.sh (log $FAIL_LOG)" >&2
	exit "$RC"
fi

heartbeat "pass"
rm -f "$FAIL_LOG"
echo "goal21-gate-run: PASS"
exit 0
