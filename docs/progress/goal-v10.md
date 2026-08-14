# GOAL v10: backup, catching up with upstream, CI, Lisp-native capabilities and the first release

> **Completion status (2026-08-01)**: the code, tests, ledgers and release
> materials for Parts A–E have all been committed, and the final
> `./scripts/verify.sh` is fully green. Part B is a no-op per user
> adjudication; upstream is no longer polled. Goal 10 is complete within the
> established boundary of "preparation finished, public release awaiting
> confirmation"; neither the `v0.2.0` tag nor the GitHub Release has been
> created, and each must be explicitly authorized separately by the user.

## 0. Positioning and general rules

> **2026-08-01 execution-order adjudication**: after Part A passed acceptance,
> the order was adjusted to `C → B (waiting for v0.84.0) → D → E`. Part C has zero
> dependency on Part B. The user then made it explicit: Part D's written
> proposal may go first while waiting for `v0.84.0`; "B must precede D"
> constrains only Part D's implementation, avoiding the parity ledger mixing in
> the old baseline. If `v0.84.0` has not been released by the time Part C is
> finished, Part B stays suspended, and the lock must not be changed to HEAD.
> Part B's bearer-token SHA-256, fixed-length comparison and socket suffix
> minimal implementation surface are pre-authorized per section 0 of
> `docs/proposals/goal-v10-part-b-baseline.md`; a new cryptographic dependency
> or anything beyond the approved file surface must still be blocked.
>
> **2026-08-01 Part D adjudication**: D1 condition/restart, the D2 Slynk
> capability and D2's exact dependency closure have all been approved item by
> item, but the implementation must still wait for Part B to finish. D1 is
> permitted to add the 34th extension event `:tool-call-error`, which lifts
> Goal 8's "cap of 33" for this one complete proposal only; after
> implementation it is re-frozen at 34 events, and any future addition must
> still go through a new proposal and item-by-item adjudication. D2 must be off
> by default, may be turned on only explicitly from the CLI, and must listen on
> a fixed `127.0.0.1`; the build and the deterministic tests must use a
> brand-new empty temporary `HOME` to prevent the build machine's `.slynkrc`
> side effects from entering the image. The full adjudication is in
> `docs/proposals/goal-v10-part-d-lisp-native-capabilities.md`. The
> implementation and the re-freeze are complete, and the acceptance evidence is
> in `docs/acceptance/goal-v10-part-d.md`.
>
> **2026-08-01 Part B final adjudication**: Part B is closed as a no-op.
> `v0.83.0` (`845d6ff1f`) is 38 commits behind the current `74caa2649`
> baseline and is missing `packages/protocol` and 11 test files; there is no
> release tag ahead of the current baseline, so there is no usable upgrade
> point. The tag policy is amended to "lock to a release tag if one is ahead;
> otherwise keep the current baseline and state the version relationship
> honestly". Upstream must not be polled any further. The execution order
> becomes `Goal 11 → D → B(no-op recorded in the ledger) → E`, in which Goal 11 and D are already
> complete.

- **Only after all Parts of goal 9 (A/A2/B/C/D/E) have passed acceptance** may this goal begin.
- This goal gathers up every outstanding item after goal 9, and **accepts no scope reduction**: anything with a large workload is split into more Parts and advanced in order; it must not be moved out of scope or pushed onto a later goal. The only legitimate form of scope reduction is to mark it blocked, state the reason, and escalate for user adjudication.
- Parts advance automatically, without waiting for user instructions. **Only three classes of situation are blocked**: (a) a new third-party dependency; (b) a cryptographic path beyond the existing adjudication; (c) a new-capability proposal that has not been adjudicated (specific to Part D).
- **Complete = committed and recorded in the ledger**; a declaration of completion that has not been committed is void. Credential discipline is unchanged: no key or token enters the code, the fixtures, the logs, the reports or the remote repository.

## 1. Part A: remote repository and off-site backup (highest priority, do it first)

**Background**: from v1 until now all work exists only on this machine's disk, with no off-site copy, which is a single point of failure. `gh` is already authenticated as `artwalker` (scopes: repo, workflow).

1. **On 2026-08-01 the user explicitly authorized Codex to create the repository, push the code and configure CI on its own** (outward-facing actions; the scope of the authorization is strictly limited to this section and Part C, does not extend to any other outward-facing operation, and in particular does not include making the repository public or publishing a Release):
   - `gh repo create cadr --private --source=/root/projects/cadr --remote=backup`
   - Push all branches and tags: at least `cadr-migration` (the main line) and `pi-mono-legacy` (the historical anchor).
   - **The remote must be named `backup`, and the existing `origin` must not be changed or overwritten** (origin still points at upstream earendil-works/pi, and the user's `git pull` habit must not be broken).
2. **The repository must be private.** Whether it is public is the user's independent decision, and this goal must not change it to public.
3. Self-check before pushing: confirm that `~/.cadr/auth.json`, any key/token, `.tmp-home/`, `.codex` and the build artifacts are all outside the tracked tree; push only after `.gitignore` is complete. **If any credential is found to have entered a historical commit, block immediately and report; history must not be rewritten on your own authority.**
4. Verification after pushing: `git -C /root/projects/cadr ls-remote backup` can list the expected branches; `git clone` a copy into a temporary directory and get `./build.sh` to run through, proving that the backup is usable and not merely reachable.
5. The report records the repository URL, the branches and tags that were pushed, and the verification commands and their results.

## 2. Part B: catching the baseline up with the latest upstream

**Final state: no-op, closed.** The original requirements are superseded by the
2026-08-01 user adjudication above; the full counts, the basis of the verdict
and the existing `362 C / 0 U / 0 M / 1 N/A / 363` conclusion are in
`docs/acceptance/goal-v10-part-b.md`. This Part changed no baseline, fixture,
source code or parity classification.

**Historical ordering constraint**: the original requirement was that Part B
must be finished before Part D, to prevent the parity ledger from mixing in an
upstream displacement. After the 2026-08-01 adjudication confirmed that there
is currently no usable upgrade point and closed Part B as a no-op, that
precondition is satisfied; the original steps below are retained only as a
historical design, and this goal does not execute them.

1. **The baseline must be locked to an upstream release tag, no longer to the tip of a development branch** (user adjudication, 2026-08-01). Take the latest stable tag of `earendil-works/pi` at the moment of execution (such as `v0.84.0`), record its tag name and the corresponding commit hash, and write both into the report and into all documents; the old baseline `74caa2649` is demoted to a historical anchor (`71efc6f0` is still retained as the original anchor).

   **Background and rationale**: both previous baselines were in-development commits after a tag — `71efc6f0` is `v0.83.0-1` and `74caa2649` is `v0.83.0-38`, while HEAD at that time was already `v0.83.0-130` and was midway through a rework of the session storage layer (`jsonl-repo`+`jsonl-storage` → `jsonl-store`, `memory-repo`+`memory-storage` → `memory-store`, the new `repository.ts`/`fork.ts`/`keyed-operation-queue.ts`, `storage.test.ts` → `session-backends.test.ts`). The benefits of locking to a release tag: the release point no longer moves and has usually converged, so it will not run into a half-finished architectural displacement; "cadr is aligned with pi v0.84.0" is communicable and reproducible; and every upstream release is a natural decision point for an upgrade.

   If at execution time the gap between the latest tag and upstream HEAD is too large (for example the tag is already hundreds of commits behind and the user explicitly wants a feature that exists only on HEAD), mark it blocked and escalate for user adjudication; the lock must not be changed to HEAD on your own authority.
2. Create a new audit checkout (such as `/tmp/cadr-parity-<new-hash>`), following the existing incremental upgrade process:
   - Regenerate the payload cross-implementation-comparison fixtures in full, list every difference from the old baseline item by item, and map each one to an implementation change or confirm that it has no impact;
   - Go through `git diff <old-baseline>..<new-baseline>` in full and produce an inventory of the increment;
   - Rebuild parity-map against the new baseline, entering new test files into the ledger as `M`; **existing `C` rows affected by upstream changes must be re-verified**, and the old conclusions must not be carried over.
3. Known increments (as of 2026-08-01; the list is incomplete, and the actual diff governs): **the new package `packages/client`** (Unix socket transport); `feat(server): composable protocol server`; `feat(tui): fullscreen transcript navigation`; `feat(tui): draggable transient scrollbars`; `feat(coding-agent): ui mode setting`; `fix(tui): preserve spaces in settings searches`; Fireworks Kimi K3 routing; per-account isolation of the Codex socket; and so on.
4. Bring every test file up to `C` against the new baseline, or to `N/A` by user adjudication.
5. Visual and runtime alignment: the new TUI features (fullscreen transcript, scrollbars, ui mode) must be entered into the mechanical alignment table of `docs/visual-parity.md`, and appended to the B3 dual-terminal A/B checklist for the user to re-verify.

## 3. Part C: CI

1. Build a GitHub Actions workflow on top of goal 9 Part D's `./scripts/verify.sh` and push it to Part A's private repository. **On 2026-08-01 the user authorized Codex to configure and enable CI on its own** (the `gh` token has the `workflow` scope).
2. Contents: SBCL environment preparation, dependency installation, `build.sh`, and **the full offline test run** (the credential-gated live portion skips normally in CI for want of credentials; it must not fail and must not be faked as passing).
3. The workflow must actually run green on CI once, and the report attaches the run link and the conclusion; **committing the yml alone must not be declared complete**.
4. Record explicitly the coverage difference between CI and the local `verify.sh` (which live items can only be run locally).

## 4. Part D: Lisp-native capabilities (proposal first, requires item-by-item user adjudication)

**Nature**: this is the "new capability" layer, that is, mechanisms the baseline does not have, so under the project's established three-layer boundary **a written proposal must be submitted first and item-by-item user approval obtained before it may be implemented**, to the same standard as `docs/proposals/goal-v7-extension-api.md` (each item contains the exact requirement, the minimal implementation surface, the alternatives and the reasons they were rejected, the impact on the existing frozen surface, and the rollback method).

Candidates (the user gave the direction on 2026-07-31; the concrete design is settled by this Part's proposal):

1. **condition/restart for tool failures**: the current usage of `restart-case`/`invoke-restart` is 0, and error handling is entirely `handler-case` (equivalent to try/catch). The goal is to provide restarts such as "retry with changed arguments / skip / abort" **at the site of the error** in a tool failure (with the stack not unwound), for a hook extension or an interactive front end to choose from — a capability the TypeScript implementation physically cannot have. The proposal must state: the set of restarts, the relationship to the existing `:tool-call-after` hook, the default behavior in non-interactive modes (print/json/rpc), and the guarantee that existing observable behavior does not change.
2. **A slynk remote REPL attached to a running agent**: the goal is to connect from an editor into a running cadr, inspect agent state and redefine tool functions, taking effect on the next turn without losing the session. The proposal must state: **off by default**, an explicit switch and listening on loopback only, the relationship to the "YOLO by default + container isolation" security stance, and that slynk, as a new third-party dependency, needs separate authorization (subject to the class (a) blocked constraint).

**Constraint**: whether or not they are approved, both of these **must not change any existing observable behavior** (the payload sent to the server, the prompts and tool descriptions fed to the model, the terminal presentation). After implementation they must be explicitly registered in the README difference list and in parity-map as "an intentional addition relative to the baseline", with a statement that they do not affect the parity verdict.

**Adjudication status (2026-08-01)**: both capabilities and the Slynk
dependency are approved; approval does not authorize starting construction
early. Part B's no-op adjudication satisfied the precondition for
implementation. D1 commit `55094c9d7`, D2 commit `65052f7a6`, documentation and
re-freeze commit `c12c03ba1`; the full evidence is in
`docs/acceptance/goal-v10-part-d.md`.

## 5. Part E: the first official release

**Status**: the `0.2.0` code, tests, documentation and Release draft are ready;
no tag or GitHub Release has been created yet, and it is waiting for the user's
confirmation as agreed. The frozen identity string is
`cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)`, and the evidence and
the release copy are in `docs/acceptance/goal-v10-part-e.md`.

1. On the basis of goal 9 Part E's CHANGELOG and single source of the version number, produce the first official version (`0.2.0` suggested, with the reasons written into the report).
2. **The version identity string must state the upstream release version it is aligned with and the actual baseline relationship**.
   After Part B's no-op adjudication the exact form is
   `cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)`. That identity string appears in the
   `--version` output, the README header, the CHANGELOG entry and the Release notes,
   identical in all four places; the numeric version is supplied to production code only by `version.sexp`.
3. `git tag` and the GitHub Release: **the tag name, the version number and whether to release are executed only after the user confirms them**; they must not be released on your own authority.
4. The Release attaches: build instructions, the overall table of verification tiers (which providers are live-verified and which are fixture cross-implementation comparisons), the difference list, the aligned upstream tag and commit hash, and acknowledgements and disclaimers.
4. Final documentation check: README, architecture, parity-map, visual-parity, dependency-audit and open-questions are all in sync with the implementation.

## 6. Acceptance criteria

1. Part A: the private repository exists, the branches and tags are complete, and it builds after cloning; no credential leak.
2. Part B: per the final adjudication, prove that there is no release tag ahead of the current baseline, keep
   `74caa2649` and do not downgrade backwards; the package/test counts and the existing
   `362 C / 0 U / 0 M / 1 N/A / 363` conclusion have been recorded.
3. Part C: CI actually runs green on the remote, with the link and the difference explanation complete.
4. Part D: the proposal has been adjudicated item by item by the user; after the approved items are implemented, existing observable behavior has zero changes (proven by payload cross-implementation comparison and runtime snapshots), and the difference list has been registered.
5. Part E: a single source for the version number, a complete CHANGELOG, complete Release content, and release only after the user confirms it.
6. The full test suite only grows and never shrinks, and is fully green; each Part has its own commit sequence and report chapter (including tokens and elapsed time).

## 7. Principles

- Tests first; freeze discipline and object-ID comparison run through the whole process.
- **A verification script must not obtain a pass by normalizing, by rewriting the input or by weakening assertions** (the lesson of goal 8's correction).
- **Assertions must cover the content itself and not only the structure**: streamed text must have an equivalence assertion that "after assembly it equals the original text character by character"; the provider × capability matrix must be covered item by item; the full copy of tools and overlays must be snapshotted verbatim (the lesson of three rounds in goal 9 Part B).
- Pause after Part E is complete and wait for the user's final acceptance.

## 8. Closeout ledger

- Part A: the private backup, the full-history credential audit and the independent clone/build have been accepted by the user;
  see `docs/acceptance/goal-v10-part-a.md` for details.
- Part C: commits `dc8052ee6` through `4bf24c96e`; CI on the private remote has actually run green;
  see `docs/acceptance/goal-v10-part-c.md` for details.
- Goal 11 prerequisite: commits `6ee7d84f3` through `d84a20dae`; the non-functional gate has been closed out.
- Part D: `55094c9d7`, `65052f7a6`, `c12c03ba1`; restarts, the 34th event,
  Slynk and the re-freeze are recorded in the ledger.
- Part B no-op: `5fbfc2fac`; the `74caa2649` baseline is kept and the exact relationship that
  `v0.83.0` is 38 commits behind is recorded.
- Part E: `80d962069`; the version, the exact alignment identity string, the CHANGELOG, the Release draft and the
  closing out of the `PI_CL_*` migration window are recorded in the ledger.
- Final verification: `7192 checks / 7192 pass / 0 skip / 0 fail`; the two isolated builds,
  the Goal 11 gate, all retained harnesses, the available live FiveAM and the DeepSeek TUI all pass.
