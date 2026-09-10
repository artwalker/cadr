GOAL: Settings JSON thinkingBudgets.high, thinkingBudgets.medium, thinkingBudgets.low, and thinkingBudgets.minimal change the token budgets cadr uses for those thinking levels. Absent settings keep the current defaults. Do not alias these keys to modelThinkingLevels.

SCOPE: Exclusive worktree /tmp/cadr-g28-thinking-budgets on branch g28-thinking-budgets. If created from 219a3edd0, copy tip files that already hold Goal 28 settings readers: /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp, /root/projects/cadr/src/cadr-cli/sdk/settings-service.lisp, /root/projects/cadr/src/cadr-cli/package.lisp, /root/projects/cadr/cadr-cli.asd, /root/projects/cadr/src/cadr-cli/bootstrap/commands.lisp, /root/projects/cadr/src/cadr-cli/sdk/agent-session.lisp, /root/projects/cadr/src/cadr-ai/websocket.lisp, /root/projects/cadr/src/cadr-ai/provider.lisp. You may edit settings readers and the existing thinking-budget lookup. Do not edit /root/projects/cadr. Patch /tmp/g28-thinking-budgets.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-settings-gaps.tsv marks those four keys and thinkingBudgets truly-absent. A prior alias pass refused to treat modelThinkingLevels as the same setting. Read pi getters in packages/coding-agent/src/core/settings-manager.ts at d981de122. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- Absent settings keep the budgets the current lookup returns.
- Each of the four JSON keys changes only that level.
- A test locks absent and one present level with expected numbers written in the test.
- Do not drop httpProxy, websocket timeout, sessionDir, shell, compaction, or branch-summary readers.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not implement themes or skills in this unit.

REPORT: status, call chain, defaults, test result, patch path, deviations.

STANDING: read preferences.md verbatim and obey.
