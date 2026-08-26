#!/usr/bin/env bash
# Proactive render-diff heal before a full gate round (~90s when captures cached).
#
# Runs analyze on cached captures, refreshes hashes, auto-syncs safe dispositions,
# then postfix-checks. Returns 0 when render-diff would pass postfix (or no work needed).
#
# usage: scripts/goal21-gate-proactive-render-diff.sh
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
RENDER_DIFF_OUTPUT="${GOAL21_RENDER_DIFF_OUTPUT:-/tmp/goal21-render-diff-output}"
RENDER_DIFF_ANALYSIS="${GOAL21_RENDER_DIFF_ANALYSIS:-/tmp/goal21-render-diff-analysis}"
PI_BASELINE_CACHE="/tmp/cadr-render-diff-pi-$(cut -d' ' -f1 "$PROJECT_DIRECTORY/BASELINE" | cut -c1-9)"

render_diff_has_cached_captures() {
	[ -d "$RENDER_DIFF_OUTPUT" ] || return 1
	local count
	count="$(ls -1 "$RENDER_DIFF_OUTPUT"/*.pi.normalized.raw 2>/dev/null | wc -l)"
	[ "${count:-0}" -gt 0 ]
}

if ! render_diff_has_cached_captures \
	&& [ -x "$PROJECT_DIRECTORY/scripts/goal21-render-diff-capture-cache.sh" ]; then
	"$PROJECT_DIRECTORY/scripts/goal21-render-diff-capture-cache.sh" restore 2>/dev/null || true
fi

if ! render_diff_has_cached_captures; then
	echo "goal21-gate-proactive-render-diff: skip (no cached captures)"
	exit 1
fi

cd "$PROJECT_DIRECTORY"
mkdir -p "$RENDER_DIFF_ANALYSIS" "$RENDER_DIFF_OUTPUT"

echo "goal21-gate-proactive-render-diff: analyze (core, cached captures)"
if ! python3 -u scripts/render-diff.py analyze \
	--pi-repo "$PROJECT_DIRECTORY" \
	--manifest test/fixtures/render-diff/scenarios.json \
	--dispositions test/fixtures/render-diff/dispositions.json \
	--tier core \
	--baseline-cache "$PI_BASELINE_CACHE" \
	--timeout 60 \
	--output "$RENDER_DIFF_OUTPUT" \
	--analysis-output "$RENDER_DIFF_ANALYSIS" >/tmp/goal21-proactive-analyze.log 2>&1; then
	echo "goal21-gate-proactive-render-diff: analyze failed (see /tmp/goal21-proactive-analyze.log)" >&2
	exit 1
fi

if [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-auto-fix-render-diff.sh" ]; then
	echo "goal21-gate-proactive-render-diff: auto-sync dispositions"
	"$PROJECT_DIRECTORY/scripts/goal21-gate-auto-fix-render-diff.sh" || true
fi

if ! python3 scripts/goal21-render-diff-audit-dispositions.py \
	--analysis "$RENDER_DIFF_ANALYSIS" >>/tmp/goal21-proactive-audit.log 2>&1; then
	echo "goal21-gate-proactive-render-diff: disposition audit failed (see /tmp/goal21-proactive-audit.log)" >&2
	exit 1
fi

if [ -x "$PROJECT_DIRECTORY/scripts/goal21-render-diff-capture-cache.sh" ]; then
	"$PROJECT_DIRECTORY/scripts/goal21-render-diff-capture-cache.sh" save >/dev/null 2>&1 || true
fi

if GOAL21_GATE_FAILURE_TYPE=render-diff \
	"$PROJECT_DIRECTORY/scripts/goal21-gate-postfix-check.sh" render-diff; then
	echo "goal21-gate-proactive-render-diff: PASS"
	exit 0
fi

echo "goal21-gate-proactive-render-diff: postfix still failing" >&2
exit 1
