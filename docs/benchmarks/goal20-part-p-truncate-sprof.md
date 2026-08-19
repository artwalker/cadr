# Goal 20 Part P — `text_truncation` sb-sprof

Diagnostic, not a gate. Same 4000-line pairing fixture as
`scripts/goal20-paired-paths.lisp`. Friend-MachineD n=5 remesure
(from the sqlite pair run on `8ae41c997`, truncate code unchanged
through `5810cf908`):

- `truncate_head` 4.57× (2566 / 562 µs), ceiling 20.0
- `truncate_tail` 3.09× (1783 / 578 µs), ceiling 18.0

Still above 1.0×. 0.15× sqlite does not pause this floor.

Do not treat this file as G.17 `met` or Part P `[done]`.

- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds per path: 4
- sample-interval: 0.001s

## Verdict

`truncate_head` is one character loop (78.8% self).
`truncate_tail` paid two full-content scans before the reverse
walk: `HARNESS-LINE-COUNT` 39.8% + `HARNESS-UTF8-LENGTH` 29.5%.
Named lever: one pass for both totals. Not intern. Not FFI.
Not empty SWAR.

## `text_truncation.truncate_head`

```
Number of samples: 998
  1  786  78.8%  CADR-AGENT:TRUNCATE-HARNESS-HEAD
  2   90   9.0%  GENERIC-+
  3   86   8.6%  %DATA-VECTOR-AND-INDEX/CHECK-BOUND
```

## `text_truncation.truncate_tail`

```
Number of samples: 998
  1  397  39.8%  CADR-AGENT::HARNESS-LINE-COUNT
  2  294  29.5%  CADR-AGENT::HARNESS-UTF8-LENGTH
  3  150  15.0%  %DATA-VECTOR-AND-INDEX/CHECK-BOUND
  4   73   7.3%  CADR-AGENT::HARNESS-UTF8-LENGTH-RANGE
```
