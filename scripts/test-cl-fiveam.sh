#!/usr/bin/env bash
# FiveAM shard of test-cl.sh (all ASDF test systems).
#
# Default stdout is suite summaries + the cadr test summary line. Full
# asdf:test-system dribble is captured to a private log. Opt in with
# --verbose or CADR_TEST_CL_VERBOSE=1.
# usage: scripts/test-cl-fiveam.sh [--record] [--verbose]
set -euo pipefail

SBCL_COMMAND="${SBCL:-sbcl}"
QUICKLISP_SETUP_SOURCE="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"
PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

RECORD_ANCHOR=0
VERBOSE=0
if [ "${CADR_TEST_CL_VERBOSE:-0}" = "1" ]; then
  VERBOSE=1
fi
while [ "$#" -gt 0 ]; do
  case "$1" in
    --record) RECORD_ANCHOR=1; shift ;;
    --verbose) VERBOSE=1; shift ;;
    *)
      echo "usage: $0 [--record] [--verbose]" >&2
      exit 2
      ;;
  esac
done

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
mkdir -p "$TEST_HOME/.cache" "$TEST_HOME/asdf-cache"

run_sbcl_tests() {
  XDG_CACHE_HOME="$TEST_HOME/.cache" \
  ASDF_OUTPUT_TRANSLATIONS="/:$TEST_HOME/asdf-cache/" \
  HOME="$TEST_HOME" "$SBCL_COMMAND" --noinform --non-interactive \
    --load "$QUICKLISP_SETUP" \
    --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-core.asd\"))" \
    --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-ai.asd\"))" \
    --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-agent.asd\"))" \
    --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-tui.asd\"))" \
    --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-cli.asd\"))" \
    --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-live-test-support.asd\"))" \
    --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-storage.asd\"))" \
    --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-server.asd\"))" \
    --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-evals.asd\"))" \
    --eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-protocol.asd\"))" \
    --eval '(asdf:test-system "cadr-core" :force t)' \
    --eval '(asdf:test-system "cadr-ai" :force t)' \
    --eval '(asdf:test-system "cadr-agent" :force t)' \
    --eval '(asdf:test-system "cadr-tui" :force t)' \
    --eval '(asdf:test-system "cadr-cli" :force t)' \
    --eval '(asdf:test-system "cadr-storage" :force t)' \
    --eval '(asdf:test-system "cadr-server" :force t)' \
    --eval '(asdf:test-system "cadr-evals" :force t)' \
    --eval '(asdf:test-system "cadr-protocol" :force t)'
}

print_suite_summaries() {
  awk '
    /^[[:space:]]*Did [0-9]+ checks\.$/ { show=1 }
    show { print }
    /^[[:space:]]*Fail: [0-9]+/ { show=0; print "" }
  ' "$TEST_OUTPUT"
}

print_fiveam_failure_excerpt() {
  local excerpt
  excerpt="$(awk '
    /^[[:space:]]*(Failure Details|Unexpected Error Details|Expected Fail)/ { dump=1 }
    dump { print }
  ' "$TEST_OUTPUT")"
  if [ -n "$excerpt" ]; then
    printf '%s\n' "$excerpt"
    return
  fi
  echo "cadr test: no FiveAM Failure Details section; suites with Fail>0:"
  awk '
    /^[[:space:]]*Did [0-9]+ checks\.$/ { buf=$0 ORS; next }
    buf != "" && /^[[:space:]]*Pass: / { buf=buf $0 ORS; next }
    buf != "" && /^[[:space:]]*Skip: / { buf=buf $0 ORS; next }
    buf != "" && /^[[:space:]]*Fail: / {
      if ($2+0 > 0) printf "%s%s\n", buf, $0
      buf=""
    }
    buf != "" && !/^[[:space:]]/ { buf="" }
  ' "$TEST_OUTPUT"
}

set +e
if [ "$VERBOSE" -eq 1 ]; then
  run_sbcl_tests 2>&1 | tee "$TEST_OUTPUT"
  TEST_STATUS=${PIPESTATUS[0]}
else
  run_sbcl_tests >"$TEST_OUTPUT" 2>&1
  TEST_STATUS=$?
fi
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
      if (did != 9 || pass_lines != 9 || skip_lines != 9 || fail_lines != 9)
        exit 2
      if (checks != pass + skip + fail)
        exit 3
      printf "cadr test summary: systems=%d checks=%d pass=%d skip=%d fail=%d", \
             did, checks, pass, skip, fail
    }
  ' "$TEST_OUTPUT")"; then
  echo "cadr test: incomplete FiveAM accounting; expected exactly 9 suite summaries." >&2
  echo "cadr test: last 80 lines of FiveAM output:" >&2
  tail -n 80 "$TEST_OUTPUT" >&2
  exit 1
fi

if [ "$VERBOSE" -ne 1 ]; then
  print_suite_summaries
fi
printf '\n%s\n' "$SUMMARY"

fail_nonzero=0
case "$SUMMARY" in
  *" fail=0") ;;
  *) fail_nonzero=1 ;;
esac

if [ "$TEST_STATUS" -ne 0 ] || [ "$fail_nonzero" -eq 1 ]; then
  echo "cadr test: FiveAM failures:"
  print_fiveam_failure_excerpt
  if [ "$TEST_STATUS" -ne 0 ]; then
    exit "$TEST_STATUS"
  fi
  exit 1
fi

if [ "$RECORD_ANCHOR" -eq 1 ]; then
  python3 "$PROJECT_DIRECTORY/scripts/write-test-check-anchor.py" \
    --summary "$SUMMARY" \
    --ledger "${CADR_TEST_CHECK_LEDGER:-$PROJECT_DIRECTORY/docs/test-matrix.md}" \
    --strict
else
  python3 "$PROJECT_DIRECTORY/scripts/write-test-check-anchor.py" \
    --verify \
    --summary "$SUMMARY" \
    --ledger "${CADR_TEST_CHECK_LEDGER:-$PROJECT_DIRECTORY/docs/test-matrix.md}" || {
    echo "test-cl-fiveam.sh: check-count ledger drifted; re-record with $0 --record and commit" >&2
    exit 1
  }
fi

echo "test-cl-fiveam: PASS"
