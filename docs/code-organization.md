# Code organization ledger

This ledger answers a different question from the four parity ledgers: not
whether Cadr matches pi, but whether a maintainer can predict where code belongs
and whether one user-visible decision has one owner.

## 1. Audit boundary and method

The Goal 14 draft recorded 135 production files.  Goal 13 added five approved
export assets and three crash/cleanup files; Goal 14 B3 then added the six-file
`cadr-core` leaf, B1 extracted eight interactive leaf owners, B2 replaced
the remaining selector monolith with eight selector owners, B4 replaced
eight mixed CLI service files with 38 domain owners, B5 split CLI bootstrap
and RPC command handling into eleven cohesive owners, B6 replaced the two
interactive controller/component monoliths with seventeen responsibility owners,
and B7 replaced three reusable TUI monoliths with sixteen protocol-ordered
owners. B8 replaced three agent session/storage/loop monoliths with thirteen
owners, B9 replaced the extension-host monolith with eight owners, B10
replaced four mixed AI files with seventeen exact owners, and B11 replaced
five mixed provider/authentication files with 25 exact owners. Silently
retaining any earlier denominator would omit exactly the source boundaries this
goal is supposed to police, so this ledger covers all 280 current files.

- 275 Lisp files, 106,580 lines, 4,470 top-level definitions.
- 5 static export assets, 4,275 lines.
- 280 production files and 110,855 physical lines in total.
- A top-level definition is a column-zero form beginning with `def*` or
  `define-*`; static assets therefore have zero.
- `合格` means one predictable responsibility; `合格·大体量` means the same but
  large for a stated structural reason; `应拆分` means unrelated responsibilities
  share a file.  No current whole file merits `应合并`: the tiny files are package,
  protocol, adapter, or load-order boundaries rather than arbitrary fragments.

The audit used file contents and top-level forms, not LOC alone.  In particular,
large protocol codecs and generated/assets files remain intact, while smaller
files with unrelated facilities fail.

## 2. Per-file ledger

### 2.1 `cadr-agent`

| Path | Lines | Definitions | One-sentence responsibility | Verdict |
|---|---:|---:|---|---|
| `src/cadr-agent/branch-summarization.lisp` | 185 | 11 | Prepare a session branch and ask the model for its branch summary. | 合格 |
| `src/cadr-agent/summarization.lisp` | 86 | 4 | Own the shared conversation-summary prompt, request, and retry contract. | 合格 |
| `src/cadr-agent/compaction.lisp` | 513 | 23 | Estimate context, choose a cut point, and execute the compaction lifecycle. | 合格·大体量 |
| `src/cadr-agent/conditions.lisp` | 43 | 9 | Define agent-layer condition types. | 合格 |
| `src/cadr-agent/execution-env.lisp` | 884 | 55 | Implement the replaceable filesystem/process execution environment used by tools and harnesses. | 合格·大体量 |
| `src/cadr-agent/export-html/template.css` | 1,066 | 0 | Provide the exact vendored baseline stylesheet embedded in offline session exports. | 合格·大体量 |
| `src/cadr-agent/export-html/template.html` | 55 | 0 | Provide the exact HTML shell embedded in offline session exports. | 合格 |
| `src/cadr-agent/export-html/template.js` | 1,864 | 0 | Provide the exact vendored baseline browser renderer embedded in session exports. | 合格·大体量 |
| `src/cadr-agent/export-html/vendor/highlight.min.js` | 1,212 | 0 | Vendor the approved Highlight.js browser asset byte-for-byte. | 合格·大体量 |
| `src/cadr-agent/export-html/vendor/marked.min.js` | 78 | 0 | Vendor the approved Marked browser asset byte-for-byte. | 合格 |
| `src/cadr-agent/extensions/api.lisp` | 373 | 31 | Validate active APIs, copy extension values, and project event payloads/results. | 合格 |
| `src/cadr-agent/extensions/commands.lisp` | 296 | 11 | Invoke extension commands and expand registered prompt templates. | 合格 |
| `src/cadr-agent/extensions/context.lisp` | 705 | 76 | Define extension host/context state, cancellation, and all context/UI actions. | 合格·大体量 |
| `src/cadr-agent/extensions/lifecycle.lisp` | 772 | 18 | Validate, merge, and dispatch the complete frozen extension lifecycle. | 合格·大体量 |
| `src/cadr-agent/extensions/providers.lisp` | 521 | 21 | Project extension tools, messages, and session-local provider overlays into an agent. | 合格 |
| `src/cadr-agent/extensions/registration.lisp` | 812 | 53 | Define bundles, registries, frozen events, and extension authoring macros. | 合格·大体量 |
| `src/cadr-agent/extensions/rendering.lisp` | 257 | 17 | Own extension failure notices, Markdown/message/tool rendering, and shortcuts. | 合格 |
| `src/cadr-agent/extensions/snapshot.lisp` | 379 | 12 | Build immutable extension snapshots and replace active bundles safely. | 合格 |
| `src/cadr-agent/file-mutation-queue.lisp` | 84 | 10 | Serialize mutations to the same resolved file. | 合格 |
| `src/cadr-agent/loop/agent-loop.lisp` | 464 | 8 | Own the public prompt/steer/follow-up entrypoints and outer agent lifecycle. | 合格 |
| `src/cadr-agent/loop/events.lisp` | 166 | 16 | Emit and normalize agent lifecycle, stream, queue, and tool events. | 合格 |
| `src/cadr-agent/loop/tool-execution.lisp` | 459 | 18 | Execute tool batches with hooks, restarts, termination, updates, and abort state. | 合格 |
| `src/cadr-agent/loop/turns.lisp` | 278 | 14 | Prepare, stream, retry, compact, and finalize one agent turn. | 合格 |
| `src/cadr-agent/messages.lisp` | 243 | 24 | Convert agent-specific message envelopes and file-operation summaries to model-facing messages. | 合格 |
| `src/cadr-agent/package.lisp` | 442 | 1 | Declare the public `cadr-agent` package surface. | 合格 |
| `src/cadr-agent/proxy.lisp` | 229 | 9 | Translate proxy-provider events into native agent stream events. | 合格 |
| `src/cadr-agent/resources.lisp` | 739 | 30 | Load, validate, substitute, and format prompts and skills as agent resources. | 合格·大体量 |
| `src/cadr-agent/runtime.lisp` | 423 | 28 | Own agent event emission, queued steering/follow-up input, mutation state, abort, and shutdown. | 合格·大体量 |
| `src/cadr-agent/schema.lisp` | 702 | 14 | Validate JSON Schema definitions and tool arguments with local reference support. | 合格·大体量 |
| `src/cadr-agent/session/codec.lisp` | 526 | 30 | Encode, decode, validate, and identify session entries and metadata. | 合格 |
| `src/cadr-agent/session/discovery.lisp` | 146 | 5 | Discover, list, continue, and resolve session files. | 合格 |
| `src/cadr-agent/session/export-html.lisp` | 455 | 24 | Embed assets and export a session as baseline-compatible offline HTML. | 合格 |
| `src/cadr-agent/session/journal.lisp` | 646 | 29 | Create, append, branch, label, and inspect the live JSONL session journal. | 合格 |
| `src/cadr-agent/session/migration.lisp` | 565 | 11 | Validate and migrate v1/v2/v3 session logs with atomic replacement. | 合格 |
| `src/cadr-agent/sqlite-storage.lisp` | 860 | 33 | Implement the SQLite session-storage and repository backend. | 合格·大体量 |
| `src/cadr-agent/storage/harness.lisp` | 495 | 31 | Adapt session-storage backends to harness session lifecycle operations. | 合格 |
| `src/cadr-agent/storage/jsonl.lisp` | 536 | 19 | Implement JSONL session storage and repository backends. | 合格 |
| `src/cadr-agent/storage/memory.lisp` | 372 | 19 | Implement in-memory session storage and repository backends. | 合格 |
| `src/cadr-agent/storage/protocol.lisp` | 122 | 24 | Define storage/repository metadata, generic protocols, and shared errors. | 合格 |
| `src/cadr-agent/tool.lisp` | 309 | 23 | Define tool registry, execution bindings, validation, and prepared outcomes. | 合格·大体量 |
| `src/cadr-agent/truncate.lisp` | 283 | 31 | Implement baseline-compatible bounded head/tail/line truncation and its result contract. | 合格 |

### 2.2 `cadr-ai`

| Path | Lines | Definitions | One-sentence responsibility | Verdict |
|---|---:|---:|---|---|
| `src/cadr-ai/auth.lisp` | 225 | 19 | Serialize, atomically persist, redact, and refresh provider credentials. | 合格 |
| `src/cadr-ai/capabilities/event-stream.lisp` | 61 | 6 | Implement the producer/consumer event stream and terminal-result protocol. | 合格 |
| `src/cadr-ai/capabilities/grammar-tools.lisp` | 133 | 10 | Resolve deferred tools and strict/grammar constrained-sampling metadata. | 合格 |
| `src/cadr-ai/capabilities/image-runtime.lisp` | 117 | 18 | Register image APIs and own the mutable image provider/model runtime. | 合格 |
| `src/cadr-ai/capabilities/proxy-config.lisp` | 77 | 5 | Resolve HTTP proxy and NO_PROXY policy for target URLs. | 合格 |
| `src/cadr-ai/capabilities/session-resources.lisp` | 34 | 5 | Register and clean session-owned provider transport resources. | 合格 |
| `src/cadr-ai/capabilities/streaming-json.lisp` | 162 | 11 | Provide stable JavaScript-compatible hashes and repair partial streaming JSON. | 合格 |
| `src/cadr-ai/conditions.lisp` | 44 | 12 | Define provider-layer condition types. | 合格 |
| `src/cadr-ai/crash.lisp` | 218 | 13 | Redact secrets and report fatal conditions through a private crash-log boundary. | 合格 |
| `src/cadr-ai/crypto.lisp` | 367 | 14 | Implement SigV4 canonicalization/signing and service-account JWT signing. | 合格·大体量 |
| `src/cadr-ai/image-models.generated.lisp` | 173 | 1 | Hold generated image-model catalog data. | 合格·大体量 |
| `src/cadr-ai/images.lisp` | 222 | 8 | Build OpenRouter image requests and normalize generated-image results. | 合格 |
| `src/cadr-ai/json.lisp` | 551 | 27 | Parse and serialize bounded JSON plus common content/data-URL helpers. | 合格·大体量 |
| `src/cadr-ai/model-data.lisp` | 398 | 26 | Validate model-data artifacts/manifests and generate deterministic catalog fixtures. | 合格·大体量 |
| `src/cadr-ai/models.generated.lisp` | 8,114 | 1 | Hold the generated model metadata catalog; the generator is its owner. | 合格·大体量 |
| `src/cadr-ai/models.lisp` | 287 | 23 | Define model metadata/catalog operations, thinking-level resolution, and cost calculation. | 合格 |
| `src/cadr-ai/oauth/callback.lisp` | 316 | 11 | Parse manual/callback authorization input and own the loopback callback lifecycle. | 合格 |
| `src/cadr-ai/oauth/openai-anthropic.lisp` | 288 | 12 | Exchange, refresh, and orchestrate the browser OAuth flows shared by OpenAI Codex and Anthropic. | 合格 |
| `src/cadr-ai/oauth/page.lisp` | 149 | 6 | Render the branded OAuth callback success and error pages. | 合格 |
| `src/cadr-ai/oauth/pkce.lisp` | 317 | 36 | Own OAuth metadata plus the SHA-256, Base64URL, PKCE, state, and authorization-URL primitives. | 合格 |
| `src/cadr-ai/oauth/providers/anthropic.lisp` | 16 | 1 | Project the Anthropic browser OAuth flow into the runtime callback contract. | 合格 |
| `src/cadr-ai/oauth/providers/github-copilot.lisp` | 136 | 13 | Implement GitHub Copilot device login, token exchange, refresh, and model filtering. | 合格 |
| `src/cadr-ai/oauth/providers/kimi.lisp` | 56 | 6 | Implement Kimi Coding device login and credential refresh. | 合格 |
| `src/cadr-ai/oauth/providers/openai-device.lisp` | 199 | 7 | Implement OpenAI Codex device authorization, polling, and runtime login selection. | 合格 |
| `src/cadr-ai/oauth/providers/openrouter.lisp` | 89 | 7 | Implement OpenRouter PKCE login, key exchange, and refresh. | 合格 |
| `src/cadr-ai/oauth/providers/radius.lisp` | 118 | 9 | Implement Radius browser/device login and gateway-scoped credential refresh. | 合格 |
| `src/cadr-ai/oauth/providers/xai.lisp` | 170 | 17 | Implement xAI device authorization, polling, and refresh over the shared OAuth request boundary. | 合格 |
| `src/cadr-ai/package.lisp` | 473 | 2 | Declare the public `cadr-ai` package surface and HTTP injection seam. | 合格 |
| `src/cadr-ai/auth/bedrock.lisp` | 163 | 11 | Resolve Bedrock credentials, profiles, regions, and ARN-derived configuration. | 合格 |
| `src/cadr-ai/auth/device-code.lisp` | 211 | 10 | Own generic cancellable device-code polling, validation, and credential parsing. | 合格 |
| `src/cadr-ai/auth/github-copilot.lisp` | 66 | 3 | Parse GitHub device authorization and resolve Copilot endpoint/model metadata. | 合格 |
| `src/cadr-ai/auth/radius-cloudflare.lisp` | 115 | 4 | Validate Radius configuration and materialize Radius/Cloudflare endpoints. | 合格 |
| `src/cadr-ai/auth/vertex.lisp` | 147 | 7 | Resolve Google Vertex credentials and exchange service-account access tokens. | 合格 |
| `src/cadr-ai/provider.lisp` | 760 | 75 | Define provider protocol classes plus common request, retry, history, stream, and error machinery. | 合格·大体量 |
| `src/cadr-ai/providers/anthropic.lisp` | 618 | 16 | Implement Anthropic Messages request, response, cache, tool, and stream semantics. | 合格·大体量 |
| `src/cadr-ai/providers/google.lisp` | 408 | 17 | Implement Google Generative AI request, thinking, response, and stream semantics. | 合格·大体量 |
| `src/cadr-ai/providers/azure-openai.lisp` | 241 | 12 | Adapt Azure, Copilot, and Cloudflare OpenAI-compatible endpoints and headers. | 合格 |
| `src/cadr-ai/providers/bedrock.lisp` | 929 | 32 | Implement Bedrock Converse payloads, SigV4 request metadata, event reduction, and complete responses. | 合格·大体量 |
| `src/cadr-ai/providers/codex.lisp` | 31 | 1 | Adapt the OpenAI Codex Responses request contract. | 合格 |
| `src/cadr-ai/providers/mistral.lisp` | 98 | 4 | Adapt Mistral Conversations reasoning and tool-call identifiers. | 合格 |
| `src/cadr-ai/providers/pi-messages.lisp` | 251 | 6 | Implement pi Messages request rewriting and event/response reduction. | 合格 |
| `src/cadr-ai/providers/vertex.lisp` | 130 | 2 | Adapt Google Vertex endpoints and signed request construction. | 合格 |
| `src/cadr-ai/providers/openai-completions.lisp` | 775 | 30 | Implement OpenAI-compatible Chat Completions request, response, tool, and stream semantics. | 合格·大体量 |
| `src/cadr-ai/providers/openai.lisp` | 772 | 17 | Implement OpenAI Responses request, response, tool, reasoning, and stream semantics. | 合格·大体量 |
| `src/cadr-ai/providers/definitions.lisp` | 963 | 10 | Validate and own the complete 38-provider declaration matrix and environment inputs. | 合格·大体量 |
| `src/cadr-ai/providers/registry.lisp` | 157 | 2 | Instantiate declared providers through the appropriate native protocol class. | 合格 |
| `src/cadr-ai/providers/runtime-projection.lisp` | 270 | 13 | Project provider declarations into session-local auth, OAuth, model, and dispatch callbacks. | 合格 |
| `src/cadr-ai/runtime/faux-provider.lisp` | 426 | 25 | Implement the deterministic faux provider, queued responses, and transcript serializer. | 合格 |
| `src/cadr-ai/runtime/models.lisp` | 834 | 50 | Own mutable provider/model/auth state, refresh, lookup, and request dispatch. | 合格·大体量 |
| `src/cadr-ai/sse.lisp` | 101 | 5 | Parse Server-Sent Events from text or binary streams. | 合格 |
| `src/cadr-ai/support/grammar-coercion.lisp` | 227 | 13 | Coerce and validate grammar-tool JSON values against schemas. | 合格 |
| `src/cadr-ai/support/overflow.lisp` | 78 | 5 | Classify context-overflow errors from status and usage evidence. | 合格 |
| `src/cadr-ai/support/release.lisp` | 21 | 6 | Read the single version source and format the aligned release identity. | 合格 |
| `src/cadr-ai/support/retry.lisp` | 129 | 6 | Classify retryable assistant failures and execute the bounded retry policy. | 合格 |
| `src/cadr-ai/support/threads.lisp` | 6 | 1 | Delegate bounded thread cleanup to the B3 core policy owner. | 合格 |
| `src/cadr-ai/support/token-estimation.lisp` | 154 | 13 | Estimate message, tool, image, and context token usage. | 合格 |
| `src/cadr-ai/support/uuid.lisp` | 65 | 4 | Generate monotonic UUIDv7 identifiers from random octets. | 合格 |
| `src/cadr-ai/transport/aws-event-stream.lisp` | 222 | 10 | Decode AWS event-stream frames and issue Bedrock event requests. | 合格 |
| `src/cadr-ai/transport/http.lisp` | 858 | 41 | Implement abortable native HTTP/TLS transport, framing, and normalized errors. | 合格·大体量 |
| `src/cadr-ai/types.lisp` | 239 | 24 | Define provider/model/message/content/tool/event value types and safe printers. | 合格 |
| `src/cadr-ai/websocket.lisp` | 582 | 41 | Implement OpenAI Codex WebSocket framing, pooling, continuation, and provider dispatch. | 合格·大体量 |

### 2.3 `cadr-cli`

| Path | Lines | Definitions | One-sentence responsibility | Verdict |
|---|---:|---:|---|---|
| `src/cadr-cli/arguments.lisp` | 586 | 17 | Parse, validate, resolve, and document the CLI argument contract. | 合格·大体量 |
| `src/cadr-cli/bootstrap/auth.lisp` | 130 | 2 | Project provider-owned authentication options into the native CLI login command. | 合格 |
| `src/cadr-cli/bootstrap/commands.lisp` | 2,058 | 4 | Construct the agent controller and dispatch CLI modes and slash-command output through one frontend sink. | 合格·大体量 |
| `src/cadr-cli/bootstrap/main.lisp` | 140 | 2 | Handle package/credential preflight, parse arguments, and enter the selected CLI path. | 合格 |
| `src/cadr-cli/bootstrap/sessions.lisp` | 1,367 | 35 | Resolve, create, switch, fork, export, and mutate CLI sessions and their tree lifecycle. | 合格·大体量 |
| `src/cadr-cli/bootstrap/settings.lisp` | 725 | 13 | Resolve agent directories, trust, settings, resources, runtime reload, and the effective system prompt. | 合格·大体量 |
| `src/cadr-cli/bootstrap/tools.lisp` | 89 | 8 | Construct the baseline tool set and its prompt metadata. | 合格 |
| `src/cadr-cli/build-support.lisp` | 14 | 2 | Supply the native-image save arguments and executable entry point. | 合格 |
| `src/cadr-cli/config.lisp` | 287 | 21 | Resolve legacy CLI provider configuration and auth commands. | 合格 |
| `src/cadr-cli/support/atomic-write.lisp` | 5 | 1 | Retain the CLI compatibility entry point while delegating atomic replacement to `cadr-core`. | 合格 |
| `src/cadr-cli/support/changelog-share.lisp` | 347 | 10 | Strip terminal styling, parse changelogs, and publish the resulting session share. | 合格 |
| `src/cadr-cli/support/event-bus.lisp` | 40 | 5 | Own the process-local event bus and its error sink. | 合格 |
| `src/cadr-cli/support/external-editor.lisp` | 20 | 1 | Round-trip text through the configured external editor. | 合格 |
| `src/cadr-cli/support/file-watcher.lisp` | 69 | 6 | Poll one file signature and close its worker through bounded cleanup. | 合格 |
| `src/cadr-cli/support/headers.lisp` | 75 | 4 | Merge provider attribution and request header sources. | 合格 |
| `src/cadr-cli/support/html.lisp` | 64 | 5 | Escape and validate HTML-facing strings and shell quoting. | 合格 |
| `src/cadr-cli/support/model-help.lisp` | 24 | 6 | Construct provider/model login help and missing-model diagnostics. | 合格 |
| `src/cadr-cli/support/paths.lisp` | 119 | 6 | Parse file URLs and normalize user path input without changing caller display policy. | 合格 |
| `src/cadr-cli/support/resume-version-git.lisp` | 227 | 9 | Format resume commands and parse versioned Git sources. | 合格 |
| `src/cadr-cli/support/shell-process.lisp` | 132 | 12 | Discover shell configuration and manage detached process trees. | 合格 |
| `src/cadr-cli/support/threads.lisp` | 6 | 1 | Retain the CLI cleanup entry point while delegating policy to `cadr-core`. | 合格 |
| `src/cadr-cli/support/timings.lisp` | 46 | 6 | Record and print opt-in startup timing namespaces. | 合格 |
| `src/cadr-cli/crash.lisp` | 59 | 4 | Bind CLI-specific secret discovery and redaction into the fatal-condition boundary. | 合格 |
| `src/cadr-cli/extensions/commands.lisp` | 56 | 3 | Dispatch extension commands and prompt-template expansion. | 合格 |
| `src/cadr-cli/extensions/discovery.lisp` | 212 | 11 | Define extension source/manager records and discover precedence-ordered sources. | 合格 |
| `src/cadr-cli/extensions/installer.lisp` | 211 | 9 | Validate, stage, clone, and install opt-in extension packages. | 合格 |
| `src/cadr-cli/extensions/loader.lisp` | 621 | 18 | Own extension/infrastructure output sinks, local dependency loading, UI wiring, and reload lifecycle. | 合格 |
| `src/cadr-cli/extensions/llama/client.lisp` | 473 | 26 | Implement llama-server HTTP operations and progress polling. | 合格·大体量 |
| `src/cadr-cli/extensions/llama/extension.lisp` | 316 | 11 | Bind llama commands and catalog refresh into the extension API. | 合格·大体量 |
| `src/cadr-cli/extensions/llama/huggingface.lisp` | 279 | 14 | Search and inspect Hugging Face GGUF artifacts. | 合格 |
| `src/cadr-cli/extensions/llama/provider.lisp` | 322 | 11 | Project llama-server as a session-local native provider. | 合格·大体量 |
| `src/cadr-cli/interactive/components/loaders.lisp` | 151 | 14 | Own dynamic-border and bordered-loader component primitives. | 合格 |
| `src/cadr-cli/interactive/components/countdown.lisp` | 91 | 7 | Own deterministic countdown timer state, rendering, and ticking. | 合格 |
| `src/cadr-cli/interactive/components/armin.lisp` | 270 | 16 | Own the Armin animated component and its frame lifecycle. | 合格 |
| `src/cadr-cli/interactive/components/daxnuts.lisp` | 169 | 14 | Own the Daxnuts animated component and its frame lifecycle. | 合格 |
| `src/cadr-cli/interactive/components/announcement.lisp` | 41 | 2 | Compose the Earendil announcement component. | 合格 |
| `src/cadr-cli/interactive/clipboard.lisp` | 450 | 22 | Own platform clipboard text/image discovery, reading, and writes. | 合格·大体量 |
| `src/cadr-cli/interactive/footer.lisp` | 537 | 23 | Own footer path/usage/status projection and asynchronous Git branch data. | 合格·大体量 |
| `src/cadr-cli/interactive/images.lisp` | 229 | 8 | Inspect and process interactive image bytes under model limits. | 合格 |
| `src/cadr-cli/interactive/state.lisp` | 281 | 11 | Own mutable TUI entry, overlay, status, theme, and root-state records. | 合格 |
| `src/cadr-cli/interactive/status.lisp` | 464 | 26 | Own startup input, status projection, render coordination, spinners, and account warnings. | 合格 |
| `src/cadr-cli/interactive/syntax.lisp` | 1,076 | 33 | Implement baseline-compatible deterministic syntax highlighting. | 合格·大体量 |
| `src/cadr-cli/interactive/theme.lisp` | 215 | 11 | Detect, resolve, export, and discover interactive themes. | 合格 |
| `src/cadr-cli/interactive/themes.lisp` | 374 | 12 | Watch, validate, and apply live TUI theme files and terminal theme changes. | 合格 |
| `src/cadr-cli/interactive/tool-render-session.lisp` | 61 | 3 | Own incremental tool-render session state and projection. | 合格 |
| `src/cadr-cli/interactive/user-bash.lisp` | 213 | 9 | Render and update direct user bash executions independently of agent tool calls. | 合格 |
| `src/cadr-cli/interactive/transcript.lisp` | 1,045 | 29 | Project every session entry and assistant/user/custom transcript component. | 合格·大体量 |
| `src/cadr-cli/interactive/tool-rendering.lisp` | 955 | 23 | Project agent tool calls/results and reduce agent events into TUI state. | 合格·大体量 |
| `src/cadr-cli/interactive/entries.lisp` | 270 | 18 | Own append, replacement, invalidation, and status-entry mutation. | 合格 |
| `src/cadr-cli/interactive/pending-messages.lisp` | 68 | 3 | Render and restore queued steering and follow-up input. | 合格 |
| `src/cadr-cli/interactive/frame.lisp` | 368 | 7 | Compose transcript, status, widgets, overlays, editor, and footer into one frame. | 合格 |
| `src/cadr-cli/interactive/extension-ui.lisp` | 503 | 21 | Bridge extension UI requests and custom components into the live TUI. | 合格 |
| `src/cadr-cli/interactive/autocomplete.lisp` | 217 | 11 | Construct command/path autocomplete and extension shortcut routing. | 合格 |
| `src/cadr-cli/interactive/controller.lisp` | 2,239 | 14 | Own the interactive lifecycle, slash-command routing, input loop, and cleanup. | 合格·大体量 |
| `src/cadr-cli/interactive/selectors/common.lisp` | 346 | 21 | Own composable selector chrome, viewport/count, input, fuzzy matching, and wrap navigation. | 合格 |
| `src/cadr-cli/interactive/selectors/sessions.lisp` | 1,342 | 47 | Search, mutate, navigate, and render resumable session trees. | 合格·大体量 |
| `src/cadr-cli/interactive/selectors/tree.lisp` | 1,747 | 57 | Filter, navigate, edit, and render the branching session tree overlay. | 合格·大体量 |
| `src/cadr-cli/interactive/selectors/settings.lisp` | 848 | 27 | Edit settings and theme submenus through the shared selector frame. | 合格·大体量 |
| `src/cadr-cli/interactive/selectors/auth.lisp` | 576 | 25 | Select authentication methods/providers and collect API keys. | 合格·大体量 |
| `src/cadr-cli/interactive/selectors/models.lisp` | 1,190 | 58 | Search, choose, scope, enable, and order models. | 合格·大体量 |
| `src/cadr-cli/interactive/selectors/trust.lisp` | 269 | 10 | Choose and persist project trust decisions. | 合格 |
| `src/cadr-cli/interactive/selectors/fork.lisp` | 147 | 7 | Choose the user-message boundary for a forked session. | 合格 |
| `src/cadr-cli/media.lisp` | 1,236 | 55 | Decode, orient, resample, and encode PNG/JPEG image bytes under model limits. | 合格·大体量 |
| `src/cadr-cli/migration.lisp` | 127 | 10 | Safely migrate the legacy user-data directory with explicit consent. | 合格 |
| `src/cadr-cli/models/auth-storage.lisp` | 376 | 24 | Serialize locked auth-store updates and runtime credential overrides. | 合格 |
| `src/cadr-cli/models/credential-print.lisp` | 208 | 6 | Parse and execute the one-shot credential-print command without exposing secrets. | 合格 |
| `src/cadr-cli/models/matching.lisp` | 413 | 17 | Resolve exact, partial, scoped, and globbed model selections. | 合格 |
| `src/cadr-cli/models/registry.lisp` | 771 | 34 | Build, refresh, authenticate, and project the cohesive runtime model registry. | 合格·大体量 |
| `src/cadr-cli/models/store.lisp` | 165 | 8 | Read and mutate provider-scoped `models.json` entries. | 合格 |
| `src/cadr-cli/modes/print.lisp` | 264 | 8 | Render agent events for print and JSON command-line modes. | 合格 |
| `src/cadr-cli/modes/rpc/commands.lisp` | 478 | 3 | Validate and dispatch the closed RPC command set through the shared response sink. | 合格 |
| `src/cadr-cli/modes/rpc/jsonl.lisp` | 123 | 16 | Read/write and validate the RPC JSONL envelope. | 合格 |
| `src/cadr-cli/modes/rpc/mode.lisp` | 95 | 3 | Own RPC line dispatch, event subscription, stream lifetime, and shutdown. | 合格 |
| `src/cadr-cli/modes/rpc/models.lisp` | 221 | 13 | Project, select, and cycle RPC models and thinking levels. | 合格 |
| `src/cadr-cli/modes/rpc/prompt-bash.lisp` | 225 | 7 | Start, steer, abort, and observe RPC prompt and bash work. | 合格 |
| `src/cadr-cli/modes/rpc/sessions.lisp` | 283 | 10 | Create, switch, fork, compact, and inspect RPC sessions and trees. | 合格 |
| `src/cadr-cli/modes/rpc/ui.lisp` | 301 | 11 | Bridge extension UI requests to RPC dialogs with cancellation and timeout. | 合格·大体量 |
| `src/cadr-cli/output-accumulator.lisp` | 199 | 17 | Accumulate split UTF-8 process output into a bounded tail and spill file. | 合格 |
| `src/cadr-cli/packages/config-selector.lisp` | 1,529 | 70 | Own the standalone config selector, resource projection, and scoped persistence interaction. | 合格·大体量 |
| `src/cadr-cli/packages/commands.lisp` | 863 | 23 | Parse package commands and execute help/list/install/update/remove workflows. | 合格 |
| `src/cadr-cli/packages/manifest.lisp` | 186 | 5 | Parse package manifests and project resource paths. | 合格 |
| `src/cadr-cli/packages/settings.lisp` | 214 | 10 | Persist, remove, deduplicate, and materialize configured package records. | 合格 |
| `src/cadr-cli/packages/source.lisp` | 348 | 13 | Parse and canonicalize npm, Git, SSH, and local package sources. | 合格 |
| `src/cadr-cli/package.lisp` | 285 | 1 | Declare the public `cadr-cli` package surface. | 合格 |
| `src/cadr-cli/remote-repl.lisp` | 67 | 8 | Manage the opt-in Slynk server and active-agent binding. | 合格 |
| `src/cadr-cli/repl.lisp` | 102 | 3 | Run the basic line-oriented REPL mode. | 合格 |
| `src/cadr-cli/resource-loader.lisp` | 322 | 13 | Discover and reload scoped prompts, skills, themes, context, and extensions. | 合格·大体量 |
| `src/cadr-cli/sdk/agent-session.lisp` | 475 | 16 | Construct and expose the in-process agent-session facade. | 合格 |
| `src/cadr-cli/sdk/cache-version.lisp` | 441 | 25 | Detect cache anomalies, restore proxy state, and perform release/version checks. | 合格 |
| `src/cadr-cli/sdk/model-service.lisp` | 355 | 19 | Implement the SDK model runtime and shared atomic credential path. | 合格 |
| `src/cadr-cli/sdk/resource-service.lisp` | 368 | 13 | Implement reloadable SDK resource discovery and overrides. | 合格 |
| `src/cadr-cli/sdk/session-manager.lisp` | 107 | 8 | Resolve, create, continue, open, and list SDK sessions. | 合格 |
| `src/cadr-cli/sdk/session-runtime.lisp` | 279 | 15 | Own replaceable SDK session services and runtime disposal. | 合格 |
| `src/cadr-cli/sdk/settings-service.lisp` | 181 | 20 | Adapt persistent and in-memory settings to the SDK contract. | 合格 |
| `src/cadr-cli/sdk/system-prompt.lisp` | 204 | 5 | Build the SDK system prompt and extension-aware provider stream. | 合格 |
| `src/cadr-cli/settings/config-values.lisp` | 198 | 15 | Resolve environment and command-backed configuration values and JSON merges. | 合格 |
| `src/cadr-cli/settings/manager.lisp` | 407 | 24 | Own layered settings reload, mutation, defaults, and keybindings. | 合格 |
| `src/cadr-cli/settings/trust.lisp` | 172 | 10 | Persist and resolve inherited project-trust decisions. | 合格 |
| `src/cadr-cli/system-prompt.lisp` | 23 | 3 | Resolve the default, replacement, and appended system prompt. | 合格 |
| `src/cadr-cli/tool-manager.lisp` | 283 | 24 | Locate, download, extract, and quarantine optional host tools. | 合格 |
| `src/cadr-cli/tools/bash.lisp` | 438 | 16 | Execute bash with live output, process-group abort/timeout, truncation, and tool wrapping. | 合格·大体量 |
| `src/cadr-cli/tools/edit.lisp` | 693 | 30 | Match replacements and produce/apply exact edit diffs. | 合格·大体量 |
| `src/cadr-cli/tools/find.lisp` | 93 | 3 | Implement the bounded find tool. | 合格 |
| `src/cadr-cli/tools/glob.lisp` | 213 | 13 | Implement recursive globbing with parseable gitignore rules. | 合格 |
| `src/cadr-cli/tools/grep.lisp` | 162 | 3 | Implement bounded regex/literal grep with context. | 合格 |
| `src/cadr-cli/tools/ls.lisp` | 94 | 3 | Implement the bounded directory-listing tool. | 合格 |
| `src/cadr-cli/tools/path.lisp` | 308 | 31 | Normalize tool paths/arguments/errors and serialize file mutations. | 合格·大体量 |
| `src/cadr-cli/tools/read.lisp` | 141 | 2 | Implement the bounded line-oriented read tool. | 合格 |
| `src/cadr-cli/tools/write.lisp` | 56 | 2 | Implement the UTF-8 write tool and baseline result count. | 合格 |
| `src/cadr-cli/truncation.lisp` | 80 | 12 | Adapt agent truncation results to the CLI tool-result detail contract. | 合格 |

### 2.4 `cadr-evals`

| Path | Lines | Definitions | One-sentence responsibility | Verdict |
|---|---:|---:|---|---|
| `src/cadr-evals/artifacts.lisp` | 176 | 11 | Validate, hash, persist, and reference eval artifacts. | 合格 |
| `src/cadr-evals/harness-table.lisp` | 359 | 17 | Define eval harness rows/tables, canonical group keys, and iteration wrappers. | 合格·大体量 |
| `src/cadr-evals/harness.lisp` | 736 | 29 | Run a coding-agent eval lifecycle and normalize transcript, usage, and cleanup. | 合格·大体量 |
| `src/cadr-evals/main.lisp` | 154 | 5 | Parse eval CLI arguments, dispatch suites, and validate result shape. | 合格 |
| `src/cadr-evals/package.lisp` | 100 | 2 | Declare the public eval package and session snapshot artifact name. | 合格 |
| `src/cadr-evals/reporter.lisp` | 315 | 14 | Persist eval case records and finish a harness report. | 合格·大体量 |
| `src/cadr-evals/suites.lisp` | 479 | 21 | Define the smoke and extension-authoring eval suites and judges. | 合格·大体量 |
| `src/cadr-evals/summary.lisp` | 733 | 31 | Pair observations, compute correctness/efficiency summaries, and render comparison reports. | 合格·大体量 |

### 2.5 `cadr-protocol`

| Path | Lines | Definitions | One-sentence responsibility | Verdict |
|---|---:|---:|---|---|
| `src/cadr-protocol/cbor.lisp` | 508 | 37 | Encode and decode bounded RFC 8949 CBOR values. | 合格·大体量 |
| `src/cadr-protocol/codec.lisp` | 121 | 10 | Compose message validation, CBOR, and framing into incremental client/server codecs. | 合格 |
| `src/cadr-protocol/framing.lisp` | 145 | 15 | Encode and incrementally decode bounded length-prefixed frames. | 合格 |
| `src/cadr-protocol/package.lisp` | 33 | 1 | Declare the public `cadr-protocol` package surface. | 合格 |
| `src/cadr-protocol/schema.lisp` | 620 | 33 | Validate and parse every protocol v2 client/server message shape. | 合格·大体量 |

### 2.6 `cadr-server`

| Path | Lines | Definitions | One-sentence responsibility | Verdict |
|---|---:|---:|---|---|
| `src/cadr-server/config.lisp` | 51 | 6 | Resolve server state, auth, instance, and socket paths. | 合格 |
| `src/cadr-server/handler.lisp` | 101 | 1 | Dispatch one local server request to supervisor operations. | 合格 |
| `src/cadr-server/ipc.lisp` | 329 | 14 | Serve and call the framed Unix-socket server transport. | 合格·大体量 |
| `src/cadr-server/main.lisp` | 211 | 10 | Parse server CLI operations and run server or stream-client entry points. | 合格 |
| `src/cadr-server/package.lisp` | 59 | 1 | Declare the public `cadr-server` package surface. | 合格 |
| `src/cadr-server/protocol.lisp` | 49 | 5 | Encode/decode the server control-plane JSON messages. | 合格 |
| `src/cadr-server/radius.lisp` | 744 | 44 | Manage opt-in Radius registration, heartbeat, recovery, and redacted token use. | 合格·大体量 |
| `src/cadr-server/rpc-process.lisp` | 419 | 26 | Own one child `cadr --mode rpc` process, pending calls, event/UI callbacks, and teardown. | 合格·大体量 |
| `src/cadr-server/storage.lisp` | 197 | 15 | Persist server machine and instance records. | 合格 |
| `src/cadr-server/supervisor.lisp` | 609 | 27 | Supervise live RPC child instances, streams, persistence, and recovery. | 合格·大体量 |
| `src/cadr-server/types.lisp` | 30 | 4 | Define machine/instance record values and timestamps. | 合格 |

### 2.7 `cadr-storage`

| Path | Lines | Definitions | One-sentence responsibility | Verdict |
|---|---:|---:|---|---|
| `src/cadr-storage/package.lisp` | 19 | 1 | Declare the minimal SQLite adapter package. | 合格 |
| `src/cadr-storage/sqlite.lisp` | 12 | 3 | Wrap SQLite open, close, and migration operations. | 合格 |

### 2.8 `cadr-tui`

| Path | Lines | Definitions | One-sentence responsibility | Verdict |
|---|---:|---:|---|---|
| `src/cadr-tui/autocomplete.lisp` | 595 | 37 | Parse completion context and provide cancellable command/file suggestions and application. | 合格·大体量 |
| `src/cadr-tui/components/image.lisp` | 45 | 1 | Render image bytes or the baseline text fallback. | 合格 |
| `src/cadr-tui/components/markdown.lisp` | 1,110 | 32 | Render Markdown, ANSI tables, inline spans, and visually truncated text. | 合格·大体量 |
| `src/cadr-tui/components/select-list.lisp` | 308 | 8 | Own filterable two-column selection state, navigation, and rendering. | 合格 |
| `src/cadr-tui/components/status.lisp` | 246 | 6 | Render footer and status-bar projections. | 合格 |
| `src/cadr-tui/components/tool-block.lisp` | 609 | 21 | Render tool titles, previews, diffs, elapsed time, and result states. | 合格·大体量 |
| `src/cadr-tui/composition/loaders.lisp` | 238 | 20 | Own animated and cancellable loader components using the shared cleanup policy. | 合格 |
| `src/cadr-tui/composition/protocol.lisp` | 128 | 30 | Define the component, focus, container, render, event, and disposal protocols. | 合格 |
| `src/cadr-tui/composition/rich-content.lisp` | 276 | 10 | Compose cached Markdown and image components. | 合格 |
| `src/cadr-tui/composition/root.lisp` | 317 | 23 | Own the TUI root, focus routing, render scheduling, and overlay stack. | 合格 |
| `src/cadr-tui/composition/settings-list.lisp` | 459 | 30 | Implement settings-list behavior and the shared editor-component adapters. | 合格·大体量 |
| `src/cadr-tui/composition/text-box.lisp` | 275 | 23 | Implement text, spacer, box, and truncated-text components. | 合格 |
| `src/cadr-tui/editor.lisp` | 1,978 | 87 | Implement the grapheme-aware multiline editor, history, editing, autocomplete, wrapping, and rendering. | 合格·大体量 |
| `src/cadr-tui/fuzzy.lisp` | 117 | 6 | Score and filter fuzzy text matches. | 合格 |
| `src/cadr-tui/input-component.lisp` | 419 | 19 | Implement the grapheme-aware single-line Input component and software cursor. | 合格·大体量 |
| `src/cadr-tui/input.lisp` | 367 | 17 | Incrementally decode terminal bytes, bracketed paste, and control sequences into input events. | 合格·大体量 |
| `src/cadr-tui/keybindings.lisp` | 144 | 11 | Store configurable keybinding definitions and resolve conflicts/actions. | 合格 |
| `src/cadr-tui/keys.lisp` | 588 | 32 | Parse and canonicalize Kitty, xterm, modified, and legacy key encodings. | 合格·大体量 |
| `src/cadr-tui/kill-ring.lisp` | 38 | 5 | Implement kill-ring push/peek/rotate operations. | 合格 |
| `src/cadr-tui/native-modifiers.lisp` | 78 | 11 | Query Apple Terminal modifier flags through CoreGraphics when supported. | 合格 |
| `src/cadr-tui/overlay.lisp` | 481 | 30 | Resolve overlay geometry, composite frames, and manage overlay focus/stack state. | 合格·大体量 |
| `src/cadr-tui/package.lisp` | 343 | 1 | Declare the public `cadr-tui` package surface. | 合格 |
| `src/cadr-tui/renderer/alt-screen.lisp` | 293 | 7 | Prepare, crop, render, and restore alternate-screen documents. | 合格 |
| `src/cadr-tui/renderer/lifecycle-input.lisp` | 737 | 27 | Own renderer state, lifecycle, viewport, selection, mouse, and input dispatch. | 合格·大体量 |
| `src/cadr-tui/renderer/main-screen.lisp` | 448 | 15 | Render incremental main-screen frames and manage terminal images. | 合格·大体量 |
| `src/cadr-tui/renderer/terminal-protocol.lisp` | 74 | 23 | Define the terminal output, cursor, lifecycle, query, and capability protocol. | 合格 |
| `src/cadr-tui/renderer/virtual-terminal.lisp` | 167 | 12 | Implement the deterministic in-memory terminal and screen snapshot. | 合格 |
| `src/cadr-tui/stdin-buffer.lisp` | 229 | 11 | Buffer terminal bytes until complete atomic control/key sequences can be emitted. | 合格 |
| `src/cadr-tui/terminal-colors.lisp` | 191 | 15 | Parse terminal background/color-scheme/cell-size responses. | 合格 |
| `src/cadr-tui/terminal-image.lisp` | 677 | 43 | Detect image capabilities, encode Kitty/iTerm images, inspect dimensions, crop, link, and fall back. | 合格·大体量 |
| `src/cadr-tui/terminal.lisp` | 882 | 45 | Own the real process terminal lifecycle, raw mode, keyboard protocol, Apple normalization, queries, and progress. | 合格·大体量 |
| `src/cadr-tui/theme.lisp` | 560 | 37 | Resolve semantic theme colors/styles and terminal color downgrades. | 合格·大体量 |
| `src/cadr-tui/threads.lisp` | 35 | 1 | Provide bounded cleanup of one SBCL thread. | 合格 |
| `src/cadr-tui/undo-stack.lisp` | 20 | 5 | Implement undo-stack push/pop/clear operations. | 合格 |
| `src/cadr-tui/unicode.lisp` | 1,213 | 49 | Implement terminal Unicode/grapheme/ANSI width, slicing, truncation, and wrapping semantics. | 合格·大体量 |
| `src/cadr-tui/word-navigation.lisp` | 141 | 8 | Move over whitespace, punctuation, CJK, and editor-atomic word segments. | 合格 |

## 3. Verdict summary and expected distribution

| System | 合格 | 合格·大体量 | 应拆分 | 应合并 | Total |
|---|---:|---:|---:|---:|---:|
| `cadr-agent` | 27 | 13 | 0 | 0 | 40 |
| `cadr-ai` | 46 | 15 | 0 | 0 | 61 |
| `cadr-cli` | 83 | 25 | 0 | 0 | 108 |
| `cadr-core` | 6 | 0 | 0 | 0 | 6 |
| `cadr-evals` | 3 | 5 | 0 | 0 | 8 |
| `cadr-protocol` | 3 | 2 | 0 | 0 | 5 |
| `cadr-server` | 7 | 4 | 0 | 0 | 11 |
| `cadr-storage` | 2 | 0 | 0 | 0 | 2 |
| `cadr-tui` | 26 | 10 | 0 | 0 | 36 |
| **Total** | **203** | **74** | **0** | **0** | **277** |

No production file remains in `应拆分` or `应合并`. B11 completed the remaining
25 named AI owners after establishing the fixed-baseline provider matrix. This
is not a quota result: every target below names a verified responsibility, and
the tests reject a missing owner or a surviving mixed file.

| System | Failing files | Expected target files | Net files |
|---|---:|---:|---:|
| `cadr-agent` | 0 | 0 | +0 |
| `cadr-ai` | 0 | 0 | +0 |
| `cadr-cli` | 0 | 0 | +0 |
| `cadr-tui` | 0 | 0 | +0 |
| **Total** | **0** | **0** | **+0** |

At current boundaries the physical distribution is 162 files below 300 lines,
76 at 300–699, 24 at 700–999, and 15 at or above 1,000;
only generated `models.generated.lisp` remains at or above 3,000. Average file
size is now 380 lines and the under-300 share is about 58%. The modest
percentage is honest:
cohesive files such as the multiline
editor, Unicode engine, image codec, protocol codecs, and vendored assets are
not chopped up to make the chart prettier.

### 3.1 Cohesion map for every `应拆分` file

| Current file | Expected named responsibilities (count) |
|---|---|
| `agent/extensions.lisp` | **Completed in B9:** `extensions/{context,api,registration,snapshot,rendering,providers,commands,lifecycle}.lisp` (8). |
| `agent/loop.lisp` | **Completed in B8:** `loop/{events,tool-execution,turns,agent-loop}.lisp` (4). |
| `agent/session.lisp` | **Completed in B8:** `session/{codec,journal,discovery,migration,export-html}.lisp` (5). |
| `agent/storage.lisp` | **Completed in B8:** `storage/{protocol,memory,harness,jsonl}.lisp` (4). |
| `ai/capabilities.lisp` | **Completed in B10:** `capabilities/{streaming-json,event-stream,grammar-tools,session-resources,proxy-config,image-runtime}.lisp` (6). |
| `ai/http.lisp` | **Completed in B10:** `transport/{http,aws-event-stream}.lisp` (2). |
| `ai/models-runtime.lisp` | **Completed in B10:** `runtime/{models,faux-provider}.lisp` (2). |
| `ai/oauth-flows.lisp` | **Completed in B11:** `oauth/providers/{xai,kimi,github-copilot,openrouter,radius,openai-device,anthropic}.lisp` (7). |
| `ai/oauth.lisp` | **Completed in B11:** `oauth/{pkce,callback,page,openai-anthropic}.lisp` (4). |
| `ai/provider-auth.lisp` | **Completed in B11:** `auth/{bedrock,vertex,device-code,github-copilot,radius-cloudflare}.lisp` (5). |
| `ai/providers/independent.lisp` | **Completed in B11:** `providers/{azure-openai,codex,mistral,vertex,bedrock,pi-messages}.lisp` (6). |
| `ai/registry.lisp` | **Completed in B11:** `providers/{definitions,registry,runtime-projection}.lisp` (3). |
| `ai/utilities.lisp` | **Completed in B10:** `support/{threads,release,retry,token-estimation,overflow,grammar-coercion,uuid}.lisp` (7). |
| `cli/core-support.lisp` | **Completed in B4:** `support/{model-help,event-bus,timings,file-watcher,paths,shell-process}.lisp` (6). |
| `cli/extensions.lisp` | **Completed in B4:** `extensions/{discovery,loader,commands,installer}.lisp` (4). |
| `cli/interactive-components.lisp` | **Completed in B6:** `interactive/components/{loaders,countdown,armin,daxnuts,announcement}.lisp` (5). |
| `cli/interactive-services.lisp` | **Completed in B2:** `interactive/selectors/{common,sessions,tree,settings,auth,models,trust,fork}.lisp` (8); `common` was implemented before the domain extraction. |
| `cli/main.lisp` | **Completed in B5:** `bootstrap/{tools,sessions,settings,auth,commands,main}.lisp` (6). |
| `cli/model-services.lisp` | **Completed in B4:** `models/{auth-storage,store,registry,matching,credential-print}.lisp` (5). |
| `cli/modes/rpc/mode.lisp` | **Completed in B5:** `modes/rpc/{models,prompt-bash,sessions,commands,mode}.lisp` (5). |
| `cli/package-manager.lisp` | **Completed in B4:** `packages/{source,settings,manifest,config-selector,commands}.lisp` (5). |
| `cli/sdk-services.lisp` | **Completed in B4:** `sdk/{cache-version,system-prompt,settings-service,resource-service,model-service}.lisp` (5). |
| `cli/sdk.lisp` | **Completed in B4:** `sdk/{session-manager,agent-session,session-runtime}.lisp` (3). |
| `cli/settings.lisp` | **Completed in B4:** `settings/{config-values,manager,trust}.lisp` (3). |
| `cli/tui.lisp` | **Completed in B6:** `interactive/{state,status,user-bash,transcript,tool-rendering,entries,pending-messages,frame,extension-ui,autocomplete,themes,controller}.lisp` (12); the existing B1 `status` and `transcript` owners absorbed their controller-side responsibilities. |
| `cli/utilities.lisp` | **Completed in B4:** `support/{threads,atomic-write,changelog-share,html,resume-version-git,headers,external-editor}.lisp` (7). |
| `tui/components.lisp` | **Completed in B7:** `components/{markdown,image,tool-block,status,select-list}.lisp` (5). |
| `tui/composition.lisp` | **Completed in B7:** `composition/{protocol,text-box,rich-content,settings-list,loaders,root}.lisp` (6). |
| `tui/renderer.lisp` | **Completed in B7:** `renderer/{terminal-protocol,virtual-terminal,lifecycle-input,main-screen,alt-screen}.lisp` (5). |

## 4. Directory ownership rules

The new hierarchy is semantic, not a mirror of TypeScript:

- `cadr-cli/interactive/` owns interactive-mode state, transcript projection,
  UI services, and the controller.  Its `selectors/` and `components/`
  subdirectories contain independently nameable selector/component families.
- `cadr-cli/modes/` owns non-interactive transport modes; `rpc/` command domains
  stay below it.  Generic settings, packages, models, extensions, and SDK
  services do not live under `interactive/` merely because the TUI calls them.
- `cadr-agent/session/`, `storage/`, `loop/`, and `extensions/` each own one
  agent-domain protocol plus its implementations; backend-specific SQLite stays
  separate from generic storage.
- `cadr-ai/providers/` contains two different but explicit kinds of source:
  declarative provider definitions and one file per wire protocol.  Provider
  brands sharing a protocol remain data rows, not 38 near-empty code files.
  `oauth/providers/` and `auth/` hold genuinely provider-specific behavior.
- `cadr-tui/components/`, `composition/`, and `renderer/` own reusable terminal
  primitives only; coding-agent copy and command behavior stay in `cadr-cli`.
- `cadr-core/` owns only cross-system, product-neutral policy primitives:
  bounded thread cleanup, component-local cancellation, atomic file replacement,
  redacted object printing, and UTC time conversion. Product, provider, session,
  and UI policy must stay in their domain system and consume these primitives.

ASDF files list modules in dependency order: value types/protocols first,
shared helpers next, implementations next, controllers last.  Moving a form
must not create exports merely to compensate for a false directory boundary.

## 5. Required anomaly decisions

### 5.1 `cadr-server`: intentional process boundary, not copied agent logic

The dependency difference is intentional and should remain.

- `cadr-server.asd:5-7` depends on `cadr-ai` only for JSON, HTTP/auth, UUID, and
  Radius primitives.  It does not load an agent or coding session in-process.
- `src/cadr-server/rpc-process.lisp:265-307` starts a child Cadr in RPC mode;
  `supervisor.lisp:259-328` owns only child lifecycle and persisted instance
  metadata.  Agent prompting, tools, session context, and extensions stay in
  that child's `cadr-cli`/`cadr-agent` runtime.
- A full top-level-name comparison found only `current-iso8601` shared with
  `cadr-agent`, and only the generic names `main` and `rpc-command-id` shared
  with `cadr-cli`; there is no duplicated agent/session implementation.
- The extra mass is concrete Cadr server functionality: Radius presence is 744
  lines, RPC child isolation 419, supervision/recovery 609, and Unix-socket IPC
  329.  Calling that duplication would be false.

Therefore the shallower dependency is an intentional implementation difference:
the server is a process supervisor around the already-frozen RPC contract rather
than an in-process coding-agent host.  Adding `cadr-agent` or `cadr-cli` would
collapse the process boundary without removing code and is rejected.

### 5.2 Providers: the headline comparison was apples to half an apple

The draft's `82 files / 2,111 lines` excludes baseline `providers/all.ts` and,
more importantly, excludes all 31 API implementation files.  At fixed baseline
`74caa2649` the actual comparison is:

| Surface | Files | Lines | Meaning |
|---|---:|---:|---|
| pi `providers/` excluding `all.ts` | 82 | 2,111 | Brand/model declarations |
| pi `api/` | 31 | 10,566 | Wire protocols, auth transforms, reducers |
| pi combined | 113 | 12,677 | Fair declaration + protocol denominator |
| Cadr `providers/` | 13 | 5,643 | Wire protocols plus validated declaration/registry/runtime projection |
| Cadr `providers/definitions.lisp` declaration rows | 38 rows | 963-file total | Brand/provider data plus field validation |

Cadr has not written twice the provider boilerplate. It does the Lisp-native
thing: 38 brands are validated rows in one `provider-definition` table, while
protocol files implement shared wire behavior. B11 closed the four defects the
audit identified:

1. The six protocols formerly in `providers/independent.lisp` have exact files.
2. Declarations, lookup/construction, and runtime projection have exact files.
3. Provider identity/auth fields and callback strategy identities live in the
   validated declaration; ambient environment names are derived from it.
4. Protocol construction has one branch per declared protocol; the stray
   duplicate Google clause is gone with the retired mixed registry.

The convergence is a validated declarative provider schema that owns names,
login labels/instructions, endpoints, auth methods, environment inputs, and
login/refresh/auth callbacks once.  One runtime constructor consumes it.  Each
wire protocol remains a real file; Cadr must not recreate pi's 82 tiny brand
wrappers merely to resemble TypeScript.

The required divergence safety net is a generated fixed-baseline fixture with
one row per provider and assertions for every field above, plus protocol payload
and event fixtures per `provider × thinking level`.  A row or callback changed
upstream must turn the gate red.

### 5.3 Freeze status

The historical whole-object freeze of `src/cadr-ai` no longer exists: approved
Goal 13 commits changed provider streaming, OAuth, transport, and crash handling.
The active freezes are narrower and still binding:

- extension public export text SHA-256
  `61eb1b623f784b3a8f0f6fe6791c65ebe991ff314ed1d969b82f3edd57646f18`;
- 34-event source block SHA-256
  `12f79b21e0e25495cb023baaf21b26f6cf9a891881b26602f6553f80af54887a`;
- public package exports, wire/payload/session contracts, and all observable
  behavior.

Internal file moves in `src/cadr-ai` are therefore eligible, but provider
declaration changes need the baseline-derived field matrix above, and any new
export/event or observable change is blocked for a separate proposal.

## 6. Repeated manual decisions

The threshold is the one from Goal 14: at least three handwritten decisions,
where one omission produces a user-visible defect.  This finds deeper risks
than the file table.

| Decision repeated by hand | Current locations | Failure if one copy drifts | Prior bug | Convergence |
|---|---|---|---|---|
| Bounded thread cleanup | **Converged in B3:** `cadr-core/threads.lisp` owns bounded cleanup; `cli/support/threads.lisp` is a branch-free compatibility delegate and raw active waits require an explicit reason. | Exit hangs, orphaned worker, or forced termination at the wrong time | Goal 13 exit deadlock | Source gates reject unannotated cleanup joins outside the core owner. |
| Cancellation state and propagation | **Converged in B3:** `cadr-core/cancellation.lisp` owns component-local state, abort, predicate adaptation, and bounded waiting; `ai/transport/http.lisp`, `ai/runtime/models.lisp`, `agent/extensions/context.lisp`, `tui/autocomplete.lisp`, and `tui/composition/loaders.lisp` are explicit adapters. Agent lifecycle abort remains a separate product policy. | UI closes while network/listener/tool work continues, or stale work updates a new request | OAuth cancel hang; slow SSE abort; stale autocomplete | Functional tests lock state/wait semantics; a source gate requires every package-boundary adapter to call the core owner. |
| Infrastructure output ownership | **CLI extension side converged in B4 and command/RPC consumers preserved in B5:** `cli/extensions/loader.lisp` owns extension output and infrastructure capture, `bootstrap/commands.lisp` owns frontend mode injection, and `modes/rpc/jsonl.lisp` owns wire emission; process/tool, TUI notice/browser, server Radius, and fatal sinks retain their domain owners. | ASDF, setsid, SSL/SBCL pointers, or internal `session>` labels reach the user channel | setsid, ASDF, SSL, and notice-prefix leaks | Source gates keep each output category with its sink and reject direct JSONL writes from RPC command domains. |
| Selector frame semantics | **Converged in B2:** `cli/interactive/selectors/common.lisp` owns frame sections, semantic borders/titles/input/help, centered viewport/count, and wrap navigation; seven domain owners supply entries and domain callbacks. | One overlay loses cursor, wraps a help glyph, uses the wrong color, spacing, or navigation semantics | Repeated Goal 9 overlay rounds; Goal 14 A0 title/border/cursor | `selector-frame` is the sole shared owner; source gates require every selector family to render through it and delegate wrap navigation. |
| Provider identity/auth metadata | **Converged in B11:** `ai/providers/definitions.lisp` owns 38 validated rows, all static fields, callback strategy identities, and the derived ambient-environment set; `registry.lisp` constructs protocols and `runtime-projection.lisp` consumes the strategies. | Endpoint, login title/instruction, auth source, environment, refresh, or model filtering differs for the same provider | Anthropic generic browser instructions; A0 stored/configured source | The fixed-baseline 38-provider matrix checks every field; source gates reject duplicate/missing rows and mixed legacy owners. |
| Secret-safe object printing | **Converged in B3 and preserved in B4:** `cadr-core/redacted-print.lisp` owns printer declarations; credential-bearing CLI values in `arguments.lisp`, `config.lisp`, `models/auth-storage.lisp`, `models/registry.lisp`, and `interactive/selectors/auth.lisp` use that owner. | A newly printable slot dumps tokens into a condition, crash log, or REPL | Fatal backtrace exposed session state; token non-leak depended on opaque printing | The registry test constructs and prints every declared secret-bearing type with sentinel secrets. |
| Atomic persistence and file modes | **Converged in B3 and preserved in B4:** `cadr-core/atomic-file.lisp` owns replacement and modes; `cli/support/atomic-write.lisp` and `cli/settings/manager.lisp` only select the existing public durability policy. | Torn JSON, refresh-token loss, stale temp files, or world-readable secrets | OAuth refresh/order investigation established atomicity as a hard safety property | Source gates reject handwritten replacement outside the core owner; private auth remains on the shared `0600` path. |
| JavaScript string/byte count semantics | **Converged in B4:** `agent/truncate.lisp` owns UTF-16 code-unit length; `cli/truncation.lisp` is now a direct delegate, while byte/line sizing retains domain adapters. | Tool result counts differ for CJK/emoji or truncation metadata disagrees | Write result counted UTF-8 bytes instead of JS UTF-16 units | B4 rejects a second CLI loop and keeps non-ASCII result fixtures. |
| ISO time and ID formatting | **Bottom-layer conversion exists from B3 and B5 consumes it at the split boundaries:** session export uses `cadr-core:milliseconds-to-utc-iso8601` in `bootstrap/sessions.lisp`; RPC IDs use `cadr-core:unix-milliseconds` in `modes/rpc/jsonl.lisp`.  Package-local compatibility delegates remain where their public semantics differ. | Session discovery, server status, tree labels, or export names drift by timezone/fraction rules | Tree timestamp and export filename parity defects | Fixed vectors guard the core owner; B5 source gates reject restoration of the former cross-package time calls. |

Two apparent repetitions must **not** be collapsed.  Home/path display differs
intentionally between tools, session selector, and tree selector because the
baseline contracts differ; one generic shortening helper would erase those
differences.  Likewise provider protocol implementations should share only
verified wire primitives, not an over-generalized request builder that hides
provider-specific payload semantics.

A small `cadr-core` leaf is the only clean home for SBCL thread cleanup,
cancellation, atomic replace, redacted-printer support, and time formatting:
putting them in `cadr-ai` would break the good `cadr-tui`-does-not-depend-on-AI
boundary.  It adds a shared leaf but no dependency reversal between existing
systems.  Because Goal 14 forbids casual system-graph changes, creating that
leaf is explicitly a Part B decision, not an audit-side implementation.

### Part C B3 implementation status

B3 implemented the approved leaf before any file extraction.  Its modules own
exactly one policy each: `threads` bounds cleanup waits and requires a written
reason for an active unbounded join; `cancellation` owns component-local abort
state and waiting; `atomic-file` owns sibling-temp replacement and explicit
file modes; `redacted-print` owns secret-safe object declarations; `time` owns
UTC millisecond and ISO formatting.  Existing package-local entry points are
compatibility delegates with no policy.  Source gates reject raw production
`join-thread`, handwritten replacement rename, and direct secret-bearing
`print-object` definitions outside these owners.

The remaining repeated decisions keep their approved order: B1 names output
ownership before extracting presentation leaves; B2 establishes
`selector-frame` before extracting selector families; B4 converges CLI sinks
and the duplicate JavaScript metric before service extraction; B5--B10 consume
those owners before their splits; B11 created the fixed-baseline provider
matrix before the declaration owner and provider file split.

### Part C B1 implementation status

B1 extracted only the eight cohesive interactive leaves.  Transcript projection,
status/startup projection, footer/Git data, theme resolution, image processing,
clipboard access, syntax highlighting, and tool-render session state now each
have one exact file owner under `src/cadr-cli/interactive/`.  The move preserved
the existing package-private symbols and introduced no alternate sink, export,
callback, or visible byte.

This batch deliberately left every selector in `interactive-services.lisp`.
Splitting those state machines before their common frame existed would have
copied the same border/title/input/count/help/navigation decisions into eight
files.  B2 therefore begins by making `selector-frame` the sole owner of those
decisions and only then extracts the selector families.  `images.lisp` loads
before `clipboard.lisp` because clipboard image acquisition consumes the shared
image result and processing functions; all other leaf owners load before the
remaining selector consumer file.

### Part C B2 implementation status

B2 first established `interactive/selectors/common.lisp` as the sole owner of
selector chrome, viewport/count placement, input, help rows, and bidirectional
wrap navigation.  Only after the frame behavior gate was red did the seven
domain selector owners move out of `interactive-services.lisp`.  Existing
overlay and base-screen bytes stayed unchanged.

### Part C B4 implementation status

B4 completed all eight approved CLI service splits.  The proposal's prose said
"36 files", but its explicit cohesion map names 37 responsibilities
(`6 + 7 + 3 + 5 + 4 + 4 + 5 + 3`); the implementation follows the approved
named boundaries rather than hiding one owner to satisfy the arithmetic typo.

Convergence preceded extraction.  `cadr-agent/truncate.lisp` became the single
implementation of JavaScript UTF-16 code-unit length before the CLI adapter
moved.  The existing extension user-output sink and infrastructure-capture
boundary moved together into `extensions/loader.lisp`; settings/auth writes
continue through `cadr-core` atomic replacement, and all credential-bearing
objects continue through the shared redacted-printer declarations.  The 37
new files preserve the old top-level forms and package-private names; only ASDF
ownership and the eliminated duplicate UTF-16 loop changed.

### Part C B5 implementation status

B5 split the 64 definitions formerly in `main.lisp` across six bootstrap
owners, and the 36 RPC definitions across five command-domain owners.  The
process entrypoint and RPC loop are now thin lifecycle boundaries; tool,
session, settings, authentication, command, model, prompt/bash, and RPC session
responsibilities live in files whose names predict their contents.

Convergence happened at the split boundary.  CLI commands still inject exactly
one `frontend-output` sink, every RPC domain emits only through
`rpc-write-object`, session-export timestamps call the B3 UTC formatter
directly, and RPC IDs call the B3 millisecond clock directly.  The split kept
all 100 top-level definitions and the public package text unchanged.

### Part C B6 implementation status

B6 removed both interactive monoliths only after the B2 selector frame, B4
output sinks, and B3 cleanup policy were available.  State records load first;
entry/status/transcript/tool reducers and extension bridges load next; frame,
autocomplete, theme watching, and the controller load in dependency order.
The two existing B1 owners, `status.lisp` and `transcript.lisp`, absorbed their
matching controller-side forms instead of creating duplicate owners.

The five independent component families now have exact files, while the live
controller keeps only lifecycle and input/command routing.  All 224 top-level
definitions moved without renaming, public package text stayed byte-identical,
and source gates reject either legacy monolith or a second selector/output/
cleanup policy.

### Part C B7 implementation status

B7 moved the 288 existing reusable-TUI definitions into sixteen exact owners.
Component protocols load before concrete composition methods; terminal
protocols and the virtual terminal load before lifecycle/input and the two
screen renderers.  The loader owner delegates cancellation and bounded thread
cleanup to the B3 primitives instead of reintroducing either policy.

No definition was renamed and `src/cadr-tui/package.lisp` remained
byte-identical, so the public export set is frozen.  Full-screen, overlay,
mouse, scroll, performance, and fresh-compile gates protect the unchanged
observable behavior while organization tests reject all three legacy
monoliths and any dependency-unsafe ASDF order.

### Part C B8 implementation status

B8 moved all 251 session, storage, and loop definitions into thirteen exact
owners. Session codecs precede journals, migration, discovery, and export;
storage protocols precede memory, harness, JSONL, and SQLite backends; loop
events and tool execution precede turns and public agent-loop entrypoints.
The split preserves the B3 UUID/time and atomic-replacement owners and adds no
alternate persistence or retry policy.

All three legacy monoliths are gone. The sorted definition set, public package
text, session bytes, tool results, event/wire output, and screen snapshots are
unchanged. The Goal 11 stability provenance now hashes the exact session codec
owner so the verification gate cannot silently follow a deleted aggregate.

### Part C B9 implementation status

B9 moved all 239 extension-host definitions into eight exact owners: context,
API value/event handling, registration, immutable snapshots, rendering,
provider/tool projection, commands/templates, and lifecycle dispatch. The ASDF
order follows those dependencies; no symbol was renamed and the legacy
monolith is gone.

The B3 cancellation owner still drives context abort state, and rendering still
emits through the injected extension notification sink. The public extension
export block and the 34-event source block remain byte-identical at SHA-256
`61eb1b623f784b3a8f0f6fe6791c65ebe991ff314ed1d969b82f3edd57646f18`
and `12f79b21e0e25495cb023baaf21b26f6cf9a891881b26602f6553f80af54887a`.

### Part C B10 implementation status

B10 moved all 229 definitions from four mixed AI files into seventeen exact
owners. Streaming JSON, event streams, grammar tools, session resources, proxy
configuration, and image runtime are separate capabilities; native HTTP and
AWS framing are separate transports; model/auth runtime and faux behavior are
separate runtime owners; release, retry, estimation, overflow, coercion, UUID,
and the B3 thread delegate are separate support owners.

The split is structural only. HTTP and model cancellation still consume the B3
core owner, SSE retains an explicit unbounded read timeout, network failures
retain the canonical `fetch failed` boundary, and the public `cadr-ai` package
text remains byte-identical at SHA-256
`e722e49fd70592edcd28da93acc97051d4a0b22bc016e4b7da314a65c4acfb4f`.

### Part C B11 implementation status

B11 retired the five mixed provider/authentication owners and replaced them
with 25 exact owners. OAuth primitives, callback/page handling, each bundled
OAuth provider, each authentication mechanism, six independent wire protocols,
provider declarations, protocol construction, and runtime projection now have
predictable files loaded in dependency order.

Convergence preceded extraction. The committed fixture generated from pi
baseline `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5` records all 38 providers and
every declaration field with `file:line` provenance. The validated declaration
is now the only owner of static provider identity/auth fields and callback
strategy identities; the ambient environment list is derived from those rows.
The public package text remains byte-identical at SHA-256
`e722e49fd70592edcd28da93acc97051d4a0b22bc016e4b7da314a65c4acfb4f`.

### Already-converged examples to preserve

- A0 now gives authentication overlays and Input components ownership of their
  own semantics instead of patching call sites.
- `model-registry-authentication-status` is the single producer of the live
  provider-status source.
- `call-with-fatal-condition-boundary` and credential `print-object` methods are
  the current top-level crash safety boundary.
- `call-with-normalized-file-operation` owns built-in file-tool condition copy.

These are design assets.  Splitting files must not duplicate their decisions
back into the new modules.

## 7. Permanent organization gate

`scripts/check-code-organization.py` scans every regular production file below
`src/`.  Part A's complete histogram placed 15 of 277 files in a distinct
`>=1000`-line band above the 700--999 band, so that audited band is the review
boundary.  The number is not a target: a cohesive 999-line file is not thereby
good, and a justified 1000-line file is not thereby bad.

Every file at or above that boundary must have a non-empty, path-specific
reason in `docs/code-organization-exemptions.json`.  The gate rejects an
unreviewed large file, a missing or duplicate reason, and a stale exemption for
a file that moved, disappeared, or fell below the boundary.  The checked-in
manifest currently contains the exact 15 Part A outliers, including generated
and vendored assets.  `scripts/verify.sh` drives both synthetic regressions and
the real repository/manifest pair before the parity and build stages.

This is a **symptom detector only**.  Passing it does not prove good ownership,
and failing it means "review and explain the boundary", not "split until the
number is green".  Repeated policy is the deeper failure mode, so the following
behavior and anti-bypass tests are the stronger permanent controls:

| Converged decision | Policy owner | Permanent behavior / anti-bypass gate |
|---|---|---|
| Bounded thread cleanup | `cadr-core/threads.lisp` | `bounded-thread-cleanup-times-out-and-makes-active-unbounded-waits-explicit`; `production-cleanup-joins-cannot-bypass-cadr-core` |
| Cancellation state and propagation | `cadr-core/cancellation.lisp` | `cancellation-state-is-local-external-waitable-and-thread-safe`; `production-cancellation-adapters-cannot-bypass-cadr-core` |
| Infrastructure output ownership | domain sinks, with CLI extension capture in `extensions/loader.lisp` and RPC wire output in `modes/rpc/jsonl.lisp` | `goal14-b4-converges-sinks-and-javascript-length-before-split`; `goal14-b5-converges-mode-output-and-time-before-split` plus existing user-channel diagnostic regressions |
| Selector frame semantics | `interactive/selectors/common.lisp` | `goal14-b2-selector-frame-owns-shared-selector-decisions`; `goal14-b2-selector-frame-wraps-and-centers-independently` |
| Provider identity/auth metadata | `cadr-ai/providers/definitions.lisp` | `goal14-provider-matrix-is-fixed-baseline-derived-and-complete`; `goal14-every-provider-definition-field-matches-fixed-baseline-matrix`; one-owner source gates |
| Secret-safe object printing | `cadr-core/redacted-print.lisp` | `redacted-object-declaration-registers-type-and-never-prints-secret`; `atomic-replacement-and-secret-printers-have-one-policy-owner` plus the credential-type registry test |
| Atomic persistence and file modes | `cadr-core/atomic-file.lisp` | `atomic-replacement-preserves-old-content-on-error-and-private-mode`; `atomic-replacement-and-secret-printers-have-one-policy-owner` |
| JavaScript UTF-16 count semantics | `cadr-agent/truncate.lisp` | `goal14-b4-converges-sinks-and-javascript-length-before-split` plus non-ASCII write/truncation fixtures |
| ISO time and ID formatting | `cadr-core/time.lisp` | `utc-time-primitives-match-fixed-baseline-vectors`; `goal14-b5-converges-mode-output-and-time-before-split` |

### Future goal preflight

Every future goal that adds production code must state before implementation:

1. the directory and named owner for the new code, using section 4;
2. which existing primitive or domain policy it reuses;
3. if none applies, why the new decision is genuinely distinct rather than a
   convenient second implementation.

The review must consider repeated decisions even when every touched file is
below the line threshold.  New files belong where responsibility is owned, not
where the current caller happens to be easiest to edit.
