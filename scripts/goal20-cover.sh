#!/usr/bin/env bash
# Goal 20 Part N (N2.7): full-tree sb-cover branch coverage measurement.
# Diagnostic only, not a gate; do not wire into test-cl.sh or verify.sh.
# usage: scripts/goal20-cover.sh [output-directory]
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SBCL_COMMAND="${SBCL:-sbcl}"
QUICKLISP_SETUP_SOURCE="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"
OUTPUT_DIRECTORY="${1:-/tmp/goal20-cover}"

if [ ! -f "$QUICKLISP_SETUP_SOURCE" ]; then
  echo "goal20 cover: Quicklisp setup not found at $QUICKLISP_SETUP_SOURCE." >&2
  exit 1
fi

QUICKLISP_SETUP_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$QUICKLISP_SETUP_SOURCE")" && pwd)"
QUICKLISP_SETUP="$QUICKLISP_SETUP_DIRECTORY/$(basename -- "$QUICKLISP_SETUP_SOURCE")"

# Isolated HOME and a fresh ASDF output cache: every file compiles exactly
# once, with the coverage policy in effect (no :force t; see the lisp
# driver header for why recompilation would corrupt the measurement).
TEST_HOME="$(mktemp -d /tmp/cadr-cover-home.XXXXXX)"
trap 'rm -rf -- "$TEST_HOME"' EXIT
mkdir -p "$TEST_HOME/.cache" "$TEST_HOME/asdf-cache" "$OUTPUT_DIRECTORY"
OUTPUT_DIRECTORY="$(CDPATH= cd -- "$OUTPUT_DIRECTORY" && pwd)"

export QUICKLISP_SETUP
export CADR_COVER_ROOT="$PROJECT_DIRECTORY"
export CADR_COVER_OUT="$OUTPUT_DIRECTORY"
export NO_COLOR=1

XDG_CACHE_HOME="$TEST_HOME/.cache" \
ASDF_OUTPUT_TRANSLATIONS="/:$TEST_HOME/asdf-cache/" \
HOME="$TEST_HOME" \
"$SBCL_COMMAND" --noinform --script "$PROJECT_DIRECTORY/scripts/goal20-cover.lisp"
