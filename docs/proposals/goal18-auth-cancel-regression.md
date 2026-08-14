# Goal 18: proposal to adjudicate the pi v0.84.1 regression difference on the authentication cancel screens (adjudicated)

Status: **adjudicated (2026-08-12): route A approved, I05 has landed.** On the pi
side of the 14 auth-cancel full-screen pairs, v0.84.1 (`53fa77ccd`) begins to
render a red `Error:` line, while the cadr side continues to suppress it (in
accordance with the user's established goal 13 adjudication). Under the
standing constraint (adding an intentional-difference class must not be decided
on your own authority), this proposal gives the evidence, the root cause and
two routes, and escalates them for user adjudication.

> Ledger record (2026-08-12, after the user adjudicated route A):
> `dispositions.json` gains an `I05` class (`textCovering=true`, with the
> summary narrowed to the login cancellation path, naming the root cause on the
> pi side: `packages/coding-agent/src/utils/abort.ts:3` throws
> `Error("The operation was aborted")`, while
> `interactive-mode.ts:5666` suppresses only `"Login cancelled"`); the 14 keys
> (12 entries) are re-hung on `I01/I04/I05` and given truthful notes (deleting
> the previous untruthful descriptions such as "visible text is identical to
> pi"). Once upstream fixes that regression, I05 is retired and these 14 keys
> go back to verbatim alignment.

## Current gate state

The unpatched `scripts/render-diff.py analyze --tier core` fails on clean fresh
captures at the very first drifting key:

```
render-diff: semantic screen pair drifted outside the exact I04 disposition:
overlays-auth-oauth/wide/login-cancelled
```

The enumeration (with a temporary patch making the validator a no-op) shows
that apart from the following 14 keys, everything is
`aligned`/`intentional-terminal-protocol`, with `missing=[] stale=[]`:

| Key | New pi SHA prefix | cadr SHA prefix |
|---|---|---|
| overlays-auth-oauth/wide/login-cancelled | `be73e7bc` | `052398f3` |
| overlays-auth-oauth/wide/login-post-cancel | `e5d88edf` | `5a3bca22` |
| overlays-auth-oauth/wide/process-exit | `66c45651` | `819b4c55` |
| overlays-auth-oauth/narrow/login-cancelled | `e13a9f49` | `6c0dd094` |
| overlays-auth-device-code/wide/login-device-cancelled | `c16a148b` | `052398f3` |
| overlays-auth-device-code/wide/login-device-post-cancel | `ae49d51d` | `5a3bca22` |
| overlays-auth-device-code/wide/process-exit | `a5ee1a0f` | `819b4c55` |
| overlays-auth-device-code/narrow/login-device-cancelled | `1dd0f8ad` | `9052a4c6` |
| overlays-auth-browser-callback/wide/login-loopback-cancelled | `eff8c927` | `052398f3` |
| overlays-auth-browser-callback/wide/login-loopback-post-cancel | `627691c0` | `5a3bca22` |
| overlays-auth-browser-callback/wide/process-exit | `118bd255` | `819b4c55` |
| overlays-auth-browser-callback/narrow/login-loopback-cancelled | `acff9fd7` | `9052a4c6` |
| overlays-auth-api-key/wide/api-key-post-cancel | `6cab2b5e` | `5a3bca22` |
| overlays-auth-api-key/wide/process-exit | `02129459` | `819b4c55` |

## Evidence

The visible text in the new pi (`53fa77ccd`) fresh captures:

```
Error: Failed to login to Render Auth: This operation was aborted
Error: Failed to login to Render Device: This operation was aborted
Error: Failed to login to Render Loopback: This operation was aborted
Error: Failed to save API key for Render Auth: This operation was aborted
```

That error line stays visible on the cancel screen, the post-cancel screen and
the process-exit screen (it appears in both wide and narrow). Under the old
baseline pi (`74caa2649`) the same key has no error line and returns straight
to the input box; the cadr side likewise has no `Error:` line. The evidence for
both the old-baseline pi screens and the cadr screens exists in the local fresh
captures (`/tmp/g18-gate6/analysis/` and `/tmp/rd-core-analysis-enum/`).

## Root cause (pi-side code, current worktree)

- `packages/coding-agent/src/core/model-runtime.ts:494-511`
  `enqueueCredentialOperation` + `raceWithAbortSignal`: cancellation is thrown
  through `signal.throwIfAborted()`/the abort race.
- `packages/coding-agent/src/utils/abort.ts:1-8` `abortReason()` returns
  `Error("The operation was aborted")` (the message is no longer `"Login cancelled"`).
- `packages/coding-agent/src/modes/interactive/interactive-mode.ts:5660-5667`
  suppresses only `errorMsg === "Login cancelled"`, and the new abort message
  falls into the `showError("Failed to login to ...")` branch.
- The old baseline `interactive-mode.ts:5246-5248/:5356-5358` suppresses
  `"Login cancelled"` (the old code threw that string at each provider's cancellation point).
- `git log 74caa2649..53fa77ccd` has 7 commits touching model-runtime/abort
  (such as `fed6009cc fix(coding-agent): make model refresh cancellation
  caller-owned` and `a261366bd feat(coding-agent): add auth preflight`).

## Conflict

This is **regression behavior** in pi v0.84.1, and it conflicts directly with
the user's established goal 13 adjudication: cancellation is a normal user
operation and should not produce error-level output; cadr had already
suppressed it per that adjudication (goal 13 P1-B: after cancelling, return
straight to the input box, with no output at all). Blindly refreshing the
disposition would bake the pi regression into the gate; adding an
intentional-difference class without adjudication would violate the goal 18
goal text ("adding an intentional-difference class must first be reported as
blocked and escalated for adjudication, and must not be decided on your own
authority").

## Adjudication outcome (2026-08-12)

- Route A approved: cadr keeps suppressing the cancellation output; the 14 keys
  above are recorded as the new intentional-difference class `I05`
  (`textCovering=true`, with the summary narrowed, covering login cancellation
  only), and the cadr SHAs stay unchanged.
- All 14 notes are changed to truthful descriptions, deleting any wording of
  the "visible text is identical to pi" kind (for the 14 keys that wording is
  false — the pi side has an `Error:` line and cadr does not).
- Retirement condition: once upstream fixes that regression, I05 is retired
  along with it, and the 14 keys go back to verbatim alignment and are
  re-captured.

The ledger record is complete (dispositions.json I05 + the note rewriting of 12
entries), and the full tier gate and the delivery sequence continue.
