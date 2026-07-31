# GOAL v7 扩展 API 限定扩充提案

> 历史提案：文内 `71efc6f0…` 仅是 Goal 7 当时的审计锚点；Goal 9 起当前
> 规范基线为 `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`。

状态：**第 1–8 项已实现并通过验收；扩大后的 API 已重新冻结。**

固定行为基线：
`71efc6f0c1909874ec8c944637a9ae7fc0e2d508`，checkout
`/tmp/cadr-parity-71efc6f0`。本文所有 `file:line` 均指该提交。

## 1. 边界

本提案只解冻：

1. Wave 2 会话、agent event spine 和队列测试直接需要的、审计提交已经存在的
   extension lifecycle events；
2. 审计提交 RPC 协议已经存在的 extension UI request/response surface；
3. 上述新增面的 Lisp 命名、payload 表示、结果表示和 `cadr-cli` bridge。

明确不解冻 provider、工具执行语义、TUI 组件或其余扩展能力。现有四个事件、
宏签名和行为保持原样：

```lisp
(define-event-hook event &key (priority 0) handler)

:turn-start
:turn-end
:tool-call-before
:tool-call-after
```

既有 `extension-event-*` accessor、`extension-hook-result`、
`make-extension-hook-result`、handler 顺序、priority、replacement、append、
block/error 隔离、snapshot/reload 与 stale-context 语义均不变。

## 2. Lisp 公共表示

### 2.1 事件名

TypeScript `snake_case` event 名映射为 Common Lisp keyword 的 kebab-case。
原有四个事件不改名、不加别名：

| 原版事件 | Lisp 事件 | 处理 |
|---|---|---|
| `turn_start` | `:turn-start` | 已有，零变更 |
| `turn_end` | `:turn-end` | 已有，零变更 |
| `tool_call` | `:tool-call-before` | 已有，零变更 |
| `tool_result` | `:tool-call-after` | 已有，零变更 |

其余获批事件按下表新增。

### 2.2 Payload

新增一个公开 accessor：

```lisp
(extension-event-payload event) ; => 只读 property list
```

新事件的字段以 kebab-case keyword 保存；camelCase 只存在于原版 TypeScript
或 RPC JSON。嵌套对象同样使用只读 plist，序列使用 list/vector，既有 cadr
domain object 直接复用。缺失 optional 字段不出现在 plist 中；显式 false
使用 `nil`，需要区分“缺失”和 `nil` 时用 `(getf plist key sentinel)`。

原有四个事件继续使用既有专用 accessor；本提案不改变它们的 payload，也不
要求旧扩展改用 `extension-event-payload`。

TypeScript `AbortSignal` 映射为新的 opaque
`extension-cancellation-signal`；只公开：

```lisp
(extension-cancellation-aborted-p signal) ; => boolean
```

这同一对象用于 lifecycle payload 的 `:signal` 和 UI dialog 的 `:signal`。

### 2.3 Handler 返回值

旧事件仍只接受 `nil` 或 `extension-hook-result`，验证规则完全不变。

新事件使用原版 object-return 语义的 Lisp 等价：handler 返回 `nil` 或严格
校验的 plist。每个事件只接受下表列出的 key；未知 key、错误类型或不允许有
返回值的事件返回非 `nil` 都触发该 extension 的执行错误，不污染其他扩展。
多个 handler 的合并、短路和链式改写按固定参考 runner 实现：
`packages/coding-agent/src/core/extensions/runner.ts:787-948`。

这样不修改 `define-event-hook` 或 `make-extension-hook-result` 的签名，也不会
把新事件的结果语义塞进既有四事件。

## 3. 新增 lifecycle events

### 3.1 Session lifecycle

| 原版事件 → Lisp | payload 字段（原版 → Lisp） | handler result plist | 固定基线 |
|---|---|---|---|
| `session_start` → `:session-start` | `reason` → `:reason` (`:startup/:reload/:new/:resume/:fork`); `previousSessionFile?` → `:previous-session-file` | 无 | `packages/coding-agent/src/core/extensions/types.ts:561-568` |
| `session_info_changed` → `:session-info-changed` | `name` → `:name`，清除时为 `nil` | 无 | `packages/coding-agent/src/core/extensions/types.ts:570-575` |
| `session_before_switch` → `:session-before-switch` | `reason` → `:reason` (`:new/:resume`); `targetSessionFile?` → `:target-session-file` | `(:cancel-p boolean)` | `packages/coding-agent/src/core/extensions/types.ts:577-582,1103-1105` |
| `session_before_fork` → `:session-before-fork` | `entryId` → `:entry-id`; `position` → `:position` (`:before/:at`) | `:cancel-p`, `:skip-conversation-restore-p` | `packages/coding-agent/src/core/extensions/types.ts:584-589,1107-1110` |
| `session_before_compact` → `:session-before-compact` | `preparation` → `:preparation`; `branchEntries` → `:branch-entries`; `customInstructions?` → `:custom-instructions`; `reason` → `:reason` (`:manual/:threshold/:overflow`); `willRetry` → `:will-retry-p`; `signal` → `:signal` | `:cancel-p`; `:compaction` | `packages/coding-agent/src/core/extensions/types.ts:591-602,1112-1115` |
| `session_compact` → `:session-compact` | `compactionEntry` → `:compaction-entry`; `fromExtension` → `:from-extension-p`; `reason` → `:reason`; `willRetry` → `:will-retry-p` | 无 | `packages/coding-agent/src/core/extensions/types.ts:604-613` |
| `session_shutdown` → `:session-shutdown` | `reason` → `:reason` (`:quit/:reload/:new/:resume/:fork`); `targetSessionFile?` → `:target-session-file` | 无 | `packages/coding-agent/src/core/extensions/types.ts:615-621` |
| `session_before_tree` → `:session-before-tree` | `preparation` → `:preparation`; `signal` → `:signal` | `:cancel-p`; `:summary`; `:details`; `:usage`; `:custom-instructions`; `:replace-instructions-p`; `:label` | `packages/coding-agent/src/core/extensions/types.ts:638-643,1117-1130` |
| `session_tree` → `:session-tree` | `newLeafId` → `:new-leaf-id`; `oldLeafId` → `:old-leaf-id`; `summaryEntry?` → `:summary-entry`; `fromExtension?` → `:from-extension-p` | 无 | `packages/coding-agent/src/core/extensions/types.ts:645-652` |

`CompactionPreparation` 的嵌套 plist 精确字段：

| 原版字段 | Lisp key |
|---|---|
| `firstKeptEntryId` | `:first-kept-entry-id` |
| `messagesToSummarize` | `:messages-to-summarize` |
| `turnPrefixMessages` | `:turn-prefix-messages` |
| `isSplitTurn` | `:split-turn-p` |
| `tokensBefore` | `:tokens-before` |
| `previousSummary?` | `:previous-summary` |
| `fileOps` | `:file-operations` |
| `settings` | `:settings` |

出处：
`packages/coding-agent/src/core/compaction/compaction.ts:688-708`。

`TreePreparation` 的嵌套 plist 精确字段：

| 原版字段 | Lisp key |
|---|---|
| `targetId` | `:target-id` |
| `oldLeafId` | `:old-leaf-id` |
| `commonAncestorId` | `:common-ancestor-id` |
| `entriesToSummarize` | `:entries-to-summarize` |
| `userWantsSummary` | `:user-wants-summary-p` |
| `customInstructions?` | `:custom-instructions` |
| `replaceInstructions?` | `:replace-instructions-p` |
| `label?` | `:label` |

出处：`packages/coding-agent/src/core/extensions/types.ts:623-636`。

扩展提供的 `:compaction` 必须是完整 compaction result：
`:summary`, `:first-kept-entry-id`, `:tokens-before`,
`:estimated-tokens-after?`, `:usage?`, `:details?`，出处
`packages/coding-agent/src/core/compaction/compaction.ts:87-97`。

### 3.2 Agent、message 与 input lifecycle

| 原版事件 → Lisp | payload 字段（原版 → Lisp） | handler result plist | 固定基线 |
|---|---|---|---|
| `context` → `:context` | `messages` → `:messages` | `(:messages list)`；按 handler 顺序链式替换 | `packages/coding-agent/src/core/extensions/types.ts:669-673,1065-1067` |
| `before_agent_start` → `:before-agent-start` | `prompt` → `:prompt`; `images?` → `:images`; `systemPrompt` → `:system-prompt`; `systemPromptOptions` → `:system-prompt-options` | `:message`; `:system-prompt`，后者链式替换 | `packages/coding-agent/src/core/extensions/types.ts:698-709,1097-1101` |
| `agent_start` → `:agent-start` | 无 | 无 | `packages/coding-agent/src/core/extensions/types.ts:711-714` |
| `agent_end` → `:agent-end` | `messages` → `:messages` | 无 | `packages/coding-agent/src/core/extensions/types.ts:716-720` |
| `agent_settled` → `:agent-settled` | 无 | 无 | `packages/coding-agent/src/core/extensions/types.ts:722-725` |
| `message_start` → `:message-start` | `message` → `:message` | 无 | `packages/coding-agent/src/core/extensions/types.ts:742-746` |
| `message_update` → `:message-update` | `message` → `:message`; `assistantMessageEvent` → `:assistant-message-event` | 无 | `packages/coding-agent/src/core/extensions/types.ts:748-753` |
| `message_end` → `:message-end` | `message` → `:message` | `(:message replacement)`；replacement role 必须不变并按 handler 顺序链式替换 | `packages/coding-agent/src/core/extensions/types.ts:755-759,1092-1095`; runner `:830-870` |
| `input` → `:input` | `text` → `:text`; `images?` → `:images`; `source` → `:source` (`:interactive/:rpc/:extension`); `streamingBehavior?` → `:streaming-behavior` (`:steer/:follow-up`) | `(:action :continue)`；`(:action :transform :text ... :images ...)`；或 `(:action :handled)` | `packages/coding-agent/src/core/extensions/types.ts:824-847` |

### 3.3 Tool execution 与 model lifecycle

| 原版事件 → Lisp | payload 字段（原版 → Lisp） | handler result | 固定基线 |
|---|---|---|---|
| `tool_execution_start` → `:tool-execution-start` | `toolCallId` → `:tool-call-id`; `toolName` → `:tool-name`; `args` → `:arguments` | 无 | `packages/coding-agent/src/core/extensions/types.ts:761-767` |
| `tool_execution_update` → `:tool-execution-update` | 同上；`partialResult` → `:partial-result` | 无 | `packages/coding-agent/src/core/extensions/types.ts:769-776` |
| `tool_execution_end` → `:tool-execution-end` | `toolCallId`, `toolName`; `result` → `:result`; `isError` → `:error-p` | 无 | `packages/coding-agent/src/core/extensions/types.ts:778-785` |
| `model_select` → `:model-select` | `model` → `:model`; `previousModel` → `:previous-model`; `source` → `:source` (`:set/:cycle/:restore`) | 无 | `packages/coding-agent/src/core/extensions/types.ts:791-799` |
| `thinking_level_select` → `:thinking-level-select` | `level` → `:level`; `previousLevel` → `:previous-level` | 无 | `packages/coding-agent/src/core/extensions/types.ts:801-806` |

这些只增加观察事件；不会修改 provider 或工具执行语义。工具拦截/结果改写继续
走既有 `:tool-call-before` / `:tool-call-after`，其 reference 对应分别为
`packages/coding-agent/src/core/extensions/types.ts:853-912,1071-1075` 和
`:914-973,1085-1090`。

审计提交还有下列 extension events，但本提案明确不新增：

| 不新增事件 | 原因 | 固定基线 |
|---|---|---|
| `project_trust` | 安全模型与本 Wave 无关 | `packages/coding-agent/src/core/extensions/types.ts:519-541` |
| `resources_discover` | resource/skill 生态不在本次限定解冻 | `packages/coding-agent/src/core/extensions/types.ts:543-555` |
| `before_provider_request`, `before_provider_headers`, `after_provider_response` | provider 层继续冻结 | `packages/coding-agent/src/core/extensions/types.ts:675-696` |
| `user_bash` | 工具语义继续冻结 | `packages/coding-agent/src/core/extensions/types.ts:808-821,1077-1083` |

## 4. RPC extension UI surface

### 4.1 Lisp context 函数

现有函数签名不变：

```lisp
(extension-context-notify context message &key (level :info))
```

新增且仅新增以下公共函数：

```lisp
(extension-context-select
 context title options &key signal timeout-ms)
  ; => string | nil

(extension-context-confirm
 context title message &key signal timeout-ms)
  ; => boolean

(extension-context-input
 context title &key placeholder signal timeout-ms)
  ; => string | nil

(extension-context-editor
 context title &key prefill)
  ; => string | nil

(extension-context-set-status context key text)
  ; text=nil clears

(extension-context-set-widget
 context key lines &key (placement :above-editor))
  ; lines is list/vector of strings or nil

(extension-context-set-title context title)

(extension-context-set-editor-text context text)
```

原版 dialog 签名与 options：
`packages/coding-agent/src/core/extensions/types.ts:95-100,131-142`；status/widget/
title/editor surface：`:147-170,192-193,215-222`。

不新增 `onTerminalInput`、working indicator、custom component、footer/header、
paste、autocomplete、custom editor、theme 或 tool-expansion API；它们不在
RPC extension UI wire union 内，且会越过 TUI 冻结。

### 4.2 RPC JSONL wire

wire 字段名和值逐字保持参考，不 Lisp 化：

下表中的 `rpc-types.ts` 与 `rpc-mode.ts` 分别指
`packages/coding-agent/src/modes/rpc/rpc-types.ts` 和
`packages/coding-agent/src/modes/rpc/rpc-mode.ts`。

| Lisp 调用 | stdout request | stdin response/default | 固定基线 |
|---|---|---|---|
| `extension-context-select` | `{"type":"extension_ui_request","id", "method":"select","title","options","timeout"?}` | `{"type":"extension_ui_response","id","value"}` 或 `cancelled:true`→`nil` | `rpc-types.ts:238-240,280-283`; `rpc-mode.ts:135-139` |
| `extension-context-confirm` | method `confirm`, `title`, `message`, `timeout?` | `confirmed:boolean`；cancel→`nil` | `rpc-types.ts:240,280-283`; `rpc-mode.ts:141-144` |
| `extension-context-input` | method `input`, `title`, `placeholder?`, `timeout?` | `value` 或 cancel→`nil` | `rpc-types.ts:241-248,280-283`; `rpc-mode.ts:146-149` |
| `extension-context-editor` | method `editor`, `title`, `prefill?` | `value` 或 cancel→`nil` | `rpc-types.ts:249,280-283`; `rpc-mode.ts:253-269` |
| `extension-context-notify` | method `notify`, `message`, `notifyType?` | fire-and-forget | `rpc-types.ts:250-256`; `rpc-mode.ts:151-160` |
| `extension-context-set-status` | method `setStatus`, `statusKey`, `statusText` | fire-and-forget | `rpc-types.ts:257-263`; `rpc-mode.ts:167-176` |
| `extension-context-set-widget` | method `setWidget`, `widgetKey`, `widgetLines`, `widgetPlacement?` | fire-and-forget | `rpc-types.ts:264-271`; `rpc-mode.ts:194-207` |
| `extension-context-set-title` | method `setTitle`, `title` | fire-and-forget | `rpc-types.ts:272`; `rpc-mode.ts:217-225` |
| `extension-context-set-editor-text` | method `set_editor_text`, `text` | fire-and-forget | `rpc-types.ts:273`; `rpc-mode.ts:237-245` |

所有 request `id` 都唯一。dialog request 在 response、timeout 或 signal abort
后只完成一次并移除 pending entry；参考状态机：
`packages/coding-agent/src/modes/rpc/rpc-mode.ts:89-130`。RPC bind 使用该
context 的出处为同文件 `:312-320`。

EOF/close 时所有 pending dialog 必须以各自默认值完成，不悬挂线程；迟到或
未知 `extension_ui_response.id` 返回 RPC error，不影响其他 request。

### 4.3 分层

- `cadr-agent` 只持有 UI callback protocol，不依赖 `cadr-cli` 或 `cadr-tui`。
- `cadr-cli` 的 RPC bridge 负责 request id、pending map、timeout/signal、
  JSONL request/response。
- `cadr-cli` 的 TUI glue 只能组合现有 `cadr-tui` 组件与 overlay API。若任何
  方法无法在不改 `cadr-tui` 的前提下实现，立即再次 blocked，不准顺手改组件。
- print/JSON 无 dialog-capable UI：select/input/editor 返回 `nil`，confirm
  返回 `nil`；fire-and-forget 方法不写 stdout，避免污染协议。

## 5. 向后兼容门禁

实现前先在 `test/cadr-agent/extensions-test.lisp` 增加一个失败测试：

`LEGACY-EXTENSION-SOURCE-REMAINS-COMPATIBLE-AFTER-WAVE-2-API-EXPANSION`。

测试加载一份不修改的旧 API fixture，同时注册：

- `define-tool`, `define-command`, `define-prompt-template`;
- `define-event-hook` 的四个旧事件；
- 旧 context accessor 与 notify/compact/reload；
- replacement、append、tool block/reason、priority 与 handler error isolation。

它必须证明：

1. 原 fixture 无修改即可 compile/load；
2. 四个旧 event 的 payload、顺序、链式 replacement、append 和 block 结果
   与开工提交 `14fc6eefeb7e9329a2743ba385cf913060240de2` 完全相同；
3. `define-event-hook` macro lambda list 仍为
   `(event &key (priority 0) handler)`；
4. 所有旧 export 仍为 external symbol；只允许增加本文列出的 export；
5. 旧 event 返回 plist 仍报原错误，新增 event 返回
   `extension-hook-result` 也报 event-specific 类型错误，防止两个 contract
   静默串线。

同时为每个新增事件至少覆盖 payload、合法结果、非法字段/类型、handler
failure isolation；RPC UI 用进程级 JSONL 测试覆盖 response、cancel、
timeout、signal、unknown id、EOF cleanup 和 stdout cleanliness。

## 6. 本 goal 允许变更与继续冻结

扩展相关条目从原冻结表移入本 goal 允许变更：

| 允许变更路径/文本 | 仅允许的变化 |
|---|---|
| `src/cadr-agent/extensions.lisp` | 本文事件、payload、cancel signal 与 UI callback protocol |
| `src/cadr-agent/package.lisp` | 仅新增本文列出的 public symbols；旧 export 不删不改 |
| `test/cadr-agent/extensions-test.lisp` | 新事件与旧 API 兼容门禁 |
| `src/cadr-cli/extensions.lisp` | 仅 UI bridge glue |
| `test/cadr-cli/extensions-test.lisp` | bridge 单元测试 |
| `src/cadr-cli/modes/rpc/` | RPC extension UI wire 与进程测试 |
| `cadr-agent.asd`, `cadr-cli.asd` | 仅新增模块/测试装配确有需要时 |

收尾时上述扩大后的 API 重新冻结，记录逐路径 Git object ID、完整 export 文本
SHA-256、宏展开/签名测试和 wire fixture SHA-256，并更新
`docs/architecture.md`。其后恢复“发布即稳定”。

继续冻结且必须保持开工 object ID：

| 路径 | object ID |
|---|---|
| `src/cadr-ai` | `e9c5affef2e36db4cdf6f7fc37a20534cd1a661a` |
| `test/cadr-ai` | `e984d714c6e53cb34d89c495939f9d2b3d975fd8` |
| `cadr-ai.asd` | `f99e2708e9ff7e3465824c7ea04bedce9512724c` |
| `src/cadr-tui` | `1a5ba07b17cd3b0c55c8a1ec35a79d1fafda0950` |
| `test/cadr-tui` | `947e63cc73b259ea2b18bfc281b5229a13f9a5d0` |
| `cadr-tui.asd` | `c09f6172c1c186f15c726b2c04b7ea65a4f4214c` |
| `src/cadr-agent/tool.lisp` | `42093b6062ab16cde78f72cb87a878057b7dd131` |
| `test/cadr-agent/tool-loop-test.lisp` | `f44cd198c1fbfab8b7402f457d1ea2a848a9aa74` |
| `src/cadr-cli/tools` | `0ad21371b8ad2e759dacb26202383965a68d5493` |
| `test/cadr-cli/file-tools-test.lisp` | `206bb0416ff53abba10378a873eeffb698162327` |
| `test/cadr-cli/search-tools-test.lisp` | `5ca50cd12f4b1442891c12ee9fa231b24df07a6c` |
| `test/cadr-cli/bash-test.lisp` | `3475ab2a3760afa06928d8748a44e1514d1ac461` |
| `test/cadr-cli/execution-policy-test.lisp` | `19df8cfbae90aa3d2afb44eb01c81939de90a2cc` |

## 7. 获批的 Wave 2 runtime actions

用户已将以下原版 extension actions 一并限定解冻；约束与 lifecycle/UI
扩充相同：只增加审计提交已有能力，不改变现有宏签名和现有事件语义。

| 获批 action | 直接依赖的目标文件 | 固定基线 |
|---|---|---|
| runtime `registerProvider` | `agent-session-dynamic-provider.test.ts`, `suite/agent-session-runtime.test.ts`, regressions `2860` | `packages/coding-agent/src/core/extensions/types.ts:1344-1416` |
| runtime `registerTool` | `agent-session-dynamic-tools.test.ts`, `suite/agent-session-runtime.test.ts` | `packages/coding-agent/src/core/extensions/types.ts:1233-1240` |
| `sendMessage` / `sendUserMessage` | `suite/agent-session-queue.test.ts`, regressions `5943` | `packages/coding-agent/src/core/extensions/types.ts:1281-1298` |
| `setSessionName` | regressions `3686`, `5996` | `packages/coding-agent/src/core/extensions/types.ts:1303-1311` |

Lisp 新增映射固定为：

```lisp
(define-provider definition &key models)

(extension-context-register-provider context definition &key models)
(extension-context-register-tool context tool)

(extension-context-send-message
 context message &key (trigger-turn-p nil) deliver-as)

(extension-context-send-user-message context content &key deliver-as)
(extension-context-set-session-name context name)
```

`definition` 复用 `cadr-ai:provider-definition`，`models` 复用
`cadr-ai:model-metadata`，`tool` 复用 `cadr-ai:tool`；不复制 provider/tool
domain type。`define-provider` 只覆盖原版 load-time `registerProvider`，
context 函数覆盖 callback 内立即生效的注册。现有 `define-tool` 继续只允许
load 期间调用，不改变其既有语义。

`deliver-as` 精确映射为 `:steer`、`:follow-up`、`:next-turn`；其中
`sendUserMessage` 只接受前两者。缺省时，idle 直接启动 turn，streaming 时
必须显式给出投递队列。session name 在写入和事件发出前移除 CR/LF。

provider 注册保存在每个 extension host 的 runtime overlay，不改
`cadr-ai` 的全局 registry。它可覆盖当前 active model 或追加当前 session
可见 model；extension reload 后 overlay 随 bundle snapshot 一并替换。
若实现该能力需要修改 `src/cadr-ai` 任一冻结 object ID，必须立即 blocked，
不得实施该修改。

## 8. 用户裁决

用户已逐项确认第 1–7 项；第 8 项裁决为第 7 节四组 action 全部限定解冻。
向后兼容门禁必须先于生产实现落地，Part B→C→D 顺序不变。goal 7 收尾时，
扩大后的 extension API 重新冻结并记录新 object/export/wire hashes。

## 9. 收尾重冻

重冻对象：

| 路径 | Git object ID |
|---|---|
| `src/cadr-agent/extensions.lisp` | `58539b2849fcf6b6756657d46f94ac09a3c639fc` |
| `src/cadr-agent/package.lisp` | `15525d7cc8bd860d66b3bbaf0f1ab56174464d39` |
| `test/cadr-agent/extensions-test.lisp` | `c097b312567386421da5cdae0f1c13d039b21bde` |
| `test/cadr-agent/extensions-wave2-test.lisp` | `c6cfa3544a3f74b44585a9c62f25af7c015d9afa` |
| `src/cadr-cli/extensions.lisp` | `4e94df55ed27b96c43313d24069225c015b99c17` |
| `test/cadr-cli/extensions-test.lisp` | `3fa8a1f9eb8a6b519b27f3004290be7551171288` |
| `src/cadr-cli/modes/rpc/jsonl.lisp` | `5839f4ae5754d91c773a2bacb5a5f61d994fd85a` |
| `src/cadr-cli/modes/rpc/ui.lisp` | `c5f676784c137dac0a5604f660acbb71415bba48` |
| `src/cadr-cli/modes/rpc/mode.lisp` | `9e0100edd769295d4a9871cfc7ac7a77f5dd3f11` |
| `test/cadr-cli/rpc-test.lisp` | `5aa90e7fa51a093a6aa6d0c8dc098d8d2d41ff7b` |
| `cadr-agent.asd` | `189df27ae5b63f6619e53e981ad7c4c77a68868b` |
| `cadr-cli.asd` | `dc112807eea502182a1518f5582f6d47348a6ad2` |

从 `#:define-tool` 到 `#:make-extension-hook-result`（含两端）的完整 export
文本 SHA-256：
`cc8e7d180b5007cbf4daa66ff904f8c0714992df646211c232135500efd936e7`。

兼容 fixture SHA-256：
`e2548662d773edfa21ecfa3b126b2209404a2b27385e6cd48e1f145a41747442`
（`test/fixtures/extensions/legacy-wave2-api.lisp`）。

RPC wire/process fixture SHA-256：
`6dc3a25271080a59c3380704044c435a0a20a972c5ba19f32cae2acee2649b10`
（`test/fixtures/rpc-process-client.py`）；UI extension fixture SHA-256：
`c1148870a539dd4a24001da74d17f668b6092bf55d41d845319d5439e3df9486`。

宏签名与旧事件语义由
`LEGACY-EXTENSION-SOURCE-REMAINS-COMPATIBLE-AFTER-WAVE-2-API-EXPANSION`
持续冻结。此后恢复“发布即稳定”；任何进一步扩面先进入
`docs/open-questions.md` 等人工裁决。
