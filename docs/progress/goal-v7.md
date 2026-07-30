# GOAL v7: Wave 2 — Part A 只读预审

## 状态

Part A 已完成测试清单、目标模块映射、session v3 磁盘规格、队列语义和冻结区
基线审计。尚未修改生产代码、测试或 parity 状态，Part B 尚未开始。

用户已裁决采用“限定解冻扩展 API”路线，但要求实现前先提交完整提案并逐项
确认。提案见
[`docs/proposals/goal-v7-extension-api.md`](../proposals/goal-v7-extension-api.md)；
当前状态仍为 blocked，未获逐项确认前不写实现。

提案复核还发现 46 个 session 目标中的 runtime provider/tool registration、
`sendMessage`/`sendUserMessage` 和 `setSessionName` 不属于本次获准提案的
lifecycle/UI 范围；它们已在提案第 7 节单列，禁止夹带。

固定参考：

- 审计提交：`71efc6f0c1909874ec8c944637a9ae7fc0e2d508`
- 审计 checkout：`/tmp/cadr-parity-71efc6f0`
- 开工提交：`14fc6eefeb7e9329a2743ba385cf913060240de2`
- 开工测试基线：`1332/1332`

## 冻结区开工基线

以下 object ID 在收尾时必须逐项一致；其中扩展 API 还额外固定了导出块文本
的 SHA-256。

| 冻结路径 | 开工 object ID |
|---|---|
| `src/cadr-ai` | `e9c5affef2e36db4cdf6f7fc37a20534cd1a661a` |
| `test/cadr-ai` | `e984d714c6e53cb34d89c495939f9d2b3d975fd8` |
| `cadr-ai.asd` | `f99e2708e9ff7e3465824c7ea04bedce9512724c` |
| `src/cadr-tui` | `1a5ba07b17cd3b0c55c8a1ec35a79d1fafda0950` |
| `test/cadr-tui` | `947e63cc73b259ea2b18bfc281b5229a13f9a5d0` |
| `cadr-tui.asd` | `c09f6172c1c186f15c726b2c04b7ea65a4f4214c` |
| `src/cadr-agent/extensions.lisp` | `5b882c26c48287f28ff31137ad9875ce28fe5f0f` |
| `test/cadr-agent/extensions-test.lisp` | `2053ef06e0bc65b03744ea024c4407eac0817468` |
| `src/cadr-cli/extensions.lisp` | `4e94df55ed27b96c43313d24069225c015b99c17` |
| `test/cadr-cli/extensions-test.lisp` | `3fa8a1f9eb8a6b519b27f3004290be7551171288` |
| `src/cadr-agent/tool.lisp` | `42093b6062ab16cde78f72cb87a878057b7dd131` |
| `test/cadr-agent/tool-loop-test.lisp` | `f44cd198c1fbfab8b7402f457d1ea2a848a9aa74` |
| `src/cadr-cli/tools` | `0ad21371b8ad2e759dacb26202383965a68d5493` |
| `test/cadr-cli/file-tools-test.lisp` | `206bb0416ff53abba10378a873eeffb698162327` |
| `test/cadr-cli/search-tools-test.lisp` | `5ca50cd12f4b1442891c12ee9fa231b24df07a6c` |
| `test/cadr-cli/bash-test.lisp` | `3475ab2a3760afa06928d8748a44e1514d1ac461` |
| `test/cadr-cli/execution-policy-test.lisp` | `19df8cfbae90aa3d2afb44eb01c81939de90a2cc` |

扩展导出块 SHA-256：
`65bdec58440ddfaaf1aa80b62c069f91a0713251b7601911f2ee2747d1586e6d`。

## Agent 包：18 个 M 文件

每个文件均有 Common Lisp 对应面；Part A 不提出 N/A。

| 原版测试文件 | cadr 目标模块 | 必须移植的语义 |
|---|---|---|
| `packages/agent/test/agent-loop.test.ts` | `src/cadr-agent/agent.lisp`, `queue.lisp`, `harness.lisp` | event spine、工具批次顺序、steering 注入、next-turn 与终止 |
| `packages/agent/test/agent.test.ts` | `src/cadr-agent/agent.lisp`, `queue.lisp` | 生命周期、异步订阅、busy guard、abort、continue、两类队列 |
| `packages/agent/test/e2e.test.ts` | `src/cadr-agent/harness.lisp` | faux provider 的 prompt/tool/abort/context/thinking/continue 闭环 |
| `packages/agent/test/harness/agent-harness-stream.test.ts` | `src/cadr-agent/harness.lisp` | stream options 与 provider hook 快照 |
| `packages/agent/test/harness/agent-harness.test.ts` | `src/cadr-agent/harness.lisp`, `queue.lisp`, `compaction.lisp` | 队列、事件、savepoint、retry、compaction、hook 错误与监听顺序 |
| `packages/agent/test/harness/compaction.test.ts` | `src/cadr-agent/compaction.lisp`, `session.lisp` | 阈值、切点、summary、split turn、usage 与失败恢复 |
| `packages/agent/test/harness/nodejs-env.test.ts` | `src/cadr-agent/execution-env.lisp` | 文件系统与 shell 执行抽象的 Lisp 等价实现 |
| `packages/agent/test/harness/prompt-templates.test.ts` | `src/cadr-agent/prompt-templates.lisp` | 模板发现、变量展开、错误与排序 |
| `packages/agent/test/harness/repo.test.ts` | `src/cadr-agent/repo.lisp` | repo CRUD、分支/树遍历与一致性 |
| `packages/agent/test/harness/resource-formatting.test.ts` | `src/cadr-agent/resource-formatting.lisp` | 资源格式化与边界 |
| `packages/agent/test/harness/session.test.ts` | `src/cadr-agent/session.lisp` | JSONL session、树、迁移、恢复与继续 |
| `packages/agent/test/harness/skills.test.ts` | `src/cadr-agent/skills.lisp` | Lisp 扩展生态下的 skill 发现与加载 |
| `packages/agent/test/harness/sqlite-migrations.test.ts` | `src/cadr-agent/storage/sqlite.lisp` | schema 迁移、幂等与失败原子性 |
| `packages/agent/test/harness/sqlite-node.test.ts` | `src/cadr-agent/storage/sqlite.lisp` | SQLite 节点存取与重开一致性 |
| `packages/agent/test/harness/storage.test.ts` | `src/cadr-agent/storage.lisp` | storage contract 与实现替换 |
| `packages/agent/test/harness/system-prompt.test.ts` | `src/cadr-agent/system-prompt.lisp` | prompt 组装、资源注入与稳定顺序 |
| `packages/agent/test/harness/tools.test.ts` | `src/cadr-agent/harness.lisp` | harness 的工具注册/调用编排；工具自身语义冻结 |
| `packages/agent/test/harness/truncate.test.ts` | `src/cadr-agent/truncate.lisp` | UTF-8 byte/line 截断、边界与 metadata |

## Coding-agent session/queue：46 个 M 文件

| 原版测试文件 | cadr 目标模块 | 备注 |
|---|---|---|
| `packages/coding-agent/test/agent-session-auto-compaction-queue.test.ts` | `queue.lisp`, `harness.lisp`, `compaction.lisp` | compaction 前后队列时序 |
| `packages/coding-agent/test/agent-session-branching.test.ts` | `session.lisp`, `harness.lisp` | 分支 session |
| `packages/coding-agent/test/agent-session-compaction.test.ts` | `compaction.lisp`, `session.lisp` | compaction 事件与持久化 |
| `packages/coding-agent/test/agent-session-concurrent.test.ts` | `queue.lisp`, `harness.lisp` | 并发事件串行化与 settlement |
| `packages/coding-agent/test/agent-session-dynamic-provider.test.ts` | `harness.lisp` | provider 配置 savepoint；provider 层冻结；依赖 `session_start` 扩展事件 |
| `packages/coding-agent/test/agent-session-dynamic-tools.test.ts` | `harness.lisp` | 工具 registry 快照；工具语义冻结；依赖 `session_start` 扩展事件 |
| `packages/coding-agent/test/agent-session-retry.test.ts` | `harness.lisp`, `queue.lisp` | retry 与 prompt completion |
| `packages/coding-agent/test/agent-session-runtime-events.test.ts` | `harness.lisp`, `session.lisp`, extension lifecycle | **冻结冲突** |
| `packages/coding-agent/test/agent-session-stats.test.ts` | `session.lisp`, `harness.lisp` | usage/session stats |
| `packages/coding-agent/test/agent-session-tree-navigation.test.ts` | `session.lisp`, `compaction.lisp` | tree navigation 与 branch summary |
| `packages/coding-agent/test/branch-summary-extensions.test.ts` | `compaction.lisp`, extension lifecycle | **冻结冲突：`session_before_tree`** |
| `packages/coding-agent/test/compaction-extensions-example.test.ts` | `compaction.lisp`, extension lifecycle | **冻结冲突：compaction hook** |
| `packages/coding-agent/test/compaction-extensions.test.ts` | `compaction.lisp`, extension lifecycle | **冻结冲突：compaction hook** |
| `packages/coding-agent/test/compaction-serialization.test.ts` | `compaction.lisp`, `session.lisp` | compaction 并发互斥 |
| `packages/coding-agent/test/compaction-summary-reasoning.test.ts` | `compaction.lisp` | reasoning summary |
| `packages/coding-agent/test/compaction.test.ts` | `compaction.lisp`, `session.lisp` | context 选择与摘要格式 |
| `packages/coding-agent/test/sdk-session-manager.test.ts` | `session.lisp`, `harness.lisp` | session manager facade |
| `packages/coding-agent/test/session-cwd.test.ts` | `session.lisp`, CLI session selection | cwd 过滤 |
| `packages/coding-agent/test/session-file-invalid.test.ts` | `session.lisp`, CLI errors | 显式坏文件必须保留并报错 |
| `packages/coding-agent/test/session-id-readonly.test.ts` | `session.lisp`, CLI args | readonly session id |
| `packages/coding-agent/test/session-info-modified-timestamp.test.ts` | `session.lisp` | session 列表时间 |
| `packages/coding-agent/test/session-manager/build-context.test.ts` | `session.lisp` | 从树构造 context |
| `packages/coding-agent/test/session-manager/custom-session-id.test.ts` | `session.lisp` | 自定义 ID |
| `packages/coding-agent/test/session-manager/file-operations.test.ts` | `session.lisp`, `repo.lisp` | 创建、加载、追加、重写 |
| `packages/coding-agent/test/session-manager/labels.test.ts` | `session.lisp` | label 节点 |
| `packages/coding-agent/test/session-manager/migration.test.ts` | `session.lisp` | v1/v2→v3 无损迁移 |
| `packages/coding-agent/test/session-manager/save-entry.test.ts` | `session.lisp` | custom entry |
| `packages/coding-agent/test/session-manager/tree-traversal.test.ts` | `session.lisp` | parent tree 与 leaf |
| `packages/coding-agent/test/startup-session-name.test.ts` | `session.lisp`, CLI startup | session name |
| `packages/coding-agent/test/suite/agent-session-bash-persistence.test.ts` | `harness.lisp`, `session.lisp` | bash message 持久化；bash 语义冻结 |
| `packages/coding-agent/test/suite/agent-session-compaction.test.ts` | `harness.lisp`, `compaction.lisp` | harness compaction 闭环 |
| `packages/coding-agent/test/suite/agent-session-model-extension.test.ts` | `harness.lisp`, extension lifecycle | **冻结冲突；provider/tool 语义继续冻结** |
| `packages/coding-agent/test/suite/agent-session-prompt.test.ts` | `harness.lisp`, `queue.lisp` | prompt 生命周期 |
| `packages/coding-agent/test/suite/agent-session-queue.test.ts` | `queue.lisp`, `harness.lisp` | steering/follow-up 精确语义 |
| `packages/coding-agent/test/suite/agent-session-retry-events.test.ts` | `harness.lisp`, `queue.lisp`, extension events | settlement 顺序；部分为**冻结冲突** |
| `packages/coding-agent/test/suite/agent-session-runtime.test.ts` | `harness.lisp`, `session.lisp` | runtime 绑定与关闭 |
| `packages/coding-agent/test/suite/regressions/1717-2113-agent-session-event-settlement.test.ts` | `harness.lisp`, extension events | **冻结冲突：`message_end`/`tool_call`** |
| `packages/coding-agent/test/suite/regressions/2860-replaced-session-context.test.ts` | `harness.lisp`, `session.lisp`, extension lifecycle | **冻结冲突：start/shutdown** |
| `packages/coding-agent/test/suite/regressions/3686-session-name-event.test.ts` | `session.lisp`, extension/public events | **冻结冲突：`session_info_changed`** |
| `packages/coding-agent/test/suite/regressions/5217-compaction-reason.test.ts` | `compaction.lisp` | compaction reason |
| `packages/coding-agent/test/suite/regressions/5943-session-start-notify.test.ts` | extension lifecycle | **冻结冲突：`session_start`** |
| `packages/coding-agent/test/suite/regressions/5996-session-name-newlines.test.ts` | `session.lisp`, extension/public events | 名称清洗；部分为**冻结冲突** |
| `packages/coding-agent/test/suite/regressions/6324-branch-summary-ambient-auth.test.ts` | `compaction.lisp`, `harness.lisp` | ambient auth 透传；provider 层冻结 |
| `packages/coding-agent/test/suite/regressions/6647-compaction-retries-transient-stream-drop.test.ts` | `compaction.lisp`, `harness.lisp` | transient stream retry |
| `packages/coding-agent/test/suite/regressions/pre-prompt-compaction-no-continue.test.ts` | `compaction.lisp`, `queue.lisp` | pre-prompt compaction 不误 continue |
| `packages/coding-agent/test/suite/regressions/startup-session-rebind-duplicate-subscription.test.ts` | `harness.lisp`, `session.lisp`, extension lifecycle | subscription 去重；部分为**冻结冲突** |

## Part C：print/JSON 目标文件

`CODING-CLI-SDK` 是混合大类；本 goal 只纳入与模式选择、一次性输入、输出洁净
和进程关闭直接相关的文件：

| 原版测试文件 | cadr 目标模块 | 必须移植的语义 |
|---|---|---|
| `packages/coding-agent/test/args.test.ts` | `src/cadr-cli/args.lisp` | `--mode`、`--print`、`--no-tui` 解析与冲突 |
| `packages/coding-agent/test/initial-message.test.ts` | `src/cadr-cli/initial-message.lisp` | argv prompt 与 stdin 合并 |
| `packages/coding-agent/test/print-mode.test.ts` | `src/cadr-cli/modes/print.lisp`, JSON mode | text/JSON 输出、错误退出、shutdown |
| `packages/coding-agent/test/stdout-cleanliness.test.ts` | CLI entry/modes | stdout 只承载协议或结果 |
| `packages/coding-agent/test/suite/regressions/5080-signal-shutdown-extension-cleanup.test.ts` | CLI close, extension lifecycle | **冻结冲突：`session_shutdown`** |
| `packages/coding-agent/test/suite/regressions/5724-sigterm-signal-exit.test.ts` | CLI signal handling | SIGTERM 退出语义 |

其余 `CODING-CLI-SDK` M 文件不因标签相同而提前解冻；它们仍属于后续 Wave。
JSON 模式没有独立 parity-map 标签，以 `print-mode.test.ts` 的 JSON cases 和
本 goal 新增的真实进程 JSONL 测试共同验收。

模式优先级的固定基线是：

1. 显式 `--mode rpc`；
2. 显式 `--mode json`；
3. 显式 `--print`；
4. stdin 或 stdout 任一非 TTY 时自动 print；
5. 其余进入 interactive。

`--no-tui` 仅作为 cadr 明确保留、且必须显式请求的行 REPL 差异，不参与非
TTY 自动回落。

## Part D：RPC 的 6 个 M 文件

| 原版测试文件 | cadr 目标模块 | 必须移植的语义 |
|---|---|---|
| `packages/coding-agent/test/rpc-client-clone.test.ts` | `src/cadr-cli/modes/rpc/client.lisp` | clone 与客户端 state |
| `packages/coding-agent/test/rpc-client-process-exit.test.ts` | RPC client/entry | 子进程退出与 pending request 收敛 |
| `packages/coding-agent/test/rpc-jsonl.test.ts` | `src/cadr-cli/modes/rpc/jsonl.lisp` | LF/CRLF/U+2028/U+2029/无末尾 LF |
| `packages/coding-agent/test/rpc-prompt-response-semantics.test.ts` | `src/cadr-cli/modes/rpc/mode.lisp` | prompt preflight、单次 response、错误 |
| `packages/coding-agent/test/rpc.test.ts` | `src/cadr-cli/modes/rpc/` | command、event、session 与关闭闭环 |
| `packages/coding-agent/test/suite/regressions/5868-rpc-unknown-command-id.test.ts` | RPC dispatcher | unknown command 保留 request id |

参考 command union 为：

`prompt`, `steer`, `follow_up`, `abort`, `new_session`, `get_state`,
`set_model`, `cycle_model`, `get_available_models`, `set_thinking_level`,
`cycle_thinking_level`, `get_available_thinking_levels`,
`set_steering_mode`, `set_follow_up_mode`, `compact`,
`set_auto_compaction`, `set_auto_retry`, `abort_retry`, `bash`,
`abort_bash`, `get_session_stats`, `export_html`, `switch_session`, `fork`,
`clone`, `get_fork_messages`, `get_entries`, `get_tree`,
`get_last_assistant_text`, `set_session_name`, `get_messages`,
`get_commands`。

response 固定为
`{id?,type:"response",command,success,data?}` 或
`{id?,type:"response",command,success:false,error}`；session events 原样逐行
转发。输入 EOF 正常关闭；解析错误的 `command` 为 `parse`；未知命令保留
`id`。JSONL 只以 LF 分帧、兼容 CRLF、不把 U+2028/U+2029 当分隔符，并处理
末尾无 LF 的最后一帧。

## Session v3 精确磁盘规格

### Header

首个有效 JSONL record：

```json
{
  "type": "session",
  "version": 3,
  "id": "session-id",
  "timestamp": "ISO-8601 string",
  "cwd": "/absolute/path",
  "parentSession": "optional parent session file"
}
```

`parentSession` 可省略。参考实现发现 session 时流式扫描最多 1 MiB，跳过空行
和坏 JSON，按 cwd 过滤；显式传入的非空坏文件保留原样并报错，空文件才允许
初始化。

### Entry envelope 与类型

所有节点共有：

```json
{"type":"entry-type","id":"8-hex","parentId":"optional-id","timestamp":"ISO-8601 string"}
```

ID 是做过碰撞检查的 8 位十六进制字符串。条目按实际 append 顺序写入，树由
`parentId` 表示；reload 后当前 leaf 是物理上最后一个有效 entry。

| `type` | envelope 外字段 |
|---|---|
| `message` | `message` |
| `thinking_level_change` | `thinkingLevel` |
| `model_change` | `provider`, `modelId` |
| `compaction` | `summary`, `firstKeptEntryId`, `tokensBefore`, `details?`, `usage?`, `fromHook?` |
| `branch_summary` | `fromId`, `summary`, `details?`, `usage?`, `fromHook?` |
| `custom` | `customType`, `data?` |
| `custom_message` | `customType`, `content`, `details?`, `display` |
| `label` | `targetId`, `label?` |
| `session_info` | `name?` |

参考 coding-agent manager 在出现首个 assistant entry 前不创建文件；首次落盘
用 exclusive create 写 header 和缓冲 entries，之后 append。

### 读取、崩溃尾与迁移

- blank 或 malformed JSONL record 被跳过，包括崩溃留下的坏尾；首个成功
  parse 的 record 必须是含字符串 `id` 的 session header。
- v1→v2 为既有 entry 补 `id`/`parentId` 链，并把 compaction 的
  `firstKeptEntryIndex` 转为 `firstKeptEntryId`。
- v2→v3 把 message role `hookMessage` 重命名为 `custom`。
- 迁移直接改 parsed object，因此未知 envelope 字段必须保留。
- 原版 `_rewriteFile` 是截断重写；本 goal 明确要求 cadr 继续使用更强的同目录
  临时文件 + rename 原子替换。
- 对真实 `~/.cadr/sessions/` 只允许 dry-run/备份路径；所有迁移测试必须使用
  临时目录。开工时该目录有 10 个 JSONL 文件，Part A 未读写其内容。

### cadr 当前 v2 的差异

| 当前 cadr v2 | 参考 v3 |
|---|---|
| header `version:2` | `version:3` |
| header timestamp 为整数毫秒 | ISO 字符串 |
| 无 `parentSession` | 可选 `parentSession` |
| 只支持 `message`、`compaction` | 支持上表全部 9 类 entry |
| compaction 使用非参考字段 `sourceIds` | `details?`, `usage?`, `fromHook?` |
| message 内部使用 `type` 与 snake_case | 原版 AgentMessage role/camelCase |
| 严格拒绝中间坏 JSON；仅忽略无换行坏尾 | 跳过 blank/malformed record |
| create 时立即写 header | 首个 assistant entry 后才落盘 |
| 仅 v1→v2，且只迁 message | v1→v2→v3 |
| 重复或 dangling parent 直接拒绝 | 以 append log + parent tree 恢复 |
| 已有原子 temp+rename | 继续保留该更强纪律 |

## Queue 精确语义

- steering 和 follow-up 各自是 FIFO；默认 mode 均为 `one-at-a-time`，另有
  `all`。
- steering 在一次 turn 开始时以及每个 assistant/tool batch 结束后轮询；
  当前 batch 的全部 tool call 完成后才注入，不抢占半个 batch。
- follow-up 只在 agent 本应停止时 drain，并启动下一次 inner run。
- `one-at-a-time` 每次 drain 一个；`all` 原子取得当时队列快照。
- agent busy 时 `prompt`/`continue` 报错；`steer`/`followUp` 允许入队。
- harness abort 捕获并清空 steer/follow-up 队列、终止当前 run、保留 next-turn
  queue，并发出 abort 与 queue-update。
- queue-update 必须携带 `{steer, followUp}` 两个队列的完整快照。
- cadr 当前只有 busy guard 与 abort flag，没有双队列、mode、注入时机或
  wait-for-idle。

## N/A 候选

本轮不提出 N/A。`nodejs-env`、SQLite、prompt/resource/skill 等测试都有明确
的 Common Lisp 等价实现，不属于“TS 运行时独有”。扩展生命周期和 RPC UI
bridge 同样是原版跨平台产品语义，不能诚实地标成 N/A。

## 进入 Part B 前的原始硬阻塞

cadr 当前公开 hook 白名单只有：

```lisp
(:turn-start :turn-end :tool-call-before :tool-call-after)
```

对应 `src/cadr-agent/extensions.lisp:349-351`；宏和公开 context accessor 位于
`src/cadr-agent/extensions.lisp:435` 与 `src/cadr-agent/package.lisp:35-45`，
均被 goal7 绝对冻结。

但目标文件直接要求：

- `session_start`, `session_shutdown`, `session_before_switch`,
  `session_before_fork`, `session_before_tree`;
- `session_info_changed`, `message_end`, `tool_call`, `agent_settled`;
- RPC `createExtensionUIContext` 及 `extension_ui_request/response`，覆盖
  select/confirm/input/editor/notify/status/widget/title/editor text。

参考证据包括：

- `packages/coding-agent/src/core/agent-session-runtime.ts:138-172`
- `packages/coding-agent/src/core/agent-session.ts:584-585,2875,2950-2953`
- `packages/coding-agent/src/core/extensions/types.ts:563-640,724-757,854`
- `packages/coding-agent/src/modes/rpc/rpc-mode.ts:128-319`
- `packages/coding-agent/src/modes/rpc/rpc-types.ts:239-273`

这不是 TS 运行时差异，也不能在不改变 hook 白名单、事件 payload 和 context
surface 的情况下完成。可执行的两条路只有：

1. 仅解冻 Wave 2 目标实际需要的原版扩展生命周期事件和 RPC extension UI
   surface，保持宏签名不变并只增加原版已有能力；
2. 保持扩展 API 完全冻结，同时由用户明确把上述测试及 RPC extension UI
   从 goal7 验收范围移除，作为批准过的 scoped exception。

用户随后裁决允许先提出限定扩充方案；实现仍须等待该方案逐项确认，Part
B/C/D 均未启动。

### 第二次阻塞复核

对 46 个 `CODING-SESSION` 目标逐文件扫描 `pi.on(...)` 后，18 个文件直接注册
了当前冻结白名单以外的公开事件：

| 目标文件 | 直接依赖的原版公开事件 |
|---|---|
| `agent-session-concurrent.test.ts` | `input` |
| `agent-session-dynamic-provider.test.ts` | `session_start` |
| `agent-session-dynamic-tools.test.ts` | `session_start` |
| `agent-session-runtime-events.test.ts` | `session_before_fork`, `session_before_switch`, `session_shutdown`, `session_start` |
| `branch-summary-extensions.test.ts` | `session_before_tree` |
| `compaction-extensions-example.test.ts` | `session_before_compact`, `session_compact` |
| `suite/agent-session-compaction.test.ts` | `session_before_compact` |
| `suite/agent-session-model-extension.test.ts` | `before_agent_start`, `context`, `input`, `model_select`, `session_shutdown`, `session_start`, `tool_call`, `tool_result` |
| `suite/agent-session-prompt.test.ts` | `input` |
| `suite/agent-session-queue.test.ts` | `agent_end` |
| `suite/agent-session-retry-events.test.ts` | `message_start`, `message_end` |
| `suite/agent-session-runtime.test.ts` | `message_end`, `session_before_fork`, `session_before_switch`, `session_shutdown`, `session_start` |
| `suite/regressions/1717-2113-agent-session-event-settlement.test.ts` | `message_end`, `tool_call` |
| `suite/regressions/2860-replaced-session-context.test.ts` | `session_shutdown`, `session_start` |
| `suite/regressions/3686-session-name-event.test.ts` | `session_info_changed` |
| `suite/regressions/5217-compaction-reason.test.ts` | `session_before_compact`, `session_compact` |
| `suite/regressions/5943-session-start-notify.test.ts` | `session_start` |
| `suite/regressions/pre-prompt-compaction-no-continue.test.ts` | `session_before_compact` |

这还没有计入不通过字面量 `pi.on(...)` 注册的 extension runner 测试，也没有
计入 Part C `print-mode.test.ts` 对 `session_shutdown` 的直接要求。

替代实现复核结论：

- 只增加内部 agent/session event spine 无法让扩展注册这些事件；
- 把新事件偷偷映射到现有四种事件会改变 payload/时序，而且不是原版语义；
- 绕过 `register-extension-hook` 另建私有注册通道仍会扩大可观察 API；
- RPC UI bridge 必须增加现有 `extension-context` 不具备的 select/confirm/input/
  editor/status/widget/title/editor-text 能力，也不能仅靠 RPC dispatcher 私有实现；
- `docs/architecture.md:1015-1017` 还明确冻结 event 为当前四种，因此即使保持
  宏签名和 package export 文本不动，扩大白名单仍然是在触碰已冻结 API。

所以“保持所有冻结 object ID，同时让所有目标文件转 C”在当前规格下不可满足。
