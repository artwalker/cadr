# Cadr documentation index

Start with the project [README](../README.md) for installation and user-facing
behavior, and the [CHANGELOG](../CHANGELOG.md) for milestone history. Current
contracts live in the top-level documents below; historical goal/phase reports
remain evidence and must not silently override a current contract.

## Current contracts

- [architecture.md](architecture.md): system boundaries, data/control flow,
  stable interfaces, frozen surfaces, and accepted implementation decisions.
- [parity-map.md](parity-map.md): behavior ledger for the fixed upstream
  baseline, observable contracts, and exhaustive test classification.
- [source-parity.md](source-parity.md): source ledger giving every
  fixed-baseline source file an explicit capability disposition.
- [performance.md](performance.md): non-functional ledger for deterministic
  performance, allocation, memory, stability, fixed-reference comparisons,
  archived results, and release thresholds.
- [presentation-parity.md](presentation-parity.md): presentation ledger for
  visible copy, semantic styling, geometry, formatting, and truncation.
- [visual-parity.md](visual-parity.md): TUI visual, content, runtime-state, and
  full-overlay comparison contract supporting the presentation ledger.
- [test-matrix.md](test-matrix.md): deterministic, fixture, process/PTY, live,
  and human verification levels and their entry points.
- [dependency-audit.md](dependency-audit.md): production dependencies,
  transitive closure, authorization class, and replacement boundary.
- [open-questions.md](open-questions.md): proposed mechanisms awaiting human
  decision; entries here are not authorization to implement.
- [delivery-checklist.md](delivery-checklist.md): mandatory root-image rebuild,
  freshness proof, full verification, and delivery-report evidence.
- [source-parity-upgrade.md](source-parity-upgrade.md): baseline source drift
  inventory plus mandatory source and render-differential upgrade gates.
- [render-diff.md](render-diff.md): fixed-baseline PTY capture, narrow
  normalization, fail-closed dispositions, and the permanent cross-
  implementation render oracle.
- [code-organization.md](code-organization.md): permanent directory ownership,
  converged policy primitives, anti-bypass tests, and reviewed large-file
  symptom gate for maintainable future development.

These four ledgers are independent: behavior, source, non-functional, and
presentation evidence cannot substitute for one another. The runnable-example
`examples/manifest.sexp` is an auxiliary inventory consumed by ledger checks,
not an additional ledger. Code organization is likewise not a parity ledger:
the ledgers answer whether Cadr is correct, while the organization contract
answers whether it can continue to be developed without duplicating policy.

## Evidence directories

- [progress/](progress/): accepted goal specifications, phase reports,
  migration records, commit hashes, and immutable historical evidence.
- [proposals/](proposals/): scoped API/architecture proposals that require
  explicit user approval before implementation.
- [acceptance/](acceptance/): mechanical, live, smoke, and human acceptance
  reports for completed Parts.

Current Goal 10 reports: [Part B no-op](acceptance/goal-v10-part-b.md),
[Part D Lisp-native capabilities](acceptance/goal-v10-part-d.md), and
[Part E release preparation](acceptance/goal-v10-part-e.md).

When behavior, tests, or dependencies change, update the relevant current
contract and its acceptance report in the same submitted Part. Historical
reports may gain a clearly labelled superseding note, but their original
evidence must remain distinguishable.
