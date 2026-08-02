#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
EXPECTED_SOURCE_LEDGER_ENTRIES=595
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
grep -Fq "A packages/demo/src/added.ts" "$FIXTURE/unresolved.out"
grep -Fq "D packages/demo/src/deleted.ts" "$FIXTURE/unresolved.out"
grep -Fq "R packages/demo/src/renamed.ts -> packages/demo/src/moved.ts" \
  "$FIXTURE/unresolved.out"
if grep -Fq ".test.ts" "$FIXTURE/unresolved.out"; then
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
grep -Fq "Source parity dispositions complete: 3" "$FIXTURE/resolved.out"

SOURCE_LEDGER="$PROJECT_DIRECTORY/docs/source-parity.md"
expect_ledger_failure() {
  local name="$1"
  local ledger="$2"
  local expected="$3"
  local output="$FIXTURE/$name.out"
  local status
  if "$PROJECT_DIRECTORY/scripts/check-source-parity-drift.sh" \
    --ledger-only --dispositions "$ledger" >"$output" 2>&1; then
    echo "source parity drift self-test: malformed $name ledger passed" >&2
    exit 1
  else
    status=$?
  fi
  if [ "$status" -ne 2 ]; then
    echo "source parity drift self-test: malformed $name ledger returned $status, expected 2" >&2
    exit 1
  fi
  grep -Fq "$expected" "$output"
}

SUMMARY_TOTAL=$(
  awk -F '|' '
    $2 ~ /^[[:space:]]*\*\*Total\*\*[[:space:]]*$/ {
      value = $3
      gsub(/[^0-9]/, "", value)
      print value
      exit
    }
  ' "$SOURCE_LEDGER"
)
if [ "$SUMMARY_TOTAL" != "$EXPECTED_SOURCE_LEDGER_ENTRIES" ]; then
  echo "source parity drift self-test: ledger summary is $SUMMARY_TOTAL, expected $EXPECTED_SOURCE_LEDGER_ENTRIES" >&2
  exit 1
fi

"$PROJECT_DIRECTORY/scripts/check-source-parity-drift.sh" \
  --ledger-only --dispositions "$SOURCE_LEDGER" >"$FIXTURE/real-ledger.out"
grep -Fq "Source parity ledger entries: $EXPECTED_SOURCE_LEDGER_ENTRIES" \
  "$FIXTURE/real-ledger.out"
grep -Fq "Source parity ledger validation complete." \
  "$FIXTURE/real-ledger.out"

NON_C_UTF8_LOCALE=$(
  locale -a 2>/dev/null |
    awk 'tolower($0) ~ /^en_us\.utf-?8$/ { print; exit }'
)
if [ -n "$NON_C_UTF8_LOCALE" ]; then
  LC_ALL="$NON_C_UTF8_LOCALE" \
    "$PROJECT_DIRECTORY/scripts/check-source-parity-drift.sh" \
    --ledger-only --dispositions "$SOURCE_LEDGER" \
    >"$FIXTURE/non-c-locale-ledger.out"
  grep -Fq \
    "Source parity ledger entries: $EXPECTED_SOURCE_LEDGER_ENTRIES" \
    "$FIXTURE/non-c-locale-ledger.out"
  grep -Fq \
    "Source parity ledger path SHA-256: 242d90e03ae708b9ea30d71747052af80f6d19e62eec3990a5863c62a614965d" \
    "$FIXTURE/non-c-locale-ledger.out"
fi

PROSE_LEDGER="$FIXTURE/prose-ledger.md"
cp "$SOURCE_LEDGER" "$PROSE_LEDGER"
printf '\nThis prose is outside the package tables and must be ignored.\n' \
  >>"$PROSE_LEDGER"
"$PROJECT_DIRECTORY/scripts/check-source-parity-drift.sh" \
  --ledger-only --dispositions "$PROSE_LEDGER" >"$FIXTURE/prose-ledger.out"
grep -Fq "Source parity ledger entries: $EXPECTED_SOURCE_LEDGER_ENTRIES" \
  "$FIXTURE/prose-ledger.out"

BAD_SEPARATOR_LEDGER="$FIXTURE/bad-separator-ledger.md"
awk '
  !changed && /^\| Baseline file \|/ { awaiting_separator = 1; print; next }
  awaiting_separator {
    print "| broken separator |"
    awaiting_separator = 0
    changed = 1
    next
  }
  { print }
' "$SOURCE_LEDGER" >"$BAD_SEPARATOR_LEDGER"
expect_ledger_failure \
  bad-separator "$BAD_SEPARATOR_LEDGER" \
  "source parity drift: invalid source ledger table separator"

BAD_ROW_LEDGER="$FIXTURE/bad-row-ledger.md"
awk '
  !changed && /^\| `packages\// {
    sub(/`已实现`|`有意差异`/, "`未裁决`")
    changed = 1
  }
  { print }
' "$SOURCE_LEDGER" >"$BAD_ROW_LEDGER"
expect_ledger_failure \
  bad-row "$BAD_ROW_LEDGER" \
  "source parity drift: invalid source ledger row"

DUPLICATE_LEDGER="$FIXTURE/duplicate-ledger.md"
awk '
  !changed && /^\| `packages\// {
    print
    changed = 1
  }
  { print }
' "$SOURCE_LEDGER" >"$DUPLICATE_LEDGER"
expect_ledger_failure \
  duplicate "$DUPLICATE_LEDGER" \
  "source parity drift: duplicate source ledger paths"

BAD_SHA_LEDGER="$FIXTURE/bad-sha-ledger.md"
awk '
  !changed && /^\| `packages\// {
    sub(/\.d\.ts`/, "-changed.d.ts`")
    changed = 1
  }
  { print }
' "$SOURCE_LEDGER" >"$BAD_SHA_LEDGER"
expect_ledger_failure \
  bad-sha "$BAD_SHA_LEDGER" \
  "does not match recorded 242d90e03ae708b9ea30d71747052af80f6d19e62eec3990a5863c62a614965d"

BAD_TOTAL_LEDGER="$FIXTURE/bad-total-ledger.md"
awk '
  !changed && /^\| \*\*Total\*\* \|/ {
    sub(/\*\*[0-9]+\*\*/, "**594**", $0)
    changed = 1
  }
  { print }
' "$SOURCE_LEDGER" >"$BAD_TOTAL_LEDGER"
expect_ledger_failure \
  bad-total "$BAD_TOTAL_LEDGER" \
  "source parity drift: ledger entries $SUMMARY_TOTAL do not match summary total 594"

printf 'source parity drift self-test: synthetic dispositions=3, real ledger entries=%s, locale-independent SHA; PASS\n' \
  "$EXPECTED_SOURCE_LEDGER_ENTRIES"
