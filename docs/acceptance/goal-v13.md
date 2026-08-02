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

## Part C batch 5 — self-contained session export

Session export now uses the fixed baseline's complete responsive HTML
application.  The five template assets are loaded into `cadr-agent` before the
native image is saved; session JSON is UTF-8/Base64 encoded and inserted into
the template; interactive `/export` passes the active theme while the existing
two-argument exporter retains deterministic dark defaults.

| Contract | Baseline | Cadr implementation | Regression |
|---|---|---|---|
| Base64 session payload and exact tree | `core/export-html/index.ts:130-174` | `src/cadr-agent/session.lisp:2501-2546` | `SESSION-LIST-RESUME-AND-HTML-EXPORT-COVER-THE-ENTIRE-TREE`; `SESSION-V3-WRITES-REFERENCE-HEADER-AND-ALL-ENTRY-ENVELOPES`; `GOAL9-A2-SESSION-WORKFLOWS-ARE-DETERMINISTIC-AND-BRANCHES-STAY-ISOLATED` |
| complete responsive renderer | `export-html/template.html:1-56`; `template.css:1-819`; `template.js:1-1830` | exact assets under `src/cadr-agent/export-html/` | `SESSION-HTML-EXPORT-RENDERS-SKILL-WRAPPER-AS-VISIBLE-SIBLING-BLOCKS` |
| theme variables and export backgrounds | `core/export-html/index.ts:42-127,151-167` | `src/cadr-agent/session.lisp:2148-2499`; `src/cadr-cli/main.lisp:3293-3348` | `SESSION-HTML-EXPORT-RESOLVES-CUSTOM-THEME-AND-NEVER-REREADS-ASSETS`; `INTERACTIVE-EXPORT-FORWARDS-THE-ACTIVE-THEME-WITHOUT-CHANGING-THE-COMMAND-SURFACE` |
| licensed offline browser scripts | `core/export-html/index.ts:143-174` | `src/cadr-agent/session.lisp:2124-2143`; vendored asset bytes | `SESSION-HTML-EXPORT-VENDORS-LICENSED-OFFLINE-ASSETS-AND-PRESERVES-TWO-ARGUMENT-CALL` |

The licensed artifacts are byte-identical to the approved repository blobs:

| Artifact | Git blob | SHA-256 | Bytes | Header retained |
|---|---|---|---:|---|
| Marked 18.0.5 | `9d79575e45d0f6b88158097f5f4622ab938d76d9` | `d5487edc7258b404bfa74c393d74a6393155f02517bd5e7e77cd64f8187f39a0` | 42,882 | MIT copyright/license/source comment, exact bytes |
| Highlight.js 11.9.0 | `5d699ae6a4cfc9544a22a9ac394b01db2e5abd4f` | `837a6fa5b0c736b52bbde2b2b6190f305da3fc9ed41681db5321507057b5c846` | 121,727 | BSD-3-Clause copyright/license comment, exact bytes |

The offline assertion rejects every active external script, stylesheet, font,
image, fetch, XHR, WebSocket, EventSource, and worker import.  Preserved source
URLs inside license comments are inert and do not weaken the no-network
contract.

### Authorized assertion migration

The baseline encodes `JSON.stringify(sessionData)` as Base64
(`core/export-html/index.ts:159-160`), so plaintext searches encoded Cadr's old
server-rendered assumption rather than the baseline contract.  Only the two
authorized HTML assertion blocks changed:

| Test | Old assertion, verbatim | Migrated assertion | Why stronger |
|---|---|---|---|
| `SESSION-V3-WRITES-REFERENCE-HEADER-AND-ALL-ENTRY-ENVELOPES` | `(is (search "thinking_level_change" text))`; `(is (search "session_info" text))` | decode `session-data`; assert entry count; for every entry compare `id`, `parentId`, `type`, every message `role` and `content`, then recursively compare every JSON field | The old search neither decoded the payload nor tied a hit to an entry.  The new assertion rejects missing, reordered, reparented, changed, or extra entries and changed message data. |
| `GOAL9-A2-SESSION-WORKFLOWS-ARE-DETERMINISTIC-AND-BRANCHES-STAY-ISOLATED` | `(is (search "branch-a-user" html))`; `(is (search "branch-b-user" html))` | decode `session-data`; compare every exported entry field against `session-entry-to-json`, including IDs, parent links, message roles/content; then require both branch texts inside decoded message content | The old global substring could match renderer code or unrelated markup.  The new assertion proves both branches are present in the exported session graph with their exact envelopes. |

The first migrated run caught one assertion defect immediately: exact textual
JSON comparison treated numerically equal `0` and `0.0e0` as different.  The
final recursive comparison preserves numeric semantics while remaining exact
for object keys, array order, strings, booleans, nulls, IDs, and parents.

The presentation ledger is now `123 = 121 aligned/closed + 0 open + 2
intentional`.  No payload, wire event, session entry, ID, parent link, message,
or tool result changed.

### Mechanical verification

An isolated copy was built from the uncommitted Part C tree.  Its `build.sh`
ran all eight deterministic systems before saving the image:

```text
cadr test summary: systems=8 checks=11711 pass=11711 skip=0 fail=0
cadr build: SBCL lacks sb-core-compression; building an uncompressed image.
```

After the image was saved, the source asset directory was moved out of that
copy.  The built binary still exported a real persisted session without access
to the source assets:

```text
Exported to: /tmp/cadr-export-proof.FdwNkk/offline.html
binary_mtime=2026-08-02 22:28:00.273504039 +0800 binary_bytes=72460408
e8488100c23fc9656cd868a69ea46d2da11acc4ec7b8be2f9157b6f1d2c655eb  offline.html
```

The proof also asserted that the result contains the session-data marker and
both embedded browser libraries.  This demonstrates image self-containment;
it does not merely exercise the exporter while its source directory remains
available.

Implementation and regression commit: `07a9ff46f`.

## Part C2 — Common Lisp expression audit and rewrite

The audit covers all 135 production Lisp files and records the disposition of
each system across manual invariants, dispatch, boilerplate, condition handling,
representation, and repeated bug families in `docs/lisp-idiom-audit.md`.  It
rejects broad `case`→CLOS, `handler-case`→restart, struct→class, and selector
macro rewrites because those changes do not meet a C2-B reason.  Closed wire
tags and finite state machines remain explicit; open behavior already uses
generic protocols for components, terminals, storage, execution environments,
SDK objects, Radius presence, and RPC processes.

The one qualifying rewrite removes the obsolete server-rendered session HTML
implementation left behind by Part C.  Five unreachable helpers disappeared;
the live content formatter moved from the session-export area to its only
callers in compaction (`src/cadr-agent/compaction.lisp:116-163`).  The net delta
is 140 fewer physical lines (`159` removed, `19` relocated), with no replacement
abstraction.

The first full run exposed a mistaken audit assumption: the content formatter
was not dead; compaction referenced it from a later-loaded file.  That run
failed 12 compaction checks and was not accepted or rerun blindly.  Relocating
the unchanged function beside those callers fixed the root cause.  The next
complete deterministic run was:

```text
cadr test summary: systems=8 checks=11711 pass=11711 skip=0 fail=0
```

All session-export, compaction, payload/wire, base-screen, and overlay gates are
part of that run.  No snapshot hash, fixture, event, result text, or session
content changed.

Audit commit: `b5eead3ed`.  Rewrite commit: `44003ed90`.

### Part C corrective found by the Part D audit

The Part D semantic-color audit found that batch 5 passed explicit
`pageBg/cardBg/infoBg` into the three template placeholders but omitted the
baseline's additional `--exportPageBg`, `--exportCardBg`, and `--exportInfoBg`
declarations from `THEME_VARS` (`core/export-html/index.ts:108-127`).  This was a
real visible HTML/CSS contract gap, not a documentation-only issue.

The new regression first failed on all three missing declarations.  It now
uses three distinct explicit values and proves both routes:

- the agent exporter emits all six baseline declarations (`--export*` plus
  `--body-bg/--container-bg/--info-bg`);
- interactive `/export` forwards all three active-theme values through the
  production command path.

The fixed template has no `var(--info-bg)` consumer.  That is also true of the
fixed baseline, so the gate explicitly preserves non-consumption instead of
inventing an information-card use.  The three first-party template assets are
now SHA-256 locked alongside Marked and Highlight.js:

```text
template.html 916782b1184a9597527605ad751e2b3af30fcea23ba2194002969cd217a06881
template.css  28c16e3827c23a62eef8283cac316b478f946e023093adad25ff9c9b891d41af
template.js   1893cdb77587f592eef5717905391269886d6d7a4dc6a488417a73da374d9226
```

Corrective commit: `370677dd7`.

```text
cadr test summary: systems=8 checks=11723 pass=11723 skip=0 fail=0
```

## Part C3 — interaction latency target

The pre-change `cd94d0b01` benchmark reproduced the reported long-session
stall: the 5000-entry mixed mouse/wheel trace had median/p95/p99
`36.000/48.001/52.001ms` and allocated 2,847,360 bytes per event. Existing
11,723 deterministic checks did not catch it because functional and full-screen
snapshot tests assert output, not cost; the performance gate allowed a 150ms
stress p99, mixed mouse and wheel into one trace, had no continuous editor-key
trace, and had no real-session scale tier.

The implementation keeps one generation of alternate-screen preparation and
reuses the maximal identity-stable prefix at the same width
(`src/cadr-tui/renderer.lisp:251-254,1424-1478,1544-1545`). Only the dirty
suffix repeats OSC-133 stripping, visible-width measurement, and clipping. It
does not prune the logical document: selection, OSC-52 copy, viewport image
cropping, and alternate-screen exit still see the updated complete document.

| Requirement | Source | Regression |
|---|---|---|
| prefix reuse plus suffix/width invalidation | `src/cadr-tui/renderer.lisp:1436-1478` | `GOAL13-ALT-SCREEN-REUSES-ONLY-THE-UNCHANGED-PREPARED-PREFIX` (`test/cadr-tui/alt-screen-test.lisp:146`) |
| complete-document selection/exit contract | `src/cadr-tui/renderer.lisp:1544-1555` | `GOAL13-ALT-SCREEN-PREPARED-CACHE-KEEPS-THE-FULL-DOCUMENT-CONTRACT` (`test/cadr-tui/alt-screen-test.lisp:198`) |
| anonymous real-session tiers | `scripts/goal13-session-scale-profile.py` | `ContinuousInputGateTest.test_session_scale_profile_is_aggregate_only_and_follows_active_path` |
| split mouse/wheel/editor traces | `scripts/goal11-bench.lisp:604-704` | `ContinuousInputGateTest.test_common_tier_absolute_contract_is_separate_and_exact` |
| p99 ≤16ms and distinct failure classes | `scripts/goal11-performance-gate.py:26,415-529` | same Python contract test plus `GOAL11-CONTINUOUS-ALT-INPUT-BENCHMARKS-ARE-RELEASE-GATED` |

The privacy-safe profile consumed all 45 local sessions, including ten older
files whose root link is stored as `parentId:false`: p50=5, p95=58, p99/max=96.
It emits no file name, ID, path, timestamp, provider/model, or content. The
checked tiers are typical=5, common=58, heavy=96, stress=5000.

Final common-tier p99 is 4.001ms mouse, 4.000ms wheel, and 4.001ms editor key.
The N=5000 stress p99 is 8.000ms, a 6.5× improvement, and median allocation is
887,248 bytes/event, a 3.2× improvement. The goal is met rather than closed by
an “acceptable limit” exception. Full before/after evidence and raw samples are
recorded in `docs/performance.md` and `docs/benchmarks/goal-v13-c3-*.json`.

Implementation commit: `7da79c376`. Evidence commit: `d84e0ea75`.

## Part D — presentation and ledger gates

The semantic-color gate uses 55 unique truecolor sentinels. Every sentinel must
appear inside the intended production-rendered marker from real selector,
transcript, tool, Markdown, syntax, editor, or HTML-export paths; equal built-in
theme values cannot hide a wrong token assignment. The test-owned key list must
also equal the production theme key set exactly.

Its first run found three red assertions. All three were test-model defects,
not product gaps: `selectedBg` had been probed through the generic select-list
instead of the real session selector, while added/removed diff markers crossed
word-level inverse ANSI spans. The probes were corrected to the baseline
surfaces; no production file changed. The final named gate is 62/62:
`GOAL13-ALL-SEMANTIC-THEME-KEYS-DRIVE-PRODUCTION-RENDERERS`
(`test/cadr-cli/goal13-presentation-test.lisp:544`).

The four independent axes are now stated consistently in `README.md`,
`docs/README.md`, `docs/architecture.md`, `docs/parity-map.md`,
`docs/source-parity.md`, `docs/performance.md`, and
`docs/presentation-parity.md`. The examples manifest is explicitly an auxiliary
inventory, not a fifth ledger. `GOAL13_PRESENTATION_LEDGER` records
`B1/B2/B3/B4=55/52/10/6` and `123=121 aligned+0 pending+2 intentional`.
`GOAL13-FOUR-LEDGERS-AND-PRESENTATION-DENOMINATORS-STAY-IN-SYNC`
(`test/cadr-cli/goal13-presentation-test.lisp:966`) recounts the real table rows
and rejects missing cross-links or obsolete three-ledger wording; it is 33/33.

No Goal 13 change regenerated a base-screen or overlay SHA. The pre-existing
13 base-screen and 15 overlay snapshot sets retain their separate
baseline-derived semantic oracles, so this work proves unchanged bytes without
using a snapshot generated from the new implementation as its own correctness
oracle.

Part D commit: `b677557b9`.

## Mechanical acceptance and live verification

The final deterministic suite is exact and complete:

```text
cadr test summary: systems=8 checks=11849 pass=11849 skip=0 fail=0
```

`./scripts/verify.sh` completed with every release gate passing:

```text
Deterministic stages
Stage                                            Result
root cadr binary freshness                       PASS
real source parity ledger                        PASS
source parity drift self-test                    PASS
deterministic FiveAM                             PASS
isolated cadr build                              PASS
isolated cadr-server build                       PASS
Goal 11 performance and stability gate           PASS
native acceptance smoke                          PASS
native process modes                             PASS
migration PTY smoke                              PASS
Unix socket server smoke                         PASS
terminal lifecycle PTY                           PASS
deterministic TUI harness                        PASS

Live stages
Stage                                            Result
credential-gated FiveAM                          PASS
DeepSeek live TUI                                PASS
```

After the user replenished the OpenAI allowance, the requested live route was
locked to `openai-codex/gpt-5.6-luna` with `thinking=max`. A direct root-binary
diagnostic returned `OAUTH_LUNA_MAX_OK`, and the complete credential-gated run
reported:

```text
Items: 8, run: 7, pass: 7, skip: 1, fail: 0
Checks: 32, pass: 31, skip: 1, fail: 0
```

The sole skip is the baseline-equivalent Anthropic credential gate because
`ANTHROPIC_API_KEY` is absent. DeepSeek and both OpenAI OAuth paths ran; this is
not a skip-based OpenAI result. The earlier OpenAI failure was a real HTTP 429
`usage_limit_reached`, not a product or assertion defect. No production source
was changed to accommodate it. The live-gate update is commit `1b407bf81`.

The delivered root binary is newer than both the last source commit and source
mtime:

```text
binary build time: 2026-08-02 23:10:33.873096648 +0800
latest src commit: 7da79c376c345e2b896821de2a25a621befb79a6 2026-08-02T23:03:11+08:00
latest source mtime: 2026-08-02 22:48:28.922337273 +0800 src/cadr-tui/renderer.lisp
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
root binary freshness: PASS
```

All mechanical Goal 13 criteria are satisfied and committed. The remaining
acceptance item is Goal 13 section 5.6: only the user can close the real-terminal
A/B comparison against the baseline. The four-ledger automation deliberately
does not claim to replace that check.
