# Goal 26 h-cli-support

Unit `h-cli-support` on worktree `/tmp/cadr-g26-h-support` (branch `g26-h-support`, tip `219a3edd0`). Slices unset. Friend-MachineD. Gate PASS. Websocket TCP_NODELAY + dotted-IPv4 left in the parent mjs copy. Not reverted.

## Status

Three of six metrics met-beat. Three writes stay open-parity. No silent freeze. No leftover-only keep.

Stop predicate (all six ≤1.0×) not met.

## Ratios

Final kept tree, fair remeter, `/tmp/g26-support-invent-remesure7` (cadr rebuilt, pi reused from remesure4).

| metric | cadr µs | pi µs | ratio | disposition |
| --- | --- | --- | --- | --- |
| cli_support.write_overwrite | 886.632 | 266.309 | 3.329× | open-parity |
| cli_support.write_hello | 808.253 | 140.315 | 5.760× | open-parity |
| cli_support.write_empty | 466.509 | 42.435 | 10.994× | open-parity |
| cli_support.threads_current | 0.028 | 0.064 | 0.440× | met-beat |
| cli_support.threads_absent | 0.040 | 0.062 | 0.642× | met-beat |
| cli_support.close_watcher | 0.040 | 0.135 | 0.297× | met-beat |

## What the ruler times

Writes time `atomic-write-utf8` / leftover `writeFileSync`+`renameSync` only. Observed still reads the file.

Threads time `stop-thread-for-cleanup` / `stopThreadForCleanup` on nil or the current-thread token. The old leftover timed `handle == null` and `isMainThread` without calling a cleanup function.

Close times two nil `close-watcher` / `closeWatcher` calls. No handler-case, no result object in the timed slot.

## Kept

Local nil/current cond on `cadr-cli` and `cadr-core` `stop-thread-for-cleanup`, with keyword parse only on the rest path.

Fair remeter in `scripts/goal20-paired-paths.lisp` and `.mjs`.

`scripts/goal20-paired-paths.py` help-text skip when `--only-enforce` is scoped (same as parent dirty tip).

cadr-core FiveAM 68/68 after the thread change.

## Reverted

Posix exclusive open+write on `atomic-file.lisp`. Fair remeter4 with that invent was overwrite 1.530×, hello 1.985×, empty 1.427×. Standing keep bar is ≤1.0×, so full revert to HEAD `atomic-file.lisp`.

O_TRUNC stable `.tmp` (remesure5). Writes did not improve. Reverted.

Close `unless`/`return-from`. Made close worse. Product `when watcher` restored (matches HEAD).

r3 close 0.29× and empty 0.75× were a slower pi plus leftover null checks. Discarded.

## Patches (parent land)

- `/tmp/g26-h-support-threads.patch` product threads
- `/tmp/g26-h-support-remeter-lisp.patch` vs HEAD lisp (includes restored `GOAL20_COLLECT_ONLY`)
- `/tmp/g26-h-support-remeter-mjs.patch` vs parent dirty mjs (websocket keep not in this hunk)
- `/tmp/g26-h-support-py.patch` scoped help-text skip vs HEAD (parent already has it)
- `/tmp/g26-h-support-keep.patch` combined vs HEAD (mjs also contains parent websocket vs clean tip)

Do not `git apply` the combined keep patch onto a tip that already has the websocket mjs. Use remeter-mjs + threads + remeter-lisp.

## Evidence

- `/tmp/g26-support-invent-remesure4/` fair remeter + posix invent (not kept)
- `/tmp/g26-support-invent-remesure7/` kept tree
- `/tmp/g26-support-final/`
- worktree `docs/benchmarks/goal26-evidence/cli_support-invent/`
- `/tmp/g26-h-support-decisions.tsv`
- remesure `/tmp/g26-h-support-remesure.sh`

## Deviations

Opening a PR skipped. Standing says patches for parent land, no gt/rebase.

Nested how-skill and Attention second-model review skipped. This worker is already a subagent.

Tip `/root/projects/cadr` not dirtied.

## Next step for the three writes

Re-land posix `open(O_EXCL)`+`write`+`rename` (r4 1.53/1.99/1.43), then remove `handler-case` from the success path. Microbench put handler-case at about 19µs extra. Empty still needs another ~20µs after that to reach 1.0× vs leftover 42µs. Do not freeze as unreachable.

## Iterations

Kept. Thread cond. Remeter.

Reverted. Posix write. O_TRUNC tmp. Close unless. Unfair leftover constructors.
