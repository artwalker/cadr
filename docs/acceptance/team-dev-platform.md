# cadr development process

> **Status:** live. Goal 20 pairing and Goal 21 remaining work use this crew.
> Local `scripts/cadr-team*.sh` / tmux / worktree / `cursor-agent --resume`
> lanes are **retired** (scripts kept; do not treat them as current).

## Standing crew

Three Grok Bot agents. None of them is a local tmux pane.

| Role | What it does | What it does not do |
|------|----------------|---------------------|
| **总控** | Coordinates only: queue, briefs, pass/fail of a round, what to send next | Edit the repo, open PRs, merge |
| **实现** | Turns accepted work into a Cursor Ultra cloud-agent run on GitHub | Merge GitHub itself, tag, release, force-push, spend |
| **审** | Verdict: pass / change / stop | Write code |

Code changes go through a **Cursor cloud agent** on GitHub `artwalker/cadr`.
The agent starts from `cadr-migration` and returns a **branch + PR**. For
Goal 20 leftover pairing, that same cloud agent **verifies the READY PR
and merges it** into `cadr-migration` (serial; see below). Grok Bot 实现
does not click merge; the cloud agent does.

## Source of truth

GitHub `cadr-migration` is the source of truth for cloud agents. A local WSL
checkout or worktree is not.

**Cursor cloud agents** merge READY Goal 20 pairing PRs into
`cadr-migration` after the freeze record is on the PR (n=5 Friend-MachineD
`--only-enforce`, observed exact, ledger test, Part H, over-1× if ratio>1).
Do it **one PR at a time**: leftover PRs all patch the same harness files.
Rebase the next PR onto the new tip before merging it. After a source
file's leftover slugs are on tip, refresh inventory
(`python3 scripts/goal20-unpaired-paths.py --write && --check`). Do not
announce Goal 20 complete. Do not mark G.17 `met`. Do not bump
`nextPairNum` for leftover IDs.

Tags, releases, force-push, and spend still require **Ethan**.

## Cloud-agent output

- Report gate results as the **summary line and exit code only**.
- Do not dump full `./scripts/verify.sh` or `./scripts/test-cl.sh` logs into
  chat (those runs are tens of thousands of lines).

## Retired local team (do not use)

The previous local crew used `scripts/cadr-team.sh`, tmux panes, git
worktrees, `cursor-agent --resume`, `director-merge.sh`, and a 90-minute
agent timeout (`CADR_AGENT_TIMEOUT_SEC=5400`). Those scripts still exist
under `scripts/` so history and Goal 21 records stay replayable. They are
not how cadr is developed now. Do not delete them as part of ordinary
process updates.
