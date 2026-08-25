#!/usr/bin/env bash
# Fast compile gate: load cadr-cli from current sources in an isolated HOME.
# Exit 0 when sources compile; non-zero on read/compile errors.
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [ "$#" -gt 0 ]; then
	case "$1" in
	--project-directory)
		PROJECT_DIRECTORY="$(CDPATH= cd -- "${2:?}" && pwd)"
		shift 2
		;;
	esac
fi

SBCL_COMMAND="${SBCL:-sbcl}"
QUICKLISP_SETUP_SOURCE="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"
if [ ! -f "$QUICKLISP_SETUP_SOURCE" ]; then
	echo "cadr-compile-check: Quicklisp setup not found at $QUICKLISP_SETUP_SOURCE" >&2
	exit 1
fi

BUILD_HOME="$(mktemp -d /tmp/cadr-compile-check-home.XXXXXX)"
trap 'rm -rf -- "$BUILD_HOME"' EXIT
mkdir -p "$BUILD_HOME/.cache" "$BUILD_HOME/asdf-cache"

cd "$PROJECT_DIRECTORY"
XDG_CACHE_HOME="$BUILD_HOME/.cache" \
ASDF_OUTPUT_TRANSLATIONS="/:$BUILD_HOME/asdf-cache/" \
HOME="$BUILD_HOME" \
QUICKLISP_SETUP="$QUICKLISP_SETUP_SOURCE" \
"$SBCL_COMMAND" --noinform --non-interactive \
	--load "$QUICKLISP_SETUP_SOURCE" \
	--eval "(pushnew (truename \"./\") asdf:*central-registry* :test #'equal)" \
	--eval '(asdf:load-system "cadr-cli" :force t)' \
	--eval '(uiop:quit 0)'

echo "cadr-compile-check: ok"
