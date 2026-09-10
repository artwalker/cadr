GOAL: Pin extension event names tool_call and tool_result register on the existing tool-call-before and tool-call-after hook tables. Dispatch stays the existing run-extension-hooks calls. Do not invent a second hook runner.

SCOPE: Exclusive worktree /tmp/cadr-g28-tool-call-events on branch g28-tool-call-events. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy these tip files first and edit only the copies: /root/projects/cadr/src/cadr-agent/extensions/registration.lisp, /root/projects/cadr/cadr-agent.asd. Do not edit /root/projects/cadr. Patch /tmp/g28-tool-call-events.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-presence-rest.tsv marks extensionEvents tool_call and tool_result missing. cadr already dispatches :tool-call-before and :tool-call-after from prepare-tool-execution and the after path. +extension-hook-events+ lists those keywords. register-extension-hook rejects any event not in that list. pi@d981de122 names the same hooks tool_call and tool_result. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- register-extension-hook accepts tool_call, "tool_call", tool_result, and "tool_result" and stores the handler on the existing :tool-call-before or :tool-call-after table.
- Existing :tool-call-before and :tool-call-after registrations still work.
- An unknown event still signals extension-registration-error.
- Do not add a new dispatch function. Do not change prepare-tool-execution. Do not setenv. Do not honor PI_ environment names.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-tool-call-events-reach-existing-hooks. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not invent a second hook runner; do not edit cadr-cli; do not replace registration.lisp wholesale if a small normalizer at register-extension-hook is enough.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If register-extension-hook cannot store on the existing hook table, stop and report that.
