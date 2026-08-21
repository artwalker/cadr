# Goal 20 — provider_mistral sb-sprof (walker `0084f0703`)

Diagnostic, not a gate. 4 s, sample-interval 0.001 s. Pairing
fixture `mistral-conversations.sse` + `provider-context.json`,
shipped `stream-chat`, no socket. This-host. Not G.17.

Friend-MachineD ledger ~1.24× (`2045.6 / 1644.0 µs`, ceiling 3.0).

## Verdict

Same family as pi_messages: generic character
`PARSE-JSON-SOURCE` on each SSE data payload.

| fn | self % |
|---|---:|
| `PARSE-VALUE` | 9.1 |
| `PARSE-STRING` | 8.2 |
| `COPY-UNESCAPED-JSON-OCTETS` | 7.1 |
| `COPY-UTF8-OCTETS` | 4.7 |
| `STRING=*` | 3.9 |
| `READ-SSE-STREAM` | 2.9 (82.1% total) |

Tried: `sse-event-data-octets` + `parse-json-octets` on the
binary `data:` window. Friend-MachineD n=5 mistral
**2046→2219 µs**, load **1763→2152 µs** — withdrawn.
Do not redo. Not G.17 `met`.

## Executor — do next (do not stop)

SSE data-octets JSON parse **withdrawn**. Single-element
content shortcut **withdrawn** (load 1763→1929). Do **not**
park. **Next**: pi_messages WRITE-JSON-STRING residual.
See leftover文首 + adjudications. Not G.17 `met`.
