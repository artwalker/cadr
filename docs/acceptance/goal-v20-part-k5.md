# Goal 20 Part K5 — cadr-evals

8 files / 3,031 → 3,016 lines. I wc matched at start.

| File | I | K5 |
|---|---|---|
| package.lisp / artifacts.lisp | no-rewrite | keep — wc and duties undrifted |
| main.lisp | needs-rewrite | **done** — `argument-after-prefix` |
| harness-table.lisp | needs-rewrite | **done** — wrap calls `run-eval-harness` |
| harness.lisp | needs-rewrite | **done** — pre-prompt tail cons |
| reporter.lisp | needs-rewrite | **done** — push / nreverse at finish |
| suites.lisp | needs-rewrite | **done** — `json-string` |
| summary.lisp | needs-rewrite | **done** — one-arg `format-summary-signed` |

I0: one owner each for `--flag=`, copy+overlay merge, new-turn
assistant lookup, observation accumulation, empty-string
coalesce, and signed format.

No H cell used as a Date.now() excuse. Existing evals FiveAM
is the before/after.

cadr-ai coupling: evals *uses* `json-get` / stringify / uuid;
it does not re-own those decisions. The empty-string coalesce
is evals-local (string= against transcript fields).

Blocked: 0. Tests red on the old body: `argument-after-prefix`,
`--suite=`, `last-assistant-since` tail signature,
newest-first observations before finish, `json-string`,
one-arg `format-summary-signed`. FiveAM 18699 → 18722.
`--all` is the same load-sensitive instrument as K2; N_i
untouched. derive 680/680.

## H class

**Tip inventory (denom 297 / 133658; `goal20-unpaired-paths.py --check`):** `needs-pair=0`, `pairable-uncovered=0`. Classes below that still say `pending H pair` / `pairable-uncovered` are historical at the K booking; current class is `paired` / `covered-as-callee` / `unpairable` per `docs/benchmarks/goal20-unpaired-paths.json`. Not 148 new benches.

Booked class from `docs/benchmarks/goal20-unpaired-paths.json`
via `scripts/goal20-unpaired-paths.py` `classify` (longest
prefix; unmatched defaults to `pairable-uncovered`). No new
unpairable.

All six `done` files (`main`, `harness-table`, `harness`,
`reporter`, `suites`, `summary`) are `pairable-uncovered`.
Single-ref vs previous cadr (FiveAM), pending H pair. Not
「不劣于 pi」.
