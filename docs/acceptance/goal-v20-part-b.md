# Goal 20 Part B — non-functional ledger write-back

Date: 2026-08-14.

Two script-written series, neither hand-edited.

## TUI self-history

`scripts/record-performance-history.py` appends a `bench.sh` row to
`docs/benchmarks/performance-history.json`.
`scripts/write-performance-ledger.py` regenerates
`<!-- GOAL20_PERF_HISTORY_START/END -->` in `docs/performance.md`.
`scripts/verify.sh` calls both after the Goal 11 isolated bench.

The table answers: current row, previous row (once two exist), label, machine,
and git.

## Paired non-TUI paths

`scripts/goal20-paired-paths.sh` records a passing pair into
`docs/benchmarks/goal20-paired-paths.json` via
`scripts/record-paired-paths.py`. The ledger writer regenerates
`<!-- GOAL20_PAIRED_PATHS_START/END -->` with current vs previous ratios,
cadr/baseline medians, ceilings, git, machine, `quick`, and `ratio_gate`.

The first booked row is the `/tmp/goal20-paired-paths` same-machine `--quick`
run (`ratio_gate=informational-quick-run`). That is a booking, not an
enforced full sample. Part O must re-measure with a non-quick run on this
host before claiming a ratio moved.

`scripts/verify.sh` does not run the paired-path halves (they need the local
baseline checkout). It does re-render the paired section whenever the Goal 11
ledger rewrite runs, so a later `bench.sh` cannot wipe the paired table.

## FiveAM check-count anchor

`scripts/test-cl.sh` writes
`<!-- GOAL20_TEST_CHECKS systems=9 checks=N pass=… skip=… fail=0 -->`
into `docs/test-matrix.md` and exits 1 when that comment changed.
`scripts/verify.sh` then runs `write-test-check-anchor.py --verify`.
The count is a CI product; do not type it.
