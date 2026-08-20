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

### Pair 5 — `sqlite_session`

| metric | cadr | pi |
|---|---|---|
| `open_walk` | `session-repository-open` + `harness-session-entries` + `harness-session-branch` (`src/cadr-agent/sqlite-storage.lisp`) | `SqliteSessionRepository.open` + `findEntries` + `findEntriesOnBranch` (`packages/session-backends/sqlite-node`) |

Both sides ingest the same `session.jsonl` (header skipped; 514 records)
into a temp SQLite file **outside** the timed loop. The timed thunk is
reopen + read every stored entry + walk the current leaf. No network.
v4 sqlite-node has no first-class `custom_message` / `label` /
`session_info` rows, so the pi half stores those three kinds as
`custom` entries with `customType` set to the v3 type name. Observed
`entry_count` / `leaf_id` / `session_id` stay comparable. Leaf-walk
length is **not** an exact field: cadr preserves v3 parent links (322
on the pairing fixture), pi's `appendEntry` parents along the main
lane (514).

### Pair 6 — `tool_read`

| metric | cadr | pi |
|---|---|---|
| `text_file` | `read-tool-file` (`src/cadr-cli/tools/read.lisp`) | `createReadToolDefinition.execute` (`packages/coding-agent/src/core/tools/read.ts`) |

Both sides write the same 4000-line truncation fixture to a temp
text file **outside** the timed loop. The timed thunk is production
read (split lines + `truncateHead` + continuation notice). No
network. Observed `line_count` / `output_chars` / `truncated` are
exact. First Friend-MachineD freeze 5.32×, ceiling 8.0. Product
`split-all-lines` / `text-lines` stay cons lists in the pair
commit.

### Pair 7 — `tool_grep`

| metric | cadr | pi |
|---|---|---|
| `context_file` | `grep-lines` (`src/cadr-cli/tools/grep.lisp`) | `createGrepToolDefinition.execute` (`packages/coding-agent/src/core/tools/grep.ts`) |

Both sides write the same 4000-line fixture and search it with
literal `"mixed tail"`, `context=2`, `limit=100`. Timed work is
production grep (`rg --json` + context via `text-lines` /
`split("\n")`). No network. Observed `match_limit` /
`output_chars` / `truncated` are exact. First Friend-MachineD freeze 1.77×, ceiling 3.0.
Product `text-lines` stays a cons list in this commit.

### Pair 8 — `agent_tool_loop`

| metric | cadr | pi |
|---|---|---|
| `roundtrip` | `agent-prompt` (`src/cadr-agent/loop/agent-loop.lisp`) | `Agent.prompt` + `runAgentLoop` (`packages/agent/src/agent.ts`, `agent-loop.ts`) |

Faux stream, no socket. Same FiveAM shape: one user prompt, one
echo tool call (`value=hello`), one tool result, one final
assistant `"done"`. Lisp-only retry/skip/abort stays
`tool_failure_restarts` (unpairable). Observed `message_count` /
`tool_value` / `tool_error` / `final_text` are exact. First
Friend-MachineD freeze 0.77× (329 / 428 µs), ceiling 1.5.

### Pair 9 — `session_compact`

| metric | cadr | pi |
|---|---|---|
| `compact` | `compact-agent` (`src/cadr-agent/compaction.lisp`) | `prepareCompaction` + `compact` (`packages/coding-agent/src/core/compaction/compaction.ts`) |

Deterministic five-message list over the compact token budget
(context-window 100, keep-recent 40, reserve 21). Faux
summarizer returns `"SUMMARY"`. Timed work is production
`compact-agent` / `compact()` to the compaction result, not
`session_load` of an already-compacted JSONL. Observed
`compacted` / `first_kept` / `summary_chars` are exact.
`branch-summarization.lisp` is not on this thunk. First
Friend-MachineD freeze 11.33× (965 / 85 µs), ceiling 20.0.
Timed Lisp core is in-memory `compact-from-preparation` (pi
`prepareCompaction` + `compact`); persist stays after the core.
Friend-MachineD remesure after that encoding: 11.33×→4.54×
(965→164 µs). UUIDv7 entropy pool then 4.54×→0.56× (164→43 µs).
Ceiling 20.0 unchanged.

### Pair 10 — `provider_anthropic`

| metric | cadr | pi |
|---|---|---|
| `stream_roundtrip` | `stream-chat` + `anthropic.lisp` | `stream` (`packages/ai/src/api/anthropic-messages.ts`) |

Same fixture bytes as the openai-completions pair's context, plus
recorded Anthropic SSE (`anthropic-messages.sse`). Seam =
`*http-request-function*` / `ProviderRequestOptions.fetch`. No live
socket. Observed `stop_reason` / `tool_call_count` / `usage_*` /
`text_characters` are exact. First Friend-MachineD freeze 0.97×
(2508 / 2585 µs), ceiling 1.5.

### Pair 11 — `provider_google`

| metric | cadr | pi |
|---|---|---|
| `stream_roundtrip` | `stream-chat` + `google.lisp` | `stream` (`packages/ai/src/api/google-generative-ai.ts`) |

Same fixture bytes as the openai-completions pair's context, plus
recorded Gemini SSE (`google-generative-ai.sse`). Seam =
`*http-request-function*` / stubbed `globalThis.fetch` (the adapter
rejects `options.fetch`). No live socket. Observed `stop_reason` /
`tool_call_count` / `usage_*` / `text_characters` /
`payload_tool_count` are exact. First Friend-MachineD freeze 0.58×
(4378 / 7498 µs), ceiling 1.5.

### Pair 12 — `provider_bedrock`

| metric | cadr | pi |
|---|---|---|
| `stream_roundtrip` | `stream-chat` + `bedrock.lisp` + AWS event-stream | `stream` (`packages/ai/src/api/bedrock-converse-stream.ts`) |

Same fixture bytes as the openai-completions pair's context, plus
recorded Bedrock event-stream (`bedrock-converse-stream.bin`). Seam =
`*http-request-function*` / stubbed Smithy `NodeHttpHandler` (SDK
builds the client internally). Auth is a fixture bearer token. No live
socket. Observed `stop_reason` / `tool_call_count` / `usage_*` /
`text_characters` / `payload_tool_count` are exact. First
Friend-MachineD freeze 0.67× (4316 / 6406 µs), ceiling 1.5.

### Pair 13 — `cli_settings`

| metric | cadr | pi |
|---|---|---|
| `create` | `make-settings-manager` (`settings/manager.lisp`) | `SettingsManager.create` (`settings-manager.ts`) |

Same fixture bytes: `settings-global.json` + `settings-project.json` staged as
`agent/settings.json` and `cwd/.pi/settings.json`. No TUI, no socket.
Observed `theme` / `default_model` / `compaction_reserve_tokens` /
`http_idle_timeout_ms` / `project_trusted` are exact. First
Friend-MachineD freeze 0.13× (105 / 813 µs), ceiling 1.5.

### Pair 14 — `resource_loader`

| metric | cadr | pi |
|---|---|---|
| `reload` | `reload-resources` (`resource-loader.lisp`) | `DefaultResourceLoader.reload` |

Fixture skills + prompt templates staged under an isolated agent dir
and cwd overlay. Auto-discovery is off so host `~/.agents/skills`
cannot leak; explicit paths are the production CLI extra-path
argument to `reload`. No TUI, no socket. Observed skill/prompt
counts and project-wins names are exact. First Friend-MachineD
freeze 0.29× (568 / 1978 µs), ceiling 1.5.

### Pair 15 — `provider_mistral`

| metric | cadr | pi |
|---|---|---|
| `stream_roundtrip` | `stream-chat` + `mistral.lisp` + chat-completions SSE | `stream` (`packages/ai/src/api/mistral-conversations.ts`) |

Same fixture bytes as the openai-completions pair's context, plus
recorded Mistral Conversations SSE (`mistral-conversations.sse`).
Seam = `*http-request-function*` / `options.fetch`. No live socket.
Observed `stop_reason` / `tool_call_count` / `usage_*` /
`text_characters` / `payload_stream` / `payload_tool_count` are exact.
First Friend-MachineD freeze 1.89× (3401 / 1801 µs), ceiling 3.0.

### Pair 16 — `provider_openai_responses`

| metric | cadr | pi |
|---|---|---|
| `stream_roundtrip` | `stream-chat` + `openai.lisp` + Responses SSE | `stream` (`packages/ai/src/api/openai-responses.ts`) |

Same fixture bytes as the openai-completions pair's context, plus
recorded OpenAI Responses SSE (`openai-responses.sse`). Seam =
`*http-request-function*` / `options.fetch`. No live socket.
Observed `stop_reason` / `tool_call_count` / `usage_*` /
`text_characters` / `payload_stream` / `payload_tool_count` are exact.
First Friend-MachineD freeze 0.37× (1460 / 3901 µs), ceiling 1.5.

### Pair 17 — `provider_azure_openai`

| metric | cadr | pi |
|---|---|---|
| `stream_roundtrip` | `stream-chat` + `azure-openai.lisp` + Responses SSE | `stream` (`packages/ai/src/api/azure-openai-responses.ts`) |

Same fixture bytes as the openai-completions pair's context, plus
recorded Azure OpenAI Responses SSE (`azure-openai-responses.sse`,
same Responses event shape as `openai-responses.sse`). Seam =
`*http-request-function*` / `options.fetch`. No live socket.
Observed `stop_reason` / `tool_call_count` / `usage_*` /
`text_characters` / `payload_stream` / `payload_tool_count` are exact.
First Friend-MachineD freeze 0.33× (1369 / 4152 µs), ceiling 1.5.

### Pair 18 — `provider_vertex`

| metric | cadr | pi |
|---|---|---|
| `stream_roundtrip` | `stream-chat` + `vertex.lisp` + Vertex SSE | `stream` (`packages/ai/src/api/google-vertex.ts`) |

Same fixture bytes as the google pair's context, plus recorded Vertex
SSE (`google-vertex.sse`, same GenerateContent event shape as
`google-generative-ai.sse`) and fixture ADC JSON (`vertex-adc.json`).
Seam = `*http-request-function*` / `globalThis.fetch` (the adapter
rejects `options.fetch`). API key on the timed thunk so
google-auth-library does not open a socket; ADC bytes are hashed and
parsed off the timed path. No live Google call.
Observed `stop_reason` / `tool_call_count` / `usage_*` /
`text_characters` / `payload_tool_count` / `adc_type` are exact.
First Friend-MachineD freeze 0.49× (2641 / 5443 µs), ceiling 1.5.

### Pair 19 — `provider_codex`

| metric | cadr | pi |
|---|---|---|
| `stream_roundtrip` | `stream-chat` + `codex.lisp` + Responses SSE | `stream` (`packages/ai/src/api/openai-codex-responses.ts`) |

Same fixture bytes as the openai-completions pair's context, plus
recorded Codex Responses SSE (`openai-codex-responses.sse`, same
Responses event shape as `openai-responses.sse`). Fixture OAuth JWT
(no live ChatGPT). Seam = `*http-request-function*` / `options.fetch`.
`transport=sse` so the websocket probe stays off. No live socket.
Observed `stop_reason` / `tool_call_count` / `usage_*` /
`text_characters` / `payload_stream` / `payload_tool_count` are exact.
First Friend-MachineD freeze 1.26× (1582 / 1258 µs), ceiling 1.5.
After stringify-skip knife `4ac111707`: **1.08×** (1327 / 1226 µs).
Ceiling 1.5 not lowered.

### Pair 20 — `package_manager`

| metric | cadr | pi |
|---|---|---|
| `resolve` | `configured-package-records` + `materialize-package-records` + `package-resource-paths` | `DefaultPackageManager.resolve` (`packages/coding-agent/src/core/package-manager.ts`) |

Fixture local package path (`./pkg` in agent settings) + `package.json`
`pi` manifest listing one skill, prompt, theme, and extension file.
No npm, no TUI, no socket. `PI_OFFLINE=1` on the pi half.
Observed `package_count` / `skill_count` / `prompt_count` /
`theme_count` / `extension_count` are exact.
First Friend-MachineD freeze 0.36× (200 / 551 µs), ceiling 1.5.

### Pair 21 — `provider_pi_messages`

| metric | cadr | pi |
|---|---|---|
| `stream_roundtrip` | `stream-chat` + `pi-messages.lisp` + native SSE | `stream` (`packages/ai/src/api/pi-messages.ts`) |

Same fixture bytes as the openai-completions pair's context, plus
recorded pi-messages SSE (`pi-messages.sse`: `text_*` /
`toolcall_*` / `done`). Seam = `*http-request-function*` /
`options.fetch`. No live socket.
Observed `stop_reason` / `tool_call_count` / `usage_*` /
`text_characters` / `payload_tool_count` are exact.
First Friend-MachineD freeze 1.25× (1103 / 885 µs), ceiling 1.5.

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

## 6. Unpairable paths and K-advanceable share

Part H item 2: unpairable paths are listed with reasons, not skipped.
Item 3: this share is the Part K advanceable surface.

<!-- GOAL20_UNPAIRED_PATHS_START -->

Produced by `scripts/goal20-unpaired-paths.py` from
`docs/benchmarks/goal20-unpaired-paths.json`. Do not edit the
tables by hand. `--check` fails when a new `src/**/*.lisp` file
is not reflected in the booked denominator, or when a prefix
matches nothing.

Denominator: **295 files / 127,337 lines**
(same Part I lock: `src/**/*.lisp`, `wc -l`).

| class | files | lines | share of lines | Part K |
|---|---:|---:|---:|---|
| `paired` | 69 | 37,606 | 29.5% | `no worse than baseline` is falsifiable |
| `unpairable` | 24 | 7,475 | 5.9% | single reference vs previous cadr |
| `pairable-uncovered` | 202 | 82,256 | 64.6% | blocked by Part A hard condition 2 |

- **Falsifiable vs baseline:** 29.5% of lines (69 files). This is the share whose `no worse than baseline` claim is a measured pair.
- **K-advanceable** (paired ∪ unpairable): 35.4% of lines.
- **K-blocked** until a new pair or a booked unpairable finding: 64.6% of lines.

H does not require the paired ratios to be ≤ 1.0×; that is Part O.

### 6.1 Unpairable paths

These have no same-path baseline counterpart, so no same-input pair
exists. Absence is a recorded decision, not an oversight. A path may
be unpairable without owning every line of a file (restarts live
inside otherwise-pairable tool execution).

| path | why unpairable | booked files |
|---|---|---|
| --slynk loopback REPL | Approved Lisp-native addition (Goal 10 D2). The baseline has no in-process REPL that can take the same input. | `src/cadr-cli/remote-repl.lisp` |
| Lisp extension host (load, compile, dispatch) | Baseline extensions are JavaScript modules; the input artifact differs, so same-fixture-bytes pairing is impossible. Observable wire events stay on event-diff. | `src/cadr-agent/extensions/api.lisp`<br>`src/cadr-agent/extensions/commands.lisp`<br>`src/cadr-agent/extensions/context.lisp`<br>`src/cadr-agent/extensions/lifecycle.lisp`<br>`src/cadr-agent/extensions/providers.lisp`<br>`src/cadr-agent/extensions/registration.lisp`<br>`src/cadr-agent/extensions/rendering.lisp`<br>`src/cadr-agent/extensions/snapshot.lisp` |
| Tool-failure restarts and :tool-call-error | Approved Lisp-native addition (Goal 10 D1) with no baseline path. The default tool-execution path is still pairable and is not covered yet. | — (path, not an exclusive file) |
| Redacted fatal-condition summary and 0600 crash log | Approved Goal 13 divergence: the baseline prints a terminal stack dump. The two do different work by design. | `src/cadr-ai/crash.lisp`<br>`src/cadr-cli/crash.lisp` |
| SBCL native-image build and process cold start | An image start against a Node bundle start measures the two runtimes, not cadr vs baseline code. Cold start keeps its own absolute ceiling. | `src/cadr-cli/build-support.lisp` |
| OAuth success/failure page mark | Branding-only difference (cons-cell grid instead of the baseline logo). | `src/cadr-ai/oauth/page.lisp` |
| Live-credential provider calls | A network call is not a fixture. stream_roundtrip covers deterministic assembly and parse; the live path stays credential-gated. | — (path, not an exclusive file) |
| ASDF/Quicklisp build and deterministic vs live test entry points | Build- and test-ecosystem difference, already an approved category. Not production src. | — (path, not an exclusive file) |
| cadr-server session-server contract | Baseline v0.84.1 rewrote packages/server; cadr-server still speaks the v0.83 session-server contract (goal 18 L1b pending adjudication). Same-input pairing is undefined until that alignment lands. | `src/cadr-server/config.lisp`<br>`src/cadr-server/handler.lisp`<br>`src/cadr-server/ipc.lisp`<br>`src/cadr-server/main.lisp`<br>`src/cadr-server/package.lisp`<br>`src/cadr-server/protocol.lisp`<br>`src/cadr-server/radius.lisp`<br>`src/cadr-server/rpc-process.lisp`<br>`src/cadr-server/storage.lisp`<br>`src/cadr-server/supervisor.lisp`<br>`src/cadr-server/types.lisp` |

`src/cadr-agent/sqlite-storage.lisp` and `src/cadr-storage/` are
**not** unpairable: the baseline ships `packages/session-backends/sqlite-node`,
so SQLite is pairable and simply not covered yet.

### 6.2 Currently paired owners

A file is `paired` when a live Part H or Goal 11 thunk names it as
production work, not merely as a transitive callee. Callees that
are not named stay `pairable-uncovered`.

| file | lines | metrics |
|---|---:|---|
| `src/cadr-agent/compaction.lisp` | 883 | `session_compact.compact` |
| `src/cadr-agent/loop/agent-loop.lisp` | 442 | `agent_tool_loop.roundtrip` |
| `src/cadr-agent/loop/events.lisp` | 169 | `agent_tool_loop.roundtrip` |
| `src/cadr-agent/loop/tool-execution.lisp` | 489 | `agent_tool_loop.roundtrip` |
| `src/cadr-agent/loop/turns.lisp` | 393 | `agent_tool_loop.roundtrip` |
| `src/cadr-agent/messages.lisp` | 253 | `session_compact.compact` |
| `src/cadr-agent/resources.lisp` | 739 | `resource_loader.reload` |
| `src/cadr-agent/session/codec.lisp` | 1,152 | `storage_journal.journal_read`, `storage_journal.journal_append` |
| `src/cadr-agent/session/journal.lisp` | 679 | `session_pipeline.context_walk`, `storage_journal.journal_append` |
| `src/cadr-agent/session/migration.lisp` | 2,382 | `session_pipeline.session_load`, `storage_journal.journal_read` |
| `src/cadr-agent/sqlite-storage.lisp` | 839 | `sqlite_session.open_walk` |
| `src/cadr-agent/summarization.lisp` | 86 | `session_compact.compact` |
| `src/cadr-agent/tool.lisp` | 319 | `agent_tool_loop.roundtrip` |
| `src/cadr-agent/truncate.lisp` | 554 | `text_truncation.truncate_head`, `text_truncation.truncate_tail` |
| `src/cadr-ai/auth/bedrock.lisp` | 220 | `provider_bedrock.stream_roundtrip` |
| `src/cadr-ai/auth/vertex.lisp` | 212 | `provider_vertex.stream_roundtrip` |
| `src/cadr-ai/json.lisp` | 1,920 | `provider_stream.stream_roundtrip`, `storage_journal.journal_read`, `storage_journal.journal_append`, `session_pipeline.session_load` |
| `src/cadr-ai/provider.lisp` | 799 | `provider_stream.stream_roundtrip` |
| `src/cadr-ai/providers/anthropic.lisp` | 644 | `provider_anthropic.stream_roundtrip` |
| `src/cadr-ai/providers/azure-openai.lisp` | 223 | `provider_azure_openai.stream_roundtrip` |
| `src/cadr-ai/providers/bedrock.lisp` | 934 | `provider_bedrock.stream_roundtrip` |
| `src/cadr-ai/providers/codex.lisp` | 35 | `provider_codex.stream_roundtrip` |
| `src/cadr-ai/providers/google.lisp` | 442 | `provider_google.stream_roundtrip` |
| `src/cadr-ai/providers/mistral.lisp` | 97 | `provider_mistral.stream_roundtrip` |
| `src/cadr-ai/providers/openai-completions.lisp` | 880 | `provider_stream.stream_roundtrip` |
| `src/cadr-ai/providers/openai.lisp` | 828 | `provider_openai_responses.stream_roundtrip` |
| `src/cadr-ai/providers/pi-messages.lisp` | 255 | `provider_pi_messages.stream_roundtrip` |
| `src/cadr-ai/providers/vertex.lisp` | 134 | `provider_vertex.stream_roundtrip` |
| `src/cadr-ai/sse.lisp` | 267 | `provider_stream.stream_roundtrip` |
| `src/cadr-ai/transport/aws-event-stream.lisp` | 222 | `provider_bedrock.stream_roundtrip` |
| `src/cadr-cli/arguments.lisp` | 1,036 | `cli_dispatch.argv_parse`, `cli_dispatch.help_render` |
| `src/cadr-cli/bootstrap/main.lisp` | 409 | `cli_dispatch.list_models_render` |
| `src/cadr-cli/interactive/entries.lisp` | 918 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-cli/interactive/frame.lisp` | 232 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-cli/interactive/state.lisp` | 303 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-cli/interactive/status.lisp` | 445 | `goal11.continuous_alt_input` |
| `src/cadr-cli/interactive/tool-rendering.lisp` | 1,015 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-cli/models/registry.lisp` | 846 | `cli_dispatch.list_models_registry` |
| `src/cadr-cli/models/store.lisp` | 197 | `cli_dispatch.list_models_registry` |
| `src/cadr-cli/packages/commands.lisp` | 764 | `package_manager.resolve` |
| `src/cadr-cli/packages/manifest.lisp` | 142 | `package_manager.resolve` |
| `src/cadr-cli/packages/settings.lisp` | 214 | `package_manager.resolve` |
| `src/cadr-cli/packages/source.lisp` | 338 | `package_manager.resolve` |
| `src/cadr-cli/resource-loader.lisp` | 353 | `resource_loader.reload` |
| `src/cadr-cli/settings/config-values.lisp` | 198 | `cli_settings.create` |
| `src/cadr-cli/settings/manager.lisp` | 512 | `cli_settings.create` |
| `src/cadr-cli/tools/grep.lisp` | 331 | `tool_grep.context_file` |
| `src/cadr-cli/tools/read.lisp` | 192 | `tool_read.text_file` |
| `src/cadr-cli/truncation.lisp` | 235 | `tool_read.text_file` |
| `src/cadr-storage/package.lisp` | 19 | `sqlite_session.open_walk` |
| `src/cadr-storage/sqlite.lisp` | 12 | `sqlite_session.open_walk` |
| `src/cadr-tui/components/image.lisp` | 40 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/components/markdown.lisp` | 1,553 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/components/tool-block.lisp` | 623 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/composition/protocol.lisp` | 143 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/composition/rich-content.lisp` | 276 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/composition/root.lisp` | 317 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/composition/text-box.lisp` | 280 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/editor.lisp` | 2,014 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/input.lisp` | 333 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/keys.lisp` | 606 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/renderer/alt-screen-search.lisp` | 181 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/renderer/alt-screen.lisp` | 610 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/renderer/lifecycle-input.lisp` | 1,353 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/renderer/main-screen.lisp` | 595 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/renderer/terminal-protocol.lisp` | 78 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/renderer/virtual-terminal.lisp` | 184 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/terminal.lisp` | 916 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/unicode.lisp` | 1,302 | `render_slicing.slice_ansi_clip`, `render_slicing.slice_plain_clip` |

### 6.3 Pairable, not yet paired

Grouped by directory. Every line here still has a baseline
counterpart; large-scale Lisp-ification is blocked until a pair
is added or the path is booked unpairable above.

| module | files | lines |
|---|---:|---:|
| `src/cadr-cli/interactive` | 27 | 16,379 |
| `src/cadr-ai/models.generated.lisp` | 1 | 8,711 |
| `src/cadr-cli/bootstrap` | 5 | 5,632 |
| `src/cadr-tui/mermaid` | 12 | 5,042 |
| `src/cadr-cli/extensions` | 9 | 3,489 |
| `src/cadr-cli/sdk` | 8 | 2,471 |
| `src/cadr-cli/modes` | 8 | 2,302 |
| `src/cadr-cli/tools` | 7 | 2,166 |
| `src/cadr-tui/latex.lisp` | 1 | 1,950 |
| `src/cadr-cli/packages` | 2 | 1,811 |
| `src/cadr-ai/oauth` | 10 | 1,786 |
| `src/cadr-agent/storage` | 4 | 1,532 |
| `src/cadr-ai/providers` | 3 | 1,494 |
| `src/cadr-cli/models` | 4 | 1,472 |
| `src/cadr-ai/runtime` | 2 | 1,410 |
| `src/cadr-cli/media.lisp` | 1 | 1,277 |
| `src/cadr-cli/support` | 13 | 1,164 |
| `src/cadr-ai/support` | 7 | 908 |
| `src/cadr-ai/transport` | 1 | 858 |
| `src/cadr-agent/execution-env.lisp` | 1 | 855 |
| `src/cadr-agent/schema.lisp` | 1 | 850 |
| `src/cadr-ai/capabilities` | 6 | 751 |
| `src/cadr-evals/harness.lisp` | 1 | 737 |
| `src/cadr-evals/summary.lisp` | 1 | 732 |
| `src/cadr-tui/composition` | 2 | 705 |
| `src/cadr-tui/terminal-image.lisp` | 1 | 686 |
| `src/cadr-ai/websocket.lisp` | 1 | 628 |
| `src/cadr-protocol/schema.lisp` | 1 | 610 |
| `src/cadr-agent/session` | 2 | 609 |
| `src/cadr-tui/autocomplete.lisp` | 1 | 594 |
| `src/cadr-tui/theme.lisp` | 1 | 562 |
| `src/cadr-tui/components` | 2 | 558 |
| `src/cadr-cli/migration.lisp` | 1 | 512 |
| `src/cadr-protocol/cbor.lisp` | 1 | 492 |
| `src/cadr-tui/overlay.lisp` | 1 | 485 |
| `src/cadr-ai/package.lisp` | 1 | 480 |
| `src/cadr-evals/suites.lisp` | 1 | 468 |
| `src/cadr-agent/package.lisp` | 1 | 456 |
| `src/cadr-agent/runtime.lisp` | 1 | 421 |
| `src/cadr-ai/auth` | 3 | 410 |
| `src/cadr-tui/input-component.lisp` | 1 | 408 |
| `src/cadr-ai/model-data.lisp` | 1 | 407 |
| `src/cadr-ai/crypto.lisp` | 1 | 367 |
| `src/cadr-tui/package.lisp` | 1 | 355 |
| `src/cadr-evals/harness-table.lisp` | 1 | 339 |
| `src/cadr-evals/reporter.lisp` | 1 | 314 |
| `src/cadr-cli/package.lisp` | 1 | 289 |
| `src/cadr-ai/models.lisp` | 1 | 288 |
| `src/cadr-cli/tool-manager.lisp` | 1 | 286 |
| `src/cadr-cli/config.lisp` | 1 | 284 |
| `src/cadr-tui/keybindings.lisp` | 1 | 268 |
| `src/cadr-agent/proxy.lisp` | 1 | 251 |
| `src/cadr-tui/stdin-buffer.lisp` | 1 | 232 |
| `src/cadr-ai/images.lisp` | 1 | 222 |
| `src/cadr-cli/settings` | 1 | 216 |
| `src/cadr-ai/auth.lisp` | 1 | 207 |
| `src/cadr-ai/types.lisp` | 1 | 207 |
| `src/cadr-cli/output-accumulator.lisp` | 1 | 199 |
| `src/cadr-tui/terminal-colors.lisp` | 1 | 191 |
| `src/cadr-agent/branch-summarization.lisp` | 1 | 185 |
| `src/cadr-ai/image-models.generated.lisp` | 1 | 185 |
| `src/cadr-protocol/framing.lisp` | 1 | 170 |
| `src/cadr-evals/artifacts.lisp` | 1 | 168 |
| `src/cadr-evals/main.lisp` | 1 | 158 |
| `src/cadr-tui/fuzzy.lisp` | 1 | 134 |
| `src/cadr-core/time.lisp` | 1 | 133 |
| `src/cadr-protocol/codec.lisp` | 1 | 121 |
| `src/cadr-tui/word-navigation.lisp` | 1 | 118 |
| `src/cadr-cli/repl.lisp` | 1 | 112 |
| `src/cadr-core/atomic-file.lisp` | 1 | 106 |
| `src/cadr-evals/package.lisp` | 1 | 100 |
| `src/cadr-core/paths.lisp` | 1 | 95 |
| `src/cadr-agent/file-mutation-queue.lisp` | 1 | 92 |
| `src/cadr-tui/native-modifiers.lisp` | 1 | 78 |
| `src/cadr-agent/harness-events.lisp` | 1 | 75 |
| `src/cadr-core/cancellation.lisp` | 1 | 70 |
| `src/cadr-cli/system-prompt.lisp` | 1 | 53 |
| `src/cadr-core/threads.lisp` | 1 | 47 |
| `src/cadr-ai/conditions.lisp` | 1 | 44 |
| `src/cadr-core/redacted-print.lisp` | 1 | 44 |
| `src/cadr-agent/conditions.lisp` | 1 | 43 |
| `src/cadr-core/package.lisp` | 1 | 43 |
| `src/cadr-tui/kill-ring.lisp` | 1 | 38 |
| `src/cadr-protocol/package.lisp` | 1 | 33 |
| `src/cadr-tui/undo-stack.lisp` | 1 | 20 |
| `src/cadr-tui/threads.lisp` | 1 | 6 |

<!-- GOAL20_UNPAIRED_PATHS_END -->
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
