# Profiling

Diagnostics, not criteria. A path that misses a paired-benchmark bar must
attach a profile showing where time went; the profile itself never
pass/fails a gate. Policy: `docs/development-policy.md` §6 (SBCL ships
`sb-sprof`; "X% slower" is not an actionable conclusion).

Do not add these scripts to `scripts/test-cl.sh` or `scripts/verify.sh`.

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

Current Part P load/read capture (HEAD `67a2d43fb`):
[`benchmarks/goal20-part-p-load-read-sprof.md`](benchmarks/goal20-part-p-load-read-sprof.md).

## What it samples

The driver loops each thunk for `--seconds` (default 4) at a 1 ms
sample interval, after a warmup call and a full GC:

- `cli_dispatch.list_models_render`
- `session_pipeline.session_load`
- `storage_journal.journal_read`
- `storage_journal.journal_append`
- `session_pipeline.context_walk`
- `cli_dispatch.argv_parse`
- `cli_dispatch.help_render`

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

## `trace`: which branch fired, without guessing or adding logging

Standing policy: `docs/development-policy.md` §6 item 1 (when the
runtime trigger cannot be read out of the source, capture evidence;
guessing is not diagnosis).

Use `trace` when the question is **"was this function called, with what
arguments, and what did it return"** — e.g. "why did login take branch 1
and not branch 2". It needs no source edit and no rebuild: wrap the
function in a live image (slynk REPL or a repro script), reproduce once,
read the calls.

```lisp
(trace cadr-cli::some-login-fn)   ; internal symbol: double colon
;; reproduce the failure
(untrace cadr-cli::some-login-fn) ; or (untrace) for all
```

Each call prints entry with arguments and exit with return values,
indented by depth, to `*trace-output*`. Narrow the noise instead of
tracing more functions:

- `:condition` / `:condition-after` evaluate a predicate per call; the
  call arguments are referenced as `(sb-debug:arg 0)`, `(sb-debug:arg
  1)`, ...  (e.g. `(trace cadr-cli::f :condition (eq (sb-debug:arg 0)
  :x))`).
- `:break t` drops into the debugger at entry, combining trace with
  stack inspection.

Rules of thumb:

- Do not trace render-loop-hot functions unfiltered; one frame is
  thousands of calls. Narrow with `:condition` or pick a calmer caller.
- Tracing a generic function alone shows the generic's calls; add
  `:methods t` to also trace each method by name.
- With the default `:encapsulate t`, redefining or reloading the
  function keeps the trace wrapper (verified on SBCL 2.6.7); with
  `:encapsulate nil` a reload silently drops it.
- Credential discipline applies to trace output exactly as to profiles:
  never print API keys or OAuth tokens. Do not trace functions whose
  arguments carry secrets (`cadr-ai` auth headers) without redacting.

`trace` vs slynk live capture: `trace` answers **path over time** (which
calls happened, in which order, with which values) without stopping the
process; slynk answers **state at one moment** (live objects, stack,
slots at the failure). When you do not yet know which branch fires,
trace first, then set the slynk breakpoint where the trace says the
branch is. Neither requires editing source; both attach to the same
running image (`./cadr --slynk <port>`).

## Branch coverage (`sb-cover`)

Driver: `scripts/goal20-cover.sh [output-directory]` (default
`/tmp/goal20-cover/`). Compiles all nine production systems with
`(optimize sb-cover:store-coverage-data)` in an isolated `HOME` with a
fresh ASDF cache, runs the full FiveAM suite in `test-cl.sh` order, and
writes `data.tsv` (per-file branch/expression counts, zero- and
partial-coverage branch lines), `coverage.dat` (restorable state), and
`coverage.lcov`. Latest booked numbers:
[`acceptance/goal-v20-sb-cover.md`](acceptance/goal-v20-sb-cover.md).
Coverage has no gate threshold; the obligation is a conclusion per
zero-coverage branch, not a percentage.
