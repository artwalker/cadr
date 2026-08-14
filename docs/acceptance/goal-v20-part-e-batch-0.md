# Goal 20 Part E — batch 0: observable-surface inventory

Date: 2026-08-13. Counted from `examples/extensions/` excluding
`support.lisp`. **78 package entries** (files + directories). The draft's
"80" is a snapshot; recount:

```sh
find examples/extensions -mindepth 1 -maxdepth 1 ! -name support.lisp | wc -l
```

Part D already differentials snake, tic-tac-toe, space-invaders. This batch
does not add scenarios; it records the surface of every remaining entry so
later batches cannot silently skip.

## Surfaces

| Entry | Observable surface | Differential? |
|---|---|---|
| snake.lisp | `/snake` custom component | Part D done |
| tic-tac-toe.lisp | `/tic-tac-toe` custom component | Part D done |
| space-invaders.lisp | `/invaders` custom component | Part D done (wide-only) |
| hello.lisp | session-start notify | yes — startup with example loaded |
| notify.lisp | hook notify | yes — startup / event |
| session-name.lisp | `/session-name` | yes — slash + footer name |
| custom-header.lisp | `/builtin-header` / header widget | yes |
| custom-footer.lisp | `/footer` | yes |
| commands.lisp | `/commands` list | yes |
| pirate.lisp | `/pirate` transform | yes |
| overlay-test.lisp | `/overlay-test` | yes |
| bookmark.lisp | `/bookmark` `/unbookmark` | yes |
| send-user-message.lisp | `/ask` `/steer` `/followup` | yes (faux) |
| trigger-compact.lisp | `/trigger-compact` | yes (injected compact already exists) |
| reload-runtime.lisp | `/reload-runtime` | yes |
| thinking-label / hidden-thinking-label.lisp | `/thinking-label` | yes |
| message-renderer.lisp | `/status` custom renderer | yes |
| entry-renderer.lisp | `/status-card` | yes |
| event-bus.lisp | `/emit` | yes |
| dynamic-tools.lisp | `/add-echo-tool` | yes |
| tools.lisp | `/tools` | yes |
| todo.lisp | `/todos` | yes |
| qna.lisp | `/qna` | yes |
| preset.lisp | `/preset` | yes |
| summarize.lisp | `/summarize` | needs model — faux ok |
| timed-confirm.lisp | `/timed` family | yes (wall-clock: harness-pause) |
| rpc-demo.lisp | `/rpc-*` | rpc mode, not TUI — **blocked pending adjudication** if TUI-only gate |
| sandbox/ | `/sandbox` | yes if local |
| plan-mode/ | `/plan` `/todos` | yes |
| gondolin/ | `/gondolin` | yes if assets local |
| doom-overlay/ | `/doom-overlay` | needs WAD — **blocked** without fixture wad |
| with-deps/ | load-time dep | registration only unless we add a command scenario |
| custom-provider-* | provider registration | needs fake provider drive — later batch |
| ssh.lisp | network | **blocked** (real network) |
| github-issue-autocomplete.lisp | network | **blocked** |
| mac-system-theme.lisp | host theme | **blocked** (not this host's contract) |
| file-trigger.lisp | fs watch | yes with fixture file write |
| git-* / dirty-repo-guard | git repo | yes with fixture git dir |
| auto-commit-on-exit / confirm-destructive / permission-gate / protected-paths | hook on tool | yes with faux tool call |
| input-transform* / inline-bash / rainbow-editor / modal-editor / border-status-editor | editor chrome | yes |
| status-line / titlebar-spinner / working-indicator / widget-placement / custom-compaction / system-prompt-header / prompt-customizer / model-status / minimal-mode / claude-rules / built-in-tool-renderer / truncated-tool / tool-override / structured-output / provider-payload / kimi-deferred-tools / handoff / project-trust / shutdown-command / question / questionnaire / overlay-qa-tests / working-message-test / bash-spawn-hook / subagent | as named | later batches; none silently skipped |

Blocked rows above need user adjudication before they can be omitted from the
gate. They are listed, not dropped.
