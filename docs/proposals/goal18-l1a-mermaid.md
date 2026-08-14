# Goal 18 L1a: dependency adjudication proposal for Mermaid rendering (adjudicated)

Status: **adjudicated (2026-08-12): route 1 (pure Lisp port of grok-mermaid +
differential golden samples) is approved, split out as goal 19, and is not
implemented within goal 18.** v0.84.1 adds `components/mermaid.ts` (an 89-line
thin wrapper) to the baseline; the real Mermaid parsing and layout live in the
third-party library `grok-mermaid@0.2.2`. Per the standing constraint (a new
dependency must be pre-reviewed), this proposal gives the routes, cost and risk;
no implementation was started within goal 18.

> Ledger record (2026-08-12, user adjudication): in `docs/source-parity.md` the
> `mermaid.ts` row goes from `pending adjudication` to `missing` (not "intentional difference" — the
> capability is not yet implemented, and the ledger records that faithfully);
> `OQ-G18-L1A-MERMAID` in `docs/open-questions.md` is moved into the
> "adjudicated, pending goal" section. Until goal 19 is closed out, Mermaid
> blocks render as a source box under the baseline's fallback semantics. Route 2
> (bringing in an equivalent Lisp dependency) has already been ruled out by the
> check that Quicklisp has no such ecosystem; route 3 is not accepted as an end
> state.

## Dependency facts (measured)

- artifact: `grok-mermaid@0.2.2`, `https://registry.npmjs.org/grok-mermaid/-/grok-mermaid-0.2.2.tgz`
- license: Apache-2.0 (redistribution allowed; the notice must be retained)
- runtime dependencies: **zero**; dist is 4,224 lines of dependency-free ESM (parse 1,107 + layout 880
  + width-data 993 + canvas/labels/ansi/...)
- capability surface: `graph`/`flowchart` (including `subgraph`), `stateDiagram`,
  `classDiagram`, `erDiagram`, `sequenceDiagram`; rendered as Unicode
  box-drawing character art; returns null when unsupported or too large, and the
  caller falls back to `sourceBox`
- baseline usage (`mermaid.ts`): a ```mermaid block in markdown goes through `render()` to
  produce character art, falling back to a source box when it is too wide or fails

## Three routes

### Route 1: pure Lisp port of grok-mermaid (recommended)

Port the 4.2k lines of parsing/layout into cadr's own Lisp code (a new system or
a module under cadr-tui), **introducing no third-party Lisp library**, with zero
change to the ASDF closure and the release binary.

- cost: porting the parser + the layouter, on the order of 3–5 working days; the
  Unicode width table (width-data, 993 lines) can be converted mechanically.
- risk: porting deviation — **controlled with differential golden samples**: the
  baseline library's character-art output for a pinned corpus is recorded byte
  for byte as a fixture, and the cadr port is compared byte for byte against the
  same corpus; the corpus covers the five diagram types + syntax errors +
  a streaming half-line + the too-wide fallback. This is exactly the
  fixture-locked approach this project has already proven.
- license: an Apache-2.0 port is a derivative work; register the source and the
  license text in NOTICE/dependency-audit.

### Route 2: bring in an equivalent Lisp dependency

The Quicklisp ecosystem has **no** Mermaid renderer (checked). This route is a dead end.

### Route 3: record it as intentional difference (mermaid blocks always render a source box)

The baseline's own fallback for unsupported/too-wide diagrams is `sourceBox`;
route 3 = fall back forever.
The user-visible capability loss is real (the baseline produces character art for
the five diagram types, cadr produces only a source box), and per the divergence
policy it must carry an equal-strength assertion (the fixed shape of a mermaid
block rendered as a source box). Of the adjudicated differences this is the
cheapest one and the one most lacking in capability.

## Recommendation

Route 1. Reasons: zero dependencies, bounded size, differential golden samples
make "aligned with the baseline" machine-verifiable, and it is consistent with
the project's "no crippling" north star. If the adjudication holds that the
upgrade window cannot carry this workload, route 3 may be recorded first
(explicit assertion + difference registration) and route 1 split out into a
later goal — but that is a deliberate capability debt and must be stated in
writing.

## Adjudication and ledger actions (2026-08-12)

- Route 1 is approved and split out as **goal 19**; the remaining goal 18
  batches (④⑥⑦⑧) are finished off first, and goal 19 opens immediately after
  goal 18 is closed out.
- The source-parity ledger already records `missing`; open-questions already
  registers it as an adjudicated, pending goal.
- When goal 19 is executed: docs/dependency-audit.md registers the
  artifact/hash/license/port relationship (for the Apache-2.0 derivative work,
  note the source and the license text); the differential fixture generator goes
  into the gates; the 89-line wrapper of mermaid.ts is ported through the normal
  routing; on completion source-parity is re-judged `implemented`.
