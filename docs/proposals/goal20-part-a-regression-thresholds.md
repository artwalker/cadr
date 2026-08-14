# Proposal: Goal 20 Part A — self-history drift thresholds

Status: **adjudicated 2026-08-14** (advisor ruling recorded in the goal 20
state board; user retains veto). The proposed fixed percents were
**rejected** in favor of the `max(floor, 6 * MAD)` band shape already used
by `scripts/goal20-paired-paths.py`:

- `frame_render.5000.median_bytes`: fail-closed, floor 4096 bytes (one
  page; the metric is deterministic, historical variance 0, so +25% would
  never trigger).
- `cold_start.median_us`: floor 10ms with MAD measured at n >= 20; demoted
  to informational by the measurement script itself if 6 * MAD exceeds 20%
  of the median.
- `frame_render.5000.median_us`: informational — the reading is quantized
  at the 4000us timer step (observed sample set {0.0, 4000.0, 4001.0});
  no percent or band can detect anything until the measurement gains
  resolution.

The measured bands live in `docs/benchmarks/goal20-part-a-noise-bands.json`
(written only by `scripts/goal20-part-a-noise-bands.py`) and are enforced
by `scripts/goal11-performance-gate.py` against the previous same-machine
row of `docs/benchmarks/performance-history.json`. Existing absolute
ceilings stay unchanged.

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

In force since the 2026-08-14 adjudication:

- **Checks:** cadr-vs-previous-same-machine drift on `cold_start.median_us`
  and `frame_render.5000.median_bytes` (band `max(floor, 6 * MAD)` from the
  bands file), plus the existing absolute ceilings (unchanged).
- **Does not check:** `frame_render.5000.median_us` (informational: the
  reading is quantized at the 4000us timer step and no band can detect
  anything until the measurement gains resolution); pi pairing outside the
  three existing ratios (Part H); quality of the screen; Lisp-ification;
  visible-string reachability. Cross-machine runs and runs with no prior
  same-machine history row are informational (same_machine rule).
- **A pass means:** no ceiling breach and no self-history drift beyond the
  adjudicated bands on a same-machine run. It does **not** mean
  "performance is good" or "not worse than pi" for any other path.

Who covers the rest: Part H (pi pairs), `goal11-performance-gate.py`
ceilings (catastrophe), `sb-sprof` (diagnosis only, not a gate).
