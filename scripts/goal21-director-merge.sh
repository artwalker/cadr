#!/usr/bin/env bash
# Cherry-pick merge one Goal 21 branch onto cadr-migration (rebase + ff-merge).
# usage: scripts/goal21-director-merge.sh <branch>
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BRANCH="${1:?branch required}"
MAIN_BRANCH="cadr-migration"

cd "$PROJECT_DIRECTORY"
BLOCKING=0
while IFS= read -r path; do
	[ -n "$path" ] || continue
	if "$PROJECT_DIRECTORY/scripts/goal21-anchor-guard.sh" is-excluded-path "$path"; then
		continue
	fi
	echo "goal21 director-merge: blocking dirty file: $path" >&2
	BLOCKING=1
done < <(git diff --name-only; git diff --cached --name-only)
if [ "$BLOCKING" -ne 0 ]; then
	echo "goal21 director-merge: main dirty" >&2
	exit 1
fi

CURRENT="$(git branch --show-current)"
if [ "$CURRENT" != "$MAIN_BRANCH" ]; then
	git checkout "$MAIN_BRANCH"
fi

if [ "$BRANCH" = "main" ]; then
	echo "goal21 director-merge: anchor/gate on main — skip merge"
	python3 scripts/baseline-anchor.py check
	exit 0
fi

if ! git show-ref --verify --quiet "refs/heads/$BRANCH"; then
	echo "goal21 director-merge: branch not found: $BRANCH" >&2
	exit 1
fi

REUSE_WT="$("$PROJECT_DIRECTORY/scripts/cadr-team-worktree.sh" path-for-branch "$BRANCH" 2>/dev/null || true)"
if [ -n "$REUSE_WT" ] && [ -d "$REUSE_WT" ]; then
	MERGE_WT="$REUSE_WT"
	REMOVE_AFTER=0
	echo "goal21 director-merge: reuse worktree $MERGE_WT"
	if ! git -C "$MERGE_WT" rebase "$MAIN_BRANCH" 1>&2; then
		echo "goal21 director-merge: rebase $BRANCH failed in $MERGE_WT" >&2
		exit 1
	fi
else
	MERGE_WT="/tmp/cadr-merge-${BRANCH//\//-}-wt"
	REMOVE_AFTER=1
	if ! "$PROJECT_DIRECTORY/scripts/cadr-team-worktree.sh" ensure "$MERGE_WT" "$BRANCH" "$MAIN_BRANCH" >/dev/null; then
		echo "goal21 director-merge: rebase $BRANCH onto $MAIN_BRANCH failed" >&2
		exit 1
	fi
fi

"$PROJECT_DIRECTORY/scripts/cadr-team-premerge.sh" goal21 "$BRANCH" "$MERGE_WT"

if ! git merge --ff-only "$BRANCH"; then
	echo "goal21 director-merge: ff-merge failed for $BRANCH" >&2
	exit 1
fi

python3 scripts/baseline-anchor.py check
if [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-run.sh" ]; then
	echo "goal21 director-merge: post-merge fast gate"
	if ! GOAL21_GATE_MODE=fast "$PROJECT_DIRECTORY/scripts/goal21-gate-run.sh" \
		--fail-log /tmp/goal21-postmerge-fast-fail.txt; then
		echo "goal21 director-merge: fast gate failed (see /tmp/goal21-postmerge-fast-fail.txt)" >&2
		exit 1
	fi
fi
if [ "$REMOVE_AFTER" -eq 1 ]; then
	git worktree remove --force "$MERGE_WT" 2>/dev/null || true
fi
echo "goal21 director-merge: merged $BRANCH (rebase+ff)"
