# Goal 18 I2/I7 derived-coverage difference-set report (2026-08-10)

This report is the machine answer to "derived requirements − existing scenarios"
required by goal18.md I2 item 3. The **set** for every category is mechanically
derived from the fixed baseline (53fa77ccd); the gate is fail-closed: it fails if
any one of derived-set drift, a missing mapping, or a stale registry occurs.

## Categories that are mechanically derived and reconciled closed

| Category | Derivation source | Size | Reconciliation method | Difference set |
|---|---|---|---:|---|
| slash commands | the `core/slash-commands.ts` registry (extracted from git) | 22 | every entry of the `reachable-interfaces.json` registry has a capture; the gate checks order and membership | empty |
| interface constructors and construction sites | full scan of `new *Component(` (extracted from git) | 15 constructors / 22 sites | `baseline-interface-inventory.json` fields compared against a fresh git extraction | empty |
| login-dialog forms | the `show*` public methods of `login-dialog.ts` (extracted from git, added in I2) | 8 | the `loginDialogCoverage` mapping: 5 through differential scenario checkpoints, 3 (showDetails/showInfo/showPrompt, no login flow is reachable in the harness) driven byte-for-byte through construction | empty |
| extension events | expansion of the `ExtensionEvent` union in `types.ts` (extracted from git, added in I2) | 33 leaf events | FiveAM asserts the cadr set = the derived set + the adjudicated splits (`tool_call`/`tool_result` → before/after/error) | empty |
| visible-string branches | 246 source files × modeled-sink extraction (pre-existing, 71 produced entries) | 508 sites / 1117 branch entries; of these the printable obligation is 479 sites / 787 branches | per-branch capture or structured exemption | empty (10 branches adjudicated as exempt, see below) |
| unmodeled sink candidates | reverse inventory: among all console/process-write/show*/print* calls, those that carry fixed text and land on no inventory site (added in I7.3) | 14 | a verdict + reason per entry in `visible-string-unmodeled-review.json`, reconciled by the gate | empty |

## Exemption closure of the difference set: 10 branches adjudicated (USER-2026-08-10-001)

Class A defensive fallbacks 5 (`main.ts:150/211/633`,
`package-manager-cli.ts:733/870`), class B permission-dependent failure arms 4
(`migrations.ts:148`, `file-processor.ts:80`), class C Android 1
(`tools-manager.ts:349`); the per-entry audit grounds are in
`docs/proposals/goal18-i7-tail-exemptions.md`. On 2026-08-10 the user adjudicated
(`userDecisionId: USER-2026-08-10-001`, ledger commit `b435ef522`): the 5 class-A
branches under `unreachable-in-baseline`, the 4 class-B branches under the newly
added `unreachable-in-harness`, and the 1 class-C branch under the existing
`unavailable-operating-system` all enter the exemption registry
(`test/fixtures/render-diff/visible-string-exemptions.json` schema 3, each entry
carrying `baselineEvidence` and a probe). The registry's fail-closed semantics are
unchanged: an unknown, stale, duplicate, or already really captured exemption
entry still makes the gate fail; those 10 branches are no longer unclosed items.

## Categories deliberately not mechanically derived, and the reasons (escalated for adjudication)

1. **State-conditional render points** (the `addLoadedSection(...)`,
   `if (xs.length)` kind): derivation yields a site inventory, but the obligation
   "every site must have empty/non-empty two-state scenarios" cannot be
   mechanically bound to a concrete scenario state — whether some state can be
   constructed in the harness, and which scenario supplies it, requires semantic
   judgement. Current mechanism: the I3 two-state rule is written into
   `docs/render-diff.md` (a mandatory rule for new scenarios) + the empty/non-empty
   two scenarios of the six startup-resource blocks are already in place. **If the
   adjudication demands something stricter, a manual mapping table must be
   maintained for every render condition point (which is back to a hand-maintained
   inventory), or the status quo accepted.**
2. **State-transition checkpoints**: I1 has already listed the scroll position /
   selected state / before and after a switch of traversal-type scenarios as
   explicit checkpoints; "whether a checkpoint should be set after every action"
   has no mechanical criterion (actions × checkpoints would explosively enlarge the
   capture volume with no linear gain). Current rule: traversal-type scenarios must
   set points on the key states being traversed (written into the render-diff
   document).

## Current state of the hand-maintained inventory

`REQUIRED_COVERAGE` is still a hand-maintained set, but it has been changed to the
**complete set of current declarations** (138 coverage tags): the deletion of any
scenario or tag fails, coverage cannot regress. Its relation to the derived sets:
the derived sets govern "what the baseline has", the hand-maintained complete set
governs "what the scenarios claim to cover", and both are reconciled by the gate.

## Note on a known coverage form: the startup deprecation-warning block

The deprecated-directory warning of `migrations.ts` (the hooks//tools/ notice +
documentation URL + the "Press any key to continue..." pause) is emitted only on
the interactive path of the baseline's `main.ts`; render-diff's TUI scenarios
construct InteractiveMode directly through the driver, not through main(), so that
block is currently covered by construction driving (byte-for-byte on the baseline
side) + FiveAM on the cadr side
(`goal18-deprecation-warnings-match-the-baseline-text`, including the keypress wait
and the complete copy), with no two-sided scenario. Adding a two-sided
cross-implementation comparison would require a new driver entry point that
"registers the faux and then runs the complete main()" — the gain is not
commensurate with the driving complexity; recorded here.
