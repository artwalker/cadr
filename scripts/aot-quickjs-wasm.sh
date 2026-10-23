#!/usr/bin/env bash
# Compile the pinned quickjs-wasi wasm to a fasl. The build may use a large heap.
# Runtime images load the fasl and do not compile this module.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SBCL_COMMAND="${SBCL:-sbcl}"

/usr/bin/time -v "$SBCL_COMMAND" --dynamic-space-size 8192 --noinform --disable-debugger \
	--load "$ROOT/scripts/aot-quickjs-wasm.lisp"
