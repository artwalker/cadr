# Goal 19 Part C acceptance — Mermaid transformer wiring

Part C attaches the Part B Lisp renderer to cadr's markdown pipeline
and locks the baseline `mermaid.ts` contract with marked 18.0.5 goldens.
Part D leftovers from this tree (REQUIRED_COVERAGE + ledger sync) are
included; Part E residual answers that were still owed after Part B are
recorded here so they are not lost in a later write-up.

## What landed

- `src/cadr-tui/mermaid/transform.lisp` implements the transformer:
  `off` / `final` / `streaming`, silent parse/width fallback, non-streaming
  warning line with `(+N more)`, six `Span.cls` mappings, top-level fences
  only (blockquote / list-nested mermaid stays source).
- `transform-tui-markdown` always runs the built-in transformer before
  extension transformers, including when `extension-host` is nil.
- Settings `markdown.mermaid` updates `tui-state-mermaid-mode` and
  invalidates entry markdown/render caches.
- Inline markdown code spans follow marked 18 run-length rules so
  mermaid `codeSpan` rows with interior backticks survive rendering.
  Existing single-backtick cases stay delimiter-free.

Wiring uses existing settings / markdown / transcript seams. No new
ASDF system, no new Lisp dependency, `src/cadr-ai` untouched.

## Goldens

- Generator: `scripts/mermaid-transform-golden.mjs`
- Fixtures: `test/fixtures/mermaid-golden/marked-18.0.5.tgz`
  (SHA-256 `7d0ea56f8c29c0e6dec5665e62ad8089136819ca7028612e52301c2ba279dac2`)
  and the existing grok-mermaid 0.2.2 tarball.
- 23 cases, byte-exact, each with an independent semantic assertion
  (`test/cadr-tui/mermaid-transform-test.lisp`).
- Theme mapping is unit-tested separately; transform goldens are unstyled
  so they do not bake 256-color vs truecolor.

## Ledger

- `docs/source-parity.md`: `mermaid.ts` `missing` → `implemented`.
  Totals `670 = 507 implemented + 163 intentional difference + 0 missing`.
- `OQ-G18-L1A-MERMAID` marked implemented.
- `docs/dependency-audit.md` records marked 18.0.5 as a test-only fixture.
- Idiom / organization counts: 291→292 Lisp files; cadr-tui modules 48→49;
  B7 definition count 323→326.

## Render-diff / Part D leftovers

- Scenario `conversation-mermaid` covers absent / rendered / fallback.
- `REQUIRED_COVERAGE` gained `mermaid-absent`, `mermaid-rendered`,
  `mermaid-fallback` (144 tags; fail-closed against scenarios.json).
- Core gate replay after dispositions:
  `captured=76/76 scenarios=38 dimensions=2`
  `aligned=14 intentional-terminal-protocol=123 requires-disposition=247 adjudicated=370`
  `EXIT:0`
  The 122/248 pair was the pre-EOF-blank split. After `cae12eeec`,
  `conversation-mermaid/narrow/mermaid-rendered` moved from
  `requires-disposition` to `intentional-terminal-protocol` (I01-only).
- Mermaid checkpoint SHAs in `dispositions.json` match the replay screens
  (8 mermaid + 8 process-exit pairs). Art matches pi. Remaining screen
  deltas are I04 identity wrapping and I01 ANSI segmentation.

  **Correction (advisor, 2026-08-13).** This bullet originally also listed
  "one extra empty row after the transform's trailing newline" as a remaining
  delta.  That delta was subsequently removed by `cae12eeec`
  ("drop mermaid EOF blank so rendered diagrams match pi"), which also updated
  `dispositions.json`, `docs/acceptance/goal-v19-part-e.md`, and added the
  locking test `mermaid-rendered-markdown-does-not-grow-an-eof-blank`.
  This document was the only record not refreshed at that time; the stale
  clause is struck here rather than silently deleted so the trail stays
  auditable.

- **Disposition breadth (advisor, 2026-08-13; `development-policy` §5.4.3).**
  `dispositions.json` holds 371 entries; class coverage is
  **I01 370/371 = 99.7%**, I04 226, I05 12, I03 1, I02 1.
  §5.4.3 requires this ratio to be stated explicitly whenever a single class
  covers a majority of the exits, because the gate's strength then equals that
  class's rigour.  **I01 is `textCovering: false`** (SBCL ANSI update
  segmentation and teardown), so under the goal 18 normalised-text gate it
  cannot absorb visible-text differences — those are carried by I04
  (`textCovering: true`).  The breadth is therefore disclosed, not excused.

## Part E residuals

### Theme tokens

`mermaid-theme-token-count-stays-56` asserts
`(length cadr-tui::+dark-theme-colors+) = 56`. Six `Span.cls` values map
onto existing tokens only (`borderMuted` / `text` / `accent` / `muted` /
`accent+bold` / unstyled). No mermaid-specific token was added.

### Binary size

This host's SBCL has no `sb-core-compression`; `build.lisp` emits an
uncompressed image. The proposal's "19.7 MB compressed" figure is therefore
not a same-host metric.

| image | bytes | mtime |
|---|---:|---|
| `/root/projects/cadr/cadr` after last `src/` edit (uncompressed, SBCL then lacked the feature) | 20,392,288 (19.45 MiB) | 2026-08-13 15:13:26 +0800 |
| isolated `verify.sh` image (`build.sh`, uncompressed) | 20,851,288 (19.89 MiB) | 2026-08-13 15:57:00 +0800 |
| isolated `cadr-server` | 16,293,816 (15.54 MiB) | 2026-08-13 15:59:00 +0800 |
| `/root/projects/cadr/cadr` rebuilt with `:sb-core-compression` after Part C landed | 20,326,720 (19.39 MiB) | 2026-08-13 16:24:46 +0800 |

A pre-Part-C image was not retained on this host, so a byte-accurate
before/after of the native image cannot be invented. Part C source added
to the image is `transform.lisp` (427 lines) plus the existing markdown /
transcript wiring. Isolated `verify.sh` rebuilds are recorded in that
run's log when they finish.

Binary freshness at the start of the post-disposition verify:

```
binary: /root/projects/cadr/cadr
binary build time: 2026-08-13 15:13:26.884619570 +0800
latest src commit: fbac6a59db28b178b4abe09b977821f4d628df55 2026-08-13T04:36:22+08:00
latest source mtime: 2026-08-13 15:12:50.194108667 +0800
  /root/projects/cadr/src/cadr-tui/mermaid/transform.lisp
root cadr binary is fresh
```

### `"none"` / `"edge"` string enums (Part B B3, evidence)

Two different `"none"` / `"edge"` families exist. They are not one thing.

1. **`Span.cls` on the canvas** (`canvas.lisp` default `"none"`, edges
   claimed as `"edge"`; `mermaid.ts:39-53` / `transform.lisp:341-358`).
   These strings are the grok-mermaid class names. They are **not**
   printed as diagram text. They **are** the styling contract: `edge` →
   `theme.fg("accent")`, `none` → emit `span.text` unstyled. Replacing
   them with keywords would be a pure Lisp rewrite only if every writer
   (`canvas`, `layout`, `layout-seq`, `ansi.lisp` assoc keys) and the
   transformer `ecase` moved together. Left as strings because they are
   the baseline class vocabulary, not TS residue.

2. **Parser arrowhead / operator tables** (`parse.lisp:636-649`
   `+gm-class-ops+`, and the `head-to` / `head-from` slots). Here
   `"none"` means "no arrowhead glyph". That **does** change the
   characters drawn (`layout.lisp` `string=` against `"none"` before
   emitting `▼`/`▶`/…). This family is a byte-exact output contract.
   Keywords would be legal Lisp, but they are not "unused TS style":
   they select whether a glyph exists.

Conclusion: keep both as strings. (1) is the mermaid.ts class contract;
(2) is a glyph-presence contract. Neither is a leftover enum that can
be deleted without a paired rewrite of writers and goldens.

## Evidence

- `./scripts/test-cl.sh` (pre-commit run): systems=9 checks=16933 pass=16933 skip=0 fail=0
- Theme tokens remain 56 (`mermaid-theme-token-count-stays-56`).
- Transformer goldens: 23/23 byte-exact against marked 18.0.5 + grok-mermaid 0.2.2.
- Root binary unchanged this turn: `/root/projects/cadr/cadr`
  20,392,304 bytes, mtime 2026-08-13 16:42:22 +0800, matches `cae12eeec`
  (no `src/` edits).
- Core render-diff after the stale-disposition fix, 2026-08-13 17:42 +0800:
  `captured=76/76 scenarios=38 dimensions=2`
  `aligned=14 intentional-terminal-protocol=123 requires-disposition=247 adjudicated=370`
  `EXIT:0`
  summary `/tmp/cadr-rd-g19-stale-analysis-final/summary.json`.
  raise-on-first found no further stale semantic keys after splitting
  `conversation-mermaid/mermaid-rendered` (wide I01+I04, narrow I01-only).
- The 16:21 `EXIT:0` recorded earlier was taken at `26fd6124d`, before
  `cae12eeec`. It is not this closeout measurement.

## Observed mermaid screen delta (not a new I-class)

The extra empty row after the transform's trailing newline was removed
by `cae12eeec`. What remains at `conversation-mermaid/mermaid-rendered`:

- **wide** — flowchart art matches pi; remaining visible wrapping is
  Goal 16 identity (I04) plus I01 ANSI segmentation.
- **narrow** — semantic screen is byte-identical to pi (same SHA
  `4de03ae7…37cf01`); only raw ANSI segmentation/teardown still
  differs, so the disposition is I01-only.

No new intentional-difference class.
