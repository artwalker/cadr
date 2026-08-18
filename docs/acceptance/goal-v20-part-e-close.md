# Goal 20 Part E — leftover classification close

Adjudication: `docs/adjudications.md` 2026-08-18 Part E.
No batch 3. No new PTY scenario. This is a conclusion per
`find examples/extensions -mindepth 1 -maxdepth 1 ! -name support.lisp`
entry (79). Not a Goal 20 pass.

Statuses:

- `pty` — existing `example-*` id in `test/fixtures/render-diff/scenarios.json`
- `suite-lock` — registration/load only; the two SP-F1 suite tests
- `blocked` — the five-name set from the adjudication

Counts: 23 `pty`, 51 `suite-lock`, 5 `blocked`.

| entry | surface | status | evidence |
|---|---|---|---|
| `auto-commit-on-exit.lisp` | auto-commit-on-exit hook | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `bash-spawn-hook.lisp` | bash-spawn hook | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `bookmark.lisp` | `/bookmark` | pty | `example-bookmark` |
| `border-status-editor.lisp` | border-status editor chrome | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `built-in-tool-renderer.lisp` | built-in tool renderer | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `claude-rules.lisp` | claude-rules | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `commands.lisp` | `/commands` selector | pty | `example-commands` |
| `confirm-destructive.lisp` | destructive-tool confirm | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `custom-compaction.lisp` | custom compaction | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `custom-footer.lisp` | `/footer` token/model line | pty | `example-custom-footer` |
| `custom-header.lisp` | `/builtin-header` / header widget | pty | `example-custom-header` |
| `custom-provider-anthropic` | custom provider registration | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `custom-provider-gitlab-duo` | custom provider registration | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `dirty-repo-guard.lisp` | dirty-repo guard | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `doom-overlay` | `/doom-overlay` | blocked | needs a WAD fixture (adjudication 2026-08-18 Part E) |
| `dynamic-resources` | dynamic resources | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `dynamic-tools.lisp` | `/add-echo-tool` | pty | `example-dynamic-tools` |
| `entry-renderer.lisp` | `/status-card` | pty | `example-entry-renderer` |
| `event-bus.lisp` | `/emit` | pty | `example-event-bus` |
| `file-trigger.lisp` | fs watch trigger | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `game-support.lisp` | shared game support (non-entry helper) | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `git-checkpoint.lisp` | git checkpoint hook | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `git-merge-and-resolve.lisp` | git merge/resolve hook | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `github-issue-autocomplete.lisp` | GitHub issue autocomplete (network) | blocked | real network (adjudication 2026-08-18 Part E) |
| `gondolin` | `/gondolin` | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `handoff.lisp` | handoff | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `hello.lisp` | faux `hello` tool result | pty | `example-hello` |
| `hidden-thinking-label.lisp` | `/thinking-label` | pty | `example-thinking-label` |
| `inline-bash.lisp` | inline bash | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `input-transform-streaming.lisp` | streaming input transform | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `input-transform.lisp` | input transform | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `interactive-shell.lisp` | interactive shell | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `kimi-deferred-tools.lisp` | kimi deferred tools | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `mac-system-theme.lisp` | host theme | blocked | not this host's contract (adjudication 2026-08-18 Part E) |
| `message-renderer.lisp` | `/status` custom renderer | pty | `example-message-renderer` |
| `minimal-mode.lisp` | minimal mode | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `modal-editor.lisp` | modal editor chrome | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `model-status.lisp` | model status | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `notify.lisp` | hook OSC notify | pty | `example-notify` |
| `overlay-qa-tests.lisp` | overlay QA tests | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `overlay-test.lisp` | `/overlay-test` overlay | pty | `example-overlay-test` |
| `permission-gate.lisp` | permission gate | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `pirate.lisp` | `/pirate` transform | pty | `example-pirate` |
| `plan-mode` | `/plan` / `/todos` | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `preset.lisp` | `/preset` | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `project-trust.lisp` | project trust | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `prompt-customizer.lisp` | prompt customizer | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `protected-paths.lisp` | protected-paths hook | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `provider-payload.lisp` | provider payload hook | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `qna.lisp` | `/qna` | pty | `example-qna` |
| `question.lisp` | question tool | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `questionnaire.lisp` | questionnaire tool | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `rainbow-editor.lisp` | rainbow editor chrome | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `reload-runtime.lisp` | `/reload-runtime` | pty | `example-reload-runtime` |
| `rpc-demo.lisp` | `/rpc-*` (RPC mode) | blocked | RPC mode, not TUI (adjudication 2026-08-18 Part E) |
| `sandbox` | `/sandbox` | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `send-user-message.lisp` | `/ask` / `/steer` / `/followup` | pty | `example-send-user-message` |
| `session-name.lisp` | `/session-name` + footer | pty | `example-session-name` |
| `shutdown-command.lisp` | shutdown command | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `snake.lisp` | `/snake` custom component | pty | `example-snake` |
| `space-invaders.lisp` | `/invaders` custom component (wide-only) | pty | `example-space-invaders` |
| `ssh.lisp` | network SSH | blocked | real network (adjudication 2026-08-18 Part E) |
| `status-line.lisp` | status line | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `structured-output.lisp` | structured output | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `subagent` | subagent example | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `summarize.lisp` | `/summarize` | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `system-prompt-header.lisp` | system-prompt header | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `tic-tac-toe.lisp` | `/tic-tac-toe` custom component | pty | `example-tic-tac-toe` |
| `timed-confirm.lisp` | `/timed` family | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `titlebar-spinner.lisp` | titlebar spinner | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `todo.lisp` | `/todos` | pty | `example-todo` |
| `tool-override.lisp` | tool override | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `tools.lisp` | `/tools` selector | pty | `example-tools` |
| `trigger-compact.lisp` | `/trigger-compact` | pty | `example-trigger-compact` |
| `truncated-tool.lisp` | truncated tool display | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `widget-placement.lisp` | widget placement | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `with-deps` | load-time dependency registration | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `working-indicator.lisp` | working indicator | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
| `working-message-test.lisp` | working-message test | suite-lock | `goal12-ported-extension-registrations-cover-the-baseline-surface` + `goal12-ported-extension-entrypoints-load-without-diagnostics` |
