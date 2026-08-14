# GOAL v5: Wave 0 regression payoff + full TUI alignment

> Historical report: the `71efc6f0…` in this document records the audit anchor
> as it stood for Goal 5; from Goal 9 onward the current canonical baseline is
> `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.

## 0. Preconditions and positioning

- goal 4 has been accepted. Throughout, `docs/parity-map.md` is the work list, and the behavior baseline is still `71efc6f0c1909874ec8c944637a9ae7fc0e2d508` (a detached worktree used for auditing; taking pi-mono-legacy's 2026-04 state as the reference is forbidden).
- **The overall ordering has been settled by the user (2026-07-30)**: Wave 0 → TUI (formerly Wave 4, moved up; reason: no dependency chain and the highest user value) → Wave 1 → 2 → 3 → 5. This goal contains only the first two segments; later waves get their own goal after this goal is accepted, and work on them must not start early.
- Everything outside this goal's freeze scope — providers, the agent loop, the session format, the extension API (already frozen) and REPL behavior — must not be changed. Problems found outside the TUI are only recorded in docs/open-questions.md.

## 1. Part A: wrap-up commit + Wave 0

1. A docs-only commit of the goal 4 output: `docs/parity-map.md` and `docs/progress/goal-v4.md`, containing no other file.
2. Fill in two `U`-level regression tests:
   - `U-SEARCH-GITIGNORE` (corresponds to `3303-find-nested-gitignore.test.ts`: nested .gitignore semantics)
   - `U-TUI-RI` (corresponds to `regression-regional-indicator-width.test.ts`: regional indicator (flag emoji) width)
3. Zero production code changes. If a new test proves a real bug exists: record the symptom and the minimal reproduction, mark it blocked and wait for the user to confirm the fix approach; production code must not be modified silently.

## 2. Part B: full TUI alignment (formerly Wave 4)

### Objective

Taking the audit commit's `packages/tui` and the TUI side of coding-agent's behavior as the reference answer, bring cadr-tui up to component-level equivalence. The 25 `M` test files of the `tui` package in parity-map are the work list — at completion every file must be reclassified as `C`, or marked N/A file by file in the report together with the reason (N/A is limited to tests of mechanisms specific to the TS runtime, and must link to the divergence list).

### Explicit requirements

1. **Component list** (against the audit commit's `packages/tui/src/`): autocomplete, fuzzy, kill-ring, undo-stack, word-navigation, keybindings (including native-modifiers), stdin-buffer, terminal-colors, terminal-image (iTerm2/kitty/sixel to the baseline's support range), the whole overlay family (including CJK boundary behavior), and the existing gaps in select-list and markdown. Behavior follows the baseline item by item, and **a mechanism the baseline does not have must not be added** — any "improvement while we are at it" idea is recorded in open-questions.md and escalated for user adjudication.
2. **Architectural constraints are unchanged**: REPL and TUI are still two renderers of the same `CADR-AGENT` event stream; `--no-tui` is always available; the TUI layer must not intrude into provider/session/extension logic.
3. **Test specification**: every component gets a virtual-terminal snapshot test; the assertions of the baseline's 25+1 test files are ported file by file at the semantic level (not line-by-line translation); CJK/emoji/regional-indicator width regressions must be included. Tests first.
4. **Do not change existing passing behavior**: all 690 assertions from the goal 3 acceptance must stay green; only add, never delete (if an existing test needs adjustment, the reason must be stated item by item in the report).

### Acceptance criteria

1. After the `tui` rows of parity-map are updated, C/U/M are recounted and the `M` entries that are not N/A are zeroed; the summary table is updated in sync, and the update is recorded by a separate docs commit.
2. The full test suite is green, the total is strictly greater than 690, and the number added matches the new component list.
3. `./scripts/live-tui-smoke.sh` passes after being extended to cover the new components.
4. **A user manual-acceptance checklist** (issued by the advisor at acceptance, covering: the completion popup and selection, undo, kill-ring paste, word-wise jumping, in-terminal image display, overlay Chinese boundaries, and all of the above under resize) — the pinned baseline has only undo and no redo, and by the global alignment principle no redo is added; completion must not be declared before the user confirms item by item, and declaring it on one's own is invalid.
5. The stage report `docs/progress/goal-v5.md`: the component mapping table, the classification change per test file, and the exact commands and results.

## 3. Principles

- Tests first, stage gates, and non-TUI problems that are found are only recorded, not fixed.
- The manual-confirmation gate is unchanged: the extension API is not touched; if the TUI alignment work finds that a frozen interface must be touched, mark it blocked and wait for user adjudication.
- Pause when done and wait for the Wave 1 instruction.

## 4. Execution record

### 2026-07-30: Part A gate

- The Goal 4 output has been recorded as the pure-documentation commit
  `f9cefa43d`; the commit contains only `docs/parity-map.md` and
  `docs/progress/goal-v4.md`.
- `U-SEARCH-GITIGNORE` has been added tests-first to
  `test/cadr-cli/search-tools-test.lisp`; `cadr-cli` is 220 checks fully green,
  and production code was not changed.
- `U-TUI-RI` has been added tests-first to `test/cadr-tui/unicode-test.lisp`.
  The width assertions for a lone regional indicator, a complete flag and
  common streaming emoji pass, but the baseline wrapping assertion exposed a
  real difference:
  `wrap-text("      - 🇨", 9)` currently returns the first line `"      - "`
  (visible width 8), while the pinned TS baseline returns the first line
  `"      -"` (visible width 7). The minimal reproduction is exactly that
  input at width 9.
- The root cause is that `wrap-logical-line` hard-cuts by grapheme only and
  keeps the trailing space at the break point; the pinned baseline's
  `wrapTextWithAnsi` calls `trimEnd()` on overflow so a continuation line does
  not start with whitespace.
- Part A did not modify production code at the time, per the hard gate. The
  user then explicitly authorized porting the complete `wrapTextWithAnsi`
  semantics tests-first in Part B rather than applying an isolated patch; that
  difference has been fixed together with the ANSI/OSC 8, word/CJK boundary
  and trailing-whitespace semantics.

### Part B final mapping

The table below pins the test semantics and the implementation modules. All 25
original `M` files apply to cadr and have all been turned into `C`; there is no
N/A.

| pinned baseline test file | behavior that must be ported | cadr target module |
|---|---|---|
| `autocomplete.test.ts` | slash, path and `@` file fuzzy completion, quoting, hidden entries, symlinks and stable ordering | `autocomplete.lisp`, `fuzzy.lisp` |
| `bug-regression-isimageline-startswith-bug.test.ts` | recognize iTerm2/Kitty image escapes at any position, with no long-line crash and no false positive on text | `terminal-image.lisp` |
| `editor.test.ts` | history, Unicode/CJK, word wrapping, kill-ring, undo, autocomplete, character jumping, atomic paste segments and sticky column | `editor.lisp`, `kill-ring.lisp`, `undo-stack.lisp`, `word-navigation.lisp` |
| `fuzzy.test.ts` | in-order matching, boundary/consecutive scoring, alphanumeric interchange, multi-token ordering | `fuzzy.lisp` |
| `input.test.ts` | single-line input, horizontal scrolling, Unicode word deletion, kill/yank/undo and configurable keys | `input-component.lisp` |
| `keybindings.test.ts` | defaults, user overrides, deduplication, disabling, conflicts and defensive copies | `keybindings.lisp` |
| `keys.test.ts` | legacy/CSI/CSI-u/Kitty/modifyOtherKeys parsing, modifier keys, press/repeat/release | `keys.lisp` |
| `markdown.test.ts` | streaming Markdown, ANSI themes, lists/quotes/code/tables/links/images and width snapshots | `components.lisp`, `terminal-image.lisp` |
| `overlay-non-capturing.test.ts` | non-capturing overlay input dispatch, focus restoration, nesting and dynamic visibility | `overlay.lisp`, `renderer.lisp` |
| `overlay-options.test.ts` | anchor, row and column, percentage sizing, margins, maximum height and clipping | `overlay.lisp` |
| `overlay-short-content.test.ts` | still composes and cleans up correctly when the overlay is taller than the main content | `overlay.lisp`, `renderer.lisp` |
| `regression-overlay-cjk-boundary.test.ts` | no half grapheme is left behind when the overlay's start point falls inside a wide character or on its boundary | `unicode.lisp`, `overlay.lisp` |
| `select-list.test.ts` | single-lining of descriptions, minimum/maximum width of the main column, truncation callback and alignment | `components.lisp` |
| `stdin-buffer.test.ts` | chunked ESC/CSI/SS3/mouse/Kitty, timeouts, deduplication, paste, flush/clear/destroy | `stdin-buffer.lisp`, `keys.lisp` |
| `tab-width.test.ts` | tabs and ANSI/overlay slicing all measure width as 3 cells | `unicode.lisp`, `overlay.lisp` |
| `terminal-colors.test.ts` | parsing of OSC 11 and color-scheme reports, query consumption, and a late reply after a timeout | `terminal-colors.lisp`, `renderer.lisp` |
| `terminal-image.test.ts` | capability probing, iTerm2/Kitty encoding, size parsing, line count, deletion, fallback and OSC 8 | `terminal-image.lisp`, `components.lisp` |
| `terminal.test.ts` | Apple Return, Kitty negotiation/fallback, ordinary input replay and environment size | `terminal.lisp`, `keys.lisp` |
| `truncate-to-width.test.ts` | ANSI-safe contiguous-prefix truncation, ellipsis, padding, malformed escapes, Thai/Lao output normalization | `unicode.lisp` |
| `truncated-text.test.ts` | first-line truncation, exact width and vertical padding, with style resets not leaking | `components.lisp` |
| `tui-cell-size-input.test.ts` | the cell-size query reply is consumed, while a bare Escape and subsequent user input are still forwarded | `terminal-image.lisp`, `renderer.lisp` |
| `tui-overlay-style-leak.test.ts` | when overlay slicing drops a trailing SGR a reset is still appended, so subsequent cells are not polluted | `unicode.lisp`, `overlay.lisp` |
| `tui-render.test.ts` | differential/full repaint, resize, content shrinkage, style reset, Kitty image pre-cleanup and deletion | `renderer.lisp`, `terminal-image.lisp` |
| `word-navigation.test.ts` | forward and backward movement over ASCII punctuation, paths, CJK, whitespace and atomic paste segments | `word-navigation.lisp` |
| `wrap-ansi.test.ts` | ANSI/OSC 8 state across lines, word/CJK wrapping, trailing whitespace and a lone regional indicator | `unicode.lisp` |

Two further status changes:

- `regression-regional-indicator-width.test.ts`: `U → C`, with evidence in
  `unicode-test.lisp` and `wrap-ansi-test.lisp`.
- `tui-shrink.test.ts`: stays `C`, with the old behavior still covered by the new renderer regressions.

Part A's `3303-find-nested-gitignore.test.ts` goes `U → C` at the same time. The
TUI rows of the strict manifest therefore go from `C/U/M = 1/1/25` to
`27/0/0`, and the whole repository from `1/2/349` to `28/0/324`.

### Part B implementation

| component domain | implementation |
|---|---|
| ANSI/Unicode layout | complete word boundaries, ANSI/OSC 8 state across lines, trailing whitespace, CJK, emoji, regional indicators, tab=3, ANSI-safe truncation |
| input protocols | legacy, CSI/SS3, CSI-u, Kitty, modifyOtherKeys, native modifiers, press/repeat/release |
| input buffering | chunked ESC/CSI/paste, timeouts, Kitty deduplication, filtering of terminal capability replies, and the order of user input within the same batch |
| editing | multiline and single-line, history, sticky column, word-wise movement, character jumping, atomic paste, kill/yank/yank-pop, undo |
| completion | slash, paths, quotes, hidden files, symlinks, recursive `@` files and stable fuzzy ordering |
| overlay | anchor, percentage sizing, margins, clipping, focus/capture, non-capturing input, nesting and CJK/ANSI-safe composition |
| terminal capabilities | OSC 11 / color scheme, cell size, Kitty/iTerm2 capabilities and images, deletion, size and text fallback |
| components/rendering | Markdown, select list, truncated text, image component, differential/full repaint, resize, style isolation |

The pinned baseline has no redo; the implementation contains only the baseline's
undo and introduced no extra core mechanism. The real
`process-terminal` reuses `stdin-buffer`, and fixed two problems that only real
hardware exposed:
the terminal DA reply sticking to user input, and Return being wrongly
recognized as `Ctrl+-`. For both, a regression test was added first and the fix
then made per the pinned baseline's semantics.

### Automated acceptance evidence

```text
./scripts/test-cl.sh
  cadr-ai:    256/256
  cadr-agent: 156/156
  cadr-tui:   582/582
  cadr-cli:   225/225
  total:     1219/1219

./build.sh
  cadr build: SBCL lacks sb-core-compression; building an uncompressed image.
  exit 0; ./cadr regenerated

./cadr --version
  cadr 0.1.0

./scripts/live-tui-smoke.sh
  goal5 manual TUI smoke: overlay focus, CJK frame, image fallback,
  resize, and terminal restore passed
  live TUI smoke: autocomplete, undo, kill-ring, DeepSeek two-turn edit,
  resize, CJK, and terminal restore passed

bash -n scripts/goal5-manual-tui.sh \
  scripts/goal5-manual-tui-smoke.sh scripts/live-tui-smoke.sh
  exit 0
```

Existing test files only gained assertions; no assertion was deleted or
weakened. The final `git diff --check` passes. `U-TUI-RI`, the complete
`wrapTextWithAnsi` semantics and the real Return / terminal-reply path all
remain in the Goal 5 gate. `goal5-manual-tui.sh` loads only the test system and
does not enter the production image or the core API; it turns the manual
acceptance of images and CJK overlays into a repeatable operation in a real
terminal.

### Commit record

Implementation and tests are split logically into three commits:

1. `8bdb6461f2ee7659bad7d935a19c2b94e8acfaa5`
   `test(cadr): pin uncovered baseline regressions`
2. `e337deed7dd31f735b0949db388408cf32a21399`
   `feat(tui): port reference component semantics`
3. `b1d11c74eb11d4534bc392df59c5b18289ebfc46`
   `feat(cli): wire full TUI parity into interactive runtime`

### Manual acceptance passed

On 2026-07-30 the user confirmed item by item that manual acceptance passed:
completion and selection, undo, kill-ring, word-wise movement, terminal images
and fallback, overlay Chinese boundaries and dual-overlay focus, resize, and the
`--no-tui` line REPL all match the pinned baseline. Real-terminal screenshot
evidence covers CJK overlay boundaries, dual-overlay focus, image fallback,
resize and terminal restore.

`./build.sh` was re-run in the committed state; the four suites are 256, 156,
582 and 225 respectively, 1219/1219 fully green in total; when the current SBCL
lacks `sb-core-compression` the build downgrades by design and produces an
uncompressed `cadr`, and `./cadr --version` outputs `cadr 0.1.0`.
`./scripts/live-tui-smoke.sh` passes again.

`git status --short --untracked-files=no` produces no output; the
version-controlled working tree is clean. The unrelated untracked paths the user
asked to keep — `.codex`, `.tmp-home/` and `docs/.obsidian/` — still exist
unchanged and were not included in any commit. Goal 5 is complete; Wave 1 has
not started.
