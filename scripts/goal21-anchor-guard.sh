#!/usr/bin/env bash
# Goal 21: verify the baseline anchor is committed on HEAD; repair drift.
#
# usage:
#   scripts/goal21-anchor-guard.sh status    # committed | dirty | mismatch
#   scripts/goal21-anchor-guard.sh ensure  # auto-commit safe anchor bump or reopen task 1
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
QUEUE_PATH="$PROJECT_DIRECTORY/docs/benchmarks/goal21-queue.json"

# Operational files — never part of the anchor bump commit.
ANCHOR_EXCLUDE=(
	docs/benchmarks/goal21-queue.json
	docs/benchmarks/goal20-queue.json
	docs/acceptance/goal20-dev-executor.md
	docs/acceptance/goal21-dev-executor.md
	docs/acceptance/goal21-pi-0843-alignment.md
	test/fixtures/render-diff/dispositions.json
	scripts/.goal20-harness.lock
	scripts/.cadr-advisor-monitor.state
	scripts/goal20-team-operator.sh
	scripts/goal21-anchor-guard.sh
	scripts/goal21-gate-fast.sh
	scripts/goal21-gate-mechanical-fix.sh
	scripts/goal21-gate-fix-dispatch.sh
	scripts/goal21-gate-proactive-render-diff.sh
	scripts/goal21-gate-postfix-check.sh
	scripts/goal21-gate-preflight.sh
	scripts/goal21-gate-classify-failure.sh
	scripts/goal21-gate-render-diff-brief.sh
	scripts/goal21-gate-auto-fix-render-diff.sh
	scripts/goal21-gate-run.sh
	scripts/goal21-render-diff-audit-dispositions.py
	scripts/goal21-render-diff-capture-cache.sh
	scripts/cadr-team-premerge.sh
	scripts/goal21-orchestrator.sh
	scripts/goal21-team-operator.sh
	scripts/goal21-director-merge.sh
	scripts/goal21-pair-worktree.sh
	scripts/goal21-team-tmux.sh
	scripts/cadr-team.sh
	scripts/cadr-team-worktree.sh
)

baseline_on_disk() {
	cut -d' ' -f1 "$PROJECT_DIRECTORY/BASELINE"
}

baseline_on_head() {
	git -C "$PROJECT_DIRECTORY" show "HEAD:BASELINE" 2>/dev/null | cut -d' ' -f1 || true
}

is_excluded() {
	local path="$1"
	local entry
	for entry in "${ANCHOR_EXCLUDE[@]}"; do
		if [ "$path" = "$entry" ]; then
			return 0
		fi
	done
	return 1
}

anchor_dirty_paths() {
	git -C "$PROJECT_DIRECTORY" diff --name-only
	git -C "$PROJECT_DIRECTORY" diff --cached --name-only
}

anchor_status() {
	local disk head
	disk="$(baseline_on_disk)"
	head="$(baseline_on_head)"
	if [ -z "$disk" ] || [ ${#disk} -ne 40 ]; then
		echo "mismatch"
		return
	fi
	if [ "$head" = "$disk" ] \
		&& git -C "$PROJECT_DIRECTORY" diff --quiet BASELINE \
		&& git -C "$PROJECT_DIRECTORY" diff --cached --quiet BASELINE 2>/dev/null; then
		local path
		while IFS= read -r path; do
			[ -n "$path" ] || continue
			if is_excluded "$path"; then
				continue
			fi
			echo "dirty"
			return
		done < <(anchor_dirty_paths | sort -u)
		echo "committed"
		return
	fi
	local path
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		if is_excluded "$path"; then
			continue
		fi
		echo "dirty"
		return
	done < <(anchor_dirty_paths | sort -u)
	if [ "$head" = "$disk" ]; then
		echo "committed"
	else
		echo "dirty"
	fi
}

reopen_anchor_task() {
	python3 - "$QUEUE_PATH" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
for task in data["tasks"]:
    if task.get("id") == 1:
        task["status"] = "pending"
        task["branch"] = None
        break
data["mergeQueue"] = [
    item for item in data.get("mergeQueue", [])
    if item.get("task") != 1 and item.get("branch") != "main"
]
path.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
print("goal21 anchor-guard: reopened task 1 (anchor)")
PY
}

commit_anchor_bump() {
	local path staged=0
	cd "$PROJECT_DIRECTORY"
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		if is_excluded "$path"; then
			continue
		fi
		git add -- "$path"
		staged=1
	done < <(anchor_dirty_paths | sort -u)
	if [ "$staged" -eq 0 ]; then
		return 1
	fi
	if ! python3 scripts/baseline-anchor.py check >/dev/null 2>&1; then
		git reset HEAD >/dev/null 2>&1 || true
		return 1
	fi
	git commit -m "chore(cadr-cli): bump baseline to pi v0.84.3 (g21)"
	echo "goal21 anchor-guard: committed anchor bump on main"
	python3 - "$QUEUE_PATH" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
for task in data["tasks"]:
    if task.get("id") == 1:
        task["status"] = "done"
        task["branch"] = "main"
        break
data["mergeQueue"] = [
    item for item in data.get("mergeQueue", [])
    if item.get("task") != 1 and item.get("branch") != "main"
]
path.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
PY
	return 0
}

cmd="${1:-status}"
case "$cmd" in
is-excluded-path)
	is_excluded "${2:-}"
	exit $?
	;;
status)
	anchor_status
	;;
ensure)
	status="$(anchor_status)"
	case "$status" in
	committed)
		;;
	dirty)
		if commit_anchor_bump; then
			:
		else
			reopen_anchor_task
		fi
		;;
	mismatch)
		reopen_anchor_task
		;;
	esac
	;;
*)
	echo "usage: $0 status|ensure|is-excluded-path <file>" >&2
	exit 2
	;;
esac
