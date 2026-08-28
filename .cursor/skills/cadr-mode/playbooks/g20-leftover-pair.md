### Goal 20 leftover pair (measure-only trio)

**You own one file's next three unused slugs. Do not touch sibling files.**
For "pair leftover", "leftover trio", a numbered pair range, or taking
over a Grok Bot leftover Cloud Agent.

This is not a perf rewrite. It is pairing: same fixture bytes, n=5,
append-only freeze JSON, no `src/` speed knives unless the knife
contract names one.

1. Session-pickup if a prior agent or PR exists for this file. Do not
   redo merged or open trios. Open PRs as of the 2026-08-28 handoff
   are listed in `docs/dev-process/grok-bot-handoff.md`.
2. Inventory on `cadr-migration` tip: the file-level `needs-pair` hole,
   slugs already in `pairedMetrics` / Part H / freeze JSON, and slugs
   claimed by open PRs. Pick the next three unused functions. Skip
   with names, do not silently overlap.
3. One worktree, one file. Sibling leftovers on other files belong to
   other knives (`principle-separate-before-serializing-shared-state`).
4. Measure n=5 against the pinned pi cache. Record cadr µs, pi µs,
   ratio, ceiling, rc. Book `>1×` in `docs/benchmarks/goal20-paired-over-1x.md`
   when required. JSON append-only vs tip.
5. Enforce only the new slugs. Run `python3 test/goal20-part-b-ledger-test.py`.
   Skip full `verify.sh` / `test-cl.sh` only when the standing leftover
   knife contract says so; write `skip:` on that todo item.
6. Open a READY PR (not draft unless blocked). Body: inventory, picked
   slugs, skipped slugs, remaining unused on that file, pair table,
   head SHA. Do not merge.

**Reply:** trio numbers, slugs, ratios, PR URL, what remains on the file.
