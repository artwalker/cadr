# Goal 20 Part P — CL ceiling (draft; G.17 not met)

Spec: `goal20-draft.md` 十B. Ruling: `docs/adjudications.md`
2026-08-18 CL ceiling (`1a24eea1d`). Floor is still pi on paired
paths. Beating pi is not a stop.

This file is a **draft**. Advisor 2026-08-18 13:50 vetoed G.17
`met` on `40db3f88a`: copying the old Friend-MachineD table is not
a P.4 probe; calling that a `number` is not a measurement; P.8 is
not a `number` while the user has not played.

Friend-MachineD non-`quick` pairing was not available here.
`RATIO_CEILINGS` is unchanged. O 7a–7d were not re-run.
Not a Goal 20 pass.

## P.1–P.11

| item | status | number or leftover | evidence |
|---|---|---|---|
| P.1 JSON read | number | 6489 ns → 5663 ns median / parse (300×515 session.jsonl, this host) | `7d5478818`. 7b not repeated. |
| P.2 JSON write | number | stringify 6596 ns → 5636 ns; terminating-rational 210 ns → 170 ns; create-session 0.40 ms vs 128 appends 3.00 ms | `232761357` / `d4da3cb65` / `a3d57ce03`. |
| P.3 list_models_render | number | 4.30 ms → 2.45 ms median / `print-cli-models` (80 calls, this host) | `f898c9ab5`. 7d not repeated. |
| P.4 help / argv / context_walk | number | µs floor (booked help 4.3 µs, argv 6.5 µs, walk 110 µs / 1.09×) | Judged floor, not a lever. |
| P.4 stream_roundtrip | leftover | not measured this knife | Old 1.29× table is not a probe. Next: measure or honest `blocked`. |
| P.5 declarations | number | folded into P.1 / P.2 before/after | Only those two centers. `safety` unchanged. |
| P.6 stream / TUI alloc | leftover | not profiled this knife | Booked cold-start 253–320 ms is not this cell. Need a stream + TUI alloc profile. Compression keep `46fabd9bb`. |
| P.7 H pairing | number | 0 new file-level pairs | 148-file benches forbidden. |
| P.8 three games | leftover | user has not played | ttt SHAs `165edc9c2` + `edb9d6dca` stay. Slot-citation for snake/invaders is not P.8. |
| P.9 live image | number | 1 runbook, 2 paths | `docs/runbooks/live-image.md`. |
| P.10 input-to-screen | leftover | not timed this knife | Existing TUI pairs stay as Goal 11 gates, not this probe. |
| P.11 tool restarts | number | 3 existing, 0 new on pairable failures | `retry-tool-call` / `skip-tool-call` / `abort-agent-run`. |

## Not claimed

- Goal 20 complete.
- G.17 `met`.
- Friend-MachineD pairing for P.1–P.3.
- Ratios ≤ 1.0× vs pi.
- User hand-play of the three games.
