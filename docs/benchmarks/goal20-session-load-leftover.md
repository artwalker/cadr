# Executor current (2026-09-04)

**Kept:** discovery header probe invent (buffered
`read-sequence` + `parse-session-header-octets`; not per-byte
`read-byte`; not string JSON). Friend-MachineD n=5 microbench
**1053→732 µs** (confirm 1187→834). Observed EQUAL.
cadr-agent FiveAM 1488 pass.

**Prior kept:** message-envelope compact-prefix (shared
`{"role":"` gate; user + toolResult). Load **1546→1192 µs**.

**Withdrawn this turn:** assistant type-branch compact
(EQUAL; no clear µs win vs tip). Do not redo without a new
allocation story.

G.17 stays `missing`. Goal 20 not complete.

**Do not:** mark G.17 `met`; redo withdrawn classes.

---


# Executor note (2026-08-21)

Walker `0084f0703` / load ~1763 (~1.11×).

**User ruling 2026-08-21 14:00:** stop circling invent.
No further load/pairing micro-knives until a concrete
algorithm/DS proposal exists (or user reopens). G.17 stays
`missing`. Goal 20 not complete.

**Kept walker:** proposal-3 era (`0084f0703`). Net keep from
earlier: compact-prefix + put-entry u32 + put-message
first-byte (~1879→1763).

**Also withdrawn in `e363ea889`:** intern length-gate (1763→1901). Do not redo.

**Do not:** raise empty ⚑ to farm new case/shortcut knives;
mark G.17 `met`; redo withdrawn classes.

---


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
  **fill-kernel** micro-rewrite banned. **Allowed:** elide the
  ASCII pre-scan by accumulating high-byte on the value
  quote-scan (knife 1, adjudication 2026-08-21). Closed-set
  intern grow withdrawn.
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

## Knife 1 (falsified) — quote-scan high-byte @ `108d9184a`

Friend-MachineD n=5: load cadr **1879→2045 µs**. Withdrawn
`78f84679f` (restore `aa2d4a89a`). Do not redo. Fill kernel
was never rewritten.

## Next knives (advisor 2026-08-21 — ban scope + knives 1/2)

**Supersedes** the DeepSeek A/D cold priority for the immediate
queue. See `docs/adjudications.md` 「COPY-UNESCAPED ban scope;
try quote-scan high-byte + content shape fast-path」and
`goal20-draft.md` 十B item 11.

1. **Knife 1 (do this first, alone):** fold ASCII/high-byte
   detection into the value quote-scan (`high-byte-p` like
   `escaped-p`); unescaped ASCII → check-less copier whose
   **fill loop is unchanged**; do not slow key scans (value
   scanner variant OK). Ban clarification: this is **not**
   COPY-UNESCAPED fill-kernel micro-rewrite. Win: Friend-MachineD
   cadr load **&lt; ~1879 µs** + `test-cl` green + strings EQUAL.
2. **Knife 2 (only after knife 1 keeps):** content compact-prefix
   fast path (text / thinking / toolCall shapes) with generic
   `parse-content-block` fallback. Not bag reuse. Mutated
   fixtures must EQUAL. Separate Friend-MachineD.
3. **Not next:** proposal 3 (message first-byte) until 1+2
   residual; proposal 4 (per-load EQ dedupe) needs user ruling;
   proposal 5 (line displaced views) research only.
4. `put-entry` u32/gperf WIP remesures alone — do not merge with
   knife 1.

Lazy octet-span / arena displaced views still need rulings where
they change output contract. Keep/revert on Friend-MachineD cadr
µs vs ~1879; speculative µs sums are not a schedule.

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
- COPY-UNESCAPED **fill-kernel** micro-rewrite (ASCII pre-scan
  elision via quote-scan high-byte is **allowed**)
- bag / token reuse of message or content-block scratch
- length-case / key-tag `case` redo without a distinct proof

Not G.17 `met`. Floor still missed on load (~1.15–1.27×).
Sidecar pairing leftovers do not replace inventing the next
Lisp knife.
