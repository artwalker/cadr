# Goal 20 Part P — `tool_read.text_file` sb-sprof (line table `c2828e831`)

Diagnostic, not a gate. Same 4000-line pairing fixture and
production `read-tool-file` as `scripts/goal20-paired-paths.lisp`.
Friend-MachineD remesure `6e07dbb08`: **2.88×** (12786 / 4442 µs),
ceiling 8.0.

This profile is of the **line-start table** read, not the
pre-`c2828e831` cons split. Do not treat as G.17 `met` or Part P
`[done]`.

- git: `c2828e831` (product; booked from HEAD `6e07dbb08`)
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds: 4
- sample-interval: 0.001s
- samples: 968

## Verdict

Named leftover is **not** the line table. `SPLIT-LINE-STARTS`
is 2.0% self. The paired thunk still reads the file every
call (`uiop:read-file-string`, same as pi `readFile` +
`toString`). Self is SBCL stream UTF-8:

`INPUT-CHAR/UTF-8/LF` 47.3% self / 48.0% total, then
`ANSI-STREAM-READ-SEQUENCE` 74.5% total. After ingest,
`TRUNCATE-HARNESS-HEAD` 5.1% self / 8.3% total. Foreign
`read` 1.7%. pthread 5.4%.

The cons-list `split-all-lines` encoding is gone from this
path. No unused legal line-table knife left on this capture.
Not intern. Not FFI Buffer. Not empty SWAR. Not a third
truncate algorithm. This booking does not change `src/`.

## `tool_read.text_file`

```
Number of samples: 968
  1  458  47.3%  SB-IMPL::INPUT-CHAR/UTF-8/LF (48.0% total)
  2   79   8.2%  SB-IMPL:ANSI-STREAM-READ-CHAR (58.5% total)
  3   56   5.8%  SB-IMPL:ANSI-STREAM-READ-SEQUENCE (74.5% total)
  4   54   5.6%  VECTOR-HAIRY-DATA-VECTOR-SET/CHECK-BOUNDS
  5   52   5.4%  foreign function pthread_sigmask
  6   49   5.1%  CADR-AGENT:TRUNCATE-HARNESS-HEAD (8.3% total)
  7   34   3.5%  (SB-VM::OPTIMIZED-DATA-VECTOR-SET CHARACTER)
  8   19   2.0%  CADR-CLI::SPLIT-LINE-STARTS (2.1% total)
  9   16   1.7%  foreign function read
 10   13   1.3%  RETURN-MULTIPLE
```
