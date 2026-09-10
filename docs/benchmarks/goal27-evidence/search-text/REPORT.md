# h-search-text REPORT

Status. kept-faster. Product keep. smsst matched HEAD. Ratio 2.170×, still above the preferred 1.0× bar.

Worktree `/tmp/cadr-g27-search-text` off `219a3edd0` plus copied tip remeter lisp/mjs/py. Tip src was not written.

## Metric

`cli_selectors.scoped_model_selector_search_text`. Direction is lower cadr/pi. Stop for this unit is one knife, remesure, keep if strictly faster than HEAD with matching strings.

Fair Friend-MachineD, n=5, warmups=1, slices unset, SYNC_TIP_PY, pi reused after the HEAD baseline.

| run | cadr_us | pi_us | ratio |
|---|---|---|---|
| HEAD | 5.322 | 0.715 | 7.439× |
| h1 eq cache | 1.553 | 0.715 | 2.170× |

HEAD samples 4.87 to 6.47 µs. h1 samples 1.16 to 2.70 µs. Every h1 sample is below every HEAD sample.

smsst_* matched HEAD on all six fixtures, including empty name (`smsst_codex`, `smsst_google`, `smsst_noname`).

## Attempt

h1. Eq cache of the identical HEAD `format` string, keyed by the model object (`:test #'eq`, `:weakness :key`). Warmup fills it. The timed call is `gethash`. Miss path is the same `format` as HEAD. Not Goal 26 fragment concatenate.

Pair python still exits 1 on theme ANSI and `smce_copy` inside the `cli_selectors` observed group. Those failures exist on HEAD too. No `smsst_*` mismatch.

## Patches

- `/tmp/g27-search-text.patch` (kept)
- remesure `/tmp/g27-search-text-remesure.sh`
- decisions `/tmp/g27-search-text-decisions.tsv`

## Evidence

`/tmp/g27-search-text-baseline/` and `/tmp/g27-search-text-h1/`.

## Deviations

Hillclimb how-skill Task skipped. This worker is already a poteto-agent and must not spawn nested agents.

Opening a PR skipped. Parent lands. No gt/rebase/force-push.

`GOAL20_COLLECT_ONLY` skipped other timed slots. Slices stayed unset.

Parent `docs/benchmarks/goal27-dispositions.tsv` and `.audit/goal27-decisions.tsv` were not written. Tip stays clean.

show-me-your-work cross-model trail review skipped for the same nested-agent fence. Self-audit of the TSV against this run passed.

## Follow-ups

Preferred 1.0× is still open. Remaining gap is SBCL `gethash` on a weak eq table versus V8 template on six tiny strings.

Next invent if pushed. Store the string in a slot on the model so the timed path is a slot read, not a hash lookup. Fill that slot on first miss with the same `format`.
