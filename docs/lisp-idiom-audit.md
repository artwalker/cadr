# Common Lisp expression audit

## Scope and method

This audit is the Goal 13 Part C2-A gate.  It covers every production Lisp
module under `src/` before any C2 rewrite.  The question is not whether a form
looks idiomatic in isolation; it is whether a different Lisp construct would
eliminate a demonstrated bug class, remove a manual invariant, enable an
otherwise unavailable capability, or materially reduce code.

The audited tree contains 135 Lisp files and 98,464 physical lines.  The form
inventory below is syntactic evidence, not a quality score:

| system | files | lines | structs | classes | generics | methods | macros | `handler-case` | `handler-bind` | `restart-case` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `cadr-ai` | 27 | 23,131 | 44 | 13 | 6 | 34 | 1 | 59 | 0 | 0 |
| `cadr-agent` | 18 | 15,472 | 49 | 6 | 23 | 35 | 15 | 54 | 3 | 1 |
| `cadr-cli` | 42 | 37,892 | 62 | 16 | 6 | 24 | 0 | 74 | 2 | 0 |
| `cadr-tui` | 22 | 14,681 | 32 | 17 | 22 | 74 | 0 | 9 | 0 | 0 |
| `cadr-storage` | 2 | 31 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `cadr-server` | 11 | 2,783 | 7 | 5 | 10 | 14 | 0 | 20 | 0 | 0 |
| `cadr-protocol` | 5 | 1,427 | 4 | 0 | 0 | 0 | 0 | 5 | 0 | 0 |
| `cadr-evals` | 8 | 3,047 | 17 | 0 | 0 | 0 | 0 | 4 | 0 | 0 |

The audit distinguishes three kinds of dispatch that are easy to conflate:

1. polymorphism over owned objects, where CLOS can enforce a protocol;
2. discrimination over external JSON/wire tags, where `case` is the protocol;
3. finite state-machine transitions, where a closed `case` is clearer and
   safer than open method dispatch.

Only the first category is a CLOS candidate.

## Module audit

| module | manual invariants | dispatch and representation | boilerplate | conditions and restarts | disposition |
|---|---|---|---|---|---|
| `cadr-ai` | Provider streaming reducers centralize scratch/final content and preserve exact wire text; request cancellation is dynamically scoped at the transport boundary.  The invariants are covered by payload and delta-boundary tests. | Provider and content records are value objects, so structs are appropriate.  Most `case`/`cond` forms discriminate API names, JSON event tags, content types, or HTTP status, not extensible owned objects.  Stream classes/generics are already used where behavior is polymorphic. | Generated model/catalog forms must stay generated; a macro would hide rather than remove their source of truth. | The 59 `handler-case` sites translate transport, parse, and credential failures at abstraction boundaries.  There is no recoverable choice at the signaling site, so adding restarts would manufacture an unused API. | **Keep.** CLOS or restarts would add indirection without satisfying a C2-B reason. |
| `cadr-agent` | Agent/session list tails are centralized with head sentinels; storage owns entry/leaf invariants; extension event validation is centralized.  The remaining concrete defect is obsolete server-rendered HTML code left behind after the baseline exporter replaced it. | Real substitutability already uses generics: execution environments (`execution-env.lisp:3-35`), session storage/repositories (`storage.lisp:12-34,828-838`), and their memory/JSONL/SQLite methods.  Session entry/message tags remain serialized data and should not become an open class hierarchy. | The extension surface already uses `define-tool`, `define-command`, `define-event-hook`, provider, renderer, shortcut, and flag macros (`extensions.lisp:1819-1899`).  Additional macros would obscure the frozen export surface. | Tool failure is the one site with a useful local choice and already uses `restart-case` plus `handler-bind` (`loop.lisp:360-381`; `tool.lisp:230-294`).  Persistence/schema handlers translate corrupt external data and correctly unwind. | **One rewrite: C2-R1.** Delete five unreachable legacy HTML helpers and move the one live compaction formatter beside its only callers; keep all other structures. |
| `cadr-cli` | Frontend notices, statuses, warnings, auth URLs, and prompts are distinct consumers in `main.lisp:2437-2452`.  Extension source output and infrastructure diagnostics use separate dynamic stream boundaries (`extensions.lisp:474-510,562-590,653-660`).  This is the structural fix for the former `setsid`/ASDF/`session>` leak family. | SDK lifecycle objects use classes/generics (`sdk.lisp:5-759`; `sdk-services.lisp:646-1210`).  Selector/editor/runtime state is closed mutable data and correctly remains structs plus explicit state-machine cases. | Similar selector constructors are not semantically identical: their search, pagination, cancellation, and payload rules differ.  A macro would save declarations while coupling unrelated observable contracts. | CLI handlers mostly convert filesystem, subprocess, configuration, and extension failures into stable user/wire outcomes.  No caller can choose a meaningful restart at those I/O sites. | **Keep.** The known diagnostic bug class is already prevented by channel/stream ownership rather than more exception syntax. |
| `cadr-tui` | Layout, focus, cache invalidation, disposal, and rendering are enforced by component composition rather than hand-spliced screen rows (`composition.lisp:6-112,129-338,1371-1678`).  Terminal lifecycle is owned by the terminal protocol. | This is the strongest CLOS use in the tree: component inheritance and generic rendering/event/disposal, plus process/virtual terminal methods (`renderer.lisp:3-230`; `terminal.lisp:218-817`).  Editor, decoder, fuzzy, undo, and key state are compact value/state records and remain structs. | No repeated constructor/validator group meets the significant-reduction threshold without hiding terminal semantics. | Nine handlers sit at terminal capability and image/decoder boundaries.  These operations have fallback values, not interactive recovery choices. | **Keep for C2.** Container append/layout cost is a measured C3 performance concern, not an idiom-only rewrite. |
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
classes.  The raw ratio (215 structs, 57 classes) is explained by the product's
large protocol/event surface and is not evidence of TypeScript translation.
The 67 generics and 181 methods are concentrated exactly where open behavior
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
