# Goal 20 Part O — met closeout

Adjudication: `docs/adjudications.md` 2026-08-18 Part O (historical
blocked probe record); **2026-09-07 G.16 `met`** (Part O exit predicate).
Goal 20's exit for the four paired paths is **met** on tip+keep with
Friend-MachineD remesure35+36 (`GOAL20_PART_O_SLICE=1` n=10).
`RATIO_CEILINGS` unchanged. **Not independently audited by a separate
advisor** (§5.2).

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

Historical (2026-08-18): probes exhausted and still > 1.0 → blocked
with what was tried.

**2026-09-07 met:** tip `e4ab46c96` + load-session linear-chain walker;
remesure35+36 all four paths ≤1.0× on the same run. Booking:
`docs/benchmarks/goal20-paired-over-1x.md` Part O section; G.16 in
`goal-v20-part-g.md`.
