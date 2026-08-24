#!/usr/bin/env bash
# Optimization Team: isolated worktree for src/ perf only. Never edit harness.
#
# usage:
#   scripts/goal20-opt-worktree.sh <slug> [base_ref]
#
# example:
#   scripts/goal20-opt-worktree.sh scoped-models-item-cache
set -eu

if [ "$#" -lt 1 ]; then
	echo "usage: $0 <slug> [base_ref]" >&2
	exit 2
fi

SLUG="$1"
BASE_REF="${2:-cadr-migration}"
PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BRANCH="opt-${SLUG}"
WORKTREE="/tmp/opt-${SLUG}-wt"

cd "$PROJECT_DIRECTORY"

if git worktree list --porcelain | rg -q "^worktree $WORKTREE$"; then
	echo "goal20 opt worktree: already exists at $WORKTREE" >&2
	exit 1
fi

git worktree add "$WORKTREE" -b "$BRANCH" "$BASE_REF"

cat <<EOF
goal20 optimization worktree ready
  path:   $WORKTREE
  branch: $BRANCH

Optimization team rules:
  1. Edit ONLY src/ (mainly models.lisp). Never scripts/goal20-paired-paths.*.
  2. Commit as perf(cadr-cli): ... (goal 20) — separate from feat pair commits.
  3. Run quick gates for touched metrics before/after; ledger test must pass.
  4. Director merges opt branch AFTER pairing harness for that area is stable.

EOF
