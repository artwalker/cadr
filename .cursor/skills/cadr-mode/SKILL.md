---
name: cadr-mode
description: cadr overlay on pstack / poteto-mode. Default for every non-trivial cadr task, including leftover pairing, ledger work, and taking over Grok Bot or Cloud Agent runs. Read this before poteto-mode when working in this repository.
---

# cadr-mode

pstack (Lauren Tan / `@poteto`) is the engineering method for agents
working in this repository. The vendored tree is `.cursor/pstack/`
(MIT, pin in `.cursor/pstack/PIN`). Cursor skills are symlinked from
`.cursor/skills/<name>` into that tree.

This skill is the overlay. **cadr standing policy wins on conflict.**
pstack does not authorize merging PRs, changing gates, inventing
intentional-difference classes, or removing behavior that looks
intentional.

## Start every multi-step task

1. Open a todo list. First item: read the Principles index in
   `.cursor/pstack/skills/poteto-mode/SKILL.md` (the **Principles**
   section). Name each principle that changes a decision.
2. Read `docs/development-policy.md` and the current goal file (repo
   root `goalN.md` if present). Policy outranks playbooks.
3. Match a playbook. Copy its steps into the todo list verbatim. Skip
   only with an explicit `skip:` reason on that step.
4. Route remaining work through pstack skills (`how`, `why`,
   `architect`, `arena`, `swarm`, `interrogate`, `tdd`, `unslop`,
   `blast-radius`, `show-me-your-work`) as the playbook names them.

## Playbook routing (cadr)

| Task | Playbook |
|---|---|
| Read-only "how/why/are we sure" | pstack `investigation.md` |
| Take over Grok Bot / Cloud Agent / a pushed branch | pstack `session-pickup.md` then the matching playbook |
| Goal 20 leftover trio (measure-only pair) | `playbooks/g20-leftover-pair.md` in this skill |
| Bug with a repro | pstack `bug-fix.md` |
| Measured slowness vs a paired path | pstack `perf-issue.md` / `hillclimb.md`; lock to baseline, never reverse-engineer from cadr |
| New behavior | pstack `feature.md` then cadr gates |
| Structure-preserving change | pstack `refactoring.md` |
| Pixel/TUI geometry | pstack `visual-parity.md` plus official `render-diff.py gate --tier core` |
| Drive open PRs to merge-ready without landing | pstack `babysit.md` |
| User said land/merge | **stop** unless they explicitly asked to merge; this repo forbids agent merges |

## Conflicts: cadr over pstack

- **Ask before removing behavior that looks intentional.** pstack
  "never block on the human" does not override that.
- **Do not merge PRs or enable auto-merge.** pstack Shipping /
  Autopilot "land the stack" is not authorized here.
- **Pins, CHANGELOG, ledgers, `RATIO_CEILINGS` stay with the main
  executor.** Concurrent agents: read-only or disjoint-file worktrees
  only (`docs/development-policy.md` §7).
- **Runtime env is `CADR_*` only.** `PI_*` is not a fallback.
- **Assertions lock to the baseline**, never to current cadr output.
- **Done** means committed, with replayable evidence (path, test name,
  gate summary + exit code). A prior agent's self-report is not proof
  (`prove-it-works`).
- **Slynk** only for live-process defects, explicit `--slynk`. Not for
  pin/ledger edits.

## Prove it works (cadr artifacts)

After a change that can affect behavior or gates, run both when the
change can affect them:

```sh
./scripts/test-cl.sh
./scripts/verify.sh
```

Cloud agents: report the summary line and exit code only, not full
logs. After a disposition or render change, rerun the official
render-diff invocation in `AGENTS.md`. A leftover-pair knife that only
appends Goal 20 JSON may skip full verify when the knife contract says
so; record that `skip:` on the todo.

## Dogfooding cadr itself

Project `.cadr/` is gitignored. To have cadr-the-binary load these
skills in this repo:

```sh
./cadr --skills .cursor/pstack/skills --skills .cursor/skills/cadr-mode
```

Do not un-ignore `.cadr/` for this. Do not ship pstack as a default
user-facing cadr skill pack (that would be a product addition vs the
pinned baseline). This tree is for **developers of cadr**.

## Reply shape

Unslop. Name the playbook. Name the resume point on a pickup. Cite
evidence paths. Do not announce completion without a commit a third
party can replay.
