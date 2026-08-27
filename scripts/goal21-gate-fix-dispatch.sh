#!/usr/bin/env bash
# Dispatch a failure-kind specialist cursor-agent (not a generic fix agent).
#
# usage:
#   scripts/goal21-gate-fix-dispatch.sh \
#     --kind render-diff --task-id 7 --round 2 --attempt 1 \
#     --fail-log /tmp/goal21-gate-fail.txt
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PI_BASELINE_CACHE="/tmp/cadr-render-diff-pi-$(cut -d' ' -f1 "$PROJECT_DIRECTORY/BASELINE" | cut -c1-9)"
BRIEF="$PROJECT_DIRECTORY/docs/acceptance/goal21-dev-executor.md"
SPEC="$PROJECT_DIRECTORY/docs/acceptance/goal21-pi-0843-alignment.md"
FAILURE_KIND=""
TASK_ID=""
FULL_ROUND=""
ATTEMPT=""
FAIL_LOG="${GOAL21_GATE_FAIL_LOG:-/tmp/goal21-gate-fail.txt}"
RENDER_DIFF_BRIEF="${GOAL21_RENDER_DIFF_BRIEF:-/tmp/goal21-render-diff-brief.txt}"

while [ "$#" -gt 0 ]; do
	case "$1" in
	--kind)
		FAILURE_KIND="${2:?}"
		shift 2
		;;
	--task-id)
		TASK_ID="${2:?}"
		shift 2
		;;
	--round)
		FULL_ROUND="${2:?}"
		shift 2
		;;
	--attempt)
		ATTEMPT="${2:?}"
		shift 2
		;;
	--fail-log)
		FAIL_LOG="${2:?}"
		shift 2
		;;
	*)
		echo "usage: $0 --kind KIND --task-id ID --round N --attempt M [--fail-log PATH]" >&2
		exit 2
		;;
	esac
done

[ -n "$FAILURE_KIND" ] && [ -n "$TASK_ID" ] && [ -n "$FULL_ROUND" ] && [ -n "$ATTEMPT" ] || {
	echo "$0: --kind --task-id --round --attempt required" >&2
	exit 2
}

TASK_KEY="gate-specialist-${FAILURE_KIND}-${TASK_ID}-r${FULL_ROUND}-p${ATTEMPT}"
FIX_TIMEOUT="${CADR_GATE_FIX_TIMEOUT_SEC:-1800}"

case "$FAILURE_KIND" in
render-diff)
	FIX_TIMEOUT="${CADR_GATE_RENDER_DIFF_FIX_TIMEOUT_SEC:-600}"
	ROLE="Goal 21 Gate SPECIALIST: render-diff"
	TARGET="Read ${RENDER_DIFF_BRIEF} and ${FAIL_LOG}. If keys are missing/stale or hash drift: edit test/fixtures/render-diff/dispositions.json (max 5 keys). If capture timed out or cadr action failed: inspect scripts/render-diff.py and test/fixtures/render-diff/cadr-driver.lisp for the failing scenario/checkpoint; apply the smallest terminal-protocol or harness fix on main."
	VALIDATE="Do NOT run render-diff.py, verify.sh, or test-cl.sh — orchestrator runs postfix."
	EXTRA="Brief: ${RENDER_DIFF_BRIEF}
Draft: ${GOAL21_DISPOSITION_DRAFT:-/tmp/goal21-disposition-draft.json}"
	;;
product-identity)
	ROLE="Goal 21 Gate SPECIALIST: product-identity allowlist"
	TARGET="Edit ONLY docs/product-identity-allowlist.json — run: python3 scripts/check-product-identity.py --root . --inventory and add missing entries; update expected_findings to match allow total."
	VALIDATE="Optional: python3 test/product-identity-gate-test.py — do NOT run verify.sh."
	EXTRA=""
	;;
source-parity)
	ROLE="Goal 21 Gate SPECIALIST: source-parity ledger"
	TARGET="Fix docs/source-parity.md citations and/or mapping drift cited in the fail excerpt."
	VALIDATE="Optional: sbcl --script scripts/derive-source-parity-mappings.lisp --check"
	EXTRA=""
	;;
goal20-ledger)
	ROLE="Goal 21 Gate SPECIALIST: goal20 unpaired-paths ledger"
	TARGET="Fix docs/benchmarks/goal20-unpaired-paths.json denominator and fileRules; run python3 scripts/goal20-unpaired-paths.py --write then --check."
	VALIDATE="Do NOT run test-cl.sh — orchestrator runs postfix."
	EXTRA=""
	;;
fiveam)
	ROLE="Goal 21 Gate SPECIALIST: FiveAM / test-cl failure"
	TARGET="Fix the specific failing test named in the excerpt (not product-identity or render-diff unless that stage actually FAILED)."
	VALIDATE="If src/ changed: scripts/cadr-compile-check.sh. Do NOT run verify.sh or test-cl.sh."
	EXTRA="If excerpt mentions goal20 unpaired paths denominator drift, fix goal20-unpaired-paths.json first."
	;;
liveness)
	ROLE="Goal 21 Gate SPECIALIST: statistical liveness / PTY capture"
	TARGET="Fix the PTY capture timeout or harness failure cited in the excerpt (often waiting for \\x1b[?2026l). Inspect scripts/render-diff.py capture path, test/fixtures/render-diff/cadr-driver.lisp, and terminal protocol handling — not dispositions.json."
	VALIDATE="Do NOT run verify.sh or render-diff.py capture — orchestrator runs postfix."
	EXTRA=""
	;;
goal11)
	ROLE="Goal 21 Gate SPECIALIST: Goal 11 performance gate"
	TARGET="Fix the Goal 11 pause/perf regression cited in the excerpt (sustained mixed interaction maximum pause exceeds threshold). Smallest src/ or bench threshold fix on main."
	VALIDATE="Do NOT run verify.sh — orchestrator runs postfix."
	EXTRA=""
	;;
event-diff)
	ROLE="Goal 21 Gate SPECIALIST: event differential"
	TARGET="Read /tmp/goal21-gate-run.log for the event differential summary. Run: python3 test/event-diff-gate-test.py && python3 scripts/event-diff.py --baseline-repo $PI_BASELINE_CACHE --artifacts /tmp/goal21-event-diff-output; inspect /tmp/goal21-event-diff-output/report.json for unresolved differences. Fix cadr event emission/normalization in src/ for cadr-bug; add exact entries to test/fixtures/event-diff/dispositions.json only for approved baseline differences (max 8 keys this round)."
	VALIDATE="Do NOT run verify.sh — orchestrator runs postfix."
	EXTRA="Dispositions: test/fixtures/event-diff/dispositions.json"
	;;
*)
	ROLE="Goal 21 Gate SPECIALIST: generic gate fix"
	TARGET="Fix the smallest set of files cited in the failure excerpt."
	VALIDATE=""
	EXTRA=""
	;;
esac

PROMPT="Read ${BRIEF} and ${SPEC}. ${ROLE}.
Task ${TASK_ID} round ${FULL_ROUND} attempt ${ATTEMPT}.
${VALIDATE}
Target: ${TARGET}
Failure excerpt: ${FAIL_LOG}
${EXTRA}
Steps:
1. Read excerpt/brief; apply the smallest fix on main.
2. git commit -m \"fix(g21-gate): ${FAILURE_KIND} (r${FULL_ROUND})\"
3. Print: GOAL21_FIX_DONE task=${TASK_ID} round=${FULL_ROUND} kind=${FAILURE_KIND}
Keep under 10 minutes; orchestrator runs postfix before the next full gate."

echo "goal21-gate-fix-dispatch: specialist=${FAILURE_KIND} task-key=${TASK_KEY} timeout=${FIX_TIMEOUT}s"
exec env CADR_AGENT_RESUME=0 \
	"$PROJECT_DIRECTORY/scripts/cadr-team-dispatch.sh" \
	--workspace "$PROJECT_DIRECTORY" \
	--goal gate \
	--task-key "$TASK_KEY" \
	--timeout "$FIX_TIMEOUT" \
	-- "$PROMPT"
