# Pi parity gap inventory, 2026-10-23

Playbook: investigation. Read-only. No product code in this change.

Upstream is pi tag `v1.4.0` at `4a080252f06caf63a525d7873c5d94d3c23887e0`.
cadr is `cadr-migration` at `c6e1afbf8` (merge of PR #874). `BASELINE`
already names that pi commit. There is no `goalN.md` at the repo root.
Standing policy in `docs/development-policy.md` already says full parity,
and that missing credentials only lower the verification tier.

Two passes ran without sharing notes.

Method A read `packages/` at the tag (`git show v1.4.0:<path>`, `git grep`
on that tree), plus cadr `src/` and `test/`. It did not read
`docs/acceptance/`, `docs/adjudications.md`, or the parity ledgers.

Method B read `docs/acceptance/`, `docs/adjudications.md`,
`docs/parity-map.md`, `docs/source-parity.md`, and the scope proposals
those files cite. It did not inventory the tag.

Parent checks on 2026-10-23 corrected a few pass notes. The chat catalog
on this tip is the pi-ai 1.4.0 snapshot (`src/cadr-ai/models.generated.lisp`
header, PR #874). `prepareRequest` virtual-model routing is in
`src/cadr-agent/loop/turns.lisp`. TypeSafe `jev-latest` and the OpenRouter
decision classifiers are registered in `src/cadr-ai/classifiers.lisp`.
`add-mcp-server-config` exists as a function. The `pi mcp` command does
not. `packages/server` and `packages/client` are not in the v1.4.0 tree.

## 1. Package list

v1.4.0 `packages/` has these directories and no `worker` package. Worker
in this release is the codemode worker thread
(`packages/coding-agent/src/extensions/codemode/worker.ts`), Chord child
hosts (`packages/chord/src/node.ts`), and an image-resize helper inside
the coding agent. The root `README.md` package table lists chord,
telemetry, ai, durable, agent, coding-agent, and tui. Codemode, env,
mcp, and evals are real packages and are absent from that table.

| Package | What it is | User-visible | cadr counterpart |
|---|---|---|---|
| `packages/agent` `@earendil-works/pi-agent-core` | Tool-calling agent loop, steering, follow-up, events. No binary. | Yes. The CLI is built on it, and extensions import it. | `src/cadr-agent/`. Loop and queues are tested. Not a published SDK. |
| `packages/ai` `@earendil-works/pi-ai` | Provider registry, catalogs, streaming, OAuth. Bin `pi-ai`. | Yes. Library and `pi-ai list` / `pi-ai login`. | `src/cadr-ai/`. 40 provider rows. No `pi-ai` binary. |
| `packages/tui` `@earendil-works/pi-tui` | Differential terminal UI. | Yes. Users see it through `pi`. Library for other apps. | `src/cadr-tui/` plus interactive chrome in `src/cadr-cli/`. |
| `packages/coding-agent` `@earendil-works/pi-coding-agent` | The `pi` CLI. Bin `pi`. | Yes. | `src/cadr-cli/`, `src/cadr-agent/`, `src/cadr-tui/`. |
| `packages/mcp` `@earendil-works/pi-mcp` | MCP client. Stdio and Streamable HTTP. No config file of its own. | Yes. The CLI's MCP extension uses it. Other apps can import it. | Config and name checks in `src/cadr-agent/extensions/mcp-config.lisp`. No JSON-RPC client. |
| `packages/codemode` `@earendil-works/pi-codemode` | QuickJS WASM sandbox. The only capability is injected tools. | Yes. `pi --tools +codemode`, and a standalone library. | None. The string `"codemode"` is an MCP exposure value. |
| `packages/chord` `@earendil-works/chord` | Hosts, contracts, replicated JSON, RPC links. | Yes as a library. The `pi` CLI does not depend on it at 1.4.0 (`packages/coding-agent/CHANGELOG.md` records the removal). Durable and env still do. | None. |
| `packages/durable` `@earendil-works/pi-durable` | Experimental durable conversations, documents, tasks, storage. No CLI. | Yes as `npm install`. Not a `pi` subcommand. | None. `cadr-storage` stores coding-agent sessions. `src/cadr-agent/execution-env.lisp` is the local tool filesystem. |
| `packages/env` `@earendil-works/pi-env` | Rust daemon `pi-env serve` plus an `ExecutionEnv` client over SSH. | Yes for Durable hosts. Not a `pi` subcommand. | None. |
| `packages/telemetry` `@earendil-works/pi-telemetry` | Span and metric contracts. No exporter. Omitted spans are a no-op. | Yes as a library. The CLI does not import it. The install ping is a different coding-agent feature. | No span API. `enableInstallTelemetry` exists and does not call `pi.dev`. |
| `packages/evals` `@earendil-works/pi-evals` | Private in-repo evals, including a Docker docs-lift. `private: true`. The publish script drops private packages. | No. Not an installed product. | `cadr-evals` is a different in-repo harness. It does not run that Docker lift. |

The CLI surface that is already implemented and locked is large. Argv
flags, slash commands other than the holes below, tools
`read` `bash` `edit` `write` `grep` `find` `ls` `powershell`, skills,
prompt templates, themes `system` `dark` `light`, session branch,
compaction, fork, clone, import, and HTML export, and the API-key
providers in `src/cadr-ai/providers/definitions.lisp` are not rows in
the gap table. OAuth login is locked for Anthropic, GitHub Copilot,
Kimi, Codex, OpenRouter, Radius, and xAI.

## 2. Gap table

Class is `没有`, `部分`, or `有但没测试`. Effort is S (one module and
tests), M (several modules), L (a subsystem), XL (a new runtime).
Source is the pass that found it. `both` means B already had an open,
missing, or do-not-port record and A confirmed the behavior is still
absent or incomplete.

| ID | Surface | Pi behavior | Pi file | cadr now | cadr file | Class | Source | Effort |
|---|---|---|---|---|---|---|---|---|
| GAP-01 | MCP client | Connect stdio or Streamable HTTP, `tools/list`, `tools/call`, progress, cancellation. | `packages/mcp/src/client.ts`, `packages/coding-agent/src/extensions/mcp/runtime.ts` | Config is parsed. No `tools/list` or `tools/call` under `src/cadr-agent` or `src/cadr-ai`. | `src/cadr-agent/extensions/mcp-config.lisp` | 没有 | both | XL |
| GAP-02 | MCP resources | `resources/list`, templates, `resources/read`. | `packages/mcp/src/client.ts`, `packages/coding-agent/src/extensions/mcp/resources.ts` | Names `list_mcp_resources`, `list_mcp_resource_templates`, `read_mcp_resource` are reserved. Nothing reads a resource. | `src/cadr-agent/extensions/mcp-config.lisp` | 没有 | both | L |
| GAP-03 | `pi mcp` CLI | `list`, `add`, `remove`, `login`, `logout`. | `packages/coding-agent/src/extensions/mcp/cli.ts` | No subcommand. `add-mcp-server-config` is a function with tests, not a user command. | `src/cadr-cli/arguments.lisp` has `--no-mcp` only | 没有 | both | M |
| GAP-04 | MCP OAuth | PKCE, discovery, dynamic registration, refresh, `insufficient_scope`. `pi mcp login` stores tokens. | `packages/mcp/src/oauth/`, `packages/coding-agent/src/extensions/mcp/oauth.ts` | `validate-mcp-oauth` checks the config object. No token exchange. | `mcp-config.lisp`, `test/cadr-agent/mcp-config-test.lisp` | 没有 | both | L |
| GAP-05 | Codemode and its worker | QuickJS sandbox, tool `codemode` off until `--tools +codemode` or `defaultTools`, scripts call `tools.*`, `store`/`load`, `models.classify`, `models.generateImages`. Worker queue and `PI_CODEMODE_MAX_WORKERS` (default 2). Settings `codemode.mode` and `codemode.inlineBudget`. | `packages/codemode/`, `packages/coding-agent/src/extensions/codemode/`, `packages/coding-agent/docs/codemode.md`, `settings-schema.ts` | No sandbox, no tool, no worker limit, no settings keys. Exposure `"codemode"` is vocabulary only. | `src/cadr-cli/bootstrap/tools.lisp`, `mcp-config.lisp` | 没有 | both | XL |
| GAP-06 | Builtin extensions | Factories `llama.cpp`, `codemode`, `tool-search`, `mcp`. The last three are replaceable. | `packages/coding-agent/src/extensions/index.ts` | Loader factories only `llama.cpp`. `tool_search` is a base tool, so a third-party extension cannot replace the builtin. | `src/cadr-cli/extensions/loader.lisp` | 部分 | both | M |
| GAP-07 | Meta provider | `META_API_KEY` or subscription device-code OAuth, then a 24-hour key. Responses API. | `packages/ai/src/providers/meta.ts`, `packages/ai/src/auth/oauth/meta.ts` | Six chat rows can sit in the catalog. No `:meta` provider row, no OAuth file, no `META_API_KEY` reader. | `src/cadr-ai/providers/definitions.lisp` | 部分 | A | M |
| GAP-08 | ChatGPT sign-in | `OPENAI_API_KEY` or subscription "Sign in with ChatGPT" (browser or pasted redirect). OAuth hides classifier models. | `packages/ai/src/auth/oauth/openai-chatgpt.ts` | OpenAI auth type is API key only. `openai-chatgpt-sign-in-p` only detects a non-`sk-` key. | `src/cadr-ai/providers/definitions.lisp`, `src/cadr-ai/providers/openai.lisp` | 没有 | both | L |
| GAP-09 | TypeSafe credentials | Provider id `typesafe`, `TYPESAFE_API_KEY`, classifier API `typesafe-system-one`. | `packages/ai/src/providers/typesafe.ts` | `jev-latest` is registered as a classifier. No provider row and no `TYPESAFE_API_KEY` read. | `src/cadr-ai/classifiers.lisp` | 部分 | both | S |
| GAP-10 | Other classifier APIs | `openai-decisions` and `llama-cpp-classify`. | `packages/ai/src/api/openai-decisions.ts`, `packages/ai/src/api/llama-cpp-classify.ts` | No matches under `src/cadr-ai`. Cloudflare System One and TypeSafe System One exist. | `src/cadr-ai/classifiers.lisp` | 没有 | both | M |
| GAP-11 | Anthropic federation | Workload identity from `ANTHROPIC_FEDERATION_RULE_ID`, organization, identity token file, optional service account and workspace. | `packages/ai/src/providers/anthropic.ts` | Browser and copy-code OAuth are tested. No federation env names under `src/`. | `src/cadr-ai/oauth/providers/anthropic.lisp` | 没有 | A | M |
| GAP-12 | Azure API version env | `AZURE_OPENAI_API_VERSION` defaults to `v1`. | `packages/ai/src/api/azure-openai-config.ts` | Help text names the variable. The provider reads option `:azure-api-version` only. | `src/cadr-cli/arguments.lisp`, `src/cadr-ai/providers/azure-openai.lisp` | 部分 | A | S |
| GAP-13 | Request options | OpenAI and Codex `serviceTier`. Responses `reasoningSummary` is caller-controlled. Codex `textVerbosity`. Mistral `promptMode`. | `packages/ai/src/api/openai-responses.ts`, `openai-codex-responses.ts`, `mistral-conversations.ts` | Summary is hardcoded `"auto"`. Codex verbosity is hardcoded `"low"`. No `service_tier` or `prompt-mode` under `src/cadr-ai`. | `src/cadr-ai/providers/openai.lisp`, `src/cadr-ai/websocket.lisp`, `src/cadr-ai/providers/mistral.lisp` | 部分 | both | M |
| GAP-14 | Cache retention env | `PI_CACHE_RETENTION=long` is the fallback on Anthropic, Bedrock, completions, responses, and pi-messages. | those API files under `packages/ai/src/api/` | `CADR_CACHE_RETENTION` is read by Bedrock only. Other adapters take the request option and do not read the env var. | `src/cadr-ai/providers/bedrock.lisp`, `src/cadr-ai/provider.lisp` | 部分 | A | S |
| GAP-15 | OAuth callback host | `PI_OAUTH_CALLBACK_HOST` overrides the loopback bind. Default `127.0.0.1`. | `packages/ai/src/auth/oauth/anthropic.ts` and the ChatGPT, Codex, OpenRouter modules | Bind is hardcoded `127.0.0.1`. No `CADR_OAUTH_CALLBACK_HOST`. | `src/cadr-ai/oauth/callback.lisp` | 没有 | A | S |
| GAP-16 | `pi-ai` binary | `help`, `list`, `login [provider]` for OAuth providers. Writes `./auth.json`. | `packages/ai/src/cli.ts` | Login is `cadr auth` and library calls. No `pi-ai` entry. | `src/cadr-cli/models/credential-print.lisp` | 没有 | A | S |
| GAP-17 | Image catalog | Image models come from the same 1.4.0 generator as chat (`fetchOpenRouterList` with `output_modalities=image`). | `packages/ai/scripts/generate-models.ts`, `packages/ai/src/image-models.ts` | File header still says the pi-ai 0.83.0 OpenRouter image catalog. PR #874 regenerated chat metadata and did not regenerate this file. Model ids were not diffed against the npm tarball here. | `src/cadr-ai/image-models.generated.lisp` | 部分 | A | M |
| GAP-18 | JSONL export | `/export path.jsonl` and `exportSessionToJsonl`. Other paths are HTML. | `packages/coding-agent/src/core/session-export.ts`, `interactive-mode.ts` | Autocomplete text mentions `.jsonl`. `handle-session-command` always calls `export-session-html`. | `src/cadr-cli/interactive/autocomplete.lisp`, `src/cadr-cli/bootstrap/sessions.lisp` | 没有 | A | S |
| GAP-19 | `cache_warming_decision` | An extension can change the warming action. | `packages/coding-agent/src/core/extensions/types.ts` | Internal struct only. The hook name is excluded on purpose. Goal 26's done row records that exclusion. | `src/cadr-cli/cache-warmer.lisp`, `test/cadr-agent/extensions-wave3-test.lisp` | 没有 | both | M |
| GAP-20 | `tool_call` / `tool_result` | One hook each. The handler can rewrite the call or the result. | `packages/coding-agent/src/core/extensions/types.ts` | Split into `:tool-call-before`, `:tool-call-after`, `:tool-call-error`, with string aliases. Rewrite power of the aliases was not proved in this pass. Goal 26 calls the split aligned. | `src/cadr-agent/extensions/registration.lisp` | 部分 | both | S |
| GAP-21 | Virtual model registration | `registerVirtualModel` routes one request to a physical model. | `packages/coding-agent/src/core/virtual-models.ts`, `docs/virtual-models.md` | Loop routing exists. No `define-virtual-model` on the extension macros. | `src/cadr-agent/loop/turns.lisp`, `src/cadr-agent/virtual-models.lisp` | 部分 | both | M |
| GAP-22 | `compaction.modelOverrides` | Per `provider/modelId` token overrides. | `packages/coding-agent/src/core/settings-schema.ts` | No `modelOverrides` under `src/`. Other compaction fields are tested. | `src/cadr-cli/bootstrap/settings.lisp` | 没有 | A | S |
| GAP-23 | `retry.maxAgentDelayMs` | Agent backoff cap. Deprecated `retry.maxDelayMs` aliases the provider delay. | `settings-schema.ts` | No `maxAgentDelayMs` or `maxDelayMs` under `src/`. | `src/cadr-cli/sdk/settings-service.lisp` | 没有 | A | S |
| GAP-24 | Windows external editor | `externalEditor`, else `VISUAL`, else `EDITOR`, else Notepad on Windows and `nano` elsewhere. | `packages/coding-agent/src/modes/interactive/extension-editor.ts` | Fallback is always `nano`. | `settings-external-editor-command` in `src/cadr-cli/bootstrap/settings.lisp` | 部分 | A | S |
| GAP-25 | Windows and WSL key defaults | `useWindowsKeybindings` changes undo, model back, follow-up, dequeue, paste image, prompt jump, and search. | `packages/coding-agent/src/core/keybindings.ts`, `docs/keybindings.md` | Global map uses the Unix chords. Tree fold is `#+darwin` at compile time. | `src/cadr-tui/keybindings.lisp`, `src/cadr-cli/interactive/selectors/tree.lisp` | 没有 | A | M |
| GAP-26 | Windows open URL | `rundll32 url.dll,FileProtocolHandler`. The pi comment says `cmd /c start` re-parses metacharacters. | `packages/coding-agent/src/utils/open-browser.ts` | `#+win32` uses `cmd /c start "" url`. | `src/cadr-cli/interactive/controller.lisp` | 部分 | A | S |
| GAP-27 | Windows VT input | `enableVirtualTerminalInput` so Shift+Tab is not Tab. | `packages/tui/src/terminal.ts` | `virtual-terminal` is an in-memory screen buffer. No Windows console VT-input enable. | `src/cadr-tui/renderer/virtual-terminal.lisp`, `src/cadr-tui/terminal.lisp` | 没有 | A | S |
| GAP-28 | Windows right-click paste | Button 2 pastes, except when `TERM_PROGRAM` is `vscode`. | `packages/tui/src/tui-alt-screen.ts` | Mouse handler acts on the left button. | `src/cadr-tui/renderer/lifecycle-input.lisp` | 没有 | A | S |
| GAP-29 | `SIGHUP` | Exit on `SIGHUP` except on win32. `SIGTERM` always. | `packages/coding-agent/src/modes/interactive/interactive-mode.ts` | `call-with-cli-signal-handlers` enables `SIGTERM` (exit 143) and, except on win32, `SIGHUP` (exit 129). The FiveAM test throws the catch tag. It does not raise the signal. | `src/cadr-cli/bootstrap/commands.lisp`, `test/cadr-cli/goal28-exit-and-auth-test.lisp` | 有但没测试 | A | S |
| GAP-30 | tmux keyboard warning | If `TMUX` is set, `tmux show -gv` and a warning. | `interactive-mode.ts` | No `tmux show` under `src/cadr-cli`. | same | 没有 | A | S |
| GAP-31 | Self `SIGWINCH` | POSIX process signals itself to refresh size. Skipped on win32. | `packages/tui/src/terminal.ts` | Incoming `SIGWINCH` is handled. No self-signal. | `src/cadr-tui/terminal.lisp` | 没有 | A | S |
| GAP-32 | `#` autocomplete | Default triggers are `@` and `#`. | `packages/tui/src/components/editor.ts` | `@` and `/` are wired. The interactive provider leaves trigger characters nil. | `src/cadr-tui/autocomplete.lisp`, `src/cadr-cli/interactive/autocomplete.lisp` | 部分 | A | S |
| GAP-33 | Shell session env | Bash and PowerShell children receive session id, session file, provider, model, and reasoning level. | `packages/coding-agent/src/core/tools/bash.ts`, `docs/environment-variables.md` | Process markers are `AI_AGENT=cadr` and `CADR_CODING_AGENT=true`. No `CADR_SESSION_ID` or `CADR_REASONING_LEVEL` under `src/`. | `src/cadr-cli/bootstrap/main.lisp` | 没有 | A | S |
| GAP-34 | Bug-report origin | `PI_RADIUS_GATEWAY` sets the `/bug` upload origin. | `docs/environment-variables.md` | No `CADR_RADIUS_GATEWAY` under `src/`. | `src/cadr-cli/support/bug-report.lisp` | 没有 | A | S |
| GAP-35 | TUI write log | `PI_TUI_WRITE_LOG` sets a write-log path. | `packages/tui/src/terminal.ts` | No `CADR_TUI_WRITE_LOG` under `src/`. | `src/cadr-tui/terminal.lisp` | 没有 | A | S |
| GAP-36 | Two env names | `PI_CLIPBOARD_OSC52` and `PI_PROGRAM_STATUS`. | `packages/coding-agent/docs/environment-variables.md`, `packages/tui/src/terminal.ts` | Those features read the `PI_` names. Product identity allows `CADR_*` only. | `src/cadr-cli/interactive/clipboard.lisp`, `src/cadr-tui/terminal.lisp` | 部分 | A | S |
| GAP-37 | `--mode text` on a TTY | `resolveAppMode` stays interactive unless the mode is `json` or `rpc` or `--print` is set or a stdio is not a TTY. | `packages/coding-agent/src/main.ts` | `resolve-cli-mode` returns the parsed mode, so `:text` on a TTY is print. | `src/cadr-cli/arguments.lisp` | 部分 | A | S |
| GAP-38 | `/share` copy | Share via Radius or a GitHub gist. | `packages/coding-agent/src/core/slash-commands.ts` | Autocomplete says a secret gist. `share-via-radius` exists. | `src/cadr-cli/interactive/autocomplete.lisp` | 部分 | A | S |
| GAP-39 | Startup 3D egg | Clicking the logo plays `easter-egg-3d`. Upstream deleted `daxnuts.ts`. | `packages/coding-agent/src/modes/interactive/components/easter-egg-3d.ts` | `daxnuts` still runs. No 3D component. | `src/cadr-cli/interactive/components/daxnuts.lisp`, `pi-logo.lisp` | 部分 | both | M |
| GAP-40 | Chord | Hosts, contracts, hot reload, JSON links, protocol version 4, child hosts, delta and sqlite subpaths. | `packages/chord/README.md`, `packages/chord/src/index.ts` | No Chord code under `src/`. | none | 没有 | both | XL |
| GAP-41 | Durable | Conversations, documents, tasks, task graph, storage backends, optional coding tools and codemode replay. | `packages/durable/README.md` | No `pi-durable` API under `src/`. | none | 没有 | both | XL |
| GAP-42 | pi-env | SSH-deployed daemon. Ops include hello, fs, exec, pty, watch, `listFiles`. PTY is unsupported on Windows. | `packages/env/README.md`, `packages/env/daemon/src/main.rs` | No daemon. Local `execution-env` is the in-process tool filesystem. | `src/cadr-agent/execution-env.lisp` | 没有 | both | XL |
| GAP-43 | Telemetry spans | Contracts plus no-op and in-memory adapters. pi-ai and durable emit only when the caller passes a span. | `packages/telemetry/src/index.ts`, `packages/ai/README.md` | No span API. The CLI install ping is a separate exclusion in section 3. | none | 没有 | both | L |
| GAP-44 | Copilot model filter | OAuth `availableModelIds` filters the static catalog. | `packages/ai/src/providers/github-copilot.ts` | Filter code exists. No test asserts it. | `src/cadr-ai/providers/runtime-projection.lisp` | 有但没测试 | A | S |
| GAP-45 | Provider retry fields | `retry.provider.timeoutMs` and `retry.provider.maxRetryDelayMs`. | `settings-schema.ts` | Readers exist. No test names those fields. | `src/cadr-cli/sdk/settings-service.lisp` | 有但没测试 | A | S |
| GAP-46 | Env and settings locks | Implemented and unread by tests: `CADR_HARDWARE_CURSOR`, `CADR_TELEMETRY`, `CADR_TUI_ESC_TIMEOUT`, `CADR_CODING_AGENT_SESSION_DIR`, `CADR_PACKAGE_DIR`, JSON key `fullscreenWheelScrollLines`, `ZELLIJ`/`STY` mouse, SSH detection, `WT_SESSION`. | `packages/coding-agent/docs/environment-variables.md`, `settings-schema.ts` | Implementations are in the paths the TUI pass cited. Tests do not mention the names. | `src/cadr-cli/bootstrap/commands.lisp`, `src/cadr-tui/terminal.lisp`, `src/cadr-cli/arguments.lisp`, `src/cadr-tui/renderer/lifecycle-input.lisp` | 有但没测试 | A | M |
| GAP-47 | RPC behavioral tests | Handlers exist for `new_session`, model and thinking cycle commands, `compact`, `set_auto_compaction`, `set_auto_retry`, `abort_retry`, `get_session_stats`, `export_html`, `switch_session`, and the read commands `get_entries`, `get_tree`, `get_messages`, `get_commands`, `get_last_assistant_text`. | `packages/coding-agent/src/modes/rpc/rpc-types.ts` | Name pin in `goal28-registries-test.lisp`. Several have no behavioral FiveAM beyond that pin. `prompt`, `get_state`, `bash`, `abort_bash`, and `clear_queue` are tested. | `src/cadr-cli/modes/rpc/commands.lisp`, `test/cadr-cli/rpc-test.lisp` | 有但没测试 | A | M |
| GAP-48 | Tool scheduling locks | Default parallel tools. One `sequential` tool forces the batch. Shared `toolChoice` `auto` or `none`. | `packages/agent/README.md`, `packages/ai/src/types.ts` | `tool-execution-mode` and `tool-choice` exist. No test covers the batch rule or both choice values on every API. | `src/cadr-agent/extensions/providers.lisp`, `src/cadr-ai/provider.lisp` | 有但没测试 | A | M |
| GAP-49 | Small option locks | Completions `thinkingBudgets`, pi-messages `debug`, Finder file-path paste. | `packages/ai/src/api/openai-completions.ts`, `pi-messages.ts`, `packages/coding-agent/src/utils/clipboard.ts` | The code paths exist or have a native text getter. No test locks these three. | `src/cadr-ai/providers/openai-completions.lisp`, `src/cadr-ai/providers/pi-messages.lisp`, `src/cadr-cli/interactive/clipboard.lisp` | 有但没测试 | A | S |
| GAP-50 | G.17 status | Part P CL ceiling. Not a pi command. | `docs/acceptance/goal-v20-part-g.md` says `met` on 2026-09-07. `docs/adjudications.md` the same week says G.17 is `met` and Goal 20 is not reopened. | Every later alignment file, including `docs/acceptance/goal26-pi-140-alignment.md` on this tip, says G.17 stays `missing` and Goals 20, 24, 25, and 26 are not announced complete. | those acceptance files | 部分 | B | S |

The table has 50 rows. GAP-07, GAP-11, GAP-12, GAP-14 through GAP-18, GAP-22 through GAP-38, and GAP-44 through GAP-49 are in A and absent from B's open and N/A lists. B recorded GAP-19 and GAP-20 as finished omissions inside a done Goal 26 row, which is why a diff queue will not reopen them. GAP-17 is the same shape. PR #874 closed the chat catalog and left the image file on the 0.83.0 stamp.

### What B listed that is not a remaining feature gap

`docs/acceptance/goal26-evidence-v130/source-dispositions.tsv` still says
75 added files are open, 73 deleted paths must be dropped, and 1 rename
must be remapped. `docs/acceptance/goal26-pi-140-alignment.md` says not
to rewrite the v1.3.0 file. Many of the 75 paths now have cadr behavior
(tool search, themes, wheel scroll, settings readers, classifier files).
The summary was not updated. That is stale bookkeeping, not 75 missing
features.

The 73 deletions are the experimental client, server, mini worker, and
plugin tree. v1.4.0 has no `packages/server` and no `packages/client`.
`packages/coding-agent/src/experimental/` contains one file,
`source-resolver.ts`, a Node preload that applies tsconfig path aliases.
That is the same class as the jiti exclusion in section 3. The deleted
client, server, mini worker, and plugin files are not in the tag.
`docs/source-parity.md` still marks 38 of those old paths
`intentional difference` with evidence text `PENDING ADJUDICATION`.
Porting them would restore a tree pi removed.

`docs/source-parity.md` prints `3 missing` in a summary and has no verdict
cell that says `missing`. The two files Goal 22 once called missing are
`implemented`. A green source ledger does not mean the feature list above
is empty. The ledger's obligation is per old file, inside an older scope.

Goal 24 and Goal 25 pin files (`docs/acceptance/goal24-pi-0860-alignment.md`,
`docs/acceptance/goal25-pi-0861-alignment.md`) are still 进行中, with
unchecked acceptance boxes. The performance goals `docs/acceptance/goal-v24.md`
and `goal-v25.md` are `met`. The unchecked boxes are process. The behavior
they were waiting on is either in the table above or already done on this
tip.

`docs/adjudications.md` 2026-09-19 freezes Goal 28 presence TSV cells at
`status=open` (114 and 461 rows). `docs/acceptance/goal-v28.md` says the
capability goal is `met`. Those cells are a scanner rule. They are not a
second feature list.

Six `accepted-runtime-gap` rows in `docs/benchmarks/goal26-dispositions.tsv`
are sub-millisecond or small write-path slowdowns on a goal marked `met`.
They are performance dispositions.

## 3. Old N/A and scope cuts

Recommendation under the 2026-10-23 goal. "Still exclude" means the next
parts do not implement it. "Reopen" means a GAP row above owns it.

| Item | Why it was skipped | Recommendation |
|---|---|---|
| `packages/coding-agent/test/config.test.ts` whole file | `docs/parity-map.md` sole `N/A`. `docs/proposals/goal-v8-part-b.md` section 4.2. npm, pnpm, yarn, and bun install layout. cadr is an SBCL `build.sh` executable. | Still exclude. The package commands cadr does ship are tested in `test/cadr-cli/part-b-package-test.lisp`. |
| Node V8 1MiB main-screen chunking | `docs/acceptance/goal22-pi-0844-alignment.md`. No V8 string-length crash on SBCL. | Still exclude. |
| `https-proxy-agent` bundle export | Same file. Node bundle export. | Still exclude. |
| Async Kitty image conversion | Goal 24 pin file, "cadr 同步路径 N/A". | Still exclude the async scheduling. Kitty and iTerm drawing are tested in `src/cadr-tui/terminal-image.lisp`. |
| Experimental package publish path | Goal 24 pin file, "TS-only N/A". | Still exclude, and retire the row. v1.4.0 deleted that tree. See section 2. |
| Windows Store shell alias `28bea006b` | `docs/proposals/goal26-pi140-misc-scope.md`. Node `existsSync` extra stat. cadr uses `probe-file`. | Still exclude. Copying `access(F_OK)` does not change cadr's check. |
| `pi update` BOM on `managed-install.json` | Same proposal. npm managed-install layout. | Still exclude. cadr has no npm managed install. |
| Extension import `@earendil-works/pi-ai/models` | Same proposal. jiti alias. The visible helper `clamp-thinking-level` exists. | Still exclude the alias table. |
| Generated models reference and `models.schema.json` descriptions | Same proposal. Docs site and JSON Schema text. | Still exclude. `docs/adjudications.md` 2026-09-19 item 2 says user-doc content is not a parity obligation. |
| User docs `quickstart.md`, `usage.md`, `index.md`, `docs.json`, `images/`, and the "not separately ported" set (`settings.md`, `sessions.md`, `json.md`, `rpc.md`, and the rest in `docs/source-parity.md` section 2a) | README was judged enough. Platform guides called not applicable to the SBCL build. | Still exclude the pages. Behaviors those pages describe are gaps when the code is missing (tmux warning, Windows keys, shell env). |
| `packages/coding-agent/docs/windows.md` and the durable copy of the Windows shell fix | Misc-scope proposal. No cadr Windows manual. The shell behavior was ported in `src/cadr-cli/support/shell-process.lisp`. | Still exclude the page. The shell behavior stays. When GAP-41 lands, the durable copy of that shell fix is part of durable, not a second exclusion. |
| Node compile cache | `docs/acceptance/goal25-pi-0861-alignment.md`. No Lisp equivalent. | Still exclude. |
| jiti lazy load, virtual modules, Windows `.node` | Goal 24 pin file. Clipboard row says do not port `.node`. | Still exclude the loader and the native addon binaries. Command fallbacks (`pbcopy`, `clip`, `wl-copy`, `xclip`) are the behavior and are implemented. |
| `packages/tui/src/native-module-path.ts` | `docs/source-parity.md`. cadr is not a Node SEA binary. | Still exclude. |
| SP-F6 Vitest harness files | `docs/source-parity.md`. FiveAM replaces Vitest. | Still exclude the harness shape. |
| Docs-content ledger | Adjudication 2026-09-19 item 2. | Still exclude. Do not add a sixth ledger. |
| Undo byte budget | 2026-08-16 picked a number. 2026-09-19 says no cap ships. | Still no cadr-only cap. This is not a pi feature to port. |
| Install ping `GET https://pi.dev/api/report-install` | `test/cadr-cli/goal14-organization-test.lisp` `goal18-install-telemetry-has-no-egress`. Default in pi is on. | Still exclude the pi.dev request. Product identity is cadr. A phone-home needs a cadr endpoint and a user ruling. The setting itself exists. |
| `packages/evals` | Private, dropped at publish, absent from the root package table. | Still exclude. A user cannot install it. `cadr-evals` stays the in-repo harness. |
| Five render-diff examples `doom-overlay`, `github-issue-autocomplete`, `mac-system-theme`, `rpc-demo`, `ssh` | `docs/adjudications.md` 2026-08-18 Part E. WAD, live network, another host's theme contract, RPC rather than TUI. | Still exclude from the PTY differential on this host. That does not license a missing product feature. This pass did not find a core CLI feature that exists only inside those examples. |
| `argv_parse` left out of the Part O four-path close | `docs/acceptance/goal-v20-part-g.md` G.16 notes. | Still a performance-bookkeeping exclusion. The argv behavior is implemented. |
| Six `accepted-runtime-gap` rows | Operator 2026-09-08. Measured slowdowns, goal marked met. | Still performance dispositions. Not feature cuts. |
| Goal 28 `status=open` freeze | Adjudication 2026-09-19 item 6. Scanners reject any other status. | Leave the scanner rule. Do not read those cells as this inventory. |
| Codemode execution, worker queue, `PI_CODEMODE_MAX_WORKERS` | `docs/acceptance/goal26-pi-140-alignment.md` section 方法. Repeated as "不在这次" on MCP, classify, truncation, and timing rows in the v1.3.0 and v1.4.0 books. | Reopen. GAP-05. The new goal is observable behavior. A user can enable the tool. |
| Files outside coding-agent, tui, and ai (437 paths on the v1.3.0 pin, decision "本钉不 port") | Same method section and `docs/acceptance/goal26-pi-130-alignment.md`. Counts in the TSV include agent, durable, chord, codemode, mcp, env. | Reopen the user-visible packages. GAP-01 through GAP-05, GAP-40 through GAP-43. `packages/agent` behavior is largely present. Evals stays excluded, row above. |
| MCP connect, OAuth, resource read, "仍不在这次" | v1.3.0 alignment rows for `mcp.json`, tool names, login URL, truncation. | Reopen. GAP-01 through GAP-04. |
| `models.classify()` from codemode | v1.4.0 classifier row, excluded in the same sentence that marked the rest done. | Reopen with GAP-05. The classifier APIs themselves are GAP-09 and GAP-10. |
| Sign in with ChatGPT and `agent_name_hint` | v1.3.0 row. "这棵树没有 Sign in with ChatGPT". | Reopen. GAP-08. The hint is part of that login. |
| Reasoning summary parameter | v1.3.0 row. The tree had no parameter, so a summary-only override could not change the effort. | Reopen. GAP-13. |
| Logo 3D egg, "仍不在这次" | v1.3.0 startup-logo row. | Reopen. GAP-39. |
| `cache_warming_decision` left out of the 41 hooks | Goal 26 done row on this tip. | Reopen. GAP-19. The done row is an exclusion, not evidence the hook is useless. |
| `tool_call` / `tool_result` kept split | Same done row. | Reopen the proof. GAP-20. If the aliases rewrite the call and the result the way pi's single hooks do, close the row with a test. If they do not, port the hook. |
| Telemetry spans "不要加 span" | Misc-scope proposal. Default pi behavior is a no-op, and the packages were out of scope. | Reopen the library API. GAP-43. Keep the no-op default and the install-ping exclusion. |
| New-server / remote-client 38 files | `docs/source-parity.md` evidence says pending. cadr-server kept the older session server. | Do not port. v1.4.0 has no `packages/server` and no `packages/client`. Do not delete `src/cadr-server/` in this program. Removing a cadr behavior needs an explicit user ruling. |
| G.17 kept `missing` in alignment files after the Part G matrix said `met` | Alignment method, repeated from Goal 24 through Goal 26, so a pin would not declare Goal 20 finished. | Reopen the status, not a feature. GAP-50. One measurement against the Part G evidence, then one status word. |

## 4. Parts

Thirteen parts. Every GAP row is in one of them. Order is dependency.

| Part | Gaps | Why this order |
|---|---|---|
| P1. Lock what already runs | GAP-20, GAP-29, GAP-44, GAP-45, GAP-46, GAP-47, GAP-48, GAP-49 | These rows are behavior that exists. Tests come before the ports so a later part cannot "fix" a green suite by moving the assertion. GAP-20 ends as either a locked alias or a hook change. GAP-29 needs a test that raises `SIGHUP`, not only the catch tag. |
| P2. Image catalog | GAP-17 | Regenerate `src/cadr-ai/image-models.generated.lisp` from the same pi-ai 1.4.0 tarball PR #874 used for chat. Later provider tests should see the current image ids. |
| P3. Provider auth | GAP-07, GAP-08, GAP-09, GAP-11, GAP-12, GAP-15, GAP-16 | Meta, ChatGPT sign-in, TypeSafe key, Anthropic federation, Azure env, callback host, and a `pi-ai`-equivalent list/login entry. Independent of MCP. |
| P4. Provider requests and classifiers | GAP-10, GAP-13, GAP-14 | `openai-decisions`, `llama-cpp-classify`, service tier, reasoning summary, verbosity, Mistral prompt mode, cache-retention env on every adapter that pi honors. Uses the auth from P3 when a live check is required. Fixture tests do not wait on credentials. |
| P5. MCP | GAP-01, GAP-02, GAP-03, GAP-04, the mcp factory in GAP-06 | Config, names, and truncation already exist. This part connects, reads resources, logs in, and exposes `cadr mcp`. |
| P6. Codemode | GAP-05, the codemode and tool-search factories in GAP-06 | The sandbox, the worker limit, the settings keys, and script calls including `models.classify`. Scripts that call MCP tools need P5. |
| P7. Session, hooks, settings, chrome | GAP-18, GAP-19, GAP-21, GAP-22, GAP-23, GAP-37, GAP-38, GAP-39 | JSONL export, warming hook, virtual-model extension registration, compaction overrides, retry caps, `--mode text` on a TTY, `/share` copy, 3D egg. Remove `daxnuts` only as part of matching the logo pi ships, in the same part, because the old egg is the behavior being replaced. |
| P8. Terminal, keys, shell env | GAP-24, GAP-25, GAP-26, GAP-27, GAP-28, GAP-30, GAP-31, GAP-32, GAP-33, GAP-34, GAP-35, GAP-36 | Windows and Unix edges, `#` completion, shell child environment, bug-report origin, write log, and the two `PI_` names renamed to `CADR_`. cadr already has `#+win32` branches, so Windows is a supported target. |
| P9. Chord | GAP-40 | Durable and pi-env depend on it. The `pi` binary does not. |
| P10. Telemetry contracts | GAP-43 | No-op default. pi-ai and durable call it when a host passes a span. No `pi.dev` ping. |
| P11. Durable | GAP-41 | Conversations, documents, tasks, storage, coding tools. Uses P9 and P10. |
| P12. pi-env | GAP-42 | Daemon and remote `ExecutionEnv` on top of durable's env interface. |
| P13. Ledger status | GAP-50 | Rewrite the G.17 word from the Part G evidence or a new measurement. Retire the pending-adjudication server rows and the v1.3.0 "open" file summary so the next diff queue does not treat deleted trees and finished files as work. |

P13 does not block P1. It should land before the next pin so the queue
starts from this inventory instead of from the old method paragraph.

## 5. Next stable tag

The diff queue used from Goal 21 through Goal 26 is the right tool for a
new tag, if the scope sentence changes.

Today the queue is `docs/acceptance/goalN-pi-*-alignment.md`. It diffs the
previous pin to the new tag, restricted to `packages/coding-agent`,
`packages/tui`, and `packages/ai`, and it refuses codemode, the worker
limit, and every other package. The coverage audit in
`docs/reviews/2026-10-23-goal26-coverage-audit.md` walks that same range
commit by commit and checks the changelog. It caught four holes inside
that scope. It cannot see GAP-07 or GAP-18, because those were already
true before the range, and it cannot see GAP-40, because the method
told it to ignore the commit.

For the next stable tag:

1. Pin with `scripts/set-baseline.sh` and `scripts/baseline-anchor.py`.
   Do not chase `main`.
2. Diff the previous tag to the new tag across all of `packages/`, not
   three directories. Keep the per-behavior queue and the FiveAM evidence
   rule.
3. Run the coverage audit on that diff with a scope sentence copied from
   the new goal. A row that cites an old N/A is covered only when section
   3 of this file still says exclude.
4. Repeat a surface inventory like this one when a package appears, or
   when someone wants to add an exclusion. A diff never reopens a cut
   that predates the range. That is how codemode and Meta survived a
   queue whose header says the queue is done.

`packages/evals` and the Node-only rows in section 3 stay out of step 2
without a new ruling. Everything else in the gap table is in scope the
day the tag moves.
