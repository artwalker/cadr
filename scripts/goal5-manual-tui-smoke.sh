#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HARNESS="$PROJECT_DIRECTORY/scripts/goal5-manual-tui.sh"

if ! command -v tmux >/dev/null 2>&1; then
  echo "goal5 manual TUI smoke: tmux is required" >&2
  exit 2
fi

SMOKE_ROOT="$(mktemp -d)"
SESSION="cadr-goal5-manual-$$"
cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  rm -rf -- "$SMOKE_ROOT"
}
trap cleanup EXIT

tmux new-session -d -s "$SESSION" -x 90 -y 28
tmux send-keys -t "$SESSION" -l \
  "cd '$PROJECT_DIRECTORY' && before=\$(stty -g) && '$HARNESS'; after=\$(stty -g); if [ \"\$before\" = \"\$after\" ]; then touch '$SMOKE_ROOT/terminal-restored'; fi"
tmux send-keys -t "$SESSION" Enter

attempt=0
while [ "$attempt" -lt 100 ]; do
  SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
  if printf '%s\n' "$SCREEN" |
    grep -Fq "Goal 5 manual TUI acceptance" &&
    printf '%s\n' "$SCREEN" |
      grep -Fq "capturing overlay"; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done

if [ "$attempt" -ge 100 ]; then
  echo "goal5 manual TUI smoke: harness did not become ready" >&2
  tmux capture-pane -t "$SESSION" -p >&2
  exit 1
fi

tmux send-keys -t "$SESSION" -l "f"
attempt=0
while [ "$attempt" -lt 30 ]; do
  SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
  if printf '%s\n' "$SCREEN" |
    grep -Fq "input target: EDITOR"; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done
if [ "$attempt" -ge 30 ]; then
  echo "goal5 manual TUI smoke: focus did not return to editor" >&2
  printf '%s\n' "$SCREEN" >&2
  exit 1
fi
if ! printf '%s\n' "$SCREEN" |
  grep -Fq "non-capturing help"; then
  echo "goal5 manual TUI smoke: non-capturing overlay disappeared" >&2
  printf '%s\n' "$SCREEN" >&2
  exit 1
fi

tmux send-keys -t "$SESSION" -l "i"
attempt=0
while [ "$attempt" -lt 30 ]; do
  SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
  if printf '%s\n' "$SCREEN" |
    grep -Fq "forced fallback"; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done
if [ "$attempt" -ge 30 ]; then
  echo "goal5 manual TUI smoke: fallback toggle did not render" >&2
  printf '%s\n' "$SCREEN" >&2
  exit 1
fi

tmux resize-window -t "$SESSION" -x 58 -y 20
attempt=0
while [ "$attempt" -lt 30 ]; do
  SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
  if printf '%s\n' "$SCREEN" |
    grep -Fq "input target: EDITOR" &&
    printf '%s\n' "$SCREEN" |
      grep -Fq "goal5-pixel.png"; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done
if [ "$attempt" -ge 30 ]; then
  echo "goal5 manual TUI smoke: resize lost the overlay state" >&2
  printf '%s\n' "$SCREEN" >&2
  exit 1
fi

tmux send-keys -t "$SESSION" -l "q"
attempt=0
while [ "$attempt" -lt 30 ]; do
  if [ -f "$SMOKE_ROOT/terminal-restored" ]; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done

if [ ! -f "$SMOKE_ROOT/terminal-restored" ]; then
  echo "goal5 manual TUI smoke: terminal mode was not restored" >&2
  exit 1
fi

echo "goal5 manual TUI smoke: overlay focus, CJK frame, image fallback, resize, and terminal restore passed"
