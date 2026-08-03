# Goal 15 Part B: fixed-baseline render differential

## Scope and fixed inputs

- Baseline: `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.
- Matrix: 12 scenarios, 34 required coverage labels, 2 dimensions
  (`100x32`, `48x20`).
- Evidence: raw PTY bytes, raw SHA-256, normalized derivatives, checkpoint
  offsets, terminal-emulated styled screens, and machine-checked dispositions.
- Result: 94 checkpoint/dimension pairs = 6 byte-aligned + 18 intentional-only
  + 70 containing at least one Cadr defect. All 88 differing pairs have an
  explicit disposition; none is pending or unclassified.

The machine-readable authority is
`test/fixtures/render-diff/dispositions.json`. `render-diff.py analyze` rejects
missing, stale, duplicate, unknown-class, wrong-baseline, and aligned-state
dispositions.

## Harness-equivalence corrections made before judging Cadr

The comparison drivers were corrected before classification; treating these
as product defects would have made the ledger lie.

| Correction | Why it matters |
|---|---|
| Both sides expose the same seven coding tools and current `edit.edits[]` schema | A different tool surface changes model/tool rendering before Cadr is involved. |
| Pi uses compact startup (`verbose=false`) | Cadr's compact startup must be compared to the baseline compact startup, not Pi's expanded help. |
| Scoped model, provider, session, tree, trust, settings, and auth fixtures describe the same domain state | Overlay item differences must come from rendering/behavior, not fixture asymmetry. |
| The Cadr custom OAuth prompt carries its URL in the same prompt object instead of sending an obsolete separate URL notice | The previous driver produced a duplicate URL and `NIL` inside the dialog; that was a driver bug, not a product finding. |
| Provider credential environment variables are removed and both homes are temporary | Ambient user auth/catalog/settings cannot change a supposedly deterministic capture. |
| Cadr's slow faux stream mutates a partial assistant message and emits the same fixed chunks as Pi | Appending deltas to an already-complete message produced false duplicated text. |
| Semantic replay consumes raw bytes before screen normalization | Replaying longer placeholders changed cursor geometry and fabricated stale cells. The self-test locks the original cursor column while normalizing only displayed values. |
| Self-replay judges terminal state at every checkpoint and reports raw identity separately | A final rerun caught an optional blank editor frame in one of two non-stream Cadr captures. Fixed faux output still crosses worker/render threads, so normalized raw-stream identity was a false determinism criterion; both terminal-emulated screens and cursors were identical. The bytes remain retained under I01 instead of being normalized away. |

## Difference classes

### Intentional differences

| ID | Disposition | Basis |
|---|---|---|
| I01 | SBCL and TypeScript use different ANSI update segmentation and teardown sequences when the resulting terminal state is otherwise the same. | This is an implementation/runtime consequence, now registered in README. Raw evidence is retained; no text, color, geometry, or cursor difference is excused. |
| I02 | Cadr emits a bounded redacted fatal summary and private crash-log path instead of Pi's terminal stack dump. | Approved Goal 13 security hardening; Cadr evidence is in `src/cadr-ai/crash.lisp` and `src/cadr-cli/crash.lisp`, while Pi dumps at `interactive-mode.ts:3671-3721`. |

### Cadr defects

| ID | Observed difference | Baseline evidence | Cadr path |
|---|---|---|---|
| D01 | Startup chrome lacks Pi's one-cell output padding and OSC title; product/version styling and compact-help spacing differ. | `interactive-mode.ts:687-812` | `src/cadr-cli/interactive/frame.lisp`; startup composition in `src/cadr-cli/bootstrap/commands.lisp` |
| D02 | Transcript/editor composition inserts two extra rows, changing viewport clipping and cursor position. | Interactive composition at `interactive-mode.ts:687-812`; components provide their natural heights. | `src/cadr-cli/interactive/frame.lisp:248-365` |
| D03 | Footer cwd, initial context, usage totals, and single-provider thinking suffix differ. | `components/footer.ts:90-187` | `src/cadr-cli/interactive/footer.lisp:3-63`; `src/cadr-cli/bootstrap/commands.lisp:724-777,1936-1960` |
| D04 | Untrusted startup omits the warning entirely. | `interactive-mode.ts:3543` | trust/startup bridge in `src/cadr-cli/bootstrap/commands.lisp` |
| D05 | `grep` ordering is `alpha,beta` in Cadr versus `beta,alpha` in the fixed baseline capture. | Fixed baseline tool execution and captured result; order is observable. | `src/cadr-cli/tools/grep.lisp:10-137` |
| D06 | `ls notes` returns root files (`created.txt`, `sample.txt`) instead of `notes/alpha.txt`, `notes/beta.md`. | `core/tools/ls.ts:143-150` resolves the requested directory and sorts its entries. | `src/cadr-cli/tools/ls.lisp:10-72` |
| D07 | Missing read says `File not found: missing.txt`; Pi says `ENOENT: no such file or directory, access '<cwd>/missing.txt'`. | `core/tools/read.ts:164-342` preserves the filesystem error result. | `src/cadr-cli/tools/read.lisp:16-18` |
| D08 | Selector frame padding, input column, viewport height/clipping, and cursor geometry differ across every overlay family. | `components/model-selector.ts`, `session-selector.ts`, `tree-selector.ts`, `settings-selector.ts`, `oauth-selector.ts`, `login-dialog.ts`, `trust-selector.ts` | shared selector/composition paths in `src/cadr-cli/interactive` and `src/cadr-tui` |
| D09 | Scoped-model startup omits `Model scope: faux-1, other-1 (Ctrl+P to cycle)`. | `interactive-mode.ts:731` | no corresponding startup emission |
| D10 | `/model` omits `tab scope (all/scoped)`. | `components/model-selector.ts:93-126,300-304` | model selector in `src/cadr-cli/interactive` |
| D11 | User-visible cwd, trust-parent, and custom session-dir values retain an extra trailing slash. | Pi renders the supplied normalized strings without adding `/`. | `src/cadr-cli/interactive/footer.lisp:3-23`; `src/cadr-cli/support/resume-version-git.lisp:20-38` |
| D12 | `/trust` help says `escape cancel`, omitting `ctrl+c`. | `components/trust-selector.ts:53-86` | trust selector rendering in `src/cadr-cli/interactive` |
| D14 | Busy queue uses lowercase `alt+up` and Working/queue lines lack Pi's left padding. | `interactive-mode.ts:4011-4141`; pending hint source at `:4025` | `src/cadr-cli/interactive/pending-messages.lisp:33-66`; `frame.lisp:172-207` |
| D15 | `/reload` appends a new status while Pi replaces the preceding `/export` status. | `interactive-mode.ts:5458-5480` uses the status surface. | `src/cadr-cli/interactive/status.lisp:18-38` and command plumbing |
| D16 | Fatal output begins before clean terminal teardown and overwrites the editor/footer region. | Pi restores/stops the interactive surface before its fatal output at `interactive-mode.ts:3646-3721`. | Cadr fatal boundary plus `src/cadr-cli/interactive/controller.lisp:2200-2240` cleanup |

`D13` is deliberately absent: the apparent duplicate OAuth URL was traced to
the comparison driver and removed before final capture.

## Checkpoint disposition matrix

Every row applies identically to wide and narrow captures. `I01` classifies
raw terminal-protocol bytes; `D*` classes classify visible/semantic Cadr
defects. Process-exit rows with only I01 add no new visible difference.

| Scenario | Checkpoint | Classes |
|---|---|---|
| startup-first | startup | I01 D01 D02 D03 |
| startup-first | process-exit | I01 |
| startup-existing | existing-session | I01 D01 D02 D03 |
| startup-existing | post-exit-resume | I01 D11 |
| startup-existing | process-exit | aligned |
| startup-untrusted | untrusted-startup | I01 D01 D02 D03 D04 |
| startup-untrusted | process-exit | I01 |
| conversation-content | plain | I01 D01 D02 D03 |
| conversation-content | markdown-code-thinking | I01 D01 D02 D03 |
| conversation-content | cjk-emoji | I01 D02 D03 |
| conversation-content | process-exit | I01 |
| tools-success | bash-multiline | I01 D01 D02 D03 |
| tools-success | read-range | I01 D02 D03 |
| tools-success | write | I01 D02 D03 |
| tools-success | edit | I01 D02 D03 |
| tools-success | grep | I01 D02 D03 D05 |
| tools-success | find | I01 D02 D03 D05 |
| tools-success | ls | I01 D02 D03 D05 D06 |
| tools-success | process-exit | I01 |
| tools-failure | tool-failure | I01 D01 D02 D03 D07 |
| tools-failure | bash-nonzero | I01 D02 D03 D07 |
| tools-failure | bash-timeout | I01 D02 D03 D07 |
| tools-failure | process-exit | I01 |
| overlays-core | overlay-model | I01 D01 D02 D03 D08 D09 D10 |
| overlays-core | overlay-session | I01 D01 D02 D03 D08 D09 |
| overlays-core | overlay-fork | I01 D01 D02 D03 D08 D09 |
| overlays-core | overlay-tree | I01 D01 D02 D03 D08 D09 |
| overlays-core | overlay-settings | I01 D01 D02 D03 D08 D09 |
| overlays-core | overlay-trust | I01 D01 D02 D03 D08 D09 D11 D12 |
| overlays-core | process-exit | I01 |
| overlays-auth | auth-method-generic | I01 D01 D02 D03 D08 |
| overlays-auth | login-provider | I01 D01 D02 D03 D08 |
| overlays-auth | auth-method-provider | I01 D01 D02 D03 D08 |
| overlays-auth | login-dialog | I01 D01 D02 D03 D08 |
| overlays-auth | login-cancelled | I01 D01 D02 D03 |
| overlays-auth | process-exit | I01 |
| stream-interrupt-queue | busy-queue | I01 D01 D02 D03 D14 |
| stream-interrupt-queue | stream-aborted | I01 D01 D02 D03 |
| stream-interrupt-queue | process-exit | I01 |
| provider-error | provider-error | I01 D01 D02 D03 |
| provider-error | process-exit | I01 |
| commands-and-exit | slash-export | I01 D01 D02 D03 |
| commands-and-exit | slash-reload | I01 D01 D02 D03 D15 |
| commands-and-exit | post-exit-resume | I01 D01 D02 D03 D11 D15 |
| commands-and-exit | process-exit | aligned |
| fatal-crash | fatal-crash | I01 I02 D01 D02 D03 D16 |
| fatal-crash | process-exit | aligned |

## Content that already aligns

The differential also establishes what does not need a repair batch: plain,
Markdown, fenced-code, CJK, emoji, thinking, multiline bash body, read-range,
write, edit, find, bash nonzero, bash timeout wording, provider-error wording,
export wording/filename, reload wording, abort wording, queued message contents,
and the successful OAuth dialog's title, URL, instructions, input prompt, and
cancel text all match once unrelated global composition defects are separated.

## Normalization ruling requested

The exact candidate list is in `docs/render-diff.md`: isolated home/cwd/sandbox
prefixes, immutable baseline cache path, exact product/version/header/title and
product-prose tokens, exact fixed export filename, `Took <number>s`, one
spinner code point in the exact styled Working context, and the numeric crash
ID. Recommendation: approve all candidates. Each removes a value that is
necessarily distinct or scheduler-generated while preserving whitespace,
colors, cursor operations, punctuation, ordering, units, and surrounding
syntax. Raw captures are never rewritten.

Part C must not begin until the user rules on these candidates and chooses the
repair batches, as required by Goal 15.

## Verification evidence

The final capture analyzer reported:

```text
render-diff analysis: aligned=6 requires-disposition=88 adjudicated=88
```

Two fresh self-replays and the scheduler-active stream replay passed the
semantic checkpoint gate while reporting raw identity honestly:

```text
render-diff self-test: PASS pi_raw_equal=true cadr_raw_equal=true semantic_equal=true
render-diff replay-check: PASS scenario=stream-interrupt-queue dimension=wide pi_raw_equal=false cadr_raw_equal=false semantic_equal=true
```

The deterministic suite passed in both the working tree and the isolated
release copy:

```text
cadr test summary: systems=9 checks=14393 pass=14393 skip=0 fail=0
```

`./scripts/verify.sh` completed every stage:

```text
Deterministic stages
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

Live stages
credential-gated FiveAM                          PASS
DeepSeek live TUI                                PASS
```

The live report ran 7 items successfully, skipped only Anthropic for the
missing credential, and failed none: `8 items / 7 pass / 1 skip / 0 fail`,
`32 checks / 31 pass / 1 skip / 0 fail`.

The delivery binary is newer than every `src/` input:

```text
binary build time: 2026-08-04 04:22:07.353408779 +0800
latest src commit: f0bb57f9f7ad137556bfaac630e198ae58778a6f 2026-08-04T01:30:04+08:00
latest source mtime: 2026-08-04 01:27:16.385190117 +0800 src/cadr-tui/components/tool-block.lisp
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

## Deferred live-eval note

`LIVE-DEEPSEEK-EVAL-SMOKE` is not changed in this Part. A future task must
compare its strict `Paris` equality assertion with the fixed baseline before
either preserving or relaxing it; no unverified widening is authorized.
