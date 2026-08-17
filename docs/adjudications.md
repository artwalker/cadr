# Adjudication log

Append-only. **A ruling belongs here when it still constrains someone after
the goal that produced it has closed out.** Goal state files are disposable
scratch and are gitignored; this file is the tracked record of why the rules
are what they are.

Established by `development-policy.md` §5.1 (user adjudication, 2026-08-15),
after the observation that the entire goal 20 ruling history lived in a
92 KB gitignored file — one `git clean` would have destroyed the rationale
layer while every gate stayed green.

**What does not belong here**: work-queue state, per-batch progress, findings
that were fixed and closed inside one goal, and anything already carried by a
current contract (`architecture.md`, the five ledgers, `development-policy.md`).
A ruling that changes a contract is recorded *in that contract*; this file
records the ruling itself, so the reasoning survives when the contract is next
edited.

Newest last. Each entry: date, who ruled, what was decided, and — the part
that matters — **what evidence made it decidable**.

---

## 2026-08-14 — I04 covering is scoped to approved identity pairs

**Ruled**: advisor. **Proposal**:
[`proposals/goal20-i04-scoped-covering.md`](proposals/goal20-i04-scoped-covering.md),
where the full ruling and its three corrections live.

**Decided**: accept the scoped-hunk rule and the v1 screen-pair table.
Attaching I04 without a matcher pass no longer counts as covering.

**Why it was decidable**: `render-diff.py:3323` admitted every visible-text
difference as soon as *any* `textCovering: true` class was attached, and I04
is attached to 283 of 432 disposition entries because almost every screen
shows a product name. The visible-text check was therefore effectively off.
This was not theoretical: 119 stray `m` glyphs passed the official core gate
that way (P0-1).

**Standing consequence**: the same scoped rule binds every `textCovering`
class, not I04 alone — so the next majority class cannot repeat this.
Mining new pairs from today's unmatched diffs is forbidden; that is how a
defect becomes a rename.

**Corrections attached to the acceptance** (all three carried into the
proposal): the "0 unmatched keys without I04" figure holds only inside the
requires-disposition population (whole-snapshot it is 8);
`normalized_screen()` is side-asymmetric, so a third self-test is required
proving the matcher does *not* redden byte-identical inputs; and step 3's
whitespace fold must disclose that it also admits indentation, padding and
alignment differences.

---

## 2026-08-14 — Development documentation is written in English

**Ruled**: user. **Scope**: prose, including historical records.

**Decided**: models read English better; conversation stays Chinese.

**Standing consequence**: `docs/glossary.md` fixes one English term per
concept so a term does not acquire three renderings across the tree. Extend
it rather than improvising a synonym.

**What was deliberately excluded, and why it later changed**: the ledger
verdict vocabulary was held back as a separate mechanized item, because
gates match those tokens byte-exactly across 670 ledger rows — converting
them piecemeal breaks the gates. It was converted on 2026-08-15 in one
commit together with its seven gate sites.

**A rule that came out of doing it**, applicable to any future cross-language
rename: **a translation may not introduce a substring relationship the source
lacked.** 已评估 is not a substring of 未评估, but "evaluated" is a substring
of "not evaluated" — a negative assertion ("this token must be absent")
started matching and a suite aborted at 5 of 9. The check is now permanent in
the conversion script, and it immediately found a second instance nobody had
noticed ("covered" inside "applicable but uncovered") which had stayed green
only because a regex happened to be pipe-delimited. **Surviving by delimiter
accident is not the same as being correct.**

---

## 2026-08-15 — The advisor adjudicates; the user retains an unconditional veto

**Ruled**: user. **Recorded in**: `development-policy.md` §5.1.

**Decided**: what was already the practice becomes the written rule, with
three binding consequences — a ruling lands in the artifact it rules on;
durable rulings are committed to this file; and **the advisor may not
adjudicate a change to the advisor's own authority.**

**Why it was decidable**: §5.5 still demanded user adjudication for every
proposal while goal20 Part A and I04 had both been advisor-ruled. The
mechanism had drifted from its documentation, and a mechanism whose real
rules are unwritten cannot be improved.

---

## 2026-08-15 — Executing and auditing are different hats

**Ruled**: user. **Recorded in**: `development-policy.md` §5.2.

**Decided**: an item the advisor executed is not audited by the advisor.
Either the user audits it, or the delivery says plainly that it was not
independently audited. Mechanical gate results stay valid either way — they
come from machinery, not judgement. What may not be claimed is the judgement
layer.

**Applied retroactively the same day**: the goal 20 documentation
translation (`e8cbfaec9`, `4c8e31416`, `7dd90672c`, `7cf6c3ca7`,
`6f073134e`, `860c075cd`) was executed by the advisor. **Its gate evidence
stands; its review does not.**

**Why it was decidable**: the external review found the advisor acting as
design authority, auditor, and occasionally executor at once — a structure
that makes one person the judge of work they may have touched. Mills gave
those roles to different people for this reason.

---

## 2026-08-15 — Liveness assertions: accepted, with the motivating defect moved to the front

**Ruled**: advisor. **Proposal**:
[`proposals/goal20-liveness-assertions.md`](proposals/goal20-liveness-assertions.md).

**Decided**: accept the timing sidecar, the statistical tier and the
per-scenario threshold rule. **Move silence injection from step 5 to step 2**
and fold it into this proposal.

**Why it was decidable**: the proposal disclosed that no existing scenario
reproduces P0-4 — they all stream promptly, while P0-4 was seconds of
silence at the start of a turn. So the gate as specified is a rhythm
regression lock, not a fix for what motivated it. Shipping the
infrastructure first and the motivating case "separately, later" would have
produced a green gate claiming to watch a dimension whose actual escape
channel stayed open.

**Standing consequence**: when a proposal's own evidence shows the gate
would not have caught the defect that prompted it, the item that closes
that gap is not a follow-up — it moves to the front, or the gate ships
under a name that states what it does not cover.

**Worth copying**: this proposal ran a throwaway pilot before naming a
threshold, so N came from measured data rather than taste — the discipline
the earlier `cold_start` band lacked. Its fd-reuse finding (tracking only
`openpty` polluted the log with 5.8MB of unrelated reads) is recorded so
the next person does not rediscover it.

---

## 2026-08-16 — Undo stack: a byte budget, not a depth cap

**Ruled**: advisor, under the user's standing delegation of technical
decisions (2026-08-16). **Recorded in**:
[`open-questions.md`](open-questions.md) `OQ-G20-UNDO-STACK-CAP`.

**Decided**: option (c) — bound the editor undo stack by snapshot bytes
rather than by entry count.

**Why it was decidable**: the deciding fact was measurability, not
preference. The snapshot is a plist whose mass is a single `:text` string
(`src/cadr-tui/editor.lisp:148-154`), so `(length text)` *is* the size. Had
it needed estimating, option (a) — keep parity, accept the cost — would
have been the honest answer, because an approximate ceiling that fails at
the extreme is worse than none.

**How it reached the queue is the part worth keeping.** The advisor listed
"cap the undo stack" as work to do regardless of benchmarks, having checked
the cost but **not the baseline**. The executor refused the instruction,
citing `packages/tui/src/undo-stack.ts:11-13` — the baseline stack is
unbounded, so a cap is a new mechanism relative to pi and owed an
open-questions entry before any implementation. The refusal was correct and
the advisor's item was retracted.

The executor then proposed option (c), which appears in neither the
advisor's item nor the external report: bound by bytes so that shallow
buffers stay fully undoable. **The adopted answer came from the party being
instructed, not the party instructing.**

**Standing consequence**: "this is obviously more sensible" is not grounds.
Anything absent from the baseline is a new mechanism and goes through
open-questions first, however reasonable it looks — and the advisor is as
prone to this as anyone, which is why the executor's objection channel has
to stay usable.

---

## 2026-08-16 — `accepted-gap` must name a compensating check, and may not dress backlog as limitation

**Ruled**: advisor, under the user's standing delegation of technical
decisions. **Recorded in**:
`test/fixtures/render-diff/visible-string-unmodeled-review.json`
(`packages/tui/src/tui-alt-screen.ts:438`).

**Decided**: `accepted-gap` remains the correct class when the extractor
genuinely cannot traverse a shape, but an entry using it must **name the
compensating check that closes the loop**, with a file:line citation — and it
must not offer "no scenario exercises this" as a reason when a scenario is
writable with the existing harness.

**Why it was decidable**: the registry's own precedent already sets the higher
bar. `packages/coding-agent/src/core/timings.ts:48` ends its reason with *"cadr
prints the identical title (`src/cadr-cli/support/timings.lisp:37`)"* — the
extractor is blind, so the entry points at what is not. The v0.84.2
alt-screen-search entry stacked two reasons and cited nothing. Measurement
settled the second half: `startup-first` already issues `{"send": "ctrl+d"}`,
so `{"send": "ctrl+shift+f"}` is directly expressible and the overlay is
reachable — **an unwritten scenario, not an unreachable one.**

**What the gap actually left open**: `" Find transcript"` matches the baseline
byte-for-byte, **leading space included, and nothing asserts it**. The leading
space is exactly what a later cleanup trims. Six commits earlier, `9e06ab61c`
fixed this same defect shape — cadr had transcribed the harness variant of the
skills prompt block and *dropped its leading blank line*. The shape recurred in
new code with no guard.

**Standing consequence**: a verdict class that means "genuinely needs no
coverage" and a verdict class that means "not covered yet" cannot be the same
class. Once they merge, the registry can no longer distinguish permanent
limitations from backlog, and the backlog stops being visible to anyone
counting gaps.

---

## 2026-08-17 — The executor never writes a ruling, under any signature

**Ruled**: user (facts confirmed with the executor); recorded by the
succeeding advisor.

**Decided**: an executor waiting on an adjudication parks the proposal
("awaiting adjudication") and moves to the next queue item. Writing the
ruling itself — under any signature, including the advisor's — is
self-adjudication (§5.1/§5.2). When an evaluator emits a step like
"Advisor: rule on …", that step is a wait-for-signal, not an
instruction to substitute.

**Why it was decidable**: board reply 18 approved the executor's own
`--sort=path` proposal in the advisor's register while the advisor's
replies stopped at 17. The content was independently verified correct
and ratified afterwards (reply 19), so the ruling stood — but only
because the verification happened to be done; the mechanism must not
depend on that.

**Standing consequence**: board replies carry a distinguishing
signature (session identity); an advisor ratifies nothing it did not
author without verifying first.

## 2026-08-17 — The advisor reads; state changes belong to the executor

**Ruled**: user. **Context**: the advisor re-ran a failed CI job as a
"zero-code discriminating experiment".

**Decided**: the advisor's evidence-gathering is read-only (logs,
diffs, blobs, run metadata). Any action that mutates shared state —
CI reruns, cancellations, pushes, hooks — is executor work, dispatched
via the board. Mechanical results of a boundary-crossing action stay
valid (§5.2); the boundary still holds.

**Why it was decidable**: the playbook (§1) already records the
incumbent's "just this once" implementation incident as the way §5.2
erodes. A rerun is small; the erosion pattern is not.

## 2026-08-17 — Differential fixture pins are local truth

**Ruled**: succeeding advisor, during the goal 20 CI campaign.

**Decided**: `screenSha256` and exact-pair pins in the render-diff
fixtures are generated in the local environment and are the truth the
gate defends. They are never re-pinned from CI observations — that
would redden the local tree and freeze an environment coupling in as
"expected". When CI disagrees with local pins, the fix is the
harness's neutralization layer or CI environment alignment (six
instances this campaign: readdir order, fdfind path, node:internal
frame numbers, slynk port release, UI response timing, elapsed-footer
threshold), or an adjudicated behavioral disposition — never the pin.
