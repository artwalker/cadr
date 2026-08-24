#!/usr/bin/env bash
# Goal 20 Part H: run both halves of the non-TUI paired benchmarks and pair
# them.  The two halves must run on the same host, back to back, so the
# absolute microseconds are comparable; scripts/goal20-paired-paths.py rejects
# a cross-host pair for the ratio gate.
#
# usage: scripts/goal20-paired-paths.sh [--quick] [--samples N] [--warmups N]
#                                       [--only-enforce GROUP.NAME]
#                                       [--baseline DIR] [--out DIR]
set -eu

PROJECT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SBCL_COMMAND="${SBCL:-sbcl}"
QUICKLISP_SETUP="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"
# Default to the render-diff cache for the commit pinned in BASELINE; the
# anchor gate (scripts/baseline-anchor.py check) rejects a literal hash here.
BASELINE_SHORT="$(cut -d' ' -f1 "$PROJECT_DIRECTORY/BASELINE" | cut -c1-9)"
BASELINE_DIRECTORY="${GOAL20_PI_BASELINE:-/tmp/cadr-render-diff-pi-$BASELINE_SHORT}"
OUTPUT_DIRECTORY="${TMPDIR:-/tmp}/goal20-paired-paths"
BENCH_ARGUMENTS=""
GATE_ARGUMENTS=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --quick)
      BENCH_ARGUMENTS="$BENCH_ARGUMENTS --quick"
      shift
      ;;
    --samples | --warmups)
      BENCH_ARGUMENTS="$BENCH_ARGUMENTS $1 $2"
      shift 2
      ;;
    --only-enforce)
      GATE_ARGUMENTS="$GATE_ARGUMENTS --only-enforce $2"
      shift 2
      ;;
    --baseline)
      BASELINE_DIRECTORY="$2"
      shift 2
      ;;
    --out)
      OUTPUT_DIRECTORY="$2"
      shift 2
      ;;
    *)
      echo "goal20 paired paths: unknown option $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v "$SBCL_COMMAND" >/dev/null 2>&1; then
  echo "goal20 paired paths: SBCL is required." >&2
  exit 2
fi

if [ ! -f "$QUICKLISP_SETUP" ]; then
  echo "goal20 paired paths: Quicklisp setup not found at $QUICKLISP_SETUP." >&2
  exit 2
fi

TSX_COMMAND="$BASELINE_DIRECTORY/node_modules/.bin/tsx"
if [ ! -x "$TSX_COMMAND" ]; then
  echo "goal20 paired paths: pi baseline tsx not found at $TSX_COMMAND." >&2
  echo "goal20 paired paths: populate the baseline with scripts/render-diff.py first." >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIRECTORY"
CADR_REPORT="$OUTPUT_DIRECTORY/cadr.json"
PI_REPORT="$OUTPUT_DIRECTORY/pi.json"
CADR_JOURNAL="$OUTPUT_DIRECTORY/cadr-journal.jsonl"
PI_JOURNAL="$OUTPUT_DIRECTORY/pi-journal.jsonl"

export CADR_BENCH_PROJECT_DIRECTORY="$PROJECT_DIRECTORY"
export QUICKLISP_SETUP
# Both sides render into counting sinks; NO_COLOR keeps a stray escape
# sequence out of the character counts the gate compares.
export NO_COLOR=1

# The fixtures are checked in; regenerating must be a no-op before the
# measurements mean anything.
node "$PROJECT_DIRECTORY/scripts/goal20-gen-paired-fixtures.mjs" --check

# shellcheck disable=SC2086
"$SBCL_COMMAND" --noinform --disable-debugger \
  --script "$PROJECT_DIRECTORY/scripts/goal20-paired-paths.lisp" \
  $BENCH_ARGUMENTS --keep-journal "$CADR_JOURNAL" --output "$CADR_REPORT"

# shellcheck disable=SC2086
"$TSX_COMMAND" "$PROJECT_DIRECTORY/scripts/goal20-paired-paths.mjs" \
  "$BASELINE_DIRECTORY" \
  $BENCH_ARGUMENTS --keep-journal "$PI_JOURNAL" --output "$PI_REPORT"

python3 "$PROJECT_DIRECTORY/scripts/goal20-paired-paths.py" \
  --cadr "$CADR_REPORT" \
  --pi "$PI_REPORT" \
  --cadr-journal "$CADR_JOURNAL" \
  --pi-journal "$PI_JOURNAL" \
  --summary-json "$OUTPUT_DIRECTORY/summary.json" \
  $GATE_ARGUMENTS
python3 "$PROJECT_DIRECTORY/scripts/record-paired-paths.py" \
  --summary "$OUTPUT_DIRECTORY/summary.json" \
  --cadr-report "$CADR_REPORT" \
  --history "$PROJECT_DIRECTORY/docs/benchmarks/goal20-paired-paths.json"
