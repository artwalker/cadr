#!/usr/bin/env bash
# Mechanical check that CI render-diff capture cache wiring is intact.
#
# usage: scripts/goal21-ci-capture-cache-verify.sh
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CI="$PROJECT_DIRECTORY/.github/workflows/ci.yml"
VERIFY="$PROJECT_DIRECTORY/scripts/verify.sh"
GATE_RUN="$PROJECT_DIRECTORY/scripts/goal21-gate-run.sh"
CACHE="$PROJECT_DIRECTORY/scripts/goal21-render-diff-capture-cache.sh"

require_pattern() {
	local file="$1"
	local label="$2"
	local pattern="$3"
	if ! grep -qE "$pattern" "$file"; then
		echo "goal21-ci-capture-cache-verify: missing $label in $file" >&2
		exit 1
	fi
}

[ -f "$CI" ] || { echo "goal21-ci-capture-cache-verify: missing $CI" >&2; exit 1; }
[ -x "$CACHE" ] || { echo "goal21-ci-capture-cache-verify: $CACHE not executable" >&2; exit 1; }

require_pattern "$CI" "cache restore step" 'actions/cache/restore'
require_pattern "$CI" "cache save step" 'actions/cache/save'
require_pattern "$CI" "BASELINE cache key" "hashFiles\\('BASELINE'\\)"
require_pattern "$CI" "GOAL21_RENDER_DIFF_OUTPUT" 'GOAL21_RENDER_DIFF_OUTPUT'
require_pattern "$CI" "capture-cache restore" 'goal21-render-diff-capture-cache.sh restore'
require_pattern "$CI" "capture-cache save" 'goal21-render-diff-capture-cache.sh save'
require_pattern "$VERIFY" "GOAL21_RENDER_DIFF_OUTPUT" 'GOAL21_RENDER_DIFF_OUTPUT'
require_pattern "$VERIFY" "GOAL21_RENDER_DIFF_ANALYSIS" 'GOAL21_RENDER_DIFF_ANALYSIS'
require_pattern "$VERIFY" "cached capture analyze branch" 'render_diff_has_cached_captures'
require_pattern "$GATE_RUN" "gate-run exports render-diff output" 'export GOAL21_RENDER_DIFF_OUTPUT'
require_pattern "$GATE_RUN" "gate-run exports render-diff analysis" 'export GOAL21_RENDER_DIFF_ANALYSIS'
require_pattern "$GATE_RUN" "gate-run warm analyze hook" 'maybe_warm_render_diff_analysis'

"$CACHE" status

if [ -d "$PROJECT_DIRECTORY/.cache/render-diff-captures" ]; then
	tmp_out="$(mktemp -d)"
	tmp_analysis="$(mktemp -d)"
	trap 'rm -rf -- "$tmp_out" "$tmp_analysis"' EXIT
	GOAL21_RENDER_DIFF_OUTPUT="$tmp_out" \
		GOAL21_RENDER_DIFF_ANALYSIS="$tmp_analysis" \
		"$CACHE" restore
	count="$(ls -1 "$tmp_out"/*.pi.normalized.raw 2>/dev/null | wc -l)"
	if [ "${count:-0}" -eq 0 ]; then
		echo "goal21-ci-capture-cache-verify: restore produced no captures" >&2
		exit 1
	fi
	echo "goal21-ci-capture-cache-verify: restore roundtrip ok ($count captures)"
fi

echo "goal21-ci-capture-cache-verify: PASS"
