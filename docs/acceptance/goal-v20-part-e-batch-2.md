# Goal 20 Part E — batch 2: ten example surfaces

Date: 2026-08-14. Status: all ten surfaces captured and adjudicated. User A/B still required for Goal 20 closeout.

Part D and batch 1 were not reopened except: tic-tac-toe `:session-start` / `:session-tree` already return NIL (required once the driver fires session-start on UI attach). Official core gate after that NIL fix plus the ttt-played / process-exit 1.5k footer pair is `{SCRATCH}/official-core-gate-4.log` `GATE_EXIT:0`.

## Surfaces

| Entry | Observable surface | Scenario | waitFor |
|---|---|---|---|
| send-user-message.lisp | `/ask` usage then faux turn | `example-send-user-message` | `Usage: /ask <message>` |
| trigger-compact.lisp | `/trigger-compact` | `example-trigger-compact` | `Compaction` (pi keeps started; cadr finishes sync) |
| reload-runtime.lisp | `reload_runtime` tool | `example-reload-runtime` | `Queued /reload-runtime as a follow-up command.` |
| hidden-thinking-label.lisp | `/thinking-label Test` | `example-thinking-label` | `Hidden thinking label set to: Test` |
| message-renderer.lisp | `/status ready` | `example-message-renderer` | `[INFO]` (SGR wraps the prefix, so not `[INFO] ready`) |
| entry-renderer.lisp | `/status-card detail-one` | `example-entry-renderer` | `detail-one` |
| dynamic-tools.lisp | session_start + `/add-echo-tool` | `example-dynamic-tools` | `Registered dynamic tool: echo_session` |
| tools.lisp | `/tools` selector | `example-tools` | `Tool Configuration` |
| todo.lisp | `/todos` empty then faux add | `example-todo` | `No todos yet. Ask the agent to add some!` |
| qna.lisp | `/qna` with no assistant | `example-qna` | `No assistant messages found` |

## Contracts taken from baseline TS, not from the previous Lisp stub

- message-renderer prefix is `[${level.toUpperCase()}]`, default level `info` → `[INFO]`.
- entry-renderer paints `[status] ${args}` (`detail-one` in the scenario).
- hidden-thinking-label default is `Pondering...`.
- trigger-compact command description is `Trigger compaction immediately`; `:turn-end` is a Wave-1 result hook, not a NIL-only event.

## Harness fix

`test/fixtures/render-diff/cadr-driver.lisp` now passes `:extension-host` into `run-tui`. Without it, `render-extension-custom-entry` returned NIL and `/status` / `/status-card` painted nothing. Production `commands.lisp` already passed the host.

## NIL-return lesson

`+extension-lifecycle-no-result-events+` includes `:session-start` and `:session-tree`. A restore/notify/register last form fails the official gate with `SESSION-START handlers must return NIL`. Batch 2 session-start/tree handlers end with explicit NIL. Do not apply that rule to `:turn-end`.
