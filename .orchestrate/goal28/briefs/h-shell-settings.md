GOAL: Settings JSON shellPath and shellCommandPrefix change the shell cadr starts and the prefix prepended to bash commands. Absent settings keep the current shell discovery and an empty prefix.

SCOPE: Exclusive worktree /tmp/cadr-g28-shell-settings on branch g28-shell-settings. If created from 219a3edd0, copy these tip files first so compaction and branch-summary wiring stay: /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp, /root/projects/cadr/src/cadr-cli/sdk/settings-service.lisp, /root/projects/cadr/src/cadr-cli/package.lisp, /root/projects/cadr/cadr-cli.asd, /root/projects/cadr/src/cadr-cli/bootstrap/commands.lisp, /root/projects/cadr/src/cadr-agent/loop/agent-loop.lisp, /root/projects/cadr/src/cadr-cli/sdk/agent-session.lisp, /root/projects/cadr/test/cadr-cli/goal28-compaction-settings-test.lisp, /root/projects/cadr/test/cadr-cli/goal28-branch-summary-settings-test.lisp. You may edit settings readers and the existing shell/bash call site. Do not rewrite process spawning. Do not edit /root/projects/cadr. Patch /tmp/g28-shell-settings.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-settings-gaps.tsv marks shellPath and shellCommandPrefix truly-absent. pi getters are getShellPath and getShellCommandPrefix in packages/coding-agent/src/core/settings-manager.ts at d981de122. cadr already has get-shell-config and node-execution-env shell-path in src/cadr-cli/support/shell-process.lisp and src/cadr-agent/execution-env.lisp. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- Absent settings do not change which shell is discovered and do not prepend a prefix.
- shellPath in settings JSON is the path passed into the existing custom-shell-path path. A missing file still errors the way get-shell-config already errors.
- shellCommandPrefix in settings JSON is prepended to the bash command string the execution path already builds.
- A test locks both keys with expected strings written in the test, not read back from the new readers as the oracle.
- Do not drop compaction or branch-summary readers already on tip.

VERIFY: Run only the new FiveAM test. Paste the command and the pass line. Do not run the full suite.

TIMEBOX: 50 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; do not mark inventory match; do not implement thinkingBudgets, themes, or the branch-summary prompt in this unit.

REPORT: status, files changed, test command and result, defaults when settings absent, patch path, deviations.

STANDING: read /root/projects/cadr/.orchestrate/goal28/preferences.md verbatim and obey.
