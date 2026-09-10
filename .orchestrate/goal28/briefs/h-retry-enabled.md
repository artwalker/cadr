GOAL: Settings JSON retry.enabled, retry.maxRetries, and retry.baseDelayMs reach the existing agent auto-retry decision. Absent settings keep the current agent defaults. Do not invent a second retry loop.

SCOPE: Exclusive worktree /tmp/cadr-g28-retry-enabled on branch g28-retry-enabled. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy these tip files first and edit only the copies: /root/projects/cadr/src/cadr-agent/tool.lisp, /root/projects/cadr/src/cadr-cli/bootstrap/commands.lisp, /root/projects/cadr/src/cadr-cli/sdk/agent-session.lisp, /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp, /root/projects/cadr/cadr-cli.asd, /root/projects/cadr/cadr-agent.asd if the test system needs it. Do not edit /root/projects/cadr. Patch /tmp/g28-retry-enabled.patch. Do not commit.

CONTEXT: settings-retry-settings and sdk-settings-retry-settings already return :enabled-p, :max-retries, :base-delay-ms. stream-function-with-provider-retry already overlays provider max-retries. That is not this unit. pi@d981de122 agent-session.ts _willRetryAfterAgentEnd uses getRetrySettings().enabled and maxRetries before auto-retry. cadr agent-will-retry-p already checks agent-auto-retry-p and agent-auto-retry-max-attempts. make-agent does not accept those keywords, so the slots stay t and 3. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md line 11.

ACCEPTANCE:
- make-agent accepts :auto-retry-p, :auto-retry-max-attempts, and :auto-retry-base-delay and stores them on the existing slots.
- CLI and SDK make-agent calls pass those from settings-retry-settings / sdk-settings-retry-settings.
- enabled false means agent-auto-retry-p is nil. Absent enabled keeps t.
- maxRetries 2 becomes auto-retry-max-attempts 2. Absent maxRetries keeps 3.
- baseDelayMs 4000 becomes auto-retry-base-delay 4. Absent baseDelayMs keeps 2.
- Do not drop the stream-function-with-provider-retry wrap, http-proxy, websocket timeout, or thinking-budgets.
- No process-wide special. No setf of a retry special.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-retry-enabled-reaches-existing-agent. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not invent a second retry loop; do not copy or rewrite cadr-ai; do not replace commands.lisp or settings.lisp wholesale.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If make-agent cannot store the existing auto-retry slots, stop and report that.
