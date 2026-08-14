# Goal 20 Part H — paired non-TUI benchmarks

Goal 11 pairs cadr against pi on three ratios, all of them TUI input:
mouse drag-to-frame, wheel-to-frame, and the continuous alt-input stress run
(`scripts/goal11-performance-gate.py`, `baseline_mouse_ratio`,
`baseline_wheel_ratio`, `baseline_continuous_p99_ratio`). Every path outside
the renderer had no pi comparison at all, so "cadr is no worse than pi" was
unfalsifiable for the CLI, the provider layer, agent sessions, and storage.

Part H adds four same-input, same-machine, no-network pairs over those layers.

| script | side |
|---|---|
| `scripts/goal20-gen-paired-fixtures.mjs` | deterministic fixture generator (`--check` mode fails on drift) |
| `scripts/goal20-paired-paths.lisp` | cadr half |
| `scripts/goal20-paired-paths.mjs` | pi half, run against `/tmp/cadr-render-diff-pi-53fa77ccd` |
| `scripts/goal20-paired-paths.py` | pairing gate |
| `scripts/goal20-paired-paths.sh` | runs all four in order |

The 180s sustained trace in `scripts/goal11-bench.lisp` is untouched, and no
existing ceiling was changed. The one edit to `scripts/goal11-performance-gate.py`
extracts its inline hostname comparison into `same_machine(candidate, baseline)`
so this gate can import it; the comparison itself is unchanged.

## 1. The four pairs

Every pair reads the same fixture bytes on both sides, from
`test/fixtures/goal20-paired-paths/`. The pi half runs through the baseline's
own `tsx`, so pi's TypeScript sources execute unbuilt.

### Pair 1 — `cli_dispatch`

Real dispatch work with the process already up. Process cold start is *not*
part of this pair: an SBCL image start against a Node bundle start measures the
two runtimes, not cadr's code.

| metric | cadr | pi |
|---|---|---|
| `argv_parse` | `parse-cli-arguments` (`src/cadr-cli/arguments.lisp`) | `parseArgs` (`packages/coding-agent/src/cli/args.ts`) |
| `help_render` | `print-cli-usage` (`src/cadr-cli/arguments.lisp`) | `printHelp` (same file) |
| `list_models_registry` | `make-model-registry` (`src/cadr-cli/models/registry.lisp`) | `ModelRuntime.create` (`packages/coding-agent/src/core/model-runtime.ts`) |
| `list_models_render` | `print-cli-models` (`src/cadr-cli/bootstrap/main.lisp`) | `listModels` (`packages/coding-agent/src/cli/list-models.ts`) |

Input: `cli-argv.json` (a 25-token argv covering provider, model, thinking,
repeated `--append-system-prompt`, `--tools`, `--exclude-tools`, `--session-dir`,
`--mode json`, `--list-models goal20`, a message, and an `@file` argument),
plus a staged agent directory holding the fixture `models.json` (one custom
provider, 24 models) and `auth.json`. Both sides render into counting sinks.

### Pair 2 — `provider_stream`

Request assembly and streaming response parse, no socket.

| side | entry point | transport seam |
|---|---|---|
| cadr | `stream-chat` for `:openai-completions` (`src/cadr-ai/provider.lisp`) | `cadr-ai:*http-request-function*`, the seam the provider tests already use |
| pi | `stream` (`packages/ai/src/api/openai-completions.ts`) | `ProviderRequestOptions.fetch` |

Input: `provider-context.json` (96 messages: text, thinking, tool calls, tool
results, CJK and astral emoji) and `openai-completions.sse` (394 chunks: an opening
role chunk, 384 text deltas, a tool call streamed across six chunks,
`finish_reason: "tool_calls"`, a usage-only chunk, then `[DONE]`). Both sides re-read the SSE
fixture from disk per call, so neither gets a pre-parsed buffer. Only the
socket is replaced: request assembly, status handling, SSE decoding, event
reduction, and final-message assembly stay on the production path.

### Pair 3 — `session_pipeline`

| metric | cadr | pi |
|---|---|---|
| `session_load` | `load-session` (`src/cadr-agent/session/migration.lisp`) | `SessionManager.open` (`packages/coding-agent/src/core/session-manager.ts`) |
| `context_walk` | `session-messages` (`src/cadr-agent/session/journal.lisp`) | `buildSessionContext` (same file) |

Input: `session.jsonl`, 209 KiB / 515 entries (514 plus header), including a
compaction entry with a retained tail, custom entries, thinking-level and
model-change entries, and a label. Both loaders parse the whole file; pi's
`open` reads the header and then loads every entry through
`loadEntriesFromFile`, which is the same work `load-session` does.

### Pair 4 — `storage_journal`

| metric | cadr | pi |
|---|---|---|
| `journal_read` | `read-session-objects` (`src/cadr-agent/session/migration.lisp`) | `loadEntriesFromFile` (`packages/coding-agent/src/core/session-manager.ts`) |
| `journal_append` | `create-session` + 128 × `session-append-message` (`src/cadr-agent/session/journal.lisp`) | `SessionManager.create` + 128 × `appendMessage` |

The append input is the first 128 message entries of the same `session.jsonl`,
replayed into a fresh journal, so both sides write the same logical entries in
the same order. Both open and close the file per entry. The journal cwd comes
from the fixture manifest (`/tmp/goal20-part-h-journal-cwd`) rather than a
scratch path, because a per-run path length would change the header bytes each
side writes.

## 2. How to run

```bash
# fixtures, both halves, and the gate
./scripts/goal20-paired-paths.sh

# faster smoke run: 1 sample, no warmup, repetitions / 20
./scripts/goal20-paired-paths.sh --quick

# other baselines / output locations
./scripts/goal20-paired-paths.sh --baseline /tmp/cadr-render-diff-pi-53fa77ccd \
  --out /tmp/goal20-paired-paths --samples 5 --warmups 1
```

The wrapper needs `SBCL`, `QUICKLISP_SETUP`, `node`, and a populated pi
baseline at `/tmp/cadr-render-diff-pi-53fa77ccd` (produced by
`scripts/render-diff.py`); it exits 2 with a message when one is missing. It
runs `scripts/goal20-gen-paired-fixtures.mjs --check` first, so a fixture that
no longer matches its generator fails before anything is measured.

The three steps can also be run by hand:

```bash
CADR_BENCH_PROJECT_DIRECTORY="$PWD" QUICKLISP_SETUP=~/quicklisp/setup.lisp NO_COLOR=1 \
  sbcl --noinform --disable-debugger --script scripts/goal20-paired-paths.lisp \
  --keep-journal /tmp/cadr-journal.jsonl --output /tmp/cadr.json

NO_COLOR=1 /tmp/cadr-render-diff-pi-53fa77ccd/node_modules/.bin/tsx \
  scripts/goal20-paired-paths.mjs /tmp/cadr-render-diff-pi-53fa77ccd \
  --keep-journal /tmp/pi-journal.jsonl --output /tmp/pi.json

python3 scripts/goal20-paired-paths.py --cadr /tmp/cadr.json --pi /tmp/pi.json \
  --cadr-journal /tmp/cadr-journal.jsonl --pi-journal /tmp/pi-journal.jsonl
```

Neither half is wired into `scripts/verify.sh`: the pi baseline tree is a local
cache, not a build input, so the gate stays an explicit measurement step like
`scripts/render-diff.py`.

## 3. What makes each one a pair

`scripts/goal20-paired-paths.py` refuses to compare two reports unless all of
this holds:

- **Same fixture bytes.** Both reports carry a SHA-256 per fixture file; the
  gate recomputes the digests from `test/fixtures/goal20-paired-paths/` and
  requires both reports to match the files on disk, so neither side can vouch
  for itself. Staged `models.json` / `auth.json` digests must also agree.
- **Same machine.** `same_machine(cadr, pi)` is imported from
  `scripts/goal11-performance-gate.py`; cadr reports
  `machine.machine_instance` from `(machine-instance)` and pi reports
  `machine.hostname` from `os.hostname()`, exactly as the goal11 gate expects.
  There is no second host-match mechanism. On a host mismatch the ratios are
  reported as `informational-host-mismatch` and not enforced, matching the
  goal11 policy for absolute microseconds.
- **Same batch shape.** The repetition table, sample count, warmup count,
  quick flag, and append entry count must be equal, and every metric must
  carry the declared number of samples: a ratio between differently sized
  batches is not a comparison. `--quick` runs report
  `informational-quick-run` and are not enforced.
- **Same environment.** Both halves unset every `*_API_KEY`, `*_AUTH_TOKEN`,
  `*_OAUTH_TOKEN`, and `*_ACCESS_TOKEN` variable before building a registry
  and record what they removed. Without this, an operator's ambient
  `DEEPSEEK_API_KEY` adds models to the available set and the measured model
  count depends on whose shell ran the benchmark.
- **Same work done.** Observed values must match exactly: all parsed argv
  fields, available model count and providers, list-models character and line
  counts, the provider payload key set and message/tool counts, streamed text
  length, content block types, stop reason, usage, session id / leaf id /
  name, entry counts, context entry and message counts, context thinking
  level and model, and journal entry counts. A benchmark that measures less
  work cannot win by measuring less work.

Both halves time themselves with a monotonic nanosecond clock
(`sb-unix:clock-gettime CLOCK_MONOTONIC` and `process.hrtime.bigint()`).
`get-internal-real-time`, which `scripts/goal11-bench.lisp` uses, is quantised
to a scheduler tick on this host (~3.99 ms under WSL2), which would report
`0 µs` for an argv parse and make every small ratio noise.

## 4. Measured result

`Friend-MachineD`, SBCL 2.6.7 / node v22.22.0, `--samples 5 --warmups 1`. The
median columns are one representative run; the range column is the observed
spread over repeated runs on this host.

| metric | pi median | cadr median | ratio | 3-run range | ceiling |
|---|---|---|---|---|---|
| `cli_dispatch.argv_parse` | 3.95 µs | 6.64 µs | 1.68x | 1.68–2.06x | 3.0x |
| `cli_dispatch.help_render` | 0.74 µs | 6.33 µs | 8.51x | 3.94–8.51x | 6.0x |
| `cli_dispatch.list_models_registry` | 4100 µs | 2859 µs | 0.70x | 0.53–0.70x | 1.5x |
| `cli_dispatch.list_models_render` | 1457 µs | 4083 µs | 2.80x | 2.67–2.94x | 4.0x |
| `provider_stream.stream_roundtrip` | 6525 µs | 8498 µs | 1.30x | 1.30–1.68x | 2.5x |
| `session_pipeline.session_load` | 1900 µs | 10366 µs | 5.46x | 5.46–7.16x | 9.0x |
| `session_pipeline.context_walk` | 123 µs | 121 µs | 0.98x | 0.88–1.13x | 2.0x |
| `storage_journal.journal_read` | 1601 µs | 8286 µs | 5.18x | 4.75–6.07x | 8.0x |
| `storage_journal.journal_append` | 1931 µs | 16446 µs | 8.52x | 7.36–8.52x | 12.0x |

Seven of the nine metrics start **above** parity. The largest gaps are JSONL
session I/O: cadr reads a 515-entry journal about 5x slower than pi and writes
128 entries about 8.5x slower, which is the cost of cadr's JSON codec against
V8's native `JSON.parse` / `JSON.stringify`. This is the first time those paths
have been measured against pi at all.

The ceilings in `RATIO_CEILINGS` therefore **record** today's measured state so
further drift fails; they are not a claim of parity. They should be ratcheted
down as cadr improves and never raised without user adjudication.

The allowed cadr median is
`max(ceiling × pi_median, pi_median + max(10 µs, 6 × run_MAD))`, the same shape
as the goal11 gate's `baseline_limit_us` with its 5000 µs absolute floor scaled
down to 10 µs. The floor matters for `argv_parse`, `help_render`, and
`context_walk`: pi's help render lands under a microsecond, and its run-to-run
swing alone moves that ratio between 3.9x and 8.5x. The gate prints which term
bound each metric (`[ratio]` or `[variance]`), so a ratio printed above its
ceiling on a sub-10 µs operation is not mistaken for a violation that slipped
through.

Sample gate output:

```text
goal20 pair gate: PASS
  run: same_machine=yes, ratio_gate=enforced, cadr_host=Friend-MachineD, pi_host=Friend-MachineD, samples=5
  ratios: cli_dispatch.argv_parse=1.68x/3.00x[variance], cli_dispatch.help_render=8.51x/6.00x[variance],
          cli_dispatch.list_models_registry=0.70x/1.50x[ratio], cli_dispatch.list_models_render=2.80x/4.00x[ratio],
          provider_stream.stream_roundtrip=1.30x/2.50x[ratio], session_pipeline.session_load=5.46x/9.00x[ratio],
          session_pipeline.context_walk=0.98x/2.00x[variance], storage_journal.journal_read=5.18x/8.00x[ratio],
          storage_journal.journal_append=8.52x/12.00x[ratio]
  notes: known_divergence:event_kind:toolcall_delta=pi6/cadr5, help_characters=pi9784/cadr9802,
         journal_body_bytes=pi54771/cadr56723 (+3.6%), journal_key_divergences=10
```

## 5. Defects the pairing found

Two blocked the pairs and are fixed here:

1. **`models.json` custom models with image input failed to load.**
   `json-model` stored the result of `(find "image" input)` — the string
   `"image"` — into the `boolean`-typed `supports-images-p` slot, so a provider
   block containing any `"input": ["text", "image"]` model aborted the whole
   `models.json` load with `Warning: errors loading models.json`. Fixed in
   `src/cadr-cli/models/store.lisp` by coercing to `T`.
2. **`--list-models` hid custom-provider models.** `print-cli-models` was the
   only `make-model-registry` caller that passed no credential store, and a
   provider outside the built-in catalog is only "available" when the registry
   can read `auth.json`. `cadr --list-models` therefore showed nothing for a
   `models.json` provider authenticated the documented way, while
   `pi --list-models` showed all 24. Fixed in
   `src/cadr-cli/bootstrap/main.lisp`.

Both are covered by
`model-registry-loads-image-input-and-lists-custom-provider` in
`test/cadr-cli/part-b-models-test.lisp`: an image-capable custom-provider
`models.json` plus an `auth.json` credential, asserting no load error, a
boolean `supports-images-p`, and the model present in
`model-registry-available-models`. Reverting either fix turns the test red
(3 of 4 checks fail on the coercion alone).

Divergences the gate now records rather than fixing. Each is checked against
its recorded value, so the gate fails if either side moves — nothing is
silently skipped:

| divergence | pi | cadr | note |
|---|---|---|---|
| `toolcall_delta` events | 6 | 5 | pi emits a delta for the opening tool-call chunk although its argument fragment is empty; cadr suppresses the empty delta. Visible on the `--mode json` event wire. |
| session `stopReason` | `"toolUse"` | `"tooluse"` | `symbol-json-name` downcases the keyword; `src/cadr-cli/modes/print.lisp` already has `wire-stop-reason-name` for the wire spelling, but `src/cadr-agent/session/codec.lisp` does not use it. |
| session `usage` total | `totalTokens` | `total` | different key name for the same number. |
| thinking blocks | no `redacted` key | `"redacted": false` | cadr always writes the flag. |
| tool-result `details` | key omitted | `"details": false` | cadr writes `false` where the schema expects an object or nothing. |
| `usage.cost.*` | `0` | `0.0` | double float printing. |
| session header `cwd` | `/tmp/…` | `/tmp/…/` | `canonical-session-cwd` returns a directory namestring. |
| journal body bytes | 54,771 | 56,723 | +3.6%, the sum of the rows above. |
| `help_characters` | 9,784 | 9,802 | product-identity renames (`pi`→`cadr`, `PI_*`→`CADR_*`), plus cadr omits pi's `BASETEN_API_KEY` line and one blank line. Bounded at ±2% instead of compared exactly. |
| context message roles | `compactionSummary`, `custom` roles | folded into `user` | `session-messages` materialises both as user messages. The gate folds pi's spellings and then requires equality. |

With `--cadr-journal` / `--pi-journal` the gate also diffs the two written
journals leaf by leaf, after dropping the per-run entry ids and timestamps, and
requires the set of differing JSON paths to equal the recorded set exactly. A
new codec divergence fails; a fixed one also fails, with a message to update
the record.

Four earlier differences turned out to be measurement artefacts in the harness
and were fixed there, not recorded as divergences: JS UTF-16 string length
against Lisp code points (an astral emoji counted twice), `buildParams` leaving
inapplicable keys as `undefined` (present as JS properties, absent on the
wire), `console.log`'s implicit newline missing from pi's character counts, and
the coarse `get-internal-real-time` clock.

## 6. Paths that cannot be paired

These have no pi counterpart, so no same-input pair exists. They are listed so
the absence is a recorded decision rather than an oversight.

| cadr-only path | evidence | why unpairable |
|---|---|---|
| `--slynk <port>` loopback REPL service | `src/cadr-cli/remote-repl.lisp`, `src/cadr-cli/arguments.lisp` | approved Lisp-native addition; pi has no in-process REPL to feed the same input to (README "Differences from TypeScript pi"). |
| Lisp extension host: load, compile, and dispatch | `src/cadr-agent/extensions/lifecycle.lisp`, `registration.lisp`, `examples/extensions/*.lisp` | pi extensions are JavaScript modules and npm packages, so the input artifact itself differs and "same fixture bytes" is impossible. Where extension activity reaches the JSONL or RPC wire, `scripts/event-diff.py` already compares the observable events; the load and dispatch cost has no comparable pi input. |
| Tool-failure restarts and the `:tool-call-error` extension event | `src/cadr-agent/loop/tool-execution.lisp` | approved Lisp-native addition with no baseline path. |
| Redacted fatal-condition summary and `0600` crash log | `src/cadr-ai/crash.lisp` | approved Goal 13 divergence: pi prints a terminal stack dump instead. The two do different work by design. |
| SBCL native image build and process cold start | `build.sh`, `scripts/goal11-cold-start.py` | an SBCL image start against a Node bundle start measures the two runtimes. Explicitly rejected as a pair; cold start keeps its own absolute 750 ms ceiling in `scripts/goal11-performance-gate.py`. |
| OAuth success/failure page mark | `src/cadr-ai/oauth/page.lisp` | branding-only difference (cons-cell grid instead of pi's logo). |
| Live-credential provider calls | `test/` live suites | a network call is not a fixture. Pair 2 covers the deterministic assembly and parse; the live path stays credential-gated. |
| Deterministic vs live test entry points, ASDF/Quicklisp build steps | `scripts/test-cl.sh`, `build.sh` | build- and test-ecosystem differences, already an approved category. |

`SQLite session storage` is deliberately **not** on this list: pi ships
`packages/session-backends/sqlite-node`, so `src/cadr-agent/sqlite-storage.lisp`
is pairable in principle and is simply not covered yet.

## 7. Policy for unpaired paths

An unpaired path must still be measured. The rule for anything in section 6,
and for anything not yet paired:

- Compare cadr against **cadr's own previous run on the same machine**, never
  nothing. The mechanism is `self_history_summary` in
  `scripts/goal11-performance-gate.py`, reading
  `docs/benchmarks/performance-history.json` via `--history`.
- A silent skip is not acceptable. When the reference row is missing, the
  gate still prints its state (`self_history_gate=informational-no-file`,
  `informational-no-same-machine-row`, `informational-unreadable`) so the
  absence is visible in the output.
- Self-history drift remains **informational** until the Goal 20 Part A
  percentages are adjudicated by the user; Part H does not enable those
  thresholds.
- A cadr-vs-previous-self comparison is never presented as a pi comparison.
  Only the nine metrics in section 4 and the three goal11 TUI ratios carry a
  pi reference.
