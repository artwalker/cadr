# g26 h-harness-storage

status: met-beat
worktree: /tmp/cadr-g26-h-harness (g26-h-harness, exclusive, tip src clean)
ratio: **0.984×** (2351.964 / 2390.273 µs)

## Ratios

Friend-MachineD, slices unset, n=5, fresh cadr mill, reused fair `pi.json`.

| step | cadr µs | ratio | verdict |
| H0 fair | 13140.144 | 5.50× | baseline |
| H1 octet+hash JSON | 5141.897 | 2.15× | kept |
| H2 schema walker + hash fallback | 2351.964 | 0.984× | kept, stop |

gate: PASS enforced-only harness_storage.open_walk
failures: [] (help-text OBS skipped under --only-enforce)
observed exact: entry_count=514 leaf_id=e00513 ingested=514 session_id and source_leaf_id match
booked shape: branch_entry_count cadr 322 / pi 514, unchanged

## Product keep

`open-jsonl-session-storage` no longer reads the file as a UTF-8 string and splits lines. It uses the existing octet JSONL reader. Version-3 body lines parse as session records. A line the schema walker rejects still loads through `parse-json-octets`, so branch-summary reload stays valid. Trailing newline repair runs only when the reader saw no final LF.

## Patches (parent lands)

`/tmp/g26-h-harness-keep.patch` `src/cadr-agent/storage/jsonl.lisp` + `src/cadr-agent/session/migration.lisp`
`/tmp/g26-h-harness-dispositions.patch` this metric only, met-beat + invent evidence
`/tmp/g26-h-harness-audit.patch` `.audit/goal26-decisions.tsv` append
no PR, no push, tip src not dirtied

## Evidence

`/tmp/g26-harness-invent-h2/` keep remesure (do not overwrite fair summary)
`/tmp/cadr-g26-h-harness/docs/benchmarks/goal26-evidence/harness_storage-invent/`
`/tmp/g26-h-harness-decisions.tsv`

## Deviations

How-skill explorers skipped. Nested worker, jsonl open is one module.
Opening a PR skipped. Parent lands patches.
Trail reviewer skipped. Nested subagent.
Worktree py OBS skip used for remesure then reverted from the keep tree. Tip already carries the dirty equivalent.

## Follow-ups

None required for ≤1.0×. `branch_entry_count` 322 vs 514 stays booked.
