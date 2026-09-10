GOAL: Settings JSON extensions, a path array, is the list of extension files or directories cadr loads. Absent settings keep current extension discovery. Do not treat the extensions/ directory under the agent dir as this key.

SCOPE: Exclusive worktree /tmp/cadr-g28-extensions on branch g28-extensions. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration), not from an old SHA, so Goal 28 readers already present stay. If you must create from 219a3edd0, copy these tip files first: /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp, /root/projects/cadr/src/cadr-cli/sdk/settings-service.lisp, /root/projects/cadr/src/cadr-cli/package.lisp, /root/projects/cadr/cadr-cli.asd, /root/projects/cadr/src/cadr-cli/bootstrap/commands.lisp, /root/projects/cadr/src/cadr-cli/sdk/resource-service.lisp. You may edit the extension path loader and the settings reader. Do not edit /root/projects/cadr. Patch /tmp/g28-extensions.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-settings-gaps.tsv marks extensions truly-absent. pi getter is settings.extensions, a string array of local extension paths or directories (getExtensionPaths in packages/coding-agent/src/core/settings-manager.ts at d981de122). cadr already has :explicit-paths on make-cli-extension-manager from CLI --extension and SDK additional-extension-paths. Call sites:
- src/cadr-cli/bootstrap/commands.lisp cli-help-extension-flags
- src/cadr-cli/bootstrap/commands.lisp the runtime make-cli-extension-manager
- src/cadr-cli/sdk/resource-service.lisp
Append settings paths after CLI/SDK paths. Mirror settings-prompt-paths. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- Absent settings still discover extensions from the current discovery path.
- extensions in settings JSON is a list of paths the existing extension manager reads as explicit paths.
- A test locks absent and one present path with expected path strings written in the test.
- Do not drop thinkingBudgets, httpProxy, websocket timeout, sessionDir, shell, compaction, branch-summary, themes, skills, or prompts readers.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-extensions-settings-reach-existing-loader. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not implement npmCommand, externalEditor, or lastChangelogVersion; do not copy or rewrite cadr-ai; do not invent a second extension store.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim.
