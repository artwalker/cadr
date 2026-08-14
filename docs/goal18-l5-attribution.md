# Goal 18 L5.1: item-by-item attribution of the findings from the manual A/B (2026-08-10)

Each row answers "which gate now catches it before the user does". Attribute to a concrete gate/test name;
"already fixed" does not count as attribution.

| # | user finding | who catches it first now |
|---:|---|---|
| 1 | TUI spacing inconsistent all over (recurring over many rounds) | the full render-diff gate: 45 scenarios × 2 terminal sizes in byte-for-byte cross-implementation comparison + 762 visible-string branches covered (the TUI composition convergence of C1–C5 is driven by exactly this) |
| 2 | `To resume this session:` missing on exit | the `post-exit-resume` checkpoint of the `commands-and-exit` scenario; channel ledger C-02/C-03 (`docs/presentation-parity.md`) lists the stdout after alt-screen teardown as a separate channel |
| 3 | heredoc multi-line command rendering corrupted | the `bash-multiline`/`bash-long-command` checkpoints of the `tools-success` scenario (the narrow dimension covers line-break re-flow) |
| 4 | the bash truncation notice printed twice | the `bash-byte-limit`/`bash-line-limit`/`bash-overlong-line` checkpoints of the `tools-significant-states` scenario (goal 16 P1-B added the truncation states into the scenario matrix) |
| 5 | compaction status wording inconsistent with the baseline | the three scenarios `compaction-status-manual`/`compaction-status-threshold`/`compaction-status-overflow` |
| 6 | `/export` notice behaves differently | the `slash-export` checkpoint of `commands-and-exit` + alignment of the bare-filename wording |
| 7 | color of the bash command text / read line numbers | the `stylePath` of the visible-string list (colors are compared across implementations one by one inside the branch model) + the read/bash checkpoints of `tools-success` |
| 8 | paths not abbreviated with `~` | `<HOME>` normalization in the startup and selector scenarios + whole-screen cross-implementation comparison (the path display line appears in several scenarios) |
| 9 | OAuth callback page is crude | channel ledger C-06 (content returned by cadr's own service) + the FiveAM OAuth page test (after the cons-cell identity mark it is cadr's own asset) |
| 10 | tool arguments polluted by JSON fragments | the grammar-coercion test for streaming assembly (`test/cadr-ai/utilities-test.lisp`) + the tool-result/event differential gates |
| 11 | the space before a number swallowed | same as above (the whitespace-handling regression for streaming assembly) + event differential |
| 12 | very laggy after a while of use (rendering is O(N²)) | the Goal 11 performance and stability gates (`scripts/bench.sh` + `goal11-stability.sh`, a mandatory stage of verify.sh) |
| 13 | periodic stutter after scrolling plus selecting text | the sustained-interaction benchmark `sustained_mixed_interaction` (p99.9 / maximum pause / GC distribution, pinned by the reference in `test/cadr-cli/live-gate-test.lisp`) |
| 14 | login dialog missing entirely | the `overlays-auth-*` family of scenarios + `loginDialogCoverage` derived from I2 (eight forms extracted mechanically; a missing mapping means red) |
| 15 | Radius browser flow is plain text | the `overlays-auth-browser-callback`(+`-complete`) scenarios (the showAuth/showProgress pair of forms) |
| 16 | four differences in the startup resources block | the two-state scenarios `startup-resources` (non-empty) and `startup-first/existing/untrusted` (empty) + the I3 two-state rule |
| 17 | ESC cancel at login deadlocks | `goal18-login-cancel-test.lisp` (FiveAM state-machine regression) + every cancel-path scenario ends with a post-cancel interaction (rule A4.3, written into the render-diff document) |
| 18 | residual product identity | the product-identity gate (`check-product-identity.py`, 373 items registered one by one) |

## Residual manual surface (explicit list, L5.3)

Surfaces that can still only be verified by hand: image-protocol rendering in a
real terminal (the actual pixel result of sixel/kitty in the host terminal),
terminal-emulator implementation differences (the forwarding behavior of an
outer conhost/Windows Terminal/tmux), macOS-only platform paths (Apple Terminal
modifiers, sandbox-exec), a real OAuth browser round trip (redirection to an
operator page outside this machine's loopback), and long-session
accumulated state (memory and rendering aging under hours of real use). The
reason in each case: a physical terminal or a platform/credential is required,
and the harness's PTY and faux provider cannot substitute for them.

## L5.2 post-exit interaction probe addition — a blocker found and reported (pending adjudication)

When, per L5.2, a "post-exit probe" (send one message and wait for a normal
reply) was added to the 15 scenarios that end in escape, the probe interactions
themselves all passed (the state machine is sound — this is precisely the
evidence that rules out this defect class), but **the probes exposed a class of
exit-afterimage difference that had not been covered before**:

- Symptom: on the process-exit screen of `tools-success` and similar scenarios,
  pi's residue is a compact tail (13 lines, cursor 0,15) while cadr leaves the
  entire final frame (32 lines, cursor 0,31). The content text is identical, the
  vertical layout differs.
- Boundary: for short sessions the afterimage on both sides is byte-for-byte
  equal (the existing 45 scenarios being fully green proves it); sessions whose
  content exceeds the viewport are equal as well (the 1.6MB streaming session of
  `tools-render-branch-sweep`); only the middle height band that "exceeds the
  startup area but does not exceed the viewport" diverges. The existing five auth
  scenarios (including three probe messages) have identical afterimages on both
  sides, which shows this is not caused by the probes themselves.
- Verdict: no existing disposition class can carry it — I01 does not cover
  text-geometry differences, and the semantics of I02/I03/I04 do not fit either.
  Per the rules a new class is required (proposed I05: exit-afterimage extent
  difference, the teardown residue of the alt-frame vs scrollback model), or
  cadr's exit teardown is fixed as a defect (aligned to the baseline's compact
  tail). **Both require user adjudication; once the probe patch had verified
  reproducibility it was **reverted**, and it does not land before adjudication.

## L5.2 adjudication landing and wrap-up (2026-08-11)

User adjudication: I05 is fixed as a defect in cadr's exit teardown path, and no
new disposition class is opened ("only the middle height band that 'exceeds the
startup area but does not exceed the viewport' diverges" shows this is a fixable
implementation difference and not a semantic divergence). The landing and the
incidental findings:

1. **In-place repaint (bbbfed52a)**: the harness ack no longer wipes the whole
   screen but does an in-place canonical repaint within the baseline's
   semantics (pi's viewportTop only increases and never decreases, and
   shrinking leaves blank lines), and the exit afterimage is byte-for-byte
   identical to pi's (tools-success and others).
2. **Settle-window race (fixed this round)**: the repaint exposed a transient
   frame-height difference — cadr's main loop renders by wall-clock polling and
   can, within the [last text-delta/message-end .. agent-end] window,
   capture a frame with "the complete body text + the Working indicator" (2
   lines taller than the settle frame); the viewport only increases and never
   decreases, so the overshoot is left behind as trailing blank lines, and the
   baseline never does this (its message_end→agent_end is a single synchronous
   event chain that a timer-driven renderer cannot observe). Fix: the
   settle-window-p flag is set at block end / message-end and cleared by the
   turn-resolution event, and frames rendered inside the window omit the working
   indicator (tool-rendering.lisp / controller.lisp render-now). The race window
   narrows from the millisecond scale (persistence I/O) to the sub-microsecond
   scale (stream-tail bookkeeping). Evidence: the first version
   (set at message-end) was re-run four times over narrow screens × nine
   checkpoints and matched the pin every time; after adding the set at block
   end, the full gates gate11/gate12 went green in a row, and verify.sh's 21
   deterministic + 2 live stages are all green.
3. **Missing provider context conversion (a real defect that the PIN had
   masked)**: while investigating the I01-only entry of
   user-bash-state-sweep/process-exit it was found that the SHAs on the two sides
   of its pin had differed all along (footer ↑14k vs ↑1.3k) yet it was
   registered as "text identical" — the real cause is that cadr never performed
   the convertToLlm conversion when building the provider context (baseline
   agent-loop.ts:295), so bash-execution/custom/branch-summary/
   compaction-summary messages were silently discarded, the model could not see
   the output of `!` commands, and real
   providers were affected the same way. Fix: stream-assistant converts through
   convert-agent-messages-to-llm before building the request context
   (turns.lisp). After the fix, that checkpoint on a narrow screen is completely
   identical to pi's.

The mechanism lesson from the masked entries: stream-interrupt-queue/process-exit
had the two sides of its narrow-screen pin equal yet was tagged I04 (stale), and
user-bash-state-sweep/process-exit had the two sides of its narrow-screen pin
unequal yet was tagged I01-only (a missed class) — both were introduced in the
L5.2 probe commit, and because the full gate run failed earlier at a drift point,
neither was ever examined by a green full run. This round they have been split
apart / corrected and the assertions filled in: the stale check (screen equality
must not be tagged with a semantic class) and the reverse check (I01-only must
not absorb a screen difference) are both fail-closed.
