# Goal 20 — session_load leftover after parse-message 三连 @ `1e2fff836`

Proposal for adjudication. Not G.17 `met`. Not Part P `[done]`.
Not FFI. Not intern grow. Not empty SWAR. Not mmap.

Friend-MachineD n=5, this host, pairing
`test/fixtures/goal20-paired-paths/session.jsonl` (209 KiB, one
1MiB-cap read; SCAN-BUFFER pending NIL, same as pi `indexOf("\n")`).

## Current ISO-kept walker

Product HEAD after three withdraws (`1e2fff836`). No `src/` on this
remesure.

| metric | cadr µs | pi µs | ratio |
|---|---:|---:|---:|
| `session_load` | **1879** | 1634 | **1.15×** |
| `journal_read` | 1708 | 1446 | 1.18× |

Historical keep after ISO timestamp (`d0c88ddd2`): load cadr **1857 µs**
/ 1.27× (pi jitter). Same walker; 1879 vs 1857 is noise, not a new
encoding.

Ceiling 9.0 / 8.0 not lowered.

## Split `PARSE-SESSION-RECORD-OCTETS` (this-host, 40× load)

From `docs/benchmarks/goal20-parse-session-record-split.md`. Inclusive
µs/load; children overlap parents. Wall ~1403 µs this-host.

| inner | inclusive µs / load | V8 `JsonParser` |
|---|---:|---|
| `put-entry-field` | 701 | named properties / `BuildJsonObject` |
| `parse-message` | 601 | `ParseJsonObject` (message) |
| `parse-string-value` | 301 | `ParseString` / `MakeString` |
| `parse-usage` | 100 | `ParseJsonObject` (usage) |
| `parse-generic` | 0 | `ParseJsonValue` (cold) |

sprof parent: `PARSE-SESSION-RECORD-OCTETS` 9.5% self / ~72% total.

## parse-message 三连 (Friend-MachineD n=5, cadr µs worse)

V8 does less: `ScanJsonString` is a window; `SmallVector<JsonProperty,16>`
then one `BuildJsonObject` / `MakeString`. Source:
`docs/benchmarks/goal20-v8-parse-message-shape.md`, V8 13.6
`json-parser.h`.

| knife | SHA | cadr load | result |
|---|---|---:|---|
| scratch bag + parse-time `message-from-json` | `cc29bec17` → `385542aab` | 1857→**2015** | withdrawn |
| stack locals → typed message | `8530c25a1` → `1ec2dacf2` | 1857→**1917** | withdrawn |
| delayed ParseString (span then `MakeString`) | `3ad720098` → `1e2fff836` | 1857→**1974** | withdrawn |

Do not redo any of the three. Lisp encodings of that V8 shape made
**cadr µs** worse.

## Other split inners — why not a fourth legal knife here

- **`parse-string-value` 301 µs.** Intern-or-`copy-unescaped` during
  scan. Delayed `MakeString` (row 3 above) lost. COPY-UNESCAPED
  rewrite banned. Closed-set intern grow withdrawn (`4de854bdd` /
  `8018b6f53`). Remaining copy is V8 `MakeString` work; cheaper
  one-byte SeqString / internalization is VM, not a Lisp DS.
- **`put-entry-field` minus `parse-message`.** Timestamp already
  ISO in-place (`635ac76a1`, kept). `type` / `id` / `parentId` are
  interned closed-set strings; intern grow banned. length-case
  `put-*-field` withdrawn (`789bec858`).
- **`parse-usage` 100 µs.** Small `ParseJsonObject`. length-case
  already lost.
- **`parse-generic` 0.** Cold on this fixture.
- **SCAN-BUFFER.** Pairing file fits the 1MiB cap; pending is NIL.
  Not the leftover on this pair.
- **Content blocks.** `finish-block` already builds typed
  `text-content` / `tool-call` at object close (`BuildJsonObject`).
  Not an unparsed bag.
- **SCAN-KEY labels→macrolet.** Withdrawn (`f87bea405`). DIGITS
  unroll withdrawn. ISO quote walk already kept.

## Leftover class (for adjudication)

session_load leftover vs pi `JSON.parse` is the walker vs V8
`JsonParser` runtime (one-byte strings, internalization, hidden-class
`BuildJsonObject`), not an untried Lisp encoding of the measured
inners.

Legal remaining classes, all already forbidden without a new ruling:

- FFI into V8 / simdjson / yyjson
- mmap
- generic intern-table growth
- empty SWAR
- COPY-UNESCAPED micro-rewrite

Not G.17 `met`. Floor (not slower than pi) still missed on load
(~1.15–1.27×). Sidecar pairing leftovers (`provider_pi_messages`,
`journal_read`) do not replace this.
