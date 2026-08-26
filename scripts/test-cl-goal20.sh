#!/usr/bin/env bash
# Goal 20 ledger shard of test-cl.sh (fast post-FiveAM check).
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
python3 "$PROJECT_DIRECTORY/scripts/goal20-unpaired-paths.py" --check
echo "test-cl-goal20: PASS"
