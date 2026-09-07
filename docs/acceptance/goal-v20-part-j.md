# Goal 20 Part J — cadr-core pilot

Pilot package: `cadr-core` (7 files). Not switched to `cadr-protocol`:
Part I already marked `time.lisp` needs-rewrite (second-granular clock
named milliseconds). That is a real rewrite, so the smallest package
is still the right pilot.

## Evaluation (consumed from Part I, not re-litigated)

| File | Lines | I status | J outcome |
|---|---:|---|---|
| package.lisp | 43 | no-rewrite | keep |
| atomic-file.lisp | 106 | no-rewrite | keep |
| cancellation.lisp | 70 | no-rewrite | keep |
| paths.lisp | 95 | no-rewrite | keep |
| redacted-print.lisp | 44 | no-rewrite | keep |
| threads.lisp | 47 | no-rewrite | keep |
| time.lisp | 66→71 | needs-rewrite | **done** |

Dual progress: 7/7 files, 471→476 lines in-package. One rewrite.
Blocked: 0.

## Rewrite: `unix-milliseconds`

Problem: `get-universal-time` is second-granular. `(* 1000 (- ut
offset))` made every timestamp and ID land on `.000`. Baseline
`Date.now()` is real milliseconds. Callers include UUID v7, RPC
ids, OAuth expiry, session export.

Fix: `sb-ext:get-time-of-day` → seconds*1000 + usec/1000.

I0 benefit: **契约 / 可测** — the name now matches the unit. Not
"used a syscall".

## Assertions first

`unix-milliseconds-has-subsecond-resolution`: eight samples 3ms
apart must not be identical; value stays within 2s of the
get-universal-time epoch. On pre-fix HEAD the first assertion is
red inside one second. After the rewrite it is green.

## Performance (same machine, 200k calls)

| | 200k calls wall |
|---|---|
| before (`get-universal-time`) | 7.985 ms |
| after (`get-time-of-day`) | 4.004 ms |
| Node `Date.now()` | 15.030 ms |

Not worse than the old cadr body; faster than `Date.now()` on this
machine. Scratch: `time-before.txt` / `time-after.txt`.

Local `--all` (rider 2) is **not** a close gate. It fail-fasted on
`tools-significant-states/wide`: three runs worst 947.5 / 943.4 /
1018.4 ms against N_i=925 ms (median ~20 ms). Same load-sensitive
family already on the board. Thresholds were not touched. This is
why option A keeps the full table off CI. Scratch:
`j-liveness-all.log`.

No Part H pair exists for this primitive. This is the single-ref
plus baseline-clock check allowed by unified-requirement 8.

## Mapping

`unix-milliseconds` is not a source-parity mapping row (core
primitive, not a 1:1 TS function in the ledger). `derive --check`
must stay 680/680.

## Process defects (required — "顺利" does not count)

1. **J re-asked I's two questions.** I already had file-level
   verdicts. Repeating them is form, not signal. → unified req 7.
2. **"对基线实测" had no H cell.** Inventing a pairing harness for
   one clock function would be new machinery. → unified req 8.
3. **Assertions-first as a separate red commit** for a 5-line
   docstring+clock swap is ceremony. The test is written so it is
   red on the old body. → unified req 9.

These three went into `goal20-draft.md` Part K unified
requirements. That is the process change; no second process doc.

## H class

Booked class from tip `docs/benchmarks/goal20-unpaired-paths.json` via
`scripts/goal20-unpaired-paths.py` (longest prefix). Refreshed 2026-09-07
against denom 297 / 133658 (`needs-pair=0`, `pairable-uncovered=0`).
Not 148 wall-clock pairs. Historical K-booking `pairable-uncovered` /
`pending H pair` sentences are superseded by this list.

- `covered-as-callee` (1): `time.lisp`.
  On a named paired thunk; no own bench.

