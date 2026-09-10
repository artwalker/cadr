# Goal 30 — product-ready first-run

> **Status:** met (2026-09-10).
> Does **not** reopen Goal 20–29 as incomplete.
> Pin stays `d981de1229ef899957bbe968bc8dcda02a21f477` `v0.85.1`.
> Solo agent. Automate every reversible first-run blocker.

## Why

Goal 29 closed program leftovers. Operators still cannot hand CADR to a
stranger as a mature product. Delivery binary is stale. README leads with
migration ledgers, not a quick start. There is no rerunnable first-run smoke.

## Done predicate (all must hold)

1. `./scripts/check-root-binary.sh` exits 0 on tip (`root cadr binary is fresh`).
2. README opens with a **Quick Start** a stranger can follow (build → credential → one `-p` prompt).
3. `scripts/smoke-first-run.sh` exits 0 (version, help, offline no-key path, print-mode when keys exist or faux skip documented).
4. `./scripts/verify.sh` exits 0, or every failure is fixed in this goal.

## Out of scope

- Paid-provider live e2e matrices beyond one `-p` smoke when keys are present
- Turning 320 `publicApiExports` intentional-differences into match
- Unbounded microbench ≤1.0× and dialog remesure without a pair machine
- Force-push / release tag publish (operator arms the tag)

## Tracks

| track | stop | result |
|---|---|---|
| **P-binary** | `check-root-binary.sh` fresh | closed (fresh tip binary) |
| **P-docs** | Quick Start at top of README | closed |
| **P-smoke** | `smoke-first-run.sh` exits 0 | closed |
| **P-verify** | `verify.sh` exits 0 or failures fixed | closed (`verify.sh` exit 0; render I04 pins cleared) |

## Claimed

- Open 2026-09-10. Solo execution toward product-ready first-run.
- Met 2026-09-10. Four tracks closed. Stranger path is build → key → `-p` → interactive.
