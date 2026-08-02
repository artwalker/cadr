# Source parity upgrade gate

`docs/source-parity.md` is a fixed-baseline ledger, not a best-effort inventory.
Every baseline upgrade must first enumerate source-file additions, deletions, and
renames with:

```sh
./scripts/check-source-parity-drift.sh \
  --repo /path/to/pi-mono \
  --from OLD_BASELINE_COMMIT \
  --to NEW_BASELINE_COMMIT \
  --dispositions /tmp/source-dispositions.tsv
```

The inventory predicate is identical to Goal 12 Part A: tracked `packages/**/*.ts`
excluding `*.test.ts`. Modified files remain governed by the existing behavioral
and source re-audit; this gate focuses on paths that otherwise silently change the
595-file denominator.

The disposition file is tab-separated:

```text
status	old_path	new_path	decision
A	-	packages/demo/src/new.ts	implement and add a ledger row
D	packages/demo/src/old.ts	-	remove the obsolete ledger row
R	packages/demo/src/a.ts	packages/demo/src/b.ts	rename and re-audit the row
```

Blank decisions, missing drift rows, stale rows, malformed records, unknown refs,
or a missing disposition file fail closed. `scripts/test-source-parity-drift.sh`
proves added/deleted/renamed detection, `*.test.ts` exclusion, the unresolved
failure, and the complete-disposition success path.

The fixed ledger itself is a separate real-input gate:

```sh
./scripts/check-source-parity-drift.sh \
  --ledger-only --dispositions docs/source-parity.md
```

This mode enters only the six-column package tables headed by `Baseline file`,
ignores prose and summary tables, accepts exactly the three ledger verdicts,
and fails on malformed separators/rows, duplicates, a row count different from
the Summary total, or a sorted-path SHA-256 different from the recorded manifest.
It is explicit because CI's shallow checkout does not contain the detached
TypeScript baseline object. A normal `--repo/--from/--to` invocation retains the
stronger tree-versus-ledger path-set comparison. `scripts/verify.sh` runs both the
synthetic A/D/R self-test and this real `docs/source-parity.md` gate before build.

After every row has a human-authored disposition, update the fixed baseline and
counts together in `docs/source-parity.md`, `docs/parity-map.md`,
`docs/performance.md`, and `examples/manifest.sexp`. Their shared
`GOAL12_LEDGER` identity is checked by FiveAM, so an upgrade cannot land with one
ledger still describing the old source set.
