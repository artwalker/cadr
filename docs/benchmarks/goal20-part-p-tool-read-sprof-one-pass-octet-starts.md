# Goal 20 Part P — `tool_read.text_file` sb-sprof (one-pass octet starts)

Diagnostic, not a gate. Same 4000-line pairing fixture.
Previous leftover at `ad1e91711` was `SPLIT-OCTET-LINE-STARTS`
27.4% self (two `0x0A` walks). Do not treat as G.17 `met`.

- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds: 4
- sample-interval: 0.001s
- samples: 952

## Verdict

Second `0x0A` walk is gone. Leftover is still Lisp
`SPLIT-OCTET-LINE-STARTS` 25.2% self (one pass + exact copy)
and window `COPY-UTF8-OCTETS` 8.5%. Not FFI. Not mmap.
Not intern. Not empty SWAR.

## `tool_read.text_file`

```
Number of samples: 952
  1  240  25.2%  CADR-CLI::SPLIT-OCTET-LINE-STARTS (26.3% total)
  2  161  16.9%  foreign function pthread_sigmask
  3   91   9.6%  foreign function read
  4   81   8.5%  CADR-AI::COPY-UTF8-OCTETS (15.0% total)
  5   65   6.8%  CADR-AGENT:TRUNCATE-HARNESS-HEAD (9.5% total)
  6   41   4.3%  CADR-AI::OCTET-U32-LE
```
