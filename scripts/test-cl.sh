#!/usr/bin/env bash
set -eu

SBCL_COMMAND="${SBCL:-sbcl}"
QUICKLISP_SETUP_SOURCE="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"
PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [ ! -f "$QUICKLISP_SETUP_SOURCE" ]; then
  echo "cadr test: Quicklisp setup not found at $QUICKLISP_SETUP_SOURCE." >&2
  exit 1
fi

QUICKLISP_SETUP_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$QUICKLISP_SETUP_SOURCE")" && pwd)"
QUICKLISP_SETUP="$QUICKLISP_SETUP_DIRECTORY/$(basename -- "$QUICKLISP_SETUP_SOURCE")"
export QUICKLISP_SETUP
TEST_HOME="$(mktemp -d /tmp/cadr-test-home.XXXXXX)"
trap 'rm -rf -- "$TEST_HOME"' EXIT

HOME="$TEST_HOME" "$SBCL_COMMAND" --noinform --non-interactive \
  --load "$QUICKLISP_SETUP" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-ai.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-agent.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-tui.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-cli.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-live-test-support.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-storage.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-server.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-evals.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-protocol.asd\"))" \
  --eval '(asdf:test-system "cadr-ai" :force t)' \
  --eval '(asdf:test-system "cadr-agent" :force t)' \
  --eval '(asdf:test-system "cadr-tui" :force t)' \
  --eval '(asdf:test-system "cadr-cli" :force t)' \
  --eval '(asdf:test-system "cadr-storage" :force t)' \
  --eval '(asdf:test-system "cadr-server" :force t)' \
  --eval '(asdf:test-system "cadr-evals" :force t)' \
  --eval '(asdf:test-system "cadr-protocol" :force t)'
