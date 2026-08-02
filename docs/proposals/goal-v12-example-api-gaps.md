# Goal 12 示例驱动的扩展 API 缺口提案

状态：**19 项能力与补充项 A/B/C 已于 2026-08-02 获得用户逐项批准；继续施工前
发现第 6、10 项仍有两处必经实现面漏列，当前按硬约束再次 blocked。第二次补充
解冻提案见 `docs/proposals/goal-v12-api-scope-amendment-2.md`；获批前不再修改生产 API。**

固定基线：
`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`
（`v0.83.0-38-g74caa2649`）。本文所有 baseline `file:line` 均指该提交。

## 1. 结论与边界

Goal 12 对固定基线的 99 个 runnable examples 逐文件复核后，17 个可在当前冻结
API 内功能等价移植，82 个至少命中一个真实缺口。`examples/manifest.sexp` 是唯一
分类源；`GOAL12-EXAMPLE-MANIFEST-COVERS-EVERY-BASELINE-SOURCE-EXACTLY-ONCE`
锁定 99/99、无重复、无遗漏。

本提案把 42 个机械 gap id 收敛为 19 个可独立裁决的解冻项。收敛原则是同一
runtime contract 只解冻一次，不把同一组 CLOS/bridge 变更拆成伪独立选项。
每项只对齐固定基线已经存在、且被示例真实调用的能力；不增加基线没有的安全、
审批、编排或策略机制。功能等价允许 Lisp 命名与数据表示不同，但禁止用内部符号、
弱化返回值或近似 UI 代替公开合同。

本提案本身不授权第三方依赖。第 11–14 项分别涉及扩展本地依赖、Gondolin、
sandbox runtime 与 WASM；即使能力项获批，引入任何具体依赖前仍须先提交完整闭包、
固定版本/归档 hash 与构建隔离审计，再单独取得依赖授权。

## 2. 当前冻结锚点与共同门禁

开工对象（本提案生成时的 `HEAD`）：

| 路径 | Git object ID |
|---|---|
| `src/cadr-agent/extensions.lisp` | `2ecd00a85c043193e35d5603015376564d460f2c` |
| `src/cadr-agent/package.lisp` | `bcd6088ffd8f8590eb4203bd5171803a6ebf965e` |
| `src/cadr-cli/extensions.lisp` | `6b6acfc13bf0ed416b508f9cffa850891a539b94` |
| `src/cadr-cli/tui.lisp` | `9c6d20fc7ae5e722eacbfd2e5d9eeba4883d1600` |
| `src/cadr-tui/composition.lisp` | `e3c7ad70a5b79060138ddf476cf76f56c4bf1d33` |
| `src/cadr-tui/package.lisp` | `60dc2a97506965d46a6b47003f6c0c8737d360d8` |
| `src/cadr-cli/sdk-services.lisp` | `9e369938415a283ff1a6a12bb52806d08ff89305` |
| `src/cadr-cli/package.lisp` | `18b6bc0effad8cc57f159d44c694718618c1f7e4` |

当前 extension export SHA-256 继续是 architecture 登记的
`bb4665245ef9df19b274535071fcc5f6e56c79ab29db2152cd41afaa4df3b1e0`。

若获批实施，每项共同门禁为：

1. 先加能复现对应示例合同的红测试；旧扩展兼容 fixture、34-event 集、旧宏
   lambda list、旧 payload/handler 顺序全部逐字不变。
2. print/json/rpc/TUI 中未使用新能力的默认路径逐字不变；整屏、15 overlay、
   payload 与 wire fixtures 不允许规范化后比较。
3. 每个获批示例必须有 load/registration/edge-case 行为测试；只有真正可运行的
   Lisp 文件才能把 ledger verdict 改为 `已实现`。
4. 收尾重算逐路径 object ID、extension export SHA、事件集 hash 与 wire fixture
   hash，同步 architecture、README、source-parity 和 parity-map，再重新冻结。
5. 任一实现需要越过本项列出的最小文件面、增加依赖或改变未列出的可观察行为，
   立即 blocked，不得顺手扩面。

## 3. 逐项提案

### 1. UI 可用性判定（`:has-ui-context`）

- **确切需求**：公开只读 `extension-context-has-ui-p`，TUI/RPC 为真，print/json
  为假；与 `mode` 分开，避免扩展自行猜测某 mode 是否有 dialog-capable UI。
- **基线证据**：`packages/coding-agent/src/core/extensions/types.ts:307-314,528-535`；
  `auto-commit-on-exit.ts:41-47`、`permission-gate.ts:20-27`、
  `rpc-demo.ts:53-72`。`rpc-extension-ui.ts:255-263` 显式加载 rpc-demo，因此该独立
  client example 是被同一 `hasUI` 缺口传递阻塞，不是自行调用 `hasUI`。
- **涉及示例**：auto-commit-on-exit、confirm-destructive、dirty-repo-guard、
  file-trigger、git-checkpoint、git-merge-and-resolve、inline-bash、permission-gate、
  project-trust、protected-paths、rpc-demo、widget-placement、rpc-extension-ui。
- **非示例影响**：扩展在非交互模式避免弹 UI；不改变核心安全模型。
- **最小解冻**：`src/cadr-agent/extensions.lisp`、`package.lisp` 与各 mode context
  binding tests；无依赖。
- **替代方案及否决**：让扩展从 `mode` 推导会复制 host policy，未来 mode 增减即
  漂移；返回 UI function 是否为空又把实现细节当合同。
- **冻结/回滚**：只增一个 accessor；回滚删除 accessor 与示例，旧 context 不变。

### 2. 完整 custom component 与 overlay（`:custom-ui-runtime`、`:overlay-options`、`:overlay-handle`）

- **确切需求**：`custom` factory 获得 TUI、Theme、Keybindings、done；接受同步或
  异步 Component；支持 inline/overlay、全部 `OverlayOptions`、动态 options、
  `OverlayHandle.setHidden()/isHidden()`、focus/nonCapturing、dispose 与 requestRender。
- **基线证据**：`types.ts:196-213`；`packages/tui/src/tui.ts:126-183`；
  `overlay-qa-tests.ts:31-302,939-1314`、`overlay-test.ts:15-31`。
- **涉及示例**：doom-component/index、handoff、interactive-shell、overlay-qa-tests、
  overlay-test、plan-mode/index、preset、qna、question、questionnaire、snake、
  space-invaders、summarize、tic-tac-toe、todo、tools。
- **非示例影响**：交互扩展的任意自定义 UI；RPC/print/json 继续无 component runtime。
- **最小解冻**：`src/cadr-agent/extensions.lisp/package.lisp`、
  `src/cadr-cli/extensions.lisp/tui.lisp`、`src/cadr-tui/composition.lisp/package.lisp`。
  复用 C1 component/root/overlay 协议，不另造第二套组件模型。
- **替代方案及否决**：当前 `custom` 只传 `done`、忽略 overlay 参数并把值渲染成
  lines，无法表达输入、动画、焦点、dispose；用 select-list 拼近似不等价。
- **冻结/回滚**：新 factory/overlay path 与旧简单 factory adapter 分层；删除新 path
  可恢复旧行为，旧扩展测试保持原样。

### 3. TUI composition 控制面（`:footer-component`、`:header-component`、`:editor-component`、`:working-indicator`、`:working-message`、`:working-state`、`:hidden-thinking-label`、`:theme-access`）

- **确切需求**：补齐 `setFooter`、`setHeader`、`setEditorComponent/getEditorComponent`、
  `setWorkingVisible`、`setWorkingMessage`、`setWorkingIndicator`、
  `setHiddenThinkingLabel` 与可调用 fg/bg/bold/italic 的完整 Theme；恢复默认值语义
  与 component dispose 时序跟基线一致。
- **基线证据**：`types.ts:115-190,249-275`；
  `border-status-editor.ts:107-148`、`custom-footer.ts:12-59`、
  `working-indicator.ts:20-98`、`hidden-thinking-label.ts:21-50`。
- **涉及示例**：border-status-editor、custom-footer、custom-header、modal-editor、
  rainbow-editor、working-indicator、working-message-test、hidden-thinking-label、status-line。
- **非示例影响**：扩展定制 footer/header/editor/streaming loader；默认组件不变。
- **最小解冻**：第 2 项文件面，加 `src/cadr-cli/interactive-components.lisp`；复用
  FooterDataProvider 与 C1 composition。
- **替代方案及否决**：`setStatus`/widget 不能替代组件生命周期；当前 theme summary
  plist 不能替代基线 Theme styling API。
- **冻结/回滚**：每类 replacement 单独保留 default factory；清除扩展即可恢复默认。

### 4. 模型、context、thinking、system prompt 与 session replacement（`:context-usage`、`:thinking-control`、`:model-registry-context`、`:model-control`、`:new-session-action`、`:system-prompt-access`、`:system-prompt-options`）

- **确切需求**：公开当前 model/scoped models、ModelRegistry auth/model lookup、
  `getContextUsage`、get/set thinking、get/set model、`getSystemPrompt`、command-only
  `getSystemPromptOptions` 与 `newSession(...withSession...)` 的 stale-safe replacement。
- **基线证据**：`types.ts:315-392,1331-1353`；`agent-session.ts:2393-2439`；
  `border-status-editor.ts:51-53,130-133`、`handoff.ts:89-191`、
  `prompt-customizer.ts:88-91`、`system-prompt-header.ts:8-16`。
- **涉及示例**：border-status-editor、trigger-compact、custom-compaction、handoff、
  preset、qna、summarize、prompt-customizer、system-prompt-header。
- **非示例影响**：模型/会话控制型扩展；会改变 session 时必须沿用既有 before/after
  lifecycle 与 withSession 新 context。
- **最小解冻**：`src/cadr-agent/extensions.lisp/package.lisp`、
  `src/cadr-cli/extensions.lisp`、session/model bridge 所在既有 CLI 文件；
  `src/cadr-ai` 保持冻结，若做不到立即 blocked。
- **替代方案及否决**：从 agent/session 私有 slot 读取绕过 provider auth、capability
  clamp 与 stale replacement；手写 prompt 构造会偏离基线。
- **冻结/回滚**：只增 context/API actions；旧 agent/session public behavior 不变。

### 5. 命令/工具 introspection 与 extension event bus（`:command-introspection`、`:tool-introspection`、`:extension-event-bus`）

- **确切需求**：公开 `getCommands`、`getAllTools`（含 source、parameters、guidelines）、
  active tools get/set，以及 host-scoped `events.emit/on`；reload 清理订阅。
- **基线证据**：`types.ts:1331-1340,1430,1563-1571`；
  `packages/coding-agent/src/core/event-bus.ts:3-25`；`commands.ts:20-60`、
  `tools.ts:19-64`、`event-bus.ts:12-43`。
- **涉及示例**：commands、tools、preset、event-bus。
- **非示例影响**：工具集合管理与扩展间通信；event bus 不进入 agent-event/JSON/RPC wire。
- **最小解冻**：`src/cadr-agent/extensions.lisp/package.lisp` 与 CLI host binding；可复用
  C2 `event-bus`，但不得导出 CLI 私有对象。
- **替代方案及否决**：读取 snapshot 私有 struct 会冻结实现布局；用 lifecycle event
  冒充 extension-to-extension channel 会污染事件语义。
- **冻结/回滚**：新增只读快照/action 与独立 bus；删除后旧 registry 不变。

### 6. autocomplete 与 message/entry renderer 完整 runtime（`:autocomplete-provider-runtime`、`:message-renderer-runtime`、`:entry-renderer-runtime`）

- **确切需求**：autocomplete factory 获得完整当前 provider 且 signal/cwd/结果合同
  对齐；message renderer 获得 `(message, expanded/outputPad, theme)`，entry renderer
  获得 `(entry, expanded, theme)`，返回真实 Component 并有 invalidate/dispose。
- **基线证据**：`types.ts:124-125,225,1281-1291`；
  `github-issue-autocomplete.ts:89-119`、`message-renderer.ts:15-33`、
  `entry-renderer.ts:20-39`。
- **涉及示例**：github-issue-autocomplete、message-renderer、entry-renderer。
- **非示例影响**：扩展补全与自定义 transcript/session entry。
- **最小解冻**：`src/cadr-agent/extensions.lisp/package.lisp`、
  `src/cadr-cli/tui.lisp`，复用 C1 Component；无依赖。
- **替代方案及否决**：当前 renderer 只传两个 Lisp 值且最终退化成 line list；缺 theme
  和 component lifecycle，不能称等价。
- **冻结/回滚**：新 renderer signature 通过独立 macro/adapter 增加，不改现有宏 lambda list。

### 7. 工具 metadata、render contract 与 terminate（`:tool-definition-metadata`、`:tool-render-contract`、`:tool-termination`）

- **确切需求**：工具定义支持 `label`、`promptSnippet`、`promptGuidelines`、
  `constrainedSampling`、`renderShell`、prepareArguments；renderer 获得完整 Theme、
  ToolRenderContext、partial/expanded/error 状态；tool result 支持基线 `terminate: true`。
- **基线证据**：`types.ts:446-501`；`agent-session.ts:2492-2500`；
  `structured-output.ts:20-65`、`built-in-tool-renderer.ts:31-249`、
  `minimal-mode.ts:65-374`。
- **涉及示例**：dynamic-tools、hello、kimi-deferred-tools、reload-runtime、
  structured-output、built-in-tool-renderer、minimal-mode。
- **非示例影响**：模型 system prompt 中的工具清单、TUI 工具块和 agent run 终止。
- **最小解冻**：`src/cadr-agent/extensions.lisp/package.lisp`、tool adapter、
  `src/cadr-cli/tui.lisp`；不改 `cadr-ai:tool` wire，若 metadata 无法留在 extension
  definition 层则 blocked。
- **替代方案及否决**：把 label 塞进 description 会污染喂给模型的字节；独立
  `define-tool-renderer` 当前缺完整 render context；把 terminate 当 error 会改语义。
- **冻结/回滚**：metadata 留在 bundle，旧 define-tool 默认值保持原输出；terminate
  默认 nil。

### 8. 工具执行控制面（`:tool-execution-context`、`:cancellation-signal-construction`）

- **确切需求**：extension tool handler 获得 call-id、arguments、可主动 abort 的 signal、
  partial `onUpdate`、完整 ExtensionContext；公开 built-in tool factory operations/spawnHook
  seam；补 `ctx.shutdown()`；允许 manual cancellation signal construction/abort。
- **基线证据**：`types.ts:300-346,476-486`；
  `bash-spawn-hook.ts:14-28`、`shutdown-command.ts:15-60`、`ssh.ts:111-205`、
  `timed-confirm.ts:45-65`。
- **涉及示例**：bash-spawn-hook、gondolin、sandbox、shutdown-command、ssh、
  subagent/index、timed-confirm。
- **非示例影响**：长工具取消、进度更新、远端/替换 backend、优雅 shutdown。
- **最小解冻**：`src/cadr-agent/extensions.lisp/package.lisp/execution-env.lisp`、
  `src/cadr-cli/extensions.lisp` 与现有 tool factories；不改变核心默认工具执行结果。
- **替代方案及否决**：轮询 `extension-cancellation-aborted-p` 但不能构造/abort 不足；
  扩展直接调用私有 CLI tool handler 无 update/context 且绕过 registry。
- **冻结/回滚**：新 handler adapter 与 factory seam 有默认旧 adapter；旧三参 handler
  兼容门禁必须保持。

### 9. 文件 mutation queue 与 truncation utilities（`:file-mutation-queue`、`:truncation-utilities`）

- **确切需求**：把 per-path serialized mutation queue、truncate head/tail/line 的完整
  result contract 作为扩展 public utility；UTF-8/line/byte 口径跟 built-in tools 相同。
- **基线证据**：`packages/coding-agent/src/core/tools/file-mutation-queue.ts:1-43`、
  `truncate.ts:1-222`；`tool-override.ts:24,54-66`、`truncated-tool.ts:24-25,91-121`。
- **涉及示例**：tool-override、truncated-tool、subagent/index。
- **非示例影响**：扩展与内置工具并发写同一路径时避免丢更新；大输出一致截断。
- **最小解冻**：导出/移动现有 `src/cadr-cli/tools/path.lisp` 与
  `truncation.lisp` 的通用实现到不依赖 CLI 的共享层，package/ASD 随之调整。
- **替代方案及否决**：每个示例自建 mutex 不能与内置工具共享队列；复刻截断算法会
  再次产生数值口径漂移。
- **冻结/回滚**：内置工具改为调用同一 public utility，输出 fixtures 必须逐字不变。

### 10. 扩展 provider OAuth（`:extension-provider-oauth`）

- **确切需求**：扩展注册的 provider 可提供 login/refresh/getApiKey、auth prompts、
  model projection 与 custom stream；进入 `/login`、credential store、refresh lock、
  model catalog 和默认 route，provider identity 始终一致。
- **基线证据**：`types.ts:1364-1475`；
  `custom-provider-anthropic/index.ts:574-610`、
  `custom-provider-gitlab-duo/index.ts:381-404`、同目录 `test.ts:19-82`。
- **涉及示例**：custom-provider-anthropic、custom-provider-gitlab-duo/index、test。
- **非示例影响**：第三方订阅/企业 SSO provider；OAuth 凭据安全边界。
- **最小解冻**：`src/cadr-agent/extensions.lisp/package.lisp`、
  `src/cadr-cli/extensions.lisp/model-services.lisp`；优先适配现有 `runtime-provider`
  callbacks。若必须修改 `src/cadr-ai`，立即 blocked，另交精确四层 contract 提案。
- **替代方案及否决**：仅注册静态 base-url/models 是当前已有能力，不能证明登录、刷新
  或自定义 stream；让示例直接写 auth.json 绕过 store/lock 属高危。
- **冻结/回滚**：provider overlay 随 bundle reload 原子替换；卸载后移除 auth method/
  models，但不删除已存用户凭据。

### 11. 扩展本地依赖解析（`:extension-dependency-loader`）

- **确切需求**：目录扩展可声明并加载自身目录中的 ASDF system，解析作用域不污染
  Cadr 全局构建；错误包含扩展路径与 system 名；reload 可重复。
- **基线证据**：`with-deps/index.ts:1-31` 与同目录 `package.json:1-22`；基线通过
  extension 自身 `node_modules` 解析固定 `ms@2.1.3`。
- **涉及示例**：with-deps/index。
- **非示例影响**：所有有自有 Lisp 依赖的第三方扩展。
- **最小解冻**：`src/cadr-cli/extensions.lisp`、新的 extension-local ASDF source-registry
  helper 与 tests。示例可用仓内本地 duration ASDF system 验证机制；不自动联网、
  不自动 Quickload 未授权库、构建 image 不烘入用户扩展。
- **替代方案及否决**：要求把所有扩展依赖加入 Cadr 主 ASDF 会污染发行闭包；自动
  Quicklisp install 引入供应链与不可复现行为。
- **冻结/回滚**：无声明时 loader 路径逐字不变；删除 helper 即恢复现状。

### 12. Gondolin micro-VM（`:gondolin-dependency`）

- **确切需求**：等价提供 VM filesystem/process backend、`/workspace` write-through、
  其他路径隔离、取消/截断和 read/write/edit/find/grep/ls/bash routing。
- **基线证据**：`gondolin/index.ts:1-531`；`package.json:1-19` 固定
  `@earendil-works/gondolin@0.12.0`，并要求 QEMU。
- **涉及示例**：gondolin/index。
- **非示例影响**：强隔离 tool backend；这不是 Cadr 默认安全边界。
- **最小解冻**：第 8/9 项 tool backend seam 加独立 example adapter；**具体 Lisp/
  helper 依赖尚未授权**，必须先给出候选 artifact、闭包、hash、QEMU platform matrix。
- **替代方案及否决**：把普通 subprocess/container 称为 Gondolin 不等价；把 Node
  runtime 带回 native image 违背当前构建边界。
- **冻结/回滚**：extension opt-in，默认工具/README 安全立场不变；卸载即回滚。

### 13. OS sandbox runtime（`:sandbox-runtime-dependency`）

- **确切需求**：等价实现 macOS sandbox-exec/Linux bubblewrap 的 network/filesystem
  policy、config merge、user-bash 与 bash override、reset lifecycle。
- **基线证据**：`sandbox/index.ts:1-321`；`package.json:1-19` 固定
  `@anthropic-ai/sandbox-runtime@0.0.26`，Linux 另需 bubblewrap/socat/ripgrep。
- **涉及示例**：sandbox/index。
- **非示例影响**：用户显式安装扩展时的 OS sandbox；核心仍默认 YOLO。
- **最小解冻**：第 8 项 backend seam 与独立 example adapter；**具体依赖未授权**，
  实施前必须审计闭包、命令发现、policy wire 与平台退化行为。
- **替代方案及否决**：复用审批 hook 不是隔离；仅过滤命令字符串不是 OS sandbox。
- **冻结/回滚**：完全 opt-in；删除扩展恢复默认直接执行，不加入 core policy。

### 14. DOOM WASM runtime（`:doom-runtime`）

- **确切需求**：加载仓内 `doom.js/doom.wasm` 等价模块、挂载 WAD、tick、framebuffer
  ARGB→RGBA、按键注入与 35 FPS overlay lifecycle。
- **基线证据**：`doom-overlay/doom-engine.ts:1-173`、
  `doom-component.ts:1-132`、`index.ts:22-70`；构建 artifact 位于
  `doom-overlay/doom/build/doom.wasm`。
- **涉及示例**：doom-engine、doom-component、doom-overlay/index。
- **非示例影响**：无；纯示例/组件压力验证。
- **最小解冻**：第 2 项 overlay，加独立 WASM adapter；**Common Lisp WASM runtime
  尚未授权**，实施前必须固定实现、闭包、hash 与 native image 打包策略。
- **替代方案及否决**：静态假帧或外部截图不是可玩的 DOOM；恢复 Node 执行 doom.js
  会给 native 发行引入 Node runtime。
- **冻结/回滚**：只存在于 example，删除目录即可；核心不含游戏逻辑。

### 15. SDK session facade（`:sdk-session-facade`）

- **确切需求**：公开 `create-agent-session` 等价入口，组合 cwd/model/tools/
  resource-loader/session-manager/settings/auth/extension factories，返回 session 与
  model-fallback message；支持 prompt/subscribe/dispose。
- **基线证据**：`packages/coding-agent/src/core/sdk.ts:1-398`，入口 `:169`；
  `sdk/01-minimal.ts:8-15`、`05-tools.ts:13-48`、`11-sessions.ts:7-45`。
- **涉及示例**：SDK 01–13 全部。
- **非示例影响**：把 Cadr 作为库嵌入，而不经过 CLI main。
- **最小解冻**：新增 `src/cadr-cli/sdk.lisp`，复用现有 agent/session/tools/
  extension manager；`src/cadr-cli/package.lisp`、`cadr-cli.asd`。
- **替代方案及否决**：调用 `main`/RPC 子进程不是 in-process SDK；让示例复制 CLI
  bootstrap 会产生第二套默认值。
- **冻结/回滚**：新 facade 不接 CLI 默认路径；删除新 module 即回滚。

### 16. SDK resource loader（`:sdk-resource-loader`）

- **确切需求**：公开 DefaultResourceLoader 等价对象，支持 system prompt override/
  append、skills、extensions、context files、prompt templates、reload 与 diagnostics。
- **基线证据**：`resource-loader.ts:195-492`；`sdk/03-custom-prompt.ts:18-63`、
  `04-skills.ts:27-55`、`06-extensions.ts:26-99`、`07-context-files.ts:15-47`、
  `08-prompt-templates.ts:29-51`。
- **涉及示例**：SDK 03、04、06、07、08、12。
- **非示例影响**：嵌入者对资源发现/信任边界的控制。
- **最小解冻**：以 CLOS facade 包装既有 `resource-loader`/extension manager；
  `src/cadr-cli/sdk-services.lisp/package.lisp`，无新依赖。
- **替代方案及否决**：直接传若干 list 无法保留 reload、diagnostics 与 source info。
- **冻结/回滚**：只增 facade；CLI 继续调用既有 loader。

### 17. SDK model runtime 与 auth override（`:sdk-model-runtime`）

- **确切需求**：公开 ModelRuntime 等价 API：catalog lookup、custom provider/model、
  api-key/OAuth/auth overrides、check/resolve/login、refresh 与 per-session visibility。
- **基线证据**：`model-runtime.ts:96-406`；`sdk/02-custom-model.ts:7-38`、
  `09-api-keys-and-oauth.ts:7-34`、`12-full-control.ts:25-74`。
- **涉及示例**：SDK 02、09、12。
- **非示例影响**：嵌入者凭据与自定义模型；敏感面高。
- **最小解冻**：`src/cadr-cli/sdk-services.lisp/package.lisp` 对现有
  `cadr-ai:models-runtime` 的 public facade；`src/cadr-ai` 保持冻结，否则 blocked。
- **替代方案及否决**：示例直接读 auth.json 会绕过 mode、refresh lock 和原子写。
- **冻结/回滚**：不新增 credential format；删除 facade 不改存储。

### 18. SDK settings manager（`:sdk-settings-manager`）

- **确切需求**：公开 disk/in-memory SettingsManager、override precedence、default
  thinking/tools/compaction/retry 等读取写入，并可注入 create-agent-session。
- **基线证据**：`settings-manager.ts:279-1127`；`sdk/10-settings.ts:7-53`。
- **涉及示例**：SDK 10。
- **非示例影响**：嵌入者的持久/临时配置，不改变 CLI 配置 precedence。
- **最小解冻**：CLOS facade 包装现有 CLI settings services；package/ASD，无依赖。
- **替代方案及否决**：只接 plist 缺 disk merge、scope 与 write-back；让嵌入者改全局
  settings 破坏测试隔离。
- **冻结/回滚**：in-memory 与 disk backend 分开；CLI 默认 backend 不变。

### 19. 可替换 AgentSessionRuntime（`:sdk-session-runtime`）

- **确切需求**：公开 services→session factory、runtime wrapper、bind extensions、
  atomic replace/newSession、diagnostics 与旧 session dispose；调用者可替换创建策略。
- **基线证据**：`agent-session-services.ts:134-219`、
  `agent-session-runtime.ts:74-441`；`sdk/13-session-runtime.ts:12-67`。
- **涉及示例**：SDK 13。
- **非示例影响**：长期嵌入进程热切 session；错误实现会泄漏线程/旧 extension context。
- **最小解冻**：第 15 项 facade 加 CLOS runtime protocol；复用现有 stale-context、
  session lifecycle 和 extension attachment generation。
- **替代方案及否决**：在同一 Agent 上原地替换 session slot 会绕过 shutdown/start
  hooks；起新 CLI 进程不具备 in-process replacement。
- **冻结/回滚**：runtime 是 opt-in SDK 对象；CLI 不实例化时行为不变。

## 4. 42 个机械 gap id 到裁决项的完备映射

| 裁决项 | gap ids |
|---:|---|
| 1 | `:has-ui-context` |
| 2 | `:custom-ui-runtime`, `:overlay-options`, `:overlay-handle` |
| 3 | `:footer-component`, `:header-component`, `:editor-component`, `:working-indicator`, `:working-message`, `:working-state`, `:hidden-thinking-label`, `:theme-access` |
| 4 | `:context-usage`, `:thinking-control`, `:model-registry-context`, `:model-control`, `:new-session-action`, `:system-prompt-access`, `:system-prompt-options` |
| 5 | `:command-introspection`, `:tool-introspection`, `:extension-event-bus` |
| 6 | `:autocomplete-provider-runtime`, `:message-renderer-runtime`, `:entry-renderer-runtime` |
| 7 | `:tool-definition-metadata`, `:tool-render-contract`, `:tool-termination` |
| 8 | `:tool-execution-context`, `:cancellation-signal-construction` |
| 9 | `:file-mutation-queue`, `:truncation-utilities` |
| 10 | `:extension-provider-oauth` |
| 11 | `:extension-dependency-loader` |
| 12 | `:gondolin-dependency` |
| 13 | `:sandbox-runtime-dependency` |
| 14 | `:doom-runtime` |
| 15 | `:sdk-session-facade` |
| 16 | `:sdk-resource-loader` |
| 17 | `:sdk-model-runtime` |
| 18 | `:sdk-settings-manager` |
| 19 | `:sdk-session-runtime` |

机械校验必须证明 manifest 中每个 `:gap` 至少一个 id、每个 id 恰好出现在上表
一个裁决项、所有 42 个 id 均有定义。82 个 gap 示例仍逐行保留在
`docs/source-parity.md`；获批并真正移植前不得提前改判。

## 5. 建议裁决顺序

建议按 1→10、15→19、11→14 裁决与实施。前 10 项完成 extension runtime，
15–19 完成无新依赖的 SDK facade；11–14 最后处理生态/外部 runtime，避免依赖问题
掩盖核心 API 缺口。任何单项可独立拒绝或暂缓；被其阻塞的示例继续诚实记为 `缺失`。

用户裁决格式可直接写“1 批准 / 2 暂缓 / …”。第 11–14 项的能力批准不等于依赖
批准；没有后续依赖闭包裁决就不得实现。
