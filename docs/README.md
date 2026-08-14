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
- [glossary.md](glossary.md): one fixed English term per concept for the
  Chinese-to-English documentation translation, so that a term does not acquire
  three renderings across the tree.  Extend it rather than improvising a
  synonym.
- [open-questions.md](open-questions.md): proposed mechanisms awaiting human
  decision; entries here are not authorization to implement.
- [delivery-checklist.md](delivery-checklist.md): mandatory root-image rebuild,
  freshness proof, full verification, and delivery-report evidence.
- [source-parity-upgrade.md](source-parity-upgrade.md): baseline source drift
  inventory plus mandatory source and render-differential upgrade gates.
- [render-diff.md](render-diff.md): fixed-baseline PTY capture, narrow
  normalization, fail-closed dispositions, and the permanent cross-
  implementation render oracle.
- [code-organization-exemptions.json](code-organization-exemptions.json):
  fail-closed large-file exemptions consumed by `scripts/verify.sh`,
  `test/code-organization-gate-test.py`, and
  `test/cadr-cli/goal14-organization-test.lisp`.  This is a human-judgement
  exit under [development-policy.md](development-policy.md) §5 and its entries
  must satisfy that section's evidence rules.
- [code-organization.md](code-organization.md): permanent directory ownership,
  converged policy primitives, anti-bypass tests, and reviewed large-file
  symptom gate for maintainable future development.
- [development-policy.md](development-policy.md): user-adjudicated permanent
  development constraints, including the single product-identity owner and
  exact exception process.
- [product-identity-allowlist.json](product-identity-allowlist.json): exact,
  fail-closed dispositions for retained upstream contracts and provenance;
  opaque assets are locked by SHA-256.

These four ledgers are independent: behavior, source, non-functional, and
presentation evidence cannot substitute for one another. The runnable-example
`examples/manifest.sexp` is an auxiliary inventory consumed by ledger checks,
not an additional ledger. Code organization is likewise not a parity ledger:
the ledgers answer whether Cadr is correct, while the organization contract
answers whether it can continue to be developed without duplicating policy.

## User-facing documentation

These twelve documents are cadr's own user documentation, created under goal 18
Part J.  They are **not translations of pi's website docs**; the baseline
`packages/coding-agent/docs/` tree was dispositioned as pi website content in
[source-parity.md](source-parity.md) §2a, where the remaining baseline docs also
carry per-file dispositions.  Existence of every path named by product text is
gate-enforced by `test/cadr-cli/goal18-docs-test.lisp`.

[extensions.md](extensions.md) · [themes.md](themes.md) ·
[skills.md](skills.md) · [prompt-templates.md](prompt-templates.md) ·
[tui.md](tui.md) · [keybindings.md](keybindings.md) · [sdk.md](sdk.md) ·
[custom-provider.md](custom-provider.md) · [models.md](models.md) ·
[packages.md](packages.md) ·
[environment-variables.md](environment-variables.md) ·
[providers.md](providers.md)

## Goal audit reports (evidence, not contracts)

Dated, goal-scoped reports.  Each states its own scope and cutoff.  **They must
not be read as current contracts**; on any conflict the current contract above
wins.

- [identity-audit.md](identity-audit.md): goal 16 product-identity tree audit.
- [lisp-idiom-audit.md](lisp-idiom-audit.md): Common Lisp expression audit.
- [goal18-part-e-audit.md](goal18-part-e-audit.md): capability-preservation
  review of the `有意差异` rows.
- [goal18-i2-derived-coverage.md](goal18-i2-derived-coverage.md): mechanical
  derived-requirement minus existing-scenario report.
- [goal18-startup-resources-audit.md](goal18-startup-resources-audit.md):
  startup resource blocks and empty-environment blind spots.
- [goal18-l5-attribution.md](goal18-l5-attribution.md): per-finding attribution
  for the manual A/B pass.
- [goal18-l-runbook.md](goal18-l-runbook.md): ordered Part L steps once the
  adjudications landed.

## Closed goal specifications

`goal6.md` … `goal19.md` at the repository root are **closed goal specs kept as
historical evidence**.  Each carries a banner saying so.  Rule-like wording in
them reflects the judgement at writing time; **on any conflict
[development-policy.md](development-policy.md) wins.**  In particular
`goal14.md` §4 still reads "仍然有效的闸门：四条准入理由", which the
2026-08-13 revision superseded (five reasons, two-step test).

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
