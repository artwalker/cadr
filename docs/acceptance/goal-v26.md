# Goal 26 — fair parity then beat pi

> **Status:** met (2026-09-08). open-parity=0. 11 met-beat, 6 accepted-runtime-gap.
> Does **not** reopen Goal 20, 23, 24, or 25 as incomplete.
> Goal 25 remains terminal `met` (finite invent stop with freezes).
> Goal 23 baseline alignment to pi `v0.85.1` stands.

## Why this exists

Goal 25 closed accounting. Operators who want **cadr at least as fast as
pi on fair product paths, preferably faster**, need a goal whose stop is
**parity / beat**, not disposition freezes.

## Target

| bar | meaning |
|---|---|
| **Minimum** | Friend-MachineD ratio ≤1.0× on every **parity-cohort** metric under a **fair** product ruler |
| **Preferred** | Maximize the count of ratios below 1.0× (beat) on that same cohort |

「Fair」means both sides pay the same class of work (same transport, same
session API shape, same timed product path, no leftover-only wrappers
counted as product wins).

## Cohort

**Seed (parity cohort):** Goal 25 `frozen-unreachable` product paths (17).

| metric | known unfairness / essence |
|---|---|
| `websocket_stream.stream_roundtrip` | cadr real TCP vs pi in-process mock |
| `harness_storage.open_walk` | booked shape gap + pi jsonl API drift |
| `session_export_html.to_html` | JSON/template vs V8; HTML size delta |
| `cli_print_rpc.dialog_request` | hash-table + `json-get` vs V8 object |
| `cli_selectors.*` (7) | timed slots wrap leftover constructors |
| `cli_support.*` (6 write/threads/close) | small-path runtime / thread semantics |

**Promote into cohort when remetered:** any Goal 25 `frozen-leftover-ruler`
row whose fair remeter shows a **product** path still above 1.0×.

**Out of cohort (explicit):**

- Goal 25 `frozen-subus-floor` (80): variance / sub-µs gate already PASS
- Goal 24 `deferred-measure-only` (833): not seeded; promote only with a
  written remeter that proves a user-visible product path
- Goal 25 `met-hillclimb` (3): already ≤1.0×; keep as wins

Inventory: `docs/benchmarks/goal26-inventory.tsv`  
Live scoreboard: `docs/benchmarks/goal26-dispositions.tsv`

## Tracks

| track | job |
|---|---|
| **R** ruler | Align harness so paired remesure is fair before invent |
| **H** hillclimb | One-hypothesis invent → remesure → keep or full revert until ≤1.0×; prefer beat when cheap |

## Stop predicate

Goal 26 is `met` when **all** hold:

1. Inventory committed; every seed metric classified (`unfair-ruler` |
   `product-gap` | `runtime-essence-candidate`).
2. `open-parity` count in `goal26-dispositions.tsv` is **0**.
3. Every cohort row disposition is one of:
   - `met-beat` (ratio below 1.0×, fair product remesure)
   - `met-parity` (ratio ≤1.0×, fair product remesure)
   - `accepted-runtime-gap` (**only** via `.orchestrate/goal26/gates.md`
     human approval, with absolute µs and user-impact note)
4. No row uses Goal 25-style silent `frozen-unreachable` as success.
5. Every `met-*` cites Friend-MachineD evidence with slices unset
   (`GOAL20_PART_O_SLICE` / `GOAL20_FLOOR_SLICE`).

Stretch score (reported, not a stop): count of `met-beat` / cohort size.

## Forbidden

- Claiming leftover-wrapper speedups as `met-parity` / `met-beat`
- Dropping `RATIO_CEILINGS` in the same commit as a speedup
- Mocking cadr websocket **or** putting only one side on TCP to fake parity
- Rewriting Goal 21–25 history as failed
- Reopening Goal 20 Part G

## Commands

```bash
python3 scripts/goal26-open-gate.py
python3 scripts/goal26-open-gate.py --require-zero
```

## Evidence matrix

| part | status | evidence | notes |
|---|---|---|---|
| 1 Inventory + classes | met | `docs/benchmarks/goal26-inventory.tsv` | seeded from Goal 25 unreachable |
| 2 Fair rulers (track R) | met | per-metric remeter packs under `docs/benchmarks/goal26-evidence/` | websocket / harness / leftover remeter |
| 3 open-parity drain (track H) | met | `docs/benchmarks/goal26-dispositions.tsv` | open-parity=0; 11 met-beat, 6 accepted-runtime-gap |
| 4 Stretch beat count | reported | dispositions `met-beat` count | 11/17 |

## Claimed

- Charter open 2026-09-07. Met 2026-09-08. 11 met-beat, 6 accepted-runtime-gap (operator automate). No silent frozen-unreachable.
