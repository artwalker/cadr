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

The current presentation ledger is `123 = 119 aligned/closed + 0 open + 4
intentional`; the two later intentional rows are the approved Cadr brand mark
and global selector boundary wrap.  No payload, wire event, session entry, ID,
parent link, message,
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
`B1/B2/B3/B4=55/52/10/6` and `123=119 aligned+0 pending+4 intentional`.
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
binary build time: 2026-08-02 23:42:15.103484835 +0800
latest src commit: 7da79c376c345e2b896821de2a25a621befb79a6 2026-08-02T23:03:11+08:00
latest source mtime: 2026-08-02 22:48:28.922337273 +0800 src/cadr-tui/renderer.lisp
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
root binary freshness: PASS
```

This was the Part D checkpoint. The real-terminal A/B remained the final
authority and subsequently found the corrective work below; the four-ledger
automation deliberately does not claim to replace that check.

## Third real-terminal A/B corrective — 2026-08-03

The third A/B closed five observable gaps and extended C3 for the reported
long-run interaction pause. Each product change has a regression that
reproduces the old failure rather than checking only an adjacent helper.

| Finding | Fixed-baseline evidence | Cadr implementation | Regression |
|---|---|---|---|
| relative read exposed `#P"..." is not a string designator` | path resolution expands `~`, resolves against cwd and returns a normalized string (`core/tools/path-utils.ts:40-53,83-89`); read then accesses and reads that string (`core/tools/read.ts:236-267`) | lexical `.`/`..` normalization and `~` expansion are shared by every file tool; presentation fallback converts pathnames to namestrings and contains classification failures (`src/cadr-cli/tools/path.lisp:44-79,247-260`; `src/cadr-cli/tui.lisp:1637-1691`) | `GOAL13-RELATIVE-READ-EXPANDS-A-SHORTENED-HOME-CWD-BEFORE-RESOLVING`; `GOAL13-FILE-TOOL-ERRORS-NEVER-LEAK-COMMON-LISP-REPRESENTATIONS`; `GOAL13-FILE-IO-FAILURES-USE-STABLE-TOOL-LEVEL-COPY` |
| built-in `/login` had no manual callback fallback | dialog title and URL/instruction/input composition (`login-dialog.ts:41-48,93-148`); OpenAI races loopback callback against `manual_code` input (`openai-codex.ts:444-480`) | code, query, `code#state`, and full redirect URL parse through one function; callback and manual worker race under a cancellation signal; the TUI renders the exact title, warning, message, input and cancel hint (`src/cadr-ai/oauth.lisp:327-356,814-905,914-955`; `src/cadr-cli/tui.lisp:115-213,4923-4932`) | `GOAL13-MANUAL-OAUTH-INPUT-MATCHES-BASELINE-URL-CODE-AND-STATE-FORMS`; `GOAL13-CALLBACK-AND-MANUAL-OAUTH-INPUT-RACE-CANCELS-THE-LOSER`; `GOAL13-BUILT-IN-OAUTH-DIALOG-MATCHES-THE-BASELINE-MANUAL-FALLBACK`; `GOAL13-LOGIN-COMMAND-FORWARDS-THE-MANUAL-AUTHORIZATION-PROMPT` |
| `/export` used weak copy and `<session-id>.html` | exporter defaults to `${APP_NAME}-session-${session-file-basename}.html` (`core/export-html/index.ts:274-280`); interactive status is `Session exported to: ${filePath}` (`interactive-mode.ts:5471-5481`) | default name is `cadr-session-<ISO timestamp with :/. replaced by ->_<session UUID>.html`; the notice uses the returned bare filename, as confirmed by real baseline A/B (`src/cadr-cli/main.lisp:1331-1345,1546-1560`) | `GOAL13-DEFAULT-HTML-EXPORT-NAME-AND-STATUS-MATCH-THE-BASELINE-RULE`; the older workflow assertion now requires the exact basename rather than the ambiguous word `Exported` |
| OAuth result page reused pi's mark | fixed page uses one 800×800 monochrome grid SVG (`auth/oauth/oauth-page.ts:1-17`) | one white even-odd path now draws two adjacent cons cells and a rightward notch on the same 117.36-step grid, with no stroke, gradient, second path, or pi geometry (`src/cadr-ai/oauth.lisp:579-581`) | `GOAL13-OAUTH-PAGE-USES-CADR-OWNED-GRID-CONS-CELL-MARK` plus the existing complete HTML/framing/escaping gate |
| clean TUI exit omitted the resume command | only TTY, persisted, existing-file sessions qualify; custom session directories are quoted and added before `--session <id>` (`interactive-mode.ts:236-249`); clean `/quit`, Ctrl+D and Ctrl+C paths write after terminal teardown (`interactive-mode.ts:3622-3634`) | normal, Ctrl+C, and suspend/resume exits print exactly one dim `To resume this session: cadr ...` after terminal restoration; SIGTERM/SIGHUP non-local exits bypass the write; `--session` accepts the emitted full/partial ID as well as a path (`src/cadr-cli/main.lisp:124-147,1563-1582,4320-4331`; `src/cadr-cli/utilities.lisp:445-477`) | `GOAL13-SESSION-IDS-AND-POST-TUI-RESUME-COPY-MATCH-THE-BASELINE`; `goal9-a2-pty.sh` covers normal, Ctrl+C, and suspend/resume ordering and command shape |

### File-tool error-channel audit

The root defect crossed two layers: a cwd abbreviated with `~` was merged with
`..` without lexical normalization, then the read-title resource classifier
passed a pathname object to a string operation. The classifier now cannot tear
down the TUI, but that containment is not used to hide a broken executor. The
executor resolves the same canonical path and maps filesystem/stream/type
conditions to stable tool-level copy.

| Tool | Product boundary | Missing-path/result contract |
|---|---|---|
| read | `src/cadr-cli/tools/read.lisp:18-48,132-142` | `File not found: <input>`; other file/decoding failures become `Could not read file: <input>` |
| write | `src/cadr-cli/tools/write.lisp:27-56` | parent creation and atomic write remain unchanged; I/O failure becomes `Could not write file: <input>` |
| edit | `src/cadr-cli/tools/edit.lisp:550-684` | baseline ENOENT copy is preserved; read/write failures become `Could not edit file: <input>` |
| find | `src/cadr-cli/tools/find.lisp:86-94` | existing `Path not found: <absolute path>` remains exact; implementation conditions are contained |
| grep | `src/cadr-cli/tools/grep.lisp:155-163` | same search-path boundary and copy |
| glob | `src/cadr-cli/tools/glob.lisp:163-181,206-214` | missing bases now fail explicitly instead of being mistaken for an empty match set |
| ls | `src/cadr-cli/tools/ls.lisp:87-95` | existing `Path not found: <absolute path>` remains exact; directory I/O is contained |

The two negative regressions reject `#P"`, `not a string designator`,
`SIMPLE-ARRAY`, and `SB-` in every tool error. This closes the same
implementation-diagnostic family as the earlier setsid, ASDF, and TLS leaks.

### Sustained C3 interaction gate

The former C3 benchmark measured isolated events and 1024-event bursts. It
could not reproduce a pause that appears only after repeated drag, wheel and
editing activity. The new release gate drives the production input/render path
for 180 real-time seconds at 60Hz: 10,800 events, exactly 2,700 each of drag,
wheel-up, wheel-down and alternating editor insert/backspace. It records every
event latency, p99.9, maximum, GC-affected event latency, runtime GC duration
and frequency, ten-second heap/RSS samples, and retained state after a final
full collection (`scripts/goal11-bench.lisp:729-976`). The checker recomputes
all summaries from raw vectors and rejects a short or internally inconsistent
trace (`scripts/goal11-performance-gate.py:531-713`).

The checked three-minute run is
`docs/benchmarks/goal-v13-c3-final.json`, SHA-256
`96350ee3588e0143d745b1af2f0c295f542b5c6c0c31693b65710dcea0ed11f6`:

```text
duration/events:       180.001004s / 10,800
p99.9 / max:           8.000ms / 20.001ms
GC-affected events:    91 (max wall latency 20.001ms)
GC runtime p99.9/max:  15.491ms / 15.491ms
GC total/frequency:    167.196ms / 30.333 per minute
raw final-30s growth:  heap +19,924,288 B; RSS +2,097,152 B
post-full-GC growth:   retained heap +241,520 B; RSS +581,632 B
convergence:           PASS (both retained values <= 8 MiB)
```

The raw final-window heap number is reported rather than hidden; it is the
normal nursery phase. Convergence is decided independently from post-full-GC
retained heap and RSS. `sb-ext:*gc-run-time*` is labelled as a runtime counter,
not falsely presented as a separately sampled stop-the-world wall clock.

### Output-channel completeness

The earlier presentation audit enumerated TUI elements. That was structurally
unable to find post-alternate-screen stdout. `docs/presentation-parity.md` now
enumerates the finite external-channel set instead: active TUI, pre-TUI and
post-TUI streams, print/JSON/RPC, session/export/auth/settings/package/SQLite
files, provider requests, OAuth callback pages, Unix-socket and server streams,
eval artifacts, and exit status. Its machine identity is
The third-round checkpoint was
`GOAL13_OUTPUT_CHANNELS total=17 covered=17 pending=0`; every row named the
fixed-baseline source, Cadr source, and a gate that drives the real channel.
`GOAL13-FOUR-LEDGERS-AND-PRESENTATION-DENOMINATORS-STAY-IN-SYNC` rejects a
missing row or channel class. The fourth round below adds abnormal termination
as C-18 and audits the exceptional path of every channel rather than silently
assuming the normal-path gate covers it.

This closes the four-axis escape for a concrete reason: source parity saw the
functions but not the missing lifecycle call; TUI snapshots end before the
resume bytes; tool tests used pathname-free cwd strings; and C3 measured only
short traces. The new gates exercise the actual path object, callback/manual
race, post-teardown PTY bytes, and three-minute mixed event stream. The two
OAuth page rows are now correctly classified as user-approved Cadr branding,
so the current presentation identity is
`123 = 119 aligned/closed + 0 open + 4 intentional`.

Implementation commits: `82d0b41bb`, `07463db44`, `829ec7f5c`.

### Corrective mechanical acceptance

The direct deterministic run and the identical run inside `verify.sh` both
accounted for all eight systems:

```text
cadr test summary: systems=8 checks=11949 pass=11949 skip=0 fail=0
```

The complete release gate passed every stage; no failed stage was retried:

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

The credential-gated report was complete rather than collapsed to a pass/fail
label:

```text
Items: 8, run: 7, pass: 7, skip: 1, fail: 0
Checks: 32, pass: 31, skip: 1, fail: 0
```

The seven run items were the DeepSeek provider stream, DeepSeek print mode,
OpenAI Codex explicit-model OAuth, DeepSeek eval, OpenAI Codex eval, DeepSeek
self-extension, and DeepSeek repository fail/fix/pass loop. The only skipped
item was Anthropic streaming because `ANTHROPIC_API_KEY` is not set. The live
TUI harness also passed autocomplete, undo, kill-ring, a real DeepSeek two-turn
edit, resize, CJK, and terminal restoration.

The delivery binary was rebuilt after the last source change and checked before
the release gate:

```text
binary build time: 2026-08-03 01:47:44.738192956 +0800
latest src commit: 82d0b41bbb3538c361cbad279d9982bc659b84b5 2026-08-03T01:40:28+08:00
latest source mtime: 2026-08-03 01:38:02.342514692 +0800 src/cadr-cli/tools/path.lisp
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
root binary freshness: PASS
```

The installed SBCL has no `sb-core-compression`; both root and isolated builds
therefore exercised the approved uncompressed-image fallback and succeeded.
`git diff --check` passed. A production-source grep found no leaked `not a
string designator` copy; pathname literals remain only for intentional system
paths such as `/dev/urandom` and `/proc/version`, never as user-facing
conditions.

Corrective commits: `82d0b41bb`, `07463db44`, `829ec7f5c`, `484e5c5a7`.

## Fourth real-terminal A/B corrective — 2026-08-03

This round closed the only runtime channel that could dump arbitrary in-memory
state, made shutdown finite even when a worker does not cooperate, and wired
OAuth dialog cancellation through to the listener rather than stopping at the
overlay boundary.

| Finding | Fixed-baseline evidence | Cadr implementation | Regression |
|---|---|---|---|
| an unhandled SBCL condition dumped the complete stack and session graph | pi restores the terminal and handles `uncaughtException` at the process boundary (`interactive-mode.ts:3646-3673,3716-3721`) | the shared native entrypoint boundary captures before stack unwind, emits only type/bounded copy, exact- and pattern-redacts a private mode-0600 log, and is installed by `cadr`, `cadr-server`, and `cadr-evals` (`src/cadr-ai/crash.lisp`; `src/cadr-cli/crash.lisp`; all three entrypoints) | `GOAL13-FATAL-CONDITION-BOUNDARY-REDACTS-USER-OUTPUT-AND-CRASH-LOG`; `GOAL13-INTERACTIVE-INTERRUPT-USES-THE-SANITIZED-FATAL-PATH` |
| credential objects had default recursive printers | a JavaScript `Error` does not recursively print unrelated object fields; Cadr needs an explicit Lisp defense | model/provider/request/auth/config/runtime/client and Radius credential holders now print identity metadata plus `[REDACTED]`, never secret slots | `GOAL13-CREDENTIAL-BEARING-OBJECTS-NEVER-PRINT-SECRET-MATERIAL`; `GOAL13-CLI-CONFIGURATION-OBJECTS-NEVER-PRINT-SECRET-MATERIAL`; `GOAL13-RADIUS-PRESENCE-NEVER-PRINTS-ITS-BEARER-TOKEN` |
| cleanup used unbounded joins | baseline async cleanup can cancel work without blocking the event loop indefinitely | one bounded cleanup primitive covers AI abort watchers, TUI workers/loaders/monitors, autocomplete, file/footer watchers and animated components; the server listener uses the same 500ms bound and forced-stop policy | `GOAL13-CLEANUP-NEVER-BLOCKS-ON-AN-UNRESPONSIVE-THREAD`; `GOAL13-TUI-EXIT-COMPLETES-WHEN-THE-ACTIVE-WORKER-IGNORES-ABORT` |
| Esc closed OAuth UI but left callback/manual work alive | `LoginDialogComponent.cancel()` aborts the shared signal, rejects pending input and completes with `Login cancelled` (`login-dialog.ts:83-90`) | the prompt now carries distinct cancel and cancelled-p callbacks; Esc invokes cancel, both workers observe it, bounded cleanup joins them, the loopback socket unwinds closed, and Working disappears | `GOAL13-RUNTIME-OAUTH-INPUT-CANCEL-INVOKES-THE-PROVIDER-CANCELLATION`; `GOAL13-EVERY-BUILT-IN-OAUTH-DIALOG-CANCEL-CLEARS-WORKING-AND-RESTORES-EDITOR`; both OAuth listener tests |
| abnormal termination was absent from the channel ledger | baseline has a distinct last-resort output path outside normal TUI/stdout elements | C-18 records runtime-fatal output and an 18-row exceptional-path matrix makes every normal channel state its failure behavior and gate | `GOAL13-FOUR-LEDGERS-AND-PRESENTATION-DENOMINATORS-STAY-IN-SYNC` requires 18 normal and 18 exceptional rows |
| `/export` notice was too long | real baseline A/B shows the returned relative filename | `Session exported to:` now receives `file-namestring`, while the file target itself remains unchanged | `GOAL13-DEFAULT-HTML-EXPORT-NAME-AND-STATUS-MATCH-THE-BASELINE-RULE` |
| interim Cadr mark was a block C | the baseline visual method is one white even-odd path on the 800-square grid (`auth/oauth/oauth-page.ts:1-17`) | the same method now depicts two adjacent cons cells with a rightward notch; it uses one path, no stroke/rounding/gradient and the 117.36 grid | `GOAL13-OAUTH-PAGE-USES-CADR-OWNED-GRID-CONS-CELL-MARK` |

### Credential and cleanup coverage

The printer audit covers `model`, `model-metadata`, `image-model`, every
provider instance, `request-spec`, API-key/OAuth credentials, memory/file
credential stores, auth results/refresh contexts/model runtimes, CLI arguments,
provider config, API-key/manual-auth input state, model registry, llama.cpp and
Hugging Face clients, and Radius presence. The fatal redactor additionally
collects command-line keys, all stored auth key/access/refresh values, every
registered provider environment variable, cloud credential variables and
Radius auth before writing the log.

The cleanup audit found no remaining unbounded join in a teardown path. The
execution-environment stdout/stderr collectors now use the same bounded stop;
bash reader joins either carry an explicit one-second timeout or occur only
after `thread-alive-p` is false. The sole production raw join left in
`cadr-agent/loop.lisp` is the deliberate synchronization point of an active
parallel tool batch, not a shutdown wait. Tests use joins only to observe their
own deterministic workers.

The cons mark remains crisp at the callback page's 72px size. At favicon scale
the shared middle border and directional notch read more like a compact cell
pair than a detailed textbook pointer; preserving the single grid path and
recognizable two-cell silhouette was chosen over adding off-grid micro-detail.

### Why 11,949 checks missed it

The suite tested handled conditions, modeled transport failures, TUI frames,
and successful cooperative teardown. It never drove an uncaught
`serious-condition` through the saved-image toplevel, never placed a secret in
a printed runtime structure, and never supplied a worker that ignored abort.
The OAuth dialog test stopped at overlay cancellation while the callback/manual
race tests cancelled only the losing internal worker; neither connected Esc to
the provider cancellation signal. Finally, the output-channel ledger had only
normal-path rows, so a runtime's own post-crash printing was outside its
enumeration by construction. The new tests drive those exact boundaries rather
than infer them from nearby helpers.

### Mechanical acceptance

The implementation is recorded in `df92b32d320ae28f61079f8f289735617d079cea`.
The direct deterministic run and the isolated deterministic run inside the
release gate both reported:

```text
cadr test summary: systems=8 checks=12056 pass=12056 skip=0 fail=0
```

The complete release gate passed without retrying a failed stage:

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

The credential-gated report preserved item-level outcomes:

```text
PASS LIVE-DEEPSEEK-CHAT-COMPLETIONS-STREAMS (5 checks)
SKIP LIVE-ANTHROPIC-STREAM-PRESERVES-TWO-TURN-CONTEXT: ANTHROPIC_API_KEY is not set
PASS LIVE-DEEPSEEK-PRINT-MODE-EMITS-ONLY-FINAL-TEXT (3 checks)
PASS LIVE-OPENAI-CODEX-EXPLICIT-MODEL-USES-OAUTH-CREDENTIAL (4 checks)
PASS LIVE-DEEPSEEK-EVAL-SMOKE (4 checks)
PASS LIVE-OPENAI-CODEX-EVAL-SMOKE-USES-EXPLICIT-MODEL-AND-REAL-OAUTH (4 checks)
PASS LIVE-DEEPSEEK-SELF-EXTENSION-WRITE-RELOAD-AND-INVOKE (6 checks)
PASS LIVE-DEEPSEEK-REPOSITORY-FAIL-FIX-PASS-LOOP (5 checks)
Items: 8, run: 7, pass: 7, skip: 1, fail: 0
Checks: 32, pass: 31, skip: 1, fail: 0
```

The root image was rebuilt after the implementation commit and passed the
freshness gate:

```text
binary build time: 2026-08-03 10:41:15.994322992 +0800
latest src commit: df92b32d320ae28f61079f8f289735617d079cea 2026-08-03T10:38:29+08:00
latest source mtime: 2026-08-03 10:34:35.370665755 +0800 src/cadr-agent/execution-env.lisp
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
root binary freshness: PASS
```

The installed SBCL lacks `sb-core-compression`; root and isolated builds both
used the approved uncompressed-image fallback and succeeded.

## Fifth real-terminal A/B corrective — 2026-08-03

This round separates the agent lifecycle from generic local-command work,
makes OAuth cancellation an explicit non-error outcome, and moves OAuth
presentation constants from shared UI code into each provider definition.

| Finding | Fixed-baseline evidence | Cadr implementation | Regression |
|---|---|---|---|
| `/login` and `/export` displayed `Working...` | every built-in command dispatches locally (`interactive-mode.ts:2691-2823`); the working indicator is installed only on `agent_start` (`interactive-mode.ts:2880-2917`) | generic command-worker `busy-p` still prevents concurrent editor submission, but the new `agent-working-p` changes only on `:agent-start`/`:agent-settled` and alone controls the spinner (`src/cadr-cli/tui.lisp:73,1995-2022,4453-4470,4602-4621`) | `GOAL13-BASELINE-BUILT-IN-SLASH-WORKING-MATRIX-IS-COMPLETE`; `GOAL13-LOCAL-SLASH-WORKER-NEVER-RENDERS-AGENT-WORKING-INDICATOR`; `GOAL13-AGENT-LIFECYCLE-ALONE-CONTROLS-WORKING-INDICATOR` |
| Esc from OAuth rendered `Error: Login cancelled` | login-dialog cancellation aborts the flow, while both API-key and OAuth consumers deliberately suppress the exact cancellation outcome (`login-dialog.ts:83-90`; `interactive-mode.ts:5240-5250,5350-5360`) | every runtime prompt maps NIL to typed `authentication-cancelled`; the TUI command boundary suppresses only that type, while prompt/transport/auth failures remain `authentication-error` (`src/cadr-ai/oauth.lisp:843-924`; `src/cadr-cli/tui.lisp:3774-3785`) | `GOAL13-EVERY-RUNTIME-AUTH-PROMPT-CANCELLATION-IS-TYPED`; `GOAL13-EVERY-BUILT-IN-OAUTH-DIALOG-CANCEL-CLEARS-WORKING-AND-RESTORES-EDITOR`; `GOAL13-OAUTH-PROMPT-FAILURES-ARE-NOT-MISCLASSIFIED-AS-CANCELLATION` |
| OAuth instructions were shared and titles used method marketing names | provider modules own provider name, auth-method name, optional `loginLabel`, `auth_url` instructions, and prompt copy (`providers/*.ts`; `auth/oauth/*.ts`) | `oauth-provider-metadata` travels through provider definitions and session-local runtime projection; dialogs use provider names, selectors use method names/login labels, and each flow emits its own instructions (`src/cadr-ai/oauth.lisp:3-30,960-1057`; `src/cadr-ai/oauth-flows.lisp:19-50,417-458,578-606`; `src/cadr-ai/registry.lisp:3-15,28-266,715-760`) | `GOAL13-OAUTH-PRESENTATION-METADATA-IS-OWNED-BY-EACH-PROVIDER`; `GOAL13-BUILT-IN-OAUTH-PROMPTS-USE-PROVIDER-OWNED-BASELINE-COPY`; `GOAL13-BUILT-IN-OAUTH-DIALOG-MATCHES-THE-BASELINE-MANUAL-FALLBACK` |

### Complete built-in slash-command working audit

The fixed baseline has exactly 22 public built-ins
(`core/slash-commands.ts:19-42`). All route through the local submit dispatcher
before any ordinary prompt can reach the agent (`interactive-mode.ts:2691-2823`).
Therefore none of them creates the agent `Working...` state.

| Command | Baseline action | Agent `Working...` |
|---|---|---|
| `/settings` | local selector | No |
| `/model` | local selector/model reload | No |
| `/scoped-models` | local selector | No |
| `/export` | local file export | No |
| `/import` | local file/confirmation flow | No |
| `/share` | local GitHub operation | No |
| `/copy` | local clipboard operation | No |
| `/name` | local session metadata update | No |
| `/session` | local session-information notice | No |
| `/changelog` | local overlay | No |
| `/hotkeys` | local overlay | No |
| `/fork` | local session selector/fork | No |
| `/clone` | local session clone | No |
| `/tree` | local tree selector | No |
| `/trust` | local trust selector/write | No |
| `/login` | local auth selector/dialog and provider auth flow | No |
| `/logout` | local auth selector/store update | No |
| `/new` | local session creation | No |
| `/compact` | compaction flow with its distinct `Compacting context...` state | No |
| `/resume` | local session selector/load | No |
| `/reload` | local configuration/extension reload | No |
| `/quit` | local shutdown | No |

Prompt commands and skill commands acquire `Working...` only after they submit
a prompt and the session emits `agent_start`. An extension command likewise has
no working state merely because it is a command; it gains one only if it calls
the prompt API. `!`/`!!` shell commands use their own local execution state and
never impersonate agent reasoning. The regression recounts the production
autocomplete command specification, so adding a twenty-third built-in without
an explicit disposition fails the gate.

### Cancellation audit

| User action | Baseline outcome | Cadr outcome after this corrective |
|---|---|---|
| cancel OAuth dialog, API-key entry, auth select/text/secret/manual-code prompt | restore the editor silently; `Login cancelled` is control flow, not a rendered error | typed `authentication-cancelled`, silently consumed at the interactive boundary |
| cancel an ordinary overlay/selector | return to the editor without an error notice | NIL/`:cancel`, no error notice |
| cancel session import confirmation | deliberate informational `Import cancelled`, never an error | same informational status (`src/cadr-cli/tui.lisp:5735`) |
| abort an active agent/tool operation | render `Operation aborted` | same; this is operational abort, not dialog cancellation |
| cancel extension UI input/select/confirm | resolve NIL/cancel to the extension | same, without synthesizing a product error |

The typed boundary matters: matching the string `Login cancelled` would also
hide a genuine provider or bridge failure which happened to reuse that text.
`GOAL13-OAUTH-PROMPT-FAILURES-ARE-NOT-MISCLASSIFIED-AS-CANCELLATION` forces a
real bridge failure through the visible authentication-error path.

### Provider-owned OAuth presentation matrix

| Provider | Provider/dialog name | Auth-method name | Login label | Provider-authored browser copy |
|---|---|---|---|---|
| Anthropic | `Anthropic` | `Anthropic (Claude Pro/Max)` | default account label | `Complete login in your browser. If the browser is on another machine, paste the final redirect URL here.` |
| GitHub Copilot | `GitHub Copilot` | `GitHub Copilot` | default account label | device flow; no `auth_url` override |
| Kimi For Coding | `Kimi For Coding` | `Kimi Code (subscription)` | `Sign in with Kimi Code` | device flow; no `auth_url` override |
| OpenAI Codex | `OpenAI Codex` | `OpenAI (ChatGPT Plus/Pro)` | default account label | `A browser window should open. Complete login to finish.` |
| OpenRouter | `OpenRouter` | `OpenRouter OAuth` | `Sign in with OpenRouter` | `Complete sign-in in your browser. If the browser is on another machine, paste the final redirect URL here.` |
| Radius | `Radius` | `Radius` | default account label | `Continue in your browser.` |
| xAI | `xAI` | `xAI (Grok/X subscription)` | `Sign in with SuperGrok or X Premium` | device flow; no `auth_url` override |

This is a data-ownership correction, not a provider-specific conditional pile.
The provider definition owns immutable presentation metadata and the runtime
projects it session-locally. Goal 14 can split provider implementations into
one file per provider without changing selector or dialog consumers: each
provider moves together with its protocol, auth flow, and presentation data.

### Auth-option partition alignment

The user approved the missing baseline partition as capability parity, not a
Cadr-specific mechanism. The implementation now uses one cardinality rule for
built-in and session-local providers:

| Provider/path | Baseline | Cadr after alignment |
|---|---|---|
| provider has no login methods | `No login methods available.` (`interactive-mode.ts:5001-5004`) | exact status text; no empty selector |
| provider has exactly one method | immediately starts that method (`interactive-mode.ts:5006-5011`) | same; no extra menu |
| provider has OAuth and API-key methods | `Select authentication method for <provider>:`; OAuth uses provider `loginLabel` or the account fallback, API key uses the fixed label (`interactive-mode.ts:4984-5039`) | same provider-owned metadata and ordering; no provider-specific conditional pile |
| OpenAI Codex OAuth | inner `Browser login (default)` / `Device code login (headless)` selector, then the chosen flow (`openai-codex.ts:510-530`) | same runtime prompt; device authorization, polling, cancellation, code exchange, and canonical `openai-codex` persistence are wired end to end |
| provider selector cancel after generic auth-type selection | returns to `Select authentication method:` | same nested-selector return path |

Red-first regressions are
`GOAL13-PROVIDER-SPECIFIC-LOGIN-METHOD-SELECTOR-USES-BASELINE-CARDINALITY-AND-LABELS`,
`GOAL13-DIRECT-LOGIN-WITH-MULTIPLE-METHODS-OPENS-PROVIDER-SPECIFIC-SELECTOR`,
`GOAL13-LOGIN-PROVIDER-SELECTOR-CANCEL-RETURNS-TO-AUTH-TYPE-SELECTOR`,
`GOAL13-BUILT-IN-RUNTIME-LOGIN-ROUTES-ALIASES-AND-PERSISTS-CANONICAL-CREDENTIALS`,
and the three OpenAI device-code tests in `test/cadr-ai/auth-test.lisp`.

The repository ignore audit also follows the fixed baseline rather than hiding
all HTML: baseline `pi-*.html` / `out.html` becomes `cadr-*.html` / `out.html`.
Thus default `cadr-session-*.html` exports do not dirty the worktree, while the
legacy arbitrary-name `ms9te620-dgwif1j3gv42.html` remains deliberately visible
and untouched.

### Why 12,056 checks missed it

The TUI used one `busy-p` for two meanings: editor serialization and agent
reasoning. Existing worker tests proved that local work completed and cleared
the flag, but never asserted that a frame rendered during that work lacked
`Working...`. OAuth cancellation tests verified listener teardown and editor
restoration, but accepted or ignored the generic error notice. Finally, the
OpenAI manual-dialog snapshot accidentally passed because the single shared
copy happened to be OpenAI's copy; no provider matrix compared provider name,
method name, login label, instructions, and prompt text as separate fields.

Implementation commits: `8ce316f99`, `c5f1c632b`.

### Verification-gate correction

The first full `./scripts/verify.sh` run was not accepted as a pass and was not
papered over by a retry. It passed binary freshness, both source-parity gates,
the deterministic suite, and both isolated builds, then failed closed at Goal
11 with:

```text
sustained mixed interaction was not paced for the declared duration
```

The six native/process/PTY/socket harnesses were consequently `NOT RUN`.
Credential-gated live tests still reported 7 pass / 1 skip and the DeepSeek TUI
smoke passed, but neither result was used as deterministic evidence.

The root cause was a single call to Common Lisp `sleep` followed by an
assumption that the requested interval had elapsed. `sleep` may return early,
so the exact duration gate could fail by a sub-tick margin. The replacement
`cadr-goal11-pacing:paced-wait-until` repeatedly checks an injected monotonic
clock and waits only for the remaining interval. The red-first regression
`test_pacing_rechecks_clock_after_early_sleep_return` simulates a sleeper which
returns after 30% of the requested time and proves the helper waits again until
the target clock value is reached. Focused Python gate: 10 tests, all pass; the
tenth test replays the checked Goal 13 artifact rather than a synthetic report.

The complete deterministic suite after this correction was:

```text
cadr test summary: systems=8 checks=12139 pass=12139 skip=0 fail=0
```

The subsequent full `./scripts/verify.sh` run completed every stage:

```text
Deterministic stages
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
credential-gated FiveAM                          PASS
DeepSeek live TUI                                PASS
```

The corrected sustained gate measured `p99.9=8ms`, maximum pause `16ms`, GC
maximum `14.47ms`, and converged memory over the declared duration. Live item
report: 8 total, 7 run/pass, 1 skipped because `ANTHROPIC_API_KEY` is absent,
0 failed; 32 checks, 31 pass, 1 skip, 0 fail.

Pacing correction commit: `df23c919f`.

## Completion-audit corrections

A final requirement-by-requirement audit found three cases where a green
mechanism was weaker than its claim. All three were reproduced red before the
gate was strengthened:

1. The presentation gate counted 123 rows but did not parse their dispositions
   or require independent file:line evidence. It now parses every B1-B4 row,
   rejects unknown status text, recomputes `119 aligned + 0 pending + 4
   intentional`, and requires explicit baseline and Cadr source locations in
   both evidence cells. Seventeen inherited “same range/component” cells were
   expanded to standalone evidence.
2. The C2 audit described the 135-file source tree that existed when it was
   written, but did not fail when later corrections added production files.
   The executable gate now recounts all 138 files across eight systems, checks
   all six audit axes, and requires explicit dispositions for
   `src/cadr-ai/crash.lisp`, `src/cadr-cli/crash.lisp`, and
   `src/cadr-tui/threads.lisp`.
3. Both checked C3 artifacts contained `"cold_start": null`. A fresh verify
   regenerated a current report, so the release gate passed without proving
   the committed artifact was replayable. The before value was measured from
   an isolated image built at exact revision `cd94d0b01`; the final value was
   measured from the current release image. Both now contain five real-PTY
   samples, and the Python regression runs the complete gate on the checked
   final artifact.

The replay command now passes directly:

```text
python3 scripts/goal11-performance-gate.py \
  --bench docs/benchmarks/goal-v13-c3-final.json \
  --stability docs/benchmarks/goal-v11-stability.json
goal11 gate: PASS
... sustained_p999=8.00ms, sustained_max=20.00ms, \
    sustained_gc_max=15.49ms, sustained_memory=converged, cold=154.57ms
```

Artifact hashes after adding the measured cold-start blocks:

```text
06d7faeb91ad7164b1d4258d6c18d3b6f1469b9bcfc09d22989a413d88583066  docs/benchmarks/goal-v13-c3-before.json
96350ee3588e0143d745b1af2f0c295f542b5c6c0c31693b65710dcea0ed11f6  docs/benchmarks/goal-v13-c3-final.json
```

Goal 13 remains open only for the user's final real-terminal A/B; the approved
auth-option partition above is mechanically implemented but is not represented
as user-accepted before that A/B.

### Final completion-audit gates

The current deterministic suite and the full release-equivalent verifier were
run after both gate corrections were committed:

```text
./scripts/test-cl.sh
cadr test summary: systems=8 checks=12432 pass=12432 skip=0 fail=0

./scripts/verify.sh
Deterministic stages
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
credential-gated FiveAM                          PASS
DeepSeek live TUI                                PASS
```

The live report ran seven items successfully and skipped only Anthropic for
the explicit reason `ANTHROPIC_API_KEY is not set`: 8 items total, 7 pass, 1
skip, 0 fail; 32 checks, 31 pass, 1 skip, 0 fail. The performance gate also
passed its checked sustained trace (`p99.9=4ms`, `max=16ms`, GC max
`15.77ms`, converged memory) and its 1,200-turn stability run.

The root binary was rebuilt after the latest source change and independently
accepted by the verifier:

```text
root binary build time: 2026-08-03 13:34:17.856602177 +0800
latest src commit:      c5f1c632b394973bdb37ac9f65f2692559cfb3f1
latest src commit time: 2026-08-03T12:17:34+08:00
./cadr --version:       cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

### Authentication-partition verification

The approved baseline partition landed in two implementation commits:

```text
012b851cc6c88718e271495fd2fd6a68fffafe73  feat(ai): add OpenAI Codex device-code login
8692b01e098c050b6fdae544ffa6dce2006c4405  fix(cli): align provider authentication routing
```

The final gates ran after both commits. Provider-specific login starts directly
for one method, opens the provider method selector only for two methods, uses
the provider-owned `loginLabel` with the baseline fallback, and returns the
exact `No login methods available.` copy for an empty method set. OpenAI Codex
browser and device-code login both persist under the canonical
`openai-codex` identity through the existing atomic auth store.

```text
./scripts/test-cl.sh
cadr test summary: systems=8 checks=12478 pass=12478 skip=0 fail=0

./scripts/verify.sh
Deterministic stages
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
credential-gated FiveAM                          PASS
DeepSeek live TUI                                PASS
```

The live report ran seven items successfully and skipped only Anthropic because
`ANTHROPIC_API_KEY is not set`: 8 items total, 7 pass, 1 skip, 0 fail; 32
checks, 31 pass, 1 skip, 0 fail. The verifier's Goal 11 gate also passed with
`sustained_p999=28ms`, `sustained_max=56ms`, `sustained_gc_max=16.59ms`, and
converged sustained memory.

The fixed baseline ignores `pi-*.html` and `out.html`; the product-name-only
translation is therefore `cadr-*.html` and `out.html`. This ignores the default
`cadr-session-*.html` export without hiding arbitrary HTML. The legacy
`ms9te620-dgwif1j3gv42.html` artifact remains untracked and untouched.

Binary freshness evidence from the same verifier run:

```text
root binary build time: 2026-08-03 15:14:13.539517095 +0800
latest src commit:      8692b01e098c050b6fdae544ffa6dce2006c4405
latest src commit time: 2026-08-03T15:11:45+08:00
./cadr --version:       cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

## Final user acceptance — 2026-08-03

The user confirmed that the final real-terminal A/B meets the Goal 13 bar.
This closes the only remaining acceptance item after the authentication
partition correction. Parts A, B, C, C2, C3, and D are complete, committed,
mechanically verified, and now user-accepted.
