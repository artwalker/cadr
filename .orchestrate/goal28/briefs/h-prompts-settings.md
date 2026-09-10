GOAL: Settings JSON prompts, a path array, is the list of prompt template files or directories cadr loads. Absent settings keep current prompt discovery. Do not treat the prompts directory under the agent dir as this key.

SCOPE: Exclusive worktree /tmp/cadr-g28-prompts on branch g28-prompts. If created from 219a3edd0, copy tip files that hold Goal 28 settings readers: /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp, /root/projects/cadr/src/cadr-cli/sdk/settings-service.lisp, /root/projects/cadr/src/cadr-cli/package.lisp, /root/projects/cadr/cadr-cli.asd, /root/projects/cadr/src/cadr-cli/bootstrap/commands.lisp, /root/projects/cadr/src/cadr-cli/sdk/resource-service.lisp, /root/projects/cadr/src/cadr-cli/resource-loader.lisp. You may edit the prompt path loader and the settings reader. Do not edit /root/projects/cadr. Patch /tmp/g28-prompts.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-settings-gaps.tsv marks prompts truly-absent. pi getter is settings.prompts, a string array of local prompt template paths or directories (packages/coding-agent/src/core/settings-manager.ts at d981de122). cadr already has :explicit-prompt-paths from CLI --prompt-template. Append settings paths after CLI paths, same shape as settings-skill-paths / settings-theme-paths on tip. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- Absent settings still load prompts from the current discovery path.
- prompts in settings JSON is a list of paths the existing loader reads.
- A test locks absent and one present path with expected path strings written in the test.
- Do not drop thinkingBudgets, httpProxy, websocket timeout, sessionDir, shell, compaction, branch-summary, themes, or skills readers.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not implement extensions, npmCommand, or externalEditor in this unit; do not copy or rewrite cadr-ai.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If cadr has no prompt path loader, stop and report that. Do not invent a second prompt store.
