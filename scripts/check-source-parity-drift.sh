#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 --repo PATH --from REV --to REV --dispositions FILE" >&2
  echo "       $0 --ledger-only --dispositions docs/source-parity.md" >&2
  exit 2
}

REPOSITORY=
FROM_REVISION=
TO_REVISION=
DISPOSITIONS=
LEDGER_ONLY=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPOSITORY=${2:-}; shift 2 ;;
    --from) FROM_REVISION=${2:-}; shift 2 ;;
    --to) TO_REVISION=${2:-}; shift 2 ;;
    --dispositions) DISPOSITIONS=${2:-}; shift 2 ;;
    --ledger-only) LEDGER_ONLY=1; shift ;;
    *) usage ;;
  esac
done

[ -n "$DISPOSITIONS" ] || usage
[ -f "$DISPOSITIONS" ] || {
  echo "source parity drift: disposition file not found: $DISPOSITIONS" >&2
  exit 2
}

if [ "$LEDGER_ONLY" -eq 0 ]; then
  [ -n "$REPOSITORY" ] || usage
  [ -n "$FROM_REVISION" ] || usage
  [ -n "$TO_REVISION" ] || usage
  git -C "$REPOSITORY" cat-file -e "$FROM_REVISION^{commit}"
  git -C "$REPOSITORY" cat-file -e "$TO_REVISION^{commit}"
fi

DRIFT_FILE=$(mktemp /tmp/cadr-source-drift.XXXXXX)
EXPECTED_FILE=$(mktemp /tmp/cadr-source-dispositions.XXXXXX)
LEDGER_PATHS_FILE=$(mktemp /tmp/cadr-source-ledger-paths.XXXXXX)
BASELINE_PATHS_FILE=$(mktemp /tmp/cadr-source-baseline-paths.XXXXXX)
cleanup() {
  rm -f -- \
    "$DRIFT_FILE" "$EXPECTED_FILE" \
    "$LEDGER_PATHS_FILE" "$BASELINE_PATHS_FILE"
}
trap cleanup EXIT

if [ "$LEDGER_ONLY" -eq 0 ]; then
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
else
  : >"$DRIFT_FILE"
fi

LEDGER_ENTRIES=
if grep -q '^| Baseline file | Exported/top-level function, class, constant, and type surface | Function | Cadr mapping | Verdict | Evidence / reason |[[:space:]]*$' \
  "$DISPOSITIONS"; then
  awk -F '|' '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    /^\| Baseline file \| Exported\/top-level function, class, constant, and type surface \| Function \| Cadr mapping \| Verdict \| Evidence \/ reason \|[[:space:]]*$/ {
      awaiting_separator = 1
      headers++
      next
    }
    awaiting_separator {
      valid = NF == 8
      for (column = 2; column <= 7; column++) {
        value = trim($column)
        if (value !~ /^:?-+:?$/) valid = 0
      }
      if (!valid) {
        print "source parity drift: invalid source ledger table separator: " $0 > "/dev/stderr"
        invalid = 1
      }
      awaiting_separator = 0
      in_table = valid
      next
    }
    in_table && /^\|/ {
      if (NF != 8) {
        print "source parity drift: invalid source ledger row: " $0 > "/dev/stderr"
        invalid = 1
        next
      }
      path = trim($2)
      verdict = trim($6)
      if (path !~ /^`packages\/.*\.ts`$/ || path ~ /\.test\.ts`$/ ||
          (verdict != "`已实现`" && verdict != "`有意差异`" && verdict != "`缺失`")) {
        print "source parity drift: invalid source ledger row: " $0 > "/dev/stderr"
        invalid = 1
        next
      }
      print substr(path, 2, length(path) - 2)
      next
    }
    in_table { in_table = 0 }
    END {
      if (awaiting_separator) {
        print "source parity drift: source ledger table is missing its separator" > "/dev/stderr"
        invalid = 1
      }
      if (headers == 0) {
        print "source parity drift: source ledger contains no package tables" > "/dev/stderr"
        invalid = 1
      }
      if (invalid) exit 2
    }
  ' "$DISPOSITIONS" >"$LEDGER_PATHS_FILE"

  SUMMARY_TOTAL=$(
    awk -F '|' '
      function trim(value) {
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        return value
      }
      /^## 2\. Summary[[:space:]]*$/ { in_summary = 1; next }
      in_summary && /^## / { in_summary = 0 }
      in_summary && trim($2) == "**Total**" {
        value = trim($3)
        gsub(/\*/, "", value)
        print value
        totals++
      }
      END { if (totals != 1) exit 2 }
    ' "$DISPOSITIONS"
  ) || {
    echo "source parity drift: source ledger must contain one summary Total row" >&2
    exit 2
  }
  case "$SUMMARY_TOTAL" in
    ''|*[!0-9]*)
      echo "source parity drift: invalid source ledger summary total: $SUMMARY_TOTAL" >&2
      exit 2
      ;;
  esac

  LEDGER_ENTRIES=$(wc -l <"$LEDGER_PATHS_FILE")
  UNIQUE_LEDGER_ENTRIES=$(sort -u "$LEDGER_PATHS_FILE" | wc -l)
  if [ "$LEDGER_ENTRIES" -ne "$UNIQUE_LEDGER_ENTRIES" ]; then
    echo "source parity drift: duplicate source ledger paths" >&2
    exit 2
  fi
  if [ "$LEDGER_ENTRIES" -ne "$SUMMARY_TOTAL" ]; then
    echo "source parity drift: ledger entries $LEDGER_ENTRIES do not match summary total $SUMMARY_TOTAL" >&2
    exit 2
  fi

  MANIFEST_SHA=$(
    awk '
      /The sorted [0-9]+-path manifest has SHA-256/ {
        awaiting_hash = 1
        next
      }
      awaiting_hash {
        value = $0
        gsub(/^[[:space:]`]+/, "", value)
        gsub(/[[:space:]`.]+$/, "", value)
        if (length(value) == 64 && value !~ /[^0-9a-f]/) {
          print value
          hashes++
        }
        awaiting_hash = 0
      }
      END { if (hashes != 1) exit 2 }
    ' "$DISPOSITIONS"
  ) || {
    echo "source parity drift: source ledger must contain one sorted-path SHA-256" >&2
    exit 2
  }
  ACTUAL_MANIFEST_SHA=$(sort "$LEDGER_PATHS_FILE" | sha256sum | awk '{ print $1 }')
  if [ "$ACTUAL_MANIFEST_SHA" != "$MANIFEST_SHA" ]; then
    echo "source parity drift: source ledger path SHA-256 $ACTUAL_MANIFEST_SHA does not match recorded $MANIFEST_SHA" >&2
    exit 2
  fi

  if [ "$LEDGER_ONLY" -eq 0 ]; then
    git -C "$REPOSITORY" ls-tree -r --name-only "$FROM_REVISION" -- packages |
    awk '
      /^packages\/.*\.ts$/ && $0 !~ /\.test\.ts$/ { print }
    ' | sort -u >"$BASELINE_PATHS_FILE"
    MISSING_LEDGER_PATHS=$(comm -23 "$BASELINE_PATHS_FILE" <(sort -u "$LEDGER_PATHS_FILE"))
    STALE_LEDGER_PATHS=$(comm -13 "$BASELINE_PATHS_FILE" <(sort -u "$LEDGER_PATHS_FILE"))
    if [ -n "$MISSING_LEDGER_PATHS" ] || [ -n "$STALE_LEDGER_PATHS" ]; then
      if [ -n "$MISSING_LEDGER_PATHS" ]; then
        echo "source parity drift: baseline paths missing from source ledger:" >&2
        printf '%s\n' "$MISSING_LEDGER_PATHS" >&2
      fi
      if [ -n "$STALE_LEDGER_PATHS" ]; then
        echo "source parity drift: source ledger paths absent from baseline:" >&2
        printf '%s\n' "$STALE_LEDGER_PATHS" >&2
      fi
      exit 2
    fi
  fi

  if [ -s "$DRIFT_FILE" ]; then
    echo "source parity drift: Markdown source ledger validates the fixed baseline only; use four-column TSV for upgrade dispositions" >&2
    exit 2
  fi
  : >"$EXPECTED_FILE"
else
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
fi

if [ "$LEDGER_ONLY" -eq 1 ] && [ -z "$LEDGER_ENTRIES" ]; then
  echo "source parity drift: --ledger-only requires a Markdown source ledger" >&2
  exit 2
fi

if [ -n "$LEDGER_ENTRIES" ]; then
  printf 'Source parity ledger entries: %s\n' "$LEDGER_ENTRIES"
  printf 'Source parity ledger path SHA-256: %s\n' "$ACTUAL_MANIFEST_SHA"
fi

if [ "$LEDGER_ONLY" -eq 1 ]; then
  echo "Source parity ledger validation complete."
  exit 0
fi

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
