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

**Tip inventory (denom 297 / 133658; `goal20-unpaired-paths.py --check`):** `needs-pair=0`, `pairable-uncovered=0`. Classes below that still say `pending H pair` / `pairable-uncovered` are historical at the K booking; current class is `paired` / `covered-as-callee` / `unpairable` per `docs/benchmarks/goal20-unpaired-paths.json`. Not 148 new benches.

Booked class from `docs/benchmarks/goal20-unpaired-paths.json`
via `classify` (longest prefix). No new unpairable.

29 `done` files:

- `paired` (14): `components/{image,markdown,tool-block}.lisp`;
  `composition/{protocol,text-box}.lisp`; `editor.lisp`;
  `input.lisp`; `keys.lisp`; `renderer/{alt-screen,
  alt-screen-search,lifecycle-input,main-screen}.lisp`;
  `terminal.lisp`; `unicode.lisp` (Goal 11 mouse/wheel/
  continuous or `render_slicing`). Dual-ref: H/Goal 11 vs
  pi, FiveAM vs previous cadr.
- `unpairable` (0).
- `pairable-uncovered` (15): autocomplete, loaders,
  settings-list, select-list, mermaid/*, overlay,
  stdin-buffer, terminal-image, theme, word-navigation,
  latex, input-component. Single-ref vs previous cadr
  (FiveAM / render-diff), pending H pair. Not 「不劣于 pi」.
