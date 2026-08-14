# Goal 18 Part H review report: the startup resource blocks and the empty-environment blind-spot sweep

Review date 2026-08-09. Two parts: (H1) the baseline-alignment fix for the
startup resource blocks; (H3.3) a systematic sweep of the interfaces that
render only in a particular state.

## 1. The H1 fix list (measured against baseline interactive-mode.ts:1451-1650)

| Item | Before the fix | After the fix (= baseline) |
|---|---|---|
| Block order | Skills → Prompt Templates → Themes → Context | Context → Skills → Prompts → Extensions → Themes → [Skill conflicts] → [Prompt conflicts] → [Extension issues] |
| Prompts label | `Prompt Templates` | `Prompts` |
| [Extensions] | Missing | The block is present (mdHeading title, compact minimal-unique-suffix labels, expanded grouped by scope) |
| [Skill conflicts] | Missing (silent when a skill is broken) | Warning-colored block: the collision groups (✓ winner / ✗ loser (skipped)) first, the load warnings after |
| [Prompt conflicts] | Missing | Structurally identical (baseline block :1618-1625) |
| [Extension issues] | Missing (an extension load failure had only a transient notification) | Structurally identical (baseline block :1627-1645, two colors, error/warning) |
| Sorting | All string<, Context sorted as well | The compact lists sort by the baseline's localeCompare semantics, Context keeps insertion order (sort:false) |
| Conflict adjudication | project overrode, and silently | project still wins (baseline resolve() takes project first then user, first-wins), and the collision is recorded — previously the loser was silently discarded, which does not match the baseline's collision diagnostic |
| Layout | A single component with padding-x 1, one blank line fewer than the baseline | The banner (padding-x 1) and the resource blocks (padding-x 0, a separate container) render separately; the separating blank line is a real blank line (baseline Spacer semantics) |

Evidence for the baseline consumption points: three components, among them
`ShowImagesSelectorComponent`, are called zero times in the baseline (see the
Part E report); `[Extension issues]` is a third warning block, outside the
advisor's list, found while this Part read the baseline source — the advisor's
H1 list (only [Skill conflicts]) was incomplete.

## 2. Differential scenarios

`startup-resources` (new): seeds AGENTS.md, two healthy skills, one broken
skill missing its description, one prompt, one directory-style extension
(pi `demo/index.ts` ↔ cadr `demo/extension.lisp`, displayed on both sides
as `demo`), and one custom theme; two checkpoints, compact and ctrl+o
expanded, at two sizes, wide and narrow, including process-exit. The
empty-environment scenarios `startup-first`/`startup-existing`/
`startup-untrusted` are unchanged and keep passing — both states are inside
the gate.

Items that cannot be cross-compared, and their substitute coverage:

- The real load-error text of [Prompt conflicts] and [Extension issues] is
  necessarily different on the two sides (JS Error.message against Lisp
  condition text), so it cannot be cross-compared byte by byte with a fixture;
  the block structure is locked by
  `test/cadr-cli/goal18-startup-resources-test.lisp` with synthetic diagnostics
  (header, path line, message line, the two colors error/warning, block order).

## 3. The H3.3 sweep of state-dependent interfaces

Method: check reachable-interfaces.json's 28 interfaces against the scenarios'
setup states one by one, find the branches that "render only in a particular
state", and confirm that every state has a differential scenario that supplies
it.

| State-dependent surface | Empty/default-state scenario | Non-empty/active-state scenario | Conclusion |
|---|---|---|---|
| Startup resource blocks (Context/Skills/Prompts/Extensions/Themes) | startup-first/existing/untrusted | startup-resources (added by this Part) | Closed |
| Skill load warnings ([Skill conflicts]) | All existing scenarios | startup-resources (broken-skill fixture) | Closed |
| [Prompt conflicts] / [Extension issues] real error text | — | Cannot be cross-compared (implementation-dependent text), FiveAM locks the structure | Closed (structural coverage) |
| The eight login shapes (A5) | overlays-auth-* | overlays-auth-manual-code-complete / browser-callback(+/-complete) | Closed (goal 18 A5) |
| Session list non-empty / relative-time buckets | — | selector-state-sweep (walks every bucket) | Closed |
| Model list (long-list scrolling) | — | selector-state-sweep | Closed |
| Project trust (untrusted / inherited / decision already stored) | startup-untrusted | selector-trust-inherited, the startup-untrusted save path | Closed |
| Update notifications (including the no-hyperlink variant) | — | update-notifications, update-notifications-no-hyperlinks | Closed |
| Conditional branches of the settings rows (the images row) | Regular | settings-state-sweep (supportsImages=true from Part E onward) | Closed |
| Significant tool states (truncation/timeout/non-zero exit/empty output/concurrency) | — | tools-significant-states, tools-failure, tool-bash-abort | Closed |
| Provider error/degradation | — | provider-error | Closed |
| The three compaction states (manual/threshold/overflow) | — | compaction-status-manual/threshold/overflow | Closed |
| Crash (abnormal-termination output) | — | fatal-crash | Closed |
| autocomplete (slash/path/empty prefix) | — | autocomplete-surfaces | Closed |
| Extension UI (selector/input/editor) | — | extension-surfaces | Closed |
| First-run setup (FirstTimeSetup, when there is no settings.json) | — | Unreachable in the differential harness: both drivers run on in-memory settings, so by construction this state is not triggered; on the cadr side it is covered by sdk-services' should-run-first-time-setup-p and the existing suite | Registered as unreachable (by construction) |

Conclusion: apart from FirstTimeSetup (unreachable by the harness's
construction, registered and with its coverage location stated), every
state-dependent surface has a differential scenario that supplies that state.
This table is the review checklist for interfaces added from now on: when an
interface with state branches is added, its empty/non-empty scenario pair must
be registered in this table.
