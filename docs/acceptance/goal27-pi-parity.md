# Goal 27：pi 能做的，cadr 都要能做

> **状态：** Goal 27 开工。队列已开，行为尚未落地。不宣布 Goal 20、24、25 或 26 完成。G.17 的状态字由 GAP-50 处理，本文件不开口宣布。
>
> **目标原话（用户 2026-10-23）：** pi 能做的，cadr 都要能做，并持续对齐 pi 最新稳定版（现为 v1.4.0，4a080252）。
>
> **钉点：** `4a080252f06caf63a525d7873c5d94d3c23887e0` · `v1.4.0` +0
> （pi tag `v1.4.0`，短名 `4a080252`）。`BASELINE` 已经指向这一提交。不追 `main`。
>
> **依据：** `docs/reviews/2026-10-23-pi-parity-gap-inventory.md`（50 个 GAP，13 个 Part）。
> 站立约束：`docs/development-policy.md`。
>
> **裁决（顾问 Claude，2026-10-23；用户保留否决权）：** 清单第 3 节写 Still exclude 的各项继续排除。写 Reopen 的各项重开，照清单执行。P1–P8 和 P13 现在开工。GAP-06 作为一行放在 P6，覆盖 mcp、codemode、tool-search 三个内置扩展工厂。P9–P12（GAP-40 Chord、GAP-41 Durable、GAP-42 pi-env、GAP-43 telemetry span）是 pi CLI 不依赖的库，等用户裁决，先不做。
>
> **对齐：** 对齐指可观察行为，结构可以不同；测试断言对着上游 v1.4.0 锁死。

## 方法

1. **范围。** 清单第 2 节的全部 GAP，从 GAP-01 到 GAP-50，每个 GAP 在下面的队列里正好一行。
2. **排除。** 只认清单第 3 节写 Still exclude 的项。那些项不进队列。新增排除需要顾问裁决。第 3 节写 Reopen 的项由对应 GAP 行承接。
3. **开工。** P1–P8 与 P13 的行状态是 `open`。GAP-06 不拆行，只出现在 P6，覆盖 mcp、codemode、tool-search 三个内置扩展工厂。清单第 4 节把 mcp 工厂写在 P5，本裁决把它并进 P6 的这一行。
4. **先不做。** P9–P12 的 GAP-40、GAP-41、GAP-42、GAP-43 状态是 `proposal：待用户裁决（pi CLI 不依赖的库）`。
5. **断言。** 每行落地时，测试锁的是上游 `v1.4.0`（`4a080252`）的可观察行为。结构可以跟 pi 不同。断言不从当前 cadr 输出反推。

## 队列

50 行。`open` 44 行。`done` 2 行。`proposal` 4 行（GAP-40、GAP-41、GAP-42、GAP-43）。出处取清单第 2 节的 pi 文件和 cadr 文件。清单里的 `same` 和短文件名按上一行或同目录展开。

### P1. Lock what already runs

| 面 | 出处 | 状态 |
|---|---|---|
| GAP-20 `tool_call` / `tool_result` | `packages/coding-agent/src/core/extensions/types.ts` → `src/cadr-agent/extensions/registration.lisp` | open：`tool_call` / `tool_result` 别名改写即将执行的参数和进入会话的结果。后一个 `tool_result` 只交 `is-error` 时保留先前的 content 与 details；只替换 content 时丢掉 structured content。拦住的调用不跑 `tool_result`。；review-fail（2026-10-23）：`src/cadr-agent/extensions/context.lisp` 新增 `tool-result-hook-patch-p`、`tool-result-content-blocks-p`、`apply-tool-result-hook-patch`、`merge-tool-result-hook-patch` 四个顶层定义，B9 属主文件的 `(def` 计数在 `a9f4b8358` 是 270、在 `de49eb602` 是 274。`test/cadr-cli/goal14-organization-test.lisp` 的 `goal14-b9-extension-host-has-exact-owners` 仍钉 270，干净检出报 `B9 moved a different top-level definition set: 274`。上游 v1.4.0 没有这条 Lisp 账，cadr 要求改定义的提交同时重记。`src/cadr-ai/package.lisp` 新增导出 `#:tool-result-message-structured-content` 后 SHA256 是 `a6f7d8bb1f2e12dfc48501c482c96e072737a1d6c790fc885969cedb48219dd4`，`goal14-b10-preserves-core-owners-and-frozen-ai-surface` 钉的是 `4655af1de0fe36ba3014b585abcbca20beb68e9ba5e529ba7cef92c94ebc9fa7`，测试报 `B10 changed the frozen cadr-ai public package text`。同一文件在本行之前已被 `a3a58ab98` 改成 `797b43afc313dac2bef2d6c9328dbf13b3eb1e9acfe51eeed256c677ba546e13`（导出 `#:image-model-input-limits`），那一段不是本行独有；本行自己的导出仍然对不上冻结哈希。钩子改写的五条可观察行为与 v1.4.0 的 `types.ts`、`extensions-runner.test.ts`、`agent-loop.test.ts` 一致，但 FiveAM 没有全部通过。 |
| GAP-29 `SIGHUP` | `packages/coding-agent/src/modes/interactive/interactive-mode.ts` → `src/cadr-cli/bootstrap/commands.lisp`，`test/cadr-cli/goal28-exit-and-auth-test.lisp` | done：交互模式收到真实 SIGHUP（win32 除外）或 SIGTERM 时，先杀掉脱离子进程并触发 session_shutdown，再走终端清理，返回 0，且第二次信号不再次触发；打印和 RPC 仍返回 129 与 143，且这次不由该处理器触发 session_shutdown。；review: pass（g27a 线验收，2026-10-23） |
| GAP-44 Copilot model filter | `packages/ai/src/providers/github-copilot.ts` → `src/cadr-ai/providers/runtime-projection.lisp` | done：OAuth 的 `availableModelIds` 是字符串数组时，静态目录只留下这些 id，顺序跟目录一致，未知 id 和重复 id 不增加模型；空数组或大小写不同则一个不留。缺字段、字符串、数字、对象、含非字符串元素，以及 API key，都保留整份目录。未登录时这份目录不出现。；review: pass（g27a 线验收，2026-10-23） |
| GAP-45 Provider retry fields | `settings-schema.ts` → `src/cadr-cli/sdk/settings-service.lisp` | done：`retry.provider.timeoutMs` 和 `retry.provider.maxRetryDelayMs` 进入请求。未设置时超时用 `httpIdleTimeoutMs`，该项为 0 时用 2147483647，延迟用 60000；这两项写成 0 就保持 0；请求里的同名字段优先。旧键 `retry.maxDelayMs` 迁进 `provider.maxRetryDelayMs`，provider 里已有的延迟保留。全局与项目合并后，项目只写 `maxRetries` 时全局的超时和延迟仍在。 |
| GAP-46 Env and settings locks | `packages/coding-agent/docs/environment-variables.md`，`settings-schema.ts` → `src/cadr-cli/bootstrap/commands.lisp`，`src/cadr-tui/terminal.lisp`，`src/cadr-cli/arguments.lisp`，`src/cadr-tui/renderer/lifecycle-input.lisp` | open |
| GAP-47 RPC behavioral tests | `packages/coding-agent/src/modes/rpc/rpc-types.ts` → `src/cadr-cli/modes/rpc/commands.lisp`，`test/cadr-cli/rpc-test.lisp` | open |
| GAP-48 Tool scheduling locks | `packages/agent/README.md`，`packages/ai/src/types.ts` → `src/cadr-agent/extensions/providers.lisp`，`src/cadr-ai/provider.lisp` | open |
| GAP-49 Small option locks | `packages/ai/src/api/openai-completions.ts`，`pi-messages.ts`，`packages/coding-agent/src/utils/clipboard.ts` → `src/cadr-ai/providers/openai-completions.lisp`，`src/cadr-ai/providers/pi-messages.lisp`，`src/cadr-cli/interactive/clipboard.lisp` | open |

### P2. Image catalog

| 面 | 出处 | 状态 |
|---|---|---|
| GAP-17 Image catalog | `packages/ai/scripts/generate-models.ts`，`packages/ai/src/image-models.ts` → `src/cadr-ai/image-models.generated.lisp` | open：`list-image-models` 返回 v1.4.0 快照里的 63 个 OpenRouter 图像模型（含 flux-3、nano-banana-2.1 等新 id）；同一 id 可同时是聊天模型和图像模型；文本输入的 recraft-v4.1-flash 没有 resize 限制。；review-fail（2026-10-23）：`test/cadr-cli/goal14-organization-test.lisp` 的 `goal14-b10-preserves-core-owners-and-frozen-ai-surface` 把 `src/cadr-ai/package.lisp` 的 sha256 钉在 `4655af1de0fe36ba3014b585abcbca20beb68e9ba5e529ba7cef92c94ebc9fa7`（父提交 a3a58ab98^ 仍是这个值）。本行新增导出 `image-model-input-limits` 后该文件摘要变为 `797b43afc313dac2bef2d6c9328dbf13b3eb1e9acfe51eeed256c677ba546e13`。上游 v1.4.0 的 ImageModel 把 `inputLimits` 放在模型对象上（`recraft/recraft-v4.1-flash` 没有该字段，其余 62 个图像模型带 resize），公开包文本的冻结摘要仍须与测试钉一致。干净检出 a3a58ab98 跑 `./scripts/test-cl.sh` 退出码 1。cadr-cli FiveAM 为 Pass 11419、Fail 1、Skip 0，失败信息是 `B10 changed the frozen cadr-ai public package text`。随后进入 debugger，脚本报 incomplete FiveAM accounting，没有 9 条 suite summary。这不是分母漂移，也不是并行临时目录或 git daemon 假失败，未重跑。 |

### P3. Provider auth

| 面 | 出处 | 状态 |
|---|---|---|
| GAP-07 Meta provider | `packages/ai/src/providers/meta.ts`，`packages/ai/src/auth/oauth/meta.ts` → `src/cadr-ai/providers/definitions.lisp` | done：`META_API_KEY` 或 Muse 订阅设备码登录后，向 `https://api.meta.ai/muse-code/key` 兑换一把 24 小时 Model API key；六个 muse 模型走 Responses API（`https://api.meta.ai/v1`），默认模型 `muse-spark-1.3`。；review: pass（g27b 线验收，2026-10-23） |
| GAP-08 ChatGPT sign-in | `packages/ai/src/auth/oauth/openai-chatgpt.ts` → `src/cadr-ai/providers/definitions.lisp`，`src/cadr-ai/providers/openai.lisp` | done：`OPENAI_API_KEY` 仍走 `https://api.openai.com/v1/responses`；Sign in with ChatGPT 用浏览器回调 `http://127.0.0.1:1455/auth/callback` 或粘贴最终重定向，保存签发的 client id 和含 `chatgpt.tokens.use.direct` 的 scopes。订阅访问令牌不带 `max_output_tokens`、`temperature`、`prompt_cache_retention`、`prompt_cache_options`；OAuth 隐藏 `gpt-6-luna` 分类器，同名聊天模型仍在。默认 `agent_name_hint` 是 Cadr，并要求安装级 UUID。 |
| GAP-09 TypeSafe credentials | `packages/ai/src/providers/typesafe.ts` → `src/cadr-ai/classifiers.lisp` | open |
| GAP-11 Anthropic federation | `packages/ai/src/providers/anthropic.ts` → `src/cadr-ai/oauth/providers/anthropic.lisp` | open |
| GAP-12 Azure API version env | `packages/ai/src/api/azure-openai-config.ts` → `src/cadr-cli/arguments.lisp`，`src/cadr-ai/providers/azure-openai.lisp` | open |
| GAP-15 OAuth callback host | `packages/ai/src/auth/oauth/anthropic.ts` and the ChatGPT, Codex, OpenRouter modules → `src/cadr-ai/oauth/callback.lisp` | open |
| GAP-16 `pi-ai` binary | `packages/ai/src/cli.ts` → `src/cadr-cli/models/credential-print.lisp` | open |

### P4. Provider requests and classifiers

| 面 | 出处 | 状态 |
|---|---|---|
| GAP-10 Other classifier APIs | `packages/ai/src/api/openai-decisions.ts`，`packages/ai/src/api/llama-cpp-classify.ts` → `src/cadr-ai/classifiers.lisp` | open |
| GAP-13 Request options | `packages/ai/src/api/openai-responses.ts`，`openai-codex-responses.ts`，`mistral-conversations.ts` → `src/cadr-ai/providers/openai.lisp`，`src/cadr-ai/websocket.lisp`，`src/cadr-ai/providers/mistral.lisp` | open |
| GAP-14 Cache retention env | those API files under `packages/ai/src/api/` → `src/cadr-ai/providers/bedrock.lisp`，`src/cadr-ai/provider.lisp` | open |

### P5. MCP

| 面 | 出处 | 状态 |
|---|---|---|
| GAP-01 MCP client | `packages/mcp/src/client.ts`，`packages/coding-agent/src/extensions/mcp/runtime.ts` → `src/cadr-agent/extensions/mcp-config.lisp` | open：stdio 或 Streamable HTTP 连上后能 `tools/list`（空 `nextCursor` 结束分页）和 `tools/call`（含 structuredContent）；progress 会续上超时，abort 和超时会发 `notifications/cancelled`，initialize 超时不发。；review-fail（2026-10-23）：`test/cadr-cli/goal13-presentation-test.lisp` 的 `goal13-lisp-idiom-audit-covers-the-current-production-file-set` 把 cadr-agent 生产文件数钉在 42、总数钉在 319（`docs/lisp-idiom-audit.md` 仍写 `files=319` 和 `| cadr-agent | 42 |`）。本行新增 `src/cadr-agent/extensions/mcp-client.lisp`、`mcp-http.lisp`、`mcp-protocol.lisp`、`mcp-runtime.lisp`、`mcp-stdio.lisp`。`a0e765a08^` 的 cadr-agent `*.lisp` 是 42 个，HEAD 是 47 个，总数 324。上游 v1.4.0 没有这条 Lisp 文件账，cadr 要求新增生产文件的提交同时重记。干净检出跑 `./scripts/test-cl.sh` 退出码 1，未重跑。cadr-cli FiveAM 为 Pass 11425、Fail 5、Skip 0，本行对应的失败信息是 `cadr-agent source-file count drifted` 和 `TOTAL evaluated to 324 which is not = to 319`。随后进入 debugger，storage、server、evals、protocol 没有跑。同一轮 `B9 changed the frozen extension export text`：`goal14-b9-preserves-core-owners-and-frozen-extension-surfaces` 把 `src/cadr-agent/package.lisp` 从 `#:define-tool` 到 `#:make-extension-hook-result` 的 sha256 钉在 `04a231e373e1e3d3fb1a4bf618fd8c4d1d3eaa710bffb48ca6c006d819578993`。本行把 MCP 客户端导出插进这段。`a0e765a08^` 这段已是 `7df0e19a5e19b049a996c2e27adf6daacbdd6e82666557161c6cb1a101eed8c6`（`e8b23ec25` 起就不等于钉），本行之后是 `247291ea2d499db4800e372ef6a90a65781e0a887aa1e0af47150ee84bc3b3b9`。 |
| GAP-02 MCP resources | `packages/mcp/src/client.ts`，`packages/coding-agent/src/extensions/mcp/resources.ts` → `src/cadr-agent/extensions/mcp-config.lisp` | done：连上的服务器能 `resources/list`（`nextCursor` 为 null 或空字符串就结束，缺 name 时用 URI）、`resources/templates/list`（方法不存在就是没有模板）和 `resources/read`。`list_mcp_resources`、`list_mcp_resource_templates`、`read_mcp_resource` 按 Codex 的 JSON 列出或读取：去掉 `ui://` 和 `profile=mcp-app`、去掉 `_meta` 和 icons，标上 server；不指定 server 时按名字排序并收集失败，cursor 只能和 server 一起用；文本和图片交给模型，其他二进制存进 0600 的临时文件，未知服务器报 `MCP server "…" has no resources`。；review: pass（g27c 线验收，2026-10-23） |
| GAP-03 `pi mcp` CLI | `packages/coding-agent/src/extensions/mcp/cli.ts` → `src/cadr-cli/arguments.lisp`（清单：has `--no-mcp` only） | open |
| GAP-04 MCP OAuth | `packages/mcp/src/oauth/`，`packages/coding-agent/src/extensions/mcp/oauth.ts` → `mcp-config.lisp`，`test/cadr-agent/mcp-config-test.lisp` | open |

### P6. Codemode

GAP-06 只在本表出现一行，覆盖 mcp、codemode、tool-search 三个内置扩展工厂。

| 面 | 出处 | 状态 |
|---|---|---|
| GAP-05 Codemode and its worker | `packages/codemode/`，`packages/coding-agent/src/extensions/codemode/`，`packages/coding-agent/docs/codemode.md`，`settings-schema.ts` → `src/cadr-cli/bootstrap/tools.lisp`，`mcp-config.lisp` | open |
| GAP-06 Builtin extensions | `packages/coding-agent/src/extensions/index.ts` → `src/cadr-cli/extensions/loader.lisp` | open |

### P7. Session, hooks, settings, chrome

| 面 | 出处 | 状态 |
|---|---|---|
| GAP-18 JSONL export | `packages/coding-agent/src/core/session-export.ts`，`interactive-mode.ts` → `src/cadr-cli/interactive/autocomplete.lisp`，`src/cadr-cli/bootstrap/sessions.lisp` | open |
| GAP-19 `cache_warming_decision` | `packages/coding-agent/src/core/extensions/types.ts` → `src/cadr-cli/cache-warmer.lisp`，`test/cadr-agent/extensions-wave3-test.lisp` | open |
| GAP-21 Virtual model registration | `packages/coding-agent/src/core/virtual-models.ts`，`docs/virtual-models.md` → `src/cadr-agent/loop/turns.lisp`，`src/cadr-agent/virtual-models.lisp` | open |
| GAP-22 `compaction.modelOverrides` | `packages/coding-agent/src/core/settings-schema.ts` → `src/cadr-cli/bootstrap/settings.lisp` | open |
| GAP-23 `retry.maxAgentDelayMs` | `settings-schema.ts` → `src/cadr-cli/sdk/settings-service.lisp` | open |
| GAP-37 `--mode text` on a TTY | `packages/coding-agent/src/main.ts` → `src/cadr-cli/arguments.lisp` | open |
| GAP-38 `/share` copy | `packages/coding-agent/src/core/slash-commands.ts` → `src/cadr-cli/interactive/autocomplete.lisp` | open |
| GAP-39 Startup 3D egg | `packages/coding-agent/src/modes/interactive/components/easter-egg-3d.ts` → `src/cadr-cli/interactive/components/daxnuts.lisp`，`pi-logo.lisp` | open |

### P8. Terminal, keys, shell env

| 面 | 出处 | 状态 |
|---|---|---|
| GAP-24 Windows external editor | `packages/coding-agent/src/modes/interactive/extension-editor.ts` → `settings-external-editor-command` in `src/cadr-cli/bootstrap/settings.lisp` | done：未配置 externalEditor、VISUAL、EDITOR 时，Windows 用 notepad，darwin 与 linux 用 nano；已配置命令和这两个环境变量仍然优先。；review: pass（g27d 线验收，2026-10-23） |
| GAP-25 Windows and WSL key defaults | `packages/coding-agent/src/core/keybindings.ts`，`docs/keybindings.md` → `src/cadr-tui/keybindings.lisp`，`src/cadr-cli/interactive/selectors/tree.lisp` | done：win32 或带 WSL_DISTRO_NAME / WSL_INTEROP 的 linux 使用 Windows 键（撤销分别为 ctrl+z 与 alt+z，回退模型 alt+p，排队 ctrl+q，出队 alt+q，贴图 alt+v，跳转 ctrl+up/down，搜索 ctrl+f）；其它平台保持 Unix 键，提示跳转同时有 ctrl+shift 与 ctrl。darwin 的树折叠是 alt 再 ctrl，运行时判断。原生 Windows 的 app.suspend 没有默认键。；review: pass（g27d 线验收，2026-10-23） |
| GAP-26 Windows open URL | `packages/coding-agent/src/utils/open-browser.ts` → `src/cadr-cli/interactive/controller.lisp` | done：Windows 打开链接时执行 `rundll32`，参数是 `url.dll,FileProtocolHandler` 和完整 URL（含 `&` `|` `^` 与引号）；darwin 执行 `open`，其它平台执行 `xdg-open`；找不到启动器时函数返回，不把错误抛给调用方。；review: pass（g27d 线验收，2026-10-23） |
| GAP-27 Windows VT input | `packages/tui/src/terminal.ts` → `src/cadr-tui/renderer/virtual-terminal.lisp`，`src/cadr-tui/terminal.lisp` | open：Windows 上 raw mode 之后把标准输入控制台模式或上 ENABLE_VIRTUAL_TERMINAL_INPUT（0x0200），失败或非 Windows 不改控制台。Shift+Tab 的 ESC [ Z、Kitty 与 modifyOtherKeys 是 shift+tab，普通 Tab 仍是 tab。内存屏幕缓冲不承担这个开关。；review-fail（2026-10-23）：`src/cadr-tui/terminal.lisp` 的 `read-windows-stdin-console-mode` 调用 `%cadr-get-std-handle`（返回类型 `system-area-pointer`），再交给 `windows-invalid-handle-p` 里的 `sb-alien:alien-sap`。`alien-sap` 只接受 `alien-value`，对 `system-area-pointer` 抛 `SIMPLE-TYPE-ERROR`（本机用返回 `system-area-pointer` 的 alien routine 复现，`type=SYSTEM-AREA-POINTER`，`caught=SIMPLE-TYPE-ERROR`）。`apply-windows-virtual-terminal-input` 的 `handler-case` 吞掉该错误，`write-windows-stdin-console-mode` 不会执行，标准输入控制台模式不会或上 `0x0200`。上游 v1.4.0 `packages/tui/native/win32/src/win32-platform.c` 的 `enable_virtual_terminal_input` 在 `GetStdHandle(STD_INPUT_HANDLE)` 有效且 `GetConsoleMode` 成功时执行 `SetConsoleMode(handle, mode | ENABLE_VIRTUAL_TERMINAL_INPUT)`。`write-windows-stdin-console-mode` 对第二次 `GetStdHandle` 走同一条 `alien-sap` 路径。ESC [ Z、Kitty `ESC [ 9 ; 2 u`、modifyOtherKeys `ESC [ 27 ; 2 ; 9 ~` 与普通 Tab 的解析与 v1.4.0 `keys.ts` `parseKey` 和 `keys.test.ts` 一致。 |
| GAP-28 Windows right-click paste | `packages/tui/src/tui-alt-screen.ts` → `src/cadr-tui/renderer/lifecycle-input.lisp` | open |
| GAP-30 tmux keyboard warning | `interactive-mode.ts` → same（上一行 GAP-29 的 cadr 文件：`src/cadr-cli/bootstrap/commands.lisp`，`test/cadr-cli/goal28-exit-and-auth-test.lisp`） | open |
| GAP-31 Self `SIGWINCH` | `packages/tui/src/terminal.ts` → `src/cadr-tui/terminal.lisp` | open |
| GAP-32 `#` autocomplete | `packages/tui/src/components/editor.ts` → `src/cadr-tui/autocomplete.lisp`，`src/cadr-cli/interactive/autocomplete.lisp` | open |
| GAP-33 Shell session env | `packages/coding-agent/src/core/tools/bash.ts`，`docs/environment-variables.md` → `src/cadr-cli/bootstrap/main.lisp` | open |
| GAP-34 Bug-report origin | `docs/environment-variables.md` → `src/cadr-cli/support/bug-report.lisp` | open |
| GAP-35 TUI write log | `packages/tui/src/terminal.ts` → `src/cadr-tui/terminal.lisp` | open |
| GAP-36 Two env names | `packages/coding-agent/docs/environment-variables.md`，`packages/tui/src/terminal.ts` → `src/cadr-cli/interactive/clipboard.lisp`，`src/cadr-tui/terminal.lisp` | open |

### P9. Chord

| 面 | 出处 | 状态 |
|---|---|---|
| GAP-40 Chord | `packages/chord/README.md`，`packages/chord/src/index.ts` → none | proposal：待用户裁决（pi CLI 不依赖的库） |

### P10. Telemetry contracts

| 面 | 出处 | 状态 |
|---|---|---|
| GAP-43 Telemetry spans | `packages/telemetry/src/index.ts`，`packages/ai/README.md` → none | proposal：待用户裁决（pi CLI 不依赖的库） |

### P11. Durable

| 面 | 出处 | 状态 |
|---|---|---|
| GAP-41 Durable | `packages/durable/README.md` → none | proposal：待用户裁决（pi CLI 不依赖的库） |

### P12. pi-env

| 面 | 出处 | 状态 |
|---|---|---|
| GAP-42 pi-env | `packages/env/README.md`，`packages/env/daemon/src/main.rs` → `src/cadr-agent/execution-env.lisp` | proposal：待用户裁决（pi CLI 不依赖的库） |

### P13. Ledger status

| 面 | 出处 | 状态 |
|---|---|---|
| GAP-50 G.17 status | `docs/acceptance/goal-v20-part-g.md` → those acceptance files | open |
