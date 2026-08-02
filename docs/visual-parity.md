# Goal 9 Part B visual parity ledger

基线固定为 `earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`。
本文记录可机械验证的视觉与交互合约；最终观感仍由 B3 双终端 A/B 门禁裁决。

## B2 方法论：视觉合约包含运行时状态

B2 不再把静态常量、单次组件 render 或最终字符串相等视为充分证据。视觉合约
同时覆盖组件在真实事件序列中的状态与状态转换：

- 选择器必须覆盖空列表、过滤后零候选、首项、末项、翻页、循环导航和确认；
- 工具必须覆盖 running、partial、success、error、折叠/展开及耗时文案；
- assistant/tool 流式输出必须按真实 delta 逐帧重绘，保留原始换行，不得借用
  notice、日志或其他展示通道；
- 流式内容必须做逐字符等价门禁：对同一固定原文遍历每一个单切点以及代表性的
  多切点，最终组装文本和每个 `text` event payload 都必须与原文逐字符相等；
  空白 delta、空白+数字、连续数字、行首数字和非流式路径均为必测边界；
- provider 能力不能由单一实现代测：每个 provider × 每个 thinking level 都必须
  断言请求能力参数以及是否发出 thinking start/delta/end，Responses reasoning
  summary 与 chat-completions reasoning content 分属独立通路；未知/临时 model id
  也必须进入同一矩阵；
- editor 必须按终端可能交付的码点边界逐步输入并逐帧 render，包括空字符串、
  CJK、combining mark、emoji ZWJ 中间态；
- 命令、键位、overlay 和 footer 必须验证从 input decoder 到运行时状态再到最终
  virtual screen 的完整链路，不能只比提示文案或构造后的静态组件；
- 键位门禁必须喂入真实终端原始字节：legacy、Kitty、xterm
  modifyOtherKeys、带 modifier 的 CSI 方向键均单独覆盖；完整但未知的 escape
  sequence 必须原子丢弃，绝不能把参数字节降级成 editor 文本；
- provider transport 必须覆盖 TLS handshake、已连接但未收 headers、流式读取三种
  abort 时机；abort 只允许收敛为 `Request was aborted`/`Operation aborted`，普通
  native transport failure 只允许归一化为 `fetch failed`，禁止泄漏 SAP、OpenSSL
  函数名或构建机 C 源码路径；
- 工具成功/失败/参数回显和每个 overlay 的每一行提示文案必须以完整字符串或
  完整 virtual-screen snapshot 逐字断言；只搜索关键词、只检查样式 token 或仅
  断言事件类型不构成视觉合约证据。
- 无 overlay 的基础屏幕与 overlay 同级：冷启动、单轮、三轮、恰好填满、溢出、
  thinking、tool 折叠/展开、active status、widget、滚动 viewport 和窄屏都必须锁定完整 virtual
  terminal 字节；组件级顺序、行数或关键词断言不能代替整屏门禁。
- 整屏 SHA 只证明 fixture 未漂移，不证明 fixture 正确。每个 SHA case 必须同时有一条
  从固定基线 `file:line` 直接推导的独立语义 oracle（首行、自然高度、顺序、间距或
  可见窗口合同），并由 case-name 双向一致性门禁保证不能只新增 hash。oracle 的期望
  禁止从 Cadr 当前 render 结果生成；修改 hash 时必须先说明基线合同并更新独立断言。

确定性门禁优先使用 faux provider + virtual terminal；只有真实进程、终端模式或
信号生命周期无法在进程内等价覆盖时才使用 PTY。每个现场缺陷先保留能复现原故障
的红测，再以同一断言转绿。B3 仍负责真实终端观感，但不再替 B2 发现可自动化的
崩溃、边界态和状态错误。

状态只允许：

- `一致`：进入 Part B 前已等价，或本轮复核未发现差异。
- `不一致（已改齐）`：本轮发现差异、实现修正并有永久门禁。
- `有意差异`：须有用户批准并登记 README。本轮有两项用户裁决：所有选择器
  双向循环，以及 bash 标题永不显示 timeout。

## B1. 可复现的基线 TUI

审计 checkout：

```bash
git -C /root/projects/pi-mono worktree add --detach \
  /tmp/cadr-parity-74caa2649 \
  74caa2649f10ed71b4378ce69f5d9fbfd2466ca5
cd /tmp/cadr-parity-74caa2649
npm ci --ignore-scripts
npm run hydrate:model-data
npm run build:offline
./node_modules/.bin/tsx packages/coding-agent/src/cli.ts --version
# 0.83.0
```

2026-07-31 机械复核：

```text
git rev-parse HEAD
74caa2649f10ed71b4378ce69f5d9fbfd2466ca5

./node_modules/.bin/tsx packages/coding-agent/src/cli.ts --version
0.83.0
```

基线 TUI 已在 `tmux` 100×32 PTY 中冷启动并以 `/quit` 正常退出。启动命令：

```bash
PI_CODING_AGENT_DIR=/tmp/cadr-goal9-pi-agent \
PI_OFFLINE=1 \
./node_modules/.bin/tsx packages/coding-agent/src/cli.ts \
  --provider deepseek --model deepseek-chat \
  --no-session --offline --no-extensions --no-skills \
  --no-prompt-templates --no-themes --no-context-files \
  --no-approve --alt
```

## B2.1 主题与完整内置色板

基线来源：

- `packages/coding-agent/src/modes/interactive/theme/{dark,light}.json`
- `packages/coding-agent/src/modes/interactive/theme/theme.ts:185-290,330-405,646-870,886-950`
- `packages/coding-agent/src/modes/interactive/theme/theme-controller.ts:18-60`

Cadr 实现与门禁：

- `src/cadr-tui/theme.lisp:3-529`
- `src/cadr-cli/interactive-services.lisp:2079-2184`
- `src/cadr-cli/tui.lisp:2250-2591,2810-2940`
- `test/cadr-tui/theme-test.lisp:135-308`
- `test/cadr-cli/part-b-interactive-test.lisp:751-818`
- `test/cadr-cli/tui-test.lisp:2241-2633`

| ID | 合约与复核结论 | 状态 |
|---|---|---|
| TH-01 | 固定主题、`light/dark` auto、未配置时 OSC 11 单次检测、auto DSR→OSC 11、`COLORFGBG` ANSI256→RGB relative luminance `>=0.5`、dark fallback 均对齐；auto/fixed 在运行期动态启停通知。 | 不一致（已改齐） |
| TH-02 | 自定义主题按完整 schema 校验；100 ms debounce 热重载；临时缺失或无效时保留最后有效主题。 | 不一致（已改齐） |
| TH-03 | 真彩前景/背景分别用 `38;2`/`48;2`，局部恢复分别为 `39`/`49`。 | 不一致（已改齐） |
| TH-04 | 256 色 cube/gray 候选、`0.299/0.587/0.114` 距离和 gray 胜出条件逐项对齐。 | 不一致（已改齐） |

完整内置色值如下；大小写不影响 RGB 值。

| Semantic token | Dark | Light |
|---|---:|---:|
| accent | `#8abeb7` | `#5a8080` |
| border | `#5f87ff` | `#547da7` |
| borderAccent | `#00d7ff` | `#5a8080` |
| borderMuted | `#505050` | `#b0b0b0` |
| success | `#b5bd68` | `#588458` |
| error | `#cc6666` | `#aa5555` |
| warning | `#ffff00` | `#9a7326` |
| muted | `#808080` | `#6c6c6c` |
| dim | `#666666` | `#767676` |
| text | `#d4d4d4` | `#1f2328` |
| thinkingText | `#808080` | `#6c6c6c` |
| selectedBg | `#3a3a4a` | `#d0d0e0` |
| userMessageBg | `#343541` | `#e8e8e8` |
| userMessageText | `#d4d4d4` | `#1f2328` |
| customMessageBg | `#2d2838` | `#ede7f6` |
| customMessageText | `#d4d4d4` | `#1f2328` |
| customMessageLabel | `#9575cd` | `#7e57c2` |
| toolPendingBg | `#282832` | `#e8e8f0` |
| toolSuccessBg | `#283228` | `#e8f0e8` |
| toolErrorBg | `#3c2828` | `#f0e8e8` |
| toolTitle | `#d4d4d4` | `#1f2328` |
| toolOutput | `#808080` | `#6c6c6c` |
| mdHeading | `#f0c674` | `#9a7326` |
| mdLink | `#81a2be` | `#547da7` |
| mdLinkUrl | `#666666` | `#767676` |
| mdCode | `#8abeb7` | `#5a8080` |
| mdCodeBlock | `#b5bd68` | `#588458` |
| mdCodeBlockBorder | `#808080` | `#6c6c6c` |
| mdQuote | `#808080` | `#6c6c6c` |
| mdQuoteBorder | `#808080` | `#6c6c6c` |
| mdHr | `#808080` | `#6c6c6c` |
| mdListBullet | `#8abeb7` | `#588458` |
| toolDiffAdded | `#b5bd68` | `#588458` |
| toolDiffRemoved | `#cc6666` | `#aa5555` |
| toolDiffContext | `#808080` | `#6c6c6c` |
| syntaxComment | `#6a9955` | `#008000` |
| syntaxKeyword | `#569cd6` | `#0000ff` |
| syntaxFunction | `#dcdcaa` | `#795e26` |
| syntaxVariable | `#9cdcfe` | `#001080` |
| syntaxString | `#ce9178` | `#a31515` |
| syntaxNumber | `#b5cea8` | `#098658` |
| syntaxType | `#4ec9b0` | `#267f99` |
| syntaxOperator | `#d4d4d4` | `#000000` |
| syntaxPunctuation | `#d4d4d4` | `#000000` |
| thinkingOff | `#505050` | `#b0b0b0` |
| thinkingMinimal | `#6e6e6e` | `#767676` |
| thinkingLow | `#5f87af` | `#547da7` |
| thinkingMedium | `#81a2be` | `#5a8080` |
| thinkingHigh | `#b294bb` | `#875f87` |
| thinkingXhigh | `#d183e8` | `#8b008b` |
| thinkingMax | `#ff5fff` | `#af005f` |
| bashMode | `#b5bd68` | `#588458` |
| pageBg | `#18181e` | `#f8f8f8` |
| cardBg | `#1e1e24` | `#ffffff` |
| infoBg | `#3c3728` | `#fffae6` |

真彩/256 色同一输入的机械 capture：

```text
truecolor accent-fg = ESC[38;2;138;190;183m
truecolor user-bg   = ESC[48;2;52;53;65m
256-color accent-fg = ESC[38;5;109m
256-color user-bg   = ESC[48;5;59m
foreground reset    = ESC[39m
background reset    = ESC[49m
```

原始字节证据保存在 `/tmp/cadr-goal9-color-capture.txt`。

## B2.2 布局、Markdown、工具、footer、选择器与动效

| ID | 基线合约与 Cadr 证据 | 状态 |
|---|---|---|
| LY-01 | root 顺序为 startup/chat/pending/status/widgets/editor/footer；above-editor widget container 在空态保留一行、非空态保留一行 leading spacer，below-editor container 不自带 spacer；`src/cadr-cli/tui.lisp:461-474,2109-2329`，`GOAL9-B3-BASE-SCREEN-ABOVE-EDITOR-SPACER-MATCHES-BASELINE-COMPOSITION`。 | 不一致（已改齐） |
| LY-02 | user 全宽背景 X=1/Y=1；assistant 无背景且可见内容前一空行；thinking muted+italic；`src/cadr-cli/tui.lisp:1689,1758,1872`。 | 不一致（已改齐） |
| LY-03 | tool 前 spacer、X=1/Y=1、状态背景；`src/cadr-tui/components.lisp:1567` `render-tool-block`。 | 不一致（已改齐） |
| LY-04 | editor 只有上下 `─`，高度 `max(5,floor(rows*0.3))`，滚动信息在边框；`src/cadr-tui/editor.lisp:1551` `render-editor`。 | 不一致（已改齐） |
| LY-05 | select primary=32、gap=2、description min=10、默认 5 行、宽度 `<=40` 关闭 description；`src/cadr-tui/components.lisp:1923,2024`。 | 不一致（已改齐） |
| LY-06 | overlay 默认 `min(80,width)`，selector 自身边框、spacer 和窄屏裁剪；`src/cadr-tui/overlay.lisp:79` `resolve-overlay-layout`、`src/cadr-cli/tui.lisp:1997`。 | 一致 |
| MD-01 | H1/H2/H3+ 样式、H3+ 前缀和 block spacing 对齐。 | 不一致（已改齐） |
| MD-02 | code fence、两格缩进、在册语言语法着色、未知语言 code-block 色对齐；完整移植基线 `syntax-highlight.test.ts` 的 span/entity/继承、TS、diff、regexp、decorator、HTML 门禁，并覆盖 HTML/diff/JSON/Bash/SQL 可见 token 边界与 Python/Bash URL 反例。审计基线完成态本身保留开、闭 fence 行，因此看到字面 <code>```text</code> / <code>```</code> 是已核实非差异。 | 不一致（已改齐） |
| MD-03 | quote `│ `、italic、HR 80-cell cap 对齐。 | 不一致（已改齐） |
| MD-04 | ordered/unordered/task marker、四格嵌套和 continuation 对齐。 | 不一致（已改齐） |
| MD-05 | link underline/color、OSC 8 与 fallback URL 规则对齐。 | 不一致（已改齐） |
| MD-06 | 表格宽度分配、wrap、粗体 header、完整 box、窄屏 raw fallback 对齐。 | 不一致（已改齐） |
| MD-07 | inline style 局部恢复、streaming partial fence 防闪烁对齐。 | 不一致（已改齐） |
| TL-01 | pending/success/error 背景、title/argument/output/error/warning 语义色对齐；真实 bash 非零退出必须从 tool result 传播为红底 error state，标题仍为 `$ command` 且不添加状态 glyph，文案为 `Command exited...`。 | 不一致（已改齐） |
| TL-02 | collapsed preview：bash 5、write 10、grep 15、find/ls 20；成功 read 折叠态不显示结果，展开后显示完整结果，error 始终可见。 | 不一致（已改齐） |
| TL-03 | real edit 结果进入 diff renderer；context/add/remove 色、单行 word inverse、tab→3 spaces 和超长行上限对齐；bash running/settled 显示 `Elapsed`/`Took`。 | 不一致（已改齐） |
| TL-04 | 默认 active tools、顺序、description、prompt snippet/guidelines 对齐基线 `read,bash,edit,write`；`grep/find/ls` 仅显式启用，避免模型因提示偏离改用 bash echo/sed。 | 不一致（已改齐） |
| TL-05 | 用户裁决：bash 标题无论是否显式传入 timeout 均只显示 `$ command`，不显示 `(timeout Ns)`。这与审计基线 `bash.ts:226-231` 的显式 timeout 后缀有意不同。 | 有意差异 |
| FT-01 | cwd/branch/session；input/output/cache read/write/hit/cost/context；provider/model/thinking；extension status 三行布局对齐。 | 不一致（已改齐） |
| FT-02 | context `>70%` warning、`>90%` error 对齐。 | 不一致（已改齐） |
| FT-03 | working/retry/compaction spinner、语义色与 status 区域对齐。 | 不一致（已改齐） |
| FT-04 | `/login`、`/model`、thinking、subscription、auto-compaction 均从 live agent state 刷新；editor thinking/bash border 同步。 | 不一致（已改齐） |
| SL-01 | generic selected `→ ` + accent、muted description、scroll/no-match 主题对齐。 | 不一致（已改齐） |
| SL-02 | session selected row 使用全宽 `selectedBg`；tree 只给固定 gutter/body segment 着色，不错误 padding 到整行。 | 不一致（已改齐） |
| SL-03 | model 最多 10 行、accent selected、muted provider、green `✓`、border/spacer 对齐。 | 不一致（已改齐） |
| SL-04 | autocomplete primary 12..32、默认 5、配置 3..20、仅 `@` 20 ms debounce、popup 在下边框后。 | 不一致（已改齐） |
| SL-05 | 用户裁决：所有选择器在首末项双向循环，空列表保持稳定；基线各选择器并非统一循环，故作为有意差异登记。 | 有意差异 |
| AN-01 | spinner `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`，80 ms；loader 前一空行。 | 不一致（已改齐） |
| AN-02 | render 16 ms throttle；terminal progress 1 s keepalive；`showTerminalProgress` 每事件读取且关闭立即 clear。 | 不一致（已改齐） |
| AN-03 | IME zero-width marker、inverse fake cursor、hardware cursor 放置/隐藏/恢复对齐。 | 不一致（已改齐） |
| AN-04 | resize invalidation、alternate screen、scroll/follow、mouse、autowrap 与退出恢复已有等价实现。 | 一致 |

Markdown 门禁：

- `test/cadr-tui/components-test.lisp:130-820`
- `test/cadr-tui/component-parity-test.lisp:159-331`
- `src/cadr-cli/interactive-services.lisp:2935-3950`
- `test/cadr-cli/part-b-interactive-test.lisp:1352-1485,1821-1881`
- `test/cadr-cli/tui-test.lisp:1695` `GOAL9-TUI-MARKDOWN-TRANSFORMERS-COVER-USER-TEXT-THINKING-STREAMING-AND-CACHE`
- `test/cadr-cli/goal9-b-runtime-parity-test.lisp:174` `GOAL9-STREAMED-MARKDOWN-FENCE-IS-EXACT-THROUGH-THE-FULL-TUI-CHAIN`

工具、footer、选择器与动效门禁：

- `test/cadr-tui/components-test.lisp:229-568`
- `test/cadr-tui/editor-parity-test.lisp:224-521`
- `test/cadr-tui/terminal-colors-test.lisp:108-251`
- `test/cadr-cli/tui-test.lisp:223-1415,2334-2700`
- `test/cadr-cli/part-b-interactive-test.lisp:1671-2180`

第三轮机械账本：35 个编号项中 `一致` 2 项，`不一致（已改齐）` 31 项，
`有意差异` 2 项，`pending` 0 项。定向门禁、隔离/当前用户全量、PTY lifecycle、
隔离 native build 与提交证据均已落账；README 差异登记已同步。B3 真实双终端
A/B 已由用户确认，Part B 已关闭。

### B2 运行时补充门禁

2026-07-31 首轮及 2026-08-01 第二轮 B3 真实双终端 A/B 退回后，新增以下原机械账本没有覆盖的
运行时矩阵；测试名和红→绿证据在 `docs/acceptance/goal-v9-part-b.md` 逐项列出。

| 状态面 | 必测转换 |
|---|---|
| selector | empty/filter-empty/first/last/page/wrap/select |
| editor | empty→incremental Unicode→ZWJ intermediate→complete grapheme |
| assistant stream | start→每个 delta→final multiline document |
| Markdown stream | delta→TUI entry→Markdown renderer→virtual terminal 全链路逐帧保留 fence 与空 code line |
| stream content | 每个单切点/代表性多切点→逐字符相等；纯空白、空白+数字、连续数字、行首数字、非流式 |
| provider thinking | 每个 provider × 每个 thinking level × catalog 命中/未知 model→payload 与 start/delta/end |
| tool | start/running/partial→success 或 error→collapsed/expanded |
| tool model result | 每个注册内置工具的 success/error/continuation/truncation result→逐字文案、原始 path、UTF-16/行数/byte/limit 数值口径；与 TUI preview 分层断言 |
| exact copy | tool success/error/args、全部 overlay 每一行与基础屏幕状态矩阵→完整 snapshot 逐字相等；15 个 overlay 必须带非空 transcript，另有 13 个 base-screen 状态，分别锁定整屏 SHA-256 |
| command UI | command→refresh→overlay→navigation→cancel/select |
| application keys | raw legacy/Kitty/xterm/Windows Terminal bytes→configured action→busy/idle behavior；未知完整 sequence→atomic ignore |
| busy interaction | long-running child→Escape→process-group termination→error tool result→idle；TLS handshake/connected-before-headers/silent SSE→active socket shutdown + blocked Lisp operation interrupt→aborted assistant→idle；parallel tools→shared cancellation；busy Enter/Alt+Enter→steering/follow-up queue→exact pending rows→configured dequeue key→both queues restored to editor→mode-controlled drain；repeated Escape→single silent abort |

The busy-interaction row is a lifecycle contract, not a static key or screen
contract. Its permanent gates couple the production TUI input loop to a faux
agent and a real detached bash process: `GOAL10-BUSY-BASH-ABORT-KILLS-GROUP-REPORTS-ERROR-AND-SETTLES-AGENT`,
`GOAL10-BUSY-PARALLEL-TOOL-ABORT-REACHES-ALL-RUNNING-EXECUTORS`,
`GOAL10-BUSY-TUI-ESCAPE-ABORTS-ACTIVE-TOOL-AND-RETURNS-IDLE`,
`GOAL10-BUSY-TUI-ENTER-AND-ALT-ENTER-USE-DISTINCT-QUEUES`,
`GOAL10-BUSY-TUI-STEERING-IS-DELIVERED-AFTER-THE-ACTIVE-TURN`, and
`GOAL10-BUSY-TUI-REPEATED-ESCAPE-DOES-NOT-SPAM-ABORT-NOTICES`. Static
keybinding assertions, queue unit tests, and idle full-screen SHA snapshots do
not satisfy this row.

The third and fourth user A/B rounds added the missing cross-layer gates. Local
servers now hold the request at TLS handshake, connected-before-headers, and
silent SSE phases. Abort closes the socket and interrupts the blocked SBCL
operation, so it does not wait for a peer byte and cl+ssl cleanup cannot replace
the product condition with `SSL_shutdown` diagnostics. The production decoder
is driven with xterm/Windows Terminal `ESC[1;3A`, xterm modifyOtherKeys
`ESC[27;3;13~`, Kitty `ESC[13;3u`, and the legacy `ESC CR` fallback. Thus
`alt+up` dequeues while Alt+Enter and Enter remain distinct follow-up/steering
actions. Pending rows are exact-copy asserted. The abort component owns exactly
one `Spacer(1)` above the baseline `Text(..., outputPad=1)` rendering: one blank
row, then one horizontal padding cell followed by `Operation aborted`, with no
`Abort requested`, `session>`, `SB-SYS`, `SSL_`, or `../ssl/` row.

### B2 基础屏幕整屏合约

用户 A/B 先后发现最后一行 transcript 与 editor 上边框过近，以及短会话整体被锚在
viewport 底部。两者都不是 `Output padding` 或 `Editor padding` 的数值问题。基线构成如下：

| 区域 | 基线 `74caa2649` 证据 | Cadr 结论 |
|---|---|---|
| transcript 顶部 | `interactive-mode.ts:758-817`：header 自带前后各一个 `Spacer(1)`；无 header/chat 时没有额外固定顶部 margin。 | `render-tui-state` 的 startup 前后各一空行；冷启动、单轮、三轮整屏快照锁定。已核实一致。 |
| transcript 条目间 | `interactive-mode.ts:3318-3369`：已有 chat 后的新 user 前加一个 spacer，assistant 直接追加；`assistant-message.ts:100-114` 仅在可见 assistant 内容前加一个 spacer。 | `src/cadr-cli/tui.lisp:1983-1999` 同构；单轮、多轮、thinking 快照锁定。已核实一致。 |
| status 前后 | `packages/tui/src/components/loader.ts:43-45`：active loader 自带一个前置空行；`status-indicator.ts:105-113`：idle status 占两个全宽空行；status container 不另加尾部 margin。 | `src/cadr-cli/tui.lisp:925-967` 同构；active/idle 与复合顺序测试锁定。已核实一致。 |
| above-editor widget | `interactive-mode.ts:2044-2072`：空容器也放一个 `Spacer(1)`；非空容器先放一个 leading `Spacer(1)`，widget 后不加 spacer。该容器位于 status 与 editor 之间（`:734-746`）。 | 原实现空态返回零行，正是截图差异根因；`src/cadr-cli/tui.lisp:461-474,2181-2186` 已按同一规则修正 base-screen 路径。 |
| below-editor widget | `interactive-mode.ts:2044-2072`：空态零行，非空态无 leading/trailing spacer；根顺序在 editor 与 footer 之间（`:743-746`）。 | `src/cadr-cli/tui.lisp:2187-2192,2311-2324` 同构；below-widget 整屏与复合顺序测试锁定。已核实一致。 |
| editor 与 footer | `interactive-mode.ts:497-505` 的 editor padding 只作为 `paddingX`；`packages/tui/src/components/editor.ts:482-530` 只改变横向内容宽度。`settings-manager.ts:120,1201-1202` 明定 output padding 是 chat message 的 horizontal padding，并由 `user-message.ts:38-57`、`assistant-message.ts:100-114` 使用。editor、below widgets、footer 在根容器中直接相邻（`interactive-mode.ts:743-746`）。 | 未发现垂直间距偏差；editor→below widget→footer 无固定空行，复合顺序与整屏矩阵锁定。 |
| 短内容与溢出 | `packages/tui/src/tui.ts:235-244` 只按 child 顺序串接实际行；`TuiMainScreen.ts:162-212` 首帧只写这些行，`bufferLength=max(height,newLines.length)` 仅用于 viewport 记账，不向根布局插入 filler；`:354-370` 仅在内容越过 viewport 时让终端滚动。`TuiAltScreen.ts:350-389` 同样先切 document，空行只追加在完整 composition 之后。 | `src/cadr-cli/tui.lisp:2811-2834` 只裁剪溢出的 transcript，并直接串接 pending/status/widget/editor/footer；短内容不补 viewport 高度，空白自然留在 footer 下方。恰好填满与溢出门禁分别证明无提前裁剪和 tail scroll。 |

因此两次基础屏幕修复分别是恢复 host-owned above-editor spacer，以及移除根布局中
不存在于基线的 flexible viewport filler；不是把用户的 padding 配置从 `1` 调成别的
数。第四轮又纠正 overlay 架构：基线 root 始终保留 chat container
（`interactive-mode.ts:734-746`），`showSelector` 只把 editor container 的 editor
替换为 selector（`:4161-4175`）。Cadr 现在同样保留并按剩余 viewport 裁剪
transcript，只在 editor slot 渲染 overlay；旧的 15 个空 transcript 快照无法证明这条
合约，现已全部以固定非空 transcript 和“editor sentinel 不可见”重新生成。

新增 `test/cadr-cli/goal9-b3-base-screen-contract-test.lisp`，固定时间、spinner、尺寸、
provider/model/cwd，并对 virtual terminal 全屏逐字节计算 SHA-256：

| 状态 | 尺寸 | SHA-256 |
|---|---:|---|
| cold-start | 80×24 | `7D6B66412D3734322CB29B8E24C95C5978B4FACC77FB89A811A6D58AB3F27D7B` |
| single-turn | 80×24 | `0732A443161016877BD9A9FC46AE593AAE2110B0ACE7F903635EA3CBB3B2A48C` |
| multi-turn (3 rounds) | 80×28 | `DC4A5F74E3FCB6EFDAAA1A55E3555F34FEF8D686A358F00ADECA00BD00180104` |
| viewport-exact-fill | 80×13 | `E0493BAA8CFBBC1DF15E3254EF007840E1571AE163AF3010A04552FC71B59A7F` |
| viewport-overflow | 80×14 | `53E1B55B933BEBCE43EDE639DB093965B148044B34191193152C067D1647CBE8` |
| thinking | 80×24 | `AB0F8F4025EE9D5E026FF2FDC8AB8ABBF452926F61223944F965CFA8E567E310` |
| tool-collapsed | 80×24 | `469F3BAE304DAC110474BFF5CB01483B72E4992C22E4B5EF7777B06018EF7343` |
| tool-expanded | 80×24 | `DF40154B2A6E7B7F5E4E986B8498278881EF24CC7E98554509B2D84E23A5D0CC` |
| active-status | 80×24 | `5B07189D441990503213180DB156B1106C0FDD95A83109BD6E93C13E84576BA1` |
| above-widget | 80×24 | `3AF104FBC8FF61878FF37623FFB539799A28BEE22BE538726F08D2DF277A53D0` |
| below-widget | 80×24 | `DC70F236342B1A935721471779EBCFA86DD0EFBE5CD4B9695148D5D33FE794D4` |
| overflow-scrolled-to-top | 52×14 | `D15615BBF1F0A2F18155DAF639EAD4A2F49DAF29DA38ABF2D95A170242A5BEFD` |
| narrow-width | 32×14 | `A417E912682A61AEB48FD0653D9E2CF1BBECF46D34ED09F44F64896619948596` |

此前 7192 条检查没有捕获 above-editor spacer；当时基础屏幕只有组件 fragment 和
局部 virtual-terminal 断言。后来建立整屏 SHA 后，用户指出的 10236 条（本轮开工
前因 Apple Terminal 门禁已为 10269 条）仍没捕获短会话底锚：`single-turn` 与旧
`multi-turn` 的 expected hash 正是从错误实现生成的，快照只防漂移却把缺陷固化，且
没有“短 document 行数必须小于 viewport、首个消息不得被 flexible filler 推下去”的
独立语义断言，也没有恰好填满/刚溢出的边界状态。新增
`GOAL9-B3-SHORT-CONVERSATION-COMPOSITION-STACKS-FROM-THE-TOP` 与
`GOAL9-B3-VIEWPORT-EXACT-FILL-AND-OVERFLOW-FOLLOW-BASELINE-SCROLL-POLICY`
先锁布局不变量，再由 13 个整屏 SHA 锁具体字节。未触及此次布局路径的四个既有
基础屏幕快照（tool collapsed/expanded、scroll-to-top overflow、narrow width）以及
全部 15 个 overlay 整屏快照保持逐字节不变。

### B2 autocomplete 触发与用户输出通道

autocomplete 的自然触发按基线 `editor.ts:2085-2100,2140-2163,2219-2229,2347-2350`
统一为同一套上下文门禁：空输入、空格、连续空格与普通路径片段不触发；`/` 只在消息
起始位置触发，`@` 与注册字符只在 token 边界触发；显式 Tab 可强制路径补全。弹层
已打开时，text/backspace/delete 保留原 natural/force 模式重新查询；输入空格后若自然
候选不再匹配则关闭，强制路径弹层仍保持 force 模式。对应门禁覆盖空前缀、空格、连续
空格、`/`、`@`、路径片段、删除到空以及打开弹层后输入空格。

用户输出通道同时按“产品输出可见、基础设施诊断隔离”审计。扩展主动写入 stdout/stderr
仍可见；ASDF/编译器/loader verbose、`setsid` 包装器、桌面 URL launcher、OAuth browser
launcher，以及 cl+ssl/OpenSSL/SBCL socket diagnostics 不得进入 transcript、tool result
或模型上下文。provider transport 的普通失败逐字为 `fetch failed`；用户 abort 逐字为
`Request was aborted`，由 TUI 显示 `Operation aborted`。模型目录刷新只把真实网络/解析
错误呈现为产品错误；前台 package-manager CLI 的安装进度仍按基线保留。完整边界清单
与逐项回归测试见 `docs/acceptance/goal-v10-visual-output-followup.md`。

第五轮补齐 notice 通道自身的视觉边界：`session>` 只属于 REPL 协议，不属于任何
TUI notice/status/error/warning/success 行。普通 status、错误、警告、`/new` success
与 extension `notify` 已按基线分流；任意多行 frontend output 保留逐行内容但不再带
内部标签。折叠态成功 `read` 的“外层一行 + Box 上下各一行 + 标题一行”共四行且
无内容预览，已按 `read.ts:164-187`、`tool-execution.ts:63-75` 核实为非差异；展开态
output 与 bash timing 前各一空行才是本轮修正的真实布局差异。

Markdown 围栏与标题标记也登记为已核实非差异：固定基线
`packages/tui/src/components/markdown.ts:383` 原样保留“```lang”行并仅施加
`codeBlockBorder` 样式，`:341` 的 `headingPrefix` 原样保留重复 `#`。终端显示保留
Markdown 源标记是刻意设计，使复制出的文本仍是合法 Markdown；Cadr 不应把这些
标记吞掉或改成仅视觉格式。

### B2 overlay 完整逐行合约

第三轮不再以“抽查六个 overlay”代表全部交互面。下表已由当前机械门禁锁定；
每一行均以去 ANSI 的完整行数组、ANSI 语义样式和首末循环事件共同验证。

| Surface | 标题 | 提示 | 搜索 | 条目、顺序和值 | 计数 | 选中、边框与间距 | 描述 | 循环 |
|---|---|---|---|---|---|---|---|---|
| `/model` | 无额外 `Select Model` 标题 | 未 scoped 时 `Only showing models from configured providers. Use /login to add providers.`；刷新后 `Model catalogs refreshed.`；scoped 状态只显示 `Scope: all | scoped`，不显示 `tab scope (all/scoped)` | `> ` | 当前过滤顺序；`id [provider]`，当前模型 `✓` | 超 viewport 时位置/总数 | `→` accent；上下 `─`，各区块空行固定 | 选中项下 `Model Name: ...` | 双向 |
| `/settings` | 主层无伪造标题；子层为 `Thinking Level`、`Theme`、`Light Theme`、`Dark Theme`、`Automatic Theme` | 主层 `Enter/Space to change · Esc to cancel`；子层 `Enter to select · Esc to go back` | 主层 type-to-search | 与基线能力门控一致：supports-images=nil 为 25 项；true 时在 Auto-compact 后追加 Show images、Image width，合计 27 项；子层候选顺序固定 | 10 行 viewport，按实际总数显示 `(i/25)` 或 `(i/27)` | `→` accent；上下边框；说明与列表间固定空行 | 宽屏显示 option description，窄屏换行/裁剪；子层显示说明 | 双向 |
| `/resume` | `Resume Session (Current Folder)`，右侧 scope/name/sort 状态 | scope、regex/exact、sort/named/delete/path/rename 两行 | `> query` | threaded/search 结果顺序；名称或首条消息、消息数与 age | viewport 时当前位置/总数 | 选中行全宽背景；上下边框与固定 spacer | cwd/path 按状态展示 | 双向 |
| `/fork` | `Fork from Message` | `Select a user message ... into a new session` | 无 | active path 的 user messages，原顺序；每项 `Message i of N` | 每项自带 `i of N` | `›` 选中；标题区、边框、条目间空行逐行固定 | 用户消息摘要 | 双向 |
| `/tree` | `Session Tree` | `↑/↓ move · ←/→ page · ctrl+←/→ branch · ctrl+x copy ...` 与 `filters ctrl+d/t/u/l/a ...` | `Type to search:` | 树序；tool call 为 `[bash: <args>]`、`[read: <path>]`，不得渲染 raw result | `(i/N)` | 固定 gutter 选中背景；上下边框与空行固定 | message/tool label、branch/label time | 双向 |
| `/login` 方法 | `Select authentication method:` | `↑↓ navigate  enter select  escape/ctrl+c cancel` | 无 | account 后 API key；值为对应 auth type | 无 | `→`；上下边框及标题/列表/提示 spacer | 无 | 双向 |
| `/login` provider/API key | `Select provider to configure:`；输入层 `Login to <provider>` | provider 选择后 OAuth 或 masked API key；`escape/ctrl+c cancel  enter submit` | provider 为 `> `；key 为 masked `> ` | provider 定义顺序；name、auth type、configured 状态 | viewport `(i/N)`；空态精确文案 | `→`；上下边框及固定 spacer | `[subscription]`/`[API key]` 与 credential source | 双向 |
| `/logout` | `Select provider to logout:` | 空态 `No providers logged in. Use /login first.` | `> ` | 已存 credential 投影，稳定排序；不混入 env/config-only 项 | viewport `(i/N)` | `→`；上下边框及固定 spacer | auth type 与 configured/source | 双向 |
| `/scoped-models` | `Model Configuration` | `Session-only. ctrl+s to save to settings.` 与完整操作提示 | `> ` | session order；unavailable id 保留；enabled `✓`/disabled `✗` | enabled/unavailable 状态及 viewport | `→` accent；上下边框及固定 spacer | `Model Name: ...` | 双向 |
| `/import` | `Import session` | `Replace current session with <path>?`；`↑↓ navigate  enter select  escape cancel` | 无 | `Yes` 后 `No`；值含 confirmed flag、原命令与 path | 无 | `→`；上下边框及固定 spacer | 无 | 双向 |
| `/trust` | `Project trust` 与 cwd | `↑↓ navigate  enter save  escape cancel` | 无 | Trust、Trust parent folder、Do not trust | 无 | `→`；上下边框及固定 spacer | saved decision、current session、parent path | 双向 |
| extension custom UI | extension 提供的单行/多行 title | 通用 `↑↓ navigate  enter select  escape cancel` | 由扩展 surface 决定 | 扩展提供的 label/value 原顺序 | generic viewport | `→`；framed select 上下边框与固定 spacer | 扩展提供 description | 双向；真实 extension worker→live TUI bridge→键盘选择→返回值已回归 |
| autocomplete | 无标题 | 无额外提示 | editor 当前 `/command`、`/model ...`、`/login ...` 或 `@path` prefix | command 规范顺序/匹配排序；model/provider/path items 与真实 value | `autocompleteMaxVisible` 限制 | selected `→`，popup 位于 editor 下边框后，无 overlay 外框；`@path` 有完整 40×8 virtual-screen 门禁 | 宽度允许时显示 description | 双向 |
| `/sessions`、`/switch`、`/branch`、`/install` | 基线无对应 slash/TUI surface | Cadr 已从内置 slash dispatch、overlay 与 autocomplete 全部删除；直接输入只按普通未知输入路径处理，不构成命令 alias 或隐藏 backend | 无 | 无 | 无 | 无 | 无 | 不适用 |
| `/compact` | 基线无 overlay | 当前直接执行 compaction，并在 status/transcript 呈现进度或结果 | 无 | 无 | 无 | 无 | compaction status | 不适用 |
| `/export` | 基线无 overlay | 当前直接按默认 HTML 或显式 path 导出并 notice 结果 | 无 | 无 | 无 | 无 | 输出 path | 不适用 |
| `/reload` | 基线无 overlay | 当前直接 reload keybindings/extensions/skills/prompts/themes/context；成功后以无 `session>` 前缀的 dim status 显示基线原文 | 无 | 无 | 无 | 无 | reload summary | 不适用 |

15 个 overlay（含独立 `/logout` surface）的完整 virtual-screen SHA-256 由
`GOAL9-B3-EVERY-OVERLAY-HAS-AN-EXACT-FULL-VIRTUAL-TERMINAL-SNAPSHOT` 锁定；
每个 fixture 都含固定 user/assistant transcript，且断言 editor sentinel 被 selector
替换。第四轮重建后的 SHA-256 为：

| Overlay | SHA-256 |
|---|---|
| model | `F00B20118A954C3CCFA6780ACECC9AAD5887EDD168913EEDC121D9250354AD3F` |
| model-scoped | `E45CF44928EA432C79CC93DBD359FA92ECCA37B2D6D97FA8A3463559AFEDE4D8` |
| settings | `BF8F74675A66393CE5F4A50785B71F78F7F54B3617358DF4D4A9C70E2C1C3AFA` |
| resume | `97547661CA2C621716565AD8322C0A886B922114D4798EAD4AEFC9AEF0FF6B4B` |
| fork | `3741D9EBD09665BE6701FD957B2071E07A621804192CD2E0E1E4E765A577FF60` |
| tree | `3E181C19A4FF90C824918E713E3B738E00C4F456BC6AEBB3AB7F2BF9235B597F` |
| scoped-models | `C70BE56733530B2E2839E3EDF65B0FE93A09EEC09C2C3B67A6BF70DE22136038` |
| trust | `ADCAA3E3FBE6FCC0075819C16FB67B5DC1EA6F5B7A4C8B3B5C6B6810E8A9F18C` |
| login-method | `ED15EB102E30928C4F4D5B3470FE1FE9D5F6B15C1294188FAE8327393FF57F85` |
| login-provider | `B3A4E71D71A37664D521F5F123D81B0E3B92E4DAB5E638FD14A311FF274F905E` |
| logout-provider | `CC22C0F6983E1975602A5AF28FCC22715A4152374C39577154D33365014B8B5D` |
| api-key | `E9A09DFE359B3AD1519A108F04A0405FA5F6F607B5A7F76F3EC90A9F56151179` |
| import | `CBB6A2FFE4C7F41DB4E4F73739D8D78BC4DBB04844016E6429E85B9E78D883F1` |
| extension-select | `D43F8F701FE98E73037B44854626149F5427B4D5A29CC48A5755425DD918ACE6` |
| extension-custom | `13C40C8025174E52DB871376BA85033BE5EEDD9F349163D36911A4C7DE01E0C5` |

### B2 SHA snapshot 独立语义 oracle 审计

仓库内视觉 SHA 只存在于上述 13 个 base-screen 与 15 个 overlay；provider 固定向量和
性能 artifact hash 不属于整屏快照。审计发现 base-screen 的 thinking、tool 两态、
scroll-to-top、narrow-width 五项没有与 SHA fixture 一一绑定的基线语义 oracle；
extension-custom 只有通用 transcript 保留和 selector 行为测试，没有该 fixture 的
直接视觉 oracle。其余项已有独立断言，但此前没有“SHA case 集合必须与 oracle 集合
完全相同”的机制。现由两个总门禁建立双向配对，完整结果如下。

| SHA case | 固定基线直接依据与独立断言 | 审计结果 |
|---|---|---|
| base `cold-start` | `interactive-mode.ts:734-746` 根顺序；首个 startup 内容固定在 row 1，随后 editor、footer | 已有，纳入总门禁 |
| base `single-turn` | `tui.ts:235-244` 只串接自然行；首条消息 row 1，document 高度小于 24 | 已有，纳入总门禁 |
| base `multi-turn` | 同上；三轮消息顺序不变，首条 row 1，document 高度小于 28 | 已有，纳入总门禁 |
| base `viewport-exact-fill` | `TuiMainScreen.ts:162-212`；自然高度恰为 13 时首条消息仍可见 | 已有，纳入总门禁 |
| base `viewport-overflow` | `TuiMainScreen.ts:354-370`；高度 14，旧首轮被裁、最新轮与 editor/footer 保留 | 已有，纳入总门禁 |
| base `thinking` | `assistant-message.ts:89-169`；user→thinking→answer，thinking 与 answer 间恰一空行 | **本轮补齐** |
| base `tool-collapsed` | `tool-execution.ts:63-75`、`bash.ts:199,234-310`；显示 earlier-lines、末五行和 timing，不显示前两行 | **本轮补齐** |
| base `tool-expanded` | 同上；完整 `one`…`seven`，不得显示 earlier-lines | **本轮补齐** |
| base `active-status` | `interactive-mode.ts:739-746`；answer→一空行→status→editor→footer | 已有，纳入总门禁 |
| base `above-widget` | `interactive-mode.ts:2044-2072,739-746`；host spacer 后 widget 紧邻 editor top | 已有，纳入总门禁 |
| base `below-widget` | 同上；editor bottom→widget→footer 无额外垂直行 | 已有，纳入总门禁 |
| base `overflow-scrolled-to-top` | `TuiAltScreen.ts:350-389`；14 行 viewport 顶部显示 transcript 01…07，不混入 editor/footer | **本轮补齐** |
| base `narrow-width` | `tui.ts:235-244` 与组件 wrap；32 列下 user/assistant 各两行且每行宽度不超 32 | **本轮补齐** |
| overlay `model` | `components/model-selector.ts:91-130,162-185,248-307`；hint→query→models→description | 已有，纳入总门禁 |
| overlay `model-scoped` | 同上；scope→query→scoped order→description→refresh notice | 已有，纳入总门禁 |
| overlay `settings` | `components/settings-selector.ts:472-738`、`settings-list.ts:80-165,237-249`；25 项顺序、count、description、help | 已有，纳入总门禁 |
| overlay `resume` | `components/session-selector.ts:119-175,414-519,685-746`；title/help/query/empty-state 顺序 | 已有，纳入总门禁 |
| overlay `fork` | `components/user-message-selector.ts:14-78,110-148`；title/help、两条 user message 与 `i of N` 顺序 | 已有，纳入总门禁 |
| overlay `tree` | `components/tree-selector.ts:664-851,1156-1252,1328-1385`；title、箭头 hint、filter hint、entries、count | 已有，纳入总门禁 |
| overlay `scoped-models` | `components/scoped-models-selector.ts:91-180,202-252`；title/help/query、enabled 状态、description、keys | 已有，纳入总门禁 |
| overlay `trust` | `components/trust-selector.ts:32-115`；cwd/state/options/help 顺序 | 已有，纳入总门禁 |
| overlay `login-method` | `interactive-mode.ts:5014-5039`、`extension-selector.ts:18-78`；两种 method 与 cancel help | 已有，纳入总门禁 |
| overlay `login-provider` | `components/oauth-selector.ts:51-160`；login title/query/providers 与 credential state | 已有，纳入总门禁 |
| overlay `logout-provider` | 同上；logout title/query/providers 与 credential state | 已有，纳入总门禁 |
| overlay `api-key` | `components/login-dialog.ts:30-71,154-167`；title/prompt/input/cancel-submit help | 已有，纳入总门禁 |
| overlay `import` | `interactive-mode.ts:2244-2281,2299-2305,5523`、`extension-selector.ts:18-78`；title/question/Yes-No/help | 已有，纳入总门禁 |
| overlay `extension-select` | `interactive-mode.ts:2244-2281,2299-2305`、`extension-selector.ts:18-78`；title/Alpha-Beta/help | 已有，纳入总门禁 |
| overlay `extension-custom` | `interactive-mode.ts:2494-2563`、`select-list.ts:74-137`；transcript 后选中 Alpha 再 Beta，footer 在其后 | **本轮补齐** |

`GOAL9-B3-EVERY-BASE-SCREEN-SHA-HAS-A-BASELINE-DERIVED-SEMANTIC-ORACLE`
直接执行 13 组不变量；
`GOAL9-B3-EVERY-OVERLAY-SHA-HAS-A-BASELINE-DERIVED-SEMANTIC-ORACLE`
把 15 个 case 与基线来源、逐行顺序做一一映射，并共同断言非空 transcript 在 surface
之前、editor sentinel 被替换、footer 在 surface 之后。任一侧新增、删除或改名都会在
hash 比较之前失败。

`@path` 整屏与循环由
`GOAL9-B3-AT-PATH-AUTOCOMPLETE-HAS-AN-EXACT-FULL-SCREEN-AND-WRAPS` 锁定。
settings 的 25/27 能力分支、完整文案、搜索、窄屏和 submenu 由
`GOAL9-B3-SETTINGS-OVERLAY-IS-AN-EXACT-BASELINE-SCREEN`、
`GOAL9-B3-SETTINGS-CAPABILITY-AND-SUBMENUS-MATCH-BASELINE-CONTRACT` 与
`GOAL9-B3-EVERY-SETTINGS-SUBMENU-WRAPS-AT-BOTH-BOUNDARIES` 锁定。extension raw
surface 由 `GOAL9-B3-EXTENSION-SELECTOR-STYLES-COUNTDOWN-KEYS-AND-TOOL-TOGGLE-ARE-EXACT`
锁定，真实桥接由
`GOAL9-B3-EXTENSION-SELECT-RUNS-THROUGH-THE-LIVE-TUI-OVERLAY-BRIDGE` 与
`GOAL9-B3-EXTENSION-CONFIRM-RUNS-THROUGH-THE-LIVE-TUI-OVERLAY-BRIDGE` 锁定。
流式 Markdown 全链路由
`GOAL9-STREAMED-MARKDOWN-FENCE-IS-EXACT-THROUGH-THE-FULL-TUI-CHAIN` 锁定；
provider × API × thinking level × catalog hit/miss 矩阵由
`EVERY-BUILT-IN-PROVIDER-AND-API-HAS-THINKING-LEVEL-HIT-MISS-CONTRACT` 锁定。

此前门禁漏掉第四轮三类缺陷的原因是测试输入本身过弱：transport output audit
没有 provider/TLS 行，silent-SSE 只使用 cleartext HTTP 并只断言 stop reason；
Alt 键测试只喂了合成的 legacy `ESC p`，没有真实 CSI/Kitty/modifyOtherKeys 字节；
15 个 overlay 整屏 fixture 的 transcript 为空，所以“清空 transcript”和“正确保留
空 transcript”产生同一结果。新增测试分别锁定三个 TLS abort phase 与禁止片段、
真实终端 byte→action→queue 全链路、以及所有 overlay 的非空 transcript/editor-slot
替换。`assistant-message.ts:190-200` 还证明 abort fragment 自带唯一 `Spacer(1)`，故
外层不再为纯 error fragment 额外添加第二行。

## B3. 双终端 A/B 门禁

两端必须使用相同 terminal emulator、font、100×32 起始尺寸、`TERM`、
`COLORTERM`、`COLORFGBG` 和 `DEEPSEEK_API_KEY`。模型措辞无需相同，只比较展示与交互。

Terminal A，基线：

```bash
cd /tmp/cadr-parity-74caa2649
PI_CODING_AGENT_DIR=/tmp/cadr-goal9-ab-pi-agent \
PI_OFFLINE=1 \
./node_modules/.bin/tsx packages/coding-agent/src/cli.ts \
  --provider deepseek --model deepseek-chat \
  --offline --no-extensions --no-skills --no-prompt-templates \
  --no-themes --no-context-files --no-approve --alt
```

Terminal B，Cadr：

```bash
cd /root/projects/cadr
CADR_OFFLINE=1 \
./cadr --provider deepseek --model deepseek-chat \
  --offline --no-extensions --no-skills --no-prompt-templates \
  --no-themes --no-context-files --alt
```

| Scene | Exact operation | Compare | User confirmation |
|---|---|---|---|
| Cold start | 启动后 5 秒不输入。 | auto theme、startup spacing、editor border、footer、cursor、idle 稳定性。 | 已确认 |
| Streaming | `Think for several seconds, then give exactly 12 numbered one-line steps for checking a CLI release.` | thinking、spinner、流式 repaint、footer/status transition。 | 已确认 |
| Long output | `Output the integers 1 through 120, one per line, with no prose.`；滚到顶、一页、底。 | follow、scroll marker、clipping、footer anchor、回到 live tail。 | 已确认 |
| Tool call | `Use bash to run printf 'alpha\\nbeta\\n'; then read README.md and report only its first heading.`；完成后 Ctrl+O。 | 状态背景、padding、title/arg/output 色、preview budget、展开稳定。 | 已确认 |
| Diff | 在各自临时目录把 `alpha beta gamma` edit 为 `alpha delta gamma`。 | add/remove/context、word inverse、背景、折叠/展开。 | 已确认 |
| Overlays | 依次打开/取消 `/model`、`/settings`、`/resume`、`/fork`、`/tree`、`/login`、`/logout`、`/scoped-models`、`/import`、`/trust` 与 extension custom UI；逐一覆盖搜索、空态、首末循环和翻页。 | 每一行标题/提示/搜索/条目/值/计数/描述、border、spacer、selectedBg、scroll、focus、无 stale。 | 已确认 |
| Autocomplete | `/mo`→取消，`/model `→取消，`@REA`→移动→应用→undo。 | popup 位置、断点、selected row、description、cursor/IME、undo。 | 已确认 |
| CJK/emoji | 重复粘贴 `中文ABC🙂👨‍👩‍👧‍👦 é` 至换行，按 grapheme 移动删除并提交。 | cell、cursor、border、wrap、transcript alignment。 | 已确认 |
| Narrow resize | overlay 打开及 streaming 时依次 100×32→60×20→40×12→100×32。 | reflow、table/code wrap、footer truncation、overlay clipping、无 stale cell。 | 已确认 |
| Error | `/model __goal9_missing_model__`；再让 bash 执行 `sh -c 'echo expected-error >&2; exit 7'`。 | error color/spacing、tool error background、footer recovery、focus。 | 已确认 |
| Exit | `/quit`；重启后 Ctrl-C。 | cursor、bracketed paste/raw、alternate screen、无重复 final frame。 | 已确认 |

Part B disposition: `B3 双终端 A/B 已由用户确认；Part B 于 2026-08-01 验收通过并关闭`
