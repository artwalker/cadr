# h-cli-selectors-leftover REPORT

Status. open-parity on both leftover metrics. No product keep. No silent freeze. Not accepted-runtime-gap.

Worktree `/tmp/cadr-g26-h-selectors` off `219a3edd0` plus the fair remeter already in `/tmp/g26-r-selectors-fair.patch`. Tip src was not written.

## Ratios (Friend-MachineD, n=5, slices unset, pi reused)

| metric | fair cadr/pi | invent final | best invent | disposition |
|---|---|---|---|---|
| `cli_selectors.scoped_model_selector_search_text` | 7.306 / 1.333 = 5.482× | 2.177 / 1.333 = 1.634× | 1.753 / 1.333 = 1.315× (h5) | open-parity |
| `cli_selectors.scoped_models_enabled_set` | 2.876 / 1.787 = 1.610× | 2.512 / 1.787 = 1.406× | 1.406× (noise, no product keep) | open-parity |

`smsst_*` and `smes_*` matched on every invent remesure. Official pair python still fails theme ANSI, `smce_copy`, and help-text 10183 vs 9882. Those are not these two product paths.

## Attempts

h1 one `make-string` plus `replace`, provider-key cache. 5.482× to 2.317×. Still over 1.0×.

h2 `concatenate` plus the same cache. 1.744×. Kept as the better haystack builder.

h3 cached `" " key " "` and `key "/"` fragments, six-piece `concatenate`. 1.351×.

h4 copy fragments with `replace`. 1.491×. Reverted.

h5 vector fragments (same concatenate) plus `:size` on the hash-table. Search 1.315×. Sized table 1.915×. Size hint reverted. Search-text stay was later fully reverted with the rest.

h6 shared empty hash-table for `'()`. 1.670×, no beat, mutation risk. Reverted.

Final remesure after reverting set experiments. Search-text still the fragment concatenate. 1.634× (noisy samples 1.66 to 3.17 µs). Enabled-set original `make-hash-table :test #'equal`. 1.406× vs fair 1.610× is run noise, not a keep.

Bar is ≤1.0×. Product `models.lisp` restored to HEAD. Near-miss search-text lives only in `/tmp/g26-h-selectors-search-text-nearmiss.patch`.

## Patches

- `/tmp/g26-h-selectors-search-text-nearmiss.patch` (not a keep)
- `/tmp/g26-h-selectors-KEEP.patch` (empty keep)
- `/tmp/g26-h-selectors-gates.md` proposal for parent/human
- remesure `/tmp/g26-h-selectors-remesure.sh`
- decisions `/tmp/g26-h-selectors-decisions.tsv`

## Evidence

`/tmp/g26-selectors-invent/` and worktree `docs/benchmarks/goal26-evidence/cli_selectors-invent/`. Fair ruler stays in `cli_selectors-fair/`.

## Deviations

Fair remeter is uncommitted on tip. This unit applied `/tmp/g26-r-selectors-fair.patch` in the exclusive worktree only.

Hillclimb subagents were not spawned. This worker is already a poteto-agent.

Opening a PR skipped. Parent lands. No gt/rebase/force-push.

`GOAL20_COLLECT_ONLY` skipped other timed slots. Slices stayed unset.

## Follow-ups

Human gate on accepted-runtime-gap for both leftovers, or a new ruler. Remaining cost is SBCL `concatenate` vs V8 template, and `make-hash-table` vs `Set`, on six tiny cases.

Next invent if pushed. Typed `simple-string` fill after a longer n, not n=5 at ~2 µs. Do not memoize the six fixture objects. That would game the thunk.
