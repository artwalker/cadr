# Advisor playbook

**What this is**: the operating manual for the cadr advisor role — the
verification recipes, the monitoring mechanics, and the standing lessons that
until 2026-08-17 lived only in the advisor's session context. It exists so the
role survives a session loss and so it can be handed to a successor (human or
model) without losing the *methods*, not just the conclusions.

Written by the incumbent advisor. Per `development-policy.md` §5.2, the author
executing this document does not certify it: its adequacy is validated
behaviorally by the handover acceptance test in §9, not by self-review.

---

## 1. The role contract

Read these before the first ruling; they are the contract, this file is only
the manual:

- **`development-policy.md` §5.1** — the advisor adjudicates; the user holds an
  unconditional veto. A ruling lands in the artifact it rules on; durable
  rulings are committed to `docs/adjudications.md`. **The advisor may not
  adjudicate a change to the advisor's own authority** — that goes to the user,
  always. Commercial/product direction (release cadence, open-sourcing) also
  goes to the user: those answers depend on what the user wants, not on
  technical skill.
- **§5.2** — executing and auditing are different hats. An item the advisor
  executed is not audited by the advisor; either the user audits it or the
  delivery states plainly that it was not independently audited. Mechanical
  gate results stay valid regardless of who ran them; only the judgement layer
  is void.
- **`docs/adjudications.md`** — append-only. A ruling belongs there when it
  still constrains someone after the goal that produced it closes out.
- The advisor **instructs, never implements**: work goes to the state board as
  `[ready]` items with the acceptance criteria spelled out; the executor
  implements. The advisor implementing "just this once" is how §5.2 gets
  violated (it happened; the commit was reverted and rewritten as a spec).

## 2. Where truth lives

| Artifact | Tracked? | Holds |
| --- | --- | --- |
| `docs/parity-map.md`, `docs/source-parity.md`, `docs/performance.md`, `docs/presentation-parity.md`, `docs/code-organization.md` | yes | the five alignment ledgers |
| `docs/development-policy.md` | yes | cross-goal constraints |
| `docs/adjudications.md` | yes | durable rulings and their evidence |
| `docs/open-questions.md` | yes | anything absent from the baseline awaits a ruling here before implementation |
| `goal20-state.md` | **gitignored** | the work queue, push preconditions, per-item rulings |
| `goal20-draft.md` | **gitignored** | the goal's task definition |

The gitignored pair is local-only: a `git clean` destroys it and no gate turns
red. Never run `git clean` in this checkout; anything in those files that must
outlive the goal gets promoted into a tracked doc (that migration is an open
item).

## 3. What "green" means

**Green is defined by what the batch touched, not by one command.**
`scripts/test-cl.sh` runs the nine FiveAM systems and nothing else. Independent
gates outside it: `test-source-parity-drift.sh`, `check-source-parity-drift.sh`,
`check-code-organization.py`, `check-product-identity.py`,
`baseline-anchor.py`, the official `render-diff.py`, and the full
`verify.sh` (which alone reaches the render/tool-result/event differentials and
the PTY smoke layer). A batch that touched ledgers, fixtures, or rendering must
run the corresponding gates; deep changes take `verify.sh` in full.

**A gate result names the commit it measured, and that state is a commit**
(policy §5.7). The live working tree is the executor's desk, not a commit:

```
W=$(mktemp -d); git worktree add -q "$W/h" <commit> && (cd "$W/h" && ./scripts/test-cl.sh)
git worktree remove "$W/h"
```

**`test-cl.sh` failure mode**: on a suite abort it prints **no**
`cadr test summary` line — only `incomplete FiveAM accounting; expected exactly
9 suite summaries`. Grepping for the summary alone returns nothing on failure,
which reads as "did not run". Green means: nine suite summaries seen, and their
nine counts sum to the summary total (cross-add them; the summary line could in
principle come from elsewhere).

**Performance gates are machine-bound.** The cadr-vs-pi relative gate demands
the archive machine `Friend-MachineD`; on any other host it self-reports
`informational-host-mismatch` and stops constraining. The absolute budgets run
anywhere but are host-dependent (`docs/performance.md`). Never accept a
performance verdict measured elsewhere as a pass.

**Self-reported vs verified.** "EXIT:0" in a commit message is the executor's
claim until the advisor reruns it. Every advisor write-up marks each result as
*verified* (advisor ran it) or *self-reported* (executor's claim), and the
state board carries that distinction. Verification work is never delegated to a
helper model — a paraphrase of a gate run is not a gate run.

## 4. The pins registry

Several counts are deliberately hand-pinned in two places so that changing one
without signing off the other turns HEAD red. **That duplication is the
mechanism, not an accident — do not "fix" it into auto-derivation**, which
would remove the sign-off. The pairs must move in the same commit:

| Truth | Pin |
| --- | --- |
| `docs/source-parity.md` per-package rows and Total | `test/cadr-cli/goal12-examples-test.lisp` (identity string + row assertions) |
| source-parity ledger size and manifest SHA | `scripts/test-source-parity-drift.sh` self-test |
| `docs/code-organization.md` `GOAL20_LISPIFICATION_LEDGER` identity | `test/cadr-cli/goal20-part-i-test.lisp:6` |
| FiveAM check count | `docs/test-matrix.md` anchor (`write-test-check-anchor.py`) |
| production file/line denominator | `docs/benchmarks/goal20-unpaired-paths.json` **and** `docs/acceptance/goal-v20-part-h.md` |
| idiom-audit file set size | `docs/lisp-idiom-audit.md` |

Historical instance of the failure this catches: a legitimate reclassification
moved the source-parity Total and the pin did not follow — HEAD stayed red for
twelve commits while the live tree looked green.

## 5. Per-commit-type verification recipes

**Re-pin commits** (dispositions, fixture digests):
- key dispositions by the triple `(scenario, checkpoint, dimensions)`.
  Keying only `(scenario, checkpoint)` collapses 432 rows to 304
  (128 duplicate keys). Goal 20 §9 handover counted that artifact
  twice; the verdict was unaffected.
- entry count unchanged (or the delta explained), key set identical;
- the **only** changed field is the digest (`screenSha256` or equivalent);
  classes, reasons, and per-class usage counts show zero change — diff them
  field by field, not by eyeball;
- movement direction per changed cell: pi moved / cadr moved / both. Both is
  expected when the baseline moved. **cadr-only movement needs a source-level
  explanation** — find the cadr change that explains it and confirm the motion
  is *toward* the baseline, not away.

**Ledger verdict changes**:
- the pin moves in the same commit (§4);
- check for swap-masking: a net ±N can hide a demotion paired with a
  promotion. Diff verdicts per key; "no existing row changed verdict" is the
  claim to verify, not the totals.

**Exemption / review-registry changes**:
- the exemption count must not grow silently; each retired entry cites the
  baseline reason it is no longer needed;
- every `accepted-gap` entry names its compensating check with a `file:line`
  citation (adjudication 2026-08-16); and "no scenario exercises this" is
  **backlog, not limitation** whenever the harness can already express the
  scenario — check what the scenario schema supports before accepting that
  wording.

**Extractor / gate-tooling changes**:
- decide which side is truth before judging. Extractor converging toward
  pinned expectations = tightening (good). Expectations re-pinned from current
  output = potential loosening (investigate). "Only one side changed" is a
  defect in one direction and a fix in the other.

**Baseline upgrades** (the adjudicated order): drift dispositions first, then
the port (gate-safe half, then flip-dependent half), then re-pin denominators,
then flip `BASELINE`, then heal the drift self-test. The baseline flips
**last** so the differentials measure the port against the old baseline the
whole way; flipping first would make every porting error self-consistent.

## 6. Monitoring

The advisor's value concentrates in latency: drift caught within the batch,
before it compounds (the twelve-commit red window, the disposition re-pins,
the accepted-gap ruling were all same-day catches). The mechanism is
harness-specific; the requirement is only *one event per new commit*.

**Portable polling loop** (any harness can run this; stdout = event stream):

```bash
cd /root/projects/cadr
last=$(git rev-parse HEAD)
while true; do
  cur=$(git rev-parse HEAD)
  if [ "$cur" != "$last" ]; then
    git log --format='NEW %h %s' "$last..$cur" | tac
    last=$cur
  fi
  sleep 30
done
```

- **Claude Code**: wrap the loop in the `Monitor` tool with
  `persistent: true`; each stdout line arrives as a notification. Re-arm after
  every session restart — persistent means session-lifetime, not survives-restart.
- **cursor-agent** (no persistent watcher): either per-batch invocation — the
  executor finishes a batch, then run
  `cursor-agent --model claude-opus-5-thinking-xhigh -p "Read docs/advisor-playbook.md and goal20-state.md, then review <sha1>..<sha2> per the playbook; write rulings back to the state board"`
  — or a `post-commit` hook that queues the same call per commit (higher cost,
  lower latency). Per-batch is the recommended default.

On every event, the review starts from the commit *message* (the executor's
claims are the checklist) and ends with the recipes in §5.
The reviewer's silence is a wait state, not a vacancy: an executor
never fills in a ruling under any signature (adjudication
2026-08-17).

## 7. Standing lessons

Each of these was paid for; the one-line form is the minimum that transfers.

- **Slynk and load-and-probe are not interchangeable.** If the user
  reproduced in a running cadr, attach `--slynk` **first**
  (`(cadr-cli:active-agent)`, live tool restarts when the failure is a
  tool condition). "Could almost name it from source" is not a skip.
  A FiveAM reconstruction may lock the fix; it is not the diagnosis.
  "slynk is the same query as load-and-probe" is a refuse. Do not add
  pairable-path `restart-case` to look native. Part L/N recorded the miss.
- **Evidence before assertion.** Run one command before stating a fact,
  especially when relaying someone else's conclusion. External reports (and
  helper-model answers) are leads, never verdicts.
- **Three clean passes, different methods each.** Verification repeats until
  three consecutive passes with *different* questions find nothing new; any
  new finding resets the count. Walking the same table three times is one pass.
- **A checklist cannot check itself.** Acceptance criteria are derived
  independently of the artifact under review; the same list building and
  approving the work always reports done.
- **The live working tree is not a commit.** Two incidents; see §3.
- **Instruction-layer errors have no gate.** A contradiction between two lines
  of the state board stalled pushes for 16 days; a wrong attribution in an
  instruction nearly caused three days of perf measurements to be checked out
  away. Numbers that are wrong turn a gate red; instructions that are wrong
  fail silently — so instructions get the same verify-before-writing
  discipline as numbers, and durable rules live in tracked docs where review
  and history apply.
- **Scope reduction is the user's call.** Large work splits into parts; items
  are never silently deferred out of scope. The only legitimate shrink is
  marking an item blocked and sending it to adjudication.
- **Anything absent from the baseline is a new mechanism** and goes through
  `docs/open-questions.md` first, however obviously sensible — the advisor is
  as prone to this as anyone (the undo-stack cap: the executor's refusal of an
  advisor instruction was correct and the adopted design came from the
  executor).
- **Green ≠ what you tested if the object is wrong.** Before quoting any
  result, ask: is the thing I measured the thing I am concluding about?

## 8. Environment notes

- **WSL uses the Linux toolchain exclusively** (`/etc/wsl.conf`
  `appendWindowsPath = false`). Diagnose PATH splits with `which -a` (full
  list and ordering), never `command -v` — the historical failure was `node`
  and `npm` resolving to different origins.
- **The baseline anchor needs full history plus upstream tags.**
  `baseline-anchor.py` runs `git describe --tags <BASELINE commit>`; locally
  that works because the `upstream` remote (`earendil-works/pi`, fetch only —
  never push) is configured with tags. CI therefore needs
  `fetch-depth: 0` on checkout; a shallow clone fails this gate by
  construction. Making the script skip on shallow clones is a forbidden
  silent loosening — fix the checkout, not the gate.
- **Push topology**: `origin` = `artwalker/cadr` (private, push target);
  `upstream` = pi (fetch only). Push preconditions live at the top of the
  state board. CI green means the deterministic credential-free gate passed —
  not the release gate.
- **Differential pins are local truth; CI is a second environment.**
  Neutralize or align — never re-pin from CI (adjudication
  2026-08-17).

## 9. Handover acceptance test

Behavioral, not documentary. Cold-start the successor with only the repository
and this file, then:

1. have it state the role contract, the green definitions, and the pins
   registry from its own reading;
2. have it review the latest three substantive commits per §5;
3. compare its findings against the incumbent's reviews of the same commits.

A miss — a skipped pin check, a self-reported result treated as verified, a
re-pin accepted without the field-level diff — is a gap **in this playbook**:
fix the playbook and re-run. The incumbent does not certify the successor by
impression; the diff of the two reviews is the certification.
