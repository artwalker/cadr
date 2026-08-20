# Goal 20 — `session_load` PARSE-USAGE / DIGITS @ `d0c88ddd2`

Diagnostic. `scripts/goal20-profile.sh --seconds 4`.
Friend-MachineD, SBCL 2.6.7. After ISO timestamp knife
(`635ac76a1` / remesure `d0c88ddd2`). Remaining load
**1.27×** (cadr **1857 µs**). Not G.17.

## Inner leftover (load)

| symbol | self % | total % | vs V8 |
|---|---:|---:|---|
| PARSE-SESSION-RECORD-OCTETS | 9.5 | 72.3 | descent |
| SCAN-BUFFER | 8.2 | 81.9 | `indexOf("\\n")` labels shell |
| SCAN-KEY | 7.7 | 7.7 | withdrawn labels→macrolet |
| PARSE-STRING-VALUE | 6.8 | 10.0 | labels→macrolet forbidden |
| COPY-UNESCAPED-JSON-OCTETS | 4.8 | 5.0 | forbidden |
| PARSE-USAGE | 3.8 | 9.3 | small object (`ParseJsonObject`) |
| DIGITS | 1.8 | 1.8 | `ParseNumber` per ISO field |

PARSE-TIMESTAMP-VALUE dropped off the top after the ISO
quote knife. DIGITS remains a **flet loop per field**.

## V8 `ParseNumber` vs DIGITS

V8 `JsonParser::ParseNumber` accumulates `digit = c - '0';
number = 10 * number + digit` **in the descent**, not a
helper called once per year/month/day. cadr `iso-ms` calls
`DIGITS` seven times with a byte loop.

PARSE-USAGE sequential `key=` of every usage field was
tried as length-case (`789bec858`) and lost. Do not redo.

## Knife

Unroll DIGITS to fixed-width `d2`/`d3`/`d4` macrolet inside
`iso-ms` (2/3/4 ASCII digits). Falsify by cadr `session_load`
µs vs `d0c88ddd2` (1857 µs). Revert if worse. Not SCAN-KEY
macrolet. Not empty SWAR. Not intern. Not FFI.
