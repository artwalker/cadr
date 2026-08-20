# Goal 20 Part P — session_load / journal_read sb-sprof (HEAD `e2a4dfad6`)

Diagnostic, not a gate. Same driver as `scripts/goal20-profile.sh`.
Compare `docs/benchmarks/goal20-part-p-load-journal-compare.md`.

Do not treat this file as G.17 `met` or Part P `[done]`.

- git: `e2a4dfad6`
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds per path: 4
- sample-interval: 0.001s
- pairing this booking: load **2.09×** (2957 / 1417 µs), read **1.97×**
  (2718 / 1382 µs). Ceilings 9.0 / 8.0.

## Verdict

Passes already match pi (`readSync` 1MiB + LF + parse line + skip
blank/malformed). Leftover is the shipped octet walker, Class C
(copy V8 `JSON.parse` in Lisp):

- `OCTET-U32-LE` (load 12.0% / read 16.3%)
- `OCTET-FIND-QUOTE-OR-BACKSLASH` + `SWAR-EQ-MSB`
- `PARSE-SESSION-RECORD-OCTETS` (77.6% / 80.2% total)
- `JSON-INTERNED-ASCII-VALUE-OCTETS` 1.3% / 1.0% (intern; do not grow)
- foreign `read` / `pthread_sigmask`

Not a deleted split/array. Not a license for a third scan. Empty
SWAR, intern growth, FFI, mmap forbidden. Product knife **blocked**.
No `src/`.

## `session_pipeline.session_load`

```
Number of samples: 989
  1  119  12.0%  CADR-AI::OCTET-U32-LE
  2   86   8.7%  CADR-AGENT::SWAR-EQ-MSB
  3   82   8.3%  CADR-AGENT::OCTET-FIND-QUOTE-OR-BACKSLASH
  4   53   5.4%  CADR-AGENT::SWAR-QUOTE-OR-BS-MASK
  5   44   4.4%  CADR-AGENT::OCTET-FIND-LF
  6   43   4.3%  CADR-AGENT::PARSE-SESSION-RECORD-OCTETS (77.6% total)
  7   41   4.1%  CADR-AGENT::OCTET-SKIP-JSON-SPACE
 13   21   2.1%  CADR-AI::COPY-UNESCAPED-JSON-OCTETS
 21   13   1.3%  CADR-AI::JSON-INTERNED-ASCII-VALUE-OCTETS
```

## `storage_journal.journal_read`

```
Number of samples: 986
  1  161  16.3%  CADR-AI::OCTET-U32-LE
  2   88   8.9%  CADR-AGENT::OCTET-FIND-QUOTE-OR-BACKSLASH
  3   59   6.0%  CADR-AGENT::SWAR-EQ-MSB
  5   53   5.4%  CADR-AGENT::OCTET-FIND-LF
  7   45   4.6%  CADR-AGENT::PARSE-SESSION-RECORD-OCTETS (80.2% total)
 10   28   2.8%  CADR-AI::COPY-UNESCAPED-JSON-OCTETS
 22   10   1.0%  CADR-AI::JSON-INTERNED-ASCII-VALUE-OCTETS
```
