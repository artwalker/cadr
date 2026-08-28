# Development Rules

cadr is a Common Lisp (SBCL) reimplementation of the
[`earendil-works/pi`](https://github.com/earendil-works/pi) coding agent.
The behavioral baseline is locked to commit
`53fa77ccd8a279eb87e92294ef3687b03ff80112`
(`v0.84.1-38-g53fa77ccd`, recorded in `BASELINE`). Do not chase a moving
upstream branch. Full parity: everything pi has, cadr has. Missing credentials
lower the verification tier (fixture replay); they do not shrink scope.

This file is for people and agents working **in this repository**. It is not
pi's TypeScript handbook and not operator notes for any particular wrapper
CLI. Runtime loading of a *user project's* `AGENTS.md` is a product feature
(`src/cadr-cli/resource-loader.lisp`); do not confuse the two.

`src/**/*.lisp` and outward-facing docs in this tree are English. Keep new
Lisp and this file that way.

## Required reading order

Before editing:

1. `docs/development-policy.md` — standing constraints. They outlive any
   single goal. Changing that file requires user adjudication.
2. The **current goal file** at the repo root (`goalN.md` or the issued
   draft). That file is the complete spec for the work in flight.
3. The five ledgers listed below. A green cell on one ledger never excuses a
   gap on another.

Goal files cite locations with **full repository paths**
(for example `src/cadr-cli/bootstrap/settings.lisp`, not
`bootstrap/settings.lisp` and not `src/cadr-tui/bootstrap/settings.lisp`).
Treat the goal's full path as authoritative. If it does not exist on disk,
stop and report the mismatch. Do not probe sibling directories.

## Package layout

Nine production ASDF systems, each rooted at `src/<system>/` with a matching
`cadr-<name>.asd` at the repo root:

| System | Tree | Role |
|---|---|---|
| `cadr-core` | `src/cadr-core/` | Failure-safety and persistence primitives |
| `cadr-ai` | `src/cadr-ai/` | Providers, models, streaming |
| `cadr-agent` | `src/cadr-agent/` | Agent loop, tools, extensions, session export |
| `cadr-tui` | `src/cadr-tui/` | Terminal rendering, editor, mermaid |
| `cadr-cli` | `src/cadr-cli/` | Process entry, settings, interactive chrome |
| `cadr-storage` | `src/cadr-storage/` | Session storage |
| `cadr-protocol` | `src/cadr-protocol/` | RPC framing |
| `cadr-server` | `src/cadr-server/` | Headless server |
| `cadr-evals` | `src/cadr-evals/` | Evaluation harness |

Tests live under `test/<system>/` and are wired through the corresponding
`/tests` ASDF systems. Support systems: `cadr-live-test-support`,
`cadr-live-tests`. Examples live under `examples/`.

When you name a file in a commit message, goal note, disposition, or review,
use the full path from the repo root.

## The five ledgers

Four parity ledgers answer whether cadr is **correct**. The fifth answers
whether it can keep being **developed**. None substitutes for another.

| Ledger | File | Question it answers |
|---|---|---|
| Behavior | `docs/parity-map.md` | Does the externally observable contract match the baseline, and where is the test? |
| Source | `docs/source-parity.md` | For each baseline source file, is the capability implemented, intentionally different, or missing? |
| Non-functional | `docs/performance.md` | What did it cost (time, allocation, RSS, stability) against the published ceilings? |
| Presentation | `docs/presentation-parity.md` | What does the user see (copy, style, geometry, truncation, output channels)? |
| Organization | `docs/code-organization.md` | Where does new code belong, and has one user-visible decision one owner? Goal 20 adds Lisp-ification status as columns on this same table — do not invent a second per-file list. |

`examples/manifest.sexp` is an auxiliary inventory consumed by ledger checks,
not a sixth ledger. `docs/visual-parity.md` supports the presentation ledger;
it is not a separate axis.

## Gates

After any change that can affect behavior or gates, run **both**:

```sh
./scripts/test-cl.sh
./scripts/verify.sh
```

`scripts/test-cl.sh` is the Nine-system FiveAM suite (isolated `HOME`).
`scripts/verify.sh` is the full deterministic pipeline: organization and
identity gates, official core render-diff, tool-result and event
differentials, then credential-gated live stages. A live skip for missing
credentials is not a skip of a deterministic stage.

Cloud agents: do not paste full `verify.sh` / `test-cl.sh` logs into chat
(tens of thousands of lines). Report the summary line and exit code only.

Do not run the full suite as a substitute for the official render-diff
invocation. After a disposition or render change, rerun the shipped gate:

```sh
python3 -u scripts/render-diff.py gate --tier core \
  --pi-repo . \
  --manifest test/fixtures/render-diff/scenarios.json \
  --dispositions test/fixtures/render-diff/dispositions.json
```

(`--baseline-cache` defaults to `/tmp/cadr-render-diff-pi-<short-sha>` from
`BASELINE`.)

`scripts/render-diff.py` **raises on the first** adjudication failure
(`validate_result_adjudications`). Fixing the error it printed does not prove
the rest of the book is clean. Rerun to a real **EXIT:0**. A previous
green `analyze` on old capture files is not a new gate.

Green SHA pairing answers "did this screen change?" It does **not** answer
"should it look like this?" Screens that match each other can still both be
wrong if the goldens were taken from a defective cadr. Lock assertions to the
baseline, never reverse-engineer them from current cadr output.

### `screenEqual` is not byte equality

Render-diff classifies each checkpoint three ways:

- **raw equal** — the normalized PTY byte slices match (`aligned`)
- **`screenEqual`** — tmux-replayed semantic screens match
  (`intentional-terminal-protocol` when raw still differs)
- otherwise — `requires-disposition`

`screenEqual` is a hash of the semantic screen, not of the raw stream. I01
(`textCovering: false`) covers SBCL ANSI segmentation and teardown only. It
must not absorb a visible-text or geometry difference.

When a checkpoint that used to need I04/I02/I03/I05 becomes `screenEqual`
but the raw streams still differ, the disposition is **stale as a semantic
claim**, not absent as a difference. **Downgrade that dimension to I01-only.
Do not delete the entry.** Deleting it fails the next gate with
`differences lack dispositions` (`automaticDisposition` stays
`intentional-terminal-protocol`). Splitting wide/narrow into two entries is
required when only one dimension became screen-equal.

A dimension whose recorded `screenSha256` pair is identical and whose classes
still include a non-I01 tag is already mechanically false — the record
disproves itself.

## Live Lisp diagnosis

Slynk and tool restarts stay **off for users** (explicit `--slynk <port>`;
no config/env back door). Use the live image; do not add Lisp machinery
to look native. Standing text: `docs/development-policy.md` §6.1
(user 2026-08-18: fully use the advantage, not Lisp-for-Lisp).

**Attach Slynk first** when the reproduction is a running cadr (interactive
TUI, `--mode rpc`, or a live provider). "Could almost name it from source"
does not skip this.

```sh
./cadr --slynk 4005 --provider opencode-go --model mimo-v2.5
# SLY: slime-connect 127.0.0.1 4005
```

```lisp
(cadr-cli:active-agent)
```

Inspect slots, queues, and the live condition. Redefine and continue.
On a tool failure, use `retry-tool-call` / `skip-tool-call` /
`abort-agent-run` at the site — do not kill the agent to replay. Then lock
the trigger with FiveAM. Do not print credentials.

**Do not attach Slynk** for pin/ledger edits, or for a rewrite whose
before/after is already a red/green FiveAM on constructed inputs. Do not
write "slynk is the same query as load-and-probe" for a live-process
defect. Do not add `restart-case` on pairable user-visible failure paths
"to use Lisp".

## Inviolable rules

Drawn from `docs/development-policy.md`. That file is the source; this is
the working set.

- Alignment is **observable behavior**, not source-tree shape. Understanding
  what pi does and implementing it in Lisp **is** alignment, and is better
  than file-for-file transcription.
- Structure may diverge only when **equal-strength behavioral assertions**
  land first, locked to the baseline. Assertions reverse-engineered from
  cadr are void. The project has already shipped thirteen full-screen SHAs
  that stayed green while locking the wrong vertical alignment.
- Lisp-native is not a style preference. The test is a **checkable benefit**
  (a repeated decision removed, an invariant the machine now enforces, a
  measured speedup). "Used a macro" is a means, not a benefit. New code
  must not be justified with "because pi is written that way."
- If you cannot invent a Lisp-native design, **say so and escalate**. Silent
  TypeScript-shaped copy produces identical behavior, so every ledger and
  every byte-level differential will go green. No existing gate can see it.
- Performance is uncapped above and must not fall below the baseline.
  Not slower than pi on a paired path; beating pi is not a stop. The
  target is this SBCL image's limit (cost and interactivity). A rewrite
  slower than pi **or** slower than pre-change cadr is unfinished (fix
  it or file `blocked`). Do not keep a transcription "for performance"
  without numbers. Do not spray `fixnum` / drop `safety` without a
  measured before/after.
- Point fixes (enumerable edits inside one module) can ship immediately
  with before/after measurements. Whole-module rewrites also need the
  performance regression gate and mechanical ledger remapping.
- Do not mix unrelated style rewrites into a functional change.
- Credentials never enter transcripts, logs, or session files. `auth.json`
  and crash logs are mode `0600` and redacted.
- New third-party dependencies need review; TLS via `cl+ssl` is the only
  standing cryptography exception. Anything pi does not have, and cadr
  would add, goes in `docs/open-questions.md` and waits for the user.
- Product identity has one owner:
  `src/cadr-ai/support/release.lisp`. Runtime environment is `CADR_*` only.
  `PI_*` is not a fallback.
- Human-judgement exits (dispositions, exemptions, allowlists, N/A rows,
  live skips, "Lisp-native is better") need: a concrete statement of the
  actual difference, a class whose summary covers that difference
  word-for-word, and evidence (digests or equivalent). Boilerplate notes
  fail the gate. A class that covers a majority of exits must have its
  ratio stated in the report.
- Changing a gate's obligation unit or inventing an intentional-difference
  class changes the definition of alignment. Propose it; do not adopt it
  and declare a perfect score in the same commit.
- **Done** means committed, with evidence a third party can replay (path,
  test name, gate output). Announcing completion without that is void.
- Ask before removing behavior that looks intentional. Do not commit unless
  asked. Stage explicit paths only; this tree may have more than one agent
  in it.
- Concurrent agents: read-only and disjoint-file worktrees only, with an
  ownership table before spawn. Never two writers in one checkout. Pins,
  CHANGELOG, ledgers, and `RATIO_CEILINGS` stay with the main executor.
  Merge one worktree at a time and run `test-cl.sh` on that commit.
  Full rule: `docs/development-policy.md` §7.
- Live crew is **Cursor cloud agents** only (`docs/acceptance/team-dev-platform.md`).
  Grok Bot 总控 / 实现 / 审 is retired. Goal 20 leftover pairing: after a
  READY PR has its n=5 freeze on the branch, **merge that PR into
  `cadr-migration`** (serial, one leftover PR at a time; rebase the next
  onto the new tip). Do not mark G.17 `met`. Do not announce Goal 20
  complete. Tags, force-push, and spend stay with Ethan.

## Recounting scale figures

Ledger and goal documents contain file/line counts that drift. Do not copy
a number into a new document without a measurement date and a command that
reproduces it. Example (Lisp production sources only):

```sh
# Measured when you run it; do not paste an old total as current.
find src -name '*.lisp' | wc -l
find src -name '*.lisp' -print0 | xargs -0 wc -l | tail -1
```

The dated totals that belong on the organization ledger live in
`docs/code-organization.md` and must be refreshed there, not here.

## User override

If the user's instructions conflict with this file, ask for an explicit
confirmation before overriding, then follow the user.
