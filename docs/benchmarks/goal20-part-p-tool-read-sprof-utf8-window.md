# Goal 20 Part P — `tool_read.text_file` sb-sprof (ub8 window decode)

Diagnostic, not a gate. Same 4000-line pairing fixture and
production `read-tool-file`. Previous leftover at ASCII-run
was `COPY-UTF8-OCTETS` 41.8% total on the whole file. Do not
treat as G.17 `met` or Part P `[done]`.

- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds: 4
- sample-interval: 0.001s
- samples: 945
- this-host read-tool-file: ~4695→800 µs

## Verdict

Whole-file `COPY-UTF8-OCTETS` is gone. Leftover is Lisp
`SPLIT-OCTET-LINE-STARTS` 27.4% self (ub8 `0x0A` scan) and
`COPY-UTF8-OCTETS` 11.7% on the truncated window.
`TRUNCATE-HARNESS-HEAD` 8.1%. foreign `read` 7.6%.

Not FFI. Not mmap. Not intern. Not empty SWAR.

## `tool_read.text_file`

```
Number of samples: 945
  1  259  27.4%  CADR-CLI::SPLIT-OCTET-LINE-STARTS (27.7% total)
  2  150  15.9%  foreign function pthread_sigmask
  3  111  11.7%  CADR-AI::COPY-UTF8-OCTETS (17.5% total)
  4   77   8.1%  CADR-AGENT:TRUNCATE-HARNESS-HEAD (11.0% total)
  5   72   7.6%  foreign function read
  6   27   2.9%  CADR-AI::OCTET-U32-LE
```
