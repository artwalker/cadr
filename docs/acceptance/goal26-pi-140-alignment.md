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
| 默认模型：Copilot `gpt-6.1-sol`，NVIDIA nemotron 3.5，Xiaomi `mimo-v2.6-pro` | v1.4.0 changelog | done：未指定模型时，`github-copilot` 选 `gpt-6.1-sol`（上下文 1050000）；Copilot 关闭思考时不写 `reasoning.effort=none`。`nvidia` 选 `nvidia/nemotron-3.5-super-vl-120b-a12b`，`xiaomi` 和三个 Xiaomi Token Plan 选 `mimo-v2.6-pro`。四个 Xiaomi 目录用 `mimo-v2.6-flash` / `mimo-v2.6-pro` 替换 v2.5 两款，`xiaomi` 另列 `mimo-v2.6-pro-ultraspeed` |
| ChatGPT Business 用量上限不重试 | v1.4.0 changelog | done：`subscription_sharing_workplace_individual_usage_limit_exceeded` 即使带 429 也不重试。OpenAI Responses 在错误后另起一行提示用户让工作区管理员到 admin.openai.com → Workspace → Usage limits 提高上限；Codex Responses 不追加这句 |
| 折叠和分支摘要用模型输出上限；`reserveTokens` 只决定何时开始；`/compact` 指令在被切开的回合开头仍生效 | v1.4.0 #9512 #9075 #11058 | done：折叠、切开回合的前缀和分支摘要请求都不写 `maxTokens`。provider 用模型输出上限，窗口不够时再收紧。`reserveTokens` 只决定自动折叠何时开始。`/compact` 指令在被切开的回合开头仍以 `Additional focus` 生效，哪怕这段前缀是上次折叠后的唯一新内容 |
| 客户端身份、`User-Agent`、OpenRouter / NIM / OpenCode attribution | v1.4.0 `identity.ts` | open |
| 只含空白的工具输出改成和空输出一样的占位 | v1.4.0 #8720 | done：`""`、`\r\n`、空格加换行加 tab 在 OpenAI Responses 和 Completions 上写成 `(no tool output)`，在 Google 上写成空字符串。有可见文字的结果仍原文送出 |
| 重试认更多上游失败、Vertex 令牌刷新、Codex 代理断流；请求号里的数字不当成 HTTP 状态 | v1.4.0 #10920 #11057 #10996 | open |
| Responses 在删过工具之后继续加载 deferred 工具时不改写前缀 | v1.4.0 #10940 | open |
| GitHub Copilot HTTP 413 算上下文溢出 | v1.4.0 #11016 | open |
| openai-codex 目录去掉 `gpt-5.5` 和 `gpt-5.3-codex-spark` | v1.4.0 #11173 | open |
| Cloudflare 分类器价格和上下文；分类器图片输入 | v1.4.0 changelog | done：`cloudflare-workers-ai` 上 Clef 输入价是每百万 token $0.24、上下文 65536，Clef Flash 是 $0.038 和 24576，Clef Omni 是 $0.15 和 64000，Jev 与 Jev 1.14 是 $0.042 和 32000。分类请求里 Clef 用最多四张 data URL，Jev 用 System One assets，OpenRouter 把 `image_url` 放进 state；`compat` 的 `imageInput` 和 `sendImageOptInHeader` 按字段盖过自动判断。codemode 的 `models.classify()` 不在这次 |
| Rex 终端：OSC 8、truecolor、行内图 | v1.4.0 #11131 | done：`TERM_PROGRAM=rex` 启用 OSC 8、truecolor 和 Kitty 行内图，没有 `COLORTERM` 提示也一样。泄漏的 `KITTY_WINDOW_ID` 不改变这三项。`CADR_HYPERLINKS=0` 只关掉超链接 |
| 未闭合 `$$` 不再吞掉后面的表；CJK 标点旁的粗体和斜体 | v1.4.0 #11159 #10730 | done：未闭合的 `$$` 或 `\[` 后面如果出现 GFM 表，表仍画成框，不再被公式块吞掉；闭合的多行公式后面的表照常渲染。`**这是测试。**后面`、`*斜体。*后面`、`字**「引用」**字` 会把标点包进粗体或斜体，`**end.**Then next` 仍保持字面量 |
| 进程没调用 `stop` 就退出时恢复终端模式 | v1.4.0 #11170 | done：进程没调用 `stop` 就退出时，exit 钩子同步写回鼠标跟踪、焦点上报、Kitty 键盘弹出、括号粘贴关闭和备用屏退出，Kitty 弹出在离开备用屏之前。正常 `stop` 之后这些序列只出现一次 |
| `@` 补全的查询含正则元字符时仍有结果 | v1.4.0 #10972 | done：fd 查询按字面转义。`@pages/[`、`@pages/(`、`@[id` 命中对应文件，不把 `[` 和 `(` 当字符类 |
| 扩展对话框叠放，关掉当前的再露出上一个 | v1.4.0 #11166 #9909 | open |
| Ctrl+Z 挂起后剪贴板进程不被一起挂起 | v1.4.0 #11179 | open |
| `mcp.json` 允许 UTF-8 BOM | v1.4.0 #11191 | open：以 UTF-8 BOM 开头的全局和项目 `mcp.json` 能读出各自的服务器，errors 为空。改写后的文件不再带 BOM，不剥 BOM 的 JSON 解析也能读出改过的条目；review-fail（2026-10-22）：上游 `packages/coding-agent/CHANGELOG.md` 明确该修复覆盖 `pi mcp add` / `pi mcp remove`，`packages/coding-agent/test/mcp-extension.test.ts` 用 `addMcpServerConfig` 在带 BOM 的全局文件中新增 `other`；cadr 的 `src/cadr-agent/extensions/mcp-config.lisp` 只提供 `update-mcp-server-config`，`src/cadr-agent/package.lisp` 也未导出 add/remove，`test/cadr-agent/mcp-config-test.lisp` 只更新既有 `demo`，未实现或锁死 add/remove 场景 |
| 恢复会话时，分支没记过的扩展工具默认仍激活 | v1.4.0 #11062 #11075 | done：恢复会话和 `/tree` 切到目标分支时，转录里从没加入或移除过的扩展工具仍然激活。注册时 `default-active` 为假的保持关闭。压实之前移除的工具保持关闭。内置工具只跟分支记下的装载走。`--tools` 允许列表之外的 `mcp__` 工具在切分支后仍不激活 |
| 输出上限截断的工具调用丢掉对应的工具结果 | v1.4.0 #11227 | done：会话停在输出上限截断的工具调用和它的工具结果上时，下一次提示把两者从投影上下文里一起去掉，请求里不再出现这条 `length` 助手消息和对应工具结果。输出已达到模型上限、换了模型、或自动折叠关闭时，这对消息仍留在请求里 |
| `grep` 使用 `rg --no-config` | v1.4.0 #11203 | done：工具自己的正则、字面、glob 和条数不受 `RIPGREP_CONFIG_PATH` 影响。配置里的 `--fixed-strings` 不会把 `a.` 变成字面搜索 |
| HTML 导出里 CJK 旁的粗体和斜体 | v1.4.0 #3353 #10154 | open |
| Windows 外壳探测、`pi update` 的 BOM、扩展加载 `@earendil-works/pi-ai/models`、生成的 models 参考文档、遥测 span | v1.4.0 | open：先裁决是否属于 cadr 的用户可见面 |
