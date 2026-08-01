# Test matrix

Behavior baseline:
`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.
The former `71efc6f0c1909874ec8c944637a9ae7fc0e2d508` baseline is historical only.
The v1 matrix remains below as historical evidence; later tables supersede its
intermediate provider, session, extension, and test-count claims.
Provider live checks are credential-gated FiveAM blocks run by the dedicated
`scripts/test-live.sh`; deterministic suites run through `scripts/test-cl.sh`.
The live runner lists every pass, skip reason, and classified failure before
returning nonzero. Shell harnesses are retained only for native
process/PTY/socket/migration boundaries; the complete script audit and exact claim limits are in
[`goal-v8-smoke-audit.md`](acceptance/goal-v8-smoke-audit.md).

## Goal 9 Part A: current baseline delta

| Baseline behavior | Common Lisp coverage | Evidence |
|---|---|---|
| Bedrock structured error metadata | `test/cadr-ai/bedrock-error-metadata-test.lisp`, `BEDROCK-FAILURE-RECORDS-BOUNDED-STRUCTURED-METADATA` | HTTP and in-stream failures preserve bounded provider diagnostics without changing abort semantics |
| Current model metadata and pricing | `GPT-5-6-AUTHORITATIVE-PRICING-AND-OPENCODE-GO-NAME` | Updated pricing/metadata and provider naming are checked against the audit baseline |
| Permanent harness shutdown/task tracking | `SHUTDOWN-*`, `WAIT-FOR-IDLE-IGNORES-MUTATIONS-BUT-SHUTDOWN-AWAITS-THEM` | Shutdown is permanent/idempotent, awaits active work and rejects later prompt/append/compact/tree mutation |
| Markdown extension API and width contract | `DISCOVERED-EXTENSION-SOURCE-REGISTERS-MARKDOWN-TRANSFORMER`, `GOAL9-TUI-MARKDOWN-TRANSFORMERS-COVER-USER-TEXT-THINKING-STREAMING-AND-CACHE`, `GOAL9-MARKDOWN-TRANSFORM-RECEIVES-EXACT-AVAILABLE-WIDTH` | Transformer chain receives message type and available width; errors are isolated; rendering cache semantics remain stable |
| Malformed package manifest | `GOAL9-MALFORMED-PACKAGE-MANIFEST-IGNORES-INVALID-FIELDS-WITHOUT-DROPPING-VALID-FIELDS` | Invalid fields are ignored independently while valid package metadata survives discovery |
| Alternate-screen TUI | `test/cadr-tui/alt-screen-test.lisp`, `test/cadr-cli/tui-test.lisp` | Viewport/scroll, configurable input, OSC 8/52, Kitty/iTerm image behavior, grapheme selection and terminal restoration |
| Terminal grapheme widths | `TERMINAL-CELL-WIDTH-*`, grapheme-safe truncation/editor suites | CJK, emoji, combining and regional-indicator clusters retain terminal-cell semantics |
| Remote-session protocol v2 | `test/cadr-protocol/cbor-test.lisp`, `framing-test.lisp`, `protocol-test.lisp` | Strict CBOR, bounded four-byte framing and validated client/server codecs; 41 tests / 497 checks |
| Comparative eval infrastructure | `test/cadr-evals/pi-harness-test.lisp`, `artifacts-test.lisp`, `harness-table-test.lisp`, `summary-test.lisp` | Explicit selection, isolated artifacts, iteration/group metadata, correctness/efficiency summaries and diagnostics |
| Deterministic workflows | `goal9-a2-workflows-test.lisp`, `goal9-a2-interactive-test.lisp`, `goal9-a2-process-faux-test.lisp` plus `scripts/goal9-a2-pty.sh` | Session/extension/rendering semantics; independent SBCL process × actual faux text/JSON/RPC; real-PTY editor/completion/overlay snapshots and terminal restoration |

The current TypeScript manifest is `362 C / 0 U / 0 M / 1 N/A = 363`.
`packages/coding-agent/test/config.test.ts` remains the sole approved `N/A`.

## Goal 9 Part E: release preparation and repository hygiene

| Contract | Common Lisp coverage | Evidence |
|---|---|---|
| One production version source | `GOAL9-PART-E-PRODUCTION-VERSION-HAS-ONE-SOURCE`, `GOAL9-PART-E-VERSION-REACHES-SERVER-CLI-AND-RADIUS-REGISTRATION` | All eight ASDF systems, both CLIs, TUI, HTTP and Radius derive from `version.sexp`; production literal audit rejects drift |
| Repository/document hygiene | `GOAL9-PART-E-REPOSITORY-HYGIENE-AND-NAVIGATION-CONTRACT` | Root changelog, docs index, ignored local state, archived goal inputs and removed empty `packages/` tree are checked together |
| Release-local verification | `scripts/verify.sh` plus root `build.sh`/`build-server.sh` | 7128 deterministic checks pass in the root test and both isolated builds; Goal 11 budgets, retained harnesses, and all available live paths pass |

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

This Phase 1 table is historical. Bedrock, Vertex and the provider-specific
compatibility matrix were subsequently closed by Wave 3 and the Goal 9 delta;
they are not current gaps.

## Phase 5: providers, images, catalog, and OAuth

| Requirement | Common Lisp coverage | Evidence |
|---|---|---|
| Historical five-provider registry step | `BUILT-IN-PROVIDER-REGISTRY-IS-COMPLETE`, construction/missing-key tests | Superseded by the exact 38-provider registry; the non-baseline built-in Ollama entry was removed |
| DeepSeek Chat Completions | `OPENAI-COMPLETIONS-*`, `RECORDED-DEEPSEEK-CHAT-COMPLETIONS-STREAM` | Tool history, non-stream parse, reasoning/tool deltas, usage |
| Current defaults | `REFRESHED-CATALOG-INCLUDES-GEMINI-3.6-AND-CURRENT-DEEPSEEK-DEFAULT` | Gemini 3.6 Flash and DeepSeek V4 Flash |
| Base URL/config precedence | `PROVIDER-CONFIG-RESOLVES-REGISTRY-CONFIG-AND-CLI-PRECEDENCE` | CLI → environment/config → registry |
| Images | `EACH-WIRE-PROTOCOL-ENCODES-IMAGE-CONTENT`, unsupported-image test | Four wire formats; text-only models fail explicitly |
| Pricing | `STATIC-MODEL-CATALOG-CALCULATES-COST` | Input/output/cache components and total |
| PKCE/reference URLs | RFC 7636 vector, OpenAI and Anthropic authorization URL tests | Pure Lisp SHA-256/base64url; fixed-reference parameters |
| OAuth persistence | auth round-trip, provider-error redaction, and logout tests | Atomic auth.json, mode 0600, OAuth tokens absent from transport/API/assistant errors |
| Refresh locking | `OAUTH-REFRESH-IS-DOUBLE-CHECKED-UNDER-LOCK` | Six concurrent callers perform one refresh |
| Refresh replay to request | `EXPIRED-OPENAI-TOKEN-REFRESHES-ONCE-THEN-BUILDS-REQUEST` | Expired → recorded token response → Codex request |
| Codex request contract | `OPENAI-OAUTH-USES-CODEX-URL-AND-APPROVED-CADR-ORIGINATOR-HEADER` | URL, bearer, account, approved `originator=cadr` identity difference, beta headers |
| Slash auth commands | config-auth REPL and dispatch tests | `/login`, `/logout`, provider re-resolution |
| Live DeepSeek | `scripts/test-live.sh` → `test/cadr-ai/live-provider-test.lisp` | Credential-gated exact response, terminal events and positive usage |
| OpenAI OAuth login/default route | `LOGIN-OPENAI-TEMP-STORE-DEFAULT-RESOLVER-ROUTES-CODEX-REQUEST` | Temporary auth/config plus login and HTTP stubs prove `openai-codex` storage, default resolution, `originator=cadr`, and Codex transport without homedir state |
| Live OpenAI OAuth | `scripts/test-live.sh` → `test/cadr-cli/live-test.lisp` | Credential-gated, explicit `openai-codex/gpt-5.5` in an isolated HOME; canonical credential sharing plus isolated injection, no user settings/session/extensions |

## Phase 6: tree sessions, compaction, resume, and export

This table records the historical v2 milestone. The current session format is
v3 and atomically migrates v1/v2 data, as covered in the Wave 2 table below.

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
| Frozen extension API | legacy compatibility plus Wave 2 extension suites | The expanded, re-frozen lifecycle/UI/runtime API preserves existing macro signatures and event semantics |
| Discovery and isolation | `EXTENSION-DISCOVERY-*`, `LATER-CLI-EXTENSION-*` | Unique generation packages; CLI/project/global priority; shadowed files never execute |
| Hook semantics | hook chain, real execution, transactional and turn persistence tests | Priority, rewrite, append, block, final schema validation, and pre-JSONL commit |
| Error containment | tool/command/template/hook/load error tests | Agent survives every extension boundary; visible errors redact configured secrets |
| Atomic reload | last-known-good and old-closure tests | One snapshot swap; failed generation keeps same-source LKG; old calls finish on old code |
| Commands/templates/skills | placeholder and command-priority tests | Built-ins beat extension commands; commands beat templates; fixed placeholder grammar |
| Git install | injected argv and real local Git daemon tests | No shell interpolation, no local/file URL, atomic staging rename, no overwrite |
| Self-extension | faux provider plus `test/cadr-evals/live-evals-test.lisp` | Both deterministic and credential-gated DeepSeek complete write → reload → invoke with explicit tool-surface assertions |
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
| Live one-shot print | `scripts/test-live.sh` → `test/cadr-cli/live-test.lisp` | Credential-gated DeepSeek CLI handler exits 0 with exact stdout and empty stderr |

## Goal 8 Wave 5: storage, server, and evals

| Requirement | Common Lisp coverage | Evidence |
|---|---|---|
| Standalone SQLite package | `CADR-STORAGE-SUITE` | 23 checks cover exports, adapter/named parameters, migrations, transactions, create/open/list/delete/fork and materialized state |
| Server protocol and persistence | `PROTOCOL-AND-STORAGE-PRESERVE-BASELINE-RECORDS`, supervisor suite | JSONL framing, machine/instance records, session metadata, lifecycle convergence and restart recovery |
| Unix-socket RPC supervisor | socket suite plus `scripts/server-smoke.sh` | Stale socket replacement, spawn/list/status/RPC/stop, stream events and extension UI bridge against a real `cadr --mode rpc` child |
| Radius presence | heartbeat retry suite | Credential gating, exponential transient backoff, three-404 re-registration threshold and dormant no-credential behavior |
| Eval harness | `CADR-EVALS-SUITE` | Goal 8 harness plus Goal 9 artifact/table/summary expansion; explicit provider/model, isolated cleanup and normalized transcript/usage |
| Self-extension eval | `SELF-EXTENSION-EVAL-WRITES-RELOADS-AND-INVOKES-HELLO-TOOL` | Isolated extension write, reload, registration and invocation |
| Live evals | `scripts/test-live.sh` → `test/cadr-evals/live-evals-test.lisp` | DeepSeek key and real Codex OAuth credential run explicit provider/model Paris/usage checks through isolated resolvers and the public harness |
| Native server image | `build-server.sh`, `cadr-server --version` | SBCL compression-feature fallback and separate native executable |
| Single local release gate | `scripts/verify.sh`, `GOAL9-PART-D-VERIFY-ENTRYPOINT-HAS-APPROVED-STAGE-CONTRACT` | Deterministic FiveAM → isolated dual build → retained process/PTY harnesses → availability-gated live FiveAM → DeepSeek live TUI; separate deterministic/live summaries, no remote CI |

## Goal 11: non-functional parity

| Contract | Common Lisp coverage | Evidence |
|---|---|---|
| Deterministic latency/allocation benchmark | `scripts/bench.sh`, `scripts/goal11-bench.lisp`, `scripts/goal11-cold-start.py` | Fixed mixed transcripts measure frame, key-to-frame, stream-to-frame, append, heap/RSS and real-PTY cold start with raw samples and provenance |
| Long-session stability | `scripts/goal11-stability.sh`, `scripts/goal11-stability.lisp` | 1200 faux turns, 14,400 rendered frames, five resource checkpoints, full-GC pauses, cleanup, and 10MiB session load/resume/continue |
| Release budget gate | `scripts/goal11-performance-gate.py`, `GOAL9-PART-D-VERIFY-ENTRYPOINT-HAS-APPROVED-STAGE-CONTRACT` | `scripts/verify.sh` regenerates both reports in its isolated tree and fails before process/live stages when any approved budget is exceeded |

## Phase 8: pure Common Lisp TUI

| Requirement | Common Lisp coverage | Evidence |
|---|---|---|
| Grapheme/cell layout | Unicode, `wrap-ansi` and `truncate-to-width` suites | Combining marks, CJK, emoji, flags, Indic/Myanmar spacing marks, ANSI/OSC 8 and tabs retain reference width/wrapping semantics |
| Input protocols and buffering | keys, keybindings, stdin-buffer and terminal-parity suites | Legacy/CSI-u/Kitty/native modifiers, fragments, paste, capability replies and Return dispatch |
| Editing and autocomplete | editor, input, fuzzy, word-navigation and autocomplete suites | History, sticky column, kill/yank/yank-pop, undo, path/slash/`@` completion and CJK word movement |
| Streaming Markdown and components | component parity tests plus TUI event projection | Streaming structures, links/tables/theme, select-list bounds, truncated text and image fallback |
| Overlay and terminal capability | overlay, terminal-color and terminal-image suites | Focus/capture, CJK-safe compositing, OSC reports, Kitty/iTerm2 encoding, sizing/deletion/fallback |
| Differential and alternate-screen rendering | renderer/virtual-terminal and alt-screen tests | Changed-row repaint, stale-row clearing, viewport/scroll, mouse/link/selection, image cleanup/cropping and full terminal restoration |
| Exception-safe terminal | lifecycle body and partial-start tests | Cleanup runs after body conditions and after a start method fails mid-setup |
| Shared frontend semantics | `DISPATCH-USER-INPUT-IS-SHARED-BY-FRONTENDS`, TUI policy test | TUI/REPL share dispatch and agent events; `--no-tui` and non-TTY fallback are explicit |
| Native/live acceptance | `scripts/acceptance-smoke.sh`, `scripts/live-tui-smoke.sh`, `scripts/goal5-manual-tui-smoke.sh` | Pipe fallback; overlay focus/CJK/image fallback; autocomplete, undo, kill ring, DeepSeek two-turn edit, resize, image protocol and termios restoration |

## Phase 9: native infrastructure and dependency closure

| Requirement | Common Lisp coverage | Evidence |
|---|---|---|
| Native JSON | `NATIVE-JSON-*`, JSONTestSuite parsing corpus, and all provider/session fixtures | 95/95 required-valid and 188/188 required-invalid corpus files, exact large decimals, bounded nesting, finite output, complete wire round-trips |
| Native CLI | `NATIVE-CLI-PARSER-HANDLES-VALUES-FLAGS-AND-REPEATS` and help/build tests | Both value forms, repeated extensions, flags, missing/unknown rejection |
| Native schema | `NATIVE-SCHEMA-*` plus all tool/hook execution tests | Nested object/array pointers, scalar/composition constraints, malformed schema rejection, rewrite revalidation |
| Native HTTP | loopback streaming, chunked, timeout, status/retry tests | HTTP/1.1 framing and stream behavior no longer depend on Dexador |
| Long-thinking SSE | `SSE-REQUEST-EXPLICITLY-DISABLES-READ-TIMEOUT` | Native transport receives explicit `read-timeout = NIL` |
| Required removals | source audit in `docs/dependency-audit.md` | No production `dexador`, `com.inuoe.jzon`, or `clingon` reference |
| Full native image | `./build.sh`, `scripts/acceptance-smoke.sh` | Historical Phase 9 gate: 1219 checks and SBCL compression-feature fallback; current totals live in the active goal report |
| Live DeepSeek paths | credential-gated FiveAM blocks plus `scripts/live-tui-smoke.sh` | HTTPS/SSE, self-extension, fail/fix/pass repository task, and real PTY TUI multi-turn task |

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
| Live Anthropic multi-turn streaming | `test/cadr-ai/live-provider-test.lisp` | Credential-gated exact two-turn context; absent key skips like the baseline |
| Live repository repair | `test/cadr-evals/live-evals-test.lisp` | DeepSeek credential gate only; isolated repo must record test failure, edit, and passing rerun |

## cadr migration

| Requirement | Common Lisp coverage | Evidence |
|---|---|---|
| ASDF/package namespace | `CADR-SYSTEM-AND-PACKAGE-NAMES-ARE-THE-ONLY-PUBLIC-NAMES` | Four production/test systems load under cadr names; old systems/packages are absent |
| Frozen extension namespace | legacy compatibility and expanded export-freeze tests | The expanded stable extension API is exported from `CADR-AGENT`; the former four-macro statement was an earlier freeze snapshot |
| Exported symbol rename | `EXPORTED-ERROR-ROOT-USES-THE-CADR-NAME` | Root condition is `CADR-AI:CADR-ERROR`; no old exported root remains |
| Reference payload helper | `REFERENCE-PAYLOAD-RUNNER-KEEPS-TYPESCRIPT-API-TYPE-NAMES` | Namespace replacement cannot corrupt the pinned TypeScript runner's `Api` / `TApi` identifiers |
| Complete data move | `INTERACTIVE-USER-DATA-MIGRATION-MOVES-THE-COMPLETE-TREE` | Sessions, extensions, and auth move together; source disappears; auth becomes 0600 |
| Session continuation | same unit test plus `scripts/migration-smoke.sh` | `--continue` resumes the migrated session without creating a second file |
| Fail-closed migration | noninteractive, decline, and yolo migration tests | No automatic move without explicit interactive consent; manual command is emitted |
| Environment transition | legacy/new environment tests | Old values warn through 0.1.x; new values win silently; removal is fixed at 0.2.0 |
| Native executable identity | `./build.sh`, `./cadr --version` | Output filename and version banner use cadr |
| Git history | ancestry check in `docs/progress/migration.md` | Pre-migration baseline `c07b5a668` remains reachable |
