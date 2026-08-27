#!/usr/bin/env bash
# Mechanical check that test-cl.sh sharding (fiveam|goal20) is wired correctly,
# FiveAM default stdout is summary-only, and full goal21-gate-run skips a
# second test-cl.sh when verify.sh already recorded deterministic FiveAM PASS.
#
# usage: scripts/goal21-test-cl-shard-verify.sh
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_CL="$PROJECT_DIRECTORY/scripts/test-cl.sh"
FIVEAM="$PROJECT_DIRECTORY/scripts/test-cl-fiveam.sh"
GOAL20="$PROJECT_DIRECTORY/scripts/test-cl-goal20.sh"
GATE_RUN="$PROJECT_DIRECTORY/scripts/goal21-gate-run.sh"

require_pattern() {
	local file="$1"
	local label="$2"
	local pattern="$3"
	if ! grep -qE "$pattern" "$file"; then
		echo "goal21-test-cl-shard-verify: missing $label in $file" >&2
		exit 1
	fi
}

[ -x "$TEST_CL" ] || {
	echo "goal21-test-cl-shard-verify: $TEST_CL not executable" >&2
	exit 1
}
[ -x "$FIVEAM" ] || {
	echo "goal21-test-cl-shard-verify: $FIVEAM not executable" >&2
	exit 1
}
[ -x "$GOAL20" ] || {
	echo "goal21-test-cl-shard-verify: $GOAL20 not executable" >&2
	exit 1
}
[ -x "$GATE_RUN" ] || {
	echo "goal21-test-cl-shard-verify: $GATE_RUN not executable" >&2
	exit 1
}

require_pattern "$TEST_CL" "CADR_TEST_CL_SHARD" 'CADR_TEST_CL_SHARD'
require_pattern "$TEST_CL" "fiveam shard" 'fiveam\|unit'
require_pattern "$TEST_CL" "goal20 shard" 'goal20\|ledger'
require_pattern "$TEST_CL" "test-cl-fiveam delegation" 'test-cl-fiveam\.sh'
require_pattern "$TEST_CL" "test-cl-goal20 delegation" 'test-cl-goal20\.sh'
require_pattern "$FIVEAM" "quiet verbose env" 'CADR_TEST_CL_VERBOSE'
require_pattern "$FIVEAM" "quiet verbose flag" '--verbose'
require_pattern "$FIVEAM" "no default tee" 'run_sbcl_tests >"\$TEST_OUTPUT"'
require_pattern "$GATE_RUN" "fiveam already-green helper" 'goal21_verify_log_fiveam_already_green'
require_pattern "$GATE_RUN" "skip heartbeat" 'test-cl.sh skipped'
require_pattern "$GATE_RUN" "check-fiveam-log" '--check-fiveam-log'

if CADR_TEST_CL_SHARD=invalid "$TEST_CL" >/dev/null 2>&1; then
	echo "goal21-test-cl-shard-verify: invalid shard must fail" >&2
	exit 1
fi

CADR_TEST_CL_SHARD=goal20 "$TEST_CL"
CADR_TEST_CL_SHARD=ledger "$TEST_CL"

# fiveam|unit runs the full nine-system suite; only check the case arm.
if ! awk '/fiveam\|unit\)/,/;;/' "$TEST_CL" | grep -q 'test-cl-fiveam\.sh'; then
	echo "goal21-test-cl-shard-verify: fiveam|unit must delegate to test-cl-fiveam.sh" >&2
	exit 1
fi

TMP="$(mktemp -d /tmp/cadr-test-cl-shard-verify.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT

write_green_fake_sbcl() {
	cat >"$1" <<'EOF'
#!/bin/sh
echo FIVEAM_FLOOD_LINE
i=0
while [ "$i" -lt 9 ]; do
  printf ' Did 3 checks.\n    Pass: 3 (100%)\n    Skip: 0 (  0%)\n    Fail: 0 (  0%)\n'
  i=$((i + 1))
done
EOF
	chmod +x "$1"
}

write_fail_fake_sbcl() {
	cat >"$1" <<'EOF'
#!/bin/sh
echo FIVEAM_FLOOD_LINE
i=0
while [ "$i" -lt 8 ]; do
  printf ' Did 3 checks.\n    Pass: 3 (100%)\n    Skip: 0 (  0%)\n    Fail: 0 (  0%)\n'
  i=$((i + 1))
done
printf ' Did 3 checks.\n    Pass: 2 ( 66%)\n    Skip: 0 (  0%)\n    Fail: 1 ( 33%)\n'
printf '\n Failure Details:\n --------------------------------\n EXAMPLE-FAILING-TEST []:\n\n expected 1 got 2.\n'
exit 1
EOF
	chmod +x "$1"
}

QUICKLISP="$TMP/setup.lisp"
: >"$QUICKLISP"
LEDGER="$TMP/test-matrix.md"
cat >"$LEDGER" <<'EOF'
# fixture
<!-- GOAL20_TEST_CHECKS systems=9 checks=27 pass=27 skip=0 fail=0 -->
EOF

FAKE="$TMP/fake-sbcl"
write_green_fake_sbcl "$FAKE"

run_fiveam() {
	SBCL="$FAKE" QUICKLISP_SETUP="$QUICKLISP" CADR_TEST_CHECK_LEDGER="$LEDGER" \
		"$FIVEAM" "$@"
}

QUIET_OUT="$TMP/quiet.out"
if ! run_fiveam >"$QUIET_OUT" 2>&1; then
	echo "goal21-test-cl-shard-verify: quiet fake-sbcl FiveAM must pass" >&2
	cat "$QUIET_OUT" >&2
	exit 1
fi
grep -Fq 'cadr test summary: systems=9 checks=27 pass=27 skip=0 fail=0' "$QUIET_OUT"
grep -Fq 'test-check-anchor: systems=9 checks=27' "$QUIET_OUT"
if grep -Fq 'FIVEAM_FLOOD_LINE' "$QUIET_OUT"; then
	echo "goal21-test-cl-shard-verify: quiet default leaked FiveAM dribble" >&2
	exit 1
fi
quiet_lines="$(wc -l <"$QUIET_OUT")"
if [ "$quiet_lines" -gt 80 ]; then
	echo "goal21-test-cl-shard-verify: quiet stdout too large ($quiet_lines lines)" >&2
	exit 1
fi

VERBOSE_OUT="$TMP/verbose.out"
if ! run_fiveam --verbose >"$VERBOSE_OUT" 2>&1; then
	echo "goal21-test-cl-shard-verify: --verbose fake-sbcl FiveAM must pass" >&2
	exit 1
fi
grep -Fq 'FIVEAM_FLOOD_LINE' "$VERBOSE_OUT"
grep -Fq 'cadr test summary: systems=9 checks=27 pass=27 skip=0 fail=0' "$VERBOSE_OUT"

ENV_VERBOSE_OUT="$TMP/env-verbose.out"
if ! CADR_TEST_CL_VERBOSE=1 run_fiveam >"$ENV_VERBOSE_OUT" 2>&1; then
	echo "goal21-test-cl-shard-verify: CADR_TEST_CL_VERBOSE=1 must pass" >&2
	exit 1
fi
grep -Fq 'FIVEAM_FLOOD_LINE' "$ENV_VERBOSE_OUT"

write_fail_fake_sbcl "$FAKE"
FAIL_OUT="$TMP/fail.out"
FAIL_RC=0
run_fiveam >"$FAIL_OUT" 2>&1 || FAIL_RC=$?
if [ "$FAIL_RC" -eq 0 ]; then
	echo "goal21-test-cl-shard-verify: failing FiveAM must be non-zero" >&2
	exit 1
fi
grep -Fq 'EXAMPLE-FAILING-TEST' "$FAIL_OUT"
grep -Fq 'cadr test summary: systems=9 checks=27 pass=26 skip=0 fail=1' "$FAIL_OUT"
if grep -Fq 'FIVEAM_FLOOD_LINE' "$FAIL_OUT"; then
	echo "goal21-test-cl-shard-verify: failure path leaked FiveAM dribble" >&2
	exit 1
fi

pad_row() {
	python3 -c 'import sys; print(sys.argv[1].ljust(48) + " " + sys.argv[2])' "$1" "$2"
}

GREEN_LOG="$TMP/verify-green.log"
{
	echo "Deterministic stages"
	pad_row "Stage" "Result"
	pad_row "deterministic FiveAM" "PASS"
	pad_row "FiveAM check-count ledger" "PASS"
	echo
	echo "Stage timings"
	pad_row "Stage" "Time"
	pad_row "deterministic FiveAM" "12s"
	pad_row "FiveAM check-count ledger" "1s"
} >"$GREEN_LOG"

SKIP_LOG="$TMP/verify-skip.log"
{
	echo "Deterministic stages"
	pad_row "deterministic FiveAM" "SKIP (not selected)"
	echo "Stage timings"
	pad_row "deterministic FiveAM" "-"
} >"$SKIP_LOG"

PASS_NO_TIME="$TMP/verify-pass-no-time.log"
{
	pad_row "deterministic FiveAM" "PASS"
	pad_row "deterministic FiveAM" "-"
} >"$PASS_NO_TIME"

if ! "$GATE_RUN" --check-fiveam-log "$GREEN_LOG" >/dev/null; then
	echo "goal21-test-cl-shard-verify: timed FiveAM PASS must be already-green" >&2
	exit 1
fi
if "$GATE_RUN" --check-fiveam-log "$SKIP_LOG" >/dev/null; then
	echo "goal21-test-cl-shard-verify: SKIP FiveAM must not be already-green" >&2
	exit 1
fi
if "$GATE_RUN" --check-fiveam-log "$PASS_NO_TIME" >/dev/null; then
	echo "goal21-test-cl-shard-verify: PASS with '-' timing must not skip test-cl" >&2
	exit 1
fi

# Real FiveAM format (one system): quiet capture still has Did/Pass/Skip/Fail.
if [ -f "${QUICKLISP_SETUP:-$HOME/quicklisp/setup.lisp}" ]; then
	REAL_HOME="$TMP/real-home"
	mkdir -p "$REAL_HOME/.cache" "$REAL_HOME/asdf-cache"
	REAL_OUT="$TMP/real-cadr-core.log"
	REAL_QL="${QUICKLISP_SETUP:-$HOME/quicklisp/setup.lisp}"
	set +e
	XDG_CACHE_HOME="$REAL_HOME/.cache" \
	ASDF_OUTPUT_TRANSLATIONS="/:$REAL_HOME/asdf-cache/" \
	HOME="$REAL_HOME" "${SBCL:-sbcl}" --noinform --non-interactive \
		--load "$REAL_QL" \
		--eval "(asdf:load-asd (truename \"$PROJECT_DIRECTORY/cadr-core.asd\"))" \
		--eval '(asdf:test-system "cadr-core" :force t)' \
		>"$REAL_OUT" 2>&1
	REAL_RC=$?
	set -e
	if [ "$REAL_RC" -ne 0 ]; then
		echo "goal21-test-cl-shard-verify: cadr-core FiveAM failed" >&2
		tail -n 40 "$REAL_OUT" >&2
		exit 1
	fi
	grep -E '^[[:space:]]*Did [0-9]+ checks\.$' "$REAL_OUT" >/dev/null
	grep -E '^[[:space:]]*Pass: [0-9]+' "$REAL_OUT" >/dev/null
	grep -E '^[[:space:]]*Skip: [0-9]+' "$REAL_OUT" >/dev/null
	grep -E '^[[:space:]]*Fail: [0-9]+' "$REAL_OUT" >/dev/null
	echo "goal21-test-cl-shard-verify: real cadr-core FiveAM summaries ok"
fi

echo "goal21-test-cl-shard-verify: PASS"
