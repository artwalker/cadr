# Goal 20 Part G — evidence matrix

Inventory for `goal20-draft.md` §十四 items 1–16.
This file is **not** a Part G pass and **not** a Goal 20 closeout.
No new measurements. `met` requires at least one openable SHA or path.

Status: `met` / `missing` / `blocked`.

| item | status | evidence | notes |
|---|---|---|---|
| 1 Part L reverse visible strings | met | `docs/acceptance/goal-v20-part-l.md`; `test/cadr-cli/goal20-part-l-test.lisp` (`goal20-l-xai-*`, `goal20-l-custom-entry-*`); `scripts/baseline-string-reachability.py`; `scripts/cadr-visible-output-origin.py`; `b90422a56` | L0 literals locked: `no models are available for that provider`; renderer must not emit `NIL`. |
| 2 Part M denominators | met | `docs/test-matrix.md`; `docs/acceptance/goal-v20-part-m.md`; `b90422a56` | Every deterministic `verify.sh` stage declares checks / does-not-check / pass-means. Provider slots from `sb-mop:class-slots`; one exclusion `baseline-source`; xAI `grok-4.5`. |
| 3 Part N introspection | missing | N0 `7c907f6fb` `scripts/derive-source-parity-mappings.lisp`; N1 `src/cadr-ai/providers/definitions.lisp`; N2.6 `scripts/cadr-compile-warnings.py`; N2.7 `docs/acceptance/goal-v20-sb-cover.md` `6da7dcf57` | N2.5 in `docs/acceptance/goal-v20-part-n.md` is load-and-probe, not live `--slynk` + `(cadr-cli:active-agent)`. Draft requires that live proof for the xAI trigger. Predecessor: N slynk. |
| 4 Part D three-game gate proof | met | `docs/acceptance/goal-v20-part-d.md`; `test/cadr-cli/goal20-example-games-test.lisp`; `dfd1cf676` | Before-fix screens unequal (snake SGR, ttt cursor, invaders no move). User A/B still required for Goal 20 closeout; that is not this cell. |
| 5 Part A constructed degeneration | missing | `cfa06a9fe`; `docs/benchmarks/goal20-part-a-noise-bands.json`; `test/goal11-performance-gate-test.py` `SelfHistoryInformationalTest` | Bands and fail-closed helper exist. The test injects `263000` vs history `250000` into `self_history_summary`, not a 3× production-image cold start. Draft §十四.5 is unsatisfied. |
| 6 Existing instruments before/after | met | `docs/test-matrix.md` `GOAL20_TEST_CHECKS` 18880; `CHANGELOG.md` Unreleased K2–K9 FiveAM series; `docs/performance.md` Goal 11 + paired-path tables; K9 `0fd767e87` official core 120/122 | No single G.6 snapshot table. Booked series only. Full-tier render is not a separate booked pair here. |
| 7 Prior user adjudications | met | `docs/adjudications.md` (incl. `46fabd9bb` Part C / G.12); `docs/proposals/` | K reports record N_i untouched. |
| 8 Part B ledger write-back | met | `docs/acceptance/goal-v20-part-b.md`; `scripts/record-performance-history.py`; `scripts/write-performance-ledger.py`; `docs/performance.md` `GOAL20_PERF_HISTORY_*` / `GOAL20_PAIRED_PATHS_*`; `c287896ce` | Script-written series. `quick=yes` rows are bookings, not enforced full samples. |
| 9 Part C compression | missing | `docs/benchmarks/goal20-part-c-compression.json`; `8587db53a`; keep `46fabd9bb` / `docs/adjudications.md` 2026-08-18 Part C | Keep is decided. `docs/benchmarks/performance-history.json` keys are `coldStartMedianUs` / `frame5000MedianUs` / `frame5000MedianBytes` — no `binary_bytes` column. Volume/cold-start sequence is missing. Do not invent a script. Predecessor: 体积序列. |
| 10 Part E example surfaces | missing | `docs/acceptance/goal-v20-part-e-batch-0.md`; batch-1 `dfd1cf676`; batch-2 `b90422a56`; `find examples/extensions -mindepth 1 -maxdepth 1 ! -name support.lisp` = 79 | D + two batches cover snake/ttt/invaders + 20 named surfaces. Batch 0 still lists later batches and five blocked rows (`rpc-demo`, `doom-overlay`, `ssh`, `github-issue-autocomplete`, `mac-system-theme`). Not a full-surface close. |
| 11 Part F ledger hygiene | met | policy `f6ebfb225` (`docs/development-policy.md` §5 includes `source-parity.md` Evidence/reason); families `85410e878` / `ca8025621` / `674ff7212`; `scripts/check-source-parity-cadr-paths.py`; `docs/source-parity.md` §3a `SP-F*` | Header still `examples=99/99/0`. SP-F1/SP-F2 state the current coverage split. |
| 12 Part K dual-ref and I0 | missing | ledger `docs/code-organization.md` `GOAL20_LISPIFICATION_LEDGER` files=295 lines=122237 unevaluated=0 needs-rewrite=0 no-rewrite=147 in-progress=0 done=148; J `8f691682b`; K2 `773153d60`; K3 `3bdf12674`; K4 `ba533f87b`; K5 `ae879d4ee`; K6 `abb31e13a`; K7 `f62784937`; K8 `61a5d0283`; K9 `0fd767e87`; G.12 ruling `docs/adjudications.md` 2026-08-18; 10% audit `goal20-state.md` `[done · advisor]` 15/15 | Ledger has no rewrite/unevaluated/in-progress; blocked 0 (under 5%). H class named: K2/K3 `pairable-uncovered`; K4 `unpairable`; J no H pair. K5–K9 **缺标记**, not 缺改写. H `pairable-uncovered` `done` is single-ref pending H — not 「不劣于 pi」, not 148 new benches. Predecessor for that dual-ref gap: H 未覆盖. |
| 13 Part H pairs and share | met | `docs/acceptance/goal-v20-part-h.md`; `docs/benchmarks/goal20-paired-paths.json`; `docs/benchmarks/goal20-unpaired-paths.json`; `2aea08382` | Four non-TUI pairs. Falsifiable vs baseline 17.0% of lines (35 files). Unpairable 6.1%. pairable-uncovered 76.9%. H does not require ratio ≤ 1. |
| 14 Part I ledger columns | met | `docs/acceptance/goal-v20-part-i.md`; `docs/code-organization.md` §2; batches `de4c60f95`–`fc0634c4c` | One table, closed states, every `src/**/*.lisp` row, dual file/line progress. I report's initial 293/121105 lock was refreshed on the current identity line. |
| 15 Part J pilot retro | met | `docs/acceptance/goal-v20-part-j.md`; `8f691682b`; `src/cadr-core/time.lisp` | Report names three process defects (re-asking I, no H cell, ceremony red commit). Not "流程顺利". |
| 16 Part O four paths ≤ 1.0 | blocked | `docs/performance.md` paired table (current `400dbadf4` enforced: append 2.21×, read 3.93×, load 4.28×, list_models_render 3.18×); `docs/benchmarks/goal20-part-o-remaining-sprof.md` | Four paths still > 1.0× after probes 7a–7d. That file: remaining gap is blocked pending adjudication of a new probe. Not a silent pass. `argv_parse` is out of scope. |

## Not claimed

- Goal 20 complete.
- Part G passed.
- Live `--slynk` proof of the xAI trigger.
- A `binary_bytes` history series.
- 148 new wall-clock pairs.
- 「不劣于 pi」 for H `pairable-uncovered` `done` files.
