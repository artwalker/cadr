GOAL: A settings JSON object compaction.keepRecentTokens and compaction.reserveTokens changes the values cadr compaction uses. Defaults stay 20000 and 16384. Observable compaction cut does not change when the settings are absent.

SCOPE: Exclusive worktree /tmp/cadr-g28-compaction-settings on branch g28-compaction-settings from tip 219a3edd0. You may edit settings read/write and the existing agent compaction slot wiring. Do not rewrite the compaction algorithm. Do not edit /root/projects/cadr. Patch /tmp/g28-compaction-settings.patch. Copy tip untracked Goal 28 files into the worktree if you need them. Do not commit.

CONTEXT: docs/benchmarks/goal28-settings-gaps.tsv marks Compaction.keepRecentTokens and Compaction.reserveTokens truly-absent as settings keys. cadr already has agent slots compaction-keep-recent-tokens (20000) and compaction-reserve-tokens (16384) in src/cadr-agent/runtime.lisp and tool.lisp. pi reads settings.compaction.keepRecentTokens and settings.compaction.reserveTokens in packages/coding-agent/src/core/settings-manager.ts at d981de1229ef899957bbe968bc8dcda02a21f477. compaction.enabled already exists. Standing /root/projects/cadr/.orchestrate/goal28/preferences.md.

ACCEPTANCE:
- Absent settings still yield keep 20000 and reserve 16384.
- Setting compaction.keepRecentTokens and compaction.reserveTokens in the settings JSON changes the numbers the compaction path reads.
- A test locks both cases. The test does not generate expected values from the implementation under test.
- Existing compaction.enabled behavior stays.

VERIFY: Run the new test file with the repo's existing FiveAM or test runner. Paste the command and the pass line. Do not run the full suite.

TIMEBOX: 50 minutes. On expiry, return the patch and what the test showed, then stop.

FORBIDDEN: no commit; no push; no gt; no rebase; no dirty tip; do not mark the inventory row match; do not alias thinkingBudgets or externalEditor in this unit.

REPORT: status, files changed, test command and result, defaults when settings absent, patch path, deviations.

STANDING: read /root/projects/cadr/.orchestrate/goal28/preferences.md verbatim and obey.
