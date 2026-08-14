#!/usr/bin/env bash
# Goal 20 Part O: sb-sprof capture for paired paths that still miss 1.0x.
# usage: scripts/goal20-profile.sh [--seconds N] [--output PATH]
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SBCL_COMMAND="${SBCL:-sbcl}"
QUICKLISP_SETUP="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"
OUTPUT_PATH="$PROJECT_DIRECTORY/docs/benchmarks/goal20-part-o-remaining-sprof.md"
PROFILE_SECONDS="4"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --seconds)
      PROFILE_SECONDS="$2"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    *)
      echo "goal20 profile: unknown option $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v "$SBCL_COMMAND" >/dev/null 2>&1; then
  echo "goal20 profile: SBCL is required." >&2
  exit 2
fi

if [ ! -f "$QUICKLISP_SETUP" ]; then
  echo "goal20 profile: Quicklisp setup not found at $QUICKLISP_SETUP." >&2
  exit 2
fi

export CADR_BENCH_PROJECT_DIRECTORY="$PROJECT_DIRECTORY"
export QUICKLISP_SETUP
export NO_COLOR=1

"$SBCL_COMMAND" --noinform --disable-debugger \
  --script "$PROJECT_DIRECTORY/scripts/goal20-profile.lisp" \
  --seconds "$PROFILE_SECONDS" \
  --output "$OUTPUT_PATH"
