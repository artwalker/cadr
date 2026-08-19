# Goal 20 Part P — `truncate_tail` sb-sprof (HEAD `19ca40947`)

Diagnostic, not a gate. Same 4000-line pairing fixture.
Friend-MachineD remesure `b7f1f7de0`: tail **1.30×**
(819 / 630 µs), ceiling 18.0. Head already 0.97×.

Do not treat this file as G.17 `met` or Part P `[done]`.

- git: `19ca40947` (tail code unchanged through `b7f1f7de0`)
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds per path: 4
- sample-interval: 0.001s

## Verdict

Named leftover is still Lisp. `truncate-harness-tail` pays
a full forward `HARNESS-LINE-AND-UTF8-LENGTH` (67.5%) then a
reverse line walk (`HARNESS-UTF8-LENGTH-RANGE` 13.2%,
`TWO-ARG->=` 9.8%, `SIMD-POSITION32-FROM-END-AVX2` 1.2%).
One reverse walk can fill totals and the selected tail.
Not intern. Not FFI. Not empty SWAR. This booking does not
change `src/`.

## `text_truncation.truncate_tail`

```
Number of samples: 998
  1  674  67.5%  CADR-AGENT::HARNESS-LINE-AND-UTF8-LENGTH
  2  132  13.2%  CADR-AGENT::HARNESS-UTF8-LENGTH-RANGE
  3   98   9.8%  SB-KERNEL:TWO-ARG->=
  4   21   2.1%  %DATA-VECTOR-AND-INDEX/CHECK-BOUND
  5   17   1.7%  foreign function pthread_sigmask
  6   12   1.2%  SB-VM::SIMD-POSITION32-FROM-END-AVX2
```
