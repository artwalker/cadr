# Goal 17 acceptance

> Final status: all evidence below was produced on 2026-08-08 against the
> committed Goal 17 tree. The last section holds the final command outputs
> verbatim; the four closeout findings resolved on that date are recorded with
> their regressions in the same section.

## Scope and evidence order

Goal 17 was executed in the approved order `A -> C2 -> D2 -> B -> F -> G -> C -> D`.
The three differential gates own distinct observable channels:

| Gate | Observable contract | Authority |
|---|---|---|
| render differential | terminal bytes, screen geometry, and baseline-visible render branches | fixed Pi source and PTY output at `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5` |
| tool-result differential | exact content and `isError` sent back to the model | real Pi and Cadr tool wrappers executing the same call in the same reset workspace |
| event differential | JSON and RPC event records and ordering | real Pi and Cadr faux-provider runs in both wire modes |

Raw artifacts and their hashes remain authoritative. No gate normalizes whitespace,
ANSI, prose, ordering, whole lines, tool results, or event types.

## A: truncated bash presentation

The fixed baseline has two copies for two different consumers, not two TUI rows.
It also has a separate direct user-bash component whose warning copy is not the
agent tool-block contract:

- `packages/coding-agent/src/core/tools/bash.ts:289-305` renders one
  warning-colored agent tool row, exactly
  `[Full output: <path>. Truncated: N lines shown (50.0KB limit)]` for byte
  truncation;
- `packages/coding-agent/src/core/tools/bash.ts:414-418` keeps the independent
  range footer in the model-visible tool result;
- `packages/coding-agent/src/modes/interactive/components/bash-execution.ts:190-200`
  uses `Output truncated. Full output: <path>` only for direct `!` user bash.

Cadr now renders one warning row and retains the independent model-visible copy.
The former grey range line plus yellow detail line was reduced to the baseline
agent warning; line, byte, and full-output metadata remain typed state rather
than a second UI message.
`POST-GOAL16-BASH-CONTEXT-TRUNCATION-RENDERS-ONE-BASELINE-WARNING` and the fixed-baseline
tool-result gate lock the two channels separately.

## B: fixed-baseline presentation branch inventory

The checked inventory is generated from the fixed Pi source rather than from
Cadr or from a hand-picked scenario list. The first extraction produced 707
sites and 1,228 branches; the final inventory regenerated on 2026-08-08
refines the obligation unit so that each obligation is one fixed visible
fragment (a single non-empty literal segment with its style path), not a
Cartesian product of runtime choices, and slot-only fragments are rejected as
non-obligations. It contains 423 source sites and 974 branches across 210
parsed source files; nine additional terminal assets make the fail-closed
source inventory 219 files in total. There is zero unresolved in-root
dataflow. Of those branches, 924 are printable terminal content and 50 are
terminal-protocol output and are reported separately. The gate self-test
`test_visible_inventory_accepts_whitespace_but_rejects_slot_only_obligations`
locks this model.

The extractor is fail-closed over its declared sinks, typed in-root producer
returns, slash-command metadata, authentication metadata, and terminal assets.
Its out-of-band OSC provenance helper returns every application value unchanged;
the regression
`test_instrumented_state_setter_preserves_empty_editor_exit_semantics` proves an
instrumented empty editor remains empty and exits normally. This replaced an
initially unsound implementation that embedded a zero-width marker in the editor
value and therefore changed the state under test. Pending obligations are keyed
by source site/branch and flushed with one batched output rewrite; this prevents
repeated renders from multiplying unmatched probes or making large changelog
frames alter the timing of the interaction under test.

The ordinary verifier runs 31 core scenarios in two dimensions (62 captures).
The complete gate runs 38 scenarios in two dimensions (76 captures) and is
mandatory through `scripts/verify-release.sh` before a tag and directly after an
upstream baseline upgrade. Structured exemptions are an exact, user-adjudicated
registry; the current registry is empty.

Every agent-backed significant-state checkpoint waits for a driver-side
`agent_settled` marker after the interactive event consumer has run, then drains
the PTY before recording the offset. This replaces the former 80ms scheduling
race that could capture Cadr's stale `Working...` frame while Pi had already
settled.

## C2 and D2: compaction status, cancellation, retry, and isolation

The three baseline status forms from
`packages/coding-agent/src/modes/interactive/components/status-indicator.ts:74-91`
are preserved exactly:

| reason | visible status |
|---|---|
| manual | `Compacting context... (escape to cancel)` |
| threshold | `Auto-compacting... (escape to cancel)` |
| overflow | `Context overflow detected, Auto-compacting... (escape to cancel)` |

The key label is obtained through the configured app interrupt binding. Escape
cancels the active summary request, leaves the prior session tree untouched, and
settles through one `compaction_end` with `aborted=true`.

Every compaction and branch-summary provider call now passes the single
summarization choke point. It applies the baseline retry classifier, a fresh
session id, and `cacheRetention=none` semantics. Transient transport failures
retry; deterministic failures and aborts do not. The source gate
`scripts/check-summarization-choke-point.sh` rejects a new summary call that
bypasses this owner.

## F and C: model-visible tool results and SIGPIPE

`scripts/tool-result-diff.py` runs 19 fixed scenarios through the real Pi agent
loop and Cadr tool batch. It covers all seven built-ins on success and failure,
including missing paths, permission denial, nonzero exit, timeout, output limits,
invalid arguments, UTF-16 write counting, and a deterministic pipeline.

The pipeline `/usr/bin/yes line | /usr/bin/head -n 5` originally exposed an
execution-environment defect: the inherited ignored SIGPIPE caused upstream
programs to report `Broken pipe`/`EPIPE` into the tool result. Cadr now starts the
shell through `/usr/bin/env --default-signal=PIPE`, matching the child signal
disposition used by Pi. The gate rejects those implementation diagnostics even if
both sides were ever to emit the same noise.

This establishes conclusion A from Goal 17 C3: with the same command, cwd, HOME,
PATH, locale, terminal dimensions, and fixture bytes, the old Cadr environment
differed from Pi. A same-prompt comparison alone remains invalid evidence because
the model may generate a different command.

The workspace reset preserves each scenario cwd inode between Pi and Cadr runs.
This matters because ripgrep stream order is filesystem-observable; deleting and
recreating the cwd allowed directory-hash order to masquerade as a product diff.

## G: JSON and RPC event streams

`scripts/event-diff.py` runs ten scenarios in both JSON and RPC modes, producing
40 raw artifacts. The matrix covers normal completion, turn retry,
summarization retry, deterministic failure, abort, tool failure, the extension-only
`:tool-call-error` sidecar, and manual/threshold/overflow compaction.

The normalizer has 40 exact JSON-pointer rules for timestamps, session ids, and
compaction entry ids. Missing pointers fail; wildcards are forbidden; the
scenario/mode/side registry is validated globally; the disposition ledger is
empty. The final differential is exact zero. In particular,
`:tool-call-error` remains outside both wires as frozen, while compaction uses the
baseline `compaction_start`/`compaction_end` result contract and operation-local
`agent_end.messages`.

The Cadr driver calls the production faux provider. It no longer synthesizes an
"aligned" event stream in the fixture, so the differential exercises the same
chunking, paced abort, usage/cache, retry, and partial-message lifecycle used by
the product implementation. The custom-interrupt regression additionally drives
raw `ctrl+q` through the input decoder and busy TUI controller into a live manual
compaction request; the abort predicate settles once, session entry ids/messages
remain unchanged, no compaction entry is written, and `compaction_end` reports
`aborted=true` with a null result.

## D: the three compaction questions

1. **Independent summary-input crop:** none. Pi serializes the selected compaction
   entries directly in `packages/coding-agent/src/core/compaction/compaction.ts:845-960`;
   it does not apply a second provider-window crop. Cadr does the same.
2. **Threshold:** Pi compacts when estimated tokens exceed
   `contextWindow - reserveTokens` (`compaction.ts:134-135,235-237`). With the
   272k model and the 16,384-token reserve this is 255,616 tokens, about 94%.
   Cadr now uses the same reserve directly and performs threshold compaction before
   a new prompt and after the completing run; the former quarter-window cap was a
   Cadr defect and is gone.
3. **Failure recovery:** Pi retries only transient summarization failures through
   `retryAssistantCall` (`compaction.ts:555-580`). It has no crop or alternate-model
   fallback. Abort returns immediately; a terminal failure reports the reason and
   leaves the original context intact. Cadr now has the same retry boundary and
   exact threshold/overflow guidance, including the one compact-and-retry limit for
   context overflow.

The reported 105.6% session was therefore not evidence of an extra baseline crop.
It had already passed the normal threshold; recovery can still fail if the provider
rejects the summary request after the threshold was missed or a single turn itself
is oversized. The safe user action remains `/fork` to an earlier point or `/new`;
Goal 17 adds no baseline-absent lossy fallback.

## Why the previous gates missed these defects

The prior 14,827 deterministic checks and 42 render captures proved only the
states they constructed. They did not enumerate baseline render branches, execute
tool wrappers on both implementations, or compare Pi's JSON/RPC output. Therefore
duplicate truncation copy, SIGPIPE contamination, summary retry omission, and wire
contract drift all had structurally empty coverage despite green self-referential
fixtures.

The failure was coverage topology, not assertion precision. The old render
screens were byte-precise for their hand-picked states, but no screen generated
the byte/line/overlong truncation branches or all three compaction reasons. The
request payload fixtures ended before any tool round trip, so they could not
observe text returned to the model. The JSON/RPC fixtures used Cadr's own prior
records as their oracle, so a behavior that had never matched Pi could remain
green forever.

## Release and upgrade enforcement

`scripts/verify.sh` owns the core render tier plus the exact tool-result and event
differentials. `scripts/verify-release.sh` runs that verifier first and then the
complete render inventory, propagates either failure, and never tags or pushes.
The same complete render command is mandatory immediately after a fixed-baseline
upgrade. Contract tests lock execution order, short-circuiting, exit propagation,
arbitrary-cwd resolution, and the core/full split.

## Final closeout evidence

### Closeout findings resolved on 2026-08-08

1. **fatal-crash disposition drift.** `36f181c11` aligned the faux zero-delay
   producer with Pi and legitimately changed the settled crash capture (footer
   now shows `0.0%/128k` and the bare model id, exactly like the fixed Pi
   screen) without refreshing the locked SHA. The disposition was refreshed
   after proving the new capture byte-identical across two independent runs and
   semantically inside the adjudicated I01/I02/I04 classes; the Pi-side SHA is
   unchanged in both dimensions.
2. **Full-tier baseline crash.** The slash/extension-selector metadata helpers
   threw `visible construction path is required` whenever a visible-site
   capture rendered those branches, because full-tier captures set
   `RENDER_DIFF_VISIBLE_CONSTRUCTS=1` without a sink path. The helpers now
   buffer construct markers and flush them at exit, matching the general site
   helper; regression `test_construct_markers_flush_without_construction_path`
   drives the exact failing environment.
3. **First real coverage measurement.** With the crash fixed, the full gate
   produced its first end-to-end measurement: 23 printable branches had no
   capture. The construction suite was extended to drive every one of them
   through the real production paths (package list/config/install/self-update
   success and failure, login prompt/info variants, OAuth status variants,
   external editor launch, assistant max-length error, auth guidance, Windows
   suspend notice, Anthropic subscription warning, empty clone, session import
   success and failure, reload failure, skill conflicts). Final coverage:
   672/672 printable branches, zero exemptions.
4. **Live credential switch.** Per user direction the live comparison
   credential is the Kimi For Coding API key; the OpenAI Codex OAuth live items
   were replaced by API-key equivalents with the same contracts. The
   deterministic OAuth refresh/rotation tests are unchanged.

The following fields are deliberately not inferred from an intermediate run.
They must be replaced from the final commands after all Goal 17 source and test
changes are committed:

| Evidence | Final value |
|---|---|
| `./scripts/test-cl.sh` | `systems=9 checks=15371 pass=15371 skip=0 fail=0` (2026-08-08) |
| render extractor self-test | `Ran 17 tests OK` (2026-08-08) |
| core render differential | `tier=core captured=62/62 scenarios=31 dimensions=2; aligned=6 intentional-terminal-protocol=75 requires-disposition=147 adjudicated=222` |
| full render differential | `tier=full captured=76/76 scenarios=38 dimensions=2; aligned=10 intentional-terminal-protocol=118 requires-disposition=202 adjudicated=320; visible-string coverage 672/672 printable branches, structured_exemptions=0, protocol_observed=13/34` |
| tool-result differential | `19 scenarios, 19 pass, 0 fail; baseline 74caa2649f` |
| JSON/RPC event differential | `40 raw artifacts, 0 differences, 0 resolved, 0 unresolved, 0 stale dispositions, 0 blocking dispositions` |
| Kimi live gates (`./scripts/test-live.sh`) | `Items: 8, run: 7, pass: 7, skip: 1 (Anthropic key unset), fail: 0; Checks: 32, pass: 31, skip: 1, fail: 0` |
| `./scripts/verify.sh` | exit 0 — all 20 deterministic stages PASS (binary freshness, code organization, product identity, source parity ledger + drift self-test, summarization choke point adversarial + real source, deterministic FiveAM, isolated cadr + cadr-server builds, Goal 11 performance gate, native acceptance smoke, native process modes, migration PTY, Unix socket server, terminal lifecycle PTY, deterministic TUI harness, fixed-baseline render/tool-result/event differentials); live stages PASS (credential-gated FiveAM, DeepSeek live TUI) |
| `./scripts/verify-release.sh` | exit 0 — full verifier first (same 20 deterministic + 2 live stages PASS), then the complete render inventory: `tier=full captured=76/76 scenarios=38 dimensions=2; aligned=10 intentional-terminal-protocol=118 requires-disposition=202 adjudicated=320; visible-string coverage 672/672 printable branches, structured_exemptions=0` |
| Goal 17 commits | `0112d2abc` package help contract; `a10b2f078` visible-string construction coverage; `afef19b0b` CLI help captures; `ae697faf2` fatal-crash disposition refresh; `709fdddc2` Kimi live gates; `df59d71f6` goal 8 advisor items; acceptance doc commit recorded below |
| root `cadr` mtime vs latest `src/` commit/mtime | binary 2026-08-08 04:36:20 > latest `src/` commit `0112d2abc` 2026-08-08 04:27:07 (fresh; verify.sh stage PASS) |
| `./cadr --version` | `cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)` |
