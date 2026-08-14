# Goal 9 Part B phase report

> Status: the mechanical, runtime and live gates are all recorded in the ledger;
> on 2026-08-01 the user explicitly adjudicated that Part B passed acceptance
> and is closed, and only then did Part C begin.

## 1. Baseline and mechanical ledger

- Specification baseline: `earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.
- Baseline checkout: `/tmp/cadr-parity-74caa2649`, whose `git rev-parse HEAD` is
  byte-identical to the specification hash.
- `npm run build:offline` succeeded; the baseline source runner's `--version` is
  `0.83.0`.
- The baseline TUI was cold-started in a 100×32 `tmux` PTY and exited normally
  with `/quit`.
- Round three of [`visual-parity.md`](../visual-parity.md) has 35 mechanically
  numbered items in total: 2 `match`, 31 `mismatch (corrected)`, 2 `intentional difference`;
  0 `pending`.
- Both intentional differences are user adjudications: every selector cycles in
  both directions; the bash title never shows a timeout. The README registers
  only these two visual/interaction differences.

## 2. Behavior surfaces already aligned

- The complete dark/light semantic palette, truecolor/256-color conversion and
  local `39`/`49` restoration.
- fixed, unconfigured detect-once, auto DSR→OSC 11, dynamic notifications and
  hot reload of the custom theme schema.
- editor border, bash/thinking live border, fake cursor, IME marker, resize and
  terminal lifecycle.
- Markdown block/inline/table/link/code fence, the visible semantics of baseline
  syntax highlighting, state restoration.
- tool title/argument/output, real edit diff, collapse budget and semantic diff.
- All footer fields, extension status, context threshold, JS rounding, live
  auto-compaction.
- spinner, retry/compaction, 16 ms render throttle, terminal-progress keepalive,
  OSC 133 zones.
- session/tree/model/settings/trust/scoped-model selector, overlay, autocomplete
  and narrow-screen cropping; settings match the baseline's capability gating:
  25 items when supports-images=nil, and 27 when true, with Show images/Image
  width added. The gates are
  `GOAL9-B3-SETTINGS-OVERLAY-IS-AN-EXACT-BASELINE-SCREEN`,
  `GOAL9-B3-SETTINGS-CAPABILITY-AND-SUBMENUS-MATCH-BASELINE-CONTRACT` and
  `GOAL9-B3-EVERY-SETTINGS-SUBMENU-WRAPS-AT-BOTH-BOUNDARIES`.
- extension select now regresses through a real worker→live TUI overlay
  bridge→keyboard selection→return value, and no longer merely proves that an
  isolated framed selector renders; the gates are
  `GOAL9-B3-EXTENSION-SELECT-RUNS-THROUGH-THE-LIVE-TUI-OVERLAY-BRIDGE` and
  `GOAL9-B3-EXTENSION-CONFIRM-RUNS-THROUGH-THE-LIVE-TUI-OVERLAY-BRIDGE`.

No third-party dependency was added; the syntax highlighting is a pure Lisp
implementation.

## 3. First round: B3 rejection and runtime correction

The original B2 adequately covered only static constants, constructed components
and final strings; it did not bring the empty boundaries, the per-frame
streaming state and the error transitions of real event sequences into the
visual contract. In a real two-terminal A/B the user consequently found ten
escapes. `docs/visual-parity.md` has expanded the B2 method into a runtime-state
gate built on a faux provider plus a virtual terminal/PTY.

| Item | Regression gate | Original failure and fix | Why the original 4759 checks did not catch it |
|---|---|---|---|
| P0-1 `/fork` empty-candidate crash | `GOAL9-SELECT-LIST-EMPTY-AND-FIRST-ITEM-NAVIGATION-NEVER-WRITES-NEGATIVE-INDEX` | The old navigation first wrote the unsigned `selected` as `-1` and then clamped it; it now atomically computes a legal cyclic index before writing the slot, and an empty list is fixed at 0. | The old selector tests used only non-empty lists and navigated from the middle or downwards; they did not cover moving up from the first item, zero candidates after filtering, or Enter/render. |
| P0-2 CJK/emoji editing crash | `EDITOR-INCREMENTAL-CJK-AND-EMOJI-INPUT-NEVER-RENDERS-EMPTY-GRAPHEME`, `GRAPHEME-CLUSTERS-HANDLE-EMPTY-AND-DANGLING-JOINER-BOUNDARIES` | In Common Lisp the empty string is true, so autocomplete executed `(char value 0)` on `""`; at the same time a dangling ZWJ swallowed the cursor placeholder. The length is now checked first, and per-code-point grapheme boundaries are preserved. | The old tests inserted a complete grapheme in one go and attached no autocomplete provider; they never rendered the intermediate ZWJ states code point by code point, nor the empty path prefix produced by Unicode plus a trailing space. |
| P0-3 `session> <char>` | `GOAL9-B-TUI-BASH-STREAM-DOES-NOT-CREATE-SESSION-NOTICES` | The TUI connected the bash live stream to the notice stream, and bash flushes per character, so it generated one notice per line; the TUI no longer connects that stream to the notice channel. | notice, bash capture and the final tool result were tested separately, and per-character flushing was never driven through the real mode wiring with the virtual screen inspected. |
| P1-4 exit 7 displayed as success | `GOAL9-B-BASH-NONZERO-EXIT-IS-A-TOOL-ERROR`, `GOAL9-B-NONZERO-BASH-TOOL-RENDERS-ERROR-STATE` | A non-zero exit changed from an ordinary result to an error tool result; the runtime block is `:error` with a red background. Round two additionally removed a status glyph the baseline does not have. | The component tests hand-constructed `:error`, and the bash tests only looked for the exit footer; the real agent tool loop was never run to verify the result `is-error` through to the TUI state. |
| P1-5 selector does not cycle | `GOAL9-SELECT-LIST-NAVIGATION-WRAPS-AT-BOTH-BOUNDARIES` | up/down/page all take the modulus of the candidate count, so the first and last items cycle in both directions; zero candidates still do not move. | The old tests treated clamping as the correct behavior and did not take the baseline's first/last cycling as a runtime contract. |
| P1-6 long output and tool selection | `GOAL9-STREAMED-MULTILINE-ASSISTANT-OUTPUT-STAYS-LINE-ORIENTED-EVERY-FRAME`, `GOAL9-DEFAULT-TOOL-AND-PROMPT-CONTRACT-MATCHES-AUDIT-BASELINE` | 120 lines prove frame by frame that explicit line breaks are not lost along the event→renderer→virtual terminal path; the run-together lines seen in the field are not a Markdown line-break implementation. The actual deviation is further upstream: Cadr wrongly enabled 7 tools by default, and the descriptions/snippets/guidelines of four tools differed from the baseline; the default is now restored to `read,bash,edit,write` and the corresponding prompts are aligned verbatim, explaining and correcting the bash echo/sed preference. | The old tests instead froze the 7 tools as the “baseline”, the system prompt was only loosely checked for a substring, and the stream test had only one static delta, with no multi-line per-frame renderer/viewport. |
| P2-7 key hints/behavior | `GOAL9-P2-BASELINE-KEY-HINTS-AND-DECODER-ACTIONS-AGREE`, `GOAL9-P2-CTRL-C-CLEARS-BUSY-DRAFT-AND-ESCAPE-INTERRUPTS` | The default changed to Escape interrupt, Ctrl-C clear / double press to exit, Ctrl-D empty exit; both raw and Kitty input go through configurable app actions. | The old tests only compared the static hints and froze the wrong text; they did not verify the decoder→busy/idle action, the double-press timing or the virtual terminal. |
| P2-8 `/model` | `GOAL9-A2-OVERLAY-SELECTORS-FOCUS-CJK-AND-RESIZE-SNAPSHOTS` | Removed `Select Model`, which does not exist in the baseline; after the model catalogs refresh successfully, `Model catalogs refreshed.` is shown in the selector. | The old snapshot explicitly expected the wrong title, and it did not cover the second frame after the refresh completes. |
| P2-9 exit copy/elapsed time | `GOAL9-B-BASH-TOOL-RUNTIME-RENDERS-ELAPSED-AND-TOOK-LINES`, `GOAL9-B-TOOL-EVENTS-RECORD-RUNTIME-FOR-THE-LIVE-TUI` | The tool error changed to `Command exited with code 7`; bash start/end use the same monotonic clock, running shows `Elapsed`, and completion/failure shows `Took 0.0s`. | The old tests froze `Process exited...`, the tool block had no time state, and there was no start→end event clock test. |
| P2-10 tree/history/fork layout | `GOAL9-SESSION-SELECTOR-LAYOUT-MATCHES-BASELINE-PANEL-AND-LIST`, `GOAL9-SESSION-SELECTOR-RENAME-LAYOUT-MATCHES-BASELINE-SPACERS`, `GOAL9-TREE-SELECTOR-LAYOUT-MATCHES-BASELINE-TREE-VIEWPORT-AND-LABEL-SHELL`, `GOAL9-FORK-HISTORY-OVERLAY-MATCHES-BASELINE-MESSAGE-LAYOUT` | Aligned the header's left and right columns, the two hint lines, query/spacers, the 10-line centered viewport, the branch/collapse glyphs, path/cwd/count/age, scroll, the rename/label shell and the fork message layout. | The old tests verified only the filter/selection business semantics and a few selected-background constants; there was no line-by-line snapshot of the complete panel/viewport. |

Red-to-green record:

- P0-1's red phase was the same `UNSIGNED-BYTE datum -1` as the original
  incident; the empty/boundary/cycling gates are green at `33/33`.
- P0-2's red phase was `14 checks / 10 pass / 4 fail`, including the original
  empty-array index condition and three ZWJ intermediate-frame errors; the
  corresponding gates and the Unicode-related regressions are all green.
- P0-3's red phase was `2 checks / 1 pass / 1 fail`, with the notice receiving
  the per-character `alphadeltagamma`; in the green phase neither the notice nor
  the virtual screen contains it.
- P1-4's red phase showed the ordinary result, `:complete` and
  `Process exited...` at the same time; the underlying and the faux-agent TUI
  gates are now all green.
- P1-6's old exact tool/prompt contract was red at `0/1`; after the fix, the
  tool/prompt plus the 120-frame pure-integer output total `525/525`.
- P2-7/8's red phases respectively froze the wrong action/hint, `Select Model`,
  and a missing refresh-completion frame; after the fix, key/decoder is `10/10`,
  the virtual terminal `3/3`, and the model overlay `28/28`.
- P2-9's red phase failed outright at the newly added accessors/keywords because
  the tool block had no start/end state; after implementation both the component
  path and the real event path are green.
- P2-10's first runtime snapshot was `103 checks / 89 pass / 14 fail`; after
  implementing the fixes per the baseline and removing the non-baseline
  assumptions from the test data, the five layout gates are `100/100`.

Retained logs: `/tmp/cadr-goal9-b-p0-stream-{red,green}.log`,
`/tmp/cadr-goal9-b-p1-tool-error-{red,green}.log`,
`/tmp/cadr-goal9-b-p2-timing-{red,green}.log`.

## 3.1 Second round: B3 rejection and content-equivalence correction

The root cause exposed by round two is not “a few more constants were missed”,
but that the original 5399 checks still leaned towards event types, structure
and local substrings, and did not prove that the content is unchanged character
by character, that the provider capability matrix is complete, or that the
full-screen copy is verbatim equivalent. Every gate below first reproduces the
field red phase on the old implementation, and then turns green with the same
assertion.

| Item | Current source location | Regression gate | Original failure and fix | Why the original 5399 checks did not catch it |
|---|---|---|---|---|
| P0-1 leading space before a streamed number swallowed | `src/cadr-ai/providers/openai-completions.lisp:526-548` | `test/cadr-ai/openai-completions-test.lisp:135` `OPENAI-COMPLETIONS-STREAM-TEXT-IS-CHARACTER-EXACT-FOR-ALL-DELTA-BOUNDARIES`; `:182` `OPENAI-COMPLETIONS-NONSTREAM-TEXT-IS-CHARACTER-EXACT` | `append-chat-text-delta` now rejects only zero-length strings; it iterates over every single split point and over whitespace and digit boundaries. | The old fixtures only asserted the event structure; they never reassembled the text and compared it against the original character by character. |
| P0-2 Responses reasoning summary missing | `src/cadr-ai/providers/openai.lisp:423-450,467-529`; `src/cadr-cli/tui.lisp:1689-1749` | `test/cadr-ai/provider-streams-test.lisp:149` `OPENAI-RESPONSES-REASONING-SUMMARY-PARTS-EMIT-EXACT-THINKING-EVENTS`; `test/cadr-cli/tui-test.lisp:2334` `GOAL9-USER-AND-ASSISTANT-MESSAGE-SHELLS-MATCH-BASELINE` | Added the summary part/delta, the segmentation, the final backfill and thinking start/delta/end; the TUI reuses the muted italic renderer. | The old gates covered only DeepSeek `reasoning_content` and the generic renderer; there was no Responses fixture. |
| P0-3 unknown-model thinking downgrade | `src/cadr-ai/registry.lisp:384-474`; `src/cadr-cli/config.lisp:156-234` | `test/cadr-cli/config-auth-test.lisp:44` `UNKNOWN-DEEPSEEK-MODEL-INHERITS-FALLBACK-CAPABILITIES-FOR-EVERY-THINKING-LEVEL` | On a catalog miss it inherits the provider default model's protocol/capabilities/thinking map but keeps the user's model ID, covering every thinking level. | The old tests had only catalog hits; there was no unknown model × level payload/event matrix. |
| P0-4 read `offset=0` | `src/cadr-cli/tools/read.lisp:3-42` | `test/cadr-cli/file-tools-test.lisp:38` `READ-OFFSET-MATCHES-BASELINE-ZERO-NEGATIVE-AND-BEYOND-END-SEMANTICS` | 0 starts from the beginning, negative values clamp; the out-of-range copy is aligned verbatim. | The old tests covered only positive offset/limit, and errors were only asserted at the type level. |
| P1-5a user block spacing | `src/cadr-cli/tui.lisp:1758-1793,1872-1888` | `test/cadr-cli/tui-test.lisp:1112` `GOAL9-B3-USER-BLOCK-SPACING-AND-WRAPPING-MATCH-BASELINE` | Added the baseline spacer for the assistant→user transcript. | The old tests rendered the user component in isolation, with no adjacent transcript. |
| P1-5b user block wrapping | `src/cadr-cli/tui.lisp:1758-1793` | `test/cadr-cli/tui-test.lisp:1112` `GOAL9-B3-USER-BLOCK-SPACING-AND-WRAPPING-MATCH-BASELINE`, with the exact expectation at `:1129-1137` | Fixed-width continuation lines preserve the baseline's line-leading padding. | The old tests only searched for a content substring; there was no line-by-line snapshot. |
| P1-7 bash title timeout | `src/cadr-cli/tui.lisp:1124-1202` | `test/cadr-cli/tui-test.lisp:1223` `GOAL9-B3-EXPLICIT-BASH-TIMEOUT-NEVER-APPEARS-IN-TITLE`; `:1139` `GOAL9-B3-TOOL-TITLE-COPY-HAS-NO-STATUS-GLYPH-OR-DEFAULT-TIMEOUT` | After the user adjudication, only `$ command` is displayed whether the timeout is default or explicit. This differs intentionally from baseline `bash.ts:226-231`. | The previous round's tests only proved “no default timeout”, and treated the explicit timeout suffix as correct baseline behavior, so they could not discover that what the user actually required was still unmet. |
| P1-8 tool title glyph | `src/cadr-tui/components.lisp:1187-1197,1567-1599` | `test/cadr-cli/tui-test.lisp:652` `GOAL9-B-NONZERO-BASH-TOOL-RENDERS-ERROR-STATE`; `:1139` `GOAL9-B3-TOOL-TITLE-COPY-HAS-NO-STATUS-GLYPH-OR-DEFAULT-TIMEOUT` | The running/success/error titles drop `…/✓/×`; the state is expressed only by the background and the semantic color. | The old snapshot itself froze the newly added glyph, and did not carry out a verbatim cross-implementation comparison of the complete title. |
| P1-9 `/login` without arguments | `src/cadr-cli/interactive-services.lisp:7159-7208`; `src/cadr-cli/tui.lisp:3802-3807,3962-3963` | `test/cadr-cli/tui-test.lisp:1338` `GOAL9-B3-LOGIN-WITHOUT-ARGUMENTS-RENDERS-AUTH-METHOD-SELECTOR` | Added the two-level account/API key selection and masked key input. | The old tests covered only the explicit provider and an isolated provider selector, and did not go through argument-less command dispatch. |
| P2-10 `/model` copy | `src/cadr-cli/interactive-services.lisp:8012-8141` | `test/cadr-cli/goal9-b3-p2-regressions-test.lisp:7` `GOAL9-B3-MODEL-OVERLAY-COPY-MATCHES-UNSCOPED-BASELINE`; `test/cadr-cli/goal9-b3-overlay-contract-test.lisp:144` `GOAL9-B3-MODEL-OVERLAYS-HAVE-COMPLETE-BASELINE-LINE-CONTRACTS` | The unscoped state adds the `/login` copy and uses `> `; the scoped state and the refresh status have their own snapshots. | The old tests only searched for warning/model and style tokens; there was no full-screen line-by-line snapshot. |
| P2-11 `/tree` hints | `src/cadr-cli/interactive-services.lisp:5990-6035` | `test/cadr-cli/goal9-b3-p2-regressions-test.lisp:39` `GOAL9-B3-TREE-HELP-COPY-PRESERVES-ARROW-GLYPHS-AND-FILTER-ABBREVIATIONS` | Restored the arrow glyphs, the branch chord and the filter abbreviations. | The old tests verified only the action, and did not assert the final two hint lines. |
| P2-12 `/tree` tool entries | `src/cadr-cli/main.lisp:557-695`; `src/cadr-cli/interactive-services.lisp:5458-5605` | `test/cadr-cli/goal9-b3-p2-regressions-test.lisp:70` `GOAL9-B3-TREE-TOOL-RESULTS-RENDER-CALL-LABELS-NOT-RAW-OUTPUT` | The call ID is associated with the result, and a `[tool: args]` label is rendered instead of raw output. | The old fixtures had only an isolated result, with no real call/result association. |
| P2-13 vertical alignment (subsequent correction) | `src/cadr-cli/tui.lisp:2811-2834` | `test/cadr-cli/goal9-b3-p2-regressions-test.lisp:129` `GOAL9-B3-COLD-STARTUP-CONTENT-IS-TOP-ALIGNED`; the two short-content/boundary gates at `test/cadr-cli/goal9-b3-base-screen-contract-test.lisp:265-333` | At the time an empty session was special-cased with only `(and startup-lines (null entry-content))`, putting the padding after startup while still anchoring the editor/footer to the bottom; the user's later A/B proved this is not the baseline's policy. After the correction the root composition no longer inserts a viewport filler: cold start and short sessions stack from the top as a whole, filling exactly without cropping, and only overflow tail-scrolls. | The first test had only an empty startup, and the whole-screen expected hash was generated from the wrong implementation; there were no independent layout invariants for 1/3-round short sessions, exact fill and overflow. |

The red phases include the original space collapsing, zero thinking for
Responses, zero thinking for the unknown model, `offset must be at least 1`, and
the complete snapshot differences of the old overlay/tool/tree/cold-start. The
5614 checks recorded earlier are a round-two historical result and cannot serve
as round-three acceptance evidence. The `:start-end` suffix of the read title
was not modified, because it is the correct behavior of the baseline's
`formatReadLineRange`.

## 3.2 Third round: correction of evidence authenticity

Three of the previous round's “aligned” declarations do not hold: timeout
verified only the path where no argument is passed explicitly, yet left the
explicit timeout that the user required be covered outside the conclusion; write
verified only that the executor really returns a byte receipt, and did not
verify whether the TUI displays the call content or the receipt in the start/end
frames; and `/model` mis-reported the `tab scope (all/scoped)` hint still
retained by the scoped branch as deleted. All three passed off a local
implementation fact as evidence for the complete user path.

| Surface | Current source and gate | This round's facts | Why the old check missed it |
|---|---|---|---|
| bash timeout title | `src/cadr-cli/tui.lisp:1124-1202`; `test/cadr-cli/tui-test.lisp:1223` `GOAL9-B3-EXPLICIT-BASH-TIMEOUT-NEVER-APPEARS-IN-TITLE` | Neither the default nor the explicit timeout may appear in the title. That user adjudication conflicts with the audit baseline's explicit suffix, and is registered as intentional difference. | The old gate only proved that “a default timeout must not appear out of nowhere”, and deliberately kept the explicit suffix, so the test scope and the declared scope did not match. |
| write running/success copy | `src/cadr-cli/tui.lisp:1221-1249,1261-1501`; `test/cadr-cli/tui-test.lisp:1274` `GOAL9-B3-WRITE-TOOL-DISPLAYS-REQUEST-CONTENT-NOT-BYTE-RECEIPT` | Both running and success display the baseline preview of the request content; the model-side result has already been separately corrected verbatim against the baseline in section 3.3, and the display layer must not substitute the receipt for the content. | The old tests only tested the executor receipt and the tool status; they took no start/end snapshot of the complete output lines from event→block, and did not verify whether the receipt itself conforms to the baseline. |
| `/model` `tab scope` hint | `src/cadr-cli/interactive-services.lisp:8012`; `test/cadr-cli/goal9-b3-p2-regressions-test.lisp:7` `GOAL9-B3-MODEL-OVERLAY-COPY-MATCHES-UNSCOPED-BASELINE`; `test/cadr-cli/goal9-b3-overlay-contract-test.lisp:144` `GOAL9-B3-MODEL-OVERLAYS-HAVE-COMPLETE-BASELINE-LINE-CONTRACTS` | Neither of the two complete copy paths, unscoped and scoped, shows `tab scope (all/scoped)` any more; the scoped state retains only the `Scope: all | scoped` status title. | The old gate covered only the unscoped branch, and treated the hint left over in the scoped branch as an allowed difference; the declared scope was larger than the actually verified scope. |
| read collapsed preview | `src/cadr-tui/components.lisp:1213-1222,1514-1565`; `test/cadr-tui/components-test.lisp:423` `GOAL9-TOOL-COLLAPSED-PREVIEWS-MATCH-BASELINE-BUDGETS` | A successful read shows no result in the collapsed state; expanding shows the complete result; errors are always visible. | The old shared budget wrongly merged read and write into 10 lines and asserted only the crop count, without comparing against read's dedicated result renderer. |
| Markdown streaming fence | `src/cadr-tui/components.lisp:796-906`; `test/cadr-tui/components-test.lisp:764` `GOAL9-MARKDOWN-STREAMING-FENCES-MATCH-BASELINE-EXACTLY`; `test/cadr-cli/goal9-b-runtime-parity-test.lisp:174` `GOAL9-STREAMED-MARKDOWN-FENCE-IS-EXACT-THROUGH-THE-FULL-TUI-CHAIN` | The audit baseline's completed state itself retains the opening and closing fence lines, so the literal <code>```text</code> / <code>```</code> in the screenshot has been verified as a non-difference; this round only fixes the empty/partial streaming fence and the first empty code line after a fence, and locks the complete chain from the delta through the TUI state and the Markdown renderer to the virtual terminal. | The old tests leaned towards the completed state and token styling; they did not fix the complete line array frame by frame, and did not pass through the complete TUI chain. |
| the 15 overlay full-screen contracts | `test/cadr-cli/goal9-b3-overlay-contract-test.lisp:125` `GOAL9-B3-EVERY-OVERLAY-HAS-AN-EXACT-FULL-VIRTUAL-TERMINAL-SNAPSHOT` | model, model-scoped, settings, resume, fork, tree, scoped-models, trust, login-method, login-provider, logout-provider, api-key, import, extension-select and extension-custom all lock a complete virtual-screen SHA-256. The closeout self-check found that the first version of the list omitted the separate `/logout` surface; the newly added case first reproduced `14 pass / 1 fail` with a `PENDING` expectation, and then went green by locking the real full-screen SHA. | The original gates were scattered across substring, style-token and business-action tests and spot-checked only six overlays; and the first version of this round's enumeration in turn wrongly treated the renderer shared by login/logout as one and the same surface, without proving the full-screen output of every command surface. |
| settings capability gating | `test/cadr-cli/goal9-b3-p2-regressions-test.lisp:169` `GOAL9-B3-SETTINGS-OVERLAY-IS-AN-EXACT-BASELINE-SCREEN`; `:347` `GOAL9-B3-SETTINGS-CAPABILITY-AND-SUBMENUS-MATCH-BASELINE-CONTRACT`; `:497` `GOAL9-B3-EVERY-SETTINGS-SUBMENU-WRAPS-AT-BOTH-BOUNDARIES` | Same as the baseline: 25 items when supports-images=nil; when true, Show images/Image width are added according to capability, 27 in total; the submenus and boundary cycling are locked separately. | The old report mistook the 25 items of the nil branch for a fixed user adjudication, and did not cover the capability=true branch. |
| `@path` autocomplete | `test/cadr-cli/goal9-b3-overlay-contract-test.lisp:837` `GOAL9-B3-AT-PATH-AUTOCOMPLETE-HAS-AN-EXACT-FULL-SCREEN-AND-WRAPS` | The 40×8 complete virtual screen, the wrapping and the up/down bidirectional cycling are all locked. | The old checks only asserted the matching items or a local popup, with no complete screen and no wrap behavior. |
| extension raw/live | `test/cadr-cli/goal9-b3-overlay-contract-test.lisp:589` `GOAL9-B3-EXTENSION-SELECTOR-STYLES-COUNTDOWN-KEYS-AND-TOOL-TOGGLE-ARE-EXACT`; `:646` `GOAL9-B3-EXTENSION-SELECT-RUNS-THROUGH-THE-LIVE-TUI-OVERLAY-BRIDGE`; `:694` `GOAL9-B3-EXTENSION-CONFIRM-RUNS-THROUGH-THE-LIVE-TUI-OVERLAY-BRIDGE` | raw input, the countdown, key presses, the tool toggle, and the real worker→live TUI overlay bridge→keyboard→return value all have gates. | The old checks only proved that an isolated framed selector can render, and did not prove the real bridge and the return value. |
| the full provider thinking matrix | `test/cadr-ai/provider-streams-test.lisp:487` `EVERY-BUILT-IN-PROVIDER-AND-API-HAS-THINKING-LEVEL-HIT-MISS-CONTRACT` | Every built-in provider/API × every thinking level × catalog hit/miss asserts the payload and the thinking event behavior. | The old checks substituted a single provider's event structure for the complete capability matrix. |

`/sessions`, `/switch`, `/branch` and `/install` have all been deleted from
Cadr's built-in slash dispatch, TUI overlays and autocomplete, which matches the
baseline surface; they are no longer `/resume` aliases, and there is no hidden
command backend retained for the user to invoke. `/compact`, `/export` and
`/reload` remain direct actions per the baseline and do not open an overlay. The
deletion gate is `GOAL9-B3-NONBASELINE-COMMAND-NAMES-DO-NOT-OPEN-TUI-OVERLAYS`,
and the autocomplete set is separately locked by
`GOAL9-B3-BUILTIN-AUTOCOMPLETE-COMMAND-CONTRACT-MATCHES-BASELINE`.

Round three's B2 adds three hard gates: every display conclusion must cover a
real event→state→frame; renderer-specific semantics must not be tested by proxy
through a shared budget or an adjacent tool; overlays must be fully enumerated
by surface, and the complete line snapshot, the styling, the empty state, the
viewport and first/last cycling are every one of them indispensable. For the
complete comparison table see
[`visual-parity.md`](../visual-parity.md#b2-overlay-complete-line-by-line-contract).

## 3.3 Fourth round: verbatim audit of the model-visible tool result

This round splits a tool call into three independent contracts:
request/arguments, the result that is written into the session and returned to
the model, and the TUI renderer. The previous round fixed only write's display
layer, and even wrote the erroneous receipt up as “retained per the baseline”.
This round takes the seven tools of the registry `+builtin-coding-tool-names+`
as a closed set and audits them one by one against the audit commit's source.
`glob.lisp` is only a test/internal helper; it is not registered as a
model-callable tool and does not pose as an eighth built-in tool.

| Tool | Audit baseline `file:line` | Model-visible result contract | Cadr source and permanent gate | Conclusion |
|---|---|---|---|---|
| write | `packages/coding-agent/src/core/tools/write.ts:220-223` | `Successfully wrote N bytes to <original path>`; `N=JavaScript content.length`, i.e. the number of UTF-16 code units, not UTF-8 bytes. | `src/cadr-cli/tools/write.lisp:42`; `GOAL9-B3-WRITE-RESULT-MATCHES-BASELINE-UTF16-CODE-UNIT-COUNT` locks `N=3` using `中🙂`. | mismatch (corrected) |
| edit | `packages/coding-agent/src/core/tools/edit.ts:323-360`; `packages/coding-agent/src/core/tools/edit-diff.ts:257-292,347-352` | success, ENOENT, not-found, duplicate, no-change and overlap all preserve the original path, the edit index and the replacement count. | `src/cadr-cli/tools/edit.lisp:173-269,577-632`; `GOAL9-B3-EDIT-RESULT-AND-ERRORS-MATCH-BASELINE-COPY`. | mismatch (corrected) |
| read | `packages/coding-agent/src/core/tools/read.ts:246-315`; `packages/coding-agent/src/utils/image-process.ts:67-117`; `packages/coding-agent/src/utils/image-resize.ts:116-123` | user limit, 2000 lines, 50.0KB, first line over the limit, total line count / next offset; the image conversion/omission/resize coordinate notices are all verbatim and their figures use the same basis. | `src/cadr-cli/tools/read.lisp:3-100`, `src/cadr-cli/interactive-services.lisp:3174-3294`; `GOAL9-B3-READ-RESULT-NOTICES-MATCH-BASELINE-LINE-COUNTS`. | mismatch (corrected) |
| bash | `packages/coding-agent/src/core/tools/bash.ts:404-454` | empty output, non-zero exit, timeout, and the 2000-line / 50.0KB / single-long-line truncation notices; the random full-output path substitutes the value only, and the template is verbatim identical. | `src/cadr-cli/tools/bash.lisp:48-87,220-316`; `GOAL9-B3-BASH-RESULT-STATUS-AND-TRUNCATION-COPY-MATCH-BASELINE`. Additionally removed the non-command stderr injected by `setsid` on timeout. | mismatch (corrected) |
| find | `packages/coding-agent/src/core/tools/find.ts:282-346` | empty result, `N results limit reached. Use limit=2N...`, the 50.0KB notice; paths relative to the search root. | `src/cadr-cli/tools/find.lisp:10-71`; `GOAL9-B3-SEARCH-TOOL-RESULTS-MATCH-BASELINE-COPY-AND-COUNTS`. | mismatch (corrected) |
| grep | `packages/coding-agent/src/core/tools/grep.ts:178-356` | default limit 100; `path:line: text` / context spacing; 500-UTF-16-code-unit long lines; the match/byte/long-line notices and their figures. | `src/cadr-cli/tools/grep.lisp:10-136`; the same search gate locks the UTF-16 basis with CJK/emoji boundaries, and covers the byte boundary. | mismatch (corrected) |
| ls | `packages/coding-agent/src/core/tools/ls.ts:124-202` | `(empty directory)`, sorting / directory `/`, the entry limit and the 50.0KB notice. | `src/cadr-cli/tools/ls.lisp:11-73`; the same search gate and the existing limit gate. | mismatch (corrected) |

Runtime/operating-system native exceptions are only allowed to retain the
“exception-object wording that the implementation-language migration inevitably
causes” difference; all the success/error/continuation/truncation copy that the
project assembles itself and that enters the session has been aligned verbatim.
The provider request policy for the image capability is still owned by the
existing frozen `cadr-ai` layer; this table audits only the result content
produced by the read tool, and does not use it to modify the provider mechanism.

The red phase is not abstract inference: with `中🙂`, write got the old value
`7 UTF-8 bytes` while the baseline is `3 bytes`; the old copy/notices of edit,
read, bash and find/grep/ls failed in the same batch; the image branch then
reproduced the old `Converted image/bmp to PNG` and a corrupted BMP being
mistaken for the text `BM`. Why the previous 6878 checks missed it: write had
only ASCII, which made UTF-8 bytes and UTF-16 units happen to be equal; the
remaining tests asserted only file side effects, substrings, the details flag or
the TUI display, never took the executor result as a complete string snapshot,
and had no Unicode, no truncation boundaries and no corrupted image input. This
round's dedicated gate is `24/24`, and within it grep additionally uses
CJK/emoji to construct the boundary “fewer than 500 Common Lisp characters, more
than 500 UTF-16 code units”, to prevent the same class of counting basis from
being masked by ASCII again.

## 3.4 Fifth round: timeout noise and timing-determinism correction

`setsid: child ... did not exit normally: Success` is not ignorable test noise.
The old implementation merged `setsid`'s own stderr with the command's
stdout/stderr into the same pipe, so a wrapper exit race would contaminate the
model-visible tool result. `src/cadr-cli/tools/bash.lisp:141-163` now merges the
command's stderr into the command's stdout inside the child session with
`2>&1`, while giving `setsid` itself `:error-output nil`; no regex erasure is
used, so even if the user command's real output contains `setsid:` it will not
be wrongly deleted.

The timeout gate now uses `exec /usr/bin/tail -f /dev/null`, which never exits
on its own, and the deadline only starts after the process-group ID is
explicitly established; the only thing it can verify is the timeout, and it no
longer races the natural end of `sleep 1` over a 50 ms window. The permanent
gates are `GOAL9-B3-BASH-RESULT-STATUS-AND-TRUNCATION-COPY-MATCH-BASELINE` and
`GOAL9-B3-BASH-TIMEOUT-NEVER-LEAKS-WRAPPER-DIAGNOSTICS`
(`test/cadr-cli/tool-result-parity-test.lisp:159-219`); the latter separately
asserts that the result contains neither `setsid:` nor `cadr-bash-wrapper`.

The reason the original 6203 checks did not catch it: the bash case compared the
final copy exactly within a single 50 ms race, and neither isolated the wrapper
fd nor separately asserted that the wrapper vocabulary never appears; and the
preflight case treated “the shutdown thread has not finished within 50 ms” as
substitute evidence that shutdown had begun, so a slightly slower scheduler
would not yet have written the shutdown flag before release. Most of the
remaining concurrency gates likewise verified only the final state, and did not
prove that the intermediate state was actually reached. What the newly added
checks lock is an explicit state transition; they no longer win by running fast
enough.

The timing audit is not just fixing two known red lights. All the automated
surfaces below have been changed from “wait a short while and then guess the
state” to an observable state handshake:

| Scope | Old race | Current deterministic synchronization |
|---|---|---|
| agent shutdown/preflight/compaction/tree | `sleep 1ms` polling or a 50 ms reverse semaphore timeout | wait under the agent lock for the condition broadcast of the shutdown flag, and assert the active operation/mutation count; see `test/cadr-agent/shutdown-test.lisp:24-365`. |
| parallel tools, file mutation | using a 10–80 ms delay to manufacture an ordering | entered/release semaphores; the realpath alias additionally asserts that the same mutex is shared; see `tool-loop-test.lisp:102`, `part-b-tools-test.lisp:76`. |
| execution-env/bash subprocess | racing a short timeout against a bounded `sleep` process; background output relied on a delay | `tail -f /dev/null`, which never exits on its own; a FIFO explicitly handshakes the background writer's ready/release, and `/proc/<pid>` proves the cleanup; see `execution-env-test.lisp:182`, `bash-test.lisp:80`. |
| SSE/real HTTP socket | the delayed stream and the second frame relied on a wall-clock sleep | stream entered/release semaphores; the first SSE callback releases the server's second frame; see `test/cadr-ai/http-test.lisp:47-177`. |
| RPC prompt/UI/bash | 10 ms polling of the thread, the pending hash and the output | join the captured worker; a newline-notifying Gray stream drives the JSON record handshake; the bash worker joins/aborts synchronously; see `test/cadr-cli/helpers.lisp:46-95`, `rpc-test.lisp:5-380`. |
| footer debounce/render | 10–50 ms sleep/poll | inject a monotonic clock, and call and assert step by step on either side of the debounce boundary; see `interactive-services.lisp:2113-2290`, `part-b-interactive-test.lisp:668-883`. |
| extension/TUI overlay | worker polling and then a fixed 20 ms wait | the overlay-installed callback signals a semaphore; the git daemon reads `Ready to rumble`; see `goal9-b3-overlay-contract-test.lisp:650-742`, `extensions-test.lisp:614-686`. |
| TUI command/event | polling the footer/model/theme/progress flags | the command callback completes the state update before returning; busy abort uses a semaphore; the RPC workflow joins the worker; see `tui-test.lisp`, `goal9-a2-interactive-test.lisp:115`, `goal9-a2-workflows-test.lisp:187`. |
| PTY smoke | a fixed sleep after sending keys/resize and then a screenshot; waiting for the deleted `sessions` copy and the old prompt glyph | every action polls its exact visible state or the terminal-restored marker; the current slash surface, the glyph-free editor and the `/quit` path are corrected item by item; see `scripts/{goal5-manual-tui-smoke,live-tui-smoke}.sh`. |

The remaining items of the whole-repository `sleep`/timeout audit fall into
three classes, none of which lets the passage of time decide whether an
assertion is true:

- `test/cadr-tui/manual-acceptance-test.lisp:250` only rate-limits the
  manual-interaction event loop; the automated FiveAM tests never call that
  runner.
- The `"sleep 1"` at `test/cadr-cli/tui-test.lisp:1178-1207` is a title fixture
  that is never executed; the `timeout-ms` of extension/RPC/sdk is
  payload/immediate-cancel semantics, and the retry tests inject a fake sleep
  function.
- The `sleep` retained in the process/PTY smokes only lowers the polling
  frequency inside a bounded loop; the success condition is a port file, a Unix
  socket, a request marker, an exact screen state or a restore marker, and there
  is no longer any path that asserts directly after a fixed delay.

An earlier report wrote the first-run failure of
`SHUTDOWN-DURING-PREFLIGHT-PREVENTS-PROVIDER-START` up as “all green on an
immediate rerun”; that closeout verdict is wrong and is now explicitly
withdrawn. From now on, if any test needs a rerun to go green, this round is not
finished: the first red light must be kept, the nondeterminism located and
changed to explicit synchronization, and the second result must not be used to
overwrite it.

## 3.5 Sixth round: live OAuth order dependency and shared-state correction

The advisor's `6220 checks / 6216 pass / 1 skip / 3 fail` is not a different
test scale: `6220 = cadr-ai 1911 + cadr-agent 623 + cadr-tui 1178 + cadr-cli
2508`. The three fails are exactly the status, stdout and stderr assertions of
`LIVE-OPENAI-CODEX-EXPLICIT-MODEL-USES-OAUTH-CREDENTIAL`; after the CLI suite
failed, ASDF did not continue to storage/server/evals/protocol.

The five runs of `6919/6918/1/0` declared earlier were real run results at the
time, but they are not enough to prove the refresh path. During those five runs
the access token in the canonical `~/.cadr/auth.json` was still far from the
5-minute proactive refresh window, and the file's SHA-256 was throughout
`1b2d7e98b4d1576d0df894b3188a7ff161f0eb885e074320780d7db99e080539`; only the
fresh-access path was therefore verified. Reporting that as covering the live
OAuth lifecycle overstates the scope of the evidence.

The old CLI live tests copied the whole real `auth.json` into a temporary HOME
each time. The isolated CLI called `resolve-oauth-credential` on the copy; on
entering the refresh window, the new access/refresh token returned by OpenAI was
written back only to the temporary copy, while the canonical file still held the
already-consumed old refresh token. A later test or a later suite run copying
from canonical again would then reliably use an invalid token. The deterministic
rotating-token simulation reproduces this directly: independent copy A refreshes
successfully, copy B gets `invalid_grant`, and canonical still holds the old
token; after switching to an atomic refresh on the shared canonical, two reads
refresh only once and canonical holds the new token.

The current mechanism has only one source of truth:
`test/cadr-live-support.lisp` rereads the canonical auth every time and does not
cache the user's credential; if the credential has already entered the refresh
window, it performs one read-modify-write through the existing
`auth-storage-modify` file lock, atomically writing the rotated token back to
canonical, and then writes that same fresh credential into the CLI's temporary
store. The eval live tests reuse the same helper and no longer read and refresh
on their own. That helper is a separate ASDF test system, and CLI/evals no
longer each compile and load their own copy of the same source.

The real-file safety conclusion: a refresh really must be written back to the
real canonical file, otherwise a rotating refresh token would inevitably leave
the user's credential as a dead value; that write happens only in the expiry
window, and it preserves mode `0600` and the other providers. The
fresh-credential path compares the file contents verbatim to prove that nothing
is rewritten; the failed-refresh path is likewise verbatim unchanged; and
canonical is asserted verbatim unchanged before and after the isolated CLI
invocation. The permanent gates are:

- `LIVE-OAUTH-SUITE-CREDENTIAL-REFRESHES-ONCE-AND-WRITES-THROUGH-CANONICAL-STORE`
- `LIVE-OAUTH-SUITE-DOES-NOT-REWRITE-A-FRESH-CANONICAL-CREDENTIAL`
- `LIVE-OAUTH-SUITE-FAILED-REFRESH-KEEPS-CANONICAL-CREDENTIAL-INTACT`
- `LIVE-OAUTH-SUITE-REREADS-THE-CANONICAL-STORE-ON-EVERY-USE`
- `LIVE-OPENAI-CODEX-EXPLICIT-MODEL-USES-OAUTH-CREDENTIAL`

This difference is not “it passes on my side, the advisor's environment has a
problem”: both sides used the same user credential and the same test command,
and what decided which path the old code took is whether the runtime token had
already entered the refresh window, and whether canonical had already been
consumed by an earlier copy's refresh. The current five runs use the corrected
`4fdc38b05`; the advisor's three failures use the old `62eee0579`. The
deterministic simulation is responsible for covering the rotation branch, and
the five real runs in a row are responsible for covering the complete suite
ordering. Order dependency and shared-state contamination now rank with
flakiness: going green once or on one machine cannot close the case; it must be
proved that the suite is order-independent and that the canonical state is safe,
and it must be locked down with consecutive full runs.

## 3.6 Seventh round: real LLM variation and correction of the evidence basis

After the OAuth fix, the advisor reran three times in a row;
`LIVE-OPENAI-CODEX-EXPLICIT-MODEL-USES-OAUTH-CREDENTIAL`, previously red without
fail, passed all three times, confirming that `4fdc38b05` only fixes the
copying/sharing of test credentials and does not mask a production refresh
defect. Across the three rounds the SHA-256 and the `0600` permissions of the
real auth also did not change.

But the three rounds' mixed full results are: round one
`6436 checks / 5 fail`, with the failure surface being
`LIVE-DEEPSEEK-SELF-EXTENSION-WRITE-RELOAD-AND-INVOKE`; rounds two and three are
both `6933 checks / 0 fail`. The user's input did not provide the raw per-round
pass/skip numbers for the three rounds, and this report does not
reverse-engineer and fill them in. Round one stopped after evals, with no
protocol result; this is not a timing race or shared-state contamination, but
the inherent behavioral variation of a model that does not necessarily complete
the write-extension, reload and tool-invocation loop every time.

The earlier “five green runs” of section 5 is therefore only a set of historical
run records that include live, and can no longer serve as deterministic
evidence. live must not fake stability through handshakes, relaxed assertions,
or rerunning until green. Its gate placement, exit semantics and pre-release
Part D responsibility went into a blocked proposal at the time:
[`goal-v9-live-test-gating.md`](../proposals/goal-v9-live-test-gating.md); for
the subsequent adjudication and implementation see section 3.7.

The permanent reporting discipline takes effect immediately from this round:
whenever “N green runs in a row” is declared, the complete
`checks / pass / skip / fail` must be attached for every single run, and the
entry point must not contain a real network/LLM call; a run that includes live
may only report its actual results stage by stage, and no failure may be
overwritten by a later green.

## 3.7 Eighth round: separating the deterministic and live gates

The user has approved the live gate proposal item by item. `e779ee828` moves the
three networked live files out of the ordinary ASDF test systems, and adds
dedicated `cadr-*/live-tests` systems plus a unified `./scripts/test-live.sh`.
`test/cadr-cli/live-auth-test.lisp` still remains in the deterministic CLI
suite: it uses only a temporary auth store and network stubs, it is the
deterministic gate for the OAuth rotation defect, and it is not a fake live.

This separation moves closer to the actual effect of the fixed baseline's
official CI: the baseline still writes the live blocks inside Vitest, but CI
does not inject provider credentials, so only the deterministic part actually
executes; Cadr expresses the same boundary with an explicit entry point. This is
a difference in organization, it is registered in the README, and it changes no
live prompt, assertion, model or credential gating, nor any production `src/`.

Raw summary of five consecutive runs of the deterministic entry point:

| run | checks | pass | skip | fail | log |
|---:|---:|---:|---:|---:|---|
| 1 | 6921 | 6921 | 0 | 0 | `/tmp/cadr-goal9-deterministic-1.log` |
| 2 | 6921 | 6921 | 0 | 0 | `/tmp/cadr-goal9-deterministic-2.log` |
| 3 | 6921 | 6921 | 0 | 0 | `/tmp/cadr-goal9-deterministic-3.log` |
| 4 | 6921 | 6921 | 0 | 0 | `/tmp/cadr-goal9-deterministic-4.log` |
| 5 | 6921 | 6921 | 0 | 0 | `/tmp/cadr-goal9-deterministic-5.log` |

The separate live entry point ran once in full, without exiting at the first
item:

| live item | Status | Reason/coverage |
|---|---|---|
| `LIVE-DEEPSEEK-CHAT-COMPLETIONS-STREAMS` | pass, 5 checks | DeepSeek stream |
| `LIVE-ANTHROPIC-STREAM-PRESERVES-TWO-TURN-CONTEXT` | skip, 1 check | `ANTHROPIC_API_KEY is not set` |
| `LIVE-DEEPSEEK-PRINT-MODE-EMITS-ONLY-FINAL-TEXT` | pass, 3 checks | DeepSeek CLI print |
| `LIVE-OPENAI-CODEX-EXPLICIT-MODEL-USES-OAUTH-CREDENTIAL` | pass, 4 checks | canonical OAuth → isolated CLI |
| `LIVE-DEEPSEEK-EVAL-SMOKE` | pass, 4 checks | explicit DeepSeek eval |
| `LIVE-OPENAI-CODEX-EVAL-SMOKE-USES-EXPLICIT-MODEL-AND-REAL-OAUTH` | pass, 4 checks | explicit Codex eval |
| `LIVE-DEEPSEEK-SELF-EXTENSION-WRITE-RELOAD-AND-INVOKE` | pass, 6 checks | self-extension behavior |
| `LIVE-DEEPSEEK-REPOSITORY-FAIL-FIX-PASS-LOOP` | pass, 5 checks | repository repair behavior |

The summary is `8 items / 7 run / 7 pass / 1 skip / 0 fail`, and the check count
is `32 checks / 31 pass / 1 skip / 0 fail`. This round has no failed item; if
there were a failure, the runner would print for every item the complete FiveAM
check/condition, the captured output, `suspected product defect / suspected model-output variance /
cannot determine` and the grounds for the judgement, and would return exit `1` only
after all items had finished. The permanent regressions
`LIVE-RUNNER-CONTINUES-AFTER-A-FAILED-ITEM`,
`LIVE-REPORT-LISTS-EVERY-ITEM-AND-COMPLETE-COUNTS` and
`DETERMINISTIC-SYSTEMS-EXCLUDE-NETWORK-LIVE-FILES` lock these boundaries.

Part D's `verify.sh` must invoke the available live, and a failure blocks the
release by default; only the user, after seeing the complete report above, may
explicitly lift it, and the script must not ignore it automatically. Per the
established adjudication, that wiring lands in Part D; no incomplete verifier is
created early.

## 4. Color byte evidence

Capture from the same dark palette input:

```text
truecolor accent-fg = ESC[38;2;138;190;183m
truecolor user-bg   = ESC[48;2;52;53;65m
256-color accent-fg = ESC[38;5;109m
256-color user-bg   = ESC[48;5;59m
foreground reset    = ESC[39m
background reset    = ESC[49m
```

Raw capture: `/tmp/cadr-goal9-color-capture.txt`.

## 5. Round-six historical mixed-run evidence (non-deterministic)

After the code commit `4fdc38b05`, the same `./scripts/test-cl.sh` was executed
five times in a row using the current user settings/auth state. The raw numbers
of those five rounds are below, but that entry point contains real LLM calls, so
this table must no longer be used to declare a deterministic “all green in a
row”:

| run | checks | pass | skip | fail | full log |
|---:|---:|---:|---:|---:|---|
| 1 | 6933 | 6932 | 1 | 0 | `/tmp/cadr-live-auth-full-1.log` |
| 2 | 6933 | 6932 | 1 | 0 | `/tmp/cadr-live-auth-full-2.log` |
| 3 | 6933 | 6932 | 1 | 0 | `/tmp/cadr-live-auth-full-3.log` |
| 4 | 6933 | 6932 | 1 | 0 | `/tmp/cadr-live-auth-full-4.log` |
| 5 | 6933 | 6932 | 1 | 0 | `/tmp/cadr-live-auth-full-5.log` |

The single skip in every round is
`LIVE-ANTHROPIC-STREAM-PRESERVES-TWO-TURN-CONTEXT`, because this machine has no
`ANTHROPIC_API_KEY`; the DeepSeek and Codex OAuth live gates both actually
executed. The layered re-check was `cadr-agent 623/623`, `cadr-cli 2522/2522`,
`cadr-ai 1911 checks / 1910 pass / 1 skip / 0 fail`.

The canonical auth SHA-256 was
`1b2d7e98b4d1576d0df894b3188a7ff161f0eb885e074320780d7db99e080539` before and
after every one of the five rounds; this real run did not trigger a refresh and
did not rewrite the user's auth. The rotation write-back is covered by the
deterministic tests of section 3.5; a five-run streak on a fresh token must not
be passed off as evidence for the refresh branch.

The external PTY smokes were likewise switched to state synchronization and then
actually run:

- `./scripts/goal5-manual-tui-smoke.sh`: overlay focus, CJK, image fallback,
  resize and terminal restore all pass.
- `./scripts/live-tui-smoke.sh`: the current slash surface,
  autocomplete/undo/kill-ring, two rounds of DeepSeek write/edit, resize, CJK
  and `/quit` terminal restore all pass; log
  `/tmp/cadr-goal9-live-tui-smoke.log`.

Residual grep commands and raw output:

```text
$ rg -n 'strip-setsid-timeout-noise|:error-output :output' src/cadr-cli/tools/bash.lisp
(no output; exit 1)

$ rg -n '2>&1|:error-output nil' src/cadr-cli/tools/bash.lisp
153:             "printf '%s' \"$$\" > \"$1\"; exec /bin/bash -lc \"$2\" 2>&1"
163:            :error-output nil

$ rg -n '\(sleep\s' test
test/cadr-tui/manual-acceptance-test.lisp:250:                  (sleep 0.02d0))

$ rg -n 'setsid:|cadr-bash-wrapper' test/cadr-cli/tool-result-parity-test.lisp
218:      (is (null (search "setsid:" message)))
219:      (is (null (search "cadr-bash-wrapper" message))))))
```

The model-visible executor result and the TUI preview still have separate gates;
the UTF-16 receipt semantics of write were not changed by this round's timing
correction.

## 6. Round-four isolated build artifacts (historical evidence)

The hashes below are round-four artifacts; they do not pose as round-five
source-build evidence. The acceptance threshold the user specified for this
round is 5 consecutive full runs plus the retained smokes; rebuilding the
release binaries was not required:

```text
compression branch: SBCL lacks sb-core-compression; both builds used the documented uncompressed fallback
build exit: build.sh=0; build-server.sh=0
cadr mode/size/version: -rwxr-xr-x 66462720 bytes; cadr 0.1.0
cadr-server mode/size/version: -rwxr-xr-x 57220840 bytes; cadr-server 0.1.0
cadr SHA-256: 53c3adf8ca0f7af0dba166e6668be23f01ce96762e99c10b7f94a5c1193a99d6
cadr-server SHA-256: a973aaa04f1d0f85ee6a59fbe767209fb45b0269e89df48790af05c0a606da61
logs: /tmp/cadr-goal9-build.log; /tmp/cadr-goal9-build-server.log
```

## 7. Commits of rounds three to six

| commit | content |
|---|---|
| `3b41becd3` | the provider thinking capability matrix and byte-level pattern gates |
| `94c1b0822` | tool preview, Markdown and editor autocomplete |
| `7d89b096b` | the complete overlay contracts, settings/auth/extension glue and runtime gates |
| `d77321774` | docs/README closure and final evidence |
| `034f69e0f` | state explicitly that the completed-state Markdown fence is a verified non-difference |
| `21ae81f13` | add the separate full-screen SHA for `/logout`, and refresh the round-three full-run figures |
| `1c442d271` | round-four model-visible tool result and permanent regression gates |
| `be243c0ab` | isolate the `setsid` wrapper stderr, the deterministic timeout target and a noise-free regression |
| `baaf6dd75` | the whole set of timing tests switched to semaphore/condition/join/FIFO/injected clock |
| `29e9bade9` | PTY smokes changed to observing the actual screen/marker state, no longer asserting after a fixed delay |
| `4fdc38b05` | live OAuth shared canonical refresh, isolated credential injection and the deterministic rotation regression |
| `e779ee828` | deterministic/live ASDF separation, the complete live summary and the failure-classification regression |

After committing, it must be confirmed again that this round's paths have no
uncommitted changes; the user's pre-existing
`docs/acceptance/goal-v8-final.md`, `.obsidian/`, `goal9.md`, `goal10.md` and
`scripts/__pycache__/` do not belong to this round and remain as they are.

## 8. The B3 manual gate

For the exact startup command, the environment constraints and the 11
per-scenario check items see
[`visual-parity.md`](../visual-parity.md#b3-two-terminal-ab-gate).

## 9. Final user acceptance

After the advisor's independent re-review, the user explicitly adjudicated that
Part B is closed. The re-review evidence is: the deterministic suite gave
`6921 checks / 6921 pass / 0 skip / 0 fail` three times in a row, identical
digit for digit; the item-level and check-level summary format of
`test-live.sh` conforms to the adjudication, seven of the eight items actually
ran and passed, and one explicitly skipped for lack of `ANTHROPIC_API_KEY`. That
adjudication covers the B3 two-terminal A/B gate listed above and all subsequent
corrections, and it is no longer in the “awaiting user confirmation” state.

Current disposition: `Part B has passed user acceptance and is closed`.
