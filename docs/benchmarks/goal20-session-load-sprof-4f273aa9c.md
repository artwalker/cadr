# Goal 20 — `session_load` sb-sprof @ `4f273aa9c`

Diagnostic. `scripts/goal20-profile.sh --seconds 4`.
Friend-MachineD, SBCL 2.6.7. After skip-space/expect-code
macrolet (`8ad4328fb` / remesure `3a23ae8b0`). Pairing SHA
`4f273aa9c` does not change the walker. Remaining load
**1.16×** booked (1958 / 1694 µs); Current board 1.22× is
pi jitter. Not G.17. `journal_read` is off the mainline
(≤1.0).

## Remaining leftover (load)

| symbol | self % | total % |
|---|---:|---:|
| PARSE-SESSION-RECORD-OCTETS | 9.9 | 72.8 |
| SCAN-KEY | 8.7 | 8.7 |
| SCAN-BUFFER | 7.4 | 81.6 |
| PARSE-STRING-VALUE | 6.8 | 9.9 |
| pthread_sigmask | 5.3 | 5.3 |
| COPY-UNESCAPED-JSON-OCTETS | 4.1 | 4.5 |
| JSON-INTERNED-ASCII-VALUE-OCTETS | 3.2 | 3.2 |

SKIP-SPACE / EXPECT-CODE dropped off the top after the
macrolet knife. Cost moved **into** PARSE-SESSION-RECORD-OCTETS
(the descent) plus SCAN-KEY labels: per-key **call tax**, not
a missing SWAR.

`COPY-UNESCAPED` / intern tables stay forbidden micro-knives.
`pthread_sigmask` / foreign `read` are runtime/OS.

## V8 vs remaining load leftover

V8 `JsonParser` object descent scans the property name in
place (`JsonString` start/length on the `Char*` window) then
`Expect(':')` and the value. No helper call per key.

cadr SCAN-KEY is still a **labels** function at every object
field. Same algorithm (octet window + known keys → slots)
with extra Lisp call frames.

Winning step: **inline SCAN-KEY like V8 property-name scan**,
not intern grow and not COPY-UNESCAPED.

## Knife

`scan-key` → `macrolet` expanding the quote-scan window at
each site. Falsify by cadr `session_load` µs vs `3a23ae8b0`
(1958 µs). Revert if worse.
