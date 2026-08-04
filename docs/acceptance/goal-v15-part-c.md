# Goal 15 Part C: repair batches

## Batch 1: D05-D07 tool behavior

Commit: the batch commit containing this section.

### Result

The three tool-result defects that can change the model's next decision are
closed before composition work:

| ID | Fixed-baseline contract | Cadr implementation | Regression |
|---|---|---|---|
| D05 | `grep.ts:215-229,270-331` delegates matching to `rg --json` and preserves its streamed match order. | `src/cadr-cli/tools/grep.lisp:3-89,131-268` now consumes the same `rg` event stream instead of sorting a Lisp filesystem walk. | `GOAL15-GREP-PRESERVES-FIXED-BASELINE-RIPGREP-STREAM-ORDER` |
| D06 | `ls.ts:124-150` resolves and reads the requested directory. | `src/cadr-cli/tools/ls.lisp:11-29` passes UIOP's canonical directory-form pathname to `directory-files` and `subdirectories`. | `GOAL15-LS-RELATIVE-SUBDIRECTORY-LISTS-THE-REQUESTED-DIRECTORY` |
| D07 | `read.ts:238-243` exposes the path-bearing filesystem access error to the tool result. | `src/cadr-cli/tools/read.lisp:3-18` emits the exact baseline `ENOENT: no such file or directory, access '<absolute-path>'` copy. | `GOAL15-READ-MISSING-RELATIVE-PATH-PRESERVES-BASELINE-ENOENT-COPY` |

All three regressions were introduced red and failed on the original paths:
`grep` returned `alpha,beta`, `ls notes` listed the workspace root, and missing
`read` returned `File not found: notes/missing.txt`. They pass after the
production changes.

The differential was recaptured in both `100x32` and `48x20`. The `grep`,
subsequent `find`, and `ls` checkpoints now show the fixed baseline's
`beta.md` then `alpha.txt` stream; `ls notes` shows only `alpha.txt` and
`beta.md`; and the missing-read block has the same wrapped ENOENT copy. D05,
D06, and D07 were consequently removed from the fail-closed disposition
ledger. Remaining differences at those checkpoints are the independently
classified I01 and D01-D03 composition classes.

### Common Lisp pathname audit

The D06 root cause was confirmed: `resolve-tool-path` returned a file-form
pathname such as `#P"/cwd/notes"`; `directory-exists-p` accepted it and
returned a directory-form pathname, but the old code discarded that value and
fed the file-form pathname to UIOP enumeration, which interpreted the last
component as a name and listed its parent.

| Tool | Directory/file-form use | Disposition |
|---|---|---|
| `ls` | Directory enumeration | Fixed to retain the directory-form pathname returned by `directory-exists-p`. |
| `grep` | Directory argument passed to external `rg`; directory-form value used only for relative result paths | Correct; regression covers a relative subdirectory and the real `rg` stream. |
| `find` | Canonicalizes the root with `ensure-directory-pathname` and `truename` before walking | Correct; covered by `GOAL15-DIRECTORY-TOOL-PATHNAME-FORMS-STAY-ROOTED-IN-RELATIVE-SUBDIRECTORIES`. |
| `glob` | Its shared tree collector canonicalizes the root before walking | Correct; covered by the same regression. |
| `write` | Intentionally passes the target file pathname to `ensure-directories-exist`, which creates its parent directories | Correct; the same regression writes `notes/generated/result.txt`. |
| `edit` | Operates on a file pathname and never enumerates it as a directory | Not affected. |

Two older tests were corrected because their fixtures encoded Cadr behavior,
not the fixed baseline. The grep context/limit case now uses the exact
single-file fixture from `tools.test.ts:786-805`, so filesystem traversal
order cannot masquerade as a context assertion. The `.gitignore` fixture now
contains a `.git/` directory because the baseline delegates ignore semantics
to real ripgrep, which only applies `.gitignore` inside a repository.

### Verification

Deterministic suite before the batch commit:

```text
cadr test summary: systems=9 checks=14401 pass=14401 skip=0 fail=0
```

The full fixed-baseline analyzer accepted all 88 remaining differences only
through their explicit dispositions:

```text
render-diff analysis: aligned=6 requires-disposition=88 adjudicated=88
```

`./scripts/verify.sh` completed every deterministic stage successfully:

```text
root cadr binary freshness                       PASS
code organization gate                           PASS
real source parity ledger                        PASS
source parity drift self-test                    PASS
deterministic FiveAM                             PASS
isolated cadr build                              PASS
isolated cadr-server build                       PASS
Goal 11 performance and stability gate           PASS
native acceptance smoke                          PASS
native process modes                             PASS
migration PTY smoke                              PASS
Unix socket server smoke                         PASS
terminal lifecycle PTY                           PASS
deterministic TUI harness                        PASS
```

Its credential-gated stage returned nonzero only because
`LIVE-DEEPSEEK-EVAL-SMOKE` received `The capital of France is Paris.` where
the baseline-derived live assertion requires the model to return exactly
`Paris`. The same unchanged live assertion and failure class were explicitly
accepted by the user during Goal 14 B4; this batch does not alter the provider,
model-resolution, or eval path. The other six runnable live items passed, one
Anthropic item skipped for its missing credential, and the DeepSeek TUI live
harness passed.

## Batch 2: D01-D03 root composition and footer state

Commit: the batch commit containing this section.

### Result

The startup, root-composition, and footer differences are closed at their
shared ownership boundaries instead of being patched per screen:

| ID | Fixed-baseline contract | Cadr implementation | Independent regression |
|---|---|---|---|
| D01 | `interactive-mode.ts:758-812` uses one horizontal padding cell, separate product/version styles, independently styled key tokens, and one surrounding spacer; `:843-853` sets `Pi - [session -] cwd-basename` as the terminal title. | `src/cadr-cli/interactive/entries.lisp:248-332` now composes the same startup component grammar; `interactive/controller.lisp:159-197,451-485,2077-2085` emits and refreshes the Cadr-branded title through the terminal boundary. | `GOAL15-STARTUP-CHROME-MATCHES-FIXED-BASELINE-PADDING-AND-STYLES`; `GOAL15-TERMINAL-TITLE-MATCHES-FIXED-BASELINE-SESSION-GRAMMAR` |
| D02 | `interactive-mode.ts:734-746` leaves the idle status container empty and obtains the one default row from the above-editor widget container. | `src/cadr-cli/interactive/frame.lisp:170-203` no longer invents a second two-row idle status placeholder. | `GOAL15-ROOT-COMPOSITION-HAS-NO-INVENTED-IDLE-STATUS-ROWS` plus the existing independent geometry assertions for all base and overlay screens. |
| D03 | `footer.ts:84-111,128-188` aggregates complete usage, begins at `0.0%`, preserves post-compaction unknown state, and adds thinking only for reasoning-capable models; `agent.ts:426-440` forwards the active session ID on every provider request. | `interactive/state.lisp:51-59,222-225`, `bootstrap/commands.lisp:1933-1940`, and `sdk/system-prompt.lisp:144-205` implement those state contracts. `cadr-ai/runtime/faux-provider.lisp:228-263` now counts the full public tool contract, matching fixed-baseline faux rather than names only. | `GOAL15-FOOTER-INITIAL-CONTEXT-AND-THINKING-FOLLOW-MODEL-CAPABILITY`; `GOAL15-PROVIDER-STREAM-RECEIVES-THE-ACTIVE-SESSION-ID`; `FAUX-PROVIDER-USAGE-COUNTS-THE-COMPLETE-TOOL-CONTRACT`. |

The session-ID regression was introduced red with an explicit
`:session-id NIL`. It exposed a real plist precedence bug: appending the active
ID left the earlier NIL visible to `getf`. The implementation now copies the
request options and replaces only a missing/NIL value before appending
callbacks.

### Differential-fixture correction

The first recapture reported a false footer asymmetry (`648` versus `1.9k`)
because the two harness drivers were not providing equal faux-provider input:
the Cadr driver omitted the fixed system prompt and Cadr faux serialized only
tool names, while fixed-baseline faux serializes each complete public tool
object. The drivers now use the same fixed prompt and baseline-derived tool
contracts. Cadr tools retain their real executors and real isolated working
directory; only the scripted faux usage estimator receives the peer fixture
path. Independent product tests lock active session-ID forwarding, full-tool
serialization, and footer state so this fixture correction cannot conceal a
production defect.

After a fresh capture of all 12 scenarios at `100x32` and `48x20`, the full
analyzer accepted every remaining difference only through an explicit class:

```text
render-diff analysis: aligned=6 requires-disposition=88 adjudicated=88
```

No analyzed checkpoint or disposition retains D01, D02, or D03. At the
representative conversation checkpoint both sides now show
`↑1.3k ↓6 W1.3k CH0.0% 2.0%`; remaining byte differences are I01 ANSI/update
sequencing and later approved repair classes.

### Snapshot migration

The old self-snapshots protected the erroneous extra idle rows and unpadded
startup chrome. All 13 base-screen cases and 15 overlay cases retain their
pre-existing baseline-derived semantic assertions; their SHA values were
regenerated only after those assertions passed. `viewport-exact-fill` changes
from 13 to the baseline-derived natural height of 11. The unchanged
`overflow-scrolled-to-top` SHA proves the explicit scroll path was unaffected.

The new SHA sets are recorded directly in
`GOAL9-B3-EVERY-BASE-SCREEN-STATE-HAS-AN-EXACT-FULL-VIRTUAL-TERMINAL-SNAPSHOT`
and `GOAL9-B3-EVERY-OVERLAY-HAS-AN-EXACT-FULL-VIRTUAL-TERMINAL-SNAPSHOT`;
each is paired with the independent first-row, ordering, spacing, geometry,
copy, and navigation assertions already required by the snapshot discipline.

### Verification

```text
cadr test summary: systems=9 checks=14423 pass=14423 skip=0 fail=0
```

The first full `verify.sh` run correctly failed after D01 because the cold-start
probe searched the raw PTY stream for contiguous plain `cadr v`; the now
baseline-matching product/version SGR boundary separates those bytes even
though the first frame is present. `scripts/goal11-cold-start.py` now removes
only CSI/OSC terminal controls for readiness detection while retaining the raw
stream for the actual TUI. A pathname-valued cwd exposed by the same real PTY
path is accepted by the terminal-title formatter. The repaired probe measured
the real frame at 168.844ms before the complete rerun.

The final `./scripts/verify.sh` run passed every stage:

```text
root cadr binary freshness                       PASS
code organization gate                           PASS
real source parity ledger                        PASS
source parity drift self-test                    PASS
deterministic FiveAM                             PASS
isolated cadr build                              PASS
isolated cadr-server build                       PASS
Goal 11 performance and stability gate           PASS
native acceptance smoke                          PASS
native process modes                             PASS
migration PTY smoke                              PASS
Unix socket server smoke                         PASS
terminal lifecycle PTY                           PASS
deterministic TUI harness                        PASS
credential-gated FiveAM                          PASS
DeepSeek live TUI                                PASS
```

The live report ran seven items successfully, skipped the Anthropic item
because `ANTHROPIC_API_KEY` is absent, and recorded 32 checks: 31 pass, one
credential skip, zero failures.

## Batch 3: D08-D12 selectors, viewport, model scope, and visible paths

Commit: the batch commit containing this section.

### Result

This batch restores the fixed baseline's component ownership instead of
maintaining Cadr's former line-compaction shim:

| ID | Fixed-baseline contract | Cadr implementation | Independent regression |
|---|---|---|---|
| D08 | `model-selector.ts:91-129,248-307` composes borders, spacers, zero-padding `Text`, `Input`, and a bounded item viewport at natural height; `tui.ts:235-244` and `TuiMainScreen.ts:162-212,250-259,354-370` own document clipping, resize, and optional clear-on-shrink. | `interactive/selectors/common.lisp` now provides one component-shaped selector frame used by every selector family; `interactive/frame.lisp` preserves natural document height; `cadr-tui/renderer/main-screen.lisp` owns bottom viewport, shrink, resize, overlay suppression, and cursor visibility. The virtual terminal now models real bottom-row scrolling instead of discarding lines below its array. | `GOAL15-SELECTOR-OVERLAYS-PRESERVE-NATURAL-HEIGHT-AND-INPUT-CURSOR`; `GOAL15-OVERLAY-VIEWPORT-CROPS-THE-NATURAL-DOCUMENT-AND-HIDES-OFFSCREEN-CURSOR`; renderer shrink/resize/overlay/cursor tests; all 15 baseline-derived overlay line oracles. |
| D09 | `interactive-mode.ts:719-731` emits `Model scope: ... (Ctrl+P to cycle)` when a scope is active and startup is not quiet; `core/keybindings.ts:77-83` owns both cycle actions. | `bootstrap/commands.lisp` emits the same gated copy and cycles the session-local scope with wrap, per-entry thinking, session entries, extension source, and configured keys; `cadr-tui/keybindings.lisp` owns the defaults. | `GOAL15-MODEL-SCOPE-STARTUP-COPY-FOLLOWS-BASELINE-GATE-AND-GRAMMAR`; `GOAL15-MODEL-CYCLE-TARGET-MATCHES-BASELINE-WRAP-AND-MISSING-CURRENT`; model-selection lifecycle regressions. |
| D10 | `model-selector.ts:213-220,311-320` derives `tab scope (all/scoped)` from `tui.input.tab` and toggles scope. | Model and session selector keybinding definitions include the shared TUI action set; model help and raw input use the configured binding. | `GOAL15-MODEL-SCOPE-HINT-USES-KEY-AND-DESCRIPTION-STYLES`; existing configurable model/session selector tests. |
| D11 | Fixed-baseline visible cwd, parent, and custom session-directory strings omit a non-root trailing separator. | `settings/trust.lisp` owns a display-only directory normalizer; footer, trust, and resume output reuse it without changing filesystem keys. | `GOAL15-VISIBLE-DIRECTORY-COPY-STRIPS-ONLY-NON-ROOT-TRAILING-SEPARATORS`; `GOAL15-TRUST-SELECTOR-COPY-AND-PATHS-MATCH-BASELINE`. |
| D12 | `trust-selector.ts:52-87` uses keybinding-composed `escape/ctrl+c cancel`. | The trust selector derives the full hint from the shared cancel action and styles key/description spans separately. | `GOAL15-TRUST-HELP-STYLES-KEYS-AND-DESCRIPTIONS-INDEPENDENTLY`. |

The clear-on-shrink gate follows fixed precedence exactly: an explicit
`terminal.clearOnShrink` setting wins over `CADR_CLEAR_ON_SHRINK`; the
environment is only a fallback and the default is false. Opening an actual
overlay suppresses the full-clear branch. Termux height changes recompute the
viewport without a full screen erase. These cases are locked independently of
the screen SHA.

### Snapshot and differential evidence

The old overlay hashes encoded incomplete rows, fake cursor coordinates, and
the selector compaction shim. Every new hash was accepted only after the
independent exact-row, natural-height, cursor, ordering, help-copy, and
bidirectional-wrap assertions passed. `docs/visual-parity.md` now mirrors the
authoritative 13 base-screen and 15 overlay hash sets in the tests.

All 12 differential scenarios were freshly captured for Cadr in both
`100x32` and `48x20` against the retained fixed-baseline bytes. D08-D12 were
then removed from the fail-closed disposition ledger. The analyzer accepted
the complete matrix:

```text
render-diff analysis: aligned=6 requires-disposition=88 adjudicated=88
```

The remaining classes are I01 plus the approved later repair classes D04,
D14-D16 and I02. No disposition retains D08, D09, D10, D11, or D12.

### Verification

```text
cadr test summary: systems=9 checks=14589 pass=14589 skip=0 fail=0
```

The first complete verifier run did its job and rejected the initial D08
implementation at the Goal 11 gate. Moving viewport ownership into the main
renderer exposed two old renderer costs that the former 40-line frame shim had
hidden: `clipped-frame-lines` rebuilt every historical line, while
`changed-line-range` and image comparison indexed Lisp lists quadratically.
The repair keeps the raw natural document as the comparison buffer, clips only
lines crossing the terminal write boundary, and walks current/previous lists
linearly. The fixed-baseline component ownership is therefore retained rather
than traded back for the old compaction shim.

The post-repair full N=5000 benchmark measured 4.001ms / 360,272 bytes for a
stable frame, 28.004ms for key-to-frame, and 26.004ms for stream-to-frame
(38.46 deltas/s). All are inside the existing Goal 11 release limits of 50ms,
16MiB, and 20 deltas/s. `MAIN-RENDERER-KEEPS-RAW-DOCUMENT-LINES-AND-CLIPS-ONLY-AT-THE-TERMINAL-BOUNDARY`
locks the ownership and terminal-width boundary independently.

The root binary was rebuilt after the final source edit before the complete
verifier rerun. That rerun passed every stage:

```text
root cadr binary freshness                       PASS
code organization gate                           PASS
real source parity ledger                        PASS
source parity drift self-test                    PASS
deterministic FiveAM                             PASS
isolated cadr build                              PASS
isolated cadr-server build                       PASS
Goal 11 performance and stability gate           PASS
native acceptance smoke                          PASS
native process modes                             PASS
migration PTY smoke                              PASS
Unix socket server smoke                         PASS
terminal lifecycle PTY                           PASS
deterministic TUI harness                        PASS
credential-gated FiveAM                          PASS
DeepSeek live TUI                                PASS
```

The live report ran seven items successfully, skipped the Anthropic item
because `ANTHROPIC_API_KEY` is absent, and recorded 32 checks: 31 pass, one
credential skip, zero failures. The real PTY contract now also consumes the
baseline-width Input row; its stale short-row oracle was the sole failure in
the preceding verifier run and was corrected before this clean rerun.
