#!/usr/bin/env bash
# Mechanical check that disposition class rules integrate with render-diff analyze.
#
# usage: scripts/goal21-class-rules-verify.sh
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CLASS_RULES="$PROJECT_DIRECTORY/test/fixtures/render-diff/disposition-class-rules.json"
PRUNE="$PROJECT_DIRECTORY/scripts/goal21-render-diff-prune-class-rules.py"
RENDER_DIFF="$PROJECT_DIRECTORY/scripts/render-diff.py"
CACHE="$PROJECT_DIRECTORY/scripts/goal21-render-diff-capture-cache.sh"
PI_BASELINE_CACHE="/tmp/cadr-render-diff-pi-$(cut -d' ' -f1 "$PROJECT_DIRECTORY/BASELINE" | cut -c1-9)"
OUTPUT="${GOAL21_RENDER_DIFF_OUTPUT:-/tmp/goal21-class-rules-verify-output}"
ANALYSIS="${GOAL21_RENDER_DIFF_ANALYSIS:-/tmp/goal21-class-rules-verify-analysis}"

require_pattern() {
	local file="$1"
	local label="$2"
	local pattern="$3"
	if ! grep -qE "$pattern" "$file"; then
		echo "goal21-class-rules-verify: missing $label in $file" >&2
		exit 1
	fi
}

[ -f "$CLASS_RULES" ] || {
	echo "goal21-class-rules-verify: missing $CLASS_RULES" >&2
	exit 1
}
[ -x "$PRUNE" ] || {
	echo "goal21-class-rules-verify: $PRUNE not executable" >&2
	exit 1
}

require_pattern "$RENDER_DIFF" "DEFAULT_CLASS_RULES" 'DEFAULT_CLASS_RULES.*disposition-class-rules\.json'
require_pattern "$RENDER_DIFF" "--class-rules CLI" '"--class-rules"'

python3 -c "
import json, sys
from pathlib import Path
payload = json.loads(Path('$CLASS_RULES').read_text())
rules = payload.get('rules', [])
assert isinstance(rules, list) and rules, 'rules must be a non-empty list'
for rule in rules:
    assert rule.get('id'), 'each rule needs id'
    assert rule.get('classes'), 'each rule needs classes'
    assert isinstance(rule.get('match'), dict), 'each rule needs match dict'
print(f'goal21-class-rules-verify: loaded {len(rules)} class rules')
"

mkdir -p "$OUTPUT" "$ANALYSIS"
GOAL21_RENDER_DIFF_OUTPUT="$OUTPUT" GOAL21_RENDER_DIFF_ANALYSIS="$ANALYSIS" \
	"$CACHE" restore >/dev/null

if ! python3 -u "$RENDER_DIFF" analyze \
	--pi-repo "$PROJECT_DIRECTORY" \
	--manifest test/fixtures/render-diff/scenarios.json \
	--dispositions test/fixtures/render-diff/dispositions.json \
	--class-rules "$CLASS_RULES" \
	--tier core \
	--baseline-cache "$PI_BASELINE_CACHE" \
	--timeout 60 \
	--output "$OUTPUT" \
	--analysis-output "$ANALYSIS" 2>&1 | tee /tmp/goal21-class-rules-verify-analyze.log | grep -q 'classRules='; then
	echo "goal21-class-rules-verify: analyze did not report classRules" >&2
	exit 1
fi

if ! python3 "$PRUNE" --analysis "$ANALYSIS" --dry-run 2>&1 | grep -q 'prunable=0'; then
	echo "goal21-class-rules-verify: prune dry-run found remaining prunable entries" >&2
	exit 1
fi

echo "goal21-class-rules-verify: PASS"
