GOAL: Settings JSON retry.provider.maxRetries, maxRetryDelayMs, and timeoutMs reach the existing provider retry policy. Absent settings keep the current defaults. Do not invent a second retry loop.

SCOPE: Exclusive worktree /tmp/cadr-g28-retry on branch g28-provider-retry. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy tip files you will edit plus /root/projects/cadr/src/cadr-cli/sdk/settings-service.lisp and /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp. Do not edit /root/projects/cadr. Patch /tmp/g28-provider-retry.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-presence-rest.tsv still marks ProviderRetry.* missing. sdk-settings-retry-settings already reads retry.provider fields in src/cadr-cli/sdk/settings-service.lisp and has no caller. cadr-ai retry policy lives in src/cadr-ai/support/retry.lisp. pi pin d981de122. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- The session path that already retries a provider request takes maxRetries, maxRetryDelayMs, and timeoutMs from settings as arguments.
- Absent settings keep the current defaults.
- A test locks absent defaults and one present maxRetries with the expected values written in the test.
- Do not drop branch-summary chooser wiring.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-provider-retry-settings-reach-existing-policy. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not invent a second retry loop; do not copy or rewrite cadr-ai except the existing retry policy constructor if it already takes those fields.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If no existing retry policy constructor exists, stop and report that.
