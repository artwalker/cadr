# Goal 20 Part K9 — cadr-cli

114 Lisp files / 48,260 lines after rewrite (draft 113 / 48,020).
This is the last K package. No K10.

## keep

§2.3 no-rewrite files kept. Two keep reasons drifted after
`optional-integer` started coercing JSON null: `tools/find.lisp`
and `tools/ls.lisp` dropped their `(or … default)` wrappers.
Their remaining I (sort / truncate / notice bytes) still holds.

Selectors were not merged (Part I 4.3 / draft K0.2). Sessions,
settings, and models each have their own frame contract
(gutter metadata, submenu unwrap, `:component` input). Merging
them would couple those contracts.

## 54 needs-rewrite

| File | I0 |
|---|---|
| arguments | `+cli-boolean-flag-slots+` |
| auth | one metadata let |
| commands | spec-driven command records |
| sessions | `+hotkeys-markdown-sections+` |
| settings | inline image options; fallback key table |
| config | `+oauth-login-providers+` |
| atomic-write | no restated `:flush` |
| headers | `+stream-setting-defaults+` |
| model-help | CLI names over unexported cadr-ai (B10 freeze) |
| resume-version-git | pop walk, missing token is 0 |
| shell-process | ProgramFiles loop |
| threads | apply core cleanup |
| timings | push + nreverse |
| installer | case-sensitive `GIT:` |
| llama/extension | `:manual` keyword |
| llama/provider | `llama-positive-number` |
| llama/ui | nthcdr; `:searching` |
| loaders | `format-key-text*` |
| armin | 2D array |
| daxnuts | parse-once RGB grid |
| state | `tui-multiline-editor-p` |
| status | last-status-cell |
| syntax | `advance` |
| theme | xterm-16 vector |
| transcript | `wrap-transcript-lines` |
| tool-rendering | kebab→camel |
| entries | `+startup-expanded-help+` |
| extension-ui | `extension-dialog-chrome` |
| autocomplete | push + nreverse |
| controller | one `plusp` wrapper |
| selectors/sessions | gutter prefixes |
| selectors/settings | unwrap + theme chrome |
| selectors/models | `:component` input |
| migration | `+managed-binary-names+` |
| credential-print | push/nreverse |
| matching | push/nreverse |
| registry | `model-registry-sort-predicate` |
| store | copy-model + three setfs |
| print | shared retry json-put |
| rpc/commands | `parse-queue-mode` |
| rpc/prompt-bash | `apply-input-or-queue` |
| rpc/ui | `rpc-dialog-request-object` |
| config-selector | `config-resource-kinds` |
| manifest | kind buckets |
| source | seen stores the cons |
| resource-loader | `load-resources-at-paths` |
| agent-session | `sdk-agent-session-dispatch` |
| cache-version | previous + any-reported-cache-p |
| model-service | unshadowed helper |
| resource-service | multiple-value-setq |
| settings-service | field flet |
| edit | `edit-no-changes-error` |
| grep | per-file line cache |
| path | optional-integer null→default |

## K0.2

`string=` stays on wire names (RPC commands, settings ids,
flag tokens). Internal enums intern once (`:manual`,
`:searching`, queue-mode keywords). No `define-*` moved onto
CLI. The one cadr-cli macro is still
`with-file-mutation-queue` in `tools/path.lisp`, a zero-decision
re-export of the agent owner.

Selectors look alike and were not merged. Each was Lisp-ified
in place: sessions emit gutter in one reverse walk, settings
unwrap once, models route the query through `:component`.

`atomic-write` / `threads` dropped restated defaults.
llama `"manual"` and installer `GIT:` are baseline-facing
bug fixes, not style.

`model-help` stays a five-line CLI facade. Exporting the
cadr-ai symbols would change the B10-frozen public package
text. Call sites that already used `cadr-ai::` keep doing so.

## Pairing

Transcript / armin / daxnuts / extension-ui / selectors / llama
ui touch official render-diff. Req 8 Date.now() is not used.
New I0 tests lock observable behavior (versions, JSON null,
GIT: case, xterm, llama gated text, OSC splice, kebab keys).
No `fboundp`. No `read-file-string`+`search`.

Blocked: 0. FiveAM 18841 → 18880. derive 680/680.
Official render-diff `--tier core` EXIT:0 (captured=120/122).
N_i untouched.

## H class

Booked class from tip `docs/benchmarks/goal20-unpaired-paths.json` via
`scripts/goal20-unpaired-paths.py` (longest prefix). Refreshed 2026-09-07
against denom 297 / 133658 (`needs-pair=0`, `pairable-uncovered=0`).
Not 148 wall-clock pairs. Historical K-booking `pairable-uncovered` /
`pending H pair` sentences are superseded by this list.

- `paired` (110): `arguments.lisp`, `bootstrap/auth.lisp`, `bootstrap/commands.lisp`, `bootstrap/main.lisp`, `bootstrap/sessions.lisp`, `bootstrap/settings.lisp`, `bootstrap/tools.lisp`, `config.lisp`, `extensions/commands.lisp`, `extensions/discovery.lisp`, `extensions/installer.lisp`, `extensions/llama/client.lisp`, `extensions/llama/extension.lisp`, `extensions/llama/huggingface.lisp`, `extensions/llama/provider.lisp`, `extensions/llama/ui.lisp`, `extensions/loader.lisp`, `interactive/autocomplete.lisp`, `interactive/clipboard.lisp`, `interactive/components/announcement.lisp`, `interactive/components/armin.lisp`, `interactive/components/countdown.lisp`, `interactive/components/daxnuts.lisp`, `interactive/components/loaders.lisp`, `interactive/controller.lisp`, `interactive/entries.lisp`, `interactive/extension-ui.lisp`, `interactive/footer.lisp`, `interactive/frame.lisp`, `interactive/images.lisp`, `interactive/selectors/auth.lisp`, `interactive/selectors/common.lisp`, `interactive/selectors/fork.lisp`, `interactive/selectors/login-dialog.lisp`, `interactive/selectors/models.lisp`, `interactive/selectors/sessions.lisp`, `interactive/selectors/settings.lisp`, `interactive/selectors/thinking.lisp`, `interactive/selectors/tree.lisp`, `interactive/selectors/trust.lisp`, `interactive/state.lisp`, `interactive/status.lisp`, `interactive/syntax.lisp`, `interactive/theme.lisp`, `interactive/themes.lisp`, `interactive/tool-render-session.lisp`, `interactive/tool-rendering.lisp`, `interactive/transcript.lisp`, `interactive/user-bash.lisp`, `media.lisp`, `migration.lisp`, `models/credential-print.lisp`, `models/login-selection.lisp`, `models/matching.lisp`, `models/registry.lisp`, `models/store.lisp`, `modes/print.lisp`, `modes/rpc/commands.lisp`, `modes/rpc/jsonl.lisp`, `modes/rpc/mode.lisp`, `modes/rpc/models.lisp`, `modes/rpc/prompt-bash.lisp`, `modes/rpc/sessions.lisp`, `modes/rpc/ui.lisp`, `output-accumulator.lisp`, `packages/commands.lisp`, `packages/config-selector.lisp`, `packages/manifest.lisp`, `packages/settings.lisp`, `packages/source.lisp`, `packages/update-checks.lisp`, `repl.lisp`, `resource-loader.lisp`, `sdk/agent-session.lisp`, `sdk/cache-version.lisp`, `sdk/model-service.lisp`, `sdk/resource-service.lisp`, `sdk/session-manager.lisp`, `sdk/session-runtime.lisp`, `sdk/settings-service.lisp`, `sdk/system-prompt.lisp`, `settings/config-values.lisp`, `settings/manager.lisp`, `settings/trust.lisp`, `support/atomic-write.lisp`, `support/changelog-share.lisp`, `support/event-bus.lisp`, `support/external-editor.lisp`, `support/file-watcher.lisp`, `support/headers.lisp`, `support/html.lisp`, `support/model-help.lisp`, `support/paths.lisp`, `support/resume-version-git.lisp`, `support/shell-process.lisp`, `support/threads.lisp`, `support/timings.lisp`, `system-prompt.lisp`, `tool-manager.lisp`, `tools/bash.lisp`, `tools/edit.lisp`, `tools/find.lisp`, `tools/glob.lisp`, `tools/grep.lisp`, `tools/ls.lisp`, `tools/path.lisp`, `tools/powershell.lisp`, `tools/read.lisp`, `tools/write.lisp`, `truncation.lisp`.
  Dual-ref: H cell vs pi + K FiveAM/render-diff vs previous cadr.
- `covered-as-callee` (3): `interactive/pending-messages.lisp`, `models/auth-storage.lisp`, `package.lisp`.
  On a named paired thunk; no own bench.
- `unpairable` (3): `build-support.lisp`, `crash.lisp`, `remote-repl.lisp`.
  Single-ref vs previous cadr; do not invent a pi pair.

