#!/usr/bin/env bash
# Return 0 when a gate failure needs a specialist agent (not postfix/mechanical only).
#
# usage: scripts/goal21-gate-failure-needs-agent.sh [fail-log]
set -euo pipefail

FAIL_LOG="${1:-${GOAL21_GATE_FAIL_LOG:-/tmp/goal21-gate-fail.txt}}"

exec python3 - "$FAIL_LOG" <<'PY'
import json
import re
import sys
from pathlib import Path

fail_log = Path(sys.argv[1])
brief_path = Path(__import__("os").environ.get("GOAL21_RENDER_DIFF_BRIEF", "/tmp/goal21-render-diff-brief.txt"))
draft_path = Path(__import__("os").environ.get("GOAL21_DISPOSITION_DRAFT", "/tmp/goal21-disposition-draft.json"))
sync_path = Path(__import__("os").environ.get("GOAL21_DISPOSITION_SYNC_REPORT", "/tmp/goal21-disposition-sync-report.json"))
pending_path = Path(__import__("os").environ.get("GOAL21_RENDER_DIFF_ANALYSIS", "/tmp/goal21-render-diff-analysis")) / "pending-dispositions.json"

if not fail_log.is_file():
    raise SystemExit(1)

blob = fail_log.read_text(encoding="utf-8", errors="replace")

agent_patterns = (
    r"timed out waiting",
    r"cadr action \d+ failed",
    r"HarnessFailure:",
    r"semantic screen pair drifted",
    r"render-diff differences lack dispositions:",
    r"render-diff dispositions no longer describe a difference:",
    r"terminal-protocol-only disposition cannot admit",
    r"disposition lacks a specific difference note:",
    r"disposition lacks an exact semantic screen pair:",
    r"statistical liveness\s+FAIL",
    r"Goal 11 performance and stability gate\s+FAIL",
    r"pause exceeds \d+ms",
    r"sustained mixed interaction maximum pause exceeds",
)
for pattern in agent_patterns:
    if re.search(pattern, blob):
        raise SystemExit(0)

event_diff_fail = re.search(
    r"fixed-baseline event differential\s+FAIL|event differential:.*\b[1-9]\d* unresolved",
    blob,
)
if event_diff_fail:
    raise SystemExit(0)

stage_fail = re.search(
    r"fixed-baseline render differential\s+FAIL|render-diff gate \(core\)\s+FAIL",
    blob,
)
if stage_fail:
  brief = brief_path.read_text(encoding="utf-8", errors="replace") if brief_path.is_file() else ""
  if any(
      marker in brief
      for marker in (
          "pending missing",
          "pending stale",
          "hash drift",
          "validationError",
          "needsReview",
      )
  ):
      raise SystemExit(0)
  if draft_path.is_file():
      draft = json.loads(draft_path.read_text(encoding="utf-8"))
      if draft.get("needsReview") or draft.get("autoApply"):
          raise SystemExit(0)
  if sync_path.is_file():
      report = json.loads(sync_path.read_text(encoding="utf-8"))
      if report.get("needsReviewCount", 0) > 0:
          raise SystemExit(0)
  if pending_path.is_file():
      pending = json.loads(pending_path.read_text(encoding="utf-8"))
      if pending.get("missing") or pending.get("stale") or pending.get("validationError"):
          raise SystemExit(0)
  # verify reported render-diff FAIL — postfix on cached analyze is not sufficient.
  raise SystemExit(0)

raise SystemExit(1)
PY
