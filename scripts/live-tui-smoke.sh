#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PI_CL="$PROJECT_DIRECTORY/pi-cl"

if [ ! -x "$PI_CL" ]; then
  echo "live TUI smoke: build ./pi-cl first" >&2
  exit 1
fi

if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  echo "live TUI smoke: DEEPSEEK_API_KEY is not set" >&2
  exit 2
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "live TUI smoke: tmux is required" >&2
  exit 2
fi

SMOKE_ROOT="$(mktemp -d)"
SESSION="pi-cl-tui-$$"
cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  rm -rf -- "$SMOKE_ROOT"
}
trap cleanup EXIT
mkdir -p "$SMOKE_ROOT/home" "$SMOKE_ROOT/project"

tmux new-session -d -s "$SESSION" -x 90 -y 28
tmux send-keys -t "$SESSION" -l \
  "cd '$SMOKE_ROOT/project' && before=\$(stty -g) && HOME='$SMOKE_ROOT/home' '$PI_CL' --provider deepseek --model deepseek-v4-flash; after=\$(stty -g); if [ \"\$before\" = \"\$after\" ]; then touch '$SMOKE_ROOT/terminal-restored'; fi"
tmux send-keys -t "$SESSION" Enter
sleep 1

tmux send-keys -t "$SESSION" -l \
  "创建 hello.txt，内容严格为 hello，并读取确认。"
tmux send-keys -t "$SESSION" Enter

attempt=0
while [ "$attempt" -lt 120 ]; do
  SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
  if [ -f "$SMOKE_ROOT/project/hello.txt" ] &&
    [ "$(sed -n '1p' "$SMOKE_ROOT/project/hello.txt")" = "hello" ] &&
    ! printf '%s\n' "$SCREEN" | grep -Fq "working"; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 1
done

if [ "$attempt" -ge 120 ]; then
  echo "live TUI smoke: first turn did not create hello.txt" >&2
  tmux capture-pane -t "$SESSION" -p >&2
  exit 1
fi

tmux resize-window -t "$SESSION" -x 58 -y 20
tmux send-keys -t "$SESSION" -l \
  "把 hello.txt 精确改为 hello world，再读取确认。"
tmux send-keys -t "$SESSION" Enter

attempt=0
while [ "$attempt" -lt 120 ]; do
  SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
  if [ "$(sed -n '1p' "$SMOKE_ROOT/project/hello.txt" 2>/dev/null || true)" = "hello world" ] &&
    ! printf '%s\n' "$SCREEN" | grep -Fq "working"; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 1
done

if [ "$attempt" -ge 120 ]; then
  echo "live TUI smoke: second turn did not edit hello.txt" >&2
  tmux capture-pane -t "$SESSION" -p >&2
  exit 1
fi

sleep 2
OUTPUT="$(tmux capture-pane -t "$SESSION" -p)"
if ! printf '%s\n' "$OUTPUT" | grep -Fq "hello world"; then
  echo "live TUI smoke: rendered screen lacks the verified result" >&2
  printf '%s\n' "$OUTPUT" >&2
  exit 1
fi

tmux send-keys -t "$SESSION" C-c
attempt=0
while [ "$attempt" -lt 20 ]; do
  if [ -f "$SMOKE_ROOT/terminal-restored" ]; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 1
done

if [ ! -f "$SMOKE_ROOT/terminal-restored" ]; then
  echo "live TUI smoke: terminal mode was not restored on exit" >&2
  exit 1
fi

echo "live TUI smoke: DeepSeek two-turn edit, resize, CJK, and terminal restore passed"
