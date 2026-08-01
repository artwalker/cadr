# Goal 12 acceptance ledger

## Part A0 — Goal 11 continuous-input baseline correction

状态：完成。实现/门禁提交 `82db71b8c`；证据提交待本章落账。

A0 没有修改 `src/`。它修正的是验收标尺：旧 pi 对照只测 main-screen，新的
归档直接驱动 production `TuiAltScreen` raw input → render request → immediate
requested-frame flush。两边使用 100×40、N=5000、五个 fresh fixture、默认 GC
和完全相同的 1024-event trace。

pi continuous median/p95/p99/max 为
315.576/347.536/365.552/427.549ms；cadr 为
32.001/40.001/48.001/68.002ms。cadr 在该固定 synthetic trace 上快 6.3–9.9×；
因此绝对 32–48ms 仍可能被感知，但不是相对原版新增的退化，不授权引入原版没有的
virtual scrolling 或 transcript memoization。

门禁公式为
`max(2*pi_q, pi_q + max(5ms, 6*pi_run_MAD_q))`，覆盖 median/p95/p99；
只在同一归档主机强制，其他主机明确报告 informational。原有 50/150/500ms
absolute budgets 保留。归档 artifact、自身 SHA、source object、clean-built dist trees、
lock object、dependency tree、事件 trace、五轮原始样本与汇总重算全部入门禁。

证据：

- pi artifact: `docs/benchmarks/goal-v11-pi-baseline.json`，SHA-256
  `56e09adc50af1c9433111cc018b095c059f99bf7ada366f5d437f64d64b46ad9`；
- cadr artifact: `docs/benchmarks/goal-v12-a0-cadr.json`，SHA-256
  `8f85b41714f142f721218009bf40524e0ff842c4c6c3d76dda486595ca05d414`；
- regressions: `test_committed_fixed_baseline_artifact_passes_full_contract`、
  `GOAL11-CONTINUOUS-ALT-INPUT-BENCHMARKS-ARE-RELEASE-GATED`；
- `python3 test/goal11-performance-gate-test.py`: 5 tests / OK；
- `./scripts/test-cl.sh`: exit 0，全部确定性 suite 0 fail；
- fixed-baseline gate: PASS，same-machine relative gate enforced。

为何旧门禁没捕获：它有连续 Cadr trace，却没有同类 pi alt-screen trace；结构与事件
结果断言不能回答“相对原版多慢才算缺陷”。本次新增的是成对、同路径、原始样本可重算
的基线合同，不再用 main-screen 数字替代 mouse/wheel 标尺。
