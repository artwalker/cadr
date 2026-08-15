# Goal 20, 12E-1 enablement step 3 — pi-side liveness re-measurement

Scope: the adjudicated step 3 of
[../proposals/goal20-liveness-assertions.md](../proposals/goal20-liveness-assertions.md):
re-measure every agent-turn scenario on the pinned pi baseline with
timing sidecars, and publish the per-scenario distribution that N_i
is adjudicated from. No gate criterion changes here.

## Method

`scripts/goal20-liveness-measure.py` captures each agent-turn scenario
(non-empty faux `responses`) in every allowed dimension, pi side, plus
the liveness manifest scenario on both sides, and aggregates the
`{stem}.timing.json` sidecars. Gaps are wall-clock intervals between
consecutive PTY reads within one capture (first byte to last byte).

- Measured: 2026-08-15T08:30:16Z, host Friend-MachineD, elapsed 323.9s
- Captures: 68; failures: 0
- pi baseline: `53fa77ccd` (cache `/tmp/cadr-render-diff-pi-53fa77ccd`)
- Raw data: `docs/benchmarks/goal20-liveness-measurement-2026-08-15.json`

## Distribution table

| scenario | dim | side | reads | median ms | p95 ms | worst ms | N_i = max(10×worst, 500ms) |
|---|---|---|---:|---:|---:|---:|---:|
| conversation-content | wide | pi | 79 | 0.5 | 37.0 | 102.1 | 1.02s |
| conversation-content | narrow | pi | 81 | 0.5 | 35.4 | 102.7 | 1.03s |
| conversation-mermaid | wide | pi | 66 | 0.5 | 21.6 | 50.4 | 0.50s |
| conversation-mermaid | narrow | pi | 64 | 0.5 | 22.2 | 50.2 | 0.50s |
| tools-success | wide | pi | 315 | 0.5 | 21.4 | 70.1 | 0.70s |
| tools-success | narrow | pi | 295 | 0.5 | 21.4 | 69.7 | 0.70s |
| tools-failure | wide | pi | 82 | 0.7 | 80.5 | 81.1 | 0.81s |
| tools-failure | narrow | pi | 87 | 0.8 | 80.1 | 81.2 | 0.81s |
| tools-significant-states | wide | pi | 218 | 0.6 | 22.2 | 92.5 | 0.93s |
| tools-significant-states | narrow | pi | 219 | 0.5 | 21.7 | 96.9 | 0.97s |
| tools-render-branch-sweep | wide | pi | 732 | 0.4 | 2.5 | 311.2 | 3.11s |
| tools-render-branch-sweep | narrow | pi | 638 | 0.4 | 5.3 | 250.6 | 2.51s |
| tool-bash-abort | wide | pi | 79 | 0.5 | 27.3 | 56.7 | 0.57s |
| tool-bash-abort | narrow | pi | 81 | 0.4 | 28.9 | 57.8 | 0.58s |
| tree-entry-state-sweep | wide | pi | 196 | 0.7 | 4.9 | 524.0 | 5.24s |
| tree-entry-state-sweep | narrow | pi | 190 | 0.7 | 4.4 | 525.1 | 5.25s |
| selector-state-sweep | wide | pi | 127 | 0.6 | 70.5 | 132.5 | 1.32s |
| selector-state-sweep | narrow | pi | 109 | 0.6 | 78.1 | 133.7 | 1.34s |
| selector-scoped-state-sweep | wide | pi | 72 | 0.6 | 50.3 | 134.3 | 1.34s |
| selector-scoped-state-sweep | narrow | pi | 66 | 0.7 | 50.2 | 133.6 | 1.34s |
| selector-trust-inherited | wide | pi | 46 | 0.5 | 49.5 | 112.3 | 1.12s |
| selector-trust-inherited | narrow | pi | 51 | 0.3 | 50.3 | 112.1 | 1.12s |
| overlays-core | wide | pi | 241 | 0.5 | 69.3 | 281.9 | 2.82s |
| overlays-core | narrow | pi | 233 | 0.5 | 68.9 | 283.1 | 2.83s |
| overlays-auth | wide | pi | 113 | 0.5 | 51.1 | 111.1 | 1.11s |
| overlays-auth | narrow | pi | 102 | 0.6 | 51.3 | 112.4 | 1.12s |
| overlays-auth-oauth | wide | pi | 124 | 0.4 | 22.9 | 300.7 | 3.01s |
| overlays-auth-oauth | narrow | pi | 115 | 0.4 | 25.4 | 301.8 | 3.02s |
| overlays-auth-device-code | wide | pi | 117 | 0.4 | 31.6 | 301.9 | 3.02s |
| overlays-auth-device-code | narrow | pi | 117 | 0.4 | 31.8 | 302.1 | 3.02s |
| overlays-auth-api-key | wide | pi | 115 | 0.4 | 32.4 | 301.0 | 3.01s |
| overlays-auth-api-key | narrow | pi | 100 | 0.6 | 48.2 | 303.1 | 3.03s |
| overlays-auth-browser-callback | wide | pi | 118 | 0.5 | 21.2 | 301.8 | 3.02s |
| overlays-auth-browser-callback | narrow | pi | 105 | 0.5 | 21.2 | 304.2 | 3.04s |
| overlays-auth-manual-code-complete | wide | pi | 89 | 0.5 | 22.1 | 301.8 | 3.02s |
| overlays-auth-manual-code-complete | narrow | pi | 106 | 0.4 | 21.4 | 302.6 | 3.03s |
| overlays-auth-browser-callback-complete | wide | pi | 85 | 0.6 | 27.3 | 302.3 | 3.02s |
| overlays-auth-browser-callback-complete | narrow | pi | 76 | 0.6 | 48.9 | 302.5 | 3.02s |
| overlays-logout | wide | pi | 45 | 0.8 | 33.3 | 89.3 | 0.89s |
| overlays-logout | narrow | pi | 44 | 0.5 | 34.0 | 89.4 | 0.89s |
| overlays-secondary | wide | pi | 157 | 0.5 | 90.0 | 101.6 | 1.02s |
| overlays-secondary | narrow | pi | 142 | 0.6 | 90.8 | 100.5 | 1.00s |
| stream-interrupt-queue | wide | pi | 268 | 77.4 | 81.0 | 82.1 | 0.82s |
| stream-interrupt-queue | narrow | pi | 256 | 79.5 | 80.9 | 100.9 | 1.01s |
| extension-surfaces | wide | pi | 46 | 0.5 | 34.4 | 70.7 | 0.71s |
| extension-surfaces | narrow | pi | 41 | 0.7 | 50.5 | 71.3 | 0.71s |
| autocomplete-surfaces | wide | pi | 44 | 0.5 | 89.2 | 101.1 | 1.01s |
| autocomplete-surfaces | narrow | pi | 40 | 0.6 | 90.3 | 100.2 | 1.00s |
| provider-error | wide | pi | 44 | 0.5 | 21.1 | 50.4 | 0.50s |
| provider-error | narrow | pi | 48 | 0.4 | 21.2 | 50.4 | 0.50s |
| user-bash-state-sweep | wide | pi | 206 | 0.3 | 16.5 | 189.1 | 1.89s |
| user-bash-state-sweep | narrow | pi | 204 | 0.3 | 16.4 | 193.0 | 1.93s |
| settings-state-sweep | wide | pi | 92 | 1.0 | 22.6 | 69.9 | 0.70s |
| settings-state-sweep | narrow | pi | 91 | 1.1 | 22.9 | 71.0 | 0.71s |
| example-hello | wide | pi | 29 | 0.6 | 50.8 | 204.1 | 2.04s |
| example-hello | narrow | pi | 28 | 0.6 | 50.0 | 203.5 | 2.04s |
| example-notify | wide | pi | 23 | 0.6 | 99.4 | 203.8 | 2.04s |
| example-notify | narrow | pi | 22 | 0.7 | 50.0 | 203.7 | 2.04s |
| example-bookmark | wide | pi | 58 | 0.5 | 50.4 | 203.5 | 2.04s |
| example-bookmark | narrow | pi | 56 | 0.6 | 50.6 | 204.8 | 2.05s |
| example-send-user-message | wide | pi | 40 | 0.4 | 101.7 | 204.0 | 2.04s |
| example-send-user-message | narrow | pi | 31 | 0.8 | 101.6 | 204.1 | 2.04s |
| example-reload-runtime | wide | pi | 27 | 0.6 | 50.1 | 203.6 | 2.04s |
| example-reload-runtime | narrow | pi | 33 | 0.5 | 50.2 | 203.1 | 2.03s |
| example-todo | wide | pi | 40 | 0.5 | 113.6 | 203.9 | 2.04s |
| example-todo | narrow | pi | 42 | 0.6 | 69.9 | 203.3 | 2.03s |
| liveness-ttt-agent-turn | wide | pi | 354 | 79.8 | 81.0 | 203.7 | 2.04s |
| liveness-ttt-agent-turn | wide | cadr | 335 | 78.8 | 83.9 | 221.0 | 2.21s |

## Observations

- Global worst pi gap: **525.1 ms** (`tree-entry-state-sweep`, both dimensions).
- The overlays-auth-* cluster sits at ~302 ms worst — a fixed ~300 ms beat in the auth flow, consistent across dimensions.
- `liveness-ttt-agent-turn` (the step-2 scenario): pi worst 203.8 ms, cadr worst 215.2 ms — both at the startup burst; turn-time ticks stay ≤88 ms.
- With the adjudicated rule `N_i = max(10 × pi_worst_i, 500 ms)`, every N_i lands in the 0.5–5.3 s band; the statistical stage (step 4) consumes the per-scenario column above, not a global constant.
