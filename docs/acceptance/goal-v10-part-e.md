# Goal 10 Part E release preparation

Date: 2026-08-01. Status: implementation and release materials committed in
`80d962069`; the final release gate passed. Tag and GitHub Release intentionally
await explicit user confirmation.

## Frozen identity

**cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)**

`version.sexp` is the single numeric production version source. All eight ASDF
systems, both native binaries, TUI, HTTP User-Agent, and Radius derive from it.
The CLI release-identity helper combines that value with the frozen upstream
relationship; the test
`GOAL10-PART-E-RELEASE-IDENTITY-HAS-ONE-VERSION-SOURCE` requires the exact
identity above in `--version`, README, CHANGELOG, and this Release draft.

The `0.2.0` choice closes the `0.1.x` migration window, includes all Goals
1–11 work, and removes the documented legacy `PI_CL_*` environment fallback.
It does not claim alignment with an older tag alone: the baseline is precisely
38 commits beyond `v0.83.0` at `74caa2649`.

## Release draft

Release title:

```text
cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

Release body:

> First formal Cadr release: a native Common Lisp/SBCL implementation aligned
> with pi `v0.83.0` plus 38 commits at `74caa2649`.
>
> Build with `QUICKLISP_SETUP=/absolute/path/setup.lisp ./build.sh`. SBCL 2.4+
> is required; systems without `sb-core-compression` receive an uncompressed
> native image. `./scripts/verify.sh` is the release gate.
>
> Deterministic coverage includes the complete 363-file parity ledger
> (`362 C / 0 U / 0 M / 1 N/A`), isolated native builds, process/PTY/Unix-socket
> harnesses, and Goal 11 performance/stability budgets. Provider fixtures are
> deterministic evidence; available DeepSeek and OpenAI Codex OAuth paths are
> separately live-tested, while unavailable credentials are explicit skips.
>
> Intentional differences are limited to Common Lisp/SBCL build and extension
> ecology, approved selector/title/originator behavior, the Lisp-native
> tool-failure restarts/event, and the explicit loopback-only Slynk debugging
> service. Slynk permits arbitrary in-process evaluation and is not a sandbox.
>
> Thanks to the pi authors and contributors for the reference design. Cadr is
> independent, unaffiliated, MIT-licensed software; provider subscription and
> OAuth use remain subject to provider terms.

## Publication boundary

No tag has been created and no GitHub Release has been published. The proposed
tag is `v0.2.0`; both operations require the user's next explicit confirmation.
Rerun `./scripts/verify.sh` immediately before publication if HEAD changes.

## Pre-publication evidence

- `./scripts/test-cl.sh`: `7192 checks / 7192 pass / 0 skip / 0 fail`.
- `./build.sh`: passed the deterministic suite and produced a native image;
  this SBCL lacks `sb-core-compression`, so the documented uncompressed
  fallback was exercised successfully.
- `./cadr --version`: exactly
  `cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)`.
- `GOAL10-PART-E-RELEASE-IDENTITY-HAS-ONE-VERSION-SOURCE`: `32/32` checks.

Final `./scripts/verify.sh` result on `80d962069`:

| Stage | Result |
|---|---|
| deterministic FiveAM | PASS; 7192/7192, 0 skip, 0 fail |
| isolated `cadr` build | PASS; repeated the 7192-check gate |
| isolated `cadr-server` build | PASS; repeated the 7192-check gate |
| Goal 11 performance/stability | PASS; 4.00ms frame/key/stream, 162.32ms cold start, 1200-turn heap growth 40.3MiB, max GC 68.0ms, 10MiB load/resume/continue 284/284/272ms |
| retained native/process/PTY/socket/TUI harnesses | PASS; all six stages |
| credential-gated live FiveAM | PASS; 8 items, 7 run/pass, Anthropic skipped for missing credential; 32 checks, 31 pass, 1 skip, 0 fail |
| DeepSeek live TUI | PASS; two-turn edit, resize, CJK, autocomplete, undo, kill-ring, and terminal restoration |

The deterministic table and live table both contain only `PASS`; the sole live
skip is explicit and credential-equivalent to the baseline mechanism. The
native image's separate real Slynk protocol probe is recorded in Part D.
Publication requires a fresh gate if HEAD changes after this docs-only
closeout.

## Baseline re-anchor addendum (2026-08-11)

Goal 18 Part L moved the fixed pi baseline to v0.84.1; the frozen identity
above remains the historical record of the 0.2.0 preparation.  The current
release identity is:

```text
cadr 0.2.0 · aligned with pi v0.84.2 (+0, 914cf1472)
```
