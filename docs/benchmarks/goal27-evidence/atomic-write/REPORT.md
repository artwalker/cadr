# Goal 27 h-atomic-write

Unit `h-atomic-write` on worktree `/tmp/cadr-g27-atomic-write` (branch `g27-atomic-write`, tip `219a3edd0` plus copied remeter/threads). Slices unset. Friend-MachineD. Pair gate PASS. Pi JSON reused from `/tmp/g26-support-invent-remesure7` because leftover `activateManagedReleaseWrite` is still `writeFileSync`+`renameSync` with no flush.

## Status

Keep bar not met. All three writes stay open-parity. Product `atomic-file.lisp` restored to HEAD. No parent keep patch.

## Ratios versus HEAD

HEAD (kept tree) from remesure7, pi reused.

| metric | cadr µs | pi µs | ratio vs leftover |
| --- | --- | --- | --- |
| cli_support.write_overwrite | 886.632 | 266.309 | 3.329× |
| cli_support.write_hello | 808.253 | 140.315 | 5.760× |
| cli_support.write_empty | 466.509 | 42.435 | 10.994× |

Invent (reverted):

| metric | h1 | h2 posix | HEAD |
| --- | --- | --- | --- |
| write_overwrite | 3.251× (866µs) | 3.311× (882µs) | 3.329× |
| write_hello | 4.394× (617µs) | 4.977× (698µs) | 5.760× |
| write_empty | 12.248× (520µs) | 11.298× (479µs) | 10.994× |

Empty was slower than HEAD on both knives. Goal 27 needs all three strictly faster. Full revert.

## Byte check

PASS on both invent trees. Hello/overwrite/empty bytes matched. Nested missing parent `a/b/c/hello.txt` was created. Error path left old target bytes. No leftover `.tmp` after success. Rename stayed.

After revert the product path is HEAD again.

## What the ruler times

Writes time `atomic-write-utf8` / leftover `activateManagedReleaseWrite` only. Collect mkdir is outside the timed lambda. Product `call-with-atomic-replacement` still called `ensure-directories-exist` on every write after revert.

Leftover timed body is `writeFileSync(tmp)` + `renameSync` + `rmSync(force)`. No `flush: true`. Hypothesis was not spent on `:durability :none` alone. O_TRUNC was not retried (Goal 26 hello regression).

## Kept

None. Remeter/threads copies match parent dirty tip. Not new product.

## Reverted

h1 skip mkdir when `(probe-file parent)`. Empty 12.248× vs HEAD 10.994×.

h2 posix `unix-open` exclusive + `unix-write` + `unix-rename`, mkdir on ENOENT. Empty 11.298×. Samples overlap HEAD empty (442–536µs vs 442–549µs). Hello improved vs HEAD but the keep bar is all three.

## Patches (parent land)

None. Do not apply `/tmp/g27-atomic-write.patch`. File not written.

## Evidence

- `/tmp/g27-atomic-write-h1/`
- `/tmp/g27-atomic-write-h2/`
- `/tmp/g27-atomic-write-decisions.tsv`
- remesure `/tmp/g27-atomic-write-remesure.sh`
- byte check `/tmp/g27-atomic-write-bytes.sh`

## Deviations

Opening a PR skipped. Standing says patches for parent land, no gt/rebase.

Nested how-skill skipped. This worker is already a subagent.

Hillclimb plateau after two named knives. Brief forbade flush-only and the Goal 26 O_TRUNC retry.

Tip `/root/projects/cadr` not dirtied by this unit. Parent still owes `docs/benchmarks/goal27-dispositions.tsv` and `.audit/goal27-decisions.tsv` if it records this close.

## Principles that changed a choice

**Prove it works.** Keep/revert used Friend-MachineD remesure medians, not Goal 26's 57µs posix empty.

**Build the lever.** Frozen command is `/tmp/g27-atomic-write-remesure.sh`. SYNC_TIP_PY copies tip `goal20-paired-paths.py` before the pair gate.

**Laziness protocol.** Stopped after skip-mkdir then posix. Did not add O_TRUNC or a flush-only knife.

**Sequence verifiable units.** h1 remesure, revert empty miss, then posix remesure, then full revert.

**Separate before serializing.** Exclusive `/tmp/cadr-g27-atomic-write`. Tip src not written.

**Never block on the human.** Empty miss closed the unit instead of asking whether 4.39× hello is enough.

## Iterations

Kept. None.

Reverted. h1 skip existing-dir mkdir. h2 posix exclusive write+rename.
