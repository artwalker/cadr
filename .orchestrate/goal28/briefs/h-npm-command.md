GOAL: Settings JSON npmCommand is the argv prefix cadr uses for npm package lookup and install. Absent settings keep the current npm argv. Do not invent an npm package installer if the Common Lisp build already refuses npm packages.

SCOPE: Exclusive worktree /tmp/cadr-g28-npm on branch g28-npm-command. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy tip files you will edit plus /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp. Do not edit /root/projects/cadr. Patch /tmp/g28-npm-command.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-settings-gaps.tsv marks npmCommand truly-absent. pi getNpmCommand returns a string array (settings-manager.ts at d981de122). cadr package-npm-install-argv in src/cadr-cli/packages/source.lisp already takes :npm-command and defaults to ("npm"). src/cadr-cli/packages/commands.lisp currently errors that npm packages are unavailable in the Common Lisp build. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- npmCommand is read only when it is a vector of strings. The first entry must be a non-empty command. Else nil, and the existing default stays.
- If a production caller of package-npm-install-argv or another npm argv builder exists, that caller receives the settings list as an argument. No process-wide special.
- If the only npm path is the unavailable error, stop after the reader and the argv argument. Do not invent an installer. Report that call site.
- A test locks absent default ("npm") and one present argv prefix with the expected argv written in the test.
- Do not drop externalEditor, lastChangelogVersion, markdown indent, or the path-array readers.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-npm-command-settings-reach-existing-argv. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not copy or rewrite cadr-ai; do not implement npm package installation.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim.
