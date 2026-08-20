# Goal 20 Part P — provider_mistral sb-sprof (HEAD `3374ac197`)

Diagnostic, not a gate. Shipped `stream-chat` on recorded
`mistral-conversations.sse` (same stub as the pairing thunk:
`*http-request-function*` opens the fixture; no socket).

- git: `3374ac197`
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- sample-interval: 0.001s
- pairing: **1.89×** (3401 / 1801 µs). Ceiling 3.0.

## Verdict

Named leftover of the shipped stream is JSON SSE decode, not the
HTTP stub:

- `PARSE-JSON-SOURCE` `PARSE-VALUE` 43.3% total
- `UTF8->STRING-AREF` 25.6% total (binary `utf8-payload` used
  `sb-ext:octets-to-string` on each `data:` line)
- `PUTHASH/EQUAL` 13.3% total / `GROW-HASH-TABLE` 5.9%
- `READ-SSE-STREAM` 86.2% total
- foreign `read` 1.0% — not the pairing file open

pi `readMistralEvents` is `TextDecoder` + `JSON.parse` then typed
`consumeChatStream`. cadr is the same two passes: decode the data
line, then parse JSON. Structure is aligned. Encoding knife is
Lisp `utf8-string` (ASCII-run) on the binary payload, already
used by tool_read / session JSONL. Not intern. Not FFI V8.
`PARSE-JSON-SOURCE` vs V8 `JSON.parse` stays leftover (Class C).

```
Number of samples: 203
  PARSE-VALUE 43.3% total
  UTF8->STRING-AREF 25.6% total
  PARSE-STRING 9.9% total
  PREPARE-VECTOR-PUSH-EXTEND 9.4%
  PUTHASH/EQUAL 13.3% total
  GROW-HASH-TABLE 5.9%
  READ-SSE-STREAM 86.2% total
  foreign read 1.0%
```
