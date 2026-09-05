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
| `session_leaf_id` | `session-leaf-id` (`src/cadr-agent/session/codec.lisp`) | `SessionManager.getLeafId` (same file) |

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
| `journal_entry_count` | `session-entry-count` (`src/cadr-agent/session/journal.lisp`) | `SessionManager.getEntries().length` (`packages/coding-agent/src/core/session-manager.ts`) |

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
| `manifest_parse` | `read-package-pi-manifest` (`src/cadr-cli/packages/manifest.lisp`) | `readPiManifest` (`packages/coding-agent/src/core/pi-manifest.ts`) |

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

### Pair 424 — `tui_stdin_buffer` (flush)

| metric | cadr | pi |
|---|---|---|
| `flush` | `stdin-buffer-flush` (`src/cadr-tui/stdin-buffer.lisp`) | `StdinBuffer.flush` (`packages/tui/src/stdin-buffer.ts`) |

Leftover sibling of Pair 46 `process` on the same `stdin-buffer.lisp` file.
Timed work is empty flush plus incomplete CSI `ESC[` flush — not `process`.
Observed `fl_empty` / `fl_before` / `fl_n` / `fl_seq` / `fl_after` are
exact (0 / 2 / 1 / 2 / 0). First n=5 freeze **0.139×** (0.392 / 2.818 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Same commit no optimize.

### Pair 425 — `tui_stdin_buffer` (clear)

| metric | cadr | pi |
|---|---|---|
| `clear` | `stdin-buffer-clear` (`src/cadr-tui/stdin-buffer.lisp`) | `StdinBuffer.clear` (`packages/tui/src/stdin-buffer.ts`) |

Leftover sibling of Pairs 46/424 on the same `stdin-buffer.lisp` file.
Timed work is leftover CSI then `clear` then `hello` — not `process`.
Observed `cl_before` / `cl_after` / `cl_hello` / `cl_final` are exact
(2 / 0 / 5 / 0). First n=5 freeze **0.172×** (0.710 / 4.129 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Same commit no optimize.

### Pair 426 — `tui_stdin_buffer` (contents)

| metric | cadr | pi |
|---|---|---|
| `contents` | `stdin-buffer-contents` (`src/cadr-tui/stdin-buffer.lisp`) | `StdinBuffer.getBuffer` (`packages/tui/src/stdin-buffer.ts`) |

Leftover sibling of Pairs 46/424–425 on the same `stdin-buffer.lisp` file.
Timed work is empty / incomplete CSI / complete `A` / leftover peek — not
`process`. Observed `ct_empty` / `ct_csi` / `ct_done` / `ct_again` / `ct_n`
are exact (0 / 2 / 0 / 2 / 4). First n=5 freeze **0.155×** (0.715 / 4.615 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Same commit no optimize.

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

### Pair 77 — `cli_support` (shell_config)

| metric | cadr | pi |
|---|---|---|
| `shell_config` | `get-shell-config` | `getShellConfig` (`packages/coding-agent/src/utils/shell.ts`) |

Leftover sibling of strip_ansi / timings / event_bus / attribution.
Default + custom `/bin/bash` → shell `/bin/bash`, arg `-c`, no
stdin transport. Missing custom path errors. No live process.
First Friend-MachineD freeze **2.47×** (21.07 / 8.54 µs),
ceiling 8.0. Same commit no optimize.

### Pair 78 — `cli_support` (sanitize_output)

| metric | cadr | pi |
|---|---|---|
| `sanitize_output` | `sanitize-binary-output` | `sanitizeBinaryOutput` (`packages/coding-agent/src/utils/shell.ts`) |

Leftover sibling of `shell_config` in the same file. hello;
NUL+BEL stripped; tab/LF/CR kept; U+FFF9 stripped; ESC
stripped. Do not exact lone surrogates. No live process.
First Friend-MachineD freeze **0.91×** (1.26 / 1.39 µs),
ceiling 8.0 (variance). cadr leads. Same commit no optimize.

### Pair 79 — `cli_support` (git_source)

| metric | cadr | pi |
|---|---|---|
| `git_source` | `parse-git-source` | `parseGitUrl` (`packages/coding-agent/src/utils/git.ts`) |

Leftover sibling in `resume-version-git.lisp`. HTTPS+ref,
`git:` scp, `git:` shorthand. Reject bare scp / traversal /
absolute. Host/path/ref/pinned only — do not exact repo.
Skipped `edit-in-external-editor` (pi spawn). First
Friend-MachineD freeze **0.48×** (26.85 / 55.99 µs),
ceiling 8.0. cadr leads. Same commit no optimize.

### Pair 80 — `cli_support` (user_agent)

| metric | cadr | pi |
|---|---|---|
| `user_agent` | `cadr-user-agent` | `getPiUserAgent` (`packages/coding-agent/src/utils/pi-user-agent.ts`) |

Leftover sibling of `git_source` in the same file. Version
`1.2.3`; observe version substring, parens, semicolon
count=2. Do not exact product (`cadr` vs `pi`) or runtime
(`sbcl` vs `node`). First Friend-MachineD freeze **3.14×**
(1.41 / 0.45 µs), ceiling 8.0 (variance). Same commit no
optimize.

### Pair 81 — `cli_support` (parse_changelog)

| metric | cadr | pi |
|---|---|---|
| `parse_changelog` | `parse-changelog` | `parseChangelog` (`packages/coding-agent/src/utils/changelog.ts`) |

Leftover sibling of `strip_ansi` in `changelog-share.lisp`.
Fixture CHANGELOG with `0.2.0` / malformed / `0.1.0`; missing
file empty. Count, version strings, first-header flag. Do not
exact product URLs (`normalize-changelog-links` skipped). First
Friend-MachineD freeze **2.96×** (36.04 / 12.20 µs), ceiling
8.0. Same commit no optimize.

### Pair 82 — `cli_models_rest` (auth_command)

| metric | cadr | pi |
|---|---|---|
| `auth_command` | `parse-auth-command` | `parseAuthCommand` (`packages/coding-agent/src/cli/auth-command.ts`) |

Leftover sibling of `pattern_match`. Argv only: skip non-auth;
api-key + `--provider openai`; bearer `--min-expiry 30m` =
1800000; check json/credentials/no-refresh. Errors on
min-expiry-on-api and unknown. Help via `isAuthCommandHelp`,
not through `parseAuthCommand` (cadr returns help-p; pi
throws). Do not exact product usage or error text. No live
auth. First Friend-MachineD freeze **0.47×** (3.56 / 7.54 µs),
ceiling 8.0. cadr leads. Same commit no optimize.

### Pair 83 — `cli_sdk` (cache_miss)

| metric | cadr | pi |
|---|---|---|
| `cache_miss` | `detect-cache-miss` | `detectCacheMiss` (`packages/coding-agent/src/core/cache-stats.ts`) |

Leftover sibling of `version_newer` in `cache-version.lisp`.
In-memory assistant usage (write 100k / read 100k then full
miss 110k write). Tokens 105000, idle 540000, model-switch
flag. Healthy and first-turn empty. Do not exact missed-cost
float. No live session. First Friend-MachineD freeze **0.55×**
(2.29 / 4.13 µs), ceiling 8.0. cadr leads. Same commit no
optimize.

### Pair 84 — `cli_sdk` (cache_waste)

| metric | cadr | pi |
|---|---|---|
| `cache_waste` | `compute-cache-waste` | `computeCacheWaste` (`packages/coding-agent/src/core/cache-stats.ts`) |

Leftover sibling of `cache_miss` in the same file. Session
scan: 3-turn miss 105000 tokens; healthy 0; compaction skip;
model-switch 100000 / count 1; no-cache-activity 0. Do not
exact missed-cost float. First Friend-MachineD freeze
**0.60×** (3.96 / 6.56 µs), ceiling 8.0. cadr leads. Same
commit no optimize.

### Pair 85 — `cli_sdk` (thinking_level)

| metric | cadr | pi |
|---|---|---|
| `thinking_level` | `valid-thinking-level-p` | `isValidThinkingLevel` (`packages/coding-agent/src/cli/args.ts`) |

Leftover sibling in `cache-version.lisp`. Lowercase
off/minimal/low/medium/high/xhigh/max + miss. Do not exact
uppercase (cadr downcases; pi is case-sensitive). First
Friend-MachineD freeze **3.21×** (0.72 / 0.22 µs), ceiling
8.0 (variance). Same commit no optimize.

### Pair 86 — `settings_load` (project_trust)

| metric | cadr | pi |
|---|---|---|
| `project_trust` | `resolve-project-trusted` | `resolveProjectTrusted` (`packages/coding-agent/src/core/project-trust.ts`) |

Independent named metric for the `settings_load` hole
(not a `cli_sdk` leftover). Empty cwd vs cwd with both
`.cadr/settings.json` and `.pi/settings.json`. Resolve:
empty/ask/always/never + override yes/no. No UI, no
extension host, no socket. First Friend-MachineD freeze
**0.24×** (330.6 / 1402.9 µs), ceiling 8.0. cadr leads.
Same commit no optimize.

### Pair 87 — `oauth_pkce_device` (poll)

| metric | cadr | pi |
|---|---|---|
| `poll` | `poll-device-authorization` | `pollOAuthDeviceCodeFlow` (`packages/ai/src/auth/oauth/device-code.ts`) |

Independent named metric for the `oauth_pkce_device` hole.
Injected poll + noop sleep + frozen clock. Complete `"tok"`;
failed throws; cancelled/aborted throws. No socket. Do not
exact error text. First Friend-MachineD freeze **0.09×**
(1.01 / 11.51 µs), ceiling 8.0. cadr leads. Same commit no
optimize.

### Pair 88 — `oauth_pkce_device` (radius_gateway)

| metric | cadr | pi |
|---|---|---|
| `radius_gateway` | `normalize-radius-gateway` | `normalizeRadiusGatewayUrl` (`packages/ai/src/providers/radius-config.ts`) |

Leftover sibling of the `oauth_pkce_device` hole. Already-schemed
URLs only: trailing slash / no slash / `http://localhost`. Do not
exact a bare host without a scheme (pi prepends `https://`; cadr
only right-trims `/`). No socket. First Friend-MachineD freeze
**1.05×** (0.57 / 0.54 µs), ceiling 8.0 (variance). Same commit
no optimize.

### Pair 89 — `cli_interactive_controller` (wayland)

| metric | cadr | pi |
|---|---|---|
| `wayland` | `clipboard-wayland-p` | `isWaylandSession` (`packages/coding-agent/src/utils/clipboard-image.ts`) |

Leftover sibling of the `cli_interactive_controller` hole.
Injected env: `WAYLAND_DISPLAY=wayland-0` / `XDG_SESSION_TYPE=wayland`
/ `x11` / dummy `FOO`. Do not exact empty `WAYLAND_DISPLAY` (Lisp
non-empty vs JS `Boolean("")`) or mixed-case session type
(`string-equal` vs `=== "wayland"`). Dummy alist, not NIL (NIL
falls through to live getenv). No TUI, no clipboard spawn. First
Friend-MachineD freeze **1.17×** (0.36 / 0.30 µs), ceiling 8.0
(variance). Same commit no optimize.

### Pair 90 — `evals_harness` (group_key)

| metric | cadr | pi |
|---|---|---|
| `group_key` | `derive-eval-group-key` | `deriveEvalGroupKey` (`packages/evals/src/vitest-evals/harness-table.ts`) |

Leftover sibling of the `evals_harness` hole. id-bearing inputs
only (`case-1`, trimmed `case-2`). Do not exact a no-id SHA path
(cadr stringify vs pi canonicalizeJson) or repetition 0 (cadr
errors, pi stringifies). Artifact parse: schema 1 ok / schema 2
nil. No live eval run. First Friend-MachineD freeze **4.06×**
(5.01 / 1.23 µs), ceiling 8.0 (variance). Same commit no
optimize.

### Pair 91 — `cli_extensions_install` (llama_catalog)

| metric | cadr | pi |
|---|---|---|
| `llama_catalog` | `llama-provider-set-catalog` | `createLlamaProvider().setCatalog` (`packages/coding-agent/src/extensions/llama/provider.ts`) |

Leftover sibling of the `cli_extensions_install` hole. Loaded
text/image + fallback ctx + sleeping/unloaded. Count 3 loaded;
image input; ctx 4096; `/v1` base URL; sleeping excluded;
missing ctx → 128000. No socket, no TUI. First Friend-MachineD
freeze **0.36×** (4.78 / 13.41 µs), ceiling 8.0. cadr leads.
Same commit no optimize.

### Pair 92 — `cli_interactive_controller` (cwd_footer)

| metric | cadr | pi |
|---|---|---|
| `cwd_footer` | `format-cwd-for-footer` | `formatCwdForFooter` (`packages/coding-agent/src/modes/interactive/components/footer.ts`) |

Leftover sibling of the `cli_interactive_controller` hole.
POSIX home / `~/proj` / outside `/tmp` / trailing slashes. Do not
exact a missing home (cadr still trims; pi returns cwd) or Windows
separators. No TUI. First Friend-MachineD freeze **0.34×**
(0.78 / 2.31 µs), ceiling 8.0. cadr leads. Same commit no
optimize.

### Pair 93 — `cli_sdk` (agent_session)

| metric | cadr | pi |
|---|---|---|
| `agent_session` | `create-agent-session` | `createAgentSession` (`packages/coding-agent/src/core/sdk.ts`) |

Independent named metric for the remaining `cli_sdk` agent-session
file. Isolated cwd/agentDir, in-memory session, explicit dummy
model, `no-tools :all` / `noTools: "all"`. Do not exact fallback
copy or thinking-level default. Dispose after each sample. No
socket, no TUI. First Friend-MachineD freeze **0.36×**
(3151 / 8769 µs), ceiling 8.0. cadr leads. Same commit no
optimize.

### Pair 94 — `cli_sdk` (session_services)

| metric | cadr | pi |
|---|---|---|
| `session_services` | `create-agent-session-services` | `createAgentSessionServices` (`packages/coding-agent/src/core/agent-session-services.ts`) |

Independent named metric for `session-runtime.lisp`. Isolated
cwd/agentDir, memory settings, empty auth/models. Do not exact
diagnostics (pi also `refresh({allowNetwork:false})`). No socket.
First Friend-MachineD freeze **0.24×** (2306 / 9493 µs), ceiling
8.0. cadr leads. Same commit no optimize.

### Pair 95 — `cli_sdk` (model_runtime)

| metric | cadr | pi |
|---|---|---|
| `model_runtime` | `sdk-model-runtime-providers` + `sdk-model-runtime-model` | `ModelRuntime.getProviders` + `getModel` (`packages/coding-agent/src/core/model-runtime.ts`) |

Independent named metric for `model-service.lisp`. Isolated empty
auth/models. openai/anthropic present; unknown provider/model
absent; `gpt-4o-mini` present. Do not exact provider count (cadr
40 vs pi 39). No socket. First Friend-MachineD freeze **0.58×**
(2243 / 3858 µs), ceiling 8.0. cadr leads. Same commit no
optimize.

### Pair 96 — `cli_print_rpc` (session_stats)

| metric | cadr | pi |
|---|---|---|
| `session_stats` | `rpc-session-stats` | `AgentSession.getSessionStats` (`packages/coding-agent/src/core/agent-session.ts`) |

Leftover sibling of the `cli_print_rpc` hole. Fixture
`session.jsonl` (119 user / 240 assistant / 120 toolResult /
120 toolCalls). Load in collect prepare; time the stats fold
only. Observed `ss_user` / `ss_asst` / `ss_tool` / `ss_calls` /
`ss_total` / `ss_id` are exact. Do not exact tokens, cost,
sessionFile, or contextUsage (pi also folds compaction /
branch_summary usage). No socket, no TUI. First Friend-MachineD
freeze **0.19×** (13.16 / 70.76 µs), ceiling 8.0. cadr leads.
Same commit no optimize.

### Pair 97 — `oauth_pkce_device` (copilot_auth)

| metric | cadr | pi |
|---|---|---|
| `copilot_auth` | `github-copilot-oauth-to-auth` | `githubCopilotOAuth.toAuth` (`packages/ai/src/auth/oauth/github-copilot.ts`) |

Leftover sibling of the `oauth_pkce_device` hole. Same four
Copilot credential cases as `copilot_url` plus api-key identity.
Observed `ga_def` / `ga_ind` / `ga_ent` / `ga_dom` / `ga_key`
are exact. Do not exact source/type (cadr sets `OAuth` / `:oauth`;
pi `toAuth` omits them). No socket. First Friend-MachineD freeze
**1.35×** (3.21 / 2.38 µs), ceiling 8.0. Same commit no
optimize.

### Pair 98 — `tui_mermaid` (render)

| metric | cadr | pi |
|---|---|---|
| `render` | `gm-render` | `render` (`grok-mermaid` / `packages/coding-agent/src/modes/interactive/components/mermaid.ts`) |

Independent named metric for the `tui_mermaid` hole. FiveAM
reference snippets: flowchart LR `A-->B`, empty, `notadiagram`,
CJK flowchart. Time parse+layout+Unicode art, not a TUI frame
and not live mermaid play. Observed `mm_lr_w` / `mm_lr_first` /
`mm_lr_rows` / `mm_empty` / `mm_unk` / `mm_cjk_w` are exact
(14 / box row / 3 / 1 / 1 / 24). `source-box.lisp` /
`transform.lisp` / `ansi.lisp` stay `needs-pair`. First
Friend-MachineD freeze **0.30×** (75.31 / 255.24 µs), ceiling
8.0. cadr leads. Same commit no optimize.

### Pair 99 — `tui_mermaid` (source_box)

| metric | cadr | pi |
|---|---|---|
| `source_box` | `gm-source-box` | `sourceBox` (`grok-mermaid` dist/source-box.js) |

Leftover sibling of the `tui_mermaid` hole. Flowchart LR
`A-->B` at max-width 80 and 12, plus empty source. Time the
framed source box, not a TUI frame. Observed `sb_wide_w` /
`sb_wide_first` / `sb_narrow_rows` / `sb_empty_w` are exact
(24 / titled header / 5 / 22). `transform.lisp` / `ansi.lisp`
stay `needs-pair`. First Friend-MachineD freeze **0.38×**
(58.73 / 155.58 µs), ceiling 8.0. cadr leads. Same commit no
optimize.

### Pair 100 — `tui_mermaid` (transform)

| metric | cadr | pi |
|---|---|---|
| `transform` | `transform-mermaid-markdown` | `createMermaidMarkdownTransformer` (`packages/coding-agent/src/modes/interactive/components/mermaid.ts`) |

Leftover sibling of the `tui_mermaid` hole. Markdown in/out,
no TUI frame. Fenced flowchart LR; mode `off`;
`assistant-thinking`; `availableWidth` 5 (too wide, silent
raw). Unstyled (`theme-p` nil / no theme). Observed `tf_ok` /
`tf_art` / `tf_off` / `tf_think` / `tf_wide` / `tf_len` are
exact (1 / 1 / 1 / 1 / 1 / 55). `ansi.lisp` stays `needs-pair`
(no Lisp `toAnsi`; grok-mermaid convenience unused). First
Friend-MachineD freeze **0.65×** (69.67 / 107.87 µs), ceiling
8.0. cadr leads. Same commit no optimize.

### Pair 101 — `cli_selectors` (session_search)

| metric | cadr | pi |
|---|---|---|
| `session_search` | `filter-and-sort-sessions` | `filterAndSortSessions` (`packages/coding-agent/src/modes/interactive/components/session-selector-search.ts`) |

Independent named metric for the `cli_selectors` hole.
Three synthetic search records. Time filter/sort only, not
selector render or TUI move/confirm. Empty query; substring
`cadr`; miss; `re:cadr`; invalid `re:[`; name-filter named.
sort-mode recent. Observed `ss_empty` / `ss_hit` / `ss_miss` /
`ss_re` / `ss_badre` / `ss_named` are exact (3 / 1 / 0 / 1 /
0 / 2). Do not exact fuzzy-token AND vs cadr whole-needle.
Other selector files stay `needs-pair`. First Friend-MachineD
freeze **2.48×** (42.40 / 17.10 µs), ceiling 8.0. Same commit
no optimize.

### Pair 102 — `websocket_stream` (stream_roundtrip)

| metric | cadr | pi |
|---|---|---|
| `stream_roundtrip` | `stream-chat` `:transport :websocket` (`src/cadr-ai/websocket.lisp`) | `stream` `transport: "websocket"` (`packages/ai/src/api/openai-codex-responses.ts`) |

Independent named metric for the `websocket_stream` hole.
Recorded `response.*` frames. cadr Goal 12 `usocket` loopback
on `127.0.0.1` (not openai.com). pi MockWebSocket (no TCP).
One user message `Say hello`; text `Hello`; usage 1/1.
Observed `ws_text` / `stop_reason` / `text_characters` /
`usage_input` / `usage_output` are exact. Do not exact
session/debug stats. First Friend-MachineD freeze
**507.72×** (44298 / 87.25 µs), ceiling 800.0 (TCP
loopback vs MockWebSocket). Same commit no optimize.

### Pair 103 — `evals_harness` (artifact_persist)

| metric | cadr | pi |
|---|---|---|
| `artifact_persist` | `persist-eval-artifact-references` | `persistEvalArtifactReferences` (`packages/evals/src/vitest-evals/artifacts.ts`) |

Leftover sibling of the `evals_harness` hole. One session
artifact + one source artifact, run-id `run-1`. Time persist
to a scratch directory, not a live vitest run. Observed
`ap_n` / `ap_sess` / `ap_src` / `ap_sess_prefix` /
`ap_src_prefix` / `ap_sess_file` / `ap_src_file` are exact
(2 / 1 / 1 / 1 / 1 / 1 / 1). Do not exact digest hex.
`atomic-file.lisp` is covered-as-callee. First Friend-MachineD
freeze **0.53×** (595 / 1130 µs), ceiling 8.0. cadr leads.
Same commit no optimize.

### Pair 104 — `cli_support` (experimental)

| metric | cadr | pi |
|---|---|---|
| `experimental` | `experimental-features-enabled-p` | `areExperimentalFeaturesEnabled` (`packages/coding-agent/src/core/experimental.ts`) |

Leftover sibling of the `cli_support` hole. Time the `"1"`
predicate, not HTML escape or a live TUI. Values `"1"` / empty /
`"0"` / `"true"` / nil. Do not exact `CADR_EXPERIMENTAL` vs
`PI_EXPERIMENTAL`. Observed `ex_on` / `ex_empty` / `ex_zero` /
`ex_true` / `ex_nil` are exact (1 / 0 / 0 / 0 / 0). First
Friend-MachineD freeze **0.05×** (0.23 / 4.77 µs), ceiling
8.0 (microsecond-floor). cadr leads. Same commit no optimize.

### Pair 105 — `cli_selectors` (key_text)

| metric | cadr | pi |
|---|---|---|
| `key_text` | `format-key-text` | `formatKeyText` (`packages/coding-agent/src/modes/interactive/components/keybinding-hints.ts`) |

Leftover sibling of the `cli_selectors` hole. Time string
format, not TUI hint render. `ctrl+c` / slash alternatives /
`shift+tab` / capitalize / empty. Do not exact darwin
alt→option. Observed `kt_ctrl` / `kt_slash` / `kt_shift` /
`kt_cap` / `kt_empty` are exact. First Friend-MachineD freeze
**2.86×** (5.76 / 2.01 µs), ceiling 8.0. Same commit no
optimize.

### Pair 106 — `evals_harness` (format)

| metric | cadr | pi |
|---|---|---|
| `format` | `format-harness-comparison-report` | `formatHarnessComparisonReport` (`packages/evals/src/vitest-evals/summary.ts`) |

Leftover sibling of the `evals_harness` hole. Time
report format only (summarize in prepare), not a live
vitest run. Empty report vs four scored observations.
Strip ANSI for flags; do not exact full report text
(pi `styleText` vs cadr unstyled). Observed `fmt_empty`
/ `fmt_empty_hdr` / `fmt_hdr` / `fmt_base` / `fmt_pass`
are exact (1 / 0 / 1 / 1 / 1). First Friend-MachineD
freeze **1.14×** (20.62 / 18.10 µs), ceiling 8.0. Same
commit no optimize.

### Pair 107 — `cli_interactive_controller` (auth_type)

| metric | cadr | pi |
|---|---|---|
| `auth_type` | `tui-auth-type-label` | `formatAuthSelectorProviderType` (`packages/coding-agent/src/modes/interactive/components/oauth-selector.ts`) |

Leftover sibling of the `cli_interactive_controller` hole.
Time the oauth/api-key label, not TUI autocomplete or
selector render. `:oauth` → `subscription`; `:api-key` →
`API key`. Do not exact other types (cadr else-branch is
`API key`; pi union is those two strings). Observed
`al_oauth` / `al_key` are exact (1 / 1). First
Friend-MachineD freeze **1.44×** (0.21 / 0.15 µs), ceiling
8.0 (microsecond-floor). Same commit no optimize.

### Pair 108 — `settings_load` (http_idle)

| metric | cadr | pi |
|---|---|---|
| `http_idle` | `http-idle-timeout-label` | `formatHttpIdleTimeoutMs` (`packages/coding-agent/src/core/http-dispatcher.ts`) |

Leftover sibling of the `settings_load` hole. Time named
timeout labels, not settings UI or a live dispatcher.
`30000` / `60000` / `120000` / `300000` / `0`. Do not
exact a custom timeout (cadr `~,3G` vs pi
`${ms/1000} sec`). Observed `ht_30` / `ht_1m` / `ht_2m` /
`ht_5m` / `ht_off` are exact. First Friend-MachineD freeze
**0.47×** (0.25 / 0.53 µs), ceiling 8.0 (microsecond-floor).
cadr leads. Same commit no optimize.

### Pair 109 — `agent_tool_loop` (tool_path)

| metric | cadr | pi |
|---|---|---|
| `tool_path` | `resolve-tool-path` | `resolveToCwd` (`packages/coding-agent/src/core/tools/path-utils.ts`) |

Leftover sibling of the `agent_tool_loop` hole. Time path
resolve only, not a tool execute or a live FS probe.
Relative `foo.txt`; abs `/tmp/abs/bar`; `@rel.txt`;
nbsp; `../x`. POSIX. Do not exact empty (cadr errors) or
`~` (cadr directory namestring trailing slash). Observed
`tp_rel` / `tp_abs` / `tp_at` / `tp_nbsp` / `tp_parent`
are exact. First Friend-MachineD freeze **2.44×**
(12.74 / 5.23 µs), ceiling 8.0. Same commit no optimize.

### Pair 110 — `agent_tool_loop` (line_ending)

| metric | cadr | pi |
|---|---|---|
| `line_ending` | `detect-line-ending` | `detectLineEnding` (`packages/coding-agent/src/core/tools/edit-diff.ts`) |

Leftover sibling of the `agent_tool_loop` hole. Time line-ending
probe only, not normalize/restore or a live edit apply.
LF `a\nb`; CRLF `a\r\nb`; no newline `ab`; empty `""`. Do not
exact mixed first-LF-then-CRLF (cadr searches any CRLF; pi
compares the first `\n` against the first `\r\n`). Observed
`le_lf` / `le_crlf` / `le_none` / `le_empty` are exact. First
Friend-MachineD freeze **1.99×** (0.75 / 0.38 µs), ceiling 8.0
(microsecond-floor). Same commit no optimize.

### Pair 111 — `cli_selectors` (fuzzy_filter)

| metric | cadr | pi |
|---|---|---|
| `fuzzy_filter` | `selector-fuzzy-filter` | `fuzzyFilter` (`packages/tui/src/fuzzy.ts`) |

Leftover sibling of the `cli_selectors` hole. Time filter +
sort only, not selector render or confirm. Empty query; token
`an`; `app` on `a_p_p`/`app`/`application`; `cl` on `clone`/`cl`;
slash token `openai-codex/gpt-5.5` on one model row. Do not
exact mixed scoring edges beyond the booked fixtures. Observed
`ff_empty` / `ff_an` / `ff_app` / `ff_cl` / `ff_slash` are
exact. First Friend-MachineD freeze **0.34×** (8.2 / 23.7 µs),
ceiling 8.0. cadr leads. Same commit no optimize.

### Pair 112 — `cli_selectors` (delete_query)

| metric | cadr | pi |
|---|---|---|
| `delete_query` | `selector-delete-query-character` | `Input.handleInput` backspace grapheme delete (`packages/tui/src/components/input.ts`) |

Leftover sibling of the `cli_selectors` hole. Time grapheme
backspace on the filter query only, not selector render.
Empty / `a` / `abc` / `café` / `a🙂b` / combining `é`.
Observed `dq_empty` / `dq_a` / `dq_abc` / `dq_cafe` /
`dq_emoji` / `dq_combining` are exact. First Friend-MachineD
freeze **0.19×** (2.2 / 11.3 µs), ceiling 8.0. cadr leads.
Same commit no optimize.

### Pair 113 — `cli_selectors` (visible_slice)

| metric | cadr | pi |
|---|---|---|
| `visible_slice` | `selector-frame-visible-slice` | selector viewport slice (`oauth-selector.ts` et al.) |

Leftover sibling of the `cli_selectors` hole. Time centered
viewport window only, not render or confirm. Count/selected/max
fixtures: 0/0/8, 5/2/8, 20/10/8, 20/0/8, 20/19/8, 3/1/8.
Observed `vs0` / `vs0_end` / `vs0_vis` / `vs5` / `vs5_vis` /
`vs20_mid` / `vs20_mid_vis` / `vs20_top` / `vs20_bot` /
`vs20_bot_vis` / `vs3_vis` are exact. First Friend-MachineD
freeze **2.23×** (2.5 / 1.1 µs), ceiling 8.0. Same commit no
optimize.

### Pair 114 — `cli_selectors` (move_index)

| metric | cadr | pi |
|---|---|---|
| `move_index` | `selector-frame-move-index` | wrap selection index (`select-list.ts` up/down) |

Leftover sibling of the `cli_selectors` hole. Time mod-wrap
only, not render. Fixtures: empty count; wrap up/down; forward/
back; large delta. Observed `mi_empty` / `mi_wrap_up` /
`mi_wrap_dn` / `mi_fwd` / `mi_back` / `mi_big` are exact.
First Friend-MachineD freeze **1.44×** (4.5 / 3.1 µs), ceiling 8.0.
Same commit no optimize.

### Pair 115 — `cli_selectors` (align_left_right)

| metric | cadr | pi |
|---|---|---|
| `align_left_right` | `selector-align-left-right` | session-selector header left/right align |

Leftover sibling of the `cli_selectors` hole. Time truncate +
pad only, not render. Fixtures: wide; truncate left; truncate
right; narrow; empty left; empty right. Observed `alr_wide` /
`alr_trunc_left` / `alr_trunc_right` / `alr_narrow` /
`alr_empty_left` / `alr_empty_right` are exact. First
Friend-MachineD freeze **3.79×** (27.2 / 7.2 µs), ceiling 8.0.
Same commit no optimize.

### Pair 116 — `cli_selectors` (fit_line)

| metric | cadr | pi |
|---|---|---|
| `fit_line` | `selector-fit-line` | `truncateToWidth` + optional pad |

Leftover sibling of the `cli_selectors` hole. Time truncate/pad
only, not render. Fixtures: short; truncate; pad; ellipsis; wide
char; empty pad. Observed `fl_short` / `fl_trunc` / `fl_pad` /
`fl_ellipsis` / `fl_wide` / `fl_empty` are exact. First
Friend-MachineD freeze **0.32×** (10.3 / 31.7 µs), ceiling 8.0.
Same commit no optimize.

### Pair 117 — `cli_selectors` (border_line)

| metric | cadr | pi |
|---|---|---|
| `border_line` | `selector-border-line` | `DynamicBorder.render` |

Leftover sibling of the `cli_selectors` hole. Time themed
horizontal rule only, not full frame render. Fixtures: width 40
border/accent; width 1/80/10/20. Observed `bl_w40` / `bl_w40_acc`
/ `bl_w1` / `bl_w80` / `bl_w10_acc` / `bl_w20` are exact. First
Friend-MachineD freeze **0.65×** (8.6 / 13.2 µs), ceiling 8.0.
Same commit no optimize.

### Pair 118 — `cli_selectors` (selected_line)

| metric | cadr | pi |
|---|---|---|
| `selected_line` | `selector-selected-line` | `theme.bg selectedBg` + truncate/pad |

Leftover sibling of the `cli_selectors` hole. Time selected-bg
fit only, not full item render. Fixtures: short; truncate; wide
char; empty; pad wide; narrow. Observed `sl_short` / `sl_trunc` /
`sl_wide` / `sl_empty` / `sl_pad20` / `sl_narrow` are exact. First
Friend-MachineD freeze **0.83×** (22.0 / 26.4 µs), ceiling 8.0.
Same commit no optimize.

### Pair 119 — `cli_selectors` (muted_line)

| metric | cadr | pi |
|---|---|---|
| `muted_line` | `selector-muted-line` | `theme.fg muted` + truncate |

Leftover sibling of the `cli_selectors` hole. Time muted fg +
truncate only, not full item render. Fixtures mirror
`selected_line` without pad. Observed `ml_short` / `ml_trunc` /
`ml_wide` / `ml_empty` / `ml_item20` / `ml_narrow` are exact.
First Friend-MachineD freeze **0.24×** (19.2 / 80.9 µs), ceiling
8.0. Same commit no optimize.

### Pair 120 — `cli_selectors` (dim_line)

| metric | cadr | pi |
|---|---|---|
| `dim_line` | `selector-dim-line` | `theme.fg dim` + truncate |

Leftover sibling of the `cli_selectors` hole. Time dim fg +
truncate only, not full item render. Fixtures mirror `muted_line`.
Observed `dl_short` / `dl_trunc` / `dl_wide` / `dl_empty` /
`dl_item20` / `dl_narrow` are exact. First Friend-MachineD freeze
**0.61×** (18.9 / 30.9 µs), ceiling 8.0. Same commit no optimize.

### Pair 121 — `cli_selectors` (modified_cursor_key)

| metric | cadr | pi |
|---|---|---|
| `modified_cursor_key` | `selector-modified-cursor-key` | `parseKey` CSI modified arrows |

Leftover sibling of the `cli_selectors` hole. Time CSI
`\x1b[1;<mod>A/B/C/D` parse only, not full keybinding match.
Fixtures: up; shift+down; ctrl+right; alt+left; ctrl+shift+up;
super+down. Observed `mck_up` / `mck_shift_dn` / `mck_ctrl_rt` /
`mck_alt_lt` / `mck_ctrl_shift_up` / `mck_super_dn` are exact.
First Friend-MachineD freeze **11.56×** (47.3 / 4.1 µs), ceiling
20.0. Same commit no optimize.

### Pair 122 — `cli_selectors` (title_line)

| metric | cadr | pi |
|---|---|---|
| `title_line` | `selector-title-line` | `theme.fg accent` + `theme.bold` + Text margins |

Leftover sibling of the `cli_selectors` hole. Time accent bold title
line render only, not full selector chrome. Fixtures: short title;
truncated long title; empty title; wide unicode; narrow width; normal
width. Observed `tl_short` / `tl_trunc` / `tl_empty` / `tl_wide` /
`tl_narrow` / `tl_normal` are exact. Pi bench isolates chalk from
`NO_COLOR=1` and matches cadr empty-title bold SGR. First
Friend-MachineD freeze **0.61×** (33.3 / 51.3 µs), ceiling 8.0. Same
commit no optimize.

### Pair 123 — `cli_selectors` (overlay_title_line)

| metric | cadr | pi |
|---|---|---|
| `overlay_title_line` | `selector-overlay-title-line` | `theme.fg accent` + `theme.bold` + TruncatedText margins |

Leftover sibling of the `cli_selectors` hole. Auth-overlay title path
with forced theme SGR (`:enabled-p t`). Fixtures mirror `title_line`
with oauth/trust overlay strings. Observed `otl_short` / `otl_trunc` /
`otl_empty` / `otl_wide` / `otl_narrow` / `otl_normal` are exact.
First Friend-MachineD freeze **0.16×** (33.4 / 205.6 µs), ceiling 8.0.
Same commit no optimize.

### Pair 124 — `cli_selectors` (input_line)

| metric | cadr | pi |
|---|---|---|
| `input_line` | `selector-input-line` | `Input.render` |

Leftover sibling of the `cli_selectors` hole. Time single-line
selector search input render only (`> ` prompt, software cursor at end).
Fixtures: empty; short ascii; two-char width; grapheme value; narrow
width; wide scroll. Observed `il_empty` / `il_short` / `il_ab12` /
`il_grapheme` / `il_narrow` / `il_scroll` are exact. First
Friend-MachineD freeze **0.05×** (39.4 / 272.8 µs), ceiling 8.0. Same
commit no optimize.

### Pair 125 — `cli_selectors` (keybinding_text)

| metric | cadr | pi |
|---|---|---|
| `keybinding_text` | `selector-keybinding-text` | `KeybindingsManager.getKeys` join |

Leftover sibling of the `cli_selectors` hole. Time raw key-id join
(`~{~A~^/~}`) for selector footer hints, not `format-key-text`.
Fixtures: default confirm/cancel/left; empty unbound binding; custom
user overrides. Observed `kbt_confirm` / `kbt_cancel` / `kbt_left` /
`kbt_empty` / `kbt_custom_confirm` / `kbt_custom_cancel` are exact.
First Friend-MachineD freeze **0.61×** (36.7 / 23.3 µs), ceiling 8.0.
Same commit no optimize.

### Pair 126 — `cli_selectors` (keybinding_hint)

| metric | cadr | pi |
|---|---|---|
| `keybinding_hint` | `selector-keybinding-hint` | `rawKeyHint` dim/muted |

Leftover sibling of the `cli_selectors` hole. Time selector footer
hint render (`raw-key-hint` on joined key ids + description). Fixtures
mirror `keybinding_text` with description strings. Observed
`kbh_confirm` / `kbh_cancel` / `kbh_left` / `kbh_empty` /
`kbh_custom_save` / `kbh_custom_cancel` are exact. First
Friend-MachineD freeze **1.32×** (59.9 / 23.2 µs), ceiling 8.0. Same
commit no optimize.

### Pair 127 — `cli_selectors` (session_format_age)

| metric | cadr | pi |
|---|---|---|
| `session_format_age` | `session-selector-format-age` | `formatSessionDate` |

Leftover sibling of the `sessions.lisp` hole. Time relative session
age labels with fixed `now` (1700000000000). Fixtures cover now,
45s, 2m, 1h, 1d, and 10d (week bucket; avoids 30-day boundary
mismatch). Observed `sfa_now` / `sfa_sec` / `sfa_min` / `sfa_hour` /
`sfa_day` / `sfa_week` are exact. First Friend-MachineD freeze
**1.00×** (0.7 / 0.7 µs), ceiling 8.0. Same commit no optimize.

### Pair 128 — `cli_selectors` (session_record_label)

| metric | cadr | pi |
|---|---|---|
| `session_record_label` | `session-selector-record-label` | session list row label (`session-selector.ts`) |

Leftover sibling of the `sessions.lisp` hole. Row label text
only: named session, first-message fallback, empty
`(no messages)`, control-char neutralization, named label with
DEL. Uses `sanitize-session-selector-label`. Fixtures avoid
whitespace-only `name` (cadr `named-session-p` vs pi
`name ?? firstMessage`). Observed `srl_named` / `srl_first` /
`srl_empty` / `srl_ctrl` / `srl_name_ctrl` are exact. First
Friend-MachineD freeze **1.84×** (2.6 / 1.4 µs), ceiling 8.0.
Same commit no optimize.

### Pair 129 — `cli_selectors` (session_shorten_path)

| metric | cadr | pi |
|---|---|---|
| `session_shorten_path` | `session-selector-shorten-path` | `shortenPath` |

Leftover sibling of the `sessions.lisp` hole. Home-dir tilde
shortening only; fixtures cover bare home, prefix-only edge case,
absolute path, nested home path, and empty string. Observed
`ssp_home` / `ssp_prefix` / `ssp_abs` / `ssp_proj` / `ssp_empty`
are exact. `session-selector-gutter-prefixes` stays unpaired
(cadr batch gutter vs pi `buildTreePrefix` ancestor padding
differs). First Friend-MachineD freeze **5.05×** (5.5 / 1.1 µs),
ceiling 8.0. Same commit no optimize.

### Pair 130 — `cli_selectors` (session_quoted_search)

| metric | cadr | pi |
|---|---|---|
| `session_quoted_search` | `search-record-position` (quoted) | phrase `indexOf` (`session-selector-search.ts`) |

Leftover sibling of the `sessions.lisp` hole. Quoted phrase
position lookup via `quoted-search-p`, not full
`filter-and-sort-sessions`. Fixtures reuse the
`session_search` records; misses encode as `-1`. Observed
`sqs_cadr` / `sqs_phrase` / `sqs_miss` / `sqs_other_miss` /
`sqs_name` / `sqs_other_hit` are exact. Do not exact
unquoted fuzzy-token AND. First Friend-MachineD freeze
**1.29×** (11.0 / 8.6 µs), ceiling 8.0. Same commit no
optimize.

### Pair 131 — `cli_selectors` (session_thread_records)

| metric | cadr | pi |
|---|---|---|
| `session_thread_records` | `thread-session-records` | `buildSessionTree` + `flattenSessionTree` |

Leftover sibling of the `sessions.lisp` hole. Parent/child session
tree flatten only, not gutter render or full selector state machine.
Five-session fixture: `parent` → `child1` → `grand`, sibling
`child2`, separate root `root2`. Observed `str_count` / `str_depths`
/ `str_ids` are exact (flat order `parent,child1,grand,child2,root2`
at depths `0,1,2,1,0`). `session-selector-gutter-prefixes` stays
unpaired (cadr batch gutter vs pi `buildTreePrefix` ancestor padding
differs). First Friend-MachineD freeze **13.07×** (165.9 / 12.7 µs),
ceiling 30.0. Same commit no optimize.

### Pair 132 — `cli_selectors` (session_binding_label)

| metric | cadr | pi |
|---|---|---|
| `session_binding_label` | `session-selector-binding-label` | `KeybindingsManager.getKeys` first-or-name |

Leftover sibling of the `sessions.lisp` hole. First bound key text
only (rename/delete footer paths), not full `keybinding_text` join or
`keybinding_hint` styling. Fixtures: default `tui.select.confirm` /
`app.session.delete` / `app.session.deleteNoninvasive`; unknown name
falls back to the binding id; custom user override on
`app.session.toggleSort`. Observed `sbl_confirm` / `sbl_delete` /
`sbl_noninvasive` / `sbl_fallback` / `sbl_custom` are exact.
`session-selector-gutter-prefixes` stays unpaired. First
Friend-MachineD freeze **1.43×** (41.2 / 28.9 µs), ceiling 8.0. Same
commit no optimize.

### Pair 133 — `cli_selectors` (session_same_path)

| metric | cadr | pi |
|---|---|---|
| `session_same_path` | `same-session-path-p` | `canonicalizePath` equality |

Leftover sibling of the `sessions.lisp` hole. Canonical session path
equality only (`canonical-file-name` vs `realpathSync` fallback), not
full delete/rename state machine. Fixtures: equal paths, different
paths, nil left/right/both (encoded as 1/0). Observed `ssp_same` /
`ssp_diff` / `ssp_nil_left` / `ssp_nil_right` / `ssp_nil_both` are
exact. `session-selector-gutter-prefixes` stays unpaired. First
Friend-MachineD freeze **0.65×** (22.1 / 33.9 µs), ceiling 8.0. Same
commit no optimize.

### Pair 134 — `cli_selectors` (session_quoted_p)

| metric | cadr | pi |
|---|---|---|
| `session_quoted_p` | `quoted-search-p` | `quotedSearchPi` (`session-selector-search.ts`) |

Leftover sibling of the `sessions.lisp` hole. Quoted-phrase predicate
only (`length >= 2` and both ends `"`), not full search or filter.
Fixtures: `"cadr"`, `"hello world"`, plain `cadr`, empty, lone `"`,
unclosed `"open` (encoded as 1/0). Observed `sqp_phrase` / `sqp_words` /
`sqp_plain` / `sqp_empty` / `sqp_one` / `sqp_open` are exact.
`session-selector-gutter-prefixes` stays unpaired. First
Friend-MachineD freeze **0.43×** (0.3 / 0.7 µs), ceiling 8.0. Same
commit no optimize.

### Pair 135 — `cli_selectors` (session_named_p)

| metric | cadr | pi |
|---|---|---|
| `session_named_p` | `named-session-p` | `hasSessionName` (`session-selector-search.ts`) |

Leftover sibling of the `sessions.lisp` hole. Named-session predicate
only (`string-trim` whitespace vs `name?.trim()`), not full
`filter-and-sort-sessions` name filter. Fixtures: `"alpha"`, spaces-only
`"   "`, empty string, nil name (encoded as 1/0). Observed `snp_named` /
`snp_whitespace` / `snp_empty` / `snp_nil` are exact.
`session-selector-gutter-prefixes` stays unpaired. First
Friend-MachineD freeze **2.11×** (0.6 / 0.3 µs), ceiling 8.0. Same
commit no optimize.

### Pair 136 — `cli_selectors` (settings_thinking_description)

| metric | cadr | pi |
|---|---|---|
| `settings_thinking_description` | `settings-thinking-description` | `THINKING_DESCRIPTIONS` (`settings-selector.ts`) |

First `settings.lisp` hole sibling under `cli_selectors`. Thinking-level
description lookup only, not submenu render or cycle. Fixtures cover
`:off` through `:max` plus unknown keyword (empty string). Observed
`std_off` / `std_minimal` / `std_low` / `std_medium` / `std_high` /
`std_xhigh` / `std_max` / `std_unknown` are exact. First
Friend-MachineD freeze **0.80×** (0.3 / 0.3 µs), ceiling 8.0. Same
commit no optimize.

### Pair 137 — `cli_selectors` (settings_display_value)

| metric | cadr | pi |
|---|---|---|
| `settings_display_value` | `settings-display-value` | boolean/value `currentValue` formatting (`settings-selector.ts`) |

`settings.lisp` sibling. Value-to-label string only (`t`/`nil`/symbol/
number/string), not `settings-option-display-value` format hooks.
Fixtures: `t`, `nil`, `:medium`, `42`, `"hello"`. Observed `sdv_true` /
`sdv_false` / `sdv_symbol` / `sdv_int` / `sdv_string` are exact. First
Friend-MachineD freeze **3.39×** (0.6 / 0.2 µs), ceiling 8.0. Same
commit no optimize.

### Pair 138 — `cli_interactive_controller` (parse_auto_theme)

| metric | cadr | pi |
|---|---|---|
| `parse_auto_theme` | `parse-auto-theme-setting` | `parseAutoThemeSetting` (`theme.ts`) |

First `theme.lisp` hole sibling under `cli_interactive_controller`.
Automatic theme setting parse only (`light/dark` split), not
`resolve-theme-setting`. Fixtures: valid `"light/dark"`, empty halves,
nil, double slash, fixed theme without slash. Encoded as `light|dark` or
empty. Observed `pat_valid` / `pat_empty_left` / `pat_empty_right` /
`pat_nil` / `pat_double` / `pat_fixed` are exact. First Friend-MachineD
freeze **1.96×** (1.0 / 0.5 µs), ceiling 8.0. Same commit no optimize.

### Pair 139 — `cli_interactive_controller` (resolve_theme)

| metric | cadr | pi |
|---|---|---|
| `resolve_theme` | `resolve-theme-setting` | `resolveThemeSetting` (`theme.ts`) |

Sibling of Pair 138 on `theme.lisp`. Theme resolution only: auto
`light/dark` picks terminal background branch; fixed theme passthrough;
invalid slash forms return empty. Fixtures: auto light/dark, fixed
`solarized`, bad double-slash, nil. Encoded as theme string or empty.
Observed `rts_auto_light` / `rts_auto_dark` / `rts_fixed` / `rts_bad` /
`rts_nil` are exact. First Friend-MachineD freeze **1.16×** (0.8 / 0.7 µs),
ceiling 8.0. Same commit no optimize.

### Pair 140 — `cli_selectors` (settings_automatic_theme_setting)

| metric | cadr | pi |
|---|---|---|
| `settings_automatic_theme_setting` | `settings-selector-automatic-theme-setting` | `ThemeSubmenu.getAutomaticThemeSetting` (`settings-selector.ts`) |

Automatic theme `light/dark` string formatting only, not submenu
navigation. Fixtures: `solarized/dark`, `dark/dark`, `light/dark`.
Observed `sats_solarized` / `sats_same` / `sats_light_dark` are exact.
First Friend-MachineD freeze **2.42×** (0.4 / 0.2 µs), ceiling 8.0. Same
commit no optimize.

### Pair 141 — `cli_selectors` (settings_active_automatic_theme)

| metric | cadr | pi |
|---|---|---|
| `settings_active_automatic_theme` | `settings-selector-active-automatic-theme` | `ThemeSubmenu.getActiveAutomaticTheme` (`settings-selector.ts`) |

Sibling of Pair 140. Terminal-background branch pick only: light terminal
uses light theme name, otherwise dark. Fixtures: `solarized/dark` with
`:light` / `:dark` terminal, plus `light/dark` with `:light`. Observed
`saat_light_term` / `saat_dark_term` / `saat_light_pair` are exact. First
Friend-MachineD freeze **1.33×** (0.2 / 0.1 µs), ceiling 8.0. Same commit
no optimize.

### Pair 142 — `cli_selectors` (settings_cycle)

| metric | cadr | pi |
|---|---|---|
| `settings_cycle` | `settings-selector-cycle` | `SettingsList` value cycle (`settings-list.ts`) |

Settings option value advance only (Space/Enter cycle path), not
submenu open or filter. Fixtures: boolean flip, three-value advance,
wrap, missing current value. Encoded as `id|value` after one cycle.
Observed `ssc_true` / `ssc_transport` / `ssc_wrap` / `ssc_missing` are
exact. First Friend-MachineD freeze **4.13×** (2.0 / 0.5 µs), ceiling
8.0. Same commit no optimize.

### Pair 143 — `cli_selectors` (settings_apply_filter)

| metric | cadr | pi |
|---|---|---|
| `settings_apply_filter` | `settings-selector-apply-filter` | `SettingsList.applyFilter` (`settings-list.ts`) |

Settings selector query filter only: fuzzy label match plus selected
reset to 0. Fixtures: empty query (all visible), single match, no match,
multi match. Encoded as `count|selected`. Observed `sap_empty` /
`sap_trans` / `sap_none` / `sap_app` are exact. First Friend-MachineD
freeze **1.61×** (7.8 / 4.8 µs), ceiling 8.0. Same commit no optimize.

### Pair 144 — `cli_selectors` (tree_entry_filtered)

| metric | cadr | pi |
|---|---|---|
| `tree_entry_filtered` | `tree-selector-entry-filtered-p` | tree-selector filter mode predicate (`tree-selector.ts`) |

Per-entry filter predicate only (default / user-only / no-tools /
labeled-only / all), not search tokens or fold skipping. Fixtures cover
user default pass, settings default fail, user-only, tool-result no-tools,
labeled message, settings all pass. Encoded as `t` or empty. Observed
`tef_user_def` / `tef_label_def` / `tef_user_uo` / `tef_tool_nt` /
`tef_labeled_lo` / `tef_all_label` are exact. First Friend-MachineD freeze
**0.56×** (0.4 / 0.6 µs), ceiling 8.0. Same commit no optimize.

### Pair 145 — `cli_selectors` (tree_query_matches)

| metric | cadr | pi |
|---|---|---|
| `tree_query_matches` | `tree-selector-query-matches-p` | tree search token predicate (`tree-selector.ts`) |

Per-entry search-token match only: lowercase haystack from label/role/text,
whitespace-split query tokens, all tokens must appear. Not filter mode or
fold skipping. Fixtures: single-token hit/miss, multi-token hit, partial
miss (`hello beta`), empty query (vacuous match). Encoded as `t` or empty.
Observed `tqm_hit` / `tqm_miss` / `tqm_multi` / `tqm_partial` /
`tqm_empty` are exact. First Friend-MachineD freeze **2.20×** (5.2 / 2.3 µs),
ceiling 8.0. Same commit no optimize.

### Pair 146 — `cli_selectors` (tree_entry_search_text)

| metric | cadr | pi |
|---|---|---|
| `tree_entry_search_text` | `tree-selector-entry-search-text` | `getSearchableText` field join (`tree-selector.ts`) |

Per-entry searchable haystack only: join non-nil label/role/text/summary/name/
model-id/thinking-level/custom-type with spaces. Not token matching or filter
mode. Fixtures: sparse label+text, label-only, empty entry, all fields, text-only.
Observed `tese_sparse` / `tese_label` / `tese_empty` / `tese_full` / `tese_text`
are exact. First Friend-MachineD freeze **1.22×** (1.8 / 1.5 µs), ceiling 8.0.
Same commit no optimize.

### Pair 147 — `cli_selectors` (tree_settings_entry_p)

| metric | cadr | pi |
|---|---|---|
| `tree_settings_entry_p` | `tree-selector-settings-entry-p` | `isSettingsEntry` predicate (`tree-selector.ts`) |

Per-entry settings/bookkeeping type check only: label, custom, model-change,
thinking-level-change, session-info vs ordinary user message. Encoded as `t` or
empty. Observed `tsep_label` / `tsep_user` / `tsep_custom` / `tsep_model` /
`tsep_think` / `tsep_session` are exact. First Friend-MachineD freeze
**0.65×** (0.3 / 0.5 µs), ceiling 8.0. Same commit no optimize.

### Pair 148 — `cli_selectors` (tree_normalize_display_text)

| metric | cadr | pi |
|---|---|---|
| `tree_normalize_display_text` | `tree-selector-normalize-display-text` | `getEntryDisplayText` normalize (`tree-selector.ts`) |

Display-text whitespace normalization only: newline/tab to space, then trim. Not
theme or entry-type formatting. Fixtures: plain, padded, newline/tab, nil, whitespace-only.
Observed `tnd_hello` / `tnd_spaced` / `tnd_newline` / `tnd_empty` / `tnd_ws` are
exact. First Friend-MachineD freeze **2.88×** (4.3 / 1.5 µs), ceiling 8.0. Same
commit no optimize.

### Pair 149 — `cli_selectors` (tree_status_labels)

| metric | cadr | pi |
|---|---|---|
| `tree_status_labels` | `tree-selector-status-labels` | `getStatusLabels` (`tree-selector.ts`) |

Filter/timestamp status suffix only: bracketed filter label plus optional
`[+label time]`. Bench uses `%make-tree-selector-state` with filter and
show-label-timestamps-p only (no apply-filter rebuild). Fixtures cover default,
no-tools, user-only, labeled-only, all, timestamps-only, combined. Observed
`tsl_empty` / `tsl_notools` / `tsl_user` / `tsl_labeled` / `tsl_all` /
`tsl_time` / `tsl_both` are exact. First Friend-MachineD freeze **8.92×**
(4.1 / 0.5 µs), ceiling 8.0. Same commit no optimize.

### Pair 150 — `cli_selectors` (tree_shorten_path)

| metric | cadr | pi |
|---|---|---|
| `tree_shorten_path` | `tree-selector-shorten-path` | `formatToolCall` shortenPath (`tree-selector.ts`) |

HOME-prefix path shortening only (`~` replacement). Not tool-arg formatting or
theme. Fixtures mirror session shorten-path: home, under-home, absolute, project
path, empty. Observed `tsp_home` / `tsp_prefix` / `tsp_abs` / `tsp_proj` /
`tsp_empty` are exact. First Friend-MachineD freeze **1.76×** (2.7 / 1.6 µs),
ceiling 8.0. Same commit no optimize.

### Pair 151 — `cli_selectors` (tree_foldable_p)

| metric | cadr | pi |
|---|---|---|
| `tree_foldable_p` | `tree-selector-foldable-p` | `isFoldable` (`tree-selector.ts`) |

Foldable predicate only: visible children present and either root or multi-sibling
branch. Bench uses `%make-tree-selector-state` with hand-built visible-parent/
visible-children maps (no apply-filter). Encoded as `t` or empty. Observed
`tfp_root` / `tfp_leaf` / `tfp_only_child` / `tfp_branch` are exact. First
Friend-MachineD freeze **2.79×** (4.1 / 1.5 µs), ceiling 8.0. Same commit no
optimize.

### Pair 152 — `cli_selectors` (tree_tool_argument)

| metric | cadr | pi |
|---|---|---|
| `tree_tool_argument` | `tree-selector-tool-argument` | `formatToolCall` arg lookup (`tree-selector.ts`) |

Tool-args JSON lookup only: primary key then fallback (`path` / `file_path`).
Fixtures: path hit, file_path fallback, primary wins, missing keys, nil args.
Observed `tta_path` / `tta_file` / `tta_prio` / `tta_miss` / `tta_nil` are exact.
First Friend-MachineD freeze **3.32×** (24.7 / 7.4 µs), ceiling 8.0. Same commit no
optimize.

### Pair 153 — `cli_selectors` (tree_cycle_filter)

| metric | cadr | pi |
|---|---|---|
| `tree_cycle_filter` | `tree-selector-cycle-filter` | filter cycle keybindings (`tree-selector.ts`) |

Filter-mode advance only on empty tree state: `default`→`no-tools` (+1),
`no-tools`→`default` (−1), `all`→`default` (+1 wrap), `user-only`→`labeled-only`
(+1). Encoded as filter name string. Observed `tcf_def_fwd` / `tcf_nt_back` /
`tcf_all_fwd` / `tcf_user_fwd` are exact. First Friend-MachineD freeze **17.08×**
(21.6 / 4.4 µs), ceiling 8.0. Same commit no optimize.

### Pair 154 — `cli_selectors` (tree_format_label_timestamp)

| metric | cadr | pi |
|---|---|---|
| `tree_format_label_timestamp` | `tree-selector-format-label-timestamp` | `formatLabelTimestamp` (`tree-selector.ts`) |

Label timestamp formatting only with fixed `now` (2026-08-02 15:00 UTC) and
`TZ=UTC`. Fixtures: same-day time, same-year date, cross-year, offset input.
Invalid `not-a-date` measured on cadr only (cadr passthrough; pi NaN path
excluded from exact). Observed `09:07` / `3/28 14:32` / `25/12/31 23:59` /
`07:30` are exact. First Friend-MachineD freeze **1.85×** (9.2 / 4.9 µs),
ceiling 8.0. Same commit no optimize.

### Pair 155 — `cli_selectors` (tree_format_tool_call)

| metric | cadr | pi |
|---|---|---|
| `tree_format_tool_call` | `tree-selector-format-tool-call` | `formatToolCall` (`tree-selector.ts`) |

Tool-call summary strings only: read/write/edit/bash/grep/find/ls/default
custom. Fixtures cover path, offset/limit range, offset-only, long bash
truncation, and custom JSON truncation. Observed `tfc_read` / `tfc_read_rng` /
`tfc_read_off` / `tfc_write` / `tfc_edit` / `tfc_bash` / `tfc_bash_long` /
`tfc_grep` / `tfc_find` / `tfc_ls` / `tfc_custom` are exact. First
Friend-MachineD freeze **5.86×** (14.1 / 2.4 µs), ceiling 8.0. Same commit no
optimize.

### Pair 156 — `cli_selectors` (tree_entry_display_text)

| metric | cadr | pi |
|---|---|---|
| `tree_entry_display_text` | `tree-selector-entry-display-text` | `getEntryDisplayText` (`tree-selector.ts`) |

Entry row text only (themed): user/assistant empty+aborted, bash, compaction,
branch summary, label, tool-result read, custom message, selected bold.
Observed `ted_user` / `ted_asst` / `ted_empty` / `ted_abort` / `ted_bash` /
`ted_compact` / `ted_branch` / `ted_label` / `ted_tool` / `ted_custom` /
`ted_sel` are exact. First Friend-MachineD freeze **5.79×** (19.2 / 3.3 µs),
ceiling 8.0. Same commit no optimize.

### Pair 157 — `cli_selectors` (tree_prefix)

| metric | cadr | pi |
|---|---|---|
| `tree_prefix` | `tree-selector-prefix` | render prefix char loop (`tree-selector.ts`) |

Tree gutter/connector prefix only (no theme dim wrapper): branch/last
connectors, fold open/closed (⊟/⊞), gutter continuation, deep indent, virtual
root child under multiple roots. Observed `tp_branch` / `tp_last` / `tp_open` /
`tp_fold` / `tp_gutter` / `tp_deep` / `tp_vroot` are exact. First
Friend-MachineD freeze **0.48×** (4.2 / 8.9 µs), ceiling 8.0. Same commit no
optimize.

### Pair 158 — `cli_selectors` (tree_visual_nodes)

| metric | cadr | pi |
|---|---|---|
| `tree_visual_nodes` | `tree-selector-visual-nodes` | `recalculateVisualStructure` DFS (`tree-selector.ts`) |

Visible-tree indent/connector/gutter layout: single root+child, branch with two
children, multiple roots, single-child chain, deep branch. Observed `tvn_single`
/ `tvn_branch` / `tvn_multi` / `tvn_chain` / `tvn_deep` are exact. First
Friend-MachineD freeze **0.92×** (17.2 / 18.7 µs), ceiling 8.0. Same commit no
optimize.

### Pair 159 — `cli_selectors` (tree_horizontal_viewport)

| metric | cadr | pi |
|---|---|---|
| `tree_horizontal_viewport` | `tree-selector-horizontal-viewport` | `renderHorizontalViewport` (`tree-selector.ts`) |

Horizontal pan + truncate: short rows (no scroll), selected long-body scroll,
narrow width clip, no-selection no-scroll, ANSI body slice. Observed
`thv_short` / `thv_scroll` / `thv_narrow` / `thv_noselect` / `thv_ansi` are
exact. First Friend-MachineD freeze **0.89×** (66.2 / 74.5 µs), ceiling 8.0.
Same commit no optimize.

### Pair 160 — `cli_selectors` (tree_help_keys)

| metric | cadr | pi |
|---|---|---|
| `tree_help_keys` | `tree-selector-help-keys` | `formatHelpKeys` (`tree-selector.ts`) |

Tree help keybinding text compaction: move/page/branch/copy/filter/cycle groups
plus custom `ctrl+k` up override. Observed `thk_move` / `thk_page` / `thk_branch`
/ `thk_copy` / `thk_filters` / `thk_cycle` / `thk_custom` are exact. First
Friend-MachineD freeze **4.56×** (190.2 / 41.7 µs), ceiling 8.0. Same commit no
optimize.

**sessions.lisp gutter note:** `session-selector-gutter-prefixes` /
`session-selector-node-prefix` remain unpaired — gate attempt `sgp_simple` pi
`   └─ ` vs cadr `└─ ` (ancestor padding); measure-only, no optimize this commit.

### Pair 161 — `cli_selectors` (tree_help_lines)

| metric | cadr | pi |
|---|---|---|
| `tree_help_lines` | `tree-selector-help-lines` | `TreeHelp.render` (`tree-selector.ts`) |

Tree help footer: chunk-aware line packing with muted theme at widths 80/50/30/20/12.
Observed `thl_w80` / `thl_w50` / `thl_w30` / `thl_w20` / `thl_w12` are exact. First
Friend-MachineD freeze **3.33×** (979.6 / 293.8 µs), ceiling 8.0. Same commit no
optimize.

### Pair 162 — `cli_selectors` (tree_active_path)

| metric | cadr | pi |
|---|---|---|
| `tree_active_path` | `tree-selector-active-path` | `buildActivePath` (`tree-selector.ts`) |

Leaf-to-root ancestor walk on branching session-tree fixtures. Observed `tap_leaf` /
`tap_mid` / `tap_root` / `tap_nil` / `tap_missing` are exact. First Friend-MachineD
freeze **2.43×** (11.8 / 4.8 µs), ceiling 8.0. Same commit no optimize.

### Pair 163 — `cli_selectors` (tree_nearest_visible_id)

| metric | cadr | pi |
|---|---|---|
| `tree_nearest_visible_id` | `tree-selector-nearest-visible-id` | `findNearestVisibleIndex` id walk (`tree-selector.ts`) |

Walk from target toward root until a visible id is found; fallback to last visible id.
Observed `tnvi_hit` / `tnvi_ancestor` / `tnvi_branch` / `tnvi_fallback` / `tnvi_missing` /
`tnvi_nil` are exact. First Friend-MachineD freeze **2.34×** (14.9 / 6.4 µs), ceiling 8.0.
Same commit no optimize.

### Pair 164 — `cli_selectors` (tree_prioritize_active)

| metric | cadr | pi |
|---|---|---|
| `tree_prioritize_active` | `tree-selector-prioritize-active` | `flattenTree` active-branch ordering (`tree-selector.ts`) |

Reorder flat entries so active-path ids precede siblings on branching fixtures.
Observed `tpa_leaf_a` / `tpa_leaf_b` / `tpa_root` / `tpa_nil` are exact. First
Friend-MachineD freeze **1.83×** (16.3 / 8.9 µs), ceiling 8.0. Same commit no optimize.

### Pair 165 — `cli_selectors` (tree_rebuild_visible_maps)

| metric | cadr | pi |
|---|---|---|
| `tree_rebuild_visible_maps` | `tree-selector-rebuild-visible-maps` | `recalculateVisualStructure` visible parent/children maps (`tree-selector.ts`) |

Rebuild visible parent/children maps on branching fixtures with full, sparse, and
sibling-skipping subsets. Observed `trvm_full` / `trvm_sparse` / `trvm_branch_b` /
`trvm_single` / `trvm_siblings` are exact. First Friend-MachineD freeze **1.49×**
(41.3 / 27.7 µs), ceiling 8.0. Same commit no optimize.

### Pair 166 — `cli_selectors` (tree_apply_filter)

| metric | cadr | pi |
|---|---|---|
| `tree_apply_filter` | `tree-selector-apply-filter` | `applyFilter` (`tree-selector.ts`) |

Filter/fold/query pass over mixed-type tree fixtures; preserves selection via
nearest visible ancestor. Observed `taf_default` / `taf_user_only` / `taf_no_tools` /
`taf_query` / `taf_fold` / `taf_reselect` are exact. First Friend-MachineD freeze
**3.60×** (71.6 / 19.9 µs), ceiling 8.0. Same commit no optimize.

### Pair 167 — `cli_selectors` (tree_render_lines)

| metric | cadr | pi |
|---|---|---|
| `tree_render_lines` | `tree-selector-render-lines` | `TreeList.render` (`tree-selector.ts`) |

Full tree list render on branching fixtures: wide/mid/narrow width, fold, empty,
short viewport. Observed `trl_wide` / `trl_mid` / `trl_narrow` / `trl_fold` /
`trl_empty` / `trl_short` are exact. First Friend-MachineD freeze **0.83×**
(1,236.6 / 1,484.2 µs), ceiling 8.0. Same commit no optimize.

### Pair 168 — `cli_selectors` (tree_move)

| metric | cadr | pi |
|---|---|---|
| `tree_move` | `tree-selector-move` | `TreeList` selection index wrap (`tree-selector.ts`) |

Visible-id selection move on branching fixtures: step, wrap, page delta, empty.
Observed `tm_down` / `tm_up` / `tm_wrap_up` / `tm_wrap_down` / `tm_page` /
`tm_page_neg` / `tm_empty` are exact. First Friend-MachineD freeze **1.74×**
(331.4 / 190.3 µs), ceiling 8.0. Same commit no optimize.

### Pair 169 — `cli_selectors` (tree_fold_or_up)

| metric | cadr | pi |
|---|---|---|
| `tree_fold_or_up` | `tree-selector-fold-or-up` | `foldOrUp` handleInput (`tree-selector.ts`) |

Fold branch point or jump to branch-segment start on branching fixtures.
Observed `tfo_fold` / `tfo_leaf` / `tfo_mid` / `tfo_prefold` / `tfo_root` /
`tfo_branch_b` are exact. First Friend-MachineD freeze **1.76×**
(316.9 / 179.6 µs), ceiling 8.0. Same commit no optimize.

### Pair 170 — `cli_selectors` (tree_unfold_or_down)

| metric | cadr | pi |
|---|---|---|
| `tree_unfold_or_down` | `tree-selector-unfold-or-down` | `unfoldOrDown` handleInput (`tree-selector.ts`) |

Unfold folded branch or move down on branching fixtures.
Observed `tuod_unfold` / `tuod_leaf` / `tuod_mid` / `tuod_prefold` / `tuod_root` /
`tuod_branch_b` are exact. First Friend-MachineD freeze **1.82×**
(324.4 / 178.0 µs), ceiling 8.0. Same commit no optimize.

### Pair 171 — `cli_selectors` (tree_branch_segment_id)

| metric | cadr | pi |
|---|---|---|
| `tree_branch_segment_id` | `tree-selector-branch-segment-id` | `findBranchSegmentStart` (`tree-selector.ts`) |

Branch-segment start lookup up/down on branching fixtures.
Observed `tbs_down_branch` / `tbs_down_leaf` / `tbs_down_mid` / `tbs_up_mid` /
`tbs_up_root` / `tbs_up_branch_b` are exact. First Friend-MachineD freeze **1.82×**
(264.9 / 145.6 µs), ceiling 8.0. Same commit no optimize.

### Pair 172 — `cli_selectors` (tree_set_query)

| metric | cadr | pi |
|---|---|---|
| `tree_set_query` | `tree-selector-set-query` | `TreeList` searchQuery + `applyFilter` (`tree-selector.ts`) |

Search query update clears folded state and reapplies filter on apply-filter fixtures.
Observed `tsq_empty` / `tsq_branch` / `tsq_fold_clear` / `tsq_miss` / `tsq_pinned` /
`tsq_multi` are exact. First Friend-MachineD freeze **0.66×**
(88.9 / 135.2 µs), ceiling 8.0. Same commit no optimize.

### Pair 173 — `cli_selectors` (tree_set_filter)

| metric | cadr | pi |
|---|---|---|
| `tree_set_filter` | `tree-selector-set-filter` | `TreeList` filterMode + `applyFilter` (`tree-selector.ts`) |

Filter mode update clears folded state and reapplies filter on apply-filter fixtures.
Observed `tsf_default` / `tsf_user_only` / `tsf_no_tools` / `tsf_fold_clear` /
`tsf_labeled_only` / `tsf_reselect` are exact. First Friend-MachineD freeze **0.60×**
(71.4 / 119.0 µs), ceiling 8.0. Same commit no optimize.

### Pair 174 — `cli_selectors` (tree_copy_selected)

| metric | cadr | pi |
|---|---|---|
| `tree_copy_selected` | `tree-selector-copy-selected` | `copySelected` (`tree-selector.ts`) |

Copy selected entry text via callback on apply-filter fixtures.
Observed `tcs_user` / `tcs_assistant` / `tcs_tool` / `tcs_empty` / `tcs_label` /
`tcs_none` are exact. First Friend-MachineD freeze **2.87×**
(142.5 / 49.6 µs), ceiling 8.0. Same commit no optimize.

### Pair 175 — `cli_selectors` (tree_toggle_label_timestamps)

| metric | cadr | pi |
|---|---|---|
| `tree_toggle_label_timestamps` | `tree-selector-toggle-label-timestamps` | `showLabelTimestamps` toggle (`tree-selector.ts`) |

Toggle label-timestamp display flag and refresh status labels.
Observed `ttlt_off` / `ttlt_on` / `ttlt_twice` / `ttlt_notools` / `ttlt_labeled` /
`ttlt_thrice` are exact. First Friend-MachineD freeze **0.04×**
(4.3 / 118.4 µs), ceiling 8.0. Same commit no optimize.

### Pair 176 — `cli_selectors` (tree_start_label_edit)

| metric | cadr | pi |
|---|---|---|
| `tree_start_label_edit` | `tree-selector-start-label-edit` | `showLabelInput` (`tree-selector.ts`) |

Enter label-edit mode for selected entry on apply-filter fixtures.
Observed `tsle_pinned` / `tsle_plain` / `tsle_assistant` / `tsle_bookmark` /
`tsle_empty` / `tsle_noselect` are exact. First Friend-MachineD freeze **2.40×**
(150.8 / 62.9 µs), ceiling 8.0. Same commit no optimize.

### Pair 177 — `cli_selectors` (tree_confirm_label)

| metric | cadr | pi |
|---|---|---|
| `tree_confirm_label` | `tree-selector-confirm-label` | `LabelInput` onSubmit (`tree-selector.ts`) |

Confirm label edit: callback args, entry label, timestamp flag on apply-filter fixtures.
Observed `tclf_set` / `tclf_rename` / `tclf_clear` / `tclf_trim` / `tclf_whitespace` /
`tclf_nop` are exact. First Friend-MachineD freeze **4.37×**
(260.2 / 59.5 µs), ceiling 8.0. Same commit no optimize.

### Pair 178 — `cli_selectors` (tree_cancel_label)

| metric | cadr | pi |
|---|---|---|
| `tree_cancel_label` | `tree-selector-cancel-label` | `LabelInput` onCancel (`tree-selector.ts`) |

Cancel label edit: mode/list, edit cleared, label unchanged on apply-filter fixtures.
Observed `tclc_pinned` / `tclc_plain` / `tclc_assistant` / `tclc_bookmark` /
`tclc_dirty` / `tclc_nop` are exact. First Friend-MachineD freeze **1.57×**
(214.6 / 136.7 µs), ceiling 8.0. Same commit no optimize.

### Pair 179 — `cli_selectors` (tree_handle_raw_input)

| metric | cadr | pi |
|---|---|---|
| `tree_handle_raw_input` | `tree-selector-handle-raw-input` | `TreeList.handleInput` (`tree-selector.ts`) |

Keybinding dispatch: copy, edit label, fold, filter toggle, label cancel, noop.
Observed `thri_copy` / `thri_edit` / `thri_fold` / `thri_notools` /
`thri_lcancel` / `thri_nop` are exact. First Friend-MachineD freeze **4.06×**
(1068.1 / 263.3 µs), ceiling 8.0. Same commit no optimize.

### Pair 180 — `cli_selectors` (tree_handle_event)

| metric | cadr | pi |
|---|---|---|
| `tree_handle_event` | `tree-selector-handle-event` | `TreeList.handleInput` (`tree-selector.ts`) |

Structured event dispatch: move, select, search text, escape clear/cancel, noop.
Observed `the_down` / `the_up` / `the_enter` / `the_text` / `the_esc_clear` /
`the_nop` are exact. First Friend-MachineD freeze **0.73×**
(245.2 / 333.8 µs), ceiling 8.0. Same commit no optimize.

### Pair 181 — `cli_selectors` (tree_handle_label_event)

| metric | cadr | pi |
|---|---|---|
| `tree_handle_label_event` | `tree-selector-handle-label-event` | `LabelInput.handleInput` (`tree-selector.ts`) |

Label-mode structured events: text append, backspace, confirm, cancel, noop.
Observed `thle_text` / `thle_bs` / `thle_enter` / `thle_escape` / `thle_nop` are
exact. First Friend-MachineD freeze **0.69×**
(159.7 / 232.7 µs), ceiling 8.0. Same commit no optimize.

### Pair 182 — `cli_selectors` (tree_selected_entry)

| metric | cadr | pi |
|---|---|---|
| `tree_selected_entry` | `tree-selector-selected-entry` | `TreeList.getSelectedNode` (`tree-selector.ts`) |

Selected entry lookup: id, type, role, label, text on apply-filter fixtures.
Observed `tse_pinned` / `tse_plain` / `tse_assistant` / `tse_label` / `tse_empty` /
`tse_noselect` are exact. First Friend-MachineD freeze **5.14×**
(199.5 / 38.8 µs), ceiling 8.0. Same commit no optimize.

### Pair 183 — `cli_selectors` (tree_select_id)

| metric | cadr | pi |
|---|---|---|
| `tree_select_id` | `tree-selector-select-id` | `TreeList` visible-id selection (`tree-selector.ts`) |

Select visible entry by id; noop when target hidden or missing.
Observed `tsid_hit` / `tsid_same` / `tsid_miss` / `tsid_label` / `tsid_filter_miss` /
`tsid_fold_miss` are exact. First Friend-MachineD freeze **4.64×**
(217.0 / 46.7 µs), ceiling 8.0. Same commit no optimize.

### Pair 184 — `cli_selectors` (tree_visible_ids)

| metric | cadr | pi |
|---|---|---|
| `tree_visible_ids` | `tree-selector-visible-ids` | `TreeList.filteredNodes` ids (`tree-selector.ts`) |

Visible id list after filter/query/fold; comma-separated encoding reuses apply-filter
first field.
Observed `tvi_default` / `tvi_user_only` / `tvi_no_tools` / `tvi_query` / `tvi_fold` /
`tvi_all` are exact. First Friend-MachineD freeze **5.78×**
(82.1 / 14.2 µs), ceiling 8.0. Same commit no optimize.

### Pair 185 — `cli_selectors` (tree_selected_id)

| metric | cadr | pi |
|---|---|---|
| `tree_selected_id` | `tree-selector-selected-id` | `TreeList.filteredNodes` selected id (`tree-selector.ts`) |

Selected id accessor after fixture state setup; `null` when no selection.
Observed `tslid_pinned` / `tslid_plain` / `tslid_assistant` / `tslid_label` / `tslid_empty` /
`tslid_noselect` are exact. First Friend-MachineD freeze **2.50×**
(213.4 / 85.3 µs), ceiling 8.0. Same commit no optimize.

### Pair 186 — `cli_selectors` (tree_entry_map)

| metric | cadr | pi |
|---|---|---|
| `tree_entry_map` | `tree-selector-entry-map` | id→entry map from flat entries (`tree-selector.ts`) |

Build id lookup table; encoded as sorted `id|type|parent` joined by `;`.
Observed `tem_branching` / `tem_filter` / `tem_empty` / `tem_solo` / `tem_single` are exact.
First Friend-MachineD freeze **2.76×**
(11.6 / 4.2 µs), ceiling 8.0. Same commit no optimize.

### Pair 187 — `cli_selectors` (tree_order_entries)

| metric | cadr | pi |
|---|---|---|
| `tree_order_entries` | `tree-selector-order-entries` | DFS entry order with active-path sibling priority (`tree-selector.ts`) |

Pre-filter entry ordering for tree flatten; encoded as comma-separated ids.
Observed `toe_leaf_a` / `toe_leaf_b` / `toe_root` / `toe_nil` / `toe_filter` are exact.
First Friend-MachineD freeze **1.21×**
(38.4 / 31.7 µs), ceiling 8.0. Same commit no optimize.

### Pair 188 — `cli_selectors` (tree_iso_timestamp)

| metric | cadr | pi |
|---|---|---|
| `tree_iso_timestamp` | `tree-selector-iso-timestamp` | local `YYYY-MM-DDTHH:MM:SS` formatter (`tree-selector.ts`) |

ISO timestamp without zone/ms; fixtures run under `TZ=UTC`.
Observed `tis_afternoon` / `tis_epoch` / `tis_eoy` / `tis_midnight` / `tis_noon` are exact.
First Friend-MachineD freeze **1.43×**
(6.1 / 4.3 µs), ceiling 8.0. Same commit no optimize.

### Pair 189 — `cli_selectors` (tree_help_key)

| metric | cadr | pi |
|---|---|---|
| `tree_help_key` | `tree-selector-help-key` | keybinding key lookup with fallbacks (`tree-selector.ts`) |

Single binding name → raw key string; `null` when unbound.
Observed `thkey_up` / `thkey_fold` / `thkey_filter_all` / `thkey_left` / `thkey_custom_up` /
`thkey_missing` are exact. First Friend-MachineD freeze **1.70×**
(58.4 / 34.4 µs), ceiling 8.0. Same commit no optimize.

### Pair 190 — `cli_selectors` (tree_app_key_p)

| metric | cadr | pi |
|---|---|---|
| `tree_app_key_p` | `tree-selector-app-key-p` | `selector-keybinding-matches-p` on tree keybindings (`common.lisp`) |

Keybinding match predicate including modified CSI arrows; encoded `true`/`false`.
Observed `tapk_copy_hit` / `tapk_copy_miss` / `tapk_up_hit` / `tapk_filter_hit` / `tapk_csi_up` /
`tapk_garbage` are exact. First Friend-MachineD freeze **0.63×**
(74.8 / 119.1 µs), ceiling 8.0. Same commit no optimize.

### Pair 191 — `cli_selectors` (project_trust_options)

| metric | cadr | pi |
|---|---|---|
| `project_trust_options` | `project-trust-options` | `getProjectTrustOptions` (`trust-manager.ts`) |

Trust selector option list; encoded as `trusted\|saved_path\|updates` per option (fixture-relative paths).
Observed `pto_child` / `pto_single` are exact. First Friend-MachineD freeze **1.16×**
(72.9 / 62.9 µs), ceiling 8.0. Same commit no optimize.

### Pair 192 — `cli_selectors` (trust_selector_selection)

| metric | cadr | pi |
|---|---|---|
| `trust_selector_selection` | `trust-selector-selection` | `getProjectTrustOptions` index (`trust-manager.ts`) |

Trust selector selection at a fixed index; encoded as `trusted|updates` or `null`.
Observed `tss_child_trust` / `tss_child_parent` / `tss_child_distrust` /
`tss_single_trust` / `tss_single_distrust` are exact. First Friend-MachineD freeze **3.78×**
(242.4 / 64.1 µs), ceiling 8.0. Same commit no optimize.

### Pair 193 — `cli_selectors` (trust_decision_description)

| metric | cadr | pi |
|---|---|---|
| `trust_decision_description` | `trust-decision-description` | `formatDecision` (`trust-selector.ts`) |

Saved trust decision label for the selector header; fixture-relative paths.
Observed `tdd_none` / `tdd_child_local` / `tdd_child_inherited` /
`tdd_single_untrusted` are exact. First Friend-MachineD freeze **2.36×**
(156.7 / 66.4 µs), ceiling 8.0. Same commit no optimize.

### Pair 194 — `cli_selectors` (trust_selector_move)

| metric | cadr | pi |
|---|---|---|
| `trust_selector_move` | `trust-selector-move` | wrap index on `getProjectTrustOptions` count |

Trust selector list navigation; encoded as resulting selected index.
Observed `tsm_child_down` / `tsm_child_up` / `tsm_child_wrap_up` /
`tsm_child_wrap_down` / `tsm_child_page` / `tsm_single_down` / `tsm_single_wrap`
are exact. First Friend-MachineD freeze **2.46×**
(328.1 / 133.3 µs), ceiling 8.0. Same commit no optimize.

### Pair 195 — `cli_selectors` (trust_selector_handle_event)

| metric | cadr | pi |
|---|---|---|
| `trust_selector_handle_event` | `trust-selector-handle-event` | event dispatch on trust selector state |

Trust selector input events; encoded as `action|selection|null|selectedIndex`.
Observed `tshe_child_down` / `tshe_child_up` / `tshe_child_enter` /
`tshe_child_k` / `tshe_child_bad` / `tshe_child_esc` / `tshe_child_nop`
are exact. First Friend-MachineD freeze **2.35×**
(333.3 / 142.1 µs), ceiling 8.0. Same commit no optimize.

### Pair 196 — `cli_selectors` (trust_selector_handle_raw_input)

| metric | cadr | pi |
|---|---|---|
| `trust_selector_handle_raw_input` | `trust-selector-handle-raw-input` | raw-input dispatch on trust selector state |

Trust selector raw key input; encoded as `action|selection|null|selectedIndex|consumed`.
Observed `tshri_child_down` / `tshri_child_k` / `tshri_child_enter` /
`tshri_child_esc` / `tshri_child_bad` / `tshri_child_j` / `tshri_child_confirm`
are exact. First Friend-MachineD freeze **2.98×**
(693.8 / 233.2 µs), ceiling 8.0. Same commit no optimize.

### Pair 197 — `cli_selectors` (trust_selector_ui_state)

| metric | cadr | pi |
|---|---|---|
| `trust_selector_ui_state` | `trust-selector-ui-encoded` | structural UI state digest |

Trust selector UI state; encoded as `saved_decision|session_trusted|option_rows`
with each option row `label|sel/nosel|saved/nosaved`. Parent-folder labels use
fixture-relative path encoding. Observed `rts_child_default` / `rts_child_saved` /
`rts_child_inherited` / `rts_child_distrust` / `rts_single` are exact. First
Friend-MachineD freeze **2.27×** (394.9 / 173.7 µs), ceiling 8.0. Same commit
no optimize.

### Pair 198 — `cli_selectors` (oauth_option_status_label)

| metric | cadr | pi |
|---|---|---|
| `oauth_option_status_label` | `oauth-option-status-label` | `formatStatusIndicator` plain label |

OAuth selector status text; unconfigured, type mismatch, configured,
stored credential, env source, and custom source fixtures. Observed
`oosl_none` / `oosl_api_mismatch` / `oosl_oauth_mismatch` /
`oosl_oauth_configured` / `oosl_stored` / `oosl_env` / `oosl_custom`
are exact. First Friend-MachineD freeze **2.46×** (2.1 / 0.8 µs),
ceiling 8.0. Same commit no optimize.

### Pair 199 — `cli_selectors` (credential_entry_auth_type)

| metric | cadr | pi |
|---|---|---|
| `credential_entry_auth_type` | `credential-entry-auth-type` | logout credential type normalization |

Maps stored credential kind strings/symbols to `oauth` or `api_key`.
Observed `ceat_oauth` / `ceat_api_key` / `ceat_api_key_hyphen` /
`ceat_oauth_sym` / `ceat_api_key_sym` / `ceat_oauth_mixed` /
`ceat_api_key_upper` are exact. First Friend-MachineD freeze **1.87×**
(0.6 / 0.3 µs), ceiling 8.0. Same commit no optimize.

### Pair 200 — `cli_selectors` (oauth_environment_source_p)

| metric | cadr | pi |
|---|---|---|
| `oauth_environment_source_p` | `oauth-environment-source-p` | `formatStatusIndicator` env-source regex |

Detects uppercase env-var credential sources (`ANTHROPIC_API_KEY`, comma
lists). Observed `oesp_nil` / `oesp_oauth` / `oesp_single_env` /
`oesp_multi_env` / `oesp_runtime` / `oesp_stored` / `oesp_lower` are exact.
First Friend-MachineD freeze **3.51×** (1.2 / 0.3 µs), ceiling 8.0. Same
commit no optimize.

### Pair 201 — `cli_selectors` (oauth_selector_selection)

| metric | cadr | pi |
|---|---|---|
| `oauth_selector_selection` | `oauth-selector-selection` | `filteredProviders[selectedIndex]` |

OAuth selector selected provider; encoded as `id|auth_type`. Observed
`oss_first` / `oss_second` / `oss_third` / `oss_filter_hit` /
`oss_filter_miss` are exact. First Friend-MachineD freeze **3.80×**
(103.4 / 27.2 µs), ceiling 8.0. Same commit no optimize.

### Pair 202 — `cli_selectors` (oauth_selector_apply_filter)

| metric | cadr | pi |
|---|---|---|
| `oauth_selector_apply_filter` | `oauth-selector-apply-filter` | `filterProviders` |

OAuth selector fuzzy filter; encoded as `filtered_count|selected` (selection
resets to 0). Observed `osaf_all` / `osaf_open` / `osaf_miss` / `osaf_anth` /
`osaf_google` are exact. First Friend-MachineD freeze **3.84×**
(113.2 / 29.5 µs), ceiling 8.0. Same commit no optimize.

### Pair 203 — `cli_selectors` (oauth_selector_handle_event)

| metric | cadr | pi |
|---|---|---|
| `oauth_selector_handle_event` | `oauth-selector-handle-event` | `handleInput` event dispatch |

OAuth selector event dispatch; encoded as
`action|value|selected|query`. Observed `oshe_down` / `oshe_up` /
`oshe_enter` / `oshe_esc` / `oshe_text` / `oshe_backspace` are exact.
First Friend-MachineD freeze **1.22×** (138.2 / 113.6 µs), ceiling 8.0.
Same commit no optimize.

### Pair 204 — `cli_selectors` (oauth_selector_handle_raw_input)

| metric | cadr | pi |
|---|---|---|
| `oauth_selector_handle_raw_input` | `oauth-selector-handle-raw-input` | `handleInput` raw key dispatch |

OAuth selector raw key input; encoded as
`action|value|selectedIndex|consumed`. Observed `oshri_down` / `oshri_j` /
`oshri_enter` / `oshri_esc` / `oshri_bad` / `oshri_o` / `oshri_confirm`
are exact. First Friend-MachineD freeze **5.02×** (691.4 / 137.7 µs),
ceiling 8.0. Same commit no optimize.

### Pair 205 — `cli_selectors` (oauth_selector_search_text)

| metric | cadr | pi |
|---|---|---|
| `oauth_selector_search_text` | `oauth-selector-search-text` | `filterProviders` search text |

OAuth selector fuzzy-filter search text; `name id authType method`. Observed
`osst_oauth` / `osst_api` / `osst_no_method` / `osst_api_plain` are exact.
First Friend-MachineD freeze **1.52×** (9.5 / 6.2 µs), ceiling 8.0. Same
commit no optimize.

### Pair 206 — `cli_selectors` (login_auth_type_route)

| metric | cadr | pi |
|---|---|---|
| `login_auth_type_route` | `login-auth-type-route` | `showLoginAuthTypeSelector` routing |

Login auth-type routing: `none|…`, `direct|id|auth_type`, or
`select|title|labels…`. Observed `latr_none` / `latr_oauth` / `latr_api` /
`latr_both` / `latr_generic` are exact. First Friend-MachineD freeze
**3.44×** (3.8 / 1.1 µs), ceiling 8.0. Gate used `--only-enforce` for this
metric only (full-suite ceiling noise on unrelated oauth metrics). Same
commit no optimize.

### Pair 207 — `cli_selectors` (login_provider_options)

| metric | cadr | pi |
|---|---|---|
| `login_provider_options` | `login-provider-options` | `getLoginProviderOptions` |

Login provider projection from definitions: auth-type filter, oauth
metadata labels, structured API-key flag, optional status. Observed
`lpo_all` / `lpo_oauth` / `lpo_api` / `lpo_labeled` / `lpo_status` are
exact. First Friend-MachineD freeze **0.87×** (14.8 / 17.1 µs), ceiling
8.0. Gate used `--only-enforce`. Same commit no optimize.

### Pair 208 — `cli_selectors` (logout_provider_options)

| metric | cadr | pi |
|---|---|---|
| `logout_provider_options` | `logout-provider-options` | `getLogoutProviderOptions` |

Logout provider projection from stored credentials: definition name
lookup, unknown-provider fallback, sorted options with stored-credential
status. Observed `lgo_empty` / `lgo_mixed` / `lgo_unknown` / `lgo_sorted`
are exact. First Friend-MachineD freeze **2.71×** (10.4 / 3.8 µs), ceiling
8.0. Gate used `--only-enforce`. Same commit no optimize.

### Pair 209 — `cli_selectors` (login_method_selector_handle_event)

| metric | cadr | pi |
|---|---|---|
| `login_method_selector_handle_event` | `login-method-selector-handle-event` | `ExtensionSelectorComponent` event dispatch |

Login method selector event routing: wrap/cancel on clear/interrupt,
select-list navigation and selection. Observed `lmhe_down` / `lmhe_up` /
`lmhe_enter_oauth` / `lmhe_enter_api` / `lmhe_esc` / `lmhe_clear` /
`lmhe_interrupt` are exact. First Friend-MachineD freeze **0.97×**
(4.2 / 4.3 µs), ceiling 8.0. Gate used `--only-enforce`. Same commit no
optimize.

### Pair 210 — `cli_selectors` (oauth_selector_move)

| metric | cadr | pi |
|---|---|---|
| `oauth_selector_move` | `oauth-selector-move` | `selector-frame-move-index` wrap (fixtures avoid pi clamp boundary) |

OAuth selector filtered-list index move (wrap). Observed `osmv_0_1` /
`osmv_2_m1` / `osmv_1_1` / `osmv_1_m1` / `osmv_filter` are exact. First
Friend-MachineD freeze **27.34×** (83.8 / 3.1 µs), ceiling 50.0. Gate
used `--only-enforce`. Same commit no optimize.

### Pair 211 — `cli_selectors` (oauth_option_status_rendered)

| metric | cadr | pi |
|---|---|---|
| `oauth_option_status_rendered` | `oauth-option-status-rendered` | `formatStatusIndicator` themed output |

OAuth option status themed indicator (muted/warning/success). Observed
`oosr_none` / `oosr_api_mismatch` / `oosr_oauth_mismatch` /
`oosr_oauth_configured` / `oosr_stored` / `oosr_env` / `oosr_custom` are
exact. First Friend-MachineD freeze **10.02×** (13.9 / 1.4 µs), ceiling
15.0. Gate used `--only-enforce`. Same commit no optimize.

### Pair 212 — `cli_selectors` (api_key_input_state_handle_event)

| metric | cadr | pi |
|---|---|---|
| `api_key_input_state_handle_event` | `api-key-input-state-handle-event` | `LoginDialogComponent` api key prompt dispatch |

API key overlay event routing: cancel on escape/clear/interrupt, text
entry, backspace, empty submit, key submit. Observed `akhe_esc` /
`akhe_clear` / `akhe_text` / `akhe_bs` / `akhe_enter_empty` /
`akhe_enter_key` / `akhe_interrupt` are exact. First Friend-MachineD freeze
**1.66×** (7.0 / 4.2 µs), ceiling 8.0. Gate used `--only-enforce`. Same
commit no optimize.

### Pair 213 — `cli_selectors` (login_method_selector_ui_state)

| metric | cadr | pi |
|---|---|---|
| `login_method_selector_ui_state` | `render-login-method-selector` | `ExtensionSelectorComponent` UI state |

Login method selector UI digest (title/selection/items/hints; render
exercised). Observed `lmsui_default` / `lmsui_sel1` / `lmsui_title` /
`lmsui_narrow` / `lmsui_mid` are exact. First Friend-MachineD freeze
**10.07×** (622.6 / 61.8 µs), ceiling 12.0. Gate used `--only-enforce`.
Same commit no optimize.

### Pair 214 — `cli_selectors` (api_key_input_ui_state)

| metric | cadr | pi |
|---|---|---|
| `api_key_input_ui_state` | `render-api-key-input-state` | `LoginDialogComponent` showPrompt UI state |

API key overlay UI digest (title/masked length/prompt/hints; render
exercised). Observed `akiui_empty` / `akiui_key` / `akiui_openai` /
`akiui_narrow` / `akiui_long` are exact. First Friend-MachineD freeze
**4.86×** (263.5 / 54.2 µs), ceiling 8.0. Gate used `--only-enforce`.
Same commit no optimize.

### Pair 215 — `cli_selectors` (oauth_selector_ui_state)

| metric | cadr | pi |
|---|---|---|
| `oauth_selector_ui_state` | `render-oauth-selector` | `OauthSelectorComponent` UI state |

OAuth selector UI digest (mode/title/selection/query/items/empty; render
exercised). Observed `osui_default` / `osui_sel2` / `osui_filter` /
`osui_miss` / `osui_logout_empty` are exact. First Friend-MachineD freeze
**24.66×** (372.1 / 15.1 µs), ceiling 35.0. Gate used `--only-enforce`.
Same commit no optimize.

### Pair 216 — `cli_selectors` (model_selector_search_text)

| metric | cadr | pi |
|---|---|---|
| `model_selector_search_text` | `model-selector-search-text` | `getModelSelectorSearchText` |

Model selector fuzzy-search text (provider-prefixed, no bare id lead).
Observed `msst_openai` / `msst_anthropic` / `msst_codex` / `msst_openrouter` /
`msst_google` are exact. First Friend-MachineD freeze **6.78×** (5.6 / 0.8 µs),
ceiling 8.0. Gate used `--only-enforce`. Same commit no optimize.

### Pair 217 — `cli_selectors` (qualified_model_id)

| metric | cadr | pi |
|---|---|---|
| `qualified_model_id` | `qualified-model-id` | `provider/id` label |

Provider-qualified model id string (`provider/id`, lowercase provider).
Observed `qmid_openai` / `qmid_anthropic` / `qmid_codex` / `qmid_openrouter` /
`qmid_google` are exact. First Friend-MachineD freeze **7.65×** (2.1 / 0.3 µs),
ceiling 8.0. Gate used `--only-enforce`. Same commit no optimize.

### Pair 218 — `cli_selectors` (model_selector_apply_filter)

| metric | cadr | pi |
|---|---|---|
| `model_selector_apply_filter` | `model-selector-apply-filter` | `filterModels` fuzzy slice |

Model selector fuzzy filter over active catalog (count|selected digest).
Observed `msaf_all` / `msaf_gpt` / `msaf_miss` / `msaf_anth` / `msaf_google`
are exact. First Friend-MachineD freeze **5.53×** (130.9 / 23.7 µs), ceiling
8.0. Gate used `--only-enforce`. Same commit no optimize.

### Pair 219 — `cli_selectors` (model_selector_move)

| metric | cadr | pi |
|---|---|---|
| `model_selector_move` | `model-selector-move` | `handleInput` up/down wrap |

Model selector list wrap move over filtered catalog (selected index digest).
Observed `msmv_0_1` / `msmv_2_m1` / `msmv_1_1` / `msmv_1_m1` / `msmv_filter`
are exact. First Friend-MachineD freeze **18.60×** (102.3 / 5.5 µs), ceiling
20.0. Gate used `--only-enforce`. Same commit no optimize.

### Pair 220 — `cli_selectors` (model_selector_handle_event)

| metric | cadr | pi |
|---|---|---|
| `model_selector_handle_event` | `model-selector-handle-event` | event dispatch |

Model selector input events (action|model-id|selected digest). Observed
`mshe_down` / `mshe_up` / `mshe_enter` / `mshe_esc` / `mshe_text` / `mshe_bs`
are exact. First Friend-MachineD freeze **5.37×** (147.6 / 27.5 µs), ceiling
8.0. Gate used `--only-enforce`. Same commit no optimize.

### Pair 221 — `cli_selectors` (model_selector_handle_raw_input)

| metric | cadr | pi |
|---|---|---|
| `model_selector_handle_raw_input` | `model-selector-handle-raw-input` | `handleInput` raw keys |
| `model_selector_set_query` | `model-selector-set-query` | `filterModels` query update |
| `model_selector_selected_model` | `model-selector-selected-model` | `filteredModels[selectedIndex]` |
| `model_selector_toggle_scope` | `model-selector-toggle-scope` | `handleInput` tab scope toggle |
| `model_selector_ui_state` | `render-model-selector` | `updateList` / render |
| `scoped_models_selector_set_query` | `scoped-models-selector-set-query` | `refresh` query clamp |
| `scoped_models_selector_move` | `scoped-models-selector-move` | `handleInput` up/down wrap |
| `scoped_models_selector_handle_raw_input` | `scoped-models-selector-handle-raw-input` | `handleInput` raw key dispatch |
| `scoped_models_selector_ui_state` | `render-scoped-models-selector` | `updateList` / render |
| `scoped_models_selector_counts` | `scoped-models-selector-counts` | `getFooterText` count logic |
| `scoped_models_selector_sorted_ids` | `scoped-models-sorted-ids` | `getSortedIds` |

### Pair 232 — `cli_selectors` (scoped_models_selector_counts)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_counts` | `scoped-models-selector-counts` | `getFooterText` count logic |

Scoped models footer counts (scope|enabled|unavailable|total digest). Observed
`smsc_all` / `smsc_partial` / `smsc_unavail` / `smsc_empty` / `smsc_single` are
exact. First Friend-MachineD freeze **43.32×** (158.5 / 3.7 µs), ceiling 55.0.
Gate used `--only-enforce`. Same commit no optimize.

### Pair 233 — `cli_selectors` (scoped_models_selector_sorted_ids)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_sorted_ids` | `scoped-models-sorted-ids` | `getSortedIds` |

Scoped models sorted id list (comma-joined qualified ids). Observed `smssi_all` /
`smssi_partial` / `smssi_single` / `smssi_empty` / `smssi_reorder` are exact.
First Friend-MachineD freeze **37.36×** (145.0 / 3.9 µs), ceiling 50.0. Gate used
`--only-enforce`. Same commit no optimize.
| `scoped_models_selector_toggle_selected` | `scoped-models-selector-toggle-selected` | `handleInput` confirm toggle |

### Pair 246 — `session_pipeline` (session_leaf_id)

| metric | cadr | pi |
|---|---|---|
| `session_leaf_id` | `session-leaf-id` (`src/cadr-agent/session/codec.lisp`) | `SessionManager.getLeafId` (`packages/coding-agent/src/core/session-manager.ts`) |

Shared `session.jsonl` fixture loaded once outside the timed loop. Timed work
is the production leaf-id accessor on the open session, not `session_load`.
Observed `leaf_id` stays exact. First Friend-MachineD freeze **0.74×**
(0.04 / 0.05 µs), ceiling 8.0 (microsecond-floor / variance). Gate used
`--only-enforce`. Same commit no optimize.

### Pair 247 — `text_truncation` (truncate_middle)

| metric | cadr | pi |
|---|---|---|
| `truncate_middle` | `truncate-harness-middle` | `truncateMiddle` (`packages/coding-agent/src/core/tools/truncate.ts`) |

4000-line pairing fixture. Keep head and tail lines with one
`... [N lines omitted] ...` marker between them under the same 2000-line /
50KB limits as head/tail. Observed `middle_output_lines` (410) /
`middle_output_bytes` (51057) / `middle_truncated_by` (lines) /
`middle_omitted_lines` (3591) / `middle_first_line_exceeds` (0) are exact.
First Friend-MachineD freeze **0.12×** (1777.8 / 14420.3 µs), ceiling 8.0.
cadr leads. Gate used `--only-enforce`. Same commit no optimize.

### Pair 244 — `provider_registry_defs` (definition_ids)

| metric | cadr | pi |
|---|---|---|
| `definition_ids` | `list-provider-definition-ids` | `getBuiltinProviders` (`packages/ai/src/providers/all.ts`) |

Enumerate built-in provider ids with a generated model catalog (excludes
radius). Observed `openai` / `anthropic` / `google` / `count` /
`sorted_digest` are exact. `unknown` stays on the lookup metric only.
First Friend-MachineD freeze **99.97×** (728.7 / 7.3 µs), ceiling 125.0
(bumped from 8.0 on first freeze). Gate used `--only-enforce`. Same commit
no optimize.

### Pair 245 — `agent_tool_loop` (tool_result_digest)

| metric | cadr | pi |
|---|---|---|
| `tool_result_digest` | `truncate-summary-tool-result` | `truncateForSummary` (`packages/coding-agent/src/core/compaction/utils.ts`) |

Leftover sibling of the `agent_tool_loop` hole. Time tool-result summary
truncation only, not `serializeConversation` or a live compact. Short /
exact-2000 / 2001-char / UTF-16 astral+suffix / empty fixtures. Do not
exact full truncated text. Observed `trd_short` / `trd_exact` / `trd_over` /
`trd_over_one` / `trd_utf16` / `trd_empty` are exact. First Friend-MachineD
freeze **107.57×** (289.4 / 2.7 µs), ceiling 125.0 (bumped from 50.0 on first
freeze). Gate used `--only-enforce`. Same commit no optimize.

### Pair 248 — `storage_journal` (journal_entry_count)

| metric | cadr | pi |
|---|---|---|
| `journal_entry_count` | `session-entry-count` | `getEntries().length` |

In-memory entry count on the written append journal (128 messages). Observed
`session_entry_count` is exact. First Friend-MachineD freeze **0.09×**
(0.22 / 2.4 µs), ceiling 8.0. cadr leads. Gate used `--only-enforce`. Same
commit no optimize.

### Pair 249 — `settings_load` (stored_auth_secrets)

| metric | cadr | pi |
|---|---|---|
| `stored_auth_secrets` | `stored-auth-secrets` | auth.json key/access/refresh scan |

Fixture auth.json, staged oauth auth.json, missing file, and bad JSON. Collect
stored key/access/refresh strings only; no env vars or provider config merge.
Observed `sas_missing` / `sas_fixture` / `sas_oauth` / `sas_bad` /
`sas_fixture_key` / `sas_oauth_access` / `sas_oauth_refresh` are exact. First
Friend-MachineD freeze **4.19×** (426.6 / 101.8 µs), ceiling 8.0. Gate used
`--only-enforce`. Same commit no optimize.

### Pair 250 — `cli_bootstrap_sessions` (bootstrap_auth)

| metric | cadr | pi |
|---|---|---|
| `bootstrap_auth` | `model-registry-login-options` | `getLoginProviderOptions` |

Built-in provider login options from a fresh model registry (no extension-only
native providers). Observed `option_count` / `auth_pairs_digest` /
`vertex_structured` / `bedrock_structured` are exact. First Friend-MachineD
freeze **0.64×** (3928.6 / 6134.0 µs), ceiling 8.0. cadr leads. Gate used
`--only-enforce`. Same commit no optimize.

### Pair 251 — `cli_extensions_install` (extension_discovery)

| metric | cadr | pi |
|---|---|---|
| `extension_discovery` | `discover-extension-sources` | `discoverAndLoadExtensions` path discovery (`packages/coding-agent/src/core/extensions/loader.ts`) |

Leftover sibling of the `cli_extensions_install` hole. Flat `.lisp`/subdir
`extension.lisp`, project `.cadr/extensions/`, global dir, explicit `-e`, plus
missing-dir probe. Observed `ed_n`/`ed_cli`/`ed_proj`/`ed_glob`/`ed_probe`/`ed_miss`
are exact. No load, no TUI. First Friend-MachineD freeze **1.98×**
(1954.5 / 987.2 µs), ceiling 8.0. pi leads. Gate used `--only-enforce`. Same
commit no optimize.

### Pair 252 — `package_manager` (manifest_parse)

| metric | cadr | pi |
|---|---|---|
| `manifest_parse` | `read-package-pi-manifest` | `readPiManifest` (`packages/coding-agent/src/core/pi-manifest.ts`) |

Leftover sibling of the `package_manager` hole. Time `package.json` `pi`
manifest read only, not `configured-package-records` or
`package-resource-paths`. Same local package fixture as `resolve`.
Observed `manifest_p` / `manifest_extensions` / `manifest_skills` /
`manifest_prompts` / `manifest_themes` are exact. First Friend-MachineD
freeze **5.09×** (52.9 / 10.4 µs), ceiling 8.0. Gate used
`--only-enforce`. Same commit no optimize.


### Pair 261 — `file_mutation_queue` (with_queue)

| metric | cadr | pi |
|---|---|---|
| `with_queue` | `with-file-mutation-queue` (`src/cadr-agent/file-mutation-queue.lisp`) | `withFileMutationQueue` (`packages/coding-agent/src/core/tools/file-mutation-queue.ts`) |

Leftover sibling of the `agent_tool_loop` hole on `file-mutation-queue.lisp`.
Timed work is canonical key resolution (existing path, missing path, alias) and
FIFO ticket acquire/release through `with-file-mutation-queue` — not write/edit
tools. Staged scratch dir with `target.txt` symlink alias, separate `other.txt`,
and missing path. Observed `fmq_alias_key` / `fmq_missing_key` / `fmq_other_key`
/ `fmq_fifo_sum` / `fmq_other_run` / `fmq_clean` are exact. First Friend-MachineD
freeze **0.55×**, ceiling 8.0. Gate used `--only-enforce`. Same commit no optimize.

### Pair 270 — `file_mutation_queue` (queue_key)

| metric | cadr | pi |
|---|---|---|
| `queue_key` | `file-mutation-queue-key` (`src/cadr-agent/file-mutation-queue.lisp`) | queue-map key (`realpath` / ENOENT `path.resolve`, same encoding as `packages/coding-agent/src/core/tools/file-mutation-queue.ts`) |

Leftover sibling of Pair 261 `with_queue` on the same `agent_tool_loop` hole.
Timed work is canonical key resolution only (existing path, symlink alias,
missing path, distinct sibling) — not `with-file-mutation-queue` and not
write/edit tools. Same staged scratch layout as `with_queue`. Observed
`fmqk_alias` / `fmqk_missing` / `fmqk_other` / `fmqk_n` are exact. First
n=5 freeze **1.08×** (169.3 / 156.2 µs) on host `cursor`, ceiling 8.0. Gate
used `--only-enforce`. Same commit no optimize.

### Pair 271 — `file_mutation_queue` (lock)

| metric | cadr | pi |
|---|---|---|
| `lock` | `file-mutation-queue-lock` (`src/cadr-agent/file-mutation-queue.lisp`) | `fileMutationQueues.get(key) ?? Promise.resolve()` / `set` after the same key encoding (`packages/coding-agent/src/core/tools/file-mutation-queue.ts`) |

Leftover sibling of Pair 261 `with_queue` and Pair 270 `queue_key` on the same
`agent_tool_loop` hole. Timed work is registry get-or-create after canonical
key (existing path, symlink alias, missing path, distinct sibling, repeat
lookup) — not `with-file-mutation-queue`, not write/edit tools. Same staged
scratch layout as `with_queue`. Observed `fmql_alias` / `fmql_other` /
`fmql_missing` / `fmql_repeat` / `fmql_n` are exact. First n=5 freeze
**1.24×** (183.3 / 148.0 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 272 — `file_mutation_queue` (register)

| metric | cadr | pi |
|---|---|---|
| `register` | `register-file-mutation` (`src/cadr-agent/file-mutation-queue.lisp`) | `withFileMutationQueue` ticket enqueue (`pending++` / next-promise chain after the same key encoding in `packages/coding-agent/src/core/tools/file-mutation-queue.ts`) |

Leftover sibling of Pair 261 `with_queue`, Pair 270 `queue_key`, and Pair 271
`lock` on the same `agent_tool_loop` hole. Timed work is FIFO ticket
allocation after canonical key (existing path, symlink alias, missing path,
distinct sibling) — not wait/fn/release, not `with-file-mutation-queue`, not
write/edit tools. Same staged scratch layout as `with_queue`. Observed
`fmqr_alias` / `fmqr_other` / `fmqr_pending` / `fmqr_ticket` / `fmqr_n` are
exact. First n=5 freeze **0.996×** (126.0 / 126.5 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 274 — `file_mutation_queue` (release_turn)

| metric | cadr | pi |
|---|---|---|
| `release_turn` | `release-file-mutation-turn` (`src/cadr-agent/file-mutation-queue.lisp`) | `withFileMutationQueue` finally / pending-- / delete-when-empty after wait (`packages/coding-agent/src/core/tools/file-mutation-queue.ts`) |

Leftover sibling of Pair 261 `with_queue`, Pair 270 `queue_key`, Pair 271
`lock`, Pair 272 `register`, and Pair 273 `wait_turn` on the same
`agent_tool_loop` hole. Timed work is FIFO ticket release after wait
(existing path, symlink alias leftover pending, missing path, distinct
sibling) — not fn, not `with-file-mutation-queue`, not write/edit tools.
Same staged scratch layout as `with_queue`. Observed `fmqe_serving` /
`fmqe_pending` / `fmqe_other` / `fmqe_missing` / `fmqe_n` are exact.
First n=5 freeze **0.918×** (155.2 / 169.1 µs) on host `cursor`, ceiling
8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 275 — `file_mutation_queue` (ensure_state)

| metric | cadr | pi |
|---|---|---|
| `ensure_state` | `ensure-file-mutation-queue-state` (`src/cadr-agent/file-mutation-queue.lisp`) | `fileMutationQueues.get(key) ?? set` given a canonical key (`packages/coding-agent/src/core/tools/file-mutation-queue.ts`) |

Leftover sibling of Pair 261 `with_queue`, Pair 270 `queue_key`, Pair 271
`lock`, Pair 272 `register`, Pair 273 `wait_turn`, and Pair 274
`release_turn` on the same `agent_tool_loop` hole. Timed work is registry
get-or-create after the key is already canonical (existing path, symlink
alias, missing path, distinct sibling, repeat lookup) — not path encoding,
not `with-file-mutation-queue`, not write/edit tools. Same staged scratch
layout as `with_queue`. Observed `fmqs_alias` / `fmqs_other` /
`fmqs_missing` / `fmqs_repeat` / `fmqs_n` are exact. First n=5 freeze
**0.879×** (109.2 / 124.3 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 276 — `harness_events` (emit)

| metric | cadr | pi |
|---|---|---|
| `emit` | `harness-event-bus-emit` (`src/cadr-agent/harness-events.lisp`) | `HarnessEventBus.emit` (`packages/agent/src/harness/events.ts`) |

Leftover of the `agent_tool_loop` hole on `harness-events.lisp` after the
`file_mutation_queue` siblings (Pairs 261 / 270–275). Timed work is publish
to a typed direct listener plus an already-started watch (run_start,
run_end, unsubscribe direct, second run_start) — not watch buffering until
start, not write/edit tools. Observed `he_direct` / `he_watch` / `he_start`
/ `he_end` / `he_second` are exact. First n=5 freeze **0.306×** (0.75 /
2.45 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text;
this metric did not fail). Same commit no optimize.

### Pair 277 — `bash_tool` (strip_exit_footer)

| metric | cadr | pi |
|---|---|---|
| `strip_exit_footer` | `bash-strip-exit-footer` (`src/cadr-cli/tools/bash.lisp`) | Process-exited suffix strip (cadr injects then strips; pi's tool path never adds the footer; same encoding as `packages/coding-agent/src/core/tools/bash.ts` result text) |

Leftover sibling of the `agent_tool_loop` hole on `src/cadr-cli/tools/bash.lisp`.
Timed work is stripping `Process exited with code N` (exact footer, newline
footer, glued footer, unchanged body, empty) — not execute/spawn. Observed
`sef_exact` / `sef_nl` / `sef_no_nl` / `sef_plain` / `sef_empty` / `sef_n`
are exact. First n=5 freeze **1.599×** (0.989 / 0.619 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 278 — `bash_tool` (append_status)

| metric | cadr | pi |
|---|---|---|
| `append_status` | `append-bash-status` (`src/cadr-cli/tools/bash.lisp`) | `appendStatus` (`packages/coding-agent/src/core/tools/bash.ts`) |

Leftover sibling of Pair 277 `strip_exit_footer` on the same `agent_tool_loop`
hole. Timed work is abort/exit/timeout status join (empty body vs non-empty)
— not execute/spawn. Observed `abs_empty` / `abs_abort` / `abs_exit` /
`abs_timeout` / `abs_n` are exact. First n=5 freeze **2.911×** (1.109 /
0.381 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script
rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this metric
did not fail). Same commit no optimize.

### Pair 279 — `bash_tool` (truncation_notice)

| metric | cadr | pi |
|---|---|---|
| `truncation_notice` | `bash-truncation-notice` (`src/cadr-cli/tools/bash.lisp`) | `formatOutput` truncation notice (`packages/coding-agent/src/core/tools/bash.ts`) |

Leftover sibling of Pair 277 `strip_exit_footer` and Pair 278 `append_status`
on the same `agent_tool_loop` hole. Timed work is the `[Showing ...]` notice
body (not truncated, last-line-partial, lines, bytes limit) — not
truncate-tail and not execute/spawn. Observed `btn_none` / `btn_partial` /
`btn_lines` / `btn_bytes` / `btn_n` are exact. First n=5 freeze
**3.363×** (2.798 / 0.832 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 280 — `output_accumulator` (append)

| metric | cadr | pi |
|---|---|---|
| `append` | `output-accumulator-append` (`src/cadr-cli/output-accumulator.lisp`) | `OutputAccumulator.append` (`packages/coding-agent/src/core/tools/output-accumulator.ts`) |

Leftover sibling of the `agent_tool_loop` hole on `output-accumulator.lisp`.
Timed work is streaming append of ASCII + split UTF-8 `é` + a trailing line
under the spill ceiling — not snapshot/finish, not bash/tool execute. Observed
`oa_append_bytes` / `oa_append_trunc` / `oa_append_lines` / `oa_append_last` /
`oa_append_n` are exact. First n=5 freeze **0.690×** (3.149 / 4.561 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known
old holes `lc_n` / `lc_sleep` / help text; this metric did not fail). Same
commit no optimize.

### Pair 281 — `output_accumulator` (snapshot)

| metric | cadr | pi |
|---|---|---|
| `snapshot` | `output-accumulator-snapshot` (`src/cadr-cli/output-accumulator.lisp`) | `OutputAccumulator.snapshot` (`packages/coding-agent/src/core/tools/output-accumulator.ts`) |

Leftover sibling of Pair 280 `append` on the same `agent_tool_loop` hole.
Timed work is display snapshot after the same append fixture (no
`persistIfTruncated`, no temp file) — not finish. Observed `oa_snap_bytes` /
`oa_snap_trunc` / `oa_snap_lines` / `oa_snap_total` / `oa_snap_n` are exact.
First n=5 freeze **0.716×** (3.157 / 4.409 µs) on host `cursor`, ceiling 8.0.
Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no optimize.

### Pair 282 — `output_accumulator` (finish)

| metric | cadr | pi |
|---|---|---|
| `finish` | `output-accumulator-finish` (`src/cadr-cli/output-accumulator.lisp`) | `OutputAccumulator.finish` (`packages/coding-agent/src/core/tools/output-accumulator.ts`) |

Leftover sibling of Pair 280 `append` and Pair 281 `snapshot` on the same
`agent_tool_loop` hole. Timed work is finish after a lone incomplete UTF-8
lead byte (`0xC3`) so both sides flush U+FFFD — not spill/temp-file. Observed
`oa_fin_bytes` / `oa_fin_fffd` / `oa_fin_last` / `oa_fin_trunc` / `oa_fin_n`
are exact. First n=5 freeze **0.658×** (1.670 / 2.537 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 427 — `output_accumulator` (last_line_bytes)

| metric | cadr | pi |
|---|---|---|
| `last_line_bytes` | `output-accumulator-last-line-bytes` (`src/cadr-cli/output-accumulator.lisp`) | `OutputAccumulator.getLastLineBytes` (`packages/coding-agent/src/core/tools/output-accumulator.ts`) |

Leftover sibling of Pair 280–282 on the same `output-accumulator.lisp`
`agent_tool_loop` hole. Timed work is last-line byte counts after an open
ASCII line, a newline-closed line, and UTF-8 `é` — not append/snapshot/finish
as the timed owner, not temp-file spill. Observed `oa_ll_open` / `oa_ll_nl` /
`oa_ll_utf8` / `oa_ll_n` are exact. First n=5 freeze **0.341×** (1.761 /
5.158 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script
rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this metric
did not fail). Same commit no optimize. Pair numbers 283–426 belong to other
lanes; this cut is 427–429 only.

### Pair 428 — `output_accumulator` (needs_file)

| metric | cadr | pi |
|---|---|---|
| `needs_file` | `output-accumulator-needs-file-p` (`src/cadr-cli/output-accumulator.lisp`) | `OutputAccumulator.shouldUseTempFile` (`packages/coding-agent/src/core/tools/output-accumulator.ts`) |

Leftover sibling of Pair 427 `last_line_bytes` on the same
`output-accumulator.lisp` hole. Timed work is the spill predicate (empty /
under ceiling / over bytes / over lines) — not temp-file create/close, not
truncateTail. Observed `oa_nf_empty` / `oa_nf_under` / `oa_nf_bytes` /
`oa_nf_lines` / `oa_nf_n` are exact. First n=5 freeze **2.464×** (50.564 /
20.524 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script
rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this metric
did not fail). Same commit no optimize. Booked in
`docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 429 — `output_accumulator` (close_temp_file)

| metric | cadr | pi |
|---|---|---|
| `close_temp_file` | `output-accumulator-close-temp-file` (`src/cadr-cli/output-accumulator.lisp`) | `OutputAccumulator.closeTempFile` (`packages/coding-agent/src/core/tools/output-accumulator.ts`) |

Leftover sibling of Pair 427 `last_line_bytes` and Pair 428 `needs_file` on
the same `output-accumulator.lisp` hole. Timed work is closing the spill
stream after a bytes overflow — not append/snapshot/finish. Observed
`oa_close_path` / `oa_close_stream` / `oa_close_n` are exact. First n=5 freeze
**0.463×** (36.231 / 78.272 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 283 — `harness_events` (on)

| metric | cadr | pi |
|---|---|---|
| `on` | `harness-event-bus-on` (`src/cadr-agent/harness-events.lisp`) | `HarnessEventBus.on` (`packages/agent/src/harness/events.ts`) |

Leftover sibling of Pair 276 `emit` on the same `harness-events.lisp`
`agent_tool_loop` hole. Timed work is typed subscribe plus unsubscribe of
`run_start` while a `run_end` listener stays — not emit delivery of a live
subscription, not watch buffering. Observed `heon_off` / `heon_keep` /
`heon_type` are exact. First n=5 freeze **0.325×** (0.58 / 1.79 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Same commit no optimize.

### Pair 284 — `harness_events` (watch)

| metric | cadr | pi |
|---|---|---|
| `watch` | `harness-event-bus-watch` (`src/cadr-agent/harness-events.lisp`) | `HarnessEventBus.watch` (`packages/agent/src/harness/events.ts`) |

Leftover sibling of Pair 276 `emit` and Pair 283 `on` on the same
`harness-events.lisp` `agent_tool_loop` hole. Timed work is snapshot capture
(an emit during capture is buffered), start flush in order, live `run_end`,
then unsubscribe — not typed direct listeners, not `emit` of an
already-started watch. Observed `hew_snap` / `hew_count` / `hew_start` /
`hew_end` are exact. First n=5 freeze **0.250×** (0.57 / 2.27 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Same commit no optimize.

### Pair 285 — `harness_events` (make_start)

| metric | cadr | pi |
|---|---|---|
| `make_start` | `make-run-start-event` (`src/cadr-agent/harness-events.lisp`) | `RunStartEvent` object (`packages/agent/src/harness/events.ts`) |

Leftover sibling of Pair 276 `emit`, Pair 283 `on`, and Pair 284 `watch` on
the same `harness-events.lisp` `agent_tool_loop` hole. Timed work is
constructing a `run_start` event (type / lane / run id) — not `on`, not
`watch`, not `emit`. Observed `hes_type` / `hes_lane` / `hes_run` are exact.
First n=5 freeze **1.18×** (0.14 / 0.12 µs) on host `cursor`, ceiling 8.0.
Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no optimize.

### Pair 286 — `file_mutation_queue` (call_with)

| metric | cadr | pi |
|---|---|---|
| `call_with` | `call-with-file-mutation-queue` (`src/cadr-agent/file-mutation-queue.lisp`) | `withFileMutationQueue` as a function (`packages/coding-agent/src/core/tools/file-mutation-queue.ts`) |

Leftover sibling of Pair 261 `with_queue` through Pair 275 `ensure_state` on
the same `agent_tool_loop` hole. Timed work is the function (not the
`with-` macro): canonical key plus FIFO acquire/fn/release on existing
path, symlink alias, and distinct sibling — not write/edit tools. Same
staged scratch layout as `with_queue`. Observed `fmqf_alias` /
`fmqf_other` / `fmqf_fifo` / `fmqf_run` / `fmqf_n` are exact. First n=5
freeze **0.523×** (124.1 / 237.4 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 287 — `file_mutation_queue` (make_state)

| metric | cadr | pi |
|---|---|---|
| `make_state` | `make-file-mutation-queue-state` (`src/cadr-agent/file-mutation-queue.lisp`) | queue-state object `{ key, pending, nextTicket, serving }` (`packages/coding-agent/src/core/tools/file-mutation-queue.ts`) |

Leftover sibling of Pair 286 `call_with` on the same `agent_tool_loop`
hole. Timed work is constructing a fresh queue state from a canonical
key (existing path and distinct sibling) — not registry insert, not
`with-file-mutation-queue`, not write/edit tools. Same staged scratch
layout as `with_queue`. Observed `fmqm_pending` / `fmqm_ticket` /
`fmqm_serving` / `fmqm_other` / `fmqm_n` are exact. First n=5 freeze
**1.597×** (105.7 / 66.2 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 288 — `file_mutation_queue` (state_key)

| metric | cadr | pi |
|---|---|---|
| `state_key` | `file-mutation-queue-state-key` (`src/cadr-agent/file-mutation-queue.lisp`) | queue `state.key` after get-or-create given a canonical key (`packages/coding-agent/src/core/tools/file-mutation-queue.ts`) |

Leftover sibling of Pair 286 `call_with` and Pair 287 `make_state` on the
same `agent_tool_loop` hole. Timed work is reading the state's canonical
key after ensure (existing path, symlink alias, missing path, distinct
sibling, repeat lookup) — not path encoding as the owner, not
`with-file-mutation-queue`, not write/edit tools. Same staged scratch
layout as `with_queue`. Observed `fmqt_alias` / `fmqt_other` /
`fmqt_missing` / `fmqt_repeat` / `fmqt_n` are exact. First n=5 freeze
**1.009×** (134.3 / 133.1 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.
### Pair 289 — `find_tool` (pattern_match)

| metric | cadr | pi |
|---|---|---|
| `pattern_match` | `find-pattern-match-p` (`src/cadr-cli/tools/find.lisp`) | basename vs path-containing glob match (`packages/coding-agent/src/core/tools/find.ts`; fd `--full-path` contract) |

Leftover sibling of the `agent_tool_loop` hole on `src/cadr-cli/tools/find.lisp`.
Timed work is glob match on basename (`*.lisp`) vs path (`src/**/*.lisp` /
`src/*.lisp`) — not fd spawn, not gitignore walk. Observed `fpm_star_a` /
`fpm_star_src` / `fpm_star_txt` / `fpm_path_src` / `fpm_path_root` /
`fpm_src_star` / `fpm_n` are exact. First n=5 freeze **7.16×** (30.5 /
4.26 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text;
this metric did not fail). Same commit no optimize.

### Pair 290 — `find_tool` (find_files)

| metric | cadr | pi |
|---|---|---|
| `find_files` | `find-files` (`src/cadr-cli/tools/find.lisp`) | execute output assembly + `relativizeFindResultPath` (`packages/coding-agent/src/core/tools/find.ts`) |

Leftover sibling of Pair 289 `pattern_match` on the same `agent_tool_loop`
hole. Timed work is empty copy (`No files found matching pattern`) plus
`*.lisp` / `src/**/*.lisp` / `src/*.lisp` result counts on a four-file
fixture — not fd spawn. Observed `ff_empty` / `ff_lisp` / `ff_path` /
`ff_src_star` / `ff_n` are exact. First n=5 freeze **3.44×** (633.4 /
184.1 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text;
this metric did not fail). Same commit no optimize.

### Pair 291 — `find_tool` (make_tool)

| metric | cadr | pi |
|---|---|---|
| `make_tool` | `make-find-tool` (`src/cadr-cli/tools/find.lisp`) | `createFindToolDefinition` (`packages/coding-agent/src/core/tools/find.ts`) |

Leftover sibling of Pair 289 `pattern_match` and Pair 290 `find_files` on
the same `agent_tool_loop` hole. Timed work is tool name / description /
required `pattern` — not execute. Observed `fmt_name` / `fmt_desc` /
`fmt_req` / `fmt_n` are exact. First n=5 freeze **1.41×** (131.9 /
93.3 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text;
this metric did not fail). Same commit no optimize.

### Pair 292 — `tool_manager` (get_tool_path)

| metric | cadr | pi |
|---|---|---|
| `get_tool_path` | `get-tool-path` (`src/cadr-cli/tool-manager.lisp`) | `getToolPath` (`packages/coding-agent/src/utils/tools-manager.ts`) |

Leftover of the `agent_tool_loop` hole on `tool-manager.lisp`. Timed work is
local `fd`/`rg` stub discovery plus PATH-empty miss — not download/install,
not write/edit tools. Observed `gtp_local_fd` / `gtp_local_rg` /
`gtp_miss_fd` / `gtp_miss_rg` / `gtp_n` are exact. First n=5 freeze
**0.014×** (107.8 / 7742.0 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 293 — `tool_manager` (ensure_tool)

| metric | cadr | pi |
|---|---|---|
| `ensure_tool` | `ensure-tool` (`src/cadr-cli/tool-manager.lisp`) | `ensureTool` (`packages/coding-agent/src/utils/tools-manager.ts`) |

Leftover sibling of Pair 292 `get_tool_path` on the same `agent_tool_loop`
hole. Timed work is local stub hit plus `CADR_OFFLINE`/`PI_OFFLINE` miss
with an empty PATH so neither side downloads — not GitHub / unpack. Observed
`et_local_fd` / `et_offline_miss` / `et_n` are exact. First n=5 freeze
**0.013×** (65.1 / 5129.9 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 294 — `tool_manager` (cleanup_quarantine)

| metric | cadr | pi |
|---|---|---|
| `cleanup_quarantine` | `cleanup-windows-self-update-quarantine` (`src/cadr-cli/tool-manager.lisp`) | `cleanupWindowsSelfUpdateQuarantine` (`packages/coding-agent/src/utils/windows-self-update.ts`) |

Leftover sibling of Pairs 292–293 on the same `agent_tool_loop` hole. Timed
work is delete of a staged native-quarantine tree under `node_modules` plus
a no-op path with no `node_modules` ancestor — not loaded-.so quarantine.
Observed `cq_removed` / `cq_noop` / `cq_n` are exact. First n=5 freeze
**1.365×** (120.1 / 88.0 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 325 — `evals_harness` (resolve_selection)

| metric | cadr | pi |
|---|---|---|
| `resolve_selection` | `resolve-eval-selection` (`src/cadr-evals/harness.lisp`) | `resolveModelSelection` (`packages/evals/src/pi-harness.ts`) |

Leftover sibling of the `evals_harness` hole on `src/cadr-evals/harness.lisp`.
Timed work is explicit provider/model, trimmed env fallback
(`CADR_EVAL_*` / `PI_PROVIDER`+`PI_MODEL`), and missing/blank errors — not a
live eval run. Do not exact error copy. Observed `rs_explicit` / `rs_env` /
`rs_miss` / `rs_prov` / `rs_blank` / `rs_n` are exact. First n=5 freeze
**0.170×** (1.06 / 6.22 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 326 — `evals_harness` (transcript)

| metric | cadr | pi |
|---|---|---|
| `transcript` | `messages-to-transcript` (`src/cadr-evals/harness.lisp`) | `toTranscriptEvents` (`packages/evals/src/pi-harness.ts`) |

Leftover sibling of Pair 325 `resolve_selection` on the same `evals_harness`
hole. Timed work is user / assistant+toolCall / toolResult / empty-assistant
skip / error toolResult — not `run-coding-agent-eval`. Observed `tr_n` /
`tr_user` / `tr_role` / `tr_text` / `tr_call` / `tr_name` / `tr_result` /
`tr_err` / `tr_keys` are exact. First n=5 freeze **1.743×** (3.80 / 2.18 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text; this metric did not
fail). Over-1× booked. Same commit no optimize.

### Pair 327 — `evals_harness` (last_assistant)

| metric | cadr | pi |
|---|---|---|
| `last_assistant` | `last-assistant-since` (`src/cadr-evals/harness.lisp`) | `promptAgent` assistant slice (`packages/evals/src/pi-harness.ts`) |

Leftover sibling of Pairs 325–326 on the same `evals_harness` hole. Timed
work is pre-prompt tail find of the new assistant, empty tail, and full-list
from-end — not `agent-prompt`. Observed `la_new` / `la_none` / `la_full` /
`la_n` are exact. First n=5 freeze **1.034×** (0.579 / 0.560 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Over-1× booked (sub-µs). Same commit no optimize.

### Pair 364 — `evals_harness` (content_text)

| metric | cadr | pi |
|---|---|---|
| `content_text` | `message-content-text` (`src/cadr-evals/harness.lisp`) | `contentText` (`packages/evals/src/pi-harness.ts` via `@earendil-works/pi-ai`) |

Leftover sibling of Pairs 325–327 on the same `evals_harness` hole. Timed
work is string content, text-part join with a non-text skip, empty, and
blank text — not `messages-to-transcript`. Observed `ct_plain` / `ct_join` /
`ct_empty` / `ct_blank` / `ct_n` are exact. First n=5 freeze **1.386×**
(0.997 / 0.719 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this
metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 365 — `evals_harness` (transcript_event)

| metric | cadr | pi |
|---|---|---|
| `transcript_event` | `transcript-message-event` (`src/cadr-evals/harness.lisp`) | transcript `{ type: "message", role, content }` (`packages/evals/src/pi-harness.ts`) |

Leftover sibling of Pair 364 `content_text` on the same `evals_harness`
hole. Timed work is user and assistant message event objects — not
`toTranscriptEvents` tool_call / tool_result. Observed `te_type` /
`te_role` / `te_content` / `te_asst_role` / `te_asst` / `te_n` are exact.
First n=5 freeze **5.702×** (1.016 / 0.178 µs) on host `cursor`, ceiling
8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Over-1× booked
(sub-µs). Same commit no optimize.

### Pair 366 — `evals_harness` (elapsed)

| metric | cadr | pi |
|---|---|---|
| `elapsed` | `eval-elapsed-milliseconds` (`src/cadr-evals/harness.lisp`) | `performance.now() - startedAt` timings.totalMs (`packages/evals/src/pi-harness.ts`) |

Leftover sibling of Pairs 364–365 on the same `evals_harness` hole. Timed
work is the eval timing helper: non-negative now, non-negative past, and
past ≥ now flags — not `run-coding-agent-eval`. Observed `el_now` /
`el_past` / `el_order` / `el_n` are exact. First n=5 freeze **0.275×**
(0.182 / 0.663 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this
metric did not fail). cadr leads. Same commit no optimize.

### Pair 295 — `provider_registry_defs` (merge_environment)

| metric | cadr | pi |
|---|---|---|
| `merge_environment` | `merge-provider-environment` (`src/cadr-ai/providers/runtime-projection.lisp`) | `getProviderEnvValue` (`packages/ai/src/utils/provider-env.ts`) |

Leftover sibling of lookup/definition_ids on the same `provider_registry_defs`
hole. Timed work is explicit-over-ambient env merge (OPENAI wins, ambient GEMINI
kept, explicit Azure URL present, missing key absent) — not lookup, not stream.
Observed `me_oa` / `me_gemini` / `me_azure` / `me_miss` are exact. First n=5 freeze
**0.114×** (0.320 / 2.803 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 296 — `provider_registry_defs` (runtime_models)

| metric | cadr | pi |
|---|---|---|
| `runtime_models` | `provider-runtime-models` (`src/cadr-ai/providers/runtime-projection.lisp`) | `getBuiltinModels` (`packages/ai/src/providers/all.ts`) |

Leftover sibling on the same `provider_registry_defs` hole. Timed work is catalog
model lists for openai/anthropic/google plus an unknown id — not
`getBuiltinProviders`, not stream. Observed `rm_openai` / `rm_anthropic` /
`rm_google` / `rm_unknown` are exact. First n=5 freeze **3.733×** (17.89 /
4.794 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script
rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this metric
did not fail). Same commit no optimize.

### Pair 297 — `provider_registry_defs` (structured_api_key_login)

| metric | cadr | pi |
|---|---|---|
| `structured_api_key_login` | `provider-definition-structured-api-key-login-p` (`src/cadr-ai/providers/runtime-projection.lisp`) | Bedrock/Vertex `ApiKeyAuth.login` select flow (`packages/ai/src/providers/amazon-bedrock.ts`, `packages/ai/src/providers/google-vertex.ts`) |

Leftover sibling on the same `provider_registry_defs` hole. Timed work is the
structured-login predicate for openai/anthropic/google/bedrock/vertex — not
stream, not login interaction. Observed `sl_openai` / `sl_anthropic` /
`sl_google` / `sl_bedrock` / `sl_vertex` are exact. First n=5 freeze
**0.000831×** (0.176 / 211.2 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 403 — `provider_registry_defs` (api_key_strategy)

| metric | cadr | pi |
|---|---|---|
| `api_key_strategy` | `api-key-auth-strategy-entry` (`src/cadr-ai/providers/runtime-projection.lisp`) | Bedrock/Vertex structured ApiKeyAuth table + environment default (`packages/ai/src/providers/amazon-bedrock.ts`, `packages/ai/src/providers/google-vertex.ts`) |

Leftover sibling of lookup/merge_environment/runtime_models/structured_api_key_login on the same `provider_registry_defs` hole. Timed work is table assoc for `:bedrock` / `:vertex` / `:environment` plus a miss — not the structured-login predicate, not login interaction, not stream. Observed `as_bedrock` / `as_vertex` / `as_env` / `as_miss` / `as_hit` are exact. First n=5 freeze
**0.417×** (0.114 / 0.274 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 404 — `provider_registry_defs` (provider_options)

| metric | cadr | pi |
|---|---|---|
| `provider_options` | `built-in-provider-options` (`src/cadr-ai/providers/runtime-projection.lisp`) | Azure/Cloudflare/Google env-key option projection (same keys the baseline providers read) |

Leftover sibling of Pair 403 on the same `provider_registry_defs` hole. Timed work is fixture env → azure URL / Google project (GOOGLE_CLOUD_PROJECT wins over GCLOUD_PROJECT) / location / Cloudflare account / Azure resource — not getenv, not stream. Observed `po_azure` / `po_project` / `po_location` / `po_cf` / `po_res` are exact. First n=5 freeze
**1.697×** (0.560 / 0.330 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize. Booked in
`docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 405 — `provider_registry_defs` (strip_runtime_options)

| metric | cadr | pi |
|---|---|---|
| `strip_runtime_options` | `remove-runtime-only-options` (`src/cadr-ai/providers/runtime-projection.lisp`) | omit `apiKey` / `headers` / `environment` / `authType` before stream/complete |

Leftover sibling of Pairs 403–404 on the same `provider_registry_defs` hole. Timed work is dropping runtime-only keys while keeping `max-tokens` / `temperature`, plus an all-runtime empty result — not `stream-chat`. Observed `sro_keep` / `sro_drop` / `sro_n` / `sro_empty` / `sro_temp` are exact. First n=5 freeze
**0.0627×** (0.134 / 2.131 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 322 — `core_rest` (cancellation_abort)

| metric | cadr | pi |
|---|---|---|
| `cancellation_abort` | `abort-cancellation` + `cancellation-aborted-p` (`src/cadr-core/cancellation.lisp`) | `AbortController.abort` + `AbortSignal.aborted` |

Leftover on hole `core_rest`. Timed work is make → abort → check → clear plus the
predicate helper — not a wait/timeout. Observed `ca_live` / `ca_abort` /
`ca_clear` / `ca_pred` are exact. First n=5 freeze **0.0712×** (0.579 /
8.130 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script
rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this metric
did not fail). Same commit no optimize.

### Pair 323 — `core_rest` (redacted_secrets)

| metric | cadr | pi |
|---|---|---|
| `redacted_secrets` | `redact-secrets` (`src/cadr-core/redacted-print.lisp`) | `String.split` / `join` of `[REDACTED]` (baseline has no secret-replace helper) |

Leftover on hole `core_rest`. Timed work is two-secret replace of `sk-live-abc`
and `hunter2` while keeping visible text — not print-object. Observed `rd_keep`
/ `rd_secret` / `rd_token` / `rd_mark` are exact. First n=5 freeze **2.488×**
(2.750 / 1.105 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this
metric did not fail). Same commit no optimize.

### Pair 324 — `core_rest` (threads_cleanup)

| metric | cadr | pi |
|---|---|---|
| `threads_cleanup` | `stop-thread-for-cleanup` (`src/cadr-core/threads.lisp`) | `worker_threads` Worker eval-exit |

Leftover on hole `core_rest`. Timed work is nil → `:absent`, current →
`:current`, and a finished thread → `:joined` — not an unbounded
`join-active-thread`. Observed `th_absent` / `th_current` / `th_joined` are
exact. First n=5 freeze **0.00799×** (181.6 / 22730 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 298 — `image_runtime` (output_modalities)

| metric | cadr | pi |
|---|---|---|
| `output_modalities` | `image-output-modalities` (`src/cadr-ai/images.lisp`) | `buildParams` modalities (`packages/ai/src/api/openrouter-images.ts`) |

Leftover sibling of `image_runtime` on `src/cadr-ai/images.lisp` after
Pairs 33 / 63–66 (those timed other files). Timed work is the
`["image","text"]` vs `["image"]` choice from catalog
`google/gemini-2.5-flash-image` and `black-forest-labs/flux.2-pro` —
not HTTP, not `generate-images`. Observed `om_gemini_n` /
`om_gemini_text` / `om_flux_n` / `om_flux_text` are exact. First n=5
freeze **0.657×** (0.196 / 0.299 µs) on host `cursor`, ceiling 8.0.
Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Same
commit no optimize.

### Pair 299 — `image_runtime` (openrouter_content)

| metric | cadr | pi |
|---|---|---|
| `openrouter_content` | `openrouter-image-content` (`src/cadr-ai/images.lisp`) | `buildParams` content parts (`packages/ai/src/api/openrouter-images.ts`) |

Leftover sibling of Pair 298 on the same `image_runtime` hole. Timed
work is text + image_url content parts (`Generate a dog` +
`data:image/png;base64,aW1hZ2U=`) — not HTTP, not
`generate-images`, not `build-openrouter-image-request`. Observed
`oc_text_type` / `oc_text` / `oc_img_type` / `oc_img_url` / `oc_ok`
are exact. First n=5 freeze **3.34×** (1.367 / 0.409 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text; this metric
did not fail). Same commit no optimize. Booked in
`docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 300 — `image_runtime` (parse_data_image)

| metric | cadr | pi |
|---|---|---|
| `parse_data_image` | `parse-data-image` (`src/cadr-ai/images.lisp`) | data-URL parse inside `generateImages` (`packages/ai/src/api/openrouter-images.ts`) |

Leftover sibling of Pairs 298–299 on the same `image_runtime` hole.
Timed work is `data:image/png;base64,…` parse plus a miss and a plain
HTTPS URL — not HTTP, not `generate-images`. Observed `pd_ok_mime` /
`pd_ok_data` / `pd_ok` / `pd_miss` / `pd_plain` are exact (`pd_ok=1`,
non-data-URL `pd_miss` / `pd_plain` = 0). First n=5 freeze **1.43×**
(0.555 / 0.387 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no
optimize. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 367 — `image_runtime` (openrouter_usage)

| metric | cadr | pi |
|---|---|---|
| `openrouter_usage` | `openrouter-image-usage` (`src/cadr-ai/images.lisp`) | `parseUsage` (`packages/ai/src/api/openrouter-images.ts`) |

Leftover sibling of Pairs 298–300 on the same `image_runtime` hole on
`src/cadr-ai/images.lisp`. Timed work is token arithmetic for a zero-cache
usage object (prompt 12 / completion 34) and a cache-write case
(prompt 100 / cached 40 / write 10) — not HTTP, not `generate-images`,
not `build-openrouter-image-request`. Observed `us_in` / `us_out` /
`us_cr` / `us_cw` / `us_in2` / `us_out2` / `us_cr2` / `us_cw2` are
exact. First n=5 freeze **4.218×** (2.167 / 0.514 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known
old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Over-1× booked. Same commit no optimize.

### Pair 368 — `image_runtime` (parse_openrouter_images)

| metric | cadr | pi |
|---|---|---|
| `parse_openrouter_images` | `parse-openrouter-images` (`src/cadr-ai/images.lisp`) | `generateImages` response parse (`packages/ai/src/api/openrouter-images.ts`) |

Leftover sibling of Pair 367 on the same `image_runtime` hole. Timed
work is OpenRouter JSON → assistant-images (id / text / data-URL image
/ usage) — not HTTP, not `generate-images`. Observed `poi_id` /
`poi_text` / `poi_n` / `poi_mime` / `poi_data` / `poi_in` / `poi_out`
are exact. First n=5 freeze **2.986×** (3.188 / 1.068 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text; this metric
did not fail). Over-1× booked. Same commit no optimize.

### Pair 369 — `image_runtime` (error_result)

| metric | cadr | pi |
|---|---|---|
| `error_result` | `image-error-result` (`src/cadr-ai/images.lisp`) | `generateImages` catch error result (`packages/ai/src/api/openrouter-images.ts`) |

Leftover sibling of Pairs 367–368 on the same `image_runtime` hole.
Timed work is authentication-error → `:error`, request-aborted →
`:aborted`, and abort-p flag → `:aborted` — not HTTP, not
`generate-images`. Observed `er_auth` / `er_hit` / `er_abort` /
`er_flag` / `er_prov` are exact. First n=5 freeze **3.028×** (1.047 /
0.346 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help
text; this metric did not fail). Over-1× booked. Same commit no
optimize.

### Pair 313 — `harness_events` (make_end)

| metric | cadr | pi |
|---|---|---|
| `make_end` | `make-run-end-event` (`src/cadr-agent/harness-events.lisp`) | `RunEndEvent` object (`packages/agent/src/harness/events.ts`) |

Leftover sibling of Pair 276 `emit` and Pairs 283–285 `on` / `watch` /
`make_start` on the same `harness-events.lisp` `agent_tool_loop` hole.
Timed work is constructing a `run_end` event (type / lane / run id /
outcome / aborted-null leaf) — not `emit`, not `on`, not `watch`, not
`make_start`. Observed `hee_type` / `hee_lane` / `hee_run` /
`hee_outcome` / `hee_abort` are exact. First n=5 freeze
**1.574×** (0.216 / 0.137 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no optimize.
Pair numbers 289–312 belong to other lanes; this cut is 313–315 only.

### Pair 314 — `harness_events` (event_type)

| metric | cadr | pi |
|---|---|---|
| `event_type` | `harness-event-type` (`src/cadr-agent/harness-events.lisp`) | `event.type` (`packages/agent/src/harness/events.ts`) |

Leftover sibling of Pair 313 `make_end` on the same `harness-events.lisp`
`agent_tool_loop` hole. Timed work is reading the type of a `run_start`,
a completed `run_end`, and a failed `run_end` — not constructors as the
timed owner, not `emit` / `on` / `watch`. Observed `het_start` /
`het_end` / `het_fail` are exact. First n=5 freeze **1.468×** (0.175 /
0.119 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text;
this metric did not fail). Same commit no optimize.

### Pair 315 — `harness_events` (make_bus)

| metric | cadr | pi |
|---|---|---|
| `make_bus` | `make-harness-event-bus` (`src/cadr-agent/harness-events.lisp`) | `new HarnessEventBus()` (`packages/agent/src/harness/events.ts`) |

Leftover sibling of Pair 313 `make_end` and Pair 314 `event_type` on the
same `harness-events.lisp` `agent_tool_loop` hole. Timed work is
constructing two distinct empty buses — not `on`, not `watch`, not
`emit`. Observed `heb_distinct` / `heb_a` / `heb_b` are exact. First n=5
freeze **1.351×** (0.344 / 0.255 µs) on host `cursor`, ceiling 8.0. Gate
used `--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no optimize.

### Pair 301 — `powershell_tool` (utf8_prefix)

| metric | cadr | pi |
|---|---|---|
| `utf8_prefix` | `+powershell-utf8-output-prefix+` (`src/cadr-cli/tools/powershell.lisp`) | `UTF8_OUTPUT_PREFIX` (`packages/coding-agent/src/core/tools/powershell.ts`) |

Leftover sibling of the `agent_tool_loop` hole on
`src/cadr-cli/tools/powershell.lisp`. Timed work is the UTF-8 console
encoding prefix string (length, trailing newline, `try ` lead, `UTF8`
token) — not execute/spawn. Observed `psu_len` / `psu_nl` / `psu_try` /
`psu_utf8` / `psu_n` are exact. First n=5 freeze **3.79×** (0.647 /
0.171 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text;
this metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 302 — `powershell_tool` (prefix_command)

| metric | cadr | pi |
|---|---|---|
| `prefix_command` | prefix + command concatenate (`src/cadr-cli/tools/powershell.lisp`) | `createLocalPowerShellOperations` wrap (`packages/coding-agent/src/core/tools/powershell.ts`) |

Leftover sibling of Pair 301 `utf8_prefix` on the same `agent_tool_loop`
hole. Timed work is concatenating the UTF-8 prefix onto empty / `Get-Date`
/ `Write-Output hi` — not exec/spawn. Observed `psc_empty` / `psc_date` /
`psc_write` / `psc_n` are exact. First n=5 freeze **1.39×** (0.468 /
0.336 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text;
this metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 303 — `powershell_tool` (make_tool)

| metric | cadr | pi |
|---|---|---|
| `make_tool` | `make-powershell-tool` (`src/cadr-cli/tools/powershell.lisp`) | `createPowerShellToolDefinition` (`packages/coding-agent/src/core/tools/powershell.ts`) |

Leftover sibling of Pair 301 `utf8_prefix` and Pair 302 `prefix_command`
on the same `agent_tool_loop` hole. Timed work is tool name / description /
required `command` — not execute. Observed `pmt_name` / `pmt_desc` /
`pmt_req` / `pmt_n` are exact. First n=5 freeze **1.34×** (1.936 /
1.448 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text;
this metric did not fail). Over-1× booked. Same commit no optimize.
### Pair 316 — `ls_tool` (directory_entry_name)

| metric | cadr | pi |
|---|---|---|
| `directory_entry_name` | `directory-entry-name` (`src/cadr-cli/tools/ls.lisp`) | directory suffix (`stat.isDirectory` + `'/'`) in `packages/coding-agent/src/core/tools/ls.ts` |

Leftover sibling of the `agent_tool_loop` hole on `src/cadr-cli/tools/ls.lisp`.
Timed work is file vs directory vs nested-directory name formatting — not
readdir, not execute. Observed `lden_file` / `lden_dir` / `lden_nested` /
`lden_n` are exact. First n=5 freeze **0.969×** (4.659 / 4.808 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Same commit no optimize.

### Pair 317 — `ls_tool` (list_directory)

| metric | cadr | pi |
|---|---|---|
| `list_directory` | `list-directory` (`src/cadr-cli/tools/ls.lisp`) | execute listing assembly (`packages/coding-agent/src/core/tools/ls.ts`; readdir/sort/suffix/limit/`truncateHead`) |

Leftover sibling of Pair 316 `directory_entry_name` on the same `agent_tool_loop`
hole. Timed work is empty copy (`(empty directory)`), mixed top-level listing,
and `limit=2` notice on a four-file fixture — not tool execute spawn, not
write. Observed `ld_empty` / `ld_mixed` / `ld_first` / `ld_limit` / `ld_n`
are exact. First n=5 freeze **1.119×** (352.2 / 314.9 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Over-1× booked.
Same commit no optimize.

### Pair 318 — `ls_tool` (make_tool)

| metric | cadr | pi |
|---|---|---|
| `make_tool` | `make-ls-tool` (`src/cadr-cli/tools/ls.lisp`) | `createLsToolDefinition` (`packages/coding-agent/src/core/tools/ls.ts`) |

Leftover sibling of Pair 316 `directory_entry_name` and Pair 317
`list_directory` on the same `agent_tool_loop` hole. Timed work is tool name /
description / empty required list — not execute. Observed `lst_name` /
`lst_desc` / `lst_req` / `lst_n` are exact. First n=5 freeze **1.017×**
(284.4 / 279.6 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this
metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 304 — `file_mutation_queue` (pending_count)

| metric | cadr | pi |
|---|---|---|
| `pending_count` | `file-mutation-queue-state-pending-count` (`src/cadr-agent/file-mutation-queue.lisp`) | queue `state.pending` after enqueue (`packages/coding-agent/src/core/tools/file-mutation-queue.ts`) |

Leftover sibling of Pair 286 `call_with` through Pair 288 `state_key` on
the same `agent_tool_loop` hole. Timed work is reading `pending` after
enqueue (shared symlink key, distinct sibling, missing path) — not
`make-file-mutation-queue-state` zeros, not `with-file-mutation-queue`,
not write/edit tools. Same staged scratch layout as `with_queue`.
Observed `fmqp_shared` / `fmqp_other` / `fmqp_missing` / `fmqp_alias` /
`fmqp_n` are exact. First n=5 freeze **1.435×** (194.6 / 135.5 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Same commit no optimize.

### Pair 305 — `file_mutation_queue` (next_ticket)

| metric | cadr | pi |
|---|---|---|
| `next_ticket` | `file-mutation-queue-state-next-ticket` (`src/cadr-agent/file-mutation-queue.lisp`) | queue `state.nextTicket` after enqueue (`packages/coding-agent/src/core/tools/file-mutation-queue.ts`) |

Leftover sibling of Pair 304 `pending_count` on the same `agent_tool_loop`
hole. Timed work is reading `nextTicket` after enqueue (shared symlink
key, distinct sibling, missing path) — not constructor zeros, not
write/edit tools. Same staged scratch layout as `with_queue`. Observed
`fmqi_shared` / `fmqi_other` / `fmqi_missing` / `fmqi_alias` / `fmqi_n`
are exact. First n=5 freeze **1.147×** (157.9 / 137.6 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old
holes `lc_n` / `lc_sleep` / help text; this metric did not fail). Same
commit no optimize.

### Pair 306 — `file_mutation_queue` (serving_ticket)

| metric | cadr | pi |
|---|---|---|
| `serving_ticket` | `file-mutation-queue-state-serving-ticket` (`src/cadr-agent/file-mutation-queue.lisp`) | queue `state.serving` after enqueue (`packages/coding-agent/src/core/tools/file-mutation-queue.ts`) |

Leftover sibling of Pair 304 `pending_count` and Pair 305 `next_ticket` on
the same `agent_tool_loop` hole. Timed work is reading `serving` after
enqueue (still 0 until release) — not wait/release, not write/edit tools.
Same staged scratch layout as `with_queue`. Observed `fmqv_zero` /
`fmqv_other` / `fmqv_missing` / `fmqv_alias` / `fmqv_n` are exact. First
n=5 freeze **0.985×** (139.5 / 141.7 µs) on host `cursor`, ceiling 8.0.
Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no optimize.

### Pair 328 — `file_mutation_queue` (waitqueue)

| metric | cadr | pi |
|---|---|---|
| `waitqueue` | `file-mutation-queue-state-waitqueue` (`src/cadr-agent/file-mutation-queue.lisp`) | queue `state.current` Promise after get-or-create (`packages/coding-agent/src/core/tools/file-mutation-queue.ts`) |

Leftover sibling of Pair 304 `pending_count` through Pair 306 `serving_ticket`
on the same `agent_tool_loop` hole. Timed work is reading the waitqueue /
`current` Promise after ensure (present, shared symlink alias, distinct
sibling, repeat lookup) — not `wait-for-file-mutation-turn`, not
`with-file-mutation-queue`, not write/edit tools. Same staged scratch
layout as `with_queue`. Observed `fmqb_present` / `fmqb_shared` /
`fmqb_other` / `fmqb_repeat` / `fmqb_n` are exact. First n=5 freeze
**1.120×** (120.311 / 107.377 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no optimize.

### Pair 329 — `file_mutation_queue` (registry)

| metric | cadr | pi |
|---|---|---|
| `registry` | `*file-mutation-queues*` membership (`src/cadr-agent/file-mutation-queue.lisp`) | `fileMutationQueues.has` after get-or-create (`packages/coding-agent/src/core/tools/file-mutation-queue.ts`) |

Leftover sibling of Pair 328 `waitqueue` on the same `agent_tool_loop` hole.
Timed work is Map/hash membership after ensure (hit, shared alias key, miss
on a never-ensured path, still present after repeat) — not get-or-create as
the owner (`ensure_state` / `lock`), not write/edit tools. Same staged
scratch layout as `with_queue`. Observed `fmqg_hit` / `fmqg_alias` /
`fmqg_miss` / `fmqg_repeat` / `fmqg_n` are exact. First n=5 freeze
**0.779×** (96.436 / 123.778 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). cadr leads. Same commit
no optimize.

### Pair 330 — `file_mutation_queue` (state_p)

| metric | cadr | pi |
|---|---|---|
| `state_p` | `file-mutation-queue-state-p` (`src/cadr-agent/file-mutation-queue.lisp`) | queue-state object predicate (`packages/coding-agent/src/core/tools/file-mutation-queue.ts`) |

Leftover sibling of Pair 328 `waitqueue` and Pair 329 `registry` on the same
`agent_tool_loop` hole. Timed work is the object predicate (true for two
constructed states, false for a list, false for null/nil) — not slot
accessors, not write/edit tools. Same staged scratch layout as `with_queue`.
Observed `fmqc_target` / `fmqc_other` / `fmqc_list` / `fmqc_null` / `fmqc_n`
are exact. First n=5 freeze **1.440×** (100.853 / 70.044 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Same commit no optimize.

### Pair 307 — `cli_settings` (reload)

| metric | cadr | pi |
|---|---|---|
| `reload` | `settings-reload` (`src/cadr-cli/settings/manager.lisp`) | `SettingsManager.reload` (`packages/coding-agent/src/core/settings-manager.ts`) |

Leftover sibling of Pair 13 `cli_settings.create` on the same
`cli_settings` hole. Timed work is re-read of staged
`settings-global.json` / `settings-project.json` — not create, not
TUI. Observed `rl_theme_light` / `rl_model` / `rl_idle` / `rl_n` are
exact. First n=5 freeze **0.593×** (84.8 / 143.0 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known
old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Same commit no optimize.

### Pair 308 — `cli_settings` (enabled_models)

| metric | cadr | pi |
|---|---|---|
| `enabled_models` | `settings-enabled-models` (`src/cadr-cli/settings/manager.lisp`) | `SettingsManager.getEnabledModels` (`packages/coding-agent/src/core/settings-manager.ts`) |

Leftover sibling of Pair 307 `reload` on the same `cli_settings` hole.
Timed work is missing-key `:all` / `undefined` plus one in-memory
explicit pattern — not persist, not selector UI. Observed `em_all` /
`em_one` / `em_n` are exact. First n=5 freeze **5.735×** (18.7 / 3.26 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known
old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Over-1× booked. Same commit no optimize.

### Pair 309 — `cli_settings` (block_images)

| metric | cadr | pi |
|---|---|---|
| `block_images` | `settings-block-images-p` (`src/cadr-cli/settings/manager.lisp`) | `SettingsManager.getBlockImages` (`packages/coding-agent/src/core/settings-manager.ts`) |

Leftover sibling of Pairs 307–308 on the same `cli_settings` hole.
Timed work is default false plus in-memory `images.blockImages=true`
— not decode/resize, not TUI. Observed `bi_default` / `bi_blocked` /
`bi_n` are exact. First n=5 freeze **5.623×** (19.1 / 3.41 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known
old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Over-1× booked. Same commit no optimize.

### Pair 310 — `oauth_pkce_device` (percent_decode)

| metric | cadr | pi |
|---|---|---|
| `percent_decode` | `percent-decode` (`src/cadr-ai/oauth/callback.lisp`) | application/x-www-form-urlencoded percent-decode used by `URLSearchParams` / `parseAuthorizationInput` (`packages/ai/src/auth/oauth/openai-codex.ts`) |

Leftover sibling of the `oauth_pkce_device` hole on `src/cadr-ai/oauth/callback.lisp`.
Timed work is `percent-decode` on valid encodings (plain / `+` as space /
`%2F` / `%20` / UTF-8 `%C3%A9`) — not loopback HTTP, not
`parse-oauth-callback-request`. Do not exact truncated or invalid percent
escapes (Lisp signals; `URLSearchParams` is lenient). Observed `pd_plain` /
`pd_plus` / `pd_slash` / `pd_space` / `pd_utf8` / `pd_n` are exact. First
n=5 freeze **1.525×** (1.592 / 1.044 µs) on host `cursor`, ceiling 8.0.
Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no optimize.

### Pair 311 — `oauth_pkce_device` (parse_query)

| metric | cadr | pi |
|---|---|---|
| `parse_query` | `parse-query` (`src/cadr-ai/oauth/callback.lisp`) | `URLSearchParams` query parse (`packages/ai/src/auth/oauth/openai-codex.ts`) |

Leftover sibling of Pair 310 `percent_decode` on the same `oauth_pkce_device`
hole. Timed work is query parse (`code`/`state`, `+` in a value, empty
value) — not callback request-line routing. Observed `pq_code` / `pq_state` /
`pq_plus` / `pq_empty` / `pq_n` are exact. First n=5 freeze **1.944×**
(6.672 / 3.431 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text;
this metric did not fail). Same commit no optimize.

### Pair 312 — `oauth_pkce_device` (parse_authorization_input)

| metric | cadr | pi |
|---|---|---|
| `parse_authorization_input` | `parse-oauth-authorization-input` (`src/cadr-ai/oauth/callback.lisp`) | `parseAuthorizationInput` (`packages/ai/src/auth/oauth/openai-codex.ts`) |

Leftover sibling of Pair 310 `percent_decode` and Pair 311 `parse_query` on
the same `oauth_pkce_device` hole. Timed work is the four Goal 13 manual
forms (callback URL, `code#state`, `code=` query, trimmed bare code) — not
the loopback listener. Do not exact empty input (Lisp `""` / `NIL` vs pi
`{}`). Observed `pai_url` / `pai_hash` / `pai_qs` / `pai_plain` / `pai_n`
are exact. First n=5 freeze **0.535×** (6.292 / 11.750 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old
holes `lc_n` / `lc_sleep` / help text; this metric did not fail). cadr
leads. Same commit no optimize.

### Pair 421 — `oauth_pkce_device` (json_copy)

| metric | cadr | pi |
|---|---|---|
| `json_copy` | `oauth-response-json-copy` (`src/cadr-ai/oauth/providers/openai-device.lisp`) | `startOpenAICodexDeviceAuth` error-body copy via `response.text` / `JSON.stringify` (`packages/ai/src/auth/oauth/openai-codex.ts`) |

Leftover sibling of the `oauth_pkce_device` hole on `src/cadr-ai/oauth/providers/openai-device.lisp`.
Timed work is empty-object / `{error: boom}` / nil copy — not loopback HTTP, not
`start-openai-codex-device-authorization`. Observed `jc_empty` / `jc_ok` /
`jc_nil` / `jc_n` are exact. Collect restore n=5 freeze **2.173×** (0.938 /
0.432 µs) on host `cursor`, gitHead `2270fa219`, ceiling 8.0. Overlay
recorded; py full gate rc=2 from leftover `parsed_provider` METRICS
pollution. Over-1× booked. Same commit no optimize.

### Pair 422 — `oauth_pkce_device` (interval_seconds)

| metric | cadr | pi |
|---|---|---|
| `interval_seconds` | `openai-device-interval-seconds` (`src/cadr-ai/oauth/providers/openai-device.lisp`) | `startOpenAICodexDeviceAuth` interval parse (`packages/ai/src/auth/oauth/openai-codex.ts`) |

Leftover sibling of Pair 421 `json_copy` on the same `openai-device.lisp`
`oauth_pkce_device` hole. Timed work is numeric / trimmed-string / zero
interval plus negative and `nope` errors — not the device POST. Observed
`iv_num` / `iv_str` / `iv_zero` / `iv_neg` / `iv_bad` / `iv_n` are exact.
Collect restore n=5 freeze **0.819×** (3.779 / 4.616 µs) on host `cursor`,
gitHead `2270fa219`, ceiling 8.0. cadr leads. Overlay recorded; py full
gate rc=2 from leftover `parsed_provider` METRICS pollution. Same commit
no optimize.

### Pair 423 — `oauth_pkce_device` (device_start)

| metric | cadr | pi |
|---|---|---|
| `device_start` | `start-openai-codex-device-authorization` (`src/cadr-ai/oauth/providers/openai-device.lisp`) | `startOpenAICodexDeviceAuth` (`packages/ai/src/auth/oauth/openai-codex.ts`) |

Leftover sibling of Pairs 421–422 on the same `openai-device.lisp`
`oauth_pkce_device` hole. Timed work is stubbed-HTTP start (200 valid / 404 /
500 body / missing `user_code`) — not poll, not runtime login select. Observed
`ds_ok` / `ds_404` / `ds_fail` / `ds_bad` / `ds_n` are exact. Collect restore
n=5 freeze **1.067×** (8.602 / 8.064 µs) on host `cursor`, gitHead
`2270fa219`, ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 343 — `write_tool` (ensure_parent)

| metric | cadr | pi |
|---|---|---|
| `ensure_parent` | `ensure-write-parent-directories` (`src/cadr-cli/tools/write.lisp`) | `defaultWriteOperations.mkdir` / `fs.mkdir` recursive (`packages/coding-agent/src/core/tools/write.ts`) |

Leftover sibling of the `agent_tool_loop` hole on `src/cadr-cli/tools/write.lisp`.
Timed work is parent mkdir (nested create / already-a-directory / parent-is-file
error) — not `write-utf8-file`, not `make-write-tool`, not execute / queue /
result copy. Observed `ep_nested` / `ep_exists` / `ep_eexist` / `ep_n` are
exact. First n=5 freeze **0.594×** (64.978 / 109.366 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Same commit no
optimize. Pair numbers 316–342 belong to other lanes; this cut is 343–345 only.

### Pair 344 — `write_tool` (write_utf8)

| metric | cadr | pi |
|---|---|---|
| `write_utf8` | `write-utf8-file` (`src/cadr-cli/tools/write.lisp`) | `defaultWriteOperations.writeFile` / `fs.writeFile` utf-8 (`packages/coding-agent/src/core/tools/write.ts`) |

Leftover sibling of Pair 343 `ensure_parent` on the same `write.lisp`
`agent_tool_loop` hole. Timed work is UTF-8 write of ASCII `hello` plus CJK/emoji
`中🙂` into an existing parent — not mkdir as the timed owner, not execute.
Observed `wu_ok` / `wu_ascii` / `wu_cjk` / `wu_n` are exact. First n=5 freeze
**1.254×** (169.771 / 135.369 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize. Booked in
`docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 345 — `write_tool` (make_tool)

| metric | cadr | pi |
|---|---|---|
| `make_tool` | `make-write-tool` (`src/cadr-cli/tools/write.lisp`) | `createWriteToolDefinition` (`packages/coding-agent/src/core/tools/write.ts`) |

Leftover sibling of Pair 343 `ensure_parent` and Pair 344 `write_utf8` on the
same `write.lisp` `agent_tool_loop` hole. Timed work is tool name / description /
required `path`+`content` — not execute. Observed `wmt_name` / `wmt_desc` /
`wmt_req` / `wmt_n` are exact. First n=5 freeze **3.139×** (13.633 / 4.343 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Same commit no optimize. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 331 — `evals_harness` (step_value)

| metric | cadr | pi |
|---|---|---|
| `step_value` | `step-value` (`src/cadr-evals/harness.lisp`) | step property access (`packages/evals/src/pi-harness.ts` `runPiCodingAgent` step loop) |

Leftover of the `evals_harness` hole on `harness.lisp`. Timed work is JSON
hash / keyword plist / interned-keyword lookup plus a miss — not
`normalize-eval-steps`, not `resolve-eval-selection`. Observed `sv_hash` /
`sv_plist` / `sv_intern` / `sv_miss` / `sv_n` are exact. First n=5 freeze
**3.693×** (0.774 / 0.210 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 332 — `evals_harness` (usage)

| metric | cadr | pi |
|---|---|---|
| `usage` | `eval-usage` (`src/cadr-evals/harness.lisp`) | usage object assembly (`packages/evals/src/pi-harness.ts` `runPiCodingAgent`) |

Leftover sibling of Pair 331 `step_value` on the same `evals_harness` hole.
Timed work is token / tool-call / cost aggregation over fixture assistant
messages — not `getSessionStats` live session, not prompt. Observed `us_in`
/ `us_out` / `us_total` / `us_tools` / `us_prov` / `us_model` / `us_cost` /
`us_n` are exact. First n=5 freeze **2.148×** (2.240 / 1.042 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Same commit no optimize.

### Pair 333 — `evals_harness` (result_json)

| metric | cadr | pi |
|---|---|---|
| `result_json` | `eval-result-json` (`src/cadr-evals/harness.lisp`) | `SimpleHarnessResult` JSON shape (`packages/evals/src/pi-harness.ts`) |

Leftover sibling of Pairs 331–332 on the same `evals_harness` hole. Timed
work is result object JSON (output / events / errors / artifacts / timings)
— not persist, not summarize. Observed `rj_out` / `rj_ev` / `rj_err` /
`rj_art` / `rj_time` / `rj_n` are exact. First n=5 freeze **5.225×**
(1.933 / 0.370 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text;
this metric did not fail). Same commit no optimize.

### Pair 346 — `evals_harness` (eval_environment)

| metric | cadr | pi |
|---|---|---|
| `eval_environment` | `eval-environment` (`src/cadr-evals/harness.lisp`) | environment trim (`packages/evals/src/pi-harness.ts` `resolveModelSelection`) |

Leftover of the `evals_harness` hole on `harness.lisp`. Timed work is
getenv lookup plus whitespace trim (padded provider, unpadded model,
whitespace-only, missing) — not `resolve-eval-selection`, not
`normalize-eval-steps`. Observed `ee_trim` / `ee_model` / `ee_ws` /
`ee_miss` / `ee_n` are exact. First n=5 freeze **2.692×** (0.758 / 0.282 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1
only from known old holes `lc_n` / `lc_sleep` / help text; this metric
did not fail). Over-1× booked. Same commit no optimize.

### Pair 347 — `evals_harness` (prompt_step)

| metric | cadr | pi |
|---|---|---|
| `prompt_step` | `make-eval-prompt-step` (`src/cadr-evals/harness.lisp`) | prompt step object (`packages/evals/src/pi-harness.ts` `runPiCodingAgent`) |

Leftover sibling of Pair 346 `eval_environment` on the same `evals_harness`
hole. Timed work is `{type: prompt, content}` construction — not step
normalization of a sequence, not prompt-agent. Observed `ps_type` /
`ps_content` / `ps_n` are exact. First n=5 freeze **0.956×** (0.109 / 0.114 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1
only from known old holes `lc_n` / `lc_sleep` / help text; this metric
did not fail). Same commit no optimize.

### Pair 348 — `evals_harness` (reload_step)

| metric | cadr | pi |
|---|---|---|
| `reload_step` | `make-eval-reload-step` (`src/cadr-evals/harness.lisp`) | reload step object (`packages/evals/src/pi-harness.ts` `runPiCodingAgent`) |

Leftover sibling of Pairs 346–347 on the same `evals_harness` hole. Timed
work is `{type: reload}` construction — not extension reload, not
`run-coding-agent-eval`. Observed `rs_type` / `rs_no_content` / `rs_n` are
exact. First n=5 freeze **0.738×** (0.078 / 0.105 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old
holes `lc_n` / `lc_sleep` / help text; this metric did not fail). Same
commit no optimize.
### Pair 319 — `tui_theme_overlay` (rgb_to_ansi_256)

| metric | cadr | pi |
|---|---|---|
| `rgb_to_ansi_256` | `rgb-to-ansi-256` (`src/cadr-tui/theme.lisp`) | `rgbTo256` (`packages/coding-agent/src/modes/interactive/theme/theme.ts`; unexported; harness copy at BASELINE) |

Leftover of the `tui_theme_overlay` hole on `theme.lisp` only. Sibling of
already-paired `osc11_bg` on `src/cadr-tui/terminal-colors.lisp` (not
re-paired). Timed work is cube vs gray-ramp mapping for five RGB fixtures
(red / black / gray / white / accent `#8abeb7`) — not OSC 11, not a TUI
frame. Observed `r256_red` / `r256_black` / `r256_gray` / `r256_white` /
`r256_accent` are exact. First n=5 freeze **1.955×** (2.52 / 1.29 µs) on
host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text; this metric did not
fail). Over-1× booked. Same commit no optimize.

### Pair 320 — `tui_theme_overlay` (parse_hex_color)

| metric | cadr | pi |
|---|---|---|
| `parse_hex_color` | `parse-theme-hex-color` (`src/cadr-tui/theme.lisp`) | `hexToRgb` (`packages/coding-agent/src/modes/interactive/theme/theme.ts`; unexported; harness copy at BASELINE) |

Leftover sibling of Pair 319 on the same `tui_theme_overlay` hole.
Timed work is `#RRGGBB` parse for `#112233` / `#8abeb7` / `#ffffff` — not
OSC 11, not theme load. Observed `ph_112233_r` / `ph_112233_g` /
`ph_112233_b` / `ph_accent_r` / `ph_white_b` are exact. First n=5 freeze
**1.127×** (0.944 / 0.837 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 321 — `tui_theme_overlay` (theme_foreground_ansi)

| metric | cadr | pi |
|---|---|---|
| `theme_foreground_ansi` | `theme-foreground-ansi` (`src/cadr-tui/theme.lisp`) | `Theme.getFgAnsi` (`packages/coding-agent/src/modes/interactive/theme/theme.ts`) |

Leftover sibling of Pairs 319–320 on the same `tui_theme_overlay` hole.
Timed work is CSI-only foreground for `:accent` / `:text` on a pinned dark
truecolor theme — not `theme-foreground` text wrap, not OSC 11.
Observed `tfa_accent_esc` / `tfa_text_esc` / `tfa_n` are exact.
First n=5 freeze **14.724×** (5.58 / 0.379 µs) on host `cursor`, ceiling
8.0. Sub-10 µs path — gate uses variance / 10 µs floor, so this ratio did
not fail `--only-enforce`. Over-1× booked. Same commit no optimize.
### Pair 349 — `evals_harness` (make_eval_root)

| metric | cadr | pi |
|---|---|---|
| `make_eval_root` | `make-eval-root` (`src/cadr-evals/harness.lisp`) | isolated eval directory (`packages/evals/src/pi-harness.ts` `runPiCodingAgent`) |

Leftover of the `evals_harness` hole on `harness.lisp`. Timed work is
creating an isolated temp root with the `cadr-eval-` prefix and no
workspace yet — not `run-coding-agent-eval`, not prompt/reload. Observed
`mer_exists` / `mer_prefix` / `mer_no_ws` / `mer_n` are exact. First n=5
freeze **1.672×** (73.6 / 44.0 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Over-1× booked. Same
commit no optimize.

### Pair 350 — `evals_harness` (normalize_step_type)

| metric | cadr | pi |
|---|---|---|
| `normalize_step_type` | `normalize-step-type` (`src/cadr-evals/harness.lisp`) | step type coercion (`packages/evals/src/pi-harness.ts` `runPiCodingAgent`) |

Leftover sibling of Pair 349 `make_eval_root` on the same `evals_harness`
hole. Timed work is keyword / symbol / string / other coercion — not
`normalize-eval-steps` of a sequence, not prompt-agent. Observed `nst_kw`
/ `nst_sym` / `nst_str` / `nst_bad` / `nst_n` are exact. First n=5 freeze
**1.003×** (0.256 / 0.255 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Over-1× booked. Same
commit no optimize.

### Pair 351 — `evals_harness` (selected_eval_tools)

| metric | cadr | pi |
|---|---|---|
| `selected_eval_tools` | `selected-eval-tools` (`src/cadr-evals/harness.lisp`) | coding-tool selection (`packages/evals/src/pi-harness.ts` `runPiCodingAgent`) |

Leftover sibling of Pairs 349–350 on the same `evals_harness` hole. Timed
work is default four-tool set, `:all` empty, and exclude-`bash` filter —
not `make-coding-tools` as a CLI bootstrap pair, not execute. Observed
`set_n` / `set_names` / `set_all` / `set_filt_n` / `set_no_bash` /
`set_cases` are exact. First n=5 freeze **1.506×** (19.9 / 13.2 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Over-1× booked. Same commit no optimize.

### Pair 352 — `cli_settings` (default_model)

| metric | cadr | pi |
|---|---|---|
| `default_model` | `settings-default-model` (`src/cadr-cli/settings/manager.lisp`) | `SettingsManager.getDefaultModel` (`packages/coding-agent/src/core/settings-manager.ts`) |

Leftover sibling of Pairs 307–309 on the same `cli_settings` hole.
Timed work is fixture `defaultModel` plus missing-key in-memory —
not persist, not selector UI. Observed `dm_fixture` / `dm_missing` /
`dm_n` are exact. First n=5 freeze **7.544×** (15.69 / 2.080 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes `lc_n` / `lc_sleep` / help text; this metric did not
fail). Over-1× booked. Same commit no optimize.

### Pair 353 — `cli_settings` (default_provider)

| metric | cadr | pi |
|---|---|---|
| `default_provider` | `settings-default-provider` (`src/cadr-cli/settings/manager.lisp`) | `SettingsManager.getDefaultProvider` (`packages/coding-agent/src/core/settings-manager.ts`) |

Leftover sibling of Pair 352 `default_model` on the same `cli_settings`
hole. Timed work is fixture `defaultProvider` plus missing-key
in-memory — not persist, not login UI. Observed `dp_fixture` /
`dp_missing` / `dp_n` are exact. First n=5 freeze **6.737×** (15.67 /
2.327 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help
text; this metric did not fail). Over-1× booked. Same commit no
optimize.

### Pair 354 — `cli_settings` (output_padding)

| metric | cadr | pi |
|---|---|---|
| `output_padding` | `settings-output-padding` (`src/cadr-cli/settings/manager.lisp`) | `SettingsManager.getOutputPad` (`packages/coding-agent/src/core/settings-manager.ts`) |

Leftover sibling of Pairs 352–353 on the same `cli_settings` hole.
Timed work is default 1 plus in-memory `outputPad=0` — not TUI
geometry, not persist. Observed `op_default` / `op_zero` / `op_n`
are exact. First n=5 freeze **6.289×** (17.54 / 2.788 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text; this metric did
not fail). Over-1× booked. Same commit no optimize.

### Pair 355 — `evals_harness` (prompt_eval_agent)

| metric | cadr | pi |
|---|---|---|
| `prompt_eval_agent` | `prompt-eval-agent` (`src/cadr-evals/harness.lisp`) | `promptAgent` (`packages/evals/src/pi-harness.ts`) |

Leftover of the `evals_harness` hole on `harness.lisp`. Timed work is
faux-stream `prompt-eval-agent` (last-assistant stop/text) — not
`run-coding-agent-eval`, not `last-assistant-since` as a standalone
pair. Observed `pea_out` / `pea_msgs` / `pea_stop` / `pea_n` are exact.
First n=5 freeze **10.47×** (19.3 / 1.84 µs) on host `cursor`, ceiling
20.0 (first-freeze bump from 8.0). Gate used `--only-enforce` (script
rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this
metric did not fail the ratio after the ceiling bump). Over-1× booked.
Same commit no optimize.

### Pair 356 — `evals_harness` (reload_shutdown)

| metric | cadr | pi |
|---|---|---|
| `reload_shutdown` | `reload-eval-extensions` + `shutdown-eval-agent` (`src/cadr-evals/harness.lisp`) | `AgentSession.reload` + `dispose` (`packages/evals/src/pi-harness.ts`) |

Leftover sibling of Pair 355 `prompt_eval_agent` on the same
`evals_harness` hole. Timed work is isolated empty-extension reload,
session-shutdown, and release — not a live prompt. Observed `rld_err` /
`rld_active` / `rld_reports` / `rld_n` are exact. First n=5 freeze
**1.872×** (222.4 / 118.8 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Over-1× booked. Same
commit no optimize.

### Pair 357 — `evals_harness` (run_coding_agent_eval)

| metric | cadr | pi |
|---|---|---|
| `run_coding_agent_eval` | `run-coding-agent-eval` (`src/cadr-evals/harness.lisp`) | `runPiCodingAgent` (`packages/evals/src/pi-harness.ts`) |

Leftover sibling of Pairs 355–356 on the same `evals_harness` hole. Timed
work is an isolated faux no-tools coding-agent eval (prompt → transcript
→ cleanup) — not a live provider. Observed `rca_out` / `rca_events` /
`rca_err` / `rca_ms` / `rca_n` are exact. First n=5 freeze **7.979×**
(940.1 / 117.8 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Over-1× booked. Same
commit no optimize.

### Pair 334 — `oauth_pkce_device` (provider_key)

| metric | cadr | pi |
|---|---|---|
| `provider_key` | `oauth-callback-provider-key` (`src/cadr-ai/oauth/callback.lisp`) | Anthropic/Radius display-name branches in `packages/ai/src/auth/oauth/anthropic.ts` and `radius.ts` |

Leftover sibling of Pairs 310–312 on the same `oauth_pkce_device` hole
in `src/cadr-ai/oauth/callback.lisp`. Timed work is the display-name map
(`Anthropic` / `Radius` / other) — not loopback HTTP. Observed `pk_anth` /
`pk_rad` / `pk_other` / `pk_n` are exact. First n=5 freeze **0.498×**
(0.139 / 0.279 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). cadr leads. Same
commit no optimize.

### Pair 335 — `oauth_pkce_device` (http_status_text)

| metric | cadr | pi |
|---|---|---|
| `http_status_text` | `oauth-http-status-text` (`src/cadr-ai/oauth/callback.lisp`) | `node:http` `STATUS_CODES` (200 / 400 / 404 / 500) |

Leftover sibling of Pair 334 `provider_key` on the same hole. Timed work
is the four recorded HTTP reason phrases — not `write-oauth-http-response`
and not the loopback listener. Do not exact the otherwise `Error` branch
(Node `STATUS_CODES` is undefined). Observed `st_ok` / `st_bad` /
`st_miss` / `st_err` / `st_n` are exact. First n=5 freeze **0.528×**
(0.137 / 0.260 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). cadr leads. Same
commit no optimize.

### Pair 336 — `oauth_pkce_device` (parse_callback_request)

| metric | cadr | pi |
|---|---|---|
| `parse_callback_request` | `parse-oauth-callback-request` (`src/cadr-ai/oauth/callback.lisp`) | `startLocalOAuthServer` pathname / state / code (`packages/ai/src/auth/oauth/openai-codex.ts`) |

Leftover sibling of Pairs 334–335 on the same hole. Timed work is OpenAI
loopback request-line routing (success / state mismatch / 404 / missing
code) — not the socket, not HTML. Do not exact Anthropic/Radius error
copy or invalid percent escapes (Lisp 500; `URLSearchParams` is
lenient). Observed `pcr_ok` / `pcr_state` / `pcr_path` / `pcr_code` /
`pcr_n` are exact. First n=5 freeze **3.699×** (12.588 / 3.403 µs) on
host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1
only from known old holes `lc_n` / `lc_sleep` / help text; this metric
did not fail). Same commit no optimize.

### Pair 337 — `core_rest` (cancellation_wait)

| metric | cadr | pi |
|---|---|---|
| `cancellation_wait` | `wait-for-cancellation` (`src/cadr-core/cancellation.lisp`) | `Atomics.wait` timeout 0 + aborted `AbortSignal` |

Leftover sibling of Pair 322 `cancellation_abort` on the same `core_rest`
hole. Timed work is wait timeout, predicate-aborted, and already-aborted —
not `abort-cancellation` as the timed owner. Observed `cw_timeout` /
`cw_pred` / `cw_abort` are exact. First n=5 freeze **6.041×** (53.40 /
8.840 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script
rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this metric
did not fail). Over-1× booked. Same commit no optimize.

### Pair 338 — `core_rest` (redacted_types)

| metric | cadr | pi |
|---|---|---|
| `redacted_types` | `redacted-object-types` (`src/cadr-core/redacted-print.lisp`) | sorted copy of a redacted-type list |

Leftover sibling of Pair 323 `redacted_secrets` on the same `core_rest`
hole. Timed work is copy+sort of the registered redacted type list — not
`redact-secrets`. Observed `rt_list` / `rt_syms` / `rt_sorted` are exact.
First n=5 freeze **4.494×** (2.375 / 0.528 µs) on host `cursor`, ceiling
8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Over-1× booked.
Same commit no optimize.

### Pair 339 — `core_rest` (threads_join)

| metric | cadr | pi |
|---|---|---|
| `threads_join` | `join-active-thread` (`src/cadr-core/threads.lisp`) | `worker_threads` Worker `postMessage`+exit |

Leftover sibling of Pair 324 `threads_cleanup` on the same `core_rest`
hole. Timed work is a required-result join with a non-empty reason — not
cleanup/terminate. Observed `tj_value` / `tj_done` / `tj_reason` are exact.
First n=5 freeze **0.00575×** (128.7 / 22383 µs) on host `cursor`, ceiling
8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 358 — `oauth_pkce_device` (base64url_value)

| metric | cadr | pi |
|---|---|---|
| `base64url_value` | `base64url-value` (`src/cadr-ai/oauth/openai-anthropic.lisp`) | RFC 4648 §5 alphabet index used by `decodeJwt` / JWT payload decode (`packages/ai/src/auth/oauth/openai-codex.ts`) |

Leftover sibling of the `oauth_pkce_device` hole on
`src/cadr-ai/oauth/openai-anthropic.lisp`. Timed work is alphabet lookup
(`A` / `a` / `0` / `-` / `_`) — not token HTTP, not browser login. Do not
exact characters outside `A-Za-z0-9-_` (Lisp `NIL` vs JS `indexOf` `-1`).
Observed `bv_A` / `bv_a` / `bv_0` / `bv_dash` / `bv_us` / `bv_n` are exact.
Collect restore n=5 freeze **2.520×** (0.739 / 0.293 µs) on host `cursor`,
gitHead `2270fa219`, ceiling 8.0. Overlay recorded; py full gate rc=2 from
leftover `parsed_provider` METRICS pollution. Over-1× booked. Same commit
no optimize.

### Pair 359 — `oauth_pkce_device` (base64url_decode)

| metric | cadr | pi |
|---|---|---|
| `base64url_decode` | `base64url-decode` (`src/cadr-ai/oauth/openai-anthropic.lisp`) | `decodeJwt` `atob` (`packages/ai/src/auth/oauth/openai-codex.ts`) |

Leftover sibling of Pair 358 `base64url_value` on the same
`oauth_pkce_device` hole. Timed work is unpadded alphabet-only decode
(`{}` / `foo` / account-id JWT payload) — not `+`/`/` padding, not `-`/`_`
(pi `atob`, not base64url). Observed `bd_obj` / `bd_foo` / `bd_acct` /
`bd_n` are exact. Collect restore n=5 freeze **6.461×** (2.922 / 0.452 µs) on
host `cursor`, gitHead `2270fa219`, ceiling 8.0. Overlay recorded; py full
gate rc=2 from leftover `parsed_provider` METRICS pollution. Over-1× booked.
Same commit no optimize.

### Pair 360 — `oauth_pkce_device` (account_id)

| metric | cadr | pi |
|---|---|---|
| `account_id` | `openai-account-id-from-token` (`src/cadr-ai/oauth/openai-anthropic.lisp`) | `getAccountId` (`packages/ai/src/auth/oauth/openai-codex.ts`) |

Leftover sibling of Pairs 358–359 on the same `oauth_pkce_device` hole.
Timed work is JWT account-id extract (present / missing claim / not a JWT)
— not token exchange, not `token-response-credential` expiry. Do not exact
two-part tokens (pi `decodeJwt` requires three parts). Do not exact empty
`chatgpt_account_id` (pi requires length > 0). Observed `aid_ok` /
`aid_miss` / `aid_bad` / `aid_n` are exact. Collect restore n=5 freeze
**5.167×** (6.065 / 1.174 µs) on host `cursor`, gitHead `2270fa219`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 361 — `core_rest` (cancellation_make)

| metric | cadr | pi |
|---|---|---|
| `cancellation_make` | `make-cancellation-state` (`src/cadr-core/cancellation.lisp`) | `AbortController` constructor |

Leftover sibling of Pair 322 `cancellation_abort` and Pair 337
`cancellation_wait` on the same `core_rest` hole. Timed work is the
constructor (plain + unused aborted-function) — not abort, wait, or
predicate as the timed owner. Observed `cm_type` / `cm_live` / `cm_pred`
are exact. First n=5 freeze **0.972×** (0.2446 / 0.2518 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes `lc_n` / `lc_sleep` / help text; this metric did not
fail). Same commit no optimize.

### Pair 362 — `core_rest` (cancellation_aborted)

| metric | cadr | pi |
|---|---|---|
| `cancellation_aborted` | `cancellation-aborted-p` (`src/cadr-core/cancellation.lisp`) | `AbortSignal.aborted` |

Leftover sibling of Pairs 322/337/361 on the same `core_rest` hole. Timed
work is live / predicate-aborted / already-set reads — not
`abort-cancellation` or `wait-for-cancellation` as the timed owner.
Observed `cab_live` / `cab_pred` / `cab_abort` are exact. First n=5 freeze
**0.0965×** (0.6703 / 6.943 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 363 — `core_rest` (cancellation_set)

| metric | cadr | pi |
|---|---|---|
| `cancellation_set` | `set-cancellation-aborted-p` (`src/cadr-core/cancellation.lisp`) | `AbortController.abort` + fresh controller (JS cannot un-abort) |

Leftover sibling of Pair 322 `cancellation_abort` on the same `core_rest`
hole. Timed work is set-true then clear — not `abort-cancellation` as the
timed owner. Observed `cs_set` / `cs_clear` / `cs_n` are exact. First n=5
freeze **0.148×** (0.5152 / 3.478 µs) on host `cursor`, ceiling 8.0. Gate
used `--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 370 — `evals_harness` (release_extensions)

| metric | cadr | pi |
|---|---|---|
| `release_extensions` | `release-eval-extensions` (`src/cadr-evals/harness.lisp`) | eval session extension cleanup (`packages/evals/src/pi-harness.ts`) |

Leftover sibling of the `evals_harness` hole on `src/cadr-evals/harness.lisp`.
Timed work is nil-manager no-op plus `replace-extension-bundles` to empty —
not reload, not `run-coding-agent-eval`. Observed `re_nil` / `re_mgr` /
`re_empty` / `re_n` are exact. First n=5 freeze **21.13×** (6.187 / 0.293 µs)
on host `cursor`, ceiling 8.0 — ratio is above 8.0 but the gate bound is the
variance/µs floor (this metric did not fail). Over-1× booked. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 371 — `evals_harness` (agent_tools)

| metric | cadr | pi |
|---|---|---|
| `agent_tools` | `eval-agent-tools` (`src/cadr-evals/harness.lisp`) | session/agent `tools` list (`packages/evals/src/pi-harness.ts` selector) |

Leftover sibling of Pair 370 `release_extensions` on the same `evals_harness`
hole. Timed work is empty-registry vs two fixture tools (`read`, `bash`) —
not `run-coding-agent-eval`. Observed `at_empty` / `at_n` / `at_read` /
`at_bash` / `at_keys` are exact. First n=5 freeze **5.118×** (1.466 / 0.286 µs)
on host `cursor`, ceiling 8.0. Over-1× booked. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this
metric did not fail). Same commit no optimize.

### Pair 372 — `evals_harness` (extension_paths)

| metric | cadr | pi |
|---|---|---|
| `extension_paths` | `eval-extension-paths` (`src/cadr-evals/harness.lisp`) | `ExtensionRunner.getExtensionPaths` (`packages/coding-agent/src/core/extensions/runner.ts`) |

Leftover sibling of Pairs 370–371 on the same `evals_harness` hole. Timed
work is no-host empty list plus visible/hidden snapshot bundles (hidden
skipped) — not extension load/reload. Observed `ep_none` / `ep_n` /
`ep_path` / `ep_skip` / `ep_keys` are exact. First n=5 freeze **6.381×**
(2.963 / 0.464 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 373 — `grep_tool` (match_event)

| metric | cadr | pi |
|---|---|---|
| `match_event` | `ripgrep-match-event` (`src/cadr-cli/tools/grep.lisp`) | JSON.parse of rg `--json` match events (`packages/coding-agent/src/core/tools/grep.ts`) |

Leftover sibling of Pair `tool_grep.context_file` (`grep-lines` / execute) on
`src/cadr-cli/tools/grep.lisp`. Timed work is match-event JSON parse (match /
begin / invalid) — not `grep-lines`, not context blocks, not execute. Observed
`rme_match` / `rme_begin` / `rme_bad` / `rme_n` are exact. First n=5 freeze
**0.954×** (4.205 / 4.407 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.
Pair numbers 346–372 belong to other lanes; this cut is 373–375 only.

### Pair 374 — `grep_tool` (line_text)

| metric | cadr | pi |
|---|---|---|
| `line_text` | `ripgrep-line-text` (`src/cadr-cli/tools/grep.lisp`) | match.lineText CR/LF sanitize (`packages/coding-agent/src/core/tools/grep.ts`) |

Leftover sibling of Pair 373 `match_event` on the same `grep.lisp` leftover
surface. Timed work is CR/LF strip of match line text (CRLF / LF / plain / CR)
— not execute. Observed `rlt_crlf` / `rlt_nl` / `rlt_plain` / `rlt_cr` /
`rlt_n` are exact. First n=5 freeze **0.962×** (0.712 / 0.741 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known
old holes `lc_n` / `lc_sleep` / help text; this metric did not fail). Same
commit no optimize.

### Pair 375 — `grep_tool` (make_tool)

| metric | cadr | pi |
|---|---|---|
| `make_tool` | `make-grep-tool` (`src/cadr-cli/tools/grep.lisp`) | `createGrepToolDefinition` (`packages/coding-agent/src/core/tools/grep.ts`) |

Leftover sibling of Pair 373 `match_event` and Pair 374 `line_text` on the
same `grep.lisp` leftover surface. Timed work is tool name / description /
required `pattern` — not execute. Observed `gmt_name` / `gmt_desc` /
`gmt_req` / `gmt_n` are exact. First n=5 freeze **10.006×** (4.152 / 0.415 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Printed ratio is above the named 8.0× ceiling; the gate bound is the 10 µs
variance floor. Same commit no optimize. Booked in
`docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 388 — `edit_tool` (normalize_line_endings)

| metric | cadr | pi |
|---|---|---|
| `normalize_line_endings` | `normalize-line-endings` (`src/cadr-cli/tools/edit.lisp`) | `normalizeToLF` (`packages/coding-agent/src/core/tools/edit-diff.ts`) |

Leftover sibling of Pair 110 `detect-line-ending` on
`src/cadr-cli/tools/edit.lisp`. Timed work is LF / CRLF / lone-CR / empty
normalize — not `detect-line-ending`, not restore, not execute / queue /
diff. Observed `nlf_lf` / `nlf_crlf` / `nlf_cr` / `nlf_empty` / `nlf_n`
are exact. First n=5 freeze **2.792×** (1.574 / 0.564 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old
holes `lc_n` / `lc_sleep` / help text; this metric did not fail). Same
commit no optimize. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
Pair numbers 328–387 belong to other lanes; this cut is 388–390 only.

### Pair 389 — `edit_tool` (restore_line_endings)

| metric | cadr | pi |
|---|---|---|
| `restore_line_endings` | `restore-line-endings` (`src/cadr-cli/tools/edit.lisp`) | `restoreLineEndings` (`packages/coding-agent/src/core/tools/edit-diff.ts`) |

Leftover sibling of Pair 388 `normalize_line_endings` on the same
`edit.lisp` hole. Timed work is restore of LF-normalized text to LF / CRLF
(plus no-newline and empty) — not detect, not execute. Do not exact a
string that already contains CRLF. Observed `rle_lf` / `rle_crlf` /
`rle_none` / `rle_empty` / `rle_n` are exact. First n=5 freeze **1.944×**
(0.773 / 0.398 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no
optimize. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 390 — `edit_tool` (make_tool)

| metric | cadr | pi |
|---|---|---|
| `make_tool` | `make-edit-tool` (`src/cadr-cli/tools/edit.lisp`) | `createEditToolDefinition` (`packages/coding-agent/src/core/tools/edit.ts`) |

Leftover sibling of Pair 388 `normalize_line_endings` and Pair 389
`restore_line_endings` on the same `edit.lisp` hole. Timed work is tool
name / description / required `path`+`edits` — not execute. Observed
`emt_name` / `emt_desc` / `emt_req` / `emt_n` are exact. First n=5 freeze
**5.850×** (3.313 / 0.566 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no
optimize. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 400 — `evals_harness` (argument_prefix)

| metric | cadr | pi |
|---|---|---|
| `argument_prefix` | `argument-after-prefix` (`src/cadr-evals/main.lisp`) | startsWith+slice (`packages/evals/scripts/run-evals.mjs`) |

Leftover sibling of the `evals_harness` hole on `src/cadr-evals/main.lisp`.
Timed work is `--flag=` suffix slice (value / empty prefix / miss / model)
— not `parse-eval-arguments`, not a live eval run. Empty suffix stays
unknown. Observed `apr_val` / `apr_empty` / `apr_miss` / `apr_model` / `apr_n`
are exact. First n=5 freeze **0.904×** (0.216 / 0.239 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). cadr leads. Same
commit no optimize.

### Pair 401 — `evals_harness` (parse_arguments)

| metric | cadr | pi |
|---|---|---|
| `parse_arguments` | `parse-eval-arguments` (`src/cadr-evals/main.lisp`) | argv loop (`packages/evals/scripts/run-evals.mjs`) |

Leftover sibling of Pair 400 `argument_prefix` on the same `evals_harness`
hole in `src/cadr-evals/main.lisp`. Timed work is space/equals
`--provider`/`--model`, cadr `--suite=` (default smoke), missing/empty/unknown
errors — not `%eval-main`, not vitest spawn. Do not exact error copy.
Observed `pa_space` / `pa_eq` / `pa_mix` / `pa_miss` / `pa_empty` /
`pa_unknown` / `pa_n` are exact. First n=5 freeze **0.134×** (1.186 / 8.837 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text; this metric did not
fail). cadr leads. Same commit no optimize.

### Pair 402 — `evals_harness` (validate_smoke)

| metric | cadr | pi |
|---|---|---|
| `validate_smoke` | `validate-smoke-result` (`src/cadr-evals/main.lisp`) | `expect(result.output.trim()).toBe("Paris")` + `totalTokens>0` (`packages/evals/src/smoke.eval.ts`) |

Leftover sibling of Pairs 400–401 on the same `evals_harness` hole in
`src/cadr-evals/main.lisp`. Timed work is Paris trim + token usage on a
constructed result — not `run-smoke-eval`, not a live provider. Observed
`vs_ok` / `vs_trim` / `vs_city` / `vs_tok` / `vs_n` are exact. First n=5 freeze
**0.512×** (2.384 / 4.654 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). cadr leads. Same commit no optimize.

### Pair 394 — `resource_loader` (context_from_dir)

| metric | cadr | pi |
|---|---|---|
| `context_from_dir` | `load-context-file-from-dir` (`src/cadr-cli/resource-loader.lisp`) | `loadContextFileFromDir` (`packages/coding-agent/src/core/resource-loader.ts`) |

Leftover sibling of the `resource_loader` hole on `src/cadr-cli/resource-loader.lisp`.
Timed work is first-wins candidate (`AGENTS.override.md` / `AGENTS.md` /
`CLAUDE.md`) plus empty-dir miss — not ancestor walk, not `reload-resources`,
not `dedupe-resources-by-name`. Do not exact file content (cadr returns a
path; pi also reads). Observed `cfd_agents` / `cfd_empty` / `cfd_claude` /
`cfd_override` / `cfd_n` are exact. First n=5 freeze **2.413×** (64.741 /
26.834 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script
rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this metric
did not fail). Over-1× booked. Same commit no optimize.

### Pair 395 — `resource_loader` (project_context)

| metric | cadr | pi |
|---|---|---|
| `project_context` | `load-project-context-files` (`src/cadr-cli/resource-loader.lisp`) | `loadProjectContextFiles` (`packages/coding-agent/src/core/resource-loader.ts`) |

Leftover sibling of Pair 394 `context_from_dir` on the same `resource_loader`
hole. Timed work is the exported ancestor+global context-file walk on the
staged resource cwd/agent — not `reload-resources`. Do not exact file
content. Observed `pc_n` / `pc_cwd` / `pc_cases` are exact. First n=5 freeze
**1.913×** (56.791 / 29.679 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 396 — `resource_loader` (nearest_config)

| metric | cadr | pi |
|---|---|---|
| `nearest_config` | `nearest-config-file` (`src/cadr-cli/resource-loader.lisp`) | project `SYSTEM.md` `existsSync` in `discoverSystemPromptFile` (`packages/coding-agent/src/core/resource-loader.ts`) |

Leftover sibling of Pairs 394–395 on the same `resource_loader` hole. Timed
work is nearest project-config `SYSTEM.md`, missing `APPEND_SYSTEM.md`, and
missing `NOPE.md` — not agent-dir global fallback, not `reload-resources`.
Observed `nc_sys` / `nc_append` / `nc_miss` / `nc_n` are exact. First n=5
freeze **5.401×** (30.226 / 5.596 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 397 — `tui_select_settings_loaders` (loader_frames)

| metric | cadr | pi |
|---|---|---|
| `loader_frames` | `loader-frames` (`src/cadr-tui/composition/loaders.lisp`) | `Loader` `DEFAULT_FRAMES` copy (`packages/tui/src/components/loader.ts` `setIndicator` frames) |

Leftover sibling of Pair 39 `filter` on the `tui_select_settings_loaders` hole,
this file only. Timed work is default / two-frame / one-frame copy — not
`loader-component-start` / `stop` / `run`. Observed `lf_default_n` /
`lf_default_first` / `lf_custom_n` / `lf_one_n` are exact (10 / 1 / 2 / 1).
First n=5 freeze **1.051×** (0.200 / 0.190 µs) on host `cursor`, ceiling 8.0.
Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no optimize.
Booked in `docs/benchmarks/goal20-paired-over-1x.md`. Pair numbers 328–396
belong to other lanes; this cut is 397–399 only. `nextPairNum` stays 328.

### Pair 398 — `tui_select_settings_loaders` (loader_interval)

| metric | cadr | pi |
|---|---|---|
| `loader_interval` | `loader-interval-seconds` (`src/cadr-tui/composition/loaders.lisp`) | `Loader` `intervalMs` default 80 (`packages/tui/src/components/loader.ts` `setIndicator`) |

Leftover sibling of Pair 397 `loader_frames` on the same `loaders.lisp` hole.
Timed work is default / positive 200 ms / non-positive fallback — not the
animation thread. Observed `li_default` / `li_pos` / `li_zero` / `li_n` are
exact (80 / 200 / 80 / 3). First n=5 freeze **1.464×** (0.201 / 0.138 µs) on
host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Same commit no optimize. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 399 — `tui_select_settings_loaders` (loader_step)

| metric | cadr | pi |
|---|---|---|
| `loader_step` | `loader-component-step` (`src/cadr-tui/composition/loaders.lisp`) | `Loader` animation tick (`currentFrame` + `updateDisplay`) |

Leftover sibling of Pair 397 `loader_frames` and Pair 398 `loader_interval` on
the same `loaders.lisp` hole. Timed work is one deterministic frame advance on
a two-frame loader constructed with `:start-p nil` / `stop()` — not
start/stop/run threads. Observed `ls_initial` / `ls_next` / `ls_wrap` / `ls_n`
are exact. First n=5 freeze **1.543×** (0.339 / 0.219 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Same commit no
optimize. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 379 — `oauth_pkce_device` (error_detail)

| metric | cadr | pi |
|---|---|---|
| `error_detail` | `oauth-response-error-detail` (`src/cadr-ai/oauth/providers/xai.lisp`) | `requestFailure` body `error` / `error_description` (`packages/ai/src/auth/oauth/xai.ts`) |

Leftover sibling of the `oauth_pkce_device` hole on `src/cadr-ai/oauth/providers/xai.lisp`.
Timed work is JSON error-detail extraction (description-only / string `error`)
— not HTTP, not `login-xai-oauth`. Do not exact both fields present (Lisp
prefers description; pi joins `"error: description"`) or nested `error`
objects / `message`. Observed `ed_desc` / `ed_error` / `ed_n` are exact.
Collect restore n=5 freeze **2.184×** (0.810 / 0.371 µs) on host `cursor`,
gitHead `2270fa219`, ceiling 8.0. Overlay recorded; py full gate rc=2 from
leftover `parsed_provider` METRICS pollution. Over-1× booked. Same commit
no optimize. Pair numbers 328–378 belong to other lanes; this cut is
379–381 only.

### Pair 380 — `oauth_pkce_device` (ensure_success)

| metric | cadr | pi |
|---|---|---|
| `ensure_success` | `ensure-oauth-response-success` (`src/cadr-ai/oauth/providers/xai.lisp`) | `if (!response.ok) throw requestFailure` (`packages/ai/src/auth/oauth/xai.ts`) |

Leftover sibling of Pair 379 `error_detail` on the same `oauth_pkce_device`
hole. Timed work is 200/201 success vs HTTP 400 throw — not socket POST.
Do not exact formatted messages (cadr interpolates provider+action; pi
hard-codes `xAI OAuth`). Observed `es_ok` / `es_created` / `es_fail` /
`es_n` are exact. Collect restore n=5 freeze **0.693×** (1.697 / 2.451 µs)
on host `cursor`, gitHead `2270fa219`, ceiling 8.0. cadr leads. Overlay
recorded; py full gate rc=2 from leftover `parsed_provider` METRICS
pollution. Same commit no optimize.

### Pair 381 — `oauth_pkce_device` (notify_device)

| metric | cadr | pi |
|---|---|---|
| `notify_device` | `notify-device-authorization` (`src/cadr-ai/oauth/providers/xai.lisp`) | `interaction.notify` `device_code` (`packages/ai/src/auth/oauth/xai.ts`) |

Leftover sibling of Pair 379 `error_detail` and Pair 380 `ensure_success`
on the same `oauth_pkce_device` hole. Timed work is device-code notify
payload (complete URI preferred / plain URI / user-code) — not poll, not
login. Do not exact interval slot names (`:interval` vs `intervalSeconds`).
Observed `nd_complete` / `nd_plain` / `nd_code` / `nd_n` are exact. Collect
restore n=5 freeze **2.643×** (0.889 / 0.336 µs) on host `cursor`, gitHead
`2270fa219`, ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 385 — `core_rest` (cancellation_predicate)

| metric | cadr | pi |
|---|---|---|
| `cancellation_predicate` | `cancellation-predicate-aborted-p` (`src/cadr-core/cancellation.lisp`) | `Boolean(fn())` try/catch |

Leftover sibling of Pair 322 `cancellation_abort` on hole `core_rest`. Timed
work is the exported predicate helper (nil / true / false / error) — not
`abort-cancellation`, `wait-for-cancellation`, or `cancellation-aborted-p` on
a `cancellation-state`. Observed `cp_nil` / `cp_true` / `cp_false` / `cp_err`
are exact. First n=5 freeze **0.106×** (0.296 / 2.788 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old
holes `lc_n` / `lc_sleep` / help text; this metric did not fail). Same
commit no optimize. Pair numbers 328–357 / 358 / 361–363 belong to other
lanes; this cut is 385–387 only.

### Pair 386 — `core_rest` (redacted_register)

| metric | cadr | pi |
|---|---|---|
| `redacted_register` | `register-redacted-object-type` (`src/cadr-core/redacted-print.lisp`) | array push-if-absent (baseline has no type registry) |

Leftover sibling of Pair 323 `redacted_secrets` on the same
`redacted-print.lisp` hole. Timed work is the unexported register helper
(first insert / duplicate / sorted names) — not `redact-secrets`, not
`redacted-object-types`, not `define-redacted-print-object`. Observed `rr_new`
/ `rr_dup` / `rr_sort` are exact. First n=5 freeze **0.698×** (0.216 /
0.309 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script
rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this metric
did not fail). Same commit no optimize.

### Pair 387 — `core_rest` (redacted_replace)

| metric | cadr | pi |
|---|---|---|
| `redacted_replace` | `replace-all` (`src/cadr-core/redacted-print.lisp`) | `String.split` / `join` of one needle |

Leftover sibling of Pair 323 `redacted_secrets` and Pair 386
`redacted_register` on the same `redacted-print.lisp` hole. Timed work is the
unexported one-needle replace (hit / miss / empty needle returns the same
string) — not `redact-secrets` as the timed owner. Observed `ra_hit` /
`ra_mark` / `ra_miss` / `ra_empty` are exact. First n=5 freeze **3.383×**
(1.464 / 0.433 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this
metric did not fail). Same commit no optimize. Booked in
`docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 376 — `evals_harness` (eval_result)

| metric | cadr | pi |
|---|---|---|
| `eval_result` | `make-eval-result` (`src/cadr-evals/harness.lisp`) | `SimpleHarnessResult` construction (`packages/evals/src/pi-harness.ts`) |

Leftover sibling of the `evals_harness` hole on `src/cadr-evals/harness.lisp`.
Timed work is struct construction (empty defaults plus populated events/errors)
— not `eval-result-json` (queued #36) and not a live eval run. Observed `er_out`
/ `er_ev` / `er_art` / `er_time` / `er_full_ev` / `er_err` / `er_n` are exact.
First n=5 freeze **1.734×** (0.762 / 0.440 µs) on host `cursor`, ceiling 8.0.
Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Over-1× booked (sub-µs).
Same commit no optimize.

### Pair 377 — `evals_harness` (root_observer)

| metric | cadr | pi |
|---|---|---|
| `root_observer` | `*eval-root-observer*` (`src/cadr-evals/harness.lisp`) | isolated eval root handoff (`packages/evals/src/pi-harness.ts`) |

Leftover sibling of Pair 376 on the same `evals_harness` hole. Timed work is
the eval-root observer seam (captured pathname) — not `make-eval-root` (queued
#38). Observed `ro_seen` / `ro_path` / `ro_name` / `ro_n` are exact. First n=5
freeze **2.239×** (0.362 / 0.162 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Over-1× booked (sub-µs). Same commit no
optimize.

### Pair 378 — `evals_harness` (model_resolver)

| metric | cadr | pi |
|---|---|---|
| `model_resolver` | stubbed `*eval-model-resolver*` (`src/cadr-evals/harness.lisp`) | `ModelRuntime.getModel` stub (`packages/evals/src/pi-harness.ts`) |

Leftover sibling of Pairs 376–377 on the same `evals_harness` hole. Timed work
is a stubbed resolver funcall (downcase provider, model id, stream function) —
not `default-eval-model-resolver` (skipped this cut; first freeze ~54× vs
ceiling 8.0). Observed `mr_prov` / `mr_model` / `mr_stream` / `mr_n` are exact.
First n=5 freeze **0.601×** (0.153 / 0.254 µs) on host `cursor`, ceiling 8.0.
Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no optimize.

### Pair 409 — `tool_manager` (release_asset)

| metric | cadr | pi |
|---|---|---|
| `release_asset` | `tool-release-asset` (`src/cadr-cli/tool-manager.lisp`) | `TOOLS.getAssetName` (`packages/coding-agent/src/utils/tools-manager.ts`) |

Leftover sibling of Pairs 292–294 on the same `tool-manager.lisp` hole.
Timed work is fd/rg GitHub release asset names for darwin-arm64, linux-x64,
windows-x64, linux musl/gnu, and darwin-arm64 ripgrep — not download, not
unpack, not `ensure-tool`. Observed `ra_fd_darwin_arm` / `ra_fd_linux_x64` /
`ra_fd_win_x64` / `ra_rg_linux_x64` / `ra_rg_linux_arm` / `ra_rg_darwin_arm` /
`ra_n` are exact. First n=5 freeze **1.465×** (1.532 / 1.046 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Over-1× booked.
Same commit no optimize.

### Pair 410 — `tool_manager` (find_binary)

| metric | cadr | pi |
|---|---|---|
| `find_binary` | `find-file-recursively` (`src/cadr-cli/tool-manager.lisp`) | `findBinaryRecursively` (`packages/coding-agent/src/utils/tools-manager.ts`) |

Leftover sibling of Pair 409 `release_asset` on the same `tool-manager.lisp`
hole. Timed work is nested `fd`, root `rg`, and a missing name — not archive
extract, not chmod. Observed `fb_nested` / `fb_root` / `fb_miss` / `fb_n` are
exact. First n=5 freeze **1.568×** (339.3 / 216.5 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Over-1× booked.
Same commit no optimize.

### Pair 411 — `tool_manager` (quarantine_native)

| metric | cadr | pi |
|---|---|---|
| `quarantine_native` | `quarantine-windows-native-dependencies` (`src/cadr-cli/tool-manager.lisp`) | `quarantineWindowsNativeDependencies` (`packages/coding-agent/src/utils/windows-self-update.ts`) |

Leftover sibling of Pair 294 `cleanup_quarantine` on the same
`tool-manager.lisp` hole. Timed work is rename+copy of a fixture native under
`node_modules` plus a no-op path with no `node_modules` ancestor — not
`process.report` enumeration on cadr (`:loaded-paths`), not cleanup. Observed
`qn_restored` / `qn_stashed` / `qn_noop` / `qn_n` are exact. First n=5 freeze
**0.961×** (560.4 / 583.0 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). cadr leads. Same commit no optimize.

### Pair 415 — `tui_select_settings_loaders` (make_loader_component)

| metric | cadr | pi |
|---|---|---|
| `make_loader_component` | `make-loader-component` (`src/cadr-tui/composition/loaders.lisp`) | `Loader` constructor (`packages/tui/src/components/loader.ts`) |

Leftover sibling of Pair 39 `filter` on the `tui_select_settings_loaders` hole,
staggered from in-flight #53 `loader_frames` / `loader_interval` / `loader_step`.
Timed work is construct a two-frame loader with `:start-p nil` / `stop()` —
not `loader-component-start` / `stop` / `run` threads. Observed `ml_has_a` /
`ml_frames` / `ml_n` are exact (1 / 2 / 2). First n=5 freeze **0.182×**
(0.402 / 2.207 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this
metric did not fail). Same commit no optimize. Pair numbers 328–414 belong to
other lanes; this cut is 415–417 only. `nextPairNum` stays 328.

### Pair 416 — `tui_select_settings_loaders` (set_message)

| metric | cadr | pi |
|---|---|---|
| `set_message` | `loader-component-set-message` (`src/cadr-tui/composition/loaders.lisp`) | `Loader.setMessage` (`packages/tui/src/components/loader.ts`) |

Leftover sibling of Pair 415 `make_loader_component` on the same `loaders.lisp`
hole. Timed work is message update + display on a stopped two-frame loader —
not start/stop/run. Observed `sm_working` / `sm_kept_a` / `sm_n` are exact
(1 / 1 / 2). First n=5 freeze **1.269×** (0.244 / 0.192 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Same commit no
optimize. Booked in `docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 417 — `tui_select_settings_loaders` (set_indicator)

| metric | cadr | pi |
|---|---|---|
| `set_indicator` | `loader-component-set-indicator` (`src/cadr-tui/composition/loaders.lisp`) | `Loader.setIndicator` (`packages/tui/src/components/loader.ts`) |

Leftover sibling of Pair 415 `make_loader_component` and Pair 416 `set_message`
on the same `loaders.lisp` hole. Timed work is frames/interval replace with
`:start-p nil` / `stop()` after — not animation threads. Observed `si_has_x` /
`si_frames` / `si_n` are exact (1 / 2 / 2). First n=5 freeze **0.201×**
(0.341 / 1.700 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text; this
metric did not fail). Same commit no optimize.

### Pair 412 — `evals_harness` (status_name)

| metric | cadr | pi |
|---|---|---|
| `status_name` | `reporter-status-name` (`src/cadr-evals/reporter.lisp`) | `test.result().state` lowercasing (`packages/evals/src/vitest-evals/reporter.ts`) |

Leftover of the `evals_harness` hole on `src/cadr-evals/reporter.lisp`. Timed
work is keyword / uppercase / mixed-case status downcasing — not
`eval-reporter-record-case`, not JSONL append. Observed `sn_kw` / `sn_str` /
`sn_mixed` / `sn_n` are exact. First n=5 freeze **1.726×** (0.352 / 0.204 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text; this metric did not
fail). Same commit no optimize. Booked in
`docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 413 — `evals_harness` (case_observation)

| metric | cadr | pi |
|---|---|---|
| `case_observation` | `reporter-case-observation` (`src/cadr-evals/reporter.lisp`) | `collectHarnessObservations` (`packages/evals/src/vitest-evals/reporter.ts`) |

Leftover sibling of Pair 412 `status_name` on the same `evals_harness` hole.
Timed work is scored / errored-from-errors / unscored-passed / failed-errored
/ missing-iteration skip — not persist, not finish. Observed `co_scored` /
`co_err` / `co_unscored` / `co_fail` / `co_miss` / `co_n` are exact. First n=5 freeze **3.069×**
(9.383 / 3.057 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text;
this metric did not fail). Same commit no optimize. Booked in
`docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 414 — `evals_harness` (finish)

| metric | cadr | pi |
|---|---|---|
| `finish` | `eval-reporter-finish` (`src/cadr-evals/reporter.lisp`) | `onTestRunEnd` (`packages/evals/src/vitest-evals/reporter.ts`) |

Leftover sibling of Pairs 412–413 on the same `evals_harness` hole. Timed
work is interrupted notice, completed comparison print, and empty-observation
silence — not record-case, not JSONL. Observed `rf_int` / `rf_cmp` /
`rf_empty` / `rf_n` are exact. First n=5 freeze **0.701×** (20.345 / 29.007 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text; this metric did not
fail). Same commit no optimize.

### Pair 406 — `grep_tool` (read_utf8)

| metric | cadr | pi |
|---|---|---|
| `read_utf8` | `read-utf8-file` (`src/cadr-cli/tools/grep.lisp`) | `defaultGrepOperations.readFile` / `fs.readFile` utf-8 (`packages/coding-agent/src/core/tools/grep.ts`) |

Leftover sibling of the `tool_grep.context_file` hole on `src/cadr-cli/tools/grep.lisp`.
Timed work is UTF-8 ingest of ASCII `hello` plus empty file — not `grep-lines` /
ripgrep spawn, not match-event / line-text / make-tool (pairs 373–375 on PR #48).
Observed `gru_ascii` / `gru_empty` / `gru_n` are exact. First n=5 freeze **0.500×**
(101.136 / 202.336 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text;
this metric did not fail). cadr leads. Same commit no optimize. Pair numbers
406–408 only.

### Pair 407 — `grep_tool` (file_lines)

| metric | cadr | pi |
|---|---|---|
| `file_lines` | `ripgrep-file-lines` (`src/cadr-cli/tools/grep.lisp`) | `getFileLines` (`packages/coding-agent/src/core/tools/grep.ts`) |

Leftover sibling of Pair 406 `read_utf8` on the same `grep.lisp` `tool_grep` hole.
Timed work is the per-file line-table cache (7 content lines, no trailing newline
so cadr table n and pi `split("\n")` length match) — not execute / spawn.
Observed `gfl_n` / `gfl_first` / `gfl_cache` / `gfl_count` are exact. First n=5 freeze
**0.644×** (97.236 / 151.098 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). cadr leads. Same commit no optimize.

### Pair 408 — `grep_tool` (context_block)

| metric | cadr | pi |
|---|---|---|
| `context_block` | `ripgrep-context-block` (`src/cadr-cli/tools/grep.lisp`) | `formatBlock` (`packages/coding-agent/src/core/tools/grep.ts`) |

Leftover sibling of Pair 406 `read_utf8` and Pair 407 `file_lines` on the same
`grep.lisp` `tool_grep` hole. Timed work is context=2 around line 4 plus missing-file
`(unable to read file)` — not match JSON parse, not `make-grep-tool`. Observed
`gcb_lines` / `gcb_match` / `gcb_missing` / `gcb_n` are exact. First n=5 freeze
**0.598×** (113.423 / 189.556 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). cadr leads. Same commit no optimize.

### Pair 418 — `evals_harness` (eval_layout)

| metric | cadr | pi |
|---|---|---|
| `eval_layout` | `run-coding-agent-eval` workspace/agent/sessions layout (`src/cadr-evals/harness.lisp`) | `runPiCodingAgent` `join(root, "workspace"|"agent"|"sessions")` (`packages/evals/src/pi-harness.ts`) |

Leftover sibling of the `evals_harness` hole on `src/cadr-evals/harness.lisp`.
Timed work is isolated eval directory leaf names (workspace / agent /
sessions) — not `make-eval-root`, not a live eval run. Do not exact session
parent (cadr nests sessions under agent/; pi joins sessions on root).
Observed `el_ws` / `el_agent` / `el_sess` / `el_n` are exact. First n=5 freeze
**3.071×** (3.297 / 1.074 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 419 — `evals_harness` (system_prompt)

| metric | cadr | pi |
|---|---|---|
| `system_prompt` | `transform-system-prompt` empty rejection (`src/cadr-evals/harness.lisp`) | `transformSystemPrompt` empty rejection (`packages/evals/src/pi-harness.ts`) |

Leftover sibling of Pair 418 `eval_layout` on the same `evals_harness` hole.
Timed work is identity / suffix transform plus empty and whitespace rejection
— not `build-system-prompt`, not a live agent. Do not exact error copy.
Observed `sp_id` / `sp_map` / `sp_empty` / `sp_blank` / `sp_n` are exact.
First n=5 freeze **0.115×** (0.569 / 4.934 µs) on host `cursor`, ceiling 8.0.
Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no optimize.

### Pair 420 — `evals_harness` (output_selector)

| metric | cadr | pi |
|---|---|---|
| `output_selector` | `run-coding-agent-eval` `:selector` (`src/cadr-evals/harness.lisp`) | `options.output` (`packages/evals/src/pi-harness.ts`) |

Leftover sibling of Pairs 418–419 on the same `evals_harness` hole. Timed
work is passthrough / identity selector / mapped selector — not prompt, not
JSON. Observed `os_none` / `os_id` / `os_map` / `os_n` are exact. First n=5
freeze **1.007×** (0.189 / 0.188 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Over-1× booked (sub-µs). Same commit
no optimize.

### Pair 433 — `tui_select_settings_loaders` (update_display)

| metric | cadr | pi |
|---|---|---|
| `update_display` | `loader-component-update-display` (`src/cadr-tui/composition/loaders.lisp`) | `Loader.updateDisplay` (`packages/tui/src/components/loader.ts`) |

Leftover sibling of Pair 39 `filter` on the `tui_select_settings_loaders` hole,
staggered from in-flight #53 `loader_frames` / `loader_interval` / `loader_step`
and #61 `make_loader_component` / `set_message` / `set_indicator`. Timed work
is display rebuild on a stopped two-frame loader — not `loader-component-start`
/ `stop` / `run` threads. Observed `ud_has_a` / `ud_frames` / `ud_n` are exact
(1 / 2 / 2). First n=5 freeze **1.225×** (0.282 / 0.230 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Over-1× booked.
Same commit no optimize. Pair numbers 328–432 belong to other lanes; this cut
is 433–435 only. `nextPairNum` stays 328.

### Pair 434 — `tui_select_settings_loaders` (make_cancellable_loader)

| metric | cadr | pi |
|---|---|---|
| `make_cancellable_loader` | `make-cancellable-loader-component` (`src/cadr-tui/composition/loaders.lisp`) | `CancellableLoader` constructor (`packages/tui/src/components/cancellable-loader.ts`) |

Leftover sibling of Pair 433 `update_display` on the same `loaders.lisp` hole.
Timed work is construct a two-frame cancellable loader with `:start-p nil` /
`stop()` — not animation threads. Observed `cl_has_a` / `cl_aborted` / `cl_n`
are exact (1 / 0 / 2). First n=5 freeze **0.205×** (0.600 / 2.934 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known
old holes `lc_n` / `lc_sleep` / help text; this metric did not fail). Same
commit no optimize.

### Pair 435 — `tui_select_settings_loaders` (cancellation_token_aborted)

| metric | cadr | pi |
|---|---|---|
| `cancellation_token_aborted` | `cancellation-token-aborted-p` (`src/cadr-tui/composition/loaders.lisp`) | `CancellableLoader.aborted` (`packages/tui/src/components/cancellable-loader.ts`) |

Leftover sibling of Pair 433 `update_display` and Pair 434
`make_cancellable_loader` on the same `loaders.lisp` hole. Timed work is the
aborted predicate after abort — not Escape `handleInput`, not start/stop/run.
Observed `ct_before` / `ct_after` / `ct_n` are exact (0 / 1 / 2). First n=5
freeze **0.868×** (0.103 / 0.119 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 436 — `oauth_pkce_device` (openrouter_input)

| metric | cadr | pi |
|---|---|---|
| `openrouter_input` | `parse-openrouter-authorization-input` (`src/cadr-ai/oauth/providers/openrouter.lisp`) | `parseAuthorizationInput` (`packages/ai/src/auth/oauth/openrouter.ts`) |

Leftover sibling of the `oauth_pkce_device` hole on `src/cadr-ai/oauth/providers/openrouter.lisp`.
Timed work is callback URL / `code=` query / trimmed bare code — not loopback
HTTP, not `login-openrouter-oauth`. Do not exact empty input (Lisp `NIL` vs
pi `undefined`) or a URL with no query. Observed `ori_url` / `ori_qs` /
`ori_plain` / `ori_n` are exact. Collect restore n=5 freeze **0.656×**
(4.934 / 7.523 µs) on host `cursor`, gitHead `2270fa219`, ceiling 8.0.
cadr leads. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Same commit no optimize.

### Pair 437 — `oauth_pkce_device` (openrouter_refresh)

| metric | cadr | pi |
|---|---|---|
| `openrouter_refresh` | `refresh-openrouter-oauth-credential` (`src/cadr-ai/oauth/providers/openrouter.lisp`) | `openRouterOAuth.refresh` (`packages/ai/src/auth/oauth/openrouter.ts`) |

Leftover sibling of Pair 436 `openrouter_input` on the same `openrouter.lisp`
`oauth_pkce_device` hole. Timed work is identity refresh (same object, access
kept, empty refresh) — not key exchange, not login. Observed `orr_same` /
`orr_access` / `orr_empty` / `orr_n` are exact. Collect restore n=5 freeze
**0.727×** (0.166 / 0.229 µs) on host `cursor`, gitHead `2270fa219`,
ceiling 8.0. cadr leads. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Same commit no optimize.

### Pair 438 — `oauth_pkce_device` (openrouter_exchange)

| metric | cadr | pi |
|---|---|---|
| `openrouter_exchange` | `openrouter-exchange-code` (`src/cadr-ai/oauth/providers/openrouter.lisp`) | `exchangeAuthorizationCode` (`packages/ai/src/auth/oauth/openrouter.ts`) |

Leftover sibling of Pairs 436–437 on the same `openrouter.lisp`
`oauth_pkce_device` hole. Timed work is stubbed-HTTP key exchange (200 with
`key`, 400 with `error`, 200 missing `key`) — not the loopback listener, not
runtime login. Observed `ox_ok` / `ox_fail` / `ox_bad` / `ox_n` are exact.
Collect restore n=5 freeze **1.164×** (7.533 / 6.469 µs) on host `cursor`,
gitHead `2270fa219`, ceiling 8.0. Overlay recorded; py full gate rc=2 from
leftover `parsed_provider` METRICS pollution. Over-1× booked. Same commit
no optimize.

### Pair 430 — `evals_harness` (make_reporter)

| metric | cadr | pi |
|---|---|---|
| `make_reporter` | `make-eval-harness-reporter` (`src/cadr-evals/reporter.lisp`) | `EvalHarnessReporter` constructor + `PI_EVAL_ARTIFACT_DIR` trim (`packages/evals/src/vitest-evals/reporter.ts`) |

Leftover of the `evals_harness` hole on `reporter.lisp`. Timed work is
explicit artifact directory, trimmed env fallback, and missing env —
not `eval-reporter-record-case`, not JSONL persist. Do not exact env
name copy (`CADR_EVAL_*` / `PI_EVAL_*`). Observed `mr_explicit` /
`mr_env` / `mr_miss` / `mr_n` are exact. First n=5 freeze **0.917×**
(0.346 / 0.377 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 431 — `evals_harness` (finite_number)

| metric | cadr | pi |
|---|---|---|
| `finite_number` | `reporter-finite-number` (`src/cadr-evals/reporter.lisp`) | `readFiniteNumber` (`packages/evals/src/vitest-evals/reporter.ts`) |

Leftover sibling of Pair 430 `make_reporter` on the same `evals_harness`
hole. Timed work is keep finite int/float and drop nil / inf / non-number
— not `reporter-case-observation`. Observed `fn_int` / `fn_float` /
`fn_nil` / `fn_inf` / `fn_str` / `fn_n` are exact. First n=5 freeze
**0.531×** (0.117 / 0.220 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 432 — `evals_harness` (artifact_metadata)

| metric | cadr | pi |
|---|---|---|
| `artifact_metadata` | `reporter-artifact-metadata` (`src/cadr-evals/reporter.lisp`) | metadata filter in `appendHarnessRunReport` (`packages/evals/src/vitest-evals/reporter.ts`) |

Leftover sibling of Pairs 430–431 on the same `evals_harness` hole.
Timed work is drop `runId` and the session-snapshot artifact key while
keeping custom metadata — not persist, not `runs.jsonl`. Observed
`am_keep` / `am_runid` / `am_snap` / `am_n` are exact. First n=5 freeze
**1.182×** (1.025 / 0.868 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Over-1× booked.
Same commit no optimize.


### Pair 877 — `oauth_pkce_device` (kimi_host_default)

| metric | cadr | pi |
|---|---|---|
| `kimi_host_default` | `kimi-oauth-host` nil env (`src/cadr-ai/oauth/providers/kimi.lisp`) | `getOauthHost` DEFAULT_OAUTH_HOST (`packages/ai/src/auth/oauth/kimi-coding.ts`) |

Leftover of the `oauth_pkce_device` hole on `kimi.lisp`. Timed work is the
default host with no environment override. Observed `khd_eq` / `khd_https` /
`khd_n` are exact. Collect restore n=5 freeze **2.293×** (0.348 /
0.152 µs) on host `Friend-MachineD`, gitHead `9ae80d2b0`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 878 — `oauth_pkce_device` (kimi_host_code)

| metric | cadr | pi |
|---|---|---|
| `kimi_host_code` | `kimi-oauth-host` KIMI_CODE_OAUTH_HOST (`src/cadr-ai/oauth/providers/kimi.lisp`) | `getOauthHost` KIMI_CODE_OAUTH_HOST (`packages/ai/src/auth/oauth/kimi-coding.ts`) |

Leftover sibling of Pair 877. Timed work is CODE host winning over
KIMI_OAUTH_HOST. Observed `khc_eq` / `khc_win` / `khc_n` are exact. Collect
restore n=5 freeze **2.773×** (0.440 /
0.159 µs) on host `Friend-MachineD`, gitHead `9ae80d2b0`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 879 — `oauth_pkce_device` (kimi_host_trim)

| metric | cadr | pi |
|---|---|---|
| `kimi_host_trim` | `kimi-oauth-host` trailing-slash trim (`src/cadr-ai/oauth/providers/kimi.lisp`) | `getOauthHost` replace `/+$` (`packages/ai/src/auth/oauth/kimi-coding.ts`) |

Leftover sibling of Pairs 877–878. Timed work is trailing-slash strip.
Observed `kht_eq` / `kht_noslash` / `kht_n` are exact. Collect restore n=5
freeze **3.014×** (0.614 /
0.204 µs) on host `Friend-MachineD`, gitHead `9ae80d2b0`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 880 — `oauth_pkce_device` (anth_oauth_name)

| metric | cadr | pi |
|---|---|---|
| `anth_oauth_name` | `oauth-provider-metadata-method-name` via `login-anthropic-runtime-oauth` (`src/cadr-ai/oauth/providers/anthropic.lisp`) | `anthropicOAuth.name` (`packages/ai/src/auth/oauth/anthropic.ts`) |

Leftover of the `oauth_pkce_device` hole on `anthropic.lisp`. Timed work is
the Anthropic OAuth display name. Observed `anm_eq` / `anm_claude` /
`anm_n` are exact. Collect restore n=5 freeze **3.755×** (0.373 /
0.099 µs) on host `Friend-MachineD`, gitHead `9ae80d2b0`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 881 — `oauth_pkce_device` (anth_oauth_sub)

| metric | cadr | pi |
|---|---|---|
| `anth_oauth_sub` | `oauth-provider-metadata-is-subscription-p` via `login-anthropic-runtime-oauth` (`src/cadr-ai/oauth/providers/anthropic.lisp`) | `anthropicOAuth.isSubscription` (`packages/ai/src/auth/oauth/anthropic.ts`) |

Leftover sibling of Pair 880. Timed work is the subscription flag.
Observed `ans_sub` / `ans_t` / `ans_n` are exact. Collect restore n=5 freeze
**1.913×** (0.143 /
0.075 µs) on host `Friend-MachineD`, gitHead `9ae80d2b0`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 882 — `oauth_pkce_device` (anth_oauth_instructions)

| metric | cadr | pi |
|---|---|---|
| `anth_oauth_instructions` | `oauth-provider-metadata-auth-url-instructions` via `login-anthropic-runtime-oauth` (`src/cadr-ai/oauth/providers/anthropic.lisp`) | login notify instructions (`packages/ai/src/auth/oauth/anthropic.ts`) |

Leftover sibling of Pairs 880–881. Timed work is the browser-redirect paste
copy. Observed `ani_eq` / `ani_paste` / `ani_n` are exact. Collect restore
n=5 freeze **7.100×** (0.729 /
0.103 µs) on host `Friend-MachineD`, gitHead `9ae80d2b0`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 868 — `cli_support` (editor_success)

| metric | cadr | pi |
|---|---|---|
| `editor_success` | `edit-in-external-editor` success (`src/cadr-cli/support/external-editor.lisp`) | `editInExternalEditor` true-exit complete (`packages/coding-agent/src/modes/interactive/external-editor.ts`) |

Leftover of the `cli_support` hole on `external-editor.lisp`. Timed work is
the success path (runner exit 0 keeps edited buffer). Observed `eed_hello` / `eed_len` / `eed_round` / `eed_nonl` / `eed_n` are exact. Collect restore n=5 freeze **0.011×** (231.411 /
20933.089 µs) on host `Friend-MachineD`, gitHead `c3c94ecf1`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Under 1× (over-1× table not updated). Same commit no
optimize.

### Pair 869 — `cli_support` (editor_fail)

| metric | cadr | pi |
|---|---|---|
| `editor_fail` | `edit-in-external-editor` non-zero runner (`src/cadr-cli/support/external-editor.lisp`) | `editInExternalEditor` false-exit failed (`packages/coding-agent/src/modes/interactive/external-editor.ts`) |

Leftover sibling of Pair 868. Timed work is the fail path (original content
kept). Observed `eef_orig` / `eef_empty` / `eef_twice` / `eef_n` are exact. Collect restore n=5 freeze **0.009×** (185.235 /
21216.830 µs) on host `Friend-MachineD`, gitHead `c3c94ecf1`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Under 1× (over-1× table not updated). Same commit no
optimize.

### Pair 870 — `cli_support` (editor_empty)

| metric | cadr | pi |
|---|---|---|
| `editor_empty` | `edit-in-external-editor` empty/one-cell (`src/cadr-cli/support/external-editor.lisp`) | `editInExternalEditor` empty/one-cell complete (`packages/coding-agent/src/modes/interactive/external-editor.ts`) |

Leftover sibling of Pairs 868–869. Timed work is empty and one-cell success
payloads. Observed `eee_ok` / `eee_len` / `eee_x` / `eee_xlen` / `eee_n` are exact. Collect restore n=5 freeze **0.011×** (164.411 /
14612.956 µs) on host `Friend-MachineD`, gitHead `c3c94ecf1`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Under 1× (over-1× table not updated). Same commit no
optimize.

### Pair 871 — `cli_support` (write_hello)

| metric | cadr | pi |
|---|---|---|
| `write_hello` | `atomic-write-utf8` hello (`src/cadr-cli/support/atomic-write.lisp`) | `activateManagedRelease` temp+rename (`packages/coding-agent/src/package-manager-cli.ts`) |

Leftover of the `cli_support` hole on `atomic-write.lisp`. Timed work is first
write of a new file. Observed `awh_hello` / `awh_len` / `awh_file` / `awh_n` are exact. Collect restore n=5 freeze **1.678×** (277.332 /
165.319 µs) on host `Friend-MachineD`, gitHead `c3c94ecf1`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 872 — `cli_support` (write_overwrite)

| metric | cadr | pi |
|---|---|---|
| `write_overwrite` | `atomic-write-utf8` overwrite (`src/cadr-cli/support/atomic-write.lisp`) | `activateManagedRelease` second write (`packages/coding-agent/src/package-manager-cli.ts`) |

Leftover sibling of Pair 871. Timed work is replacing an existing payload.
Observed `awo_second` / `awo_no_first` / `awo_len` / `awo_n` are exact. Collect restore n=5 freeze **1.295×** (438.860 /
338.824 µs) on host `Friend-MachineD`, gitHead `c3c94ecf1`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 873 — `cli_support` (write_empty)

| metric | cadr | pi |
|---|---|---|
| `write_empty` | `atomic-write-utf8` empty (`src/cadr-cli/support/atomic-write.lisp`) | `activateManagedRelease` empty (`packages/coding-agent/src/package-manager-cli.ts`) |

Leftover sibling of Pairs 871–872. Timed work is empty payload still creating
the file. Observed `awe_ok` / `awe_len` / `awe_file` / `awe_n` are exact. Collect restore n=5 freeze **2.790×** (129.194 /
46.306 µs) on host `Friend-MachineD`, gitHead `c3c94ecf1`,
ceiling 15.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 886 — `cli_support` (threads_absent)

| metric | cadr | pi |
|---|---|---|
| `threads_absent` | `stop-thread-for-cleanup` nil (`src/cadr-cli/support/threads.lisp`) | worker_threads absent-handle branch (`node:worker_threads`) |

Leftover of the `cli_support` hole on `cadr-cli/support/threads.lisp`. Timed
work is the nil/absent branch. Observed `cta_eq` / `cta_n` are exact. Collect restore n=5 freeze **1.631×** (0.192 /
0.118 µs) on host `Friend-MachineD`, gitHead `c3c94ecf1`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 887 — `cli_support` (threads_current)

| metric | cadr | pi |
|---|---|---|
| `threads_current` | `stop-thread-for-cleanup` current (`src/cadr-cli/support/threads.lisp`) | `isMainThread` (`node:worker_threads`) |

Leftover sibling of Pair 886. Timed work is the current-thread branch.
Observed `ctc_eq` / `ctc_n` are exact. Collect restore n=5 freeze **1.165×** (0.139 /
0.120 µs) on host `Friend-MachineD`, gitHead `c3c94ecf1`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 888 — `cli_support` (threads_joined)

| metric | cadr | pi |
|---|---|---|
| `threads_joined` | `stop-thread-for-cleanup` joined (`src/cadr-cli/support/threads.lisp`) | Worker eval-exit (`node:worker_threads`) |

Leftover sibling of Pairs 886–887. Timed work is the joined/finished-thread
branch. Observed `ctj_eq` / `ctj_n` are exact. Collect restore n=5 freeze **0.005×** (151.395 /
28910.926 µs) on host `Friend-MachineD`, gitHead `c3c94ecf1`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Under 1× (over-1× table not updated). Same commit no
optimize.


### Pair 874 — `cli_interactive_controller` (announcement_make)

| metric | cadr | pi |
|---|---|---|
| `announcement_make` | `make-earendil-announcement-component` (`src/cadr-cli/interactive/components/announcement.lisp`) | `EarendilAnnouncementComponent` (`packages/coding-agent/src/modes/interactive/components/earendil-announcement.ts`) |

Leftover of the `cli_selectors` hole on `announcement.lisp` (timed under
`cli_interactive_controller`). Timed work is component construction.
Observed `eam_ok` / `eam_min` / `eam_n` are exact. Collect restore n=5 freeze **0.039×** (10.159 /
257.748 µs) on host `Friend-MachineD`, gitHead `78aa2cb75`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Under 1× (over-1× table not updated). Same commit no
optimize.

### Pair 875 — `cli_interactive_controller` (announcement_url)

| metric | cadr | pi |
|---|---|---|
| `announcement_url` | `+earendil-blog-url+` in render (`src/cadr-cli/interactive/components/announcement.lisp`) | `BLOG_URL` in render (`packages/coding-agent/src/modes/interactive/components/earendil-announcement.ts`) |

Leftover sibling of Pair 874. Timed work is blog URL presence in the
rendered announcement. Observed `eau_eq` / `eau_sold` / `eau_n` are exact. Collect restore n=5 freeze **0.149×** (70.638 /
475.352 µs) on host `Friend-MachineD`, gitHead `78aa2cb75`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Under 1× (over-1× table not updated). Same commit no
optimize.

### Pair 876 — `cli_interactive_controller` (announcement_title)

| metric | cadr | pi |
|---|---|---|
| `announcement_title` | title string in render (`src/cadr-cli/interactive/components/announcement.lisp`) | `"pi has joined Earendil"` (`packages/coding-agent/src/modes/interactive/components/earendil-announcement.ts`) |

Leftover sibling of Pairs 874–875. Timed work is title string presence.
Observed `eat_eq` / `eat_pi` / `eat_n` are exact. Collect restore n=5 freeze **0.412×** (71.844 /
174.317 µs) on host `Friend-MachineD`, gitHead `78aa2cb75`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Under 1× (over-1× table not updated). Same commit no
optimize.


### Pair 883 — `ai_support` (threads_absent)

| metric | cadr | pi |
|---|---|---|
| `threads_absent` | `stop-thread-for-cleanup` nil (`src/cadr-ai/support/threads.lisp`) | worker_threads absent-handle (`node:worker_threads`) |

Leftover of the `ai_support` hole on `cadr-ai/support/threads.lisp`. Timed
work is the nil/absent branch. Observed `tha_eq` / `tha_n` are exact. Collect restore n=5 freeze **2.141×** (0.165 /
0.077 µs) on host `Friend-MachineD`, gitHead `571ec063b`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 884 — `ai_support` (threads_current)

| metric | cadr | pi |
|---|---|---|
| `threads_current` | `stop-thread-for-cleanup` current (`src/cadr-ai/support/threads.lisp`) | `isMainThread` (`node:worker_threads`) |

Leftover sibling of Pair 883. Timed work is the current-thread branch.
Observed `thc_eq` / `thc_n` are exact. Collect restore n=5 freeze **1.882×** (0.135 /
0.072 µs) on host `Friend-MachineD`, gitHead `571ec063b`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 885 — `ai_support` (threads_joined)

| metric | cadr | pi |
|---|---|---|
| `threads_joined` | `stop-thread-for-cleanup` joined (`src/cadr-ai/support/threads.lisp`) | Worker eval-exit (`node:worker_threads`) |

Leftover sibling of Pairs 883–884. Timed work is the joined/finished-thread
branch. Observed `thj_eq` / `thj_n` are exact. Collect restore n=5 freeze **0.005×** (142.465 /
30428.377 µs) on host `Friend-MachineD`, gitHead `571ec063b`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Under 1× (over-1× table not updated). Same commit no
optimize.


### Pair 751 — `provider_registry_defs` (runtime_provider)

| metric | cadr | pi |
|---|---|---|
| `runtime_provider` | `make-built-in-runtime-provider` (`src/cadr-ai/providers/runtime-projection.lisp`) | `builtinProviders` openai (`packages/ai/src/providers/all.ts`) |

Leftover of the `provider_registry_defs` hole. Timed work is constructing the
openai runtime-provider — not `stream-chat`. Observed `rp_id` / `rp_key` / `rp_no_oauth` / `rp_models` / `rp_n` are exact. Collect restore n=5 freeze **0.037×** (10.134 /
276.451 µs) on host `Friend-MachineD`, gitHead `473e3bb84`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Under 1× (over-1× table not updated). Same commit no
optimize.

### Pair 752 — `provider_registry_defs` (runtime_provider_copilot)

| metric | cadr | pi |
|---|---|---|
| `runtime_provider_copilot` | `make-built-in-runtime-provider` github-copilot (`src/cadr-ai/providers/runtime-projection.lisp`) | `githubCopilotProvider` (`packages/ai/src/providers/github-copilot.ts`) |

Leftover sibling of Pair 751. Timed work is oauth/login/filter/models flags —
not login I/O. Observed `rpc_oauth` / `rpc_login` / `rpc_filter` / `rpc_models` / `rpc_n` are exact. Collect restore n=5 freeze **0.546×** (8.428 /
15.424 µs) on host `Friend-MachineD`, gitHead `473e3bb84`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Under 1× (over-1× table not updated). Same commit no
optimize.

### Pair 753 — `provider_registry_defs` (models_runtime)

| metric | cadr | pi |
|---|---|---|
| `models_runtime` | `make-built-in-models-runtime` (`src/cadr-ai/providers/runtime-projection.lisp`) | `builtinProviders` installed into a Map (`packages/ai/src/providers/all.ts`) |

Leftover sibling of Pairs 751–752. Timed work is installing every built-in
runtime-provider — not `stream-chat`. Observed `mr_oa` / `mr_anth` / `mr_miss` / `mr_env` / `mr_n` are exact. Collect restore n=5 freeze **1.596×** (412.117 /
258.229 µs) on host `Friend-MachineD`, gitHead `473e3bb84`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 754 — `provider_registry_defs` (protocol_provider)

| metric | cadr | pi |
|---|---|---|
| `protocol_provider` | `make-protocol-provider` openai-responses (`src/cadr-ai/providers/registry.lisp`) | `openAIResponsesApi` (`packages/ai/src/api/openai-responses.lazy.ts`) |

Leftover that closes the `registry.lisp` needs-pair hole. Timed work is
protocol adapter construct — not `stream-chat`. Observed `pp_stream` / `pp_simple` / `pp_miss` / `pp_diff` / `pp_n` are exact. Collect restore n=5 freeze **1.293×** (1.756 /
1.358 µs) on host `Friend-MachineD`, gitHead `473e3bb84`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 755 — `provider_registry_defs` (protocol_provider_anthropic)

| metric | cadr | pi |
|---|---|---|
| `protocol_provider_anthropic` | `make-protocol-provider` anthropic-messages (`src/cadr-ai/providers/registry.lisp`) | `anthropicMessagesApi` (`packages/ai/src/api/anthropic-messages.lazy.ts`) |

Leftover sibling of Pair 754. Timed work is native oauth token / type flags —
not login I/O. Observed `ppa_id` / `ppa_oauth` / `ppa_type` / `ppa_diff` / `ppa_n` are exact. Collect restore n=5 freeze **0.113×** (0.685 /
6.046 µs) on host `Friend-MachineD`, gitHead `473e3bb84`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Under 1× (over-1× table not updated). Same commit no
optimize.

### Pair 756 — `provider_registry_defs` (instantiate_provider)

| metric | cadr | pi |
|---|---|---|
| `instantiate_provider` | `instantiate-provider` openai (`src/cadr-ai/providers/registry.lisp`) | `openaiProvider` + `getModels` (`packages/ai/src/providers/openai.ts`) |

Leftover sibling of Pairs 754–755. Timed work is protocol adapter + default
model metadata — not `stream-chat`. Observed `ip_id` / `ip_api` / `ip_model` / `ip_type` / `ip_n` are exact. Collect restore n=5 freeze **0.187×** (1.343 /
7.186 µs) on host `Friend-MachineD`, gitHead `473e3bb84`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Under 1× (over-1× table not updated). Same commit no
optimize.


### Pair 838 — `cli_bootstrap_sessions` (data_directory)

| metric | cadr | pi |
|---|---|---|
| `data_directory` | `data-directory` (`src/cadr-cli/migration.lisp`) | `join(home, CONFIG_DIR_NAME)` |

Leftover of the `cli_bootstrap_sessions` hole on `migration.lisp`. Timed work is
user data dir under an explicit home. Observed `dd_under` / `dd_neq` / `dd_dot` are exact. Collect restore n=5 freeze **9.926×** (8.765 /
0.883 µs) on host `Friend-MachineD`, gitHead `cc0d0c6ea`,
ceiling 40.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 839 — `cli_bootstrap_sessions` (legacy_data_directory)

| metric | cadr | pi |
|---|---|---|
| `legacy_data_directory` | `legacy-data-directory` (`src/cadr-cli/migration.lisp`) | `join(home, '.' + legacy product)` |

Leftover sibling of Pair 838. Observed `ldd_under` / `ldd_neq` / `ldd_leaf` are exact. Collect restore n=5 freeze **7.950×** (8.924 /
1.122 µs) on host `Friend-MachineD`, gitHead `cc0d0c6ea`,
ceiling 40.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 840 — `cli_bootstrap_sessions` (manual_migration_command)

| metric | cadr | pi |
|---|---|---|
| `manual_migration_command` | `manual-migration-command` (`src/cadr-cli/migration.lisp`) | `mv --` + quoted paths |

Leftover sibling of Pairs 838–839. Observed `mmc_mv` / `mmc_old` / `mmc_new` / `mmc_space` / `mmc_quote` are exact. Collect restore n=5 freeze **2.726×** (4.577 /
1.679 µs) on host `Friend-MachineD`, gitHead `cc0d0c6ea`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 841 — `cli_bootstrap_sessions` (managed_binary_names)

| metric | cadr | pi |
|---|---|---|
| `managed_binary_names` | `+managed-binary-names+` (`src/cadr-cli/migration.lisp`) | fd/rg (+ `.exe`) names |

Leftover sibling of Pairs 838–840. Observed `mbn_n` / `mbn_fd` / `mbn_rg` / `mbn_fdexe` / `mbn_rgexe` are exact. Collect restore n=5 freeze **1.362×** (0.430 /
0.315 µs) on host `Friend-MachineD`, gitHead `cc0d0c6ea`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 842 — `cli_bootstrap_sessions` (migration_guide_url)

| metric | cadr | pi |
|---|---|---|
| `migration_guide_url` | `+migration-guide-url+` (`src/cadr-cli/migration.lisp`) | `MIGRATION_GUIDE_URL` |

Leftover sibling of Pair 841. Observed `mgu_eq` / `mgu_https` / `mgu_gh` / `mgu_n` are exact. Collect restore n=5 freeze **3.089×** (0.656 /
0.212 µs) on host `Friend-MachineD`, gitHead `cc0d0c6ea`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 843 — `cli_bootstrap_sessions` (extensions_doc_url)

| metric | cadr | pi |
|---|---|---|
| `extensions_doc_url` | `+extensions-doc-url+` (`src/cadr-cli/migration.lisp`) | `EXTENSIONS_DOC_URL` |

Leftover sibling of Pair 842. Observed `edu_eq` / `edu_https` / `edu_gh` / `edu_n` are exact. Collect restore n=5 freeze **2.691×** (0.549 /
0.204 µs) on host `Friend-MachineD`, gitHead `cc0d0c6ea`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.


### Pair 919 — `skill_prompt_load` (sdk_get_skills)

| metric | cadr | pi |
|---|---|---|
| `sdk_get_skills` | `sdk-resource-loader-skills` (`src/cadr-cli/sdk/resource-service.lisp`) | `DefaultResourceLoader.getSkills` (`packages/coding-agent/src/core/resource-loader.ts`) |

Leftover of the `skill_prompt_load` hole on `resource-service.lisp`. Timed work is
the skills getter after isolated no-discovery reload. Observed `sk_n` / `sk_list` / `sk_ok` are exact. Collect restore n=5 freeze **1.587×** (0.175 /
0.110 µs) on host `Friend-MachineD`, gitHead `a2fe765ab`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 920 — `skill_prompt_load` (sdk_get_prompts)

| metric | cadr | pi |
|---|---|---|
| `sdk_get_prompts` | `sdk-resource-loader-prompts` (`src/cadr-cli/sdk/resource-service.lisp`) | `DefaultResourceLoader.getPrompts` (`packages/coding-agent/src/core/resource-loader.ts`) |

Leftover sibling of Pair 919. Observed `pr_n` / `pr_list` / `pr_ok` are exact. Collect restore n=5 freeze **1.367×** (0.167 /
0.123 µs) on host `Friend-MachineD`, gitHead `a2fe765ab`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 921 — `skill_prompt_load` (sdk_get_themes)

| metric | cadr | pi |
|---|---|---|
| `sdk_get_themes` | `sdk-resource-loader-themes` (`src/cadr-cli/sdk/resource-service.lisp`) | `DefaultResourceLoader.getThemes` (`packages/coding-agent/src/core/resource-loader.ts`) |

Leftover sibling of Pairs 919–920. Observed `th_n` / `th_list` / `th_ok` are exact. Collect restore n=5 freeze **2.560×** (0.298 /
0.117 µs) on host `Friend-MachineD`, gitHead `a2fe765ab`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.


### Pair 763 — `settings_load` (sdk_default_provider)

| metric | cadr | pi |
|---|---|---|
| `sdk_default_provider` | `sdk-settings-default-provider` (`src/cadr-cli/sdk/settings-service.lisp`) | `SettingsManager.getDefaultProvider` (`packages/coding-agent/src/core/settings-manager.ts`) |

Leftover of the `settings_load` hole on `settings-service.lisp`. Timed work is
in-memory defaultProvider lookup. Observed `sdp_hit` / `sdp_miss` / `sdp_len` / `sdp_str` / `sdp_n` are exact. Collect restore n=5 freeze **2.335×** (34.963 /
14.971 µs) on host `Friend-MachineD`, gitHead `d6e0870f6`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 764 — `settings_load` (sdk_default_model)

| metric | cadr | pi |
|---|---|---|
| `sdk_default_model` | `sdk-settings-default-model` (`src/cadr-cli/sdk/settings-service.lisp`) | `SettingsManager.getDefaultModel` (`packages/coding-agent/src/core/settings-manager.ts`) |

Leftover sibling of Pair 763. Observed `sdm_hit` / `sdm_miss` / `sdm_len` / `sdm_str` / `sdm_n` are exact. Collect restore n=5 freeze **5.024×** (36.317 /
7.229 µs) on host `Friend-MachineD`, gitHead `d6e0870f6`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 765 — `settings_load` (sdk_retry_settings)

| metric | cadr | pi |
|---|---|---|
| `sdk_retry_settings` | `sdk-settings-retry-settings` (`src/cadr-cli/sdk/settings-service.lisp`) | `SettingsManager.getRetrySettings` (`packages/coding-agent/src/core/settings-manager.ts`) |

Leftover sibling of Pairs 763–764. Observed `srs_en` / `srs_max` / `srs_base` / `srs_empty` / `srs_n` are exact. Collect restore n=5 freeze **1.819×** (19.285 /
10.602 µs) on host `Friend-MachineD`, gitHead `d6e0870f6`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.


### Pair 1012 — `cli_bootstrap_sessions` (pb_ok)

| metric | cadr | pi |
|---|---|---|
| `pb_ok` | `parse-user-bash-input` (`src/cadr-cli/repl.lisp`) | leftover replica of `!` / `!!` bash extract |

Leftover of the last `cli_bootstrap_sessions` needs-pair file. Does not remount
`parse_bash`. Timed work is bang-prefix parse. Observed `pb_ls` / `pb_n` are exact. Collect restore n=5 freeze **0.804×** (0.820 /
1.020 µs) on host `Friend-MachineD`, gitHead `ceb8a4cb3`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Under 1×. Same commit no
optimize.

### Pair 1013 — `cli_bootstrap_sessions` (rt_ok)

| metric | cadr | pi |
|---|---|---|
| `rt_ok` | `response-text` (`src/cadr-cli/repl.lisp`) | leftover replica of textParts.join |

Leftover sibling of Pair 1012. Does not remount `response_text`.
Observed `rt_one` / `rt_empty` are exact. Collect restore n=5 freeze **2.499×** (1.475 /
0.590 µs) on host `Friend-MachineD`, gitHead `ceb8a4cb3`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 1014 — `cli_bootstrap_sessions` (dp_ok)

| metric | cadr | pi |
|---|---|---|
| `dp_ok` | `dispatch-user-input` (`src/cadr-cli/repl.lisp`) | leftover replica of submit classify |

Leftover sibling of Pairs 1012–1013. Does not remount `dispatch_plain`.
Observed `dp_empty` / `dp_n` are exact. Collect restore n=5 freeze **0.618×** (0.654 /
1.059 µs) on host `Friend-MachineD`, gitHead `ceb8a4cb3`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Under 1×. Same commit no
optimize.


### Pair 439 — `evals_harness` (extension_authoring_input)

| metric | cadr | pi |
|---|---|---|
| `extension_authoring_input` | `extension-authoring-input` (`src/cadr-evals/suites.lisp`) | `describeEval` input steps (`packages/evals/src/extensions.eval.ts`) |

Leftover of the `evals_harness` hole on `suites.lisp`. Timed work is the
three-step extension-authoring input vector (prompt / reload / prompt).
Types and length only — product copy in prompt strings is not an exact
key (Cadr vs Pi). Observed `ei_n` / `ei_t0` / `ei_t1` / `ei_t2` / `ei_c0`
are exact. First n=5 freeze **4.662×** (1.148 / 0.246 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old
holes `lc_n` / `lc_sleep` / help text; this metric did not fail). Over-1×
booked. Same commit no optimize.

### Pair 440 — `evals_harness` (json_array_items)

| metric | cadr | pi |
|---|---|---|
| `json_array_items` | `json-array-items` (`src/cadr-evals/suites.lisp`) | `Array.isArray` judge helper (`packages/evals/src/extensions.eval.ts`) |

Leftover sibling of Pair 439 on the same `evals_harness` hole. Timed work
is vector/list → sequence, atom and NIL → NIL — not the hello judge, not
`extension-authoring-input`. Observed `ja_vec` / `ja_list` / `ja_atom` /
`ja_nil` are exact. First n=5 freeze **0.766×** (0.162 / 0.212 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Same commit no optimize.

### Pair 441 — `evals_harness` (json_string)

| metric | cadr | pi |
|---|---|---|
| `json_string` | `json-string` (`src/cadr-evals/suites.lisp`) | missing/false JSON string accessor (`packages/evals/src/extensions.eval.ts`) |

Leftover sibling of Pairs 439–440 on the same `evals_harness` hole. Timed
work is `(or (json-get …) "")` — present string kept, missing and NIL
become empty. Observed `js_hit` / `js_miss` / `js_empty` are exact. First
n=5 freeze **5.012×** (0.902 / 0.180 µs) on host `cursor`, ceiling 8.0.
Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Over-1× booked. Same
commit no optimize.

### Pair 442 — `package_manager` (normalize_pattern)

| metric | cadr | pi |
|---|---|---|
| `normalize_pattern` | `config-normalize-pattern-path` (`src/cadr-cli/packages/config-selector.lisp`) | `normalizeExactPattern` (`packages/coding-agent/src/core/package-manager.ts`) |

Leftover of the `package_manager` hole on `config-selector.lisp`. Timed work
is `./` and `.\` prefix strip plus slash fold — not resolve, not
`config-glob-regex`. Observed `np_dot` / `np_plain` / `np_win` are exact.
First n=5 freeze **0.650×** (0.444 / 0.683 µs) on host `cursor`, ceiling
8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 443 — `package_manager` (resource_kinds)

| metric | cadr | pi |
|---|---|---|
| `resource_kinds` | `config-resource-kinds` (`src/cadr-cli/packages/config-selector.lisp`) | `RESOURCE_TYPES` (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pair 442 on the same `package_manager` hole. Timed work
is the four-kind extensions/skills/prompts/themes table — not selector
render, not package resolve. Observed `rk_n` / `rk_ext` / `rk_sk` /
`rk_pr` / `rk_th` are exact. First n=5 freeze **0.756×** (0.117 / 0.155 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1
only from known old holes `lc_n` / `lc_sleep` / help text; this metric
did not fail). Same commit no optimize.

### Pair 444 — `package_manager` (type_label)

| metric | cadr | pi |
|---|---|---|
| `type_label` | `config-resource-type-label` (`src/cadr-cli/packages/config-selector.lisp`) | `RESOURCE_TYPE_LABELS` (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pairs 442–443 on the same `package_manager` hole. Timed
work is the four display labels Extensions/Skills/Prompts/Themes — not
`config-resource-display-name`. Observed `tl_ext` / `tl_sk` / `tl_pr` /
`tl_th` are exact. First n=5 freeze **1.002×** (0.135 / 0.134 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Over-1× booked. Same commit no optimize.

### Pair 445 — `package_manager` (update_argv)

| metric | cadr | pi |
|---|---|---|
| `update_argv` | `package-update-check-process-argv` (`src/cadr-cli/packages/update-checks.lisp`) | git argv wrap for `runGitRemoteCommand` (`packages/coding-agent/src/core/package-manager.ts`) |

Leftover of the `package_manager` hole on `update-checks.lisp`. Timed work
is setsid `--fork --wait` argv construction on POSIX — not spawn, not
`default-package-update-check-runner`. Observed `ua_setsid` / `ua_fork` /
`ua_tail` / `ua_rest` are exact. Collect restore n=5 freeze **2.579×** (8.431 /
3.270 µs) on host `Friend-MachineD`, gitHead `1cc6098c9`, ceiling 8.0. Overlay
recorded; py full gate rc=2 from leftover `parsed_provider` METRICS pollution.
Over-1× booked. Same commit no optimize.

### Pair 446 — `package_manager` (update_env)

| metric | cadr | pi |
|---|---|---|
| `update_env` | `package-update-check-environment` (`src/cadr-cli/packages/update-checks.lisp`) | `GIT_TERMINAL_PROMPT=0` on `runGitRemoteCommand` (`packages/coding-agent/src/core/package-manager.ts`) |

Leftover sibling of Pair 445 on the same `package_manager` hole. Timed work
is injecting `GIT_TERMINAL_PROMPT=0` and dropping prior copies — not git
exec. Observed `ue_first` / `ue_one` are exact. Collect restore n=5 freeze
**0.232×** (12.977 / 55.823 µs) on host `Friend-MachineD`, gitHead `1cc6098c9`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Under-1×. Same commit no optimize.

### Pair 447 — `package_manager` (git_object_id)

| metric | cadr | pi |
|---|---|---|
| `git_object_id` | `package-update-git-object-id` (`src/cadr-cli/packages/update-checks.lisp`) | `getRemoteGitHead` 40-hex extract (`packages/coding-agent/src/core/package-manager.ts`) |

Leftover sibling of Pairs 445–446 on the same `package_manager` hole. Timed
work is trimming the first 40-hex token (rev-parse / ls-remote) — not
`package-git-update-available-p`. Observed `go_plain` / `go_nl` / `go_ls` /
`go_upper` / `go_bad` are exact. Collect restore n=5 freeze **3.013×** (3.300 /
1.095 µs) on host `Friend-MachineD`, gitHead `1cc6098c9`, ceiling 8.0. Overlay
recorded; py full gate rc=2 from leftover `parsed_provider` METRICS pollution.
Over-1× booked. Same commit no optimize.

### Pair 448 — `find_tool` (glob_regex)

| metric | cadr | pi |
|---|---|---|
| `glob_regex` | `glob-regex-source` (`src/cadr-cli/tools/glob.lisp`) | glob pattern compile (`packages/coding-agent/src/core/tools/find.ts`) |

Leftover of the `agent_tool_loop` hole on `glob.lisp`. Timed work is `*` /
`**` / `?` / `.` glob-to-regex source. Observed `gr_star` / `gr_glob` /
`gr_q` / `gr_dot` are exact. First n=5 freeze **2.403×** (0.527 / 0.220 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text; this metric did not
fail). Over-1× booked. Same commit no optimize.

### Pair 449 — `find_tool` (glob_special)

| metric | cadr | pi |
|---|---|---|
| `glob_special` | `regex-special-p` (`src/cadr-cli/tools/glob.lisp`) | glob regex metacharacters (`packages/coding-agent/src/core/tools/find.ts`) |

Leftover sibling of Pair 448 on the same `find_tool` hole. Timed work is
the metacharacter table for glob compile. Observed `gs_dot` / `gs_star` /
`gs_pipe` / `gs_bs` are exact. First n=5 freeze **0.549×** (0.082 / 0.149 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text; this metric did not
fail). Same commit no optimize.

### Pair 450 — `find_tool` (gitignore_regex)

| metric | cadr | pi |
|---|---|---|
| `gitignore_regex` | `gitignore-regex-source` (`src/cadr-cli/tools/glob.lisp`) | gitignore glob compile (`packages/coding-agent/src/core/tools/find.ts`) |

Leftover sibling of Pairs 448–449 on the same `find_tool` hole. Timed work
is anchored / directory-only / plain gitignore regex source. Observed
`gi_plain` / `gi_anch` / `gi_dir` are exact. First n=5 freeze **1.142×**
(0.693 / 0.607 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text;
this metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 451 — `cli_bootstrap_sessions` (session_path)

| metric | cadr | pi |
|---|---|---|
| `session_path` | `session-argument-path-p` (`src/cadr-cli/bootstrap/sessions.lisp`) | `resolveSessionPath` path heuristic (`packages/coding-agent/src/main.ts`) |

Leftover of the `cli_bootstrap_sessions` hole on `sessions.lisp`. Timed work
is slash / backslash / `.jsonl` path detection. Observed `sp_id` /
`sp_slash` / `sp_win` / `sp_jsonl` / `sp_plain` are exact. First n=5 freeze
**0.752×** (0.294 / 0.391 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce`. Same commit no optimize.

### Pair 452 — `cli_bootstrap_sessions` (split_command)

| metric | cadr | pi |
|---|---|---|
| `split_command` | `split-command` (`src/cadr-cli/bootstrap/sessions.lisp`) | first-token slash split (`packages/coding-agent/src/cli`) |

Leftover sibling of Pair 451 on the same hole. Timed work is trim plus
first space/tab split. Observed `sc_cmd` / `sc_arg` / `sc_only` /
`sc_noarg` / `sc_cmd3` / `sc_rest` are exact. First n=5 freeze **0.937×**
(0.491 / 0.524 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`.
Same commit no optimize.

### Pair 453 — `cli_bootstrap_sessions` (path_argument)

| metric | cadr | pi |
|---|---|---|
| `path_argument` | `path-command-argument` (`src/cadr-cli/bootstrap/sessions.lisp`) | quoted path after command (`packages/coding-agent/src/cli`) |

Leftover sibling of Pairs 451–452 on the same hole. Timed work is the
path token after a command, including quotes. Observed `pa_plain` /
`pa_quote` / `pa_empty` / `pa_miss` are exact. First n=5 freeze **0.598×**
(0.379 / 0.633 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`.
Same commit no optimize.

### Pair 454 — `settings_load` (provider_symbol)

| metric | cadr | pi |
|---|---|---|
| `provider_symbol` | `provider-symbol` (`src/cadr-cli/config.lisp`) | upcase keyword intern (`packages/coding-agent/src/config.ts`) |

Leftover of the `settings_load` hole on `config.lisp`. Timed work is
string-upcase intern to keyword. Observed `ps_openai` / `ps_mixed` /
`ps_hyphen` are exact. First n=5 freeze **1.351×** (0.313 / 0.231 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Same commit
no optimize. Over-1× booked.

### Pair 455 — `settings_load` (parse_auth_provider)

| metric | cadr | pi |
|---|---|---|
| `parse_auth_provider` | `parse-auth-provider` (`src/cadr-cli/config.lisp`) | openai / openai-codex / anthropic identity (`packages/coding-agent/src/cli`) |

Leftover sibling of Pair 454 on the same hole. Timed work is OAuth provider
identity plus the configuration-error message. Observed `pap_openai` /
`pap_anth` / `pap_codex` / `pap_bad` are exact. First n=5 freeze
**0.365×** (0.846 / 2.314 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce`. Same commit no optimize.

### Pair 456 — `settings_load` (split_command_line)

| metric | cadr | pi |
|---|---|---|
| `split_command_line` | `split-command-line` (`src/cadr-cli/config.lisp`) | space/tab command-line split (`packages/coding-agent/src/cli`) |

Leftover sibling of Pairs 454–455 on the same hole. Timed work is trim plus
space/tab split dropping empties. Observed `scl_two` / `scl_trim` /
`scl_empty` are exact. First n=5 freeze **0.967×** (0.939 / 0.971 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Same commit
no optimize.

### Pair 457 — `cli_bootstrap_sessions` (legacy_product)

| metric | cadr | pi |
|---|---|---|
| `legacy_product` | `legacy-product-name` (`src/cadr-cli/migration.lisp`) | legacy product directory name (`packages/coding-agent/src/migrations.ts`) |

Leftover of the `cli_bootstrap_sessions` hole on `migration.lisp`. Timed work
is the two-character product name plus `-cl`. Observed `lp_len` / `lp_p` /
`lp_i` are exact. First n=5 freeze **1.178×** (0.171 / 0.145 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce`. Same commit no optimize.
Over-1× booked.

### Pair 458 — `cli_bootstrap_sessions` (shell_quote)

| metric | cadr | pi |
|---|---|---|
| `shell_quote` | `shell-single-quote` (`src/cadr-cli/migration.lisp`) | POSIX single-quote wrap (`packages/coding-agent/src/migrations.ts`) |

Leftover sibling of Pair 457 on the same hole. Timed work is wrapping plus
embedded-quote escape. Observed `sq_plain` / `sq_space` / `sq_quote` /
`sq_empty` are exact. First n=5 freeze **0.714×** (0.461 / 0.645 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce`. Same commit no optimize.

### Pair 459 — `cli_bootstrap_sessions` (affirmative)

| metric | cadr | pi |
|---|---|---|
| `affirmative` | `affirmative-response-p` (`src/cadr-cli/migration.lisp`) | y/yes consent trim (`packages/coding-agent/src/migrations.ts`) |

Leftover sibling of Pairs 457–458 on the same hole. Timed work is trim plus
downcase membership in y/yes. Observed `af_y` / `af_yes` / `af_trim` /
`af_no` are exact. First n=5 freeze **0.584×** (0.371 / 0.635 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce`. Same commit no optimize.

### Pair 460 — `cli_support` (no_models_help)

| metric | cadr | pi |
|---|---|---|
| `no_models_help` | `format-no-models-available-message` (`src/cadr-cli/support/model-help.lisp`) | `formatNoModelsAvailableMessage` (`packages/coding-agent/src/core/auth-guidance.ts`) |

Leftover of the `cli_support` hole on `model-help.lisp`. Timed work is the
CLI wrapper over the no-models guidance string. Observed `nm_pref` /
`nm_login` / `nm_prov` are exact. First n=5 freeze **27.45×** (244.9 / 8.92 µs)
on host `cursor`, ceiling 50.0 (docs-dir sibling of `ai_support.auth_guidance`).
Gate used `--only-enforce`. Same commit no optimize. Over-1× booked.

### Pair 461 — `cli_support` (no_model_selected)

| metric | cadr | pi |
|---|---|---|
| `no_model_selected` | `format-no-model-selected-message` (`src/cadr-cli/support/model-help.lisp`) | `formatNoModelSelectedMessage` (`packages/coding-agent/src/core/auth-guidance.ts`) |

Leftover sibling of Pair 460 on the same hole. Timed work is the CLI wrapper
over the no-model-selected guidance string. Observed `ns_pref` / `ns_then` /
`ns_nl` are exact. First n=5 freeze **27.67×** (245.4 / 8.87 µs) on host
`cursor`, ceiling 50.0. Gate used `--only-enforce`. Same commit no optimize.
Over-1× booked.

### Pair 462 — `cli_support` (no_api_key)

| metric | cadr | pi |
|---|---|---|
| `no_api_key` | `format-no-api-key-found-message` (`src/cadr-cli/support/model-help.lisp`) | `formatNoApiKeyFoundMessage` (`packages/coding-agent/src/core/auth-guidance.ts`) |

Leftover sibling of Pairs 460–461 on the same hole. Timed work is the CLI
wrapper over openai/unknown no-key guidance. Observed `nk_oai` / `nk_unk` /
`nk_sel` are exact. First n=5 freeze **27.48×** (480.3 / 17.48 µs) on host
`cursor`, ceiling 50.0. Gate used `--only-enforce`. Same commit no optimize.
Over-1× booked.

### Pair 463 — `cli_print_rpc` (rpc_images)

| metric | cadr | pi |
|---|---|---|
| `rpc_images` | `rpc-images-from-json` (`src/cadr-cli/modes/rpc/prompt-bash.lisp`) | prompt `command.images` (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |

Leftover of the `cli_print_rpc` hole on `prompt-bash.lisp`. Timed work is JSON
image-array parse into image content. Observed `img_nil` / `img_n` /
`img_mime` / `img_bad` are exact. First n=5 freeze **0.657×** (2.260 / 3.439 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Same commit no
optimize.

### Pair 464 — `cli_print_rpc` (rpc_prompt)

| metric | cadr | pi |
|---|---|---|
| `rpc_prompt` | `rpc-prompt-message` (`src/cadr-cli/modes/rpc/prompt-bash.lisp`) | prompt message+images (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |

Leftover sibling of Pair 463 on the same hole. Timed work is user-message
assembly from RPC text and optional images. Observed `rp_str` / `rp_len` /
`rp_parts` / `rp_mime` are exact. First n=5 freeze **2.266×** (1.323 / 0.584 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Same commit no
optimize. Over-1× booked.

### Pair 465 — `cli_print_rpc` (bash_result)

| metric | cadr | pi |
|---|---|---|
| `bash_result` | `rpc-bash-result-json` (`src/cadr-cli/modes/rpc/prompt-bash.lisp`) | bash result payload (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |

Leftover sibling of Pairs 463–464 on the same hole. Timed work is RPC bash
result object assembly (footer strip, exit, cancelled, truncated, path).
Observed `br_out` / `br_code` / `br_can` / `br_tr` / `br_path` / `br_null`
are exact. First n=5 freeze **2.913×** (2.165 / 0.743 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce`. Same commit no optimize. Over-1×
booked.

### Pair 466 — `cli_print_rpc` (dialog_request)

| metric | cadr | pi |
|---|---|---|
| `dialog_request` | `rpc-dialog-request-object` (`src/cadr-cli/modes/rpc/ui.lisp`) | `createDialogPromise` request object (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |

Leftover of the `cli_print_rpc` hole on `ui.lisp`. Timed work is extension UI
request object assembly. Observed `dr_type` / `dr_method` / `dr_msg` /
`dr_opt_n` / `dr_ph` / `dr_to` are exact. Collect restore n=5 freeze **2.423×**
(1.570 / 0.648 µs) on host `Friend-MachineD`, gitHead `1cc6098c9`, ceiling 8.0.
Overlay recorded; py full gate rc=2 from leftover `parsed_provider` METRICS
pollution. Over-1× booked. Same commit no optimize.

### Pair 467 — `cli_print_rpc` (dialog_result)

| metric | cadr | pi |
|---|---|---|
| `dialog_result` | `rpc-dialog-result` (`src/cadr-cli/modes/rpc/ui.lisp`) | `createDialogPromise` parseResponse (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |

Leftover sibling of Pair 466 on the same hole. Timed work is confirm/select
response parse (cancelled, confirmed, string value). Observed `rs_nil` /
`rs_can` / `rs_ok` / `rs_val` / `rs_num` are exact. Collect restore n=5 freeze
**6.823×** (2.387 / 0.350 µs) on host `Friend-MachineD`, gitHead `1cc6098c9`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no optimize.

### Pair 468 — `cli_print_rpc` (dialog_expired)

| metric | cadr | pi |
|---|---|---|
| `dialog_expired` | `rpc-dialog-expired-p` (`src/cadr-cli/modes/rpc/ui.lisp`) | `createDialogPromise` timeout (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |

Leftover sibling of Pairs 466–467 on the same hole. Timed work is dialog
deadline comparison. Observed `ex_nil` / `ex_zero` / `ex_future` are exact.
Collect restore n=5 freeze **0.488×** (0.188 / 0.386 µs) on host
`Friend-MachineD`, gitHead `1cc6098c9`, ceiling 8.0. Overlay recorded; py full
gate rc=2 from leftover `parsed_provider` METRICS pollution. Under-1×. Same
commit no optimize.

### Pair 469 — `settings_load` (sdk_nonempty)

| metric | cadr | pi |
|---|---|---|
| `sdk_nonempty` | `sdk-nonempty-setting-string` (`src/cadr-cli/sdk/settings-service.lisp`) | nonempty `getDefaultProvider` (`packages/coding-agent/src/core/settings-manager.ts`) |

Leftover of the `settings_load` hole on `settings-service.lisp`. Timed work is
nonempty string setting lookup on a CLOS/`SettingsManager.inMemory` manager
(not a plain-object walk). Observed `sn_prov` / `sn_empty` / `sn_miss`
are exact. First n=5 freeze **3.319×** (20.855 / 6.284 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old
holes `lc_n` / `lc_sleep` / help text; this metric did not fail). Same
commit no optimize.

### Pair 470 — `settings_load` (sdk_boolean)

| metric | cadr | pi |
|---|---|---|
| `sdk_boolean` | `sdk-settings-boolean` (`src/cadr-cli/sdk/settings-service.lisp`) | compaction.enabled boolean (`packages/coding-agent/src/core/settings-manager.ts`) |

Leftover sibling of Pair 469 on the same hole. Timed work is nested JSON
boolean with default (`getCompactionEnabled` on the pi side). Observed
`sb_on` / `sb_def` / `sb_miss` are exact. First n=5 freeze **2.136×**
(13.423 / 6.283 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 471 — `settings_load` (sdk_tools)

| metric | cadr | pi |
|---|---|---|
| `sdk_tools` | `sdk-settings-enabled-tools` (`src/cadr-cli/sdk/settings-service.lisp`) | defaultTools list (`packages/coding-agent/src/core/settings-manager.ts`) |

Leftover sibling of Pairs 469–470 on the same hole. Timed work is tools
array-to-list projection (`getDefaultTools` on the pi side). Observed
`st_n` / `st_read` / `st_none` are exact. First n=5 freeze **2.037×**
(12.769 / 6.268 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 472 — `skill_prompt_load` (resolve_prompt)

| metric | cadr | pi |
|---|---|---|
| `resolve_prompt` | `resolve-system-prompt` (`src/cadr-cli/system-prompt.lisp`) | `resolvePromptInput` (`packages/coding-agent/src/core/resource-loader.ts`) |

Leftover of the `skill_prompt_load` hole on `system-prompt.lisp`. Timed work
is literal / file / missing-path prompt resolution — not
`build-system-prompt`. Observed `rp_lit` / `rp_file` / `rp_miss` are exact.
First n=5 freeze **3.636×** (16.882 / 4.643 µs) on host `cursor`, ceiling
8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 473 — `skill_prompt_load` (node_read_error)

| metric | cadr | pi |
|---|---|---|
| `node_read_error` | `node-read-error-message` (`src/cadr-cli/system-prompt.lisp`) | Node fs errno text (`packages/coding-agent/src/core/resource-loader.ts`) |

Leftover sibling of Pair 472 on the same hole. Timed work is EISDIR / EACCES
/ generic read-error mapping. Observed `nr_eisdir` / `nr_eacces` /
`nr_other` are exact. First n=5 freeze **3.120×** (10.042 / 3.219 µs) on
host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text; this metric did not
fail). Same commit no optimize.

### Pair 474 — `skill_prompt_load` (prompt_appends)

| metric | cadr | pi |
|---|---|---|
| `prompt_appends` | `resolve-system-prompt-with-appends` (`src/cadr-cli/system-prompt.lisp`) | appendSystemPrompt join (`packages/coding-agent/src/core/resource-loader.ts`) |

Leftover sibling of Pairs 472–473 on the same hole. Timed work is base plus
append list joined with blank lines. Observed `pa_len` / `pa_join` /
`pa_base` are exact. First n=5 freeze **3.268×** (6.306 / 1.930 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes `lc_n` / `lc_sleep` / help text; this metric did not fail).
Same commit no optimize.

### Pair 475 — `cli_print_rpc` (queue_mode)

| metric | cadr | pi |
|---|---|---|
| `queue_mode` | `parse-queue-mode` (`src/cadr-cli/modes/rpc/commands.lisp`) | steering/follow-up mode strings (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |

Leftover of the `cli_print_rpc` hole on `commands.lisp`. Timed work is
`all` / `one-at-a-time` / invalid mode parse — not session set. Observed
`qm_all` / `qm_one` / `qm_bad` are exact. First n=5 freeze **0.116×**
(0.316 / 2.720 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 476 — `cli_print_rpc` (last_assistant)

| metric | cadr | pi |
|---|---|---|
| `last_assistant` | `rpc-last-assistant-text` (`src/cadr-cli/modes/rpc/commands.lisp`) | `getLastAssistantText` (`packages/coding-agent/src/core/agent-session.ts`) |

Leftover sibling of Pair 475 on the same hole. Timed work is last assistant
text extract on a fixture message list — not prompt. Observed `la_hit` /
`la_len` / `la_miss` are exact. First n=5 freeze **0.713×** (0.285 /
0.400 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text;
this metric did not fail). Same commit no optimize.

### Pair 477 — `cli_print_rpc` (command_list)

| metric | cadr | pi |
|---|---|---|
| `command_list` | `rpc-command-list` (`src/cadr-cli/modes/rpc/commands.lisp`) | `get_commands` extension+prompt walk (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |

Leftover sibling of Pairs 475–476 on the same hole. Timed work is slash
command JSON from one extension command plus one prompt template — not
skills, not invoke. Observed `cl_n` / `cl_ext` / `cl_prompt` are exact.
First n=5 freeze **4.151×** (1.490 / 0.359 µs) on host `cursor`, ceiling
8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Same commit
no optimize.

### Pair 478 — `skill_prompt_load` (sdk_prompt_input)

| metric | cadr | pi |
|---|---|---|
| `sdk_prompt_input` | `sdk-resolve-prompt-input` (`src/cadr-cli/sdk/resource-service.lisp`) | `resolvePromptInput` (`packages/coding-agent/src/core/resource-loader.ts`) |

Leftover of the `skill_prompt_load` hole on `resource-service.lisp`. Timed
work is nil / literal / file prompt input resolve — not
`build-system-prompt`, not reload. Observed `si_nil` / `si_lit` /
`si_file` are exact. First n=5 freeze **4.322×** (15.179 / 3.512 µs) on
host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text; this metric did not
fail). Same commit no optimize.

### Pair 479 — `skill_prompt_load` (sdk_list_override)

| metric | cadr | pi |
|---|---|---|
| `sdk_list_override` | `sdk-apply-resource-list-override` (`src/cadr-cli/sdk/resource-service.lisp`) | `skillsOverride` apply (`packages/coding-agent/src/core/resource-loader.ts`) |

Leftover sibling of Pair 478 on the same hole. Timed work is no-op /
replace / keep-diagnostics override apply — not extension reload.
Observed `ov_none` / `ov_replace` / `ov_keep` are exact. First n=5 freeze
**0.365×** (0.188 / 0.516 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 480 — `skill_prompt_load` (sdk_context_files)

| metric | cadr | pi |
|---|---|---|
| `sdk_context_files` | `sdk-context-file-records` (`src/cadr-cli/sdk/resource-service.lisp`) | agentsFiles path+content records (`packages/coding-agent/src/core/resource-loader.ts`) |

Leftover sibling of Pairs 478–479 on the same hole. Timed work is one
staged file mapped to path+content — not directory discovery, not
reload. Observed `cf_n` / `cf_path` / `cf_text` are exact. First n=5
freeze **2.879×** (7.556 / 2.625 µs) on host `cursor`, ceiling 8.0. Gate
used `--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 481 — `cli_support` (watch_retry_delay)

| metric | cadr | pi |
|---|---|---|
| `watch_retry_delay` | `+fs-watch-retry-delay-milliseconds+` (`src/cadr-cli/support/file-watcher.lisp`) | `FS_WATCH_RETRY_DELAY_MS` (`packages/coding-agent/src/utils/fs-watch.ts`) |

Leftover of the `cli_support` hole on `file-watcher.lisp`. Timed work is
the 5000ms retry constant — not poll, not native `fs.watch`. Observed
`rd_eq` / `rd_ms` / `rd_pos` are exact. Collect restore n=5 freeze **1.335×**
(0.157 / 0.118 µs) on host `Friend-MachineD`, gitHead `1cc6098c9`, ceiling 8.0.
Overlay recorded; py full gate rc=2 from leftover `parsed_provider` METRICS
pollution. Over-1× booked. Same commit no optimize.

### Pair 482 — `cli_support` (close_watcher)

| metric | cadr | pi |
|---|---|---|
| `close_watcher` | `close-watcher` (`src/cadr-cli/support/file-watcher.lisp`) | `closeWatcher` (`packages/coding-agent/src/utils/fs-watch.ts`) |

Leftover sibling of Pair 481 on the same hole. Timed work is close on a
null watcher twice — not start-watch, not thread join. Observed `cl_nil`
/ `cl_twice` / `cl_ok` are exact. Collect restore n=5 freeze **1.046×** (0.162 /
0.155 µs) on host `Friend-MachineD`, gitHead `1cc6098c9`, ceiling 8.0. Overlay
recorded; py full gate rc=2 from leftover `parsed_provider` METRICS pollution.
Over-1× booked. Same commit no optimize.

### Pair 483 — `cli_support` (watch_signature)

| metric | cadr | pi |
|---|---|---|
| `watch_signature` | `watched-path-signature` (`src/cadr-cli/support/file-watcher.lisp`) | `statSync` mtime+size presence (`packages/coding-agent/src/core/footer-data-provider.ts`) |

Leftover sibling of Pairs 481–482 on the same hole. Timed work is missing
vs present path signature shape — not `watchWithErrorHandler`, not
poll. Observed `sg_miss` / `sg_hit` / `sg_n` are exact. Collect restore n=5 freeze
**3.482×** (23.825 / 6.843 µs) on host `Friend-MachineD`, gitHead `1cc6098c9`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 484 — `cli_bootstrap_sessions` (model_cycle)

| metric | cadr | pi |
|---|---|---|
| `model_cycle` | `model-cycle-target-entry` (`src/cadr-cli/bootstrap/commands.lisp`) | `_cycleScopedModel` index wrap (`packages/coding-agent/src/core/agent-session.ts`) |

Leftover of the `cli_bootstrap_sessions` hole on `bootstrap/commands.lisp`.
Timed work is scoped-entry wrap / missing-current default — not
session persist, not `cycleModel` emit. Observed `mc_fwd` / `mc_bwd` /
`mc_wrap` / `mc_miss` / `mc_one` / `mc_empty` are exact. First n=5 freeze
**0.622×** (0.632 / 1.017 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 485 — `cli_bootstrap_sessions` (model_scope_line)

| metric | cadr | pi |
|---|---|---|
| `model_scope_line` | `model-scope-startup-line` (`src/cadr-cli/bootstrap/commands.lisp`) | interactive-mode `init` Model scope line (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover sibling of Pair 484 on the same hole. Timed work is the startup
scope line (quiet / empty / cycle-hint / unbound) — not TUI mount, not
theme init. Observed `ms_quiet` / `ms_empty` / `ms_text` / `ms_n` /
`ms_disabled` are exact. First n=5 freeze **1.608×** (37.431 / 23.274 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1
only from known old holes `lc_n` / `lc_sleep` / help text; this metric
did not fail). Same commit no optimize.

### Pair 486 — `cli_bootstrap_sessions` (process_files)

| metric | cadr | pi |
|---|---|---|
| `process_files` | `process-cli-file-arguments` (`src/cadr-cli/bootstrap/commands.lisp`) | `processFileArguments` (`packages/coding-agent/src/cli/file-processor.ts`) |

Leftover sibling of Pairs 484–485 on the same hole. Timed work is one
text file plus one empty skip — not image resize, not `@file` CLI
parse. Observed `pf_hello` / `pf_n` / `pf_img` are exact. First n=5
freeze **0.419×** (61.164 / 146.148 µs) on host `cursor`, ceiling 8.0.
Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text; this metric did not fail). Same commit
no optimize.

### Pair 487 — `cli_extensions_install` (split_command)

| metric | cadr | pi |
|---|---|---|
| `split_command` | `split-extension-command` (`src/cadr-cli/extensions/commands.lisp`) | `_tryExecuteExtensionCommand` spaceIndex split (`packages/coding-agent/src/core/agent-session.ts`) |

Leftover of the `cli_extensions_install` hole on `extensions/commands.lisp`.
Timed work is command/args split — not reload, not host invoke. Observed
`sc_reload` / `sc_reload_args` / `sc_foo` / `sc_foo_args` / `sc_plain` /
`sc_blank` are exact. First n=5 freeze **0.282×** (0.465 / 1.652 µs) on
host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1
only from known old holes `lc_n` / `lc_sleep` / help text; this metric
did not fail). Same commit no optimize.

### Pair 488 — `cli_extensions_install` (handle_plain)

| metric | cadr | pi |
|---|---|---|
| `handle_plain` | `handle-extension-command` (`src/cadr-cli/extensions/commands.lisp`) | `_tryExecuteExtensionCommand` non-slash miss (`packages/coding-agent/src/core/agent-session.ts`) |

Leftover sibling of Pair 487 on the same hole. Timed work is non-slash
lines returning nil — not `/reload`, not `invoke-extension-command`.
Observed `hp_hello` / `hp_ws` / `hp_blank` are exact. First n=5 freeze
**0.449×** (0.344 / 0.766 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 489 — `cli_extensions_install` (handle_unknown)

| metric | cadr | pi |
|---|---|---|
| `handle_unknown` | `handle-extension-command` unknown slash (`src/cadr-cli/extensions/commands.lisp`) | `_tryExecuteExtensionCommand` `getCommand` miss (`packages/coding-agent/src/core/agent-session.ts`) |

Leftover sibling of Pairs 487–488 on the same hole. Timed work is
unknown `/command` lookup returning nil — not handler run, not reload.
Observed `hu_nope` / `hu_miss` / `hu_n` are exact. First n=5 freeze
**0.561×** (0.474 / 0.845 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text; this metric did not fail). Same commit no
optimize.

### Pair 490 — `cli_bootstrap_sessions` (parse_bash)

| metric | cadr | pi |
|---|---|---|
| `parse_bash` | `parse-user-bash-input` (`src/cadr-cli/repl.lisp`) | `!` / `!!` bash extract (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover of the `cli_bootstrap_sessions` hole on `repl.lisp`.
Timed work is bang-prefix parse — not bash execution, not the REPL
loop. Observed `pb_ls` / `pb_excl` / `pb_bang` / `pb_ws` / `pb_plain_ok`
/ `pb_n` are exact. First n=5 freeze **0.421×** (0.528 / 1.252 µs) on
host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1
only from known old holes `lc_n` / `lc_sleep` / help text /
`execution_env.tmp_*`; this metric did not fail). Same commit no
optimize.

### Pair 491 — `cli_bootstrap_sessions` (response_text)

| metric | cadr | pi |
|---|---|---|
| `response_text` | `response-text` (`src/cadr-cli/repl.lisp`) | `sendUserMessage` `textParts.join("\\n")` (`packages/coding-agent/src/core/agent-session.ts`) |

Leftover sibling of Pair 490 on the same hole. Timed work is joining
assistant text blocks with newline, skipping thinking — not a live
prompt. Observed `rt_one` / `rt_two` / `rt_empty` / `rt_n` are exact.
First n=5 freeze **1.314×** (0.939 / 0.714 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known
old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`;
this metric did not fail). Same commit no optimize.

### Pair 492 — `cli_bootstrap_sessions` (dispatch_plain)

| metric | cadr | pi |
|---|---|---|
| `dispatch_plain` | `dispatch-user-input` (`src/cadr-cli/repl.lisp`) | submit classify (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover sibling of Pairs 490–491 on the same hole. Timed work is empty
/ plain / unknown slash / bash-present classification with stub
functions — not `run-repl`, not a live session. Observed `dp_empty` /
`dp_plain` / `dp_slash` / `dp_bash` / `dp_bang` / `dp_n` are exact.
First n=5 freeze **0.446×** (0.543 / 1.216 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known
old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`;
this metric did not fail). Same commit no optimize.

### Pair 493 — `cli_interactive_controller` (make_entry)

| metric | cadr | pi |
|---|---|---|
| `make_entry` | `make-tui-user-bash-entry` (`src/cadr-cli/interactive/user-bash.lisp`) | `BashExecutionComponent` constructor (`packages/coding-agent/src/modes/interactive/components/bash-execution.ts`) |

Leftover of the `cli_interactive_controller` hole on `user-bash.lisp`.
Timed work is entry construction — not bash execution, not TUI render.
Observed `me_type` / `me_label` / `me_run` / `me_ex` / `me_n` are exact.
First n=5 freeze **5.982×** (1.424 / 0.238 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known
old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`;
this metric did not fail). Same commit no optimize.

### Pair 494 — `cli_interactive_controller` (append_output)

| metric | cadr | pi |
|---|---|---|
| `append_output` | `append-tui-user-bash-output` (`src/cadr-cli/interactive/user-bash.lisp`) | `BashExecutionComponent.appendOutput` (`packages/coding-agent/src/modes/interactive/components/bash-execution.ts`) |

Leftover sibling of Pair 493 on the same hole. Timed work is chunk
concatenate — not ANSI strip, not `updateDisplay`. Observed `ao_text` /
`ao_n` / `ao_skip` / `ao_cache` are exact. First n=5 freeze **2.670×**
(0.776 / 0.290 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text / `execution_env.tmp_*`; this metric did not
fail). Same commit no optimize.

### Pair 495 — `cli_interactive_controller` (complete_entry)

| metric | cadr | pi |
|---|---|---|
| `complete_entry` | `complete-tui-user-bash-entry` (`src/cadr-cli/interactive/user-bash.lisp`) | `BashExecutionComponent.setComplete` (`packages/coding-agent/src/modes/interactive/components/bash-execution.ts`) |

Leftover sibling of Pairs 493–494 on the same hole. Timed work is
result fields onto the entry — not loader stop, not render. Observed
`ce_text` / `ce_exit` / `ce_trunc` / `ce_path` / `ce_err` are exact.
First n=5 freeze **2.411×** (0.974 / 0.404 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known
old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`;
this metric did not fail). Same commit no optimize.

### Pair 496 — `cli_print_rpc` (handle_bad_json)

| metric | cadr | pi |
|---|---|---|
| `handle_bad_json` | `rpc-handle-line` (`src/cadr-cli/modes/rpc/mode.lisp`) | `handleInputLine` JSON.parse catch (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |

Leftover of the `cli_print_rpc` hole on `mode.lisp`. Timed work is
invalid JSON (`not-json`) through the outer parse failure — not
`run-rpc-mode`, not a live agent. Observed `bj_cmd` / `bj_ok` / `bj_id`
/ `bj_nl` are exact. Do not exact full error strings. First n=5 freeze
**1.092×** (5.390 / 4.937 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text / `execution_env.tmp_*`; this metric did not
fail). Same commit no optimize.

### Pair 497 — `cli_print_rpc` (handle_not_object)

| metric | cadr | pi |
|---|---|---|
| `handle_not_object` | `rpc-handle-line` (`src/cadr-cli/modes/rpc/mode.lisp`) | `handleInputLine` require JSON object (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |

Leftover sibling of Pair 496 on the same hole. Timed work is JSON array
`[]` rejected as a non-object — not command dispatch. Observed `no_cmd`
/ `no_ok` / `no_id` / `no_nl` are exact. Do not exact full error
strings. First n=5 freeze **1.066×** (5.213 / 4.889 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`;
this metric did not fail). Same commit no optimize.

### Pair 498 — `cli_print_rpc` (handle_ui_miss)

| metric | cadr | pi |
|---|---|---|
| `handle_ui_miss` | `rpc-handle-line` (`src/cadr-cli/modes/rpc/mode.lisp`) | `handleInputLine` unknown `extension_ui_response` (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |

Leftover sibling of Pairs 496–497 on the same hole. Timed work is an
unknown pending UI id (`missing`) — not dialog resolve, not
`rpc-shutdown`. Observed `um_cmd` / `um_ok` / `um_id` / `um_nl` /
`um_unk` are exact. Do not exact full error strings. First n=5 freeze
**4.070×** (6.190 / 1.521 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text / `execution_env.tmp_*`; this metric did not
fail). Same commit no optimize.

### Pair 499 — `cli_extensions_install` (unsafe_git)

| metric | cadr | pi |
|---|---|---|
| `unsafe_git` | `unsafe-git-source-p` (`src/cadr-cli/extensions/installer.lisp`) | `hasUnsafeGitInstallPart` (`packages/coding-agent/src/utils/git.ts`) |

Leftover of the `cli_extensions_install` hole on `installer.lisp`. Timed
work is empty / dash / NUL / backslash / `..` / safe path flags — not
`git clone`, not `install-extension-package`. Observed `ug_empty` /
`ug_dash` / `ug_null` / `ug_bs` / `ug_dot` / `ug_ok` / `ug_n` are exact.
Collect restore n=5 freeze **1.272×** (0.776 / 0.610 µs) on host `cursor`,
gitHead `04b38a745`, ceiling 8.0. Overlay recorded; py full gate rc=2 from
leftover `parsed_provider` METRICS pollution. Over-1× booked. Same commit
no optimize.

### Pair 500 — `cli_extensions_install` (git_path)

| metric | cadr | pi |
|---|---|---|
| `git_path` | `git-source-path` (`src/cadr-cli/extensions/installer.lisp`) | `parseGenericGitUrl` path slice (`packages/coding-agent/src/utils/git.ts`) |

Leftover sibling of Pair 499 on the same hole. Timed work is HTTPS /
`git@` / slash / missing-path extraction — not hosted-git-info, not
clone. Observed `gp_https` / `gp_scp` / `gp_slash` / `gp_miss` / `gp_n`
are exact. Collect restore n=5 freeze **1.855×** (1.075 / 0.579 µs) on host
`cursor`, gitHead `04b38a745`, ceiling 8.0. Overlay recorded; py full gate
rc=2 from leftover `parsed_provider` METRICS pollution. Over-1× booked.
Same commit no optimize.

### Pair 501 — `cli_extensions_install` (normalize_git)

| metric | cadr | pi |
|---|---|---|
| `normalize_git` | `normalize-git-install-source` (`src/cadr-cli/extensions/installer.lisp`) | `parseGitUrl` + extension name (`packages/coding-agent/src/utils/git.ts`) |

Leftover sibling of Pairs 499–500 on the same hole. Timed work is HTTPS
success / `git:` prefix / `file://` / empty / bare-host reject — not
staging, not `reload-cli-extensions`. Observed `ng_https` / `ng_git` /
`ng_file` / `ng_empty` / `ng_bare` are exact. Do not exact full error
strings. Collect restore n=5 freeze **0.378×** (4.969 / 13.148 µs) on host
`cursor`, gitHead `04b38a745`, ceiling 8.0. cadr leads. Overlay recorded;
py full gate rc=2 from leftover `parsed_provider` METRICS pollution. Same
commit no optimize.

### Pair 502 — `cli_extensions_install` (package_fragment)

| metric | cadr | pi |
|---|---|---|
| `package_fragment` | `extension-package-fragment` (`src/cadr-cli/extensions/loader.lisp`) | package-name sanitize (`packages/coding-agent/src/core/extensions/loader.ts`) |

Leftover of the `cli_extensions_install` hole on `loader.lisp`. Timed
work is alphanumeric / hyphen / underscore keep plus other-char hyphen
— not ASDF load, not `reload-cli-extensions`. Observed `pf_plain` /
`pf_hyphen` / `pf_keep` / `pf_empty` / `pf_n` are exact. Collect restore n=5
freeze **0.376×** (0.603 / 1.603 µs) on host `cursor`, gitHead `04b38a745`,
ceiling 8.0. cadr leads. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Same commit no optimize.

### Pair 503 — `cli_extensions_install` (local_system_name)

| metric | cadr | pi |
|---|---|---|
| `local_system_name` | `extension-local-system-name-p` (`src/cadr-cli/extensions/loader.lisp`) | local system name predicate (`packages/coding-agent/src/core/extensions/loader.ts`) |

Leftover sibling of Pair 502 on the same hole. Timed work is name
accept / empty / `.` / `..` / slash reject — not
`read-extension-local-systems`, not network. Observed `ls_ok` /
`ls_empty` / `ls_dot` / `ls_dotdot` / `ls_slash` / `ls_n` are exact.
Collect restore n=5 freeze **0.261×** (0.197 / 0.758 µs) on host `cursor`,
gitHead `04b38a745`, ceiling 8.0. cadr leads. Overlay recorded; py full
gate rc=2 from leftover `parsed_provider` METRICS pollution. Same commit
no optimize.

### Pair 504 — `cli_extensions_install` (inline_factory)

| metric | cadr | pi |
|---|---|---|
| `inline_factory` | `valid-inline-extension-factory-p` (`src/cadr-cli/extensions/loader.lisp`) | `loadExtensionFromFactory` input check (`packages/coding-agent/src/core/extensions/loader.ts`) |

Leftover sibling of Pairs 502–503 on the same hole. Timed work is
function / named plist / empty name / missing factory / odd list — not
factory invoke, not host load. Observed `if_fn` / `if_plist` /
`if_empty_name` / `if_no_factory` / `if_odd` are exact. Collect restore n=5
freeze **0.262×** (0.197 / 0.749 µs) on host `cursor`, gitHead `04b38a745`,
ceiling 8.0. cadr leads. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Same commit no optimize.

### Pair 505 — `cli_extensions_install` (gated_approval)

| metric | cadr | pi |
|---|---|---|
| `gated_approval` | `llama-gated-approval-text` (`src/cadr-cli/extensions/llama/extension.lisp`) | gated-repo approval copy (`packages/coding-agent/src/extensions/llama/index.ts`) |

Leftover of the `cli_extensions_install` hole on `llama/extension.lisp`.
Timed work is `:manual` vs other gated values — not login, not catalog
HTTP. Observed `ga_manual` / `ga_auto` / `ga_str` / `ga_nil` are exact.
Collect restore n=5 freeze **0.580×** (0.130 / 0.223 µs) on host `cursor`,
gitHead `04b38a745`, ceiling 8.0. cadr leads. Overlay recorded; py full
gate rc=2 from leftover `parsed_provider` METRICS pollution. Same commit
no optimize.

### Pair 506 — `cli_extensions_install` (split_args)

| metric | cadr | pi |
|---|---|---|
| `split_args` | `split-llama-command-arguments` (`src/cadr-cli/extensions/llama/extension.lisp`) | llama command argv split (`packages/coding-agent/src/extensions/llama/index.ts`) |

Leftover sibling of Pair 505 on the same hole. Timed work is trim /
first-token downcase / remainder left-trim — not `handle-llama-command`,
not network. Observed `sa_login` / `sa_view` / `sa_bare` / `sa_tab` /
`sa_n` are exact. Collect restore n=5 freeze **0.442×** (0.975 / 2.206 µs)
on host `cursor`, gitHead `04b38a745`, ceiling 8.0. cadr leads. Overlay
recorded; py full gate rc=2 from leftover `parsed_provider` METRICS
pollution. Same commit no optimize.

### Pair 507 — `cli_extensions_install` (quant_label)

| metric | cadr | pi |
|---|---|---|
| `quant_label` | `llama-quantization-option-label` (`src/cadr-cli/extensions/llama/extension.lisp`) | downloadModel option text (`packages/coding-agent/src/extensions/llama/index.ts`) |

Leftover sibling of Pairs 505–506 on the same hole. Timed work is name /
size / Q4_K_M recommended join — not download, not Hugging Face search.
Observed `ql_name` / `ql_rec` / `ql_bytes` / `ql_both` are exact. First
n=5 freeze **1.232×** (1.070 / 0.868 µs) on host `cursor`, gitHead
`04b38a745`, ceiling 8.0. Over-1× booked. Overlay recorded; py full gate
rc=2 from leftover `parsed_provider` METRICS pollution. Same commit no
optimize.

### Pair 508 — `bash_tool` (live_output)

| metric | cadr | pi |
|---|---|---|
| `live_output` | `bash-live-output-for-mode` (`src/cadr-cli/tools/bash.lisp`) | live-output stream pick (`packages/coding-agent/src/core/tools/bash.ts`) |

Leftover of the `agent_tool_loop` hole on `tools/bash.lisp` after the
`bash_tool` strip/append/notice trio. Timed work is `:repl` / `:tui` /
otherwise stream routing — not execute, not spawn. Observed `lo_repl` /
`lo_tui` / `lo_print` / `lo_rpc` are exact. First n=5 freeze **0.479×**
(0.105 / 0.218 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text / `execution_env.tmp_*`; this metric did not
fail). Same commit no optimize.

### Pair 509 — `bash_tool` (strip_status)

| metric | cadr | pi |
|---|---|---|
| `strip_status` | `bash-strip-status-footer` (`src/cadr-cli/tools/bash.lisp`) | status-footer suffix strip (`packages/coding-agent/src/core/tools/bash.ts`) |

Leftover sibling of Pair 508 on the same hole. Timed work is exact /
suffix / whitespace-trim strip — not `append-bash-status`, not execute.
Observed `ss_exact` / `ss_nl` / `ss_plain` / `ss_trim` are exact. First
n=5 freeze **0.773×** (0.417 / 0.540 µs) on host `cursor`, ceiling 8.0.
cadr leads. Gate used `--only-enforce` (script rc=1 only from known old
holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this
metric did not fail). Same commit no optimize.

### Pair 510 — `bash_tool` (strip_truncation)

| metric | cadr | pi |
|---|---|---|
| `strip_truncation` | `bash-strip-truncation-footer` (`src/cadr-cli/tools/bash.lisp`) | `[Showing … Full output:]` suffix strip (`packages/coding-agent/src/core/tools/bash.ts`) |

Leftover sibling of Pairs 508–509 on the same hole. Timed work is
from-end `\n\n[` plus `Full output: ` strip — not truncation-notice
construction, not execute. Observed `st_none` / `st_footer` /
`st_no_full` / `st_plain` are exact. First n=5 freeze **5.885×** (2.331 /
0.396 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text / `execution_env.tmp_*`; this metric did not
fail). Same commit no optimize.

### Pair 511 — `cli_interactive_controller` (sanitize_title)

| metric | cadr | pi |
|---|---|---|
| `sanitize_title` | `sanitize-terminal-title-text` (`src/cadr-cli/interactive/controller.lisp`) | terminal-title control-byte strip (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover of the `cli_interactive_controller` hole on `interactive/controller.lisp`. Timed work is Escape/BEL strip — not OSC title sequence, not `run-tui`. Observed `st_plain` / `st_esc` / `st_bel` / `st_nil` / `st_empty` are exact. First n=5 freeze **0.895×** (0.586 / 0.655 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 512 — `cli_interactive_controller` (title_basename)

| metric | cadr | pi |
|---|---|---|
| `title_basename` | `tui-terminal-title-cwd-basename` (`src/cadr-cli/interactive/controller.lisp`) | cwd basename (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover sibling of Pair 511 on the same hole. Timed work is trailing `/` `\\` trim plus last-separator basename — not title grammar, not `run-tui`. Observed `bn_unix` / `bn_win` / `bn_plain` / `bn_empty` / `bn_nil` are exact. First n=5 freeze **0.393×** (0.353 / 0.898 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 513 — `cli_interactive_controller` (terminal_title)

| metric | cadr | pi |
|---|---|---|
| `terminal_title` | `tui-terminal-title` (`src/cadr-cli/interactive/controller.lisp`) | APP_TITLE session/cwd grammar (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover sibling of Pairs 511–512 on the same hole. Timed work is `cadr - [session -] basename` — not OSC sequence, not `run-tui`. Observed `tt_none` / `tt_session` / `tt_esc` / `tt_empty` are exact. Product slug is cadr (identity), not Pi. First n=5 freeze **0.645×** (1.530 / 2.370 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 514 — `cli_selectors` (armin_pixel)

| metric | cadr | pi |
|---|---|---|
| `armin_pixel` | `armin-pixel-p` (`src/cadr-cli/interactive/components/armin.lisp`) | ArminComponent pixel probe (`packages/coding-agent/src/modes/interactive/components/armin.ts`) |

Leftover of the `cli_selectors` hole on `interactive/components/armin.lisp`. Timed work is XBM bit test — not tick, not render. Observed `ap_blank` / `ap_ink` / `ap_out` are exact. First n=5 freeze **0.548×** (0.126 / 0.230 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 515 — `cli_selectors` (armin_cell)

| metric | cadr | pi |
|---|---|---|
| `armin_cell` | `armin-cell` (`src/cadr-cli/interactive/components/armin.lisp`) | ArminComponent half-block cell (`packages/coding-agent/src/modes/interactive/components/armin.ts`) |

Leftover sibling of Pair 514 on the same hole. Timed work is upper/lower pixel → `█▀▄` / space — not grid copy, not tick. Observed `ac_space` / `ac_lower` / `ac_upper` / `ac_full` are exact. First n=5 freeze **0.444×** (0.307 / 0.691 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 516 — `cli_selectors` (armin_grid_height)

| metric | cadr | pi |
|---|---|---|
| `armin_grid_height` | `armin-grid-height` (`src/cadr-cli/interactive/components/armin.lisp`) | ArminComponent grid rows (`packages/coding-agent/src/modes/interactive/components/armin.ts`) |

Leftover sibling of Pairs 514–515 on the same hole. Timed work is `ceiling(height/2)` — not make-grid, not tick. Observed `ag_h` is exact. First n=5 freeze **0.870×** (0.081 / 0.093 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 517 — `cli_interactive_controller` (wrap_transcript)

| metric | cadr | pi |
|---|---|---|
| `wrap_transcript` | `wrap-transcript-lines` (`src/cadr-cli/interactive/transcript.lisp`) | `UserMessageComponent.render` OSC 133 wrap (`packages/coding-agent/src/modes/interactive/components/user-message.ts`) |

Leftover of the `cli_interactive_controller` hole on `interactive/transcript.lisp`. Timed work is OSC 133 A/B/C wrap of a line list (nil, one-element shared-cons order, two-element first/last) — not user-message markdown, not assistant render. Observed `wt_nil` / `wt_one_n` / `wt_one_order` / `wt_two_n` / `wt_two_first` / `wt_two_last` are exact. First n=5 freeze **1.003×** (0.601 / 0.599 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 518 — `cli_interactive_controller` (output_padding)

| metric | cadr | pi |
|---|---|---|
| `output_padding` | `output-padding-string` (`src/cadr-cli/interactive/transcript.lisp`) | `UserMessageComponent` outputPad (`packages/coding-agent/src/modes/interactive/components/user-message.ts`) |

Leftover sibling of Pair 517 on the same hole. Timed work is pad 0/1 vs other → length-1 space string — not wrap-text, not OSC wrap. Observed `op_0` / `op_1` / `op_other` / `op_space` are exact. First n=5 freeze **0.987×** (0.226 / 0.229 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 519 — `cli_interactive_controller` (render_cacheable)

| metric | cadr | pi |
|---|---|---|
| `render_cacheable` | `tui-entry-render-cacheable-p` (`src/cadr-cli/interactive/transcript.lisp`) | TUI entry render cache gate (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover sibling of Pairs 517–518 on the same hole. Timed work is streaming/tool-block/custom-call cache predicate — not `render-tui-entry`, not theme snapshot. Observed `rc_assist` / `rc_stream` / `rc_tool_nil` / `rc_tool_done` / `rc_tool_run` / `rc_custom` are exact. First n=5 freeze **2.515×** (1.461 / 0.581 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 520 — `cli_interactive_controller` (tool_session_make)

| metric | cadr | pi |
|---|---|---|
| `tool_session_make` | `make-tool-render-session` (`src/cadr-cli/interactive/tool-render-session.lisp`) | `ToolExecutionComponent` construct (`packages/coding-agent/src/modes/interactive/components/tool-execution.ts`) |

Leftover of the `cli_interactive_controller` hole on `interactive/tool-render-session.lisp`. Timed work is session construct (name, default pending, nil result) — not render, not update. Observed `tsm_name` / `tsm_pending` / `tsm_nil` are exact. First n=5 freeze **1.224×** (0.257 / 0.210 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 521 — `cli_interactive_controller` (tool_session_update)

| metric | cadr | pi |
|---|---|---|
| `tool_session_update` | `update-tool-render-session` (`src/cadr-cli/interactive/tool-render-session.lisp`) | result/pending (`packages/coding-agent/src/modes/interactive/components/tool-execution.ts`) |

Leftover sibling of Pair 520 on the same hole. Timed work is result write plus pending keep/clear — not renderCall, not construct. Observed `tsu_result` / `tsu_pending` / `tsu_cleared` are exact. First n=5 freeze **1.151×** (0.266 / 0.231 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 522 — `cli_interactive_controller` (tool_session_render)

| metric | cadr | pi |
|---|---|---|
| `tool_session_render` | `render-tool-session` (`src/cadr-cli/interactive/tool-render-session.lisp`) | renderCall/renderResult fallback (`packages/coding-agent/src/modes/interactive/components/tool-execution.ts`) |

Leftover sibling of Pairs 520–521 on the same hole. Timed work is pending default call, done default result, custom renderers, empty-line drop — not TUI Box, not images. Observed `trr_pending_n` / `trr_pending_call` / `trr_done_n` / `trr_done_result` / `trr_custom` / `trr_empty` are exact. First n=5 freeze **0.969×** (1.733 / 1.789 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 523 — `cli_interactive_controller` (theme_primitive)

| metric | cadr | pi |
|---|---|---|
| `theme_primitive` | `valid-tui-theme-primitive-p` (`src/cadr-cli/interactive/themes.lisp`) | `ColorValueSchema` (`packages/coding-agent/src/modes/interactive/theme/theme.ts`) |

Leftover of the `cli_interactive_controller` hole on `interactive/themes.lisp`. Timed work is string / 0..255 integer predicate — not file load, not watcher. Observed `tp_str` / `tp_int` / `tp_255` / `tp_256` / `tp_neg` / `tp_nil` are exact. First n=5 freeze **0.472×** (0.110 / 0.233 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 524 — `cli_interactive_controller` (theme_resolve)

| metric | cadr | pi |
|---|---|---|
| `theme_resolve` | `resolve-tui-theme-value` (`src/cadr-cli/interactive/themes.lisp`) | theme color resolve (`packages/coding-agent/src/modes/interactive/theme/theme.ts`) |

Leftover sibling of Pair 523 on the same hole. Timed work is integer/empty/hex/var/cycle/miss resolve — not `theme-object-overrides`, not `set-current-theme`. Observed `tr_int` / `tr_empty` / `tr_hex` / `tr_var` / `tr_cycle` / `tr_miss` are exact. First n=5 freeze **0.184×** (1.442 / 7.853 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 525 — `cli_interactive_controller` (theme_validate)

| metric | cadr | pi |
|---|---|---|
| `theme_validate` | `validate-tui-theme-object` (`src/cadr-cli/interactive/themes.lisp`) | `ThemeJsonSchema` (`packages/coding-agent/src/modes/interactive/theme/theme.ts`) |

Leftover sibling of Pairs 523–524 on the same hole. Timed work is ok / slash-name / unknown-property validate — not JSON parse, not watcher poll. Observed `tv_ok` / `tv_slash` / `tv_unknown` are exact. First n=5 freeze **0.795×** (20.435 / 25.698 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 526 — `cli_selectors` (user_message_make)

| metric | cadr | pi |
|---|---|---|
| `user_message_make` | `make-user-message-selector-state` (`src/cadr-cli/interactive/selectors/fork.lisp`) | `UserMessageList` constructor (`packages/coding-agent/src/modes/interactive/components/user-message-selector.ts`) |

Leftover trio on `src/cadr-cli/interactive/selectors/fork.lisp` / hole `cli_selectors`. Timed work is empty/one/two/initial-hit/initial-miss/copy-list construction — not `render-user-message-selector`, not handle-event. Fixtures pass `:keybindings :bench` so default `make-keybindings-manager` is not in the timed path. Observed `umm_empty` / `umm_one` / `umm_two` / `umm_hit` / `umm_miss` / `umm_copy` are exact. First n=5 freeze **0.530×** (0.760 / 1.434 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 527 — `cli_selectors` (user_message_move)

| metric | cadr | pi |
|---|---|---|
| `user_message_move` | `user-message-selector-move` (`src/cadr-cli/interactive/selectors/fork.lisp`) | `selectedIndex` wrap (`packages/coding-agent/src/modes/interactive/components/user-message-selector.ts`) |

Leftover sibling of Pair 526 on the same hole. Timed work is wrap-forward / back / full-step / three-item wrap via `selector-frame-move-index` — not handle-raw-input. Observed `umv_empty` / `umv_wrap_fwd` / `umv_back` / `umv_full` / `umv_three_back` / `umv_three_fwd` are exact. First n=5 freeze **0.526×** (0.826 / 1.572 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 528 — `cli_selectors` (user_message_selection)

| metric | cadr | pi |
|---|---|---|
| `user_message_selection` | `user-message-selector-selection` (`src/cadr-cli/interactive/selectors/fork.lisp`) | selected item value (`packages/coding-agent/src/modes/interactive/components/user-message-selector.ts`) |

Leftover sibling of Pairs 526–527 on the same hole. Timed work is empty/last/initial-hit/wrap/miss/one-item value lookup — not render. Observed `ums_empty` / `ums_last` / `ums_hit` / `ums_wrap` / `ums_miss` / `ums_one` are exact. First n=5 freeze **0.553×** (0.862 / 1.559 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 529 — `cli_selectors` (login_dialog_make)

| metric | cadr | pi |
|---|---|---|
| `login_dialog_make` | `make-login-dialog-state` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | `LoginDialogComponent` constructor (`packages/coding-agent/src/modes/interactive/components/login-dialog.ts`) |

Leftover trio on `src/cadr-cli/interactive/selectors/login-dialog.lisp` / hole `cli_selectors`. Timed work is empty/named/long provider construction — not render, not handle-event. Observed `ldm_empty_n` / `ldm_named` / `ldm_named_sec` / `ldm_long` / `ldm_input` / `ldm_long_n` are exact. First n=5 freeze **0.543×** (0.169 / 0.312 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 530 — `cli_selectors` (login_dialog_auth)

| metric | cadr | pi |
|---|---|---|
| `login_dialog_auth` | `login-dialog-show-auth` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | `showAuth` (`packages/coding-agent/src/modes/interactive/components/login-dialog.ts`) |

Leftover sibling of Pair 529 on the same hole. Timed work is plain/instructions/empty-instructions/replace auth sections — not OAuth HTTP, not render. Observed `lda_plain` / `lda_instr` / `lda_empty_instr` / `lda_replace` / `lda_provider` / `lda_n` are exact. First n=5 freeze **1.039×** (1.925 / 1.853 µs) on host `cursor`, ceiling 8.0. Booked in `docs/benchmarks/goal20-paired-over-1x.md`. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 531 — `cli_selectors` (login_dialog_device)

| metric | cadr | pi |
|---|---|---|
| `login_dialog_device` | `login-dialog-show-device-code` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | `showDeviceCode` (`packages/coding-agent/src/modes/interactive/components/login-dialog.ts`) |

Leftover sibling of Pairs 529–530 on the same hole. Timed work is device-code / empty-code / replace sections — not poll, not render. Observed `ldd_code` / `ldd_empty` / `ldd_replace` / `ldd_provider` / `ldd_n` / `ldd_hint` are exact. First n=5 freeze **2.148×** (3.653 / 1.701 µs) on host `cursor`, ceiling 8.0. Booked in `docs/benchmarks/goal20-paired-over-1x.md`. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 532 — `cli_selectors` (thinking_level_label)

| metric | cadr | pi |
|---|---|---|
| `thinking_level_label` | `thinking-level-label` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | thinking level label (`packages/coding-agent/src/modes/interactive/components/thinking-selector.ts`) |

Leftover trio on `src/cadr-cli/interactive/selectors/thinking.lisp` / hole `cli_selectors`. Timed work is off/minimal/xhigh/max/low/bogus downcase labels — not render, not keybindings. Observed `tll_off` / `tll_minimal` / `tll_xhigh` / `tll_max` / `tll_low` / `tll_bogus` are exact. First n=5 freeze **0.887×** (0.223 / 0.251 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 533 — `cli_selectors` (thinking_level_search_text)

| metric | cadr | pi |
|---|---|---|
| `thinking_level_search_text` | `thinking-level-search-text` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | thinking level search text (`packages/coding-agent/src/modes/interactive/components/thinking-selector.ts`) |

Leftover sibling of Pair 532 on the same hole. Timed work is label plus `settings-thinking-description` (including unknown → trailing space) — not fuzzy filter, not render. Observed `tlst_off` / `tlst_minimal` / `tlst_high` / `tlst_xhigh` / `tlst_max` / `tlst_bogus` are exact. First n=5 freeze **2.096×** (1.090 / 0.520 µs) on host `cursor`, ceiling 8.0. Booked in `docs/benchmarks/goal20-paired-over-1x.md`. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 534 — `cli_selectors` (thinking_selector_set_query)

| metric | cadr | pi |
|---|---|---|
| `thinking_selector_set_query` | `thinking-selector-set-query` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | filter query update (`packages/coding-agent/src/modes/interactive/components/thinking-selector.ts`) |

Leftover sibling of Pairs 532–533 on the same hole. Timed work is empty/off/high/miss/nil/clear-after-off query apply — not handle-event, not render. Fixtures pass `:keybindings :bench`. Observed `tsq_empty` / `tsq_off` / `tsq_high` / `tsq_miss` / `tsq_nil` / `tsq_clear` are exact. First n=5 freeze **1.081×** (11.827 / 10.942 µs) on host `cursor`, ceiling 8.0. Booked in `docs/benchmarks/goal20-paired-over-1x.md`. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 535 — `cli_interactive_controller` (clipboard_candidates)

| metric | cadr | pi |
|---|---|---|
| `clipboard_candidates` | `clipboard-command-candidates` (`src/cadr-cli/interactive/clipboard.lisp`) | copy argv lists (`packages/coding-agent/src/utils/clipboard.ts`) |

Leftover trio on `src/cadr-cli/interactive/clipboard.lisp` / hole `cli_interactive_controller`. Timed work is darwin/windows/linux-empty/termux+wayland+x11/wayland/x11 argv lists — not OSC 52, not subprocess. Observed `ccand_darwin` / `ccand_win` / `ccand_none` / `ccand_termux` / `ccand_wl` / `ccand_x11` are exact. First n=5 freeze **1.405×** (2.349 / 1.672 µs) on host `cursor`, ceiling 8.0. Booked in `docs/benchmarks/goal20-paired-over-1x.md`. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 536 — `cli_interactive_controller` (osc52_copy)

| metric | cadr | pi |
|---|---|---|
| `osc52_copy` | `osc52-copy-sequence` (`src/cadr-cli/interactive/clipboard.lisp`) | OSC 52 encode (`packages/coding-agent/src/utils/clipboard.ts`) |

Leftover sibling of Pair 535 on the same hole. Timed work is hello/empty/CJK/oversize/emoji/bound-length encode — not stdout write, not native clipboard. Observed `osc_hello` / `osc_empty` / `osc_cjk` / `osc_over` / `osc_emoji` / `osc_bound` are exact. First n=5 freeze **1.043×** (1.614 / 1.547 µs) on host `cursor`, ceiling 8.0. Booked in `docs/benchmarks/goal20-paired-over-1x.md`. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 537 — `cli_interactive_controller` (clipboard_copy)

| metric | cadr | pi |
|---|---|---|
| `clipboard_copy` | `copy-to-clipboard` (`src/cadr-cli/interactive/clipboard.lisp`) | copyToClipboard injected (`packages/coding-agent/src/utils/clipboard.ts`) |

Leftover sibling of Pairs 535–536 on the same hole. Timed work is darwin-native/linux-shell/remote+osc52/osc-only/windows-native/termux-shell with injected runners — not `execSync`, not image paste. Observed `cc_darwin` / `cc_linux_shell` / `cc_remote` / `cc_osc` / `cc_win` / `cc_termux` are exact. First n=5 freeze **1.137×** (1.911 / 1.680 µs) on host `cursor`, ceiling 8.0. Booked in `docs/benchmarks/goal20-paired-over-1x.md`. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 538 — `cli_interactive_controller` (colorfgbg_index)

| metric | cadr | pi |
|---|---|---|
| `colorfgbg_index` | `colorfgbg-background-index` (`src/cadr-cli/interactive/theme.lisp`) | COLORFGBG parse (`packages/coding-agent/src/modes/interactive/theme/theme.ts`) |

Leftover trio on `src/cadr-cli/interactive/theme.lisp` / hole `cli_interactive_controller`. Timed work is last-valid 0–255 segment parse — not OSC 11, not getenv. Observed `cfg_plain` / `cfg_last` / `cfg_skip` / `cfg_miss` / `cfg_pad` / `cfg_empty` are exact. First n=5 freeze **1.605×** (1.430 / 0.891 µs) on host `cursor`, ceiling 8.0. Booked in `docs/benchmarks/goal20-paired-over-1x.md`. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 539 — `cli_interactive_controller` (rgb_background)

| metric | cadr | pi |
|---|---|---|
| `rgb_background` | `rgb-background-theme` (`src/cadr-cli/interactive/theme.lisp`) | `getThemeForRgbColor` (`packages/coding-agent/src/modes/interactive/theme/theme.ts`) |

Leftover sibling of Pair 538 on the same hole. Timed work is WCAG luminance ≥0.5 light/dark on six RGB fixtures — not type-error, not hex. Observed `rgb_black` / `rgb_white` / `rgb_mid` / `rgb_187` / `rgb_188` / `rgb_red` are exact. First n=5 freeze **0.659×** (2.180 / 3.309 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 540 — `cli_interactive_controller` (detect_background)

| metric | cadr | pi |
|---|---|---|
| `detect_background` | `detect-background-from-environment` (`src/cadr-cli/interactive/theme.lisp`) | `detectTerminalBackgroundFromEnv` (`packages/coding-agent/src/modes/interactive/theme/theme.ts`) |

Leftover sibling of Pairs 538–539 on the same hole. Timed work is COLORFGBG white/black/missing/empty/invalid/pair detection — not live getenv (dummy alist), not OSC 11. Observed `dbg_white` / `dbg_black` / `dbg_none` / `dbg_empty` / `dbg_bad` / `dbg_pair` are exact. First n=5 freeze **0.863×** (3.025 / 3.504 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Same commit no optimize.

### Pair 541 — `cli_interactive_controller` (fit_footer_text)

| metric | cadr | pi |
|---|---|---|
| `fit_footer_text` | `fit-footer-text` (`src/cadr-cli/interactive/footer.lisp`) | `truncateToWidth` (`packages/tui/src/utils.ts`) |

Leftover sibling of Pair `cwd_footer` on the same `footer.lisp` file /
`cli_interactive_controller` hole. Timed work is default-ellipsis truncate
— not `format-cwd-for-footer`, not selector `fit_line`. Observed `fft_short`
/ `fft_long` / `fft_cjk` / `fft_empty` / `fft_zero` / `fft_emoji` are exact.
First n=5 freeze **1.038×** (21.385 / 20.600 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old
holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric
did not fail). Over-1× booked. Same commit no optimize.

### Pair 542 — `cli_interactive_controller` (footer_usage)

| metric | cadr | pi |
|---|---|---|
| `footer_usage` | `footer-usage-summary` (`src/cadr-cli/interactive/footer.lisp`) | `addUsageToTotals` (`packages/coding-agent/src/core/usage-totals.ts`) then cadr footer format |

Leftover sibling of Pairs 541 / `cwd_footer` on the same file. Timed work
is usage-total sum plus cadr's `in:/out:/CH/$/(sub)` format — not
`formatTokens`, not live FooterComponent render. Observed `fu_kimi` /
`fu_plain` / `fu_zero` / `fu_nocache` / `fu_case` / `fu_cost0` are exact.
First n=5 freeze **2.049×** (7.216 / 3.522 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old
holes; this metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 543 — `cli_interactive_controller` (footer_git_paths)

| metric | cadr | pi |
|---|---|---|
| `footer_git_paths` | `find-git-footer-paths` (`src/cadr-cli/interactive/footer.lisp`) | `findGitPaths` (`packages/coding-agent/src/core/footer-data-provider.ts`) |

Leftover sibling of Pairs 541–542 on the same file. Timed work is git
metadata path walk (regular repo, nested cwd, worktree file, commondir) —
not `resolve-git-footer-branch`, not watcher/CLOS provider. Observed
`fgp_repo` / `fgp_nested` / `fgp_worktree` / `fgp_common` / `fgp_nohead` /
`fgp_none` are exact (relative `repo|commonGit|HEAD`; `.git` directory
without HEAD is empty on both sides). First n=5 freeze **1.649×**
(214.734 / 130.225 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes; this metric did
not fail). Over-1× booked. Same commit no optimize.

### Pair 544 — `cli_extensions_install` (llama_context_label)

| metric | cadr | pi |
|---|---|---|
| `llama_context_label` | `llama-context-label` (`src/cadr-cli/extensions/llama/ui.lisp`) | `contextLabel` (`packages/coding-agent/src/extensions/llama/ui.ts`) |

Leftover sibling of the `cli_extensions_install` hole on `llama/ui.lisp`.
Timed work is n_ctx / n_ctx_train / `--ctx-size`/`-c` format — not
Hugging Face search, not the framed selector. Observed `cl_meta` /
`cl_train` / `cl_args` / `cl_small` / `cl_none` / `cl_dashc` are exact.
Collect restore n=5 freeze **1.257×** (1.425 / 1.134 µs) on host `cursor`,
gitHead `cf07413d6`, ceiling 8.0. Overlay recorded; py full gate rc=2 from
leftover `parsed_provider` METRICS pollution (this metric did not fail
observed). Over-1× booked. Same commit no optimize.

### Pair 545 — `cli_extensions_install` (llama_model_description)

| metric | cadr | pi |
|---|---|---|
| `llama_model_description` | `llama-model-description` (`src/cadr-cli/extensions/llama/ui.lisp`) | `modelDescription` (`packages/coding-agent/src/extensions/llama/ui.ts`) |

Leftover sibling of Pair 544 on the same file. Timed work is loaded /
sleeping / status / context join — not TUI render. Observed `md_loaded` /
`md_sleep` / `md_unload` / `md_load` / `md_down` / `md_nocontext` are exact.
Collect restore n=5 freeze **1.156×** (1.569 / 1.357 µs) on host `cursor`,
gitHead `cf07413d6`, ceiling 8.0. Overlay recorded; py full gate rc=2 from
leftover `parsed_provider` METRICS pollution. Over-1× booked. Same commit
no optimize.

### Pair 546 — `cli_extensions_install` (llama_compact_count)

| metric | cadr | pi |
|---|---|---|
| `llama_compact_count` | `llama-compact-count` (`src/cadr-cli/extensions/llama/ui.lisp`) | `compactCount` (`packages/coding-agent/src/extensions/llama/ui.ts`) |

Leftover sibling of Pairs 544–545 on the same file. Timed work is 1.2k /
3M `toFixed` cutoffs — not download UI. Observed `cc_small` / `cc_k` /
`cc_k0` / `cc_m` / `cc_m0` / `cc_999` are exact. Collect restore n=5 freeze
**1.593×** (1.017 / 0.638 µs) on host `cursor`, gitHead `cf07413d6`,
ceiling 8.0. Overlay recorded; py full gate rc=2 from leftover
`parsed_provider` METRICS pollution. Over-1× booked. Same commit no
optimize.

### Pair 547 — `cli_selectors` (daxnuts_parse_image)

| metric | cadr | pi |
|---|---|---|
| `daxnuts_parse_image` | `parse-daxnuts-rgb-grid` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | `parseImage` (`packages/coding-agent/src/modes/interactive/components/daxnuts.ts`) |

Leftover trio on the `cli_selectors` hole for `daxnuts.lisp` (inventory
`needs-pair`). Timed work is hex-blob RGB grid parse — not component tick,
not TUI render. Observed `dpi_00` / `dpi_0x` / `dpi_mid` / `dpi_last` /
`dpi_h` / `dpi_w` are exact (RGB samples, not the blob). First n=5 freeze
**0.557×** (50.293 / 90.217 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text / `execution_env.tmp_*`; this metric did not fail). Same commit
no optimize. `nextPairNum` left at 328.

### Pair 548 — `cli_selectors` (daxnuts_image_line)

| metric | cadr | pi |
|---|---|---|
| `daxnuts_image_line` | `daxnuts-image-line` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | `buildImage` half-block row (`packages/coding-agent/src/modes/interactive/components/daxnuts.ts`) |

Leftover sibling of Pair 547. Timed work is half-block ANSI scanline from
the cached RGB grid — not animation, not `center`. Observed `dil_0` /
`dil_7` / `dil_15` / `dil_0_len` / `dil_15_len` / `dil_reset` are exact.
First n=5 freeze **2.220×** (36.319 / 16.357 µs) on host `cursor`, ceiling
8.0. Gate used `--only-enforce` (script rc=1 only from known old holes;
this metric did not fail). Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
Same commit no optimize. `nextPairNum` left at 328.

### Pair 549 — `cli_selectors` (daxnuts_center_line)

| metric | cadr | pi |
|---|---|---|
| `daxnuts_center_line` | `center-component-line` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | `render()` `center` (`packages/coding-agent/src/modes/interactive/components/daxnuts.ts`) |

Leftover sibling of Pairs 547–548. Timed work is left-pad to visible width
— ASCII and CSI only (`visible-width` vs regex `.length` diverge on CJK).
Observed `dcl_plain` / `dcl_odd` / `dcl_narrow` / `dcl_empty` / `dcl_ansi` /
`dcl_wide` are exact. First n=5 freeze **0.970×** (0.896 / 0.924 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from
known old holes; this metric did not fail). Same commit no optimize.
`nextPairNum` left at 328.

### Pair 550 — `cli_interactive_controller` (framed_select_title)

| metric | cadr | pi |
|---|---|---|
| `framed_select_title` | `framed-select-title` (`src/cadr-cli/interactive/extension-ui.lisp`) | ExtensionSelector countdown title (`packages/coding-agent/src/modes/interactive/components/extension-selector.ts` `${baseTitle} (${s}s)`) |

Leftover trio on the `cli_interactive_controller` hole for
`extension-ui.lisp` (inventory `needs-pair`). Timed work is title +
`Math.ceil` remaining seconds — not select-list render, not TUI overlay.
Message is cadr-only and omitted. Observed `fst_plain` / `fst_ceil` /
`fst_exact` / `fst_zero` / `fst_neg` / `fst_empty` are exact. First n=5
freeze **1.406×** (0.775 / 0.551 µs) on host `cursor`, ceiling 8.0. Gate
used `--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail).
Booked in `docs/benchmarks/goal20-paired-over-1x.md`. Same commit no
optimize. `nextPairNum` left at 328.

### Pair 551 — `cli_interactive_controller` (extension_overlay_options)

| metric | cadr | pi |
|---|---|---|
| `extension_overlay_options` | `extension-overlay-options` (`src/cadr-cli/interactive/extension-ui.lisp`) | `showExtensionCustom` resolveOptions (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover sibling of Pair 550. Timed work is static overlay options vs
function vs missing — not `showOverlay`, not layout. Observed `eoo_nil` /
`eoo_static` / `eoo_fn` / `eoo_pct` / `eoo_zero` / `eoo_width` are exact.
First n=5 freeze **2.114×** (1.270 / 0.601 µs) on host `cursor`, ceiling
8.0. Gate used `--only-enforce` (script rc=1 only from known old holes;
this metric did not fail). Booked over-1×. Same commit no optimize.
`nextPairNum` left at 328.

### Pair 552 — `cli_interactive_controller` (extension_custom_ui_visible)

| metric | cadr | pi |
|---|---|---|
| `extension_custom_ui_visible` | `extension-custom-ui-visible-p` (`src/cadr-cli/interactive/extension-ui.lisp`) | OverlayHandle `isHidden` plus explicit `visible`/`visible-p` flags (`packages/tui/src/tui.ts`) |

Leftover sibling of Pairs 550–551. Handle is nil (no overlay stack). Does
not call `OverlayOptions.visible(termWidth, termHeight)` (cadr does not).
Observed `ecu_default` / `ecu_width` / `ecu_vis_nil` / `ecu_visp_nil` /
`ecu_vis_t` / `ecu_fn_nil` are exact. First n=5 freeze **1.866×** (1.027 /
0.551 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`
(script rc=1 only from known old holes; this metric did not fail). Booked
over-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 553 — `cli_bootstrap_sessions` (session_argument_path)

| metric | cadr | pi |
|---|---|---|
| `session_argument_path` | `session-argument-path-p` (`src/cadr-cli/bootstrap/sessions.lisp`) | `resolveSessionPath` path test (`packages/coding-agent/src/main.ts` `includes("/") \|\| includes("\\") \|\| endsWith(".jsonl")`) |

Leftover trio on the `cli_bootstrap_sessions` hole for
`bootstrap/sessions.lisp` (inventory `needs-pair`). Timed work is the
path-vs-id predicate — not session load, not `--session` flag
conflicts. Observed `sap_slash` / `sap_backslash` / `sap_jsonl` /
`sap_id` / `sap_empty` / `sap_json` are exact. First n=5 freeze
**0.852×** (0.371 / 0.436 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text / `execution_env.tmp_*`; this metric did not
fail). Same commit no optimize. `nextPairNum` left at 328.

### Pair 554 — `cli_bootstrap_sessions` (split_command)

| metric | cadr | pi |
|---|---|---|
| `split_command` | `split-command` (`src/cadr-cli/bootstrap/sessions.lisp`) | interactive-mode slash-command first-space split (`packages/coding-agent/src/modes/interactive/interactive-mode.ts` after `text.trim()`) |

Leftover sibling of Pair 553. Timed work is command/argument split —
not `/name` mutation, not session switch. Observed `sc_name` /
`sc_name_arg` / `sc_pad` / `sc_import` / `sc_empty` / `sc_tab` are
exact. First n=5 freeze **0.568×** (1.339 / 2.356 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known
old holes; this metric did not fail). Same commit no optimize.
`nextPairNum` left at 328.

### Pair 555 — `cli_bootstrap_sessions` (path_command_argument)

| metric | cadr | pi |
|---|---|---|
| `path_command_argument` | `path-command-argument` (`src/cadr-cli/bootstrap/sessions.lisp`) | `getPathCommandArgument` (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover sibling of Pairs 553–554. Timed work is quoted/unquoted path
after `/import` — not JSONL import, not `/export` write. Observed
`pca_none` / `pca_plain` / `pca_dq` / `pca_sq` / `pca_unclosed` /
`pca_extra` are exact. First n=5 freeze **0.802×** (0.713 / 0.889 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1
only from known old holes; this metric did not fail). Same commit no
optimize. `nextPairNum` left at 328.

### Pair 556 — `cli_selectors` (countdown_seconds)

| metric | cadr | pi |
|---|---|---|
| `countdown_seconds` | `make-countdown-timer` remaining seconds (`src/cadr-cli/interactive/components/countdown.lisp`, `:start-p nil`) | `Math.ceil(timeoutMs / 1000)` (`packages/coding-agent/src/modes/interactive/components/countdown-timer.ts`) |

Leftover trio on the `cli_selectors` hole for `countdown.lisp`
(inventory `needs-pair`). Timed work is ceiling seconds from timeout —
not `setInterval`, not SBCL threads. Observed `cds_0` / `cds_1` /
`cds_1000` / `cds_1001` / `cds_1500` / `cds_999` are exact. First n=5
freeze **2.292×** (0.768 / 0.335 µs) on host `cursor`, ceiling 8.0.
Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric
did not fail). Booked in `docs/benchmarks/goal20-paired-over-1x.md`.
Same commit no optimize. `nextPairNum` left at 328.

### Pair 557 — `cli_selectors` (countdown_tick)

| metric | cadr | pi |
|---|---|---|
| `countdown_tick` | `countdown-timer-tick` (`src/cadr-cli/interactive/components/countdown.lisp`) | CountdownTimer interval body (`packages/coding-agent/src/modes/interactive/components/countdown-timer.ts`) |

Leftover sibling of Pair 556. Timed work is one remaining-second step
plus expire at 0 — not `sleep`, not `countdown-timer-run`. Observed
`cdt_make` / `cdt_remain` / `cdt_expired` / `cdt_ticks` / `cdt_expires` /
`cdt_renders` are exact. First n=5 freeze **3.006×** (0.700 / 0.233 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1
only from known old holes; this metric did not fail). Booked over-1×.
Same commit no optimize. `nextPairNum` left at 328.

### Pair 558 — `cli_selectors` (countdown_render)

| metric | cadr | pi |
|---|---|---|
| `countdown_render` | `countdown-request-render` (`src/cadr-cli/interactive/components/countdown.lisp`) | `tui?.requestRender()` (`packages/coding-agent/src/modes/interactive/components/countdown-timer.ts`) |

Leftover sibling of Pairs 556–557. Function UI vs missing UI — not
`tui-root` request-render. Observed `cdr_fn1` / `cdr_fn2` / `cdr_nil` /
`cdr_sym` / `cdr_zero` / `cdr_fn3` are exact. First n=5 freeze **1.928×**
(0.892 / 0.463 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes; this metric
did not fail). Booked over-1×. Same commit no optimize. `nextPairNum`
left at 328.

### Pair 559 — `cli_selectors` (model_selector_provider_badge)

| metric | cadr | pi |
|---|---|---|
| `model_selector_provider_badge` | `model-selector-provider-badge` (`src/cadr-cli/interactive/selectors/models.lisp`) | `` [`${item.provider}`] `` (`packages/coding-agent/src/modes/interactive/components/model-selector.ts`) |

Leftover trio on unused helpers in `models.lisp` (inventory `needs-pair`).
Timed work is the `[provider]` badge string — not selector render, not
keybindings. Observed `mspb_openai` / `mspb_anthropic` / `mspb_codex` /
`mspb_google` / `mspb_openrouter` / `mspb_hit` are exact. First n=5
freeze **0.307×** (0.126 / 0.411 µs) on host `cursor`, ceiling 8.0.
Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric
did not fail). Same commit no optimize. `nextPairNum` left at 328.

### Pair 560 — `cli_selectors` (scoped_models_copy_enabled)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_copy_enabled` | `scoped-models-copy-enabled` (`src/cadr-cli/interactive/selectors/models.lisp`) | `enabledModelIds === null ? null : [...enabledModelIds]` (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pair 559. Timed work is `:all`/list copy — not
persist, not reorder. Observed `smce_all` / `smce_two` / `smce_empty` /
`smce_one` / `smce_three` / `smce_unavail` are exact. First n=5 freeze
**1.960×** (1.074 / 0.548 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes; this metric
did not fail). Booked over-1×. Same commit no optimize. `nextPairNum`
left at 328.

### Pair 561 — `cli_selectors` (move_list_item)

| metric | cadr | pi |
|---|---|---|
| `move_list_item` | `move-list-item` (`src/cadr-cli/interactive/selectors/models.lisp`) | `move()` index swap (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pairs 559–560. Timed work is copy-and-swap by
index — not `scoped-models-selector-reorder`. Observed `mli_swap` /
`mli_ends` / `mli_neg` / `mli_over` / `mli_same` / `mli_empty` are exact.
First n=5 freeze **1.357×** (1.317 / 0.971 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known
old holes; this metric did not fail). Booked over-1×. Same commit no
optimize. `nextPairNum` left at 328.

### Pair 562 — `cli_selectors` (session_scoped_models)

| metric | cadr | pi |
|---|---|---|
| `session_scoped_models` | `session-scoped-models` (`src/cadr-cli/interactive/selectors/models.lisp`) | session-scoped model filter (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover trio on unused helpers in `models.lisp` (inventory `needs-pair`).
Timed work is the session-scoped model subset — not provider-count, not
selector render. Observed `ssm_all` / `ssm_partial` / `ssm_unavail` /
`ssm_empty` / `ssm_full` / `ssm_single` are exact. First n=5 freeze
**2.563×** (11.473 / 4.477 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text / `execution_env.tmp_*`; this metric did not
fail). Booked over-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 563 — `cli_selectors` (scoped_model_id_enabled_p)

| metric | cadr | pi |
|---|---|---|
| `scoped_model_id_enabled_p` | `scoped-model-id-enabled-p` (`src/cadr-cli/interactive/selectors/models.lisp`) | `isEnabled` (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pair 562. Selector states prepared with
`:keybindings :bench` so constructor cost is not on the timed path.
Observed `smie_all` / `smie_hit` / `smie_miss` / `smie_empty` /
`smie_stale` / `smie_all_stale` are exact. First n=5 freeze **0.775×**
(0.167 / 0.215 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes; this metric
did not fail). Same commit no optimize. `nextPairNum` left at 328.

### Pair 564 — `cli_selectors` (scoped_models_toggle_id)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_toggle_id` | `scoped-models-toggle-id` (`src/cadr-cli/interactive/selectors/models.lisp`) | `toggle` (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pairs 562–563. Timed work is enable-id list toggle
— not `scoped-models-selector-toggle-selected`. Observed `smti_from_all`
/ `smti_remove` / `smti_add` / `smti_empty` / `smti_again` /
`smti_unavail` are exact. First n=5 freeze **1.191×** (1.098 / 0.922 µs)
on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1
only from known old holes; this metric did not fail). Booked over-1×.
Same commit no optimize. `nextPairNum` left at 328.

### Pair 565 — `cli_selectors` (all_known_model_ids_enabled_p)

| metric | cadr | pi |
|---|---|---|
| `all_known_model_ids_enabled_p` | `all-known-model-ids-enabled-p` (`src/cadr-cli/interactive/selectors/models.lisp`) | enableAll collapse-to-null check (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of the `cli_selectors` hole on `models.lisp`. Timed work is the list-length-and-membership collapse check — not `scoped-models-selector-enable-all`, not the selector UI. Observed `ake_all` / `ake_full` / `ake_partial` / `ake_empty` / `ake_vacuous` / `ake_wrong` are exact. First n=5 freeze **2.035×** (1.679 / 0.825 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 566 — `cli_selectors` (scoped_models_enable_ids)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_enable_ids` | `scoped-models-enable-ids` (`src/cadr-cli/interactive/selectors/models.lisp`) | enableAll id union (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pair 565 on the same `models.lisp` hole. Timed work is union of enabled ids with targets, collapsing to `:all` / `null` when every known id is present — not the selector wrapper. Observed `smei_all` / `smei_one` / `smei_rest` / `smei_add` / `smei_fill` / `smei_none` are exact. First n=5 freeze **1.519×** (2.605 / 1.715 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes; this metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 567 — `cli_selectors` (scoped_models_clear_ids)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_clear_ids` | `scoped-models-clear-ids` (`src/cadr-cli/interactive/selectors/models.lisp`) | clearAll id subtract (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pairs 565–566 on the same `models.lisp` hole. Timed work is subtract of target ids from `:all` (via `all-ids`) or from an explicit enabled list — not `scoped-models-selector-clear-all`. Observed `smci_all_one` / `smci_list` / `smci_all_all` / `smci_empty` / `smci_keep` / `smci_all_none` are exact. First n=5 freeze **2.015×** (2.931 / 1.455 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes; this metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 568 — `cli_selectors` (scoped_models_enabled_set)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_enabled_set` | `scoped-models-enabled-set` (`src/cadr-cli/interactive/selectors/models.lisp`) | `new Set(enabledIds)` in `getSortedIds` (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of the `cli_selectors` hole on `models.lisp`. Timed work is hash-table / Set construction over enabled ids (empty, one, two, duplicate, unsorted, three) — not `getSortedIds` order merge, not the selector UI. Observed `smes_empty` / `smes_one` / `smes_two` / `smes_dup` / `smes_sort` / `smes_three` are exact. First n=5 freeze **2.540×** (2.709 / 1.067 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 569 — `cli_selectors` (model_equal_p)

| metric | cadr | pi |
|---|---|---|
| `model_equal_p` | `model-equal-p` (`src/cadr-cli/interactive/selectors/models.lisp`) | `modelsAreEqual` (`packages/ai/src/models.ts`) |

Leftover sibling of Pair 568 on the same `models.lisp` hole. Timed work is id+provider equality plus both-nil / one-nil misses — not `sort-model-selector-models`, not the selector. Observed `meq_same` / `meq_diff_id` / `meq_diff_prov` / `meq_nil_left` / `meq_nil_right` / `meq_both_nil` are exact. First n=5 freeze **1.840×** (0.458 / 0.249 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes; this metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 570 — `cli_selectors` (scoped_model_selector_search_text)

| metric | cadr | pi |
|---|---|---|
| `scoped_model_selector_search_text` | `scoped-model-selector-search-text` (`src/cadr-cli/interactive/selectors/models.lisp`) | `getModelSearchText` (`packages/coding-agent/src/modes/interactive/model-search.ts`) |

Leftover sibling of Pairs 568–569 on the same `models.lisp` hole. Timed work is the scoped-selector search haystack (`id provider provider/id provider id` plus optional name) — not `getModelSelectorSearchText` / `model-selector-search-text`. Observed `smsst_openai` / `smsst_anthropic` / `smsst_codex` / `smsst_openrouter` / `smsst_google` / `smsst_noname` are exact. First n=5 freeze **8.503×** (4.242 / 0.499 µs) on host `cursor`, ceiling 12.0. Gate used `--only-enforce` (script rc=1 only from known old holes; this metric did not fail; variance floor bound the 8.0 ratio on the first run, ceiling raised to 12.0). Over-1× booked. Same commit no optimize.

### Pair 571 — `cli_selectors` (model_selector_active_models)

| metric | cadr | pi |
|---|---|---|
| `model_selector_active_models` | `model-selector-active-models` (`src/cadr-cli/interactive/selectors/models.lisp`) | `activeModels` scope switch (`packages/coding-agent/src/modes/interactive/components/model-selector.ts`) |

Leftover sibling of the `cli_selectors` hole on `models.lisp`. Timed work is all-vs-scoped list selection (including empty, one, and forced scope) — not `model-selector-toggle-scope`, not filter. Observed `msa_all` / `msa_scoped` / `msa_empty` / `msa_one` / `msa_force_all` / `msa_force_scoped` are exact. First n=5 freeze **11.315×** (20.408 / 1.804 µs) on host `cursor`, ceiling 15.0. Gate used `--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail after first-freeze ceiling). Over-1× booked. Same commit no optimize.

### Pair 572 — `cli_selectors` (model_selector_clamp_selected)

| metric | cadr | pi |
|---|---|---|
| `model_selector_clamp_selected` | `model-selector-clamp-selected` (`src/cadr-cli/interactive/selectors/models.lisp`) | `filterModels` selectedIndex clamp (`packages/coding-agent/src/modes/interactive/components/model-selector.ts`) |

Leftover sibling of Pair 571 on the same `models.lisp` hole. Timed work is clamp of `selected` to `[0, count)` including empty, one, and filtered lists — not move, not apply-filter itself. Observed `msc_ok` / `msc_high` / `msc_zero` / `msc_one` / `msc_keep` / `msc_filter` are exact. First n=5 freeze **4.015×** (21.011 / 5.234 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old holes; this metric did not fail). Over-1× booked. Same commit no optimize.

### Pair 573 — `cli_selectors` (model_selector_select_current)

| metric | cadr | pi |
|---|---|---|
| `model_selector_select_current` | `model-selector-select-current` (`src/cadr-cli/interactive/selectors/models.lisp`) | `setScope` currentIndex (`packages/coding-agent/src/modes/interactive/components/model-selector.ts`) |

Leftover sibling of Pairs 571–572 on the same `models.lisp` hole. Timed work is `position` / `findIndex` of the current model in the visible list, including miss / nil / empty — not sort, not toggle-scope. Observed `msel_hit` / `msel_first` / `msel_last` / `msel_miss` / `msel_nil` / `msel_empty` are exact. First n=5 freeze **43.943×** (19.744 / 0.449 µs) on host `cursor`, ceiling 55.0. Gate used `--only-enforce` (script rc=1 only from known old holes; this metric did not fail after first-freeze ceiling). Over-1× booked. Same commit no optimize.

### Pair 574 — `cli_selectors` (sort_model_selector_models)

| metric | cadr | pi |
|---|---|---|
| `sort_model_selector_models` | `sort-model-selector-models` (`src/cadr-cli/interactive/selectors/models.lisp`) | current-first then `provider` `localeCompare` (`packages/coding-agent/src/modes/interactive/components/model-selector.ts`) |

Leftover on unused helpers in `models.lisp`. Timed work is current-first
then provider-key sort of unique-provider fixtures — not
`make-model-selector-state`, not filter. Observed `smsort_first` /
`smsort_last` / `smsort_mid` / `smsort_rev` / `smsort_single` are exact.
First n=5 freeze **2.928×** (8.603 / 2.939 µs) on host `cursor`, ceiling
8.0. Gate used `--only-enforce` (script rc=1 only from known old holes
`lc_n` / `lc_sleep` / help text / `execution_env.tmp_*`; this metric did
not fail). Over-1× booked. Same commit no optimize. `nextPairNum` left at
328.

### Pair 575 — `cli_selectors` (model_selector_visible_models)

| metric | cadr | pi |
|---|---|---|
| `model_selector_visible_models` | `model-selector-visible-models` (`src/cadr-cli/interactive/selectors/models.lisp`) | `filteredModels` after filter (`packages/coding-agent/src/modes/interactive/components/model-selector.ts`) |

Leftover sibling of Pair 574 on the same `models.lisp` hole. Timed work is
the filtered-models accessor after construct + apply-filter (empty / gpt /
nope / anth / oogle) — not viewport slice, not sort. Observed `msvm_all` /
`msvm_gpt` / `msvm_nope` / `msvm_anth` / `msvm_oogle` are exact. First n=5
freeze **1.879×** (37.867 / 20.148 µs) on host `cursor`, ceiling 8.0. Gate
used `--only-enforce` (script rc=1 only from known old holes). Over-1×
booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 576 — `cli_selectors` (model_selector_visible_slice)

| metric | cadr | pi |
|---|---|---|
| `model_selector_visible_slice` | `model-selector-visible-slice` (`src/cadr-cli/interactive/selectors/models.lisp`) | viewport slice of `filteredModels` (`packages/coding-agent/src/modes/interactive/components/model-selector.ts`) |

Leftover sibling of Pairs 574–575 on the same `models.lisp` hole. Distinct
from already-paired `cli_selectors.visible_slice`
(`selector-frame-visible-slice`). Timed work is start|total|ids digest at
max 10 / mid max 3 / gpt filter / nope / max 1. Observed `msvs_all` /
`msvs_mid` / `msvs_filter` / `msvs_empty` / `msvs_max1` are exact. First
n=5 freeze **2.710×** (31.486 / 11.617 µs) on host `cursor`, ceiling 8.0.
Gate used `--only-enforce` (script rc=1 only from known old holes). Over-1×
booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 577 — `cli_selectors` (model_selector_rebuild_search_text_table)

| metric | cadr | pi |
|---|---|---|
| `model_selector_rebuild_search_text_table` | `model-selector-rebuild-search-text-table` (`src/cadr-cli/interactive/selectors/models.lisp`) | search-text table rebuild (`packages/coding-agent/src/modes/interactive/components/model-selector.ts`) |

Leftover on unused helpers in `models.lisp`. Timed work is eq/Map identity
table fill (all-models, overlapping scoped refs, extra scoped object,
empty, scoped-only) — not `model-selector-search-text` pairing, not
filter. Observed `msrst_all` / `msrst_overlap` / `msrst_extra` /
`msrst_empty` / `msrst_scoped_only` are exact. First n=5 freeze **3.240×**
(16.001 / 4.939 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail).
Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 578 — `cli_selectors` (model_selector_filter_search_text)

| metric | cadr | pi |
|---|---|---|
| `model_selector_filter_search_text` | `model-selector-filter-search-text` (`src/cadr-cli/interactive/selectors/models.lisp`) | search-text table lookup (`packages/coding-agent/src/modes/interactive/components/model-selector.ts`) |

Leftover sibling of Pair 577 on the same `models.lisp` hole. Timed work is
table hit / last / scoped-extra / miss fallback / empty-table fallback —
not rebuild pairing, not fuzzy filter. Observed `msfst_hit` / `msfst_last`
/ `msfst_extra` / `msfst_miss` / `msfst_empty` are exact. First n=5 freeze
**4.389×** (13.376 / 3.048 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum`
left at 328.

### Pair 579 — `cli_selectors` (model_selector_finish_refresh)

| metric | cadr | pi |
|---|---|---|
| `model_selector_finish_refresh` | `model-selector-finish-refresh` (`src/cadr-cli/interactive/selectors/models.lisp`) | catalog refresh completion (`packages/coding-agent/src/modes/interactive/components/model-selector.ts`) |

Leftover sibling of Pairs 577–578 on the same `models.lisp` hole. Timed
work is sort + status/error/kind + skip-refilter-when-query-unchanged +
select/clamp (ok / fail / accent kind / reversed snapshot / gpt query) —
not `make-model-selector-state` constructor, not handle-event. Observed
`msfr_ok` / `msfr_err` / `msfr_kind` / `msfr_rev` / `msfr_query` are
exact. First n=5 freeze **4.278×** (46.658 / 10.907 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no
optimize. `nextPairNum` left at 328.

### Pair 580 — `cli_selectors` (scoped_models_selector_rebuild_models_by_id)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_rebuild_models_by_id` | `scoped-models-selector-rebuild-models-by-id` (`src/cadr-cli/interactive/selectors/models.lisp`) | `modelsById` rebuild (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover on unused helpers in `models.lisp`. Timed work is hash/Map fill of
qualified ids (all, partial enabled copy, empty, single, extra grok) —
constructor uses `%make-scoped-models-selector-state` so keybindings are
not on the path. Observed `smrm_all` / `smrm_partial` / `smrm_empty` /
`smrm_single` / `smrm_extra` are exact. First n=5 freeze **2.096×**
(10.000 / 4.771 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail).
Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 581 — `cli_selectors` (scoped_models_model_by_id)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_model_by_id` | `scoped-models-model-by-id` (`src/cadr-cli/interactive/selectors/models.lisp`) | `modelsById` lookup (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pair 580 on the same `models.lisp` hole. Timed work is
hit / google / miss / empty-table / openrouter id — not rebuild pairing
as the named metric. Observed `smbid_hit` / `smbid_google` / `smbid_miss`
/ `smbid_empty` / `smbid_openrouter` are exact. First n=5 freeze **3.185×**
(9.193 / 2.886 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum`
left at 328.

### Pair 582 — `cli_selectors` (scoped_model_item_search_text)

| metric | cadr | pi |
|---|---|---|
| `scoped_model_item_search_text` | `scoped-model-item-search-text` (`src/cadr-cli/interactive/selectors/models.lisp`) | `getModelSearchText` on a scoped item (`packages/coding-agent/src/modes/interactive/model-search.ts`) |

Leftover sibling of Pairs 580–581 on the same `models.lisp` hole. Timed
work is gpt / claude / codex / cached `:search-text` / no-model id —
reuses JS `scopedModelItemSearchText`. Observed `smist_gpt` /
`smist_claude` / `smist_codex` / `smist_cached` / `smist_noid` are exact.
First n=5 freeze **3.735×** (2.879 / 0.771 µs) on host `cursor`, ceiling
8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize.
`nextPairNum` left at 328.

### Pair 583 — `cli_selectors` (scoped_models_copy_enabled)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_copy_enabled` | `scoped-models-copy-enabled` (`src/cadr-cli/interactive/selectors/models.lisp`) | enabled-ids copy (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover on unused helpers in `models.lisp`. Timed work is `:all` / two ids /
empty / one id / copy independence — not persist pairing. Observed `smce_all`
/ `smce_two` / `smce_empty` / `smce_one` / `smce_copy` are exact. First n=5
freeze **1.604×** (0.743 / 0.463 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail).
Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 584 — `cli_selectors` (scoped_models_selector_items)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_items` | `scoped-models-selector-items` (`src/cadr-cli/interactive/selectors/models.lisp`) | items after rebuild (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pair 583 on the same `models.lisp` hole. Timed work is
rebuild-items then items getter (all / partial / empty-enabled / empty
models / single). Reuses JS `scopedModelsBuildItems`. Constructor uses
`%make-scoped-models-selector-state`. Observed `smsi_all` / `smsi_partial`
/ `smsi_none` / `smsi_empty` / `smsi_single` are exact. First n=5 freeze
**4.189×** (26.959 / 6.435 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum`
left at 328.

### Pair 585 — `cli_selectors` (scoped_models_selector_cancel)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_cancel` | `scoped-models-selector-cancel` (`src/cadr-cli/interactive/selectors/models.lisp`) | `onCancel` (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pairs 583–584 on the same `models.lisp` hole. Timed
work is callback once / twice / missing / missing twice / zero times —
not handle-event escape. Observed `smsc_once` / `smsc_twice` / `smsc_none`
/ `smsc_none2` / `smsc_zero` are exact. First n=5 freeze **1.746×**
(0.667 / 0.382 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum`
left at 328.

### Pair 586 — `cli_selectors` (scoped_models_selector_selected_item)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_selected_item` | `scoped-models-selector-selected-item` (`src/cadr-cli/interactive/selectors/models.lisp`) | selected visible item (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover on unused helpers in `models.lisp`. Timed work is selected item id
(first / mid / out-of-range / empty / gpt filter) after
`%make-scoped-models-selector-state` + refresh-items. Reuses JS
`scopedModelsFilterItems`. Observed `smsel_first` / `smsel_mid` /
`smsel_oob` / `smsel_empty` / `smsel_gpt` are exact. First n=5 freeze
**3.417×** (26.636 / 7.796 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` /
`lc_sleep` / help text / `execution_env.tmp_*`; this metric did not fail).
Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 587 — `cli_selectors` (scoped_models_selector_select_id)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_select_id` | `scoped-models-selector-select-id` (`src/cadr-cli/interactive/selectors/models.lisp`) | select by qualified id (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pair 586 on the same `models.lisp` hole. Timed work is
select-id then selected index (first / last / miss keeps 3 / empty /
gpt filter). Observed `smsid_first` / `smsid_last` / `smsid_miss` /
`smsid_empty` / `smsid_gpt` are exact. First n=5 freeze **3.323×**
(26.954 / 8.112 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum`
left at 328.

### Pair 588 — `cli_selectors` (scoped_models_selector_notify_change)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_notify_change` | `scoped-models-selector-notify-change` (`src/cadr-cli/interactive/selectors/models.lisp`) | `onChange` (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pairs 586–587 on the same `models.lisp` hole. Timed
work is change-callback payload|count (`:all` / partial / missing /
twice / empty list) — not mark-changed, not persist. Observed `smnc_all`
/ `smnc_partial` / `smnc_none` / `smnc_twice` / `smnc_empty` are exact.
First n=5 freeze **1.745×** (1.398 / 0.801 µs) on host `cursor`, ceiling
8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize.
`nextPairNum` left at 328.

### Pair 589 — `cli_selectors` (scoped_models_selector_rebuild_items)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_rebuild_items` | `scoped-models-selector-rebuild-items` (`src/cadr-cli/interactive/selectors/models.lisp`) | rebuild items (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover on unused helpers in `models.lisp`. Timed work is rebuild-items then
item ids (all / partial / empty-enabled / empty models / single) through
`%make-scoped-models-selector-state`. Reuses JS `scopedModelsBuildItems`.
Observed `smri_all` / `smri_partial` / `smri_none` / `smri_empty` /
`smri_single` are exact. First n=5 freeze **4.448×** (27.154 / 6.105 µs) on
host `cursor`, ceiling 8.0. Gate used `--only-enforce` (script rc=1 only
from known old holes `lc_n` / `lc_sleep` / help text /
`execution_env.tmp_*`; this metric did not fail). Over-1× booked. Same
commit no optimize. `nextPairNum` left at 328.

### Pair 590 — `cli_selectors` (scoped_models_selector_apply_filter)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_apply_filter` | `scoped-models-selector-apply-filter` (`src/cadr-cli/interactive/selectors/models.lisp`) | apply filter (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pair 589 on the same `models.lisp` hole. Timed work is
rebuild then apply-filter visible ids (empty query / gpt / miss / partial
+ gpt / empty models). Reuses JS `scopedModelsFilterItems`. Observed
`smaf_all` / `smaf_gpt` / `smaf_miss` / `smaf_partial` / `smaf_empty` are
exact. First n=5 freeze **1.464×** (34.896 / 23.842 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no
optimize. `nextPairNum` left at 328.

### Pair 591 — `cli_selectors` (scoped_models_selector_visible_items)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_visible_items` | `scoped-models-selector-visible-items` (`src/cadr-cli/interactive/selectors/models.lisp`) | visible items (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pairs 589–590 on the same `models.lisp` hole. Timed
work is the lazy visible-items getter (all / gpt / miss / empty models /
partial enabled). Observed `smvi_all` / `smvi_gpt` / `smvi_miss` /
`smvi_empty` / `smvi_partial` are exact. First n=5 freeze **2.422×**
(32.039 / 13.230 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum`
left at 328.

### Pair 592 — `cli_selectors` (scoped_models_selector_refresh_items)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_refresh_items` | `scoped-models-selector-refresh-items` (`src/cadr-cli/interactive/selectors/models.lisp`) | refresh items (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pair 240 on the same `models.lisp` hole. Timed work is
rebuild then apply-filter (all / gpt / miss / empty models / partial
enabled) via `%make-scoped-models-selector-state`. Reuses JS
`scopedModelsFilterItems`. Observed `smref_all` / `smref_gpt` /
`smref_miss` / `smref_empty` / `smref_partial` are exact. First n=5 freeze
**2.471×** (33.511 / 13.561 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep`
/ help text / `execution_env.tmp_*`; this metric did not fail). Over-1×
booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 593 — `cli_selectors` (scoped_models_selector_clamp_selected)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_clamp_selected` | `scoped-models-selector-clamp-selected` (`src/cadr-cli/interactive/selectors/models.lisp`) | clamp selected (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pair 592 on the same `models.lisp` hole. Timed work is
clamp after a high / zero / miss-query / gpt-query / empty-models selected
index. Reuses JS `scopedModelsSelectorClampSelected` (does not redeclare).
Observed `smcl_high` / `smcl_zero` / `smcl_miss` / `smcl_gpt` / `smcl_empty`
are exact. First n=5 freeze **2.365×** (30.415 / 12.863 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same
commit no optimize. `nextPairNum` left at 328.

### Pair 594 — `cli_selectors` (scoped_models_selector_mark_changed)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_mark_changed` | `scoped-models-selector-mark-changed` (`src/cadr-cli/interactive/selectors/models.lisp`) | mark changed (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pairs 592–593 on the same `models.lisp` hole. Timed
work is dirty + refresh-items + clamp + notify-change (all / partial /
empty enabled / no callback / gpt filter). Observed `smmc_all` /
`smmc_partial` / `smmc_empty` / `smmc_nocb` / `smmc_filter` are exact.
First n=5 freeze **1.359×** (35.327 / 25.989 µs) on host `cursor`, ceiling
8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize.
`nextPairNum` left at 328.

### Pair 595 — `cli_selectors` (scoped_models_selector_finish_refresh)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_finish_refresh` | `scoped-models-selector-finish-refresh` (`src/cadr-cli/interactive/selectors/models.lisp`) | `updateModels` + `setRefreshStatus` (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pair 594 on the same `models.lisp` hole. Timed work is
catalog reload with selection preserved by id, optional enabled-ids replace,
and terminal refresh status (ok / success / reversed models / partial
enabled / gpt filter) via `%make-scoped-models-selector-state`. Reuses JS
`scopedModelsFilterItems` / `scopedModelsSelectorClampSelected`. Observed
`smfrf_ok` / `smfrf_success` / `smfrf_rev` / `smfrf_enabled` / `smfrf_filter`
are exact. First n=5 freeze **3.243×** (68.310 / 21.063 µs) on host
`cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report
`parsed_provider` from METRICS observed-key pollution; this metric did not
fail observed-exact). Over-1× booked. Same commit no optimize.
`nextPairNum` left at 328.

### Pair 596 — `cli_selectors` (scoped_models_selector_key_p)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_key_p` | `scoped-models-selector-key-p` (`src/cadr-cli/interactive/selectors/models.lisp`) | `KeybindingsManager.matches` + CSI modified-arrow canonical compare (`packages/tui/src/keybindings.ts`) |

Leftover sibling of Pair 595 on the same `models.lisp` hole. Timed work is
`selector-keybinding-matches-p` on cached
`*default-models-selector-keybindings*` (ctrl+s save hit / miss, up-arrow
hit, CSI `1;1A` up, garbage). Does not time `make-keybindings-manager`.
Observed `smskp_save_hit` / `smskp_save_miss` / `smskp_up_hit` /
`smskp_csi_up` / `smskp_garbage` are exact. First n=5 freeze **18.835×**
(22.914 / 1.217 µs) on host `cursor`, ceiling 30.0 first-freeze headroom.
Gate used `--only-enforce`. Over-1× booked. Same commit no optimize.
`nextPairNum` left at 328.

### Pair 597 — `cli_selectors` (scoped_models_binding_label)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_binding_label` | `scoped-models-binding-label` (`src/cadr-cli/interactive/selectors/models.lisp`) | `KeybindingsManager.getKeys` first-or-fallback (`packages/coding-agent/src/core/keybindings.ts`) |

Leftover sibling of Pairs 595–596 on the same `models.lisp` hole. Timed
work is first bound key or the binding name (save / enableAll / confirm /
missing name / custom `ctrl+k`). Cached default and custom managers; does
not time `make-keybindings-manager`. Observed `smbl_save` / `smbl_enable` /
`smbl_confirm` / `smbl_fallback` / `smbl_custom` are exact. First n=5 freeze
**16.362×** (5.542 / 0.339 µs) on host `cursor`, ceiling 25.0 first-freeze
headroom. Gate used `--only-enforce`. Over-1× booked. Same commit no
optimize. `nextPairNum` left at 328.

### Pair 598 — `cli_selectors` (model_selector_key_p)

| metric | cadr | pi |
|---|---|---|
| `model_selector_key_p` | `model-selector-key-p` (`src/cadr-cli/interactive/selectors/models.lisp`) | `KeybindingsManager.matches` + CSI modified-arrow canonical compare (`packages/tui/src/keybindings.ts`) |

Leftover sibling of Pair 596 on the same `models.lisp` hole. Timed work is
`selector-keybinding-matches-p` on cached
`*default-models-selector-keybindings*` (tab hit / miss, up-arrow hit, CSI
`1;1A` up, ctrl+s save). Does not time `make-keybindings-manager`. Observed
`mskp_tab_hit` / `mskp_tab_miss` / `mskp_up_hit` / `mskp_csi_up` /
`mskp_save_hit` are exact. First n=5 freeze **18.605×** (16.140 / 0.868 µs)
on host `cursor`, ceiling 30.0 first-freeze headroom. Gate used
`--only-enforce` (py invalid-report `parsed_provider` from METRICS
observed-key pollution; this metric did not fail observed-exact). Over-1×
booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 599 — `cli_selectors` (model_selector_keybindings)

| metric | cadr | pi |
|---|---|---|
| `model_selector_keybindings` | `model-selector-keybindings` (`src/cadr-cli/interactive/selectors/models.lisp`) | `getKeybindings` slot-or-default (`packages/coding-agent/src/modes/interactive/components/model-selector.ts`) |

Leftover sibling of Pairs 597–598 on the same `models.lisp` hole. Timed
work is the cached manager slot-or-default, then first bound key (nil slot
/ explicit default / custom `ctrl+k` / enableAll / confirm). Does not time
`make-keybindings-manager`. Observed `mskb_nil` / `mskb_default` /
`mskb_custom` / `mskb_enable` / `mskb_confirm` are exact. First n=5 freeze
**8.076×** (4.144 / 0.513 µs) on host `cursor`, ceiling 12.0 first-freeze
headroom. Gate used `--only-enforce`. Over-1× booked. Same commit no
optimize. `nextPairNum` left at 328.

### Pair 600 — `cli_selectors` (make_model_selector_state)

| metric | cadr | pi |
|---|---|---|
| `make_model_selector_state` | `make-model-selector-state` (`src/cadr-cli/interactive/selectors/models.lisp`) | constructor sort + filter + select current (`packages/coding-agent/src/modes/interactive/components/model-selector.ts`) |

Leftover sibling of Pairs 598–599 on the same `models.lisp` hole. Timed
work is sort-by-current, scoped copy, search-text table rebuild, empty-query
filter, and select-current (all / current-last / scoped / extra scoped id /
single model). Passes cached default keybindings; does not time
`make-keybindings-manager`. Observed `msmk_all` / `msmk_last` /
`msmk_scoped` / `msmk_extra` / `msmk_one` are exact. First n=5 freeze
**3.037×** (21.230 / 6.989 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce`. Over-1× booked. Same commit no optimize.
`nextPairNum` left at 328.

### Pair 601 — `cli_selectors` (thinking_selector_key_p)

| metric | cadr | pi |
|---|---|---|
| `thinking_selector_key_p` | `thinking-selector-key-p` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | `KeybindingsManager.matches` + CSI modified-arrow canonical compare (`packages/tui/src/keybindings.ts`) |

Leftover trio on `src/cadr-cli/interactive/selectors/thinking.lisp` / hole `cli_selectors`. Timed work is `selector-keybinding-matches-p` on cached `*default-thinking-selector-keybindings*` (tab hit / miss, up-arrow hit, CSI `1;1A` up, ctrl+s save). Does not time `make-thinking-selector-keybindings`. Pi `KEYBINDINGS` lacks `app.thinking.save`; the harness spreads those definitions into the manager. Observed `tskp_tab_hit` / `tskp_tab_miss` / `tskp_up_hit` / `tskp_csi_up` / `tskp_save_hit` are exact. First n=5 freeze **19.196×** (15.469 / 0.806 µs) on host `cursor`, ceiling 30.0 first-freeze headroom. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 602 — `cli_selectors` (thinking_selector_keybindings)

| metric | cadr | pi |
|---|---|---|
| `thinking_selector_keybindings` | `thinking-selector-keybindings` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | `getKeybindings` slot-or-default (`packages/coding-agent/src/modes/interactive/components/thinking-selector.ts`) |

Leftover sibling of Pair 601 on the same `thinking.lisp` hole. Timed work is the cached manager slot-or-default, then first bound key (nil slot / explicit default / custom `ctrl+k` / clearSearchOrCancel / confirm). Does not time `make-thinking-selector-keybindings`. Observed `tskb_nil` / `tskb_default` / `tskb_custom` / `tskb_cancel` / `tskb_confirm` are exact. First n=5 freeze **5.685×** (3.014 / 0.530 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 603 — `cli_selectors` (make_thinking_selector_state)

| metric | cadr | pi |
|---|---|---|
| `make_thinking_selector_state` | `make-thinking-selector-state` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | constructor filter + select current (`packages/coding-agent/src/modes/interactive/components/thinking-selector.ts`) |

Leftover sibling of Pairs 601–602 on the same `thinking.lisp` hole. Timed work is `%make-thinking-selector-state` plus `thinking-selector-apply-filter` plus `thinking-selector-select-current` (high / off / missing medium / empty levels / default-level). Initial empty query equals `(or filter-query "")`, so apply-filter no-ops and filtered-count stays 0 on both harness sides. Observed encode is `levels-n|current|selected|filtered-count|selected-level|default`. Observed `tms_high` / `tms_off` / `tms_miss` / `tms_empty` / `tms_default` are exact. First n=5 freeze **0.638×** (1.623 / 2.545 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce`. Same commit no optimize. `nextPairNum` left at 328. Also restores dropped leftover collect wiring for thinking.lisp slugs 532–534.

### Pair 604 — `cli_selectors` (thinking_selector_apply_filter)

| metric | cadr | pi |
|---|---|---|
| `thinking_selector_apply_filter` | `thinking-selector-apply-filter` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | `applyFilter` (`packages/coding-agent/src/modes/interactive/components/thinking-selector.ts`) |

Leftover sibling of Pairs 601–603 on the same `thinking.lisp` hole. Timed work is query apply on a fresh `%make-thinking-selector-state` (high / off / miss / empty-after-high / low). Does not time `make-thinking-selector-keybindings`. Observed `tsaf_high` / `tsaf_off` / `tsaf_miss` / `tsaf_empty` / `tsaf_low` are exact. First n=5 freeze **1.149×** (13.399 / 11.664 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 605 — `cli_selectors` (thinking_selector_clamp_selected)

| metric | cadr | pi |
|---|---|---|
| `thinking_selector_clamp_selected` | `thinking-selector-clamp-selected` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | clamp selected index (`packages/coding-agent/src/modes/interactive/components/thinking-selector.ts`) |

Leftover sibling of Pair 604 on the same `thinking.lisp` hole. Timed work is clamp of selected against filtered-count (over-range / empty / in-range / last / singleton). Observed `tscl_high` / `tscl_zero` / `tscl_ok` / `tscl_last` / `tscl_one` are exact. First n=5 freeze **0.753×** (0.637 / 0.847 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce`. Same commit no optimize. `nextPairNum` left at 328.

### Pair 606 — `cli_selectors` (thinking_selector_select_current)

| metric | cadr | pi |
|---|---|---|
| `thinking_selector_select_current` | `thinking-selector-select-current` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | select current thinking level (`packages/coding-agent/src/modes/interactive/components/thinking-selector.ts`) |

Leftover sibling of Pairs 604–605 on the same `thinking.lisp` hole. Timed work is `position`/`indexOf` of current-level in filtered-levels (high / off / missing medium / empty / only-high). Observed `tssc_high` / `tssc_off` / `tssc_miss` / `tssc_empty` / `tssc_only` are exact. First n=5 freeze **0.854×** (0.981 / 1.149 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce`. Same commit no optimize. `nextPairNum` left at 328.

### Pair 607 — `cli_selectors` (thinking_selector_move)

| metric | cadr | pi |
|---|---|---|
| `thinking_selector_move` | `thinking-selector-move` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | wrap selected index (`packages/coding-agent/src/modes/interactive/components/thinking-selector.ts`) |

Leftover sibling of Pairs 604–606 on the same `thinking.lisp` hole. Timed work is `selector-frame-move-index` wrap (down / up-wrap / down-wrap / page / empty). Observed `tsmv_down` / `tsmv_up_wrap` / `tsmv_down_wrap` / `tsmv_page` / `tsmv_empty` are exact. First n=5 freeze **1.353×** (0.637 / 0.471 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 608 — `cli_selectors` (thinking_selector_handle_raw_input)

| metric | cadr | pi |
|---|---|---|
| `thinking_selector_handle_raw_input` | `thinking-selector-handle-raw-input` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | handleInput keybindings (`packages/coding-agent/src/modes/interactive/components/thinking-selector.ts`) |

Leftover sibling of Pair 607 on the same `thinking.lisp` hole. Timed work is raw CSI down/up, CR confirm, ctrl+s persist, and `q` miss on cached `*default-thinking-selector-keybindings*`. Does not time `make-thinking-selector-keybindings`. Observed `tshri_down` / `tshri_up` / `tshri_enter` / `tshri_save` / `tshri_nop` are exact. First n=5 freeze **20.910×** (144.448 / 6.908 µs) on host `cursor`, ceiling 30.0 first-freeze headroom. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 609 — `cli_selectors` (thinking_selector_handle_event)

| metric | cadr | pi |
|---|---|---|
| `thinking_selector_handle_event` | `thinking-selector-handle-event` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | typed input event dispatch (`packages/coding-agent/src/modes/interactive/components/thinking-selector.ts`) |

Leftover sibling of Pairs 607–608 on the same `thinking.lisp` hole. Timed work is `:down` / `:enter` / `:escape` / `:text "h"` / `:tab` otherwise. Observed `tshe_down` / `tshe_enter` / `tshe_esc` / `tshe_text` / `tshe_tab` are exact. First n=5 freeze **0.834×** (3.312 / 3.974 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce`. Same commit no optimize. `nextPairNum` left at 328.

### Pair 610 — `cli_selectors` (thinking_selector_selected_level)

| metric | cadr | pi |
|---|---|---|
| `thinking_selector_selected_level` | `thinking-selector-selected-level` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | selected SelectList item (`packages/coding-agent/src/modes/interactive/components/thinking-selector.ts`) |

Leftover sibling of Pairs 607–609 on the same `thinking.lisp` hole. Timed work is `nth`/`[]` of filtered-levels at selected (first / mid / last / empty / out-of-range). Observed `tssl_first` / `tssl_mid` / `tssl_last` / `tssl_empty` / `tssl_oob` are exact. First n=5 freeze **0.608×** (0.467 / 0.768 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce`. Same commit no optimize. `nextPairNum` left at 328.

### Pair 611 — `cli_selectors` (thinking_level_description_line)

| metric | cadr | pi |
|---|---|---|
| `thinking_level_description_line` | `thinking-level-description-line` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | LEVEL_DESCRIPTIONS · default suffix (`packages/coding-agent/src/modes/interactive/components/thinking-selector.ts`) |

Leftover sibling of Pair 610 on the same `thinking.lisp` hole. Timed work is description plus optional ` · default` (off-as-default / high / high-as-default / unknown / minimal). Observed `tsdl_off_def` / `tsdl_high` / `tsdl_high_def` / `tsdl_bogus` / `tsdl_min` are exact. First n=5 freeze **1.155×** (0.268 / 0.232 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 612 — `cli_selectors` (render_thinking_selector)

| metric | cadr | pi |
|---|---|---|
| `render_thinking_selector` | `render-thinking-selector` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | ThinkingSelectorComponent layout (`packages/coding-agent/src/modes/interactive/components/thinking-selector.ts`) |

Leftover sibling of Pairs 610–611 on the same `thinking.lisp` hole. Timed work is `render-thinking-selector` (default / selected-last / query / empty / 12-level scroll at width 80). Observed `tsrd_default` / `tsrd_sel` / `tsrd_query` / `tsrd_empty` / `tsrd_wide` are exact. First n=5 freeze **44.726×** (316.671 / 7.080 µs) on host `cursor`, ceiling 60.0 first-freeze headroom. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 613 — `cli_selectors` (trust_option_saved_p)

| metric | cadr | pi |
|---|---|---|
| `trust_option_saved_p` | `trust-option-saved-p` (`src/cadr-cli/interactive/selectors/trust.lisp`) | isSavedOption (`packages/coding-agent/src/modes/interactive/components/trust-selector.ts`) |

Leftover sibling on the `trust.lisp` hole. Timed work is saved-entry match (nil / trust / parent / decision-mismatch / distrust). Observed `tosp_nil` / `tosp_trust` / `tosp_parent` / `tosp_mismatch` / `tosp_distrust` are exact. First n=5 freeze **2.292×** (35.594 / 15.530 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 614 — `cli_selectors` (make_trust_selector_state)

| metric | cadr | pi |
|---|---|---|
| `make_trust_selector_state` | `make-trust-selector-state` (`src/cadr-cli/interactive/selectors/trust.lisp`) | TrustSelectorComponent constructor (`packages/coding-agent/src/modes/interactive/components/trust-selector.ts`) |

Leftover sibling of Pair 613. Timed work is options + saved-position (child / saved / inherited / distrust / single). Cached keybindings so this pair matches pi (does not time `make-keybindings-manager`). Observed `mtss_child` / `mtss_saved` / `mtss_inherited` / `mtss_distrust` / `mtss_single` are exact. First n=5 freeze **1.715×** (91.097 / 53.106 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 615 — `cli_selectors` (render_trust_selector)

| metric | cadr | pi |
|---|---|---|
| `render_trust_selector` | `render-trust-selector` (`src/cadr-cli/interactive/selectors/trust.lisp`) | TrustSelectorComponent layout (`packages/coding-agent/src/modes/interactive/components/trust-selector.ts`) |

Leftover sibling of Pairs 613–614. Timed work is `render-trust-selector` (default / saved / inherited / distrust / single at width 80). Observed `rtrs_default` / `rtrs_saved` / `rtrs_inherited` / `rtrs_distrust` / `rtrs_single` are exact. First n=5 freeze **8.798×** (1074.462 / 122.128 µs) on host `cursor`, ceiling 15.0 first-freeze headroom. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 616 — `cli_selectors` (make_login_method_selector_state)

| metric | cadr | pi |
|---|---|---|
| `make_login_method_selector_state` | `make-login-method-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | ExtensionSelectorComponent constructor (`packages/coding-agent/src/modes/interactive/components/extension-selector.ts`) |

Leftover sibling on the `auth.lisp` hole. Timed work is login-method constructor (default / custom title / custom labels / one item / three items). Observed `mlms_default` / `mlms_title` / `mlms_custom` / `mlms_one` / `mlms_three` are exact. First n=5 freeze **1.143×** (2.654 / 2.323 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 617 — `cli_selectors` (make_api_key_input_state)

| metric | cadr | pi |
|---|---|---|
| `make_api_key_input_state` | `make-api-key-input-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | showPrompt api key Input constructor (`packages/coding-agent/src/modes/interactive/components/login-dialog.ts`) |

Leftover sibling of Pair 616. Timed work is api-key input constructor (anthropic / openai / google / oauth-typed option / named vertex). Observed `makis_anth` / `makis_openai` / `makis_google` / `makis_oauth_opt` / `makis_named` are exact. First n=5 freeze **1.803×** (2.203 / 1.222 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 618 — `cli_selectors` (make_oauth_selector_state)

| metric | cadr | pi |
|---|---|---|
| `make_oauth_selector_state` | `make-oauth-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | OauthSelectorComponent constructor (`packages/coding-agent/src/modes/interactive/components/oauth-selector.ts`) |

Leftover sibling of Pairs 616–617. Timed work is oauth selector constructor (default / filter / miss / logout-empty / logout). Cached keybindings so this pair matches pi (does not time `make-keybindings-manager`). Observed `moss_default` / `moss_filter` / `moss_miss` / `moss_logout_empty` / `moss_logout` are exact. First n=5 freeze **1.204×** (7.245 / 6.020 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 619 — `cli_selectors` (login_dialog_show_waiting)

| metric | cadr | pi |
|---|---|---|
| `login_dialog_show_waiting` | `login-dialog-show-waiting` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | LoginDialogComponent.showWaiting (`packages/coding-agent/src/modes/interactive/components/login-dialog.ts`) |

Leftover sibling on the `login-dialog.lisp` hole after Pairs 529–531 (make/auth/device). Timed work is waiting-state append (empty / after-auth / twice / blank message / after-device). Observed `ldw_empty` / `ldw_auth` / `ldw_twice` / `ldw_blank` / `ldw_device` are exact. First n=5 freeze **1.338×** (5.469 / 4.088 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 620 — `cli_selectors` (login_dialog_show_progress)

| metric | cadr | pi |
|---|---|---|
| `login_dialog_show_progress` | `login-dialog-show-progress` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | LoginDialogComponent.showProgress (`packages/coding-agent/src/modes/interactive/components/login-dialog.ts`) |

Leftover sibling of Pair 619. Timed work is progress-line append (empty / after-auth / two lines / blank / after-waiting). Observed `ldp_empty` / `ldp_auth` / `ldp_two` / `ldp_blank` / `ldp_wait` are exact. First n=5 freeze **1.281×** (3.159 / 2.466 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 621 — `cli_selectors` (login_dialog_show_manual_input)

| metric | cadr | pi |
|---|---|---|
| `login_dialog_show_manual_input` | `login-dialog-show-manual-input` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | LoginDialogComponent.showManualInput (`packages/coding-agent/src/modes/interactive/components/login-dialog.ts`) |

Leftover sibling of Pairs 619–620. Timed work is manual-input append (empty / after-auth / blank prompt / nil cancel / after-waiting). Observed `ldmi_empty` / `ldmi_auth` / `ldmi_blank` / `ldmi_nocancel` / `ldmi_wait` are exact. First n=5 freeze **1.683×** (5.131 / 3.050 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 622 — `cli_selectors` (login_dialog_show_prompt)

| metric | cadr | pi |
|---|---|---|
| `login_dialog_show_prompt` | `login-dialog-show-prompt` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | LoginDialogComponent.showPrompt (`packages/coding-agent/src/modes/interactive/components/login-dialog.ts`) |

Leftover sibling on the `login-dialog.lisp` hole after Pairs 619–621 (wait/progress/manual). Timed work is prompt-state append (empty / after-auth / no placeholder / nil cancel / after-waiting). Observed `ldpr_empty` / `ldpr_auth` / `ldpr_noplace` / `ldpr_nocancel` / `ldpr_wait` are exact. First n=5 freeze **1.771×** (6.781 / 3.830 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 623 — `cli_selectors` (login_dialog_show_info)

| metric | cadr | pi |
|---|---|---|
| `login_dialog_show_info` | `login-dialog-show-info` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | LoginDialogComponent.showInfo (`packages/coding-agent/src/modes/interactive/components/login-dialog.ts`) |

Leftover sibling of Pair 622. Timed work is info-state append (labeled link / after-auth two links / bare URL / no links no close / after-waiting). Observed `ldi_labeled` / `ldi_auth` / `ldi_bare` / `ldi_nolink` / `ldi_wait` are exact. First n=5 freeze **1.567×** (8.766 / 5.594 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 624 — `cli_selectors` (login_dialog_show_details)

| metric | cadr | pi |
|---|---|---|
| `login_dialog_show_details` | `login-dialog-show-details` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | LoginDialogComponent.showDetails (`packages/coding-agent/src/modes/interactive/components/login-dialog.ts`) |

Leftover sibling of Pairs 622–623. Timed work is details replace (two lines / replace-after-auth / empty / muted+accent / replace-after-waiting). Observed `lddt_two` / `lddt_auth` / `lddt_empty` / `lddt_styles` / `lddt_wait` are exact. First n=5 freeze **0.756×** (2.598 / 3.435 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). cadr leads. Same commit no optimize. `nextPairNum` left at 328.

### Pair 625 — `cli_selectors` (login_dialog_complete_input)

| metric | cadr | pi |
|---|---|---|
| `login_dialog_complete_input` | `login-dialog-complete-input` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | LoginDialogComponent.replaceInputWithSubmittedText (`packages/coding-agent/src/modes/interactive/components/login-dialog.ts`) |

Leftover sibling on the `login-dialog.lisp` hole after Pairs 622–624. Timed work is replacing the input section with submitted text (manual / prompt / no-input / blank value / after-auth). Observed `ldci_manual` / `ldci_prompt` / `ldci_none` / `ldci_blank` / `ldci_auth` are exact. First n=5 freeze **1.643×** (5.722 / 3.482 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 626 — `cli_selectors` (login_dialog_handle_event)

| metric | cadr | pi |
|---|---|---|
| `login_dialog_handle_event` | `login-dialog-state-handle-event` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | LoginDialogComponent.handleInput (`packages/coding-agent/src/modes/interactive/components/login-dialog.ts`) |

Leftover sibling of Pair 625. Timed work is typed event dispatch (escape / cancel-fn / enter-empty / type-text / down-no-input). Observed `ldhe_esc` / `ldhe_cancel` / `ldhe_enter` / `ldhe_type` / `ldhe_down` are exact. First n=5 freeze **1.923×** (6.392 / 3.325 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 627 — `cli_selectors` (render_login_dialog)

| metric | cadr | pi |
|---|---|---|
| `render_login_dialog` | `render-login-dialog-state` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | LoginDialogComponent layout (`packages/coding-agent/src/modes/interactive/components/login-dialog.ts`) |

Leftover sibling of Pairs 625–626. Timed work is selector-frame layout (waiting / auth / manual cursor / prompt cursor / details). Observed `ldrd_wait` / `ldrd_auth` / `ldrd_manual` / `ldrd_prompt` / `ldrd_details` are exact. First n=5 freeze **32.688×** (135.552 / 4.147 µs) on host `cursor`, ceiling 50.0 first-freeze headroom. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 628 — `cli_selectors` (user_message_handle_event)

| metric | cadr | pi |
|---|---|---|
| `user_message_handle_event` | `user-message-selector-handle-event` (`src/cadr-cli/interactive/selectors/fork.lisp`) | UserMessageList.handleInput structured events (`packages/coding-agent/src/modes/interactive/components/user-message-selector.ts`) |

Leftover sibling on the `fork.lisp` hole after Pairs 526–528 (make/move/selection). Timed work is typed event dispatch (down wrap / enter select / escape cancel / text no-op / empty enter). Observed `umhe_down` / `umhe_enter` / `umhe_esc` / `umhe_text` / `umhe_empty` are exact. First n=5 freeze **0.766×** (1.754 / 2.288 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. cadr leads. Same commit no optimize. `nextPairNum` left at 328.

### Pair 629 — `cli_selectors` (user_message_handle_raw)

| metric | cadr | pi |
|---|---|---|
| `user_message_handle_raw` | `user-message-selector-handle-raw-input` (`src/cadr-cli/interactive/selectors/fork.lisp`) | UserMessageList.handleInput raw key dispatch (`packages/coding-agent/src/modes/interactive/components/user-message-selector.ts`) |

Leftover sibling of Pair 628. Timed work is raw key dispatch (arrow-down / arrow-up / enter / escape / nop `q`). Observed `umhr_down` / `umhr_up` / `umhr_enter` / `umhr_esc` / `umhr_nop` are exact. First n=5 freeze **15.827×** (85.983 / 5.433 µs) on host `cursor`, ceiling 30.0 first-freeze headroom. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 630 — `cli_selectors` (render_user_message_selector)

| metric | cadr | pi |
|---|---|---|
| `render_user_message_selector` | `render-user-message-selector` (`src/cadr-cli/interactive/selectors/fork.lisp`) | UserMessageSelectorComponent layout (`packages/coding-agent/src/modes/interactive/components/user-message-selector.ts`) |

Leftover sibling of Pairs 628–629. Timed work is selector-frame layout (three items / one / empty / narrow / hit initial). Observed `umrd_three` / `umrd_one` / `umrd_empty` / `umrd_narrow` / `umrd_hit` are exact. First n=5 freeze **65.009×** (265.302 / 4.081 µs) on host `cursor`, ceiling 100.0 first-freeze headroom. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 631 — `cli_selectors` (make_models_selector_keybindings)

| metric | cadr | pi |
|---|---|---|
| `make_models_selector_keybindings` | `make-models-selector-keybindings` (`src/cadr-cli/interactive/selectors/models.lisp`) | KEYBINDINGS `app.models.*` KeybindingsManager constructor (`packages/coding-agent/src/core/keybindings.ts`) |

Leftover sibling on the `models.lisp` hole after Pair 600 (`make-model-selector-state`). Timed work is default/custom first-key lookup (save / enableAll / confirm / custom save / reorderUp). Observed `mmskb_save` / `mmskb_enable` / `mmskb_confirm` / `mmskb_custom` / `mmskb_reorder` are exact. First n=5 freeze **1.496×** (32.105 / 21.468 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 632 — `cli_selectors` (make_scoped_models_selector_state)

| metric | cadr | pi |
|---|---|---|
| `make_scoped_models_selector_state` | `make-scoped-models-selector-state` (`src/cadr-cli/interactive/selectors/models.lisp`) | ScopedModelsSelectorComponent constructor (`packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts`) |

Leftover sibling of Pair 631. Timed work is constructor copy/isolation (all / partial enabled / empty / refresh status / copy length). Observed `msmksc_all` / `msmksc_partial` / `msmksc_empty` / `msmksc_status` / `msmksc_copy` are exact. First n=5 freeze **20.997×** (97.005 / 4.620 µs) on host `cursor`, ceiling 40.0 first-freeze headroom. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 633 — `cli_selectors` (render_model_selector)

| metric | cadr | pi |
|---|---|---|
| `render_model_selector` | `render-model-selector` (`src/cadr-cli/interactive/selectors/models.lisp`) | ModelSelectorComponent layout (`packages/coding-agent/src/modes/interactive/components/model-selector.ts`) |

Leftover sibling of Pairs 631–632. Timed work is selector-frame layout (default / selected-2 / scoped / narrow / miss query). Observed `rms_default` / `rms_sel2` / `rms_scoped` / `rms_narrow` / `rms_miss` are exact. First n=5 freeze **26.593×** (247.317 / 9.300 µs) on host `cursor`, ceiling 50.0 first-freeze headroom. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 634 — `cli_selectors` (daxnuts_rgb_at)

| metric | cadr | pi |
|---|---|---|
| `daxnuts_rgb_at` | `daxnuts-rgb-at` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | parseImage pixel lookup (`packages/coding-agent/src/modes/interactive/components/daxnuts.ts`) |

Leftover sibling on the `daxnuts.lisp` hole after Pairs 547–549 (parse/image-line/center). Timed work is five grid probes ((0,0) / (0,31) / (16,16) / (31,31) / (1,0)). Observed `dra_00` / `dra_0x` / `dra_mid` / `dra_last` / `dra_10` are exact. First n=5 freeze **1.831×** (0.910 / 0.497 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 635 — `cli_selectors` (make_daxnuts_component)

| metric | cadr | pi |
|---|---|---|
| `make_daxnuts_component` | `make-daxnuts-component` (`src/cadr-cli/interactive/components/daxnuts.lisp`, `:start-p nil`) | DaxnutsComponent constructor without `startAnimation` (`packages/coding-agent/src/modes/interactive/components/daxnuts.ts`) |

Leftover sibling of Pair 634. Timed work is constructor isolation without the animation thread (tick / stopped / thread / cache / second instance). Observed `dmc_tick` / `dmc_stop` / `dmc_thread` / `dmc_cache` / `dmc_second` are exact. First n=5 freeze **3.472×** (0.688 / 0.198 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 636 — `cli_selectors` (daxnuts_component_tick)

| metric | cadr | pi |
|---|---|---|
| `daxnuts_component_tick` | `daxnuts-component-tick` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | DaxnutsComponent interval body (`packages/coding-agent/src/modes/interactive/components/daxnuts.ts`) |

Leftover sibling of Pairs 634–635. Timed work is one tick / 25 ticks to max / stop flag / no-op after max / shared render count. Observed `dct_one` / `dct_max` / `dct_stop` / `dct_after` / `dct_renders` are exact (renders=51). First n=5 freeze **1.119×** (3.787 / 3.384 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 637 — `cli_interactive_controller` (theme_object_overrides)

| metric | cadr | pi |
|---|---|---|
| `theme_object_overrides` | `theme-object-overrides` (`src/cadr-cli/interactive/themes.lisp`) | withThemeColorFallbacks + resolveThemeColors (`packages/coding-agent/src/modes/interactive/theme/theme.ts`) |

Leftover sibling on the `themes.lisp` hole after Pairs 523–525 (primitive/resolve/validate). Timed work is override collection plus thinking-max / scrollbar / search-match fallbacks (count / accent / thinking-max / scrollbar-thumb / nil object). Observed `too_n` / `too_accent` / `too_tmax` / `too_scroll` / `too_nil` are exact. First n=5 freeze **0.651×** (22.839 / 35.090 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce`. Same commit no optimize. `nextPairNum` left at 328.

### Pair 638 — `cli_interactive_controller` (apply_tui_theme_summary)

| metric | cadr | pi |
|---|---|---|
| `apply_tui_theme_summary` | `apply-tui-theme-summary` (`src/cadr-cli/interactive/themes.lisp`) | setTheme (`packages/coding-agent/src/modes/interactive/theme/theme.ts`) |

Leftover sibling of Pair 637. Timed work is named dark/light apply, object apply, invalid keep-current, and resulting theme name. Observed `tas_dark` / `tas_light` / `tas_obj` / `tas_bad` / `tas_name` are exact. First n=5 freeze **3.211×** (52.489 / 16.348 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 639 — `cli_interactive_controller` (load_tui_theme_file)

| metric | cadr | pi |
|---|---|---|
| `load_tui_theme_file` | `load-tui-theme-file` (`src/cadr-cli/interactive/themes.lisp`) | loadThemeFromPath (`packages/coding-agent/src/modes/interactive/theme/theme.ts`) |

Leftover sibling of Pairs 637–638. Timed work is JSON load of a valid file / missing / truncated / empty (name / ok / miss / bad / empty). Observed `ltf_name` / `ltf_ok` / `ltf_miss` / `ltf_bad` / `ltf_empty` are exact. First n=5 freeze **2.383×** (233.265 / 97.883 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 640 — `cli_interactive_controller` (bash_append_running)

| metric | cadr | pi |
|---|---|---|
| `bash_append_running` | `append-tui-user-bash-running` (`src/cadr-cli/interactive/user-bash.lisp`) | BashExecutionComponent addChild running (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover sibling of Pairs 493–495 on the same `user-bash.lisp` hole. Timed work is two running appends (`ls` idle-exclude / `echo hi` exclude) plus entry count / label / running / streaming / exclude. Observed `bar_n` / `bar_label` / `bar_run` / `bar_stream` / `bar_ex` / `bar_run2` are exact. First n=5 freeze **2.059×** (0.735 / 0.357 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 641 — `cli_interactive_controller` (bash_complete_string)

| metric | cadr | pi |
|---|---|---|
| `bash_complete_string` | `complete-tui-user-bash-string` (`src/cadr-cli/interactive/user-bash.lisp`) | setComplete exit 0 string (`packages/coding-agent/src/modes/interactive/components/bash-execution.ts`) |

Leftover sibling of Pair 640. Timed work is string complete (`hello`) plus empty-string complete (text / running / streaming / exit 0 / cache invalid / empty length). Observed `cs_text` / `cs_run` / `cs_stream` / `cs_exit` / `cs_cache` / `cs_empty` are exact. First n=5 freeze **2.719×** (0.745 / 0.274 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 642 — `cli_interactive_controller` (bash_stop_entry)

| metric | cadr | pi |
|---|---|---|
| `bash_stop_entry` | `stop-tui-user-bash-entry` (`src/cadr-cli/interactive/user-bash.lisp`) | loader.stop without setComplete (`packages/coding-agent/src/modes/interactive/components/bash-execution.ts`) |

Leftover sibling of Pairs 640–641. Timed work is stop after a partial append (running / streaming / text kept / cache invalid / missing exit). Observed `st_run` / `st_stream` / `st_text` / `st_cache` / `st_exit` are exact. First n=5 freeze **2.843×** (0.621 / 0.219 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 643 — `cli_interactive_controller` (assistant_has_tools)

| metric | cadr | pi |
|---|---|---|
| `assistant_has_tools` | `assistant-message-has-tool-calls-p` (`src/cadr-cli/interactive/transcript.lisp`) | AssistantMessageComponent hasToolCalls (`packages/coding-agent/src/modes/interactive/components/assistant-message.ts`) |

Leftover sibling of Pairs 517–519 on the same `transcript.lisp` hole. Timed work is empty / text / tool-call / text+tool / thinking-only. Observed `aht_empty` / `aht_text` / `aht_tool` / `aht_both` / `aht_think` are exact. First n=5 freeze **1.160×** (1.082 / 0.933 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 644 — `cli_interactive_controller` (assistant_display_blocks)

| metric | cadr | pi |
|---|---|---|
| `assistant_display_blocks` | `assistant-display-blocks` (`src/cadr-cli/interactive/transcript.lisp`) | assistant display block flatten (`packages/coding-agent/src/modes/interactive/components/assistant-message.ts`) |

Leftover sibling of Pair 643. Timed work is trim/drop blank text, merge consecutive thinking with a blank line, keep tail text (n / first / think / tail / blank-dropped). Observed `adb_n` / `adb_first` / `adb_think` / `adb_tail` / `adb_blank` are exact. First n=5 freeze **0.686×** (0.948 / 1.383 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce`. Same commit no optimize. `nextPairNum` left at 328.

### Pair 645 — `cli_interactive_controller` (transcript_summary_label)

| metric | cadr | pi |
|---|---|---|
| `transcript_summary_label` | `transcript-summary-label` (`src/cadr-cli/interactive/transcript.lisp`) | `[skill]` / `[branch]` / `[compaction]` label (`packages/coding-agent/src/modes/interactive/components/skill-invocation-message.ts`) |

Leftover sibling of Pairs 643–644. Timed work is themed `[name]` labels (skill / branch / empty / compaction) with ANSI stripped for observed. Observed `tsl_skill` / `tsl_branch` / `tsl_empty` / `tsl_n` / `tsl_comp` are exact. First n=5 freeze **6.352×** (12.217 / 1.923 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 646 — `cli_interactive_controller` (transcript_summary_text)

| metric | cadr | pi |
|---|---|---|
| `transcript_summary_text` | `transcript-summary-text` (`src/cadr-cli/interactive/transcript.lisp`) | `customMessageText` (`packages/coding-agent/src/modes/interactive/components/custom-message.ts`) |

Leftover sibling of Pairs 643–645 on the same `transcript.lisp` hole. Timed work is themed summary body text (hello / empty / CJK / spaced) with ANSI stripped for observed. Observed `tst_hi` / `tst_empty` / `tst_cjk` / `tst_n` / `tst_space` are exact. First n=5 freeze **5.434×** (8.866 / 1.632 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 647 — `cli_interactive_controller` (assistant_stop_error)

| metric | cadr | pi |
|---|---|---|
| `assistant_stop_error` | `assistant-stop-error-lines` (`src/cadr-cli/interactive/transcript.lisp`) | AssistantMessageComponent `stopReason` (`packages/coding-agent/src/modes/interactive/components/assistant-message.ts`) |

Leftover sibling of Pair 646. Timed work is length/aborted/error stop lines (truncated / Operation aborted / custom abort / tool-calls skip / Error: boom). Observed `ase_len` / `ase_abort` / `ase_custom` / `ase_tool` / `ase_err` are exact. First n=5 freeze **10.444×** (24.257 / 2.323 µs) on host `cursor`. First-freeze headroom ceiling **20.0** (ratchet down only). Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 648 — `cli_interactive_controller` (update_notification_border)

| metric | cadr | pi |
|---|---|---|
| `update_notification_border` | `update-notification-border-line` (`src/cadr-cli/interactive/transcript.lisp`) | warning `DynamicBorder` (`packages/coding-agent/src/modes/interactive/components/dynamic-border.ts`) |

Leftover sibling of Pairs 646–647. Timed work is warning-themed `─` border at widths 8 / 0 / 1 / 40 with ANSI stripped. Observed `unb_w` / `unb_ch` / `unb_0` / `unb_1` / `unb_n` are exact. First n=5 freeze **4.259×** (6.319 / 1.484 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 649 — `cli_interactive_controller` (theme_message_background)

| metric | cadr | pi |
|---|---|---|
| `theme_message_background` | `theme-message-background-lines` (`src/cadr-cli/interactive/transcript.lisp`) | `theme.bg` message background (`packages/coding-agent/src/modes/interactive/theme/theme.ts`) |

Leftover sibling of Pairs 646–648 on the same `transcript.lisp` hole. Timed work is per-line themed backgrounds (hello / empty / two-line keep / user-message token) with ANSI stripped. Observed `tmb_hi` / `tmb_empty` / `tmb_n` / `tmb_keep` / `tmb_tok` are exact. First n=5 freeze **5.465×** (8.586 / 1.571 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider`). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 650 — `cli_interactive_controller` (update_notification_text)

| metric | cadr | pi |
|---|---|---|
| `update_notification_text` | `update-notification-text-lines` (`src/cadr-cli/interactive/transcript.lisp`) | warning body text (`packages/coding-agent/src/modes/interactive/components/dynamic-border.ts`) |

Leftover sibling of Pair 649. Timed work is padded notification body lines (hello / empty / CJK / wrap). Observed `unt_hi` / `unt_empty` / `unt_cjk` / `unt_n` / `unt_pad` are exact. First n=5 freeze **29.104×** (59.152 / 2.032 µs) on host `cursor`. First-freeze headroom ceiling **50.0** (ratchet down only). Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 651 — `cli_interactive_controller` (syntax_highlight)

| metric | cadr | pi |
|---|---|---|
| `syntax_highlight` | `tui-syntax-highlight` (`src/cadr-cli/interactive/transcript.lisp`) | syntaxHighlight keyword/number (`packages/coding-agent/src/modes/interactive/theme/theme.ts`) |

Leftover sibling of Pairs 649–650. Timed work is unsupported-language passthrough, empty lisp, lisp keep `(+ 1 2)`, json `{}` with ANSI stripped. Observed `syn_plain` / `syn_empty` / `syn_keep` / `syn_n` / `syn_json` are exact. First n=5 freeze **12.184×** (13.174 / 1.081 µs) on host `cursor`. First-freeze headroom ceiling **20.0** (ratchet down only). Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 652 — `cli_interactive_controller` (assistant_price_known)

| metric | cadr | pi |
|---|---|---|
| `assistant_price_known` | `assistant-price-known-p` (`src/cadr-cli/interactive/transcript.lisp`) | `findModel` presence (`packages/agent/src/models.ts`) |

Leftover sibling of Pairs 649–651 on the same `transcript.lisp` hole. Timed work is catalog hit/miss (deepseek-v4-flash / unknown / gemini-3.6-flash / empty id / nil provider) via `ignore-errors` around `find-model-metadata`. Observed `apk_hit` / `apk_miss` / `apk_google` / `apk_empty` / `apk_nil` are exact. First n=5 freeze **0.240×** (4.477 / 18.674 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce`. Same commit no optimize. `nextPairNum` left at 328.

### Pair 653 — `cli_interactive_controller` (accumulate_usage)

| metric | cadr | pi |
|---|---|---|
| `accumulate_usage` | `accumulate-message-usage` (`src/cadr-cli/interactive/transcript.lisp`) | session usage accumulate (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover sibling of Pair 652. Timed work is input/output/cache token accumulate, cost-known on catalog hit, rounded cache-hit rate (10+2+1 prompt, 2/13). Observed `amu_in` / `amu_out` / `amu_cache` / `amu_known` / `amu_hit` are exact. First n=5 freeze **1.188×** (0.775 / 0.652 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 654 — `cli_interactive_controller` (append_user_message)

| metric | cadr | pi |
|---|---|---|
| `append_user_message` | `append-tui-user-message` (`src/cadr-cli/interactive/transcript.lisp`) | `parseSkillBlock` / UserMessageComponent (`packages/coding-agent/src/core/agent-session.ts`) |

Leftover sibling of Pairs 652–653. Timed work is plain user entry vs skill-invocation plus trailing user text. Observed `aum_user` / `aum_n` / `aum_skill` / `aum_both` / `aum_text` are exact. First n=5 freeze **4.205×** (5.050 / 1.201 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 655 — `cli_interactive_controller` (seed_tui_message)

| metric | cadr | pi |
|---|---|---|
| `seed_tui_message` | `seed-tui-message` (`src/cadr-cli/interactive/transcript.lisp`) | addChild user/assistant/bash (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover sibling of Pairs 652–654 on the same `transcript.lisp` hole. Timed work is seeding user `"hi"`, assistant `"ok"`, bash-execution `ls`/`ok`, and mixed user+assistant. Observed `stm_user` / `stm_n` / `stm_asst` / `stm_bash` / `stm_mix` are exact. First n=5 freeze **0.469×** (4.095 / 8.722 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce`. Same commit no optimize. `nextPairNum` left at 328.

### Pair 656 — `cli_interactive_controller` (reset_tui_messages)

| metric | cadr | pi |
|---|---|---|
| `reset_tui_messages` | `reset-tui-messages` (`src/cadr-cli/interactive/transcript.lisp`) | chatContainer reset + usage preserve (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover sibling of Pair 655. Timed work is replace-with-new user, drop usage, preserve input-tokens 7, zero tokens after filled reset, and context-unknown percent nil. Observed `rtm_n` / `rtm_drop` / `rtm_keep` / `rtm_zero` / `rtm_unk` are exact. First n=5 freeze **1.296×** (2.035 / 1.570 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 657 — `cli_interactive_controller` (render_user_lines)

| metric | cadr | pi |
|---|---|---|
| `render_user_lines` | `render-user-message-lines` (`src/cadr-cli/interactive/transcript.lisp`) | UserMessageComponent wrap + OSC 133 (`packages/coding-agent/src/modes/interactive/components/user-message.ts`) |

Leftover sibling of Pairs 655–656. Timed work is OSC 133 sandwich + wrap of padding+text (`hello` / empty / pad 1). Observed `rum_hi` / `rum_n` / `rum_osc` / `rum_pad` / `rum_empty` are exact. First n=5 freeze **2.567×** (3.956 / 1.541 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 658 — `cli_interactive_controller` (render_assistant_lines)

| metric | cadr | pi |
|---|---|---|
| `render_assistant_lines` | `render-assistant-message-lines` (`src/cadr-cli/interactive/transcript.lisp`) | AssistantMessageComponent wrap + OSC 133 (`packages/coding-agent/src/modes/interactive/components/assistant-message.ts`) |

Leftover sibling of Pairs 655–657 on the same `transcript.lisp` hole. Timed work is text wrap + OSC, hidden thinking (`Thinking...`), and length stop-reason truncation. Observed `ram_hi` / `ram_n` / `ram_osc` / `ram_think` / `ram_trunc` are exact. First n=5 freeze **2.730×** (12.279 / 4.498 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 659 — `cli_interactive_controller` (transform_tui_markdown)

| metric | cadr | pi |
|---|---|---|
| `transform_tui_markdown` | `transform-tui-markdown` (`src/cadr-cli/interactive/transcript.lisp`) | mermaid transform + markdown cache (`packages/coding-agent/src/modes/interactive/components/assistant-message.ts`) |

Leftover sibling of Pair 658. Timed work is nil-host mermaid passthrough, cache hit/miss (`:assistant` then `:other`), mermaid-mode `off`, and thinking skip. Observed `ttm_eq` / `ttm_n` / `ttm_off` / `ttm_think` / `ttm_hit` are exact. First n=5 freeze **1.485×** (2.923 / 1.968 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 660 — `cli_interactive_controller` (render_transcript_summary)

| metric | cadr | pi |
|---|---|---|
| `render_transcript_summary` | `render-transcript-summary-entry` (`src/cadr-cli/interactive/transcript.lisp`) | skill/branch/compaction CustomMessage (`packages/coding-agent/src/modes/interactive/components/skill-invocation-message.ts`) |

Leftover sibling of Pairs 658–659. Timed work is collapsed skill/branch/compaction box render. Observed `rts_skill` / `rts_foo` / `rts_branch` / `rts_comp` / `rts_n` are exact. First n=5 freeze **255.111×** (786.501 / 3.083 µs) on host `cursor`. First-freeze headroom ceiling **400.0** (ratchet down only). Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 661 — `cli_interactive_controller` (render_assistant_blocks)

| metric | cadr | pi |
|---|---|---|
| `render_assistant_blocks` | `render-assistant-blocks` (`src/cadr-cli/interactive/transcript.lisp`) | assistant markdown blocks + stop error (`packages/coding-agent/src/modes/interactive/components/assistant-message.ts`) |

Leftover sibling of Pairs 658–660 on the same `transcript.lisp` hole. Timed work is nil-host markdown blocks, empty text, stop-reason error lines, and hidden thinking label (`Thinking...`). Observed `rab_hi` / `rab_n` / `rab_empty` / `rab_err` / `rab_think` are exact. First n=5 freeze **5.377×** (54.605 / 10.156 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 662 — `cli_interactive_controller` (render_version_notification)

| metric | cadr | pi |
|---|---|---|
| `render_version_notification` | `render-version-update-notification` (`src/cadr-cli/interactive/transcript.lisp`) | version warning DynamicBorder (`packages/coding-agent/src/modes/interactive/components/dynamic-border.ts`) |

Leftover sibling of Pair 661. Timed work is the version-update warning box (`Update Available` / version text / Changelog). Observed does not exact-match the product slug (`cadr` vs `pi`). Observed `rvn_avail` / `rvn_ver` / `rvn_change` / `rvn_n` / `rvn_dash` are exact. First n=5 freeze **69.400×** (304.547 / 4.388 µs) on host `cursor`. First-freeze headroom ceiling **120.0** (ratchet down only). Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 663 — `cli_interactive_controller` (render_package_notification)

| metric | cadr | pi |
|---|---|---|
| `render_package_notification` | `render-package-update-notification` (`src/cadr-cli/interactive/transcript.lisp`) | package warning DynamicBorder (`packages/coding-agent/src/modes/interactive/components/dynamic-border.ts`) |

Leftover sibling of Pairs 661–662. Timed work is the package-update warning box (`Package Updates Available` / package names / `update`). Observed does not exact-match the product slug. Observed `rpn_avail` / `rpn_pkg` / `rpn_run` / `rpn_n` / `rpn_dash` are exact. First n=5 freeze **52.727×** (217.221 / 4.120 µs) on host `cursor`. First-freeze headroom ceiling **100.0** (ratchet down only). Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 664 — `cli_interactive_controller` (render_tui_entry_uncached)

| metric | cadr | pi |
|---|---|---|
| `render_tui_entry_uncached` | `render-tui-entry-uncached` (`src/cadr-cli/interactive/transcript.lisp`) | chat-log render entry uncached (`packages/coding-agent/src/modes/interactive/components/chat-log.ts`) |

Leftover sibling of Pairs 661–663 on the same `transcript.lisp` hole. Timed work is user/assistant/error/version-update entry paint plus unknown-type empty. Observed `rteu_user` / `rteu_asst` / `rteu_err` / `rteu_ver` / `rteu_empty` are exact. First n=5 freeze **27.525×** (200.288 / 7.276 µs) on host `cursor`. First-freeze headroom ceiling **50.0** (ratchet down only). Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 665 — `cli_interactive_controller` (render_tui_entry)

| metric | cadr | pi |
|---|---|---|
| `render_tui_entry` | `render-tui-entry` (`src/cadr-cli/interactive/transcript.lisp`) | chat-log render entry cache (`packages/coding-agent/src/modes/interactive/components/chat-log.ts`) |

Leftover sibling of Pair 664. Timed work is cacheable user paint plus second-call cache hit, error, and version-update. Observed `rte_user` / `rte_n` / `rte_hit` / `rte_err` / `rte_ver` are exact. First n=5 freeze **17.083×** (102.484 / 5.999 µs) on host `cursor`. First-freeze headroom ceiling **30.0** (ratchet down only). Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 666 — `cli_interactive_controller` (render_tui_entries)

| metric | cadr | pi |
|---|---|---|
| `render_tui_entries` | `render-tui-entries` (`src/cadr-cli/interactive/transcript.lisp`) | chat-log render entries + user gap (`packages/coding-agent/src/modes/interactive/components/chat-log.ts`) |

Leftover sibling of Pairs 664–665. Timed work is list paint of user+assistant, a user-user gap line, and empty list. Observed `rtes_user` / `rtes_asst` / `rtes_gap` / `rtes_n` / `rtes_empty` are exact. First n=5 freeze **5.530×** (42.711 / 7.723 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 667 — `cli_interactive_controller` (should_use_tui)

| metric | cadr | pi |
|---|---|---|
| `should_use_tui` | `should-use-tui-p` (`src/cadr-cli/interactive/controller.lisp`) | shouldUseTui stdin/stdout isTTY (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover sibling on the `controller.lisp` hole. Timed work is injected tty predicates (both / no-tui flag / input-only / output-only / none). Observed `sut_tty` / `sut_off` / `sut_in` / `sut_out` / `sut_none` are exact. First n=5 freeze **0.199×** (0.115 / 0.576 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce`. Same commit no optimize. `nextPairNum` left at 328.

### Pair 668 — `cli_interactive_controller` (tui_command_error)

| metric | cadr | pi |
|---|---|---|
| `tui_command_error` | `call-with-tui-command-error-notice` (`src/cadr-cli/interactive/controller.lisp`) | command error notice skip auth cancel (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover sibling of Pair 667. Timed work is success, `authentication-cancelled` skip, and generic error notice. Observed `tce_ok` / `tce_auth` / `tce_err` / `tce_n` / `tce_skip` are exact. First n=5 freeze **0.069×** (1.472 / 21.323 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce`. Same commit no optimize. `nextPairNum` left at 328.

### Pair 669 — `cli_interactive_controller` (route_tui_submission)

| metric | cadr | pi |
|---|---|---|
| `route_tui_submission` | `route-tui-submission` (`src/cadr-cli/interactive/controller.lisp`) | busy submit queue vs start (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover sibling of Pairs 667–668. Timed work is idle start, busy queue, and busy-without-callback. Observed `rsub_start` / `rsub_queue` / `rsub_busy` / `rsub_line` / `rsub_qline` are exact. First n=5 freeze **0.360×** (0.190 / 0.527 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce`. Same commit no optimize. `nextPairNum` left at 328.

### Pair 670 — `cli_interactive_controller` (extension_dialog_chrome)

| metric | cadr | pi |
|---|---|---|
| `extension_dialog_chrome` | `extension-dialog-chrome` (`src/cadr-cli/interactive/extension-ui.lisp`) | dialog chrome border (`packages/coding-agent/src/modes/interactive/components/extension-editor.ts`) |

Leftover sibling on the `extension-ui.lisp` hole. Timed work is title/body/footer chrome with selector border. Observed `edc_hi` / `edc_body` / `edc_sub` / `edc_n` / `edc_dash` are exact. First n=5 freeze **14.268×** (21.804 / 1.528 µs) on host `cursor`. First-freeze headroom ceiling **30.0** (ratchet down only). Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 671 — `cli_interactive_controller` (tui_component_protocol)

| metric | cadr | pi |
|---|---|---|
| `tui_component_protocol` | `tui-component-protocol-p` (`src/cadr-cli/interactive/extension-ui.lisp`) | Component protocol predicate (`packages/tui/src/tui.ts`) |

Leftover sibling of Pair 670. Timed work is nil/string negatives plus input/dialog/editor positives. Observed `tcp_nil` / `tcp_in` / `tcp_str` / `tcp_dlg` / `tcp_ed` are exact. First n=5 freeze **1.527×** (0.587 / 0.384 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 672 — `cli_interactive_controller` (extension_render_value_lines)

| metric | cadr | pi |
|---|---|---|
| `extension_render_value_lines` | `extension-render-value-lines` (`src/cadr-cli/interactive/extension-ui.lisp`) | custom value lines (`packages/coding-agent/src/modes/interactive/components/custom-message.ts`) |

Leftover sibling of Pairs 670–671. Timed work is nil/string/list wrap plus non-string skip. Observed `erv_nil` / `erv_hi` / `erv_list` / `erv_num` / `erv_n` are exact. First n=5 freeze **2.452×** (2.505 / 1.022 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 673 — `cli_interactive_controller` (make_framed_select_state)

| metric | cadr | pi |
|---|---|---|
| `make_framed_select_state` | `make-framed-select-state` (`src/cadr-cli/interactive/extension-ui.lisp`) | framed select-list constructor (`packages/tui/src/select-list.ts`) |

Leftover sibling on the `extension-ui.lisp` hole. Timed work is title/items plus timeout vs open deadline. Observed `mfs_title` / `mfs_n` / `mfs_a` / `mfs_dead` / `mfs_open` are exact. First n=5 freeze **1.037×** (0.903 / 0.870 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 674 — `cli_interactive_controller` (note_component_render_channel)

| metric | cadr | pi |
|---|---|---|
| `note_component_render_channel` | `note-component-render-channel` (`src/cadr-cli/interactive/extension-ui.lisp`) | requestRender inject on render-aware mixin (`packages/tui/src/tui.ts`) |

Leftover sibling of Pair 673. Timed work is nil skip, render-aware inject, and plain dialog pass-through. Observed `ncr_nil` / `ncr_eq` / `ncr_set` / `ncr_plain` / `ncr_ret` are exact. First n=5 freeze **1.278×** (0.357 / 0.279 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 675 — `cli_interactive_controller` (tui_extension_theme_runtime)

| metric | cadr | pi |
|---|---|---|
| `tui_extension_theme_runtime` | `tui-extension-theme-runtime` (`src/cadr-cli/interactive/extension-ui.lisp`) | theme fg/bg/bold/italic runtime (`packages/tui/src/theme.ts`) |

Leftover sibling of Pairs 673–674. Timed work is functionp slots plus stripped accent text contains `hi`. Observed `tet_fg` / `tet_bg` / `tet_bold` / `tet_italic` / `tet_hi` are exact. Do not exact-match ANSI or product slug. First n=5 freeze **3.379×** (1.449 / 0.429 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 676 — `cli_interactive_controller` (make_extension_input_dialog)

| metric | cadr | pi |
|---|---|---|
| `make_extension_input_dialog` | `make-extension-input-dialog` (`src/cadr-cli/interactive/extension-ui.lisp`) | input dialog constructor (`packages/coding-agent/src/modes/interactive/components/extension-editor.ts`) |

Leftover sibling on the `extension-ui.lisp` hole. Timed work is title, protocol-p, single-line input prompt, and empty-title protocol. Observed `eid_t` / `eid_proto` / `eid_in` / `eid_pr` / `eid_empty` are exact. First n=5 freeze **1.099×** (0.496 / 0.451 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 677 — `cli_interactive_controller` (make_extension_editor_dialog)

| metric | cadr | pi |
|---|---|---|
| `make_extension_editor_dialog` | `make-extension-editor-dialog` (`src/cadr-cli/interactive/extension-ui.lisp`) | editor dialog constructor (`packages/coding-agent/src/modes/interactive/components/extension-editor.ts`) |

Leftover sibling of Pair 676. Timed work is title, prefill text, nil prefill empty, protocol-p, and multiline editor type. Observed `eed_t` / `eed_hi` / `eed_empty` / `eed_proto` / `eed_ed` are exact. First n=5 freeze **4.545×** (1.648 / 0.363 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 678 — `cli_interactive_controller` (make_runtime_auth_input_state)

| metric | cadr | pi |
|---|---|---|
| `make_runtime_auth_input_state` | `make-runtime-auth-input-state` (`src/cadr-cli/interactive/extension-ui.lisp`) | runtime auth input constructor (`packages/coding-agent/src/modes/interactive/components/auth-input.ts`) |

Leftover sibling of Pairs 676–677. Timed work is prompt copy, type slot, input prompt, and nil prompt. Do not exact-match redacted print. Observed `rai_type` / `rai_copy` / `rai_in` / `rai_pr` / `rai_nil` are exact. First n=5 freeze **1.042×** (0.459 / 0.441 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 679 — `cli_interactive_controller` (runtime_auth_input_handle_event)

| metric | cadr | pi |
|---|---|---|
| `runtime_auth_input_handle_event` | `runtime-auth-input-state-handle-event` (`src/cadr-cli/interactive/extension-ui.lisp`) | oauth runtime auth `handleEvent` (`packages/coding-agent/src/modes/interactive/components/oauth.ts`) |

Leftover sibling of Pair 678 on the `extension-ui.lisp` hole. Timed work is escape/interrupt cancel, cancel-function once, enter→select with value, and text nop. Observed `rah_esc` / `rah_int` / `rah_fn` / `rah_sel` / `rah_nop` are exact. First n=5 freeze **1.135×** (1.040 / 0.916 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 680 — `cli_interactive_controller` (render_runtime_auth_input)

| metric | cadr | pi |
|---|---|---|
| `render_runtime_auth_input` | `render-runtime-auth-input-state` (`src/cadr-cli/interactive/extension-ui.lisp`) | oauth runtime auth render (`packages/coding-agent/src/modes/interactive/components/oauth.ts`) |

Leftover sibling of Pair 679. Timed work is simple (non-`manual-code`) message render plus secret masking. Do not exact-match ANSI, hints, or product slug. Observed `rra_hi` / `rra_dash` / `rra_n` / `rra_msg` / `rra_star` are exact. First n=5 freeze **56.286×** (143.679 / 2.553 µs) on host `cursor`, ceiling 100.0 (first-freeze headroom; ratchet down only). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 681 — `cli_interactive_controller` (render_extension_custom_entry)

| metric | cadr | pi |
|---|---|---|
| `render_extension_custom_entry` | `render-extension-custom-entry` (`src/cadr-cli/interactive/extension-ui.lisp`) | custom entry render nil host (`packages/coding-agent/src/modes/interactive/components/custom-message.ts`) |

Leftover sibling of Pairs 679–680. Timed work is nil host → nil at widths 80/1 plus custom-message. Observed `rec_nil` / `rec_w` / `rec_again` / `rec_type` / `rec_msg` are exact. First n=5 freeze **2.800×** (0.434 / 0.155 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 682 — `cli_interactive_controller` (render_framed_select_state)

| metric | cadr | pi |
|---|---|---|
| `render_framed_select_state` | `render-framed-select-state` (`src/cadr-cli/interactive/extension-ui.lisp`) | framed select-list render (`packages/tui/src/select-list.ts`) |

Leftover sibling of Pair 673 on the `extension-ui.lisp` hole. Timed work is title/labels/border/hint render. Do not exact-match ANSI or keybinding copy beyond `navigate`. Observed `rfs_pick` / `rfs_dash` / `rfs_n` / `rfs_a` / `rfs_nav` are exact. First n=5 freeze **101.599×** (230.310 / 2.267 µs) on host `cursor`, ceiling 180.0 (first-freeze headroom; ratchet down only). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 683 — `cli_interactive_controller` (framed_select_state_handle_event)

| metric | cadr | pi |
|---|---|---|
| `framed_select_state_handle_event` | `framed-select-state-handle-event` (`src/cadr-cli/interactive/extension-ui.lisp`) | framed select-list handleEvent (`packages/tui/src/select-list.ts`) |

Leftover sibling of Pair 682. Timed work is escape cancel, enter select, down `:changed`, toggle-tools once, and left nop. Observed `fsh_esc` / `fsh_sel` / `fsh_down` / `fsh_fn` / `fsh_nop` are exact. First n=5 freeze **1.252×** (1.259 / 1.006 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 684 — `cli_interactive_controller` (framed_select_state_handle_raw_input)

| metric | cadr | pi |
|---|---|---|
| `framed_select_state_handle_raw_input` | `framed-select-state-handle-raw-input` (`src/cadr-cli/interactive/extension-ui.lisp`) | framed select-list handleRawInput (`packages/tui/src/select-list.ts`) |

Leftover sibling of Pairs 682–683. Timed work is `j`/`k` consumed and `x`/`z` not consumed. Observed `fsr_j` / `fsr_k` / `fsr_x` / `fsr_z` / `fsr_again` are exact. First n=5 freeze **91.669×** (87.360 / 0.953 µs) on host `cursor`, ceiling 160.0 (first-freeze headroom; ratchet down only). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 685 — `cli_interactive_controller` (render_extension_custom_ui)

| metric | cadr | pi |
|---|---|---|
| `render_extension_custom_ui` | `render-extension-custom-ui` (`src/cadr-cli/interactive/extension-ui.lisp`) | custom ui render (`packages/coding-agent/src/modes/interactive/components/custom-message.ts`) |

Leftover sibling on the `extension-ui.lisp` hole. Timed work is string/list/nil component render plus input-dialog protocol path. Do not exact-match ANSI. Observed `rcu_hi` / `rcu_nil` / `rcu_aa` / `rcu_n` / `rcu_dlg` are exact. First n=5 freeze **22.775×** (32.260 / 1.416 µs) on host `cursor`, ceiling 40.0 (first-freeze headroom; ratchet down only). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 686 — `cli_interactive_controller` (extension_custom_ui_handle_event)

| metric | cadr | pi |
|---|---|---|
| `extension_custom_ui_handle_event` | `extension-custom-ui-handle-event` (`src/cadr-cli/interactive/extension-ui.lisp`) | custom ui handleEvent (`packages/coding-agent/src/modes/interactive/components/custom-message.ts`) |

Leftover sibling of Pair 685. Timed work is string-component escape cancel, enter select, left nop, and text nop. Observed `ecu_esc` / `ecu_sel` / `ecu_val` / `ecu_nop` / `ecu_txt` are exact. First n=5 freeze **0.421×** (0.344 / 0.818 µs) on host `cursor`, ceiling 8.0. cadr leads; not booked over-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 687 — `cli_interactive_controller` (render_tui_extension_overlay)

| metric | cadr | pi |
|---|---|---|
| `render_tui_extension_overlay` | `render-tui-extension-overlay` (`src/cadr-cli/interactive/extension-ui.lisp`) | extension overlay composite (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |

Leftover sibling of Pairs 685–686. Timed work is hidden overlay (`:visible nil`) plus visible Hello composite. Do not exact-match ANSI or full-screen geometry. Observed `rto_hid` / `rto_hi` / `rto_n` / `rto_vn` / `rto_row` are exact. First n=5 freeze **88.995×** (144.970 / 1.629 µs) on host `cursor`, ceiling 160.0 (first-freeze headroom; ratchet down only). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 688 — `find_tool` (glob_scanner)

| metric | cadr | pi |
|---|---|---|
| `glob_scanner` | `glob-scanner` (`src/cadr-cli/tools/glob.lisp`) | glob scanner compile+test (`packages/coding-agent/src/core/tools/find.ts`) |

Leftover sibling of Pairs 448–450 on the same `glob.lisp` `find_tool` hole. Timed work is compile+test of `*` / `**` / `?` / `.a` scanners. Observed `gsc_star` / `gsc_miss` / `gsc_glob` / `gsc_q` / `gsc_dot` are exact. First n=5 freeze **11.176×** (10.624 / 0.951 µs) on host `cursor`, ceiling 20.0 (first-freeze headroom; ratchet down only). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 689 — `find_tool` (glob_regex_body)

| metric | cadr | pi |
|---|---|---|
| `glob_regex_body` | `glob-regex-body` (`src/cadr-cli/tools/glob.lisp`) | glob regex body (`packages/coding-agent/src/core/tools/find.ts`) |

Leftover sibling of Pair 688. Timed work is stripping `^`/`$` from glob regex source for `*` / `**` / `?` / `.a`. Observed `grb_star` / `grb_glob` / `grb_q` / `grb_dot` are exact. First n=5 freeze **1.393×** (0.580 / 0.417 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 690 — `find_tool` (parse_gitignore_line)

| metric | cadr | pi |
|---|---|---|
| `parse_gitignore_line` | `parse-gitignore-line` (`src/cadr-cli/tools/glob.lisp`) | gitignore line parse (`packages/coding-agent/src/core/tools/find.ts`) |

Leftover sibling of Pairs 688–689. Timed work is empty/`#` skip, `foo` rule, `!foo` negation, and scanner construction. Observed `pgl_empty` / `pgl_hash` / `pgl_foo` / `pgl_bang` / `pgl_scan` are exact. First n=5 freeze **5.556×** (7.267 / 1.308 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 691 — `find_tool` (ignored_directory)

| metric | cadr | pi |
|---|---|---|
| `ignored_directory` | `ignored-directory-p` (`src/cadr-cli/tools/glob.lisp`) | ignored directory names (`packages/coding-agent/src/core/tools/find.ts`) |

Leftover sibling of Pairs 688–690 on the same `glob.lisp` `find_tool` hole. Timed work is `.git` / `node_modules` / `src` / `.github` / trailing-slash `.git/` last-component checks. Observed `igd_git` / `igd_nm` / `igd_src` / `igd_hub` / `igd_slash` are exact. First n=5 freeze **8.621×** (16.582 / 1.923 µs) on host `cursor`, ceiling 16.0 (first-freeze headroom; ratchet down only). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 692 — `find_tool` (gitignored)

| metric | cadr | pi |
|---|---|---|
| `gitignored` | `gitignored-p` (`src/cadr-cli/tools/glob.lisp`) | gitignore rule apply (`packages/coding-agent/src/core/tools/find.ts`) |

Leftover sibling of Pair 691. Timed work is empty rules, `foo` hit, `bar` miss, `!foo` re-include, and a path outside the rule base. Observed `gig_empty` / `gig_hit` / `gig_miss` / `gig_bang` / `gig_out` are exact. First n=5 freeze **10.286×** (37.755 / 3.671 µs) on host `cursor`, ceiling 20.0 (first-freeze headroom; ratchet down only). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 693 — `find_tool` (make_glob_tool)

| metric | cadr | pi |
|---|---|---|
| `make_glob_tool` | `make-glob-tool` (`src/cadr-cli/tools/glob.lisp`) | glob tool constructor (`packages/coding-agent/src/core/tools/find.ts`) |

Leftover sibling of Pairs 691–692. Timed work is constructing the glob tool (name / description / required `pattern` / `:parallel`). Observed `mgt_name` / `mgt_desc` / `mgt_req` / `mgt_par` / `mgt_n` are exact. First n=5 freeze **701.525×** (193.915 / 0.276 µs) on host `cursor`, ceiling 1200.0 (first-freeze headroom; ratchet down only). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 694 — `bash_tool` (process_deadline)

| metric | cadr | pi |
|---|---|---|
| `process_deadline` | `process-deadline` (`src/cadr-cli/tools/bash.lisp`) | timeout deadline (`packages/coding-agent/src/core/tools/bash.ts`) |

Leftover sibling of earlier `bash_tool` leftovers on `src/cadr-cli/tools/bash.lisp`. Timed work is nil timeout, integer deadline, 1s vs 2s ordering, and zero timeout. Observed `pd_nil` / `pd_int` / `pd_ord` / `pd_zero` are exact. First n=5 freeze **0.272×** (0.124 / 0.457 µs) on host `cursor`, ceiling 8.0. cadr leads. Same commit no optimize. `nextPairNum` left at 328.

### Pair 695 — `bash_tool` (user_bash_result)

| metric | cadr | pi |
|---|---|---|
| `user_bash_result` | `make-user-bash-result-from-execution` (`src/cadr-cli/tools/bash.lisp`) | user bash result from execution (`packages/coding-agent/src/core/tools/bash.ts`) |

Leftover sibling of Pair 694. Timed work is command/output, exit-footer strip, empty content, cancelled+exclude, and truncation-footer strip. Observed `ubr_cmd` / `ubr_out` / `ubr_exit` / `ubr_can` / `ubr_ex` are exact. First n=5 freeze **2.070×** (2.616 / 1.264 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 696 — `bash_tool` (normalized_extension)

| metric | cadr | pi |
|---|---|---|
| `normalized_extension` | `normalized-extension-bash-result` (`src/cadr-cli/tools/bash.lisp`) | extension bash result normalize (`packages/coding-agent/src/core/tools/bash.ts`) |

Leftover sibling of Pairs 694–695. Timed work is output+exit footer, empty output, exit code, cancelled flag, and full-output path. Observed `neb_text` / `neb_nl` / `neb_code` / `neb_can` / `neb_path` are exact. First n=5 freeze **1.812×** (0.840 / 0.464 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 697 — `evals_harness` (canonical_api)

| metric | cadr | pi |
|---|---|---|
| `canonical_api` | `source-uses-canonical-extension-api-p` (`src/cadr-evals/suites.lisp`) | canonical extension API probe (`packages/evals/src/suites.ts`) |

Leftover sibling of earlier `evals_harness` leftovers on `src/cadr-evals/suites.lisp`. Timed work is `(define-tool`, packaged `define-tool`, case-insensitive `DEFINE-TOOL`, miss on `hello`, and miss on `@mariozechner/pi`. Observed `sca_def` / `sca_pkg` / `sca_case` / `sca_miss` / `sca_leg` are exact. First n=5 freeze **1.842×** (0.944 / 0.512 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 698 — `evals_harness` (legacy_api)

| metric | cadr | pi |
|---|---|---|
| `legacy_api` | `source-uses-legacy-extension-api-p` (`src/cadr-evals/suites.lisp`) | legacy extension API probe (`packages/evals/src/suites.ts`) |

Leftover sibling of Pair 697. Timed work is `@mariozechner/`, `@sinclair/typebox`, `@earendil-works/pi-coding-agent`, case-insensitive `@MarioZechner/`, and miss on `(define-tool`. Observed `sla_mz` / `sla_tb` / `sla_pi` / `sla_case` / `sla_miss` are exact. First n=5 freeze **3.666×** (1.903 / 0.519 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 699 — `evals_harness` (extension_error_json)

| metric | cadr | pi |
|---|---|---|
| `extension_error_json` | `extension-error-json` (`src/cadr-evals/suites.lisp`) | extension error JSON (`packages/evals/src/suites.ts`) |

Leftover sibling of Pairs 697–698. Timed work is path, error text, empty path/error, blank strings, and hash-table count. Observed `see_path` / `see_err` / `see_empty` / `see_blank` / `see_n` are exact. First n=5 freeze **4.784×** (0.860 / 0.180 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 700 — `evals_harness` (required_prompt_boundary)

| metric | cadr | pi |
|---|---|---|
| `required_prompt_boundary` | `required-prompt-boundary` (`src/cadr-evals/suites.lisp`) | required prompt boundary (`packages/evals/src/suites.ts`) |

Leftover sibling of Pairs 697–699 on `src/cadr-evals/suites.lisp`. Timed work is mid-string marker, from-end last marker, zero offset, missing-marker error, and observation count. Observed `rpb_mid` / `rpb_end` / `rpb_zero` / `rpb_miss` / `rpb_n` are exact. First n=5 freeze **0.397×** (0.852 / 2.148 µs) on host `cursor`, ceiling 8.0. cadr leads. Same commit no optimize. `nextPairNum` left at 328.

### Pair 701 — `evals_harness` (exclude_guidelines)

| metric | cadr | pi |
|---|---|---|
| `exclude_guidelines` | `exclude-guidelines-and-documentation` (`src/cadr-evals/suites.lisp`) | exclude Guidelines section (`packages/evals/src/suites.ts`) |

Leftover sibling of Pair 700. Timed work is prefix cut, length, Guidelines absence, and HEAD keep. Observed `egd_cut` / `egd_len` / `egd_no_g` / `egd_head` / `egd_n` are exact. First n=5 freeze **3.757×** (0.742 / 0.197 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 702 — `evals_harness` (prepare_default_prompt)

| metric | cadr | pi |
|---|---|---|
| `prepare_default_prompt` | `prepare-default-prompt-override` (`src/cadr-evals/suites.lisp`) | prepare default prompt override (`packages/evals/src/suites.ts`) |

Leftover sibling of Pairs 700–701. Timed work is cwd cut, last-of-two cwd markers, cwd absence in the cut, and Guidelines keep. Observed `pdp_cut` / `pdp_dbl` / `pdp_no_cwd` / `pdp_keep` / `pdp_n` are exact. First n=5 freeze **6.700×** (2.797 / 0.417 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 703 — `evals_harness` (reporter_run_id)

| metric | cadr | pi |
|---|---|---|
| `reporter_run_id` | `reporter-run-id` (`src/cadr-evals/reporter.lisp`) | artifact runId (`packages/evals/src/vitest-evals/reporter.ts`) |

Leftover sibling of earlier `evals_harness` leftovers on `src/cadr-evals/reporter.lisp`. Timed work is present runId, empty string, custom id, and generated id when missing (stringp / length only). Observed `rid_hit` / `rid_empty` / `rid_custom` / `rid_gen` / `rid_n` are exact. First n=5 freeze **2.941×** (2.621 / 0.891 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 704 — `evals_harness` (artifact_reference_json)

| metric | cadr | pi |
|---|---|---|
| `artifact_reference_json` | `artifact-reference-json` (`src/cadr-evals/reporter.lisp`) | persist name/path (`packages/evals/src/vitest-evals/artifacts.ts`) |

Leftover sibling of Pair 703. Timed work is name, path, empty strings, and key count. Observed `arj_name` / `arj_path` / `arj_empty` / `arj_keys` / `arj_n` are exact. First n=5 freeze **5.883×** (0.913 / 0.155 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 705 — `evals_harness` (reporter_artifacts)

| metric | cadr | pi |
|---|---|---|
| `reporter_artifacts` | `reporter-artifacts` (`src/cadr-evals/reporter.lisp`) | test.artifacts assemble (`packages/evals/src/vitest-evals/reporter.ts`) |

Leftover sibling of Pairs 703–704. Timed work is empty assemble, session snapshot artifact, recorded artifact keep, and case artifact keep. Observed `ra_empty` / `ra_sess` / `ra_rec` / `ra_case` / `ra_n` are exact. First n=5 freeze **0.927×** (1.620 / 1.747 µs) on host `cursor`, ceiling 8.0. cadr leads. Same commit no optimize. `nextPairNum` left at 328.

### Pair 706 — `package_manager` (resource_file_p)

| metric | cadr | pi |
|---|---|---|
| `resource_file_p` | `config-resource-file-p` (`src/cadr-cli/packages/config-selector.lisp`) | resource file match (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of earlier `package_manager` leftovers on `src/cadr-cli/packages/config-selector.lisp`. Timed work is lisp extension, case-insensitive type, miss, and SKILL.md basename. Observed `rfp_lisp` / `rfp_case` / `rfp_miss` / `rfp_skill` / `rfp_n` are exact. First n=5 freeze **6.124×** (10.973 / 1.792 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 707 — `package_manager` (resource_display_name)

| metric | cadr | pi |
|---|---|---|
| `resource_display_name` | `config-resource-display-name` (`src/cadr-cli/packages/config-selector.lisp`) | resource display name (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pair 706. Timed work is SKILL.md parent directory, lisp filename, markdown filename, and json filename. Observed `rdn_skill` / `rdn_lisp` / `rdn_md` / `rdn_json` / `rdn_n` are exact. First n=5 freeze **33.631×** (15.082 / 0.448 µs) on host `cursor`, ceiling 60.0 (first-freeze headroom; ratchet down only). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 708 — `package_manager` (settings_array)

| metric | cadr | pi |
|---|---|---|
| `settings_array` | `config-settings-array` (`src/cadr-cli/packages/config-selector.lisp`) | settings array coerce (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pairs 706–707. Timed work is vector coerce, list copy, missing key, and non-sequence. Observed `csa_vec` / `csa_list` / `csa_miss` / `csa_bad` / `csa_n` are exact. First n=5 freeze **2.393×** (1.161 / 0.485 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 709 — `package_manager` (resource_specification)

| metric | cadr | pi |
|---|---|---|
| `resource_specification` | `config-resource-specification` (`src/cadr-cli/packages/config-selector.lisp`) | RESOURCE_TYPES lookup (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of leftover 706–708 on `src/cadr-cli/packages/config-selector.lisp`. Timed work is extensions extension, skills basename, relative directory, and unknown-type error. Observed `rsp_ext` / `rsp_sk` / `rsp_rel` / `rsp_miss` / `rsp_n` are exact. First n=5 freeze **0.190×** (0.428 / 2.249 µs) on host `cursor`, ceiling 8.0. cadr leads. Not booked over-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 710 — `package_manager` (config_glob_regex)

| metric | cadr | pi |
|---|---|---|
| `config_glob_regex` | `config-glob-regex` (`src/cadr-cli/packages/config-selector.lisp`) | globToRegex (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pair 709. Timed work is star, question, plain, and `./` prefix. Observed `cgr_star` / `cgr_q` / `cgr_plain` / `cgr_dot` / `cgr_n` are exact. First n=5 freeze **0.546×** (0.900 / 1.648 µs) on host `cursor`, ceiling 8.0. cadr leads. Not booked over-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 711 — `package_manager` (entry_target)

| metric | cadr | pi |
|---|---|---|
| `entry_target` | `config-selector-entry-target` (`src/cadr-cli/packages/config-selector.lisp`) | entry target strip (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pairs 709–710. Timed work is `!` / `+` / `-` prefixes, plain, and empty. Observed `cet_bang` / `cet_plus` / `cet_minus` / `cet_plain` / `cet_empty` / `cet_n` are exact. First n=5 freeze **0.893×** (0.277 / 0.310 µs) on host `cursor`, ceiling 8.0. cadr leads. Not booked over-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 712 — `package_manager` (autoload_disabled)

| metric | cadr | pi |
|---|---|---|
| `autoload_disabled` | `config-package-entry-autoload-disabled-p` (`src/cadr-cli/packages/config-selector.lisp`) | package autoload disabled (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of leftover 709–711 on `src/cadr-cli/packages/config-selector.lisp`. Timed work is autoload nil, autoload true, missing key, and non-table. Observed `ad_nil` / `ad_true` / `ad_miss` / `ad_notht` / `ad_n` are exact. First n=5 freeze **2.181×** (0.758 / 0.347 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 713 — `package_manager` (package_entry_filter)

| metric | cadr | pi |
|---|---|---|
| `package_entry_filter` | `config-package-entry-filter` (`src/cadr-cli/packages/config-selector.lisp`) | package entry filter (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pair 712. Timed work is vector coerce, list copy, missing key, and non-sequence. Observed `pef_vec` / `pef_list` / `pef_miss` / `pef_bad` / `pef_n` are exact. First n=5 freeze **1.788×** (1.074 / 0.600 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 714 — `package_manager` (item_matches)

| metric | cadr | pi |
|---|---|---|
| `item_matches` | `config-selector-item-matches-p` (`src/cadr-cli/packages/config-selector.lisp`) | item query match (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pairs 712–713. Timed work is empty query, display name, path, type symbol, and miss. Observed `im_empty` / `im_name` / `im_path` / `im_type` / `im_miss` / `im_n` are exact. First n=5 freeze **11.092×** (10.553 / 0.951 µs) on host `cursor`, ceiling 20.0 (first-freeze headroom; ratchet down only). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 715 — `package_manager` (resource_key)

| metric | cadr | pi |
|---|---|---|
| `resource_key` | `config-selector-resource-key` (`src/cadr-cli/packages/config-selector.lisp`) | resource type key (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of leftover 712–714 on `src/cadr-cli/packages/config-selector.lisp`. Timed work is extensions, skills, prompts, and themes type keys. Observed `crk_ext` / `crk_sk` / `crk_pr` / `crk_th` / `crk_n` are exact. First n=5 freeze **11.643×** (2.758 / 0.237 µs) on host `cursor`, ceiling 20.0 (first-freeze headroom; ratchet down only). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 716 — `package_manager` (relative_pattern)

| metric | cadr | pi |
|---|---|---|
| `relative_pattern` | `config-selector-relative-pattern` (`src/cadr-cli/packages/config-selector.lisp`) | relative pattern (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pair 715. Timed work is file, nested skill path, extensions path, and bare name. Observed `rel_file` / `rel_nested` / `rel_ext` / `rel_plain` / `rel_n` are exact. First n=5 freeze **17.574×** (15.709 / 0.894 µs) on host `cursor`, ceiling 30.0 (first-freeze headroom; ratchet down only). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 717 — `package_manager` (config_fit_line)

| metric | cadr | pi |
|---|---|---|
| `config_fit_line` | `config-selector-fit-line` (`src/cadr-cli/packages/config-selector.lisp`) | truncateToWidth (`packages/tui/src/utils.ts`) |

Leftover sibling of Pairs 715–716. Timed work is short fit, overflow with empty ellipsis (CSI reset), overflow with `...`, and zero width. Observed `cfl_short` / `cfl_long` / `cfl_dots` / `cfl_zero` / `cfl_n` are exact. First n=5 freeze **2.793×** (5.200 / 1.862 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 718 — `package_manager` (group_less_p)

| metric | cadr | pi |
|---|---|---|
| `group_less_p` | `config-resource-group-less-p` (`src/cadr-cli/packages/config-selector.lisp`) | group sort (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of leftover 715–717 on `src/cadr-cli/packages/config-selector.lisp`. Timed work is package-before-top-level, user-before-project, source order, and reverse source. Observed `gl_pkg` / `gl_user` / `gl_src` / `gl_rev` / `gl_n` are exact. First n=5 freeze **7.128×** (3.937 / 0.552 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 719 — `package_manager` (package_entry_has_filters)

| metric | cadr | pi |
|---|---|---|
| `package_entry_has_filters` | `config-selector-package-entry-has-filters-p` (`src/cadr-cli/packages/config-selector.lisp`) | package entry filters (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pair 718. Timed work is extensions key, missing, skills key, and unrelated key. Observed `hf_ext` / `hf_miss` / `hf_sk` / `hf_other` / `hf_n` are exact. First n=5 freeze **1.804×** (1.379 / 0.765 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 720 — `package_manager` (find_item_index)

| metric | cadr | pi |
|---|---|---|
| `find_item_index` | `config-selector-find-item-index` (`src/cadr-cli/packages/config-selector.lisp`) | find item index (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pairs 718–719. Timed work is forward, skip subgroup, backward, and end stay. Observed `fi_fwd` / `fi_skip` / `fi_back` / `fi_end` / `fi_n` are exact. First n=5 freeze **0.569×** (0.242 / 0.426 µs) on host `cursor`, ceiling 8.0. cadr leads. Not booked over-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 721 — `package_manager` (selected_entry)

| metric | cadr | pi |
|---|---|---|
| `selected_entry` | `config-selector-selected-entry` (`src/cadr-cli/packages/config-selector.lisp`) | selected entry (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of leftover 718–720 on `src/cadr-cli/packages/config-selector.lisp`. Timed work is selected item, group, subgroup, and last item kind codes. Observed `se_item` / `se_group` / `se_sub` / `se_last` / `se_n` are exact. First n=5 freeze **1.195×** (0.968 / 0.810 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 722 — `package_manager` (selector_move)

| metric | cadr | pi |
|---|---|---|
| `selector_move` | `config-selector-move` (`src/cadr-cli/packages/config-selector.lisp`) | selector move (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pair 721. Timed work is forward, skip subgroup, backward, and end stay. Observed `sm_fwd` / `sm_skip` / `sm_back` / `sm_end` / `sm_n` are exact. First n=5 freeze **0.896×** (1.069 / 1.193 µs) on host `cursor`, ceiling 8.0. cadr leads. Not booked over-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 723 — `package_manager` (visible_range)

| metric | cadr | pi |
|---|---|---|
| `visible_range` | `config-selector-visible-range` (`src/cadr-cli/packages/config-selector.lisp`) | visible range (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pairs 721–722. Timed work is small list, mid window, top clamp, and bottom clamp. Observed `vr_small` / `vr_mid` / `vr_top` / `vr_bot` / `vr_n` are exact. First n=5 freeze **0.542×** (1.898 / 3.504 µs) on host `cursor`, ceiling 8.0. cadr leads. Not booked over-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 724 — `package_manager` (item_ordinal)

| metric | cadr | pi |
|---|---|---|
| `item_ordinal` | `config-selector-item-ordinal` (`src/cadr-cli/packages/config-selector.lisp`) | item ordinal (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of leftover 721–723 on `src/cadr-cli/packages/config-selector.lisp`. Timed work is group, first item, second item, and subgroup ordinals. Observed `io_group` / `io_first` / `io_second` / `io_sub` / `io_n` are exact. First n=5 freeze **0.835×** (1.077 / 1.289 µs) on host `cursor`, ceiling 8.0. cadr leads. Not booked over-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 725 — `package_manager` (replace_pattern)

| metric | cadr | pi |
|---|---|---|
| `replace_pattern` | `config-selector-replace-pattern` (`src/cadr-cli/packages/config-selector.lisp`) | replace pattern (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pair 724. Timed work is drop bang target, load prefix, unload prefix, and keep source pattern. Observed `rp_drop` / `rp_load` / `rp_unload` / `rp_keep` / `rp_n` are exact. First n=5 freeze **0.716×** (0.629 / 0.879 µs) on host `cursor`, ceiling 8.0. cadr leads. Not booked over-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 726 — `package_manager` (scope_base)

| metric | cadr | pi |
|---|---|---|
| `scope_base` | `config-selector-scope-base` (`src/cadr-cli/packages/config-selector.lisp`) | scope base (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pairs 724–725. Timed work is global agent directory, project `.cadr/` join, nested cwd, and trailing slash. Observed `sb_global` / `sb_proj` / `sb_nested` / `sb_slash` / `sb_n` are exact. First n=5 freeze **30.489×** (16.512 / 0.542 µs) on host `cursor`, ceiling 50.0 (first-freeze headroom). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 727 — `package_manager` (selector_items)

| metric | cadr | pi |
|---|---|---|
| `selector_items` | `config-selector-items` (`src/cadr-cli/packages/config-selector.lisp`) | selector items (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of leftover 724–726 on `src/cadr-cli/packages/config-selector.lisp`. Timed work is global list, project list, empty global, and copy independence. Observed `si_global` / `si_proj` / `si_empty` / `si_copy` / `si_n` are exact. First n=5 freeze **22.378×** (10.768 / 0.481 µs) on host `cursor`, ceiling 40.0 (first-freeze headroom). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 728 — `package_manager` (item_source_base)

| metric | cadr | pi |
|---|---|---|
| `item_source_base` | `config-selector-item-source-base` (`src/cadr-cli/packages/config-selector.lisp`) | item source base (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pair 727. Timed work is global item, project item, user item, and project-vs-global difference. Observed `isb_global` / `isb_proj` / `isb_user` / `isb_diff` / `isb_n` are exact. First n=5 freeze **28.506×** (16.439 / 0.577 µs) on host `cursor`, ceiling 50.0 (first-freeze headroom). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 729 — `package_manager` (package_resource_pattern)

| metric | cadr | pi |
|---|---|---|
| `package_resource_pattern` | `config-selector-package-resource-pattern` (`src/cadr-cli/packages/config-selector.lisp`) | package resource pattern (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pairs 727–728. Timed work is file, nested skill path, extensions path, and bare name. Observed `prp_file` / `prp_nested` / `prp_ext` / `prp_plain` / `prp_n` are exact. First n=5 freeze **13.804×** (15.247 / 1.105 µs) on host `cursor`, ceiling 20.0 (first-freeze headroom). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 730 — `package_manager` (package_override_source)

| metric | cadr | pi |
|---|---|---|
| `package_override_source` | `config-selector-package-override-source` (`src/cadr-cli/packages/config-selector.lisp`) | package override source (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of leftover 727–729 on `src/cadr-cli/packages/config-selector.lisp`. Timed work is npm source as-is, local nested `enough-namestring`, same-directory empty relative, and pinned npm spec. Observed `pos_npm` / `pos_rel` / `pos_same` / `pos_pin` / `pos_n` are exact. First n=5 freeze **12.402×** (18.871 / 1.522 µs) on host `cursor`, ceiling 20.0 (first-freeze headroom). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 731 — `package_manager` (resource_group_label)

| metric | cadr | pi |
|---|---|---|
| `resource_group_label` | `config-resource-group-label` (`src/cadr-cli/packages/config-selector.lisp`) | resource group label (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pair 730. Timed work is package source+scope, local user settings, local project settings, and project `.cadr/` label. Observed `rgl_pkg` / `rgl_user` / `rgl_proj` / `rgl_cadr` / `rgl_n` are exact. First n=5 freeze **31.609×** (17.081 / 0.540 µs) on host `cursor`, ceiling 50.0 (first-freeze headroom). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 732 — `package_manager` (settings_values)

| metric | cadr | pi |
|---|---|---|
| `settings_values` | `config-selector-settings-values` (`src/cadr-cli/packages/config-selector.lisp`) | settings values (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pairs 730–731. Timed work is global string vector, project string vector, numeric vector, and non-array miss. Observed `csv_ok` / `csv_proj` / `csv_nums` / `csv_bad` / `csv_n` are exact. First n=5 freeze **6.444×** (5.209 / 0.808 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 733 — `package_manager` (pattern_candidates)

| metric | cadr | pi |
|---|---|---|
| `pattern_candidates` | `config-pattern-candidates` (`src/cadr-cli/packages/config-selector.lisp`) | pattern candidates (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of leftover 730–732 on `src/cadr-cli/packages/config-selector.lisp`. Timed work is plain file candidate count, absolute namestring membership, skill parent extras, and skill directory name. Observed `cpc_plain` / `cpc_abs` / `cpc_skill` / `cpc_hello` / `cpc_n` are exact. First n=5 freeze **5.911×** (15.875 / 2.686 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 734 — `package_manager` (pattern_matches)

| metric | cadr | pi |
|---|---|---|
| `pattern_matches` | `config-pattern-matches-p` (`src/cadr-cli/packages/config-selector.lisp`) | pattern matches (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pair 733. Timed work is glob `*.lisp` hit, `*.md` miss, exact `SKILL.md`, and `a?b`. Observed `cpm_lisp` / `cpm_miss` / `cpm_exact` / `cpm_q` / `cpm_n` are exact. First n=5 freeze **7.155×** (32.598 / 4.556 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 735 — `package_manager` (enabled_by_patterns)

| metric | cadr | pi |
|---|---|---|
| `enabled_by_patterns` | `config-enabled-by-patterns-p` (`src/cadr-cli/packages/config-selector.lisp`) | enabled by patterns (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pairs 733–734. Timed work is default-on with no includes, include glob, exclude bang, and `+` exact load after a miss include. Observed `ebp_def` / `ebp_inc` / `ebp_exc` / `ebp_load` / `ebp_n` are exact. First n=5 freeze **4.820×** (31.989 / 6.637 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 736 — `package_manager` (delta_resource_state)

| metric | cadr | pi |
|---|---|---|
| `delta_resource_state` | `config-package-delta-resource-state` (`src/cadr-cli/packages/config-selector.lisp`) | package delta resource state (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of leftover 733–735 on `src/cadr-cli/packages/config-selector.lisp`. Timed work is `+` exact enable+match, `-` match not enabled, `!` glob match not enabled, and `*.md` miss. Observed `drs_plus` / `drs_minus` / `drs_bang` / `drs_miss` / `drs_n` are exact. First n=5 freeze **3.946×** (17.140 / 4.344 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 737 — `package_manager` (project_top_level_state)

| metric | cadr | pi |
|---|---|---|
| `project_top_level_state` | `config-selector-project-top-level-state` (`src/cadr-cli/packages/config-selector.lisp`) | project top-level state (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pair 736. Timed work is project settings `+hello.lisp` load, `-hello.lisp` unload, `!hello.lisp` unload, and `+other.lisp` inherit. Observed `pts_load` / `pts_unload` / `pts_bang` / `pts_miss` / `pts_n` are exact. First n=5 freeze **5.971×** (31.215 / 5.227 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 738 — `package_manager` (derived_project_state)

| metric | cadr | pi |
|---|---|---|
| `derived_project_state` | `config-selector-derived-project-state` (`src/cadr-cli/packages/config-selector.lisp`) | derived project state (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |

Leftover sibling of Pairs 736–737. Timed work is derived top-level load, derived top-level unload, package origin `npm:foo` empty project packages inherit, and derived miss inherit. Observed `dps_load` / `dps_unload` / `dps_pkg` / `dps_miss` / `dps_n` are exact. First n=5 freeze **6.210×** (31.710 / 5.107 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 739 — `settings_load` (environment_value)

| metric | cadr | pi |
|---|---|---|
| `environment_value` | `environment-value` (`src/cadr-cli/config.lisp`) | env lookup (`packages/coding-agent/src/config.ts`) |

Leftover sibling of leftover 454–456 on `src/cadr-cli/config.lisp`. Timed work is bound-env hit, miss, blank string, and `CADR_PROVIDER`. Observed `ev_hit` / `ev_miss` / `ev_blank` / `ev_cadr` / `ev_n` are exact. First n=5 freeze **1.090×** (0.299 / 0.274 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 740 — `settings_load` (configured_provider_name)

| metric | cadr | pi |
|---|---|---|
| `configured_provider_name` | `configured-provider-name` (`src/cadr-cli/config.lisp`) | configured provider name (`packages/coding-agent/src/config.ts`) |

Leftover sibling of Pair 739. Timed work is explicit name, `CADR_PROVIDER`, Anthropic key, and OpenAI key. Observed `cpn_exp` / `cpn_cadr` / `cpn_anth` / `cpn_openai` / `cpn_n` are exact. First n=5 freeze **0.760×** (0.376 / 0.495 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 741 — `settings_load` (provider_settings)

| metric | cadr | pi |
|---|---|---|
| `provider_settings` | `provider-settings` (`src/cadr-cli/config.lisp`) | provider settings object (`packages/coding-agent/src/config.ts`) |

Leftover sibling of Pairs 739–740. Timed work is openai model hit, missing provider empty object, missing providers key, and miss result is a hash table. Observed `pset_hit` / `pset_miss` / `pset_none` / `pset_ht` / `pset_n` are exact. First n=5 freeze **2.018×** (1.333 / 0.661 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 742 — `settings_load` (provider_default_model)

| metric | cadr | pi |
|---|---|---|
| `provider_default_model` | `provider-default-model` (`src/cadr-cli/config.lisp`) | provider default model (`packages/coding-agent/src/config.ts`) |

Leftover sibling of leftover 739–741 on `src/cadr-cli/config.lisp`. Timed work is openai `gpt-5.5`, anthropic `claude-opus-4-8`, google `gemini-3.1-pro-preview`, and unknown provider error. Observed `pdm_openai` / `pdm_anth` / `pdm_google` / `pdm_miss` / `pdm_n` are exact. First n=5 freeze **0.410×** (0.970 / 2.367 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 743 — `settings_load` (oauth_refresh_function)

| metric | cadr | pi |
|---|---|---|
| `oauth_refresh_function` | `oauth-refresh-function` (`src/cadr-cli/config.lisp`) | oauth refresh function (`packages/coding-agent/src/config.ts`) |

Leftover sibling of Pair 742. Timed work is openai-codex refresh symbol, anthropic refresh symbol, google miss, and two providers not eq. Observed `orf_codex` / `orf_anth` / `orf_miss` / `orf_diff` / `orf_n` are exact. First n=5 freeze **0.139×** (0.346 / 2.498 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 744 — `settings_load` (oauth_login_function)

| metric | cadr | pi |
|---|---|---|
| `oauth_login_function` | `oauth-login-function` (`src/cadr-cli/config.lisp`) | oauth login function (`packages/coding-agent/src/config.ts`) |

Leftover sibling of Pairs 742–743. Timed work is openai-codex login function, anthropic login function, google ecase miss, and two providers not eq. Observed `olf_codex` / `olf_anth` / `olf_miss` / `olf_diff` / `olf_n` are exact. First n=5 freeze **1.057×** (2.562 / 2.423 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 745 — `provider_registry_defs` (oauth_login_function)

| metric | cadr | pi |
|---|---|---|
| `oauth_login_function` | `built-in-oauth-login-function` (`src/cadr-ai/providers/runtime-projection.lisp`) | oauth.login presence (`packages/ai/src/providers/github-copilot.ts` + `anthropic.ts` + `google.ts`) |

Leftover sibling of leftover 742–744 on a different needs-pair file. Timed work is github-copilot login function, anthropic login function, google miss, and two providers not eq. Observed `ologin_copilot` / `ologin_anth` / `ologin_miss` / `ologin_diff` / `ologin_n` are exact. First n=5 freeze **0.008×** (0.121 / 15.704 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 746 — `provider_registry_defs` (oauth_refresh_function)

| metric | cadr | pi |
|---|---|---|
| `oauth_refresh_function` | `built-in-oauth-refresh-function` (`src/cadr-ai/providers/runtime-projection.lisp`) | oauth.refresh presence (`packages/ai/src/providers/github-copilot.ts` + `anthropic.ts` + `google.ts`) |

Leftover sibling of Pair 745. Timed work is github-copilot refresh function, anthropic refresh function, google miss, and two providers not eq. Observed `orefresh_copilot` / `orefresh_anth` / `orefresh_miss` / `orefresh_diff` / `orefresh_n` are exact. First n=5 freeze **0.008×** (0.122 / 15.368 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 747 — `provider_registry_defs` (oauth_to_auth)

| metric | cadr | pi |
|---|---|---|
| `oauth_to_auth` | `built-in-oauth-to-auth` (`src/cadr-ai/providers/runtime-projection.lisp`) | anthropic toAuth + kimi-coding toAuth (`packages/ai/src/auth/oauth/anthropic.ts` + `kimi-coding.ts`) |

Leftover sibling of Pairs 745–746. Timed work is anthropic access-token api-key, kimi-bearer Authorization header, google miss, and access-token vs bearer not sharing api-key. Observed `ota_anth` / `ota_kimi` / `ota_miss` / `ota_diff` / `ota_n` are exact. First n=5 freeze **1.601×** (0.428 / 0.267 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.

### Pair 748 — `provider_registry_defs` (api_key_login_function)

| metric | cadr | pi |
|---|---|---|
| `api_key_login_function` | `built-in-api-key-login-function` (`src/cadr-ai/providers/runtime-projection.lisp`) | ApiKeyAuth.login select-flow presence (`packages/ai/src/providers/amazon-bedrock.ts` + `google-vertex.ts`) |

Leftover sibling of leftover 745–747 on the same needs-pair file. Timed work is amazon-bedrock login function, google-vertex login function, openai env-login not in the cadr table, and two structured logins not eq. Observed `alk_bedrock` / `alk_vertex` / `alk_openai` / `alk_diff` / `alk_n` are exact. First n=5 freeze **0.001×** (0.174 / 212.888 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 749 — `provider_registry_defs` (api_key_auth)

| metric | cadr | pi |
|---|---|---|
| `api_key_auth` | `built-in-api-key-auth` (`src/cadr-ai/providers/runtime-projection.lisp`) | envApiKeyAuth.resolve (`packages/ai/src/auth/helpers.ts`; openai-codex has no apiKey) |

Leftover sibling of Pair 748. Timed work is explicit key, stored credential, OPENAI_API_KEY env, miss, and openai-codex otherwise-nil. Observed `aka_explicit` / `aka_stored` / `aka_env` / `aka_miss` / `aka_n` are exact. First n=5 freeze **0.003×** (0.709 / 209.735 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 750 — `provider_registry_defs` (model_filter_function)

| metric | cadr | pi |
|---|---|---|
| `model_filter_function` | `built-in-model-filter-function` (`src/cadr-ai/providers/runtime-projection.lisp`) | filterModels (`packages/ai/src/providers/github-copilot.ts`) |

Leftover sibling of Pairs 748–749. Timed work is github-copilot filter function, openai miss, availableModelIds keep-me, and empty availableModelIds. Observed `mff_copilot` / `mff_openai` / `mff_keep` / `mff_empty` / `mff_n` are exact. First n=5 freeze **0.003×** (0.646 / 215.457 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.

### Pair 889 — `oauth_pkce_device` (token_fields)

| metric | cadr | pi |
|---|---|---|
| `token_fields` | `token-response-credential` (`src/cadr-ai/oauth/openai-anthropic.lisp`) | `readTokenResponse` field check (`packages/ai/src/auth/oauth/openai-codex.ts`) |
Leftover trio on unclaimed `src/cadr-ai/oauth/openai-anthropic.lisp`. Timed work is access/refresh/expires_in presence (ok / missing access / missing expires_in) — not live HTTP, not expiry timestamps, not old-refresh fallback. Observed `trc_ok` / `trc_miss_acc` / `trc_miss_exp` / `trc_n` are exact. First n=5 freeze **0.746×** (3.187 / 4.272 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1×. Booked in `docs/benchmarks/goal20-paired-over-1x.md`. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 890 — `oauth_pkce_device` (openai_exchange)
| `openai_exchange` | `exchange-openai-authorization-code` (`src/cadr-ai/oauth/openai-anthropic.lisp`) | `exchangeAuthorizationCode` JSON parse (`packages/ai/src/auth/oauth/openai-codex.ts`) |
Leftover sibling of Pair 889. Timed work is stub HTTP 200 token JSON, HTTP 400, and missing refresh_token — not browser login, not PKCE. Observed `oex_ok` / `oex_http` / `oex_miss` / `oex_n` are exact. First n=5 freeze **5.625×** (29.574 / 5.257 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 891 — `oauth_pkce_device` (anthropic_exchange)
| `anthropic_exchange` | `exchange-anthropic-authorization-code` (`src/cadr-ai/oauth/openai-anthropic.lisp`) | `exchangeAuthorizationCode` JSON parse (`packages/ai/src/auth/oauth/anthropic.ts`) |
Leftover sibling of Pairs 889–890. Timed work is stub HTTP 200 token JSON, HTTP 400, and invalid JSON — not callback server, not expires skew. Observed `aex_ok` / `aex_http` / `aex_badjson` / `aex_n` are exact. First n=5 freeze **1.697×** (12.807 / 7.545 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 892 — `oauth_pkce_device` (device_poll_complete)
| `device_poll_complete` | `poll-openai-codex-device-authorization` (`src/cadr-ai/oauth/providers/openai-device.lisp`) | `pollOpenAICodexDeviceAuth` complete (`packages/ai/src/auth/oauth/openai-codex.ts`) |
Leftover trio on unclaimed `src/cadr-ai/oauth/providers/openai-device.lisp` (leftover 421–423 measured json_copy / interval_seconds / device_start). Timed work is stub HTTP 200 with authorization_code and code_verifier — not device_start, not browser login. Observed `dpc_code` / `dpc_ver` / `dpc_n` are exact. First n=5 freeze **15.756×** (2.586 / 0.164 µs) on host `Friend-MachineD`, ceiling 15.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 893 — `oauth_pkce_device` (device_poll_fail)
| `device_poll_fail` | `poll-openai-codex-device-authorization` failed (`src/cadr-ai/oauth/providers/openai-device.lisp`) | `pollOpenAICodexDeviceAuth` failed (`packages/ai/src/auth/oauth/openai-codex.ts`) |
Leftover sibling of Pair 892. Timed work is stub HTTP 200 missing fields throwing — not exact failed-message JSON stringify. Observed `dpf_throw` / `dpf_n` are exact. First n=5 freeze **1.705×** (2.962 / 1.737 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 894 — `oauth_pkce_device` (device_poll_slow)
| `device_poll_slow` | `poll-openai-codex-device-authorization` slow_down timeout (`src/cadr-ai/oauth/providers/openai-device.lisp`) | `pollOpenAICodexDeviceAuth` slow_down + `SLOW_DOWN_TIMEOUT_MESSAGE` (`packages/ai/src/auth/oauth/openai-codex.ts` + `device-code.ts`) |
Leftover sibling of Pairs 892–893. Timed work is stub HTTP error `slow_down` then timeout message — not interval_seconds, not live sleep. Observed `dps_msg` / `dps_n` are exact. First n=5 freeze **1.824×** (3.588 / 1.967 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 925 — `evals_harness` (validate_extension)
| `validate_extension` | `validate-extension-result` (`src/cadr-evals/main.lisp`) | leftover replica of extension greeting + path-count |
Leftover sibling of leftover 400–402 on the same needs-pair file. Timed work is Bob+one-path ok, Alice greeting fail, two-path fail, empty-path fail. Observed `ve_ok` / `ve_greet` / `ve_paths` / `ve_empty` / `ve_n` are exact. First n=5 freeze **7.979×** (2.604 / 0.326 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 926 — `evals_harness` (suite_dispatch)
| `suite_dispatch` | leftover replica of `%eval-main` suite cond (`src/cadr-evals/main.lisp`) | leftover replica of cadr suite cond (pi has no `--suite`) |
Leftover sibling of Pair 925. Timed work is smoke/extensions/extension-authoring/unknown dispatch ids. Observed `sd_smoke` / `sd_ext` / `sd_auth` / `sd_unk` / `sd_n` are exact. First n=5 freeze **0.874×** (0.171 / 0.196 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 927 — `evals_harness` (eval_result_p)
| `eval_result_p` | leftover of `%eval-main` `(typep value 'eval-result)` (`src/cadr-evals/main.lisp`) | leftover object-shape predicate (`output` + `events` own properties) |
Leftover sibling of Pairs 925–926. Timed work is make-eval-result yes, json-object miss, string miss, nil miss. Observed `er_yes` / `er_hash` / `er_str` / `er_nil` / `er_n` are exact. First n=5 freeze **1.836×** (0.608 / 0.331 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 928 — `evals_harness` (msg_content)
| `msg_content` | `message-content-text` (`src/cadr-evals/harness.lisp`) | leftover replica of content-text join |
Leftover sibling of leftover 418–420 on the same needs-pair file. Does not remount `content_text`. Timed work is plain string, text-parts join, empty, blank. Observed `ct_plain` / `ct_join` / `ct_empty` / `ct_blank` / `ct_n` are exact. First n=5 freeze **1.352×** (1.008 / 0.745 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 929 — `evals_harness` (eval_tools)
| `eval_tools` | `eval-agent-tools` (`src/cadr-evals/harness.lisp`) | leftover replica of agent.tools list |
Leftover sibling of Pair 928. Does not remount `agent_tools`. Timed work is empty tools, filled count, read name, bash name. Observed `at_empty` / `at_n` / `at_read` / `at_bash` / `at_keys` are exact. First n=5 freeze **5.428×** (1.547 / 0.285 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 930 — `evals_harness` (eval_paths)
| `eval_paths` | `eval-extension-paths` (`src/cadr-evals/harness.lisp`) | leftover replica of visible extension-host paths |
Leftover sibling of Pairs 928–929. Does not remount `extension_paths`. Timed work is no-host empty, one visible path, hidden skipped. Observed `ep_none` / `ep_n` / `ep_path` / `ep_skip` / `ep_keys` are exact. First n=5 freeze **7.223×** (3.230 / 0.447 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 931 — `cli_interactive_controller` (theme_prim)
| `theme_prim` | `valid-tui-theme-primitive-p` (`src/cadr-cli/interactive/themes.lisp`) | leftover replica of isThemeColorValue |
Leftover sibling of leftover 532–534 on the same needs-pair file. Does not remount `theme_primitive`. Timed work is string, 0, 255, 256, negative, nil. Observed `tp_str` / `tp_int` / `tp_255` / `tp_256` / `tp_neg` / `tp_nil` are exact. First n=5 freeze **0.741×** (0.110 / 0.149 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 932 — `cli_interactive_controller` (theme_val)
| `theme_val` | `validate-tui-theme-object` (`src/cadr-cli/interactive/themes.lisp`) | leftover replica of theme object validate |
Leftover sibling of Pair 931. Does not remount `theme_validate`. Timed work is valid object, slash name, unknown property. Observed `tv_ok` / `tv_slash` / `tv_unknown` are exact. First n=5 freeze **0.756×** (19.713 / 26.066 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 933 — `cli_interactive_controller` (theme_res)
| `theme_res` | `resolve-tui-theme-value` (`src/cadr-cli/interactive/themes.lisp`) | leftover replica of resolveThemeColor |
Leftover sibling of Pairs 931–932. Does not remount `theme_resolve`. Timed work is integer, empty, hex, variable, cycle, miss. Observed `tr_int` / `tr_empty` / `tr_hex` / `tr_var` / `tr_cycle` / `tr_miss` are exact. First n=5 freeze **0.144×** (1.192 / 8.261 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 934 — `cli_print_rpc` (queue_parse)
| `queue_parse` | `parse-queue-mode` (`src/cadr-cli/modes/rpc/commands.lisp`) | leftover replica of parseQueueMode |
Leftover sibling of leftover 475–477 on the same needs-pair file. Does not remount `queue_mode`. Timed work is all, one-at-a-time, invalid. Observed `qm_all` / `qm_one` / `qm_bad` are exact. First n=5 freeze **0.132×** (0.337 / 2.547 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 935 — `cli_print_rpc` (asst_text)
| `asst_text` | `rpc-last-assistant-text` (`src/cadr-cli/modes/rpc/commands.lisp`) | leftover replica of last assistant text |
Leftover sibling of Pair 934. Does not remount `last_assistant`. Timed work is hit hello, length, empty miss. Observed `la_hit` / `la_len` / `la_miss` are exact. First n=5 freeze **0.791×** (0.293 / 0.370 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 936 — `cli_print_rpc` (cmd_list)
| `cmd_list` | `rpc-command-list` (`src/cadr-cli/modes/rpc/commands.lisp`) | leftover replica of rpc command list |
Leftover sibling of Pairs 934–935. Does not remount `command_list`. Timed work is count, extension foo, prompt bar. Observed `cl_n` / `cl_ext` / `cl_prompt` are exact. First n=5 freeze **4.603×** (1.533 / 0.333 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 937 — `cli_print_rpc` (bad_line)
| `bad_line` | `rpc-handle-line` (`src/cadr-cli/modes/rpc/mode.lisp`) | `handleInputLine` JSON.parse catch (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |
Leftover sibling of leftover 496–498 on the same needs-pair file. Does not remount `handle_bad_json`. Timed work is invalid JSON (`not-json`) through the outer parse failure — not `run-rpc-mode`, not a live agent. Observed `bj_cmd` / `bj_ok` / `bj_id` / `bj_nl` are exact. Do not exact full error strings. First n=5 freeze **1.262×** (5.686 / 4.505 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 938 — `cli_print_rpc` (array_line)
| `array_line` | `rpc-handle-line` (`src/cadr-cli/modes/rpc/mode.lisp`) | `handleInputLine` require JSON object (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |
Leftover sibling of Pair 937. Does not remount `handle_not_object`. Timed work is JSON array `[]` rejected as a non-object — not command dispatch. Observed `no_cmd` / `no_ok` / `no_id` / `no_nl` are exact. Do not exact full error strings. First n=5 freeze **1.474×** (5.528 / 3.750 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 939 — `cli_print_rpc` (ui_absent)
| `ui_absent` | `rpc-handle-line` (`src/cadr-cli/modes/rpc/mode.lisp`) | `handleInputLine` unknown `extension_ui_response` (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |
Leftover sibling of Pairs 937–938. Does not remount `handle_ui_miss`. Timed work is an unknown pending UI id (`missing`) — not dialog resolve, not `rpc-shutdown`. Observed `um_cmd` / `um_ok` / `um_id` / `um_nl` / `um_unk` are exact. Do not exact full error strings. First n=5 freeze **4.202×** (6.543 / 1.557 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 940 — `cli_bootstrap_sessions` (cycle_wrap)
| `cycle_wrap` | `model-cycle-target-entry` (`src/cadr-cli/bootstrap/commands.lisp`) | `_cycleScopedModel` index wrap (`packages/coding-agent/src/core/agent-session.ts`) |
Leftover sibling of leftover 484–486 on the same needs-pair file. Does not remount `model_cycle`. Timed work is scoped-entry wrap / missing-current default — not session persist, not `cycleModel` emit. Observed `mc_fwd` / `mc_bwd` / `mc_wrap` / `mc_miss` / `mc_one` / `mc_empty` are exact. First n=5 freeze **0.745×** (0.655 / 0.879 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 941 — `cli_bootstrap_sessions` (scope_hint)
| `scope_hint` | `model-scope-startup-line` (`src/cadr-cli/bootstrap/commands.lisp`) | interactive-mode `init` Model scope line (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |
Leftover sibling of Pair 940. Does not remount `model_scope_line`. Timed work is the startup scope line (quiet / empty / cycle-hint / unbound) — not TUI mount, not theme init. Observed `ms_quiet` / `ms_empty` / `ms_text` / `ms_n` / `ms_disabled` are exact. First n=5 freeze **0.838×** (35.665 / 42.573 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 942 — `cli_bootstrap_sessions` (file_tags)
| `file_tags` | `process-cli-file-arguments` (`src/cadr-cli/bootstrap/commands.lisp`) | `processFileArguments` (`packages/coding-agent/src/cli/file-processor.ts`) |
Leftover sibling of Pairs 940–941. Does not remount `process_files`. Timed work is one text file plus one empty skip — not image resize, not `@file` CLI parse. Observed `pf_hello` / `pf_n` / `pf_img` are exact. First n=5 freeze **0.556×** (80.505 / 144.830 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 943 — `cli_interactive_controller` (sess_make)
| `sess_make` | `make-tool-render-session` (`src/cadr-cli/interactive/tool-render-session.lisp`) | leftover replica of `ToolExecutionComponent` construct |
Leftover sibling of leftover 520–522 on the same needs-pair file. Does not remount `tool_session_make`. Timed work is session construct (name, default pending, nil result) — not render, not update. Observed `tsm_name` / `tsm_pending` / `tsm_nil` are exact. First n=5 freeze **1.130×** (0.244 / 0.216 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 944 — `cli_interactive_controller` (sess_upd)
| `sess_upd` | `update-tool-render-session` (`src/cadr-cli/interactive/tool-render-session.lisp`) | leftover replica of result/pending |
Leftover sibling of Pair 943. Does not remount `tool_session_update`. Timed work is result write plus pending keep/clear — not renderCall, not construct. Observed `tsu_result` / `tsu_pending` / `tsu_cleared` are exact. First n=5 freeze **1.132×** (0.257 / 0.227 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 945 — `cli_interactive_controller` (sess_draw)
| `sess_draw` | `render-tool-session` (`src/cadr-cli/interactive/tool-render-session.lisp`) | leftover replica of renderCall/renderResult fallback |
Leftover sibling of Pairs 943–944. Does not remount `tool_session_render`. Timed work is pending default call, done default result, custom renderers, empty-line drop — not TUI Box, not images. Observed `trr_pending_n` / `trr_pending_call` / `trr_done_n` / `trr_done_result` / `trr_custom` / `trr_empty` are exact. First n=5 freeze **0.842×** (1.503 / 1.785 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 946 — `cli_selectors` (dlg_make)
| `dlg_make` | `make-login-dialog-state` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of `LoginDialogComponent` constructor |
Leftover sibling of leftover 529–531 on the same needs-pair file. Does not remount `login_dialog_make`. Timed work is empty/named/long provider construction — not render, not handle-event. Observed `ldm_empty_n` / `ldm_named` / `ldm_named_sec` / `ldm_long` / `ldm_input` / `ldm_long_n` are exact. First n=5 freeze **1.471×** (0.189 / 0.128 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 947 — `cli_selectors` (dlg_auth)
| `dlg_auth` | `login-dialog-show-auth` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of `showAuth` |
Leftover sibling of Pair 946. Does not remount `login_dialog_auth`. Timed work is plain/instructions/empty-instructions/replace auth sections — not OAuth HTTP, not render. Observed `lda_plain` / `lda_instr` / `lda_empty_instr` / `lda_replace` / `lda_provider` / `lda_n` are exact. First n=5 freeze **1.689×** (2.003 / 1.186 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 948 — `cli_selectors` (dlg_dev)
| `dlg_dev` | `login-dialog-show-device-code` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of `showDeviceCode` |
Leftover sibling of Pairs 946–947. Does not remount `login_dialog_device`. Timed work is device-code / empty-code / replace sections — not poll, not render. Observed `ldd_code` / `ldd_empty` / `ldd_replace` / `ldd_provider` / `ldd_n` / `ldd_hint` are exact. First n=5 freeze **3.465×** (4.085 / 1.179 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 949 — `cli_interactive_controller` (wrap_osc)
| `wrap_osc` | `wrap-transcript-lines` (`src/cadr-cli/interactive/transcript.lisp`) | leftover replica of `UserMessageComponent.render` OSC 133 wrap |
Leftover sibling of leftover 517–519 on the same needs-pair file. Does not remount `wrap_transcript`. Timed work is OSC 133 A/B/C wrap of a line list (nil, one-element shared-cons order, two-element first/last) — not user-message markdown, not assistant render. Observed `wt_nil` / `wt_one_n` / `wt_one_order` / `wt_two_n` / `wt_two_first` / `wt_two_last` are exact. First n=5 freeze **0.981×** (0.583 / 0.594 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 950 — `cli_interactive_controller` (pad_str)
| `pad_str` | `output-padding-string` (`src/cadr-cli/interactive/transcript.lisp`) | leftover replica of output padding spaces |
Leftover sibling of Pair 949. Does not remount `output_padding`. Timed work is pad length 0/1/other and space identity — not wrap, not cacheable. Observed `op_0` / `op_1` / `op_other` / `op_space` are exact. First n=5 freeze **1.041×** (0.215 / 0.206 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 951 — `cli_interactive_controller` (cache_p)
| `cache_p` | `tui-entry-render-cacheable-p` (`src/cadr-cli/interactive/transcript.lisp`) | leftover replica of TUI entry render cacheable |
Leftover sibling of Pairs 949–950. Does not remount `render_cacheable`. Timed work is assistant/streaming/tool-nil/done/running/custom flags — not wrap, not pad. Observed `rc_assist` / `rc_stream` / `rc_tool_nil` / `rc_tool_done` / `rc_tool_run` / `rc_custom` are exact. First n=5 freeze **2.014×** (1.264 / 0.627 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 952 — `evals_harness` (rep_make)
| `rep_make` | `make-eval-harness-reporter` (`src/cadr-evals/reporter.lisp`) | leftover replica of reporter constructor artifactDirectory |
Leftover sibling of leftover 703–705 on the same needs-pair file. Does not remount `make_reporter`. Timed work is explicit dir, trimmed env fallback, missing env — not record-case, not persist. Observed `mr_explicit` / `mr_env` / `mr_miss` / `mr_n` are exact. First n=5 freeze **0.898×** (0.367 / 0.409 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 953 — `evals_harness` (fin_num)
| `fin_num` | `reporter-finite-number` (`src/cadr-evals/reporter.lisp`) | leftover replica of finite number keep |
Leftover sibling of Pair 952. Does not remount `finite_number`. Timed work is int/float keep and nil/inf/string drop — not observation walk, not persist. Observed `fn_int` / `fn_float` / `fn_nil` / `fn_inf` / `fn_str` / `fn_n` are exact. First n=5 freeze **0.563×** (0.126 / 0.224 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 954 — `evals_harness` (art_meta)
| `art_meta` | `reporter-artifact-metadata` (`src/cadr-evals/reporter.lisp`) | leftover replica of artifact metadata filter |
Leftover sibling of Pairs 952–953. Does not remount `artifact_metadata`. Timed work is keep custom, drop runId and session snapshot — not JSONL, not persist. Observed `am_keep` / `am_runid` / `am_snap` / `am_n` are exact. First n=5 freeze **1.181×** (1.038 / 0.879 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 955 — `cli_interactive_controller` (bash_run)
| `bash_run` | `append-tui-user-bash-running` (`src/cadr-cli/interactive/user-bash.lisp`) | leftover replica of BashExecutionComponent addChild running |
Leftover sibling of leftover 640–642 on the same needs-pair file. Does not remount `bash_append_running`. Timed work is two running entries (plain / exclude-from-context). Observed `bar_n` / `bar_run2` are exact. First n=5 freeze **2.219×** (0.807 / 0.363 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 956 — `cli_interactive_controller` (bash_fin)
| `bash_fin` | `complete-tui-user-bash-string` (`src/cadr-cli/interactive/user-bash.lisp`) | leftover replica of setComplete exit 0 string |
Leftover sibling of Pair 955. Does not remount `bash_complete_string`. Timed work is hello complete and empty complete. Observed `cs_text` / `cs_empty` are exact. First n=5 freeze **2.620×** (0.785 / 0.300 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 957 — `cli_interactive_controller` (bash_halt)
| `bash_halt` | `stop-tui-user-bash-entry` (`src/cadr-cli/interactive/user-bash.lisp`) | leftover replica of loader.stop without setComplete |
Leftover sibling of Pairs 955–956. Does not remount `bash_stop_entry`. Timed work is stop after partial output. Observed `st_run` / `st_exit` are exact. First n=5 freeze **2.872×** (0.635 / 0.221 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1354 — `cli_selectors` (latxxx_ok)
| `latxxx_ok` | `login-auth-type-route` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showLoginAuthTypeSelector routing |
Leftover sibling of leftover 1288–1290 on the same needs-pair file (fifth unused slug after leftover 1060 `oa_rt` / leftover 1141 `lat_ok` / leftover 1222 `latx_ok` / leftover 1288 `latxx_ok`). Does not remount `login_auth_type_route`. Timed work is auth-type route none / oauth. Observed `latr_none` / `latr_oauth` are exact. First n=5 freeze **2.078×** (2.534 / 1.220 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1355 — `cli_selectors` (lpoxxx_ok)
| `lpoxxx_ok` | `login-provider-options` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of getLoginProviderOptions |
Leftover sibling of Pair 1354. Does not remount `login_provider_options` / leftover 1060 `oa_lin` / leftover 1142 `lpo_ok` / leftover 1223 `lpox_ok` / leftover 1289 `lpoxx_ok`. Timed work is login provider options all / oauth. Observed `lpo_all` / `lpo_oauth` are exact. First n=5 freeze **1.459×** (8.355 / 5.726 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1356 — `cli_selectors` (lgoxxx_ok)
| `lgoxxx_ok` | `logout-provider-options` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of getLogoutProviderOptions |
Leftover sibling of Pairs 1354–1355. Does not remount `logout_provider_options` / leftover 1060 `oa_out` / leftover 1143 `lgo_ok` / leftover 1224 `lgox_ok` / leftover 1290 `lgoxx_ok`. Timed work is logout provider options empty / mixed. Observed `lgo_empty` / `lgo_mixed` are exact. First n=5 freeze **2.122×** (7.260 / 3.422 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1363 — `cli_selectors` (henxxx_ok)
| `henxxx_ok` | `thinking-selector-handle-event` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking selector typed input event dispatch |
Leftover sibling of leftover 1297–1299 on the same needs-pair file (sixth unused slug after leftover 1069 `th_he` / leftover 1120 `hev_ok` / leftover 1150 `hen_ok` / leftover 1231 `henx_ok` / leftover 1297 `henxx_ok`). Does not remount `thinking_selector_handle_event`. Timed work is thinking handle-event down / text. Observed `tshe_down` / `tshe_text` are exact. First n=5 freeze **0.839×** (3.337 / 3.979 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1364 — `cli_selectors` (mtsxxx_ok)
| `mtsxxx_ok` | `make-thinking-selector-state` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking selector constructor filter + select current |
Leftover sibling of Pair 1363. Does not remount `make_thinking_selector_state` / leftover 1070 `th_mts` / leftover 1151 `mts_ok` / leftover 1232 `mtsx_ok` / leftover 1298 `mtsxx_ok`. Timed work is thinking constructor high / default. Observed `tms_high` / `tms_default` are exact. First n=5 freeze **0.775×** (1.706 / 2.200 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1365 — `cli_selectors` (lstxxx_ok)
| `lstxxx_ok` | `thinking-level-search-text` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking selector label + description search text |
Leftover sibling of Pairs 1363–1364. Does not remount `thinking_level_search_text` / leftover 1071 `th_lst` / leftover 1152 `lst_ok` / leftover 1233 `lstx_ok` / leftover 1299 `lstxx_ok`. Timed work is thinking search-text off / high. Observed `tlst_off` / `tlst_high` are exact. First n=5 freeze **1.577×** (1.172 / 0.743 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1381 — `cli_selectors` (ldwxxx_ok)
| `ldwxxx_ok` | `login-dialog-show-waiting` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showWaiting |
Leftover sibling of leftover 1315–1317 on the same needs-pair file (sixth unused slug after leftover 1027 `ld_wait` / leftover 1102 `wait_ok` / leftover 1183 `ldw_ok` / leftover 1249 `ldwx_ok` / leftover 1315 `ldwxx_ok`). Does not remount `login_dialog_show_waiting`. Timed work is empty / device waiting UI. Observed `ldw_empty` / `ldw_device` are exact. First n=5 freeze **2.566×** (5.581 / 2.175 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1382 — `cli_selectors` (ldpxxx_ok)
| `ldpxxx_ok` | `login-dialog-show-progress` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showProgress |
Leftover sibling of Pair 1381. Does not remount `login_dialog_show_progress` / leftover 1028 `ld_prog` / leftover 1103 `prog_ok` / leftover 1184 `ldp_ok` / leftover 1250 `ldpx_ok` / leftover 1316 `ldpxx_ok`. Timed work is empty / wait progress UI. Observed `ldp_empty` / `ldp_wait` are exact. First n=5 freeze **1.770×** (3.206 / 1.811 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1383 — `cli_selectors` (ldmixxx_ok)
| `ldmixxx_ok` | `login-dialog-show-manual-input` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showManualInput |
Leftover sibling of Pairs 1381–1382. Does not remount `login_dialog_show_manual_input` / leftover 1029 `ld_man` / leftover 1104 `man_ok` / leftover 1185 `ldmi_ok` / leftover 1251 `ldmix_ok` / leftover 1317 `ldmixx_ok`. Timed work is empty / nocancel manual input UI. Observed `ldmi_empty` / `ldmi_nocancel` are exact. First n=5 freeze **2.096×** (5.271 / 2.515 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1384 — `cli_selectors` (ldprxxx_ok)
| `ldprxxx_ok` | `login-dialog-show-prompt` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showPrompt |
Leftover sibling of leftover 1318–1320 on the same needs-pair file (sixth unused slug after leftover 1030 `ld_prmt` / leftover 1105 `prmt_ok` / leftover 1186 `ldpr_ok` / leftover 1252 `ldprx_ok` / leftover 1318 `ldprxx_ok`). Does not remount `login_dialog_show_prompt`. Timed work is empty / wait prompt UI. Observed `ldpr_empty` / `ldpr_wait` are exact. First n=5 freeze **2.164×** (7.001 / 3.234 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1385 — `cli_selectors` (ldixxx_ok)
| `ldixxx_ok` | `login-dialog-show-info` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showInfo |
Leftover sibling of Pair 1384. Does not remount `login_dialog_show_info` / leftover 1030 `ld_info` / leftover 1106 `info_ok` / leftover 1187 `ldi_ok` / leftover 1253 `ldix_ok` / leftover 1319 `ldixx_ok`. Timed work is labeled / nolink info UI. Observed `ldi_labeled` / `ldi_nolink` are exact. First n=5 freeze **2.297×** (9.135 / 3.977 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1386 — `cli_selectors` (lddtxxx_ok)
| `lddtxxx_ok` | `login-dialog-show-details` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showDetails |
Leftover sibling of Pairs 1384–1385. Does not remount `login_dialog_show_details` / leftover 1030 `ld_det` / leftover 1107 `det_ok` / leftover 1188 `lddt_ok` / leftover 1254 `lddtx_ok` / leftover 1320 `lddtxx_ok`. Timed work is two-row / styles details UI. Observed `lddt_two` / `lddt_styles` are exact. First n=5 freeze **0.794×** (2.646 / 3.330 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1387 — `cli_selectors` (ldcixxx_ok)
| `ldcixxx_ok` | `login-dialog-complete-input` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.replaceInputWithSubmittedText |
Leftover sibling of leftover 1321–1323 on the same needs-pair file (sixth unused slug after leftover 1033 `ld_cmp` / leftover 1108 `cmp_ok` / leftover 1189 `ldci_ok` / leftover 1255 `ldcix_ok` / leftover 1321 `ldcixx_ok`). Does not remount `login_dialog_complete_input`. Timed work is complete-input on manual / prompt states. Observed `ldci_manual` / `ldci_prompt` are exact. First n=5 freeze **3.230×** (5.854 / 1.813 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1388 — `cli_selectors` (ldhexxx_ok)
| `ldhexxx_ok` | `login-dialog-handle-event` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.handleInput |
Leftover sibling of Pair 1387. Does not remount `login_dialog_handle_event` / leftover 1033 `ld_evt` / leftover 1109 `evt_ok` / leftover 1190 `ldhe_ok` / leftover 1256 `ldhex_ok` / leftover 1322 `ldhexx_ok`. Timed work is esc / cancel handleInput. Observed `ldhe_esc` / `ldhe_cancel` are exact. First n=5 freeze **2.887×** (7.396 / 2.562 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1389 — `cli_selectors` (ldrdxxx_ok)
| `ldrdxxx_ok` | `render-login-dialog-state` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent layout |
Leftover sibling of Pairs 1387–1388. Does not remount `render_login_dialog` / leftover 1033 `ld_rnd` / leftover 1110 `rnd_ok` / leftover 1191 `ldrd_ok` / leftover 1257 `ldrdx_ok` / leftover 1323 `ldrdxx_ok`. Timed work is wait / details layout. Observed `ldrd_wait` / `ldrd_details` are exact. First n=5 freeze **29.776×** (106.883 / 3.590 µs) on host `cursor`, ceiling 50.0 matching leftover 1323. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1390 — `cli_selectors` (umevxxx_ok)
| `umevxxx_ok` | `user-message-selector-handle-event` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageList.handleInput (structured events) |
Leftover sibling of leftover 1324–1326 on the same needs-pair file (sixth unused slug after leftover 1036 `um_he` / leftover 1111 `he_ok` / leftover 1192 `umev_ok` / leftover 1258 `umevx_ok` / leftover 1324 `umevxx_ok`). Does not remount `user_message_handle_event`. Timed work is down / empty structured handle-event. Observed `umhe_down` / `umhe_empty` are exact. First n=5 freeze **0.707×** (1.371 / 1.940 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1391 — `cli_selectors` (umrwxxx_ok)
| `umrwxxx_ok` | `user-message-selector-handle-raw-input` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageList.handleInput (raw key dispatch) |
Leftover sibling of Pair 1390. Does not remount `user_message_handle_raw` / leftover 1036 `um_hr` / leftover 1112 `raw_ok` / leftover 1193 `umrw_ok` / leftover 1259 `umrwx_ok` / leftover 1325 `umrwxx_ok`. Timed work is down / nop raw handle. Observed `umhr_down` / `umhr_nop` are exact. First n=5 freeze **17.622×** (85.685 / 4.862 µs) on host `cursor`, ceiling 30.0 matching leftover 1325. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1392 — `cli_selectors` (umrsxxx_ok)
| `umrsxxx_ok` | `render-user-message-selector` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageSelectorComponent layout |
Leftover sibling of Pairs 1390–1391. Does not remount `render_user_message_selector` / leftover 1036 `um_rd` / leftover 1113 `sel_ok` / leftover 1194 `umrs_ok` / leftover 1260 `umrsx_ok` / leftover 1326 `umrsxx_ok`. Timed work is three-row / hit selector layout. Observed `umrd_three` / `umrd_hit` are exact. First n=5 freeze **70.735×** (242.804 / 3.433 µs) on host `cursor`, ceiling 100.0 matching leftover 1326. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1393 — `cli_selectors` (mkbxxx_ok)
| `mkbxxx_ok` | `make-models-selector-keybindings` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of KeybindingsManager app.models.* constructor |
Leftover sibling of leftover 1327–1329 on the same needs-pair file (sixth unused slug after leftover 1039 `ms_kb` / leftover 1114 `kb_ok` / leftover 1195 `mkb_ok` / leftover 1261 `mkbx_ok` / leftover 1327 `mkbxx_ok`). Does not remount `make_models_selector_keybindings`. Timed work is save / reorder keybinding construction. Observed `mmskb_save` / `mmskb_reorder` are exact. First n=5 freeze **1.515×** (32.739 / 21.614 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1394 — `cli_selectors` (msmsxxx_ok)
| `msmsxxx_ok` | `make-scoped-models-selector-state` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of ScopedModelsSelectorComponent constructor |
Leftover sibling of Pair 1393. Does not remount `make_scoped_models_selector_state` / leftover 1039 `sm_st` / leftover 1115 `sms_ok` / leftover 1196 `msms_ok` / leftover 1262 `msmsx_ok` / leftover 1328 `msmsxx_ok`. Timed work is all / copy scoped-models state. Observed `msmksc_all` / `msmksc_copy` are exact. First n=5 freeze **24.432×** (105.397 / 4.314 µs) on host `cursor`, ceiling 40.0 matching leftover 1328. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1395 — `cli_selectors` (mrmsxxx_ok)
| `mrmsxxx_ok` | `render-model-selector` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of ModelSelectorComponent layout |
Leftover sibling of Pairs 1393–1394. Does not remount `render_model_selector` / leftover 1039 `rm_sel` / leftover 1116 `rms_ok` / leftover 1197 `mrms_ok` / leftover 1263 `mrmsx_ok` / leftover 1329 `mrmsxx_ok`. Timed work is default / miss model-selector layout. Observed `rms_default` / `rms_miss` are exact. First n=5 freeze **27.467×** (196.853 / 7.167 µs) on host `cursor`, ceiling 50.0 matching leftover 1329. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1396 — `cli_selectors` (thafxxx_ok)
| `thafxxx_ok` | `thinking-selector-apply-filter` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector applyFilter |
Leftover sibling of leftover 1330–1332 on the same needs-pair file (sixth unused slug after leftover 1042 `th_af` / leftover 1117 `af_ok` / leftover 1198 `thaf_ok` / leftover 1264 `thafx_ok` / leftover 1330 `thafxx_ok`). Does not remount `thinking_selector_apply_filter`. Timed work is high / empty apply-filter. Observed `tsaf_high` / `tsaf_empty` are exact. First n=5 freeze **1.251×** (13.551 / 10.831 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1397 — `cli_selectors` (thclxxx_ok)
| `thclxxx_ok` | `thinking-selector-clamp-selected` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector clamp selected |
Leftover sibling of Pair 1396. Does not remount `thinking_selector_clamp_selected` / leftover 1042 `th_cl` / leftover 1118 `cl_ok` / leftover 1199 `thcl_ok` / leftover 1265 `thclx_ok` / leftover 1331 `thclxx_ok`. Timed work is high / zero clamp. Observed `tscl_high` / `tscl_zero` are exact. First n=5 freeze **0.854×** (0.650 / 0.761 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1398 — `cli_selectors` (thscxxx_ok)
| `thscxxx_ok` | `thinking-selector-select-current` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector select current |
Leftover sibling of Pairs 1396–1397. Does not remount `thinking_selector_select_current` / leftover 1042 `th_sc` / leftover 1119 `sc_ok` / leftover 1200 `thsc_ok` / leftover 1266 `thscx_ok` / leftover 1332 `thscxx_ok`. Timed work is high / only select-current. Observed `tssc_high` / `tssc_only` are exact. First n=5 freeze **0.837×** (0.984 / 1.176 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1399 — `cli_selectors` (thmvxxx_ok)
| `thmvxxx_ok` | `thinking-selector-move` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector wrap selected |
Leftover sibling of leftover 1333–1335 on the same needs-pair file (unused slug after leftover 1045 `th_mv` / leftover 1120 `mv_ok` / leftover 1201 `thmv_ok` / leftover 1267 `thmvx_ok` / leftover 1333 `thmvxx_ok`). Does not remount `thinking_selector_move`. Timed work is down / wrap. Observed `tsmv_down` / `tsmv_up_wrap` are exact. First n=5 freeze **1.675×** (0.633 / 0.378 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1400 — `cli_selectors` (thhrxxx_ok)
| `thhrxxx_ok` | `thinking-selector-handle-raw-input` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector handleInput keybindings |
Leftover sibling of Pair 1399. Does not remount `thinking_selector_handle_raw_input` / leftover 1045 `th_hri` / leftover 1121 `hri_ok` / leftover 1202 `thhr_ok` / leftover 1268 `thhrx_ok` / leftover 1334 `thhrxx_ok`. Timed work is down / save keybindings. Observed `tshri_down` / `tshri_save` are exact. First n=5 freeze **23.939×** (143.544 / 5.996 µs) on host `cursor`, ceiling 30.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1401 — `cli_selectors` (thhexxx_ok)
| `thhexxx_ok` | `thinking-selector-handle-event` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector typed input event dispatch |
Leftover sibling of Pairs 1399–1400. Does not remount `thinking_selector_handle_event` / leftover 1363 `henxxx_ok` / leftover 1045 `th_hev` / leftover 1122 `hev_ok` / leftover 1203 `thhe_ok` / leftover 1269 `thhex_ok` / leftover 1335 `thhexx_ok`. Timed work is down / text dispatch. Observed `tshe_down` / `tshe_text` are exact. First n=5 freeze **0.914×** (3.238 / 3.542 µs) on host `cursor`, ceiling 8.0. Under-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1402 — `cli_selectors` (trsvxxx_ok)
| `trsvxxx_ok` | `trust-option-saved-p` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of trust-selector isSavedOption |
Leftover sibling of leftover 1336–1338 on the same needs-pair file (unused slug after leftover 1048 `tr_sv` / leftover 1123 `sv_ok` / leftover 1204 `trsv_ok` / leftover 1270 `trsvx_ok` / leftover 1336 `trsvxx_ok`). Does not remount `trust_option_saved_p`. Timed work is nil / distrust saved-option. Observed `tosp_nil` / `tosp_distrust` are exact. First n=5 freeze **5.065×** (76.972 / 15.197 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1403 — `cli_selectors` (trmkxxx_ok)
| `trmkxxx_ok` | `make-trust-selector-state` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of TrustSelectorComponent constructor |
Leftover sibling of Pair 1402. Does not remount `make_trust_selector_state` / leftover 1048 `tr_mk` / leftover 1124 `mk_ok` / leftover 1205 `trmk_ok` / leftover 1271 `trmkx_ok` / leftover 1337 `trmkxx_ok`. Timed work is child / single constructor. Observed `mtss_child` / `mtss_single` are exact. First n=5 freeze **2.552×** (131.369 / 51.480 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1404 — `cli_selectors` (trrsxxx_ok)
| `trrsxxx_ok` | `render-trust-selector` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of TrustSelectorComponent layout |
Leftover sibling of Pairs 1402–1403. Does not remount `render_trust_selector` / leftover 1048 `tr_rnd` / leftover 1125 `trn_ok` / leftover 1206 `trrs_ok` / leftover 1272 `trrsx_ok` / leftover 1338 `trrsxx_ok`. Timed work is default / single layout. Observed `rtrs_default` / `rtrs_single` are exact. First n=5 freeze **9.157×** (1023.386 / 111.757 µs) on host `cursor`, ceiling 15.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1405 — `cli_selectors` (lmsxxxx_ok)
| `lmsxxxx_ok` | `make-login-method-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of ExtensionSelector login-method constructor |
Leftover sibling of leftover 1339–1341 on the same needs-pair file (unused slug after leftover 1003 `mlms_ok` / leftover 1126 `lms_ok` / leftover 1207 `lmsx_ok` / leftover 1273 `lmsxx_ok` / leftover 1339 `lmsxxx_ok`). Does not remount `make_login_method_selector_state`. Timed work is default / three login-method constructors. Observed `mlms_default` / `mlms_three` are exact. First n=5 freeze **1.274×** (2.681 / 2.105 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1406 — `cli_selectors` (akixxxx_ok)
| `akixxxx_ok` | `make-api-key-input-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showPrompt api key Input constructor |
Leftover sibling of Pair 1405. Does not remount `make_api_key_input_state` / leftover 1003 `makis_ok` / leftover 1127 `aki_ok` / leftover 1208 `akix_ok` / leftover 1274 `akixx_ok` / leftover 1340 `akixxx_ok`. Timed work is anthropic / named constructors. Observed `makis_anth` / `makis_named` are exact. First n=5 freeze **2.039×** (2.164 / 1.061 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 1407 — `cli_selectors` (ossxxxx_ok)
| `ossxxxx_ok` | `make-oauth-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of OauthSelectorComponent constructor |
Leftover sibling of Pairs 1405–1406. Does not remount `make_oauth_selector_state` / leftover 1003 `moss_ok` / leftover 1128 `oss_ok` / leftover 1209 `ossx_ok` / leftover 1275 `ossxx_ok` / leftover 1341 `ossxxx_ok`. Timed work is default / logout constructors. Observed `moss_default` / `moss_logout` are exact. First n=5 freeze **1.340×** (7.239 / 5.400 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 760 — `settings_load` (read_cli_config)
| `read_cli_config` | `read-cli-config` (`src/cadr-cli/config.lisp`) | JSON.parse settings.json object (`packages/coding-agent/src/config.ts`) |
Leftover sibling on a different needs-pair file. Timed work is missing/object/bad/array config.json — not `stream-chat`. Observed `rcc_miss` / `rcc_hit` / `rcc_bad` / `rcc_arr` / `rcc_n` are exact. First n=5 freeze **2.098×** (200.606 / 95.628 µs) on host `cursor`; remesure Friend-MachineD **1.188×** (260.569 / 219.256 µs), ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 761 — `settings_load` (provider_config_secrets)
| `provider_config_secrets` | `provider-config-secrets` (`src/cadr-cli/config.lisp`) | apiKey/oauth/env secret collect (`packages/coding-agent/src/config.ts`) |
Leftover sibling of Pair 760. Timed work is provider plus environment secret collection — not login I/O. Observed `pcs_key` / `pcs_oauth` / `pcs_env` / `pcs_nil` / `pcs_n` are exact. First n=5 freeze **43.688×** (59.914 / 1.371 µs) on host `cursor`; remesure Friend-MachineD **33.085×** (61.333 / 1.854 µs), ceiling 50.0 first-freeze headroom. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 762 — `settings_load` (resolve_provider_config)
| `resolve_provider_config` | `resolve-provider-config` (`src/cadr-cli/config.lisp`) | `openaiProvider` construct (`packages/ai/src/providers/openai.ts`) |
Leftover sibling of Pairs 760–761. Timed work is constructing openai with an explicit CLI key — not `stream-chat`. Observed `rpc_name` / `rpc_cli` / `rpc_model` / `rpc_type` / `rpc_n` are exact. First n=5 freeze **5.300×** (225.982 / 42.635 µs) on host `cursor`; remesure Friend-MachineD **1.031×** (208.703 / 202.485 µs), ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 757 — `package_manager` (records_project_first)
| `records_project_first` | `package-update-records-project-first` (`src/cadr-cli/packages/update-checks.lisp`) | project-then-user collect (`packages/coding-agent/src/core/package-manager.ts` `checkForAvailableUpdates`) |
Leftover sibling on a different needs-pair file. Timed work is reordering user/project/user records so project comes first — not git ls-remote. Observed `upf_proj` / `upf_user` / `upf_tail` / `upf_len` / `upf_n` are exact. First n=5 freeze **0.614×** (0.433 / 0.706 µs) on host `cursor`; remesure Friend-MachineD **1.059×** (0.576 / 0.544 µs), ceiling 8.0. Over-1× booked on Friend-MachineD. Same commit no optimize. `nextPairNum` left at 328.
### Pair 758 — `package_manager` (candidate_record)
| `candidate_record` | `package-update-candidate-record-p` (`src/cadr-cli/packages/update-checks.lisp`) | git/unpinned/exists filter (`packages/coding-agent/src/core/package-manager.ts` `checkForAvailableUpdates`) |
Leftover sibling of Pair 757. Timed work is git vs pinned vs npm vs missing path — not ls-remote. Observed `upc_git` / `upc_pin` / `upc_npm` / `upc_miss` / `upc_n` are exact. First n=5 freeze **17.132×** (30.746 / 1.795 µs) on host `cursor`; remesure Friend-MachineD **3.048×** (7.755 / 2.544 µs), ceiling 20.0 first-freeze headroom. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 759 — `package_manager` (update_offline)
| `update_offline` | `check-for-available-package-updates` (`src/cadr-cli/packages/update-checks.lisp`) | `isOfflineModeEnabled` short-circuit (`packages/coding-agent/src/core/package-manager.ts` `checkForAvailableUpdates`) |
Leftover sibling of Pairs 757–758. Timed work is offline short-circuit and empty-record no-op — not git. Observed `uoff_off` / `uoff_empty_off` / `uoff_empty` / `uoff_run` / `uoff_n` are exact. First n=5 freeze **1.316×** (0.333 / 0.253 µs) on host `cursor`; remesure Friend-MachineD **1.568×** (0.416 / 0.266 µs), ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 766 — `settings_load` (sdk_http_idle_timeout)
| `sdk_http_idle_timeout` | `sdk-settings-http-idle-timeout-ms` (`src/cadr-cli/sdk/settings-service.lisp`) | `SettingsManager.getHttpIdleTimeoutMs` (`packages/coding-agent/src/core/settings-manager.ts`) |
Leftover sibling of Pairs 763–765. Timed work is in-memory idle timeout parse — not `stream-chat`. Observed `shi_hit` / `shi_def` / `shi_bad` / `shi_int` / `shi_n` are exact. First n=5 freeze **1.249×** (10.990 / 8.800 µs) on host `cursor`; remesure Friend-MachineD **1.412×** (11.259 / 7.976 µs), ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 767 — `settings_load` (sdk_apply_overrides)
| `sdk_apply_overrides` | `sdk-settings-apply-overrides` (`src/cadr-cli/sdk/settings-service.lisp`) | `SettingsManager.applyOverrides` (`packages/coding-agent/src/core/settings-manager.ts`) |
Leftover sibling of Pair 766. Timed work is overlay merge last-wins — not login I/O. Observed `sao_prov` / `sao_last` / `sao_len` / `sao_base` / `sao_n` are exact. First n=5 freeze **6.960×** (45.476 / 6.534 µs) on host `cursor`; remesure Friend-MachineD **7.583×** (47.291 / 6.236 µs), ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 768 — `settings_load` (sdk_model_thinking_level)
| `sdk_model_thinking_level` | `sdk-settings-model-thinking-level` (`src/cadr-cli/sdk/settings-service.lisp`) | `SettingsManager.getModelThinkingLevel` (`packages/coding-agent/src/core/settings-manager.ts`) |
Leftover sibling of Pairs 766–767. Timed work is per-model thinking lookup — not `stream-chat`. Observed `smt_hit` / `smt_miss` / `smt_other` / `smt_sym` / `smt_n` are exact. First n=5 freeze **4.323×** (16.293 / 3.769 µs) on host `cursor`; remesure Friend-MachineD **5.346×** (16.830 / 3.148 µs), ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 769 — `settings_load` (sdk_settings_value)
| `sdk_settings_value` | `sdk-settings-value` (`src/cadr-cli/sdk/settings-service.lisp`) | Settings object json-get replica (`packages/coding-agent/src/core/settings-manager.ts`) |
Leftover sibling of Pairs 766–768. Timed work is in-memory json-get hit/miss/default — not login I/O. Observed `ssv_hit` / `ssv_miss` / `ssv_def` / `ssv_ok` / `ssv_n` are exact. First n=5 freeze **114.678×** (33.477 / 0.292 µs) on host `cursor`, ceiling 150.0. Over-1× booked. Gate `--only-enforce`; py rc=2 from known METRICS observed-key pollution (`parsed_provider`); this metric did not fail observed-exact. Same commit no optimize. `nextPairNum` left at 328.
### Pair 770 — `settings_load` (sdk_default_thinking_level)
| `sdk_default_thinking_level` | `sdk-settings-default-thinking-level` (`src/cadr-cli/sdk/settings-service.lisp`) | `SettingsManager.getDefaultThinkingLevel` (`packages/coding-agent/src/core/settings-manager.ts`) |
Leftover sibling of Pair 769. Timed work is defaultThinkingLevel lookup. Empty cadr returns `:medium`; pi returns `undefined` — encoded as cadr `eq :medium` → 1 and pi `== null` → 1. Invalid `"nope"` is not an exact key. Observed `sdt_high` / `sdt_off` / `sdt_empty` / `sdt_ok` / `sdt_n` are exact. First n=5 freeze **2.541×** (10.345 / 4.072 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 771 — `settings_load` (sdk_drain_errors)
| `sdk_drain_errors` | `sdk-settings-drain-errors` (`src/cadr-cli/sdk/settings-service.lisp`) | `SettingsManager.drainErrors` (`packages/coding-agent/src/core/settings-manager.ts`) |
Leftover sibling of Pairs 769–770. Timed work is empty-memory drain by length — not `listp` vs `Array.isArray([])`, not `flush()`. Observed `sde_len` / `sde_empty` / `sde_again` / `sde_ok` / `sde_n` are exact. First n=5 freeze **0.806×** (1.002 / 1.244 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate `--only-enforce`; py rc=2 from known METRICS pollution. Same commit no optimize. `nextPairNum` left at 328.
### Pair 772 — `settings_load` (sdk_effective_object)
| `sdk_effective_object` | `sdk-settings-effective-object` (`src/cadr-cli/sdk/settings-service.lisp`) | Settings object merge replica (`packages/coding-agent/src/core/settings-manager.ts`) |
Leftover sibling of Pairs 769–771. Timed work is in-memory merged settings object — not login I/O. Observed `seo_prov` / `seo_model` / `seo_empty` / `seo_obj` / `seo_n` are exact. First n=5 freeze **86.669×** (15.846 / 0.183 µs) on host `cursor`, ceiling 100.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 773 — `settings_load` (sdk_settings_set)
| `sdk_settings_set` | `sdk-settings-set` (`src/cadr-cli/sdk/settings-service.lisp`) | `SettingsManager.setDefaultProvider` / `setDefaultModel` / `setTheme` (`packages/coding-agent/src/core/settings-manager.ts`) |
Leftover sibling of Pair 772. Timed work is in-memory set (nil path; no `settings.json` write). Observed `sss_prov` / `sss_model` / `sss_theme` / `sss_str` / `sss_n` are exact. First n=5 freeze **2.210×** (17.925 / 8.113 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 774 — `settings_load` (sdk_settings_remove)
| `sdk_settings_remove` | `sdk-settings-remove` (`src/cadr-cli/sdk/settings-service.lisp`) | Settings object delete-key replica (`packages/coding-agent/src/core/settings-manager.ts`) |
Leftover sibling of Pairs 772–773. Timed work is memory remhash; pi has no generic `remove`. Observed `ssr_miss` / `ssr_keep` / `ssr_ret` / `ssr_val` / `ssr_n` are exact. First n=5 freeze **35.830×** (32.715 / 0.913 µs) on host `cursor`, ceiling 40.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 775 — `settings_load` (sdk_settings_reload)
| `sdk_settings_reload` | `sdk-settings-reload` (`src/cadr-cli/sdk/settings-service.lisp`) | `SettingsManager.reload` (`packages/coding-agent/src/core/settings-manager.ts`) |
Leftover sibling of Pairs 772–774. Timed work is in-memory reload (nil path; no `settings.json` read). cadr returns the manager; pi resolves to `undefined` — encoded as cadr `eq` manager → 1 and pi `== null` → 1. Observed `srl_hit` / `srl_model` / `srl_same` / `srl_empty` / `srl_n` are exact. First n=5 freeze **4.144×** (24.265 / 5.855 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 776 — `settings_load` (sdk_settings_flush)
| `sdk_settings_flush` | `sdk-settings-flush` (`src/cadr-cli/sdk/settings-service.lisp`) | `SettingsManager.flush` (`packages/coding-agent/src/core/settings-manager.ts`) |
Leftover sibling of Pair 775. Timed work is flush identity vs `await flush()`. Do not compare manager vs Promise. Observed `sfl_hit` / `sfl_model` / `sfl_same` / `sfl_empty` / `sfl_n` are exact. First n=5 freeze **5.937×** (26.442 / 4.454 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 777 — `settings_load` (sdk_compaction_enabled)
| `sdk_compaction_enabled` | `sdk-settings-compaction-enabled-p` (`src/cadr-cli/sdk/settings-service.lisp`) | `SettingsManager.getCompactionEnabled` (`packages/coding-agent/src/core/settings-manager.ts`) |
Leftover sibling of Pairs 775–776. Timed work is compaction enabled default/true/false — not login I/O. Observed `sce_on` / `sce_off` / `sce_def` / `sce_eq` / `sce_n` are exact. First n=5 freeze **3.643×** (17.188 / 4.718 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 778 — `evals_harness` (matching_hello_call)
| `matching_hello_call` | `matching-hello-tool-call-p` (`src/cadr-evals/suites.lisp`) | ExtensionAuthoringJudge hello-call replica (`packages/evals/src/extensions.eval.ts`) |
Leftover sibling of Pairs 700–702. Timed work is the hello({name:Bob}) event walk — not live eval, not rationale copy. Observed `mh_hit` / `mh_alice` / `mh_empty` / `mh_no_res` / `mh_n` are exact. First n=5 freeze **2.600×** (5.560 / 2.138 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Gate used `--only-enforce`. Same commit no optimize. `nextPairNum` left at 328.
### Pair 779 — `evals_harness` (authoring_judge)
| `authoring_judge` | `judge-extension-authoring-result` (`src/cadr-evals/suites.lisp`) | ExtensionAuthoringJudge replica (`packages/evals/src/extensions.eval.ts`) |
Leftover sibling of Pair 778. Timed work is judge score (pass / missing source / non-canonical API / wrong response). Do not compare rationale product copy. Observed `aj_pass` / `aj_src` / `aj_api` / `aj_resp` / `aj_n` are exact. First n=5 freeze **2.331×** (16.713 / 7.170 µs) on host `cursor`, ceiling 8.0. Over-1× booked. Gate used `--only-enforce`. Same commit no optimize. `nextPairNum` left at 328.
### Pair 780 — `evals_harness` (source_bundle)
| `source_bundle` | `extension-source-bundle` (`src/cadr-evals/suites.lisp`) | hello-tool bundle pick replica (`packages/evals/src/extensions.eval.ts`) |
Leftover sibling of Pairs 778–779. Timed work is pick hello bundle else first — not `read-extension-source` path I/O. Observed `esb_hello` / `esb_first` / `esb_empty` / `esb_tools` / `esb_n` are exact. First n=5 freeze **0.465×** (0.776 / 1.671 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Same commit no optimize. `nextPairNum` left at 328.
### Pair 781 — `package_manager` (resource_item_key)
| `resource_item_key` | `config-resource-item-key` (`src/cadr-cli/packages/config-selector.lisp`) | leftover `getResourceItemKey` replica (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |
Leftover sibling of Pairs 736–738 on the same `config-selector.lisp` `package_manager` hole. Timed work is type-prefixed item key (`extensions:` / `skills:` plus path) — not TUI render, not directory discovery. Observed `rik_ext` / `rik_skill` / `rik_diff` / `rik_hello` / `rik_n` are exact. First n=5 freeze **23.49×** (15.782 / 0.672 µs) on host `cursor`, ceiling 50.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 782 — `package_manager` (project_override_state)
| `project_override_state` | `config-selector-project-state` (`src/cadr-cli/packages/config-selector.lisp`) | leftover override-hash replica (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |
Leftover sibling of Pair 781. Timed work is hash lookup load/unload/inherit — not `getProjectOverrideState` settings walk. Observed `cps_load` / `cps_unload` / `cps_miss` / `cps_eq` / `cps_n` are exact. First n=5 freeze **17.17×** (44.722 / 2.605 µs) on host `cursor`, ceiling 20.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 783 — `package_manager` (next_project_state)
| `next_project_state` | `config-selector-next-project-state` (`src/cadr-cli/packages/config-selector.lisp`) | leftover `nextProjectOverrideState` replica (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |
Leftover sibling of Pairs 781–782. Timed work is inherit/unload/load cycle given inherited-enabled — not TUI checkbox. Observed `nps_inh_t` / `nps_inh_f` / `nps_unl` / `nps_load` / `nps_n` are exact. First n=5 freeze **9.35×** (40.473 / 4.330 µs) on host `cursor`, ceiling 15.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 784 — `package_manager` (inherited_enabled)
| `inherited_enabled` | `config-selector-inherited-enabled-p` (`src/cadr-cli/packages/config-selector.lisp`) | leftover inheritedEnabled map (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |
Leftover sibling of Pairs 781–783 on the same `config-selector.lisp` `package_manager` hole. Timed work is inherited-enabled hash lookup plus item `enabled-p` default — not TUI checkbox. Observed `ie_hash_t` / `ie_hash_f` / `ie_def_t` / `ie_def_f` / `ie_n` are exact. First n=5 freeze **7.81×** (28.743 / 3.682 µs) on host `cursor`, ceiling 20.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 785 — `package_manager` (resource_group_key)
| `resource_group_key` | `config-resource-group-key` (`src/cadr-cli/packages/config-selector.lisp`) | leftover group-key replica (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |
Leftover sibling of Pair 784. Timed work is `origin:scope:source:` prefix of the group key — not TUI label, not directory walk. Observed `rgk_top` / `rgk_pkg` / `rgk_src` / `rgk_diff` / `rgk_n` are exact. First n=5 freeze **16.47×** (12.761 / 0.775 µs) on host `cursor`, ceiling 50.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 786 — `package_manager` (package_entry_index)
| `package_entry_index` | `config-selector-package-entry-index` (`src/cadr-cli/packages/config-selector.lisp`) | leftover npm identity index (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |
Leftover sibling of Pairs 784–785. Timed work is npm package-source identity position (hit / first / miss / scoped pin) — not git/local path I/O. Observed `pei_hit` / `pei_first` / `pei_miss` / `pei_pin` / `pei_n` are exact. First n=5 freeze **7.45×** (14.402 / 1.934 µs) on host `cursor`, ceiling 20.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 787 — `package_manager` (project_package_entry)
| `project_package_entry` | `config-selector-project-package-entry` (`src/cadr-cli/packages/config-selector.lisp`) | leftover project npm identity find (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |
Leftover sibling of Pairs 784–786 on the same `config-selector.lisp` `package_manager` hole. Timed work is project-settings identity find (hit / miss / scoped pin) — not TUI, not directory walk. Observed `ppe_hit` / `ppe_miss` / `ppe_pin` / `ppe_eq` / `ppe_n` are exact. First n=5 freeze **6.71×** (18.051 / 2.691 µs) on host `cursor`, ceiling 15.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 788 — `package_manager` (project_package_state)
| `project_package_state` | `config-selector-project-package-state` (`src/cadr-cli/packages/config-selector.lisp`) | leftover project package filter walk (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |
Leftover sibling of Pair 787. Timed work is load/unload/inherit from `+-!` exact pattern match plus empty-filter unload — not TUI checkbox. Observed `pps_load` / `pps_unload` / `pps_miss` / `pps_nofilter` / `pps_n` are exact. First n=5 freeze **7.90×** (25.317 / 3.203 µs) on host `cursor`, ceiling 15.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 789 — `package_manager` (package_setting_record)
| `package_setting_record` | `config-package-setting-record` (`src/cadr-cli/packages/config-selector.lisp`) | leftover npm setting record (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |
Leftover sibling of Pairs 787–788. Timed work is npm record identity / nil path / autoload-disabled — not git/local install path I/O. Observed `psr_npm` / `psr_id` / `psr_path` / `psr_auto` / `psr_n` are exact. First n=5 freeze **11.91×** (10.399 / 0.873 µs) on host `cursor`, ceiling 40.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 790 — `package_manager` (package_setting_records)
| `package_setting_records` | `config-package-setting-records` (`src/cadr-cli/packages/config-selector.lisp`) | leftover npm records merge (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |
Leftover sibling of Pair 789 on the same `config-selector.lisp` `package_manager` hole. Timed work is global+project npm record merge (length / scopes / global-only) — not git/local install I/O. Observed `psrs_len` / `psrs_user` / `psrs_proj` / `psrs_glob` / `psrs_n` are exact. First n=5 freeze **5.64×** (22.779 / 4.036 µs) on host `cursor`, ceiling 15.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 791 — `package_manager` (selector_rebuild)
| `selector_rebuild` | `config-selector-rebuild` (`src/cadr-cli/packages/config-selector.lisp`) | leftover selector flat rebuild (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |
Leftover sibling of Pair 790. Timed work is group/item flatten from pre-seeded items plus query miss — not `make-config-selector-state` directory walk, not TUI render. Observed `crb_group` / `crb_items` / `crb_sel` / `crb_query` / `crb_n` are exact. First n=5 freeze **5.89×** (26.127 / 4.435 µs) on host `cursor`, ceiling 15.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 792 — `package_manager` (switch_scope)
| `switch_scope` | `config-selector-switch-scope` (`src/cadr-cli/packages/config-selector.lisp`) | leftover selector scope flip (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |
Leftover sibling of Pair 791. Timed work is write-scope flip plus rebuild (project / global / unavailable no-op / package item) — not TUI tab handler. Observed `css_proj` / `css_glob` / `css_nop` / `css_pkg` / `css_n` are exact. First n=5 freeze **6.03×** (36.289 / 6.020 µs) on host `cursor`, ceiling 12.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 793 — `evals_harness` (bundle_tool_names)
| `bundle_tool_names` | `extension-bundle-tool-names` (`src/cadr-evals/suites.lisp`) | leftover bundle tool-name list (`packages/evals/src/extensions.eval.ts`) |
Leftover sibling of Pairs 778–780 on the same `suites.lisp` `evals_harness` hole. Timed work is tool-name list (hello / multi / empty / unequal) — not `read-extension-source` path I/O. Observed `ebt_hello` / `ebt_multi` / `ebt_empty` / `ebt_eq` / `ebt_n` are exact. First n=5 freeze **0.969×** (1.001 / 1.033 µs) on host `cursor`, ceiling 8.0. cadr leads. Gate used `--only-enforce`. Same commit no optimize. `nextPairNum` left at 328.
### Pair 794 — `evals_harness` (visible_extension_bundles)
| `visible_extension_bundles` | `visible-extension-bundles` (`src/cadr-evals/suites.lisp`) | leftover hidden-p filter (`packages/evals/src/extensions.eval.ts`) |
Leftover sibling of Pair 793. Timed work is drop `hidden-p` bundles from a memory snapshot — not directory discovery, not TUI. Observed `veb_vis` / `veb_hid` / `veb_empty` / `veb_nvis` / `veb_n` are exact. First n=5 freeze **21.59×** (12.635 / 0.585 µs) on host `cursor`, ceiling 25.0 first-freeze headroom. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 795 — `evals_harness` (authoring_harness_table)
| `authoring_harness_table` | `extension-authoring-harness-table` (`src/cadr-evals/suites.lisp`) | leftover two-row authoring table (`packages/evals/src/extensions.eval.ts`) |
Leftover sibling of Pairs 793–794. Timed work is construct the two named rows (system-prompt-without-docs / default-system-prompt, repetition 1) — do not invoke `:run`. Observed `eht_len` / `eht_base` / `eht_cand` / `eht_rep` / `eht_n` are exact. First n=5 freeze **4.301×** (0.880 / 0.205 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 796 — `package_manager` (git_output)
| `git_output` | `package-update-git-output` (`src/cadr-cli/packages/update-checks.lisp`) | leftover git argv runner (`packages/coding-agent/src/core/package-manager.ts`) |
Leftover sibling of Pairs 757–759 on the same `update-checks.lisp` `package_manager` hole. Timed work is `git -C path` argv plus runner reply — not git spawn. Observed `pug_git` / `pug_cwd` / `pug_rev` / `pug_out` / `pug_n` are exact. First n=5 freeze **14.54×** (3.208 / 0.221 µs) on host `cursor`, ceiling 120.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 797 — `package_manager` (remote_ref)
| `remote_ref` | `package-update-remote-ref` (`src/cadr-cli/packages/update-checks.lisp`) | leftover origin/ upstream ref (`packages/coding-agent/src/core/package-manager.ts`) |
Leftover sibling of Pair 796. Timed work is origin/ prefix to `refs/heads/` — not `ls-remote` spawn. Observed `pur_main` / `pur_feat` / `pur_plain` / `pur_empty` / `pur_n` are exact. First n=5 freeze **4.082×** (4.714 / 1.155 µs) on host `cursor`, ceiling 25.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 798 — `package_manager` (update_record_result)
| `update_record_result` | `package-update-record-result` (`src/cadr-cli/packages/update-checks.lisp`) | leftover host/path update result (`packages/coding-agent/src/core/package-manager.ts`) |
Leftover sibling of Pairs 796–797. Timed work is host/path when mock oids differ, nil on match/error/bad oid — not git spawn. Observed `prr_hit` / `prr_same` / `prr_err` / `prr_bad` / `prr_n` are exact. First n=5 freeze **1.814×** (11.610 / 6.399 µs) on host `cursor`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 799 — `package_manager` (selector_hint)
| `selector_hint` | `config-selector-hint` (`src/cadr-cli/packages/config-selector.lisp`) | leftover keyHint wrap (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |
Leftover sibling of leftover 790–792 on the same `config-selector.lisp` `package_manager` hole. Timed work is dim key plus muted description — not `config-selector-header-lines` / `render-entry`. Observed `csh_tab` / `csh_space` / `csh_esc` / `csh_empty` / `csh_n` are exact. First n=5 freeze **15.49×** (10.635 / 0.687 µs) on host `cursor`, ceiling 20.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 800 — `package_manager` (override_suffix)
| `override_suffix` | `config-selector-override-suffix` (`src/cadr-cli/packages/config-selector.lisp`) | leftover getItemSuffix (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |
Leftover sibling of Pair 799. Timed work is project load/unload/inherit suffix strings — not writers, not full TUI. Observed `cos_load` / `cos_unload` / `cos_global` / `cos_inh` / `cos_n` are exact. First n=5 freeze **9.075×** (35.220 / 3.881 µs) on host `cursor`, ceiling 25.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 801 — `package_manager` (checkbox)
| `checkbox` | `config-selector-checkbox` (`src/cadr-cli/packages/config-selector.lisp`) | leftover renderCheckbox (`packages/coding-agent/src/modes/interactive/components/config-selector.ts`) |
Leftover sibling of Pairs 799–800. Timed work is `[x]` / `[ ]` / `[+]` / `[-]` marks — not `render-entry`. Observed `ccb_on` / `ccb_off` / `ccb_plus` / `ccb_minus` / `ccb_n` are exact. First n=5 freeze **10.47×** (36.479 / 3.484 µs) on host `cursor`, ceiling 25.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 802 — `cli_extensions_install` (string_prefix)
| `string_prefix` | `string-prefix-p` (`src/cadr-cli/extensions/installer.lisp`) | leftover startsWith (`packages/coding-agent/src/utils/git.ts`) |
Leftover sibling of leftover 499–501 on the same `installer.lisp` `cli_extensions_install` hole. Timed work is case-sensitive prefix — not `unsafe-git-source-p`, not git spawn. Observed `sp_git` / `sp_http` / `sp_case` / `sp_empty` / `sp_n` are exact. First n=5 freeze **1.109×** (0.236 / 0.213 µs) on host `Friend-MachineD`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 803 — `cli_extensions_install` (split_path_segments)
| `split_path_segments` | `split-path-segments` (`src/cadr-cli/extensions/installer.lisp`) | leftover split("/") (`packages/coding-agent/src/utils/git.ts`) |
Leftover sibling of Pair 802. Timed work is slash split including empty segments — not `unsafe-git-source-p`, not git spawn. Observed `sps_dot` / `sps_empty` / `sps_nseg` / `sps_blank` / `sps_n` are exact. First n=5 freeze **2.742×** (0.885 / 0.323 µs) on host `Friend-MachineD`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 804 — `cli_extensions_install` (strip_git_query)
| `strip_git_query` | `strip-git-query-and-ref` (`src/cadr-cli/extensions/installer.lisp`) | leftover strip query/hash (`packages/coding-agent/src/utils/git.ts`) |
Leftover sibling of Pairs 802–803. Timed work is strip at first `?` or `#` — not git spawn. Observed `sgq_q` / `sgq_hash` / `sgq_plain` / `sgq_both` / `sgq_n` are exact. First n=5 freeze **2.811×** (0.697 / 0.248 µs) on host `Friend-MachineD`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 805 — `cli_extensions_install` (llama_format_context)
| `llama_format_context` | `llama-format-context-size` (`src/cadr-cli/extensions/llama/ui.lisp`) | leftover Math.round k (`packages/coding-agent/src/extensions/llama/ui.ts`) |
Leftover sibling of leftover 544–546 on the same `llama/ui.lisp` `cli_extensions_install` hole. Timed work is k-suffix rounding — not `llama-context-label` TUI, not view frames. Observed `lfc_small` / `lfc_1k` / `lfc_8k` / `lfc_round` / `lfc_n` are exact. First n=5 freeze **4.332×** (0.868 / 0.200 µs) on host `Friend-MachineD`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 806 — `cli_extensions_install` (llama_js_to_fixed)
| `llama_js_to_fixed` | `llama-js-to-fixed` (`src/cadr-cli/extensions/llama/ui.lisp`) | leftover Number.toFixed (`packages/coding-agent/src/extensions/llama/ui.ts`) |
Leftover sibling of Pair 805. Timed work is toFixed digit strings — not compactCount TUI. Observed `ltf_one` / `ltf_zero` / `ltf_pi` / `ltf_ten` / `ltf_n` are exact. First n=5 freeze **3.076×** (1.301 / 0.423 µs) on host `Friend-MachineD`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 807 — `cli_extensions_install` (llama_search_exact)
| `llama_search_exact` | `llama-search-exact-query-p` (`src/cadr-cli/extensions/llama/ui.lisp`) | leftover org/name regex (`packages/coding-agent/src/extensions/llama/ui.ts`) |
Leftover sibling of Pairs 805–806. Timed work is org/name(:quant) regex — not search schedule, not TUI. Observed `lseq_ok` / `lseq_tag` / `lseq_space` / `lseq_slash` / `lseq_n` are exact. First n=5 freeze **4.086×** (0.945 / 0.231 µs) on host `Friend-MachineD`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 808 — `cli_bootstrap_sessions` (assistant_tool_call_only)
| `assistant_tool_call_only` | `assistant-tool-call-only-p` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover hasTextContent invert (`packages/coding-agent/src/modes/interactive/components/tree-selector.ts`) |
Leftover sibling of leftover 553–555 on the same `sessions.lisp` `cli_bootstrap_sessions` hole. Timed work is tool-call-only hide (tool present, no nonempty text) — not tree render. Observed `atco_none` / `atco_text` / `atco_tool` / `atco_both` / `atco_n` are exact. First n=5 freeze **2.121×** (1.423 / 0.671 µs) on host `Friend-MachineD`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 809 — `cli_bootstrap_sessions` (session_entry_user_text)
| `session_entry_user_text` | `session-entry-user-text` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover contentText user entry (`packages/coding-agent/src/core/agent-session.ts`) |
Leftover sibling of Pair 808. Timed work is string or text-block join for user message entries — not fork TUI. Observed `seut_str` / `seut_blocks` / `seut_asst` / `seut_empty` / `seut_n` are exact. First n=5 freeze **2.198×** (1.431 / 0.651 µs) on host `Friend-MachineD`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 810 — `cli_bootstrap_sessions` (session_compaction_status)
| `session_compaction_status` | `session-compaction-status` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover compaction count string (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |
Leftover sibling of Pairs 808–809. Timed work is `Session compacted N time(s)` — not `showStatus` TUI. Observed `scs_none` / `scs_one` / `scs_two` / `scs_zero` / `scs_n` are exact. First n=5 freeze **3.530×** (2.150 / 0.609 µs) on host `Friend-MachineD`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 811 — `cli_bootstrap_sessions` (last_assistant_text)
| `last_assistant_text` | `last-assistant-text` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover getLastAssistantText (`packages/coding-agent/src/core/agent-session.ts`) |
Leftover sibling of leftover 808–810 on the same `sessions.lisp` `cli_bootstrap_sessions` hole. Timed work is last non-aborted-empty assistant text join/trim — not clipboard TUI. Observed `lat_none` / `lat_hit` / `lat_skip` / `lat_ws` / `lat_n` are exact. First n=5 freeze **3.389×** (4.006 / 1.182 µs) on host `Friend-MachineD`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 812 — `cli_bootstrap_sessions` (session_export_basename)
| `session_export_basename` | `session-export-basename` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover APP_NAME-session ISO_id.html (`packages/coding-agent/src/core/export-html/index.ts`) |
Leftover sibling of Pair 811. Timed work is `cadr-session-{ISO}_{id}.html` with `[:.]` replaced — not HTML write. Observed `seb_epoch` / `seb_ms` / `seb_sec` / `seb_999` / `seb_n` are exact. First n=5 freeze **5.369×** (12.308 / 2.292 µs) on host `Friend-MachineD`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 813 — `cli_bootstrap_sessions` (session_user_messages_for_forking)
| `session_user_messages_for_forking` | `session-user-messages-for-forking` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover getUserMessagesForForking (`packages/coding-agent/src/core/agent-session.ts`) |
Leftover sibling of Pairs 811–812. Timed work is nonempty trimmed user-entry texts for fork — not fork TUI. Observed `sumf_none` / `sumf_n` / `sumf_first` / `sumf_id` / `sumf_last` are exact. First n=5 freeze **2.692×** (2.542 / 0.944 µs) on host `Friend-MachineD`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 814 — `cli_bootstrap_sessions` (session_command_stats)
| `session_command_stats` | `session-command-stats` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover getSessionStats (`packages/coding-agent/src/core/agent-session.ts`) |
Leftover sibling of leftover 808–813 on the same `sessions.lisp` `cli_bootstrap_sessions` hole. Timed work is user/assistant/tool-result/tool-call counts — not `/session` TUI. Observed `sst_empty_user` / `sst_user` / `sst_asst` / `sst_tr` / `sst_tc` are exact. First n=5 freeze **2.362×** (2.578 / 1.092 µs) on host `Friend-MachineD`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 815 — `cli_bootstrap_sessions` (session_usage_breakdown)
| `session_usage_breakdown` | `session-usage-breakdown` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover getUsageCostBreakdown (`packages/coding-agent/src/core/usage-totals.ts`) |
Leftover sibling of Pair 814. Timed work is provider/model and Tools/summaries token totals — not `/session` TUI. Observed `sub_empty` / `sub_n` / `sub_first` / `sub_tok` / `sub_second` are exact. First n=5 freeze **3.689×** (7.127 / 1.932 µs) on host `Friend-MachineD`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 816 — `cli_bootstrap_sessions` (session_tree_label_timestamps)
| `session_tree_label_timestamps` | `session-tree-label-timestamps` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover label timestamps (`packages/coding-agent/src/modes/interactive/components/tree-selector.ts`) |
Leftover sibling of Pairs 814–815. Timed work is nonempty label ISO map (empty label remhash) — not tree TUI. Observed `stl_empty` / `stl_n` / `stl_a` / `stl_b` / `stl_c` are exact. First n=5 freeze **2.873×** (4.218 / 1.468 µs) on host `Friend-MachineD`, ceiling 8.0. Gate used `--only-enforce`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 817 — `cli_bootstrap_sessions` (session_tree_tool_calls)
| `session_tree_tool_calls` | `session-tree-tool-calls` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover tool-call id→name map (`packages/coding-agent/src/modes/interactive/components/tree-selector.ts`) |
Leftover sibling of leftover 808–816 on the same `sessions.lisp` `cli_bootstrap_sessions` hole. Timed work is assistant tool-call id→name/arguments hash — not tree TUI. Observed `sttc_empty` / `sttc_n` / `sttc_t1` / `sttc_args` / `sttc_miss` are exact. First n=5 freeze **2.754×** (2.883 / 1.047 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 818 — `cli_bootstrap_sessions` (session_compaction_display_state)
| `session_compaction_display_state` | `session-compaction-display-state` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover display messages + nil summary/kept (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |
Leftover sibling of Pair 817. Timed work is message-only display projection returning `(messages nil nil)` — not `/compact` TUI. Fixture has no compaction entry (invalid first-kept-id errors). Observed `scds_empty` / `scds_n` / `scds_sum` / `scds_kept` / `scds_first` are exact. First n=5 freeze **3.286×** (3.306 / 1.006 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 819 — `cli_bootstrap_sessions` (write_hotkeys_command)
| `write_hotkeys_command` | `write-hotkeys-command` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover Keyboard Shortcuts list (`packages/coding-agent/src/modes/interactive/interactive-mode.ts`) |
Leftover sibling of Pairs 817–818. Timed work is fixed `Keyboard Shortcuts` plus `+interactive-hotkey-definitions+` (optional configured bindings) — not markdown keybinding tables. Observed `whc_plain` / `whc_hdr` / `whc_ctrlc` / `whc_bound` / `whc_cfg` are exact. First n=5 freeze **3.421×** (8.281 / 2.421 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 820 — `cli_bootstrap_sessions` (find_session_by_id_or_prefix)
| `find_session_by_id_or_prefix` | `find-session-by-id-or-prefix` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover find by id or prefix (`packages/coding-agent/src/core/session-manager.ts`) |
Leftover sibling of leftover 808–819 on the same `sessions.lisp` `cli_bootstrap_sessions` hole. Timed work is exact session-id then prefix match over an in-memory list — not `list-sessions` disk I/O. Observed `fsb_exact` / `fsb_prefix` / `fsb_xy` / `fsb_miss` / `fsb_empty` are exact. First n=5 freeze **1.888×** (1.627 / 0.862 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 821 — `cli_bootstrap_sessions` (session_display_messages)
| `session_display_messages` | `session-display-messages` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover display message projection (`packages/coding-agent/src/core/agent-session.ts`) |
Leftover sibling of Pair 820. Timed work is message-only context projection (parent chain + leaf/by-id) — not TUI. Observed `sdm_empty` / `sdm_n` / `sdm_first` / `sdm_asst` / `sdm_tool` are exact. First n=5 freeze **3.471×** (3.262 / 0.940 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 822 — `cli_bootstrap_sessions` (session_tree_selector_data)
| `session_tree_selector_data` | `session-tree-selector-data` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover tree row map (`packages/coding-agent/src/modes/interactive/components/tree-selector.ts`) |
Leftover sibling of Pairs 820–821. Timed work is tree row plists (id/text/leaf) — not tree TUI render. Observed `stsd_nil` / `stsd_n` / `stsd_leaf` / `stsd_id` / `stsd_text` are exact. First n=5 freeze **3.574×** (4.557 / 1.275 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 823 — `cli_bootstrap_sessions` (validate_cli_session_flags)
| `validate_cli_session_flags` | `validate-cli-session-flags` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover validateForkFlags/validateSessionIdFlags (`packages/coding-agent/src/cli/main.ts`) |
Leftover sibling of leftover 808–822 on the same `sessions.lisp` `cli_bootstrap_sessions` hole. Timed work is fork/`--session-id` conflict strings — not picker I/O. Observed `vcsf_ok` / `vcsf_fork` / `vcsf_fork2` / `vcsf_sid` / `vcsf_sidok` are exact. First n=5 freeze **5.366×** (2.825 / 0.526 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 824 — `cli_bootstrap_sessions` (session_entry_tree_selector_data)
| `session_entry_tree_selector_data` | `session-entry-tree-selector-data` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover one tree row (`packages/coding-agent/src/modes/interactive/components/tree-selector.ts`) |
Leftover sibling of Pair 823. Timed work is one tree row plist (id/role/text/type) — not tree TUI render. Observed `sets_id` / `sets_role` / `sets_text` / `sets_type` / `sets_asst` are exact. First n=5 freeze **4.596×** (4.460 / 0.970 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 825 — `cli_bootstrap_sessions` (session_restored_model)
| `session_restored_model` | `session-restored-model` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover restored model lookup (`packages/coding-agent/src/core/agent-session.ts`) |
Leftover sibling of Pairs 823–824. Timed work is last assistant/model-change lookup against an in-memory registry — not models.json I/O. Observed `srm_none` / `srm_hit` / `srm_noreg` / `srm_noavail` / `srm_wrong` are exact. First n=5 freeze **1.559×** (4.808 / 3.084 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 826 — `cli_extensions_install` (llama_search_status)
| `llama_search_status` | `llama-search-status-text` (`src/cadr-cli/extensions/llama/ui.lisp`) | leftover HuggingFaceSearch status (`packages/coding-agent/src/extensions/llama/ui.ts`) |
Leftover sibling of leftover 805–807 on the same `llama/ui.lisp` `cli_extensions_install` hole. Timed work is search status copy — not HF HTTP, not search TUI. Observed `lss_type` / `lss_search` / `lss_empty` / `lss_found` / `lss_n` are exact. First n=5 freeze **2.908×** (0.456 / 0.157 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **4.854×** (0.880 / 0.181 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 827 — `cli_extensions_install` (llama_search_filter)
| `llama_search_filter` | `llama-search-filter` (`src/cadr-cli/extensions/llama/ui.lisp`) | leftover filterResults (`packages/coding-agent/src/extensions/llama/ui.ts`) |
Leftover sibling of Pair 826. Timed work is in-memory result filter + selected clamp — not scheduleSearch debounce/HTTP. Observed `lsf_empty` / `lsf_miss` / `lsf_hit` / `lsf_sel` / `lsf_n` are exact. First n=5 freeze **0.472×** (3.792 / 8.027 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **0.602×** (4.961 / 8.243 µs) on host `Friend-MachineD`. Under 1× — not booked on over-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 828 — `cli_extensions_install` (llama_view_width)
| `llama_view_width` | `llama-view-width` (`src/cadr-cli/extensions/llama/ui.lisp`) | leftover last width (`packages/coding-agent/src/extensions/llama/ui.ts`) |
Leftover sibling of Pairs 826–827. Timed work is last-width slot — not frame TUI render. Observed `lvw_def` / `lvw_set` / `lvw_n` / `lvw_pos` / `lvw_eq` are exact. First n=5 freeze **149.278×** (27.079 / 0.181 µs) on host `cursor`, ceiling 180.0 (CLOS `make-llama-view` vs leftover replica lastWidth property). Remeasure on tip **114.091×** (27.891 / 0.244 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 829 — `cli_print_rpc` (dialog_default)
| `dialog_default` | `rpc-dialog-default` (`src/cadr-cli/modes/rpc/ui.lisp`) | leftover createDialogPromise defaultValue (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |
Leftover sibling of leftover 466–468 / 496–498 on the same `rpc/ui.lisp` `cli_print_rpc` hole. Timed work is the dialog default value — not wait, not TUI. Observed `rdd_sel` / `rdd_conf` / `rdd_in` / `rdd_ed` / `rdd_n` are exact. First n=5 freeze **0.524×** (0.072 / 0.137 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **0.699×** (0.173 / 0.248 µs) on host `Friend-MachineD`. Under 1× — not booked on over-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 830 — `cli_print_rpc` (dialog_deadline)
| `dialog_deadline` | `rpc-dialog-deadline` (`src/cadr-cli/modes/rpc/ui.lisp`) | leftover opts.timeout deadline (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |
Leftover sibling of Pair 829. Timed work is timeout-ms → deadline — not condition-wait. Observed `rdl_nil` / `rdl_fut` / `rdl_num` / `rdl_one` / `rdl_n` are exact. First n=5 freeze **0.593×** (0.108 / 0.181 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **0.702×** (0.230 / 0.328 µs) on host `Friend-MachineD`. Under 1× — not booked on over-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 831 — `cli_print_rpc` (close_pending)
| `close_pending` | `rpc-close-pending-dialogs` (`src/cadr-cli/modes/rpc/ui.lisp`) | leftover pendingExtensionRequests clear (`packages/coding-agent/src/modes/rpc/rpc-mode.ts`) |
Leftover sibling of Pairs 829–830. Timed work is closing-p + pending map clear — not listen, not HTTP. Observed `rcp_close` / `rcp_n` / `rcp_empty` / `rcp_empty_n` / `rcp_keys` are exact. First n=5 freeze **2.795×** (1.526 / 0.546 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **3.213×** (2.293 / 0.714 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 832 — `oauth_pkce_device` (hex_value)
| `hex_value` | `hex-value` (`src/cadr-ai/oauth/callback.lisp`) | leftover `parseInt` hex digit (`packages/ai/src/auth/oauth`) |
Leftover sibling of leftover percent_decode / parse_query / parse_callback_request on the same `callback.lisp` `oauth_pkce_device` hole. Timed work is a valid hex digit — not percent-decode, not listen. Observed `hv_A` / `hv_a` / `hv_0` / `hv_F` / `hv_9` / `hv_n` are exact. First n=5 freeze **0.371×** (0.142 / 0.384 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **0.692×** (0.272 / 0.392 µs) on host `Friend-MachineD`. Under 1× — not booked on over-1×. Same commit no optimize. `nextPairNum` left at 328.
### Pair 833 — `oauth_pkce_device` (write_http_response)
| `write_http_response` | `write-oauth-http-response` (`src/cadr-ai/oauth/callback.lisp`) | leftover `writeHead`+`end` (`packages/ai/src/auth/oauth/anthropic.ts`) |
Leftover sibling of Pair 832. Timed work is string-stream HTTP write — not sockets, not listen. Observed `woh_ok` / `woh_ct` / `woh_body` / `woh_400` / `woh_n` are exact. First n=5 freeze **8.881×** (5.964 / 0.672 µs) on host `cursor`, ceiling 12.0 (Lisp `format` HTTP framing vs leftover writeHead mock). Remeasure on tip **10.896×** (6.758 / 0.620 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 834 — `oauth_pkce_device` (present_auth_url)
| `present_auth_url` | `present-oauth-auth-url` (`src/cadr-ai/oauth/callback.lisp`) | leftover `auth_url` notify (`packages/ai/src/cli.ts`) |
Leftover sibling of Pairs 832–833. Timed work is URL print or callback — not browser open, not wait. Observed `pau_fmt` / `pau_url` / `pau_ret` / `pau_cb` / `pau_n` are exact. First n=5 freeze **4.268×** (1.580 / 0.370 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **5.875×** (2.080 / 0.354 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 835 — `cli_selectors` (armin_make_grid)
| `armin_make_grid` | `make-armin-grid` (`src/cadr-cli/interactive/components/armin.lisp`) | leftover `buildFinalGrid` / `createEmptyGrid` (`packages/coding-agent/src/modes/interactive/components/armin.ts`) |
Leftover sibling of Pairs 514–516 on the same `armin.lisp` `cli_selectors` hole. Timed work is empty vs final 2d grid construct — not tick, not TUI render. Observed `amg_spaces` / `amg_ink` / `amg_h` / `amg_w` / `amg_empty0` are exact. First n=5 freeze **4.041×** (27.332 / 6.763 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **1.684×** (27.119 / 16.108 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 836 — `cli_selectors` (armin_copy_grid)
| `armin_copy_grid` | `copy-armin-grid` (`src/cadr-cli/interactive/components/armin.lisp`) | leftover `finalGrid.map(row => [...row])` (`packages/coding-agent/src/modes/interactive/components/armin.ts`) |
Leftover sibling of Pair 835. Timed work is independent 2d copy plus mutate-copy — not tick, not render. Observed `acg_orig` / `acg_copy` / `acg_h` / `acg_w` / `acg_n` are exact. First n=5 freeze **6.066×** (24.123 / 3.977 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **6.466×** (24.841 / 3.842 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 837 — `cli_selectors` (armin_row_string)
| `armin_row_string` | `armin-grid-row-string` (`src/cadr-cli/interactive/components/armin.lisp`) | leftover `row.join("")` (`packages/coding-agent/src/modes/interactive/components/armin.ts`) |
Leftover sibling of Pairs 835–836. Timed work is row join without theme/clip — not `component-render`, not tick. Observed `ars_len` / `ars_empty0` / `ars_ink` / `ars_full` / `ars_n` are exact. First n=5 freeze **4.095×** (23.245 / 5.676 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **4.293×** (23.584 / 5.494 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 844 — `cli_extensions_install` (http_timeout_p)
| `http_timeout_p` | `extension-http-timeout-condition-p` (`src/cadr-cli/extensions/loader.lisp`) | leftover timeout error names (`packages/coding-agent/src/core/extensions/loader.ts`) |
Leftover sibling of Pair 502–504 on the same `loader.lisp` hole. Timed work is the timeout-condition predicate — not HTTP, not reload. Observed `htp_to` / `htp_native` / `htp_nested` / `htp_plain` / `htp_nil` are exact. First n=5 freeze **2.787×** (0.832 / 0.298 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **4.480×** (1.356 / 0.303 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 845 — `cli_extensions_install` (same_source)
| `same_source` | `same-extension-source-p` (`src/cadr-cli/extensions/loader.lisp`) | leftover `bundle.path === source.path` (`packages/coding-agent/src/core/extensions/loader.ts`) |
Leftover sibling of Pair 844. Timed work is path equality — not `reload-cli-extensions`. Observed `ses_eq` / `ses_neq` / `ses_nil` / `ses_slash` / `ses_n` are exact. First n=5 freeze **2.631×** (0.421 / 0.160 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **4.802×** (0.759 / 0.158 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 846 — `cli_extensions_install` (quiet_manager)
| `quiet_manager` | `call-with-quiet-extension-manager` (`src/cadr-cli/extensions/loader.lisp`) | leftover silenced notify stream (`packages/coding-agent/src/core/extensions/loader.ts`) |
Leftover sibling of Pairs 844–845. Timed work is swapping the manager output stream — not discovery. Observed `qm_silent` / `qm_restored` / `qm_after` / `qm_n` are exact. First n=5 freeze **2.740×** (0.680 / 0.248 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **6.863×** (1.176 / 0.171 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 847 — `cli_extensions_install` (manager_notify)
| `manager_notify` | `extension-manager-notify` (`src/cadr-cli/extensions/loader.lisp`) | leftover notify format (`packages/coding-agent/src/core/extensions/loader.ts`) |
Leftover sibling of Pairs 844–846 on the same `loader.lisp` hole. Timed work is the notify prefix, downcased level, and secret absence — not reload. Observed `enm_info` / `enm_error` / `enm_redact` / `enm_nl` / `enm_n` are exact. First n=5 freeze **2.503×** (3.324 / 1.328 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **2.930×** (3.618 / 1.235 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 848 — `cli_extensions_install` (startup_issues)
| `startup_issues` | `report-startup-extension-issues` (`src/cadr-cli/extensions/loader.lisp`) | leftover `reportDiagnostics` (`packages/coding-agent/src/core/extensions/loader.ts`) |
Leftover sibling of Pair 847. Timed work is Error:/Warning:/load-failure flags — not ANSI, not TUI. Observed `rsi_err` / `rsi_warn` / `rsi_load` / `rsi_prefix` / `rsi_n` are exact. First n=5 freeze **2.567×** (2.919 / 1.137 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **4.819×** (3.989 / 0.828 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 849 — `cli_extensions_install` (output_boundary)
| `output_boundary` | `call-with-extension-output-boundary` (`src/cadr-cli/extensions/loader.lisp`) | leftover stdout/stderr bind (`packages/coding-agent/src/core/extensions/loader.ts`) |
Leftover sibling of Pairs 847–848. Timed work is writes landing on the manager stream — not asdf load. Observed `eob_out` / `eob_err` / `eob_n` are exact. First n=5 freeze **2.759×** (0.740 / 0.268 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **5.208×** (1.196 / 0.230 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 850 — `cli_extensions_install` (loaded_model)
| `loaded_model` | `llama-loaded-model-p` (`src/cadr-cli/extensions/llama/extension.lisp`) | leftover loaded/sleeping predicate (`packages/coding-agent/src/extensions/llama`) |
Leftover sibling of Pairs 505–507 on the same `llama/extension.lisp` hole. Timed work is the loaded/sleeping status predicate — not HTTP, not login. Observed `llm_loaded` / `llm_sleep` / `llm_unloaded` / `llm_n` are exact. First n=5 freeze **1.511×** (0.211 / 0.140 µs) on host `cursor`, ceiling 8.0. Remeasure on tip **3.296×** (0.427 / 0.130 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 851 — `cli_extensions_install` (catalog_notify)
| `catalog_notify` | `notify-llama-catalog` (`src/cadr-cli/extensions/llama/extension.lisp`) | leftover catalog notify lines (`packages/coding-agent/src/extensions/llama`) |
Leftover sibling of Pair 850. Timed work is empty/catalog notify text — not auth. Observed `lnc_empty` / `lnc_loaded` / `lnc_sleep` / `lnc_n` are exact. First n=5 freeze **40.150×** (28.921 / 0.720 µs) on host `cursor`, ceiling 60.0 (first-freeze bump). Remeasure on tip **14.250×** (9.316 / 0.654 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 852 — `cli_extensions_install` (progress_notify)
| `progress_notify` | `llama-progress-notifier` (`src/cadr-cli/extensions/llama/extension.lisp`) | leftover progress notify text (`packages/coding-agent/src/extensions/llama`) |
Leftover sibling of Pairs 850–851. Timed work is progress message flags (`%` / detail) — not download. Observed `lpn_plain` / `lpn_pct` / `lpn_detail` / `lpn_n` are exact. First n=5 freeze **47.472×** (29.267 / 0.616 µs) on host `cursor`, ceiling 60.0 (first-freeze bump). Remeasure on tip **19.792×** (11.417 / 0.577 µs) on host `Friend-MachineD`. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 853 — `cli_bootstrap_sessions` (cli_platform)
| `cli_platform` | `cli-platform` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover process.platform darwin/win32/linux |
Leftover sibling of Pairs 808–825 on the same `sessions.lisp` hole. Timed work is the platform keyword — not clipboard. Observed `cpl_linux` / `cpl_win` / `cpl_darwin` are exact. First n=5 freeze **1.049×** (0.131 / 0.125 µs) on host `Friend-MachineD`, ceiling 8.0. Within ceiling; not booked in over-1× ledger. Gate used `--only-enforce` (scoped overlay; py rc=2 from known METRICS observed-key pollution; this metric did not fail observed-exact). Same commit no optimize. `nextPairNum` left at 328.
### Pair 854 — `cli_bootstrap_sessions` (session_info_style)
| `session_info_style` | `session-info-style` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover heading/label/other style |
Leftover sibling of Pair 853. Timed work is heading/label/other style flags — not TUI render. Observed `sis_head_plain` / `sis_head_bold` / `sis_lab_plain` / `sis_lab_dim` / `sis_other` are exact. First n=5 freeze **7.201×** (2.643 / 0.367 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Gate used `--only-enforce` (scoped overlay; py rc=2 from known METRICS observed-key pollution; this metric did not fail observed-exact). Same commit no optimize. `nextPairNum` left at 328.
### Pair 855 — `cli_bootstrap_sessions` (default_changelog_path)
| `default_changelog_path` | `default-changelog-path` (`src/cadr-cli/bootstrap/sessions.lisp`) | leftover CHANGELOG env/leaf |
Leftover sibling of Pairs 853–854. Timed work is CADR_CHANGELOG_PATH / CHANGELOG.md leaf flags — not disk walk. Observed `dcp_forced` / `dcp_fallback` / `dcp_clean` are exact. First n=5 freeze **1182.272×** (218.058 / 0.184 µs) on host `Friend-MachineD`, ceiling 1200.0 (first-freeze bump). Over-1× booked. Gate used `--only-enforce` (scoped overlay; py rc=2 from known METRICS observed-key pollution; this metric did not fail observed-exact). Same commit no optimize. `nextPairNum` left at 328.
### Pair 856 — `settings_load` (sdk_make_manager)
| `sdk_make_manager` | `make-sdk-settings-manager` (`src/cadr-cli/sdk/settings-service.lisp`) | leftover `SettingsManager.inMemory({})` (nil-path construct; not `create` I/O) |
Leftover sibling of Pairs 763–777 on the same `settings-service.lisp` hole. Timed work is nil-path manager construct — `settings-reload` sees nil paths and does not read settings.json. Observed `ssm_type` / `ssm_nil_prov` / `ssm_nil_model` / `ssm_trusted` / `ssm_n` are exact. First n=5 freeze **1.411×** (3.670 / 2.600 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 857 — `settings_load` (sdk_make_memory)
| `sdk_make_memory` | `make-memory-sdk-settings-manager` (`src/cadr-cli/sdk/settings-service.lisp`) | `SettingsManager.inMemory` (`packages/coding-agent/src/core/settings-manager.ts`) |
Leftover sibling of Pair 856. Timed work is in-memory SDK manager construct with fixture vs empty — not disk. Observed `smm_prov` / `smm_model` / `smm_empty` / `smm_type` / `smm_n` are exact. First n=5 freeze **5.581×** (26.876 / 4.816 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 858 — `settings_load` (sdk_effective_thinking_level)
| `sdk_effective_thinking_level` | `sdk-settings-effective-thinking-level` (`src/cadr-cli/sdk/settings-service.lisp`) | leftover explicit / per-model / restored / default thinking precedence |
Leftover sibling of Pairs 856–857. Timed work is thinking-level precedence — not login I/O. Do not compare keyword vs string. Observed `set_exp` / `set_model` / `set_rest` / `set_def` / `set_n` are exact. First n=5 freeze **3.700×** (14.454 / 3.907 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
Leftover sibling of Pairs 763–777 on the same `settings-service.lisp` hole. Timed work is nil-path manager construct — `settings-reload` sees nil paths and does not read settings.json. Observed `ssm_type` / `ssm_nil_prov` / `ssm_nil_model` / `ssm_trusted` / `ssm_n` are exact. First n=5 freeze pending. Same commit no optimize. `nextPairNum` left at 328.
Leftover sibling of Pair 856. Timed work is in-memory SDK manager construct with fixture vs empty — not disk. Observed `smm_prov` / `smm_model` / `smm_empty` / `smm_type` / `smm_n` are exact. First n=5 freeze pending. Same commit no optimize. `nextPairNum` left at 328.
Leftover sibling of Pairs 856–857. Timed work is thinking-level precedence — not login I/O. Do not compare keyword vs string. Observed `set_exp` / `set_model` / `set_rest` / `set_def` / `set_n` are exact. First n=5 freeze pending. Same commit no optimize. `nextPairNum` left at 328.
### Pair 859 — `cli_interactive_controller` (terminal_title_sequence)
| `terminal_title_sequence` | `tui-terminal-title-sequence` (`src/cadr-cli/interactive/controller.lisp`) | leftover OSC 0 title wrap (`ESC]0;…BEL`) |
Leftover sibling of Pairs 511–513 on the same `controller.lisp` hole. Timed work is OSC 0 wrap of the already-paired title — not TUI render. Observed `tts_osc` / `tts_bel` / `tts_cadr` / `tts_sess` / `tts_n` are exact. First n=5 freeze **1.519×** (2.713 / 1.785 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Gate used `--only-enforce` (py rc=2 from known `parsed_provider` pollution; scoped gate PASS). Same commit no optimize. `nextPairNum` left at 328.
### Pair 860 — `cli_interactive_controller` (make_notification_stream)
| `make_notification_stream` | `make-notification-output-stream` (`src/cadr-cli/interactive/controller.lisp`) | leftover notification buffer construct |
Leftover sibling of Pair 859. Timed work is gray-stream construct plus one write/flush — not TUI. Observed `mns_type` / `mns_cb` / `mns_empty` / `mns_char` / `mns_n` are exact. First n=5 freeze **8.280×** (1.429 / 0.173 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 861 — `cli_interactive_controller` (notification_stream_flush)
| `notification_stream_flush` | `notification-stream-flush` (`src/cadr-cli/interactive/controller.lisp`) | leftover notification buffer flush |
Leftover sibling of Pairs 859–860. Timed work is flush of buffered chars; empty flush is a no-op. Observed `nsf_hi` / `nsf_once` / `nsf_len` / `nsf_again` / `nsf_n` are exact. First n=5 freeze **4.675×** (1.154 / 0.247 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 862 — `cli_selectors` (armin_copy_cell)
| `armin_copy_cell` | `armin-copy-cell` (`src/cadr-cli/interactive/components/armin.lisp`) | leftover typewriter `currentGrid[row][x] = finalGrid[row][x]` (`packages/coding-agent/src/modes/interactive/components/armin.ts`) |
Leftover sibling of Pairs 835–837 on the same `armin.lisp` hole. Timed work is one cell assign plus oob reject — not tick, not TUI render, no animation thread. Observed `acc_ok` / `acc_match` / `acc_oob` / `acc_mid` / `acc_n` are exact. First n=5 freeze **5.290×** (25.759 / 4.869 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 863 — `cli_selectors` (armin_copy_row)
| `armin_copy_row` | `armin-copy-row` (`src/cadr-cli/interactive/components/armin.lisp`) | leftover scanline row copy (`packages/coding-agent/src/modes/interactive/components/armin.ts`) |
Leftover sibling of Pair 862. Timed work is one display-row copy plus dest mutate — not tick, not render. Observed `acr_eq` / `acr_indep` / `acr_w` / `acr_h` / `acr_n` are exact. First n=5 freeze **4.716×** (23.953 / 5.080 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 864 — `cli_selectors` (armin_rotate_row)
| `armin_rotate_row` | `armin-rotate-row` (`src/cadr-cli/interactive/components/armin.lisp`) | leftover glitch `slice(offset).concat(slice(0, offset))` (`packages/coding-agent/src/modes/interactive/components/armin.ts`) |
Leftover sibling of Pairs 862–863. Timed work is left-rotate of one row; offsets are non-negative so JS slice and CL `mod` agree. Observed `arr_len` / `arr_zero` / `arr_shift` / `arr_mod` / `arr_n` are exact. First n=5 freeze **3.429×** (21.362 / 6.230 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Same commit no optimize. `nextPairNum` left at 328.
### Pair 865 — `cli_interactive_controller` (tui_input_thread)
| `tui_input_thread` | `tui-input-thread-p` (`src/cadr-cli/interactive/extension-ui.lisp`) | leftover TUI input-thread sentinel |
Leftover sibling of Pairs 670–687 on the same `extension-ui.lisp` hole. Timed work is the input-thread predicate (nil / self / other) — not TUI render, not spawn. Observed `tit_nil` / `tit_self` / `tit_other` / `tit_both` / `tit_n` are exact. First n=5 freeze **0.979×** (0.168 / 0.171 µs) on host `Friend-MachineD`, ceiling 8.0. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Same commit no optimize. `nextPairNum` left at 328.
### Pair 866 — `cli_interactive_controller` (extension_host_turn)
| `extension_host_turn` | `call-extension-host-turn-without-blocking-tui` (`src/cadr-cli/interactive/extension-ui.lisp`) | leftover inline vs deferred startTurn |
Leftover sibling of Pair 865. Timed work is inline thunk vs start-turn dispatch — not a live LLM turn, not `make-thread`. Observed `eht_inline` / `eht_start` / `eht_defer` / `eht_ok` / `eht_n` are exact. First n=5 freeze **1.495×** (0.323 / 0.216 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Same commit no optimize. `nextPairNum` left at 328.
### Pair 867 — `cli_interactive_controller` (wrap_extension_host_turn)
| `wrap_extension_host_turn` | `wrap-extension-host-tui-turn-dispatch` (`src/cadr-cli/interactive/extension-ui.lisp`) | leftover sendCustomMessage wrap/restore (`packages/coding-agent/src/core/agent-session.ts`) |
Leftover sibling of Pairs 865–866. Timed work is wrap send/user plus restorer off the TUI thread — not a live turn. Observed `wet_send` / `wet_user` / `wet_restore` / `wet_trig` / `wet_n` are exact. First n=5 freeze **2.313×** (1.297 / 0.561 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Gate used `--only-enforce` (py invalid-report `parsed_provider` from METRICS observed-key pollution; this metric did not fail observed-exact). Same commit no optimize. `nextPairNum` left at 328.
### Pair 895 — `oauth_pkce_device` (xai_login)
| `xai_login` | `login-xai-oauth` (`src/cadr-ai/oauth/providers/xai.lisp`) | `parseDeviceCode` + `credentialsFromTokenResponse` (`packages/ai/src/auth/oauth/xai.ts`) |
Leftover trio on unclaimed `src/cadr-ai/oauth/providers/xai.lisp` (leftover 379–381 measured error_detail / ensure_success / notify_device). Timed work is stub device+token HTTP login — not error_detail, not expires, not referrer slug. Observed `xli_acc` / `xli_ref` / `xli_n` are exact. First n=5 freeze **13.116×** (15.536 / 1.185 µs) on host `Friend-MachineD`, ceiling 20.0 (raised 8→20). Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 896 — `oauth_pkce_device` (xai_login_fail)
| `xai_login_fail` | `login-xai-oauth` device HTTP fail (`src/cadr-ai/oauth/providers/xai.lisp`) | `requestDeviceCode` HTTP fail (`packages/ai/src/auth/oauth/xai.ts`) |
Leftover sibling of Pair 895. Timed work is stub device HTTP 400 throwing — not exact message text. Observed `xlf_throw` / `xlf_n` are exact. First n=5 freeze **3.870×** (8.266 / 2.136 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 897 — `oauth_pkce_device` (xai_refresh)
| `xai_refresh` | `refresh-xai-oauth-credential` (`src/cadr-ai/oauth/providers/xai.lisp`) | `refreshXaiToken` / `credentialsFromTokenResponse` (`packages/ai/src/auth/oauth/xai.ts`) |
Leftover sibling of Pairs 895–896. Timed work is stub token HTTP 200 refresh — exact access/refresh, not expires. Observed `xrf_acc` / `xrf_ref` / `xrf_n` are exact. First n=5 freeze **22.614×** (5.365 / 0.237 µs) on host `Friend-MachineD`, ceiling 20.0 (raised 8→20). Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 898 — `oauth_pkce_device` (openrouter_login)
| `openrouter_login` | `login-openrouter-oauth` (`src/cadr-ai/oauth/providers/openrouter.lisp`) | `parseAuthorizationInput` + `exchangeAuthorizationCode` (`packages/ai/src/auth/oauth/openrouter.ts`) |
Leftover trio on unclaimed `src/cadr-ai/oauth/providers/openrouter.lisp` (leftover 436–438 queued openrouter_input / openrouter_refresh / openrouter_exchange). Timed work is stub HTTP login after a pasted code — not parse-openrouter-authorization-input fixtures, not PKCE, not callback port. Observed `olg_acc` / `olg_ref` / `olg_n` are exact. First n=5 freeze **35.027×** (168.272 / 4.804 µs) on host `Friend-MachineD`, ceiling 50.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 899 — `oauth_pkce_device` (openrouter_login_fail)
| `openrouter_login_fail` | `login-openrouter-oauth` key exchange fail (`src/cadr-ai/oauth/providers/openrouter.lisp`) | `exchangeAuthorizationCode` HTTP fail (`packages/ai/src/auth/oauth/openrouter.ts`) |
Leftover sibling of Pair 898. Timed work is stub HTTP 400 throwing — not exact message text. Observed `olf_throw` / `olf_n` are exact. First n=5 freeze **53.681×** (202.181 / 3.766 µs) on host `Friend-MachineD`, ceiling 80.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 900 — `oauth_pkce_device` (openrouter_login_miss)
| `openrouter_login_miss` | `login-openrouter-oauth` missing code (`src/cadr-ai/oauth/providers/openrouter.lisp`) | `Missing authorization code` (`packages/ai/src/auth/oauth/openrouter.ts`) |
Leftover sibling of Pairs 898–899. Timed work is empty pasted input throwing — not NIL vs undefined. Observed `olm_throw` / `olm_n` are exact. First n=5 freeze **98.722×** (183.818 / 1.862 µs) on host `Friend-MachineD`, ceiling 100.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 901 — `find_tool` (directory_gitignore_rules)
| `directory_gitignore_rules` | `directory-gitignore-rules` (`src/cadr-cli/tools/glob.lisp`) | `.gitignore` load classify (`packages/coding-agent/src/core/tools/find.ts`) |
Leftover trio on unclaimed `src/cadr-cli/tools/glob.lisp` (leftover 448–450 / 688–693 already frozen; no open leftover PR). Timed work is production directory-gitignore-rules on a staged tree — not parse-gitignore-line fixtures. Observed `dgr_n` / `dgr_ok` / `dgr_none` / `dgr_hash` are exact. First n=5 freeze **1.635×** (598.841 / 366.283 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 902 — `find_tool` (collect_tree_files)
| `collect_tree_files` | `collect-tree-files` (`src/cadr-cli/tools/glob.lisp`) | tree walk classify (`packages/coding-agent/src/core/tools/find.ts`) |
Leftover sibling of Pair 901. Timed work is collect-tree-files keep.lisp / nested / skip.txt / .git / node_modules filtering. Observed `ctf_n` / `ctf_keep` / `ctf_nested` / `ctf_skip` / `ctf_git` / `ctf_nm` are exact. First n=5 freeze **1.315×** (754.579 / 573.769 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 903 — `find_tool` (glob_files)
| `glob_files` | `glob-files` (`src/cadr-cli/tools/glob.lisp`) | glob execute classify (`packages/coding-agent/src/core/tools/find.ts`) |
Leftover sibling of Pairs 901–902. Timed work is glob-files match count / empty copy / limit truncation / missing path throw — not make-glob-tool constructor. Observed `gf_lisp` / `gf_empty` / `gf_limit` / `gf_miss` are exact. First n=5 freeze **1.951×** (1370.273 / 702.302 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 904 — `cli_selectors` (countdown_dispose)
| `countdown_dispose` | `cadr-tui:component-dispose` on unstarted `countdown-timer` (`src/cadr-cli/interactive/components/countdown.lisp`) | CountdownTimer.dispose with intervalId unset (`packages/coding-agent/src/modes/interactive/components/countdown-timer.ts`) |
Leftover sibling of leftover 556–558 on the same `countdown.lisp` hole. Timed work is dispose without a live thread — not remaining-seconds, not tick, not request-render. Observed `cdd_stop` / `cdd_thread` / `cdd_expired` / `cdd_n` are exact. First n=5 freeze **1.773×** (0.318 / 0.179 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 905 — `cli_selectors` (countdown_unstarted)
| `countdown_unstarted` | `make-countdown-timer` `:start-p nil` 2500ms (`src/cadr-cli/interactive/components/countdown.lisp`) | remainingSeconds ceil without setInterval (`packages/coding-agent/src/modes/interactive/components/countdown-timer.ts`) |
Leftover sibling of leftover 556–558 / 904. Timed work is construct without starting the thread — 2500ms remaining is 3, not leftover 556's 1500ms path. Observed `cdu_thread` / `cdu_stop` / `cdu_expired` / `cdu_remain` / `cdu_n` are exact. First n=5 freeze **1.653×** (0.249 / 0.150 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 906 — `cli_selectors` (countdown_start_guard)
| `countdown_start_guard` | `countdown-timer-start` when thread is already bound (`src/cadr-cli/interactive/components/countdown.lisp`) | keep existing intervalId (`packages/coding-agent/src/modes/interactive/components/countdown-timer.ts`) |
Leftover sibling of leftover 556–558 / 904–905. Timed work is the existing-thread skip — no `sb-thread:make-thread`, no setInterval. Observed `csg_keep` / `csg_stop` / `csg_fresh` / `csg_n` are exact. First n=5 freeze **1.458×** (0.292 / 0.200 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 907 — `cli_support` (provider_login_help)

| metric | cadr | pi |
|---|---|---|
| `provider_login_help` | `get-provider-login-help` (`src/cadr-cli/support/model-help.lisp`) | `getProviderLoginHelp` (`packages/coding-agent/src/core/auth-guidance.ts`) |

Leftover sibling of leftover 460–462 on the same `model-help.lisp` hole. Timed work is the login-help wrapper itself — not format-no-models / no-model-selected / no-api-key. Observed `plh_pref` / `plh_login` / `plh_prov` / `plh_mod` / `plh_n` are exact. First n=5 freeze **45.516×** (476.985 / 10.480 µs) on host `Friend-MachineD`, ceiling 50.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 908 — `cli_support` (docs_directory)

| metric | cadr | pi |
|---|---|---|
| `docs_directory` | `docs-directory` (`src/cadr-cli/support/model-help.lisp`) | `getDocsPath` (`packages/coding-agent/src/config.ts`) |

Leftover sibling of leftover 460–462 / 907. Timed work is the docs-directory wrapper — not the three format-* messages. Observed `dd_docs` / `dd_len` / `dd_n` are exact. First n=5 freeze **33.348×** (227.853 / 6.833 µs) on host `Friend-MachineD`, ceiling 50.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 909 — `cli_support` (default_thinking_level)

| metric | cadr | pi |
|---|---|---|
| `default_thinking_level` | `+default-thinking-level+` (`src/cadr-cli/support/model-help.lisp`) | `DEFAULT_THINKING_LEVEL` (`packages/coding-agent/src/core/defaults.ts`) |

Leftover sibling of leftover 460–462 / 907–908. Timed work is the default thinking keyword/string classify — not settings-manager get/set. Observed `dtl_med` / `dtl_high` / `dtl_name` / `dtl_n` are exact. First n=5 freeze **0.546×** (0.240 / 0.440 µs) on host `Friend-MachineD`, ceiling 8.0. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 910 — `cli_selectors` (daxnuts_render)

| metric | cadr | pi |
|---|---|---|
| `daxnuts_render` | `cadr-tui:component-render` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftoverDaxnutsRenderOnce cadr append structure (`packages/coding-agent/src/modes/interactive/components/daxnuts.ts`) |

Leftover sibling of leftover 547–549 / 634–636 on the same `daxnuts.lisp` hole. Timed work is unstarted `component-render` at width 80 twice (cache `eq`) then tick=20 late render — not parse/image-line/center, not rgb_at / make / tick, not startAnimation. Observed `dxr_len` / `dxr_cache` / `dxr_late` / `dxr_scan` / `dxr_rev20` are exact. First n=5 freeze **4.055×** (594.457 / 146.590 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 911 — `cli_selectors` (daxnuts_invalidate)

| metric | cadr | pi |
|---|---|---|
| `daxnuts_invalidate` | `cadr-tui:component-invalidate` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftoverDaxnutsInvalidateOnce cachedKey clear (`packages/coding-agent/src/modes/interactive/components/daxnuts.ts`) |

Leftover sibling of leftover 910. Timed work is render then invalidate (cached-key was set then nil). Observed `dxi_had` / `dxi_cleared` / `dxi_n` are exact (`dxi_cleared` is still-cached after invalidate = 0). First n=5 freeze **6.106×** (21.783 / 3.568 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 912 — `cli_selectors` (daxnuts_dispose)

| metric | cadr | pi |
|---|---|---|
| `daxnuts_dispose` | `cadr-tui:component-dispose` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftoverDaxnutsDisposeUnstarted stopped / interval stays null (`packages/coding-agent/src/modes/interactive/components/daxnuts.ts`) |

Leftover sibling of leftover 910–911. Timed work is dispose on an unstarted timer (thread/interval nil) — not `daxnuts-component-run` sleep, not start. Observed `dxd_stop` / `dxd_thread` / `dxd_n` are exact. First n=5 freeze **3.537×** (0.851 / 0.241 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.
### Pair 913 — `oauth_pkce_device` (github_domain)

| metric | cadr | pi |
|---|---|---|
| `github_domain` | `normalize-github-domain` (`src/cadr-ai/oauth/providers/github-copilot.lisp`) | leftoverNormalizeGitHubDomain / normalizeDomain (`packages/ai/src/auth/oauth/github-copilot.ts`) |

Leftover sibling of leftover copilot_url / copilot_auth on the same github-copilot hole. Timed work is domain normalize (blank / plain / https host / trim) — not base-url, not toAuth, not device login. Observed `ghd_blank` / `ghd_plain` / `ghd_https` / `ghd_trim` / `ghd_n` are exact. First n=5 freeze **1.141×** (1.715 / 1.503 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1×. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.


### Pair 914 — `oauth_pkce_device` (github_oauth_url)

| metric | cadr | pi |
|---|---|---|
| `github_oauth_url` | `github-oauth-url` (`src/cadr-ai/oauth/providers/github-copilot.lisp`) | leftoverGithubOAuthUrl / getUrls (`packages/ai/src/auth/oauth/github-copilot.ts`) |

Leftover sibling of leftover 913. Timed work is `https://domain+suffix` for device-code / access-token / enterprise host — not copilot_internal token URL. Observed `gou_dev` / `gou_tok` / `gou_ent` / `gou_https` / `gou_n` are exact. First n=5 freeze **3.329×** (1.387 / 0.417 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.


### Pair 915 — `oauth_pkce_device` (github_request_headers)

| metric | cadr | pi |
|---|---|---|
| `github_request_headers` | `github-copilot-request-headers` (`src/cadr-ai/oauth/providers/github-copilot.lisp`) | leftoverGithubCopilotRequestHeaders / COPILOT_HEADERS + Authorization (`packages/ai/src/auth/oauth/github-copilot.ts`) |

Leftover sibling of leftover 913–914. Timed work is extra Accept + Bearer + COPILOT_HEADERS — not oauth-flow-request. Observed `gch_n` / `gch_auth` / `gch_ua` / `gch_acc` / `gch_ok` are exact. First n=5 freeze **0.851×** (0.668 / 0.785 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1×. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.


### Pair 916 — `cli_support` (watch_error)

| metric | cadr | pi |
|---|---|---|
| `watch_error` | `watch-with-error-handler` (`src/cadr-cli/support/file-watcher.lisp`) | leftover watchWithErrorHandler catch (`packages/coding-agent/src/utils/fs-watch.ts`) |

Leftover sibling of leftover 481–483 on the same file-watcher hole. Timed work is the error/onError path — not retry delay, not null close, not signature. Observed `we_nil` / `we_err` / `we_pos` / `we_n` are exact. First n=5 freeze **0.324×** (4.832 / 14.918 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1×. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 917 — `cli_support` (watch_start_close)

| metric | cadr | pi |
|---|---|---|
| `watch_start_close` | `watch-with-error-handler` + `close-watcher` (`src/cadr-cli/support/file-watcher.lisp`) | watchWithErrorHandler + closeWatcher (`packages/coding-agent/src/utils/fs-watch.ts`) |

Leftover sibling of leftover 916. Timed work is start on a present file then close — not poll, not null close. Observed `wsc_got` / `wsc_closed` / `wsc_err` / `wsc_n` are exact. First n=5 freeze **23.588×** (178.516 / 7.568 µs) on host `Friend-MachineD`, ceiling 40.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 918 — `cli_support` (poll_once)

| metric | cadr | pi |
|---|---|---|
| `poll_once` | `poll-file-watcher-once` (`src/cadr-cli/support/file-watcher.lisp`) | leftoverPollOnce (`packages/coding-agent/src/utils/fs-watch.ts` signature compare) |

Leftover sibling of leftover 916–917. Timed work is unchanged then changed poll — not `watch_signature` as its own metric, not native `fs.watch` keep-alive. Observed `po_same` / `po_change` / `po_n1` / `po_n` are exact. First n=5 freeze **0.300×** (59.744 / 199.071 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1×. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 922 — `bash_tool` (output_path)

| metric | cadr | pi |
|---|---|---|
| `output_path` | `bash-output-path` (`src/cadr-cli/tools/bash.lisp`) | ensureTempFile temp log path (`packages/coding-agent/src/core/bash-executor.ts`) |

Leftover sibling of earlier `bash_tool` leftovers on `src/cadr-cli/tools/bash.lisp`. Timed work is constructing a temp log path (`.log` suffix, 16-hex id after last hyphen, under the process temp directory). Do not exact `cadr-bash` vs `pi-bash` product prefixes or the random hex. Observed `bop_log` / `bop_hex` / `bop_tmp` / `bop_n` are exact. First n=5 freeze **10.664×** (117.640 / 11.032 µs) on host `Friend-MachineD`, ceiling 24.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 923 — `bash_tool` (make_tool)

| metric | cadr | pi |
|---|---|---|
| `make_tool` | `make-bash-tool` (`src/cadr-cli/tools/bash.lisp`) | `createBashTool` (`packages/coding-agent/src/core/tools/bash.ts`) |

Leftover sibling of Pair 922. Timed work is constructing the bash tool (name `bash`, nonempty description, executor/execute function). Do not exact description product copy. Observed `mt_name` / `mt_desc` / `mt_exec` / `mt_n` are exact. First n=5 freeze **2.046×** (3.108 / 1.519 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 924 — `bash_tool` (record_nil)

| metric | cadr | pi |
|---|---|---|
| `record_nil` | `record-user-bash-result` nil agent (`src/cadr-cli/tools/bash.lisp`) | leftover nil-agent no-op return of `recordBashResult` (`packages/coding-agent/src/core/agent-session.ts`) |

Leftover sibling of Pairs 922–923. Timed work is the nil-agent no-op: return the same result object without appending a session message. Observed `rn_eq` / `rn_cmd` / `rn_out` / `rn_n` are exact. First n=5 freeze **3.436×** (0.384 / 0.112 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 958 — `cli_interactive_controller` (theme_kind)

| metric | cadr | pi |
|---|---|---|
| `theme_kind` | `valid-tui-theme-primitive-p` (`src/cadr-cli/interactive/themes.lisp`) | leftover replica of isThemeColorValue |

Leftover sibling of leftover 931–933 on the same needs-pair file. Does not remount `theme_prim`. Timed work is string/int/255/256/neg/nil primitive flags. Observed `tp_str` / `tp_nil` are exact. First n=5 freeze **0.610×** (0.246 / 0.404 µs) on host `Friend-MachineD`, ceiling 8.0. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 959 — `cli_interactive_controller` (theme_ok)

| metric | cadr | pi |
|---|---|---|
| `theme_ok` | `validate-tui-theme-object` (`src/cadr-cli/interactive/themes.lisp`) | leftover replica of theme object validate |

Leftover sibling of Pair 958. Does not remount `theme_val`. Timed work is ok / slash-name / unknown-key objects. Observed `tv_ok` / `tv_slash` are exact. First n=5 freeze **0.978×** (19.361 / 19.800 µs) on host `Friend-MachineD`, ceiling 8.0. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 960 — `cli_interactive_controller` (theme_get)

| metric | cadr | pi |
|---|---|---|
| `theme_get` | `resolve-tui-theme-value` (`src/cadr-cli/interactive/themes.lisp`) | leftover replica of resolveThemeColor |

Leftover sibling of Pairs 958–959. Does not remount `theme_res`. Timed work is int/empty/hex/var/cycle/missing resolve. Observed `tr_int` / `tr_hex` are exact. First n=5 freeze **0.234×** (1.891 / 8.088 µs) on host `Friend-MachineD`, ceiling 8.0. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 961 — `cli_interactive_controller` (wrap_ln)

| metric | cadr | pi |
|---|---|---|
| `wrap_ln` | `wrap-transcript-lines` (`src/cadr-cli/interactive/transcript.lisp`) | leftover replica of UserMessageComponent.render OSC 133 wrap |

Leftover sibling of leftover 949–951 on the same needs-pair file. Does not remount `wrap_osc`. Timed work is nil / one-line / two-line OSC wrap. Observed `wt_nil` / `wt_two_last` are exact. First n=5 freeze **2.376×** (1.174 / 0.494 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 962 — `cli_interactive_controller` (pad_sp)

| metric | cadr | pi |
|---|---|---|
| `pad_sp` | `output-padding-string` (`src/cadr-cli/interactive/transcript.lisp`) | leftover replica of output padding spaces |

Leftover sibling of Pair 961. Does not remount `pad_str`. Timed work is zero / one / other / space padding. Observed `op_0` / `op_space` are exact. First n=5 freeze **3.724×** (0.610 / 0.164 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 963 — `cli_interactive_controller` (cache_ok)

| metric | cadr | pi |
|---|---|---|
| `cache_ok` | `tui-entry-render-cacheable-p` (`src/cadr-cli/interactive/transcript.lisp`) | leftover replica of TUI entry render cacheable |

Leftover sibling of Pairs 961–962. Does not remount `cache_p`. Timed work is assistant / stream / tool nil / done / running / custom. Observed `rc_assist` / `rc_custom` are exact. First n=5 freeze **4.732×** (2.179 / 0.460 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 964 — `cli_interactive_controller` (sess_new)

| metric | cadr | pi |
|---|---|---|
| `sess_new` | `make-tool-render-session` (`src/cadr-cli/interactive/tool-render-session.lisp`) | leftover replica of ToolExecutionComponent construct |

Leftover sibling of leftover 943–945 on the same needs-pair file. Does not remount `sess_make`. Timed work is named session construct. Observed `tsm_name` / `tsm_nil` are exact. First n=5 freeze **3.192×** (0.550 / 0.172 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 965 — `cli_interactive_controller` (sess_set)

| metric | cadr | pi |
|---|---|---|
| `sess_set` | `update-tool-render-session` (`src/cadr-cli/interactive/tool-render-session.lisp`) | leftover replica of result/pending |

Leftover sibling of Pair 964. Does not remount `sess_upd`. Timed work is result set and clear. Observed `tsu_result` / `tsu_cleared` are exact. First n=5 freeze **2.746×** (0.537 / 0.196 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 966 — `cli_interactive_controller` (sess_out)

| metric | cadr | pi |
|---|---|---|
| `sess_out` | `render-tool-session` (`src/cadr-cli/interactive/tool-render-session.lisp`) | leftover replica of renderCall/renderResult fallback |

Leftover sibling of Pairs 964–965. Does not remount `sess_draw`. Timed work is pending vs hide-result empty render. Observed `trr_pending_n` / `trr_empty` are exact. First n=5 freeze **0.622×** (2.499 / 4.017 µs) on host `Friend-MachineD`, ceiling 8.0. cadr leads. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 967 — `cli_bootstrap_sessions` (cycle_ent)

| metric | cadr | pi |
|---|---|---|
| `cycle_ent` | `model-cycle-target-entry` (`src/cadr-cli/bootstrap/commands.lisp`) | leftover replica of `_cycleScopedModel` index wrap |

Leftover sibling of leftover 940–942 on the same needs-pair file. Does not remount `cycle_wrap`. Timed work is forward/empty model cycle. Observed `mc_fwd` / `mc_empty` are exact. First n=5 freeze **0.697×** (0.806 / 1.156 µs) on host `Friend-MachineD`, ceiling 8.0. cadr leads. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 968 — `cli_bootstrap_sessions` (scope_st)

| metric | cadr | pi |
|---|---|---|
| `scope_st` | `model-scope-startup-line` (`src/cadr-cli/bootstrap/commands.lisp`) | leftover replica of init Model scope line |

Leftover sibling of Pair 967. Does not remount `scope_hint`. Timed work is quiet/disabled scope lines. Observed `ms_quiet` / `ms_disabled` are exact. First n=5 freeze **0.470×** (34.441 / 73.206 µs) on host `Friend-MachineD`, ceiling 8.0. cadr leads. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 969 — `cli_bootstrap_sessions` (file_cli)

| metric | cadr | pi |
|---|---|---|
| `file_cli` | `process-cli-file-arguments` (`src/cadr-cli/bootstrap/commands.lisp`) | leftover replica of processFileArguments |

Leftover sibling of Pairs 967–968. Does not remount `file_tags`. Timed work is hello/image file tags. Observed `pf_hello` / `pf_img` are exact. First n=5 freeze **0.117×** (95.692 / 817.796 µs) on host `Friend-MachineD`, ceiling 8.0. cadr leads. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 970 — `cli_print_rpc` (line_bad)

| metric | cadr | pi |
|---|---|---|
| `line_bad` | `rpc-handle-line` (`src/cadr-cli/modes/rpc/mode.lisp`) | leftover replica of handleInputLine JSON.parse catch |

Leftover sibling of leftover 937–939 on the same needs-pair file. Does not remount `bad_line`. Timed work is invalid JSON line. Observed `bj_cmd` / `bj_nl` are exact. First n=5 freeze **1.188×** (7.254 / 6.107 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 971 — `cli_print_rpc` (line_arr)

| metric | cadr | pi |
|---|---|---|
| `line_arr` | `rpc-handle-line` (`src/cadr-cli/modes/rpc/mode.lisp`) | leftover replica of handleInputLine require JSON object |

Leftover sibling of Pair 970. Does not remount `array_line`. Timed work is a JSON array line. Observed `no_cmd` / `no_nl` are exact. First n=5 freeze **1.345×** (6.497 / 4.830 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 972 — `cli_print_rpc` (line_ui)

| metric | cadr | pi |
|---|---|---|
| `line_ui` | `rpc-handle-line` (`src/cadr-cli/modes/rpc/mode.lisp`) | leftover replica of handleInputLine unknown extension_ui_response |

Leftover sibling of Pairs 970–971. Does not remount `ui_absent`. Timed work is an unknown pending UI id. Observed `um_cmd` / `um_unk` are exact. First n=5 freeze **4.206×** (7.486 / 1.780 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 973 — `cli_print_rpc` (queue_ok)

| metric | cadr | pi |
|---|---|---|
| `queue_ok` | `parse-queue-mode` (`src/cadr-cli/modes/rpc/commands.lisp`) | leftover replica of parseQueueMode |

Leftover sibling of leftover 934–936 on the same needs-pair file. Does not remount `queue_parse`. Timed work is all/bad queue-mode parse. Observed `qm_all` / `qm_bad` are exact. First n=5 freeze **0.159×** (0.435 / 2.740 µs) on host `Friend-MachineD`, ceiling 8.0. cadr leads. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 974 — `cli_print_rpc` (asst_hit)

| metric | cadr | pi |
|---|---|---|
| `asst_hit` | `rpc-last-assistant-text` (`src/cadr-cli/modes/rpc/commands.lisp`) | leftover replica of last assistant text |

Leftover sibling of Pair 973. Does not remount `asst_text`. Timed work is hit/miss last assistant. Observed `la_hit` / `la_miss` are exact. First n=5 freeze **1.889×** (0.520 / 0.275 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 975 — `cli_print_rpc` (cmd_n)

| metric | cadr | pi |
|---|---|---|
| `cmd_n` | `rpc-command-list` (`src/cadr-cli/modes/rpc/commands.lisp`) | leftover replica of rpc command list |

Leftover sibling of Pairs 973–974. Does not remount `cmd_list`. Timed work is command list length/extension. Observed `cl_n` / `cl_ext` are exact. First n=5 freeze **8.772×** (2.232 / 0.254 µs) on host `Friend-MachineD`, ceiling 12.0 (raised from 8.0). Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 976 — `cli_print_rpc` (img_ok)

| metric | cadr | pi |
|---|---|---|
| `img_ok` | `rpc-images-from-json` (`src/cadr-cli/modes/rpc/prompt-bash.lisp`) | leftover replica of prompt command.images |

Leftover sibling of leftover 463–465 on the same needs-pair file. Does not remount `rpc_images`. Timed work is nil/mime image parse. Observed `img_nil` / `img_mime` are exact. First n=5 freeze **0.840×** (3.033 / 3.610 µs) on host `Friend-MachineD`, ceiling 8.0. cadr leads. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 977 — `cli_print_rpc` (prompt_ok)

| metric | cadr | pi |
|---|---|---|
| `prompt_ok` | `rpc-prompt-message` (`src/cadr-cli/modes/rpc/prompt-bash.lisp`) | leftover replica of prompt message+images |

Leftover sibling of Pair 976. Does not remount `rpc_prompt`. Timed work is string/parts prompt. Observed `rp_str` / `rp_parts` are exact. First n=5 freeze **3.997×** (1.991 / 0.498 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 978 — `cli_print_rpc` (bash_js)

| metric | cadr | pi |
|---|---|---|
| `bash_js` | `rpc-bash-result-json` (`src/cadr-cli/modes/rpc/prompt-bash.lisp`) | leftover replica of bash result payload |

Leftover sibling of Pairs 976–977. Does not remount `bash_result`. Timed work is output/null bash result. Observed `br_out` / `br_null` are exact. First n=5 freeze **4.536×** (3.070 / 0.677 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 979 — `evals_harness` (val_ext)

| metric | cadr | pi |
|---|---|---|
| `val_ext` | `validate-extension-result` (`src/cadr-evals/main.lisp`) | leftover replica of extension greeting + path-count |

Leftover sibling of leftover 925–927 on the same needs-pair file. Does not remount `validate_extension`. Timed work is Bob+one-path ok, Alice greeting fail, two-path fail, empty-path fail. Observed `ve_ok` / `ve_greet` are exact. First n=5 freeze **18.295×** (3.633 / 0.199 µs) on host `Friend-MachineD`, ceiling 20.0 (raised from 12.0). Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 980 — `evals_harness` (suite_id)

| metric | cadr | pi |
|---|---|---|
| `suite_id` | leftover replica of `%eval-main` suite cond (`src/cadr-evals/main.lisp`) | leftover replica of cadr suite cond (pi has no `--suite`) |

Leftover sibling of Pair 979. Does not remount `suite_dispatch`. Timed work is smoke/extensions/extension-authoring/unknown dispatch ids. Observed `sd_smoke` / `sd_unk` are exact. First n=5 freeze **2.323×** (0.244 / 0.105 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 981 — `evals_harness` (type_ok)

| metric | cadr | pi |
|---|---|---|
| `type_ok` | leftover of `%eval-main` `(typep value 'eval-result)` (`src/cadr-evals/main.lisp`) | leftover object-shape predicate (`output` + `events` own properties) |

Leftover sibling of Pairs 979–980. Does not remount `eval_result_p`. Timed work is make-eval-result yes, json-object miss, string miss, nil miss. Observed `er_yes` / `er_nil` are exact. First n=5 freeze **4.059×** (1.005 / 0.248 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 982 — `evals_harness` (msg_txt)

| metric | cadr | pi |
|---|---|---|
| `msg_txt` | `message-content-text` (`src/cadr-evals/harness.lisp`) | leftover replica of content-text join |

Leftover sibling of leftover 928–930 on the same needs-pair file. Does not remount `msg_content`. Timed work is plain string, text-parts join, empty, blank. Observed `ct_plain` / `ct_join` are exact. First n=5 freeze **2.635×** (1.599 / 0.607 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 983 — `evals_harness` (tools_n)

| metric | cadr | pi |
|---|---|---|
| `tools_n` | `eval-agent-tools` (`src/cadr-evals/harness.lisp`) | leftover replica of agent.tools list |

Leftover sibling of Pair 982. Does not remount `eval_tools`. Timed work is empty tools, filled count, read name, bash name. Observed `at_empty` / `at_read` are exact. First n=5 freeze **10.111×** (2.373 / 0.235 µs) on host `Friend-MachineD`, ceiling 12.0 (raised from 8.0). Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 984 — `evals_harness` (paths_n)

| metric | cadr | pi |
|---|---|---|
| `paths_n` | `eval-extension-paths` (`src/cadr-evals/harness.lisp`) | leftover replica of visible extension-host paths |

Leftover sibling of Pairs 982–983. Does not remount `eval_paths`. Timed work is no-host empty, one visible path, hidden skipped. Observed `ep_none` / `ep_path` are exact. First n=5 freeze **13.850×** (4.853 / 0.350 µs) on host `Friend-MachineD`, ceiling 16.0 (raised from 12.0). Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 985 — `evals_harness` (rep_ok)

| metric | cadr | pi |
|---|---|---|
| `rep_ok` | `make-eval-harness-reporter` (`src/cadr-evals/reporter.lisp`) | leftover replica of constructor artifactDirectory |

Leftover sibling of leftover 952–954 on the same needs-pair file. Does not remount `rep_make`. Timed work is explicit dir, trimmed env, missing env. Observed `mr_explicit` / `mr_n` are exact. First n=5 freeze **1.805×** (0.570 / 0.316 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 986 — `evals_harness` (fin_ok)

| metric | cadr | pi |
|---|---|---|
| `fin_ok` | `reporter-finite-number` (`src/cadr-evals/reporter.lisp`) | leftover replica of finite number keep |

Leftover sibling of Pair 985. Does not remount `fin_num`. Timed work is int, float, nil, inf, string. Observed `fn_int` / `fn_n` are exact. First n=5 freeze **1.873×** (0.267 / 0.142 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 987 — `evals_harness` (meta_ok)

| metric | cadr | pi |
|---|---|---|
| `meta_ok` | `reporter-artifact-metadata` (`src/cadr-evals/reporter.lisp`) | leftover replica of artifact metadata filter |

Leftover sibling of Pairs 985–986. Does not remount `art_meta`. Timed work is keep/runid/snap filter. Observed `am_keep` / `am_n` are exact. First n=5 freeze **2.042×** (1.651 / 0.809 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 988 — `cli_interactive_controller` (bash_go)

| metric | cadr | pi |
|---|---|---|
| `bash_go` | `append-tui-user-bash-running` (`src/cadr-cli/interactive/user-bash.lisp`) | leftover replica of BashExecutionComponent addChild running |

Leftover sibling of leftover 640–642 and 955–957 on the same needs-pair file. Does not remount `bash_run`. Timed work is addChild running. Observed `bar_n` / `bar_run2` are exact. First n=5 freeze **4.156×** (1.218 / 0.293 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 989 — `cli_interactive_controller` (bash_end)

| metric | cadr | pi |
|---|---|---|
| `bash_end` | `complete-tui-user-bash-string` (`src/cadr-cli/interactive/user-bash.lisp`) | leftover replica of setComplete exit 0 string |

Leftover sibling of Pair 988. Does not remount `bash_fin`. Timed work is hello complete and empty complete. Observed `cs_text` / `cs_empty` are exact. First n=5 freeze **6.552×** (1.460 / 0.223 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 990 — `cli_interactive_controller` (bash_off)

| metric | cadr | pi |
|---|---|---|
| `bash_off` | `stop-tui-user-bash-entry` (`src/cadr-cli/interactive/user-bash.lisp`) | leftover replica of loader.stop without setComplete |

Leftover sibling of Pairs 988–989. Does not remount `bash_halt`. Timed work is stop after partial output. Observed `st_run` / `st_exit` are exact. First n=5 freeze **8.012×** (1.346 / 0.168 µs) on host `Friend-MachineD`, ceiling 12.0 (raised from 8.0). Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 991 — `cli_selectors` (dlg_new)

| metric | cadr | pi |
|---|---|---|
| `dlg_new` | `make-login-dialog-state` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent constructor |

Leftover sibling of leftover 529–531, 619–627, and 946–948 on the same needs-pair file. Does not remount `dlg_make`. Timed work is empty/named/long provider construct. Observed `ldm_empty_n` / `ldm_named` are exact. First n=5 freeze **5.046×** (0.514 / 0.102 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 992 — `cli_selectors` (dlg_key)

| metric | cadr | pi |
|---|---|---|
| `dlg_key` | `login-dialog-show-auth` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of showAuth |

Leftover sibling of Pair 991. Does not remount `dlg_auth`. Timed work is plain/instr/empty/replace auth sections. Observed `lda_plain` / `lda_n` are exact. First n=5 freeze **5.599×** (2.945 / 0.526 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 993 — `cli_selectors` (dlg_code)

| metric | cadr | pi |
|---|---|---|
| `dlg_code` | `login-dialog-show-device-code` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of showDeviceCode |

Leftover sibling of Pairs 991–992. Does not remount `dlg_dev`. Timed work is code/empty/replace device sections. Observed `ldd_code` / `ldd_hint` are exact. First n=5 freeze **5.985×** (5.677 / 0.949 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 994 — `cli_selectors` (th_sel)

| metric | cadr | pi |
|---|---|---|
| `th_sel` | `thinking-selector-selected-level` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinkingSelectorSelectedLevel |

Leftover sibling of leftover 532–534 and 601–612 on the same needs-pair file. Does not remount `thinking_selector_selected_level`. Timed work is first/oob selected level. Observed `tssl_first` / `tssl_oob` are exact. First n=5 freeze **1.783×** (0.809 / 0.454 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 995 — `cli_selectors` (th_desc)

| metric | cadr | pi |
|---|---|---|
| `th_desc` | `thinking-level-description-line` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinkingLevelDescriptionLine |

Leftover sibling of Pair 994. Does not remount `thinking_level_description_line`. Timed work is off/default/bogus description lines. Observed `tsdl_off_def` / `tsdl_bogus` are exact. First n=5 freeze **5.486×** (0.729 / 0.133 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 996 — `cli_selectors` (th_draw)

| metric | cadr | pi |
|---|---|---|
| `th_draw` | `render-thinking-selector` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of renderThinkingSelector |

Leftover sibling of Pairs 994–995. Does not remount `render_thinking_selector`. Timed work is default/wide thinking selector render. Observed `tsrd_default` / `tsrd_wide` are exact. First n=5 freeze **59.389×** (278.008 / 4.681 µs) on host `Friend-MachineD`, ceiling 60.0 (first-freeze headroom for high render ratio). Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 997 — `cli_selectors` (um_evt)

| metric | cadr | pi |
|---|---|---|
| `um_evt` | `user-message-selector-handle-event` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageList.handleInput (structured events) |

Leftover sibling of leftover user-message handle/render pairs on fork.lisp. Does not remount `user_message_handle_event`. Timed work is down/empty structured events. Observed `umhe_down` / `umhe_empty` are exact. First n=5 freeze **1.518×** (2.504 / 1.649 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 998 — `cli_selectors` (um_raw)

| metric | cadr | pi |
|---|---|---|
| `um_raw` | `user-message-selector-handle-raw-input` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageList.handleInput (raw key dispatch) |

Leftover sibling of Pair 997. Does not remount `user_message_handle_raw`. Timed work is down/nop raw key dispatch. Observed `umhr_down` / `umhr_nop` are exact. First n=5 freeze **14.238×** (100.493 / 7.058 µs) on host `Friend-MachineD`, ceiling 30.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 999 — `cli_selectors` (um_draw)

| metric | cadr | pi |
|---|---|---|
| `um_draw` | `render-user-message-selector` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageSelectorComponent layout |

Leftover sibling of Pairs 997–998. Does not remount `render_user_message_selector`. Timed work is three/hit user-message selector render. Observed `umrd_three` / `umrd_hit` are exact. First n=5 freeze **105.189×** (312.691 / 2.973 µs) on host `Friend-MachineD`, ceiling 120.0 (raised from 100.0 for first Friend-MachineD freeze). Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1000 — `cli_selectors` (tosp_ok)

| metric | cadr | pi |
|---|---|---|
| `tosp_ok` | `trust-option-saved-p` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of isSavedOption |

Leftover sibling of leftover trust saved/ctor/layout remounts on trust.lisp. Does not remount `trust_option_saved_p`. Timed work is nil/distrust saved-option checks. Observed `tosp_nil` / `tosp_distrust` are exact. First n=5 freeze **1.914×** (51.075 / 26.680 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1001 — `cli_selectors` (mtss_ok)

| metric | cadr | pi |
|---|---|---|
| `mtss_ok` | `make-trust-selector-state` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of TrustSelectorComponent constructor |

Leftover sibling of Pair 1000. Does not remount `make_trust_selector_state`. Timed work is child/single trust selector construct. Observed `mtss_child` / `mtss_single` are exact. First n=5 freeze **1.937×** (164.943 / 85.159 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1002 — `cli_selectors` (rtrs_ok)

| metric | cadr | pi |
|---|---|---|
| `rtrs_ok` | `render-trust-selector` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of TrustSelectorComponent layout |

Leftover sibling of Pairs 1000–1001. Does not remount `render_trust_selector`. Timed work is default/single trust selector render. Observed `rtrs_default` / `rtrs_single` are exact. First n=5 freeze **7.030×** (1370.312 / 194.933 µs) on host `Friend-MachineD`, ceiling 15.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1003 — `cli_selectors` (mlms_ok)

| metric | cadr | pi |
|---|---|---|
| `mlms_ok` | `make-login-method-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of ExtensionSelector login-method constructor |

Leftover sibling of leftover auth login/api/oauth ctor remounts. Does not remount `make_login_method_selector_state`. Timed work is default/three login-method construct. Observed `mlms_default` / `mlms_three` are exact. First n=5 freeze **1.900×** (3.649 / 1.921 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1004 — `cli_selectors` (makis_ok)

| metric | cadr | pi |
|---|---|---|
| `makis_ok` | `make-api-key-input-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showPrompt api key Input constructor |

Leftover sibling of Pair 1003. Does not remount `make_api_key_input_state`. Timed work is anth/named api-key input construct. Observed `makis_anth` / `makis_named` are exact. First n=5 freeze **3.828×** (3.372 / 0.881 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1005 — `cli_selectors` (moss_ok)

| metric | cadr | pi |
|---|---|---|
| `moss_ok` | `make-oauth-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of OauthSelectorComponent constructor |

Leftover sibling of Pairs 1003–1004. Does not remount `make_oauth_selector_state`. Timed work is default/logout oauth selector construct. Observed `moss_default` / `moss_logout` are exact. First n=5 freeze **1.630×** (9.651 / 5.922 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1006 — `cli_extensions_install` (sc_ok)

| metric | cadr | pi |
|---|---|---|
| `sc_ok` | `split-extension-command` (`src/cadr-cli/extensions/commands.lisp`) | leftover replica of spaceIndex command/args split |

Leftover sibling of leftover 487–489 on commands.lisp. Does not remount `split_command`. Timed work is plain/reload command split. Observed `sc_plain` / `sc_reload` are exact. First n=5 freeze **0.926×** (0.835 / 0.902 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1× (cadr leads); not listed in over-1× table. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1007 — `cli_extensions_install` (hp_ok)

| metric | cadr | pi |
|---|---|---|
| `hp_ok` | `handle-extension-command plain` (`src/cadr-cli/extensions/commands.lisp`) | leftover replica of non-slash return |

Leftover sibling of Pair 1006. Does not remount `handle_plain`. Timed work is hello/blank non-slash handle. Observed `hp_hello` / `hp_blank` are exact. First n=5 freeze **1.012×** (0.604 / 0.597 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1008 — `cli_extensions_install` (hu_ok)

| metric | cadr | pi |
|---|---|---|
| `hu_ok` | `handle-extension-command unknown slash` (`src/cadr-cli/extensions/commands.lisp`) | leftover replica of getCommand miss |

Leftover sibling of Pairs 1006–1007. Does not remount `handle_unknown`. Timed work is nope/miss unknown slash handle. Observed `hu_nope` / `hu_miss` are exact. First n=5 freeze **0.710×** (0.779 / 1.097 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1× (cadr leads); not listed in over-1× table. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1009 — `cli_interactive_controller` (br_ok)

| metric | cadr | pi |
|---|---|---|
| `br_ok` | `append-tui-user-bash-running` (`src/cadr-cli/interactive/user-bash.lisp`) | leftover replica of BashExecutionComponent addChild running |

Leftover sibling of leftover 988–990 bash_go/end/off on user-bash.lisp. Does not remount `bash_run`. Timed work is n/run2 append running. Observed `bar_n` / `bar_run2` are exact. First n=5 freeze **3.907×** (1.316 / 0.337 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1010 — `cli_interactive_controller` (bf_ok)

| metric | cadr | pi |
|---|---|---|
| `bf_ok` | `complete-tui-user-bash-string` (`src/cadr-cli/interactive/user-bash.lisp`) | leftover replica of setComplete exit 0 string |

Leftover sibling of Pair 1009. Does not remount `bash_fin`. Timed work is text/empty complete string. Observed `cs_text` / `cs_empty` are exact. First n=5 freeze **5.260×** (1.405 / 0.267 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1011 — `cli_interactive_controller` (bh_ok)

| metric | cadr | pi |
|---|---|---|
| `bh_ok` | `stop-tui-user-bash-entry` (`src/cadr-cli/interactive/user-bash.lisp`) | leftover replica of loader.stop without setComplete |

Leftover sibling of Pairs 1009–1010. Does not remount `bash_halt`. Timed work is run/exit stop entry. Observed `st_run` / `st_exit` are exact. First n=5 freeze **7.203×** (1.345 / 0.187 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1015 — `powershell_tool` (up_ok)

| metric | cadr | pi |
|---|---|---|
| `up_ok` | `+powershell-utf8-output-prefix+` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of UTF8_OUTPUT_PREFIX |

Leftover sibling of leftover 301–303 on powershell.lisp. Does not remount `utf8_prefix`. Timed work is utf8 prefix length/bytes. Observed `psu_len` / `psu_utf8` are exact. First n=5 freeze **5.415×** (0.739 / 0.137 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1016 — `powershell_tool` (pc_ok)

| metric | cadr | pi |
|---|---|---|
| `pc_ok` | `UTF-8 prefix + command concatenate` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of prefix+command |

Leftover sibling of Pair 1015. Does not remount `prefix_command`. Timed work is empty/date prefix+command. Observed `psc_empty` / `psc_date` are exact. First n=5 freeze **3.197×** (0.873 / 0.273 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1017 — `powershell_tool` (mt_ok)

| metric | cadr | pi |
|---|---|---|
| `mt_ok` | `make-powershell-tool` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of createPowerShellToolDefinition |

Leftover sibling of Pairs 1015–1016. Does not remount `make_tool`. Timed work is name/desc make-tool. Observed `pmt_name` / `pmt_desc` are exact. First n=5 freeze **2.019×** (2.723 / 1.349 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1018 — `cli_selectors` (cd_sec)

| metric | cadr | pi |
|---|---|---|
| `cd_sec` | `countdown-seconds` (`src/cadr-cli/interactive/components/countdown.lisp`) | leftover replica of countdown-seconds |

Leftover sibling of countdown seconds/tick/render on countdown.lisp. Does not remount `countdown_seconds`. Timed work is countdown seconds. Observed `cds_*` are exact. First n=5 freeze **5.648×** (1.152 / 0.204 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1019 — `cli_selectors` (cd_tick)

| metric | cadr | pi |
|---|---|---|
| `cd_tick` | `countdown-tick` (`src/cadr-cli/interactive/components/countdown.lisp`) | leftover replica of countdown-tick |

Leftover sibling of Pair 1018. Does not remount `countdown_tick`. Timed work is countdown tick. Observed `cdt_*` are exact. First n=5 freeze **6.479×** (1.066 / 0.165 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1020 — `cli_selectors` (cd_rnd)

| metric | cadr | pi |
|---|---|---|
| `cd_rnd` | `countdown-render` (`src/cadr-cli/interactive/components/countdown.lisp`) | leftover replica of countdown-render |

Leftover sibling of Pairs 1018–1019. Does not remount `countdown_render`. Timed work is countdown render. Observed `cdr_*` are exact. First n=5 freeze **4.599×** (1.539 / 0.335 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1021 — `cli_selectors` (dax_rgb)

| metric | cadr | pi |
|---|---|---|
| `dax_rgb` | `daxnuts-rgb-at` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of daxnuts-rgb-at |

Leftover sibling of daxnuts rgb/make/tick on daxnuts.lisp. Does not remount `daxnuts_rgb_at`. Timed work is rgb-at. Observed `dra_*` are exact. First n=5 freeze **3.149×** (1.131 / 0.359 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1022 — `cli_selectors` (dax_make)

| metric | cadr | pi |
|---|---|---|
| `dax_make` | `make-daxnuts-component` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of make-daxnuts-component |

Leftover sibling of Pair 1021. Does not remount `make_daxnuts_component`. Timed work is make component. Observed `dmc_*` are exact. First n=5 freeze **6.531×** (0.999 / 0.153 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1023 — `cli_selectors` (dax_tick)

| metric | cadr | pi |
|---|---|---|
| `dax_tick` | `daxnuts-component-tick` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of daxnuts-component-tick |

Leftover sibling of Pairs 1021–1022. Does not remount `daxnuts_component_tick`. Timed work is component tick. Observed `dct_*` are exact. First n=5 freeze **8.845×** (5.142 / 0.581 µs) on host `Friend-MachineD`, ceiling 12.0 (raised from 8.0). Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1024 — `cli_selectors` (th_lbl)

| metric | cadr | pi |
|---|---|---|
| `th_lbl` | `thinking-level-label` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-level-label |

Leftover sibling of thinking label/query/kb on thinking.lisp. Does not remount `thinking_level_label`. Timed work is level label. Observed `tll_*` are exact. First n=5 freeze **1.960×** (0.386 / 0.197 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1025 — `cli_selectors` (th_qry)

| metric | cadr | pi |
|---|---|---|
| `th_qry` | `thinking-selector-set-query` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of set-query |

Leftover sibling of Pair 1024. Does not remount `thinking_selector_set_query`. Timed work is set query. Observed `tsq_*` are exact. First n=5 freeze **0.841×** (12.894 / 15.333 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1× (cadr leads); not listed in over-1× table. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1026 — `cli_selectors` (th_kb)

| metric | cadr | pi |
|---|---|---|
| `th_kb` | `thinking-selector-keybindings` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of keybindings |

Leftover sibling of Pairs 1024–1025. Does not remount `thinking_selector_keybindings`. Timed work is keybindings. Observed `tskb_*` are exact. First n=5 freeze **4.194×** (4.463 / 1.064 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1027 — `cli_selectors` (ld_wait)

| metric | cadr | pi |
|---|---|---|
| `ld_wait` | `login-dialog-show-waiting` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showWaiting |

Leftover sibling of login-dialog waiting/progress/manual on login-dialog.lisp. Does not remount `login_dialog_show_waiting`. Timed work is show waiting. Observed `ldw_*` are exact. First n=5 freeze **3.389×** (6.342 / 1.871 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1028 — `cli_selectors` (ld_prog)

| metric | cadr | pi |
|---|---|---|
| `ld_prog` | `login-dialog-show-progress` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showProgress |

Leftover sibling of Pair 1027. Does not remount `login_dialog_show_progress`. Timed work is show progress. Observed `ldp_*` are exact. First n=5 freeze **2.586×** (3.541 / 1.369 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1029 — `cli_selectors` (ld_man)

| metric | cadr | pi |
|---|---|---|
| `ld_man` | `login-dialog-show-manual-input` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showManualInput |

Leftover sibling of Pairs 1027–1028. Does not remount `login_dialog_show_manual_input`. Timed work is show manual input. Observed `ldmi_*` are exact. First n=5 freeze **2.650×** (6.210 / 2.343 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1030 — `cli_selectors` (ld_prmt)

| metric | cadr | pi |
|---|---|---|
| `ld_prmt` | `login-dialog-show-prompt` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showPrompt |

Leftover sibling of login-dialog prompt/info/details on login-dialog.lisp. Does not remount `login_dialog_show_prompt`. Timed work is show prompt. Observed `ldpr_*` are exact. First n=5 freeze **3.088×** (10.038 / 3.250 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1031 — `cli_selectors` (ld_info)

| metric | cadr | pi |
|---|---|---|
| `ld_info` | `login-dialog-show-info` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showInfo |

Leftover sibling of Pair 1030. Does not remount `login_dialog_show_info`. Timed work is show info. Observed `ldi_*` are exact. First n=5 freeze **3.050×** (10.904 / 3.575 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1032 — `cli_selectors` (ld_det)

| metric | cadr | pi |
|---|---|---|
| `ld_det` | `login-dialog-show-details` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showDetails |

Leftover sibling of Pairs 1030–1031. Does not remount `login_dialog_show_details`. Timed work is show details. Observed `lddt_*` are exact. First n=5 freeze **0.822×** (3.050 / 3.708 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1× (cadr leads); not listed in over-1× table. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1033 — `cli_selectors` (ld_cmp)

| metric | cadr | pi |
|---|---|---|
| `ld_cmp` | `login-dialog-complete-input` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.replaceInputWithSubmittedText |

Leftover sibling of login-dialog complete/handle/render on login-dialog.lisp. Does not remount `login_dialog_complete_input`. Timed work is complete input. Observed `ldci_*` are exact. First n=5 freeze **2.256×** (6.716 / 2.977 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1034 — `cli_selectors` (ld_evt)

| metric | cadr | pi |
|---|---|---|
| `ld_evt` | `login-dialog-handle-event` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.handleInput |

Leftover sibling of Pair 1033. Does not remount `login_dialog_handle_event`. Timed work is handle event. Observed `ldhe_*` are exact. First n=5 freeze **3.257×** (7.339 / 2.254 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1035 — `cli_selectors` (ld_rnd)

| metric | cadr | pi |
|---|---|---|
| `ld_rnd` | `render-login-dialog` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.render |

Leftover sibling of Pairs 1033–1034. Does not remount `render_login_dialog`. Timed work is render. Observed `ldrd_*` are exact. First n=5 freeze **59.042×** (98.051 / 1.661 µs) on host `Friend-MachineD`, ceiling 70.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1036 — `cli_selectors` (um_he)

| metric | cadr | pi |
|---|---|---|
| `um_he` | `user-message-handle-event` (`src/cadr-cli/interactive/selectors/user-message.lisp`) | leftover replica of UserMessageList.handleInput structured |

Leftover sibling of user-message handle/render on user-message selector. Does not remount `user_message_handle_event`. Timed work is structured handle. Observed `umhe_*` are exact. First n=5 freeze **2.984×** (1.736 / 0.582 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1037 — `cli_selectors` (um_hr)

| metric | cadr | pi |
|---|---|---|
| `um_hr` | `user-message-handle-raw` (`src/cadr-cli/interactive/selectors/user-message.lisp`) | leftover replica of UserMessageList.handleInput raw |

Leftover sibling of Pair 1036. Does not remount `user_message_handle_raw`. Timed work is raw handle. Observed `umhr_*` are exact. First n=5 freeze **12.654×** (95.867 / 7.576 µs) on host `Friend-MachineD`, ceiling 16.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1038 — `cli_selectors` (um_rd)

| metric | cadr | pi |
|---|---|---|
| `um_rd` | `render-user-message-selector` (`src/cadr-cli/interactive/selectors/user-message.lisp`) | leftover replica of UserMessageSelectorComponent layout |

Leftover sibling of Pairs 1036–1037. Does not remount `render_user_message_selector`. Timed work is render. Observed `umrd_*` are exact. First n=5 freeze **225.713×** (276.946 / 1.227 µs) on host `Friend-MachineD`, ceiling 250.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1039 — `cli_selectors` (ms_kb)

| metric | cadr | pi |
|---|---|---|
| `ms_kb` | `make-models-selector-keybindings` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of models KeybindingsManager constructor |

Leftover sibling of models keybindings/scoped/render on models selector. Does not remount `make_models_selector_keybindings`. Timed work is keybindings ctor. Observed `mmskb_*` are exact. First n=5 freeze **0.517×** (29.638 / 57.314 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1× (cadr leads); not listed in over-1× table. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1040 — `cli_selectors` (sm_st)

| metric | cadr | pi |
|---|---|---|
| `sm_st` | `make-scoped-models-selector-state` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of ScopedModelsSelectorComponent constructor |

Leftover sibling of Pair 1039. Does not remount `make_scoped_models_selector_state`. Timed work is scoped state ctor. Observed `msmksc_*` are exact. First n=5 freeze **24.651×** (107.261 / 4.351 µs) on host `Friend-MachineD`, ceiling 40.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1041 — `cli_selectors` (rm_sel)

| metric | cadr | pi |
|---|---|---|
| `rm_sel` | `render-model-selector` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of ModelSelectorComponent layout |

Leftover sibling of Pairs 1039–1040. Does not remount `render_model_selector`. Timed work is render. Observed `rms_*` are exact. First n=5 freeze **28.160×** (184.907 / 6.566 µs) on host `Friend-MachineD`, ceiling 50.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1141 — `cli_selectors` (lat_ok)

| metric | cadr | pi |
|---|---|---|
| `lat_ok` | `login-auth-type-route` (`src/cadr-cli/interactive/selectors/login.lisp`) | leftover replica of showLoginAuthTypeSelector routing |

Leftover sibling unused-slug remount on login selectors. Does not remount `login_auth_type_route`. Timed work is the remounted path. Observed `latr_*` are exact. First n=5 freeze **2.118×** (3.668 / 1.731 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1142 — `cli_selectors` (lpo_ok)

| metric | cadr | pi |
|---|---|---|
| `lpo_ok` | `login-provider-options` (`src/cadr-cli/interactive/selectors/login.lisp`) | leftover replica of getLoginProviderOptions |

Leftover sibling unused-slug remount on login selectors. Does not remount `login_provider_options`. Timed work is the remounted path. Observed `lpo_*` are exact. First n=5 freeze **3.415×** (12.585 / 3.685 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1143 — `cli_selectors` (lgo_ok)

| metric | cadr | pi |
|---|---|---|
| `lgo_ok` | `logout-provider-options` (`src/cadr-cli/interactive/selectors/login.lisp`) | leftover replica of getLogoutProviderOptions |

Leftover sibling unused-slug remount on login selectors. Does not remount `logout_provider_options`. Timed work is the remounted path. Observed `lgo_*` are exact. First n=5 freeze **2.824×** (10.328 / 3.658 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1042 — `cli_selectors` (th_af)

| metric | cadr | pi |
|---|---|---|
| `th_af` | `thinking-selector-apply-filter` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking applyFilter |

Leftover sibling unused-slug remount on thinking selectors. Does not remount `thinking_selector_apply_filter`. Timed work is the remounted path. Observed `tsaf_*` are exact. First n=5 freeze **0.776×** (14.863 / 19.147 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1× (cadr leads); not listed in over-1× table. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1043 — `cli_selectors` (th_cl)

| metric | cadr | pi |
|---|---|---|
| `th_cl` | `thinking-selector-clamp-selected` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking clampSelected |

Leftover sibling unused-slug remount on thinking selectors. Does not remount `thinking_selector_clamp_selected`. Timed work is the remounted path. Observed `tscl_*` are exact. First n=5 freeze **3.075×** (1.557 / 0.506 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1044 — `cli_selectors` (th_sc)

| metric | cadr | pi |
|---|---|---|
| `th_sc` | `thinking-selector-select-current` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking selectCurrent |

Leftover sibling unused-slug remount on thinking selectors. Does not remount `thinking_selector_select_current`. Timed work is the remounted path. Observed `tssc_*` are exact. First n=5 freeze **1.919×** (1.870 / 0.975 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1045 — `cli_selectors` (th_mv)

| metric | cadr | pi |
|---|---|---|
| `th_mv` | `thinking-selector-move` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking move |

Leftover sibling unused-slug remount on thinking selectors. Does not remount `thinking_selector_move`. Timed work is the remounted path. Observed `tsmv_*` are exact. First n=5 freeze **2.244×** (1.128 / 0.502 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1046 — `cli_selectors` (th_lv)

| metric | cadr | pi |
|---|---|---|
| `th_lv` | `thinking-selector-selected-level` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking selectedLevel |

Leftover sibling unused-slug remount on thinking selectors. Does not remount `thinking_selector_selected_level`. Timed work is the remounted path. Observed `tssl_*` are exact. First n=5 freeze **1.231×** (0.877 / 0.712 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1047 — `cli_selectors` (th_ds)

| metric | cadr | pi |
|---|---|---|
| `th_ds` | `thinking-level-description-line` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking descriptionLine |

Leftover sibling unused-slug remount on thinking selectors. Does not remount `thinking_level_description_line`. Timed work is the remounted path. Observed `tsdl_*` are exact. First n=5 freeze **3.296×** (0.596 / 0.181 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1048 — `cli_selectors` (tr_pto)

| metric | cadr | pi |
|---|---|---|
| `tr_pto` | `project-trust-options` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of projectTrustOptions |

Leftover sibling unused-slug remount on trust selectors. Does not remount `project_trust_options`. Timed work is the remounted path. Observed `pto_*` are exact. First n=5 freeze **1.662×** (72.698 / 43.738 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1049 — `cli_selectors` (tr_tss)

| metric | cadr | pi |
|---|---|---|
| `tr_tss` | `trust-selector-selection` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of trustSelectorSelection |

Leftover sibling unused-slug remount on trust selectors. Does not remount `trust_selector_selection`. Timed work is the remounted path. Observed `tss_*` are exact. First n=5 freeze **5.820×** (251.711 / 43.252 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1050 — `cli_selectors` (tr_tdd)

| metric | cadr | pi |
|---|---|---|
| `tr_tdd` | `trust-decision-description` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of trustDecisionDescription |

Leftover sibling unused-slug remount on trust selectors. Does not remount `trust_decision_description`. Timed work is the remounted path. Observed `tdd_*` are exact. First n=5 freeze **3.101×** (176.212 / 56.817 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1051 — `cli_selectors` (tr_mv)

| metric | cadr | pi |
|---|---|---|
| `tr_mv` | `trust-selector-move` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of trust move |

Leftover sibling unused-slug remount. Does not remount `trust_selector_move`. Timed work is the remounted path. Observed `tsm_*` are exact. First n=5 freeze **2.529×** (286.724 / 113.395 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1052 — `cli_selectors` (tr_he)

| metric | cadr | pi |
|---|---|---|
| `tr_he` | `trust-selector-handle-event` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of trust handleEvent |

Leftover sibling unused-slug remount. Does not remount `trust_selector_handle_event`. Timed work is the remounted path. Observed `tshe_*` are exact. First n=5 freeze **2.405×** (301.199 / 125.263 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1053 — `cli_selectors` (tr_ui)

| metric | cadr | pi |
|---|---|---|
| `tr_ui` | `trust-selector-ui-state` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of trust uiState |

Leftover sibling unused-slug remount. Does not remount `trust_selector_ui_state`. Timed work is the remounted path. Observed `rts_*` are exact. First n=5 freeze **2.093×** (335.271 / 160.186 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1054 — `cli_selectors` (oa_lbl)

| metric | cadr | pi |
|---|---|---|
| `oa_lbl` | `oauth-option-status-label` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of oauthOptionStatusLabel |

Leftover sibling unused-slug remount. Does not remount `oauth_option_status_label`. Timed work is the remounted path. Observed `oosl_*` are exact. First n=5 freeze **1.443×** (1.961 / 1.359 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1055 — `cli_selectors` (oa_typ)

| metric | cadr | pi |
|---|---|---|
| `oa_typ` | `credential-entry-auth-type` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of credentialEntryAuthType |

Leftover sibling unused-slug remount. Does not remount `credential_entry_auth_type`. Timed work is the remounted path. Observed `ceat_*` are exact. First n=5 freeze **1.254×** (0.575 / 0.458 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1056 — `cli_selectors` (oa_env)

| metric | cadr | pi |
|---|---|---|
| `oa_env` | `oauth-environment-source-p` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of oauthEnvironmentSource |

Leftover sibling unused-slug remount. Does not remount `oauth_environment_source_p`. Timed work is the remounted path. Observed `oesp_*` are exact. First n=5 freeze **1.548×** (1.061 / 0.686 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1057 — `cli_selectors` (oa_sel)

| metric | cadr | pi |
|---|---|---|
| `oa_sel` | `oauth-selector-selection` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of oauthSelectorSelection |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_selection`. Timed work is the remounted path. Observed `oss_*` are exact. First n=5 freeze **13.640×** (75.871 / 5.562 µs) on host `Friend-MachineD`, ceiling 20.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1058 — `cli_selectors` (oa_flt)

| metric | cadr | pi |
|---|---|---|
| `oa_flt` | `oauth-selector-apply-filter` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of oauthSelectorApplyFilter |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_apply_filter`. Timed work is the remounted path. Observed `osaf_*` are exact. First n=5 freeze **8.536×** (78.512 / 9.198 µs) on host `Friend-MachineD`, ceiling 12.0 (raised 8→12). Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1059 — `cli_selectors` (oa_qry)

| metric | cadr | pi |
|---|---|---|
| `oa_qry` | `oauth-selector-search-text` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of oauthSelectorSearchText |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_search_text`. Timed work is the remounted path. Observed `osst_*` are exact. First n=5 freeze **4.565×** (1.461 / 0.320 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1060 — `cli_selectors` (oa_rt)

| metric | cadr | pi |
|---|---|---|
| `oa_rt` | `login-auth-type-route` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showLoginAuthTypeSelector |

Leftover sibling unused-slug remount. Does not remount `login_auth_type_route`. Timed work is the remounted path. Observed `latr_*` are exact. First n=5 freeze **3.735×** (3.335 / 0.893 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1061 — `cli_selectors` (oa_lin)

| metric | cadr | pi |
|---|---|---|
| `oa_lin` | `login-provider-options` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of getLoginProviderOptions |

Leftover sibling unused-slug remount. Does not remount `login_provider_options`. Timed work is the remounted path. Observed `lpo_*` are exact. First n=5 freeze **3.566×** (10.793 / 3.027 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1062 — `cli_selectors` (oa_out)

| metric | cadr | pi |
|---|---|---|
| `oa_out` | `logout-provider-options` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of getLogoutProviderOptions |

Leftover sibling unused-slug remount. Does not remount `logout_provider_options`. Timed work is the remounted path. Observed `lgo_*` are exact. First n=5 freeze **3.953×** (8.807 / 2.228 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1063 — `cli_selectors` (oa_lmh)

| metric | cadr | pi |
|---|---|---|
| `oa_lmh` | `login-method-selector-handle-event` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of loginMethod handleEvent |

Leftover sibling unused-slug remount. Does not remount `login_method_selector_handle_event`. Timed work is the remounted path. Observed `lmhe_*` are exact. First n=5 freeze **1.768×** (3.612 / 2.043 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1064 — `cli_selectors` (oa_lui)

| metric | cadr | pi |
|---|---|---|
| `oa_lui` | `login-method-selector-ui-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of loginMethod uiState |

Leftover sibling unused-slug remount. Does not remount `login_method_selector_ui_state`. Timed work is the remounted path. Observed `lmsui_*` are exact. First n=5 freeze **6.409×** (515.508 / 80.430 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1065 — `cli_selectors` (oa_aki)

| metric | cadr | pi |
|---|---|---|
| `oa_aki` | `api-key-input-ui-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of apiKeyInput uiState |

Leftover sibling unused-slug remount. Does not remount `api_key_input_ui_state`. Timed work is the remounted path. Observed `akiui_*` are exact. First n=5 freeze **2.990×** (233.752 / 78.178 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1066 — `cli_selectors` (oa_akhe)

| metric | cadr | pi |
|---|---|---|
| `oa_akhe` | `api-key-input-state-handle-event` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of apiKeyInput handleEvent |

Leftover sibling unused-slug remount. Does not remount `api_key_input_state_handle_event`. Timed work is the remounted path. Observed `akhe_*` are exact. First n=5 freeze **0.657×** (8.093 / 12.312 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1× (cadr leads); not listed in over-1× table. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1067 — `cli_selectors` (oa_mls)

| metric | cadr | pi |
|---|---|---|
| `oa_mls` | `make-login-method-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of makeLoginMethodSelectorState |

Leftover sibling unused-slug remount. Does not remount `make_login_method_selector_state`. Timed work is the remounted path. Observed `mlms_*` are exact. First n=5 freeze **2.478×** (4.539 / 1.831 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1068 — `cli_selectors` (oa_ais)

| metric | cadr | pi |
|---|---|---|
| `oa_ais` | `make-api-key-input-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of makeApiKeyInputState |

Leftover sibling unused-slug remount. Does not remount `make_api_key_input_state`. Timed work is the remounted path. Observed `makis_*` are exact. First n=5 freeze **3.580×** (3.248 / 0.907 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1069 — `cli_selectors` (th_he)

| metric | cadr | pi |
|---|---|---|
| `th_he` | `thinking-selector-handle-event` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking handleEvent |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_handle_event`. Timed work is the remounted path. Observed `the_*` are exact. First n=5 freeze **1.142×** (4.958 / 4.343 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1070 — `cli_selectors` (th_mts)

| metric | cadr | pi |
|---|---|---|
| `th_mts` | `make-thinking-selector-state` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of makeThinkingSelectorState |

Leftover sibling unused-slug remount. Does not remount `make_thinking_selector_state`. Timed work is the remounted path. Observed `tms_*` are exact. First n=5 freeze **2.582×** (2.324 / 0.900 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1071 — `cli_selectors` (th_lst)

| metric | cadr | pi |
|---|---|---|
| `th_lst` | `thinking-level-search-text` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinkingLevelSearchText |

Leftover sibling unused-slug remount. Does not remount `thinking_level_search_text`. Timed work is the remounted path. Observed `tlst_*` are exact. First n=5 freeze **6.810×** (1.536 / 0.226 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1072 — `cli_selectors` (oa_ohe)

| metric | cadr | pi |
|---|---|---|
| `oa_ohe` | `oauth-selector-handle-event` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of oauth handleEvent |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_handle_event`. Timed work is the remounted path. Observed `oshe_*` are exact. First n=5 freeze **12.153×** (134.720 / 11.085 µs) on host `Friend-MachineD`, ceiling 20.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1073 — `cli_selectors` (oa_mos)

| metric | cadr | pi |
|---|---|---|
| `oa_mos` | `make-oauth-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of makeOauthSelectorState |

Leftover sibling unused-slug remount. Does not remount `make_oauth_selector_state`. Timed work is the remounted path. Observed `moss_*` are exact. First n=5 freeze **1.155×** (11.495 / 9.950 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1074 — `cli_selectors` (oa_sst)

| metric | cadr | pi |
|---|---|---|
| `oa_sst` | `oauth-selector-search-text` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of oauth searchText |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_search_text`. Timed work is the remounted path. Observed `osst_*` are exact. First n=5 freeze **2.920×** (1.769 / 0.606 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1075 — `cli_selectors` (oa_osr)

| metric | cadr | pi |
|---|---|---|
| `oa_osr` | `oauth-option-status-rendered` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of oauthOptionStatusRendered |

Leftover sibling unused-slug remount. Does not remount `oauth_option_status_rendered`. Timed work is the remounted path. Observed `oosr_*` are exact. First n=5 freeze **7.459×** (10.627 / 1.425 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1076 — `cli_selectors` (oa_osl)

| metric | cadr | pi |
|---|---|---|
| `oa_osl` | `oauth-option-status-label` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of oauthOptionStatusLabel |

Leftover sibling unused-slug remount. Does not remount `oauth_option_status_label`. Timed work is the remounted path. Observed `oosl_*` are exact. First n=5 freeze **2.963×** (2.286 / 0.772 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1077 — `cli_selectors` (oa_cet)

| metric | cadr | pi |
|---|---|---|
| `oa_cet` | `credential-entry-auth-type` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of credentialEntryAuthType |

Leftover sibling unused-slug remount. Does not remount `credential_entry_auth_type`. Timed work is the remounted path. Observed `ceat_*` are exact. First n=5 freeze **2.746×** (0.682 / 0.248 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1078 — `cli_selectors` (oa_hri)

| metric | cadr | pi |
|---|---|---|
| `oa_hri` | `oauth-selector-handle-raw-input` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of oauth-selector handleInput raw key dispatch |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_handle_raw_input`. Timed work is the remounted path. Observed `oshri_*` are exact. First n=5 freeze **3.896×** (620.744 / 159.344 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1079 — `cli_selectors` (oa_esp)

| metric | cadr | pi |
|---|---|---|
| `oa_esp` | `oauth-environment-source-p` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of env source regex |

Leftover sibling unused-slug remount. Does not remount `oauth_environment_source_p`. Timed work is the remounted path. Observed `oesp_*` are exact. First n=5 freeze **3.229×** (1.200 / 0.372 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1080 — `cli_selectors` (oa_lgo)

| metric | cadr | pi |
|---|---|---|
| `oa_lgo` | `logout-provider-options` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of getLogoutProviderOptions |

Leftover sibling unused-slug remount. Does not remount `logout_provider_options`. Timed work is the remounted path. Observed `lgo_*` are exact. First n=5 freeze **2.095×** (11.156 / 5.324 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1081 — `cli_selectors` (oa_lat)

| metric | cadr | pi |
|---|---|---|
| `oa_lat` | `login-auth-type-route` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showLoginAuthTypeSelector routing |

Leftover sibling unused-slug remount. Does not remount `login_auth_type_route`. Timed work is the remounted path. Observed `latr_*` are exact. First n=5 freeze **3.516×** (3.632 / 1.033 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1082 — `cli_selectors` (oa_lpo)

| metric | cadr | pi |
|---|---|---|
| `oa_lpo` | `login-provider-options` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of getLoginProviderOptions |

Leftover sibling unused-slug remount. Does not remount `login_provider_options`. Timed work is the remounted path. Observed `lpo_*` are exact. First n=5 freeze **1.922×** (14.676 / 7.636 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1083 — `cli_selectors` (oa_lhe)

| metric | cadr | pi |
|---|---|---|
| `oa_lhe` | `login-method-selector-handle-event` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of login-method-selector handleInput |

Leftover sibling unused-slug remount. Does not remount `login_method_selector_handle_event`. Timed work is the remounted path. Observed `lmhe_*` are exact. First n=5 freeze **1.778×** (4.008 / 2.254 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1084 — `cli_selectors` (oa_lms)

| metric | cadr | pi |
|---|---|---|
| `oa_lms` | `login-method-selector-ui-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of login-method-selector UI state |

Leftover sibling unused-slug remount. Does not remount `login_method_selector_ui_state`. Timed work is the remounted path. Observed `lmsui_*` are exact. First n=5 freeze **4.808×** (498.558 / 103.684 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1085 — `cli_selectors` (oa_aku)

| metric | cadr | pi |
|---|---|---|
| `oa_aku` | `api-key-input-ui-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of api-key-input UI state |

Leftover sibling unused-slug remount. Does not remount `api_key_input_ui_state`. Timed work is the remounted path. Observed `akiui_*` are exact. First n=5 freeze **2.151×** (230.325 / 107.085 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1086 — `cli_selectors` (oa_ahe)

| metric | cadr | pi |
|---|---|---|
| `oa_ahe` | `api-key-input-state-handle-event` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of api-key-input handleInput |

Leftover sibling unused-slug remount. Does not remount `api_key_input_state_handle_event`. Timed work is the remounted path. Observed `akhe_*` are exact. First n=5 freeze **1.642×** (7.956 / 4.847 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1087 — `cli_selectors` (sec_ok)

| metric | cadr | pi |
|---|---|---|
| `sec_ok` | `Math.ceil(timeoutMs/1000)` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of Math.ceil(timeoutMs/1000) |

Leftover sibling unused-slug remount. Does not remount `countdown_seconds`. Timed work is the remounted path. Observed `cds_*` are exact. First n=5 freeze **3.567×** (1.199 / 0.336 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1088 — `cli_selectors` (tick_ok)

| metric | cadr | pi |
|---|---|---|
| `tick_ok` | `countdown-timer-tick` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of countdown tick |

Leftover sibling unused-slug remount. Does not remount `countdown_tick`. Timed work is the remounted path. Observed `cdt_*` are exact. First n=5 freeze **3.994×** (1.269 / 0.318 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1089 — `cli_selectors` (rnd_ok)

| metric | cadr | pi |
|---|---|---|
| `rnd_ok` | `countdown-request-render` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of countdown requestRender |

Leftover sibling unused-slug remount. Does not remount `countdown_render`. Timed work is the remounted path. Observed `cdr_*` are exact. First n=5 freeze **3.484×** (1.467 / 0.421 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1090 — `cli_selectors` (ps_up)

| metric | cadr | pi |
|---|---|---|
| `ps_up` | `powershell-utf8-output-prefix` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of UTF8_OUTPUT_PREFIX |

Leftover sibling unused-slug remount. Does not remount `utf8_prefix`. Timed work is the remounted path. Observed `psu_*` are exact. First n=5 freeze **6.778×** (0.846 / 0.125 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1091 — `cli_selectors` (ps_pc)

| metric | cadr | pi |
|---|---|---|
| `ps_pc` | `prefix+command` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of prefix+command |

Leftover sibling unused-slug remount. Does not remount `prefix_command`. Timed work is the remounted path. Observed `psc_*` are exact. First n=5 freeze **4.067×** (1.246 / 0.306 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1092 — `cli_selectors` (ps_mt)

| metric | cadr | pi |
|---|---|---|
| `ps_mt` | `make-powershell-tool` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of createPowerShellToolDefinition |

Leftover sibling unused-slug remount. Does not remount `make_tool`. Timed work is the remounted path. Observed `pmt_*` are exact. First n=5 freeze **1.930×** (4.116 / 2.133 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1093 — `cli_selectors` (dn_rgb)

| metric | cadr | pi |
|---|---|---|
| `dn_rgb` | `daxnuts-rgb-at` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of parseImage pixel lookup |

Leftover sibling unused-slug remount. Does not remount `daxnuts_rgb_at`. Timed work is the remounted path. Observed `dra_*` are exact. First n=5 freeze **3.909×** (1.580 / 0.404 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1094 — `cli_selectors` (dn_make)

| metric | cadr | pi |
|---|---|---|
| `dn_make` | `daxnuts-component-tick` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of DaxnutsComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_daxnuts_component`. Timed work is the remounted path. Observed `dmc_*` are exact. First n=5 freeze **4.636×** (1.395 / 0.301 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1095 — `cli_selectors` (dn_tick)

| metric | cadr | pi |
|---|---|---|
| `dn_tick` | `daxnuts-component-tick` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of DaxnutsComponent interval |

Leftover sibling unused-slug remount. Does not remount `daxnuts_component_tick`. Timed work is the remounted path. Observed `dct_*` are exact. First n=5 freeze **15.673×** (5.390 / 0.344 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1096 — `cli_bootstrap_sessions` (psb_ok)

| metric | cadr | pi |
|---|---|---|
| `psb_ok` | `parse-user-bash-input` (`src/cadr-cli/repl.lisp`) | leftover replica of ! / !! bash extract |

Leftover sibling unused-slug remount. Does not remount `parse_bash`. Timed work is the remounted path. Observed `pb_*` are exact. First n=5 freeze **1.225×** (1.042 / 0.851 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1097 — `cli_bootstrap_sessions` (rst_ok)

| metric | cadr | pi |
|---|---|---|
| `rst_ok` | `response-text` (`src/cadr-cli/repl.lisp`) | leftover replica of textParts.join |

Leftover sibling unused-slug remount. Does not remount `response_text`. Timed work is the remounted path. Observed `rt_*` are exact. First n=5 freeze **2.482×** (1.737 / 0.700 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1098 — `cli_bootstrap_sessions` (dsp_ok)

| metric | cadr | pi |
|---|---|---|
| `dsp_ok` | `dispatch-user-input` (`src/cadr-cli/repl.lisp`) | leftover replica of submit classify |

Leftover sibling unused-slug remount. Does not remount `dispatch_plain`. Timed work is the remounted path. Observed `dp_*` are exact. First n=5 freeze **0.810×** (0.811 / 1.001 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1× (cadr leads); not listed in over-1× table. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1099 — `cli_selectors` (tlbl_ok)

| metric | cadr | pi |
|---|---|---|
| `tlbl_ok` | `thinking-level-label` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking level label |

Leftover sibling unused-slug remount. Does not remount `thinking_level_label`. Timed work is the remounted path. Observed `tll_*` are exact. First n=5 freeze **3.419×** (0.484 / 0.142 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1100 — `cli_selectors` (tqry_ok)

| metric | cadr | pi |
|---|---|---|
| `tqry_ok` | `thinking-selector-set-query` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking applyFilter from search |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_set_query`. Timed work is the remounted path. Observed `tsq_*` are exact. First n=5 freeze **1.429×** (12.620 / 8.834 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1101 — `cli_selectors` (tkb_ok)

| metric | cadr | pi |
|---|---|---|
| `tkb_ok` | `thinking-selector-keybindings` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking getKeybindings |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_keybindings`. Timed work is the remounted path. Observed `tskb_*` are exact. First n=5 freeze **11.805×** (3.415 / 0.289 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1102 — `cli_selectors` (wait_ok)

| metric | cadr | pi |
|---|---|---|
| `wait_ok` | `login-dialog-show-waiting` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showWaiting |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_waiting`. Timed work is the remounted path. Observed `ldw_*` are exact. First n=5 freeze **5.365×** (7.978 / 1.487 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1103 — `cli_selectors` (prog_ok)

| metric | cadr | pi |
|---|---|---|
| `prog_ok` | `login-dialog-show-progress` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showProgress |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_progress`. Timed work is the remounted path. Observed `ldp_*` are exact. First n=5 freeze **4.332×** (4.603 / 1.062 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1104 — `cli_selectors` (man_ok)

| metric | cadr | pi |
|---|---|---|
| `man_ok` | `login-dialog-show-manual-input` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showManualInput |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_manual_input`. Timed work is the remounted path. Observed `ldmi_*` are exact. First n=5 freeze **5.021×** (8.147 / 1.623 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1105 — `cli_selectors` (prmt_ok)

| metric | cadr | pi |
|---|---|---|
| `prmt_ok` | `login-dialog-show-prompt` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showPrompt |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_prompt`. Timed work is the remounted path. Observed `ldpr_*` are exact. First n=5 freeze **4.795×** (8.683 / 1.811 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1106 — `cli_selectors` (info_ok)

| metric | cadr | pi |
|---|---|---|
| `info_ok` | `login-dialog-show-info` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showInfo |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_info`. Timed work is the remounted path. Observed `ldi_*` are exact. First n=5 freeze **2.351×** (13.436 / 5.714 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1107 — `cli_selectors` (det_ok)

| metric | cadr | pi |
|---|---|---|
| `det_ok` | `login-dialog-show-details` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showDetails |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_details`. Timed work is the remounted path. Observed `lddt_*` are exact. First n=5 freeze **0.971×** (3.776 / 3.888 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1× (cadr leads); not listed in over-1× table. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1108 — `cli_selectors` (cmp_ok)

| metric | cadr | pi |
|---|---|---|
| `cmp_ok` | `login-dialog-complete-input` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.replaceInputWithSubmittedText |

Leftover sibling unused-slug remount. Does not remount `login_dialog_complete_input`. Timed work is the remounted path. Observed `ldci_*` are exact. First n=5 freeze **5.672×** (7.304 / 1.288 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1109 — `cli_selectors` (evt_ok)

| metric | cadr | pi |
|---|---|---|
| `evt_ok` | `login-dialog-state-handle-event` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.handleInput |

Leftover sibling unused-slug remount. Does not remount `login_dialog_handle_event`. Timed work is the remounted path. Observed `ldhe_*` are exact. First n=5 freeze **3.956×** (8.149 / 2.060 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1110 — `cli_selectors` (rnd2_ok)

| metric | cadr | pi |
|---|---|---|
| `rnd2_ok` | `render-login-dialog-state` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_login_dialog`. Timed work is the remounted path. Observed `ldrd_*` are exact. First n=5 freeze **48.784×** (104.030 / 2.132 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1111 — `cli_selectors` (he_ok)

| metric | cadr | pi |
|---|---|---|
| `he_ok` | `user-message-selector-handle-event` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageList.handleInput (structured) |

Leftover sibling unused-slug remount. Does not remount `user_message_handle_event`. Timed work is the remounted path. Observed `umhe_*` are exact. First n=5 freeze **1.670×** (1.652 / 0.989 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1112 — `cli_selectors` (raw_ok)

| metric | cadr | pi |
|---|---|---|
| `raw_ok` | `user-message-selector-handle-raw-input` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageList.handleInput (raw) |

Leftover sibling unused-slug remount. Does not remount `user_message_handle_raw`. Timed work is the remounted path. Observed `umhr_*` are exact. First n=5 freeze **16.062×** (91.365 / 5.688 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1113 — `cli_selectors` (sel_ok)

| metric | cadr | pi |
|---|---|---|
| `sel_ok` | `render-user-message-selector` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageSelectorComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_user_message_selector`. Timed work is the remounted path. Observed `umrd_*` are exact. First n=5 freeze **115.242×** (254.663 / 2.210 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1114 — `cli_selectors` (kb_ok)

| metric | cadr | pi |
|---|---|---|
| `kb_ok` | `make-models-selector-keybindings` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of KEYBINDINGS app.models.* constructor |

Leftover sibling unused-slug remount. Does not remount `make_models_selector_keybindings`. Timed work is the remounted path. Observed `mmskb_*` are exact. First n=5 freeze **1.012×** (30.920 / 30.541 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1115 — `cli_selectors` (sms_ok)

| metric | cadr | pi |
|---|---|---|
| `sms_ok` | `make-scoped-models-selector-state` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of ScopedModelsSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_scoped_models_selector_state`. Timed work is the remounted path. Observed `msmksc_*` are exact. First n=5 freeze **28.561×** (109.309 / 3.827 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1116 — `cli_selectors` (rms_ok)

| metric | cadr | pi |
|---|---|---|
| `rms_ok` | `render-model-selector` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of ModelSelectorComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_model_selector`. Timed work is the remounted path. Observed `rms_*` are exact. First n=5 freeze **28.581×** (187.216 / 6.550 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1117 — `cli_selectors` (af_ok)

| metric | cadr | pi |
|---|---|---|
| `af_ok` | `thinking-selector-apply-filter` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector applyFilter |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_apply_filter`. Timed work is the remounted path. Observed `tsaf_*` are exact. First n=5 freeze **1.728×** (17.747 / 10.269 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1118 — `cli_selectors` (cl_ok)

| metric | cadr | pi |
|---|---|---|
| `cl_ok` | `thinking-selector-clamp-selected` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector clamp selected |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_clamp_selected`. Timed work is the remounted path. Observed `tscl_*` are exact. First n=5 freeze **4.795×** (0.906 / 0.189 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1119 — `cli_selectors` (sc_ok)

| metric | cadr | pi |
|---|---|---|
| `sc_ok` | `thinking-selector-select-current` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector select current |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_select_current`. Timed work is the remounted path. Observed `tssc_*` are exact. First n=5 freeze **3.825×** (1.283 / 0.335 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1120 — `cli_selectors` (mv_ok)

| metric | cadr | pi |
|---|---|---|
| `mv_ok` | `thinking-selector-move` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector wrap selected index |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_move`. Timed work is the remounted path. Observed `tsmv_*` are exact. First n=5 freeze **9.747×** (1.300 / 0.133 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1121 — `cli_selectors` (hri_ok)

| metric | cadr | pi |
|---|---|---|
| `hri_ok` | `thinking-selector-handle-raw-input` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector handleInput keybindings |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_handle_raw_input`. Timed work is the remounted path. Observed `tshri_*` are exact. First n=5 freeze **16.019×** (161.015 / 10.052 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1122 — `cli_selectors` (hev_ok)

| metric | cadr | pi |
|---|---|---|
| `hev_ok` | `thinking-selector-handle-event` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector typed event dispatch |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_handle_event`. Timed work is the remounted path. Observed `tshe_*` are exact. First n=5 freeze **1.738×** (4.005 / 2.304 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1123 — `cli_selectors` (sv_ok)

| metric | cadr | pi |
|---|---|---|
| `sv_ok` | `trust-option-saved-p` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of trust-selector isSavedOption |

Leftover sibling unused-slug remount. Does not remount `trust_option_saved_p`. Timed work is the remounted path. Observed `tosp_*` are exact. First n=5 freeze **1.560×** (56.278 / 36.077 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1124 — `cli_selectors` (mk_ok)

| metric | cadr | pi |
|---|---|---|
| `mk_ok` | `make-trust-selector-state` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of TrustSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_trust_selector_state`. Timed work is the remounted path. Observed `mtss_*` are exact. First n=5 freeze **1.340×** (145.127 / 108.325 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1125 — `cli_selectors` (trn_ok)

| metric | cadr | pi |
|---|---|---|
| `trn_ok` | `render-trust-selector` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of TrustSelectorComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_trust_selector`. Timed work is the remounted path. Observed `rtrs_*` are exact. First n=5 freeze **5.383×** (1162.348 / 215.910 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1126 — `cli_selectors` (lms_ok)

| metric | cadr | pi |
|---|---|---|
| `lms_ok` | `make-login-method-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of ExtensionSelectorComponent constructor (login method selector) |

Leftover sibling unused-slug remount. Does not remount `make_login_method_selector_state`. Timed work is the remounted path. Observed `mlms_*` are exact. First n=5 freeze **1.460×** (3.885 / 2.662 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1127 — `cli_selectors` (aki_ok)

| metric | cadr | pi |
|---|---|---|
| `aki_ok` | `make-api-key-input-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of login-dialog showPrompt api key Input constructor |

Leftover sibling unused-slug remount. Does not remount `make_api_key_input_state`. Timed work is the remounted path. Observed `makis_*` are exact. First n=5 freeze **6.256×** (2.957 / 0.473 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1128 — `cli_selectors` (oss_ok)

| metric | cadr | pi |
|---|---|---|
| `oss_ok` | `make-oauth-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of OauthSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_oauth_selector_state`. Timed work is the remounted path. Observed `moss_*` are exact. First n=5 freeze **1.579×** (8.838 / 5.596 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1129 — `cli_selectors` (tsm_ok)

| metric | cadr | pi |
|---|---|---|
| `tsm_ok` | `trust-selector-move` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of wrap selection index |

Leftover sibling unused-slug remount. Does not remount `trust_selector_move`. Timed work is the remounted path. Observed `tsm_*` are exact. First n=5 freeze **2.507×** (337.926 / 134.774 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1130 — `cli_selectors` (tse_ok)

| metric | cadr | pi |
|---|---|---|
| `tse_ok` | `trust-selector-handle-event` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of trust-selector handle-event dispatch |

Leftover sibling unused-slug remount. Does not remount `trust_selector_handle_event`. Timed work is the remounted path. Observed `tshe_*` are exact. First n=5 freeze **2.355×** (370.246 / 157.217 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1131 — `cli_selectors` (tui_ok)

| metric | cadr | pi |
|---|---|---|
| `tui_ok` | `trust-selector-ui-state` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of TrustSelectorComponent UI state |

Leftover sibling unused-slug remount. Does not remount `trust_selector_ui_state`. Timed work is the remounted path. Observed `rts_*` are exact. First n=5 freeze **2.112×** (405.519 / 192.023 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1132 — `cli_selectors` (sl_ok)

| metric | cadr | pi |
|---|---|---|
| `sl_ok` | `thinking-selector-selected-level` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector selected SelectList item |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_selected_level`. Timed work is the remounted path. Observed `tssl_*` are exact. First n=5 freeze **4.398×** (0.982 / 0.223 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1133 — `cli_selectors` (dsc_ok)

| metric | cadr | pi |
|---|---|---|
| `dsc_ok` | `thinking-level-description-line` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of LEVEL_DESCRIPTIONS default suffix |

Leftover sibling unused-slug remount. Does not remount `thinking_level_description_line`. Timed work is the remounted path. Observed `tsdl_*` are exact. First n=5 freeze **3.757×** (0.505 / 0.135 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1134 — `cli_selectors` (rth_ok)

| metric | cadr | pi |
|---|---|---|
| `rth_ok` | `render-thinking-selector` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of ThinkingSelectorComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_thinking_selector`. Timed work is the remounted path. Observed `tsrd_*` are exact. First n=5 freeze **41.601×** (294.766 / 7.086 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1135 — `cli_selectors` (lbl_ok)

| metric | cadr | pi |
|---|---|---|
| `lbl_ok` | `oauth-option-status-label` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of formatStatusIndicator plain label |

Leftover sibling unused-slug remount. Does not remount `oauth_option_status_label`. Timed work is the remounted path. Observed `oosl_*` are exact. First n=5 freeze **2.544×** (2.108 / 0.829 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1136 — `cli_selectors` (typ_ok)

| metric | cadr | pi |
|---|---|---|
| `typ_ok` | `credential-entry-auth-type` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of credential-entry authType |

Leftover sibling unused-slug remount. Does not remount `credential_entry_auth_type`. Timed work is the remounted path. Observed `ceat_*` are exact. First n=5 freeze **5.457×** (0.847 / 0.155 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1137 — `cli_selectors` (env_ok)

| metric | cadr | pi |
|---|---|---|
| `env_ok` | `oauth-environment-source-p` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of env source regex |

Leftover sibling unused-slug remount. Does not remount `oauth_environment_source_p`. Timed work is the remounted path. Observed `oesp_*` are exact. First n=5 freeze **5.427×** (1.199 / 0.221 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1138 — `cli_selectors` (oas_ok)

| metric | cadr | pi |
|---|---|---|
| `oas_ok` | `oauth-selector-selection` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of filteredProviders[selectedIndex] |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_selection`. Timed work is the remounted path. Observed `oss_*` are exact. First n=5 freeze **23.182×** (106.295 / 4.585 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1139 — `cli_selectors` (flt_ok)

| metric | cadr | pi |
|---|---|---|
| `flt_ok` | `oauth-selector-apply-filter` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of filterProviders |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_apply_filter`. Timed work is the remounted path. Observed `osaf_*` are exact. First n=5 freeze **7.400×** (85.440 / 11.545 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1140 — `cli_selectors` (qry_ok)

| metric | cadr | pi |
|---|---|---|
| `qry_ok` | `oauth-selector-search-text` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of filterProviders search text |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_search_text`. Timed work is the remounted path. Observed `osst_*` are exact. First n=5 freeze **3.823×** (1.642 / 0.429 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1144 — `cli_selectors` (lmh_ok)

| metric | cadr | pi |
|---|---|---|
| `lmh_ok` | `login-method-selector-handle-event` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of login method selector handleInput |

Leftover sibling unused-slug remount. Does not remount `login_method_selector_handle_event`. Timed work is the remounted path. Observed `lmhe_*` are exact. First n=5 freeze **5.735×** (3.307 / 0.577 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1145 — `cli_selectors` (lui_ok)

| metric | cadr | pi |
|---|---|---|
| `lui_ok` | `login-method-selector-ui-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of ExtensionSelectorComponent UI state |

Leftover sibling unused-slug remount. Does not remount `login_method_selector_ui_state`. Timed work is the remounted path. Observed `lmsui_*` are exact. First n=5 freeze **4.628×** (430.541 / 93.029 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1146 — `cli_selectors` (aku_ok)

| metric | cadr | pi |
|---|---|---|
| `aku_ok` | `api-key-input-ui-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showPrompt api key UI state |

Leftover sibling unused-slug remount. Does not remount `api_key_input_ui_state`. Timed work is the remounted path. Observed `akiui_*` are exact. First n=5 freeze **2.698×** (200.852 / 74.457 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1147 — `cli_selectors` (akhe_ok)

| metric | cadr | pi |
|---|---|---|
| `akhe_ok` | `api-key-input-state-handle-event` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of handleInput api key prompt dispatch |

Leftover sibling unused-slug remount. Does not remount `api_key_input_state_handle_event`. Timed work is the remounted path. Observed `akhe_*` are exact. First n=5 freeze **1.617×** (7.823 / 4.838 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1148 — `cli_selectors` (mls_ok)

| metric | cadr | pi |
|---|---|---|
| `mls_ok` | `make-login-method-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of ExtensionSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_login_method_selector_state`. Timed work is the remounted path. Observed `mlms_*` are exact. First n=5 freeze **1.071×** (3.899 / 3.639 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1149 — `cli_selectors` (ais_ok)

| metric | cadr | pi |
|---|---|---|
| `ais_ok` | `make-api-key-input-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showPrompt api key Input constructor |

Leftover sibling unused-slug remount. Does not remount `make_api_key_input_state`. Timed work is the remounted path. Observed `makis_*` are exact. First n=5 freeze **5.362×** (3.860 / 0.720 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1150 — `cli_selectors` (hen_ok)

| metric | cadr | pi |
|---|---|---|
| `hen_ok` | `thinking-selector-handle-event` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector typed input event dispatch |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_handle_event`. Timed work is the remounted path. Observed `tshe_*` are exact. First n=5 freeze **2.514×** (6.210 / 2.471 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1151 — `cli_selectors` (mts_ok)

| metric | cadr | pi |
|---|---|---|
| `mts_ok` | `make-thinking-selector-state` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector constructor filter + select current |

Leftover sibling unused-slug remount. Does not remount `make_thinking_selector_state`. Timed work is the remounted path. Observed `tms_*` are exact. First n=5 freeze **4.818×** (2.186 / 0.454 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1152 — `cli_selectors` (lst_ok)

| metric | cadr | pi |
|---|---|---|
| `lst_ok` | `thinking-level-search-text` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector label + description search text |

Leftover sibling unused-slug remount. Does not remount `thinking_level_search_text`. Timed work is the remounted path. Observed `tlst_*` are exact. First n=5 freeze **7.115×** (1.614 / 0.227 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1153 — `cli_selectors` (ohe_ok)

| metric | cadr | pi |
|---|---|---|
| `ohe_ok` | `oauth-selector-handle-event` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of oauth-selector handleInput event dispatch |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_handle_event`. Timed work is the remounted path. Observed `oshe_*` are exact. First n=5 freeze **11.608×** (182.806 / 15.748 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1154 — `cli_selectors` (mos_ok)

| metric | cadr | pi |
|---|---|---|
| `mos_ok` | `make-oauth-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of OauthSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_oauth_selector_state`. Timed work is the remounted path. Observed `moss_*` are exact. First n=5 freeze **1.162×** (13.535 / 11.644 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1155 — `cli_selectors` (sst_ok)

| metric | cadr | pi |
|---|---|---|
| `sst_ok` | `oauth-selector-search-text` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of oauth-selector filterProviders search text |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_search_text`. Timed work is the remounted path. Observed `osst_*` are exact. First n=5 freeze **6.411×** (2.557 / 0.399 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1156 — `cli_selectors` (osr_ok)

| metric | cadr | pi |
|---|---|---|
| `osr_ok` | `oauth-option-status-rendered` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of formatStatusIndicator themed output |

Leftover sibling unused-slug remount. Does not remount `oauth_option_status_rendered`. Timed work is the remounted path. Observed `oosr_*` are exact. First n=5 freeze **5.869×** (10.561 / 1.799 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1157 — `cli_selectors` (osl_ok)

| metric | cadr | pi |
|---|---|---|
| `osl_ok` | `oauth-option-status-label` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of formatStatusIndicator plain label |

Leftover sibling unused-slug remount. Does not remount `oauth_option_status_label`. Timed work is the remounted path. Observed `oosl_*` are exact. First n=5 freeze **3.717×** (2.036 / 0.548 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1158 — `cli_selectors` (cet_ok)

| metric | cadr | pi |
|---|---|---|
| `cet_ok` | `credential-entry-auth-type` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of credential-entry authType |

Leftover sibling unused-slug remount. Does not remount `credential_entry_auth_type`. Timed work is the remounted path. Observed `ceat_*` are exact. First n=5 freeze **3.753×** (0.609 / 0.162 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1159 — `cli_selectors` (rwi_ok)

| metric | cadr | pi |
|---|---|---|
| `rwi_ok` | `oauth-selector-handle-raw-input` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of oauth-selector handleInput raw key dispatch |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_handle_raw_input`. Timed work is the remounted path. Observed `oshri_*` are exact. First n=5 freeze **5.721×** (1039.776 / 181.734 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1160 — `cli_selectors` (esp_ok)

| metric | cadr | pi |
|---|---|---|
| `esp_ok` | `oauth-environment-source-p` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of formatStatusIndicator env source regex |

Leftover sibling unused-slug remount. Does not remount `oauth_environment_source_p`. Timed work is the remounted path. Observed `oesp_*` are exact. First n=5 freeze **8.619×** (1.847 / 0.214 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1161 — `cli_selectors` (lgt_ok)

| metric | cadr | pi |
|---|---|---|
| `lgt_ok` | `logout-provider-options` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of getLogoutProviderOptions |

Leftover sibling unused-slug remount. Does not remount `logout_provider_options`. Timed work is the remounted path. Observed `lgo_*` are exact. First n=5 freeze **4.440×** (10.011 / 2.255 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1162 — `cli_selectors` (rte_ok)

| metric | cadr | pi |
|---|---|---|
| `rte_ok` | `login-auth-type-route` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showLoginAuthTypeSelector routing |

Leftover sibling unused-slug remount. Does not remount `login_auth_type_route`. Timed work is the remounted path. Observed `latr_*` are exact. First n=5 freeze **8.829×** (3.667 / 0.415 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1163 — `cli_selectors` (lpr_ok)

| metric | cadr | pi |
|---|---|---|
| `lpr_ok` | `login-provider-options` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of getLoginProviderOptions |

Leftover sibling unused-slug remount. Does not remount `login_provider_options`. Timed work is the remounted path. Observed `lpo_*` are exact. First n=5 freeze **5.540×** (16.974 / 3.064 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1164 — `cli_selectors` (lhe_ok)

| metric | cadr | pi |
|---|---|---|
| `lhe_ok` | `login-method-selector-handle-event` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of login method selector handleInput |

Leftover sibling unused-slug remount. Does not remount `login_method_selector_handle_event`. Timed work is the remounted path. Observed `lmhe_*` are exact. First n=5 freeze **6.260×** (3.803 / 0.607 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1165 — `cli_selectors` (lmsu_ok)

| metric | cadr | pi |
|---|---|---|
| `lmsu_ok` | `login-method-selector-ui-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of ExtensionSelectorComponent UI state |

Leftover sibling unused-slug remount. Does not remount `login_method_selector_ui_state`. Timed work is the remounted path. Observed `lmsui_*` are exact. First n=5 freeze **4.771×** (457.136 / 95.817 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1166 — `cli_selectors` (aui_ok)

| metric | cadr | pi |
|---|---|---|
| `aui_ok` | `api-key-input-ui-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showPrompt api key UI state |

Leftover sibling unused-slug remount. Does not remount `api_key_input_ui_state`. Timed work is the remounted path. Observed `akiui_*` are exact. First n=5 freeze **2.104×** (196.168 / 93.225 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1167 — `cli_selectors` (ahe_ok)

| metric | cadr | pi |
|---|---|---|
| `ahe_ok` | `api-key-input-state-handle-event` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of login dialog api key prompt handleInput |

Leftover sibling unused-slug remount. Does not remount `api_key_input_state_handle_event`. Timed work is the remounted path. Observed `akhe_*` are exact. First n=5 freeze **1.283×** (6.326 / 4.929 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1168 — `cli_selectors` (cds_ok)

| metric | cadr | pi |
|---|---|---|
| `cds_ok` | `countdown-timer-tick` (`src/cadr-cli/interactive/components/countdown.lisp`) | leftover replica of Math.ceil(timeoutMs/1000) |

Leftover sibling unused-slug remount. Does not remount `countdown_seconds`. Timed work is the remounted path. Observed `cds_*` are exact. First n=5 freeze **8.372×** (1.080 / 0.129 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1169 — `cli_selectors` (cdt_ok)

| metric | cadr | pi |
|---|---|---|
| `cdt_ok` | `countdown-timer-tick` (`src/cadr-cli/interactive/components/countdown.lisp`) | leftover replica of countdown tick |

Leftover sibling unused-slug remount. Does not remount `countdown_tick`. Timed work is the remounted path. Observed `cdt_*` are exact. First n=5 freeze **5.213×** (1.021 / 0.196 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1170 — `cli_selectors` (cdr_ok)

| metric | cadr | pi |
|---|---|---|
| `cdr_ok` | `countdown-request-render` (`src/cadr-cli/interactive/components/countdown.lisp`) | leftover replica of countdown requestRender |

Leftover sibling unused-slug remount. Does not remount `countdown_render`. Timed work is the remounted path. Observed `cdr_*` are exact. First n=5 freeze **5.790×** (1.337 / 0.231 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1171 — `powershell_tool` (utf_ok)

| metric | cadr | pi |
|---|---|---|
| `utf_ok` | `+powershell-utf8-output-prefix+` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of UTF8_OUTPUT_PREFIX |

Leftover sibling unused-slug remount. Does not remount `utf8_prefix`. Timed work is the remounted path. Observed `psu_*` are exact. First n=5 freeze **5.636×** (0.705 / 0.125 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1172 — `powershell_tool` (pfx_ok)

| metric | cadr | pi |
|---|---|---|
| `pfx_ok` | `make-powershell-tool` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of prefix+command wrap |

Leftover sibling unused-slug remount. Does not remount `prefix_command`. Timed work is the remounted path. Observed `psc_*` are exact. First n=5 freeze **6.387×** (1.656 / 0.259 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1173 — `powershell_tool` (mtb_ok)

| metric | cadr | pi |
|---|---|---|
| `mtb_ok` | `make-powershell-tool` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of createPowerShellToolDefinition |

Leftover sibling unused-slug remount. Does not remount `make_tool`. Timed work is the remounted path. Observed `pmt_*` are exact. First n=5 freeze **1.627×** (3.052 / 1.876 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1174 — `cli_selectors` (dra_ok)

| metric | cadr | pi |
|---|---|---|
| `dra_ok` | `daxnuts-rgb-at` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of parseImage pixel lookup |

Leftover sibling unused-slug remount. Does not remount `daxnuts_rgb_at`. Timed work is the remounted path. Observed `dra_*` are exact. First n=5 freeze **6.138×** (1.484 / 0.242 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1175 — `cli_selectors` (dmc_ok)

| metric | cadr | pi |
|---|---|---|
| `dmc_ok` | `make-daxnuts-component` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of DaxnutsComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_daxnuts_component`. Timed work is the remounted path. Observed `dmc_*` are exact. First n=5 freeze **9.850×** (1.227 / 0.125 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1176 — `cli_selectors` (dct_ok)

| metric | cadr | pi |
|---|---|---|
| `dct_ok` | `daxnuts-component-tick` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of DaxnutsComponent interval |

Leftover sibling unused-slug remount. Does not remount `daxnuts_component_tick`. Timed work is the remounted path. Observed `dct_*` are exact. First n=5 freeze **20.277×** (4.958 / 0.244 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1177 — `cli_bootstrap_sessions` (pbk_ok)

| metric | cadr | pi |
|---|---|---|
| `pbk_ok` | `parse-user-bash-input` (`src/cadr-cli/repl.lisp`) | leftover replica of ! / !! bash extract |

Leftover sibling unused-slug remount. Does not remount `parse_bash`. Timed work is the remounted path. Observed `pb_*` are exact. First n=5 freeze **0.967×** (1.119 / 1.157 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1× (cadr leads); not listed in over-1× table. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1178 — `cli_bootstrap_sessions` (rtk_ok)

| metric | cadr | pi |
|---|---|---|
| `rtk_ok` | `response-text` (`src/cadr-cli/repl.lisp`) | leftover replica of textParts.join |

Leftover sibling unused-slug remount. Does not remount `response_text`. Timed work is the remounted path. Observed `rt_*` are exact. First n=5 freeze **2.458×** (1.777 / 0.723 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1179 — `cli_bootstrap_sessions` (dpk_ok)

| metric | cadr | pi |
|---|---|---|
| `dpk_ok` | `dispatch-user-input` (`src/cadr-cli/repl.lisp`) | leftover replica of submit classify |

Leftover sibling unused-slug remount. Does not remount `dispatch_plain`. Timed work is the remounted path. Observed `dp_*` are exact. First n=5 freeze **1.185×** (0.898 / 0.758 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1180 — `cli_selectors` (tll_ok)

| metric | cadr | pi |
|---|---|---|
| `tll_ok` | `thinking-level-label` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking level label |

Leftover sibling unused-slug remount. Does not remount `thinking_level_label`. Timed work is the remounted path. Observed `tll_*` are exact. First n=5 freeze **4.123×** (0.523 / 0.127 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1181 — `cli_selectors` (tsq_ok)

| metric | cadr | pi |
|---|---|---|
| `tsq_ok` | `thinking-selector-set-query` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of applyFilter from search |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_set_query`. Timed work is the remounted path. Observed `tsq_*` are exact. First n=5 freeze **1.813×** (14.395 / 7.939 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1182 — `cli_selectors` (tskb_ok)

| metric | cadr | pi |
|---|---|---|
| `tskb_ok` | `thinking-selector-keybindings` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of getKeybindings |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_keybindings`. Timed work is the remounted path. Observed `tskb_*` are exact. First n=5 freeze **9.466×** (3.062 / 0.323 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1183 — `cli_selectors` (ldw_ok)

| metric | cadr | pi |
|---|---|---|
| `ldw_ok` | `login-dialog-show-waiting` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showWaiting |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_waiting`. Timed work is the remounted path. Observed `ldw_*` are exact. First n=5 freeze **4.104×** (8.371 / 2.040 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1184 — `cli_selectors` (ldp_ok)

| metric | cadr | pi |
|---|---|---|
| `ldp_ok` | `login-dialog-show-progress` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showProgress |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_progress`. Timed work is the remounted path. Observed `ldp_*` are exact. First n=5 freeze **2.991×** (4.138 / 1.384 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1185 — `cli_selectors` (ldmi_ok)

| metric | cadr | pi |
|---|---|---|
| `ldmi_ok` | `login-dialog-show-manual-input` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showManualInput |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_manual_input`. Timed work is the remounted path. Observed `ldmi_*` are exact. First n=5 freeze **4.531×** (7.537 / 1.664 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1186 — `cli_selectors` (ldpr_ok)

| metric | cadr | pi |
|---|---|---|
| `ldpr_ok` | `login-dialog-show-prompt` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showPrompt |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_prompt`. Timed work is the remounted path. Observed `ldpr_*` are exact. First n=5 freeze **4.634×** (10.961 / 2.365 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1187 — `cli_selectors` (ldi_ok)

| metric | cadr | pi |
|---|---|---|
| `ldi_ok` | `login-dialog-show-info` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showInfo |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_info`. Timed work is the remounted path. Observed `ldi_*` are exact. First n=5 freeze **3.446×** (11.704 / 3.396 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1188 — `cli_selectors` (lddt_ok)

| metric | cadr | pi |
|---|---|---|
| `lddt_ok` | `login-dialog-show-details` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showDetails |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_details`. Timed work is the remounted path. Observed `lddt_*` are exact. First n=5 freeze **1.544×** (4.310 / 2.792 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1189 — `cli_selectors` (ldci_ok)

| metric | cadr | pi |
|---|---|---|
| `ldci_ok` | `login-dialog-complete-input` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.replaceInputWithSubmittedText |

Leftover sibling unused-slug remount. Does not remount `login_dialog_complete_input`. Timed work is the remounted path. Observed `ldci_*` are exact. First n=5 freeze **5.361×** (7.260 / 1.354 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1190 — `cli_selectors` (ldhe_ok)

| metric | cadr | pi |
|---|---|---|
| `ldhe_ok` | `login-dialog-state-handle-event` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.handleInput |

Leftover sibling unused-slug remount. Does not remount `login_dialog_handle_event`. Timed work is the remounted path. Observed `ldhe_*` are exact. First n=5 freeze **5.848×** (7.976 / 1.364 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1191 — `cli_selectors` (ldrd_ok)

| metric | cadr | pi |
|---|---|---|
| `ldrd_ok` | `render-login-dialog-state` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_login_dialog`. Timed work is the remounted path. Observed `ldrd_*` are exact. First n=5 freeze **95.438×** (129.532 / 1.357 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1192 — `cli_selectors` (umev_ok)

| metric | cadr | pi |
|---|---|---|
| `umev_ok` | `user-message-selector-handle-event` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageList.handleInput (structured) |

Leftover sibling unused-slug remount. Does not remount `user_message_handle_event`. Timed work is the remounted path. Observed `umhe_*` are exact. First n=5 freeze **3.469×** (2.048 / 0.590 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1193 — `cli_selectors` (umrw_ok)

| metric | cadr | pi |
|---|---|---|
| `umrw_ok` | `user-message-selector-handle-raw-input` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageList.handleInput (raw) |

Leftover sibling unused-slug remount. Does not remount `user_message_handle_raw`. Timed work is the remounted path. Observed `umhr_*` are exact. First n=5 freeze **31.664×** (103.853 / 3.280 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1194 — `cli_selectors` (umrs_ok)

| metric | cadr | pi |
|---|---|---|
| `umrs_ok` | `render-user-message-selector` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageSelectorComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_user_message_selector`. Timed work is the remounted path. Observed `umrd_*` are exact. First n=5 freeze **263.196×** (290.148 / 1.102 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1195 — `cli_selectors` (mkb_ok)

| metric | cadr | pi |
|---|---|---|
| `mkb_ok` | `make-models-selector-keybindings` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of KeybindingsManager app.models.* |

Leftover sibling unused-slug remount. Does not remount `make_models_selector_keybindings`. Timed work is the remounted path. Observed `mmskb_*` are exact. First n=5 freeze **0.528×** (39.724 / 75.219 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1× (cadr leads); not listed in over-1× table. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1196 — `cli_selectors` (msms_ok)

| metric | cadr | pi |
|---|---|---|
| `msms_ok` | `make-scoped-models-selector-state` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of ScopedModelsSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_scoped_models_selector_state`. Timed work is the remounted path. Observed `msmksc_*` are exact. First n=5 freeze **39.017×** (134.701 / 3.452 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1197 — `cli_selectors` (mrms_ok)

| metric | cadr | pi |
|---|---|---|
| `mrms_ok` | `render-model-selector` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of ModelSelectorComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_model_selector`. Timed work is the remounted path. Observed `rms_*` are exact. First n=5 freeze **28.308×** (243.569 / 8.604 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1198 — `cli_selectors` (thaf_ok)

| metric | cadr | pi |
|---|---|---|
| `thaf_ok` | `thinking-selector-apply-filter` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector applyFilter |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_apply_filter`. Timed work is the remounted path. Observed `tsaf_*` are exact. First n=5 freeze **1.414×** (13.343 / 9.437 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1199 — `cli_selectors` (thcl_ok)

| metric | cadr | pi |
|---|---|---|
| `thcl_ok` | `thinking-selector-clamp-selected` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector clamp selected |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_clamp_selected`. Timed work is the remounted path. Observed `tscl_*` are exact. First n=5 freeze **5.437×** (0.987 / 0.182 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1200 — `cli_selectors` (thsc_ok)

| metric | cadr | pi |
|---|---|---|
| `thsc_ok` | `thinking-selector-select-current` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector select current |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_select_current`. Timed work is the remounted path. Observed `tssc_*` are exact. First n=5 freeze **3.634×** (1.341 / 0.369 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1201 — `cli_selectors` (thmv_ok)

| metric | cadr | pi |
|---|---|---|
| `thmv_ok` | `thinking-selector-move` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector wrap selected |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_move`. Timed work is the remounted path. Observed `tsmv_*` are exact. First n=5 freeze **8.055×** (0.992 / 0.123 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1202 — `cli_selectors` (thhr_ok)

| metric | cadr | pi |
|---|---|---|
| `thhr_ok` | `thinking-selector-handle-raw-input` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector handleInput keybindings |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_handle_raw_input`. Timed work is the remounted path. Observed `tshri_*` are exact. First n=5 freeze **34.311×** (166.081 / 4.840 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1203 — `cli_selectors` (thhe_ok)

| metric | cadr | pi |
|---|---|---|
| `thhe_ok` | `thinking-selector-handle-event` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector typed input event dispatch |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_handle_event`. Timed work is the remounted path. Observed `tshe_*` are exact. First n=5 freeze **1.793×** (4.275 / 2.383 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1204 — `cli_selectors` (trsv_ok)

| metric | cadr | pi |
|---|---|---|
| `trsv_ok` | `trust-option-saved-p` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of trust-selector isSavedOption |

Leftover sibling unused-slug remount. Does not remount `trust_option_saved_p`. Timed work is the remounted path. Observed `tosp_*` are exact. First n=5 freeze **2.164×** (52.581 / 24.296 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1205 — `cli_selectors` (trmk_ok)

| metric | cadr | pi |
|---|---|---|
| `trmk_ok` | `make-trust-selector-state` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of TrustSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_trust_selector_state`. Timed work is the remounted path. Observed `mtss_*` are exact. First n=5 freeze **1.652×** (136.316 / 82.531 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1206 — `cli_selectors` (trrs_ok)

| metric | cadr | pi |
|---|---|---|
| `trrs_ok` | `render-trust-selector` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of TrustSelectorComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_trust_selector`. Timed work is the remounted path. Observed `rtrs_*` are exact. First n=5 freeze **6.285×** (1114.238 / 177.291 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1207 — `cli_selectors` (lmsx_ok)

| metric | cadr | pi |
|---|---|---|
| `lmsx_ok` | `make-login-method-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of ExtensionSelector login-method constructor |

Leftover sibling unused-slug remount. Does not remount `make_login_method_selector_state`. Timed work is the remounted path. Observed `mlms_*` are exact. First n=5 freeze **3.066×** (4.009 / 1.308 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1208 — `cli_selectors` (akix_ok)

| metric | cadr | pi |
|---|---|---|
| `akix_ok` | `make-api-key-input-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showPrompt api key Input constructor |

Leftover sibling unused-slug remount. Does not remount `make_api_key_input_state`. Timed work is the remounted path. Observed `makis_*` are exact. First n=5 freeze **10.725×** (3.520 / 0.328 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1209 — `cli_selectors` (ossx_ok)

| metric | cadr | pi |
|---|---|---|
| `ossx_ok` | `make-oauth-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of OauthSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_oauth_selector_state`. Timed work is the remounted path. Observed `moss_*` are exact. First n=5 freeze **2.007×** (8.436 / 4.203 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1210 — `cli_selectors` (tsmx_ok)

| metric | cadr | pi |
|---|---|---|
| `tsmx_ok` | `trust-selector-move` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of wrap selection index |

Leftover sibling unused-slug remount. Does not remount `trust_selector_move`. Timed work is the remounted path. Observed `tsm_*` are exact. First n=5 freeze **2.744×** (286.270 / 104.310 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1211 — `cli_selectors` (tsex_ok)

| metric | cadr | pi |
|---|---|---|
| `tsex_ok` | `trust-selector-handle-event` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of trust-selector handle-event dispatch |

Leftover sibling unused-slug remount. Does not remount `trust_selector_handle_event`. Timed work is the remounted path. Observed `tshe_*` are exact. First n=5 freeze **2.501×** (285.730 / 114.245 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1212 — `cli_selectors` (tuix_ok)

| metric | cadr | pi |
|---|---|---|
| `tuix_ok` | `trust-selector-ui-state` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of TrustSelectorComponent UI state |

Leftover sibling unused-slug remount. Does not remount `trust_selector_ui_state`. Timed work is the remounted path. Observed `rts_*` are exact. First n=5 freeze **2.619×** (336.435 / 128.478 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1213 — `cli_selectors` (slx_ok)

| metric | cadr | pi |
|---|---|---|
| `slx_ok` | `thinking-selector-selected-level` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector selected SelectList item |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_selected_level`. Timed work is the remounted path. Observed `tssl_*` are exact. First n=5 freeze **4.190×** (0.851 / 0.203 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1214 — `cli_selectors` (dscx_ok)

| metric | cadr | pi |
|---|---|---|
| `dscx_ok` | `thinking-level-description-line` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of LEVEL_DESCRIPTIONS default suffix |

Leftover sibling unused-slug remount. Does not remount `thinking_level_description_line`. Timed work is the remounted path. Observed `tsdl_*` are exact. First n=5 freeze **4.188×** (0.499 / 0.119 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1215 — `cli_selectors` (rthx_ok)

| metric | cadr | pi |
|---|---|---|
| `rthx_ok` | `render-thinking-selector` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of ThinkingSelectorComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_thinking_selector`. Timed work is the remounted path. Observed `tsrd_*` are exact. First n=5 freeze **59.875×** (258.321 / 4.314 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1216 — `cli_selectors` (lblx_ok)

| metric | cadr | pi |
|---|---|---|
| `lblx_ok` | `oauth-option-status-label` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of formatStatusIndicator plain label |

Leftover sibling unused-slug remount. Does not remount `oauth_option_status_label`. Timed work is the remounted path. Observed `oosl_*` are exact. First n=5 freeze **3.777×** (1.841 / 0.487 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1217 — `cli_selectors` (typx_ok)

| metric | cadr | pi |
|---|---|---|
| `typx_ok` | `credential-entry-auth-type` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of credential-entry authType |

Leftover sibling unused-slug remount. Does not remount `credential_entry_auth_type`. Timed work is the remounted path. Observed `ceat_*` are exact. First n=5 freeze **3.992×** (0.571 / 0.143 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1218 — `cli_selectors` (envx_ok)

| metric | cadr | pi |
|---|---|---|
| `envx_ok` | `oauth-environment-source-p` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of env source regex |

Leftover sibling unused-slug remount. Does not remount `oauth_environment_source_p`. Timed work is the remounted path. Observed `oesp_*` are exact. First n=5 freeze **5.375×** (1.084 / 0.202 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1219 — `cli_selectors` (oasx_ok)

| metric | cadr | pi |
|---|---|---|
| `oasx_ok` | `oauth-selector-selection` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of filteredProviders[selectedIndex] |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_selection`. Timed work is the remounted path. Observed `oss_*` are exact. First n=5 freeze **19.944×** (76.164 / 3.819 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1220 — `cli_selectors` (fltx_ok)

| metric | cadr | pi |
|---|---|---|
| `fltx_ok` | `oauth-selector-apply-filter` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of filterProviders |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_apply_filter`. Timed work is the remounted path. Observed `osaf_*` are exact. First n=5 freeze **8.925×** (78.904 / 8.841 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1221 — `cli_selectors` (qryx_ok)

| metric | cadr | pi |
|---|---|---|
| `qryx_ok` | `oauth-selector-search-text` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of filterProviders search text |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_search_text`. Timed work is the remounted path. Observed `osst_*` are exact. First n=5 freeze **5.681×** (1.447 / 0.255 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1222 — `cli_selectors` (latx_ok)

| metric | cadr | pi |
|---|---|---|
| `latx_ok` | `login-auth-type-route` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showLoginAuthTypeSelector routing |

Leftover sibling unused-slug remount. Does not remount `login_auth_type_route`. Timed work is the remounted path. Observed `latr_*` are exact. First n=5 freeze **8.535×** (3.123 / 0.366 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1223 — `cli_selectors` (lpox_ok)

| metric | cadr | pi |
|---|---|---|
| `lpox_ok` | `login-provider-options` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of getLoginProviderOptions |

Leftover sibling unused-slug remount. Does not remount `login_provider_options`. Timed work is the remounted path. Observed `lpo_*` are exact. First n=5 freeze **3.737×** (9.745 / 2.608 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1224 — `cli_selectors` (lgox_ok)

| metric | cadr | pi |
|---|---|---|
| `lgox_ok` | `logout-provider-options` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of getLogoutProviderOptions |

Leftover sibling unused-slug remount. Does not remount `logout_provider_options`. Timed work is the remounted path. Observed `lgo_*` are exact. First n=5 freeze **4.279×** (8.527 / 1.993 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1225 — `cli_selectors` (lmhx_ok)

| metric | cadr | pi |
|---|---|---|
| `lmhx_ok` | `login-method-selector-handle-event` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of login method selector handleInput |

Leftover sibling unused-slug remount. Does not remount `login_method_selector_handle_event`. Timed work is the remounted path. Observed `lmhe_*` are exact. First n=5 freeze **5.528×** (3.231 / 0.585 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1226 — `cli_selectors` (luix_ok)

| metric | cadr | pi |
|---|---|---|
| `luix_ok` | `login-method-selector-ui-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of ExtensionSelectorComponent UI state |

Leftover sibling unused-slug remount. Does not remount `login_method_selector_ui_state`. Timed work is the remounted path. Observed `lmsui_*` are exact. First n=5 freeze **4.673×** (388.529 / 83.137 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1227 — `cli_selectors` (akux_ok)

| metric | cadr | pi |
|---|---|---|
| `akux_ok` | `api-key-input-ui-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showPrompt api key UI state |

Leftover sibling unused-slug remount. Does not remount `api_key_input_ui_state`. Timed work is the remounted path. Observed `akiui_*` are exact. First n=5 freeze **2.384×** (191.040 / 80.139 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1228 — `cli_selectors` (akhex_ok)

| metric | cadr | pi |
|---|---|---|
| `akhex_ok` | `api-key-input-state-handle-event` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of handleInput api key prompt dispatch |

Leftover sibling unused-slug remount. Does not remount `api_key_input_state_handle_event`. Timed work is the remounted path. Observed `akhe_*` are exact. First n=5 freeze **2.075×** (6.046 / 2.914 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1229 — `cli_selectors` (mlsx_ok)

| metric | cadr | pi |
|---|---|---|
| `mlsx_ok` | `make-login-method-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of ExtensionSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_login_method_selector_state`. Timed work is the remounted path. Observed `mlms_*` are exact. First n=5 freeze **3.626×** (3.176 / 0.876 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1230 — `cli_selectors` (aisx_ok)

| metric | cadr | pi |
|---|---|---|
| `aisx_ok` | `make-api-key-input-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showPrompt api key Input constructor |

Leftover sibling unused-slug remount. Does not remount `make_api_key_input_state`. Timed work is the remounted path. Observed `makis_*` are exact. First n=5 freeze **7.834×** (2.480 / 0.317 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1231 — `cli_selectors` (henx_ok)

| metric | cadr | pi |
|---|---|---|
| `henx_ok` | `thinking-selector-handle-event` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector typed input event dispatch |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_handle_event`. Timed work is the remounted path. Observed `tshe_*` are exact. First n=5 freeze **1.721×** (3.946 / 2.292 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1232 — `cli_selectors` (mtsx_ok)

| metric | cadr | pi |
|---|---|---|
| `mtsx_ok` | `make-thinking-selector-state` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector constructor filter + select current |

Leftover sibling unused-slug remount. Does not remount `make_thinking_selector_state`. Timed work is the remounted path. Observed `tms_*` are exact. First n=5 freeze **5.261×** (2.082 / 0.396 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1233 — `cli_selectors` (lstx_ok)

| metric | cadr | pi |
|---|---|---|
| `lstx_ok` | `thinking-level-search-text` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector label + description search text |

Leftover sibling unused-slug remount. Does not remount `thinking_level_search_text`. Timed work is the remounted path. Observed `tlst_*` are exact. First n=5 freeze **6.236×** (1.257 / 0.202 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1234 — `cli_selectors` (cdsx_ok)

| metric | cadr | pi |
|---|---|---|
| `cdsx_ok` | `Math.ceil(timeoutMs/1000)` (`src/cadr-cli/interactive/components/countdown.lisp`) | leftover replica of Math.ceil(timeoutMs/1000) |

Leftover sibling unused-slug remount. Does not remount `countdown_seconds`. Timed work is the remounted path. Observed `cds_*` are exact. First n=5 freeze **9.650×** (1.110 / 0.115 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1235 — `cli_selectors` (cdtx_ok)

| metric | cadr | pi |
|---|---|---|
| `cdtx_ok` | `countdown-timer-tick` (`src/cadr-cli/interactive/components/countdown.lisp`) | leftover replica of countdown tick |

Leftover sibling unused-slug remount. Does not remount `countdown_tick`. Timed work is the remounted path. Observed `cdt_*` are exact. First n=5 freeze **7.172×** (1.045 / 0.146 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1236 — `cli_selectors` (cdrx_ok)

| metric | cadr | pi |
|---|---|---|
| `cdrx_ok` | `countdown-request-render` (`src/cadr-cli/interactive/components/countdown.lisp`) | leftover replica of countdown requestRender |

Leftover sibling unused-slug remount. Does not remount `countdown_render`. Timed work is the remounted path. Observed `cdr_*` are exact. First n=5 freeze **5.010×** (1.357 / 0.271 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1237 — `powershell_tool` (utfx_ok)

| metric | cadr | pi |
|---|---|---|
| `utfx_ok` | `+powershell-utf8-output-prefix+` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of UTF8_OUTPUT_PREFIX |

Leftover sibling unused-slug remount. Does not remount `utf8_prefix`. Timed work is the remounted path. Observed `psu_*` are exact. First n=5 freeze **5.782×** (0.630 / 0.109 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1238 — `powershell_tool` (pfxx_ok)

| metric | cadr | pi |
|---|---|---|
| `pfxx_ok` | `make-powershell-tool` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of prefix+command wrap |

Leftover sibling unused-slug remount. Does not remount `prefix_command`. Timed work is the remounted path. Observed `psc_*` are exact. First n=5 freeze **3.593×** (0.733 / 0.204 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1239 — `powershell_tool` (mtbx_ok)

| metric | cadr | pi |
|---|---|---|
| `mtbx_ok` | `make-powershell-tool` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of createPowerShellToolDefinition |

Leftover sibling unused-slug remount. Does not remount `make_tool`. Timed work is the remounted path. Observed `pmt_*` are exact. First n=5 freeze **1.793×** (2.382 / 1.329 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1240 — `cli_selectors` (drax_ok)

| metric | cadr | pi |
|---|---|---|
| `drax_ok` | `daxnuts-rgb-at` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of parseImage pixel lookup |

Leftover sibling unused-slug remount. Does not remount `daxnuts_rgb_at`. Timed work is the remounted path. Observed `dra_*` are exact. First n=5 freeze **6.244×** (1.229 / 0.197 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1241 — `cli_selectors` (dmcx_ok)

| metric | cadr | pi |
|---|---|---|
| `dmcx_ok` | `make-daxnuts-component` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of DaxnutsComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_daxnuts_component`. Timed work is the remounted path. Observed `dmc_*` are exact. First n=5 freeze **11.028×** (1.232 / 0.112 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1242 — `cli_selectors` (dctx_ok)

| metric | cadr | pi |
|---|---|---|
| `dctx_ok` | `daxnuts-component-tick` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of DaxnutsComponent interval |

Leftover sibling unused-slug remount. Does not remount `daxnuts_component_tick`. Timed work is the remounted path. Observed `dct_*` are exact. First n=5 freeze **20.209×** (4.363 / 0.216 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1243 — `cli_bootstrap_sessions` (pbkx_ok)

| metric | cadr | pi |
|---|---|---|
| `pbkx_ok` | `parse-user-bash-input` (`src/cadr-cli/repl.lisp`) | leftover replica of ! / !! bash extract |

Leftover sibling unused-slug remount. Does not remount `parse_bash`. Timed work is the remounted path. Observed `pb_*` are exact. First n=5 freeze **1.282×** (0.711 / 0.555 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1244 — `cli_bootstrap_sessions` (rtkx_ok)

| metric | cadr | pi |
|---|---|---|
| `rtkx_ok` | `response-text` (`src/cadr-cli/repl.lisp`) | leftover replica of textParts.join |

Leftover sibling unused-slug remount. Does not remount `response_text`. Timed work is the remounted path. Observed `rt_*` are exact. First n=5 freeze **2.458×** (1.283 / 0.522 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1245 — `cli_bootstrap_sessions` (dpkx_ok)

| metric | cadr | pi |
|---|---|---|
| `dpkx_ok` | `dispatch-user-input` (`src/cadr-cli/repl.lisp`) | leftover replica of submit classify |

Leftover sibling unused-slug remount. Does not remount `dispatch_plain`. Timed work is the remounted path. Observed `dp_*` are exact. First n=5 freeze **1.098×** (0.683 / 0.622 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1246 — `cli_selectors` (tllx_ok)

| metric | cadr | pi |
|---|---|---|
| `tllx_ok` | `thinking-level-label` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking level label |

Leftover sibling unused-slug remount. Does not remount `thinking_level_label`. Timed work is the remounted path. Observed `tll_*` are exact. First n=5 freeze **3.512×** (0.455 / 0.129 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1247 — `cli_selectors` (tsqx_ok)

| metric | cadr | pi |
|---|---|---|
| `tsqx_ok` | `thinking-selector-set-query` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of applyFilter from search |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_set_query`. Timed work is the remounted path. Observed `tsq_*` are exact. First n=5 freeze **1.587×** (11.623 / 7.323 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1248 — `cli_selectors` (tskbx_ok)

| metric | cadr | pi |
|---|---|---|
| `tskbx_ok` | `thinking-selector-keybindings` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of getKeybindings |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_keybindings`. Timed work is the remounted path. Observed `tskb_*` are exact. First n=5 freeze **16.298×** (2.861 / 0.176 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1249 — `cli_selectors` (ldwx_ok)

| metric | cadr | pi |
|---|---|---|
| `ldwx_ok` | `login-dialog-show-waiting` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showWaiting |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_waiting`. Timed work is the remounted path. Observed `ldw_*` are exact. First n=5 freeze **1.526×** (6.326 / 4.145 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1250 — `cli_selectors` (ldpx_ok)

| metric | cadr | pi |
|---|---|---|
| `ldpx_ok` | `login-dialog-show-progress` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showProgress |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_progress`. Timed work is the remounted path. Observed `ldp_*` are exact. First n=5 freeze **3.981×** (3.738 / 0.939 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1251 — `cli_selectors` (ldmix_ok)

| metric | cadr | pi |
|---|---|---|
| `ldmix_ok` | `login-dialog-show-manual-input` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showManualInput |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_manual_input`. Timed work is the remounted path. Observed `ldmi_*` are exact. First n=5 freeze **5.275×** (5.863 / 1.112 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1252 — `cli_selectors` (ldprx_ok)

| metric | cadr | pi |
|---|---|---|
| `ldprx_ok` | `login-dialog-show-prompt` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showPrompt |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_prompt`. Timed work is the remounted path. Observed `ldpr_*` are exact. First n=5 freeze **5.043×** (8.460 / 1.678 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1253 — `cli_selectors` (ldix_ok)

| metric | cadr | pi |
|---|---|---|
| `ldix_ok` | `login-dialog-show-info` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showInfo |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_info`. Timed work is the remounted path. Observed `ldi_*` are exact. First n=5 freeze **5.533×** (11.876 / 2.146 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1254 — `cli_selectors` (lddtx_ok)

| metric | cadr | pi |
|---|---|---|
| `lddtx_ok` | `login-dialog-show-details` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showDetails |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_details`. Timed work is the remounted path. Observed `lddt_*` are exact. First n=5 freeze **1.897×** (3.003 / 1.583 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1255 — `cli_selectors` (ldcix_ok)

| metric | cadr | pi |
|---|---|---|
| `ldcix_ok` | `login-dialog-complete-input` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.replaceInputWithSubmittedText |

Leftover sibling unused-slug remount. Does not remount `login_dialog_complete_input`. Timed work is the remounted path. Observed `ldci_*` are exact. First n=5 freeze **5.781×** (7.691 / 1.330 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1256 — `cli_selectors` (ldhex_ok)

| metric | cadr | pi |
|---|---|---|
| `ldhex_ok` | `login-dialog-state-handle-event` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.handleInput |

Leftover sibling unused-slug remount. Does not remount `login_dialog_handle_event`. Timed work is the remounted path. Observed `ldhe_*` are exact. First n=5 freeze **6.829×** (9.049 / 1.325 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1257 — `cli_selectors` (ldrdx_ok)

| metric | cadr | pi |
|---|---|---|
| `ldrdx_ok` | `render-login-dialog-state` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_login_dialog`. Timed work is the remounted path. Observed `ldrd_*` are exact. First n=5 freeze **77.143×** (111.106 / 1.440 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1258 — `cli_selectors` (umevx_ok)

| metric | cadr | pi |
|---|---|---|
| `umevx_ok` | `user-message-selector-handle-event` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageList.handleInput (structured) |

Leftover sibling unused-slug remount. Does not remount `user_message_handle_event`. Timed work is the remounted path. Observed `umhe_*` are exact. First n=5 freeze **2.950×** (1.791 / 0.607 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1259 — `cli_selectors` (umrwx_ok)

| metric | cadr | pi |
|---|---|---|
| `umrwx_ok` | `user-message-selector-handle-raw-input` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageList.handleInput (raw) |

Leftover sibling unused-slug remount. Does not remount `user_message_handle_raw`. Timed work is the remounted path. Observed `umhr_*` are exact. First n=5 freeze **32.591×** (108.530 / 3.330 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1260 — `cli_selectors` (umrsx_ok)

| metric | cadr | pi |
|---|---|---|
| `umrsx_ok` | `render-user-message-selector` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageSelectorComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_user_message_selector`. Timed work is the remounted path. Observed `umrd_*` are exact. First n=5 freeze **215.567×** (263.484 / 1.222 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1261 — `cli_selectors` (mkbx_ok)

| metric | cadr | pi |
|---|---|---|
| `mkbx_ok` | `make-models-selector-keybindings` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of KeybindingsManager app.models.* |

Leftover sibling unused-slug remount. Does not remount `make_models_selector_keybindings`. Timed work is the remounted path. Observed `mmskb_*` are exact. First n=5 freeze **0.402×** (33.431 / 83.237 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1× (cadr leads); not listed in over-1× table. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1262 — `cli_selectors` (msmsx_ok)

| metric | cadr | pi |
|---|---|---|
| `msmsx_ok` | `make-scoped-models-selector-state` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of ScopedModelsSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_scoped_models_selector_state`. Timed work is the remounted path. Observed `msmksc_*` are exact. First n=5 freeze **26.957×** (109.615 / 4.066 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1263 — `cli_selectors` (mrmsx_ok)

| metric | cadr | pi |
|---|---|---|
| `mrmsx_ok` | `render-model-selector` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of ModelSelectorComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_model_selector`. Timed work is the remounted path. Observed `rms_*` are exact. First n=5 freeze **27.875×** (188.436 / 6.760 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1264 — `cli_selectors` (thafx_ok)

| metric | cadr | pi |
|---|---|---|
| `thafx_ok` | `thinking-selector-apply-filter` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector applyFilter |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_apply_filter`. Timed work is the remounted path. Observed `tsaf_*` are exact. First n=5 freeze **1.474×** (14.773 / 10.024 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1265 — `cli_selectors` (thclx_ok)

| metric | cadr | pi |
|---|---|---|
| `thclx_ok` | `thinking-selector-clamp-selected` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector clamp selected |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_clamp_selected`. Timed work is the remounted path. Observed `tscl_*` are exact. First n=5 freeze **5.108×** (0.986 / 0.193 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1266 — `cli_selectors` (thscx_ok)

| metric | cadr | pi |
|---|---|---|
| `thscx_ok` | `thinking-selector-select-current` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector select current |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_select_current`. Timed work is the remounted path. Observed `tssc_*` are exact. First n=5 freeze **3.435×** (1.321 / 0.385 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1267 — `cli_selectors` (thmvx_ok)

| metric | cadr | pi |
|---|---|---|
| `thmvx_ok` | `thinking-selector-move` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector wrap selected |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_move`. Timed work is the remounted path. Observed `tsmv_*` are exact. First n=5 freeze **7.009×** (0.947 / 0.135 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1268 — `cli_selectors` (thhrx_ok)

| metric | cadr | pi |
|---|---|---|
| `thhrx_ok` | `thinking-selector-handle-raw-input` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector handleInput keybindings |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_handle_raw_input`. Timed work is the remounted path. Observed `tshri_*` are exact. First n=5 freeze **30.826×** (166.608 / 5.405 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1269 — `cli_selectors` (thhex_ok)

| metric | cadr | pi |
|---|---|---|
| `thhex_ok` | `thinking-selector-handle-event` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector typed input event dispatch |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_handle_event`. Timed work is the remounted path. Observed `tshe_*` are exact. First n=5 freeze **1.596×** (4.024 / 2.522 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1270 — `cli_selectors` (trsvx_ok)

| metric | cadr | pi |
|---|---|---|
| `trsvx_ok` | `trust-option-saved-p` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of trust-selector isSavedOption |

Leftover sibling unused-slug remount. Does not remount `trust_option_saved_p`. Timed work is the remounted path. Observed `tosp_*` are exact. First n=5 freeze **1.896×** (54.839 / 28.920 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1271 — `cli_selectors` (trmkx_ok)

| metric | cadr | pi |
|---|---|---|
| `trmkx_ok` | `make-trust-selector-state` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of TrustSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_trust_selector_state`. Timed work is the remounted path. Observed `mtss_*` are exact. First n=5 freeze **1.770×** (154.616 / 87.346 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1272 — `cli_selectors` (trrsx_ok)

| metric | cadr | pi |
|---|---|---|
| `trrsx_ok` | `render-trust-selector` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of TrustSelectorComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_trust_selector`. Timed work is the remounted path. Observed `rtrs_*` are exact. First n=5 freeze **6.224×** (1224.489 / 196.750 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1273 — `cli_selectors` (lmsxx_ok)

| metric | cadr | pi |
|---|---|---|
| `lmsxx_ok` | `make-login-method-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of ExtensionSelector login-method constructor |

Leftover sibling unused-slug remount. Does not remount `make_login_method_selector_state`. Timed work is the remounted path. Observed `mlms_*` are exact. First n=5 freeze **2.421×** (3.606 / 1.489 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1274 — `cli_selectors` (akixx_ok)

| metric | cadr | pi |
|---|---|---|
| `akixx_ok` | `make-api-key-input-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showPrompt api key Input constructor |

Leftover sibling unused-slug remount. Does not remount `make_api_key_input_state`. Timed work is the remounted path. Observed `makis_*` are exact. First n=5 freeze **7.512×** (2.669 / 0.355 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1275 — `cli_selectors` (ossxx_ok)

| metric | cadr | pi |
|---|---|---|
| `ossxx_ok` | `make-oauth-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of OauthSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_oauth_selector_state`. Timed work is the remounted path. Observed `moss_*` are exact. First n=5 freeze **1.714×** (8.001 / 4.668 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1276 — `cli_selectors` (tsmxx_ok)

| metric | cadr | pi |
|---|---|---|
| `tsmxx_ok` | `trust-selector-move` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of wrap selection index |

Leftover sibling unused-slug remount. Does not remount `trust_selector_move`. Timed work is the remounted path. Observed `tsm_*` are exact. First n=5 freeze **2.591×** (294.776 / 113.763 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1277 — `cli_selectors` (tsexx_ok)

| metric | cadr | pi |
|---|---|---|
| `tsexx_ok` | `trust-selector-handle-event` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of trust-selector handle-event dispatch |

Leftover sibling unused-slug remount. Does not remount `trust_selector_handle_event`. Timed work is the remounted path. Observed `tshe_*` are exact. First n=5 freeze **2.212×** (312.875 / 141.421 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1278 — `cli_selectors` (tuixx_ok)

| metric | cadr | pi |
|---|---|---|
| `tuixx_ok` | `trust-selector-ui-state` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of TrustSelectorComponent UI state |

Leftover sibling unused-slug remount. Does not remount `trust_selector_ui_state`. Timed work is the remounted path. Observed `rts_*` are exact. First n=5 freeze **2.315×** (365.451 / 157.831 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1279 — `cli_selectors` (slxx_ok)

| metric | cadr | pi |
|---|---|---|
| `slxx_ok` | `thinking-selector-selected-level` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector selected SelectList item |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_selected_level`. Timed work is the remounted path. Observed `tssl_*` are exact. First n=5 freeze **2.236×** (0.785 / 0.351 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1280 — `cli_selectors` (dscxx_ok)

| metric | cadr | pi |
|---|---|---|
| `dscxx_ok` | `thinking-level-description-line` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of LEVEL_DESCRIPTIONS default suffix |

Leftover sibling unused-slug remount. Does not remount `thinking_level_description_line`. Timed work is the remounted path. Observed `tsdl_*` are exact. First n=5 freeze **3.744×** (0.519 / 0.139 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1281 — `cli_selectors` (rthxx_ok)

| metric | cadr | pi |
|---|---|---|
| `rthxx_ok` | `render-thinking-selector` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of ThinkingSelectorComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_thinking_selector`. Timed work is the remounted path. Observed `tsrd_*` are exact. First n=5 freeze **91.402×** (280.415 / 3.068 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1282 — `cli_selectors` (lblxx_ok)

| metric | cadr | pi |
|---|---|---|
| `lblxx_ok` | `oauth-option-status-label` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of formatStatusIndicator plain label |

Leftover sibling unused-slug remount. Does not remount `oauth_option_status_label`. Timed work is the remounted path. Observed `oosl_*` are exact. First n=5 freeze **4.001×** (2.121 / 0.530 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1283 — `cli_selectors` (typxx_ok)

| metric | cadr | pi |
|---|---|---|
| `typxx_ok` | `credential-entry-auth-type` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of credential-entry authType |

Leftover sibling unused-slug remount. Does not remount `credential_entry_auth_type`. Timed work is the remounted path. Observed `ceat_*` are exact. First n=5 freeze **3.779×** (0.589 / 0.156 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1284 — `cli_selectors` (envxx_ok)

| metric | cadr | pi |
|---|---|---|
| `envxx_ok` | `oauth-environment-source-p` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of env source regex |

Leftover sibling unused-slug remount. Does not remount `oauth_environment_source_p`. Timed work is the remounted path. Observed `oesp_*` are exact. First n=5 freeze **5.032×** (1.050 / 0.209 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1285 — `cli_selectors` (oasxx_ok)

| metric | cadr | pi |
|---|---|---|
| `oasxx_ok` | `oauth-selector-selection` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of filteredProviders[selectedIndex] |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_selection`. Timed work is the remounted path. Observed `oss_*` are exact. First n=5 freeze **17.768×** (77.864 / 4.382 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1286 — `cli_selectors` (fltxx_ok)

| metric | cadr | pi |
|---|---|---|
| `fltxx_ok` | `oauth-selector-apply-filter` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of filterProviders |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_apply_filter`. Timed work is the remounted path. Observed `osaf_*` are exact. First n=5 freeze **10.131×** (89.250 / 8.810 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1287 — `cli_selectors` (qryxx_ok)

| metric | cadr | pi |
|---|---|---|
| `qryxx_ok` | `oauth-selector-search-text` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of filterProviders search text |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_search_text`. Timed work is the remounted path. Observed `osst_*` are exact. First n=5 freeze **5.191×** (1.512 / 0.291 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1288 — `cli_selectors` (latxx_ok)

| metric | cadr | pi |
|---|---|---|
| `latxx_ok` | `login-auth-type-route` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showLoginAuthTypeSelector routing |

Leftover sibling unused-slug remount. Does not remount `login_auth_type_route`. Timed work is the remounted path. Observed `latr_*` are exact. First n=5 freeze **9.081×** (3.705 / 0.408 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1289 — `cli_selectors` (lpoxx_ok)

| metric | cadr | pi |
|---|---|---|
| `lpoxx_ok` | `login-provider-options` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of getLoginProviderOptions |

Leftover sibling unused-slug remount. Does not remount `login_provider_options`. Timed work is the remounted path. Observed `lpo_*` are exact. First n=5 freeze **3.768×** (10.552 / 2.800 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1290 — `cli_selectors` (lgoxx_ok)

| metric | cadr | pi |
|---|---|---|
| `lgoxx_ok` | `logout-provider-options` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of getLogoutProviderOptions |

Leftover sibling unused-slug remount. Does not remount `logout_provider_options`. Timed work is the remounted path. Observed `lgo_*` are exact. First n=5 freeze **2.479×** (9.229 / 3.723 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1291 — `cli_selectors` (lmhxx_ok)

| metric | cadr | pi |
|---|---|---|
| `lmhxx_ok` | `login-method-selector-handle-event` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of login method selector handleInput |

Leftover sibling unused-slug remount. Does not remount `login_method_selector_handle_event`. Timed work is the remounted path. Observed `lmhe_*` are exact. First n=5 freeze **5.597×** (3.617 / 0.646 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1292 — `cli_selectors` (luixx_ok)

| metric | cadr | pi |
|---|---|---|
| `luixx_ok` | `login-method-selector-ui-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of ExtensionSelectorComponent UI state |

Leftover sibling unused-slug remount. Does not remount `login_method_selector_ui_state`. Timed work is the remounted path. Observed `lmsui_*` are exact. First n=5 freeze **4.239×** (435.820 / 102.824 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1293 — `cli_selectors` (akuxx_ok)

| metric | cadr | pi |
|---|---|---|
| `akuxx_ok` | `api-key-input-ui-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showPrompt api key UI state |

Leftover sibling unused-slug remount. Does not remount `api_key_input_ui_state`. Timed work is the remounted path. Observed `akiui_*` are exact. First n=5 freeze **2.044×** (203.048 / 99.350 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1294 — `cli_selectors` (akhexx_ok)

| metric | cadr | pi |
|---|---|---|
| `akhexx_ok` | `api-key-input-state-handle-event` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of handleInput api key prompt dispatch |

Leftover sibling unused-slug remount. Does not remount `api_key_input_state_handle_event`. Timed work is the remounted path. Observed `akhe_*` are exact. First n=5 freeze **1.697×** (6.396 / 3.770 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1295 — `cli_selectors` (mlsxx_ok)

| metric | cadr | pi |
|---|---|---|
| `mlsxx_ok` | `make-login-method-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of ExtensionSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_login_method_selector_state`. Timed work is the remounted path. Observed `mlms_*` are exact. First n=5 freeze **3.572×** (3.415 / 0.956 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1296 — `cli_selectors` (aisxx_ok)

| metric | cadr | pi |
|---|---|---|
| `aisxx_ok` | `make-api-key-input-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showPrompt api key Input constructor |

Leftover sibling unused-slug remount. Does not remount `make_api_key_input_state`. Timed work is the remounted path. Observed `makis_*` are exact. First n=5 freeze **8.480×** (2.799 / 0.330 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1297 — `cli_selectors` (henxx_ok)

| metric | cadr | pi |
|---|---|---|
| `henxx_ok` | `thinking-selector-handle-event` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector typed input event dispatch |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_handle_event`. Timed work is the remounted path. Observed `tshe_*` are exact. First n=5 freeze **1.892×** (4.835 / 2.555 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1298 — `cli_selectors` (mtsxx_ok)

| metric | cadr | pi |
|---|---|---|
| `mtsxx_ok` | `make-thinking-selector-state` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector constructor filter + select current |

Leftover sibling unused-slug remount. Does not remount `make_thinking_selector_state`. Timed work is the remounted path. Observed `tms_*` are exact. First n=5 freeze **4.827×** (2.041 / 0.423 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1299 — `cli_selectors` (lstxx_ok)

| metric | cadr | pi |
|---|---|---|
| `lstxx_ok` | `thinking-level-search-text` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector label + description search text |

Leftover sibling unused-slug remount. Does not remount `thinking_level_search_text`. Timed work is the remounted path. Observed `tlst_*` are exact. First n=5 freeze **6.705×** (1.473 / 0.220 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1300 — `cli_selectors` (cdsxx_ok)

| metric | cadr | pi |
|---|---|---|
| `cdsxx_ok` | `Math.ceil(timeoutMs/1000)` (`src/cadr-cli/interactive/components/countdown.lisp`) | leftover replica of Math.ceil(timeoutMs/1000) |

Leftover sibling unused-slug remount. Does not remount `countdown_seconds`. Timed work is the remounted path. Observed `cds_*` are exact. First n=5 freeze **9.253×** (1.212 / 0.131 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1301 — `cli_selectors` (cdtxx_ok)

| metric | cadr | pi |
|---|---|---|
| `cdtxx_ok` | `countdown-timer-tick` (`src/cadr-cli/interactive/components/countdown.lisp`) | leftover replica of countdown tick |

Leftover sibling unused-slug remount. Does not remount `countdown_tick`. Timed work is the remounted path. Observed `cdt_*` are exact. First n=5 freeze **6.431×** (1.052 / 0.164 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1302 — `cli_selectors` (cdrxx_ok)

| metric | cadr | pi |
|---|---|---|
| `cdrxx_ok` | `countdown-request-render` (`src/cadr-cli/interactive/components/countdown.lisp`) | leftover replica of countdown requestRender |

Leftover sibling unused-slug remount. Does not remount `countdown_render`. Timed work is the remounted path. Observed `cdr_*` are exact. First n=5 freeze **7.367×** (1.204 / 0.163 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1303 — `powershell_tool` (utfxx_ok)

| metric | cadr | pi |
|---|---|---|
| `utfxx_ok` | `+powershell-utf8-output-prefix+` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of UTF8_OUTPUT_PREFIX |

Leftover sibling unused-slug remount. Does not remount `utf8_prefix`. Timed work is the remounted path. Observed `psu_*` are exact. First n=5 freeze **6.209×** (0.702 / 0.113 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1304 — `powershell_tool` (pfxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `pfxxx_ok` | `make-powershell-tool` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of prefix+command wrap |

Leftover sibling unused-slug remount. Does not remount `prefix_command`. Timed work is the remounted path. Observed `psc_*` are exact. First n=5 freeze **4.585×** (1.042 / 0.227 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1305 — `powershell_tool` (mtbxx_ok)

| metric | cadr | pi |
|---|---|---|
| `mtbxx_ok` | `make-powershell-tool` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of createPowerShellToolDefinition |

Leftover sibling unused-slug remount. Does not remount `make_tool`. Timed work is the remounted path. Observed `pmt_*` are exact. First n=5 freeze **2.131×** (3.145 / 1.476 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1306 — `cli_selectors` (draxx_ok)

| metric | cadr | pi |
|---|---|---|
| `draxx_ok` | `daxnuts-rgb-at` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of parseImage pixel lookup |

Leftover sibling unused-slug remount. Does not remount `daxnuts_rgb_at`. Timed work is the remounted path. Observed `dra_*` are exact. First n=5 freeze **5.419×** (1.297 / 0.239 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1307 — `cli_selectors` (dmcxx_ok)

| metric | cadr | pi |
|---|---|---|
| `dmcxx_ok` | `make-daxnuts-component` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of DaxnutsComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_daxnuts_component`. Timed work is the remounted path. Observed `dmc_*` are exact. First n=5 freeze **7.513×** (1.025 / 0.136 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1308 — `cli_selectors` (dctxx_ok)

| metric | cadr | pi |
|---|---|---|
| `dctxx_ok` | `daxnuts-component-tick` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of DaxnutsComponent interval |

Leftover sibling unused-slug remount. Does not remount `daxnuts_component_tick`. Timed work is the remounted path. Observed `dct_*` are exact. First n=5 freeze **15.546×** (4.434 / 0.285 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1312 — `cli_selectors` (tllxx_ok)

| metric | cadr | pi |
|---|---|---|
| `tllxx_ok` | `thinking-level-label` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking level label |

Leftover sibling unused-slug remount. Does not remount `thinking_level_label`. Timed work is the remounted path. Observed `tll_*` are exact. First n=5 freeze **4.063×** (0.582 / 0.143 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1313 — `cli_selectors` (tsqxx_ok)

| metric | cadr | pi |
|---|---|---|
| `tsqxx_ok` | `thinking-selector-set-query` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of applyFilter from search |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_set_query`. Timed work is the remounted path. Observed `tsq_*` are exact. First n=5 freeze **1.813×** (14.416 / 7.953 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1314 — `cli_selectors` (tskbxx_ok)

| metric | cadr | pi |
|---|---|---|
| `tskbxx_ok` | `thinking-selector-keybindings` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of getKeybindings |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_keybindings`. Timed work is the remounted path. Observed `tskb_*` are exact. First n=5 freeze **15.428×** (3.278 / 0.212 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1309 — `cli_bootstrap_sessions` (pbkxx_ok)

| metric | cadr | pi |
|---|---|---|
| `pbkxx_ok` | `parse-user-bash-input` (`src/cadr-cli/repl.lisp`) | leftover replica of ! / !! bash extract |

Leftover sibling unused-slug remount. Does not remount `parse_bash`. Timed work is the remounted path. Observed `pb_*` are exact. First n=5 freeze **3.227×** (0.965 / 0.299 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1310 — `cli_bootstrap_sessions` (rtkxx_ok)

| metric | cadr | pi |
|---|---|---|
| `rtkxx_ok` | `response-text` (`src/cadr-cli/repl.lisp`) | leftover replica of textParts.join |

Leftover sibling unused-slug remount. Does not remount `response_text`. Timed work is the remounted path. Observed `rt_*` are exact. First n=5 freeze **2.628×** (1.442 / 0.549 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1311 — `cli_bootstrap_sessions` (dpkxx_ok)

| metric | cadr | pi |
|---|---|---|
| `dpkxx_ok` | `dispatch-user-input` (`src/cadr-cli/repl.lisp`) | leftover replica of submit classify |

Leftover sibling unused-slug remount. Does not remount `dispatch_plain`. Timed work is the remounted path. Observed `dp_*` are exact. First n=5 freeze **1.799×** (0.847 / 0.471 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1324 — `cli_selectors` (umevxx_ok)

| metric | cadr | pi |
|---|---|---|
| `umevxx_ok` | `user-message-selector-handle-event` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageList.handleInput (structured) |

Leftover sibling unused-slug remount. Does not remount `user_message_handle_event`. Timed work is the remounted path. Observed `umhe_*` are exact. First n=5 freeze **3.424×** (2.178 / 0.636 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1325 — `cli_selectors` (umrwxx_ok)

| metric | cadr | pi |
|---|---|---|
| `umrwxx_ok` | `user-message-selector-handle-raw-input` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageList.handleInput (raw) |

Leftover sibling unused-slug remount. Does not remount `user_message_handle_raw`. Timed work is the remounted path. Observed `umhr_*` are exact. First n=5 freeze **27.799×** (98.992 / 3.561 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1326 — `cli_selectors` (umrsxx_ok)

| metric | cadr | pi |
|---|---|---|
| `umrsxx_ok` | `render-user-message-selector` (`src/cadr-cli/interactive/selectors/fork.lisp`) | leftover replica of UserMessageSelectorComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_user_message_selector`. Timed work is the remounted path. Observed `umrd_*` are exact. First n=5 freeze **204.526×** (267.422 / 1.308 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1318 — `cli_selectors` (ldprxx_ok)

| metric | cadr | pi |
|---|---|---|
| `ldprxx_ok` | `login-dialog-show-prompt` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showPrompt |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_prompt`. Timed work is the remounted path. Observed `ldpr_*` are exact. First n=5 freeze **4.148×** (12.485 / 3.010 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1319 — `cli_selectors` (ldixx_ok)

| metric | cadr | pi |
|---|---|---|
| `ldixx_ok` | `login-dialog-show-info` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showInfo |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_info`. Timed work is the remounted path. Observed `ldi_*` are exact. First n=5 freeze **3.051×** (12.861 / 4.216 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1320 — `cli_selectors` (lddtxx_ok)

| metric | cadr | pi |
|---|---|---|
| `lddtxx_ok` | `login-dialog-show-details` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showDetails |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_details`. Timed work is the remounted path. Observed `lddt_*` are exact. First n=5 freeze **1.532×** (3.876 / 2.531 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1315 — `cli_selectors` (ldwxx_ok)

| metric | cadr | pi |
|---|---|---|
| `ldwxx_ok` | `login-dialog-show-waiting` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showWaiting |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_waiting`. Timed work is the remounted path. Observed `ldw_*` are exact. First n=5 freeze **5.483×** (7.936 / 1.447 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1316 — `cli_selectors` (ldpxx_ok)

| metric | cadr | pi |
|---|---|---|
| `ldpxx_ok` | `login-dialog-show-progress` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showProgress |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_progress`. Timed work is the remounted path. Observed `ldp_*` are exact. First n=5 freeze **6.580×** (6.653 / 1.011 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1317 — `cli_selectors` (ldmixx_ok)

| metric | cadr | pi |
|---|---|---|
| `ldmixx_ok` | `login-dialog-show-manual-input` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.showManualInput |

Leftover sibling unused-slug remount. Does not remount `login_dialog_show_manual_input`. Timed work is the remounted path. Observed `ldmi_*` are exact. First n=5 freeze **6.211×** (7.435 / 1.197 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1321 — `cli_selectors` (ldcixx_ok)

| metric | cadr | pi |
|---|---|---|
| `ldcixx_ok` | `login-dialog-complete-input` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.replaceInputWithSubmittedText |

Leftover sibling unused-slug remount. Does not remount `login_dialog_complete_input`. Timed work is the remounted path. Observed `ldci_*` are exact. First n=5 freeze **5.578×** (7.961 / 1.427 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1322 — `cli_selectors` (ldhexx_ok)

| metric | cadr | pi |
|---|---|---|
| `ldhexx_ok` | `login-dialog-state-handle-event` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent.handleInput |

Leftover sibling unused-slug remount. Does not remount `login_dialog_handle_event`. Timed work is the remounted path. Observed `ldhe_*` are exact. First n=5 freeze **7.142×** (9.364 / 1.311 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1323 — `cli_selectors` (ldrdxx_ok)

| metric | cadr | pi |
|---|---|---|
| `ldrdxx_ok` | `render-login-dialog-state` (`src/cadr-cli/interactive/selectors/login-dialog.lisp`) | leftover replica of LoginDialogComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_login_dialog`. Timed work is the remounted path. Observed `ldrd_*` are exact. First n=5 freeze **91.160×** (133.993 / 1.470 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1327 — `cli_selectors` (mkbxx_ok)

| metric | cadr | pi |
|---|---|---|
| `mkbxx_ok` | `make-models-selector-keybindings` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of KeybindingsManager app.models.* |

Leftover sibling unused-slug remount. Does not remount `make_models_selector_keybindings`. Timed work is the remounted path. Observed `mmskb_*` are exact. First n=5 freeze **0.542×** (36.763 / 67.773 µs) on host `Friend-MachineD`, ceiling 8.0. Under-1× (cadr leads); not listed in over-1× table. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1328 — `cli_selectors` (msmsxx_ok)

| metric | cadr | pi |
|---|---|---|
| `msmsxx_ok` | `make-scoped-models-selector-state` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of ScopedModelsSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_scoped_models_selector_state`. Timed work is the remounted path. Observed `msmksc_*` are exact. First n=5 freeze **28.012×** (112.519 / 4.017 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1329 — `cli_selectors` (mrmsxx_ok)

| metric | cadr | pi |
|---|---|---|
| `mrmsxx_ok` | `render-model-selector` (`src/cadr-cli/interactive/selectors/models.lisp`) | leftover replica of ModelSelectorComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_model_selector`. Timed work is the remounted path. Observed `rms_*` are exact. First n=5 freeze **32.412×** (233.429 / 7.202 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1330 — `cli_selectors` (thafxx_ok)

| metric | cadr | pi |
|---|---|---|
| `thafxx_ok` | `thinking-selector-apply-filter` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector applyFilter |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_apply_filter`. Timed work is the remounted path. Observed `tsaf_*` are exact. First n=5 freeze **1.442×** (15.184 / 10.528 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1331 — `cli_selectors` (thclxx_ok)

| metric | cadr | pi |
|---|---|---|
| `thclxx_ok` | `thinking-selector-clamp-selected` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector clamp selected |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_clamp_selected`. Timed work is the remounted path. Observed `tscl_*` are exact. First n=5 freeze **5.254×** (1.000 / 0.190 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1332 — `cli_selectors` (thscxx_ok)

| metric | cadr | pi |
|---|---|---|
| `thscxx_ok` | `thinking-selector-select-current` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector select current |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_select_current`. Timed work is the remounted path. Observed `tssc_*` are exact. First n=5 freeze **3.654×** (1.485 / 0.406 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1333 — `cli_selectors` (thmvxx_ok)

| metric | cadr | pi |
|---|---|---|
| `thmvxx_ok` | `thinking-selector-move` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector wrap selected |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_move`. Timed work is the remounted path. Observed `tsmv_*` are exact. First n=5 freeze **2.484×** (1.163 / 0.468 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1334 — `cli_selectors` (thhrxx_ok)

| metric | cadr | pi |
|---|---|---|
| `thhrxx_ok` | `thinking-selector-handle-raw-input` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector handleInput keybindings |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_handle_raw_input`. Timed work is the remounted path. Observed `tshri_*` are exact. First n=5 freeze **36.779×** (210.204 / 5.715 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1335 — `cli_selectors` (thhexx_ok)

| metric | cadr | pi |
|---|---|---|
| `thhexx_ok` | `thinking-selector-handle-event` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector typed input event dispatch |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_handle_event`. Timed work is the remounted path. Observed `tshe_*` are exact. First n=5 freeze **1.167×** (4.805 / 4.117 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1336 — `cli_selectors` (trsvxx_ok)

| metric | cadr | pi |
|---|---|---|
| `trsvxx_ok` | `trust-option-saved-p` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of trust-selector isSavedOption |

Leftover sibling unused-slug remount. Does not remount `trust_option_saved_p`. Timed work is the remounted path. Observed `tosp_*` are exact. First n=5 freeze **1.662×** (60.336 / 36.304 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1337 — `cli_selectors` (trmkxx_ok)

| metric | cadr | pi |
|---|---|---|
| `trmkxx_ok` | `make-trust-selector-state` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of TrustSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_trust_selector_state`. Timed work is the remounted path. Observed `mtss_*` are exact. First n=5 freeze **1.349×** (160.158 / 118.732 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1338 — `cli_selectors` (trrsxx_ok)

| metric | cadr | pi |
|---|---|---|
| `trrsxx_ok` | `render-trust-selector` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of TrustSelectorComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_trust_selector`. Timed work is the remounted path. Observed `rtrs_*` are exact. First n=5 freeze **4.822×** (1286.519 / 266.786 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1348 — `cli_selectors` (lblxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `lblxxx_ok` | `oauth-option-status-label` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of formatStatusIndicator plain label |

Leftover sibling unused-slug remount. Does not remount `oauth_option_status_label`. Timed work is the remounted path. Observed `oosl_*` are exact. First n=5 freeze **2.374×** (2.380 / 1.002 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1349 — `cli_selectors` (typxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `typxxx_ok` | `credential-entry-auth-type` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of credential-entry authType |

Leftover sibling unused-slug remount. Does not remount `credential_entry_auth_type`. Timed work is the remounted path. Observed `ceat_*` are exact. First n=5 freeze **2.670×** (0.833 / 0.312 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1350 — `cli_selectors` (envxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `envxxx_ok` | `oauth-environment-source-p` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of env source regex |

Leftover sibling unused-slug remount. Does not remount `oauth_environment_source_p`. Timed work is the remounted path. Observed `oesp_*` are exact. First n=5 freeze **3.008×** (1.321 / 0.439 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1342 — `cli_selectors` (tsmxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `tsmxxx_ok` | `trust-selector-move` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of wrap selection index |

Leftover sibling unused-slug remount. Does not remount `trust_selector_move`. Timed work is the remounted path. Observed `tsm_*` are exact. First n=5 freeze **2.443×** (357.629 / 146.367 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1343 — `cli_selectors` (tsexxx_ok)

| metric | cadr | pi |
|---|---|---|
| `tsexxx_ok` | `trust-selector-handle-event` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of trust-selector handle-event dispatch |

Leftover sibling unused-slug remount. Does not remount `trust_selector_handle_event`. Timed work is the remounted path. Observed `tshe_*` are exact. First n=5 freeze **2.739×** (461.478 / 168.488 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1344 — `cli_selectors` (tuixxx_ok)

| metric | cadr | pi |
|---|---|---|
| `tuixxx_ok` | `trust-selector-ui-state` (`src/cadr-cli/interactive/selectors/trust.lisp`) | leftover replica of TrustSelectorComponent UI state |

Leftover sibling unused-slug remount. Does not remount `trust_selector_ui_state`. Timed work is the remounted path. Observed `rts_*` are exact. First n=5 freeze **1.900×** (460.535 / 242.412 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1339 — `cli_selectors` (lmsxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `lmsxxx_ok` | `make-login-method-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of ExtensionSelector login-method constructor |

Leftover sibling unused-slug remount. Does not remount `make_login_method_selector_state`. Timed work is the remounted path. Observed `mlms_*` are exact. First n=5 freeze **3.914×** (3.801 / 0.971 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1340 — `cli_selectors` (akixxx_ok)

| metric | cadr | pi |
|---|---|---|
| `akixxx_ok` | `make-api-key-input-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showPrompt api key Input constructor |

Leftover sibling unused-slug remount. Does not remount `make_api_key_input_state`. Timed work is the remounted path. Observed `makis_*` are exact. First n=5 freeze **11.185×** (3.934 / 0.352 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1341 — `cli_selectors` (ossxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `ossxxx_ok` | `make-oauth-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of OauthSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_oauth_selector_state`. Timed work is the remounted path. Observed `moss_*` are exact. First n=5 freeze **1.798×** (8.730 / 4.855 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1345 — `cli_selectors` (slxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `slxxx_ok` | `thinking-selector-selected-level` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking-selector selected SelectList item |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_selected_level`. Timed work is the remounted path. Observed `tssl_*` are exact. First n=5 freeze **4.489×** (1.096 / 0.244 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1346 — `cli_selectors` (dscxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `dscxxx_ok` | `thinking-level-description-line` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of LEVEL_DESCRIPTIONS default suffix |

Leftover sibling unused-slug remount. Does not remount `thinking_level_description_line`. Timed work is the remounted path. Observed `tsdl_*` are exact. First n=5 freeze **4.094×** (0.591 / 0.144 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1347 — `cli_selectors` (rthxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `rthxxx_ok` | `render-thinking-selector` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of ThinkingSelectorComponent layout |

Leftover sibling unused-slug remount. Does not remount `render_thinking_selector`. Timed work is the remounted path. Observed `tsrd_*` are exact. First n=5 freeze **54.590×** (360.624 / 6.606 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1351 — `cli_selectors` (oasxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `oasxxx_ok` | `oauth-selector-selection` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of filteredProviders[selectedIndex] |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_selection`. Timed work is the remounted path. Observed `oss_*` are exact. First n=5 freeze **21.149×** (99.113 / 4.686 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1352 — `cli_selectors` (fltxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `fltxxx_ok` | `oauth-selector-apply-filter` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of filterProviders |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_apply_filter`. Timed work is the remounted path. Observed `osaf_*` are exact. First n=5 freeze **13.059×** (108.534 / 8.311 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1353 — `cli_selectors` (qryxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `qryxxx_ok` | `oauth-selector-search-text` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of filterProviders search text |

Leftover sibling unused-slug remount. Does not remount `oauth_selector_search_text`. Timed work is the remounted path. Observed `osst_*` are exact. First n=5 freeze **5.541×** (2.538 / 0.458 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1360 — `cli_selectors` (akhexxx_ok)

| metric | cadr | pi |
|---|---|---|
| `akhexxx_ok` | `api-key-input-state-handle-event` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of handleInput api key prompt dispatch |

Leftover sibling unused-slug remount. Does not remount `api_key_input_state_handle_event`. Timed work is the remounted path. Observed `akhe_*` are exact. First n=5 freeze **2.081×** (6.603 / 3.173 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1361 — `cli_selectors` (mlsxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `mlsxxx_ok` | `make-login-method-selector-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of ExtensionSelectorComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_login_method_selector_state`. Timed work is the remounted path. Observed `mlms_*` are exact. First n=5 freeze **3.570×** (3.397 / 0.952 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1362 — `cli_selectors` (aisxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `aisxxx_ok` | `make-api-key-input-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showPrompt api key Input constructor |

Leftover sibling unused-slug remount. Does not remount `make_api_key_input_state`. Timed work is the remounted path. Observed `makis_*` are exact. First n=5 freeze **6.481×** (2.607 / 0.402 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1357 — `cli_selectors` (lmhxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `lmhxxx_ok` | `login-method-selector-handle-event` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of login method selector handleInput |

Leftover sibling unused-slug remount. Does not remount `login_method_selector_handle_event`. Timed work is the remounted path. Observed `lmhe_*` are exact. First n=5 freeze **5.741×** (3.390 / 0.590 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1358 — `cli_selectors` (luixxx_ok)

| metric | cadr | pi |
|---|---|---|
| `luixxx_ok` | `login-method-selector-ui-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of ExtensionSelectorComponent UI state |

Leftover sibling unused-slug remount. Does not remount `login_method_selector_ui_state`. Timed work is the remounted path. Observed `lmsui_*` are exact. First n=5 freeze **4.853×** (446.180 / 91.942 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1359 — `cli_selectors` (akuxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `akuxxx_ok` | `api-key-input-ui-state` (`src/cadr-cli/interactive/selectors/auth.lisp`) | leftover replica of showPrompt api key UI state |

Leftover sibling unused-slug remount. Does not remount `api_key_input_ui_state`. Timed work is the remounted path. Observed `akiui_*` are exact. First n=5 freeze **2.180×** (210.540 / 96.557 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1372 — `cli_selectors` (draxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `draxxx_ok` | `daxnuts-rgb-at` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of parseImage pixel lookup |

Leftover sibling unused-slug remount. Does not remount `daxnuts_rgb_at`. Timed work is the remounted path. Observed `dra_*` are exact. First n=5 freeze **6.787×** (1.597 / 0.235 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1373 — `cli_selectors` (dmcxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `dmcxxx_ok` | `make-daxnuts-component` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of DaxnutsComponent constructor |

Leftover sibling unused-slug remount. Does not remount `make_daxnuts_component`. Timed work is the remounted path. Observed `dmc_*` are exact. First n=5 freeze **8.963×** (1.165 / 0.130 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1374 — `cli_selectors` (dctxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `dctxxx_ok` | `daxnuts-component-tick` (`src/cadr-cli/interactive/components/daxnuts.lisp`) | leftover replica of DaxnutsComponent interval |

Leftover sibling unused-slug remount. Does not remount `daxnuts_component_tick`. Timed work is the remounted path. Observed `dct_*` are exact. First n=5 freeze **18.022×** (4.660 / 0.259 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1369 — `powershell_tool` (utfxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `utfxxx_ok` | `+powershell-utf8-output-prefix+` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of UTF8_OUTPUT_PREFIX |

Leftover sibling unused-slug remount. Does not remount `utf8_prefix`. Timed work is the remounted path. Observed `psu_*` are exact. First n=5 freeze **5.837×** (0.665 / 0.114 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1370 — `powershell_tool` (pfxxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `pfxxxx_ok` | `make-powershell-tool` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of prefix+command wrap |

Leftover sibling unused-slug remount. Does not remount `prefix_command`. Timed work is the remounted path. Observed `psc_*` are exact. First n=5 freeze **4.008×** (0.843 / 0.210 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1371 — `powershell_tool` (mtbxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `mtbxxx_ok` | `make-powershell-tool` (`src/cadr-cli/tools/powershell.lisp`) | leftover replica of createPowerShellToolDefinition |

Leftover sibling unused-slug remount. Does not remount `make_tool`. Timed work is the remounted path. Observed `pmt_*` are exact. First n=5 freeze **1.998×** (2.845 / 1.424 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1366 — `cli_selectors` (cdsxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `cdsxxx_ok` | `Math.ceil(timeoutMs/1000)` (`src/cadr-cli/interactive/components/countdown.lisp`) | leftover replica of Math.ceil(timeoutMs/1000) |

Leftover sibling unused-slug remount. Does not remount `countdown_seconds`. Timed work is the remounted path. Observed `cds_*` are exact. First n=5 freeze **5.811×** (1.169 / 0.201 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1367 — `cli_selectors` (cdtxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `cdtxxx_ok` | `countdown-timer-tick` (`src/cadr-cli/interactive/components/countdown.lisp`) | leftover replica of countdown tick |

Leftover sibling unused-slug remount. Does not remount `countdown_tick`. Timed work is the remounted path. Observed `cdt_*` are exact. First n=5 freeze **7.107×** (1.092 / 0.154 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1368 — `cli_selectors` (cdrxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `cdrxxx_ok` | `countdown-request-render` (`src/cadr-cli/interactive/components/countdown.lisp`) | leftover replica of countdown requestRender |

Leftover sibling unused-slug remount. Does not remount `countdown_render`. Timed work is the remounted path. Observed `cdr_*` are exact. First n=5 freeze **9.080×** (1.477 / 0.163 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1375 — `cli_bootstrap_sessions` (pbkxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `pbkxxx_ok` | `parse-user-bash-input` (`src/cadr-cli/repl.lisp`) | leftover replica of ! / !! bash extract |

Leftover sibling unused-slug remount. Does not remount `parse_bash`. Timed work is the remounted path. Observed `pb_*` are exact. First n=5 freeze **2.411×** (0.766 / 0.318 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1376 — `cli_bootstrap_sessions` (rtkxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `rtkxxx_ok` | `response-text` (`src/cadr-cli/repl.lisp`) | leftover replica of textParts.join |

Leftover sibling unused-slug remount. Does not remount `response_text`. Timed work is the remounted path. Observed `rt_*` are exact. First n=5 freeze **2.539×** (1.418 / 0.558 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1377 — `cli_bootstrap_sessions` (dpkxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `dpkxxx_ok` | `dispatch-user-input` (`src/cadr-cli/repl.lisp`) | leftover replica of submit classify |

Leftover sibling unused-slug remount. Does not remount `dispatch_plain`. Timed work is the remounted path. Observed `dp_*` are exact. First n=5 freeze **1.828×** (0.715 / 0.391 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1378 — `cli_selectors` (tllxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `tllxxx_ok` | `thinking-level-label` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of thinking level label |

Leftover sibling unused-slug remount. Does not remount `thinking_level_label`. Timed work is the remounted path. Observed `tll_*` are exact. First n=5 freeze **2.746×** (0.396 / 0.144 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1379 — `cli_selectors` (tsqxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `tsqxxx_ok` | `thinking-selector-set-query` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of applyFilter from search |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_set_query`. Timed work is the remounted path. Observed `tsq_*` are exact. First n=5 freeze **1.165×** (12.192 / 10.467 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 1380 — `cli_selectors` (tskbxxx_ok)

| metric | cadr | pi |
|---|---|---|
| `tskbxxx_ok` | `thinking-selector-keybindings` (`src/cadr-cli/interactive/selectors/thinking.lisp`) | leftover replica of getKeybindings |

Leftover sibling unused-slug remount. Does not remount `thinking_selector_keybindings`. Timed work is the remounted path. Observed `tskb_*` are exact. First n=5 freeze **14.631×** (2.908 / 0.199 µs) on host `Friend-MachineD`, ceiling 8.0. Over-1× booked. Scoped gate PASS. Same commit no optimize. `nextPairNum` left at 328.

### Pair 273 — `file_mutation_queue` (wait_turn)

| metric | cadr | pi |
|---|---|---|
| `wait_turn` | `wait-for-file-mutation-turn` (`src/cadr-agent/file-mutation-queue.lisp`) | `withFileMutationQueue` await-current / ticket wait after enqueue (`packages/coding-agent/src/core/tools/file-mutation-queue.ts`) |

Leftover sibling of Pair 261 `with_queue`, Pair 270 `queue_key`, Pair 271
`lock`, and Pair 272 `register` on the same `agent_tool_loop` hole. Timed
work is FIFO ticket wait after enqueue (existing path, symlink alias,
missing path, distinct sibling) — not fn/release, not
`with-file-mutation-queue`, not write/edit tools. Same staged scratch
layout as `with_queue`. Observed `fmqw_serving` / `fmqw_pending` /
`fmqw_other` / `fmqw_missing` / `fmqw_n` are exact. First n=5 freeze
**0.767×** (101.7 / 132.5 µs) on host `cursor`, ceiling 8.0. Gate used
`--only-enforce` (script rc=1 only from known old holes `lc_n` / `lc_sleep` /
help text; this metric did not fail). Same commit no optimize.

### Pair 257 — `execution_env` (exists_remove_temps)

| metric | cadr | pi |
|---|---|---|
| `exists_remove_temps` | `execution-env-exists-p` + `execution-env-remove` + temp helpers (`src/cadr-agent/execution-env.lisp`) | `NodeExecutionEnv.exists` / `remove` / `createTempDir` / `createTempFile` (`packages/agent/src/harness/env/nodejs.ts`) |

Leftover sibling of the `agent_tool_loop` hole on `execution-env.lisp`.
Timed work is exists on missing/present paths, remove, force-remove missing,
recursive directory remove, and temp dir/file creation through
`call-signaled-operation` — not `execution-env-exec`. Staged cwd under harness
scratch only. Observed `ex_missing` / `ex_present` / `ex_after_rm` /
`tmp_dir` / `tmp_file` / `tmp_suffix` / `rm_force` / `rm_recursive` are exact.
First Friend-MachineD freeze **RATIO_PLACEHOLDER**. Gate used `--only-enforce`.
Same commit no optimize.

### Pair 391 — `execution_env` (absolute_path)

| metric | cadr | pi |
|---|---|---|
| `absolute_path` | `execution-env-absolute-path` (`src/cadr-agent/execution-env.lisp`) | `NodeExecutionEnv.absolutePath` / `resolvePath` (`packages/agent/src/harness/env/nodejs.ts`) |

Leftover sibling of Pair 257 `exists_remove_temps` on the same
`execution-env.lisp` `agent_tool_loop` hole. Timed work is resolving a
relative leaf, an absolute `/tmp` path, a `~/` home path, and a
`file://` URL — not exists/remove/temps, not join, not fileInfo, not
exec. Observed `ap_rel` / `ap_abs` / `ap_home` / `ap_file` / `ap_n` are
exact. First n=5 freeze **3.301×** (11.920 / 3.612 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old
holes `lc_n` / `lc_sleep` / help text; this metric did not fail). Same
commit no optimize. Pair numbers 328–330 belong to the in-flight
`file-mutation-queue.lisp` knife; this cut is 391–393 only. Booked in
`docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 392 — `execution_env` (join_path)

| metric | cadr | pi |
|---|---|---|
| `join_path` | `execution-env-join-path` (`src/cadr-agent/execution-env.lisp`) | `NodeExecutionEnv.joinPath` (`packages/agent/src/harness/env/nodejs.ts`) |

Leftover sibling of Pair 391 `absolute_path` on the same
`execution-env.lisp` hole. Timed work is joining relative `a`/`b` plus
an absolute `/tmp/goal20-jp-abs`/`x`/`y` — not absolutePath, not
fileInfo, not exists/remove. Observed `jp_rel` / `jp_abs` / `jp_n` are
exact. First n=5 freeze **10.091×** (9.267 / 0.918 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old
holes `lc_n` / `lc_sleep` / help text; this metric did not fail — variance
floor binds on a sub-µs pi median). Same commit no optimize. Booked in
`docs/benchmarks/goal20-paired-over-1x.md`.

### Pair 393 — `execution_env` (file_info)

| metric | cadr | pi |
|---|---|---|
| `file_info` | `execution-env-file-info` (`src/cadr-agent/execution-env.lisp`) | `NodeExecutionEnv.fileInfo` (`packages/agent/src/harness/env/nodejs.ts`) |

Leftover sibling of Pair 391 `absolute_path` and Pair 392 `join_path` on
the same `execution-env.lisp` hole. Timed work is `lstat` name/kind/size
of a staged `info.txt` — not write as the timed owner, not exists, not
listDir. Observed `fi_name` / `fi_kind` / `fi_size` / `fi_n` are exact.
First n=5 freeze **0.408×** (5.834 / 14.284 µs) on host `cursor`,
ceiling 8.0. Gate used `--only-enforce` (script rc=1 only from known old
holes `lc_n` / `lc_sleep` / help text; this metric did not fail). cadr
leads. Same commit no optimize.

### Pair 256 — `resource_loader` (dedupe_by_name)

| metric | cadr | pi |
|---|---|---|
| `dedupe_by_name` | `dedupe-resources-by-name` (`src/cadr-cli/resource-loader.lisp`) | project-before-user first-wins dedupe (`skills.ts` `skillMap`) |

Leftover sibling of the `resource_loader` hole. Same skill/prompt collision
fixture as `reload`: global + project `shared` skill and `review` prompt.
Load paths once outside the timed loop; time name dedupe only, not
`reload-resources` or `load-skills-at-paths`. Observed `dbn_skill_count` /
`dbn_skill_collisions` / `dbn_skill_project` / `dbn_prompt_count` /
`dbn_prompt_collisions` / `dbn_prompt_project` are exact. First Friend-MachineD
freeze **0.50×** (253.5 / 505.5 µs), ceiling 8.0. Gate used
`--only-enforce`. Same commit no optimize.

### Pair 253 — `settings_load` (config_paths)

| metric | cadr | pi |
|---|---|---|
| `config_paths` | `default-config-path` + `default-auth-path` | `getSettingsPath` + `getAuthPath` (`packages/coding-agent/src/config.ts`) |

Leftover sibling of the `settings_load` hole on `src/cadr-cli/config.lisp`.
Staged `CADR_CODING_AGENT_DIR` / `PI_CODING_AGENT_DIR` agent directory only;
no file reads. cadr resolves `config.json` + `auth.json`; pi resolves
`settings.json` + `auth.json` under the same agent dir. Observed
`cp_auth_eq` / `cp_cfg_eq` / `cp_same_p` / `cp_auth_leaf` / `cp_cfg_leaf`
are exact. First Friend-MachineD freeze **RATIO_PLACEHOLDER**. Gate used
`--only-enforce`. Same commit no optimize.

### Pair 253 — `agent_tool_loop` (runtime)

| metric | cadr | pi |
|---|---|---|
| `runtime` | `agent-steer` + `drain-agent-queue` + `clear-live-agent-queues` (`src/cadr-agent/runtime.lisp`) | `PendingMessageQueue` (`packages/agent/src/agent.ts`) |

Leftover sibling of the `agent_tool_loop` hole for `runtime.lisp`. Time
steering/follow-up queue enqueue, one-at-a-time vs `:all` drain, clear-live,
and snapshot only — not `agent-prompt`, not a live loop. Fixtures: steer
`a`/`b`, follow-up `c`/`d`, all-mode steer `x`/`y`, clear-live
`clear-me`/`clear-fu`. Do not exact `next-turn` queue (cadr-only). Observed
`rt_steer_len` / `rt_follow_len` / `rt_drain_steer_a` / `rt_drain_steer1_n` /
`rt_steer_remain1` / `rt_drain_steer_b` / `rt_steer_empty` /
`rt_drain_steer_all_n` / `rt_drain_follow_c` / `rt_follow_remain1` /
`rt_drain_follow_d` / `rt_follow_empty` / `rt_clear_steer_n` /
`rt_clear_follow_n` / `rt_snap_steer_empty` / `rt_snap_follow_empty` are exact.
First Friend-MachineD freeze **6.30×** (7.8 / 1.2 µs), ceiling 8.0. Gate used
`--only-enforce`. Same commit no optimize.

### Pair 255 — `session_compact` (branch_summarize)

| metric | cadr | pi |
|---|---|---|
| `branch_summarize` | `collect-entries-for-branch-summary` + `generate-branch-summary` (`src/cadr-agent/branch-summarization.lisp`) | `collectEntriesForBranchSummary` + `generateBranchSummary` (`packages/coding-agent/src/core/compaction/branch-summarization.ts`) |

Forked five-message tree (e1–e5, leaf e4, target e5). Collect e4→e5
yields e3,e4. Faux summarizer returns `"BRANCH SUMMARY"`. Timed work is
production collect + generate on an in-memory `SessionEntry[]` tree, not
`session_load`. Observed `summarized` / `entry_count` /
`branch_summary_chars` are exact. `session_compact.compact` stays on its own
thunk. First Friend-MachineD freeze **1.15×** (37.3 / 32.5 µs), ceiling 20.0.

### Pair 258 — `session_compact` (prepare_branch_entries)

| metric | cadr | pi |
|---|---|---|
| `prepare_branch_entries` | `prepare-branch-entries` (`src/cadr-agent/branch-summarization.lisp`) | `prepareBranchEntries` (`packages/coding-agent/src/core/compaction/branch-summarization.ts`) |

Leftover sibling of the `branch_summarize` pair on the same forked tree.
After `collect-entries-for-branch-summary` (e4→e5), time
`prepare-branch-entries` only with the same context-window/reserve token
budget encoding as `generate-branch-summary` — no summarization model call.
Observed `prepared` / `message_count` / `total_tokens` / `read_file_count` /
`modified_file_count` are exact. Gate used `--only-enforce`. Same commit no
optimize.

### Pair 254 — `agent_conditions` (error_probe)

| metric | cadr | pi |
|---|---|---|
| `error_probe` | `define-condition` slot accessors + `subtypep` (`src/cadr-agent/conditions.lisp`) | fixture-aligned agent error slot/type probe |

Leftover sibling of the `agent_conditions` hole. Time condition construction,
slot reads, hierarchy checks, and `handler-case`/`catch` only — not tool-loop
execution or settings I/O. Fixture slots: schema `edit`/`/edits`/`required`,
tool `bash`/`call-1`, session `/tmp/s.jsonl` line 12. Observed `ac_schema_tool`
/ `ac_schema_ptr` / `ac_schema_reason` / `ac_tool_name` / `ac_tool_id` /
`ac_sess_path` / `ac_sess_line` / `ac_sub_schema` / `ac_sub_tool` /
`ac_sub_ext_reg` / `ac_sub_ext_exec` / `ac_sub_stale` / `ac_sub_session` /
`ac_catch_busy` / `ac_catch_shutdown` / `ac_catch_turn` / `ac_catch_ext_reg` /
`ac_catch_ext_exec` / `ac_catch_stale` are exact. Gate used `--only-enforce`.
Same commit no optimize.

### Pair 240 — `cli_selectors` (scoped_models_selector_provider_count)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_provider_count` | `scoped-models-selector-provider-count` | provider-count helper |

Scoped models active-provider count (string digest). Observed `smsprv_all` /
`smsprv_partial` / `smsprv_unavail` / `smsprv_empty` / `smsprv_single` are exact.
First Friend-MachineD freeze **40.39×** (157.5 / 3.9 µs), ceiling 50.0 (bumped from
8.0 on first freeze 46.24×). Gate used `--only-enforce`. Same commit no optimize.

### Pair 239 — `cli_selectors` (scoped_models_selector_persist)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_persist` | `scoped-models-selector-persist` | `onPersist` callback |

Scoped models persist (enabled-ids|dirty|calls digest). Observed `smsper_all` /
`smsper_partial` / `smsper_no_cb` / `smsper_empty` / `smsper_two` / `smsper_single`
are exact. First Friend-MachineD freeze **13.58×** (208.1 / 15.3 µs), ceiling 25.0
(bumped from 8.0 on first freeze 20.35×). Gate used `--only-enforce`. Same commit
no optimize.

### Pair 238 — `cli_selectors` (scoped_models_selector_reorder)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_reorder` | `scoped-models-selector-reorder` | reorder up/down |

Scoped models enabled-list reorder (enabled-ids|dirty|selected digest). Observed
`smsror_down` / `smsror_up` / `smsror_noop` / `smsror_empty` / `smsror_filter` /
`smsror_miss` are exact. First Friend-MachineD freeze **3.42×** (287.2 / 84.0 µs),
ceiling 8.0. Gate used `--only-enforce`. Same commit no optimize.

### Pair 237 — `cli_selectors` (scoped_models_selector_clear_all)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_clear_all` | `scoped-models-selector-clear-all` | `clearAll` |

Scoped models clear-all (enabled-ids|dirty digest). Observed `smsca_all` /
`smsca_partial` / `smsca_empty` / `smsca_two` / `smsca_filter` / `smsca_miss`
are exact. First Friend-MachineD freeze **21.18×** (287.2 / 13.6 µs), ceiling
25.0 (bumped from 8.0 on first freeze 19.56×). Gate used `--only-enforce`. Same
commit no optimize.

### Pair 236 — `cli_selectors` (scoped_models_selector_toggle_provider)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_toggle_provider` | `scoped-models-selector-toggle-provider` | `toggleProvider` |

Scoped models toggle-provider (enabled-ids|dirty|selected digest). Observed
`smstgp_all_0` / `smstgp_partial_off` / `smstgp_partial_on` / `smstgp_retoggle` /
`smstgp_filter` / `smstgp_miss` are exact. First Friend-MachineD freeze **4.55×**
(303.9 / 66.8 µs), ceiling 8.0. Gate used `--only-enforce`. Same commit no optimize.

### Pair 235 — `cli_selectors` (scoped_models_selector_enable_all)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_enable_all` | `scoped-models-selector-enable-all` | `enableAll` |

Scoped models enable-all (enabled-ids|dirty digest). Observed `smsea_all` /
`smsea_partial` / `smsea_empty` / `smsea_two` / `smsea_filter` / `smsea_miss`
are exact. First Friend-MachineD freeze **20.77×** (384.3 / 18.5 µs), ceiling
25.0. Gate used `--only-enforce`. Same commit no optimize.

### Pair 234 — `cli_selectors` (scoped_models_selector_target_ids)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_target_ids` | `scoped-models-selector-target-ids` | `enableAll`/`clearAll` targetIds |

Scoped models enableAll/clearAll target id list (comma-joined qualified ids).
Observed `smsti_all` / `smsti_gpt` / `smsti_nope` / `smsti_claude` / `smsti_partial`
are exact. First Friend-MachineD freeze **5.27×** (240.6 / 45.7 µs), ceiling 8.0.
Gate used `--only-enforce`. Same commit no optimize.

### Pair 231 — `cli_selectors` (scoped_models_selector_toggle_selected)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_toggle_selected` | `scoped-models-selector-toggle-selected` | `handleInput` confirm toggle |

Scoped models confirm toggle (enabled-ids|dirty|selected digest). Observed
`smstg_all_0` / `smstg_partial_off` / `smstg_partial_on` / `smstg_retoggle` /
`smstg_filter` / `smstg_miss` are exact. First Friend-MachineD freeze **2.95×**
(247.0 / 83.7 µs), ceiling 8.0. Gate used `--only-enforce`. Same commit no
optimize.

### Pair 230 — `cli_selectors` (scoped_models_selector_ui_state)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_ui_state` | `render-scoped-models-selector` | `updateList` / render |

Model selector raw key dispatch (action|model-id|selected|consumed digest).
Observed `mshri_down` / `mshri_j` / `mshri_esc` / `mshri_bad` / `mshri_o` /
`mshri_confirm` / `mshri_up` are exact. First Friend-MachineD freeze **7.08×**
(823.0 / 116.3 µs), ceiling 8.0. Gate used `--only-enforce`. Same commit no
optimize.

Model selector query update (count|selected digest). Observed `mssq_clear` /
`mssq_gpt` / `mssq_same` / `mssq_reset` / `mssq_miss` are exact. First
Friend-MachineD freeze **3.85×** (148.5 / 38.6 µs), ceiling 8.0. Gate used
`--only-enforce`. Same commit no optimize.

Model selector selected model (qualified-model-id digest). Observed `mssm_0` /
`mssm_1` / `mssm_3` / `mssm_gpt0` / `mssm_gpt2` / `mssm_miss` / `mssm_oob` are
exact. First Friend-MachineD freeze **7.90×** (160.3 / 20.3 µs), ceiling 12.0
(bumped from 8.0 on first freeze 9.75×). Gate used `--only-enforce`. Same commit
no optimize.

Model selector scope toggle (scope|count|selected digest). Observed `msts_all` /
`msts_scoped` / `msts_gpt` / `msts_none` / `msts_anth` are exact. First
Friend-MachineD freeze **5.45×** (141.1 / 25.9 µs), ceiling 8.0. Gate used
`--only-enforce`. Same commit no optimize.

Model selector UI render (scope|width|selected|query|total|scroll|items|empty|
footer digest). Observed `msui_default` / `msui_sel2` / `msui_scoped` /
`msui_filter` / `msui_miss` / `msui_error` / `msui_refresh` are exact. First
Friend-MachineD freeze **21.70×** (648.3 / 29.9 µs), ceiling 35.0. Gate used
`--only-enforce`. Same commit no optimize.

Scoped models selector query update (count|selected digest). Observed `smssq_clear` /
`smssq_gpt` / `smssq_same` / `smssq_reset` / `smssq_miss` are exact. First
Friend-MachineD freeze **6.80×** (272.7 / 40.1 µs), ceiling 8.0. Gate used
`--only-enforce`. Same commit no optimize.

### Pair 228 — `cli_selectors` (scoped_models_selector_handle_event)

| metric | cadr | pi |
|---|---|---|
| `scoped_models_selector_handle_event` | `scoped-models-selector-handle-event` | event dispatch |

Scoped models selector input events (action\|null\|selected digest). Observed
`smshe_down` / `smshe_up` / `smshe_enter` / `smshe_esc` / `smshe_text` / `smshe_bs`
are exact. First Friend-MachineD freeze **6.76×** (246.1 / 36.4 µs), ceiling 12.0
(bumped from 8.0 on first freeze 10.40×). Gate used `--only-enforce`. Same commit
no optimize.
Scoped models selector raw key dispatch (action|value|selected|consumed digest).
Observed `smsri_down` / `smsri_j` / `smsri_esc` / `smsri_bad` / `smsri_o` /
`smsri_confirm` / `smsri_up` are exact. First Friend-MachineD freeze **9.03×**
(1638.3 / 181.4 µs), ceiling 8.0. Gate used `--only-enforce`. Same commit no
optimize.
Scoped models selector UI render (scope|width|selected|query|total|scroll|items|
empty|footer digest). Observed `smsui_default` / `smsui_sel2` / `smsui_partial` /
`smsui_filter` / `smsui_miss` / `smsui_refresh` / `smsui_dirty` are exact. First
Friend-MachineD freeze **33.04×** (1,636.7 / 49.5 µs), ceiling 35.0. Gate used
`--only-enforce`. Same commit no optimize.

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

Denominator: **297 files / 130,760 lines**
(same Part I lock: `src/**/*.lisp`, `wc -l`).

| class | files | lines | share of lines | Part K / P.13 |
|---|---:|---:|---:|---|
| `paired` | 244 | 105,727 | 80.9% | `no worse than baseline` is falsifiable |
| `unpairable` | 24 | 7,561 | 5.8% | single reference vs previous cadr |
| `covered-as-callee` | 29 | 17,472 | 13.4% | on a named paired thunk; no own bench |
| `needs-pair` | 0 | 0 | 0.0% | must get an H pair; not a file-level idle bench |
| `pairable-uncovered` | 0 | 0 | 0.0% | P.13 requires 0% |

- **Falsifiable vs baseline:** 80.9% of lines (244 files). This is the share whose `no worse than baseline` claim is a measured pair.
- **K-advanceable** (paired ∪ unpairable): 86.6% of lines.
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
| `src/cadr-agent/branch-summarization.lisp` | 184 | `session_compact.branch_summarize`, `session_compact.prepare_branch_entries` |
| `src/cadr-agent/compaction.lisp` | 943 | `session_compact.compact` |
| `src/cadr-agent/conditions.lisp` | 43 | `agent_conditions.error_probe` |
| `src/cadr-agent/execution-env.lisp` | 878 | `execution_env.exists_remove_temps`, `execution_env.absolute_path`, `execution_env.join_path`, `execution_env.file_info` |
| `src/cadr-agent/file-mutation-queue.lisp` | 92 | `file_mutation_queue.with_queue`, `file_mutation_queue.queue_key`, `file_mutation_queue.lock`, `file_mutation_queue.register`, `file_mutation_queue.wait_turn`, `file_mutation_queue.release_turn`, `file_mutation_queue.ensure_state`, `file_mutation_queue.call_with`, `file_mutation_queue.make_state`, `file_mutation_queue.state_key`, `file_mutation_queue.pending_count`, `file_mutation_queue.next_ticket`, `file_mutation_queue.serving_ticket`, `file_mutation_queue.waitqueue`, `file_mutation_queue.registry`, `file_mutation_queue.state_p` |
| `src/cadr-agent/harness-events.lisp` | 75 | `harness_events.emit`, `harness_events.on`, `harness_events.watch`, `harness_events.make_start`, `harness_events.make_end`, `harness_events.event_type`, `harness_events.make_bus` |
| `src/cadr-agent/loop/agent-loop.lisp` | 453 | `agent_tool_loop.roundtrip` |
| `src/cadr-agent/loop/events.lisp` | 169 | `agent_tool_loop.roundtrip` |
| `src/cadr-agent/loop/tool-execution.lisp` | 489 | `agent_tool_loop.roundtrip` |
| `src/cadr-agent/loop/turns.lisp` | 401 | `agent_tool_loop.roundtrip` |
| `src/cadr-agent/messages.lisp` | 253 | `session_compact.compact` |
| `src/cadr-agent/proxy.lisp` | 251 | `agent_proxy.stream_roundtrip` |
| `src/cadr-agent/resources.lisp` | 739 | `resource_loader.reload` |
| `src/cadr-agent/runtime.lisp` | 421 | `agent_tool_loop.runtime` |
| `src/cadr-agent/schema.lisp` | 850 | `agent_schema.validate_ok_fail` |
| `src/cadr-agent/session/codec.lisp` | 1,152 | `storage_journal.journal_read`, `storage_journal.journal_append` |
| `src/cadr-agent/session/discovery.lisp` | 483 | `session_discovery.header_probe`, `session_discovery.session_list_probe` |
| `src/cadr-agent/session/export-html.lisp` | 484 | `session_export_html.to_html` |
| `src/cadr-agent/session/journal.lisp` | 683 | `session_pipeline.context_walk`, `storage_journal.journal_append` |
| `src/cadr-agent/session/migration.lisp` | 2,537 | `session_pipeline.session_load`, `storage_journal.journal_read` |
| `src/cadr-agent/sqlite-storage.lisp` | 839 | `sqlite_session.open_walk` |
| `src/cadr-agent/storage/harness.lisp` | 476 | `harness_storage.open_walk` |
| `src/cadr-agent/storage/jsonl.lisp` | 537 | `harness_storage.open_walk` |
| `src/cadr-agent/storage/memory.lisp` | 378 | `harness_storage.open_walk` |
| `src/cadr-agent/storage/protocol.lisp` | 142 | `harness_storage.open_walk` |
| `src/cadr-agent/summarization.lisp` | 86 | `session_compact.compact` |
| `src/cadr-agent/tool.lisp` | 319 | `agent_tool_loop.roundtrip` |
| `src/cadr-agent/truncate.lisp` | 806 | `text_truncation.truncate_head`, `text_truncation.truncate_tail` |
| `src/cadr-ai/auth.lisp` | 207 | `oauth_pkce_device.auth_json` |
| `src/cadr-ai/auth/bedrock.lisp` | 220 | `provider_bedrock.stream_roundtrip` |
| `src/cadr-ai/auth/device-code.lisp` | 239 | `oauth_pkce_device.poll` |
| `src/cadr-ai/auth/github-copilot.lisp` | 53 | `oauth_pkce_device.copilot_url` |
| `src/cadr-ai/auth/radius-cloudflare.lisp` | 191 | `oauth_pkce_device.cloudflare_url` |
| `src/cadr-ai/auth/vertex.lisp` | 212 | `provider_vertex.stream_roundtrip` |
| `src/cadr-ai/capabilities/event-stream.lisp` | 69 | `ai_capabilities.event_stream` |
| `src/cadr-ai/capabilities/grammar-tools.lisp` | 292 | `ai_capabilities.deferred_tools` |
| `src/cadr-ai/capabilities/image-runtime.lisp` | 117 | `image_runtime.api_provider` |
| `src/cadr-ai/capabilities/proxy-config.lisp` | 77 | `ai_capabilities.http_proxy` |
| `src/cadr-ai/capabilities/session-resources.lisp` | 34 | `ai_capabilities.session_resources` |
| `src/cadr-ai/capabilities/streaming-json.lisp` | 170 | `ai_capabilities.short_hash` |
| `src/cadr-ai/crypto.lisp` | 367 | `ai_crypto.hmac` |
| `src/cadr-ai/image-models.generated.lisp` | 185 | `image_runtime.lookup` |
| `src/cadr-ai/images.lisp` | 222 | `image_runtime.output_modalities`, `image_runtime.openrouter_content`, `image_runtime.parse_data_image`, `image_runtime.openrouter_usage`, `image_runtime.parse_openrouter_images`, `image_runtime.error_result` |
| `src/cadr-ai/json.lisp` | 1,920 | `provider_stream.stream_roundtrip`, `storage_journal.journal_read`, `storage_journal.journal_append`, `session_pipeline.session_load` |
| `src/cadr-ai/model-data.lisp` | 431 | `ai_crypto_model_data.manifest` |
| `src/cadr-ai/oauth/callback.lisp` | 324 | `oauth_pkce_device.hex_value`, `oauth_pkce_device.http_status_text`, `oauth_pkce_device.parse_authorization_input`, `oauth_pkce_device.parse_callback_request`, `oauth_pkce_device.parse_query`, `oauth_pkce_device.percent_decode`, `oauth_pkce_device.present_auth_url`, `oauth_pkce_device.provider_key`, `oauth_pkce_device.write_http_response` |
| `src/cadr-ai/oauth/openai-anthropic.lisp` | 333 | `oauth_pkce_device.base64url_value`, `oauth_pkce_device.base64url_decode`, `oauth_pkce_device.account_id`, `oauth_pkce_device.token_fields`, `oauth_pkce_device.openai_exchange`, `oauth_pkce_device.anthropic_exchange` |
| `src/cadr-ai/oauth/pkce.lisp` | 322 | `oauth_pkce.challenge_urls` |
| `src/cadr-ai/oauth/providers/anthropic.lisp` | 16 | `oauth_pkce_device.anth_oauth_name`, `oauth_pkce_device.anth_oauth_sub`, `oauth_pkce_device.anth_oauth_instructions` |
| `src/cadr-ai/oauth/providers/github-copilot.lisp` | 174 | `oauth_pkce_device.copilot_auth`, `oauth_pkce_device.github_domain`, `oauth_pkce_device.github_oauth_url`, `oauth_pkce_device.github_request_headers` |
| `src/cadr-ai/oauth/providers/kimi.lisp` | 58 | `oauth_pkce_device.kimi_host_default`, `oauth_pkce_device.kimi_host_code`, `oauth_pkce_device.kimi_host_trim` |
| `src/cadr-ai/oauth/providers/openai-device.lisp` | 199 | `oauth_pkce_device.json_copy`, `oauth_pkce_device.interval_seconds`, `oauth_pkce_device.device_start` |
| `src/cadr-ai/oauth/providers/openrouter.lisp` | 89 | `oauth_pkce_device.openrouter_input`, `oauth_pkce_device.openrouter_refresh`, `oauth_pkce_device.openrouter_exchange`, `oauth_pkce_device.openrouter_login`, `oauth_pkce_device.openrouter_login_fail`, `oauth_pkce_device.openrouter_login_miss` |
| `src/cadr-ai/oauth/providers/radius.lisp` | 116 | `oauth_pkce_device.radius_gateway` |
| `src/cadr-ai/oauth/providers/xai.lisp` | 184 | `oauth_pkce_device.error_detail`, `oauth_pkce_device.ensure_success`, `oauth_pkce_device.notify_device`, `oauth_pkce_device.xai_login`, `oauth_pkce_device.xai_login_fail`, `oauth_pkce_device.xai_refresh` |
| `src/cadr-ai/provider.lisp` | 799 | `provider_stream.stream_roundtrip` |
| `src/cadr-ai/providers/anthropic.lisp` | 644 | `provider_anthropic.stream_roundtrip` |
| `src/cadr-ai/providers/azure-openai.lisp` | 223 | `provider_azure_openai.stream_roundtrip` |
| `src/cadr-ai/providers/bedrock.lisp` | 934 | `provider_bedrock.stream_roundtrip` |
| `src/cadr-ai/providers/codex.lisp` | 35 | `provider_codex.stream_roundtrip` |
| `src/cadr-ai/providers/definitions.lisp` | 1,091 | `provider_registry_defs.lookup` |
| `src/cadr-ai/providers/google.lisp` | 471 | `provider_google.stream_roundtrip` |
| `src/cadr-ai/providers/mistral.lisp` | 97 | `provider_mistral.stream_roundtrip` |
| `src/cadr-ai/providers/openai-completions.lisp` | 883 | `provider_stream.stream_roundtrip` |
| `src/cadr-ai/providers/openai.lisp` | 828 | `provider_openai_responses.stream_roundtrip` |
| `src/cadr-ai/providers/pi-messages.lisp` | 255 | `provider_pi_messages.stream_roundtrip` |
| `src/cadr-ai/providers/registry.lisp` | 157 | `provider_registry_defs.protocol_provider`, `provider_registry_defs.protocol_provider_anthropic`, `provider_registry_defs.instantiate_provider` |
| `src/cadr-ai/providers/runtime-projection.lisp` | 297 | `provider_registry_defs.api_key_auth`, `provider_registry_defs.api_key_login_function`, `provider_registry_defs.api_key_strategy`, `provider_registry_defs.merge_environment`, `provider_registry_defs.model_filter_function`, `provider_registry_defs.oauth_login_function`, `provider_registry_defs.oauth_refresh_function`, `provider_registry_defs.oauth_to_auth`, `provider_registry_defs.provider_options`, `provider_registry_defs.runtime_models`, `provider_registry_defs.strip_runtime_options`, `provider_registry_defs.structured_api_key_login`, `provider_registry_defs.runtime_provider`, `provider_registry_defs.runtime_provider_copilot`, `provider_registry_defs.models_runtime` |
| `src/cadr-ai/providers/vertex.lisp` | 134 | `provider_vertex.stream_roundtrip` |
| `src/cadr-ai/runtime/faux-provider.lisp` | 609 | `ai_runtime_faux.blocks` |
| `src/cadr-ai/sse.lisp` | 267 | `provider_stream.stream_roundtrip` |
| `src/cadr-ai/support/grammar-coercion.lisp` | 279 | `ai_support.grammar_delta` |
| `src/cadr-ai/support/overflow.lisp` | 78 | `ai_support.context_overflow` |
| `src/cadr-ai/support/release.lisp` | 111 | `ai_support.auth_guidance` |
| `src/cadr-ai/support/threads.lisp` | 6 | `ai_support.threads_absent`, `ai_support.threads_current`, `ai_support.threads_joined` |
| `src/cadr-ai/support/token-estimation.lisp` | 170 | `ai_support.estimate_text` |
| `src/cadr-ai/support/uuid.lisp` | 93 | `ai_support.uuid_v7` |
| `src/cadr-ai/transport/aws-event-stream.lisp` | 222 | `provider_bedrock.stream_roundtrip` |
| `src/cadr-ai/transport/http.lisp` | 858 | `http_transport.parse_url` |
| `src/cadr-ai/websocket.lisp` | 628 | `websocket_stream.stream_roundtrip` |
| `src/cadr-cli/arguments.lisp` | 1,036 | `cli_dispatch.argv_parse`, `cli_dispatch.help_render` |
| `src/cadr-cli/bootstrap/auth.lisp` | 172 | `cli_bootstrap_sessions.bootstrap_auth` |
| `src/cadr-cli/bootstrap/commands.lisp` | 2,661 | `cli_bootstrap_sessions.cycle_wrap`, `cli_bootstrap_sessions.file_tags`, `cli_bootstrap_sessions.scope_hint` |
| `src/cadr-cli/bootstrap/main.lisp` | 409 | `cli_dispatch.list_models_render` |
| `src/cadr-cli/bootstrap/sessions.lisp` | 1,999 | `cli_bootstrap_sessions.assistant_tool_call_only`, `cli_bootstrap_sessions.last_assistant_text`, `cli_bootstrap_sessions.path_argument`, `cli_bootstrap_sessions.session_compaction_status`, `cli_bootstrap_sessions.session_entry_user_text`, `cli_bootstrap_sessions.session_export_basename`, `cli_bootstrap_sessions.session_path`, `cli_bootstrap_sessions.session_user_messages_for_forking`, `cli_bootstrap_sessions.session_command_stats`, `cli_bootstrap_sessions.session_usage_breakdown`, `cli_bootstrap_sessions.session_tree_label_timestamps`, `cli_bootstrap_sessions.session_tree_tool_calls`, `cli_bootstrap_sessions.session_compaction_display_state`, `cli_bootstrap_sessions.write_hotkeys_command`, `cli_bootstrap_sessions.find_session_by_id_or_prefix`, `cli_bootstrap_sessions.session_display_messages`, `cli_bootstrap_sessions.session_tree_selector_data`, `cli_bootstrap_sessions.validate_cli_session_flags`, `cli_bootstrap_sessions.session_entry_tree_selector_data`, `cli_bootstrap_sessions.session_restored_model`, `cli_bootstrap_sessions.split_command`, `cli_bootstrap_sessions.cli_platform`, `cli_bootstrap_sessions.session_info_style`, `cli_bootstrap_sessions.default_changelog_path` |
| `src/cadr-cli/bootstrap/settings.lisp` | 957 | `settings_load.http_idle` |
| `src/cadr-cli/bootstrap/tools.lisp` | 91 | `cli_bootstrap_sessions.coding_tools` |
| `src/cadr-cli/config.lisp` | 284 | `settings_load.config_paths`, `settings_load.configured_provider_name`, `settings_load.environment_value`, `settings_load.oauth_login_function`, `settings_load.oauth_refresh_function`, `settings_load.parse_auth_provider`, `settings_load.provider_default_model`, `settings_load.provider_settings`, `settings_load.provider_symbol`, `settings_load.split_command_line`, `settings_load.stored_auth_secrets`, `settings_load.read_cli_config`, `settings_load.provider_config_secrets`, `settings_load.resolve_provider_config` |
| `src/cadr-cli/extensions/commands.lisp` | 56 | `cli_extensions_install.handle_plain`, `cli_extensions_install.handle_unknown`, `cli_extensions_install.split_command` |
| `src/cadr-cli/extensions/discovery.lisp` | 212 | `cli_extensions_install.extension_discovery` |
| `src/cadr-cli/extensions/installer.lisp` | 209 | `cli_extensions_install.unsafe_git`, `cli_extensions_install.git_path`, `cli_extensions_install.normalize_git`, `cli_extensions_install.string_prefix`, `cli_extensions_install.split_path_segments`, `cli_extensions_install.strip_git_query` |
| `src/cadr-cli/extensions/llama/client.lisp` | 485 | `cli_extensions_install.llama_url` |
| `src/cadr-cli/extensions/llama/extension.lisp` | 470 | `cli_extensions_install.catalog_notify`, `cli_extensions_install.gated_approval`, `cli_extensions_install.loaded_model`, `cli_extensions_install.progress_notify`, `cli_extensions_install.quant_label`, `cli_extensions_install.split_args` |
| `src/cadr-cli/extensions/llama/huggingface.lisp` | 290 | `cli_extensions_install.hf_token` |
| `src/cadr-cli/extensions/llama/provider.lisp` | 337 | `cli_extensions_install.llama_catalog` |
| `src/cadr-cli/extensions/llama/ui.lisp` | 763 | `cli_extensions_install.llama_context_label`, `cli_extensions_install.llama_model_description`, `cli_extensions_install.llama_compact_count`, `cli_extensions_install.llama_format_context`, `cli_extensions_install.llama_js_to_fixed`, `cli_extensions_install.llama_search_exact`, `cli_extensions_install.llama_search_status`, `cli_extensions_install.llama_search_filter`, `cli_extensions_install.llama_view_width` |
| `src/cadr-cli/extensions/loader.lisp` | 702 | `cli_extensions_install.http_timeout_p`, `cli_extensions_install.inline_factory`, `cli_extensions_install.local_system_name`, `cli_extensions_install.manager_notify`, `cli_extensions_install.output_boundary`, `cli_extensions_install.package_fragment`, `cli_extensions_install.quiet_manager`, `cli_extensions_install.same_source`, `cli_extensions_install.startup_issues` |
| `src/cadr-cli/interactive/autocomplete.lisp` | 332 | `cli_interactive_controller.auth_type` |
| `src/cadr-cli/interactive/clipboard.lisp` | 449 | `cli_interactive_controller.wayland` |
| `src/cadr-cli/interactive/components/announcement.lisp` | 41 | `cli_interactive_controller.announcement_make`, `cli_interactive_controller.announcement_url`, `cli_interactive_controller.announcement_title` |
| `src/cadr-cli/interactive/components/armin.lisp` | 294 | `cli_selectors.armin_cell`, `cli_selectors.armin_copy_cell`, `cli_selectors.armin_copy_grid`, `cli_selectors.armin_copy_row`, `cli_selectors.armin_grid_height`, `cli_selectors.armin_make_grid`, `cli_selectors.armin_pixel`, `cli_selectors.armin_rotate_row`, `cli_selectors.armin_row_string` |
| `src/cadr-cli/interactive/components/countdown.lisp` | 90 | `cli_selectors.countdown_dispose`, `cli_selectors.countdown_render`, `cli_selectors.countdown_seconds`, `cli_selectors.countdown_start_guard`, `cli_selectors.countdown_tick`, `cli_selectors.countdown_unstarted` |
| `src/cadr-cli/interactive/components/daxnuts.lisp` | 185 | `cli_selectors.daxnuts_component_tick`, `cli_selectors.daxnuts_dispose`, `cli_selectors.daxnuts_invalidate`, `cli_selectors.daxnuts_render`, `cli_selectors.daxnuts_rgb_at`, `cli_selectors.make_daxnuts_component` |
| `src/cadr-cli/interactive/components/loaders.lisp` | 197 | `cli_selectors.key_text` |
| `src/cadr-cli/interactive/controller.lisp` | 2,999 | `cli_interactive_controller.make_notification_stream`, `cli_interactive_controller.notification_stream_flush`, `cli_interactive_controller.route_tui_submission`, `cli_interactive_controller.should_use_tui`, `cli_interactive_controller.terminal_title_sequence`, `cli_interactive_controller.tui_command_error` |
| `src/cadr-cli/interactive/entries.lisp` | 918 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-cli/interactive/extension-ui.lisp` | 756 | `cli_interactive_controller.extension_custom_ui_handle_event`, `cli_interactive_controller.extension_dialog_chrome`, `cli_interactive_controller.extension_host_turn`, `cli_interactive_controller.extension_render_value_lines`, `cli_interactive_controller.framed_select_state_handle_event`, `cli_interactive_controller.framed_select_state_handle_raw_input`, `cli_interactive_controller.make_extension_editor_dialog`, `cli_interactive_controller.make_extension_input_dialog`, `cli_interactive_controller.make_framed_select_state`, `cli_interactive_controller.make_runtime_auth_input_state`, `cli_interactive_controller.note_component_render_channel`, `cli_interactive_controller.render_extension_custom_entry`, `cli_interactive_controller.render_extension_custom_ui`, `cli_interactive_controller.render_framed_select_state`, `cli_interactive_controller.render_runtime_auth_input`, `cli_interactive_controller.render_tui_extension_overlay`, `cli_interactive_controller.runtime_auth_input_handle_event`, `cli_interactive_controller.tui_component_protocol`, `cli_interactive_controller.tui_extension_theme_runtime`, `cli_interactive_controller.tui_input_thread`, `cli_interactive_controller.wrap_extension_host_turn` |
| `src/cadr-cli/interactive/footer.lisp` | 536 | `cli_interactive_controller.cwd_footer` |
| `src/cadr-cli/interactive/frame.lisp` | 234 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-cli/interactive/images.lisp` | 290 | `image_runtime.dimension_note` |
| `src/cadr-cli/interactive/selectors/auth.lisp` | 720 | `cli_selectors.api_key_input_state_handle_event`, `cli_selectors.api_key_input_ui_state`, `cli_selectors.credential_entry_auth_type`, `cli_selectors.login_auth_type_route`, `cli_selectors.login_method_selector_handle_event`, `cli_selectors.login_method_selector_ui_state`, `cli_selectors.login_provider_options`, `cli_selectors.logout_provider_options`, `cli_selectors.make_api_key_input_state`, `cli_selectors.make_login_method_selector_state`, `cli_selectors.make_oauth_selector_state`, `cli_selectors.oauth_environment_source_p`, `cli_selectors.oauth_option_status_label`, `cli_selectors.oauth_option_status_rendered`, `cli_selectors.oauth_selector_apply_filter`, `cli_selectors.oauth_selector_handle_event`, `cli_selectors.oauth_selector_handle_raw_input`, `cli_selectors.oauth_selector_move`, `cli_selectors.oauth_selector_search_text`, `cli_selectors.oauth_selector_selection`, `cli_selectors.oauth_selector_ui_state` |
| `src/cadr-cli/interactive/selectors/common.lisp` | 402 | `cli_selectors.fuzzy_filter`, `cli_selectors.delete_query`, `cli_selectors.visible_slice`, `cli_selectors.move_index` |
| `src/cadr-cli/interactive/selectors/fork.lisp` | 199 | `cli_selectors.render_user_message_selector`, `cli_selectors.user_message_handle_event`, `cli_selectors.user_message_handle_raw`, `cli_selectors.user_message_make`, `cli_selectors.user_message_move`, `cli_selectors.user_message_selection` |
| `src/cadr-cli/interactive/selectors/login-dialog.lisp` | 279 | `cli_selectors.dlg_auth`, `cli_selectors.dlg_dev`, `cli_selectors.dlg_make`, `cli_selectors.login_dialog_complete_input`, `cli_selectors.login_dialog_handle_event`, `cli_selectors.login_dialog_show_details`, `cli_selectors.login_dialog_show_info`, `cli_selectors.login_dialog_show_manual_input`, `cli_selectors.login_dialog_show_progress`, `cli_selectors.login_dialog_show_prompt`, `cli_selectors.login_dialog_show_waiting`, `cli_selectors.render_login_dialog` |
| `src/cadr-cli/interactive/selectors/models.lisp` | 1,449 | `cli_selectors.all_known_model_ids_enabled_p`, `cli_selectors.make_model_selector_state`, `cli_selectors.make_models_selector_keybindings`, `cli_selectors.make_scoped_models_selector_state`, `cli_selectors.model_equal_p`, `cli_selectors.model_selector_active_models`, `cli_selectors.model_selector_apply_filter`, `cli_selectors.model_selector_clamp_selected`, `cli_selectors.model_selector_filter_search_text`, `cli_selectors.model_selector_finish_refresh`, `cli_selectors.model_selector_handle_event`, `cli_selectors.model_selector_handle_raw_input`, `cli_selectors.model_selector_key_p`, `cli_selectors.model_selector_keybindings`, `cli_selectors.model_selector_move`, `cli_selectors.model_selector_provider_badge`, `cli_selectors.model_selector_rebuild_search_text_table`, `cli_selectors.model_selector_search_text`, `cli_selectors.model_selector_select_current`, `cli_selectors.model_selector_selected_model`, `cli_selectors.model_selector_set_query`, `cli_selectors.model_selector_toggle_scope`, `cli_selectors.model_selector_ui_state`, `cli_selectors.model_selector_visible_models`, `cli_selectors.model_selector_visible_slice`, `cli_selectors.move_list_item`, `cli_selectors.qualified_model_id`, `cli_selectors.render_model_selector`, `cli_selectors.scoped_model_id_enabled_p`, `cli_selectors.scoped_model_item_search_text`, `cli_selectors.scoped_model_selector_search_text`, `cli_selectors.scoped_models_binding_label`, `cli_selectors.scoped_models_clear_ids`, `cli_selectors.scoped_models_copy_enabled`, `cli_selectors.scoped_models_enable_ids`, `cli_selectors.scoped_models_enabled_set`, `cli_selectors.scoped_models_model_by_id`, `cli_selectors.scoped_models_selector_apply_filter`, `cli_selectors.scoped_models_selector_cancel`, `cli_selectors.scoped_models_selector_clamp_selected`, `cli_selectors.scoped_models_selector_clear_all`, `cli_selectors.scoped_models_selector_counts`, `cli_selectors.scoped_models_selector_enable_all`, `cli_selectors.scoped_models_selector_finish_refresh`, `cli_selectors.scoped_models_selector_handle_event`, `cli_selectors.scoped_models_selector_handle_raw_input`, `cli_selectors.scoped_models_selector_items`, `cli_selectors.scoped_models_selector_key_p`, `cli_selectors.scoped_models_selector_mark_changed`, `cli_selectors.scoped_models_selector_move`, `cli_selectors.scoped_models_selector_notify_change`, `cli_selectors.scoped_models_selector_persist`, `cli_selectors.scoped_models_selector_rebuild_items`, `cli_selectors.scoped_models_selector_rebuild_models_by_id`, `cli_selectors.scoped_models_selector_refresh_items`, `cli_selectors.scoped_models_selector_reorder`, `cli_selectors.scoped_models_selector_select_id`, `cli_selectors.scoped_models_selector_selected_item`, `cli_selectors.scoped_models_selector_set_query`, `cli_selectors.scoped_models_selector_sorted_ids`, `cli_selectors.scoped_models_selector_target_ids`, `cli_selectors.scoped_models_selector_toggle_provider`, `cli_selectors.scoped_models_selector_toggle_selected`, `cli_selectors.scoped_models_selector_ui_state`, `cli_selectors.scoped_models_selector_visible_items`, `cli_selectors.scoped_models_toggle_id`, `cli_selectors.session_scoped_models`, `cli_selectors.sort_model_selector_models` |
| `src/cadr-cli/interactive/selectors/sessions.lisp` | 1,526 | `cli_selectors.session_search`, `cli_selectors.session_format_age`, `cli_selectors.session_record_label`, `cli_selectors.session_shorten_path`, `cli_selectors.session_quoted_search`, `cli_selectors.session_thread_records`, `cli_selectors.session_binding_label`, `cli_selectors.session_same_path`, `cli_selectors.session_quoted_p`, `cli_selectors.session_named_p` |
| `src/cadr-cli/interactive/selectors/settings.lisp` | 1,043 | `cli_selectors.settings_thinking_description`, `cli_selectors.settings_display_value`, `cli_selectors.settings_automatic_theme_setting`, `cli_selectors.settings_active_automatic_theme`, `cli_selectors.settings_cycle`, `cli_selectors.settings_apply_filter` |
| `src/cadr-cli/interactive/selectors/thinking.lisp` | 381 | `cli_selectors.make_thinking_selector_state`, `cli_selectors.render_thinking_selector`, `cli_selectors.thinking_level_description_line`, `cli_selectors.thinking_level_label`, `cli_selectors.thinking_level_search_text`, `cli_selectors.thinking_selector_apply_filter`, `cli_selectors.thinking_selector_clamp_selected`, `cli_selectors.thinking_selector_handle_event`, `cli_selectors.thinking_selector_handle_raw_input`, `cli_selectors.thinking_selector_key_p`, `cli_selectors.thinking_selector_keybindings`, `cli_selectors.thinking_selector_move`, `cli_selectors.thinking_selector_select_current`, `cli_selectors.thinking_selector_selected_level`, `cli_selectors.thinking_selector_set_query` |
| `src/cadr-cli/interactive/selectors/tree.lisp` | 1,931 | `cli_selectors.tree_entry_filtered` |
| `src/cadr-cli/interactive/selectors/trust.lisp` | 293 | `cli_selectors.make_trust_selector_state`, `cli_selectors.project_trust_options`, `cli_selectors.render_trust_selector`, `cli_selectors.trust_decision_description`, `cli_selectors.trust_option_saved_p`, `cli_selectors.trust_selector_handle_event`, `cli_selectors.trust_selector_handle_raw_input`, `cli_selectors.trust_selector_move`, `cli_selectors.trust_selector_selection`, `cli_selectors.trust_selector_ui_state` |
| `src/cadr-cli/interactive/state.lisp` | 303 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-cli/interactive/status.lisp` | 445 | `goal11.continuous_alt_input` |
| `src/cadr-cli/interactive/syntax.lisp` | 1,089 | `cli_interactive_controller.decode_entity` |
| `src/cadr-cli/interactive/theme.lisp` | 215 | `cli_interactive_controller.parse_auto_theme`, `cli_interactive_controller.resolve_theme` |
| `src/cadr-cli/interactive/themes.lisp` | 415 | `cli_interactive_controller.apply_tui_theme_summary`, `cli_interactive_controller.load_tui_theme_file`, `cli_interactive_controller.theme_object_overrides`, `cli_interactive_controller.theme_get`, `cli_interactive_controller.theme_kind`, `cli_interactive_controller.theme_ok`, `cli_interactive_controller.theme_prim`, `cli_interactive_controller.theme_res`, `cli_interactive_controller.theme_val` |
| `src/cadr-cli/interactive/tool-render-session.lisp` | 61 | `cli_interactive_controller.sess_draw`, `cli_interactive_controller.sess_make`, `cli_interactive_controller.sess_new`, `cli_interactive_controller.sess_out`, `cli_interactive_controller.sess_set`, `cli_interactive_controller.sess_upd` |
| `src/cadr-cli/interactive/tool-rendering.lisp` | 1,027 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-cli/interactive/transcript.lisp` | 1,070 | `cli_interactive_controller.accumulate_usage`, `cli_interactive_controller.append_user_message`, `cli_interactive_controller.assistant_display_blocks`, `cli_interactive_controller.assistant_has_tools`, `cli_interactive_controller.assistant_price_known`, `cli_interactive_controller.assistant_stop_error`, `cli_interactive_controller.cache_ok`, `cli_interactive_controller.cache_p`, `cli_interactive_controller.pad_sp`, `cli_interactive_controller.pad_str`, `cli_interactive_controller.render_assistant_blocks`, `cli_interactive_controller.render_assistant_lines`, `cli_interactive_controller.render_package_notification`, `cli_interactive_controller.render_transcript_summary`, `cli_interactive_controller.render_tui_entries`, `cli_interactive_controller.render_tui_entry`, `cli_interactive_controller.render_tui_entry_uncached`, `cli_interactive_controller.render_user_lines`, `cli_interactive_controller.render_version_notification`, `cli_interactive_controller.reset_tui_messages`, `cli_interactive_controller.seed_tui_message`, `cli_interactive_controller.syntax_highlight`, `cli_interactive_controller.theme_message_background`, `cli_interactive_controller.transcript_summary_label`, `cli_interactive_controller.transcript_summary_text`, `cli_interactive_controller.transform_tui_markdown`, `cli_interactive_controller.update_notification_border`, `cli_interactive_controller.update_notification_text`, `cli_interactive_controller.wrap_ln`, `cli_interactive_controller.wrap_osc` |
| `src/cadr-cli/interactive/user-bash.lisp` | 213 | `cli_interactive_controller.append_output`, `cli_interactive_controller.bash_append_running`, `cli_interactive_controller.bash_complete_string`, `cli_interactive_controller.bash_stop_entry`, `cli_interactive_controller.complete_entry`, `cli_interactive_controller.make_entry` |
| `src/cadr-cli/media.lisp` | 1,277 | `image_runtime.mime_type` |
| `src/cadr-cli/migration.lisp` | 512 | `cli_bootstrap_sessions.data_directory`, `cli_bootstrap_sessions.legacy_data_directory`, `cli_bootstrap_sessions.manual_migration_command`, `cli_bootstrap_sessions.managed_binary_names`, `cli_bootstrap_sessions.migration_guide_url`, `cli_bootstrap_sessions.extensions_doc_url` |
| `src/cadr-cli/models/credential-print.lisp` | 623 | `cli_models_rest.auth_command` |
| `src/cadr-cli/models/login-selection.lisp` | 75 | `cli_models_rest.login_selection` |
| `src/cadr-cli/models/matching.lisp` | 396 | `cli_models_rest.pattern_match` |
| `src/cadr-cli/models/registry.lisp` | 846 | `cli_dispatch.list_models_registry` |
| `src/cadr-cli/models/store.lisp` | 197 | `cli_dispatch.list_models_registry` |
| `src/cadr-cli/modes/print.lisp` | 600 | `cli_print_rpc.jsonl_line` |
| `src/cadr-cli/modes/rpc/commands.lisp` | 474 | `cli_print_rpc.asst_text`, `cli_print_rpc.cmd_list`, `cli_print_rpc.queue_parse` |
| `src/cadr-cli/modes/rpc/jsonl.lisp` | 123 | `cli_print_rpc.jsonl_read` |
| `src/cadr-cli/modes/rpc/mode.lisp` | 96 | `cli_print_rpc.array_line`, `cli_print_rpc.bad_line`, `cli_print_rpc.ui_absent` |
| `src/cadr-cli/modes/rpc/models.lisp` | 226 | `cli_print_rpc.clamp_thinking` |
| `src/cadr-cli/modes/rpc/prompt-bash.lisp` | 248 | `cli_print_rpc.bash_result`, `cli_print_rpc.rpc_images`, `cli_print_rpc.rpc_prompt` |
| `src/cadr-cli/modes/rpc/sessions.lisp` | 283 | `cli_print_rpc.session_stats` |
| `src/cadr-cli/modes/rpc/ui.lisp` | 288 | `cli_print_rpc.dialog_request`, `cli_print_rpc.dialog_result`, `cli_print_rpc.dialog_expired`, `cli_print_rpc.dialog_default`, `cli_print_rpc.dialog_deadline`, `cli_print_rpc.close_pending` |
| `src/cadr-cli/output-accumulator.lisp` | 199 | `output_accumulator.append`, `output_accumulator.snapshot`, `output_accumulator.finish`, `output_accumulator.last_line_bytes`, `output_accumulator.needs_file`, `output_accumulator.close_temp_file` |
| `src/cadr-cli/packages/commands.lisp` | 764 | `package_manager.resolve` |
| `src/cadr-cli/packages/config-selector.lisp` | 1,561 | `package_manager.autoload_disabled`, `package_manager.config_fit_line`, `package_manager.config_glob_regex`, `package_manager.delta_resource_state`, `package_manager.derived_project_state`, `package_manager.enabled_by_patterns`, `package_manager.entry_target`, `package_manager.find_item_index`, `package_manager.group_less_p`, `package_manager.item_matches`, `package_manager.item_ordinal`, `package_manager.item_source_base`, `package_manager.normalize_pattern`, `package_manager.package_entry_filter`, `package_manager.package_entry_has_filters`, `package_manager.package_override_source`, `package_manager.package_resource_pattern`, `package_manager.pattern_candidates`, `package_manager.pattern_matches`, `package_manager.project_top_level_state`, `package_manager.relative_pattern`, `package_manager.replace_pattern`, `package_manager.resource_display_name`, `package_manager.resource_file_p`, `package_manager.resource_group_label`, `package_manager.resource_key`, `package_manager.resource_kinds`, `package_manager.resource_specification`, `package_manager.scope_base`, `package_manager.selected_entry`, `package_manager.selector_items`, `package_manager.selector_move`, `package_manager.settings_array`, `package_manager.settings_values`, `package_manager.type_label`, `package_manager.visible_range`, `package_manager.resource_item_key`, `package_manager.project_override_state`, `package_manager.next_project_state`, `package_manager.inherited_enabled`, `package_manager.resource_group_key`, `package_manager.package_entry_index`, `package_manager.project_package_entry`, `package_manager.project_package_state`, `package_manager.package_setting_record`, `package_manager.package_setting_records`, `package_manager.selector_rebuild`, `package_manager.switch_scope`, `package_manager.selector_hint`, `package_manager.override_suffix`, `package_manager.checkbox` |
| `src/cadr-cli/packages/manifest.lisp` | 142 | `package_manager.resolve` |
| `src/cadr-cli/packages/settings.lisp` | 214 | `package_manager.resolve` |
| `src/cadr-cli/packages/source.lisp` | 338 | `package_manager.resolve`, `package_manager.package_source` |
| `src/cadr-cli/packages/update-checks.lisp` | 293 | `package_manager.update_argv`, `package_manager.update_env`, `package_manager.git_object_id`, `package_manager.git_output`, `package_manager.records_project_first`, `package_manager.candidate_record`, `package_manager.update_offline`, `package_manager.remote_ref`, `package_manager.update_record_result` |
| `src/cadr-cli/repl.lisp` | 112 | `cli_bootstrap_sessions.pb_ok`, `cli_bootstrap_sessions.rt_ok`, `cli_bootstrap_sessions.dp_ok` |
| `src/cadr-cli/resource-loader.lisp` | 376 | `resource_loader.reload`, `resource_loader.dedupe_by_name`, `resource_loader.context_from_dir`, `resource_loader.project_context`, `resource_loader.nearest_config` |
| `src/cadr-cli/sdk/agent-session.lisp` | 481 | `cli_sdk.agent_session` |
| `src/cadr-cli/sdk/cache-version.lisp` | 498 | `cli_sdk.version_newer`, `cli_sdk.cache_miss`, `cli_sdk.cache_waste`, `cli_sdk.thinking_level` |
| `src/cadr-cli/sdk/model-service.lisp` | 349 | `cli_sdk.model_runtime` |
| `src/cadr-cli/sdk/resource-service.lisp` | 370 | `skill_prompt_load.sdk_get_skills`, `skill_prompt_load.sdk_get_prompts`, `skill_prompt_load.sdk_get_themes` |
| `src/cadr-cli/sdk/session-manager.lisp` | 107 | `cli_sdk.session_list` |
| `src/cadr-cli/sdk/session-runtime.lisp` | 277 | `cli_sdk.session_services` |
| `src/cadr-cli/sdk/settings-service.lisp` | 195 | `settings_load.sdk_default_provider`, `settings_load.sdk_default_model`, `settings_load.sdk_retry_settings`, `settings_load.sdk_http_idle_timeout`, `settings_load.sdk_apply_overrides`, `settings_load.sdk_model_thinking_level`, `settings_load.sdk_settings_value`, `settings_load.sdk_default_thinking_level`, `settings_load.sdk_drain_errors`, `settings_load.sdk_effective_object`, `settings_load.sdk_settings_set`, `settings_load.sdk_settings_remove`, `settings_load.sdk_settings_reload`, `settings_load.sdk_settings_flush`, `settings_load.sdk_compaction_enabled`, `settings_load.sdk_make_manager`, `settings_load.sdk_make_memory`, `settings_load.sdk_effective_thinking_level` |
| `src/cadr-cli/sdk/system-prompt.lisp` | 225 | `skill_prompt_load.build_prompt` |
| `src/cadr-cli/settings/config-values.lisp` | 198 | `cli_settings.create`, `settings_load.config_value` |
| `src/cadr-cli/settings/manager.lisp` | 632 | `cli_settings.create`, `cli_settings.reload`, `cli_settings.enabled_models`, `cli_settings.block_images`, `cli_settings.default_model`, `cli_settings.default_provider`, `cli_settings.output_padding` |
| `src/cadr-cli/settings/trust.lisp` | 216 | `settings_load.project_trust` |
| `src/cadr-cli/support/atomic-write.lisp` | 7 | `cli_support.write_hello`, `cli_support.write_overwrite`, `cli_support.write_empty` |
| `src/cadr-cli/support/changelog-share.lisp` | 346 | `cli_support.strip_ansi`, `cli_support.parse_changelog` |
| `src/cadr-cli/support/event-bus.lisp` | 40 | `cli_support.event_bus` |
| `src/cadr-cli/support/external-editor.lisp` | 20 | `cli_support.editor_success`, `cli_support.editor_fail`, `cli_support.editor_empty` |
| `src/cadr-cli/support/file-watcher.lisp` | 69 | `cli_support.watch_retry_delay`, `cli_support.close_watcher`, `cli_support.watch_signature`, `cli_support.watch_error`, `cli_support.watch_start_close`, `cli_support.poll_once` |
| `src/cadr-cli/support/headers.lisp` | 75 | `cli_support.attribution_headers` |
| `src/cadr-cli/support/html.lisp` | 63 | `cli_support.experimental` |
| `src/cadr-cli/support/model-help.lisp` | 20 | `cli_support.default_thinking_level`, `cli_support.docs_directory`, `cli_support.no_api_key`, `cli_support.no_model_selected`, `cli_support.no_models_help`, `cli_support.provider_login_help` |
| `src/cadr-cli/support/paths.lisp` | 135 | `cli_support.normalize_path` |
| `src/cadr-cli/support/resume-version-git.lisp` | 225 | `cli_support.git_source`, `cli_support.user_agent` |
| `src/cadr-cli/support/shell-process.lisp` | 151 | `cli_support.shell_config`, `cli_support.sanitize_output` |
| `src/cadr-cli/support/threads.lisp` | 7 | `cli_support.threads_absent`, `cli_support.threads_current`, `cli_support.threads_joined` |
| `src/cadr-cli/support/timings.lisp` | 45 | `cli_support.timings` |
| `src/cadr-cli/system-prompt.lisp` | 53 | `skill_prompt_load.resolve_prompt`, `skill_prompt_load.node_read_error`, `skill_prompt_load.prompt_appends` |
| `src/cadr-cli/tool-manager.lisp` | 295 | `tool_manager.get_tool_path`, `tool_manager.ensure_tool`, `tool_manager.cleanup_quarantine`, `tool_manager.release_asset`, `tool_manager.find_binary`, `tool_manager.quarantine_native` |
| `src/cadr-cli/tools/bash.lisp` | 591 | `bash_tool.append_status`, `bash_tool.live_output`, `bash_tool.make_tool`, `bash_tool.normalized_extension`, `bash_tool.output_path`, `bash_tool.process_deadline`, `bash_tool.record_nil`, `bash_tool.strip_exit_footer`, `bash_tool.strip_status`, `bash_tool.strip_truncation`, `bash_tool.truncation_notice`, `bash_tool.user_bash_result` |
| `src/cadr-cli/tools/edit.lisp` | 753 | `agent_tool_loop.line_ending` |
| `src/cadr-cli/tools/find.lisp` | 171 | `find_tool.pattern_match`, `find_tool.find_files`, `find_tool.make_tool` |
| `src/cadr-cli/tools/glob.lisp` | 249 | `find_tool.gitignore_regex`, `find_tool.gitignored`, `find_tool.glob_regex`, `find_tool.glob_regex_body`, `find_tool.glob_scanner`, `find_tool.glob_special`, `find_tool.ignored_directory`, `find_tool.make_glob_tool`, `find_tool.parse_gitignore_line`, `find_tool.directory_gitignore_rules`, `find_tool.collect_tree_files`, `find_tool.glob_files` |
| `src/cadr-cli/tools/grep.lisp` | 331 | `tool_grep.context_file` |
| `src/cadr-cli/tools/ls.lisp` | 100 | `ls_tool.directory_entry_name`, `ls_tool.list_directory`, `ls_tool.make_tool` |
| `src/cadr-cli/tools/path.lisp` | 333 | `agent_tool_loop.tool_path` |
| `src/cadr-cli/tools/powershell.lisp` | 115 | `powershell_tool.make_tool`, `powershell_tool.prefix_command`, `powershell_tool.utf8_prefix` |
| `src/cadr-cli/tools/read.lisp` | 192 | `tool_read.text_file` |
| `src/cadr-cli/tools/write.lisp` | 70 | `write_tool.ensure_parent`, `write_tool.write_utf8`, `write_tool.make_tool` |
| `src/cadr-cli/truncation.lisp` | 235 | `tool_read.text_file` |
| `src/cadr-core/cancellation.lisp` | 70 | `core_rest.cancellation_abort`, `core_rest.cancellation_predicate` |
| `src/cadr-core/redacted-print.lisp` | 54 | `core_rest.redacted_secrets`, `core_rest.redacted_register`, `core_rest.redacted_replace` |
| `src/cadr-core/threads.lisp` | 47 | `core_rest.threads_cleanup` |
| `src/cadr-evals/artifacts.lisp` | 168 | `evals_harness.artifact_persist` |
| `src/cadr-evals/harness-table.lisp` | 339 | `evals_harness.group_key` |
| `src/cadr-evals/harness.lisp` | 737 | `evals_harness.eval_environment`, `evals_harness.eval_paths`, `evals_harness.eval_tools`, `evals_harness.last_assistant`, `evals_harness.make_eval_root`, `evals_harness.msg_content`, `evals_harness.normalize_step_type`, `evals_harness.normalize_steps`, `evals_harness.prompt_eval_agent`, `evals_harness.prompt_step`, `evals_harness.reload_shutdown`, `evals_harness.reload_step`, `evals_harness.resolve_selection`, `evals_harness.result_json`, `evals_harness.run_coding_agent_eval`, `evals_harness.selected_eval_tools`, `evals_harness.step_value`, `evals_harness.transcript`, `evals_harness.usage` |
| `src/cadr-evals/main.lisp` | 158 | `evals_harness.argument_prefix`, `evals_harness.eval_result_p`, `evals_harness.parse_arguments`, `evals_harness.validate_extension`, `evals_harness.validate_smoke` |
| `src/cadr-evals/reporter.lisp` | 314 | `evals_harness.art_meta`, `evals_harness.artifact_reference_json`, `evals_harness.fin_num`, `evals_harness.rep_make`, `evals_harness.reporter_artifacts`, `evals_harness.reporter_run_id` |
| `src/cadr-evals/suites.lisp` | 468 | `evals_harness.canonical_api`, `evals_harness.exclude_guidelines`, `evals_harness.extension_error_json`, `evals_harness.legacy_api`, `evals_harness.prepare_default_prompt`, `evals_harness.required_prompt_boundary`, `evals_harness.matching_hello_call`, `evals_harness.authoring_judge`, `evals_harness.source_bundle`, `evals_harness.bundle_tool_names`, `evals_harness.visible_extension_bundles`, `evals_harness.authoring_harness_table` |
| `src/cadr-evals/summary.lisp` | 732 | `evals_harness.summarize`, `evals_harness.format` |
| `src/cadr-protocol/cbor.lisp` | 492 | `protocol_cbor.roundtrip` |
| `src/cadr-protocol/codec.lisp` | 121 | `protocol_codec.roundtrip` |
| `src/cadr-protocol/framing.lisp` | 170 | `protocol_codec.roundtrip` |
| `src/cadr-protocol/schema.lisp` | 610 | `protocol_codec.roundtrip` |
| `src/cadr-storage/package.lisp` | 19 | `sqlite_session.open_walk` |
| `src/cadr-storage/sqlite.lisp` | 12 | `sqlite_session.open_walk` |
| `src/cadr-tui/autocomplete.lisp` | 647 | `tui_autocomplete.suggest_apply` |
| `src/cadr-tui/components/image.lisp` | 40 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/components/markdown.lisp` | 1,553 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/components/select-list.lisp` | 305 | `tui_select_settings_loaders.filter` |
| `src/cadr-tui/components/tool-block.lisp` | 623 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/composition/loaders.lisp` | 235 | `tui_select_settings_loaders.loader_frames`, `tui_select_settings_loaders.loader_interval`, `tui_select_settings_loaders.loader_step` |
| `src/cadr-tui/composition/protocol.lisp` | 143 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/composition/rich-content.lisp` | 276 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/composition/root.lisp` | 317 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/composition/settings-list.lisp` | 470 | `tui_settings_list.apply_filter` |
| `src/cadr-tui/composition/text-box.lisp` | 280 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/editor.lisp` | 2,014 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/fuzzy.lisp` | 134 | `tui_editor_helpers.fuzzy_match` |
| `src/cadr-tui/input-component.lisp` | 408 | `tui_input_component.edit` |
| `src/cadr-tui/input.lisp` | 333 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/keybindings.lisp` | 269 | `tui_keybindings.resolve_match` |
| `src/cadr-tui/keys.lisp` | 606 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/kill-ring.lisp` | 38 | `tui_kill_ring.push_peek` |
| `src/cadr-tui/latex.lisp` | 1,973 | `tui_latex.render` |
| `src/cadr-tui/mermaid/index.lisp` | 109 | `tui_mermaid.render` |
| `src/cadr-tui/mermaid/source-box.lisp` | 93 | `tui_mermaid.source_box` |
| `src/cadr-tui/mermaid/transform.lisp` | 428 | `tui_mermaid.transform` |
| `src/cadr-tui/native-modifiers.lisp` | 78 | `tui_native_modifiers.pressed` |
| `src/cadr-tui/overlay.lisp` | 485 | `tui_overlay.composite_line` |
| `src/cadr-tui/renderer/alt-screen-search.lisp` | 181 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/renderer/alt-screen.lisp` | 610 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/renderer/lifecycle-input.lisp` | 1,394 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/renderer/main-screen.lisp` | 595 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/renderer/terminal-protocol.lisp` | 78 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/renderer/virtual-terminal.lisp` | 184 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/stdin-buffer.lisp` | 232 | `tui_stdin_buffer.process`, `tui_stdin_buffer.flush`, `tui_stdin_buffer.clear`, `tui_stdin_buffer.contents` |
| `src/cadr-tui/terminal-colors.lisp` | 191 | `tui_theme_overlay.osc11_bg` |
| `src/cadr-tui/terminal-image.lisp` | 806 | `image_runtime.dimensions` |
| `src/cadr-tui/terminal.lisp` | 916 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/theme.lisp` | 562 | `tui_theme_overlay.rgb_to_ansi_256`, `tui_theme_overlay.parse_hex_color`, `tui_theme_overlay.theme_foreground_ansi` |
| `src/cadr-tui/undo-stack.lisp` | 20 | `tui_undo_stack.push_pop` |
| `src/cadr-tui/unicode.lisp` | 1,302 | `render_slicing.slice_ansi_clip`, `render_slicing.slice_plain_clip` |
| `src/cadr-tui/word-navigation.lisp` | 118 | `tui_word_navigation.step` |

### 6.3 Covered as callee

On a named paired thunk. No own bench (G.12).

| file | lines | parent metrics |
|---|---:|---|
| `src/cadr-agent/package.lisp` | 470 | `session_pipeline.session_load`, `session_pipeline.context_walk`, `storage_journal.journal_read`, `storage_journal.journal_append` |
| `src/cadr-ai/conditions.lisp` | 44 | `provider_stream.stream_roundtrip`, `cli_dispatch.list_models_registry` |
| `src/cadr-ai/models.generated.lisp` | 8,720 | `cli_dispatch.list_models_registry` |
| `src/cadr-ai/models.lisp` | 288 | `cli_dispatch.list_models_registry` |
| `src/cadr-ai/package.lisp` | 482 | `provider_stream.stream_roundtrip`, `session_pipeline.session_load`, `cli_dispatch.list_models_registry` |
| `src/cadr-ai/runtime/models.lisp` | 809 | `cli_dispatch.list_models_registry` |
| `src/cadr-ai/support/retry.lisp` | 178 | `provider_stream.stream_roundtrip` |
| `src/cadr-ai/types.lisp` | 207 | `provider_stream.stream_roundtrip`, `session_pipeline.session_load` |
| `src/cadr-cli/interactive/pending-messages.lisp` | 63 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-cli/models/auth-storage.lisp` | 376 | `cli_dispatch.list_models_registry` |
| `src/cadr-cli/package.lisp` | 292 | `cli_dispatch.argv_parse`, `cli_dispatch.help_render`, `cli_dispatch.list_models_registry`, `cli_dispatch.list_models_render`, `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-core/atomic-file.lisp` | 106 | `evals_harness.artifact_persist` |
| `src/cadr-core/package.lisp` | 43 | `session_pipeline.session_load`, `cli_dispatch.list_models_registry` |
| `src/cadr-core/paths.lisp` | 95 | `cli_dispatch.list_models_registry` |
| `src/cadr-core/time.lisp` | 133 | `session_pipeline.session_load`, `storage_journal.journal_read` |
| `src/cadr-evals/package.lisp` | 100 | `evals_harness.summarize` |
| `src/cadr-protocol/package.lisp` | 33 | `protocol_cbor.roundtrip`, `protocol_codec.roundtrip` |
| `src/cadr-tui/components/status.lisp` | 253 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |
| `src/cadr-tui/mermaid/ansi.lisp` | 17 | `tui_mermaid.render` |
| `src/cadr-tui/mermaid/canvas.lisp` | 336 | `tui_mermaid.render` |
| `src/cadr-tui/mermaid/graph.lisp` | 106 | `tui_mermaid.render` |
| `src/cadr-tui/mermaid/labels.lisp` | 332 | `tui_mermaid.render` |
| `src/cadr-tui/mermaid/layout-seq.lisp` | 254 | `tui_mermaid.render` |
| `src/cadr-tui/mermaid/layout.lisp` | 1,090 | `tui_mermaid.render` |
| `src/cadr-tui/mermaid/parse.lisp` | 1,197 | `tui_mermaid.render` |
| `src/cadr-tui/mermaid/width-data.lisp` | 1,008 | `tui_mermaid.render` |
| `src/cadr-tui/mermaid/width.lisp` | 72 | `tui_mermaid.render` |
| `src/cadr-tui/package.lisp` | 362 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input`, `render_slicing.slice_ansi_clip`, `render_slicing.slice_plain_clip` |
| `src/cadr-tui/threads.lisp` | 6 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` |

### 6.4 Needs an H pair

Same-path baseline counterpart, not on an existing timed stack.
Grouped by hole. Do not invent a file-level idle bench.

| hole | files | lines |
|---|---:|---:|

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
