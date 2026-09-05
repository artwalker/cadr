# Goal 9 Part B visual parity ledger

The baseline is fixed at `earendil-works/pi@d981de1229ef899957bbe968bc8dcda02a21f477`.
This document records the mechanically verifiable visual and interaction contract; the final perceptual judgement is still adjudicated by the B3 two-terminal A/B gate.

## B2 methodology: the visual contract includes runtime state

B2 no longer treats static constants, a single component render, or final string equality as sufficient evidence. The visual contract
covers a component's states and state transitions within a real event sequence as well:

- selectors must cover the empty list, zero candidates after filtering, the first item, the last item, paging, wrap-around navigation, and confirmation;
- tools must cover running, partial, success, error, collapse/expand, and the elapsed-time copy;
- assistant/tool streaming output must repaint frame by frame according to the real deltas, preserving the original line breaks, and must not borrow the
  notice, log, or any other display channel;
- streaming content must have a character-by-character equivalence gate: for one and the same fixed source text, iterate over every single cut point and over representative
  multi-cut points; the final assembled text and every `text` event payload must be character-for-character equal to the source text;
  whitespace deltas, whitespace+digit, consecutive digits, a digit at the start of a line, and the non-streaming path are all mandatory boundaries;
- provider capabilities must not be tested by proxy through a single implementation: for every provider × every thinking level, the request capability parameters
  and whether thinking start/delta/end are emitted must both be asserted; the Responses reasoning
  summary and the chat-completions reasoning content belong to separate paths; unknown/temporary model ids
  must also enter the same matrix;
- the editor must be fed input step by step at the code-point boundaries the terminal may deliver, and rendered frame by frame, including the empty string,
  CJK, combining marks, and emoji ZWJ intermediate states;
- commands, key bindings, overlays, and the footer must verify the complete chain from the input decoder through runtime state to the final
  virtual screen, and must not compare only the hint copy or the constructed static component;
- the key-binding gate must be fed real terminal raw bytes: legacy, Kitty, xterm
  modifyOtherKeys, and CSI arrow keys with modifiers are each covered separately; a complete but unknown escape
  sequence must be dropped atomically, and the parameter bytes must never be degraded into editor text;
- provider transport must cover the three abort timings: TLS handshake, connected but headers not yet received, and streaming read;
  an abort may only converge to `Request was aborted`/`Operation aborted`, an ordinary
  native transport failure may only be normalized to `fetch failed`, and leaking a SAP, an OpenSSL
  function name, or a build machine's C source path is forbidden;
- tool success/failure/argument echo and every line of hint copy in every overlay must be asserted verbatim as a complete string or a
  complete virtual-screen snapshot; searching for keywords only, checking style tokens only, or only
  asserting event types does not constitute visual contract evidence.
- reachable interfaces are only the first layer of closure; every interface's significant runtime states must also enter a separate registry, bound to
  fixed-baseline `file:line` evidence, a deterministic trigger, and a real checkpoint. When a required state is deleted, a capture
  becomes invalid, or there is neither a capture nor an explicit reason, render-diff fails closed before it starts the PTY.
- base screens without an overlay rank equally with overlays: cold start, single turn, three turns, exact fill, overflow,
  thinking, tool collapsed/expanded, active status, widget, scrolled viewport, and narrow width must all lock the complete virtual
  terminal bytes; component-level order, line-count, or keyword assertions cannot replace the full-screen gate.
- a full-screen SHA only proves that the fixture has not drifted, not that the fixture is correct. Every SHA case must also have one
  independent semantic oracle derived directly from the fixed baseline's `file:line` (first line, natural height, order, spacing, or
  the visible-window contract), and a bidirectional case-name consistency gate guarantees that a hash cannot be added alone. Generating the oracle's expectation
  from Cadr's current render result is forbidden; when a hash is modified, the baseline contract must first be stated and the independent assertion updated.

Deterministic gates use a faux provider + virtual terminal by preference; a PTY is used only when a real process, terminal mode, or
signal lifecycle cannot be covered equivalently in-process. For every field defect, a red test that reproduces the original fault
is kept first, and it is then turned green by the same assertion. B3 is still responsible for real-terminal feel, but no longer finds on B2's behalf the automatable
crashes, boundary states, and state errors.

The status may only be:

- `match`: already equivalent before entering Part B, or this round's re-check found no difference.
- `mismatch (corrected)`: this round found a difference, the implementation was corrected, and there is a permanent gate.
- `intentional difference`: must have user approval and be registered in the README. This round has two user adjudications: all selectors
  wrap in both directions, and the bash title never displays the timeout.

## B1. Reproducible baseline TUI

Audit checkout:

```bash
git -C /root/projects/pi-mono worktree add --detach \
  /tmp/cadr-parity-d981de122 \
  d981de1229ef899957bbe968bc8dcda02a21f477
cd /tmp/cadr-parity-d981de122
npm ci --ignore-scripts
npm run hydrate:model-data
npm run build:offline
./node_modules/.bin/tsx packages/coding-agent/src/cli.ts --version
# 0.83.0
```

2026-07-31 mechanical re-check:

```text
git rev-parse HEAD
d981de1229ef899957bbe968bc8dcda02a21f477

./node_modules/.bin/tsx packages/coding-agent/src/cli.ts --version
0.83.0
```

The baseline TUI has been cold-started in a `tmux` 100×32 PTY and exited normally with `/quit`. Startup command:

```bash
PI_CODING_AGENT_DIR=/tmp/cadr-goal9-pi-agent \
PI_OFFLINE=1 \
./node_modules/.bin/tsx packages/coding-agent/src/cli.ts \
  --provider deepseek --model deepseek-chat \
  --no-session --offline --no-extensions --no-skills \
  --no-prompt-templates --no-themes --no-context-files \
  --no-approve --alt
```

## B2.1 Theme and the complete built-in palette

Baseline sources:

- `packages/coding-agent/src/modes/interactive/theme/{dark,light}.json`
- `packages/coding-agent/src/modes/interactive/theme/theme.ts:185-290,330-405,646-870,886-950`
- `packages/coding-agent/src/modes/interactive/theme/theme-controller.ts:18-60`

Cadr implementation and gates:

- `src/cadr-tui/theme.lisp:3-529`
- `src/cadr-cli/interactive-services.lisp:2079-2184`
- `src/cadr-cli/tui.lisp:2250-2591,2810-2940`
- `test/cadr-tui/theme-test.lisp:135-308`
- `test/cadr-cli/part-b-interactive-test.lisp:751-818`
- `test/cadr-cli/tui-test.lisp:2241-2633`

| ID | Contract and re-check conclusion | Status |
|---|---|---|
| TH-01 | Fixed theme, `light/dark` auto, a single OSC 11 detection when unconfigured, auto DSR→OSC 11, `COLORFGBG` ANSI256→RGB relative luminance `>=0.5`, and dark fallback are all aligned; auto/fixed dynamically start and stop the notification at runtime. | mismatch (corrected) |
| TH-02 | Custom themes are validated against the complete schema; 100 ms debounce hot reload; the last valid theme is retained when one is temporarily missing or invalid. | mismatch (corrected) |
| TH-03 | Truecolor foreground/background use `38;2`/`48;2` respectively, and local restore is `39`/`49` respectively. | mismatch (corrected) |
| TH-04 | The 256-color cube/gray candidates, the `0.299/0.587/0.114` distance, and the gray-wins condition are aligned item by item. | mismatch (corrected) |

The complete built-in color values follow; letter case does not affect the RGB value.

| Semantic token | Dark | Light |
|---|---:|---:|
| accent | `#8abeb7` | `#5a8080` |
| border | `#5f87ff` | `#547da7` |
| borderAccent | `#00d7ff` | `#5a8080` |
| borderMuted | `#505050` | `#b0b0b0` |
| success | `#b5bd68` | `#588458` |
| error | `#cc6666` | `#aa5555` |
| warning | `#ffff00` | `#9a7326` |
| muted | `#808080` | `#6c6c6c` |
| dim | `#666666` | `#767676` |
| text | `#d4d4d4` | `#1f2328` |
| thinkingText | `#808080` | `#6c6c6c` |
| selectedBg | `#3a3a4a` | `#d0d0e0` |
| userMessageBg | `#343541` | `#e8e8e8` |
| userMessageText | `#d4d4d4` | `#1f2328` |
| customMessageBg | `#2d2838` | `#ede7f6` |
| customMessageText | `#d4d4d4` | `#1f2328` |
| customMessageLabel | `#9575cd` | `#7e57c2` |
| toolPendingBg | `#282832` | `#e8e8f0` |
| toolSuccessBg | `#283228` | `#e8f0e8` |
| toolErrorBg | `#3c2828` | `#f0e8e8` |
| toolTitle | `#d4d4d4` | `#1f2328` |
| toolOutput | `#808080` | `#6c6c6c` |
| mdHeading | `#f0c674` | `#9a7326` |
| mdLink | `#81a2be` | `#547da7` |
| mdLinkUrl | `#666666` | `#767676` |
| mdCode | `#8abeb7` | `#5a8080` |
| mdCodeBlock | `#b5bd68` | `#588458` |
| mdCodeBlockBorder | `#808080` | `#6c6c6c` |
| mdQuote | `#808080` | `#6c6c6c` |
| mdQuoteBorder | `#808080` | `#6c6c6c` |
| mdHr | `#808080` | `#6c6c6c` |
| mdListBullet | `#8abeb7` | `#588458` |
| toolDiffAdded | `#b5bd68` | `#588458` |
| toolDiffRemoved | `#cc6666` | `#aa5555` |
| toolDiffContext | `#808080` | `#6c6c6c` |
| syntaxComment | `#6a9955` | `#008000` |
| syntaxKeyword | `#569cd6` | `#0000ff` |
| syntaxFunction | `#dcdcaa` | `#795e26` |
| syntaxVariable | `#9cdcfe` | `#001080` |
| syntaxString | `#ce9178` | `#a31515` |
| syntaxNumber | `#b5cea8` | `#098658` |
| syntaxType | `#4ec9b0` | `#267f99` |
| syntaxOperator | `#d4d4d4` | `#000000` |
| syntaxPunctuation | `#d4d4d4` | `#000000` |
| thinkingOff | `#505050` | `#b0b0b0` |
| thinkingMinimal | `#6e6e6e` | `#767676` |
| thinkingLow | `#5f87af` | `#547da7` |
| thinkingMedium | `#81a2be` | `#5a8080` |
| thinkingHigh | `#b294bb` | `#875f87` |
| thinkingXhigh | `#d183e8` | `#8b008b` |
| thinkingMax | `#ff5fff` | `#af005f` |
| bashMode | `#b5bd68` | `#588458` |
| pageBg | `#18181e` | `#f8f8f8` |
| cardBg | `#1e1e24` | `#ffffff` |
| infoBg | `#3c3728` | `#fffae6` |

Mechanical capture of the same input in truecolor / 256 color:

```text
truecolor accent-fg = ESC[38;2;138;190;183m
truecolor user-bg   = ESC[48;2;52;53;65m
256-color accent-fg = ESC[38;5;109m
256-color user-bg   = ESC[48;5;59m
foreground reset    = ESC[39m
background reset    = ESC[49m
```

The raw byte evidence is saved in `/tmp/cadr-goal9-color-capture.txt`.

## B2.2 Layout, Markdown, tools, footer, selectors, and animation

| ID | Baseline contract and Cadr evidence | Status |
|---|---|---|
| LY-01 | The root order is startup/chat/pending/status/widgets/editor/footer; the above-editor widget container keeps one line in the empty state and one leading spacer in the non-empty state, and the below-editor container carries no spacer of its own; `src/cadr-cli/tui.lisp:461-474,2109-2329`, `GOAL9-B3-BASE-SCREEN-ABOVE-EDITOR-SPACER-MATCHES-BASELINE-COMPOSITION`. | mismatch (corrected) |
| LY-02 | user full-width background X=1/Y=1; assistant has no background and one blank line before visible content; thinking is muted+italic; `src/cadr-cli/tui.lisp:1689,1758,1872`. | mismatch (corrected) |
| LY-03 | A spacer before the tool, X=1/Y=1, state background; `src/cadr-tui/components/tool-block.lisp:464` `render-tool-block`. | mismatch (corrected) |
| LY-04 | The editor has `─` only at top and bottom, height `max(5,floor(rows*0.3))`, and the scroll information sits in the border; `src/cadr-tui/editor.lisp:1551` `render-editor`. | mismatch (corrected) |
| LY-05 | select primary=32, gap=2, description min=10, 5 rows by default, and a width of `<=40` turns the description off; `src/cadr-tui/components/select-list.lisp:19,120`. | mismatch (corrected) |
| LY-06 | The overlay defaults to `min(80,width)`, with the selector's own border, spacer, and narrow-screen clipping; `src/cadr-tui/overlay.lisp:79` `resolve-overlay-layout`, `src/cadr-cli/tui.lisp:1997`. | match |
| MD-01 | The H1/H2/H3+ styles, the H3+ prefix, and block spacing are aligned. | mismatch (corrected) |
| MD-02 | code fence, two-space indentation, syntax coloring for registered languages, and the code-block color for unknown languages are aligned; the baseline `syntax-highlight.test.ts` span/entity/inheritance, TS, diff, regexp, decorator, and HTML gates are ported in full, and the visible token boundaries of HTML/diff/JSON/Bash/SQL and the Python/Bash URL counterexamples are covered. The audited baseline's finished state itself keeps the opening and closing fence lines, so seeing a literal <code>```text</code> / <code>```</code> is a verified non-difference. | mismatch (corrected) |
| MD-03 | quote `│ `, italic, and the HR 80-cell cap are aligned. | mismatch (corrected) |
| MD-04 | ordered/unordered/task markers, four-space nesting, and continuation are aligned. | mismatch (corrected) |
| MD-05 | link underline/color, and the OSC 8 and fallback URL rules are aligned. | mismatch (corrected) |
| MD-06 | Table width allocation, wrap, bold header, the complete box, and the narrow-screen raw fallback are aligned. | mismatch (corrected) |
| MD-07 | inline style local restore and the streaming partial fence's flicker prevention are aligned. | mismatch (corrected) |
| TL-01 | The pending/success/error backgrounds and the title/argument/output/error/warning semantic colors are aligned; a real nonzero bash exit must propagate from the tool result into a red-background error state, the title remains `$ command` with no state glyph added, and the copy is `Command exited...`. | mismatch (corrected) |
| TL-02 | collapsed preview: bash 5, write 10, grep 15, find/ls 20; a successful read shows no result in the collapsed state and shows the complete result once expanded, and an error is always visible. | mismatch (corrected) |
| TL-03 | A real edit result enters the diff renderer; the context/add/remove colors, single-line word inverse, tab→3 spaces, and the overlong-line cap are aligned; bash running/settled displays `Elapsed`/`Took`. | mismatch (corrected) |
| TL-04 | The default active tools, their order, description, and prompt snippet/guidelines are aligned with the baseline `read,bash,edit,write`; `grep/find/ls` are only enabled explicitly, avoiding the model switching to bash echo/sed because the prompt deviates. | mismatch (corrected) |
| TL-05 | User adjudication: the bash title displays only `$ command` whether or not a timeout is passed in explicitly, and does not display `(timeout Ns)`. This differs intentionally from the explicit timeout suffix of the audited baseline `bash.ts:226-231`. | intentional difference |
| FT-01 | cwd/branch/session; input/output/cache read/write/hit/cost/context; provider/model/thinking; extension status — the three-row layout is aligned. | mismatch (corrected) |
| FT-02 | The context `>70%` warning and `>90%` error are aligned. | mismatch (corrected) |
| FT-03 | The working/retry/compaction spinner, the semantic colors, and the status region are aligned. | mismatch (corrected) |
| FT-04 | `/login`, `/model`, thinking, subscription, and auto-compaction all refresh from live agent state; the editor thinking/bash border is synchronized. | mismatch (corrected) |
| SL-01 | generic selected `→ ` + accent, muted description, and the scroll/no-match theme are aligned. | mismatch (corrected) |
| SL-02 | The session selected row uses a full-width `selectedBg`; tree colors only the fixed gutter/body segment and does not incorrectly pad to the whole row. | mismatch (corrected) |
| SL-03 | model has at most 10 rows, accent selected, muted provider, green `✓`, and border/spacer are aligned. | mismatch (corrected) |
| SL-04 | autocomplete primary 12..32, default 5, configurable 3..20, a 20 ms debounce for `@` only, and the popup after the bottom border. | mismatch (corrected) |
| SL-05 | User adjudication: all selectors wrap in both directions at the first and last item, and an empty list stays stable; the baseline's selectors do not wrap uniformly, so this is registered as an intentional difference. | intentional difference |
| AN-01 | spinner `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`, 80 ms; one blank line before the loader. | mismatch (corrected) |
| AN-02 | render 16 ms throttle; terminal progress 1 s keepalive; `showTerminalProgress` is read on every event and clears immediately when turned off. | mismatch (corrected) |
| AN-03 | IME zero-width marker, inverse fake cursor, and hardware cursor placement/hiding/restoration are aligned. | mismatch (corrected) |
| AN-04 | resize invalidation, alternate screen, scroll/follow, mouse, autowrap, and exit restoration already have equivalent implementations. | match |

Markdown gates:

- `test/cadr-tui/components-test.lisp:130-820`
- `test/cadr-tui/component-parity-test.lisp:159-331`
- `src/cadr-cli/interactive-services.lisp:2935-3950`
- `test/cadr-cli/part-b-interactive-test.lisp:1352-1485,1821-1881`
- `test/cadr-cli/tui-test.lisp:1695` `GOAL9-TUI-MARKDOWN-TRANSFORMERS-COVER-USER-TEXT-THINKING-STREAMING-AND-CACHE`
- `test/cadr-cli/goal9-b-runtime-parity-test.lisp:174` `GOAL9-STREAMED-MARKDOWN-FENCE-IS-EXACT-THROUGH-THE-FULL-TUI-CHAIN`

Tool, footer, selector, and animation gates:

- `test/cadr-tui/components-test.lisp:229-568`
- `test/cadr-tui/editor-parity-test.lisp:224-521`
- `test/cadr-tui/terminal-colors-test.lisp:108-251`
- `test/cadr-cli/tui-test.lisp:223-1415,2334-2700`
- `test/cadr-cli/part-b-interactive-test.lisp:1671-2180`

Third-round mechanical ledger: of the 35 numbered items, `match` 2, `mismatch (corrected)` 31,
`intentional difference` 2, `pending` 0. The targeted gates, the isolated / current-user full runs, the PTY lifecycle,
the isolated native build, and the commit evidence are all in the ledger; the README difference registration is synchronized. The B3 real two-terminal
A/B has been confirmed by the user, and Part B is closed.

### B2 supplementary runtime gates

After the first B3 real two-terminal A/B round on 2026-07-31 and the second on 2026-08-01 were sent back, the following
runtime matrix, which the original mechanical ledger did not cover, was added; the test names and the red→green evidence are listed item by item in `docs/acceptance/goal-v9-part-b.md`.

| State surface | Mandatory transitions |
|---|---|
| selector | empty/filter-empty/first/last/page/wrap/select |
| editor | empty→incremental Unicode→ZWJ intermediate→complete grapheme |
| assistant stream | start→every delta→final multiline document |
| Markdown stream | delta→TUI entry→Markdown renderer→virtual terminal, the whole chain preserving fences and empty code lines frame by frame |
| stream content | every single cut point / representative multi-cut points→character-for-character equality; pure whitespace, whitespace+digit, consecutive digits, digit at line start, non-streaming |
| provider thinking | every provider × every thinking level × catalog hit/unknown model→payload and start/delta/end |
| tool | start/running/partial→success or error→collapsed/expanded |
| tool model result | the success/error/continuation/truncation result of every registered built-in tool→verbatim copy, the original path, the UTF-16/line-count/byte/limit numeric conventions; asserted in layers separate from the TUI preview |
| exact copy | tool success/error/args, every line of every overlay and the base-screen state matrix→complete snapshot, verbatim equality; the 15 overlays must carry a non-empty transcript, and there are a further 13 base-screen states, each locking a full-screen SHA-256 |
| command UI | command→refresh→overlay→navigation→cancel/select |
| application keys | raw legacy/Kitty/xterm/Windows Terminal bytes→configured action→busy/idle behavior; unknown complete sequence→atomic ignore |
| busy interaction | long-running child→Escape→process-group termination→error tool result→idle; TLS handshake/connected-before-headers/silent SSE→active socket shutdown + blocked Lisp operation interrupt→aborted assistant→idle; parallel tools→shared cancellation; busy Enter/Alt+Enter→steering/follow-up queue→exact pending rows→configured dequeue key→both queues restored to editor→mode-controlled drain; repeated Escape→single silent abort |

The busy-interaction row is a lifecycle contract, not a static key or screen
contract. Its permanent gates couple the production TUI input loop to a faux
agent and a real detached bash process: `GOAL10-BUSY-BASH-ABORT-KILLS-GROUP-REPORTS-ERROR-AND-SETTLES-AGENT`,
`GOAL10-BUSY-PARALLEL-TOOL-ABORT-REACHES-ALL-RUNNING-EXECUTORS`,
`GOAL10-BUSY-TUI-ESCAPE-ABORTS-ACTIVE-TOOL-AND-RETURNS-IDLE`,
`GOAL10-BUSY-TUI-ENTER-AND-ALT-ENTER-USE-DISTINCT-QUEUES`,
`GOAL10-BUSY-TUI-STEERING-IS-DELIVERED-AFTER-THE-ACTIVE-TURN`, and
`GOAL10-BUSY-TUI-REPEATED-ESCAPE-DOES-NOT-SPAM-ABORT-NOTICES`. Static
keybinding assertions, queue unit tests, and idle full-screen SHA snapshots do
not satisfy this row.

The third and fourth user A/B rounds added the missing cross-layer gates. Local
servers now hold the request at TLS handshake, connected-before-headers, and
silent SSE phases. Abort closes the socket and interrupts the blocked SBCL
operation, so it does not wait for a peer byte and cl+ssl cleanup cannot replace
the product condition with `SSL_shutdown` diagnostics. The production decoder
is driven with xterm/Windows Terminal `ESC[1;3A`, xterm modifyOtherKeys
`ESC[27;3;13~`, Kitty `ESC[13;3u`, and the legacy `ESC CR` fallback. Thus
`alt+up` dequeues while Alt+Enter and Enter remain distinct follow-up/steering
actions. Pending rows are exact-copy asserted. The abort component owns exactly
one `Spacer(1)` above the baseline `Text(..., outputPad=1)` rendering: one blank
row, then one horizontal padding cell followed by `Operation aborted`, with no
`Abort requested`, `session>`, `SB-SYS`, `SSL_`, or `../ssl/` row.

Goal 15 closes the remaining busy/local-status composition gap: pending
steering/follow-up rows and the active loader use the baseline component's
one-cell horizontal padding and complete width; dequeue copy is generated from
the configured `app.message.dequeue` key. Consecutive `/export` and `/reload`
results travel through the same replaceable status channel, so only the latter
remains visible. The real-controller regressions are
`GOAL15-BUSY-STATUS-AND-QUEUED-MESSAGES-USE-BASELINE-TEXT-PADDING` and
`GOAL15-CONSECUTIVE-LOCAL-COMMAND-STATUSES-REPLACE-THROUGH-THE-REAL-TUI`.

### B2 base-screen full-screen contract

The user A/B rounds found, in turn, that the last transcript line sat too close to the editor's top border, and that a short session as a whole was anchored at
the bottom of the viewport. Neither is a numeric problem of `Output padding` or `Editor padding`. The baseline composition is as follows:

| Region | Baseline `d981de122` evidence | Cadr conclusion |
|---|---|---|
| transcript top | `interactive-mode.ts:758-817`: the header carries one `Spacer(1)` before and after it; with no header/chat there is no extra fixed top margin. | `render-tui-state` has one blank line before and after startup; the cold-start, single-turn, and three-turn full-screen snapshots lock it. Verified consistent. |
| between transcript entries | `interactive-mode.ts:3318-3369`: one spacer is added before a new user message when chat already exists, while an assistant message is appended directly; `assistant-message.ts:100-114` adds one spacer only before visible assistant content. | `src/cadr-cli/tui.lisp:1983-1999` is isomorphic; the single-turn, multi-turn, and thinking snapshots lock it. Verified consistent. |
| around status | `packages/tui/src/components/loader.ts:43-45`: the active loader carries one leading blank line of its own; `status-indicator.ts:105-113`: the idle status occupies two full-width blank lines; the status container adds no trailing margin of its own. | `src/cadr-cli/tui.lisp:925-967` is isomorphic; the active/idle and composite-order tests lock it. Verified consistent. |
| above-editor widget | `interactive-mode.ts:2044-2072`: an empty container also places one `Spacer(1)`; a non-empty container first places one leading `Spacer(1)` and adds no spacer after the widget. This container sits between status and editor (`:734-746`). | The original implementation returned zero lines in the empty state, which is exactly the root cause of the screenshot difference; `src/cadr-cli/tui.lisp:461-474,2181-2186` has corrected the base-screen path by the same rule. |
| below-editor widget | `interactive-mode.ts:2044-2072`: zero lines in the empty state, no leading/trailing spacer in the non-empty state; in the root order it sits between editor and footer (`:743-746`). | `src/cadr-cli/tui.lisp:2187-2192,2311-2324` is isomorphic; the below-widget full-screen and composite-order tests lock it. Verified consistent. |
| editor and footer | the editor padding of `interactive-mode.ts:497-505` acts only as `paddingX`; `packages/tui/src/components/editor.ts:482-530` changes only the horizontal content width. `settings-manager.ts:120,1201-1202` states explicitly that output padding is the chat message's horizontal padding, used by `user-message.ts:38-57` and `assistant-message.ts:100-114`. editor, below widgets, and footer are directly adjacent in the root container (`interactive-mode.ts:743-746`). | No vertical spacing deviation was found; editor→below widget→footer has no fixed blank line, and the composite order and the full-screen matrix lock it. |
| short content and overflow | `packages/tui/src/tui.ts:235-244` concatenates only the actual lines in child order; `TuiMainScreen.ts:162-212` writes only those lines in the first frame, and `bufferLength=max(height,newLines.length)` is used only for viewport accounting and inserts no filler into the root layout; `:354-370` lets the terminal scroll only when the content passes beyond the viewport. `TuiAltScreen.ts:350-389` likewise cuts the document first, and blank lines are appended only after the complete composition. | `src/cadr-cli/tui.lisp:2811-2834` clips only the overflowing transcript and concatenates pending/status/widget/editor/footer directly; short content does not pad out the viewport height, and the blank space naturally stays below the footer. The exact-fill and overflow gates prove, respectively, that there is no premature clipping and no tail scroll. |

The two base-screen fixes were therefore, respectively, restoring the host-owned above-editor spacer, and removing from the root layout a
flexible viewport filler that does not exist in the baseline; they were not changing the user's padding configuration from `1` to some other
number. The fourth round further corrected the overlay architecture: the baseline root always keeps the chat container
(`interactive-mode.ts:734-746`), and `showSelector` replaces only the editor of the editor container
with the selector (`:4161-4175`). Cadr now likewise keeps the transcript and clips it to the remaining viewport,
rendering the overlay only in the editor slot; the old 15 empty-transcript snapshots could not prove this
contract, and have all now been regenerated with a fixed non-empty transcript and "the editor sentinel is not visible".

Added `test/cadr-cli/goal9-b3-base-screen-contract-test.lisp`, which fixes time, spinner, size, and
provider/model/cwd, and computes a SHA-256 over the virtual terminal's full screen byte by byte:

| State | Size | SHA-256 |
|---|---:|---|
| cold-start | 80×24 | `9733E04F6DE7672AEEE75764D149C02DB371BBC574E60D8799993675E6A1330A` |
| single-turn | 80×24 | `82D3A3D1162A88AEC7639414079F536E60D3E59B2A5FE04945EE6DC8557BF0B7` |
| multi-turn (3 rounds) | 80×28 | `99FC5B3F2A8F5F8D854064D8C0EB5890174DAD09F0C346BA8D048BFF4CB2012F` |
| viewport-exact-fill | 80×11 | `FE62F046A32FEAF0196939D9EDD4EE7B22F43205DD2307660C9951A7C9D74531` |
| viewport-overflow | 80×14 | `6FD90AA56FB8F791B62D1A1ACE1560C443CC8A10CCFF01B603E21179019761AA` |
| thinking | 80×24 | `029DB78936CC5F7F1A549ADBF4F6DA50F9968AD81F1398C6FD1672ED96BACD4F` |
| tool-collapsed | 80×24 | `6DEE222A9E0C83464F53AD8653FCBDCE15FD63D294638EB3374D74094236DEFE` |
| tool-expanded | 80×24 | `200859C6BA14DE80DD2C7F432BEDD659C66B7A9B58EE5A50410A6E6AC59E03AF` |
| active-status | 80×24 | `0B5F0BE1E3198B974634214CCB4C2E37360C834FDA34D8D1AE68EDF9B23E207C` |
| above-widget | 80×24 | `1B2E5A37C04D1A3621244D7F2E094C5C7340772CB0C39A15F05D38A5B9A6C406` |
| below-widget | 80×24 | `D6303174613AA56EACF5A0F79927B771449EDCB93CBCED5F5B66AC124C537A40` |
| overflow-scrolled-to-top | 52×14 | `D15615BBF1F0A2F18155DAF639EAD4A2F49DAF29DA38ABF2D95A170242A5BEFD` |
| narrow-width | 32×14 | `3879C2A71C2BF04C357276800FEC1C848F9FE13453A84C9E8579F25A569F6539` |

The 7192 checks in place before this did not catch the above-editor spacer; at that time the base screen had only component fragments and
partial virtual-terminal assertions. After the full-screen SHA was established, the 10236 checks the user pointed at (10269 before
this round started, because of the Apple Terminal gate) still did not catch the short-session bottom anchoring: the expected hashes of `single-turn` and the old
`multi-turn` were generated from exactly the wrong implementation, so the snapshots only prevented drift while fixing the defect in place, and
there was no independent semantic assertion that "a short document's line count must be smaller than the viewport, and the first message must not be pushed down by a flexible filler",
nor any exactly-filled/just-overflowed boundary state. The added
`GOAL9-B3-SHORT-CONVERSATION-COMPOSITION-STACKS-FROM-THE-TOP` and
`GOAL9-B3-VIEWPORT-EXACT-FILL-AND-OVERFLOW-FOLLOW-BASELINE-SCROLL-POLICY`
lock the layout invariants first, and the 13 full-screen SHAs then lock the concrete bytes. The four existing
base-screen snapshots that this layout path did not touch (tool collapsed/expanded, scroll-to-top overflow, narrow width) and
all 15 overlay full-screen snapshots stay byte-for-byte unchanged.

### B2 autocomplete triggering and the user output channel

Autocomplete's natural triggering is unified into one and the same set of context gates per the baseline `editor.ts:2085-2100,2140-2163,2219-2229,2347-2350`:
empty input, a space, consecutive spaces, and an ordinary path fragment do not trigger it; `/` triggers only at the start
of a message, and `@` and registered characters trigger only at a token boundary; an explicit Tab can force path completion. Once the popup
is open, text/backspace/delete re-query while retaining the original natural/force mode; after a space is typed, it closes if the natural
candidates no longer match, while a forced path popup stays in force mode. The corresponding gates cover the empty prefix, a space, consecutive
spaces, `/`, `@`, a path fragment, deleting down to empty, and typing a space after the popup is open.

The user output channel is audited at the same time under "product output is visible, infrastructure diagnostics are isolated". What an extension writes to stdout/stderr on its own initiative
remains visible; ASDF/compiler/loader verbosity, the `setsid` wrapper, the desktop URL launcher, the OAuth browser
launcher, and cl+ssl/OpenSSL/SBCL socket diagnostics must not enter the transcript, a tool result,
or the model context. An ordinary provider transport failure is verbatim `fetch failed`; a user abort is verbatim
`Request was aborted`, displayed by the TUI as `Operation aborted`. A model catalog refresh presents only real network/parse
errors as product errors; the installation progress of the foreground package-manager CLI is still retained per the baseline. The complete boundary list
and the item-by-item regression tests are in `docs/acceptance/goal-v10-visual-output-followup.md`.

The fifth round filled in the visual boundary of the notice channel itself: `session>` belongs only to the REPL protocol and to no
TUI notice/status/error/warning/success line. Ordinary status, errors, warnings, `/new` success,
and extension `notify` are already routed per the baseline; frontend output of any number of lines retains its content line by line but no longer carries
internal labels. The "one outer line + one line above and below the Box + one title line", four lines in total and
with no content preview, of a successful `read` in the collapsed state has been verified as a non-difference against `read.ts:164-187` and `tool-execution.ts:63-75`; the one blank line before the expanded-state
output and before the bash timing is the real layout difference corrected in this round.

The Markdown fence and heading markers are likewise registered as verified non-differences: the fixed baseline
`packages/tui/src/components/markdown.ts:383` keeps the "```lang" line as is and applies only the
`codeBlockBorder` style, and the `headingPrefix` at `:341` keeps the repeated `#` as is. Keeping the Markdown source markers in the terminal display
is deliberate design, so that the copied-out text is still valid Markdown; Cadr should not swallow these
markers or turn them into purely visual formatting.

### B2 overlay complete line-by-line contract

The third round no longer takes "spot-checking six overlays" as representing the whole interaction surface. The table below is locked by the current mechanical gates;
every row is verified jointly by the complete ANSI-stripped line array, the ANSI semantic styles, and the first/last wrap-around events.

The title color is determined by the fixed baseline's component class; there is no rule that "all overlay titles are uniformly accent":

| Class | Fixed baseline basis | Title style |
|---|---|---|
| main list with no title | the main layer of `model-selector.ts` and `settings-selector.ts` renders the list directly | no title |
| session/tree/fork class | `session-selector.ts:132,873`, `user-message-selector.ts:123`, `tree-selector.ts:1377` | ordinary bright color, bold |
| authentication, trust, extension selector/dialog | `extension-selector.ts:44-48`, `login-dialog.ts:44-48`, `trust-selector.ts:48-50` | accent bold |
| settings sub-layer | `settings-selector.ts:167-188,349-352` | accent bold, no outer horizontal padding |
| extension input/editor | the custom input/edit components of the fixed baseline's extension UI | accent, not bold |

`POST-GOAL15-OVERLAY-TITLE-STYLES-FOLLOW-BASELINE-COMPONENT-CLASSES` asserts each class separately,
so `/login`'s accent and the ordinary bright color of `/fork` and `/resume` can no longer be tied together by one global color change.

### Goal 15 post-close `/session` alignment

The fixed baseline `interactive-mode.ts:5723-5783` renders the complete information with one `Text(info, 1, 0)` component:
lines run consecutively within a group, and only between groups is there a blank line; `Session Info`, `Messages`, `Tokens`, and `Cost`
are bold and the field labels are dim; Cached also displays the hit rate; Cost is grouped by the actual provider/model,
and appends cache re-billed tokens/cost/miss count. Cadr's notification stream now first buffers
the complete multi-line text and creates only one transcript component at `finish-output`;
`write-session-command-info` outputs by the same structure and the same numeric conventions. The gate
`POST-GOAL15-SESSION-INFO-MATCHES-BASELINE-SPACING-STYLES-PERCENT-AND-COST-BREAKDOWN`
locks S01-S04 at the same time, and plain string containment can no longer mask a line-by-line spacer error.

| Surface | Title | Hints | Search | Entries, order, and values | Count | Selection, border, and spacing | Description | Wrap |
|---|---|---|---|---|---|---|---|---|
| `/model` | no extra `Select Model` title | when not scoped `Only showing models from configured providers. Use /login to add providers.`; after a refresh `Model catalogs refreshed.`; in the scoped state it displays `Scope: all | scoped` and the `tab scope (all/scoped)` generated from the configured key | `> ` | the current filter order; `id [provider]`, with `✓` on the current model | position/total when it exceeds the viewport | `→` accent; `─` above and below, with the blank lines of each block fixed | `Model Name: ...` below the selected item | bidirectional |
| `/settings` | no fabricated title in the main layer; the sub-layers are `Thinking Level`, `Theme`, `Light Theme`, `Dark Theme`, `Automatic Theme` | main layer `Enter/Space to change · Esc to cancel`; sub-layer `Enter to select · Esc to go back` | type-to-search in the main layer | consistent with the baseline capability gating: supports-images=nil gives 25 items; when true, Show images and Image width are appended after Auto-compact, 27 items in total; the sub-layer candidate order is fixed | a 10-row viewport, displaying `(i/25)` or `(i/27)` according to the actual total | `→` accent; top and bottom borders; a fixed blank line between the description and the list | the option description is displayed on a wide screen, wrapped/clipped on a narrow one; the sub-layer displays the description | bidirectional |
| `/resume` | `Resume Session (Current Folder)`, with the scope/name/sort state on the right | two lines: scope, regex/exact, sort/named/delete/path/rename | `> query` | the threaded/search result order; the name or the first message, the message count, and the age | current position/total when in a viewport | full-width background on the selected row; top and bottom borders and a fixed spacer | cwd/path displayed according to state | bidirectional |
| `/fork` | `Fork from Message` | `Select a user message ... into a new session` | none | the user messages of the active path, in their original order; `Message i of N` for each | each item carries its own `i of N` | `›` for selection; the title area, borders, and the blank lines between entries are fixed line by line | a summary of the user message | bidirectional |
| `/tree` | `Session Tree` | `↑/↓ move · ←/→ page · ctrl+←/→ branch · ctrl+x copy ...` and `filters ctrl+d/t/u/l/a ...` | `Type to search:` | tree order; a tool call is `[bash: <args>]` or `[read: <path>]`, and the raw result must not be rendered | `(i/N)` | a fixed gutter selection background; top and bottom borders and blank lines are fixed | message/tool label, branch/label time | bidirectional |
| `/login` method | `Select authentication method:` | `↑↓ navigate  enter select  escape/ctrl+c cancel` | none | API key after account; the value is the corresponding auth type | none | `→`; top and bottom borders and the title/list/hint spacers | none | bidirectional |
| `/login` provider/API key | `Select provider to configure:`; input layer `Login to <provider>` | OAuth or a masked API key after the provider is selected; `escape/ctrl+c cancel  enter submit` | `> ` for the provider; a masked `> ` for the key | the provider definition order; name, auth type, configured state | viewport `(i/N)`; exact copy for the empty state | `→`; top and bottom borders and a fixed spacer | `[subscription]`/`[API key]` and the credential source | bidirectional |
| `/logout` | `Select provider to logout:` | empty state `No providers logged in. Use /login first.` | `> ` | a projection of the stored credentials, in a stable sort order; env/config-only items are not mixed in | viewport `(i/N)` | `→`; top and bottom borders and a fixed spacer | auth type and configured/source | bidirectional |
| `/scoped-models` | `Model Configuration` | `Session-only. ctrl+s to save to settings.` and the complete operation hints | `> ` | session order; unavailable ids are retained; enabled `✓`/disabled `✗` | the enabled/unavailable state and the viewport | `→` accent; top and bottom borders and a fixed spacer | `Model Name: ...` | bidirectional |
| `/import` | `Import session` | `Replace current session with <path>?`; `↑↓ navigate  enter select  escape cancel` | none | `No` after `Yes`; the value contains the confirmed flag, the original command, and the path | none | `→`; top and bottom borders and a fixed spacer | none | bidirectional |
| `/trust` | `Project trust` and the cwd | `↑↓ navigate  enter save  escape/ctrl+c cancel` | none | Trust, Trust parent folder, Do not trust | none | `→`; top and bottom borders and a fixed spacer | saved decision, current session, parent path | bidirectional |
| extension custom UI | the single-line/multi-line title supplied by the extension | the generic `↑↓ navigate  enter select  escape cancel` | determined by the extension surface | the label/value supplied by the extension, in their original order | generic viewport | `→`; the framed select's top and bottom borders and a fixed spacer | the extension supplies the description | bidirectional; the real extension worker→live TUI bridge→keyboard selection→return value has a regression test |
| autocomplete | no title | no extra hints | the editor's current `/command`, `/model ...`, `/login ...`, or `@path` prefix | the canonical command order / match ordering; model/provider/path items with their real values | limited by `autocompleteMaxVisible` | selected `→`, the popup sits after the editor's bottom border, with no outer overlay frame; `@path` has a complete 40×8 virtual-screen gate | the description is displayed when the width allows | bidirectional |
| `/sessions`, `/switch`, `/branch`, `/install` | the baseline has no corresponding slash/TUI surface | Cadr has deleted them all from the built-in slash dispatch, the overlays, and autocomplete; typing them directly is handled only by the ordinary unknown-input path and constitutes neither a command alias nor a hidden backend | none | none | none | none | none | n/a |
| `/compact` | the baseline has no overlay | it currently executes compaction directly and presents the progress or the result in the status/transcript | none | none | none | none | compaction status | n/a |
| `/export` | the baseline has no overlay | it currently exports directly to the default HTML or to an explicit path and notices the result | none | none | none | none | the output path | n/a |
| `/reload` | the baseline has no overlay | it currently reloads keybindings/extensions/skills/prompts/themes/context directly; on success it displays the baseline's original text as a dim status with no `session>` prefix | none | none | none | none | reload summary | n/a |

The complete virtual-screen SHA-256 of the 15 overlays (including the standalone `/logout` surface) is locked by
`GOAL9-B3-EVERY-OVERLAY-HAS-AN-EXACT-FULL-VIRTUAL-TERMINAL-SNAPSHOT`;
every fixture contains a fixed user/assistant transcript and asserts that the editor sentinel is replaced by the selector.
The SHA-256 values after the fourth round's rebuild are:

| Overlay | SHA-256 |
|---|---|
| model | `828CFA77C89D3FA8E84E4ACC72FC9AFC797E8C82A26AEFA3FE0FC46438195869` |
| model-scoped | `9031A4EA00CFEAA9E9A931B0A493414B76AAB46BEC10A0C81204003DAA466DB1` |
| settings | `DB40F8BBA31200DB8C5BE49E59B2AE01EDA11F935B002DF230F96BA6F4133CC4` |
| resume | `DE1B4941BEAC9C1087885B26E7F97093682758FCDE492FCC4429385C01E548C8` |
| fork | `AA7D9886BCA3858198561FA431CA5DC5028A608B4EA200AA2F65FE9B50072D2E` |
| tree | `B0ECA829983C7840B4026E9C3F102D5D62AE7ED8CAB7412D5E7CC086DA59C117` |
| scoped-models | `9827A029C2C8B9AB28C8EF754B887447C23FDE41EB5941145DDAC9A97FC68415` |
| trust | `3D484AC3838FAE5ADA7A490D6274C6BD1C78FCC2F0BD196026F33EA1A4631A7E` |
| login-method | `305B0BB2D1C67D71D7851B1EF450E992212C08F8A680CC6DF00AA23CE3B033C0` |
| login-provider | `5CA87C165CDB0E54D1D8A1FB03379A4CE5BC0363904D1E243935F513956EBA20` |
| logout-provider | `5B88F48EC8368B4395CC5CDCBEE9CBF86B564CD0924F48282ED8E9DE81308212` |
| api-key | `FD7DC83C63AC1AD2767D362FE27C960FB4CBF110227CC99DADE7E85360AA3EED` |
| import | `B836156D2E481FCB62CF14A058B69A6F2E9D1723E47C4A29B496A0F58CB134AC` |
| extension-select | `BD71C617E1CE9E9A9CB32B6EEDFDC575600FB69772F4BA2CC866E36DA2C7BD9F` |
| extension-custom | `A85DF2C8310E88D1BEA5B9AE84CBF6735FBC83CBC1116082E52A2CBB9A76A2EC` |

### B2 SHA snapshot independent semantic oracle audit

Visual SHAs exist in the repository only for the 13 base-screens and the 15 overlays above; provider fixed vectors and
performance artifact hashes are not full-screen snapshots. The audit found that five base-screen items — thinking, the two tool states,
scroll-to-top, and narrow-width — had no baseline semantic oracle bound one-to-one to the SHA fixture;
extension-custom had only the generic transcript-retention and selector-behavior tests, and no
direct visual oracle for that fixture. The remaining items already had independent assertions, but there was previously no mechanism for "the set of SHA cases must be
exactly identical to the set of oracles". Two overall gates now establish the bidirectional pairing, with the complete result below.

| SHA case | Direct fixed-baseline basis and independent assertion | Audit result |
|---|---|---|
| base `cold-start` | `interactive-mode.ts:734-746` root order; the first startup content is fixed at row 1, followed by editor and footer | already present, folded into the overall gate |
| base `single-turn` | `tui.ts:235-244` concatenates only the natural lines; the first message at row 1, document height less than 24 | already present, folded into the overall gate |
| base `multi-turn` | same as above; the order of the three rounds of messages is unchanged, the first at row 1, document height less than 28 | already present, folded into the overall gate |
| base `viewport-exact-fill` | `TuiMainScreen.ts:162-212`; when the natural height is exactly 13 the first message is still visible | already present, folded into the overall gate |
| base `viewport-overflow` | `TuiMainScreen.ts:354-370`; height 14, the old first round is clipped while the latest round and editor/footer are retained | already present, folded into the overall gate |
| base `thinking` | `assistant-message.ts:89-169`; user→thinking→answer, with exactly one blank line between thinking and answer | **filled in this round** |
| base `tool-collapsed` | `tool-execution.ts:63-75`, `bash.ts:199,234-310`; displays earlier-lines, the last five lines, and the timing, and does not display the first two lines | **filled in this round** |
| base `tool-expanded` | same as above; the complete `one`…`seven`, and earlier-lines must not be displayed | **filled in this round** |
| base `active-status` | `interactive-mode.ts:739-746`; answer→one blank line→status→editor→footer | already present, folded into the overall gate |
| base `above-widget` | `interactive-mode.ts:2044-2072,739-746`; after the host spacer the widget is immediately adjacent to the editor top | already present, folded into the overall gate |
| base `below-widget` | same as above; editor bottom→widget→footer with no extra vertical line | already present, folded into the overall gate |
| base `overflow-scrolled-to-top` | `TuiAltScreen.ts:350-389`; the top of the 14-row viewport displays transcript 01…07, with no editor/footer mixed in | **filled in this round** |
| base `narrow-width` | `tui.ts:235-244` and component wrapping; at 32 columns user and assistant are two lines each and no line exceeds width 32 | **filled in this round** |
| overlay `model` | `components/model-selector.ts:91-130,162-185,248-307`; hint→query→models→description | already present, folded into the overall gate |
| overlay `model-scoped` | same as above; scope→query→scoped order→description→refresh notice | already present, folded into the overall gate |
| overlay `settings` | `components/settings-selector.ts:472-738`, `settings-list.ts:80-165,237-249`; the order of the 25 items, count, description, help | already present, folded into the overall gate |
| overlay `resume` | `components/session-selector.ts:119-175,414-519,685-746`; the title/help/query/empty-state order | already present, folded into the overall gate |
| overlay `fork` | `components/user-message-selector.ts:14-78,110-148`; title/help, the two user messages and the `i of N` order | already present, folded into the overall gate |
| overlay `tree` | `components/tree-selector.ts:664-851,1156-1252,1328-1385`; title, arrow hint, filter hint, entries, count | already present, folded into the overall gate |
| overlay `scoped-models` | `components/scoped-models-selector.ts:91-180,202-252`; title/help/query, enabled state, description, keys | already present, folded into the overall gate |
| overlay `trust` | `components/trust-selector.ts:32-115`; the cwd/state/options/help order | already present, folded into the overall gate |
| overlay `login-method` | `interactive-mode.ts:5014-5039`, `extension-selector.ts:18-78`; the two methods and the cancel help | already present, folded into the overall gate |
| overlay `login-provider` | `components/oauth-selector.ts:51-160`; the login title/query/providers and the credential state | already present, folded into the overall gate |
| overlay `logout-provider` | same as above; the logout title/query/providers and the credential state | already present, folded into the overall gate |
| overlay `api-key` | `components/login-dialog.ts:30-71,154-167`; title/prompt/input/cancel-submit help | already present, folded into the overall gate |
| overlay `import` | `interactive-mode.ts:2244-2281,2299-2305,5523`, `extension-selector.ts:18-78`; title/question/Yes-No/help | already present, folded into the overall gate |
| overlay `extension-select` | `interactive-mode.ts:2244-2281,2299-2305`, `extension-selector.ts:18-78`; title/Alpha-Beta/help | already present, folded into the overall gate |
| overlay `extension-custom` | `interactive-mode.ts:2494-2563`, `select-list.ts:74-137`; after the transcript, Alpha then Beta is selected, with the footer after them | **filled in this round** |

`GOAL9-B3-EVERY-BASE-SCREEN-SHA-HAS-A-BASELINE-DERIVED-SEMANTIC-ORACLE`
directly executes 13 groups of invariants;
`GOAL9-B3-EVERY-OVERLAY-SHA-HAS-A-BASELINE-DERIVED-SEMANTIC-ORACLE`
maps the 15 cases one-to-one onto their baseline sources and line-by-line order, and both jointly assert that the non-empty transcript comes before the
surface, that the editor sentinel is replaced, and that the footer comes after the surface. An addition, deletion, or rename on either side fails before the
hash comparison.

The `@path` full screen and wrap-around are locked by
`GOAL9-B3-AT-PATH-AUTOCOMPLETE-HAS-AN-EXACT-FULL-SCREEN-AND-WRAPS`.
The settings 25/27 capability branches, the complete copy, search, narrow screen, and submenus are locked by
`GOAL9-B3-SETTINGS-OVERLAY-IS-AN-EXACT-BASELINE-SCREEN`,
`GOAL9-B3-SETTINGS-CAPABILITY-AND-SUBMENUS-MATCH-BASELINE-CONTRACT`, and
`GOAL9-B3-EVERY-SETTINGS-SUBMENU-WRAPS-AT-BOTH-BOUNDARIES`. The extension raw
surface is locked by `GOAL9-B3-EXTENSION-SELECTOR-STYLES-COUNTDOWN-KEYS-AND-TOOL-TOGGLE-ARE-EXACT`,
and the real bridging by
`GOAL9-B3-EXTENSION-SELECT-RUNS-THROUGH-THE-LIVE-TUI-OVERLAY-BRIDGE` and
`GOAL9-B3-EXTENSION-CONFIRM-RUNS-THROUGH-THE-LIVE-TUI-OVERLAY-BRIDGE`.
The full chain of streaming Markdown is locked by
`GOAL9-STREAMED-MARKDOWN-FENCE-IS-EXACT-THROUGH-THE-FULL-TUI-CHAIN`;
the provider × API × thinking level × catalog hit/miss matrix is locked by
`EVERY-BUILT-IN-PROVIDER-AND-API-HAS-THINKING-LEVEL-HIT-MISS-CONTRACT`.

The reason the earlier gates missed the fourth round's three classes of defect is that the test inputs themselves were too weak: the transport output audit
had no provider/TLS line, and silent-SSE used only cleartext HTTP and asserted only the stop reason;
the Alt key test was fed only a synthetic legacy `ESC p`, with no real CSI/Kitty/modifyOtherKeys bytes;
the transcripts of the 15 overlay full-screen fixtures were empty, so "clearing the transcript" and "correctly retaining an
empty transcript" produced the same result. The added tests lock, respectively, the three TLS abort phases and the forbidden fragments,
the complete real-terminal byte→action→queue chain, and the non-empty transcript / editor-slot
replacement of every overlay. `assistant-message.ts:190-200` further proves that an abort fragment carries its own single `Spacer(1)`, so
the outer layer no longer adds a second line for a pure error fragment.

## B3. Two-terminal A/B gate

Both ends must use the same terminal emulator, font, 100×32 starting size, `TERM`,
`COLORTERM`, `COLORFGBG`, and `DEEPSEEK_API_KEY`. The model's wording need not be the same; only the presentation and the interaction are compared.

Terminal A, baseline:

```bash
cd /tmp/cadr-parity-d981de122
PI_CODING_AGENT_DIR=/tmp/cadr-goal9-ab-pi-agent \
PI_OFFLINE=1 \
./node_modules/.bin/tsx packages/coding-agent/src/cli.ts \
  --provider deepseek --model deepseek-chat \
  --offline --no-extensions --no-skills --no-prompt-templates \
  --no-themes --no-context-files --no-approve --alt
```

Terminal B, Cadr:

```bash
cd /root/projects/cadr
CADR_OFFLINE=1 \
./cadr --provider deepseek --model deepseek-chat \
  --offline --no-extensions --no-skills --no-prompt-templates \
  --no-themes --no-context-files --alt
```

| Scene | Exact operation | Compare | User confirmation |
|---|---|---|---|
| Cold start | Type nothing for 5 seconds after startup. | auto theme, startup spacing, editor border, footer, cursor, idle stability. | Confirmed |
| Streaming | `Think for several seconds, then give exactly 12 numbered one-line steps for checking a CLI release.` | thinking, spinner, streaming repaint, footer/status transition. | Confirmed |
| Long output | `Output the integers 1 through 120, one per line, with no prose.`; scroll to the top, one page, the bottom. | follow, scroll marker, clipping, footer anchor, return to the live tail. | Confirmed |
| Tool call | `Use bash to run printf 'alpha\\nbeta\\n'; then read README.md and report only its first heading.`; Ctrl+O once it finishes. | state background, padding, title/arg/output colors, preview budget, expansion stability. | Confirmed |
| Diff | In each side's own temporary directory, edit `alpha beta gamma` into `alpha delta gamma`. | add/remove/context, word inverse, background, collapse/expand. | Confirmed |
| Overlays | Open/cancel `/model`, `/settings`, `/resume`, `/fork`, `/tree`, `/login`, `/logout`, `/scoped-models`, `/import`, `/trust`, and the extension custom UI in turn; cover search, the empty state, first/last wrap-around, and paging one by one. | every line's title/hint/search/entry/value/count/description, border, spacer, selectedBg, scroll, focus, no stale content. | Confirmed |
| Autocomplete | `/mo`→cancel, `/model `→cancel, `@REA`→move→apply→undo. | popup position, breakpoints, selected row, description, cursor/IME, undo. | Confirmed |
| CJK/emoji | Paste `中文ABC🙂👨‍👩‍👧‍👦 é` repeatedly until it wraps, then move and delete by grapheme and submit. | cell, cursor, border, wrap, transcript alignment. | Confirmed |
| Narrow resize | With an overlay open and while streaming, go 100×32→60×20→40×12→100×32 in turn. | reflow, table/code wrap, footer truncation, overlay clipping, no stale cell. | Confirmed |
| Error | `/model __goal9_missing_model__`; then have bash execute `sh -c 'echo expected-error >&2; exit 7'`. | error color/spacing, tool error background, footer recovery, focus. | Confirmed |
| Exit | `/quit`; Ctrl-C after restarting. | cursor, bracketed paste/raw, alternate screen, no duplicated final frame. | Confirmed |

Part B disposition: `the B3 two-terminal A/B has been confirmed by the user; Part B passed acceptance and was closed on 2026-08-01`

## Goal 15 fixed-baseline differential closure

The permanent raw-byte harness supplements these self-snapshots with a second
oracle: the fixed baseline's actual PTY output. The `startup-untrusted` case now
locks the bare yellow trust warning after seeded transcript content, and the
`fatal-crash` case locks terminal teardown before fatal output. I01 retains raw
ANSI/update differences for self-replay rather than normalizing them away; I02
retains the approved redacted crash summary while keeping teardown geometry
aligned. Exact scenario coverage and normalization boundaries are maintained in
[`render-diff.md`](render-diff.md).

The first round after closeout expanded the 12 hand-picked scenarios into a mechanically closed set: 20 scenarios, 40 fresh
captures, and 83 checkpoints covering all 22 slash commands and 28 reachable interface
states of the fixed baseline. The old I01 terminal-emitter differences that appeared in the new captures continue to keep their raw evidence; before the existing
disposition was applied, the visible text was re-checked checkpoint by checkpoint with ANSI and trailing padding stripped, first correcting real semantic differences such as
`/session`, title classification, narrow-screen Text wrap, clone session name, path autocomplete,
the multi-layer settings/auth/extension states, and the hotkeys table.

After Goal 16's closeout, the tool-state closure gained 7 items: bash line-count/byte/single-line truncation, empty output, nonzero
exit, timeout, and a parallel tool batch. The real contract of the fixed baseline's ordinary agent bash is at
`core/tools/bash.ts:248-306`: the detailed footer is retained inside the model result, but the TUI first strips that footer,
and then renders only one warning-colored `[Full output: ... Truncated: ...]`. Cadr previously echoed the result footer
as gray body text and then added a yellow warning as well, so it appeared twice on the same path. The gate
`POST-GOAL16-BASH-CONTEXT-TRUNCATION-RENDERS-ONE-BASELINE-WARNING` now locks separately that
the model-visible text is unchanged, that the TUI has only one warning, and the complete wording and the warning color; the new scenarios are captured state by state in both the wide and narrow
dimensions. The earlier 20 scenarios only proved that "the interface was reached" and had no input exceeding 50KB/2,000 lines,
so the duplicated hint was unobservable in both the 14,827 Cadr self-tests and the 40 differential captures.
