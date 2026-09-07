# harness_storage.open_walk frozen-unreachable

Class: product-path (not leftover-replica).

Timed work: cadr `jsonl-session-repository` open + `harness-session-entries` + `harness-session-branch` vs pi `JsonlSessionRepo.open` + `findEntries` + `findEntriesOnBranch` (Pair 26).

Why 1.0x is unreachable on this ruler:
1. Observed `branch_entry_count` is a booked shape gap (cadr 322 / pi 514). That is not leftover collect vs V8.
2. Goal 23 baseline pi v0.85.1 removed the booked adapter: `JsonlSessionRepo` now requires `fileSystem` plus `Context`, and Session no longer has `appendEntry` / `getLeafId` / `findEntriesOnBranch`. Friend-MachineD remesure with PART_O/FLOOR unset died in ingest (`Cannot read properties of undefined (reading 'absolutePath')`) before a timed walk.
3. Rewriting that adapter is a Goal 23 harness change. Goal 25 forbids rewriting Goal 21-24 as incomplete. A stub walk would be leftover-replica, not met-hillclimb.
4. Last runnable pair: Friend-MachineD 2026-09-04 n=5 1.637x (12224.6 / 7466.2 us), ceiling 8.0x. Product Lisp invent cannot close a pair the baseline no longer executes.

Banned levers: Goal 23 jsonl adapter rewrite, `GOAL20_ALLOW_SQLITE_STUB`-style fake walk, leftover collect vs V8.

Invent attempts this run: 0 product src keeps. 1 remesure attempt aborted on the pi constructor.
