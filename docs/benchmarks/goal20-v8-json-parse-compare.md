# Goal 20 — V8 `JSON.parse` vs cadr JSON / session load

One page. Design source is V8 13.6 (`src/json/json-parser.h`,
`json-parser.cc`) and pi `loadEntriesFromFile` /
`SessionManager.open` (`session-manager.ts`). Not FFI. Not intern
grow. Not empty SWAR. Not G.17 `met`.

## What V8 does (hot object)

1. One-pass recursive descent (`ParseJsonValueRecursive`).
2. Object keys + values land on a `property_stack_`
   (`SmallVector<JsonProperty, 16>`).
3. `BuildJsonObject` allocates **one** `JSObject` with sequential
   named properties (hidden-class `Map`, optional map feedback).
   Dictionary only for large/sparse objects.
4. Numbers: Smi or HeapNumber. Short ASCII names internalized.

Parse fills the target type. The SmallVector is scratch, not an
EQUAL hash copied after the scan.

## What pi `loadEntriesFromFile` does

1MiB `readSync` into a `Buffer`, `StringDecoder` → pending
string, `indexOf("\n")`, `pending.slice`, `JSON.parse(line)` as
`FileEntry`. Header check: `type === "session"` and `id` string.
That is one JSON.parse per line into a JS object (V8 sequential
properties), then the array of FileEntry.

cadr `load-session` / `read-session-objects` already copies the
1MiB octet buffer + LF scan. `parse-session-record-octets` fills
`session-entry` slots from the window (not `uiop:split-string`).
Aligned passes. Leftover vs V8 is the walker itself
(`SCAN-KEY` / `SKIP-SPACE` / `PARSE-STRING-VALUE`) plus nested
tool-call arguments.

## `a78ee0171` — cons plist in public `parse-json` — withdrawn

Lisp encoding tried: `(:json-object . cons-plist)` for ≤16 keys
from **public** `parse-json` / `parse-json-octets`. Friend-MachineD
n=5, host Friend-MachineD, git `a78ee0171`:

| metric | cadr µs | pi µs | ratio | ledger before |
|---|---:|---:|---:|---:|
| `session_pipeline.session_load` | 3447.7 | 1860.5 | **1.85×** | 1.83× (2877.9 / 1572.6) |
| `storage_journal.journal_read` | 3923.0 | 1516.7 | **2.59×** | 1.62× (2667.1 / 1647.0) |
| `provider_mistral.stream_roundtrip` | 1678.1 | 2077.5 | **0.81×** | 1.28× |
| `provider_codex.stream_roundtrip` | 1289.8 | 1657.9 | **0.78×** | 0.79× (prev 1.08×) |

Reverted `1c8e7ef6f`. SSE won; load/journal lost. Why: `json-get`
linear scan of a cons spine vs EQUAL hash on journal objects, plus
dual-representation fallout (`json-as-hash-table` copies at HTTP /
file edges). Cons plist is not V8's sequential property store.

Public `parse-json` stays EQUAL hash after the revert.

## Lisp encoding (this knife)

V8 sequential properties ≈ a **simple-vector of k,v,k,v**, not a
cons plist and not a public parse-json type change.

`parse-session-record-octets` `parse-arguments-object` (nested
session/journal JSON, tool-call arguments) fills
`(:json-object . simple-vector)`. `json-get` / `json-present-p` /
`json-map-entries` / stringify walk `svref`. Public `parse-json`
unchanged.

Empty object: `(cons :json-object (vector))`. Not intern grow.
Not FFI. Ceiling not lowered.

## Deliberately not this knife

- Changing public `parse-json` return type again.
- FFI V8 / simdjson / yyjson.
- Growing intern tables.
- Empty SWAR on `SCAN-KEY`.
- mmap.

Remesure: `session_load` / `journal_read` on Friend-MachineD.
Revert if worse than the ledger at `1c8e7ef6f` (1.83× / 1.62×).
