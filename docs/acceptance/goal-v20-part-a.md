# Goal 20 Part A — self-history drift (not fail-closed)

Date: 2026-08-14. Status: machinery landed; **thresholds awaiting user adjudication**.

Proposal: `docs/proposals/goal20-part-a-regression-thresholds.md`.
Store: `docs/benchmarks/performance-history.json` (script-written only).

`scripts/goal11-performance-gate.py` now prints

- `self_history_gate=informational-awaiting-adjudication`
- `self_history_enforced=no`
- cold / N=5000 frame / N=5000 alloc ratios vs the last same-machine history row

when `--history` points at that JSON (default path). **A worse ratio does not fail the gate.** Existing absolute ceilings are unchanged.

`test/goal11-performance-gate-test.py` `SelfHistoryInformationalTest` asserts the helper never appends failures.

Do not enable the +20% / +25% caps in the same change as this report.
