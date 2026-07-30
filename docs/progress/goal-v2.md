# GOAL v2: pi-cl 全量功能对齐与纯 Lisp 生态化

## 〇、与 v1 的关系

本 goal 在 v1 交付物（pi-ai / pi-agent / pi-cli 三个 system，249 项测试全绿）基础上继续，不推翻既有架构。v1 的一切纪律继续生效：测试先行、阶段门禁、每阶段可运行产物、对拍验证、诚实报告。docs/architecture.md 随每阶段同步更新。

## 一、总体目标

最终交付一个**功能语义完全对齐原版 pi**（earendil-works/pi，沿用 v1 固定的审计提交）的 Common Lisp 实现，并确立一条生态原则：

> **扩展生态完全是 Lisp 的。** 扩展、skill、prompt template 全部用 Common Lisp 编写和加载。不追求加载原版 TS 扩展，不内嵌 JS 运行时。原版扩展生态的"能力"要对齐（能做到的事一样多），"格式"不兼容（这是语言迁移的既定决策，写入 README 差异章节）。

## 二、自研与依赖原则（重要）

1. **默认自研**：凡属协议解析、算法、渲染、数据结构的部分，优先纯 Lisp 自己实现，逐步替换 v1 引入的第三方库。每替换一个库，必须先让自研实现通过该库原有职责对应的全部测试，再切换，最后从 .asd 依赖中移除。
2. **唯一例外——TLS**：HTTPS 的加密层允许通过 FFI 绑定系统 OpenSSL（cl+ssl 或自写薄绑定）。禁止自研密码学。HTTP 客户端本身（连接管理、请求写出、响应解析、chunked 编码、流式读取）要自研，使 dexador 可被移除。
3. 自研模块一律配独立测试套件，且必须通过 v1 已有的全部回归测试（尤其 SSE 的 UTF-8 切割 fixture）。
4. 替换顺序由风险从低到高排：JSON → CLI 参数解析 → glob/正则中用到的子集 → HTTP 客户端。cl-ppcre 的完整正则引擎自研成本极高，允许保留到最后，作为独立可选阶段。
5. SBCL 自带设施（sb-thread、sb-bsd-sockets、uiop/asdf）不算第三方依赖，鼓励使用。

## 三、功能范围：对齐原版的全量清单

以下按阶段排列。每一项都以原版对应源码为行为参照，差异必须记录在 README 的差异清单中。

### Phase 5：Provider 完备化
- 新增 **OpenAI Chat Completions 协议 adapter**（/v1/chat/completions，含流式），这是接入 DeepSeek、开源推理服务（vLLM、Ollama）等大多数厂商的通用协议。
- 建立 **provider 注册表**：每个 provider = 协议 + base-url + 认证方式 + 默认模型 + key 环境变量。内置：anthropic、openai、google、deepseek（走 Anthropic 兼容或 Chat Completions，实现时测试后择优）、ollama（本地）。
- 支持 `--base-url` / 配置文件覆盖任意 provider 的地址。
- 静态模型目录：内置一份模型元数据表（上下文窗口、是否支持工具/思维链），提供更新脚本从各家公开数据刷新；含价格数据与用量成本计算（对齐原版 usage 展示）。
- 图片输入：消息模型增加 image content（base64），三种协议各自正确编码；不支持图片的 provider 明确报错而非静默丢弃。
- **OAuth 认证支持**：
  - provider 认证抽象为 `api-key | oauth` 两种方式，协议 adapter 不变，仅认证头构造不同。
  - 实现标准 PKCE 授权流程：本地一次性回调 HTTP 服务（纯 Lisp 自研，符合第二节自研原则）、打开浏览器授权、code 换 token。做成 `/login <provider>` 与 `/logout <provider>` 命令。
  - token 存储于 `~/.pi-cl/auth.json`，文件权限强制 0600；access token 过期用 refresh token 静默续期，续期加锁防止并发请求重复刷新；token 适用与 API key 完全相同的脱敏红线（不进日志、不进 condition 报告、不进会话文件）。
  - 第一优先级为 **OpenAI Codex OAuth**（复用 v1 已实现的 Responses API 协议路径），授权端点、client ID、请求头构造以固定参考提交中 pi 原版实现的实际行为为准，不自行发明。
  - Anthropic OAuth（Claude 订阅）实现相同接口结构，但标记为**未验证**（无订阅账号可测），README 中如实注明。
  - README 差异清单中注明：订阅 OAuth 通道在各家条款中通常限定官方客户端使用，第三方工具使用该通道的条款风险由使用者自担。

### Phase 6：会话系统对齐
- 会话由线性升级为**树形**：每条消息含 id 与 parent-id，支持从任意历史节点分叉继续（对齐原版 branch 语义）。JSONL 格式升级为 v2，提供 v1 → v2 迁移，旧会话可无损读取。
- **会话压缩**：上下文接近模型窗口上限时，将较早消息总结压缩（调用当前模型完成总结），保留压缩摘要节点与原始节点的引用关系，可追溯。
- 会话列表、切换、`--resume <id>`、HTML 导出（自研极简 HTML 生成，无需模板库）。

### Phase 7：Lisp 扩展系统（本 goal 的核心）
- 扩展 = 一个 `.lisp` 文件或一个含 `extension.lisp` 的目录，通过受控的 `load` 进入独立 package。
- 扩展 API（导出自 pi-agent，保持稳定）：
  - `define-tool`：注册新工具（名称、描述、JSON Schema、执行函数、执行模式）
  - `define-command`：注册 REPL 斜杠命令（如 /compact、/model）
  - `define-event-hook`：订阅 agent 生命周期事件（turn 开始/结束、工具调用前后），hook 可以拦截、改写、追加消息——对齐原版扩展能干预 agent 行为的能力
  - `define-prompt-template`：具名提示模板，REPL 内以 /name 展开
- 加载来源与优先级：`~/.pi-cl/extensions/`（全局）、`./.pi-cl/extensions/`（项目级，覆盖全局同名项）、`--extension <path>`（一次性）。
- **热重载**：`/reload` 命令重新 load 全部扩展；扩展加载或执行中的任何 condition 都被捕获，报告错误并保持 agent 存活，绝不允许扩展错误击穿主循环。
- **自扩展能力验收**：agent 必须能在一次会话中，用自己的 write 工具写出一个新扩展文件、/reload、然后在同一会话内成功调用这个新工具。这是"self-extensible"的核心语义，作为硬性验收项。
- 安全：扩展是任意代码，加载即执行。首次加载某路径的扩展时向用户显示路径并要求确认（--yolo 跳过）；项目级扩展目录尤其如此（防止 clone 恶意仓库即中招）。
- skills / package 安装（从 git URL 拉取扩展目录到全局扩展目录）建立在同一机制上，`/install <git-url>` 实现为内置命令。

### Phase 8：TUI（自研，对齐 pi-tui）
- 纯 Lisp 实现差分渲染终端 UI：ANSI escape 序列输出、终端尺寸探测与 resize 处理、宽字符（CJK/emoji 按 Unicode East Asian Width 计宽）、按行 diff 只重绘变化区域。
- 组件：多行编辑器输入框（光标移动、历史、粘贴）、流式 markdown 渲染文本区、工具调用折叠块、状态栏（模型、token 用量、成本）、选择列表（模型/会话选择）。
- 原始终端模式的进入/退出必须异常安全：任何 condition 下都要恢复终端状态（unwind-protect 全覆盖），崩溃不留下坏终端。
- REPL 模式保留为 `--no-tui` 降级路径，两种前端共享同一 agent 事件流，前端只是事件的不同渲染器——这是架构约束，禁止 TUI 分支携带独立业务逻辑。
- TUI 的测试策略：渲染层以"虚拟终端缓冲区"做快照测试（输入事件序列 → 断言缓冲区内容），不依赖真实 TTY；真实终端行为以人工验收清单覆盖并记录。

### Phase 9：库替换与收尾
- 按第二节的顺序执行自研替换，每替换一项出一份简短报告（被替换库、自研模块、测试证据、性能对比）。
- 最终依赖审计：.asd 中剩余的第三方依赖逐一说明保留理由（预期仅剩 TLS 绑定，或明确列出的暂缓项如 cl-ppcre）。
- 全量回归 + 全部 live smoke（用 DeepSeek 端点）+ 更新 README 与差异清单 + 最终报告。

## 四、验收标准（v2 新增，v1 标准继续有效）

1. `--provider deepseek` 开箱可用（设 DEEPSEEK_API_KEY 即可），Chat Completions 与 Anthropic 兼容两条路径至少一条有录制回放 E2E。
1a. OAuth：使用真实 ChatGPT 账号完成 `/login openai` 后，live smoke 全程走 OAuth 通道（Responses API）跑通；token 刷新逻辑有录制回放测试（过期 → 静默续期 → 请求成功）；auth.json 权限为 0600 的检查含在测试中；日志与错误输出的脱敏测试覆盖 OAuth token。
2. 会话可分叉：从历史某节点继续产生新分支，两分支互不污染，重启后均可恢复。
3. 上下文超限时自动压缩发生且会话可继续，压缩前的完整历史仍可从会话文件追溯。
4. 自扩展验收：单次会话内完成"agent 写扩展 → /reload → 调用新工具"闭环（faux provider 确定性测试 + live smoke 各一次）。
5. 扩展抛出任意错误（加载期与执行期各测）时 agent 存活且给出可读报错。
6. TUI 下完成一次真实多轮编码任务；terminal resize、CJK 输入渲染正确；异常退出后终端状态正常。快照测试覆盖核心组件。
7. 依赖审计报告存在，v1 引入的 dexador、com.inuoe.jzon、clingon 已被自研实现替换并移除。
8. README 差异清单完整列出与原版 pi 的全部已知差异（至少含：扩展语言为 Lisp、不兼容 TS 扩展、其余任何行为差异）。

## 五、风险与原则

- 扩展 API 一旦发布即为稳定接口，Phase 7 设计需经人工确认后再实现（同 v1 的架构门禁）。
- TUI 是最大工程量，允许在 Phase 8 内部再分子阶段，但每个子阶段仍须可运行。
- 自研替换若在某项上遇到超预期成本，允许申请将该项移入"暂缓清单"并说明理由，由人工裁决——不允许静默保留依赖。
- 一切与原版行为不明处，以固定审计提交的源码实际行为为准；不确定时记入 docs/open-questions.md 并暂停询问。
