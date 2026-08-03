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

| System | 合格 | 合格·大体量 | 应拆分 | 应合并 | Total |
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
verdict totals: 合格=62 合格·大体量=52 应拆分=29 应合并=0
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
