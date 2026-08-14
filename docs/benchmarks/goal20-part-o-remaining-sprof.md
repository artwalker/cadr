# Goal 20 Part O remaining-path sb-sprof

Diagnostic capture, not a gate. Same fixtures as
`scripts/goal20-paired-paths.lisp`. Recorded because
the four Part O paths are still above 1.0x after
probes 7a-7d.

- recordedAt: 2026-08-14T18:06:55Z
- git: `7cf6c3ca7a77`
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds per path: 4
- sample-interval: 0.001s

## `cli_dispatch.list_models_render`

```

Number of samples:   982
Sample interval:     0.001 seconds
Total sampling time: 0.982 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=3757569 "main thread" RUNNING {1200038003}> (188368/1048576 bytes, 621 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1     75   7.6     75   7.6     75   7.6        -  foreign function readlink
   2     74   7.5     74   7.5    149  15.2        -  SB-KERNEL:STRING=*
   3     73   7.4     73   7.4    222  22.6        -  SB-KERNEL:%SP-STRING-COMPARE
   4     72   7.3     72   7.3    294  29.9        -  foreign function fstatat
   5     51   5.2     51   5.2    345  35.1        -  foreign function pthread_sigmask
   6     36   3.7    105  10.7    381  38.8        -  SB-KERNEL:STRING<*
   7     35   3.6     51   5.2    416  42.4        -  STRING-DOWNCASE
   8     29   3.0     48   4.9    445  45.3        -  SB-IMPL::INPUT-CHAR/UTF-8/LF
   9     26   2.6     26   2.6    471  48.0        -  foreign function __open64
  10     25   2.5     25   2.5    496  50.5        -  foreign function access
  11     24   2.4    223  22.7    520  53.0        -  SB-IMPL::MERGE-LISTS*
  12     21   2.1    108  11.0    541  55.1        -  (LAMBDA (CADR-CLI::LEFT CADR-CLI::RIGHT) :IN CADR-CLI:REFRESH-MODEL-REGISTRY)
  13     20   2.0     23   2.3    561  57.1        -  CADR-AI:MAKE-MODEL
  14     19   1.9     19   1.9    580  59.1        -  foreign function read
  15     17   1.7     17   1.7    597  60.8        -  (LABELS CADR-AI::PEEK :IN CADR-AI::PARSE-JSON-SOURCE)
  16     16   1.6     79   8.0    613  62.4        -  REMOVE
  17     14   1.4     14   1.4    627  63.8        -  CADR-AI:MODEL-ID
  18     11   1.1    317  32.3    638  65.0        -  (LABELS SB-IMPL::RECUR :IN SB-IMPL::STABLE-SORT-LIST)
  19     10   1.0    473  48.2    648  66.0        -  (LABELS CADR-CLI::CONFIGURED-P :IN CADR-CLI::MODEL-REGISTRY-AVAILABLE-MODELS)
  20     10   1.0     10   1.0    658  67.0        -  CADR-AI:MODEL-METADATA-ID
  21     10   1.0     10   1.0    668  68.0        -  STRING<
  22     10   1.0     10   1.0    678  69.0        -  foreign function __fstat64
------------------------------------------------------------------------
         60   6.1                                     elsewhere
```

## `session_pipeline.session_load`

```

Number of samples:   947
Sample interval:     0.001 seconds
Total sampling time: 0.9470000000000001 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=3757569 "main thread" RUNNING {1200038003}> (225272/1048576 bytes, 785 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    157  16.6    157  16.6    157  16.6        -  (LABELS CADR-AI::PEEK :IN CADR-AI::PARSE-JSON-SOURCE)
   2     63   6.7    385  40.7    220  23.2        -  (LABELS CADR-AI::PARSE-STRING :IN CADR-AI::PARSE-JSON-SOURCE)
   3     63   6.7    126  13.3    283  29.9        -  (LABELS CADR-AI::TAKE :IN CADR-AI::PARSE-JSON-SOURCE)
   4     44   4.6     48   5.1    327  34.5        -  (LABELS SB-IMPL::CHARACTER-OUT :IN SB-IMPL::%INIT-STRING-OUTPUT-STREAM)
   5     42   4.4    723  76.3    369  39.0        -  (LABELS CADR-AI::PARSE-VALUE :IN CADR-AI::PARSE-JSON-SOURCE)
   6     41   4.3     41   4.3    410  43.3        -  foreign function pthread_sigmask
   7     31   3.3     77   8.1    441  46.6        -  SB-IMPL::GETHASH/EQUAL
   8     26   2.7     26   2.7    467  49.3        -  (LABELS SB-IMPL::EQUAL-NOT-INLINE :IN EQUAL)
   9     25   2.6     81   8.6    492  52.0        -  GET-OUTPUT-STREAM-STRING
  10     20   2.1     30   3.2    512  54.1        -  (LAMBDA (SB-IMPL::RESULT SB-IMPL::SOURCE SB-IMPL::START SB-IMPL::SCALE) :IN GET-OUTPUT-STREAM-STRING)
  11     17   1.8     17   1.8    529  55.9        -  %DATA-VECTOR-AND-INDEX/CHECK-BOUND
  12     15   1.6     15   1.6    544  57.4        -  SB-IMPL::%SXHASH-STRING/TRUNCATING
  13     14   1.5     75   7.9    558  58.9        -  SB-IMPL::PUTHASH/EQUAL
  14     13   1.4     38   4.0    571  60.3        -  (LABELS CADR-AI::EXPECT :IN CADR-AI::PARSE-JSON-SOURCE)
  15     13   1.4     25   2.6    584  61.7        -  SB-IMPL::GROW-HASH-TABLE
  16     13   1.4     13   1.4    597  63.0        -  GENERIC-<
  17     13   1.4     13   1.4    610  64.4        -  GENERIC-+
  18     12   1.3     28   3.0    622  65.7        -  SB-IMPL::FD-STREAM-READ-N-CHARACTERS/UTF-8
  19     11   1.2    165  17.4    633  66.8        -  CADR-AGENT::RECORD-TO-SESSION-ENTRY
  20     10   1.1     20   2.1    643  67.9        -  SB-KERNEL:VECTOR-SUBSEQ
  21     10   1.1     10   1.1    653  69.0        -  SB-IMPL::%INIT-STRING-OUTPUT-STREAM
  22     10   1.1     10   1.1    663  70.0        -  (LABELS CADR-AI::CURRENT :IN CADR-AI::VALID-JSON-NUMBER-TOKEN-P)
  23     10   1.1     10   1.1    673  71.1        -  foreign function read
  24      9   1.0     38   4.0    682  72.0        -  (LABELS CADR-AI::SKIP-SPACE :IN CADR-AI::PARSE-JSON-SOURCE)
  25      9   1.0      9   1.0    691  73.0        -  SB-KERNEL:STRING=*
------------------------------------------------------------------------
         45   4.8                                     elsewhere
```

## `storage_journal.journal_read`

```

Number of samples:   914
Sample interval:     0.001 seconds
Total sampling time: 0.914 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=3757571 "finalizer" RUNNING {1200039CF3}> (128/1048576 bytes, 1 hash buckets)
   #<THREAD tid=3757569 "main thread" RUNNING {1200038003}> (206720/1048576 bytes, 725 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    180  19.7    180  19.7    180  19.7        -  (LABELS CADR-AI::PEEK :IN CADR-AI::PARSE-JSON-SOURCE)
   2     77   8.4    148  16.2    257  28.1        -  (LABELS CADR-AI::TAKE :IN CADR-AI::PARSE-JSON-SOURCE)
   3     73   8.0    456  49.9    330  36.1        -  (LABELS CADR-AI::PARSE-STRING :IN CADR-AI::PARSE-JSON-SOURCE)
   4     49   5.4    105  11.5    379  41.5        -  GET-OUTPUT-STREAM-STRING
   5     47   5.1    862  94.3    426  46.6        -  (LABELS CADR-AI::PARSE-VALUE :IN CADR-AI::PARSE-JSON-SOURCE)
   6     46   5.0     49   5.4    472  51.6        -  (LABELS SB-IMPL::CHARACTER-OUT :IN SB-IMPL::%INIT-STRING-OUTPUT-STREAM)
   7     45   4.9     45   4.9    517  56.6        -  foreign function pthread_sigmask
   8     23   2.5     30   3.3    540  59.1        -  (LAMBDA (SB-IMPL::RESULT SB-IMPL::SOURCE SB-IMPL::START SB-IMPL::SCALE) :IN GET-OUTPUT-STREAM-STRING)
   9     20   2.2     65   7.1    560  61.3        -  (LABELS CADR-AI::SKIP-SPACE :IN CADR-AI::PARSE-JSON-SOURCE)
  10     19   2.1     19   2.1    579  63.3        -  %DATA-VECTOR-AND-INDEX/CHECK-BOUND
  11     18   2.0     32   3.5    597  65.3        -  SB-IMPL::FD-STREAM-READ-N-CHARACTERS/UTF-8
  12     17   1.9     46   5.0    614  67.2        -  (LABELS CADR-AI::EXPECT :IN CADR-AI::PARSE-JSON-SOURCE)
  13     16   1.8     83   9.1    630  68.9        -  SB-IMPL::PUTHASH/EQUAL
  14     16   1.8     24   2.6    646  70.7        -  SB-IMPL::GROW-HASH-TABLE
  15     15   1.6     15   1.6    661  72.3        -  GENERIC-<
  16     14   1.5     14   1.5    675  73.9        -  (LABELS CADR-AI::CURRENT :IN CADR-AI::VALID-JSON-NUMBER-TOKEN-P)
  17     13   1.4     13   1.4    688  75.3        -  SB-KERNEL:UB32-BASH-COPY
  18     12   1.3     12   1.3    700  76.6        -  SB-IMPL::%INIT-STRING-OUTPUT-STREAM
  19     11   1.2     11   1.2    711  77.8        -  SB-IMPL::PARSE-INTEGER10
  20      9   1.0      9   1.0    720  78.8        -  GENERIC-+
------------------------------------------------------------------------
         51   5.6                                     elsewhere
```

## `storage_journal.journal_append`

```

Number of samples:   994
Sample interval:     0.001 seconds
Total sampling time: 0.994 seconds
Graph cycles:        0
Sampled threads:
   #<THREAD tid=3757569 "main thread" RUNNING {1200038003}> (132696/1048576 bytes, 444 hash buckets)

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    160  16.1    160  16.1    160  16.1        -  foreign function mkdir
   2    113  11.4    113  11.4    273  27.5        -  foreign function __open64
   3     84   8.5     84   8.5    357  35.9        -  foreign function __write
   4     76   7.6     76   7.6    433  43.6        -  foreign function access
   5     43   4.3    129  13.0    476  47.9        -  CADR-AI::WRITE-JSON-STRING
   6     41   4.1     41   4.1    517  52.0        -  foreign function __close
   7     28   2.8     28   2.8    545  54.8        -  WRITE-CHAR
   8     28   2.8     28   2.8    573  57.6        -  foreign function pthread_sigmask
   9     22   2.2     22   2.2    595  59.9        -  foreign function lseek64
  10     18   1.8     18   1.8    613  61.7        -  SB-KERNEL:VECTOR-HAIRY-DATA-VECTOR-REF/CHECK-BOUNDS
  11     16   1.6    258  26.0    629  63.3        -  CADR-AI::WRITE-JSON-VALUE
  12     15   1.5     44   4.4    644  64.8        -  (LABELS SB-IMPL::CHARACTER-OUT :IN SB-IMPL::%INIT-STRING-OUTPUT-STREAM)
  13     14   1.4     14   1.4    658  66.2        -  foreign function __fstat64
  14     12   1.2     48   4.8    670  67.4        -  CADR-AI::JSON-OBJECT
  15     10   1.0     10   1.0    680  68.4        -  (SB-VM::OPTIMIZED-DATA-VECTOR-REF CHARACTER)
  16     10   1.0     10   1.0    690  69.4        -  (SB-VM::OPTIMIZED-DATA-VECTOR-REF BASE-CHAR)
------------------------------------------------------------------------
         27   2.7                                     elsewhere
```

## Interpretation

Probes 7a–7d are exhausted. These four paths remain above 1.0×
(enforced, Friend-MachineD, `6211fff2f` / `a29f59c3f` ledger). The
profiles say where, so "still slower" is not the conclusion.

### `list_models_render` (~2.8×)

The timed thunk is the whole `print-cli-models`, which rebuilds the
registry. Top samples are `readlink` / `fstatat` / `access` / `open`,
`STRING=*`, `refresh-model-registry` sort, and `parse-json` peek.
Per-cell `format` does not appear in the top 20. Probe 7d (batch
`write-string` of padded rows) was the wrong cost centre, which matches
the measured regression 2.74× → 2.97×.

### `journal_read` (~5.4×) and `session_load` (~6.7×)

Both are `parse-json`. `PEEK` is 17–20% self; `PARSE-STRING` is 7–8%
self and ~41–50% total; `PARSE-VALUE` is 76–94% total. The rest is
string-output-stream and hash-table growth. Probe 7b (unescaped
`write-string` spans) did not beat peek/take and measured worse. A
different parser (displaced windows, or an adjudicated library) is a
new proposal, not another locked probe.

### `journal_append` (~1.9×)

`mkdir` / `open` / `write` / `access` / `close` are ~40% self. The
harness creates a fresh session directory per sample, so this is
create-session I/O plus stringify (`WRITE-JSON-VALUE` 26% total,
`WRITE-JSON-STRING` 4% self). Probe 7a removed per-id OS RNG. Probe 7c
(fd cache) was skipped because the post-7a ratio was not still above
2×. Further append work is a new proposal.

### What this does not authorize

- Lowering `RATIO_CEILINGS` (ratios are not at 1.0×).
- yason/shasht, mmap, JSONL format change, `uuid-v7`, lowering
  `safety`.
- Calling 7b/7d "untried"; they were tried and lost.

Part O's remaining gap is **blocked** pending adjudication of a new
probe. `scripts/goal20-profile.sh` reproduces this capture.

