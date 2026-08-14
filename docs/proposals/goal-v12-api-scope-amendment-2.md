# Goal 12 second supplementary unfreeze proposal for the extension API implementation surface

Status: **D/E 已于 2026-08-02 获得用户批准, implemented as written.**

Fixed baseline:
`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`
(`v0.83.0-38-g74caa2649`). Every baseline `file:line` in this document refers to
that commit.

## 1. Why work stopped again

After the user approved supplementary items A/B/C, A/B were implemented within
the approved file surface and passed their targeted gates; items 9 and 11 and
SDK 15–19 have also produced uncommitted increments. The call-chain audit before
continuing work confirmed, once again, two implementation surfaces that the
original proposal had failed to list. Both lie on the unavoidable path of already-approved
capabilities and are not a widening of functionality; but the general constraint
states explicitly that any boundary crossing must immediately be blocked, so no
global function replacement, no pollution of the Cadr-AI registry and no
weakening of the contract was used to get around it.

This proposal requests only the two minimal additions D/E. The requirements and
adjudications of A/B/C are unchanged, and `src/cadr-ai` remains completely
frozen; the current uncommitted implementation is kept in the working tree, and
production code is not modified further before approval.

## 2. Supplementary item D: the complete autocomplete provider must enter the TUI provider/editor protocol

### 2.1 Exact requirement and baseline evidence

The already-approved item 6 requires the extension autocomplete factory to
receive the complete current provider, and to keep `getSuggestions`,
`applyCompletion`, `shouldTriggerFileCompletion`, the request signal, cwd and the
result contract. The baseline contract is at:

- `packages/tui/src/autocomplete.ts:241-270`: the three methods of
  `AutocompleteProvider` and the `AbortSignal`/force arguments;
- `packages/tui/src/components/editor.ts:2165-2217,2242-2312`: the editor creates
  a controller for every request, cancels the old request, rejects aborted/stale
  results, and applies the completion through the provider;
- `packages/coding-agent/examples/extensions/github-issue-autocomplete.ts:91-127`: the example wraps
  the current provider, and delegates to the original provider when the condition
  does not match or the request is cancelled.

Cadr's current blocking points are:

- the provider at `src/cadr-tui/autocomplete.lisp:18-27` has only
  commands/base-path/fd-path;
- the suggestions/apply at `src/cadr-tui/autocomplete.lisp:429-472,474-524` are
  fixed ordinary functions that a replacement struct cannot override;
- `src/cadr-tui/editor.lisp:935-963,1072-1105` calls those functions directly,
  with no request-local cancellation/stale-result seam.

Changing only the `src/cadr-cli/tui.lisp` listed in the original proposal cannot
express this contract. Replacing the global functions through `setf symbol-function`
would pollute across editors and change the default path, and is explicitly
rejected.

### 2.2 Minimal supplementary unfreeze surface

- `src/cadr-tui/autocomplete.lisp`: add optional callbacks to the provider; when
  they default to NIL the existing fixed implementation is still used; expose a
  unified dispatch, without changing the existing constructor defaults.
- `src/cadr-tui/editor.lisp`: add a request-local cancellation/stale generation;
  only a custom async provider uses it, and when the new capability is not
  registered the existing synchronous path is used.
- `src/cadr-tui/package.lisp` and the corresponding TUI/CLI tests: export the
  necessary additive constructor/dispatch surface.

The agent/CLI file surface of the original item 6 is unchanged; no dependencies,
and `src/cadr-ai` is not modified.

### 2.3 Default behavior and gates

- With no extension provider, the existing provider struct, the space/delete
  trigger semantics, the suggestions, the apply results and the full-screen
  snapshots are byte-for-byte unchanged.
- Red-test coverage: the wrapper matching, delegating to current, force/trigger,
  cwd, before cancellation / during the request / after completion, an old
  request arriving late, the row/column position of apply, and two editors in
  parallel not polluting each other.
- The existing gates for space, consecutive spaces, an empty prefix, `/`, `@`,
  path fragments and deleting to empty stay all-green.

### 2.4 Alternatives, freeze and rollback

- Supporting only a command argument completer: the GitHub issue example cannot
  run, and there is no signal / current provider contract.
- Merging the suggestions in advance in the CLI: it bypasses the editor's
  cancellation and stale gate.
- Dynamically replacing the global fdefinition: a hidden process-level side
  effect, and multiple sessions cannot be isolated.

Rollback deletes the optional callbacks/generation and the new adapter; the
default branch of the old provider keeps its original function body.

## 3. Supplementary item E: the extension OAuth provider must enter the provider source of the argument-less `/login`

### 3.1 Exact requirement and baseline evidence

The already-approved item 10 explicitly requires an extension provider to enter
the real `/login`. The baseline selector is constructed from the current
providers of the session `modelRuntime`, and not by reading only the static
built-ins:

- `packages/coding-agent/src/modes/interactive/interactive-mode.ts:4894-4924`
  enumerates the OAuth/API-key methods of the `modelRuntime` providers;
- `:2773-2774,4975-4986` in the same file makes the argument-less and the
  explicit `/login` share that runtime contract.

Cadr's current call chain is:

- `src/cadr-agent/extensions.lisp:1499-1535,2764-2768` puts only native providers
  into the extension snapshot;
- `src/cadr-cli/model-services.lisp:618-639` synchronizes to the session-local
  models runtime;
- the argument-less selector at `src/cadr-cli/tui.lisp:4134-4149`, and the
  `/login` autocomplete at `:2743-2750,3391-3393`, still hard-code
  `cadr-ai:list-provider-definitions`;
- `src/cadr-ai/registry.lisp:294-320` is the frozen global built-in registry, and
  must not be polluted by extensions.

Supplementary item C's conditional unfreeze of `tui.lisp` authorizes only the
OAuth prompt callback bridge. That bridge does indeed need to be enabled: the
Anthropic example asks for the authorization code after the URL
(`custom-provider-anthropic/index.ts:92-95`), and the GitLab example asks for the
callback URL (`custom-provider-gitlab-duo/index.ts:245-247`); the existing
one-way `auth-url` consumer is not enough. But it did not authorize injecting the
selector's provider source, so this item is requested separately.

### 3.2 Minimal supplementary unfreeze surface

- Explicitly allow `src/cadr-cli/tui.lisp` to add a `login-options-function`
  injection point, serving both the selector and the autocomplete; with no
  injection it continues to call the current built-in list.
- `src/cadr-cli/main.lisp` composes the built-in definitions with the current
  extension/model runtime providers, without writing to the global registry.
- `src/cadr-cli/model-services.lisp` projects, read-only, the id/name/auth-types
  of the runtime providers.

These three are completed together with the config/main prompt callback seam of
the already-approved C. There is no need to modify `interactive-services.lisp` or
`src/cadr-ai`.

### 3.3 Default behavior, credential discipline and gates

- With no extension OAuth, `/login openai`, `/login anthropic`, the argument-less
  selector, the autocomplete, the provider ordering, all copy and the
  full-screen snapshots are byte-for-byte unchanged.
- Only when an extension is loaded do the selector/autocomplete gain its methods;
  after a reload they disappear, but credentials already stored in the auth store
  are not deleted.
- A temporary auth store plus network stubs lock the identity, the default route
  and the same refresh lock / atomic write; logs, conditions, notices and the
  wire are all asserted to contain no token / refresh secret.
- The prompt callback uses the existing overlay/Input components: the worker
  waits on a condition variable, and cancellation returns NIL; the selector
  layout, the default entries and the copy are not changed.

### 3.4 Alternatives, freeze and rollback

- Writing the extension provider into `cadr-ai:*provider-definitions*`: it
  pollutes across sessions and violates the `src/cadr-ai` freeze.
- Supporting only `/login <id>`: the argument-less real user path would not be
  equivalent to the baseline.
- Letting the extension build its own command / write auth.json: it bypasses the
  unified auth store, the refresh lock and the atomic write.

Rollback deletes the provider-source injection and the runtime projection; the
path with no injection is still the original built-in call.

## 4. Adjudication and resumption order

Adjudication result:

1. **D (supplementary `autocomplete.lisp`/`editor.lisp` file surface for item 6): approved.**
2. **E (item 10 allowed to inject the provider source in `tui.lisp`): approved.**

Once both D and E are approved, the established order resumes: complete 1→10,
15→19, 11, 13→12→14, Part D. If either is not approved, the corresponding
examples continue to be honestly recorded as missing; the remaining already-approved
increments must not pass themselves off as completing that contract.
