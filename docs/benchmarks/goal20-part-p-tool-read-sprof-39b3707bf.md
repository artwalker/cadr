# Goal 20 Part P — `tool_read.text_file` sb-sprof (octet decode `39b3707bf`)

Diagnostic, not a gate. Same 4000-line pairing fixture and
production `read-tool-file` as `scripts/goal20-paired-paths.lisp`.
Friend-MachineD remesure `e055ea8df`: **2.39×** (10299 / 4316 µs),
ceiling 8.0.

This profile is after octet `read-sequence` + `utf8-string`.
Do not treat as G.17 `met` or Part P `[done]`.

- git: `39b3707bf` (product; booked from HEAD `e055ea8df`)
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds: 4
- sample-interval: 0.001s
- samples: 965

## Verdict

`INPUT-CHAR/UTF-8/LF` is gone. Leftover is still Lisp:

1. `UTF8->STRING-AREF` 17.3% self / 65.9% total and
   `BYTES-PER-UTF8-CHARACTER-AREF` 16.2% — SBCL
   `octets-to-string` (the pi `toString("utf-8")` encoding).
   Not FFI Buffer.
2. `PREPARE-VECTOR-PUSH-EXTEND` 12.7% self / 25.6% total —
   `split-line-starts` still `vector-push-extend` into a
   hinted adjustable array. Same algorithm: exact-size the
   fixnum vector (count newlines, then fill). Not a third
   split.

Also `TRUNCATE-HARNESS-HEAD` 6.7%, `SPLIT-LINE-STARTS` 3.8%,
foreign `read` 2.5%, pthread 11.9%. Not intern. Not mmap.
Not empty SWAR. This booking does not change `src/`.

## `tool_read.text_file`

```
Number of samples: 965
  1  167  17.3%  SB-IMPL::UTF8->STRING-AREF (65.9% total)
  2  156  16.2%  SB-IMPL::BYTES-PER-UTF8-CHARACTER-AREF
  3  123  12.7%  SB-VM::PREPARE-VECTOR-PUSH-EXTEND (25.6% total)
  4  115  11.9%  foreign function pthread_sigmask
  5   67   6.9%  %DATA-VECTOR-AND-INDEX
  6   65   6.7%  CADR-AGENT:TRUNCATE-HARNESS-HEAD (7.3% total)
  7   37   3.8%  CADR-CLI::SPLIT-LINE-STARTS (4.0% total)
  8   24   2.5%  foreign function read
```
