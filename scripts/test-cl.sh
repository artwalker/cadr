#!/usr/bin/env bash
set -eu

SBCL_COMMAND="${SBCL:-sbcl}"
QUICKLISP_SETUP="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"
PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

exec "$SBCL_COMMAND" --noinform --non-interactive \
  --load "$QUICKLISP_SETUP" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-ai.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-agent.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-tui.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-cli.asd\"))" \
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
