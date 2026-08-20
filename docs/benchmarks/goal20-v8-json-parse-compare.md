# Goal 20 — V8 `JSON.parse` vs cadr `parse-json`

One page. Design source is V8 13.6 (`src/json/json-parser.h`,
`json-parser.cc`), not sprof of the Lisp walker. Not FFI. Not intern
grow. Not empty SWAR. Not G.17 `met`.

Node `JSON.parse` is `v8::JSON::Parse` → `JsonParser<Char>::Parse`.
The `Char` template is the sequential source: one-byte
`SeqOneByteString` for ASCII JSON, two-byte otherwise. Property
scan is a window (`JsonString` start/length/escape/internalize),
not a fresh JS string per key.

## What V8 does (hot object)

1. One-pass recursive descent (`ParseJsonValueRecursive`).
2. Object keys + values land on a `property_stack_`
   (`SmallVector<JsonProperty, 16>`).
3. `BuildJsonObject` allocates **one** `JSObject` with a
   hidden-class `Map` (`JSDataObjectBuilder`, optional **map
   feedback** from the previous sibling so the same shape reuses
   the descriptor array). Sequential named properties. Dictionary
   / `NumberDictionary` only when index-elements are sparse.
4. Numbers: Smi or HeapNumber (IEEE double), not exact rationals.
5. Short ASCII strings (`length < 10`) and property names are
   internalized in the isolate string table.

That is “parse fills the target type”. The stack is a scratch
window; the result is not an EQUAL hash copied from the stack.

## What cadr `parse-json` had

`parse-json-source` / `parse-json-octets` already one-pass
descent, interned closed ASCII keys/values, unescaped window
copy. Then `parse-object` stacked 8 pairs and **always**
`MAKE-HASH-TABLE :test EQUAL` + `SETF GETHASH` (spill at 8 to
`:size 16`). That is EQUAL-hash-then-copy, V8 dictionary mode
for every SSE event.

`session_load` `parse-session-record-octets` already fills
`session-entry` slots from the octet window; nested arguments
are `(:json-object . pairs)`. Leftover there is the key scan
(`OCTET-U32-LE`), not this hash. Same family: sequential
properties, not a third parser.

SSE mistral/codex: `utf8-string` of `data:` then `parse-json` →
hash → `json-get`. json-get already walked pairs.

## Lisp encoding (this knife)

V8 fast properties ≈ ordered named slots. Lisp already has
`(:json-object k v …)` and `json-get` / `write-json-value`.

- ≤16 keys (V8 `SmallVector<T, 16>`): keep the pair list.
  No EQUAL table, no second copy.
- \>16 keys: spill to EQUAL hash (V8 dictionary / large Map).
  Model catalogs stay hash.

`json-object` (builder) is unchanged (hash). Observable
stringify bytes stay sorted keys. Not intern expand.

## Deliberately not this knife

- FFI V8 / simdjson / yyjson.
- Growing the intern tables.
- Empty SWAR on the session key scan.
- Changing JSON number values to doubles (observable
  rationals / stringify).
- mmap.

Remesure: `provider_mistral`, `provider_codex`, `session_load`
on Friend-MachineD. Revert if worse.
