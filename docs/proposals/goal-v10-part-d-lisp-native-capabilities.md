# Goal 10 Part D Lisp-native capabilities proposal

Status: **Approved item by item and implemented on 2026-08-01. Part B was subsequently adjudicated by the user to be a no-op, and the execution-order gate is lifted; the implementation and re-freeze evidence are in `docs/acceptance/goal-v10-part-d.md`.**

Current cadr implementation base point:
`7fb06d093d5eebd7163e3271fdc3451c31aa213a`. The current behavioral baseline is
still `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`; Part B will re-lock only after
upstream stable `v0.84.0` is released. This document's adjudication is complete,
but any implementation must satisfy both of:

1. Part B is finished, and this document's source locations and object IDs have
   been re-reviewed against the new baseline;
2. the implementation stays strictly within the capabilities, dependencies, and
   file surface approved in this document; if the minimal implementation surface
   expands, become blocked again and escalate for user adjudication.

## 1. Overall boundary

Both items are deliberate additions that the fixed TypeScript pi does not have,
and they do not count toward the parity `C` verdict. Once approved and
implemented they must be registered in the README divergence list and the
parity-map, and must obey:

- the default path does not enable them at all; the existing CLI, provider
  payload, system prompt, tool schema/description/result, session bytes,
  agent/JSON/RPC events, and TUI snapshots are byte-for-byte unchanged;
- no approval flow, trust ledger, or new security boundary is introduced; it is
  still YOLO by default, and strong isolation is provided by a container, a
  virtual machine, or a restricted user;
- the existing extension macro signatures, the four old events, and the
  stale/snapshot/reload semantics have zero change;
- only the files and symbols listed in this document may be unfrozen. If the
  minimal implementation surface expands after Part B, become blocked
  immediately; a newly frozen surface must not be crossed in passing.

The start-of-work freeze audit additionally found: using the same sampling
command as Goal 7/8, the extension export SHA-256 measured at the current HEAD is
`bb4665245ef9df19b274535071fcc5f6e56c79ab29db2152cd41afaa4df3b1e0`,
not the Goal 8 historical value
`e0bcbf8c5f170efb99579fe6065579a8c2e93c7f1bd590b7502b08180ba54046`
that `docs/architecture.md` still says "continues".
The difference comes from the `define-markdown-transformer` export approved in
Goal 9, not from this proposal. This round does not pretend to have re-frozen;
when Part B rebuilds the baseline document it will first correct the current
anchor, and it will be recomputed again after the Part D implementation.

## 2. D1: condition/restart at the tool-failure site

### 2.1 Exact requirement and current state

The goal is to signal `tool-execution-error` while the original stack of the
schema validation or tool executor error still exists, and at the same time
establish three restarts: "retry with changed arguments / skip / abort the agent
run". A Common Lisp host can choose directly with `handler-bind`/`invoke-restart`;
an extension can choose with a new hook, and can show a selector in the
TUI/RPC front end through the already frozen extension UI. The core TUI has no
built-in automatic pop-up.

Decisive evidence for the current path:

- `src/cadr-agent/tool.lisp:141-189`: after `:tool-call-before` and revalidation,
  the schema condition is turned directly into an error tool result by
  `handler-case`;
- `src/cadr-agent/tool.lisp:191-217`: any `error` from the executor retains only
  `princ-to-string` after the stack is unwound, with no usable restart;
- `src/cadr-agent/loop.lisp:148-189,215-285`: `:tool-call-after` and
  `:tool-execution-end` handle only the terminal outcome; the batch may run in
  parallel and results are submitted in source order;
- `src/cadr-agent/extensions.lisp:949-982,3380-3462`: the current extension events
  contain no decision point at the failure site.

An unknown tool, `:length` truncation, and an active block by
`:tool-call-before` are not executor failures; they continue to produce results by
the old path and do not establish this restart group.

### 2.2 Public condition and restart contract

Reuse the already exported `cadr-agent:tool-execution-error`; do not modify its
existing readers. The condition's `message` must equal the existing tool result
text, `cause` retains the original condition, and `tool` and `tool-call-id` keep
their existing meanings. Only three restart name symbols are added and exported:

| restart | Arguments | Exact semantics |
|---|---|---|
| `cadr-agent:retry-tool-call` | `(replacement-arguments)` | keeps the call id/name and rewalks from `:tool-call-before` with the new JSON object, resolving the tool again and performing schema validation; no retry bypasses the hook or the validation |
| `cadr-agent:skip-tool-call` | `(&optional reason)` | does not execute further and produces a terminal tool result with `is-error=t`; when `reason` is omitted it uses the original failure text verbatim |
| `cadr-agent:abort-agent-run` | `(&optional reason)` | first produces the same error result as above for the current logical tool call, then enters the existing `agent-abort` path; after the current batch converges to completion, no new provider payload is sent |

The restarts exist only within the dynamic extent of the corresponding condition,
are not saved to the session, and do not serialize the stack or the condition into
JSON/RPC. Restarts of parallel tools are isolated per call; one worker must not
find or invoke another call's restart.

### 2.3 Relationship to the extension hook

A new event `:tool-call-error` is added, still using the existing signature:

```lisp
(define-event-hook :tool-call-error
  :priority 0
  :handler (lambda (event context) ...))
```

`(extension-event-payload event)` is a strictly read-only plist:

```lisp
(:condition <tool-execution-error>
 :tool-call <cadr-ai:tool-call>
 :arguments <hash-table>
 :attempt <positive-integer>
 :restart-names
 (cadr-agent:retry-tool-call
 cadr-agent:skip-tool-call
 cadr-agent:abort-agent-run))
```

`:arguments` is a defensive deep copy; modifying it does not affect the current
attempt. The only way to change behavior is to return a validated `:retry` result.

A handler returning `nil` means it makes no choice; non-`nil` allows only:

```lisp
(:action :retry :arguments <hash-table>)
(:action :skip  :reason <optional-string>)
(:action :abort :reason <optional-string>)
```

The first hook that returns non-`nil` and passes type validation short-circuits the
subsequent hooks, and the core invokes the corresponding restart on its behalf
while the condition is still live. An illegal return value only records that
extension as failed and continues to the next hook; it does not change the tool
result.

The ordering is frozen as:

1. a logical call emits `:tool-execution-start` only once;
2. every actual attempt first runs `:tool-call-before` and revalidates;
3. on failure, `:tool-call-error` runs at the site; a retry returns to step 2;
4. `:tool-call-after` runs once, only for a final success, a skip, an abort, or a
   failure nobody handled;
5. the terminal `:tool-execution-end` is emitted only once.

Therefore `:tool-call-after` never sees an intermediate failed attempt, and the old
extensions' "one call corresponds to one after" is unchanged. Interactive approval
still does not enter the core; a user who needs to choose does so through this hook
calling `extension-context-select` and returning one of the actions above.

### 2.4 Non-interactive modes and the zero-change guarantee

print, JSON, and RPC install no implicit condition handler, and choose no restart
automatically. When there is no `:tool-call-error` extension, or all hooks return
`nil`:

- the condition is turned into the same `is-error=t` tool result along the
  existing boundary;
- the text is still the existing redacted string of the original condition;
- agent event types, counts, and order are unchanged; `:tool-call-error` is only an
  extension-internal lifecycle event and does not join `agent-event` or the
  JSON/RPC wire;
- `:tool-call-after`, session persistence, and the tool result fed to the model on
  the next round are byte-for-byte unchanged.

The gate will run both the "start-of-work object" and the "new implementation's
default path" with the same faux provider/tool condition, recursively comparing
session JSON, the model-visible result, agent events, and the complete
text/JSON/RPC output; it does not obtain a pass through normalization or weak
assertions.

### 2.5 Minimal unfreeze surface

The current HEAD is the audit point of this proposal:

| Path | Current object ID | Only permitted changes |
|---|---|---|
| `src/cadr-agent/tool.lisp` | `08beda50203d7af790d1690a06090ca7df82da23` | signaling on the original stack, the restart cluster, retry/skip outcome |
| `src/cadr-agent/loop.lisp` | `118b99b97488a8640f9e825c50b6b7e1423f0769` | attempt orchestration, abort convergence, the event-invariance gate |
| `src/cadr-agent/extensions.lisp` | `39924113baa1928cb521dcf257e4afe9509bb0ca` | only the new event's payload/result validation and dispatch |
| `src/cadr-agent/package.lisp` | `05357d1575581916098191e14c1821f39a7a42e2` | only adding the three restart name exports |
| `test/cadr-agent/tool-loop-test.lisp` | `0e32eed1d92d96bb023f2e6f214687028993e53a` | condition/restart, parallel isolation, old-path snapshots |
| `test/cadr-agent/extensions-wave2-test.lisp` | `cf16c937b667eb2252a45ec93585edc8d0a4d60a` | the new hook and the old-extension compatibility gate |

`src/cadr-ai`, `src/cadr-cli`, `src/cadr-tui`, all of `src/cadr-cli/tools/`, ASDF,
and the provider implementations stay frozen. Tests go red before the
implementation, locking at least:

1. when the handler observes the condition, the executor's `unwind-protect` cleanup
   has not yet happened;
2. both a schema failure and an executor failure can be retried with changed
   arguments; the new arguments must rerun the before hook and the schema;
3. on multiple retries, before/error occur per attempt while after/start/end still
   occur once each;
4. skip's default text is word-for-word identical to the old error result; abort
   sends no new provider request;
5. the condition/restart/arguments of two concurrently failing calls do not leak
   into each other;
6. `LEGACY-EXTENSION-SOURCE-REMAINS-COMPATIBLE-AFTER-WAVE-2-API-EXPANSION`
   is fully green without modification, and the old macro signatures and the four
   old events have zero change;
7. the default path's session/model-visible bytes and text/JSON/RPC output undergo
   a complete differential comparison.

### 2.6 Alternatives considered

| Alternative | Reason for rejection |
|---|---|
| keep `handler-case` and retry in an ordinary loop after unwinding | loses the original stack and the dynamic restarts, and does not exploit Lisp's core capability |
| build a tool-failure pop-up into the TUI | stuffs approval/policy back into the core, violating YOLO by default and the extension boundary |
| expose only the condition, giving extensions no event | usable by an external Lisp host, but existing extensions cannot choose portably at the dynamic site |
| automatically retry N times with the old arguments | introduces a policy the baseline does not have and is dangerous for non-idempotent tools; a retry may only be chosen explicitly by a handler/hook |
| serialize the condition/backtrace into JSON/RPC | leaks the stack, expands the wire, and breaks zero observable change; not done |

### 2.7 Freeze impact and rollback

This item unfreezes only the internal execution boundary of tool/loop and the
extension event set; it does not change the tool domain types, the six/eight
built-in tools, old hook results, or the wire. At wrap-up, recompute all unfrozen
object IDs, the extension event-set hash, and the existing extension export SHA,
then re-freeze.

Rollback only requires removing the restart cluster, the `:tool-call-error`
validation/dispatch, and the three exports, restoring the existing
`handler-case → make-error-tool-result` path. There is no configuration, session, or data migration.

## 3. D2: Slynk remote REPL

### 3.1 Exact requirement and public interface

Start Slynk for the current `cadr` process only when the user explicitly passes a
port:

```text
./cadr --slynk 4005
```

The exact CLI contract:

- `--slynk <port>` is a value-taking option; by default no listener exists, no
  configuration or environment variable is read, and the previous value is not
  remembered;
- the port must be a decimal integer in `1..65535`; `0` is not accepted, which
  avoids polluting text/JSON/RPC stdout in order to report an
  ephemeral port;
- it calls `slynk:create-server :port port :interface "127.0.0.1"
  :style :spawn :dont-close t`; no host/interface option is provided, `localhost`
  is not resolved, and `0.0.0.0`/`::` are not allowed;
- a bind failure is a fatal startup configuration error; it does not degrade into
  "continue without a REPL";
- a normal exit closes the listener with `slynk:stop-server` and then clears the
  active agent reference. It writes no session/config and does not modify tool or
  extension discovery.

One read-only public entry point is added:

```lisp
(cadr-cli:active-agent) ; => cadr-agent:agent | nil
```

It only returns the agent the current CLI is running; it does not copy a second
copy of the state and provides no write operation. The stable inspection procedure
is to call the existing `cadr-agent:agent-wait-for-idle` first, then read the
existing agent/session accessors. After recompiling/redefining a named tool helper
function in the SLY MREPL, SBCL's global function binding takes effect from the
next call onward; the agent and session objects are not rebuilt, and the session
id, leaf, and history are not lost. No retroactive replacement is promised for a
current function already on the stack.

Evidence for the current integration points:

- `src/cadr-cli/arguments.lisp:7-54,56-113,311-454`: the argument object,
  value-taking options, flags, and unknown arguments already have a single parser;
- `src/cadr-cli/main.lisp:2700-2733`: the agent is established only inside the CLI
  handler;
- `src/cadr-cli/main.lisp:3523-3935`: TUI/REPL/text/JSON/RPC share the same agent
  and terminal lifecycle, which suits starting and stopping them uniformly outside
  the mode dispatch.

### 3.2 Dependency pre-review and transitive closure

Slynk is a new third-party dependency and must be authorized separately from the
capability itself. The audit target is `sly-20260101-git` in the current
Quicklisp `2026-01-01`, upstream commit
`e01c7b4b66876073b07edbc797188435eb098698`, archive MD5
`129945ec9a674a1efe353e2d3742fb00`. The dependency closure is:

```text
cadr-cli
└─ slynk/mrepl
   └─ slynk
      └─ ASDF
```

- Quicklisp `systems.txt:5548-5552` lists only `slynk → asdf` and each contrib
  `→ slynk`;
- the core system in `slynk/slynk.asd:20-82,99-101` has no other
  `depends-on`, and `slynk/mrepl` depends only on `slynk`;
- the SBCL backend `slynk/backend/sbcl.lisp:21-25` `require`s
  `sb-bsd-sockets`, `sb-introspect`, `sb-posix`, and `sb-cltl2` at runtime; all
  four are SBCL contribs, not part of the third-party closure;
- `slynk/fancy-inspector`, `arglists`, `profiler`, `stickers`,
  `trace-dialog`, `macrostep`, and `named-readtables` are not introduced.

Slynk is a pure Common Lisp editor-protocol server with no new C ABI, dynamic
library, cryptographic, or database dependency; but it opens an arbitrary
in-process evaluation channel, so it is not filed under the image codec's
"pure-Lisp replaceable" category. If approved, `docs/dependency-audit.md` and the
README will add a separate "explicitly enabled debugging service" category,
registered per the snapshot and closure above.

Audit evidence for Slynk's upstream binding semantics:
the default value in `slynk/slynk.lisp:923-949` is `localhost` and `create-server`
accepts an explicit `interface`; this proposal does not trust the default
resolution and always passes `127.0.0.1`. `Slynk` optionally reads `~/.sly-secret`
(`slynk/slynk.lisp:1020-1035`), but cadr does not treat that optional file as a
security boundary.

There is one more load side effect that must not be ignored: `slynk/slynk.asd:80-82`
calls `slynk::init` after the ASDF load, and
`slynk/slynk.lisp:4217-4232` loads the building user's `.slynk.lisp` or
`.slynkrc`. Personal configuration, side effects, or even secrets must not be baked
into the released image. Therefore the official build and the deterministic tests
must first preserve the `QUICKLISP_SETUP` already resolved to an absolute path, and
then start SBCL with a newly created empty temporary `HOME`; the temporary
directory is deleted on exit. Slynk's source is not patched, and the build
machine's dotfiles are not trusted.

### 3.3 Security position

`--slynk` is an explicit enabling of "this process allows clients in the same
network namespace on this machine to execute arbitrary Lisp"; it is not an approval
pop-up or a permission sandbox. Even when listening only on loopback, other
processes in the same host/container/network namespace can still connect, and can
read agent state, credentials, and files, or perform system calls.

The README must therefore state clearly:

- off by default; configuration or environment variables must not be allowed to
  silently enable it;
- enable it only on a trusted machine; when cross-machine access is needed the
  user establishes an SSH tunnel themselves, and cadr never listens on a
  non-loopback address;
- when strong isolation is needed, put cadr and Slynk together into a
  container/virtual machine/restricted user;
- YOLO by default does not contradict this capability: neither of them treats a
  core pop-up as a security boundary, but Slynk's arbitrary-evaluation risk must be
  disclosed by an explicit CLI switch.

### 3.4 Minimal unfreeze surface

| Path | Current object ID | Only permitted changes |
|---|---|---|
| `cadr-cli.asd` | `4c45e1ba78e10f6c499b1aab6e565305dcdecd94` | adding `slynk/mrepl`, one runtime module, and the test wiring |
| `src/cadr-cli/package.lisp` | `143e4997bee670c28edbb03bd5f84c3a59288e88` | only exporting `active-agent` |
| `src/cadr-cli/arguments.lisp` | `39adf3ff684ac296b2f8af9ce6a1576dc1c798ac` | `--slynk <port>` parsing, validation, and help |
| `src/cadr-cli/remote-repl.lisp` | new file | the active-agent lock, Slynk start/stop, and the fixed loopback arguments |
| `src/cadr-cli/main.lisp` | `a5b04bbee254c4b2b90519e5763b1269909efe34` | installing/cleaning up the runtime REPL only after the agent is established and before mode dispatch |
| `test/cadr-cli/remote-repl-test.lisp` | new file | parser, socket, eval/redefine/session continuity, and stdout snapshots |
| `scripts/test-cl.sh` | `a2eb0f544a67b0ec868b70c86e7a40b2d1518510` | only providing an empty temporary HOME for the Slynk ASDF init, preserving the absolute `QUICKLISP_SETUP` |
| `build.sh` | `43826965957004c3b13c49d5ddd77c29b62d35b3` | likewise isolating the Slynk init that would be saved into the native image |

`src/cadr-agent`, `src/cadr-ai`, `src/cadr-tui`, the provider/tool sources, and
`build.lisp`/server/evals stay frozen. `build.lisp` only needs to quickload
`cadr-cli` and is not modified; Slynk
enters the native image through ASDF and does not depend on Quicklisp sources at
runtime.

Tests come first, and include at least:

1. without `--slynk` no port is listened on, and the old help/version/text/JSON/RPC/TUI snapshots have zero change;
2. a non-integer, 0, out of range, a missing value, and a port conflict fail deterministically;
3. the real socket binds only `127.0.0.1`, with no `0.0.0.0`/`::` appearing; the port is reusable after exit;
4. connecting to the native image over the real Slynk protocol and evaluating
   `(cadr-cli:active-agent)` obtains the current session id;
5. while the agent is idle, redefining a test tool helper function from SLY makes the next round return the new value;
   the agent identity, session id, and leaf/history are continuous before and after;
6. the full-process test runs under an isolated HOME where no Quicklisp source exists, proving that the
   native image does no runtime loading;
7. placing a `.slynkrc` that creates a sentinel in the building user's HOME, then asserting after the build that the
   sentinel does not exist and that the image contains no such string;
8. enabling Slynk still writes no credential to stdout, the session, errors, or logs, and does not break the
   JSON/RPC framing.

### 3.5 Alternatives considered

| Alternative | Reason for rejection |
|---|---|
| write our own socket REPL | duplicates the editor protocol, debugger, compilation, and thread integration; security-sensitive and unnecessary |
| only start an out-of-process `sbcl --load` | yields another Lisp world that cannot see the active agent/session, and a redefinition does not affect the running process |
| enable a fixed port by default | opens arbitrary evaluation without the user choosing it; unacceptable |
| support `--slynk-host`/`0.0.0.0` | brings remote exposure, authentication, and firewall policy into cadr; when a user needs cross-machine access they should use an SSH tunnel |
| silently enable via configuration/environment variable | the switch is hard to audit on the command line, and it can be activated accidentally by the project environment |
| depend on core `slynk` only, without preloading MREPL | connects but does not guarantee a usable editor REPL, which does not meet this item's requirement |
| preload all Slynk contribs | enlarges the code surface and the feature surface; this item needs only core + MREPL |

### 3.6 Freeze impact and rollback

This item unfreezes only the CLI arguments/lifecycle, one read-only agent entry
point, the `cadr-cli` ASDF dependency surface, and the build/test HOME isolation.
Once approved and implemented, wrap-up must record the Slynk
version/closure, recompute the eight
unfrozen object IDs, and re-freeze the `active-agent` signature and the `--slynk`
behavior.

Rollback removes `--slynk`, `remote-repl.lisp`, the `active-agent` export, and the
ASDF `slynk/mrepl` dependency, and deletes the divergence/dependency registration
at the same time. There is no session/config migration, and the data format read by
the old binary and the new binary is exactly the same.

## 4. User adjudication and the implementation gate

On 2026-08-01 the user adjudicated item by item:

1. `D1` **approved**: implement the condition/restart and
   `:tool-call-error` per section 2. That event is the 34th of the complete
   extension event set; Goal 8's "capped at 33" is lifted only for this addition,
   which went through a complete proposal and item-by-item adjudication. At
   implementation wrap-up, re-freeze on the complete set of 34 events; any future
   addition must still submit a fresh written proposal and be adjudicated item by
   item, and must not be inferred by analogy from this authorization. At that point
   recompute the extension export SHA, synchronize `docs/architecture.md`
   and the README, and mark `:tool-call-error` as a deliberate addition relative to the baseline;
2. `D2-capability` **approved**: implement strictly per section 3 the
   `active-agent` contract that is off by default, only via an explicit
   `--slynk <port>`, fixed to `127.0.0.1`, with cross-machine access left to a
   user-built SSH tunnel. The README must state truthfully that this is an
   arbitrary-evaluation channel, that loopback
   is not a sandbox, and that strong isolation should use a container, a virtual machine, or a restricted user;
3. `D2-dependency` **approved**: the dependency is pinned exactly to Quicklisp 2026-01-01
   `slynk/mrepl → slynk → ASDF`, upstream commit
   `e01c7b4b66876073b07edbc797188435eb098698`, archive MD5
   `129945ec9a674a1efe353e2d3742fb00`, and the contribs excluded in section 3.2 must not be introduced.
   At implementation time `docs/dependency-audit.md` and the README add a separate "explicitly enabled debugging
   service" category, not filed under "pure-Lisp replaceable";
4. the `.slynkrc` bake-in prevention measure is a mandatory gate: both the build and the deterministic tests must
   start SBCL in a brand-new empty temporary `HOME`, preserving the pre-resolved absolute `QUICKLISP_SETUP`, and clean
   up on exit; third-party sources are not patched, the build machine's dotfiles are not trusted, and a regression
   proves the released image contains none of its side effects.

Approval does not lift the execution order: Part B must first lock and complete the
`v0.84.0` alignment, and only then may the object IDs be re-reviewed and the Part D
implementation begun. For now, production code, ASDF, the dependency
list, README frozen values, and architecture frozen values must not be modified ahead of time.

Adjudication ledger re-check (2026-08-01): upstream GitHub Latest is still `v0.83.0`
(released 2026-07-29), and the `v0.84.0` tag ref still returns 404; Part B remains
suspended, and the lock was not changed to HEAD.
