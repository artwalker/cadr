# Source parity upgrade gate

`docs/source-parity.md` is a fixed-baseline ledger, not a best-effort inventory.
Every baseline upgrade must first enumerate source-file additions, deletions, and
renames with:

```sh
./scripts/check-source-parity-drift.sh \
  --repo /path/to/pi-mono \
  --from OLD_BASELINE_COMMIT \
  --to NEW_BASELINE_COMMIT \
  --dispositions /tmp/source-dispositions.tsv
```

The inventory predicate is identical to Goal 12 Part A: tracked `packages/**/*.ts`
excluding `*.test.ts`. Modified files remain governed by the existing behavioral
and source re-audit; this gate focuses on paths that otherwise silently change the
595-file denominator.

The disposition file is tab-separated:

```text
status	old_path	new_path	decision
A	-	packages/demo/src/new.ts	implement and add a ledger row
D	packages/demo/src/old.ts	-	remove the obsolete ledger row
R	packages/demo/src/a.ts	packages/demo/src/b.ts	rename and re-audit the row
```

Blank decisions, missing drift rows, stale rows, malformed records, unknown refs,
or a missing disposition file fail closed. `scripts/test-source-parity-drift.sh`
proves added/deleted/renamed detection, `*.test.ts` exclusion, the unresolved
failure, and the complete-disposition success path.

The fixed ledger itself is a separate real-input gate:

```sh
./scripts/check-source-parity-drift.sh \
  --ledger-only --dispositions docs/source-parity.md
```

## Named-set enumeration (goal 18 Part L)

File-level drift is not enough: the v0.84.1 upgrade's user-visible surface
changes hide in named sets (flags, settings keys, events, providers, ...).
`scripts/enumerate-baseline-diff.py FROM TO` derives every such set from the
two commits' git objects — no hand-maintained checklist.  Hand passes missed
real changes twice before this tool existed (`--tui-mode`,
`MarkdownSettings.mermaid`), and the first mechanical run caught four more
the advisor's hand list did not have (the `--alt` removal, the
`PI_CONFIG_DIR`/`PI_RADIUS_*`/`RADIUS_API_KEY` env removals, `STY`/`ZELLIJ`,
and the `CredentialPrintError` → `AuthCommandError` rename).

The enumerated classes: CLI flags, slash commands, settings keys (nested
interfaces included), extension events (union-expanded), exported components,
keybinding actions, providers, environment variables, theme tokens, error
classes, tool files, extension type fields, public API export count, RPC
methods, process exit codes, session format versions, and the
file add/delete/rename catch-all.

**Completeness argument ("还有没有第十类")**: the classes above were closed by
walking every producer of a *named, user-observable or contract-bound set* in
the baseline tree: CLI surface (flags, slash commands, exit codes), persisted
or wire contracts (settings keys, session format versions, RPC methods,
provider set, error classes, public API), extension surface (events, type
fields, exported components), interactive surface (keybinding actions, theme
tokens), and environment contract (env vars).  The two things this misses by
construction — anonymous behavioral changes inside functions, and renamed
local symbols — are covered by the 595→670-row source ledger and the
behavioral gates, not by named-set enumeration.  If a future review finds a
named set kind outside this list, it is added here first, not to a hand
checklist.

### v0.84.1 enumeration result (74caa2649 → v0.84.1, generated 2026-08-10)

| Class | Delta |
|---|---|
| CLI flags | +`--tui-mode` / −`--alt` |
| slash commands | none |
| settings keys | +`Markdown.mermaid`, +`fullscreenScrollbar`, +`tuiMode` |
| extension events | none |
| exported components | none |
| keybinding actions | +`tui.altScreen.halfPageUp`, +`halfPageDown`, +`previousPrompt`, +`nextPrompt`, +`tui.editor.historyPrevious`, +`historyNext` |
| providers | +`baseten`, +`qwen-token-plan-individual` |
| environment variables | +`AI_AGENT`, +`STY`, +`ZELLIJ` / −`PI_CONFIG_DIR`, −`PI_RADIUS_SERVER_URL`, −`PI_RADIUS_URL`, −`RADIUS_API_KEY` |
| theme tokens | +`scrollbarThumb` |
| error classes | +`AuthCommandError` (renames `CredentialPrintError`), +`CredentialSynchronizationError`; `RemoteSessionDisposedError` is new but not exported |
| tool files | none |
| extension type fields | +`ExtensionRuntimeState.trackEventBusSubscription`; also `terminate?` on `ToolCallEventResult` and `isSubscription?` on the OAuth provider options (nested shapes the field extractor notes here) |
| public API exports | 34 → 34 |
| RPC methods / exit codes / session format | none |
| files | +182/−36 .ts (7 renames) under `packages/`; of these **+104/−29 non-test** — the hand pass counted 88/27, undercounting again |

This mode enters only the six-column package tables headed by `Baseline file`,
ignores prose and summary tables, accepts exactly the three ledger verdicts,
and fails on malformed separators/rows, duplicates, a row count different from
the Summary total, or a sorted-path SHA-256 different from the recorded manifest.
The digest input is the extracted path only, UTF-8 with one LF per path, sorted
bytewise under `LC_ALL=C`; the checker overrides the caller locale so a clean
checkout produces the same digest under C, C.UTF-8, or en_US.UTF-8.
It is explicit because CI's shallow checkout does not contain the detached
TypeScript baseline object. A normal `--repo/--from/--to` invocation retains the
stronger tree-versus-ledger path-set comparison. `scripts/verify.sh` runs the real
`docs/source-parity.md` gate before the synthetic A/D/R self-test so a synthetic
failure cannot prevent the requested production input from being exercised.

After every row has a human-authored disposition, update the fixed baseline and
counts together in `docs/source-parity.md`, `docs/parity-map.md`,
`docs/performance.md`, and `examples/manifest.sexp`. Their shared
`GOAL12_LEDGER` identity is checked by FiveAM, so an upgrade cannot land with one
ledger still describing the old source set.

The source inventory is only the first upgrade gate. The same upgrade must also
update `baselineCommit` in both
`test/fixtures/render-diff/scenarios.json` and
`test/fixtures/render-diff/dispositions.json`; regenerate
`baseline-visible-strings.json` and its TypeScript source inventory from the new
tree; and adjudicate every added, removed, or changed source site/branch. The
extractor must again report zero unresolved in-root dataflow. A printable branch
without a full-tier checkpoint or an exact physical-obstruction exemption blocks
the upgrade; the current exemption registry is empty.

The same change must update the baseline commit in
`test/fixtures/event-diff/scenarios.json` and the fixed commit constants used by
`scripts/event-diff.py` and `scripts/tool-result-diff.py`. Update the
fixed-version baseline artifact and digest in `scripts/render-diff.py` if
upstream's generated model data changed, then run the complete real render
matrix:

```sh
./scripts/test-render-diff-full.sh
```

This captures all 37 manifest scenarios in both dimensions (74 fresh captures)
before analysis. A new difference without a human disposition fails; a
disposition whose difference disappeared also fails. Every new difference must
be classified as a Cadr defect or an intentional difference with its baseline
evidence and user ruling. Raw PTY bytes and their SHA-256 files remain
authoritative; upgrade work must not broaden normalization to make a new
difference disappear. `scripts/verify.sh` runs the 31-scenario core tier (62
captures); the full wrapper above is separately mandatory after every upstream
baseline change and before a release tag, so an upgrade cannot be accepted from
the source ledger or core render tier alone.

Finally run both non-visual cross-implementation gates against the same new
baseline:

```sh
python3 ./scripts/tool-result-diff.py
python3 ./scripts/event-diff.py
```

This is required even when the PTY matrix is unchanged: tool text returned to
the model and JSON/RPC event ordering are distinct observable channels and are
not derivable from a rendered screen.
