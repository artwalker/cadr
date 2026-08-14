# Goal 12 third supplementary unfreeze proposal for the extension API implementation surface

状态：**approved and implemented** (the user adjudicated item by item on 2026-08-02: F：批准, G：批准, H：批准).

Fixed baseline:
`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`
(`v0.83.0-38-g74caa2649`). Every baseline `file:line` in this document refers to
that commit.

## 1. Why work stopped again

After D/E were approved, the runtime/TUI/OAuth bridge within the authorized scope
was implemented, and 94 of the 99 baseline extension examples can already be
ported with the existing API. A real-entry-point audit done one by one confirmed
that the remaining 5 files depend on three baseline contracts that are not yet
wired into the production call chain:

- `custom-compaction.ts`: `:session-before-compact` does already exist in the
  event table and the return-value validator, but the main compact path never
  dispatches it;
- `prompt-customizer.ts`: the `:system-prompt-options` of `:before-agent-start`
  is currently hard-coded to NIL;
- the 3 files of custom Anthropic and GitLab Duo: the OAuth/token/direct-access
  control plane depends on an HTTP seam that the extension can call, and Cadr
  currently has only the subprocess `exec` and no equivalent capability.

This is not a new product feature; it is that the earlier proposal misjudged "the
API is already declared" as "the real call chain is already closed". But all
three go beyond the approved file surface, and the user has explicitly required
that any boundary crossing be immediately blocked. So no example was faked,
`cadr-ai::native-http-request` was not called, no function was globally replaced,
and no provider was written into the global registry. Before approval the current
ledger honestly records **94 ported / 5 gap**; after implementation it is
**99 ported / 0 gap**.

## 2. Supplementary item F: wire `session_before_compact` into the real compaction lifecycle

### 2.1 Exact requirement and baseline evidence

The baseline dispatches on both the manual and the automatic compaction paths
before the summary is generated:

- `packages/coding-agent/src/core/agent-session.ts:1796-1831`: manual compaction
  passes in `preparation`, `branchEntries`, `customInstructions`,
  `reason="manual"`, `willRetry=false` and the abort signal, and accepts a cancel
  or a complete custom compaction;
- `:2065-2105` in the same file: the threshold/overflow path uses the same
  contract;
- `packages/coding-agent/src/core/extensions/types.ts:591-612`: the frozen event and the after-event fields;
- `packages/coding-agent/examples/extensions/custom-compaction.ts:21-131`: the example reads the complete
  preparation and returns `summary/firstKeptEntryId/tokensBefore/usage`.

Cadr already validates and merges the `:cancel-p/:compaction` return values of
`:session-before-compact` in
`src/cadr-agent/extensions.lisp:3527-3569,3577-3584,3903-3909`, but
`src/cadr-agent/compaction.lisp:235-297` generates and writes the default summary
directly, and has never called the lifecycle.

### 2.2 Minimal supplementary unfreeze surface

- `src/cadr-agent/compaction.lisp`: dispatch once preparation is complete and the
  default summarizer has not yet been called; pass in the source/kept entries,
  the token count, the custom instructions, the manual/threshold/overflow reason,
  will-retry and the session-local cancellation signal; consume strictly the
  already-existing `:cancel-p/:compaction` contract.
- The corresponding `test/cadr-agent/*compaction*` and Goal 12 example tests.

`src/cadr-ai` is not modified, no event is added, and the already-frozen event
semantics of `extensions.lisp` are not changed.

### 2.3 Default behavior and gates

- With no handler, or when the handler returns NIL, the default summary input,
  the event ordering, the session entry, the JSON/RPC wire and the error copy are
  byte-for-byte unchanged.
- Red-test coverage: the manual/threshold/overflow payload; cancel; extension
  compaction; the empty-summary fallback; abort; the handler-error fallback;
  `from-extension` on the after event; the custom result being written into the
  session in full.
- The existing `:session-before-compact` event name and return structure gain no
  fields and do not change meaning.

### 2.4 Alternatives, freeze and rollback

- Rewriting the `/compact` command inside the example: it bypasses automatic
  compaction/overflow and is not the baseline contract.
- Calling the hook but ignoring the return value: it would disguise "there is an
  event" as "it is customizable".

Rollback deletes only the dispatch branch on the main compaction path; the old
path with no handler keeps its original function body.

## 3. Supplementary item G: store and emit the real `systemPromptOptions`

### 3.1 Exact requirement and baseline evidence

The baseline `BuildSystemPromptOptions` contains the custom prompt, selected
tools, tool snippets, prompt guidelines, append prompt, cwd, context files and
skills:

- `packages/coding-agent/src/core/system-prompt.ts:8-25`: the complete field contract;
- `packages/coding-agent/src/core/extensions/types.ts:698-709`: `before_agent_start` must carry the
  fully assembled prompt and the structured options that built it;
- `packages/coding-agent/src/core/extensions/runner.ts:1081-1112`: every handler receives the same
  options, and the per-handler modification of the system prompt does not pollute
  the options in return;
- `packages/coding-agent/examples/extensions/prompt-customizer.ts:22-96`: the example depends on
  `selectedTools/skills/appendSystemPrompt`, not on an approximation that only reads cwd.

Cadr's `src/cadr-agent/loop.lisp:1259-1277` hard-codes `:system-prompt-options`
to NIL; the real fields are immediately flattened into a string only after being
assembled in `src/cadr-cli/main.lisp:2280-2323` and
`src/cadr-cli/sdk.lisp:355-375`. The command-only getter at
`src/cadr-agent/extensions.lisp:258-265` cannot replace the lifecycle event
payload, and its semantics must not be relaxed either.

### 3.2 Minimal supplementary unfreeze surface

- `src/cadr-agent/runtime.lisp`, `src/cadr-agent/tool.lisp`: the agent gains a
  read-only `system-prompt-options` slot/constructor argument; when it is not
  passed in, it is NIL.
- `src/cadr-agent/loop.lisp`: the `before-agent-start` payload reads that slot,
  keeping the existing system-prompt string and the per-handler merge semantics.
- `src/cadr-cli/main.lisp`, `src/cadr-cli/sdk.lisp`: system prompt construction
  returns both the prompt and defensive-copy options, and updates both atomically
  on reload.
- The corresponding agent/CLI/SDK/example tests.

The prompt builder in `sdk-services.lisp` is not modified, the command-only
getter is not changed, and `src/cadr-ai` is not modified.

### 3.3 Default behavior and gates

- When the constructor does not pass options, the event still carries NIL; the
  existing call sites and the external construction API stay compatible.
- The final system prompt of the real CLI/SDK path must be byte-for-byte
  unchanged; only the structured event field that was previously NIL is added,
  and it does not enter the agent-event/JSON/RPC wire.
- Red-test coverage of all 8 fields, the defensive copy, the ordering of two
  handlers, the reload update, CLI/SDK equivalence, and the command-only getter
  continuing to reject a lifecycle context.

### 3.4 Alternatives, freeze and rollback

- Having the handler rescan the resources on the spot: inconsistent timing,
  duplicated I/O, and it violates the baseline's "no rediscovery needed".
- Parsing backwards from the final prompt: lossy, and it would treat formatting
  details as the API.
- Borrowing the command-only getter: it changes the already-frozen context-kind
  semantics.

Rollback deletes the agent slot / the two-value return; the prompt builder and
the final prompt itself are unchanged.

## 4. Supplementary item H: a session-local extension HTTP control-plane seam

### 4.1 Exact requirement and baseline evidence

Baseline extensions run in JS and can naturally call `fetch`; the two provider
examples use that capability for real authentication and the provider control
plane:

- `custom-provider-anthropic/index.ts:78-153`: both the authorization-code
  exchange and refresh POST JSON to the token endpoint; `:574-609` registers the
  OAuth and the custom stream;
- `custom-provider-gitlab-duo/index.ts:183-208`: exchanges the OAuth access token
  for a direct-access token and caches it; `:233-300` completes the
  form-urlencoded login/refresh; `:306-375` projects the short-lived
  token/headers onto the existing Anthropic/OpenAI stream;
- `:381-403` in the same file: those capabilities are part of the provider
  registration, not a standalone demo.

Cadr's `src/cadr-agent/extensions.lisp:26-45,781-815,1823-1860` has only the host
`exec` seam. `cadr-ai:*http-request-function*` is exported, but the interface
needed to construct a request is not public; calling
`cadr-ai::native-http-request` directly would make extensions depend on a private
implementation of the frozen layer. Shelling out to `curl` would in turn add a
host dependency and expose the token in the process arguments/environment;
neither is accepted.

### 4.2 Minimal supplementary unfreeze surface and signature

- `src/cadr-agent/extensions.lisp`: add a session-local
  `http-request-function` to the extension host, exported additively:

  ```lisp
  (extension-api-http-request api url
    &key method headers body timeout-ms signal)
  => (:status integer :headers alist :body octet-vector)
  ```

  The URL/method/header/body are copied and validated first; signal/timeout
  propagate; the return value contains no request secrets.
- `src/cadr-agent/package.lisp`: export only the form above and the necessary
  result readers (if the implementation uses a struct).
- `src/cadr-cli/extensions.lisp`: inject the adapter when the host is created,
  internally reusing the existing Cadr-AI HTTP transport; the extension sees only
  the stable agent API, never the Cadr-AI private request object.
- `src/cadr-cli/sdk.lisp`: the SDK host uses the same adapter, avoiding a fork
  between the CLI and SDK extension capabilities.
- The corresponding agent/CLI/SDK/example tests.

This item provides only the buffered control-plane request that
OAuth/direct-access needs; the provider's SSE is still implemented through the
approved `runtime-provider` stream function and the existing Cadr-AI provider
stream, and no second transport is built. No new third-party dependency, no
modification of `src/cadr-ai`, and nothing enters the ASDF closure.

### 4.3 Credentials, default behavior and gates

- When it is not called there is zero network, zero new threads and zero
  observable change; when the host has not injected it, unavailable is reported
  explicitly.
- Redirect, abort, timeout and non-2xx all return/signal a stable
  extension-level condition; conditions, logs, notices and wire fixtures must not
  contain the Authorization, the access token, the refresh secret or the body.
- Red tests against a temporary HTTP server cover the JSON/form body, the
  headers/status/bytes, timeout, abort, concurrent session isolation and the
  reload stale API; the OAuth tests use network stubs and a temporary auth store.
- Both providers go through the existing auth store, refresh lock and atomic
  write; reload removes the provider projection but does not delete the
  credential; the `src/cadr-ai` global registry is not written.

### 4.4 Alternatives, freeze and rollback

- Exporting/modifying the Cadr-AI transport: it violates this round's complete
  freeze of `src/cadr-ai`.
- A `curl` subprocess: the host dependency, the token exposure surface and the
  cancellation semantics are all worse than the existing transport.
- Writing a special case for each of the two examples: it is not an extension
  API, and subsequent providers would still be unportable.
- Making HTTP a default agent tool: it would pollute the default YOLO tool set,
  and the baseline has no such mechanism.

Rollback deletes the host callback and the public wrapper; the path that does not
call it has no persistent state.

## 5. Blocked examples, adjudication items and resumption order

The 5 gaps at the time of approval (all now closed):

| Baseline file | gap | Corresponding adjudication |
|---|---|---|
| `custom-compaction.ts` | `:compaction-lifecycle-dispatch` | F |
| `prompt-customizer.ts` | `:system-prompt-options-event-payload` | G |
| `custom-provider-anthropic/index.ts` | `:extension-http-runtime` | H |
| `custom-provider-gitlab-duo/index.ts` | `:extension-http-runtime` | H |
| `custom-provider-gitlab-duo/test.ts` | `:extension-http-runtime` | H |

User adjudication:

1. **F (unfreeze the lifecycle dispatch of `src/cadr-agent/compaction.lisp`): approved.**
2. **G (unfreeze storing the agent prompt-options and the two-value return in CLI/SDK): approved.**
3. **H (add a session-local extension HTTP control-plane seam): approved.**

The three items have already completed the 5 examples in the order F→G→H; the extension export
SHA, architecture, README, source-parity and parity-map are synchronized with the
implementation commit, after which Goal 12 Part D begins. What F/G/H fill in are
capabilities the fixed baseline already has; they are not listed as deliberate
additions relative to the baseline.
