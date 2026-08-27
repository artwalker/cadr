#!/usr/bin/env bash
# Credential-free Common Lisp test gate with optional sharding.
#
# CADR_TEST_CL_SHARD:
#   all (default) — FiveAM + goal20 ledger
#   fiveam|unit   — FiveAM only
#   goal20|ledger — goal20-unpaired-paths only
#
# usage: scripts/test-cl.sh [--record] [--verbose]
#   --verbose / CADR_TEST_CL_VERBOSE=1  full FiveAM dribble (default: summary)
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SHARD="${CADR_TEST_CL_SHARD:-all}"

case "$SHARD" in
all)
	"$PROJECT_DIRECTORY/scripts/test-cl-fiveam.sh" "$@"
	"$PROJECT_DIRECTORY/scripts/test-cl-goal20.sh"
	;;
fiveam|unit)
	"$PROJECT_DIRECTORY/scripts/test-cl-fiveam.sh" "$@"
	;;
goal20|ledger)
	"$PROJECT_DIRECTORY/scripts/test-cl-goal20.sh"
	;;
*)
	echo "test-cl.sh: unknown CADR_TEST_CL_SHARD=$SHARD (all|fiveam|goal20)" >&2
	exit 2
	;;
esac

echo "test-cl.sh: PASS (shard=$SHARD)"
