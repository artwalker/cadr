#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FIXTURE=$(mktemp -d /tmp/cadr-source-drift-test.XXXXXX)
cleanup() {
  rm -rf -- "$FIXTURE"
}
trap cleanup EXIT

git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.name "Cadr Test"
git -C "$FIXTURE" config user.email "cadr-test@example.invalid"
mkdir -p "$FIXTURE/packages/demo/src" "$FIXTURE/packages/demo/test"
printf 'old\n' >"$FIXTURE/packages/demo/src/renamed.ts"
printf 'delete\n' >"$FIXTURE/packages/demo/src/deleted.ts"
printf 'ignored\n' >"$FIXTURE/packages/demo/test/ignored.test.ts"
git -C "$FIXTURE" add packages
git -C "$FIXTURE" commit -qm old
OLD_REVISION=$(git -C "$FIXTURE" rev-parse HEAD)

git -C "$FIXTURE" mv \
  packages/demo/src/renamed.ts packages/demo/src/moved.ts
git -C "$FIXTURE" rm -q packages/demo/src/deleted.ts
printf 'new\n' >"$FIXTURE/packages/demo/src/added.ts"
printf 'ignored too\n' >"$FIXTURE/packages/demo/test/new.test.ts"
git -C "$FIXTURE" add packages
git -C "$FIXTURE" commit -qm new
NEW_REVISION=$(git -C "$FIXTURE" rev-parse HEAD)

DISPOSITIONS="$FIXTURE/dispositions.tsv"
printf 'status\told_path\tnew_path\tdecision\n' >"$DISPOSITIONS"

if "$PROJECT_DIRECTORY/scripts/check-source-parity-drift.sh" \
  --repo "$FIXTURE" --from "$OLD_REVISION" --to "$NEW_REVISION" \
  --dispositions "$DISPOSITIONS" >"$FIXTURE/unresolved.out" 2>&1; then
  echo "source parity drift self-test: unresolved drift unexpectedly passed" >&2
  exit 1
fi
grep -F "A packages/demo/src/added.ts" "$FIXTURE/unresolved.out"
grep -F "D packages/demo/src/deleted.ts" "$FIXTURE/unresolved.out"
grep -F "R packages/demo/src/renamed.ts -> packages/demo/src/moved.ts" \
  "$FIXTURE/unresolved.out"
if grep -F ".test.ts" "$FIXTURE/unresolved.out"; then
  echo "source parity drift self-test: test source was not excluded" >&2
  exit 1
fi

printf 'A\t-\tpackages/demo/src/added.ts\tport before baseline advance\n' \
  >>"$DISPOSITIONS"
printf 'D\tpackages/demo/src/deleted.ts\t-\tremove ledger row\n' \
  >>"$DISPOSITIONS"
printf 'R\tpackages/demo/src/renamed.ts\tpackages/demo/src/moved.ts\trename ledger row\n' \
  >>"$DISPOSITIONS"

"$PROJECT_DIRECTORY/scripts/check-source-parity-drift.sh" \
  --repo "$FIXTURE" --from "$OLD_REVISION" --to "$NEW_REVISION" \
  --dispositions "$DISPOSITIONS" >"$FIXTURE/resolved.out"
grep -F "Source parity dispositions complete: 3" "$FIXTURE/resolved.out"
echo "source parity drift self-test: PASS"
