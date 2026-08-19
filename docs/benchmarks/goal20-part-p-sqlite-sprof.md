# Goal 20 Part P — `sqlite_session.open_walk` sb-sprof (HEAD `e3eb0d956`)

Diagnostic, not a gate. Same fixture and production thunk as
`scripts/goal20-paired-paths.lisp` (`session-repository-open` +
`harness-session-entries` + `harness-session-branch`). Recorded
because the 20:27 board asked for sprof after the 0.15× pair.
0.15× is not a stop.

Do not treat this file as G.17 `met` or Part P `[done]`.

- recordedAt: 2026-08-19T12:30:00Z
- git: `e3eb0d956`
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds: 4 (958 samples at 0.001s; wall includes SQLite/CFFI)
- sample-interval: 0.001s
- pairing: Friend-MachineD n=5, 0.15× (7365 / 49932 µs), ceiling 1.5

## Verdict

Leftover **is** Lisp structure: `PARSE-JSON-SOURCE` /
`PARSE-VALUE` (8.9% self / 49.8% total) and `PARSE-STRING`
(7.0%) while decoding SQLite `payload` TEXT via
`cadr-ai::parse-json` in `sqlite-row-to-entry`. That is
EQUAL-hash JSON, not the session JSONL octet FSM already
shipped for `load-session`.

Also on the stack: Babel/CFFI UTF-8 (`FOREIGN-STRING-TO-LISP`
18.7% total), `STRING=*`, `GETHASH/EQUAL` / `PUTHASH/EQUAL`,
`JSON-INTERNED-ASCII-VALUE` (intern — do not expand),
foreign `pread64` / `pthread_sigmask` / `unlink`.

Named unused legal lever: decode the stored payload with the
session record octet parser (`parse-session-record-octets` /
`record-to-session-entry`) instead of `parse-json`. Not intern.
Not FFI. Not empty SWAR.

| Nr | self % | total % | function |
|---|---:|---:|---|
| 1 | 8.9 | 49.8 | `PARSE-VALUE` in `PARSE-JSON-SOURCE` |
| 2 | 7.0 | 13.8 | `PARSE-STRING` in `PARSE-JSON-SOURCE` |
| 3 | 6.7 | 6.7 | Babel UTF-8 decoder (CFFI string) |
| 4 | 5.8 | 5.8 | `STRING=*` |
| 5 | 4.1 | 4.1 | `pthread_sigmask` |
| 6 | 4.1 | 4.1 | Babel UTF-8 code-point counter |
| 7 | 3.0 | 4.1 | `CFFI::FOREIGN-STRING-LENGTH` |
| 8 | 2.4 | 2.4 | `%SXHASH-STRING/TRUNCATING` |
| 9 | 2.1 | 2.1 | foreign `pread64` |
| 10 | 1.8 | 18.7 | `CFFI:FOREIGN-STRING-TO-LISP` |
| 11 | 1.7 | 5.2 | `GETHASH/EQUAL` |
| 12 | 1.6 | 3.5 | `JSON-INTERNED-ASCII-VALUE` (intern; forbidden to expand) |

## `sqlite_session.open_walk`

```
Number of samples:   958
Sample interval:     0.001 seconds
Total sampling time: 0.958s

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1     85   8.9    477  49.8     85   8.9        -  (LABELS CADR-AI::PARSE-VALUE :IN CADR-AI::PARSE-JSON-SOURCE)
   2     67   7.0    132  13.8    152  15.9        -  (LABELS CADR-AI::PARSE-STRING :IN CADR-AI::PARSE-JSON-SOURCE)
   3     64   6.7     64   6.7    216  22.5        -  Babel UTF-8 decoder (CFFI strings.lisp)
   4     56   5.8     56   5.8    272  28.4        -  SB-KERNEL:STRING=*
   5     39   4.1     39   4.1    311  32.5        -  foreign function pthread_sigmask
   6     39   4.1     39   4.1    350  36.5        -  Babel UTF-8 code-point counter
   7     29   3.0     39   4.1    379  39.6        -  CFFI::FOREIGN-STRING-LENGTH
   8     23   2.4     23   2.4    402  42.0        -  SB-IMPL::%SXHASH-STRING/TRUNCATING
   9     20   2.1     20   2.1    422  44.1        -  foreign function pread64
  10     17   1.8    179  18.7    439  45.8        -  CFFI:FOREIGN-STRING-TO-LISP
  11     16   1.7     50   5.2    455  47.5        -  SB-IMPL::GETHASH/EQUAL
  12     16   1.7     30   3.1    471  49.2        -  SB-IMPL::GROW-HASH-TABLE
  13     16   1.7     16   1.7    487  50.8        -  (LABELS CADR-AI::SKIP-SPACE :IN CADR-AI::PARSE-JSON-SOURCE)
  14     15   1.6     34   3.5    502  52.4        -  CADR-AI::JSON-INTERNED-ASCII-VALUE
  15     15   1.6     15   1.6    517  54.0        -  (LABELS CADR-AI::EXPECT :IN CADR-AI::PARSE-JSON-SOURCE)
  16     13   1.4     85   8.9    530  55.3        -  SB-IMPL::PUTHASH/EQUAL
  17     12   1.3     12   1.3    542  56.6        -  PCL braid
  18     10   1.0     10   1.0    552  57.6        -  foreign function unlink
------------------------------------------------------------------------
         77   8.0                                     elsewhere
```
