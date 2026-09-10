1. Repo /root/projects/cadr tip cadr-migration. Goal 29 only. Never reopen Goal 20-28 as incomplete.
2. Pin remains BASELINE d981de1229ef899957bbe968bc8dcda02a21f477 v0.85.1.
3. Solo agent. No Task subagents. Parent does all invent, test, and land.
4. Product invent in /tmp worktrees when changing src. Hygiene and docs may land on tip.
5. Commit and push to origin/cadr-migration when a track advances. No force-push. No rebase of shared history.
6. match requires an existing FiveAM file that asserts pin-named behavior. Do not invent match from source-parity.
7. Perf keep only if fair remesure is strictly faster than HEAD and bytes/behavior match. Else exhausted-no-keep with evidence.
8. Dialog remains out-of-scope.
9. Stop when all four tracks in docs/acceptance/goal-v29.md are closed and goal-v29 Status is met.
10. Update .orchestrate/goal29/decisions.tsv every land.
