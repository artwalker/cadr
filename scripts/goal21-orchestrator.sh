#!/usr/bin/env bash
# Goal 21 team orchestrator: queue, director merge, cursor-agent dispatch.
#
# usage:
#   scripts/goal21-orchestrator.sh status
#   scripts/goal21-orchestrator.sh cleanup-worktrees [--dry-run]
#   scripts/goal21-orchestrator.sh director-once
#   scripts/goal21-orchestrator.sh director-loop [seconds]
#   scripts/goal21-orchestrator.sh dispatch <lane>   # anchor|parity|a|b|c|infra|gate
#   scripts/goal21-orchestrator.sh dispatch-loop <lane> [seconds]
#
# Queue: docs/benchmarks/goal21-queue.json
# Brief: docs/acceptance/goal21-dev-executor.md
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
QUEUE_PATH="$PROJECT_DIRECTORY/docs/benchmarks/goal21-queue.json"
BRIEF="$PROJECT_DIRECTORY/docs/acceptance/goal21-dev-executor.md"
SPEC="$PROJECT_DIRECTORY/docs/acceptance/goal21-pi-0843-alignment.md"
AGENT_BIN="${CURSOR_AGENT_BIN:-cursor-agent}"
AGENT_MODEL="${CURSOR_AGENT_MODEL:-auto}"

queue_py() {
	python3 - "$QUEUE_PATH" "$@" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
command = sys.argv[2]
GOAL_ID = "21"
UNIFIED = path.parent / "cadr-team-queues.json"
data = json.loads(path.read_text(encoding="utf-8"))


def save() -> None:
    path.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
    root = (
        json.loads(UNIFIED.read_text(encoding="utf-8"))
        if UNIFIED.is_file()
        else {"schemaVersion": 1, "goals": {}}
    )
    root.setdefault("goals", {})[GOAL_ID] = data
    UNIFIED.write_text(json.dumps(root, indent=1) + "\n", encoding="utf-8")


def next_task(lane: str):
    for task in data["tasks"]:
        if task.get("lane") == lane and task.get("status") == "pending":
            return task
    return None


if command == "status":
    pending = sum(1 for t in data["tasks"] if t.get("status") == "pending")
    inprog = sum(1 for t in data["tasks"] if t.get("status") == "in_progress")
    done = sum(1 for t in data["tasks"] if t.get("status") == "done")
    paused = data.get("goal20Paused", False)
    print(
        f"goal21 queue: pending={pending} in_progress={inprog} done={done} "
        f"mergeQueue={len(data.get('mergeQueue', []))} goal20Paused={paused}"
    )
    for task in data["tasks"]:
        if task.get("status") != "done":
            print(
                f"  task {task['id']:>2} lane={task['lane']:6} "
                f"{task['status']:12} {task.get('slug', '')}"
            )
    for item in data.get("mergeQueue", []):
        print(f"  merge: {item['branch']}")

elif command == "claim":
    lane = sys.argv[3]
    task = next_task(lane)
    if task is None:
        print("", end="")
        sys.exit(2)
    task["status"] = "in_progress"
    save()
    print(json.dumps(task))

elif command == "infra-pending":
    pending = sum(1 for t in data["tasks"] if t.get("lane") == "infra" and t.get("status") == "pending")
    inprog = sum(1 for t in data["tasks"] if t.get("lane") == "infra" and t.get("status") == "in_progress")
    print(f"{pending} {inprog}")

elif command == "complete":
    task_id = int(sys.argv[3])
    branch = sys.argv[4]
    for task in data["tasks"]:
        if task.get("id") == task_id:
            task["status"] = "done"
            task["branch"] = branch
            break
    # Anchor/gate land on main — nothing to cherry-pick.
    if branch != "main":
        data.setdefault("mergeQueue", []).append({"branch": branch, "task": task_id})
    save()

elif command == "reconcile-in-progress":
    for task in data["tasks"]:
        if task.get("status") != "in_progress":
            continue
        if task.get("lane") in ("anchor", "gate", "infra"):
            continue
        slug = task.get("slug", "")
        branch = f"g21-{task['id']}-{slug}"
        proc = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--verify", branch],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            continue
        head = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        tip = subprocess.run(
            ["git", "-C", str(root), "rev-parse", branch],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        if tip != head:
            task["status"] = "done"
            task["branch"] = branch
            data.setdefault("mergeQueue", []).append(
                {"branch": branch, "task": task["id"]}
            )
    save()
    print("ok")

elif command == "pop-merge":
    queue = data.get("mergeQueue", [])
    if not queue:
        sys.exit(2)
    item = queue.pop(0)
    save()
    print(json.dumps(item))

elif command == "peek-merge":
    queue = data.get("mergeQueue", [])
    if not queue:
        sys.exit(2)
    print(json.dumps(queue[0]))

elif command == "unshift-merge":
    branch = sys.argv[3]
    task_id = int(sys.argv[4])
    data.setdefault("mergeQueue", []).insert(0, {"branch": branch, "task": task_id})
    save()

else:
    raise SystemExit(f"unknown queue command: {command}")
PY
}

require_clean_main() {
	local path
	local blocking=0
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		if "$PROJECT_DIRECTORY/scripts/goal21-anchor-guard.sh" is-excluded-path "$path" 2>/dev/null; then
			continue
		fi
		blocking=1
		echo "  $path" >&2
	done < <(
		git diff --name-only
		git diff --cached --name-only
	)
	if [ "$blocking" -ne 0 ]; then
		echo "goal21 orchestrator: main worktree dirty (non-operational files)" >&2
		exit 1
	fi
}

cmd="${1:-status}"
shift || true

case "$cmd" in
status)
	queue_py status
	git -C "$PROJECT_DIRECTORY" log -1 --oneline
	cat "$PROJECT_DIRECTORY/BASELINE"
	;;
cleanup-worktrees)
	for wt in /tmp/g21-*-wt; do
		[ -d "$wt" ] || continue
		if [ "${1:-}" = "--dry-run" ]; then
			echo "would remove worktree $wt"
		else
			git -C "$PROJECT_DIRECTORY" worktree remove --force "$wt" 2>/dev/null || true
		fi
	done
	;;
reconcile-in-progress)
	queue_py reconcile-in-progress
	;;
director-once)
	cd "$PROJECT_DIRECTORY"
	"$PROJECT_DIRECTORY/scripts/goal21-anchor-guard.sh" ensure
	require_clean_main
	if MERGE_JSON="$(queue_py peek-merge 2>/dev/null || true)" && [ -n "$MERGE_JSON" ]; then
		BRANCH="$(printf '%s' "$MERGE_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["branch"])')"
		TASK="$(printf '%s' "$MERGE_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["task"])')"
		echo "goal21 director: merge $BRANCH (task $TASK)"
		if "$PROJECT_DIRECTORY/scripts/goal21-director-merge.sh" "$BRANCH"; then
			queue_py pop-merge >/dev/null
		else
			echo "goal21 director: merge failed — leaving $BRANCH in queue" >&2
		fi
	else
		echo "goal21 director: nothing in merge queue"
	fi
	"$0" cleanup-worktrees
	;;
director-loop)
	INTERVAL="${1:-120}"
	while true; do
		"$0" director-once || true
		sleep "$INTERVAL"
	done
	;;
dispatch)
	LANE="${1:?lane required (anchor|parity|a|b|c|infra|gate)}"
	shift || true
	cd "$PROJECT_DIRECTORY"
	TASK_JSON="$(queue_py claim "$LANE")" || {
		echo "goal21 dispatch: no pending task for lane $LANE"
		exit 0
	}
	TASK_ID="$(printf '%s' "$TASK_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
	SLUG="$(printf '%s' "$TASK_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["slug"])')"
	TITLE="$(printf '%s' "$TASK_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["title"])')"
	BRANCH="g21-${TASK_ID}-${SLUG}"
	WORKTREE="/tmp/g21-${TASK_ID}-wt"
	AGENT_WORKSPACE="$PROJECT_DIRECTORY"

	if [ "$LANE" != "anchor" ] && [ "$LANE" != "gate" ] && [ "$LANE" != "infra" ]; then
		if ! WORKTREE=$("$PROJECT_DIRECTORY/scripts/cadr-team-worktree.sh" ensure "$WORKTREE" "$BRANCH" cadr-migration | tail -1); then
			echo "goal21 dispatch: worktree ensure failed for $BRANCH" >&2
			python3 - "$QUEUE_PATH" "$TASK_ID" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
tid = int(sys.argv[2])
for t in data["tasks"]:
    if t.get("id") == tid:
        t["status"] = "pending"
        t["branch"] = None
        break
Path(sys.argv[1]).write_text(json.dumps(data, indent=1) + "\n")
PY
			exit 1
		fi
		AGENT_WORKSPACE="$WORKTREE"
	fi

	PROMPT="Read $BRIEF and $SPEC. You are Goal 21 lane ${LANE}.
Worktree: ${AGENT_WORKSPACE} branch ${BRANCH}. cd there first.
Task ${TASK_ID}: ${TITLE}
Steps:
1. Implement in worktree only; add tests per goal21 spec
2. python3 scripts/baseline-anchor.py check if touching anchors
3. git commit -m \"feat(cadr-cli): g21 task ${TASK_ID} ${SLUG}\"
4. Print: GOAL21_COMPLETE task=${TASK_ID} branch=${BRANCH}
Never edit src/ on main checkout."

	if [ "$LANE" = "infra" ]; then
		PROMPT="Read $BRIEF and $SPEC. You are Goal 21 Infra lane (mechanical, main checkout).
Task ${TASK_ID}: ${TITLE}
Work on main checkout only. chmod +x new scripts/goal21-* before commit.
Commit: feat(cadr-cli): g21 infra task ${TASK_ID} ${SLUG}
Print: GOAL21_COMPLETE task=${TASK_ID} branch=main"
		case "$SLUG" in
		disposition-audit)
			PROMPT="${PROMPT}
Verify scripts/goal21-render-diff-audit-dispositions.py; run: python3 scripts/goal21-render-diff-audit-dispositions.py --validate-only
git add scripts/goal21-render-diff-audit-dispositions.py docs/acceptance/goal21-dev-executor.md"
			;;
		anchor-disposition-guard)
			PROMPT="${PROMPT}
Verify dispositions.json is excluded: scripts/goal21-anchor-guard.sh is-excluded-path test/fixtures/render-diff/dispositions.json
git add scripts/goal21-anchor-guard.sh"
			;;
		fast-gate)
			PROMPT="${PROMPT}
Verify scripts/goal21-gate-fast.sh; run: GOAL21_GATE_MODE=fast scripts/goal21-gate-run.sh (skip if verify/test-cl running)
git add scripts/goal21-gate-fast.sh scripts/goal21-gate-run.sh docs/acceptance/goal21-dev-executor.md"
			;;
		capture-cache)
			PROMPT="${PROMPT}
Verify scripts/goal21-render-diff-capture-cache.sh status; git add scripts/goal21-render-diff-capture-cache.sh scripts/goal21-gate-run.sh scripts/goal21-gate-proactive-render-diff.sh"
			;;
		team-integration)
			PROMPT="${PROMPT}
Verify infra lane in goal21-team-operator.sh and goal21-dev-executor.md; git add docs/acceptance/goal21-dev-executor.md scripts/goal21-team-operator.sh scripts/goal21-orchestrator.sh docs/benchmarks/goal21-queue.json"
			;;
		p1-merge-fast-gate)
			PROMPT="${PROMPT}
Verify GOAL21_GATE_MODE=fast in cadr-team-premerge.sh and goal21-director-merge.sh
git add scripts/cadr-team-premerge.sh scripts/cadr-team-worktree.sh scripts/goal21-director-merge.sh"
			;;
		p1-ci-capture-cache)
			PROMPT="${PROMPT}
Verify .github/workflows/ci.yml cache steps; verify.sh honors GOAL21_RENDER_DIFF_*; run scripts/goal21-ci-capture-cache-verify.sh
git add .github/workflows/ci.yml scripts/verify.sh scripts/goal21-ci-capture-cache-verify.sh docs/acceptance/goal21-dev-executor.md"
			;;
		p2-class-rules)
			PROMPT="${PROMPT}
Verify test/fixtures/render-diff/disposition-class-rules.json; run scripts/goal21-class-rules-verify.sh
git add test/fixtures/render-diff/disposition-class-rules.json scripts/goal21-render-diff-prune-class-rules.py scripts/goal21-class-rules-verify.sh docs/acceptance/goal21-dev-executor.md"
			;;
		p2-test-cl-shard)
			PROMPT="${PROMPT}
Verify scripts/test-cl.sh CADR_TEST_CL_SHARD; run scripts/goal21-test-cl-shard-verify.sh
git add scripts/test-cl-fiveam.sh scripts/test-cl-goal20.sh scripts/goal21-test-cl-shard-verify.sh docs/acceptance/goal21-dev-executor.md"
			;;
		esac
	fi

	if [ "$LANE" = "anchor" ]; then
		ANCHOR_COMMIT="$(cut -d' ' -f1 "$PROJECT_DIRECTORY/BASELINE")"
		PROMPT="Read $BRIEF and $SPEC. You are Goal 21 Anchor lane.
Task ${TASK_ID}: ${TITLE}
On main checkout (allowed for this task only):
1. scripts/set-baseline.sh ${ANCHOR_COMMIT}
2. Update scripts/render-diff.py PI_AI_MODEL_DATA_* to match the new baseline package metadata
3. rm -rf /tmp/cadr-render-diff-pi-* (old baseline caches)
4. python3 scripts/baseline-anchor.py check
5. git add BASELINE scripts/render-diff.py and any rewritten refs; commit -m \"chore(cadr-cli): bump baseline to pi v0.84.3 (g21)\"
6. Print: GOAL21_COMPLETE task=${TASK_ID} branch=main"
	fi

	# Gate: script runs verify/test-cl; short-lived agent only fixes failures.
	# Avoids multi-hour cursor-agent sessions that hang on HTTP/2 stream drops.
	if [ "$LANE" = "gate" ]; then
		FAIL_LOG="${GOAL21_GATE_FAIL_LOG:-/tmp/goal21-gate-fail.txt}"
		FAILURE_TYPE_FILE="${GOAL21_GATE_FAILURE_TYPE_FILE:-/tmp/goal21-gate-failure-type}"
		MAX_ROUNDS="${GOAL21_GATE_MAX_ROUNDS:-6}"
		MAX_POSTFIX_TRIES="${GOAL21_GATE_MAX_POSTFIX_TRIES:-5}"
		FIX_TIMEOUT="${CADR_GATE_FIX_TIMEOUT_SEC:-1800}"
		RENDER_DIFF_BRIEF="/tmp/goal21-render-diff-brief.txt"
		full_round=0
		while [ "$full_round" -lt "$MAX_ROUNDS" ]; do
			full_round=$((full_round + 1))
			if [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-proactive-render-diff.sh" ]; then
				echo "goal21 gate: proactive render-diff heal before round ${full_round}"
				if "$PROJECT_DIRECTORY/scripts/goal21-gate-proactive-render-diff.sh"; then
					echo "goal21 gate: proactive heal PASS — proceeding to full gate"
				else
					echo "goal21 gate: proactive heal incomplete (agent may be needed after failure)" >&2
				fi
			fi
			echo "goal21 gate: full round ${full_round}/${MAX_ROUNDS} running scripts/goal21-gate-run.sh"
			if "$PROJECT_DIRECTORY/scripts/goal21-gate-run.sh" --fail-log "$FAIL_LOG"; then
				if ! rg -q 'pi v0\.84\.3|Goal 21:' "$PROJECT_DIRECTORY/CHANGELOG.md"; then
					echo "goal21 gate: PASS but CHANGELOG missing 0843 note — dispatching short docs agent"
					PROMPT="On main checkout for Goal 21 gate docs only.
Add under CHANGELOG.md ## [Unreleased] ### Changed a short Goal 21 / pi v0.84.3 alignment note if missing.
Commit: chore(cadr-cli): bump baseline to pi v0.84.3 (g21)
Print: GOAL21_COMPLETE task=${TASK_ID} branch=main"
					OUT="$("$PROJECT_DIRECTORY/scripts/cadr-team-dispatch.sh" \
						--workspace "$PROJECT_DIRECTORY" \
						--goal gate \
						--task-key "gate-docs-${TASK_ID}" \
						--timeout "$FIX_TIMEOUT" \
						-- "$PROMPT" 2>&1)" || true
					printf '%s\n' "$OUT"
				fi
				queue_py complete "$TASK_ID" "main"
				echo "goal21 dispatch: gate task $TASK_ID complete"
				exit 0
			fi
			FAILURE_KIND="$("$PROJECT_DIRECTORY/scripts/goal21-gate-classify-failure.sh" "$FAIL_LOG")"
			printf '%s\n' "$FAILURE_KIND" >"$FAILURE_TYPE_FILE"
			echo "goal21 gate: failure classified as ${FAILURE_KIND} (saved $FAILURE_TYPE_FILE)"
			FIX_TIMEOUT="${CADR_GATE_FIX_TIMEOUT_SEC:-1800}"
			case "$FAILURE_KIND" in
			render-diff)
				FIX_TARGET="Review /tmp/goal21-render-diff-brief.txt for failing keys; check /tmp/goal21-disposition-draft.json needsReview entries; auto-sync already applied safe updates."
				FIX_VALIDATE="Do NOT run render-diff.py, verify.sh, or test-cl.sh — orchestrator runs postfix."
				FIX_TIMEOUT="${CADR_GATE_RENDER_DIFF_FIX_TIMEOUT_SEC:-600}"
				;;
			product-identity)
				FIX_TARGET="Fix docs/product-identity-allowlist.json for unapproved pi tokens."
				FIX_VALIDATE="Do NOT run verify.sh — optional: python3 test/product-identity-gate-test.py"
				;;
			source-parity)
				FIX_TARGET="Fix docs/source-parity.md line citations and/or mapping drift."
				FIX_VALIDATE="Optional: sbcl --script scripts/derive-source-parity-mappings.lisp --check"
				;;
			goal20-ledger)
				FIX_TARGET="Refresh docs/benchmarks/goal20-unpaired-paths.json denominator via goal20-unpaired-paths.py --write."
				FIX_VALIDATE="Do NOT run test-cl.sh — orchestrator runs postfix."
				FIX_TIMEOUT="${CADR_GATE_LEDGER_FIX_TIMEOUT_SEC:-300}"
				;;
			*)
				FIX_TARGET="Fix the smallest set of files cited in the failure excerpt."
				FIX_VALIDATE=""
				;;
			esac
			if [ "$FAILURE_KIND" = "render-diff" ] && [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-render-diff-brief.sh" ]; then
				"$PROJECT_DIRECTORY/scripts/goal21-gate-render-diff-brief.sh" \
					"${GOAL21_RENDER_DIFF_ANALYSIS:-/tmp/goal21-render-diff-analysis}" \
					"$FAIL_LOG" >/dev/null 2>&1 || true
			fi
			postfix_passed=0
			if [ "$FAILURE_KIND" = "render-diff" ] \
				&& [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-auto-fix-render-diff.sh" ]; then
				echo "goal21 gate: auto-sync render-diff dispositions"
				AUTO_FIX_RC=0
				"$PROJECT_DIRECTORY/scripts/goal21-gate-auto-fix-render-diff.sh" || AUTO_FIX_RC=$?
				if [ "$AUTO_FIX_RC" -eq 0 ]; then
					echo "goal21 gate: auto-sync applied safe disposition updates"
				else
					echo "goal21 gate: auto-sync incomplete — agent may need to review draft" >&2
				fi
				"$PROJECT_DIRECTORY/scripts/goal21-gate-render-diff-brief.sh" \
					"${GOAL21_RENDER_DIFF_ANALYSIS:-/tmp/goal21-render-diff-analysis}" \
					"$FAIL_LOG" >/dev/null 2>&1 || true
				if GOAL21_GATE_FAILURE_TYPE="$FAILURE_KIND" \
					"$PROJECT_DIRECTORY/scripts/goal21-gate-postfix-check.sh" "$FAILURE_KIND"; then
					echo "goal21 gate: postfix PASS after auto-sync — next full gate round"
					postfix_passed=1
				fi
			fi
			# Skip fix agent when only stale/missing keys remain but brief is empty (re-analyze first).
			if [ "$FAILURE_KIND" = "render-diff" ] && [ "$postfix_passed" -ne 1 ] \
				&& [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-proactive-render-diff.sh" ]; then
				BRIEF="${GOAL21_RENDER_DIFF_BRIEF:-/tmp/goal21-render-diff-brief.txt}"
				if [ ! -s "$BRIEF" ] || ! rg -q 'missing dispositions|stale dispositions|non-aligned' "$BRIEF" 2>/dev/null; then
					echo "goal21 gate: empty/stale brief — retry proactive heal before fix agent"
					if "$PROJECT_DIRECTORY/scripts/goal21-gate-proactive-render-diff.sh"; then
						postfix_passed=1
					fi
					"$PROJECT_DIRECTORY/scripts/goal21-gate-render-diff-brief.sh" \
						"${GOAL21_RENDER_DIFF_ANALYSIS:-/tmp/goal21-render-diff-analysis}" \
						"$FAIL_LOG" >/dev/null 2>&1 || true
				fi
			fi
			if [ "$postfix_passed" -eq 1 ]; then
				continue
			fi
			# Skip fix agent when targeted postfix already passes (e.g. misclassified stale fail log).
			if GOAL21_GATE_FAILURE_TYPE="$FAILURE_KIND" \
				"$PROJECT_DIRECTORY/scripts/goal21-gate-postfix-check.sh" "$FAILURE_KIND"; then
				echo "goal21 gate: postfix PASS (${FAILURE_KIND}) before fix agent — next full gate round"
				continue
			fi
			if [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-mechanical-fix.sh" ]; then
				echo "goal21 gate: mechanical fix for ${FAILURE_KIND}"
				if "$PROJECT_DIRECTORY/scripts/goal21-gate-mechanical-fix.sh" "$FAILURE_KIND"; then
					if GOAL21_GATE_FAILURE_TYPE="$FAILURE_KIND" \
						"$PROJECT_DIRECTORY/scripts/goal21-gate-postfix-check.sh" "$FAILURE_KIND"; then
						echo "goal21 gate: postfix PASS after mechanical fix — next full gate round"
						continue
					fi
				fi
			fi
			postfix_try=0
			while [ "$postfix_try" -lt "$MAX_POSTFIX_TRIES" ]; do
				postfix_try=$((postfix_try + 1))
				echo "goal21 gate: fix attempt ${postfix_try}/${MAX_POSTFIX_TRIES} (timeout ${FIX_TIMEOUT}s, kind=${FAILURE_KIND})"
				DISPATCH_STATUS=0
				HEAD_BEFORE="$(git -C "$PROJECT_DIRECTORY" rev-parse HEAD)"
				if [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-fix-dispatch.sh" ]; then
					OUT="$("$PROJECT_DIRECTORY/scripts/goal21-gate-fix-dispatch.sh" \
						--kind "$FAILURE_KIND" \
						--task-id "$TASK_ID" \
						--round "$full_round" \
						--attempt "$postfix_try" \
						--fail-log "$FAIL_LOG" 2>&1)" || DISPATCH_STATUS=$?
				else
					PROMPT="Read $BRIEF and $SPEC. You are Goal 21 Gate FIX lane (short session).
Task ${TASK_ID} full round ${full_round} fix ${postfix_try}/${MAX_POSTFIX_TRIES}: failed (${FAILURE_KIND}).
${FIX_VALIDATE}
Target: ${FIX_TARGET}
Failure excerpt: $FAIL_LOG
Render-diff brief (if applicable): ${RENDER_DIFF_BRIEF}
Steps:
1. Read the brief/excerpt; apply the smallest fix on main.
2. If you changed src/: scripts/cadr-compile-check.sh before commit.
3. git commit -m \"fix(g21-gate): <stage-slug> (r${full_round})\"
4. Print: GOAL21_FIX_DONE task=${TASK_ID} round=${full_round}
Keep under 10 minutes; orchestrator runs postfix before the next full gate."
					OUT="$("$PROJECT_DIRECTORY/scripts/cadr-team-dispatch.sh" \
						--workspace "$PROJECT_DIRECTORY" \
						--goal gate \
						--task-key "gate-fix-${TASK_ID}-r${full_round}-p${postfix_try}" \
						--timeout "$FIX_TIMEOUT" \
						-- "$PROMPT" 2>&1)" || DISPATCH_STATUS=$?
				fi
				DISPATCH_STATUS="${DISPATCH_STATUS:-0}"
				printf '%s\n' "$OUT"
				if [ "$DISPATCH_STATUS" -eq 124 ]; then
					echo "goal21 gate: fix agent timeout on full round ${full_round} fix ${postfix_try}" >&2
				elif ! printf '%s' "$OUT" | rg -q "GOAL21_FIX_DONE task=${TASK_ID}"; then
					echo "goal21 gate: fix agent finished without GOAL21_FIX_DONE on full round ${full_round} fix ${postfix_try}" >&2
				fi
				HEAD_AFTER="$(git -C "$PROJECT_DIRECTORY" rev-parse HEAD)"
				if [ "$HEAD_AFTER" != "$HEAD_BEFORE" ]; then
					echo "goal21 gate: fix agent produced commit ${HEAD_AFTER} on full round ${full_round} fix ${postfix_try}" >&2
				else
					echo "goal21 gate: skip postfix (no commit from fix ${postfix_try}/${MAX_POSTFIX_TRIES})" >&2
					continue
				fi
				if GOAL21_GATE_FAILURE_TYPE="$FAILURE_KIND" \
					"$PROJECT_DIRECTORY/scripts/goal21-gate-postfix-check.sh" "$FAILURE_KIND"; then
					echo "goal21 gate: postfix check PASS (${FAILURE_KIND}) — next iteration runs full gate"
					postfix_passed=1
					break
				fi
				echo "goal21 gate: postfix check FAILED (${FAILURE_KIND}) — retry fix" >&2
			done
			if [ "$postfix_passed" -ne 1 ]; then
				echo "goal21 gate: postfix did not pass after ${MAX_POSTFIX_TRIES} tries — reset task ${TASK_ID} to pending (no more blind full gates)" >&2
				python3 - "$QUEUE_PATH" "$TASK_ID" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
tid = int(sys.argv[2])
for t in data["tasks"]:
    if t.get("id") == tid:
        t["status"] = "pending"
        t["branch"] = None
        break
Path(sys.argv[1]).write_text(json.dumps(data, indent=1) + "\n")
PY
				"$PROJECT_DIRECTORY/scripts/goal21-team-operator.sh" once 2>&1 || true
				exit 0
			fi
		done
		echo "goal21 gate: exhausted ${MAX_ROUNDS} rounds — reset task ${TASK_ID} to pending" >&2
		python3 - "$QUEUE_PATH" "$TASK_ID" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
tid = int(sys.argv[2])
for t in data["tasks"]:
    if t.get("id") == tid:
        t["status"] = "pending"
        t["branch"] = None
        break
Path(sys.argv[1]).write_text(json.dumps(data, indent=1) + "\n")
PY
		"$PROJECT_DIRECTORY/scripts/goal21-team-operator.sh" once 2>&1 || true
		exit 0
	fi

	DISPATCH_GOAL="21"
	if [ "$LANE" = "anchor" ]; then
		DISPATCH_GOAL="anchor"
	fi
	if [ "$LANE" = "infra" ]; then
		DISPATCH_GOAL="infra"
	fi

	OUT="$("$PROJECT_DIRECTORY/scripts/cadr-team-dispatch.sh" \
		--workspace "$AGENT_WORKSPACE" \
		--goal "$DISPATCH_GOAL" \
		--task-key "${LANE}-${TASK_ID}" \
		--timeout "${CADR_AGENT_TIMEOUT_SEC:-5400}" \
		-- "$PROMPT" 2>&1)" || DISPATCH_STATUS=$?
	DISPATCH_STATUS="${DISPATCH_STATUS:-0}"
	if [ "$DISPATCH_STATUS" -eq 124 ]; then
		echo "goal21 dispatch: timeout — reset task ${TASK_ID} to pending" >&2
		python3 - "$QUEUE_PATH" "$TASK_ID" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
tid = int(sys.argv[2])
for t in data["tasks"]:
    if t.get("id") == tid:
        t["status"] = "pending"
        t["branch"] = None
        break
Path(sys.argv[1]).write_text(json.dumps(data, indent=1) + "\n")
PY
		exit 0
	fi
	printf '%s\n' "$OUT"
	if printf '%s' "$OUT" | rg -q "GOAL21_COMPLETE task=${TASK_ID}"; then
		if [ "$LANE" = "anchor" ]; then
			if [ "$("$PROJECT_DIRECTORY/scripts/goal21-anchor-guard.sh" status)" != "committed" ]; then
				echo "goal21 dispatch: anchor incomplete — not marking task ${TASK_ID} done" >&2
				python3 - "$QUEUE_PATH" "$TASK_ID" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
task_id = int(sys.argv[2])
data = json.loads(path.read_text(encoding="utf-8"))
for task in data["tasks"]:
    if task.get("id") == task_id:
        task["status"] = "pending"
        task["branch"] = None
        break
path.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
PY
				exit 0
			fi
		fi
		if [ "$LANE" = "anchor" ] || [ "$LANE" = "infra" ]; then
			queue_py complete "$TASK_ID" "main"
		else
			queue_py complete "$TASK_ID" "$BRANCH"
		fi
		echo "goal21 dispatch: queued merge for task $TASK_ID"
	fi
	;;
dispatch-loop)
	LANE="${1:?lane}"
	INTERVAL="${2:-300}"
	while true; do
		"$0" dispatch "$LANE" || true
		sleep "$INTERVAL"
	done
	;;
*)
	echo "usage: $0 status|cleanup-worktrees|reconcile-in-progress|director-once|director-loop|dispatch|dispatch-loop" >&2
	exit 2
	;;
esac
