#!/usr/bin/env bash
set -eu

SBCL_COMMAND="${SBCL:-sbcl}"
QUICKLISP_SETUP="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"
PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

exec "$SBCL_COMMAND" --noinform --non-interactive \
  --load "$QUICKLISP_SETUP" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/pi-ai.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/pi-agent.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/pi-tui.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/pi-cli.asd\"))" \
  --eval '(asdf:test-system "pi-ai" :force t)' \
  --eval '(asdf:test-system "pi-agent" :force t)' \
  --eval '(asdf:test-system "pi-tui" :force t)' \
  --eval '(asdf:test-system "pi-cli" :force t)'
