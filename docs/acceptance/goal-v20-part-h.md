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

### Pair 22 — `session_discovery`

| metric | cadr | pi |
|---|---|---|
| `header_probe` | `read-session-header-for-discovery` over `*.jsonl` + newest mtime | `findMostRecentSession` (`packages/coding-agent/src/core/session-manager.ts`) |

32 copies of the existing `session.jsonl` fixture with distinct
utimes. Time directory list + header probe, not `load-session`.
No TUI, no socket. Observed `file_count` / `header_count` /
`found` / `session_id` / `most_recent_name` are exact.
First Friend-MachineD freeze **2.05×** (1449.6 / 708.6 µs),
ceiling 8.0. Same commit no optimize.

### Pair 23 — `session_export_html`

| metric | cadr | pi |
|---|---|---|
| `to_html` | `export-session-html` | `exportSessionToHtml` (`packages/coding-agent/src/core/export-html/index.ts`) |

Existing `session.jsonl` loaded once, then timed HTML write
(`theme=dark`). No TUI, no socket. Observed `has_accent` /
`theme` are exact. `html_chars` is a booked size gap (cadr
555702 / pi 546995, +1.6%; JSON key order in the embedded
payload), not an exact field. First Friend-MachineD freeze
**3.55×** (29217.8 / 8239.7 µs), ceiling 20.0. Same commit
no optimize.

### Pair 24 — `protocol_cbor`

| metric | cadr | pi |
|---|---|---|
| `roundtrip` | `encode-cbor` + `decode-cbor` | `encodeCbor` + `decodeCbor` (`packages/protocol/src/cbor`) |

16 RFC 8949 vectors (null/bool/int/string/empty array/map).
Observed `vector_count` / `roundtrip_hex` / `match` are exact
(match=1). `cbor.lisp` is the timed owner; `package.lisp` is a
callee; codec/framing/schema stay `needs-pair`. First
Friend-MachineD freeze **0.25×** (17.7 / 70.1 µs), ceiling 1.5.
Same commit no optimize.

### Pair 25 — `agent_schema`

| metric | cadr | pi |
|---|---|---|
| `validate_ok_fail` | `validate-tool-arguments` | `validateToolArguments` (`packages/ai/src/utils/validation.ts`) |

FiveAM nested edit-tool JSON Schema (path + edits[{oldText,newText}]).
Time one ok call and one fail call (missing `newText`). No TUI, no
socket. Observed `ok` / `fail` / `tool` are exact. First
Friend-MachineD freeze **0.38×** (34.2 / 89.4 µs), ceiling 1.5.
Same commit no optimize.

### Pair 26 — `harness_storage`

| metric | cadr | pi |
|---|---|---|
| `open_walk` | `jsonl-session-repository` open + entries + branch | `JsonlSessionRepo.open` + `findEntries` + `findEntriesOnBranch` |

Ingest existing `session.jsonl` into harness JSONL storage (not
v3 `storage_journal`, not SQLite). Time open + read-all + leaf
walk. No TUI, no socket. Observed `entry_count` / `leaf_id` /
`ingested_entry_count` / `session_id` / `source_leaf_id` are
exact. `branch_entry_count` is a booked shape gap (cadr 322 /
pi 514), not exact. First Friend-MachineD freeze **1.80×**
(11643.5 / 6484.9 µs), ceiling 8.0. Same commit no optimize.

### Pair 27 — `protocol_codec`

| metric | cadr | pi |
|---|---|---|
| `roundtrip` | `encode-client-message` + `message-decoder-push` | `encodeClientMessage` + `createClientMessageDecoder` |

Same-input client `list` request (`type=request`, `command=list`).
Time encode + incremental decode through length-prefixed frames.
Observed `frame_bytes` / `message_count` / `type` / `id` /
`command` are exact (53-byte frame). Independent of
`protocol_cbor.roundtrip`. First Friend-MachineD freeze **0.10×**
(9.6 / 94.2 µs), ceiling 1.5. Same commit no optimize.

### Pair 28 — `agent_proxy`

| metric | cadr | pi |
|---|---|---|
| `stream_roundtrip` | `stream-proxy` | `streamProxy` (`packages/agent/src/proxy.ts`) |

Stub SSE (no socket): start / text_* / done. Observed `event_count`
/ `text` / `usage_total` are exact. First Friend-MachineD freeze
**1.59×** (25.4 / 16.0 µs), ceiling 1.5 (variance bound). Same
commit no optimize.

### Pair 29 — `oauth_pkce`

| metric | cadr | pi |
|---|---|---|
| `challenge_urls` | `pkce-challenge` + openai/anthropic authorize URLs | SHA-256 S256 challenge + openai-codex/anthropic authorize URLs |

RFC 7636 recorded verifier (no `/dev/urandom`, no browser, no
token HTTP). Observed `challenge` is the RFC vector
`E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM`; URL prefixes
and `*_has_challenge` are exact. Other oauth_pkce_device files
stay `needs-pair`. First Friend-MachineD freeze **0.37×**
(50.6 / 135.3 µs), ceiling 1.5. Same commit no optimize.

### Pair 30 — `evals_harness`

| metric | cadr | pi |
|---|---|---|
| `summarize` | `summarize-harness-comparisons` | `summarizeHarnessComparisons` |

Same four scored observations as the FiveAM summary test (tool
access create/inspect). Time report assembly, not a live eval
run. Observed `eval_sets` / `comparisons` / `candidate_wins` /
`ties` are exact. Other evals files stay `needs-pair`. First
Friend-MachineD freeze **0.88×** (8.0 / 9.0 µs), ceiling 1.5.
Same commit no optimize.

### Pair 31 — `ai_crypto_model_data`

| metric | cadr | pi |
|---|---|---|
| `manifest` | `create-model-data-manifest` | `createModelDataManifest` (`packages/ai/scripts/model-data.ts`) |

In-memory two-provider structure + two JSON shard strings +
fixed `generatedAt`. Time SHA-256 catalog manifest, not the
directory walk (cadr reads a JSON dir; pi reads
`models.generated.ts`). No TUI, no socket. Observed
`schema_version` / `structure_hash` / `generated_at` /
`file_count` / `openai_json_hash` / `anthropic_json_hash`
are exact. HMAC is a leftover sibling pair
(`ai_crypto.hmac`). First Friend-MachineD freeze **8.97×**
(77.3 / 8.6 µs), ceiling 20.0. Same commit no optimize.

### Pair 32 — `cli_models_rest`

| metric | cadr | pi |
|---|---|---|
| `pattern_match` | `parse-scoped-model-pattern` | `parseModelPattern` (`packages/coding-agent/src/core/model-resolver.ts`) |

Staged `models.json` / `auth.json` (same agent dir as
`list_models_registry`). Time five patterns: canonical
`goal20faux/goal20-paired-0`, bare id, substring `paired-2`,
`goal20-paired-3:high`, and a miss. No TUI, no socket.
Observed `exact_id` / `exact_provider` / `bare_id` /
`partial_id` / `scoped_id` / `scoped_thinking` / `miss` are
exact (`partial_id` is `goal20-paired-23`: highest alias
substring, not `goal20-paired-2`). Other cli_models_rest
files stay `needs-pair`. First Friend-MachineD freeze
**1.65×** (31.9 / 19.4 µs), ceiling 3.0. Same commit no
optimize.

### Pair 33 — `image_runtime`

| metric | cadr | pi |
|---|---|---|
| `dimensions` | `image-dimensions` | `getImageDimensions` (`packages/tui/src/terminal-image.ts`) |

1x1 RGB PNG + 2x3 GIF89a as base64, plus a miss mime.
Time header parse, not Kitty/iTerm encode or a live image
API. Observed `png_width` / `png_height` / `gif_width` /
`gif_height` / `miss` are exact (1×1, 2×3, miss=1). Other
image_runtime files stay `needs-pair`. First Friend-MachineD
freeze **5.44×** (7.8 / 1.4 µs), ceiling 8.0. Same commit no
optimize.

### Pair 34 — `cli_print_rpc`

| metric | cadr | pi |
|---|---|---|
| `jsonl_line` | `write-json-line` | `serializeJsonLine` (`packages/coding-agent/src/modes/rpc/jsonl.ts`) |

Same RPC response object (`command=get_state`, `id=rpc-1`).
Time JSONL frame write (stringify + LF), not a live stdin
RPC loop. Observed `line_chars` / `newline` / `payload` are
exact (70 chars, LF, keys sorted). Other cli_print_rpc files
stay `needs-pair`. First Friend-MachineD freeze **13.21×**
(3.3 / 0.25 µs), ceiling 8.0 (variance / microsecond floor).
Same commit no optimize.

### Pair 35 — `tui_latex`

| metric | cadr | pi |
|---|---|---|
| `render` | `render-latex` | `renderLatex` (`packages/tui/src/latex.ts`) |

FiveAM reference snippets: `E = mc^2`, inline/display
`\frac{1}{2}`, greek, unsupported command. Time Unicode
render, not a TUI frame. Observed `e_mc2` / `frac_inline` /
`greek` / `frac_display_newlines` / `unknown_miss` are
exact. First Friend-MachineD freeze **2.49×** (64.4 / 25.8
µs), ceiling 3.0. Same commit no optimize.

### Pair 36 — `tui_editor_helpers`

| metric | cadr | pi |
|---|---|---|
| `fuzzy_match` | `fuzzy-match` | `fuzzyMatch` (`packages/tui/src/fuzzy.ts`) |

Queries against `gpt-4o`: `gpt`, `4o`, `g4`, `xyzzy`, empty.
Time match flags, not a TUI frame. Observed `gpt` /
`id_suffix` / `swapped` / `empty` = 1 and `miss` = 0
(`xyzzy` does not match) are exact. Other editor-helper
files stay `needs-pair`. First Friend-MachineD freeze
**0.45×** (1.8 / 4.0 µs), ceiling 8.0. Same commit no
optimize.

### Pair 37 — `tui_theme_overlay`

| metric | cadr | pi |
|---|---|---|
| `osc11_bg` | `parse-osc-11-background-color` | `parseOsc11BackgroundColor` (`packages/tui/src/terminal-colors.ts`) |

OSC 11 `rgb:` / `#RRGGBB` / 12-digit hex, a prefix miss,
and `?997;1n` dark scheme. Time parse, not a TUI frame.
Observed RGB triples / `miss` / `scheme_dark` are exact.
`theme.lisp` / `overlay.lisp` stay `needs-pair`. First
Friend-MachineD freeze **1.16×** (3.8 / 3.3 µs), ceiling
8.0. Same commit no optimize.

### Pair 38 — `ai_support`

| metric | cadr | pi |
|---|---|---|
| `estimate_text` | `estimate-text-tokens` | `estimateTextTokens` (`packages/ai/src/utils/estimate.ts`) |

Empty / `hello world` / 100 ASCII `a`. Time `ceil(utf16/4)`,
no TUI, no socket. Observed `empty` / `hello` / `block` are
exact (0 / 3 / 25). Other ai_support files stay `needs-pair`.
First Friend-MachineD freeze **3.10×** (0.54 / 0.17 µs),
ceiling 8.0 (variance / microsecond floor). Same commit no
optimize.

### Pair 39 — `tui_select_settings_loaders`

| metric | cadr | pi |
|---|---|---|
| `filter` | `select-list-filtered-items` | `SelectList.setFilter` (`packages/tui/src/components/select-list.ts`) |

Items hello/help/world. Filters `he` / `wo` / `zz`. Time
prefix filter, not a live TUI. Observed `he_count` /
`he_first` / `wo_count` / `zz_count` are exact (2 / hello /
1 / 0). Other files stay `needs-pair`. First
Friend-MachineD freeze **1.27×** (1.2 / 1.0 µs), ceiling
8.0 (variance). Same commit no optimize.

### Pair 40 — `tui_word_navigation`

| metric | cadr | pi |
|---|---|---|
| `step` | `find-word-backward` + `find-word-forward` | `findWordBackward` + `findWordForward` (`packages/tui/src/word-navigation.ts`) |

ASCII `"hello world"`. Time word steps, not a TUI frame.
Observed `back_from_space` / `fwd_from_o` / `back_start` /
`fwd_end` are exact (6 / 11 / 0 / 11). First Friend-MachineD
freeze **0.17×** (0.94 / 5.4 µs), ceiling 8.0. Same commit
no optimize.

### Pair 41 — `tui_overlay`

| metric | cadr | pi |
|---|---|---|
| `composite_line` | `composite-overlay-line` | `compositeTuiLine` (`packages/tui/src/tui.ts`) |

ASCII base `"hello world this is a long line"` overlay
`"OVER"` at col 6 width 4 total 40. Time compositing, not
a TUI frame. Observed `line_chars` / `visible_width` /
`has_reset` are exact (60 / 40 / 1). `theme.lisp` stays
`needs-pair`. First Friend-MachineD freeze **0.87×**
(19.1 / 22.0 µs), ceiling 8.0. Same commit no optimize.

### Pair 42 — `tui_kill_ring`

| metric | cadr | pi |
|---|---|---|
| `push_peek` | `kill-ring-push` + `kill-ring-peek` + `kill-ring-rotate` | `KillRing.push` + `peek` + `rotate` (`packages/tui/src/kill-ring.ts`) |

Push `aa`/`bbb`, rotate (n=2), accumulate append `ab`+`c`,
accumulate prepend `yz`+`x`. Time the ring, not a TUI
frame. Observed `empty_len` / `ring_len` / `peek_two` /
`peek_rot` / `acc_append` / `acc_prepend` are exact
(0 / 2 / 3 / 2 / 3 / 3). Other editor-helper files stay
`needs-pair`. First Friend-MachineD freeze **0.85×**
(0.58 / 0.68 µs), ceiling 8.0 (variance / microsecond
floor). Same commit no optimize.

### Pair 43 — `tui_undo_stack`

| metric | cadr | pi |
|---|---|---|
| `push_pop` | `undo-stack-push` + `undo-stack-pop` + `undo-stack-clear` | `UndoStack.push` + `pop` + `clear` (`packages/tui/src/undo-stack.ts`) |

Clone-on-push `{text,n}`, mutate source, push a second
snapshot, pop, clear. Time the stack, not a TUI frame.
Observed `empty_len` / `after_two` / `pop_n` /
`after_pop` / `clone_n` / `after_clear` are exact
(0 / 2 / 2 / 1 / 1 / 0). Other editor-helper files stay
`needs-pair`. First Friend-MachineD freeze **0.21×**
(0.51 / 2.42 µs), ceiling 8.0. Same commit no optimize.

### Pair 44 — `tui_autocomplete`

| metric | cadr | pi |
|---|---|---|
| `suggest_apply` | `autocomplete-get-suggestions` + `autocomplete-apply` | `CombinedAutocompleteProvider.getSuggestions` + `applyCompletion` (`packages/tui/src/autocomplete.ts`) |

Slash `/he`, quoted `"hel`, force Tab `he`, `@he` with
no fd. Fixture dir `hello.txt` / `help.md` / `src/a.ts`.
Time token/quote + command filter + dir listing + apply,
not a TUI frame. Observed slash/quote/force/at/apply
fields are exact. Other editor-helper files stay
`needs-pair`. First Friend-MachineD freeze **5.17×**
(136.4 / 26.4 µs), ceiling 8.0. Same commit no optimize.

### Pair 45 — `tui_keybindings`

| metric | cadr | pi |
|---|---|---|
| `resolve_match` | `make-keybindings-manager` + `keybinding-keys` + `keybinding-matches-p` | `KeybindingsManager` / `getKeybindings` (`packages/tui/src/keybindings.ts`) |

Default TUI registry plus user `ctrl+k` clash on yank /
deleteToLineEnd. Time resolve + match + conflict, not a
TUI frame. Observed `left_count` / `left_ctrl_b` /
`hist_count` / `enter_submit` / `tab_tab` /
`enter_undo` / `conflict_count` / `conflict_key_len`
are exact (2 / 1 / 0 / 1 / 1 / 0 / 1 / 6). Other
editor-helper files stay `needs-pair`. First
Friend-MachineD freeze **1.88×** (27.7 / 14.8 µs),
ceiling 8.0. Same commit no optimize.

### Pair 46 — `tui_stdin_buffer`

| metric | cadr | pi |
|---|---|---|
| `process` | `stdin-buffer-process` | `StdinBuffer.process` (`packages/tui/src/stdin-buffer.ts`) |

`hello`, incomplete CSI `ESC[`, complete `A` (up),
bracketed paste `hi` then `x`. Time the buffer, not a
TUI frame. Observed `hello_count` / `leftover` /
`up_len` / `paste_len` / `tail_count` are exact
(5 / 2 / 3 / 2 / 1). Other editor-helper files stay
`needs-pair`. First Friend-MachineD freeze **0.33×**
(2.3 / 6.9 µs), ceiling 8.0. Same commit no optimize.

### Pair 47 — `tui_input_component`

| metric | cadr | pi |
|---|---|---|
| `edit` | `single-line-input-handle-event` | `Input.handleInput` (`packages/tui/src/components/input.ts`) |

Type `hello world`, backspace, kill-to-line-start, yank.
Time the input object, not a TUI frame. Observed
`after_insert` / `after_bs` / `after_kill` /
`after_yank` / `last_code` are exact (11 / 10 / 0 / 10 /
108). Other editor-helper files stay `needs-pair`. First
Friend-MachineD freeze **0.06×** (5.5 / 97.8 µs), ceiling
8.0. Same commit no optimize.

### Pair 48 — `tui_native_modifiers`

| metric | cadr | pi |
|---|---|---|
| `pressed` | `is-native-modifier-pressed` | `isNativeModifierPressed` (`packages/tui/src/native-modifiers.ts`) |

Keys shift/control/option/command. Production platform
gate, not a TUI frame, no native addon on Linux. Observed
all 0. Other editor-helper files stay `needs-pair`. First
Friend-MachineD freeze **7.50×** (1.22 / 0.16 µs), ceiling
8.0 (variance / microsecond floor). Same commit no
optimize.

### Pair 49 — `tui_settings_list`

| metric | cadr | pi |
|---|---|---|
| `apply_filter` | `settings-list-apply-filter` | `SettingsList.applyFilter` (`packages/tui/src/components/settings-list.ts`) |

Items Hello/Help/World. Queries `he` / `wo` / `zz`. Time
fuzzy filter, not a live TUI. Observed `he_count` /
`he_hello` / `he_help` / `wo_count` / `zz_count` /
`he_selected` are exact (2 / 1 / 1 / 1 / 0 / 0).
`loaders.lisp` stays `needs-pair`. First Friend-MachineD
freeze **0.47×** (5.3 / 11.4 µs), ceiling 8.0. Same
commit no optimize.

### Pair 50 — `ai_capabilities`

| metric | cadr | pi |
|---|---|---|
| `short_hash` | `short-hash` | `shortHash` (`packages/ai/src/utils/hash.ts`) |

Empty / `abc` / `中文😀`. Time UTF-16 hash, not a stream.
Observed `empty` / `abc` / `cjk` are exact
(`k4n83c7h0j2b` / `y0biex7f9bbh` / `1uqnrlm1d9i9jc`).
Other ai_capabilities files stay `needs-pair`. First
Friend-MachineD freeze **1.70×** (1.5 / 0.9 µs), ceiling
8.0 (variance / microsecond floor). Same commit no
optimize.

### Pair 51 — `cli_support`

| metric | cadr | pi |
|---|---|---|
| `strip_ansi` | `strip-ansi` | `stripAnsi` (`packages/coding-agent/src/utils/ansi.ts`) |

CSI + OSC hyperlink, RIS `ESC c`, single-byte `ESC m`,
plain `hello`. Time strip, not a TUI frame. Observed
`csi_osc` / `ris` / `single` / `plain` are exact
(`aredlinkz` / `done` / `ok` / `hello`). Other
cli_support files stay `needs-pair`. First
Friend-MachineD freeze **2.73×** (1.3 / 0.5 µs), ceiling
8.0 (variance / microsecond floor). Same commit no
optimize.

### Pair 52 — `cli_interactive_controller`

| metric | cadr | pi |
|---|---|---|
| `decode_entity` | `decode-highlight-entity` | `decodeHtmlEntity` (`packages/coding-agent/src/utils/html.ts`) |

Named entities amp/lt/gt/quot/apos, decimal `#65`,
unknown `nope`. Time decode, not a live TUI. Observed
`amp` / `lt` / `gt` / `quot` / `apos` / `hash65` /
`miss` are exact (`&` / `<` / `>` / `"` / `'` / `A` /
0). Other interactive-controller files stay `needs-pair`.
First Friend-MachineD freeze **1.49×** (0.63 / 0.42 µs),
ceiling 8.0 (variance / microsecond floor). Same commit
no optimize.

### Pair 53 — `cli_sdk`

| metric | cadr | pi |
|---|---|---|
| `version_newer` | `newer-package-version-p` | `isNewerPackageVersion` (`packages/coding-agent/src/utils/version-check.ts`) |

Valid semver `5.0.0-beta.20`/`9`, `1.2.3`/`1.2.4`/`1.3.0`.
No network. Observed `beta` / `eq` / `older` /
`newer_flag` / `equal_flag` are exact (1 / 0 / -1 / 1 /
0). Other cli_sdk files stay `needs-pair`. First
Friend-MachineD freeze **0.40×** (4.1 / 10.3 µs), ceiling
8.0. Same commit no optimize.

### Pair 54 — `provider_registry_defs`

| metric | cadr | pi |
|---|---|---|
| `lookup` | `find-provider-definition` | `getBuiltinProviders` (`packages/ai/src/providers/all.ts`) |

Presence of openai/anthropic/google and a miss.
Time lookup, no socket. Observed `openai` / `anthropic` /
`google` / `unknown` are exact (1 / 1 / 1 / 0). Catalog
counts differ (cadr 40 / pi 39); not exact. Other
registry files stay `needs-pair`. First Friend-MachineD
freeze **4.44×** (1.03 / 0.23 µs), ceiling 8.0 (variance /
microsecond floor). Same commit no optimize.

### Pair 55 — `skill_prompt_load`

| metric | cadr | pi |
|---|---|---|
| `build_prompt` | `build-system-prompt` | `buildSystemPrompt` (`packages/coding-agent/src/core/system-prompt.ts`) |

Custom prompt `hello`, append `extra`, context
`AGENTS.md`, cwd `/tmp/proj`. Time assemble, no TUI.
Observed `custom_len` / `append_len` / `ctx_len` /
`has_cwd` / `has_extra` / `has_agents` are exact
(43 / 50 / 206 / 1 / 1 / 1). Keyword initforms still
hit ASDF on this path. Other skill_prompt files stay
`needs-pair`. First Friend-MachineD freeze **1170.57×**
(2196 / 1.88 µs), ceiling 3000.0. Same commit no
optimize.

### Pair 56 — `cli_bootstrap_sessions`

| metric | cadr | pi |
|---|---|---|
| `coding_tools` | `make-coding-tools` | `createCodingTools` (`packages/coding-agent/src/core/tools/index.ts`) |

cwd `/tmp/proj`. Time construct the four baseline tools,
not a live session. Observed `count` / `baseline` /
`snippet_count` / `read_first` are exact (4 / 1 / 4 / 1).
Other bootstrap files stay `needs-pair`. First
Friend-MachineD freeze **2.40×** (11.1 / 4.6 µs), ceiling
8.0. Same commit no optimize.

### Pair 57 — `ai_runtime_faux`

| metric | cadr | pi |
|---|---|---|
| `blocks` | `faux-text` + `faux-thinking` | `fauxText` + `fauxThinking` (`packages/ai/src/providers/faux.ts`) |

Fixture `hello` / `hmm`. Time construct the two content
blocks, not a live faux stream. Observed `text_len` /
`text` / `think_len` / `think` are exact (5 / hello / 3 /
hmm). First Friend-MachineD freeze **1.76×** (0.27 /
0.15 µs), ceiling 8.0 (variance; sub-10 µs floor). Same
commit no optimize.

### Pair 58 — `http_transport`

| metric | cadr | pi |
|---|---|---|
| `parse_url` | `parse-http-url` | WHATWG `URL` |

Fixtures `https://example.com/foo` and
`http://localhost:8080/bar`. Time parse, no socket.
Observed `https_scheme` / `https_host` / `https_path` /
`http_scheme` / `http_host` / `http_port` / `http_path`
are exact (https / example.com / /foo / http /
localhost / 8080 / /bar). Do not exact default HTTPS
port (cadr 443 vs empty `URL.port`) or query-in-path
(cadr keeps `?` in path). First Friend-MachineD freeze
**0.99×** (1.16 / 1.17 µs), ceiling 8.0 (variance). Same
commit no optimize.

### Pair 59 — `cli_support` (normalize_path)

| metric | cadr | pi |
|---|---|---|
| `normalize_path` | `normalize-path-input` | `normalizePath` (`packages/coding-agent/src/utils/paths.ts`) |

Leftover sibling of `strip_ansi`. Fixtures: trim
`  /tmp/foo  `, `@rel` strip, unicode NBSP, `~/x` with
home `/tmp/home`, `file:///tmp/z`. Time normalize, no
TUI, no socket. Observed `trim` / `at` / `nbsp` /
`tilde` / `file` are exact. First Friend-MachineD freeze
**2.82×** (4.58 / 1.63 µs), ceiling 8.0. Same commit no
optimize.

### Pair 60 — `ai_support` (context_overflow)

| metric | cadr | pi |
|---|---|---|
| `context_overflow` | `context-overflow-p` | `isContextOverflow` (`packages/ai/src/utils/overflow.ts`) |

Leftover sibling of `estimate_text`. Fixtures: error
`prompt is too long` (1), error `rate limit` (0), stop
with input 100 / window 50 (1), length with output 0 /
input 100 / window 100 (1). Time classify, no socket.
Observed `prompt` / `rate` / `silent` / `length` are
exact. First Friend-MachineD freeze **1.67×** (1.85 /
1.11 µs), ceiling 8.0 (variance). Same commit no
optimize.

### Pair 61 — `ai_crypto` (hmac)

| metric | cadr | pi |
|---|---|---|
| `hmac` | `hmac-sha256` | `createHmac("sha256")` (`node:crypto`) |

Leftover sibling of `ai_crypto_model_data.manifest`.
Fixtures: RFC 4231 fox, empty message, 70-byte key.
Time HMAC hex, no socket. Observed `fox` / `empty` /
`long` are exact. Pure-Lisp SHA-256 vs OpenSSL.
First Friend-MachineD freeze **18.81×** (133.9 / 7.1 µs),
ceiling 30.0. Same commit no optimize.

### Pair 62 — `ai_support` (grammar_delta)

| metric | cadr | pi |
|---|---|---|
| `grammar_delta` | `append-grammar-json-delta` | `appendGrammarToolInputJsonDelta` (`packages/ai/src/api/constrained-sampling.ts`) |

Leftover sibling of `estimate_text` / `context_overflow`.
Fixtures: property `input`, `hel` → `hello` → close.
Observed `d1` / `d2` / `d3` / `started` / `closed` are
exact (`{"input":"hel` / `lo` / `"}` / 1 / 1). Time
delta assemble, no socket. First Friend-MachineD freeze
**2.87×** (1.52 / 0.53 µs), ceiling 8.0 (variance). Same
commit no optimize.

### Pair 63 — `image_runtime` (mime_type)

| metric | cadr | pi |
|---|---|---|
| `mime_type` | `detect-image-mime-type` | `detectSupportedImageMimeType` (`packages/coding-agent/src/utils/mime.ts`) |

Leftover sibling of `dimensions`. Fixtures: 1x1 PNG,
JPEG SOI `FF D8 FF E0`, `GIF89a`, `RIFF....WEBP`,
`hello` miss. Do not exact JPEG `0xf7`, animated PNG,
or invalid BMP (cadr prefix vs pi header checks).
Observed `png_mime` / `jpeg_mime` / `gif_mime` /
`webp_mime` / `miss_mime` are exact. Time sniff, no
Kitty/iTerm. First Friend-MachineD freeze **1.62×**
(6.63 / 4.09 µs), ceiling 8.0. Same commit no optimize.

### Pair 64 — `image_runtime` (lookup)

| metric | cadr | pi |
|---|---|---|
| `lookup` | `find-image-model` | `getImageModel` (`packages/ai/src/image-models.ts`) |

Leftover sibling of `dimensions` / `mime_type`. Catalog
presence for `google/gemini-2.5-flash-image` and
`black-forest-labs/flux.2-pro`; `nope` missing. Do not
exact catalog count. `models.lisp` stays
covered-as-callee. Observed `gemini` / `flux` /
`unknown` are exact (1 / 1 / 0). First Friend-MachineD
freeze **7.38×** (1.51 / 0.20 µs), ceiling 8.0
(variance). Same commit no optimize.

### Pair 65 — `image_runtime` (dimension_note)

| metric | cadr | pi |
|---|---|---|
| `dimension_note` | `format-image-dimension-note` | `formatDimensionNote` (`packages/coding-agent/src/utils/image-resize.ts`) |

Leftover sibling of `dimensions` / `mime_type` / `lookup`.
Synthetic resized 2000×1000→1000×500 (scale 2.00) and
1000×800→400×320 (scale 2.50); unresized 64×64 is empty.
Do not time decode/resize/Photon. Observed `note_resized`
/ `note_half` / `note_plain` are exact. First
Friend-MachineD freeze **1.73×** (3.67 / 2.12 µs),
ceiling 8.0. Same commit no optimize.

### Pair 66 — `image_runtime` (api_provider)

| metric | cadr | pi |
|---|---|---|
| `api_provider` | `get-images-api-provider` | `getImagesApiProvider` (`packages/ai/src/images-api-registry.ts`) |

Leftover sibling of `dimensions` / `mime_type` / `lookup`
/ `dimension_note`. Register fixture API
`:fixture-images` / `"fixture-images"`, then lookup
present vs `nope` missing. Do not exact builtin
openrouter-images (cadr product generate-images is
direct, not registry-backed at load). Observed
`api_fixture` / `api_unknown` are exact (1 / 0). First
Friend-MachineD freeze **1.09×** (0.23 / 0.21 µs),
ceiling 8.0 (variance). Same commit no optimize. No HTTP.

### Pair 67 — `cli_print_rpc` (jsonl_read)

| metric | cadr | pi |
|---|---|---|
| `jsonl_read` | `read-rpc-jsonl-lines` | `attachJsonlLineReader` (`packages/coding-agent/src/modes/rpc/jsonl.ts`) |

Leftover sibling of `jsonl_line`. Fixture
`{"id":"1"}\\n{"id":"2"}\\r\\nlast\\n` on a string
stream / Readable, not live stdin. CRLF second line
is trimmed. Observed `line_count` / `first` /
`second` / `last_line` are exact (3 /
`{"id":"1"}` / `{"id":"2"}` / `last`). First
Friend-MachineD freeze **0.03×** (0.63 / 23.84 µs),
ceiling 8.0. cadr leads (sync `read-line` vs async
Readable). Same commit no optimize.

### Pair 68 — `ai_support` (uuid_v7)

| metric | cadr | pi |
|---|---|---|
| `uuid_v7` | `uuid-v7` | `uuidv7` (`packages/ai/src/utils/uuid.ts`) |

Leftover sibling of estimate/overflow/grammar. Time
production UUID generation. Do not exact the hex
(entropy). Observed `uuid_len` / `uuid_hyphens` /
`uuid_version` / `uuid_variant` / `uuid_neq` are
exact (36 / 4 / 7 / 1 / 1). First Friend-MachineD
freeze **0.32×** (3.08 / 9.49 µs), ceiling 8.0.
cadr leads (entropy pool vs `getRandomValues`).
Same commit no optimize.

### Pair 69 — `ai_capabilities` (deferred_tools)

| metric | cadr | pi |
|---|---|---|
| `deferred_tools` | `split-deferred-tools` | `splitDeferredTools` (`packages/ai/src/utils/deferred-tools.ts`) |

Leftover sibling of `short_hash`. Fixture tools grep/bash/read;
assistant called bash; tool result added `read`. Disabled:
all immediate. Enabled: grep+bash immediate, read deferred.
Observed counts/names exact. First Friend-MachineD freeze
**2.04×** (5.51 / 2.70 µs), ceiling 8.0. Same commit no
optimize.

### Pair 70 — `ai_support` (auth_guidance)

| metric | cadr | pi |
|---|---|---|
| `auth_guidance` | `no-models-available-message` | `formatNoModelsAvailableMessage` (`packages/coding-agent/src/core/auth-guidance.ts`) |

Leftover sibling of estimate/overflow/grammar/uuid.
Prefixes only: `No models available.` / `No model
selected.` / `No API key found for openai.` / `No API
key found for the selected model.` Flags: Use /login,
providers.md, models.md. Do not exact docs paths
(cadr vs pi package dir). First Friend-MachineD freeze
**27.66×** (1922 / 69.5 µs), ceiling 50.0 (ASDF
docs-dir). Same commit no optimize.

### Pair 71 — `ai_capabilities` (event_stream)

| metric | cadr | pi |
|---|---|---|
| `event_stream` | `make-event-stream` | `EventStream` (`packages/ai/src/utils/event-stream.ts`) |

Leftover sibling of `short_hash` / `deferred_tools`. FIFO
`a`/`b`/`end`; complete on `end`. Observed `ev_first` /
`ev_second` / `ev_third` / `ev_result` are exact
(`a`/`b`/`end`/`end`). No live socket. First
Friend-MachineD freeze **1.44×** (1.73 / 1.20 µs),
ceiling 8.0 (variance). Same commit no optimize.

### Pair 72 — `cli_support` (timings)

| metric | cadr | pi |
|---|---|---|
| `timings` | `reset-timings` + `record-timing` + `print-timings` | `resetTimings` + `time` + `printTimings` (`packages/coding-agent/src/core/timings.ts`) |

Leftover sibling of `strip_ansi` / `normalize_path`. Enable
timing; fake clock +10 ms/step; reset `main`; record `boot`
then `load`; print. Observed `time_title` / `time_boot` /
`time_load` / `time_total` exact (`1` / `10` / `10` / `20`).
No TUI frame. First Friend-MachineD freeze **1.71×**
(4.55 / 2.66 µs), ceiling 8.0. Same commit no optimize.

### Pair 73 — `ai_capabilities` (http_proxy)

| metric | cadr | pi |
|---|---|---|
| `http_proxy` | `resolve-http-proxy-url-for-target` | `resolveHttpProxyUrlForTarget` (`packages/ai/src/utils/node-http-proxy.ts`) |

Leftover sibling of `short_hash` / `deferred_tools` / `event_stream`.
Fixture env maps (no live socket, no process-env leak):
HTTPS_PROXY hit / NO_PROXY `*` / host skip / host keep / SOCKS
error. Observed `px_hit` / `px_star` / `px_skip` / `px_keep`
exact strings; `px_socks` is the error flag. First
Friend-MachineD freeze **0.45×** (5.71 / 12.59 µs),
ceiling 8.0. cadr leads. Same commit no optimize.

### Pair 74 — `ai_capabilities` (session_resources)

| metric | cadr | pi |
|---|---|---|
| `session_resources` | `register-session-resource-cleanup` + `cleanup-session-resources` | `registerSessionResourceCleanup` + `cleanupSessionResources` (`packages/ai/src/session-resources.ts`) |

Leftover sibling of short_hash / deferred / event_stream / http_proxy.
Recorder cleanup `sess-1`; unregister; `sess-2` must not append;
thrower must error. Do not exact error text. No live socket. Do
not call cadr-only `clear-session-resource-cleanups`. First
Friend-MachineD freeze **0.16×** (1.41 / 9.04 µs), ceiling
8.0. cadr leads. Same commit no optimize.

### Pair 75 — `cli_support` (event_bus)

| metric | cadr | pi |
|---|---|---|
| `event_bus` | `make-event-bus` + `event-bus-on` + `event-bus-emit` | `createEventBus` (`packages/coding-agent/src/core/event-bus.ts`) |

Leftover sibling of strip_ansi / normalize_path / timings.
Recorder on `ch`; emit `a`; emit other channel; unsub; emit `c`
must not append; thrower swallowed; clear then emit `d` must
not append. Do not exact error text. No TUI. First
Friend-MachineD freeze **0.33×** (2.68 / 8.21 µs), ceiling
8.0. cadr leads. Same commit no optimize.

### Pair 76 — `cli_support` (attribution_headers)

| metric | cadr | pi |
|---|---|---|
| `attribution_headers` | `provider-attribution-headers` | `mergeProviderAttributionHeaders` (`packages/coding-agent/src/core/provider-attribution.ts`) |

Leftover sibling of strip_ansi / normalize_path / timings / event_bus.
OpenRouter / NVIDIA / Cloudflare / OpenCode URLs. Telemetry on/off.
Presence flags only for product strings (Referer, title, billing,
UA, client). Exact: Categories `cli-agent`, session `sess-1`,
overlay title `custom`. No live socket. First Friend-MachineD
freeze **0.29×** (2.70 / 9.31 µs), ceiling 8.0. cadr leads.
Same commit no optimize.

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
is not reflected in the booked denominator, when a prefix
matches nothing, or when `pairable-uncovered` lines are not 0.

Denominator: **295 files / 127,389 lines**
(same Part I lock: `src/**/*.lisp`, `wc -l`).

| class | files | lines | share of lines | Part K / P.13 |
|---|---:|---:|---:|---|
| `paired` | 129 | 59,438 | 46.7% | `no worse than baseline` is falsifiable |
| `unpairable` | 24 | 7,475 | 5.9% | single reference vs previous cadr |
| `covered-as-callee` | 19 | 12,919 | 10.1% | on a named paired thunk; no own bench |
| `needs-pair` | 123 | 47,557 | 37.3% | must get an H pair; not a file-level idle bench |
| `pairable-uncovered` | 0 | 0 | 0.0% | P.13 requires 0% |

- **Falsifiable vs baseline:** 46.7% of lines (129 files). This is the share whose `no worse than baseline` claim is a measured pair.
- **K-advanceable** (paired ∪ unpairable): 52.5% of lines.
- **P.13 `pairable-uncovered`:** 0.0% of lines (must be 0%). Remaining pairable work is `needs-pair`, not unlabeled.

H does not require the paired ratios to be ≤ 1.0×; that is Part O / P.13 floor.

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
**not** unpairable: they own `sqlite_session.open_walk`.

### 6.2 Currently paired owners

A file is `paired` when a live Part H or Goal 11 thunk names it as
production work, not merely as a transitive callee.

| file | lines | metrics |
|---|---:|---|
| `src/cadr-agent/compaction.lisp` | 883 | `session_compact.compact` |
| `src/cadr-agent/loop/agent-loop.lisp` | 442 | `agent_tool_loop.roundtrip` |
| `src/cadr-agent/loop/events.lisp` | 169 | `agent_tool_loop.roundtrip` |
| `src/cadr-agent/loop/tool-execution.lisp` | 489 | `agent_tool_loop.roundtrip` |
| `src/cadr-agent/loop/turns.lisp` | 393 | `agent_tool_loop.roundtrip` |
| `src/cadr-agent/messages.lisp` | 253 | `session_compact.compact` |
| `src/cadr-agent/proxy.lisp` | 251 | `agent_proxy.stream_roundtrip` |
| `src/cadr-agent/resources.lisp` | 739 | `resource_loader.reload` |
| `src/cadr-agent/schema.lisp` | 850 | `agent_schema.validate_ok_fail` |
| `src/cadr-agent/session/codec.lisp` | 1,152 | `storage_journal.journal_read`, `storage_journal.journal_append` |
| `src/cadr-agent/session/discovery.lisp` | 154 | `session_discovery.header_probe` |
| `src/cadr-agent/session/export-html.lisp` | 455 | `session_export_html.to_html` |
| `src/cadr-agent/session/journal.lisp` | 679 | `session_pipeline.context_walk`, `storage_journal.journal_append` |
| `src/cadr-agent/session/migration.lisp` | 2,434 | `session_pipeline.session_load`, `storage_journal.journal_read` |
| `src/cadr-agent/sqlite-storage.lisp` | 839 | `sqlite_session.open_walk` |
| `src/cadr-agent/storage/harness.lisp` | 476 | `harness_storage.open_walk` |
| `src/cadr-agent/storage/jsonl.lisp` | 536 | `harness_storage.open_walk` |
| `src/cadr-agent/storage/memory.lisp` | 378 | `harness_storage.open_walk` |
| `src/cadr-agent/storage/protocol.lisp` | 142 | `harness_storage.open_walk` |
| `src/cadr-agent/summarization.lisp` | 86 | `session_compact.compact` |
| `src/cadr-agent/tool.lisp` | 319 | `agent_tool_loop.roundtrip` |
| `src/cadr-agent/truncate.lisp` | 554 | `text_truncation.truncate_head`, `text_truncation.truncate_tail` |
| `src/cadr-ai/auth/bedrock.lisp` | 220 | `provider_bedrock.stream_roundtrip` |
| `src/cadr-ai/auth/vertex.lisp` | 212 | `provider_vertex.stream_roundtrip` |
| `src/cadr-ai/capabilities/event-stream.lisp` | 69 | `ai_capabilities.event_stream` |
| `src/cadr-ai/capabilities/grammar-tools.lisp` | 292 | `ai_capabilities.deferred_tools` |
| `src/cadr-ai/capabilities/image-runtime.lisp` | 117 | `image_runtime.api_provider` |
| `src/cadr-ai/capabilities/proxy-config.lisp` | 77 | `ai_capabilities.http_proxy` |
| `src/cadr-ai/capabilities/session-resources.lisp` | 34 | `ai_capabilities.session_resources` |
| `src/cadr-ai/capabilities/streaming-json.lisp` | 162 | `ai_capabilities.short_hash` |
| `src/cadr-ai/crypto.lisp` | 367 | `ai_crypto.hmac` |
| `src/cadr-ai/image-models.generated.lisp` | 185 | `image_runtime.lookup` |
| `src/cadr-ai/json.lisp` | 1,920 | `provider_stream.stream_roundtrip`, `storage_journal.journal_read`, `storage_journal.journal_append`, `session_pipeline.session_load` |
| `src/cadr-ai/model-data.lisp` | 407 | `ai_crypto_model_data.manifest` |
| `src/cadr-ai/oauth/pkce.lisp` | 322 | `oauth_pkce.challenge_urls` |
| `src/cadr-ai/provider.lisp` | 799 | `provider_stream.stream_roundtrip` |
| `src/cadr-ai/providers/anthropic.lisp` | 644 | `provider_anthropic.stream_roundtrip` |
| `src/cadr-ai/providers/azure-openai.lisp` | 223 | `provider_azure_openai.stream_roundtrip` |
| `src/cadr-ai/providers/bedrock.lisp` | 934 | `provider_bedrock.stream_roundtrip` |
| `src/cadr-ai/providers/codex.lisp` | 35 | `provider_codex.stream_roundtrip` |
| `src/cadr-ai/providers/definitions.lisp` | 1,040 | `provider_registry_defs.lookup` |
| `src/cadr-ai/providers/google.lisp` | 442 | `provider_google.stream_roundtrip` |
| `src/cadr-ai/providers/mistral.lisp` | 97 | `provider_mistral.stream_roundtrip` |
| `src/cadr-ai/providers/openai-completions.lisp` | 880 | `provider_stream.stream_roundtrip` |
| `src/cadr-ai/providers/openai.lisp` | 828 | `provider_openai_responses.stream_roundtrip` |
| `src/cadr-ai/providers/pi-messages.lisp` | 255 | `provider_pi_messages.stream_roundtrip` |
| `src/cadr-ai/providers/vertex.lisp` | 134 | `provider_vertex.stream_roundtrip` |
| `src/cadr-ai/runtime/faux-provider.lisp` | 601 | `ai_runtime_faux.blocks` |
| `src/cadr-ai/sse.lisp` | 267 | `provider_stream.stream_roundtrip` |
| `src/cadr-ai/support/grammar-coercion.lisp` | 279 | `ai_support.grammar_delta` |
| `src/cadr-ai/support/overflow.lisp` | 78 | `ai_support.context_overflow` |
| `src/cadr-ai/support/release.lisp` | 104 | `ai_support.auth_guidance` |
| `src/cadr-ai/support/token-estimation.lisp` | 170 | `ai_support.estimate_text` |
| `src/cadr-ai/support/uuid.lisp` | 93 | `ai_support.uuid_v7` |
| `src/cadr-ai/transport/aws-event-stream.lisp` | 222 | `provider_bedrock.stream_roundtrip` |
| `src/cadr-ai/transport/http.lisp` | 858 | `http_transport.parse_url` |
| `src/cadr-cli/arguments.lisp` | 1,036 | `cli_dispatch.argv_parse`, `cli_dispatch.help_render` |
| `src/cadr-cli/bootstrap/main.lisp` | 409 | `cli_dispatch.list_models_render` |
| `src/cadr-cli/bootstrap/tools.lisp` | 89 | `cli_bootstrap_sessions.coding_tools` |
| `src/cadr-cli/interactive/entries.lisp` | 918 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-cli/interactive/frame.lisp` | 232 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-cli/interactive/images.lisp` | 290 | `image_runtime.dimension_note` |
| `src/cadr-cli/interactive/state.lisp` | 303 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-cli/interactive/status.lisp` | 445 | `goal11.continuous_alt_input` |
| `src/cadr-cli/interactive/syntax.lisp` | 1,089 | `cli_interactive_controller.decode_entity` |
| `src/cadr-cli/interactive/tool-rendering.lisp` | 1,015 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-cli/media.lisp` | 1,277 | `image_runtime.mime_type` |
| `src/cadr-cli/models/matching.lisp` | 398 | `cli_models_rest.pattern_match` |
| `src/cadr-cli/models/registry.lisp` | 846 | `cli_dispatch.list_models_registry` |
| `src/cadr-cli/models/store.lisp` | 197 | `cli_dispatch.list_models_registry` |
| `src/cadr-cli/modes/print.lisp` | 578 | `cli_print_rpc.jsonl_line` |
| `src/cadr-cli/modes/rpc/jsonl.lisp` | 123 | `cli_print_rpc.jsonl_read` |
| `src/cadr-cli/packages/commands.lisp` | 764 | `package_manager.resolve` |
| `src/cadr-cli/packages/manifest.lisp` | 142 | `package_manager.resolve` |
| `src/cadr-cli/packages/settings.lisp` | 214 | `package_manager.resolve` |
| `src/cadr-cli/packages/source.lisp` | 338 | `package_manager.resolve` |
| `src/cadr-cli/resource-loader.lisp` | 353 | `resource_loader.reload` |
| `src/cadr-cli/sdk/cache-version.lisp` | 498 | `cli_sdk.version_newer` |
| `src/cadr-cli/sdk/system-prompt.lisp` | 218 | `skill_prompt_load.build_prompt` |
| `src/cadr-cli/settings/config-values.lisp` | 198 | `cli_settings.create` |
| `src/cadr-cli/settings/manager.lisp` | 512 | `cli_settings.create` |
| `src/cadr-cli/support/changelog-share.lisp` | 342 | `cli_support.strip_ansi` |
| `src/cadr-cli/support/event-bus.lisp` | 40 | `cli_support.event_bus` |
| `src/cadr-cli/support/headers.lisp` | 75 | `cli_support.attribution_headers` |
| `src/cadr-cli/support/paths.lisp` | 119 | `cli_support.normalize_path` |
| `src/cadr-cli/support/timings.lisp` | 45 | `cli_support.timings` |
| `src/cadr-cli/tools/grep.lisp` | 331 | `tool_grep.context_file` |
| `src/cadr-cli/tools/read.lisp` | 192 | `tool_read.text_file` |
| `src/cadr-cli/truncation.lisp` | 235 | `tool_read.text_file` |
| `src/cadr-evals/summary.lisp` | 732 | `evals_harness.summarize` |
| `src/cadr-protocol/cbor.lisp` | 492 | `protocol_cbor.roundtrip` |
| `src/cadr-protocol/codec.lisp` | 121 | `protocol_codec.roundtrip` |
| `src/cadr-protocol/framing.lisp` | 170 | `protocol_codec.roundtrip` |
| `src/cadr-protocol/schema.lisp` | 610 | `protocol_codec.roundtrip` |
| `src/cadr-storage/package.lisp` | 19 | `sqlite_session.open_walk` |
| `src/cadr-storage/sqlite.lisp` | 12 | `sqlite_session.open_walk` |
| `src/cadr-tui/autocomplete.lisp` | 594 | `tui_autocomplete.suggest_apply` |
| `src/cadr-tui/components/image.lisp` | 40 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/components/markdown.lisp` | 1,553 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/components/select-list.lisp` | 305 | `tui_select_settings_loaders.filter` |
| `src/cadr-tui/components/tool-block.lisp` | 623 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/composition/protocol.lisp` | 143 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/composition/rich-content.lisp` | 276 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/composition/root.lisp` | 317 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/composition/settings-list.lisp` | 470 | `tui_settings_list.apply_filter` |
| `src/cadr-tui/composition/text-box.lisp` | 280 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/editor.lisp` | 2,014 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/fuzzy.lisp` | 134 | `tui_editor_helpers.fuzzy_match` |
| `src/cadr-tui/input-component.lisp` | 408 | `tui_input_component.edit` |
| `src/cadr-tui/input.lisp` | 333 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/keybindings.lisp` | 268 | `tui_keybindings.resolve_match` |
| `src/cadr-tui/keys.lisp` | 606 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/kill-ring.lisp` | 38 | `tui_kill_ring.push_peek` |
| `src/cadr-tui/latex.lisp` | 1,950 | `tui_latex.render` |
| `src/cadr-tui/native-modifiers.lisp` | 78 | `tui_native_modifiers.pressed` |
| `src/cadr-tui/overlay.lisp` | 485 | `tui_overlay.composite_line` |
| `src/cadr-tui/renderer/alt-screen-search.lisp` | 181 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/renderer/alt-screen.lisp` | 610 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/renderer/lifecycle-input.lisp` | 1,353 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/renderer/main-screen.lisp` | 595 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/renderer/terminal-protocol.lisp` | 78 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/renderer/virtual-terminal.lisp` | 184 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/stdin-buffer.lisp` | 232 | `tui_stdin_buffer.process` |
| `src/cadr-tui/terminal-colors.lisp` | 191 | `tui_theme_overlay.osc11_bg` |
| `src/cadr-tui/terminal-image.lisp` | 686 | `image_runtime.dimensions` |
| `src/cadr-tui/terminal.lisp` | 916 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/undo-stack.lisp` | 20 | `tui_undo_stack.push_pop` |
| `src/cadr-tui/unicode.lisp` | 1,302 | `render_slicing.slice_ansi_clip`, `render_slicing.slice_plain_clip` |
| `src/cadr-tui/word-navigation.lisp` | 118 | `tui_word_navigation.step` |

### 6.3 Covered as callee

On a named paired thunk. No own bench (G.12).

| file | lines | parent metrics |
|---|---:|---|
| `src/cadr-agent/package.lisp` | 456 | `session_pipeline.session_load`, `session_pipeline.context_walk`, `storage_journal.journal_read`, `storage_journal.journal_append` |
| `src/cadr-ai/conditions.lisp` | 44 | `provider_stream.stream_roundtrip`, `cli_dispatch.list_models_registry` |
| `src/cadr-ai/models.generated.lisp` | 8,711 | `cli_dispatch.list_models_registry` |
| `src/cadr-ai/models.lisp` | 288 | `cli_dispatch.list_models_registry` |
| `src/cadr-ai/package.lisp` | 480 | `provider_stream.stream_roundtrip`, `session_pipeline.session_load`, `cli_dispatch.list_models_registry` |
| `src/cadr-ai/runtime/models.lisp` | 809 | `cli_dispatch.list_models_registry` |
| `src/cadr-ai/support/retry.lisp` | 178 | `provider_stream.stream_roundtrip` |
| `src/cadr-ai/types.lisp` | 207 | `provider_stream.stream_roundtrip`, `session_pipeline.session_load` |
| `src/cadr-cli/interactive/pending-messages.lisp` | 63 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-cli/models/auth-storage.lisp` | 376 | `cli_dispatch.list_models_registry` |
| `src/cadr-cli/package.lisp` | 289 | `cli_dispatch.argv_parse`, `cli_dispatch.help_render`, `cli_dispatch.list_models_registry`, `cli_dispatch.list_models_render`, `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-core/package.lisp` | 43 | `session_pipeline.session_load`, `cli_dispatch.list_models_registry` |
| `src/cadr-core/paths.lisp` | 95 | `cli_dispatch.list_models_registry` |
| `src/cadr-core/time.lisp` | 133 | `session_pipeline.session_load`, `storage_journal.journal_read` |
| `src/cadr-evals/package.lisp` | 100 | `evals_harness.summarize` |
| `src/cadr-protocol/package.lisp` | 33 | `protocol_cbor.roundtrip`, `protocol_codec.roundtrip` |
| `src/cadr-tui/components/status.lisp` | 253 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/package.lisp` | 355 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input`, `render_slicing.slice_ansi_clip`, `render_slicing.slice_plain_clip` |
| `src/cadr-tui/threads.lisp` | 6 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |

### 6.4 Needs an H pair

Same-path baseline counterpart, not on an existing timed stack.
Grouped by hole. Do not invent a file-level idle bench.

| hole | files | lines |
|---|---:|---:|
| `cli_selectors` | 14 | 7,982 |
| `cli_interactive_controller` | 10 | 6,955 |
| `cli_bootstrap_sessions` | 5 | 5,339 |
| `tui_mermaid` | 12 | 5,042 |
| `agent_tool_loop` | 13 | 4,094 |
| `cli_extensions_install` | 9 | 3,489 |
| `evals_harness` | 6 | 2,184 |
| `oauth_pkce_device` | 13 | 2,081 |
| `package_manager` | 2 | 1,811 |
| `cli_print_rpc` | 6 | 1,601 |
| `settings_load` | 4 | 1,499 |
| `cli_sdk` | 4 | 1,214 |
| `cli_models_rest` | 2 | 698 |
| `websocket_stream` | 1 | 628 |
| `tui_theme_overlay` | 1 | 562 |
| `cli_support` | 8 | 543 |
| `provider_registry_defs` | 2 | 454 |
| `skill_prompt_load` | 2 | 423 |
| `core_rest` | 4 | 267 |
| `tui_select_settings_loaders` | 1 | 235 |
| `image_runtime` | 1 | 222 |
| `session_compact` | 1 | 185 |
| `agent_conditions` | 1 | 43 |
| `ai_support` | 1 | 6 |

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
