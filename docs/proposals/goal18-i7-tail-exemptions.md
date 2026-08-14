# Goal 18 I7 closeout: coverage-exemption proposal for ten baseline branches (adjudicated)

Status: **Adjudicated (`USER-2026-08-10-001`, ledger commit `b435ef522`).** This proposal
requests only an exemption verdict; it does not change any product behavior.

## Background

goal18.md I7 requires that every printable branch of the baseline visible-string
inventory be captured or explicitly exempted. This round brought the uncaptured
branches down from 59 to 10: 49 were recorded in the ledger through real fixes
plus differential scenarios or constructed drives (migration output, the
`--list-models` table and the models.json warning, the `-ne` hint on extension
load failure, the keybinding-conflict diagnostic, the prompt-file warning, pnpm
and the Update note, and so on); the remaining 10 branches were confirmed by
source review one by one to be **not deterministically drivable** in this
project's gate environment, and an exemption is requested.

Exemption mechanism: `test/fixtures/render-diff/visible-string-exemptions.json`
(schema 3, fail-closed: an unknown, stale or duplicated exemption entry, or one
that already has a real capture, makes the gate fail). The existing
`obstacleKind` enumeration does not contain "defensive fallback / permission-
dependent failure arm", so this case adds the `unreachable-in-harness` kind (and
at the same time introduces `unreachable-in-baseline` for defensive fallback
branches); both were recorded in the ledger together with the adjudication.

## Class A: defensive fallback branches (reached only when a non-Error value is thrown, unreachable from user input) — 5 branches

Site-by-site audit conclusion: these `error.message || "<fallback>"` branches are
reached only when a **non-Error object** is thrown; every throw site in the
baseline itself is an Error carrying a message.

| Branch | Location | Audit basis |
|---|---|---|
| `B-fd13d93a29bf` | `main.ts:150` "Failed to parse auth command" | all 12 throw sites in `credential-print.ts` are `CredentialPrintError` (:38,51,56,68,71,74,99,111,140,143,145,149); `parseArgs` only records diagnostics and does not throw |
| `B-3f0215f4a9d2` | `main.ts:211` "Failed to resolve credential" | `resolveCredentialForPrint` throws only `CredentialPrintError`; the models.json load errors of `ModelRuntime.create({allowModelNetwork:false})` are conveyed as return values through `model-config.ts:251,261,271` rather than thrown |
| `B-fa0be7fade22` | `main.ts:633` "Failed to export session" | every throw site of `exportFromFile` carries a message (`export-html/index.ts:245,248,293`) |
| `B-85d3c79ec77b` | `package-manager-cli.ts:733` "Unknown model catalog refresh error" | both the network failures and the parse failures of `refreshModelCatalogs` carry a message |
| `B-c5a60ab5ff3b` | `package-manager-cli.ts:870` "Unknown package command error" | the operation failures wrapped by the two catch-alls both carry a message |

The corresponding paths on the cadr side already implement same-shape fallback
copy (non-credential errors take their respective fallback messages).

## Class B: permission-dependent failure arms (not deterministically reachable as root) — 4 branches

| Branch | Location | Notes |
|---|---|---|
| `B-d987d23f73bb` `B-4b479e0533e6` | `migrations.ts:148` "Warning: Could not migrate … to prompts/: " | requires `rename(2)` to fail (EACCES); the gate runs as root, so permission bits have no effect; tsx loads the baseline through ESM linking, so patching `fs` is unreachable (measured); the setuid subprocess approach is unreadable because the instrumented tree is a 0700 temporary directory |
| `B-a329842f84c5` `B-c1b8a22b174c` | `file-processor.ts:80` "Error: Could not read file " | same as above (requires `readFile` EACCES); in the directory case the baseline crashes before mime detection (uncaught exception), and cadr normalizes it to that copy under the established P0-1 rule and pairs it with a FiveAM test |

On the cadr side: the migration failure arm is paired with a FiveAM test through
the `*migration-rename-function*` injection seam (the failure assertion of
`goal18-commands-directories-migrate-to-prompts`); the @file directory case is
locked by a FiveAM test
(`goal18-file-argument-directory-is-a-normalized-error`).

## Class C: operating system unavailable — 1 branch

| Branch | Location | Notes |
|---|---|---|
| `B-6e91fc06717b` | `tools-manager.ts:349` "not found. Install with: pkg install " | reached only under `platform() === "android"` (Termux); the existing `unavailable-operating-system` kind applies |

## Existing pending items submitted for adjudication together with this case

The following entries were already marked pending adjudication in earlier batches and are
listed here together (see the acceptance report for details):

1. `--resume <id>` (a cadr extension: the baseline has only the selector form).
2. The npm package install source is unavailable in cadr, while `--help` shows
   the npm package example as in the baseline.
3. `update --models`: the baseline refreshes the model catalog over the network;
   cadr's model catalog is built into the binary.
4. Telemetry: the baseline sends an install report to pi.dev; cadr has no such
   outlet.
5. The pre-TUI session selector when `-r` has no argument (startup-ui.ts); cadr
   resumes the most recent one directly.
6. The sentinel model state of the TUI in a bare environment vs cadr's openai
   fallback.
7. cadr's own switches (`--slynk`, `--no-tui`) were removed from --help in order
   to align verbatim with the baseline.
8. (new) The two baseline documentation URLs in the deprecated-directory warning
   (github.com/earendil-works/pi-mono): keep them verbatim (output alignment) or
   replace them (cadr has no equivalent page yet).
9. (new) Keybinding storage: the baseline reads a `keybindings.json` file; cadr
   reads the `keybindings` key of settings.json. Whether to add
   keybindings.json support or record it as intentional difference.

## Ledger actions after the adjudication

Recorded in the ledger (`b435ef522`): the 5 Class A branches under
`unreachable-in-baseline`, the 4 Class B branches under
`unreachable-in-harness`, and the 1 Class C branch under
`unavailable-operating-system` were all written into the exemption registry,
each carrying `userDecisionId: USER-2026-08-10-001`, `baselineEvidence` and a
probe; the full gate turned green on those 10 branches.
