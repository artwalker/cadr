#!/usr/bin/env bash
# Summarize render-diff failures for fix agents without re-running capture.
#
# usage: scripts/goal21-gate-render-diff-brief.sh [analysis-dir] [fail-log]
# writes: /tmp/goal21-render-diff-brief.txt (override with GOAL21_RENDER_DIFF_BRIEF)
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ANALYSIS="${1:-${GOAL21_RENDER_DIFF_ANALYSIS:-/tmp/goal21-render-diff-analysis}}"
FAIL_LOG="${2:-${GOAL21_GATE_FAIL_LOG:-/tmp/goal21-gate-fail.txt}}"
BRIEF="${GOAL21_RENDER_DIFF_BRIEF:-/tmp/goal21-render-diff-brief.txt}"

{
	echo "=== render-diff failure brief ==="
	echo "analysis: $ANALYSIS"
	echo ""

	if [ -f "$FAIL_LOG" ]; then
		if rg -q 'render-diff differences lack dispositions:' "$FAIL_LOG" 2>/dev/null; then
			rg -o 'render-diff differences lack dispositions:.*' "$FAIL_LOG" | head -1
		fi
		if rg -q 'render-diff dispositions no longer describe a difference:' "$FAIL_LOG" 2>/dev/null; then
			rg -o 'render-diff dispositions no longer describe a difference:.*' "$FAIL_LOG" | head -1
		fi
		if rg -q 'HarnessFailure:' "$FAIL_LOG" 2>/dev/null; then
			rg 'HarnessFailure:' "$FAIL_LOG" | tail -5
		fi
		if rg -q 'render-diff analysis:' "$FAIL_LOG" 2>/dev/null; then
			rg 'render-diff analysis:' "$FAIL_LOG" | tail -1
		fi
		echo ""
	fi

	if [ -f "$ANALYSIS/summary.json" ]; then
		python3 - "$ANALYSIS/summary.json" <<'PY'
import json
import sys
from collections import Counter
from pathlib import Path

results = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
counts = Counter(r.get("automaticDisposition", "?") for r in results)
print("disposition counts:", " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
non_aligned = [r for r in results if r.get("automaticDisposition") != "aligned"]
print(f"non-aligned: {len(non_aligned)}")
for row in non_aligned[:40]:
    key = row.get("key", "?")
    disp = row.get("automaticDisposition", "?")
    scenario = row.get("scenarioId", row.get("scenario", ""))
    dimension = row.get("dimensionId", row.get("dimension", ""))
    checkpoint = row.get("checkpointId", row.get("checkpoint", ""))
    print(f"  {key}\t{disp}\t{scenario}/{dimension}/{checkpoint}")
if len(non_aligned) > 40:
    print(f"  ... and {len(non_aligned) - 40} more (see {sys.argv[1]})")
PY
	else
		echo "(no summary.json — capture may still be running or failed early)"
		if [ -d "$ANALYSIS" ]; then
			ls -1 "$ANALYSIS" 2>/dev/null | head -10 || true
		fi
	fi

	echo ""
	echo "Fix: edit test/fixtures/render-diff/dispositions.json for keys listed above."
	echo "Do NOT run render-diff.py yourself; orchestrator runs postfix checks."
} >"$BRIEF"

echo "goal21-gate-render-diff-brief: wrote $BRIEF"
cat "$BRIEF"
