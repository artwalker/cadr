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
failure, and the complete-disposition success path. `scripts/verify.sh` runs that
self-test before building.

After every row has a human-authored disposition, update the fixed baseline and
counts together in `docs/source-parity.md`, `docs/parity-map.md`,
`docs/performance.md`, and `examples/manifest.sexp`. Their shared
`GOAL12_LEDGER` identity is checked by FiveAM, so an upgrade cannot land with one
ledger still describing the old source set.
