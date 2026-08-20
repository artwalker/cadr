# Bug — agent is working but TUI sometimes omits "Working..."

**Status**: fixed. Not G.17.

## Symptom

While cadr is actually busy (request in flight / retrying /
streaming), the interactive UI sometimes **does not show** the
`Working...` loader (spinner + message). User sees a quiet
editor/footer as if idle, even though work is ongoing.

Related: OpenCode Go usage-limit 429 can leave the UI on a long
silent wait; that path is booked separately in
`opencode-go-usage-limit-429-retry.md`. This note covers **missing
Working indicator in general**, including non-429 cases.

## Likely product surfaces (executor must verify)

- `src/cadr-cli/interactive/controller.lisp` `render-now`: paints
  loader only when `(and agent-working-p (not settle-window-p))`.
  Settle window intentionally hides the loader while still busy —
  confirm it is not left stuck true during live work.
- `src/cadr-cli/interactive/tool-rendering.lisp`:
  `:message-end` / `:tool-execution-end` / `:agent-end` /
  `:agent-settled` toggling `settle-window-p` and
  `agent-working-p`.
- `src/cadr-cli/interactive/frame.lisp`: default `"Working..."` /
  `working-message`.
- `src/cadr-cli/interactive/state.lisp`: `agent-working-p`,
  `settle-window-p`, `working-message`.
- pi: `packages/coding-agent/src/modes/interactive/interactive-mode.ts`
  `defaultWorkingMessage = "Working..."`.

## Cause and fix

`settle-window-p` is the cadr stand-in for pi's unobservable
`message_end`→`agent_end` persist gap. It was left set through the
**next** assistant `message-start` and `:text-delta` after a completed
tool so render-diff would not paint Took+loader. That hid `Working...`
for the entire follow-up stream while `agent-working-p` stayed true.

Fix: keep the persist-only hide (block-end, assistant `message-end`,
tool-end with no running sibling). Lift on live work — user/assistant
`message-start`, text/thinking/tool-call start+delta, tool start,
retry, compaction. Tests:
`goal18-message-end-render-suppression-covers-the-settle-window` and
`working-indicator-paints-during-live-follow-up-and-thinking`.

## Required delivery

1. Reproduce: submit a prompt that stays busy ≥2s (or force a
   retrying 429 before the quota fix) and capture whether the
   loader row is absent while `agent-working-p` should be true.
2. Fix so **any** live agent work paints Working/spinner whenever
   pi would (same busy window; settle-only hide only in the
   baseline settle gap after a completed assistant turn).
3. Regression test if feasible (TUI/state unit or suite harness
   with faux provider): busy ⇒ loader present; settle window ⇒
   loader omitted only when baseline omits it.
4. `scripts/test-cl.sh` green. Not G.17.

## Order

Board: after OpenCode Go 429 P0 (or in parallel if that is done).
Do not park behind load knives.

## Pointers

- Board `[ready · P0]` Working indicator
- Sibling: `docs/bugs/opencode-go-usage-limit-429-retry.md`
