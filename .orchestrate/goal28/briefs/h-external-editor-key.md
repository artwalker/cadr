GOAL: The existing key name app.editor.external opens the current editor text in edit-in-external-editor and writes the result back. The command comes from settings-external-editor-command. Do not hardcode a ctrl+g check. Do not invent a new editor widget.

SCOPE: Exclusive worktree /tmp/cadr-g28-editor-key on branch g28-external-editor-key. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy tip files you will edit plus /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp and /root/projects/cadr/src/cadr-cli/support/external-editor.lisp. Do not edit /root/projects/cadr. Patch /tmp/g28-external-editor-key.patch. Do not commit.

CONTEXT: settings-external-editor-command is on tip. +tui-keybinding-definitions already binds app.editor.external to ctrl+g. +logical-key-events in src/cadr-tui/keybindings.lisp does not map that name, so the key never becomes an event. The controller case on input-event-kind is in src/cadr-cli/interactive/controller.lisp near :copy. edit-in-external-editor is in src/cadr-cli/support/external-editor.lisp. Mirror :code-block-indent-function: pass an editor-command function into the interactive session, do not read settings from a process-wide special. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- +logical-key-events maps app.editor.external to an event kind.
- That event kind calls edit-in-external-editor with the current editor text and a runner built from the command function.
- The returned text is written back with the existing editor set-text path.
- A test uses a fake runner, not a real process. It locks the written-back text.
- Do not drop settings-external-editor-command.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-external-editor-key-reaches-existing-editor. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; no matchesKey of a literal ctrl+g; do not implement npmCommand; do not copy or rewrite cadr-ai.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim.
