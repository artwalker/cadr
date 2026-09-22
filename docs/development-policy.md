# cadr standing development policy

> **This file holds cross-goal constraints. It does not lapse when any single goal closes out.**
> Every goal document must cite it; before any development, confirm its constraints are understood.
> Changing this file requires user adjudication.

---

## 1. cadr is a Lisp program, not TypeScript written in Lisp (user adjudication, 2026-08-03)

The original text is `goal14.md` 0.5; goal 14 has closed out, so it moved into this standing file.

### 1. Alignment is defined as functional alignment

**"Understand what pi does, then implement it in Lisp" *is* alignment with pi**, and it is a better method than point-for-point correspondence. The criterion is observable behavior, not source structure.

Earlier practice leaned toward transcription not because of the alignment **standard** but because of the alignment **method**: goal 12 set the audit unit as "pi's 595 source files, each needing a corresponding cadr location" — **audit file-by-file and a structural mirror is the inevitable by-product**, even though that goal said in writing "this is not a line-by-line translation" and provided an "intentional difference" verdict class.

**The audit unit is observable behavior.** More "intentional difference" rows in `docs/source-parity.md` is the expected result, not a signal of drift.

**Performance is a separate question.** Same output bytes with a worse algorithm is still aligned as a product and still **wrong as a speed design**. See 4.5.

### 2. The price of divergence: losing mechanical drift detection

While structure corresponds, `scripts/check-source-parity-drift.sh` can **mechanically** list added, deleted, and renamed files after an upstream release and force a disposition out of each one — no understanding required, and nothing slips past.

Once structure diverges, that detector stops working: the only remaining question is "what behavior did this upstream change alter, and does cadr's differently-shaped implementation have that same behavior" — **which cannot be mechanized**.

This is not a theoretical risk. **This project has already confirmed that "a corresponding implementation exists" being true while "the behavior matches" is false is the hardest class of defect to find**: `read` line-number coloring, unabbreviated paths, per-provider OAuth browser prompt copy where cadr used generic copy, `/login` and `/export` showing an extra `Working...`, overlay title and border colors, a missing input cursor — **all four ledgers said "aligned", and every one of them was found by the user screenshotting a real terminal.**

### 3. Admission condition: however much structure you diverge, add that much behavioral assertion

**Structure may diverge freely, but every point of divergence must simultaneously gain a behavioral assertion of equal strength to the structure it replaced.**

Assertions must be **locked item by item against the baseline, never reverse-engineered from cadr's current implementation**. This project has already been burned here: thirteen full-screen snapshot SHAs stayed green for a long time while locking the wrong vertical alignment — because the SHAs were generated from the implementation of the day, not derived from baseline semantics.

**A divergence with no equal-strength behavioral assertion is not accepted, without exception**, however reasonable it may be in Lisp terms.

**A landed positive example**: the `provider-definition` declaration table in `src/cadr-ai/providers/definitions.lisp`, where each row carries `:baseline-source "packages/ai/src/providers/*.ts:NN"`, paired with a 38-provider × per-field baseline matrix gate.

### 4. The admission test: legitimate grounds for divergence (revised 2026-08-13)

**Why this was revised**: the original text of this item (established in goal 13 Part C2) explicitly rejected "more idiomatic Lisp" as grounds for divergence, on the basis that it "touches working code, takes on regression risk, and buys zero functional gain". **That basis held only while it was impossible to prove a change preserves behavior.**

**When the item was written that premise was true, and it can be checked item by item**:

```
Section 1 policy adjudication      2026-08-03
render-diff.py created              2026-08-04   e16881d3c   ← one day later
normalized text-layer gate          2026-08-08   3d71d27b9   ← five days later
```

That is, on the day the item was written, **the byte-level presentation differential did not yet exist**; the machinery capable of proving "this change preserves behavior" was built afterwards. As of this revision it is in place:

```
render-diff byte-level terminal comparison + normalized text-layer gate    141 required checkpoints
deterministic tests                                                        16,497 (test-cl.sh, nine suites)
four alignment ledgers                                                     behavior / source / non-functional / presentation
```

**The premise changed, so the conclusion changes with it.**

**User adjudication, 2026-08-13 (the governing principle for this item; every other clause is subordinate to it):**

> **The point is to write Lisp programs that exploit Lisp's advantages, not to expediently write TypeScript in Lisp. This applies to new and old code alike.**
>
> **Performance has no ceiling and a floor at the baseline**: the Lisp
> implementation must not be slower than pi on a paired path. Beating pi
> is the floor being met, not a reason to stop. The target is the limit of
> this SBCL image and live Lisp process without changing the product
> contract — cost and interactivity both. User ruling 2026-08-18: that
> whole programme stays inside the current goal; do not drip-feed knives
> through the advisor.

The two sentences together need spelling out: **"Lisp-native" is not a style preference; it is about actually obtaining what Lisp offers. A rewrite that obtains nothing is not Lisp-native, it is just a different spelling.**

**The criterion is the outcome, not a feature checklist.** The only test is: **can you state what concrete benefit this change obtained, and is that benefit checkable** (which repeated decision was removed, which hand-maintained invariant, which error path — or measured numbers). **"Used a macro" and "switched to CLOS" are not benefits, they are means** — a stated means with an unstatable benefit is the same as no grounds at all.

The following are **examples, not an exhaustive list, and certainly not a table you must match yourself against**:

```
macros and compile-time computation   remove repeated decisions; turn hand-maintained invariants into machine guarantees
CLOS and multiple dispatch            express contracts, method combination, organise by type instead of conditionals
the condition system and restart      recoverable errors and interactive handling, replacing layered error codes and sentinels
specialised arrays and declarations   buy speed and control over memory layout
symbols and the package system        namespacing, keyword arguments, compile-time symbol computation
dynamic scope                         pass context without threading it through every call
homoiconicity and the reader          describe rules as data instead of simulating data in code
REPL and incremental compilation      interactive development, redefinition in a running image
```

**Lisp's advantages are not limited to these, and this table grows as understanding grows.** Invoking an advantage not in the table **does not require prior adjudication** — state the benefit by the criterion above and that is enough; **invoking one that is in the table does not exempt you from stating it either.**

**Exploring which Lisp constructs to use is the implementer's responsibility, not an option.** The hard conditions in this item constrain the **evidence burden**, not the **means**: which construct to use, and whether to invent an approach this table does not list, **is the implementer's judgement and needs no permission**. Finding an advantage this table does not list and using it **is meeting the bar, not overstepping it.**

**Retreating conservatively to a literal translation of TypeScript syntax is a failure mode, not the safe choice.** This item lists many hard conditions and many prohibitions — if that leads you to conclude "copying the baseline's classes and files is least likely to be rejected", you have read the item backwards: **the cost of copying syntax does not show up in the gates, it shows up in the product** (slower, harder to maintain, none of Lisp's benefits obtained), and **no gate can catch "this could have been better but was not".**

Therefore: **when you cannot think of a Lisp-native *encoding*, you must say so honestly and escalate for adjudication; you must not quietly transcribe TypeScript classes, `nth` on lists, or `uiop:split-string` and move on.** The former is information that can be acted on; the latter is silent outstanding debt.

**Note that this class of debt is harder to find than the one in item 2.** Item 2 records "a corresponding implementation exists but the behavior differs" — the behavior differs, so a differential gate at least **has a chance** of catching it. Code produced by copying the baseline's *syntax* **behaves identically**: all four ledgers will necessarily be green and the byte-level differential will necessarily pass, and **it is structurally impossible for any existing gate to find it.** The only routes to discovery are the implementer reporting it, or someone re-reading the code later. **That is precisely why this item makes "say honestly that you could not think of one" an obligation.**

Conversely, **performance must not become an excuse for keeping a transcribed *encoding*** (cons lists for JS arrays, encode-the-string to count UTF-8). If a literal translation of the *algorithm* is faster than a Lisp encoding that dropped the data structure, that is an implementation problem: **restore the algorithm, fix the encoding**. Do not delete the data structure to chase a local allocation win (`0afb9660c`), and do not record that as "Lisp-native". If you cannot produce a Lisp encoding that matches pi's complexity and is not slower, **report blocked and escalate; do not default to a different algorithm.**

#### 4.1 New code: Lisp-native is an unconditional requirement

Writing new code **requires no grounds for divergence at all** — the admission test in 4.2 governs only rewrites of code that already works. The test in item 5 applies directly: point at any location and ask "why is it written this way", and **the answer must not be "because that is how pi does it".**

**But what is exempted is the *grounds*, not the *assertions*.** Item 3 applies equally to new code with no exception: **however much the structure diverges from the baseline, that much equal-strength behavioral assertion must be added, locked against the baseline and never reverse-engineered from the cadr implementation.** New code is inherently structurally different from the baseline, so it needs more assertions, not fewer.

Carrying the upstream data structure's semantics across as well **is not divergence; it is not writing it correctly**. A confirmed instance: `src/cadr-tui/mermaid/parse.lisp` simulated JS's `[...s]` with `(coerce s 'list)` and then indexed it position by position with `nth` — a JS array subscript is O(1), a CL list is O(n), so **the baseline's complexity semantics were not preserved**. That is neither "staying close to the baseline" nor a case for 4.2's admission test: it should simply have been written correctly.

#### 4.2 Rewriting code that already works: legitimate grounds and hard conditions

There are five legitimate grounds:

**remove a class of bug / remove a hand-maintained invariant / unlock a capability / substantially reduce code / the Lisp-native implementation is better**

The fifth is added by this revision. **The hard conditions come in two groups; within its applicable scope, not one condition in a group may be dropped.**

**Determine the scale first, then apply the conditions — a single blanket rule freezes every improvement in the name of "safety".**

| Scale | Definition | Condition 2 (performance evidence) | Condition 3 (ledger mappings) | When it may be done |
|---|---|---|---|---|
| **Point fix** | A correction inside one module whose edits can be enumerated one by one | Before/after measurement of that change | ≤10 mappings may be updated by hand, each with checking evidence | **Immediately**, without waiting for goal 20 |
| **At-scale rewrite** | Structural reorganisation of a whole module | Same, **and it must be covered by the performance regression gate** — ad-hoc measurement of a whole-module rewrite is unreliable | Must be recomputed mechanically | Once that module is covered by the regression gate |

**Condition 1 (assertions land first) applies to both scales with no scaling.**

**Scale is judged by the enumerability of the change, not by line count**: if you can state "which places changed and why each one changed", it is a point fix; if you cannot, and the module can only be carried off whole, it is an at-scale rewrite. **When in doubt, treat it as at-scale.**

The reason for this grading: holding point fixes to the at-scale threshold would freeze already-confirmed defects until after goal 20 — **and every extra day a transcription artifact survives is another day it gets copied**, with the untouched parts of the same module continuing to be written to the same wrong pattern.

**The cost of a point fix has a measured reference**: `src/cadr-tui/mermaid/canvas.lisp` misused `defconstant` on a string (reloading signalled `DEFCONSTANT-UNEQL`); it was found on 2026-08-13 and fixed to `defparameter` the same day — **one edit, zero behavior change, requiring no gate support at all.** Holding changes like that behind the at-scale threshold does not block risk, it blocks repair.

**Note the boundary with 4.1**: new code not yet in the build (for example `src/cadr-tui/mermaid/` at present) is governed by 4.1 — **that is "not written correctly", so fix it directly; this item's admission test does not apply.** This item governs only old code that already works and is already covered by gates.

**A. General hard conditions — these apply to any structural rewrite, whichever of the five grounds is invoked:**

1. **Equal-strength behavioral assertions land first, before the code is touched.** Adding tests afterwards is not allowed. Assertions must be locked against the baseline and **must not be reverse-engineered from the post-change implementation** (an existing requirement of item 3) — this project has already been burned here: thirteen full-screen snapshot SHAs stayed green for a long time while locking the wrong vertical alignment, because the SHAs were generated from the implementation of the day.
2. **Performance must be demonstrated by measurement to be no worse than two references: pi's same-path implementation, and cadr before the change.**

   **There is exactly one exception: no same-path implementation exists on the pi side** (a cadr-only capability, or no one-to-one counterpart after a structural divergence). In that case switch to the single reference "no worse than cadr before the change",
   **but the "no paired path" finding must first be established mechanically and booked; the changer may not declare it on the spot**
   (for the establishing mechanism see goal 20 Part H). **Using the single reference without that finding counts as not having discharged the evidence burden.** (User adjudication, 2026-08-13, restated 2026-08-18: **performance has no ceiling and a floor at the baseline** — not slower than pi on a paired path; beating pi is not a stop; the target is this SBCL image's limit. Experience uses the same bar.)

   **The evidence burden lies with the changer, not with the gate.** The byte-level differential looks only at output, never at cost: a rewritten implementation that is ten times slower will still leave all 141 checkpoints green; the performance gate currently has only absolute ceilings as well (measured headroom: cold start 4.85×, frame allocation 23.3×), with regression checks listed under goal 20 Part A/B. **So until the gates are complete, a change must carry its own before/after measurement** — you may not be excused from the evidence burden on the grounds that "the gate does not cover it", nor may you defer the change on the grounds that "the gate is not built yet".

   Measuring worse than either reference means the work is unfinished: **either fix it until it is not worse, or report blocked and escalate for adjudication**; it must not be recorded as "an acceptable trade-off".
3. **Source-ledger mappings must be updated inside the same change.** `docs/source-parity.md` currently holds **1,038 mappings pointing at cadr-side "file:line", covering 555 of 680 rows (81%)**. A rewrite invalidates them, and **a ledger that is not updated is lying** — item 2 already confirmed that "a corresponding implementation exists but the behavior differs" is the hardest class of defect to find, and an invalidated mapping means even "a corresponding implementation exists" is no longer true. The update method scales with size: **when at most 10 mappings are affected** (the typical magnitude of a point fix) **they may be updated by hand, but each must carry checking evidence** (that the post-change path and line really do point at that implementation); **above 10 it must be mechanized** (a script recomputes and validates), **never filled in by hand.**

   **No gate can currently find an invalidated mapping**: `check-source-parity-drift.sh` only compares additions, deletions, and modifications of pi-side `packages/**.ts`, and **does not check whether the cadr-side path still exists.** That gap must be closed before any at-scale rewrite begins (listed under goal 20 Part F); **point fixes are not blocked by this gap**, because their mapping changes can be checked one by one.

**B. Additional condition for the fifth ground:**

4. **Proceed module by module; no tree-wide campaign.** Before work starts, each module must account for: where the pre-change behavioral assertions are, how equivalence will be demonstrated afterwards, and where the coverage gaps are. **"Lisp-native" must not be the grounds for undertaking a single sweeping overhaul** — that is exactly what the original text of this item was written to prevent; this revision lifts only the blanket rejection of the *reason*, not the rejection of *campaign rewrites*.

**"The Lisp-native implementation is better" is itself a human-judgement exit, and the discipline of section 5 applies to it in full.** The catch-all clause in section 5 item 2 ("any future mechanism where recording a reason permits release") covers this item:

- **State the concrete improvements one by one**: what shape of transcription artifact was removed this time, what Lisp construct replaced it, and what was obtained as a result. **An assertive conclusion is not a statement** (e.g. "rewritten into a more idiomatic implementation").
- **Boilerplate is rejected**: within one batch, repeated reason text is a failure. **This project has confirmed this failure mode** — `docs/source-parity.md` currently holds **94 notes with an identical template** (normalized by stripping backticked paths and digits; the count of byte-identical notes is 0, and across the file 16 template families cover 347 of 670 rows), which, while declaring that "merely loading is not alignment", nonetheless marked a zero-coloring example as `implemented`.
- **Breadth warning**: when a single reason covers more than a majority of the modules, its proportion must be stated explicitly in the report.

#### 4.3 Handling the existing `Keep` verdicts in item 5

Item 5 records `cadr-cli` (96 files / 0 macros) and `cadr-tui` (23 files / 0 macros) as `Keep`. That verdict must be re-examined, for **two independently sufficient reasons**:

1. **The admission test changed** — the verdict was reached under the old test, when "Lisp-native" was not legitimate grounds.
2. **The audited surface is long out of date** — those two numbers are a 2026-08-04 snapshot; today they are `cadr-cli` 113 files and `cadr-tui` 43 files (macro count still 0). **119 → 156 in total, meaning about a quarter of the code has never entered a C2 audit at all.** For that portion no `Keep` verdict exists to invoke.

This revision **neither automatically overturns the old verdicts nor automatically makes them operative**:

- The reason that the CLI selectors "look alike but have different contracts" **is unrelated to this revision and still stands** — merging unrelated observable contracts is coupling, not Lisp-native design.
- But whatever part of that verdict rested on "Keep, because those are not legitimate grounds" **has lapsed and must be reconsidered under the new admission test.**
- **Re-examination must proceed module by module with a stated conclusion**; it may not be waved through with "C2 already ruled Keep", nor may this revision be used to launch a tree-wide rewrite.

#### 4.4 Still rejected

- **A rewrite with no equal-strength behavioral assertion**, however reasonable in Lisp terms (item 3's original text, unchanged).
- **A rewrite whose assertions are reverse-engineered from the post-change implementation** — that locks nothing at all.
- **Smuggling under the banner of "while I was in there"**: mixing unrelated style rewrites into a functional change, which destroys the ability to localise a regression.
- **A rewrite whose hard conditions are incomplete**, however sufficient the grounds. **General hard conditions 1–3 apply to all five grounds**, with no exemption for invoking a hard ground such as "removes a class of bug".

**The test (revised)**, in two steps, both required:

1. **Grounds**: you can state what concrete harm this change removes (the first four grounds), **or** you can state why the post-change code is a better Lisp implementation, specifically enough to be checked (the fifth ground).
2. **Conditions**: general hard conditions 1–3 are complete; **if the fifth ground is invoked, additional condition 4 must be complete as well.**

**Grounds without complete conditions: do not proceed. Complete conditions with unstatable grounds: likewise do not proceed.**

### 5. What has and has not crossed the line (as of 2026-08-04)

**Crossed**: the extension API (the 15 `define-*` macros in `src/cadr-agent/extensions/registration.lisp`, 15 of the tree's 17 macros), the provider declaration table, and the `cadr-core` failure-safety primitives.

**Not crossed**: `cadr-cli` (96 files / 0 macros) and `cadr-tui` (23 files / 0 macros). **But those zeros are not outstanding debt** — the C2 audit ruled `Keep` and the reasoning held: the TUI's use of CLOS is already the strongest in the tree; the CLI's selectors **look alike but have different contracts** (search, paging, and cancellation rules all differ), and merging them would couple unrelated observable contracts.

**The test**: point at any piece of *product* structure (files, classes, control-flow spelling) and ask "why is it written this way"; the answer must not contain "because that is how pi does it". Point at a *computational* structure (random-access lines, `Buffer.byteLength`, `JSON.parse` passes) and the answer **must** be able to name the pi function it matches, or say why cadr's is strictly better *and show the number*.

### 6. Performance work copies pi's algorithm (user 2026-08-19)

**Product alignment** stays item 1: observable behavior, not source files.

**Speed design** starts from the pi production function for that path: its passes and its data structure. Encode those in Lisp (`simple-vector` / fixnum index / octet window / typed walk). That encoding **is** Lisp-native. Deleting the data structure because the first encoding allocated **is not**.

sprof is a diagnostic of an implementation that already has the right algorithm. A profile of a worse algorithm does not authorize a third scan. Open the pi source before the next lever.

Confirmed instance: `truncateTail` is `byteLength` + `split("\n")` + index from the end. cadr had `uiop:split-string` (right algorithm, list encoding), then `0afb9660c` scanned instead. Output bytes still matched. Friend-MachineD tail still 1.30×. Audit: `docs/acceptance/goal-v20-ds-audit.md`.

Forbidden as the next knife on a leftover path: FFI to `Buffer` / simdjson, intern-table growth, empty SWAR, `uiop:split-string` as a "copy" of JS `split`.

---

## 2. Code quality and organization are standing constraints (user adjudication, 2026-08-03)

The original text is `goal14.md` Part D item 5.

**The purpose is not to control file size; it is to stop the same decision being re-made by hand an Nth time.**

`interactive-services.lisp` was not written as 9,063 lines in one sitting; the three places where `join-thread` lacked a timeout were not written at once either — both accumulated from "just this one more, right here is most convenient", **and not one of those steps tripped any threshold.**

**So whenever a goal involves new code, before work starts it must account for**:
1. which file the new code belongs in, and why;
2. **whether an existing primitive was reused rather than hand-implemented again.**

**The limits of what gates can do**: automated detection can stop "a huge new file", but it **cannot stop "appending to an already-acceptable file until it exceeds the limit"**, and it cannot stop "that decision was hand-copied once more". The latter rests on judgement at development time, not on gates.

**Bug families confirmed to be caused by hand repetition** (see the repeated-decision table in `docs/code-organization.md`): shutdown deadlock (`join-thread` missing a timeout in three places), diagnostics leaking four times (setsid / ASDF / SSL / `session>`), spacing deviations, wrong Anthropic prompt copy, crash backtraces leaking session state, `write` counting UTF-8 bytes, and export filenames deviating from tree timestamps.

---

## 3. Other constraints that remain in force (index)

- **Full parity, no crippling**: whatever pi has, cadr must have; missing credentials only lower the verification tier (fixture comparison), they never shrink scope.
- **Credential discipline**: API keys and OAuth tokens never enter transcripts, logs, or session files; `auth.json` is forced to `0600`; crash logs must be redacted and `0600`.
- **Build-it-ourselves principle**: TLS via cl+ssl is the sole cryptography exception; new third-party dependencies require prior review, and a blocked report escalates to the user for adjudication.
- **New mechanisms require adjudication**: any idea that is "an addition relative to the original" goes into `docs/open-questions.md` for user adjudication; it is not implemented by default.
- **Definition of done**: committed and booked, and the announcement must carry evidence that can be verified by hand (source location, test name, gate output). Declaring completion yourself is void.
- **Baseline pinning**: pin the upstream release tag (currently `v0.87.0 (+0, 16787ad5b)`); do not chase a moving development branch.

---

## 4. Product identity has exactly one decision source (user adjudication, 2026-08-05)

The product slug, display name, canonical repository URL, and default share viewer may be owned only by the private product-identity constant group in `src/cadr-ai/support/release.lisp`. Other production owners may only derive from that group; a second copy of the product identity must never be hand-written into an HTTP header, User-Agent, OAuth parameter, user-facing copy, exported artifact, temporary file, thread name, or example.

Environment variables and configurable endpoints are held by their respective feature owners, but the Cadr runtime accepts only the `CADR_*` namespace. The old `PI_*` may appear only in migration documents or the fixed-baseline driver, and must never become a fallback, an alias, or a warning-based compatibility layer.

External contracts and baseline provenance are not product self-identification. Radius client/API/wire, extension manifest schemas, catalog sources, historical text, and fixed comparison inputs that genuinely must be retained must each enter `docs/product-identity-allowlist.json` individually, with an exact file, exact line, fixed token, occurrence count, and a non-empty reason. Directory, glob, or generalised-regex exemptions are forbidden; opaque third-party assets may be pinned only by exact path, SHA-256, and reason.

`scripts/check-product-identity.py` rejects unregistered hits, stale or duplicate dispositions, count drift, manifest-total drift, and opaque-digest drift alike. `scripts/verify.sh` must run the synthetic self-test first and the real repository second; a failure of either blocks the deterministic gates that follow. Adding to or changing the allowlist is equivalent to changing the product-identity boundary, and requires a written proposal and item-by-item user adjudication first; it may not be released on your own authority as "just a comment / an internal name".

## 5. A gate's human-judgement exits must be checkable (user adjudication, 2026-08-08)

### 1. Why this exists

This project has produced the same shape of incident three times — **the gate correctly detected the problem, and the human-judgement layer explained it away**:

| Incident | Detection | How the exit was used |
|---|---|---|
| goal 8 OAuth live | The test correctly failed | Used `jq` to rename a credential key so the test would pass, bypassing the defect itself |
| goal 17 presentation differential | `overlays-auth-oauth/login-dialog` correctly captured two different SHAs for pi and cadr | Closed with `I01`+`I04` and one boilerplate note, while cadr was actually missing `Enter code:`, `Waiting for authentication...`, the title, and the container — none of which either class covers |
| goal 17 coverage unit | —— | The obligation unit was changed from a runtime Cartesian product to fixed fragments, printable branches 1108→672, and a perfect score was declared under the new definition in the same commit |

**What these share is not dishonesty** (all three actively disclosed the unfavourable data), but this: **faced with "fix it properly" versus "rule it acceptable", the exit is the path of less resistance.** So what is constrained here is the exit itself, not anyone's attitude.

### 2. Scope

Every human-judgement exit in this project is covered alike: the intentional-difference verdicts in `test/fixtures/render-diff/dispositions.json`, `visible-string-exemptions.json`, `docs/product-identity-allowlist.json` (detailed separately in section 4), the N/A verdicts in `docs/parity-map.md`, the `Evidence / reason` column of `docs/source-parity.md`, live gate skip conditions, and any future mechanism where recording a reason permits release.

### 3. Mandatory fields for each exit record

1. **A concrete statement of the actual difference or violation** — it must state what pi and cadr each are at this point, or why this one does not apply. **An assertive conclusion is not a statement** (e.g. `no product defect is admitted`).
2. **Why the cited class covers that difference word for word** — the class summary must be able to explain the stated difference word for word. **Whatever it cannot explain is a defect and must be fixed; it must not be absorbed in passing by that class.**
3. **Evidence** — comparison-type exits must carry both sides' digests or equivalent evidence; an entry without evidence does not stand.

### 4. Three things a gate must be able to check itself

1. **Boilerplate is rejected**: within one exit file, repeated reason text is a failure. A reason is the product of a per-item judgement; repetition shows the judgement was not made per item.
2. **A class must not absorb across layers**: a class describing a byte-level difference (such as `I01`'s ANSI segmentation and teardown sequences) must not be used to close a **visible-text-level** difference. A comparison must first normalize both sides into a visible-text grid and compare again; **a checkpoint whose normalized text differs may not be closed on a byte-level class alone.**
3. **Breadth warning**: when a single class covers more than a majority of the exit entries, its coverage proportion must be stated explicitly in the report. A catch-all class is not necessarily wrong, but it makes that gate's strength equal to that class's rigour, which must therefore be visible.

### 5. New classes and changes of criteria require prior adjudication

**Adding an intentional-difference class is equivalent to changing the definition of "alignment"**; **changing a gate's obligation unit or counting basis** (such as the denominator of a coverage figure) **is equivalent to changing what the gate promises.** Both require a written proposal first; neither may be self-authorised, and neither may change the criteria and declare compliance under the new criteria in the same commit. Before adjudication, figures under the new criteria may not serve as acceptance evidence.

#### 5.1 Who adjudicates (user adjudication, 2026-08-15; amended 2026-09-05)

**Standing form (2026-08-15):** the advisor adjudicates; the user retains
an unconditional veto. That recorded practice for a two-session structure
(executor + separate advisor).

**Amendment (user 2026-09-05, Cursor-only development):** when work runs
in a single Cursor session with **no separate advisor session**, the user
delegates technical adjudication (including Goal 20 G.17 process
signatures) to the **Cursor executor**. The user keeps an unconditional
veto. A change to that delegated authority still requires a user ruling
in `docs/adjudications.md`.

This amendment does **not** mark G.17 `met` and does **not** close Goal 20.
When the executor later writes a G.17 `met` ruling, the delivery must state
plainly that it was not independently audited by a separate advisor
(§5.2). Mechanical gate evidence still stands.

Three consequences, all binding:

1. **A ruling lands in the artifact it rules on.** Writing it only into a
   working state file is not a ruling: the next reader opens the proposal,
   sees "awaiting adjudication", and either waits or re-litigates it. The
   proposal's `Status:` line must carry the verdict, the date and who
   ruled. This was violated once already — the I04 proposal sat at
   "awaiting adjudication" for a day after the ruling was made.
2. **Durable rulings are committed.** Anything that still constrains
   someone after the goal closes out goes into `docs/adjudications.md`,
   which is tracked. A goal state file is disposable scratch; it is
   gitignored, and one `git clean` would destroy the entire rationale layer
   while every gate stayed green.
3. **Neither advisor nor Cursor executor may self-authorise a change to
   adjudication authority.** Those go to the user. The 2026-09-05 Cursor
   delegation is itself a user ruling.

#### 5.2 Role boundary: executing and auditing are different hats (user adjudication, 2026-08-15)

The two-role structure works because a doer and an independent checker are
different people. It stops working the moment the checker becomes the doer.

**An item the advisor executed is not audited by the advisor.** Either the
user audits it, or the delivery states plainly that it has not been
independently audited. Mechanical gate results (test counts, gate exits,
digest comparisons) remain valid evidence in either case — they are
produced by machinery, not judgement. What may not be claimed is the
judgement layer: that the work was reviewed by someone who did not write
it.

Applied retroactively on the day this clause landed: the goal 20
documentation translation (`e8cbfaec9`, `4c8e31416`, `7dd90672c`,
`7cf6c3ca7`, `6f073134e`, `860c075cd`) was executed by the advisor. Its
gate evidence stands; **its review does not, and it is recorded here as not
independently audited.**

### 6. Reports must distinguish "drive completeness" from "conformance"

Coverage-type metrics must state what they measure. Example: the construction suite for `baseline-visible-strings` is TypeScript and drives the fixed-baseline pi, so **its 672/672 measures how completely the scenario set drives the baseline's branches, not cadr's conformance**, and it is structurally incapable of finding a string cadr is missing. For every metric of this kind, the report must state the measured object honestly and must not present it with a stronger meaning.

### 7. A gate result names the state it measured, and that state is a commit

A green run proves something about the tree it ran in. When the repository is
being edited concurrently, **the working tree is not any commit** — it is the
author's current desk. A gate run there attests to a state that no reviewer can
check out and that will never be pushed.

**So a gate result that will be quoted as evidence is produced in a clean
checkout of the commit it speaks for**, and the report names that commit:

```
W=$(mktemp -d); git worktree add -q "$W/h" <commit> && (cd "$W/h" && ./scripts/test-cl.sh)
```

**Why this is written down** (advisor, 2026-08-16): the advisor reported
`18589/18589` for a batch of ported commits, having run the suite in the live
working tree while the executor was mid-edit. **`HEAD` had been red for twelve
commits at that moment** — a hand-pinned count in
`test/cadr-cli/goal12-examples-test.lisp` disagreed with `docs/source-parity.md`
after a legitimate reclassification changed the ledger and not the pin. The
executor's uncommitted fix was on disk, so the run was green and the claim was
false. This is the second instance of the same error; the first read a
working-tree file count as evidence about a script's behaviour while the same
file was being edited.

**A related trap in this repository's own harness**: `scripts/test-cl.sh` does
not print `cadr test summary` when a suite aborts — it emits
`incomplete FiveAM accounting; expected exactly 9 suite summaries`. Grepping
only for the summary line therefore returns nothing on failure, which reads as
"the run did not happen" rather than "the run failed". **Green means nine suite
summaries were seen, not that no failure line was found.**

## 6. Standing uses of Lisp's capabilities (advisor investigation 2026-08-13; user adjudicated it into standing form)

**This section records practices, not any one goal's tasks.** goal 20 Part N is their first engineering application; **this section remains in force after Part N closes out.** Every item adds zero dependencies (`sb-introspect`, `sb-mop`, `trace`, `sb-cover`, and `sb-sprof` all ship with SBCL; slynk was approved by `OQ-G10-D2-SLYNK-REPL` on 2026-08-01 and ships with the image).

### 1. Diagnosis: pick the instrument by where the state lives, not as a last resort after guessing

**Use Lisp's live image. Do not add Lisp machinery to look native.**
User ruling 2026-08-18: fully use the advantage; do not stretch constructs
for their own sake. "Could almost name it from source" is not a reason to
skip Slynk on a running process.

```
./cadr --slynk <port>       starts a loopback-only server; in the REPL (cadr-cli:active-agent)
                            returns the running agent object, and reproducing to the failure leaves that state live
(trace some-function)       shows calls and returns without editing code, answering "which branch was taken"
```

**Which tool:**

- **`--slynk <port>` and SLY first** when the reproduction vehicle is a
  running cadr process (interactive TUI, `--mode rpc`, or a live provider).
  Inspect `(cadr-cli:active-agent)`, slots, queues, and the condition.
  Redefine and continue; do not kill the process to "see if it happens
  again". Source reading may suggest a hypothesis; the live image is the
  diagnosis.
- **`asdf:load-system` and call the function** (item 2) when the state is a
  function of constructed inputs — no live session, no TUI reader thread,
  no provider round-trip.
- **`(trace …)`** when the question is which branch ran, and the inputs are
  already known.
- **Forbidden substitute:** writing "slynk is the same query as
  load-and-probe" for a defect the user reproduced in a live process.
  Load-and-probe may *lock* a reconstructed snapshot in FiveAM; it is not
  the diagnosis of that live trigger. (Part L/N recorded this miss.)
- **Forbidden cargo-cult:** extra `restart-case` / hooks on pairable
  user-visible failure paths "to use Lisp"; spraying `fixnum`; treating
  Slynk as a second test runner.

**Restarts at a live tool failure** (Goal 10 D1; already in the image,
default-off for interactive picking):

- With Slynk attached, use `retry-tool-call` / `skip-tool-call` /
  `abort-agent-run` at the condition site. That is the Lisp advantage:
  the stack is still live.
- Without a `:tool-call-error` hook, the default product path still emits
  the error result (parity with pi). Do not add hooks or extra
  `restart-case` on pairable wires "to use Lisp".
- A test that claims restart behavior must invoke the restart, not only
  assert `fboundp`.

**After a Slynk session, the lock is FiveAM** (or the matching
deterministic gate). A pasted REPL snapshot is evidence in the report, not
the gate. Credential discipline of section 3 still applies — no API keys
or OAuth tokens in the REPL, logs, or the report.

**This item does not apply to every edit.** Pin/ledger commits and K
rewrites whose before/after is already a red/green FiveAM on constructed
inputs stay on item 2. Slynk is for live-process defects, not a second
test runner.

### 2. Development loop: load and probe first, before rebuilding a whole image

For change-one-thing-verify-one-thing work, **prefer `asdf:load-system` to load the subsystem and call the function directly**, rather than rebuilding the release image. Measured cold-cache load of `cadr-ai` (61 files / 25,818 lines) is about 12 seconds; for how to write it, see the isolated `HOME` and `ASDF_OUTPUT_TRANSLATIONS` pattern in `scripts/test-cl.sh`.

### 3. Ledgers and gates: whatever the image can answer must not be maintained by hand

- **Derive symbol locations with `sb-introspect:find-definition-sources-by-name`**; do not hand-write "file:line". **Hand-written mappings necessarily rot** — this project has confirmed it: 108 of `source-parity.md`'s 1,038 hand-written mappings had rotted, across five closeouts, with nobody noticing.
- **Drive declaration-table field comparison from `sb-mop:class-slots` enumeration**; do not hand-list fields in a test. **Hand-listing necessarily misses** — this project has confirmed it: the provider matrix gate compared only 6 of 21 fields, and the one it missed was `default-model`, where the defect was.
- **Exclusions must be carried by declarations too**, not scattered through test code.

### 4. Compiler warnings are a free source of defects and must be heeded

**cadr's own compilation WARNINGs count as defects**; a new one fails the gate. STYLE-WARNINGs are only counted and booked for now. Third-party dependencies' warnings do not count against our own account.

**Two accompanying rules; without either, this item can be hollowed out**:

- **Suppressing a warning is equivalent to manufacturing a defect**: adding any `muffle-conditions`, `muffle-warning`, or `declaim` suppression aimed at cadr's own code **is itself a gate failure**, unless declared item by item and adjudicated. (The two existing muffles in `src/cadr-cli/extensions/loader.lisp` are for **loading user extensions** and do not cover cadr's own compilation, so they are legitimate.)
- **Attribution needs a mechanical standard**: a warning triggered by a third-party macro expanding inside a cadr source file will point at cadr's `.lisp` as its source location. **The standard for "ours vs third-party" must be written down and mechanized**, not eyeballed; whatever cannot be classified **counts against our own account** (better a false positive than a miss).

**The reasoning is measured**: the project went a long time without addressing compiler warnings, and loading `cadr-ai` alone produced 3 real WARNINGs — `release.lisp` wrapped `defparameter` inside `multiple-value-bind` (not toplevel, so the compiler could not obtain the compile-time declaration). **The compiler had been shouting all along; nobody was listening.**

### 5. Performance: declarations need measurements, profiles are not criteria

- **Add type declarations only on hot paths**, and **every one must come with measured numbers from before and after.** **A declaration whose improvement you cannot state is not added** — declarations sprayed across the tree are noise, not quality.
- **Lowering `safety` for speed requires a proposal and adjudication first**: that trades crash risk for performance, which changes the product's failure characteristics.
- **An `sb-sprof` profile is a diagnostic tool, not a criterion.** The criteria remain the regression gate and the paired benchmarks; **"X% slower" is not an actionable conclusion**. A path that misses the bar must attach a profile **of an implementation that already uses pi's algorithm** (section 1 item 6). A profile of a scan that replaced `split` / an array does not authorize another scan.

### 6. Capabilities examined and excluded (raising them again requires refuting the reason first)

**Note what this table means**: what is excluded is **treating the capability as a quality or diagnostic mechanism**; it **does not forbid using it in the implementation** — two entries in the table are in normal use right now.

| Capability | Reason it is not used as a quality/diagnostic mechanism |
|---|---|
| `sb-posix` (currently used in 13 files), `sb-bsd-sockets` (6 files) | **In use, and should stay in use.** They are utility libraries; **what this table excludes is only the use of them as a quality or diagnostic mechanism**, not their use at all |
| `sb-md5`, `sb-rotate-byte` | Unused and not needed; utility libraries, not quality or diagnostic mechanisms |
| `sb-cltl2` (compile-time environment queries) | Serves code generation for macro authors; this project has no corresponding need |
| `sb-introspect:function-lambda-list` (signature introspection) | cadr's structure is permitted to diverge under section 1, so signatures should not correspond one-to-one with pi's in the first place |
| The condition system for the agent's own error handling | That changes the product's observable failure behavior, so it goes through adjudication rather than being treated as a development tool |
| `save-lisp-and-die` to dump a failure image | Roughly 20 MB each; slynk live evidence capture covers the same need and is lighter |
| `sb-ext:lock-package` to isolate extensions | See `OQ-G20-EXTENSION-ISOLATION` in `docs/open-questions.md`: **cadr's existing isolation is already stronger than pi's** (pi has no sandbox), so locking buys no security pi lacks |

## 7. Concurrent agents (user 2026-08-18)

**Throughput is allowed. Two writers on one tree is not.**
This repository already forbids `git add -A` because several sessions
may share a cwd. Multi-agent is the same constraint, scaled: extra
agents help only when they do not create a second owner for one
decision, one pin, or one file.

### 1. What may run in parallel

- **Read-only**: review a named SHA, sprof/cover in a throwaway
  worktree, baseline lookup, draft a proposal. Same cwd is fine if
  the agent does not write tracked files.
- **Disjoint writers**, each in its **own git worktree** cut from the
  same SHA, with an ownership table posted *before* spawn: paths it
  may touch, paths it must not, commit-message prefix.
- **Serial integrate**: one merge onto `cadr-migration` at a time,
  `test-cl.sh` on that commit, then the next worktree rebases. Do not
  merge four speedups and then measure. The live crew is Cursor cloud
  agents (not Grok Bot). Goal 20 leftover pairing PRs are merged by a
  Cursor cloud agent (GitHub merge, one PR at a time); see
  `docs/acceptance/team-dev-platform.md`.

### 2. Single-writer mutex (never parallel)

Pins, ledgers, and "one user-visible decision / one owner"
(`docs/code-organization.md`) are the product. Concurrent edits here
are how identity strings, FiveAM anchors, and `RATIO_CEILINGS` drift:

- `CHANGELOG.md` Unreleased, `docs/performance.md` paired tables,
  `docs/test-matrix.md` / FiveAM anchor, lispification identity,
  unpaired-paths denominator, `RATIO_CEILINGS`, source-parity
  mappings, `build-support.lisp`
- Any file already dirty in another session's cwd
- Two Lisp-native rewrites of the same module
- Two JSON-parser probes, two overlay owners, two "add a helper in
  `cadr-core`"

The main executor is the only writer on mutex paths. A subagent that
needs a CHANGELOG line returns the sentence; the executor types it.

### 3. What is not "using agents well"

- Spawning write-subagents into `/root/projects/cadr` (or any shared
  checkout) while the executor or advisor is also editing
- `git add -A`, stash, `reset --hard`, cleaning the other session's
  files
- Each agent inventing a parallel helper for the same job
- One test run after a pile of merges (Part P needs one lever per
  commit with numbers)
- Calling "we used five agents" a quality signal

**Why this is written down**: 2026-08-18 the advisor and the executor
shared one worktree — docs hunks and tic-tac-toe Lisp dirty at once.
That is the failure mode. Worktrees exist so gate evidence names a
commit (§5.7); they also exist so two writers never share a desk.
