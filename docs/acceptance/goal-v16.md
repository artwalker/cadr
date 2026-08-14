# Goal 16 acceptance record

Status: Part A0, A, B, Part C1-C5, and Part D are complete and committed; awaiting user acceptance.

## Part A0: compaction degradation behavior

Separate commit: `3dbb58b895a1f732d6354233e91d6981b0a35c09`
(`fix(agent): align compaction degradation with baseline`).

### Baseline contract and implementation

- `packages/coding-agent/src/core/compaction/compaction.ts:679-685` of the fixed
  baseline `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5` fails only when
  `stopReason === "error"`; the already generated text for an empty string,
  whitespace, `length`, `toolUse`, and `aborted` is all returned as is.
- `packages/coding-agent/src/core/branch-summarization.ts:353-375` returns abort
  as a cancellation, uses the provider's copy for error, and finally degrades an
  empty summary to `No summary generated`.
- Cadr reuses the existing `agent-stream-function`, the extension cancellation
  signal, session journal/migration, and overflow temporary-branch recovery; no new
  retrier and no new mechanism were created.

Change ownership:

| Contract | Implementation location |
|---|---|
| summary failure/degradation matrix, no persistence after abort | `src/cadr-agent/compaction.lisp` |
| branch abort/error/empty fallback | `src/cadr-agent/branch-summarization.lisp`, `src/cadr-agent/loop/agent-loop.lisp` |
| empty/whitespace summary persistence and reload | `src/cadr-agent/session/journal.lisp`, `src/cadr-agent/session/migration.lisp` |

The path audit additionally found and removed three same-origin over-strictnesses:
extension compaction rejecting an empty summary, the journal rejecting an empty
summary, and migration being unable to reload a persisted empty summary. No
empty-value failure branch that the baseline does not have was retained.

### Recovery and self-rescue

- When threshold auto-compaction fails, the original context is kept and the current
  prompt continues; the agent's busy state is cleared by the existing
  unwind-protect. The user may continue the conversation or run `/compact` again.
- When context-overflow compaction succeeds it retries along the existing path; when
  it fails it restores the original error leaf and returns the provider error, but
  the agent goes back to idle and the next prompt can still be executed.
- When the user cancels after the summary response, no compaction entry is written;
  a branch summary abort does not move the session leaf.

### Red/green evidence

Added/updated gates:

- `COMPACTION-SUMMARY-FAILURE-CONTRACT-MATCHES-BASELINE`
- `EMPTY-AND-WHITESPACE-COMPACTION-SUMMARIES-PERSIST-AND-CONTINUE`
- `EXTENSION-COMPACTION-ALLOWS-EMPTY-AND-WHITESPACE-SUMMARIES`
- `USER-ABORT-AFTER-SUMMARY-RESPONSE-DOES-NOT-PERSIST-COMPACTION`
- `FAILED-OVERFLOW-COMPACTION-LEAVES-SESSION-USABLE`
- `BRANCH-SUMMARY-USES-BASELINE-EMPTY-FALLBACK`
- `ABORTED-BRANCH-SUMMARY-CANCELS-WITHOUT-MOVING-THE-SESSION`
- `SESSION-COMPACTION-EMPTY-HOOK-IS-USED-FAILING-HOOK-FALLS-BACK-AND-ABORT-STOPS`

The tests-first run against the old implementation: 998 checks / 990 pass / 0 skip /
**8 fail**, the failures hitting item by item the empty summary, the whitespace
summary, the extension summary, the overflow error copy, and the branch fallback.
After the fix `CADR-AGENT-SUITE` is 1024/1024/0/0.

## Part A: identity audit

Commit: `dcba371ff` (`docs: audit product identity across the full tree`). Artifact:
`docs/identity-audit.md`. Part A's staged diff contains only that audit and this
report, with zero change to production code. Results:

- full enumeration yields 14 distinct production `PI_*` environment variables;
- six groups of third-party attribution values (including the xAI referrer) are all
  `must replace`, with an existing user pre-adjudication;
- Radius `pi-gateway` has registration-contract evidence from live discovery, and
  `radius.pi.dev` is a real provider/API endpoint; the two are not speculative
  retentions;
- `/share`, the version check, the HTML viewer meta contract, and the
  environment-variable migration have been separated out as Part B decisions;
- additionally found: export localStorage, the notify example, the synthetic tool
  call ID, Radius free-form log copy, and residual exported Lisp API names;
- catalog comments, the fixed-baseline harness, the version-alignment declaration,
  the extension manifest `"pi"` schema, and the Radius wire dialect have each been
  given a retention reason.

## Part B: adjudicated proposal

Proposal: `docs/proposals/goal-v16-identity.md`. It splits the implementation
decisions into six items:

1. the `/share` default viewer is finally adjudicated as `https://cadr.dev/session/`,
   stays enabled, and is overridden only by `CADR_SHARE_VIEWER_URL` or an explicit
   argument; the user has knowingly accepted that the link is temporarily unreachable
   before the page goes live;
2. the version check is disabled by default when no Cadr endpoint is configured;
3. the 14 `PI_*` environment variables are hard-switched to `CADR_*`, retaining no
   alias or warning compatibility period;
4. non-contract identity values such as the repository link, temporary files, HTML
   localStorage, the synthetic call ID, Radius free-form copy, and the example title
   are replaced as one group;
5. an exact allowlist for Radius registration/API/wire, the extension manifest, and
   catalog/baseline provenance;
6. reuse the existing release identity as the private single source, and enter the D
   gate after C1→C5.

The User-Agent, OpenRouter, NVIDIA, Cloudflare, OpenCode, and xAI referrer values the
user pre-adjudicated in the Goal 16 specification are not submitted for adjudication
again. Part B only writes documentation; it did not modify production code.

Radius external verification (2026-08-04):

```text
GET https://radius.pi.dev/             -> HTTP 200
GET https://radius.pi.dev/v1/oauth     -> HTTP 200
discovery.clientId                     -> pi-gateway
discovery.scope                        -> gateway offline_access
```

## Part C: identity convergence implementation

### C1: single identity source and third-party attribution

Commit `cc4f1f0e0`. `src/cadr-ai/support/release.lisp` uniformly owns the product
slug, display name, canonical repository URL, and default share viewer; the version
User-Agent, OpenRouter, NVIDIA, Cloudflare, OpenCode, and the xAI device-code
referrer are all derived from the Cadr identity. xAI issued a real device
authorization request with the same client ID/scope and `referrer=cadr` and received
HTTP 200, so no fallback functional constraint is needed.

The contract gates include `GOAL16-PRODUCT-IDENTITY-HAS-ONE-PRIVATE-OWNER`,
`GOAL16-THIRD-PARTY-ATTRIBUTION-USES-CADR-IDENTITY`, and the existing xAI OAuth
payload test; the remaining fields of the provider payload are unchanged.

### C2: service endpoints

Commit `ac23e11bb`. `/share` uses `https://cadr.dev/session/` as the default viewer;
a non-empty `CADR_SHARE_VIEWER_URL` and an explicit argument keep their override
precedence; the success state presents both the generated link and the viewer
address. render-diff's `slash-share` adds only the approved I03 URL difference, and
the complete 40/40 capture and the fail-closed dispositions all pass.

The version check no longer queries pi.dev; when `CADR_VERSION_CHECK_URL` is not
configured no network request is made, and once configured it reuses the original
timeout, JSON, comparison, and silent-network-failure contracts, while `CADR_OFFLINE`
and `CADR_SKIP_VERSION_CHECK` can still switch it off. This item is recorded in the
CHANGELOG as a fix, because comparing the version numbers of two different products
has no meaning in itself.

### C3: environment-variable hard switch

Commit `af8612d95`. The 14 old production names were hard-switched to `CADR_*` in one
go per the approved table, among which `PI_MODEL -> CADR_EVAL_MODEL` and
`PI_PROVIDER -> CADR_EVAL_PROVIDER` are explicit renames, not a simple prefix change.
A scan for old names in production `src/` returns zero; `PI_OFFLINE` in the fixed
TypeScript baseline driver does not belong to the Cadr runtime and is retained.

The gate `GOAL16-C3-PRODUCTION-ENVIRONMENT-NAMES-ARE-CADR-ONLY` proves both that the
new names take effect and that the old names are no longer read; the behavioral
regressions for Bedrock/eval/server/tool/version all pass.

### C4: free-form identity values

Commit `5eb36c930`. The `/changelog` canonical repository, the WSL temporary file,
the notify example, the exported HTML localStorage, the synthetic tool-call ID, and
the Radius free-form log/thread copy have been replaced. The Radius
client/API/wire, the extension manifest, the generated provenance, and the
fixed-baseline inputs were not changed.

The gate `GOAL16-C4-FREE-IDENTITY-VALUES-ARE-CADR-OWNED` asserts file by file that
the old strings are gone; the HTML template SHA was updated in step, and session
entries, payload, and wire did not change.

### C5: documentation convergence

commit `481033fe1`.

The README records the 14-item migration table, the share transition period, the
version-check switch, and the external contract boundary; the CHANGELOG lists the
version check as a fix; architecture, the audit, the proposal, and open-questions all
synchronize the final adjudication. Part C added no dependency, compatibility layer,
telemetry, or unadjudicated mechanism.

## Part D: product-identity drift gate

commit `44f8dd8a7`.

- `scripts/check-product-identity.py` scans only the production scope: `src/`,
  `examples/`, `scripts/`, `.github/`, the root README/CHANGELOG, ASDF, and the build
  entry points.
- `docs/product-identity-allowlist.json` records 274 real hits, 251 exact
  dispositions, and 1 SHA-256-locked opaque asset in total. Every disposition binds
  path, kind, token, the complete line content, the occurrence count, and a non-empty
  reason at once; a directory, glob, regex, or empty-reason exemption is illegal.
- The gate is fail-closed and rejects a new hit, the same token after a move, a
  duplicate/expired disposition, count drift, total drift, and opaque digest drift.
  The 9 independent regressions of `test/product-identity-gate-test.py` cover these
  counterexamples and drive the current real repository directly.
- Tests-first evidence: with no checker, the synthetic cases fail as a whole batch;
  with the checker landed but no real manifest, the real-repository case fails; with
  `verify.sh` not yet wired in, the ordering-contract regression fails. After
  implementation 9/9 pass, and the real scan counts equal the manifest item by item.
- `scripts/verify.sh` runs the synthetic regressions and the real-tree scan in order
  after code organization and before source parity/FiveAM/build; a failure of either
  blocks the subsequent deterministic stages.
- The standing policy lands in `docs/development-policy.md`: changing the identity
  allowlist is equivalent to changing the product identity boundary, and must first
  go through a written proposal and item-by-item user adjudication.

## Goal 16 complete verification (2026-08-05)

`./scripts/test-cl.sh`:

```text
cadr test summary: systems=9 checks=14827 pass=14827 skip=0 fail=0
```

`./scripts/verify.sh`:

| Stage | Result |
|---|---|
| root cadr binary freshness | PASS |
| code organization gate | PASS |
| product identity gate | PASS (9 synthetic/real regressions; 274 hits / 251 dispositions / 1 opaque) |
| real source parity ledger | PASS (595) |
| source parity drift self-test | PASS |
| deterministic FiveAM | PASS (14,827/14,827) |
| isolated cadr build | PASS (uncompressed degradation when core compression is absent) |
| isolated cadr-server build | PASS (uncompressed degradation when core compression is absent) |
| Goal 11 performance and stability gate | PASS |
| native acceptance smoke | PASS |
| native process modes | PASS |
| migration PTY smoke | PASS |
| Unix socket server smoke | PASS |
| terminal lifecycle PTY | PASS (6/6) |
| deterministic TUI harness | PASS |
| fixed-baseline render differential | PASS (40/40; 160/160 dispositions) |
| credential-gated FiveAM | PASS (7 pass / 1 Anthropic credential skip / 0 fail) |
| DeepSeek live TUI | PASS |

The live item-level statistics are 8 items, 7 run/pass, 1 `ANTHROPIC_API_KEY is not
set` skip; the check-level statistics are 32 checks / 31 pass / 1 skip / 0 fail. That
result does not pass itself off as deterministic evidence.

Root binary freshness:

```text
binary build time: 2026-08-05 02:07:50.103011288 +0800
latest src commit: 5eb36c930 2026-08-05T01:28:46+08:00
latest source mtime: 2026-08-05 01:23:24 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

## Post-closeout A/B correction: bash truncation and the state matrix

The fixed baseline actually has two different bash presentation paths. The
`modes/interactive/components/bash-execution.ts:190-200` the user cited belongs to `!`
direct execution; this screenshot comes from ordinary agent bash, whose corresponding
contract is `core/tools/bash.ts:248-306`: the detailed footer of the model result is
retained, but the TUI strips it at `:251-255` and at `:292-306` produces only a single
warning-colored `[Full output: ... Truncated: ...]`. Cadr already does the same
layering at `src/cadr-cli/interactive/tool-rendering.lisp:331-376`; the model result,
the session history, and the JSON/RPC wire were all left unmodified.

`reachable-interfaces.json` and the checker now expand completeness into "interface ×
significant state". The required set is held independently by the checker, and
deleting the same state/domain from the ledger also fails; every item must have a
fixed-baseline token, a deterministic trigger, and either a valid checkpoint or an
explicit reason for not capturing. All 7 current items are really captured with zero
exemptions; their triggers and checkpoints are in `docs/render-diff.md`. The new
scenarios expand the matrix from 20×2/83 checkpoints to 21×2/89 checkpoints. The
direct reason the old gate did not catch it is that none of the 20 scenarios had any
output exceeding 50KB or 2,000 lines, and the static tool-result test did not go
through the real TUI's combined "result footer + presentation warning" path.

### 105.6% context compaction investigation (no code change this round)

1. **A separate size trim: none.** The baseline's `compaction.ts:710-788` retains the
   recent `keepRecentTokens` through a cut point, but `:648-666` serializes the
   remaining `messagesToSummarize` as a whole into a single summary prompt, with no
   second trim against the model window. Cadr likewise retains recent content by a
   cut point and sends the source entries in one go at `compaction.lisp:189-225`; it
   only does a 2,000-character trim on each tool result (`:109-114`), and it has no
   global prompt budget either.
2. **Trigger threshold: identical on the 272k model.** The baseline's default
   reserve/keep is 16,384/20,000 (`compaction.ts:132-136`), with the condition
   `contextTokens > contextWindow - reserveTokens` (`:232-238`), i.e. a 272,000 window
   triggers at 255,616 tokens, about 94.0%. Cadr's defaults are the same
   (`runtime.lisp:39-43`) and the decision sits at `compaction.lisp:339-366`; its small
   windows cap both values to a quarter of the window, but 272k does not trigger that
   cap. Seeing 105.6% does not prove a late trigger; more likely compaction had
   already failed after 94% and the original context is retained under the baseline's
   degradation semantics.
3. **Failure recovery: a bounded retry exists, a summary-shrinking fallback does
   not.** All baseline summary requests go through `completeSummarization` →
   `retryAssistantCall` (`compaction.ts:555-580`), using the configured retry policy;
   once it is exhausted, threshold only emits `Auto-compaction failed: ...`
   (`agent-session.ts:2196-2211`). A context overflow may compact and then retry the
   original prompt once, and only a second overflow prompts to reduce the context or
   switch to a larger window (`:1979-2011`). Cadr already has one overflow
   compact-and-retry (`loop/agent-loop.lisp:73-101`), but the summary call
   `compaction.lisp:205-225` does not go through the retry wrapper; this is the parity
   gap the investigation found. This round's generic provider error alone cannot
   determine whether it was a window overflow or a transient error, so nothing was
   modified without authorization this round; a separate correction should be raised
   to wire the summary retry through per the baseline, and to preserve the baseline
   boundary of "no second trim / no degraded summary algorithm".

### Correction commits and final verification

- `0ac0b054a`: the model result/TUI presentation layering for ordinary agent bash, and
  the regression for the original defect.
- `79971ecac`: the significant-state registry, the 21-scenario/89-checkpoint matrix,
  the fail-closed regressions, and the identity dispositions for the two fixed-baseline
  paths. The product-identity gate is currently at 276 hits, 253 exact
  dispositions, and 1 digest-locked opaque file.

`./scripts/test-cl.sh` run independently on the content of those commits:

```text
cadr test summary: systems=9 checks=14832 pass=14832 skip=0 fail=0
```

`./scripts/verify.sh` complete stage summary:

| Stage | Result |
|---|---|
| root cadr binary freshness | PASS |
| code organization gate | PASS |
| product identity gate | PASS (276 / 253 / 1 opaque) |
| real source parity ledger | PASS (595) |
| source parity drift self-test | PASS |
| deterministic FiveAM | PASS (14,832/14,832) |
| isolated cadr build | PASS (uncompressed degradation when SBCL has no core compression) |
| isolated cadr-server build | PASS (uncompressed degradation when SBCL has no core compression) |
| Goal 11 performance and stability gate | PASS |
| native acceptance smoke | PASS |
| native process modes | PASS |
| migration PTY smoke | PASS |
| Unix socket server smoke | PASS |
| terminal lifecycle PTY | PASS (6/6) |
| deterministic TUI harness | PASS |
| fixed-baseline render differential | PASS (42/42; 6 aligned; 172/172 adjudicated) |
| credential-gated FiveAM | PASS (7 pass / 1 Anthropic credential skip / 0 fail) |
| DeepSeek live TUI | PASS |

The live item-level statistics are 8 items, 7 run/pass, 1 `ANTHROPIC_API_KEY is not
set` skip; the check-level statistics are 32 checks / 31 pass / 1 skip / 0 fail.

The root binary was rebuilt again after the implementation was committed; freshness
evidence:

```text
binary build time: 2026-08-05 06:39:25.510688474 +0800
latest src commit: 0ac0b054a43c0844b7c35a0b3509058a05dacd8a 2026-08-05T06:36:56+08:00
latest source mtime: 2026-08-05 05:55:39.195234996 +0800 /root/projects/cadr/src/cadr-cli/interactive/tool-rendering.lisp
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```
