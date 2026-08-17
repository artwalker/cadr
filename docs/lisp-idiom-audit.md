# Common Lisp expression audit

## Scope and method

This audit is the Goal 13 Part C2-A gate.  It covers every production Lisp
module under `src/` before any C2 rewrite.  The question is not whether a form
looks idiomatic in isolation; it is whether a different Lisp construct would
eliminate a demonstrated bug class, remove a manual invariant, enable an
otherwise unavailable capability, or materially reduce code.

<!-- GOAL13_LISP_IDIOM_AUDIT files=295 systems=9 axes=6 rewrite=1 keep=8 -->

The audited tree contains 295 Lisp files and 122,629 physical lines.  The form
inventory below is syntactic evidence, not a quality score:

| system | files | lines | structs | classes | generics | methods | macros | `handler-case` | `handler-bind` | `restart-case` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `cadr-core` | 7 | 471 | 1 | 0 | 0 | 0 | 1 | 3 | 0 | 0 |
| `cadr-ai` | 61 | 26,341 | 46 | 13 | 6 | 34 | 1 | 66 | 2 | 0 |
| `cadr-agent` | 37 | 16,281 | 49 | 7 | 23 | 35 | 15 | 54 | 3 | 1 |
| `cadr-cli` | 114 | 48,520 | 68 | 20 | 6 | 30 | 0 | 93 | 2 | 0 |
| `cadr-tui` | 50 | 23,730 | 40 | 17 | 22 | 74 | 0 | 9 | 0 | 0 |
| `cadr-storage` | 2 | 31 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `cadr-server` | 11 | 2,793 | 7 | 5 | 10 | 14 | 0 | 20 | 0 | 0 |
| `cadr-protocol` | 5 | 1,427 | 4 | 0 | 0 | 0 | 0 | 5 | 0 | 0 |
| `cadr-evals` | 8 | 3,031 | 17 | 0 | 0 | 0 | 0 | 4 | 0 | 0 |

The audit distinguishes three kinds of dispatch that are easy to conflate:

1. polymorphism over owned objects, where CLOS can enforce a protocol;
2. discrimination over external JSON/wire tags, where `case` is the protocol;
3. finite state-machine transitions, where a closed `case` is clearer and
   safer than open method dispatch.

Only the first category is a CLOS candidate.

## Module audit

| module | manual invariants | dispatch and representation | boilerplate | conditions and restarts | disposition |
|---|---|---|---|---|---|
| `cadr-core` | Bounded cleanup, cancellation, atomic replacement, secret-safe printing, and UTC conversion each have one policy owner. | These are closed SBCL/UIOP primitives, not extensible product objects; plain functions and one declaration macro expose the exact policy. | Compatibility wrappers in product packages delegate without policy. | Cleanup and filesystem conditions are normalized at the leaf boundary; no caller-selectable recovery exists. | **Keep.** Goal 14 B3 introduced this leaf specifically to remove repeated failure-policy invariants before later file extraction. |
| `cadr-ai` | Provider streaming reducers centralize scratch/final content and preserve exact wire text; request cancellation is dynamically scoped at the transport boundary.  The invariants are covered by payload and delta-boundary tests.  `src/cadr-ai/crash.lisp` adds the shared fatal-condition boundary and exact secret redaction. | Provider, credential and content records are value objects, so structs are appropriate; credential-bearing records have redacted `print-object` methods.  Most `case`/`cond` forms discriminate API names, JSON event tags, content types, or HTTP status, not extensible owned objects.  Stream classes/generics are already used where behavior is polymorphic. | Generated model/catalog forms must stay generated; a macro would hide rather than remove their source of truth. | Transport/parse handlers translate failures at abstraction boundaries.  The fatal boundary deliberately uses `handler-bind` so it captures the failure before stack unwind; it offers no fake recovery choice. | **Keep.** The post-audit crash boundary uses the correct pre-unwind condition mechanism; another hierarchy would add indirection without satisfying a C2-B reason. |
| `cadr-agent` | Agent/session list tails are centralized with head sentinels; storage owns entry/leaf invariants; extension event validation is centralized. Goal 17 adds one summarization choke point that solely owns retry, cache-retention, routing identity, and abort policy for compaction and branch summaries. The remaining concrete defect is obsolete server-rendered HTML code left behind after the baseline exporter replaced it. | Real substitutability already uses generics: execution environments (`execution-env.lisp:3-35`), session storage/repositories (`storage/protocol.lisp:3-35`), and their memory/JSONL/SQLite methods. Session entry/message tags remain serialized data and should not become an open class hierarchy. The summarization policy is closed behavior over an agent and is correctly a function, not a new class protocol. | The extension surface already uses `define-tool`, `define-command`, `define-event-hook`, provider, renderer, shortcut, and flag macros (`extensions/registration.lisp:732-812`). The summarization owner is protected by a source-level anti-bypass gate; wrapping it in a macro would hide rather than strengthen the call graph. | Tool failure is the one site with a useful local choice and already uses `restart-case` plus `handler-bind` (`loop/tool-execution.lisp:191-270`; `tool.lisp:230-294`). Summary retries classify transient errors at their single request boundary, while deterministic errors and aborts unwind immediately. Persistence/schema handlers translate corrupt external data and correctly unwind. | **One rewrite: C2-R1.** Delete five unreachable legacy HTML helpers and move the one live compaction formatter beside its only callers; keep all other structures. |
| `cadr-cli` | Frontend notices, statuses, warnings, auth URLs, and prompts remain distinct consumers in `bootstrap/commands.lisp`; RPC wire output remains owned by `modes/rpc/jsonl.lisp`.  Extension source output and infrastructure diagnostics use separate dynamic stream boundaries (`extensions/loader.lisp`).  `selector-frame` owns selector chrome, viewport/count, and wrap navigation while domain selectors retain distinct search and payload rules.  `src/cadr-cli/crash.lisp` applies the shared sanitized boundary to shipped entrypoints. | SDK lifecycle objects use classes/generics under `sdk/`.  Selector/editor/runtime state is closed mutable data and correctly remains structs plus explicit state-machine cases.  The selector frame is a composable value object rather than an open hierarchy.  The crash adapter is a boundary function, not a new object protocol. | Similar selector state machines are not semantically identical, but their frame decisions are one component.  Bootstrap and RPC command families are cohesive functions with one mode sink each; a macro over domain handlers would hide distinct command, cancellation, and payload contracts. | CLI handlers convert filesystem, subprocess, configuration, extension and fatal failures into stable user/wire outcomes.  No caller can choose a meaningful restart at those I/O sites. | **Keep.** Shared selector presentation, diagnostic, time, and crash bug classes are prevented by component/channel ownership and one shared fatal boundary rather than more exception syntax. |
| `cadr-tui` | Layout, focus, cache invalidation, disposal, and rendering are enforced by the component protocol and exact composition owners (`composition/{protocol,text-box,rich-content,settings-list,loaders,root}.lisp`). Terminal lifecycle is owned by the renderer terminal protocol. `src/cadr-tui/threads.lisp` centralizes bounded worker shutdown. | This is the strongest CLOS use in the tree: component inheritance and generic rendering/event/disposal, plus terminal/virtual-terminal methods (`renderer/{terminal-protocol,virtual-terminal}.lisp`; `terminal.lisp:218-817`). Editor, decoder, fuzzy, undo, key and thread handles are closed value/state records; bounded cleanup is a function over SBCL's closed thread primitive, so a wrapper class would add no substitutability. | No repeated constructor/validator group meets the significant-reduction threshold without hiding terminal semantics. | Terminal capability and image/decoder handlers provide fallback values. Bounded join handles cleanup failure as a fixed lifecycle policy, not an interactive recovery choice. | **Keep for C2.** B7 preserves the existing CLOS protocols while giving every implementation family one exact owner. |
| `cadr-storage` | This is a 31-line compatibility system boundary with no state of its own. | It re-exports the repository-backed implementation; another object model would duplicate it. | None. | None. | **Keep.** |
| `cadr-server` | Supervisor child state and connection ownership are encapsulated; socket framing remains explicit. | Radius presence and RPC process behavior already use classes/generics (`radius.lisp:3-75,105-120,581-704`; `rpc-process.lisp:3-13,27-393`).  Protocol message kinds are external closed tags and stay data-driven. | Repeated wire validation is intentionally explicit so each rejected field remains auditable. | Handlers isolate socket/process/JSON boundaries.  Server clients have no in-process restart protocol, so unwinding to a response/error frame is correct. | **Keep.** |
| `cadr-protocol` | Decoder length, depth, and frame state are carried in bounded structs and validated before allocation. | CBOR and wire schemas are external closed formats.  Open CLOS dispatch would weaken the explicit rejection surface. | Encoder/decoder cases are the readable protocol table; macro generation would make security review harder. | Five handlers normalize malformed input; retrying a malformed frame at the same stack point is meaningless. | **Keep.** |
| `cadr-evals` | Observations, summaries, diagnostics, and artifacts are immutable report values assembled by pure grouping/sorting passes. | Structs fit value records; there is no interchangeable runtime behavior.  Harness selection is a closed declared table. | Summary formatting is verbose but each field is distinct and reviewable; no duplicated block clears the significant-reduction bar. | Four handlers convert candidate/source execution failures into scored/unscored observations.  Continuing inside the failed candidate would falsify the evaluation. | **Keep.** |

## Six required audit axes

### 1. Manually maintained invariants

- **Already structural:** TUI spacing/focus/cache behavior is component-owned;
  storage and execution environments are generic protocols; frontend output
  categories have distinct consumers; tool restarts remain at the un-unwound
  failure site.
- **Centralized but intentionally explicit:** agent/session tail pointers use a
  head sentinel and repair only on wholesale list replacement.  Existing
  append regressions prove the cons tail, so replacing the list representation
  would not remove another user-visible bug class.
- **Candidate:** the removed server-rendered export path is an invariant with
  two implementations of “HTML export”.  Leaving both lets the dead copy drift
  and mislead future edits.  Deleting it makes the baseline template the only
  implementation.

### 2. Repeated dispatch logic

The repeated `case` forms fall mainly into wire tags, serialized session entry
types, input key actions, and closed UI states.  They are deliberately closed
sets.  Owned polymorphic objects already use CLOS for components, terminals,
storage, execution contexts, SDK runtime objects, Radius presence, and RPC
processes.  No additional conversion meets a C2-B reason.

### 3. Repeated boilerplate

The extension API is already macro-defined, while the model catalog is
generated.  Selector and provider blocks look similar but expose different
baseline contracts; merging them would exchange visible, separately tested
code for a macro protocol with no demonstrated bug reduction.  They remain
explicit.

### 4. Error handling

The single approved interactive recovery surface is tool failure, and it uses
conditions, `handler-bind`, and restarts before stack unwinding.  Network,
filesystem, parse, subprocess, wire, and evaluation errors cross process or
data boundaries and have only one valid local action: normalize and unwind.
Converting those `handler-case` forms to restarts would create choices no
consumer can safely take.

### 5. `defstruct` versus `defclass`

Current use is consistent: wire/value/state records are structs; objects with
substitutable behavior, lifecycle, inheritance, or method combination are
classes.  The raw ratio (222 structs, 59 classes) is explained by the product's
large protocol/event surface and is not evidence of TypeScript translation.
The 67 generics and 205 methods are concentrated exactly where open behavior
exists.

### 6. Repeated bug classes

The historical internal-diagnostic leaks had different sources but one root:
an infrastructure stream was routed into a user stream.  The current design
now separates:

- extension-authored stdout/stderr from loader/ASDF diagnostics;
- tool child output from process-wrapper diagnostics;
- frontend notice/status/warning/auth channels from CLI stderr;
- transport abort conditions from normalized user-visible errors.

The boundary functions and dedicated consumers make the route explicit; a new
macro or condition hierarchy would not strengthen it.  Existing regressions
assert absence of `setsid`, ASDF, SSL/SBCL, and internal `session>` text on the
user channel.  The audit therefore records this family as structurally closed,
not as another rewrite target.

## Post-audit source-set review

Part C2 originally audited 135 files.  Three production files were added by
later Goal 13 corrections.  Goal 14 then added six `cadr-core` convergence
owners, eight B1 interactive leaves, a net seven B2 selector owners, a net 29
B4 service owners, a net nine B5 bootstrap/RPC owners, a net twelve B6
interactive owners, and a net thirteen B7 reusable-TUI owners. B8 replaced
three mixed agent files with thirteen session, storage, and loop owners, for a
net ten files. B9 replaced the extension-host monolith with eight context, API,
registration, snapshot, rendering, provider, command, and lifecycle owners, for
a net seven files. B10 replaced four mixed AI files with seventeen capability,
transport, runtime, and support owners, for a net thirteen files. B11 replaced
five mixed provider/authentication owners with 25 protocol, authentication,
OAuth, declaration, registry, and runtime-projection owners, for a net twenty
files. The audit therefore follows the current 275 files rather than treating the old file set
as permanent:

| added file | required capability | Lisp-idiom disposition |
|---|---|---|
| `src/cadr-ai/crash.lisp` | shared pre-unwind fatal boundary, exact redaction and private crash log | keep the `handler-bind` boundary and redacted `print-object` methods; both directly encode the failure-site and secrecy invariants |
| `src/cadr-ai/{capabilities,transport,runtime,support}/*.lisp` | separate streaming/grammar/image capabilities, native transports, model/faux runtime, and closed support policies into exact owners | keep the existing value functions, stream protocol, and B3 compatibility delegates; B10 changed ownership only and introduced no new dispatch surface |
| `src/cadr-ai/{auth,oauth,providers}/*.lisp` | give every provider protocol, authentication mechanism, OAuth flow, declaration table, registry, and runtime projection one exact owner | keep external wire/tag dispatch explicit; B11 centralizes all static provider fields and callback identities in one validated declaration while leaving protocol implementations as cohesive native functions |
| `src/cadr-cli/crash.lisp` | apply the shared boundary to CLI entrypoints | keep as a thin boundary adapter; no owned polymorphic protocol exists |
| `src/cadr-cli/interactive/{transcript,status,footer,theme,images,clipboard,syntax,tool-render-session}.lisp` | give each interactive leaf service one exact output or data owner before selector convergence | keep the plain closed state/value functions; the extraction adds no polymorphic protocol and leaves selectors together until `selector-frame` owns their shared behavior |
| `src/cadr-cli/interactive/selectors/{common,sessions,tree,settings,auth,login-dialog,models,trust,fork}.lisp` | give selector framing and each selector family one exact owner | keep `selector-frame` as composition plus plain closed domain state; do not introduce an open hierarchy for fixed overlays |
| `src/cadr-cli/{support,settings,models,packages,extensions,sdk}/*.lisp` | replace eight mixed service files with 38 named domain owners, including the standalone config selector | keep the cohesive plain functions/classes in their existing package; the split changes ownership, not dispatch semantics |
| `src/cadr-cli/bootstrap/{tools,sessions,settings,auth,commands,main}.lisp` | separate tool construction, session lifecycle, settings/runtime, authentication, command dispatch, and the process entrypoint | keep command-domain functions explicit; `bootstrap/commands.lisp` is the sole mode-output injection owner and `bootstrap/main.lisp` stays a thin entrypoint |
| `src/cadr-cli/modes/rpc/{models,prompt-bash,sessions,commands,mode}.lisp` | separate RPC command domains from the JSONL loop | keep the closed RPC command handlers explicit; every domain emits only through the shared `rpc-write-object` wire sink |
| `src/cadr-cli/interactive/{state,status,user-bash,transcript,tool-rendering,entries,pending-messages,frame,extension-ui,autocomplete,themes,controller}.lisp` | separate direct bash rendering, interactive state, reducers, transcript projection, composition, extension bridges, and lifecycle control | keep the closed state records and explicit controller functions; composition and mutation now have named owners without inventing an open hierarchy |
| `src/cadr-cli/interactive/components/{loaders,countdown,armin,daxnuts,announcement}.lisp` | separate reusable loader primitives from independent animated and announcement components | keep each component's existing CLOS lifecycle while making its source owner exact |
| `src/cadr-tui/components/{markdown,image,tool-block,status,select-list}.lisp` | separate Markdown/image/tool/status/select rendering families | keep plain render functions and closed tool/select state; these are value transformations, not an open object protocol |
| `src/cadr-tui/composition/{protocol,text-box,rich-content,settings-list,loaders,root}.lisp` | separate the reusable component protocol from concrete content, settings, loader, and root orchestration | keep the existing CLOS protocol and load it before implementations; no new dispatch surface is needed |
| `src/cadr-tui/renderer/{terminal-protocol,virtual-terminal,alt-screen-search,lifecycle-input,main-screen,alt-screen}.lisp` | separate terminal protocols, deterministic virtual terminal, lifecycle/input, transcript search, and screen-specific rendering | keep terminal polymorphism and closed renderer state; main- and alt-screen algorithms remain explicit owners |
| `src/cadr-agent/{session,storage,loop}/*.lisp` | separate codecs, journals, migration/discovery/export, storage protocols/backends, lifecycle events, tool execution, turns, and loop entrypoints | keep serialized tags and mutable closed state explicit; retain CLOS only for the storage protocol and keep B3 time/atomic decisions delegated before extraction |
| `src/cadr-agent/summarization.lisp` | one non-bypassable owner for retry classification, abort-aware backoff, cache isolation, and fresh routing identity across every summary request | keep as a plain function over the closed agent/request protocol; `check-summarization-choke-point.sh` proves all compaction, split-turn, and branch call sites pass through it, so a macro or class would add syntax without another invariant |
| `src/cadr-agent/harness-events.lisp` | harness run lifecycle event bus (v0.84.2 baseline `harness/events.ts`) with buffered watch semantics | keep as a plain listener-registry class plus functions; the bus is a closed notification channel, not an open dispatch protocol |
| `src/cadr-agent/extensions/*.lisp` | separate context/UI contracts, API copying/events, registration, snapshots, rendering, provider projection, commands/templates, and lifecycle dispatch | keep the frozen macro/event surface explicit; preserve B3 cancellation and injected output ownership rather than introducing a second host abstraction |
| `src/cadr-tui/renderer/alt-screen-search.lisp` | transcript search corpus, matcher, and find-bar presentation (v0.84.2 baseline `alt-screen-search.ts`) | keep as closed data transforms; matches are value records, not an open component hierarchy |
| `src/cadr-tui/threads.lisp` | bounded join/forced-stop cleanup for terminal workers | keep as one function over SBCL's closed thread primitive; wrapping threads in a new class would not remove another invariant |
| `src/cadr-core/{package,threads,cancellation,atomic-file,redacted-print,time,paths}.lisp` | one bottom-layer owner for the repeated failure-safety decisions and the user-level path layout | keep as the dependency-free internal leaf approved in Goal 14 B3; product packages retain only compatibility delegation where required |

The module rows above apply to every Lisp file below each listed `src/`
system, not a sampled subset.  The executable gate recounts that source set,
requires all nine per-system file counts and all six audit axes, and fails
when a new production file lacks an explicit disposition.  The rewrite count
therefore remains one and the eight non-rewrite system decisions remain keep.

## Rewrite register

| id | before | decision and C2-B reason | expected delta | behavior gate |
|---|---|---|---|---|
| C2-R1 | `session.lisp:1946-2120`: five HTML/display helpers survive from the deleted server-rendered exporter; `content-block-display-text` is live but belongs to compaction rather than session export | **Implement — significant code reduction and removal of a duplicate implementation invariant.** Move the live formatter to `compaction.lisp`; keep `parse-session-skill-block` because TUI history projection calls it. | remove 159 lines from session, add 19 beside the compaction callers: net −140 physical lines and five unreachable functions | compaction and session-export tests, all full-screen/overlay snapshots, payload/wire fixtures, and the full deterministic suite remain byte-identical |
| C2-R2 | component containers append children with list `nconc`; long transcripts still incur measured layout cost | **Defer to C3.** This has a performance reason, but changing it without the C3 before/after trace would violate the measurement-first rule. | determined by C3 | C3 performance JSON plus unchanged presentation gates |
| C2-R3 | external tag dispatch could be represented as class methods | **Reject — no qualifying reason.** It would turn closed wire/schema sets into open dispatch and would not remove code or bugs. | none | n/a |
| C2-R4 | I/O `handler-case` sites could expose restarts uniformly | **Reject — no qualifying reason.** Most sites have no safe in-place recovery action; a restart name without a consumer is fake capability. | none | n/a |
| C2-R5 | selector/provider declarations could be generated by macros | **Reject — no qualifying reason.** Similar shapes carry distinct observable contracts, and generated control flow would be harder to audit. | none | n/a |

Only C2-R1 is authorized by the audit.  C2-R2 moves to the already mandated
performance phase; R3–R5 are explicitly kept to prevent “more idiomatic” from
becoming an unbounded rewrite excuse.
