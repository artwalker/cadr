GOAL: Settings JSON skills, a path array, is the list of skill directories or files cadr loads. Absent settings keep the current skill discovery. Do not invent a second skill store.

SCOPE: Exclusive worktree /tmp/cadr-g28-skills on branch g28-skills. If created from 219a3edd0, copy tip Goal 28 settings readers and related CLI files from /root/projects/cadr: src/cadr-cli/bootstrap/settings.lisp, src/cadr-cli/sdk/settings-service.lisp, src/cadr-cli/package.lisp, cadr-cli.asd, src/cadr-cli/bootstrap/commands.lisp, src/cadr-cli/resource-loader.lisp, src/cadr-cli/sdk/resource-service.lisp. You may edit the skill path loader and the settings reader. Do not edit /root/projects/cadr. Do not revert tip cadr-ai or drop sibling Goal 28 tests from cadr-cli.asd. Patch /tmp/g28-skills.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-settings-gaps.tsv marks skills truly-absent. themes was just landed as a path array into the existing loader. Mirror that pattern for skills. Read pi's skills getter at d981de122. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- Absent settings still load skills from the current discovery path.
- skills in settings JSON is a list of paths the existing loader reads.
- A test locks absent and one present path with expected path strings written in the test.
- Tip Goal 28 readers and tests stay loadable. Do not remove them from cadr-cli.asd.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not revert tip cadr-ai; do not implement extensions or prompts in this unit.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If cadr has no skill path loader, stop and report that.
