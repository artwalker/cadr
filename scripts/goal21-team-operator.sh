#!/usr/bin/env bash
# Goal 21 team operator — advisor tick for baseline alignment team.
#
# usage:
#   scripts/goal21-team-operator.sh once
#   scripts/goal21-team-operator.sh loop [seconds]
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
QUEUE_PATH="$PROJECT_DIRECTORY/docs/benchmarks/goal21-queue.json"
ORCH="$PROJECT_DIRECTORY/scripts/goal21-orchestrator.sh"
TMUX_SESSION="${GOAL21_TEAM_SESSION:-goal21-team}"
export CURSOR_AGENT_MODEL="${CURSOR_AGENT_MODEL:-auto}"

operator_once() {
	cd "$PROJECT_DIRECTORY"

	PAUSED="$(python3 -c "import json; d=json.load(open('$QUEUE_PATH')); print('yes' if d.get('paused') else 'no')")"
	if [ "$PAUSED" = "yes" ]; then
		echo "goal21 operator: paused — skip dispatch (set paused=false in goal21-queue.json to resume)"
		"$ORCH" status
		return 0
	fi

	"$PROJECT_DIRECTORY/scripts/goal21-anchor-guard.sh" ensure
	python3 "$PROJECT_DIRECTORY/scripts/cadr-team-queue.py" migrate >/dev/null 2>&1 || true
	"$ORCH" reconcile-in-progress >/dev/null 2>&1 || true

	if [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-queue-sync.sh" ]; then
		"$PROJECT_DIRECTORY/scripts/goal21-gate-queue-sync.sh" 2>&1 || true
	fi

	# Progress-based stale kill (idle agent with no verify/test-cl/commit).
	"$PROJECT_DIRECTORY/scripts/cadr-team-stale-agents.sh" once 2>&1 || true

	# Reset in_progress tasks with no running agent (stale dispatch).
	python3 - "$QUEUE_PATH" <<'PY' >/dev/null 2>&1 || true
import json, subprocess, sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
changed = 0
running = subprocess.run(["pgrep", "-af", "cursor-agent"], capture_output=True, text=True).stdout
dispatch = subprocess.run(["pgrep", "-af", "goal21-orchestrator.sh dispatch"], capture_output=True, text=True).stdout
gate_run = subprocess.run(["pgrep", "-af", "goal21-gate-run"], capture_output=True, text=True).stdout
blob = running + dispatch + gate_run


def gate_agent_active(blob_text: str) -> bool:
    patterns = (
        "Goal 21 Gate",
        "gate-fix-",
        "gate-docs-",
        "task-key gate-",
        "goal21-gate-run",
        "dispatch gate",
    )
    return any(p in blob_text for p in patterns)

for task in data["tasks"]:
    if task.get("status") != "in_progress":
        continue
    lane = task.get("lane", "")
    tid = task.get("id", "")
    if lane == "gate":
        if gate_agent_active(blob):
            continue
    if lane == "infra":
        if "Goal 21 Infra" in blob or f"dispatch infra" in blob:
            continue
    if f"lane {lane}" in blob or f"lane-{tid}" in blob or f"task={tid}" in blob:
        continue
    if f"dispatch {lane}" in blob:
        continue
    task["status"] = "pending"
    task["branch"] = None
    changed += 1
if changed:
    path.write_text(json.dumps(data, indent=1) + "\n")
    root = path.parent / "cadr-team-queues.json"
    if root.is_file():
        u = json.loads(root.read_text())
        u.setdefault("goals", {})["21"] = data
        root.write_text(json.dumps(u, indent=1) + "\n")
PY

	# Commit queue state if only queue changed.
	if git diff --quiet docs/benchmarks/goal21-queue.json 2>/dev/null; then
		:
	elif git diff --cached --quiet 2>/dev/null; then
		git add docs/benchmarks/goal21-queue.json
		git commit -m "chore(cadr-cli): sync goal21 queue state (goal 21)" >/dev/null 2>&1 \
			|| git restore docs/benchmarks/goal21-queue.json
	fi

	"$ORCH" cleanup-worktrees 2>/dev/null || true

	if git -C "$PROJECT_DIRECTORY" diff --name-only | while read -r p; do
		[ -n "$p" ] || continue
		"$PROJECT_DIRECTORY/scripts/goal21-anchor-guard.sh" is-excluded-path "$p" || exit 1
	done && git -C "$PROJECT_DIRECTORY" diff --cached --name-only | while read -r p; do
		[ -n "$p" ] || continue
		"$PROJECT_DIRECTORY/scripts/goal21-anchor-guard.sh" is-excluded-path "$p" || exit 1
	done; then
		"$ORCH" director-once 2>&1 || true
	elif git -C "$PROJECT_DIRECTORY" diff --quiet && git -C "$PROJECT_DIRECTORY" diff --cached --quiet; then
		"$ORCH" director-once 2>&1 || true
	fi

	if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
		echo "goal21 operator: starting tmux $TMUX_SESSION"
		"$PROJECT_DIRECTORY/scripts/goal21-team-tmux.sh" "$TMUX_SESSION"
	fi

	# Dispatch priority: anchor first, then parity, impl lanes, infra, gate last.
	for lane in anchor parity a b c infra; do
		if pgrep -af "cursor-agent.*Goal 21 lane ${lane}" >/dev/null 2>&1 \
			|| pgrep -af "cadr-team-dispatch.*lane-${lane}" >/dev/null 2>&1 \
			|| pgrep -af "goal21-orchestrator.sh dispatch ${lane}" >/dev/null 2>&1; then
			continue
		fi
		pending="$(python3 -c "import json; d=json.load(open('$QUEUE_PATH')); print(sum(1 for t in d['tasks'] if t['lane']=='$lane' and t['status']=='pending'))")"
		inprog="$(python3 -c "import json; d=json.load(open('$QUEUE_PATH')); print(sum(1 for t in d['tasks'] if t['lane']=='$lane' and t['status']=='in_progress'))")"
		if [ "$pending" -gt 0 ] || [ "$inprog" -gt 0 ]; then
			echo "goal21 operator: dispatch lane $lane"
			"$ORCH" dispatch "$lane" >>"/tmp/goal21-dispatch-${lane}.log" 2>&1 &
			break
		fi
	done

	# Gate lane only when impl + core infra batch (tasks 8–12) done.
	all_impl_done="$(python3 -c "
import json
d=json.load(open('$QUEUE_PATH'))
impl=[t for t in d['tasks'] if t['lane'] in ('anchor','parity','a','b','c')]
infra_core=[t for t in d['tasks'] if t['lane']=='infra' and t['id'] <= 12]
gate=[t for t in d['tasks'] if t['lane']=='gate']
impl_ok=all(t['status']=='done' for t in impl)
infra_ok=all(t['status']=='done' for t in infra_core) if infra_core else True
print('yes' if impl_ok and infra_ok and any(t['status']=='pending' for t in gate) else 'no')
")"
	gate_busy=0
	if pgrep -af "cursor-agent.*(Goal 21 Gate|gate-fix|gate-docs)" >/dev/null 2>&1 \
		|| pgrep -af "cadr-team-dispatch.*gate-" >/dev/null 2>&1 \
		|| pgrep -af "goal21-orchestrator.sh dispatch gate" >/dev/null 2>&1 \
		|| pgrep -af "goal21-gate-run\.sh" >/dev/null 2>&1; then
		gate_busy=1
	fi
	if [ "$all_impl_done" = "yes" ] && [ "$gate_busy" -eq 0 ]; then
		gate_pending="$(python3 -c "import json; d=json.load(open('$QUEUE_PATH')); print(sum(1 for t in d['tasks'] if t['lane']=='gate' and t['status']=='pending'))")"
		if [ "$gate_pending" -gt 0 ]; then
			echo "goal21 operator: dispatch lane gate"
			"$ORCH" dispatch gate >>"/tmp/goal21-dispatch-gate.log" 2>&1 &
		elif [ -f /tmp/goal21-gate-fail.txt ] \
			&& [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-dispatch-fix.sh" ] \
			&& "$PROJECT_DIRECTORY/scripts/goal21-gate-failure-needs-agent.sh" /tmp/goal21-gate-fail.txt; then
			echo "goal21 operator: dispatch gate fix specialist"
			"$PROJECT_DIRECTORY/scripts/goal21-gate-dispatch-fix.sh" >>"/tmp/goal21-dispatch-gate.log" 2>&1 &
		fi
	fi

	"$ORCH" status
}

case "${1:-once}" in
once)
	operator_once
	;;
loop)
	INTERVAL="${2:-300}"
	while true; do
		operator_once || true
		sleep "$INTERVAL"
	done
	;;
*)
	echo "usage: $0 once|loop [seconds]" >&2
	exit 2
	;;
esac
