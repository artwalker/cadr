# Goal 27 — same result, faster representation

> **Status:** met (2026-09-08). 2 kept-faster, 3 no-keep, dialog out-of-scope.
> Does **not** reopen Goal 20–26 as incomplete.
> Goal 26 remains terminal `met` (11 met-beat, 6 accepted-runtime-gap).

## Why this exists

Goal 26 refused any keep above 1.0×. The remaining six product paths are still slower than pi. The operator asked for another goal that may land a speedup only when the observable result does not change.

## Target

| bar | meaning |
|---|---|
| **Keep** | Fair Friend-MachineD remesure strictly faster than current HEAD, and behavior checks match HEAD |
| **Preferred** | Ratio ≤1.0× on that same fair ruler |
| **Forbidden** | A faster path that changes file bytes, search text, enabled membership, atomic replace, or concurrent safety |

「Same result」means the caller-visible value. When the string is built may move. The string, the enabled set membership, and the replaced file bytes may not.

## Cohort

The six Goal 26 `accepted-runtime-gap` rows. Dialog has no remaining semantic-preserving knife (struct missed 1.0×, recycle is not concurrent-safe). It stays out unless a new knife preserves concurrent RPC.

| metric | allowed knife |
|---|---|
| `cli_selectors.scoped_model_selector_search_text` | Store the same search string on the model or an eq cache filled before the timed read. Returned text must match HEAD `format`. |
| `cli_selectors.scoped_models_enabled_set` | Cheaper membership structure. Update both call sites in `models.lisp`. Membership and id order must match HEAD `gethash`. |
| `cli_support.write_overwrite` | Faster atomic replace. Temp plus rename stays. Missing parents still created. Bytes match. |
| `cli_support.write_hello` | Same write knife. |
| `cli_support.write_empty` | Same write knife. |
| `cli_print_rpc.dialog_request` | Out. No semantic-preserving knife left. |

## Stop predicate

Goal 27 is `met` when **all** hold:

1. Each of the five in-scope metrics is `kept-faster` or `no-keep` with a Friend-MachineD ratio and a behavior note.
2. No keep changes observable results.
3. No leftover-only win. No silent freeze. Dialog is `out-of-scope`.

## Tracks

| track | job |
|---|---|
| **H** | One representation hypothesis, remesure, keep or full revert |

## Evidence matrix

| metric | status | evidence |
|---|---|---|
| `cli_selectors.scoped_model_selector_search_text` | kept-faster 2.170× | `docs/benchmarks/goal27-evidence/search-text/REPORT.md` |
| `cli_selectors.scoped_models_enabled_set` | kept-faster 0.0367× | `docs/benchmarks/goal27-evidence/enabled-set/REPORT.md` |
| `cli_support.write_overwrite` | no-keep | `docs/benchmarks/goal27-evidence/atomic-write/REPORT.md` |
| `cli_support.write_hello` | no-keep | same write unit |
| `cli_support.write_empty` | no-keep | empty slower than HEAD on h1 and h2 |
| `cli_print_rpc.dialog_request` | out-of-scope | no semantic-preserving knife |

## Claimed

- Charter open 2026-09-08. Met 2026-09-08. Search-text and enabled-set kept. Atomic write reverted. No result change. Dialog stayed out.
