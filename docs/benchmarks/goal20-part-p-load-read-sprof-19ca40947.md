# Goal 20 Part P — session_load / journal_read sb-sprof (HEAD `19ca40947`)

Diagnostic, not a gate. Same driver as
`scripts/goal20-profile.sh`. Contrast
[`goal20-part-p-load-read-sprof-5cc895b84.md`](goal20-part-p-load-read-sprof-5cc895b84.md).

Do not treat this file as G.17 `met` or Part P `[done]`.

- git: `19ca40947`
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds per path: 4
- sample-interval: 0.001s
- driver: `scripts/goal20-profile.sh --seconds 4`
- pairing at remesure `02b19a026` / `17df52451`: load 2.04×
  (2926 / 1433 µs), read 1.80× (2665 / 1483 µs)

## Verdict

No unused legal named Lisp structure. Top leftover is the
already-shipped octet walker:

- `OCTET-U32-LE` (load 11.2% / read 11.1%)
- `OCTET-FIND-QUOTE-OR-BACKSLASH` (8.1% / 9.4%)
- `SWAR-EQ-MSB` (6.8% / 7.4%)
- skip-space / find-lf
- `SCAN-KEY` / `COPY-UNESCAPED-JSON-OCTETS`
- `pthread_sigmask` / foreign `read`

Board forbids repeating LF/space SWAR, key=, copy-unescaped,
`OCTET-U32-LE`, string scan, empty SWAR, intern
(`JSON-INTERNED-ASCII-VALUE-OCTETS` 1.4% is intern).
Foreign `read` is not copyable without adjudication.

Floor still >1.0×. This booking does not change `src/`.

## `session_pipeline.session_load`

```
Number of samples: 981
  1  110  11.2%  CADR-AI::OCTET-U32-LE
  2   79   8.1%  CADR-AGENT::OCTET-FIND-QUOTE-OR-BACKSLASH
  3   67   6.8%  CADR-AGENT::SWAR-EQ-MSB
  4   57   5.8%  CADR-AGENT::SWAR-QUOTE-OR-BS-MASK
  5   51   5.2%  CADR-AGENT::OCTET-SKIP-JSON-SPACE
  6   50   5.1%  CADR-AGENT::OCTET-FIND-LF
  7   42   4.3%  SKIP-SPACE
  8   29   3.0%  PARSE-SESSION-RECORD-OCTETS (74.4% total)
 10   26   2.7%  foreign function pthread_sigmask
 11   25   2.5%  SCAN-KEY
 12   24   2.4%  COPY-UNESCAPED-JSON-OCTETS
 13   19   1.9%  foreign function read
 19   14   1.4%  JSON-INTERNED-ASCII-VALUE-OCTETS
```

## `storage_journal.journal_read`

```
Number of samples: 986
  1  109  11.1%  CADR-AI::OCTET-U32-LE
  2   93   9.4%  CADR-AGENT::OCTET-FIND-QUOTE-OR-BACKSLASH
  3   73   7.4%  CADR-AGENT::SWAR-EQ-MSB
  4   52   5.3%  CADR-AGENT::OCTET-FIND-LF
  5   51   5.2%  CADR-AGENT::OCTET-SKIP-JSON-SPACE
  7   45   4.6%  PARSE-SESSION-RECORD-OCTETS (81.0% total)
 10   26   2.6%  foreign function pthread_sigmask
 11   25   2.5%  SCAN-KEY
 15   21   2.1%  foreign function read
 17   17   1.7%  COPY-UNESCAPED-JSON-OCTETS
```
