GOAL: Settings JSON themes, a path array, is the list of theme files cadr loads. Absent settings keep the current theme discovery. Do not treat the theme string setting as this key.

SCOPE: Exclusive worktree /tmp/cadr-g28-themes on branch g28-themes. If created from 219a3edd0, copy tip files that hold Goal 28 settings readers: /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp, /root/projects/cadr/src/cadr-cli/sdk/settings-service.lisp, /root/projects/cadr/src/cadr-cli/package.lisp, /root/projects/cadr/cadr-cli.asd, /root/projects/cadr/src/cadr-cli/bootstrap/commands.lisp, /root/projects/cadr/src/cadr-cli/sdk/agent-session.lisp. You may edit the theme path loader and the settings reader. Do not edit /root/projects/cadr. Patch /tmp/g28-themes.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-settings-gaps.tsv marks themes truly-absent. A prior alias pass said the theme string is not the themes path array. Read pi's themes getter at d981de122. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- Absent settings still load themes from the current discovery path.
- themes in settings JSON is a list of paths the existing loader reads.
- A test locks absent and one present path with expected path strings written in the test.
- Do not drop thinkingBudgets, httpProxy, websocket timeout, sessionDir, shell, compaction, or branch-summary readers.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not implement skills or extensions in this unit.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If cadr has no theme path loader, stop and report that. Do not invent a second theme store.
