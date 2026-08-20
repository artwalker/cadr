# Goal 20 — `session_load` PARSE-USAGE / DIGITS @ `d0c88ddd2`

Diagnostic. `scripts/goal20-profile.sh --seconds 4`.
Friend-MachineD, SBCL 2.6.7. After ISO timestamp knife.
Remaining load **1.27×** (cadr **1857 µs**). Not G.17.

## Inner leftover (load)

| symbol | self % | total % | vs V8 |
|---|---:|---:|---|
| PARSE-SESSION-RECORD-OCTETS | 9.5 | 72.3 | descent |
| SCAN-BUFFER | 8.2 | 81.9 | `indexOf("\\n")` labels shell |
| PARSE-USAGE | 3.8 | 9.3 | small object (`ParseJsonObject`) |
| DIGITS | 1.8 | 1.8 | `ParseNumber` per ISO field |

## V8 `ParseNumber` vs DIGITS (withdrawn)

V8 accumulates digits in the descent. cadr `iso-ms` called
`DIGITS` seven times. Knife `ebbea846f`: unroll `d2`/`d3`/`d4`.
Friend-MachineD n=5: cadr `session_load` **1857→1928 µs**
(worse). Reverted `7a3f07520`. Not SCAN-KEY macrolet. Not
intern. Not FFI.

PARSE-USAGE sequential `key=` was tried as length-case
(`789bec858`) and lost. Do not redo. Descent self is the
parent after skip/expect inline.
