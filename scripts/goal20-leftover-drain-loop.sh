#!/usr/bin/env bash
# Goal 20 serial leftover drain heartbeat for Cursor /loop (local monitored shell).
#
# Emits AGENT_LOOP_TICK_goal20 with a JSON payload (dynamic next PR + prompt).
# The bash loop is wake-only; the agent session executes drain work.
#
# usage:
#   scripts/goal20-leftover-drain-loop.sh [interval_seconds]
#   GOAL20_DRAIN_INTERVAL=1800 scripts/goal20-leftover-drain-loop.sh
#
# Arm with notify_on_output regex: ^AGENT_LOOP_TICK_goal20
# Run scripts/goal20-leftover-drain-status.py prompt once immediately after arming.
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INTERVAL="${1:-${GOAL20_DRAIN_INTERVAL:-1800}}"
STATUS="$PROJECT_DIRECTORY/scripts/goal20-leftover-drain-status.py"

if [ ! -x "$STATUS" ] && [ -f "$STATUS" ]; then
	chmod +x "$STATUS"
fi

echo "AGENT_LOOP_GOAL20_DRAIN_START interval=${INTERVAL}s pid=$$ head=$(git -C "$PROJECT_DIRECTORY" rev-parse --short HEAD 2>/dev/null || echo none)"

while true; do
	sleep "$INTERVAL"
	python3 "$STATUS" emit-tick | while IFS= read -r payload; do
		printf 'AGENT_LOOP_TICK_goal20 %s\n' "$payload"
	done
done
