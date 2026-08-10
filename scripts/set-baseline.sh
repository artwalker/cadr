#!/usr/bin/env bash
# Goal 18 L2.1: mechanical baseline-anchor rewrite for upgrades.
# Usage: scripts/set-baseline.sh <full-pi-commit>
#
# Rewrites the BASELINE owner file (release/distance derived from
# `git describe`) and every operational reference.  Historical narrative
# (CHANGELOG.md, docs/proposals/, docs/progress/, docs/acceptance/,
# goal*.md) intentionally keeps old anchors as history; the current-state
# ledgers are rewritten.  The anchor consistency gate and the full gate
# suite must run afterwards.
set -euo pipefail

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
NEW_COMMIT="${1:-}"

if ! printf '%s' "$NEW_COMMIT" | grep -qE '^[0-9a-f]{40}$'; then
  echo "usage: set-baseline.sh <full-40-hex-pi-commit>" >&2
  exit 2
fi

git -C "$PROJECT_DIRECTORY" cat-file -e "$NEW_COMMIT^{commit}" || {
  echo "set-baseline: commit not in the repository object store: $NEW_COMMIT" >&2
  exit 1
}

OLD_COMMIT="$(cut -d' ' -f1 "$PROJECT_DIRECTORY/BASELINE")"
OLD_SHORT="${OLD_COMMIT:0:9}"
NEW_SHORT="${NEW_COMMIT:0:9}"
DESCRIBE="$(git -C "$PROJECT_DIRECTORY" describe --tags "$NEW_COMMIT")"
NEW_RELEASE="$(printf '%s' "$DESCRIBE" | sed -E 's/^(v[0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)-g[0-9a-f]+$/\1/')"
NEW_DISTANCE="$(printf '%s' "$DESCRIBE" | sed -E 's/^(v[0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)-g[0-9a-f]+$/\2/')"

printf '%s %s %s\n' "$NEW_COMMIT" "$NEW_RELEASE" "$NEW_DISTANCE" \
  > "$PROJECT_DIRECTORY/BASELINE"

# Operational surface: every occurrence of the old short or full anchor.
# Current-state ledgers are included; historical narrative is not.
targets="$(
  grep -rl "$OLD_SHORT" \
    "$PROJECT_DIRECTORY/scripts" \
    "$PROJECT_DIRECTORY/src" \
    "$PROJECT_DIRECTORY/test" \
    "$PROJECT_DIRECTORY/README.md" \
    "$PROJECT_DIRECTORY/docs" \
    2>/dev/null \
    | grep -v -E 'docs/(proposals|progress|acceptance)/' \
    | grep -v -E '\.tmp|node_modules'
)"

for file in $targets; do
  sed -i -e "s/$OLD_COMMIT/$NEW_COMMIT/g" -e "s/$OLD_SHORT/$NEW_SHORT/g" "$file"
done

echo "set-baseline: $OLD_SHORT -> $NEW_SHORT ($NEW_RELEASE +$NEW_DISTANCE)"
echo "rewritten files:"
printf '%s\n' $targets
echo "next: python3 scripts/baseline-anchor.py check && ./scripts/verify.sh"
