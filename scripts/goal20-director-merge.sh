#!/usr/bin/env bash
# Director: merge ONE pairing branch into cadr-migration, then run Testing QA.
# Serializes harness integration — never merge two pair branches in parallel.
#
# usage:
#   scripts/goal20-director-merge.sh <pair-branch> [--only-enforce GROUP.NAME]...
#
# Resolves harness conflicts by keeping both sides' additive blocks; if lisp/mjs
# look truncated vs HEAD, abort and inspect.
set -eu

if [ "$#" -lt 1 ]; then
	echo "usage: $0 <pair-branch> [--only-enforce GROUP.NAME]..." >&2
	exit 2
fi

PAIR_BRANCH="$1"
shift

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$PROJECT_DIRECTORY"

if ! git show-ref --verify --quiet "refs/heads/$PAIR_BRANCH"; then
	echo "goal20 director merge: branch $PAIR_BRANCH not found" >&2
	exit 1
fi

"$PROJECT_DIRECTORY/scripts/goal20-team-lock.sh" acquire director

cleanup() {
	"$PROJECT_DIRECTORY/scripts/goal20-team-lock.sh" release || true
}
trap cleanup EXIT

MAIN_BRANCH="$(git branch --show-current)"
if [ "$MAIN_BRANCH" != "cadr-migration" ]; then
	echo "goal20 director merge: expected cadr-migration, on $MAIN_BRANCH" >&2
	exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
	if ! git diff --name-only | while read -r p; do
		[ -n "$p" ] || continue
		"$PROJECT_DIRECTORY/scripts/goal21-anchor-guard.sh" is-excluded-path "$p" || exit 1
	done && git diff --cached --name-only | while read -r p; do
		[ -n "$p" ] || continue
		"$PROJECT_DIRECTORY/scripts/goal21-anchor-guard.sh" is-excluded-path "$p" || exit 1
	done; then
		echo "goal20 director merge: main worktree dirty; stash or commit foreign changes first" >&2
		git status --short >&2
		exit 1
	fi
fi

LISP_LINES_BEFORE="$(wc -l < scripts/goal20-paired-paths.lisp)"

MERGE_WT="/tmp/cadr-merge-${PAIR_BRANCH//\//-}-wt"
echo "goal20 director merge: rebase+ff $PAIR_BRANCH onto cadr-migration"
if ! "$PROJECT_DIRECTORY/scripts/cadr-team-worktree.sh" ensure "$MERGE_WT" "$PAIR_BRANCH" cadr-migration; then
	echo "goal20 director merge: rebase failed — resolve in $MERGE_WT" >&2
	exit 1
fi
"$PROJECT_DIRECTORY/scripts/cadr-team-premerge.sh" goal20 "$PAIR_BRANCH" "$MERGE_WT" "$@"
if ! git merge --ff-only "$PAIR_BRANCH"; then
	echo "goal20 director merge: ff-merge failed for $PAIR_BRANCH" >&2
	exit 1
fi
git worktree remove --force "$MERGE_WT" 2>/dev/null || true

LISP_LINES_AFTER="$(wc -l < scripts/goal20-paired-paths.lisp)"
if [ "$LISP_LINES_AFTER" -lt $((LISP_LINES_BEFORE - 50)) ]; then
	echo "goal20 director merge: ABORT — goal20-paired-paths.lisp shrank ${LISP_LINES_BEFORE}→${LISP_LINES_AFTER} (likely stomp)" >&2
	git cherry-pick --abort
	exit 1
fi

echo "goal20 director merge: testing team QA"
# shellcheck disable=SC2086
"$PROJECT_DIRECTORY/scripts/goal20-team-qa.sh" "$@"

echo "goal20 director merge: OK $(git log -1 --oneline)"
