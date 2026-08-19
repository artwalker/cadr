# Goal 20 Part P — `tool_read.text_file` sb-sprof (ASCII-run `utf8-string`)

Diagnostic, not a gate. Same 4000-line pairing fixture and
production `read-tool-file`. Previous leftover at `ab4a52ea4`
was `UTF8->STRING-AREF` 58.3% total. Do not treat as G.17
`met` or Part P `[done]`.

- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds: 4
- sample-interval: 0.001s
- samples: 942
- this-host read-tool-file: ~5512→3103 µs

## Verdict

`UTF8->STRING-AREF` is gone. Leftover is Lisp
`COPY-UTF8-OCTETS` 26.2% self / 41.8% total (ASCII ub32
schar + UTF-8 scalars) and `OCTET-U32-LE` 11.0%.
`UTF8-NEXT-WIDTH` 1.5% after the ASCII-only count walk.
`TRUNCATE-HARNESS-HEAD` 13.9%. foreign `read` 6.1%.

Not FFI. Not mmap. Not intern. Not empty SWAR.

## `tool_read.text_file`

```
Number of samples: 942
  1  247  26.2%  CADR-AI::COPY-UTF8-OCTETS (41.8% total)
  2  131  13.9%  CADR-AGENT:TRUNCATE-HARNESS-HEAD (15.1% total)
  3  105  11.1%  foreign function pthread_sigmask
  4  104  11.0%  CADR-AI::OCTET-U32-LE
  5   74   7.9%  CADR-CLI::SPLIT-LINE-STARTS (8.1% total)
  6   57   6.1%  foreign function read
  7   14   1.5%  CADR-AI::UTF8-NEXT-WIDTH
```
