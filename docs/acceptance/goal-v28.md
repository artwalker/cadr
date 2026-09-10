# Goal 28 — pi capabilities work on cadr

> **Status:** met (2026-09-10). open-capability=0. 594 fixed, 365 intentional-difference. Pin `d981de1229ef899957bbe968bc8dcda02a21f477` v0.85.1.
> Does **not** reopen Goal 20–27 as incomplete.
> Pin: `BASELINE` `d981de1229ef899957bbe968bc8dcda02a21f477` `v0.85.1`.

## Why this exists

Performance goals closed on ratios. The operator asked for every capability pi can perform to work on cadr, not a hand-picked command slice and not a source-file mirror.

`docs/source-parity.md` and `docs/presentation-parity.md` already claimed alignment and still missed real terminal defects. Those rows do not count as proof here.

## Target

The denominator is the named sets `scripts/enumerate-baseline-diff.py` already extracts, dumped as an absolute inventory from `/root/projects/pi-mono` at the pin. Not a diff against an older tag. Not a hand list.

| class | what a caller can ask for |
|---|---|
| CLI flags, slash commands, exit codes | process surface |
| settings keys, session format versions, RPC methods, providers, error classes, public API exports | wire and contract |
| extension events, extension type fields, exported components | extension surface |
| keybinding actions, theme tokens, environment variables | interactive and environment contract |
| tool files | tools the agent can run |

Anonymous behavior inside a function is in scope only after its named capability is on the table. A green ledger row is not a substitute.

## Row states

`open` · `match` · `intentional-difference` · `fixed`

`match` requires a behavioral assertion locked against the pin, rerunnable, not reverse-engineered from current cadr. `intentional-difference` requires an existing adjudication and the user can still do the thing. If pi can do it and cadr cannot, the row stays a defect until it is `fixed`.

## Stop predicate

Goal 28 is `met` when **all** hold:

1. `scripts/goal28-capability-inventory.py` regenerates `docs/benchmarks/goal28-capabilities.tsv` from the pin.
2. Every required class is present. A class that is empty on the pin has an explicit empty proof.
3. `open-capability=0`. Every row is `match`, `intentional-difference`, or `fixed`.
4. No row became `match` because `docs/source-parity.md` said aligned.

## Tracks

| track | job |
|---|---|
| **R** | Dump the inventory and the open-count gate. No product edits. |
| **H** | One class or one open row. Prove behavior or fix the defect. |

## Forbidden

- Treating source-parity or presentation-parity `aligned` / `covered` as `match`
- Implementing missing features inside the inventory unit
- Reopening Goal 25–27 speed work
- Counting internal Lisp functions as the denominator
