# Test matrix

Behavior baseline:
`earendil-works/pi@71efc6f0c1909874ec8c944637a9ae7fc0e2d508`.
The v1 matrix remains below; Phases 5–8 add the `docs/progress/goal-v2.md` coverage tables.

## Phase 1: cadr-ai

| TypeScript behavior source | Common Lisp coverage | Evidence |
|---|---|---|
| `tokens.test.ts`, `total-tokens.test.ts` | `USAGE-DEFAULTS-AND-TOTAL`, `COMPLETE-RESPONSE-FIXTURES-NORMALIZE-MESSAGES-AND-USAGE` | Three complete-response fixtures; provider-specific cache/reasoning totals |
| `stream.test.ts`, `text.test.ts` | `RECORDED-SSE-FIXTURES-NORMALIZE-EVENTS-AND-FINAL-MESSAGE` | Three real raw SSE recordings; ordered start/delta/end/done events |
| `anthropic-sse-parsing.test.ts` | `SSE-FRAMING-*`, recorded Anthropic replay | LF/CRLF, comments, multiline data, EOF, UTF-8 boundaries |
| `abort.test.ts` | `COMPLETE-CHAT-HONORS-IMMEDIATE-ABORT`, `STREAM-ABORT-PRESERVES-PARTIAL-CONTENT-AND-TERMINATES` | Immediate and mid-stream termination; partial content retained |
| `empty.test.ts` | request conversion paths plus `INCOMPLETE-AND-EMPTY-ASSISTANT-MESSAGES-ARE-NOT-REPLAYED` | Empty/incomplete assistant turns are not replayed |
| `tool-call-without-result.test.ts` | `ORPHANED-TOOL-CALLS-RECEIVE-SYNTHETIC-ERROR-RESULTS` | Synthetic error results for all three provider formats |
| `cross-provider-handoff.test.ts`, `google-thinking-signature.test.ts` | `FOREIGN-HISTORY-IS-MADE-SAFE-FOR-GEMINI-3.6` | Foreign thinking/signatures removed; IDs normalized and paired |
| Anthropic consecutive tool-result conversion | `CONSECUTIVE-ANTHROPIC-TOOL-RESULTS-SHARE-ONE-USER-TURN` | Consecutive results share one user turn |
| `openai-responses-terminal-event.test.ts` | `STREAM-ENDING-WITHOUT-PROVIDER-TERMINAL-EVENT-IS-AN-ERROR` | Missing terminal event becomes one final error |
| Provider request builders | `PROVIDER-REQUEST-PAYLOADS-MATCH-REFERENCE-FIXTURES` | Exact recursive JSON equality against exporter output |
| Provider auth/path behavior | `PROVIDER-REQUEST-PATHS-AND-AUTH-HEADERS`, `PROVIDERS-REJECT-MISSING-API-KEY` | Exact URLs and header forms; missing key rejected |
| True non-streaming protocol | `COMPLETE-CHAT-USES-REAL-NONSTREAM-REQUEST-PATH` | HTTP transport called with `want-stream = NIL` |
| API error normalization | `COMPLETE-CHAT-NORMALIZES-API-ERRORS` | Provider body message preserved in final assistant error |
| SSE long-thinking transport | `SSE-REQUEST-EXPLICITLY-DISABLES-READ-TIMEOUT` | Delayed stream plus captured explicit `read-timeout = NIL` |
| Real HTTP streaming transport | `NATIVE-HTTP-CONSUMES-A-REAL-STREAMING-HTTP-SOCKET` | Real loopback TCP server, native body stream, two separately flushed SSE events |
| Socket timeout classification | `SOCKET-TIMEOUTS-REMAIN-DISTINCT-RETRYABLE-TRANSPORT-ERRORS` | Native socket timeout remains a retryable `timeout-error` |
| Gemini 3.6 API contract | `GEMINI-3.6-OMITS-DEPRECATED-SAMPLING-PARAMETERS` | Default model ID and omission of deprecated sampling fields |

Bedrock, Vertex, WebSocket, and provider-specific compatibility quirks outside
the five-provider v2 registry remain outside the current phase.

## Phase 5: providers, images, catalog, and OAuth

| Requirement | Common Lisp coverage | Evidence |
|---|---|---|
| Five-provider registry | `BUILT-IN-PROVIDER-REGISTRY-IS-COMPLETE`, construction/missing-key tests | Protocol and provider are separate; Ollama is keyless |
| DeepSeek Chat Completions | `OPENAI-COMPLETIONS-*`, `RECORDED-DEEPSEEK-CHAT-COMPLETIONS-STREAM` | Tool history, non-stream parse, reasoning/tool deltas, usage |
| Current defaults | `REFRESHED-CATALOG-INCLUDES-GEMINI-3.6-AND-CURRENT-DEEPSEEK-DEFAULT` | Gemini 3.6 Flash and DeepSeek V4 Flash |
| Base URL/config precedence | `PROVIDER-CONFIG-RESOLVES-REGISTRY-CONFIG-AND-CLI-PRECEDENCE` | CLI → environment/config → registry |
| Images | `EACH-WIRE-PROTOCOL-ENCODES-IMAGE-CONTENT`, unsupported-image test | Four wire formats; text-only models fail explicitly |
| Pricing | `STATIC-MODEL-CATALOG-CALCULATES-COST` | Input/output/cache components and total |
| PKCE/reference URLs | RFC 7636 vector, OpenAI and Anthropic authorization URL tests | Pure Lisp SHA-256/base64url; fixed-reference parameters |
| OAuth persistence | auth round-trip, provider-error redaction, and logout tests | Atomic auth.json, mode 0600, OAuth tokens absent from transport/API/assistant errors |
| Refresh locking | `OAUTH-REFRESH-IS-DOUBLE-CHECKED-UNDER-LOCK` | Six concurrent callers perform one refresh |
| Refresh replay to request | `EXPIRED-OPENAI-TOKEN-REFRESHES-ONCE-THEN-BUILDS-REQUEST` | Expired → recorded token response → Codex request |
| Codex request contract | `OPENAI-OAUTH-USES-CODEX-URL-AND-REFERENCE-HEADERS` | URL, bearer, account, originator, beta headers |
| Slash auth commands | config-auth REPL and dispatch tests | `/login`, `/logout`, provider re-resolution |
| Live DeepSeek | `scripts/live-deepseek-smoke.sh` | Native executable streamed exact response |
| Live OpenAI OAuth | `scripts/live-openai-oauth-smoke.sh` | Real ChatGPT login; Codex Responses streaming passed |

## Phase 6: tree sessions, compaction, resume, and export

| Requirement | Common Lisp coverage | Evidence |
|---|---|---|
| JSONL v2 parent-linked tree | `SESSION-V2-BRANCHES-FROM-ANY-NODE-AND-PERSISTS-BOTH-PATHS` | Every node has id/parentId; two paths restore independently and accept new children |
| Lossless v1 migration | `SESSION-V1-LOAD-MIGRATES-ATOMICALLY-WITHOUT-LOSING-ENVELOPE-FIELDS` | Atomic v2 rewrite preserves message semantics and unknown header/envelope fields |
| Tree corruption rejection | duplicate-id/dangling-parent test plus existing crash-tail test | Duplicate, missing, and forward references fail; incomplete final write remains recoverable |
| Images in sessions | `SESSION-V2-ROUND-TRIPS-IMAGE-CONTENT` | MIME type and base64 data survive v2 persistence |
| Threshold compaction | `AUTOMATIC-COMPACTION-USES-CURRENT-MODEL-AND-CONTINUES-THE-PROMPT` | Current stream/model generates summary; original prompt continues against summary plus suffix |
| Provider overflow recovery | `CONTEXT-OVERFLOW-COMPACTS-ONCE-AND-RETRIES-WITHOUT-THE-ERROR-BRANCH` | Error is retained as a branch; active context compacts and retries exactly once |
| Traceable originals | automatic-compaction file assertions | JSONL retains original text plus the compaction summary and firstKeptEntryId |
| Session list and exact resume | `SESSION-LIST-RESUME-*`, CLI resolver tests | Sorted cwd list, exact ID, missing ID failure, continue/resume mutual exclusion |
| In-process switch and branch | `SESSION-COMMANDS-LIST-SWITCH-BRANCH-AND-EXPORT` | Agent session and context change together; next append uses selected parent |
| Safe full-tree HTML | `SESSION-LIST-RESUME-AND-HTML-EXPORT-COVER-THE-ENTIRE-TREE` | Both branches render; hostile markup is escaped and no template dependency is used |
| Native process resume | `scripts/acceptance-smoke.sh` | Separate native processes reuse one file through both `--continue` and exact `--resume` |

## Phase 7: Lisp extensions

| Requirement | Common Lisp coverage | Evidence |
|---|---|---|
| Frozen registration API | `EXTENSION-REGISTRATION-*` | Four macros reject invalid names, modes, schemas, events, templates, and calls outside loader context |
| Discovery and isolation | `EXTENSION-DISCOVERY-*`, `LATER-CLI-EXTENSION-*` | Unique generation packages; CLI/project/global priority; shadowed files never execute |
| Hook semantics | hook chain, real execution, transactional and turn persistence tests | Priority, rewrite, append, block, final schema validation, and pre-JSONL commit |
| Error containment | tool/command/template/hook/load error tests | Agent survives every extension boundary; visible errors redact configured secrets |
| Atomic reload | last-known-good and old-closure tests | One snapshot swap; failed generation keeps same-source LKG; old calls finish on old code |
| Commands/templates/skills | placeholder and command-priority tests | Built-ins beat extension commands; commands beat templates; fixed placeholder grammar |
| Git install | injected argv and real local Git daemon tests | No shell interpolation, no local/file URL, atomic staging rename, no overwrite |
| Self-extension | faux provider and `scripts/live-extension-smoke.sh` | Both deterministic and live DeepSeek complete write → reload → invoke |
| Original-pi execution model | `CORE-EXPOSES-NO-BUILT-IN-APPROVAL-OR-YOLO-SWITCH`, direct write test | No core confirmation export or `--yolo`; side-effect tools execute after validation |

## Wave 2: agent harness, session v3, print/JSON, and RPC

| Requirement | Common Lisp coverage | Evidence |
|---|---|---|
| Agent queues and settlement | queue/retry/loop suites | Steering and follow-up FIFO modes, next-turn retention, busy guard, abort cleanup, retry and ordered events |
| Harness resources and execution environment | resources/truncate/execution-env suites | Prompt templates, skills, system-prompt formatting, UTF-8 truncation, file abstraction, shell timeout/abort and process-group cleanup |
| Pluggable session storage | storage and SQLite suites | Memory/JSONL/SQLite CRUD, forks, active leaf, branches, materialized state, migration idempotence and rollback |
| Session v3 | `SESSION-V3-*`, v1/v2 migration and context tests | Delayed persistence, all reference entry types, bounded discovery, malformed-record recovery and unknown-field preservation |
| Expanded frozen extension API | legacy compatibility and Wave 2 extension suites | Existing macro/event behavior unchanged; approved lifecycle/UI/runtime additions validated and used by the real loop |
| Text/JSON modes | modes suite plus `scripts/test-wave2-process-modes.sh` | Mode priority, stdin merge, clean final text, JSONL events, error exits and SIGTERM cleanup |
| RPC mode | RPC suite plus process fixture | Full command union, response IDs, events, LF framing, prompt intervention, bash abort and extension UI response/timeout/EOF cleanup |
| Live one-shot print | `scripts/live-print-smoke.sh` | DeepSeek one-shot text mode exits 0 with exact clean output |

## Phase 8: pure Common Lisp TUI

| Requirement | Common Lisp coverage | Evidence |
|---|---|---|
| Grapheme/cell layout | Unicode, `wrap-ansi` and `truncate-to-width` suites | Combining marks, CJK, emoji, flags, ANSI/OSC 8 and tabs retain reference width/wrapping semantics |
| Input protocols and buffering | keys, keybindings, stdin-buffer and terminal-parity suites | Legacy/CSI-u/Kitty/native modifiers, fragments, paste, capability replies and Return dispatch |
| Editing and autocomplete | editor, input, fuzzy, word-navigation and autocomplete suites | History, sticky column, kill/yank/yank-pop, undo, path/slash/`@` completion and CJK word movement |
| Streaming Markdown and components | component parity tests plus TUI event projection | Streaming structures, links/tables/theme, select-list bounds, truncated text and image fallback |
| Overlay and terminal capability | overlay, terminal-color and terminal-image suites | Focus/capture, CJK-safe compositing, OSC reports, Kitty/iTerm2 encoding, sizing/deletion/fallback |
| Differential rendering | renderer/virtual-terminal tests | Only changed rows repaint; shrink clears stale rows; width change forces full redraw; image rows preclear |
| Exception-safe terminal | lifecycle body and partial-start tests | Cleanup runs after body conditions and after a start method fails mid-setup |
| Shared frontend semantics | `DISPATCH-USER-INPUT-IS-SHARED-BY-FRONTENDS`, TUI policy test | TUI/REPL share dispatch and agent events; `--no-tui` and non-TTY fallback are explicit |
| Native/live acceptance | `scripts/acceptance-smoke.sh`, `scripts/live-tui-smoke.sh`, `scripts/goal5-manual-tui.sh` | Pipe fallback; overlay focus/CJK/image fallback; autocomplete, undo, kill ring, DeepSeek two-turn edit, resize, image protocol and termios restoration |

## Phase 9: native infrastructure and dependency closure

| Requirement | Common Lisp coverage | Evidence |
|---|---|---|
| Native JSON | `NATIVE-JSON-*`, JSONTestSuite parsing corpus, and all provider/session fixtures | 95/95 required-valid and 188/188 required-invalid corpus files, exact large decimals, bounded nesting, finite output, complete wire round-trips |
| Native CLI | `NATIVE-CLI-PARSER-HANDLES-VALUES-FLAGS-AND-REPEATS` and help/build tests | Both value forms, repeated extensions, flags, missing/unknown rejection |
| Native schema | `NATIVE-SCHEMA-*` plus all tool/hook execution tests | Nested object/array pointers, scalar/composition constraints, malformed schema rejection, rewrite revalidation |
| Native HTTP | loopback streaming, chunked, timeout, status/retry tests | HTTP/1.1 framing and stream behavior no longer depend on Dexador |
| Long-thinking SSE | `SSE-REQUEST-EXPLICITLY-DISABLES-READ-TIMEOUT` | Native transport receives explicit `read-timeout = NIL` |
| Required removals | source audit in `docs/dependency-audit.md` | No production `dexador`, `com.inuoe.jzon`, or `clingon` reference |
| Full native image | `./build.sh`, `scripts/acceptance-smoke.sh` | 1219 checks and SBCL compression-feature fallback |
| Live DeepSeek paths | four live smoke scripts | Native HTTPS/SSE, self-extension, fail/fix/pass repository task, and real TUI multi-turn task |

## Phase 2: cadr-agent

| TypeScript behavior source | Common Lisp coverage | Evidence |
|---|---|---|
| `agent-loop.test.ts`: lifecycle | `SIMPLE-TURN-EMITS-REFERENCE-LIFECYCLE-ORDER` | Exact agent/turn/message start-update-end ordering |
| Tool call to result to next turn | `TOOL-CALL-RESULT-AND-NEXT-MODEL-TURN-COMPLETE` | Faux provider observes tool result in the next context |
| Unknown tool and argument validation | `UNKNOWN-INVALID-AND-LENGTH-TRUNCATED-TOOLS-BECOME-ERROR-RESULTS` | Structured error results; executor remains uncalled |
| Length-truncated tool call safety | same test | Every call fails closed and is re-presented to the model |
| Parallel completion and source ordering | `ALL-PARALLEL-TOOLS-FINISH-BY-COMPLETION-BUT-RESULTS-STAY-IN-SOURCE-ORDER` | End events complete fast-first; messages stay source ordered |
| Sequential batch override | `ONE-SEQUENTIAL-TOOL-FORCES-THE-WHOLE-BATCH-SEQUENTIAL` | One sequential tool serializes the entire batch |
| Provider error/abort | `ERROR-AND-ABORT-STOP-THE-RUN-CLEANLY` | One turn-end and one agent-end, without another model turn |

## Phase 3: tools and CLI

| Behavior source / requirement | Common Lisp coverage | Evidence |
|---|---|---|
| Read offset/limit/UTF-8/truncation | `READ-SUPPORTS-UTF8-OFFSET-LIMIT-AND-BOUNDED-HEAD-OUTPUT` | 1-based slicing, multibyte content, out-of-range error, 50 KiB bound |
| Write parent creation/overwrite | `WRITE-CREATES-PARENTS-AND-OVERWRITES-UTF8` | Nested parent creation and exact UTF-8 overwrite |
| Edit uniqueness/overlap/atomic result | `EDIT-REQUIRES-UNIQUE-NONOVERLAPPING-ORIGINAL-MATCHES` | Missing and duplicate old text rejected; original-coordinate replacements |
| Glob recursion/order/limit/ignore | `GLOB-IS-RECURSIVE-STABLE-LIMITED-AND-IGNORES-HEAVY-DIRECTORIES`, `GLOB-AND-GREP-FOLLOW-PARSEABLE-GITIGNORE-RULES` | Stable relative paths, `.git`/`node_modules`, nested `.gitignore`, negation |
| Grep regex/literal/context/filter/limit | `GREP-SUPPORTS-REGEX-LITERAL-CONTEXT-FILTER-AND-LIMIT`, `GREP-OUTPUT-IS-BOUNDED-BY-UTF8-BYTES-EVEN-WITH-CONTEXT`, gitignore test | Path/line output, context markers, case folding, glob filtering, 50 KiB total bound |
| Bash output/nonzero/bounds/timeout | `BASH-MERGES-OUTPUT-REPORTS-NONZERO-AND-TRUNCATES-TAIL`, `BASH-TIMEOUT-KILLS-THE-PROCESS-GROUP` | Merged stream, exact status, full-log retention, TERM-ignoring descendant killed with its independent group |
| Execution policy | `CORE-EXPOSES-NO-BUILT-IN-APPROVAL-OR-YOLO-SWITCH`, `SIDE-EFFECT-TOOLS-EXECUTE-DIRECTLY-BY-DEFAULT` | Original-pi default YOLO behavior; optional approval lives in an extension hook |
| REPL multi-turn | `REPL-CONSUMES-MULTIPLE-LINES-AND-STREAMS-TEXT` | Empty input ignored; multiple prompts and response rendering |
| Real tool loop from REPL | `REPL-RUNS-A-FAUX-PROVIDER-THROUGH-REAL-READ-EDIT-AND-BASH-TOOLS` | Faux model drives actual read → edit → bash → final response |
| Exact terminal deltas/errors | `EVENT-RENDERER-STREAMS-EACH-DELTA-AND-REPORTS-TERMINAL-ERRORS-ONCE` | Every delta rendered once; terminal error printed once |

## Phase 4: persistence, retry, build, and acceptance

| Requirement | Common Lisp coverage | Evidence |
|---|---|---|
| JSONL message round-trip and secret exclusion | `SESSION-JSONL-ROUND-TRIPS-ALL-FIRST-VERSION-MESSAGE-TYPES` | User/assistant/tool-result data survives; no API key field |
| Crash-tail recovery and corruption detection | `SESSION-LOADER-IGNORES-ONLY-AN-INCOMPLETE-FINAL-LINE` | Unterminated final record ignored; malformed middle record signals `session-error` |
| Cwd-scoped continuation | `CONTINUE-SESSION-SELECTS-LATEST-CANONICAL-MATCHING-CWD` | Latest valid canonical-cwd match selected |
| Invalid continuation headers | `CONTINUE-SESSION-REJECTS-INVALID-SESSION-HEADERS` | Corrupt session metadata fails explicitly instead of silently starting over |
| Immediate agent persistence | `AGENT-FLUSHES-FINAL-USER-AND-ASSISTANT-MESSAGES-TO-SESSION` | Reload sees both finalized messages |
| Retry policy | `RETRYABLE-COMPLETE-REQUESTS-RESPECT-CAP-AND-RETRY-AFTER`, `NONRETRYABLE-COMPLETE-REQUEST-IS-NOT-RETRIED` | Two-retry cap, 0.25/0.5 backoff, numeric Retry-After, 400 fail-fast |
| HTTP status preservation | `NATIVE-HTTP-STATUSES-RETAIN-API-BODY-AND-RETRY-POLICY` | Native status/body/hash headers map to `api-error` |
| Safe SSE retry | `STREAM-RETRIES-BEFORE-PROVIDER-EVENTS-WITHOUT-DUPLICATING-START` | Pre-event reconnect only; exactly one unified start |
| Compression feature fallback | `NATIVE-IMAGE-OPTIONS-OMIT-UNSUPPORTED-COMPRESSION-KEYWORD` | Unsupported builds omit the keyword entirely; supported builds use compression |
| Repository repair acceptance | `FAUX-REPO-TASK-OBSERVES-FAILING-TEST-FIXES-AND-PASSES` | Read → wrong edit → failed test → corrected edit → passing test |
| Native executable continuation | `scripts/acceptance-smoke.sh` | Saved image help plus two-process `--continue`, one session file |
| Live Anthropic multi-turn streaming | `scripts/live-anthropic-smoke.sh` | Credential-gated two-turn context assertion; fails before network when the key is absent |
| Live repository repair | `scripts/live-repo-smoke.sh` | DeepSeek credential plus script-level opt-in; isolated repo must record test failure, edit, and passing rerun |

## cadr migration

| Requirement | Common Lisp coverage | Evidence |
|---|---|---|
| ASDF/package namespace | `CADR-SYSTEM-AND-PACKAGE-NAMES-ARE-THE-ONLY-PUBLIC-NAMES` | Four production/test systems load under cadr names; old systems/packages are absent |
| Frozen extension namespace | `CADR-EXTENSION-API-IS-EXPORTED-FROM-THE-FROZEN-AGENT-PACKAGE` | Four stable registration macros are external symbols of `CADR-AGENT` |
| Exported symbol rename | `EXPORTED-ERROR-ROOT-USES-THE-CADR-NAME` | Root condition is `CADR-AI:CADR-ERROR`; no old exported root remains |
| Reference payload helper | `REFERENCE-PAYLOAD-RUNNER-KEEPS-TYPESCRIPT-API-TYPE-NAMES` | Namespace replacement cannot corrupt the pinned TypeScript runner's `Api` / `TApi` identifiers |
| Complete data move | `INTERACTIVE-USER-DATA-MIGRATION-MOVES-THE-COMPLETE-TREE` | Sessions, extensions, and auth move together; source disappears; auth becomes 0600 |
| Session continuation | same unit test plus `scripts/migration-smoke.sh` | `--continue` resumes the migrated session without creating a second file |
| Fail-closed migration | noninteractive, decline, and yolo migration tests | No automatic move without explicit interactive consent; manual command is emitted |
| Environment transition | legacy/new environment tests | Old values warn through 0.1.x; new values win silently; removal is fixed at 0.2.0 |
| Native executable identity | `./build.sh`, `./cadr --version` | Output filename and version banner use cadr |
| Git history | ancestry check in `docs/progress/migration.md` | Pre-migration baseline `c07b5a668` remains reachable |
