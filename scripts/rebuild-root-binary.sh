#!/usr/bin/env bash
# Rebuild ./cadr from current sources (no test-cl.sh). Used when the root
# binary is stale so verify can continue deterministic stages.
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

if ! command -v "$SBCL_COMMAND" >/dev/null 2>&1; then
	echo "rebuild-root-binary: SBCL is required" >&2
	exit 1
fi

QUICKLISP_SETUP_SOURCE="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"
if [ ! -f "$QUICKLISP_SETUP_SOURCE" ]; then
	echo "rebuild-root-binary: Quicklisp setup not found at $QUICKLISP_SETUP_SOURCE" >&2
	exit 1
fi
QUICKLISP_SETUP_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$QUICKLISP_SETUP_SOURCE")" && pwd)"
QUICKLISP_SETUP="$QUICKLISP_SETUP_DIRECTORY/$(basename -- "$QUICKLISP_SETUP_SOURCE")"
export QUICKLISP_SETUP

cd "$PROJECT_DIRECTORY"
echo "rebuild-root-binary: building $PROJECT_DIRECTORY/cadr"
"$SBCL_COMMAND" --noinform --disable-debugger \
	--script "$PROJECT_DIRECTORY/build.lisp"
test -x "$PROJECT_DIRECTORY/cadr"
echo "rebuild-root-binary: ok"
