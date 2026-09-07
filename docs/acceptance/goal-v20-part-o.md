# Goal 20 Part O — blocked closeout

Adjudication: `docs/adjudications.md` 2026-08-18 Part O.
Goal 20's exit for the four paired paths is **blocked**, not
ratio ≤ 1.0. `RATIO_CEILINGS` is unchanged. `goal20-paired-paths.sh`
was not re-run for this note. Not a Goal 20 pass.

## Four paths

`argv_parse` is out of scope (`goal20-draft.md` §十四.16).

| path | booked non-quick ratio (`400dbadf4`) | ceiling |
|---|---:|---:|
| `storage_journal.journal_append` | 2.21× | 12.00× |
| `storage_journal.journal_read` | 3.93× | 8.00× |
| `session_pipeline.session_load` | 4.28× | 9.00× |
| `cli_dispatch.list_models_render` | 3.18× | 4.00× |

Source: `docs/performance.md` paired table, Friend-MachineD,
2026-08-15T12:07:28Z, `ratio_gate=enforced`, `quick=no`, samples=5.

## Locked probes 7a–7d

| probe | outcome | booked movement |
|---|---|---|
| 7a | shipped `6211fff2f` | append 8.45× → 2.15× (then 1.90× on that SHA) |
| 7b | abandoned | read 5.42× → 6.20× |
| 7c | skipped | append already 1.90× on `6211fff2f`, below the "> 2×" trigger |
| 7d | abandoned | `list_models_render` 2.74× → 2.97× |

## sprof heat (`5f7c96750`)

`docs/benchmarks/goal20-part-o-remaining-sprof.md`:

- read / load: `parse-json` `PEEK` / `PARSE-STRING`
- append: per-sample mkdir + stringify (`WRITE-JSON-VALUE`)
- `list_models_render`: registry / filesystem, not table `format`

12C-3 (`dacebac5e`) already spent the post-sprof JSON inline
proposal. A JSON library, `safety` drop, or session-format change
needs a new written proposal. That is not this cell.

## Exit

Draft §10-annex item 7: probes exhausted and still > 1.0 → blocked
with what was tried. The completion line (every path ≤ 1.0) was not
reached. This goal records the gap and stops.

## 2026-09-07 hillclimb (superseded `met` attempt)

Harness `e4ab46c96` (`GOAL20_PART_O_SLICE=1`). Tried load-session
linear-chain walker in `migration.lisp`; fuse index-build keep
(`c058581e7`) reverted after A/B showed +65 µs cadr load. Walker
reverted (`3ae98c6c1`) after remesures failed dual ALL4:

| run | artifact | append | read | load | list_models |
|---|---|---:|---:|---:|---:|
| r35 | `/tmp/g20-po-r35` | 0.966× | 0.975× | **1.020× OPEN** | 0.063× |
| r36 | `/tmp/g20-po-r36` | 0.792× | 0.994× | **1.025× OPEN** | 0.062× |

False `met` booking cited missing artifacts
(`/tmp/goal20-part-o-remesure35`, `/tmp/goal20-part-o-remesure36`).
Superseding ruling: `docs/adjudications.md` 2026-09-07 G.16 supersede.
G.16 remains **blocked**.
