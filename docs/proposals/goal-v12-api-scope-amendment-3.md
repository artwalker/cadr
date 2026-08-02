# Goal 12 扩展 API 实现面第三次补充解冻提案

状态：**approved and implemented**（用户于 2026-08-02 逐项裁决：F：批准，G：批准，H：批准）。

固定基线：
`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`
（`v0.83.0-38-g74caa2649`）。本文所有 baseline `file:line` 均指该提交。

## 1. 为何再次停止

D/E 获批后，授权范围内的 runtime/TUI/OAuth bridge 已实现，99 个基线 extension
example 中 94 个已可用现有 API 移植。逐个做真实入口审计时确认剩余 5 个文件依赖
三条尚未接入生产调用链的基线合同：

- `custom-compaction.ts`：`:session-before-compact` 虽已在事件表和返回值校验器中存在，
  但 compact 主路径从未 dispatch；
- `prompt-customizer.ts`：`:before-agent-start` 的 `:system-prompt-options` 当前硬编码为 NIL；
- custom Anthropic 与 GitLab Duo 的 3 个文件：OAuth/token/direct-access 控制面依赖
  extension 可调用的 HTTP seam，Cadr 目前只有 subprocess `exec`，没有等价能力。

这不是新增产品功能，而是此前提案把“API 已声明”误判成“真实调用链已闭合”。但三项
都超出已批准文件面，且用户已明确要求越界即 blocked。因此没有伪造示例、调用
`cadr-ai::native-http-request`、全局替换函数或把 provider 写入全局 registry。当前账本
在批准前如实记为 **94 ported / 5 gap**；实施后为 **99 ported / 0 gap**。

## 2. 补充项 F：把 `session_before_compact` 接入真实 compaction 生命周期

### 2.1 确切需求与基线证据

基线在手动与自动 compaction 两条路径均于摘要生成前 dispatch：

- `packages/coding-agent/src/core/agent-session.ts:1796-1831`：手动 compaction 传入
  `preparation`、`branchEntries`、`customInstructions`、`reason="manual"`、
  `willRetry=false`、abort signal，并接受 cancel 或完整 custom compaction；
- 同文件 `:2065-2105`：threshold/overflow 路径使用相同合同；
- `packages/coding-agent/src/core/extensions/types.ts:591-612`：冻结事件与 after-event 字段；
- `packages/coding-agent/examples/extensions/custom-compaction.ts:21-131`：示例读取完整
  preparation，返回 `summary/firstKeptEntryId/tokensBefore/usage`。

Cadr 已在 `src/cadr-agent/extensions.lisp:3527-3569,3577-3584,3903-3909` 校验并合并
`:session-before-compact` 的 `:cancel-p/:compaction` 返回值，但
`src/cadr-agent/compaction.lisp:235-297` 直接生成并写入默认摘要，从未调用 lifecycle。

### 2.2 最小补充解冻面

- `src/cadr-agent/compaction.lisp`：在已完成 preparation、尚未调用默认 summarizer 时
  dispatch；传入 source/kept entries、token 数、custom instructions、manual/threshold/
  overflow reason、will-retry 与 session-local cancellation signal；严格消费已存在的
  `:cancel-p/:compaction` 合同。
- 对应 `test/cadr-agent/*compaction*` 与 Goal 12 example tests。

不修改 `src/cadr-ai`，不新增事件，不改变 `extensions.lisp` 已冻结的事件语义。

### 2.3 默认行为与门禁

- 没有 handler 或 handler 返回 NIL 时，默认摘要输入、事件顺序、session entry、JSON/RPC
  wire 与错误文案逐字节不变。
- 红测试覆盖：手动/threshold/overflow payload；cancel；extension compaction；空摘要回退；
  abort；handler error 回退；after event 的 `from-extension`；custom result 完整写入会话。
- 已有 `:session-before-compact` 事件名与返回结构不增加字段、不改含义。

### 2.4 替代方案、冻结与回滚

- 在示例里重写 `/compact` command：绕过自动 compaction/overflow，非基线合同。
- 只调用 hook 但忽略返回值：会把“有事件”伪装成“可定制”。

回滚只删除 compaction 主路径 dispatch 分支；无 handler 的旧路径保持原函数体。

## 3. 补充项 G：保存并发出真实 `systemPromptOptions`

### 3.1 确切需求与基线证据

基线 `BuildSystemPromptOptions` 包含 custom prompt、selected tools、tool snippets、prompt
guidelines、append prompt、cwd、context files、skills：

- `packages/coding-agent/src/core/system-prompt.ts:8-25`：完整字段合同；
- `packages/coding-agent/src/core/extensions/types.ts:698-709`：`before_agent_start` 必须携带
  fully assembled prompt 与构建它的结构化 options；
- `packages/coding-agent/src/core/extensions/runner.ts:1081-1112`：每个 handler 均收到同一
  options，system prompt 的逐 handler 修改不反向污染 options；
- `packages/coding-agent/examples/extensions/prompt-customizer.ts:22-96`：示例依赖
  `selectedTools/skills/appendSystemPrompt`，不是只读 cwd 的近似实现。

Cadr 的 `src/cadr-agent/loop.lisp:1259-1277` 把 `:system-prompt-options` 写死为 NIL；真实
字段只在 `src/cadr-cli/main.lisp:2280-2323` 和 `src/cadr-cli/sdk.lisp:355-375` 组装后
立即压平成字符串。`src/cadr-agent/extensions.lisp:258-265` 的 command-only getter 不能
替代 lifecycle event payload，也不得放宽其语义。

### 3.2 最小补充解冻面

- `src/cadr-agent/runtime.lisp`、`src/cadr-agent/tool.lisp`：agent 新增只读的
  `system-prompt-options` slot/constructor 参数；未传入时为 NIL。
- `src/cadr-agent/loop.lisp`：`before-agent-start` payload 读取该 slot，保留现有
  system-prompt 串与逐 handler merge 语义。
- `src/cadr-cli/main.lisp`、`src/cadr-cli/sdk.lisp`：系统提示构造同时返回 prompt 与
  defensive-copy options，并在 reload 时原子更新两者。
- 对应 agent/CLI/SDK/example tests。

不修改 `sdk-services.lisp` 的 prompt builder，不改变 command-only getter，不修改
`src/cadr-ai`。

### 3.3 默认行为与门禁

- 构造者未传 options 时事件仍带 NIL；现有调用点与外部构造 API 保持兼容。
- CLI/SDK 真实路径的最终 system prompt 必须逐字节不变；只新增此前为 NIL 的结构化
  event 字段，不进入 agent-event/JSON/RPC wire。
- 红测试覆盖全部 8 个字段、defensive copy、两 handler 顺序、reload 更新、CLI/SDK
  等价，以及 command-only getter 继续拒绝 lifecycle context。

### 3.4 替代方案、冻结与回滚

- handler 现场重新扫描 resources：时序不一致、重复 I/O，且违反基线“无需重发现”。
- 从最终 prompt 反向解析：有损且会把格式细节当 API。
- 借用 command-only getter：改变已冻结 context-kind 语义。

回滚删除 agent slot/双值传递，prompt builder 与最终 prompt 本身不变。

## 4. 补充项 H：session-local extension HTTP control-plane seam

### 4.1 确切需求与基线证据

基线 extension 运行于 JS，天然可调用 `fetch`；两份 provider 示例把该能力用于真实
认证与 provider 控制面：

- `custom-provider-anthropic/index.ts:78-153`：authorization-code exchange 与 refresh
  均 POST JSON token endpoint；`:574-609` 注册 OAuth 与 custom stream；
- `custom-provider-gitlab-duo/index.ts:183-208`：用 OAuth access token 换取并缓存
  direct-access token；`:233-300` 完成 form-urlencoded login/refresh；`:306-375`
  将短期 token/headers 投影到现有 Anthropic/OpenAI stream；
- 同文件 `:381-403`：上述能力是 provider 注册的组成部分，不是独立 demo。

Cadr 的 `src/cadr-agent/extensions.lisp:26-45,781-815,1823-1860` 只有 host `exec` seam。
`cadr-ai:*http-request-function*` 虽导出，但构造 request 所需接口未公开；直接调用
`cadr-ai::native-http-request` 会让扩展依赖冻结层私有实现。shell 到 `curl` 又会新增宿主
依赖并把 token 暴露在进程参数/环境中，均不接受。

### 4.2 最小补充解冻面与签名

- `src/cadr-agent/extensions.lisp`：给 extension host 增加 session-local
  `http-request-function`，导出 additive：

  ```lisp
  (extension-api-http-request api url
    &key method headers body timeout-ms signal)
  => (:status integer :headers alist :body octet-vector)
  ```

  URL/method/header/body 先复制并校验；signal/timeout 传播；返回值不含 request secrets。
- `src/cadr-agent/package.lisp`：仅导出上式及必要的结果 reader（若实现采用 struct）。
- `src/cadr-cli/extensions.lisp`：创建 host 时注入 adapter，内部复用现有 Cadr-AI HTTP
  transport；扩展只见稳定的 agent API，不见 Cadr-AI 私有 request object。
- `src/cadr-cli/sdk.lisp`：SDK host 使用同一 adapter，避免 CLI/SDK 扩展能力分叉。
- 对应 agent/CLI/SDK/example tests。

本项只提供 OAuth/direct-access 所需的 buffered control-plane request；provider 的 SSE
仍通过已批准 `runtime-provider` stream function 和既有 Cadr-AI provider stream 实现，
不另造 transport。无新第三方依赖，不改 `src/cadr-ai`，不进入 ASDF 闭包。

### 4.3 凭据、默认行为与门禁

- 未调用时零网络、零新线程、零可观察变化；host 未注入时明确报 unavailable。
- redirect、abort、timeout、非 2xx 均返回/抛出稳定的 extension-level condition；condition、
  log、notice、wire fixture 不得包含 Authorization、access token、refresh secret 或 body。
- 临时 HTTP server 红测试覆盖 JSON/form body、headers/status/bytes、timeout、abort、并发
  session 隔离、reload stale API；OAuth tests 使用网络桩和临时 auth store。
- 两个 provider 均走既有 auth store、refresh lock、原子写；reload 移除 provider 投影但
  不删 credential；不写 `src/cadr-ai` 全局 registry。

### 4.4 替代方案、冻结与回滚

- 导出/修改 Cadr-AI transport：违反本批 `src/cadr-ai` 完全冻结。
- `curl` subprocess：宿主依赖、token 泄露面和取消语义均劣于现有 transport。
- 为两个示例各写特例：不是 extension API，后续 provider 仍无法移植。
- 把 HTTP 做成默认 agent tool：污染默认 YOLO 工具集，且基线没有该机制。

回滚删除 host callback 与公开 wrapper；未调用路径没有持久状态。

## 5. 受阻示例、裁决项与恢复顺序

批准时的 5 个 gap（现均关闭）：

| Baseline 文件 | gap | 对应裁决 |
|---|---|---|
| `custom-compaction.ts` | `:compaction-lifecycle-dispatch` | F |
| `prompt-customizer.ts` | `:system-prompt-options-event-payload` | G |
| `custom-provider-anthropic/index.ts` | `:extension-http-runtime` | H |
| `custom-provider-gitlab-duo/index.ts` | `:extension-http-runtime` | H |
| `custom-provider-gitlab-duo/test.ts` | `:extension-http-runtime` | H |

用户裁决：

1. **F（解冻 `src/cadr-agent/compaction.lisp` 的 lifecycle dispatch）：批准。**
2. **G（解冻 agent prompt-options 保存与 CLI/SDK 双值传递）：批准。**
3. **H（增加 session-local extension HTTP control-plane seam）：批准。**

三项已按 F→G→H 完成 5 个示例；extension export SHA、architecture、README、
source-parity 与 parity-map 随实施提交同步，随后进入 Goal 12 Part D。F/G/H
补齐的是固定基线已有能力，不列为相对基线的有意新增。
