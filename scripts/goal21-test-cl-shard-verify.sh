#!/usr/bin/env bash
# Mechanical check that test-cl.sh sharding (fiveam|goal20) is wired correctly.
#
# usage: scripts/goal21-test-cl-shard-verify.sh
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_CL="$PROJECT_DIRECTORY/scripts/test-cl.sh"
FIVEAM="$PROJECT_DIRECTORY/scripts/test-cl-fiveam.sh"
GOAL20="$PROJECT_DIRECTORY/scripts/test-cl-goal20.sh"

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

require_pattern "$TEST_CL" "CADR_TEST_CL_SHARD" 'CADR_TEST_CL_SHARD'
require_pattern "$TEST_CL" "fiveam shard" 'fiveam\|unit'
require_pattern "$TEST_CL" "goal20 shard" 'goal20\|ledger'
require_pattern "$TEST_CL" "test-cl-fiveam delegation" 'test-cl-fiveam\.sh'
require_pattern "$TEST_CL" "test-cl-goal20 delegation" 'test-cl-goal20\.sh'

if CADR_TEST_CL_SHARD=invalid "$TEST_CL" >/dev/null 2>&1; then
	echo "goal21-test-cl-shard-verify: invalid shard must fail" >&2
	exit 1
fi

CADR_TEST_CL_SHARD=goal20 "$TEST_CL"
CADR_TEST_CL_SHARD=ledger "$TEST_CL"
CADR_TEST_CL_SHARD=fiveam "$TEST_CL"
CADR_TEST_CL_SHARD=unit "$TEST_CL"

echo "goal21-test-cl-shard-verify: PASS"
