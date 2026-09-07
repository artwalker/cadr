# Goal 20 Part G — evidence matrix

Inventory for `goal20-draft.md` §十四 items 1–17.
Part G matrix is terminal (`met` ∪ `blocked`). Goal 20 closeout booked in `docs/adjudications.md` 2026-09-07.
No new measurements. `met` requires at least one openable SHA or path.

Status: `met` / `missing` / `blocked`.

| item | status | evidence | notes |
|---|---|---|---|
| 1 Part L reverse visible strings | met | `docs/acceptance/goal-v20-part-l.md`; `test/cadr-cli/goal20-part-l-test.lisp` (`goal20-l-xai-*`, `goal20-l-custom-entry-*`); `scripts/baseline-string-reachability.py`; `scripts/cadr-visible-output-origin.py`; `b90422a56` | L0 literals locked: `no models are available for that provider`; renderer must not emit `NIL`. |
| 2 Part M denominators | met | `docs/test-matrix.md`; `docs/acceptance/goal-v20-part-m.md`; `b90422a56` | Every deterministic `verify.sh` stage declares checks / does-not-check / pass-means. Provider slots from `sb-mop:class-slots`; one exclusion `baseline-source`; xAI `grok-4.5`. |
| 3 Part N introspection | met | `c6a164102`; `docs/acceptance/goal-v20-part-n-slynk.md` | Live `--slynk` + `(cadr-cli:active-agent)` on a running cadr. Not load-and-probe. N2.5 in `docs/acceptance/goal-v20-part-n.md` remains the older load-and-probe writeup. |
| 4 Part D three-game gate proof | met | `docs/acceptance/goal-v20-part-d.md`; `test/cadr-cli/goal20-example-games-test.lisp`; `dfd1cf676` | Before-fix screens unequal (snake SGR, ttt cursor, invaders no move). Paper A/B passed; that is not “the three games play”. Live tic-tac-toe was a P0 (`165edc9c2` steer, `edb9d6dca` overlay bind), not this cell. |
| 5 Part A constructed degeneration | met | `8a843c395`; `docs/acceptance/goal-v20-part-a-degeneration.md` | Isolated 3.29× cold-start degeneration. The 750 ms ceiling is the fail-closed check; the cold band is informational. |
| 6 Existing instruments before/after | met | `docs/test-matrix.md` `GOAL20_TEST_CHECKS` 19150; `CHANGELOG.md` Unreleased K2–K9 + P.1–P.4 + P0 FiveAM series; `docs/performance.md` Goal 11 + paired-path tables; K9 `0fd767e87` official core 120/122 | No single G.6 snapshot table. Booked series only. Full-tier render is not a separate booked pair here. |
| 7 Prior user adjudications | met | `docs/adjudications.md` (incl. `46fabd9bb` Part C / G.12); `docs/proposals/` | K reports record N_i untouched. |
| 8 Part B ledger write-back | met | `docs/acceptance/goal-v20-part-b.md`; `scripts/record-performance-history.py`; `scripts/write-performance-ledger.py`; `docs/performance.md` `GOAL20_PERF_HISTORY_*` / `GOAL20_PAIRED_PATHS_*`; `c287896ce` | Script-written series. `quick=yes` rows are bookings, not enforced full samples. |
| 9 Part C compression | met | keep `46fabd9bb`; volume column `ff2e4f03f` | Keep is decided. History keys are still `coldStartMedianUs` / `frame5000MedianUs` / `frame5000MedianBytes`. The first `binary_bytes` cell waits for the next isolated verify; do not invent a script. |
| 10 Part E example surfaces | met | `224450447`; `docs/acceptance/goal-v20-part-e-close.md` (79 = 23 pty / 51 suite-lock / 5 blocked) | Paper A/B passed. Live tic-tac-toe defects were P0 (`165edc9c2` steer, `edb9d6dca` overlay bind); this cell does not close them. |
| 11 Part F ledger hygiene | met | policy `f6ebfb225` (`docs/development-policy.md` §5 includes `source-parity.md` Evidence/reason); families `85410e878` / `ca8025621` / `674ff7212`; `scripts/check-source-parity-cadr-paths.py`; `docs/source-parity.md` §3a `SP-F*` | Header still `examples=99/99/0`. SP-F1/SP-F2 state the current coverage split. |
| 12 Part K dual-ref and I0 | met | K2–K9 reports + tip H inventory `needs-pair=0` `pairable-uncovered=0` (297 files / 133658 lines; `goal20-unpaired-paths.py --check`); K5–K9 `## H class` marks + tip inventory notes; G.12 ruling `docs/adjudications.md` 2026-08-18 scoring; close ruling **2026-09-07** | Marks complete (not 148 benches). H unfinished surface closed. Dual-ref per ruling: `paired` falsifiable vs baseline; `unpairable` single-ref; `covered-as-callee` on named thunks. §5.2. |
| 13 Part H pairs and share | met | `docs/acceptance/goal-v20-part-h.md`; `docs/benchmarks/goal20-paired-paths.json`; `docs/benchmarks/goal20-unpaired-paths.json`; tip `--check` 297/133658 paired 80.3% / unpairable 5.7% / callee 14.1% / needs-pair 0 / uncovered 0 | H does not require ratio ≤ 1. Historical first booking SHA `2aea08382` remains. |
| 14 Part I ledger columns | met | `docs/acceptance/goal-v20-part-i.md`; `docs/code-organization.md` §2; batches `de4c60f95`–`fc0634c4c` | One table, closed states, every `src/**/*.lisp` row, dual file/line progress. I report's initial 293/121105 lock was refreshed on the current identity line. |
| 15 Part J pilot retro | met | `docs/acceptance/goal-v20-part-j.md`; `8f691682b`; `src/cadr-core/time.lisp` | Report names three process defects (re-asking I, no H cell, ceremony red commit). Not "流程顺利". |
| 16 Part O four paths ≤ 1.0 | met | keep `e4ab46c96`+ load-session linear-chain walker; remesure35+36 Friend-MachineD `GOAL20_PART_O_SLICE=1` n=10 all four ≤1.0× (`/tmp/goal20-part-o-remesure35`, `/tmp/goal20-part-o-remesure36`); booking `docs/benchmarks/goal20-paired-over-1x.md`; `docs/acceptance/goal-v20-part-o.md`; rulings `docs/adjudications.md` 2026-09-07 G.16 `met` | Part O exit predicate met on tip+keep. Prior 2026-08-18 blocked closeout superseded. **Not independently audited by a separate advisor** (§5.2). `argv_parse` out of scope. |
| 17 Part P CL ceiling | met | invent/floor keep `594d066a4`; remesure25 + remesure26 Friend-MachineD `GOAL20_FLOOR_SLICE=1` n=10 all four ≤1.0× (`/tmp/goal20-floor-remesure25`, `/tmp/goal20-floor-remesure26`); booking `docs/benchmarks/goal20-paired-over-1x.md`; draft `docs/acceptance/goal-v20-part-p.md`; rulings `docs/adjudications.md` 2026-09-05 signer + **2026-09-06 `met`** | Invent/floor quartet closed. **Not independently audited by a separate advisor** (§5.2). User veto retained. |

## Claimed (2026-09-07)

- Goal 20 complete (Part G matrix terminal: every cell `met`).
- Part G matrix terminal.

## Still not claimed

- 148 new wall-clock pairs (G.12 forbids that reading).
- 「不劣于 pi」 for files that were historically `pairable-uncovered` at a K booking (tip class is inventory, not that claim).
- A complete `binary_bytes` history series (G.9 keep is booked; first history cell waits).
- Paper A/B passing means the three games play.
- Extra invent below the closed G.17 floor as a Goal 20 reopen.
