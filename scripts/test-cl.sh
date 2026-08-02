#!/usr/bin/env bash
set -euo pipefail

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
TEST_OUTPUT="$TEST_HOME/fiveam-output.log"

set +e
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
  --eval '(asdf:test-system "cadr-protocol" :force t)' \
  2>&1 | tee "$TEST_OUTPUT"
TEST_STATUS=${PIPESTATUS[0]}
set -e

if ! SUMMARY="$(awk '
    /^[[:space:]]*Did [0-9]+ checks\.$/ {
      did += 1
      checks += $2
    }
    /^[[:space:]]*Pass: [0-9]+/ {
      pass_lines += 1
      pass += $2
    }
    /^[[:space:]]*Skip: [0-9]+/ {
      skip_lines += 1
      skip += $2
    }
    /^[[:space:]]*Fail: [0-9]+/ {
      fail_lines += 1
      fail += $2
    }
    END {
      if (did != 8 || pass_lines != 8 || skip_lines != 8 || fail_lines != 8)
        exit 2
      if (checks != pass + skip + fail)
        exit 3
      printf "cadr test summary: systems=%d checks=%d pass=%d skip=%d fail=%d", \
             did, checks, pass, skip, fail
    }
  ' "$TEST_OUTPUT")"; then
  echo "cadr test: incomplete FiveAM accounting; expected exactly 8 suite summaries." >&2
  exit 1
fi

printf '\n%s\n' "$SUMMARY"

if [ "$TEST_STATUS" -ne 0 ]; then
  exit "$TEST_STATUS"
fi

case "$SUMMARY" in
  *" fail=0") ;;
  *) exit 1 ;;
esac
