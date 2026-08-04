# Goal 15 post-close A/B correction

## Scope and root cause

The original differential was fail-closed only inside a manually selected
12-scenario domain. Its 88 adjudicated differences were real, but an omitted
surface produced no signal. `/session` and the provider-specific authentication
layers exposed that structural gap.

The replacement registry is mechanically checked against fixed baseline
`74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`:

| Set | Count | Gate |
|---|---:|---|
| Fixed-baseline slash commands | 22 | exact extracted order must match registry |
| Reachable interface states | 28 | every row must name a real scenario/checkpoint |
| Baseline component constructors | 15 | every extracted constructor must be mapped |
| Baseline construction sites | 22 | every `file:line:constructor` must be mapped |
| Cadr overlay kinds | 13 | every source kind must be mapped |
| Scenario/dimension captures | 20 x 2 = 40 | fresh capture required before analyze |
| Intermediate checkpoints | 83 per side | dispositions remain missing/stale/duplicate fail-closed |

`test_reachable_interface_registry_is_complete_against_fixed_baseline` drives
the real ledger and fixed commit. `baseline-interface-inventory.json` records
the mechanically extracted immutable input so a source archive without `.git`
remains buildable; whenever the commit object is available the gate requires
the snapshot and live extraction to be byte-for-byte equivalent. The synthetic
companions prove that a new slash command, construction site, or uncaptured
secondary dialog fails.

## A/B defects

| Item | Fixed-baseline evidence | Cadr implementation | Regression |
|---|---|---|---|
| S01 row spacing | `interactive-mode.ts:5734-5761` builds one multiline `Text` with newlines only between rows | `interactive/controller.lisp` buffers notification text until `finish-output`; `bootstrap/sessions.lisp:1026-1156` writes one block | `POST-GOAL15-SESSION-INFO-MATCHES-BASELINE-SPACING-STYLES-PERCENT-AND-COST-BREAKDOWN` |
| S02 heading color | `interactive-mode.ts:5734,5740,5745,5764` uses `theme.bold`; labels use `theme.fg("dim", ...)` | `session-info-style` owns heading/label styles | same test |
| S03 cache percentage | `interactive-mode.ts:5750-5758` computes `cacheRead / promptTokens` to one decimal | `write-session-command-info` uses the identical denominator and precision | same test |
| S04 cost breakdown | `interactive-mode.ts:5727-5732,5763-5777` groups actual provider/model usage and cache misses | `session-usage-breakdown` plus `compute-cache-waste` render provider/model, Tools/summaries, and re-billed detail | same test |
| S05 title taxonomy | `extension-selector.ts:44-48`, `login-dialog.ts:44-48`, `session-selector.ts:132,873`, `user-message-selector.ts:123`, `settings-selector.ts:167-188` | selector frame exposes explicit plain/overlay/submenu styles; input/editor remain accent non-bold | `POST-GOAL15-OVERLAY-TITLE-STYLES-FOLLOW-BASELINE-COMPONENT-CLASSES` |

The expanded captures also found semantic defects in narrow Text wrapping,
session-selector ellipsis, clone name retention, path-autocomplete cwd,
settings/auth/extension nested state, import cancellation, and Markdown table
width allocation. These were fixed before applying the already-approved I01
terminal-emitter disposition to the newly reachable checkpoints; visible text
was compared independently after stripping ANSI and trailing cell padding.

## Verification

The first `verify.sh` attempt exposed a real delivery-path defect: the isolated
source copy intentionally omitted `.git`, but the new Python regression tried
to read the fixed commit object. The build failed rather than silently skipping
the audit. Commit `185f70257` added the immutable inventory/fixed-object
cross-check and gitless archive path; `0ea9656fd` updated the enclosing FiveAM
gate to require all five Python regressions. The passing run below is after
those fixes, not a retry of unchanged code.

| Gate | Result |
|---|---|
| `./scripts/test-cl.sh` | 9 systems; 14,683 checks; 14,683 pass; 0 skip; 0 fail |
| render-diff Python regressions | 5/5 pass |
| real fixed-baseline capture | 20 scenarios; 40/40 captures; 83 checkpoints per side |
| analyzer | 6 aligned; 160 differences requiring disposition; 160 adjudicated |
| `./scripts/verify.sh` deterministic | 15/15 stages pass, including gitless `cadr` and `cadr-server` builds |
| `./scripts/verify.sh` live | 2/2 stages pass |
| credential-gated live items | 7 pass; 1 Anthropic skip because `ANTHROPIC_API_KEY` is not set; 0 fail |

Implementation commits are `0f41d3990` (reachable interfaces and A/B fixes),
`185f70257` (source-archive-safe fixed-baseline inventory), and `0ea9656fd`
(five-test enclosing gate).

Root binary freshness after the final non-documentation commit:

```text
binary build time: 2026-08-04 21:26:07.452137690 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
latest src commit: 0f41d39904cb7a8a46b1cd7ee24e7db4b92dd960 2026-08-04T21:10:31+08:00
latest source mtime: 2026-08-04 20:43:01.955968482 +0800
root binary freshness: fresh
```
