# Parity map

<!-- GOAL12_LEDGER baseline=53fa77ccd8a279eb87e92294ef3687b03ff80112 source=595/518/77/0 examples=99/99/0 -->

## 1. Scope and counting rules

This is the **behavior ledger**. It tracks externally observable contracts and
their test evidence. It does not substitute for the per-file source
dispositions in `docs/source-parity.md`, the non-functional budgets in
`docs/performance.md`, or the visible-copy/style/geometry audit in
`docs/presentation-parity.md`. `examples/manifest.sexp` is an auxiliary
runnable-example inventory, not another ledger.

Behavioral baseline: `earendil-works/pi@53fa77ccd8a279eb87e92294ef3687b03ff80112`
(`v0.84.1-38-g53fa77ccd`). No release tag leads this commit, so Goal 10 Part B
is a user-adjudicated no-op; the fixed baseline remains unchanged.
The audit uses the detached worktree `/tmp/cadr-parity-53fa77ccd`. The former
baseline `71efc6f0c1909874ec8c944637a9ae7fc0e2d508` and its checkout are retained
only as a historical delta anchor; neither is a current parity source of truth.

Status meanings:

- **已实现**: the complete externally observable behavior in the row is
  implemented and has linked Common Lisp evidence.
- **缺失**: absent or only partially implemented. A partial adapter is not
  promoted to “已实现”.
- **有意差异**: an existing user-approved difference listed in
  [README](../README.md#differences-from-typescript-pi). Unless a row says
  otherwise, these remain limited to language/build ecosystem differences;
  `originator=cadr` is the explicit Goal 9 Part C identity-only exception,
  while Goal 10 Part D adds only the separately approved tool restarts and
  opt-in Slynk debugging service.

Test classification is deliberately strict:

- `C` = covered: every relevant behavior in that TypeScript test file is
  covered by the linked CL tests.
- `U` = applicable but uncovered: the production behavior exists, but the exact
  regression is missing from the CL suite.
- `M` = corresponds to a missing feature: the file contains behavior outside the
  current implementation, including files that are only partially covered.
- `N/A` = 不适用 by per-file user adjudication, solely because the
  implementation language or build ecosystem necessarily differs.
  `N/A` must not be expanded by the implementer on their own, and must not
  conceal any behavior that still applies.

Live-gated blocks use **credential-gate equivalence**. When the baseline wraps
a live block in `skipIf(!KEY)` (or an equivalent availability gate), cadr may
classify the file `C` when the deterministic behavior is covered and the CL
suite proves the equivalent credential gate. In this environment the DeepSeek
API key and the OpenCode Go API key credential are available: their
corresponding live tests must actually run and pass. Every other credentialed
live block, including Ollama while no local daemon is deployed, must skip under
the same condition as the baseline. A fixture never substitutes for an
available live credential. Offline deterministic behavior remains subject to
the strict whole-file rule above.

Part reports must list every classification changed by applying this rule.
Verification-level labels (`fixture`, `live-ready`, `live-proven`) remain
separate from `C`/`U`/`M`; a `C` row does not imply universal live coverage.

### Mechanical inventory

| Package | Files at baseline | `*.test.ts` |
|---|---:|---:|
| `ai` | 310 | 121 |
| `agent` | 71 | 18 |
| `coding-agent` | 590 | 189 |
| `tui` | 75 | 28 |
| `storage` | 18 | 0 |
| `server` | 17 | 0 |
| `evals` | 19 | 4 |
| `protocol` | 17 | 3 |
| **Total** | **1117** | **363** |

`storage` and `server` contain no `*.test.ts` at the audit commit. SQLite
coverage lives in two `agent/test/harness/sqlite-*.test.ts` files. `evals`
contains four deterministic `*.test.ts` files and retains two `*.eval.ts`
suites; the new `protocol` package contains three deterministic test files.

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
| Native JSON, SSE, HTTP, retry | 已实现 | [json](../src/cadr-ai/json.lisp), [sse](../src/cadr-ai/sse.lisp), [HTTP transport](../src/cadr-ai/transport/http.lisp), [streaming JSON](../src/cadr-ai/capabilities/streaming-json.lisp), [event streams](../src/cadr-ai/capabilities/event-stream.lisp), and [retry](../src/cadr-ai/support/retry.lisp), including proxy CONNECT in [CL-GOAL12-AI](#cl-goal12-ai) |
| Anthropic/OpenAI Responses/OpenAI Completions/Google core adapters | 已实现 | Complete deterministic compatibility, transport, history, retry, image and provider-matrix behavior is covered by [CL-AI-WAVE3](#cl-ai-wave3) and the retained Wave 1 evidence |
| Remaining independent APIs | 已实现 | Azure Responses, Bedrock Converse Stream, Vertex, Mistral Conversations, OpenAI Codex Responses and `pi-messages` have independent request/response/auth coverage in [CL-AI-WAVE3](#cl-ai-wave3) |
| 38 built-in text providers | 已实现 | The registry is baseline-exact at 38 IDs; the non-baseline `ollama` registration was removed. See [CL-AI-WAVE3](#cl-ai-wave3) |
| Static catalogs and cost calculation | 已实现 | [generated catalog](../src/cadr-ai/models.generated.lisp) plus the schema/structure/per-shard integrity gate and deterministic native generators in [CL-GOAL12-AI](#cl-goal12-ai) cover the exact pinned 37-file, 1153-model snapshot |
| API-key and OAuth/device authentication | 已实现 | [auth](../src/cadr-ai/auth.lisp), [OAuth core](../src/cadr-ai/oauth/pkce.lisp), [provider OAuth flows](../src/cadr-ai/oauth/providers/), and [CL-GOAL12-AI](#cl-goal12-ai) cover all provider-owned login/refresh/store/filter contracts, including GitHub Copilot, Kimi, OpenRouter, Radius and xAI |
| Image input | 已实现 | [CL-AI-IMAGE](#cl-ai-image) |
| Image generation / OpenRouter Images | 已实现 | Exact 40-model snapshot and request/result/error behavior in [CL-AI-WAVE3](#cl-ai-wave3) |
| Dynamic provider/faux-provider public runtime | 已实现 | [models runtime](../src/cadr-ai/runtime/models.lisp) covers provider mutation, credentials, refresh/filter/dispatch; [faux provider](../src/cadr-ai/runtime/faux-provider.lisp) owns the deterministic provider contract |
| `pi-ai` CLI | 已实现 | The equivalent provider login/logout surface is integrated into cadr's `auth`/`/login` commands; separate npm-bin packaging is an approved Lisp build-ecosystem difference |

#### Provider ledger

Verification labels describe what is reachable with the credentials observed
during this audit, not what was rerun: `fixture` means deterministic local
replay/unit conversion; `live-ready` means a usable credential is present;
`live-proven` links an existing cadr credential-gated FiveAM result. No unavailable
credential is inferred.

| # | Provider | Protocol | Authentication | Status and main difficulty | Reachable verification |
|---:|---|---|---|---|---|
| 1 | `amazon-bedrock` | `bedrock-converse-stream` | AWS chain/profile/access keys or bearer token | 已实现; profile/access-key/bearer resolution, SigV4, region/inference-profile routing and Converse EventStream | fixture; no AWS credential |
| 2 | `ant-ling` | `openai-completions` | `ANT_LING_API_KEY` | 已实现 (fixture cross-implementation comparison); Wave 1 registry/catalog/request/error path | fixture only |
| 3 | `anthropic` | `anthropic-messages` | API key, bearer auth token, or subscription OAuth | 已实现; full deterministic compatibility, OAuth and stream/error matrix | fixture; no live credential |
| 4 | `azure-openai-responses` | `azure-openai-responses` | `AZURE_OPENAI_API_KEY` plus deployment endpoint | 已实现; Azure URL/deployment normalization and Responses replay | fixture; no Azure credential |
| 5 | `cerebras` | `openai-completions` | `CEREBRAS_API_KEY` | 已实现 (fixture cross-implementation comparison); Wave 1 registry/catalog/request/error path | fixture only |
| 6 | `cloudflare-ai-gateway` | Anthropic + Completions + Responses | Cloudflare key, account ID, gateway ID | 已实现; placeholder materialization and gateway-specific headers across three APIs | fixture; no Cloudflare credential |
| 7 | `cloudflare-workers-ai` | `openai-completions` | Cloudflare key and account ID | 已实现; endpoint materialization | fixture; no Cloudflare credential |
| 8 | `deepseek` | `openai-completions` | `DEEPSEEK_API_KEY` | 已实现; complete deterministic matrix plus a real streaming gate | fixture + [live-proven](../test/cadr-ai/live-provider-test.lisp) |
| 9 | `fireworks` | Anthropic + Completions | `FIREWORKS_API_KEY` | 已实现; multi-API catalog routing | fixture; no Fireworks credential |
| 10 | `github-copilot` | Anthropic + Completions + Responses | Copilot token or GitHub device OAuth | 已实现; device flow, token exchange, model filtering and Copilot headers | fixture; no GitHub Copilot credential |
| 11 | `google` | `google-generative-ai` | `GEMINI_API_KEY` | 已实现; complete deterministic Gemini 3.6 and compatibility matrix | fixture; no Gemini credential |
| 12 | `google-vertex` | `google-vertex` | API key or ADC/service account + project/location | 已实现; API-key/ADC resolution, RS256 JWT exchange and regional endpoint construction | fixture; no Vertex credential |
| 13 | `groq` | `openai-completions` | `GROQ_API_KEY` | 已实现 (fixture cross-implementation comparison); Wave 1 registry/catalog/request/error path | fixture only |
| 14 | `huggingface` | `openai-completions` | `HF_TOKEN` | 已实现 (fixture cross-implementation comparison); Wave 1 registry/catalog/request/error path | fixture only |
| 15 | `kimi-coding` | `anthropic-messages` | `KIMI_API_KEY` or device OAuth | 已实现; device flow and subscription headers | fixture; no Kimi credential |
| 16 | `minimax` | `anthropic-messages` | `MINIMAX_API_KEY` | 已实现 (fixture cross-implementation comparison); Wave 1 registry/catalog/request/error path | fixture only |
| 17 | `minimax-cn` | `anthropic-messages` | `MINIMAX_CN_API_KEY` | 已实现 (fixture cross-implementation comparison); Wave 1 regional registry/catalog/request/error path | fixture only |
| 18 | `mistral` | `mistral-conversations` | `MISTRAL_API_KEY` | 已实现; independent protocol, reasoning mode, raw stop and schema sanitization | fixture; no Mistral credential |
| 19 | `moonshotai` | `openai-completions` | `MOONSHOT_API_KEY` | 已实现 (fixture cross-implementation comparison); Wave 1 registry/catalog/request/error path | fixture only |
| 20 | `moonshotai-cn` | `openai-completions` | `MOONSHOT_API_KEY` | 已实现 (fixture cross-implementation comparison); Wave 1 regional registry/catalog/request/error path | fixture only |
| 21 | `nvidia` | `openai-completions` | `NVIDIA_API_KEY` | 已实现; shared adapter and exact catalog | fixture; no NVIDIA credential |
| 22 | `openai` | `openai-responses` | `OPENAI_API_KEY` | 已实现; full deterministic Responses compatibility matrix | fixture; no OpenAI API-key credential |
| 23 | `openai-codex` | `openai-codex-responses` | ChatGPT OAuth | 已实现; one provider identity across login/store/default routing and Codex response transport; `originator=cadr` is an approved client-attribution difference | deterministic login/request tests + [Goal 9 Part C live gate](acceptance/goal-v9-part-c.md) |
| 24 | `opencode` | Anthropic + Google + Completions + Responses | `OPENCODE_API_KEY` | 已实现; four-API model routing | fixture; no OpenCode credential |
| 25 | `opencode-go` | Anthropic + Completions + Responses | `OPENCODE_API_KEY` | 已实现; three-API model routing | fixture; no OpenCode credential |
| 26 | `openrouter` | `openai-completions` | API key or OAuth | 已实现; OAuth shapes, cache-control variants and exact catalog | fixture; no OpenRouter credential |
| 27 | `qwen-token-plan` | `openai-completions` | `QWEN_TOKEN_PLAN_API_KEY` | 已实现 (fixture cross-implementation comparison); Wave 1 plan registry/catalog/request/error path | fixture only |
| 28 | `qwen-token-plan-cn` | `openai-completions` | `QWEN_TOKEN_PLAN_CN_API_KEY` | 已实现 (fixture cross-implementation comparison); Wave 1 regional plan registry/catalog/request/error path | fixture only |
| 29 | `radius` | `pi-messages` | API key or Radius OAuth | 已实现; dynamic gateway config/catalog, PKCE authorization and independent stream protocol | fixture; no Radius credential |
| 30 | `together` | `openai-completions` | `TOGETHER_API_KEY` | 已实现 (fixture cross-implementation comparison); Wave 1 registry/catalog/request/error path | fixture only |
| 31 | `vercel-ai-gateway` | `anthropic-messages` | `AI_GATEWAY_API_KEY` | 已实现; gateway headers and exact catalog | fixture; no Vercel credential |
| 32 | `xai` | Completions + Responses | API key or xAI device OAuth | 已实现; dual API, trusted device polling and model routing | fixture; no xAI credential |
| 33 | `xiaomi` | `openai-completions` | `XIAOMI_API_KEY` | 已实现 (fixture cross-implementation comparison); Wave 1 MiMo catalog/compat/request/error path | fixture only |
| 34 | `xiaomi-token-plan-ams` | `openai-completions` | `XIAOMI_TOKEN_PLAN_AMS_API_KEY` | 已实现; regional plan endpoint and empty-signature behavior | fixture; no credential |
| 35 | `xiaomi-token-plan-cn` | `openai-completions` | `XIAOMI_TOKEN_PLAN_CN_API_KEY` | 已实现; regional plan endpoint/catalog | fixture; no credential |
| 36 | `xiaomi-token-plan-sgp` | `openai-completions` | `XIAOMI_TOKEN_PLAN_SGP_API_KEY` | 已实现; regional plan endpoint/catalog | fixture; no credential |
| 37 | `zai` | `openai-completions` | `ZAI_API_KEY` | 已实现; endpoint/catalog | fixture; no ZAI credential |
| 38 | `zai-coding-cn` | `openai-completions` | `ZAI_CODING_CN_API_KEY` | 已实现; regional coding endpoint/catalog | fixture; no ZAI credential |

The separate `openrouter` image provider and dynamic `faux` provider are not
counted among the 38 text providers; both are implemented as public cadr
runtimes with deterministic tests.

The former non-baseline `ollama` registry entry is removed. Ollama remains a
valid custom OpenAI-compatible live target when explicitly configured, but no
local daemon is deployed in this environment, so its credential/availability
gate skips exactly as the corresponding baseline live blocks do.

### 2.2 `agent`

Reference public surface includes `Agent`, the agent loop and queue modes,
before/after tool hooks, `AgentHarness`, execution environments, filesystem
and in-memory/JSONL/SQLite session repo/storage interfaces, compaction,
skills, prompt templates, system-prompt formatting, tools, truncation, and
proxy/default-stream helpers.

| Surface | Status | cadr evidence or gap |
|---|---|---|
| Agent lifecycle and tool loop | 已实现 | [agent loop](../src/cadr-agent/loop/agent-loop.lisp), [CL-AGENT-LOOP](#cl-agent-loop) |
| Sequential/parallel tools, validation, hook rewrite/block | 已实现 | [tool](../src/cadr-agent/tool.lisp), [schema](../src/cadr-agent/schema.lisp), [CL-AGENT-SCHEMA](#cl-agent-schema), [CL-EXT](#cl-ext) |
| Busy guard | 已实现 | [runtime](../src/cadr-agent/runtime.lisp), [CL-WAVE2-AGENT](#cl-wave2-agent) |
| Steering/follow-up queues and queue modes | 已实现 | [CL-WAVE2-AGENT](#cl-wave2-agent) |
| `AgentHarness`, environment, repo/storage public abstractions | 已实现 | [CL-WAVE2-HARNESS](#cl-wave2-harness) |
| Tree session and compaction core | 已实现 | [CL-WAVE2-SESSION](#cl-wave2-session) |
| Built-in read/write/edit/bash/find/grep/ls harness set | 已实现 | Exact public tool names and execution-environment behavior are covered by [CL-PART-B](#cl-part-b) |
| Skills/templates/system prompt | 有意差异 | Lisp registrations replace Markdown/TS resource formats; [CL-PART-B](#cl-part-b) |
| Stream configuration/provider-request hooks and permanent shutdown | 已实现 | [CL-WAVE2-HARNESS](#cl-wave2-harness), [CL-GOAL9-HARNESS](#cl-goal9-harness) |
| Tool-failure condition/restarts | 有意差异 | Lisp-native `retry-tool-call`/`skip-tool-call`/`abort-agent-run` and event 34 `:tool-call-error`; default behavior and all baseline wires remain unchanged. [CL-GOAL10-D](#cl-goal10-d) |

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

cadr currently exposes the complete baseline contract plus the intentional
`--slynk <port>` debugging option. The latter is default-off and fixed to
loopback; it is not counted as missing or additional baseline behavior.
Historically, the early implementation exposed `--provider`, `--model`, `--base-url`,
`--system-prompt`, `--continue`, `--resume`, repeatable `--extension`,
`--mode text|json|rpc`, `--print/-p`, `--no-tui`, `--help`, and `--version`.

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
| Interactive TUI and line fallback | 已实现 | [bootstrap](../src/cadr-cli/bootstrap/main.lisp), [command controller](../src/cadr-cli/bootstrap/commands.lisp), [interactive controller](../src/cadr-cli/interactive/controller.lisp), [frame](../src/cadr-cli/interactive/frame.lisp), [CL-TUI](#cl-tui) |
| Text/JSON print and RPC modes | 已实现 | [CL-WAVE2-MODES](#cl-wave2-modes), [CL-WAVE2-RPC](#cl-wave2-rpc) |
| Full CLI option/command contract | 已实现 | [arguments](../src/cadr-cli/arguments.lisp), [CL-PART-B](#cl-part-b) |
| Built-in commands | 已实现 | Package/config/auth/session/model/theme/tree/import/clone and interactive commands are covered by [CL-PART-B](#cl-part-b) |
| Public SDK/runtime/services | 已实现 | [CL-PART-B](#cl-part-b) |
| Model registry/runtime and scoped model selection | 已实现 | [CL-PART-B](#cl-part-b) |
| Tool set and mutation/runtime semantics | 已实现 | [tools](../src/cadr-cli/tools/), [CL-TOOLS](#cl-tools), [CL-PART-B](#cl-part-b) |
| Session JSONL format | 已实现 | v3 header, entry union, delayed persistence and v1/v2 migration are covered by [CL-WAVE2-SESSION](#cl-wave2-session) |
| Extension capability | 有意差异 | Original lifecycle/UI/runtime capabilities are covered; only the Lisp format/ecosystem differs. [CL-WAVE2-EXT](#cl-wave2-ext), [CL-PART-B](#cl-part-b) |
| Runtime Slynk REPL | 有意差异 | Explicit `--slynk <port>`, loopback-only listener, live `active-agent`, cleanup and empty-HOME build isolation. [CL-GOAL10-D](#cl-goal10-d) |
| Settings, themes, packages, context files, remote catalogs | 已实现 | [CL-PART-B](#cl-part-b) |

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
| Reusable component tree, focus lifecycle, box/text/spacer/Markdown/image/settings/loader composition and coding-agent interactive components | 已实现 | [composition](../src/cadr-tui/composition/), [interactive components](../src/cadr-cli/interactive/components/), [CL-TUI](#cl-tui) |
| Markdown, tool block, status bar, select list, truncated text and image component | 已实现 | [components](../src/cadr-tui/components/), [CL-TUI](#cl-tui) |
| Differential renderer and terminal cleanup | 已实现 | [renderer](../src/cadr-tui/renderer/), [terminal](../src/cadr-tui/terminal.lisp), [CL-TUI](#cl-tui) |
| Autocomplete, fuzzy matching, configurable keybindings, word navigation | 已实现 | [autocomplete](../src/cadr-tui/autocomplete.lisp), [fuzzy](../src/cadr-tui/fuzzy.lisp), [keybindings](../src/cadr-tui/keybindings.lisp), [word navigation](../src/cadr-tui/word-navigation.lisp), [CL-TUI](#cl-tui) |
| Overlay stack/compositing | 已实现 | [overlay](../src/cadr-tui/overlay.lisp), [renderer](../src/cadr-tui/renderer/), [CL-TUI](#cl-tui) |
| Terminal image protocols, cell-size replies, color probing | 已实现 | [terminal image](../src/cadr-tui/terminal-image.lisp), [terminal colors](../src/cadr-tui/terminal-colors.lisp), [CL-TUI](#cl-tui) |
| Goal 5 reference component/test surface | 已实现 | [components](../src/cadr-tui/components/), [component parity tests](../test/cadr-tui/component-parity-test.lisp), [CL-TUI](#cl-tui) |

### 2.5 `storage`

The reference `@earendil-works/pi-storage-sqlite-node` exports a
`node:sqlite` adapter, migration loader/runner, `SqliteSessionRepo`, and
`SqliteSessionStorage`. Its schema contains sessions, sequences, tree
entries, materialized session/entry state and branch entries; repo operations
are create/open/list/delete/fork and storage operations implement the agent
session-storage contract.

| Surface | Status | cadr evidence or gap |
|---|---|---|
| SQLite adapter and transaction contract | 已实现 | [cadr-storage tests](../test/cadr-storage/storage-test.lisp), [STORAGE-SQLITE](#storage-sqlite) |
| Migration/schema | 已实现 | [cadr-storage tests](../test/cadr-storage/storage-test.lisp), [STORAGE-SQLITE](#storage-sqlite) |
| SQLite repo create/open/list/delete/fork | 已实现 | [cadr-storage tests](../test/cadr-storage/storage-test.lisp), [STORAGE-SQLITE](#storage-sqlite) |
| Materialized tree/branch storage | 已实现 | [cadr-storage tests](../test/cadr-storage/storage-test.lisp), [STORAGE-SQLITE](#storage-sqlite) |
| JSONL filesystem sessions | 已实现 but not a storage-package substitute | [session journal](../src/cadr-agent/session/journal.lisp), [JSONL storage](../src/cadr-agent/storage/jsonl.lisp) |

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
| Server CLI and Unix socket framing | 已实现 | [server tests](../test/cadr-server/server-test.lisp), [server smoke](../scripts/server-smoke.sh), [SERVER](#server) |
| Instance supervisor and persistence | 已实现 | [server tests](../test/cadr-server/server-test.lisp), [SERVER](#server) |
| RPC request/stream bridge and extension UI bridge | 已实现 | [server tests](../test/cadr-server/server-test.lisp), [server smoke](../scripts/server-smoke.sh), [SERVER](#server) |
| Radius registration/presence | 已实现 | credential gate, heartbeat backoff and 404 re-registration in [radius.lisp](../src/cadr-server/radius.lisp), [SERVER](#server) |
| Public server API | 已实现 | [package exports](../src/cadr-server/package.lisp), [SERVER](#server) |

### 2.7 `evals`

The reference package wraps `AgentSession` as a `vitest-evals` harness. It
requires an explicit provider/model, creates isolated project/agent
directories, normalizes messages/tool calls/results and usage, supports
prompt/reload sequences, and cleans up the session and temporary tree. The
current baseline adds artifact persistence, iteration/group planning, and
correctness/efficiency summaries with incomplete and duplicate diagnostics.

It has four deterministic `*.test.ts` files:

- `test/pi-harness.test.ts`;
- `test/vitest-evals/artifacts.test.ts`;
- `test/vitest-evals/harness-table.test.ts`;
- `test/vitest-evals/summary.test.ts`.

It also retains two `*.eval.ts` suites:

- `src/smoke.eval.ts`: exact “Paris” end-to-end response and usage identity;
- `src/extensions.eval.ts`: model creates, reloads and invokes a `hello`
  extension, then the harness checks extension paths, tool definitions and
  normalized tool-call results.

| Surface | Status | cadr evidence or gap |
|---|---|---|
| Generic eval harness and normalized transcript/usage | 已实现 | [eval tests](../test/cadr-evals/evals-test.lisp), [pi harness tests](../test/cadr-evals/pi-harness-test.lisp), [CL-GOAL9-EVALS](#cl-goal9-evals) |
| Artifacts, harness table, reporter lifecycle and summaries | 已实现 | [artifacts](../test/cadr-evals/artifacts-test.lisp), [harness table](../test/cadr-evals/harness-table-test.lisp), [reporter](../test/cadr-evals/reporter-test.lisp), [summary](../test/cadr-evals/summary-test.lisp), [CL-GOAL9-EVALS](#cl-goal9-evals) |
| Explicit provider/model runner | 已实现 | [run-evals](../scripts/run-evals.sh), [CL-GOAL9-EVALS](#cl-goal9-evals) |
| Smoke eval | 已实现 | faux unit gate plus [DeepSeek/Codex live gate](../test/cadr-evals/live-evals-test.lisp), [EVALS](#evals) |
| Self-extension eval | 已实现 | isolated write/reload/invoke gate plus baseline/candidate prompt table, native source/API/loader/tool-call judge and source-artifact reporter lifecycle in [extension authoring tests](../test/cadr-evals/extension-authoring-test.lisp), [EVALS](#evals) |

### 2.8 `protocol`

The current baseline adds the standalone remote-session v2 wire package. Its
public contract is strict CBOR encoding/decoding, four-byte big-endian length
framing, and validated client/server message codecs. Cadr implements the same
contract in pure Lisp without adding a dependency.

| Surface | Status | cadr evidence or gap |
|---|---|---|
| CBOR value subset, limits and rejection semantics | 已实现 | [CBOR tests](../test/cadr-protocol/cbor-test.lisp), [CL-GOAL9-PROTOCOL](#cl-goal9-protocol) |
| Fragmented/coalesced bounded framing | 已实现 | [framing tests](../test/cadr-protocol/framing-test.lisp), [CL-GOAL9-PROTOCOL](#cl-goal9-protocol) |
| Version 2 client/server schemas and codecs | 已实现 | [protocol tests](../test/cadr-protocol/protocol-test.lisp), [CL-GOAL9-PROTOCOL](#cl-goal9-protocol) |

## 3. Gap and evidence index

### What each test layer can answer (goal 20 P0-3)

Three layers cover the example extensions, and their boundaries do not
overlap — a reader must not take any single count (such as the FiveAM
check total) as thickness:

| Layer | Sees | Cannot see |
|---|---|---|
| Source greps (`goal20-example-games-test.lisp` shape locks) | that a text/defect shape is present or absent in the file | any behavior; a grep passes without executing a line |
| Loader suites (`goal12-examples-test.lisp` registration/load) | that the entry loads diagnostics-free and registers its surface | rendering, state changes, repaints |
| Render differential (example scenarios) | the drawn screens on user-driven paths | agent-driven paths ([EXAMPLES-AGENT-DRIVEN-REDRAW-GAP](#examples-agent-driven-redraw-gap)); anything a textCovering class absorbs |

The behavior tier added for the three games (construct → mutate → render
→ assert: `goal20-snake-behavior-render-reflects-state`,
`goal20-invaders-behavior-render-reflects-state`,
`goal20-ttt-agent-action-repaints-the-live-overlay`) closes the
construct-and-render gap for those files only; the remaining examples
keep the loader-suite tier as their strongest behavioral evidence.

### Implemented evidence

| ID | Common Lisp tests |
|---|---|
| <a id="cl-ai-types"></a>`CL-AI-TYPES` | [`USAGE-DEFAULTS-AND-TOTAL`, `CONSTRUCTORS-RETAIN-UNIFIED-MESSAGE-DATA`](../test/cadr-ai/types-test.lisp), [`COMPLETE-RESPONSE-FIXTURES-NORMALIZE-MESSAGES-AND-USAGE`](../test/cadr-ai/provider-responses-test.lisp) |
| <a id="cl-ai-stream"></a>`CL-AI-STREAM` | [`RECORDED-SSE-FIXTURES-NORMALIZE-EVENTS-AND-FINAL-MESSAGE`, `STREAM-ENDING-WITHOUT-PROVIDER-TERMINAL-EVENT-IS-AN-ERROR`, `STREAM-ABORT-PRESERVES-PARTIAL-CONTENT-AND-TERMINATES`](../test/cadr-ai/provider-streams-test.lisp), [`SSE-FRAMING-*`](../test/cadr-ai/sse-test.lisp), [`SSE-REQUEST-EXPLICITLY-DISABLES-READ-TIMEOUT`](../test/cadr-ai/http-test.lisp) |
| <a id="cl-ai-history"></a>`CL-AI-HISTORY` | [`ORPHANED-TOOL-CALLS-RECEIVE-SYNTHETIC-ERROR-RESULTS`, `FOREIGN-HISTORY-IS-MADE-SAFE-FOR-GEMINI-3.6`, `CONSECUTIVE-ANTHROPIC-TOOL-RESULTS-SHARE-ONE-USER-TURN`, `INCOMPLETE-AND-EMPTY-ASSISTANT-MESSAGES-ARE-NOT-REPLAYED`](../test/cadr-ai/provider-history-test.lisp) |
| <a id="cl-ai-payload"></a>`CL-AI-PAYLOAD` | [`PROVIDER-REQUEST-PAYLOADS-MATCH-REFERENCE-FIXTURES`, `PROVIDER-REQUEST-PATHS-AND-AUTH-HEADERS`, `GEMINI-3.6-OMITS-DEPRECATED-SAMPLING-PARAMETERS`](../test/cadr-ai/provider-payloads-test.lisp) |
| <a id="cl-ai-compat"></a>`CL-AI-COMPAT` | [Anthropic adaptive/disabled thinking, cache/eager/strict tool compatibility; OpenAI Completions/Responses reasoning, cache and affinity; Google thinking/tool mode](../test/cadr-ai/provider-compat-test.lisp), with exact [request fixtures](../test/fixtures/requests/) |
| <a id="cl-ai-wave1"></a>`CL-AI-WAVE1` | [12 independent provider registry/catalog/default-payload/missing-key tests](../test/cadr-ai/provider-wave1-test.lisp), [fixed 143-model catalog fixture](../test/fixtures/catalogs/wave1-provider-models.json), and [`BUILT-IN-PROVIDER-REGISTRY-IS-COMPLETE`](../test/cadr-ai/provider-registry-test.lisp) |
| <a id="cl-ai-image"></a>`CL-AI-IMAGE` | [`EACH-WIRE-PROTOCOL-ENCODES-IMAGE-CONTENT`, `UNSUPPORTED-IMAGE-INPUT-FAILS-BEFORE-TRANSPORT`](../test/cadr-ai/image-model-test.lisp) |
| <a id="cl-ai-error-retry"></a>`CL-AI-ERROR-RETRY` | [`COMPLETE-CHAT-NORMALIZES-API-ERRORS`](../test/cadr-ai/provider-responses-test.lisp), [`RETRYABLE-COMPLETE-REQUESTS-RESPECT-CAP-AND-RETRY-AFTER`, `NONRETRYABLE-COMPLETE-REQUEST-IS-NOT-RETRIED`, `NATIVE-HTTP-STATUSES-RETAIN-API-BODY-AND-RETRY-POLICY`, `STREAM-RETRIES-BEFORE-PROVIDER-EVENTS-WITHOUT-DUPLICATING-START`](../test/cadr-ai/retry-test.lisp), [`CONTEXT-OVERFLOW-COMPACTS-ONCE-AND-RETRIES-WITHOUT-THE-ERROR-BRANCH`](../test/cadr-agent/compaction-test.lisp) |
| <a id="cl-ai-oauth"></a>`CL-AI-OAUTH` | [`OPENAI-AUTHORIZATION-URL-USES-APPROVED-CADR-ORIGINATOR-DIFFERENCE`, `ANTHROPIC-AUTHORIZATION-URL-MATCHES-FIXED-REFERENCE`, `OAUTH-CALLBACK-PARSER-VALIDATES-PATH-AND-STATE`, `OAUTH-REFRESH-IS-DOUBLE-CHECKED-UNDER-LOCK`, `OPENAI-OAUTH-USES-CODEX-URL-AND-APPROVED-CADR-ORIGINATOR-HEADER`, `EXPIRED-OPENAI-TOKEN-REFRESHES-ONCE-THEN-BUILDS-REQUEST`](../test/cadr-ai/auth-test.lisp) |
| <a id="cl-ai-deepseek"></a>`CL-AI-DEEPSEEK` | [`OPENAI-COMPLETIONS-BUILDS-TOOL-HISTORY`, `OPENAI-COMPLETIONS-PARSES-COMPLETE-TOOL-CALL-AND-USAGE`, `RECORDED-DEEPSEEK-CHAT-COMPLETIONS-STREAM`](../test/cadr-ai/openai-completions-test.lisp) |
| <a id="cl-ai-wave3"></a>`CL-AI-WAVE3` | [independent protocols, exact 38-provider/1153-model catalog, SigV4, Vertex RS256/ADC, OAuth/device flows and dynamic Radius](../test/cadr-ai/provider-wave3-test.lisp); [model runtime and credentials](../test/cadr-ai/models-runtime-test.lisp); [faux provider](../test/cadr-ai/faux-provider-test.lisp); [context/overflow/retry/schema/UUID utilities](../test/cadr-ai/utilities-test.lisp); [40-model OpenRouter image generation](../test/cadr-ai/image-generation-test.lisp); available [DeepSeek](../test/cadr-ai/live-provider-test.lisp) and explicit-model [OpenCode Go](../test/cadr-cli/live-test.lisp) live gates, plus deterministic login/default-route coverage |
| <a id="cl-goal12-ai"></a>`CL-GOAL12-AI` | [capability primitives](../test/cadr-ai/goal12-capabilities-test.lisp), [provider wire contracts](../test/cadr-ai/goal12-provider-capabilities-test.lisp), [complete OAuth provider contracts](../test/cadr-ai/goal12-auth-test.lisp), [model-data/generator contracts](../test/cadr-ai/goal12-model-data-test.lisp), and [Codex WebSocket/cache/probe contracts](../test/cadr-ai/goal12-codex-websocket-test.lisp): full cadr-ai suite green, 0 skip, 0 fail |
| <a id="cl-goal9-ai"></a>`CL-GOAL9-AI` | [Bedrock error metadata](../test/cadr-ai/bedrock-error-metadata-test.lisp) and [Bedrock structured failure plus GPT-5.6 pricing/provider metadata](../test/cadr-ai/provider-wave3-test.lisp) |
| <a id="cl-goal9-harness"></a>`CL-GOAL9-HARNESS` | [permanent, idempotent shutdown; active/preflight/mutation/tree task settlement; post-shutdown rejection](../test/cadr-agent/shutdown-test.lisp) |
| <a id="cl-goal9-coding"></a>`CL-GOAL9-CODING` | [session/print/JSON/RPC/extension workflows](../test/cadr-cli/goal9-a2-workflows-test.lisp), [interactive structure and snapshots](../test/cadr-cli/goal9-a2-interactive-test.lisp), [malformed package manifest](../test/cadr-cli/part-b-package-test.lisp), and [Markdown extension/TUI bridge](../test/cadr-cli/extensions-test.lisp) |
| <a id="cl-goal9-tui"></a>`CL-GOAL9-TUI` | [alternate-screen viewport/input/image/link/selection/restore](../test/cadr-tui/alt-screen-test.lisp), [terminal grapheme widths](../test/cadr-tui/unicode-test.lisp), [Markdown transformer width](../test/cadr-tui/components-test.lisp), and [CLI frontend integration](../test/cadr-cli/tui-test.lisp) |
| <a id="cl-goal9-evals"></a>`CL-GOAL9-EVALS` | [pi harness](../test/cadr-evals/pi-harness-test.lisp), [artifacts](../test/cadr-evals/artifacts-test.lisp), [harness table](../test/cadr-evals/harness-table-test.lisp), and [summary](../test/cadr-evals/summary-test.lisp) |
| <a id="cl-goal9-protocol"></a>`CL-GOAL9-PROTOCOL` | [CBOR](../test/cadr-protocol/cbor-test.lisp), [framing](../test/cadr-protocol/framing-test.lisp), and [v2 schemas/codecs](../test/cadr-protocol/protocol-test.lisp) |
| <a id="cl-goal10-d"></a>`CL-GOAL10-D` | [tool condition/restart and default-path tests](../test/cadr-agent/tool-loop-test.lisp), [event 34 lifecycle/parallel tests](../test/cadr-agent/extensions-wave2-test.lisp), [event-set freeze](../test/cadr-agent/extensions-wave3-test.lisp), and [real Slynk protocol/build-isolation tests](../test/cadr-cli/remote-repl-test.lisp) |
| <a id="cl-goal12-core"></a>`CL-GOAL12-CORE` | [branch collection/generation, message projection, proxy streaming and replaceable execution context](../test/cadr-agent/goal12-core-capabilities-test.lisp), plus [auth guidance, event bus, timings, JSON/path/shell/watch/tool-manager, bounded output and built-in tool context](../test/cadr-cli/goal12-core-capabilities-test.lisp) |
| <a id="cl-goal12-examples"></a>`CL-GOAL12-EXAMPLES` | [99-file example manifest, entrypoint loading, registration-surface and edge-case tests](../test/cadr-cli/goal12-examples-test.lisp): 99 functionally equivalent Lisp ports; 0 source-axis gaps, with load/behavior coverage open for 14 ports as [EXAMPLES-LOAD-GAP](#examples-load-gap); the final compaction/prompt-options/session-HTTP call chains were approved in [scope amendment 3](proposals/goal-v12-api-scope-amendment-3.md) |
| <a id="cl-agent-loop"></a>`CL-AGENT-LOOP` | [`SIMPLE-TURN-EMITS-REFERENCE-LIFECYCLE-ORDER`, `ERROR-AND-ABORT-STOP-THE-RUN-CLEANLY`](../test/cadr-agent/loop-test.lisp), [`TOOL-CALL-RESULT-AND-NEXT-MODEL-TURN-COMPLETE`](../test/cadr-agent/tool-loop-test.lisp) |
| <a id="cl-agent-schema"></a>`CL-AGENT-SCHEMA` | [`NATIVE-SCHEMA-VALIDATES-NESTED-TOOL-ARGUMENTS`, `NATIVE-SCHEMA-SUPPORTS-COMPOSITION-AND-SCALAR-CONSTRAINTS`, `NATIVE-SCHEMA-DEFINITION-REJECTS-MALFORMED-KEYWORDS`](../test/cadr-agent/schema-test.lisp) |
| <a id="cl-compaction"></a>`CL-COMPACTION` | [`AUTOMATIC-COMPACTION-USES-CURRENT-MODEL-AND-CONTINUES-THE-PROMPT`, `CONTEXT-OVERFLOW-COMPACTS-ONCE-AND-RETRIES-WITHOUT-THE-ERROR-BRANCH`](../test/cadr-agent/compaction-test.lisp) |
| <a id="cl-session"></a>`CL-SESSION` | [`SESSION-V2-BRANCHES-FROM-ANY-NODE-AND-PERSISTS-BOTH-PATHS`, `SESSION-V1-LOAD-MIGRATES-ATOMICALLY-WITHOUT-LOSING-ENVELOPE-FIELDS`, `SESSION-V2-REJECTS-DUPLICATE-IDS-AND-DANGLING-PARENTS`, `SESSION-LIST-RESUME-AND-HTML-EXPORT-COVER-THE-ENTIRE-TREE`](../test/cadr-agent/session-v2-test.lisp), [`SESSION-JSONL-ROUND-TRIPS-ALL-FIRST-VERSION-MESSAGE-TYPES`](../test/cadr-agent/session-test.lisp) |
| <a id="cl-ext"></a>`CL-EXT` | [`EXTENSION-REGISTRATION-*`, hook, reload and resource-precedence tests](../test/cadr-agent/extensions-test.lisp), [discovery/install/self-extension tests](../test/cadr-cli/extensions-test.lisp) |
| <a id="cl-tools"></a>`CL-TOOLS` | [file tools](../test/cadr-cli/file-tools-test.lisp), [search tools](../test/cadr-cli/search-tools-test.lisp), [bash](../test/cadr-cli/bash-test.lisp) |
| <a id="cl-cli"></a>`CL-CLI` | [config/auth](../test/cadr-cli/config-auth-test.lisp), [REPL/tool loop](../test/cadr-cli/repl-test.lisp), [retry tests](../test/cadr-ai/retry-test.lisp) |
| <a id="cl-tui"></a>`CL-TUI` | [Unicode/layout](../test/cadr-tui/unicode-test.lisp), [ANSI wrapping](../test/cadr-tui/wrap-ansi-test.lisp), [truncation](../test/cadr-tui/truncate-to-width-test.lisp), [keys](../test/cadr-tui/keys-test.lisp), [keybindings](../test/cadr-tui/keybindings-test.lisp), [stdin buffering](../test/cadr-tui/stdin-buffer-test.lisp), [autocomplete](../test/cadr-tui/autocomplete-test.lisp), [editor](../test/cadr-tui/editor-parity-test.lisp), [single-line input](../test/cadr-tui/input-component-test.lisp), [components](../test/cadr-tui/component-parity-test.lisp), [composition protocol](../test/cadr-tui/composition-test.lisp), [coding-agent interactive components](../test/cadr-cli/goal12-tui-composition-test.lisp), [overlays](../test/cadr-tui/overlay-test.lisp), [terminal colors](../test/cadr-tui/terminal-colors-test.lisp), [terminal images](../test/cadr-tui/terminal-image-test.lisp), [renderer](../test/cadr-tui/renderer-test.lisp), [terminal parity](../test/cadr-tui/terminal-parity-test.lisp), [frontend projection](../test/cadr-cli/tui-test.lisp) |
| <a id="cl-wave2-agent"></a>`CL-WAVE2-AGENT` | [queue and abort/continue semantics](../test/cadr-agent/queue-test.lisp), [retry and settlement](../test/cadr-agent/retry-test.lisp), [agent lifecycle/tool loop](../test/cadr-agent/loop-test.lisp) |
| <a id="cl-wave2-harness"></a>`CL-WAVE2-HARNESS` | [resources/skills/system prompt](../test/cadr-agent/resources-test.lisp), [UTF-8 truncation](../test/cadr-agent/truncate-test.lisp), [execution environment](../test/cadr-agent/execution-env-test.lisp), [memory/JSONL repo/storage](../test/cadr-agent/storage-test.lisp), [SQLite adapter/migrations](../test/cadr-agent/sqlite-storage-test.lisp) |
| <a id="cl-wave2-session"></a>`CL-WAVE2-SESSION` | [v3 disk format and migration](../test/cadr-agent/session-v3-test.lisp), [tree/context/compaction](../test/cadr-agent/storage-test.lisp), [CLI resume and migration](../test/cadr-cli/session-command-test.lisp) |
| <a id="cl-wave2-ext"></a>`CL-WAVE2-EXT` | [legacy source compatibility gate](../test/cadr-agent/extensions-test.lisp), [approved lifecycle/UI/runtime expansion](../test/cadr-agent/extensions-wave2-test.lisp), [RPC UI process fixture](../test/fixtures/rpc-process-client.py) |
| <a id="cl-wave2-modes"></a>`CL-WAVE2-MODES` | [mode selection, stdin, text and JSON](../test/cadr-cli/modes-test.lisp), [real-process mode/SIGTERM gate](../scripts/test-wave2-process-modes.sh), [credential-gated live print](../test/cadr-cli/live-test.lisp) |
| <a id="cl-wave2-rpc"></a>`CL-WAVE2-RPC` | [framing, command/response/event/UI/bash semantics](../test/cadr-cli/rpc-test.lisp), [real-process intervention/UI/EOF gate](../scripts/test-wave2-process-modes.sh) |
| <a id="cl-part-b"></a>`CL-PART-B` | [CLI/options](../test/cadr-cli/part-b-cli-test.lisp), [configuration/resources](../test/cadr-cli/part-b-config-test.lisp), [models/auth](../test/cadr-cli/part-b-models-test.lisp), [tools](../test/cadr-cli/part-b-tools-test.lisp), [SDK/utilities](../test/cadr-cli/part-b-sdk-test.lisp), [interactive/controllers/images](../test/cadr-cli/part-b-interactive-test.lisp), [packages](../test/cadr-cli/part-b-package-test.lisp), [extensions](../test/cadr-cli/extensions-test.lisp), and [llama.cpp](../test/cadr-cli/llama-extension-test.lisp) |

### Missing-feature IDs

| ID | Missing behavior |
|---|---|
| <a id="ai-protocol"></a>`AI-PROTOCOL` | closed by Goal 8 Part A; see [CL-AI-WAVE3](#cl-ai-wave3) |
| <a id="ai-independent"></a>`AI-INDEPENDENT` | closed by Goal 8 Part A; see [CL-AI-WAVE3](#cl-ai-wave3) |
| <a id="ai-auth"></a>`AI-AUTH` | closed by Goal 8 Part A; see [CL-AI-WAVE3](#cl-ai-wave3) |
| <a id="ai-catalog"></a>`AI-CATALOG` | closed by Goal 8 Part A; see [CL-AI-WAVE3](#cl-ai-wave3) |
| <a id="ai-image-gen"></a>`AI-IMAGE-GEN` | closed by Goal 8 Part A; see [CL-AI-WAVE3](#cl-ai-wave3) |
| <a id="agent-harness"></a>`AGENT-HARNESS` | closed by Wave 2 harness coverage and Goal 9 permanent shutdown/task tracking; see [CL-WAVE2-HARNESS](#cl-wave2-harness) and [CL-GOAL9-HARNESS](#cl-goal9-harness) |
| <a id="coding-rpc"></a>`CODING-RPC` | closed by Wave 2 RPC and Goal 8 Wave 5 server/client packaging; see [SERVER](#server) |
| <a id="coding-cli-sdk"></a>`CODING-CLI-SDK` | closed by Goal 8 Part B; see [CL-PART-B](#cl-part-b) |
| <a id="coding-models"></a>`CODING-MODELS` | closed by Goal 8 Part B; see [CL-PART-B](#cl-part-b) |
| <a id="coding-session"></a>`CODING-SESSION` | closed by Goal 8 Part B; see [CL-PART-B](#cl-part-b) |
| <a id="coding-tools"></a>`CODING-TOOLS` | closed by Goal 8 Part B; see [CL-PART-B](#cl-part-b) |
| <a id="coding-config"></a>`CODING-CONFIG` | closed except the approved `config.test.ts` build-ecosystem `N/A`; see [CL-PART-B](#cl-part-b) |
| <a id="coding-interactive"></a>`CODING-INTERACTIVE` | closed by Goal 8 Part B; see [CL-PART-B](#cl-part-b) |
| <a id="storage-sqlite"></a>`STORAGE-SQLITE` | closed by Goal 8 Wave 5; [standalone storage checks](../test/cadr-storage/storage-test.lisp) cover adapter, migrations, repo and materialized state |
| <a id="server"></a>`SERVER` | closed by Goal 8 Wave 5; [server checks](../test/cadr-server/server-test.lisp) plus the [native Unix-socket smoke](../scripts/server-smoke.sh) cover the package |
| <a id="evals"></a>`EVALS` | closed by Goal 8 Wave 5 and expanded for the current baseline by [CL-GOAL9-EVALS](#cl-goal9-evals); credential-gated DeepSeek/Codex suites remain in [live evals](../test/cadr-evals/live-evals-test.lisp) |
| <a id="diff-lisp-ecosystem"></a>`DIFF-LISP-ECOSYSTEM` | approved Lisp extension/skill/template/package format and implementation/build-language differences; capability gaps inside those systems remain separately missing |
| <a id="examples-load-gap"></a>`EXAMPLES-LOAD-GAP` | **open** (recorded 2026-08-14, goal 20 Part F): no deterministic gate loads or drives the 14 example ports `examples/rpc-extension-ui.lisp` and `examples/sdk/01`–`13.lisp` — the goal 12 entrypoint-load suite covers `:entry-p` extension rows only, no render-diff scenario drives them, and `goal12-sdk-test.lisp` tests the SDK APIs they demonstrate, not the files. Capability existence is ledgered on the source axis (`docs/source-parity.md` class `SP-F2`); until a load or behavior gate exists, their runnability is unverified |
| <a id="llama-extension-entry-gap"></a>`LLAMA-EXTENSION-ENTRY-GAP` | **open** (recorded 2026-08-14, goal 20 Part F): no test references any symbol of `src/cadr-cli/extensions/llama/extension.lisp` (the llama extension entry, 464 lines, 17 top-level functions) — `llama-extension-test.lisp` covers the sibling client/provider/huggingface modules only. Capability existence is ledgered on the source axis (`docs/source-parity.md` class `SP-F4`); the entry's registration, auth and command behavior is unverified |
| <a id="examples-agent-driven-redraw-gap"></a>`EXAMPLES-AGENT-DRIVEN-REDRAW-GAP` | **open** (recorded 2026-08-14, goal 20 P0-2): every render-diff example checkpoint is user-keystroke driven, and the framework repaints after each input event — so the differential can never see a "state changed on the agent's execution path but nothing repainted" defect. The tic-tac-toe instance of that defect (no `tui` handle, zero repaint requests; baseline `tic-tac-toe.ts:389-393`) was found by the user in a real terminal and is fixed with a FiveAM behavior lock (`goal20-ttt-agent-action-repaints-the-live-overlay`), but the differential blind spot itself remains: adding agent-driven scenarios changes the gate's obligation unit and awaits adjudication with the Part F 6.5 proposal |

### Applicable but uncovered backlog

There are no `U` or `M` files in the strict manifest. Goal 5 closed
`U-SEARCH-GITIGNORE` and `U-TUI-RI`; Goal 8 Parts A and B closed the remaining
applicable files; Goal 9 Part A closed all 11 newly added files and revalidated
all 26 modified prior-`C` files. `config.test.ts` is the sole user-approved
`N/A`.

### `docs/test-matrix.md` audit notes

The matrix retains historical phase tables and adds a current Goal 9 Part A
delta table. The **2987** checks quoted by Goal 8 are a historical closeout
snapshot, not the current suite total. Earlier conservative AI notes are
superseded by Part A:
malformed stream/tool JSON, complete provider matrices, independent protocols,
auth and catalog/runtime behavior now have linked deterministic evidence.
Its Phase 6 table describes the historical JSONL v2 format. Wave 2 now
   writes exact v3 entries and migrates v1/v2 atomically.
Wave 5 added the standalone `storage`, `server`, and original eval harness;
Goal 9 adds the four comparative-eval test files and the standalone `protocol`
package.

## 4. Exhaustive `*.test.ts` manifest

The appendix is sorted exactly like
`find packages -type f -name '*.test.ts' | sort`. Each path appears once.

| Package | C | U | M | N/A | Total |
|---|---:|---:|---:|---:|---:|
| `ai` | 121 | 0 | 0 | 0 | 121 |
| `agent` | 18 | 0 | 0 | 0 | 18 |
| `coding-agent` | 188 | 0 | 0 | 1 | 189 |
| `tui` | 28 | 0 | 0 | 0 | 28 |
| `evals` | 4 | 0 | 0 | 0 | 4 |
| `protocol` | 3 | 0 | 0 | 0 | 3 |
| `storage` / `server` | 0 | 0 | 0 | 0 | 0 |
| **Total** | **362** | **0** | **0** | **1** | **363** |

All 121 AI files, the complete 28-file TUI surface, all 18 agent files, 188
applicable coding-agent files, all four eval test files, and all three protocol
test files are covered. `config.test.ts` remains the sole user-approved
build-ecosystem exception. Whole-file classification is
`362 C / 0 U / 0 M / 1 N/A`.

The baseline delta modified 26 previously classified `C` files. Each was
re-read against `71efc6f0..53fa77ccd` and revalidated rather than carried
forward by status alone:

| Package | Revalidated existing baseline files | Goal 9 evidence |
|---|---|---|
| `agent` | `harness/agent-harness.test.ts` | [CL-GOAL9-HARNESS](#cl-goal9-harness) |
| `ai` | `deferred-tools.test.ts`; `openai-completions-thinking-as-text.test.ts`; `openai-completions-tool-choice.test.ts`; `openai-completions-tool-result-images.test.ts` | [CL-GOAL9-AI](#cl-goal9-ai), [CL-AI-WAVE3](#cl-ai-wave3) |
| `coding-agent` | `args.test.ts`; `assistant-message.test.ts`; `edit-tool-no-full-redraw.test.ts`; `extensions-discovery.test.ts`; `extensions-runner.test.ts`; `interactive-mode-status.test.ts`; `user-message.test.ts` | [CL-GOAL9-CODING](#cl-goal9-coding) |
| `tui` | `editor.test.ts`; `markdown.test.ts`; `overlay-non-capturing.test.ts`; `overlay-options.test.ts`; `overlay-short-content.test.ts`; `regression-overlay-cjk-boundary.test.ts`; `tab-width.test.ts`; `terminal-colors.test.ts`; `terminal-image.test.ts`; `truncate-to-width.test.ts`; `tui-cell-size-input.test.ts`; `tui-overlay-style-leak.test.ts`; `tui-render.test.ts`; `tui-shrink.test.ts` | [CL-GOAL9-TUI](#cl-goal9-tui) |

| Class | Baseline test file | Evidence/gap |
|---|---|---|
<!-- TEST-MANIFEST-BEGIN -->
| C | `packages/agent/test/agent-loop.test.ts` | [CL-WAVE2-AGENT](#cl-wave2-agent) |
| C | `packages/agent/test/agent.test.ts` | [CL-WAVE2-AGENT](#cl-wave2-agent) |
| C | `packages/agent/test/e2e.test.ts` | [CL-WAVE2-AGENT](#cl-wave2-agent) |
| C | `packages/agent/test/harness/agent-harness-stream.test.ts` | [CL-WAVE2-HARNESS](#cl-wave2-harness) |
| C | `packages/agent/test/harness/agent-harness.test.ts` | [CL-WAVE2-HARNESS](#cl-wave2-harness) |
| C | `packages/agent/test/harness/compaction.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/agent/test/harness/nodejs-env.test.ts` | [CL-WAVE2-HARNESS](#cl-wave2-harness) |
| C | `packages/agent/test/harness/prompt-templates.test.ts` | [CL-WAVE2-HARNESS](#cl-wave2-harness) |
| C | `packages/agent/test/harness/repo.test.ts` | [CL-WAVE2-HARNESS](#cl-wave2-harness) |
| C | `packages/agent/test/harness/resource-formatting.test.ts` | [CL-WAVE2-HARNESS](#cl-wave2-harness) |
| C | `packages/agent/test/harness/session.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/agent/test/harness/skills.test.ts` | [CL-WAVE2-HARNESS](#cl-wave2-harness) |
| C | `packages/agent/test/harness/sqlite-migrations.test.ts` | [CL-WAVE2-HARNESS](#cl-wave2-harness) |
| C | `packages/agent/test/harness/sqlite-node.test.ts` | [CL-WAVE2-HARNESS](#cl-wave2-harness) |
| C | `packages/agent/test/harness/storage.test.ts` | [CL-WAVE2-HARNESS](#cl-wave2-harness) |
| C | `packages/agent/test/harness/system-prompt.test.ts` | [CL-WAVE2-HARNESS](#cl-wave2-harness) |
| C | `packages/agent/test/harness/tools.test.ts` | [CL-WAVE2-HARNESS](#cl-wave2-harness) |
| C | `packages/agent/test/harness/truncate.test.ts` | [CL-WAVE2-HARNESS](#cl-wave2-harness) |
| C | `packages/ai/test/abort.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/anthropic-adaptive-thinking-models.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/anthropic-auth-token.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/anthropic-cache-write-1h-cost.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/anthropic-eager-tool-input-compat.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/anthropic-eager-tool-input-e2e.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/anthropic-empty-thinking-signature-compat.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/anthropic-force-adaptive-thinking.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/anthropic-long-cache-retention-e2e.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/anthropic-oauth.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/anthropic-opus-4-8-smoke.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/anthropic-sse-parsing.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/anthropic-temperature-compat.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/anthropic-thinking-disable.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/anthropic-tool-name-normalization.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/azure-openai-base-url.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/azure-openai-responses-reasoning-replay.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/bedrock-convert-messages.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/bedrock-credentials.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/bedrock-custom-headers.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/bedrock-endpoint-resolution.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/bedrock-error-metadata.test.ts` | [CL-GOAL9-AI](#cl-goal9-ai) |
| C | `packages/ai/test/bedrock-models.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/bedrock-raw-stop-reason.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/bedrock-thinking-payload.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/cache-retention.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/cloudflare-stream.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/compat-env.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/constrained-sampling.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/context-estimate.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/context-overflow.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/cross-provider-handoff.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/deferred-tools.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/empty.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/env-api-keys.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/error-body.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/faux-provider.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/fetch-option.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/fireworks-models.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/github-copilot-anthropic.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/github-copilot-oauth.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/google-raw-stop-reason.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/google-shared-convert-tools.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/google-shared-gemini3-unsigned-tool-call.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/google-shared-image-tool-result-routing.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/google-thinking-disable.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/google-thinking-signature.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/google-vertex-api-key-resolution.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/image-model-data.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/image-tool-result.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/images-models.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/images.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/interleaved-thinking.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/kimi-coding-oauth.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/lax-message-content.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/lazy-module-load.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/max-thinking.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/mistral-raw-stop-reason.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/mistral-reasoning-mode.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/mistral-tool-schema.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/model-catalog-types.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/model-data-validation.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/models-runtime.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/node-http-proxy.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/oauth-auth.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/oauth-device-code.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-codex-cache-affinity-e2e.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-codex-oauth.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3); approved `originator=cadr` identity difference is locked by `OPENAI-AUTHORIZATION-URL-USES-APPROVED-CADR-ORIGINATOR-DIFFERENCE` |
| C | `packages/ai/test/openai-codex-stream.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3); approved request-header difference is locked by `OPENAI-OAUTH-USES-CODEX-URL-AND-APPROVED-CADR-ORIGINATOR-HEADER` |
| C | `packages/ai/test/openai-completions-cache-control-format.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-completions-empty-tools.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-completions-prompt-cache.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-completions-raw-stop-reason.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-completions-reasoning-details.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-completions-response-model.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-completions-retry.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-completions-thinking-as-text.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-completions-tool-choice.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-completions-tool-result-images.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-responses-cache-affinity-e2e.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-responses-compat.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-responses-empty-tool-result.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-responses-foreign-toolcall-id.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-responses-message-id.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-responses-partial-json-cleanup.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-responses-reasoning-replay-e2e.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-responses-terminal-event.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openai-responses-tool-result-images.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openrouter-cache-control-models.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openrouter-cache-write-repro.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openrouter-images.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/openrouter-oauth.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/overflow.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/pi-messages.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/provider-error-body-passthrough.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/provider-error-body-regression.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/provider-retry.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/providers.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/qwen-token-plan-models.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/radius-oauth.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/reasoning-options.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/responseid.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/retry.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/stream.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/supports-xhigh.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/text.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/together-models.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/tokens.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/tool-call-id-normalization.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/tool-call-without-result.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/total-tokens.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/transform-messages-copilot-openai-to-anthropic.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/unicode-surrogate.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/uuid.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/validation.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/xai-oauth.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/xai-responses.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/xhigh.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/xiaomi-models.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/xiaomi-token-plan-ams-anthropic-empty-signature-smoke.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/ai/test/zen.test.ts` | [CL-AI-WAVE3](#cl-ai-wave3) |
| C | `packages/coding-agent/test/agent-session-auto-compaction-queue.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/agent-session-branching.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/agent-session-compaction.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/agent-session-concurrent.test.ts` | [CL-WAVE2-AGENT](#cl-wave2-agent) |
| C | `packages/coding-agent/test/agent-session-dynamic-provider.test.ts` | [CL-WAVE2-EXT](#cl-wave2-ext) |
| C | `packages/coding-agent/test/agent-session-dynamic-tools.test.ts` | [CL-WAVE2-EXT](#cl-wave2-ext) |
| C | `packages/coding-agent/test/agent-session-retry.test.ts` | [CL-WAVE2-AGENT](#cl-wave2-agent) |
| C | `packages/coding-agent/test/agent-session-runtime-events.test.ts` | [CL-WAVE2-EXT](#cl-wave2-ext) |
| C | `packages/coding-agent/test/agent-session-stats.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/agent-session-tree-navigation.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/ansi-utils.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/args.test.ts` | [CL-WAVE2-MODES](#cl-wave2-modes) |
| C | `packages/coding-agent/test/assistant-message.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/auth-storage.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/bash-close-hang-windows.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/bash-execution-width.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/block-images.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/branch-summary-extensions.test.ts` | [CL-WAVE2-EXT](#cl-wave2-ext) |
| C | `packages/coding-agent/test/cache-stats.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/changelog.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/clipboard-image-bmp-conversion.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/clipboard-image.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/clipboard-native.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/clipboard.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/compaction-extensions-example.test.ts` | [CL-WAVE2-EXT](#cl-wave2-ext) |
| C | `packages/coding-agent/test/compaction-extensions.test.ts` | [CL-WAVE2-EXT](#cl-wave2-ext) |
| C | `packages/coding-agent/test/compaction-serialization.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/compaction-summary-reasoning.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/compaction.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/config-value-migration.test.ts` | [CL-PART-B](#cl-part-b) |
| N/A | `packages/coding-agent/test/config.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/credential-print.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/custom-message.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/edit-tool-legacy-input.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/edit-tool-no-full-redraw.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/experimental.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/export-html-skill-block.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/export-html-whitespace.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/export-html-xss.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/extensions-discovery.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/extensions-input-event.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/extensions-runner.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/external-editor.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/file-mutation-queue.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/first-time-setup-fork.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/first-time-setup.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/footer-data-provider.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/footer-width.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/format-resume-command.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/frontmatter.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/git-merge-and-resolve-extension.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/git-ssh-url.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/git-update.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/http-dispatcher.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/image-process.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/image-processing.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/image-resize-callers.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/initial-message.test.ts` | [CL-WAVE2-MODES](#cl-wave2-modes) |
| C | `packages/coding-agent/test/input-transform-streaming-example.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/interactive-mode-anthropic-warning.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/interactive-mode-clone-command.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/interactive-mode-compaction.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/interactive-mode-import-command.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/interactive-mode-startup-input.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/interactive-mode-status.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/interactive-mode-suspend.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/interactive-tui.test.ts` | [CL-GOAL9-CODING](#cl-goal9-coding), [CL-GOAL9-TUI](#cl-goal9-tui) |
| C | `packages/coding-agent/test/keybindings-migration.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/llama-extension.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/max-thinking.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/model-registry.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/model-resolver.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/model-runtime-auth-options.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/model-runtime-cloudflare-compat.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/model-runtime-modify-models-compat.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/models-store.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/oauth-selector.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/package-command-paths.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/package-manager-ssh.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/package-manager.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/path-utils.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/paths.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/pi-user-agent.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/plan-mode-extension.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/plan-mode-utils.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/print-mode.test.ts` | [CL-WAVE2-MODES](#cl-wave2-modes) |
| C | `packages/coding-agent/test/prompt-templates.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/radius.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/remote-catalog-provider.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/resolve-config-value.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/resource-loader.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/restore-sandbox-env.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/rpc-client-clone.test.ts` | [CL-WAVE2-RPC](#cl-wave2-rpc) |
| C | `packages/coding-agent/test/rpc-client-process-exit.test.ts` | [CL-WAVE2-RPC](#cl-wave2-rpc) |
| C | `packages/coding-agent/test/rpc-jsonl.test.ts` | [CL-WAVE2-RPC](#cl-wave2-rpc) |
| C | `packages/coding-agent/test/rpc-prompt-response-semantics.test.ts` | [CL-WAVE2-RPC](#cl-wave2-rpc) |
| C | `packages/coding-agent/test/rpc.test.ts` | [CL-WAVE2-RPC](#cl-wave2-rpc) |
| C | `packages/coding-agent/test/runtime-credentials.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/sdk-openrouter-attribution.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/sdk-session-manager.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/sdk-skills.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/sdk-stream-options.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/session-cwd.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/session-file-invalid.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/session-id-readonly.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/session-info-modified-timestamp.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/session-manager/build-context.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/session-manager/custom-session-id.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/session-manager/file-operations.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/session-manager/labels.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/session-manager/migration.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/session-manager/save-entry.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/session-manager/tree-traversal.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/session-selector-path-delete.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/session-selector-rename.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/session-selector-search.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/settings-manager-bug.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/settings-manager.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/skills.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/startup-session-name.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/status-indicator.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/stdout-cleanliness.test.ts` | [CL-WAVE2-MODES](#cl-wave2-modes) |
| C | `packages/coding-agent/test/suite/agent-session-bash-persistence.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/suite/agent-session-compaction.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/suite/agent-session-model-extension.test.ts` | [CL-WAVE2-EXT](#cl-wave2-ext) |
| C | `packages/coding-agent/test/suite/agent-session-prompt.test.ts` | [CL-WAVE2-AGENT](#cl-wave2-agent) |
| C | `packages/coding-agent/test/suite/agent-session-queue.test.ts` | [CL-WAVE2-AGENT](#cl-wave2-agent) |
| C | `packages/coding-agent/test/suite/agent-session-retry-events.test.ts` | [CL-WAVE2-AGENT](#cl-wave2-agent) |
| C | `packages/coding-agent/test/suite/agent-session-runtime.test.ts` | [CL-WAVE2-EXT](#cl-wave2-ext) |
| C | `packages/coding-agent/test/suite/lax-message-content.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/1717-2113-agent-session-event-settlement.test.ts` | [CL-WAVE2-EXT](#cl-wave2-ext) |
| C | `packages/coding-agent/test/suite/regressions/2023-queued-slash-command-followup.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/2753-reload-stale-resource-settings.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/2781-skill-collision-precedence.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/2791-fswatch-error-crash.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/2835-tools-allowlist-filters-extension-tools.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/2860-replaced-session-context.test.ts` | [CL-WAVE2-EXT](#cl-wave2-ext) |
| C | `packages/coding-agent/test/suite/regressions/3217-scoped-model-order.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/3302-find-path-glob.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/3303-find-nested-gitignore.test.ts` | [CL-TOOLS](#cl-tools) |
| C | `packages/coding-agent/test/suite/regressions/3317-network-connection-lost-retry.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/3592-no-builtin-tools-keeps-extension-tools.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/3616-settings-inmemory-reload.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/3686-session-name-event.test.ts` | [CL-WAVE2-EXT](#cl-wave2-ext) |
| C | `packages/coding-agent/test/suite/regressions/3688-tree-cancel-compacting.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/3982-message-end-cost-override.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/4167-thinking-toggle-pending-tool-render.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/5080-signal-shutdown-extension-cleanup.test.ts` | [CL-WAVE2-MODES](#cl-wave2-modes) |
| C | `packages/coding-agent/test/suite/regressions/5109-exclude-tools.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/5208-late-bash-output.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/5217-compaction-reason.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/suite/regressions/5303-bash-output-truncation.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/5433-extension-oauth-prompt-input.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/5596-missing-theme-export.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/5661-uppercase-header-values.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/5724-sigterm-signal-exit.test.ts` | [CL-WAVE2-MODES](#cl-wave2-modes) |
| C | `packages/coding-agent/test/suite/regressions/5868-rpc-unknown-command-id.test.ts` | [CL-WAVE2-RPC](#cl-wave2-rpc) |
| C | `packages/coding-agent/test/suite/regressions/5943-session-start-notify.test.ts` | [CL-WAVE2-EXT](#cl-wave2-ext) |
| C | `packages/coding-agent/test/suite/regressions/5996-session-name-newlines.test.ts` | [CL-WAVE2-EXT](#cl-wave2-ext) |
| C | `packages/coding-agent/test/suite/regressions/6019-explicit-provider-retry-message.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/6162-extension-active-tools-next-turn.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/6260-inline-extension-naming.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/6324-branch-summary-ambient-auth.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/suite/regressions/6363-agent-settled-event.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/6647-compaction-retries-transient-stream-drop.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/suite/regressions/6904-dns-transport-retry.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/6949-unavailable-scoped-model.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/6999-models-json-hot-reload.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/7187-malformed-package-manifest.test.ts` | [CL-GOAL9-CODING](#cl-goal9-coding) |
| C | `packages/coding-agent/test/suite/regressions/7209-model-selector-filter-resets-selection.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/extension-factory-cache.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/suite/regressions/pre-prompt-compaction-no-continue.test.ts` | [CL-WAVE2-SESSION](#cl-wave2-session) |
| C | `packages/coding-agent/test/suite/regressions/startup-session-rebind-duplicate-subscription.test.ts` | [CL-WAVE2-EXT](#cl-wave2-ext) |
| C | `packages/coding-agent/test/suite/regressions/tree-during-streaming.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/syntax-highlight.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/system-prompt.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/test-harness.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/theme-detection.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/theme-export.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/theme-picker.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/tool-execution-component.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/tools.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/tree-selector.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/trigger-compact-extension.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/truncate-to-width.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/trust-manager.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/trust-selector.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/user-message.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/coding-agent/test/version-check.test.ts` | [CL-PART-B](#cl-part-b) |
| C | `packages/evals/test/pi-harness.test.ts` | [CL-GOAL9-EVALS](#cl-goal9-evals) |
| C | `packages/evals/test/vitest-evals/artifacts.test.ts` | [CL-GOAL9-EVALS](#cl-goal9-evals) |
| C | `packages/evals/test/vitest-evals/harness-table.test.ts` | [CL-GOAL9-EVALS](#cl-goal9-evals) |
| C | `packages/evals/test/vitest-evals/summary.test.ts` | [CL-GOAL9-EVALS](#cl-goal9-evals) |
| C | `packages/protocol/test/cbor/cbor.test.ts` | [CL-GOAL9-PROTOCOL](#cl-goal9-protocol) |
| C | `packages/protocol/test/framing.test.ts` | [CL-GOAL9-PROTOCOL](#cl-goal9-protocol) |
| C | `packages/protocol/test/protocol.test.ts` | [CL-GOAL9-PROTOCOL](#cl-goal9-protocol) |
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
| C | `packages/tui/test/tui-alt-screen.test.ts` | [CL-GOAL9-TUI](#cl-goal9-tui) |
| C | `packages/tui/test/tui-cell-size-input.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/tui-overlay-style-leak.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/tui-render.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/tui-shrink.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/word-navigation.test.ts` | [CL-TUI](#cl-tui) |
| C | `packages/tui/test/wrap-ansi.test.ts` | [CL-TUI](#cl-tui) |
<!-- TEST-MANIFEST-END -->

## 5. Fixed implementation sequence

The user approved the historical order Wave 0 → pulled-forward TUI → Wave 1 →
2 → 3 → 5, followed by Goal 9 Part A/A2.

| Order | Status | Scope | Verification gate |
|---|---|---|---|
| Wave 0 | complete | `U-SEARCH-GITIGNORE` and `U-TUI-RI` | both regressions are `C`; no `U` remains |
| TUI (former Wave 4) | complete; manual acceptance passed 2026-07-30 | historical 27-file TUI test surface | 582 TUI checks, PTY/live smoke, user-confirmed real-terminal checklist |
| Wave 1 | complete | shared OpenAI-Completions/Responses and Anthropic compatibility; compatible providers/catalogs | generated fixtures plus credential-gated smokes |
| Wave 2 | complete | exact agent harness, session v3, queues, print/JSON and RPC | 76 reference files are `C`; 1716 CL checks plus process/live gates |
| Wave 3 | complete | independent APIs, auth flows, exact catalogs, model/image/faux runtimes | 641 AI checks plus DeepSeek and Codex OAuth live smokes |
| Goal 8 Part B | complete | complete coding-agent runtime, tools, configuration, models, packages, interactive UI and approved extension/llama surfaces | 127 former `M` files are `C`; `config.test.ts` is the sole approved `N/A`; 2905 CL checks |
| Wave 5 | complete | standalone storage packaging, server and eval harness | 23 storage + 43 server + 16 eval checks; native Unix-socket smoke; DeepSeek and Codex OAuth eval smokes |
| Goal 8 Part F | complete; user acceptance passed | historical final ledger, dependency audit, freeze anchors, README and acceptance package | Historical `351 C / 0 U / 0 M / 1 N/A`; 2987 CL checks |
| Goal 9 Part A/A2 | ledger complete; final clean-tree gate tracked in the Part A report | baseline upgrade, protocol, evals, shutdown, metadata/pricing, Markdown, manifest, alternate screen, grapheme widths and permanent faux/PTY gates | `362 C / 0 U / 0 M / 1 N/A = 363`; all 11 new files and 26 changed prior-`C` files revalidated |
| Goal 12 Part C1–C5 | complete | 19 TUI composition, 22 core, 36 AI, 2 eval, and 2 Apple Terminal modifier source capabilities; Apple Terminal is fixture-verified because the platform is unavailable locally | [source-parity ledger](source-parity.md) and Goal 12 package-specific tests |
| Goal 12 runnable examples | complete | fixed-baseline 99-file extension/SDK example surface | [CL-GOAL12-EXAMPLES](#cl-goal12-examples): 99 functionally equivalent Lisp ports and 0 gaps |

Compatible providers reuse Wave 1 adapters; RPC depends on Wave 2 session
state; server depends on RPC; evals should exercise the completed public
runtime rather than a temporary parallel harness.

## 6. Reproduction commands

```bash
git cat-file -e 53fa77ccd8a279eb87e92294ef3687b03ff80112^{commit}
git worktree add --detach /tmp/cadr-parity-53fa77ccd \
  53fa77ccd8a279eb87e92294ef3687b03ff80112
git -C /tmp/cadr-parity-53fa77ccd rev-parse HEAD

find /tmp/cadr-parity-53fa77ccd/packages -type f -name '*.test.ts' |
  sed 's#^/tmp/cadr-parity-53fa77ccd/##' | sort
for p in ai agent coding-agent tui storage server evals protocol; do
  printf '%s files=' "$p"
  git -C /tmp/cadr-parity-53fa77ccd ls-tree -r --name-only HEAD -- \
    "packages/$p" | wc -l
  printf '%s tests=' "$p"
  find "/tmp/cadr-parity-53fa77ccd/packages/$p" \
    -type f -name '*.test.ts' | wc -l
done

find /tmp/cadr-parity-53fa77ccd/packages/ai/src/providers \
  -maxdepth 1 -type f | wc -l
find /tmp/cadr-parity-53fa77ccd/packages/ai/src/providers \
  -maxdepth 1 -type f -name '*.models.ts' | wc -l
sed -n '/export function builtinProviders/,/^}/p' \
  /tmp/cadr-parity-53fa77ccd/packages/ai/src/providers/all.ts

awk '/^<!-- TEST-MANIFEST-BEGIN -->/{flag=1;next}
     /^<!-- TEST-MANIFEST-END -->/{exit}
     flag' docs/parity-map.md |
  rg -o 'packages/[^` ]+\.test\.ts' | sort > /tmp/cadr-map-tests
find /tmp/cadr-parity-53fa77ccd/packages -type f -name '*.test.ts' |
  sed 's#^/tmp/cadr-parity-53fa77ccd/##' | sort > /tmp/cadr-baseline-tests
test "$(wc -l < /tmp/cadr-map-tests)" -eq 363
test "$(sort -u /tmp/cadr-map-tests | wc -l)" -eq 363
diff -u /tmp/cadr-baseline-tests /tmp/cadr-map-tests

./scripts/test-cl.sh
git status --short
```

Spot checks:

```bash
git -C /tmp/cadr-parity-53fa77ccd show HEAD:packages/ai/src/providers/all.ts |
  sed -n '/export function builtinProviders/,/^}/p'
git -C /tmp/cadr-parity-53fa77ccd show \
  HEAD:packages/coding-agent/src/core/session-manager.ts | sed -n '1,170p'
git -C /tmp/cadr-parity-53fa77ccd show \
  HEAD:packages/server/src/ipc/protocol.ts | sed -n '1,170p'
git -C /tmp/cadr-parity-53fa77ccd show \
  HEAD:packages/storage/sqlite-node/src/sqlite/migrations/001_initial.sql
git -C /tmp/cadr-parity-53fa77ccd show \
  HEAD:packages/protocol/src/schemas.ts | sed -n '1,220p'
```
