# Goal 18 Part L: one-off adjudication proposal for the 38 "new-server alignment" 待裁决 rows

Status: **pending user adjudication.** After the re-anchor to v0.84.1,
38 rows in the `docs/source-parity.md` working tree carry `有意差异` and
`PENDING ADJUDICATION` at the same time (0 of them in HEAD 51aed63d1; all of
them added by this upgrade), and neither the git history nor the existing
proposals holds a corresponding adjudication record (the 9 existing pending
items of the I7 proposal do not include this group; nor do the three
prerequisite adjudications of goal18-l-runbook). Under the ledger's convention
that "every row has an adjudication", this proposal asks the user to adjudicate
these 38 rows in one go.

## Grouping and scope

Five groups, 38 rows in total, all belonging to pi v0.84.1's **client/server
architecture rewrite + experimental CLI scaffolding**, and all registered as
`有意差异` on the cadr side:

| # | Group | Rows | source-parity.md lines | Baseline files |
|---|---|---|---|---|
| 1 | experimental CLI scaffolding | 8 | 459–466 | `packages/coding-agent/src/cli/experimental/{auth,cli,command-options,command,commands/client,commands/pi,commands/server,transport-address}.ts` |
| 2 | coding-agent client surface | 3 | 473–475 | `packages/coding-agent/src/client/{index,remote-session,transcript}.ts` |
| 3 | server harness / management HTTP | 2 | 615, 636 | `packages/coding-agent/src/server/create-harness.ts`, `packages/coding-agent/src/utils/management-http.ts` |
| 4 | packages/server v0.84.1 rewrite | 15 | 773–788 (except line 775, the barrel whose verdict is `已实现`) | `connection,errors,listener,protocol,server,sessions,snapshots`, `testing/{client,index,server,service}`, `transports/unix/{index,listener,preset,types}.ts` |
| 5 | packages/client v0.84.1 rewrite | 10 | 850–859 | `{client,connection,errors,index,promise,session-handle,state,transport,types,unix}.ts` |

## Evidence

- The verdict column of all 38 rows is `有意差异`, and the mapping column is
  `no cadr experimental CLI` / `no cadr remote-session client` /
  `src/cadr-server/* (v0.83 architecture port)`, that is, **cadr keeps the v0.83
  session-server architecture and has not ported the v0.84.1 client/server rewrite**.
- Acceptance criterion 12 requires only that "the 248 changed files have been
  triaged per section 1a" and that the four ledgers close; it does not require
  porting the client/server rewrite; that rewrite is an architectural decision,
  not a default obligation of Part L.
- Existing adjudication precedent: the 9 existing pending items of the goal 18
  I7 proposal (--resume, the npm registry, update --models, telemetry, the
  argument-less -r selector, the sentinel, the removal of --slynk/--no-tui,
  the deprecated URL, keybindings.json) were recorded in the ledger along with
  `USER-2026-08-10-001`, and do not cover this group; this group is a class
  exposed by the new re-anchor, and must be adjudicated separately.

## Adjudication requested

- Route A (recommended): **keep cadr's existing v0.83 server architecture and
  the current state of having no experimental CLI**, and record all 38 rows as
  `有意差异`; delete the words `PENDING ADJUDICATION` from the evidence column
  and rewrite it as "user adjudication 2026-08-12: the v0.84.1 client/server
  rewrite and the experimental CLI are architecture-level additions, and cadr
  keeps the v0.83 server architecture; the difference in the baseline
  capability surface has been registered (new-server alignment item)", while
  retaining the baseline file:line and the mapping explanation.
- Route B: move some or all of them into the unimplemented/gap list and port
  them in phases (this requires a separate proposal to assess the engineering
  effort and the acceptance surface of the v0.84.1 server protocol rewrite,
  which this goal does not undertake by default).

After adjudication, record it in the ledger by the existing process: change the
evidence column of `docs/source-parity.md`, re-run
`check-source-parity-drift.sh --ledger-only` (670 rows; the SHA-256 must either
stay unchanged or be synchronized with the ledger), register this adjudication
in open-questions, and then continue with the wrap-up batches.
