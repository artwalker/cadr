# Goal 20 Part P — provider_codex sb-sprof (HEAD `cdcae1912`)

Diagnostic, not a gate. Shipped `stream-chat` on recorded
`openai-codex-responses.sse` (`transport :sse`). Same pairing
stub. No socket.

- git: `cdcae1912`
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- sample-interval: 0.001s
- pairing: **1.26×** (1582 / 1258 µs). Ceiling 1.5.

## pi vs cadr passes + DS

Pi `openai-codex-responses.ts` SSE path (`transport: "sse"`):

1. `buildRequestBody` — one object: `instructions`, `input`,
   `text.verbosity`, `include`, `tool_choice`, `parallel_tool_calls`.
2. `JSON.stringify(body)` **once**.
3. `zstdCompressSync` only when Node zlib exposes it.
4. `options.fetch` / `parseSSE` (`TextDecoder` + `JSON.parse` per
   `data:` event) + `processResponsesStream`.

Cadr `codex.lisp` + `websocket.lisp` `prepare-provider-sse-request`:

1. `build-request` delegates to openai-provider, then `:around`
   puts the same Codex fields.
2. `prepare-provider-sse-request` **stringify-json** of the payload
   to feed `compress-request-body-zstd`, even when
   `*zstd-compress-function*` is nil (pairing path).
3. `invoke-http-request` stringify-json **again** for `:content`
   when `raw-body` is unset.
4. `read-sse-stream` + `parse-json` / `PARSE-JSON-SOURCE` + openai
   Responses reduce.

Named leftover of the extra pass (not Class C JSON.parse):

- `WRITE-JSON-STRING` 21.8% total / 10.0% self
- `PARSE-VALUE` 22.7% total (SSE JSON; same family as mistral)
- `READ-SSE-STREAM` 57.3% total
- `CALL-NEXT-METHOD` in `copy-model-with` (`azure-openai.lisp`) 10.0% total
- foreign `read` 3.6% self

The legal first knife is dropping the unused stringify when zstd is
unbound — copy of pi's one `JSON.stringify` then optional compress.
SSE `PARSE-JSON-SOURCE` stays Class C leftover after that. Not FFI
V8. Not empty SWAR. Not intern grow.

```
Number of samples: 110
  WRITE-JSON-STRING 21.8% total
  PARSE-VALUE 22.7% total
  READ-SSE-STREAM 57.3% total
  CALL-NEXT-METHOD (copy-model-with) 10.0% total
```
