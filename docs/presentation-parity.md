# Presentation parity ledger

<!-- GOAL13_PRESENTATION_LEDGER baseline=53fa77ccd8a279eb87e92294ef3687b03ff80112 b1=55 b2=52 b3=10 b4=6 total=123 aligned=119 pending=0 intentional=4 -->
<!-- GOAL13_OUTPUT_CHANNELS total=18 covered=18 pending=0 -->

Fixed baseline: `earendil-works/pi@53fa77ccd8a279eb87e92294ef3687b03ff80112`.
Audit point: Cadr `e04d9230f` (Goal 13 Part A complete).  This ledger audits
the independent **presentation axis** only. Tool results sent to the model,
provider payloads, event sequences, and session data belong to the behavior
ledger in `docs/parity-map.md`; per-file capability disposition belongs to
`docs/source-parity.md`; performance, allocation, memory, and stability belong
to `docs/performance.md`. `examples/manifest.sexp` is only an auxiliary
runnable-example inventory.

The `GOAL13_PRESENTATION_LEDGER` comment is the machine-readable completeness
identity. Its B1-B4 denominators must equal `55 + 52 + 10 + 6 = 123`, and its
dispositions must equal `119 aligned + 0 pending + 4 intentional = 123`.

Status meanings:

- `一致`: the fixed baseline and Cadr assign the same copy, style, geometry,
  formatting rule, and truncation behavior.
- `不一致`: an implementation difference found by this audit; Part C owns it.
- `有意差异`: a user-approved difference which must remain documented.

## Output-channel completeness gate

The old audit enumerated visible elements. That set is open-ended and missed
copy written after alternate-screen teardown. The finite audit boundary is now
every channel by which Cadr can affect an external observer. A gate is accepted
only when it drives the real channel; a renderer snapshot cannot stand in for
stdout, a fixture cannot stand in for a persisted file, and a payload builder
cannot stand in for a process exit status.

| ID | Observable channel | Fixed baseline output (`file:line`) | Cadr output | Gate | Coverage |
|---|---|---|---|---|---|
| C-01 | TUI screen while alternate screen is active | terminal composition and lifecycle (`interactive-mode.ts:785,3785-3791,6107-6121`) | `run-tui` composes the complete document through the terminal renderer (`src/cadr-cli/interactive/controller.lisp:204-2466`) | 13 base-screen and 15 overlay snapshots with independent baseline assertions; fixed-baseline PTY render differential: 61 scenarios/120 captures in `verify.sh`, 72/142 in the mandatory pre-tag and post-upstream full gate; the latter proves all 476 printable sites/776 printable branch obligations are captured or explicitly exempted. 61/120 and 72/142 are recounted mechanically from test/fixtures/render-diff/scenarios.json with the commands below the table (core = default tier; most scenarios use both dimensions; scenarios with a declared `dimensions` list count only those; `example-space-invaders` is wide-only because the baseline 60-column board exceeds the 48-column fixture) | 已覆盖 |
| C-02 | stdout/stderr before TUI startup or without TUI takeover | help/version/list/config errors and one-shot command output (`main.ts:541-648`; `cli/args.ts:239-331`) | CLI metadata, migration diagnostics and configuration failures use the process streams before `run-tui` (`src/cadr-cli/main.lisp:2428-2775`) | `GOAL9-A2-PROCESS-FAUX-*`; `test-wave2-process-modes.sh`; acceptance smoke | 已覆盖 |
| C-03 | stdout after TUI teardown | clean interactive exit prints dim `To resume this session:` plus the exact command; signal/emergency exits do not (`interactive-mode.ts:236-249,3622-3634`) | clean normal, Ctrl+C and suspend/resume returns print `cadr --session ...` after terminal stop; custom directories add `--session-dir`; SIGTERM/SIGHUP non-local exits bypass it (`src/cadr-cli/main.lisp:3945-4331`; `src/cadr-cli/utilities.lisp:445-477`) | `GOAL13-SESSION-IDS-AND-POST-TUI-RESUME-COPY-MATCH-THE-BASELINE`; real-PTY normal/Ctrl+C/suspend-resume ordering; signal process harness | 已覆盖 |
| C-04 | `--print` stdout/stderr | final assistant text to raw stdout and request failures to stderr (`print-mode.ts:32-151`) | print consumer emits final text only; normalized errors use stderr (`src/cadr-cli/main.lisp:49-113,4338-4376`) | `GOAL9-A2-PROCESS-FAUX-PRINT-*`; process-mode harness | 已覆盖 |
| C-05 | `--mode json` JSONL stdout | header plus complete agent events as one JSON object per line (`print-mode.ts:101-119`) | `agent-event-to-json`, `write-json-line`, and `run-print-mode` own the JSON projection and one-record-per-line framing (`src/cadr-cli/modes/print.lisp:200-496,505-584`) | fixed-baseline Pi/Cadr faux-provider event differential in JSON mode; `GOAL9-A2-PROCESS-FAUX-JSON-*` | 已覆盖 |
| C-06 | `--mode rpc` stdin/stdout JSONL | RPC request/response/event loop (`modes/rpc/rpc-mode.ts:53-184`; `modes/rpc/jsonl.ts:1-14`) | `run-rpc-mode` projects the same production events through the serialized RPC sink (`src/cadr-cli/modes/rpc/mode.lisp:3-96`; `src/cadr-cli/modes/rpc/jsonl.lisp:3-65`) | fixed-baseline Pi/Cadr faux-provider event differential in RPC mode; process-mode framing harness | 已覆盖 |
| C-07 | session JSONL on disk | header and every appended/re-written entry (`session-manager.ts:979-1040,1620-1625`) | v3 header/entry envelopes and atomic migration writes (`src/cadr-agent/session.lisp:566-852,1427-1442`) | session v1/v2/v3 whole-tree round trips and migration smoke | 已覆盖 |
| C-08 | exported session files | self-contained HTML with Base64 session data; default name derives from app/session-file basename and the interactive notice reports the returned relative filename (`core/export-html/index.ts:130-174,274-314`; `interactive-mode.ts:5471-5481`) | offline HTML preserves the exact session tree; default `cadr-session-<ISO>_<uuid>.html`; the notice reports only that filename (`src/cadr-agent/session.lisp:2347-2555`; `src/cadr-cli/main.lisp:1331-1345,1546-1560`) | export asset/tree/theme tests and `GOAL13-DEFAULT-HTML-EXPORT-NAME-AND-STATUS-MATCH-THE-BASELINE-RULE` | 已覆盖 |
| C-09 | `auth.json` | locked JSON credential store, mode 0600 and atomic replacement (`core/auth-storage.ts:46-149,188-334`) | provider-identity-preserving atomic 0600 store with refresh lock and redaction (`src/cadr-ai/auth.lisp:84-205`) | auth round-trip/permissions/refresh-race tests; deterministic login route; live credential integrity checks | 已覆盖 |
| C-10 | settings, trust and installed-package state on disk | global/project settings plus trust/package metadata (`settings-manager.ts:200-252,610-630`; `trust-manager.ts:112-137`; `package-manager.ts:1920-1945`) | atomic global/project settings carry model, keybindings, trust and package entries (`src/cadr-cli/settings.lisp:180-469`; `src/cadr-cli/package-manager.lisp:586-665`) | settings reload/concurrency/keybinding/package-manager suites | 已覆盖 |
| C-11 | SQLite session/server persistence | SQLite session store opens, creates, appends and forks repository records (`packages/storage/sqlite-node/src/sqlite/session-store.ts:66-271`) | standalone storage adapter and server repository persist schema-versioned rows (`src/cadr-agent/sqlite-storage.lisp:1-901`; `src/cadr-server/storage.lisp:1-120`) | `CADR-STORAGE-SUITE`; server protocol-and-storage round trip | 已覆盖 |
| C-12 | outbound provider HTTP/WebSocket requests | provider-specific URL, headers, body and streaming transport (`packages/ai/src/api/openai-responses.ts:1-184`; `packages/ai/src/api/openai-responses-shared.ts:419-733`) | request specs feed the HTTP/SSE/WebSocket implementations without presentation rewriting (`src/cadr-ai/providers/openai.lisp:1-1130`; `src/cadr-ai/http.lisp:1-806`; `src/cadr-ai/websocket.lisp:1-586`) | complete payload fixtures, delta-boundary properties and credential-gated provider matrix | 已覆盖 |
| C-13 | OAuth loopback HTTP response | byte-framed success/failure HTML callback page (`auth/oauth/openai-codex.ts:336-365`; `auth/oauth/oauth-page.ts:1-108`) | byte-accurate HTML with a Cadr-owned grid cons-cell mark and provider-specific escaped copy (`src/cadr-ai/oauth/page.lisp:1-149`; `src/cadr-ai/oauth/callback.lisp:78-237`) | OAuth HTML/framing/parser tests plus real `/login openai` | 已覆盖 |
| C-14 | Cadr server Unix-socket responses | validated framed messages and Unix listener writes (`packages/protocol/src/codec.ts:50-158`; `packages/server/src/transports/unix/listener.ts:71-235`) | local socket supervisor returns frozen JSON protocol envelopes (`src/cadr-server/protocol.lisp:1-65`; `src/cadr-server/ipc.lisp:139-225`) | protocol suite and real multiprocess `server-smoke.sh` | 已覆盖 |
| C-15 | process exit status | print errors, signals, package commands and fatal paths set explicit status (`print-mode.ts:34-150`; `main.ts:541-648,901-913`) | `main` returns deterministic mode status; signals map to 129/143 and build support passes it to `uiop:quit` (`src/cadr-cli/main.lisp:1562-1581,3944-4383`; `src/cadr-cli/build-support.lisp:1-13`) | process faux tests, signal PTY lifecycle and `test-wave2-process-modes.sh` | 已覆盖 |
| C-16 | server control-process stdout/stderr | server CLI prints help/version, JSON responses, stream frames and listener state (`packages/server/src/cli.ts:13-94`; `packages/server/src/serve.ts:16-38`) | `cadr-server` prints the corresponding control responses and listener lifecycle outside its socket channel (`src/cadr-server/main.lisp:1-155`) | server suite plus real multiprocess `server-smoke.sh` | 已覆盖 |
| C-17 | eval runner stdout/stderr and report artifacts | vitest-evals writes schema-versioned `runs.jsonl` and summaries (`packages/evals/src/vitest-evals/reporter.ts:24-61`; `summary.ts:95-177`) | `cadr-evals` emits the result envelope or normalized failure and writes matching run/artifact records (`src/cadr-evals/main.lisp:1-145`; `src/cadr-evals/reporter.lisp:125-180`; `src/cadr-evals/artifacts.lisp:78-116`) | deterministic eval suite, eval reporter/artifact round trips and credential-gated live eval entry | 已覆盖 |
| C-18 | runtime output during abnormal termination | pi first restores the terminal, prints `pi exiting due to uncaughtException:` and the JavaScript `Error`, then exits 1 (`interactive-mode.ts:3646-3673,3716-3721`) | every shipped entrypoint catches an otherwise unhandled serious condition before stack unwind, prints only its type and a bounded message, writes a redacted mode-0600 diagnostic under `~/.cadr/crash/`, and exits 1 (`src/cadr-ai/crash.lisp:1-220`; `src/cadr-cli/crash.lisp:1-65`; `src/cadr-cli/build-support.lisp:10-14`; `src/cadr-server/main.lisp:206-212`; `src/cadr-evals/main.lisp:107-155`) | `GOAL13-FATAL-CONDITION-BOUNDARY-REDACTS-USER-OUTPUT-AND-CRASH-LOG`; `GOAL13-INTERACTIVE-INTERRUPT-USES-THE-SANITIZED-FATAL-PATH`; credential-object print regressions | 已覆盖 |

Completeness is machine-checked as `18 = 18 covered + 0 pending`. Direct
extension output and package/tool subprocess output do not form extra channels:
their user-observable bytes are deliberately projected into C-01/C-04/C-05/C-06,
while raw implementation diagnostics are excluded by those channel gates.
Build and test diagnostics are development-only channels and do not exist in
the shipped `cadr`, `cadr-server`, or `cadr-evals` runtime surface.

The C-01 scale numbers are never hand-synced. Recount them from the artifacts
(same semantics as `test/cadr-cli/goal18-presentation-numbers-test.lisp`:
core = scenarios whose tier defaults to `core`; captures = declared
`dimensions` count, else 2; sites/branches = `printable-visible` entries and
their unique branch ids):

```sh
jq -r '[.scenarios[] | select((.tier // "core") != "full")] as $core |
  "core \($core | length)/\([$core[] | (.dimensions // [0,0]) | length] | add) " +
  "full \(.scenarios | length)/\([.scenarios[] | (.dimensions // [0,0]) | length] | add)"' \
  test/fixtures/render-diff/scenarios.json
jq -r '[.entries[] | select(.sink.channel == "printable-visible")] as $p |
  "sites \($p | length) branches \([$p[].branches[]?.id] | unique | length)"' \
  test/fixtures/render-diff/baseline-visible-strings.json
```

2026-08-14 recount: core 61/120, full 72/142, sites 476, branches 776.

### Exceptional-path closure

Each normal channel row also owns an exceptional path; C-18 is the final
runtime boundary, not an excuse to leave product errors unnormalized.

| ID | Channel | Exceptional-path contract | Gate |
|---|---|---|---|
| A-01 | C-01 active TUI | renderer cleanup restores the terminal; a stuck worker receives abort and then a bounded join/forced stop before C-18 writes outside the alternate screen | `GOAL13-TUI-EXIT-COMPLETES-WHEN-THE-ACTIVE-WORKER-IGNORES-ABORT`; fatal-boundary tests |
| A-02 | C-02 pre-TUI streams | parse/configuration errors keep their stable product copy; an unexpected condition uses C-18 without printing in-memory objects | process faux errors; fatal-boundary tests |
| A-03 | C-03 post-TUI stdout | only a clean resumable exit prints the resume command; abnormal exit prints the C-18 stderr summary and never the resume line | resume PTY lifecycle; fatal-boundary tests |
| A-04 | C-04 print mode | provider/tool failures are normalized on stderr and return nonzero; unexpected failures fall through to C-18 | print process faux errors; exit-status harness |
| A-05 | C-05 JSON mode | modeled failures remain schema-valid events; runtime failure is isolated to C-18 stderr rather than corrupting JSONL with a backtrace | fixed-baseline JSON event differential error/abort scenarios; fatal-boundary tests |
| A-06 | C-06 RPC mode | command errors remain framed RPC responses; runtime failure uses C-18 stderr and nonzero exit | fixed-baseline RPC event differential error/abort scenarios; fatal-boundary tests |
| A-07 | C-07 session JSONL | failed writes preserve the prior atomic file; a runtime failure cannot serialize an arbitrary stack/object dump into the session | session atomic-write/migration tests; fatal-boundary tests |
| A-08 | C-08 export files | export errors use the product error surface and never leave an advertised partial success; runtime failure uses C-18 | exporter failure/atomic asset tests; fatal-boundary tests |
| A-09 | C-09 auth store | parse/write/refresh failures are normalized; secrets are exact-redacted and credential structures have redacted printers even inside C-18 | auth permissions/race tests; credential print tests; fatal-boundary tests |
| A-10 | C-10 settings/package files | invalid state is rejected before atomic replacement; implementation diagnostics remain outside notices and flow to C-18 only if unhandled | settings/package error suites; infrastructure-output audit |
| A-11 | C-11 SQLite | database failures retain typed storage/server errors and transaction rollback; unhandled runtime faults use C-18 | storage failure/rollback suite; fatal-boundary tests |
| A-12 | C-12 provider transport | TLS/socket/SSE/WebSocket failures are normalized and abort is silent except `Operation aborted`; a surviving unexpected fault uses C-18 | transport normalization and three-phase abort tests; fatal-boundary tests |
| A-13 | C-13 OAuth HTTP | failure pages are escaped and byte-framed; cancel stops the listener/manual worker, releases the port and clears Working before any outer C-18 handling | OAuth failure-page tests; `GOAL13-OAUTH-CANCEL-ABORTS-THE-LOOPBACK-WORKER-AND-RELEASES-IT`; `GOAL13-EVERY-BUILT-IN-OAUTH-DIALOG-CANCEL-CLEARS-WORKING-AND-RESTORES-EDITOR` |
| A-14 | C-14 Unix socket | malformed requests produce protocol errors and listener teardown uses a bounded join; an unhandled server condition uses the shared C-18 boundary | protocol malformed-frame suite; server lifecycle tests; fatal-boundary tests |
| A-15 | C-15 exit status | all modeled failures and signals retain their assigned code; C-18 is fixed at 1 | process/status harness; fatal-boundary tests |
| A-16 | C-16 server streams | command errors retain `cadr-server:` copy; credential-bearing Radius state prints redacted and an unhandled serious condition uses the shared C-18 boundary | server error suite; `GOAL13-RADIUS-PRESENCE-NEVER-PRINTS-ITS-BEARER-TOKEN`; fatal-boundary tests |
| A-17 | C-17 eval streams/artifacts | eval failures retain `cadr-evals:` copy and do not forge a completed artifact; an unhandled serious condition uses the shared C-18 boundary | deterministic eval failure/reporter tests; fatal-boundary tests |
| A-18 | C-18 abnormal termination | terminal output excludes prompts, session content, encrypted reasoning and secrets; the private log preserves the pre-unwind failure site after exact and pattern redaction | fatal-boundary user/log/permission regression and all credential-object print regressions |

The machine gate requires all 18 `A-*` rows as well as all 18 normal channel
rows, preventing another audit that silently covers only successful execution.

## B1. Semantic theme-color assignment

The baseline schema contains 55 semantic colors
(`packages/coding-agent/src/modes/interactive/theme/theme.ts:31-103`); Cadr has
the same 55 names and values (`src/cadr-tui/theme.lisp:3-126`).  Equal values
are not enough: the rows below compare the elements to which each token is
applied.  Markdown mappings are at baseline `theme.ts:1230-1266` and Cadr
`src/cadr-tui/components/markdown.lisp:557-908`; syntax mappings are at baseline
`theme.ts:1096-1157` and Cadr
`src/cadr-cli/interactive-services.lisp:3470-3498,4132-4315`.

| Token | Baseline element assignment | Cadr element assignment | Status |
|---|---|---|---|
| `accent` | selected arrows/labels, links and tool path/pattern only; tool header remainder stays `toolOutput` (`model-selector.ts:268-301`; `render-utils.ts:75-84`; `find.ts:59-73`; `grep.ts:70-85`) | tool headers are typed segments: pattern/path use `accent`, while `in`, glob and limit use `toolOutput` (`src/cadr-cli/tui.lisp:1417-1516`; `src/cadr-tui/components/tool-block.lisp:422-442`) | 不一致（已改齐） |
| `border` | editor/dynamic/loader border (`dynamic-border.ts:10-16`; `bordered-loader.ts:13-30`) | editor, selector and loader border (`src/cadr-tui/editor.lisp:1730-1792`; `src/cadr-tui/composition/loaders.lisp:128-196`) | 一致 |
| `borderAccent` | tree compaction marker (`tree-selector.ts:790-839`) | tree compaction marker (`src/cadr-cli/interactive-services.lisp:5656-5661`) | 一致 |
| `borderMuted` | Markdown tables and code/table structure (`theme.ts:1230-1266`) | Markdown tables and code/table structure (`src/cadr-tui/components/markdown.lisp:300-390,679-750`) | 一致 |
| `success` | configured/current/assistant-success labels (`model-selector.ts:268-301`; `tree-selector.ts:774-839`) | same selector and tree labels (`src/cadr-cli/interactive-services.lisp:5613-5624,8060-8125`) | 一致 |
| `error` | product errors, abort/length messages, invalid args, and only tool-specific error renderers (`assistant-message.ts:177-200`; `render-utils.ts:71-84`; `write.ts:164-179`; `edit.ts:200-226`) | invalid segments and write/edit failures use `error`; other failed-tool output stays `toolOutput` (`src/cadr-cli/tui.lisp:1358-1401`; `src/cadr-tui/components/tool-block.lisp:74-84`) | 不一致（已改齐） |
| `warning` | warnings, read ranges, and renderer-created truncation lines (`read.ts:67-76,190-198`; `bash.ts:292-312`) | read ranges and structured detail-derived truncation rows use `warning`; raw result copy is no longer guessed from prefixes (`src/cadr-cli/tui.lisp:1403-1415,1719-1849`; `src/cadr-tui/components/tool-block.lisp:74-84`) | 不一致（已改齐） |
| `muted` | secondary labels, hints, timing, preview counts and tool suffixes (`keybinding-hints.ts:35-50`; `bash.ts:275-312`) | same categories (`src/cadr-tui/components/tool-block.lisp:388-413,494-517`; `src/cadr-tui/components/select-list.lisp:155-240`) | 一致 |
| `dim` | footer, inactive key names, timestamps, compact hints (`footer.ts:222-240`; `keybinding-hints.ts:35-50`) | same categories (`src/cadr-tui/components/status.lisp:3-165`; `src/cadr-cli/interactive/components/loaders.lisp:38-51`) | 一致 |
| `text` | ordinary selector/dialog foreground (`extension-selector.ts:80-90`; `login-dialog.ts:150-196`) | same selector/dialog foreground (`src/cadr-cli/interactive-services.lisp:7510-7540,8810-8870`) | 一致 |
| `thinkingText` | visible and hidden thinking, italic (`assistant-message.ts:139-164`) | visible and hidden thinking, italic (`src/cadr-cli/tui.lisp:1993-2075`) | 一致 |
| `selectedBg` | selected session/tree row (`session-selector.ts:500-516`; `tree-selector.ts:1156-1252`) | selected session/tree row (`src/cadr-cli/interactive-services.lisp:1640-1705,5800-5865`) | 一致 |
| `userMessageBg` | full-width user-message box (`user-message.ts:38-57`) | full-width user-message box (`src/cadr-cli/tui.lisp:2086-2123`) | 一致 |
| `userMessageText` | user Markdown foreground (`user-message.ts:40-55`) | user Markdown foreground (`src/cadr-cli/tui.lisp:2086-2123`) | 一致 |
| `customMessageBg` | custom, skill, branch and compaction transcript boxes (`custom-message.ts:33-38`; `skill-invocation-message.ts:11-52`; `branch-summary-message.ts:10-56`; `compaction-summary-message.ts:10-57`) | native skill/branch/compaction entries now compose the same full-width custom background box as extension messages (`src/cadr-cli/tui.lisp:2529-2615`) | 不一致（已改齐） |
| `customMessageText` | custom/skill/branch/compaction body (`custom-message.ts:91-110`; `skill-invocation-message.ts:36-52`; `branch-summary-message.ts:39-54`; `compaction-summary-message.ts:40-55`) | collapsed copy and expanded Markdown bodies use `customMessageText` (`src/cadr-cli/tui.lisp:2525-2606`) | 不一致（已改齐） |
| `customMessageLabel` | `[custom]`, `[skill]`, `[branch]`, `[compaction]` labels (`custom-message.ts:33-112`; `skill-invocation-message.ts:11-52`; `branch-summary-message.ts:10-56`; `compaction-summary-message.ts:10-57`) | all three native transcript components use bold bracketed `customMessageLabel` labels (`src/cadr-cli/tui.lisp:2517-2523,2544-2590`) | 不一致（已改齐） |
| `toolPendingBg` | running/default tool shell (`tool-execution.ts:63-75,248-268`) | running tool shell (`src/cadr-tui/components/tool-block.lisp:35-45,415-543`) | 一致 |
| `toolSuccessBg` | settled successful tool shell and valid edit preview (`tool-execution.ts:248-268`; `edit.ts:229-264`) | settled successful tool shell; edit-preview timing is separately missing, but settled assignment is correct (`src/cadr-tui/components/tool-block.lisp:35-45,415-543`) | 一致 |
| `toolErrorBg` | settled failed tool shell and invalid edit preview (`tool-execution.ts:248-268`; `edit.ts:229-264`) | settled failed tool shell (`src/cadr-tui/components/tool-block.lisp:35-45,415-543`) | 一致 |
| `toolTitle` | tool verb and bash `$ command` (`bash.ts:226-231`; `read.ts:67-76`; `write.ts:131-161`; `edit.ts:195-198`) | same verb/command assignment after Part A (`src/cadr-tui/components/tool-block.lisp:430-482`) | 一致 |
| `toolOutput` | raw tool output and secondary call fragments such as `in`, glob and limit (`bash.ts:258-306`; `find.ts:59-104`; `grep.ts:70-118`; `ls.ts:52-90`) | raw output and typed secondary header segments use `toolOutput`; no copy-prefix color inference remains (`src/cadr-cli/tui.lisp:1417-1516`; `src/cadr-tui/components/tool-block.lisp:74-84`) | 不一致（已改齐） |
| `mdHeading` | Markdown headings (`theme.ts:1230-1266`) | Markdown headings (`src/cadr-tui/components/markdown.lisp:557-604`) | 一致 |
| `mdLink` | linked label, underlined (`theme.ts:1230-1266`) | linked label, underlined (`src/cadr-tui/components/markdown.lisp:99-125`) | 一致 |
| `mdLinkUrl` | fallback visible URL (`theme.ts:1230-1266`) | fallback visible URL (`src/cadr-tui/components/markdown.lisp:99-125`) | 一致 |
| `mdCode` | inline code (`theme.ts:1230-1266`) | inline code (`src/cadr-tui/components/markdown.lisp:186-220`) | 一致 |
| `mdCodeBlock` | fenced code content (`theme.ts:1230-1266`) | fenced code content (`src/cadr-tui/components/markdown.lisp:737-893`) | 一致 |
| `mdCodeBlockBorder` | literal fence rows (`theme.ts:1230-1266`) | literal fence rows (`src/cadr-tui/components/markdown.lisp:737-893`) | 一致 |
| `mdQuote` | quote text (`theme.ts:1230-1266`) | quote text (`src/cadr-tui/components/markdown.lisp:609-678`) | 一致 |
| `mdQuoteBorder` | quote `│` (`theme.ts:1230-1266`) | quote `│` (`src/cadr-tui/components/markdown.lisp:609-678`) | 一致 |
| `mdHr` | horizontal rule (`theme.ts:1230-1266`) | horizontal rule (`src/cadr-tui/components/markdown.lisp:535-556`) | 一致 |
| `mdListBullet` | list/task marker (`theme.ts:1230-1266`) | list/task marker (`src/cadr-tui/components/markdown.lisp:391-534`) | 一致 |
| `toolDiffAdded` | added diff lines and word spans (`diff.ts:89-141`) | added diff lines and word spans (`src/cadr-tui/components/tool-block.lisp:240-333`) | 一致 |
| `toolDiffRemoved` | removed diff lines and word spans (`diff.ts:89-141`) | removed diff lines and word spans (`src/cadr-tui/components/tool-block.lisp:240-333`) | 一致 |
| `toolDiffContext` | hunk/context lines (`diff.ts:89-141`) | hunk/context lines (`src/cadr-tui/components/tool-block.lisp:240-333`) | 一致 |
| `syntaxComment` | Markdown plus read/write source highlighting (`theme.ts:1096-1157`; `read.ts:177-185`; `write.ts:146-155`) | Markdown and language-mapped read/write previews share the syntax highlighter (`src/cadr-cli/tui.lisp:1618-1655`; `src/cadr-tui/components/tool-block.lisp:328-362`) | 不一致（已改齐） |
| `syntaxKeyword` | Markdown plus read/write source highlighting (`theme.ts:1096-1157`; `read.ts:177-185`; `write.ts:146-155`) | Markdown and language-mapped read/write previews share the syntax highlighter (`src/cadr-cli/tui.lisp:1618-1655`; `src/cadr-tui/components/tool-block.lisp:328-362`) | 不一致（已改齐） |
| `syntaxFunction` | Markdown plus read/write source highlighting (`theme.ts:1096-1157`; `read.ts:177-185`; `write.ts:146-155`) | Markdown and language-mapped read/write previews share the syntax highlighter (`src/cadr-cli/tui.lisp:1618-1655`; `src/cadr-tui/components/tool-block.lisp:328-362`) | 不一致（已改齐） |
| `syntaxVariable` | Markdown plus read/write source highlighting (`theme.ts:1096-1157`; `read.ts:177-185`; `write.ts:146-155`) | Markdown and language-mapped read/write previews share the syntax highlighter (`src/cadr-cli/tui.lisp:1618-1655`; `src/cadr-tui/components/tool-block.lisp:328-362`) | 不一致（已改齐） |
| `syntaxString` | Markdown plus read/write source highlighting (`theme.ts:1096-1157`; `read.ts:177-185`; `write.ts:146-155`) | Markdown and language-mapped read/write previews share the syntax highlighter (`src/cadr-cli/tui.lisp:1618-1655`; `src/cadr-tui/components/tool-block.lisp:328-362`) | 不一致（已改齐） |
| `syntaxNumber` | Markdown plus read/write source highlighting (`theme.ts:1096-1157`; `read.ts:177-185`; `write.ts:146-155`) | Markdown and language-mapped read/write previews share the syntax highlighter (`src/cadr-cli/tui.lisp:1618-1655`; `src/cadr-tui/components/tool-block.lisp:328-362`) | 不一致（已改齐） |
| `syntaxType` | Markdown plus read/write source highlighting (`theme.ts:1096-1157`; `read.ts:177-185`; `write.ts:146-155`) | Markdown and language-mapped read/write previews share the syntax highlighter (`src/cadr-cli/tui.lisp:1618-1655`; `src/cadr-tui/components/tool-block.lisp:328-362`) | 不一致（已改齐） |
| `syntaxOperator` | Markdown plus read/write source highlighting (`theme.ts:1096-1157`; `read.ts:177-185`; `write.ts:146-155`) | Markdown and language-mapped read/write previews share the syntax highlighter (`src/cadr-cli/tui.lisp:1618-1655`; `src/cadr-tui/components/tool-block.lisp:328-362`) | 不一致（已改齐） |
| `syntaxPunctuation` | Markdown plus read/write source highlighting (`theme.ts:1096-1157`; `read.ts:177-185`; `write.ts:146-155`) | Markdown and language-mapped read/write previews share the syntax highlighter (`src/cadr-cli/tui.lisp:1618-1655`; `src/cadr-tui/components/tool-block.lisp:328-362`) | 不一致（已改齐） |
| `thinkingOff` | editor border at thinking `off` (`theme.ts:407-425`; `interactive-mode.ts:3810-3815`) | same editor border (`src/cadr-tui/theme.lisp:505-524`; `src/cadr-tui/editor.lisp:1900-1932`) | 一致 |
| `thinkingMinimal` | editor border at thinking `minimal` (`theme.ts:407-425`; `interactive-mode.ts:3810-3815`) | same editor border (`src/cadr-tui/theme.lisp:505-524`; `src/cadr-tui/editor.lisp:1900-1932`) | 一致 |
| `thinkingLow` | editor border at thinking `low` (`theme.ts:407-425`; `interactive-mode.ts:3810-3815`) | same editor border (`src/cadr-tui/theme.lisp:505-524`; `src/cadr-tui/editor.lisp:1900-1932`) | 一致 |
| `thinkingMedium` | editor border at thinking `medium` (`theme.ts:407-425`; `interactive-mode.ts:3810-3815`) | same editor border (`src/cadr-tui/theme.lisp:505-524`; `src/cadr-tui/editor.lisp:1900-1932`) | 一致 |
| `thinkingHigh` | editor border at thinking `high` (`theme.ts:407-425`; `interactive-mode.ts:3810-3815`) | same editor border (`src/cadr-tui/theme.lisp:505-524`; `src/cadr-tui/editor.lisp:1900-1932`) | 一致 |
| `thinkingXhigh` | editor border at thinking `xhigh` (`theme.ts:407-425`; `interactive-mode.ts:3810-3815`) | same editor border (`src/cadr-tui/theme.lisp:505-524`; `src/cadr-tui/editor.lisp:1900-1932`) | 一致 |
| `thinkingMax` | editor border at thinking `max` (`theme.ts:407-425`; `interactive-mode.ts:3810-3815`) | same editor border (`src/cadr-tui/theme.lisp:505-524`; `src/cadr-tui/editor.lisp:1900-1932`) | 一致 |
| `bashMode` | user-bash editor/execution emphasis (`bash-execution.ts:130-151`) | same user-bash emphasis (`src/cadr-tui/theme.lisp:526-534`; `src/cadr-cli/tui.lisp:790-835`) | 一致 |
| `pageBg` | exported session page background (`core/export-html/index.ts:108-167`) | active interactive theme and explicit `pageBg` flow into the template body background (`src/cadr-cli/main.lisp:3293-3348`; `src/cadr-agent/session.lisp:2440-2534`) | 不一致（已改齐） |
| `cardBg` | exported session card background (`core/export-html/index.ts:108-167`) | active `cardBg`, or the baseline-derived fallback, becomes the template container background (`src/cadr-cli/main.lisp:3293-3348`; `src/cadr-agent/session.lisp:2440-2534`) | 不一致（已改齐） |
| `infoBg` | emitted as `--exportInfoBg` and injected as `--info-bg`; the fixed template currently has no `var(--info-bg)` consumer (`core/export-html/index.ts:108-167`; `export-html/template.css:1-5`) | same exported declarations and deliberate non-consumption in the byte-identical fixed template (`src/cadr-agent/session.lisp:2307-2405`; `src/cadr-agent/export-html/template.css:1-5`) | 不一致（已改齐） |

B1 final count: `36 一致 + 19 不一致（已改齐） / 0 不一致 / 0 有意差异 = 55`.

## B2. Visible element contracts

### Tools

| ID | Element | Baseline | Cadr | Status |
|---|---|---|---|---|
| T-01 | outer shell/state | one leading spacer, `Box(1,1)`, pending/success/error background (`tool-execution.ts:63-75,248-268`) | same geometry and three backgrounds (`src/cadr-tui/components/tool-block.lisp:415-543`) | 一致 |
| T-02 | bash title/time | bold `toolTitle` `$ command`; explicit timeout only, muted; output tail 5; `Elapsed/Took 0.0s` (`bash.ts:222-231,258-313`) | same after Part A (`src/cadr-cli/tui.lisp:1389-1397`; `src/cadr-tui/components/tool-block.lisp:441-517`) | 一致 |
| T-03 | read title/range/preview | bold verb, accent path, warning range; collapsed success has no preview, collapsed error has 10 (`read.ts:67-76,164-200`) | same title/range and budgets (`src/cadr-cli/tui.lisp:1398-1415`; `src/cadr-tui/components/tool-block.lisp:372-387,474-478`) | 一致 |
| T-04 | write call content | path plus first 10/full content lines, language-aware source highlighting (`write.ts:131-161`) | write/read previews now carry the baseline extension map into the shared syntax highlighter (`src/cadr-cli/tui.lisp:1618-1655`; `src/cadr-tui/components/tool-block.lisp:328-362`) | 不一致（已改齐） |
| T-05 | edit preview | validates args and renders pending preview diff before execution; preview decides pending header background (`edit.ts:195-264`) | the start event invokes read-only edit validation/diff generation and assigns the pending preview state before execution (`src/cadr-cli/tools/edit.lisp:543-580`; `src/cadr-cli/tui.lisp:1698-1717,2016-2075`) | 不一致（已改齐） |
| T-06 | find title | accent pattern; ` in path` and optional limit are `toolOutput` (`find.ts:59-73`) | typed header segments make only the pattern accent (`src/cadr-cli/tui.lisp:1486-1492`) | 不一致（已改齐） |
| T-07 | grep title | accent `/pattern/`; ` in path`, glob and limit are `toolOutput` (`grep.ts:70-85`) | typed header segments preserve the baseline token split (`src/cadr-cli/tui.lisp:1493-1509`) | 不一致（已改齐） |
| T-08 | ls title | accent path; optional limit is `toolOutput` (`ls.ts:52-59`) | path and limit are separate typed segments (`src/cadr-cli/tui.lisp:1510-1516`) | 不一致（已改齐） |
| T-09 | clickable file paths | read/write/edit/ls path is OSC-8 linked to an absolute `file:` URL when terminal capabilities allow (`render-utils.ts:19-23,75-84`) | eligible path segments carry an escaped absolute `file:` URL and render OSC-8 only when supported (`src/cadr-cli/tui.lisp:1372-1401`; `src/cadr-tui/components/tool-block.lisp:409-420`) | 不一致（已改齐） |
| T-10 | invalid argument copy | every non-string visible arg is exact `[invalid arg]`; missing value is empty/ellipsis by tool (`render-utils.ts:25-29,71-84`) | every non-string visible argument now uses exact `[invalid arg]` (`src/cadr-cli/tui.lisp:1358-1365`) | 不一致（已改齐） |
| T-11 | failed/raw output color | bash/find/grep/ls/read raw output remains `toolOutput`; only write/edit explicit errors are `error` (`bash.ts:258-306`; `read.ts:164-200`; `write.ts:146-179`; `edit.ts:200-226`) | output token selection is tool-specific; structured renderer warnings are separate supplemental rows (`src/cadr-tui/components/tool-block.lisp:74-84`; `src/cadr-cli/tui.lisp:1719-1849`) | 不一致（已改齐） |
| T-12 | preview/expand/truncation | bash tail 5; write 10; grep 15; find/ls 20; read success 0/error 10; exact earlier/more-lines hints (`bash.ts:264-288`; `read.ts:173-188`; `write.ts:150-158`; `find.ts:85-105`; `grep.ts:97-119`; `ls.ts:71-91`) | same budgets, direction and hint placement (`src/cadr-tui/components/tool-block.lisp:61-70,362-413`) | 一致 |
| T-13 | compact read titles | docs/resources/skills use `read docs`, `read resource`, or `[skill] name`, with expand hint (`read.ts:91-162`) | repo docs, resources and `SKILL.md` are classified before normal path rendering and use the exact compact title forms (`src/cadr-cli/tui.lisp:1537-1616`) | 不一致（已改齐） |

### Messages

| ID | Element | Baseline | Cadr | Status |
|---|---|---|---|---|
| M-01 | user | full-width background, X=`outputPad`, Y=1, OSC-133 zone, Markdown preserves list markers/escapes (`user-message.ts:38-68`) | same composition and OSC-133 boundaries (`src/cadr-cli/tui.lisp:2086-2123`; `src/cadr-cli/interactive-services.lisp:16-34`) | 一致 |
| M-02 | assistant | leading spacer, no background, Markdown, OSC-133 only without tool calls (`assistant-message.ts:78-114`) | same (`src/cadr-cli/tui.lisp:1935-2075`) | 一致 |
| M-03 | thinking | consecutive blocks merge with blank lines; muted/italic; one spacer before following answer (`assistant-message.ts:115-168`) | same (`src/cadr-cli/tui.lisp:2003-2075`) | 一致 |
| M-04 | length/error/abort | exact length message, `Operation aborted`, or `Error: ...`, with one spacer and output padding (`assistant-message.ts:172-201`) | same exact copy, color and spacing (`src/cadr-cli/tui.lisp:1954-2001`) | 一致 |
| M-05 | extension custom message/entry | custom background/label/body or extension-owned component (`custom-message.ts:33-112`; `custom-entry.ts:40-60`) | same bridge/default surface (`src/cadr-cli/tui.lisp:2124-2198`) | 一致 |
| M-06 | skill invocation | separate collapsible custom-background `[skill] name` row plus user text (`skill-invocation-message.ts:11-52`; `interactive-mode.ts:3290-3369`) | both history seeding and streaming message-start parse the skill envelope into a collapsible skill entry plus a separate user entry (`src/cadr-cli/tui.lisp:1259-1351,1953-1985,2529-2563`) | 不一致（已改齐） |
| M-07 | branch/compaction summary | collapsible custom-background component, label, localized token count and full Markdown (`branch-summary-message.ts:10-56`; `compaction-summary-message.ts:10-57`) | native messages and compaction events retain summary/tokens as typed entry fields and render exact collapsed/expanded components (`src/cadr-cli/tui.lisp:1303-1320,2221-2243,2564-2615`) | 不一致（已改齐） |

### Footer and active status

| ID | Element | Baseline | Cadr | Status |
|---|---|---|---|---|
| F-01 | cwd/branch/session | home-relative cwd, then ` (branch)` and ` • session` (`footer.ts:32-44,113-126`) | same (`src/cadr-cli/interactive/footer.lisp:3-25`; `src/cadr-tui/components/status.lisp:3-13`) | 一致 |
| F-02 | usage/cost | `↑ ↓ R W CH`; 1-decimal/rounded k/M; `$0.000`; optional `(sub)` (`footer.ts:24-29,128-145`) | same (`src/cadr-tui/components/status.lisp:14-103`) | 一致 |
| F-03 | context | one decimal `%/window`, `(auto)`, warning `>70`, error `>90` (`footer.ts:147-164`) | same thresholds and copy (`src/cadr-tui/components/status.lisp:104-132`) | 一致 |
| F-04 | provider/model/thinking | right-aligned; provider only with multiple providers and space; `thinking off` special copy (`footer.ts:168-220`) | same (`src/cadr-tui/components/status.lisp:133-213`) | 一致 |
| F-05 | extension statuses | alphabetic, control characters collapsed, optional third line (`footer.ts:232-243`) | same (`src/cadr-tui/components/status.lisp:214-234`) | 一致 |
| F-06 | working/retry/compaction | `Working...` is installed only by `agent_start`; all built-in slash commands remain local, while compaction has its distinct `Compacting context...` state (`interactive-mode.ts:2691-2823,2880-2917`; `status-indicator.ts:9-113`) | `agent-working-p` changes only on `:agent-start`/`:agent-settled`; generic command-worker `busy-p` still locks the editor but never renders the agent spinner, and compaction keeps its separate state (`src/cadr-cli/tui.lisp:73,1995-2022,4453-4470,4602-4621`) | 不一致（已改齐） |

### Overlays and selectors

The row order, exact copy, counts, selected spans, borders, descriptions,
search prompts, and transcript preservation are already locked by the 15
full-screen fixtures and their independent baseline oracles.  The evidence
below rechecks the production renderers rather than treating the hashes as an
oracle.

| ID | Surface | Baseline | Cadr | Status |
|---|---|---|---|---|
| O-01 | model | `model-selector.ts:91-130,162-185,248-307` | `src/cadr-cli/interactive-services.lisp:7950-8155` | 一致 |
| O-02 | model scoped state | `model-selector.ts:91-130,162-185,248-307` | `src/cadr-cli/interactive-services.lisp:7950-8155` | 一致 |
| O-03 | settings | `settings-selector.ts:472-738`; `settings-list.ts:80-249` | `src/cadr-cli/interactive-services.lisp:7002-7195` | 一致 |
| O-04 | resume | `session-selector.ts:119-175,414-519,685-746` | `src/cadr-cli/interactive-services.lisp:1288-1705` | 一致 |
| O-05 | fork | `user-message-selector.ts:14-148` | `src/cadr-cli/interactive-services.lisp:1719-1875` | 一致 |
| O-06 | tree | `tree-selector.ts:664-851,1156-1385` | `src/cadr-cli/interactive-services.lisp:5340-6055` | 一致 |
| O-07 | login method | method names and optional `loginLabel` come from each provider's auth method (`interactive-mode.ts:4984-5039`; `auth/types.ts:188-197`) | the selector consumes provider-owned OAuth presentation metadata, including exact method names and optional login labels (`src/cadr-ai/oauth/pkce.lisp:3-30`; `src/cadr-ai/oauth/providers/*.lisp`; `src/cadr-cli/interactive/selectors/auth.lisp:1-104`) | 不一致（已改齐） |
| O-08 | login provider | provider rows use provider display names, distinct from auth-method names (`interactive-mode.ts:4875-4934`; `oauth-selector.ts:51-180`) | validated declarations/runtime projections carry the same provider display names without hard-coded selector aliases (`src/cadr-ai/providers/definitions.lisp:1-963`; `src/cadr-ai/providers/runtime-projection.lisp:1-270`; `src/cadr-cli/interactive/selectors/auth.lisp:205-315`) | 不一致（已改齐） |
| O-09 | logout provider | `oauth-selector.ts:51-180` | `src/cadr-cli/interactive-services.lisp:7420-7710` | 一致 |
| O-10 | API-key input | `login-dialog.ts:30-71,154-218` | `src/cadr-cli/interactive-services.lisp:7310-7415` | 一致 |
| O-11 | scoped models | `scoped-models-selector.ts:91-252` | `src/cadr-cli/interactive-services.lisp:8778-8945` | 一致 |
| O-12 | trust | `trust-selector.ts:32-115` | `src/cadr-cli/interactive-services.lisp:6057-6310` | 一致 |
| O-13 | import confirmation | `interactive-mode.ts:5523`; `extension-selector.ts:18-90` | `src/cadr-cli/tui.lisp:4710-4785` | 一致 |
| O-14 | extension select/confirm/custom | `interactive-mode.ts:2244-2563`; `extension-selector.ts:18-90` | `src/cadr-cli/tui.lisp:4650-4785`; `src/cadr-tui/composition/settings-list.lisp:25-115` | 一致 |
| O-15 | autocomplete | editor trigger/update paths, request cancellation/debounce, value/description list and popup placement (`packages/tui/src/components/editor.ts:590-598,1123-1153,1343-1357,1708-1722,2102-2350`) | same natural/forced trigger rules, isolated request state, 20 ms debounce and popup geometry (`src/cadr-tui/editor.lisp:966-1256,1284-1351,1427-1525,1663-1810`) | 一致 |
| O-16 | selector boundary navigation | selectors implement component-specific non-universal boundary policies (`model-selector.ts:248-307`; `settings-list.ts:80-249`; `tree-selector.ts:1156-1252`) | user-approved global first/last bidirectional wrap (`src/cadr-tui/components/select-list.lisp:5-50` and selector-specific move functions) | 有意差异 |

### Notices and system surfaces

| ID | Surface | Baseline | Cadr | Status |
|---|---|---|---|---|
| N-01 | status/notice | dim, one leading spacer, no protocol prefix; status coalesces (`interactive-mode.ts:3803-3806,3910-3930`) | same; `session>` is confined to REPL (`src/cadr-cli/tui.lisp:2204-2227`) | 一致 |
| N-02 | error/warning | exact `Error: ` / `Warning: `, one-cell output padding (`interactive-mode.ts:3916-3928`) | same (`src/cadr-cli/tui.lisp:2228-2253`) | 一致 |
| N-03 | new-session success | accent `✓ New session started` with its distinct spacing (`interactive-mode.ts:5916`) | same (`src/cadr-cli/tui.lisp:2254-2267,4965-4975`) | 一致 |
| N-04 | reload | exact successful status text (`interactive-mode.ts:5456-5460`) | same (`src/cadr-cli/main.lisp:1780-1792`) | 一致 |
| N-05 | trust warning/selector | project path/state, three choices and exact help (`trust-selector.ts:32-115`) | same (`src/cadr-cli/interactive-services.lisp:6057-6310`) | 一致 |
| N-06 | startup banner/resources | compact/expanded resource list, loaded-count details and expansion hint (`interactive-mode.ts:758-817`) | same composition and copy, with the product name changed to Cadr (`src/cadr-cli/interactive-components.lisp:430-720`; `src/cadr-cli/main.lisp:3920-3924`) | 有意差异 |
| N-07 | compaction transient state | `Compacting context...`, escape hint, cancellation/error status (`status-indicator.ts:74-91`; `interactive-mode.ts:3112-3155`) | same transient state; final summary mismatch is M-07 (`src/cadr-cli/tui.lisp:1793-1830,2625-2691`) | 一致 |
| N-08 | OAuth login dialog, method partition, and URL | title uses the provider display name; provider-authored labels/instructions/prompt copy remain distinct; provider-specific auth selection appears only for 2+ methods; OpenAI Codex offers browser/device-code login; user cancellation restores the editor silently (`login-dialog.ts:41-48,83-90`; `interactive-mode.ts:4937-5039,5240-5250,5310-5360`; `openai-codex.ts:510-530`) | provider metadata supplies the exact labels/title/instructions/prompt; `login-auth-type-route` implements the 0/1/2+ cardinality; OpenAI browser/device-code selection is projected through the same runtime prompt bridge; typed `authentication-cancelled` is swallowed only at the interactive command boundary (`src/cadr-ai/oauth/pkce.lisp:3-30`; `src/cadr-ai/oauth/providers/openai-device.lisp:167-199`; `src/cadr-cli/interactive/selectors/auth.lisp:36-72`; `src/cadr-cli/interactive/controller.lisp:65-76,850-890`) | 不一致（已改齐） |
| N-09 | model catalog refresh | exact `Model catalogs refreshed.` and configured-provider guidance (`model-selector.ts:91-103,174-185`) | same (`src/cadr-cli/main.lisp:3455-3480`; `src/cadr-cli/interactive-services.lisp:8060-8090`) | 一致 |
| N-10 | package/install foreground output | deliberate foreground progress; wrapper diagnostics excluded (`package-manager-cli.ts:503-510`; `core/package-manager.ts:2530-2536`) | same product/diagnostic boundary (`src/cadr-cli/package-manager.lisp:937-1105`) | 一致 |

B2 count after the fifth real-terminal corrective: `35 一致 + 15 不一致（已改齐） / 0 不一致 / 2 有意差异 = 52`.

## B3. Paths and numeric formats

| ID | Format | Baseline | Cadr | Status |
|---|---|---|---|---|
| P-01 | tool `~` shortening | raw prefix test: any string starting with `homedir` is shortened (`render-utils.ts:10-17`) | tool-only `shortened-home-prefix-path` uses the same raw prefix rule; footer/image paths retain their boundary-safe contract (`src/cadr-tui/terminal-image.lisp:647-655`; `src/cadr-cli/tui.lisp:1385-1401`) | 不一致（已改齐） |
| P-02 | footer `~` shortening | only cwd equal to or inside home is shortened (`footer.ts:32-44`) | same boundary rule (`src/cadr-cli/interactive-services.lisp:1877-1899`) | 一致 |
| P-03 | session-selector `~` shortening | raw prefix test (`session-selector.ts:26-33`) | session display uses the same raw home-prefix substitution, including the prefix-only edge case (`src/cadr-cli/interactive-services.lisp:1288-1301`) | 不一致（已改齐） |
| P-04 | tool path URI | eligible file paths receive OSC-8 `file:` links (`render-utils.ts:19-23,75-84`) | typed path segments carry escaped absolute `file:` URLs and the component emits OSC-8 conditionally (`src/cadr-cli/tui.lisp:1372-1401`; `src/cadr-tui/components/tool-block.lisp:409-420`) | 不一致（已改齐） |
| P-05 | read range | `:start`, or `:start-end` where default start is 1 (`read.ts:67-76`) | same (`src/cadr-cli/tui.lisp:1398-1415`) | 一致 |
| P-06 | tokens/cost/context | `<1k`, one-decimal k/M, rounded k/M, `$0.000`, `0.0%` (`footer.ts:24-29,111-164`) | same positive-number thresholds and units (`src/cadr-tui/components/status.lisp:14-132`) | 一致 |
| P-07 | tool elapsed time | seconds with exactly one decimal (`bash.ts:222-224,309-313`) | seconds with exactly one decimal (`src/cadr-tui/components/tool-block.lisp:494-517`) | 一致 |
| P-08 | session age | `now`, `m`, `h`, `d`, `w`, `mo`, `y` with floor boundaries (`session-selector.ts:35-49`) | same thresholds and units (`src/cadr-cli/interactive-services.lisp:1306-1326`) | 一致 |
| P-09 | tree label timestamp | today `HH:MM`; current year `M/D HH:MM`; older `YY/M/D HH:MM` (`tree-selector.ts:854-877`) | parses ISO zones, projects into local time, and selects the same today/current-year/older-year shape (`src/cadr-cli/interactive-services.lisp:5311-5388`) | 不一致（已改齐） |
| P-10 | truncation sizes/counts | binary size units, line/result/match/entry counts and exact brackets (`bash.ts:292-306`; `read.ts:190-198`; `find.ts:98-105`; `grep.ts:110-119`; `ls.ts:84-91`) | same displayed units/counts; model-facing result copy remains independently locked (`src/cadr-tui/components/tool-block.lisp:362-413`; `src/cadr-cli/truncation.lisp:1-120`) | 一致 |

B3 count after Part C selector-format batch: `6 一致 + 4 不一致（已改齐） / 0 不一致 / 0 有意差异 = 10`.

## B4. Non-terminal content returned by Cadr services

| ID | Surface | Baseline | Cadr | Status |
|---|---|---|---|---|
| H-01 | OAuth success HTML | complete responsive dark page, pi mark, `<title>`/`<h1>` = `Authentication successful`, dim close message (`packages/ai/src/auth/oauth/oauth-page.ts:1-99`) | the shell/copy/geometry remain aligned; Cadr's single-path white 800×800 grid mark is a two-cell cons diagram with a directional notch rather than pi's brand asset (`src/cadr-ai/oauth/page.lisp:1-113`) | 有意差异（Cadr 品牌标识） |
| H-02 | OAuth failure HTML | same shell and pi mark with `Authentication failed`, escaped message and optional monospace details (`oauth-page.ts:3-17,102-108`) | same failure shell and Cadr-owned cons-cell mark (`src/cadr-ai/oauth/page.lisp:1-119`) | 有意差异（Cadr 品牌标识） |
| H-03 | callback-specific copy | route/state/missing-code/internal failures have distinct escaped messages (`openai-codex.ts:340-363`; `anthropic.ts:118-145`; `radius.ts:176-202`) | parser returns a typed outcome and provider-specific response copy for OpenAI, Anthropic and Radius (`src/cadr-ai/oauth/callback.lisp:78-127`; `src/cadr-ai/oauth/page.lisp:120-149`) | 不一致（已改齐） |
| H-04 | HTML escaping | title, heading, message and details escape `&<>"'` (`oauth-page.ts:3-17`) | all four fields pass through one character-level HTML escaper before interpolation (`src/cadr-ai/oauth/page.lisp:6-106`) | 不一致（已改齐） |
| H-05 | session export HTML | theme variables including `pageBg/cardBg/infoBg`, complete template/CSS/JS, Base64 session data, Marked and syntax highlighter (`core/export-html/index.ts:108-174`) | exact baseline template assets, Base64 session data, licensed vendored browser scripts, and active/default theme projection (`src/cadr-agent/session.lisp:2124-2555`; `src/cadr-cli/main.lisp:1533-1544,3293-3348`) | 不一致（已改齐） |
| H-06 | HTTP response framing | UTF-8 HTML content type, byte-accurate content length and close (`openai-codex.ts:336-365`) | same wire-level framing and UTF-8 byte length (`src/cadr-ai/oauth/callback.lisp:129-144`) | 一致 |

B4 final count: `1 一致 + 3 不一致（已改齐） / 0 不一致 / 2 有意差异 = 6`.

## Audit summary and Part C worklist

| Category | 一致 | 不一致 | 有意差异 | Total |
|---|---:|---:|---:|---:|
| B1 semantic colors | 55 | 0 | 0 | 55 |
| B2 visible elements | 50 | 0 | 2 | 52 |
| B3 paths/numbers | 10 | 0 | 0 | 10 |
| B4 non-terminal content | 4 | 0 | 2 | 6 |
| **Total** | **119** | **0** | **4** | **123** |

The 39 row-level mismatches collapse to these implementation clusters; one fix
may close multiple B1/B2/B3 rows, but no row may be silently dropped:

1. tool header segment colors for find/grep/ls;
2. tool path shortening and OSC-8 links;
3. exact invalid-argument copy;
4. read/write source syntax highlighting;
5. tool-specific raw/error/warning output colors;
6. pre-execution edit preview;
7. compact read docs/resource/skill titles;
8. skill, branch and compaction transcript components;
9. session-selector home shortening and tree label timestamp formatting;
10. OAuth success/failure HTML and callback-specific escaped copy;
11. session-export theme/template presentation.

Part B changed no presentation source.  Part C must update each affected row to
`不一致（已改齐）` with implementation and regression evidence. The four
row-level intentional dispositions remain frozen: product branding on the
startup and both OAuth result surfaces, plus user-approved universal selector
wrapping.

All eleven implementation clusters are closed.  The final presentation ledger
is `123 = 119 aligned/closed + 0 open + 4 intentional`.
