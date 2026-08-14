# Goal 11 acceptance ledger

## Part A — deterministic measurement infrastructure

Status: Complete. Benchmark implementation commit `6ee7d84f3`; the production
performance path was not changed.

A one-command JSON benchmark `scripts/bench.sh` was added, with its
implementation in `scripts/goal11-bench.lisp`; the real TUI cold start is
measured by `scripts/goal11-cold-start.py`. It covers, over a fixed mixed
session, single-frame time/allocation, key-to-frame, streaming delta-to-frame,
append cost, SBCL heap, RSS and first-frame cold start; the default N ladder,
the sample count, median/MAD and the raw samples are all written into the JSON.

Mechanical verification:

```text
bash -n scripts/bench.sh
python3 -m py_compile scripts/goal11-cold-start.py
python3 scripts/goal11-cold-start.py /root/projects/cadr/cadr
  251420.906
./scripts/bench.sh --quick --samples 1 --warmups 1 \
  --output /tmp/cadr-goal11-quick.json
  exit 0; N=0/50/200, all four paths completed
./scripts/bench.sh --label before-optimization \
  --output /tmp/cadr-goal11-before.json
  exit 0; N=0/50/200/1000/5000, all four paths completed
jq . /tmp/cadr-goal11-before.json
  exit 0
```

The archived baseline is
[`docs/benchmarks/goal-v11-before.json`](../benchmarks/goal-v11-before.json);
the summary and the method are in [`docs/performance.md`](../performance.md).
Decisive results: at 5000 entries, frame 488.0ms, key→frame 480.0ms, stream
466.0ms / 2.15 delta/s, all three linear; append grows from 0.024µs at N=0 to
5.200µs at N=5000, slope 0.910, confirming cumulative O(N²); real PTY first
frame median 163.5ms, MAD 4.5ms.

Part A used no real LLM, no credentials, no random fixture, no input rewriting
and no weak assertion. The complete JSON records the HEAD and the TUI object ID;
later optimization results must be produced by the same script, on the same
machine, with the same parameters.

## Part B — fixed-baseline long-session strategy

Status: Complete. The audited object is fixed at `74caa2649f10…`.

The item-by-item conclusions and the source evidence have been written into
[`docs/performance.md`](../performance.md#fixed-ts-baseline-strategy): pi has no
viewport-before-render, no virtual scrolling and no incremental history-prefix
frame; every frame still walks the complete component tree, and on both the main
and the alt screen the diff or the viewport slice happens only after a full
render. pi's verified strategy is: stable `Markdown`/`Text`/bash previews cached
by content and width, chat children appended in O(1) with array `push`, only the
current streaming component rebuilt, 16ms render requests coalesced, and only
changed lines written.

This freezes the Part C implementation boundary: port only the per-entry
width/content cache and the O(1) tail append; add no transcript memoization, no
viewport pruning and no virtual scrolling. This is component-level memoization +
differential rendering, not a new UI architecture.

The same-host structural comparison is executed by
`scripts/goal11-pi-baseline-bench.mjs`, which loads the production dist of the
fixed worktree directly; the JSON is archived at
[`docs/benchmarks/goal-v11-pi-baseline.json`](../benchmarks/goal-v11-pi-baseline.json).
At N=5000 pi's frame/key/stream are 14.46/15.06/17.94ms respectively, all
staying linear; append is 0.0136µs and is judged constant. cadr's corresponding
pre-optimization values are 488.0/480.0/466.0ms and 5.200µs linear. The absolute
ratio is affected by the terminal-end difference between cadr's virtual terminal
and pi's mock terminal, and the report does not disguise it as a
runtime-identical cross-implementation comparison; the strategy/complexity
evidence is not subject to that limitation.

Mechanical verification:

```text
node --check scripts/goal11-pi-baseline-bench.mjs
  exit 0
node --expose-gc scripts/goal11-pi-baseline-bench.mjs \
  /tmp/cadr-parity-74caa2649 \
  > /tmp/cadr-goal11-pi-baseline.json
  exit 0; N=0/50/200/1000/5000, all four paths completed
sha256sum /tmp/cadr-goal11-pi-baseline.json \
  docs/benchmarks/goal-v11-pi-baseline.json
  f2240d4d56aba32582a33d0a055713649622e572861958808d51f8c1eb16a906 (the two agree)
```

Part B did not modify production code.

## Part C — long-session rendering and append complexity

Status: Complete. Implementation commit `56a50ca9c`.

Test-first evidence: before the implementation the new cache test failed stably
at 4 pass / 1 fail, the failure point being that a second render at the same
width/theme did not reuse the first line list; after the implementation this
Part's four regressions are 20/20. Source locations and test names:

| requirement | production source | regression test |
|---|---|---|
| stable per-entry rendered-line cache; width/theme invalidation | `src/cadr-cli/tui.lisp:3-24, 1806-1975` | `GOAL11-STABLE-ENTRY-RENDER-CACHE-MATCHES-BASELINE-INVALIDATION` |
| streaming bypass; completed tool cache; expand invalidation | `src/cadr-cli/tui.lisp:506-514, 1519-1529, 1920-1975, 2323-2333` | `GOAL11-STREAMING-AND-TOOL-MUTATIONS-INVALIDATE-ENTRY-RENDER-CACHE` |
| O(1) tail append and safe direct-SETF recovery | `src/cadr-cli/tui.lisp:21-39, 470-504, 1119, 3980` | `GOAL11-TUI-ENTRY-APPEND-MAINTAINS-O1-TAIL-INVARIANT` |
| mixed user/assistant/tool/notice transcript bytes unchanged | `src/cadr-cli/tui.lisp:1806-2000` | `GOAL11-CACHED-MIXED-TRANSCRIPT-IS-BYTE-IDENTICAL` |

Complete performance archive:
[`docs/benchmarks/goal-v11-after-part-c.json`](../benchmarks/goal-v11-after-part-c.json),
SHA-256 `4d6accbe834b5b6a8aa198b6a8aab178deae21b4c443dd480062276285b93f9a`.
At N=5000 frame/key/stream fell from 488.01/480.01/466.01ms to 4.00ms each;
frame allocation fell from 139.58MB to 0.72MB; stream throughput rose from 2.15
to 250 delta/s. append fell from 5.200µs linear to 0.020µs constant. The
detailed method, the ratios and the memory cost are in
[`docs/performance.md`](../performance.md#part-c--baseline-mechanisms-restored).

Mechanical verification:

```text
Four Goal 11 targeted regressions
  20 checks / 20 pass / 0 skip / 0 fail
./scripts/test-cl.sh
  7110 checks / 7110 pass / 0 skip / 0 fail
./build.sh
  exit 0; SBCL 2.6.7 has no sb-core-compression, degraded to an uncompressed image per the established contract
./scripts/bench.sh --label after-part-c \
  --output /tmp/cadr-goal11-after-part-c-committed.json
  exit 0; N=0/50/200/1000/5000, all four paths plus the real PTY cold start completed
sha256sum /tmp/cadr-goal11-after-part-c-committed.json \
  docs/benchmarks/goal-v11-after-part-c.json
  4d6accbe834b5b6a8aa198b6a8aab178deae21b4c443dd480062276285b93f9a (the two agree)
```

No transcript memoization, viewport pruning or virtual scrolling was added;
output semantics are unchanged.

## Part D — long-run stability and large sessions

Status: Complete. Implementation commit `ec5834ec2`.

`scripts/goal11-stability.sh` / `scripts/goal11-stability.lisp` were added; with
the production faux provider they drive 1200 turns of the real
agent/session/TUI event path and render 14,400 frames, which is equivalent to 10
hours of interaction at two turns per minute. At the five checkpoints the
FD/Lisp thread/OS thread counts are always 5/1/2; retained heap grows linearly
from 35.86MiB to 78.17MiB (exponent 0.966), and the maximum full GC is 80.0ms;
after the scenario is released the heap returns to 35.77MiB, and no leak or
residual resource was found.

For a real 10,507,435-byte / 2400-entry JSONL, load/resume/continue are
328/268/276ms respectively, the RSS peak recorded by the 1ms sampler is about
168MiB, and the retained heap after the three operations is about 73MiB. The
report does not misreport retained conversation state as a leak, and it does not
pass the sampled peak off as an exact instantaneous upper bound.

The scenario found that appends to agent messages and session entries still
traverse linearly. The fixed baseline uses array `push` for each, so the fix
uses the same private-tail mechanism; the public list, the session bytes, the
events and the TUI output are not changed. Source locations and regression
tests:

| requirement | production source | regression test |
|---|---|---|
| agent message O(1) append and whole-list replacement recovery | `src/cadr-agent/runtime.lisp:23-31`, `src/cadr-agent/tool.lisp:74-116`, `src/cadr-agent/loop.lisp:127-166` | `GOAL11-AGENT-MESSAGE-APPEND-MAINTAINS-O1-TAIL-INVARIANT` |
| session entry O(1) append and loaded-session tail restoration | `src/cadr-agent/session.lisp:34-50, 802-890, 1860-1880` | `GOAL11-SESSION-APPEND-MAINTAINS-O1-TAIL-INVARIANT` |

The test-first red evidence is the cadr-agent suite at 625 checks / 623 pass / 2
fail, both failures being that the newly added tail accessor did not yet exist;
after the implementation that suite is 635/635. On the old object, agent append
at N=20000 is 21.593µs with exponent 0.994; on the new object it is 0.110µs with
exponent -0.035. The fixed cost of the session's random ID masks the slope, but
at N=20000 it fell from 135.394µs to 109.678µs, and the cons-tail identity test
locks the complexity mechanism directly.

Complete machine-readable results:
[`docs/benchmarks/goal-v11-stability.json`](../benchmarks/goal-v11-stability.json).
For the committed performance/stability JSON the gate script outputs
`goal11 gate: PASS`.

Mechanical verification:

```text
./scripts/test-cl.sh
  exit 0; all deterministic systems green
./build.sh
  exit 0; unsupported sb-core-compression correctly falls back to uncompressed image
./scripts/goal11-stability.sh --label after-goal11 \
  --output /tmp/cadr-goal11-stability-final.json
  exit 0; 1200 turns, 10.0 simulated hours, 10,507,435-byte JSONL
python3 scripts/goal11-performance-gate.py \
  --bench /tmp/cadr-goal11-bench-final.json \
  --stability /tmp/cadr-goal11-stability-final.json
  PASS: frame/key/stream 4.00ms; heap exponent 0.966; GC max 80.0ms
```

## Part E — release gate and documentation

Status: Complete. `scripts/verify.sh` regenerates the complete benchmark and the
10-hour stability report after the isolated builds and before the process/PTY
harnesses, and decides the budget with `scripts/goal11-performance-gate.py`; any
failure blocks the later stages, and a historical archive or a weak assertion
must not take the place of this measurement. When the isolated copy has no
`.git`, the reported source revision is explicitly recorded as
`isolated-copy`, while the production object ID is still fixed by
`git hash-object`.

Test-first red evidence: before the implementation
`GOAL9-PART-D-VERIFY-ENTRYPOINT-HAS-APPROVED-STAGE-CONTRACT` was 35 checks / 29
pass / 6 fail, missing three scripts, the stage name and two output files; after
the implementation it is 35/35.

Final one-command acceptance:

```text
./scripts/verify.sh
  exit 0
  deterministic FiveAM: 7128 checks / 7128 pass / 0 skip / 0 fail
  isolated cadr build: PASS (the same 7128-check gate, repeated)
  isolated cadr-server build: PASS (the same 7128-check gate, repeated)
  Goal 11 gate: PASS
    frame/key/stream 4.00/4.00/4.00ms
    append exponent 0.029
    cold start 154.08ms
    1200-turn heap growth 40.3MiB, exponent 0.966
    full-GC max 68.0ms
    load/resume/continue 264/260/256ms
  retained process/PTY/socket/TUI harnesses: PASS
  live FiveAM: 8 items, 7 pass, 1 Anthropic credential skip, 0 fail
  DeepSeek live TUI: PASS
```

README, architecture, the test matrix and `docs/performance.md` together freeze
the two acceptance axes: functional parity and the non-functional budget, and
neither may be missing. Goal 11's mechanical gate is closed; how a real user's
everyday long session actually feels is still decided by the user's final
acceptance, and is not impersonated by a synthetic benchmark.

## Fifth A/B follow-up — continuous mouse and wheel streams

Status: Complete. Implementation commit `15bc6ae08`; performance evidence commit
`5a62cbc82`.

The old Goal 11 covered only the single frame, key→frame, stream delta and the
long-session checkpoints; the existing alt-screen regressions verified only the
results of scroll/selection, and did not quantify the event→frame latency, the
per-event allocation or the GC tail of continuous SGR mouse input. They could
therefore prove "behavior is correct", but could not catch the nearly
one-second stall on every drag/wheel over a long transcript.

The production-path gates and implementation evidence added this round:

| requirement | production / gate source | regression test |
|---|---|---|
| real SGR drag and wheel event→frame metrics at every N | `mouse-drag-statistics` / `wheel-statistics` in `scripts/goal11-bench.lisp` | `GOAL11-CONTINUOUS-ALT-INPUT-BENCHMARKS-ARE-RELEASE-GATED` |
| fixed 1024-event stream, raw samples, p95/p99/max, allocation and GC-affected wall latency | `continuous-alt-input-json` in `scripts/goal11-bench.lisp` | `GOAL11-CONTINUOUS-ALT-INPUT-BENCHMARKS-ARE-RELEASE-GATED` |
| release budgets for median/allocation/event count/p99/GC max | `scripts/goal11-performance-gate.py` | `GOAL11-CONTINUOUS-ALT-INPUT-BENCHMARKS-ARE-RELEASE-GATED` |
| scroll/selection uses baseline differential redraw instead of forced full clear | the scroll/mouse paths in `src/cadr-tui/renderer.lisp` | `GOAL11-ALT-INPUT-REUSES-BASELINE-DIFFERENTIAL-REDRAW` |
| non-allocating width scan remains byte-for-byte equivalent in terminal cell semantics | `src/cadr-tui/unicode.lisp` | `GOAL11-VISIBLE-WIDTH-FAST-PATH-MATCHES-REFERENCE-GRAPHEME-SEMANTICS` (182 fixed combinations) |
| image-line fast/slow detection preserves embedded Kitty/iTerm semantics | `src/cadr-tui/terminal-image.lisp` | `TERMINAL-IMAGE-ENCODING-SIZING-AND-DETECTION` (including a 304k prefix fixture) |

Test-first diagnosis of the old path: at N=5000 with an 8MiB nursery, the
8-event sample had median 896.041ms, p99/max 932.060ms, and median allocation
202,858,216 bytes/event; 8/8 events crossed a GC. The default 1024-event size
had still not finished after more than two minutes, so it was aborted and
explicitly marked as an incomplete diagnosis.

The optimization introduced no transcript cache, viewport pruning or virtual
scrolling that the fixed baseline does not have. It only restored differential
redraw and turned width/image/reset/copy into semantically identical scans
without intermediate strings. The final committed 1024-event run is: mouse /
wheel both 36.001ms, allocation 2,832,352 / 3,668,816 bytes; continuous median
36.001ms, p95 48.001ms, p99 52.001ms, max 68.002ms, and a max of 68.002ms over
the 447 GC-affected events; cold start 157.428ms. The report's HEAD is
`15bc6ae084d37a4b760e959bccf540ec1fe68c73`, its TUI object is
`9c6d20fc7ae5e722eacbfd2e5d9eeba4883d1600`, and its SHA-256 is
`1d2d3d1faac43006e56b08a505487035c0d8a6dffdc0b52ab069a45c0d0d8f1e`.

Mechanical verification:

```text
python3 test/goal11-performance-gate-test.py
  2 tests / OK; proves item by item that mouse, wheel, allocation, event count, p99, GC max
  and "crossed a nursery yet observed no GC" each fail on any breach
./scripts/test-cl.sh
  7706 checks / 7706 pass / 0 skip / 0 fail
python3 scripts/goal11-performance-gate.py \
  --bench /tmp/cadr-goal11-fifth-final.json \
  --stability docs/benchmarks/goal-v11-stability.json
  PASS：mouse/wheel 36.00/36.00ms；continuous p99 52.00ms；GC max 68.00ms
```

Final release-path re-measurement:

```text
./scripts/verify.sh
  exit 0
  root cadr binary freshness: PASS
  deterministic FiveAM: 7706 checks / 7706 pass / 0 skip / 0 fail
  isolated cadr build: PASS (the same 7706-check gate, repeated)
  isolated cadr-server build: PASS (the same 7706-check gate, repeated)
  Goal 11 gate: PASS
    frame/key/stream 4.00/8.00/4.00ms
    mouse/wheel 36.00/40.00ms
    continuous p99 56.00ms；GC max 84.00ms
    append exponent 0.073；cold start 163.26ms
    1200-turn heap growth 39.1MiB；exponent 0.964；GC max 52.0ms
    load/resume/continue 288/296/300ms
  retained process/PTY/socket/TUI harnesses: PASS
  live FiveAM: 8 items；7 pass；1 Anthropic credential skip；0 fail
  DeepSeek live TUI: PASS
```

The delivered binary was built at `2026-08-01 23:46:54.986162021 +0800`; the
last `src/` commit is `15bc6ae084d37a4b760e959bccf540ec1fe68c73`, at
`2026-08-01T23:44:52+08:00`. The freshness gate passed, and the version is
`cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)`.

## Goal 12 A0 correction — fixed paired alt-screen baseline

Status: Complete. Gate/benchmark commit `82db71b8c`.

The 1024-event cadr data of the previous section is valid, but the original pi
`14–18ms` figures came from the main screen, did not drive the production
`TuiAltScreen` raw mouse/wheel handler, and cannot be used to adjudicate
continuous input. A0 redid the cross-implementation comparison on the same host,
at the same 100×40, N=5000, with the same 1024-event trace, five fresh fixtures
and the default runtime GC; both sides go through production
input/request-render and flush the requested frame immediately, excluding the
16ms scheduler wait they have in common.

The archived pi baseline is median/p95/p99/max
315.576/347.536/365.552/427.549ms; cadr is
32.001/40.001/48.001/68.002ms. The single mouse/wheel points are pi
276.150/297.999ms and cadr 32.000/36.000ms respectively. All of cadr's tails are
below pi's, so the user-perceptible cost on a long transcript comes from the
full-document O(N) render that both sides have, and there is no
order-of-magnitude cadr regression that would need to be corrected with a
non-baseline mechanism.

The gate adds the complete artifact SHA, source/dist/dependency provenance,
recomputation from five rounds of raw samples, and a same-host relative
threshold; a different host is explicitly downgraded to
`informational-host-mismatch`. The tests
`GOAL11-CONTINUOUS-ALT-INPUT-BENCHMARKS-ARE-RELEASE-GATED` and
`test_committed_fixed_baseline_artifact_passes_full_contract` lock that
contract.

```text
python3 test/goal11-performance-gate-test.py
  5 tests / OK
./scripts/test-cl.sh
  PASS (all deterministic suites, 0 fail)
python3 scripts/goal11-performance-gate.py \
  --bench /tmp/goal12-a0-cadr.json \
  --stability docs/benchmarks/goal-v11-stability.json \
  --baseline docs/benchmarks/goal-v11-pi-baseline.json
  Goal 11 gate: PASS
  mouse/wheel 32.00/36.00ms
  continuous p99 52.00ms；GC max 64.00ms
  baseline relative gate enforced；mouse/wheel/p99 ratio 0.12/0.12/0.13×
```

Complete evidence: pi artifact SHA-256
`56e09adc50af1c9433111cc018b095c059f99bf7ada366f5d437f64d64b46ad9`;
cadr artifact SHA-256
`8f85b41714f142f721218009bf40524e0ff842c4c6c3d76dda486595ca05d414`.
