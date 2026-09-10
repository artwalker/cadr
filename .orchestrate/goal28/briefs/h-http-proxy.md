GOAL: Settings JSON httpProxy is passed into the existing HTTP proxy resolver. No process-wide special. Absent settings keep today's proxy discovery.

SCOPE: Exclusive worktree /tmp/cadr-g28-http-proxy on branch g28-http-proxy. If created from 219a3edd0, copy these tip files first: /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp, /root/projects/cadr/src/cadr-cli/sdk/settings-service.lisp, /root/projects/cadr/src/cadr-cli/package.lisp, /root/projects/cadr/cadr-cli.asd, /root/projects/cadr/src/cadr-cli/bootstrap/commands.lisp, /root/projects/cadr/src/cadr-cli/sdk/agent-session.lisp, /root/projects/cadr/src/cadr-ai/websocket.lisp, /root/projects/cadr/src/cadr-ai/provider.lisp. You may edit the settings reader and the existing proxy resolver call. Do not add a special. Do not edit /root/projects/cadr. Patch /tmp/g28-http-proxy.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-settings-gaps.tsv marks httpProxy truly-absent. connect-codex-websocket already calls resolve-http-proxy-url-for-target. Read pi's httpProxy getter at d981de122. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md line 11.

ACCEPTANCE:
- No defparameter or setf of a proxy special.
- The session that owns the settings passes httpProxy into the existing resolver.
- Absent settings still use the current environment proxy discovery.
- A test locks absent and present cases with expected URL strings written in the test.
- Do not drop websocket timeout, sessionDir, shell, compaction, or branch-summary readers.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test, not at load top level. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not implement thinkingBudgets.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim and obey.
