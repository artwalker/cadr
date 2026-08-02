# Goal 12 扩展 API 实现面补充解冻提案

状态：**blocked，等待用户逐项裁决。**

固定基线：
`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`
（`v0.83.0-38-g74caa2649`）。本文所有 baseline `file:line` 均指该提交。

## 1. 为何必须补充裁决

用户已批准 `goal-v12-example-api-gaps.md` 全部 19 项能力，但同时规定：任一
实现需要越出各项所列最小文件面时，必须立即 blocked 并重新提案。开工前
逐路径读取证明第 7、8、10 项的真实基线语义必然穿过原未列出的核心文件。
这不是功能扩面，而是原提案对现有 Cadr 分层判断不完整。

本提案只请求增补解冻必不可少的文件；原 19 项的需求、默认行为、依赖
和回滚边界全部不变。`src/cadr-ai` 仍完全冻结。

## 2. 补充项 A：第 7 项 tool terminate 的 agent-loop 语义

### 2.1 确切需求与基线证据

- `packages/agent/src/types.ts:354-368` 把 `terminate` 定义为
  `AgentToolResult` 上不进 provider wire 的 agent-only 提示。
- `packages/agent/src/agent-loop.ts:540-553,582-584` 规定精确批语义：只有当
  finalized call 非空，且该批每个最终 result 均为 `terminate === true`
  时才终止 agent loop。混合批不终止。
- `packages/coding-agent/src/core/extensions/types.ts:446-497` 将该字段作为扩展
  tool execute 结果合同的一部分。

Cadr 当前 `src/cadr-agent/tool.lisp:127-130,228-254` 的 outcome 及 executor
返回合同只保留 content/details；`src/cadr-agent/loop.lisp:457-548,885-908`
的 batch 第三值只有 abort，无法表达“全部 terminate 才停”。

### 2.2 最小补充解冻面

- `src/cadr-agent/tool.lisp`：在 agent-only outcome 中保留 terminate，不改
  `cadr-ai:tool-result-message`。
- `src/cadr-agent/loop.lisp`：对 finalized outcomes 实施与基线一致的
  非空 + `every` 批门控，与 abort 状态分开。

原已批第 7 项的其余文件面不变。不解冻 `src/cadr-ai`。

### 2.3 默认行为与门禁

- 所有旧 tool 默认 terminate=nil，其 result、event、JSON/RPC wire 逐字节不变。
- 红测试覆盖：单个 true、全部 true、true/nil 混合、空批、after hook 最终值，
  并锁定每个 tool result 仍完整入会话。
- 旧扩展 fixture、旧宏 lambda list、34-event 集及 payload/wire fixture 不变。

### 2.4 已考虑但否决的替代方案

- 把 terminate 写进 details：会污染发给模型与 UI 的可观察 payload，且 loop 仍不读。
- 把 terminate 当 abort/error：会把正常终止伪装为错误，改变 event 与会话。
- 单个 tool 立即停：违反基线的整批 `every` 语义。

回滚：删除 outcome 字段与 loop gate；旧路径因默认 nil 无迁移。

## 3. 补充项 B：第 8 项 partial update 与 cancellation 的执行路径

### 3.1 确切需求与基线证据

- `packages/coding-agent/src/core/extensions/types.ts:307-346,479-486` 规定 handler
  获得 signal、onUpdate 与 ExtensionContext。
- `packages/agent/src/types.ts:371-377,388-394` 把 partial callback 定义为当次
  execute 的有界合同，handler settle 后的 callback 必须忽略。
- `packages/agent/src/agent-loop.ts:672-689` 由 agent tool 执行层发出
  `tool_execution_update`。

Cadr 当前 `src/cadr-agent/extensions.lisp:2024-2064` 将扩展 handler 降为
`(call-id arguments context)`；`src/cadr-agent/tool.lisp:228-254` 的 executor 只有两参；
`src/cadr-agent/loop.lisp:175-189,457-548` 只发 start/end。仅在 extension adapter
里临时发 event 无法保证 settle 边界、restart 重试、并行批次序及核心
lifecycle 一致性。

### 3.2 最小补充解冻面

- `src/cadr-agent/tool.lisp`：向工具 executor 传入当次 cancellation signal 与
  update callback，用 unwind-protect 关闭 callback，保证 settle 后更新忽略。
- `src/cadr-agent/loop.lisp`：通过现有 agent lifecycle/event spine 发出
  `:tool-execution-update`，并保持同一 call-id 与并行批隔离。

原已批第 8 项的 extensions/package/execution-env/CLI tool factory 文件面不变。
不解冻 `src/cadr-ai`。

### 3.3 默认行为与门禁

- 旧二参 `cadr-ai:tool-executor` 及旧三参 extension handler 仍走兼容 adapter，
  无 partial 时 event 序列逐字节不变。
- 红测试覆盖：单调用多次 update、settle 后 update 被忽略、handler 错误、
  retry 后新 signal、用户 abort、并行工具隔离及 update/start/end 的精确顺序。
- `ctx.shutdown()` 继续调用既有 agent shutdown，不新增退出策略。

### 3.4 已考虑但否决的替代方案

- 在 extension adapter 里直接 emit：绕过 tool restart/settle 层，迟到 callback
  会泄漏到后续 turn。
- 让扩展轮询 `extension-cancellation-aborted-p`：无法将用户 abort 与当次
  tool invocation 精确绑定，也缺 partial callback。
- 只在 TUI 合成 update：print/json/rpc 与核心 lifecycle 会分叉。

回滚：删除执行上下文参数与 update 发射；旧 adapter 不变。

## 4. 补充项 C：第 10 项进入真实 `/login` orchestration

### 4.1 确切需求与基线证据

- `packages/coding-agent/src/core/extensions/types.ts:1364-1475` 规定扩展 provider 的
  login/refresh/getApiKey/model projection/custom stream 合同。
- `packages/coding-agent/src/core/extensions/provider-composer.ts:230-247,411-498` 把该合同
  适配到统一 provider/auth runtime，而非让扩展直接写凭据文件。

Cadr 虽然已有 runtime-provider 与 auth storage，但 `src/cadr-cli/config.lisp:221-236`
只接受 openai/openai-codex/anthropic，`:238-275` 的 `/login` 用 `ecase`
直调两个内置函数。`src/cadr-cli/main.lisp:3141-3148` 在 extension command
之前处理该路径，因此只改已批的 extensions/model-services 无法让扩展
OAuth 进入真实 `/login`。

### 4.2 最小补充解冻面

- `src/cadr-cli/config.lisp`：让 `handle-auth-command` 可注入 provider OAuth
  resolver/handler；无注入时的内置 openai/anthropic 路径与文案不变。
- `src/cadr-cli/main.lisp`：将当前 extension/model runtime 绑到 auth command，
  复用现有 auth store、refresh lock 与原子写。
- `src/cadr-cli/tui.lisp` **仅作条件解冻**：若扩展 OAuth callback 的展示/输入
  无法由现有 `/login` output/auth-url 桥完整承载，只允许增加同一 callback
  桥；不改 selector 布局、文案或默认条目。实施时若证明不需要则不修改。

原已批的 extensions/model-services 文件面不变。`src/cadr-ai` 继续冻结。

### 4.3 默认行为与门禁

- 无扩展 OAuth 时，`/login openai`、`/login anthropic`、无参选择器、存储
  provider identity 及所有文案逐字节不变。
- 红测试使用临时 auth store 和网络打桩，覆盖：扩展 provider 出现在
  `/login`；login 凭据以同一 provider identity 落盘；默认 route 立即可取；
  refresh 并发只发生一次；getApiKey/model projection/custom stream 各自生效；
  reload 移除 auth method/model 但不删除已存凭据。
- 日志、condition、notice 与 wire fixture 不得包含 token/refresh secret。

### 4.4 已考虑但否决的替代方案

- 让示例直接写 `auth.json`：绕过 identity、refresh lock、原子写和权限保持，
  是已明令禁止的“绕过式通过”。
- 把 extension `/login` 当普通自定义 command：核心 auth handler 优先拦截，
  且无法进入统一 credential/runtime 合同。
- 在 `src/cadr-ai` 加特例：不需要，且违反冻结红线。

回滚：删除 auth resolver 注入与 runtime 绑定；内置函数仍为默认。

## 5. 裁决与施工顺序

请逐项裁决：

1. **A（第 7 项补充文件面）：批准 / 拒绝 / 暂缓。**
2. **B（第 8 项补充文件面）：批准 / 拒绝 / 暂缓。**
3. **C（第 10 项补充文件面）：批准 / 拒绝 / 暂缓。**

三项获批后，恢复原施工顺序 1→10、15→19、11、13→12→14、Part D，
不再对已批能力重复要求裁决。若任一项不获批，受该 gap 阻塞的示例
继续记为缺失；其余项的能力批准不变，但为遵守“立即 blocked”硬约束，
本轮在新裁决前不开工。
