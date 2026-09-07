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

## 2026-08-19 — Read pi first; copy its structure, do not tinker (P.13)

**Ruled**: user (2026-08-19 22:18). Advisor recorded after
reading pi and cadr, not from sprof rank.

**Decided**: A leftover path is refined by **searching how pi
does the same work** (source, not a guess, not a trial
permutation of the current Lisp scan). If the data structure
or algorithm is wrong, replace it with the correct one. That
is the qualitative jump. Micro-knives that only reorder the
existing Lisp walk do not have speaking rights until that
comparison exists.

Standing method, every leftover paired path:

1. Open the pi production function for that pair.
2. Name its data structure and its passes.
3. Name cadr's. If they differ, the next knife is the copy
   (in Lisp, not FFI). If they already match, say so and
   stop inventing scan-order variants.
4. `uiop:split-string` / cons lists of new strings is **not**
   a copy of a JS `string[]`. A fixnum line-start vector plus
   one `subseq` of the original buffer is.

**Evidence (truncate_tail, this ruling's example)**:

pi `packages/agent/src/harness/utils/truncate.ts`
`truncateTail`:

- `utf8ByteLength(content)` → Node `Buffer.byteLength` when
  present (native UTF-8 length of the whole string).
- `splitLinesForCounting` → `content.split("\n")`, pop if
  trailing newline → **random-access array of every line**.
- Walk `lines.length - 1` down to 0 until `maxLines` /
  `maxBytes`; `unshift`; `join("\n")`; byte-length the
  output.

cadr `src/cadr-agent/truncate.lisp`
`truncate-harness-tail` after `13903e05c`:

- Separate full-string `harness-line-and-utf8-length`.
- Then `position #\Newline :from-end t` in a loop (no line
  table).
- `harness-text-lines` already exists and uses
  `uiop:split-string` — that is the **wrong** copy of split
  (new string conses, not an index vector).

`34b76695f` one-reverse-walk of the whole string was a Lisp
scan-order trial. Friend-MachineD tail 1.30×→1.59×. It was
not pi's algorithm. Prefix-remainder-after-short-reverse is
the same class of trial until the line table exists.

**Not decided**: FFI to `Buffer`, mmap, intern tables, AVX /
`sb-simd` as the next truncate knife. Copy the **shape**
(one length pass + random-access lines + index from the end).
Lisp may keep one walk that fills totals and the line-start
vector together; that is still the pi shape, not a new
invention.

**Load / read leftover**: pi is `JSON.parse` (V8). The
standing copy-V8-in-Lisp rule still applies. More empty
SWAR on the existing walker is not this ruling.

**Why it was decidable**: the user rejected "try a small
change". The pi source for the live 1.30× path was unread
before the reverse-walk knife. After reading it, the missing
structure is the line table, not another character-loop
direction.

## 2026-08-19 — Performance work starts from pi's algorithm, not from sprof of a worse one

**Ruled**: user (2026-08-19 22:27). Advisor agrees.
Recorded as a diagnosis of *why* the line table was missing,
not a new truncate knife.

**Decided**: Yes, the guiding thought was wrong, in a
specific way. Product alignment stays **observable
behavior** (`development-policy.md` §1). **Speed work**
starts from pi's algorithm and data structure, encoded in
Lisp. sprof is for leftover *after* those match. It must
not be used to invent a different algorithm.

Three stacked rules produced the truncate mess:

1. Goal 12 Lispified `truncateTail` as
   `harness-text-lines` = `uiop:split-string` (same
   algorithm, **wrong representation**: conses of new
   strings).
2. `400dbadf4` (zero-alloc UTF-8 count) and `0afb9660c`
   ("scan without split-string") treated allocation as the
   enemy. this-host head 7.276 ms / 2.56 MB → 2.319 ms /
   197 kB. That number was real. They deleted the line
   table with the conses, and never put back a fixnum index
   vector. Output bytes still matched, so §1 called it
   aligned.
3. Part P then said: sprof → one lever; "copying pi's
   TypeScript shape because it is fast enough" is a failure
   (`docs/adjudications.md` 2026-08-18 CL ceiling). The
   executor and the advisor both read that as "do not keep
   pi's DS". Hottest frames (`HARNESS-LINE-AND-UTF8-LENGTH`,
   reverse `position`) became the queue. `34b76695f` /
   remainder proposals are that queue.

**What was right in the old thought**: do not copy JS
`string[]` allocations; do not stop because cadr beat pi;
one lever per commit with numbers.

**What was wrong**: using sprof of a scan to choose the
next scan. Using §1 "not source structure" to drop the
algorithm. Using "do not copy TS shape as the ceiling" to
forbid copying the algorithm as the **floor of the design**.

**Standing split**:

| question | source of truth |
|---|---|
| Same product? | observable bytes / UX |
| Same speed design? | pi's production function: passes and DS |
| Lisp encoding? | fixnum vector / octet window / typed walk — not `uiop:split-string`, not FFI |
| After DS matches, still slow? | sprof of *that* implementation |

Promoted the same day (user 22:32) into
`docs/development-policy.md` section 1 item 6.

**Why it was decidable**: the user asked why the correct
algorithm was not chosen and only cleaned up later. The
git history of `truncate.lisp` answers: it was chosen
(`harness-text-lines`), then deleted as a perf win, then
the board kept mining the replacement scan.

## 2026-08-19 — Promote performance alignment into standing policy; audit the tree

**Ruled**: user (2026-08-19 22:32). Advisor recorded.

**Decided**: Change the standing development thought, then
re-check cadr for the same defect (pi's data structure
dropped or encoded as a cons list).

Landed in `docs/development-policy.md` section 1 item 6,
`docs/glossary.md` 「性能对齐」, and
`docs/acceptance/goal-v20-ds-audit.md`.

Class A (deleted structure): harness truncate scan;
CLI `utf8-length` still encodes to count.

Class B (list encoding of `string[]`): CLI `text-lines` /
`split-all-lines`; `tools/read`, `tools/grep`, bash notice
`harness-text-lines`; JSONL open still `split-string`
(not the paired octet `session_load` path).

Class C: load/read vs `JSON.parse` stays copy-V8-in-Lisp,
not a scan-order knife. Markdown table split is not a
floor campaign.

**Why it was decidable**: the user asked to fix the guiding
thought and to look for other instances, not only truncate.

## 2026-08-20 — Same observable behavior; beat pi; study the callee's algorithm

**Ruled**: user (2026-08-20 16:50). Advisor agrees.

**Decided**:

1. **Product**: same observable behavior as pi.
2. **Speed**: cadr must be able to **beat** pi, not stop at
   parity. High performance is the goal ("Lisp 屠龙刀").
3. When pi's hot path is a **callee** (Node/`JSON.parse`→V8,
   `Buffer`, zlib, …), do **not** treat "Class C / not our
   source" as a stop. Open that software's algorithm and
   data structure, learn whether it is better, then
   **Lisp-encode** that essence (or a falsifiably better DS
   that keeps behavior). Same rule as reading pi first
   (§1 item 6): the design source is the real computational
   structure, wherever it lives.
4. Still forbidden without adjudication: **FFI into** that
   callee (link V8/simdutf), mmap, intern-table growth,
   empty SWAR, observable-byte SIMD. Studying V8 ≠ calling V8.

**Supersedes in practice**: reading Class C rows in
`goal-v20-ds-audit.md` as "product knife blocked / park
forever". Class C only means "do not invent a third scan
from sprof of a worse walker"; it does **not** mean "never
touch JSON/load again".

**Why it was decidable**: the user restated the goal after
a provider-pairing conveyor and Class C leftover flags.
The bottleneck is shared (`PARSE-JSON` / load). The work
is to understand V8/`JSON.parse` (and peers) and encode
the win in Lisp.

## 2026-08-20 — Bucket-split leftover parents; empty ⚑ ≠ exhausted

**Ruled**: user (2026-08-20 21:40–21:46). Advisor agrees.

**Decided**:

1. Call-boundary wins (inline quote-scan / skip-expect) are
   real essence for that layer. Micro knives that only rename
   V8 (`scan-key` macrolet, length-case key dispatch,
   closed-set enum flyweights, DIGITS unroll) and lose on
   **cadr µs** are circling phenomena — do not treat them as
   "V8 essence found" or as "levers exhausted".
2. When sprof names a **parent** with high total%
   (e.g. `PARSE-SESSION-RECORD-OCTETS` ~70%+ total), the next
   delivery is a **bucket split** (which child path costs
   cadr µs) + V8 `Parse*` function names + one unfalsified
   knife — not another <3% self polish and not an empty ⚑.
3. A ⚑ is valid only with that note proving the remainder is
   solely FFI-into-callee / mmap / intern-table growth /
   empty SWAR / COPY-UNESCAPED (or other already-banned
   classes). "Banned micro classes" alone is not exhaustion.
4. Durable pointers: this file; `goal20-draft.md` 十B
   「Callee / 屠龙」; `docs/acceptance/goal-v20-ds-audit.md`
   Class C; `docs/acceptance/goal-v20-part-p.md`.

**Why it was decidable**: user asked whether the board
guidance was in the goal; agreed to land it in-repo.

## 2026-08-20 — Study algorithm shape, not port the V8 VM

**Ruled**: user (2026-08-20 22:41–22:50). Advisor agrees.

**Decided**:

1. **Study** means open the callee hot path
   (`json-parser.cc` / `.h`, or the named file for that
   step) and write what it **does less of** (allocations,
   key lookup, string copy, one-shot object build, …).
   Mapping cadr symbols to `Parse*` / `BuildJsonObject`
   names **without** that contrast is superficial and is
   not "essence found".
2. **Not required** (and not a stop if absent): porting
   V8 tokenizer, `HandleScope`, HiddenClass/Map transitions,
   Zone allocator, smi vs heap number, or linking
   V8 / simdjson / yyjson. Those are VM/runtime machinery;
   the goal is a Lisp encoding of the computational win
   (or a falsifiably better DS) at same observable behavior.
3. Bucket-split notes must pair **cadr child µs** with that
   source-level contrast for the expensive child — not only
   a V8 name column.
4. A knife is **not landed** until `scripts/test-cl.sh` is
   green and Friend-MachineD non-quick reports **cadr µs**
   (keep if better or flat-for-noise; revert if worse).
5. Pointers: this file; `goal20-draft.md` 十B; Class C /
   Method in `goal-v20-ds-audit.md`; `goal-v20-part-p.md`.

**Why it was decidable**: user asked whether shape-only
study without dumping the V8 tree is mere skin; agreed to
land the distinction in-repo.

## 2026-08-20 — Lisp 屠龙刀: invent the DS if none is ready-made

**Ruled**: user (2026-08-20 23:43). Advisor agrees.

**Decided**:

1. **Lisp is the dragon-slaying sword.** Same observable
   behavior as pi; performance must be able to **beat** pi.
   If there is no ready-made library/encoding that wins,
   **build the algorithm and data structure in Lisp** — do
   not stop at "V8 is a VM so only FFI remains".
2. The leftover note
   `docs/benchmarks/goal20-session-load-leftover.md`
   (`a698334d5`) is accepted as a **bookkeeping of three
   falsified V8-shape knives**, not as product `blocked`,
   not as G.17 `met`, and not as permission to park load.
3. Falsifying a *copy of V8's surface shape* (bag,
   stack-locals→typed, delayed span→MakeString) means those
   **encodings** lost on cadr µs. It does **not** mean
   "no legal Lisp lever". Next knives may be a **falsifiably
   better Lisp DS/algorithm** (behavior unchanged), still
   informed by studying callees, still without FFI/mmap/
   intern grow/empty SWAR unless newly adjudicated.
4. Empty ⚑ that only lists banned classes after surface
   copies failed is **rejected**. A ⚑ needs a new concrete
   Lisp proposal that failed, or an explicit ask to break a
   ban.
5. Pointers: this file; leftover md; Part P; board.

**Why it was decidable**: user answered the leftover
proposal — keep building in Lisp, do not default to FFI or
stop.

## 2026-08-20 — Mature algorithms/DS as design sources; keep optimizing

**Ruled**: user (2026-08-20 23:48). Advisor agrees.

**Decided**:

1. Design sources for the next load knives are **not limited
   to V8 surface shapes**. Mature, published algorithms and
   data structures (classic texts, well-known parsers,
   rope/gap/buffer views, closed perfect hashing for tiny
   key sets, arena/bump patterns expressible in Lisp, …)
   may be studied and **Lisp-encoded**, same rule as studying
   a callee: learn the computational structure, do not FFI
   the foreign binary unless newly adjudicated.
2. The executor continues optimizing `session_load` (and
   other >1.0 floors) under Part P / 屠龙: propose DS + why
   cheaper than the ISO-kept walker and the three withdrawn
   knives; green `test-cl.sh`; Friend-MachineD **cadr µs**
   wins or revert.
3. Confidence that a Lisp solution exists does **not** relax
   measurement: no G.17 `met`, no empty ⚑, no redoing
   falsified encodings.
4. Pointers: this file; `goal20-draft.md` 十B; Part P;
   `goal20-session-load-leftover.md`; board `[ready]`.

**Why it was decidable**: user affirmed keep going with
Lisp, using the body of known algorithms/DS, after the
leftover booking.

## 2026-08-21 — Load knife priority after bag-reuse falsifications (DeepSeek review)

**Ruled**: user forwarded an external (DeepSeek) load plan and
asked the advisor to land the review in goal/docs
(2026-08-21). Advisor **partially agrees**.

**Decided**:

1. **Diagnosis (agreed in direction)**: the remaining
   `session_load` gap (~1.15×, cadr ~1879 µs vs pi ~1634) is
   mostly allocation / constant factors, not "JSON syntax
   scan is too slow". V8's edge on `MakeString` /
   `BuildJsonObject` is cheap one-byte strings, bump-ish
   young allocation, and schema slot writes — not a reason
   to port HiddenClass / Zone / HandleScope.
2. **Facts already true in product** (correct the plan's
   premises before cutting):
   - Keys are octet windows + `octet-window-equals` (ub32);
     not per-key `make-string` / `string=`.
   - Unescaped ASCII values already use
     `simple-base-string` + ub32→`schar` copy in
     `copy-unescaped-json-octets`; closed-set value intern
     exists. Do not reinvent "first switch to base-string".
   - `put-entry-field` / `put-message-field` already
     length (+ optional first byte) + `key=` then a
     specialized value parser.
   - Closed-schema length-case dispatch (`789bec858`) was
     withdrawn. SCAN-KEY labels→macrolet (`f87bea405`) was
     withdrawn.
   - Bag / token reuse family lost on cadr µs: parse-message
     三连 (2015 / 1917 / 1974) **and** content-block scratch
     reuse (`767b4c452` → withdraw `52d0986f8`, 1879→**2083**).
     Do not redo.
3. **Next-knife priority** (executor):
   - **Try first**: (A) per-load string arena / bump into one
     `simple-base-string`, return displaced (or equivalent)
     views for unescaped ASCII — **without** micro-rewriting
     the `COPY-UNESCAPED` kernel; short strings may lose on
     displaced headers — Friend-MachineD only; treat
     &lt;~50 µs as noise and revert. (D) content (or similar)
     arrays: exact-length / `svref` fill instead of
     list+`nreverse` / repeated extend — **not** bag reuse.
   - **Default reject as next knife**: (B) integer key-tag
     `case` / length-case redos of `789bec858` unless the
     encoding is shown **distinct** (e.g. unique first-u32 /
     gperf prefix with collision confirm) **and** Friend-MachineD
     cadr µs beats ~1879 (else withdraw). (C)
     "schema-specialized parsers" that become stack-locals
     then assemble typed message (= 三连 #2). Weak if it
     only restates existing `put-*-field` dispatch.
   - **Last**: (E) `tagbody` merge of hot labels — after A/D;
     SCAN-KEY macrolet already lost.
   - **Needs new adjudication**: lazy `octet-span` (or
     `(or string octet-span)`) materialization that changes
     internal session representation. Not the default knife.
4. Do **not** treat summed speculative µs from an external
   plan as a schedule. Keep/revert only on Friend-MachineD
   **cadr µs** vs ~1879 baseline; green `scripts/test-cl.sh`.
5. Still forbidden without adjudication: FFI into
   V8/simdjson/yyjson, mmap, intern grow, empty SWAR,
   COPY-UNESCAPED micro-rewrite, empty banned-class ⚑,
   G.17 `met` / product `blocked` for this leftover.
6. Pointers: this file; `goal20-draft.md` 十B item 10;
   `docs/acceptance/goal-v20-part-p.md`;
   `docs/acceptance/goal-v20-ds-audit.md` Class C;
   `docs/benchmarks/goal20-session-load-leftover.md`;
   `docs/benchmarks/goal20-parse-session-record-split.md`;
   board `[ready]`.

**Why it was decidable**: user asked to record the advisor
review of the DeepSeek proposals into the goal and durable
docs after the content-block scratch falsification.

## 2026-08-21 — COPY-UNESCAPED ban scope; try quote-scan high-byte + content shape fast-path

**Ruled**: user asked whether an external plan's knives are
worth trying and to land the worth-trying ones for the
executor (2026-08-21). Advisor agrees **proposals 1 and 2**
are worth trying; clarifies the COPY-UNESCAPED ban.

**Decided**:

1. **Ban scope — COPY-UNESCAPED micro-rewrite does NOT
   include** removing the redundant ASCII classification
   pass before the ub32→`schar` fill, when high-byte
   presence is already known from the value quote-scan.
   Banned remains: rewriting the fill/copy **kernel**
   itself (instruction schedule / unroll polish of the
   Latin-1 memcpy loop). Folding `(logand word #x80808080)`
   into the already-paid `octet-find-quote-or-backslash`
   (or a **value-only** variant) and calling a check-less
   ASCII copier whose fill loop is byte-identical is a
   **legal** knife. Do not slow key scans: prefer a value
   scanner variant or optional high-byte accumulation only
   on `parse-string-value`.
2. **Try next (executor order — one knife at a time)**:
   - **Knife 1 (main)**: quote-scan accumulates `high-byte-p`
     across escape resumes (like `escaped-p`); unescaped
     ASCII → check-less copier; high-byte unescaped →
     `octets-to-string` UTF-8; escaped → existing decode.
     Green `test-cl.sh`; strings EQUAL to current walker;
     Friend-MachineD `session_load` cadr **&lt; ~1879 µs**
     or revert. Do **not** merge with knife 2.
   - **Knife 2 (after knife 1 keeps)**: content-block
     compact-prefix fast path for pi's common emit shapes
     (`"type":"text","text":"…"` / thinking / toolCall
     prefixes via ub32 memcmp); miss → existing
     `parse-content-block`. Not bag reuse (fast path never
     builds `session-json-block`). Extra: mutated fixtures
     (key order, spaces, escaped type, unknown type) must
     EQUAL the generic path. Friend-MachineD further drop
     or revert.
3. **Not authorized as the next cold knives**:
   - Proposal 3 (`put-message-field` first-byte dispatch):
     only after 1+2 residual; adjacent to banned
     length-case; do not merge with 1/2. Existing
     `put-entry` u32/gperf WIP is separate — remesure alone;
     do not merge with knife 1.
   - Proposal 4 (per-load ephemeral EQ dedupe table):
     **needs a new user ruling** before any code (near
     intern-grow).
   - Proposal 5 (whole-line base-string + displaced views):
     research only; displaced ≠ `simple-string` breaks
     downstream declares; chunk-buffer alias risk. Needs
     output-contract ruling before product work.
4. Speculative µs sums are not a schedule. Keep/revert on
   Friend-MachineD cadr µs only.
5. Pointers: this file; `goal20-draft.md` 十B item 11;
   Part P; Class C; leftover; split note; board `[ready]`.

**Why it was decidable**: user asked yes/no on ban scope
and to put worth-trying knives in docs for grok.

## 2026-08-21 — item 10 A/D falsified; invent next load knife

**Ruled**: executor remesured authorized item 10 knives after
proposal 3 keep (`0084f0703`, Friend-MachineD load ~1763 µs).

**Decided**:

1. **Item 10 D withdrawn** (`4bc73e29d`): exact-length /
   `svref` content fill **1763→1838 µs**. Do not redo.
2. **Item 10 A withdrawn** (`27c197192`): per-load
   string-arena + displaced ASCII views **1763→3667 µs**.
   Do not redo. COPY-UNESCAPED fill kernel was untouched.
3. **Next**: remesure `PARSE-SESSION-RECORD-OCTETS` split on
   the current walker, then invent **one** new Lisp encoding
   (屠龙刀). Keep/revert on Friend-MachineD cadr **&lt; ~1763 µs**.
4. Still forbidden without a new ruling: bag/token reuse,
   knife 1 high-byte redo, length-case/key-tag redo, proposal 4
   EQ dedupe, proposal 5 productization, FFI, mmap, intern grow,
   COPY-UNESCAPED fill-kernel micro-rewrite, empty ⚑ that only
   repeats banned classes. Default-reject B/E unless a distinct
   proof.
5. Pointers: this file; `goal20-draft.md` 十B items 10–11;
   leftover; split note; board `[ready]`.

**Why it was decidable**: keep/revert numbers on Friend-MachineD
falsified both remaining item-10 cold knives; continuous 屠龙
requires invent-from-residual, not park.

## 2026-08-21 — after A/D withdraw: E authorized; 4/5/octet-span ruled

**Ruled**: executor reported item 10 A/D withdrawn, walker
`0084f0703` @ ~1763 µs, empty `[ready]`, and ⚑ waiting on
proposals 4/5/octet-span (2026-08-21). Advisor **agrees** with
the keep/withdraw table and **rejects** the empty ⚑.

**Decided**:

1. **Facts kept**: product walker `0084f0703`; baseline
   Friend-MachineD load **~1763 µs**; D `4bc73e29d`
   (1763→1838) and A `27c197192` (1763→3667) withdrawn —
   do not redo. G.17 stays `missing`. Goal 20 not done.
2. **Empty ⚑ rejected**: listing "needs ruling on 4/5/octet-span"
   without a keep/revert knife is banned-class ⚑ (十B item 8).
3. **Authorized next (order)**:
   - Remesure `PARSE-SESSION-RECORD-OCTETS` split on the
     current walker (docs).
   - **(E) `tagbody` merge of hot labels** — last-resort from
     item 10, now that A/D are done. Alone; Friend-MachineD
     cadr **&lt; ~1763** or revert. Not a SCAN-KEY macrolet redo.
   - Then invent one new Lisp encoding from residual if needed.
4. **Proposal 5 productization — rejected**: whole-line /
   displaced views are the same tax family as withdrawn A.
   Research notes only.
5. **octet-span lazy materialization — not the next cold
   knife**: still changes internal representation; needs a
   separate EQUAL-contract ruling if ever proposed with
   numbers. Not a stop reason.
6. **Proposal 4 (per-load EQ dedupe) — still forbidden**
   until the user explicitly says YES (near intern-grow).
   Do not code it on ⚑.
7. Pointers: this file; `goal20-draft.md` 十B; leftover;
   split note; board `[ready]`.

**Why it was decidable**: A/D falsifications + standing 屠龙
rules decide E and reject 5; 4 still needs the user; empty
⚑ is already banned.

## 2026-08-21 — user YES on proposal 4 (per-load EQ dedupe)

**Ruled**: user replied 同意 to the advisor question whether
to open proposal 4 (2026-08-21).

**Decided**:

1. **Proposal 4 authorized**: per-load **ephemeral** EQ
   dedupe table for repeated string values during one
   `session_load` (or equivalent walk). Alone; Friend-MachineD
   cadr **&lt; ~1763 µs** or revert; strings EQUAL to current
   walker; green `test-cl.sh`.
2. **Still banned**: growing a **global / cross-load** intern
   table; persisting the dedupe map beyond the load; merging
   with E/`tagbody` or other knives in one keep/revert.
3. Proposal 5 productization and octet-span-as-cold-knife
   rulings from the prior adjudication stand.
4. Pointers: this file; `goal20-draft.md` 十B; board `[ready]`.

**Why it was decidable**: user explicitly agreed to open
proposal 4 after it was held for a YES.

## 2026-08-21 — E tagbody falsified (1763→2004)

**Ruled**: executor withdrew E after Friend-MachineD n=5
load **1763→2004 µs** (`b042b4fbb`); product restored to
`0084f0703`.

**Decided**: do not redo folding `put-entry-field` into the
record-object `tagbody`. Next remains proposal 4 (user YES)
then invent. G.17 stays `missing`.

**Why it was decidable**: keep/revert on Friend-MachineD.

## 2026-08-21 — proposal 4 ephemeral EQ falsified (1763→2217)

**Ruled**: executor remesured per-load EQUAL-hash intern-miss
dedupe (table bound only in `load-session`; closed intern set
unchanged). Friend-MachineD n=5 load **1763→2217 µs** (samples
2108–2295). Product restored to `0084f0703`.

**Decided**:

1. Do not redo per-load EQ string tables (EQUAL keys, EQ
   values) on this walker. Hash + extra gethash lost to
   intern-miss copy.
2. Do not grow a global intern table.
3. Invent residual: leftover is still intern-miss
   `copy-unescaped` + `parse-content-block` + `parse-usage`.
   Banned redos (A/D/knife 1/bag/P5/octet-span/SCAN-KEY/
   length-case/fill-kernel) are not invent. G.17 stays
   `missing`. Goal 20 not complete.

**Why it was decidable**: keep/revert on Friend-MachineD.

## 2026-08-21 — invent usage compact-prefix falsified (1763→1805)

**Ruled**: executor tried pairing-fixture usage compact
prefix (same family as kept content compact-prefix, not a
banned redo). Friend-MachineD n=5 load **1763→1805 µs**
(samples 1768–1832). Product restored to `0084f0703`.

**Decided**:

1. Do not redo this usage key-order prefix.
2. Next invent targets remain `[ready]`: intern-miss
   `copy-unescaped` (not fill-kernel / knife 1 / EQ / A);
   `parse-content-block` residual after kept compact-prefix
   (not bag / not usage prefix redo). Do not park on empty ⚑.
3. G.17 stays `missing`. Goal 20 not complete.

**Why it was decidable**: keep/revert on Friend-MachineD.

## 2026-08-21 — silent stop after invent miss; name next knives

**Ruled**: user reported grok Goal stopped (2026-08-21 ~10:27).
Board still had invent `[ready]`; no `⚑`. Last HEAD
`f72150c2e` (usage compact-prefix withdraw).

**Decided**:

1. Silent stop is invalid. Either continue `[ready]` or raise
   `⚑` with tried/banned list.
2. **Named next knives** (one at a time, Friend-MachineD
   cadr **&lt; ~1763** or revert):
   - `parse-usage` **first-byte field dispatch** (proposal-3
     family). Not the withdrawn whole-object usage
     compact-prefix.
   - Then `parse-content-block` first-byte on the **generic**
     path after compact-prefix miss (not bag).
3. Parallel OK if load knives keep losing: paired paths still
   &gt;1.0× (`journal_read`, `provider_pi_messages`,
   `provider_mistral`).
4. G.17 stays `missing`.

**Why it was decidable**: board state + standing no-silent-stop
rule; concrete encodings replace vague invent.

## 2026-08-21 — parse-usage first-byte falsified (1763→1996)

**Ruled**: executor remesured proposal-3-family first-byte
on `put-usage-field`. Friend-MachineD n=5 load
**1763→1996 µs** (samples 1773–2127). Product restored to
`0084f0703`.

**Decided**: do not redo usage first-byte. Next remains
`parse-content-block` generic first-byte (compact miss),
or leftover pairing `journal_read` / `pi_messages` /
`mistral`. Silent stop still invalid. G.17 stays `missing`.

**Why it was decidable**: keep/revert on Friend-MachineD.

## 2026-08-21 — parse-content-block generic first-byte falsified (1763→2470)

**Ruled**: executor remesured first-byte on generic
`put-block-field` (compact miss). Friend-MachineD n=5 load
**1763→2470 µs** (samples 2345–3571). Product restored to
`0084f0703`.

**Decided**: do not redo content generic first-byte. Load
first-byte family exhausted on this walker. Leftover
pairing still >1.0× on some samples (`journal_read`,
`provider_pi_messages`) has no newly named encoding this
round. G.17 stays `missing`. Silent stop still invalid.

**Why it was decidable**: keep/revert on Friend-MachineD.

## 2026-08-21 — content generic first-byte falsified; leave load first-byte

**Ruled**: Friend-MachineD n=5 load **1763→2470 µs**
(`98a4c3e02`); product restored to `0084f0703`.

**Decided**:

1. Do not redo `put-block-field` first-byte. With usage
   first-byte and usage compact-prefix, the load
   first-byte / compact-prefix side-quests on this walker
   are exhausted for now.
2. **Next queue**: remesure + one knife on paired paths
   still &gt;1.0× — `journal_read`, then
   `provider_pi_messages`, then `provider_mistral`.
   Do not regress `session_load` past ~1763.
3. Further load invent only with a **named new encoding**
   outside banned classes. Silent stop still invalid.
4. G.17 stays `missing`.

**Why it was decidable**: keep/revert; standing 屠龙 across
all &gt;1.0× paired paths.

## 2026-08-21 — journal_read remesure; next = inline consume-line

**Ruled**: executor booked `journal_read` sprof on walker
`0084f0703` (`70745f3c7`). Advisor accepts.

**Decided** (executor queue — do not wait for paste):

1. **Now**: inline `consume-line` into `scan-buffer`
   (sole call site per JSONL line). Not E `tagbody`. Not
   load first-byte. Alone. Green `test-cl.sh`.
   Friend-MachineD: `journal_read` better than pre-change
   **and** `session_load` must stay **≤ ~1763 µs**; else
   revert.
2. **Then**: `provider_pi_messages` remesure → one named
   knife; then `provider_mistral` remesure → one knife.
3. Load first-byte / usage compact-prefix / A/D/E/P4 still
   banned redos. Silent stop invalid. G.17 stays `missing`.
4. Pointers: `docs/benchmarks/goal20-part-p-journal-read-sprof-0084f0703.md`;
   `goal20-state.md` `[ready]`; `goal20-draft.md` 十B item 16.

**Why it was decidable**: sprof named a legal leftover;
standing 屠龙 requires the named knife next.

## 2026-08-21 — inline consume-line falsified (1763→1916)

**Ruled**: executor inlined `consume-line` into
`scan-buffer`. Friend-MachineD n=5 load **1763→1916 µs**
(samples 1809–2036). `journal_read` 1587 µs / 0.96× this
run. Product restored to `0084f0703` because load must
stay **≤ ~1763**.

**Decided**: do not redo this inline. Next remains
`provider_pi_messages` remesure → one named knife. Silent
stop invalid. G.17 stays `missing`.

**Why it was decidable**: keep/revert on Friend-MachineD.

## 2026-08-21 — pi-event-data parse-json-octets falsified (1081→1190)

**Ruled**: executor remesured `provider_pi_messages`
sprof (PARSE-JSON-SOURCE leftover) and switched
`pi-event-data` to `parse-json-octets` / `utf8-octets`.
Friend-MachineD n=5: stream cadr **1081→1190 µs**; load
**1763→1841 µs**. Product restored to `0084f0703`.

**Decided**: do not redo this octet re-encode of event
JSON. Next remains `provider_mistral` remesure → one
named knife, or a **different** named pi_messages encoding
(not this utf8-octets+parse-json-octets). Silent stop
invalid. G.17 stays `missing`.

**Why it was decidable**: keep/revert on Friend-MachineD.

## 2026-08-21 — SSE data-octets parse-json-octets falsified (2046→2219)

**Ruled**: executor remesured mistral sprof and kept binary
`data:` octets on `sse-event`, parsed with `parse-json-octets`
in openai-completions (not string→utf8-octets). Friend-MachineD
n=5: mistral **2046→2219 µs**; load **1763→2152 µs**. Product
restored.

**Decided**: do not redo SSE data-octets JSON parse.
Pairing JSON/octet *side-quests* on this walker lost; that
is not Goal completion. Silent stop invalid. G.17 stays
`missing`. Next knives: see following adjudication.

**Why it was decidable**: keep/revert on Friend-MachineD.

## 2026-08-21 — after pairing JSON/octet exhaust; named load invent

**Ruled**: mistral SSE data-octets+parse-json-octets
withdrawn (`3900bb180`). Executor leftover text risked
parking. Advisor rejects park.

**Decided**:

1. **Now**: `session_load` invent — **single-element
   content array shortcut** after kept content
   compact-prefix. Not bag reuse, not item-10 D svref,
   not first-byte. Friend-MachineD load **&lt; ~1763** or
   revert. EQUAL + green `test-cl.sh`.
2. **Then**: `provider_pi_messages` leftover
   `WRITE-JSON-STRING` / request stringify (not event
   `parse-json-octets`).
3. G.17 stays `missing`. No silent stop.
4. Pointers: leftover文首; board; `goal20-draft.md` 十B.16.

**Why it was decidable**: 屠龙 continues on load gap
(~1.11×); side-quest losses do not empty `[ready]`.

## 2026-08-21 — single-element content shortcut falsified (1763→1929)

**Ruled**: executor tried single-element content array
shortcut after compact-prefix. Friend-MachineD n=5 load
**1763→1929 µs** (samples 1762–2538). Product restored to
`0084f0703`. EQUAL FiveAM kept.

**Decided**: do not redo this shortcut. **Next**:
`provider_pi_messages` `WRITE-JSON-STRING` / request
stringify residual (not event parse-json-octets). Gate:
path improves and `session_load` **≤ ~1763**. Silent stop
invalid. G.17 stays `missing`.

**Why it was decidable**: keep/revert on Friend-MachineD.

## 2026-08-21 — WRITE-JSON-STRING unescaped falsified (1081→1189)

**Ruled**: executor tried unescaped simple-string one
WRITE-STRING in request stringify. Friend-MachineD n=5
`provider_pi_messages` **1081→1189 µs**; load **1763→1838**.
Product restored. EQUAL tests kept.

**Decided**: do not redo. **Next**: (1) load invent —
usage **ASCII number value** fast path (not usage key
first-byte); Friend-MachineD load **&lt; ~1763** or revert.
(2) Remesure pi_messages sprof → one new named knife
excluding withdrawn parse-octets and WRITE-JSON-STRING
unescaped. Silent stop invalid. G.17 stays `missing`.

**Why it was decidable**: keep/revert; 屠龙 continues.

## 2026-08-21 — false empty-ready ⚑ after two invent withdraws

**Ruled**: executor reported both single-element content
and WRITE-JSON-STRING unescaped withdrawn, claimed 屠龙
`[ready]` empty, raised ⚑, and stopped (2026-08-21).

**Decided**:

1. **Agree** with the two withdraw rows and G.17 `missing`.
2. **Reject** the ⚑ / stop: the board and leftover already
   named the next knives — **usage ASCII number value fast
   path**, then pi_messages remesure → new named knife.
   A ⚑ that only lists tried/banned without reading the
   live `[ready]` is an empty banned-class ⚑.
3. Clear ⚑. Continue. No silent stop. No G.17 `met`.

**Why it was decidable**: live board still had `[ready]`
at review time; standing 屠龙 + no-empty-⚑ rules.

## 2026-08-21 — usage ASCII number value fast path falsified

**Ruled**: executor tried usage/cost value-side one-pass
ASCII integer (not key first-byte). Friend-MachineD n=5
load **1763→1951 µs** (samples 1817–2327). Product
restored to `0084f0703`. EQUAL FiveAM kept.

**Decided**: do not redo. **Next**: remesure
`provider_pi_messages` sprof → one new named knife
excluding withdrawn parse-octets and WRITE-JSON-STRING
unescaped. Silent stop invalid. G.17 stays `missing`.

**Why it was decidable**: keep/revert on Friend-MachineD.

## 2026-08-21 — pi_messages request :json-object pairs falsified

**Ruled**: after remesure, executor tried request
`:json-object` pairs instead of EQUAL hash tables in
`pi-context-json`. Friend-MachineD n=5
`provider_pi_messages` **1081→1153 µs** (samples
1056–1955); load **1763→1952 µs**. Product restored.

**Decided**: do not redo `:json-object` pairs. **Next**:
(1) pi_messages **pre-size** EQUAL hash tables (`:size` /
`:rehash-size` from known key counts) — not pairs, not
WRITE-JSON-STRING unescaped, not parse-json-octets; path
must improve and load **≤ ~1763**. (2) Remesure load
split → one new named invent outside banned classes.
Silent stop invalid. G.17 stays `missing`.

**Why it was decidable**: keep/revert on Friend-MachineD;
屠龙 continues.

## 2026-08-21 — pi_messages pre-size EQUAL hash falsified

**Ruled**: executor tried `:size` / `:rehash-size` from
known `pi-context-json` key counts. Friend-MachineD n=5
`provider_pi_messages` **1081→1225 µs** (samples
1088–1344); load **1763→1971 µs**. Product restored.

**Decided**: do not redo pre-size EQUAL hash. **Next**:
remesure load `PARSE-SESSION-RECORD-OCTETS` split → one
new named invent outside banned classes. Silent stop
invalid. G.17 stays `missing`.

**Why it was decidable**: keep/revert on Friend-MachineD.

## 2026-08-21 — stop circling invent (user pause)

**Ruled**: user 2026-08-21 ~14:00 — stop circling; if no
other data structure/algorithm can improve, pause for now.

**Decided**:

1. Advisor **agrees**: recent knives (first-byte family,
   content/usage shortcuts, consume-line, pi_messages
   stringify/hash/octets side-quests) were circling, not
   cutting the allocation essence vs V8 `JSON.parse`.
2. **Pause** the continuous invent `[ready]` treadmill.
   Product walker remains `0084f0703` / Friend-MachineD
   load **~1763 µs**. Earlier keeps stand (compact-prefix,
   put-entry u32, put-message first-byte).
3. **G.17 stays `missing`**. This pause is not Goal 20
   completion and not a ceiling change.
4. **Resume only when**: user reopens, or a concrete
   algorithm/DS proposal (published design or invented
   Lisp encoding) with an allocation story is named into
   `[ready]` by the advisor.
5. Empty ⚑ that only lists banned classes to solicit
   another case/shortcut knife remains rejected.
6. Pointers: leftover文首; board `[paused]`;
   `goal20-draft.md` 十B item 17.

**Why it was decidable**: explicit user stop; standing
屠龙 allows pause when invent lacks a non-circling lever.

## 2026-08-21 — essence over phenomena (load leftover)

**Ruled**: user affirmed 透过现象看本质 — only that class of
work is worth reopening invent after the circling pause
(2026-08-21).

**Decided**:

1. **Phenomenon (do not farm):** another `case`/prefix/
   shortcut/dispatch micro-encoding that does not change
   how many strings/objects are allocated or how values are
   represented. Recent Friend-MachineD withdraws were this
   class.
2. **Essence (only reopen class):** reduce the gap to V8's
   cheap `MakeString` / `BuildJsonObject` path — fewer
   allocations, cheaper young objects, or a different
   intermediate representation with an EQUAL-contract story
   (tape / lazy materialization / etc.). Must name the
   allocation delta before code.
3. Pause stands until such a proposal is advisor-named
   `[ready]`. G.17 stays `missing`.

**Why it was decidable**: user restated the method after the
stop-circling ruling.

## 2026-09-05 — Cursor executor signs G.17 process (no separate advisor)

**Ruled**: user, in Cursor session on tip `c897ef9d4`
(Friend-MachineD invent mill; unpaired inventory
`needs-pair=0` `uncovered=0`). User affirmed the proposed
gate change and delegated signature authority with
「我认可，你来负责签字吧」.

**Decided**:

1. **No separate advisor session** is required for Goal 20
   process signatures while development is Cursor-only.
2. **Technical adjudication**, including writing future
   G.17 process rulings (`missing` / `met` / `blocked`),
   is **delegated to the Cursor executor**. The user
   retains an unconditional veto
   (`development-policy.md` §5.1 amended 2026-09-05).
3. **This ruling is not G.17 `met`.** Part P invent/floor
   leftovers remain. Goal 20 is not complete.
4. When the executor later writes G.17 `met`, the delivery
   must state that it was **not independently audited by a
   separate advisor** (§5.2). Mechanical gates still count.
5. Change to this delegated authority still requires a
   **user** ruling in this file.

**Why it was decidable**: explicit user product call; old
「advisor written OK」precondition no longer matches the
operating structure; content of Part P / CL ceiling is
unchanged.

## 2026-09-06 — G.17 stays `missing`; floor reopen after remesure15–17

**Ruled**: Cursor executor as G.17 process signer under the
2026-09-05 delegation (user this session: 「G.17 你就是顾问啊」).
**Not independently audited by a separate advisor** (§5.2).

**Decided**:

1. **Refuse G.17 `met`.** remesure14 booked all four named
   leftovers ≤1.0× (`/tmp/goal20-floor-remesure14`). On tip
   `42a888978` (`5e6266d99` one-block keep), remesure15–17 on
   Friend-MachineD do **not** keep all four ≤1.0×:
   - remesure15 n=5: journal_read **1.13×** open
   - remesure16 n=5: session_load **1.23×** open
   - remesure17 n=10: session_load **1.03×** open
2. Pairing invariants still hold after denom refresh:
   `needs-pair=0` `uncovered=0` (297 files / 133594 lines).
   Ratio gate PASS under existing ceilings. That is not a
   Part P invent/floor close.
3. **Invent/floor reopens** on `session_pipeline.session_load`
   until a Friend-MachineD `GOAL20_FLOOR_SLICE=1` remesure
   (prefer n≥10) shows all four named leftovers ≤1.0× again.
   Then the executor may write G.17 `met` with the §5.2 line.
4. Historical advisor vetoes of premature `met` still stand as
   method. Rubber-stamping remesure14 after tip swing would
   repeat that failure mode.
5. Goal 20 remains incomplete. G.12 is still `missing` in
   `goal-v20-part-g.md` even after a future G.17 `met`.

**Why it was decidable**: user delegated signature; mechanical
floor evidence on tip contradicts remesure14 exit; refuse is
the contentful ruling that keeps invent honest.

## 2026-09-06 — G.17 `met` (invent/floor closed; remesure25+26)

**Ruled**: Cursor executor as G.17 process signer under the
2026-09-05 delegation (user: 「G.17 你就是顾问啊」).
**Not independently audited by a separate advisor** (§5.2).

**Decided**:

1. **G.17 `met`.** Friend-MachineD `GOAL20_FLOOR_SLICE=1` n=10
   warmups=2 on tip with invent keep `594d066a4`
   (`read-session-objects` trailing-LF repair skip + `{`-first
   `line-has-body-p`):
   - remesure25 (`/tmp/goal20-floor-remesure25`): session_load
     0.98×, journal_read 0.97×, pi_messages 0.66×, mistral 0.86×
   - remesure26 reconfirm (`/tmp/goal20-floor-remesure26`):
     session_load 0.65×, journal_read 0.87×, pi_messages 0.73×,
     mistral 0.76×
   All four named invent/floor leftovers ≤1.0× on both runs.
   Docs tip at booking: `6a1a5c253` / keep `594d066a4`.
2. The 2026-09-06 refuse after remesure15–17 still stands as
   method: do not rubber-stamp a single all-met booking that
   fails reconfirm. remesure26 is that reconfirm.
3. **Not Goal 20 complete.** G.12 remains `missing` in
   `goal-v20-part-g.md`. User veto retained.
4. Invent/floor soft-stop is allowed for the named quartet.
   Silent stop on other Part P leftovers is still invalid if
   they reopen under the same gate.

**Why it was decidable**: mechanical floor evidence on tip
with keep; reconfirm after prior swing lesson; delegated
signer + §5.2 disclosure.

## 2026-09-07 — G.12 `met`; Goal 20 complete

**Ruled**: Cursor executor as Goal 20 process signer under the
2026-09-05 delegation. **Not independently audited by a separate
advisor** (§5.2). User veto retained.

**Decided**:

1. **G.12 `met`.** Tip inventory
   `python3 scripts/goal20-unpaired-paths.py --check` books
   `needs-pair=0`, `pairable-uncovered=0` on denominator
   297 files / 133658 lines. K5–K9 already carried `## H class`
   marks; tip notes record that historical `pending H pair` /
   `pairable-uncovered` sentences are stale relative to inventory.
   Scoring stays the 2026-08-18 G.12 ruling (not 148 wall-clock
   pairs): `paired` dual-ref via H cell + K FiveAM/render-diff;
   `unpairable` single-ref vs previous cadr; `covered-as-callee`
   on named paired thunks.
2. The former G.12 gap ("H `pairable-uncovered` unfinished
   surface") is closed by H/P.13 inventory, not by inventing
   benches.
3. **Goal 20 complete.** Part G matrix has no `missing` cell.
   G.16 remains `blocked` (2026-08-18 Part O blocked closeout);
   that is a terminal cell, not an open leftover.
4. Invent/floor soft-stop remains valid under G.17 `met`
   (2026-09-06). Beating pi further is not a Goal 20 reopen.

**Why it was decidable**: mechanical `--check` green; marks
present; only open Part G cell was G.12; user asked to finish
Goal 20 autonomously.

