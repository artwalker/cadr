# 内置数据资产对照 v1.4.0

日期：2026-10-23。钉点：`v1.4.0` = `4a080252f06caf63a525d7873c5d94d3c23887e0`。
只读上游：`git -C /root/projects/pi-mono show v1.4.0:<path>` 与 `git ls-tree -r v1.4.0`。
主题 JSON 的解析用本机已有的 v1.4.0 包树 `/tmp/cadr-render-diff-pi-4a080252f`（`package.json` 版本 1.4.0，`dark.json` 的 SHA256 与 `git show v1.4.0` 相同）。没有改 pi-mono，也没有改 cadr 源码。

对照脚本在 `/tmp`，用完已删。两边都先解析成规范形式再 diff。产品身份替换（`pi`→`cadr`、`PI_`→`CADR_`、`.pi`→`.cadr`、`pi.dev`→`cadr.dev`、`pi-share`→`cadr-share`）算一致。范围外只按差距清单第 3 节 Still exclude，加上本次任务写明排除的测试夹具、`package.json`、`tsconfig`、CHANGELOG、node 构建配置（含 `package-lock.json`）。

模型目录不重做。Goal 26 PR #874 已整表重生成。这里只抽查：图像目录 `src/cadr-ai/image-models.generated.lisp` 有 63 个 `:ID`，与 Goal 26 的 OpenRouter 图像数一致。聊天目录里 `grok-4.7`、`glm-5.3`、`kimi-k3` 都在；过期的是默认模型指针，不是目录缺行。把 `*.json` 里带 `contextWindow` 的 id 和聊天目录直接相减会把分类器算进去，那个差不作目录缺口。

GAP 行按功能聚合。主题颜色整表不一致，已由 GAP-51 覆盖，这里不另开行。

## 统计

`git ls-tree -r --name-only v1.4.0 packages/` 里扩展名为 json、md、txt、yaml、yml、html、css、png、svg，以及 export-html 的 `template.js` 与 `vendor/*.min.js`，共 164 个数据文件。

| 类 | 项数 |
|---|---|
| 范围外（文档、README、图片、evals、`models.schema.json`） | 76 |
| 范围外（测试夹具） | 21 |
| 范围外（package.json、lock、tsconfig、CHANGELOG） | 44 |
| 范围内数据文件 | 23 |
| 范围内 TS 常量组 | 22 |
| 检查项合计 | 186 |

范围内 45 项的结论：一致 22，不一致 10，cadr 没有 13。
按功能聚合后，不一致或缺失 14 组。其中主题颜色是 GAP-51。本审计新开 GAP-52 到 GAP-64，共 13 组。

## 范围内数据文件

| 上游 | cadr | 结论 | 差异摘要 |
|---|---|---|---|
| `packages/coding-agent/src/modes/interactive/theme/dark.json` | `src/cadr-tui/theme.lisp` `+dark-theme-colors+` | 不一致 | 解析后的色值与内置十六进制表不同。`bf8e4b953`（2026-09-26，System theme）。见 GAP-51 |
| `packages/coding-agent/src/modes/interactive/theme/light.json` | `src/cadr-tui/theme.lisp` `+light-theme-colors+` | 不一致 | 同上，亮色表。见 GAP-51 |
| `packages/coding-agent/src/core/export-html/template.html` | `src/cadr-agent/export-html/template.html` | 一致 | 字节相同，2271 |
| `packages/coding-agent/src/core/export-html/template.css` | `src/cadr-agent/export-html/template.css` | 一致 | 字节相同，22952 |
| `packages/coding-agent/src/core/export-html/template.js` | `src/cadr-agent/export-html/template.js` | 一致 | 唯一差别是 `pi-share:v1:sidebar-width` 与 `cadr-share:v1:sidebar-width`（80552 / 80554） |
| `packages/coding-agent/src/core/export-html/vendor/highlight.min.js` | `src/cadr-agent/export-html/vendor/highlight.min.js` | 一致 | 字节相同，121727 |
| `packages/coding-agent/src/core/export-html/vendor/marked.min.js` | `src/cadr-agent/export-html/vendor/marked.min.js` | 一致 | 字节相同，44640 |
| `packages/coding-agent/src/core/export-html/vendor/marked-cjk-friendly.min.js` | `src/cadr-agent/export-html/vendor/marked-cjk-friendly.min.js` | 一致 | 字节相同，4754 |
| `packages/coding-agent/src/modes/interactive/assets/clankolas.png` | 无 | cadr 没有 | 上游约 539053 字节，公告组件按文件名加载。cadr 公告只有 URL 和标题。见 GAP-57 |
| `packages/coding-agent/examples/extensions/dynamic-resources/dynamic.json` | `examples/extensions/dynamic-resources/dynamic.json` | 不一致 | 去掉 `$schema` 和空白后，`vars` 与 `export` 相同。`colors` 缺 `scrollbarTrack`、`scrollbarThumb`。`457ae8c79`（2026-09-04）。见 GAP-61 |
| `packages/coding-agent/examples/extensions/dynamic-resources/dynamic.md` | `examples/extensions/dynamic-resources/dynamic.md` | 一致 | 字节相同，160 |
| `packages/coding-agent/examples/extensions/dynamic-resources/SKILL.md` | `examples/extensions/dynamic-resources/SKILL.md` | 一致 | 字节相同，177 |
| `packages/coding-agent/examples/extensions/subagent/agents/planner.md` | 无同路径文件 | cadr 没有 | 示例 Lisp 会读用户目录里的 `*.md`，仓库不带这四份代理说明。见 GAP-62 |
| `packages/coding-agent/examples/extensions/subagent/agents/reviewer.md` | 无同路径文件 | cadr 没有 | 同上 |
| `packages/coding-agent/examples/extensions/subagent/agents/scout.md` | 无同路径文件 | cadr 没有 | 同上 |
| `packages/coding-agent/examples/extensions/subagent/agents/worker.md` | 无同路径文件 | cadr 没有 | 同上 |
| `packages/coding-agent/examples/extensions/subagent/prompts/implement.md` | 无同路径文件 | cadr 没有 | 三份工作流提示词未随示例携带。见 GAP-62 |
| `packages/coding-agent/examples/extensions/subagent/prompts/implement-and-review.md` | 无同路径文件 | cadr 没有 | 同上 |
| `packages/coding-agent/examples/extensions/subagent/prompts/scout-and-plan.md` | 无同路径文件 | cadr 没有 | 同上 |
| `packages/coding-agent/schemas/keybindings.schema.json` | 无 | cadr 没有 | 编辑器 `$schema` 用的三份 schema 未入库。见 GAP-63 |
| `packages/coding-agent/schemas/settings.schema.json` | 无 | cadr 没有 | 同上 |
| `packages/coding-agent/schemas/theme.schema.json` | 无 | cadr 没有 | 同上 |
| `packages/mcp/LICENSES/modelcontextprotocol-typescript-sdk.txt` | 无 | cadr 没有 | Node MCP SDK 的许可证文本。cadr 不打包该 SDK。见 GAP-64 |

`packages/coding-agent/schemas/models.schema.json` 在清单第 3 节，范围外。

## 范围内常量

| 上游常量 | cadr | 结论 | 差异摘要 |
|---|---|---|---|
| `TUI_KEYBINDINGS` + `APP_KEYBINDINGS` 与平台增量（`packages/tui/src/keybindings.ts`，`packages/coding-agent/src/core/keybindings.ts`） | `src/cadr-tui/keybindings.lisp` 的 `+unix-keybinding-definitions+`、`+keybinding-platform-deltas+` | 一致 | 共享 id 的 unix 默认键相同。win32：`app.suspend` 无键，`tui.editor.undo` 为 `ctrl+z`，WSL 为 `alt+z`。cadr 另有上游没有的 `app.debug` = `shift+ctrl+d`，以及模型、思考选择器的 `clearSearchOrCancel` = `ctrl+c`。这三键是 cadr 多出来的，不记成上游漂移 |
| `SETTINGS_DEFAULTS`（`packages/coding-agent/src/core/settings-defaults.ts`） | `src/cadr-cli/bootstrap/settings.lisp`、`src/cadr-cli/sdk/settings-service.lisp` | 一致 | 脚本用第一次出现的字符串配对，把 `transport`、`quietStartup` 配错。复核：`branchSummary.skipPrompt` false，`enableAnalytics` false，`markdown.codeBlockIndent` 缺省 `"  "`，`markdown.mermaid` 缺省 `streaming`，`images.autoResize` true，`images.blockImages` false，`terminal.clearOnShrink` false |
| 系统提示词前言（`packages/coding-agent/src/core/system-prompt.ts`） | `src/cadr-cli/sdk/system-prompt.lisp` 前言 | 一致 | 产品名替换后相同。`src/cadr-cli/system-prompt.lisp` 的短句 `+default-system-prompt+` 不在主路径上 |
| 系统提示词 docs 段 | 同上 docs 段 | 不一致 | cadr 在工具列表后截断，少了 MCP 与 codemode 两句。`8562bcf66`（2026-09-29）。见 GAP-54 |
| `BUILTIN_SLASH_COMMANDS`（`slash-commands.ts`，24 条） | `src/cadr-cli/interactive/autocomplete.lisp` `+tui-autocomplete-command-specifications+` | 一致 | 顺序相同。`quit` 是 `Quit cadr`。`bug` 是 `Report a bug to the developers`，上游是 `Report a bug to the Pi developers`。产品名替换 |
| read、bash、edit、write、grep、find、ls 的工具说明 | `src/cadr-cli/tools/*.lisp` | 一致 | 代入 `DEFAULT_MAX_LINES` 2000、字节上限 50 KiB、grep 500、find 1000、ls 500 后相同。shell 名 bash / PowerShell 的替换相同 |
| 上述工具的参数说明（bash/powershell 的 `command` 除外） | 同上 schema 字符串 | 一致 | 与上游 schema 的 description 相同 |
| bash 与 powershell 的 `command` 参数说明 | `src/cadr-cli/tools/bash.lisp`、`powershell.lisp` | 不一致 | 上游两边都是 `Shell command to execute`。cadr 分别是 `Bash command to execute` 与 `PowerShell command to execute`。`80e62761f`（2026-08-24）。见 GAP-56 |
| `SUMMARIZATION_PROMPT`、`UPDATE_SUMMARIZATION_PROMPT`、`SUMMARIZATION_SYSTEM_PROMPT`、`BRANCH_SUMMARY_PREAMBLE`、`BRANCH_SUMMARY_PROMPT` | `src/cadr-agent/compaction.lisp`、`src/cadr-agent/branch-summarization.lisp` | 一致 | 正文相同。更新提示词的说明在 cadr 里内联 |
| `TURN_PREFIX_SUMMARIZATION_PROMPT` | `src/cadr-agent/compaction.lisp` `+turn-prefix-summarization-prompt+` | 不一致 | cadr 仍是 #9908 之前的 PREFIX 文案。`d192bd6dc`（2026-09-22）。见 GAP-53 |
| `defaultModelPerProvider`（`model-resolver.ts`） | `src/cadr-ai/providers/definitions.lisp` `:default-model` | 不一致 | 42 个提供方里 5 个默认 id 过期。typesafe 上游没有聊天默认。见 GAP-52 |
| 提供方 id、显示名、baseUrl | `src/cadr-ai/providers/definitions.lisp` | 不一致 | 脚本曾把认证标签和文件里第一个空 `baseUrl` 当成差异。复核后 anthropic 名为 `Anthropic`，Cloudflare 与 OpenCode 的 baseUrl 与 v1.4.0 提供方对象一致。显示名只有 openai-codex 少了 `(legacy)`。`02eed88fd`（2026-09-29）。见 GAP-59 |
| 交互热键说明（`interactive-mode.ts` 热键模板） | `src/cadr-cli/bootstrap/sessions.lisp` `+hotkeys-markdown-sections+`、`+interactive-hotkey-definitions+` | 不一致 | 粘贴句仍是旧文案。换行行没有 Windows Terminal 的后缀。`fd889a274`（2026-09-28）。见 GAP-55 |
| `printHelp`（`packages/coding-agent/src/cli/args.ts`） | `src/cadr-cli/arguments.lisp` `+cli-usage-prefix+`、`+cli-usage-suffix+` | 不一致 | 身份替换后仍少 `--`、工具通配与 MCP 说明、codemode 例子、powershell 工具行、`BASETEN_API_KEY`。`cadr ai` 是 GAP-16 的合并入口，不算旧文案。见 GAP-60 |
| `GUESSED_DEFAULT_COLORS`（`theme.ts`） | 无对应表 | cadr 没有 | 空 token 在终端不报颜色时，上游用 dark `#e5e5e7`/`#000000`、light `#000000`/`#ffffff`。cadr 空串走 ANSI 39/49。`567469096`（2026-09-24）。见 GAP-58 |
| `TOOL_SEARCH_DESCRIPTION` 与停用词 | `src/cadr-agent/tool-search.lisp` `+tool-search-description+` | 一致 | TS 里的 `\n` 转义展开后正文相同。参数说明 `Search query for deferred tools.` 与 `Maximum number of tools to return. Defaults to 8.` 相同 |
| codemode `DESCRIPTION_INTRO` | `src/cadr-cli/extensions/codemode.lisp` 描述拼接 | 一致 | 首段与 Globals 段相同，不是单独的 defparameter |
| MCP JSON-RPC 错误码 | `src/cadr-agent/extensions/mcp-protocol.lisp` | 一致 | -32700、-32600、-32601、-32602、-32603。连接关闭与超时句式相同 |
| `NESTED_CALL_LIMITS` | `src/cadr-agent/nested-calls.lisp` | 一致 | 256、8192、32768、500 |
| 模型目录（抽查，不重做） | `src/cadr-ai/models.generated.lisp`、`radius.models.generated.lisp` | 一致 | 见文首。不把分类器 id 的粗扫记成缺口 |
| 图像模型目录（抽查） | `src/cadr-ai/image-models.generated.lisp` | 一致 | 63 个 id |
| 设置菜单标签 | `src/cadr-cli/bootstrap/settings.lisp`、`src/cadr-cli/interactive/selectors/settings.lisp` | 一致 | 主列表与 `Anthropic extra usage` 都在。先前 43 对 35 是把子菜单标签只算在一个文件里 |

## 不一致组

主题颜色（dark.json、light.json）→ 已有 GAP-51。
其余 13 组 → GAP-52 至 GAP-64，写在 `docs/acceptance/goal27-pi-parity.md` 末尾。
