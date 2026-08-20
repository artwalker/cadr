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

## Knife (falsified)

Zero bag: stack locals then one `message-from-parts` at `}` —
Lisp encoding of SmallVector then BuildJsonObject. Not bag reuse
(`cc29bec17` lost: 1857→2015 µs). Friend-MachineD n=5 @ `8530c25a1`:
load cadr **1857→1917 µs** (1.27×→1.13× is pi jitter; cadr µs worse).
Withdrawn. Do not redo stack-local parse-time typed fill.
Not intern. Not FFI. Ceiling not lowered. Not G.17.

## Knife — ParseString delayed materialization @ `1ec2dacf2`

`scan-json-string` records `{start, length, escaped}` (packed fixnum,
tag bit 45). No intern / COPY-UNESCAPED during the property walk.
`make-json-string` (V8 `MakeString`) runs at object close:
`parse-message` after `}`, `finish-block` for content blocks.
Existing intern / `copy-unescaped-json-octets` / decode-escaped —
not a COPY-UNESCAPED rewrite. Not bag reuse. Not stack-local typed
fill. Not intern grow. Not FFI.

Win: Friend-MachineD n=5 `session_load` cadr µs **< ~1857**. Revert
if not.
