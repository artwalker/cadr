# cadr architecture

状态：**v1 Phase 1–4 与 v2 Phase 5–9 已实现；北极星 Wave 2 的 agent
harness、session v3、print/JSON 与 RPC 已完成；扩大的稳定扩展 API 已重新
冻结；原版默认执行安全模型已对齐；Phase 8 TUI、Phase 9 依赖收尾与 cadr
命名迁移已完成**

本文是 `docs/progress/goal-v1.md` 要求的第一个交付物，已于 2026-07-30
获得人工确认。
后续实现若改变本文中的公开接口、数据格式或行为约束，必须先同步修改本文，
并在对应阶段报告中说明。

2026-07-30 起新增一条全局约束：cadr 对齐固定 TS 基线的设计哲学，不在
核心增加原版没有的机制。默认执行模型是 YOLO；审批不是核心安全边界，强
隔离由用户通过容器提供。任何拟新增机制先写入 `docs/open-questions.md`
等待人工裁决，不得默认实现。v1 工具确认已在 Phase 7 完成后作为独立任务
移除；核心不再导出确认回调，也没有 `--yolo` 分支。

## 1. 参考基线与边界

### 1.1 参考源码

- 行为参考仓库：`https://github.com/earendil-works/pi`
- 固定审计提交：`71efc6f0c1909874ec8c944637a9ae7fc0e2d508`
  （2026-07-30）
- 迁移前上游 TypeScript HEAD：
  `e3f6912d49d14b6e6ffe96bb053644922004ecf3`
- legacy 状态保存于 `pi-mono-legacy` 分支引用与 patch 归档，基点
  `48b9a05f2cfc3f34f749ac4a2d8d17aec0f843a1`；`/root/projects/pi-mono`
  目录现跟踪上游 `main`
- 当前 cadr tracked tree 不再包含上游 TypeScript 实现；下列参考路径均
  指固定审计提交中的路径。重新生成对拍 fixture 时必须 checkout
  `71efc6f0c1909874ec8c944637a9ae7fc0e2d508` 并将其路径作为
  `scripts/export-ts-payloads.ts --reference`，不得改用移动中的 legacy
  分支 tip。

固定提交的范围内，重点参考：

- `packages/ai/src/types.ts`
- `packages/ai/src/api/anthropic-messages.ts`
- `packages/ai/src/api/openai-responses.ts`
- `packages/ai/src/api/openai-responses-shared.ts`
- `packages/ai/src/api/google-generative-ai.ts`
- `packages/ai/src/api/google-shared.ts`
- `packages/agent/src/agent-loop.ts`
- `packages/agent/src/agent.ts`
- `packages/agent/src/harness/`
- `packages/coding-agent/src/core/tools/`
- `packages/coding-agent/src/core/session-manager.ts`
- `packages/coding-agent/src/cli/args.ts`
- `packages/coding-agent/src/main.ts`

### 1.2 第一版包含

- Anthropic Messages API
- OpenAI Responses API
- Google Gemini Generative Language API，第一版默认模型
  `gemini-3.6-flash`
- 三家的真实非流式请求和真实 SSE 流式请求
- 统一消息、工具、用量、停止原因和错误模型
- 完整的“模型响应 → 工具调用 → 工具结果 → 再次调用模型”循环
- JSON Schema 工具参数校验
- `read`、`write`、`edit`、`bash`、`glob`、`grep`
- REPL、多轮会话、JSONL 持久化和 `--continue`
- 与原版一致，全部工具在 schema 校验后默认直接执行
- Linux x64 / SBCL 2.4+ 单文件可执行程序

### 1.3 第一版不包含

- 全屏 TUI、图片输入和图片工具结果
- OpenAI Chat Completions 兼容层；OpenAI 第一版只实现 Responses API
- Anthropic/OpenAI/Google 之外的 provider
- OAuth、云平台代理、Bedrock、Vertex、WebSocket
- extension、skill、prompt-template、package 安装系统
- 会话分支、压缩、HTML 导出、RPC、Web UI、Slack、pods
- 动态模型目录和价格计算；只统计 provider 返回的 token 用量

这些是明确的产品边界，不用空壳或“以后实现”的假接口冒充已支持功能。

### 1.4 两个明确裁决

1. `docs/progress/goal-v1.md` 要求工具名为 `glob`，参考提交中的同类工具名为
   `find`。
   第一版公开名采用 `glob`，参数和结果语义对齐参考实现的 `find`：
   `pattern`、可选 `path`、可选 `limit`、相对路径输出和稳定截断提示。
2. 参考实现的 `complete()` 可以通过收集流事件得到最终消息，但
   `docs/progress/goal-v1.md` 明确要求“非流式和流式请求”。因此 CL 层会发送真实的
   `stream=false` 请求，不用“内部仍然流式，只是不显示增量”偷换概念。

## 2. 系统分层

依赖方向固定为：

```text
cadr-cli -> cadr-agent -> cadr-ai
```

| TypeScript 责任 | Common Lisp system / package / module | 第一版责任 |
|---|---|---|
| `packages/ai/src/types.ts`、model/provider registry | `cadr-ai` / `cadr-ai` / `types.lisp`、`provider.lisp` | 统一模型、消息、内容块、工具、用量、事件 |
| `packages/ai/src/api/*` 三家实现 | `cadr-ai` / `cadr-ai` / `providers/*.lisp` | 请求构造、消息转换、非流式响应和 SSE reducer |
| `packages/ai/src/utils/event-stream.ts` | `cadr-ai` / `cadr-ai` / `types.lisp`、`provider.lisp` | 同步事件回调协议和最终消息收集 |
| provider SDK / fetch 边界 | `cadr-ai` / `cadr-ai` / `http.lisp`、`sse.lisp` | 自研 HTTP/1.1、OpenSSL TLS、UTF-8 流读取、通用 SSE framing |
| `packages/agent/src/agent-loop.ts` | `cadr-agent` / `cadr-agent` / `loop.lisp` | turn 循环、工具批次、事件顺序、停止条件 |
| `packages/agent/src/agent.ts` | `cadr-agent` / `cadr-agent` / `runtime.lisp` | 可变状态、订阅、忙碌状态、取消、提示入口 |
| `packages/agent/src/harness/types.ts` | `cadr-agent` / `cadr-agent` / `conditions.lisp`、`tool.lisp` | 稳定错误分类、工具协议和执行模式 |
| harness / coding-agent session | `cadr-agent` / `cadr-agent` / `session.lisp` | 第一版线性 JSONL 保存、加载、最近会话查找 |
| harness 与 coding-agent 内置工具 | `cadr-cli` / `cadr-cli` / `tools/*.lisp` | 六个本地编码工具和统一截断 |
| `coding-agent` args/main/system prompt | `cadr-cli` / `cadr-cli` / `config.lisp`、`main.lisp`、`repl.lisp` | 配置、模型选择和 REPL |

每个 system 只导出稳定入口；provider 私有 payload 类型、SSE 临时状态和
文件工具内部辅助函数不导出。

## 3. 目录与 ASDF

实现目录：

```text
cadr-ai.asd
cadr-agent.asd
cadr-cli.asd
build.lisp
build.sh
src/
  cadr-ai/
    package.lisp
    conditions.lisp
    types.lisp
    json.lisp
    http.lisp
    sse.lisp
    provider.lisp
    providers/
      anthropic.lisp
      openai.lisp
      google.lisp
  cadr-agent/
    package.lisp
    conditions.lisp
    schema.lisp
    tool.lisp
    loop.lisp
    runtime.lisp
    session.lisp
  cadr-cli/
    package.lisp
    arguments.lisp
    build-support.lisp
    config.lisp
    truncation.lisp
    extensions.lisp
    tools/
      path.lisp
      read.lisp
      write.lisp
      edit.lisp
      bash.lisp
      glob.lisp
      grep.lisp
    system-prompt.lisp
    repl.lisp
    tui.lisp
    main.lisp
  cadr-tui/
    package.lisp
    unicode.lisp
    fuzzy.lisp
    word-navigation.lisp
    keys.lisp
    keybindings.lisp
    kill-ring.lisp
    undo-stack.lisp
    input.lisp
    stdin-buffer.lisp
    terminal-colors.lisp
    terminal-image.lisp
    overlay.lisp
    autocomplete.lisp
    editor.lisp
    input-component.lisp
    components.lisp
    renderer.lisp
    terminal.lisp
test/
  fixtures/
    requests/
    responses/
    sse/
  cadr-ai/
  cadr-agent/
  cadr-cli/
  cadr-tui/
scripts/
  export-ts-payloads.ts
  acceptance-smoke.sh
  test-cl.sh
docs/
  architecture.md
  test-matrix.md
  progress/
```

ASDF systems：

- `cadr-ai`、`cadr-ai/tests`
- `cadr-agent`、`cadr-agent/tests`
- `cadr-cli`、`cadr-cli/tests`
- `cadr-tui`、`cadr-tui/tests`

Phase 9 后的生产依赖：

| 库 | 用途 | 选择理由 |
|---|---|---|
| `cl+ssl` | HTTPS TLS | 第一个在册自研例外；绑定系统 OpenSSL，不自研密码学 |
| `cl-sqlite`（ASDF `sqlite`） | session storage SQLite adapter | 第二个在册自研例外；经 CFFI 绑定系统 `libsqlite3`，项目自研 storage/repository contract 而不重写数据库引擎 |
| `cl-ppcre` | `grep`、glob 和 JSON Schema `pattern` | 完整正则引擎按 `docs/progress/goal-v2.md` 明确暂缓；用户 pattern 不交给 shell |
| `uiop` / ASDF、`sb-thread`、`sb-bsd-sockets`、`sb-posix` | 路径、进程、线程、socket、终端和构建 | SBCL/ASDF 自带设施，不计第三方生产依赖 |

`fiveam` 只存在于测试 system。`babel`、`bordeaux-threads`、
`flexi-streams`、`usocket` 和 `trivial-gray-streams` 不被生产源码或
production system 直接依赖；其中部分仍会作为 `cl+ssl` 或 `cl-sqlite`
的 Quicklisp 传递依赖进入 image。`cl-sqlite` 直接依赖 `iterate` 与 CFFI；
Linux/SBCL 下的 CFFI 闭包为 Alexandria、Babel 与 trivial-features。完整
归属见 `docs/dependency-audit.md`，这些传递项不构成新的独立例外。

不使用 Node/Bun，不调用 provider 的 JavaScript SDK。实现直接使用官方 HTTP
协议，因此 payload 对拍和原始 SSE 回放是硬门槛。

## 4. 统一数据模型

使用 `defstruct` 表示纯数据，使用 CLOS generic function 表示 provider 和
tool 的多态行为。

核心对象：

- `model`：`id`、`provider`、`api`、`base-url`、`max-tokens`
- `text-content`、`thinking-content`、`tool-call`
- `user-message`、`assistant-message`、`tool-result-message`
- `usage`：`input`、`output`、`cache-read`、`cache-write`、`total`
- `tool`：`name`、`description`、`parameters`、`execution-mode`、`executor`
- `context`：`system-prompt`、`messages`、`tools`

统一停止原因：

- `:stop`
- `:length`
- `:tool-use`
- `:error`
- `:aborted`

统一流事件：

- `:start`
- `:text-start`、`:text-delta`、`:text-end`
- `:thinking-start`、`:thinking-delta`、`:thinking-end`
- `:tool-call-start`、`:tool-call-delta`、`:tool-call-end`
- `:done`
- `:error`

每个成功流必须恰好一个 `:start` 和一个终止事件。失败不能让调用方等不到
终止事件；网络/API/解析失败必须归一化为最终 `assistant-message`，其
`stop-reason` 为 `:error` 或 `:aborted`。

## 5. HTTP、非流式和 SSE

### 5.1 HTTP 抽象

`cadr-ai.http` 提供两个可替换入口：

- `request-json`：返回 status、headers、已解析 JSON
- `request-sse`：返回 status、headers，并把响应体流交给 SSE consumer

默认实现由 `sb-bsd-sockets` 写出 HTTP/1.1 请求并解析 status、headers、
content-length、connection-close 与 chunked body；HTTPS 只在 socket
外包一层 `cl+ssl`。测试既可注入录制 fixture，也用真实 loopback socket
验证流式读取。请求对象在发送前可以被测试捕获，但任何日志和 condition
report 都不得包含 API key 或 Authorization header。

`request-json` 使用有限 connect/read timeout。`request-sse` 仍保留有限
connect timeout，但必须在原生 HTTP 请求上显式传入无界 read timeout
（`read-timeout = NIL`），不能继承客户端的短默认值。SSE 长时间没有字节
可能只是模型处于长思考期，不等同于失联；取消由用户 abort、进程退出或
provider/agent 上层 deadline 控制。这个差异必须位于 HTTP 抽象层，不能让
三个 provider 各自碰运气覆盖 timeout。

### 5.2 通用 SSE framing

`cadr-ai.sse` 只负责协议，不理解 provider：

1. 以二进制流接收 chunk，经 UTF-8 解码器保留跨 chunk 的未完成字符。
2. 同时接受 LF 和 CRLF。
3. 空行提交一个事件。
4. 忽略 `:` comment；支持 `event:`、`data:`、`id:`。
5. 多个 `data:` 行按规范用换行连接。
6. 正确处理 EOF 前没有最终空行的最后一个完整事件。
7. 不把 `[DONE]` 当 JSON；由 provider reducer 决定是否为终止标记。
8. JSON 损坏、意外 EOF 和 HTTP body 错误分别产生可区分 condition。

### 5.3 Provider adapter

每个 adapter 实现四件事：

- `build-request`
- `parse-complete-response`
- `reduce-sse-event`
- `map-provider-error`

#### Anthropic

- `POST {base-url}/v1/messages`
- `x-api-key`、`anthropic-version`、`content-type`
- system prompt 独立于 messages
- assistant tool call 映射为 `tool_use`
- 连续 tool results 合并进一个 user turn
- 处理 `message_start`、`content_block_start/delta/stop`、
  `message_delta`、`message_stop`
- 从 start/delta usage 汇总 input/output/cache token

#### OpenAI

- `POST {base-url}/v1/responses`
- Bearer auth
- system prompt 进入 `input` 的 system/developer message
- tool 定义使用 Responses function tool 结构
- tool call ID 同时保留 `call_id` 和 item ID，保证后续
  `function_call_output` 能配对
- 处理 `response.created`、output item、text delta、function argument
  delta、`response.completed/failed`
- cached input 从 input token 中扣除后计入 `cache-read`

#### Google

- 非流式：
  `POST .../models/{model}:generateContent`
- 流式：
  `POST .../models/{model}:streamGenerateContent?alt=sse`
- API key 通过 provider 要求的 header/query 发送，不进入日志
- system prompt 映射为 `systemInstruction`
- assistant role 映射为 `model`
- tool call/result 映射为 `functionCall` / `functionResponse`
- 从 candidate parts 生成 text/thinking/tool-call 事件
- 若响应包含工具调用，最终停止原因强制归一化为 `:tool-use`
- 当前基线和默认模型固定为 Google 官方列出的稳定 ID
  [`gemini-3.6-flash`](https://ai.google.dev/gemini-api/docs/models/gemini-3.6-flash)。
  Google 的
  [2026-07-21 release note](https://ai.google.dev/gemini-api/docs/changelog)
  同时废弃 `temperature`、`top_p`、`top_k`；对该模型的请求不得发送这些
  字段，即使调用方提供通用 temperature 选项。旧模型仍保留现有
  temperature 映射。

三家 adapter 都必须保留文本和工具调用的出现顺序，并在流中增量解析工具
参数；只有 `tool-call-end` 后的 JSON 参数才可进入执行阶段。

## 6. TS async/Promise 到 CL 的映射

网络和 agent 主循环采用**同步调用 + 增量回调**，而不是给每次请求制造一个
后台线程：

```lisp
(stream-chat provider context
             :on-event #'handle-event)
;; 阻塞到 :done / :error，但 delta 到达即回调
```

这是有意的结构化同步设计：

- REPL 在一次 agent run 中本来就必须等待最终结果；
- 同一线程回调让消息状态和终端输出顺序确定；
- 仍然是真流式，不会等待完整 HTTP body；
- 不需要模拟 JavaScript event loop，也不会留下失控 promise/thread。

只有一个 assistant message 内的独立只读工具批次使用 `sb-thread`：

- `:tool-call-before` 扩展 hook 和参数校验按固定顺序执行；
- 全部工具都标记 `:parallel` 时才并发；
- `tool-execution-end` 可按实际完成顺序发出；
- tool-result message 必须按 assistant 中的调用顺序写回上下文；
- 任一工具标记 `:sequential` 时，整个批次顺序执行。

`bash`、`write`、`edit` 永远标记为 `:sequential`，避免文件修改竞态。
事件 sink 由 mutex 串行化；每个线程必须在 run
结束前 join，不允许 detached worker。

## 7. Condition system 与重试

Condition 层次：

```text
cadr-error
├── configuration-error
├── transport-error
│   ├── network-error
│   ├── timeout-error
│   ├── request-aborted
│   └── sse-protocol-error
├── api-error
├── schema-validation-error
├── tool-execution-error
├── agent-busy-error
├── agent-turn-limit-error
└── session-error
```

共同 slot：

- 人类可读 message
- 原始 cause（若有）
- `retryable-p`

额外结构：

- `api-error`：provider、HTTP status、provider code、retry-after
- `schema-validation-error`：tool、JSON pointer、校验原因
- `tool-execution-error`：tool、tool-call-id；具体错误类别保留在 message/cause
- `session-error`：文件路径、损坏行号

处理边界：

- 配置和 session header 损坏是 CLI fatal error，退出码非零。
- provider 失败变成最终 assistant error message。
- 未知工具、参数校验失败、扩展 hook 拦截和工具自身失败变成
  `tool-result-message`，`is-error = true`；agent 可读取错误并修正。
- 日志和 condition printer 统一脱敏 key、Authorization、原始敏感 header。

Phase 4 实现有限重试：

- 网络断开、429、500/502/503/504 可重试；
- 其他 4xx、schema 和工具错误不重试；
- 默认最多 2 次重试（共 3 次请求），退避为 0.25s、0.5s；
- 纯数字秒数格式的 `Retry-After` 优先于指数退避，并封顶 60s；
- SSE 只允许在收到第一个 provider 事件前重试，且不会重复发出统一
  `:start`；事件已开始后失败则直接终止，避免重复 delta；
- 达到上限后必须产出明确 error message，不能无限循环。

## 8. Agent 循环

单次 `prompt` 的确定性流程：

1. 拒绝并发的第二个 prompt（`busy`）。
2. 追加 user message，发出 agent/turn/message 生命周期事件。
3. 对上下文做 provider message conversion。
4. 流式调用模型并持续更新当前 assistant message。
5. 收到终止事件后持久化最终 assistant message。
6. 若为 `:error` / `:aborted`，结束 run。
7. 若有工具调用：
   - `:length` 时一律不执行，因为参数可能被截断；
   - 查找工具；
   - JSON Schema 校验；
   - 运行 `:tool-call-before` 扩展 hook；
   - 用最终 name 重新解析工具并重校验最终 arguments；
   - 执行工具并生成 tool result；
   - 运行 `:tool-call-after` 扩展 hook；
   - 按调用顺序追加所有 tool results；
   - 回到第 3 步。
8. 无工具调用时结束 turn 和 agent run。

默认允许模型连续多轮调用工具。设置一个较高但有限的内部 turn 上限
（默认 100）防止恶意或失控 provider 永久循环；触发后返回明确错误。

## 9. 工具注册、校验与安全

### 9.1 注册与校验

registry 以 tool name 为唯一键，重复注册直接失败。工具参数是原生 JSON
parser 生成的 hash-table，执行前由 `schema.lisp` 的原生校验器校验。
校验器覆盖固定基线工具 schema 使用的 object/array/scalar 约束、本地
`$ref`、组合关键字、依赖与 `pattern`；错误结果至少包含：

- JSON pointer
- 违反的约束
- 工具名

不做“猜字段”“自动修正类型”或把无效参数传给 shell/filesystem。

### 9.2 默认执行与隔离边界

对齐原版 pi：工具在最终参数通过 schema 校验后直接执行。核心不提供确认
弹窗、信任账本、审批回调或 `--yolo` 开关，也不把 cwd 路径检查伪装成安全
沙箱。需要强隔离的用户应在容器、虚拟机或受限用户中运行。

需要逐工具审批时，用 Phase 7 的 `:tool-call-before` hook 实现。该策略属于
用户扩展，不进入 agent 或 CLI 核心；README 提供最小示例。

### 9.3 工具行为

| 工具 | 关键行为 |
|---|---|
| `read` | 相对 cwd 或绝对路径；UTF-8；1-based offset/limit；默认 head 截断 2000 行或 50 KiB；越界明确报错 |
| `write` | 创建父目录；UTF-8；完整覆盖；同一路径文件写入串行化 |
| `edit` | 一个文件内一个或多个 exact replacement；每个 old text 必须在原文件唯一；所有匹配基于原文件；拒绝重叠；一次写回 |
| `bash` | `/bin/bash -lc`；cwd 固定；合并并流式显示 stdout/stderr；返回 exit code；tail 截断 2000 行或 50 KiB；超时/终止清理进程组 |
| `glob` | glob pattern、path、limit；递归；默认忽略 `.git`/`node_modules`，并遵循可解析的 `.gitignore`；相对 POSIX 路径 |
| `grep` | regex 或 literal、path、glob filter、ignore-case、context、limit；路径和行号；长行、match 数和总字节均有上限 |

glob/grep 由 CL 遍历和 `cl-ppcre` 完成，不拼接 shell 命令，因此无需把
用户 pattern 交给 `/bin/bash`。路径解析以 cwd 为基准，但允许用户明确
给出绝对路径；第一版不把 cwd 当安全沙箱。

`bash` 在 Linux 使用独立进程组；取消时先 TERM，短暂等待后 KILL，避免
pipeline 或孙进程泄漏。完整输出边读边写入临时文件，只有发生截断时才在
tool result 中暴露该路径。

## 10. 会话

第一版采用线性 append-only JSONL，满足保存/恢复，不实现参考项目的分支树。

header：

```json
{"type":"session","version":1,"id":"...","timestamp":"...","cwd":"..."}
```

后续每行：

```json
{"type":"message","timestamp":"...","message":{...}}
```

约束：

- 默认目录：`~/.cadr/sessions/`
- API key、Authorization 和环境变量绝不写入 session
- 每个最终 user/assistant/tool-result message 追加后立即 flush
- 允许崩溃留下一个不完整的最后一行；只忽略这个尾行
- 中间行损坏或 header 不合法必须报 `session-error`
- `--continue` 选择 header.cwd 与当前 canonical cwd 相同的最新有效 session
- 找不到历史 session 时给出诊断并启动新 session
- 恢复后重建完整消息上下文，再进入 REPL；不会伪造遗漏的 tool result

## 11. CLI 与 REPL

当前参数：

- `--provider anthropic|openai|google|deepseek|ollama`
- `--model <id>`
- `--base-url <url>`
- `--system-prompt <text-or-file>`
- `--continue`
- `--resume <session-id>`
- `--extension <path>`（可重复）
- `--help`
- `--version`

环境变量：

- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `GEMINI_API_KEY`
- 可选 `CADR_PROVIDER`、`CADR_MODEL`

provider 未指定时，从现有 key 推断，优先级 Anthropic → OpenAI → Google；
这保证只设置 `ANTHROPIC_API_KEY` 后执行 `./cadr` 能直接工作。每个 provider
都有固定默认模型：Anthropic `claude-opus-4-8`、OpenAI `gpt-5.5`、
Google `gemini-3.6-flash`；同时允许 CLI/env 覆盖。三者都记录进 README，
避免把动态网络模型目录带入第一版。

REPL 使用标准输入逐行读取：

```text
cadr> 用户输入
assistant> 流式文本
```

- 空行忽略
- EOF 正常保存并退出
- 每个输入完成完整 agent loop 后才读取下一行
- provider/tool 错误打印一次且保留会话可继续
- Ctrl-C 尽力中止当前 HTTP/进程；空闲时退出

## 12. 测试先行与对拍

每个模块执行固定节奏：

1. 先移植/新增 FiveAM 测试。
2. 运行目标 suite，保存预期失败证据。
3. 实现最小完整行为。
4. 重跑目标 suite，直到通过。
5. 运行所有已完成 phase 的回归测试。

`docs/test-matrix.md` 会逐项记录：

- 原 TS 测试文件和测试名
- 对应 CL suite/test
- 是否属于第一版范围
- fixture 或验证证据

“所有移植测试通过”以这个矩阵为审计入口，不能用测试数量代替行为覆盖。

### Phase 1：cadr-ai

先移植：

- 统一 stream event 顺序和最终结果
- abort/error termination
- token usage/total token
- empty response
- tool-call without result
- cross-provider history conversion 的文本/工具子集
- SSE transport 显式使用无界 read timeout；模拟超过普通 JSON read
  timeout 的静默期后再发送事件，连接仍能消费并正常终止
- Anthropic SSE parsing
- OpenAI Responses tool call/result
- Gemini 3.6 Flash tool call/signature 的第一版相关子集；回放 fixture
  必须来自 `gemini-3.6-flash` 的真实流式响应

新增 fixture：

- `test/fixtures/requests/{anthropic,openai,google}-*.json`
- `test/fixtures/responses/{anthropic,openai,google}-complete.json`
- `test/fixtures/sse/{anthropic,openai,google}-*.sse`

SSE fixture 必须是去敏后的真实响应录制，测试直接回放原始字节流，并覆盖
故意切在 UTF-8 字符和 JSON token 中间的 chunk 边界。测试不访问在线 API。

### Phase 2：cadr-agent

优先移植 `packages/agent/test/agent-loop.test.ts` 的范围内语义：

- 生命周期事件顺序
- tool call → result → 下一轮
- 未知工具和 schema 错误
- `:length` 响应中的工具绝不执行
- sequential/parallel 批次规则
- completion-order 事件与 source-order 结果
- abort/error 后正常终止

使用 faux provider 和 mock tools，不使用真实 key。

### Phase 3：tools + CLI

优先移植：

- read offset/limit/UTF-8/截断/越界
- write 创建父目录和覆盖
- edit not-found/non-unique/overlap/多替换/原子写回
- bash stdout+stderr/nonzero/timeout/大输出/进程清理
- glob/grep limit、忽略规则、路径和无结果
- 默认直接执行副作用工具（原 v1 确认回归已由对齐测试取代）
- REPL 多轮和真实工具循环（faux provider）

### Phase 4：持久化、重试、构建和验收

- JSONL round-trip、损坏文件、尾行恢复、cwd 隔离、`--continue`
- retryable/non-retryable/上限
- 全量 test-op
- clean build
- 三家录制回放端到端
- 小型 fixture repo 的“读 → 改 → 测试失败 → 再修复 → 测试通过”

### Payload 对拍

`scripts/export-ts-payloads.ts` 在固定参考提交上通过公开 stream API 的
payload hook 和 fake transport 导出三家请求体。CL 测试用同一份
context/model/tool 输入生成 payload，递归逐字段比较：

- key 集合相等
- array 顺序相等
- number/string/bool/null 类型和值相等
- 除测试显式列出的动态字段外不允许忽略字段

动态字段白名单只允许 request/session ID 和时间戳；`model`、messages、
tools、stream、max tokens 等都不能被模糊比较。

## 13. 构建

`build.sh`：

1. 检查 `sbcl` 存在且版本 >= 2.4。
2. 加载 `QUICKLISP_SETUP` 指定文件，或
   `~/quicklisp/setup.lisp`。
3. Quickload `cadr-cli`。
4. 运行所有 ASDF test-op；测试失败则不产出二进制。
5. 检查 `*features*` 是否包含 `:sb-core-compression`。支持时调用：

```lisp
(sb-ext:save-lisp-and-die
 "cadr"
 :toplevel #'cadr-cli:executable-main
 :executable t
 :save-runtime-options t
 :compression t)
```

不支持时打印明确降级提示，并调用不含 `:compression` 关键字的
`save-lisp-and-die`。不能仅传 `:compression nil`，因为不带
`sb-core-compression` 的 SBCL 可能连该关键字都不接受；无压缩构建仍须成功
产出 `cadr`。构建测试分别覆盖 feature 存在和不存在时的参数构造，避免只在
本机 SBCL 变体上碰巧可用。

产物位于仓库根目录 `./cadr`。执行时不需要源码或 Quicklisp，但仍依赖
Linux/glibc 和 HTTPS 所需的系统动态库；“单个可执行文件”不虚假承诺完全
静态链接。

当前审计环境使用 SBCL 2.6.7 和 Quicklisp 2026-01-01。该 SBCL 不含
`:sb-core-compression`；隔离 HOME 的实际构建已验证降级提示、无压缩
`cadr` 产物、保存 runtime options 后的 `--help` / `--version`，以及跨
两个进程的 `--continue`。

## 14. 验收证据映射

| `docs/progress/goal-v1.md` 验收项 | 最终证据 |
|---|---|
| clean Linux 一键产出 `cadr` | 隔离 HOME 的 clean-build 日志、二进制 `file` 输出 |
| Anthropic 多轮流式对话 | `scripts/live-anthropic-smoke.sh` 的获授权终端记录；脚本不输出或保存 key |
| 真实 repo 读/改/测/修 | faux provider 确定性 E2E + DeepSeek 双重授权的 `scripts/live-repo-smoke.sh` |
| 三家各一 E2E | 三套原始 SSE 回放、请求捕获和最终统一消息断言 |
| 所有移植测试、文档一致 | `docs/test-matrix.md` 全绿、ASDF 全量 test-op、文档 diff 审计 |
| 默认执行、无核心审批 | 副作用工具直接执行、`--yolo` 被拒绝、审批 hook 示例 |
| `--continue` | 两进程 session restore E2E |
| README 完整 | 构建、配置、provider、工具、安全、差异章节检查 |

## 15. 阶段报告

每个 Phase 结束新增 `docs/progress/phase-N.md`，固定包含：

- 完成内容
- 执行的精确测试/构建命令和结果
- 与固定 TS 基线的已知差异
- 剩余风险和下一阶段

### 15.1 后续 goal 的预审与关账门禁

从本次整改后的下一份 goal 起，每份 goal 规格都必须原文包含以下两条全局
门禁：

1. Part A 必须列出新增第三方依赖及其传递闭包；发现任何未在
   `docs/dependency-audit.md` 登记的依赖，立即标记 `blocked`，取得用户明确
   授权并同步审计与 README 后才能实现。先添加、后追认视为违规。
2. “完成”必须同时满足实现与测试验收、按逻辑分组提交落账、提交后的全量
   门禁复验，以及工作区干净。未提交改动不得宣告完成；受明确保护的本地文件
   只能通过仓库本地 ignore 保留，不能混入提交或删除。

实现过程中没有出现需要源码作者澄清的问题。设计确认时冻结了：

- OpenAI 第一版只实现 Responses API；
- `glob` 采用参考实现 `find` 的语义；
- session 第一版是线性 JSONL，不实现分支/压缩；
- 网络主循环同步流式，只对安全的只读工具做受控并行。

人工确认后的补充冻结项：

- SBCL 缺少 `sb-core-compression` 时降级为无压缩 native image，而非构建
  失败；
- SSE 请求显式使用无界 read timeout，并以长静默期回归测试保护该行为。

## 16. v2 Phase 5：Provider 完备化

Phase 5 保留 v1 的统一消息、统一事件流和 protocol adapter 边界，但把
“provider 名称”和“wire protocol”拆开。DeepSeek、Ollama 等 provider
复用 OpenAI Chat Completions adapter，不复制传输或流解析逻辑。

### 16.1 Provider 注册表与解析优先级

`cadr-ai` 新增 `provider-definition` 和显式注册表。每项声明：

- 稳定 provider id
- wire protocol：`anthropic-messages`、`openai-responses`、
  `openai-completions` 或 `google-generative-ai`
- 默认 base URL、默认模型和 API key 环境变量
- 支持的认证方式：`api-key`、`oauth`
- 图片、工具和思维链能力

内置定义为 Anthropic、OpenAI、Google、DeepSeek 和 Ollama。请求对象仍由
protocol adapter 构建；注册表只负责选择 adapter、认证和默认值。
base URL 解析顺序固定为：

1. CLI `--base-url`
2. `~/.cadr/config.json` 中对应 provider 的 `base-url`
3. 注册表默认值

模型解析同理为 CLI `--model`、环境/配置覆盖、注册表默认值。Ollama 是无
API key 的本地 provider；其余 API-key provider 缺少凭据时必须立即报告
configuration condition。DeepSeek 使用
`https://api.deepseek.com` 的 OpenAI Chat Completions 路径。

### 16.2 OpenAI Chat Completions adapter

新增独立 `openai-completions-provider`，负责
`/v1/chat/completions` 请求与 SSE：

- system/user/assistant/tool 四种 role 的历史转换
- tool schema、assistant `tool_calls` 和 tool result 关联
- 流式 `delta.content`、`delta.reasoning_content` 与分片
  `tool_calls[].function.arguments` 聚合
- `finish_reason` 映射：`stop`、`length`、`tool_calls`，未知值为错误
- `stream_options.include_usage = true`，usage 中 cache/reasoning tokens
  映射到统一 usage
- 非流式响应复用相同的内容、tool call、usage 和 stop-reason 语义

模型/provider 的兼容差异只允许由注册表能力字段控制，不能散落成 CLI
分支。DeepSeek 的录制回放必须走这个 adapter。

### 16.3 图片与模型目录

统一 content 增加 `image-content`，只保存 MIME type 与 base64 数据，不把
二进制或 token 写入日志。三种协议编码分别为：

- Anthropic：`source.type=base64`
- OpenAI Responses：`input_image.image_url=data:<mime>;base64,<data>`
- OpenAI Chat Completions：`image_url.url=data:<mime>;base64,<data>`
- Google：`inlineData.mimeType` 与 `inlineData.data`

provider/model 未声明图片能力时，在发请求前抛出明确
`unsupported-content-error`，禁止静默丢弃。

静态模型目录由 `model-metadata` 组成，记录 context window、最大输出、
图片/工具/思维链能力以及每百万 token 的 input/output/cache 单价。usage
成本以模型目录计算并存入统一 usage。更新脚本只生成确定性 Lisp 数据文件；
运行时不依赖网络。

### 16.4 认证与 OAuth

provider 的请求认证统一解析为 `api-key-credential` 或
`oauth-credential`。adapter 只接收最终请求头，不参与登录和刷新。
`~/.cadr/auth.json` 是唯一持久凭据文件，写入采用临时文件加原子替换，
创建后强制 `0600`。所有 condition、会话和诊断输出先经过 secret
redaction。

OAuth 解析采用双重检查锁：access token 剩余有效期不足五分钟时，先取得
provider 级锁，再重新读取 auth 文件；只有仍将过期的请求执行 refresh，
随后在释放锁前持久化旋转后的凭据。

OpenAI Codex OAuth 严格采用固定 TS 审计提交的参数：

- authorize：`https://auth.openai.com/oauth/authorize`
- token：`https://auth.openai.com/oauth/token`
- client id：`app_EMoamEEZ73f0CkXaXp7hrann`
- redirect URI：`http://localhost:1455/auth/callback`
- scope：`openid profile email offline_access`
- PKCE：S256，并校验随机 state
- authorize 附加
  `id_token_add_organizations=true`、
  `codex_cli_simplified_flow=true`、`originator=pi`
- Responses 请求头包含 bearer token、JWT 中提取的
  `chatgpt-account-id`、`originator: pi` 和
  `OpenAI-Beta: responses=experimental`

本地一次性 callback server 只监听 `127.0.0.1:1455`，只接受
`/auth/callback`，验证 state 后立即关闭。`/login openai` 完成 PKCE，
`/logout openai` 原子删除该凭据。Anthropic OAuth 复用相同 credential
接口，但在实现、测试报告和 README 中明确标记为未验证。

### 16.5 Phase 5 测试门禁

实现顺序为测试先行：

1. registry/default/覆盖/无 key 行为
2. Chat Completions 非流式 payload 与录制 SSE E2E
3. 四种图片编码与 unsupported-content 错误
4. 模型查找和 cost 算术
5. PKCE、callback state、0600、logout、脱敏
6. 过期 token 的并发单次刷新录制回放
7. OpenAI Codex OAuth Responses 请求头
8. 原有 v1 全量回归、`npm run check` 和 Phase 5 live smoke

Phase 7 的稳定扩展 API 后续已通过独立人工确认并完成实现。

## 17. v2 Phase 6：树形会话、压缩与导出

Phase 6 把会话文件定义为 append-only event tree。运行时只选择一条
root-to-leaf 路径作为模型上下文；分叉不会复制、修改或删除旧节点。这是
parent-linked tree，而不是维护多份容易漂移的线性消息数组。

### 17.1 JSONL v2 与树不变量（历史格式，已由 Wave 2 v3 取代）

首行仍是 session header，但 `version` 升为 `2`。其余记录分为：

- `message`：包含唯一 `id`、`parentId`、`timestamp` 与完整 `message`；
- `compaction`：Phase 6 的 v2 节点曾含 `summary`、`sourceIds`、
  `firstKeptEntryId` 与 `tokensBefore`；Wave 2 v3 不再写非参考
  `sourceIds`。

每个普通追加节点的 `parentId` 都是当前 leaf；从历史节点分叉只移动内存
中的 leaf，下一次追加自然形成第二个 child。文件永不原地删改节点，因此
两个分支重启后仍可分别按 parent 链恢复。加载器拒绝重复 id、缺失/前向
parent 与不存在的压缩引用，避免把损坏文件伪装成可恢复会话。

v1 加载采用一次性原地迁移：

1. 保留 header 和每条消息 envelope 的全部既有字段；
2. 按原顺序补唯一 id 与线性 parentId，header 改为 v2；
3. 在同目录写临时文件并原子 rename；
4. 再按 v2 不变量加载。

因此旧消息的内容、usage、tool call/result、时间戳与未知扩展字段都不会因
反序列化再序列化而丢失。只有最后一条未完成 JSONL 尾记录沿用 v1 行为被
忽略；中间损坏仍是硬错误。

### 17.2 活跃分支与会话操作

`session-branch` 可把 leaf 移到任意已存在节点；`session-messages` 每次从
leaf 沿 parent 链重建活跃上下文，不保留第二份可漂移的消息真相。
`list-sessions`、`resume-session` 与 CLI 提供：

- `--resume <id>`：按精确 session id 恢复，和 `--continue` 互斥；
- `/sessions`：列出可恢复会话并标出当前会话；
- `/switch <id>`：在同一进程切换 session，同时替换 agent 上下文；
- `/branch <node-id>`：把下一条消息接到指定历史节点；
- `/export [path]`：导出完整树，而非仅导出当前分支。

HTML 导出只使用自研转义与字符串生成。所有消息、工具参数、摘要、id 与
parentId 都作为文本转义，文件不含脚本，故会话内容不能注入 HTML。

### 17.3 压缩节点与可追溯性

自动压缩属于 agent runtime，不属于 provider adapter。每次模型请求前，
runtime 用最近一次有效 assistant usage 加尾部估算；无 usage 时用保守的
字符/4 估算。当上下文超过
`model.context-window - reserve-tokens` 时：

1. 从最新消息向前累计 `keep-recent-tokens`，只在 user 或 assistant
   边界切割，绝不从孤立 tool result 开始；
2. 用当前 agent 的 provider、model 与 stream function 总结较旧部分；
3. 追加 compaction 节点，`firstKeptEntryId` 指向保留后缀；完整旧节点依靠
   append log 和 parent 链继续可追溯；
4. 将模型上下文替换为“摘要消息 + 保留后缀”，再继续原请求。

后续压缩可总结前一压缩节点与新的旧消息，形成可追踪的摘要链。原始节点
始终留在 JSONL，压缩只改变上下文投影，不改变历史。压缩失败时不写半成品
节点；agent 报告事件并保留原上下文。

若 provider 仍返回明确的 context-overflow 错误，runtime 把该错误节点保留
为可追溯的旁支，回到请求前 leaf 强制压缩并只重试一次。第二次 overflow
不循环重试，直接作为终态错误返回。

默认阈值沿用固定 TS 基线的意图：reserve 16,384 token、保留最近 20,000
token；对小窗口模型按窗口比例下调，避免默认值反而让压缩永久触发。
测试可显式覆盖这两个值以构造确定性边界。

### 17.4 Phase 6 测试门禁

Phase 6 在功能实现前先加入以下回归：

1. 新会话逐节点写出 v2 id/parentId，分叉后两条路径互不污染；
2. 文件重载后两个 leaf 都能恢复并继续追加；
3. v1 自动迁移为 v2，全部消息语义与原 envelope 附加字段保留；
4. 重复 id、悬空 parent、损坏中间行失败，未完成尾行仍可恢复；
5. 接近窗口时调用当前模型生成摘要，随后原请求继续；
6. 压缩 context 只含摘要与保留后缀，而 JSONL 仍含全部原节点；Phase 6
   当时还断言了后来在 Wave 2 v3 删除的 `sourceIds`；
7. 精确 resume、列表、进程内 switch、CLI 参数互斥；
8. HTML 导出含完整分支并正确转义恶意文本；
9. 原有 Phase 1–5 全量回归、native build 与 `npm run check` 继续通过。

Phase 7 的扩展 API 已在 Phase 6 全部门禁通过后单独提交人工确认并实现。

## 18. v2 Phase 7：Lisp 扩展系统（已实现）

本节的稳定 API 已于 2026-07-30 人工确认并冻结。

扩展系统采用 **registry builder + immutable snapshot**：加载期只向 staging
registry 注册定义，成功后原子替换 agent 使用的只读快照。扩展 package 提供
命名空间隔离，快照提供重载隔离；二者都不是安全沙箱。Common Lisp 扩展拥有
进程内任意代码能力，强隔离由用户通过容器提供。

### 18.1 扩展形态、发现与优先级

合法入口只有两种：

- 单个 `*.lisp` 文件，extension id 为不含后缀的文件名；
- 含 `extension.lisp` 的目录，extension id 为目录名。

每个入口在唯一的 `CADR-EXTENSION/<id>/<generation>` package 中加载，初始
package 只 `:use` `CL` 与 `CADR-AGENT`；需要 `CADR-AI` 时使用显式包前缀。
加载器动态绑定 `*package*`、`*load-pathname*` 与注册上下文。扩展不需要也
不应写 `in-package`。这避免不同扩展的普通符号互相污染，但不声称限制可信
扩展主动访问其他 package 或系统能力。

发现顺序先按 scope、再按文件名字典序固定：

1. `--extension <path>`，最高优先级；参数可重复，后出现者优先；
2. `./.cadr/extensions/`，项目级；
3. `~/.cadr/extensions/`，全局级。

同 id 的低优先级入口在加载前即被遮蔽，所以项目项明确覆盖全局同名项，
CLI 项覆盖二者。相同 scope 出现同 id 时报告冲突并保留确定性的第一项；
只有重复的 CLI 参数按“后者优先”处理。被遮蔽的入口不会执行，避免一个
看似已覆盖的全局扩展仍产生加载期副作用。

不同 extension id 注册同名资源时，按上述优先级取第一个并报告冲突：

- 扩展工具可以覆盖内置工具，与固定 TS 基线的能力一致；
- 内置斜杠命令始终优先，扩展不能劫持 `/reload`、`/install`、认证或会话
  命令；
- 其余命令优先于同名 prompt template；
- prompt template 和 skill 名称也按扩展优先级解析。

### 18.2 冻结的注册 API

以下四个宏及其参数协议导出自 `CADR-AGENT`，发布后保持兼容：

```lisp
(define-tool "echo"
  :description "Return text."
  :parameters <JSON-Schema hash-table>
  :execution-mode :parallel
  :handler (lambda (call-id arguments context)
             (declare (ignore call-id context))
             (values
              (list (cadr-ai:make-text-content
                     :text (gethash "text" arguments)))
              nil)))

(define-command "hello"
  :description "Print a greeting."
  :argument-hint "[name]"
  :handler (lambda (arguments context) ...))

(define-event-hook :tool-call-before
  :priority 0
  :handler (lambda (event context) ...))

(define-prompt-template "review"
  :description "Review a file."
  :argument-hint "<path>"
  :template "Review $1 carefully.")
```

具体契约如下：

- `define-tool`
  - 必填：字符串 name、description、JSON Schema hash-table、handler；
  - `:execution-mode` 只能是 `:parallel` 或 `:sequential`，默认
    `:parallel`；
  - handler 固定为 `(call-id arguments context)`，返回 `(values content
    details)`；content 是 `CADR-AI` content 列表；
  - schema 在注册期验证结构，在每次调用期验证最终 arguments。
- `define-command`
  - handler 固定为 `(arguments context)`；arguments 是命令名后未经拆词的
    字符串；
  - 返回值不参与消息发送，扩展通过 context 通知前端或调用 agent；
  - name 不含前导 `/`，只能使用小写 ASCII 字母、数字、`-`、`_`、`:`。
- `define-event-hook`
  - 既有四事件 `:turn-start`、`:turn-end`、`:tool-call-before`、
    `:tool-call-after` 的 payload 与结果语义不变；
  - Wave 2 只增加提案第 3 节列出的原版 lifecycle event；handler 仍固定为
    `(event context)`，新事件使用各自严格 plist result；
  - priority 为整数，较小者先执行；相同 priority 按扩展优先级和定义顺序
    固定执行。
- `define-prompt-template`
  - `:template` 可为字符串或 `(lambda (argv context) string)`；
  - 静态字符串支持固定 TS 基线的 `$1`、`$2`、`$@`、`$ARGUMENTS`、
    `${N:-default}`、`${@:-default}`、`${@:N}` 与 `${@:N:L}`；
  - argv 使用支持单双引号的确定性拆词器生成，替换不递归；
  - name 为 `skill:<name>` 时即为 Lisp skill。skill 不是第二套文件格式，
    而是使用同一注册、优先级和重载机制的具名模板。
- `define-provider`
  - 只注册 `cadr-ai:provider-definition` 与可选 model metadata；
  - 注册落在当前 extension host overlay，不改全局 provider registry。

这些宏只能在有效加载注册上下文中调用；在 REPL 或普通应用代码中直接调用
会给出明确 condition，避免定义落入不可见的全局隐式 registry。

### 18.3 稳定的 handler 数据协议

`extension-context` 是不透明对象，稳定导出以下读取与动作接口：

- `extension-context-cwd`
- `extension-context-agent`
- `extension-context-session`
- `extension-context-source-path`
- `extension-context-mode`
- `extension-context-notify`
- `extension-context-compact`
- `extension-context-reload`
- `extension-context-select`、`extension-context-confirm`
- `extension-context-input`、`extension-context-editor`
- `extension-context-set-status`、`extension-context-set-widget`
- `extension-context-set-title`、`extension-context-set-editor-text`
- `extension-context-register-provider`、`extension-context-register-tool`
- `extension-context-send-message`、`extension-context-send-user-message`
- `extension-context-set-session-name`

context 只在当前 handler 动态范围内有效；保存后跨 handler 或跨 reload 使用
会抛出 `stale-extension-context`。`extension-context-agent` 返回当前
`CADR-AGENT:AGENT`，允许 Lisp 扩展使用已经公开的 agent API，但不把 CLI 或
未来 TUI 对象纳入稳定接口。动作函数签名固定为：

- `(extension-context-notify context message &key (level :info))`，level
  只能是 `:info`、`:warning` 或 `:error`，由当前前端渲染；
- `(extension-context-compact context &key (force-p t))`，返回是否发生压缩；
- `(extension-context-reload context)`，返回 reload report，并立即使旧
  context stale；
- `extension-context-mode` 返回当前模式的 `:repl`、`:tui`、`:text`、
  `:json` 或 `:rpc`；
- dialog/UI 与 runtime action 的精确签名固定在获批提案第 4、7 节。

`extension-event` 稳定导出以下只读 accessor：

- `extension-event-type`
- `extension-event-turn-index`
- `extension-event-message`
- `extension-event-tool-call`
- `extension-event-tool-result`
- `extension-event-tool-results`
- `extension-event-payload`
- `extension-cancellation-aborted-p`

旧四事件继续使用专用 accessor；新增事件 payload 是只读 kebab-case plist。
`extension-cancellation-signal` 是不透明对象，只暴露 aborted 状态。

hook 的唯一修改返回值由
`make-extension-hook-result` 构造，稳定 keyword 为：

- `:replacement`：替换该事件的主 payload；
- `:append-messages`：在该事件提交点追加的合法 `CADR-AI` 消息列表；
- `:block-p` 与 `:reason`：只允许用于 `:tool-call-before`。

`replacement` 的类型由事件决定：

| event | replacement |
|---|---|
| `:turn-start` | 即将持久化并发送的 user message |
| `:turn-end` | 本轮最终 assistant message |
| `:tool-call-before` | `CADR-AI:TOOL-CALL` |
| `:tool-call-after` | `CADR-AI:TOOL-RESULT-MESSAGE` |

多个 hook 串行组合：后一个看到前一个的 replacement 与累计追加消息。
返回类型错误、替换消息 role 错误、tool call/result id 不一致都只使当前
hook 失败；保留上一个合法状态并继续下一个 hook。

工具调用顺序固定为：

1. `:tool-call-before` 链式改写或拦截；
2. 用最终 name 重新解析工具，并用最终 arguments 做 schema 校验；
3. 执行工具；
4. `:tool-call-after` 链式改写结果；
5. 持久化最终结果与 append messages。

因此 hook 不能靠“校验后改参数”绕过 schema。turn replacement 和 append
messages 同样在写入 JSONL 前完成，session 文件仍是运行时语义的唯一事实
来源。需要工具审批的用户可用 `:tool-call-before` hook 实现，核心不内置
审批策略。

### 18.4 热重载与 condition containment

`/reload` 重新发现并把每个入口加载到新的 generation package。
加载成功的扩展形成 staging snapshot；单个扩展加载失败时：

- 首次加载：跳过该扩展，其他扩展继续；
- 热重载：保留该 id 的 last-known-good 定义，其他成功项照常更新；
- 高优先级覆盖项失败时不会偷偷启用被遮蔽的低优先级扩展。

完成全部入口后只做一次加锁指针交换。正在执行的 handler/tool 捕获旧快照，
不会在半次调用中换实现；最后一个旧调用结束后才回收旧 package。registry
交换可回滚，但扩展加载期主动产生的任意外部副作用无法回滚，这一点必须在
README 安全章节明说。

所有边界都捕获 `condition`：

- 加载错误含 extension id、绝对路径与 load 阶段；
- command/hook/tool/template 错误含资源名与执行阶段；
- tool 错误转换成 `is-error` tool result；
- command/template 错误写入当前前端的错误输出；
- hook 错误跳过当前 hook，agent 主循环继续。

用户可见文本先走既有 secret redaction。扩展错误永不终止 agent；只有
cadr 本身的不变量损坏仍按核心错误处理，不能被扩展异常处理器吞掉。

### 18.5 安全模型

对齐固定 TS 基线：扩展发现后默认直接加载，工具默认直接执行，不建立信任
账本、首次加载确认、内容 fingerprint 审批或 `--yolo` 分支。扩展是进程内
任意代码，package 隔离和 condition containment 只解决命名冲突与可靠性，
不提供权限隔离。

README 必须明确：

- 在不可信仓库运行 cadr 等价于允许该仓库中的项目扩展执行任意本机代码；
- 需要强隔离时应在容器、虚拟机或受限用户中运行；
- 需要逐工具审批时，可加载文档提供的最小
  `:tool-call-before` Lisp hook 扩展，审批策略不进入核心。

### 18.6 `/install` 与 Lisp package/skill

`/install <git-url>` 对齐固定 TS 基线的 URL 规则：无 `git:` 前缀时只接受
显式 `http://`、`https://`、`ssh://` 或 `git://`；有 `git:` 前缀时兼容
历史 shorthand（包括 `git@host:path`）。拒绝本地路径、`file://`、以 `-`
开头的值、NUL、反斜杠和含 `..` 的仓库路径。
实现通过 argv 列表调用 `git clone -- <url> <staging>`，绝不拼 shell
字符串。

clone 目标先放在 `~/.cadr/extensions/.staging-<random>/`。成功后验证：

1. 顶层存在 `extension.lisp`；
2. 推导出的目录名只含安全字符；
3. canonical entry 与所有加载文件不逃出 clone 根；
4. 最终目标不存在，禁止静默覆盖已有扩展。

验证通过后原子 rename 到全局扩展目录，再走正常 `/reload`。
扩展加载失败不会破坏 REPL；安装目录保留，便于用户审计或修复。
一个 git package 的 tools、commands、skills 与 prompt templates 全部由其
Common Lisp `extension.lisp` 注册，不引入 npm、JavaScript 或 Markdown
skill 运行时。

### 18.7 Phase 7 测试门禁

实现前先加入以下回归：

1. 四个注册宏的 happy path、参数错误、注册上下文外调用；
2. 独立 package、确定性发现、global/project/CLI 覆盖与冲突诊断；
3. 四类 hook 的链式 rewrite、append、block、priority 与改写后重校验；
4. 加载期及 tool/command/hook/template 执行期任意 condition 均不杀 agent；
5. reload 原子切换、失败时 last-known-good、运行中调用保持旧快照；
6. 默认无审批加载、无信任账本、路径约束与错误隔离；
7. prompt placeholder 全集、command/template/builtin 解析优先级；
8. 用本地临时 git repo 验证 `/install`、argv 注入防护、目标冲突不覆盖；
9. faux provider 在单次进程内完成“write 新扩展 → `/reload` → 调用新工具”；
10. DeepSeek live smoke 完成同一自扩展闭环；
11. Phase 1–6 全量回归、native build、acceptance smoke 与
    `npm run check` 继续通过。

若实现需要改变上述导出符号、handler arity 或 hook 组合语义，必须重新走
人工确认，而不能在编码中静默漂移。

## 19. Phase 8：TUI 架构

Phase 8 新增独立 ASDF system `cadr-tui`。依赖方向扩展为：

```text
cadr-cli -> cadr-agent -> cadr-ai
   |
   +----> cadr-tui
```

`cadr-tui` 是无 agent 语义的终端组件库，只负责输入解码、Unicode 单元格
布局、组件渲染、ANSI 差分输出和终端生命周期。`cadr-cli/tui.lisp` 是唯一
adapter：它把与 REPL 完全相同的 `CADR-AGENT:AGENT-EVENT` 投影成界面状态，
并把编辑器提交交给现有 prompt/command/template 调度。provider、session、
extension、工具执行与压缩逻辑不得复制进 `cadr-tui`。

### 19.1 渲染模型

组件的共同协议是 `(render component width) -> lines`；
每个 line 的可见宽度不得超过 width。根视图每帧产生纯字符串行数组，
`terminal-renderer` 与上一帧比较：

- 首帧、宽度变化或显式 invalidate 时全量重绘；
- 其余帧只定位并重绘变化行；
- 内容缩短时清除旧尾行；
- 一帧 ANSI 输出包在 synchronized-output 序列中，避免半帧闪烁；
- 光标位置由编辑器返回的逻辑 row/column 决定，不把不可见标记写进业务
  文本。

测试使用 `virtual-terminal` 消费同一份 ANSI 输出，断言屏幕行与光标快照；
真实终端不是单元测试前提。

Unicode 布局以 grapheme cluster 为最小编辑与裁剪单位。组合附加符宽度为
0；CJK wide/fullwidth、emoji、regional indicator 和 ZWJ emoji cluster
宽度为 2；其余可打印字符宽度为 1。ANSI/OSC/APC 序列不计宽，tab 在渲染
边界固定展开为三个空格。编辑器的移动、删除、换行与换行裁剪都不得拆开
cluster。

### 19.2 输入与组件

输入路径支持 legacy、CSI/SS3、CSI-u、Kitty 与 modifyOtherKeys，解析
press/repeat/release 和 native modifiers；`stdin-buffer` 跨 read 保留不完整
ESC/CSI/paste 序列，并在同一批次中按原顺序分离终端能力回复与用户输入。
普通 UTF-8、方向键、Home/End、Delete/Backspace、Enter、Shift+Enter、
Ctrl+C、Ctrl+D、PageUp/PageDown、Escape 和 bracketed paste 均进入同一套
可配置 keybinding matcher。

`multiline-editor` 保存纯文本、grapheme 光标索引和最多 100 条历史；Enter
提交，Shift+Enter 插入换行，paste 原样插入并规范 CRLF 为 LF。编辑器与
单行输入共享按词移动、kill ring、yank/yank-pop 和 undo 语义。固定基线只
提供 undo，不提供 redo，因此核心不增加 redo 栈或绑定。

Phase 8 固定包含以下组件：

- slash、路径与 `@` 文件 autocomplete，使用确定性的 fuzzy 排序；
- overlay stack 的 anchor/尺寸/边距/裁剪、focus/capture、非捕获输入分派
  与 CJK/ANSI 安全合成；
- OSC 11/颜色方案、cell-size 回复，以及 Kitty/iTerm2 图片编码、能力探测、
  删除和不支持终端上的文本 fallback；
- streaming Markdown 文本区：增量文本每帧重新做确定性 block/inline
  渲染，支持标题、列表、引用、围栏代码和行内代码，不等待 message-end；
- 工具块：显示工具名、参数摘要和执行状态，完成后默认折叠，可由 Enter
  展开或收起；
- 状态栏：只读展示当前 model、累计 input/output/cache token、累计成本和
  session id；缺失价格时成本显示 `—`，不得猜价；
- 通用 select-list：过滤、循环上下移动、PageUp/PageDown、Enter 确认、
  Escape 取消；模型与会话选择器复用它。

模型选择只使用 `CADR-AI` 当前模型目录，选择后通过现有 provider
instantiate 路径更新 agent；会话选择只调用现有 session list/switch
路径。两者都是原版已有交互能力，不产生第二套状态源。

### 19.3 终端生命周期与前端选择

`process-terminal` 只支持本项目目标平台 Linux x64 / SBCL 2.4+：

1. 保存 stdin termios；
2. 进入 raw mode，启用 bracketed paste，安装 SIGWINCH handler；
3. 运行 TUI；
4. 在覆盖整个运行期的 `unwind-protect` cleanup 中恢复 termios、handler、
   bracketed paste 与硬件光标。

进入 raw mode 失败时在进入主循环前报错，不能留下部分启用状态。退出、
Ctrl+C、EOF、provider condition 和扩展 condition 都走同一 cleanup。

交互式 stdin/stdout 默认启动 TUI；`--no-tui` 强制使用既有 line REPL。
任一流不是 TTY 时自动使用一次性 text print 模式；`--mode json` 和
`--mode rpc` 分别输出事件 JSONL 与 RPC JSONL。TUI/REPL 继续调用同一个
`dispatch-user-input` 并订阅同一个 agent 事件流；模式选择不复制 agent
状态。

### 19.4 Phase 8 验证门

- `cadr-tui/tests` 覆盖 Unicode width/cluster、换行裁剪、编辑器、paste、
  history、select-list、Markdown、差分输出、resize、尾行清除和虚拟终端
  快照；
- `cadr-cli/tests` 覆盖 `--no-tui`、非 TTY 降级、共享 dispatch、agent 事件
  到工具块/stream/status 的投影，以及 condition 下 terminal cleanup；
- 人工终端验收覆盖真实多轮编码任务、流式输出、工具折叠、模型/会话选择、
  resize、CJK/emoji 输入和异常退出后的 shell 状态。

## 20. Phase 9：原生基础设施与最终依赖边界

Phase 9 保持 provider、agent、extension、session 与前端公开协议不变，只在
其下方替换实现。切换顺序按风险固定为 JSON、CLI 参数、正则评估、HTTP：

1. `json.lisp` 自研 RFC JSON parser/stringifier，统一处理 UTF-8、Unicode
   surrogate、任意精度十进制数字、转义、对象和数组；解析器限制容器嵌套
   深度以正常 condition 拒绝恶意输入，stringifier 拒绝 NaN/Infinity；
   `com.inuoe.jzon` 移除。
2. `arguments.lisp` 自研本项目固定选项语法，支持 `--name value`、
   `--name=value`、重复 `--extension`、flags 与结构化错误；`clingon` 移除。
3. 完整正则引擎不重复造轮子，按 `docs/progress/goal-v2.md` 明确暂缓并保留 `cl-ppcre`；
   glob 遍历、`.gitignore` 解释和 literal grep 仍由项目代码实现。
4. `http.lisp` 自研连接、请求写出、响应解析、content-length、
   connection-close、chunked 和流式 body；TLS 由 `cl+ssl` 提供；
   `dexador` 移除。Content-Length 必须是非负十进制整数，截断 body 明确
   报错；认证 header 值在 transport/API condition 生成前统一脱敏。

同时完成两项无行为变化的依赖收口：生产线程 API 直接使用 `sb-thread`，
工具 JSON Schema 由 `schema.lisp` 原生校验，因而移除
`bordeaux-threads` 与 `cl-jschema`。生产 UTF-8 转换使用 SBCL 原生设施，
移除 `babel`、`flexi-streams` 和 `usocket` 的直接依赖。

最终生产依赖审计的不变量是：

- 两个在册自研例外仅为 `cl+ssl` 与 `cl-sqlite`；
- `cl+ssl` 是唯一加密依赖；`cl-sqlite` 只绑定系统 `libsqlite3`；
- 唯一明确暂缓依赖为完整正则引擎 `cl-ppcre`；
- 其他 `.asd` production system 依赖均为本项目 system 或 SBCL/ASDF
  自带设施；
- 测试 system 可保留历史库以构造独立 fixture 和对照，但生产源码不得
  引用它们。

Phase 9 的回归门包括原生 JSON、CLI、schema、真实 loopback HTTP、chunked、
SSE 无界 read timeout、全部旧测试、native image、DeepSeek 普通流式、
自扩展与真实 TUI smoke。实现和性能证据记录在
`docs/progress/phase-9.md`。

## 21. cadr 命名与数据迁移边界

命名迁移只改变身份、路径与一次性兼容入口，不改变 provider、agent、
session、extension 或 TUI 语义。迁移前已验收基线为
`c07b5a668`，该提交及其全部祖先在当前分支可达。

公开命名固定为：

```text
cadr-cli -> cadr-agent -> cadr-ai
    |
    +----> cadr-tui
```

ASDF production/test system、目录、CL package 和 native image 均使用该
命名。扩展稳定接口 `DEFINE-TOOL`、`DEFINE-COMMAND`、
`DEFINE-EVENT-HOOK`、`DEFINE-PROMPT-TEMPLATE`、`DEFINE-PROVIDER` 及 Wave 2
获批 context/event accessor 从 `CADR-AGENT` 导出；此次迁移后命名空间冻结，
不再提供旧 nickname 或别名。

用户数据根目录为 `~/.cadr/`。启动时只有在旧目录存在且新目录不存在时
进入迁移门：

1. stdin 必须是 TTY，且原始 argv 不得含 `--yolo`；
2. 用户明确回答 `y` 或 `yes` 后，以同文件系统 rename 移动整个目录；
3. 迁移后的 `auth.json` 强制为 `0600`；
4. 拒绝、EOF、非交互或 `--yolo` 都返回 configuration condition，并给出
   可直接执行的、正确 shell quoting 的手动 `mv` 命令；
5. 移动或权限修复失败时尝试把目录 rename 回原位置并 fail closed。

`--yolo` 仍不是 CLI 选项，也不重新引入工具确认机制；迁移门只在旧目录
确实待迁移时检查原始 argv，以确保它绝不成为数据移动授权。

新配置读取 `CADR_PROVIDER`、`CADR_MODEL`、`CADR_BASE_URL`。旧前缀仅在
`0.1.x` 作为缺省回退读取，每次实际采用旧值都向 stderr 打弃用警告；新值
始终优先。兼容入口在 `0.2.0` 删除。session v1/v2 header 不含产品名字段，
因此读取格式无需增加别名或重写逻辑。

## 22. 北极星 Wave 2：harness、session v3 与进程模式

Wave 2 沿用原版的 storage/repository 分层：`harness-session` 只依赖统一
storage contract；memory、严格 JSONL 与 SQLite 是可替换 adapter，不另建
第二套 agent 状态。SQLite 使用原版表、索引、`001_initial.sql` migration、
WAL、FULL synchronous、busy timeout、事务 append、branch materialization
与 materialized stats。Wave 5 仍只负责独立 storage package、server 和 eval
集成，不再重复实现这层 adapter。

coding-agent session 新写入版本为 v3。header 使用 ISO-8601 timestamp、
可选 `parentSession`；entry envelope 使用 `id`、`parentId`、timestamp，
支持 message、thinking/model change、compaction、branch summary、custom、
custom message、label 与 session info。agent harness storage 另使用原版已有的
`active_tools_change` 和 `leaf` 记录。v1/v2 迁移保留未知字段并通过同目录临时
文件原子替换；发现阶段最多扫描每个候选 1 MiB，坏 JSONL record 和崩溃尾
跳过。coding-agent manager 在首个 assistant entry 前只缓冲、不创建文件。
compaction 不再写非参考 `sourceIds`；完整原节点仍留在 append log 中，
`firstKeptEntryId` 和 parent tree 提供追溯。

agent runtime 具有原版 steering、follow-up 与 next-turn 队列。steering 在
turn 开始和完整工具批次结束后注入；follow-up 只在 agent 本应停止时 drain；
abort 清空前两者但保留 next-turn。每类队列支持 `one-at-a-time` 与 `all`，
queue event 总是携带两个 live queue 的完整快照。retry、compaction 与
extension lifecycle 都走同一 event spine。

模式优先级固定为显式 `--mode`、`--print`、显式 `--no-tui`、非 TTY 自动
text、最后 TUI。text 只输出最终文本；JSON 输出逐行 agent event；RPC 使用
LF 分帧并兼容 CRLF、U+2028/U+2029 与无末尾 LF。RPC 实现固定 command
union、一次 response、event 转发、session 控制、bash/abort、EOF cleanup
和 extension UI request/response；它是 Wave 5 server 的复用边界，本 Wave
不实现 server。

扩展 API 的限定扩大只包含审计提交已有的 lifecycle events、RPC UI surface
与 runtime provider/tool/message/session actions。`define-event-hook` 原签名、
四个旧事件与旧结果语义不变；兼容门禁
`LEGACY-EXTENSION-SOURCE-REMAINS-COMPATIBLE-AFTER-WAVE-2-API-EXPANSION`
冻结这一点。runtime provider overlay 属于 extension host，不修改
`cadr-ai` registry；TUI 组件层同样未改。完整事件、payload、Lisp 映射与
逐项 `file:line` 基线见
[`docs/proposals/goal-v7-extension-api.md`](proposals/goal-v7-extension-api.md)。

Goal 7 收尾时的 extension export 文本 SHA-256 为
`cc8e7d180b5007cbf4daa66ff904f8c0714992df646211c232135500efd936e7`。
Goal 8 Part B 预裁第 0.5(3) 随 provider request lifecycle 新增公开
`provider-request-replacement` 三项导出，因此该 SHA **不再保持不变**；当前
重冻锚点为
`e89a7f84962c539bfab1645df4867a8f3b587ae46201865abcf9d2b503dc068a`，
旧源兼容 fixture SHA-256
`e2548662d773edfa21ecfa3b126b2209404a2b27385e6cd48e1f145a41747442`，
RPC wire/process fixture SHA-256
`6dc3a25271080a59c3380704044c435a0a20a972c5ba19f32cae2acee2649b10`，
UI extension fixture SHA-256
`c1148870a539dd4a24001da74d17f668b6092bf55d41d845319d5439e3df9486`。
逐文件 Git object ID 记录在提案第 9 节；此后该扩大面恢复“发布即稳定”。
