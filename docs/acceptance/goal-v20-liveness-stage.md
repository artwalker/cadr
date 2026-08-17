# Goal 20, 12E-1 enablement step 5 — statistical liveness stage

Implements the adjudicated N_i rule from
[goal20-liveness-assertions.md](../proposals/goal20-liveness-assertions.md)
§3–§4 and the 2026-08-16 board ruling.

This stage is **not** part of `render-diff.py gate --tier core`. A
silent implementation can still paint a legal last frame; this stage
watches inter-output gaps.

## Criterion

Booked in `docs/benchmarks/goal20-liveness-thresholds.json`.

`N_i = max(10 × baseline_worst_i, 500ms)` from the 2026-08-15
measurement (`goal20-liveness-measurement-2026-08-15.json`). Each
`(scenario, dimension)` has one threshold, taken from the baseline
side row. `capturesPerCheck` is 3. A check fails when **any** run's
worst interior gap exceeds `N_i`. Failure prints every gap, not just
the verdict.

Default `scripts/goal20-liveness-check.py` (and the `verify.sh`
stage) runs the silence-injection scenario
`liveness-ttt-agent-turn` / wide / cadr, n=3. That is the P0-4 lock.
`--all` walks the full booked table (cadr side).

## Scope (board 2026-08-17, option A)

The default path **only** locks the P0-4 silence defect (the ttt
cell). The booked 67-cell table is a **local `--all` instrument**,
not a CI obligation. Thresholds come from a same-machine baseline
measurement; CI must not judge them (playbook §3). `--all` never
enters CI.

Run `--all` locally before pushing a batch that touches
render / stream / TUI, and in every Part K module-close `verify.sh`.

`verify.sh` runs this stage from `PROJECT_DIRECTORY`, not the
isolated tar copy. Capture calls `git -C <repo>` to verify the
baseline cache; the isolated tree has no `.git` (CI-1f:
`fatal: not a git repository` in ~1s). Same cwd as the render-diff
gate. Thresholds are unchanged.

## N_i table

| scenario | dim | baseline worst ms | N_i ms |
|---|---|---:|---:|
| conversation-content | wide | 102.1 | 1021 |
| conversation-content | narrow | 102.7 | 1027 |
| conversation-mermaid | wide | 50.4 | 504 |
| conversation-mermaid | narrow | 50.2 | 502 |
| tools-success | wide | 70.1 | 701 |
| tools-success | narrow | 69.7 | 697 |
| tools-failure | wide | 81.1 | 811 |
| tools-failure | narrow | 81.2 | 812 |
| tools-significant-states | wide | 92.5 | 925 |
| tools-significant-states | narrow | 96.9 | 969 |
| tools-render-branch-sweep | wide | 311.2 | 3112 |
| tools-render-branch-sweep | narrow | 250.6 | 2506 |
| tool-bash-abort | wide | 56.7 | 567 |
| tool-bash-abort | narrow | 57.8 | 578 |
| tree-entry-state-sweep | wide | 524.0 | 5240 |
| tree-entry-state-sweep | narrow | 525.1 | 5251 |
| selector-state-sweep | wide | 132.5 | 1325 |
| selector-state-sweep | narrow | 133.7 | 1337 |
| selector-scoped-state-sweep | wide | 134.3 | 1343 |
| selector-scoped-state-sweep | narrow | 133.6 | 1336 |
| selector-trust-inherited | wide | 112.3 | 1123 |
| selector-trust-inherited | narrow | 112.1 | 1121 |
| overlays-core | wide | 281.9 | 2819 |
| overlays-core | narrow | 283.1 | 2831 |
| overlays-auth | wide | 111.1 | 1111 |
| overlays-auth | narrow | 112.4 | 1124 |
| overlays-auth-oauth | wide | 300.7 | 3007 |
| overlays-auth-oauth | narrow | 301.8 | 3018 |
| overlays-auth-device-code | wide | 301.9 | 3019 |
| overlays-auth-device-code | narrow | 302.1 | 3021 |
| overlays-auth-api-key | wide | 301.0 | 3010 |
| overlays-auth-api-key | narrow | 303.1 | 3031 |
| overlays-auth-browser-callback | wide | 301.8 | 3018 |
| overlays-auth-browser-callback | narrow | 304.2 | 3042 |
| overlays-auth-manual-code-complete | wide | 301.8 | 3018 |
| overlays-auth-manual-code-complete | narrow | 302.6 | 3026 |
| overlays-auth-browser-callback-complete | wide | 302.3 | 3023 |
| overlays-auth-browser-callback-complete | narrow | 302.5 | 3025 |
| overlays-logout | wide | 89.3 | 893 |
| overlays-logout | narrow | 89.4 | 894 |
| overlays-secondary | wide | 101.6 | 1016 |
| overlays-secondary | narrow | 100.5 | 1005 |
| stream-interrupt-queue | wide | 82.1 | 821 |
| stream-interrupt-queue | narrow | 100.9 | 1009 |
| extension-surfaces | wide | 70.7 | 707 |
| extension-surfaces | narrow | 71.3 | 713 |
| autocomplete-surfaces | wide | 101.1 | 1011 |
| autocomplete-surfaces | narrow | 100.2 | 1002 |
| provider-error | wide | 50.4 | 504 |
| provider-error | narrow | 50.4 | 504 |
| user-bash-state-sweep | wide | 189.1 | 1891 |
| user-bash-state-sweep | narrow | 193.0 | 1930 |
| settings-state-sweep | wide | 69.9 | 699 |
| settings-state-sweep | narrow | 71.0 | 710 |
| example-hello | wide | 204.1 | 2041 |
| example-hello | narrow | 203.5 | 2035 |
| example-notify | wide | 203.8 | 2038 |
| example-notify | narrow | 203.7 | 2037 |
| example-bookmark | wide | 203.5 | 2035 |
| example-bookmark | narrow | 204.8 | 2048 |
| example-send-user-message | wide | 204.0 | 2040 |
| example-send-user-message | narrow | 204.1 | 2041 |
| example-reload-runtime | wide | 203.6 | 2036 |
| example-reload-runtime | narrow | 203.1 | 2031 |
| example-todo | wide | 203.9 | 2039 |
| example-todo | narrow | 203.3 | 2033 |
| liveness-ttt-agent-turn | wide | 203.7 | 2037 |

67 booked cells. Values must match
`docs/benchmarks/goal20-liveness-thresholds.json`; the unit test
recomputes the rule from the measurement file.

## Reproduce

```sh
python3 test/goal20-liveness-check-test.py
python3 scripts/goal20-liveness-check.py
python3 scripts/goal20-liveness-check.py --all
```
