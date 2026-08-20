# Goal 20 Part P — session_compact sb-sprof (HEAD `66b7403b6`)

Diagnostic, not a gate. In-memory `run-paired-compact` /
`compact-from-preparation` after the JSONL thunk was removed.

- git: `66b7403b6`
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- sample-interval: 0.001s
- pairing: **4.54×** (164 / 36 µs). Ceiling 20.0.

## Verdict

Named leftover of the **shipped** compact core is UUIDv7 entropy, not
summarization:

- foreign `read` 79.3%
- `__close` 1.9% / `access` 1.9% / `__open64` 1.2%
- `COMPLETE-SUMMARIZATION` 90.9% total
- `UUID-V7` 89.8% total

`complete-summarization` calls `make-session-id` → `uuid-v7` →
`default-random-octets`, which **opens `/dev/urandom` per UUID**.
pi `uuidv7` is `crypto.getRandomValues` on a 16-byte buffer (no
open/close). Item 6: Lisp-encode that fill. Not intern. Not empty
SWAR. Not FFI simdutf. Not a third summarizer.

```
Number of samples: 482
  foreign read 79.3%
  __close 1.9%
  access 1.9%
  pthread_sigmask 1.2%
  __open64 1.2%
  COMPLETE-SUMMARIZATION 90.9% total
  UUID-V7 89.8% total
```
