# Goal 15 Part D: permanent fixed-baseline render gate

Commit: the commit containing this report.

## Result

The fixed-baseline differential is now a permanent release gate rather than a
manual Goal 15 artifact. `scripts/render-diff.py gate` captures all 12 manifest
scenarios at both terminal dimensions, using both real PTY drivers, before it
invokes the fail-closed analyzer on those fresh artifacts. A single Cadr ASDF
cache is shared across the 24 isolated captures; each capture still receives a
fresh HOME and working directory. The retained pi commit object in this
repository is the default baseline source.

`scripts/verify.sh` runs the orchestration regression and then the complete
real-input gate as deterministic stage `fixed-baseline render differential`.
It passes the real scenario manifest and disposition ledger explicitly, so a
synthetic self-test or historical capture cannot stand in for the release
evidence.

The permanent documentation now states the boundary precisely:

- raw PTY bytes and SHA-256 files remain authoritative;
- normalization is limited to the approved exact-value substitutions;
- every non-aligned checkpoint needs a current disposition;
- I01 and I02 remain the two approved intentional-difference classes;
- the differential is the only cross-implementation rendered-output oracle,
  while the four parity ledgers remain Cadr-side implementation evidence.

The baseline-upgrade procedure now requires updating both render-diff baseline
commit fields, refreshing the pinned model-data artifact digest when needed,
running the complete gate, and obtaining a disposition for every new
difference. Missing, duplicate, stale, or wrong-baseline dispositions fail.

## Test-first evidence

The orchestration tests were written before `gate` existed. Their first run
failed twice with:

```text
AttributeError: module 'cadr_render_diff' has no attribute 'gate'
```

The implemented regressions prove that all 12 x 2 pairs are captured with
`side=both`, that the Cadr cache is shared only within the gate run, and that
analysis is never invoked after an incomplete capture matrix.

The first real cold capture used the former 20-second action timeout and failed
waiting for Cadr's first synchronized render. A single 60-second capture proved
that the delay was cold ASDF compilation, not a rendering hang. The permanent
gate therefore uses a 60-second per-action bound and one gate-local ASDF cache;
it does not weaken HOME, cwd, credential, raw-byte, or disposition isolation.

## Real differential evidence

The standalone real-input gate and the gate embedded in `verify.sh` both
completed with the same totals:

```text
render-diff gate: captured=24/24 scenarios=12 dimensions=2
render-diff analysis: aligned=6 requires-disposition=88 adjudicated=88
```

No historical capture was read as current evidence. The analyzer consumed the
fresh artifacts produced earlier in the same gate invocation.

## Verification

The standalone deterministic suite completed with all nine systems included:

```text
cadr test summary: systems=9 checks=14640 pass=14640 skip=0 fail=0
```

`./scripts/verify.sh` completed every deterministic stage:

```text
root cadr binary freshness                       PASS
code organization gate                           PASS
real source parity ledger                        PASS
source parity drift self-test                    PASS
deterministic FiveAM                             PASS
isolated cadr build                              PASS
isolated cadr-server build                       PASS
Goal 11 performance and stability gate           PASS
native acceptance smoke                          PASS
native process modes                             PASS
migration PTY smoke                              PASS
Unix socket server smoke                         PASS
terminal lifecycle PTY                           PASS
deterministic TUI harness                        PASS
fixed-baseline render differential               PASS
```

Its complete live report ran seven items successfully, skipped the Anthropic
item because `ANTHROPIC_API_KEY` was not set, and recorded 32 checks: 31 pass,
one credential skip, zero failures. The DeepSeek live TUI stage also passed.

The delivery root image was rebuilt before this final verification. The
freshness gate reported:

```text
binary build time: 2026-08-04 15:58:07.674317656 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
latest src commit: 700635b75a3f8c2bdf859efeb4b815d38226fcf2 2026-08-04T15:11:13+08:00
root binary freshness: root cadr binary is fresh
```

Part D changes no production source file; the delivery image is later than the
last Part C source commit and the latest source mtime.
