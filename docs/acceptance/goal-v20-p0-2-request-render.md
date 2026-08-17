# Goal 20 P0-2 / P0-3 — request-render pairing and gate-validity

Advisor count of `requestRender` / `tui-request-render` included
TypeScript type annotations (`tui: { requestRender: () => void }`).
Those are not call sites. The pairing below is every **call that
requests a frame after a state change**.

## Pairing

| Game | Baseline call | State change | Cadr |
|---|---|---|---|
| snake | `snake.ts:95` timer | tick moved the snake | `snake-component-advance` (timer) |
| snake | `snake.ts:199` restart | new board after game over | **framework** — restart is inside `component-handle-event`; `tui-dispatch-event` (`src/cadr-tui/composition/root.lisp:207-208`) always `tui-request-render`s afterwards |
| tic-tac-toe | `tic-tac-toe.ts:392` `updateState` | agent tool mutated the shared board | `tic-tac-toe-request-render` after the tool handler |
| tic-tac-toe | `tic-tac-toe.ts:412` cursor up | user cursor row-- | **framework** (handle-event) |
| tic-tac-toe | `tic-tac-toe.ts:416` cursor down | user cursor row++ | **framework** |
| tic-tac-toe | `tic-tac-toe.ts:420` cursor left | user cursor col-- | **framework** |
| tic-tac-toe | `tic-tac-toe.ts:424` cursor right | user cursor col++ | **framework** |
| space-invaders | `space-invaders.ts:149` timer | tick | `space-invaders-advance` (timer) |
| space-invaders | `space-invaders.ts:373` restart | new board after game over / victory | **framework** (handle-event) |

Not added: the five user-input calls. Cadr's overlay input path already
repaints; adding a second `tui-request-render` would only double-paint.
The P0-2 hole was the **agent / timer** path, which never goes through
`tui-dispatch-event`.

## Gate-validity proof

Temporary deletion of the three request-render calls (not committed).
`cadr-cli` FiveAM, the three behavior tests only:

```
GOAL20-TTT-AGENT-ACTION-REPAINTS-THE-LIVE-OVERLAY
  Did 6 checks. Pass: 5  Fail: 1
  agent tool action did not request a repaint

GOAL20-SNAKE-BEHAVIOR-RENDER-REFLECTS-STATE
  Did 5 checks. Pass: 4  Fail: 1
  timer tick did not request a repaint

GOAL20-INVADERS-BEHAVIOR-RENDER-REFLECTS-STATE
  Did 4 checks. Pass: 3  Fail: 1
  timer tick did not request a repaint
```

Restored; the same three tests pass (6/6, 5/5, 4/4). Scratch logs
`p02-green.log`, `p02-red.log`, `p02-ttt-red2.log`.
