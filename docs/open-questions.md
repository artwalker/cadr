# Open Questions

This file records only mechanisms proposed as additions relative to the fixed
TS baseline. Until an entry has received an explicit human adjudication, it
must not enter implementation.

Items awaiting adjudication:

- `OQ-G20-AGENT-EVAL-TOOL`: **a Lisp evaluation tool for the agent (not for
  humans)**. On 2026-08-13 the user raised "cadr is written in Lisp; could the
  REPL be used to change it while it runs, so as to raise development quality
  and efficiency and find bugs earlier". The advisor's investigation and
  reservations on this:

  **This and the existing `OQ-G10-D2-SLYNK-REPL` are two different things.**
  The latter was approved and implemented on 2026-08-01 and is **for humans**:
  off by default, requires an explicit `--slynk`, loopback-only; a human
  connects with SLY and, against the running agent, redefines functions, looks
  at restarts, and continues.
  This entry asks about **opening the evaluation capability to the model** —
  the baseline pi has no equivalent tool at all (its tool surface is
  read/write/edit/bash), so it belongs to "mechanisms added relative to the
  baseline".

  **First, the part obtainable without any adjudication** (the recommendation
  is to exhaust this layer before discussing a new tool):
  the executing side can use the existing bash to load a subsystem and call
  functions directly to probe behavior, with no need to rebuild the 20 MB core.
  Measured: loading `cadr-ai` (61 files / 25,818 lines) on a cold cache takes
  **11.9 seconds** (`sbcl --load ~/quicklisp/setup.lisp` + `asdf:load-asd` one
  by one + `asdf:load-system`, with `HOME` and `ASDF_OUTPUT_TRANSLATIONS`
  isolated; see the existing formulation in `scripts/test-cl.sh:15-40`); a warm
  cache is faster.
  **The premise that "changing one line means waiting for a whole-core rebuild"
  does not hold.**

  **The capability the new tool genuinely adds** amounts to one item only:
  attaching to **the cadr process that is actually running**, and fixing and
  continuing without losing the session state. This is the capability slynk
  gives a human.

  **The advisor's reservations (input to the adjudication, not opposition)**:
  1. **The design problem is unsolved.** A human doing interactive debugging
     relies on holding the state in their head and probing continuously; for an
     agent to use it, a long-lived session has to be managed (when to open it,
     when to close it, how context is carried, how to recover from a crash).
     **That is not a capability you get by adding a tool.**
  2. **The tool and the object under test are the same.** cadr's correctness is
     defined by the differential against pi; letting the model change itself
     inside a live image produces a state that **corresponds to no commit**,
     and neither render-diff nor the ledgers have any way to check it.
  3. **The credential surface.** An evaluation tool is equivalent to arbitrary
     code execution, and must be checked item by item against the credential
     discipline of `development-policy` section 3 (`auth.json` 0600, tokens
     never entering logs/sessions) before its boundary is discussed.

  **Adjudication (the user authorized the advisor to adjudicate on their
  behalf, 2026-08-13): implementation is deferred, with conditions for
  restarting.**

  Three reasons; the first two are measured:
  1. **The main benefit can already be had at no cost.** Measured: loading
     `cadr-ai` (61 files / 25,818 lines) on a cold cache takes **11.9
     seconds**, with no need to rebuild the 20 MB core; the premise "changing
     one line means a whole-core rebuild" does not hold. What the new tool
     genuinely adds is only "attaching to the process that is actually running,
     and finishing the fix and continuing without losing session state".
  2. **Higher-value Lisp capabilities have not been put to use yet, and have
     been verified as feasible.**
     `sb-introspect:find-definition-sources-by-name` can derive the ledger
     mapping from the image (of the existing 1,038 hand-made mappings, 108 have
     already rotted);
     `sb-mop:class-slots` slot-by-slot comparison was measured to locate the
     `default-model` difference automatically (the provider gate currently
     compares only 6/21 fields). **These two have a larger benefit, a lower
     risk, and add no mechanism at all**, and are listed as goal 20 Part N.
  3. **The design problem is unsolved**: how an agent manages a long-lived REPL
     session (when to open and close it, carrying context, crash recovery) has
     no answer yet; and the tool and the object under test are the same, so a
     change made in a live image corresponds to no commit.

  **Conditions for restarting**: goal 20 Part N2 requires recording "which
  defects were found first by the load-and-probe loop". **If that record shows
  that a class of defect exists that can be found only by debugging a live
  image**, a fresh proposal is made on that basis and its boundary (including
  the credential surface) is adjudicated item by item. **Until then it must not
  be implemented.**

Adjudicated, goal pending:

(There is currently no pending goal.)

Adjudicated as not to be done:

- `OQ-G20-EXTENSION-ISOLATION`: **after the advisor's investigation of
  2026-08-13 the decision is not to do it; this entry is closed.** The worry
  when it was raised was "cadr extensions are loaded into the same image and
  can reach any internal symbol". **The investigation overturned it**:
  - Every cadr extension gets its own package,
    `(make-package name :use '(:cl :cadr-agent))`
    (`src/cadr-cli/extensions/loader.lisp:476-478`), which **does not use the
    internals of `cadr-cli` / `cadr-tui` / `cadr-ai`**; a load failure is
    cleaned up with `delete-package`.
  - **The baseline pi's isolation is weaker**: `jiti.import(extensionPath)` is
    an ordinary dynamic import (`core/extensions/loader.ts:455`), with **no vm
    sandbox and no worker isolation**; a pi extension is a Node module, can
    `require('fs')` and read `process.env`, and holds whole-process privileges.
  - The residual surface is that CL's `pkg::symbol` can reach internals, but
    that requires deliberately writing out the qualified name, **and a pi
    extension's privileges are strictly greater**. Adding package locks is a
    behavioral divergence relative to the baseline, and **does not buy any
    security that pi lacks either**.

  **Conclusion: cadr's isolation as it stands is not weaker than the
  baseline's; no change is made.** If extensions should in future become
  automatically installable from untrusted sources, this conclusion must be
  re-evaluated — **at that point it is the distribution model that changed, not
  this entry's judgement that was wrong**.

Adjudicated and implemented:

- `OQ-G18-L1A-MERMAID`: route 1 was adjudicated on 2026-08-12; it landed in
  goal 19 Part C. In `docs/source-parity.md` the `mermaid.ts` row records
  `已实现`
  (`src/cadr-tui/mermaid/transform.lisp:transform-mermaid-markdown`).


- `OQ-G18-AUTH-CANCEL-14`: route A was adjudicated on 2026-08-12 and landed.
  From v0.84.1 onward the baseline pi renders, on the 14 auth-cancel
  full-screen keys, a red
  `Error: ... This operation was aborted` (the regression: abort.ts:3 throws
  `"The operation was aborted"`, and interactive-mode.ts:5666 suppresses only
  `"Login cancelled"`); cadr keeps suppressing it under the adjudication
  already made in goal 13, and the 14 keys are recorded as
  intentional-difference `I05` (textCovering, limited to login cancellation,
  with the note describing it truthfully). Once upstream fixes that regression,
  I05 is retired and the 14 keys return to verbatim alignment. The disposition
  record is in `docs/proposals/goal18-auth-cancel-regression.md`.

- `OQ-G15-I02-FATAL-REDACTION`: on 2026-08-04 it was confirmed that the crash
  redaction mechanism implemented in Goal 13 is retained. The fixed baseline
  dumps the stack straight to the terminal
  (`packages/coding-agent/src/modes/interactive/interactive-mode.ts:3671-3721`),
  which leaks the system prompt and session content; Cadr changed it to a
  user-visible redacted summary plus an owner-readable-only `0600` private
  crash log. This item is an intentional addition relative to the baseline,
  not a difference the language migration makes inevitable;
- `OQ-G10-D1-TOOL-RESTARTS`: on 2026-08-01 the condition/restart at the site of
  a tool failure and the 34th extension event `:tool-call-error` were approved;
  after implementation it was re-frozen at 34 events, and any further addition
  must still go through a fresh proposal and item-by-item adjudication;
- `OQ-G10-D2-SLYNK-REPL`: on 2026-08-01 the off-by-default, loopback-only
  Slynk runtime REPL and the exactly pinned third-party dependency closure were
  each approved;
- After Goal 10 Part B was adjudicated by the user as a no-op, the two items
  were implemented according to the approved proposal and re-frozen.

The complete boundary, the dependency lock and the adjudication record are in
[`docs/proposals/goal-v10-part-d-lisp-native-capabilities.md`](proposals/goal-v10-part-d-lisp-native-capabilities.md).

`OQ-G9-LIVE-GATE` was approved item by item by the user and implemented; the
adjudication and the evidence are archived in
[`docs/proposals/goal-v9-live-test-gating.md`](proposals/goal-v9-live-test-gating.md).

- `OQ-G16-SHARE-VIEWER-TRANSITION`: adjudicated on 2026-08-05. `/share` stays
  enabled by default, the default viewer is unified to
  `https://cadr.dev/session/`, and only `CADR_SHARE_VIEWER_URL` is permitted to
  override it. The user has accepted, with full knowledge, that before the
  cadr.dev page goes live `/share` will successfully create a Gist but the
  viewer link it generates will be temporarily unreachable; once the page is
  live, no change to Cadr's code is needed. This transitional state must not be
  used as a reason to disable `/share`, to fall back to the upstream viewer, or
  to introduce any other fallback mechanism.

- `OQ-CANONICAL-REPOSITORY-URL`: adjudicated and implemented on 2026-08-05.
  `src/cadr-cli/support/changelog-share.lisp:144,152-160` rewrites `/share`'s
  changelog link and pins it at `https://github.com/earendil-works/pi`. But
  what `CHANGELOG.md` records are **Cadr's own** changes (such as "Added the
  fourth parity ledger", "Replaced the OAuth callback page's interim block-C
  mark with Cadr's cons-cell identity"), so linking to the upstream repository
  amounts to outwardly usurping the upstream identity, of the same family as
  the already-corrected `originator=pi` and pi logo.
  The user has confirmed that the canonical repository is
  `https://github.com/artwalker/cadr`; the repository being private does not
  change its canonical URL. C4 has made `/changelog`'s runtime link rewriting
  read that URL from the release identity's single source, without changing
  `origin`. The legacy TS extension detection in `src/cadr-evals/suites.lisp`
  and the `pi-ai` provenance comment of the generated catalog were confirmed by
  a whole-tree audit to be baseline evidence, and continue into the exact
  allowlist rather than being replaced along with the product identity.

- `OQ-G18-NPM-PACKAGE-SOURCE`: on 2026-08-10 adjudicated as 有意差异. The
  baseline's `install`/`update` installs `npm:` package sources through npm;
  the Common Lisp build has no npm outlet and refuses with fixed wording ("npm
  packages are unavailable in the Common Lisp build; install a Lisp local or
  Git package"). Equal-strength assertion:
  `goal18-npm-package-source-is-a-fixed-intentional-difference`
  (part-b-package-test.lisp) locks that fixed shape.

- `OQ-G18-UPDATE-MODELS`: on 2026-08-10 adjudicated as 有意差异. The baseline's
  `update --models` refreshes the model catalog over the network; cadr's model
  catalog is bundled with the binary, and the command outputs a fixed offline
  notice ("Model catalogs are bundled with this cadr build."). Equal-strength
  assertion: `goal18-update-models-is-a-fixed-intentional-difference`
  (part-b-package-test.lisp, using `:offline-p t` to prove no network takes
  part).

- `OQ-G18-INSTALL-TELEMETRY`: on 2026-08-10 adjudicated as 有意差异. At
  interactive startup the baseline sends an install report to pi.dev's
  report-install endpoint (interactive-mode.ts:1045-1062, gated by
  enableInstallTelemetry and PI_OFFLINE); cadr keeps the
  `enableInstallTelemetry` display surface in settings, but no reporting outlet
  exists at all. Equal-strength assertion:
  `goal18-install-telemetry-has-no-egress` (goal14-organization-test.lisp)
  scans all of src/**/*.lisp for the absence of the endpoint string.
