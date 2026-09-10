GOAL: Tree navigation asks "Summarize branch?" unless branchSummary.skipPrompt is true. skipPrompt true stays no-summary and does not ask. Do not invent a new selector widget.

SCOPE: Exclusive worktree /tmp/cadr-g28-branch-prompt on branch g28-branch-summary-prompt. Create the worktree from current tip of /root/projects/cadr (branch cadr-migration). If you must create from 219a3edd0, copy tip files you will edit plus /root/projects/cadr/src/cadr-cli/bootstrap/settings.lisp. Do not edit /root/projects/cadr. Patch /tmp/g28-branch-prompt.patch. Do not commit.

CONTEXT: pi interactive-mode.ts showExtensionSelector "Summarize branch?" with "No summary", "Summarize", "Summarize with custom prompt" at d981de122. skipPrompt skips that and defaults to no summary. cadr settings-branch-summary-skip-prompt-p exists. branch-summary-tree-summarize-p requires user-wants-summary-p, and select-tree-entry in src/cadr-cli/bootstrap/commands.lisp calls it with no user yes, so summarize never runs. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- skipPrompt true does not ask and summarize-p is false.
- skipPrompt false asks through an existing selector. "No summary" is false. "Summarize" is true.
- A test locks those two results with the expected summarize-p written in the test. The test may pass a fake chooser. Do not invent a new widget.
- Do not drop reserve-tokens wiring.

VERIFY: Run only the new FiveAM test via fiveam:run! and quit on its boolean. The test form must be inside fiveam:test. Name it goal28-branch-summary-prompt-reaches-existing-tree. Paste the pass line.

TIMEBOX: 45 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; no process-wide special; do not invent a selector widget; do not copy or rewrite cadr-ai.

REPORT: status, call chain, test result, patch path, deviations.

STANDING: read preferences.md verbatim. If no existing selector can take those labels, stop and report the nearest one.
