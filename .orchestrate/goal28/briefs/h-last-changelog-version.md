GOAL: Settings JSON lastChangelogVersion is the last changelog version cadr has shown. An empty interactive session shows changelog entries newer than that string, then stores the current cadr version. Absent key on a fresh session stores the current version and shows nothing. A session that already has messages shows nothing. collapseChangelog is a different key.

SCOPE: Exclusive worktree /tmp/cadr-g28-changelog on branch g28-last-changelog. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy tip files you will edit plus /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp. Do not edit /root/projects/cadr. Patch /tmp/g28-last-changelog.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-settings-gaps.tsv marks lastChangelogVersion truly-absent. pi is getLastChangelogVersion / setLastChangelogVersion and getChangelogForDisplay in packages/coding-agent/src/modes/interactive/interactive-mode.ts at d981de122. parseChangelog and getNewEntries live in packages/coding-agent/src/utils/changelog.ts. cadr already has parse-changelog in src/cadr-cli/support/changelog-share.lisp and settings-set in src/cadr-cli/settings/manager.lisp. Interactive startup already has startup-compact-lines. Use those. Do not invent a second parser or a process-wide special. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- Absent lastChangelogVersion stores the current version and returns no changelog text.
- A stored older version returns only newer parse-changelog entries, then stores the current version.
- A session that already has messages does not show changelog text and does not need to rewrite the key.
- A test locks those three cases with the expected version string and entry versions written in the test.
- Do not drop settings-markdown-code-block-indent or the path-array readers.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-last-changelog-version-reaches-startup. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not implement npmCommand or externalEditor; do not copy or rewrite cadr-ai; do not treat collapseChangelog as this key.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If no startup notice slot exists, stop and report the nearest one. Do not invent a widget.
