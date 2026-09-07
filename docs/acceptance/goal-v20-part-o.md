# Goal 20 Part O — four paths ≤ 1.0

Adjudication: `docs/adjudications.md` 2026-09-07 G.16 `met` (after
supersede of a false booking). Historical 2026-08-18 **blocked**
closeout and the failed walker attempt below stay as record.

Harness: `e4ab46c96` (`GOAL20_PART_O_SLICE=1`). Tip at booking:
`8bef4de85` (no new product invent keep; prior keeps including
`594d066a4` stand). `argv_parse` out of scope.

## Closeout remesures (Friend-MachineD, n=10 warmups=2)

| run | artifact | append | read | load | list_models |
|---|---|---:|---:|---:|---:|
| remesure43 | `/tmp/goal20-part-o-remesure43` | 0.887× | 0.887× | 0.867× | 0.067× |
| remesure44 | `/tmp/goal20-part-o-remesure44` | 0.870× | 0.892× | 0.984× | 0.065× |
| remesure45 | `/tmp/goal20-part-o-remesure45` | 0.997× | 0.859× | 0.706× | 0.067× |

All four ≤1.0× on remesure43 and remesure44 (predicate). remesure45 is
safety. Thin margins (append 0.997×, load 0.984× on 44) remain host-noise
risk; §5.2.

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
| r41 | `/tmp/g20-po-r41` | 0.895× | 0.929× | 0.994× | 0.058× |
| r42 | `/tmp/g20-po-r42` | 0.812× | **1.073× OPEN** | 0.937× | 0.068× |

False `met` booking cited no-hyphen paths that are missing; hyphenated
`remesure-35`/`-36` were ALL4 once but r41→r42 failed reconfirm.
Superseding ruling: `docs/adjudications.md` 2026-09-07 G.16 supersede.
Later quiet-tip remesure43+44 closed G.16 as `met` (see top of file).
