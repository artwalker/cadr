#!/usr/bin/env bash
set -eu

if [ "${1:-}" = "--help" ]; then
  echo "Usage: ./scripts/goal5-manual-tui.sh"
  echo "Run directly in Kitty/iTerm2, not through tmux, for image validation."
  echo "Keys: f toggles the capturing overlay; i toggles image fallback; q exits."
  exit 0
fi

if [ "$#" -ne 0 ]; then
  echo "goal5 manual TUI: unexpected argument: $1" >&2
  exit 2
fi

if [ ! -t 0 ] || [ ! -t 1 ]; then
  echo "goal5 manual TUI: interactive stdin and stdout are required" >&2
  exit 2
fi

SBCL_COMMAND="${SBCL:-sbcl}"
QUICKLISP_SETUP="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"
PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if ! command -v "$SBCL_COMMAND" >/dev/null 2>&1; then
  echo "goal5 manual TUI: SBCL is required" >&2
  exit 2
fi

if [ ! -f "$QUICKLISP_SETUP" ]; then
  echo "goal5 manual TUI: Quicklisp setup not found at $QUICKLISP_SETUP" >&2
  exit 2
fi

exec "$SBCL_COMMAND" --noinform --disable-debugger \
  --load "$QUICKLISP_SETUP" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-tui.asd\"))" \
  --eval '(asdf:load-system "cadr-tui/tests")' \
  --eval '(cadr-tui/tests:run-goal5-manual-acceptance)' \
  --quit
