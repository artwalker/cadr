# harness_storage.open_walk fair ruler

Goal 23 baseline pi v0.87.0 (`16787ad5b`) dropped the Pair 26 adapter. `JsonlSessionRepo` takes `fileSystem` plus `Context`. Session write/read is `createBranch` / `insertEntry` / `findEntries` / `Branch.findEntries`. The mill used `fs` / `appendEntry` / `getLeafId` / `findEntriesOnBranch`, so ingest died on `absolutePath` and the walk never timed.

## What both sides pay

| side | open | entries | branch |
|---|---|---|---|
| cadr | `jsonl-session-repository` `session-repository-open` | `harness-session-entries` | `harness-session-branch` |
| pi | `JsonlSessionRepo.open(metadata, context)` | `session.findEntries({ order: "asc" }, context)` | `branch.findEntries({ start: leafId, order: "oldestFirst" }, context)` |

Ingest is outside the mill. Pi ingest creates a v4 jsonl session, maps v3 records onto v4 entries (model/thinking/label/session_info become `custom`), commits one transaction, then closes. Each timed sample reopens.

Observed exact keys stay `entry_count`, `leaf_id`, `ingested_entry_count`, `session_id`, `source_leaf_id`. Friend-MachineD this remeter: 514 / `e00513` / 514 / `019f0000-0000-7000-8000-00000000cadr` / `e00513`. `branch_entry_count` is still the booked shape gap (cadr 322 / pi 514) and is not an exact key.

## What this is not

Not a SQLite stub walk. `GOAL20_ALLOW_SQLITE_STUB` stays unset. Pi `sqlite_session` is try/caught so the mill can reach jsonl. That slot is not this pair.

Not a RATIO_CEILINGS drop. Not leftover collect vs V8. Not a Goal 20-25 rewrite.

## Evidence hygiene

Friend-MachineD fair remeter, slices unset, n=5: **5.50×** (13140.144 / 2390.273 µs). Gate PASS `enforced-only:harness_storage.open_walk`, failures `[]`. CadR mill reused from `/tmp/g26-websocket-fair-remesure/cadr.json` (same host, same n). Pi mill after the adapter. Full reports: `/tmp/g26-harness-fair-remesure/`.

5.50× is above 1.0×, so disposition stays open-parity. Invent next: Lisp `jsonl.lisp` open+entries+path, not a fake 322-entry branch.
