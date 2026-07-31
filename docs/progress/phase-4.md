# Phase 4 progress: persistence, retries, build, and acceptance

> Historical report: `71efc6f0...` below is the audit anchor used by this
> phase. Goal 9 moved the current normative baseline to
> `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.

> Superseded policy note (2026-07-30): `--yolo` and the core confirmation path
> referenced below were removed after Phase 7. The live smoke retains only a
> script-level cost/side-effect opt-in.

## Completed

- Append-only JSONL sessions with immediate flush, all first-version message
  types, strict header/middle-record validation, incomplete-tail recovery,
  canonical-cwd selection, and CLI `--continue`.
- Bounded provider retries: at most two retries, exponential backoff, numeric
  `Retry-After`, retryable HTTP status classification, and SSE retry only before
  the first provider event.
- The phase originally verified Dexador status/body/headers and true streaming.
  Phase 9 superseded that transport with native HTTP while retaining the same
  status, timeout, retry, and separately flushed loopback SSE coverage.
- Feature-aware native image options omit `:compression` entirely when SBCL
  lacks `:sb-core-compression`, while preserving command-line runtime options.
- Deterministic fixture-repository acceptance covers read → wrong edit → failed
  test → corrected edit → passing test.
- README documents build, provider configuration, defaults, tools, confirmation,
  sessions, and first-version differences.

## Verification

```bash
./scripts/test-cl.sh
```

Result: 249 checks, 249 passed (`pi-ai` 135, `pi-agent` 40, `pi-cli` 74).
This is the historical Phase 4 count; the Phase 9 report contains the final
all-system total.

```bash
npx tsx scripts/export-ts-payloads.ts \
  --reference /tmp/tmp.2AyfDOAyVq \
  --output /tmp/pi-cl-payloads-final
diff -ru --exclude README.md \
  test/fixtures/requests /tmp/pi-cl-payloads-final
```

Result: no diff against
`earendil-works/pi@71efc6f0c1909874ec8c944637a9ae7fc0e2d508`.

```bash
HOME=<empty-temporary-home> \
QUICKLISP_SETUP=/root/quicklisp/setup.lisp \
SBCL=/root/.local/bin/sbcl ./build.sh
file pi-cl
./pi-cl --version
./scripts/acceptance-smoke.sh
```

Result: SBCL 2.6.7 without `:sb-core-compression` produced an uncompressed
Linux x86-64 executable; help/version and two-process continuation passed.

## Intentional differences

- Sessions remain linear JSONL without upstream branching, compaction, export,
  or custom message types.
- Retry-After HTTP dates are not parsed in the first version; decimal seconds
  are honored and capped at 60 seconds.
- The executable is an SBCL native image for Linux/glibc, not a static binary.

## Residual acceptance item

No Anthropic, OpenAI, or Gemini API key is present in the audit environment.
Provider E2E coverage therefore uses exact request capture plus recorded raw SSE
and complete-response fixtures. `scripts/live-anthropic-smoke.sh` is ready and
fails before network access when the key is absent; an authorized invocation
remains the external deployment check. The repository-level live smoke is
separately gated by `ANTHROPIC_API_KEY` and
`PI_CL_ALLOW_LIVE_TOOL_SMOKE=1` before it performs tool side effects in its
isolated temporary fixture.
