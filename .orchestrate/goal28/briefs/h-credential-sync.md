GOAL: After a credential write, a failed local model refresh signals credential-synchronization-error. The existing status line stays "..., but local model state could not be synchronized: ...". Do not invent a second login path.

SCOPE: Exclusive worktree /tmp/cadr-g28-credential-sync on branch g28-credential-sync. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy these tip files first and edit only the copies: /root/projects/cadr/src/cadr-cli/models/registry.lisp, /root/projects/cadr/src/cadr-cli/bootstrap/auth.lisp, /root/projects/cadr/cadr-cli.asd. Do not edit /root/projects/cadr. Patch /tmp/g28-credential-sync.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-presence-rest.tsv marks errorClasses CredentialSynchronizationError missing. pi@d981de122 model-runtime.ts throws CredentialSynchronizationError after a credential operation when local snapshot sync fails. cadr model-registry-login-api-key writes the credential then calls refresh-model-registry. refresh-model-registry stores the failure string on model-registry-error. auth.lisp report-login prints that string. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- define-condition credential-synchronization-error with provider-id, operation, and message readers. The report includes the existing synchronization sentence fragment, not a new wording.
- model-registry-login-api-key signals that condition when refresh-model-registry leaves a non-nil model-registry-error. The credential write stays before the signal.
- report-login still prints the existing synchronization line when that condition is signaled, or when model-registry-error is already set. Do not drop the string path.
- No process-wide special. Do not honor PI_ names.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-credential-sync-reaches-existing-login. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not replace registry.lisp or auth.lisp wholesale.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If model-registry-login-api-key does not refresh after the write, stop and report that.
