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

## Content-block scratch (Friend-MachineD n=5, cadr µs worse)

Lexer token reuse: one `session-json-block` per walker;
`finish-block` still copies. Friend-MachineD @ `767b4c452`:
load cadr **1879→2083 µs**. Withdrawn `52d0986f8`. Do not redo
content-block bag reuse (same family as message bag).

## Other split inners — withdrawn or already encoded

- **`parse-string-value`.** Intern-or-`copy-unescaped` during
  scan. Delayed `MakeString` (三连 row 3) lost. ASCII already
  `simple-base-string` + ub32 `schar` copy. COPY-UNESCAPED
  **kernel** micro-rewrite banned. Closed-set intern grow
  withdrawn. Next legal try on this child: **per-load string
  arena / bump** (adjudication 2026-08-21 A) — not a redo of
  the copy loop body.
- **`put-entry-field`.** Keys are already octet windows +
  `octet-window-equals`. Timestamp ISO kept. length-case
  `put-*-field` withdrawn (`789bec858`). Default-reject key-tag
  / length-case **redos**; a claim of distinct encoding (e.g.
  gperf unique first-u32 prefix) is allowed only if Friend-MachineD
  cadr µs wins — otherwise withdraw. Prefer A/D when choosing
  the next knife cold.
- **`parse-usage`.** Small object; length-case already lost.
- **`parse-generic`.** Cold on this fixture.
- **SCAN-BUFFER.** Pairing file fits the 1MiB cap; pending NIL.
- **Content blocks / arrays.** Scratch bag reuse lost. List +
  `nreverse` (or repeated extend) may still be a lever —
  **exact-length / `svref`** (adjudication 2026-08-21 D), not
  bag reuse.
- **SCAN-KEY labels→macrolet.** Withdrawn (`f87bea405`). DIGITS
  unroll withdrawn. ISO quote walk kept. `tagbody` merge is
  last-resort only.

## Next knives (advisor 2026-08-21 — DeepSeek review)

Prefer **A** (string arena / bump) or **D** (exact content
arrays). See `docs/adjudications.md` 「Load knife priority after
bag-reuse falsifications」and `goal20-draft.md` 十B item 10.
Lazy octet-span needs a new ruling. Keep/revert on Friend-MachineD
cadr µs vs ~1879; &lt;~50 µs treat as noise.

## Leftover class (bookkeeping — superseded as a stop)

session_load leftover vs pi `JSON.parse` was booked after three
falsified V8-shape knives on the `parse-message` child (and
later content-block scratch).

**User ruling 2026-08-20 23:43** (`docs/adjudications.md`
「Lisp 屠龙刀: invent the DS if none is ready-made」),
**2026-08-20 23:48** (mature algorithms/DS as design
sources; keep optimizing), and **2026-08-21** (DeepSeek review
priority A/D over B/C/E):
Lisp is the sword. Failed *surface encodings* ≠ park
load ≠ G.17. Study mature published algorithms/structures
and **Lisp-encode** them (study ≠ FFI). If no ready-made
binary wins, invent the encoding. Empty ⚑ that only repeats
banned classes is rejected.

Historical classes that stay forbidden without a new ruling:

- FFI into V8 / simdjson / yyjson
- mmap
- generic intern-table growth
- empty SWAR
- COPY-UNESCAPED micro-rewrite
- bag / token reuse of message or content-block scratch
- length-case / key-tag `case` redo without a distinct proof

Not G.17 `met`. Floor still missed on load (~1.15–1.27×).
Sidecar pairing leftovers do not replace inventing the next
Lisp knife.
