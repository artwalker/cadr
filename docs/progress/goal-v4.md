# GOAL v4: 全量对齐审计（parity map）

## 〇、前置条件与定位

- goal 3 已通过机械验收；本 goal 可与 TUI 人工验收收尾并行。
- **北极星已由用户确认（2026-07-30）：cadr 以审计提交 `71efc6f0c1909874ec8c944637a9ae7fc0e2d508` 的 pi-mono 全部内容为完整对齐目标**——包括全部 provider、全部运行模式、`server`、`evals`、`storage`。缺少 API 凭据只降低单项的可验证等级，不构成缩小实现范围的理由。
- 本 goal 是**纯审计任务**：只盘点、分类、记录，不实现任何功能、不修任何 bug、不改任何生产代码。发现的问题一律记录，越界实现视为违规。

## 一、任务

以 `git show`/worktree 方式读取审计提交（**禁止以 pi-mono-legacy worktree 的 2026-04 状态为审计基准**——其中含基线之后的功能；仅允许将其作为阅读便利，逐项以 `71efc6f0` 内容为准），产出一份完整地图 `docs/parity-map.md`：

### 1. 功能差距盘点
- 逐 package（`ai`、`agent`、`coding-agent`、`tui`、`storage`、`server`、`evals`）枚举其对外行为面（provider 清单、运行模式、CLI 选项、公开 API、工具集、会话/存储格式、服务端点）。
- 每项标注状态：`已实现`（链接到 cadr 对应模块与测试）/ `缺失` / `有意差异`（链接到既有差异清单条目，如全 Lisp 扩展生态）。
- Provider 逐个列出（约 35 个），每个标注：协议类别（openai-completions 兼容 / 独立协议）、认证方式、实现难点（如 Bedrock SigV4、Vertex GCP 认证、Copilot 设备流）、**可达验证等级**（fixture 对拍 / live 冒烟，依据现有凭据：DeepSeek key、ChatGPT OAuth、本地 Ollama）。

### 2. 测试三分类审计
- 枚举审计提交中全部 `*.test.ts` 文件（含 `evals`、`server`、`storage` 的测试），逐文件分类：
  - `已覆盖`：链接到现有 CL 测试名（与 docs/test-matrix.md 互相校对，发现矩阵错漏一并记录）；
  - `适用但未覆盖`：属于已实现功能但 CL 缺对应测试——这是当前欠账，单独成表；
  - `对应缺失功能`：归入功能差距盘点对应条目，随该功能的实现波次一起补。
- 分类必须全量：审计提交里每个测试文件在地图中恰好出现一次，总数对得上。

### 3. 波次建议（供用户裁决，不自行开工）
- 按依赖关系与性价比给出建议分批（如：OpenAI 兼容 provider 批量 → RPC/JSON 模式 → 独立协议 provider → storage/server/evals），每波估计规模与验证方案。仅为建议，实现顺序由用户拍板后另立 goal。

## 二、验收标准

1. `docs/parity-map.md` 存在，功能面逐 package 全覆盖，provider 清单数量与审计提交 `packages/ai/src/providers/` 实际文件一致。
2. 测试文件枚举总数与 `git show` 统计一致，三分类无遗漏、无重复；"适用但未覆盖"表可直接作为补测试的工作清单。
3. test-matrix.md 的错漏（若有）已记录（不修改矩阵本身，修正随后续 goal）。
4. 全程零已跟踪文件及生产代码变更；本次新增内容仅为 `docs/parity-map.md` 与本报告。全量测试数量与 goal 3 验收时一致（690），全绿。
5. 审计报告注明所用的精确 git 命令，抽查可复现。

## 三、原则

- 只记录不修复；对既有差异清单条目（全 Lisp 扩展、REPL 后备等)不重新翻案，仅链接。
- 对每个 provider 的"可达验证等级"必须诚实标注，不得把 fixture 对拍宣称为 live 验证。
- 完成后暂停等待用户裁决波次，不得自行开始任何实现。

## 四、完成记录（2026-07-30）

- 审计基线：`71efc6f0c1909874ec8c944637a9ae7fc0e2d508`，通过 detached worktree 读取。
- Provider：`packages/ai/src/providers/` 顶层 82 个文件；`builtinProviders()` 的 38 个 text provider 已逐项记录并机械对账；另记 1 个 image provider 与 1 个 faux provider。
- 测试：352 个 `*.test.ts`，分布为 ai 120、agent 18、coding-agent 187、tui 27，storage/server/evals 各 0；manifest 逐路径对账无遗漏、无重复。
- 严格整文件分类：已覆盖 1、适用但未覆盖 2、对应缺失功能 349。局部覆盖但含任一未实现 case 的文件保留在“对应缺失功能”。
- `docs/test-matrix.md` 发现的错漏只记录在 parity map，未修改原文件。
- Common Lisp 全量回归：cadr-ai 256、cadr-agent 156、cadr-tui 59、cadr-cli 219，共 690 checks，全部通过。
- 交付变更仅为 `docs/parity-map.md` 与本报告；未修改生产代码、测试或既有矩阵。
