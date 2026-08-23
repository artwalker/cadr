#!/usr/bin/env bash
set -euo pipefail
CADR=/root/projects/cadr
BASELINE=$(cd "$CADR" && git rev-parse HEAD)
echo "AGENT_ADVISOR_MONITOR_START baseline=$BASELINE pid=$$"
while true; do
  sleep 120
  HEAD=$(cd "$CADR" && git rev-parse HEAD 2>/dev/null || echo "")
  DIRTY=$(cd "$CADR" && git status --porcelain -- \
    scripts/goal20-paired-paths.* \
    test/goal20-part-b-ledger-test.py \
    docs/acceptance/goal-v20-part-h.md \
    docs/acceptance/goal20-dev-executor.md \
    docs/performance.md \
    CHANGELOG.md 2>/dev/null | wc -l)
  if [ "$HEAD" != "$BASELINE" ]; then
    LOG=$(cd "$CADR" && git log --format='%h %s' "$BASELINE"..HEAD | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')
    echo "AGENT_LOOP_WAKE_advisor {\"event\":\"new_commits\",\"baseline\":\"$BASELINE\",\"head\":\"$HEAD\",\"log\":$LOG}"
    BASELINE="$HEAD"
  elif [ "$DIRTY" -gt 0 ]; then
    FILES=$(cd "$CADR" && git status --porcelain -- \
      scripts/goal20-paired-paths.* \
      test/goal20-part-b-ledger-test.py \
      docs/acceptance/goal-v20-part-h.md \
      docs/acceptance/goal20-dev-executor.md \
      docs/performance.md \
      CHANGELOG.md 2>/dev/null | head -8)
    FILES_JSON=$(echo "$FILES" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')
    echo "AGENT_LOOP_WAKE_advisor {\"event\":\"wip_pairing\",\"dirty_files\":$FILES_JSON}"
    sleep 300
  fi
done
