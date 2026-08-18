# Goal 20 Part P — CL ceiling (performance + experience)

Spec: `goal20-draft.md` 十B. Ruling: `docs/adjudications.md`
2026-08-18 CL ceiling (`1a24eea1d`). Floor is still pi on paired
paths; a rewrite must not be slower than pre-change cadr. Beating
pi is not a stop and is not this report’s exit.

Friend-MachineD non-`quick` pairing was not available here. vs-pre-cadr
+ same-machine sprof/wall is the bar used below. The booked
Friend-MachineD paired table in `docs/performance.md` (`400dbadf4`,
2026-08-15) is unchanged. `RATIO_CEILINGS` is unchanged. O 7a–7d
were not re-run.

Not a Goal 20 pass. H `pairable-uncovered` is still 76.9%.

## P.1–P.11

| item | status | number or blocked | evidence |
|---|---|---|---|
| P.1 JSON read | number | session.jsonl parse median 6489 ns → 5663 ns (300×515, same machine) | `7d5478818`. `simple-string` + `schar` + ASCII `simple-base-string` copy. 7b not repeated. |
| P.2 JSON write | number | stringify median 6596 ns → 5636 ns; terminating-rational 210 ns → 170 ns; create-session 0.40 ms vs 128 appends 3.00 ms | `232761357` write-string spans; `d4da3cb65` rational; `a3d57ce03` harness tax. |
| P.3 list_models_render | number | print-cli-models median 4.30 ms → 2.45 ms (80 calls) | `f898c9ab5` registry cache by models.json/auth.json mtime. 7d not repeated. |
| P.4 remaining pairs | number (非杠杆 / leftover) | help_render 4.3 µs vs 0.8 µs (5.36×); argv_parse 6.5 µs vs 4.1 µs (1.59×); context_walk 110 µs vs 101 µs (1.09×); stream_roundtrip 6253 µs vs 4833 µs (1.29×) | Booked Friend-MachineD table. First three are µs/MAD floor — not a lever. stream_roundtrip left as leftover heat (provider assembly + SSE); no >10% lever shown here. |
| P.5 declarations | number | folded into P.1/P.2 before/after | `fixnum` / `simple-string` only on those cost centers. No tree-wide `fixnum`. `safety` unchanged. |
| P.6 alloc / 750 ms | number | parse-json 4005 bytes/line on the 515-line fixture; booked cold start 253–320 ms | Alloc this host after P.1. Cold start from `docs/performance.md` verify-isolated (Friend-MachineD), under 750 ms. Compression keep `46fabd9bb`. This Part did not rebuild `./cadr`. |
| P.7 H pairing | number | no new file-level wall-clock pair | User-felt paths already paired: session_load, journal_*, list_models_*, TUI mouse/wheel/continuous. 148-file benches forbidden. Friend-MachineD unavailable for a new pair. |
| P.8 three games | number | ttt live SHAs + FiveAM; snake/invaders render from the component slot | ttt `165edc9c2` + `edb9d6dca`. snake `component-render` reads `snake-component-state` (`examples/extensions/snake.lisp`). invaders same (`space-invaders-component`). Tests in `goal20-example-games-test.lisp`. |
| P.9 live image | number | runbook exists | `docs/runbooks/live-image.md`. Disk `~/.cadr` extensions: `/reload`. Host-in-image: rebuild. |
| P.10 input-to-screen | number | existing TUI pairs | `key_to_frame` / mouse / wheel / continuous in `docs/performance.md`. No new lying spinner. Product busy is `agent-busy-p` (ttt steer already booked). |
| P.11 tool restarts | number | existing three restarts | `retry-tool-call` / `skip-tool-call` / `abort-agent-run` in `src/cadr-agent/loop/tool-execution.lisp`. Tests in `test/cadr-agent/tool-loop-test.lisp`. No new `restart-case` on a pairable failure. |

## Floor vs ceiling

Paired paths are still above 1.0× vs pi on the last Friend-MachineD
non-quick run (read 3.93×, load 4.28×, append 2.21×,
`list_models_render` 3.18×). That is the **floor** ledger, not this
Part’s stop. Same-machine levers above moved vs pre-change cadr.
Further knives that need a JSON library, dropped `safety`, mmap, a
session-format change, or observable-byte SIMD stay `blocked` until
adjudicated.

## Not claimed

- Goal 20 complete.
- Friend-MachineD pairing for P.1–P.3.
- Ratios ≤ 1.0× vs pi.
- 148 new benches.
- User hand-play of the three games (advisor still has not played).
