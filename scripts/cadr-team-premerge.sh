#!/usr/bin/env bash
# Fast smoke checks before director ff-merge (run in rebased worktree).
#
# usage:
#   scripts/cadr-team-premerge.sh goal20 <branch> <worktree> [--only-enforce GROUP.NAME]...
#   scripts/cadr-team-premerge.sh goal21 <branch> <worktree>
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
GOAL="${1:?goal20|goal21}"
BRANCH="${2:?branch}"
WORKTREE="${3:?worktree}"
shift 3

cd "$WORKTREE"

echo "cadr-team premerge: goal=$GOAL branch=$BRANCH worktree=$WORKTREE"

python3 "$PROJECT_DIRECTORY/scripts/baseline-anchor.py" check

if ! git show-ref --verify --quiet "refs/heads/$BRANCH"; then
	echo "cadr-team premerge: branch not found: $BRANCH" >&2
	exit 1
fi

case "$GOAL" in
goal20)
	python3 "$PROJECT_DIRECTORY/test/goal20-part-b-ledger-test.py"
	python3 "$PROJECT_DIRECTORY/scripts/goal20-unpaired-paths.py" --check
	if [ "$#" -gt 0 ]; then
		OUT="/tmp/cadr-premerge-g20-$$"
		mkdir -p "$OUT"
		# shellcheck disable=SC2086
		"$PROJECT_DIRECTORY/scripts/goal20-paired-paths.sh" --quick "$@" --out "$OUT"
		git -C "$PROJECT_DIRECTORY" restore \
			docs/benchmarks/goal20-paired-paths.json \
			docs/benchmarks/goal20-ledger.json \
			docs/benchmarks/paired \
			docs/performance.md 2>/dev/null || true
	fi
	;;
goal21)
	if [ -f "$PROJECT_DIRECTORY/test/goal21-source-parity-test.py" ]; then
		python3 "$PROJECT_DIRECTORY/test/goal21-source-parity-test.py"
	fi
	if [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-run.sh" ]; then
		GOAL21_GATE_MODE=fast "$PROJECT_DIRECTORY/scripts/goal21-gate-run.sh" \
			--fail-log /tmp/goal21-premerge-fast-fail.txt
	fi
	;;
*)
	echo "cadr-team premerge: unknown goal $GOAL" >&2
	exit 2
	;;
esac

echo "cadr-team premerge: OK"
