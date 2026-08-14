# Goal 20 Part B — performance ledger time series

Date: 2026-08-14.

`scripts/write-performance-ledger.py` regenerates the marked section in
`docs/performance.md` from `docs/benchmarks/performance-history.json`.
`scripts/verify.sh` calls it after `record-performance-history.py`.

The table answers: current row, previous row (once two exist), label, machine,
and git. Numbers are not hand-edited.

Today the history file has one `verify-isolated` row. A second real
`bench.sh` (not `--quick`) is required before the ledger can show a delta.
