# Goal 13 acceptance ledger

## Part A — Goal 12 carry-over defects

### Result

Part A is implemented and committed before the presentation audit begins.  The
fixes are deliberately split at the transport/presentation boundary: the
provider reducer owns authoritative tool-call JSON, while the TUI only changes
how already-parsed arguments are displayed.  Tool result text, session content,
payloads, and wire events are unchanged.

| Item | Baseline evidence | Cadr implementation | Regression |
|---|---|---|---|
| OpenAI Responses tool arguments | `packages/ai/src/api/openai-responses-shared.ts:629-645` replaces the scratch JSON with `response.function_call_arguments.done.arguments` and emits only a missing suffix when it is a prefix extension | `src/cadr-ai/providers/openai.lisp:615-661` now performs the same authoritative replacement; a correction never appends the bad scratch value | `GOAL13-STREAMED-TOOL-ARGUMENTS-ARE-EXACT-AT-EVERY-DELTA-BOUNDARY`; `GOAL13-OPENAI-AUTHORITATIVE-TOOL-ARGUMENTS-REPLACE-CORRUPT-DELTAS` (`test/cadr-ai/goal12-provider-capabilities-test.lisp:292-356`) |
| Bash command and explicit timeout | `packages/coding-agent/src/core/tools/bash.ts:226-231` applies `toolTitle` + bold to the command and `muted` only to an explicitly supplied timeout | `src/cadr-cli/tui.lisp:1389-1397`; `src/cadr-tui/components.lisp:1593-1634` | `GOAL13-EXPLICIT-BASH-TIMEOUT-APPEARS-ONLY-WHEN-MODEL-SUPPLIES-IT`; `GOAL13-TOOL-TITLE-COLORS-PATH-SHORTENING-AND-READ-RANGE-MATCH-BASELINE` (`test/cadr-cli/tui-test.lisp:1358-1442`) |
| Read range color | `packages/coding-agent/src/core/tools/read.ts:67-76` renders the `:start-end` suffix with `warning` | `src/cadr-tui/components.lisp:1626-1630` separates the suffix from the accent-colored path | `GOAL13-TOOL-TITLE-COLORS-PATH-SHORTENING-AND-READ-RANGE-MATCH-BASELINE` |
| Home-shortened paths | `packages/coding-agent/src/core/tools/render-utils.ts:10-17,75-84`; find/grep call the same helper | `src/cadr-cli/tui.lisp:1398-1454` reuses `cadr-tui:shortened-home-path` for read/write/edit/grep/find/ls | `GOAL13-TOOL-TITLE-COLORS-PATH-SHORTENING-AND-READ-RANGE-MATCH-BASELINE` |
| Concurrent Slynk/FASL isolation | build and test already promised a fresh HOME, but inherited ASDF/XDG configuration could still redirect both SBCL processes into one cache | `scripts/test-cl.sh:16-24` and `build.sh:34-40` bind both `XDG_CACHE_HOME` and `ASDF_OUTPUT_TRANSLATIONS` below their unique `mktemp` roots | `GOAL10-SLYNK-INIT-IS-ISOLATED-FROM-THE-BUILD-USERS-HOME` (`test/cadr-cli/remote-repl-test.lisp:285-372`) |

The Slynk choice is isolation, not locking.  Compiler artifacts are disposable
per invocation, so a shared-cache lock would add failure and cleanup states for
no benefit.  Unique ASDF output trees make concurrent compilation structurally
disjoint, including when a caller has exported a global
`ASDF_OUTPUT_TRANSLATIONS` or `XDG_CACHE_HOME`.

### Why the old gates missed these defects

- The old streamed-argument test sent one incomplete prefix and asserted only
  that repaired JSON was temporarily usable.  It never sent the authoritative
  `function_call_arguments.done` event, never finalized the call, never tried
  every split boundary, and never compared the assembled raw JSON or parsed
  values character-for-character.
- Tool-title snapshots stripped ANSI, used relative paths, and therefore could
  not distinguish accent from `toolTitle`/`warning` or `/root/...` from `~/...`.
- The explicit-timeout regression encoded an earlier incorrect ruling that the
  suffix must always be absent.  Goal 13 supersedes that assertion with the
  fixed-baseline contract: absent by default, present only when the model
  supplies `timeout`.
- The Slynk test isolated `HOME` but not the two variables ASDF actually honors
  for output placement.  A clean single process passed; two processes could
  still be redirected to one externally configured cache.

### Mechanical verification

`./scripts/test-cl.sh` after the Part A changes:

```text
cadr test summary: systems=8 checks=11498 pass=11498 skip=0 fail=0
```

Part B begins from this committed state and is audit-only: no presentation code
will change until the complete presentation ledger is committed.

## Part B — complete presentation audit

Part B audited the fixed baseline against Cadr without changing presentation
code.  The fourth ledger is `docs/presentation-parity.md`; it contains all 55
semantic theme tokens, 52 visible-element contracts, 10 path/number formats,
and 6 non-terminal surfaces, each with baseline and Cadr `file:line` evidence.

The result is `123 = 82 一致 + 39 不一致 + 2 有意差异`.  The 39 row-level
differences reduce to 11 implementation clusters: tool subsegment colors,
tool path shortening/links, invalid-argument copy, read/write highlighting,
tool-specific result colors, edit preview, compact-read titles,
skill/branch/compaction transcript components, tree timestamps, OAuth HTML,
and session-export presentation.

The audit found two important false positives in the older ledgers.  First,
having all syntax tokens and a Markdown highlighter did not prove that read and
write tool previews used them.  Second, parsing `pageBg/cardBg/infoBg` did not
prove that the real exporter consumed those values: the parser had no
production caller.  These are exactly the class of defects this fourth axis is
meant to expose.

Part B source-diff boundary from `e04d9230f`:

```text
docs/presentation-parity.md
docs/acceptance/goal-v13.md
```

No `src/`, `test/`, build, script, or fixture file changed during Part B.

## Part C batch 1 — built-in tool presentation

The first Part C batch closes presentation clusters 1–7 without changing tool
execution, model-facing result text, payloads, session data, or event counts.
Headers are now typed segments instead of one uniformly colored summary; this
enforces the baseline token split and also carries optional OSC-8 metadata.

| Contract | Baseline | Cadr implementation | Regression |
|---|---|---|---|
| find/grep/ls header tokens, exact invalid copy, tool-only home prefix, path links | `render-utils.ts:10-29,71-84`; `find.ts:59-73`; `grep.ts:70-85`; `ls.ts:52-59` | `src/cadr-cli/tui.lisp:1358-1516`; `src/cadr-tui/components.lisp:1561-1594`; `src/cadr-tui/terminal-image.lisp:647-655` | `GOAL13-TOOL-HEADER-SEGMENTS-MATCH-BASELINE-COLORS-LINKS-AND-INVALID-COPY` |
| read/write source highlighting | `read.ts:177-185`; `write.ts:146-155`; `theme.ts:1096-1157` | `src/cadr-cli/tui.lisp:1618-1655`; `src/cadr-tui/components.lisp:1480-1514` | `GOAL13-READ-AND-WRITE-SOURCE-PREVIEWS-USE-BASELINE-SYNTAX-COLORS` |
| tool-specific output colors and renderer warnings | `bash.ts:258-312`; `read.ts:164-200`; `write.ts:164-179`; `edit.ts:200-226`; `find.ts:85-105`; `grep.ts:97-119`; `ls.ts:71-91` | `src/cadr-tui/components.lisp:1226-1236`; `src/cadr-cli/tui.lisp:1719-1849` | `GOAL13-TOOL-RESULTS-USE-TOOL-SPECIFIC-COLORS-AND-DETAIL-WARNINGS`; `GOAL13-TOOL-OUTPUT-COLORS-ARE-TOOL-SPECIFIC-WHILE-STATUS-BACKGROUNDS-REMAIN` |
| edit pending preview | `edit.ts:195-264` validates and builds a diff before execution | `src/cadr-cli/tools/edit.lisp:543-580`; `src/cadr-cli/tui.lisp:1698-1717,2016-2075` uses the same read-only validation/diff path | `GOAL13-EDIT-CALL-RENDERS-PREEXECUTION-PREVIEW-AND-VALIDATION-STATE` |
| compact read title | `read.ts:91-162` classifies docs, resources, and skills | `src/cadr-cli/tui.lisp:1537-1616` performs the same classification before ordinary path rendering | `GOAL13-COMPACT-READ-TITLES-MATCH-BASELINE-CLASSIFICATION-AND-COPY` |

Old → new observable values are exact: uniformly accent search summaries became
accent pattern/path plus `toolOutput` suffixes; tool-specific invalid labels
became `[invalid arg]`; eligible absolute file paths gained OSC-8 links; source
previews gained language token colors; bash/read/find/grep/ls raw failures no
longer become red merely because their status or text looks diagnostic; edit
calls now show their validated diff while pending; classified reads use
`read docs`, `read resource`, or `[skill] name`.

The pre-existing Goal 9 test encoded the wrong generic rule that every failed
tool result is red and every raw `Truncated` line is yellow.  It was replaced
with a baseline-derived independent assertion: the background still reflects
execution state, while raw foreground color remains tool-specific.  Structured
truncation rows are generated from result details and use `warning`; model-facing
tool result strings are untouched.

Deterministic verification after this batch:

```text
cadr test summary: systems=8 checks=11544 pass=11544 skip=0 fail=0
```

The presentation ledger now stands at `123 = 106 closed/aligned + 15 open + 2
intentional`.  No snapshot hash was changed in this batch; all existing full
screen and overlay snapshots passed byte-for-byte.

## Part C batch 2 — native transcript components

Skill invocations, branch summaries, and compaction summaries now use the same
collapsible custom-background composition as the baseline.  A shared entry
projection handles both restored history and live message-start events, so the
same skill envelope cannot render differently depending on when it appears.

| Contract | Baseline | Cadr implementation | Regression |
|---|---|---|---|
| skill envelope split | `agent-session.ts:115-139`; `interactive-mode.ts:3320-3346` | `src/cadr-cli/tui.lisp:1259-1351,1953-1985` emits a skill entry and optional trimmed user entry | `GOAL13-SKILL-BRANCH-AND-COMPACTION-TRANSCRIPTS-MATCH-BASELINE-COMPONENTS`; `GOAL13-STREAMING-SKILL-MESSAGE-USES-THE-SAME-SPLIT-TRANSCRIPT-PATH` |
| skill component | `skill-invocation-message.ts:11-52` | `src/cadr-cli/tui.lisp:2529-2563` | same component regression |
| branch/compaction components | `branch-summary-message.ts:10-56`; `compaction-summary-message.ts:10-57` | `src/cadr-cli/tui.lisp:1303-1320,2221-2243,2564-2615` | same component regression |
| global expand action | `interactive-mode.ts:3849-3868` expands every expandable transcript child | `src/cadr-cli/tui.lisp:3377-3397` updates tools, custom entries, skill entries, and summary entries together | same component regression |

The old flat values—an ordinary user block for a skill and `Compaction
summary: ...` for compaction—became exact `[skill]`, `[branch]`, and
`[compaction]` components with localized token grouping, `ctrl+o` hints,
Markdown-expanded bodies, and full-width `customMessageBg`.  Agent messages,
session serialization, and model context remain unchanged; only their TUI
projection changed.

The component regression also derives geometry independently from the baseline:
every custom transcript box is exactly full width with one top and bottom padding
row, while branch and compaction add exactly one internal spacer.  No SHA was
regenerated to bless the implementation.

Deterministic gate after this batch:

```text
cadr test summary: systems=8 checks=11562 pass=11562 skip=0 fail=0
```

## Part C batch 3 — selector path and timestamp formats

The session selector now applies the baseline's deliberately naive raw home
prefix replacement instead of a path-component boundary check.  The tree
selector now parses ISO timestamps, observes their UTC/offset suffix, projects
them into the display timezone, and selects `HH:MM`, `M/D HH:MM`, or
`YY/M/D HH:MM` from the same calendar rules as the baseline.

| Contract | Baseline | Cadr implementation | Regression |
|---|---|---|---|
| session path shortening | `session-selector.ts:26-33` | `src/cadr-cli/interactive-services.lisp:1288-1301` | `GOAL13-SESSION-PATH-AND-TREE-TIMESTAMPS-MATCH-BASELINE-DISPLAY-RULES` |
| tree label timestamp | `tree-selector.ts:854-877` | `src/cadr-cli/interactive-services.lisp:5311-5388` | same regression: today/current-year/older-year, UTC-to-local conversion, explicit offset, malformed fallback |

The red phase proved both old defects: a home-prefix sibling remained absolute,
and the timestamp formatter rejected the new calendar/zone contract.  The
focused regression is now `9/9`; the presentation ledger stands at `123 = 113
closed/aligned + 8 open + 2 intentional`.

```text
cadr test summary: systems=8 checks=11571 pass=11571 skip=0 fail=0
```

## Part C batch 4 — OAuth callback pages

The loopback callback now returns the baseline's complete responsive dark HTML
shell for both success and failure. Title, heading, message, and optional
details share one character-level escaper for `&<>"'`; UTF-8 content length and
connection-close framing remain byte-accurate.

| Contract | Baseline | Cadr implementation | Regression |
|---|---|---|---|
| page shell and semantic copy | `oauth-page.ts:1-109` | `src/cadr-ai/oauth.lisp:550-719` | `GOAL13-OAUTH-PAGES-MATCH-BASELINE-SHELL-COPY-AND-ESCAPING`; `GOAL13-OAUTH-HTTP-RESPONSE-KEEPS-BYTE-ACCURATE-HTML-FRAMING` |
| provider callback outcomes | `openai-codex.ts:340-363`; `anthropic.ts:118-145`; `radius.ts:176-202` | `src/cadr-ai/oauth.lisp:327-368,667-696,721-769` | `GOAL13-OAUTH-CALLBACK-COPY-DISTINGUISHES-EVERY-BASELINE-FAILURE` |

The parser's first two return values remain backward compatible; additional
reason/details values let the callback distinguish route, state, missing
parameters, provider denial, and internal failure without ever interpolating
the authorization code or state. Focused red/green proof is `36/36`. The
presentation ledger now stands at `123 = 117 closed/aligned + 4 open + 2
intentional`.

```text
cadr test summary: systems=8 checks=11607 pass=11607 skip=0 fail=0
```
