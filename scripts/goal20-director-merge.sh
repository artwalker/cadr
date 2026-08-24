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
	echo "goal20 director merge: main worktree dirty; stash or commit foreign changes first" >&2
	git status --short >&2
	exit 1
fi

LISP_LINES_BEFORE="$(wc -l < scripts/goal20-paired-paths.lisp)"

echo "goal20 director merge: cherry-pick $PAIR_BRANCH onto $MAIN_BRANCH"
if ! git cherry-pick "$PAIR_BRANCH"; then
	echo "goal20 director merge: cherry-pick conflict — resolve ONLY in harness files you expect, then:" >&2
	echo "  git cherry-pick --continue && $0 $PAIR_BRANCH $*" >&2
	exit 1
fi

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
