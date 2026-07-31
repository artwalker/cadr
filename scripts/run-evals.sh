#!/usr/bin/env bash
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SBCL_COMMAND="${SBCL:-sbcl}"

exec "$SBCL_COMMAND" --noinform --disable-debugger \
  --script "$PROJECT_DIRECTORY/scripts/run-evals.lisp" "$@"
