#!/usr/bin/env bash
# Auto-sync render-diff dispositions from analysis artifacts.
#
# usage: scripts/goal21-gate-auto-fix-render-diff.sh [--dry-run]
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ANALYSIS="${GOAL21_RENDER_DIFF_ANALYSIS:-/tmp/goal21-render-diff-analysis}"
DISPOSITIONS="$PROJECT_DIRECTORY/test/fixtures/render-diff/dispositions.json"
DRY_RUN=0

while [ "$#" -gt 0 ]; do
	case "$1" in
	--dry-run)
		DRY_RUN=1
		shift
		;;
	*)
		echo "usage: $0 [--dry-run]" >&2
		exit 2
		;;
	esac
done

if [ ! -f "$ANALYSIS/summary.json" ]; then
	echo "goal21-gate-auto-fix-render-diff: no analysis summary at $ANALYSIS/summary.json" >&2
	echo "goal21-gate-auto-fix-render-diff: trying hash refresh from capture artifacts" >&2
fi

if [ -f "$PROJECT_DIRECTORY/scripts/goal21-gate-refresh-disposition-hashes.py" ]; then
	python3 "$PROJECT_DIRECTORY/scripts/goal21-gate-refresh-disposition-hashes.py" \
		--analysis "$ANALYSIS" --dispositions "$DISPOSITIONS" || true
	if [ "$DRY_RUN" -eq 0 ] && ! git -C "$PROJECT_DIRECTORY" diff --quiet -- "$DISPOSITIONS"; then
		git -C "$PROJECT_DIRECTORY" add "$DISPOSITIONS"
		git -C "$PROJECT_DIRECTORY" commit -m "fix(g21-gate): refresh render-diff disposition hashes (auto)"
		echo "goal21-gate-auto-fix-render-diff: committed hash refresh"
	fi
fi

if [ ! -f "$ANALYSIS/summary.json" ]; then
	echo "goal21-gate-auto-fix-render-diff: no summary.json for pattern sync" >&2
	if git -C "$PROJECT_DIRECTORY" diff --quiet -- "$DISPOSITIONS" 2>/dev/null; then
		exit 2
	fi
	exit 0
fi

SYNC_ARGS=(--analysis "$ANALYSIS" --dispositions "$DISPOSITIONS")
if [ "$DRY_RUN" -eq 1 ]; then
	SYNC_ARGS+=(--dry-run)
else
	SYNC_ARGS+=(--auto-apply)
fi

set +e
SYNC_OUT="$(python3 "$PROJECT_DIRECTORY/scripts/goal21-render-diff-sync-dispositions.py" "${SYNC_ARGS[@]}" 2>&1)"
SYNC_RC=$?
set -e
printf '%s\n' "$SYNC_OUT"

if [ "$DRY_RUN" -eq 1 ]; then
	exit "$SYNC_RC"
fi

if git -C "$PROJECT_DIRECTORY" diff --quiet -- "$DISPOSITIONS"; then
	echo "goal21-gate-auto-fix-render-diff: no disposition changes to commit"
	exit "$SYNC_RC"
fi

git -C "$PROJECT_DIRECTORY" add "$DISPOSITIONS"
git -C "$PROJECT_DIRECTORY" commit -m "fix(g21-gate): sync render-diff dispositions (auto)"
echo "goal21-gate-auto-fix-render-diff: committed disposition sync"
exit "$SYNC_RC"
