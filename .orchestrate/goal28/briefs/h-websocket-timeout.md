GOAL: Settings JSON websocketConnectTimeoutMs changes the timeout cadr uses when opening a websocket. Absent settings keep the current default timeout.

SCOPE: Exclusive worktree /tmp/cadr-g28-websocket-timeout on branch g28-websocket-timeout. If created from 219a3edd0, copy these tip files first: /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp, /root/projects/cadr/src/cadr-cli/sdk/settings-service.lisp, /root/projects/cadr/src/cadr-cli/package.lisp, /root/projects/cadr/cadr-cli.asd, /root/projects/cadr/src/cadr-cli/bootstrap/commands.lisp, /root/projects/cadr/src/cadr-cli/bootstrap/tools.lisp, /root/projects/cadr/src/cadr-cli/tools/bash.lisp, /root/projects/cadr/src/cadr-cli/sdk/agent-session.lisp, /root/projects/cadr/src/cadr-agent/loop/agent-loop.lisp. You may edit the settings reader and the existing websocket connect call site. Do not rewrite the websocket stack. Do not edit /root/projects/cadr. Patch /tmp/g28-websocket-timeout.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-settings-gaps.tsv marks websocketConnectTimeoutMs truly-absent. Read the pi getter in packages/coding-agent/src/core/settings-manager.ts at d981de122 and use that default. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- Absent settings still use the same timeout the connect path uses today.
- websocketConnectTimeoutMs in settings JSON is the number passed into that connect path.
- Non-positive values do not replace the default.
- A test locks absent and present cases with expected numbers written in the test.
- Do not drop sessionDir, shell, compaction, or branch-summary readers already on tip.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. Paste the pass line. Do not run the full suite.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; do not mark inventory match; do not implement thinkingBudgets or httpProxy in this unit.

REPORT: status, files changed, default timeout, test command and result, patch path, deviations.

STANDING: read /root/projects/cadr/.orchestrate/goal28/preferences.md verbatim and obey.
