#!/usr/bin/env bash
# Start Goal 20 team tmux session (director only — operator dispatches pair lanes).
#
# usage:
#   scripts/goal20-team-tmux.sh [session-name]
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SESSION="${1:-goal20-team}"
WINDOW="team"
ORCH="$PROJECT_DIRECTORY/scripts/goal20-orchestrator.sh"
export CURSOR_AGENT_MODEL="${CURSOR_AGENT_MODEL:-auto}"
TARGET="$SESSION:$WINDOW"

if tmux has-session -t "$SESSION" 2>/dev/null; then
	echo "goal20 team tmux: session $SESSION already exists"
	exit 0
fi

tmux new-session -d -s "$SESSION" -n "$WINDOW" -c "$PROJECT_DIRECTORY" \
	"export CURSOR_AGENT_MODEL=$CURSOR_AGENT_MODEL; exec $ORCH director-loop 90"

echo "goal20 team tmux: started $SESSION (director-loop only; operator dispatches pair lanes)"
