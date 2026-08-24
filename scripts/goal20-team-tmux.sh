#!/usr/bin/env bash
# Start Goal 20 team tmux session (director + 2 pair lanes + opt).
#
# usage:
#   scripts/goal20-team-tmux.sh [session-name]
#
# Attach: tmux attach -t goal20-team
# Logs:   tmux capture-pane -t goal20-team:team.0 -p
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SESSION="${1:-goal20-team}"
WINDOW="team"
ORCH="$PROJECT_DIRECTORY/scripts/goal20-orchestrator.sh"
export CURSOR_AGENT_MODEL="${CURSOR_AGENT_MODEL:-auto}"
TARGET="$SESSION:$WINDOW"

if tmux has-session -t "$SESSION" 2>/dev/null; then
	echo "goal20 team tmux: session $SESSION already exists — attach with: tmux attach -t $SESSION"
	exit 0
fi

tmux new-session -d -s "$SESSION" -n "$WINDOW" -c "$PROJECT_DIRECTORY" \
	"export CURSOR_AGENT_MODEL=$CURSOR_AGENT_MODEL; exec $ORCH director-loop 90"

tmux split-window -h -t "$TARGET.0" -c "$PROJECT_DIRECTORY" \
	"export CURSOR_AGENT_MODEL=$CURSOR_AGENT_MODEL; exec $ORCH dispatch-loop a 300"

tmux split-window -v -t "$TARGET.0" -c "$PROJECT_DIRECTORY" \
	"export CURSOR_AGENT_MODEL=$CURSOR_AGENT_MODEL; exec $ORCH dispatch-loop b 300"

tmux split-window -v -t "$TARGET.2" -c "$PROJECT_DIRECTORY" \
	"export CURSOR_AGENT_MODEL=$CURSOR_AGENT_MODEL; exec $ORCH dispatch-loop opt 600"

tmux select-layout -t "$TARGET" tiled

echo "goal20 team tmux: started session $SESSION"
echo "  pane 0: director-loop (90s)"
echo "  pane 1: pair lane-a (300s)"
echo "  pane 2: pair lane-b (300s)"
echo "  pane 3: optimization (600s)"
echo "attach: tmux attach -t $SESSION"
