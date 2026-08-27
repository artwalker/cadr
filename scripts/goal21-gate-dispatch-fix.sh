#!/usr/bin/env bash
# Dispatch a gate fix specialist when mechanical heal cannot close the failure.
#
# usage: scripts/goal21-gate-dispatch-fix.sh [--fail-log PATH] [--task-id N]
# Skips when gate-run, verify, or an existing gate fix agent is active.
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FAIL_LOG="${GOAL21_GATE_FAIL_LOG:-/tmp/goal21-gate-fail.txt}"
TASK_ID="${GOAL21_GATE_TASK_ID:-7}"
ATTEMPT_FILE="${GOAL21_GATE_FIX_ATTEMPT_FILE:-/tmp/goal21-gate-fix-attempt}"

while [ "$#" -gt 0 ]; do
	case "$1" in
	--fail-log)
		FAIL_LOG="${2:?}"
		shift 2
		;;
	--task-id)
		TASK_ID="${2:?}"
		shift 2
		;;
	*)
		echo "usage: $0 [--fail-log PATH] [--task-id N]" >&2
		exit 2
		;;
	esac
done

gate_work_active() {
	pgrep -af 'goal21-gate-run\.sh|scripts/verify\.sh' >/dev/null 2>&1 \
		|| pgrep -af 'cursor-agent.*(Goal 21 Gate SPECIALIST|gate-specialist-|gate-fix-)' >/dev/null 2>&1 \
		|| pgrep -af 'cadr-team-dispatch\.sh.*gate-' >/dev/null 2>&1
}

if gate_work_active; then
	echo "goal21-gate-dispatch-fix: skip (gate or fix agent already active)"
	exit 0
fi

if [ ! -f "$FAIL_LOG" ]; then
	echo "goal21-gate-dispatch-fix: skip (no fail log at $FAIL_LOG)" >&2
	exit 1
fi

if ! [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-failure-needs-agent.sh" ] \
	|| ! "$PROJECT_DIRECTORY/scripts/goal21-gate-failure-needs-agent.sh" "$FAIL_LOG"; then
	echo "goal21-gate-dispatch-fix: skip (postfix/mechanical path sufficient)"
	exit 0
fi

FAILURE_KIND="$("$PROJECT_DIRECTORY/scripts/goal21-gate-classify-failure.sh" "$FAIL_LOG")"
ATTEMPT=1
if [ -f "$ATTEMPT_FILE" ]; then
	ATTEMPT="$(($(cat "$ATTEMPT_FILE") + 1))"
fi
printf '%s\n' "$ATTEMPT" >"$ATTEMPT_FILE"

if [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-render-diff-brief.sh" ]; then
	"$PROJECT_DIRECTORY/scripts/goal21-gate-render-diff-brief.sh" \
		"${GOAL21_RENDER_DIFF_ANALYSIS:-/tmp/goal21-render-diff-analysis}" \
		"$FAIL_LOG" >/dev/null 2>&1 || true
fi

echo "goal21-gate-dispatch-fix: dispatch specialist kind=${FAILURE_KIND} task=${TASK_ID} attempt=${ATTEMPT}"
exec "$PROJECT_DIRECTORY/scripts/goal21-gate-fix-dispatch.sh" \
	--kind "$FAILURE_KIND" \
	--task-id "$TASK_ID" \
	--round 0 \
	--attempt "$ATTEMPT" \
	--fail-log "$FAIL_LOG"
