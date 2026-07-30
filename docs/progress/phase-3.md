# Phase 3 progress: tools and CLI

> Superseded policy note (2026-07-30): the v1 confirmation mechanism described
> below was removed after Phase 7. Current behavior matches original pi:
> validated tools execute directly and optional approval is an extension hook.

## Completed

- UTF-8 `read`, `write`, and atomic multi-replacement `edit` tools with bounded
  output and explicit edge-case errors.
- `bash` with merged live stdout/stderr, exit status, bounded tail output,
  retained full logs only on truncation, timeout, and whole-process-group
  TERM/KILL cleanup.
- Recursive stable `glob` and `grep`, including limits, context, long-line
  bounds, heavy-directory exclusion, nested parseable `.gitignore` rules, and
  negation.
- The phase originally shipped side-effect confirmation; the superseding
  post-Phase-7 alignment removed it from core.
- Provider/model/key resolution, system prompt selection, multi-turn REPL, and
  exact text-delta terminal streaming.
- Faux-provider REPL E2E through the real agent loop and real read/edit/bash
  executors.

## Verification

```bash
/root/.local/bin/sbcl --noinform --non-interactive \
  --load /root/quicklisp/setup.lisp \
  --eval '(asdf:load-asd (truename "pi-ai.asd"))' \
  --eval '(asdf:load-asd (truename "pi-agent.asd"))' \
  --eval '(asdf:load-asd (truename "pi-cli.asd"))' \
  --eval '(asdf:test-system "pi-cli" :force t)'
```

Result: 55 checks, 55 passed.

## Intentional differences

- The first-version REPL is line-oriented and does not provide the upstream
  full-screen TUI, editor keybindings, extensions, or package system.
- `.gitignore` support covers ordinary glob rules, anchoring, directory rules,
  comments, escaped leading markers, nested files, and negation. Git's obscure
  trailing-space escape rules are not emulated.
- `bash` process-group management targets Linux, matching the required build
  platform.

## Handoff

Phase 4 completed JSONL sessions and `--continue`, bounded provider retries,
feature-aware native-image construction, README, and final acceptance evidence.
