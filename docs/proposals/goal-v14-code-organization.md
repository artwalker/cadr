# Goal 14 Part B proposal — organization batches

Status: **approved with ordering correction (2026-08-03)**.  The user approved
all eleven batches, the internal `cadr-core` leaf, and the validated provider
declaration schema.  B3 is executed first; every repeated decision named by the
audit must converge before, or in the same commit as, any related file split.

The source audit is [`docs/code-organization.md`](../code-organization.md).
Every batch below is behavior-preserving: package exports, extension export SHA,
34-event SHA, full-screen/overlay SHA, payload/wire/session fixtures, exit codes,
and user-visible bytes remain unchanged.  A batch that cannot satisfy that rule
is reverted, not normalized into a new baseline.

## 1. Ranked sequence

The order is benefit/risk, not subsystem aesthetics.  The approved correction
puts the smallest cross-system convergence batch first so later extraction
cannot fossilize duplicated decisions into more files.  High-coupling/frozen
surfaces still come last.

| Batch | Current files | Expected result | Export/freeze surface | ASDF/load-order risk | Required behavior proof |
|---|---|---|---|---|---|
| B3 — shared failure primitives | identical thread helpers in `ai/utilities`, `tui/threads`, `cli/utilities`; atomic writers/cancellation/printers/time call sites listed in the audit | Add a bottom-layer `cadr-core` system with narrowly named `threads`, `cancellation`, `atomic-file`, `redacted-print`, and `time` modules; retain package-local compatibility wrappers only where internal names are already referenced | New internal ASDF system, no public Cadr/extension API | Medium: all existing systems depend downward on the leaf; no existing edge reverses and TUI still does not depend on AI | Source gates reject unannotated cleanup joins/duplicate metric implementations; private-mode and secret-print tests; cancellation/exit tests; package export sets unchanged |
| B1 — interactive leaf services | `cli/interactive-services.lisp` | Extract transcript/status, footer, theme detection, clipboard, images, syntax, and tool-render-session into 8 named files; selectors remain temporarily in the source file | No public or extension export change | Low-medium: helpers must precede consumers | Existing semantic-theme, image, syntax, footer, transcript, tool, base-screen and overlay gates byte-identical; clean ASDF compile |
| B2 — selector families | remaining `cli/interactive-services.lisp` | First establish one composable `selector-frame` owner, then extract `selectors/{common,sessions,tree,settings,auth,models,trust,fork}.lisp` (8) | No export change; A0 auth behavior is frozen | Medium: frame/component definitions must load before all selector families | All 15 overlay SHAs, independent geometry assertions, navigation tests, A0 title/border/cursor/status tests unchanged |
| B4 — CLI domain services | `core-support`, `utilities` remainder, `settings`, `model-services`, `package-manager`, `extensions`, `sdk-services`, `sdk` | 37 named support/settings/models/packages/extensions/SDK files from 8 mixed files (the original prose said 36, while the approved explicit map totals 37) | SDK and extension behavior frozen; extension export SHA must remain exact | Medium-high: types/managers before facades/controllers; no new symbol export | SDK, package, settings/trust, model/auth, extension loader/output, install, and full deterministic gates |
| B5 — CLI commands and RPC | `main.lisp`, `modes/rpc/mode.lisp` | 6 bootstrap/command files and 5 RPC domain files | CLI/RPC wire frozen; no extension export change | High: current command functions have broad internal references and the entry point must load last | CLI option/command fixtures, RPC JSONL/wire/process fixtures, session workflows, exit/resume/export output, clean build |
| B6 — interactive controller | `cli/tui.lisp`, `interactive-components.lisp` | 11 interactive state/render/controller files and 5 standalone component files | TUI observable output and extension UI surface frozen | High: state types first, renderers next, controller last; circular state/render references are the main risk | Every base-screen/overlay SHA plus independent geometry assertions, PTY/faux busy-input/abort tests, extension UI fixtures |
| B7 — reusable TUI internals | `tui/components.lisp`, `composition.lisp`, `renderer.lisp` | 16 files under `components/`, `composition/`, and `renderer/` | Public `cadr-tui` exports frozen | High: CLOS classes/generics before methods; renderer protocol before real/virtual implementations | Entire TUI suite, screen/overlay SHA, mouse/scroll/performance gates, export symbol set, fresh compile |
| B8 — agent session/loop storage | `agent/session.lisp`, `storage.lisp`, `loop.lisp` | 13 files under `session/`, `storage/`, and `loop/` | Session format, event order, tool result, and package exports frozen | Medium-high: envelopes/protocols before backends; turn/tool functions before loop | Session v1-v3, JSONL/SQLite, queue/retry/tool lifecycle, event sequence, export HTML, wire fixtures |
| B9 — extension host | `agent/extensions.lisp` | 8 context/API/registration/snapshot/render/provider/command/lifecycle files | **Touches the frozen implementation behind** extension export/event surfaces; both SHAs must remain exact | High: macros before examples/use, snapshots before host, lifecycle after validation | Export SHA `61eb…f18`, event SHA `12f7…87a`, all 34 dispatch tests, legacy source compatibility, every ported example |
| B10 — AI support/runtime/transport | `ai/capabilities.lisp`, `http.lisp`, `models-runtime.lisp`, `utilities.lisp` remainder | 16 streaming/grammar/proxy/image/runtime/faux/transport/support files | Provider payload/events and public AI exports frozen | Medium-high: JSON/event values before transport/runtime; WebSocket/HTTP dispatch order retained | JSON/SSE/HTTP/abort/TLS/AWS stream, faux provider, capability matrix, payload/event fixtures, live entry unchanged |
| B11 — provider/auth organization | `ai/oauth-flows.lisp`, `oauth.lisp`, `provider-auth.lisp`, `providers/independent.lisp`, `registry.lisp` | 25 OAuth/auth/protocol/declaration/runtime-projection files | Highest-risk provider and credential surface; no public/export behavior change | High: OAuth metadata/auth helpers before registry; protocol methods before runtime construction | Generated 38-provider × every-field baseline matrix, provider × thinking payload/events, deterministic OAuth, secret non-leak, existing live entry |

Each row is one independently committed/revertible batch.  B4 and later may be
split into smaller commits inside the row only when every commit independently
loads and passes its focused gates; the full deterministic suite runs before
the row is declared complete.

The resulting execution order is **B3 -> B1 -> B2 -> B4 -> B5 -> B6 -> B7 ->
B8 -> B9 -> B10 -> B11**.

## 1.1 Convergence-before-split audit

| Batch | Repeated decision touching the batch | Mandatory order inside the batch |
|---|---|---|
| B3 | bounded cleanup, cancellation, secret-safe printing, atomic persistence, UTC time/ID formatting | Define and test the five `cadr-core` owners first, then replace every listed handwritten implementation with delegation; compatibility wrappers contain no policy. |
| B1 | presentation/output ownership at transcript, status, footer, and tool-render boundaries | Name the user-facing sinks and preserve the existing infrastructure boundary before extracting leaf services; extracted files consume those owners rather than creating local writers. |
| B2 | selector frame semantics | Build and behavior-lock `selector-frame` first.  It owns border, title, input, viewport/count, help, and wrap navigation; the eight domain files supply only items and callbacks. |
| B4 | infrastructure output, atomic settings/auth persistence, secret printing, JavaScript length metrics | Reuse B3 file/redaction primitives; establish CLI extension/infrastructure sinks and replace the duplicate CLI UTF-16 implementation before splitting services. |
| B5 | command/RPC output ownership and timestamps | Reuse the B3 time primitive and B4 sinks before command/RPC extraction; no extracted command may write around its mode-owned sink. |
| B6 | interactive output ownership and selector composition | Reuse B2 `selector-frame` and B4 sinks before controller extraction; render/state files do not rebuild notices, URL-launch capture, or selector chrome. |
| B7 | TUI cancellation and cleanup | B3 already owns these decisions; reusable TUI files delegate to that owner before they move.  No new local token/worker policy is introduced. |
| B8 | session time/ID and atomic migration | B3 owns both before session/storage/loop extraction; the B8 files retain only domain serialization and lifecycle policy. |
| B9 | extension cancellation, redacted values, and extension-output ownership | B3 and B4 owners are prerequisites; migrate any remaining adapter before splitting the host.  Macro/export/event SHAs remain exact. |
| B10 | HTTP cancellation, transport diagnostics, request redaction, and time | B3 owns cancellation/redaction/time first; define the AI infrastructure sink before transport extraction, preserving the existing fatal and network-error copy. |
| B11 | provider identity/auth metadata | Generate the fixed-baseline 38-provider field matrix first, then validate one declaration owner, then split protocols/auth/runtime projection.  No field is sourced from the current Cadr table as authority. |

B11 also starts with an explicit freeze audit.  The historical whole-tree
`src/cadr-ai` freeze ended through approved Goal 13 changes; public exports,
wire/payload behavior, extension export SHA, and the 34-event SHA remain
frozen.  If that conclusion is contradicted by current history or architecture
when B11 begins, B11 stops for a new ruling.

## 2. Decision requested: shared `cadr-core` leaf

Approve or reject B3 separately.  The alternatives are worse:

- Keeping three byte-identical cleanup functions preserves the exact bug class
  Goal 14 was created to eliminate.
- Putting the primitive in `cadr-ai` makes `cadr-tui` depend on AI and destroys a
  deliberately protected boundary.
- A macro copied into three packages still has three owners and no stronger
  safety property.

The proposed leaf depends only on SBCL/UIOP and contains no product policy,
provider code, TUI code, third-party dependency, or observable mechanism.  It
adds downward dependencies only; existing system-to-system directions remain
unchanged.  If the user rejects the new system, B3 is removed and the audit will
retain the duplication as an explicit unresolved risk rather than hiding it.

## 3. Decision requested: provider declaration schema

Approve or reject the B11 declaration convergence separately.  Approval means:

- all 38 existing providers and only their existing fields/callbacks move into
  one validated declaration schema;
- protocol implementations split by actual wire protocol, not by brand;
- no new provider, auth method, endpoint, scope, environment source, model, or
  fallback is authorized;
- the fixed-baseline field fixture is written first and must fail before the
  reorganization if any current value is wrong.

Rejected alternatives:

- One file per provider copies TypeScript's module shape without reducing code
  or decisions.
- Keeping callback `case` trees separate from the declaration table retains the
  exact metadata drift that produced the Anthropic bug.
- A generic universal request builder would erase protocol-specific payload
  semantics and weaken the existing payload fixtures.

## 4. Rollback and stop rules

- Every batch is a standalone commit; rollback is a plain revert of that batch,
  never a partial compatibility shim.
- Clean builds use a new temporary HOME/ASDF cache so old FASLs cannot conceal a
  load-order mistake.
- Any A0-external observable byte change, new export, changed event SHA, needed
  dependency, or false cohesion boundary stops the batch and returns for user
  decision.
- No threshold-based file splitting is authorized.  The 273-file distribution
  is a planning consequence of the named boundaries, not a target to hit.

Part C must not start until the user approves the sequence and separately rules
on B3 and B11.
