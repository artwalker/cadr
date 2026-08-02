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

## Part C2 — Agent/session/coding core（22）

状态：实现与回归已落账。实现提交 `2799ffc82`、`19dc334b7`；本章与账本证据提交
见本节所在提交。

本批补齐 6 个 `agent` 与 16 个 `coding-agent` source capabilities。Agent 层新增
abandoned-branch 的收集、file-operation 累积、token-budget 准备与摘要生成，完整
message projection，以及 authenticated `/api/stream` proxy reducer；`agent-navigate-tree`
现在在调用者要求时走完整 branch-summary 路径，同时保持原有前两个返回值与不摘要默认
路径不变。工具执行上下文改为 CLOS class/generic protocol，使测试、嵌入者或远端执行器可
替换 read/write/edit/bash backend，而 production 默认 backend 仍是原生文件系统与进程。

Coding-agent 层新增集中 auth guidance、`:medium` 默认 thinking 常量、具名 EventBus、
runtime timings、可恢复 watcher、JSON-with-comments scanner、路径/cloud-sync、shell/env/
detached-process、fd/rg tool manager、Windows native quarantine，以及有界 UTF-8 output
accumulator。构造选择是小型原生模块与 CLOS 泛函数，不复制 TypeScript class：需要后端
替换的位置使用多态，纯值/生命周期能力保持普通函数与 structure，避免给简单工具制造无用
对象层。

可观察行为：默认 production 路径、现有 session wire、agent event/JSON/RPC、基础屏幕、
15 个 overlay 与 payload fixtures 均未改变。新增 branch summary 只在已有显式
`summarize-p` 路径触发；EventBus 与 runtime timing 未接入固定 agent event spine；工具
backend 默认方法逐字复用原操作。因此本批是补 source surface，不靠规范化或弱断言改变
既有合同。

门禁：`GOAL12-AGENT-*` 覆盖 file operations、branch preparation/generation、tree hook
payload、bash/custom/summary message projection、proxy text/thinking/tool/usage/error reduction
与 execution-context dispatch；`GOAL12-CODING-CORE-*` 覆盖 guidance、default、EventBus、
timings、JSON/path/shell/watcher、fd/rg 与 Windows fallback、split UTF-8 accumulator、temp-file
lifecycle 及四个 built-in tools 的 backend replacement。最终确定性套件为
`7895 checks / 7895 pass / 0 skip / 0 fail`。

账本由 `coding-agent 147/27/115` 更新为 `163/27/99`，`agent 25/11/6`
更新为 `31/11/0`，全仓更新为 `384 已实现 / 72 有意差异 / 139 缺失`。剩余项精确为
99 examples、36 AI、2 eval 与 2 个用户明确暂缓的 Apple Terminal rows。

## Part C3 — AI catalog/OAuth/transport/stream（36）

状态：实现与回归已落账。实现提交 `c215dda40`、`dee7cee7c`、`cc1b37374`、
`40950bd06`、`3cbf0528f`、`fe1c58c1e`；本章与账本证据提交见本节所在提交。

本批补齐全部 36 个 AI source capabilities。Common Lisp 构造按职责分层：纯值能力
（JavaScript UTF-16 `shortHash`、JSON repair、deferred/grammar tool placement、model-data
hash/manifest）用普通函数；有独立生产者/消费者生命周期的 event stream 与 image-model
runtime 用 structure/CLOS + condition variable；provider 登录/刷新通过 runtime-provider
函数槽派发；Codex transport 用原生 HTTP proxy/CONNECT、RFC 6455 socket 与按 session 的
continuation cache。没有新第三方依赖。

关键合同包括：全部 provider-owned OAuth 流与 store/filter wiring；Anthropic/OpenAI/
Mistral 的 deferred/grammar/hash wire semantics；HTTP(S)_PROXY/NO_PROXY；image API registry；
schema v3 catalog manifest 与 37 个 shard 的 structure/per-file SHA-256；生成时间嵌入发布
image；纯 Lisp PNG fixture generator；Codex SSE/WebSocket/websocket-cached/auto、连接复用、
delta continuation、完整 debug stats、session cleanup、可选 zstd（不可用时无压缩降级），
以及独立 cached transport probe。

可观察行为变化均向基线收敛：`auto` 与 `websocket-cached` 现在共享 continuation cache；
WebSocket 首事件前失败才可 sticky fallback 到 SSE，首事件后禁止 replay；provider tool/history
IDs、deferred tools、reasoning/options 与 payload 以 fixture/精确事件断言锁定。固定 catalog
的 native generator 在 hydrated canonical shard 边界拆分：先验证审计过的 37-shard manifest，
再确定性 materialize 1153-model Lisp catalog；该边界不改变固定基线输出。

门禁：`GOAL12-*` 五个 AI 测试文件覆盖 capability/provider/auth/model-data/WebSocket
各层；`scripts/check-model-data.lisp` 与 `scripts/generate-models.lisp` 实跑通过；
`cadr-ai` 为 `2117 checks / 2117 pass / 0 skip / 0 fail`。账本由
`ai 117/30/36` 更新为 `153/30/0`，全仓更新为
`420 已实现 / 72 有意差异 / 103 缺失`；余项精确为 99 examples、2 eval 与
2 个用户明确暂缓的 Apple Terminal rows。

## Part C4 — Eval lifecycle（2）

状态：实现与回归已落账。实现提交 `797a9cbbe`；本章与账本证据提交见本节所在提交。

本批补齐 `extensions.eval.ts` 与 `vitest-evals/reporter.ts`。扩展 authoring suite
现有与基线相同的两行 harness：删去 Guidelines/文档的 baseline，以及保留完整 prompt、
仅删 CWD 尾部的 candidate；固定 create/reload/use 输入后，原生 judge 同时检查生成源码、
规范 `cadr-agent` 扩展 API、loader errors、已注册 `hello`、成功的
`hello({name: "Bob"}) -> Hello, Bob!` tool result 与逐字最终响应。Lisp loader 自动把每个
扩展放入 `(:use :cl :cadr-agent)` 的隔离 package，因此规范 API 判据是源码使用
`define-tool`/`cadr-agent:define-tool`，而不是照搬 TypeScript import；这是实现语言带来的必然
映射，未降低功能合同。生成的 `hello.lisp` 作为 UTF-8 Common Lisp source artifact 留存。

Reporter 采用 Common Lisp structure 表达 runner case 与生命周期状态，不复制 Vitest class。
每个 harness case 追加 schema-v1 `runs.jsonl`，artifact root 固定 `0700`、JSONL 与 session/
source 文件固定 `0600`；metadata 排除 run ID 与内嵌 session snapshot，保留 iteration 和其他
自定义元数据。结束阶段从 iteration artifact、score、usage、timings、errors 与 test status
构造 observation，调用既有 summary；中断时逐字输出
`Eval comparisons unavailable: test run interrupted.`。`eval-main --suite extension-authoring`
把两行 suite 接入该生命周期，原有 `smoke`/`extensions` 入口保持不变。

测试先红后绿：新增 reporter 文件尚不存在时 ASDF 明确失败；实现后
`cadr-evals` 为 `150 checks / 150 pass / 0 skip / 0 fail`。门禁为
`EXTENSION-AUTHORING-PROMPT-VARIANTS-MATCH-BASELINE-BOUNDARIES`、
`EXTENSION-AUTHORING-HARNESS-TABLE-REGISTERS-BASELINE-AND-CANDIDATE`、
`EXTENSION-AUTHORING-JUDGE-REQUIRES-SOURCE-API-LOADER-TOOL-AND-RESPONSE`、
`EXTENSION-AUTHORING-HARNESS-CAPTURES-SOURCE-ERRORS-TOOLS-AND-ARTIFACT`、
`EXTENSION-AUTHORING-SUITE-RUNS-BOTH-ROWS-THROUGH-REPORTER-LIFECYCLE`、
`EVAL-HARNESS-REPORTER-APPENDS-PERMISSIONED-RECORDS-AND-SUMMARIZES` 与
`EVAL-HARNESS-REPORTER-INTERRUPTED-NOTICE-IS-EXACT`。

账本由 `evals 6/2/2` 更新为 `8/2/0`，全仓更新为
`422 已实现 / 72 有意差异 / 101 缺失`。剩余项精确为 99 examples 与两个用户明确
暂缓的 Apple Terminal rows；本批没有新依赖，也没有改变既有可观察行为。

## Part C5 — Apple Terminal modifier（2，完成）

状态：用户撤销原“目标平台不适用”暂缓裁决后完成实施。该调整是
产品优先级的纠正，不是把平台能力改判为有意差异。

- `src/cadr-tui/native-modifiers.lisp:3-78` 实现基线四个 CoreGraphics mask、
  Darwin/arm64/x64 门控、`CGEventSourceFlagsState` FFI 与 fail-closed 查询。
- `src/cadr-tui/terminal.lisp:159-178,275-307,518-565` 实现 Apple Terminal
  session 判定，并仅在 Apple Terminal Return 路径查询 Shift，命中时输出
  `ESC[13;2u`。非 Apple Terminal、非 Return 和未按 Shift 时原字节不变。
- 没有新增 ASDF 闭包依赖、第三方库、外部二进制或发行产物内容；
  仅调用 macOS 自带 CoreGraphics，因此不触发新依赖授权流程。
- 验证等级为“实现完成，平台不可实测”。本机无 macOS/Apple Terminal，
  `APPLE-TERMINAL-NATIVE-MODIFIER-FIXTURES-MATCH-COREGRAPHICS-MASKS`、
  `APPLE-TERMINAL-NATIVE-MODIFIER-QUERY-IS-FAIL-CLOSED`、
  `APPLE-TERMINAL-SESSION-DETECTION-MATCHES-BASELINE` 与
  `PROCESS-TERMINAL-QUERIES-SHIFT-ONLY-FOR-APPLE-TERMINAL-RETURN` 只能证明
  fixture 对拍与集成分支，未宣称 live 验证。

目标回归为 `595 = 523 已实现 + 72 有意差异 + 0 暂缓/缺失`，
首次达成零暂缓状态。

机械验收：

- 四条 Apple Terminal 回归共 `30 checks / 30 pass / 0 skip / 0 fail`；
  `cadr-tui` 为 `1580/1580/0/0`。
- `./scripts/test-cl.sh` 为
  `systems=8 / 10269 checks / 10269 pass / 0 skip / 0 fail`。
- `./scripts/verify.sh` 全部 12 个确定性阶段 PASS，包括 source drift、
  两个隔离构建、Goal 11 gate、六类进程/PTY/TUI harness；凭据门控
  live 为 `8 items / 7 run / 7 pass / 1 skip / 0 fail`，Anthropic 因缺 key
  跳过，DeepSeek live TUI PASS。
- 根目录二进制构建时间为
  `2026-08-02 17:49:38.252818046 +0800`，新于最后一次 `src/` 提交
  `0c52709ab09c5d27431301307b11b4342bdf19a5`
  (`2026-08-02T17:47:20+08:00`)；`./cadr --version` 输出
  `cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)`。
- 本批 `src/cadr-ai` 零 diff；原有整屏、overlay、payload、wire 与非
  Apple Terminal 键位门禁全绿。

## Part C6 — Runnable examples（99，阶段性 blocked）

状态：17 个现有冻结 API 内可完成的示例已移植；其余 82 个已逐文件、逐能力入
blocked 提案，等待用户逐项裁决。实现/测试提交 `10d5fb29f`；文档收尾见本节
所在提交。

本批先用 `examples/manifest.sexp` 对固定基线的 99 个 example source 建立一对一
inventory。每行只能是 `:ported` 或 `:gap`：ported 必须指向真实 Lisp source；gap
必须列出非空 gap ids。机械结果为 99 total / 99 unique / 17 ported / 82 gap；42 个
唯一 gap id 全部恰好映射到
[`docs/proposals/goal-v12-example-api-gaps.md`](../proposals/goal-v12-example-api-gaps.md)
的 19 个可独立裁决项。

17 个功能等价移植为：bookmark、claude-rules、doom keys、WAD finder、dynamic
resources、两种 input transform、model status、terminal notify、pirate mode、plan-mode
utilities、provider payload logging、send-user-message、session-name 与 subagent agent
discovery，以及 mac-system-theme 与 titlebar-spinner。构造继续使用 Lisp 的长处：扩展入口直接用冻结 macros/hooks，纯算法 helper
保持普通函数/structure，session/model domain object 直接复用；没有为示例复制 TypeScript
class，也没有增加第三方依赖。WAD 下载严格使用基线的未压缩 shareware WAD URL 与
原始 octet 写入口径；macOS theme 与 titlebar timer 用 SBCL 原生线程表达，不虚构 API 缺口。

本批拒绝了一批“能 load 但不等价”的假阳性。典型例子是当前 `custom` 只把 factory
当 `(done)` 调用、忽略 overlay options，并把返回值退化为 line rendering；它不能替代
基线 `(tui, theme, keybindings, done) -> Component` 的焦点、动画、dispose 与 overlay
handle 合同。同理，`mode` 推导不替代公开 `hasUI`，内部 agent slot 不替代 model/runtime
context，已有简化 renderer 不替代完整 Theme/ToolRenderContext。所有这些行保持 `缺失`，
没有用内部符号、弱断言或降级示例冲高数字。

提案的 19 项逐项包含确切需求、固定 baseline file:line、受影响示例、非示例影响、
最小解冻面、替代方案及否决理由、冻结影响与回滚。第 11–14 项涉及扩展本地依赖、
Gondolin、sandbox runtime 与 WASM；提案明确不把能力批准偷换为依赖批准，具体依赖
闭包、版本/hash 与构建隔离仍须另行预审。

测试先红后绿：manifest 尚不存在时
`GOAL12-EXAMPLE-MANIFEST-COVERS-EVERY-BASELINE-SOURCE-EXACTLY-ONCE` 以
`FILE-DOES-NOT-EXIST .../examples/manifest.sexp` 失败。完成后门禁包括：

- `GOAL12-EXAMPLE-MANIFEST-COVERS-EVERY-BASELINE-SOURCE-EXACTLY-ONCE`；
- `GOAL12-EVERY-EXAMPLE-GAP-IS-DEFINED-BY-THE-BLOCKED-PROPOSAL`；
- `GOAL12-PORTED-EXTENSION-ENTRYPOINTS-LOAD-WITHOUT-DIAGNOSTICS`；
- `GOAL12-PORTED-EXTENSION-REGISTRATIONS-COVER-THE-BASELINE-SURFACE`；
- `GOAL12-PURE-EXAMPLE-PORTS-PRESERVE-EDGE-CASE-BEHAVIOR`。

五条定向门禁合计 `503 checks / 503 pass / 0 skip / 0 fail`。完整
`./scripts/test-cl.sh` 为 `8590 checks / 8590 pass / 0 skip / 0 fail`。
`./scripts/verify.sh` 的 11 个确定性阶段全部 PASS，包括隔离 `cadr`/`cadr-server`
无压缩降级构建、Goal 11 性能稳定性门禁、进程/PTY/socket/TUI harness；两个 live
阶段亦 PASS。凭据门控项中 7 项实际运行并通过，Anthropic 一项因
`ANTHROPIC_API_KEY is not set` 跳过，DeepSeek live TUI 通过。

交付前根目录二进制已重建。`scripts/check-root-binary.sh` 记录 binary build time
`2026-08-02 10:18:34.175969809 +0800`，晚于最后一个 `src/` 提交
`797a9cbbe7055be59fc1f1ac1f5e6361b8f9f2e0` 的
`2026-08-02T08:46:22+08:00`；`./cadr --version` 为
`cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)`。

账本由 `422 已实现 / 72 有意差异 / 101 缺失` 更新为
`439 已实现 / 72 有意差异 / 84 缺失`。余项精确为 82 个提案 blocked examples 与
2 个用户明确暂缓的 Apple Terminal rows。此时暂停是新增能力裁决边界，不是把 82
个示例宣告完成；获批项实施后才可继续逐行改判。

### Part C6 intermediate checkpoint — approved API implementation and 94 ports

The user subsequently approved all 19 itemized capabilities plus the necessary
A–E core seams. Commits `5688d1c8a`, `595ba3b67`, and `5c0cc220b` close the
approved runtime/TUI/OAuth/key-release surfaces and raise the mechanical example
ledger to **99 total / 94 ported / 5 gap**. The remaining rows are exactly
`custom-compaction.ts`, `prompt-customizer.ts`, custom Anthropic `index.ts`, and
GitLab Duo `index.ts` plus its `test.ts`.

Real entrypoint auditing found that those five files still require three
production call-chain seams outside the approved file surface: compaction must
actually dispatch the already-declared lifecycle event, the real structured
system-prompt options must reach `before-agent-start`, and provider extensions
need a session-local buffered HTTP control-plane callback. These are recorded
with fixed-baseline file:line evidence and minimal thaw surfaces in
[`goal-v12-api-scope-amendment-3.md`](../proposals/goal-v12-api-scope-amendment-3.md),
commit `639035ce9`. No approximation, private `cadr-ai` call, global registry
mutation, or shell-to-curl workaround is counted.

The manifest now drives the source ledger directly, and
`GOAL12-SOURCE-PARITY-VERDICTS-FOLLOW-THE-CURRENT-EXAMPLE-MANIFEST` prevents a
future implementation/ledger split. The intermediate totals at proposal commit
`639035ce9` were **516 implemented /
72 intentional differences / 7 missing**: five proposal-blocked examples and
the two user-deferred Apple Terminal rows. `src/cadr-ai` remains unchanged.
The approved additive exports change the re-frozen extension export SHA-256 to
`61eb1b623f784b3a8f0f6fe6791c65ebe991ff314ed1d969b82f3edd57646f18`;
the 34-event set remains
`12f79b21e0e25495cb023baaf21b26f6cf9a891881b26602f6553f80af54887a`.

### Part C6 final — F/G/H and all 99 runnable examples

状态：实现与回归完成，提交见本节所在提交。

用户批准的 F/G/H 是基线能力补齐，不是 Cadr 新机制：

- F 把已声明但未接通的 `:session-before-compact` 与
  `:session-compact` 接到 manual、threshold、overflow 三条真实 compaction
  路径。before payload 含 preparation、branch entries、instructions、reason、
  retry 标记和 cancellation signal；合法 extension compaction 原样持久化，
  cancel/abort 停止，非法结果或 handler error 回退原 summarizer。
- G 将 CLI 与 SDK 真实组装出的八字段 system-prompt options 保存为 agent
  状态并以 defensive copy 交给每个 `:before-agent-start` handler；reload 后
  prompt 文本和 options 同步替换，CLI/SDK 生成结果逐值一致。
- H 在 extension host 上增加 session-local buffered HTTP callback；公开 API
  只接受 HTTP(S)、受限 method、string headers、string/octet body、非负 timeout
  与 cancellation signal，并复制输入输出。CLI adapter 复用现有 native HTTP
  transport，保留 status/headers/octet body，归一化 timeout/abort/transport
  condition，且从不暴露 token、refresh secret 或底层错误。

由此完成 `custom-compaction.lisp`、`prompt-customizer.lisp`、custom Anthropic
provider 以及 GitLab Duo provider/test 的功能等价移植。manifest 机械结果为
**99 total / 99 unique / 99 ported / 0 gap**；source ledger 为
**595 total / 523 implemented / 72 intentional differences / 0 missing**，已达成
零暂缓、零缺失。四本账共享同一 `GOAL12_LEDGER` 身份，
确定性门禁从 manifest 实际解析并逐字核对 counts、baseline 与交叉链接。

34 个 extension event 的 production dispatch 审计见
[`goal-v12-extension-event-dispatch.md`](goal-v12-extension-event-dispatch.md)。
每一行都给出 event、真实 dispatch `file:line` 与安装 handler、驱动 production
路径并显式断言 called 的测试。唯一发现的断路是
`:session-before-compact`：Goal 7 只测试了返回值校验/合并，没有驱动 compaction
入口，因此“接收端存在”被误当成“事件已实现”。本批连接发射端后，manual、
threshold、overflow、cancel、abort、invalid/error fallback 和 after payload
均由生产路径回归覆盖。

extension export text 重新冻结为
`61eb1b623f784b3a8f0f6fe6791c65ebe991ff314ed1d969b82f3edd57646f18`；
34-event source block 仍为
`12f79b21e0e25495cb023baaf21b26f6cf9a891881b26602f6553f80af54887a`。
`src/cadr-ai` 在 F/G/H 全批保持零 diff；无 extension compaction、prompt options
consumer 或 HTTP consumer 时，原 result/event/session/JSON/RPC/overlay/payload
合同保持逐字不变。

`scripts/test-cl.sh` 不再依赖人工相加：它保存完整 FiveAM 输出，要求恰好八组
`Did/Pass/Skip/Fail`，验证 `checks = pass + skip + fail`，缺一套、重复 summary
或任一 failure 均 fail closed。本批完整确定性结果为
`systems=8 / 10233 checks / 10233 pass / 0 skip / 0 fail`。

## Part D — fixed-baseline source drift gate

状态：完成，提交见本节所在提交。

`scripts/check-source-parity-drift.sh` 比较两个 baseline commit，在与 Part A
相同的 `packages/**/*.ts`、排除 `*.test.ts` 口径下列出新增、删除和 rename。
每一项必须在四列 TSV 中有非空人工 decision；missing、stale、malformed row、
未知 revision 或缺失 disposition file 均失败。它不把 modified file 偷换为已审计：
内容变化仍走既有 source/behavior 复审。

`scripts/test-source-parity-drift.sh` 用临时 Git repository 确定性证明 A/D/R、
test exclusion、未处置失败与完整处置通过；`scripts/verify.sh` 在构建前运行该
self-test。升级操作手册见 [`docs/source-parity-upgrade.md`](../source-parity-upgrade.md)。
README 与 architecture 明确三本账分工：parity-map 管可观察行为，source-parity
管逐源文件处置，performance 管非功能预算；manifest 是 99 个 runnable example
的机器清单。共享身份门禁使任何一本账落后都直接变红。

## Final mechanical verification

实现、漂移门禁与账本分别落账为 `07c00a1d1`、`9bd12e6f1`、
`c1d7f5d5c`。完成审计又发现 `parity-map` 的实施顺序表仍保留阶段性的
`94 complete / 5 blocked`，证明只校验共享 marker 仍不足；提交 `07996b6aa`
修正正文并新增 current-summary/obsolete-summary 双向断言。该断言先以 3 项失败复现
漂移，修正后定向结果为 `311/311`。提交后执行 `./scripts/test-cl.sh`，脚本从完整输出解析到恰好八个
suite：`cadr-ai 2117`、`cadr-agent 911`、`cadr-tui 1550`、
`cadr-cli 4943`、`cadr-storage 23`、`cadr-server 45`、`cadr-evals 150`、
`cadr-protocol 497`；汇总为
`systems=8 / 10236 checks / 10236 pass / 0 skip / 0 fail`。

根目录 `./build.sh` exit 0；SBCL 不含 `sb-core-compression` 时按架构合同降级为
无压缩 image。`./scripts/verify.sh` exit 0，十二个确定性阶段全部 PASS：二进制
新鲜度、source drift self-test、FiveAM、隔离 `cadr`/`cadr-server` 构建、Goal 11
性能稳定性、native acceptance/process modes、migration PTY、Unix socket、terminal
lifecycle 与 deterministic TUI harness。隔离构建中的两次全量测试也各自精确为
`8 / 10236 / 10236 / 0 / 0`。Goal 11 为 PASS（1200-turn long run、至少
10 MiB JSONL session，continuous p99 52ms、continuous GC max 92ms）。

live 报告为 `8 items / 7 run / 7 pass / 1 skip / 0 fail`，检查级为
`32 / 31 pass / 1 skip / 0 fail`；唯一跳过项是
`LIVE-ANTHROPIC-STREAM-PRESERVES-TWO-TURN-CONTEXT`，原因为
`ANTHROPIC_API_KEY is not set`。DeepSeek 与 OpenAI Codex OAuth 的七项 live、
以及 DeepSeek live TUI 均实际运行并通过。

最终根目录二进制构建时间为
`2026-08-02 17:13:08.606765195 +0800`，晚于最后一次 `src/` 提交
`07c00a1d1a0c070b9e237a2dd40c126334a2fcd4` 的
`2026-08-02T16:49:59+08:00`；`./cadr --version` 为
`cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)`，新鲜度门禁 PASS。

## Part D revalidation correction and screen-oracle audit

状态：补正完成。真实账本门禁提交 `bd2276ad5`；整屏独立 oracle 提交
`f91cc2178`；本章证据见本节所在提交。

此前 `check-source-parity-drift.sh` 把所有 disposition 输入都按四列 TSV 扫描，既不
认识 `docs/source-parity.md` 的六列 package tables，也不知道表格边界。因此用户按
usage 以真实账本执行时，合法的 `packages/protocol/vitest.config.ts` 行和表外散文都
被报成 invalid disposition row。旧 `verify.sh` 只运行临时 Git repository 加合成 TSV
的 A/D/R self-test，确实是“测替身不测产品”。

补正后的 Markdown parser 只在精确的六列表头和 separator 后进入 package table，
只接受反引号包裹的 `packages/**/*.ts` 非测试路径与三种合法 verdict，离开表格即停止；
正文、说明段落和 Summary table 均不参与 row parsing。真实账本门禁同时要求：

- Summary 恰有一个 Total，且解析行数等于该值，当前为 **595**；
- 595 个路径唯一；
- 排序后的路径 SHA-256 等于账本记录的
  `242d90e03ae708b9ea30d71747052af80f6d19e62eec3990a5863c62a614965d`；
- 普通 `--repo/--from/--to` 模式再把账本路径集合与 `--from` tree 逐项比较；
  浅克隆的 `verify.sh` 使用显式 `--ledger-only`，不伪装具备 detached baseline object。

用户给出的真实命令现 exit 0，输出为 `Source parity ledger entries: 595`、上述 path
SHA、`No added, deleted, or renamed baseline source files.` 与
`Source parity dispositions complete: 0`。合成回归另锁定表外散文忽略、坏 separator、
坏 verdict、重复 path、路径 SHA 漂移和 Summary total 漂移；后五种均以 exit 2
fail closed。`verify.sh` 新增独立的 `real source parity ledger` 阶段，确定性阶段由
12 增至 13。

为何旧 10286 条检查与 12 个阶段没有捕获：FiveAM 没有执行 shell parser，更没有把
真实 Markdown 账本交给它；唯一相关的 shell stage 使用临时 repository 和四列 TSV，
完全绕开了出错的输入类型。数量再大也没用，入口错了就是零覆盖。

整屏 SHA 审计覆盖仓库内全部视觉 hash：13 个 base-screen 与 15 个 overlay。完整
逐项清单、固定基线 `file:line`、独立断言和补齐状态见
[`docs/visual-parity.md`](../visual-parity.md) 的
“B2 SHA snapshot 独立语义 oracle 审计”表。审计结果为：

- base-screen 既有 8/13 具备直接语义断言；thinking、tool collapsed、tool expanded、
  overflow scrolled-to-top、narrow width 五项本轮补齐；
- overlay 既有 14/15 有 case-specific line contract；extension-custom 本轮补齐；
- 两个总门禁把 SHA case name 与 oracle case name 做双向集合相等检查，随后逐 case
  执行首行、自然高度、顺序、间距、viewport、preview 和完整文案合同。今后只更新
  hash 或只新增 case 都会失败，oracle 的期望不得从当前 Cadr render 反推。

既有 13+15 个 SHA 值均未修改；补的是证明它们“对”，不是重新生成一批仍可能保护
错误实现的 hash。新增两条总门禁贡献 266 个独立 checks；完整确定性结果为
`systems=8 / 10552 checks / 10552 pass / 0 skip / 0 fail`。

`./scripts/verify.sh` exit 0，13 个确定性阶段与 2 个 live 阶段全部 PASS；两个隔离
构建各自再次得到 `8 / 10552 / 10552 / 0 / 0`。Goal 11 gate PASS；live 为
`8 items / 7 run / 7 pass / 1 skip / 0 fail`、检查级
`32 / 31 pass / 1 skip / 0 fail`，唯一跳过仍是缺少 `ANTHROPIC_API_KEY`，DeepSeek
live TUI PASS。

交付前根目录二进制已重建。`scripts/check-root-binary.sh` 记录 binary build time
`2026-08-02 19:14:02.763812157 +0800`，晚于最后一次 `src/` 提交
`ceb30956ca526aa9ce505da3bb6282d37f231c1d`
(`2026-08-02T18:13:41+08:00`)；`./cadr --version` 为
`cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)`，新鲜度门禁 PASS。
