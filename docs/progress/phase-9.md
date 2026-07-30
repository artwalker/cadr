# Phase 9 progress

Phase 9 replaces the v1 infrastructure libraries without changing the frozen
provider, agent, extension, session, or frontend contracts.

## Replacement report

The measurements below are warm-process SBCL 2.6.7 microbenchmarks on the
delivery host. They compare 10,000 operations on a roughly 6 KiB JSON value,
50,000 equivalent CLI/schema parses, and 200 fresh loopback HTTP requests.
They are directional evidence, not product throughput claims.

| Replaced library | Native module | Test evidence | Measured comparison |
|---|---|---|---|
| `com.inuoe.jzon` | `src/pi-ai/json.lisp` | RFC values, JSONTestSuite 95 required-valid + 188 required-invalid files, exact large decimals, bounded nesting, finite output, every provider/session fixture | parse 114.4 vs 115.2 µs/op; stringify 74.8 vs 62.8 µs/op. Native parse is equivalent; stringify is about 19% slower and remains negligible beside network latency. |
| `clingon` | `src/pi-cli/arguments.lisp` | values, `=`, repeated extensions, flags, missing values, unknown options, help/version | 1.60 vs 8.64 µs/op; native is about 5.4× faster. |
| full regex engine | deferred `cl-ppcre` | existing glob/grep, `.gitignore`, regex/literal/filter/limit suites | No replacement benchmark: `goal2.md` explicitly allows this deferral. Traversal and filtering remain project code. |
| `dexador` | `src/pi-ai/http.lisp` | real socket streaming, strict/truncated content-length, close-delimited and chunked bodies, status/retry mapping, auth redaction, timeout classification, SSE timeout | 10.48 vs 10.20 ms/request through a fresh loopback connection; native is about 2.7% slower. Real DeepSeek HTTPS/SSE passed. |

Two additional production dependencies were removed:

- `cl-jschema` became the native tool-schema validator in
  `src/pi-agent/schema.lisp`; nested objects/arrays, scalar constraints,
  composition, local references, malformed schemas, and JSON pointers are
  covered. Equivalent parse-plus-validate measured 4.24 vs 13.84 µs/op,
  about 3.3× faster.
- `bordeaux-threads` became direct `sb-thread`; the same lock benchmark was
  0.036 µs/op for both, while concurrency, refresh-lock, extension snapshot,
  bash reader, and TUI worker regressions remain green.

Production UTF-8 conversion also moved to SBCL primitives, removing direct
`babel`, `flexi-streams`, and `usocket` dependencies. Those libraries remain
in test systems where they help construct independent binary streams and
loopback servers; some are also transitive implementation dependencies of the
permitted `cl+ssl` TLS binding, but no production source calls them.

## Verification

```text
./build.sh
  pi-ai:    256/256
  pi-agent: 156/156
  pi-tui:    59/59
  pi-cli:   161/161
  total:    632/632

  SBCL without sb-core-compression emitted an uncompressed native image.

./scripts/acceptance-smoke.sh
  help, --continue, and exact --resume passed

./scripts/live-deepseek-smoke.sh
  native HTTPS + Chat Completions SSE passed

./scripts/live-extension-smoke.sh
  DeepSeek write → reload → invoke passed

PI_CL_ALLOW_LIVE_TOOL_SMOKE=1 ./scripts/live-repo-smoke.sh
  DeepSeek observed failure → edit → passing rerun passed

./scripts/live-tui-smoke.sh
  two-turn write/edit/read, resize, CJK, and termios restoration passed

./scripts/live-openai-oauth-smoke.sh
  real ChatGPT OAuth + OpenAI Codex Responses streaming passed

npm run check
  Biome, tsgo, browser smoke, and web-ui TypeScript checks passed
```

The TUI smoke now waits for the first agent turn to leave `working` state
before submitting the second turn, preventing the test harness from racing the
frontend.

`dexador`, `com.inuoe.jzon`, `clingon`, `cl-jschema`, and
`bordeaux-threads` have no production source or production-system references.
The final inventory is in `docs/dependency-audit.md`.

## External acceptance gate

Acceptance item 1a passed after a real ChatGPT `/login openai`: pi-cl stored
`~/.pi-cl/auth.json` with mode `0600`, and
`scripts/live-openai-oauth-smoke.sh` completed an OAuth-authenticated Codex
Responses streaming request. Recorded refresh, PKCE, callback, permission,
redaction, and exact Codex request tests also pass.
