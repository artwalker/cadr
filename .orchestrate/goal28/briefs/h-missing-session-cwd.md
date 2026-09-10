GOAL: Import of a session whose stored working directory does not exist signals missing-session-cwd-error. The printed text stays "Session working directory does not exist: ...". Do not invent a second import path.

SCOPE: Exclusive worktree /tmp/cadr-g28-missing-cwd on branch g28-missing-session-cwd. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy these tip files first and edit only the copies: /root/projects/cadr/src/cadr-cli/bootstrap/sessions.lisp, /root/projects/cadr/cadr-cli.asd. Do not edit /root/projects/cadr. Patch /tmp/g28-missing-session-cwd.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-presence-rest.tsv marks errorClasses MissingSessionCwdError missing. pi@d981de122 session-cwd.ts throws MissingSessionCwdError when the stored session cwd is absent. cadr import-agent-session already errors with the string "Session working directory does not exist: ~A" after load-session, then the surrounding handler-case returns that string. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- define-condition missing-session-cwd-error with a session-cwd reader. Report text is "Session working directory does not exist: " plus the cwd.
- The existing probe-file check inside import-agent-session signals that condition instead of a bare error string.
- The surrounding handler-case still returns the condition text as the import error string so /import printing does not change.
- Do not add a new cwd check on resume. No process-wide special.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-missing-session-cwd-reaches-existing-import. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not replace sessions.lisp wholesale; do not change the printed sentence.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If that probe-file check does not exist, stop and report that.
