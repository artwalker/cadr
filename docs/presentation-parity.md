# Presentation parity ledger

Fixed baseline: `earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.
Audit point: Cadr `e04d9230f` (Goal 13 Part A complete).  This ledger audits
presentation only.  Tool results sent to the model, provider payloads, event
sequences, and session data are outside this axis and remain governed by
`docs/parity-map.md` and `docs/source-parity.md`.

Status meanings:

- `一致`: the fixed baseline and Cadr assign the same copy, style, geometry,
  formatting rule, and truncation behavior.
- `不一致`: an implementation difference found by this audit; Part C owns it.
- `有意差异`: a user-approved difference which must remain documented.

## B1. Semantic theme-color assignment

The baseline schema contains 55 semantic colors
(`packages/coding-agent/src/modes/interactive/theme/theme.ts:31-103`); Cadr has
the same 55 names and values (`src/cadr-tui/theme.lisp:3-126`).  Equal values
are not enough: the rows below compare the elements to which each token is
applied.  Markdown mappings are at baseline `theme.ts:1230-1266` and Cadr
`src/cadr-tui/components.lisp:557-908`; syntax mappings are at baseline
`theme.ts:1096-1157` and Cadr
`src/cadr-cli/interactive-services.lisp:3470-3498,4132-4315`.

| Token | Baseline element assignment | Cadr element assignment | Status |
|---|---|---|---|
| `accent` | selected arrows/labels, links and tool path/pattern only; tool header remainder stays `toolOutput` (`model-selector.ts:268-301`; `render-utils.ts:75-84`; `find.ts:59-73`; `grep.ts:70-85`) | selectors and links align, but the complete non-read tool summary is accent, including `in`, path, glob and limit (`src/cadr-tui/components.lisp:1626-1634`) | 不一致 |
| `border` | editor/dynamic/loader border (`dynamic-border.ts:10-16`; `bordered-loader.ts:13-30`) | editor, selector and loader border (`src/cadr-tui/editor.lisp:1730-1792`; `src/cadr-tui/composition.lisp:1260-1320`) | 一致 |
| `borderAccent` | tree compaction marker (`tree-selector.ts:790-839`) | tree compaction marker (`src/cadr-cli/interactive-services.lisp:5656-5661`) | 一致 |
| `borderMuted` | Markdown tables and code/table structure (`theme.ts:1230-1266`) | Markdown tables and code/table structure (`src/cadr-tui/components.lisp:300-390,679-750`) | 一致 |
| `success` | configured/current/assistant-success labels (`model-selector.ts:268-301`; `tree-selector.ts:774-839`) | same selector and tree labels (`src/cadr-cli/interactive-services.lisp:5613-5624,8060-8125`) | 一致 |
| `error` | product errors, abort/length messages, invalid args, and only tool-specific error renderers (`assistant-message.ts:177-200`; `render-utils.ts:71-84`; `write.ts:164-179`; `edit.ts:200-226`) | those uses exist, but every line of any failed tool result and text beginning `error`/`failed` is additionally forced red (`src/cadr-tui/components.lisp:1224-1235,1487-1512`) | 不一致 |
| `warning` | warnings, read ranges, and renderer-created truncation lines (`read.ts:67-76,190-198`; `bash.ts:292-312`) | those uses exist, but raw tool-result lines beginning `warning`/`truncated`/`timed out` are additionally recolored (`src/cadr-tui/components.lisp:1224-1235`) | 不一致 |
| `muted` | secondary labels, hints, timing, preview counts and tool suffixes (`keybinding-hints.ts:35-50`; `bash.ts:275-312`) | same categories (`src/cadr-tui/components.lisp:1540-1565,1646-1669,2160-2245`) | 一致 |
| `dim` | footer, inactive key names, timestamps, compact hints (`footer.ts:222-240`; `keybinding-hints.ts:35-50`) | same categories (`src/cadr-tui/components.lisp:1747-1926`; `src/cadr-cli/interactive-components.lisp:38-51`) | 一致 |
| `text` | ordinary selector/dialog foreground (`extension-selector.ts:80-90`; `login-dialog.ts:150-196`) | same selector/dialog foreground (`src/cadr-cli/interactive-services.lisp:7510-7540,8810-8870`) | 一致 |
| `thinkingText` | visible and hidden thinking, italic (`assistant-message.ts:139-164`) | visible and hidden thinking, italic (`src/cadr-cli/tui.lisp:1993-2075`) | 一致 |
| `selectedBg` | selected session/tree row (`session-selector.ts:500-516`; `tree-selector.ts:1156-1252`) | selected session/tree row (`src/cadr-cli/interactive-services.lisp:1640-1705,5800-5865`) | 一致 |
| `userMessageBg` | full-width user-message box (`user-message.ts:38-57`) | full-width user-message box (`src/cadr-cli/tui.lisp:2086-2123`) | 一致 |
| `userMessageText` | user Markdown foreground (`user-message.ts:40-55`) | user Markdown foreground (`src/cadr-cli/tui.lisp:2086-2123`) | 一致 |
| `customMessageBg` | custom, skill, branch and compaction transcript boxes (`custom-message.ts:33-38`; `skill-invocation-message.ts:11-52`; `branch-summary-message.ts:10-56`; `compaction-summary-message.ts:10-57`) | extension custom messages use it, but skill invocations are ordinary user rows and branch/compaction summaries have no equivalent box (`src/cadr-cli/tui.lisp:1256-1302,2196-2203`) | 不一致 |
| `customMessageText` | custom/skill/branch/compaction body (`custom-message.ts:91-110`; `skill-invocation-message.ts:36-52`; `branch-summary-message.ts:39-54`; `compaction-summary-message.ts:40-55`) | extension custom body only; the other three transcript surfaces are absent or plain text (`src/cadr-cli/tui.lisp:2196-2203`) | 不一致 |
| `customMessageLabel` | `[custom]`, `[skill]`, `[branch]`, `[compaction]` labels (same files as preceding row) | extension custom label only; the other three transcript surfaces are absent or plain text (`src/cadr-cli/tui.lisp:2196-2203`) | 不一致 |
| `toolPendingBg` | running/default tool shell (`tool-execution.ts:63-75,248-268`) | running tool shell (`src/cadr-tui/components.lisp:1187-1197,1567-1695`) | 一致 |
| `toolSuccessBg` | settled successful tool shell and valid edit preview (`tool-execution.ts:248-268`; `edit.ts:229-264`) | settled successful tool shell; edit-preview timing is separately missing, but settled assignment is correct (`src/cadr-tui/components.lisp:1187-1197,1567-1695`) | 一致 |
| `toolErrorBg` | settled failed tool shell and invalid edit preview (`tool-execution.ts:248-268`; `edit.ts:229-264`) | settled failed tool shell (`src/cadr-tui/components.lisp:1187-1197,1567-1695`) | 一致 |
| `toolTitle` | tool verb and bash `$ command` (`bash.ts:226-231`; `read.ts:67-76`; `write.ts:131-161`; `edit.ts:195-198`) | same verb/command assignment after Part A (`src/cadr-tui/components.lisp:1582-1634`) | 一致 |
| `toolOutput` | raw tool output and secondary call fragments such as `in`, glob and limit (`bash.ts:258-306`; `find.ts:59-104`; `grep.ts:70-118`; `ls.ts:52-90`) | ordinary output uses it, but failed/content-prefixed lines are recolored and find/grep/ls secondary call fragments are accent (`src/cadr-tui/components.lisp:1224-1235,1487-1512,1626-1634`) | 不一致 |
| `mdHeading` | Markdown headings (`theme.ts:1230-1266`) | Markdown headings (`src/cadr-tui/components.lisp:557-604`) | 一致 |
| `mdLink` | linked label, underlined (`theme.ts:1230-1266`) | linked label, underlined (`src/cadr-tui/components.lisp:99-125`) | 一致 |
| `mdLinkUrl` | fallback visible URL (`theme.ts:1230-1266`) | fallback visible URL (`src/cadr-tui/components.lisp:99-125`) | 一致 |
| `mdCode` | inline code (`theme.ts:1230-1266`) | inline code (`src/cadr-tui/components.lisp:186-220`) | 一致 |
| `mdCodeBlock` | fenced code content (`theme.ts:1230-1266`) | fenced code content (`src/cadr-tui/components.lisp:737-893`) | 一致 |
| `mdCodeBlockBorder` | literal fence rows (`theme.ts:1230-1266`) | literal fence rows (`src/cadr-tui/components.lisp:737-893`) | 一致 |
| `mdQuote` | quote text (`theme.ts:1230-1266`) | quote text (`src/cadr-tui/components.lisp:609-678`) | 一致 |
| `mdQuoteBorder` | quote `│` (`theme.ts:1230-1266`) | quote `│` (`src/cadr-tui/components.lisp:609-678`) | 一致 |
| `mdHr` | horizontal rule (`theme.ts:1230-1266`) | horizontal rule (`src/cadr-tui/components.lisp:535-556`) | 一致 |
| `mdListBullet` | list/task marker (`theme.ts:1230-1266`) | list/task marker (`src/cadr-tui/components.lisp:391-534`) | 一致 |
| `toolDiffAdded` | added diff lines and word spans (`diff.ts:89-141`) | added diff lines and word spans (`src/cadr-tui/components.lisp:1392-1485`) | 一致 |
| `toolDiffRemoved` | removed diff lines and word spans (`diff.ts:89-141`) | removed diff lines and word spans (`src/cadr-tui/components.lisp:1392-1485`) | 一致 |
| `toolDiffContext` | hunk/context lines (`diff.ts:89-141`) | hunk/context lines (`src/cadr-tui/components.lisp:1392-1485`) | 一致 |
| `syntaxComment` | Markdown plus read/write source highlighting (`theme.ts:1096-1157`; `read.ts:177-185`; `write.ts:146-155`) | Markdown highlighting only; read/write tool source is flattened to `toolOutput` (`src/cadr-cli/interactive-services.lisp:3470-3498`; `src/cadr-tui/components.lisp:1487-1512`) | 不一致 |
| `syntaxKeyword` | same syntax surfaces as preceding row | Markdown only; read/write source missing | 不一致 |
| `syntaxFunction` | same syntax surfaces as preceding row | Markdown only; read/write source missing | 不一致 |
| `syntaxVariable` | same syntax surfaces as preceding row | Markdown only; read/write source missing | 不一致 |
| `syntaxString` | same syntax surfaces as preceding row | Markdown only; read/write source missing | 不一致 |
| `syntaxNumber` | same syntax surfaces as preceding row | Markdown only; read/write source missing | 不一致 |
| `syntaxType` | same syntax surfaces as preceding row | Markdown only; read/write source missing | 不一致 |
| `syntaxOperator` | same syntax surfaces as preceding row | Markdown only; read/write source missing | 不一致 |
| `syntaxPunctuation` | same syntax surfaces as preceding row | Markdown only; read/write source missing | 不一致 |
| `thinkingOff` | editor border at thinking `off` (`theme.ts:407-425`; `interactive-mode.ts:3810-3815`) | same editor border (`src/cadr-tui/theme.lisp:505-524`; `src/cadr-tui/editor.lisp:1900-1932`) | 一致 |
| `thinkingMinimal` | editor border at `minimal` (same baseline range) | same editor border (same Cadr range) | 一致 |
| `thinkingLow` | editor border at `low` (same baseline range) | same editor border (same Cadr range) | 一致 |
| `thinkingMedium` | editor border at `medium` (same baseline range) | same editor border (same Cadr range) | 一致 |
| `thinkingHigh` | editor border at `high` (same baseline range) | same editor border (same Cadr range) | 一致 |
| `thinkingXhigh` | editor border at `xhigh` (same baseline range) | same editor border (same Cadr range) | 一致 |
| `thinkingMax` | editor border at `max` (same baseline range) | same editor border (same Cadr range) | 一致 |
| `bashMode` | user-bash editor/execution emphasis (`bash-execution.ts:130-151`) | same user-bash emphasis (`src/cadr-tui/theme.lisp:526-534`; `src/cadr-cli/tui.lisp:790-835`) | 一致 |
| `pageBg` | exported session page background (`core/export-html/index.ts:108-167`) | parsed and tested but never passed to the actual exporter; exporter hard-codes light CSS (`src/cadr-cli/interactive-services.lisp:2576-2597`; `src/cadr-agent/session.lisp:2124-2149`) | 不一致 |
| `cardBg` | exported session card background (same baseline range) | parsed but unused by exporter (same Cadr ranges) | 不一致 |
| `infoBg` | exported session information-card background (same baseline range) | parsed but unused by exporter (same Cadr ranges) | 不一致 |

B1 count: `36 一致 / 19 不一致 / 0 有意差异 = 55`.

## B2. Visible element contracts

### Tools

| ID | Element | Baseline | Cadr | Status |
|---|---|---|---|---|
| T-01 | outer shell/state | one leading spacer, `Box(1,1)`, pending/success/error background (`tool-execution.ts:63-75,248-268`) | same geometry and three backgrounds (`src/cadr-tui/components.lisp:1567-1695`) | 一致 |
| T-02 | bash title/time | bold `toolTitle` `$ command`; explicit timeout only, muted; output tail 5; `Elapsed/Took 0.0s` (`bash.ts:222-231,258-313`) | same after Part A (`src/cadr-cli/tui.lisp:1389-1397`; `src/cadr-tui/components.lisp:1593-1669`) | 一致 |
| T-03 | read title/range/preview | bold verb, accent path, warning range; collapsed success has no preview, collapsed error has 10 (`read.ts:67-76,164-200`) | same title/range and budgets (`src/cadr-cli/tui.lisp:1398-1415`; `src/cadr-tui/components.lisp:1524-1539,1626-1630`) | 一致 |
| T-04 | write call content | path plus first 10/full content lines, language-aware source highlighting (`write.ts:131-161`) | content and budget align, but all non-diff lines are `toolOutput` (`src/cadr-cli/tui.lisp:1477-1488`; `src/cadr-tui/components.lisp:1487-1565`) | 不一致 |
| T-05 | edit preview | validates args and renders pending preview diff before execution; preview decides pending header background (`edit.ts:195-264`) | diff appears only after final tool result; running call has no preview (`src/cadr-cli/tui.lisp:1489-1514`; `src/cadr-tui/components.lisp:1567-1695`) | 不一致 |
| T-06 | find title | accent pattern; ` in path` and optional limit are `toolOutput` (`find.ts:59-73`) | complete summary after verb is accent (`src/cadr-cli/tui.lisp:1438-1447`; `src/cadr-tui/components.lisp:1631-1634`) | 不一致 |
| T-07 | grep title | accent `/pattern/`; ` in path`, glob and limit are `toolOutput` (`grep.ts:70-85`) | complete summary after verb is accent (`src/cadr-cli/tui.lisp:1419-1437`; `src/cadr-tui/components.lisp:1631-1634`) | 不一致 |
| T-08 | ls title | accent path; optional limit is `toolOutput` (`ls.ts:52-59`) | path and limit are one accent summary (`src/cadr-cli/tui.lisp:1448-1454`; `src/cadr-tui/components.lisp:1631-1634`) | 不一致 |
| T-09 | clickable file paths | read/write/edit/ls path is OSC-8 linked to an absolute `file:` URL when terminal capabilities allow (`render-utils.ts:19-23,75-84`) | display is shortened and colored but never linked (`src/cadr-cli/tui.lisp:1398-1454`; `src/cadr-tui/components.lisp:1626-1634`) | 不一致 |
| T-10 | invalid argument copy | every non-string visible arg is exact `[invalid arg]`; missing value is empty/ellipsis by tool (`render-utils.ts:25-29,71-84`) | tool-specific `[invalid command]`, `[invalid path]`, `[invalid pattern]`, or `[invalid argument]` (`src/cadr-cli/tui.lisp:1358-1457`) | 不一致 |
| T-11 | failed/raw output color | bash/find/grep/ls/read raw output remains `toolOutput`; only write/edit explicit errors are `error` (`bash.ts:258-306`; `read.ts:164-200`; `write.ts:164-179`; `edit.ts:200-226`) | all lines in a failed result and lines whose copy looks like a diagnostic are recolored red/yellow (`src/cadr-tui/components.lisp:1224-1235,1487-1512`) | 不一致 |
| T-12 | preview/expand/truncation | bash tail 5; write 10; grep 15; find/ls 20; read success 0/error 10; exact earlier/more-lines hints (`bash.ts:264-288`; `read.ts:173-188`; `write.ts:150-158`; `find.ts:85-105`; `grep.ts:97-119`; `ls.ts:71-91`) | same budgets, direction and hint placement (`src/cadr-tui/components.lisp:1213-1222,1514-1565`) | 一致 |
| T-13 | compact read titles | docs/resources/skills use `read docs`, `read resource`, or `[skill] name`, with expand hint (`read.ts:91-162`) | every read uses the ordinary path title (`src/cadr-cli/tui.lisp:1398-1415`) | 不一致 |

### Messages

| ID | Element | Baseline | Cadr | Status |
|---|---|---|---|---|
| M-01 | user | full-width background, X=`outputPad`, Y=1, OSC-133 zone, Markdown preserves list markers/escapes (`user-message.ts:38-68`) | same composition and OSC-133 boundaries (`src/cadr-cli/tui.lisp:2086-2123`; `src/cadr-cli/interactive-services.lisp:16-34`) | 一致 |
| M-02 | assistant | leading spacer, no background, Markdown, OSC-133 only without tool calls (`assistant-message.ts:78-114`) | same (`src/cadr-cli/tui.lisp:1935-2075`) | 一致 |
| M-03 | thinking | consecutive blocks merge with blank lines; muted/italic; one spacer before following answer (`assistant-message.ts:115-168`) | same (`src/cadr-cli/tui.lisp:2003-2075`) | 一致 |
| M-04 | length/error/abort | exact length message, `Operation aborted`, or `Error: ...`, with one spacer and output padding (`assistant-message.ts:172-201`) | same exact copy, color and spacing (`src/cadr-cli/tui.lisp:1954-2001`) | 一致 |
| M-05 | extension custom message/entry | custom background/label/body or extension-owned component (`custom-message.ts:33-112`; `custom-entry.ts:40-60`) | same bridge/default surface (`src/cadr-cli/tui.lisp:2124-2198`) | 一致 |
| M-06 | skill invocation | separate collapsible custom-background `[skill] name` row plus user text (`skill-invocation-message.ts:11-52`; `interactive-mode.ts:3290-3369`) | stored skill block is rendered as an ordinary user message; no transcript skill component (`src/cadr-cli/tui.lisp:1256-1302`) | 不一致 |
| M-07 | branch/compaction summary | collapsible custom-background component, label, localized token count and full Markdown (`branch-summary-message.ts:10-56`; `compaction-summary-message.ts:10-57`) | compaction is a flat `Compaction summary: ...` line; branch summary has no transcript component (`src/cadr-cli/tui.lisp:1793-1820,2199-2203`) | 不一致 |

### Footer and active status

| ID | Element | Baseline | Cadr | Status |
|---|---|---|---|---|
| F-01 | cwd/branch/session | home-relative cwd, then ` (branch)` and ` • session` (`footer.ts:32-44,113-126`) | same (`src/cadr-cli/interactive-services.lisp:1877-1899`; `src/cadr-tui/components.lisp:1771-1775`) | 一致 |
| F-02 | usage/cost | `↑ ↓ R W CH`; 1-decimal/rounded k/M; `$0.000`; optional `(sub)` (`footer.ts:24-29,128-145`) | same (`src/cadr-tui/components.lisp:1706-1722,1777-1815`) | 一致 |
| F-03 | context | one decimal `%/window`, `(auto)`, warning `>70`, error `>90` (`footer.ts:147-164`) | same thresholds and copy (`src/cadr-tui/components.lisp:1724-1749`) | 一致 |
| F-04 | provider/model/thinking | right-aligned; provider only with multiple providers and space; `thinking off` special copy (`footer.ts:168-220`) | same (`src/cadr-tui/components.lisp:1833-1906`) | 一致 |
| F-05 | extension statuses | alphabetic, control characters collapsed, optional third line (`footer.ts:232-243`) | same (`src/cadr-tui/components.lisp:1751-1755,1907-1927`) | 一致 |
| F-06 | working/retry/compaction | braille spinner, accent/muted/error/warning semantics and exact action hints (`status-indicator.ts:9-113`) | same state and copy (`src/cadr-cli/tui.lisp:1528-1545,2625-2691`) | 一致 |

### Overlays and selectors

The row order, exact copy, counts, selected spans, borders, descriptions,
search prompts, and transcript preservation are already locked by the 15
full-screen fixtures and their independent baseline oracles.  The evidence
below rechecks the production renderers rather than treating the hashes as an
oracle.

| ID | Surface | Baseline | Cadr | Status |
|---|---|---|---|---|
| O-01 | model | `model-selector.ts:91-130,162-185,248-307` | `src/cadr-cli/interactive-services.lisp:7950-8155` | 一致 |
| O-02 | model scoped state | same baseline range | same Cadr range | 一致 |
| O-03 | settings | `settings-selector.ts:472-738`; `settings-list.ts:80-249` | `src/cadr-cli/interactive-services.lisp:7002-7195` | 一致 |
| O-04 | resume | `session-selector.ts:119-175,414-519,685-746` | `src/cadr-cli/interactive-services.lisp:1288-1705` | 一致 |
| O-05 | fork | `user-message-selector.ts:14-148` | `src/cadr-cli/interactive-services.lisp:1719-1875` | 一致 |
| O-06 | tree | `tree-selector.ts:664-851,1156-1385` | `src/cadr-cli/interactive-services.lisp:5340-6055` | 一致 |
| O-07 | login method | `interactive-mode.ts:5014-5039`; `extension-selector.ts:18-90` | `src/cadr-cli/interactive-services.lisp:7197-7275` | 一致 |
| O-08 | login provider | `oauth-selector.ts:51-180` | `src/cadr-cli/interactive-services.lisp:7420-7710` | 一致 |
| O-09 | logout provider | same baseline component | same Cadr component | 一致 |
| O-10 | API-key input | `login-dialog.ts:30-71,154-218` | `src/cadr-cli/interactive-services.lisp:7310-7415` | 一致 |
| O-11 | scoped models | `scoped-models-selector.ts:91-252` | `src/cadr-cli/interactive-services.lisp:8778-8945` | 一致 |
| O-12 | trust | `trust-selector.ts:32-115` | `src/cadr-cli/interactive-services.lisp:6057-6310` | 一致 |
| O-13 | import confirmation | `interactive-mode.ts:5523`; `extension-selector.ts:18-90` | `src/cadr-cli/tui.lisp:4710-4785` | 一致 |
| O-14 | extension select/confirm/custom | `interactive-mode.ts:2244-2563`; `extension-selector.ts:18-90` | `src/cadr-cli/tui.lisp:4650-4785`; `src/cadr-tui/composition.lisp:700-790` | 一致 |
| O-15 | autocomplete | editor trigger/update paths, request cancellation/debounce, value/description list and popup placement (`packages/tui/src/components/editor.ts:590-598,1123-1153,1343-1357,1708-1722,2102-2350`) | same natural/forced trigger rules, isolated request state, 20 ms debounce and popup geometry (`src/cadr-tui/editor.lisp:966-1256,1284-1351,1427-1525,1663-1810`) | 一致 |
| O-16 | selector boundary navigation | baseline selectors do not share one universal wrap policy | user-approved global first/last bidirectional wrap (`src/cadr-tui/components.lisp:2010-2055` and selector-specific move functions) | 有意差异 |

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
| N-08 | OAuth URL in terminal | one unwrapped URL row and explicit browser fallback (`interactive-mode.ts:5250-5345`) | same TUI auth-url entry (`src/cadr-cli/tui.lisp:2268-2271,4390-4485`) | 一致 |
| N-09 | model catalog refresh | exact `Model catalogs refreshed.` and configured-provider guidance (`model-selector.ts:91-103,174-185`) | same (`src/cadr-cli/main.lisp:3455-3480`; `src/cadr-cli/interactive-services.lisp:8060-8090`) | 一致 |
| N-10 | package/install foreground output | deliberate foreground progress; wrapper diagnostics excluded (`package-manager-cli.ts:503-510`; `core/package-manager.ts:2530-2536`) | same product/diagnostic boundary (`src/cadr-cli/package-manager.lisp:937-1105`) | 一致 |

B2 count: `39 一致 / 11 不一致 / 2 有意差异 = 52`.

## B3. Paths and numeric formats

| ID | Format | Baseline | Cadr | Status |
|---|---|---|---|---|
| P-01 | tool `~` shortening | raw prefix test: any string starting with `homedir` is shortened (`render-utils.ts:10-17`) | path-component boundary is required (`src/cadr-tui/terminal-image.lisp:634-645`) | 不一致 |
| P-02 | footer `~` shortening | only cwd equal to or inside home is shortened (`footer.ts:32-44`) | same boundary rule (`src/cadr-cli/interactive-services.lisp:1877-1899`) | 一致 |
| P-03 | session-selector `~` shortening | raw prefix test (`session-selector.ts:26-33`) | path-component boundary is required (`src/cadr-cli/interactive-services.lisp:1288-1304`) | 不一致 |
| P-04 | tool path URI | eligible file paths receive OSC-8 `file:` links (`render-utils.ts:19-23,75-84`) | no tool-title path URI (`src/cadr-cli/tui.lisp:1398-1454`) | 不一致 |
| P-05 | read range | `:start`, or `:start-end` where default start is 1 (`read.ts:67-76`) | same (`src/cadr-cli/tui.lisp:1398-1415`) | 一致 |
| P-06 | tokens/cost/context | `<1k`, one-decimal k/M, rounded k/M, `$0.000`, `0.0%` (`footer.ts:24-29,111-164`) | same positive-number thresholds and units (`src/cadr-tui/components.lisp:1706-1749,1777-1822`) | 一致 |
| P-07 | tool elapsed time | seconds with exactly one decimal (`bash.ts:222-224,309-313`) | seconds with exactly one decimal (`src/cadr-tui/components.lisp:1646-1669`) | 一致 |
| P-08 | session age | `now`, `m`, `h`, `d`, `w`, `mo`, `y` with floor boundaries (`session-selector.ts:35-49`) | same thresholds and units (`src/cadr-cli/interactive-services.lisp:1306-1326`) | 一致 |
| P-09 | tree label timestamp | today `HH:MM`; current year `M/D HH:MM`; older `YY/M/D HH:MM` (`tree-selector.ts:854-877`) | always `M/D HH:MM`, and the parser ignores year/day-relative context (`src/cadr-cli/interactive-services.lisp:5310-5325`) | 不一致 |
| P-10 | truncation sizes/counts | binary size units, line/result/match/entry counts and exact brackets (`bash.ts:292-306`; `read.ts:190-198`; `find.ts:98-105`; `grep.ts:110-119`; `ls.ts:84-91`) | same displayed units/counts; model-facing result copy remains independently locked (`src/cadr-tui/components.lisp:1514-1565`; `src/cadr-cli/truncation.lisp:1-120`) | 一致 |

B3 count: `6 一致 / 4 不一致 / 0 有意差异 = 10`.

## B4. Non-terminal content returned by Cadr services

| ID | Surface | Baseline | Cadr | Status |
|---|---|---|---|---|
| H-01 | OAuth success HTML | complete responsive dark page, embedded Pi mark, `<title>`/`<h1>` = `Authentication successful`, dim close message (`packages/ai/src/auth/oauth/oauth-page.ts:1-99`) | one unstyled paragraph, `<title>cadr</title>`, no heading/logo/layout (`src/cadr-ai/oauth.lisp:530-546,576-584`) | 不一致 |
| H-02 | OAuth failure HTML | same shell with `Authentication failed`, escaped message and optional monospace details (`oauth-page.ts:3-17,102-108`) | same minimal page as success; no failure title/heading/details region (`src/cadr-ai/oauth.lisp:530-546,576-588`) | 不一致 |
| H-03 | callback-specific copy | route/state/missing-code/internal failures have distinct escaped messages (`openai-codex.ts:340-363`; `anthropic.ts:118-145`) | all validation failures return provider-generic `authentication failed. Return to cadr.` (`src/cadr-ai/oauth.lisp:573-588`) | 不一致 |
| H-04 | HTML escaping | title, heading, message and details escape `&<>"'` (`oauth-page.ts:3-17`) | message is interpolated directly (`src/cadr-ai/oauth.lisp:530-534`) | 不一致 |
| H-05 | session export HTML | theme variables including `pageBg/cardBg/infoBg`, complete template/CSS/JS, marked and syntax highlighter (`core/export-html/index.ts:108-174`) | fixed light CSS and a static nested list; parsed export colors are unused (`src/cadr-agent/session.lisp:2124-2235`; `src/cadr-cli/interactive-services.lisp:2576-2597`) | 不一致 |
| H-06 | HTTP response framing | UTF-8 HTML content type, byte-accurate content length and close (`openai-codex.ts:336-365`) | same wire-level framing and UTF-8 byte length (`src/cadr-ai/oauth.lisp:530-547`) | 一致 |

B4 count: `1 一致 / 5 不一致 / 0 有意差异 = 6`.

## Audit summary and Part C worklist

| Category | 一致 | 不一致 | 有意差异 | Total |
|---|---:|---:|---:|---:|
| B1 semantic colors | 36 | 19 | 0 | 55 |
| B2 visible elements | 39 | 11 | 2 | 52 |
| B3 paths/numbers | 6 | 4 | 0 | 10 |
| B4 non-terminal content | 1 | 5 | 0 | 6 |
| **Total** | **82** | **39** | **2** | **123** |

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
9. tree label timestamp formatting;
10. OAuth success/failure HTML and callback-specific escaped copy;
11. session-export theme/template presentation.

Part B changed no presentation source.  Part C must update each affected row to
`不一致（已改齐）` with implementation and regression evidence.  The two
intentional differences remain frozen: product branding and user-approved
universal selector wrapping.
