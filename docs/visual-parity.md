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
- editor 必须按终端可能交付的码点边界逐步输入并逐帧 render，包括空字符串、
  CJK、combining mark、emoji ZWJ 中间态；
- 命令、键位、overlay 和 footer 必须验证从 input decoder 到运行时状态再到最终
  virtual screen 的完整链路，不能只比提示文案或构造后的静态组件。

确定性门禁优先使用 faux provider + virtual terminal；只有真实进程、终端模式或
信号生命周期无法在进程内等价覆盖时才使用 PTY。每个现场缺陷先保留能复现原故障
的红测，再以同一断言转绿。B3 仍负责真实终端观感，但不再替 B2 发现可自动化的
崩溃、边界态和状态错误。

状态只允许：

- `一致`：进入 Part B 前已等价，或本轮复核未发现差异。
- `不一致（已改齐）`：本轮发现差异、实现修正并有永久门禁。
- `有意差异`：须有用户批准并登记 README；当前为零项。

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
| LY-01 | root 顺序为 startup/chat/pending/status/widgets/editor/footer；`tui.lisp:1740-1915`，`GOAL9-ROOT-LAYOUT-PUTS-EDITOR-BEFORE-TWO-LINE-FOOTER`。 | 不一致（已改齐） |
| LY-02 | user 全宽背景 X=1/Y=1；assistant 无背景且可见内容前一空行；thinking muted+italic；`tui.lisp:1497-1639`。 | 不一致（已改齐） |
| LY-03 | tool 前 spacer、X=1/Y=1、状态背景；`components.lisp:1554-1649`。 | 不一致（已改齐） |
| LY-04 | editor 只有上下 `─`，高度 `max(5,floor(rows*0.3))`，滚动信息在边框；`editor.lisp:1420-1662`。 | 不一致（已改齐） |
| LY-05 | select primary=32、gap=2、description min=10、默认 5 行、宽度 `<=40` 关闭 description；`components.lisp:1871-2164`。 | 不一致（已改齐） |
| LY-06 | overlay 默认 `min(80,width)`，selector 自身边框、spacer 和窄屏裁剪；`overlay.lisp:87-107`、`tui.lisp:1838-1915`。 | 一致 |
| MD-01 | H1/H2/H3+ 样式、H3+ 前缀和 block spacing 对齐。 | 不一致（已改齐） |
| MD-02 | code fence、两格缩进、在册语言语法着色、未知语言 code-block 色对齐；完整移植基线 `syntax-highlight.test.ts` 的 span/entity/继承、TS、diff、regexp、decorator、HTML 门禁，并覆盖 HTML/diff/JSON/Bash/SQL 可见 token 边界与 Python/Bash URL 反例。 | 不一致（已改齐） |
| MD-03 | quote `│ `、italic、HR 80-cell cap 对齐。 | 不一致（已改齐） |
| MD-04 | ordered/unordered/task marker、四格嵌套和 continuation 对齐。 | 不一致（已改齐） |
| MD-05 | link underline/color、OSC 8 与 fallback URL 规则对齐。 | 不一致（已改齐） |
| MD-06 | 表格宽度分配、wrap、粗体 header、完整 box、窄屏 raw fallback 对齐。 | 不一致（已改齐） |
| MD-07 | inline style 局部恢复、streaming partial fence 防闪烁对齐。 | 不一致（已改齐） |
| TL-01 | pending/success/error 背景、title/argument/output/error/warning 语义色对齐；真实 bash 非零退出必须从 tool result 传播为 `× $` error state，文案为 `Command exited...`。 | 不一致（已改齐） |
| TL-02 | collapsed preview：bash 5、read/write 10、grep 15、find/ls 20；expanded 显示完整保留结果。 | 不一致（已改齐） |
| TL-03 | real edit 结果进入 diff renderer；context/add/remove 色、单行 word inverse、tab→3 spaces 和超长行上限对齐；bash running/settled 显示 `Elapsed`/`Took`。 | 不一致（已改齐） |
| TL-04 | 默认 active tools、顺序、description、prompt snippet/guidelines 对齐基线 `read,bash,edit,write`；`grep/find/ls` 仅显式启用，避免模型因提示偏离改用 bash echo/sed。 | 不一致（已改齐） |
| FT-01 | cwd/branch/session；input/output/cache read/write/hit/cost/context；provider/model/thinking；extension status 三行布局对齐。 | 不一致（已改齐） |
| FT-02 | context `>70%` warning、`>90%` error 对齐。 | 不一致（已改齐） |
| FT-03 | working/retry/compaction spinner、语义色与 status 区域对齐。 | 不一致（已改齐） |
| FT-04 | `/login`、`/model`、thinking、subscription、auto-compaction 均从 live agent state 刷新；editor thinking/bash border 同步。 | 不一致（已改齐） |
| SL-01 | generic selected `→ ` + accent、muted description、scroll/no-match 主题对齐。 | 不一致（已改齐） |
| SL-02 | session selected row 使用全宽 `selectedBg`；tree 只给固定 gutter/body segment 着色，不错误 padding 到整行。 | 不一致（已改齐） |
| SL-03 | model 最多 10 行、accent selected、muted provider、green `✓`、border/spacer 对齐。 | 不一致（已改齐） |
| SL-04 | autocomplete primary 12..32、默认 5、配置 3..20、仅 `@` 20 ms debounce、popup 在下边框后。 | 不一致（已改齐） |
| AN-01 | spinner `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`，80 ms；loader 前一空行。 | 不一致（已改齐） |
| AN-02 | render 16 ms throttle；terminal progress 1 s keepalive；`showTerminalProgress` 每事件读取且关闭立即 clear。 | 不一致（已改齐） |
| AN-03 | IME zero-width marker、inverse fake cursor、hardware cursor 放置/隐藏/恢复对齐。 | 不一致（已改齐） |
| AN-04 | resize invalidation、alternate screen、scroll/follow、mouse、autowrap 与退出恢复已有等价实现。 | 一致 |

Markdown 门禁：

- `test/cadr-tui/components-test.lisp:130-767`
- `test/cadr-tui/component-parity-test.lisp:159-331`
- `src/cadr-cli/interactive-services.lisp:2935-3950`
- `test/cadr-cli/part-b-interactive-test.lisp:1352-1485,1821-1881`
- `test/cadr-cli/tui-test.lisp:2693-2725`

工具、footer、选择器与动效门禁：

- `test/cadr-tui/components-test.lisp:229-568`
- `test/cadr-tui/editor-parity-test.lisp:224-521`
- `test/cadr-tui/terminal-colors-test.lisp:108-251`
- `test/cadr-cli/tui-test.lisp:223-1145,1698-2240`
- `test/cadr-cli/part-b-interactive-test.lisp:1671-2180`

机械账本结论：33 个编号项中 `一致` 2 项，`不一致（已改齐）` 31 项，
`有意差异` 0 项，`pending` 0 项。

### B2 运行时补充门禁

2026-07-31 首轮 B3 真实双终端 A/B 退回后，新增以下原机械账本没有覆盖的
运行时矩阵；测试名和红→绿证据在 `docs/acceptance/goal-v9-part-b.md` 逐项列出。

| 状态面 | 必测转换 |
|---|---|
| selector | empty/filter-empty/first/last/page/wrap/select |
| editor | empty→incremental Unicode→ZWJ intermediate→complete grapheme |
| assistant stream | start→每个 delta→final multiline document |
| tool | start/running/partial→success 或 error→collapsed/expanded |
| command UI | command→refresh→overlay→navigation→cancel/select |
| application keys | raw/Kitty input→configured action→busy/idle behavior |

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
| Cold start | 启动后 5 秒不输入。 | auto theme、startup spacing、editor border、footer、cursor、idle 稳定性。 |  |
| Streaming | `Think for several seconds, then give exactly 12 numbered one-line steps for checking a CLI release.` | thinking、spinner、流式 repaint、footer/status transition。 |  |
| Long output | `Output the integers 1 through 120, one per line, with no prose.`；滚到顶、一页、底。 | follow、scroll marker、clipping、footer anchor、回到 live tail。 |  |
| Tool call | `Use bash to run printf 'alpha\\nbeta\\n'; then read README.md and report only its first heading.`；完成后 Ctrl+O。 | 状态背景、padding、title/arg/output 色、preview budget、展开稳定。 |  |
| Diff | 在各自临时目录把 `alpha beta gamma` edit 为 `alpha delta gamma`。 | add/remove/context、word inverse、背景、折叠/展开。 |  |
| Overlays | 依次打开/取消 `/model`、`/settings`、`/resume`、`/fork`、`/tree`、`/login`，各移动和翻页一次。 | border、spacer、selectedBg、provider/checkmark、scroll、focus、无 stale。 |  |
| Autocomplete | `/mo`→取消，`/model `→取消，`@REA`→移动→应用→undo。 | popup 位置、断点、selected row、description、cursor/IME、undo。 |  |
| CJK/emoji | 重复粘贴 `中文ABC🙂👨‍👩‍👧‍👦 é` 至换行，按 grapheme 移动删除并提交。 | cell、cursor、border、wrap、transcript alignment。 |  |
| Narrow resize | overlay 打开及 streaming 时依次 100×32→60×20→40×12→100×32。 | reflow、table/code wrap、footer truncation、overlay clipping、无 stale cell。 |  |
| Error | `/model __goal9_missing_model__`；再让 bash 执行 `sh -c 'echo expected-error >&2; exit 7'`。 | error color/spacing、tool error background、footer recovery、focus。 |  |
| Exit | `/quit`；重启后 Ctrl-C。 | cursor、bracketed paste/raw、alternate screen、无重复 final frame。 |  |

Part B disposition: `首轮 B3 已退回；运行时补正完成后等待用户重新逐项确认`
