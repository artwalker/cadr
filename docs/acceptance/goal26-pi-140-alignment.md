# Goal 26：pi 基线推进至 v1.4.0

> **状态：** 进行中（钉点改靶）。用户 2026-10-22 明确要求从已发布的
> v1.3.0 改钉到已发布的 **v1.4.0**。不宣布 Goal 20、24、25 或 26
> 完成。G.17 保持 `missing`。`version.sexp` 仍是 `0.2.0`。
>
> **自：** `71023aec1546d6d677a65669c5665c0927ce0dd0` · `v1.3.0` +0
> **目标锚点：** `4a080252f06caf63a525d7873c5d94d3c23887e0` · `v1.4.0` +0
> （pi tag `v1.4.0`，提交说明 `Release v1.4.0`，2026-10-22 00:29:13 +0200）
>
> **作废：** 不改写 `docs/acceptance/goal26-pi-130-alignment.md`。
> 分支 `goal26-pin-v130` 保留为历史，不 merge、不继续追。
> 本分支 `goal26-pin-v140` 从该历史继续。已在 v1.3.0 钉上落地、
> 且 v1.4.0 没有改掉的行为保留。

## 差量

测量 2026-10-22，pi 仓库 `71023aec..v1.4.0`：

```sh
git rev-list --count 71023aec1546d6d677a65669c5665c0927ce0dd0..v1.4.0
git diff --stat 71023aec1546d6d677a65669c5665c0927ce0dd0..v1.4.0 \
  -- packages/coding-agent packages/tui packages/ai
```

81 个提交。上述三包 179 个文件，+5656 / −1497 行。发布说明：
[v1.4.0](https://github.com/earendil-works/pi/releases/tag/v1.4.0)。

## 方法

1. **机械钉点**：`BASELINE` → `4a080252…` / `v1.4.0` +0。
   `scripts/set-baseline.sh` 已改写操作引用。
   `PI_AI_MODEL_DATA_*` → `@earendil-works/pi-ai@1.4.0`，
   tarball SHA-256 `b40e2ba8bb6fc332908f8b96e837dc2d1fdfb45eb9cd382f5aed111462981e3c`
   （`npm pack @earendil-works/pi-ai@1.4.0 --ignore-scripts`）。
   `python3 scripts/baseline-anchor.py check` 通过。
2. **按面落地**：下面的队列只含 coding-agent / tui / ai 的用户可见面。
   每面 port 或裁决，并附 FiveAM 或确定性证据。
3. **不追 `main`。** codemode 执行、worker 排队、`PI_CODEMODE_MAX_WORKERS`
   不 port。三包以外的文件不 port。不合并旧 PR。

## 队列

v1.3.0 账本里已标 done、且 v1.4.0 没有改行为的面，不在此重开。

| 面 | 出处 | 状态 |
|---|---|---|
| 门禁回绿：test-cl.sh 的 cadr-agent 扩展事件数 41 对 39、HTML 导出摘要不一致（钉 v1.4.0 后的既有失败；先查是 v1.4.0 行为变化还是回归，按上游修，不改断言迁就实现） | 既有门禁失败 | done：扩展钩子与 v1.4.0 的 41 个 `ExtensionAPI.on` 事件对齐，`tool_call` / `tool_result` 仍拆成 before、after、error，且不含 `cache_warming_decision`。HTML 导出重新带上隐藏消息开关、`context_edit` 树节点和 `nestedCalls`，样式表与 v1.4.0 逐字节相同 |
| MiniMax-M3.1-Flash，thinking low–max，不能关 | v1.4.0 `models` #11121 | done：`minimax` 与 `minimax-cn` 的 `MiniMax-M3.1-Flash` 可选档是 low、medium、high、xhigh、max。省略思考时不写 `thinking.type=disabled`，选中的档位写入 `output_config.effort`。M2、M2.1、M2.5、M2.5-highspeed 仍不在这两个目录里 |
| xAI Grok 4.3 / 4.5 增加 `xhigh` | v1.4.0 changelog | done：`xai` 的 `grok-4.3` 可选档是 off、low、medium、high、xhigh，`grok-4.5` 是 low、medium、high、xhigh。选中 `xhigh` 时 Responses 请求的 `reasoning.effort` 写成 `xhigh` |
| 默认模型：Copilot `gpt-6.1-sol`，NVIDIA nemotron 3.5，Xiaomi `mimo-v2.6-pro` | v1.4.0 changelog | done：未指定模型时，`github-copilot` 选 `gpt-6.1-sol`（上下文 1050000）；Copilot 关闭思考时不写 `reasoning.effort=none`。`nvidia` 选 `nvidia/nemotron-3.5-super-vl-120b-a12b`，`xiaomi` 和三个 Xiaomi Token Plan 选 `mimo-v2.6-pro`。四个 Xiaomi 目录用 `mimo-v2.6-flash` / `mimo-v2.6-pro` 替换 v2.5 两款，`xiaomi` 另列 `mimo-v2.6-pro-ultraspeed`；review: pass（ai 线验收，2026-10-22） |
| ChatGPT Business 用量上限不重试 | v1.4.0 changelog | done：`subscription_sharing_workplace_individual_usage_limit_exceeded` 即使带 429 也不重试。OpenAI Responses 在错误后另起一行提示用户让工作区管理员到 admin.openai.com → Workspace → Usage limits 提高上限；Codex Responses 不追加这句；review: pass（ai 线验收，2026-10-22） |
| 折叠和分支摘要用模型输出上限；`reserveTokens` 只决定何时开始；`/compact` 指令在被切开的回合开头仍生效 | v1.4.0 #9512 #9075 #11058 | done：折叠、切开回合的前缀和分支摘要请求都不写 `maxTokens`。provider 用模型输出上限，窗口不够时再收紧。`reserveTokens` 只决定自动折叠何时开始。`/compact` 指令在被切开的回合开头仍以 `Additional focus` 生效，哪怕这段前缀是上次折叠后的唯一新内容 |
| 客户端身份、`User-Agent`、OpenRouter / NIM / OpenCode attribution | v1.4.0 `identity.ts` | open：默认 User-Agent 是 `cadr/<版本> (<平台>; sbcl/<实现>; <架构>)`，short 是 `cadr`，自定义字符串原样送出。attribution 默认关闭；开启后 OpenRouter 发送 `https://github.com/artwalker/cadr`、标题 `cadr` 和 `cli-agent`，NVIDIA 发送 `Cadr`，OpenCode 无会话也发送 `x-opencode-client: cadr`，`x-opencode-session` 只在有会话时发往 `opencode.ai`。模型头和请求头覆盖身份头，null 删掉该名；扩展钩子看不到默认 attribution，返回 null 仍能删除。Cloudflare 改发详细 User-Agent。`CADR_TELEMETRY` 为 `0`、`false` 或空字符串时关闭 attribution。Bedrock 签进缩短的 `cadr/<版本>`。Anthropic OAuth 不套这套身份头；review-fail（2026-10-22）：1. `src/cadr-cli/tool-manager.lisp` 的 `latest-tool-version` 用 curl `-A` 发送 `cadr-coding-agent`。上游 v1.4.0 `packages/coding-agent/src/utils/tools-manager.ts` 的 `getLatestVersion` 发送 `getPiUserAgent(VERSION)`，形式是 `pi/<版本> (<平台>; <运行时>/<运行时版本>; <架构>)`。`packages/coding-agent/CHANGELOG.md` 1.4.0 写明 GitHub 工具下载的 release 检查改发这套详细 User-Agent，和不再发送 `pi-coding-agent` 是同一句。2. `src/cadr-ai/classifiers.lisp` 的 `classifier-request-headers` 只放 content-type、authorization、模型头和调用方头，`classify-model` 没有 identity。上游 `packages/ai/src/api/classifier-shared.ts` 的 `requestHeaders` 展开 `getIdentityHeaders`，分类请求带 `formatUserAgent()` 的 User-Agent。`packages/ai/CHANGELOG.md` 1.4.0 写明 classifier requests 也发送 User-Agent。Cloudflare Workers AI 分类请求走 `classify-system-one`，因此没有详细 User-Agent。聊天请求经 `build-request :around` 会带上。3. `docs/lisp-idiom-audit.md` 和 `test/cadr-cli/goal13-presentation-test.lisp` 的 `goal13-lisp-idiom-audit-covers-the-current-production-file-set` 仍写 cadr-ai 66 个文件、合计 318。`2ead34767` 新增 `src/cadr-ai/support/identity.lisp` 之后，该提交的 `src/cadr-ai` lisp 文件是 67 个。干净检出的 FiveAM 报 `cadr-ai source-file count drifted`，合计 319 对 318。4. 状态格写 attribution 默认关闭。上游 `packages/coding-agent/src/core/settings-defaults.ts` 的 `enableInstallTelemetry` 默认 true，`PI_TELEMETRY` 未设置时 `packages/coding-agent/test/sdk-client-identity.test.ts` 期望 attribution 为 `PI_ATTRIBUTION`。cadr 的 `src/cadr-cli/bootstrap/settings.lisp` `install-telemetry-enabled-p` 在 `CADR_TELEMETRY` 未设置时对缺省的 `enableInstallTelemetry` 返回 t，`src/cadr-cli/support/headers.lisp` 的 `coding-agent-client-identity` 因此带上 `+cadr-attribution+`。 |
| 只含空白的工具输出改成和空输出一样的占位 | v1.4.0 #8720 | done：`""`、`\r\n`、空格加换行加 tab 在 OpenAI Responses 和 Completions 上写成 `(no tool output)`，在 Google 上写成空字符串。有可见文字的结果仍原文送出 |
| 重试认更多上游失败、Vertex 令牌刷新、Codex 代理断流；请求号里的数字不当成 HTTP 状态 | v1.4.0 #10920 #11057 #10996 | done：`upstream_error: Upstream request failed`、`upstream_stream_read_error`、`Upstream HTTP/2 stream failed`、`request to … failed, reason:`、`stream disconnected before completion` 会重试。`req_011CU503xyz` 和 `5242880 bytes` 里的数字不当成 HTTP 状态 |
| Responses 在删过工具之后继续加载 deferred 工具时不改写前缀 | v1.4.0 #10940 | open |
| GitHub Copilot HTTP 413 算上下文溢出 | v1.4.0 #11016 | done：任意提供方的 HTTP 413 都算上下文溢出，包括 `github-copilot API error (413): {"message":"failed to parse request","code":""}` 和裸的 `413`。正文里才出现的 413、状态 400 和 4130 不算。GitHub Copilot 流式 413（嵌套或顶层 `failed to parse request`）会折叠一次并重试，同样正文的 400 仍是普通错误 |
| openai-codex 目录去掉 `gpt-5.5` 和 `gpt-5.3-codex-spark` | v1.4.0 #11173 | done：`openai-codex` 不再列出 `gpt-5.5` 和 `gpt-5.3-codex-spark`，查找这两款报 `Unknown model`。未指定模型时选 `gpt-6.1-sol`。OpenAI API 目录仍有 `gpt-5.5`；review: pass（ai2 线验收，2026-10-22） |
| Cloudflare 分类器价格和上下文；分类器图片输入 | v1.4.0 changelog | open：`cloudflare-workers-ai` 上 Clef 输入价是每百万 token $0.24、上下文 65536，Clef Flash 是 $0.038 和 24576，Clef Omni 是 $0.15 和 64000，Jev 与 Jev 1.14 是 $0.042 和 32000。分类请求里 Clef 用最多四张 data URL，Jev 用 System One assets，OpenRouter 把 `image_url` 放进 state；`compat` 的 `imageInput` 和 `sendImageOptInHeader` 按字段盖过自动判断。codemode 的 `models.classify()` 不在这次；review-fail（2026-10-22）：1. 上游 `packages/ai/scripts/generate-models.ts` 把 `typesafe` 的 `jev-latest` 标成 input 含 image，compat 为 `imageInput: assets`、`sendImageOptInHeader: true`；`packages/ai/scripts/openrouter-catalog.ts` 给每个 OpenRouter 决策模型写上 `imageInput: state-image-urls`、`sendImageOptInHeader: false`，`packages/ai/test/classifier-models.test.ts` 锁死这一点。`packages/ai/CHANGELOG.md` 写明 Jev 在 typesafe 上、以及目录里带图片输入的 OpenRouter 决策模型都能收图。cadr 的 `src/cadr-ai/classifiers.lisp` `register-builtin-classifier-models` 只登记 `cloudflare-workers-ai` 的五款，`find-classifier-model` 查不到 `:typesafe` `jev-latest` 和 `:openrouter` `typesafe/jev-1.14`，请求形态只在测试里用手造模型覆盖。2. 上游 `packages/coding-agent/src/core/provider-composer.ts` 把 models.json 的 provider compat 按字段盖到分类器模型上；`packages/coding-agent/test/model-runtime-classifiers.test.ts` 在 typesafe 代理上把 `imageInput` 设成 `state-image-urls`、`sendImageOptInHeader` 设成 false 后，请求体是 `image_url`，且不带 `TypeSafe-Danger-Zone-Images`。`packages/coding-agent/CHANGELOG.md` 写了这条，本行只排除了 codemode 的 `models.classify()`。cadr 的 `src/cadr-cli/models/store.lisp` `parse-model-compat` 丢掉 `imageInput` 和 `sendImageOptInHeader`，`src/cadr-cli/models/registry.lisp` `refresh-model-registry` 只给聊天模型盖 baseUrl 和 headers，不碰分类器目录。3. 门禁 `goal13-lisp-idiom-audit-covers-the-current-production-file-set` 仍要求 cadr-ai 65 个源文件、合计 317；本行新增 `src/cadr-ai/classifiers.lisp` 后是 66 和 318。`goal14-b10-preserves-core-owners-and-frozen-ai-surface` 要求 `src/cadr-ai/package.lisp` 的 sha256 为 `9cc3e876dc11cdf93f48272cec52c5a450cd1348e8db0dd735bc68dcdc893244`（`6a604f877` 的父提交），本行导出分类器符号后是 `4655af1de0fe36ba3014b585abcbca20beb68e9ba5e529ba7cef92c94ebc9fa7`。 |
| Rex 终端：OSC 8、truecolor、行内图 | v1.4.0 #11131 | done：`TERM_PROGRAM=rex` 启用 OSC 8、truecolor 和 Kitty 行内图，没有 `COLORTERM` 提示也一样。泄漏的 `KITTY_WINDOW_ID` 不改变这三项。`CADR_HYPERLINKS=0` 只关掉超链接 |
| 未闭合 `$$` 不再吞掉后面的表；CJK 标点旁的粗体和斜体 | v1.4.0 #11159 #10730 | open：未闭合的 `$$` 或 `\[` 后面如果出现 GFM 表，表仍画成框，不再被公式块吞掉；闭合的多行公式后面的表照常渲染。`**这是测试。**后面`、`*斜体。*后面`、`字**「引用」**字` 会把标点包进粗体或斜体，`**end.**Then next` 仍保持字面量；review-fail（2026-10-22）：`src/cadr-tui/components/markdown.lisp` 的 `latex-looks-like-pending-math-p` 对连字符、竖线、右方括号和 `±≤≥≠≈∈→⇒∞∫∑√` 返回假，上游 v1.4.0 `packages/tui/src/components/markdown.ts` 的 `looksLikePendingDollarMath` 对这些字符返回真。未闭合 `$$` 后面没有 GFM 表、正文又只靠这些字符才像公式时，上游仍收成 pending 公式块，按 `raw.trim()` 原样输出。`$$` 换行 `---` 换行 `not a table` 在上游是三行 `$$`、`---`、`not a table`；cadr 把 `---` 画成 80 列横线，横线和后文之间多一个空行。提交 `6ce7a2fa8` |
| 进程没调用 `stop` 就退出时恢复终端模式 | v1.4.0 #11170 | open：进程没调用 `stop` 就退出时，exit 钩子同步写回鼠标跟踪、焦点上报、Kitty 键盘弹出、括号粘贴关闭和备用屏退出，Kitty 弹出在离开备用屏之前。正常 `stop` 之后这些序列只出现一次；review-fail（2026-10-22）：`test/cadr-cli/goal14-organization-test.lisp` 的 `goal14-b7-reusable-tui-internals-have-exact-owners` 仍要求 B7 顶层定义数 394。本行在 `src/cadr-tui/renderer/lifecycle-input.lisp` 增加 `*terminal-exit-renderers*`、`note-terminal-exit-renderer`、`clear-terminal-exit-renderer`、`terminal-exit-renderer` 四个顶层定义。父提交 `0a9f2b9b4` 实测 394，提交 `2bb627592` 实测 398。上游 v1.4.0 的 `#11170` 只改 terminal 恢复序列，不改这条组织计数；干净检出的 `./scripts/test-cl.sh` 在 cadr-cli 因这条失败 |
| `@` 补全的查询含正则元字符时仍有结果 | v1.4.0 #10972 | done：fd 查询按字面转义。`@pages/[`、`@pages/(`、`@[id` 命中对应文件，不把 `[` 和 `(` 当字符类 |
| 扩展对话框叠放，关掉当前的再露出上一个 | v1.4.0 #11166 #9909 | open |
| Ctrl+Z 挂起后剪贴板进程不被一起挂起 | v1.4.0 #11179 | open |
| `mcp.json` 允许 UTF-8 BOM | v1.4.0 #11191 | blocked：两次验收未通过；`test/cadr-cli/goal14-organization-test.lisp` 的 `goal14-b9-preserves-core-owners-and-frozen-extension-surfaces` 仍要求 `src/cadr-agent/package.lisp` 从 `#:define-tool` 到 `#:make-extension-hook-result` 的导出块 SHA-256 为 `f52b974189f593b4abc2d46ce05885345f743663a8ea1498958daceef3764cb1`。`06668b39e` 在该块插入 `#:add-mcp-server-config` 和 `#:remove-mcp-server-config` 后哈希变为 `04a231e373e1e3d3fb1a4bf618fd8c4d1d3eaa710bffb48ca6c006d819578993`，失败信息是 `B9 changed the frozen extension export text`。干净检出 `/tmp/cadr-review-agent-2120463`（HEAD `06668b39e`）跑 `./scripts/test-cl.sh` 退出 1，FiveAM 在 cadr-cli 进入 debugger 后中止：11302 项，11297 过，5 败，没有 9 份 suite summary。上游 `packages/coding-agent/src/extensions/mcp/config.ts` 导出 `addMcpServerConfig` / `removeMcpServerConfig`；cadr 加了对应导出，冻结哈希仍是父提交的值。以 UTF-8 BOM 开头的全局和项目 `mcp.json` 能读出各自的服务器，errors 为空。`add-mcp-server-config` 在带 BOM 的全局文件中新增 `other` 时返回未替换，原 `demo` 仍是 `enabled: false`；同名再加返回已替换。`remove-mcp-server-config` 删掉已有服务器时返回已删除，不存在的名字返回未删除且不改写文件。改写后的文件不再带 BOM，不剥 BOM 的 JSON 解析也能读出改过的条目；review-fail（2026-10-22）：上游 `packages/coding-agent/CHANGELOG.md` 明确该修复覆盖 `pi mcp add` / `pi mcp remove`，`packages/coding-agent/test/mcp-extension.test.ts` 用 `addMcpServerConfig` 在带 BOM 的全局文件中新增 `other`；cadr 的 `src/cadr-agent/extensions/mcp-config.lisp` 只提供 `update-mcp-server-config`，`src/cadr-agent/package.lisp` 也未导出 add/remove，`test/cadr-agent/mcp-config-test.lisp` 只更新既有 `demo`，未实现或锁死 add/remove 场景 |
| 恢复会话时，分支没记过的扩展工具默认仍激活 | v1.4.0 #11062 #11075 | done：恢复会话和 `/tree` 切到目标分支时，转录里从没加入或移除过的扩展工具仍然激活。注册时 `default-active` 为假的保持关闭。压实之前移除的工具保持关闭。内置工具只跟分支记下的装载走。`--tools` 允许列表之外的 `mcp__` 工具在切分支后仍不激活；review: pass（agent 线验收，2026-10-22） |
| 输出上限截断的工具调用丢掉对应的工具结果 | v1.4.0 #11227 | done：会话停在输出上限截断的工具调用和它的工具结果上时，下一次提示把两者从投影上下文里一起去掉，请求里不再出现这条 `length` 助手消息和对应工具结果。输出已达到模型上限、换了模型、或自动折叠关闭时，这对消息仍留在请求里；review: pass（agent 线验收，2026-10-22） |
| `grep` 使用 `rg --no-config` | v1.4.0 #11203 | done：工具自己的正则、字面、glob 和条数不受 `RIPGREP_CONFIG_PATH` 影响。配置里的 `--fixed-strings` 不会把 `a.` 变成字面搜索 |
| HTML 导出里 CJK 旁的粗体和斜体 | v1.4.0 #3353 #10154 | open |
| Windows 外壳探测、`pi update` 的 BOM、扩展加载 `@earendil-works/pi-ai/models`、生成的 models 参考文档、遥测 span | v1.4.0 | done：PowerShell 两个安装目录、按 SystemRoot 识别旧 WSL bash.exe、空 SystemRoot 时 taskkill 用 C:\Windows、工具包解压不再用 WINDIR；N/A（已裁决）：Windows Store 别名、pi update BOM、扩展加载 pi-ai/models、models 参考文档、遥测 span |
