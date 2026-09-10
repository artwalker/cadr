GOAL: A live TUI session paints fenced code lines with settings JSON markdown.codeBlockIndent. Absent settings still paint two spaces. The renderer argument already exists. This unit only threads that argument the same way mermaid-mode already reaches the transcript.

SCOPE: Exclusive worktree /tmp/cadr-g28-md-indent-live on branch g28-md-indent-live. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy tip files you will edit plus /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp and /root/projects/cadr/src/cadr-tui/components/markdown.lisp. Do not edit /root/projects/cadr. Patch /tmp/g28-md-indent-live.patch. Do not commit.

CONTEXT: settings-markdown-code-block-indent is on tip. cadr-tui:render-markdown accepts :code-block-indent, default "  ". Transcript still calls render-markdown without it (src/cadr-cli/interactive/transcript.lisp render-assistant-blocks and render-tui-entry-uncached-compute). Mermaid already threads settings-mermaid-rendering-mode through :mermaid-mode-function in bootstrap/commands.lisp, tui-state-mermaid-mode, frame.lisp render-tui-entries, and the render cache key. Copy that path for the indent string. Include the indent in the render cache key the same way mermaid-mode is included, or a settings change will paint the cached two-space lines. No process-wide special. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- The assistant and user transcript render paths pass the indent from the existing settings function into render-markdown.
- Absent settings still produce the two-space prefix.
- A test locks one present prefix on the transcript path, with the expected painted line written in the test.
- Do not drop the renderer argument or settings-markdown-code-block-indent.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-markdown-indent-live-reaches-transcript. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not implement npmCommand, externalEditor, or lastChangelogVersion; do not copy or rewrite cadr-ai; do not invent a second markdown renderer.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If no settings owner exists on the mermaid-mode path, stop and report that.
