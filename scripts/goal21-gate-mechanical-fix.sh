#!/usr/bin/env bash
# Run deterministic gate fixes before dispatching any cursor-agent specialist.
#
# usage: scripts/goal21-gate-mechanical-fix.sh <failure-kind>
# exit 0 when a mechanical fix was applied (commit made) or postfix would pass.
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FAILURE_KIND="${1:-unknown}"
FAIL_LOG="${GOAL21_GATE_FAIL_LOG:-/tmp/goal21-gate-fail.txt}"

cd "$PROJECT_DIRECTORY"

case "$FAILURE_KIND" in
render-diff)
	if [ -x "$PROJECT_DIRECTORY/scripts/goal21-gate-proactive-render-diff.sh" ]; then
		"$PROJECT_DIRECTORY/scripts/goal21-gate-proactive-render-diff.sh"
		exit $?
	fi
	exit 1
	;;
goal20-ledger)
	if ! python3 scripts/goal20-unpaired-paths.py --check >/dev/null 2>&1; then
		python3 scripts/goal20-unpaired-paths.py --write
		if git diff --quiet docs/benchmarks/goal20-unpaired-paths.json docs/acceptance/goal-v20-part-h.md 2>/dev/null; then
			exit 1
		fi
		git add docs/benchmarks/goal20-unpaired-paths.json docs/acceptance/goal-v20-part-h.md
		git commit -m "fix(g21-gate): refresh goal20 unpaired-paths ledger (auto)"
		echo "goal21-gate-mechanical-fix: committed goal20-ledger refresh"
		exit 0
	fi
	exit 1
	;;
product-identity)
	if python3 test/product-identity-gate-test.py >/dev/null 2>&1; then
		echo "goal21-gate-mechanical-fix: product-identity already PASS"
		exit 0
	fi
	if [ -x "$PROJECT_DIRECTORY/scripts/goal21-sync-product-identity-allowlist.py" ]; then
		if python3 "$PROJECT_DIRECTORY/scripts/goal21-sync-product-identity-allowlist.py" --apply; then
			if git diff --quiet docs/product-identity-allowlist.json; then
				exit 1
			fi
			git add docs/product-identity-allowlist.json
			git commit -m "fix(g21-gate): sync product-identity allowlist (auto)"
			echo "goal21-gate-mechanical-fix: committed product-identity allowlist sync"
			exit 0
		fi
	fi
	exit 1
	;;
source-parity)
	if "${SBCL:-sbcl}" --script scripts/derive-source-parity-mappings.lisp --check >/dev/null 2>&1; then
		echo "goal21-gate-mechanical-fix: source-parity already PASS"
		exit 0
	fi
	exit 1
	;;
fiveam)
	if python3 scripts/goal20-unpaired-paths.py --check >/dev/null 2>&1; then
		:
	else
		"$0" goal20-ledger && exit 0
	fi
	exit 1
	;;
*)
	exit 1
	;;
esac
