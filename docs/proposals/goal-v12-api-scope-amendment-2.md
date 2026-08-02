# Goal 12 扩展 API 实现面第二次补充解冻提案

状态：**D/E 已于 2026-08-02 获得用户批准，按原文实施。**

固定基线：
`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`
（`v0.83.0-38-g74caa2649`）。本文所有 baseline `file:line` 均指该提交。

## 1. 为何再次停止

用户批准补充项 A/B/C 后，A/B 已在获批文件面内实现并通过定向门禁；第 9、
第 11、SDK 15–19 也已形成未提交增量。继续开工前的调用链审计又确认两个原提案
漏列的实现面。它们都属于已批准能力的必经路径，不是功能扩面；但通用约束明确规定
任一越界必须立即 blocked，因此没有用全局函数替换、污染 Cadr-AI registry 或弱化
合同绕过。

本提案只请求 D/E 两个最小增补。A/B/C 的需求与裁决不变，`src/cadr-ai` 继续完全
冻结；当前未提交实现保留在工作区，获批前不再修改生产代码。

## 2. 补充项 D：完整 autocomplete provider 必须进入 TUI provider/editor 协议

### 2.1 确切需求与基线证据

已批第 6 项要求 extension autocomplete factory 获得完整 current provider，并保留
`getSuggestions`、`applyCompletion`、`shouldTriggerFileCompletion`、request signal、cwd
及结果合同。基线合同位于：

- `packages/tui/src/autocomplete.ts:241-270`：`AutocompleteProvider` 三个方法与
  `AbortSignal`/force 参数；
- `packages/tui/src/components/editor.ts:2165-2217,2242-2312`：editor 为每次请求创建
  controller，取消旧请求，拒绝 aborted/stale 结果，并通过 provider 应用 completion；
- `packages/coding-agent/examples/extensions/github-issue-autocomplete.ts:91-127`：示例包装
  current provider，条件不命中或被取消时委托原 provider。

Cadr 当前阻断点为：

- `src/cadr-tui/autocomplete.lisp:18-27` 的 provider 只有 commands/base-path/fd-path；
- `src/cadr-tui/autocomplete.lisp:429-472,474-524` 的 suggestions/apply 是固定普通函数，
  replacement struct 无法覆盖；
- `src/cadr-tui/editor.lisp:935-963,1072-1105` 直接调用上述函数，没有 request-local
  cancellation/stale-result seam。

只改原提案列出的 `src/cadr-cli/tui.lisp` 无法表达该合同。通过 `setf symbol-function`
替换全局函数会跨 editor 污染并改变默认路径，明确否决。

### 2.2 最小补充解冻面

- `src/cadr-tui/autocomplete.lisp`：给 provider 增加可选 callbacks，默认 NIL 时继续走
  现有固定实现；公开统一 dispatch，不改现有 constructor 默认值。
- `src/cadr-tui/editor.lisp`：增加 request-local cancellation/stale generation；仅自定义
  async provider 使用，新能力未注册时走现有同步路径。
- `src/cadr-tui/package.lisp` 与对应 TUI/CLI tests：导出必要的 additive constructor/
  dispatch surface。

原第 6 项的 agent/CLI 文件面不变；无依赖，不修改 `src/cadr-ai`。

### 2.3 默认行为与门禁

- 没有 extension provider 时，现有 provider struct、空格/删除触发语义、suggestions、
  apply 结果与整屏快照逐字节不变。
- 红测试覆盖：wrapper 命中、委托 current、force/trigger、cwd、取消前/请求中/完成后、
  旧请求晚到、apply 的行列位置，以及两个 editor 并行互不污染。
- 现有空格、连续空格、空前缀、`/`、`@`、路径片段、删除到空门禁继续全绿。

### 2.4 替代方案、冻结与回滚

- 只支持命令 argument completer：不能运行 GitHub issue 示例，也没有 signal/current
  provider 合同。
- 在 CLI 预先合并 suggestions：绕过 editor 的取消与 stale gate。
- 动态替换全局 fdefinition：隐藏的进程级副作用，多个 session 无法隔离。

回滚删除可选 callbacks/generation 与新 adapter；旧 provider 默认分支保持原函数体。

## 3. 补充项 E：扩展 OAuth provider 必须进入无参 `/login` 的 provider source

### 3.1 确切需求与基线证据

已批第 10 项明确要求扩展 provider 进入真实 `/login`。基线 selector 从 session
`modelRuntime` 当前 providers 构造，而不是仅读静态 built-ins：

- `packages/coding-agent/src/modes/interactive/interactive-mode.ts:4894-4924` 枚举
  `modelRuntime` provider 的 OAuth/API-key 方法；
- 同文件 `:2773-2774,4975-4986` 使无参和显式 `/login` 共用该 runtime 合同。

Cadr 当前调用链为：

- `src/cadr-agent/extensions.lisp:1499-1535,2764-2768` 只把 native provider 放入
  extension snapshot；
- `src/cadr-cli/model-services.lisp:618-639` 同步到 session-local models runtime；
- `src/cadr-cli/tui.lisp:4134-4149` 的无参 selector，以及 `:2743-2750,3391-3393`
  的 `/login` autocomplete，仍硬编码 `cadr-ai:list-provider-definitions`；
- `src/cadr-ai/registry.lisp:294-320` 是冻结的全局 built-in registry，不能被扩展污染。

补充项 C 对 `tui.lisp` 的条件解冻只授权 OAuth prompt callback bridge。该 bridge
确实需要启用：Anthropic 示例在 URL 后询问 authorization code
（`custom-provider-anthropic/index.ts:92-95`），GitLab 示例询问 callback URL
（`custom-provider-gitlab-duo/index.ts:245-247`）；现有 `auth-url` 单向 consumer 不够。
但它没有授权 selector provider source 注入，因此本项另行申请。

### 3.2 最小补充解冻面

- 明确允许 `src/cadr-cli/tui.lisp` 新增 `login-options-function` 注入点，同时供 selector
  与 autocomplete 使用；没有注入时继续调用当前 built-in 列表。
- `src/cadr-cli/main.lisp` 组合 built-in definitions 与当前 extension/model runtime
  provider，不写全局 registry。
- `src/cadr-cli/model-services.lisp` 只读投影 runtime provider 的 id/name/auth-types。

这三条与已批 C 的 config/main prompt callback seam 一起完成。无需修改
`interactive-services.lisp` 或 `src/cadr-ai`。

### 3.3 默认行为、凭据纪律与门禁

- 无扩展 OAuth 时 `/login openai`、`/login anthropic`、无参 selector、autocomplete、
  provider 顺序、全部文案和整屏快照逐字节不变。
- 扩展加载时 selector/autocomplete 才增加其方法；reload 后消失，但 auth store 中已存
  凭据不删除。
- 临时 auth store + 网络桩锁定 identity、默认 route、同一 refresh lock/原子写；日志、
  condition、notice、wire 均断言不含 token/refresh secret。
- prompt callback 用既有 overlay/Input 组件：worker 通过条件变量等待，取消返回 NIL；
  不改 selector 布局、默认条目或文案。

### 3.4 替代方案、冻结与回滚

- 把 extension provider 写入 `cadr-ai:*provider-definitions*`：跨 session 污染且违反
  `src/cadr-ai` 冻结。
- 只支持 `/login <id>`：无参真实用户路径与基线不等价。
- 让扩展自建 command/写 auth.json：绕过统一 auth store、refresh lock 和原子写。

回滚删除 provider-source 注入与 runtime projection；未注入路径仍是原 built-in 调用。

## 4. 裁决与恢复顺序

裁决结果：

1. **D（第 6 项补充 `autocomplete.lisp`/`editor.lisp` 文件面）：批准。**
2. **E（第 10 项允许 `tui.lisp` provider-source 注入）：批准。**

D/E 均获批后，恢复既定顺序：完成 1→10、15→19、11、13→12→14、Part D。
若任一不获批，对应示例继续诚实记为缺失；其余已获批增量不得冒充该合同完成。
