# Engineering Foundations Report — cadr (2026-08-14)

Author: Kimi Code CLI (external reviewer). Status: **advisory, not
adjudicated**. Nothing here changes a gate, a ledger, or policy by itself;
items that would are marked **[needs adjudication]** and belong in
`docs/proposals/` or `docs/open-questions.md` first.

Companion documents:

- [2026-08-14-external-review.md](2026-08-14-external-review.md) — the raw
  evidence review (process / code / documentation findings) this report
  builds on.
- Chapters: [01 Software Philosophy](sections/01-software-philosophy.md) ·
  [02 Classic Methodology](sections/02-classic-methodology.md) ·
  [03 Verification Theory](sections/03-verification-theory.md) ·
  [04 Team and Process](sections/04-team-and-process.md) ·
  [05 Algorithms and Data Structures](sections/05-algorithms-and-data-structures.md) ·
  [06 Algorithm Hotspots Addendum](sections/06-algorithm-hotspots-addendum.md)
  (externally supplied, re-verified line-by-line 2026-08-15)

## Method

Two passes over HEAD `4c8e31416` on 2026-08-14: (1) an evidence review of
process, code, and documentation; (2) five themed chapters, each mapping
established software-engineering thought onto that evidence. Every claim
carries a `file:line` citation measured that day; recount before quoting
(see `AGENTS.md` "Recounting scale figures").

**Corrections made during drafting** (the chapters use the corrected
figures):

- The codex websocket file is `src/cadr-ai/websocket.lisp`, not
  `src/cadr-ai/providers/codex/websocket.lisp`. All cited line numbers were
  re-verified against the real path.
- The controller's two dispatch sites (`controller.lisp:2441-2499` and
  `2726-2775`) are structurally parallel but already diverged (15-branch
  event dispatch vs 8-branch raw-input dispatch); the fix is a dispatch
  table, not extraction of one copy.
- Ropes are Boehm, Atkinson & Plass, *Software—Practice & Experience*
  25(12), 1995 (not Boehm/Atwood/Ganger).
- Journal performance: the enforced ledger rows (2026-08-14,
  `docs/performance.md:526-529`) are journal_append 1.93×, journal_read
  5.48×, session_load 6.39× behind pi; the 7.67×/4.29×/3.70× figures are
  the informational quick run (`:533`). The append improvement came from a
  `make-random-state` fix — an in-repo proof of profile-first discipline.
- The goal-20 ready queue measured 16 items, not 11.

## Thesis

cadr's verification machinery — a pinned-baseline cross-implementation
oracle, five independent ledgers, executor/advisor review — is genuinely
rare and mostly sound. The chapters converge on three systemic gaps:

1. **The backstop is disconnected and the oracle is blind in one
   dimension.** CI has not run since 2026-08-01; the gates cover static
   checkpoints but not the *time dimension* of interaction (P0-4: no output
   during an agent turn). Dijkstra's limit applies: the user's five
   manual-terminal discoveries are the expected yield of exploratory
   testing, so make that a first-class stage instead of an accident.
2. **The theory is at risk.** In Naur's sense the five ledgers externalize
   the theory of the program unusually well — but rulings with lasting
   force live in a gitignored state file, adjudication results are not
   written back to proposals, and ledger references rot mechanically (108
   of 1,052). The fixes are mostly cheap: commit the rulings, add the
   cadr-side existence check, generate scale figures by script.
3. **The Lisp-ification burn-down is the right main effort, and the order
   matters.** Brooks: the transcription was the prototype you planned to
   throw away; Part K is the second system — keep the checkable-benefit
   rule as the guard against gold-plating. Start where the accidental
   complexity is densest and provable: the two mega-defuns
   (`run-tui` 2,659 lines, `cli-handler` 2,261 lines), the plist payload
   culture, and the O(n²) streaming accumulation that likely violates the
   project's own performance floor.

## Cross-cutting priority list (impact × cost)

Synthesis of the five chapter Top-3s. Part references are goal-20 Parts.

**P0 — high impact, low cost (days):**

| # | Item | Chapter | Mapping |
|---|---|---|---|
| 1 | Restore CI (deterministic stages at minimum); record verify wall-clock | 01/02/04 | — |
| 2 | Add cadr-side existence check to `check-source-parity-drift.sh` | 02 | Part F, [needs adjudication] |
| 3 | Split `verify.sh` into read-only verify + `record` subcommand | 02/04 | — |
| 4 | Fix websocket lock race + FIN-bit handling; delete identity dead code | 05/02 | bug fix, ship now |
| 5 | Commit rulings to tracked files; write adjudications back to proposal Status lines; record "advisor rules, user vetoes" in policy | 01/04 | [needs adjudication] |

**P1 — high impact, medium cost:**

| # | Item | Chapter | Mapping |
|---|---|---|---|
| 6 | O(n²) streaming accumulation → chunk lists; prove with paired benchmarks | 05 | Part O |
| 7 | Liveness assertions: timestamped PTY capture, "output within every N-second window" | 03 | [needs adjudication — new assertion class] |
| 8 | Property-based round-trip tests for the three hand-written codecs (no-new-dependency path first) | 03 | Part K; [needs adjudication] if a dep is added |
| 9 | Package-boundary ratchet gate (`cadr-ai::` external references may only decrease) | 01 | Part K, [needs adjudication] |
| 10 | Feathers-style characterization-test checklist per Part K target file | 02 | Part K/J |
| 11 | Two-tier gates: deterministic vs statistical (kills live-flake and cold-start false reds) | 03 | Part O, [needs adjudication] |

**P2 — structural, alongside Part K:**

| # | Item | Chapter | Mapping |
|---|---|---|---|
| 12 | CLOS-ify `run-tui`/`cli-handler`; replace twin dispatch chains with a dispatch table | 01/02 | Part K |
| 13 | Profile-driven journal_read / session_load attack (sb-sprof runbook first) | 05 | Part O |
| 14 | Eliminate O(transcript) frame rebuilds and selector rescans | 05 | Part O |
| 15 | Design-by-contract pilot: defstruct payloads + assertion macros in one Part J package | 02 | Part K, [needs adjudication] |
| 16 | Documentation hygiene batch (CHANGELOG duplicate sections, README index rot, 36KB ledger lines, script-generated scale figures) | 04 + review file §3 | — |

## Chapter summaries

- **01 Software Philosophy** — Naur (theory must live in versioned
  artifacts, not just heads), Parnas (package leaks), Hoare (keep each gate
  simple; measure the gates), Brooks (essence/accident; second-system
  warning for Part K), Hyrum (why baseline-locked assertions are the right
  defense), Gabriel (Right Thing chosen; decouple release cadence from goal
  completeness), Dijkstra, Ousterhout (restarts underused), Knuth
  (profile-first).
- **02 Classic Methodology** — Feathers (the pi baseline *is* legacy code;
  "equal-strength assertions first" is the seam method — name it and use it
  per file), Fowler (two hats; CI pain → do it more often), Nygard (audit
  provider timeout/retry consistency), Meyer (DbC pilot), Beck (where TDD
  does and does not apply in parity work), Poppendieck (goal serialization
  trade-offs).
- **03 Verification Theory** — the oracle problem (cadr owns a rare
  pseudo-oracle; protect it and admit correlated-error failure), golden
  masters (periodic human re-review), property-based tests for the three
  hand-written codecs, metamorphic relations for exports, exploratory
  testing as a chartered stage, liveness assertions, mutation thinking for
  dead assertions, deterministic/statistical gate split.
- **04 Team and Process** — TOC (the constraint is gate runtime + advisor
  bandwidth; subordinate, exploit, elevate), DORA four keys mapped (release
  cadence, unmeasured lead time), Mills/Brooks surgical team (executor +
  advisor is that structure; guard the advisor single point), Lean wastes
  mapped to ledger rot and doc duplication, egoless programming (the
  objection mechanism is healthy — keep the records), review sizing
  research, Conway (plan the post-parity architecture deliberately),
  Brooks's law and multi-agent tree coordination.
- **05 Algorithms and Data Structures** — chunk lists for streaming
  accumulation, profile-first journal/session attack, JSON rational parsing
  cost, unicode width tables (currently a handwritten range chain — no
  table at all), renderer frame rebuilds, editor buffer (flat string;
  measure before choosing gap/piece), selector rescans, diff (replay-based
  line diff already beats Myers — keep; word LCS is guarded), allocation
  discipline checklist, profiling runbook proposal.
- **06 Algorithm Hotspots Addendum** — externally supplied per-call-site
  review, re-verified line-by-line: truncate UTF-8 length by full encode
  (F1), slice-with-width pending-ansi O(k²) (F2), compaction/frontmatter
  `nth` walks (F3/F4), small-n accumulate-in-loop (F5), fuzzy downcase
  (F6, overlaps 05 §7), glob double relative path (F7), edit
  all-occurrences keep-as-is ruling (F8). Complementary to 05; only F6
  overlaps.
