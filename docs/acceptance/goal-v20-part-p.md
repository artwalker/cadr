# Goal 20 Part P — CL ceiling (draft; G.17 missing)

Spec: `goal20-draft.md` 十B (incl. 「Callee / 屠龙」).
Rulings: `docs/adjudications.md` 2026-08-18 CL ceiling
(`1a24eea1d`); 2026-08-20 beat-pi / study-callee; 2026-08-20
bucket-split / empty ⚑ ≠ exhausted; 2026-08-20 study shape,
not port the V8 VM. Floor is still pi; beating pi is not a
stop. DS audit Class C:
`docs/acceptance/goal-v20-ds-audit.md`.

Advisor vetoed G.17 `met` on `40db3f88a` and `c53e13c47`,
and vetoed G.17 `blocked` on `7e4ec5201`. G.17 is `missing`.
`blocked` is only for new deps / safety / format / mmap /
observable SIMD (and FFI-into-callee / intern grow / empty SWAR
without adjudication). P.8 is `number` after user 2026-08-18 18:09
deferred live play (reopen if a defect appears).
`RATIO_CEILINGS` is unchanged. O 7a–7d were not re-run.
Not a Goal 20 pass.

**Load leftover method (not G.17):** bucket-split
`PARSE-SESSION-RECORD-OCTETS` (child cadr µs) **and** open the
matching V8 source step (what it does less of) before a knife.
Name-only `Parse*` stickers are not essence. Do not require
HiddenClass/Zone/HandleScope ports. Knife not landed without
green `test-cl.sh` + Friend-MachineD cadr µs. Call-boundary
inlines won; several V8-named micro knives withdrew — see
`docs/benchmarks/goal20-session-load-sprof-d0c88ddd2.md`,
`docs/benchmarks/goal20-parse-session-record-split.md`.

## P.1–P.11

| item | status | number or leftover | evidence |
|---|---|---|---|
| P.1 JSON read | leftover | Call-boundary inlines won; load still ~1.27× (cadr ~1857 µs @ `d0c88ddd2` ledger). Next = bucket-split descent (`PARSE-SESSION-RECORD-OCTETS`), not empty SWAR / intern grow / FFI / labels→macrolet redo / <3% ISO/DIGITS polish. | adjudications 2026-08-20; sprof `d0c88ddd2`. Not G.17. |
| P.2 JSON write | number | typed emit + reused journal fd + schema octet emit. this-host create+128 append 4069 µs / 1,273,115 B → 1311 µs / 185,013 B | this knife. Bytes match stringify. Not intern. Not FFI. |
| P.3 list_models_render | number | available-models cached on registry. this-host 2189→199 µs; pairing 1.57×→0.06×, cadr 2088→97 µs | remesure `8d7917472`. |
| P.4 help / argv / walk | number | remesure `b7f1f7de0`: argv 0.98× (3.0 / 3.1 µs). `cli-token-tail=` now `schar`; this-host 3.0→1.96 µs | this knife for argv. Not intern. |
| P.4 stream_roundtrip | number | this-host 6.398 ms / 3,750,979 B → 4.995 ms / 2,432,214 B; SSE-only 2.899 ms / 2,327,510 B → 1.698 ms / 1,229,201 B | `c183539e7`–this knife. File-stream newline scan. |
| P.5 declarations | number | folded into P.1 / P.2 | `safety` unchanged. |
| P.6 alloc | number | stream 2,350,697 B; snake overlay 39,963 B; ttt overlay 47,819 B | ttt visual-board stream rewrite. |
| P.7 H pairing | leftover | P.13 reopens remaining `needs-pair`. Existing 16 named metrics stay. Not 148 file benches. | user 2026-08-19 18:30 |
| P.8 three games | number | user 2026-08-18 18:09 deferred live play; reopen if a defect appears | Overlay: ttt `edb9d6dca`, snake/invaders `f3ccf75f6`. Not FiveAM. |
| P.9 live image | number | 1 runbook, 2 paths | `docs/runbooks/live-image.md`: disk `/reload`; host rebuild. Rechecked this turn. |
| P.10 input-to-screen | number | key→overlay 0.050 ms, spinner=NIL, thinking=NIL | This host, 80× snake key+render after `f3ccf75f6`. |
| P.11 tool restarts | number | 14/14 FiveAM, fail=0 | this turn: retry 7 + skip 3 + abort 4 (`tool-loop-test.lisp`). |

## P.12

| item | status | number or leftover | evidence |
|---|---|---|---|
| P.12.1 JSON window scan | number | remaining `PEEK`/`TAKE` are macros over `SCHAR` + fixnum `position`; `PARSE-STRING` copies a source window | already `7d5478818` / `87b24e85f`. Not 7b. |
| P.12.2 editor-lines | number | 80× 200-line editor-lines+render 183,349 B → 177,188 B / call | this knife. Wall 0.300–0.399 ms (timer step). |
| P.12.3 alt-screen nth | number | last-document vector; 400-row × 80 `NTH` 0.100 ms → `AREF` 0.000 ms | this knife. prepared-document stays a list for car/cdr prefix reuse. |
| P.12.4 mermaid concatenate | number | `gm-read-shape` 200× 800-char 1,342,124 B → 24,717 B; 0.340 ms → 0.040 ms. `gm-wrap-label` fill-pointer 88,758 B → 95,310 B (worse; concatenate kept) | parse `c95c24757`. wrap not a lever. |

## Load/read leftover (sprof `67a2d43fb`)

`docs/benchmarks/goal20-part-p-load-read-sprof.md`. Contrast
`docs/benchmarks/goal20-part-o-remaining-sprof.md`. Leftover is
walker / `pthread_sigmask` / foreign `read`. Not EQUAL hash.
Not `parse-json-octets`. Not a G.17 close.

## Not claimed

- Goal 20 complete.
- G.17 `met`.
- Live three-game play (deferred 18:09).
- P.13 complete (H JSON still three-class; inventory
  `docs/acceptance/goal-v20-part-p13-inventory.md` has
  `pairable-uncovered` 0% pending the schema knife).

## P.13 (user 2026-08-19 18:30)

| item | status | number or leftover | evidence |
|---|---|---|---|
| P.13 pairable coverage | leftover | Truncate head/tail **0.72× / 0.87×** (383.5 / 529.0 µs, 462.7 / 534.5 µs) Friend-MachineD n=5 `635ac76a1`. load **1.27×** (cadr **1882→1857 µs**) / journal **1.15×**. `pairable-uncovered` not 0%. Not P.13 complete. | H pair booked. G.17 still `missing`. Part P still `[open]`. |
