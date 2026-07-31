#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SBCL_COMMAND="${SBCL:-sbcl}"
PYTHON_COMMAND="${PYTHON:-python3}"
QUICKLISP_SETUP="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"

if ! command -v "$SBCL_COMMAND" >/dev/null 2>&1; then
  echo "goal9 A2 PTY lifecycle: SBCL is required" >&2
  exit 2
fi

if ! command -v "$PYTHON_COMMAND" >/dev/null 2>&1; then
  echo "goal9 A2 PTY lifecycle: Python 3 is required" >&2
  exit 2
fi

if ! command -v stty >/dev/null 2>&1; then
  echo "goal9 A2 PTY lifecycle: stty is required" >&2
  exit 2
fi

if [ ! -f "$QUICKLISP_SETUP" ]; then
  echo "goal9 A2 PTY lifecycle: Quicklisp setup not found at $QUICKLISP_SETUP" >&2
  exit 2
fi

exec "$PYTHON_COMMAND" \
  -B \
  "$PROJECT_DIRECTORY/scripts/goal9-a2-pty-driver.py" \
  --project "$PROJECT_DIRECTORY" \
  --sbcl "$SBCL_COMMAND" \
  --quicklisp "$QUICKLISP_SETUP"
