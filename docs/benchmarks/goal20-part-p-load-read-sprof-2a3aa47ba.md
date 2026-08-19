# Goal 20 Part P — session_load / journal_read sb-sprof (HEAD `2a3aa47ba`)

Diagnostic, not a gate. Same driver and fixtures as
`scripts/goal20-profile.sh` / `scripts/goal20-paired-paths.lisp`.
Recorded because the 17:05 board asked whether leftover
load/read after SWAR / ub32 key / ASCII block-copy is still
`COPY-UNESCAPED` / `PARSE-STRING-VALUE`, or walker / GC / `read`.

Do not treat this file as G.17 `met` or Part P `[done]`.

- recordedAt: 2026-08-19T09:10:12Z
- git: `2a3aa47ba810`
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds per path: 4
- sample-interval: 0.001s
- driver: `scripts/goal20-profile.sh --seconds 4`
- contrast: [`goal20-part-p-load-read-sprof.md`](goal20-part-p-load-read-sprof.md)
  (`67a2d43fb`, 2026-08-19T05:16:19Z)

## Verdict

Leftover on `session_load` and `journal_read` is still the
session JSONL octet walker, plus the SWAR helpers that now
own skip-space / find-lf, runtime (`pthread_sigmask`), and
foreign `read`. There is no EQUAL-hash rebuild and no
re-entry into `parse-json-octets` / `PARSE-JSON-SOURCE`.

`COPY-UNESCAPED-JSON-OCTETS` dropped (load 3.1%→2.4% self;
read still ~3%). `PARSE-STRING-VALUE` dropped (load
6.7%→2.9% self). The new top names are `SWAR-EQ-MSB` and
`OCTET-SKIP-JSON-SPACE` — already shipped; the board
forbids another word-width guess. `ALLOC-UNSIGNED-BIGNUM-IN-RDX`
(~2%) is the 64-bit SWAR word boxing, not a new algorithm.
`JSON-INTERNED-ASCII-VALUE-OCTETS` remains intern (forbidden).

No unused legal named structure. No `src/` knife.

| path | old top (`67a2d43fb`) | now (`2a3aa47ba`) |
|---|---|---|
| `session_load` | `SCAN-BUFFER` 7.0% self / 82.1% total; `PARSE-STRING-VALUE` 6.7%; `OCTET-WINDOW-EQUALS` 5.9%; `COPY-UNESCAPED` 3.1% | `SWAR-EQ-MSB` 7.7%; `OCTET-SKIP-JSON-SPACE` 7.5% / 10.2%; `PARSE-SESSION-RECORD-OCTETS` 69.7% total; `COPY-UNESCAPED` 2.4%; `PARSE-STRING-VALUE` 2.9% |
| `journal_read` | `SCAN-BUFFER` 7.0% self / 91.6% total; `PARSE-SESSION-RECORD-OCTETS` 81.9% total | `PARSE-SESSION-RECORD-OCTETS` 7.4% / 79.2%; `SWAR-EQ-MSB` 7.4%; `OCTET-SKIP-JSON-SPACE` 7.3%; `COPY-UNESCAPED` 3.3% |

## `cli_dispatch.list_models_render`

```

Number of samples:   983
Sample interval:     0.001 seconds
Total sampling time: 0.983 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=17667 "main thread" RUNNING {1200038003}> (153880/1048576 bytes, 581 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    182  18.5    182  18.5    182  18.5        -  foreign function readlink
   2    156  15.9    156  15.9    338  34.4        -  foreign function fstatat
   3     27   2.7     27   2.7    365  37.1        -  foreign function pthread_sigmask
   4     24   2.4     74   7.5    389  39.6        -  SB-IMPL::STRING-SOUT
   5     24   2.4     63   6.4    413  42.0        -  CADR-TUI::FUZZY-MATCH-NORMALIZED
   6     23   2.3     25   2.5    436  44.4        -  (LABELS SB-IMPL::CHARACTER-OUT :IN SB-IMPL::%INIT-STRING-OUTPUT-STREAM)
   7     20   2.0     39   4.0    456  46.4        -  (FLET CADR-CLI::PAD :IN CADR-CLI::PRINT-CLI-MODELS)
   8     19   1.9     31   3.2    475  48.3        -  (LABELS SB-IMPL::CHAR-STRING-OUT :IN SB-IMPL::%INIT-STRING-OUTPUT-STREAM)
   9     18   1.8     18   1.8    493  50.2        -  SB-KERNEL:UB32-BASH-COPY
  10     17   1.7     17   1.7    510  51.9        -  SB-IMPL::HASH-PATHNAME-PIECE
  11     13   1.3    977  99.4    523  53.2        -  CADR-CLI::PRINT-CLI-MODELS
  12     12   1.2     32   3.3    535  54.4        -  SB-INT:HASHSET-FIND
  13     12   1.2     12   1.2    547  55.6        -  SB-KERNEL:TWO-ARG-+
  14     11   1.1     11   1.1    558  56.8        -  SB-KERNEL:%SP-STRING-COMPARE
  15     10   1.0     10   1.0    568  57.8        -  SB-KERNEL::TRUNCATE1
------------------------------------------------------------------------
         39   4.0                                     elsewhere
```

## `session_pipeline.session_load`

```

Number of samples:   967
Sample interval:     0.001 seconds
Total sampling time: 0.967 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=17667 "main thread" RUNNING {1200038003}> (204848/1048576 bytes, 742 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1     74   7.7     74   7.7     74   7.7        -  CADR-AGENT::SWAR-EQ-MSB
   2     73   7.5     99  10.2    147  15.2        -  CADR-AGENT::OCTET-SKIP-JSON-SPACE
   3     58   6.0    151  15.6    205  21.2        -  (LABELS CADR-AGENT::SKIP-SPACE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   4     46   4.8    674  69.7    251  26.0        -  CADR-AGENT::PARSE-SESSION-RECORD-OCTETS
   5     39   4.0     47   4.9    290  30.0        -  (LABELS CADR-AGENT::SCAN-KEY :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   6     37   3.8     37   3.8    327  33.8        -  (LABELS CADR-AGENT::EXPECT-CODE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   7     36   3.7     36   3.7    363  37.5        -  foreign function pthread_sigmask
   8     35   3.6     83   8.6    398  41.2        -  CADR-AGENT::OCTET-FIND-LF
   9     31   3.2     31   3.2    429  44.4        -  CADR-AI::OCTET-U32-LE
  10     30   3.1    125  12.9    459  47.5        -  (LABELS CADR-AGENT::PARSE-USAGE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  11     28   2.9     68   7.0    487  50.4        -  (LABELS CADR-AGENT::PARSE-STRING-VALUE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  12     23   2.4     32   3.3    510  52.7        -  CADR-AI::COPY-UNESCAPED-JSON-OCTETS
  13     23   2.4     30   3.1    533  55.1        -  CADR-AI::JSON-INTERNED-ASCII-VALUE-OCTETS
  14     21   2.2     29   3.0    554  57.3        -  ALLOC-UNSIGNED-BIGNUM-IN-RDX
  15     19   2.0     19   2.0    573  59.3        -  foreign function read
  16     18   1.9     81   8.4    591  61.1        -  CADR-AGENT::FINALIZE-SESSION-ENTRY
  17     17   1.8     66   6.8    608  62.9        -  SB-IMPL::UTF8->STRING-AREF
  18     14   1.4    214  22.1    622  64.3        -  (LABELS CADR-AGENT::PARSE-CONTENT-BLOCK :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  19     14   1.4     42   4.3    636  65.8        -  (LABELS CADR-AGENT::PARSE-TIMESTAMP-VALUE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  20     14   1.4     14   1.4    650  67.2        -  CADR-AGENT::RECORD-TO-SESSION-ENTRY
  21     13   1.3     13   1.3    663  68.6        -  SB-KERNEL:STRING=*
  22     13   1.3     13   1.3    676  69.9        -  SB-IMPL::BYTES-PER-UTF8-CHARACTER-AREF
  23     10   1.0    689  71.3    686  70.9        -  CADR-AGENT::PARSE-SESSION-LINE
------------------------------------------------------------------------
         44   4.6                                     elsewhere
```

## `storage_journal.journal_read`

```

Number of samples:   973
Sample interval:     0.001 seconds
Total sampling time: 0.973 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=17667 "main thread" RUNNING {1200038003}> (200696/1048576 bytes, 733 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1     72   7.4    771  79.2     72   7.4        -  CADR-AGENT::PARSE-SESSION-RECORD-OCTETS
   2     72   7.4     72   7.4    144  14.8        -  CADR-AGENT::SWAR-EQ-MSB
   3     71   7.3     98  10.1    215  22.1        -  CADR-AGENT::OCTET-SKIP-JSON-SPACE
   4     63   6.5    156  16.0    278  28.6        -  (LABELS CADR-AGENT::SKIP-SPACE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   5     61   6.3     67   6.9    339  34.8        -  (LABELS CADR-AGENT::SCAN-KEY :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   6     52   5.3     52   5.3    391  40.2        -  CADR-AI::OCTET-U32-LE
   7     45   4.6     65   6.7    436  44.8        -  (LABELS CADR-AGENT::PARSE-STRING-VALUE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
   8     37   3.8     37   3.8    473  48.6        -  foreign function pthread_sigmask
   9     32   3.3     43   4.4    505  51.9        -  CADR-AI::COPY-UNESCAPED-JSON-OCTETS
  10     29   3.0     73   7.5    534  54.9        -  CADR-AGENT::OCTET-FIND-LF
  11     28   2.9     28   2.9    562  57.8        -  (LABELS CADR-AGENT::EXPECT-CODE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  12     25   2.6     90   9.2    587  60.3        -  SB-IMPL::UTF8->STRING-AREF
  13     23   2.4     23   2.4    610  62.7        -  foreign function read
  14     20   2.1    122  12.5    630  64.7        -  (LABELS CADR-AGENT::PARSE-USAGE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  15     20   2.1     26   2.7    650  66.8        -  ALLOC-UNSIGNED-BIGNUM-IN-RDX
  16     18   1.8     18   1.8    668  68.7        -  SB-IMPL::BYTES-PER-UTF8-CHARACTER-AREF
  17     17   1.7     17   1.7    685  70.4        -  CADR-AI::PARSE-JSON-SIMPLE-INTEGER-OCTETS
  18     17   1.7     17   1.7    702  72.1        -  (FLET CADR-AGENT::DIGITS :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  19     14   1.4     49   5.0    716  73.6        -  (LABELS CADR-AGENT::PARSE-TIMESTAMP-VALUE :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  20     12   1.2    260  26.7    728  74.8        -  (LABELS CADR-AGENT::PARSE-CONTENT-BLOCK :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
  21     12   1.2     39   4.0    740  76.1        -  SB-VM::PREPARE-VECTOR-PUSH-EXTEND
  22     12   1.2     12   1.2    752  77.3        -  CADR-AI::%MAKE-USAGE
  23     10   1.0     21   2.2    762  78.3        -  CADR-AI::DECODE-ESCAPED-JSON-OCTETS
  24     10   1.0     17   1.7    772  79.3        -  CADR-AI::JSON-INTERNED-ASCII-VALUE-OCTETS
------------------------------------------------------------------------
         51   5.2                                     elsewhere
```

## `storage_journal.journal_append`

```

Number of samples:   995
Sample interval:     0.001 seconds
Total sampling time: 0.995 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=17668 "finalizer" RUNNING {1200039CC3}> (232/1048576 bytes, 2 hash buckets)
   #<THREAD tid=17667 "main thread" RUNNING {1200038003}> (164056/1048576 bytes, 543 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    255  25.6    255  25.6    255  25.6        -  foreign function mkdir
   2    143  14.4    143  14.4    398  40.0        -  foreign function __write
   3     74   7.4    206  20.7    472  47.4        -  CADR-AGENT::EMIT-JSON-STRING
   4     57   5.7     58   5.8    529  53.2        -  SB-VM::PREPARE-VECTOR-PUSH-EXTEND
   5     56   5.6    115  11.6    585  58.8        -  (FLET CADR-AGENT::EMIT-UNESCAPED :IN CADR-AGENT::EMIT-JSON-STRING)
   6     20   2.0     20   2.0    605  60.8        -  foreign function fstatat
   7     17   1.7     17   1.7    622  62.5        -  %DATA-VECTOR-AND-INDEX
   8     14   1.4     14   1.4    636  63.9        -  %DATA-VECTOR-AND-INDEX/CHECK-BOUND
   9     13   1.3     13   1.3    649  65.2        -  foreign function __open64
  10     10   1.0    121  12.2    659  66.2        -  CADR-AGENT::EMIT-JSON-KEY
  11     10   1.0     10   1.0    669  67.2        -  SUBSTITUTE
------------------------------------------------------------------------
         15   1.5                                     elsewhere
```

## `session_pipeline.context_walk`

```

Number of samples:   924
Sample interval:     0.001 seconds
Total sampling time: 0.924 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=17668 "finalizer" RUNNING {1200039CC3}> (232/1048576 bytes, 2 hash buckets)
   #<THREAD tid=17667 "main thread" RUNNING {1200038003}> (12112/1048576 bytes, 53 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    525  56.8    559  60.5    525  56.8        -  COPY-LIST
   2    342  37.0    342  37.0    867  93.8        -  foreign function pthread_sigmask
   3     16   1.7     16   1.7    883  95.6        -  FPR-RESTORE
   4     11   1.2     11   1.2    894  96.8        -  FPR-SAVE
------------------------------------------------------------------------
          4   0.4                                     elsewhere
```

## `cli_dispatch.argv_parse`

```

Number of samples:   994
Sample interval:     0.001 seconds
Total sampling time: 0.994 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=17667 "main thread" RUNNING {1200038003}> (160608/1048576 bytes, 649 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    123  12.4    123  12.4    123  12.4        -  CADR-CLI::CLI-TOKEN-TAIL=
   2     57   5.7     87   8.8    180  18.1        -  FIND
   3     52   5.2    411  41.3    232  23.3        -  CADR-CLI::SET-CLI-VALUE
   4     49   4.9    983  98.9    281  28.3        -  CADR-CLI::PARSE-CLI-ARGUMENTS
   5     49   4.9     93   9.4    330  33.2        -  POSITION
   6     48   4.8     48   4.8    378  38.0        -  SB-KERNEL:STRING=*
   7     46   4.6    206  20.7    424  42.7        -  CADR-CLI::LOOKUP-CLI-OPTION
   8     43   4.3     43   4.3    467  47.0        -  %DATA-VECTOR-AND-INDEX/CHECK-BOUND
   9     42   4.2    161  16.2    509  51.2        -  SB-KERNEL:%FIND-POSITION-IF
  10     34   3.4     34   3.4    543  54.6        -  LENGTH
  11     32   3.2     53   5.3    575  57.8        -  SB-KERNEL:%FIND-POSITION
  12     30   3.0     33   3.3    605  60.9        -  IDENTITY
  13     25   2.5     25   2.5    630  63.4        -  foreign function pthread_sigmask
  14     19   1.9     89   9.0    649  65.3        -  CADR-CLI::REQUIRE-CLI-VALUE
  15     18   1.8     75   7.5    667  67.1        -  CADR-CLI::CLI-OPTION-TOKEN-P
  16     18   1.8     18   1.8    685  68.9        -  (FLET UIOP/UTILITY::SEPARATORP :IN UIOP/UTILITY:SPLIT-STRING)
  17     18   1.8     18   1.8    703  70.7        -  SB-VM::SIMD-POSITION8-AVX2
  18     17   1.7     37   3.7    720  72.4        -  CADR-CLI::CLI-STRING-PREFIX-P
  19     16   1.6     53   5.3    736  74.0        -  CADR-CLI::MAKE-CLI-ARGUMENTS
  20     16   1.6     29   2.9    752  75.7        -  REMOVE
  21     16   1.6     16   1.6    768  77.3        -  EQL
  22     15   1.5    180  18.1    783  78.8        -  POSITION-IF
  23     15   1.5     15   1.5    798  80.3        -  (FLET SB-IMPL::TRIM-CHAR-P :IN SB-IMPL::GENERIC-STRING-TRIM)
  24     13   1.3    104  10.5    811  81.6        -  CADR-CLI::OPTION-WITH-EQUALS
  25     12   1.2     27   2.7    823  82.8        -  SB-IMPL::GENERIC-STRING-TRIM
  26     11   1.1     11   1.1    834  83.9        -  CADR-CLI::SET-CLI-FLAG
  27     11   1.1     11   1.1    845  85.0        -  SB-KERNEL:TWO-ARG-STRING=
  28     10   1.0     10   1.0    855  86.0        -  SB-KERNEL:UB8-BASH-COPY
  29     10   1.0     10   1.0    865  87.0        -  SB-IMPL::%LOOKUP-SYMBOL
------------------------------------------------------------------------
         17   1.7                                     elsewhere
```

## `cli_dispatch.help_render`

```

Number of samples:   1000
Sample interval:     0.001 seconds
Total sampling time: 1.0 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=17667 "main thread" RUNNING {1200038003}> (57568/1048576 bytes, 247 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    284  28.4    284  28.4    284  28.4        -  (LAMBDA (SB-PCL::.ARG0.) :IN "SYS:SRC;PCL;DLISP3.LISP")
   2    107  10.7    151  15.1    391  39.1        -  SB-IMPL::%WRITE-STRING
   3     96   9.6    126  12.6    487  48.7        -  GET-INTERNAL-REAL-TIME
   4     79   7.9     79   7.9    566  56.6        -  SB-IMPL::BROADCAST-MISC
   5     65   6.5    427  42.7    631  63.1        -  CADR-CLI::CLI-STREAM-COLOR-P
   6     51   5.1     51   5.1    682  68.2        -  WRITE-STRING
   7     46   4.6    715  71.5    728  72.8        -  CADR-CLI::PRINT-CLI-USAGE
   8     41   4.1     41   4.1    769  76.9        -  (LAMBDA (STREAM STRING SB-IMPL::START SB-IMPL::END) :IN MAKE-BROADCAST-STREAM)
   9     38   3.8    456  45.6    807  80.7        -  CADR-CLI::WRITE-CLI-USAGE-BLOCK
  10     38   3.8     59   5.9    845  84.5        -  foreign function clock_gettime
  11     37   3.7     62   6.2    882  88.2        -  FINISH-OUTPUT
  12     25   2.5    965  96.5    907  90.7        -  PROFILE-THUNK
  13     25   2.5     25   2.5    932  93.2        -  (LAMBDA NIL :IN RUN-PROFILES)
  14     23   2.3     23   2.3    955  95.5        -  (SB-PCL::FAST-METHOD INTERACTIVE-STREAM-P (SB-KERNEL:ANSI-STREAM))
  15     20   2.0     20   2.0    975  97.5        -  MARK-SYMBOL-CARD
------------------------------------------------------------------------
         18   1.8                                     elsewhere
```

