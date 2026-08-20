# Goal 20 — `session_load` sb-sprof @ `4f273aa9c`

Diagnostic. `scripts/goal20-profile.sh --seconds 4`.
Friend-MachineD, SBCL 2.6.7. After skip-space/expect-code
macrolet (`8ad4328fb` / remesure `3a23ae8b0`). Pairing SHA
`4f273aa9c` does not change the walker. Remaining load
**1.16×** booked (1958 / 1694 µs). Not G.17. `journal_read`
is off the mainline (≤1.0).

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
(the descent) plus SCAN-KEY labels.

`COPY-UNESCAPED` / intern tables stay forbidden micro-knives.
`pthread_sigmask` / foreign `read` are runtime/OS.

## V8 vs remaining load leftover

V8 `JsonParser` object descent scans the property name in
place (`JsonString` start/length on the `Char*` window).
cadr SCAN-KEY is still a **labels** function at every object
field.

## Knife (withdrawn)

`scan-key` → `macrolet` at each site (`f87bea405`). Friend-MachineD
n=5: cadr `session_load` **1958→2260 µs** (worse),
`journal_read` **1563→1904 µs** (worse). Reverted `64e564968`.
Same class as skip/expect (which won); expanding the quote-scan
loop five times lost on cadr µs. Not empty SWAR. Not intern.
Not FFI. Ceiling not lowered. Not G.17.

PARSE-STRING-VALUE is the same labels-to-macrolet class.
Do not repeat it as a blind next-slot inline.

## Next win tried (withdrawn)

V8 named-property lookup after `JsonString` start/length.
cadr sequential `key=` of every field in `put-entry-field` /
`put-usage-field`. Knife `789bec858`: exclusive length then
one literal. Friend-MachineD n=5: cadr `session_load`
**1958→1986 µs** (no win). Reverted `157300eae`. Not labels
macrolet. Not intern. Not FFI.

## Next win (closed-set intern)

sprof load: `STRING=*` 3.2%, `JSON-INTERNED-ASCII-VALUE-OCTETS`
3.2%, `COPY-UNESCAPED` 4.1%. V8
`JsonParser::InternalizeJsonString` / internalized short
ASCII. cadr already flies `text`/`message`/`toolCall`;
closed session types (`leaf`/`label`/`image`/`compaction`/…)
still copy then `STRING=*`. Not a growing intern table.
Falsify by cadr `session_load` µs vs `3a23ae8b0` (1958 µs).
Revert if worse.
