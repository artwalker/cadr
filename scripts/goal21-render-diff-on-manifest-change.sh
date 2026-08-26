#!/usr/bin/env bash
# Run after scenarios.json changes: audit manifest coverage and report skeleton needs.
#
# usage: scripts/goal21-render-diff-on-manifest-change.sh
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ANALYSIS="${GOAL21_RENDER_DIFF_ANALYSIS:-/tmp/goal21-render-diff-analysis}"

cd "$PROJECT_DIRECTORY"
python3 scripts/goal21-render-diff-audit-dispositions.py --analysis "$ANALYSIS"
if [ -f "$ANALYSIS/summary.json" ]; then
	python3 scripts/goal21-render-diff-ensure-skeletons.py --analysis "$ANALYSIS"
fi
