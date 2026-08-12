# Goal 18 L1a：Mermaid 渲染的依赖裁决提案（已裁决）

状态：**已裁决（2026-08-12）：路线 1（纯 Lisp 移植 grok-mermaid + 差分
金样）批准，拆为 goal 19 执行，不在 goal 18 内实施。** v0.84.1 为基线
新增 `components/mermaid.ts`（89 行薄封装），真正的 Mermaid 解析与布局
在第三方库 `grok-mermaid@0.2.2` 中。按常设约束（新依赖必须预审），本
提案给出路线、成本与风险；goal 18 内未开始任何实现。

> 落账记录（2026-08-12，用户裁决）：`docs/source-parity.md` 中
> `mermaid.ts` 行由 `待裁决` 记为 `缺失`（非"有意差异"——该能力尚未
> 实现，账本如实登记）；`docs/open-questions.md` `OQ-G18-L1A-MERMAID`
> 移入"已裁决待办 goal"区。goal 19 关账前 Mermaid 块按基线回退语义
> 渲染为源码框。路线 2（引入等价 Lisp 依赖）已因 Quicklisp 无此生态
> 核查而排除；路线 3 不被接受作为终态。

## 依赖事实（已实测）

- artifact：`grok-mermaid@0.2.2`，`https://registry.npmjs.org/grok-mermaid/-/grok-mermaid-0.2.2.tgz`
- 许可：Apache-2.0（允许再分发，须保留声明）
- 运行时依赖：**零**；dist 为 4,224 行无依赖 ESM（parse 1,107 + layout 880
  + width-data 993 + canvas/labels/ansi/...）
- 能力面：`graph`/`flowchart`（含 `subgraph`）、`stateDiagram`、
  `classDiagram`、`erDiagram`、`sequenceDiagram`；渲染为 Unicode 制表符
  字符画；不支持或过大时返回 null，由调用方回退 `sourceBox`
- 基线用法（`mermaid.ts`）：markdown 中的 ```mermaid 块经 `render()` 出
  字符画，超宽或失败时回退源码框

## 三条路线

### 路线 1：纯 Lisp 移植 grok-mermaid（推荐）

把 4.2k 行解析/布局移植为 cadr 自有 Lisp 代码（新 system 或 cadr-tui 下
模块），**不引入任何第三方 Lisp 库**，ASDF 闭包与发行二进制零变化。

- 成本：解析器 + 布局器移植，约 3–5 个工作日量级；Unicode 宽度表
  （width-data 993 行）可机械转换。
- 风险：移植偏差——**用差分金样控制**：基线库对固定语料库的字符画输出
  逐字节落为 fixture，cadr 移植版对同一语料逐字节对拍；语料覆盖五种图
  型 + 语法错误 + 流式半行 + 超宽回退。这正是本项目已验证的
  fixture-locked 打法。
- 许可：Apache-2.0 移植属衍生作品，在 NOTICE/dependency-audit 登记来源与
  许可文本。

### 路线 2：引入等价 Lisp 依赖

Quicklisp 生态**不存在** Mermaid 渲染器（已核查）。此路不通。

### 路线 3：记为有意差异（mermaid 块始终渲染源码框）

基线自身对不支持/超宽图的回退就是 `sourceBox`；路线 3 = 永远回退。
用户可见能力损失真实存在（基线对五种图型出字符画，cadr 只出源码框），
按分岔政策须配等强度断言（mermaid 块渲染为源码框的固定形状）。这是
已裁决差异里最便宜但能力最缺的一条。

## 建议

路线 1。理由：零依赖、体量有界、差分金样使"对齐基线"可机器验证，且
与项目"不做阉割"的北极星一致。若裁决认为升级窗口不承载该工作量，可
先以路线 3 落账（显式断言 + 差异登记），把路线 1 拆为后续 goal——但
那是有意的能力欠账，须写明。

## 裁决与落账动作（2026-08-12）

- 路线 1 批准，拆为 **goal 19**；goal 18 剩余批次（④⑥⑦⑧）先行收完，
  goal 18 关账后立即开 goal 19。
- source-parity 账本已记 `缺失`；open-questions 已登记为已裁决待办 goal。
- goal 19 执行时：docs/dependency-audit.md 登记 artifact/hash/许可/移植
  关系（Apache-2.0 衍生作品注明来源与许可文本）；差分 fixture 生成器
  入门禁；mermaid.ts 的 89 行封装按常规分流移植；完成后 source-parity
  改判 `已实现`。
