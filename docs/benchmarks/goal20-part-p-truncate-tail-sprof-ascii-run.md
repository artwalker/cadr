# Goal 20 Part P — `truncate_tail` sb-sprof (ASCII-run fill)

Diagnostic, not a gate. Same 4000-line pairing fixture.
Do not treat this file as G.17 `met` or Part P `[done]`.

- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds per path: 4
- sample-interval: 0.001s

## Verdict

Named leftover is still Lisp. `truncate-harness-tail` self
78.6% (was 88.8% with per-char `utf8-char-length`) plus
`PUSH-LINE` 3.2%. ASCII-run increment removed the per-ASCII
`utf8-char-length` from the fill. Not intern. Not FFI. Not
empty SWAR. Not another line-table swap.

## `text_truncation.truncate_tail`

```
Number of samples: 987
  1  776  78.6%  CADR-AGENT:TRUNCATE-HARNESS-TAIL
  2   82   8.3%  foreign function pthread_sigmask
  3   32   3.2%  (FLET CADR-AGENT::PUSH-LINE :IN CADR-AGENT:TRUNCATE-HARNESS-TAIL)
```

## `text_truncation.truncate_head` (unchanged this knife)

```
Number of samples: 998
  1  921  92.3%  CADR-AGENT:TRUNCATE-HARNESS-HEAD
  2   24   2.4%  foreign function pthread_sigmask
```
