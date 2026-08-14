# Goal 12 supplementary unfreeze proposal for the extension API implementation surface

Status: **A/B/C were approved by the user item by item on 2026-08-02; for the D/E
produced by the later call-chain audit see
`goal-v12-api-scope-amendment-2.md`.**

Fixed baseline:
`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`
(`v0.83.0-38-g74caa2649`). Every baseline `file:line` in this document refers to
that commit.

## 1. Why a supplementary adjudication is required

The user has already approved all 19 capabilities of
`goal-v12-example-api-gaps.md`, but stipulated at the same time: whenever an
implementation needs to go beyond the minimal file surface listed for an item, it
must immediately be blocked and re-proposed. Reading each path before starting
work proved that the real baseline semantics of items 7, 8 and 10 necessarily
pass through core files that were not originally listed. This is not a widening
of functionality; it is that the original proposal judged the existing Cadr
layering incompletely.

This proposal requests only the files whose unfreezing is indispensable; the
requirements, default behavior, dependencies and rollback boundaries of the
original 19 items are all unchanged. `src/cadr-ai` remains completely frozen.

## 2. Supplementary item A: the agent-loop semantics of tool terminate in item 7

### 2.1 Exact requirement and baseline evidence

- `packages/agent/src/types.ts:354-368` defines `terminate` as an agent-only hint
  on `AgentToolResult` that does not go onto the provider wire.
- `packages/agent/src/agent-loop.ts:540-553,582-584` prescribes the exact batch
  semantics: the agent loop terminates only when the finalized calls are
  non-empty and every final result in that batch has `terminate === true`. A
  mixed batch does not terminate.
- `packages/coding-agent/src/core/extensions/types.ts:446-497` makes that field
  part of the result contract of an extension tool's execute.

Cadr's current outcome and executor return contract in
`src/cadr-agent/tool.lisp:127-130,228-254` keeps only content/details; the third
value of the batch in `src/cadr-agent/loop.lisp:457-548,885-908` has only abort,
and cannot express "stop only when all terminate".

### 2.2 Minimal supplementary unfreeze surface

- `src/cadr-agent/tool.lisp`: keep terminate in the agent-only outcome; do not
  change `cadr-ai:tool-result-message`.
- `src/cadr-agent/loop.lisp`: apply to the finalized outcomes the same
  non-empty + `every` batch gating as the baseline, kept separate from the abort
  state.

The rest of the file surface of the already-approved item 7 is unchanged.
`src/cadr-ai` is not unfrozen.

### 2.3 Default behavior and gates

- Every old tool defaults to terminate=nil, and its result, events and JSON/RPC
  wire are byte-for-byte unchanged.
- Red-test coverage: a single true, all true, a true/nil mix, an empty batch, the
  final value of the after hook; and it locks that every tool result still enters
  the session in full.
- The old extension fixtures, the old macro lambda list, the 34-event set and the
  payload/wire fixtures are unchanged.

### 2.4 Alternatives considered and rejected

- Writing terminate into details: it would pollute the observable payload sent to
  the model and the UI, and the loop still would not read it.
- Treating terminate as abort/error: it would disguise a normal termination as an
  error and change events and the session.
- Stopping immediately on a single tool: it violates the baseline's whole-batch
  `every` semantics.

Rollback: delete the outcome field and the loop gate; old paths need no migration
because the default is nil.

## 3. Supplementary item B: the execution path of partial update and cancellation in item 8

### 3.1 Exact requirement and baseline evidence

- `packages/coding-agent/src/core/extensions/types.ts:307-346,479-486` prescribes
  that the handler receives signal, onUpdate and ExtensionContext.
- `packages/agent/src/types.ts:371-377,388-394` defines the partial callback as a
  contract bounded to that one execute; callbacks after the handler settles must
  be ignored.
- `packages/agent/src/agent-loop.ts:672-689` emits `tool_execution_update` from
  the agent tool execution layer.

Cadr currently reduces the extension handler to `(call-id arguments context)` in
`src/cadr-agent/extensions.lisp:2024-2064`; the executor in
`src/cadr-agent/tool.lisp:228-254` takes only two arguments;
`src/cadr-agent/loop.lisp:175-189,457-548` emits only start/end. Emitting events
ad hoc inside the extension adapter alone cannot guarantee the settle boundary,
restart retries, parallel batch ordering, or consistency with the core
lifecycle.

### 3.2 Minimal supplementary unfreeze surface

- `src/cadr-agent/tool.lisp`: pass this invocation's cancellation signal and
  update callback into the tool executor, and close the callback with
  unwind-protect so that updates after settle are ignored.
- `src/cadr-agent/loop.lisp`: emit `:tool-execution-update` through the existing
  agent lifecycle/event spine, keeping the same call-id and parallel-batch
  isolation.

The extensions/package/execution-env/CLI tool factory file surface of the
already-approved item 8 is unchanged. `src/cadr-ai` is not unfrozen.

### 3.3 Default behavior and gates

- The old two-argument `cadr-ai:tool-executor` and the old three-argument
  extension handler still go through a compatibility adapter; with no partial,
  the event sequence is byte-for-byte unchanged.
- Red-test coverage: several updates in a single call, updates after settle being
  ignored, handler errors, a new signal after retry, user abort, parallel tool
  isolation, and the exact ordering of update/start/end.
- `ctx.shutdown()` keeps calling the existing agent shutdown; no new exit policy
  is added.

### 3.4 Alternatives considered and rejected

- Emitting directly inside the extension adapter: it bypasses the tool
  restart/settle layer, and a late callback would leak into a subsequent turn.
- Having the extension poll `extension-cancellation-aborted-p`: it cannot bind a
  user abort precisely to that one tool invocation, and it also lacks the partial
  callback.
- Synthesizing updates only in the TUI: print/json/rpc would diverge from the
  core lifecycle.

Rollback: delete the execution-context arguments and the update emission; the old
adapter is unchanged.

## 4. Supplementary item C: item 10 entering the real `/login` orchestration

### 4.1 Exact requirement and baseline evidence

- `packages/coding-agent/src/core/extensions/types.ts:1364-1475` prescribes the
  login/refresh/getApiKey/model projection/custom stream contract of an extension
  provider.
- `packages/coding-agent/src/core/extensions/provider-composer.ts:230-247,411-498`
  adapts that contract onto the unified provider/auth runtime, instead of letting
  the extension write the credential file directly.

Cadr does already have a runtime-provider and auth storage, but
`src/cadr-cli/config.lisp:221-236` accepts only openai/openai-codex/anthropic,
and the `/login` at `:238-275` uses `ecase` to call two built-in functions
directly. `src/cadr-cli/main.lisp:3141-3148` handles that path before extension
commands, so changing only the already-approved extensions/model-services cannot
make extension OAuth enter the real `/login`.

### 4.2 Minimal supplementary unfreeze surface

- `src/cadr-cli/config.lisp`: let `handle-auth-command` accept an injected
  provider OAuth resolver/handler; with no injection, the built-in
  openai/anthropic path and its copy are unchanged.
- `src/cadr-cli/main.lisp`: bind the current extension/model runtime to the auth
  command, reusing the existing auth store, refresh lock and atomic write.
- `src/cadr-cli/tui.lisp` **is unfrozen only conditionally**: if the
  display/input of the extension OAuth callback cannot be carried in full by the
  existing `/login` output/auth-url bridge, only adding the same callback bridge
  is allowed; the selector layout, copy and default entries must not change. If
  the implementation proves it unnecessary, the file is not modified.

The already-approved extensions/model-services file surface is unchanged.
`src/cadr-ai` stays frozen.

### 4.3 Default behavior and gates

- With no extension OAuth, `/login openai`, `/login anthropic`, the
  argument-less selector, the stored provider identity and all copy are
  byte-for-byte unchanged.
- The red tests use a temporary auth store and network stubs, covering: the
  extension provider appearing in `/login`; login credentials landing on disk
  under the same provider identity; the default route being immediately
  retrievable; a concurrent refresh happening only once;
  getApiKey/model projection/custom stream each taking effect; reload removing
  the auth method/model without deleting already-stored credentials.
- Logs, conditions, notices and wire fixtures must not contain a token/refresh
  secret.

### 4.4 Alternatives considered and rejected

- Letting the example write `auth.json` directly: it bypasses identity, the
  refresh lock, the atomic write and permission preservation, and is the
  explicitly forbidden "passing by bypassing".
- Treating the extension `/login` as an ordinary custom command: the core auth
  handler intercepts it first, and it cannot enter the unified credential/runtime
  contract.
- Adding a special case in `src/cadr-ai`: unnecessary, and it violates the freeze
  red line.

Rollback: delete the auth resolver injection and the runtime binding; the
built-in functions remain the default.

## 5. Adjudication and construction order

Please adjudicate item by item:

1. **A (supplementary file surface for item 7): approve / reject / defer.**
2. **B (supplementary file surface for item 8): approve / reject / defer.**
3. **C (supplementary file surface for item 10): approve / reject / defer.**

Once the three are approved, the original construction order 1→10, 15→19, 11,
13→12→14, Part D resumes, and no repeated adjudication is requested for
already-approved capabilities. If any one of them is not approved, the examples
blocked by that gap continue to be recorded as 缺失; the capability approvals of
the remaining items are unchanged, but in order to obey the "immediately
blocked" hard constraint, this round does not start work before the new
adjudication.
