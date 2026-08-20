# Goal 20 Part P — session_load / journal_read sb-sprof (HEAD `9a9a96d73`)

Diagnostic, not a gate. Contrast
[`goal20-part-p-load-read-sprof-e2a4dfad6.md`](goal20-part-p-load-read-sprof-e2a4dfad6.md).

Do not treat this file as G.17 `met` or Part P `[done]`.

- git: `9a9a96d73` (simple-vector index; remesure `2d2f24b07`)
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds per path: 4
- sample-interval: 0.001s
- pairing `2d2f24b07`: load **1.85×** (3111 / 1686 µs), read **1.65×**
  (2816 / 1702 µs). Ceilings 9.0 / 8.0.

## Verdict

`coerce` / `simple-vector` index is not in the samples. Named leftover
is still the octet walker (Class C — Lisp encoding of V8 `JSON.parse`):

- `OCTET-U32-LE` (load 11.3% / read 12.9%)
- `OCTET-FIND-QUOTE-OR-BACKSLASH` + `SWAR-EQ-MSB`
- `PARSE-SESSION-RECORD-OCTETS` (73.9% / 80.2% total)
- `JSON-INTERNED-ASCII-VALUE-OCTETS` 1.2% / 1.6% (do not grow intern)
- foreign `read` / `pthread_sigmask`

No unused legal named Lisp structure. Not a third JSON parser. Not
empty SWAR. No `src/` this booking.

## `session_pipeline.session_load`

```
Number of samples: 982
  1  111  11.3%  CADR-AI::OCTET-U32-LE
  2   77   7.8%  CADR-AGENT::OCTET-FIND-QUOTE-OR-BACKSLASH
  3   68   6.9%  CADR-AGENT::OCTET-SKIP-JSON-SPACE
  4   64   6.5%  CADR-AGENT::SWAR-EQ-MSB
  5   49   5.0%  CADR-AGENT::OCTET-FIND-LF
  6   42   4.3%  CADR-AGENT::PARSE-SESSION-RECORD-OCTETS (73.9% total)
 14   22   2.2%  CADR-AI::COPY-UNESCAPED-JSON-OCTETS
 18   12   1.2%  CADR-AI::JSON-INTERNED-ASCII-VALUE-OCTETS
```

## `storage_journal.journal_read`

```
Number of samples: 977
  1  126  12.9%  CADR-AI::OCTET-U32-LE
  2   76   7.8%  CADR-AGENT::OCTET-FIND-QUOTE-OR-BACKSLASH
  3   65   6.7%  CADR-AGENT::SWAR-EQ-MSB
  7   49   5.0%  CADR-AGENT::PARSE-SESSION-RECORD-OCTETS (80.2% total)
 14   22   2.3%  CADR-AI::COPY-UNESCAPED-JSON-OCTETS
 19   16   1.6%  CADR-AI::JSON-INTERNED-ASCII-VALUE-OCTETS
```
