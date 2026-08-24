#!/usr/bin/env bash
# Start Goal 20 team tmux session (director + 2 pair lanes + opt).
#
# usage:
#   scripts/goal20-team-tmux.sh [session-name]
#
# Attach: tmux attach -t goal20-team
# Logs:   tmux capture-pane -t goal20-team:director -p
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SESSION="${1:-goal20-team}"
ORCH="$PROJECT_DIRECTORY/scripts/goal20-orchestrator.sh"

if tmux has-session -t "$SESSION" 2>/dev/null; then
	echo "goal20 team tmux: session $SESSION already exists — attach with: tmux attach -t $SESSION"
	exit 0
fi

tmux new-session -d -s "$SESSION" -n team -c "$PROJECT_DIRECTORY"
tmux send-keys -t "$SESSION:0.0" "export CURSOR_AGENT_MODEL=auto; $ORCH director-loop 90" Enter

tmux split-window -h -t "$SESSION:0" -c "$PROJECT_DIRECTORY"
tmux send-keys -t "$SESSION:0.1" "export CURSOR_AGENT_MODEL=auto; $ORCH dispatch-loop a 300" Enter

tmux split-window -v -t "$SESSION:0.1" -c "$PROJECT_DIRECTORY"
tmux send-keys -t "$SESSION:0.2" "export CURSOR_AGENT_MODEL=auto; $ORCH dispatch-loop b 300" Enter

tmux select-pane -t "$SESSION:0.0"
tmux split-window -v -t "$SESSION:0.0" -c "$PROJECT_DIRECTORY"
tmux send-keys -t "$SESSION:0.3" "export CURSOR_AGENT_MODEL=auto; $ORCH dispatch-loop opt 600" Enter

tmux select-layout -t "$SESSION:0" tiled
tmux rename-window -t "$SESSION:0" team

echo "goal20 team tmux: started session $SESSION"
echo "  pane 0: director-loop (90s)"
echo "  pane 1: pair lane-a (300s)"
echo "  pane 2: pair lane-b (300s)"
echo "  pane 3: optimization (600s)"
echo "attach: tmux attach -t $SESSION"
