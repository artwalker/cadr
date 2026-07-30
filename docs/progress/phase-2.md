# Phase 2 progress: pi-agent

## Completed

- Stateful agent runtime with busy-state protection and deterministic lifecycle
  events.
- Full user → assistant → tool batch → tool results → assistant loop.
- Unique-name tool registry and tool-schema validation with pointer and reason
  in structured conditions. Phase 9 replaced the original library with the
  native validator while preserving this contract.
- Unknown tools, invalid arguments, blocked calls, executor exceptions, and
  length-truncated calls become error tool results rather than fatal exits.
- All-explicit-parallel batches run in joined worker threads. A single
  sequential tool serializes the whole batch. Completion events reflect actual
  completion order while result messages retain source order.
- Error/abort termination and a default 100-model-turn safety ceiling.

## Verification

```bash
/root/.local/bin/sbcl --noinform --non-interactive \
  --load /root/quicklisp/setup.lisp \
  --eval '(asdf:load-asd (truename "pi-ai.asd"))' \
  --eval '(asdf:load-asd (truename "pi-agent.asd"))' \
  --eval '(asdf:test-system "pi-agent" :force t)'
```

Result: 26 checks, 26 passed.

## Intentional differences

- The first-version loop omits upstream steering/follow-up queues, custom agent
  message types, and after-tool mutation hooks. Those are outside `goal.md`.
- Parallelism is opt-in per tool; this is stricter than upstream's broader
  default and prevents confirmations or file mutations from racing.

## Next

Phase 3 adds six coding tools, confirmation behavior, CLI configuration, and
the REPL executable path.
