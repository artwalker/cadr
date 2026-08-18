# Goal 20 Part A — constructed 3× cold-start degeneration

Proof for `goal20-draft.md` §十四.5. Not a threshold change.
No sleep or degeneration landed in shipped `src/`.

## Setup

Isolation directory (discarded after the run):
`/tmp/grok-goal-4cbb600f2c5d/implementer/g5-isolate`.

The repo-root `./cadr` times out on this host waiting for the first
TUI frame (trust prompt from `/root/.agents/skills`). The isolate
copied the same image out of the tree so `goal11-cold-start.py`
could see `cadr v`.

```sh
mkdir -p "$ISOLATE"
cp -a /root/projects/cadr/cadr "$ISOLATE/cadr.real"
# wrapper: sleep 0.52; exec cadr.real
python3 /root/projects/cadr/scripts/goal11-cold-start.py "$ISOLATE/cadr"
```

`scripts/goal11-cold-start.py` is the first-frame helper
`scripts/goal11-bench.lisp` `cold-start-statistics` already calls.
1 warmup + 3 samples. Median fed to
`scripts/goal11-performance-gate.py` `self_history_summary` (same
function `verify.sh` uses) and to the shipped ceiling predicate
`cold_start <= 750_000` (`check_bench`).

Part A noise bands leave `cold_start.median_us` **informational**
(`docs/benchmarks/goal20-part-a-noise-bands.json`). The red that
lit is therefore the absolute 750ms ceiling, not `cold start drifted`.

## Numbers

Booked last same-machine history row
(`docs/benchmarks/performance-history.json`,
2026-08-15T19:09:32Z, Friend-MachineD): **248,317.5 µs**.

| | µs |
|---|---:|
| booked history median | 248,317.5 |
| isolate samples | 815,933.3 / 823,652.8 / 814,200.5 |
| isolate median | 815,933.3 |
| ratio vs history | 3.29× |

## Red log

Raw capture: the driver printed the following (also
`{SCRATCH}/g5-red.log` in the implementing session).

```
samples_us=[815933.33, 823652.799, 814200.464]
median_us=815933.33
booked_history_median_us=248317.515625
ratio_vs_history=3.286
self_history_summary=["self_history_gate=adjudicated-bands", "self_history_enforced=alloc", "self_history_frame5000_time=informational-quantized-4000us", "self_history_cold_ratio=3.29x", "self_history_frame5000_ratio=n/a", "self_history_frame5000_alloc_ratio=1.00x"]
failures=["cold start exceeds 750ms"]
```

`self_history_cold_ratio=3.29x` is the same helper verify prints.
`failures=["cold start exceeds 750ms"]` is the shipped ceiling.
Bands and assertions were not widened.
