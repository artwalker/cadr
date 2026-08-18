# Goal 20 Part G — evidence matrix

Inventory for `goal20-draft.md` §十四 items 1–17.
This file is **not** a Part G pass and **not** a Goal 20 closeout.
No new measurements. `met` requires at least one openable SHA or path.

Status: `met` / `missing` / `blocked`.

| item | status | evidence | notes |
|---|---|---|---|
| 1 Part L reverse visible strings | met | `docs/acceptance/goal-v20-part-l.md`; `test/cadr-cli/goal20-part-l-test.lisp` (`goal20-l-xai-*`, `goal20-l-custom-entry-*`); `scripts/baseline-string-reachability.py`; `scripts/cadr-visible-output-origin.py`; `b90422a56` | L0 literals locked: `no models are available for that provider`; renderer must not emit `NIL`. |
| 2 Part M denominators | met | `docs/test-matrix.md`; `docs/acceptance/goal-v20-part-m.md`; `b90422a56` | Every deterministic `verify.sh` stage declares checks / does-not-check / pass-means. Provider slots from `sb-mop:class-slots`; one exclusion `baseline-source`; xAI `grok-4.5`. |
| 3 Part N introspection | met | `c6a164102`; `docs/acceptance/goal-v20-part-n-slynk.md` | Live `--slynk` + `(cadr-cli:active-agent)` on a running cadr. Not load-and-probe. N2.5 in `docs/acceptance/goal-v20-part-n.md` remains the older load-and-probe writeup. |
| 4 Part D three-game gate proof | met | `docs/acceptance/goal-v20-part-d.md`; `test/cadr-cli/goal20-example-games-test.lisp`; `dfd1cf676` | Before-fix screens unequal (snake SGR, ttt cursor, invaders no move). Paper A/B passed; that is not “the three games play”. Live tic-tac-toe was a P0 (`165edc9c2` steer, `edb9d6dca` overlay bind), not this cell. |
| 5 Part A constructed degeneration | met | `8a843c395`; `docs/acceptance/goal-v20-part-a-degeneration.md` | Isolated 3.29× cold-start degeneration. The 750 ms ceiling is the fail-closed check; the cold band is informational. |
| 6 Existing instruments before/after | met | `docs/test-matrix.md` `GOAL20_TEST_CHECKS` 19037; `CHANGELOG.md` Unreleased K2–K9 + P.1–P.4 + P0 FiveAM series; `docs/performance.md` Goal 11 + paired-path tables; K9 `0fd767e87` official core 120/122 | No single G.6 snapshot table. Booked series only. Full-tier render is not a separate booked pair here. |
| 7 Prior user adjudications | met | `docs/adjudications.md` (incl. `46fabd9bb` Part C / G.12); `docs/proposals/` | K reports record N_i untouched. |
| 8 Part B ledger write-back | met | `docs/acceptance/goal-v20-part-b.md`; `scripts/record-performance-history.py`; `scripts/write-performance-ledger.py`; `docs/performance.md` `GOAL20_PERF_HISTORY_*` / `GOAL20_PAIRED_PATHS_*`; `c287896ce` | Script-written series. `quick=yes` rows are bookings, not enforced full samples. |
| 9 Part C compression | met | keep `46fabd9bb`; volume column `ff2e4f03f` | Keep is decided. History keys are still `coldStartMedianUs` / `frame5000MedianUs` / `frame5000MedianBytes`. The first `binary_bytes` cell waits for the next isolated verify; do not invent a script. |
| 10 Part E example surfaces | met | `224450447`; `docs/acceptance/goal-v20-part-e-close.md` (79 = 23 pty / 51 suite-lock / 5 blocked) | Paper A/B passed. Live tic-tac-toe defects were P0 (`165edc9c2` steer, `edb9d6dca` overlay bind); this cell does not close them. |
| 11 Part F ledger hygiene | met | policy `f6ebfb225` (`docs/development-policy.md` §5 includes `source-parity.md` Evidence/reason); families `85410e878` / `ca8025621` / `674ff7212`; `scripts/check-source-parity-cadr-paths.py`; `docs/source-parity.md` §3a `SP-F*` | Header still `examples=99/99/0`. SP-F1/SP-F2 state the current coverage split. |
| 12 Part K dual-ref and I0 | missing | ledger `docs/code-organization.md` `GOAL20_LISPIFICATION_LEDGER` files=295 lines=122238 unevaluated=0 needs-rewrite=0 no-rewrite=147 in-progress=0 done=148; J `8f691682b`; K2 `773153d60`; K3 `3bdf12674`; K4 `ba533f87b`; K5 `ae879d4ee`; K6 `abb31e13a`; K7 `f62784937`; K8 `61a5d0283`; K9 `0fd767e87`; G.12 ruling `docs/adjudications.md` 2026-08-18; 10% audit `goal20-state.md` `[done · advisor]` 15/15 | Ledger has no rewrite/unevaluated/in-progress; blocked 0 (under 5%). H class named: K2/K3 `pairable-uncovered`; K4 `unpairable`; J no H pair. K5–K9 **缺标记**, not 缺改写. H `pairable-uncovered` `done` is single-ref pending H — not 「不劣于 pi」, not 148 new benches. Predecessor for that dual-ref gap: H 未覆盖. |
| 13 Part H pairs and share | met | `docs/acceptance/goal-v20-part-h.md`; `docs/benchmarks/goal20-paired-paths.json`; `docs/benchmarks/goal20-unpaired-paths.json`; `2aea08382` | Four non-TUI pairs. Falsifiable vs baseline 17.0% of lines (35 files). Unpairable 6.1%. pairable-uncovered 76.9%. H does not require ratio ≤ 1. |
| 14 Part I ledger columns | met | `docs/acceptance/goal-v20-part-i.md`; `docs/code-organization.md` §2; batches `de4c60f95`–`fc0634c4c` | One table, closed states, every `src/**/*.lisp` row, dual file/line progress. I report's initial 293/121105 lock was refreshed on the current identity line. |
| 15 Part J pilot retro | met | `docs/acceptance/goal-v20-part-j.md`; `8f691682b`; `src/cadr-core/time.lisp` | Report names three process defects (re-asking I, no H cell, ceremony red commit). Not "流程顺利". |
| 16 Part O four paths ≤ 1.0 | blocked | `4cd3a510b`; `docs/acceptance/goal-v20-part-o.md`; `docs/performance.md` paired table (append 2.21×, read 3.93×, load 4.28×, list_models_render 3.18×) | O blocked is not a performance close. Next knife is Part P (SBCL/live-image ceiling; floor is pi). Beating pi is not a stop. `argv_parse` is out of scope. |
| 17 Part P CL ceiling | missing | spec `goal20-draft.md` 十B; ruling `docs/adjudications.md` 2026-08-18 CL ceiling (`1a24eea1d`); draft `docs/acceptance/goal-v20-part-p.md`; levers `c183539e7`–`f3ccf75f6` | Not `met`. Advisor vetoed `met` on `40db3f88a` and `c53e13c47`, and vetoed `blocked` on `7e4ec5201`. `blocked` is only for new deps / safety / format / mmap / observable SIMD. P.8 is leftover. Advisor has not written G.17 may be `met`. |

## Not claimed

- Goal 20 complete.
- Part G passed.
- 148 new wall-clock pairs.
- 「不劣于 pi」 for H `pairable-uncovered` `done` files.
- A complete `binary_bytes` history series (G.9 keep is booked; first history cell waits).
- Paper A/B passing means the three games play.
- Ratios above 1.0× vs pi mean Part P is done.
