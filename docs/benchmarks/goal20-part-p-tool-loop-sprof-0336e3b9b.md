# Goal 20 Part P — agent_tool_loop sb-sprof (HEAD `0336e3b9b`)

Diagnostic, not a gate. Shipped `agent-prompt` on the pairing
faux stream (one `:parallel` echo tool). No socket.

- git: `0336e3b9b`
- machine: Friend-MachineD
- lisp: SBCL 2.6.7
- sample-interval: 0.001s
- pairing: **1.54×–1.75×** vs ceiling 1.50 (variance bound).
  cadr ~265–290 µs; pi jitter 166–172 µs.

## Verdict

Named leftover is OS thread create/join for a **single**
parallel tool:

- foreign `pthread_sigmask` 53.1%
- foreign `syscall` 3.1%
- sampled thread list is hundreds of `cadr-tool-echo` threads
- `GENSYM` 5.3% total (thread names)

pi `executeToolCallsParallel` is `Promise.all` on the same
event loop. cadr `execute-agent-tool-batch` called
`sb-thread:make-thread` whenever `parallel-p` was true, even
for `runnable = 1`. Copy that pass: spawn threads only when two
or more calls actually run. Not intern. Not FFI. Not a ceiling
raise.

```
Number of samples: 320
  pthread_sigmask 53.1%
  GENSYM 5.3% total
  syscall 3.1%
  EMIT-AGENT-EVENT 4.4% total
```
