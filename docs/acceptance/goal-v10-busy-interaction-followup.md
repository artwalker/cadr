# Goal 10 busy-interaction follow-up

Date: 2026-08-01. Baseline: `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.
This is a new task after `c0dc46a3c` and `dbff2f9ea`; neither prior commit
implemented these runtime paths.
Initial implementation and regression commit: `c3cef6dfd`. Third A/B
correction implementation: `badc7319d`. Delivery-binary freshness gate:
`df92e9fcb`.

## Baseline contract

| Contract | Baseline evidence |
|---|---|
| Escape while the agent streams | `packages/coding-agent/src/modes/interactive/interactive-mode.ts:2601-2605,4030-4048`: restore both live queues to the editor, abort the agent, and emit no `Abort requested` notice or escalation copy. |
| Enter while streaming | `interactive-mode.ts:2856-2864`: submit with `streamingBehavior: "steer"`, clear the editor, then refresh pending messages. |
| Alt+Enter while streaming | `interactive-mode.ts:3784-3797`: submit with `streamingBehavior: "followUp"`; when idle it is ordinary Enter. |
| Pending UI | `interactive-mode.ts:4011-4027`: one spacer, exact `Steering:`/`Follow-up:` rows, then `↳ <dequeue key> to edit all queued messages`. |
| Bash cancellation | `packages/coding-agent/src/core/tools/bash.ts:84-145,424-444`: the shared abort signal kills the detached process tree and the model-visible error is exactly `Command aborted` (preceded by captured command output only when present). |
| Parallel tools | `packages/agent/src/agent-loop.ts:411-425,489-530`: the same abort signal reaches every prepared parallel executor. |
| Provider cancellation | `packages/agent/src/agent.ts:308-313` aborts the active controller; `packages/ai/src/api/openai-codex-responses.ts:395-410,763-817` passes that signal to `fetch`, cancels the reader, and checks it around every blocking read. |
| Aborted-message copy | `packages/coding-agent/src/modes/interactive/components/assistant-message.ts:190-196` renders `Operation aborted` through `Text(..., outputPad, 0)`; `packages/tui/src/components/text.ts:63-76` makes `outputPad=1` one leading cell. |
| Configurable queue keys | `packages/coding-agent/src/core/keybindings.ts:103-110` defaults follow-up/dequeue to `alt+enter`/`alt+up`; `interactive-mode.ts:2644-2645,3800-3808,4011-4048` binds, displays, and restores both queues. |

Steering is drained at the next model boundary; follow-up waits until the agent
would otherwise stop. The existing `:all` versus `:one-at-a-time` settings
change only how many FIFO messages each drain consumes
(`src/cadr-agent/runtime.lisp:183-219`). Existing mode tests remain
`STEERING-QUEUES-DRAIN-FIFO-AT-TURN-BOUNDARIES` and
`FOLLOW-UP-QUEUES-DRAIN-ONLY-WHEN-THE-AGENT-WOULD-STOP`.

## Root causes and fixes

| Item | Root cause | Production source | Regression |
|---|---|---|---|
| P0-1 single bash | The local child wait loop polled only its deadline; neither the agent's abort state nor the TUI's external abort flag reached it. | `src/cadr-agent/tool.lisp:146-150`, `src/cadr-agent/loop.lisp:439-448`, `src/cadr-cli/tools/bash.lisp:141-149,211-268`, `src/cadr-cli/main.lisp:3077-3086,3856-3859` | `GOAL10-BUSY-BASH-ABORT-KILLS-GROUP-REPORTS-ERROR-AND-SETTLES-AGENT` (`test/cadr-cli/bash-test.lisp:148-260`): FIFO handshake proves the real child is running, abort kills its process group, emits one error result with exact `Command aborted`, and settles the agent. `GOAL10-BUSY-TUI-ESCAPE-ABORTS-ACTIVE-TOOL-AND-RETURNS-IDLE` (`test/cadr-cli/goal9-a2-interactive-test.lisp:457-570`) adds raw Escape→TUI→agent→active executor coverage with a semaphore handshake. |
| P0-1 parallel tools | Worker threads did not inherit an agent-owned cancellation predicate. | `src/cadr-agent/loop.lisp:439-448` binds the owning agent predicate inside every worker's execution scope. | `GOAL10-BUSY-PARALLEL-TOOL-ABORT-REACHES-ALL-RUNNING-EXECUTORS` (`test/cadr-agent/tool-loop-test.lisp:232-315`): two semaphore-synchronized parallel executors both observe abort, both return error results, and the agent becomes idle. |
| P0-2 busy input | Core steering/follow-up queues and modes already existed, but the TUI never consumed `:queue-update`, had no pending-message surface, and exposed neither follow-up nor dequeue actions. | `src/cadr-cli/main.lisp:3773-3803`; `src/cadr-cli/tui.lisp:1376-1383,2159-2219,4234-4278`; `src/cadr-tui/keybindings.lisp:7-8`; `src/cadr-tui/input.lisp:98-99` | `GOAL10-BUSY-TUI-ROUTES-STEERING-FOLLOW-UP-AND-SHOWS-PENDING-COPY`, `GOAL10-BUSY-TUI-ENTER-AND-ALT-ENTER-USE-DISTINCT-QUEUES`, and `GOAL10-BUSY-TUI-STEERING-IS-DELIVERED-AFTER-THE-ACTIVE-TURN` (`test/cadr-cli/goal9-a2-interactive-test.lisp:178-421`). |
| P1-3 repeated Escape | The busy branch unconditionally called the handler and appended `Abort requested` on every keypress. Baseline has no escalation notice. | `src/cadr-cli/tui.lisp:3880-3882,3935,4545-4549`: one abort per active worker, silent queue restoration, latch reset only at worker boundaries. | `GOAL10-BUSY-TUI-REPEATED-ESCAPE-DOES-NOT-SPAM-ABORT-NOTICES` (`test/cadr-cli/goal9-a2-interactive-test.lisp:424-455`). |

## Third A/B correction

The root `./cadr` used for the third A/B predated the first busy-interaction
commit: its recorded mtime was 18:45, while `c3cef6dfd` was committed at 19:39.
That stale image explains both the missing pending rows and the obsolete
`session> Abort requested` row even though neither behavior remained in source.
The prior delivery report incorrectly treated the 20:33 root image as current,
but `badc7319d` was committed at 20:34. The image was therefore stale at handoff
despite the successful isolated build. The delivery-time evidence below
supersedes that claim.

The audit nevertheless found two real gaps: the legacy terminal encoding for
the default `alt+up` binding was not decoded as dequeue, and a silent native
HTTP/SSE read had no active cancellation path.

| Item | Disposition | Production source | Regression test |
|---|---|---|---|
| P0-1 pending display and dequeue | Existing pending rows retain the baseline spacer, steering-before-follow-up order, configured-key hint, and restore order. Generic two-byte Alt decoding now routes legacy `ESC p` to the configured action, so dequeue is usable outside Kitty terminals. | `src/cadr-cli/tui.lisp:2159-2219,4259-4278`; `src/cadr-tui/keys.lisp:104`; `src/cadr-tui/input.lisp:274-299` | `GOAL10-BUSY-TUI-ROUTES-STEERING-FOLLOW-UP-AND-SHOWS-PENDING-COPY`; `GOAL10-BUSY-TUI-DEQUEUE-RESTORES-BOTH-QUEUES-TO-THE-EDITOR`; `GOAL10-PENDING-HINT-USES-THE-CONFIGURED-DEQUEUE-KEY`; `INPUT-DECODER-PRESERVES-CONFIGURABLE-ALT-KEY-ACTIONS` |
| P0-2 `Abort requested` | No product change was needed beyond rebuilding the stale root image. Busy Escape remains latched and silent; only the assistant's aborted terminal state renders feedback. | `src/cadr-cli/tui.lisp:4545-4549`; `src/cadr-cli/tui.lisp:1735` | `GOAL10-BUSY-TUI-REPEATED-ESCAPE-DOES-NOT-SPAM-ABORT-NOTICES`; `GOAL10-OPERATION-ABORTED-MATCHES-BASELINE-TEXT-PADDING` |
| P1-3 leading space | The report is not a baseline defect. At `Output padding=1`, fixed-reference pi deliberately prefixes one cell through `Text(..., outputPad, 0)`. Removing it would create a new parity regression, so the exact one-cell contract is frozen. | `src/cadr-cli/tui.lisp:1735` | `GOAL10-OPERATION-ABORTED-MATCHES-BASELINE-TEXT-PADDING` asserts one leading cell, then `Operation aborted`, and rejects both `Abort requested` and `session>`. |
| P1-4 provider abort latency | `abort-p` now reaches JSON, SSE, AWS-event-stream, images, and provider dispatch. A 5 ms watcher actively shuts down the native socket during connect, headers, or a silent body read; SSE read timeout remains disabled as required for long thinking. | `src/cadr-ai/http.lisp:23-69,397-435,532-575,674-737,907-953`; `src/cadr-ai/provider.lisp:524,572`; `src/cadr-ai/images.lisp:205` | `SILENT-SSE-REQUEST-ABORTS-WITHOUT-WAITING-FOR-THE-SERVER` uses a handshaken local server that sends headers and then remains silent; before the fix it exceeded 500 ms and ended as `:error`, after the fix it settles as `:aborted`. |
| P1-5 configurable keys | Capability already existed; defaults remain unchanged. README now documents global/project settings, string-or-array values, `/reload`, and a Windows Terminal `ctrl+g` follow-up override. | `src/cadr-cli/settings.lisp:562-600`; `src/cadr-cli/main.lisp:2750-2754,3197-3201`; `src/cadr-tui/keybindings.lisp:7-8,107-116`; `README.md:132-151` | `GOAL10-PENDING-HINT-USES-THE-CONFIGURED-DEQUEUE-KEY` proves the live hint uses the resolved binding; existing keybinding tests cover settings parsing and action override scope. |

### Red-to-green and latency evidence

- `INPUT-DECODER-PRESERVES-CONFIGURABLE-ALT-KEY-ACTIONS` first produced
  `(:INTERRUPT :TEXT)` for `ESC p`; it now produces exactly `(:DEQUEUE)`.
- The silent-SSE regression first remained blocked beyond 500 ms and produced
  stop reason `:ERROR`; it now completes as `:ABORTED` without server release.
- Thirty handshaken local runs measured fixed-reference pi at median 0.358 ms,
  p95 0.670 ms, max 4.186 ms, and Cadr at median 0 ms, p95 0 ms, max 4 ms
  (SBCL's clock has 4 ms granularity). Both settle within one terminal frame;
  the old Cadr path did not settle within 500 ms.

### Why the previous 7306 checks missed these paths

The isolated build gate does not refresh the ignored root `./cadr`, so it could
not detect that the binary selected for manual A/B predated the source fix.
The queue tests invoked configured actions or asserted substrings; none drove
the default `alt+up` legacy bytes through the production decoder or locked all
pending rows exactly. Provider tests aborted between delivered deltas; none
held a socket open after response headers and aborted during a blocking silent
read. The new gates cover those precise lifecycle boundaries rather than
another layer of static assertions.

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
checks: 7334
pass:   7334
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
deterministic stages: 11/11 PASS
terminal lifecycle PTY: 6/6 PASS
live stages: 2/2 PASS
live FiveAM items: 7 PASS, 1 SKIP (ANTHROPIC_API_KEY is not set), 0 FAIL
live FiveAM checks: 31 PASS, 1 SKIP, 0 FAIL
```

The earlier statement that the 20:33 root image represented `badc7319d` was
false: the commit followed the image by 77 seconds. The permanent correction is
`scripts/check-root-binary.sh`, the first local `verify.sh` stage, and the
mandatory `docs/delivery-checklist.md` procedure. The deterministic regression
`DELIVERY-BINARY-FRESHNESS-CHECK-REJECTS-MISSING-STALE-AND-DIRTY-IMAGES`
first failed because the checker did not exist, then passed all 11 assertions
for missing, post-build source commit, fresh, and uncommitted-newer-source
states.

Final user-facing image, rebuilt after `df92e9fcb`:

```text
binary build time: 2026-08-01 21:19:47.067039517 +0800
latest src commit: badc7319daba122a345aead8c71af4e3a964a698 2026-08-01T20:34:30+08:00
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
root cadr binary is fresh
```
