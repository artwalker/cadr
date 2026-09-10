GOAL: A missing /import path signals the existing import failure as SessionImportFileNotFoundError. The printed slash-command text stays "Failed to import session: File not found: ...". Do not invent a second import path.

SCOPE: Exclusive worktree /tmp/cadr-g28-import-missing on branch g28-import-missing. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy these tip files first and edit only the copies: /root/projects/cadr/src/cadr-cli/bootstrap/sessions.lisp, /root/projects/cadr/cadr-cli.asd. Do not edit /root/projects/cadr. Patch /tmp/g28-import-file-not-found.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-presence-rest.tsv marks errorClasses SessionImportFileNotFoundError missing. pi@d981de122 agent-session-runtime.ts throws SessionImportFileNotFoundError with message "File not found: ${filePath}" when importFromJsonl resolves a path that does not exist. cadr import-agent-session in src/cadr-cli/bootstrap/sessions.lisp returns (values nil "File not found: ..."). The /import handler prints "Failed to import session: ~A". Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- define-condition session-import-file-not-found-error with a file-path reader. Message is "File not found: " plus the namestring.
- import-agent-session signals that condition when the source file is absent. Do not keep the nil/string return for that case.
- The /import handler catches that condition and still prints "Failed to import session: File not found: ...".
- A present file does not signal that condition. Cancelled import still returns :cancelled.
- No process-wide special. Do not honor PI_ names.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-import-file-not-found-reaches-existing-import. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not replace sessions.lisp wholesale; do not change the printed slash-command prefix.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If import-agent-session does not exist, stop and report that.
