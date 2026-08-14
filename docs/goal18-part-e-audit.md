# Goal 18 Part E re-review report: capability preservation for the `有意差异` rows

Re-review date 2026-08-09; the subject is all **77** current `有意差异` rows in
`docs/source-parity.md` (the 72 existing rows + the 5 component-export rows
recast by this Part E3). Method: mechanically extract every row whose verdict is
`有意差异`, and check three things row by row — (a) whether the grounds for the
divergence are specific and legitimate, (b) whether the pointer of the
equal-strength behavioral assertion is specific and runnable, (c) whether the
assertion locks baseline behavior or is reverse-engineered from cadr's current
implementation. Every pointer is given as a file/gate name, and can be run
directly by the reader to verify.

## 1. Conclusions first

- All 77 rows have specific grounds for divergence; not one row rests on "more
  Lisp" alone.
- 51 rows (CL-1 through CL-4) are language/build-ecosystem inevitable
  differences and **produce no observable behavioral difference in themselves**;
  their capability surface is locked by the differential-class gates under
  baseline drive (see the per-cluster pointers in §2).
- 26 rows (CL-5) are real behavior-surface divergences, each fitted row by row
  with a runnable assertion pointer; among them, 5 component-export rows were
  recast by this Part and had their assertions filled in (§4).
- The re-review found and has fixed 1 assertion gap: settings-state-sweep did not
  previously enable terminal image support, and the `Show images` and
  `Image width` rows never entered the cross-implementation comparison (§4.3).
- The unrecorded-divergence inventory (§3) found no new unregistered divergence.

## 2. E1: row-by-row re-review of the seventy-seven rows

### Cluster definitions

- **CL-1 declaration files / barrel files / module topology** (9 rows):
  TypeScript `.d.ts`, barrel exports and runtime-split declarations have no
  corresponding artifact in Common Lisp; they carry no observable behavior. The
  capability surface is locked by the package-export freeze gate (goal 14 B10)
  and by the individual capability tests.
- **CL-2 dynamic import build mechanism** (12 rows): the lazy loading of
  `*.lazy.ts` is a JS build optimization with no behavioral semantics; the
  provider adaptation behavior that is delivered is locked by
  `test/cadr-ai/provider-payloads-test.lisp`, `provider-streams-test.lisp`,
  `provider-responses-test.lisp` and the fixed-baseline payload
  cross-implementation-comparison gate — the expected values come from the
  fixtures of the baseline checkout, not from cadr's current implementation.
- **CL-3 Bun runtime split** (4 rows): Bun conditional
  registration/bootstrap/sandbox-env restoration have no counterpart under the
  single SBCL image; the behavior is locked by two verify.sh stages, the
  isolated build and the native acceptance smoke.
- **CL-4 test infrastructure and development odds and ends** (26 rows): 8
  vitest.config files, 16 test helper modules, 2 scratch files. The
  exportability of a Vitest helper is an artifact of the JS test ecosystem; the
  corresponding behavioral guarantee is carried by `./scripts/test-cl.sh` (the
  FiveAM suites, 15493 checks) and the credential-gated live suites, and the
  live/offline separation is guaranteed by the ASDF system split.
- **CL-5 behavior-surface divergence** (26 rows): see the row-by-row pointers in
  the table below.

### CL-5 row-by-row pointers (26 rows)

| Baseline file | What diverges and the legitimate grounds | Equal-strength assertion pointer |
|---|---|---|
| `ai/src/cli.ts` | A standalone npm login CLI merged into the cadr CLI (markedly less code / product shape) | `test/cadr-cli/config-auth-test.lisp`, `live-auth-test.lisp`, verify.sh native process modes |
| `ai/src/compat.ts` | JS compatibility barrel/registry → the CADR-AI package + generic functions (removes a hand-maintained invariant) | `test/cadr-ai/provider-registry-test.lisp`, `provider-compat-test.lisp` |
| `ai/src/compat/extension-oauth-types.ts` | TS structural callback types → callable slots (language-inevitable) | `test/cadr-agent/goal12-extension-api-test.lisp`, extensions-wave2/3 |
| `ai/src/legacy-api-aliases.ts` | cadr never published the old JS symbol names, and there is nothing to be compatible with; the stable surface is the Lisp API | `test/cadr-ai/provider-compat-test.lisp` locks the current API surface |
| `ai/src/model-catalog.ts` | Nested TS groups → a hash-table catalog, with lookup/enumeration preserved (markedly less code) | `test/cadr-ai/goal12-model-data-test.lisp`, `models-runtime-test.lisp` |
| `ai/src/utils/abort-signals.ts` | AbortSignal objects → predicates/conditions + unwind cleanup (eliminates a bug class: the goal 13 exit-deadlock / cancellation-not-chaining family) | `test/cadr-cli/goal18-login-cancel-test.lisp`, `test/cadr-ai/retry-test.lisp`, `http-test.lisp` |
| `ai/src/utils/typebox-helpers.ts` | TypeBox construction helpers → JSON Schema directly (language-inevitable) | `test/cadr-ai/provider-payloads-test.lisp`, the tool-result cross-implementation-comparison gate |
| `coding-agent/src/config.ts` | Path owner converged, install-method expressed in terms of the SBCL image, getToolsDir registered as dead code, getDebugLogPath implemented by /debug (Part B/C/D) | verify.sh migration PTY smoke, `test/cadr-cli/part-b-config-test.lisp`, `goal18-debug-command-test.lisp` |
| `coding-agent/src/core/extensions/index.ts` etc., 5 rows | JS module loader/types/runner → a Lisp package/form registry + immutable snapshot + host (an adjudicated structural divergence: unlocks Lisp extension capability) | `test/cadr-agent/goal12-extension-api-test.lisp` (including the declared-but-disconnected dispatch audit), `extensions-test.lisp`, wave2/3, live `LIVE-DEEPSEEK-SELF-EXTENSION-WRITE-RELOAD-AND-INVOKE` |
| `coding-agent/src/core/output-guard.ts` | monkey-patching Node stdout → explicit output/error streams (eliminates a bug class: protocol output pollution) | `test/cadr-cli/rpc-test.lisp`, `goal9-a2-process-faux-test.lisp`, live `LIVE-DEEPSEEK-PRINT-MODE-EMITS-ONLY-FINAL-TEXT` |
| `coding-agent/src/core/prompt-templates.ts` | Resource discovery structure follows the Lisp ecosystem (language-inevitable, capability-equivalent) | `test/cadr-agent/resources-test.lisp`, the startup resource block fixture (strengthened in Part H) |
| `coding-agent/src/core/skills.ts` | Same as above | `test/cadr-agent/resources-test.lisp`, `test/cadr-agent/session-v2-test.lisp` |
| `coding-agent/src/utils/clipboard-native.ts` | Node native module → an injected platform command bridge (language-inevitable) | `test/cadr-cli/part-b-interactive-test.lisp`, `goal13-presentation-test.lisp` |
| `coding-agent/src/utils/image-resize-worker.ts` | Node worker entry point → a native synchronous pipeline (markedly less code) | the resize coverage in `test/cadr-cli/part-b-interactive-test.lisp` |
| `coding-agent/src/utils/photon.ts` | The approved pure-Lisp PNG/JPEG codec replaces the native binding (eliminates a dependency class) | `test/cadr-cli/part-b-interactive-test.lisp`, the image fixture tests |
| `coding-agent/src/utils/sleep.ts` | Promise wrapper → CL:SLEEP + dynamically rebindable injection (language-inevitable) | `test/cadr-cli/goal18-login-cancel-test.lisp`, `test/cadr-ai/retry-test.lisp` |
| `agent/src/stream-fn.ts` | A process-level global default stream → per-agent injection (removes a hand-maintained invariant; prevents multi-session pollution) | `test/cadr-ai/faux-provider-test.lisp`, and every suite runs through injection (there is no global default to rely on) |
| 5 component-export rows (extension-selector / show-images-selector / skill-invocation-message / theme-selector / thinking-selector) | See §4: the component classes are deliberately not exported, and the equivalent capability is provided through host-side rendering / native settings rows | See the per-row ledger notes in §4 and the coverage fix in §4.3 |

### On check item (c) (the assertion locks the baseline rather than being reverse-engineered)

The expected values of the differential-class pointers (render-diff,
tool-result, event and payload cross-implementation comparison) are all
generated under the drive of the fixed baseline checkout `53fa77ccd`, and the
cadr implementation takes no part in constructing the expected values; among the
FiveAM pointers, every assertion that locks copy/behavior gives the baseline
file:line source in a note or a test comment. All 5 rows recast by this Part
checked the baseline call site first and only then reached a conclusion (§4).

## 3. E2: unrecorded-divergence inventory

Method: taking "observable behavior does not match, but is not among the 77
rows" as the subject, do a structural sweep along the coverage boundaries of the
four existing traffic lanes, and inventory the cadr-side additions relative to
the baseline:

1. **Layout divergence** (the `~/.cadr/agent/` layer) — goal 18 Part B/C already
   aligned it with the baseline and recorded it (the note on the config.ts row),
   and it is no longer an unrecorded divergence.
2. **cadr-side added capabilities** were checked item by item for registration
   status: crash redaction (I02, adjudicated and registered in
   `docs/open-questions.md` as OQ-G15-I02-FATAL-REDACTION), the `/share` viewer
   `https://cadr.dev/session/` (I03, registered in open-questions and the README
   difference list), product identity (I04, the README difference list), and
   `:tool-call-error`, the 34th extension event, together with `originator=cadr`
   (README:387, :480 and :490 are all registered). **All of them are on the
   ledger.**
3. **Known presentation-layer differences** are all registered checkpoint by
   checkpoint by the render-diff dispositions (268 of them, each with a specific
   note + an exact screenSha256), with nothing off the ledger.
4. The coverage gap newly found in this round (the settings image rows were not
   cross-compared) is "the assertion is not in place", not a behavioral
   divergence; it has been fixed in §4.3.

Conclusion: apart from the layout divergence that Part B already handled and
recorded, no new unrecorded divergence was found.

## 4. E3: set comparison of the extension API export surface (23 `*Component`s)

### 4.1 Set comparison method

The baseline `packages/coding-agent/src/index.ts` exports 23 `*Component`s. Each
was checked for its **real consumption point** in the baseline (called inside
the product / imported by an extension or example / only re-exported by a
barrel), and then compared against cadr's functional landing point.

### 4.2 Key facts (all re-checkable in the baseline checkout)

- `ShowImagesSelectorComponent`, `ThemeSelectorComponent` and
  `ThinkingSelectorComponent` have, in the baseline, **zero product calls in the
  whole repository and zero extension/example imports** — only two barrels,
  `components/index.ts` and `src/index.ts`, re-export them. That is, these three
  components do not exist at all in the baseline's user-visible interface; the
  premise in the advisor table of goal18.md that "the baseline is a two-option
  selector" **took the export list for the actual scene**. The baseline's actual
  scene is the boolean settings row at `settings-selector.ts:627-632` (label
  `Show images`, description `Render images inline in terminal`), which matches
  cadr word for word.
- `ExtensionSelectorComponent` (startup-ui.ts:152,
  interactive-mode.ts:2261/5018) and `SkillInvocationMessageComponent`
  (interactive-mode.ts:3327) are **host-internal renderers**: an extension
  triggers them through `ctx.ui.select`/`ui.custom`/session content, and the
  host instantiates them on its behalf; not one of the baseline
  examples/extensions imports these two classes.
- The other 18 components all have a same-named functional landing point in cadr
  (the transcript/selector/component rendering families), locked by render-diff
  screen-by-screen cross-implementation comparison.

### 4.3 Verdict and disposition

**Verdict: the five component classes are deliberately not exported; this is a divergence, recorded on the ledger and fitted with an equal-strength assertion.**
Grounds: the baseline extension ecosystem never consumes these classes (the
consumption surface is the `ctx.ui` callbacks and host-side rendering), and
cadr's extension API has already been adjudicated into a host-mediated Lisp form
(goal 13); exporting a Lisp equivalent for a class nobody consumes provides no
capability at all, and would only manufacture a second UI construction entry
point.
The user-visible behavior (the settings rows, the skill invocation message, the
extension selector) is locked by the following assertions:

- The verdict on the 5 ledger rows was changed from `已实现` to `有意差异`, and
  the note states the baseline consumption-point evidence, cadr's equivalent
  landing point and the assertion pointer (the corresponding rows in section 4.2
  of docs/source-parity.md; the summary table and the header counts were updated
  in step to 595 = 518 + 77 + 0).
- **Coverage fix**: `settings-state-sweep` is now driven with
  `setup.supportsImages=true`, and its 34 row checkpoints traverse every
  settings row including `Show images` and `Image width` (image support was not
  enabled before, and these two rows had never been cross-compared — the
  assertion gap this Part found and fixed); all 72 checkpoints on both sides are
  locked screen by screen, and the visible text matches the baseline
  (byte-for-byte equal on the narrow screen; on wide, only the trailing-padding
  difference of the product-name placeholder, I04).
- The skill invocation message is locked by
  `test/cadr-agent/resources-test.lisp` and `session-v2-test.lisp`, and the
  baseline-side construction is driven by the construction suite within the
  baseline-visible-strings list.
- The extension selector is locked by the
  `test/fixtures/extensions/rpc-ui.lisp` suite and the render-diff
  `extension-surfaces` scenario.

## 5. Remediation list

| Item | Status |
|---|---|
| Recasting the 5 component-export rows as `有意差异` + specific notes + assertion pointers | Done (this Part) |
| The settings-state-sweep image-row coverage gap | Done (the scenario enables image support, and the 72 checkpoints were re-compared) |
| Updating the summary table / header counts / goal12-examples-test in step (523/72 → 518/77) | Done |
| Re-review of the grounds and assertion pointers for the other 72 rows | Done (the §2 table; no remediation items) |
| The unrecorded-divergence inventory | Done (§3; nothing new) |
