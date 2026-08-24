#!/usr/bin/env bash
# Goal 20 team orchestrator: queue, director merge loop, cursor-agent dispatch.
#
# usage:
#   scripts/goal20-orchestrator.sh status
#   scripts/goal20-orchestrator.sh cleanup-worktrees [--dry-run]
#   scripts/goal20-orchestrator.sh director-once
#   scripts/goal20-orchestrator.sh director-loop [seconds]
#   scripts/goal20-orchestrator.sh dispatch <lane>   # a|b|c|opt
#   scripts/goal20-orchestrator.sh dispatch-loop <lane> [seconds]
#   scripts/goal20-orchestrator.sh enqueue-merge <branch> [--only-enforce GROUP.NAME]...
#
# Queue file: docs/benchmarks/goal20-queue.json
# Brief: docs/acceptance/goal20-dev-executor.md
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
QUEUE_PATH="$PROJECT_DIRECTORY/docs/benchmarks/goal20-queue.json"
BRIEF="$PROJECT_DIRECTORY/docs/acceptance/goal20-dev-executor.md"
AGENT_BIN="${CURSOR_AGENT_BIN:-cursor-agent}"
AGENT_MODEL="${CURSOR_AGENT_MODEL:-auto}"

queue_py() {
	python3 - "$QUEUE_PATH" "$@" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
command = sys.argv[2]
data = json.loads(path.read_text(encoding="utf-8"))


def save() -> None:
    path.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")


def next_task(lane: str):
    for task in data["tasks"]:
        if task.get("lane") == lane and task.get("status") == "pending":
            return task
    return None


if command == "status":
    pending = sum(1 for t in data["tasks"] if t.get("status") == "pending")
    inprog = sum(1 for t in data["tasks"] if t.get("status") == "in_progress")
    done = sum(1 for t in data["tasks"] if t.get("status") == "done")
    print(
        f"goal20 queue: nextPair={data.get('nextPairNum')} "
        f"pending={pending} in_progress={inprog} done={done} "
        f"mergeQueue={len(data.get('mergeQueue', []))}"
    )
    for task in data["tasks"]:
        if task.get("status") != "done":
            metric = task.get("metric") or "TBD"
            print(
                f"  pair {task['pair']:>3} lane={task['lane']} "
                f"{task['status']:12} {metric}"
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

elif command == "complete":
    pair = int(sys.argv[3])
    branch = sys.argv[4]
    metric = sys.argv[5] if len(sys.argv) > 5 else None
    for task in data["tasks"]:
        if task.get("pair") == pair:
            task["status"] = "done"
            task["branch"] = branch
            if metric:
                task["metric"] = metric
            break
    data.setdefault("mergeQueue", []).append({"branch": branch, "pair": pair})
    save()

elif command == "pop-merge":
    queue = data.get("mergeQueue", [])
    if not queue:
        sys.exit(2)
    item = queue.pop(0)
    save()
    print(json.dumps(item))

elif command == "add-task":
    lane = sys.argv[3]
    source = sys.argv[4]
    measure = sys.argv[5]
    pair = int(data.get("nextPairNum", 253))
    data["nextPairNum"] = pair + 1
    data["tasks"].append(
        {
            "pair": pair,
            "lane": lane,
            "status": "pending",
            "source": source,
            "measure": measure,
            "metric": None,
            "branch": None,
        }
    )
    save()
    print(pair)

else:
    raise SystemExit(f"unknown queue command: {command}")
PY
}

require_clean_main() {
	if ! git diff --quiet || ! git diff --cached --quiet; then
		echo "goal20 orchestrator: main worktree dirty" >&2
		git status --short >&2
		exit 1
	fi
}

cmd="${1:-status}"
shift || true

case "$cmd" in
status)
	"$0" cleanup-worktrees --dry-run 2>/dev/null || true
	queue_py status
	git -C "$PROJECT_DIRECTORY" log -1 --oneline
	;;
cleanup-worktrees)
	"$PROJECT_DIRECTORY/scripts/goal20-cleanup-worktrees.sh" "$@"
	;;
director-once)
	cd "$PROJECT_DIRECTORY"
	require_clean_main
	if MERGE_JSON="$(queue_py pop-merge 2>/dev/null || true)" && [ -n "$MERGE_JSON" ]; then
		BRANCH="$(printf '%s' "$MERGE_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["branch"])')"
		PAIR="$(printf '%s' "$MERGE_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["pair"])')"
		echo "goal20 director: merge queue $BRANCH (pair $PAIR)"
		# shellcheck disable=SC2086
		"$PROJECT_DIRECTORY/scripts/goal20-director-merge.sh" "$BRANCH" "$@"
	elif true; then
		# Only auto-merge branches explicitly queued by pairing agents.
		# Do not scan orphan pair-* branches (stale worktrees caused pair-229 conflicts).
		echo "goal20 director: nothing in merge queue"
	fi
	"$0" cleanup-worktrees
	;;
director-loop)
	INTERVAL="${1:-90}"
	while true; do
		"$0" director-once || true
		sleep "$INTERVAL"
	done
	;;
dispatch)
	LANE="${1:?lane required (a|b|c|opt)}"
	shift || true
	cd "$PROJECT_DIRECTORY"
	TASK_JSON="$(queue_py claim "$LANE")" || {
		echo "goal20 dispatch: no pending task for lane $LANE"
		exit 0
	}
	PAIR="$(printf '%s' "$TASK_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["pair"])')"
	SOURCE="$(printf '%s' "$TASK_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["source"])')"
	MEASURE="$(printf '%s' "$TASK_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["measure"])')"
	SLUG="$(printf '%s' "$SOURCE" | sed 's|.*/||; s/\.lisp$//; s/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]')"
	BRANCH="pair-${PAIR}-${SLUG}"
	WORKTREE="/tmp/pair${PAIR}-wt"

	PROMPT="Read $BRIEF. You are Goal 20 Pairing lane ${LANE}.
Task: pair needs-pair code in ${SOURCE} (Pair ${PAIR}).
Harness region: ${MEASURE} — do not collide with other lanes.
Steps:
1. scripts/goal20-pair-worktree.sh ${PAIR} ${SLUG}
2. Wire goal20-paired-paths.{lisp,mjs,py}, record, write, ledger test, Part H
3. scripts/goal20-paired-paths.sh --quick --only-enforce <new.metric>
4. scripts/goal20-paired-paths.sh --only-enforce <new.metric>
5. python3 test/goal20-part-b-ledger-test.py
6. git commit -m \"feat(cadr-cli): pair <group>.<metric> (${PAIR})\"
7. Print: GOAL20_COMPLETE pair=${PAIR} branch=${BRANCH} metric=<group>.<metric>
Never edit harness on main checkout. Never optimize in pair commit."

	if [ "$LANE" = "opt" ]; then
		PROMPT="Read $BRIEF and docs/benchmarks/goal20-paired-over-1x.md. You are Optimization team.
Pick the hottest over-1x metric not yet optimized this session (sorted_ids, enable_all, oauth_selector_ui_state).
Use scripts/goal20-opt-worktree.sh. Only src/. perf commit. --quick on affected metrics."
		"$AGENT_BIN" --print --force --trust --model "$AGENT_MODEL" \
			--workspace "$PROJECT_DIRECTORY" \
			-p "$PROMPT"
		exit 0
	fi

	OUT="$("$AGENT_BIN" --print --force --trust --model "$AGENT_MODEL" \
		--workspace "$PROJECT_DIRECTORY" \
		-p "$PROMPT" 2>&1)" || true
	printf '%s\n' "$OUT"
	if printf '%s' "$OUT" | rg -q 'GOAL20_COMPLETE pair='"${PAIR}"; then
		METRIC="$(printf '%s' "$OUT" | sed -n 's/.*metric=\([^[:space:]]*\).*/\1/p' | tail -1)"
		queue_py complete "$PAIR" "$BRANCH" "$METRIC"
		echo "goal20 dispatch: queued merge $BRANCH"
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
enqueue-merge)
	BRANCH="${1:?branch required}"
	shift
	PAIR="$(printf '%s' "$BRANCH" | sed -n 's/^pair-\([0-9][0-9]*\).*/\1/p')"
	queue_py complete "${PAIR:-0}" "$BRANCH"
	echo "goal20 orchestrator: enqueued $BRANCH"
	;;
*)
	echo "usage: $0 status|cleanup-worktrees|director-once|director-loop|dispatch|dispatch-loop|enqueue-merge" >&2
	exit 2
	;;
esac
