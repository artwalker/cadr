# Goal 26：pi 基线推进至 v1.3.0

> **状态：** 进行中（钉点改靶）。用户 2026-10-20 明确要求从已发布的
> v0.87.0 改钉到已发布的 **v1.3.0**（major leap）。不宣布 Goal 20、24 或 25
> 完成。G.17 保持 `missing`。`version.sexp` 仍是 `0.2.0`，直到这一版对齐被接受。
> Goal 20 invent 的 `paused` 置为 `true`，直至机械钉点与门禁可跑。
>
> **自：** `16787ad5b2dc748047f314ca1bfe7708f30f54f3` · `v0.87.0` +0
> **目标锚点：** `71023aec1546d6d677a65669c5665c0927ce0dd0` · `v1.3.0` +0
> （pi tag `v1.3.0`，提交说明 `Release v1.3.0`，2026-10-15 20:57:27 +0200）
>
> **作废：** 原 `docs/acceptance/goal26-pi-0870-alignment.md` 与 leftover-PR
> 逐条落地法。分支 `goal26-pin-v0870` / PR 855 保留为历史，不 merge、不继续追。

## 差量

测量 2026-10-20：

```sh
git rev-list --count \
  16787ad5b2dc748047f314ca1bfe7708f30f54f3..71023aec1546d6d677a65669c5665c0927ce0dd0
git diff --stat \
  16787ad5b2dc748047f314ca1bfe7708f30f54f3..71023aec1546d6d677a65669c5665c0927ce0dd0 \
  -- packages/coding-agent packages/tui packages/ai
```

482 个提交。上述三包约 722 个文件，+54420 / −39668 行。中间含 v0.87.1、
v0.99.x、v1.0.0–v1.2.0。发布说明入口：
[v1.3.0](https://github.com/earendil-works/pi/releases/tag/v1.3.0)、
[v1.0.0](https://github.com/earendil-works/pi/releases/tag/v1.0.0)。

## 方法（major-leap，取代 leftover-PR）

v0.87.0 时代的「按 leftover PR 逐条 cherry-pick」对 ~482 commits / 1.x 太慢，
且 PR 队列相对 v1.3.0 tip 已过时。本目标改用：

1. **机械钉点**：`BASELINE` → `71023aec…` / `v1.3.0` +0；
   `PI_AI_MODEL_DATA_*` → `@earendil-works/pi-ai@1.3.0`；
   fixture `baselineCommit` 与身份行跟 `set-baseline.sh`。
2. **机械枚举**：`enumerate-baseline-diff.py` +
   `check-source-parity-drift.sh` 处置写在
   `docs/acceptance/goal26-evidence-v130/`。
3. **按面落地**：以枚举类与发布说明里的用户可见面为队列
   （agent loop / providers / TUI / settings schema / MCP / session），
   每面一个可验证单元；不把未合并 leftover PR 当权威顺序。
4. **保留仍有效的 WIP**：Cerebras bodyless 400/413 overflow 与 v1.3.0
   `overflow.ts` 的 `CEREBRAS_BODYLESS_OVERFLOW_PATTERN` 一致，保留在钉上。
5. **不新造 intentional-difference 类**；不追 `main`；CADR_* only。

### 源文件处置摘要

`source-dispositions.tsv` 共 586 行 A/D/R：

| 桶 | 约数 | 处置 |
|---|---|---|
| 范围外包（durable/chord/mcp/codemode/…） | 437 | 本钉不 port |
| coding-agent/tui/ai 新增 | 75 | open；对齐前必须 port 或裁决 |
| coding-agent/tui/ai 删除 | 73 | open；对齐时 drop/rewrite |
| ai oauth-page 重命名 | 1 | open；改映射 |

### 枚举注意

`settingsKeys` / `themeTokens` 的大规模「removed」在 v1.3.0 上很可能是
枚举器仍按旧 interface 形状抽取、而上游已迁到 TypeBox
`settings-schema.ts` 导致的假阳性。落地前须重解析；不得把整表当真实删除。

真实新增命名集（摘录）：CLI `--no-mcp`；扩展事件
`mcp_servers_change`、`provider_stream_event`（移除 `before_agent_start`）；
`PI_PROGRAM_STATUS`；`publicApiExportCount` 36→44；错误类
`McpSignInCancelledError`。

## 必须跟进的用户可见面（首批；完整以枚举为准）

| 面 | 来源 | 处置方向 |
|---|---|---|
| Fullscreen 默认 TUI；`tuiMode` / `--tui-mode regular` | v1.0.0 | done on tip：unset/`*` → fullscreen；仅 `"regular"` → regular；help + settings 文案对齐 |
| `--no-mcp` | 枚举 | done：CLI 标志 + `disabled-builtin-extensions ("mcp")`；MCP builtin 仍薄 |
| `mcp_servers_change` / `provider_stream_event`；去掉 `before_agent_start` | 枚举 | done：两事件入 hook 表 + emit；保留 `before_agent_start` |
| `sessionShareDestination`（`/share` → auto/gist/radius） | v1.3.0 | done：settings + `/share` destination auto/gist/radius |
| 换模型时丢弃他模型 thinking，不改写成可见文本 | v1.3.0 | done：`copy-history-content-block` 跨模型 drop；同模型保留 signed/redacted/非空 |
| Resume 保留会话激活工具；`--tools +/-` 叠加上去 | v1.3.0 | done：usesDefaultTools restore + modifiers；session toolsAdded persist/parse |
| Kimi Coding → Chat Completions + `/v1` base URL | v1.3.0 | done：openai-completions + `/v1`；catalog mid-convo flags |
| OpenAI GPT-6 中途改 thinking 保 cache | v1.3.0 | done：`configuration_update` + 固定 `reasoning.effort`；catalog `supportsMidConvoEffort` |
| Cerebras bodyless 400/413 overflow | v1.3.0 overflow.ts | done on tip：`290327a77` bodyless 400/413 仅 Cerebras |
| `PI_PROGRAM_STATUS` / OSC 7501 program status | 枚举 | done：`format-program-status` + terminal 探测/`PI_PROGRAM_STATUS=1\|0`；interactive reporter |
| `fullscreenWheelScrollLines` / wheel auto-accel | v1.3.0 #9758 | done：`WheelScrollAccelerator` + settings/`/settings`；默认 `:auto` |
| settings schema 重解析 | 枚举假阳性 | done：82 个 interface key 仍在 `settings-schema.ts` `SettingsSchema`；真实新增 `$schema`、`deviceId`、`codemode`、`queueMode`/`websockets`（deprecated）。`deviceId` + 三项迁移已落地；`codemode` 仍缺 |
| theme token 重解析 | 枚举假阳性 | done：56 个调色板 token 在 `theme-tokens.ts` `THEME_TOKENS`，与 `theme.lisp` kebab-case 一一对应；`pageBg`/`cardBg`/`infoBg` 是 export 色，已在调色板外。枚举「removed 56」是 `theme.ts` 联合类型迁走造成的假阳性 |
| skill slash 按裸名计分 | v1.3.0 `autocomplete.ts` | done：`skill:` 先按裸名 fuzzy，未中的再按全名，裸名命中排在前面 |
| `--continue` 最近会话 | v1.3.0 `findMostRecentSession` | done：匹配 cwd 的 jsonl 按文件 mtime 取最新；同一秒 mtime 再比消息时间 |
| Responses `api-error` provider | v1.3.0 `openai-responses.ts` | done：request-spec 与 SSE `api-error` 用模型 provider；`response.failed` / `error` 文案跟 shared stream |
| Anthropic thinking drop 提示 | v1.3.0 `interactive-mode.ts` | done：`message_delta.input_transformations` 记入 diagnostic；次数高于上一条 assistant 且 cache-miss notices 开时警告 |
| Google thinking 钳制 | v1.3.0 `getDisabledGoogleThinkingConfig` #9455 | done：省略 reasoning 时按 thinkingLevelMap 把 off 钳到下一档；Gemini 3.1 Pro medium 保持 MEDIUM；2.5 用 budget |
| OpenCode session header | v1.3.0 `getSessionHeaders` | done：没有 session id 时不发 `x-opencode-session` / `x-opencode-client`，不再合成 UUID |
| compaction `systemMessage` | v1.3.0 `appendCompaction` | done：折叠后的 system message 写在 compaction 条目上，时间戳用条目时间；投影在摘要前放回该 checkpoint |
| read 行号范围 | v1.3.0 `formatReadLineRange` | done：数字字符串可解析；任一端畸形则整段省略；end 为 0 时不写 `-0` |
| `executeTool` / `nestedCalls` | v1.3.0 `nested-tool-calls.ts` | done：工具执行中 `extension-context-execute-tool` 跑子调用；父结果记下 `nestedCalls`（256 条、参数字节上限）；子结果不记；事件带 `parent-tool-call-id` |
| virtual model | v1.3.0 `virtual-models.ts` | done：`api` `:pi-virtual` 只作为选择；请求前 `route` 换成物理模型和钳制后的 thinking；未注册、非物理目标、无凭证、直接 `stream-chat` 都失败；物理回复之后分支选择仍停在已注册的虚拟模型上；路由状态记在 `pi.virtual-model-state` |
| `tool_search` | v1.3.0 `extensions/tool-search/tool.ts` | done：BM25 检索尚未声明的 `deferred` / `codemode` 工具并写入 active tools，下一次调用才声明；空 query、非正整数 limit 失败；内置但不在默认四个工具里。`createCodemodeDescription` 不移植 |
| MCP `mcp.json` | v1.3.0 `mcp-servers.ts` / `extensions/mcp/config.ts` | done：校验 stdio/HTTP、exposure 别名、按工具 exposure、OAuth 回调、provider auth 只允许全局文件；可信项目可覆盖 enabled/exposure/toolExposure；`-`/`_` 命名冲突拒绝。连接、OAuth 登录和 codemode 执行仍不在这次 |
| MCP 工具名 / `mcp_servers` 段 | v1.3.0 `createMcpToolName` / `renderServersSection` | done：名字只留 `[A-Za-z0-9_]`，超过 64 或撞名时加 sha256 后缀；系统段列出 codemode / deferred 服务器，描述缩短，放不下的末尾服务器计在结束行。连接仍不在这次 |
| 登录授权 URL | v1.3.0 `auth-url.ts` | done：`showAuth` 的点击提示在 macOS 为 Cmd+click，其余为 Ctrl+click，后面跟 `app.message.copy`；该键复制 URL，成功写成 “Copied URL to clipboard”，失败写成剪贴板错误。设备码 URL 仍只有点击提示。MCP OAuth 连接仍不在这次 |
| 截断输出临时文件 | v1.3.0 `output-files.ts` | done：bash 和 output accumulator 的完整输出用 `O_EXCL` 建在临时目录，权限 `#o600`；已有名字（含符号链接）失败，不跟着链接写。codemode 写图仍不在这次 |
| 启动 logo | v1.3.0 `pi-logo.ts` | done：能画半块的终端用珊瑚/蓝/黄两行标记，版本跟在第一行，第一条提示跟在第二行；truecolor 用 `38;2`，否则用 256 色。Apple Terminal 改为珊瑚 `c`、黄色 `adr`。点击播放 3D 彩蛋仍不在这次 |
| Radius 登录 shimmer | v1.3.0 `radius-login-selector.ts` | done：顶层 `/login` 在账户和 API key 之后加上 `Sign in with Radius`；选中时这几个字按 logo 四色、每秒 10 字做 sRGB smoothstep。状态后缀仍用现有 configured 文案。50ms 重画只在该项选中时发生 |
| MCP 结果截断 | v1.3.0 `limitMcpContent` | done：文本块按换行拼起来，超过 20KB 时各留一半字节，中间标出省掉的码点数，只在 UTF-8 字符边界切开；原文写入 `cadr-mcp` 临时文件（`#o600`），模型看到 token 估算、行数和路径。存盘失败只留下错误。图片块跟在警告后面。连接、OAuth 和资源读取仍不在这次 |
| 主题 appearance / OKLCH | v1.3.0 `theme-schema.ts` / `colors.ts` | done：主题 JSON 接受 `appearance` 为 `dark` 或 `light`；省略时按前景和背景的 Oklab 明度判断，背景更亮就是 light。`#RGB`、`oklch()`、`okhsl()` 解析成 `#rrggbb`。调色板 0–15 不参与判断 |
| 系统主题 | v1.3.0 `system-theme.ts` | done：`system` 排在主题列表最前，名字保留。有背景和 16 色调色板时按家族色相和对比度曲线生成；只有背景时用家族自己的色相；都没有时用 ANSI 下标，中性字用 SGR 2。正文在面板上至少 4.5:1，浅色调色板不会在别的明度上变艳 |
| 终端前景和 16 色 | v1.3.0 `queryTerminalColors` | done：一次查询 OSC 10、OSC 11 和 OSC 4 的 0–15，并以 DA1 收尾。18 个回复或 DA1 结束；调色板缺任何一格就不用。超时先交已到的颜色，迟到的回复再合并，不清掉先前的前景、背景或调色板。当前主题是 `system` 时重新套用 |
| Azure provider | v1.3.0 `azure.ts` / Foundry DeepSeek | done：目录里的 Azure 模型改挂 provider `azure`。`deepseek-v4-pro` 走 Chat Completions，地址归一到 `/openai/v1`，请求里的 model 用 `AZURE_OPENAI_DEPLOYMENT_NAME_MAP` 或 `azureDeploymentName`，回复上的模型 id 仍是目录 id。thinking 用 `reasoning_effort`，`max` 钳到 `high`，不发 `thinking` 和 prompt cache 字段；系统提示用 system 角色，对话中的 system 消息留在原位。没有地址时流返回错误，而不是从 `stream` 抛出去 |
| 瞬时错误重试 | v1.3.0 `retry.ts` #10965 #10920 | done：`The service is temporarily unavailable`、`Unable to forward upstream stream`、`provider returned an error`、HTTP 520、HTTP/2 pending stream canceled、高峰 `high demand` 会重试。ChatGPT `subscription_sharing_usage_limit_exceeded` 即使带 429 也不重试。会话循环和 `retryable-assistant-error-p` 用同一组句子 |
| 提示词空引号参数 | v1.3.0 `parseCommandArgs` #10867 | done：`""` 和 `''` 占一个空参数，后面的位置不前移。空的 `$1` 仍用 `${1:-default}`。反斜杠不转义引号。未加引号的换行仍是分隔符 |
| 工具参数 JSON | v1.3.0 `parseToolCallArguments` #10868 #10897 | done：字符串里的非法 `\u`（如 `\usepackage`）变成字面反斜杠，后面的字段还在。流被截在 `\u` 中间时丢掉这个未写完的转义。工具调用结束后，残缺 JSON 不再留下已解析的前缀：参数是空对象，`argumentsError` 带原文。校验失败，模型看到 `Invalid arguments for tool` 和收到的文本 |
| `--model` 多 provider | v1.3.0 `resolveModelReference` #10160 | done：同一 id 有多家时，有凭证的那一家胜出；只有一家可用就选它；多家可用或一家都没用则报歧义，不按目录顺序，也不落到更弱的 fuzzy。`provider/id` 在该 provider 可用时优先。`--models` / enabledModels 把每一家都加进范围并警告。`--api-key` 不替用户选 provider。没有对应模型但 provider 明确时用自定义 id，并警告 |
| 同块 reasoning 顺序 | v1.3.0 `openai-completions` #10926 | done：一条 delta 同时带 reasoning 和 content 时，thinking 在正文前面。`reasoning_details` 也先进入 thinking；连续的 text/summary 合并，encrypted 保持独立。签名是这些对象的 JSON，下一次请求只带回 `reasoning_details`，不再带原始 reasoning 字段。旧 tool `thoughtSignature` 里的 encrypted 对象同样回放 |
| 错误 tool result 图片 | v1.3.0 #10794 | done：Anthropic 和 Bedrock 上的 Claude 不把图片留在 `is_error` 结果里。连续图片换成 `(image attached after the tool results)`，原图跟在这一轮全部 tool result 后面，说明行带 tool call id 和工具名。成功结果、没有图片的错误结果、非 Claude 的 Bedrock 模型仍把图片留在结果里 |
| OpenCode inference 端点 | v1.3.0 `generate-models.ts` `195120a91` | done：Zen 和 Go 的目录地址从 `opencode.ai/zen` 改到 `opencode.ai/inference`。先替换 `/zen/go`，再替换 `/zen`。`minimax-m2.7` 改走 Anthropic Messages，base 不带 `/v1`，请求打到 `.../inference/go/v1/messages`。Go 上的 `qwen3.6-plus` 仍是 openai-completions，地址 `.../inference/go/v1`。Zen 的 Gemini 仍是 google-generative-ai，地址 `.../inference/v1`。OpenCode Go 的协议补上 `google-generative-ai` |
| Claude off 思考 | v1.3.0 #10753 | done：`claude-opus-5`、`claude-haiku-5-5`、`claude-haiku-5.5`（含 `anthropic/` 前缀和日期快照）不再把 `off: null` 留在 thinking map 里。思考关掉时请求是 `thinking: {type: "disabled"}`，不带 effort 标记，也不带 `block_binding`。`off` 仍是 null 的模型（如 Fable 5.1）继续走 adaptive thinking 和 effort |
| Xiaomi MiMo 思考档 | v1.3.0 #10818 | done：`xiaomi` 和三个 token-plan 上会思考的模型只暴露 `off` 和 `high`。`minimal` 钳到 `high`。请求只发 `thinking.type` enabled/disabled，不发 `reasoning_effort` |

v0.87.0 钉上尚未关闭的缺口与 leftover 行为，在 v1.3.0 上重新对照 tip；
不以旧 PR 是否合并为完成条件。

## 执行顺序

1. 冻结 Goal 20：`goal20-queue.json` `paused=true`。
2. `git fetch upstream --tags`；确认
   `71023aec1546d6d677a65669c5665c0927ce0dd0` 可 `cat-file`。
3. `scripts/set-baseline.sh 71023aec1546d6d677a65669c5665c0927ce0dd0`
4. `scripts/render-diff.py` 中 `PI_AI_MODEL_DATA_PACKAGE` /
   `PI_AI_MODEL_DATA_SHA256` → `@earendil-works/pi-ai@1.3.0` /
   `5343e1639bf343bdc3344df3ad6c31c05a50b68bad07ac6bce10890d4b6b8a61`
5. 删旧 render-diff 缓存：`rm -rf /tmp/cadr-render-diff-pi-16787ad5b`
6. 证据目录：`docs/acceptance/goal26-evidence-v130/`
7. 按面落地；每面 FiveAM / 确定性门禁绿后再推。
8. 全门禁可跑后再把 Goal 20 `paused=false`（不宣布 Goal 20 完成）。

## 硬约束

- `version.sexp` = `"0.2.0"` 直到对齐被接受
- 不标 Goals 20/24/25/26 完成；G.17 保持 `missing`
- 不 merge PR 855；leftover PR 用「已改钉 v1.3.0，勿合」关闭或搁置
- 不 force-push；显式 path staging
- Live probes：仅 xAI；OpenCode 计费失败不是产品缺陷
