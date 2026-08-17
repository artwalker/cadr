#!/usr/bin/env bash
set -eu

# Local instrument. Never called from verify.sh or test-live.sh.
export CADR_LIVE_OPENCODE_GO_SWEEP=1

SBCL_COMMAND="${SBCL:-sbcl}"
QUICKLISP_SETUP="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"
PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

exec "$SBCL_COMMAND" --noinform --non-interactive \
  --load "$QUICKLISP_SETUP" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-core.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-ai.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-agent.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-tui.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-cli.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-live-test-support.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-evals.asd\"))" \
  --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-live-tests.asd\"))" \
  --eval '(asdf:load-system "cadr-ai/live-tests" :force t)' \
  --eval '(unless (fiveam:run! (quote cadr-ai/live-tests::live-opencode-go-catalog-sweep)) (uiop:quit 1))'
