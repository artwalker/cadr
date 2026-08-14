# 02 — Classic Software Engineering Methodology

Seven canonical methodology sources mapped onto cadr's governance, gates, and
codebase, ordered by relevance to goal20. Evidence base: the 2026-08-14
external review (`docs/reviews/2026-08-14-external-review.md`), plus spot
re-measurement on 2026-08-14 (defun lengths via `grep -n "^(defun"` + scan
for the next top-level form; byte counts via `wc -c`). One path correction
against the review: the websocket defects live in `src/cadr-ai/websocket.lisp`;
there is no `src/cadr-ai/providers/codex/` tree.

## 1. Characterization tests and seams — Feathers, *Working Effectively with Legacy Code* (2004)

Thesis: legacy code is code without tests. Before changing it, find seams —
"a place where you can alter behavior in your program without editing in that
place" (ch. 4, "The Seam Model") — and write characterization tests that pin
*current* behavior, not intended behavior. Only then change the code.

cadr mapping: the pi baseline locked at commit `53fa77cc` (`BASELINE`) is
legacy code in Feathers' literal sense. The inviolable rule "structure may
diverge only when equal-strength behavioral assertions land first, locked to
the baseline" is Feathers' change protocol stated as policy, and "assertions
reverse-engineered from cadr are void" is his characterization discipline:
pin the *reference's* behavior, never the code under change — the thirteen
green full-screen SHAs that locked the wrong vertical alignment are the
failure mode this exists to prevent. `scripts/render-diff.py` (PTY bytes plus
tmux semantic screen) is the terminal-boundary seam, with the scenario
manifest and dispositions as enabling point; verify.sh's 24 deterministic
stages are the characterization harness.

Evidence of a coverage hole — an uncharacterized behavior region in Feathers'
terms: five times gates were green while the user's real terminal showed a
defect (latest P0-4: no cadr output for long stretches of an agent turn
while pi displays activity throughout). The suite pins static checkpoints,
not the time axis of interaction. The target shape is his "monster method"
chapter (ch. 22) verbatim: `run-tui` is one 2659-line defun
(`src/cadr-cli/interactive/controller.lisp:217`, to EOF at line 2875) with
~90 `&key` parameters and ~70 local functions; `cli-handler` is one
2261-line defun (`src/cadr-cli/bootstrap/commands.lisp:291`, to EOF at 2551);
the same overlay-selector dispatch chain appears in both `handle-event` and
`handle-raw-input` (`src/cadr-cli/interactive/controller.lisp:2441-2499` and
`:2726-2775`).

Recommendation: (a) name the divergence rule explicitly as Feathers semantics
("characterization-first") in `docs/development-policy.md`, so contributors
can read the method behind the rule [needs adjudication — policy text];
(b) in Part K, land a per-target characterization checklist *before* touching
each refactor target — pinned behaviors explicitly including streaming and
timing, to close the P0-4 defect class; (c) treat the twin dispatch chains as
the first extraction seam when `run-tui` is broken up. Maps to Part K.

## 2. Two hats and small steps — Fowler, *Refactoring* (2nd ed. 2018, ch. 2)

Thesis: Kent Beck's two-hats metaphor, as Fowler presents it — adding
function and refactoring are distinct activities; swap hats deliberately,
never wear both at once; refactor in small steps, tests green between steps.

cadr mapping: the policy "do not mix unrelated style rewrites into a
functional change" (AGENTS.md, inviolable rules) is already hat separation.

Evidence: the O(n²) streaming accumulation is a textbook Substitute Algorithm
refactoring — behavior-preserving, no golden changes: full-string
`concatenate` per token at `src/cadr-ai/providers/anthropic.lisp:528,559`
(re-verification adds `:537` and `:546`), `openai.lisp:581,627`,
`google.lisp:339`, `bedrock.lisp:705,726`, plus per-chunk append at
`bedrock.lisp:679-682` (same directory). Swapping the accumulator for an
adjustable buffer touches no observable behavior and serves the performance
policy directly (floor = pi baseline). Extract Function applies to
`run-tui`'s ~70 local functions; Consolidate Duplicate Conditional Fragments
applies to the twin dispatch chains of item 1.

Recommendation: execute Part K as a per-file *series* of small
behavior-preserving commits — one refactoring pattern per commit, the item-1
characterization checklist as the first commit of each series. Needs no
policy change; it is an execution-mode instruction for the goal file [needs
adjudication if it amends goal20 text]. Maps to Part K; the accumulator fix
also feeds Part O.

## 3. "If it hurts, do it more frequently" — Fowler, *Continuous Integration* (martinfowler.com, 2006)

Thesis: integrate at least daily; painful processes should be done *more*
often — automated, deterministic, pain brought forward — not batched.

Evidence: CI (`.github/workflows/ci.yml`) has not run since 2026-08-01
(review finding) — a direct violation. `scripts/verify.sh` is deterministic
but runs as an occasional heavy batch; it is not read-only — a stage passes
`--ledger docs/performance.md` (`scripts/verify.sh:144`) and rewrites the
ledger, producing trailing bookkeeping commits that further discourage
frequent runs; verify's wall-clock cost is unrecorded, so the batching pain
is not even measured. The predicted rot followed: 108 of 1,052 cadr-side
file:line mappings in `docs/source-parity.md` are dead because the drift
checker never checks cadr-side file existence, and line-number drift has no
guard at all — exactly what CI exists to surface within hours.

Recommendation: (a) restore CI running the deterministic subset of
verify.sh's 24 stages [needs adjudication — changes gate operation];
(b) split verify.sh into a read-only verify mode and an explicit "harvest"
mode that updates `docs/performance.md`, so the common path leaves no
trailing commits [needs adjudication]; (c) record verify wall-clock in
`docs/performance.md` — it is non-functional data and belongs in that ledger;
(d) add the cadr-side existence check to the drift checker — a small script
fix that maps to Part F (ledger mapping repair).

## 4. Stability patterns — Nygard, *Release It!* (2nd ed. 2018)

Thesis: production systems die at integration points; contain failure with
Timeouts, Circuit Breaker, Bulkheads, and Let It Crash.

cadr mapping: the 10-hour stable run and the supervisor are the strengths
(Let It Crash done right). The anti-patterns sit where Nygard looks — at the
Codex websocket integration point (`src/cadr-ai/websocket.lisp`):
`read-websocket-frame` (:165-191) never checks the FIN bit, so fragmented
frames are silently mis-parsed (re-verified 2026-08-14). Debug stats are
mutated outside the
lock (`increment-codex-stat`/`set-codex-stat` :218-226, called from
`record-codex-request-stats` :394-419) while the reader takes
`*codex-websocket-cache-lock*` (:229-235): the lock covers only half the
protocol. `websocket-url-as-http-url` (:279-285) returns its input unchanged
on both branches — dead code at the connection seam. Error-taxonomy
flattening defeats the prerequisite for any circuit breaker: 188 untyped
`(error "...")` calls bypass the `cadr-error` hierarchy; `parse-json`
(`src/cadr-ai/json.lisp:364-373`) re-signals `json-parse-error` as
`sse-protocol-error`, mislabeling a local data defect as a transport defect;
`ignore-errors` ~117 times against `restart-case` ~7. A breaker can only trip
on failures it can classify.

Recommendation: audit all 9 providers for timeout/retry/cancellation/frame
handling consistency before Part K burns them down further (or as K's first
pass over the provider layer); migrate integration-point errors onto the
`cadr-error` hierarchy *before* adding any breaker logic — classification
precedes tripping. The taxonomy migration changes signaled conditions and is
behavior-visible [needs adjudication]. Maps to Part K (provider burn-down),
with parity risk controlled by item 1's checklists.

## 5. Design by Contract — Meyer, *Object-Oriented Software Construction* (1988; 2nd ed. 1997)

Thesis: correctness is specified as preconditions, postconditions, and
invariants at component boundaries; the contract is part of the interface and
is checked mechanically.

cadr mapping: provider and tool payloads are plists used as JS objects —
`getf` on ~1,364 lines — with no stated shape anywhere; `cadr-ai::` internal
symbols are referenced outside the package on 796 lines across 63 symbols.
Boundaries exist by convention only, so shape errors surface far from their
origin (the item-4 websocket stats are such plists, mutated piecemeal at
`src/cadr-ai/websocket.lisp:218-226,394-419`). The CL equivalent of Eiffel
contracts is defstruct/standard-class with typed slots plus assertion macros
at entry points; this mechanizes part of the project's "honesty obligations":
latent plist shape bugs become immediate contract violations at the boundary
that owns them.

Recommendation: run a Part K pilot in one package — defstruct field contracts
for provider request/response payloads plus a small assertion macro for
pre/postconditions at provider entry points; measure the caught-defect rate
before any wider rollout. This changes interface conventions and the
organization ledger's accounting [needs adjudication]. Maps to Part K.

## 6. TDD's applicability boundary — Beck, *Test-Driven Development: By Example* (2002)

Thesis: red-green-refactor; writing the test first drives the design.

Boundary: parity work is golden-driven — the pi baseline *is* the
specification, so the test exists before the code, but as a
characterization/golden test, not a design driver; forcing TDD there would be
theater. Part K's new Lisp-native code is the opposite case: admitted only
with a "checkable benefit," it has no golden to lean on, so test-first is the
correct discipline — and the checkable benefit itself should be expressed as
the first failing assertion. Supporting evidence: dead tautological
assertions (`test/cadr-cli/goal20-part-l-test.lisp:62-65`, over a nil list)
keep FiveAM green while pinning nothing.

Recommendation: write the two-tier strategy into policy — parity code:
characterization/golden first (Feathers); new Lisp-native code: test-first
(Beck), benefit stated as a failing test [needs adjudication — policy text].
Flag the dead assertions for repair or removal (repo rule: ask before
removing intentional-looking code).

## 7. Lean development — Poppendieck & Poppendieck, *Lean Software Development* (2003)

Thesis: amplify learning, decide as late as possible, deliver as fast as
possible.

Evaluation of goal-serial governance (L→M→N→…→K): serialization is
decide-late by construction — each goal re-plans against fresh parity state,
and durable adjudications accrete in `goal20-state.md` (89,712 bytes,
measured 2026-08-14 via `wc -c`; gitignored by `.gitignore:28`, `/goal*.md`)
instead of being specified upfront. That is lean in the Poppendieck sense and
matches one-executor-plus-advisor capacity; do not parallelize goals. The
costs: cross-goal concerns starve between goals — the CI lapse ran two weeks
unnoticed because no goal owns operations hygiene, and performance waits for
Part O while `journal_append` trails pi by 7.67×, `journal_read` by 4.29×,
`session_load` by 3.70×, even where Part K already touches adjacent code.
Separately, the advisor-proxy-plus-user-veto convention is de facto but
unwritten — `docs/development-policy.md` §5.5 still requires user
adjudication — and a decision mechanism that has drifted from its own
documentation cannot be improved, because its actual rules are written down
nowhere.

Recommendation: (a) keep serial goals; (b) add a standing operations lane —
CI health, drift-checker integrity, verify wall-clock — outside goal
serialization [needs adjudication]; (c) codify advisor-proxy with explicit
user veto in §5.5 [needs adjudication]; (d) apply
decide-at-last-responsible-moment per interface rather than per goal: when
Part K reaches the journal/session storage files, decide *then* whether to
pull those perf items into K or hold them for O — the decision is cheap
precisely because it is late.

## Section top 3 (impact × cost)

1. **Restore CI + verify observability + drift-checker existence check**
   (item 3). Days of work; would have caught the 108-mapping rot and the CI
   lapse itself within hours. Maps to Part F.
2. **Name and operationalize characterization-first for Part K** (items 1–2):
   per-file checklists that include streaming/time-axis behaviors, executed as
   small behavior-preserving commit series. Medium cost; targets the repeated
   gate-green defect class and de-risks the monster-defun burn-down.
3. **Provider integration-point audit before further provider burn-down**
   (item 4): FIN/timeout/retry/lock coverage across all 9 providers, with
   typed-error migration first. Medium cost; removes confirmed live bugs
   (`src/cadr-ai/websocket.lisp:165-191,218-226`) and enables later
   Nygard-style resilience work.
