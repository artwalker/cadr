# Goal 20 — `session_load` sb-sprof @ `9b1678b20`

Diagnostic. `scripts/goal20-profile.sh --seconds 4`.
Friend-MachineD, SBCL 2.6.7. After quote-scan inline
(`318822b1c`). Remaining load **1.28×** (2069 / 1613 µs).
Not G.17.

## Remaining leftover (load)

| symbol | self % | total % |
|---|---:|---:|
| SCAN-KEY | 8.5 | 9.5 |
| SKIP-SPACE | 8.2 | 8.2 |
| SCAN-BUFFER | 6.8 | 83.1 |
| PARSE-SESSION-RECORD-OCTETS | 6.0 | 74.5 |
| PARSE-STRING-VALUE | 5.5 | 7.5 |
| COPY-UNESCAPED-JSON-OCTETS | 4.9 | 5.3 |
| EXPECT-CODE | 3.5 | 3.5 |

Helpers (`OCTET-U32-LE`, quote-scan functions) dropped off the
top after inlining. Cost moved **into** SCAN-KEY / SKIP-SPACE
labels: per-field **call tax**, not a missing SWAR.

`COPY-UNESCAPED` / intern tables stay forbidden micro-knives.
`pthread_sigmask` / foreign `read` are runtime/OS.

## V8 vs remaining 1.28×

V8 `JsonParser`: `SkipWhiteSpace` and `Expect` are **inlined**
in the descent (`Peek()` / `Advance()` on the `Char*` window).
Property names stay a `JsonString` start/length; no helper call
per colon or comma.

cadr after two inline knives still uses **labels** `skip-space`
and `expect-code` at every field. That is the same algorithm
(octet window + known keys → slots) with extra Lisp call frames.

Winning step for the remaining 1.28×: **inline skip/expect like
V8**, not a third object container and not intern grow.

## Knife

`skip-space` / `expect-code` → `macrolet` expanding
`octet-skip-json-space` / `take-code` at each site. Falsify
by cadr `session_load` µs vs `9b1678b20` (2069 µs). Revert if
worse.
