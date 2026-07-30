# Phase 8 progress

Phase 8 adds the pure Common Lisp TUI while preserving the line REPL as a
frontend-only fallback.

## Delivered

- Independent `pi-tui` ASDF system with grapheme-aware CJK/emoji layout,
  multiline editor, bracketed paste, history, Markdown, collapsible tool
  blocks, status bar, and reusable select lists.
- Synchronized ANSI line-diff renderer with resize invalidation, stale-row
  clearing, and a virtual-terminal snapshot backend.
- Linux/SBCL process terminal with termios raw mode, `SIGWINCH`, alternate
  screen, bracketed paste, and cleanup covering both body failure and partial
  startup failure.
- Default TUI on interactive streams, `--no-tui` override, and automatic REPL
  fallback for pipes.
- Shared `dispatch-user-input` and the same `PI-AGENT:AGENT-EVENT` stream for
  both frontends; provider, tools, session, extension, and compaction behavior
  remain outside `pi-tui`.
- `/model` and `/sessions` selectors, streaming assistant text, live tool
  state, cumulative token/cost status, and Ctrl+O tool expansion.

## Verification

```text
pi-tui/tests
  59/59

pi-cli/tests
  161/161

./build.sh
  all four suites passed; native image built with compression fallback

./scripts/acceptance-smoke.sh
  non-TTY REPL fallback, --continue, and exact --resume passed

./scripts/live-tui-smoke.sh
  DeepSeek two-turn write/edit/read task, resize, CJK/emoji rendering,
  and exact termios restoration passed
```

Manual selector and tool-block checks used `/model`, `/sessions`, and Ctrl+O
inside an actual tmux terminal.

## Residual risk

Unicode width follows the same conservative terminal convention as original
pi: emoji and East Asian wide/fullwidth graphemes occupy two cells. A terminal
with a nonstandard font width policy can still disagree visually.
