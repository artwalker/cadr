# Goal 12 example-driven extension API gap proposal

Status: **19 项能力 and supplementary items A/B/C/D/E were approved by the user
item by item on 2026-08-02; the minimal supplementary file surface of
`docs/proposals/goal-v12-api-scope-amendment.md` and
`docs/proposals/goal-v12-api-scope-amendment-2.md` takes effect along with them.**

Fixed baseline:
`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`
(`v0.83.0-38-g74caa2649`). Every baseline `file:line` in this document refers to
that commit.

## 1. Conclusion and boundaries

After Goal 12 reviewed the fixed baseline's 99 runnable examples file by file,
17 can be ported with functional equivalence inside the currently frozen API and
82 hit at least one real gap. `examples/manifest.sexp` is the only
classification source;
`GOAL12-EXAMPLE-MANIFEST-COVERS-EVERY-BASELINE-SOURCE-EXACTLY-ONCE` locks 99/99,
no duplicates, no omissions.

This proposal converges the 42 mechanical gap ids into 19 independently
adjudicable unfreeze items. The convergence principle is that one runtime
contract is unfrozen only once, and that one set of CLOS/bridge changes is not
split into pseudo-independent options. Each item aligns only with capabilities
that already exist in the fixed baseline and are really called by an example; no
security, approval, orchestration or policy mechanism that the baseline does not
have is added. Functional equivalence allows Lisp naming and data representation
to differ, but using internal symbols, weakened return values or an approximated
UI in place of the public contract is forbidden.

This proposal itself does not authorize third-party dependencies. Items 11–14
concern, respectively, extension-local dependencies, Gondolin, the sandbox
runtime and WASM; even if a capability item is approved, before any concrete
dependency is introduced the complete closure, the pinned versions / archive
hashes and a build-isolation audit must still be submitted first, and dependency
authorization must then be obtained separately.

## 2. Current freeze anchors and common gates

The objects work starts from (the `HEAD` when this proposal was generated):

| Path | Git object ID |
|---|---|
| `src/cadr-agent/extensions.lisp` | `2ecd00a85c043193e35d5603015376564d460f2c` |
| `src/cadr-agent/package.lisp` | `bcd6088ffd8f8590eb4203bd5171803a6ebf965e` |
| `src/cadr-cli/extensions.lisp` | `6b6acfc13bf0ed416b508f9cffa850891a539b94` |
| `src/cadr-cli/tui.lisp` | `9c6d20fc7ae5e722eacbfd2e5d9eeba4883d1600` |
| `src/cadr-tui/composition.lisp` | `e3c7ad70a5b79060138ddf476cf76f56c4bf1d33` |
| `src/cadr-tui/package.lisp` | `60dc2a97506965d46a6b47003f6c0c8737d360d8` |
| `src/cadr-cli/sdk-services.lisp` | `9e369938415a283ff1a6a12bb52806d08ff89305` |
| `src/cadr-cli/package.lisp` | `18b6bc0effad8cc57f159d44c694718618c1f7e4` |

The current extension export SHA-256 continues to be the one registered in
architecture, `bb4665245ef9df19b274535071fcc5f6e56c79ab29db2152cd41afaa4df3b1e0`.

If implementation is approved, the common gates for every item are:

1. First add a red test that reproduces the corresponding example's contract; the
   old extension compatibility fixtures, the 34-event set, the old macro
   lambda lists and the old payload/handler ordering are all verbatim unchanged.
2. In print/json/rpc/TUI the default paths that do not use the new capability are
   verbatim unchanged; the full-screen, 15-overlay, payload and wire fixtures
   must not be compared after normalization.
3. Every approved example must have load/registration/edge-case behavior tests;
   only a genuinely runnable Lisp file may change a ledger verdict to `已实现`.
4. At closeout, recompute the per-path object IDs, the extension export SHA, the
   event-set hash and the wire fixture hash, synchronize architecture, README,
   source-parity and parity-map, and then freeze again.
5. If any implementation needs to go beyond the minimal file surface listed for
   that item, add a dependency or change observable behavior that is not listed,
   it is immediately blocked; the surface must not be widened along the way.

## 3. Item-by-item proposal

### 1. UI availability determination (`:has-ui-context`)

- **Exact requirement**: expose a read-only `extension-context-has-ui-p`, true
  for TUI/RPC and false for print/json; kept separate from `mode`, so that an
  extension does not guess for itself whether a given mode has a dialog-capable
  UI.
- **Baseline evidence**: `packages/coding-agent/src/core/extensions/types.ts:307-314,528-535`;
  `auto-commit-on-exit.ts:41-47`, `permission-gate.ts:20-27`,
  `rpc-demo.ts:53-72`. `rpc-extension-ui.ts:255-263` explicitly loads rpc-demo,
  so that standalone client example is transitively blocked by the same `hasUI`
  gap rather than calling `hasUI` itself.
- **Examples involved**: auto-commit-on-exit, confirm-destructive,
  dirty-repo-guard, file-trigger, git-checkpoint, git-merge-and-resolve,
  inline-bash, permission-gate, project-trust, protected-paths, rpc-demo,
  widget-placement, rpc-extension-ui.
- **Non-example impact**: extensions avoid popping up UI in non-interactive
  modes; the core security model is not changed.
- **Minimal unfreeze**: `src/cadr-agent/extensions.lisp`, `package.lisp` and the
  per-mode context binding tests; no dependencies.
- **Alternatives considered and rejected**: letting the extension derive it from
  `mode` would duplicate host policy, and would drift as soon as modes are added
  or removed in future; returning whether the UI function is empty in turn
  treats an implementation detail as the contract.
- **Freeze / rollback**: only one accessor is added; rollback deletes the
  accessor and the examples, and the old context is unchanged.

### 2. Full custom component and overlay (`:custom-ui-runtime`, `:overlay-options`, `:overlay-handle`)

- **Exact requirement**: the `custom` factory receives TUI, Theme, Keybindings
  and done; it accepts a synchronous or asynchronous Component; it supports
  inline/overlay, all of `OverlayOptions`, dynamic options,
  `OverlayHandle.setHidden()/isHidden()`, focus/nonCapturing, dispose and requestRender.
- **Baseline evidence**: `types.ts:196-213`; `packages/tui/src/tui.ts:126-183`;
  `overlay-qa-tests.ts:31-302,939-1314`, `overlay-test.ts:15-31`.
- **Examples involved**: doom-component/index, handoff, interactive-shell,
  overlay-qa-tests, overlay-test, plan-mode/index, preset, qna, question,
  questionnaire, snake, space-invaders, summarize, tic-tac-toe, todo, tools.
- **Non-example impact**: arbitrary custom UI for interactive extensions;
  RPC/print/json continue to have no component runtime.
- **Minimal unfreeze**: `src/cadr-agent/extensions.lisp/package.lisp`,
  `src/cadr-cli/extensions.lisp/tui.lisp`, `src/cadr-tui/composition.lisp/package.lisp`.
  Reuse the C1 component/root/overlay protocol; do not build a second component
  model.
- **Alternatives considered and rejected**: the current `custom` passes only
  `done`, ignores the overlay arguments and renders the value into lines, and
  cannot express input, animation, focus or dispose; assembling an approximation
  out of select-list is not equivalent.
- **Freeze / rollback**: the new factory/overlay path and the old simple factory
  adapter are layered separately; deleting the new path restores the old
  behavior, and the old extension tests stay as they are.

### 3. TUI composition control plane (`:footer-component`, `:header-component`, `:editor-component`, `:working-indicator`, `:working-message`, `:working-state`, `:hidden-thinking-label`, `:theme-access`)

- **Exact requirement**: fill in `setFooter`, `setHeader`,
  `setEditorComponent/getEditorComponent`, `setWorkingVisible`,
  `setWorkingMessage`, `setWorkingIndicator`, `setHiddenThinkingLabel` and a full
  Theme on which fg/bg/bold/italic can be called; the restore-default semantics
  and the component dispose timing match the baseline.
- **Baseline evidence**: `types.ts:115-190,249-275`;
  `border-status-editor.ts:107-148`, `custom-footer.ts:12-59`,
  `working-indicator.ts:20-98`, `hidden-thinking-label.ts:21-50`.
- **Examples involved**: border-status-editor, custom-footer, custom-header,
  modal-editor, rainbow-editor, working-indicator, working-message-test,
  hidden-thinking-label, status-line.
- **Non-example impact**: extensions customize the footer/header/editor/streaming
  loader; the default components are unchanged.
- **Minimal unfreeze**: the file surface of item 2, plus
  `src/cadr-cli/interactive-components.lisp`; reuse FooterDataProvider and the C1
  composition.
- **Alternatives considered and rejected**: `setStatus`/widget cannot replace the
  component lifecycle; the current theme summary plist cannot replace the
  baseline Theme styling API.
- **Freeze / rollback**: each kind of replacement keeps its own default factory;
  clearing the extension restores the defaults.

### 4. Model, context, thinking, system prompt and session replacement (`:context-usage`, `:thinking-control`, `:model-registry-context`, `:model-control`, `:new-session-action`, `:system-prompt-access`, `:system-prompt-options`)

- **Exact requirement**: expose the current model / scoped models, ModelRegistry
  auth/model lookup, `getContextUsage`, get/set thinking, get/set model,
  `getSystemPrompt`, the command-only `getSystemPromptOptions`, and the
  stale-safe replacement of `newSession(...withSession...)`.
- **Baseline evidence**: `types.ts:315-392,1331-1353`; `agent-session.ts:2393-2439`;
  `border-status-editor.ts:51-53,130-133`, `handoff.ts:89-191`,
  `prompt-customizer.ts:88-91`, `system-prompt-header.ts:8-16`.
- **Examples involved**: border-status-editor, trigger-compact,
  custom-compaction, handoff, preset, qna, summarize, prompt-customizer,
  system-prompt-header.
- **Non-example impact**: model/session control extensions; when a session is
  going to be changed, the existing before/after lifecycle and the new
  withSession context must be followed.
- **Minimal unfreeze**: `src/cadr-agent/extensions.lisp/package.lisp`,
  `src/cadr-cli/extensions.lisp`, and the existing CLI files where the
  session/model bridge lives; `src/cadr-ai` stays frozen, and if that cannot be
  achieved it is immediately blocked.
- **Alternatives considered and rejected**: reading from private agent/session
  slots bypasses provider auth, the capability clamp and stale replacement;
  hand-writing the prompt construction would deviate from the baseline.
- **Freeze / rollback**: only context/API actions are added; the old
  agent/session public behavior is unchanged.

### 5. Command/tool introspection and the extension event bus (`:command-introspection`, `:tool-introspection`, `:extension-event-bus`)

- **Exact requirement**: expose `getCommands`, `getAllTools` (including source,
  parameters and guidelines), active tools get/set, and a host-scoped
  `events.emit/on`; reload cleans up subscriptions.
- **Baseline evidence**: `types.ts:1331-1340,1430,1563-1571`;
  `packages/coding-agent/src/core/event-bus.ts:3-25`; `commands.ts:20-60`,
  `tools.ts:19-64`, `event-bus.ts:12-43`.
- **Examples involved**: commands, tools, preset, event-bus.
- **Non-example impact**: tool-set management and extension-to-extension
  communication; the event bus does not enter the agent-event/JSON/RPC wire.
- **Minimal unfreeze**: `src/cadr-agent/extensions.lisp/package.lisp` and the CLI
  host binding; the C2 `event-bus` may be reused, but CLI-private objects must
  not be exported.
- **Alternatives considered and rejected**: reading the snapshot's private struct
  would freeze the implementation layout; passing a lifecycle event off as an
  extension-to-extension channel would pollute the event semantics.
- **Freeze / rollback**: a read-only snapshot/action and a separate bus are
  added; after deletion the old registry is unchanged.

### 6. Full runtime for autocomplete and message/entry renderers (`:autocomplete-provider-runtime`, `:message-renderer-runtime`, `:entry-renderer-runtime`)

- **Exact requirement**: the autocomplete factory receives the complete current
  provider and the signal/cwd/result contract is aligned; the message renderer
  receives `(message, expanded/outputPad, theme)` and the entry renderer receives
  `(entry, expanded, theme)`, they return a real Component and have
  invalidate/dispose.
- **Baseline evidence**: `types.ts:124-125,225,1281-1291`;
  `github-issue-autocomplete.ts:89-119`, `message-renderer.ts:15-33`,
  `entry-renderer.ts:20-39`.
- **Examples involved**: github-issue-autocomplete, message-renderer,
  entry-renderer.
- **Non-example impact**: extension completion and custom transcript/session
  entries.
- **Minimal unfreeze**: `src/cadr-agent/extensions.lisp/package.lisp`,
  `src/cadr-cli/tui.lisp`, reusing the C1 Component; no dependencies.
- **Alternatives considered and rejected**: the current renderer passes only two
  Lisp values and ends up degenerating into a line list; it lacks the theme and
  the component lifecycle, and cannot be called equivalent.
- **Freeze / rollback**: the new renderer signature is added through a separate
  macro/adapter, without changing the existing macro lambda list.

### 7. Tool metadata, render contract and terminate (`:tool-definition-metadata`, `:tool-render-contract`, `:tool-termination`)

- **Exact requirement**: tool definitions support `label`, `promptSnippet`,
  `promptGuidelines`, `constrainedSampling`, `renderShell` and prepareArguments;
  the renderer receives the complete Theme, ToolRenderContext and the
  partial/expanded/error states; the tool result supports the baseline's
  `terminate: true`.
- **Baseline evidence**: `types.ts:446-501`; `agent-session.ts:2492-2500`;
  `structured-output.ts:20-65`, `built-in-tool-renderer.ts:31-249`,
  `minimal-mode.ts:65-374`.
- **Examples involved**: dynamic-tools, hello, kimi-deferred-tools,
  reload-runtime, structured-output, built-in-tool-renderer, minimal-mode.
- **Non-example impact**: the tool list in the model's system prompt, the TUI
  tool block and agent run termination.
- **Minimal unfreeze**: `src/cadr-agent/extensions.lisp/package.lisp`, the tool
  adapter, `src/cadr-cli/tui.lisp`; the `cadr-ai:tool` wire is not changed, and
  if the metadata cannot stay in the extension definition layer it is blocked.
- **Alternatives considered and rejected**: stuffing the label into the
  description would pollute the bytes fed to the model; the separate
  `define-tool-renderer` currently lacks the complete render context; treating
  terminate as an error would change the semantics.
- **Freeze / rollback**: the metadata stays in the bundle, and the defaults of
  the old define-tool keep their original output; terminate defaults to nil.

### 8. Tool execution control plane (`:tool-execution-context`, `:cancellation-signal-construction`)

- **Exact requirement**: the extension tool handler receives the call-id, the
  arguments, a signal it can abort on its own initiative, a partial `onUpdate`
  and the complete ExtensionContext; expose the built-in tool factory
  operations/spawnHook seam; add `ctx.shutdown()`; allow manual cancellation
  signal construction/abort.
- **Baseline evidence**: `types.ts:300-346,476-486`;
  `bash-spawn-hook.ts:14-28`, `shutdown-command.ts:15-60`, `ssh.ts:111-205`,
  `timed-confirm.ts:45-65`.
- **Examples involved**: bash-spawn-hook, gondolin, sandbox, shutdown-command,
  ssh, subagent/index, timed-confirm.
- **Non-example impact**: cancelling long-running tools, progress updates,
  remote/replacement backends, graceful shutdown.
- **Minimal unfreeze**: `src/cadr-agent/extensions.lisp/package.lisp/execution-env.lisp`,
  `src/cadr-cli/extensions.lisp` and the existing tool factories; the core
  default tool execution results are not changed.
- **Alternatives considered and rejected**: polling
  `extension-cancellation-aborted-p` without being able to construct/abort is not
  enough; having the extension call the private CLI tool handler directly has no
  update/context and bypasses the registry.
- **Freeze / rollback**: the new handler adapter and factory seam have a default
  old adapter; the old three-argument handler compatibility gate must be kept.

### 9. File mutation queue and truncation utilities (`:file-mutation-queue`, `:truncation-utilities`)

- **Exact requirement**: make the per-path serialized mutation queue and the
  complete result contract of truncate head/tail/line public utilities for
  extensions; the UTF-8/line/byte accounting is the same as for the built-in
  tools.
- **Baseline evidence**: `packages/coding-agent/src/core/tools/file-mutation-queue.ts:1-43`,
  `truncate.ts:1-222`; `tool-override.ts:24,54-66`, `truncated-tool.ts:24-25,91-121`.
- **Examples involved**: tool-override, truncated-tool, subagent/index.
- **Non-example impact**: avoiding lost updates when an extension and a built-in
  tool write the same path concurrently; consistent truncation of large output.
- **Minimal unfreeze**: export/move the general implementation of the existing
  `src/cadr-cli/tools/path.lisp` and `truncation.lisp` to a shared layer that
  does not depend on the CLI, with the package/ASD adjusted accordingly.
- **Alternatives considered and rejected**: each example building its own mutex
  cannot share the queue with the built-in tools; replicating the truncation
  algorithm would produce numeric accounting drift once again.
- **Freeze / rollback**: the built-in tools are changed to call the same public
  utility, and the output fixtures must be verbatim unchanged.

### 10. Extension provider OAuth (`:extension-provider-oauth`)

- **Exact requirement**: a provider registered by an extension may supply
  login/refresh/getApiKey, auth prompts, model projection and a custom stream; it
  enters `/login`, the credential store, the refresh lock, the model catalog and
  the default route, and the provider identity is consistent throughout.
- **Baseline evidence**: `types.ts:1364-1475`;
  `custom-provider-anthropic/index.ts:574-610`,
  `custom-provider-gitlab-duo/index.ts:381-404`, and `test.ts:19-82` in the same
  directory.
- **Examples involved**: custom-provider-anthropic,
  custom-provider-gitlab-duo/index, test.
- **Non-example impact**: third-party subscription / enterprise SSO providers;
  the OAuth credential security boundary.
- **Minimal unfreeze**: `src/cadr-agent/extensions.lisp/package.lisp`,
  `src/cadr-cli/extensions.lisp/model-services.lisp`; adapting the existing
  `runtime-provider` callbacks takes priority. If `src/cadr-ai` must be modified,
  it is immediately blocked, and a precise four-layer contract proposal is
  submitted separately.
- **Alternatives considered and rejected**: registering only a static
  base-url/models is a capability that already exists and cannot demonstrate
  login, refresh or a custom stream; letting the example write auth.json directly
  bypasses the store/lock and is high-risk.
- **Freeze / rollback**: the provider overlay is replaced atomically along with
  the bundle reload; after uninstall the auth method/models are removed, but
  already-stored user credentials are not deleted.

### 11. Extension-local dependency resolution (`:extension-dependency-loader`)

- **Exact requirement**: a directory extension may declare and load an ASDF
  system inside its own directory, and the resolution scope does not pollute the
  Cadr global build; errors include the extension path and the system name;
  reload is repeatable.
- **Baseline evidence**: `with-deps/index.ts:1-31` and `package.json:1-22` in the
  same directory; the baseline resolves the pinned `ms@2.1.3` through the
  extension's own `node_modules`.
- **Examples involved**: with-deps/index.
- **Non-example impact**: every third-party extension that has Lisp dependencies
  of its own.
- **Minimal unfreeze**: `src/cadr-cli/extensions.lisp`, a new extension-local
  ASDF source-registry helper and tests. The example may verify the mechanism
  with an in-repo local duration ASDF system; no automatic network access, no
  automatic Quickload of unauthorized libraries, and the build image does not
  bake in user extensions.
- **Alternatives considered and rejected**: requiring every extension dependency
  to be added to the main Cadr ASDF would pollute the release closure; automatic
  Quicklisp install introduces supply-chain and non-reproducible behavior.
- **Freeze / rollback**: with no declaration the loader path is verbatim
  unchanged; deleting the helper restores the current state.

### 12. Gondolin micro-VM (`:gondolin-dependency`)

- **Exact requirement**: provide an equivalent VM filesystem/process backend,
  `/workspace` write-through, isolation of the other paths,
  cancellation/truncation and read/write/edit/find/grep/ls/bash routing.
- **Baseline evidence**: `gondolin/index.ts:1-531`; `package.json:1-19` pins
  `@earendil-works/gondolin@0.12.0` and requires QEMU.
- **Examples involved**: gondolin/index.
- **Non-example impact**: a strongly isolated tool backend; this is not Cadr's
  default security boundary.
- **Minimal unfreeze**: the tool backend seam of items 8/9 plus a separate
  example adapter; **the concrete Lisp/helper dependency is not yet
  authorized**, and the candidate artifact, closure, hash and QEMU platform
  matrix must be given first.
- **Alternatives considered and rejected**: calling an ordinary
  subprocess/container Gondolin is not equivalent; bringing the Node runtime back
  into the native image violates the current build boundary.
- **Freeze / rollback**: extension opt-in, and the default tools / README
  security stance are unchanged; uninstalling is the rollback.

### 13. OS sandbox runtime (`:sandbox-runtime-dependency`)

- **Exact requirement**: implement an equivalent of the macOS
  sandbox-exec/Linux bubblewrap network/filesystem policy, config merge,
  user-bash and bash override, and reset lifecycle.
- **Baseline evidence**: `sandbox/index.ts:1-321`; `package.json:1-19` pins
  `@anthropic-ai/sandbox-runtime@0.0.26`, and Linux additionally requires
  bubblewrap/socat/ripgrep.
- **Examples involved**: sandbox/index.
- **Non-example impact**: an OS sandbox when the user explicitly installs the
  extension; the core still defaults to YOLO.
- **Minimal unfreeze**: the backend seam of item 8 and a separate example
  adapter; **the concrete dependency is not authorized**, and before
  implementation the closure, command discovery, policy wire and platform
  degradation behavior must be audited.
- **Alternatives considered and rejected**: reusing the approval hook is not
  isolation; filtering command strings alone is not an OS sandbox.
- **Freeze / rollback**: entirely opt-in; deleting the extension restores the
  default direct execution, and nothing is added to the core policy.

### 14. DOOM WASM runtime (`:doom-runtime`)

- **Exact requirement**: load an equivalent of the in-repo `doom.js/doom.wasm`
  module, mount the WAD, tick, framebuffer ARGB→RGBA, key injection and the
  35 FPS overlay lifecycle.
- **Baseline evidence**: `doom-overlay/doom-engine.ts:1-173`,
  `doom-component.ts:1-132`, `index.ts:22-70`; the build artifact is at
  `doom-overlay/doom/build/doom.wasm`.
- **Examples involved**: doom-engine, doom-component, doom-overlay/index.
- **Non-example impact**: none; purely example/component stress verification.
- **Minimal unfreeze**: the overlay of item 2, plus a separate WASM adapter;
  **a Common Lisp WASM runtime is not yet authorized**, and before
  implementation the implementation, closure, hash and native image packaging
  strategy must be pinned.
- **Alternatives considered and rejected**: a static fake frame or an external
  screenshot is not playable DOOM; going back to executing doom.js with Node
  would introduce a Node runtime into the native release.
- **Freeze / rollback**: it exists only in the example, and deleting the
  directory suffices; the core contains no game logic.

### 15. SDK session facade (`:sdk-session-facade`)

- **Exact requirement**: expose an entry point equivalent to
  `create-agent-session`, composing the
  cwd/model/tools/resource-loader/session-manager/settings/auth/extension
  factories and returning the session and the model-fallback message; support
  prompt/subscribe/dispose.
- **Baseline evidence**: `packages/coding-agent/src/core/sdk.ts:1-398`, entry
  point at `:169`; `sdk/01-minimal.ts:8-15`, `05-tools.ts:13-48`,
  `11-sessions.ts:7-45`.
- **Examples involved**: all of SDK 01–13.
- **Non-example impact**: embedding Cadr as a library without going through the
  CLI main.
- **Minimal unfreeze**: add `src/cadr-cli/sdk.lisp`, reusing the existing
  agent/session/tools/extension manager; `src/cadr-cli/package.lisp`,
  `cadr-cli.asd`.
- **Alternatives considered and rejected**: calling `main` / an RPC subprocess is
  not an in-process SDK; letting the examples copy the CLI bootstrap would
  produce a second set of defaults.
- **Freeze / rollback**: the new facade is not wired into the CLI default path;
  deleting the new module is the rollback.

### 16. SDK resource loader (`:sdk-resource-loader`)

- **Exact requirement**: expose an object equivalent to DefaultResourceLoader,
  supporting system prompt override/append, skills, extensions, context files,
  prompt templates, reload and diagnostics.
- **Baseline evidence**: `resource-loader.ts:195-492`;
  `sdk/03-custom-prompt.ts:18-63`, `04-skills.ts:27-55`,
  `06-extensions.ts:26-99`, `07-context-files.ts:15-47`,
  `08-prompt-templates.ts:29-51`.
- **Examples involved**: SDK 03, 04, 06, 07, 08, 12.
- **Non-example impact**: the embedder's control over resource discovery / the
  trust boundary.
- **Minimal unfreeze**: wrap the existing `resource-loader`/extension manager in
  a CLOS facade; `src/cadr-cli/sdk-services.lisp/package.lisp`, no new
  dependencies.
- **Alternatives considered and rejected**: passing a handful of lists directly
  cannot preserve reload, diagnostics and source info.
- **Freeze / rollback**: only the facade is added; the CLI continues to call the
  existing loader.

### 17. SDK model runtime and auth override (`:sdk-model-runtime`)

- **Exact requirement**: expose an API equivalent to ModelRuntime: catalog
  lookup, custom provider/model, api-key/OAuth/auth overrides,
  check/resolve/login, refresh and per-session visibility.
- **Baseline evidence**: `model-runtime.ts:96-406`; `sdk/02-custom-model.ts:7-38`,
  `09-api-keys-and-oauth.ts:7-34`, `12-full-control.ts:25-74`.
- **Examples involved**: SDK 02, 09, 12.
- **Non-example impact**: the embedder's credentials and custom models; a highly
  sensitive surface.
- **Minimal unfreeze**: a public facade in
  `src/cadr-cli/sdk-services.lisp/package.lisp` over the existing
  `cadr-ai:models-runtime`; `src/cadr-ai` stays frozen, otherwise blocked.
- **Alternatives considered and rejected**: having the examples read auth.json
  directly would bypass the mode, the refresh lock and the atomic write.
- **Freeze / rollback**: no new credential format is added; deleting the facade
  does not change the storage.

### 18. SDK settings manager (`:sdk-settings-manager`)

- **Exact requirement**: expose the disk/in-memory SettingsManager, the override
  precedence, and reads and writes of default thinking/tools/compaction/retry and
  the like, injectable into create-agent-session.
- **Baseline evidence**: `settings-manager.ts:279-1127`; `sdk/10-settings.ts:7-53`.
- **Examples involved**: SDK 10.
- **Non-example impact**: the embedder's persistent/temporary configuration,
  without changing the CLI configuration precedence.
- **Minimal unfreeze**: a CLOS facade wrapping the existing CLI settings
  services; package/ASD, no dependencies.
- **Alternatives considered and rejected**: accepting only a plist lacks the disk
  merge, the scope and the write-back; letting the embedder modify the global
  settings breaks test isolation.
- **Freeze / rollback**: the in-memory and disk backends are kept separate; the
  CLI default backend is unchanged.

### 19. Replaceable AgentSessionRuntime (`:sdk-session-runtime`)

- **Exact requirement**: expose the services→session factory, the runtime
  wrapper, bind extensions, atomic replace/newSession, diagnostics and disposal
  of the old session; the caller may replace the creation strategy.
- **Baseline evidence**: `agent-session-services.ts:134-219`,
  `agent-session-runtime.ts:74-441`; `sdk/13-session-runtime.ts:12-67`.
- **Examples involved**: SDK 13.
- **Non-example impact**: hot-swapping sessions in a long-lived embedding
  process; an incorrect implementation would leak threads / the old extension
  context.
- **Minimal unfreeze**: the facade of item 15 plus a CLOS runtime protocol;
  reuse the existing stale-context, session lifecycle and extension attachment
  generation.
- **Alternatives considered and rejected**: replacing the session slot in place
  on the same Agent would bypass the shutdown/start hooks; starting a new CLI
  process does not have in-process replacement.
- **Freeze / rollback**: the runtime is an opt-in SDK object; when the CLI does
  not instantiate it, behavior is unchanged.

## 4. Complete mapping from the 42 mechanical gap ids to the adjudication items

| Adjudication item | gap ids |
|---:|---|
| 1 | `:has-ui-context` |
| 2 | `:custom-ui-runtime`, `:overlay-options`, `:overlay-handle` |
| 3 | `:footer-component`, `:header-component`, `:editor-component`, `:working-indicator`, `:working-message`, `:working-state`, `:hidden-thinking-label`, `:theme-access` |
| 4 | `:context-usage`, `:thinking-control`, `:model-registry-context`, `:model-control`, `:new-session-action`, `:system-prompt-access`, `:system-prompt-options` |
| 5 | `:command-introspection`, `:tool-introspection`, `:extension-event-bus` |
| 6 | `:autocomplete-provider-runtime`, `:message-renderer-runtime`, `:entry-renderer-runtime` |
| 7 | `:tool-definition-metadata`, `:tool-render-contract`, `:tool-termination` |
| 8 | `:tool-execution-context`, `:cancellation-signal-construction` |
| 9 | `:file-mutation-queue`, `:truncation-utilities` |
| 10 | `:extension-provider-oauth` |
| 11 | `:extension-dependency-loader` |
| 12 | `:gondolin-dependency` |
| 13 | `:sandbox-runtime-dependency` |
| 14 | `:doom-runtime` |
| 15 | `:sdk-session-facade` |
| 16 | `:sdk-resource-loader` |
| 17 | `:sdk-model-runtime` |
| 18 | `:sdk-settings-manager` |
| 19 | `:sdk-session-runtime` |

机械校验 must prove that every `:gap` in the manifest has at least one id, that
every id appears in exactly one adjudication item of the table above, and that
all 42 ids are defined. The 82 gap examples are still kept row by row in
`docs/source-parity.md`; before they are approved and really ported, their
verdict must not be changed early.

## 5. Recommended adjudication order

Adjudication and implementation are recommended in the order 1→10, 15→19, 11→14.
The first 10 items complete the extension runtime and 15–19 complete the SDK
facade with no new dependencies; 11–14 handle the ecosystem / external runtimes
last, to avoid dependency questions obscuring the core API gaps. Any single item
may be rejected or deferred on its own; the examples blocked by it continue to be
honestly recorded as `缺失`.

The user's adjudication may be written directly in the form "1 approve /
2 defer / …". A capability approval for items 11–14 is not a dependency
approval; without a subsequent dependency-closure adjudication they must not be
implemented.
