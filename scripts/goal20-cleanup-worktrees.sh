#!/usr/bin/env bash
# Remove Goal 20 pair/opt worktrees whose branch is already on cadr-migration.
#
# usage:
#   scripts/goal20-cleanup-worktrees.sh [--dry-run]
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$PROJECT_DIRECTORY"

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
	DRY_RUN=1
fi

MAIN_BRANCH="$(git branch --show-current)"
if [ "$MAIN_BRANCH" != "cadr-migration" ]; then
	echo "goal20 cleanup worktrees: expected cadr-migration, on $MAIN_BRANCH" >&2
	exit 1
fi

git worktree prune

removed=0
while IFS= read -r line; do
	case "$line" in
	worktree\ *)
		WT="${line#worktree }"
		;;
	branch\ refs/heads/*)
		BRANCH="${line#branch refs/heads/}"
		if [ -z "${WT:-}" ] || [ -z "${BRANCH:-}" ]; then
			continue
		fi
		case "$BRANCH" in
		pair-* | opt-*)
			SHOULD_REMOVE=0
			if git merge-base --is-ancestor "$BRANCH" HEAD 2>/dev/null; then
				SHOULD_REMOVE=1
			else
				case "$BRANCH" in
				pair-[0-9]*)
					PAIR_NUM="$(printf '%s' "$BRANCH" | sed -n 's/^pair-\([0-9][0-9]*\).*/\1/p')"
					if [ -n "$PAIR_NUM" ] && git log --oneline HEAD | rg -q "\(${PAIR_NUM}\)"; then
						SHOULD_REMOVE=1
					fi
					;;
				esac
			fi
			if [ "$SHOULD_REMOVE" = 1 ]; then
				if [ "$DRY_RUN" = 1 ]; then
					echo "would remove worktree $WT ($BRANCH merged)"
				else
					echo "goal20 cleanup: remove $WT ($BRANCH merged)"
					git worktree remove --force "$WT" 2>/dev/null || git worktree remove "$WT"
					git branch -d "$BRANCH" 2>/dev/null || true
				fi
				removed=$((removed + 1))
			fi
			;;
		esac
		WT=""
		BRANCH=""
		;;
	esac
done < <(git worktree list --porcelain)

echo "goal20 cleanup worktrees: ${removed} removed (dry_run=$DRY_RUN)"
