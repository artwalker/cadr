#!/usr/bin/env bash
# Shared worktree lifecycle for cadr team lanes (idempotent, rebase-aware).
# stdout: worktree path only (last line). All git chatter goes to stderr.
#
# usage:
#   scripts/cadr-team-worktree.sh ensure <worktree-path> <branch> <base-ref>
#   scripts/cadr-team-worktree.sh rebase <worktree-path> <base-ref>
#   scripts/cadr-team-worktree.sh path-for-branch <branch>
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CMD="${1:-}"
shift || true

git_quiet() {
	"$@" 1>&2
}

worktree_for_branch() {
	local branch="$1"
	git -C "$PROJECT_DIRECTORY" worktree list --porcelain | awk -v want="$branch" '
		/^worktree / { wt=$2 }
		/^branch refs\/heads\// {
			sub(/^branch refs\/heads\//, "", $0)
			if ($0 == want) print wt
		}
	'
}

ensure_worktree() {
	local wt="$1"
	local branch="$2"
	local base="$3"
	local existing

	cd "$PROJECT_DIRECTORY"
	existing="$(worktree_for_branch "$branch")"
	if [ -n "$existing" ] && [ -d "$existing" ]; then
		wt="$existing"
	elif git worktree list --porcelain | awk -v w="$wt" '$1=="worktree" && $2==w {found=1} END{exit !found}'; then
		git_quiet git -C "$wt" checkout "$branch" 2>/dev/null \
			|| git_quiet git -C "$wt" checkout -B "$branch" "$base"
	else
		if git show-ref --verify --quiet "refs/heads/$branch"; then
			git_quiet git worktree add "$wt" "$branch"
		else
			git_quiet git worktree add -b "$branch" "$wt" "$base"
		fi
	fi
	if git -C "$wt" diff --quiet && git -C "$wt" diff --cached --quiet; then
		if ! git -C "$wt" rebase "$base" >&2; then
			echo "cadr-team-worktree: rebase $branch onto $base failed (resolve in $wt)" >&2
			return 1
		fi
	else
		echo "cadr-team-worktree: dirty worktree $wt — skip rebase" >&2
	fi
	printf '%s\n' "$wt"
}

rebase_worktree() {
	local wt="$1"
	local base="$2"
	git_quiet git -C "$wt" rebase "$base"
}

case "$CMD" in
ensure)
	WT="${1:?worktree path}"
	BRANCH="${2:?branch}"
	BASE="${3:-cadr-migration}"
	ensure_worktree "$WT" "$BRANCH" "$BASE"
	;;
rebase)
	WT="${1:?worktree path}"
	BASE="${2:-cadr-migration}"
	rebase_worktree "$WT" "$BASE"
	;;
path-for-branch)
	BRANCH="${1:?branch}"
	worktree_for_branch "$BRANCH"
	;;
*)
	echo "usage: $0 ensure|rebase|path-for-branch ..." >&2
	exit 2
	;;
esac
