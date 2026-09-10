GOAL: Settings JSON httpIdleTimeoutMs reaches the existing HTTP read timeout as a per-request argument. Absent settings keep the current request default. No process-wide special.

SCOPE: Exclusive worktree /tmp/cadr-g28-http-idle on branch g28-http-idle. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy these tip files first and edit only the copies: /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp, /root/projects/cadr/src/cadr-cli/sdk/settings-service.lisp, /root/projects/cadr/src/cadr-cli/bootstrap/commands.lisp, /root/projects/cadr/src/cadr-cli/sdk/agent-session.lisp, /root/projects/cadr/src/cadr-ai/provider.lisp, /root/projects/cadr/cadr-cli.asd. Do not edit /root/projects/cadr. Patch /tmp/g28-http-idle-timeout.patch. Do not commit.

CONTEXT: settings-http-idle-timeout-ms and sdk-settings-http-idle-timeout-ms already read httpIdleTimeoutMs, default 300000. The settings UI displays that value. No stream or request call uses it. pi@d981de122 uses that timeout as the HTTP idle timeout. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md line 11.

ACCEPTANCE:
- The session stream path passes httpIdleTimeoutMs into the existing request read timeout as an argument. 300000 stays the absent default.
- A present value of 5000 becomes a 5 second read timeout on that request. Do not change connect-timeout unless the existing request already uses the same field for idle.
- Do not drop provider-retry, http-proxy, websocket timeout, or thinking-budgets wraps.
- No defparameter. No setenv. Do not copy provider.lisp wholesale. Only add the idle argument on the tip request call that already takes read-timeout.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-http-idle-timeout-reaches-existing-request. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not invent a second HTTP client; if the transport has no read-timeout argument, stop and report the function name.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim.
