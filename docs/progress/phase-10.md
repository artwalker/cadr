# Phase 10 progress — goal 18 acceptance summary (2026-08-10)

The prerequisite parts of goal 18's alignment with pi v0.84.1 (Part A–K) are
complete; Part L (baseline upgrade) is ordered last by the spec, and the three
sets of adjudications its execution requires are under "Pending adjudication" at
the end of this document.

## Completed surface

| Part | Status | Key evidence |
|---|---|---|
| A login-cancel deadlock | done | `cda918e56` the cancellation chain is connected end to end; `ab50abf48` the eight forms; `goal18-login-cancel-test.lisp` state-machine regression; the attribution conclusion (earlier than 74fe2c0b8, not a goal 17 regression) entered the CHANGELOG |
| B agent layer and migration | done | the nine residents of `~/.cadr/agent/` + crash/; `CADR_CODING_AGENT_DIR`; four migration tests |
| C path-owner convergence | done | the `".cadr/"` literal grep check has been folded into the code-organization gate |
| D tools/ and debug.log | done | the config.ts row records it: getToolsDir is dead code and is not implemented; the debug log is implemented by `/debug` |
| E intentional-difference re-audit | done | `docs/goal18-part-e-audit.md` (77 rows) |
| F package-boundary mapping | done | §1a was spot-checked row by row and matches the code |
| G hygiene items | mostly done | the `.tmp/` cleanup and the toolchain switch are left to goal closeout per G4/G5 (the timing must be coordinated with the user) |
| H startup resource blocks | done | dual-state cross-implementation comparison of the `startup-resources` scenario |
| I gate structure gaps | done (except the 10 exemptions pending adjudication) | I1 sweep mid-states, I2 derivation (login forms / extension events / label floor), I4 machine reconciliation of the ledger numbers, I5 cache content validation, I6 release gate, I7 key actions + sink widening, I7.3 reverse scan, I8 llama UI |
| J user documentation | done | 12 documents + the reference-integrity FiveAM gate; the `/usr/local` fake-path defect is fixed |
| K tool-definition cross-implementation comparison | done | the descriptions + schemas + snippets of the seven tools are locked by a fixture mechanically derived from the baseline |

Real capabilities filled in this round (the I7 tail): full port of the startup
content migration, the `--list-models` baseline table, making extension load
failure fatal (reportDiagnostics + the `-ne` hint), shortcut-conflict semantics,
prompt/@file error normalization, and migration of 62 legacy key names.

## Gate evidence

- `./scripts/test-cl.sh`: **15699/15699** (9 systems).
- `./scripts/verify.sh`: 20 deterministic stages + the live stages all PASS
  (verify14, including the newly added baseline anchor consistency stage).
- Full render gate (rerun on a clean checkout): 90/90 captures, all 466
  adjudications agree; red only on the 10 exemption branches pending adjudication.
- `./scripts/verify-release.sh`: per the I6 design it does not give a success
  exit code when live is unverified or the full run is red — it currently fails
  because the 10 exemptions are pending adjudication, which is a
  pending-adjudication state.
- Binary freshness: PASS.

## Pending adjudication (prerequisites for executing Part L)

1. **The 10 exemption branches** + the new `unreachable-in-harness` obstacleKind:
   `docs/proposals/goal18-i7-tail-exemptions.md`.
2. **Mermaid route**: `docs/proposals/goal18-l1a-mermaid.md`
   (recommended route 1: pure-Lisp port of grok-mermaid + byte-by-byte
   differential golden sample).
3. **The 9 existing pending items** (--resume extension, npm package,
   update --models, telemetry, the -r selector, sentinel models, help switches,
   the pi-mono URL, keybindings.json).
4. **The I05 exit-residue class** (or fix cadr's teardown path):
   the last section of `docs/goal18-l5-attribution.md`; the L5.2 probe patch has
   been verified reproducible and reverted, pending adjudication.

## Part L prerequisites already in place

- L2.1 anchor unification: the `BASELINE` file is the sole owner; the consistency
  gate is in verify.sh; `set-baseline.sh` has passed an end-to-end dry run toward
  v0.84.1 (including the +0 of an exact tag).
- L1 mechanical enumeration: `scripts/enumerate-baseline-diff.py`; the v0.84.1
  difference-set result and the completeness argument are in
  `docs/source-parity-upgrade.md` (including the correction of four omissions in
  the hand list: the `--alt` removal, the removal of four PI_*/RADIUS
  environment variables, STY/ZELLIJ, and the
  CredentialPrintError rename).
- L5.1 attribution table: `docs/goal18-l5-attribution.md`.
