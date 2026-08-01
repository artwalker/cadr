#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SBCL_COMMAND="${SBCL:-sbcl}"
QUICKLISP_SETUP="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"

if ! command -v "$SBCL_COMMAND" >/dev/null 2>&1; then
  echo "cadr bench: SBCL is required." >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "cadr bench: python3 is required for the real-PTY cold-start measurement." >&2
  exit 2
fi

if [ ! -f "$QUICKLISP_SETUP" ]; then
  echo "cadr bench: Quicklisp setup not found at $QUICKLISP_SETUP." >&2
  exit 2
fi

if [ ! -x "$PROJECT_DIRECTORY/cadr" ]; then
  echo "cadr bench: build ./cadr first so cold-start latency measures the release image." >&2
  exit 2
fi

export CADR_BENCH_PROJECT_DIRECTORY="$PROJECT_DIRECTORY"
export QUICKLISP_SETUP

exec "$SBCL_COMMAND" --noinform --disable-debugger \
  --script "$PROJECT_DIRECTORY/scripts/goal11-bench.lisp" "$@"
