# Goal 20 Part P — `text_truncation` sb-sprof (line table `c074a85ec`)

Diagnostic, not a gate. Same 4000-line pairing fixture.
Friend-MachineD remesure `364a714d3`: head 1.17× (592 / 506 µs),
tail 1.47× (790 / 537 µs).

This profile is of the **line-start table** tail, not the
pre-`c074a85ec` scan. Do not treat as G.17 `met` or Part P
`[done]`.

- git: `c074a85ec` (product; booked from HEAD `d24c052e4`)
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- seconds per path: 4
- sample-interval: 0.001s

## Verdict

Tail leftover encoding is `PREPARE-VECTOR-PUSH-EXTEND` 1.8%
self / 7.9% total (`make-array` 64 + `vector-push-extend` per
line) plus `%DATA-VECTOR-AND-INDEX` 1.3%. Self is still
`TRUNCATE-HARNESS-TAIL` 86.2% (the one fill walk). Head leftover
is `TRUNCATE-HARNESS-HEAD` 91.8% self + pthread.

Named next encoding (same algorithm): pre-size the fixnum
vectors so 4000 lines do not realloc from 64. Not a third
algorithm. Not intern. Not FFI. This booking does not change
`src/`.

## `text_truncation.truncate_head`

```
Number of samples: 993
  1  912  91.8%  CADR-AGENT:TRUNCATE-HARNESS-HEAD
  2   23   2.3%  foreign function pthread_sigmask
```

## `text_truncation.truncate_tail`

```
Number of samples: 987
  1  851  86.2%  CADR-AGENT:TRUNCATE-HARNESS-TAIL
  2   33   3.3%  foreign function pthread_sigmask
  3   18   1.8%  SB-VM::PREPARE-VECTOR-PUSH-EXTEND (7.9% total)
  4   13   1.3%  %DATA-VECTOR-AND-INDEX
```
