# Goal 9 Part D stage report

> Status: the single local verification entrypoint is implemented; both the
> with-credentials and the zero-credential conditions were really run and passed.

## 1. Entrypoint and isolation boundary

`./scripts/verify.sh` executes a fixed sequence:

1. deterministic FiveAM;
2. `build.sh` and `build-server.sh` inside an `mktemp` worktree;
3. the six retained harnesses: native image, process modes, migration PTY, Unix
   socket server, terminal lifecycle, deterministic TUI;
4. the eight availability-gated FiveAM items of `test-live.sh`;
5. a real TUI two-turn file edit when `DEEPSEEK_API_KEY` is available.

The isolation copy explicitly excludes `.git`, existing binaries, `.cadr`,
`.pi-cl`, `.tmp-home`, `.env*`, Obsidian and Python caches. The script prints
separate deterministic/live tables; a failure of any item that did run makes the
final exit `1`, but a live FiveAM failure does not prevent the runnable live TUI
that follows. This Part did not create or modify any remote CI configuration.

The test-first gate
`GOAL9-PART-D-VERIFY-ENTRYPOINT-HAS-APPROVED-STAGE-CONTRACT` was red at
`1 check / 0 pass / 1 fail` while the entrypoint did not exist; after
implementing and locking the stage order, the isolation, the summary and the
absence of a remote workflow it is green at `29/29`.

## 2. Run with credentials

Command: `./scripts/verify.sh`. Elapsed `3m29s`. Deterministic stages:

| Stage | Result |
|---|---|
| deterministic FiveAM | PASS, 6952/6952, 0 skip, 0 fail |
| isolated cadr build | PASS; the shared build entrypoint repeats the same 6952/6952 gate |
| isolated cadr-server build | PASS; the shared build entrypoint repeats the same 6952/6952 gate |
| native acceptance | PASS |
| text/JSON/RPC/SIGTERM process modes | PASS |
| migration PTY | PASS |
| Unix socket server | PASS |
| terminal lifecycle PTY | PASS, 3/3 |
| deterministic TUI | PASS |

Complete live FiveAM report:

| Item | Result | Checks / reason |
|---|---|---|
| DeepSeek completions stream | PASS | 5 |
| Anthropic two-turn stream | SKIP | `ANTHROPIC_API_KEY is not set` |
| DeepSeek print | PASS | 3 |
| OpenAI Codex explicit OAuth model | PASS | 4 |
| DeepSeek eval | PASS | 4 |
| OpenAI Codex OAuth eval | PASS | 4 |
| DeepSeek self-extension | PASS | 6 |
| DeepSeek repository fail/fix/pass | PASS | 5 |

Item summary: `8 items / 7 run / 7 pass / 1 skip / 0 fail`; check summary:
`32 checks / 31 pass / 1 skip / 0 fail`. The DeepSeek real TUI then passed
autocomplete, undo, kill-ring, the two-turn write/edit, resize, CJK and terminal
restore — all PASS.

## 3. Zero-credential run

Uses a brand-new temporary HOME, an explicit external Quicklisp path, and unsets
`DEEPSEEK_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`. Elapsed `2m11s`. The
nine deterministic/build/harness stages are identical to the with-credentials
condition and all PASS; the three deterministic FiveAM executions are still
`6952/6952/0/0` each.

All eight live FiveAM items SKIP under their availability gates: five DeepSeek
items because the key is missing, one Anthropic item because the key is missing,
and two Codex items because the temporary HOME has no OAuth. The summaries are
`8 items / 0 run / 0 pass / 8 skip / 0 fail` and
`8 checks / 0 pass / 8 skip / 0 fail`. The DeepSeek live TUI explicitly displays
`SKIP (DEEPSEEK_API_KEY is not set)`. The temporary HOME was deleted afterwards;
the real user auth was not read.

## 4. Evidence discipline

- With-credentials raw log: `/tmp/cadr-goal9-part-d-with-credentials.log`.
- Zero-credential raw log: `/tmp/cadr-goal9-part-d-without-credentials.log`.
- Both combined-entrypoint runs report per-stage results only; a run that
  includes live is not called "deterministically all green".
- New third-party dependencies: `0`.
- Total elapsed time for this Part: about 1 hour, including design, red/green
  tests and two complete entrypoint runs.
- token: the product does not provide an auditable exact per-Part token count;
  no estimate was fabricated.
- Commit: this Part is committed on its own.
