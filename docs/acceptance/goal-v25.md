# Goal 25 — performance hillclimb (post–Goal 24)

> **Status:** open (chartered 2026-09-07). Does **not** reopen Goal 20 or Goal 24.
> Goal 24 remains terminal `met` (disposition bookkeeping). Goal 23 baseline
> alignment to pi `v0.85.1` stands.

## Why this exists

Goal 24 closed leftover **accounting**. It explicitly did **not** require every
paired path ≤1.0×. Operators who want **performance wins** against pi need a
separate goal with a finite invent stop.

## Cohort

Seeded from Goal 24 terminal rows that are still slower / gap-booked:

- `booked-shape-gap` (32)
- `deferred-variance-floor` (94)

**Out of cohort:** `deferred-measure-only` (833), already `met-remesure` (4).

Inventory: `docs/benchmarks/goal25-inventory.tsv`  
Live scoreboard: `docs/benchmarks/goal25-dispositions.tsv`

## Classes

| class | Meaning | Typical close |
|---|---|---|
| `leftover-replica` | Timed leftover collect vs V8 replica | `frozen-leftover-ruler` |
| `subus-floor` | Sub-µs / variance-floor already gate-clean | `frozen-subus-floor` |
| `product-path` / `charter-shape` | Real product timed path (or charter shape needing product remesure) | `met-hillclimb` or `frozen-unreachable` |

## Stop predicate

Goal 25 is `met` when **all** hold:

1. Inventory committed and classes assigned for every cohort metric.
2. `open-hillclimb` count in `goal25-dispositions.tsv` is **0**.
3. Every row's disposition is one of: `met-hillclimb`, `frozen-leftover-ruler`,
   `frozen-subus-floor`, `frozen-unreachable`.
4. Every `met-hillclimb` cites Friend-MachineD remesure evidence with ratio ≤1.0×
   on the **product** timed path (not leftover-only).
5. Every `frozen-*` cites written reason (inventory class and/or adjudications /
   decision log).

「963 paths ≤1.0×」is **not** the stop. Measure-only stays outside the cohort.

## Commands

```bash
python3 scripts/goal25-open-gate.py
python3 scripts/goal25-open-gate.py --require-zero
```

## Evidence matrix

| part | status | evidence | notes |
|---|---|---|---|
| 1 Inventory + classes | open | `docs/benchmarks/goal25-inventory.tsv` | seeded from Goal 24 |
| 2 open-hillclimb drain | open | `docs/benchmarks/goal25-dispositions.tsv` | start = full cohort |
| 3 met-hillclimb keeps | open | Friend-MachineD packs under `docs/benchmarks/goal25-evidence/` | none yet |
