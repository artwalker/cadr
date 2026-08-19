# Goal 20 Part P — context_walk / argv_parse / help_render sb-sprof

Diagnostic, not a gate. Same driver as `scripts/goal20-profile.sh`
after the 13:20 thunks. Pairing numbers from
`docs/performance.md` (`8d7917472`, Friend-MachineD, n=5).

Do not treat this file as G.17 `met` or Part P `[done]`.
Do not guess `help_render` `format` (board 13:19 / 13:20).

- recordedAt: 2026-08-19T05:18:00Z
- git: `34c2cd511` tree plus driver thunks (HEAD at capture
  still product `67a2d43fb`)
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds per path: 4
- sample-interval: 0.001s
- pairing: walk 113.3 / 107.9 µs (1.05×); argv 5.8 / 3.4 µs
  (1.69×); help 4.7 / 0.8 µs (5.59×)

## Verdict

| path | leftover | class |
|---|---|---|
| `context_walk` | `GETHASH/EQUAL` 18.0% self, `PUTHASH/EQUAL` 5.5%, `SESSION-PATH-ENTRIES` 84.5% total | named: EQUAL hash walk of parent ids on every `session-messages` |
| `argv_parse` | `STRING=*` 29.7%, `%ASSOC-TEST` 17.9%, `PARSE-CLI-ARGUMENTS` 98.8% total | option alist `assoc` / `string=`; 5.8 µs |
| `help_render` | `FORMAT` 16.3% self / 96.5% total, `PRINT-CLI-USAGE` 99.0% total | `format`; board forbids guessing this at 4.7 µs |

`context_walk` is the only unused legal named structure. The
pairing thunk is `session-messages` on an already-loaded
session. `session-path-entries` allocates an EQUAL `seen` table
and `gethash`s `session-by-id` (`:test #'equal`) on each call.

`argv_parse` / `help_render` are sub-6 µs. Recorded. Not this
knife. Not intern. Not FFI.

## `session_pipeline.context_walk`

Thunk: `(cadr-agent:session-messages session)` after one
`load-session` of the pairing fixture.

```
Number of samples:   979
Sample interval:     0.001 seconds
Total sampling time: 0.979 seconds

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    176  18.0    368  37.6    176  18.0        -  SB-IMPL::GETHASH/EQUAL
   2    138  14.1    138  14.1    314  32.1        -  SB-IMPL::%SXHASH-STRING/TRUNCATING
   3    119  12.2    119  12.2    433  44.2        -  SB-KERNEL:STRING=*
   4     79   8.1     79   8.1    512  52.3        -  foreign function pthread_sigmask
   5     54   5.5    410  41.9    566  57.8        -  SB-IMPL::PUTHASH/EQUAL
   6     39   4.0    191  19.5    605  61.8        -  SB-IMPL::PERHAPS-TRUNCATED-EQUAL-HASH
   7     38   3.9    827  84.5    643  65.7        -  CADR-AGENT::SESSION-PATH-ENTRIES
   8     38   3.9    118  12.1    681  69.6        -  SB-IMPL::GROW-HASH-TABLE
   9     30   3.1     30   3.1    711  72.6        -  (LABELS SB-IMPL::EQUAL-NOT-INLINE :IN EQUAL)
  10     28   2.9    212  21.7    739  75.5        -  (FLET SB-IMPL::INSERT-AT :IN "SYS:SRC;CODE;TARGET-HASH-TABLE.LISP")
  11     20   2.0     21   2.1    759  77.5        -  SB-IMPL::REHASH
  12     17   1.7    142  14.5    776  79.3        -  (LABELS SB-IMPL::SXHASH-RECURSE :IN SB-IMPL::PERHAPS-TRUNCATED-EQUAL-HASH)
  13     16   1.6    970  99.1    792  80.9        -  CADR-AGENT:SESSION-MESSAGES
  14     16   1.6     32   3.3    808  82.5        -  FIND
  15     15   1.5     54   5.5    823  84.1        -  SB-IMPL::RAISE-SXSTATE-LIMIT-AND-REHASH
  16     12   1.2     12   1.2    835  85.3        -  VECTOR-FILL/T
  17     11   1.1     11   1.1    846  86.4        -  EQUAL
------------------------------------------------------------------------
         50   5.1                                     elsewhere
```

## `cli_dispatch.argv_parse`

Thunk: `(cadr-cli::parse-cli-arguments parse-argv)` on fixture
`cli-argv.json` key `parse`.

```
Number of samples:   994
Sample interval:     0.001 seconds
Total sampling time: 0.994 seconds

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    295  29.7    295  29.7    295  29.7        -  SB-KERNEL:STRING=*
   2    178  17.9    513  51.6    473  47.6        -  SB-KERNEL:%ASSOC-TEST
   3    121  12.2    121  12.2    594  59.8        -  SB-KERNEL:TWO-ARG-STRING=
   4     32   3.2     38   3.8    626  63.0        -  FIND
   5     31   3.1    982  98.8    657  66.1        -  CADR-CLI::PARSE-CLI-ARGUMENTS
   6     27   2.7     47   4.7    684  68.8        -  POSITION
   7     25   2.5    198  19.9    709  71.3        -  CADR-CLI::SET-CLI-VALUE
   8     21   2.1     21   2.1    730  73.4        -  LENGTH
   9     20   2.0     70   7.0    750  75.5        -  SB-KERNEL:%FIND-POSITION-IF
  10     14   1.4     27   2.7    764  76.9        -  SB-KERNEL:%FIND-POSITION
  11     14   1.4     14   1.4    778  78.3        -  foreign function pthread_sigmask
  12     13   1.3     27   2.7    791  79.6        -  CADR-CLI::MAKE-CLI-ARGUMENTS
  13     11   1.1     11   1.1    802  80.7        -  IDENTITY
  14     10   1.0     40   4.0    812  81.7        -  CADR-CLI::REQUIRE-CLI-VALUE
  15     10   1.0     10   1.0    822  82.7        -  SB-VM::SIMD-POSITION8-AVX2
------------------------------------------------------------------------
          4   0.4                                     elsewhere
```

## `cli_dispatch.help_render`

Thunk: `(cadr-cli::print-cli-usage stream)` to a broadcast
stream. `FORMAT` is 96.5% total. Board: do not guess `format`
at 4.7 µs.

```
Number of samples:   994
Sample interval:     0.001 seconds
Total sampling time: 0.994 seconds

           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    162  16.3    959  96.5    162  16.3        -  FORMAT
   2    149  15.0    149  15.0    311  31.3        -  (LAMBDA (SB-PCL::.ARG0. SB-PCL::.ARG1.) :IN "SYS:SRC;PCL;DLISP3.LISP")
   3     90   9.1    525  52.8    401  40.3        -  PRINC
   4     72   7.2    418  42.1    473  47.6        -  (LABELS SB-IMPL::HANDLE-IT :IN SB-KERNEL:OUTPUT-OBJECT)
   5     63   6.3     76   7.6    536  53.9        -  SB-IMPL::%WRITE-STRING
   6     43   4.3     43   4.3    579  58.2        -  WRITE-CHAR
   7     43   4.3     43   4.3    622  62.6        -  PPRINT-DISPATCH
   8     41   4.1    537  54.0    663  66.7        -  fmt$RTL1B8S4DEJ1
   9     34   3.4    984  99.0    697  70.1        -  CADR-CLI::PRINT-CLI-USAGE
  10     31   3.1     31   3.1    728  73.2        -  SB-KERNEL:OUTPUT-OBJECT
  11     31   3.1     31   3.1    759  76.4        -  WRITE-STRING
  12     26   2.6     67   6.7    785  79.0        -  SB-KERNEL:%CONCATENATE-TO-STRING-SUBSEQ
  13     26   2.6     26   2.6    811  81.6        -  (SB-PCL::FAST-METHOD PRINT-OBJECT (VECTOR T))
  14     24   2.4     24   2.4    835  84.0        -  SB-FORMAT::%FORMAT
  15     22   2.2     22   2.2    857  86.2        -  SB-KERNEL:UB32-BASH-COPY
  16     20   2.0     20   2.0    877  88.2        -  (LAMBDA (STREAM STRING SB-IMPL::START SB-IMPL::END) :IN MAKE-BROADCAST-STREAM)
  17     17   1.7     52   5.2    894  89.9        -  (LABELS SB-IMPL::PRINT-IT :IN SB-KERNEL:OUTPUT-OBJECT)
  18     16   1.6     16   1.6    910  91.5        -  TAIL-CALL-CALLABLE-VARIABLE
  19     14   1.4     14   1.4    924  93.0        -  SB-KERNEL:OUTPUT-UGLY-OBJECT
  20     13   1.3     13   1.3    937  94.3        -  foreign function pthread_sigmask
------------------------------------------------------------------------
         10   1.0                                     elsewhere
```
