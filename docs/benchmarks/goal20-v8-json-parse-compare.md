# Goal 20 — V8 `JSON.parse` vs cadr JSON / session load

One page. Design source is V8 13.6 (`src/json/json-parser.h`,
`json-parser.cc`) and pi `loadEntriesFromFile` /
`SessionManager.open`. Not FFI. Not intern grow. Not empty SWAR.
Not G.17 `met`.

## What V8 does (hot object)

One-pass descent. Keys/values on `SmallVector<JsonProperty, 16>`.
`BuildJsonObject` allocates **one** JSObject with sequential named
properties (hidden-class Map). Dictionary only for large/sparse.
Short ASCII names internalized. The stack is scratch, not an EQUAL
hash copied after the scan.

## What pi `loadEntriesFromFile` does

1MiB `readSync` → `StringDecoder` pending string → `indexOf("\n")`
→ `JSON.parse(line)` as `FileEntry`. Header: `type === "session"`
and `id` string. One V8 object per line.

cadr `load-session` / `read-session-objects`: 1MiB octet buffer +
LF scan. `parse-session-record-octets` fills `session-entry` slots
from the window. Passes are aligned. Leftover is the walker
(`SCAN-KEY` / `SKIP-SPACE` / `PARSE-STRING-VALUE` / nested
arguments) vs V8 `JSON.parse`.

## Withdrawn encodings (Friend-MachineD n=5)

Ledger before both knives (`65623892a` / `1c8e7ef6f`):
`session_load` 1.83× (2877.9 / 1572.6 µs), `journal_read` 1.62×
(2667.1 / 1647.0 µs).

### `a78ee0171` — cons plist in **public** `parse-json`

| metric | cadr µs | pi µs | ratio | vs ledger |
|---|---:|---:|---:|---|
| `session_load` | 3447.7 | 1860.5 | 1.85× | worse |
| `journal_read` | 3923.0 | 1516.7 | **2.59×** | worse |
| `provider_mistral` | 1678.1 | 2077.5 | 0.81× | better |
| `provider_codex` | 1289.8 | 1657.9 | 0.78× | ~flat |

Reverted `1c8e7ef6f`. SSE won; load/journal lost. Cause: `json-get`
linear scan of a cons spine vs EQUAL hash, plus dual-representation
fallout (`json-as-hash-table` copies). Cons plist is not V8's
property store. Public `parse-json` stays EQUAL hash.

### `28e0eae06` — `simple-vector` k,v in session walker only

Public `parse-json` unchanged. Nested session/journal objects filled
`(:json-object . simple-vector)`.

| metric | cadr µs | pi µs | ratio | cadr before |
|---|---:|---:|---:|---:|
| `session_load` | 3109.5 | 2357.1 | 1.32× | 2877.9 (cadr slower) |
| `journal_read` | 3153.2 | 1760.5 | 1.79× | 2667.1 (cadr slower) |

Reverted `51e6e0b8b`. Ratio 1.32× is pi variance (pi 1572→2357),
not a cadr win. Absolute cadr µs rose. Vector slots did not beat
the walker leftover.

## This drain — leftover booked (not G.17)

HEAD remesure Friend-MachineD n=5 git `da3d7322f` (no src
speedup on this SHA):

| metric | cadr µs | pi µs | ratio |
|---|---:|---:|---:|
| `session_load` | 3105.9 | 1567.1 | 1.98× |
| `journal_read` | 2716.4 | 1443.5 | 1.88× |
| `truncate_head` | 387.3 | 544.0 | 0.71× |
| `truncate_tail` | 533.8 | 613.3 | 0.87× |

Legal Lisp encodings of V8 sequential properties were tried and
made **cadr µs** worse. Remaining levers are empty SWAR, intern
grow, FFI V8, mmap — all forbidden without adjudication.

**This drain has no remaining legal encoding knife** on
load/journal. Leftover is walker vs V8 `JSON.parse`. Not G.17
`blocked` (that needs advisor). Not G.17 `met`. Not product-format
blocked. Ceiling not lowered. Part P still `[open]`.
