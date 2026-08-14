# 03 — Verification and Testing Theory

cadr's verification stack is unusually heavy for a reimplementation project: ~17k FiveAM cases
(`scripts/test-cl.sh`), a 24-stage deterministic pipeline (`scripts/verify.sh`), and a
cross-implementation render differential (`scripts/render-diff.py`: PTY byte capture + tmux
semantic-screen replay against pi pinned at `BASELINE`). Eight classical testing-theory lenses
follow, ordered by relevance to cadr, one actionable recommendation each. All file:line references
were re-verified against the working tree on 2026-08-14.

## 3.1 The oracle problem: cadr owns a rare, high-quality oracle — protect it, and admit its failure mode

**Barr, Harman, McMinn, Shahbaz & Yoo, "The Oracle Problem in Software Testing: A Survey," IEEE TSE 41(5) (2015).**
Testing splits into generating inputs and deciding correctness (the oracle problem). The strongest
automatable oracle the survey classifies is the *pseudo-oracle* — an independent implementation
whose output defines correctness — and such oracles are rare because independent implementations
seldom exist.

cadr is that rare case. pi, pinned at commit `53fa77ccd` (`BASELINE`), is a complete, executable
specification: render-diff drives both binaries through identical scripted PTY sessions
(`test/fixtures/render-diff/scenarios.json`), replays both byte streams through tmux, and
classifies every checkpoint as raw-equal / `screenEqual` / `requires-disposition`
(`AGENTS.md:115-138`). This converts "is this screen correct?" — a judgement call — into "is it
identical to the baseline?" — a mechanical one. It is the project's single most valuable
verification asset: the ledgers and FiveAM suite are locally checkable, but only the differential
anchors semantics to an external truth (core tier EXIT:0 at 120/122, `goal20-state.md:131`).

The shared failure mode of pseudo-oracles is *correlated error*: both sides wrong together. cadr
has self-diagnosed this — `AGENTS.md:110-113`: "Screens that match each other can still both be
wrong if the goldens were taken from a defective cadr." Two aggravating specifics: the oracle is
pinned, so baseline bugs get faithfully locked in as features; and the oracle only sees what
scenarios drive — all five user-discovered real-terminal defects (§3.5, §3.6) escaped it.

**Recommendation.** Keep an independent human acceptance channel as a permanent, planned stage
whose expectations never derive from cadr output (§3.5), and extend the differential below the
terminal: provider SSE parsers, journal append/read, and session export can be differentially
exercised against captured pi fixtures without a PTY (identical input bytes, diff the event/item
sequences) — cheap, deterministic, widening oracle coverage below the render gate. Adopting these
as verify.sh stages is a gate change: [needs adjudication].

## 3.2 Golden masters capture behavior — including wrong behavior

**Feathers, "Working Effectively with Legacy Code" (2004) — characterization tests; the approval/golden-master lineage.**
A golden master records what the system *did*, not what it *should do*. Whoever takes the snapshot
is the oracle; a snapshot of defective output freezes the defect and grants it a green badge.

cadr has the canonical incident on record: "The project has already shipped thirteen full-screen
SHAs that stayed green while locking the wrong vertical alignment" (`AGENTS.md:148-151`). The
mechanism repeated at finer grain: the `example-snake` dispositions waved through 119 visible
character differences (`m SNAKE`, a stray `m` per grid point) while claiming the board matched the
baseline contract (`goal20-state.md:1127-1135`). Two distinct weaknesses: (a) goldens taken from
defective cadr output, and (b) dispositions written to make the gate pass rather than to describe
a verified difference. cadr already has one mechanical self-falsification check — identical
`screenSha256` pair + non-I01 class is "mechanically false" (`AGENTS.md:136-138`).

**Recommendation.** Institute periodic human audit of goldens and dispositions: at each Part
close-out, sample N checkpoint entries, re-derive the expected screen from the *baseline* (never
from current cadr output), and eyeball the rendered checkpoint in a real terminal; record audit
yield (mis-locked SHAs per sample) in the close-out note. This adds a recurring human-judgement
exit, which policy §5 requires to be checkable (`docs/development-policy.md:231`):
[needs adjudication]. Adjacent ledger-hygiene repair belongs to goal20 Part F.

## 3.3 Property-based testing for the three hand-written codecs

**Claessen & Hughes, "QuickCheck: A Lightweight Tool for Random Testing of Haskell Programs," ICFP (2000).**
State properties instead of enumerating examples; let a generator search the input space for
counterexamples and shrink them. The highest-leverage target is an encoder/decoder pair:
`decode ∘ encode = id` plus "never signal outside the declared condition hierarchy" covers input
regions no author enumerates by hand.

cadr hand-implements three wire codecs: `src/cadr-ai/json.lisp` (551 lines),
`src/cadr-protocol/cbor.lisp` (508 lines), `src/cadr-ai/websocket.lisp` (582 lines). The
example-based suite missed real defects there: `read-websocket-frame` (`websocket.lisp:165-191`)
computes the opcode as `(logand first #x0f)` at `:171` and silently drops the FIN bit, so
fragmented frames are never detected; `parse-json` (`json.lisp:364-373`) re-signals any
`json-parse-error` as `sse-protocol-error`, mislabeling the failure class for every consumer of
the condition hierarchy. The same files carry the known O(n²) per-token `concatenate` accumulation
(`anthropic.lisp:527-530,556-559`; `openai.lisp:581,627`; `google.lisp:339`;
`bedrock.lisp:679-682,705,726`) — a round-trip property over long token streams would turn that
into a measurable, shrinking counterexample search.

**Recommendation.** Add FiveAM-embedded property tests: JSON round-trip (deep nesting, escapes,
surrogate pairs, `-0.0`, large integers), CBOR round-trip for the actually-used tags, WebSocket
frame round-trip *including fragmentation flags*, and a robustness property — random
truncations/bit-flips of valid frames must signal only conditions from the declared hierarchy
(directly kills the `json.lisp:364-373` mislabeling class). Log the `*random-state*` seed per run
so failures replay inside the deterministic pipeline. CL's `check-it` (DalekBaldwin) is the
QuickCheck-style library and embeds into any framework, but new dependencies require prior review
(`docs/development-policy.md:214`). The no-new-dependency path — a ~150-line seeded generator
harness inside the existing FiveAM systems — comes first. [needs adjudication only if `check-it`
or any new dependency is adopted.] Maps to Part K: generative testing of pure-Lisp components is
exactly the "checkable benefit" Lisp-native work must show (`docs/development-policy.md:9`).

## 3.4 Metamorphic testing for transforms with no direct oracle

**Chen, Cheung & Yiu, "Metamorphic Testing: A New Approach for Generating Next Test Cases," HKUST-CS98-01 (1998)** (motivated by Weyuker's non-testable programs, "On Testing Non-Testable Programs," The Computer Journal 25(4), 1982).
When no oracle exists for a single execution, assert *metamorphic relations*: necessary properties
of the *relation between* outputs of related inputs — consistency across runs replaces per-run
correctness.

Several cadr transforms sit outside the render oracle's reach: session → HTML export
(`src/cadr-agent/session/export-html.lisp`, compared against pi only by hand) and the
journal/session persistence paths — also the Part O performance laggards (`journal_append` 7.67×,
`journal_read` 4.29×, `session_load` 3.70× behind pi, `goal20-state.md:421`). Cheap relations are
already implicit: *information conservation* — every user/assistant/tool message in the session
JSONL appears exactly once in the exported HTML, modulo declared elisions; *batch-boundary
invariance* — appending N entries in one call vs. N calls yields identical reads (exercises
`journal_append`/`journal_read` correctness independently of their speed); *perturbation
invariance* — `session_load` returns equal content under whitespace-only JSONL perturbations.

**Recommendation.** Land these as ordinary FiveAM tests now (no gate or policy change); they give
Part O's performance rewrites a correctness net example tests cannot, because the relations hold
for *all* inputs. Promoting a metamorphic suite into verify.sh as a named stage:
[needs adjudication].

## 3.5 Exploratory testing: the user's five discoveries are a process yield, not accidents

**Kaner, "Testing Computer Software" (1988, coined the term) and the 2006 Exploratory Testing Research Summit consensus definition.**
Exploratory testing is simultaneous learning, test design, and test execution — a style that
emphasizes the tester's freedom and responsibility to continually optimize the value of the work.
Scripted tests check only what was anticipated; the highest-value defects live elsewhere.

goal20's record is a clean demonstration: all five real-terminal defects were found by the user
playing with the product, not by any gate — P0-2 (tic-tac-toe overlay never repaints during agent
play; fourth discovery, `goal20-state.md:1021`) and P0-4 (cadr shows nothing during an entire
agent turn while pi shows the whole process; fifth discovery, `goal20-state.md:853`). Each was
processed as a gate embarrassment ("why didn't 17,026 checks catch any?", `goal20-state.md:958`)
when it was actually the most productive testing channel the project has. The bundled game
extensions (snake, tic-tac-toe, space-invaders) are exactly the interactive, stateful,
time-dependent surface where exploration dominates scripting.

**Recommendation.** Formalize a structured exploratory-testing charter as a required step before
each Part close-out: time-boxed (~45 min), chartered (e.g. "drive one full agent session per
bundled game; resize the terminal mid-turn; interrupt mid-stream"), findings filed as P0 entries,
each converted into either a new scripted assertion or an explicitly declared oracle-free zone.
This reclassifies user discoveries from gate-failure accidents into expected charter yield. It
adds a human-judgement exit to Part acceptance, which policy §5 requires to be checkable
(`docs/development-policy.md:231`): [needs adjudication].

## 3.6 Liveness: the time dimension the checkpoint oracle cannot see

**Alpern & Schneider, "Defining Liveness," Information Processing Letters 21(4) (1985).**
Safety properties say nothing bad happens; liveness properties say something good eventually
happens. Snapshot-based checking can only express safety — a system that goes silent is perfectly
safe and completely broken.

P0-4 is a liveness failure invisible to a safety-only gate: during an agent turn cadr emitted no
output for a long window while pi displayed the process throughout (`goal20-state.md:853`); no
screen was ever *wrong*, the screens were *absent*. The render-diff checkpoints are user-keystroke
driven static slices (`ttt-initial`/`ttt-cursor`/`ttt-played`, `goal20-state.md:1067`); the PTY
capture records the full byte stream, but assertions evaluate only slice content, never
inter-arrival gaps.

**Recommendation.** Timestamp the PTY capture (record `(time, bytes)` tuples) and add a liveness
assertion class: "within any N-second window of an agent turn, cadr emits some output" — N derived
from the baseline's observed worst-case gap times a margin, locked to pi exactly like the project's
other assertions (`AGENTS.md:148-150`). The capture infrastructure already exists; only the
analysis is new. This is a new assertion category, which changes what the gate promises
(`docs/development-policy.md:261-263`): [needs adjudication].

## 3.7 Mutation thinking: an assertion that cannot fail is not a test

**DeMillo, Lipton & Sayward, "Hints on Test Data Selection: Help for the Practicing Programmer," IEEE Computer 11(4) (1978).**
Mutation testing: seed a fault, and require the suite to kill it. A suite's value is measured by
the faults it detects, not the assertions it counts. Applied to assertions themselves: one that
survives any implementation is dead weight inflating the green count.

cadr has evidence on both sides. Residue: `test/cadr-cli/goal20-part-l-test.lisp:61-66` asserts
`(null lines)` and then asserts a string search over that same null list finds nothing — the
second assertion is unfalsifiable. P0-3 swept 68 `(search … source)` assertions after the
three-layer coverage miss (`goal20-state.md:958,922`), yet the tautology above survived —
example-based review cannot prove an assertion is killable. Positive precedent: the P0-1
regression lock explicitly rejects the defective shape while the P0-2/P0-3 behavior tests lack
that proof (`goal20-state.md:946`) — cadr applies killability case-by-case, not systematically.

**Recommendation.** Sampled mutation audit, no tooling required: for the highest-stakes test files
(`test/cadr-cli/test/suite/regressions/`, `goal20-part-*-test.lisp`), pick K assertions per file,
break the implementation in the asserted way, and require the assertion to go red; record the kill
rate in the Part close-out note. This generalizes an already-adjudicated practice
(`goal20-state.md:946`), so the audit itself needs no policy change; making kill-rate a standing
gate obligation: [needs adjudication]. Natural home: Part K.

## 3.8 Flaky-test governance: split deterministic from statistical gates

**Luo, Hariri, Eloussi & Marinov, "An Empirical Analysis of Flaky Tests," FSE (2014).**
Flaky tests corrode the trust that makes a suite useful: developers learn to re-run instead of
investigate, and chronic false alarms pressure teams into loosening assertions — the most damaging
long-term outcome.

cadr exhibits both canonical flakiness sources. Live-model nondeterminism: a live-suite red that
passed 7/7 on rerun (`goal20-state.md:131`), and a `LIVE-DEEPSEEK` run hitting the 100-turn cap
(`goal20-state.md:1478`). Timing-band flakiness: `cold_start.median_us` was set fail-closed
against the wrong population and would false-red a normal verify until reclassified as
informational (`goal20-state.md:563-595`). The project already articulated the corrosion mechanism
itself: false reds force matcher loosening, "that is the recurrence path of this hole"
(`goal20-state.md:257`). Structural aggravators: CI (`.github/workflows/ci.yml`) has not run since
2026-08-01, removing the repeated-run signal flakiness analysis needs; verify.sh wall-clock is
unrecorded; and `scripts/verify.sh:144` rewrites `docs/performance.md` on each run, mixing
measurement into a ledger file.

**Recommendation.** Split the gates into two tiers with explicit contracts. (D) *Deterministic* —
FiveAM, render-diff core, tool/event differentials: must never flake; any flake is a P0 harness
bug. (S) *Statistical* — live-model stages and timing benchmarks: declared as such, each with a
published statistical contract (n, median/MAD — the n≥20 + MAD practice at `goal20-state.md:530`
is the right nucleus), informational by default, fail-closed only on sustained excursion (k of the
last n runs beyond the band). Also record verify.sh wall-clock per run so tier-S drift is
measurable. Reclassifying a gate's obligation unit or denominator is a criteria change under
`docs/development-policy.md:261-263`: [needs adjudication]. Maps to Part O, whose
paired-performance gates are the current flakiness center of mass.

## Top 3 (impact × cost)

1. **§3.3 — Property-based tests for json/cbor/websocket.** Highest density of confirmed latent
   bugs per line in the repo (FIN bit dropped, error mislabeling, lock-free stats), no new
   dependency needed (seeded generator inside FiveAM), directly de-risks Part K. Cost: days.
2. **§3.6 — Liveness assertions on timestamped PTY capture.** The only proposal covering the
   empirically dominant escape channel: 5 of 5 user-found P0s were invisible to static
   checkpoints. Capture infrastructure already exists; only analysis is new. [needs adjudication]
3. **§3.8 — Deterministic/statistical gate split.** Protects the credibility of the entire
   green-signal economy; mostly a classification exercise plus wall-clock recording, but it
   touches gate definitions and ledger conventions. [needs adjudication]
