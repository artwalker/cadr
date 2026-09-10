1. Repo /root/projects/cadr tip cadr-migration. Goal 30 only. Never reopen Goal 20-29 as incomplete.
2. Pin remains BASELINE d981de1229ef899957bbe968bc8dcda02a21f477 v0.85.1.
3. Solo agent. Automate every reversible first-run blocker. Do not leave automatable work for humans.
4. Product invent in /tmp worktrees when changing src. Docs, scripts, rebuild may land on tip.
5. Commit and push to origin/cadr-migration when a track advances. No force-push.
6. Stop when docs/acceptance/goal-v30.md Status is met and all four tracks closed.
7. Update .orchestrate/goal30/decisions.tsv every land.
8. Candor: intentional-difference SDK exports are not first-run blockers; do not burn the goal inventing them.
