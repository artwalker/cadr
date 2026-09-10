GOAL: Settings JSON externalEditor is the command cadr runs to edit the current message outside the TUI. Absent settings use VISUAL, then EDITOR, then nano. The existing edit-in-external-editor function is the only editor. Do not treat the keybinding name app.editor.external as this command string.

SCOPE: Exclusive worktree /tmp/cadr-g28-editor on branch g28-external-editor. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy tip files you will edit plus /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp. Do not edit /root/projects/cadr. Patch /tmp/g28-external-editor.patch. Do not commit.

CONTEXT: pi getExternalEditorCommand in packages/coding-agent/src/core/settings-manager.ts at d981de122. cadr edit-in-external-editor is in src/cadr-cli/support/external-editor.lisp and has no caller. The key name app.editor.external exists as a binding label, not as a command. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- A non-empty externalEditor string is the command. Blank or non-string falls through to VISUAL, then EDITOR, then nano.
- The resolved command is an argument to the existing edit-in-external-editor path, not a process-wide special.
- If the interactive editor already dispatches app.* keys, that path calls edit-in-external-editor and writes the result back into the editor text.
- If no such dispatch exists, stop after the command resolver and report the nearest key loop. Do not invent a new editor widget.
- A test locks the three fallback strings and one settings string.
- Do not drop lastChangelogVersion, markdown indent, or the path-array readers.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-external-editor-settings-reach-existing-editor. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not implement npmCommand; do not copy or rewrite cadr-ai.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim.
