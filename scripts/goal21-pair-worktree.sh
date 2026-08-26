#!/usr/bin/env bash
# Goal 21 implementation worktree (delegates to cadr-team-worktree).
# usage: scripts/goal21-pair-worktree.sh <task-id> <slug>
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TASK_ID="${1:?task id required}"
SLUG="${2:?slug required}"
BRANCH="g21-${TASK_ID}-${SLUG}"
WORKTREE="/tmp/g21-${TASK_ID}-wt"

exec "$PROJECT_DIRECTORY/scripts/cadr-team-worktree.sh" ensure "$WORKTREE" "$BRANCH" cadr-migration
