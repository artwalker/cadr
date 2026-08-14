# Goal 20 Part D — three-game example differentials

Date: 2026-08-13. Status: implemented; user A/B still required for Goal 20 closeout.

**A/B precondition (added 2026-08-14 after a three-day divergence):** before
any manual acceptance run, sync `examples/extensions/` into the runtime
extension directory and verify with
`./scripts/check-runtime-extension-drift.sh` — otherwise the terminal loads
`~/.cadr/agent/extensions/` copies the gates never saw, and the A/B judges
old code.

## What landed

Reuse of `scripts/render-diff.py` (no second oracle):

- `setup.exampleExtensions` loads `examples/extensions/<name>.lisp` on cadr and
  copies the baseline `<name>.ts` into the pi agent extensions directory.
- Harness mode (`RENDER_DIFF_READY_PATH`): `Math.random = () => 0` / cadr
  `snake-harness-random` returns 0; wall-clock ticks are off; snake steps once
  per direction key. Space Invaders does not tick.
- `example-space-invaders` is **wide-only**. Baseline pi aborts in 48 columns
  (`Rendered line 14 exceeds terminal width (63 > 48)`).

Scenarios: `example-snake`, `example-tic-tac-toe`, `example-space-invaders`.

## Gate-validity proof (before the visual fixes)

Official `capture` of the shipped scenarios, then the shipped
`tmux_screen` / `normalized_screen` pair
(`{SCRATCH}/compare-example-games.py` imports `scripts/render-diff.py`):

| Checkpoint family | Before | Meaning |
|---|---|---|
| snake-initial / moved / over | `screenEqual=false` | cadr board had no green/red SGR |
| ttt-initial / cursor / played | `screenEqual=false` | cadr had `>`/`<` ASCII, no cursor-border painter |
| invaders-left / right vs initial **on each side** | SHA-identical | left/right do not move the player (no Kitty release) |

Saved: `{SCRATCH}/part-d-before.json`.

A second bug turned up while wiring `/tic-tac-toe`:
`example-session-branch` called `session-branch`, which **returns the session
object**, then `dolist` blew up (`is not of type LIST`). Fixed to
`session-path-entries`. Locked by
`test/cadr-cli/goal20-example-games-test.lisp`.

## Fixes

- `examples/extensions/snake.lisp`: same raw SGR as `snake.ts`
  (`32m` head/body, `31m` food, `2m` dim borders, `1;33m` scores). No new
  theme tokens.
- `examples/extensions/tic-tac-toe.lisp`: ports the baseline box-drawing
  board and green/yellow cursor-border highlight (`32;1m` / `33;1m`).
- `examples/extensions/support.lisp`: harness predicate + branch walk.

After recapture (`part-d-after.json`) cadr snake screens contain
`ESC[32m` / `ESC[31m`. Invaders left/right remain SHA-identical to initial
on **each** side. Remaining pi/cadr deltas are startup chrome and I04/I01,
recorded per checkpoint in `test/fixtures/render-diff/dispositions.json`.

Official `scripts/render-diff.py gate --tier core` on this host: `captured=81/82`
then `EXIT:2` on `startup-first/wide/startup`. The cadr half of that pair
matches the book; the pi half dropped `\x1b[1m` around the product name
(251 pi-only SHA drifts, 0 cadr drifts). That is a host/book mismatch on
the frozen pi banner, not a Part D game defect. The 251 hashes were not
rewritten.

## Colouring choice

Examples follow the baseline's raw ANSI. They are not product chrome (I04).
Theme tokens would have been a second look, not alignment.
