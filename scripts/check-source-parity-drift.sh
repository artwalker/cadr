#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 --repo PATH --from REV --to REV --dispositions FILE" >&2
  exit 2
}

REPOSITORY=
FROM_REVISION=
TO_REVISION=
DISPOSITIONS=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPOSITORY=${2:-}; shift 2 ;;
    --from) FROM_REVISION=${2:-}; shift 2 ;;
    --to) TO_REVISION=${2:-}; shift 2 ;;
    --dispositions) DISPOSITIONS=${2:-}; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$REPOSITORY" ] || usage
[ -n "$FROM_REVISION" ] || usage
[ -n "$TO_REVISION" ] || usage
[ -n "$DISPOSITIONS" ] || usage
[ -f "$DISPOSITIONS" ] || {
  echo "source parity drift: disposition file not found: $DISPOSITIONS" >&2
  exit 2
}

git -C "$REPOSITORY" cat-file -e "$FROM_REVISION^{commit}"
git -C "$REPOSITORY" cat-file -e "$TO_REVISION^{commit}"

DRIFT_FILE=$(mktemp /tmp/cadr-source-drift.XXXXXX)
EXPECTED_FILE=$(mktemp /tmp/cadr-source-dispositions.XXXXXX)
cleanup() {
  rm -f -- "$DRIFT_FILE" "$EXPECTED_FILE"
}
trap cleanup EXIT

git -C "$REPOSITORY" diff --name-status -M \
  "$FROM_REVISION" "$TO_REVISION" -- packages |
awk -F '\t' '
  function source_path(path) {
    return path ~ /^packages\/.*\.ts$/ && path !~ /\.test\.ts$/
  }
  $1 == "A" && source_path($2) { print "A\t-\t" $2; next }
  $1 == "D" && source_path($2) { print "D\t" $2 "\t-"; next }
  $1 ~ /^R[0-9]+$/ && (source_path($2) || source_path($3)) {
    print "R\t" $2 "\t" $3
  }
' >"$DRIFT_FILE"

awk -F '\t' '
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  NR == 1 && $1 == "status" { next }
  NF != 4 || ($1 != "A" && $1 != "D" && $1 != "R") || $4 == "" {
    print "source parity drift: invalid disposition row: " $0 > "/dev/stderr"
    invalid = 1
    next
  }
  { print $1 "\t" $2 "\t" $3 }
  END { if (invalid) exit 2 }
' "$DISPOSITIONS" | sort -u >"$EXPECTED_FILE"

printf 'Source parity drift %s..%s\n' "$FROM_REVISION" "$TO_REVISION"
if [ ! -s "$DRIFT_FILE" ]; then
  echo "No added, deleted, or renamed baseline source files."
else
  awk -F '\t' '
    $1 == "A" { print "A " $3 }
    $1 == "D" { print "D " $2 }
    $1 == "R" { print "R " $2 " -> " $3 }
  ' "$DRIFT_FILE"
fi

MISSING=$(comm -23 <(sort -u "$DRIFT_FILE") "$EXPECTED_FILE")
STALE=$(comm -13 <(sort -u "$DRIFT_FILE") "$EXPECTED_FILE")
if [ -n "$MISSING" ]; then
  echo "source parity drift: unresolved changes:" >&2
  printf '%s\n' "$MISSING" >&2
fi
if [ -n "$STALE" ]; then
  echo "source parity drift: stale disposition rows:" >&2
  printf '%s\n' "$STALE" >&2
fi
if [ -n "$MISSING" ] || [ -n "$STALE" ]; then
  exit 1
fi

printf 'Source parity dispositions complete: %s\n' \
  "$(wc -l <"$DRIFT_FILE")"
