# Goal 20 Part P — CL ceiling

Spec: `goal20-draft.md` 十B. Ruling: `docs/adjudications.md`
2026-08-18 CL ceiling (`1a24eea1d`). Floor is still pi on paired
paths. Beating pi is not a stop.

Friend-MachineD non-`quick` pairing was not available. vs-pre-cadr
+ same-machine numbers are the bar. `RATIO_CEILINGS` is unchanged.
O 7a–7d were not re-run. Not a Goal 20 pass.

Advisor 2026-08-18 13:50 vetoed G.17 `met` on `40db3f88a` (copied
table). This report uses this-host measurements. P.8 is FiveAM, not
user hand-play (`goal20-state` 不许停：等用户手玩).

## P.1–P.11

| item | status | number or blocked | evidence |
|---|---|---|---|
| P.1 JSON read | number | 6489 ns → 5663 ns median / parse (300×515) | `7d5478818`. 7b not repeated. |
| P.2 JSON write | number | stringify 6596→5636 ns; rational 210→170 ns; create 0.40 ms vs 128 append 3.00 ms | `232761357` / `d4da3cb65` / `a3d57ce03`. |
| P.3 list_models_render | number | 4.30 ms → 2.45 ms / `print-cli-models` | `f898c9ab5`. 7d not repeated. |
| P.4 help / argv / walk | number | booked help 4.3 µs, argv 6.5 µs, walk 110 µs (1.09×) | µs/MAD floor, not a lever. |
| P.4 stream_roundtrip | number | this host 5.400 ms / call, 3,753,622 B / call | Fixture `stream-chat`. sprof top `READ-SSE-STREAM`. No >10% product lever without a new SSE path. |
| P.5 declarations | number | same P.1 6489→5663 ns and P.2 6596→5636 ns | Only those centers. `safety` unchanged. |
| P.6 alloc | number | stream 3,753,622 B/call; snake overlay 39,963 B/call (0.100 ms) | This host. Compression keep `46fabd9bb`. |
| P.7 H pairing | number | 0 new file-level pairs | 148-file benches forbidden. |
| P.8 three games | number | 34/34 FiveAM this host, fail=0 | ttt busy/steer/overlay 25; snake render 5; invaders render 4. Tests drive shipped host + `component-render`. Not hand-play. |
| P.9 live image | number | 1 runbook, 2 paths | `docs/runbooks/live-image.md`. |
| P.10 input-to-screen | number | key→overlay 0.100 ms / call, 39,997 B; spinner=NIL thinking=NIL | Snake `component-handle-event` + `component-render`, 80 repeats. |
| P.11 tool restarts | number | 14/14 FiveAM this host, fail=0 | retry 7 + skip 3 + abort 4. 0 new restarts on pairable failures. |

## Floor vs ceiling

Last Friend-MachineD non-quick table is unchanged (read 3.93×, load
4.28×, append 2.21×, list_models_render 3.18×). That is the floor
ledger. Same-machine levers above moved vs pre-change cadr.

## Not claimed

- Goal 20 complete.
- Friend-MachineD pairing for P.1–P.3.
- Ratios ≤ 1.0× vs pi.
- User hand-play of the three games.
