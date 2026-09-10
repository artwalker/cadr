GOAL: Settings httpIdleTimeoutMs that already arrives as :read-timeout on stream-chat reaches the existing SSE and AWS event-stream HTTP calls. Omitted :read-timeout keeps today's nil. No second HTTP client. No process-wide special.

SCOPE: Exclusive worktree /tmp/cadr-g28-http-idle-stream on branch g28-http-idle-stream. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy these tip files first and edit only the copies: /root/projects/cadr/src/cadr-ai/provider.lisp, /root/projects/cadr/src/cadr-ai/transport/http.lisp, /root/projects/cadr/src/cadr-ai/transport/aws-event-stream.lisp. Do not edit /root/projects/cadr. Patch /tmp/g28-http-idle-stream.patch. Do not commit.

CONTEXT: stream-function-with-http-idle-timeout already injects :read-timeout in seconds. complete-chat already forwards it to request-json. stream-chat accepts :read-timeout via &allow-other-keys and ignores it. request-provider-events, request-sse, and request-aws-event-stream hardcode :read-timeout nil. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md line 11.

ACCEPTANCE:
- request-sse and request-aws-event-stream take an optional read-timeout. Omitted keeps nil.
- request-provider-events forwards that keyword.
- stream-chat passes its :read-timeout into request-provider-events. Do not drop environment-with-http-proxy, connect-timeout from timeout-ms, or provider retry.
- A supplied 5 second read-timeout is the value invoke-http-request sees. Omitted stays nil.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-http-idle-stream-reaches-existing-sse. Paste the pass line. Stub the HTTP function. Do not open a socket.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not copy provider.lisp wholesale; do not change the nil default when read-timeout is omitted.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If request-sse cannot take a read-timeout argument, stop and report that.
