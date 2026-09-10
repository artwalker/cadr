# Goal 26 h-cli-support-writes-slot

Unit `h-cli-support-writes-slot` on worktree `/tmp/cadr-g26-h-support-writes-slot` (branch `g26-h-support-writes-slot`, tip `219a3edd0` plus copied remeter/threads). Slices unset. Friend-MachineD. Pair gate PASS. Pi JSON reused from `/tmp/g26-support-invent-remesure7`.

## Status

Stop predicate for the three writes is **not met**. All three stay **open-parity**. No silent freeze. No leftover-only keep. Product `atomic-file.lisp` restored to HEAD. No parent keep patch.

Slot tax was measured. The remainder is essence (SBCL stream atomic-write vs V8 `writeFileSync`+`renameSync` inside a full-GC paired slot). Do not open a second posix hunt.

## Ratios

Final tree is HEAD write path. Invent h1 (skip mkdir when parent exists) remesured then reverted.

| metric | cadr µs | pi µs | ratio | disposition |
| --- | --- | --- | --- | --- |
| cli_support.write_overwrite | 405.319 (h1) / 886.632 (HEAD) | 266.309 | 1.522× invent / 3.329× HEAD | open-parity |
| cli_support.write_hello | 240.890 (h1) / 808.253 (HEAD) | 140.315 | 1.717× invent / 5.760× HEAD | open-parity |
| cli_support.write_empty | 155.544 (h1) / 466.509 (HEAD) | 42.435 | 3.666× invent / 10.994× HEAD | open-parity |

## Isolated vs paired hello

Isolated `atomic-write-utf8` hello on this worktree image is **128.960µs**. Leftover paired hello is **140.315µs**. Isolated already sits at leftover.

Harness-faithful isolated (full GC, 5 reps, CLOCK_MONOTONIC) utf8 hello is **326.752µs**.

Paired HEAD hello is **808.253µs**. Paired h1 hello is **240.890µs**. Prior posix h2 paired hello was 249µs. The ~100µs h2-vs-isolated gap is the collect slot (full GC then 5 reps in the giant paired image), not another unix-open shape.

`:durability :none` did not move isolated hello (147µs flush and none at n-times; slot micro none was not faster than flush).

## What the ruler times

Writes time `atomic-write-utf8` / leftover `activateManagedReleaseWrite` only. Collect mkdir is outside the timed lambda on both remeters. Product `call-with-atomic-replacement` still called `ensure-directories-exist` on every write until h1.

Leftover timed body is `writeFileSync(tmp)` + `renameSync` + `rmSync(force)`. No `flush: true`. Node default flush is false, so it does not fsync. `:durability :none` was allowed and was not the keep.

## Kept

None for writes. Remeter/threads copies match parent. Not new product.

## Reverted

h1 skip `ensure-directories-exist` when `(probe-file parent)`. Nested missing-parent still created `a/b/c/hello.txt`. All three ratios stayed >1.0×. Full revert.

## Patches (parent land)

None. Do not apply product write patches.

## Evidence

- `/tmp/g26-support-writes-slot-h1/` (invent remesure, then product reverted)
- `/tmp/g26-support-writes-slot-isolated.txt`
- `/tmp/g26-h-support-writes-slot-decisions.tsv`
- remesure `/tmp/g26-h-support-writes-slot-remesure.sh`

## Deviations

Opening a PR skipped. Standing says patches for parent land, no gt/rebase.

Nested how-skill and Attention second-model review skipped. This worker is already a subagent.

Hillclimb plateau step skipped. Brief allows one hypothesis then stop if still >1.0×.

Tip `/root/projects/cadr` not dirtied by this unit.

## Principles that changed a choice

**Prove it works.** Keep/revert used Friend-MachineD remesure medians, not the 129µs isolated hello.

**Build the lever.** Frozen command is `/tmp/g26-h-support-writes-slot-remesure.sh`. SYNC_TIP_PY copies tip `goal20-paired-paths.py` before the pair gate.

**Laziness protocol.** One product edit (skip existing-dir mkdir). No posix rewrite. No extra API.

**Fix root causes.** Isolated hello already matches leftover, so the paired miss is the timed product extras plus collect GC slot, not a new open(2) shape.

**Sequence verifiable units.** Isolated measure, leftover fsync check, one change, remesure, revert. No stacked knives.

**Separate before serializing.** Exclusive `/tmp/cadr-g26-h-support-writes-slot`. Tip src not written.

**Never block on the human.** Exhaustion writes a gates.md proposal instead of asking whether 1.72× is good enough.

## Next / gates.md proposal

Do not freeze as unreachable. Human gate on `accepted-runtime-gap` for the three writes.

```
## Gate: cli_support.write_overwrite, write_hello, write_empty → accepted-runtime-gap?

- Status: **awaiting human**
- Default if no answer: leave `open-parity` (do not silent-freeze)
- Options: (A) approve `accepted-runtime-gap` (B) continue invent (C) leave open-parity
- Evidence: /tmp/g26-h-support-writes-slot-REPORT.md /tmp/g26-support-writes-slot-h1/ /tmp/g26-support-writes-slot-isolated.txt
- Worker proposal excerpt:

Fair remeter (HEAD stream atomic-write): 3.329× / 5.760× / 10.994× (887/266µs, 808/140µs, 467/42µs).

Isolated atomic-write-utf8 hello 129µs vs leftover 140µs. The write miss is not an isolated syscall shape.

Slot invent (skip mkdir when parent exists, missing-parent still created): 1.522× / 1.717× / 3.666× (405/241/156µs). Nested parent create kept. All three >1.0×. Full revert.

Leftover activateManagedReleaseWrite does not fsync (writeFileSync without flush). :durability :none was legal and did not close hello in isolated slot microbench.

Remainder after measuring the slot tax is essence. Lisp with-open-file + pathname tmp + unwind-protect inside a full-GC 5-rep collect versus V8 writeFileSync+renameSync. Isolated already at leftover. Paired HEAD stays ~808µs hello. No further product knife stays inside atomic replace without a posix rewrite (forbidden as a second hunt) or dropping atomicity / parent-create.

Forbidden as a close: leftover-only win, RATIO_CEILINGS drop, silent frozen-unreachable, timing mkdir out of the product function by deleting parent-create behavior.
```

## Iterations

Kept. None for writes.

Reverted. h1 skip existing-dir mkdir.
