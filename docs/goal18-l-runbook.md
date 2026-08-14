# Goal 18 Part L runbook (the ordered steps once every adjudication is in)

Prerequisite adjudications (do not touch anything until all of them are
approved):

1. The 10-branch exemption in `docs/proposals/goal18-i7-tail-exemptions.md` plus
   the new `unreachable-in-harness` kind.
2. The route choice in `docs/proposals/goal18-l1a-mermaid.md`.
3. The 9 existing pending items plus the I05 exit-afterimage class (last section
   of `docs/goal18-l5-attribution.md`).

## Steps

1. **Enter the exemptions in the register**: per the adjudication, write the 10
   branches into `test/fixtures/render-diff/visible-string-exemptions.json`
   (including the assigned `userDecisionId`); if the 9 class-A/B entries are
   approved, the new kind must first be added to the
   `load_visible_string_exemptions` enumeration in `scripts/render-diff.py`.
   The full gate must go green under 74caa2649 at this point — this is the
   baseline green point before the upgrade.

2. **Anchor rewrite**: `scripts/set-baseline.sh 53fa77ccd8a279eb87e92294ef3687b03ff80112`
   (already rehearsed). `python3 scripts/baseline-anchor.py check` must then be
   green.

3. **Model-data pin**: `PI_AI_MODEL_DATA_PACKAGE`/`PI_AI_MODEL_DATA_SHA256` in
   `scripts/render-diff.py` are manually updated to the artifacts corresponding
   to v0.84.1 (take the SHA-256 of the new `npm pack` package).

4. **Freeze the new baseline checkout**: delete the cache directory
   `/tmp/cadr-render-diff-pi-74caa2649` so that `ensure_baseline` rebuilds it
   against the new anchor (I5's content check changes over together with the
   marker). **The G5 toolchain switch is done in this same step** (node/npm on
   the WSL side, see goal18.md Part G5; the cache must be rebuilt after the
   switch, and doing both at the same point in time is cleanest).

5. **File triage**: `./scripts/check-source-parity-drift.sh --from 74caa2649...
   --to 53fa77ccd... ` lists the additions/deletions/renames, and a disposition
   conclusion is given for each one; the 248 changed files are routed by the
   §1a rules of `docs/source-parity.md`. The 17 classes of difference set from
   `enumerate-baseline-diff.py` are dispositioned item by item (the results are
   already recorded in `docs/source-parity-upgrade.md`).

6. **Land the new capabilities** (driven by the enumerated difference set, all
   with tests/scenarios): LaTeX rendering, half-page scrolling and the 6
   prompt-history key actions, `--tui-mode`, 3 new settings items, the two
   providers baseten/qwen-token-plan-individual, `AGENTS.override.md`, the
   AI_AGENT/STY/ZELLIJ environment variables, the `scrollbarThumb` theme token,
   the follow-up to the `AuthCommandError` rename, and the
   `terminate`/`isSubscription`/`trackEventBusSubscription` extension fields.
   Mermaid is executed along the adjudicated route.

7. **Re-close the four ledgers**: all 670 rows of the source ledger
   dispositioned (缺失 0); the behavior/presentation/non-functional ledger
   figures are verified by the I4 machine reconciliation.

8. **L4 no-blind-spot verification**: the I2-derived difference set is empty or
   fully adjudicated; the I7.3 reverse scan is rerun on v0.84.1 (new components
   such as `mermaid.ts` may introduce new sinks); J's reference integrity covers
   the new documentation surface.

9. **L5 verification**: the L5.1 attribution table is rerun to confirm that
   every row is still caught by a gate first; after I05 lands per the
   adjudication, the L5.2 probe patch is reapplied (the working record is in
   this file and in the L5.1 document).

10. **L6 organization retrospective**: the hit rate of routing the 248 changed
    files by §1a, the amount of human judgement, and how the hotspot files
    performed, written into `docs/code-organization.md` ("worse than expected"
    is permitted).

11. **Closeout**: the full gate + `test-cl.sh` + `verify.sh` +
    `verify-release.sh` all green; G4 (`.tmp/` cleanup + gitignore); binary
    freshness; the version string agreeing in all four places (L3:
    --version/README/CHANGELOG/Release being derived from BASELINE is itself
    the proof).
