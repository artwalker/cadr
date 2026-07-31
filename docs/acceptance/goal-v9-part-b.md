# Goal 9 Part B 阶段报告

> 状态：第三轮机械门禁、全量、grep、PTY 与隔离构建已绿；提交证据见第 7 节。
> 等待用户重新执行 B3 双终端 A/B，Part C 尚未开始。

## 1. 基线与机械账本

- 规范基线：`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`。
- 基线 checkout：`/tmp/cadr-parity-74caa2649`，`git rev-parse HEAD` 与规范
  hash 逐字节一致。
- `npm run build:offline` 成功；基线 source runner `--version` 为 `0.83.0`。
- 基线 TUI 已在 100×32 `tmux` PTY 中冷启动并以 `/quit` 正常退出。
- [`visual-parity.md`](../visual-parity.md) 第三轮共 35 个机械编号项：
  `一致` 2 项，`不一致（已改齐）` 31 项，`有意差异` 2 项；`pending` 0 项。
- 两项有意差异均为用户裁决：所有选择器双向循环；bash 标题永不显示 timeout。
  README 只登记这两项视觉/交互差异。

## 2. 已对齐的行为面

- 完整 dark/light semantic palette、truecolor/256-color 转换以及 `39`/`49`
  局部恢复。
- fixed、未配置 detect-once、auto DSR→OSC 11、动态通知和自定义主题 schema
  热重载。
- editor border、bash/thinking live border、fake cursor、IME marker、resize 与
  terminal lifecycle。
- Markdown block/inline/table/link/code fence、基线语法高亮可见语义、状态恢复。
- tool title/argument/output、真实 edit diff、折叠预算和 semantic diff。
- footer 全字段、extension status、context threshold、JS rounding、live
  auto-compaction。
- spinner、retry/compaction、16 ms render throttle、terminal-progress keepalive、
  OSC 133 zones。
- session/tree/model/settings/trust/scoped-model selector、overlay、autocomplete
  与窄屏裁剪；settings 与基线能力门控一致：supports-images=nil 时 25 项，true
  时增加 Show images/Image width 至 27 项。门禁为
  `GOAL9-B3-SETTINGS-OVERLAY-IS-AN-EXACT-BASELINE-SCREEN`、
  `GOAL9-B3-SETTINGS-CAPABILITY-AND-SUBMENUS-MATCH-BASELINE-CONTRACT` 与
  `GOAL9-B3-EVERY-SETTINGS-SUBMENU-WRAPS-AT-BOTH-BOUNDARIES`。
- extension select 已经真实 worker→live TUI overlay bridge→键盘选择→返回值回归，
  不再仅证明孤立 framed selector 会 render；门禁为
  `GOAL9-B3-EXTENSION-SELECT-RUNS-THROUGH-THE-LIVE-TUI-OVERLAY-BRIDGE` 与
  `GOAL9-B3-EXTENSION-CONFIRM-RUNS-THROUGH-THE-LIVE-TUI-OVERLAY-BRIDGE`。

没有新增第三方依赖；语法高亮为纯 Lisp 实现。

## 3. 首轮 B3 退回与运行时补正

原 B2 只充分覆盖了静态常量、构造后的组件和最终字符串，没有把真实事件序列
中的空边界、逐帧流式状态和错误转换纳入视觉合约。用户在真实双终端 A/B 中因此
发现十项逃逸。`docs/visual-parity.md` 已把 B2 方法扩充为 faux provider + virtual
terminal/PTY 的运行时状态门禁。

| 项 | 回归门禁 | 原故障与修正 | 原 4759 条为何未捕获 |
|---|---|---|---|
| P0-1 `/fork` 空候选崩溃 | `GOAL9-SELECT-LIST-EMPTY-AND-FIRST-ITEM-NAVIGATION-NEVER-WRITES-NEGATIVE-INDEX` | 旧导航先把 unsigned `selected` 写成 `-1` 再 clamp；改为在写槽前原子计算合法循环索引，空列表固定为 0。 | 旧 selector 测试只使用非空列表并从中间/向下导航，没有覆盖首项向上、过滤后零候选及 Enter/render。 |
| P0-2 CJK/emoji 编辑崩溃 | `EDITOR-INCREMENTAL-CJK-AND-EMOJI-INPUT-NEVER-RENDERS-EMPTY-GRAPHEME`、`GRAPHEME-CLUSTERS-HANDLE-EMPTY-AND-DANGLING-JOINER-BOUNDARIES` | Common Lisp 中空字符串为真，autocomplete 对 `""` 执行 `(char value 0)`；同时悬空 ZWJ 吞掉 cursor placeholder。现先验长度并保持逐码点 grapheme 边界。 | 旧测试一次插入完整 grapheme，且未挂 autocomplete provider；没有逐码点渲染 ZWJ 中间态或 Unicode+尾随空格产生的空 path prefix。 |
| P0-3 `session> <char>` | `GOAL9-B-TUI-BASH-STREAM-DOES-NOT-CREATE-SESSION-NOTICES` | TUI 把 bash live stream 接到 notice stream，而 bash 每字符 flush，遂生成一行一个 notice；TUI 不再把该流接入 notice 通道。 | notice、bash capture 和最终 tool result 分别测试，从未通过真实 mode wiring 驱动每字符 flush 并检查 virtual screen。 |
| P1-4 exit 7 显示成功 | `GOAL9-B-BASH-NONZERO-EXIT-IS-A-TOOL-ERROR`、`GOAL9-B-NONZERO-BASH-TOOL-RENDERS-ERROR-STATE` | 非零退出从普通 result 改为 error tool result；运行时 block 为 `:error`、红色背景。第二轮进一步移除了基线没有的状态 glyph。 | 组件测试手工构造 `:error`，bash 测试只找 exit footer；没有跑真实 agent tool loop 验证 result `is-error` 到 TUI 状态。 |
| P1-5 selector 不循环 | `GOAL9-SELECT-LIST-NAVIGATION-WRAPS-AT-BOTH-BOUNDARIES` | up/down/page 均以候选数取模，首末双向循环；零候选仍不移动。 | 旧测试把 clamp 当正确行为，没有以基线首末循环作为运行时契约。 |
| P1-6 长输出与工具选择 | `GOAL9-STREAMED-MULTILINE-ASSISTANT-OUTPUT-STAYS-LINE-ORIENTED-EVERY-FRAME`、`GOAL9-DEFAULT-TOOL-AND-PROMPT-CONTRACT-MATCHES-AUDIT-BASELINE` | 120 行逐帧证明显式换行在 event→renderer→virtual terminal 链路不丢失；现场连排不是 Markdown 换行实现。实际偏离在更上游：Cadr 错把 7 个工具默认启用，且四工具 descriptions/snippets/guidelines 与基线不同；现默认恢复 `read,bash,edit,write` 并逐字对齐相应提示，解释并修正 bash echo/sed 偏好。 | 旧测试反而把 7 工具固化为“基线”，system prompt 仅宽松查 substring，stream 测试只有一个静态 delta，无多行逐帧 renderer/viewport。 |
| P2-7 键位提示/行为 | `GOAL9-P2-BASELINE-KEY-HINTS-AND-DECODER-ACTIONS-AGREE`、`GOAL9-P2-CTRL-C-CLEARS-BUSY-DRAFT-AND-ESCAPE-INTERRUPTS` | 默认改为 Escape interrupt、Ctrl-C clear/双击 exit、Ctrl-D empty exit；raw 与 Kitty 输入均走可配置 app actions。 | 旧测试只比静态提示并把错误文本固化，没有验证 decoder→busy/idle action、双击时序和 virtual terminal。 |
| P2-8 `/model` | `GOAL9-A2-OVERLAY-SELECTORS-FOCUS-CJK-AND-RESIZE-SNAPSHOTS` | 移除基线不存在的 `Select Model`；模型目录刷新成功后在 selector 中显示 `Model catalogs refreshed.`。 | 旧 snapshot 明确期待错误标题，也没有覆盖 refresh 完成后的第二帧。 |
| P2-9 exit 文案/耗时 | `GOAL9-B-BASH-TOOL-RUNTIME-RENDERS-ELAPSED-AND-TOOK-LINES`、`GOAL9-B-TOOL-EVENTS-RECORD-RUNTIME-FOR-THE-LIVE-TUI` | tool error 改为 `Command exited with code 7`；bash start/end 使用同一 monotonic clock，running 显示 `Elapsed`，完成/失败显示 `Took 0.0s`。 | 旧测试固化了 `Process exited...`，tool block 没有时间状态，也没有 start→end 事件时钟测试。 |
| P2-10 tree/history/fork layout | `GOAL9-SESSION-SELECTOR-LAYOUT-MATCHES-BASELINE-PANEL-AND-LIST`、`GOAL9-SESSION-SELECTOR-RENAME-LAYOUT-MATCHES-BASELINE-SPACERS`、`GOAL9-TREE-SELECTOR-LAYOUT-MATCHES-BASELINE-TREE-VIEWPORT-AND-LABEL-SHELL`、`GOAL9-FORK-HISTORY-OVERLAY-MATCHES-BASELINE-MESSAGE-LAYOUT` | 对齐 header 左右栏、两行 hints、query/spacers、10 行居中 viewport、树枝/折叠符、路径/cwd/count/age、scroll、rename/label shell 与 fork message layout。 | 旧测试只验证过滤/选择业务语义和少数 selected background 常量，没有完整 panel/viewport 的逐行快照。 |

红→绿记录：

- P0-1 红相为原现场同一 `UNSIGNED-BYTE datum -1`；空/边界/循环门禁绿
  `33/33`。
- P0-2 红相 `14 checks / 10 pass / 4 fail`，包含原始 empty-array index
  condition 与三个 ZWJ 中间帧错误；对应门禁及 Unicode 相关回归全绿。
- P0-3 红相 `2 checks / 1 pass / 1 fail`，notice 收到逐字符
  `alphadeltagamma`；绿相 notice 与 virtual screen 均无该内容。
- P1-4 红相同时出现普通 result、`:complete` 和 `Process exited...`；底层与
  faux-agent TUI 门禁现全绿。
- P1-6 旧工具/prompt 精确契约红 `0/1`；修正后工具/prompt 及 120 帧纯整数
  输出合计 `525/525`。
- P2-7/8 红相分别固定了错误 action/hint、`Select Model` 且缺失 refresh 完成帧；
  修正后 key/decoder `10/10`、virtual terminal `3/3`、model overlay `28/28`。
- P2-9 红相因 tool block 没有 start/end 状态而在新增 accessor/keyword 处直接失败；
  实现后 component 与真实 event 路径均绿。
- P2-10 首轮运行时快照 `103 checks / 89 pass / 14 fail`；按基线修正实现，
  并移除测试数据中的非基线假设后，五个布局门禁 `100/100`。

保留日志：`/tmp/cadr-goal9-b-p0-stream-{red,green}.log`、
`/tmp/cadr-goal9-b-p1-tool-error-{red,green}.log`、
`/tmp/cadr-goal9-b-p2-timing-{red,green}.log`。

## 3.1 第二轮 B3 退回与内容等价补正

第二轮暴露的根因不是“又漏了几个常量”，而是原 5399 条仍偏向事件类型、结构和
局部 substring，没有证明内容逐字符不变、provider 能力矩阵完整以及整屏文案逐字
等价。以下门禁均先在旧实现上复现现场红相，再以同一断言转绿。

| 项 | 当前源码位置 | 回归门禁 | 原故障与修正 | 原 5399 条为何未捕获 |
|---|---|---|---|---|
| P0-1 流式数字前空格被吞 | `src/cadr-ai/providers/openai-completions.lisp:526-548` | `test/cadr-ai/openai-completions-test.lisp:135` `OPENAI-COMPLETIONS-STREAM-TEXT-IS-CHARACTER-EXACT-FOR-ALL-DELTA-BOUNDARIES`；`:182` `OPENAI-COMPLETIONS-NONSTREAM-TEXT-IS-CHARACTER-EXACT` | `append-chat-text-delta` 改为只拒绝长度为零的字符串；遍历全部单切点及空白、数字边界。 | 旧 fixture 只断言事件结构，未拼回并逐字符比原文。 |
| P0-2 Responses reasoning summary 缺失 | `src/cadr-ai/providers/openai.lisp:423-450,467-529`；`src/cadr-cli/tui.lisp:1689-1749` | `test/cadr-ai/provider-streams-test.lisp:149` `OPENAI-RESPONSES-REASONING-SUMMARY-PARTS-EMIT-EXACT-THINKING-EVENTS`；`test/cadr-cli/tui-test.lisp:2334` `GOAL9-USER-AND-ASSISTANT-MESSAGE-SHELLS-MATCH-BASELINE` | 补 summary part/delta、分段、最终回填与 thinking start/delta/end；TUI 复用 muted italic renderer。 | 旧门禁仅覆盖 DeepSeek `reasoning_content` 和通用 renderer，没有 Responses fixture。 |
| P0-3 未知模型 thinking 降级 | `src/cadr-ai/registry.lisp:384-474`；`src/cadr-cli/config.lisp:156-234` | `test/cadr-cli/config-auth-test.lisp:44` `UNKNOWN-DEEPSEEK-MODEL-INHERITS-FALLBACK-CAPABILITIES-FOR-EVERY-THINKING-LEVEL` | catalog miss 继承 provider 默认模型协议/能力/thinking map但保留用户 model ID，覆盖全部 thinking level。 | 旧测试仅有 catalog hit，没有未知 model × level 的 payload/event 矩阵。 |
| P0-4 read `offset=0` | `src/cadr-cli/tools/read.lisp:3-42` | `test/cadr-cli/file-tools-test.lisp:38` `READ-OFFSET-MATCHES-BASELINE-ZERO-NEGATIVE-AND-BEYOND-END-SEMANTICS` | 0 从头、负值 clamp；超界文案逐字对齐。 | 旧测试仅覆盖正 offset/limit，错误只做类型级断言。 |
| P1-5a 用户块间距 | `src/cadr-cli/tui.lisp:1758-1793,1872-1888` | `test/cadr-cli/tui-test.lisp:1112` `GOAL9-B3-USER-BLOCK-SPACING-AND-WRAPPING-MATCH-BASELINE` | assistant→user transcript 增加基线 spacer。 | 旧测试孤立渲染 user component，没有相邻 transcript。 |
| P1-5b 用户块换行 | `src/cadr-cli/tui.lisp:1758-1793` | `test/cadr-cli/tui-test.lisp:1112` `GOAL9-B3-USER-BLOCK-SPACING-AND-WRAPPING-MATCH-BASELINE`，精确期望见 `:1129-1137` | 固定宽度续行保留基线行首 padding。 | 旧测试只搜索内容 substring，没有逐行快照。 |
| P1-7 bash 标题 timeout | `src/cadr-cli/tui.lisp:1124-1202` | `test/cadr-cli/tui-test.lisp:1223` `GOAL9-B3-EXPLICIT-BASH-TIMEOUT-NEVER-APPEARS-IN-TITLE`；`:1139` `GOAL9-B3-TOOL-TITLE-COPY-HAS-NO-STATUS-GLYPH-OR-DEFAULT-TIMEOUT` | 用户裁决后，无论 default/explicit timeout 均只显示 `$ command`。这与基线 `bash.ts:226-231` 有意不同。 | 上轮测试只证明“无默认 timeout”，并把显式 timeout 后缀当基线正确行为，因而无法发现用户实际要求尚未满足。 |
| P1-8 工具标题 glyph | `src/cadr-tui/components.lisp:1187-1197,1567-1599` | `test/cadr-cli/tui-test.lisp:652` `GOAL9-B-NONZERO-BASH-TOOL-RENDERS-ERROR-STATE`；`:1139` `GOAL9-B3-TOOL-TITLE-COPY-HAS-NO-STATUS-GLYPH-OR-DEFAULT-TIMEOUT` | running/success/error 标题移除 `…/✓/×`，状态只由背景和语义色表达。 | 旧 snapshot 自身固化新增 glyph，未逐字对拍完整标题。 |
| P1-9 `/login` 无参数 | `src/cadr-cli/interactive-services.lisp:7159-7208`；`src/cadr-cli/tui.lisp:3802-3807,3962-3963` | `test/cadr-cli/tui-test.lisp:1338` `GOAL9-B3-LOGIN-WITHOUT-ARGUMENTS-RENDERS-AUTH-METHOD-SELECTOR` | 新增 account/API key 两级选择及 masked key 输入。 | 旧测试只覆盖显式 provider 与孤立 provider selector，未走无参命令分派。 |
| P2-10 `/model` 文案 | `src/cadr-cli/interactive-services.lisp:8012-8141` | `test/cadr-cli/goal9-b3-p2-regressions-test.lisp:7` `GOAL9-B3-MODEL-OVERLAY-COPY-MATCHES-UNSCOPED-BASELINE`；`test/cadr-cli/goal9-b3-overlay-contract-test.lisp:144` `GOAL9-B3-MODEL-OVERLAYS-HAVE-COMPLETE-BASELINE-LINE-CONTRACTS` | 未 scoped 状态补 `/login` 文案并使用 `> `；scoped 状态和 refresh status 独立快照。 | 旧测试只搜 warning/model 和样式 token，没有整屏逐行快照。 |
| P2-11 `/tree` 提示 | `src/cadr-cli/interactive-services.lisp:5990-6035` | `test/cadr-cli/goal9-b3-p2-regressions-test.lisp:39` `GOAL9-B3-TREE-HELP-COPY-PRESERVES-ARROW-GLYPHS-AND-FILTER-ABBREVIATIONS` | 恢复箭头字形、branch chord 与 filters 缩写。 | 旧测试只验证 action，不断言最终两行提示。 |
| P2-12 `/tree` 工具条目 | `src/cadr-cli/main.lisp:557-695`；`src/cadr-cli/interactive-services.lisp:5458-5605` | `test/cadr-cli/goal9-b3-p2-regressions-test.lisp:70` `GOAL9-B3-TREE-TOOL-RESULTS-RENDER-CALL-LABELS-NOT-RAW-OUTPUT` | call ID 关联 result，渲染 `[tool: args]` 标签而非 raw output。 | 旧 fixture 只有孤立 result，没有真实 call/result 关联。 |
| P2-13 冷启动下沉 | `src/cadr-cli/tui.lisp:1997-2215` | `test/cadr-cli/goal9-b3-p2-regressions-test.lisp:129` `GOAL9-B3-COLD-STARTUP-CONTENT-IS-TOP-ALIGNED` | 冷启动把剩余 padding 放到 startup 后，editor/footer 仍锚底。 | 旧 root test 绕过 viewport padding，只验组件顺序。 |

红相包括原始空格折叠、Responses 零 thinking、未知模型零 thinking、
`offset must be at least 1`、旧 overlay/tool/tree/cold-start 完整快照差异。此前记录的
5614 条是第二轮历史结果，不能作为第三轮验收证据。read 标题的 `:起-止` 后缀未修改，
因为它是基线 `formatReadLineRange` 的正确行为。

## 3.2 第三轮：证据真实性补正

上轮有三项“已对齐”宣告不成立：timeout 只验证了未显式传参路径，却把用户要求覆盖的
explicit timeout 排除在结论外；write 只验证 executor 确实返回 byte receipt，没有验证
TUI 在 start/end 两帧展示 call content 还是 receipt；`/model` 则把 scoped 分支仍保留的
`tab scope (all/scoped)` 提示误报为已删除。三处都把局部实现事实冒充为完整用户路径证据。

| 面 | 当前源码与门禁 | 本轮事实 | 旧检查为何漏过 |
|---|---|---|---|
| bash timeout 标题 | `src/cadr-cli/tui.lisp:1124-1202`；`test/cadr-cli/tui-test.lisp:1223` `GOAL9-B3-EXPLICIT-BASH-TIMEOUT-NEVER-APPEARS-IN-TITLE` | default 与 explicit timeout 均不得出现在标题。该用户裁决与审计基线显式后缀冲突，按有意差异登记。 | 旧门禁只证明“默认 timeout 不应凭空出现”，并主动保留 explicit 后缀，测试范围与宣告范围不一致。 |
| write running/success 文案 | `src/cadr-cli/tui.lisp:1221-1249,1261-1501`；`test/cadr-cli/tui-test.lisp:1274` `GOAL9-B3-WRITE-TOOL-DISPLAYS-REQUEST-CONTENT-NOT-BYTE-RECEIPT` | running 与 success 均展示请求 content 的基线 preview；`Wrote N UTF-8 bytes...` 仍可作为模型侧 executor result，但不得成为 TUI 用户文案。 | 旧测试只测 executor receipt 和 tool status，未对 event→block 的完整 output 行做 start/end 快照。 |
| `/model` `tab scope` 提示 | `src/cadr-cli/interactive-services.lisp:8012`；`test/cadr-cli/goal9-b3-p2-regressions-test.lisp:7` `GOAL9-B3-MODEL-OVERLAY-COPY-MATCHES-UNSCOPED-BASELINE`；`test/cadr-cli/goal9-b3-overlay-contract-test.lisp:144` `GOAL9-B3-MODEL-OVERLAYS-HAVE-COMPLETE-BASELINE-LINE-CONTRACTS` | unscoped/scoped 两条完整文案路径均不再出现 `tab scope (all/scoped)`；scoped 状态只保留 `Scope: all | scoped` 状态标题。 | 旧门禁只覆盖 unscoped 分支，并把 scoped 分支残留提示当作允许差异；宣告范围大于真实验证范围。 |
| read collapsed preview | `src/cadr-tui/components.lisp:1213-1222,1514-1565`；`test/cadr-tui/components-test.lisp:423` `GOAL9-TOOL-COLLAPSED-PREVIEWS-MATCH-BASELINE-BUDGETS` | 成功 read 折叠态不显示结果；展开显示完整结果；error 始终可见。 | 旧共享 budget 错把 read 与 write 合并为 10 行，并只断言裁剪数量，未对照 read 专用 result renderer。 |
| Markdown streaming fence | `src/cadr-tui/components.lisp:796-906`；`test/cadr-tui/components-test.lisp:764` `GOAL9-MARKDOWN-STREAMING-FENCES-MATCH-BASELINE-EXACTLY`；`test/cadr-cli/goal9-b-runtime-parity-test.lisp:174` `GOAL9-STREAMED-MARKDOWN-FENCE-IS-EXACT-THROUGH-THE-FULL-TUI-CHAIN` | empty/partial/closed backtick 与 tilde fence 的每一帧逐行等价，含 fence 后首个空 code line；另从 delta 经 TUI state、Markdown renderer 到 virtual terminal 锁定完整链路。 | 旧测试偏重完成态和 token 样式，没有逐帧固定完整行数组，也没有穿过完整 TUI 链。 |
| 14 个 overlay 整屏合约 | `test/cadr-cli/goal9-b3-overlay-contract-test.lisp:122` `GOAL9-B3-EVERY-OVERLAY-HAS-AN-EXACT-FULL-VIRTUAL-TERMINAL-SNAPSHOT` | model、model-scoped、settings、resume、fork、tree、scoped-models、trust、login-method、login-provider、api-key、import、extension-select、extension-custom 均锁定完整 virtual-screen SHA-256。 | 原门禁分散在 substring、样式 token 和业务 action 测试，只抽查六个 overlay，未证明每个 surface 的整屏输出。 |
| settings 能力门控 | `test/cadr-cli/goal9-b3-p2-regressions-test.lisp:169` `GOAL9-B3-SETTINGS-OVERLAY-IS-AN-EXACT-BASELINE-SCREEN`；`:347` `GOAL9-B3-SETTINGS-CAPABILITY-AND-SUBMENUS-MATCH-BASELINE-CONTRACT`；`:497` `GOAL9-B3-EVERY-SETTINGS-SUBMENU-WRAPS-AT-BOTH-BOUNDARIES` | 与基线相同：supports-images=nil 时 25 项；true 时按能力增加 Show images/Image width，合计 27 项；submenu 与边界循环另行锁定。 | 旧报告把 nil 分支的 25 项误当作固定用户裁决，没有覆盖 capability=true 分支。 |
| `@path` autocomplete | `test/cadr-cli/goal9-b3-overlay-contract-test.lisp:837` `GOAL9-B3-AT-PATH-AUTOCOMPLETE-HAS-AN-EXACT-FULL-SCREEN-AND-WRAPS` | 40×8 完整 virtual screen、换行与上下双向循环均锁定。 | 旧检查只断言匹配项或局部 popup，没有完整屏幕与 wrap 行为。 |
| extension raw/live | `test/cadr-cli/goal9-b3-overlay-contract-test.lisp:589` `GOAL9-B3-EXTENSION-SELECTOR-STYLES-COUNTDOWN-KEYS-AND-TOOL-TOGGLE-ARE-EXACT`；`:646` `GOAL9-B3-EXTENSION-SELECT-RUNS-THROUGH-THE-LIVE-TUI-OVERLAY-BRIDGE`；`:694` `GOAL9-B3-EXTENSION-CONFIRM-RUNS-THROUGH-THE-LIVE-TUI-OVERLAY-BRIDGE` | raw input、倒计时、按键、tool toggle，以及真实 worker→live TUI overlay bridge→键盘→返回值均有门禁。 | 旧检查只证明孤立 framed selector 可 render，未证明真实 bridge 与返回值。 |
| provider thinking 全矩阵 | `test/cadr-ai/provider-streams-test.lisp:487` `EVERY-BUILT-IN-PROVIDER-AND-API-HAS-THINKING-LEVEL-HIT-MISS-CONTRACT` | 每个 built-in provider/API × 每个 thinking level × catalog hit/miss 均断言 payload 与 thinking 事件行为。 | 旧检查以单一 provider 的事件结构代替完整能力矩阵。 |

`/sessions`、`/switch`、`/branch`、`/install` 已从 Cadr 内置 slash dispatch、TUI
overlay 与 autocomplete 全部删除，与基线 surface 一致；它们不再是 `/resume` alias，
也不存在保留给用户调用的隐藏命令 backend。`/compact`、`/export`、`/reload` 按基线
仍为直接动作，不打开 overlay。删除门禁为
`GOAL9-B3-NONBASELINE-COMMAND-NAMES-DO-NOT-OPEN-TUI-OVERLAYS`，autocomplete
集合另由 `GOAL9-B3-BUILTIN-AUTOCOMPLETE-COMMAND-CONTRACT-MATCHES-BASELINE` 锁定。

第三轮 B2 增加三条硬门禁：所有展示结论必须覆盖真实 event→state→frame；renderer
专用语义不得由共享预算或相邻工具代测；overlay 必须按 surface 全枚举，完整行快照、
样式、空态、viewport 和首末循环缺一不可。完整对照表见
[`visual-parity.md`](../visual-parity.md#b2-overlay-完整逐行合约)。

## 4. 色彩字节证据

同一 dark palette 输入的 capture：

```text
truecolor accent-fg = ESC[38;2;138;190;183m
truecolor user-bg   = ESC[48;2;52;53;65m
256-color accent-fg = ESC[38;5;109m
256-color user-bg   = ESC[48;5;59m
foreground reset    = ESC[39m
background reset    = ESC[49m
```

原始 capture：`/tmp/cadr-goal9-color-capture.txt`。

## 5. 第三轮最终机械证据

| 证据 | 命令/范围 | checks | pass | skip | fail | 输出记录 |
|---|---|---:|---:|---:|---:|---|
| 隔离确定性全量 | 临时空 `HOME`，显式 unset 四类 live credential，`./scripts/test-cl.sh` | 6854 | 6846 | 8 | 0 | `/tmp/cadr-goal9-isolated-rerun.log` |
| 当前用户状态全量 | `./scripts/test-cl.sh` | 6877 | 6876 | 1 | 0 | `/tmp/cadr-goal9-current.log` |
| 本机可用 live 门禁 | 当前与隔离 totals 的增量；DeepSeek 与 Codex OAuth 均真实执行 | 23 | 23 | 0 | 0 | `/tmp/cadr-goal9-current.log` |
| PTY lifecycle | `./scripts/goal9-a2-pty.sh` | 3 | 3 | 0 | 0 | normal、ctrl-c、suspend-resume 均 PASS |

当前用户全量中的唯一 skip 为没有 `ANTHROPIC_API_KEY` 的
`LIVE-ANTHROPIC-STREAM-PRESERVES-TWO-TURN-CONTEXT`。DeepSeek streaming/print、
Codex OAuth CLI、DeepSeek/Codex eval 及两个 DeepSeek 进程级 eval 均真实执行。

证据真实性补充：第一次保存隔离重跑时，既有
`SHUTDOWN-DURING-PREFLIGHT-PREVENTS-PROVIDER-START` 时序测试偶发 2 个断言失败；
本轮没有改动 `cadr-agent`，按“顺手发现只记录不修”处理。相同隔离命令立即重跑
6854 checks 全绿，当前用户状态 6877 checks 亦全绿；失败日志保留为
`/tmp/cadr-goal9-isolated.log`。

残留 grep 命令与原始输出：

```text
$ rg -n 'format nil " \(timeout ~As\)"|timeout ~As' src/cadr-cli/tui.lisp
(no output; exit 1)

$ rg -n 'Wrote ~D UTF-8 bytes|Wrote [0-9]+ UTF-8 bytes' src/cadr-cli/tui.lisp
(no output; exit 1)

$ rg -n 'tab scope \(all/scoped\)' src/cadr-cli/tui.lisp test/cadr-cli
(no output; exit 1)

$ rg -n 'up/down navigate · enter change · escape close' src
(no output; exit 1)

$ rg -n 'timeout 10s|Wrote 16 UTF-8 bytes' test/cadr-cli/tui-test.lisp
1247:      (is (null (search " (timeout 10s)" rendered)))
1290:              :text "Wrote 16 UTF-8 bytes to /tmp/notes.txt"))

$ rg -n 'tool-preview-budget|\(string-equal name "read"\)' src/cadr-tui/components.lisp
1213:(defun tool-preview-budget (name)
1216:    ((string-equal name "read") 0)
1532:                (tool-preview-budget

$ rg -n 'Wrote ~D UTF-8 bytes' src/cadr-cli/tools/write.lisp
40:          (format nil "Wrote ~D UTF-8 bytes to ~A"
```

最后一项是模型可见 executor result，按基线工具协议保留；前述 TUI-scoped grep
证明它不再泄漏为用户展示文案。

## 6. 隔离构建产物

最终隔离构建须在本轮实现稳定后重跑，并记录 SBCL compression 分支、退出码、
产物 mode/size、`--version` 与 SHA-256：

```text
compression branch: SBCL lacks sb-core-compression; both builds used the documented uncompressed fallback
build exit: build.sh=0; build-server.sh=0
cadr mode/size/version: -rwxr-xr-x 66462720 bytes; cadr 0.1.0
cadr-server mode/size/version: -rwxr-xr-x 57220840 bytes; cadr-server 0.1.0
cadr SHA-256: 53c3adf8ca0f7af0dba166e6668be23f01ce96762e99c10b7f94a5c1193a99d6
cadr-server SHA-256: a973aaa04f1d0f85ee6a59fbe767209fb45b0269e89df48790af05c0a606da61
logs: /tmp/cadr-goal9-build.log; /tmp/cadr-goal9-build-server.log
```

## 7. 第三轮提交

| commit | 内容 |
|---|---|
| `3b41becd3` | provider thinking 能力矩阵与字节级模式门禁 |
| `94c1b0822` | tool preview、Markdown 与 editor autocomplete |
| `7d89b096b` | overlay 完整合约、settings/auth/extension glue 与运行时门禁 |
| `本报告提交` | docs/README 收口与最终证据 |

提交后须再次确认本轮路径无未提交变更；用户预存的
`docs/acceptance/goal-v8-final.md`、`.obsidian/`、`goal9.md`、`goal10.md` 与
`scripts/__pycache__/` 不属于本轮且保持原样。

## 8. B3 人工门禁

精确启动命令、环境约束和 11 个逐场景检查项见
[`visual-parity.md`](../visual-parity.md#b3-双终端-ab-门禁)。

当前处置：`第三轮机械门禁、全量、PTY、构建与提交已落账；等待用户重新逐项确认`。
收到确认前不开始 Part C。
