GOAL: Settings JSON sessionDir changes the directory cadr uses for session files. Absent settings keep the current default session directory.

SCOPE: Exclusive worktree /tmp/cadr-g28-session-dir on branch g28-session-dir. If created from 219a3edd0, copy these tip files first: /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp, /root/projects/cadr/src/cadr-cli/sdk/settings-service.lisp, /root/projects/cadr/src/cadr-cli/package.lisp, /root/projects/cadr/cadr-cli.asd, /root/projects/cadr/src/cadr-cli/bootstrap/commands.lisp, /root/projects/cadr/src/cadr-cli/bootstrap/tools.lisp, /root/projects/cadr/src/cadr-cli/tools/bash.lisp, /root/projects/cadr/src/cadr-cli/sdk/agent-session.lisp, /root/projects/cadr/src/cadr-agent/loop/agent-loop.lisp, /root/projects/cadr/test/cadr-cli/goal28-compaction-settings-test.lisp, /root/projects/cadr/test/cadr-cli/goal28-branch-summary-settings-test.lisp, /root/projects/cadr/test/cadr-cli/goal28-shell-settings-test.lisp. You may edit settings readers and the existing session-directory resolver. Do not rewrite session storage. Do not edit /root/projects/cadr. Patch /tmp/g28-session-dir.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-settings-gaps.tsv marks sessionDir truly-absent. pi reads settings.sessionDir in packages/coding-agent/src/core/settings-manager.ts at d981de122. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- Absent settings still resolve to the current default session directory.
- sessionDir in settings JSON is the directory the existing session list/create path uses.
- A test locks both cases with expected path strings written in the test.
- Do not drop compaction, branch-summary, or shell readers already on tip.

VERIFY: Run only the new FiveAM test. Paste the command and the pass line. Do not run the full suite.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; do not mark inventory match; do not implement thinkingBudgets, themes, or the RPC bash settings gap in this unit.

REPORT: status, files changed, test command and result, default when settings absent, patch path, deviations.

STANDING: read /root/projects/cadr/.orchestrate/goal28/preferences.md verbatim and obey.
