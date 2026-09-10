GOAL: RPC bash uses the same shellPath and shellCommandPrefix settings as the CLI. Absent settings keep the current RPC bash command. No process-wide special.

SCOPE: Exclusive worktree /tmp/cadr-g28-rpc-bash on branch g28-rpc-bash. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy tip files you will edit plus /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp and /root/projects/cadr/src/cadr-cli/tools/bash.lisp. Do not edit /root/projects/cadr. Patch /tmp/g28-rpc-bash.patch. Do not commit.

CONTEXT: CLI run-user-bash in src/cadr-cli/bootstrap/commands.lisp already passes settings-shell-command-prefix and settings-shell-path into execute-user-bash. RPC rpc-start-bash in src/cadr-cli/modes/rpc/prompt-bash.lisp calls execute-user-bash without those keywords. run-rpc-mode in src/cadr-cli/modes/rpc/mode.lisp builds rpc-state from agent and extension-manager only. The CLI caller of run-rpc-mode already has settings-manager. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- RPC bash passes the settings shell path and prefix into the existing execute-user-bash keywords.
- Absent settings leave those arguments nil, which is the current default.
- A test locks one present prefix and one present shell path on the RPC call path, with the expected keyword values written in the test. Do not spawn a real shell if the argv can be captured.
- Do not drop CLI shell wiring or settings-npm-command.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-rpc-bash-settings-reach-existing-executor. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not invent an npm installer; do not copy or rewrite cadr-ai.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If run-rpc-mode has no settings owner at its caller, stop and report that caller.
