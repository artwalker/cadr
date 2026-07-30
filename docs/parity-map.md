# Parity map

## 1. Scope and counting rules

Behavioral baseline: `earendil-works/pi@71efc6f0c1909874ec8c944637a9ae7fc0e2d508`.
The audit used the detached worktree `/tmp/cadr-parity-71efc6f0`; the
`pi-mono-legacy` worktree was not used as a source of truth.

Status meanings:

- **已实现**: the complete externally observable behavior in the row is
  implemented and has linked Common Lisp evidence.
- **缺失**: absent or only partially implemented. A partial adapter is not
  promoted to “已实现”.
- **有意差异**: an existing, approved language/build ecosystem difference
  listed in [README](../README.md#differences-from-typescript-pi).

Test classification is deliberately strict:

- `C` = 已覆盖: every relevant behavior in that TypeScript test file is
  covered by the linked CL tests.
- `U` = 适用但未覆盖: the production behavior exists, but the exact regression
  is missing from the CL suite.
- `M` = 对应缺失功能: the file contains behavior outside the current
  implementation, including files that are only partially covered.

This avoids claiming a provider-matrix E2E file as covered merely because one
provider path has a fixture.

### Mechanical inventory

| Package | Files at baseline | `*.test.ts` |
|---|---:|---:|
| `ai` | 309 | 120 |
| `agent` | 71 | 18 |
| `coding-agent` | 586 | 187 |
| `tui` | 72 | 27 |
| `storage` | 18 | 0 |
| `server` | 17 | 0 |
| `evals` | 8 | 0 |
| **Total tests** |  | **352** |

`storage`, `server`, and `evals` genuinely contain no `*.test.ts` at the audit
commit. SQLite coverage lives in two `agent/test/harness/sqlite-*.test.ts`
files. `evals` instead has two `*.eval.ts` suites, inventoried below.

The provider directory has **82 top-level files**: **38 built-in text-provider
factories**, **37 static `*.models.ts` catalogs**, one built-in image-provider
factory, one dynamic faux provider, and five shared/registry/declaration
files. “Provider count” below therefore means the 38 entries returned by
`builtinProviders()`, not the raw file count.

## 2. Package parity

### 2.1 `ai`

Reference public surface:

- unified message/content/tool/model/usage/event types, validation, overflow
  and retry helpers;
- ten text APIs: `openai-completions`, `mistral-conversations`,
  `openai-responses`, `azure-openai-responses`,
  `openai-codex-responses`, `anthropic-messages`,
  `bedrock-converse-stream`, `google-generative-ai`, `google-vertex`, and
  `pi-messages`;
- `openrouter-images`, provider/model registries, generated model catalogs,
  API-key/OAuth credential stores, dynamic/faux providers, and the `pi-ai`
  CLI.

| Surface | Status | cadr evidence or gap |
|---|---|---|
| Unified types, errors, usage, events | 已实现 | [types](../src/cadr-ai/types.lisp), [conditions](../src/cadr-ai/conditions.lisp), [CL-AI-TYPES](#cl-ai-types) |
| Native JSON, SSE, HTTP, retry | 已实现 | [json](../src/cadr-ai/json.lisp), [sse](../src/cadr-ai/sse.lisp), [http](../src/cadr-ai/http.lisp), [CL-AI-STREAM](#cl-ai-stream), [CL-AI-ERROR-RETRY](#cl-ai-error-retry) |
| Anthropic/OpenAI Responses/OpenAI Completions/Google core adapters | 缺失（基础已实现） | Core payload/stream paths exist under [providers](../src/cadr-ai/providers/), but current compatibility flags, caching, transport options, raw edge cases, and full provider matrices remain [AI-PROTOCOL](#ai-protocol) |
| Remaining independent APIs | 缺失 | [AI-INDEPENDENT](#ai-independent) |
| 38 built-in text providers | 缺失 | cadr registers five IDs, only four of which are baseline IDs; see provider table and [AI-CATALOG](#ai-catalog) |
| Static catalogs and cost calculation | 缺失（基础已实现） | [models](../src/cadr-ai/models.lisp) and [generated catalog](../src/cadr-ai/models.generated.lisp) cover the five cadr IDs, not the full baseline catalog |
| API-key and OpenAI/Anthropic OAuth | 缺失（基础已实现） | [auth](../src/cadr-ai/auth.lisp), [oauth](../src/cadr-ai/oauth.lisp), [CL-AI-OAUTH](#cl-ai-oauth); other flows are [AI-AUTH](#ai-auth) |
| Image input | 已实现 | [CL-AI-IMAGE](#cl-ai-image) |
| Image generation / OpenRouter Images | 缺失 | [AI-IMAGE-GEN](#ai-image-gen) |
| Dynamic provider/faux-provider public runtime | 缺失 | cadr has a definition registry, but not the reference `Models`/provider runtime contract |
| `pi-ai` CLI | 缺失 | no standalone cadr-ai CLI |

#### Provider ledger

Verification labels describe what is reachable with the credentials observed
during this audit, not what was rerun: `fixture` means deterministic local
replay/unit conversion; `live-ready` means a usable credential is present;
`live-proven` links an existing cadr live-smoke result. No unavailable
credential is inferred.

| # | Provider | Protocol | Authentication | Status and main difficulty | Reachable verification |
|---:|---|---|---|---|---|
| 1 | `amazon-bedrock` | `bedrock-converse-stream` | AWS chain/profile/access keys or bearer token | 缺失; AWS SDK credential chain, SigV4, region/inference-profile routing | fixture only; no AWS credential |
| 2 | `ant-ling` | `openai-completions` | `ANT_LING_API_KEY` | 缺失; low adapter cost, catalog/endpoint validation | fixture only |
| 3 | `anthropic` | `anthropic-messages` | API key, bearer auth token, or subscription OAuth | 缺失（基础已实现）; adaptive thinking, caching, eager tool input and compatibility matrix remain | fixture; no live credential |
| 4 | `azure-openai-responses` | `azure-openai-responses` | `AZURE_OPENAI_API_KEY` plus deployment endpoint | 缺失; Azure URL/deployment normalization and Responses replay | fixture only |
| 5 | `cerebras` | `openai-completions` | `CEREBRAS_API_KEY` | 缺失; shared adapter plus catalog | fixture only |
| 6 | `cloudflare-ai-gateway` | Anthropic + Completions + Responses | Cloudflare key, account ID, gateway ID | 缺失; placeholder materialization and gateway-specific headers across three APIs | fixture only |
| 7 | `cloudflare-workers-ai` | `openai-completions` | Cloudflare key and account ID | 缺失; endpoint materialization | fixture only |
| 8 | `deepseek` | `openai-completions` | `DEEPSEEK_API_KEY` | 已实现 for recorded core text/reasoning/tools; broader generic compat options remain package gaps | fixture + live-ready + [live-proven](../scripts/live-deepseek-smoke.sh) |
| 9 | `fireworks` | Anthropic + Completions | `FIREWORKS_API_KEY` | 缺失; multi-API catalog routing | fixture only |
| 10 | `github-copilot` | Anthropic + Completions + Responses | Copilot token or GitHub device OAuth | 缺失; device flow, token exchange, model filtering and Copilot headers | fixture only |
| 11 | `google` | `google-generative-ai` | `GEMINI_API_KEY` | 缺失（基础已实现）; full Gemini compatibility/thinking matrix remains | fixture; no live credential |
| 12 | `google-vertex` | `google-vertex` | API key or ADC/service account + project/location | 缺失; ADC/GCP auth and regional endpoint construction | fixture only |
| 13 | `groq` | `openai-completions` | `GROQ_API_KEY` | 缺失; shared adapter plus catalog | fixture only |
| 14 | `huggingface` | `openai-completions` | `HF_TOKEN` | 缺失; router catalog/compat | fixture only |
| 15 | `kimi-coding` | `anthropic-messages` | `KIMI_API_KEY` or device OAuth | 缺失; device flow and subscription headers | fixture only |
| 16 | `minimax` | `anthropic-messages` | `MINIMAX_API_KEY` | 缺失; Anthropic-compatible endpoint quirks | fixture only |
| 17 | `minimax-cn` | `anthropic-messages` | `MINIMAX_CN_API_KEY` | 缺失; regional endpoint/catalog | fixture only |
| 18 | `mistral` | `mistral-conversations` | `MISTRAL_API_KEY` | 缺失; independent SDK protocol, reasoning mode, schema sanitization | fixture only |
| 19 | `moonshotai` | `openai-completions` | `MOONSHOT_API_KEY` | 缺失; shared adapter plus catalog | fixture only |
| 20 | `moonshotai-cn` | `openai-completions` | `MOONSHOT_API_KEY` | 缺失; regional endpoint/catalog | fixture only |
| 21 | `nvidia` | `openai-completions` | `NVIDIA_API_KEY` | 缺失; shared adapter plus catalog | fixture only |
| 22 | `openai` | `openai-responses` | `OPENAI_API_KEY` | 缺失（基础已实现）; cache affinity, reasoning replay and compat options remain | fixture; no API-key live credential |
| 23 | `openai-codex` | `openai-codex-responses` | ChatGPT OAuth | 缺失（core OAuth/SSE works under cadr `openai` ID）; distinct provider identity, device flow parity, cache affinity and WebSocket modes remain | fixture + live-ready + [live-proven](../scripts/live-openai-oauth-smoke.sh) |
| 24 | `opencode` | Anthropic + Google + Completions + Responses | `OPENCODE_API_KEY` | 缺失; four-API model routing | fixture only |
| 25 | `opencode-go` | Anthropic + Completions + Responses | `OPENCODE_API_KEY` | 缺失; three-API model routing | fixture only |
| 26 | `openrouter` | `openai-completions` | API key or OAuth | 缺失; OAuth, cache-control variants and broad model catalog | fixture only |
| 27 | `qwen-token-plan` | `openai-completions` | `QWEN_TOKEN_PLAN_API_KEY` | 缺失; regional plan endpoint/catalog | fixture only |
| 28 | `qwen-token-plan-cn` | `openai-completions` | `QWEN_TOKEN_PLAN_CN_API_KEY` | 缺失; regional plan endpoint/catalog | fixture only |
| 29 | `radius` | `pi-messages` | API key or Radius OAuth | 缺失; dynamic gateway config/catalog and independent stream protocol | fixture only |
| 30 | `together` | `openai-completions` | `TOGETHER_API_KEY` | 缺失; shared adapter plus catalog | fixture only |
| 31 | `vercel-ai-gateway` | `anthropic-messages` | `AI_GATEWAY_API_KEY` | 缺失; gateway headers/catalog | fixture only |
| 32 | `xai` | Completions + Responses | API key or xAI device OAuth | 缺失; dual API, device polling and model filtering | fixture only |
| 33 | `xiaomi` | `openai-completions` | `XIAOMI_API_KEY` | 缺失; MiMo catalog/compat | fixture only |
| 34 | `xiaomi-token-plan-ams` | `openai-completions` | `XIAOMI_TOKEN_PLAN_AMS_API_KEY` | 缺失; regional plan endpoint and empty-signature behavior | fixture only |
| 35 | `xiaomi-token-plan-cn` | `openai-completions` | `XIAOMI_TOKEN_PLAN_CN_API_KEY` | 缺失; regional plan endpoint/catalog | fixture only |
| 36 | `xiaomi-token-plan-sgp` | `openai-completions` | `XIAOMI_TOKEN_PLAN_SGP_API_KEY` | 缺失; regional plan endpoint/catalog | fixture only |
| 37 | `zai` | `openai-completions` | `ZAI_API_KEY` | 缺失; endpoint/catalog | fixture only |
| 38 | `zai-coding-cn` | `openai-completions` | `ZAI_CODING_CN_API_KEY` | 缺失; regional coding endpoint/catalog | fixture only |

The reference also has the separate `openrouter` image provider and the
dynamic `faux` provider; neither is counted among the 38 text providers.
Both are missing as public cadr runtimes.

Audit drift: cadr additionally registers `ollama`, which is **not** in
`builtinProviders()` at the baseline. It is implemented as a keyless
OpenAI-Completions endpoint, but the local daemon was unreachable during this
audit. This is not an approved README difference; the next goal must either
map it to an exact reference extension/custom-provider behavior or put the
addition through manual `open-questions` review. This audit does neither.

### 2.2 `agent`

Reference public surface includes `Agent`, the agent loop and queue modes,
before/after tool hooks, `AgentHarness`, execution environments, filesystem
and in-memory/JSONL/SQLite session repo/storage interfaces, compaction,
skills, prompt templates, system-prompt formatting, tools, truncation, and
proxy/default-stream helpers.

| Surface | Status | cadr evidence or gap |
|---|---|---|
| Agent lifecycle and tool loop | 已实现 | [loop](../src/cadr-agent/loop.lisp), [CL-AGENT-LOOP](#cl-agent-loop) |
| Sequential/parallel tools, validation, hook rewrite/block | 已实现 | [tool](../src/cadr-agent/tool.lisp), [schema](../src/cadr-agent/schema.lisp), [CL-AGENT-SCHEMA](#cl-agent-schema), [CL-EXT](#cl-ext) |
| Busy guard | 已实现, but the reference file also requires steering/follow-up queues and ordered async extension events | [runtime](../src/cadr-agent/runtime.lisp); whole-file status remains [AGENT-HARNESS](#agent-harness) |
| Steering/follow-up queues and queue modes | 缺失 | [AGENT-HARNESS](#agent-harness) |
| `AgentHarness`, environment, repo/storage public abstractions | 缺失 | [AGENT-HARNESS](#agent-harness) |
| Tree session and compaction core | 缺失（基础已实现） | cadr supports message/compaction trees, but not the complete reference v3 entry/storage contract; [CODING-SESSION](#coding-session) |
| Built-in read/write/edit/bash/find/grep/ls harness set | 缺失 | cadr has read/write/edit/bash/glob/grep, but no reference `find`/`ls` APIs and no generic execution-environment contract; [CODING-TOOLS](#coding-tools) |
| Skills/templates/system prompt | 有意差异 | Lisp registrations replace Markdown/TS resource formats; [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| Proxy/default-stream compatibility helpers | 缺失 | [AGENT-HARNESS](#agent-harness) |

### 2.3 `coding-agent`

Reference modes are interactive, text print, JSON event print, and JSONL RPC.
Its public root exports argument parsing, `AgentSession`, runtime/services
factories, model runtime/registry, session manager v3, settings/resources,
extension APIs, compaction, tool factories, and utility APIs.

Reference CLI options at the baseline are:

`--provider`, `--model`, `--api-key`, `--system-prompt`,
`--append-system-prompt`, `--thinking`, `--continue/-c`, `--resume/-r`,
`--mode text|json|rpc`, `--name/-n`, `--no-session`, `--session`,
`--session-id`, `--fork`, `--session-dir`, `--models`, `--tools/-t`,
`--exclude-tools/-xt`, `--no-tools/-nt`, `--no-builtin-tools/-nbt`,
`--extension/-e`, `--no-extensions/-ne`, `--print/-p`, `--export`,
`--skill`, `--no-skills/-ns`, `--prompt-template`,
`--no-prompt-templates/-np`, `--theme`, `--no-themes`,
`--no-context-files/-nc`, `--list-models`, `--offline`, `--verbose`,
`--approve/-a`, `--no-approve/-na`, `--help/-h`, and `--version/-v`, plus
`@file` arguments and extension-defined flags.

cadr currently exposes only `--provider`, `--model`, `--base-url`,
`--system-prompt`, `--continue`, `--resume`, repeatable `--extension`,
`--no-tui`, `--help`, and `--version`.

Reference top-level management commands are `install`, `remove`, `uninstall`,
`update`, `list`, `config`, and `auth`. Reference built-in slash commands are
`/settings`, `/model`, `/scoped-models`, `/export`, `/import`, `/share`,
`/copy`, `/name`, `/session`, `/changelog`, `/hotkeys`, `/fork`, `/clone`,
`/tree`, `/trust`, `/login`, `/logout`, `/new`, `/compact`, `/resume`,
`/reload`, and `/quit`.

Reference RPC commands are `prompt`, `steer`, `follow_up`, `abort`,
`new_session`, `get_state`, `set_model`, `cycle_model`,
`get_available_models`, `set_thinking_level`, `cycle_thinking_level`,
`get_available_thinking_levels`, `set_steering_mode`,
`set_follow_up_mode`, `compact`, `set_auto_compaction`, `set_auto_retry`,
`abort_retry`, `bash`, `abort_bash`, `get_session_stats`, `export_html`,
`switch_session`, `fork`, `clone`, `get_fork_messages`, `get_entries`,
`get_tree`, `get_last_assistant_text`, `set_session_name`, `get_messages`,
and `get_commands`.

| Surface | Status | cadr evidence or gap |
|---|---|---|
| Interactive TUI and line fallback | 已实现 | [main](../src/cadr-cli/main.lisp), [tui adapter](../src/cadr-cli/tui.lisp), [CL-TUI](#cl-tui) |
| Text/JSON print and RPC modes | 缺失 | [CODING-RPC](#coding-rpc), [CODING-CLI-SDK](#coding-cli-sdk) |
| Full CLI option/command contract | 缺失 | option list above versus [arguments](../src/cadr-cli/arguments.lisp) |
| Built-in commands | 缺失（基础已实现） | cadr has sessions/switch/branch/compact/export/auth/reload/install; reference also has package management, configuration, import/clone/tree/model/thinking/theme and other interactive commands |
| Public SDK/runtime/services | 缺失 | [CODING-CLI-SDK](#coding-cli-sdk) |
| Model registry/runtime and scoped model selection | 缺失 | [CODING-MODELS](#coding-models) |
| Tool set and mutation/runtime semantics | 缺失（基础已实现） | [tools](../src/cadr-cli/tools/), [CL-TOOLS](#cl-tools), [CODING-TOOLS](#coding-tools) |
| Session JSONL format | 缺失 | baseline `CURRENT_SESSION_VERSION = 3`; cadr calls its smaller message/compaction-only format v2 and lacks thinking/model changes, branch summaries, custom entries/messages, labels and session-info entries |
| Extension capability | 有意差异 | semantic hooks/tools/commands/templates exist, but formats and package runtime are Lisp; [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| Settings, themes, packages, context files, remote catalogs | 缺失 except Lisp extension install subset | [CODING-CONFIG](#coding-config), [CODING-INTERACTIVE](#coding-interactive) |

### 2.4 `tui`

Reference public surface includes terminal/input parsing, components and
containers, editor/input, autocomplete/fuzzy matching, configurable
keybindings, Markdown, overlays, select lists, spinners/loaders, terminal
capabilities/colors/images, ANSI-aware wrapping/truncation and word
navigation.

| Surface | Status | cadr evidence or gap |
|---|---|---|
| Grapheme/cell width, wrapping, ANSI-aware layout | 已实现 | [unicode](../src/cadr-tui/unicode.lisp), [CL-TUI](#cl-tui) |
| Input decoding, bracketed paste, multiline editor, kill ring and undo | 已实现 | [input](../src/cadr-tui/input.lisp), [stdin buffer](../src/cadr-tui/stdin-buffer.lisp), [editor](../src/cadr-tui/editor.lisp), [CL-TUI](#cl-tui) |
| Markdown, tool block, status bar, select list, truncated text and image component | 已实现 | [components](../src/cadr-tui/components.lisp), [CL-TUI](#cl-tui) |
| Differential renderer and terminal cleanup | 已实现 | [renderer](../src/cadr-tui/renderer.lisp), [terminal](../src/cadr-tui/terminal.lisp), [CL-TUI](#cl-tui) |
| Autocomplete, fuzzy matching, configurable keybindings, word navigation | 已实现 | [autocomplete](../src/cadr-tui/autocomplete.lisp), [fuzzy](../src/cadr-tui/fuzzy.lisp), [keybindings](../src/cadr-tui/keybindings.lisp), [word navigation](../src/cadr-tui/word-navigation.lisp), [CL-TUI](#cl-tui) |
| Overlay stack/compositing | 已实现 | [overlay](../src/cadr-tui/overlay.lisp), [renderer](../src/cadr-tui/renderer.lisp), [CL-TUI](#cl-tui) |
| Terminal image protocols, cell-size replies, color probing | 已实现 | [terminal image](../src/cadr-tui/terminal-image.lisp), [terminal colors](../src/cadr-tui/terminal-colors.lisp), [CL-TUI](#cl-tui) |
| Goal 5 reference component/test surface | 已实现 | [components](../src/cadr-tui/components.lisp), [component parity tests](../test/cadr-tui/component-parity-test.lisp), [CL-TUI](#cl-tui) |

### 2.5 `storage`

The reference `@earendil-works/pi-storage-sqlite-node` exports a
`node:sqlite` adapter, migration loader/runner, `SqliteSessionRepo`, and
`SqliteSessionStorage`. Its schema contains sessions, sequences, tree
entries, materialized session/entry state and branch entries; repo operations
are create/open/list/delete/fork and storage operations implement the agent
session-storage contract.

| Surface | Status | cadr evidence or gap |
|---|---|---|
| SQLite adapter and transaction contract | 缺失 | [STORAGE-SQLITE](#storage-sqlite) |
| Migration/schema | 缺失 | [STORAGE-SQLITE](#storage-sqlite) |
| SQLite repo create/open/list/delete/fork | 缺失 | [STORAGE-SQLITE](#storage-sqlite) |
| Materialized tree/branch storage | 缺失 | [STORAGE-SQLITE](#storage-sqlite) |
| JSONL filesystem sessions | 已实现 but not a storage-package substitute | [session](../src/cadr-agent/session.lisp) |

### 2.6 `server`

The reference package is a Unix-socket JSONL supervisor, not an HTTP server.
Its CLI commands are `serve`, `list`, `spawn [--cwd --label]`, `status`,
`stop`, `rpc`, and `rpc-stream`. IPC requests are `spawn`, `list`, `stop`,
`status`, `rpc`, and `rpc_stream`; the stream bridges coding-agent RPC events
and extension UI requests/responses. It persists machine and instance records,
spawns RPC child processes, tracks lifecycle/session metadata, and optionally
maintains Radius presence.

| Surface | Status | cadr evidence or gap |
|---|---|---|
| Server CLI and Unix socket framing | 缺失 | [SERVER](#server) |
| Instance supervisor and persistence | 缺失 | [SERVER](#server) |
| RPC request/stream bridge and extension UI bridge | 缺失 | [SERVER](#server) |
| Radius registration/presence | 缺失 | [SERVER](#server) |
| Public server API | 缺失 | [SERVER](#server) |

### 2.7 `evals`

The reference package wraps `AgentSession` as a `vitest-evals` harness. It
requires an explicit provider/model, creates isolated project/agent
directories, normalizes messages/tool calls/results and usage, supports
prompt/reload sequences, and cleans up the session and temporary tree.

It has two non-`*.test.ts` suites:

- `src/smoke.eval.ts`: exact “Paris” end-to-end response and usage identity;
- `src/extensions.eval.ts`: model creates, reloads and invokes a `hello`
  extension, then the harness checks extension paths, tool definitions and
  normalized tool-call results.

| Surface | Status | cadr evidence or gap |
|---|---|---|
| Generic eval harness and normalized transcript/usage | 缺失 | [EVALS](#evals) |
| Explicit provider/model runner | 缺失 | [EVALS](#evals) |
| Smoke eval | 缺失 | [EVALS](#evals) |
| Self-extension eval | 缺失; deterministic/live smoke scripts are not the exported eval harness | [EVALS](#evals) |

## 3. Gap and evidence index

### Implemented evidence

| ID | Common Lisp tests |
|---|---|
| <a id="cl-ai-types"></a>`CL-AI-TYPES` | [`USAGE-DEFAULTS-AND-TOTAL`, `CONSTRUCTORS-RETAIN-UNIFIED-MESSAGE-DATA`](../test/cadr-ai/types-test.lisp), [`COMPLETE-RESPONSE-FIXTURES-NORMALIZE-MESSAGES-AND-USAGE`](../test/cadr-ai/provider-responses-test.lisp) |
| <a id="cl-ai-stream"></a>`CL-AI-STREAM` | [`RECORDED-SSE-FIXTURES-NORMALIZE-EVENTS-AND-FINAL-MESSAGE`, `STREAM-ENDING-WITHOUT-PROVIDER-TERMINAL-EVENT-IS-AN-ERROR`, `STREAM-ABORT-PRESERVES-PARTIAL-CONTENT-AND-TERMINATES`](../test/cadr-ai/provider-streams-test.lisp), [`SSE-FRAMING-*`](../test/cadr-ai/sse-test.lisp), [`SSE-REQUEST-EXPLICITLY-DISABLES-READ-TIMEOUT`](../test/cadr-ai/http-test.lisp) |
| <a id="cl-ai-history"></a>`CL-AI-HISTORY` | [`ORPHANED-TOOL-CALLS-RECEIVE-SYNTHETIC-ERROR-RESULTS`, `FOREIGN-HISTORY-IS-MADE-SAFE-FOR-GEMINI-3.6`, `CONSECUTIVE-ANTHROPIC-TOOL-RESULTS-SHARE-ONE-USER-TURN`, `INCOMPLETE-AND-EMPTY-ASSISTANT-MESSAGES-ARE-NOT-REPLAYED`](../test/cadr-ai/provider-history-test.lisp) |
| <a id="cl-ai-payload"></a>`CL-AI-PAYLOAD` | [`PROVIDER-REQUEST-PAYLOADS-MATCH-REFERENCE-FIXTURES`, `PROVIDER-REQUEST-PATHS-AND-AUTH-HEADERS`, `GEMINI-3.6-OMITS-DEPRECATED-SAMPLING-PARAMETERS`](../test/cadr-ai/provider-payloads-test.lisp) |
| <a id="cl-ai-image"></a>`CL-AI-IMAGE` | [`EACH-WIRE-PROTOCOL-ENCODES-IMAGE-CONTENT`, `UNSUPPORTED-IMAGE-INPUT-FAILS-BEFORE-TRANSPORT`](../test/cadr-ai/image-model-test.lisp) |
| <a id="cl-ai-error-retry"></a>`CL-AI-ERROR-RETRY` | [`COMPLETE-CHAT-NORMALIZES-API-ERRORS`](../test/cadr-ai/provider-responses-test.lisp), [`RETRYABLE-COMPLETE-REQUESTS-RESPECT-CAP-AND-RETRY-AFTER`, `NONRETRYABLE-COMPLETE-REQUEST-IS-NOT-RETRIED`, `NATIVE-HTTP-STATUSES-RETAIN-API-BODY-AND-RETRY-POLICY`, `STREAM-RETRIES-BEFORE-PROVIDER-EVENTS-WITHOUT-DUPLICATING-START`](../test/cadr-ai/retry-test.lisp), [`CONTEXT-OVERFLOW-COMPACTS-ONCE-AND-RETRIES-WITHOUT-THE-ERROR-BRANCH`](../test/cadr-agent/compaction-test.lisp) |
| <a id="cl-ai-oauth"></a>`CL-AI-OAUTH` | [`OPENAI-AUTHORIZATION-URL-MATCHES-FIXED-REFERENCE`, `ANTHROPIC-AUTHORIZATION-URL-MATCHES-FIXED-REFERENCE`, `OAUTH-CALLBACK-PARSER-VALIDATES-PATH-AND-STATE`, `OAUTH-REFRESH-IS-DOUBLE-CHECKED-UNDER-LOCK`, `OPENAI-OAUTH-USES-CODEX-URL-AND-REFERENCE-HEADERS`, `EXPIRED-OPENAI-TOKEN-REFRESHES-ONCE-THEN-BUILDS-REQUEST`](../test/cadr-ai/auth-test.lisp) |
| <a id="cl-ai-deepseek"></a>`CL-AI-DEEPSEEK` | [`OPENAI-COMPLETIONS-BUILDS-TOOL-HISTORY`, `OPENAI-COMPLETIONS-PARSES-COMPLETE-TOOL-CALL-AND-USAGE`, `RECORDED-DEEPSEEK-CHAT-COMPLETIONS-STREAM`](../test/cadr-ai/openai-completions-test.lisp) |
| <a id="cl-agent-loop"></a>`CL-AGENT-LOOP` | [`SIMPLE-TURN-EMITS-REFERENCE-LIFECYCLE-ORDER`, `ERROR-AND-ABORT-STOP-THE-RUN-CLEANLY`](../test/cadr-agent/loop-test.lisp), [`TOOL-CALL-RESULT-AND-NEXT-MODEL-TURN-COMPLETE`](../test/cadr-agent/tool-loop-test.lisp) |
| <a id="cl-agent-schema"></a>`CL-AGENT-SCHEMA` | [`NATIVE-SCHEMA-VALIDATES-NESTED-TOOL-ARGUMENTS`, `NATIVE-SCHEMA-SUPPORTS-COMPOSITION-AND-SCALAR-CONSTRAINTS`, `NATIVE-SCHEMA-DEFINITION-REJECTS-MALFORMED-KEYWORDS`](../test/cadr-agent/schema-test.lisp) |
| <a id="cl-compaction"></a>`CL-COMPACTION` | [`AUTOMATIC-COMPACTION-USES-CURRENT-MODEL-AND-CONTINUES-THE-PROMPT`, `CONTEXT-OVERFLOW-COMPACTS-ONCE-AND-RETRIES-WITHOUT-THE-ERROR-BRANCH`](../test/cadr-agent/compaction-test.lisp) |
| <a id="cl-session"></a>`CL-SESSION` | [`SESSION-V2-BRANCHES-FROM-ANY-NODE-AND-PERSISTS-BOTH-PATHS`, `SESSION-V1-LOAD-MIGRATES-ATOMICALLY-WITHOUT-LOSING-ENVELOPE-FIELDS`, `SESSION-V2-REJECTS-DUPLICATE-IDS-AND-DANGLING-PARENTS`, `SESSION-LIST-RESUME-AND-HTML-EXPORT-COVER-THE-ENTIRE-TREE`](../test/cadr-agent/session-v2-test.lisp), [`SESSION-JSONL-ROUND-TRIPS-ALL-FIRST-VERSION-MESSAGE-TYPES`](../test/cadr-agent/session-test.lisp) |
| <a id="cl-ext"></a>`CL-EXT` | [`EXTENSION-REGISTRATION-*`, hook, reload and resource-precedence tests](../test/cadr-agent/extensions-test.lisp), [discovery/install/self-extension tests](../test/cadr-cli/extensions-test.lisp) |
| <a id="cl-tools"></a>`CL-TOOLS` | [file tools](../test/cadr-cli/file-tools-test.lisp), [search tools](../test/cadr-cli/search-tools-test.lisp), [bash](../test/cadr-cli/bash-test.lisp) |
| <a id="cl-cli"></a>`CL-CLI` | [config/auth](../test/cadr-cli/config-auth-test.lisp), [REPL/tool loop](../test/cadr-cli/repl-test.lisp), [retry tests](../test/cadr-ai/retry-test.lisp) |
| <a id="cl-tui"></a>`CL-TUI` | [Unicode/layout](../test/cadr-tui/unicode-test.lisp), [ANSI wrapping](../test/cadr-tui/wrap-ansi-test.lisp), [truncation](../test/cadr-tui/truncate-to-width-test.lisp), [keys](../test/cadr-tui/keys-test.lisp), [keybindings](../test/cadr-tui/keybindings-test.lisp), [stdin buffering](../test/cadr-tui/stdin-buffer-test.lisp), [autocomplete](../test/cadr-tui/autocomplete-test.lisp), [editor](../test/cadr-tui/editor-parity-test.lisp), [single-line input](../test/cadr-tui/input-component-test.lisp), [components](../test/cadr-tui/component-parity-test.lisp), [overlays](../test/cadr-tui/overlay-test.lisp), [terminal colors](../test/cadr-tui/terminal-colors-test.lisp), [terminal images](../test/cadr-tui/terminal-image-test.lisp), [renderer](../test/cadr-tui/renderer-test.lisp), [terminal parity](../test/cadr-tui/terminal-parity-test.lisp), [frontend projection](../test/cadr-cli/tui-test.lisp) |

### Missing-feature IDs

| ID | Missing behavior |
|---|---|
| <a id="ai-protocol"></a>`AI-PROTOCOL` | complete protocol option/compatibility matrices, prompt/cache/session affinity, transport selection, partial JSON/ID handling, constrained/deferred tools and all-provider E2E |
| <a id="ai-independent"></a>`AI-INDEPENDENT` | Bedrock, Vertex, Mistral Conversations, Azure Responses and `pi-messages` adapters |
| <a id="ai-auth"></a>`AI-AUTH` | remaining provider auth/OAuth/device flows, token resolution and provider-specific headers |
| <a id="ai-catalog"></a>`AI-CATALOG` | full 38-provider runtime, generated catalogs, dynamic stores, model metadata/compat and faux public provider |
| <a id="ai-image-gen"></a>`AI-IMAGE-GEN` | image-provider/model registry and OpenRouter image generation |
| <a id="agent-harness"></a>`AGENT-HARNESS` | reference harness, queue modes, execution environment, repo/storage and proxy/default-stream public contracts |
| <a id="coding-rpc"></a>`CODING-RPC` | JSONL RPC mode/client and complete command/response/event/UI protocol |
| <a id="coding-cli-sdk"></a>`CODING-CLI-SDK` | print/text/JSON modes, full CLI, SDK/runtime/services and exported utilities |
| <a id="coding-models"></a>`CODING-MODELS` | model runtime, scopes/cycling, models store, runtime credentials and provider composition |
| <a id="coding-session"></a>`CODING-SESSION` | exact JSONL v3 entry types, AgentSession runtime/queues/events, labels/name/clone and session selector semantics |
| <a id="coding-tools"></a>`CODING-TOOLS` | exact read/bash/edit/write/find/grep/ls API and concurrent mutation/streaming/platform edge behavior |
| <a id="coding-config"></a>`CODING-CONFIG` | settings manager, resource loader, configurable keybindings, project context/trust and migrations |
| <a id="coding-interactive"></a>`CODING-INTERACTIVE` | complete interactive command/component behavior, clipboard/images, themes, syntax and selectors |
| <a id="storage-sqlite"></a>`STORAGE-SQLITE` | complete SQLite package, migrations, materialized views and repo/storage contracts |
| <a id="server"></a>`SERVER` | complete server package |
| <a id="evals"></a>`EVALS` | complete eval harness, runner and two eval suites |
| <a id="diff-lisp-ecosystem"></a>`DIFF-LISP-ECOSYSTEM` | approved Lisp extension/skill/template/package format and implementation/build-language differences; capability gaps inside those systems remain separately missing |

### Applicable but uncovered backlog

There are no `U` files in the strict manifest. Goal 5 closed
`U-SEARCH-GITIGNORE` and `U-TUI-RI`; similar-looking files remain `M` when
they also cover an unimplemented provider, queue, compatibility option or
platform behavior.

### `docs/test-matrix.md` audit notes

The matrix now records the Goal 5 total of **1212** checks and the expanded
TUI gates. The following conservative whole-file classification notes remain:

1. It maps `anthropic-sse-parsing.test.ts` to generic SSE framing and a
   recorded replay, but the baseline file specifically repairs malformed SSE
   JSON and malformed streamed tool JSON. cadr does not implement or test that
   repair, so the file is `M`, not covered.
2. It presents `cross-provider-handoff.test.ts`, `empty.test.ts`,
   `image-tool-result.test.ts`, `stream.test.ts`, `tokens.test.ts` and similar
   provider-matrix files as covered by a small implemented-protocol subset.
   Under whole-file classification those files remain `M` until all baseline
   provider cases pass.
3. It describes cadr’s parent-linked format as JSONL v2. The audit baseline is
   `CURRENT_SESSION_VERSION = 3` and includes entry kinds absent from cadr.
   Existing cadr tree tests prove its own format, not exact v3 parity.
4. It has no exhaustive mapping for the 352 baseline test files and no rows
   for the new `storage`, `server`, or `evals` package surfaces.

## 4. Exhaustive `*.test.ts` manifest

The appendix is sorted exactly like
`find packages -type f -name '*.test.ts' | sort`. Each path appears once.

| Package | C | U | M | Total |
|---|---:|---:|---:|---:|
| `ai` | 0 | 0 | 120 | 120 |
| `agent` | 0 | 0 | 18 | 18 |
| `coding-agent` | 1 | 0 | 186 | 187 |
| `tui` | 27 | 0 | 0 | 27 |
| `storage` / `server` / `evals` | 0 | 0 | 0 | 0 |
| **Total** | **28** | **0** | **324** | **352** |

The 1219 CL assertions now cover the complete 27-file TUI test surface and
the nested-gitignore regression. Most other reference files still contain at
least one provider, v3 entry type, queue, UI, platform, or compatibility case
that cadr does not implement. Partial coverage stays `M`.

| Class | Baseline test file | Evidence/gap |
|---|---|---|
<!-- TEST-MANIFEST-BEGIN -->
| M | `packages/agent/test/agent-loop.test.ts` | [AGENT-HARNESS](#agent-harness) |
| M | `packages/agent/test/agent.test.ts` | [AGENT-HARNESS](#agent-harness) |
| M | `packages/agent/test/e2e.test.ts` | [AGENT-HARNESS](#agent-harness) |
| M | `packages/agent/test/harness/agent-harness-stream.test.ts` | [AGENT-HARNESS](#agent-harness) |
| M | `packages/agent/test/harness/agent-harness.test.ts` | [AGENT-HARNESS](#agent-harness) |
| M | `packages/agent/test/harness/compaction.test.ts` | [AGENT-HARNESS](#agent-harness) |
| M | `packages/agent/test/harness/nodejs-env.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/agent/test/harness/prompt-templates.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/agent/test/harness/repo.test.ts` | [AGENT-HARNESS](#agent-harness) |
| M | `packages/agent/test/harness/resource-formatting.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/agent/test/harness/session.test.ts` | [AGENT-HARNESS](#agent-harness) |
| M | `packages/agent/test/harness/skills.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/agent/test/harness/sqlite-migrations.test.ts` | [STORAGE-SQLITE](#storage-sqlite) |
| M | `packages/agent/test/harness/sqlite-node.test.ts` | [STORAGE-SQLITE](#storage-sqlite) |
| M | `packages/agent/test/harness/storage.test.ts` | [AGENT-HARNESS](#agent-harness) |
| M | `packages/agent/test/harness/system-prompt.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/agent/test/harness/tools.test.ts` | [AGENT-HARNESS](#agent-harness) |
| M | `packages/agent/test/harness/truncate.test.ts` | [AGENT-HARNESS](#agent-harness) |
| M | `packages/ai/test/abort.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/anthropic-adaptive-thinking-models.test.ts` | [AI-CATALOG](#ai-catalog) |
| M | `packages/ai/test/anthropic-auth-token.test.ts` | [AI-AUTH](#ai-auth) |
| M | `packages/ai/test/anthropic-cache-write-1h-cost.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/anthropic-eager-tool-input-compat.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/anthropic-eager-tool-input-e2e.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/anthropic-empty-thinking-signature-compat.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/anthropic-force-adaptive-thinking.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/anthropic-long-cache-retention-e2e.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/anthropic-oauth.test.ts` | [AI-AUTH](#ai-auth) |
| M | `packages/ai/test/anthropic-opus-4-8-smoke.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/anthropic-sse-parsing.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/anthropic-temperature-compat.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/anthropic-thinking-disable.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/anthropic-tool-name-normalization.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/azure-openai-base-url.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/azure-openai-responses-reasoning-replay.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/bedrock-convert-messages.test.ts` | [AI-INDEPENDENT](#ai-independent) |
| M | `packages/ai/test/bedrock-credentials.test.ts` | [AI-INDEPENDENT](#ai-independent) |
| M | `packages/ai/test/bedrock-custom-headers.test.ts` | [AI-INDEPENDENT](#ai-independent) |
| M | `packages/ai/test/bedrock-endpoint-resolution.test.ts` | [AI-INDEPENDENT](#ai-independent) |
| M | `packages/ai/test/bedrock-models.test.ts` | [AI-INDEPENDENT](#ai-independent) |
| M | `packages/ai/test/bedrock-raw-stop-reason.test.ts` | [AI-INDEPENDENT](#ai-independent) |
| M | `packages/ai/test/bedrock-thinking-payload.test.ts` | [AI-INDEPENDENT](#ai-independent) |
| M | `packages/ai/test/cache-retention.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/cloudflare-stream.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/compat-env.test.ts` | [AI-CATALOG](#ai-catalog) |
| M | `packages/ai/test/constrained-sampling.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/context-estimate.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/context-overflow.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/cross-provider-handoff.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/deferred-tools.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/empty.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/env-api-keys.test.ts` | [AI-AUTH](#ai-auth) |
| M | `packages/ai/test/error-body.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/faux-provider.test.ts` | [AI-CATALOG](#ai-catalog) |
| M | `packages/ai/test/fetch-option.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/fireworks-models.test.ts` | [AI-CATALOG](#ai-catalog) |
| M | `packages/ai/test/github-copilot-anthropic.test.ts` | [AI-AUTH](#ai-auth) |
| M | `packages/ai/test/github-copilot-oauth.test.ts` | [AI-AUTH](#ai-auth) |
| M | `packages/ai/test/google-raw-stop-reason.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/google-shared-convert-tools.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/google-shared-gemini3-unsigned-tool-call.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/google-shared-image-tool-result-routing.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/google-thinking-disable.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/google-thinking-signature.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/google-vertex-api-key-resolution.test.ts` | [AI-INDEPENDENT](#ai-independent) |
| M | `packages/ai/test/image-model-data.test.ts` | [AI-IMAGE-GEN](#ai-image-gen) |
| M | `packages/ai/test/image-tool-result.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/images-models.test.ts` | [AI-IMAGE-GEN](#ai-image-gen) |
| M | `packages/ai/test/images.test.ts` | [AI-IMAGE-GEN](#ai-image-gen) |
| M | `packages/ai/test/interleaved-thinking.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/kimi-coding-oauth.test.ts` | [AI-AUTH](#ai-auth) |
| M | `packages/ai/test/lax-message-content.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/lazy-module-load.test.ts` | [AI-CATALOG](#ai-catalog) |
| M | `packages/ai/test/max-thinking.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/mistral-raw-stop-reason.test.ts` | [AI-INDEPENDENT](#ai-independent) |
| M | `packages/ai/test/mistral-reasoning-mode.test.ts` | [AI-INDEPENDENT](#ai-independent) |
| M | `packages/ai/test/mistral-tool-schema.test.ts` | [AI-INDEPENDENT](#ai-independent) |
| M | `packages/ai/test/model-catalog-types.test.ts` | [AI-CATALOG](#ai-catalog) |
| M | `packages/ai/test/model-data-validation.test.ts` | [AI-CATALOG](#ai-catalog) |
| M | `packages/ai/test/models-runtime.test.ts` | [AI-CATALOG](#ai-catalog) |
| M | `packages/ai/test/node-http-proxy.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/oauth-auth.test.ts` | [AI-AUTH](#ai-auth) |
| M | `packages/ai/test/oauth-device-code.test.ts` | [AI-AUTH](#ai-auth) |
| M | `packages/ai/test/openai-codex-cache-affinity-e2e.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-codex-oauth.test.ts` | [AI-AUTH](#ai-auth) |
| M | `packages/ai/test/openai-codex-stream.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-completions-cache-control-format.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-completions-empty-tools.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-completions-prompt-cache.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-completions-raw-stop-reason.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-completions-reasoning-details.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-completions-response-model.test.ts` | [AI-CATALOG](#ai-catalog) |
| M | `packages/ai/test/openai-completions-retry.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-completions-thinking-as-text.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-completions-tool-choice.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-completions-tool-result-images.test.ts` | [AI-IMAGE-GEN](#ai-image-gen) |
| M | `packages/ai/test/openai-responses-cache-affinity-e2e.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-responses-compat.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-responses-empty-tool-result.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-responses-foreign-toolcall-id.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-responses-message-id.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-responses-partial-json-cleanup.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-responses-reasoning-replay-e2e.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-responses-terminal-event.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openai-responses-tool-result-images.test.ts` | [AI-IMAGE-GEN](#ai-image-gen) |
| M | `packages/ai/test/openrouter-cache-control-models.test.ts` | [AI-CATALOG](#ai-catalog) |
| M | `packages/ai/test/openrouter-cache-write-repro.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/openrouter-images.test.ts` | [AI-IMAGE-GEN](#ai-image-gen) |
| M | `packages/ai/test/openrouter-oauth.test.ts` | [AI-AUTH](#ai-auth) |
| M | `packages/ai/test/overflow.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/pi-messages.test.ts` | [AI-INDEPENDENT](#ai-independent) |
| M | `packages/ai/test/provider-error-body-passthrough.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/provider-error-body-regression.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/provider-retry.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/providers.test.ts` | [AI-CATALOG](#ai-catalog) |
| M | `packages/ai/test/qwen-token-plan-models.test.ts` | [AI-CATALOG](#ai-catalog) |
| M | `packages/ai/test/radius-oauth.test.ts` | [AI-INDEPENDENT](#ai-independent) |
| M | `packages/ai/test/reasoning-options.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/responseid.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/retry.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/stream.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/supports-xhigh.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/text.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/together-models.test.ts` | [AI-CATALOG](#ai-catalog) |
| M | `packages/ai/test/tokens.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/tool-call-id-normalization.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/tool-call-without-result.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/total-tokens.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/transform-messages-copilot-openai-to-anthropic.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/unicode-surrogate.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/uuid.test.ts` | [AI-CATALOG](#ai-catalog) |
| M | `packages/ai/test/validation.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/xai-oauth.test.ts` | [AI-AUTH](#ai-auth) |
| M | `packages/ai/test/xai-responses.test.ts` | [AI-AUTH](#ai-auth) |
| M | `packages/ai/test/xhigh.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/xiaomi-models.test.ts` | [AI-CATALOG](#ai-catalog) |
| M | `packages/ai/test/xiaomi-token-plan-ams-anthropic-empty-signature-smoke.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/ai/test/zen.test.ts` | [AI-PROTOCOL](#ai-protocol) |
| M | `packages/coding-agent/test/agent-session-auto-compaction-queue.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/agent-session-branching.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/agent-session-compaction.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/agent-session-concurrent.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/agent-session-dynamic-provider.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/agent-session-dynamic-tools.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/agent-session-retry.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/agent-session-runtime-events.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/agent-session-stats.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/agent-session-tree-navigation.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/ansi-utils.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/args.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/assistant-message.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/auth-storage.test.ts` | [CODING-MODELS](#coding-models) |
| M | `packages/coding-agent/test/bash-close-hang-windows.test.ts` | [CODING-TOOLS](#coding-tools) |
| M | `packages/coding-agent/test/bash-execution-width.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/block-images.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/branch-summary-extensions.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/cache-stats.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/changelog.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/clipboard-image-bmp-conversion.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/clipboard-image.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/clipboard-native.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/clipboard.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/compaction-extensions-example.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/compaction-extensions.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/compaction-serialization.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/compaction-summary-reasoning.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/compaction.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/config-value-migration.test.ts` | [CODING-CONFIG](#coding-config) |
| M | `packages/coding-agent/test/config.test.ts` | [CODING-CONFIG](#coding-config) |
| M | `packages/coding-agent/test/credential-print.test.ts` | [CODING-MODELS](#coding-models) |
| M | `packages/coding-agent/test/custom-message.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/edit-tool-legacy-input.test.ts` | [CODING-TOOLS](#coding-tools) |
| M | `packages/coding-agent/test/edit-tool-no-full-redraw.test.ts` | [CODING-TOOLS](#coding-tools) |
| M | `packages/coding-agent/test/experimental.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/export-html-skill-block.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/export-html-whitespace.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/export-html-xss.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/extensions-discovery.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/extensions-input-event.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/extensions-runner.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/external-editor.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/file-mutation-queue.test.ts` | [CODING-TOOLS](#coding-tools) |
| M | `packages/coding-agent/test/first-time-setup-fork.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/first-time-setup.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/footer-data-provider.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/footer-width.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/format-resume-command.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/frontmatter.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/git-merge-and-resolve-extension.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/git-ssh-url.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/git-update.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/http-dispatcher.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/image-process.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/image-processing.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/image-resize-callers.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/initial-message.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/input-transform-streaming-example.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/interactive-mode-anthropic-warning.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/interactive-mode-clone-command.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/interactive-mode-compaction.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/interactive-mode-import-command.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/interactive-mode-startup-input.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/interactive-mode-status.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/interactive-mode-suspend.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/keybindings-migration.test.ts` | [CODING-CONFIG](#coding-config) |
| M | `packages/coding-agent/test/llama-extension.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/max-thinking.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/model-registry.test.ts` | [CODING-MODELS](#coding-models) |
| M | `packages/coding-agent/test/model-resolver.test.ts` | [CODING-MODELS](#coding-models) |
| M | `packages/coding-agent/test/model-runtime-auth-options.test.ts` | [CODING-MODELS](#coding-models) |
| M | `packages/coding-agent/test/model-runtime-cloudflare-compat.test.ts` | [CODING-MODELS](#coding-models) |
| M | `packages/coding-agent/test/model-runtime-modify-models-compat.test.ts` | [CODING-MODELS](#coding-models) |
| M | `packages/coding-agent/test/models-store.test.ts` | [CODING-MODELS](#coding-models) |
| M | `packages/coding-agent/test/oauth-selector.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/package-command-paths.test.ts` | [CODING-TOOLS](#coding-tools) |
| M | `packages/coding-agent/test/package-manager-ssh.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/package-manager.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/path-utils.test.ts` | [CODING-TOOLS](#coding-tools) |
| M | `packages/coding-agent/test/paths.test.ts` | [CODING-TOOLS](#coding-tools) |
| M | `packages/coding-agent/test/pi-user-agent.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/plan-mode-extension.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/plan-mode-utils.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/print-mode.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/prompt-templates.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/radius.test.ts` | [CODING-MODELS](#coding-models) |
| M | `packages/coding-agent/test/remote-catalog-provider.test.ts` | [CODING-MODELS](#coding-models) |
| M | `packages/coding-agent/test/resolve-config-value.test.ts` | [CODING-CONFIG](#coding-config) |
| M | `packages/coding-agent/test/resource-loader.test.ts` | [CODING-CONFIG](#coding-config) |
| M | `packages/coding-agent/test/restore-sandbox-env.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/rpc-client-clone.test.ts` | [CODING-RPC](#coding-rpc) |
| M | `packages/coding-agent/test/rpc-client-process-exit.test.ts` | [CODING-RPC](#coding-rpc) |
| M | `packages/coding-agent/test/rpc-jsonl.test.ts` | [CODING-RPC](#coding-rpc) |
| M | `packages/coding-agent/test/rpc-prompt-response-semantics.test.ts` | [CODING-RPC](#coding-rpc) |
| M | `packages/coding-agent/test/rpc.test.ts` | [CODING-RPC](#coding-rpc) |
| M | `packages/coding-agent/test/runtime-credentials.test.ts` | [CODING-MODELS](#coding-models) |
| M | `packages/coding-agent/test/sdk-openrouter-attribution.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/sdk-session-manager.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/sdk-skills.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/sdk-stream-options.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/session-cwd.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/session-file-invalid.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/session-id-readonly.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/session-info-modified-timestamp.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/session-manager/build-context.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/session-manager/custom-session-id.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/session-manager/file-operations.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/session-manager/labels.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/session-manager/migration.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/session-manager/save-entry.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/session-manager/tree-traversal.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/session-selector-path-delete.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/session-selector-rename.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/session-selector-search.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/settings-manager-bug.test.ts` | [CODING-CONFIG](#coding-config) |
| M | `packages/coding-agent/test/settings-manager.test.ts` | [CODING-CONFIG](#coding-config) |
| M | `packages/coding-agent/test/skills.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/startup-session-name.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/status-indicator.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/stdout-cleanliness.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/suite/agent-session-bash-persistence.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/agent-session-compaction.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/agent-session-model-extension.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/agent-session-prompt.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/agent-session-queue.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/agent-session-retry-events.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/agent-session-runtime.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/lax-message-content.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/suite/regressions/1717-2113-agent-session-event-settlement.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/regressions/2023-queued-slash-command-followup.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/suite/regressions/2753-reload-stale-resource-settings.test.ts` | [CODING-CONFIG](#coding-config) |
| M | `packages/coding-agent/test/suite/regressions/2781-skill-collision-precedence.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/suite/regressions/2791-fswatch-error-crash.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/suite/regressions/2835-tools-allowlist-filters-extension-tools.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/suite/regressions/2860-replaced-session-context.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/regressions/3217-scoped-model-order.test.ts` | [CODING-MODELS](#coding-models) |
| M | `packages/coding-agent/test/suite/regressions/3302-find-path-glob.test.ts` | [CODING-TOOLS](#coding-tools) |
| C | `packages/coding-agent/test/suite/regressions/3303-find-nested-gitignore.test.ts` | [CL-TOOLS](#cl-tools) |
| M | `packages/coding-agent/test/suite/regressions/3317-network-connection-lost-retry.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/suite/regressions/3592-no-builtin-tools-keeps-extension-tools.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/suite/regressions/3616-settings-inmemory-reload.test.ts` | [CODING-CONFIG](#coding-config) |
| M | `packages/coding-agent/test/suite/regressions/3686-session-name-event.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/regressions/3688-tree-cancel-compacting.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/suite/regressions/3982-message-end-cost-override.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/suite/regressions/4167-thinking-toggle-pending-tool-render.test.ts` | [CODING-TOOLS](#coding-tools) |
| M | `packages/coding-agent/test/suite/regressions/5080-signal-shutdown-extension-cleanup.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/suite/regressions/5109-exclude-tools.test.ts` | [CODING-TOOLS](#coding-tools) |
| M | `packages/coding-agent/test/suite/regressions/5208-late-bash-output.test.ts` | [CODING-TOOLS](#coding-tools) |
| M | `packages/coding-agent/test/suite/regressions/5217-compaction-reason.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/regressions/5303-bash-output-truncation.test.ts` | [CODING-TOOLS](#coding-tools) |
| M | `packages/coding-agent/test/suite/regressions/5433-extension-oauth-prompt-input.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/suite/regressions/5596-missing-theme-export.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/suite/regressions/5661-uppercase-header-values.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/suite/regressions/5724-sigterm-signal-exit.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/suite/regressions/5868-rpc-unknown-command-id.test.ts` | [CODING-RPC](#coding-rpc) |
| M | `packages/coding-agent/test/suite/regressions/5943-session-start-notify.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/regressions/5996-session-name-newlines.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/regressions/6019-explicit-provider-retry-message.test.ts` | [CODING-MODELS](#coding-models) |
| M | `packages/coding-agent/test/suite/regressions/6162-extension-active-tools-next-turn.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/suite/regressions/6260-inline-extension-naming.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/suite/regressions/6324-branch-summary-ambient-auth.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/regressions/6363-agent-settled-event.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/suite/regressions/6647-compaction-retries-transient-stream-drop.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/regressions/6904-dns-transport-retry.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/suite/regressions/6949-unavailable-scoped-model.test.ts` | [CODING-MODELS](#coding-models) |
| M | `packages/coding-agent/test/suite/regressions/6999-models-json-hot-reload.test.ts` | [CODING-MODELS](#coding-models) |
| M | `packages/coding-agent/test/suite/regressions/7209-model-selector-filter-resets-selection.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/suite/regressions/extension-factory-cache.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/suite/regressions/pre-prompt-compaction-no-continue.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/regressions/startup-session-rebind-duplicate-subscription.test.ts` | [CODING-SESSION](#coding-session) |
| M | `packages/coding-agent/test/suite/regressions/tree-during-streaming.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/syntax-highlight.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/system-prompt.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/test-harness.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/theme-detection.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/theme-export.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/theme-picker.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/tool-execution-component.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/tools.test.ts` | [CODING-TOOLS](#coding-tools) |
| M | `packages/coding-agent/test/tree-selector.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/trigger-compact-extension.test.ts` | [DIFF-LISP-ECOSYSTEM](#diff-lisp-ecosystem) |
| M | `packages/coding-agent/test/truncate-to-width.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/trust-manager.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| M | `packages/coding-agent/test/trust-selector.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/user-message.test.ts` | [CODING-INTERACTIVE](#coding-interactive) |
| M | `packages/coding-agent/test/version-check.test.ts` | [CODING-CLI-SDK](#coding-cli-sdk) |
| C | `packages/tui/test/autocomplete.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/bug-regression-isimageline-startswith-bug.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/editor.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/fuzzy.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/input.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/keybindings.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/keys.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/markdown.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/overlay-non-capturing.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/overlay-options.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/overlay-short-content.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/regression-overlay-cjk-boundary.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/regression-regional-indicator-width.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/select-list.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/stdin-buffer.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/tab-width.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/terminal-colors.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/terminal-image.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/terminal.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/truncate-to-width.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/truncated-text.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/tui-cell-size-input.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/tui-overlay-style-leak.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/tui-render.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/tui-shrink.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/word-navigation.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/wrap-ansi.test.ts` | [CL-TUI](#cl-tui) |
<!-- TEST-MANIFEST-END -->

## 5. Fixed implementation sequence

The user approved the order Wave 0 → pulled-forward TUI → Wave 1 → 2 → 3 → 5.
Goal 5 contains only the first two entries; Wave 1 has not started.

| Order | Status | Scope | Verification gate |
|---|---|---|---|
| Wave 0 | complete | `U-SEARCH-GITIGNORE` and `U-TUI-RI` | both regressions are `C`; no `U` remains |
| TUI (former Wave 4) | implemented, awaiting manual acceptance | complete 27-file TUI baseline test surface | 582 TUI checks, PTY/live smoke, manual checklist |
| Wave 1 | not started | shared OpenAI-Completions/Responses and Anthropic compatibility; compatible providers/catalogs | generated fixtures plus credential-gated smokes |
| Wave 2 | not started | exact agent harness, session v3, queues, print/JSON and RPC | reference harness/session/RPC tests |
| Wave 3 | not started | independent APIs and auth flows | protocol fixtures and available live credentials |
| Wave 5 | not started | SQLite storage, server and eval harness | migration/reopen/fork, Unix-socket RPC and eval smokes |

Compatible providers reuse Wave 1 adapters; RPC depends on Wave 2 session
state; server depends on RPC; evals should exercise the completed public
runtime rather than a temporary parallel harness.

## 6. Reproduction commands

```bash
git cat-file -e 71efc6f0c1909874ec8c944637a9ae7fc0e2d508^{commit}
git worktree add --detach /tmp/cadr-parity-71efc6f0 \
  71efc6f0c1909874ec8c944637a9ae7fc0e2d508
git -C /tmp/cadr-parity-71efc6f0 rev-parse HEAD

find /tmp/cadr-parity-71efc6f0/packages -type f -name '*.test.ts' |
  sed 's#^/tmp/cadr-parity-71efc6f0/##' | sort
for p in ai agent coding-agent tui storage server evals; do
  printf '%s ' "$p"
  find "/tmp/cadr-parity-71efc6f0/packages/$p" \
    -type f -name '*.test.ts' | wc -l
done

find /tmp/cadr-parity-71efc6f0/packages/ai/src/providers \
  -maxdepth 1 -type f | wc -l
find /tmp/cadr-parity-71efc6f0/packages/ai/src/providers \
  -maxdepth 1 -type f -name '*.models.ts' | wc -l
sed -n '/export function builtinProviders/,/^}/p' \
  /tmp/cadr-parity-71efc6f0/packages/ai/src/providers/all.ts

awk '/^<!-- TEST-MANIFEST-BEGIN -->/{flag=1;next}
     /^<!-- TEST-MANIFEST-END -->/{exit}
     flag' docs/parity-map.md |
  rg -o 'packages/[^` ]+\.test\.ts' | sort > /tmp/cadr-map-tests
find /tmp/cadr-parity-71efc6f0/packages -type f -name '*.test.ts' |
  sed 's#^/tmp/cadr-parity-71efc6f0/##' | sort > /tmp/cadr-baseline-tests
test "$(wc -l < /tmp/cadr-map-tests)" -eq 352
test "$(sort -u /tmp/cadr-map-tests | wc -l)" -eq 352
diff -u /tmp/cadr-baseline-tests /tmp/cadr-map-tests

./scripts/test-cl.sh
test -z "$(git status --porcelain --untracked-files=no)"
git status --short |
  rg '^\?\? docs/(parity-map\.md|progress/goal-v4\.md)$'
```

Spot checks:

```bash
git -C /tmp/cadr-parity-71efc6f0 show HEAD:packages/ai/src/providers/all.ts |
  sed -n '/export function builtinProviders/,/^}/p'
git -C /tmp/cadr-parity-71efc6f0 show \
  HEAD:packages/coding-agent/src/core/session-manager.ts | sed -n '1,170p'
git -C /tmp/cadr-parity-71efc6f0 show \
  HEAD:packages/server/src/ipc/protocol.ts | sed -n '1,170p'
git -C /tmp/cadr-parity-71efc6f0 show \
  HEAD:packages/storage/sqlite-node/src/sqlite/migrations/001_initial.sql
```
