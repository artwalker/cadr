# Goal 20 Part K8 — cadr-tui

50 Lisp files / 23,711 lines at start (38 non-mermaid + 12 mermaid).
Generated `mermaid/width-data.lisp` untouched.

## keep

All §2.8 no-rewrite files kept. I reasons still match:
wire tokens, generated width table, fixture-locked layout,
keybindings.json string registry, CLOS protocol stubs.

`keybindings.lisp` stayed no-rewrite. It now hosts
`+logical-key-events+` and the rebuild-time event-kind table
because that table is the invert of resolved bindings, not a
new I-hole in this file.

## 29 needs-rewrite

| File | I0 |
|---|---|
| autocomplete | dead when gone |
| image | `fallback-lines` |
| markdown | table width vectors |
| select-list | `clamp-select-index`, height 5 |
| tool-block | pop remaining, no reparse |
| loaders | `loader-frames` / `loader-interval-seconds` |
| protocol | `:documentation` on six defgenerics |
| settings-list | `nthcdr` walk |
| text-box | `:blank` cache |
| editor | `editor-atomic-span` |
| input-component | `single-line-input-clear-action` |
| input | rebuild event-kind table |
| keys | load-time scanners |
| mermaid/index | `+gm-draw-kinds+` |
| mermaid/transform | consume-list streams |
| mermaid/labels | char on string |
| mermaid/parse | `gm-char` |
| overlay | composite result vector |
| alt-screen | `+synchronized-update-*+` |
| alt-screen-search | `+search-whitespace-characters+` |
| lifecycle-input | coerce lines to vector |
| main-screen | `+kitty-control-prefix+` |
| stdin-buffer | index walk |
| terminal-image | `+base64-decode-table+` |
| terminal | protocol scanners |
| theme | `ensure-theme-keyword` |
| unicode | extract/wrap streams |
| word-navigation | `scan-word-while` |
| latex | layout/node vectors |

## K0.2 macros

Zero macros in `src/cadr-tui/`. nth density was the highest in
the tree because the TUI walks display lists and char buffers.
K8 replaces those walks with cons tails, `aref`, and
`with-output-to-string`. No `define-*` authoring surface was
added. Widget `with-` macros were not needed: the repeated
bindings were one-owner helpers (`gm-char`, `scan-word-while`,
`loader-frames`), not a new DSL.

## Pairing

Markdown / latex / unicode / mermaid / renderer / overlay
touch official render-diff. Req 8 Date.now() is not used.
Existing cadr-tui FiveAM is the before/after (3652 pass).

Blocked: 0. FiveAM 18768 → 18841. derive 680/680.
Official render-diff `--tier core` EXIT:0 (captured=120/122).
N_i untouched.

## H class

Booked class from tip `docs/benchmarks/goal20-unpaired-paths.json` via
`scripts/goal20-unpaired-paths.py` (longest prefix). Refreshed 2026-09-07
against denom 297 / 133658 (`needs-pair=0`, `pairable-uncovered=0`).
Not 148 wall-clock pairs. Historical K-booking `pairable-uncovered` /
`pending H pair` sentences are superseded by this list.

- `paired` (38): `autocomplete.lisp`, `components/image.lisp`, `components/markdown.lisp`, `components/select-list.lisp`, `components/tool-block.lisp`, `composition/loaders.lisp`, `composition/protocol.lisp`, `composition/rich-content.lisp`, `composition/root.lisp`, `composition/settings-list.lisp`, `composition/text-box.lisp`, `editor.lisp`, `fuzzy.lisp`, `input-component.lisp`, `input.lisp`, `keybindings.lisp`, `keys.lisp`, `kill-ring.lisp`, `latex.lisp`, `mermaid/index.lisp`, `mermaid/source-box.lisp`, `mermaid/transform.lisp`, `native-modifiers.lisp`, `overlay.lisp`, `renderer/alt-screen-search.lisp`, `renderer/alt-screen.lisp`, `renderer/lifecycle-input.lisp`, `renderer/main-screen.lisp`, `renderer/terminal-protocol.lisp`, `renderer/virtual-terminal.lisp`, `stdin-buffer.lisp`, `terminal-colors.lisp`, `terminal-image.lisp`, `terminal.lisp`, `theme.lisp`, `undo-stack.lisp`, `unicode.lisp`, `word-navigation.lisp`.
  Dual-ref: H cell vs pi + K FiveAM/render-diff vs previous cadr.
- `covered-as-callee` (12): `components/status.lisp`, `mermaid/ansi.lisp`, `mermaid/canvas.lisp`, `mermaid/graph.lisp`, `mermaid/labels.lisp`, `mermaid/layout-seq.lisp`, `mermaid/layout.lisp`, `mermaid/parse.lisp`, `mermaid/width-data.lisp`, `mermaid/width.lisp`, `package.lisp`, `threads.lisp`.
  On a named paired thunk; no own bench.

