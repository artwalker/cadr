# Goal 26 unit h-dialog-request

**Status.** open-parity. No product keep. No silent freeze. Not `accepted-runtime-gap` (parent/human only).

**Metric.** `cli_print_rpc.dialog_request` on Friend-MachineD. Direction lower. Stop ≤1.0× on the frozen remesure.

**Consumer.** Operators who need cadr dialog request construction at least as fast as pi. After this unit they still wait on a gate, not a keep.

**Maintainer.** `rpc-dialog-request-object` stays EQUAL `json-object` plus `json-put`. Do not land the struct or the racy scratch.

## Ratios

| run | cadr µs | pi µs | ratio |
|---|---|---|---|
| baseline (hash-table) | 1.802 | 0.294 | 6.120× |
| h2 struct + json-get | 0.701 | 0.294 | 2.379× |
| h3 struct + recycle | 0.513 | 0.294 | 1.742× |
| after full revert | 1.802 (booked) | 0.294 | 6.120× |

Pi half reused `/tmp/g26-websocket-invent-remesure/pi.json` (same host, frozen `rpcDialogRequestObject`). Slices unset. `--only-enforce cli_print_rpc.dialog_request`.

## Attempts

h2 replaced the EQUAL hash table with `json-dialog-request` and taught `json-get` / `json-put` / `write-json-value` the struct. Product still serializes as a JSON object. Ratio 6.12× → 2.38×. Keep bar is ≤1.0×, so not a land.

h3 reused one struct in `*rpc-dialog-request-scratch*`. 2.38× → 1.74× (0.513 µs). Matches the Goal 25 local ~0.52 µs screen. The special is process-global, so concurrent RPC would race. Even ignoring that, 1.74× misses 1.0×.

Both invents reverted in `/tmp/cadr-g26-h-dialog`. Worktree src matches 219a3edd0.

Cheap remaining knobs (inline `json-get`, skip `coerce`, reorder `hash-table-p`) cannot close 0.513−0.294 µs. That remainder is six `json-get` dispatches versus V8 hidden-class loads.

Banned levers not used. No leftover collect as met-*. No `:json-object` pairs in `pi-context-json`. No `RATIO_CEILINGS` drop.

## Patches

- `/tmp/g26-h-dialog-KEEP.patch` (no land)
- `/tmp/g26-h-dialog-h3-recycle.reverted.patch` (best attempt, reverted)

## Evidence

- remesure `/tmp/g26-h-dialog-remesure.sh`
- `/tmp/g26-dialog-baseline/`
- `/tmp/g26-dialog-h2-struct/`
- `/tmp/g26-dialog-h3-recycle/`
- `/tmp/g26-dialog-evidence-pack/`
- worktree `docs/benchmarks/goal26-evidence/cli_print_rpc-dialog-invent/`

## Decisions

`/tmp/g26-h-dialog-decisions.tsv`  
`/tmp/g26-h-dialog-show-me.tsv`

## Deviations

Nested hillclimb subagents were not spawned. This worker is already a poteto-agent. Opening a PR skipped (parent lands, no gt/rebase/force-push).

Baseline python pair gate failed help-text 2% (pi=10183 cadr=9882) because reused pi.json predates current cadr help. H2/H3 later saw a foreign `scoped is None` skip in this worktree (websocket remeter collision). That skip was restored. Ratios come from cadr.json/pi.json medians, not from that skip.

Tip `/root/projects/cadr` was not written.

## Follow-ups

Human gate on accepted-runtime-gap, or a remeter that times slot access without calling `json-get` (that would be a new ruler, not this invent).

## gates.md proposal (not approved)

Paste only after a human signs. Do not treat this block as a close.

```
## cli_print_rpc.dialog_request (proposal)

Disposition proposed: accepted-runtime-gap
Class: runtime-essence-candidate
Not approved by this worker.

Fair remesure (Friend-MachineD, slices unset, --only-enforce cli_print_rpc.dialog_request):
- pi rpcDialogRequestObject + field reads: 0.294 µs (n=5, mad 0.002)
- cadr rpc-dialog-request-object + json-get×6: 1.802 µs baseline (6.120×)
- best product invent (struct + recycled scratch): 0.513 µs (1.742×), reverted

User impact: one RPC dialog request object per UI prompt. Absolute gap ~0.22 µs after the best invent, ~1.5 µs on the shipped hash-table path. Not on the token/stream hot path.

Why 1.0× is not available on this product path:
1. Timed work is object construction plus six named field reads. V8 uses a hidden-class object. SBCL's shipped shape is an EQUAL hash table. A dedicated defstruct plus json-get still pays type dispatch and string key matching.
2. Goal 24 sized EQUAL hash + setf missed 1.0× on this host.
3. Goal 25 pairs/struct/recycle screens landed ~0.52 µs locally and were reverted. This run reproduced 0.513 µs on Friend-MachineD against a faster pi (0.294 µs vs booked 0.393 µs).
4. Recycle that hits 1.74× is a process-global scratch and is unsafe for concurrent RPC.

Forbidden as a close: leftover collect counted as met-*, :json-object pairs in pi-context-json, RATIO_CEILINGS drop, silent frozen-unreachable.

Human action: accept this gap in gates.md, or charter a remeter that changes what is timed.
```

## Principles

**Prove it works.** Keep/revert used remesure medians, not the struct looking faster.

**Build the lever.** `/tmp/g26-h-dialog-remesure.sh` is the frozen command.

**Laziness protocol.** 1.74× was not landed. Src reverted.

**Sequence verifiable units.** Baseline, then h2, then h3, revert.

**Model the domain / foundational thinking.** The invent encoded the dialog object as a struct instead of a hash table. It still lost to V8.

**Separate before serializing.** Exclusive `/tmp/cadr-g26-h-dialog`. Tip src not written by this unit.

**Never block on the human.** Recycle was measured without asking. Exhaustion wrote a proposal instead of waiting.

**Fix root causes.** Stopped on SBCL field-access vs V8, not a leftover wrapper.
