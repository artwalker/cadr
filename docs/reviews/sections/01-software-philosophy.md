# 01 — Software Philosophy

Nine classical positions, ordered by relevance to cadr's current state (goal20: Lisp burn-down + outperform-pi). Each entry: the argument itself, cadr's concrete evidence (file:line), and an actionable recommendation.

Evidence discipline: facts marked "review" are taken from the 2026-08-14 external review; everything else was re-verified against the working tree on 2026-08-15. Verification produced two corrections to the review, adopted throughout this section: the WebSocket provider code lives at `src/cadr-ai/websocket.lisp` (not `src/cadr-ai/providers/codex/websocket.lisp`), and the "verbatim duplicated 12-branch dispatch" in the TUI controller is in fact two *structurally parallel but divergent* `cond` chains — which changes the fix from "extract one function" to "extract one dispatch table" (see §2).

## 1. Naur — *Programming as Theory Building* (1985)

**Peter Naur, "Programming as Theory Building", Microprocessing and Microprogramming 15(5), 1985.** The program is not its text; the program is the *theory* the developers hold — why the code is the way it is, which requirements map to which decisions, which alternatives were rejected and why. A newcomer cannot rebuild that theory from the text alone; when the theory-holders leave, the program is "dead" even while it still compiles and runs.

cadr's five parity ledgers (behavior / source / non-functional / presentation / organization) are the project's strongest Naur-artifact: they externalize not only *what* maps to pi but *why* each mapping exists — and, crucially, they record the *sanctioned divergences*, the rejected alternative every parity project otherwise re-litigates forever. Rejected alternatives are precisely the part of a theory that code can never recover. The ledgers deserve the credit the review gave them.

But the theory of the goal20 *regime itself* — advisor rulings, user vetoes, the de facto convention that advisor adjudication plus user veto substitutes for the user arbitration `development-policy.md` §5.5 still formally demands — lives in `goal20-state.md`, 89.7 KB, matched by `.gitignore:28` (`/goal*.md`). One `git clean` or one machine loss destroys the rationale layer while every gate stays green: the text (ledgers, gates, code) survives; the theory (why the rules are what they are) evaporates. The executor↔advisor handoff mechanism deserves half credit: passing theory through a written state file is far better than hallway memory. But an unversioned, single-writer scratch file is a theory channel with no error correction — and the failure mode is not only loss but silent divergence: an executor resuming from a stale copy holds a *different* theory than the advisor, with no checksum to detect it.

A second symptom: `docs/source-parity.md` pins theory to volatile `file:line` coordinates, and the rot follows Naur's mechanism exactly. Trace: a mapping records cadr file:line at transcription time → Part K refactors move and rename Lisp code → lines shift → `scripts/check-source-parity-drift.sh` performs exactly one existence check, on its dispositions file (`:33`), never on the cadr-side target → the drift gate stays green while 108 of 1,052 mappings now point at the wrong code (review). The theory said *why* the mapping exists; the coordinate was only a pointer into it, and pointers were never validated.

Recommendations:

- Commit durable rulings as an append-only, repo-tracked adjudication log (ADRs or `docs/adjudications.md`); keep `goal20-state.md` as disposable scratch that syncs into it. Near-zero cost; removes the single point of theory loss. [needs adjudication]
- Amend `development-policy.md` §5.5 to record the advisor-ruling/user-veto convention as practiced. Unwritten conventions are theory stored in exactly one head. [needs adjudication]
- Re-anchor ledger mappings to symbol names plus content hashes instead of bare line numbers — this is the already-planned Part F (ledger mapping repair); add a cadr-side existence check to the drift script as its first line of defense.

## 2. Parnas — information hiding (1972)

**David Parnas, "On the Criteria To Be Used in Decomposing Systems into Modules", CACM 15(12), 1972.** Decompose by the design decisions most likely to change, and hide each behind an interface so no client can couple to it. A boundary everyone reaches through is not a boundary.

Measured 2026-08-15: 890 `cadr-ai::` double-colon references across 98 files under `src/`, covering 64 distinct internal symbols (review counted 796 lines / 63 symbols; the discrepancy is counting method, the conclusion is identical). In CL, `::` is the compiler-visible declaration "I depend on your internals." The export list is therefore not the real API surface — the real surface is whatever 98 client files happen to grab. Parnas's prediction follows mechanically: any internal refactor in `cadr-ai` is a breaking change with 890 call sites, so internals will ossify and the package gets refactored *around*, never *through*.

The same failure repeats at function scale. `run-tui` (`src/cadr-cli/interactive/controller.lisp:217`, spanning to EOF `:2875` — 2659 lines, ~70 `labels` functions sharing 30+ mutable variables) has no information hiding inside it, so the knowledge "which overlay type dispatches to which handler" cannot be localized and instead appears twice: `controller.lisp:2441-2499` (event dispatch, 15 overlay branches) and `:2726-2775` (raw-input dispatch, 8 branches with extra guards). Not verbatim duplicates — worse: two hand-maintained projections of one decision, free to drift apart. That is the Parnas violation's interest payment.

Fairness requires the counterpoint: where boundaries were designed, they hold. `cadr-core`, the 508-line cbor codec behind a small interface, and the provider generic-function layer are genuinely deep modules (the review's own praise). The erosion is concentrated in `cadr-ai`'s internals — localized, and therefore containable by a ratchet.

Recommendation: a mechanical ratchet gate — the count of `cadr-ai::` references outside `cadr-ai` may only decrease; the current count lives in a committed budget file; adding a new internal symbol to the leak requires an explicit export decision (`::` → `:`). This is a grep-and-compare script plus one CI step, and it converts "clean this up someday" into monotonic progress. Every ratchet-driven conversion is also a forced answer to the question that was never asked: is this symbol part of the API or not? [needs adjudication]

## 3. Hoare — two ways of constructing a design (1980)

**C.A.R. Hoare, 1980 ACM Turing Award lecture, published as "The Emperor's Old Clothes", CACM 24(2), 1981.** "There are two ways of constructing a software design: one way is to make it so simple that there are obviously no deficiencies, and the other way is to make it so complicated that there are no obvious deficiencies. The first method is far more difficult."

`scripts/verify.sh` is a 24-stage deterministic pipeline, and three facts say it is sliding toward Hoare's second kind. (a) The CI workflow was last touched 2026-08-01 and, per the review, has not run since — for two weeks nobody noticed, which means the full gate is too heavy to run habitually; a gate nobody can afford to run provides confidence of exactly the illusory kind. (b) The gate is not even read-only: `verify.sh:144` passes `--ledger docs/performance.md`, so every validation mutates a tracked document → dirty tree → trailing bookkeeping commit → history noise, and verification is coupled to repository churn. (c) The gate's own wall-clock cost is unrecorded, so stage additions never face a budget — a complexity meter with no meter.

The first kind of confidence stays available only if gates remain individually comprehensible: one stage, one script, one question, one artifact. Composability is not an aesthetic preference; it is what lets a failing stage be read as an answer instead of a riddle.

Recommendations:

- Record verify.sh's own duration as a first-class metric in the ledger it already writes; the gate's cost is project data, not noise. [needs adjudication]
- Split the pipeline into a fast core (minutes, run on every change) and the full 24 stages (nightly/CI), with the core explicitly enumerated. Gates stay simple and composable or they join the second kind. [needs adjudication]
- Make the ledger write opt-in (`--record`) so verification is read-only by default and the bookkeeping commits disappear. [needs adjudication]

## 4. Brooks — essence, accident, and the second system (1975/1986)

**Fred Brooks, *The Mythical Man-Month* (1975) and "No Silver Bullet — Essence and Accident in Software Engineering" (IFIP 1986; IEEE Computer 20(4), April 1987).** Most historical productivity gains came from removing *accidental* complexity, not essential complexity — so the highest-leverage work is identifying which complexity was never intrinsic. Two companion warnings: the second-system effect (the successor to a successful simple system gets over-designed), and "plan to throw one away; you will, anyhow" — the first version is a prototype whether or not you meant it to be.

Part K (Lisp burn-down) is accident removal by definition: transcription scaffolding — shims, dual-implementation seams, the ~1,364 `getf`-as-JS-object lines (review) — is complexity that exists only because cadr began as a port. Affirm it, and affirm the framing "plan to throw one away" retroactively legitimizes: the direct TS→Lisp transcription *was* the throwaway first system, and Part K is the planned discarding. Under that reading the 2659-line `run-tui` and the 2261-line `cli-handler` (`src/cadr-cli/bootstrap/commands.lisp:291` to EOF `:2551`) are scheduled waste, not failure — *provided the discard actually happens* and the throwaway is not allowed to harden into the permanent system. Hardening is the real danger: 293 production files now carry transcription-era idioms, and every month Part K slips, those idioms acquire more dependents.

The second live risk is the second-system effect: burn-down invites gilding. Watch list: new abstraction layers "for the Lisp-native future," generalization beyond pi's feature set, configurability pi never had. Each may be valuable; none is burn-down. The existing policy — any divergence must first land equal-strength assertions locking the pi baseline — is exactly the right brake and should be extended explicitly to burn-down work.

Recommendation: define burn-down changes as deletion-dominant — net-negative LOC, no new capabilities, behavior changes only under pre-locked assertions; any feature idea discovered mid-burn-down becomes a separate goal item. [needs adjudication] — maps to Part K.

## 5. Hyrum's Law (2012)

**Hyrum Wright, hyrumslaw.com, 2012; popularized by Titus Winters in *Software Engineering at Google* (2020).** "With a sufficient number of users of an API, it does not matter what you promise in the contract: all observable behaviors of your system will be depended on by somebody."

cadr's standing rule — assertions lock only the pi baseline, expectations may never be derived from cadr itself — is precisely Hyrum-hygiene: during transcription, cadr's incidental observable behavior is forbidden from self-ratifying into contract. That rule earns its keep; without it every transcription artifact (getf shapes, Lisp-specific error text, hash iteration order) would have become load-bearing by now. There is a quiet corollary on the other side: every assertion locking the baseline is a contract on *pi's* observable quirks, so the pinned pi commit must stay immutable — it is the sole witness that keeps the contract set from being rewritten by the system under test.

The inversion arrives with Part K: once cadr is the only implementation, every behavior it observably emits — output ordering, streaming cadence, error text — becomes contract-by-observation, whether or not a ledger records it. P0-4 is the canonical instance, and worth a one-line trace: user submits prompt → agent turn runs → pi emits streaming deltas throughout → cadr emits nothing until turn end. Observable, depended upon, and locked by no gate — the fifth green-gates/real-terminal escape. The behavior users depend on has a *time dimension* the diff gates never sample.

Recommendations:

- Extend render-diff with deadline assertions (bytes-within-T during a scripted turn). This reuses existing machinery — PTY byte streams plus tmux semantic screens already diff cross-implementation output; it adds a time axis, not a new tool — and moves the time dimension into the locked contract deliberately. [needs adjudication]
- Post-burn-down, every newly locked behavior gets a behavior-ledger entry as an *intentional* contract; the ledger should be the exhaustive list of what Hyrum's Law is allowed to bind.

## 6. Gabriel — "Worse is Better" (1991)

**Richard P. Gabriel, "Lisp: Good News, Bad News, How to Win Big", AI Expert, 1991 (circulated from 1989).** The New Jersey style — implementation simplicity first, early availability, incremental correctness — out-survives the MIT style ("the right thing": completeness, correctness, consistency before release), because the worse system ships, accrues users, and improves under feedback while the right system is still being finished.

cadr is unabashedly MIT: full behavioral parity with a pinned pi commit before any release, in the lineage of the CADR Lisp Machine the project is named for. The historical irony is sharp enough to state: the namesake machine was itself a Right Thing that lost the market to worse-is-better Unix and C — the name is a memento of how that story ends. Gabriel's predicted cost is already visible on the balance sheet: 0.2.0 remains untagged, time-to-value is deferred until goal completeness, and the project forgoes the user-feedback loop that is the New Jersey style's actual engine. Note that none of the project's three genuine assets (ledgers, gates, parity discipline) requires withholding releases; the coupling between "goal complete" and "may tag" is a policy choice, not a technical constraint.

Recommendation: decouple release cadence from goal completeness — tag rolling releases on a schedule, with parity percentages and benchmark deltas published as data attached to each release rather than as preconditions for it. This keeps the Right Thing internally while buying Worse-is-Better's one real advantage externally: feedback from real use. [needs adjudication]

## 7. Dijkstra — testing shows presence, not absence (1972)

**Edsger Dijkstra, 1972 ACM Turing Award lecture, "The Humble Programmer", CACM 15(10), 1972.** "Program testing can be a very effective way to show the presence of bugs, but is hopelessly inadequate for showing their absence."

For this section the point is governance-level: P0-4-class liveness defects are the *inherent limit* of checkpoint gates, not a gate failure — the tests sampled the state space and the defect lived in the time dimension they never sampled. A green verify run must therefore be reported as "no defects found in the sampled space," never as "no deficiencies"; conflating the two is how a 24-stage pipeline buys Hoare's second kind of confidence while believing it has the first. The verification-theory section carries the analysis; the philosophy section flags the vocabulary, because the vocabulary is what the governance loop reads.

## 8. Ousterhout — deep modules, errors designed away (2018)

**John Ousterhout, *A Philosophy of Software Design* (2018): modules should be deep — small interface, large capability (chapter 4); and the best error handling is to "define errors out of existence" — design so the exceptional case cannot occur, instead of throwing and catching more elaborately (chapter 10).**

CL gives cadr the best define-errors-away machinery in any mainstream language — restarts, which let low-level code offer recovery strategies while high-level code picks the policy — and the project barely uses it: `restart-case` appears exactly once in all of `src/` (`src/cadr-agent/loop/tool-execution.lisp`; review counts 7 repo-wide). The condition system is used as throw/catch only. Worse, the throw side is undisciplined: 188 untyped `(error "...")` sites across 62 files (verified, matching the review) bypass the `cadr-error` hierarchy, and `src/cadr-ai/json.lisp:364-373` makes the taxonomy actively lie — the *general* JSON entry point re-signals every `json-parse-error` as `sse-protocol-error`, so a malformed config file and a malformed provider payload become indistinguishable at the handler. The 117 `ignore-errors` sites (review) complete the picture: errors are neither designed away nor handled, but swallowed.

Contrast with what depth looks like when done: the 508-line cbor codec sits behind a small generic-function interface — that is a deep module. The 551-line `json.lisp` whose front door mislabels its own error type shows depth is not line count but honest contracts. The same absence of designed protocols is what the real concurrency bug exploits: `src/cadr-ai/websocket.lisp:218-226` and `:394-419` mutate shared debug stats outside the mutex the reader (`:228-235`) holds — a defect that an ownership protocol (who may mutate stats, under what discipline) would have made structurally impossible. Nearby, `read-websocket-frame` (`:165-191`) ignores the FIN bit and `websocket-url-as-http-url` (`:279-285`) is an identity function in both branches — small undefined-away corners accumulating in the same module.

Recommendations:

- Ratchet the 188 untyped errors into the `cadr-error` hierarchy (count may only decrease); fix the json→sse mislabel first since it corrupts triage. [needs adjudication]
- Audit the 117 `ignore-errors` for swallowed domain conditions.
- Add restarts where a caller can meaningfully resume — e.g. the session codec offers `use-value`/`skip-record`, the interactive layer prompts, the batch layer aborts: one condition, policy decided at the right layer, no signaling spaghetti.

## 9. Knuth — premature optimization (1974)

**Donald Knuth, "Structured Programming with go to Statements", ACM Computing Surveys 6(4), 1974.** "We should forget about small efficiencies, say about 97% of the time: premature optimization is the root of all evil."

cadr's performance policy is the correct institutional answer to Knuth: no ceiling, floor = pi baseline, paired benchmarks decide. That names the 3% in advance — `journal_append` 7.67×, `journal_read` 4.29×, `session_load` 3.70× behind pi (Part O targets) — and forbids speculative tuning where headroom says there is nothing to win (cold-start 4.85× margin, frame-allocation 23.3× margin: leave them alone). The margins list is the "97%" written down, which is rarer and more valuable than it sounds: it is the project's defense against its own enthusiasm, and the pairing discipline (same workload, both implementations) is the anti-rationalization device that keeps a 7.67× gap from being explained away.

One discipline addition: profile before optimizing — no performance change lands without an `sb-sprof` capture showing the target in the hot path, and each Part O item files its capture in the ledger next to the paired-benchmark delta, so "why this optimization" stays answerable later (Naur's theory, one loop up). Profiling is also how the actually-embarrassing problem gets found: the O(n²) per-token full-string `concatenate` in the streaming accumulators (verified at `src/cadr-ai/providers/anthropic.lisp:528` and `:559`; review adds `openai.lisp:581,627`, `google.lisp:339`, `bedrock.lisp:705,726`, plus per-chunk append at `bedrock.lisp:679-682`). Knuth's rule cuts both ways — it also forbids *not* measuring.

## Cross-references

- §2's god-function and package-boundary evidence feeds the codebase-structure section (decomposition plan for `run-tui` / `cli-handler`).
- §5's time-dimension gap and §7's sampling caveat are developed in the verification-theory section.
- §9's O(n²) accumulation and Part O targets are developed in the algorithms/performance section.
- §1's adjudication-log and §3's gate-cost recommendations converge in the governance section's policy amendments.
- §6's release-cadence recommendation and §4's burn-down scope rule jointly define the post-goal20 operating mode: what ships, and when.

## Section Top 3 (impact × cost)

1. **Commit the adjudication log** (Naur, §1): near-zero cost; eliminates the project's single point of theory loss — an 89.7 KB gitignored file currently carrying the entire goal20 ruling history. [needs adjudication]
2. **Mechanical ratchet on `cadr-ai::` leakage** (Parnas, §2): a grep-and-compare gate plus a committed budget file; halts boundary erosion today (890 lines / 98 files / 64 symbols) and makes a real export list reachable. [needs adjudication]
3. **Split and meter the gate** (Hoare, §3): record verify.sh wall-clock, make the ledger write opt-in, extract a fast core, and get CI running again — the two-week silent CI lapse is the costliest unmeasured signal in the project. [needs adjudication]
