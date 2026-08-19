# Goal 20 Part P — session_load / journal_read sb-sprof (HEAD `67a2d43fb`)

Diagnostic, not a gate. Same driver and fixtures as
`scripts/goal20-profile.sh` / `scripts/goal20-paired-paths.lisp`.
Recorded because the 13:06 board asked whether leftover load/read
cost is walker / GC / foreign / OS, or still EQUAL hash /
`parse-json-octets`.

Do not treat this file as G.17 `met` or Part P `[done]`.

- recordedAt: 2026-08-19T05:16:19Z
- git: `67a2d43fb375`
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds per path: 4
- sample-interval: 0.001s
- driver: `scripts/goal20-profile.sh --seconds 4`
- contrast: [`goal20-part-o-remaining-sprof.md`](goal20-part-o-remaining-sprof.md)
  (`7cf6c3ca7a77`, 2026-08-14)

## Verdict

Leftover on `session_load` and `journal_read` is the session
JSONL octet walker itself, plus runtime (`pthread_sigmask`) and
foreign `read`. There is no EQUAL-hash rebuild and no re-entry
into `parse-json-octets` / `PARSE-JSON-SOURCE`.

That matches the 13:06 stop: no `src/` knife, no intern expand,
no FFI, no 10% guess.

| path | old top (`7cf6c3ca7a77`) | now (`67a2d43fb`) |
|---|---|---|
| `session_load` | `PEEK` 16.6% self in `PARSE-JSON-SOURCE`; `GETHASH/EQUAL` 3.3% | `SCAN-BUFFER` 7.0% self / 82.1% total in `READ-SESSION-OBJECTS`; `PARSE-SESSION-RECORD-OCTETS` 73.0% total |
| `journal_read` | `PEEK` 19.7% self in `PARSE-JSON-SOURCE` | same walker: `SCAN-BUFFER` 7.0% self / 91.6% total; `PARSE-SESSION-RECORD-OCTETS` 81.9% total |

`GETHASH/EQUAL` and `PARSE-JSON-SOURCE` labels are gone from the
≥1% table. `COPY-UNESCAPED-JSON-OCTETS` (3.1% / 5.0%) and
`JSON-INTERNED-ASCII-VALUE-OCTETS` (2.4% / 1.4%) are intern/copy
micro-knives, forbidden. `foreign function read` is OS.

## `session_pipeline.session_load`

```
Number of samples:   973
Sample interval:     0.001 seconds
Total sampling time: 0.973 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=657003 "main thread" RUNNING {1200038003}> (198552/1048576 bytes, 717 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1     68   7.0    799  82.1     68   7.0        -  (LABELS CADR-AGENT::SCAN-BUFFER :IN CADR-AGENT::READ-SESSION-OBJECTS)
   2     65   6.7    115  11.8    133  13.7        -  (LABELS CADR-AGENT::PARSE-STRING-VALUE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   3     57   5.9     57   5.9    190  19.5        -  CADR-AI::OCTET-WINDOW-EQUALS
   4     51   5.2     58   6.0    241  24.8        -  (LABELS CADR-AGENT::SCAN-KEY :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   5     47   4.8     47   4.8    288  29.6        -  (LABELS CADR-AGENT::SKIP-SPACE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   6     46   4.7    710  73.0    334  34.3        -  CADR-AGENT::PARSE-SESSION-RECORD-OCTETS
   7     40   4.1     40   4.1    374  38.4        -  foreign function pthread_sigmask
   8     39   4.0     39   4.0    413  42.4        -  (LABELS CADR-AGENT::EXPECT-CODE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   9     30   3.1     33   3.4    443  45.5        -  CADR-AI::COPY-UNESCAPED-JSON-OCTETS
  10     29   3.0     29   3.0    472  48.5        -  foreign function read
  11     26   2.7     26   2.7    498  51.2        -  SB-KERNEL:STRING=*
  12     25   2.6     56   5.8    523  53.8        -  (LABELS CADR-AGENT::PARSE-TIMESTAMP-VALUE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  13     23   2.4     43   4.4    546  56.1        -  CADR-AI::JSON-INTERNED-ASCII-VALUE-OCTETS
  14     22   2.3    254  26.1    568  58.4        -  (LABELS CADR-AGENT::PARSE-CONTENT-BLOCK :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  15     22   2.3    116  11.9    590  60.6        -  (LABELS CADR-AGENT::PARSE-USAGE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  16     19   2.0     19   2.0    609  62.6        -  CADR-AI::PARSE-JSON-SIMPLE-INTEGER-OCTETS
  17     17   1.7     17   1.7    626  64.3        -  SB-IMPL::BYTES-PER-UTF8-CHARACTER-AREF
  18     15   1.5     46   4.7    641  65.9        -  SB-VM::PREPARE-VECTOR-PUSH-EXTEND
  19     13   1.3     17   1.7    654  67.2        -  CADR-AGENT::MAKE-SESSION-ENTRY
  20     12   1.2     81   8.3    666  68.4        -  SB-IMPL::UTF8->STRING-AREF
  21     11   1.1     11   1.1    677  69.6        -  (LABELS CADR-AGENT::SKIP-NUMBER :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  22     10   1.0     18   1.8    687  70.6        -  CADR-AI::DECODE-ESCAPED-JSON-OCTETS
------------------------------------------------------------------------
         24   2.5                                     elsewhere
```

## `storage_journal.journal_read`

```
Number of samples:   980
Sample interval:     0.001 seconds
Total sampling time: 0.98 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=657004 "finalizer" RUNNING {1200039D13}> (128/1048576 bytes, 1 hash buckets)
   #<THREAD tid=657003 "main thread" RUNNING {1200038003}> (186016/1048576 bytes, 683 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1     70   7.1     70   7.1     70   7.1        -  CADR-AI::OCTET-WINDOW-EQUALS
   2     69   7.0    898  91.6    139  14.2        -  (LABELS CADR-AGENT::SCAN-BUFFER :IN CADR-AGENT::READ-SESSION-OBJECTS)
   3     69   7.0     69   7.0    208  21.2        -  (LABELS CADR-AGENT::SKIP-SPACE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   4     63   6.4    109  11.1    271  27.7        -  (LABELS CADR-AGENT::PARSE-STRING-VALUE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   5     58   5.9     66   6.7    329  33.6        -  (LABELS CADR-AGENT::SCAN-KEY :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   6     54   5.5    803  81.9    383  39.1        -  CADR-AGENT::PARSE-SESSION-RECORD-OCTETS
   7     49   5.0     58   5.9    432  44.1        -  CADR-AI::COPY-UNESCAPED-JSON-OCTETS
   8     43   4.4     43   4.4    475  48.5        -  foreign function pthread_sigmask
   9     34   3.5     34   3.5    509  51.9        -  (LABELS CADR-AGENT::EXPECT-CODE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  10     30   3.1     90   9.2    539  55.0        -  SB-IMPL::UTF8->STRING-AREF
  11     29   3.0     59   6.0    568  58.0        -  (LABELS CADR-AGENT::PARSE-TIMESTAMP-VALUE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  12     28   2.9     28   2.9    596  60.8        -  foreign function read
  13     22   2.2    116  11.8    618  63.1        -  (LABELS CADR-AGENT::PARSE-USAGE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  14     18   1.8    298  30.4    636  64.9        -  (LABELS CADR-AGENT::PARSE-CONTENT-BLOCK :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  15     15   1.5    819  83.6    651  66.4        -  CADR-AGENT::PARSE-SESSION-LINE
  16     15   1.5     15   1.5    666  68.0        -  SB-IMPL::BYTES-PER-UTF8-CHARACTER-AREF
  17     14   1.4     42   4.3    680  69.4        -  CADR-AI::JSON-INTERNED-ASCII-VALUE-OCTETS
  18     14   1.4     36   3.7    694  70.8        -  SB-VM::PREPARE-VECTOR-PUSH-EXTEND
  19     14   1.4     14   1.4    708  72.2        -  CADR-AI::PARSE-JSON-SIMPLE-INTEGER-OCTETS
  20     13   1.3     13   1.3    721  73.6        -  (LABELS CADR-AGENT::KEY= :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  21     12   1.2     12   1.2    733  74.8        -  (LABELS CADR-AGENT::SKIP-NUMBER :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  22     12   1.2     12   1.2    745  76.0        -  CADR-AI::%MAKE-USAGE
  23     11   1.1     11   1.1    756  77.1        -  (FLET CADR-AGENT::DIGITS :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  24     10   1.0    314  32.0    766  78.2        -  (LABELS CADR-AGENT::PARSE-CONTENT-VALUE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
------------------------------------------------------------------------
         32   3.3                                     elsewhere
```

## What this does not authorize

- intern table expand / intern micro-knives
- FFI simdjson / V8 / yyjson
- mmap or observable-byte SIMD (adjudication)
- touching session strings / header again
- changing list_models table assembly
- G.17 `met`, Part P `[done]`, Goal 20 complete
- lowering `RATIO_CEILINGS`
