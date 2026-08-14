# Goal 20 Part I — Lisp-ification columns on the existing ledger

Date: 2026-08-14. Status: denominator locked; every current Lisp row is `pending evaluation`.
This landing does not assess any file and does not start Part K.

No second table. Columns were added to the existing per-file ledger in
`docs/code-organization.md` section 2.

## Locked denominator

Host `Friend-MachineD`, UTC `2026-08-13T18:36:11Z` (local 2026-08-14).

```sh
find src -name '*.lisp' | wc -l
# 293
find src -name '*.lisp' -print0 | sort -z | xargs -0 wc -l | tail -1
# 120927 total
```

| kind | files | lines |
|---|---:|---:|
| `src/**/*.lisp` (denominator) | 293 | 120,927 |
| mermaid (included, already in section 2) | 12 | 5,048 |
| static export assets (not in the denominator) | 5 | 4,275 |
| production files in the organization ledger | 298 | 125,202 |

The draft snapshot (280 files / 115,621 lines, mermaid excluded) is not this
lock. Goal 19 mermaid files were already in section 2; they were not added as
a second table.

Identity line in `docs/code-organization.md`:

```
GOAL20_LISPIFICATION_LEDGER baseline=53fa77ccd8a279eb87e92294ef3687b03ff80112 files=293 lines=120927 assets=5 unevaluated=293 needs-rewrite=0 no-rewrite=0 in-progress=0 done=0
```

Same-day extras used to reproduce the other section-1 numbers (not the
denominator lock itself):

```sh
find src -name '*.lisp' -print0 | xargs -0 grep -chE '^\((def|define-)' | paste -sd+ | bc
# 4968
find src -type f ! -name '*.lisp' | wc -l
# 5
```

Line counts are `wc -l` (newline count). `highlight.min.js` has no trailing
newline, so `physical_line_count` is one higher on that file only. The Lisp
denominator is unaffected.

## Columns and initial states

Header now:

`| Path | Lines | Definitions | One-sentence responsibility | Verdict | Lisp-ification status | evaluation verdict | handling goal |`

Closed states: `pending evaluation` / `evaluated-rewrite needed` / `evaluated-no rewrite` / `rewriting` / `done`.

| row kind | Lisp-ification status | evaluation verdict | handling goal |
|---|---|---|---|
| every current `src/**/*.lisp` | `pending evaluation` | — | — |
| five export assets | `n/a` | `Static export asset, a byte-for-byte copy of the baseline, no Lisp source to evaluate` | — |

Progress: `0/293` files, `0/120,927` lines.

`evaluated-no rewrite` was not used. That state still requires the two I0 questions
(most TypeScript-like site with a line number; why it is correct in Lisp).

Section 3.1 historical split rows (`agent/extensions.lisp` and the rest) were
not given Lisp-ification cells; they are not current files.

## What this Part does not do

- Does not enable Part A `+20%` / `+25%` fail-closed thresholds.
- Does not edit `docs/development-policy.md`.
- Does not start Part J or Part K.
