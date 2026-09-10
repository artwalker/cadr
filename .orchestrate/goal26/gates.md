

## Gate: cli_print_rpc.dialog_request → accepted-runtime-gap?

- Status: **approved** by operator 2026-09-08 (`请自动化处理`). Invent exhausted. No in-flight unit.
- User impact: dialog object build 0.513µs vs pi 0.294µs. Not visible in RPC. Recycle that reaches 1.74× is unsafe for concurrent RPC.
- Options: (A) approve `accepted-runtime-gap` (B) continue invent with new ruler (C) leave open-parity
- Evidence: baseline 6.120×; best invent 1.742× reverted; pi ~0.294µs
- Worker proposal excerpt:

```
field reads. V8 uses a hidden-class object. SBCL's shipped shape is an EQUAL hash table. A dedicated defstruct plus json-get still pays type dispatch and string key matching.
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

```

## Gate: cli_selectors leftovers → accepted-runtime-gap?

- Metrics: `scoped_model_selector_search_text`, `scoped_models_enabled_set`
- Status: **approved** by operator 2026-09-08 (`请自动化处理`). Invent exhausted. No in-flight unit.
- User impact: search text best 1.753µs vs 1.333µs. Enabled-set is hash-table alloc vs `Set` on 0–3 ids. Neither is visible in the selector UI.
- Options: (A) approve both as accepted-runtime-gap (B) approve one (C) continue invent (D) leave open-parity
- Evidence: docs/benchmarks/goal26-evidence/cli_selectors-invent/

```
## Gate: cli_selectors.scoped_model_selector_search_text and scoped_models_enabled_set → accepted-runtime-gap?

- Status: **approved** by operator 2026-09-08 (`请自动化处理`)
- Default if no answer: leave `open-parity` (do not silent-freeze)
- Options: (A) approve `accepted-runtime-gap` (B) continue invent (C) leave open-parity
- Evidence: fair 5.482× and 1.610×; best search-text invent 1.315× reverted; enabled-set hash-table vs Set never ≤1.0× with a keepable change
- Worker proposal excerpt:

```
scoped_model_selector_search_text times getModelSearchText vs scoped-model-selector-search-text.
Fair 7.306/1.333 µs = 5.482× (format plus nested qualified-model-id).
Best invent cached provider fragments then concatenate. 1.753/1.333 µs = 1.315×. smsst_* exact.
Final remesure of that invent 2.177/1.333 = 1.634× (n=5 noisy). Bar ≤1.0× so reverted.

scoped_models_enabled_set times new Set(enabled) vs make-hash-table :test #'equal.
Fair 2.876/1.787 µs = 1.610×.
:size matching length slowed to 1.915×. Shared empty table 1.670× and is unsafe if callers setf gethash.
No keep. Remainder is SBCL hash-table alloc vs V8 Set on lists of length 0-3.

Forbidden as a close: leftover ctor back in the timed slot, RATIO_CEILINGS drop, silent frozen-unreachable, memoizing the six fixture models.
```
```

## Gate: cli_support.write_overwrite, write_hello, write_empty → accepted-runtime-gap?

- Status: **approved** by operator 2026-09-08 (`请自动化处理`) after `h-cli-support-writes-slot` returned no keep.
- User impact: tiny atomic replace stays slower than `writeFileSync`+`renameSync`. Isolated hello 129µs already matches leftover 140µs. Paired medians stay above 1.0×. Not a visible stall on normal files. No product keep.
- Default if no answer: leave `open-parity` (do not silent-freeze)
- Options: (A) approve `accepted-runtime-gap` (B) continue invent (C) leave open-parity
- Evidence: `docs/benchmarks/goal26-evidence/cli_support-writes-invent/h2/summary.json`
- Worker proposal excerpt:

```
Fair remeter (HEAD stream atomic-write): 3.329× / 5.760× / 10.994× (887/266µs, 808/140µs, 467/42µs).

Best keepable-shape invent (posix unix-open/write/rename, no handler-case, mkdir only on ENOENT): 1.585× / 1.777× / 1.341× (422/266, 249/140, 57/42). cadr-core FiveAM 68/68. Nested missing-parent still creates dirs.

O_TRUNC stable tmp improved empty to 1.202× and worsened hello to 1.949×. Reverted.

Unwind-protect drop is ~19µs in microbench. That can finish empty versus 42µs leftover. It cannot close hello's remaining ~109µs or overwrite's remaining ~156µs.

Remainder is SBCL unix-open/unix-write/rename plus Lisp wrappers versus V8 writeFileSync+renameSync on the same temp+rename product. Isolated microbench hello ~126–158µs already sits at leftover's 140µs. The paired-path median stays higher. No further product knife stays inside atomic replace without dropping atomicity or moving mkdir/encoding into the leftover.

Forbidden as a close: leftover-only win, RATIO_CEILINGS drop, silent frozen-unreachable, timing mkdir out of the product function by deleting parent-create behavior.
```

