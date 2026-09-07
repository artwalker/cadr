# Goal 20 Part K2 — cadr-storage

K1 was Part J (`cadr-core`). This package is 2 files / 31 lines.
I already marked both `no-rewrite`. Line counts and duties have
not drifted (`wc -l` 19 / 12, same one-sentence owners).

| File | Lines | I status | K2 |
|---|---:|---|---|
| `src/cadr-storage/package.lisp` | 19 | no-rewrite | keep — still a defpackage import-from/re-export facade |
| `src/cadr-storage/sqlite.lisp` | 12 | no-rewrite | keep — still a 12-line forwarder; `cadr-agent::` at :4 is owned by cadr-agent |

No rewrite. Inventing one to look busy would violate the K2
heading and unified req 7.


H class is tip inventory below (both files `paired`). Keep-as-I does
not invoke req 8's single-ref exception.

Theme index Recount 197 → 198 (P0 added
`test/cadr-ai/opencode-go-live-test.lisp`; 198/198 paths on disk
are in the index).

Blocked: 0. part-i identity untouched (done count still 1).

Local `--all` (rider 2) is not a close gate. It failed
`tools-significant-states/wide` (975.5 / 958.8 / 937.5 ms vs
N_i=925) and `/narrow` (933.8 / 915.3 / 1079.0 vs 969). Median
~18–22 ms. Same load-sensitive family already on the board.
Thresholds were not touched. Scratch: `k2-liveness-all.log`.

## H class

Booked class from tip `docs/benchmarks/goal20-unpaired-paths.json` via
`scripts/goal20-unpaired-paths.py` (longest prefix). Refreshed 2026-09-07
against denom 297 / 133658 (`needs-pair=0`, `pairable-uncovered=0`).
Not 148 wall-clock pairs. Historical K-booking `pairable-uncovered` /
`pending H pair` sentences are superseded by this list.

- `paired` (2): `package.lisp`, `sqlite.lisp`.
  Dual-ref: H cell vs pi + K FiveAM/render-diff vs previous cadr.

