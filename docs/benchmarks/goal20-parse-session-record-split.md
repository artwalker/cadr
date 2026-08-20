# Goal 20 — split `PARSE-SESSION-RECORD-OCTETS` inners @ `d3a6244fe`

This-host tagged timing of **shipped** `parse-session-record-octets`
via `cadr-agent:load-session` on pairing
`test/fixtures/goal20-paired-paths/session.jsonl` (40 loads).
Not a reimplementation. Not G.17. Descent is a **parent bucket**.

Wall ~1403 µs/load this-host (Friend-MachineD pairing cadr ~1857 µs).
Inclusive internal-real-time; children overlap parents.

| inner | inclusive µs / load | V8 `JsonParser` |
|---|---:|---|
| `put-entry-field` | 701 | sequential named properties / `BuildJsonObject` |
| `parse-message` | 601 | `ParseJsonObject` (message) |
| `parse-string-value` | 301 | `ParseString` |
| `parse-usage` | 100 | `ParseJsonObject` (usage) |
| `parse-generic` | 0 | `ParseJsonValue` (cold on this fixture) |

`put-entry-field` includes `parse-message`. `parse-message` includes
`parse-string-value` and `parse-usage`. `PARSE-SESSION-RECORD-OCTETS`
sprof self 9.5% / total 72% is this parent plus SCAN-KEY /
SCAN-BUFFER / COPY-UNESCAPED.

Forbidden on these inners (already falsified or banned):
SCAN-KEY labels→macrolet, length-case `put-*-field`, closed-set
intern grow, `PARSE-STRING-VALUE` labels→macrolet, COPY-UNESCAPED,
DIGITS unroll, ISO quote walk.

## Knife

`parse-message` 601 µs: two-stage `session-json-message` bag then
`message-from-json` in `finalize-session-entry`. V8
`ParseJsonObject` + `BuildJsonObject` fills **one** JSObject from a
scratch `SmallVector<JsonProperty,16>`. Lisp encoding: reuse one
scratch bag per walker (SmallVector) and convert to the target
message type at parse time (BuildJsonObject). `finalize-session-entry`
still runs `message-from-json` on hash/EQUAL leftovers (v1 migrate,
`open-jsonl-session-storage`). Not a second walk of walker output.
