#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CADR="$PROJECT_DIRECTORY/cadr"

if [ ! -x "$CADR" ]; then
  echo "live TUI smoke: build ./cadr first" >&2
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

"$PROJECT_DIRECTORY/scripts/goal5-manual-tui-smoke.sh"

SMOKE_ROOT="$(mktemp -d)"
SESSION="cadr-tui-$$"
cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  rm -rf -- "$SMOKE_ROOT"
}
trap cleanup EXIT
mkdir -p "$SMOKE_ROOT/home" "$SMOKE_ROOT/project"

tmux new-session -d -s "$SESSION" -x 90 -y 28
tmux send-keys -t "$SESSION" -l \
  "cd '$SMOKE_ROOT/project' && before=\$(stty -g) && HOME='$SMOKE_ROOT/home' '$CADR' --provider deepseek --model deepseek-v4-flash; after=\$(stty -g); if [ \"\$before\" = \"\$after\" ]; then touch '$SMOKE_ROOT/terminal-restored'; fi"
tmux send-keys -t "$SESSION" Enter

attempt=0
while [ "$attempt" -lt 300 ]; do
  SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
  if printf '%s\n' "$SCREEN" | grep -Fq "session:" &&
    printf '%s\n' "$SCREEN" | grep -Fq "›"; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done

if [ "$attempt" -ge 300 ]; then
  echo "live TUI smoke: TUI did not become ready" >&2
  tmux capture-pane -t "$SESSION" -p >&2
  exit 1
fi

tmux send-keys -t "$SESSION" -l "/"
attempt=0
while [ "$attempt" -lt 20 ]; do
  SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
  if printf '%s\n' "$SCREEN" | grep -Fq "sessions"; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done

if [ "$attempt" -ge 20 ]; then
  echo "live TUI smoke: slash autocomplete popup did not render" >&2
  tmux capture-pane -t "$SESSION" -p >&2
  exit 1
fi

tmux send-keys -t "$SESSION" -l "scoped-"
attempt=0
while [ "$attempt" -lt 20 ]; do
  SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
  if printf '%s\n' "$SCREEN" | grep -Fq "/scoped-models"; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done
tmux send-keys -t "$SESSION" Tab
sleep 0.2
SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
if ! printf '%s\n' "$SCREEN" | grep -Fq "/scoped-models"; then
  echo "live TUI smoke: autocomplete selection did not apply" >&2
  printf '%s\n' "$SCREEN" >&2
  exit 1
fi

tmux send-keys -t "$SESSION" C-_
sleep 0.2
SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
if printf '%s\n' "$SCREEN" | grep -Fq "/scoped-models"; then
  echo "live TUI smoke: autocomplete undo did not restore the prefix" >&2
  printf '%s\n' "$SCREEN" >&2
  exit 1
fi
tmux send-keys -t "$SESSION" C-a C-k
sleep 0.2
SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
if printf '%s\n' "$SCREEN" | grep -Fq "› /"; then
  echo "live TUI smoke: editor prefix cleanup failed" >&2
  printf '%s\n' "$SCREEN" >&2
  exit 1
fi

tmux send-keys -t "$SESSION" -l "killringprobe"
tmux send-keys -t "$SESSION" C-w
sleep 0.2
SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
if printf '%s\n' "$SCREEN" | grep -Fq "killringprobe"; then
  echo "live TUI smoke: kill-ring deletion did not update the editor" >&2
  printf '%s\n' "$SCREEN" >&2
  exit 1
fi

tmux send-keys -t "$SESSION" C-y
sleep 0.2
SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
if ! printf '%s\n' "$SCREEN" | grep -Fq "killringprobe"; then
  echo "live TUI smoke: yank did not restore killed text" >&2
  printf '%s\n' "$SCREEN" >&2
  exit 1
fi

tmux send-keys -t "$SESSION" C-_
sleep 0.2
SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
if printf '%s\n' "$SCREEN" | grep -Fq "killringprobe"; then
  echo "live TUI smoke: undo did not revert yank" >&2
  printf '%s\n' "$SCREEN" >&2
  exit 1
fi
sleep 0.2

tmux send-keys -t "$SESSION" -l \
  "创建 hello.txt，内容严格为 hello，并读取确认。"
attempt=0
while [ "$attempt" -lt 20 ]; do
  SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
  if printf '%s\n' "$SCREEN" | grep -Fq "创建 hello.txt"; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done
if [ "$attempt" -ge 20 ]; then
  echo "live TUI smoke: first prompt did not reach the editor" >&2
  tmux capture-pane -t "$SESSION" -p >&2
  exit 1
fi
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
attempt=0
while [ "$attempt" -lt 20 ]; do
  SCREEN="$(tmux capture-pane -t "$SESSION" -p)"
  if printf '%s\n' "$SCREEN" | grep -Fq "把 hello.txt"; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done
if [ "$attempt" -ge 20 ]; then
  echo "live TUI smoke: second prompt did not reach the editor" >&2
  tmux capture-pane -t "$SESSION" -p >&2
  exit 1
fi
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

echo "live TUI smoke: autocomplete, undo, kill-ring, DeepSeek two-turn edit, resize, CJK, and terminal restore passed"
