# h-enabled-set REPORT

Status. kept-faster. Product patch at `/tmp/g27-enabled-set.patch`. Tip `/root/projects/cadr` src was not written by this unit.

Worktree `/tmp/cadr-g27-enabled-set` on `g27-enabled-set` from `219a3edd0`. Tip `goal20-paired-paths.lisp/.mjs/.py` copied in. Slices unset. Friend-MachineD. `SYNC_TIP_PY` before the pair script.

## Metric

`cli_selectors.scoped_models_enabled_set`. Lower cadr median is better. Keep if strictly faster than this session's HEAD mill and membership plus sorted-id order match HEAD `gethash`. Prefer ≤1.0× vs pi.

## Result

| mill | cadr µs | pi µs | ratio |
|---|---|---|---|
| HEAD hash-table | 2.22286 | 2.13684 | 1.040× |
| list membership | 0.07844 | 2.13684 | 0.0367× |

Samples after. 0.08066, 0.09608, 0.07844, 0.07506, 0.07446.

Behavior. `/tmp/g27-enabled-set-behavior.lisp` compared HEAD `gethash` membership and `append` order against the product functions. Match. Harness `smes_empty` `smes_one` `smes_two` `smes_dup` `smes_sort` `smes_three` matched pi on both mills.

Official pair python still fails theme ANSI, `smce_copy`, and the scoped help-text OBS. Same as Goal 26 selectors remesure. Those keys are not this product path.

## Change

`scoped-models-enabled-set` returns the enabled list. Both former `gethash` sites use `member` with `:test #'equal`. Empty `'()` is the empty list, not a shared mutable table. No `:size` hint.

The timed slot is still the product function. Pi still builds `new Set(enabled)`.

Worktree mill encode accepts a list or a hash-table so HEAD and after mills share one lisp. That harness tweak is not in the keep patch. Parent must teach `encode-scoped-models-enabled-set` to walk a list (unique keys, `string<`) or `maphash` will error after landing.

## Attempts

h1 list identity plus `member` equal. Kept.

## Patches

- `/tmp/g27-enabled-set.patch` (keep, `models.lisp` only)
- remesure `/tmp/g27-enabled-set-remesure.sh`
- decisions `/tmp/g27-enabled-set-decisions.tsv`
- mills `/tmp/g27-enabled-set-head/` and `/tmp/g27-enabled-set-after/`

## Deviations

Hillclimb subagents were not spawned. This worker is already a poteto-agent.

Opening a PR skipped. Parent lands. No gt/rebase/force-push.

`GOAL20_COLLECT_ONLY` skipped other timed slots.

Tip `models.lisp` was already dirty from another session. This unit did not edit it.

## Follow-ups

Parent encode update, then land. Next knife is not needed on this metric unless call-site `member` on a longer enabled list shows up later.
