# Goal 20 Part E — batch 1: ten example surfaces

Date: 2026-08-13. Status: implemented; user A/B still required for Goal 20 closeout.

Part D (snake / tic-tac-toe / space-invaders) was not reopened. Batch 0 inventory stays in
`docs/acceptance/goal-v20-part-e-batch-0.md`.

## Surfaces

| Entry | Observable surface | Scenario |
|---|---|---|
| hello.lisp | faux `hello` tool result `Hello, PartE!` | `example-hello` |
| notify.lisp | OSC notify on `agent_end` (title is I04) | `example-notify` |
| session-name.lisp | `/session-name Goal20` + footer `• Goal20` | `example-session-name` |
| pirate.lisp | `/pirate` → `Arrr! Pirate mode enabled!` | `example-pirate` |
| bookmark.lisp | `/bookmark first` | `example-bookmark` |
| commands.lisp | `/commands` selector + path confirm | `example-commands` |
| custom-header.lisp | mascot + `shitty coding agent v0.84.1` | `example-custom-header` |
| custom-footer.lisp | `/footer` token/model line | `example-custom-footer` |
| overlay-test.lisp | 70-col overlay (wide-only) | `example-overlay-test` |
| event-bus.lisp | session_start + `/emit hi` | `example-event-bus` |

## Defects fixed (not dumped as intentional)

- hello: pi-driver active-tools allowlist omitted extension tools, so the faux `hello` call never ran.
- event-bus: listener used the stale session-start context; `/emit` now rebinds the live command context.
- overlay-test: stub dialog replaced; `~C` FORMAT-ERROR (`ch` was a string); action rows no longer reverse the whole box.
- custom-header: subtitle uses the BASELINE release (`0.84.1`), not asdf `0.2.0`.
- commands: harness `getCommands` no longer injects builtins or the hidden `/llama` factory.

## Gate

`REQUIRED_COVERAGE` gained the new labels. Dispositions for these checkpoints are I01+I04 with per-entry notes and exact screen SHA pairs. Official `scripts/render-diff.py gate --tier core` after this batch is recorded in `{SCRATCH}/official-core-gate-3.log`.
