# Goal 20 — provider_pi_messages sb-sprof (walker `0084f0703`)

Diagnostic, not a gate. 4 s, sample-interval 0.001 s. Pairing
fixture `pi-messages.sse` + `provider-context.json`, shipped
`stream-chat`, no socket. This-host. Not G.17.

Friend-MachineD ledger ~1.30× (`1080.8 / 830.4 µs`, ceiling 1.5).

## Verdict

SSE file-stream is already binary `READ-SEQUENCE`. Leftover is
**generic character `PARSE-JSON-SOURCE` on each event payload**
(`pi-event-data`).

| fn | self % | note |
|---|---:|---|
| `PARSE-STRING` | 7.0 | in `PARSE-JSON-SOURCE` |
| `PARSE-VALUE` | 6.0 | 37.5% total |
| `COPY-UNESCAPED-JSON-OCTETS` | 5.0 | |
| `COPY-UTF8-OCTETS` | 4.6 | |
| `WRITE-JSON-STRING` | 4.5 | request stringify |
| `READ-SSE-STREAM` | 3.7 | 70.2% total |

Tried: `pi-event-data` → `parse-json-octets` / `utf8-octets`.
Friend-MachineD n=5 stream **1081→1190 µs**, load
**1763→1841 µs** — withdrawn. Do not redo this re-encode.
Not intern-grow. Not fill-kernel. Not G.17 `met`.
