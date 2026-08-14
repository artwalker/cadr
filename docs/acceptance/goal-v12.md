# Goal 12 acceptance ledger

## Part A0 — Goal 11 continuous-input baseline correction

Status: complete. Implementation/gate commit `82db71b8c`; the evidence commit is
pending this chapter landing in the ledger.

A0 did not modify `src/`. What it corrects is the acceptance yardstick: the old
pi comparison only measured main-screen, while the new archive directly drives
the production `TuiAltScreen` raw input → render request → immediate
requested-frame flush. Both sides use 100×40, N=5000, five fresh fixtures,
default GC and exactly the same 1024-event trace.

pi continuous median/p95/p99/max are
315.576/347.536/365.552/427.549ms; cadr is
32.001/40.001/48.001/68.002ms. cadr is 6.3–9.9× faster on this fixed synthetic
trace; therefore an absolute 32–48ms may still be perceptible, but it is not a
regression added relative to the baseline, and it does not authorize
introducing virtual scrolling or transcript memoization that the baseline does
not have.

The gate formula is
`max(2*pi_q, pi_q + max(5ms, 6*pi_run_MAD_q))`, covering median/p95/p99;
it is enforced only on the same archiving host, and on other hosts it
explicitly reports informational. The existing 50/150/500ms absolute budgets
are retained. The archived artifact, its own SHA, the source object, the
clean-built dist trees, the lock object, the dependency tree, the event trace,
the five rounds of raw samples and the recomputation of the summary all enter
the gate.

Evidence:

- pi artifact: `docs/benchmarks/goal-v11-pi-baseline.json`, SHA-256
  `56e09adc50af1c9433111cc018b095c059f99bf7ada366f5d437f64d64b46ad9`;
- cadr artifact: `docs/benchmarks/goal-v12-a0-cadr.json`, SHA-256
  `8f85b41714f142f721218009bf40524e0ff842c4c6c3d76dda486595ca05d414`;
- regressions: `test_committed_fixed_baseline_artifact_passes_full_contract`,
  `GOAL11-CONTINUOUS-ALT-INPUT-BENCHMARKS-ARE-RELEASE-GATED`;
- `python3 test/goal11-performance-gate-test.py`: 5 tests / OK;
- `./scripts/test-cl.sh`: exit 0, every deterministic suite 0 fail;
- fixed-baseline gate: PASS, same-machine relative gate enforced.

Why the old gate did not catch it: it had a continuous Cadr trace but no pi
alt-screen trace of the same kind; structural and event-result assertions
cannot answer "how much slower than the baseline counts as a defect". What this
round adds is a paired, same-path baseline contract whose raw samples can be
recomputed, and it no longer substitutes main-screen numbers for the
mouse/wheel yardstick.

## Part A — full fixed-baseline source audit

Status: audit complete, awaiting user adjudication; Part C not entered.

Under the fixed baseline `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`, the
command

```sh
git -C /tmp/cadr-parity-74caa2649 ls-tree -r --name-only 74caa2649 -- packages \
  | awk '$0 !~ /\.test\.ts$/ && $0 ~ /\.ts$/' | sort
```

produces 595 unique files, and the manifest SHA-256 is
`242d90e03ae708b9ea30d71747052af80f6d19e62eec3990a5863c62a614965d`.
For every file, the top-level/exported surface, the functionality, the specific
Cadr symbol/location, the three-class verdict and the complete baseline line
span are all written into [`docs/source-parity.md`](../source-parity.md). The
ledger SHA-256 is
`4603646c6a780466af6df2900b02afc6696b1fff00463c0eed3381ec92417aac`.

| package | files | implemented | intentional difference | missing |
|---|---:|---:|---:|---:|
| ai | 183 | 117 | 30 | 36 |
| coding-agent | 289 | 139 | 27 | 123 |
| agent | 42 | 25 | 11 | 6 |
| tui | 37 | 23 | 1 | 13 |
| server | 13 | 13 | 0 | 0 |
| storage | 12 | 12 | 0 | 0 |
| evals | 10 | 6 | 2 | 2 |
| protocol | 9 | 8 | 1 | 0 |
| **total** | **595** | **343** | **72** | **180** |

Of the 180 missing items, 99 are shipped runnable examples and 81 are
production/helper capabilities. The suggested batches, ordered by dependency,
are: TUI composition 19, Apple Terminal modifier 2,
agent/session/coding core 22, AI catalog/OAuth/transport/stream 36, eval
lifecycle 2, runnable examples 99. The 72 "intentional difference" rows are retained line by
line and have not yet been approved on the user's behalf.

Mechanical re-check: rendered paths 595, unique 595; `diff -u` against the
manifest produces no output; the three-class counts are 343/72/180; all 595/595
rows carry exact baseline `file:start-end` evidence. Part A's own changes are
only `docs/source-parity.md` and this report, with zero changes to `src/`; the
user's existing working-tree changes to `docs/acceptance/goal-v8-final.md` are
left as they are and are not included.

The limits of this axis are recorded honestly: it can find a missing source
capability, but it cannot prove that an implementation of the same name is
internally equivalent in behavior down to the letter; parity-map, the
performance gate and the user's A/B remain irreplaceable.

## Part C1 — TUI composition (19)

Status: implementation and regression tests recorded in the ledger.
Implementation commits `76e85dcc4`, `86ff53909`; for the commit of this chapter
and the ledger evidence, see the commit this section is in.

This batch fills in all 19 missing source capabilities as a native Common Lisp
composition layer, without replacing the hand-written full-screen assembly of
the existing production CLI, so the byte-for-byte snapshots of the existing
transcript, the base screens and the 15 overlays stay unchanged. The
construction chosen is a CLOS composition protocol: generic functions for the
component/focus lifecycle, inheritance for containers so that child-component
invalidation and focus propagation are shared, and primitives such as
Box/Text/Spacer/Markdown/Image/Settings/Loader reused through composition; no
TypeScript class was copied line by line, and there is no new third-party
dependency.

The new capabilities come in two layers:

- `src/cadr-tui/composition.lisp`: the general component/focus/container/root
  protocol, caching, invalidation, overlay, input listening and renderer
  scheduling, plus 10 reusable components;
- `src/cadr-cli/interactive-components.lisp`: key hint, dynamic border,
  bordered loader, countdown, Armin, Daxnuts and the Earendil announcement. The
  animations expose an explicit tick seam, so the regression tests do not
  depend on sleep or on timing races.

Behavioral boundary: what this batch establishes is the reusable source surface
that was missing until now; the default CLI still takes the original path, so
there is no observable behavior change, and no snapshot difference is covered
up by normalization or weak assertions. Earendil, like the baseline, keeps the
full text announcement when the bundled image does not exist. Daxnuts uses the
baseline's exact 32×32 RGB payload; Armin covers seven animation states.

Gates: the eight `GOAL12-TUI-*` tests cover the component tree, cache
invalidation, width/background, image ids, loader cancellation, settings search
and submenus, the protocol shared by the two editors, and root/overlay/input;
the five `GOAL12-CODING-AGENT-*` tests cover every dependent component and the
public barrel. The ledger goes from `coding-agent 139/27/123` to `147/27/115`,
`tui 23/1/13` to `34/1/2`, and the whole repository to
`362 implemented / 72 intentional difference / 161 missing`; the remainder is exactly
99 examples plus 62 production/helper capabilities.

Verification: the deterministic suite is
`7823 checks / 7823 pass / 0 skip / 0 fail`; all 11 deterministic stages and 2
live stages of the full `./scripts/verify.sh` PASS, with the live report being
`32 checks / 31 pass / 1 skip / 0 fail` (only `ANTHROPIC_API_KEY` is missing).
The root `cadr` build time is
`2026-08-02 06:24:33.660346183 +0800`, later than the
`2026-08-02T06:11:50+08:00` of `86ff53909`, the last `src/` commit at that
time, and the binary freshness gate is PASS.

## Part C2 — Agent/session/coding core (22)

Status: implementation and regression tests recorded in the ledger.
Implementation commits `2799ffc82`, `19dc334b7`; for the commit of this chapter
and the ledger evidence, see the commit this section is in.

This batch fills in 6 `agent` and 16 `coding-agent` source capabilities. The
agent layer adds abandoned-branch collection, file-operation accumulation,
token-budget preparation and summary generation, full message projection, and
an authenticated `/api/stream` proxy reducer; `agent-navigate-tree`
now takes the full branch-summary path when the caller asks for it, while
keeping the original first two return values and the non-summarizing default
path unchanged. The tool execution context becomes a CLOS class/generic
protocol, so that tests, embedders or a remote executor can replace the
read/write/edit/bash backend, while the production default backend is still the
native filesystem and processes.

The coding-agent layer adds centralized auth guidance, the `:medium` default
thinking constant, a named EventBus, runtime timings, a resumable watcher, a
JSON-with-comments scanner, path/cloud-sync, shell/env/detached-process, the
fd/rg tool manager, Windows native quarantine, and a bounded UTF-8 output
accumulator. The construction chosen is small native modules and CLOS generic
functions, not copies of TypeScript classes: polymorphism where the backend
must be replaceable, and plain functions and structures for pure-value and
lifecycle capabilities, avoiding a useless object layer for simple tools.

Observable behavior: the default production path, the existing session wire,
agent event/JSON/RPC, the base screens, the 15 overlays and the payload
fixtures are all unchanged. The new branch summary is triggered only on the
existing explicit `summarize-p` path; the EventBus and runtime timings are not
wired into the fixed agent event spine; the default methods of the tool backend
reuse the original operations verbatim. This batch therefore fills in source
surface, and does not change an existing contract by normalization or weak
assertions.

Gates: `GOAL12-AGENT-*` covers file operations, branch preparation/generation,
the tree hook payload, bash/custom/summary message projection, proxy
text/thinking/tool/usage/error reduction and execution-context dispatch;
`GOAL12-CODING-CORE-*` covers guidance, defaults, the EventBus, timings,
JSON/path/shell/watcher, fd/rg and the Windows fallback, the split UTF-8
accumulator, temp-file lifecycle and backend replacement for the four built-in
tools. The final deterministic suite is
`7895 checks / 7895 pass / 0 skip / 0 fail`.

The ledger goes from `coding-agent 147/27/115` to `163/27/99`, `agent 25/11/6`
to `31/11/0`, and the whole repository to
`384 implemented / 72 intentional difference / 139 missing`. The remaining items are exactly
99 examples, 36 AI, 2 eval and the 2 Apple Terminal rows the user explicitly
deferred.

## Part C3 — AI catalog/OAuth/transport/stream (36)

Status: implementation and regression tests recorded in the ledger.
Implementation commits `c215dda40`, `dee7cee7c`, `cc1b37374`,
`40950bd06`, `3cbf0528f`, `fe1c58c1e`; for the commit of this chapter and the
ledger evidence, see the commit this section is in.

This batch fills in all 36 AI source capabilities. The Common Lisp constructs
are layered by responsibility: plain functions for pure-value capabilities
(JavaScript UTF-16 `shortHash`, JSON repair, deferred/grammar tool placement,
model-data hash/manifest); structure/CLOS + condition variables for the event
stream and the image-model runtime, which have independent
producer/consumer lifecycles; provider login/refresh dispatched through
runtime-provider function slots; and native HTTP proxy/CONNECT, RFC 6455
sockets and a per-session continuation cache for the Codex transport. There is
no new third-party dependency.

The key contracts include: all provider-owned OAuth flows and store/filter
wiring; the deferred/grammar/hash wire semantics of Anthropic/OpenAI/
Mistral; HTTP(S)_PROXY/NO_PROXY; the image API registry; the schema v3 catalog
manifest and the structure/per-file SHA-256 of the 37 shards; the generation
time embedded into the released image; a pure-Lisp PNG fixture generator; Codex
SSE/WebSocket/websocket-cached/auto, connection reuse, delta continuation, full
debug stats, session cleanup, optional zstd (degrading to no compression when
it is unavailable), and a standalone cached transport probe.

The observable behavior changes all converge on the baseline: `auto` and
`websocket-cached` now share the continuation cache; only a WebSocket failure
before the first event may sticky-fallback to SSE, and replay is forbidden
after the first event; provider tool/history IDs, deferred tools,
reasoning/options and payloads are locked down by fixtures and exact event
assertions. The native generator for the fixed catalog is split at the hydrated
canonical shard boundary: it first verifies the audited 37-shard manifest, then
deterministically materializes the 1153-model Lisp catalog; that boundary does
not change the fixed-baseline output.

Gates: the five `GOAL12-*` AI test files cover the
capability/provider/auth/model-data/WebSocket layers;
`scripts/check-model-data.lisp` and `scripts/generate-models.lisp` were
actually run and passed; `cadr-ai` is `2117 checks / 2117 pass / 0 skip / 0 fail`.
The ledger goes from `ai 117/30/36` to `153/30/0`, and the whole repository to
`420 implemented / 72 intentional difference / 103 missing`; the remainder is exactly 99 examples,
2 eval and the 2 Apple Terminal rows the user explicitly deferred.

## Part C4 — Eval lifecycle (2)

Status: implementation and regression tests recorded in the ledger.
Implementation commit `797a9cbbe`; for the commit of this chapter and the
ledger evidence, see the commit this section is in.

This batch fills in `extensions.eval.ts` and `vitest-evals/reporter.ts`. The
extension authoring suite now has the same two-row harness as the baseline: a
baseline that deletes the Guidelines/documentation, and a candidate that keeps
the full prompt and deletes only the CWD tail; with the create/reload/use input
fixed, the native judge checks the generated source, the canonical
`cadr-agent` extension API, loader errors, the registered `hello`, the
successful `hello({name: "Bob"}) -> Hello, Bob!` tool result and the verbatim
final response. The Lisp loader automatically puts each extension into an
isolated package with `(:use :cl :cadr-agent)`, so the criterion for the
canonical API is that the source uses
`define-tool`/`cadr-agent:define-tool` rather than copying the TypeScript
import over; this is a mapping made inevitable by the implementation language,
and it does not weaken the functional contract. The generated `hello.lisp` is
retained as a UTF-8 Common Lisp source artifact.

The reporter expresses the runner case and the lifecycle state with Common Lisp
structures, and does not copy the Vitest class.
Every harness case appends to a schema-v1 `runs.jsonl`, with the artifact root
fixed at `0700` and the JSONL and session/source files fixed at `0600`; the
metadata excludes the run ID and the embedded session snapshot, and keeps the
iteration and other custom metadata. The finish phase constructs an observation
from the iteration artifact, score, usage, timings, errors and test status, and
calls the existing summary; on interruption it prints
`Eval comparisons unavailable: test run interrupted.` verbatim.
`eval-main --suite extension-authoring` wires the two-row suite into that
lifecycle, and the existing `smoke`/`extensions` entry points are unchanged.

The tests went red first and green after: while the new reporter file did not
yet exist, ASDF failed explicitly; after implementation
`cadr-evals` is `150 checks / 150 pass / 0 skip / 0 fail`. The gates are
`EXTENSION-AUTHORING-PROMPT-VARIANTS-MATCH-BASELINE-BOUNDARIES`,
`EXTENSION-AUTHORING-HARNESS-TABLE-REGISTERS-BASELINE-AND-CANDIDATE`,
`EXTENSION-AUTHORING-JUDGE-REQUIRES-SOURCE-API-LOADER-TOOL-AND-RESPONSE`,
`EXTENSION-AUTHORING-HARNESS-CAPTURES-SOURCE-ERRORS-TOOLS-AND-ARTIFACT`,
`EXTENSION-AUTHORING-SUITE-RUNS-BOTH-ROWS-THROUGH-REPORTER-LIFECYCLE`,
`EVAL-HARNESS-REPORTER-APPENDS-PERMISSIONED-RECORDS-AND-SUMMARIZES` and
`EVAL-HARNESS-REPORTER-INTERRUPTED-NOTICE-IS-EXACT`.

The ledger goes from `evals 6/2/2` to `8/2/0`, and the whole repository to
`422 implemented / 72 intentional difference / 101 missing`. The remaining items are exactly
99 examples and the two Apple Terminal rows the user explicitly deferred; this
batch has no new dependency and changes no existing observable behavior.

## Part C5 — Apple Terminal modifier (2, complete)

Status: implemented after the user revoked the original "not applicable to the
target platform" deferral adjudication. That adjustment is a correction of
product priority, not a re-verdict of a platform capability into intentional difference.

- `src/cadr-tui/native-modifiers.lisp:3-78` implements the baseline's four
  CoreGraphics masks, the Darwin/arm64/x64 gating, the
  `CGEventSourceFlagsState` FFI and the fail-closed query.
- `src/cadr-tui/terminal.lisp:159-178,275-307,518-565` implements Apple
  Terminal session detection, and queries Shift only on the Apple Terminal
  Return path, emitting `ESC[13;2u` on a hit. For a non-Apple Terminal, a
  non-Return key and Shift not pressed, the original bytes are unchanged.
- No ASDF closure dependency, third-party library, external binary or
  distributed-artifact content was added; it calls only the CoreGraphics that
  ships with macOS, so it does not trigger the new-dependency authorization
  process.
- The verification tier is "implementation complete, platform not actually
  testable". This machine has no macOS/Apple Terminal, so
  `APPLE-TERMINAL-NATIVE-MODIFIER-FIXTURES-MATCH-COREGRAPHICS-MASKS`,
  `APPLE-TERMINAL-NATIVE-MODIFIER-QUERY-IS-FAIL-CLOSED`,
  `APPLE-TERMINAL-SESSION-DETECTION-MATCHES-BASELINE` and
  `PROCESS-TERMINAL-QUERIES-SHIFT-ONLY-FOR-APPLE-TERMINAL-RETURN` can only
  prove the fixture cross-implementation comparison and the integration
  branch, and claim no live verification.

The goal regression is `595 = 523 implemented + 72 intentional difference + 0 暂缓/missing`,
reaching zero-deferral status for the first time.

Mechanical acceptance:

- The four Apple Terminal regression tests total
  `30 checks / 30 pass / 0 skip / 0 fail`;
  `cadr-tui` is `1580/1580/0/0`.
- `./scripts/test-cl.sh` is
  `systems=8 / 10269 checks / 10269 pass / 0 skip / 0 fail`.
- All 12 deterministic stages of `./scripts/verify.sh` PASS, including source
  drift, the two isolated builds, the Goal 11 gate, and the six kinds of
  process/PTY/TUI harness; the credential-gated live run is
  `8 items / 7 run / 7 pass / 1 skip / 0 fail`, with Anthropic skipped for a
  missing key and the DeepSeek live TUI PASS.
- The root binary build time is
  `2026-08-02 17:49:38.252818046 +0800`, newer than the last `src/` commit
  `0c52709ab09c5d27431301307b11b4342bdf19a5`
  (`2026-08-02T17:47:20+08:00`); `./cadr --version` outputs
  `cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)`.
- This batch has zero diff in `src/cadr-ai`; the existing full-screen, overlay,
  payload, wire and non-Apple-Terminal key gates are all green.

## Part C6 — Runnable examples (99, blocked at this stage)

Status: the 17 examples that can be completed within the existing frozen API have
been ported; the other 82 have entered a blocked proposal file by file and
capability by capability, awaiting item-by-item user adjudication.
Implementation/test commit `10d5fb29f`; for the documentation wrap-up, see the
commit this section is in.

This batch first uses `examples/manifest.sexp` to build a one-to-one inventory
of the fixed baseline's 99 example sources. Each row may only be `:ported` or
`:gap`: ported must point at real Lisp source; gap must list non-empty gap ids.
The mechanical result is 99 total / 99 unique / 17 ported / 82 gap; all 42
unique gap ids map onto exactly the 19 independently adjudicable items in
[`docs/proposals/goal-v12-example-api-gaps.md`](../proposals/goal-v12-example-api-gaps.md).

The 17 functionally equivalent ports are: bookmark, claude-rules, doom keys,
WAD finder, dynamic resources, the two input transforms, model status, terminal
notify, pirate mode, plan-mode utilities, provider payload logging,
send-user-message, session-name and subagent agent discovery, plus
mac-system-theme and titlebar-spinner. The constructions continue to use
Lisp's strengths: extension entry points use the frozen macros/hooks directly,
pure algorithmic helpers stay plain functions/structures, and the
session/model domain objects are reused directly; no TypeScript class was
copied for an example, and no third-party dependency was added. The WAD
download strictly uses the baseline's uncompressed shareware WAD URL and its
raw-octet writing convention; the macOS theme and the titlebar timer are
expressed with SBCL native threads, and no API gap is invented.

This batch rejected a set of "loads but is not equivalent" false positives. The
typical example is that the current `custom` only calls the factory as
`(done)`, ignores the overlay options, and degrades the return value to line
rendering; it cannot replace the baseline's
`(tui, theme, keybindings, done) -> Component` contract for focus, animation,
dispose and the overlay handle. Likewise, deriving `mode` does not replace the
public `hasUI`, an internal agent slot does not replace the model/runtime
context, and the existing simplified renderer does not replace the full
Theme/ToolRenderContext. All those rows stay `missing`, and no internal symbol,
weak assertion or downgraded example was used to inflate the numbers.

Each of the proposal's 19 items contains the exact requirement, the fixed
baseline file:line, the affected examples, the non-example impact, the minimal
thaw surface, the alternatives and the reasons they were rejected, the freeze
impact and the rollback. Items 11–14 involve extension-local dependencies,
Gondolin, the sandbox runtime and WASM; the proposal is explicit in not
swapping an approval of capability for an approval of dependency, and the
specific dependency closure, the versions/hashes and the build isolation must
still be pre-reviewed separately.

The tests went red first and green after: while the manifest did not yet exist,
`GOAL12-EXAMPLE-MANIFEST-COVERS-EVERY-BASELINE-SOURCE-EXACTLY-ONCE` failed with
`FILE-DOES-NOT-EXIST .../examples/manifest.sexp`. Once complete, the gates
include:

- `GOAL12-EXAMPLE-MANIFEST-COVERS-EVERY-BASELINE-SOURCE-EXACTLY-ONCE`;
- `GOAL12-EVERY-EXAMPLE-GAP-IS-DEFINED-BY-THE-BLOCKED-PROPOSAL`;
- `GOAL12-PORTED-EXTENSION-ENTRYPOINTS-LOAD-WITHOUT-DIAGNOSTICS`;
- `GOAL12-PORTED-EXTENSION-REGISTRATIONS-COVER-THE-BASELINE-SURFACE`;
- `GOAL12-PURE-EXAMPLE-PORTS-PRESERVE-EDGE-CASE-BEHAVIOR`.

The five targeted gates total `503 checks / 503 pass / 0 skip / 0 fail`. The
full `./scripts/test-cl.sh` is `8590 checks / 8590 pass / 0 skip / 0 fail`.
All 11 deterministic stages of `./scripts/verify.sh` PASS, including the
isolated `cadr`/`cadr-server` builds that degrade to no compression, the Goal
11 performance and stability gate, and the process/PTY/socket/TUI harness; the
two live stages also PASS. Of the credential-gated items, 7 actually ran and
passed, one Anthropic item was skipped because
`ANTHROPIC_API_KEY is not set`, and the DeepSeek live TUI passed.

The root binary was rebuilt before delivery. `scripts/check-root-binary.sh`
records binary build time
`2026-08-02 10:18:34.175969809 +0800`, later than the
`2026-08-02T08:46:22+08:00` of the last `src/` commit
`797a9cbbe7055be59fc1f1ac1f5e6361b8f9f2e0`;
`./cadr --version` is
`cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)`.

The ledger goes from `422 implemented / 72 intentional difference / 101 missing` to
`439 implemented / 72 intentional difference / 84 missing`. The remainder is exactly the 82
proposal-blocked examples and the 2 Apple Terminal rows the user explicitly
deferred. Stopping here is the adjudication boundary for new capabilities, not
a declaration that the 82 examples are complete; re-verdicting them row by row
may continue only after the approved items are implemented.

### Part C6 intermediate checkpoint — approved API implementation and 94 ports

The user subsequently approved all 19 itemized capabilities plus the necessary
A–E core seams. Commits `5688d1c8a`, `595ba3b67`, and `5c0cc220b` close the
approved runtime/TUI/OAuth/key-release surfaces and raise the mechanical example
ledger to **99 total / 94 ported / 5 gap**. The remaining rows are exactly
`custom-compaction.ts`, `prompt-customizer.ts`, custom Anthropic `index.ts`, and
GitLab Duo `index.ts` plus its `test.ts`.

Real entrypoint auditing found that those five files still require three
production call-chain seams outside the approved file surface: compaction must
actually dispatch the already-declared lifecycle event, the real structured
system-prompt options must reach `before-agent-start`, and provider extensions
need a session-local buffered HTTP control-plane callback. These are recorded
with fixed-baseline file:line evidence and minimal thaw surfaces in
[`goal-v12-api-scope-amendment-3.md`](../proposals/goal-v12-api-scope-amendment-3.md),
commit `639035ce9`. No approximation, private `cadr-ai` call, global registry
mutation, or shell-to-curl workaround is counted.

The manifest now drives the source ledger directly, and
`GOAL12-SOURCE-PARITY-VERDICTS-FOLLOW-THE-CURRENT-EXAMPLE-MANIFEST` prevents a
future implementation/ledger split. The intermediate totals at proposal commit
`639035ce9` were **516 implemented /
72 intentional differences / 7 missing**: five proposal-blocked examples and
the two user-deferred Apple Terminal rows. `src/cadr-ai` remains unchanged.
The approved additive exports change the re-frozen extension export SHA-256 to
`61eb1b623f784b3a8f0f6fe6791c65ebe991ff314ed1d969b82f3edd57646f18`;
the 34-event set remains
`12f79b21e0e25495cb023baaf21b26f6cf9a891881b26602f6553f80af54887a`.

### Part C6 final — F/G/H and all 99 runnable examples

Status: implementation and regression tests complete; for the commit, see the
commit this section is in.

The F/G/H the user approved fill in baseline capabilities; they are not new
Cadr mechanisms:

- F wires the declared but unconnected `:session-before-compact` and
  `:session-compact` into the three real compaction paths: manual, threshold
  and overflow. The before payload contains the preparation, the branch
  entries, the instructions, the reason, the retry marker and the cancellation
  signal; a legal extension compaction is persisted as it is, cancel/abort
  stops it, and an illegal result or a handler error falls back to the original
  summarizer.
- G saves the eight-field system-prompt options that the CLI and the SDK
  actually assemble as agent state and hands them to every
  `:before-agent-start` handler as a defensive copy; after a reload the
  prompt text and the options are replaced together, and the results generated
  by the CLI and the SDK agree value by value.
- H adds a session-local buffered HTTP callback on the extension host; the
  public API accepts only HTTP(S), a restricted set of methods, string headers,
  a string/octet body, a non-negative timeout and a cancellation signal, and it
  copies both input and output. The CLI adapter reuses the existing native HTTP
  transport, preserves the status/headers/octet body, normalizes the
  timeout/abort/transport conditions, and never exposes a token, a refresh
  secret or an underlying error.

This completes the functionally equivalent ports of `custom-compaction.lisp`,
`prompt-customizer.lisp`, the custom Anthropic provider and the GitLab Duo
provider/test. The manifest's mechanical result is
**99 total / 99 unique / 99 ported / 0 gap**; the source ledger is
**595 total / 523 implemented / 72 intentional differences / 0 missing**,
reaching zero deferrals and zero missing. The four ledgers share the same
`GOAL12_LEDGER` identity, and the deterministic gate actually parses the
manifest and checks the counts, the baseline and the cross-links verbatim.

The audit of production dispatch for the 34 extension events is in
[`goal-v12-extension-event-dispatch.md`](goal-v12-extension-event-dispatch.md).
Every row gives the event, the real dispatch `file:line` and the installed
handler, and the test that drives the production path and explicitly asserts
that it was called. The only break found is
`:session-before-compact`: Goal 7 tested only return-value validation/merging
and did not drive the compaction entry point, so "the receiving end exists" was
mistaken for "the event is implemented". After this batch connected the
emitting end, manual, threshold, overflow, cancel, abort, invalid/error
fallback and the after payload are all covered by regression tests through the
production path.

The extension export text is re-frozen to
`61eb1b623f784b3a8f0f6fe6791c65ebe991ff314ed1d969b82f3edd57646f18`;
the 34-event source block is still
`12f79b21e0e25495cb023baaf21b26f6cf9a891881b26602f6553f80af54887a`.
`src/cadr-ai` stays at zero diff across the whole F/G/H batch; with no
extension compaction, no prompt-options consumer and no HTTP consumer, the
original result/event/session/JSON/RPC/overlay/payload contracts stay verbatim
unchanged.

`scripts/test-cl.sh` no longer depends on adding numbers by hand: it saves the
full FiveAM output, requires exactly eight groups of `Did/Pass/Skip/Fail`,
verifies that `checks = pass + skip + fail`, and fails closed on a missing
suite, a duplicated summary or any failure. This batch's full deterministic
result is
`systems=8 / 10233 checks / 10233 pass / 0 skip / 0 fail`.

## Part D — fixed-baseline source drift gate

Status: complete; for the commit, see the commit this section is in.

`scripts/check-source-parity-drift.sh` compares two baseline commits and lists
additions, deletions and renames under the same `packages/**/*.ts` convention
as Part A, excluding `*.test.ts`.
Every item must have a non-empty human decision in the four-column TSV; a
missing, stale or malformed row, an unknown revision or a missing disposition
file all fail. It does not swap a modified file for an audited one: a content
change still goes through the existing source/behavior review.

`scripts/test-source-parity-drift.sh` uses a temporary Git repository to prove
deterministically that A/D/R, test exclusion, failure on an undisposed row and
passing with complete dispositions all hold; `scripts/verify.sh` runs that
self-test before the build. The upgrade runbook is in
[`docs/source-parity-upgrade.md`](../source-parity-upgrade.md).
The README and architecture state the division of labor of the three ledgers:
parity-map governs observable behavior, source-parity governs per-source-file
dispositions, and performance governs the non-functional budgets; the manifest
is the machine-readable inventory of the 99 runnable examples. The
shared-identity gate makes any ledger that falls behind go red immediately.

## Final mechanical verification

The implementation, the drift gate and the ledger were recorded as
`07c00a1d1`, `9bd12e6f1` and `c1d7f5d5c` respectively. The completion audit
then found that the implementation-order table in `parity-map` still kept the
intermediate `94 complete / 5 blocked`, proving that checking only the shared
marker is still not enough; commit `07996b6aa` corrects the body text and adds
bidirectional current-summary/obsolete-summary assertions. Those assertions
first reproduced the drift with 3 failing items, and after the correction the
targeted result is `311/311`. `./scripts/test-cl.sh` was run after the commit,
and the script parsed exactly eight suites from the full output:
`cadr-ai 2117`, `cadr-agent 911`, `cadr-tui 1550`,
`cadr-cli 4943`, `cadr-storage 23`, `cadr-server 45`, `cadr-evals 150`,
`cadr-protocol 497`; summing to
`systems=8 / 10236 checks / 10236 pass / 0 skip / 0 fail`.

The root `./build.sh` exits 0; when SBCL does not include
`sb-core-compression`, it degrades per the architecture contract to an
uncompressed image. `./scripts/verify.sh` exits 0, with all twelve
deterministic stages PASS: binary freshness, the source drift self-test,
FiveAM, the isolated `cadr`/`cadr-server` builds, Goal 11 performance and
stability, native acceptance/process modes, migration PTY, Unix socket,
terminal lifecycle and the deterministic TUI harness. The two full test runs
inside the isolated builds are each exactly
`8 / 10236 / 10236 / 0 / 0`. Goal 11 is PASS (1200-turn long run, at least
10 MiB JSONL session, continuous p99 52ms, continuous GC max 92ms).

The live report is `8 items / 7 run / 7 pass / 1 skip / 0 fail`, at check level
`32 / 31 pass / 1 skip / 0 fail`; the only skipped item is
`LIVE-ANTHROPIC-STREAM-PRESERVES-TWO-TURN-CONTEXT`, because
`ANTHROPIC_API_KEY is not set`. The seven live DeepSeek and OpenAI Codex OAuth
items, and the DeepSeek live TUI, all actually ran and passed.

The final root binary build time is
`2026-08-02 17:13:08.606765195 +0800`, later than the
`2026-08-02T16:49:59+08:00` of the last `src/` commit
`07c00a1d1a0c070b9e237a2dd40c126334a2fcd4`; `./cadr --version` is
`cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)`, and the freshness gate
is PASS.

## Part D revalidation correction and screen-oracle audit

Status: the correction is complete. The real-ledger gate commit is `bd2276ad5`;
the independent full-screen oracle commit is `f91cc2178`; for the evidence of
this chapter, see the commit this section is in.

Previously `check-source-parity-drift.sh` scanned every disposition input as a
four-column TSV; it neither recognized the six-column package tables of
`docs/source-parity.md` nor knew where a table ends. So when the user ran it
against the real ledger as the usage says, the legitimate
`packages/protocol/vitest.config.ts` row and the prose outside the tables were
both reported as invalid disposition rows. The old `verify.sh` ran only the
A/D/R self-test over a temporary Git repository plus a synthetic TSV, which
really was "testing the stand-in, not the product".

The corrected Markdown parser enters a package table only after the exact
six-column header and separator, accepts only backtick-wrapped non-test
`packages/**/*.ts` paths and the three legal verdicts, and stops as soon as it
leaves the table; the body text, the explanatory paragraphs and the Summary
table all take no part in row parsing. The real-ledger gate requires, at the
same time:

- that the Summary have exactly one Total, and that the number of parsed rows
  equal that value, currently **595**;
- that the 595 paths be unique;
- that the SHA-256 of the sorted paths equal the value recorded in the ledger,
  `242d90e03ae708b9ea30d71747052af80f6d19e62eec3990a5863c62a614965d`;
- that the ordinary `--repo/--from/--to` mode additionally compare the ledger's
  path set item by item against the `--from` tree; the shallow-clone
  `verify.sh` uses an explicit `--ledger-only` and does not pretend to have the
  detached baseline object.

The real command the user gave now exits 0, printing
`Source parity ledger entries: 595`, the path SHA above,
`No added, deleted, or renamed baseline source files.` and
`Source parity dispositions complete: 0`. The synthetic regression tests
additionally lock down ignoring prose outside tables, a bad separator, a bad
verdict, a duplicate path, path-SHA drift and Summary-total drift; the last
five all fail closed with exit 2. `verify.sh` gains a separate
`real source parity ledger` stage, and the deterministic stages go from 12 to
13.

Why the old 10286 checks and 12 stages did not catch it: FiveAM did not execute
the shell parser, still less hand it the real Markdown ledger; the only
relevant shell stage used a temporary repository and a four-column TSV, and
completely bypassed the input type that was failing. However large the count,
it is useless: get the entry point wrong and the coverage is zero.

The full-screen SHA audit covers every visual hash in the repository: 13 base
screens and 15 overlays. The complete item-by-item inventory, the fixed
baseline `file:line`, the independent assertions and the fill-in status are in
the "B2 SHA snapshot independent semantic oracle audit" table of
[`docs/visual-parity.md`](../visual-parity.md). The audit results are:

- of the base screens, 8/13 already had a direct semantic assertion; thinking,
  tool collapsed, tool expanded, overflow scrolled-to-top and narrow width —
  five items — were filled in this round;
- of the overlays, 14/15 already had a case-specific line contract;
  extension-custom was filled in this round;
- two aggregate gates check the SHA case names and the oracle case names for
  set equality in both directions, then execute, case by case, the contracts
  for the first line, the natural height, the order, the spacing, the viewport,
  the preview and the full copy. From now on, updating only a hash or adding
  only a case will fail, and the oracle's expectations must not be
  reverse-engineered from the current Cadr render.

None of the existing 13+15 SHA values was modified; what was filled in is the
proof that they are "right", not a regenerated batch of hashes that could still
be protecting a wrong implementation. The two new aggregate gates contribute
266 independent checks; the full deterministic result is
`systems=8 / 10552 checks / 10552 pass / 0 skip / 0 fail`.

`./scripts/verify.sh` exits 0, with all 13 deterministic stages and 2 live
stages PASS; the two isolated builds each again reach
`8 / 10552 / 10552 / 0 / 0`. The Goal 11 gate is PASS; live is
`8 items / 7 run / 7 pass / 1 skip / 0 fail` at check level
`32 / 31 pass / 1 skip / 0 fail`, the only skip is still the missing
`ANTHROPIC_API_KEY`, and the DeepSeek live TUI is PASS.

The root binary was rebuilt before delivery. `scripts/check-root-binary.sh`
records binary build time
`2026-08-02 19:14:02.763812157 +0800`, later than the last `src/` commit
`ceb30956ca526aa9ce505da3bb6282d37f231c1d`
(`2026-08-02T18:13:41+08:00`); `./cadr --version` is
`cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)`, and the freshness gate
is PASS.

## Part D locale reproducibility correction

Status: the SHA failure the advisor sent back has been reproduced exactly on this
machine and corrected. Implementation commit
`86fff5b66`; for the evidence of this section, see the commit it is in. The
earlier conclusion in `04078ad79` that "the real-ledger gate is reproducible
under a clean checkout" does not hold; this section corrects it explicitly and
does not delete the historical record.

The SHA is recorded in `Baseline source path SHA-256` at the top of
`docs/source-parity.md`. Its input is not the whole Markdown file but the 595
UTF-8 paths parsed out of the package tables, each path followed by one LF,
then sorted, with the SHA-256 computed over that. The root cause is that the
sort did not fix the locale:

- under `LC_ALL=C.UTF-8` it computes to the value recorded in the ledger,
  `242d90e03ae708b9ea30d71747052af80f6d19e62eec3990a5863c62a614965d`;
- under `LC_ALL=en_US.utf8` the same 595 paths in locale-aware order compute to
  the `e0d986af6b596079daa0e28e3922d5b28391974554ea05337e857e27bd43436b` that
  the advisor saw.

The difference between the two runs is therefore the caller's locale, not a
dirty worktree; my previous run inherited `C.UTF-8` and so falsely reported
PASS, while the advisor failed consistently under `en_US.utf8`. After the
correction the checker fixes and exports `LC_ALL=C` at its entry point, and the
ledger document fixes the same byte-level convention; the regression test
additionally calls the checker from an actually available non-C `en_US` UTF-8
locale, and must obtain the same SHA.

`Source parity dispositions complete: 3` comes from the three-item A/D/R
synthetic TSV fixture; it is not a count parsed from the real ledger. But the
previous round really did not deliver the independent, fixed-595 regression
test the user required: the old test only read the Summary total dynamically
and compared it against the parser count, which can stay self-consistent while
both sides drift together — that was mistaking mutual consistency for an
independent oracle. The new regression test requires at the same time that the
Summary total equal a fixed 595 and that the checker's output be exactly
`Source parity ledger entries: 595`, and fails closed if either does not match.
The final wording of the synthetic self-test becomes
`synthetic dispositions=3, real ledger entries=595`, and no longer conflates
the two numbers.

`verify.sh` now runs `real source parity ledger` first, and the synthetic
`source parity drift self-test` second. A failure of the latter therefore can
no longer leave the former `NOT RUN`.
The full acceptance run was executed in a local clean clone
`/tmp/cadr-clean-verify.Zfrh4y/repo`, at revision
`86fff5b6612fd1e99b240a8821b10cb2ed1fbbe7`, with `git status --short`
producing no output before the build, and deliberately run under
`LC_ALL=en_US.utf8`. The full stage table is:

| Deterministic stage | Result |
|---|---|
| root cadr binary freshness | PASS |
| real source parity ledger | PASS |
| source parity drift self-test | PASS |
| deterministic FiveAM | PASS |
| isolated cadr build | PASS |
| isolated cadr-server build | PASS |
| Goal 11 performance and stability gate | PASS |
| native acceptance smoke | PASS |
| native process modes | PASS |
| migration PTY smoke | PASS |
| Unix socket server smoke | PASS |
| terminal lifecycle PTY | PASS |
| deterministic TUI harness | PASS |

| Live stage | Result |
|---|---|
| credential-gated FiveAM | PASS |
| DeepSeek live TUI | PASS |

The full numbers from `./scripts/test-cl.sh` are: `cadr-ai 2117`,
`cadr-agent 911`, `cadr-tui 1580`, `cadr-cli 5231`, `cadr-storage 23`,
`cadr-server 45`, `cadr-evals 150`, `cadr-protocol 497`; summing to
`systems=8 / checks=10554 / pass=10554 / skip=0 / fail=0`. The two isolated
builds in the clean clone obtain the same summary. Live is
`8 items / 7 run / 7 pass / 1 skip / 0 fail`, at check level
`32 / 31 pass / 1 skip / 0 fail`; the only skipped item is still the missing
`ANTHROPIC_API_KEY`, and the DeepSeek and OpenAI Codex OAuth items all actually
ran and passed.

The root binary was rebuilt before delivery. Its build time is
`2026-08-02 20:09:12.597914344 +0800`, later than the last `src/` commit
`ceb30956ca526aa9ce505da3bb6282d37f231c1d`
(`2026-08-02T18:13:41+08:00`); `./cadr --version` is
`cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)`, and the freshness gate
is PASS.
