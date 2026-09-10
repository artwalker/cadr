# Goal 26 h-cli-support-writes

Unit `h-cli-support-writes` on worktree `/tmp/cadr-g26-h-support-writes` (branch `g26-h-support-writes`, tip `219a3edd0` plus copied remeter/threads). Slices unset. Friend-MachineD. Pair gate PASS. Pi JSON reused from remesure7/h1.

## Status

Stop predicate for the three writes is **not met**. All three stay **open-parity**. No silent freeze. No leftover-only keep. Product `atomic-file.lisp` restored to HEAD. No parent keep patch.

## Ratios

Final tree is HEAD write path (same as remesure7). Best invent (h2, reverted) on `/tmp/g26-support-writes-h2` with reused pi.

| metric | cadr µs | pi µs | ratio | disposition |
| --- | --- | --- | --- | --- |
| cli_support.write_overwrite | 422.005 (h2) / 886.632 (HEAD) | 266.309 | 1.585× invent / 3.329× HEAD | open-parity |
| cli_support.write_hello | 249.367 (h2) / 808.253 (HEAD) | 140.315 | 1.777× invent / 5.760× HEAD | open-parity |
| cli_support.write_empty | 56.917 (h2) / 466.509 (HEAD) | 42.435 | 1.341× invent / 10.994× HEAD | open-parity |

h1 (mkdir still timed): 2.678 / 4.208 / 9.536. h3 (O_TRUNC): 1.574 / 1.949 / 1.202. Hello lost, so h3 reverted.

## What the ruler times

Writes time `atomic-write-utf8` / leftover `activateManagedReleaseWrite` only. mkdir is outside the timed slot on both remeters.

## Kept

None for writes. Threads/close remeter copies stayed in the worktree only to match parent. Not new product.

## Reverted

h1 posix exclusive without handler-case. Still paid `ensure-directories-exist` on every success.

h2 lazy mkdir on ENOENT. Best three-metric invent. Bar is ≤1.0×, full revert.

h3 stable pid tmp + `O_TRUNC`. Empty 1.202×. Hello 1.949× worse than h2. Reverted.

## Patches (parent land)

None. Write invent missed ≤1.0×. Do not apply product write patches.

Record of reverted h2 (not for land): see this report's h2 description. Evidence dirs hold remesure JSON.

Copied remeter/threads in the worktree match parent dirty tip. Do not land them again from this unit.

## Evidence

- `/tmp/g26-support-writes-h1/`
- `/tmp/g26-support-writes-h2/` (best invent)
- `/tmp/g26-support-writes-h3/`
- worktree `docs/benchmarks/goal26-evidence/cli_support-writes-invent/`
- `/tmp/g26-h-support-writes-decisions.tsv`
- remesure `/tmp/g26-h-support-writes-remesure.sh`

## Deviations

Opening a PR skipped. Standing says patches for parent land, no gt/rebase.

Nested how-skill and Attention second-model review skipped. This worker is already a subagent.

Tip `/root/projects/cadr` not dirtied by this unit.

## Principles that changed a choice

**Prove it works.** Keep/revert used remesure medians, not the 126µs isolated hello microbench.

**Build the lever.** Frozen command is `/tmp/g26-h-support-writes-remesure.sh`. SYNC_TIP_PY copies tip `goal20-paired-paths.py` before the pair gate.

**Laziness protocol.** h3 trunc was extra shape for leftover match. Hello got worse, so it died. No extra API.

**Fix root causes.** h1 leftover 405µs empty was timed `ensure-directories-exist` on an already-created scratch dir, not the write syscalls.

**Sequence verifiable units.** h1 remesure, then h2, then h3, then revert. No stacked unmeasured knives on the keep bar.

**Never block on the human.** Exhaustion wrote a gates.md proposal instead of asking whether 1.58× is good enough.

**Separate before serializing.** Exclusive `/tmp/cadr-g26-h-support-writes`. Tip src not written.

## Next / gates.md proposal

Do not freeze as unreachable. Human gate on `accepted-runtime-gap` for the three writes.

```
## Gate: cli_support.write_overwrite, write_hello, write_empty → accepted-runtime-gap?

- Status: **awaiting human**
- Default if no answer: leave `open-parity` (do not silent-freeze)
- Options: (A) approve `accepted-runtime-gap` (B) continue invent (C) leave open-parity
- Evidence: /tmp/g26-support-writes-h2/ and docs/benchmarks/goal26-evidence/cli_support-writes-invent/
- Worker proposal excerpt:

Fair remeter (HEAD stream atomic-write): 3.329× / 5.760× / 10.994× (887/266µs, 808/140µs, 467/42µs).

Best keepable-shape invent (posix unix-open/write/rename, no handler-case, mkdir only on ENOENT): 1.585× / 1.777× / 1.341× (422/266, 249/140, 57/42). cadr-core FiveAM 68/68. Nested missing-parent still creates dirs.

O_TRUNC stable tmp improved empty to 1.202× and worsened hello to 1.949×. Reverted.

Unwind-protect drop is ~19µs in microbench. That can finish empty versus 42µs leftover. It cannot close hello's remaining ~109µs or overwrite's remaining ~156µs.

Remainder is SBCL `unix-open`/`unix-write`/`rename` plus Lisp wrappers versus V8 `writeFileSync`+`renameSync` on the same temp+rename product. Isolated microbench hello ~126–158µs already sits at leftover's 140µs. The paired-path median stays higher. No further product knife stays inside atomic replace without dropping atomicity or moving mkdir/encoding into the leftover.

Forbidden as a close: leftover-only win, RATIO_CEILINGS drop, silent frozen-unreachable, timing mkdir out of the product function by deleting parent-create behavior.
```

## Iterations

Kept. None for writes.

Reverted. h1 posix+mkdir. h2 lazy mkdir. h3 O_TRUNC.
