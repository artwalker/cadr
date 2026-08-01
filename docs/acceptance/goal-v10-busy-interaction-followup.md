# Goal 10 busy-interaction follow-up

Date: 2026-08-01. Baseline: `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.
This is a new task after `c0dc46a3c` and `dbff2f9ea`; neither prior commit
implemented these runtime paths.
Implementation and regression commit: `c3cef6dfd`.

## Baseline contract

| Contract | Baseline evidence |
|---|---|
| Escape while the agent streams | `packages/coding-agent/src/modes/interactive/interactive-mode.ts:2601-2605,4030-4048`: restore both live queues to the editor, abort the agent, and emit no `Abort requested` notice or escalation copy. |
| Enter while streaming | `interactive-mode.ts:2856-2864`: submit with `streamingBehavior: "steer"`, clear the editor, then refresh pending messages. |
| Alt+Enter while streaming | `interactive-mode.ts:3784-3797`: submit with `streamingBehavior: "followUp"`; when idle it is ordinary Enter. |
| Pending UI | `interactive-mode.ts:4011-4027`: one spacer, exact `Steering:`/`Follow-up:` rows, then `↳ <dequeue key> to edit all queued messages`. |
| Bash cancellation | `packages/coding-agent/src/core/tools/bash.ts:84-145,424-444`: the shared abort signal kills the detached process tree and the model-visible error is exactly `Command aborted` (preceded by captured command output only when present). |
| Parallel tools | `packages/agent/src/agent-loop.ts:411-425,489-530`: the same abort signal reaches every prepared parallel executor. |

Steering is drained at the next model boundary; follow-up waits until the agent
would otherwise stop. The existing `:all` versus `:one-at-a-time` settings
change only how many FIFO messages each drain consumes
(`src/cadr-agent/runtime.lisp:183-219`). Existing mode tests remain
`STEERING-QUEUES-DRAIN-FIFO-AT-TURN-BOUNDARIES` and
`FOLLOW-UP-QUEUES-DRAIN-ONLY-WHEN-THE-AGENT-WOULD-STOP`.

## Root causes and fixes

| Item | Root cause | Production source | Regression |
|---|---|---|---|
| P0-1 single bash | The local child wait loop polled only its deadline; neither the agent's abort state nor the TUI's external abort flag reached it. | `src/cadr-agent/tool.lisp:146-150`, `src/cadr-agent/loop.lisp:439-448`, `src/cadr-cli/tools/bash.lisp:141-149,211-268`, `src/cadr-cli/main.lisp:3077-3086,3856-3859` | `GOAL10-BUSY-BASH-ABORT-KILLS-GROUP-REPORTS-ERROR-AND-SETTLES-AGENT` (`test/cadr-cli/bash-test.lisp:148-260`): FIFO handshake proves the real child is running, abort kills its process group, emits one error result with exact `Command aborted`, and settles the agent. `GOAL10-BUSY-TUI-ESCAPE-ABORTS-ACTIVE-TOOL-AND-RETURNS-IDLE` (`test/cadr-cli/goal9-a2-interactive-test.lisp:355-468`) adds raw Escape→TUI→agent→active executor coverage with a semaphore handshake. |
| P0-1 parallel tools | Worker threads did not inherit an agent-owned cancellation predicate. | `src/cadr-agent/loop.lisp:439-448` binds the owning agent predicate inside every worker's execution scope. | `GOAL10-BUSY-PARALLEL-TOOL-ABORT-REACHES-ALL-RUNNING-EXECUTORS` (`test/cadr-agent/tool-loop-test.lisp:232-315`): two semaphore-synchronized parallel executors both observe abort, both return error results, and the agent becomes idle. |
| P0-2 busy input | Core steering/follow-up queues and modes already existed, but the TUI never consumed `:queue-update`, had no pending-message surface, and exposed neither follow-up nor dequeue actions. | `src/cadr-cli/main.lisp:3773-3803`; `src/cadr-cli/tui.lisp:1376-1383,2151-2195,4221-4267,4576-4580`; `src/cadr-tui/keybindings.lisp:7-8`; `src/cadr-tui/input.lisp:98-99` | `GOAL10-BUSY-TUI-ROUTES-STEERING-FOLLOW-UP-AND-SHOWS-PENDING-COPY`, `GOAL10-BUSY-TUI-ENTER-AND-ALT-ENTER-USE-DISTINCT-QUEUES`, and `GOAL10-BUSY-TUI-STEERING-IS-DELIVERED-AFTER-THE-ACTIVE-TURN` (`test/cadr-cli/goal9-a2-interactive-test.lisp:178-320`). |
| P1-3 repeated Escape | The busy branch unconditionally called the handler and appended `Abort requested` on every keypress. Baseline has no escalation notice. | `src/cadr-cli/tui.lisp:3858-3862,3912-3915,4535-4546`: one abort per active worker, silent queue restoration, latch reset only at worker boundaries. | `GOAL10-BUSY-TUI-REPEATED-ESCAPE-DOES-NOT-SPAM-ABORT-NOTICES` (`test/cadr-cli/goal9-a2-interactive-test.lisp:322-353`). |

## Red-to-green evidence

- Parallel cancellation first failed with `EXECUTORS-FINISHED = 0` instead of
  `2`; both workers had no cancellation source.
- Pending-copy coverage first failed all three exact-copy assertions; no
  `Steering:`, `Follow-up:`, or dequeue hint existed.
- Loading the TUI regressions first warned that
  `:FOLLOW-UP-INPUT-FUNCTION` was unknown.
- The same targeted tests pass after the implementation; no timing race is
  used to decide when a child or provider is active.

## Why 7273 checks missed it

The old gates proved the pieces separately: static application key mappings,
queue drain rules, an Escape callback, idle/base-screen SHA snapshots, and bash
timeout cleanup. None coupled raw busy-state input to an actually blocked agent
and then to a real child process. They therefore could not prove that abort
crossed the TUI→agent→tool-worker→process-group boundary, that queue events were
rendered, or that a queued message was delivered after the active turn. The B2
matrix in `docs/visual-parity.md` now makes that lifecycle coupling mandatory.

## Mechanical verification

Old behavior scan:

```text
$ rg -n 'Abort requested' src
(no matches; exit 1)
```

The positive-path scan finds the cancellation predicate in
`src/cadr-agent/tool.lisp:148`, the bash abort checks/copy in
`src/cadr-cli/tools/bash.lisp:145,149,261`, the real TUI abort call in
`src/cadr-cli/main.lisp:3859`, and the follow-up/dequeue actions in
`src/cadr-tui/{keybindings,input}.lisp:7-8,98-99`.

Deterministic suite, final run after all changes:

```text
$ ./scripts/test-cl.sh
checks: 7306
pass:   7306
skip:   0
fail:   0
```

The overlay and base-screen full SHA tests are included and unchanged; both
`GOAL9-B3-EVERY-OVERLAY-HAS-AN-EXACT-FULL-VIRTUAL-TERMINAL-SNAPSHOT` and
`GOAL9-B3-EVERY-BASE-SCREEN-STATE-HAS-AN-EXACT-FULL-VIRTUAL-TERMINAL-SNAPSHOT`
passed.

Full verification:

```text
$ ./scripts/verify.sh
exit: 0
deterministic stages: 10/10 PASS
terminal lifecycle PTY: 6/6 PASS
live stages: 2/2 PASS
live FiveAM items: 7 PASS, 1 SKIP (ANTHROPIC_API_KEY is not set), 0 FAIL
live FiveAM checks: 31 PASS, 1 SKIP, 0 FAIL
```
