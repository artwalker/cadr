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
cp "$PROJECT_DIRECTORY/BASELINE" "$PROJECT_DIRECTORY/.baseline-prev"
OLD_SHORT="${OLD_COMMIT:0:9}"
NEW_SHORT="${NEW_COMMIT:0:9}"
DESCRIBE="$(git -C "$PROJECT_DIRECTORY" describe --tags "$NEW_COMMIT")"
if printf '%s' "$DESCRIBE" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-g[0-9a-f]+$'; then
  NEW_RELEASE="$(printf '%s' "$DESCRIBE" | sed -E 's/^(v[0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)-g[0-9a-f]+$/\1/')"
  NEW_DISTANCE="$(printf '%s' "$DESCRIBE" | sed -E 's/^(v[0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)-g[0-9a-f]+$/\2/')"
elif printf '%s' "$DESCRIBE" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
  # Exact tag: zero commits ahead.
  NEW_RELEASE="$DESCRIBE"
  NEW_DISTANCE="0"
else
  echo "set-baseline: cannot parse git describe output: $DESCRIBE" >&2
  exit 1
fi

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
    "$PROJECT_DIRECTORY/examples" \
    2>/dev/null \
    | grep -v -E 'docs/(proposals|progress|acceptance)/' \
    | grep -v -E '\.tmp|node_modules'
)"

OLD_RELEASE="$(cut -d' ' -f2 "$PROJECT_DIRECTORY/.baseline-prev")"
OLD_DISTANCE="$(cut -d' ' -f3 "$PROJECT_DIRECTORY/.baseline-prev")"
for file in $targets; do
  sed -i \
    -e "s/$OLD_COMMIT/$NEW_COMMIT/g" \
    -e "s/$OLD_SHORT/$NEW_SHORT/g" \
    -e "s/$OLD_RELEASE/$NEW_RELEASE/g" \
    -e "s/(+$OLD_DISTANCE,/(+$NEW_DISTANCE,/g" \
    "$file"
done

echo "set-baseline: $OLD_SHORT -> $NEW_SHORT ($NEW_RELEASE +$NEW_DISTANCE)"
echo "rewritten files:"
printf '%s\n' $targets
rm -f "$PROJECT_DIRECTORY/.baseline-prev"
echo "next: python3 scripts/baseline-anchor.py check && ./scripts/verify.sh"
echo "note: PI_AI_MODEL_DATA_PACKAGE / PI_AI_MODEL_DATA_SHA256 in"
echo "      scripts/render-diff.py pin the model-data artifact; update them"
echo "      from the new baseline's package metadata during the upgrade."
