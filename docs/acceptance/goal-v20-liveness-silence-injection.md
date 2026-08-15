# Goal 20, 12E-1 enablement step 2 — silence injection and the red/green proof

Scope: the adjudicated step 2 of
[../proposals/goal20-liveness-assertions.md](../proposals/goal20-liveness-assertions.md)
— one scenario that injects turn-time silence, demonstrated **red before
the motivating fix and green after it**. This file is the evidence record.
It changes no gate criterion; the scenario lives in its own manifest and
is not part of the render-diff gate matrix.

## The scenario

`test/fixtures/render-diff/liveness-scenarios.json` →
`liveness-ttt-agent-turn`: open `/tic-tac-toe`, play X, and the
extension's `send-message :trigger-turn-p t` starts an agent turn whose
faux text streams at 0.5 tokens/second — a multi-second turn.

Why this shape: P0-4's mechanism (`d72b260d4`) was the extension
trigger-turn running the agent loop **on the TUI input thread**, so
`flush-render` never ran during the turn. A slow trigger-turn is exactly
that defect's silhouette. Two cheaper shapes were probed first and
rejected as non-representative — both are healthy on both products:

| Probe shape | pi worst gap | cadr worst gap |
|---|---:|---:|
| slow first token (0.5 tok/s), no tool | 82.4 ms | 88.3 ms |
| 3 s `sleep` inside a bash tool call | 81.8 ms | 103.3 ms |

(Both sides tick a `Working...` spinner every ~80–90 ms through both
waits. First-token slowness and tool-execution slowness are not the P0-4
shape.)

## The proof

Same scenario, same harness, two cadr builds, wide dimension:

| Build | PTY reads | worst gap | shape |
|---|---:|---:|---|
| pre-fix `520a0f715` (= `d72b260d4^`) | 22 | **26,009 ms** | zero output from t=0.57s until the entire turn dumps at t=26.6s |
| current (post-`d72b260d4`) | 336 | **215 ms** (startup burst; ≤88 ms through the turn) | spinner ticks every ~80–90 ms, response streams progressively |

Pre-fix the final screen is correct and the middle is missing — the
exact P0-4 signature ("最终画面是对的，中间什么都没有"). Against the
proposed N ≈ 1 s the pre-fix capture is **red** by 26×, the current
capture **green**. The gate this stage feeds can catch the defect that
motivated it.

Replay (this tree):

```sh
python3 -u scripts/render-diff.py capture \
  --manifest test/fixtures/render-diff/liveness-scenarios.json \
  --scenario liveness-ttt-agent-turn --dimension wide --side cadr \
  --allow-partial-coverage --output /tmp/liveness-replay
```

Pre-fix replay: `git worktree add /tmp/cadr-prefix 520a0f715`, backport
the timing patch (`git -C /tmp/cadr-prefix checkout f234344f7 -- \
scripts/render-diff.py`), run the same command from the worktree with
`--output` elsewhere.

## Findings recorded along the way

1. **Driver observability gap**: `waitForAgentSettled` never fires for a
   trigger-turn on cadr — the driver's settle signal is
   `:work-rendered-function` (`test/fixtures/render-diff/cadr-driver.lisp:1644`),
   which the background-thread turn path does not invoke. The scenario
   therefore waits on visible text instead. If the settled side-channel
   is ever extended to background turns, revisit.
2. cadr's `slow-faux-stream` supports text blocks only
   (`cadr-driver.lisp` errors on toolCall blocks under `stream`), so
   silence through a *tool call* cannot be paced this way yet; the
   trigger-turn text shape covers the defect class regardless.
3. `load_manifest` gained `enforce_coverage_floor` (CLI
   `--allow-partial-coverage` on `capture`): the coverage floor and the
   interface-registry check both assume the full render-gate manifest and
   reject a single-scenario liveness manifest. The render gate's own
   manifest keeps the strict path.

## Boundaries

- N_i per scenario is derived from the full re-measurement (step 3) and
  adjudicated there; this scenario's measured cadence (≤88 ms turn-time
  ticks on both sides) is the defended rhythm.
- The statistical liveness stage is step 4; nothing here wires into
  `verify.sh` or `gate --tier core`.
- `.raw` artifacts remain untouched by timing; sidecars are additive
  (step 1, `f234344f7`).
