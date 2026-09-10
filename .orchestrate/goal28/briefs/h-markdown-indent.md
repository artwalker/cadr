GOAL: Settings JSON markdown.codeBlockIndent is the string prepended to fenced code lines when cadr renders markdown. Absent settings keep the current two-space indent. Do not treat the theme color md-code-block as this key.

SCOPE: Exclusive worktree /tmp/cadr-g28-md-indent on branch g28-md-indent. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration), not from an old SHA, so Goal 28 readers already present stay. If you must create from 219a3edd0, copy these tip files first: /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp, /root/projects/cadr/src/cadr-cli/sdk/settings-service.lisp, /root/projects/cadr/src/cadr-cli/package.lisp, /root/projects/cadr/cadr-cli.asd. You may edit the markdown renderer and the settings reader. Do not edit /root/projects/cadr. Patch /tmp/g28-md-indent.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-settings-gaps.tsv marks Markdown.codeBlockIndent truly-absent. pi getter is settings.markdown.codeBlockIndent, default "  " (getCodeBlockIndent in packages/coding-agent/src/core/settings-manager.ts at d981de122). cadr hardcodes the two spaces in markdown-line in src/cadr-tui/components/markdown.lisp around the in-code-p branch that concatenates "  " with the line. Thread the indent as an argument from the caller that owns settings. Default the argument to "  " so callers without settings stay unchanged. No process-wide special. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- Absent or non-string markdown.codeBlockIndent still prepends two spaces to fenced code lines.
- A string markdown.codeBlockIndent is the prefix those lines get.
- A test locks absent and one present prefix with the expected rendered strings written in the test.
- Do not drop thinkingBudgets, httpProxy, websocket timeout, sessionDir, shell, compaction, branch-summary, themes, skills, prompts, or extensions readers.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-markdown-indent-settings-reach-existing-renderer. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not implement npmCommand, externalEditor, or lastChangelogVersion; do not copy or rewrite cadr-ai; do not invent a second markdown renderer.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If the hardcoded indent is not in markdown-line, stop and report the actual call site.
