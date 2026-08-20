# Goal 20 — split `PARSE-SESSION-RECORD-OCTETS` inners (shipped labels)

Inclusive `get-internal-real-time` around **shipped** labels in
`parse-session-record-octets` (40× `load-session` on pairing
`test/fixtures/goal20-paired-paths/session.jsonl`). Special
`*parse-session-split-ticks*` bound only in the capture script;
production walker has no timer. Not wall-fraction. Not G.17.

This-host wall ~1494 µs/load (Friend-MachineD pairing cadr ~1879 µs).
Children overlap parents (`parse-string-value` ⊆ `parse-message` ⊆
`put-entry-field`; `parse-content-block` ⊆ `parse-message`).

| inner | inclusive µs / load | V8 `JsonParser` |
|---|---:|---|
| `put-entry-field` | 897 | named properties / `BuildJsonObject` |
| `parse-message` | 498 | `ParseJsonObject` (message) |
| `parse-string-value` | 399 | `ParseString` / `MakeString` |
| `parse-content-block` | 199 | `ParseJsonObject` (content block) |
| `parse-usage` | 0 | `ParseJsonObject` (usage; inside message, <1 µs/call on this clock) |
| `parse-generic` | 0 | `ParseJsonValue` (cold) |

Previous table (701 / 601 / 301 / 100) was **not** timer output — it
was exact fractions of wall 1402.8 µs. Discarded.

sprof (older, still directional): `PARSE-CONTENT-BLOCK` ~22–32% total
on load/journal; `PARSE-STRING-VALUE` ~7–12% total; `COPY-UNESCAPED`
~2–5% self. Forbidden micro-knives: SCAN-KEY macrolet, length-case /
key-tag `case` redo of `789bec858`, intern grow, COPY-UNESCAPED
kernel rewrite, DIGITS, ISO quote walk, message bag reuse,
stack-local typed message, delayed ParseString spans, content-block
scratch reuse.

## Knife (falsified) — lexer token reuse

`parse-content-block` 199 µs: one `session-json-block` scratch per
walker; `finish-block` copies to typed content. Friend-MachineD n=5
@ `767b4c452`: load cadr **1879→2083 µs** (worse; samples 1916–2629).
Withdrawn. Do not redo content-block bag reuse. Not intern. Not FFI.

Honest split numbers above stay. Not G.17 `met`.

## Next knife (adjudication 2026-08-21)

Prefer **A** per-load string arena / bump (no COPY-UNESCAPED kernel
rewrite; Friend-MachineD; &lt;~50 µs noise → revert) or **D** exact-length
/`svref` content arrays (not bag reuse). Default-reject B key-tag
`case`; reject C if it becomes 三连 #2; E `tagbody` last. Lazy
octet-span needs a new ruling. See leftover md + `docs/adjudications.md`.

## Knife — gperf unique-prefix dispatch on `put-entry-field`

Hottest remaining parent: `put-entry-field` 897 µs (includes
`parse-message`). Closed set of record keys; first 4 bytes as
little-endian u32 (gperf unique prefix). Only `fromId`/`fromHook`
share a prefix (`from`). Not `case n` length-case (`789bec858`).
Not bag reuse. Not intern grow.

Win: Friend-MachineD n=5 `session_load` cadr **< ~1879 µs**. Revert
if not.
