GOAL: Settings JSON websocketConnectTimeoutMs is passed as the existing optional timeout argument of connect-codex-websocket. No process-wide special.

SCOPE: Exclusive worktree /tmp/cadr-g28-websocket-timeout-arg on branch g28-websocket-timeout-arg. If created from 219a3edd0, copy tip settings/cli files first so sessionDir, shell, compaction, and branch-summary stay. You may edit the caller that opens the Codex websocket and the settings reader. Do not add cadr-ai::*websocket-connect-timeout-ms*. Do not edit /root/projects/cadr. Patch /tmp/g28-websocket-timeout-arg.patch. Do not commit.

CONTEXT: The previous unit was not landed. connect-codex-websocket already takes &optional timeout-ms and passes it to connect-native-http-stream. Absent settings must still pass the current 10 second default. Pi's unset getter is 15000ms at the Codex client. Keep cadr's current 10 second connect argument unless the call site already used another number. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- No defparameter or setf of a websocket timeout special.
- The session that owns the settings passes websocketConnectTimeoutMs into connect-codex-websocket.
- A second session cannot change the first session's timeout.
- Absent or non-positive JSON still yields 10 seconds at that argument.
- A test locks absent and present cases with expected numbers written in the test.
- Do not drop sessionDir, shell, compaction, or branch-summary readers on tip.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no *websocket-connect-timeout-ms*; do not implement httpProxy or thinkingBudgets.

REPORT: status, call chain from settings to connect-codex-websocket, test result, patch path, deviations.

STANDING: read /root/projects/cadr/.orchestrate/goal28/preferences.md verbatim and obey.
