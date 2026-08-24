#!/usr/bin/env bash
# Pairing Team: create an isolated worktree for ONE metric. Never edit harness on
# cadr-migration main checkout — only inside the worktree until director merges.
#
# usage:
#   scripts/goal20-pair-worktree.sh <pair-num> <metric_slug> [base_ref]
#
# example:
#   scripts/goal20-pair-worktree.sh 239 scoped_models_selector_persist
set -eu

if [ "$#" -lt 2 ]; then
	echo "usage: $0 <pair-num> <metric_slug> [base_ref]" >&2
	exit 2
fi

PAIR_NUM="$1"
METRIC_SLUG="$2"
BASE_REF="${3:-cadr-migration}"
PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BRANCH="pair-${PAIR_NUM}-${METRIC_SLUG//_/-}"
WORKTREE="/tmp/pair${PAIR_NUM}-wt"

cd "$PROJECT_DIRECTORY"

if git worktree list --porcelain | rg -q "^worktree $WORKTREE$"; then
	echo "goal20 pair worktree: already exists at $WORKTREE (branch $(git -C "$WORKTREE" branch --show-current))" >&2
	exit 1
fi

git worktree add "$WORKTREE" -b "$BRANCH" "$BASE_REF"

cat <<EOF
goal20 pair worktree ready
  path:   $WORKTREE
  branch: $BRANCH
  metric: cli_selectors.${METRIC_SLUG}

Pairing team rules:
  1. Edit ONLY inside $WORKTREE until freeze + commit on $BRANCH.
  2. Wire ALL of: goal20-paired-paths.{lisp,mjs,py}, record, write, ledger test.
  3. py METRICS tuple MUST include ${METRIC_SLUG} (Pair 216 lesson).
  4. Quick then freeze; bump ceiling on first freeze fail only; no optimize.
  5. Do NOT touch $PROJECT_DIRECTORY/scripts/goal20-paired-paths.* on main checkout.
  6. Tell director to merge: scripts/goal20-director-merge.sh $BRANCH

EOF
