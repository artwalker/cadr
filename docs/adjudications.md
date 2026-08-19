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

## 2026-08-18 — Keep SBCL core compression (Part C)

**Ruled**: advisor, after the user delegated the product call that
`goal20-draft.md` §8 item 3 and §14.9 reserved for the user. User
veto remains unconditional.

**Decided**: keep `:compression t` in
`cadr-cli:native-image-save-arguments` whenever `:sb-core-compression`
is in `*features*`. Do not ship an uncompressed default image. Do not
reopen the flag as a rewrite package. The uncompressed path remains
the existing fallback when the feature is absent
(`architecture.md`).

**Why it was decidable**: `8587db53a` measured both variants with the
production save arguments, dropping only `:sb-core-compression` on the
control. Harness: real PTY, new process to first TUI frame, n=20,
interleaved, isolated `/tmp`, not `--help`. Numbers in
`docs/benchmarks/goal20-part-c-compression.json` (Friend-MachineD):

| variant | bytes | median cold start | range |
|---|---:|---:|---|
| compressed | 20,884,056 | 284.338 ms | 258.077–313.390 ms |
| uncompressed | 74,033,504 | 177.015 ms | 164.553–199.184 ms |

The distributions do not overlap (compressed fastest > uncompressed
slowest). Save 53.1 MB (3.54×); pay +107.3 ms (+61%). Both sit under
the 750 ms ceiling (38% vs 24%). A 107 ms once-per-process cost is
below a human-scale CLI wait; 50+ MB is paid on every download, CI
artifact, and disk copy. The switch is one feature flag.

**Rider retired, not passed**: the 2026-08-17 board flip
("if Part H later pairs cold start and compressed is slower than pi
while uncompressed is not, drop compression") cannot fire. Part H
booked `native_image_cold_start` as unpairable: an SBCL image start
versus a Node bundle start measures two runtimes, not cadr versus
baseline code. Cold start keeps the absolute ceiling
(`docs/acceptance/goal-v20-part-h.md` §6.1;
`docs/benchmarks/goal20-unpaired-paths.json`). That is "inapplicable",
not "pi pairing passed".

**Flip conditions that remain**: compressed median cold start on the
gate machine approaches or exceeds 750 ms; the platform lacks
`:sb-core-compression` (already the uncompressed fallback); user veto.

## 2026-08-18 — G.12 dual-reference is not 148 new wall-clock pairs

**Ruled**: advisor, so Part G does not stall on a harness J §8 forbids.

**Decided**: `goal20-draft.md` §14.12 "every `done` row has a
performance dual-reference" is scored as follows. It does **not**
require a new pairing harness or a per-file wall-clock pair.

- H `paired` files: vs pi is the existing H cell; vs previous cadr is
  the K batch FiveAM / render-diff. That is dual-reference.
- H `unpairable` files: single-reference vs previous cadr, already
  booked. Mark the H path. Do not invent a pi pair.
- H `pairable-uncovered` `done` files: J revision 8 forbids inventing
  a second pairing harness. FiveAM / render-diff is vs previous cadr
  only. Do **not** claim "no worse than pi" for those files. Mark them
  single-reference pending an H pair. That gap is G.12 / H unfinished
  surface (76.9% of lines at the H booking), not a silent pass and
  not a K10.

K reports that used FiveAM without naming the H class are incomplete
on the mark, not incomplete on the rewrite. Part G's matrix records
the mark; it does not re-bench 148 files.

## 2026-08-18 — Part E: no batch 3; classify leftovers

**Ruled**: advisor, after the user delegated the G.10 product call.
User veto remains.

**Decided**: do **not** open a Part E batch 3 of remaining PTY
scenarios in Goal 20. The 23 already-captured surfaces (Part D games
plus batches 1–2) stay. Every remaining `examples/extensions/` entry
must leave the weasel word "later batches" and land in one of:

- `pty` — already has a render-diff scenario id
- `suite-lock` — observable surface is registration / load; evidence
  is `goal12-ported-extension-registrations-cover-the-baseline-surface`
  and `goal12-ported-extension-entrypoints-load-without-diagnostics`
  (`source-parity.md` SP-F1 already published that 51 rows have no
  per-row behavior gate)
- `blocked` — cannot differential on this host. Accepted blocked set:
  `rpc-demo` (RPC mode, not TUI), `doom-overlay` (needs a WAD fixture),
  `ssh` (real network), `github-issue-autocomplete` (real network),
  `mac-system-theme` (not this host's contract)

Do not invent "intentional difference" for a newly found defect. Do
not silently skip. User A/B on the captured set remains a Goal 20
closeout gate, not this cell.

**Why it was decidable**: draft §5 forbids shrinking by batching, but
G.10's required artifact is a conclusion per entry, not a PTY for
every entry. Batch 0 already named surfaces; D+20 already found the
hello / event-bus / overlay / header / commands class of bugs. Forty
more PTY scenarios is a new goal. SP-F1 already told the truth about
suite-lock. Replacing "later batches" with `pty` / `suite-lock` /
`blocked` is the closeout; another capture wave is not.

## 2026-08-18 — Part O: blocked closeout; no 7f without a proposal

**Ruled**: advisor, after the user delegated the G.16 product call.
User veto remains.

**Decided**: Goal 20 Part O closes as **blocked**, not as ratio ≤ 1.0.
Do not run a fifth locked probe. Do not lower `RATIO_CEILINGS` in the
same breath. Do not take a third-party JSON library, drop `safety`, or
change the session file format without a written proposal and a later
user/advisor pass.

Booked same-machine non-quick ratios (`docs/performance.md`, git
`400dbadf4`): append 2.21×, read 3.93×, load 4.28×,
`list_models_render` 3.18×. Locked probes: 7a shipped (`6211fff2f`,
append 8.45× → 2.15×); 7b abandoned (read 5.42× → 6.20×); 7c skipped
(append 1.90× on `6211fff2f`, below the "> 2×" trigger); 7d abandoned
(render 2.74× → 2.97×). Remaining heat after sprof (`5f7c96750`):
`parse-json` PEEK/PARSE-STRING on read/load; per-sample mkdir +
stringify on append; registry/FS on `list_models_render`, not table
`format`. 12C-3 (`dacebac5e`) already spent the post-sprof JSON
inline proposal.

**Why it was decidable**: draft §10-annex item 7 is the exit — probes
exhausted and still > 1.0 → blocked with what was tried. Item 3
forbids the next real win (a JSON library or a format change) without
a proposal. Re-running 7a–7d is theatre. A later goal may take the
parser; this goal records the gap.

## 2026-08-18 — Live Lisp first; not Lisp-for-Lisp; paper A/B does not close live example bugs

**Ruled**: user (2026-08-18 11:25–11:27). Advisor recorded.

**Decided**:

1. Use Common Lisp's live image (Slynk, restarts, load-and-probe,
   MOP/introspect, compiler warnings) where the state actually lives.
   Do not add `restart-case`, hooks, or declarations on pairable
   user-visible paths in order to look native.
2. On a running cadr (TUI / rpc / live provider), attach `--slynk`
   **first**. "Could almost name the trigger from source" is not a skip.
   FiveAM locks the trigger afterwards. Slynk is not a second test
   runner and is not load-and-probe.
3. Paper A/B of captured example surfaces, and Part E classification
   closeout, do **not** close defects the user still hits while
   playing. Those stay in Goal 20 as fixes or `blocked`, diagnosed
   with Slynk on the live process.

**Why it was decidable**: the previous §6.1 wording ("attach Slynk when
source-reading cannot name the trigger") produced screenshot-and-guess
diagnosis. The same day the user still reproduced tic-tac-toe overlay
desync and `send-message requires DELIVER-AS while the agent is running`
after a paper A/B pass. Baseline `sendCustomMessage` steers when
`isStreaming` (`packages/coding-agent/src/core/agent-session.ts:1452-1457`);
cadr errors (`src/cadr-agent/extensions/providers.lisp:260-265`).

## 2026-08-18 — CL ceiling, not beat-pi-and-stop; experience on the same bar

**Ruled**: user (2026-08-18 11:44). Advisor recorded.

**Decided**:

1. The standing sentence in `development-policy.md` §1.4 ("performance
   has no ceiling and a floor at the baseline") is the product bar.
   Goal 20 Part O's exit (four paired paths ≤ 1.0 or `blocked` after
   probes 7a–7d, `4cd3a510b`) remains the record of *those* probes.
   It is not permission to stop because cadr beat pi, and it is not
   "performance is done".
2. The target is the limit of this SBCL image and live Lisp process
   without changing the product contract: specialised arrays,
   declarations with numbers, a JSON parser that is not per-character
   `PEEK` where a vector window would do, registry not re-stat'd on
   every print, overlay/transcript/busy agreeing with the live objects.
   Copying pi's TypeScript shape "because it is fast enough" is a
   failure mode the policy already names.
3. Experience uses the same bar. A live image that can be inspected and
   continued, and a screen that does not lie, is the Lisp product; a
   pixel-faithful slower clone of pi's TUI is not.
4. The whole programme stays in Goal 20 as Part P (`goal20-draft.md`
   十B). Do not drip-feed 7e/7f/7g through the advisor. One lever per
   commit with numbers is measurement, not scope-slicing. Stop for
   adjudication only on a new dependency, a `safety` drop, a session
   format change, mmap, or SIMD that changes observable bytes.
5. Do not re-run Part O probes 7a–7d. Do not lower `RATIO_CEILINGS` in
   the same commit as a speedup. Do not announce Goal 20 complete
   because O is `blocked`.

**Why it was decidable**: booked Friend-MachineD ratios still show
read 3.93× and load 4.28× on `parse-json` `PEEK`/`PARSE-STRING`;
append 2.21×; `list_models_render` 3.18× on registry/FS, not `format`.
H can falsify "no worse than pi" for 17.0% of lines. N2.8 found zero
optimising type declarations. The user rejected both "one knife at a
time from the advisor" and "beat pi, stop".

## 2026-08-18 — Concurrent agents: throughput without a second owner

**Ruled**: user (2026-08-18 11:52). Advisor recorded.

**Decided**: grok may use parallel agents. Extra writers in one
checkout are forbidden. Policy: `docs/development-policy.md` §7.

1. Read-only agents (review a SHA, sprof in a throwaway worktree,
   baseline lookup) may share a cwd if they do not write tracked
   files.
2. Write agents need a posted ownership table and each their own git
   worktree from the same SHA. Merge onto `cadr-migration` one at a
   time; `test-cl.sh` on that commit; then rebase the next.
3. Pins, CHANGELOG, ledgers, `RATIO_CEILINGS`, and any already-dirty
   file stay with the main executor. Two Lisp-native rewrites of one
   module, two JSON probes, two overlay owners: refuse.
4. "We used five agents" is not a quality signal. One lever per
   commit still holds for Part P.

**Why it was decidable**: the same morning the advisor's Part P docs
and the executor's tic-tac-toe Lisp were dirty in one worktree.
`git add -A` is already banned for that reason. Multi-agent without
file ownership repeats it at larger scale. The organization ledger's
question is "one user-visible decision, one owner"; parallel writers
on one file are a second owner.

## 2026-08-19 — Pairable paths: measure then optimize (P.13)

**Ruled**: user (2026-08-19 18:30). Advisor recorded.

**Decided**: Goal 20 must measure every path that can be paired with
pi, then refine it. Losing to pi is the floor, not the stop.
This is Part P item **P.13** in `goal20-draft.md`. It is not a
new goal.

- The unit is a **path** (same fixture bytes, same machine, both
  sides' production code). It is **not** one wall-clock per
  `.lisp` file. The 2026-08-18 G.12 ruling ("not 148 file-level
  pairs") still holds.
- H `pairable-uncovered` is no longer an acceptable terminal
  state. After P.13, `--check` on `goal20-unpaired-paths.py`
  must not report that class. Every `src/**/*.lisp` is
  `paired`, `covered-as-callee` of a named metric, `needs-pair`
  (until the pair lands), or booked `unpairable`.
- New `unpairable` rows need a proposal. "No fixture yet" is
  not unpairable.
- A new pair and an optimization of that pair are separate
  commits. Do not optimize a path that has no pair. After the
  pair exists, keep refining: floor first if behind pi, then
  the CL ceiling even if already faster than pi. High
  performance is not a defect and not a stop.
- Already-paired paths stay in scope whether they lose or win
  (load, read, argv, truncation still behind; help, walk,
  append, list_models, stream already ahead — keep going while
  sprof names a Lisp structure).
- Unpairable paths stay single-reference vs previous cadr
  (cold start, live sockets, Lisp-only extension host, etc.).

**Why it was decidable**: H reports 74.4% of lines as
`pairable-uncovered`. That share was a measurement gap, not a
physical limit. The user asked whether performance coverage was
comprehensive; it was not. They then ordered the gap closed
inside Goal 20.

## 2026-08-19 — After a pair lands, keep refining (P.13)

**Ruled**: user (2026-08-19 19:21). Advisor recorded.

**Decided**: Measuring is not the end. Paths that can still be
refined must be refined. Beating pi is not a reason to stop.
The 18:30 P.13 sentence "optimize the ones that lose" is
narrowed: losing to pi is the **floor** queue; the **ceiling**
queue is every paired path whose sprof leftover is still Lisp
structure, including paths already faster than pi.

Split commits remain: fixture+pair first, then sprof+one lever.
Empty micro-knives with no wall-clock movement are not
"refining".

**Why it was decidable**: the sqlite pair was queued as
"measure only in that commit". The user stated that after
measurement, further optimization is still required, and that
high performance is not wrong.

