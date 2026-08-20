# Goal 20 — `session_load` inner PARSE / SCAN-BUFFER @ `7517049cb`

Diagnostic. `scripts/goal20-profile.sh --seconds 4`.
Friend-MachineD, SBCL 2.6.7. After skip/expect kept,
three knives withdrawn. Remaining load **1.17×**
(1882 / 1611 µs). Not G.17.

## Inner leftover (load)

| symbol | self % | total % | vs V8 / pi |
|---|---:|---:|---|
| PARSE-SESSION-RECORD-OCTETS | 9.7 | 73.0 | descent (`ParseJsonObject`) |
| SCAN-BUFFER | 7.7 | 82.9 | `loadEntriesFromFile` `indexOf("\\n")` |
| SCAN-KEY | 7.0 | 7.0 | withdrawn labels→macrolet |
| PARSE-STRING-VALUE | 5.8 | 9.1 | labels→macrolet forbidden |
| PARSE-USAGE | 4.4 | 10.3 | withdrawn length-case |
| COPY-UNESCAPED-JSON-OCTETS | 3.9 | 4.0 | forbidden micro-knife |
| PARSE-TIMESTAMP-VALUE | 3.3 | 8.6 | `ParseString` then number |
| DIGITS | 2.1 | 2.1 | ISO field parse |

## SCAN-BUFFER vs `loadEntriesFromFile`

pi: 1MiB `readSync` + `StringDecoder` + `pending.indexOf("\\n")`
+ `JSON.parse(line)`. cadr pairing `session.jsonl` is 209 KiB
< 1MiB cap, so `pending` is NIL: one octet buffer +
`octet-find-lf` (already SWAR). Passes aligned. Remaining
SCAN-BUFFER self is the labels shell around that LF loop.
Inlining it is the withdrawn labels→macrolet class.

## PARSE inner vs V8 `ParseString`

V8 `JsonParser::ParseString` sequential-scans to `"`, then
internalizes or copies. cadr `PARSE-STRING-VALUE` already uses
`octet-find-quote-or-backslash`. `PARSE-TIMESTAMP-VALUE` still
walks **one byte at a time** looking for `"`, then `iso-ms`.
Session timestamps are 24-byte `YYYY-MM-DDTHH:MM:SS.sssZ`.

Winning step: **fixed-width ISO then one quote**, else the
existing quote scanner. Not empty SWAR. Not intern. Not
COPY-UNESCAPED. Not labels→macrolet.

## Knife

`parse-timestamp-value`: if 24 ASCII + `"` and `iso-ms`
succeeds, consume 25 bytes. Else `octet-find-quote-or-backslash`.
Falsify by cadr `session_load` µs vs `7517049cb` (1882 µs).
Revert if worse.
