# GAP-32 上游用例对应

范围是 v1.4.0 `packages/tui/src/components/editor.ts` 的补全触发（`buildTriggerPattern`、`buildDebouncePattern`、`setAutocompleteTriggerCharacters`）以及它用到的 `packages/tui/src/utils.ts` 空白和 CJK 标点。断言对着 `git show v1.4.0:<path>` 和本机 Node 22.22.0。编辑器其它行为（历史、折行、杀死环、粘贴标记、跳转）不是这一行的验收记录，表里标成范围外，并写明已经锁住它们的 FiveAM。

## 源码行为（没有单独的 `it`）

Node 22.22.0 对 v1.4.0 的 `buildTriggerPattern` / `isWhitespaceChar` / `autocompleteSeparatorRegex` / `setAutocompleteTriggerCharacters`，2026-10-23。

| 行为 | FiveAM | 状态 |
|---|---|---|
| `buildTriggerPattern(["@","#",wrapper])` 对 wrapper、wrapper+`foo`、两个 wrapper、空格+wrapper、空格+wrapper+`foo` 为真，对 `x`+wrapper 和 `x`+wrapper+`foo` 为假。wrapper 是 `(`、`[`、`{`、`<`、U+0060。debounce 模式在这些字符串上和触发模式相同 | `editor-wrapper-triggers-backtrack-like-v140` | 新增 |
| 编辑器输入该 wrapper 再输入 `f`，19ms 不请求，再 1ms 请求整段且 force 为假，菜单出现。`x` 加该 wrapper 不请求 | 同上 | 新增 |
| 默认触发只有 `@` 和 `#` 时，`(#`、`{#`、`[#`、`<#`、`` `# `` 为真，请求文本是整段，force 为假 | 同上，以及 `editor-default-triggers-follow-v140-boundaries` 对 `(` 和 `[` 后的 `#` | 新增 / 已覆盖 |
| `setAutocompleteTriggerCharacters` 留下单字符 `( ` 和 U+FF0C，丢掉长度不是 1 的 `$$`、`/`、空格、U+FEFF，以及重复项。`@` 和 `#` 始终在 | `editor-provider-trigger-keeps-fullwidth-comma-and-drops-bom`、`editor-custom-triggers-reset-when-the-provider-changes` | 已覆盖 |
| `/\s/` 与 `/\s/u` 都是 25 个码位，含 U+FEFF。`\uFEFF#` 为真，20ms 后请求且 force 为假 | `editor-bom-is-javascript-whitespace-before-hash` | 已覆盖 |
| `cjkPunctuationRegex` 扫出 56 个码位。`・#`（U+30FB）和 `〈#`（U+3008）为真。这些标点结束补全 | `editor-node-cjk-punctuation-bounds-hash-completion` | 已覆盖 |
| `prefix#123`、`问题#123` 不请求 | `editor-symbol-triggers-do-not-fire-mid-token` | 已覆盖 |
| 内置交互补全提供者不设 `triggerCharacters`。`packages/coding-agent/src/modes/interactive/interactive-mode.ts` 的 `createBaseAutocompleteProvider` 同样不设。扩展包装器把触发字符合并进提供者 | `interactive-autocomplete-provider-leaves-trigger-characters-nil` | 已覆盖内置字段为空。扩展包装器合并是范围外：两次验收都写内置字段为空，没有要求合并扩展包装器 |

## `packages/tui/test/editor.test.ts` 的 Autocomplete

| 用例 | FiveAM | 状态 |
|---|---|---|
| `triggers and debounces symbol completion after CJK punctuation` | `editor-default-triggers-follow-v140-boundaries` | 已覆盖 |
| `does not auto-trigger after CJK letters or for unprefixed paths` | `editor-symbol-triggers-do-not-fire-mid-token` | 已覆盖 |
| `requests path completion after CJK punctuation only on Tab` | `editor-symbol-triggers-do-not-fire-mid-token` 锁 `查看，/path/` 打完 20ms 不请求。Tab 的 force 在 `editor-text-autocomplete-matches-baseline-trigger-gate` | 已覆盖。样例是 `./` 的 Tab，不是 `查看，/path/` 这一个字符串 |
| `completes Chinese path prefixes after whitespace or CJK punctuation with Tab` | `goal24-cjk-punctuation-ends-autocomplete-path-prefix`、`goal24-cjk-path-requires-quotes` | 已覆盖路径前缀在标点处切开。磁盘上的 `文档/说明.md` 补全不在这次返修的断言里 |
| `ends unquoted trigger and debounce contexts at whitespace or CJK punctuation` | `editor-trigger-context-ends-at-whitespace-and-cjk-punctuation` | 已覆盖 |
| `re-triggers CJK path completion after accepting directories and deleting` | 无同名锁 | 范围外：接受目录后再删除并重开路径补全，不在 GAP-32 的 review-fail 里 |
| `auto-applies single force-file suggestion without showing menu` | `editor-custom-autocomplete-tab-applies-a-single-async-result`、`editor-natural-hash-completion-is-not-forced` | 已覆盖 Tab 对单个结果直接应用，以及 `#` 不是 force |
| `shows menu when force-file has multiple suggestions` | `editor-text-autocomplete-matches-baseline-trigger-gate` 在 `./` 上 Tab 后菜单可见 | 已覆盖菜单出现。样例文件名不是 `src` 和 `src.txt` |
| `keeps suggestions open when typing in force mode (Tab-triggered)` | 同上，force 在继续输入空格后仍为真 | 已覆盖 force 保持。没有锁 `readme.md` 这组过滤 |
| `debounces @ autocomplete while typing` | `editor-hash-autocomplete-debounces-without-provider-triggers`、`editor-autocomplete-debounce-is-pollable-and-latest-request-wins` | 已覆盖 |
| `re-queries the autocomplete picker when the cursor moves back into the command name` | 无 | 范围外：左箭头从参数区回到命令名。不是 `#` 触发 |
| `debounces # autocomplete while typing` | `editor-hash-autocomplete-debounces-without-provider-triggers` | 已覆盖 |
| `debounces custom triggerCharacters autocomplete while typing` | `editor-default-triggers-follow-v140-boundaries` 对 `$` 和 `-` | 已覆盖 |
| `resets custom triggerCharacters when provider changes` | `editor-custom-triggers-reset-when-the-provider-changes` | 已覆盖 |
| `aborts active @ autocomplete when typing continues` | `editor-custom-autocomplete-cancels-stale-requests-and-keeps-latest-result` | 已覆盖继续输入会取消旧请求。上游数的是 abort 监听次数 1 |
| `hides autocomplete when backspacing slash command to empty` | `editor-delete-to-empty-and-symbol-triggers-match-baseline` | 已覆盖 |
| `applies exact typed slash-argument value on Enter even when first item is highlighted` | 无同名锁 | 范围外：斜杠参数的 Enter 选择。不是 `#` 触发 |
| `selects first prefix match on Enter when typed arg is not exact match` | 无同名锁 | 范围外：同上 |
| `highlights unique prefix match as user types (before full exact match)` | 无同名锁 | 范围外：同上 |
| `selects first prefix match when multiple items match` | 无同名锁 | 范围外：同上 |
| `works for built-in-style command argument completion path (model-like)` | `slash-argument-completions-cover-thinking-and-extensions` | 已覆盖 `/thinking` 收到 `low`。不是 model 命令的整段样例 |
| `awaits async slash command argument completions` | 无同名锁 | 范围外：异步参数补全。不是 `#` 触发 |
| `ignores invalid slash command argument completion results` | 无同名锁 | 范围外：同上 |
| `does not show argument completions when command has no argument completer` | 无同名锁 | 范围外：同上 |
| Undo 里的 `undoes autocomplete` | `editor-autocomplete-popup-selection-and-undo` | 已覆盖 |
| Undo 里的 `does not trigger autocomplete during single-line paste` | 无同名锁 | 范围外：粘贴不开启补全。不在 review-fail 里 |

## 同文件其余 `it`

这些 describe 的每一条都是范围外。理由相同：它们不决定 `@` / `#` / 包装字符 / 空白 / CJK 标点的触发。对应的编辑器行为已经有 FiveAM，这次返修没有改那些断言。

| describe | 条数 | 已有 FiveAM |
|---|---|---|
| Prompt history navigation | 15 | `editor-history-state-and-normalization-match-reference` |
| public state accessors | 2 | 同上 |
| Backslash+Enter newline workaround | 5 | `editor-backslash-enter-and-programmatic-insert` |
| Kitty CSI-u handling | 3 | 范围外：键序列在 `test/cadr-tui/keys-test.lisp`，不是这一行 |
| Unicode text editing behavior | 12 | `editor-word-navigation-cjk-punctuation-and-multiline-kills`、`editor-incremental-cjk-and-emoji-input-never-renders-empty-grapheme` |
| Scroll indicators | 2 | `editor-autocomplete-centers-selection-after-bottom-border` |
| Grapheme-aware text wrapping | 8 | `editor-word-wrap-keeps-boundaries-and-wide-cells` |
| Word wrapping | 22 | 同上 |
| Kill ring | 20 | `editor-kill-ring-yank-pop-and-undo` |
| Undo（除上面两条） | 22 | `editor-kill-ring-yank-pop-and-undo`、`editor-paste-is-atomic-and-large-pastes-expand-literally` |
| Character jump (Ctrl+]) | 14 | `editor-character-jump-and-sticky-column` |
| Sticky column | 19 | `editor-character-jump-and-sticky-column`、`editor-sticky-column-navigates-wrapped-visual-lines` |
| Paste marker atomic behavior | 22 | `editor-paste-is-atomic-and-large-pastes-expand-literally`、`editor-renumbers-multiple-paste-markers-and-undo-restores-registry` |

`git show v1.4.0:packages/tui/test/editor.test.ts` 里 `it("` 共 192 条。Autocomplete 24 条，Undo 里点名的 2 条，其余 166 条落在这些 describe 里。外层 `describe("Editor component")` 自己没有 `it`。

## `packages/tui/test/autocomplete.test.ts`

四条 `it`（`extracts / from 'hey /'`、`extracts /A from '/A'`、`does not trigger for slash commands`、`triggers for absolute paths after slash command argument`）测路径前缀，不是触发字符。`autocomplete-slash-and-path-prefix-semantics` 锁路径前缀。范围外。

## 已记录的 review-fail

| 记录 | 结果 |
|---|---|
| U+FEFF 不是 JavaScript 空白，并且被叠进提供者触发 | `autocomplete-javascript-whitespace-p` 含 `#xfeff`。分隔为真，触发列表丢掉它。`editor-bom-is-javascript-whitespace-before-hash` |
| CJK 标点缺 28 个码位，U+30FB 和 U+3008 后的 `#` 不请求 | 56 个码位都在 `autocomplete-cjk-punctuation-p`。`editor-node-cjk-punctuation-bounds-hash-completion` |
| U+FF0C 被 `autocomplete-trigger-separator-p` 从提供者触发里滤掉 | `editor-provider-trigger-characters` 只按长度、`/`、`autocomplete-javascript-whitespace-p` 和重复项过滤。U+FF0C 留下。`editor-provider-trigger-keeps-fullwidth-comma-and-drops-bom` |
| 第二次验收：包装字符先被跳过，`(`、`(foo`、`((`、空格加 `(` 的上下文是 NIL | `autocomplete-unquoted-trigger-p` 在包装兼触发时回溯。`editor-wrapper-triggers-backtrack-like-v140` |

## 逐条名单

上面没有单独成行的 `it` 都在这里。状态都是范围外，理由见上一节的 describe 表。行号是 v1.4.0 `packages/tui/test/editor.test.ts`。

| 行 | describe | 用例 |
|---|---|---|
| 47 | Prompt history navigation | `does nothing on Up arrow when history is empty` |
| 55 | Prompt history navigation | `shows most recent history entry on Up arrow when editor is empty` |
| 66 | Prompt history navigation | `cycles through history entries on repeated Up arrow` |
| 86 | Prompt history navigation | `jumps to start before entering history from a non-empty draft` |
| 106 | Prompt history navigation | `navigates forward through history with Down arrow` |
| 131 | Prompt history navigation | `exits history mode when typing a character` |
| 142 | Prompt history navigation | `exits history mode on setText` |
| 156 | Prompt history navigation | `does not add empty strings to history` |
| 171 | Prompt history navigation | `does not add consecutive duplicates to history` |
| 185 | Prompt history navigation | `allows non-consecutive duplicates in history` |
| 202 | Prompt history navigation | `uses cursor movement instead of history when editor has content` |
| 218 | Prompt history navigation | `limits history to 100 entries` |
| 239 | Prompt history navigation | `places cursor at start after browsing history upward` |
| 254 | Prompt history navigation | `places cursor at end after browsing history downward` |
| 273 | Prompt history navigation | `allows opposite-direction cursor movement within multi-line history entry` |
| 292 | public state accessors | `returns cursor position` |
| 307 | public state accessors | `returns lines as a defensive copy` |
| 320 | Backslash+Enter newline workaround | `inserts backslash immediately (no buffering)` |
| 329 | Backslash+Enter newline workaround | `converts standalone backslash to newline on Enter` |
| 338 | Backslash+Enter newline workaround | `inserts backslash normally when followed by other characters` |
| 347 | Backslash+Enter newline workaround | `does not trigger newline when backslash is not immediately before cursor` |
| 363 | Backslash+Enter newline workaround | `only removes one backslash when multiple are present` |
| 378 | Kitty CSI-u handling | `ignores printable CSI-u sequences with unsupported modifiers` |
| 386 | Kitty CSI-u handling | `inserts shifted CSI-u letters as text` |
| 394 | Kitty CSI-u handling | `inserts shifted xterm modifyOtherKeys letters as text` |
| 404 | Unicode text editing behavior | `inserts mixed ASCII, umlauts, and emojis as literal text` |
| 423 | Unicode text editing behavior | `deletes single-code-unit unicode characters (umlauts) with Backspace` |
| 437 | Unicode text editing behavior | `deletes multi-code-unit emojis with single Backspace` |
| 450 | Unicode text editing behavior | `inserts characters at the correct position after cursor movement over umlauts` |
| 468 | Unicode text editing behavior | `moves cursor across multi-code-unit emojis with single arrow key` |
| 488 | Unicode text editing behavior | `preserves umlauts across line breaks` |
| 503 | Unicode text editing behavior | `replaces the entire document with unicode text via setText (paste simulation)` |
| 513 | Unicode text editing behavior | `moves cursor to document start on Ctrl+A and inserts at the beginning` |
| 525 | Unicode text editing behavior | `deletes words correctly with Ctrl+W and Alt+Backspace` |
| 575 | Unicode text editing behavior | `navigates words correctly with Ctrl+Left/Right` |
| 629 | Unicode text editing behavior | `stops at fullwidth Chinese punctuation (issue #4972)` |
| 661 | Unicode text editing behavior | `handles mixed CJK and ASCII word movement` |
| 707 | Scroll indicators | `centers scroll indicators on wide borders` |
| 720 | Scroll indicators | `keeps truncated scroll indicators within width and preserves their color (issue #6962)` |
| 745 | Grapheme-aware text wrapping | `wraps lines correctly when text contains wide emojis` |
| 760 | Grapheme-aware text wrapping | `wraps long text with emojis at correct positions` |
| 777 | Grapheme-aware text wrapping | `renders isolated Thai and Lao AM clusters without width drift` |
| 789 | Grapheme-aware text wrapping | `wraps CJK characters correctly (each is 2 columns wide)` |
| 809 | Grapheme-aware text wrapping | `handles mixed ASCII and wide characters in wrapping` |
| 825 | Grapheme-aware text wrapping | `renders cursor correctly on wide characters` |
| 841 | Grapheme-aware text wrapping | `does not exceed terminal width with emoji at wrap boundary` |
| 856 | Grapheme-aware text wrapping | `shows cursor at end of line before wrap, wraps on next char` |
| 878 | Word wrapping | `wraps at word boundaries instead of mid-word` |
| 900 | Word wrapping | `does not start lines with leading whitespace after word wrap` |
| 921 | Word wrapping | `breaks long words (URLs) at character level` |
| 935 | Word wrapping | `preserves multiple spaces within words on same line` |
| 947 | Word wrapping | `handles empty string` |
| 958 | Word wrapping | `handles single word that fits exactly` |
| 971 | Word wrapping | `wraps word to next line when it ends exactly at terminal width` |
| 981 | Word wrapping | `keeps whitespace at terminal width boundary on same line` |
| 991 | Word wrapping | `handles unbreakable word filling width exactly followed by space` |
| 999 | Word wrapping | `wraps word to next line when it fits width but not remaining space` |
| 1007 | Word wrapping | `keeps word with multi-space and following word together when they fit` |
| 1015 | Word wrapping | `keeps word with multi-space and following word when they fill width exactly` |
| 1023 | Word wrapping | `splits when word plus multi-space plus word exceeds width` |
| 1032 | Word wrapping | `breaks long whitespace at line boundary` |
| 1041 | Word wrapping | `breaks long whitespace at line boundary 2` |
| 1050 | Word wrapping | `breaks whitespace spanning full lines` |
| 1059 | Word wrapping | `force-breaks when wide char after word boundary wrap still overflows` |
| 1077 | Word wrapping | `splits oversized atomic segment across multiple chunks` |
| 1102 | Word wrapping | `splits oversized atomic segment at start of line` |
| 1122 | Word wrapping | `splits oversized atomic segment at end of line` |
| 1141 | Word wrapping | `splits consecutive oversized atomic segments` |
| 1163 | Word wrapping | `wraps normally after oversized atomic segment` |
| 1201 | Kill ring | `Ctrl+W saves deleted text to kill ring and Ctrl+Y yanks it` |
| 1214 | Kill ring | `Ctrl+U saves deleted text to kill ring` |
| 1234 | Kill ring | `Ctrl+K saves deleted text to kill ring` |
| 1247 | Kill ring | `Ctrl+Y does nothing when kill ring is empty` |
| 1255 | Kill ring | `Alt+Y cycles through kill ring after Ctrl+Y` |
| 1282 | Kill ring | `Alt+Y does nothing if not preceded by yank` |
| 1298 | Kill ring | `Alt+Y does nothing if kill ring has ≤1 entry` |
| 1311 | Kill ring | `consecutive Ctrl+W accumulates into one kill ring entry` |
| 1326 | Kill ring | `Ctrl+U accumulates multiline deletes including newlines` |
| 1358 | Kill ring | `backward deletions prepend, forward deletions append during accumulation` |
| 1374 | Kill ring | `non-delete actions break kill accumulation` |
| 1397 | Kill ring | `non-yank actions break Alt+Y chain` |
| 1416 | Kill ring | `kill ring rotation persists after cycling` |
| 1444 | Kill ring | `consecutive deletions across lines coalesce into one entry` |
| 1469 | Kill ring | `Ctrl+K at line end deletes newline and coalesces` |
| 1496 | Kill ring | `handles yank in middle of text` |
| 1511 | Kill ring | `handles yank-pop in middle of text` |
| 1536 | Kill ring | `multiline yank and yank-pop in middle of text` |
| 1564 | Kill ring | `Alt+D deletes word forward and saves to kill ring` |
| 1581 | Kill ring | `Alt+D at end of line deletes newline` |
| 1598 | Undo | `does nothing when undo stack is empty` |
| 1605 | Undo | `coalesces consecutive word characters into one undo unit` |
| 1630 | Undo | `undoes spaces one at a time` |
| 1652 | Undo | `undoes newlines and signals next word to capture state` |
| 1678 | Undo | `undoes backspace` |
| 1693 | Undo | `undoes forward delete` |
| 1710 | Undo | `undoes Ctrl+W (delete word backward)` |
| 1733 | Undo | `undoes Ctrl+K (delete to line end)` |
| 1760 | Undo | `undoes Ctrl+U (delete to line start)` |
| 1784 | Undo | `undoes yank` |
| 1801 | Undo | `undoes single-line paste atomically` |
| 1840 | Undo | `decodes CSI-u Ctrl+letter sequences inside bracketed paste (tmux popup)` |
| 1850 | Undo | `undoes multi-line paste atomically` |
| 1869 | Undo | `undoes insertTextAtCursor atomically` |
| 1888 | Undo | `insertTextAtCursor handles multiline text` |
| 1909 | Undo | `insertTextAtCursor normalizes CRLF and CR line endings` |
| 1926 | Undo | `undoes setText to empty string` |
| 1949 | Undo | `clears undo stack on submit` |
| 1971 | Undo | `exits history browsing mode on undo` |
| 2003 | Undo | `undo restores to pre-history state even after multiple history navigations` |
| 2042 | Undo | `cursor movement starts new undo unit` |
| 2075 | Undo | `no-op delete operations do not push undo snapshots` |
| 3079 | Character jump (Ctrl+]) | `jumps forward to first occurrence of character on same line` |
| 3092 | Character jump (Ctrl+]) | `jumps forward to next occurrence after cursor` |
| 3107 | Character jump (Ctrl+]) | `jumps forward across multiple lines` |
| 3123 | Character jump (Ctrl+]) | `jumps backward to first occurrence before cursor on same line` |
| 3136 | Character jump (Ctrl+]) | `jumps backward across multiple lines` |
| 3149 | Character jump (Ctrl+]) | `does nothing when character is not found (forward)` |
| 3162 | Character jump (Ctrl+]) | `does nothing when character is not found (backward)` |
| 3175 | Character jump (Ctrl+]) | `is case-sensitive` |
| 3195 | Character jump (Ctrl+]) | `cancels jump mode when Ctrl+] is pressed again` |
| 3210 | Character jump (Ctrl+]) | `cancels jump mode on Escape and processes the Escape` |
| 3228 | Character jump (Ctrl+]) | `cancels backward jump mode when Ctrl+Alt+] is pressed again` |
| 3243 | Character jump (Ctrl+]) | `searches for special characters` |
| 3263 | Character jump (Ctrl+]) | `handles empty text gracefully` |
| 3275 | Character jump (Ctrl+]) | `resets lastAction when jumping` |
| 3311 | Sticky column | `preserves target column when moving up through a shorter line` |
| 3334 | Sticky column | `preserves target column when moving down through a shorter line` |
| 3355 | Sticky column | `resets sticky column on horizontal movement (left arrow)` |
| 3380 | Sticky column | `resets sticky column on horizontal movement (right arrow)` |
| 3407 | Sticky column | `resets sticky column on typing` |
| 3431 | Sticky column | `resets sticky column on backspace` |
| 3455 | Sticky column | `resets sticky column on Ctrl+A (move to line start)` |
| 3476 | Sticky column | `resets sticky column on Ctrl+E (move to line end)` |
| 3500 | Sticky column | `resets sticky column on word movement (Ctrl+Left)` |
| 3523 | Sticky column | `resets sticky column on word movement (Ctrl+Right)` |
| 3549 | Sticky column | `resets sticky column on undo` |
| 3587 | Sticky column | `handles multiple consecutive up/down movements` |
| 3612 | Sticky column | `moves correctly through wrapped visual lines without getting stuck` |
| 3636 | Sticky column | `handles setText resetting sticky column` |
| 3656 | Sticky column | `sets preferredVisualCol when pressing right at end of prompt (last line)` |
| 3685 | Sticky column | `handles editor resizes when preferredVisualCol is on the same line` |
| 3710 | Sticky column | `handles editor resizes when preferredVisualCol is on a different line` |
| 3748 | Sticky column | `rewrapped lines: target fits current visual column` |
| 3774 | Sticky column | `rewrapped lines: target shorter than current visual column` |
| 3815 | Paste marker atomic behavior | `creates a paste marker for large pastes` |
| 3821 | Paste marker atomic behavior | `treats paste marker as single unit for right arrow` |
| 3846 | Paste marker atomic behavior | `treats paste marker as single unit for left arrow` |
| 3868 | Paste marker atomic behavior | `treats paste marker as single unit for backspace` |
| 3890 | Paste marker atomic behavior | `treats paste marker as single unit for forward delete` |
| 3906 | Paste marker atomic behavior | `treats paste marker as single unit for word movement` |
| 3930 | Paste marker atomic behavior | `undo restores marker after backspace deletion` |
| 3952 | Paste marker atomic behavior | `undo after paste marker deletion restores the paste registry` |
| 3967 | Paste marker atomic behavior | `undo after deleting the first of two paste markers restores both registry entries` |
| 3986 | Paste marker atomic behavior | `renumbers the paste registry in ascending id order when markers are out of order in text` |
| 4007 | Paste marker atomic behavior | `undo after setText restores paste markers and registry` |
| 4022 | Paste marker atomic behavior | `handles multiple paste markers in same line` |
| 4051 | Paste marker atomic behavior | `does not treat manually typed marker-like text as atomic (no valid paste ID)` |
| 4066 | Paste marker atomic behavior | `does not crash when paste marker is wider than terminal width` |
| 4089 | Paste marker atomic behavior | `does not crash when text + paste marker exceeds terminal width with cursor on marker` |
| 4124 | Paste marker atomic behavior | `wordWrapLine re-checks overflow after backtracking to wrap opportunity` |
| 4153 | Paste marker atomic behavior | `expands large pasted content literally in getExpandedText` |
| 4175 | Paste marker atomic behavior | `snaps to the paste marker start when navigating down into it` |
| 4210 | Paste marker atomic behavior | `preserves sticky column when navigating through paste marker line` |
| 4252 | Paste marker atomic behavior | `does not get stuck moving down from a multi-visual-line paste marker` |
| 4313 | Paste marker atomic behavior | `skips marker continuation VLs when preferred col falls in marker tail` |
| 4354 | Paste marker atomic behavior | `submits large pasted content literally` |
