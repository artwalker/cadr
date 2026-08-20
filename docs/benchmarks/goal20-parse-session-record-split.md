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

## Knife (falsified) — quote-scan high-byte + check-less ASCII copier

`108d9184a`: value quote-scan accumulated `high-byte-p`;
unescaped ASCII skipped the classify pass and used
`copy-unescaped-ascii-json-octets` (fill loop byte-identical
to the classified ASCII arm). Friend-MachineD n=5: load cadr
**1879→2045 µs** (worse; samples 1978–2222). Withdrawn.
Do not redo this scan+copier split. Fill kernel was never
rewritten. Not intern. Not FFI.

## Knife (in flight) — content compact-prefix

Type-first compact prefixes (`{"type":"text","text":` /
`{"type":"thinking","thinking":` /
`{"type":"toolCall","id":`) fill typed content without
`session-json-block`. Spaces / key order / escaped type rewind
to the generic walker. Not bag reuse. Not knife 1.

Friend-MachineD n=5: load cadr **1879→1829 µs** (keep).
Samples 1731–1868. Not bag reuse. Not intern. Not FFI.

## Knife — put-entry unique-prefix u32

`put-entry-field` jumps on first 4 little-endian bytes; `fromId` /
`fromHook` share `from`. Not length-case (`789bec858`).
Friend-MachineD n=5: load cadr **1829→1821 µs** (keep).
Not intern. Not FFI. Ceiling not lowered.

## Knife — put-message-field first-byte

Proposal 3. `case` on the first key byte, then the small
same-initial-letter set. Not length-case. Friend-MachineD
n=5: load cadr **1821→1763 µs** (keep). Ceiling not lowered.

## Next knife (adjudication 2026-08-21 item 11)

**Knife 1 remesured and withdrawn.** Knife 2 (content
compact-prefix) is the next keep/revert. Do not merge with gperf
`put-entry`.

**Knife 2 after knife 1 keeps:** content compact-prefix fast
path + generic fallback (not bag reuse). See leftover md +
`docs/adjudications.md`.

DeepSeek A/D and gperf `put-entry` remesure are **not** merged
with knife 1.

## Knife — gperf unique-prefix dispatch on `put-entry-field`

Hottest remaining parent: `put-entry-field` 897 µs (includes
`parse-message`). Closed set of record keys; first 4 bytes as
little-endian u32 (gperf unique prefix). Only `fromId`/`fromHook`
share a prefix (`from`). Not `case n` length-case (`789bec858`).
Not bag reuse. Not intern grow.

Win: Friend-MachineD n=5 `session_load` cadr **< ~1879 µs**. Revert
if not.
