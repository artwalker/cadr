#!/usr/bin/env bash
set -eu

SBCL_COMMAND="${SBCL:-sbcl}"

if ! command -v "$SBCL_COMMAND" >/dev/null 2>&1; then
  echo "cadr build: SBCL is required (version 2.4 or newer)." >&2
  exit 1
fi

SBCL_VERSION="$("$SBCL_COMMAND" --noinform --version | awk '{print $2}')"
SBCL_MAJOR="${SBCL_VERSION%%.*}"
SBCL_REMAINDER="${SBCL_VERSION#*.}"
SBCL_MINOR="${SBCL_REMAINDER%%.*}"

if [ "$SBCL_MAJOR" -lt 2 ] ||
  { [ "$SBCL_MAJOR" -eq 2 ] && [ "$SBCL_MINOR" -lt 4 ]; }; then
  echo "cadr build: SBCL 2.4 or newer is required; found $SBCL_VERSION." >&2
  exit 1
fi

QUICKLISP_SETUP_SOURCE="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"
if [ ! -f "$QUICKLISP_SETUP_SOURCE" ]; then
  echo "cadr build: Quicklisp setup not found at $QUICKLISP_SETUP_SOURCE." >&2
  exit 1
fi
QUICKLISP_SETUP_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$QUICKLISP_SETUP_SOURCE")" && pwd)"
QUICKLISP_SETUP="$QUICKLISP_SETUP_DIRECTORY/$(basename -- "$QUICKLISP_SETUP_SOURCE")"
export QUICKLISP_SETUP

SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
"$SCRIPT_DIRECTORY/scripts/test-cl.sh"

BUILD_HOME="$(mktemp -d /tmp/cadr-build-home.XXXXXX)"
trap 'rm -rf -- "$BUILD_HOME"' EXIT
mkdir -p "$BUILD_HOME/.cache" "$BUILD_HOME/asdf-cache"

XDG_CACHE_HOME="$BUILD_HOME/.cache" \
ASDF_OUTPUT_TRANSLATIONS="/:$BUILD_HOME/asdf-cache/" \
HOME="$BUILD_HOME" "$SBCL_COMMAND" --noinform --disable-debugger \
  --script "$SCRIPT_DIRECTORY/build.lisp"
