# Goal 20 Part P — CL ceiling (draft; G.17 not met)

Spec: `goal20-draft.md` 十B. Ruling: `docs/adjudications.md`
2026-08-18 CL ceiling (`1a24eea1d`). Floor is still pi.

Advisor vetoed G.17 `met` on `40db3f88a` and `c53e13c47`.
`RATIO_CEILINGS` is unchanged. O 7a–7d were not re-run.
Not a Goal 20 pass.

## P.1–P.11

| item | status | number or leftover | evidence |
|---|---|---|---|
| P.1 JSON read | number | 6489 ns → 5663 ns median / parse | `7d5478818`. |
| P.2 JSON write | number | stringify 6596→5636 ns; rational 210→170 ns; create 0.40 ms vs 128 append 3.00 ms | `232761357` / `d4da3cb65` / `a3d57ce03`. |
| P.3 list_models_render | number | 4.30 ms → 2.45 ms | `f898c9ab5`. |
| P.4 help / argv / walk | number | booked help 4.3 µs, argv 6.5 µs, walk 110 µs | Floor. |
| P.4 stream_roundtrip | number | this-host 6.398 ms / 3,750,979 B → 5.397 ms / 3,108,022 B; SSE-only 2.899 → 2.199 ms / 2,327,510 → 1,659,406 B | `c183539e7` join+file `read-sequence`; then `split-sse-field` one payload `subseq`. |
| P.5 declarations | number | folded into P.1 / P.2 | `safety` unchanged. |
| P.6 alloc | number | stream 3,753,622 B; snake overlay 39,963 B | This host. |
| P.7 H pairing | number | 0 new file-level pairs | |
| P.8 three games | leftover | user has not played | FiveAM exists; not hand-play. |
| P.9 live image | number | 1 runbook, 2 paths | `docs/runbooks/live-image.md`. |
| P.10 input-to-screen | number | key→overlay 0.100 ms, spinner=NIL | This host. |
| P.11 tool restarts | number | 14/14 FiveAM, fail=0 | retry 7 + skip 3 + abort 4. |

## Not claimed

- Goal 20 complete.
- G.17 `met`.
- User hand-play.
