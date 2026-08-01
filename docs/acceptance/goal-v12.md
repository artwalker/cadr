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

## Part A — full fixed-baseline source audit

状态：完成审计，等待用户裁决；未进入 Part C。

固定基线 `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5` 下，命令

```sh
git -C /tmp/cadr-parity-74caa2649 ls-tree -r --name-only 74caa2649 -- packages \
  | awk '$0 !~ /\.test\.ts$/ && $0 ~ /\.ts$/' | sort
```

产生 595 个唯一文件，manifest SHA-256 为
`242d90e03ae708b9ea30d71747052af80f6d19e62eec3990a5863c62a614965d`。
每个文件的 top-level/exported surface、功能、具体 Cadr 符号/位置、三类判定与完整
baseline line span 均写入 [`docs/source-parity.md`](../source-parity.md)。账本 SHA-256
为 `4603646c6a780466af6df2900b02afc6696b1fff00463c0eed3381ec92417aac`。

| package | files | 已实现 | 有意差异 | 缺失 |
|---|---:|---:|---:|---:|
| ai | 183 | 117 | 30 | 36 |
| coding-agent | 289 | 139 | 27 | 123 |
| agent | 42 | 25 | 11 | 6 |
| tui | 37 | 23 | 1 | 13 |
| server | 13 | 13 | 0 | 0 |
| storage | 12 | 12 | 0 | 0 |
| evals | 10 | 6 | 2 | 2 |
| protocol | 9 | 8 | 1 | 0 |
| **total** | **595** | **343** | **72** | **180** |

180 个缺失项中，99 个是 shipped runnable examples，81 个是 production/helper
capabilities。建议批次按依赖排序为：TUI composition 19、Apple Terminal modifier 2、
agent/session/coding core 22、AI catalog/OAuth/transport/stream 36、eval lifecycle 2、
runnable examples 99。72 个“有意差异”逐行保留，尚未替用户批准。

机械复核：rendered paths 595、unique 595；与 manifest `diff -u` 无输出；三类计数
343/72/180；595/595 行均含精确 baseline `file:start-end` 证据。Part A 自有变更
仅为 `docs/source-parity.md` 与本报告，`src/` 零变更；用户既有的
`docs/acceptance/goal-v8-final.md` 工作区改动保持原样且未纳入。

本轴的边界如实保留：它能发现缺失的 source capability，却不能证明同名实现内部逐字
行为等价；parity-map、performance gate 与用户 A/B 仍不可替代。

## Part C1 — TUI composition（19）

状态：实现与回归已落账。实现提交 `76e85dcc4`、`86ff53909`；本章与账本证据提交
见本节所在提交。

本批把 19 个缺失 source capability 全部补为原生 Common Lisp 组合层，而未替换现有
production CLI 的手工整屏装配，因此既有 transcript、基础屏幕和 15 个 overlay 的
逐字节快照保持不变。构造选择是 CLOS 组合协议：组件/焦点生命周期用泛函数，容器用
继承共享子组件失效与焦点传播，Box/Text/Spacer/Markdown/Image/Settings/Loader 等
原语通过组合复用；没有逐行复制 TypeScript class，也没有新第三方依赖。

新增能力分两层：

- `src/cadr-tui/composition.lisp`：通用 component/focus/container/root 协议，缓存、
  invalidation、overlay、输入监听与 renderer 调度，以及 10 个可复用组件；
- `src/cadr-cli/interactive-components.lisp`：key hint、dynamic border、bordered loader、
  countdown、Armin、Daxnuts 与 Earendil announcement。动画暴露显式 tick seam，回归不
  依赖 sleep 或计时竞态。

行为边界：本批建立的是此前缺失的可复用 source surface；默认 CLI 仍走原路径，故没有
可观察行为变化，也没有用规范化或弱断言掩盖快照差异。Earendil 与基线一样在 bundled
image 不存在时保留完整文字公告。Daxnuts 使用基线精确 32×32 RGB payload；Armin 覆盖
七种动画状态。

门禁：`GOAL12-TUI-*` 八条测试覆盖组件树、缓存失效、宽度/背景、图片 id、loader
取消、settings 搜索与子菜单、两种 editor 共用协议以及 root/overlay/input；
`GOAL12-CODING-AGENT-*` 五条测试覆盖全部依赖组件和 public barrel。账本由
`coding-agent 139/27/123` 更新为 `147/27/115`，`tui 23/1/13` 更新为
`34/1/2`，全仓更新为 `362 已实现 / 72 有意差异 / 161 缺失`；余项精确为
99 examples 加 62 production/helper capabilities。

验证：确定性套件 `7823 checks / 7823 pass / 0 skip / 0 fail`；完整
`./scripts/verify.sh` 的 11 个 deterministic stage 与 2 个 live stage 全部 PASS，live
报告为 `32 checks / 31 pass / 1 skip / 0 fail`（仅缺
`ANTHROPIC_API_KEY`）。根目录 `cadr` 构建时间为
`2026-08-02 06:24:33.660346183 +0800`，晚于当时最后一个 `src/` 提交
`86ff53909` 的 `2026-08-02T06:11:50+08:00`，二进制新鲜度门禁 PASS。
