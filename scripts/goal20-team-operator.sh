#!/usr/bin/env bash
# Goal 20 team operator — one tick of advisor-side team maintenance.
#
# usage:
#   scripts/goal20-team-operator.sh once
#   scripts/goal20-team-operator.sh loop [seconds]
#
# Does NOT pair metrics itself; keeps tmux team, queue, merges, and dispatches healthy.
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
QUEUE_PATH="$PROJECT_DIRECTORY/docs/benchmarks/goal20-queue.json"
ORCH="$PROJECT_DIRECTORY/scripts/goal20-orchestrator.sh"
TMUX_SESSION="${GOAL20_TEAM_SESSION:-goal20-team}"
export CURSOR_AGENT_MODEL="${CURSOR_AGENT_MODEL:-auto}"

queue_py() {
	python3 - "$QUEUE_PATH" "$@" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
cmd = sys.argv[2]
data = json.loads(path.read_text(encoding="utf-8"))


def save() -> None:
    path.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")


def needs_pair_files(root: Path) -> list[str]:
    inv = json.loads((root / "docs/benchmarks/goal20-unpaired-paths.json").read_text())
    return [e["prefix"] for e in inv["fileRules"] if e.get("class") == "needs-pair"]


if cmd == "reset-stale":
    changed = 0
    for task in data["tasks"]:
        if task.get("status") != "in_progress":
            continue
        branch = task.get("branch")
        pair = task["pair"]
        slug = task["source"].split("/")[-1].replace(".lisp", "")
        expected = f"pair-{pair}-{slug.replace('_', '-')}"
        if branch and branch != expected:
            task["status"] = "pending"
            task["branch"] = None
            changed += 1
            continue
        # in_progress with no branch and no merge queue entry → retry
        if not branch:
            task["status"] = "pending"
            changed += 1
    if changed:
        save()
    print(changed)

elif cmd == "refill":
    root = Path(sys.argv[3])
    lanes = {
        "a": "measure-agent-tool-loop",
        "b": "measure-resource-loader",
        "c": "measure-cli-settings",
    }
    pending_by_lane = {lane: 0 for lane in lanes}
    for task in data["tasks"]:
        if task.get("status") in ("pending", "in_progress"):
            pending_by_lane[task["lane"]] = pending_by_lane.get(task["lane"], 0) + 1
    files = needs_pair_files(root)
    if not files:
        print("0")
        sys.exit(0)
    added = 0
    lane_order = ["a", "b", "c"]
    idx = 0
    while any(pending_by_lane.get(l, 0) < 2 for l in lane_order) and files:
        lane = lane_order[idx % len(lane_order)]
        idx += 1
        if pending_by_lane.get(lane, 0) >= 2:
            continue
        source = files.pop(0)
        pair = int(data.get("nextPairNum", 253))
        data["nextPairNum"] = pair + 1
        data["tasks"].append(
            {
                "pair": pair,
                "lane": lane,
                "status": "pending",
                "source": source,
                "measure": lanes[lane],
                "metric": None,
                "branch": None,
            }
        )
        pending_by_lane[lane] = pending_by_lane.get(lane, 0) + 1
        added += 1
        if added >= 6:
            break
    if added:
        save()
    print(added)

elif cmd == "goal-status":
    root = Path(sys.argv[3])
    inv = json.loads((root / "docs/benchmarks/goal20-unpaired-paths.json").read_text())
    needs = sum(1 for e in inv["fileRules"] if e.get("class") == "needs-pair")
    paired = len(inv.get("pairedMetrics", []))
    print(json.dumps({"needs_pair_files": needs, "paired_metrics": paired, "complete": needs == 0}))

else:
    raise SystemExit(f"unknown: {cmd}")
PY
}

emit_wake() {
	local head payload
	head="$(git -C "$PROJECT_DIRECTORY" rev-parse HEAD)"
	payload="$(python3 - "$PROJECT_DIRECTORY" "$head" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
head = sys.argv[2]
inv = json.loads((root / "docs/benchmarks/goal20-unpaired-paths.json").read_text())
needs = sum(1 for e in inv["fileRules"] if e.get("class") == "needs-pair")
prompt = (
    "Operate Goal 20 team per docs/acceptance/goal20-dev-executor.md: "
    "run scripts/goal20-team-operator.sh once; keep tmux goal20-team; "
    "director merge; dispatch pair lanes (cursor-agent --model auto); "
    "refill queue until needs-pair=0. Do NOT declare Goal 20 complete or G.17 met."
)
print(
    json.dumps(
        {
            "event": "operator_tick",
            "head": head,
            "needs_pair_files": needs,
            "complete": needs == 0,
            "prompt": prompt,
        }
    )
)
PY
)"
	echo "AGENT_LOOP_WAKE_goal20_team $payload"
}

operator_once() {
	cd "$PROJECT_DIRECTORY"

	# Queue claim writes are operational state — keep main mergeable.
	if git diff --quiet docs/benchmarks/goal20-queue.json 2>/dev/null; then
		:
	elif git diff --cached --quiet 2>/dev/null; then
		git add docs/benchmarks/goal20-queue.json
		git commit -m "chore(cadr-cli): sync goal20 queue state (goal 20)" >/dev/null 2>&1 || git restore docs/benchmarks/goal20-queue.json
	fi

	# Drop other incidental dirt on harness paths before director merge.
	if ! git diff --quiet || ! git diff --cached --quiet; then
		git status --short >&2
		if git diff --name-only | rg -qv '^(docs/benchmarks/goal20-queue\.json|scripts/\.goal20-harness\.lock|scripts/\.cadr-advisor-monitor\.state)$'; then
			echo "goal20 operator: main still dirty — skip director merge" >&2
		fi
	fi

	queue_py reset-stale >/dev/null || true
	"$ORCH" cleanup-worktrees 2>/dev/null || true

	if git diff --quiet && git diff --cached --quiet; then
		"$ORCH" director-once 2>&1 || true
	fi

	refilled="$(queue_py refill "$PROJECT_DIRECTORY")"
	[ "$refilled" != "0" ] && echo "goal20 operator: refilled $refilled queue tasks"

	if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
		echo "goal20 operator: starting tmux $TMUX_SESSION"
		"$PROJECT_DIRECTORY/scripts/goal20-team-tmux.sh" "$TMUX_SESSION"
	fi

	# Dispatch one pending task per pair lane if no cursor-agent child is running for that lane.
	for lane in a b c; do
		if pgrep -af "cursor-agent.*lane ${lane}" >/dev/null 2>&1 || pgrep -af "goal20-orchestrator.sh dispatch ${lane}" >/dev/null 2>&1; then
			continue
		fi
		pending="$(python3 -c "import json; d=json.load(open('$QUEUE_PATH')); print(sum(1 for t in d['tasks'] if t['lane']=='$lane' and t['status']=='pending'))")"
		if [ "$pending" -gt 0 ]; then
			echo "goal20 operator: dispatch lane $lane"
			"$ORCH" dispatch "$lane" >>"/tmp/goal20-dispatch-${lane}.log" 2>&1 &
		fi
	done

	goal="$(python3 - "$PROJECT_DIRECTORY" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
inv = json.loads((root / "docs/benchmarks/goal20-unpaired-paths.json").read_text())
needs = sum(1 for e in inv["fileRules"] if e.get("class") == "needs-pair")
print(f"needs-pair files={needs} paired_metrics={len(inv.get('pairedMetrics', []))}")
PY
)"
	echo "goal20 operator: $goal"
	emit_wake
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
