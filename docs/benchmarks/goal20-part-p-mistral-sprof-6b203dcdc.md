# Goal 20 Part P — provider_mistral sb-sprof (HEAD `6b203dcdc`)

Diagnostic, not a gate. Shipped `stream-chat` on recorded
`mistral-conversations.sse` after the SSE `utf8-string` knife
(`a54c022f0`). Same pairing stub. No socket.

- git: `6b203dcdc`
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- sample-interval: 0.001s
- pairing: **1.19×** (2149 / 1804 µs) at `0336e3b9b`. Ceiling 3.0.

## Verdict

Passes match pi `mistral-conversations.ts`:
`readMistralEvents` = `TextDecoder` + `JSON.parse` per SSE
`data:` line; `consumeChatStream` walks typed
`choices[0].delta`. cadr = `utf8-string` (ASCII-run, already
the encoding knife) + `parse-json` / `PARSE-JSON-SOURCE` +
`json-get`.

Named leftover of the shipped stream is the Lisp JSON parser
versus V8 `JSON.parse` (Class C, same family as
`session_load`):

- `PARSE-JSON-SOURCE` `PARSE-VALUE` 56.5% total
- `PARSE-STRING` 12.9% total
- `PUTHASH/EQUAL` 17.0% total
- `READ-SSE-STREAM` 83.7% total
- `UTF8-STRING` 1.4% — encoding knife already spent
- foreign `read` not in the top 1%

Copying V8's parser is FFI, intern grow, or empty SWAR — all
forbidden. `docs/acceptance/goal-v20-ds-audit.md` Class C:
product knife blocked. Not a new dep, `safety`, session
format, mmap, or observable SIMD. Floor 1.19× stays leftover.

```
Number of samples: 147
  PARSE-VALUE 56.5% total
  PARSE-STRING 12.9% total
  PUTHASH/EQUAL 17.0% total
  READ-SSE-STREAM 83.7% total
  UTF8-STRING 1.4% total
```
