# Goal 20 Part P — provider_codex sb-sprof after stringify skip (HEAD `4ac111707`)

Diagnostic, not a gate. Shipped `stream-chat` on recorded
`openai-codex-responses.sse` (`transport :sse`). Same pairing
stub. No socket.

- git: `4ac111707` (remesure booked `e7dfdf2a4`)
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- sample-interval: 0.001s
- pairing: **1.08×** (1327 / 1226 µs). Ceiling 1.5. Pre-knife 1.26×.

## Verdict

The extra stringify pass is gone. Remaining request encode
(`WRITE-JSON-STRING` 12.6% / `WRITE-JSON-VALUE` 23.2% total) is
the one `JSON.stringify` pi also does. `copy-model-with` is not
in the top 1%.

Named leftover of the shipped stream is the Lisp JSON parser
versus V8 `JSON.parse` on SSE `data:` events (Class C, same
family as `provider_mistral` / `session_load`):

- `READ-SSE-STREAM` 65.3% total
- `PARSE-STRING` 12.6% total
- `FLUSH-EVENT` 37.9% total
- `UTF8-PAYLOAD` 15.8% total
- foreign `read` 3.2% self

Copying V8's parser is FFI, intern grow, or empty SWAR — all
forbidden. Floor 1.08× stays leftover. Not product blocked
(not a new dep, `safety`, session format, mmap, or observable
SIMD). Do not jump `package_manager` while this path is still
>1.0 unless the board says so.

```
Number of samples: 95
  PARSE-STRING 12.6% total
  WRITE-JSON-STRING 12.6% total
  READ-SSE-STREAM 65.3% total
  WRITE-JSON-VALUE 23.2% total
```
