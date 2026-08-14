# 04 — Team and Process

cadr is built by a two-role team (executor + advisor) driving a goal/ledger/gate
pipeline: `scripts/test-cl.sh` (~17k FiveAM checks) plus the 24-stage
`scripts/verify.sh`, with persistent state in gitignored `goal20-state.md` and
five tracked parity ledgers. This section maps classic process literature onto
that setup, ordered by relevance. Figures marked "measured 2026-08-15" were
recounted for this report; the rest cite `docs/reviews/2026-08-14-external-review.md`
("the review") or the files themselves.

## 1. Theory of Constraints — Goldratt & Cox, *The Goal* (1984)

The throughput of any system is set by one constraint; the Five Focusing Steps
are identify, exploit, subordinate, elevate, repeat. cadr's constraint is not
writing Lisp — it is the **serial gate chain plus advisor bandwidth**.

Evidence: the executor is instructed to work the queue "until no `[ready]`
remains" (`goal20-state.md:7-9`), i.e. batches are sized to amortize verify.
Gate-run bookkeeping commits trail work batches by ~40–150 min (git log
2026-08-14: work `51e34ce2c` 17:02 → gate-run `b81a049f7` 17:43; `7a98c0c65`
17:52 → `7558184c5` 18:33; `dfd1cf676` 19:13 → `b31473ba2` 21:40; the review
reports 49–110 min verify intervals). The advisor recomputes denominators by
hand and re-runs gates himself (`goal20-advisor-note.md`: recounting
293 files / 120,897 lines, catching an executor round that landed two real bug
fixes without re-running `test-cl.sh`/`verify.sh`) and, per the review, has
absorbed executor-class work (the goal-20 English-translation commits) — a role
breach that consumes the scarcest resource.

- Exploit/subordinate: split `scripts/verify.sh` into a read-only `check` and a
  separate `record` subcommand (verify currently rewrites `docs/performance.md`
  via `scripts/write-performance-ledger.py` at `scripts/verify.sh:139-145` and
  forces a trailing bookkeeping commit per run); parallelize deterministic
  stages that share no state; extend the render-diff `--baseline-cache` pattern
  to all pi-side build artifacts. [needs adjudication — gate changes]
- Elevate: add advisor throughput only after the above; checklist automation
  (section 7) is cheaper than a second advisor.

## 2. DORA four key metrics — Forsgren, Humble & Kim, *Accelerate* (2018)

Four metrics predict delivery performance: deployment frequency, lead time for
changes, change failure rate, and time to restore service (renamed "failed
deployment recovery time" in DORA's 2023 model). cadr currently **cannot
measure any of the four**, so the advice is: instrument first, optimize second.

- Deployment frequency: effectively zero. `version.sexp` is `"0.2.0"` with no
  `v0.2.0` tag (`git describe` → `v0.67.6-455-gc287896ce`, measured
  2026-08-15); the repo inherits pi-era tags only.
- Lead time for changes: unmeasurable — verify's own wall-clock is not recorded
  (review item 2). The git-log proxies in section 1 are the only signal.
- Change failure rate: gates are strong but the only independent detector
  (`.github/workflows/ci.yml`) has not run since 2026-08-01 (review item 1).
  Five gate-green escapes reached a real terminal (P0 series; latest P0-4:
  agent-turn silence that static checkpoints cannot see), i.e. the failures
  concentrate exactly where the gates are blind — the time dimension.
- Recovery time: P0 fixes landed same-day on 2026-08-14 (`2249c8bb4` 19:13 →
  `34136ce88`/`2efa7355f` 20:55), but recovery time is only as good as
  detection, and detection currently depends on the user.

Recommendation: record per-stage and total wall-clock in the verify output and
the performance ledger; restore CI (even credential-gated to the deterministic
stages); only then set lead-time targets. [needs adjudication — gate changes]

## 3. Chief-programmer / surgical team — Mills (IBM FSD Report FSC 71-5108, 1971); Brooks, *The Mythical Man-Month*, ch. 3 (1975)

Mills proposed and Brooks popularized organizing around one chief programmer
(the "surgeon") supported by specialists (co-pilot, editor, toolsmith, tester,
language lawyer) so the scarce expert never does support work. cadr's
executor+advisor pair is this structure's modern form — the division of a
doer and an independent checker is affirmed, and goal20's productivity is
evidence it works.

The risk is role conflation in the support seat: the advisor is simultaneously
co-pilot (design rulings), editor/auditor (recomputing counts, re-running
gates), and occasionally surgeon (taking executor tasks). Mills gave those to
*different people*; combining them makes one person the judge of work they may
have touched, and a single point of bandwidth failure.

Recommendation: write a role-boundary list (ruling / audit / execution are
distinct hats; an item the advisor executed is audited by the user or not
claimed audited); codify the de-facto "advisor adjudicates, user vetoes" rule
into `docs/development-policy.md` (§5 still requires user adjudication while
goal20-part-a and I04 were advisor-ruled — review item 4); establish an advisor
backup/rotation path. [needs adjudication — policy text]

## 4. Lean's seven wastes — Ohno (Toyota Production System); software mapping by Poppendieck & Poppendieck, *Lean Software Development* (2003)

Ohno's catalog (waiting, overproduction, overprocessing, inventory, transport,
motion, defects) was mapped to software by the Poppendiecks. Four of the seven
have concrete cadr instances:

- Waiting: serial gate stages and the verify-amortizing batch pattern (section 1).
- Overprocessing: the same adjudication requirement is restated across
  `docs/development-policy.md` sections dated 2026-08-03/08/13, and
  `AGENTS.md:142-143` dual-writes the policy ("That file is the source; this is
  the working set") — two documents to keep in sync per policy change.
- Defects: 108/1,052 rotted cadr-side mappings in `docs/source-parity.md`
  (review item 3); 38 `PENDING ADJUDICATION` rows in that ledger (measured
  2026-08-15); stale Status lines in
  `docs/proposals/goal20-i04-scoped-covering.md` and
  `docs/proposals/goal-v13-session-export-assets.md` (review item 4).
- Inventory: 16 `[ready]` queue entries in `goal20-state.md` (measured
  2026-08-15) plus the adjudication backlog — work that is booked but not
  earning parity.

Recommendation: after goal20, consider a waste-elimination goal theme (defect
class: ledger rot, Part F's remaining coverage; overprocessing: single-source
the policy text). [needs adjudication — goal scope]

## 5. Egoless programming — Weinberg, *The Psychology of Computer Programming* (1971)

Weinberg's finding: code review fails when criticism of code is read as
criticism of the author; healthy teams decouple the two. cadr has
institutionalized this: the executor is instructed, on finding a wrong advisor
ruling, to append `异议: <reason>` under the review item rather than silently
comply or silently override (`goal20-state.md:48`, `:84`); a real dissent with
reasoning exists at `goal20-state.md:186` (the I04 scoping proposal). This is a
genuine health signal — the channel exists and is used.

Recommendation: keep the mechanism, and make dissent a tracked process metric —
retention rate, resolution, and whether the dissent was upheld. This requires
moving the review log from gitignored state into tracked docs (the review's
split suggestion: live queue at root, archived review log under `docs/`).
[needs adjudication — state/ledger format]

## 6. Peer code review sizing — SmartBear, *Best Kept Secrets of Peer Code Review* (2006)

A 10-month study of 2,500 reviews covering 3.2M LOC at Cisco found: defect
detection falls off past 200–400 LOC per sitting; sessions should stay under
60–90 minutes at ≤300–500 LOC/hour, yielding 70–90% defect discovery; and
author preparation (annotations the reviewer can check) materially raises
review quality.

cadr evidence: advisor review arrives per *round*, not per change — a single
`goal20-advisor-note.md` round re-checks bug fixes, nine paired ratios, and a
denominator recount at once. Executor batches are family-sized (e.g. Part F
commits `51e34ce2c` "37 generated provider-catalog rows", `674ff7212` "33
provider-definition rows"), which is the right grain. Two findings already have
cadr analogues: the five ledgers function as the review checklist (affirmed —
keep review ledger-keyed, not ad hoc), and the policy's evidence requirement
for human-judgement exits (`docs/development-policy.md` §5) *is* author
preparation (affirmed).

Recommendation: cap advisor review passes at ~400 changed LOC; split rounds
that mix bug fixes, ledger rewrites, and measurements into separate reviewable
units. No gate change needed.

## 7. Conway's law — Conway, "How Do Committees Invent?", *Datamation* (1968)

Organizations ship systems that mirror their communication structure; the
inverse Conway maneuver designs the org (or here, the ownership structure) to
force the desired architecture. cadr's nine ASDF systems deliberately mirror
pi's package layout (`AGENTS.md:39-51`) — correct while the goal is parity,
because the mirroring *is* the specification of where behavior lives.

After Part K (the Lisp-ification burn-down), that rationale expires and the
structure will drift toward Lisp conventions by accretion unless a target is
declared. Recommendation: before Part K lands, write the target architecture
explicitly into `docs/architecture.md` and the organization ledger
(`docs/code-organization.md`), then let burn-down land into that design —
inverse Conway with the ledger as the org chart. [needs adjudication —
architecture/policy text; maps to goal20 Part K]

## 8. Brooks's law and multi-agent coordination — Brooks, *The Mythical Man-Month*, ch. 2 (1975)

"Adding manpower to a late software project makes it later": new workers add
ramp-up and coordination cost superlinearly. cadr already runs multiple agents
in one tree (`AGENTS.md:186-187` mandates explicit-path staging for exactly
this reason), so the binding question is where merge/ramp costs concentrate.

They concentrate in the ledgers. `docs/source-parity.md` is 507,663 bytes over
948 physical lines with a longest single line of 36,624 characters (measured
2026-08-15) — one family row per physical line. `git blame`, `git diff`, and
any three-way merge are effectively disabled at that grain; two agents touching
two rows of the same family serialize on one line. The same holds, milder, for
`docs/parity-map.md` (longest line 1,084) and `docs/code-organization.md`
(666).

Recommendation: reformat ledgers to merge-friendly row-per-line with capped
width *before* scaling agent count — this is a format change to a ledger, so it
needs the same adjudication as any obligation-unit change, and it slots into
Part F's ledger-coverage work. [needs adjudication — ledger format; maps to
goal20 Part F]

## Section Top 3 (impact × cost)

1. **Make the pipeline measurable, then split verify.** Record wall-clock and
   per-stage timing; separate read-only `check` from `record`; restore CI.
   Cheap, unblocks DORA tracking and every TOC step. [needs adjudication —
   gate changes]
2. **Relieve the advisor constraint.** Role-boundary list, ~400-LOC review
   caps, codify advisor-adjudicates/user-vetoes in policy. Directly attacks
   the system's constraint per Goldratt. [needs adjudication — policy text]
3. **Merge-friendly ledger reformat + tracked review-log split.** Removes the
   coordination bottleneck before adding agents (Brooks) and preserves dissent
   records (Weinberg). Low cost, high leverage. [needs adjudication — ledger
   format; maps to Part F]
