# Goal 24 — post–Goal 20 leftover drain

> **Status:** met (2026-09-07). Chartered same day. Does **not** reopen Goal 20.
> Goal 20 Part G remains terminal `met`.

## Why this is not Goal 21

Goal 21 is **done**. It was pi baseline advance to **v0.84.3**
(`docs/acceptance/goal21-pi-0843-alignment.md`). Goal 22 / 23 were later
baseline bumps. Dumping invent leftovers into Goal 21 would rewrite a
closed baseline goal. Goal 24 owns the post–Goal 20 performance and
bookkeeping surface instead.

## Problem

Goal 20 closed Part G. Ledger rows still say `invent pause` /
`地板优化另刀`. Goal 20「Still not claimed」items remain intentional
non-claims. Operators still see unfinished work. That work needs a
named goal with a **finite stop predicate**, not an infinite
「every path ≤ 1.0×」wish.

## In scope

| Part | Item | Exit |
|---|---|---|
| 1 | Charter + classifier inventory | `scripts/goal24-invent-pause-classify.py` writes `docs/benchmarks/goal24-invent-pause-inventory.tsv`; counts booked below |
| 2 | Terminal disposition for every inventory metric | each row's `bucket` is one of the closed set below; no bare `invent pause` without a Goal 24 disposition |
| 3 | Drain `floor-invent` + `keep-pending-remount` | each metric either ≤1.0× on Friend-MachineD paired remesure, or reclassified with written reason |
| 4 | Resolve `needs-proposal` / `ceiling-or-variance` / `shape-gap` / `variance-floor` | written proposal, ceiling change, or booked gap — not silent ignore |
| 5 | Goal 20 still-not-claimed that are doable here | `binary_bytes` first history cell after isolated verify; Part O absolute µs margin optional |

## Out of scope (explicit)

- 148 new wall-clock pairs (G.12 forbids)
- 「Paper A/B ⇒ three games play」live P0 product work
- Reopening Goal 20 / flipping G.17 for 「beat pi further」as Goal 20
- Raising `RATIO_CEILINGS` in the same commit as a speedup without a Part 4 ruling
- Rewriting Goal 21 / 22 / 23 baseline history

## Closed bucket set

`floor-invent` · `keep-pending-remount` · `measure-only-floor` ·
`needs-proposal` · `ceiling-or-variance` · `shape-gap` ·
`variance-floor` · `other` (must shrink to zero by Part 2)

## Stop predicate

Goal 24 is `met` when **all** hold:

1. Inventory regenerated and committed; Part 1 evidence SHA present.
2. Part 2. every inventory metric has a terminal disposition in
   `docs/benchmarks/goal24-dispositions.tsv` (metric, disposition,
   evidence).
3. Part 3. `floor-invent` + `keep-pending-remount` counts are **0**
   open (drained or reclassified).
4. Part 4. `needs-proposal` / ceiling / shape / variance buckets are
   **0** open (each row closed with evidence).
5. Part 5. `binary_bytes` first history cell booked **or** deferred
   with a dated blocker in adjudications.

「All paired ratios ≤ 1.0×」is **not** the stop. Shape gaps and
OpenSSL-class paths close by disposition, not by impossible invent.

## Evidence matrix

| part | status | evidence | notes |
|---|---|---|---|
| 1 Classifier inventory | met | `scripts/goal24-invent-pause-classify.py`; `docs/benchmarks/goal24-invent-pause-inventory.tsv` @ `5bd734f2d` (963 metrics charter cut: measure-only-floor 833, variance-floor 69, floor-invent 47, ceiling-or-variance 5, shape-gap 3, needs-proposal 3, keep-pending-remount 3) | Charter snapshot; live opens live in dispositions.tsv |
| 2 Disposition coverage | met | `docs/benchmarks/goal24-dispositions.tsv` (963 rows; no open-/needs- dispositions) | Terminal set: deferred-measure-only / deferred-variance-floor / booked-shape-gap / met-remesure |
| 3 Floor invent drain | met | Friend-MachineD leftover remesures + terminal dispositions; open-floor=0 open-remount=0 | drained from charter 47+3 opens to 0 |
| 4 Proposal / ceiling / gap close | met | `docs/adjudications.md` 2026-09-07 Part 4 (six `needs-proposal` + five `needs-ceiling-ruling` closed); `docs/benchmarks/goal24-dispositions.tsv` | needs-proposal 0; needs-ceiling-ruling 0 |
| 5 binary_bytes history cell | met | `docs/benchmarks/performance-history.json` (`nativeImageBytes` 21343120 at `2026-09-07T07:56:50Z`); `docs/performance.md` `GOAL20_PERF_HISTORY`; `docs/benchmarks/goal24-evidence/p5-verify.log` | Isolated verify `--record` Goal 11 gate on Friend-MachineD (`gitHead=isolated-copy` in history cell); first cell not hand-filled |

## Claimed

- Part 1 classifier inventory (2026-09-07).
- Part 2–4 disposition drain complete (2026-09-07); open counts 0.
- Part 5 `binary_bytes` / `nativeImageBytes` first history cell (2026-09-07).

## Open drain counts (after Part 1 seed)

| disposition | n |
|---|---:|
| open-floor-invent | 0 |
| open-remount | 0 |
| needs-proposal | 0 |
| needs-ceiling-ruling | 0 |

## Scoreboard (read this first)

- **Live open counts** live only in `docs/benchmarks/goal24-dispositions.tsv`.
- `docs/benchmarks/goal24-invent-pause-inventory.tsv` is the **charter cut** at
  `5bd734f2d`. Its `floor-invent` / `needs-proposal` bucket counts stay frozen
  on purpose. Do not treat that file as the current drain scoreboard.
- Friend-MachineD remesure packs that closed drained rows live under
  `docs/benchmarks/goal24-evidence/` (not `/tmp`).
- `python3 scripts/goal24-evidence-gate.py` fails if open counts rise, evidence
  files go missing, or a disposition points at `/tmp` again.

## Attention follow-ups (2026-09-07)

Cross-review flags after the first `met` claim. Closed by durable evidence +
written rulings in `docs/adjudications.md` (same date, "Attention remediation"):

1. Part 1 evidence SHA booked (`5bd734f2d`).
2. Inventory-vs-dispositions scoreboard clarified above.
3. Charter-bulk shape-gap rows (`harness_storage.open_walk`,
   `session_export_html.to_html`, `websocket_stream.stream_roundtrip`) stay
   classifier-accepted without a Goal 24 remesure; see adjudications.
4. Drained-row evidence moved off `/tmp` into `goal24-evidence/`.
5. f4/f5 invent-skip and f4 `too_n` pollution recorded; no product knife
   replay (leftover Lisp vs V8 pattern already falsified on f1–f3).
6. `session_discovery.header_probe` keep retained under
   `deferred-variance-floor` explained in adjudications.
7. Part 5 verify log committed; `gitHead=isolated-copy` called out.

## Commands


```bash
python3 scripts/goal24-invent-pause-classify.py
python3 scripts/goal24-evidence-gate.py
```
