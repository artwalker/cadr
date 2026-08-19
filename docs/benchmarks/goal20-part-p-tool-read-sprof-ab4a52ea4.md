# Goal 20 Part P — `tool_read.text_file` sb-sprof (exact-size `ab4a52ea4`)

Diagnostic, not a gate. Same 4000-line pairing fixture and
production `read-tool-file`. Friend-MachineD remesure
`ba6296d54`: **2.42×** (11131 / 4594 µs), ceiling 8.0.

This profile is after exact-size `split-line-starts`. Do not
treat as G.17 `met` or Part P `[done]`.

- git: `ab4a52ea4` (product; booked from HEAD `ba6296d54`)
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds: 4
- sample-interval: 0.001s
- samples: 926

## Verdict

`vector-push-extend` on the line table is gone from cadr's
fill. Remaining `PREPARE-VECTOR-PUSH-EXTEND` 10.8% sits
under `UTF8->STRING-AREF` 58.3% total — SBCL
`octets-to-string` growing the decoded string. That is the
pi `toString("utf-8")` encoding. Not FFI Buffer.

Also `BYTES-PER-UTF8-CHARACTER-AREF` 14.5%,
`TRUNCATE-HARNESS-HEAD` 7.5%, `SPLIT-LINE-STARTS` 5.4%,
foreign `read` 3.7%, pthread 9.5%.

No unused legal line-table knife left on this capture. Not
intern. Not mmap. Not empty SWAR. This booking does not
change `src/`.

## `tool_read.text_file`

```
Number of samples: 926
  1  134  14.5%  SB-IMPL::BYTES-PER-UTF8-CHARACTER-AREF
  2  132  14.3%  SB-IMPL::UTF8->STRING-AREF (58.3% total)
  3  100  10.8%  SB-VM::PREPARE-VECTOR-PUSH-EXTEND (22.2% total)
  4   88   9.5%  foreign function pthread_sigmask
  5   69   7.5%  CADR-AGENT:TRUNCATE-HARNESS-HEAD (9.0% total)
  6   51   5.5%  %DATA-VECTOR-AND-INDEX
  7   50   5.4%  CADR-CLI::SPLIT-LINE-STARTS
  8   34   3.7%  foreign function read
```
