# Goal 20 Part K3 — cadr-protocol

5 files / 1,427 → 1,426 lines. I line counts matched at start
(33 / 121 / 508 / 145 / 620).

| File | I | K3 |
|---|---|---|
| package.lisp | no-rewrite, 33 | keep — still defpackage-only |
| codec.lisp | no-rewrite, 121 | keep — condition flattening is still the wire error text |
| cbor.lisp | needs-rewrite | **done** — `cbor-writer` owns the three limits; `encode-cbor-value` is `(writer value depth ancestors)` |
| framing.lisp | needs-rewrite | **done** — `offset` cursor; `consume-pending` is `incf`; compact on append when offset > 4096 |
| schema.lisp | needs-rewrite | **done** — `optional-field-p` replaces 14 copied absent-or-valid guards |

I0: one owner each for encoder limits, frame consume, and optional
fields. Not "used a struct".


H class is tip inventory below (`paired` / `covered-as-callee`).
Req 8's Date.now() exception is not invoked. Existing protocol
FiveAM is the before/after.

string= on wire command/type/role names stayed — those are the
byte contract, not internal enums.

Tests red on the old body: `cbor-writer-*` accessors, decoder
offset after one frame, `optional-field-p`. FiveAM protocol
497 → 505.

Blocked: 0.

Local `--all` (rider 2) is the same load-sensitive instrument as
K2. Thresholds were not touched. FiveAM 18683 → 18691.

## H class

Booked class from tip `docs/benchmarks/goal20-unpaired-paths.json` via
`scripts/goal20-unpaired-paths.py` (longest prefix). Refreshed 2026-09-07
against denom 297 / 133658 (`needs-pair=0`, `pairable-uncovered=0`).
Not 148 wall-clock pairs. Historical K-booking `pairable-uncovered` /
`pending H pair` sentences are superseded by this list.

- `paired` (4): `cbor.lisp`, `codec.lisp`, `framing.lisp`, `schema.lisp`.
  Dual-ref: H cell vs pi + K FiveAM/render-diff vs previous cadr.
- `covered-as-callee` (1): `package.lisp`.
  On a named paired thunk; no own bench.

