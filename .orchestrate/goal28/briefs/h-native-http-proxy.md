GOAL: A per-session httpProxy setting reaches native HTTP requests the same way it already reaches the websocket connect path. Absent settings keep the current environment-only proxy. Do not call setenv. No process-wide special.

SCOPE: Exclusive worktree /tmp/cadr-g28-native-http on branch g28-native-http-proxy. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy tip files you will edit, including /root/projects/cadr/src/cadr-ai/websocket.lisp and /root/projects/cadr/src/cadr-ai/transport/http.lisp and /root/projects/cadr/src/cadr-ai/provider.lisp. You may edit the native HTTP caller that already has an :http-proxy argument. Do not edit /root/projects/cadr. Patch /tmp/g28-native-http.patch. Do not commit.

CONTEXT: settings-http-proxy and stream-function-with-http-proxy already exist. Websocket connect uses environment-with-http-proxy and does not setenv. native-http-request in src/cadr-ai/transport/http.lisp resolves the proxy only from its environment keyword. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- The caller that already owns :http-proxy passes that value into native-http-request as an argument, using environment-with-http-proxy or the same resolve function. Absent httpProxy leaves the existing environment lookup.
- A test locks absent and one present proxy URL with the expected proxy string written in the test. Do not open a real socket.
- Do not drop websocket proxy wiring or settings-http-proxy.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-native-http-proxy-reaches-existing-request. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no setenv; no process-wide special; do not invent a second HTTP client.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If no caller already owns :http-proxy before native-http-request, stop and report that caller.
