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
		if rg -q 'semantic screen pair drifted' "$FAIL_LOG" 2>/dev/null; then
			echo "validation errors:"
			rg -o 'semantic screen pair drifted[^[:space:]]* [^[:space:]]+' "$FAIL_LOG" | tail -5
		fi
		if rg -q 'terminal-protocol-only disposition cannot admit' "$FAIL_LOG" 2>/dev/null; then
			rg -o 'terminal-protocol-only disposition cannot admit[^[:space:]]* [^[:space:]]+' "$FAIL_LOG" | tail -5
		fi
		if rg -q 'render-diff: semantic screen pair drifted' "$FAIL_LOG" 2>/dev/null; then
			rg 'render-diff: semantic screen pair drifted' "$FAIL_LOG" | tail -5
		fi
		if rg -q 'render-diff: terminal-protocol-only' "$FAIL_LOG" 2>/dev/null; then
			rg 'render-diff: terminal-protocol-only' "$FAIL_LOG" | tail -5
		fi
		if rg -q 'HarnessFailure:' "$FAIL_LOG" 2>/dev/null; then
			rg 'HarnessFailure:' "$FAIL_LOG" | tail -5
		fi
		if rg -q 'render-diff analysis:' "$FAIL_LOG" 2>/dev/null; then
			rg 'render-diff analysis:' "$FAIL_LOG" | tail -1
		fi
		echo ""
	fi

	if [ -f "$ANALYSIS/pending-dispositions.json" ]; then
		python3 - "$ANALYSIS/pending-dispositions.json" <<'PY'
import json
import sys
from pathlib import Path

pending = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
error = pending.get("validationError")
if error:
    print("validationError:", error)
missing = pending.get("missing") or []
stale = pending.get("stale") or []
if missing:
    print(f"missing dispositions ({len(missing)}):")
    for key in missing[:20]:
        print(f"  {key}")
if stale:
    print(f"stale dispositions ({len(stale)}):")
    for key in stale[:20]:
        print(f"  {key}")
PY
		echo ""
	fi

	if [ -f "$ANALYSIS/summary.json" ]; then
		python3 - "$ANALYSIS/summary.json" <<'PY'
import json
import sys
from pathlib import Path

results = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
counts: dict[str, int] = {}
for row in results:
    counts[row.get("automaticDisposition", "?")] = counts.get(row.get("automaticDisposition", "?"), 0) + 1
print("disposition counts:", " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
non_aligned = [r for r in results if r.get("automaticDisposition") != "aligned"]
print(f"non-aligned: {len(non_aligned)}")
for row in non_aligned[:40]:
    print(f"  {row.get('key')}\t{row.get('automaticDisposition')}\tgeometryEqual={row.get('textGeometryEqual')}")
if len(non_aligned) > 40:
    print(f"  ... and {len(non_aligned) - 40} more")
PY
	fi

	if [ -f "${GOAL21_DISPOSITION_SYNC_REPORT:-/tmp/goal21-disposition-sync-report.json}" ]; then
		echo ""
		echo "=== disposition sync report ==="
		python3 - "${GOAL21_DISPOSITION_SYNC_REPORT:-/tmp/goal21-disposition-sync-report.json}" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(
    f"missing={len(report.get('missing', []))} stale={len(report.get('stale', []))} "
    f"autoApply={report.get('autoApplyCount', 0)} needsReview={report.get('needsReviewCount', 0)} "
    f"applied={report.get('applied', False)}"
)
for key in report.get("addedKeys", [])[:20]:
    print(f"  added {key}")
for key in report.get("removedStale", [])[:20]:
    print(f"  removed stale {key}")
PY
	fi

	if [ -f "${GOAL21_DISPOSITION_DRAFT:-/tmp/goal21-disposition-draft.json}" ]; then
		echo ""
		echo "=== disposition draft (needs review) ==="
		python3 - "${GOAL21_DISPOSITION_DRAFT:-/tmp/goal21-disposition-draft.json}" <<'PY'
import json
import sys
from pathlib import Path

draft = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for entry in draft.get("needsReview", [])[:10]:
    print(
        f"  {entry.get('scenario')}/{entry.get('checkpoint')} "
        f"dims={entry.get('dimensions')} kind={entry.get('syncKind')}"
    )
PY
	fi

	echo ""
	echo "Fix: edit test/fixtures/render-diff/dispositions.json for keys listed above."
	echo "Do NOT run render-diff.py yourself; orchestrator runs postfix checks."
} >"$BRIEF"

echo "goal21-gate-render-diff-brief: wrote $BRIEF"
cat "$BRIEF"
