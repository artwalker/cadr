# Goal 20 Part K6 — cadr-agent

37 Lisp files / 16,281 lines at start. Five export-html assets
untouched (n/a, byte-pinned).

## 14 no-rewrite kept

package, conditions, summarization, resources, truncate,
loop/events, extensions/{api,commands,lifecycle,providers},
session/{discovery,export-html}, storage/{jsonl,protocol}.

wc and I duties undrifted. protocol.lisp gained
`model-plist-from-entry` (shared current-model owner used by
harness and sqlite). That is the I hole of those two files, not
a re-open of protocol's no-rewrite verdict (the protocol file
was already the shared storage owner).

## 23 needs-rewrite

| File | I0 |
|---|---|
| branch-summarization | `llm-passthrough-message-p` / `agent-message-to-llm` |
| compaction | one reverse walk; `compaction-field` |
| execution-env | `call-signaled-operation` owns abort/classify; exists-p / remove / temps use it |
| extensions/context | `assert-extension-deliver-as`; dead `(or … nil)` gone |
| extensions/registration | register-* owns `&key`; define-* keeps Goal 12 frozen lambda lists |
| extensions/rendering | `render-extension-named` |
| extensions/snapshot | `extension-definition-bundle` generic |
| file-mutation-queue | `with-` macro over `call-with-file-mutation-queue` |
| harness-events | push / nreverse on watch flush |
| loop/agent-loop | early terminal exit, no cond pyramid |
| loop/tool-execution | `map-into` |
| loop/turns | abort-p keyword, no one-field plist |
| messages | `agent-message-to-llm` generic |
| proxy | `nappend-string` |
| runtime | `agent-queue-messages` / `set-agent-queue-messages` |
| schema | `with-present` owns every present-p bind; `when-present` wraps it |
| session/codec | push/nreverse diagnostics; `usage-cost-amount` |
| session/journal | `put-session-details-and-usage` |
| session/migration | `case` on interned type |
| sqlite-storage | one model/level bind; `model-plist-from-entry` |
| storage/harness | same `model-plist-from-entry` |
| storage/memory | tail pointer |
| tool | drop `(or content nil)` |

## K0.2 macros

17 macros in `src/`: 15 in `extensions/registration.lisp`, one
`define-redacted-print-object` (`cadr-core`), one
`define-provider-constructor` (`cadr-ai`).

The 15 agent macros are the **extension authoring surface**.
They used to re-list every keyword of the matching
`register-*` function (two owners, no compile-time work).
K6 makes `register-*` the keyword owner; the macros `&rest`
onto that list. That is why this package "crossed the line":
it already had an authoring DSL. The failure was treating the
DSL as a second copy of the function lambda list.

**K8 (`cadr-tui`)** counterpart: `(nth …)` on display lists
(41 sites). The migration is the same idea as
`context-estimated-tokens` and `map-into` — walk the cons, do
not re-index. Macros help only where a widget repeats a
binding pattern (with-frame / with-clip). Do not invent 15
define-* macros for TUI; invent `nth` replacements and a
handful of with- macros.

**K9 (`cadr-cli`)** counterpart: 246 `string=` sites. Wire
names stay strings. Internal enums should intern once (the
migration.lisp pattern) or `ecase` on keywords. The authoring
macros do not migrate to CLI selectors — those have distinct
observable contracts (Part I). Each selector Lisp-ifies
itself; they do not share a define-selector macro.

**cadr-core / cadr-ai macros** are print-object and provider
constructor DSLs. They already have compile-time effect.
Leave them.

## Pairing

Several agent files have H cells. Req 8 Date.now() is not
used. Existing agent FiveAM is the before/after.

Blocked: 0. FiveAM 18725 → 18738 → 18748. derive 680/680.
`--all` is the known load-sensitive instrument; N_i untouched.

## H class

Booked class from tip `docs/benchmarks/goal20-unpaired-paths.json` via
`scripts/goal20-unpaired-paths.py` (longest prefix). Refreshed 2026-09-07
against denom 297 / 133658 (`needs-pair=0`, `pairable-uncovered=0`).
Not 148 wall-clock pairs. Historical K-booking `pairable-uncovered` /
`pending H pair` sentences are superseded by this list.

- `paired` (28): `branch-summarization.lisp`, `compaction.lisp`, `conditions.lisp`, `execution-env.lisp`, `file-mutation-queue.lisp`, `harness-events.lisp`, `loop/agent-loop.lisp`, `loop/events.lisp`, `loop/tool-execution.lisp`, `loop/turns.lisp`, `messages.lisp`, `proxy.lisp`, `resources.lisp`, `runtime.lisp`, `schema.lisp`, `session/codec.lisp`, `session/discovery.lisp`, `session/export-html.lisp`, `session/journal.lisp`, `session/migration.lisp`, `sqlite-storage.lisp`, `storage/harness.lisp`, `storage/jsonl.lisp`, `storage/memory.lisp`, `storage/protocol.lisp`, `summarization.lisp`, `tool.lisp`, `truncate.lisp`.
  Dual-ref: H cell vs pi + K FiveAM/render-diff vs previous cadr.
- `covered-as-callee` (1): `package.lisp`.
  On a named paired thunk; no own bench.
- `unpairable` (8): `extensions/api.lisp`, `extensions/commands.lisp`, `extensions/context.lisp`, `extensions/lifecycle.lisp`, `extensions/providers.lisp`, `extensions/registration.lisp`, `extensions/rendering.lisp`, `extensions/snapshot.lisp`.
  Single-ref vs previous cadr; do not invent a pi pair.

