# Goal 20 Part K4 — cadr-server

11 files / 2,793 → 2,784 lines. I wc matched at start.

| File | I | K4 |
|---|---|---|
| package/types/config/protocol/ipc/rpc-process/supervisor | no-rewrite | keep — wc and duties undrifted |
| handler.lisp | needs-rewrite | **done** — `handle-instance-request` |
| main.lisp | needs-rewrite | **done** — `run-ipc-command` + `client-ipc-request` |
| storage.lisp | needs-rewrite | **done** — `member` + `setf car` |
| radius.lisp | needs-rewrite | **done** — `heartbeat-retry-or-reregister` |

I0: one owner each for missing-instance, IPC print wrap, identity
replace, and heartbeat backoff.

cadr-server is unpairable in Part H (session-server contract).
Req 8 not invoked as a Date.now() excuse; existing server FiveAM
is the before/after.

ipc stringly upgrade sniff left alone (K0.2).

Blocked: 0. Tests red on old HEAD: the four new `fboundp` /
upsert-order checks. FiveAM 18691 → 18699. `--all` still the
known `tools-significant-states` load family; N_i untouched.

## H class

Booked class from tip `docs/benchmarks/goal20-unpaired-paths.json` via
`scripts/goal20-unpaired-paths.py` (longest prefix). Refreshed 2026-09-07
against denom 297 / 133658 (`needs-pair=0`, `pairable-uncovered=0`).
Not 148 wall-clock pairs. Historical K-booking `pairable-uncovered` /
`pending H pair` sentences are superseded by this list.

- `unpairable` (11): `config.lisp`, `handler.lisp`, `ipc.lisp`, `main.lisp`, `package.lisp`, `protocol.lisp`, `radius.lisp`, `rpc-process.lisp`, `storage.lisp`, `supervisor.lisp`, `types.lisp`.
  Single-ref vs previous cadr; do not invent a pi pair.

