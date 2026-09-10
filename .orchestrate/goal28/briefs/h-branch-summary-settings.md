GOAL: Settings JSON branchSummary.reserveTokens and branchSummary.skipPrompt change cadr branch-summary behavior. Defaults stay reserve 16384 and skipPrompt false. Absent settings keep the current prompt and reserve.

SCOPE: Exclusive worktree /tmp/cadr-g28-branch-summary-settings on branch g28-branch-summary-settings from current tip files that this unit needs. Copy /root/projects/cadr compaction settings changes into the worktree if the branch is created from commit 219a3edd0 without them. You may edit settings read/write and the existing branch-summary call site. Do not rewrite summarization. Do not edit /root/projects/cadr. Patch /tmp/g28-branch-summary-settings.patch. Do not commit.

CONTEXT: docs/benchmarks/goal28-settings-gaps.tsv marks BranchSummary.reserveTokens, BranchSummary.skipPrompt, and branchSummary truly-absent. pi reads settings.branchSummary.reserveTokens (default 16384) and settings.branchSummary.skipPrompt (default false) in packages/coding-agent/src/core/settings-manager.ts at d981de122. cadr branch-summarization.lisp already defaults a local reserve-tokens to 16384. skipPrompt may be absent. Compaction keep/reserve wiring just landed on tip in bootstrap/settings.lisp and sdk/settings-service.lisp. Match that reader style. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- Absent settings still use reserve 16384 and do not skip the prompt.
- branchSummary.reserveTokens and branchSummary.skipPrompt in settings JSON change the values the branch-summary path reads.
- A test locks both cases. Expected values are written in the test, not computed from the new readers.
- Compaction keep/reserve and compaction.enabled stay as they are on tip.

VERIFY: Run only the new FiveAM test. Paste the command and the pass line. Do not run the full suite.

TIMEBOX: 50 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; do not mark inventory match; do not implement thinkingBudgets, themes, or shellPath in this unit.

REPORT: status, files changed, test command and result, defaults when settings absent, patch path, deviations.

STANDING: read /root/projects/cadr/.orchestrate/goal28/preferences.md verbatim and obey.
