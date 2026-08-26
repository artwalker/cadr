#!/usr/bin/env bash
# Mechanical check that manifest skeleton generation is wired correctly.
#
# usage: scripts/goal21-manifest-skeletons-verify.sh
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ENSURE="$PROJECT_DIRECTORY/scripts/goal21-render-diff-ensure-skeletons.py"
HOOK="$PROJECT_DIRECTORY/scripts/goal21-render-diff-on-manifest-change.sh"
AUTO_FIX="$PROJECT_DIRECTORY/scripts/goal21-gate-auto-fix-render-diff.sh"
AUDIT="$PROJECT_DIRECTORY/scripts/goal21-render-diff-audit-dispositions.py"
ANALYSIS="${GOAL21_RENDER_DIFF_ANALYSIS:-/tmp/goal21-render-diff-analysis}"

require_pattern() {
	local file="$1"
	local label="$2"
	local pattern="$3"
	if ! grep -qE "$pattern" "$file"; then
		echo "goal21-manifest-skeletons-verify: missing $label in $file" >&2
		exit 1
	fi
}

[ -f "$ENSURE" ] || {
	echo "goal21-manifest-skeletons-verify: missing $ENSURE" >&2
	exit 1
}
[ -x "$HOOK" ] || {
	echo "goal21-manifest-skeletons-verify: $HOOK not executable" >&2
	exit 1
}
[ -f "$AUTO_FIX" ] || {
	echo "goal21-manifest-skeletons-verify: missing $AUTO_FIX" >&2
	exit 1
}
[ -f "$AUDIT" ] || {
	echo "goal21-manifest-skeletons-verify: missing $AUDIT" >&2
	exit 1
}

require_pattern "$HOOK" "audit call" 'goal21-render-diff-audit-dispositions\.py'
require_pattern "$HOOK" "ensure-skeletons call" 'goal21-render-diff-ensure-skeletons\.py'
require_pattern "$AUTO_FIX" "ensure-skeletons integration" 'goal21-render-diff-ensure-skeletons\.py'
if ! grep -qF -- '--apply' "$AUTO_FIX"; then
	echo "goal21-manifest-skeletons-verify: missing ensure-skeletons --apply in $AUTO_FIX" >&2
	exit 1
fi

if [ ! -f "$ANALYSIS/summary.json" ]; then
	echo "goal21-manifest-skeletons-verify: missing $ANALYSIS/summary.json (run render-diff analyze first)" >&2
	exit 1
fi

python3 "$AUDIT" --analysis "$ANALYSIS" --validate-only
python3 "$ENSURE" --analysis "$ANALYSIS" --dry-run
"$HOOK"

echo "goal21-manifest-skeletons-verify: PASS"
