# Goal 20 Part P — session_compact sb-sprof (HEAD `a7a31ae8c`)

Diagnostic, not a gate. Before the in-memory compact() encoding knife.

- git: `a7a31ae8c` (JSONL pairing thunk)
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- sample-interval: 0.001s
- pairing: **11.33×** (965 / 85 µs). Ceiling 20.0.

## Verdict

Named leftover of the **timed thunk** is filesystem, not summarization:

- `mkdir` 44.0%
- foreign `read` 24.0%
- `__write` 6.7%
- `fstatat` / `__open64`

pi `compact()` does not mkdir or write JSONL. Item 6: copy that
in-memory prepare+compact DS. Not a third summarizer. Not intern.
Not empty SWAR. Not FFI.

```
Number of samples: 75
  mkdir 44.0%
  foreign read 24.0%
  __write 6.7%
```
