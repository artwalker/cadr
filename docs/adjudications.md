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
