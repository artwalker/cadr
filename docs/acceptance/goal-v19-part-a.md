# Goal 19 Part A acceptance — Mermaid golden fixtures

> All evidence below was produced on 2026-08-12 against the Goal 19 tree
> (HEAD `3e1c67be0`, goal 18 closeout). Part A does not touch `src/`; it
> locks the baseline renderer output so Parts B–E can be verified byte-exact.

## A0 — toolchain, artifact, proposal re-verification

### Toolchain

- `npm` used explicitly by absolute path: `/root/.nvm/versions/node/v22.22.0/bin/npm`
  (npm 10.9.4, WSL side). The current shell PATH also resolves `npm`/`node`
  to the same WSL nvm installation (`node v22.22.0`), but the absolute path
  was used regardless, per the A0 requirement. No cross-boundary issue
  (path form, permissions, platform probe) was exposed; no blocked.
- `node` used explicitly by absolute path: `/root/.nvm/versions/node/v22.22.0/bin/node`
  for both the artifact refetch (`npm pack`) and the golden generator.

### Artifact verification (`grok-mermaid@0.2.2`)

| Check | Result |
|---|---|
| tarball SHA-256 | `61f98236a93be5f0b4f8caeb9956a728dc22b275d012b190639d3c03ae942934` — matches the refetch at `/tmp/gm-refetch/grok-mermaid-0.2.2.tgz` and the upstream `package-lock.json` integrity entry |
| license | Apache-2.0 (author Alexey Zaytsev); redistribution/derivation permitted with notice, registered in Part B's `docs/dependency-audit.md` entry |
| runtime dependencies | zero — the 11-file import graph is fully internal; `source-box.js` is exported but not imported by `index.js` |
| dist line count | 4,224 lines across 11 source files, exactly as proposed: parse 1,107 + layout 880 + layout-seq 193 + canvas 365 + labels 323 + width 75 + width-data 993 + index 99 + ansi 22 + source-box 77 + graph 90 |
| diagram kinds | all five verified by live render: `graph`/`flowchart` (incl. `subgraph`), `stateDiagram`, `classDiagram`, `erDiagram`, `sequenceDiagram` |
| determinism | no RNG/clock in dist; two consecutive generator runs produced identical `reference.json` (SHA-256 `01eea985066b1d11cc766bf5099f8d057b37ec49dbdbb8cf887f9b02aebe8a43`) |

The proposal numbers are all confirmed; no correction to
`docs/proposals/goal18-l1a-mermaid.md` was needed. The fixture tarball is
committed at `test/fixtures/mermaid-golden/grok-mermaid-0.2.2.tgz` so the
generator reruns offline.

### Theme token check (feeds Part C)

- Baseline v0.84.1 `dark.json`: 53 theme tokens (46 foreground + 7
  background); the `export` pageBg/cardBg/infoBg are outside that set.
- cadr `+dark-theme-colors+`: 56 tokens (46 foreground + 10 background) —
  the extra 3 are the goal-13 export tokens folded in. No mermaid/diagram
  tokens exist on either side, and Part B/C adds none (56/56 before/after).

## A1 — corpus and golden

### Artifacts

- Corpus: `test/fixtures/mermaid-golden/corpus.json` — 47 cases, each
  `{ "id", "src" }`.
- Generator: `scripts/grok-mermaid-golden.mjs` — verifies the fixture
  SHA-256, unpacks to a temp dir, renders every corpus entry with
  `grok-mermaid@0.2.2`, writes `reference.json` (atomic rename). It never
  depends on the probe directories under `/tmp`.
- Golden: `test/fixtures/mermaid-golden/reference.json` — per case:
  `input`, `null` (parse/blank → nil), and for rendered cases `width`,
  `warnings`, `plain` (rows), `styled` (rows of `[text, cls]` spans).

### Coverage vs. the six required categories

| Category | Cases |
|---|---|
| flowchart / graph (≥3) | graph-lr, graph-td-chain, graph-subgraph, graph-selfloop, graph-multibranch, graph-bt, graph-rl, graph-edge-label, graph-dotted, graph-thick, graph-node-shapes, flow-escaped, graph-stray-node |
| stateDiagram (≥3) | state-basic, state-desc, state-fork, state-note |
| classDiagram (≥3) | class-basic, class-members, class-chain, class-note, class-err |
| erDiagram (≥3) | er-basic, er-attrs, er-doc-example, er-err |
| sequenceDiagram (≥3) | seq-basic, seq-note, seq-loop, seq-actors, seq-err, seq-cjk, seq-emoji |
| syntax errors → null | err-bad, flowchart-empty-body, state-err, er-err, empty, comment |
| wide diagrams | graph-long-chain (width 68), graph-wide (width 34, 4-line wrapped label) |
| streaming half-lines | graph-half-link (`A-->`), graph-half-edge2 (`B--` unfinished second edge) |
| CJK / emoji labels | graph-cjk (width 24), graph-emoji (width 23), seq-cjk, seq-emoji |
| warning paths | err-graph, class-err, graph-half-link, graph-half-edge2 (1 warning each); graph-html (3 warnings — exercises the `(+N more)` suffix) |
| HTML entities / backtick labels | graph-html, graph-html2 |

6 of 47 cases are null; 5 rendered cases carry warnings.

### Baseline behaviors the golden locks (found during probing, not inferred from cadr)

- `flowchart LR\n  A[` (err-graph) is **not** null: the lenient flowchart
  grammar rescues it into an empty `A` box plus the warning
  `node "A": label is missing its closing \`]\``.
- `classDiagram … A -->` (class-err) rescues by dropping the final line:
  `dropped, unreadable final line: "A -->"`.
- `stateDiagram-v2 … note right of A: hi` and `classDiagram … note "hello"
  for A` render **without** the note (notes are consumed but not drawn).
- `sequenceDiagram\n  Alice->>John` (no message after the arrow) renders an
  unlabeled arrow rather than failing.
- `title` span class exists only in `source-box.js`; the five diagram kinds
  emit only `border`, `text`, `edge`, `edgeLabel`, `none`. The full six-way
  theme mapping of `mermaid.ts:38-53` is still implemented and unit-tested
  in Part C.

## A2 — mechanized judgment

Every corpus entry is judged byte-exact: the Part B Lisp renderer must match
`reference.json` exactly on null/width/warnings/plain/styled (text and cls
per span). The Lisp data file will be generated from `reference.json` by a
checked-in script and re-verified by a `verify.sh` consistency gate, mirroring
the `latex-reference-cases.lisp` pattern.

## Part A exit criteria

- A0 absolute npm path recorded (above); artifact SHA-256 verified; proposal
  numbers re-verified; theme token count corrected in `goal19.md` (53 → 56,
  three export tokens already present in cadr).
- Golden generator checked in and reproducible (two runs, identical output).
- Corpus covers all six required categories; 47 cases; judgment is byte-exact.

Next: Part B — pure-Lisp port under `src/cadr-tui/mermaid/`, zero new Lisp
dependencies, width-data mechanically converted, per-module provenance
headers, `docs/dependency-audit.md` registration.
