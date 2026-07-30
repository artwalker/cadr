# GOAL: 将 Pi Agent Harness 重构为 Common Lisp 实现

## 一、总体目标

将 https://github.com/earendil-works/pi 仓库中的 pi coding agent 用 Common Lisp（SBCL）完整重新实现，最终交付一个**可在终端运行的、功能对齐原版核心能力的 coding agent 可执行文件**。

以原 TypeScript 项目为参照实现（reference implementation），不是逐行翻译，而是按 Lisp 惯用风格重新设计，同时保证外部行为（API 请求构造、agent 循环语义、工具调用协议）与原版一致。

## 二、范围界定

### 需要实现（按依赖顺序）

1. **pi-ai 对应层**（`packages/ai`）：统一多供应商 LLM API 封装
   - 支持 Anthropic、OpenAI、Google 三家 provider（其余 provider 可后置）
   - 请求构造、流式 SSE 响应解析、token 用量统计、错误归一化
2. **pi-agent-core 对应层**（`packages/agent`）：agent 运行时
   - agent 主循环（用户输入 → LLM 调用 → 工具调用 → 结果回传 → 循环）
   - 工具定义与注册机制（含 JSON Schema 参数校验）
   - 会话状态管理与持久化（会话可保存/恢复）
3. **coding-agent CLI 对应层**（`packages/coding-agent`）：
   - 内置工具：read / write / edit / bash / glob / grep（对齐原版内置工具的行为语义）
   - 配置系统：API key 读取（环境变量）、模型选择、系统提示词
   - 第一版交互界面做成 **REPL 式命令行**：readline 输入、流式纯文本输出、支持多轮对话
   - **在每次执行 bash / write / edit 等有副作用的工具前，向用户请求确认**（原版没有权限系统，这是本次重构要求新增的安全改进；提供 --yolo 标志跳过确认）

### 明确排除（不要做）

- pi-tui 的差分渲染全屏 TUI —— 第一版不做，REPL 式交互即可
- pi-chat（Slack 集成）、任何 Web UI、vLLM pods 相关功能
- 原版的 extension/skill/package 安装系统 —— 不在第一版范围内

## 三、技术约束

- 语言与运行时：**Common Lisp，目标实现为 SBCL**（>= 2.4），最终通过 `sb-ext:save-lisp-and-die` 或等价方式产出单个原生可执行文件
- 构建系统：ASDF，依赖用 Quicklisp 管理；提供一个 `build.sh` 一键构建脚本
- 推荐库（可根据实际情况替换，但需在设计文档中说明理由）：
  - HTTP/流式：dexador（注意 SSE 需要基于流的分块读取，不能等完整响应）
  - JSON：com.inuoe.jzon
  - 并发：bordeaux-threads
  - CLI 参数：clingon 或 adopt
- 错误处理使用 CL condition system 设计分层错误类型（网络错误 / API 错误 / 工具执行错误可区分与重试）
- 代码风格：每个原 TS 包对应一个 CL system（如 `pi-ai`、`pi-agent`、`pi-cli`），包结构清晰，导出符号明确

## 四、执行方式要求（重要）

1. **先产出设计文档再写代码**：第一个交付物是 `docs/architecture.md`，内容包括 TS 模块 → CL system/package 的映射表、异步模型的处理方案（TS Promise/async 如何映射为线程或同步流）、错误处理设计。完成后暂停，等待人工确认后再继续。
2. **测试先行**：每个模块先将原仓库对应的测试用例语义移植为 CL 测试（用 fiveam 或 rove），再实现功能让测试通过。原版测试是行为规格，不是可选项。
3. **分阶段推进，每阶段有可运行产物**，不允许跳阶段：
   - Phase 1: pi-ai 层 —— 交付一个能对三家 provider 发起非流式和流式对话请求的库 + 测试
   - Phase 2: agent 核心 —— 交付一个能跑通「LLM 决定调用工具 → 执行 → 回传 → 继续」完整循环的库 + 测试（工具可先用 mock）
   - Phase 3: 内置工具 + CLI —— 交付可执行的 REPL agent，能在真实项目目录中完成「读文件、改代码、跑命令」类任务
   - Phase 4: 打磨 —— 会话持久化、确认机制、错误重试、构建脚本、README
4. **对拍验证**：对于 API 请求构造，用相同输入分别在原 TS 实现和 CL 实现中生成请求体，逐字段比对（可写一个对拍脚本）。SSE 解析用录制的真实响应流做回放测试，不依赖在线 API。
5. 每个 Phase 结束时输出一份简短进度报告：完成了什么、与原版行为的已知差异、下一步计划。

## 五、验收标准（最终交付必须全部满足）

1. `./build.sh` 在干净的 Linux x64 环境（安装了 SBCL 和 Quicklisp）能一键产出可执行文件 `pi-cl`
2. 设置 `ANTHROPIC_API_KEY` 后运行 `./pi-cl`，能进行多轮流式对话
3. 在一个真实的小型代码仓库中，能通过自然语言指令完成：读取指定文件并总结、修改某个函数、运行测试命令并根据输出继续修复——完整的 agent 循环无人工干预（除工具确认）
4. 三家 provider（Anthropic / OpenAI / Google）至少各有一个端到端测试通过（可用录制回放替代真实 API）
5. 所有移植的测试通过；`docs/architecture.md` 与最终实现一致
6. 有副作用的工具默认需要用户确认，`--yolo` 可跳过
7. 会话可通过 `--continue` 恢复上一次对话
8. README 包含：构建方法、配置方法、与原版 pi 的功能差异清单

## 六、已知风险与处理原则

- SSE 流式解析是最容易出错的部分：各家 provider 的事件格式不同，必须以录制的真实响应做测试基准
- 遇到原版行为不明确处，以原版源码实际行为为准，不要自行发明语义；无法确定时记录在 `docs/open-questions.md` 中并暂停询问
- 不要为了"完整"而堆砌未验证的代码；宁可范围小而全部可运行
