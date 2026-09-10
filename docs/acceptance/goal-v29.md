# Goal 29 — harden proofs, tip hygiene, exhaust remaining solo work

> **Status:** met (2026-09-10).
> Does **not** reopen Goal 20–28 as incomplete.
> Goal 28 remains terminal `met` (`open-capability=0`).
> Pin stays `d981de1229ef899957bbe968bc8dcda02a21f477` `v0.85.1`.
> Solo agent only (no Task subagents).

## Why this exists

Goals 24–28 closed their stop predicates. Operators still see weaker proof
(`match=0`), tip dirt, and Goal 27 `no-keep` write paths. The operator asked
for Goal 29 that finishes every remaining item a solo agent can complete.

Unbounded “every microbenchmark ≤1.0×” and paid-provider e2e are out. Finite
tracks below define done.

## Tracks

| track | job | stop | result |
|---|---|---|---|
| **H-hygiene** | Dispose tip dirt | `git status --porcelain` has no Goal20 harness/orphan leftovers; Goal24/25 orch landed or deleted with note | closed (orch24/25 landed; `.pair260-harness-stable` removed) |
| **H-match** | Promote pin-behavior `fixed` → `match` | Every Goal 28 `fixed` row whose evidence is a `goal28-*-test.lisp` is `match`; `open-capability=0` | closed (`594 match`, `365 intentional-difference`, `open-capability=0`) |
| **H-test** | Run non-e2e CL tests | `scripts/test-cl-fiveam.sh` exits 0 (or documented shard failures fixed) | closed (`checks=21102 pass=21102 fail=0`) |
| **H-perf** | Exhaust write_* knives | Each of `write_overwrite` / `write_hello` / `write_empty` is `kept-faster` or `exhausted-no-keep` under Goal 29 evidence; dialog stays out | closed (`exhausted-no-keep`; dialog out-of-scope) |

## Forbidden

- Reopening Goal 20–28 as incomplete
- Claiming paid-provider e2e green without keys
- Silent freezes of perf gaps
- Leftover-only wrapper “wins”
- Infinite invent without remesure

## Claimed

- Charter open 2026-09-10. Solo execution.
- Met 2026-09-10. Four tracks closed. FiveAM ledger re-recorded.
