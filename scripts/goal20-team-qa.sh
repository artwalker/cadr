#!/usr/bin/env bash
# Testing Team: mandatory gate after director merge (or before declaring a pair done).
#
# usage:
#   scripts/goal20-team-qa.sh [--only-enforce GROUP.NAME]...
#
# With no --only-enforce, runs ledger test + unpaired-paths check only.
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$PROJECT_DIRECTORY"

GATE_ARGS=()
while [ "$#" -gt 0 ]; do
	case "$1" in
	--only-enforce)
		GATE_ARGS+=("$1" "$2")
		shift 2
		;;
	*)
		echo "goal20 team qa: unknown option $1" >&2
		exit 2
		;;
	esac
done

echo "goal20 team qa: ledger test"
python3 test/goal20-part-b-ledger-test.py

echo "goal20 team qa: unpaired paths inventory"
python3 scripts/goal20-unpaired-paths.py --check

if [ "${#GATE_ARGS[@]}" -gt 0 ]; then
	OUT="/tmp/goal20-team-qa-$$"
	mkdir -p "$OUT"
	echo "goal20 team qa: quick gates ${GATE_ARGS[*]}"
	# shellcheck disable=SC2086
	"$PROJECT_DIRECTORY/scripts/goal20-paired-paths.sh" --quick "${GATE_ARGS[@]}" --out "$OUT"
	# Informational quick runs pollute history; restore committed ledger.
	git restore docs/benchmarks/goal20-paired-paths.json \
		docs/benchmarks/goal20-ledger.json \
		docs/benchmarks/paired \
		docs/performance.md
fi

echo "goal20 team qa: PASS"
