# Goal 20 P.13 inventory

Written by Grok (cadr-dev). Spec: `goal20-draft.md` P.13.
Ruling: `docs/adjudications.md` 2026-08-19.
Board 2026-08-19 19:02: classify every not-yet `paired`/`unpairable`
`src/**/*.lisp`. Schema of `goal20-unpaired-paths.json` is **not**
changed on this knife.

## Method

- Unit is a path (same fixture bytes, same machine, production code).
  Not one wall-clock per file (G.12).
- `covered-as-callee` only when a named paired thunk actually calls
  the file (Goal 11 `render-tui-state` / `make-model-registry` /
  `stream-chat` / session timestamp parse). Same-package is not enough.
- Everything else with a pi counterpart is `needs-pair` with a pi
  entry and a proposed fixture. No new `unpairable`.
- Minimum holes from the user 18:30 list are **not** callees.
- Pairing and optimizing those paths are later commits.

## Counts

Denominator: **295 files / 126,497 lines**
(same Part I lock as `goal20-unpaired-paths.json`).

| class | files | lines | share |
|---|---:|---:|---:|
| `paired` (already in H JSON) | 35 | 24,901 | 19.7% |
| `unpairable` (already in H JSON) | 24 | 7,475 | 5.9% |
| `covered-as-callee` | 17 | 12,777 | 10.1% |
| `needs-pair` | 219 | 81,344 | 64.3% |
| `pairable-uncovered` | 0 | 0 | 0.0% |

H JSON + `--check` now book `covered-as-callee` and
`needs-pair`. `pairable-uncovered` line share is 0%.
Not G.17 `met`.

## Required holes vs H metrics (2026-08-21)

All user-list lower-bound holes already have a named
`goal20-paired-paths` metric. No new pair this session.
No optimize. Not G.17 `met`.

| hole | H metric |
|---|---|
| `sqlite_session` | `sqlite_session.open_walk` |
| `agent_tool_loop` | `agent_tool_loop.roundtrip` |
| `session_compact` | `session_compact.compact` |
| `provider_anthropic` | `provider_anthropic.stream_roundtrip` |
| `provider_openai_responses` | `provider_openai_responses.stream_roundtrip` |
| `provider_google` | `provider_google.stream_roundtrip` |
| `provider_bedrock` | `provider_bedrock.stream_roundtrip` |
| `provider_azure` | `provider_azure_openai.stream_roundtrip` |
| `provider_mistral` | `provider_mistral.stream_roundtrip` |
| `provider_vertex` | `provider_vertex.stream_roundtrip` |
| `provider_codex` | `provider_codex.stream_roundtrip` |
| `provider_pi_messages` | `provider_pi_messages.stream_roundtrip` |
| `provider_registry_defs` | parent of each provider pair; no own bench |
| `settings_load` | `cli_settings.create` |
| `package_manager` | `package_manager.resolve` |
| `skill_prompt_load` | `resource_loader.reload` |

## Required needs-pair holes (inventory; several now `paired`)

These must not be filed as callees.

| id | files | lines | pi entry | proposed fixture |
|---|---:|---:|---|---|
| `sqlite_session` | 3 | 865 | `packages/session-backends/sqlite-node/src/sqlite/index.ts (repo.ts, branch-entries.ts)` | Ingest the existing session.jsonl (209 KiB / 515 lines) into both SQLite backends; time open + read-all-entries + leaf walk. Same bytes, no network. |
| `agent_tool_loop` | 21 | 6,449 | `packages/agent/src/agent-loop.ts (runAgentLoop) + packages/coding-agent/src/core/tools/*.ts` | Faux provider, no socket. One user message, one streamed tool call, one tool result, one final assistant. Reuse FiveAM tool-loop fixtures; Lisp-only retry/skip/abort UX stays unpairable as tool_failure_restarts. |
| `session_compact` | 4 | 1,397 | `packages/coding-agent/src/core/compaction/compaction.ts (compact) and branch-summarization.ts` | Deterministic message list over the compact token budget (text + tool results). Time compact() to the compaction entry bytes. Loading an already-compacted session.jsonl is session_load, not this path. |
| `provider_anthropic` | 1 | 644 | `packages/ai/src/api/anthropic-messages.ts` | Same shape as openai-completions pair: provider-context.json + recorded Anthropic SSE fixture. Seam = *http-request-function* / ProviderRequestOptions.fetch. No live socket. |
| `provider_openai_responses` | 1 | 828 | `packages/ai/src/api/openai-responses.ts` | Recorded OpenAI Responses SSE + same provider-context.json. No live socket. |
| `provider_google` | 1 | 442 | `packages/ai/src/api/google-generative-ai.ts` | Recorded Gemini SSE/JSON chunks + same provider-context.json. No live socket. |
| `provider_bedrock` | 3 | 1,373 | `packages/ai/src/api/bedrock-converse-stream.ts + packages/ai/src/providers/amazon-bedrock.ts` | Recorded Bedrock event-stream bytes + same messages. Auth is fixture credentials, not a live AWS call. |
| `provider_azure` | 1 | 223 | `packages/ai/src/api/azure-openai-responses.ts` | Recorded Azure Responses SSE + same provider-context.json. |
| `provider_mistral` | 1 | 97 | `packages/ai/src/api/mistral-conversations.ts` | Recorded Mistral SSE + same provider-context.json. |
| `provider_vertex` | 2 | 346 | `packages/ai/src/api/google-vertex.ts + packages/ai/src/providers/google-vertex.ts` | Recorded Vertex SSE + fixture ADC JSON. No live Google call. |
| `provider_codex` | 1 | 35 | `packages/ai/src/api/openai-codex-responses.ts` | Recorded Codex Responses SSE + same provider-context.json. |
| `provider_pi_messages` | 1 | 255 | `packages/ai/src/api/pi-messages.ts` | Recorded pi-messages SSE + same provider-context.json. |
| `provider_registry_defs` | 3 | 1,494 | `packages/ai/src/providers/all.ts + packages/ai/src/models.ts provider projection` | Covered by each new provider pair (dispatch + definition lookup). Do not invent a file-level empty bench; the first additional provider pair is the parent metric. |
| `settings_load` | 6 | 2,209 | `packages/coding-agent/src/core/settings-manager.ts` | Checked-in settings.json covering compaction, theme, model, project trust. Time load + get + scoped override. Same bytes both sides. |
| `package_manager` | 6 | 3,269 | `packages/coding-agent/src/core/package-manager.ts + pi-manifest.ts` | Fixture package source (npm/git/local) + manifest.json. Time parse + list + settings persist. Install/network stays off the timed thunk. |
| `skill_prompt_load` | 5 | 1,733 | `packages/coding-agent/src/core/resource-loader.ts, skills.ts, prompt-templates.ts, system-prompt.ts` | Agent dir with skills/*.md and prompts/*.md plus a cwd overlay. Time loadSkills + loadPromptTemplates + system-prompt assemble. Same bytes. |

## covered-as-callee

| file | lines | parent metrics | why on the timed stack |
|---|---:|---|---|
| `src/cadr-agent/package.lisp` | 456 | `session_pipeline.session_load`, `session_pipeline.context_walk`, `storage_journal.journal_read`, `storage_journal.journal_append` | DEFPACKAGE for paired session/journal owners. No independent runtime path. |
| `src/cadr-ai/conditions.lisp` | 44 | `provider_stream.stream_roundtrip`, `cli_dispatch.list_models_registry` | configuration-error / cadr-error signaled from catalog and provider assembly. |
| `src/cadr-ai/models.generated.lisp` | 8,711 | `cli_dispatch.list_models_registry` | register-generated-models fills *model-catalog* that list-model-metadata walks. |
| `src/cadr-ai/models.lisp` | 288 | `cli_dispatch.list_models_registry` | make-model-registry → built-in-models → list-model-metadata / model-from-metadata. |
| `src/cadr-ai/package.lisp` | 480 | `provider_stream.stream_roundtrip`, `session_pipeline.session_load`, `cli_dispatch.list_models_registry` | DEFPACKAGE for the three paired cadr-ai owners. No independent runtime path. |
| `src/cadr-ai/runtime/models.lisp` | 809 | `cli_dispatch.list_models_registry` | make-model-registry always constructs cadr-ai:make-models-runtime. |
| `src/cadr-ai/support/retry.lisp` | 169 | `provider_stream.stream_roundtrip` | stream-chat calls call-with-provider-retries on the SSE roundtrip. |
| `src/cadr-ai/types.lisp` | 207 | `provider_stream.stream_roundtrip`, `session_pipeline.session_load` | stream-chat builds assistant-message structs; session records fill the same types. |
| `src/cadr-cli/interactive/pending-messages.lisp` | 63 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` | render-tui-state always calls render-tui-pending-message-lines. |
| `src/cadr-cli/models/auth-storage.lisp` | 376 | `cli_dispatch.list_models_registry` | pairing thunk passes make-file-auth-storage on the fixture auth.json. |
| `src/cadr-cli/package.lisp` | 289 | `cli_dispatch.argv_parse`, `cli_dispatch.help_render`, `cli_dispatch.list_models_registry`, `cli_dispatch.list_models_render`, `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` | DEFPACKAGE for paired cadr-cli owners. No independent runtime path. |
| `src/cadr-core/package.lisp` | 43 | `session_pipeline.session_load`, `cli_dispatch.list_models_registry` | DEFPACKAGE for time.lisp / paths.lisp. No independent runtime path. |
| `src/cadr-core/paths.lisp` | 95 | `cli_dispatch.list_models_registry` | pairing thunk uses cadr-core:agent-models-path for the staged models.json. |
| `src/cadr-core/time.lisp` | 133 | `session_pipeline.session_load`, `storage_journal.journal_read` | migration.lisp and codec.lisp call iso8601-to-milliseconds on session timestamps. |
| `src/cadr-tui/components/status.lisp` | 253 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` | render-tui-state always calls cadr-tui:render-footer when no custom footer is set. Goal 11 bench does not set one. |
| `src/cadr-tui/package.lisp` | 355 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input`, `render_slicing.slice_ansi_clip`, `render_slicing.slice_plain_clip` | DEFPACKAGE for paired tui owners. No independent runtime path. |
| `src/cadr-tui/threads.lisp` | 6 | `goal11.mouse_drag`, `goal11.wheel`, `goal11.continuous_alt_input` | One-function wrapper around cadr-core:stop-thread-for-cleanup used by renderer teardown. |

## needs-pair by path

### `sqlite_session` (required hole)

- pi: `packages/session-backends/sqlite-node/src/sqlite/index.ts (repo.ts, branch-entries.ts)`
- fixture: Ingest the existing session.jsonl (209 KiB / 515 lines) into both SQLite backends; time open + read-all-entries + leaf walk. Same bytes, no network.

| file | lines |
|---|---:|
| `src/cadr-agent/sqlite-storage.lisp` | 834 |
| `src/cadr-storage/package.lisp` | 19 |
| `src/cadr-storage/sqlite.lisp` | 12 |

### `agent_tool_loop` (required hole)

- pi: `packages/agent/src/agent-loop.ts (runAgentLoop) + packages/coding-agent/src/core/tools/*.ts`
- fixture: Faux provider, no socket. One user message, one streamed tool call, one tool result, one final assistant. Reuse FiveAM tool-loop fixtures; Lisp-only retry/skip/abort UX stays unpairable as tool_failure_restarts.

| file | lines |
|---|---:|
| `src/cadr-agent/execution-env.lisp` | 855 |
| `src/cadr-agent/file-mutation-queue.lisp` | 92 |
| `src/cadr-agent/harness-events.lisp` | 75 |
| `src/cadr-agent/loop/agent-loop.lisp` | 442 |
| `src/cadr-agent/loop/events.lisp` | 169 |
| `src/cadr-agent/loop/tool-execution.lisp` | 480 |
| `src/cadr-agent/loop/turns.lisp` | 393 |
| `src/cadr-agent/runtime.lisp` | 421 |
| `src/cadr-agent/tool.lisp` | 319 |
| `src/cadr-cli/output-accumulator.lisp` | 199 |
| `src/cadr-cli/tool-manager.lisp` | 286 |
| `src/cadr-cli/tools/bash.lisp` | 591 |
| `src/cadr-cli/tools/edit.lisp` | 753 |
| `src/cadr-cli/tools/find.lisp` | 101 |
| `src/cadr-cli/tools/glob.lisp` | 218 |
| `src/cadr-cli/tools/grep.lisp` | 320 |
| `src/cadr-cli/tools/ls.lisp` | 100 |
| `src/cadr-cli/tools/path.lisp` | 333 |
| `src/cadr-cli/tools/read.lisp` | 153 |
| `src/cadr-cli/tools/write.lisp` | 70 |
| `src/cadr-cli/truncation.lisp` | 79 |

### `session_compact` (required hole)

- pi: `packages/coding-agent/src/core/compaction/compaction.ts (compact) and branch-summarization.ts`
- fixture: Deterministic message list over the compact token budget (text + tool results). Time compact() to the compaction entry bytes. Loading an already-compacted session.jsonl is session_load, not this path.

| file | lines |
|---|---:|
| `src/cadr-agent/branch-summarization.lisp` | 185 |
| `src/cadr-agent/compaction.lisp` | 873 |
| `src/cadr-agent/messages.lisp` | 253 |
| `src/cadr-agent/summarization.lisp` | 86 |

### `provider_anthropic` (required hole)

- pi: `packages/ai/src/api/anthropic-messages.ts`
- fixture: Same shape as openai-completions pair: provider-context.json + recorded Anthropic SSE fixture. Seam = *http-request-function* / ProviderRequestOptions.fetch. No live socket.

| file | lines |
|---|---:|
| `src/cadr-ai/providers/anthropic.lisp` | 644 |

### `provider_openai_responses` (required hole)

- pi: `packages/ai/src/api/openai-responses.ts`
- fixture: Recorded OpenAI Responses SSE + same provider-context.json. No live socket.

| file | lines |
|---|---:|
| `src/cadr-ai/providers/openai.lisp` | 828 |

### `provider_google` (required hole)

- pi: `packages/ai/src/api/google-generative-ai.ts`
- fixture: Recorded Gemini SSE/JSON chunks + same provider-context.json. No live socket.

| file | lines |
|---|---:|
| `src/cadr-ai/providers/google.lisp` | 442 |

### `provider_bedrock` (required hole)

- pi: `packages/ai/src/api/bedrock-converse-stream.ts + packages/ai/src/providers/amazon-bedrock.ts`
- fixture: Recorded Bedrock event-stream bytes + same messages. Auth is fixture credentials, not a live AWS call.

| file | lines |
|---|---:|
| `src/cadr-ai/auth/bedrock.lisp` | 220 |
| `src/cadr-ai/providers/bedrock.lisp` | 931 |
| `src/cadr-ai/transport/aws-event-stream.lisp` | 222 |

### `provider_azure` (required hole)

- pi: `packages/ai/src/api/azure-openai-responses.ts`
- fixture: Recorded Azure Responses SSE + same provider-context.json.

| file | lines |
|---|---:|
| `src/cadr-ai/providers/azure-openai.lisp` | 223 |

### `provider_mistral` (required hole)

- pi: `packages/ai/src/api/mistral-conversations.ts`
- fixture: Recorded Mistral SSE + same provider-context.json.

| file | lines |
|---|---:|
| `src/cadr-ai/providers/mistral.lisp` | 97 |

### `provider_vertex` (required hole)

- pi: `packages/ai/src/api/google-vertex.ts + packages/ai/src/providers/google-vertex.ts`
- fixture: Recorded Vertex SSE + fixture ADC JSON. No live Google call.

| file | lines |
|---|---:|
| `src/cadr-ai/auth/vertex.lisp` | 212 |
| `src/cadr-ai/providers/vertex.lisp` | 134 |

### `provider_codex` (required hole)

- pi: `packages/ai/src/api/openai-codex-responses.ts`
- fixture: Recorded Codex Responses SSE + same provider-context.json.

| file | lines |
|---|---:|
| `src/cadr-ai/providers/codex.lisp` | 35 |

### `provider_pi_messages` (required hole)

- pi: `packages/ai/src/api/pi-messages.ts`
- fixture: Recorded pi-messages SSE + same provider-context.json.

| file | lines |
|---|---:|
| `src/cadr-ai/providers/pi-messages.lisp` | 255 |

### `provider_registry_defs` (required hole)

- pi: `packages/ai/src/providers/all.ts + packages/ai/src/models.ts provider projection`
- fixture: Covered by each new provider pair (dispatch + definition lookup). Do not invent a file-level empty bench; the first additional provider pair is the parent metric.

| file | lines |
|---|---:|
| `src/cadr-ai/providers/definitions.lisp` | 1,040 |
| `src/cadr-ai/providers/registry.lisp` | 157 |
| `src/cadr-ai/providers/runtime-projection.lisp` | 297 |

### `settings_load` (required hole)

- pi: `packages/coding-agent/src/core/settings-manager.ts`
- fixture: Checked-in settings.json covering compaction, theme, model, project trust. Time load + get + scoped override. Same bytes both sides.

| file | lines |
|---|---:|
| `src/cadr-cli/bootstrap/settings.lisp` | 828 |
| `src/cadr-cli/config.lisp` | 284 |
| `src/cadr-cli/sdk/settings-service.lisp` | 171 |
| `src/cadr-cli/settings/config-values.lisp` | 198 |
| `src/cadr-cli/settings/manager.lisp` | 512 |
| `src/cadr-cli/settings/trust.lisp` | 216 |

### `package_manager` (required hole)

- pi: `packages/coding-agent/src/core/package-manager.ts + pi-manifest.ts`
- fixture: Fixture package source (npm/git/local) + manifest.json. Time parse + list + settings persist. Install/network stays off the timed thunk.

| file | lines |
|---|---:|
| `src/cadr-cli/packages/commands.lisp` | 764 |
| `src/cadr-cli/packages/config-selector.lisp` | 1,518 |
| `src/cadr-cli/packages/manifest.lisp` | 142 |
| `src/cadr-cli/packages/settings.lisp` | 214 |
| `src/cadr-cli/packages/source.lisp` | 338 |
| `src/cadr-cli/packages/update-checks.lisp` | 293 |

### `skill_prompt_load` (required hole)

- pi: `packages/coding-agent/src/core/resource-loader.ts, skills.ts, prompt-templates.ts, system-prompt.ts`
- fixture: Agent dir with skills/*.md and prompts/*.md plus a cwd overlay. Time loadSkills + loadPromptTemplates + system-prompt assemble. Same bytes.

| file | lines |
|---|---:|
| `src/cadr-agent/resources.lisp` | 739 |
| `src/cadr-cli/resource-loader.lisp` | 353 |
| `src/cadr-cli/sdk/resource-service.lisp` | 370 |
| `src/cadr-cli/sdk/system-prompt.lisp` | 218 |
| `src/cadr-cli/system-prompt.lisp` | 53 |

### `harness_storage` (additional) — paired `harness_storage.open_walk`

- pi: `packages/agent/src/harness/session/jsonl JsonlSessionRepo`
- fixture: existing `session.jsonl` ingested into JSONL repo. Time open + read-all + leaf walk. Distinct from `storage_journal` and `sqlite_session`.
- Friend-MachineD n=5: **1.80×** (11643.5 / 6484.9 µs), ceiling 8.0. No optimize in the booking commit.

| file | lines |
|---|---:|
| `src/cadr-agent/storage/harness.lisp` | 476 |
| `src/cadr-agent/storage/jsonl.lisp` | 536 |
| `src/cadr-agent/storage/memory.lisp` | 378 |
| `src/cadr-agent/storage/protocol.lisp` | 142 |

### `session_discovery` (additional) — paired `session_discovery.header_probe`

- pi: `packages/coding-agent/src/core/session-manager.ts findMostRecentSession`
- fixture: 32 copies of `session.jsonl` with distinct utimes. Time discover + header parse. Not `load-session`.
- Friend-MachineD n=5: **2.05×** (1449.6 / 708.6 µs), ceiling 8.0. No optimize in the booking commit.

| file | lines |
|---|---:|
| `src/cadr-agent/session/discovery.lisp` | 154 |

### `session_export_html` (additional) — paired `session_export_html.to_html`

- pi: `packages/coding-agent/src/core/export-html/index.ts exportSessionToHtml`
- fixture: existing `session.jsonl`, theme=dark. Time HTML write. `html_chars` not exact (cadr 555702 / pi 546995).
- Friend-MachineD n=5: **3.55×** (29217.8 / 8239.7 µs), ceiling 20.0. No optimize in the booking commit.

| file | lines |
|---|---:|
| `src/cadr-agent/session/export-html.lisp` | 455 |

### `agent_schema` (additional) — paired `agent_schema.validate_ok_fail`

- pi: `packages/ai/src/utils/validation.ts validateToolArguments`
- fixture: FiveAM nested edit-tool JSON Schema. Time ok + fail (missing newText).
- Friend-MachineD n=5: **0.38×** (34.2 / 89.4 µs), ceiling 1.5. No optimize in the booking commit.

| file | lines |
|---|---:|
| `src/cadr-agent/schema.lisp` | 850 |

### `agent_proxy` (additional) — paired `agent_proxy.stream_roundtrip`

- pi: `packages/agent/src/proxy.ts streamProxy`
- fixture: stub SSE (start/text/done), no live Radius socket.
- Friend-MachineD n=5: **1.59×** (25.4 / 16.0 µs), ceiling 1.5 (variance). No optimize in the booking commit.

| file | lines |
|---|---:|
| `src/cadr-agent/proxy.lisp` | 251 |

### `agent_conditions` (additional)

- pi: `packages/agent/src error types used by the tool-loop pair`
- fixture: Parent = agent_tool_loop once that pair lands. Do not split a condition file into its own bench.

| file | lines |
|---|---:|
| `src/cadr-agent/conditions.lisp` | 43 |

### `oauth_pkce_device` (additional) — `pkce.lisp` paired `oauth_pkce.challenge_urls`

- pi: `packages/ai/src/auth/oauth/pkce.ts` SHA-256 + openai-codex/anthropic authorize URLs
- fixture: RFC 7636 recorded verifier. Time challenge + URL build. No browser/socket. Other oauth files still `needs-pair`; page.lisp stays unpairable.
- Friend-MachineD n=5: **0.37×** (50.6 / 135.3 µs), ceiling 1.5. No optimize in the booking commit.

| file | lines |
|---|---:|
| `src/cadr-ai/auth.lisp` | 207 |
| `src/cadr-ai/auth/device-code.lisp` | 239 |
| `src/cadr-ai/auth/github-copilot.lisp` | 53 |
| `src/cadr-ai/auth/radius-cloudflare.lisp` | 118 |
| `src/cadr-ai/oauth/callback.lisp` | 324 |
| `src/cadr-ai/oauth/openai-anthropic.lisp` | 304 |
| `src/cadr-ai/oauth/pkce.lisp` | 322 |
| `src/cadr-ai/oauth/providers/anthropic.lisp` | 16 |
| `src/cadr-ai/oauth/providers/github-copilot.lisp` | 174 |
| `src/cadr-ai/oauth/providers/kimi.lisp` | 58 |
| `src/cadr-ai/oauth/providers/openai-device.lisp` | 199 |
| `src/cadr-ai/oauth/providers/openrouter.lisp` | 89 |
| `src/cadr-ai/oauth/providers/radius.lisp` | 116 |
| `src/cadr-ai/oauth/providers/xai.lisp` | 184 |

### `http_transport` (additional)

- pi: `Node fetch / undici path behind ProviderRequestOptions.fetch`
- fixture: stream_roundtrip already replaces this seam. A dedicated pair is recorded HTTP request bytes in/out with the production client, not a second SSE parse. Do not empty-bench the file.

| file | lines |
|---|---:|
| `src/cadr-ai/transport/http.lisp` | 831 |

### `websocket_stream` (additional)

- pi: `packages/ai websocket stream (provider websocket branch)`
- fixture: Recorded websocket frames for a provider that uses them. No live socket.

| file | lines |
|---|---:|
| `src/cadr-ai/websocket.lisp` | 622 |

### `image_runtime` (additional) — `terminal-image.lisp` paired `image_runtime.dimensions`

- pi: `packages/tui/src/terminal-image.ts getImageDimensions`
- fixture: 1x1 PNG + 2x3 GIF base64. Time header parse, not Kitty/iTerm or live image API.
- Friend-MachineD n=5: **5.44×** (7.8 / 1.4 µs), ceiling 8.0. Other files still `needs-pair`. No optimize in the booking commit.

| file | lines |
|---|---:|
| `src/cadr-ai/capabilities/image-runtime.lisp` | 117 |
| `src/cadr-ai/image-models.generated.lisp` | 185 |
| `src/cadr-ai/images.lisp` | 222 |
| `src/cadr-cli/interactive/images.lisp` | 290 |
| `src/cadr-cli/media.lisp` | 1,277 |
| `src/cadr-tui/terminal-image.lisp` | 686 |

### `ai_capabilities` (additional)

- pi: `packages/ai/src/utils/event-stream.ts, deferred-tools, json-parse streaming, session-resources, node-http-proxy`
- fixture: Parent of the first provider/tool pair that actually calls the helper. No empty per-file bench.

| file | lines |
|---|---:|
| `src/cadr-ai/capabilities/event-stream.lisp` | 69 |
| `src/cadr-ai/capabilities/grammar-tools.lisp` | 292 |
| `src/cadr-ai/capabilities/proxy-config.lisp` | 77 |
| `src/cadr-ai/capabilities/session-resources.lisp` | 34 |
| `src/cadr-ai/capabilities/streaming-json.lisp` | 162 |

### `ai_support` (additional) — `token-estimation.lisp` paired `ai_support.estimate_text`

- pi: `packages/ai/src/utils/estimate.ts estimateTextTokens`
- fixture: empty / hello world / 100 ASCII a. Time ceil(utf16/4).
- Friend-MachineD n=5: **3.10×** (0.54 / 0.17 µs), ceiling 8.0 (variance). Other files still `needs-pair`. retry.lisp stays covered-as-callee. No optimize in the booking commit.

| file | lines |
|---|---:|
| `src/cadr-ai/support/grammar-coercion.lisp` | 279 |
| `src/cadr-ai/support/overflow.lisp` | 78 |
| `src/cadr-ai/support/release.lisp` | 104 |
| `src/cadr-ai/support/threads.lisp` | 6 |
| `src/cadr-ai/support/token-estimation.lisp` | 170 |
| `src/cadr-ai/support/uuid.lisp` | 65 |

### `ai_crypto_model_data` (additional) — `model-data.lisp` paired `ai_crypto_model_data.manifest`

- pi: `packages/ai/scripts/model-data.ts createModelDataManifest` (catalog SHA-256; not `hash.ts` shortHash)
- fixture: in-memory two-provider structure + two JSON shard strings. Time manifest, not directory walk. json.lisp pairing already uses sha256 for fixture digests outside the timed thunk.
- Friend-MachineD n=5: **8.97×** (77.3 / 8.6 µs), ceiling 20.0. `crypto.lisp` still `needs-pair`. No optimize in the booking commit.

| file | lines |
|---|---:|
| `src/cadr-ai/crypto.lisp` | 367 |
| `src/cadr-ai/model-data.lisp` | 407 |

### `ai_runtime_faux` (additional)

- pi: `packages/ai/src/providers/faux.ts`
- fixture: Faux event script (text + tool call). Parent of agent_tool_loop; do not split a second empty bench.

| file | lines |
|---|---:|
| `src/cadr-ai/runtime/faux-provider.lisp` | 601 |

### `cli_bootstrap_sessions` (additional)

- pi: `packages/coding-agent/src/cli/* session/command/auth dispatch (not argv_parse / help_render / list_models_render, already paired)`
- fixture: cli-argv.json extra keys for /resume /login /compact routed through command handlers with a staged agent dir. No process cold start.

| file | lines |
|---|---:|
| `src/cadr-cli/bootstrap/auth.lisp` | 172 |
| `src/cadr-cli/bootstrap/commands.lisp` | 2,580 |
| `src/cadr-cli/bootstrap/sessions.lisp` | 1,963 |
| `src/cadr-cli/bootstrap/tools.lisp` | 89 |
| `src/cadr-cli/migration.lisp` | 512 |
| `src/cadr-cli/repl.lisp` | 112 |

### `cli_models_rest` (additional) — `matching.lisp` paired `cli_models_rest.pattern_match`

- pi: `packages/coding-agent/src/core/model-resolver.ts parseModelPattern`
- fixture: staged models.json + auth.json. Time pattern match, not list_models_render / credential-print.
- Friend-MachineD n=5: **1.65×** (31.9 / 19.4 µs), ceiling 3.0. Other files still `needs-pair`. No optimize in the booking commit.

| file | lines |
|---|---:|
| `src/cadr-cli/models/credential-print.lisp` | 623 |
| `src/cadr-cli/models/login-selection.lisp` | 75 |
| `src/cadr-cli/models/matching.lisp` | 398 |

### `cli_interactive_controller` (additional)

- pi: `packages/coding-agent/src/modes/interactive/* controller, transcript, theme, syntax, clipboard`
- fixture: Goal 11 already times mouse/wheel/editor-key through frame.lisp. These files are the rest of the interactive app (slash palette, transcript rebuild, theme switch). Same virtual terminal, fixture key sequence that actually opens those surfaces. Do not re-bench mouse_drag.

| file | lines |
|---|---:|
| `src/cadr-cli/interactive/autocomplete.lisp` | 331 |
| `src/cadr-cli/interactive/clipboard.lisp` | 449 |
| `src/cadr-cli/interactive/controller.lisp` | 2,909 |
| `src/cadr-cli/interactive/extension-ui.lisp` | 756 |
| `src/cadr-cli/interactive/footer.lisp` | 536 |
| `src/cadr-cli/interactive/syntax.lisp` | 1,089 |
| `src/cadr-cli/interactive/theme.lisp` | 215 |
| `src/cadr-cli/interactive/themes.lisp` | 415 |
| `src/cadr-cli/interactive/tool-render-session.lisp` | 61 |
| `src/cadr-cli/interactive/transcript.lisp` | 1,070 |
| `src/cadr-cli/interactive/user-bash.lisp` | 213 |

### `cli_selectors` (additional)

- pi: `packages/coding-agent/src/modes/interactive selectors (models, sessions, settings, tree, auth, login)`
- fixture: Open each selector on a staged session/model/settings tree; time render + one move + confirm. Same bytes of the backing JSON.

| file | lines |
|---|---:|
| `src/cadr-cli/interactive/components/announcement.lisp` | 41 |
| `src/cadr-cli/interactive/components/armin.lisp` | 282 |
| `src/cadr-cli/interactive/components/countdown.lisp` | 90 |
| `src/cadr-cli/interactive/components/daxnuts.lisp` | 185 |
| `src/cadr-cli/interactive/components/loaders.lisp` | 155 |
| `src/cadr-cli/interactive/selectors/auth.lisp` | 624 |
| `src/cadr-cli/interactive/selectors/common.lisp` | 394 |
| `src/cadr-cli/interactive/selectors/fork.lisp` | 147 |
| `src/cadr-cli/interactive/selectors/login-dialog.lisp` | 279 |
| `src/cadr-cli/interactive/selectors/models.lisp` | 1,310 |
| `src/cadr-cli/interactive/selectors/sessions.lisp` | 1,477 |
| `src/cadr-cli/interactive/selectors/settings.lisp` | 893 |
| `src/cadr-cli/interactive/selectors/tree.lisp` | 1,812 |
| `src/cadr-cli/interactive/selectors/trust.lisp` | 293 |

### `cli_extensions_install` (additional)

- pi: `packages/coding-agent/src/core/extensions/loader.ts (JS extension install/discover). Lisp extension host stays lisp_extension_host unpairable.`
- fixture: Fixture extension manifest on disk. Time discover + load metadata. No network install. Llama UI is the llama.cpp extension's TUI, pair against that extension's TS if present.

| file | lines |
|---|---:|
| `src/cadr-cli/extensions/commands.lisp` | 56 |
| `src/cadr-cli/extensions/discovery.lisp` | 212 |
| `src/cadr-cli/extensions/installer.lisp` | 209 |
| `src/cadr-cli/extensions/llama/client.lisp` | 472 |
| `src/cadr-cli/extensions/llama/extension.lisp` | 470 |
| `src/cadr-cli/extensions/llama/huggingface.lisp` | 290 |
| `src/cadr-cli/extensions/llama/provider.lisp` | 315 |
| `src/cadr-cli/extensions/llama/ui.lisp` | 763 |
| `src/cadr-cli/extensions/loader.lisp` | 702 |

### `cli_sdk` (additional)

- pi: `packages/coding-agent/src/core/sdk.ts + agent-session.ts + agent-session-runtime.ts`
- fixture: SDK create-session + prompt + read with faux provider. Overlaps agent_tool_loop; first pair should own both rather than two empty benches.

| file | lines |
|---|---:|
| `src/cadr-cli/sdk/agent-session.lisp` | 481 |
| `src/cadr-cli/sdk/cache-version.lisp` | 498 |
| `src/cadr-cli/sdk/model-service.lisp` | 349 |
| `src/cadr-cli/sdk/session-manager.lisp` | 107 |
| `src/cadr-cli/sdk/session-runtime.lisp` | 277 |

### `cli_print_rpc` (additional) — `print.lisp` paired `cli_print_rpc.jsonl_line`

- pi: `packages/coding-agent/src/modes/rpc/jsonl.ts serializeJsonLine`
- fixture: one RPC response object. Time JSONL frame write, not a live stdin loop.
- Friend-MachineD n=5: **13.21×** (3.3 / 0.25 µs), ceiling 8.0 (variance). Other files still `needs-pair`. No optimize in the booking commit.

| file | lines |
|---|---:|
| `src/cadr-cli/modes/print.lisp` | 578 |
| `src/cadr-cli/modes/rpc/commands.lisp` | 460 |
| `src/cadr-cli/modes/rpc/jsonl.lisp` | 123 |
| `src/cadr-cli/modes/rpc/mode.lisp` | 96 |
| `src/cadr-cli/modes/rpc/models.lisp` | 226 |
| `src/cadr-cli/modes/rpc/prompt-bash.lisp` | 248 |
| `src/cadr-cli/modes/rpc/sessions.lisp` | 283 |
| `src/cadr-cli/modes/rpc/ui.lisp` | 288 |

### `cli_support` (additional)

- pi: `packages/coding-agent/src/core/{event-bus,timings,exec,diagnostics}.ts and path helpers`
- fixture: Callee of a parent pair. No empty per-file bench.

| file | lines |
|---|---:|
| `src/cadr-cli/support/atomic-write.lisp` | 7 |
| `src/cadr-cli/support/changelog-share.lisp` | 342 |
| `src/cadr-cli/support/event-bus.lisp` | 40 |
| `src/cadr-cli/support/external-editor.lisp` | 20 |
| `src/cadr-cli/support/file-watcher.lisp` | 69 |
| `src/cadr-cli/support/headers.lisp` | 75 |
| `src/cadr-cli/support/html.lisp` | 63 |
| `src/cadr-cli/support/model-help.lisp` | 20 |
| `src/cadr-cli/support/paths.lisp` | 119 |
| `src/cadr-cli/support/resume-version-git.lisp` | 225 |
| `src/cadr-cli/support/shell-process.lisp` | 132 |
| `src/cadr-cli/support/threads.lisp` | 7 |
| `src/cadr-cli/support/timings.lisp` | 45 |

### `tui_mermaid` (additional)

- pi: `grok-mermaid dist/*.js + packages/coding-agent/src/modes/interactive/components/mermaid.ts`
- fixture: Checked-in mermaid fences (already used by FiveAM). Time parse + layout + ANSI art. Goal 11 markdown does not run this unless the transcript contains a mermaid fence; K8 left it uncovered.

| file | lines |
|---|---:|
| `src/cadr-tui/mermaid/ansi.lisp` | 17 |
| `src/cadr-tui/mermaid/canvas.lisp` | 336 |
| `src/cadr-tui/mermaid/graph.lisp` | 106 |
| `src/cadr-tui/mermaid/index.lisp` | 109 |
| `src/cadr-tui/mermaid/labels.lisp` | 332 |
| `src/cadr-tui/mermaid/layout-seq.lisp` | 254 |
| `src/cadr-tui/mermaid/layout.lisp` | 1,090 |
| `src/cadr-tui/mermaid/parse.lisp` | 1,197 |
| `src/cadr-tui/mermaid/source-box.lisp` | 93 |
| `src/cadr-tui/mermaid/transform.lisp` | 428 |
| `src/cadr-tui/mermaid/width-data.lisp` | 1,008 |
| `src/cadr-tui/mermaid/width.lisp` | 72 |

### `tui_latex` (additional) — `latex.lisp` paired `tui_latex.render`

- pi: `packages/tui/src/latex.ts renderLatex`
- fixture: FiveAM reference snippets. Time Unicode render, not a TUI frame.
- Friend-MachineD n=5: **2.49×** (64.4 / 25.8 µs), ceiling 3.0. No optimize in the booking commit.

| file | lines |
|---|---:|
| `src/cadr-tui/latex.lisp` | 1,950 |

### `tui_editor_helpers` (additional) — `fuzzy.lisp` paired `tui_editor_helpers.fuzzy_match`

- pi: `packages/tui/src/fuzzy.ts fuzzyMatch`
- fixture: queries against `gpt-4o`. Time match flags, not a TUI frame.
- Friend-MachineD n=5: **0.45×** (1.8 / 4.0 µs), ceiling 8.0. `word-navigation.lisp` now paired `tui_word_navigation.step` **0.17×** (0.94 / 5.4 µs), ceiling 8.0. `kill-ring.lisp` now paired `tui_kill_ring.push_peek` **0.85×** (0.58 / 0.68 µs), ceiling 8.0. `undo-stack.lisp` now paired `tui_undo_stack.push_pop` **0.21×** (0.51 / 2.42 µs), ceiling 8.0. `autocomplete.lisp` now paired `tui_autocomplete.suggest_apply` **5.17×** (136.4 / 26.4 µs), ceiling 8.0. `keybindings.lisp` now paired `tui_keybindings.resolve_match` **1.88×** (27.7 / 14.8 µs), ceiling 8.0. `stdin-buffer.lisp` now paired `tui_stdin_buffer.process` **0.33×** (2.3 / 6.9 µs), ceiling 8.0. `input-component.lisp` now paired `tui_input_component.edit` **0.06×** (5.5 / 97.8 µs), ceiling 8.0. `native-modifiers.lisp` now paired `tui_native_modifiers.pressed` **7.50×** (1.22 / 0.16 µs), ceiling 8.0. Other files still `needs-pair`. No optimize in the booking commit.

| file | lines |
|---|---:|
| `src/cadr-tui/autocomplete.lisp` | 594 |
| `src/cadr-tui/fuzzy.lisp` | 134 |
| `src/cadr-tui/input-component.lisp` | 408 |
| `src/cadr-tui/keybindings.lisp` | 268 |
| `src/cadr-tui/kill-ring.lisp` | 38 |
| `src/cadr-tui/native-modifiers.lisp` | 78 |
| `src/cadr-tui/stdin-buffer.lisp` | 232 |
| `src/cadr-tui/undo-stack.lisp` | 20 |
| `src/cadr-tui/word-navigation.lisp` | 118 |

### `tui_theme_overlay` (additional) — `terminal-colors.lisp` paired `tui_theme_overlay.osc11_bg`

- pi: `packages/tui/src/terminal-colors.ts parseOsc11BackgroundColor`
- fixture: OSC 11 rgb:/hex + scheme report. Time parse, not a TUI frame.
- Friend-MachineD n=5: **1.16×** (3.8 / 3.3 µs), ceiling 8.0. `overlay.lisp` now paired `tui_overlay.composite_line` **0.87×** (19.1 / 22.0 µs), ceiling 8.0. Other files still `needs-pair`. No optimize in the booking commit.

| file | lines |
|---|---:|
| `src/cadr-tui/overlay.lisp` | 485 |
| `src/cadr-tui/terminal-colors.lisp` | 191 |
| `src/cadr-tui/theme.lisp` | 562 |

### `tui_select_settings_loaders` (additional) — `select-list.lisp` paired `tui_select_settings_loaders.filter`

- pi: `packages/tui/src/components/select-list.ts SelectList.setFilter`
- fixture: hello/help/world items; filters he/wo/zz. Time prefix filter, not a live TUI.
- Friend-MachineD n=5: **1.27×** (1.2 / 1.0 µs), ceiling 8.0 (variance). Other files still `needs-pair`. No optimize in the booking commit.

| file | lines |
|---|---:|
| `src/cadr-tui/components/select-list.lisp` | 305 |
| `src/cadr-tui/composition/loaders.lisp` | 235 |
| `src/cadr-tui/composition/settings-list.lisp` | 470 |

### `evals_harness` (additional) — `summary.lisp` paired `evals_harness.summarize`

- pi: `packages/evals/src/vitest-evals/summary.ts summarizeHarnessComparisons`
- fixture: Four scored harness observations (tool access create/inspect). Time report assembly, not a live eval.
- Friend-MachineD n=5: **0.88×** (8.0 / 9.0 µs), ceiling 1.5. Other evals files still `needs-pair`. No optimize in the booking commit.

| file | lines |
|---|---:|
| `src/cadr-evals/artifacts.lisp` | 168 |
| `src/cadr-evals/harness-table.lisp` | 339 |
| `src/cadr-evals/harness.lisp` | 737 |
| `src/cadr-evals/main.lisp` | 158 |
| `src/cadr-evals/package.lisp` | 100 |
| `src/cadr-evals/reporter.lisp` | 314 |
| `src/cadr-evals/suites.lisp` | 468 |
| `src/cadr-evals/summary.lisp` | 732 |

### `protocol_cbor` (additional) — `cbor.lisp` paired `protocol_cbor.roundtrip`; codec/framing/schema paired `protocol_codec.roundtrip`

- pi: `packages/protocol/src/cbor encodeCbor + decodeCbor` and `packages/protocol/src/codec.ts encodeClientMessage`
- fixture: 16 RFC 8949 vectors (cbor) + client `list` request through frames (codec).
- Friend-MachineD n=5: cbor **0.25×** (17.7 / 70.1 µs), ceiling 1.5; codec **0.10×** (9.6 / 94.2 µs), ceiling 1.5. No optimize in the booking commits.

| file | lines |
|---|---:|
| `src/cadr-protocol/cbor.lisp` | 492 |
| `src/cadr-protocol/codec.lisp` | 121 |
| `src/cadr-protocol/framing.lisp` | 170 |
| `src/cadr-protocol/package.lisp` | 33 |
| `src/cadr-protocol/schema.lisp` | 610 |

### `core_rest` (additional)

- pi: `shared Node helpers (fs atomic write, abort, threads, redacted print, cancellation)`
- fixture: Callee of a parent pair (journal persist, settings write). No empty per-file bench. time.lisp and paths.lisp are already covered-as-callee.

| file | lines |
|---|---:|
| `src/cadr-core/atomic-file.lisp` | 106 |
| `src/cadr-core/cancellation.lisp` | 70 |
| `src/cadr-core/redacted-print.lisp` | 44 |
| `src/cadr-core/threads.lisp` | 47 |

## Not done

- `session_compact` H pair is booked (11.33× / ceiling 20.0);
  not P.13 complete. Loading an already-compacted session stays
  `session_load`. Next required hole is `provider_anthropic`.
- `goal20-unpaired-paths.py` schema still three classes.
- G.17 still `missing`. Part P still `[open]`.
- Already-paired paths above 1.0× (load / journal_read / argv)
  stay in scope; this inventory does not pause them.
  Truncate head/tail remesure `e2a4dfad6` is **0.70× / 0.82×** (<1).
  Not P.13 complete. G.17 still `missing`. Part P still `[open]`.
