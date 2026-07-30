# Phase 7 progress

Phase 7 implements the frozen Common Lisp extension API and the post-phase
original-pi execution-policy alignment.

## Delivered

- Stable `define-tool`, `define-command`, `define-event-hook`, and
  `define-prompt-template` APIs with opaque handler context/event values.
- Deterministic CLI/project/global discovery, isolated generation packages,
  immutable registry snapshots, atomic reload, and per-extension
  last-known-good fallback.
- Tool, command, prompt template/skill, four lifecycle hooks, `/reload`, and
  staged `/install <git-url>`.
- Schema revalidation after hook rewrites, transactional hook composition,
  condition containment, and secret-redacted diagnostics.
- Faux and live DeepSeek self-extension loops.
- Separate post-Phase-7 removal of the v1 confirmation callback and `--yolo`;
  default execution now matches original pi.

## Verification

```text
./scripts/test-cl.sh
  pi-ai:    223/223
  pi-agent: 143/143
  pi-cli:   136/136 after the independent policy cleanup

./build.sh
  passed all suites and emitted an uncompressed image after feature detection

./scripts/acceptance-smoke.sh
  executable help, --continue, and exact --resume passed

./scripts/live-extension-smoke.sh
  DeepSeek write/reload/invoke loop passed
```

The policy cleanup was verified separately and was not interleaved with the
Phase 7 implementation.

## Residual risk

Extensions execute arbitrary in-process Lisp code. Package isolation and
condition containment improve reliability, not security; strong isolation is
the user's container/VM/OS-user boundary.
