# Proposal: Goal 20 Part A — self-history drift thresholds

Status: **awaiting user adjudication**. Not in force. Existing absolute
ceilings in `scripts/goal11-performance-gate.py` stay unchanged.

## Why

The gate today only has disaster ceilings (e.g. frame 50ms, cold start
750ms). A 10× regression that stays under the ceiling is invisible.
Goal 20 Part A adds cadr-vs-its-last-passing-run checks.

## Proposed store

`docs/benchmarks/performance-history.json`, written only by
`scripts/record-performance-history.py` from a real `bench.sh` JSON.
`docs/performance.md` should include a generated table (later; Part B)
derived from that file.

## Proposed fail-closed metrics (need numbers)

| metric | source field | compare to | proposed cap | notes |
|---|---|---|---|---|
| cold start | `cold_start.median_us` | previous same-machine entry | +20% | informational if `same_machine` is false |
| N=5000 frame | `metrics.frame_render.5000.median_us` | previous same-machine | +20% | keep 50ms ceiling |
| N=5000 frame alloc | `metrics.frame_render.5000.median_bytes` | previous same-machine | +25% | keep 16MiB ceiling |

Paired pi ratios (`baseline_mouse_ratio` / `baseline_wheel_ratio` /
`paired_continuous`) stay as they are. Expanding those pairs is Part H.

## What is not proposed

- Loosening any existing ceiling.
- Enabling these numbers in the same commit as this proposal.
- Using `./cadr --help` as cold start.

Adjudicate: accept / change the percents / pick a different store.

## Denominator (Goal 20 Part M)

This proposal is **not a gate**. When the thresholds are later enabled they
must declare:

- **Checks:** cadr-vs-previous-same-machine drift on the three metrics above,
  plus the existing absolute ceilings (unchanged).
- **Does not check:** pi pairing outside the three existing ratios (Part H);
  quality of the screen; Lisp-ification; visible-string reachability.
- **A pass means:** no ceiling breach and no self-history drift beyond the
  adjudicated percents on a same-machine run. It does **not** mean
  "performance is good" or "not worse than pi" for any other path.

Who covers the rest: Part H (pi pairs), `goal11-performance-gate.py`
ceilings (catastrophe), `sb-sprof` (diagnosis only, not a gate).
