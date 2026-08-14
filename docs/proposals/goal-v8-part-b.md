# GOAL v8 Part B four-item adjudication proposal

> Historical proposal: the `71efc6f0…` in this document is only the audit anchor
> as of Goal 8; from Goal 9 on, the current normative baseline is
> `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.

Status: **All four items were approved by the user item by item and completed per section 5; this document is retained as the authorization and baseline evidence.**

Fixed behavior baseline:
`71efc6f0c1909874ec8c944637a9ae7fc0e2d508`, checkout
`/tmp/cadr-parity-71efc6f0`. Every TypeScript `file:line` in this document refers to that commit.

## 0. Procedural boundary and increments already on the ledger

The Part B increments within the pre-authorized scope have already been split logically into five commits:

| Commit | Content | Pre-adjudicated boundary |
|---|---|---|
| `724494fd562d34097c225072ace81771311c58f4` | tests and fixtures | Goal 8 Part B; the six lifecycle events correspond to pre-adjudication item 0.5(3) |
| `36310bfb040674ef43dff421e4e537eb7471ebaa` | agent/session/resource/tool/input runtime | provider request hooks only under pre-adjudication item 0.5(3) |
| `267b215aa45e488053dd85330d8a9c1106553369` | CLI service primitives | provider lifecycle bridge only under pre-adjudication item 0.5(3) |
| `81b441aec12669ef368670f494a1b28697bb8193` | CLI-owned interactive controllers | did not modify `src/cadr-tui` production code |
| `d0a90f9e009aadcca4f3fb482596c21e4314308b` | REPL/RPC/TUI glue | startup lifecycle wiring only under pre-adjudication item 0.5(3) |

The provider request replacement under pre-adjudication item 0.5(3) adds three
public exports, so the claim that "the extension export SHA is still the Goal 7
frozen value" is wrong. Recomputed over the same sampling range as Goal 7:

```text
sed -n '/#:define-tool/,/#:make-extension-hook-result/p' \
  src/cadr-agent/package.lisp | sha256sum
e89a7f84962c539bfab1645df4867a8f3b587ae46201865abcf9d2b503dc068a  -
```

The Goal 7 original value
`cc8e7d180b5007cbf4daa66ff904f8c0714992df646211c232135500efd936e7`
is retained only as a historical anchor; the current anchor is
`e89a7f84962c539bfab1645df4867a8f3b587ae46201865abcf9d2b503dc068a`.
This SHA correction does not widen the permissions of the four subsequent items.

Hard constraints common to all:

1. All four items remain `M`/blocked, and the user must approve them item by
   item; approval of one of them must not be taken to imply approval of the
   others;
2. Only mechanisms that already exist in the fixed baseline are implemented; no
   security, approval, caching or abstraction that the baseline does not have is
   added;
3. Zero changes to existing extension macro signatures, existing event semantics
   and the stale-context rule;
4. A new third-party dependency must first obtain user authorization, and
   `docs/dependency-audit.md` and the README must be updated in step; adding
   first and ratifying afterwards is not permitted;
5. If the minimal implementation of an approved item exceeds the unfreeze surface
   listed in this document, go blocked again immediately;
6. The implementation order is fixed as tests first, minimal production
   implementation, full gates, logical commits, refreeze.

## 1. Adjudication item one: real image pixel decoding, conversion and scaling

### 1.1 Exact requirement

Fill in the whole-file semantics of
`packages/coding-agent/test/image-processing.test.ts`:

1. PNG keeps its original bytes when within the limit;
2. JPEG can be converted to PNG;
3. PNG/JPEG must read real pixels and apply EXIF orientation;
4. when the width/height are exceeded, scale proportionally; the baseline
   sampler is Lanczos3;
5. when the encoded size is exceeded, compare PNG/JPEG and compress in steps by
   JPEG quality `requested, 85, 70, 55, 40` and 0.75× dimensions;
6. if it is still over the limit down to `1x1`, return `nil`;
7. the worker is a Node/Bun concurrency implementation detail; Lisp may execute
   synchronously, but the output semantics must be identical.

### 1.2 Does the baseline really decode pixels

**Yes — the baseline really decodes and resamples pixels; it is in no way merely reading the dimension header.**

| Fact | Fixed baseline |
|---|---|
| `PhotonImage.new_from_byteslice(bytes)` decodes the input, applies EXIF orientation, then re-encodes PNG with `get_bytes()` | `packages/coding-agent/src/utils/image-convert.ts:4-23` |
| resize likewise calls `new_from_byteslice` first, then reads width and height from the already-decoded image | `packages/coding-agent/src/utils/image-resize-core.ts:59-80` |
| uses `photon.resize(..., SamplingFilter.Lanczos3)` to resample the pixels, and encodes PNG/JPEG from the resized image | `packages/coding-agent/src/utils/image-resize-core.ts:95-120` |
| tries JPEG quality and 0.75 dimension decrements in turn, until `1x1` or the byte limit is satisfied | `packages/coding-agent/src/utils/image-resize-core.ts:122-163` |
| when the worker fails, falls back to the same in-process pixel implementation | `packages/coding-agent/src/utils/image-resize.ts:78-109` |
| the tests require JPEG→PNG, not merely accepting the MIME/dimensions | `packages/coding-agent/test/image-processing.test.ts:29-49` |
| the tests require `100x100` to really shrink to no more than `50x50` | `packages/coding-agent/test/image-processing.test.ts:85-98` |
| the tests require the encoded bytes to get smaller, to return null when it cannot get down to 1 byte, and to accept JPEG input | `packages/coding-agent/test/image-processing.test.ts:100-139` |

The current cadr does pixel decoding for BMP only:

- `src/cadr-cli/media.lisp:31-47` recognizes magic only;
- `src/cadr-cli/media.lisp:191-231` has only an RGBA→PNG encoder;
- `src/cadr-cli/media.lisp:233-293` decodes BMP pixels;
- `src/cadr-cli/media.lisp:295-302` returns non-BMP unchanged;
- `src/cadr-cli/interactive-services.lisp:2566-2654` reads only the dimension header for PNG/JPEG;
- `src/cadr-cli/interactive-services.lisp:2656-2701` has only a test-injectable
  `resize-function`, with no production PNG/JPEG decoder/resampler.

So "the current code already covers image processing via the dimension header"
is false; it covers only metadata and BMP conversion, and does not cover the
baseline's PNG/JPEG pixel pipeline.

### 1.3 Minimal dependencies and unfreeze scope

Recommend approving two direct Quicklisp production dependencies:

| System | Fixed Quicklisp release | Purpose | New transitive closure |
|---|---|---|---|
| `cl-jpeg` | `cl-jpeg-20230214-git` | JPEG decode/encode | only ASDF; ASDF is provided by the implementation |
| `png-read` | `png-read-20170830-git` | PNG scanline/filter/color decode | `babel`, `chipz`, `iterate` |

`babel` and `iterate` already exist in the registered `cl-sqlite` transitive
closure, but once they enter the image path via `png-read` they must be
explicitly re-registered in the dependency audit; `chipz` is a new transitive
system. Both direct dependencies and `chipz` must first obtain user approval.

Minimal production implementation:

1. `cl-jpeg`/`png-read` decode JPEG/PNG uniformly to RGBA;
2. implement a deterministic Lanczos3 RGBA resampler inside cadr;
3. reuse the existing `encode-rgba-png`; use `cl-jpeg` for the JPEG candidate;
4. apply EXIF orientation before JPEG decode, following the baseline;
5. retain the original-bytes fast path for when the input is not over the limit;
6. add no subprocess, and call no external ImageMagick.

Minimal unfrozen files:

```text
cadr-cli.asd
src/cadr-cli/media.lisp
src/cadr-cli/interactive-services.lisp
test/cadr-cli/part-b-interactive-test.lisp
docs/dependency-audit.md
README.md
docs/parity-map.md
docs/progress/goal-v8.md
```

`src/cadr-tui`, `src/cadr-ai` and `src/cadr-agent` stay frozen. If the library
APIs cannot cover the PNG/JPEG pixel pipeline within that boundary, go blocked
again.

### 1.4 Alternatives considered and rejected

| Alternative | Reason for rejection |
|---|---|
| Keep reading only the dimension header | Directly violates the JPEG→PNG, real resize and byte reduction baseline |
| ImageMagick/ffmpeg subprocess | Adds an external runtime dependency; build and deployment are no longer hermetic |
| `opticl` | The closure is markedly larger: `cl-jpeg`, `cl-tga`, `opticl-core`, `pngload`, `retrospectiff`, `skippy`, `zpng` and others |
| Write a complete PNG/JPEG codec ourselves | Duplicates a mature codec; both the maintenance surface and the malicious-input risk are far higher than two narrow libraries |
| Use `cl-jpeg` only and implement PNG inflate/filter ourselves | Still requires rewriting DEFLATE, filters, CRC and the color-type boundaries; insufficient gain |
| Port the worker semantics verbatim to Lisp threads | The worker is an implementation means for preventing Node event-loop blocking, not an observable contract |

**Recommended adjudication: approve `cl-jpeg` + `png-read` together with the closure above and the minimal unfreeze surface.**

## 2. Adjudication item two: the extension API and CLI UI glue Part B requires

### 2.1 Exact requirement

Fill in only the following fixed-baseline extension surface:

1. `ctx.isIdle()` and command-only `ctx.waitForIdle()`;
2. shortcut, flag, message renderer and entry renderer registration;
3. tool call/result custom renderer;
4. the load-scope extension API's `sendMessage`, `sendUserMessage`, `exec`,
   `getFlag`, `getActiveTools`, `setActiveTools`;
5. bare/named/hidden inline extension factories;
6. the CLI-owned UI bridge's custom overlay, autocomplete wrapper, theme
   get/set/list/load and tool-output expansion get/set.

No new event names, no changes to existing macro signatures, no loosening of the
lifetime of the existing handler context, and no unfreezing of `src/cadr-tui`
production code.

### 2.2 Fixed-baseline evidence

| Surface | Fixed baseline |
|---|---|
| `ExtensionContext.isIdle` | `packages/coding-agent/src/core/extensions/types.ts:307-347`, method at `:329-330` |
| command-only `waitForIdle` | `packages/coding-agent/src/core/extensions/types.ts:353-365`, method at `:357-358` |
| shortcut, flag, `getFlag` | `packages/coding-agent/src/core/extensions/types.ts:1243-1269` |
| message/entry renderer | `packages/coding-agent/src/core/extensions/types.ts:1271-1279` |
| `exec`, active tools get/set | `packages/coding-agent/src/core/extensions/types.ts:1313-1326` |
| tool renderer context, `renderCall`, `renderResult` | `packages/coding-agent/src/core/extensions/types.ts:410-497` |
| custom UI, autocomplete | `packages/coding-agent/src/core/extensions/types.ts:195-225` |
| theme and tool expansion | `packages/coding-agent/src/core/extensions/types.ts:265-281` |
| registration and action delegation | `packages/coding-agent/src/core/extensions/loader.ts:230-352` |
| inline factory construction and naming | `packages/coding-agent/src/core/extensions/loader.ts:483-497`; `packages/coding-agent/src/core/resource-loader.ts:158-175,945-967` |
| runtime binding and dynamic context | `packages/coding-agent/src/core/extensions/runner.ts:278-293,313-430,659-763` |

Tests that constrain the behavior directly:

| Behavior | Fixed baseline |
|---|---|
| renderer/shortcut/flag discovery | `packages/coding-agent/test/extensions-discovery.test.ts:374-393,463-497` |
| shortcut conflicts and reserved-key semantics | `packages/coding-agent/test/extensions-runner.test.ts:161-365` |
| renderer and flag resolution | `packages/coding-agent/test/extensions-runner.test.ts:596-699` |
| plan mode uses flags and active tools | `packages/coding-agent/test/plan-mode-extension.test.ts:35-128` |
| tool renderer state, fallback, inheritance | `packages/coding-agent/test/tool-execution-component.test.ts:38-365` |
| expansion, theme, custom focus, autocomplete | `packages/coding-agent/test/interactive-mode-status.test.ts:120-376` |
| inline factories reach the harness | `packages/coding-agent/test/test-harness.test.ts:271-322` |
| the `pi` object may be used asynchronously outside a handler, within the same valid runtime | `packages/coding-agent/test/suite/regressions/2023-queued-slash-command-followup.test.ts:17-79` |
| active tools take effect within the same run and are written into the tool-result delta | `packages/coding-agent/test/suite/regressions/6162-extension-active-tools-next-turn.test.ts:8-123` |
| inline factory bare/named/hidden/mixed naming | `packages/coding-agent/test/suite/regressions/6260-inline-extension-naming.test.ts:36-118` |
| `isIdle=true` after settling; command `waitForIdle` waits until the session has settled | `packages/coding-agent/test/suite/regressions/6363-agent-settled-event.test.ts:29-120` |
| the boundary between the module cache and rerunning the factory each time | `packages/coding-agent/test/suite/regressions/extension-factory-cache.test.ts:69-129` |

### 2.3 Minimal Lisp public contract

The existing `extension-context` remains valid only inside a handler; its stale
error, its existing accessors and the existing macro signatures are all
unchanged. Add one load-scope opaque handle corresponding to the TS factory
parameter `pi`:

```lisp
(current-extension-api) ; only obtainable during extension load, => extension-api

(extension-api-send-message
 api message &key trigger-turn-p deliver-as)
(extension-api-send-user-message
 api content &key deliver-as)
(extension-api-exec
 api command arguments &key cwd environment timeout-ms)
(extension-api-get-flag api name)
(extension-api-get-active-tools api)
(extension-api-set-active-tools api tool-names)
```

The handle may be captured by an extension and used in the command/tool/async
continuation of the same valid generation, which satisfies regression #2023;
after a reload, session replacement or bundle retirement it must still be stale.
It is not an immortal global, and it does not loosen `extension-context`.

Only these are added to the context:

```lisp
(extension-context-idle-p context)
(extension-command-context-wait-for-idle context)
```

The second function accepts only a command context; calling it on an ordinary
event/tool context must signal a type error. The definition of settled follows
the existing agent's retry/follow-up drain boundary.

The registration surface gains new macros only; the lambda lists of the existing
`define-tool`, `define-command`, `define-event-hook` and `define-provider` are
unchanged:

```lisp
(define-shortcut key &key description handler)
(define-flag name &key description type default)
(define-message-renderer custom-type &key renderer)
(define-entry-renderer custom-type &key renderer)
(define-tool-renderer tool-name &key call result)
```

`define-tool-renderer` exists separately, avoiding adding a keyword to the
already-frozen `define-tool`. A renderer returns the existing cadr-tui
component/line protocol; when the call/result slot is missing it falls back or
inherits as the baseline does, and no second set of component types is created.

The inline factory input allows only:

```lisp
function
(:name string :factory function :hidden-p boolean)
```

A bare factory displays `<inline:N>`, a named factory displays `<inline:name>`;
the module/source parse cache still follows cwd/generation, and the factory runs
on every load.

The UI bridge adds only:

```lisp
(extension-context-custom context factory &key overlay-p overlay-options)
(extension-context-add-autocomplete-provider context factory)
(extension-context-theme context)
(extension-context-all-themes context)
(extension-context-get-theme context name)
(extension-context-set-theme context theme)
(extension-context-tools-expanded-p context)
(extension-context-set-tools-expanded context expanded-p)
```

The implementation must live in `cadr-cli` and reuse the existing
overlay/editor/theme/autocomplete/tool row components; `src/cadr-tui` stays
frozen. If any one of them genuinely requires modifying a `src/cadr-tui`
production object ID, go blocked immediately.

### 2.4 Minimal unfreeze scope

```text
src/cadr-agent/extensions.lisp
src/cadr-agent/package.lisp
src/cadr-agent/loop.lisp
src/cadr-agent/tool.lisp
test/cadr-agent/extensions-wave3-test.lisp
src/cadr-cli/extensions.lisp
src/cadr-cli/resource-loader.lisp
src/cadr-cli/interactive-services.lisp
src/cadr-cli/tui.lisp
src/cadr-cli/main.lisp
test/cadr-cli/extensions-test.lisp
test/cadr-cli/part-b-*.lisp
cadr-agent.asd
cadr-cli.asd
docs/parity-map.md
docs/architecture.md
docs/progress/goal-v8.md
```

Only files that the tests prove are actually needed may enter the commit; this
list is not a whole-directory authorization.
`src/cadr-ai` and `src/cadr-tui` stay frozen.

### 2.5 Backward compatibility and refreeze gates

1. `LEGACY-EXTENSION-SOURCE-REMAINS-COMPATIBLE-AFTER-WAVE-2-API-EXPANSION`
   must stay fully green;
2. the existing four old events, the 33 frozen events and all old macro
   signatures are regressed item by item;
3. a captured old `extension-context` still signals
   `stale-extension-context` after it leaves the handler;
4. the new load-scope API is stale after reload/retirement as well;
5. zero change to `src/cadr-tui` production object IDs;
6. after the implementation commit, recompute the extension export SHA and all
   extension object IDs, update architecture, then restore "stable on release".

### 2.6 Alternatives considered and rejected

| Alternative | Reason for rejection |
|---|---|
| Simply make `extension-context` permanently valid | Breaks the Goal 7 stale-context freeze and reload/session-replacement isolation |
| Add keywords to the existing macros | Changes a frozen lambda list, and distorts the old-extension compatibility gate |
| Add new events that carry UI/active-tools | The baseline already has an action/context surface; there is no need to invent events |
| Do only a test fixture wrapper | Cannot cover the real resource loader, TUI focus, or the active-tool next request |
| Copy the TUI components into `cadr-agent` | Breaks the dependency direction and produces a second set of UI types |
| Modify `src/cadr-tui` | The current evidence shows the CLI glue can reuse the existing components; if the facts are the opposite, a separate adjudication is required |
| Rule these rows N/A | They are not language/build inevitable differences, but the baseline's public extension mechanism |

**Recommended adjudication: approve the additive API and CLI glue listed in this section; unfreezing
`src/cadr-ai` and `src/cadr-tui` is forbidden.**

## 3. Adjudication item three: the llama.cpp bundled extension and the minimal `cadr-ai` contract

### 3.1 Exact requirement

Cover `packages/coding-agent/test/llama-extension.test.ts` as a whole file:

1. the bundled extension registers a native runtime provider and `/llama`;
2. normalization of the management URL and the `/v1` inference URL;
3. expose only `loaded` models, and map metadata such as context window and
   image modality;
4. the provider-scoped model store supports online refresh and cache-only
   restore;
5. dormant when unconfigured; interactive login saves the server URL and the
   optional key;
6. auth check/resolve produce the request-time base URL/key;
7. Hugging Face search, GGUF quantization grouping and gated metadata;
8. `/models/sse` load/download progress and the final catalog refresh;
9. inference reuses the existing OpenAI Chat Completions stream and adds no new
   wire protocol.

### 3.2 Fixed-baseline evidence

| Contract | Fixed baseline |
|---|---|
| the runtime provider's auth/models/refresh/filter/stream surface | `packages/ai/src/models.ts:34-120` |
| the public semantics of runtime login/check | `packages/ai/src/models.ts:127-171,364-445` |
| provider mutation, provider-scoped store, credential-aware refresh and cache fallback | `packages/ai/src/models.ts:218-328` |
| store entry and provider-scoped read/write/delete | `packages/ai/src/models-store.ts:3-28` |
| API-key login/check/resolve | `packages/ai/src/auth/types.ts:150-182,212-220` |
| llama provider URL/key login, check, resolve | `packages/coding-agent/src/extensions/llama/provider.ts:58-110` |
| loaded catalog, cache restore, OpenAI completions stream | `packages/coding-agent/src/extensions/llama/provider.ts:111-133` |
| extension registration and URL normalization | `packages/coding-agent/test/llama-extension.test.ts:42-60` |
| loaded-only model mapping | `packages/coding-agent/test/llama-extension.test.ts:62-87` |
| cache-only restore | `packages/coding-agent/test/llama-extension.test.ts:89-131` |
| dormant/login/check/resolve | `packages/coding-agent/test/llama-extension.test.ts:133-162` |
| Hugging Face search/details | `packages/coding-agent/test/llama-extension.test.ts:164-202` |
| local loopback SSE load/download | `packages/coding-agent/test/llama-extension.test.ts:204-291` |

`llama-extension.test.ts` is not an Ollama/llama.cpp live smoke. It starts a
local loopback HTTP/SSE server, all of its assertions are deterministic, and the
fixed baseline has no `skipIf(!KEY)`. It therefore must not be skipped under the
live-credential gating principle; llama.cpp not being deployed on this machine
is not a reason for N/A either.

### 3.3 What `cadr-ai` already has

The current `cadr-ai` is not missing an entire provider runtime:

- `src/cadr-ai/models-runtime.lisp:66-79` already has models/model-function,
  auth resolver, OAuth, refresh/filter and complete/stream slots;
- `src/cadr-ai/models-runtime.lisp:100-154` already has provider mutation and
  synchronizing current models;
- `src/cadr-ai/models-runtime.lisp:293-341` already has auth check and
  availability;
- `src/cadr-ai/models-runtime.lisp:343-418` already has a provider-scoped model
  store and refresh/cache fallback;
- `src/cadr-ai/models-runtime.lisp:538-543` already has complete/stream dispatch.

So rewriting the registry is not allowed, and neither is stuffing llama
management into `cadr-ai`.

### 3.4 The minimal new contract surface `cadr-ai` needs

Only additive slots on `runtime-provider`:

```lisp
api-key-login-function
auth-check-function
refresh-context-function
```

API-key login uses an opaque interaction equivalent to the baseline's
`AuthInteraction`:

```lisp
(make-runtime-auth-interaction
 :prompt-function function
 :notify-function function
 :abort-p function)
(runtime-auth-interaction-prompt interaction prompt)
(runtime-auth-interaction-notify interaction event)
(runtime-auth-interaction-aborted-p interaction)
```

`prompt` is a strict plist that supports at least the
`(:type :text/:secret :message string :placeholder optional-string)` that llama
needs; `event` is `(:type keyword :message string)`. This is not a new UI
framework; the CLI only bridges it to the existing input/secret/notification.

A new opaque refresh context:

```lisp
(runtime-refresh-context-credential context)
(runtime-refresh-context-store context)
(runtime-refresh-context-allow-network-p context)
(runtime-refresh-context-force-p context)
(runtime-refresh-context-aborted-p context)
```

A new runtime entry point:

```lisp
(models-runtime-login-api-key runtime provider-id interaction)
```

Exact semantics:

1. `models-runtime-login-api-key` only calls the provider's
   `api-key-login-function`, returning an `api-key-credential` that the existing
   credential store saves; it does not unfreeze OAuth login;
2. `models-runtime-check-auth` calls `auth-check-function` first if there is
   one, and otherwise keeps the existing resolver fallback;
3. `models-runtime-refresh`, if there is a `refresh-context-function`, passes in
   the provider-scoped store, credential, allow-network, force and abort view;
   otherwise it goes on calling the existing
   `refresh-function credential store allow-network force`;
4. **the existing `refresh-function` parameter list is not changed**, and
   existing providers need zero migration;
5. export only the new types/accessors/entry point above and the additive slot
   accessors the constructor needs; the static provider registry, the model
   types, HTTP/SSE and the wire protocol are not changed.

The agent/CLI glue adds, separately and minimally:

```lisp
(define-native-provider runtime-provider)
```

It coexists with the existing `define-provider`, whose signature and static
overlay semantics are unchanged. `cadr-cli` wires the native runtime provider
into the existing model selector, auth/store and agent dispatch; the llama
client, the Hugging Face client, SSE progress and the `/llama` command go in the
bundled CLI extension directory and do not enter `cadr-ai`. Inference reuses the
existing `:openai-completions` adapter.

### 3.5 Minimal unfreeze scope and the fuse

```text
src/cadr-ai/models-runtime.lisp
src/cadr-ai/package.lisp
test/cadr-ai/models-runtime-test.lisp
cadr-ai.asd
src/cadr-agent/extensions.lisp
src/cadr-agent/package.lisp
test/cadr-agent/extensions-wave3-test.lisp
src/cadr-cli/extensions.lisp
src/cadr-cli/model-services.lisp
src/cadr-cli/extensions/llama/*.lisp
test/cadr-cli/llama-extension-test.lisp
cadr-agent.asd
cadr-cli.asd
docs/parity-map.md
docs/architecture.md
docs/progress/goal-v8.md
```

This is a **scoped override proposal** against Goal 7's "if `src/cadr-ai` needs
modifying, go blocked", and it has not yet been approved. Only the following
frozen objects may be modified:

```text
src/cadr-ai/models-runtime.lisp
src/cadr-ai/package.lisp
test/cadr-ai/models-runtime-test.lisp
cadr-ai.asd
```

If the implementation needs to touch any other `src/cadr-ai` production object
ID, go blocked immediately; modifying it in passing is not permitted. This item
adds no third-party dependency.

### 3.6 Alternatives considered and rejected

| Alternative | Reason for rejection |
|---|---|
| Skip because llama.cpp is not deployed on this machine | The test is a local loopback deterministic contract, not a live block |
| Pass the existing static `define-provider` off as it | Cannot cover the dynamic catalog, cache-only restore, or custom login/check |
| Put llama/Hugging Face management into `cadr-ai` | Breaks the extension boundary and widens the core's responsibilities |
| Rewrite a provider runtime in the CLI | Duplicates the store/auth/dispatch `models-runtime` already has |
| Change the existing `refresh-function` parameter list | Breaks existing runtime providers; an additive context slot is already enough |
| Add a llama wire adapter | Inference is already standard OpenAI Chat Completions |

**Recommended adjudication: approve the scoped unfreeze of the four `cadr-ai` files above and the additive contract;
the rest of `cadr-ai` stays frozen.**

## 4. Adjudication item four: rule `config.test.ts` N/A as a whole file

### 4.1 Summary of the file's contents

The fixed-baseline file is 437 lines in total and contains only the Node/Bun
installation source and the JS package-manager self-update contract:

| Content | Fixed baseline |
|---|---|
| temporary npm/pnpm/yarn/bun global install layout and fake CLI helpers | `packages/coding-agent/test/config.test.ts:1-147` |
| detecting pnpm from the Windows `.pnpm` path; an unknown wrapper does not self-update | `packages/coding-agent/test/config.test.ts:148-168` |
| npm custom prefix, exact version, package rename, configured/empty `npmCommand`, display quoting, Windows prefix | `packages/coding-agent/test/config.test.ts:170-293` |
| bun global install | `packages/coding-agent/test/config.test.ts:295-306` |
| pnpm rename and pnpm v11 store resolution | `packages/coding-agent/test/config.test.ts:308-375` |
| on a yarn/bun rename, uninstall the old package first | `packages/coding-agent/test/config.test.ts:377-426` |
| when the install path is not writable, forbid self-update and give an explanation | `packages/coding-agent/test/config.test.ts:428-436` |

The corresponding production contract explicitly enumerates
`"bun-binary" | "npm" | "pnpm" | "yarn" | "bun" | "unknown"`, sourced at
`packages/coding-agent/src/config.ts:25-94`; the package-manager command
construction is at `:115-186`, and the global
ownership/writability/self-update gate is at
`:304-355`.

### 4.2 Grounds for N/A

cadr is a single native executable produced by the SBCL `build.sh`; it is not
installed by npm, pnpm, yarn, bun or the Bun embedded filesystem. Having a Lisp
binary detect `node_modules`, `.pnpm`, `PNPM_HOME` or `bun pm bin -g`, or run a
JS package uninstall/install, is not a semantic port; it is forcing a mechanism
that exists in the baseline only because of the JavaScript distribution method
into a different build ecosystem.

This is exactly the "build-method inevitable difference" that the global
principle allows to be retained. The current cadr self-update boundary is to
explicitly tell the user to use the Common Lisp build/install method:
`src/cadr-cli/package-manager.lisp:849-877,1187-1197`.

The N/A applies only to the one package-manager/self-update file
`config.test.ts`, and does not extend to version checking:

- `packages/coding-agent/test/version-check.test.ts` must still be aligned file
  by file;
- the remote version-check currently in `src/cadr-cli/sdk-services.lisp:240-398`
  and `test/cadr-cli/part-b-sdk-test.lisp:152-323` is applicable behavior;
- extension/resource Git package update does not become N/A because of this
  adjudication either.

The only ledger action after approval is to change
`packages/coding-agent/test/config.test.ts` from `M` to a user-adjudicated
`N/A`, and to record "SBCL binary build/install method" in the parity-map
difference note. No production code is added, and no C is faked.

### 4.3 Alternatives considered and rejected

| Alternative | Reason for rejection |
|---|---|
| Simulate npm/pnpm/yarn/bun detection in cadr | Introduces a new mechanism that does not apply to an SBCL binary, plus Node package coupling |
| Interpret the `build.sh` update command as the same contract and mark it C | The install ownership, rename, global root and writability semantics are completely different |
| Substitute the already-implemented remote version-check and mark it C | Violates the whole-file strictness principle; version notification is not self-update |
| Keep it M permanently | A clear N/A boundary caused solely by the build ecosystem already exists, and after human adjudication it should be recorded truthfully |

**Recommended adjudication: approve N/A for this file as a whole file; it does not affect `version-check.test.ts` or the resource-package
update rows.**

## 5. Implementation and acceptance order

The user has approved items 1–4 item by item; the order below is retained as the
authorization constraint that was executed.

If approval is given, the order is fixed:

1. move only approved items into the "changes allowed in this goal" list;
2. for item 1, first update the dependency audit/README and commit the
   authorization record separately, then add the dependencies;
3. tests first for every item, retaining an attributable red gate;
4. for items 2/3, run legacy extension compatibility first, then do the
   production implementation;
5. once the specific tests are fully green, run `./scripts/test-cl.sh`;
6. commit in logical groups; the working tree must be clean;
7. recompute the extension export SHA/object IDs and update architecture;
8. only after every approved item is complete, committed and fully re-verified
   may the parity counts be updated.

Suggested adjudication format:

```text
Item 1: approve / reject
Item 2: approve / reject
Item 3: approve / reject
Item 4: approve / reject
```
