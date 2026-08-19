# Goal 20 Part P — session_load / journal_read sb-sprof (HEAD `5cc895b84`)

Diagnostic, not a gate. Same driver and fixtures as
`scripts/goal20-profile.sh` / `scripts/goal20-paired-paths.lisp`.
Recorded because the 17:58 board asked whether
`ALLOC-UNSIGNED-BIGNUM-IN-RDX` is gone after the two-ub32
SWAR knife, and what load/read leftover remains.

Do not treat this file as G.17 `met` or Part P `[done]`.

- recordedAt: 2026-08-19T10:02:31Z
- git: `5cc895b84d92`
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds per path: 4
- sample-interval: 0.001s
- driver: `scripts/goal20-profile.sh --seconds 4`
- contrast: [`goal20-part-p-load-read-sprof-2a3aa47ba.md`](goal20-part-p-load-read-sprof-2a3aa47ba.md)
  (`2a3aa47ba`, 2026-08-19T09:10:12Z)

## Verdict

`ALLOC-UNSIGNED-BIGNUM-IN-RDX` is gone from both load and
read (not in the ≥1% table). The 64-bit SWAR word no
longer boxes.

Leftover on `session_load` and `journal_read` is still the
session JSONL octet walker, plus `OCTET-U32-LE` (the two
ub32 loads that replaced `%vector-raw-bits`), skip-space /
find-lf / `SWAR-EQ-MSB`, runtime (`pthread_sigmask`), and
foreign `read`. There is no EQUAL-hash rebuild and no
re-entry into `parse-json-octets` / `PARSE-JSON-SOURCE`.

`SWAR-EQ-MSB` dropped (load 7.7%→4.9% self; read
7.4%→4.8%). `OCTET-U32-LE` is the new top (load 10.6%;
read 11.4%). That helper is already shipped; this booking
does not change `src/`. Do not guess `SCAN-KEY`.
`JSON-INTERNED-ASCII-VALUE-OCTETS` remains intern
(forbidden). `COPY-UNESCAPED` 2.4%→3.9% load (share
shift after boxing left); read 3.3%→2.8%.

No unused legal named structure. No `src/` knife.

| path | old top (`2a3aa47ba`) | now (`5cc895b84`) |
|---|---|---|
| `session_load` | `SWAR-EQ-MSB` 7.7%; `OCTET-SKIP-JSON-SPACE` 7.5% / 10.2%; `PARSE-SESSION-RECORD-OCTETS` 69.7% total; `COPY-UNESCAPED` 2.4%; `ALLOC-UNSIGNED-BIGNUM-IN-RDX` 2.2% | `OCTET-U32-LE` 10.6%; `OCTET-FIND-LF` 6.3% / 14.3%; `OCTET-SKIP-JSON-SPACE` 6.2% / 12.6%; `SWAR-EQ-MSB` 4.9%; `PARSE-SESSION-RECORD-OCTETS` 71.4% total; no bignum |
| `journal_read` | `PARSE-SESSION-RECORD-OCTETS` 7.4% / 79.2%; `SWAR-EQ-MSB` 7.4%; `OCTET-SKIP-JSON-SPACE` 7.3%; `ALLOC-UNSIGNED-BIGNUM-IN-RDX` 2.1% | `OCTET-U32-LE` 11.4%; `OCTET-FIND-LF` 6.4% / 15.5%; `SCAN-KEY` 6.4%; `PARSE-SESSION-RECORD-OCTETS` 4.9% / 78.4%; `SWAR-EQ-MSB` 4.8%; no bignum |

## `cli_dispatch.list_models_render`

```

Number of samples:   981
Sample interval:     0.001 seconds
Total sampling time: 0.981 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=54096 "finalizer" RUNNING {1200039C33}> (128/1048576 bytes, 1 hash buckets)
   #<THREAD tid=54094 "main thread" RUNNING {1200038003}> (139288/1048576 bytes, 531 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    214  21.8    214  21.8    214  21.8        -  foreign function readlink
   2    143  14.6    143  14.6    357  36.4        -  foreign function fstatat
   3     42   4.3     42   4.3    399  40.7        -  foreign function pthread_sigmask
   4     30   3.1     73   7.4    429  43.7        -  SB-IMPL::STRING-SOUT
   5     20   2.0     67   6.8    449  45.8        -  CADR-TUI::FUZZY-MATCH-NORMALIZED
   6     19   1.9     22   2.2    468  47.7        -  (LABELS SB-IMPL::CHARACTER-OUT :IN SB-IMPL::%INIT-STRING-OUTPUT-STREAM)
   7     12   1.2     32   3.3    480  48.9        -  (FLET CADR-CLI::PAD :IN CADR-CLI::PRINT-CLI-MODELS)
   8     12   1.2     12   1.2    492  50.2        -  SB-IMPL::HASH-PATHNAME-PIECE
   9     12   1.2     12   1.2    504  51.4        -  SB-KERNEL::CEILING1
  10     12   1.2     12   1.2    516  52.6        -  SB-KERNEL:UB32-BASH-COPY
  11     11   1.1     18   1.8    527  53.7        -  SB-KERNEL:TWO-ARG--
  12     10   1.0     10   1.0    537  54.7        -  SB-KERNEL:TWO-ARG-+
  13     10   1.0     10   1.0    547  55.8        -  SB-KERNEL::TRUNCATE1
  14     10   1.0     10   1.0    557  56.8        -  SB-KERNEL:%SP-STRING-COMPARE
------------------------------------------------------------------------
         38   3.9                                     elsewhere
```

## `session_pipeline.session_load`

```

Number of samples:   972
Sample interval:     0.001 seconds
Total sampling time: 0.972 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=54094 "main thread" RUNNING {1200038003}> (199176/1048576 bytes, 715 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    103  10.6    103  10.6    103  10.6        -  CADR-AI::OCTET-U32-LE
   2     61   6.3    139  14.3    164  16.9        -  CADR-AGENT::OCTET-FIND-LF
   3     60   6.2    122  12.6    224  23.0        -  CADR-AGENT::OCTET-SKIP-JSON-SPACE
   4     50   5.1     58   6.0    274  28.2        -  (LABELS CADR-AGENT::SCAN-KEY :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   5     48   4.9     48   4.9    322  33.1        -  CADR-AGENT::SWAR-EQ-MSB
   6     46   4.7    694  71.4    368  37.9        -  CADR-AGENT::PARSE-SESSION-RECORD-OCTETS
   7     43   4.4    154  15.8    411  42.3        -  (LABELS CADR-AGENT::SKIP-SPACE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   8     42   4.3     72   7.4    453  46.6        -  (LABELS CADR-AGENT::PARSE-STRING-VALUE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   9     38   3.9     50   5.1    491  50.5        -  CADR-AI::COPY-UNESCAPED-JSON-OCTETS
  10     34   3.5     34   3.5    525  54.0        -  foreign function pthread_sigmask
  11     26   2.7     26   2.7    551  56.7        -  (LABELS CADR-AGENT::EXPECT-CODE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  12     25   2.6     48   4.9    576  59.3        -  CADR-AGENT::SWAR-WS-MASK
  13     20   2.1     49   5.0    596  61.3        -  (LABELS CADR-AGENT::PARSE-TIMESTAMP-VALUE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  14     19   2.0     29   3.0    615  63.3        -  CADR-AI::JSON-INTERNED-ASCII-VALUE-OCTETS
  15     18   1.9     18   1.9    633  65.1        -  SB-KERNEL:STRING=*
  16     16   1.6    239  24.6    649  66.8        -  (LABELS CADR-AGENT::PARSE-CONTENT-BLOCK :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  17     16   1.6     73   7.5    665  68.4        -  SB-IMPL::UTF8->STRING-AREF
  18     14   1.4     18   1.9    679  69.9        -  CADR-AGENT::MAKE-SESSION-ENTRY
  19     14   1.4     14   1.4    693  71.3        -  SB-IMPL::BYTES-PER-UTF8-CHARACTER-AREF
  20     13   1.3     87   9.0    706  72.6        -  (LABELS CADR-AGENT::PARSE-USAGE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  21     13   1.3     13   1.3    719  74.0        -  foreign function read
  22     11   1.1     11   1.1    730  75.1        -  (FLET CADR-AGENT::DIGITS :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  23     10   1.0     10   1.0    740  76.1        -  CADR-AI::PARSE-JSON-SIMPLE-INTEGER-OCTETS
------------------------------------------------------------------------
         32   3.3                                     elsewhere
```

## `storage_journal.journal_read`

```

Number of samples:   975
Sample interval:     0.001 seconds
Total sampling time: 0.975 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=54094 "main thread" RUNNING {1200038003}> (188680/1048576 bytes, 688 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    111  11.4    111  11.4    111  11.4        -  CADR-AI::OCTET-U32-LE
   2     62   6.4    151  15.5    173  17.7        -  CADR-AGENT::OCTET-FIND-LF
   3     62   6.4     71   7.3    235  24.1        -  (LABELS CADR-AGENT::SCAN-KEY :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   4     60   6.2    167  17.1    295  30.3        -  (LABELS CADR-AGENT::SKIP-SPACE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   5     54   5.5     72   7.4    349  35.8        -  (LABELS CADR-AGENT::PARSE-STRING-VALUE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   6     53   5.4    114  11.7    402  41.2        -  CADR-AGENT::OCTET-SKIP-JSON-SPACE
   7     48   4.9    764  78.4    450  46.2        -  CADR-AGENT::PARSE-SESSION-RECORD-OCTETS
   8     47   4.8     47   4.8    497  51.0        -  CADR-AGENT::SWAR-EQ-MSB
   9     35   3.6     35   3.6    532  54.6        -  foreign function pthread_sigmask
  10     30   3.1    136  13.9    562  57.6        -  (LABELS CADR-AGENT::PARSE-USAGE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  11     29   3.0     48   4.9    591  60.6        -  CADR-AGENT::SWAR-WS-MASK
  12     27   2.8     47   4.8    618  63.4        -  CADR-AI::COPY-UNESCAPED-JSON-OCTETS
  13     23   2.4     92   9.4    641  65.7        -  SB-IMPL::UTF8->STRING-AREF
  14     23   2.4     23   2.4    664  68.1        -  (LABELS CADR-AGENT::EXPECT-CODE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  15     20   2.1     51   5.2    684  70.2        -  (LABELS CADR-AGENT::PARSE-TIMESTAMP-VALUE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  16     18   1.8     18   1.8    702  72.0        -  SB-IMPL::BYTES-PER-UTF8-CHARACTER-AREF
  17     17   1.7    266  27.3    719  73.7        -  (LABELS CADR-AGENT::PARSE-CONTENT-BLOCK :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  18     15   1.5     15   1.5    734  75.3        -  foreign function read
  19     12   1.2     12   1.2    746  76.5        -  (LABELS CADR-AGENT::SKIP-NUMBER :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  20     11   1.1     41   4.2    757  77.6        -  SB-VM::PREPARE-VECTOR-PUSH-EXTEND
  21     11   1.1     16   1.6    768  78.8        -  CADR-AI::JSON-INTERNED-ASCII-VALUE-OCTETS
  22     10   1.0     10   1.0    778  79.8        -  (FLET CADR-AGENT::DIGITS :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  23     10   1.0     10   1.0    788  80.8        -  CADR-AI::PARSE-JSON-SIMPLE-INTEGER-OCTETS
------------------------------------------------------------------------
         43   4.4                                     elsewhere
```

## `storage_journal.journal_append`

```

Number of samples:   988
Sample interval:     0.001 seconds
Total sampling time: 0.988 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=54096 "finalizer" RUNNING {1200039C33}> (128/1048576 bytes, 1 hash buckets)
   #<THREAD tid=54094 "main thread" RUNNING {1200038003}> (149800/1048576 bytes, 496 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    234  23.7    234  23.7    234  23.7        -  foreign function mkdir
   2    184  18.6    184  18.6    418  42.3        -  foreign function __write
   3     67   6.8    190  19.2    485  49.1        -  CADR-AGENT::EMIT-JSON-STRING
   4     55   5.6     59   6.0    540  54.7        -  SB-VM::PREPARE-VECTOR-PUSH-EXTEND
   5     43   4.4    103  10.4    583  59.0        -  (FLET CADR-AGENT::EMIT-UNESCAPED :IN CADR-AGENT::EMIT-JSON-STRING)
   6     28   2.8     28   2.8    611  61.8        -  %DATA-VECTOR-AND-INDEX
   7     21   2.1     21   2.1    632  64.0        -  foreign function fstatat
   8     15   1.5     15   1.5    647  65.5        -  foreign function __open64
   9     14   1.4    216  21.9    661  66.9        -  CADR-AGENT::EMIT-JSON-VALUE
  10     13   1.3     25   2.5    674  68.2        -  SB-IMPL::VECTOR-SUBSTITUTE
  11     13   1.3     13   1.3    687  69.5        -  %DATA-VECTOR-AND-INDEX/CHECK-BOUND
  12     11   1.1     16   1.6    698  70.6        -  SB-FORMAT::FORMAT-WRITE-FIELD
  13     10   1.0    101  10.2    708  71.7        -  CADR-AGENT::EMIT-JSON-KEY
------------------------------------------------------------------------
         29   2.9                                     elsewhere
```

## `session_pipeline.context_walk`

```

Number of samples:   890
Sample interval:     0.001 seconds
Total sampling time: 0.89 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=54096 "finalizer" RUNNING {1200039C33}> (248/1048576 bytes, 2 hash buckets)
   #<THREAD tid=54094 "main thread" RUNNING {1200038003}> (11352/1048576 bytes, 50 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    487  54.7    516  58.0    487  54.7        -  COPY-LIST
   2    349  39.2    349  39.2    836  93.9        -  foreign function pthread_sigmask
   3     15   1.7     15   1.7    851  95.6        -  FPR-RESTORE
------------------------------------------------------------------------
          2   0.2                                     elsewhere
```

## `cli_dispatch.argv_parse`

```

Number of samples:   991
Sample interval:     0.001 seconds
Total sampling time: 0.991 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=54096 "finalizer" RUNNING {1200039C33}> (128/1048576 bytes, 1 hash buckets)
   #<THREAD tid=54094 "main thread" RUNNING {1200038003}> (155216/1048576 bytes, 628 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    121  12.2    121  12.2    121  12.2        -  CADR-CLI::CLI-TOKEN-TAIL=
   2     66   6.7     81   8.2    187  18.9        -  FIND
   3     51   5.1     51   5.1    238  24.0        -  %DATA-VECTOR-AND-INDEX/CHECK-BOUND
   4     51   5.1     51   5.1    289  29.2        -  SB-KERNEL:STRING=*
   5     46   4.6    390  39.4    335  33.8        -  CADR-CLI::SET-CLI-VALUE
   6     44   4.4    208  21.0    379  38.2        -  CADR-CLI::LOOKUP-CLI-OPTION
   7     41   4.1     41   4.1    420  42.4        -  LENGTH
   8     40   4.0    968  97.7    460  46.4        -  CADR-CLI::PARSE-CLI-ARGUMENTS
   9     40   4.0     79   8.0    500  50.5        -  POSITION
  10     35   3.5    145  14.6    535  54.0        -  SB-KERNEL:%FIND-POSITION-IF
  11     31   3.1     64   6.5    566  57.1        -  CADR-CLI::CLI-STRING-PREFIX-P
  12     30   3.0     44   4.4    596  60.1        -  SB-KERNEL:%FIND-POSITION
  13     28   2.8     28   2.8    624  63.0        -  foreign function pthread_sigmask
  14     21   2.1    170  17.2    645  65.1        -  POSITION-IF
  15     20   2.0     20   2.0    665  67.1        -  (FLET UIOP/UTILITY::SEPARATORP :IN UIOP/UTILITY:SPLIT-STRING)
  16     19   1.9    269  27.1    684  69.0        -  CADR-CLI::SPLIT-COMMA-OPTION
  17     19   1.9     99  10.0    703  70.9        -  CADR-CLI::OPTION-WITH-EQUALS
  18     18   1.8     18   1.8    721  72.8        -  SB-KERNEL:UB8-BASH-COPY
  19     18   1.8     18   1.8    739  74.6        -  IDENTITY
  20     17   1.7    106  10.7    756  76.3        -  CADR-CLI::CLI-OPTION-TOKEN-P
  21     16   1.6     61   6.2    772  77.9        -  CADR-CLI::MAKE-CLI-ARGUMENTS
  22     15   1.5     27   2.7    787  79.4        -  SB-IMPL::GENERIC-STRING-TRIM
  23     12   1.2    108  10.9    799  80.6        -  CADR-CLI::REQUIRE-CLI-VALUE
  24     12   1.2     12   1.2    811  81.8        -  (FLET SB-IMPL::TRIM-CHAR-P :IN SB-IMPL::GENERIC-STRING-TRIM)
  25     11   1.1     20   2.0    822  82.9        -  REMOVE
  26     11   1.1     12   1.2    833  84.1        -  SB-IMPL::%LOOKUP-SYMBOL
  27     11   1.1     11   1.1    844  85.2        -  SB-VM::SIMD-POSITION8-AVX2
  28     11   1.1     11   1.1    855  86.3        -  SB-KERNEL:%COERCE-CALLABLE-TO-FUN
  29     11   1.1     11   1.1    866  87.4        -  CADR-CLI::SET-CLI-FLAG
------------------------------------------------------------------------
         23   2.3                                     elsewhere
```

## `cli_dispatch.help_render`

```

Number of samples:   999
Sample interval:     0.001 seconds
Total sampling time: 0.999 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=54094 "main thread" RUNNING {1200038003}> (48600/1048576 bytes, 208 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    319  31.9    319  31.9    319  31.9        -  (LAMBDA (SB-PCL::.ARG0.) :IN "SYS:SRC;PCL;DLISP3.LISP")
   2     85   8.5    118  11.8    404  40.4        -  SB-IMPL::%WRITE-STRING
   3     85   8.5     85   8.5    489  48.9        -  SB-IMPL::BROADCAST-MISC
   4     69   6.9     97   9.7    558  55.9        -  GET-INTERNAL-REAL-TIME
   5     68   6.8    454  45.4    626  62.7        -  CADR-CLI::CLI-STREAM-COLOR-P
   6     63   6.3    505  50.6    689  69.0        -  CADR-CLI::WRITE-CLI-USAGE-BLOCK
   7     49   4.9     49   4.9    738  73.9        -  (LAMBDA (STREAM STRING SB-IMPL::START SB-IMPL::END) :IN MAKE-BROADCAST-STREAM)
   8     48   4.8    749  75.0    786  78.7        -  CADR-CLI::PRINT-CLI-USAGE
   9     42   4.2     42   4.2    828  82.9        -  WRITE-STRING
  10     31   3.1    962  96.3    859  86.0        -  PROFILE-THUNK
  11     31   3.1     50   5.0    890  89.1        -  foreign function clock_gettime
  12     24   2.4     24   2.4    914  91.5        -  MARK-SYMBOL-CARD
  13     23   2.3     56   5.6    937  93.8        -  FINISH-OUTPUT
  14     22   2.2     22   2.2    959  96.0        -  (SB-PCL::FAST-METHOD INTERACTIVE-STREAM-P (SB-KERNEL:ANSI-STREAM))
  15     20   2.0     20   2.0    979  98.0        -  (LAMBDA NIL :IN RUN-PROFILES)
------------------------------------------------------------------------
         11   1.1                                     elsewhere
```

