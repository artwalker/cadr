# Goal 14 acceptance ledger

## Part A0 — Goal 13 presentation carry-over

### Result

The three approved authentication-presentation corrections are complete.  The
implementation fixes ownership rather than painting individual call sites:
authentication overlays obtain their title and border semantics from shared
overlay primitives, while the generic single-line Input component owns the
software cursor.  Provider status text is a projection of the credential
producer's source identity; no display-only `configured` to `stored` rewrite
exists.

| Item | Fixed-baseline evidence | Cadr implementation | Regression |
|---|---|---|---|
| Cyan bold title and blue border | `packages/coding-agent/src/modes/interactive/components/oauth-selector.ts:67-96` constructs both borders through `DynamicBorder` and the title through `accent` plus bold | `src/cadr-cli/interactive-services.lisp:1421-1448,7351-7466,7757-7832` centralizes the three auth overlay families on `auth-overlay-border-line` and `selector-overlay-title-line`; ordinary selectors retain `border-muted` | `GOAL14-A0-AUTH-OVERLAYS-OWN-BASELINE-TITLE-AND-BORDER-SEMANTICS` |
| Visible software cursor | `packages/tui/src/components/input.ts:378-445` owns inverse-video cursor placement, grapheme selection, horizontal scrolling, and right padding | `src/cadr-tui/input-component.lisp:342-423`; auth search/API-key renderers delegate through `selector-input-line` instead of rebuilding `> value` | `GOAL14-A0-PROVIDER-SEARCH-AND-LOGIN-INPUTS-RENDER-A-VISIBLE-CURSOR`; `SINGLE-LINE-INPUT-RENDERS-BASELINE-SOFTWARE-CURSOR-AT-END-AND-OVER-TEXT`; `SINGLE-LINE-INPUT-CURSOR-PRESERVES-GRAPHEMES-AND-NARROW-WIDTHS` |
| Credential source identity | `packages/coding-agent/src/core/model-runtime.ts:428-437` fixes precedence as runtime, stored, configured request, then native auth; `provider-composer.ts:534-548` defines command/env/literal sources; `oauth-selector.ts:164-181` only formats the supplied source | `src/cadr-cli/model-services.lisp:924-1063`; `src/cadr-cli/main.lisp:3145-3150`; `src/cadr-cli/interactive-services.lisp:7619-7654` | `GOAL14-A0-PROVIDER-STATUS-SOURCE-CONTRACT-MATCHES-BASELINE` |

### Ownership conclusion

The old Cadr path made presentation decisions at each renderer: borders were
generic muted lines, titles were plain fitted strings, and authentication
inputs concatenated `"> "` with a value.  That is the repeated-decision defect
Goal 14 is intended to remove.  The corrected ownership is:

- authentication overlay composition owns `border` and accent/bold title;
- the reusable Input component owns cursor visibility, grapheme placement,
  scrolling, and padding;
- authentication producers own the status source; the selector only formats
  that source.

The generic selector border remains `border-muted`.  Changing it globally
would alter non-authentication overlays outside A0 and violate the byte-stable
boundary.

### Authentication source contract

| Producer state | Fixed baseline source | Previous Cadr source | Corrected Cadr source | Selector text |
|---|---|---|---|---|
| request-local credential override | `runtime` | not projected | `runtime` | `✓ runtime` |
| credential in persistent auth store | `stored` | `stored credential` on the live login path | `stored` | `✓ stored` |
| native OAuth auth check | `OAuth` | `OAuth` | `OAuth` | `✓ configured` |
| legacy/logout projection | `stored credential` | `stored credential` | unchanged | `✓ configured` |
| built-in environment credential | environment label/name | provider environment name | provider environment name | `✓ env: NAME` |
| models.json environment template | comma-separated variable names | not projected | comma-separated variable names | `✓ env: NAME[, NAME]` |
| models.json command | `models_json_command` | not projected | `models_json_command` | `✓ models_json_command` |
| models.json literal key | `models_json_key` | not projected | `models_json_key` | `✓ models_json_key` |
| no usable credential | absent | absent | absent | `• unconfigured` |

`OAuth`, absent source, and the deliberately retained legacy phrase `stored
credential` still render as `configured`, exactly as the baseline selector
defines.  Environment detection also accepts the baseline's comma-separated
uppercase-name form.

### Observable changes and unchanged boundary

Only the approved A0 surface changed:

- the three authentication overlay families now use blue borders and
  cyan/bold titles;
- provider search and API-key input show the inverse-video cursor;
- a persistent credential on the live model-registry path displays `stored`
  because its source is now correctly `stored`.

The login-provider and logout-provider full-screen SHA fixtures changed for
those approved pixels.  Every other full-screen/overlay SHA, payload fixture,
wire fixture, session behavior, extension export, and non-authentication
selector remained byte-identical.

### Freeze audit

The historical whole-tree `src/cadr-ai` object freeze ended when Goal 13 made
separately approved provider and OAuth changes.  The still-active freezes are
the public extension export surface, the 34-event extension contract, and
published public behavior.  A0 touches none of them and makes no `src/cadr-ai`
change.  Any later Goal 14 batch that changes those surfaces remains blocked
pending a separate proposal.

### Mechanical verification

The complete deterministic suite after A0:

```text
cadr test summary: systems=8 checks=12511 pass=12511 skip=0 fail=0
```

Part A starts only after this A0 implementation and ledger are committed.

## Part A — code-organization audit

### Result

The complete audit is [`docs/code-organization.md`](../code-organization.md).
The draft denominator of 135 files was stale: the clean tree at A0 commit
`47f71898e` contains 143 production files because Goal 13 added five approved
offline-export assets plus `cadr-ai/crash.lisp`, `cadr-cli/crash.lisp`, and
`cadr-tui/threads.lisp`.  Omitting those eight files would have hidden the
newest crash and cleanup boundaries from the audit.

The ledger accounts for every current source file exactly once:

| System | pass | pass · large | should split | should merge | Total |
|---|---:|---:|---:|---:|---:|
| `cadr-agent` | 9 | 10 | 4 | 0 | 23 |
| `cadr-ai` | 8 | 11 | 9 | 0 | 28 |
| `cadr-cli` | 20 | 10 | 13 | 0 | 43 |
| `cadr-evals` | 3 | 5 | 0 | 0 | 8 |
| `cadr-protocol` | 3 | 2 | 0 | 0 | 5 |
| `cadr-server` | 7 | 4 | 0 | 0 | 11 |
| `cadr-storage` | 2 | 0 | 0 | 0 | 2 |
| `cadr-tui` | 10 | 10 | 3 | 0 | 23 |
| **Total** | **62** | **52** | **29** | **0** | **143** |

The 29 split candidates contain 54,456 of 104,348 production lines.  Their
cohesion map names 159 replacement responsibilities and produces a planning
denominator of 273 files; the expected distribution is approximately 156 below
300 lines, 86 at 300--699, 23 at 700--999, and 8 at or above 1,000.  These are
consequences of named boundaries, not line-count targets.

### Required anomaly conclusions

- `cadr-server` is intentionally a shallow process supervisor, not a duplicate
  agent host.  It launches a child `cadr --mode rpc`; its extra code is Radius,
  IPC, child isolation, and recovery.  Adding `cadr-agent`/`cadr-cli` would
  collapse a useful process boundary without removing duplicated behavior.
- The provider comparison in the draft was incomplete.  At baseline
  `74caa2649`, pi has 82 provider declaration files / 2,111 lines plus 31 API
  protocol files / 10,566 lines.  Cadr already stores 38 brands as data rows;
  its actual defects are six protocols combined in `independent.lisp` and
  provider/auth identity repeated across declarations, OAuth metadata, callback
  cases, environment sources, and runtime projection.
- The historical whole-tree `src/cadr-ai` object freeze ended through approved
  Goal 13 work.  Public exports, wire/payload/session behavior, the extension
  export SHA `61eb1b623f784b3a8f0f6fe6791c65ebe991ff314ed1d969b82f3edd57646f18`,
  and the 34-event SHA
  `12f79b21e0e25495cb023baaf21b26f6cf9a891881b26602f6553f80af54887a`
  remain frozen.

### Repeated-decision audit

Nine current decisions meet the Goal 14 convergence threshold: bounded thread
cleanup, cancellation propagation, infrastructure-output ownership, selector
frame semantics, provider identity/auth metadata, secret-safe printing, atomic
persistence/file modes, JavaScript string/byte metrics, and ISO time/ID
formatting.  The ledger records every location, failure mode, prior incident,
and proposed single owner.  Path display and provider payload construction are
explicit non-candidates because their baseline semantics genuinely differ by
caller/protocol.

### Mechanical audit proof

The audit used column-zero `def*`/`define-*` forms as the top-level-definition
metric.  Direct comparison against the tree produced no missing/extra path and
no line/definition-count mismatch:

```text
ledger rows: 143
tree files: 143
path set difference: empty
line/count mismatches: empty
ledger totals: lines=104348 definitions=4246
verdict totals: pass=62 pass · large=52 should split=29 should merge=0
```

Part A changed no production file.  Relative to A0 commit `47f71898e`, the
owned Part A/B delta consists only of this report,
`docs/code-organization.md`, and the Part B proposal; the pre-existing modified
Goal 8 report and untracked exported HTML remain untouched and uncommitted.

## Part B — ranked implementation proposal

### Result

The complete proposal is
[`docs/proposals/goal-v14-code-organization.md`](../proposals/goal-v14-code-organization.md).
It ranks eleven independently revertible Part C batches from low-risk
interactive leaf extraction through the frozen extension/provider surfaces.
Each batch records its source/target files, export and freeze exposure, ASDF
load-order risk, and required byte-stability gates.

### User ruling

The user approved all eleven batches, the new internal `cadr-core` leaf, and
the validated B11 provider declaration schema.  The ruling moved B3 to the
front: repeated decisions must converge before, or in the same batch as, the
files that currently contain their copies.  The approved sequence is B3, B1,
B2, B4, B5, B6, B7, B8, B9, B10, B11.

B2 has an additional hard gate: one composable `selector-frame` must own the
border, title, input, viewport/count, help row, and wrap navigation before the
eight selector families are extracted.  B11 must re-audit the historical
`src/cadr-ai` freeze and build its 38-provider matrix from baseline semantics,
never from the current Cadr table.  The proposal now records the required
convergence-before-split order for every batch.

## Part C B3 — shared failure-safety core

### Result

B3 is complete.  The new internal `cadr-core` leaf contains no product policy,
provider behavior, TUI behavior, third-party system, or new public mechanism.
All existing systems depend downward on it; `cadr-tui` still does not depend on
`cadr-ai`.

| Previous owners | New owner | One responsibility |
|---|---|---|
| `cadr-ai/utilities.lisp`, `cadr-tui/threads.lisp`, `cadr-cli/utilities.lisp`, plus raw joins in agent/tool/server cleanup | `src/cadr-core/threads.lisp` | Bound cleanup waits and require a non-empty reason for deliberately unbounded active synchronization. |
| AI HTTP/runtime, agent extension/runtime, TUI autocomplete/composition local flags | `src/cadr-core/cancellation.lisp` | Own component-local abort state, predicates, notification, and waiting without adding lifecycle policy. |
| AI auth, CLI settings/import, agent migration, server storage, eval artifacts/reporting | `src/cadr-core/atomic-file.lisp` | Own sibling-temp atomic replacement, explicit file modes/durability, copy, and explicitly non-atomic append. |
| AI provider/request/auth/model values and CLI config/credential values | `src/cadr-core/redacted-print.lisp` | Declare and enumerate secret-safe object printers and provide exact sentinel redaction. |
| AI event timestamps, agent session/storage timestamps, CLI export names, server status timestamps | `src/cadr-core/time.lisp` | Own Unix milliseconds and fixed UTC ISO-8601 conversions. |

`src/cadr-core/package.lisp` is the internal contract and `cadr-core.asd` is the
serial load boundary.  The former package-local helper names remain only where
existing internal callers already use them; every such wrapper delegates to
`cadr-core` and owns no branch, timeout, file-mode, redaction, or timestamp
policy.

### Convergence and safety gates

Tests were written before the implementation.  `cadr-core/tests` covers the
absent/current/completed/unresponsive thread cases, mandatory active-join
reason, local and external cancellation, atomic rollback, `0600` preservation,
append semantics, secret-bearing object printing, and fixed UTC vectors.
Repository source gates additionally reject:

- raw production `sb-thread:join-thread` outside `cadr-core/threads.lisp`;
- handwritten `rename-file-overwriting-target` outside
  `cadr-core/atomic-file.lisp`;
- direct production `defmethod print-object` outside the redacted declaration
  owner.

The deterministic entrypoint now accounts for nine suites instead of eight,
and every build/live/benchmark helper explicitly loads the new leaf before its
consumers.  A clean temporary HOME and ASDF cache proved that no stale FASL was
required.

### Frozen behavior

No package other than the new internal `cadr-core` package gained an export.
The public extension export SHA remains
`61eb1b623f784b3a8f0f6fe6791c65ebe991ff314ed1d969b82f3edd57646f18` and
the 34-event SHA remains
`12f79b21e0e25495cb023baaf21b26f6cf9a891881b26602f6553f80af54887a`.
All screen/overlay snapshots, payload and wire fixtures, session files, tool
results, exit codes, and user-visible bytes remain unchanged.

### Mechanical verification

```text
cadr-core/tests: 36 checks / 36 pass / 0 skip / 0 fail
cadr test summary: systems=9 checks=12552 pass=12552 skip=0 fail=0
```

The first full verifier run exposed that the standalone Goal 9 A2 PTY driver,
like the already-corrected Goal 5 harness, loaded a consumer ASDF file without
first registering `cadr-core.asd`.  The shared regression now enumerates both
harnesses and requires the core registration to precede `cadr-tui`; the real
PTY gate then passed all six lifecycle and interaction scenarios.  The final
`./scripts/verify.sh` run passed all 13 deterministic stages and both live
stages.  Credential-gated live results were 7 pass, 1 Anthropic skip because
`ANTHROPIC_API_KEY` is unset, and 0 fail; the DeepSeek live TUI passed.

Root binary freshness at verification time:

```text
binary build time: 2026-08-03 17:25:55.930730933 +0800
latest source mtime: 2026-08-03 17:20:33.215966287 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

The implementation adds six production Lisp files / 359 lines and removes the
duplicated policy bodies from existing systems.  B1 begins from this committed
shared owner rather than reproducing those decisions during extraction.

## Part C B1 — interactive leaf ownership

### Result

The former 9,131-line `interactive-services.lisp` now retains only selector
state machines and their domain behavior.  Eight cohesive leaves moved without
renaming package-private symbols or changing a function body:

| New owner | Responsibility |
|---|---|
| `interactive/transcript.lisp` | user/assistant transcript projection |
| `interactive/status.lisp` | status log, startup input, Anthropic warning |
| `interactive/footer.lisp` | footer projection and Git branch refresh |
| `interactive/theme.lisp` | terminal/theme detection and discovery |
| `interactive/images.lisp` | image inspection and model-limit processing |
| `interactive/clipboard.lisp` | platform clipboard text/image I/O |
| `interactive/syntax.lisp` | deterministic syntax highlighting |
| `interactive/tool-render-session.lisp` | incremental tool-render state |

`cadr-cli.asd` loads value/data owners before consumers, specifically images
before clipboard and all eight leaves before the remaining selector source.
`GOAL14-B1-INTERACTIVE-LEAF-SERVICES-HAVE-EXACT-OWNERS` rejects duplicated or
missing sentinel definitions and proves selectors were not prematurely split;
`GOAL14-B1-ASDF-LOADS-LEAF-OWNERS-BEFORE-SELECTOR-CONSUMERS` locks the dependency
order.

### Convergence-before-split result

B1 names the existing output owners rather than creating a generic presentation
abstraction: transcript, status, footer, and tool-render bytes still pass through
their one pre-existing function family.  The selector frame repetition remains
co-located on purpose.  B2 must first give border, title, input, viewport/count,
help, and wrap navigation to one composable `selector-frame`; only then may the
eight selector families leave `interactive-services.lisp`.

### Mechanical verification

```text
cadr test summary: systems=9 checks=12600 pass=12600 skip=0 fail=0
```

All existing full-screen, overlay, payload, wire, session, tool-result, and exit
contract checks stayed byte-identical.  The Lisp source ledger now accounts for
152 production Lisp files and the organization ledger accounts for all 157
production files.  No public package export or frozen extension/event surface
changed.  `./scripts/verify.sh` passed all 13 deterministic stages and both live
stages; live results were 7 pass, 1 Anthropic skip because
`ANTHROPIC_API_KEY` is unset, and 0 fail, followed by a passing DeepSeek TUI.

Root binary freshness at verification time:

```text
binary build time: 2026-08-03 18:08:44.700365611 +0800
latest source mtime: 2026-08-03 18:04:15.586755658 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

## Part C B2 — composable selector frame and domain ownership

### Result

B2 converged the repeated selector decisions before extracting the domains.
`src/cadr-cli/interactive/selectors/common.lisp` now owns the composable
`selector-frame`: border and title sections, optional input, viewport and
count placement, help rows, visible slicing, and bidirectional wrap
navigation.  Domain selectors provide their entries, state, and callbacks;
they no longer own navigation or viewport policy.

The former selector remainder in `interactive-services.lisp` was then split
into eight load-ordered owners:

| New owner | Responsibility |
|---|---|
| `interactive/selectors/common.lisp` | selector-frame composition, shared filtering/input helpers, viewport slicing, and wrap navigation |
| `interactive/selectors/sessions.lisp` | resume, session, switch, branch, and compact selection |
| `interactive/selectors/tree.lisp` | tree entries, filters, paging, branch navigation, and copy actions |
| `interactive/selectors/settings.lisp` | settings rows, values, search, and mutation callbacks |
| `interactive/selectors/auth.lisp` | login method/provider selectors and authentication input bridges |
| `interactive/selectors/models.lisp` | model catalog search, scope, refresh, and selection |
| `interactive/selectors/trust.lisp` | resource trust and extension/package authorization choices |
| `interactive/selectors/fork.lisp` | fork-point selection and empty-history behavior |

`cadr-cli.asd` loads `common` first, followed by the seven domain owners.
`GOAL14-B2-SELECTOR-FRAME-OWNS-SHARED-SELECTOR-DECISIONS` rejects a missing
frame owner, duplicated domain navigation policy, or a domain renderer that
bypasses the frame.  `GOAL14-B2-SELECTOR-FRAME-WRAPS-AND-CENTERS-INDEPENDENT`
locks empty/single/multi-entry boundaries, both wrap directions, centered
viewport slicing, and count placement.  Before implementation these tests
failed 8/8 because the owner and extracted domains did not exist; after the
split the focused gates pass 26/26 and 9/9.

### Observable boundary and verification

The refactor preserves every existing selector byte.  All base-screen and
overlay snapshots, payload and wire fixtures, session files, tool results,
exit codes, public exports, and the frozen extension/event surfaces remained
unchanged.  The source ledger now accounts for 159 production Lisp files and
the organization ledger accounts for all 164 production files.

```text
cadr test summary: systems=9 checks=12635 pass=12635 skip=0 fail=0
```

`./scripts/verify.sh` passed all 13 deterministic stages and both live stages.
Credential-gated live results were 7 pass, 1 Anthropic skip because
`ANTHROPIC_API_KEY` is unset, and 0 fail; the DeepSeek live TUI passed.

Root binary freshness at verification time:

```text
binary build time: 2026-08-03 18:43:50.772166957 +0800
latest source mtime: 2026-08-03 18:33:34.275339974 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

## Part C B4 — CLI domain services

### Result

B4 converged the duplicated policy decisions before replacing eight mixed CLI
files with 37 named owners.  The approved proposal prose said 36 files, but its
explicit map sums to 37 (`6 + 7 + 3 + 5 + 4 + 4 + 5 + 3`); the implementation
follows that authoritative map rather than hiding the arithmetic error.

| Previous owner | New owners | Responsibility boundary |
|---|---|---|
| `core-support.lisp`, `utilities.lisp` | `support/{model-help,event-bus,timings,file-watcher,paths,shell-process,threads,atomic-write,changelog-share,html,resume-version-git,headers,external-editor}.lisp` | process-neutral CLI support, with each file naming one service |
| `settings.lisp` | `settings/{config-values,manager,trust}.lisp` | settings values/persistence and project trust |
| `model-services.lisp` | `models/{auth-storage,store,registry,matching,credential-print}.lisp` | credential storage, model registry/projection, matching, and secret-safe rendering |
| `package-manager.lisp` | `packages/{source,settings,manifest,commands}.lisp` | package source parsing, persisted settings, manifest state, and commands |
| `extensions.lisp` | `extensions/{discovery,loader,commands,installer}.lisp` | extension discovery, diagnostic-safe loading, commands, and installation |
| `sdk-services.lisp`, `sdk.lisp` | `sdk/{cache-version,system-prompt,settings-service,resource-service,model-service,session-manager,agent-session,session-runtime}.lisp` | SDK services and session-local runtime ownership |

### Convergence-before-split proof

Tests were added first and failed 48 checks before the new owners existed.  B4
then established the policy owners before extraction:

- `extensions/loader.lisp` co-locates `extension-manager-notify`,
  `call-with-extension-output-boundary`, and
  `call-with-infrastructure-output-isolated`; extracted extension commands do
  not write around that boundary;
- settings and auth persistence delegate to the B3 atomic-file owner, while
  credential/config printers remain under the B3 redaction discipline;
- the CLI JavaScript-length compatibility function delegates to the single
  `cadr-agent::utf16-code-unit-length` implementation instead of retaining a
  second metric policy.

`GOAL14-B4-DOMAIN-SERVICES-HAVE-EXACT-OWNERS` and
`GOAL14-B4-CONVERGES-SINKS-AND-JAVASCRIPT-LENGTH-BEFORE-SPLIT` lock those
boundaries.  Top-level definitions are 409 before and after the split, and
`src/cadr-cli/package.lisp` is unchanged.

### Verification and live-gate ruling

```text
cadr test summary: systems=9 checks=12724 pass=12724 skip=0 fail=0
```

All 13 deterministic `verify.sh` stages passed, including isolated `cadr` and
`cadr-server` builds, Goal 11 performance/stability, process/PTY/socket
harnesses, and the real source-parity ledger.  The captured live run had six
passes, one Anthropic credential skip, and one failure:
`LIVE-DEEPSEEK-REPOSITORY-FAIL-FIX-PASS-LOOP` stopped with provider reason
`LENGTH`; the independent DeepSeek TUI stage passed.

The initial explanation that B4 did not edit `cadr-ai`, `cadr-agent`, or
`cadr-evals` was insufficient: `cadr-evals/harness.lisp` calls
`cadr-cli::resolve-provider-config`, so B4 lies on the transitive execution
path.  The accepted causal evidence is narrower: the B4 changes on model
resolution and max-token handling are definition-preserving moves, with no
branch or value change, and the user independently reran the complete
`./scripts/test-live.sh` on the same code and binary with seven passes, one
Anthropic credential skip, and zero failures.  The user therefore classified
the captured `LENGTH` stop as model-output variation and explicitly accepted
B4.

Root binary freshness at the captured verification run:

```text
binary build time: 2026-08-03 19:20:31.586946115 +0800
latest source commit: 7939b2b0ddd22ca4dbd12228519a1b4dc2038652 2026-08-03T19:17:51+08:00
latest source mtime: 2026-08-03 19:15:45.304226081 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

### Deferred live-smoke audit

`assert-live-smoke-eval` currently requires the model output to equal `Paris`
exactly.  This is recorded for a separate baseline audit: the conclusion must
be either that pi enforces the same strict response (a baseline-inherent live
variance) or that pi uses a different matching/retry contract that Cadr must
adopt.  B4 does not weaken or otherwise change that assertion without the
baseline evidence.

## Part C B5 — CLI bootstrap and RPC ownership

### Result

B5 replaced the two remaining mixed command entrypoints with eleven cohesive
owners while preserving all 100 top-level definitions and the package-private
symbol names used by existing callers.

| Previous owner | New owners | Responsibility boundary |
|---|---|---|
| `main.lisp` | `bootstrap/tools.lisp` | built-in tool construction and prompt metadata |
| `main.lisp` | `bootstrap/sessions.lisp` | session resolution, lifecycle, tree, and export |
| `main.lisp` | `bootstrap/settings.lisp` | directories, trust, settings, resources, runtime, and system prompt |
| `main.lisp` | `bootstrap/auth.lisp` | native authentication options and command dispatch |
| `main.lisp` | `bootstrap/commands.lisp` | event rendering, file input, controller construction, and mode-output injection |
| `main.lisp` | `bootstrap/main.lisp` | model listing and process entrypoint |
| `modes/rpc/mode.lisp` | `modes/rpc/models.lisp` | RPC model enumeration and selection commands |
| `modes/rpc/mode.lisp` | `modes/rpc/prompt-bash.lisp` | RPC prompt, steering/follow-up, and bash execution commands |
| `modes/rpc/mode.lisp` | `modes/rpc/sessions.lisp` | RPC session-state and compaction commands |
| `modes/rpc/mode.lisp` | `modes/rpc/commands.lisp` | RPC command parsing, validation, and dispatch |
| `modes/rpc/mode.lisp` | `modes/rpc/mode.lisp` | RPC loop and lifecycle only |

`cadr-cli.asd` loads value owners before their consumers and leaves the RPC
loop last.  A clean isolated build proved the order without relying on stale
FASLs.  `src/cadr-cli/package.lisp` remained byte-identical with SHA-256
`8bab04da761b5035172ece9c7d15dd93be00bfe5269f2ca80510d24a1c01b1db`.

### Convergence-before-split proof

B5 completed the approved convergence at the new boundaries:

- session export timestamps call `cadr-core:milliseconds-to-utc-iso8601`
  directly;
- RPC IDs call `cadr-core:unix-milliseconds` directly;
- `bootstrap/commands.lisp` owns the single frontend-output injection;
- `modes/rpc/jsonl.lisp` remains the sole RPC wire sink, and the extracted RPC
  domains cannot call `write-json-line` directly.

`GOAL14-B5-COMMAND-AND-RPC-DOMAINS-HAVE-EXACT-OWNERS`,
`GOAL14-B5-CONVERGES-MODE-OUTPUT-AND-TIME-BEFORE-SPLIT`, and
`GOAL14-B5-ASDF-LOADS-COMMAND-DOMAINS-BEFORE-ENTRYPOINTS` lock those decisions.
The red gate was 6,184 checks / 6,165 pass / 19 expected failures before the
owners existed.  After implementation, the complete deterministic suite was:

```text
cadr test summary: systems=9 checks=12781 pass=12781 skip=0 fail=0
```

### Full verification

`./scripts/verify.sh` passed all 13 deterministic stages and both live stages:

```text
root cadr binary freshness                       PASS
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
credential-gated FiveAM                          PASS
DeepSeek live TUI                                PASS
```

The credential-gated report ran seven items successfully, skipped Anthropic
because `ANTHROPIC_API_KEY` is unset, and failed none: 32 checks / 31 pass / 1
skip / 0 fail.  `LIVE-DEEPSEEK-EVAL-SMOKE` passed its four checks in this run;
the separately recorded baseline audit of its exact `Paris` assertion remains
unchanged.

Root binary freshness at verification time:

```text
binary build time: 2026-08-03 20:12:22.504791370 +0800
latest source commit: d0935fadbfa8d34de0fe6d30e5b54733f51c4ea6 2026-08-03T20:09:52+08:00
latest source mtime: 2026-08-03 20:09:19.298069498 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

The production Lisp inventory is now 197 files / 100,354 lines; the complete
production inventory including five embedded assets is 202 files / 104,629
lines.  All screen and overlay snapshots, payload and wire fixtures, extension
export/event SHA values, session files, tool results, exit codes, and other
observable bytes remain unchanged.  Implementation commit:
`d0935fadbfa8d34de0fe6d30e5b54733f51c4ea6`.

## Part C B6 — interactive controller ownership

### Result

B6 removed the remaining interactive monoliths and assigned their 224
top-level definitions to sixteen dependency-ordered owners:

- `interactive/{state,entries,status,extension-ui,transcript,tool-rendering,
  pending-messages,frame,autocomplete,themes,controller}.lisp`;
- `interactive/components/{loaders,countdown,armin,daxnuts,announcement}.lisp`.

The existing B1 status/transcript owners absorbed the corresponding controller
responsibilities. B2's `selector-frame`, B4's output sinks, and B3's bounded
cleanup/cancellation primitives remain the single policy owners; the split did
not recreate those decisions locally. The old and new sorted top-level
definition sets contain 224 byte-identical first lines, with no missing or
added definition. `src/cadr-cli/package.lisp` remained byte-identical with
SHA-256 `8bab04da761b5035172ece9c7d15dd93be00bfe5269f2ca80510d24a1c01b1db`.

The red-first organization gate failed until every named owner existed and the
ASDF graph loaded state before renderers and the controller. The completed
gate and full deterministic suite passed:

```text
cadr test summary: systems=9 checks=12868 pass=12868 skip=0 fail=0
```

### Full verification

`./scripts/verify.sh` passed all thirteen deterministic stages and both live
stages. The credential-gated report ran seven items successfully, skipped
Anthropic because `ANTHROPIC_API_KEY` is unset, and failed none:

```text
Items: 8, run: 7, pass: 7, skip: 1, fail: 0
Checks: 32, pass: 31, skip: 1, fail: 0
```

`LIVE-DEEPSEEK-EVAL-SMOKE` passed all four checks; its separately recorded
baseline audit remains deferred and unchanged. The deterministic stage table
was:

```text
root cadr binary freshness                       PASS
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
```

Root binary freshness at verification time:

```text
binary build time: 2026-08-03 20:46:30.765671794 +0800
latest source commit: 357130858839409ed93f442ce85953e180786016 2026-08-03T20:44:13+08:00
latest source mtime: 2026-08-03 20:44:10.274474102 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

The production inventory is now 209 Lisp files / 100,378 lines and five
embedded assets / 4,275 lines, for 214 files / 104,653 lines total. All
screen/overlay snapshots and their independent semantic assertions, payload
and wire fixtures, extension exports, session bytes, tool results, exit codes,
and other observable output remained unchanged. Implementation commit:
`357130858839409ed93f442ce85953e180786016`.

## Part C B7 — reusable TUI internals

### Result

B7 replaced the three remaining `cadr-tui` monoliths with sixteen
dependency-ordered owners while preserving all 288 top-level definitions and
the package-private names used by existing consumers:

- `components/{markdown,image,tool-block,status,select-list}.lisp`;
- `composition/{protocol,text-box,rich-content,settings-list,loaders,root}.lisp`;
- `renderer/{terminal-protocol,virtual-terminal,lifecycle-input,main-screen,
  alt-screen}.lisp`.

The ASDF graph loads composition and terminal protocols before their
implementations. B3 remains the single owner of failure-safety decisions:
renderer cleanup delegates to `stop-thread-for-cleanup`, composition
cancellation delegates to `cadr-core:make-cancellation-state`, and no new raw
`join-thread` call was introduced. The sorted old and new definition sets are
identical at 288 entries. `src/cadr-tui/package.lisp` remained byte-identical
with SHA-256
`5eacdc9c3ecad7e578623a141a1b4b948a31ae014497a0e319a66f14693d8713`.

Tests were added before the split. The completed gates are
`GOAL14-B7-REUSABLE-TUI-INTERNALS-HAVE-EXACT-OWNERS`,
`GOAL14-B7-REUSES-CORE-CANCELLATION-AND-CLEANUP-BEFORE-SPLIT`, and
`GOAL14-B7-ASDF-LOADS-PROTOCOLS-BEFORE-IMPLEMENTATIONS`. The complete
deterministic suite passed:

```text
cadr test summary: systems=9 checks=12978 pass=12978 skip=0 fail=0
```

### Full verification

`./scripts/verify.sh` passed all thirteen deterministic stages and both live
stages:

```text
root cadr binary freshness                       PASS
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
credential-gated FiveAM                          PASS
DeepSeek live TUI                                PASS
```

The real source-parity ledger contains 595 accepted entries with SHA-256
`242d90e03ae708b9ea30d71747052af80f6d19e62eec3990a5863c62a614965d`.
Credential-gated live verification ran seven items successfully, skipped
Anthropic because `ANTHROPIC_API_KEY` is unset, and failed none:

```text
Items: 8, run: 7, pass: 7, skip: 1, fail: 0
Checks: 32, pass: 31, skip: 1, fail: 0
```

`LIVE-DEEPSEEK-EVAL-SMOKE` passed all four checks; its separately recorded
baseline audit remains deferred and unchanged. The Goal 11 gate also passed,
including sustained-interaction p99.9 of 4 ms, maximum pause of 16 ms, maximum
measured GC pause of 15.09 ms, and converged sustained memory.

Root binary freshness at verification time:

```text
binary build time: 2026-08-03 21:25:00.577094410 +0800
latest source commit: 7b94e5c440485624d9cd8346eda3dd31d026c392 2026-08-03T21:22:35+08:00
latest source mtime: 2026-08-03 21:22:29.105932154 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

The production inventory is now 222 Lisp files / 100,383 lines and five
embedded assets / 4,275 lines, for 227 files / 104,658 lines total. All
screen/overlay snapshots and their independent semantic assertions, payload
and wire fixtures, extension exports, session bytes, tool results, exit codes,
and other observable output remained unchanged. Implementation commit:
`7b94e5c440485624d9cd8346eda3dd31d026c392`.

## Part C B8 — agent session, storage, and loop ownership

### Result

B8 replaced the three mixed agent files with thirteen dependency-ordered
owners while preserving all 251 top-level definitions:

- `session/{codec,journal,migration,discovery,export-html}.lisp`;
- `storage/{protocol,memory,harness,jsonl}.lisp`;
- `loop/{events,tool-execution,turns,agent-loop}.lisp`.

Session codecs load before journal, migration, discovery, and export;
storage protocols load before all three backends; loop events and tool
execution load before turns and the public agent-loop entrypoints. B3 remains
the sole owner of UTC/ID and atomic replacement policy. The old and new sorted
top-level definition sets are identical: 99 session, 96 storage, and 56 loop
definitions. `src/cadr-agent/package.lisp` remained byte-identical with
SHA-256
`41374c3caf9a306242b483d870383f3fdae641ee649ed461cf2b67164847c4a5`.

Tests were written before extraction. The ownership gate initially produced
34 expected failures because the thirteen owners did not exist and the three
legacy files still did. The completed gates are
`GOAL14-B8-AGENT-SESSION-STORAGE-AND-LOOP-HAVE-EXACT-OWNERS`,
`GOAL14-B8-REUSES-CORE-TIME-ID-AND-ATOMIC-MIGRATION-BEFORE-SPLIT`, and
`GOAL14-B8-ASDF-LOADS-PROTOCOLS-BEFORE-BACKENDS-AND-LOOP`.
`GOAL14-B8-STABILITY-PROVENANCE-FOLLOWS-SESSION-OWNER` additionally prevents
the Goal 11 harness from silently hashing a removed monolith. The complete
deterministic suite passed:

```text
cadr test summary: systems=9 checks=13069 pass=13069 skip=0 fail=0
```

### Full verification

`./scripts/verify.sh` passed all thirteen deterministic stages and both live
stages:

```text
root cadr binary freshness                       PASS
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
credential-gated FiveAM                          PASS
DeepSeek live TUI                                PASS
```

The real source-parity ledger contains 595 accepted entries with SHA-256
`242d90e03ae708b9ea30d71747052af80f6d19e62eec3990a5863c62a614965d`.
Credential-gated live verification ran seven items successfully, skipped
Anthropic because `ANTHROPIC_API_KEY` is unset, and failed none:

```text
Items: 8, run: 7, pass: 7, skip: 1, fail: 0
Checks: 32, pass: 31, skip: 1, fail: 0
```

`LIVE-DEEPSEEK-EVAL-SMOKE` passed all four checks. Its exact `Paris`
assertion remains unchanged pending the separately required baseline audit.
The actual failure path runs through `cadr-evals` into
`cadr-cli::resolve-provider-config`; B8 changed neither that path nor its
model/max-token decisions. The Goal 11 gate passed with sustained-interaction
p99.9 of 4 ms, maximum pause of 16 ms, maximum measured GC pause of 13.85 ms,
and converged sustained memory.

Root binary freshness at verification time:

```text
binary build time: 2026-08-03 21:58:54.619806404 +0800
latest source commit: 1632bcdfa4d4681a203eeac85a46cd59b924f097 2026-08-03T21:56:40+08:00
latest source mtime: 2026-08-03 21:46:10.299708323 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

The build explicitly took the approved compatibility path:
`SBCL lacks sb-core-compression; building an uncompressed image.` The
production inventory is now 232 Lisp files / 100,400 lines and five embedded
assets / 4,275 lines, for 237 files / 104,675 lines total. All screen/overlay
snapshots and their independent semantic assertions, payload and wire
fixtures, extension export/event hashes, session bytes, tool results, exit
codes, and other observable output remained unchanged. Implementation commit:
`1632bcdfa4d4681a203eeac85a46cd59b924f097`; verification-provenance fix:
`d750b01a0`.

## Part C B9 — extension host ownership

### Result

B9 replaced the mixed extension host with eight dependency-ordered owners
while preserving all 239 top-level definitions:

- `extensions/{context,api,registration,snapshot}.lisp`;
- `extensions/{rendering,providers,commands,lifecycle}.lisp`.

The ASDF graph loads context and API contracts before registration and
snapshots, then loads rendering, provider, command, and lifecycle adapters.
B3 remains the sole owner of cancellation and output-diagnostic policy. The
extension host still consumes the same cancellation primitive and injected
output sink; it does not recreate either policy locally.

Tests were written before extraction. The red-first ownership gate produced
ten expected failures while the eight owners were absent and the legacy
monolith remained. The completed gates are
`GOAL14-B9-EXTENSION-HOST-HAS-EXACT-OWNERS`,
`GOAL14-B9-PRESERVES-CORE-OWNERS-AND-FROZEN-EXTENSION-SURFACES`, and
`GOAL14-B9-ASDF-LOADS-EXTENSION-HOST-IN-DEPENDENCY-ORDER`. The public agent
package remained byte-identical with SHA-256
`41374c3caf9a306242b483d870383f3fdae641ee649ed461cf2b67164847c4a5`.
The frozen extension export SHA remains
`61eb1b623f784b3a8f0f6fe6791c65ebe991ff314ed1d969b82f3edd57646f18`,
and the event SHA remains
`12f79b21e0e25495cb023baaf21b26f6cf9a891881b26602f6553f80af54887a`.
The complete deterministic suite passed:

```text
cadr test summary: systems=9 checks=13150 pass=13150 skip=0 fail=0
```

### Full verification

`./scripts/verify.sh` passed all thirteen deterministic stages and both live
stages:

```text
root cadr binary freshness                       PASS
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
credential-gated FiveAM                          PASS
DeepSeek live TUI                                PASS
```

The real source-parity ledger contains 595 accepted entries with SHA-256
`242d90e03ae708b9ea30d71747052af80f6d19e62eec3990a5863c62a614965d`.
Credential-gated live verification ran seven items successfully, skipped
Anthropic because `ANTHROPIC_API_KEY` is unset, and failed none:

```text
Items: 8, run: 7, pass: 7, skip: 1, fail: 0
Checks: 32, pass: 31, skip: 1, fail: 0
```

`LIVE-DEEPSEEK-EVAL-SMOKE` passed all four checks. Its exact `Paris`
assertion remains unchanged pending the separately required baseline audit.
The actual live-eval path enters `cadr-evals` and calls
`cadr-cli::resolve-provider-config`; B9 changed no definition or caller on
that path, and the moved extension-host definitions do not participate in its
model or max-token resolution. This is call-path evidence, not an ASDF-system
boundary argument.

The Goal 11 gate passed with sustained-interaction p99.9 of 4 ms, maximum
pause of 16 ms, maximum measured sustained GC pause of 15.31 ms, and
converged sustained memory.

Root binary freshness at verification time:

```text
binary build time: 2026-08-03 22:37:22.636144306 +0800
latest source commit: 0107210c863b84ca20595a614c206893f6507621 2026-08-03T22:34:59+08:00
latest source mtime: 2026-08-03 22:33:08.086823017 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

The build explicitly took the approved compatibility path:
`SBCL lacks sb-core-compression; building an uncompressed image.` The
production inventory is now 239 Lisp files / 100,407 lines and five embedded
assets / 4,275 lines, for 244 files / 104,682 lines total. All screen/overlay
snapshots and their independent semantic assertions, payload and wire
fixtures, extension export/event hashes, session bytes, tool results, exit
codes, and other observable output remained unchanged. Implementation commit:
`0107210c863b84ca20595a614c206893f6507621`.

## Part C B10 — AI support, runtime, and transport ownership

### Result

B10 replaced four mixed AI files with seventeen dependency-ordered owners
while preserving all 229 top-level definitions:

- `capabilities/{streaming-json,event-stream,grammar-tools,session-resources,proxy-config,image-runtime}.lisp`;
- `transport/{http,aws-event-stream}.lisp`;
- `runtime/{models,faux-provider}.lisp`;
- `support/{threads,release,retry,token-estimation,overflow,grammar-coercion,uuid}.lisp`.

The ASDF graph loads value and framing helpers before transports, runtime
models before the faux provider, and low-level support before every consumer.
B3 remains the owner of cancellation, redacted printing, and time policy; the
new AI files consume those primitives and do not recreate them.

Tests were written before extraction. The red-first ownership gate failed on
all seventeen absent owners and the four surviving monoliths. The completed
gates are
`GOAL14-B10-AI-CAPABILITY-TRANSPORT-RUNTIME-AND-SUPPORT-HAVE-EXACT-OWNERS`,
`GOAL14-B10-PRESERVES-CORE-OWNERS-AND-FROZEN-AI-SURFACE`, and
`GOAL14-B10-ASDF-LOADS-AI-OWNERS-IN-DEPENDENCY-ORDER`. The public AI package
remained byte-identical with SHA-256
`e722e49fd70592edcd28da93acc97051d4a0b22bc016e4b7da314a65c4acfb4f`.
The complete deterministic suite passed:

```text
cadr test summary: systems=9 checks=13276 pass=13276 skip=0 fail=0
```

### Full verification

`./scripts/verify.sh` passed all thirteen deterministic stages and both live
stages:

```text
root cadr binary freshness                       PASS
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
credential-gated FiveAM                          PASS
DeepSeek live TUI                                PASS
```

The real source-parity ledger contains 595 accepted entries with SHA-256
`242d90e03ae708b9ea30d71747052af80f6d19e62eec3990a5863c62a614965d`.
Credential-gated live verification ran seven items successfully, skipped
Anthropic because `ANTHROPIC_API_KEY` is unset, and failed none:

```text
Items: 8, run: 7, pass: 7, skip: 1, fail: 0
Checks: 32, pass: 31, skip: 1, fail: 0
```

`LIVE-DEEPSEEK-EVAL-SMOKE` passed all four checks. Its exact `Paris`
assertion remains unchanged pending the separately required baseline audit.
The actual live-eval path enters `cadr-evals`, calls
`cadr-cli::resolve-provider-config`, then constructs the Cadr AI provider.
B10 moved the eventual runtime and transport definitions without changing
their bodies, call sites, model resolution, or max-token decisions. This is
call-path evidence, not an ASDF-system boundary argument.

The Goal 11 gate passed with sustained-interaction p99.9 of 4 ms, maximum
pause of 16 ms, maximum measured sustained GC pause of 12.86 ms, and
converged sustained memory.

Root binary freshness at verification time:

```text
binary build time: 2026-08-03 23:14:59.067295301 +0800
latest source commit: 4339d98b1 2026-08-03T23:12:36+08:00
latest source mtime: 2026-08-03 23:11:57.143498021 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

The build explicitly took the approved compatibility path:
`SBCL lacks sb-core-compression; building an uncompressed image.` The
production inventory is now 252 Lisp files / 100,420 lines and five embedded
assets / 4,275 lines, for 257 files / 104,695 lines total. All screen/overlay
snapshots and their independent semantic assertions, payload and wire
fixtures, public package exports, session bytes, tool results, exit codes, and
other observable output remained unchanged. Implementation commit:
`4339d98b1`.

## Part C B11 — provider and authentication ownership

### Freeze audit and result

The historical whole-tree `src/cadr-ai` object freeze was already ended by the
separately approved Goal 13 provider and OAuth changes. B11 therefore proceeded
inside its approved file map while retaining the still-active public surface
freezes. `src/cadr-ai/package.lisp` remained byte-identical with SHA-256
`e722e49fd70592edcd28a93acc97051d4a0b22bc016e4b7da314a65c4acfb4f`.
The extension export and 34-event hashes remain, respectively,
`61eb1b623f784b3a8f0f6fe6791c65ebe991ff314ed1d969b82f3edd57646f18`
and `12f79b21e0e25495cb023baaf21b26f6cf9a891881b26602f6553f80af54887a`.

B11 retired the five mixed owners `oauth-flows.lisp`, `oauth.lisp`,
`provider-auth.lisp`, `providers/independent.lisp`, and `registry.lisp`. Their
responsibilities now have 25 dependency-ordered owners:

- seven provider OAuth owners under `oauth/providers/`;
- four shared OAuth protocol/page owners under `oauth/`;
- five credential/auth owners under `auth/`;
- six independent provider protocol owners under `providers/`;
- `providers/definitions.lisp`, `providers/registry.lisp`, and
  `providers/runtime-projection.lisp` for declarations, protocol construction,
  and runtime consumption.

`providers/definitions.lisp` is the single validated declaration schema for
all 38 providers. It owns static identity, protocol and protocol alternatives,
base URL, authentication types, default model, required environment, dynamic
catalog/image/tool/reasoning capabilities, API-key presentation, OAuth
presentation, and the API-key/OAuth/refresh/model-filter strategy identities.
The runtime environment-name set is derived from those declarations instead
of retaining another decision table. Protocol construction and session-local
runtime projection consume the declaration rather than repeating its branches.

### Fixed-baseline matrix and red-first gates

The matrix in `test/fixtures/goal14-provider-baseline.json` was generated from
fixed baseline `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`, not from Cadr. It contains
38 unique provider rows, every declared field, OAuth metadata, and the exact
baseline `file:line` source for each row. The four B11 gates are:

- `GOAL14-PROVIDER-MATRIX-IS-FIXED-BASELINE-DERIVED-AND-COMPLETE`;
- `GOAL14-EVERY-PROVIDER-DEFINITION-FIELD-MATCHES-FIXED-BASELINE-MATRIX`;
- `GOAL14-PROVIDER-DECLARATIONS-OWN-RUNTIME-DECISIONS-ONCE`;
- `GOAL14-PROVIDER-AUTH-FILES-HAVE-ONE-REAL-OWNER-EACH`.

They were installed before the split and failed while the 25 owners were
absent and the five mixed files still existed. After implementation they lock
the complete 38-provider field matrix, declaration-derived environment and
auth strategy decisions, owner presence/retirement, and ASDF dependency order.
The focused `cadr-ai` suite passed 4,300 checks with zero skip and zero fail.

### Live-eval assertion audit

The deferred `LIVE-DEEPSEEK-EVAL-SMOKE` audit is resolved. Fixed baseline
`packages/evals/src/smoke.eval.ts:9-15` asks for only the city name and uses
`expect(result.output.trim()).toBe("Paris")`. Cadr
`test/cadr-evals/live-evals-test.lisp:82-103` performs the same trimmed exact
comparison. The strictness is therefore baseline-inherent; Cadr did not weaken
the assertion or add a retry.

The real live path is `cadr-evals` through
`cadr-cli::resolve-provider-config` into the Cadr AI declaration, provider,
auth, runtime, and transport code. B11 is directly on that path, so the live
result is assessed through the matrix/payload gates and real calls rather than
an ASDF-system-boundary argument. In the final verifier run all seven available
live items passed, including the four-check DeepSeek eval; Anthropic alone was
skipped because `ANTHROPIC_API_KEY` is unset.

```text
Items: 8, run: 7, pass: 7, skip: 1, fail: 0
Checks: 32, pass: 31, skip: 1, fail: 0
```

### Full verification

The complete deterministic suite, the isolated build copy, and the final
verifier all reported the same deterministic denominator:

```text
cadr test summary: systems=9 checks=14347 pass=14347 skip=0 fail=0
```

The final `./scripts/verify.sh` stage table was:

```text
Deterministic stages
Stage                                            Result
root cadr binary freshness                       PASS
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

Live stages
Stage                                            Result
credential-gated FiveAM                          PASS
DeepSeek live TUI                                PASS
```

The real source-parity ledger contains 595 accepted entries with SHA-256
`242d90e03ae708b9ea30d71747052af80f6d19e62eec3990a5863c62a614965d`.
The Goal 11 gate passed with sustained-interaction p99.9 of 4 ms, maximum pause
of 20 ms, maximum measured sustained GC pause of 15.26 ms, and converged
sustained memory. Both isolated images used the approved uncompressed fallback
because this SBCL lacks `sb-core-compression`.

Root binary freshness at verification time:

```text
binary build time: 2026-08-04 00:13:20.330289796 +0800
latest source commit: 90313a565b3f65bfc8ce35f866abf3b90d1e325a 2026-08-04T00:11:06+08:00
latest source mtime: 2026-08-03 23:48:53.122125429 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

The final production inventory is 272 Lisp files / 101,013 lines and five
embedded assets / 4,275 lines, for 277 files / 105,288 lines total. All
screen/overlay snapshots and independent semantic assertions, payload and wire
fixtures, package exports, session bytes, tool results, exit codes, and other
observable output remained unchanged. Implementation commit:
`90313a565b3f65bfc8ce35f866abf3b90d1e325a`.

## Part D — permanent organization gates and Goal 14 closeout

### Symptom gate and red-first evidence

`scripts/check-code-organization.py` now scans the real `src/` tree and checks
it against `docs/code-organization-exemptions.json`. The threshold is the
audited Part A histogram boundary: the final 277-file inventory has a distinct
15-file `>=1000` band after the 24-file `700--999` band. It is a manual-review
boundary derived from that distribution, not a target file size. Passing the
gate proves only that every current large-file symptom was reviewed; it does
not prove that ownership is coherent or that decisions are not duplicated.

The checker was added test-first. Before it existed,
`python3 test/code-organization-gate-test.py` failed all six cases. After the
implementation, the same command passes and locks the real repository plus
five fail-closed cases: exactly 1,000 lines without an exemption, 999 lines
without an exemption, an empty reason, a stale exemption, and a duplicate
path. The real invocation reports:

```text
Code organization gate: 277 production files, threshold >= 1000 lines, 15 reviewed exemptions; symptom detector only.
```

The reviewed set is exact and reason-bearing:

| Files | Review conclusion |
|---|---|
| `cadr-agent/export-html/{template.css,template.js}` | Each is one fixed-baseline offline browser asset with no useful Lisp ownership boundary. |
| `cadr-agent/export-html/vendor/highlight.min.js` | Authorized, byte-audited vendored artifact rather than hand-maintained product logic. |
| `cadr-ai/models.generated.lisp` | Generated catalog with an audited generator and generated-file header. |
| `cadr-cli/bootstrap/{commands,sessions}.lisp` | Cohesive slash-dispatch and coding-session workflow owners after shared policy extraction. |
| `cadr-cli/interactive/controller.lisp` | Remaining TUI lifecycle/input controller after all nameable services and renderers were extracted. |
| `cadr-cli/interactive/selectors/{models,sessions,tree}.lisp` | Three independent state machines whose internal behavior shares one domain data set and delegates common chrome/navigation to `selector-frame`. |
| `cadr-cli/interactive/syntax.lisp` | One deterministic highlighting engine and precedence table. |
| `cadr-cli/media.lisp` | One image/media pipeline with shared MIME, sizing, conversion, and encoding invariants. |
| `cadr-tui/components/markdown.lisp` | One streaming Markdown parser/renderer state machine. |
| `cadr-tui/editor.lisp` | One grapheme-aware editor mutation state machine. |
| `cadr-tui/unicode.lisp` | One Unicode/grapheme/ANSI terminal-semantics engine. |

Any missing reason, missing file, below-threshold stale entry, duplicate path,
source symlink, unreadable source, or unreviewed `>=1000` file fails closed.
`verify.sh` runs both the six synthetic cases and this real-tree invocation as
the second of fourteen deterministic stages.

### Decision-owner anti-bypass gates

The line-count gate cannot detect the actual failure class, so each of the nine
Part A repeated decisions has a stronger behavior/source-owner gate:

| Decision owner | Permanent gate |
|---|---|
| bounded thread cleanup | `BOUNDED-CLEANUP-HAS-ONE-OWNER-AND-ACTIVE-JOINS-REQUIRE-A-REASON`; `PRODUCTION-CLEANUP-JOINS-CANNOT-BYPASS-CADR-CORE` |
| cancellation state and propagation | `CANCELLATION-STATE-IS-LOCAL-EXTERNAL-WAITABLE-AND-THREAD-SAFE`; `PRODUCTION-CANCELLATION-ADAPTERS-CANNOT-BYPASS-CADR-CORE` |
| infrastructure output ownership | `GOAL14-B4-CONVERGES-SINKS-AND-JAVASCRIPT-LENGTH-BEFORE-SPLIT`; `GOAL14-B5-CONVERGES-MODE-OUTPUT-AND-TIME-BEFORE-SPLIT` plus the existing process/TUI/server/fatal channel tests |
| selector frame semantics | `GOAL14-B2-SELECTOR-FRAME-OWNS-SHARED-SELECTOR-DECISIONS`; `GOAL14-B2-SELECTOR-FRAME-WRAPS-AND-CENTERS-INDEPENDENTLY` |
| provider identity/auth metadata | `GOAL14-PROVIDER-MATRIX-IS-FIXED-BASELINE-DERIVED-AND-COMPLETE`; `GOAL14-EVERY-PROVIDER-DEFINITION-FIELD-MATCHES-FIXED-BASELINE-MATRIX`; declaration-owner source gates |
| secret-safe object printing | `REDACTED-OBJECT-DECLARATION-REGISTERS-TYPE-AND-NEVER-PRINTS-SECRET`; `ATOMIC-REPLACEMENT-AND-SECRET-PRINTERS-HAVE-ONE-POLICY-OWNER` |
| atomic persistence and modes | `ATOMIC-REPLACEMENT-PRESERVES-OLD-CONTENT-ON-ERROR-AND-PRIVATE-MODE`; the same policy-owner source gate |
| JavaScript UTF-16 length | `GOAL14-B4-CONVERGES-SINKS-AND-JAVASCRIPT-LENGTH-BEFORE-SPLIT`; the existing Chinese/emoji tool-result fixtures |
| ISO time and ID formatting | `UTC-TIME-PRIMITIVES-MATCH-FIXED-BASELINE-VECTORS`; `GOAL14-B5-CONVERGES-MODE-OUTPUT-AND-TIME-BEFORE-SPLIT` |

The new cancellation source gate checks every current cross-system adapter:
AI HTTP/model runtime, agent extension context, TUI autocomplete, and TUI
loaders. The standing rule is now documented in README, architecture, and
`docs/code-organization.md`: before adding code, every future goal must name
its directory owner and state which existing primitive it reuses. A new manual
copy of one of these decisions is a failure even when the file remains small.

### Permanent ownership documentation and parity boundary

`docs/code-organization.md` is now the permanent placement guide. It records
the semantic directory hierarchy, ASDF ordering rule, cross-system limits of
`cadr-core`, all nine decision owners, and the no-quota treatment of cohesive
large files. README and architecture explicitly keep organization separate
from the four correctness-parity axes: behavior, source-capability,
non-functional, and presentation ledgers answer whether Cadr is correct;
organization answers whether it remains maintainable. It is not a fifth
parity axis.

Part D changed no production source. The diff from B11 closeout
`7c01a00c18224a32da7c3918c2132056f884979e` through Part D implementation
`26e5dde96104f0e1fb0386373a1cbb44ee809898` is empty under `src/`. It is also
empty for `docs/parity-map.md`, `docs/source-parity.md`,
`docs/performance.md`, and `docs/presentation-parity.md`. The public
`cadr-ai` package, extension export, and 34-event hashes therefore remain the
B11 values.

### Final distribution

The final physical inventory, verified from the real `src/` tree, is:

| Measure | Goal 14 draft baseline | Final | Change |
|---|---:|---:|---:|
| production files | 135 | 277 | +142 named owners/assets |
| physical lines | 98,796 | 105,288 | +6,492 |
| average lines/file | 732 | 380.10 | -48.1% |
| files below 300 lines | 57 / 135 (42%) | 162 / 277 (58.48%) | +16.48 percentage points |
| files at least 3,000 lines | 5 | 1 | -4 |

The complete final bands are 162 below 300, 76 at 300--699, 24 at 700--999,
and 15 at or above 1,000. Only generated
`src/cadr-ai/models.generated.lisp` remains at or above 3,000. The 58.48%
share deliberately does not imitate pi's 80% distribution by splitting
cohesive editors, parsers, protocol engines, or vendored assets.

### Final verification

The post-implementation-commit deterministic suite and both isolated builds
used the same denominator:

```text
cadr test summary: systems=9 checks=14365 pass=14365 skip=0 fail=0
```

The complete final `./scripts/verify.sh` table was:

```text
Deterministic stages
Stage                                            Result
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

Live stages
Stage                                            Result
credential-gated FiveAM                          PASS
DeepSeek live TUI                                PASS
```

The real source ledger remained 595 entries with SHA-256
`242d90e03ae708b9ea30d71747052af80f6d19e62eec3990a5863c62a614965d`.
All seven available live items passed; Anthropic alone was skipped because
`ANTHROPIC_API_KEY` is unset. There were no failed items or failure output:

```text
Items: 8, run: 7, pass: 7, skip: 1, fail: 0
Checks: 32, pass: 31, skip: 1, fail: 0
```

`LIVE-DEEPSEEK-EVAL-SMOKE` passed all four checks. The Goal 11 sustained gate
reported p99.9 12 ms, maximum pause 44 ms, maximum measured sustained GC pause
13.05 ms, and converged memory. Both isolated images and the root image took
the approved uncompressed fallback because this SBCL lacks
`sb-core-compression`.

Root delivery evidence:

```text
binary build time: 2026-08-04 00:42:35.273135741 +0800
latest source commit: 90313a565b3f65bfc8ce35f866abf3b90d1e325a 2026-08-04T00:11:06+08:00
latest source mtime: 2026-08-03 23:48:53.122125429 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
root binary freshness: PASS
```

Part D implementation commit:
`26e5dde96104f0e1fb0386373a1cbb44ee809898`. The pre-existing user changes in
`docs/acceptance/goal-v8-final.md` and `ms9te620-dgwif1j3gv42.html` were not
staged or modified by Goal 14.
