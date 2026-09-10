GOAL: The named environment variable PI_OFFLINE disables the same startup network operations as CADR_OFFLINE and --offline. Absent PI_OFFLINE keeps today's behavior. Do not setenv. Do not remove CADR_OFFLINE.

SCOPE: Exclusive worktree /tmp/cadr-g28-pi-offline on branch g28-pi-offline. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy these tip files first and edit only the copies: /root/projects/cadr/src/cadr-cli/tool-manager.lisp, /root/projects/cadr/src/cadr-cli/bootstrap/main.lisp, /root/projects/cadr/src/cadr-cli/sdk/cache-version.lisp, /root/projects/cadr/cadr-cli.asd. Do not edit /root/projects/cadr. Patch /tmp/g28-pi-offline.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-presence-rest.tsv marks environmentVariables PI_OFFLINE missing. pi@d981de122 main.ts treats --offline or isTruthyEnvFlag(PI_OFFLINE) as offline. cadr offline-mode-p only checks CADR_OFFLINE. main.lisp package-command checks --offline or CADR_OFFLINE=1. get-latest-cadr-release and check-for-new-cadr-version default offline-value to getenv CADR_OFFLINE. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md line 11.

ACCEPTANCE:
- PI_OFFLINE values 1, true, and yes are offline. Empty or unset is not.
- CADR_OFFLINE still works. --offline still works.
- No sb-posix:setenv of PI_OFFLINE or CADR_OFFLINE. No process-wide special.
- The existing offline predicate and the version-check offline default both see PI_OFFLINE. Do not invent a second offline flag.
- A test locks absent, PI_OFFLINE=1, and CADR_OFFLINE=1 with expected booleans written in the test. Pass an environment function. Do not setenv in the test.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-pi-offline-reaches-existing-offline. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not setenv; do not replace commands.lisp; do not drop CADR_OFFLINE.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If no existing offline predicate exists, stop and report that.
