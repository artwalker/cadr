# Profiling

`sb-sprof` is a diagnostic, not a criterion. A path that misses a
paired-benchmark bar must attach a profile showing where time went;
the profile itself never pass/fail a gate. Policy:
`docs/development-policy.md` §6 (SBCL ships `sb-sprof`; "X% slower" is
not an actionable conclusion).

Do not add this script to `scripts/test-cl.sh` or `scripts/verify.sh`.

## Driver

```sh
./scripts/goal20-profile.sh
./scripts/goal20-profile.sh --seconds 4 \
  --output docs/benchmarks/goal20-part-o-remaining-sprof.md
```

`scripts/goal20-profile.lisp` is the only owner of the capture
incantation (`sb-sprof:start-profiling` / `report :type :flat`). It
reuses the paired-path fixtures and the same `CADR_CODING_AGENT_DIR`
staging as `scripts/goal20-paired-paths.lisp`.

Current Part O remaining-path capture:
[`benchmarks/goal20-part-o-remaining-sprof.md`](benchmarks/goal20-part-o-remaining-sprof.md).

## What it samples

The driver loops each thunk for `--seconds` (default 4) at a 1 ms
sample interval, after a warmup call and a full GC:

- `cli_dispatch.list_models_render`
- `session_pipeline.session_load`
- `storage_journal.journal_read`
- `storage_journal.journal_append`

To profile a different named path, add a thunk next to those four in
`run-profiles`. Do not start a second driver.

## Ad-hoc REPL capture

Same incantation as the driver, against an already-loaded system (prefer
`asdf:load-system` over rebuilding the image):

```lisp
(require :sb-sprof)
(sb-ext:gc :full t)
(funcall thunk) ; warmup
(sb-sprof:reset)
(sb-sprof:start-profiling :max-samples 50000 :sample-interval 0.001d0)
(loop repeat 50 do (funcall thunk))
(sb-sprof:stop-profiling)
(sb-sprof:report :type :flat :min-percent 1.0)
```

Do not print API keys or OAuth tokens into a profile report.

## Reading a report

Flat `Self %` is the sample share of that function. Foreign
`readlink` / `fstatat` / `open` rows are the filesystem, not Lisp
allocation. Labels inside `parse-json-source` (`PEEK`, `PARSE-STRING`,
`PARSE-VALUE`) are the JSON decoder.
