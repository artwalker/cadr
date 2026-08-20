# Goal 20 — V8 `ParseJsonObject` / `ScanJsonString` vs cadr `parse-message`

Source: V8 13.6 `src/json/json-parser.h` (`JsonString`, `JsonProperty`,
`SmallVector<T,16>`, `ParseJsonObject`, `ScanJsonString`,
`BuildJsonObject`, `MakeString`). Not FFI. Not HiddenClass/Zone.
Not G.17.

## What V8 does less

`ScanJsonString` returns `{start, length, has_escape, internalize}` —
no heap `String` until `MakeString` inside `BuildJsonObject`.
Property keys/values sit on a stack `SmallVector<JsonProperty,16>`.
`ParseJsonObject` then allocates **one** JSObject.

cadr (ISO-kept walker @ `385542aab`): `parse-string-value` intern-or-copies
on every kept value during the scan. `parse-message` heap-allocates a
`session-json-message`, then `finalize-session-entry` allocates the
typed cadr-ai message (`message-from-json`). Two heap objects per
message; the bag is not the target type.

## Knife

Zero bag: stack locals (role/content/timestamp/usage/extra) then one
`message-from-parts` at `}` — Lisp encoding of SmallVector then
BuildJsonObject. Not bag reuse (`cc29bec17` lost: 1857→2015 µs).
Not intern grow. Not COPY-UNESCAPED rewrite. Not FFI.

`message-from-json` is identity on already-typed messages so
`journal_append` (pairing) can re-enter.

Win condition: Friend-MachineD n=5 `session_load` cadr µs **< ~1857**.
Revert if not.
