# Goal 9 Part B 阶段报告

> 状态：第五轮 timeout 噪音与时序确定性补正已落账；全量连续 5 次零失败。
> 按用户要求暂停，等待重新验收；Part C 尚未开始。

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
| write running/success 文案 | `src/cadr-cli/tui.lisp:1221-1249,1261-1501`；`test/cadr-cli/tui-test.lisp:1274` `GOAL9-B3-WRITE-TOOL-DISPLAYS-REQUEST-CONTENT-NOT-BYTE-RECEIPT` | running 与 success 均展示请求 content 的基线 preview；模型侧 result 已在第 3.3 节另行按基线逐字修正，显示层不得以 receipt 替代 content。 | 旧测试只测 executor receipt 和 tool status，未对 event→block 的完整 output 行做 start/end 快照，也没有验证 receipt 自身是否符合基线。 |
| `/model` `tab scope` 提示 | `src/cadr-cli/interactive-services.lisp:8012`；`test/cadr-cli/goal9-b3-p2-regressions-test.lisp:7` `GOAL9-B3-MODEL-OVERLAY-COPY-MATCHES-UNSCOPED-BASELINE`；`test/cadr-cli/goal9-b3-overlay-contract-test.lisp:144` `GOAL9-B3-MODEL-OVERLAYS-HAVE-COMPLETE-BASELINE-LINE-CONTRACTS` | unscoped/scoped 两条完整文案路径均不再出现 `tab scope (all/scoped)`；scoped 状态只保留 `Scope: all | scoped` 状态标题。 | 旧门禁只覆盖 unscoped 分支，并把 scoped 分支残留提示当作允许差异；宣告范围大于真实验证范围。 |
| read collapsed preview | `src/cadr-tui/components.lisp:1213-1222,1514-1565`；`test/cadr-tui/components-test.lisp:423` `GOAL9-TOOL-COLLAPSED-PREVIEWS-MATCH-BASELINE-BUDGETS` | 成功 read 折叠态不显示结果；展开显示完整结果；error 始终可见。 | 旧共享 budget 错把 read 与 write 合并为 10 行，并只断言裁剪数量，未对照 read 专用 result renderer。 |
| Markdown streaming fence | `src/cadr-tui/components.lisp:796-906`；`test/cadr-tui/components-test.lisp:764` `GOAL9-MARKDOWN-STREAMING-FENCES-MATCH-BASELINE-EXACTLY`；`test/cadr-cli/goal9-b-runtime-parity-test.lisp:174` `GOAL9-STREAMED-MARKDOWN-FENCE-IS-EXACT-THROUGH-THE-FULL-TUI-CHAIN` | 审计基线完成态本身保留开、闭 fence 行，因此截图中的字面 <code>```text</code> / <code>```</code> 已核实为非差异；本轮只修 empty/partial streaming fence 与 fence 后首个空 code line，并从 delta 经 TUI state、Markdown renderer 到 virtual terminal 锁定完整链路。 | 旧测试偏重完成态和 token 样式，没有逐帧固定完整行数组，也没有穿过完整 TUI 链。 |
| 15 个 overlay 整屏合约 | `test/cadr-cli/goal9-b3-overlay-contract-test.lisp:125` `GOAL9-B3-EVERY-OVERLAY-HAS-AN-EXACT-FULL-VIRTUAL-TERMINAL-SNAPSHOT` | model、model-scoped、settings、resume、fork、tree、scoped-models、trust、login-method、login-provider、logout-provider、api-key、import、extension-select、extension-custom 均锁定完整 virtual-screen SHA-256。收尾自查发现初版清单漏列独立 `/logout` surface；新增 case 先以 `PENDING` 期望复现 `14 pass / 1 fail`，再锁定真实整屏 SHA 转绿。 | 原门禁分散在 substring、样式 token 和业务 action 测试，只抽查六个 overlay；本轮初版枚举又误把 login/logout 共用 renderer 当成同一 surface，未证明每个命令 surface 的整屏输出。 |
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

## 3.3 第四轮：模型可见 tool result 逐字审计

本轮把工具调用拆成三层独立合约：request/arguments、写入会话并回传模型的
result、TUI renderer。前一轮只修 write 的显示层，甚至把错误 receipt 误写成
“按基线保留”；本轮以注册表 `+builtin-coding-tool-names+` 的七个工具为封闭集合，
逐个对照审计提交源码。`glob.lisp` 只是测试/内部辅助，未注册为模型可调用工具，
不冒充第八个内置工具。

| 工具 | 审计基线 `file:line` | 模型可见 result 合约 | Cadr 源码与永久门禁 | 结论 |
|---|---|---|---|---|
| write | `packages/coding-agent/src/core/tools/write.ts:220-223` | `Successfully wrote N bytes to <原始 path>`；`N=JavaScript content.length`，即 UTF-16 码元数，不是 UTF-8 bytes。 | `src/cadr-cli/tools/write.lisp:42`；`GOAL9-B3-WRITE-RESULT-MATCHES-BASELINE-UTF16-CODE-UNIT-COUNT` 用 `中🙂` 锁定 `N=3`。 | 不一致（已改齐） |
| edit | `packages/coding-agent/src/core/tools/edit.ts:323-360`；`packages/coding-agent/src/core/tools/edit-diff.ts:257-292,347-352` | success、ENOENT、not-found、duplicate、no-change、overlap 均保留原始 path、edit index 与 replacement 数。 | `src/cadr-cli/tools/edit.lisp:173-269,577-632`；`GOAL9-B3-EDIT-RESULT-AND-ERRORS-MATCH-BASELINE-COPY`。 | 不一致（已改齐） |
| read | `packages/coding-agent/src/core/tools/read.ts:246-315`；`packages/coding-agent/src/utils/image-process.ts:67-117`；`packages/coding-agent/src/utils/image-resize.ts:116-123` | user limit、2000 行、50.0KB、首行超限、总行数/next offset；图片转换/省略/resize 坐标提示均逐字且数值同口径。 | `src/cadr-cli/tools/read.lisp:3-100`、`src/cadr-cli/interactive-services.lisp:3174-3294`；`GOAL9-B3-READ-RESULT-NOTICES-MATCH-BASELINE-LINE-COUNTS`。 | 不一致（已改齐） |
| bash | `packages/coding-agent/src/core/tools/bash.ts:404-454` | 空输出、非零退出、timeout、2000 行/50.0KB/单长行截断提示；随机 full-output path 只替换值，模板逐字一致。 | `src/cadr-cli/tools/bash.lisp:48-87,220-316`；`GOAL9-B3-BASH-RESULT-STATUS-AND-TRUNCATION-COPY-MATCH-BASELINE`。额外移除 timeout 时 `setsid` 注入的非命令 stderr。 | 不一致（已改齐） |
| find | `packages/coding-agent/src/core/tools/find.ts:282-346` | 空结果、`N results limit reached. Use limit=2N...`、50.0KB notice；路径相对 search root。 | `src/cadr-cli/tools/find.lisp:10-71`；`GOAL9-B3-SEARCH-TOOL-RESULTS-MATCH-BASELINE-COPY-AND-COUNTS`。 | 不一致（已改齐） |
| grep | `packages/coding-agent/src/core/tools/grep.ts:178-356` | default limit 100；`path:line: text`/context spacing；500 UTF-16 码元长行；match/byte/long-line notice 与数值。 | `src/cadr-cli/tools/grep.lisp:10-136`；同一 search 门禁以 CJK/emoji 边界锁定 UTF-16 口径，并覆盖 byte-boundary。 | 不一致（已改齐） |
| ls | `packages/coding-agent/src/core/tools/ls.ts:124-202` | `(empty directory)`、排序/目录 `/`、entry limit 与 50.0KB notice。 | `src/cadr-cli/tools/ls.lisp:11-73`；同一 search 门禁及既有 limit 门禁。 | 不一致（已改齐） |

运行时/操作系统原生异常只允许保留“实现语言迁移必然导致的异常对象措辞”差异；
所有项目自行拼装并会进入会话的 success/error/continuation/truncation 文案均已逐字
对齐。图片能力的 provider 请求策略仍由既有 `cadr-ai` 冻结层负责，本表只审计
read tool 产生的 result 内容，不借此修改 provider 机制。

红相不是抽象推断：write 用 `中🙂` 得到旧值 `7 UTF-8 bytes` 而基线为 `3 bytes`；
edit、read、bash、find/grep/ls 的旧文案/notice 同批失败；图片分支随后复现旧
`Converted image/bmp to PNG` 与损坏 BMP 被误当文本 `BM`。先前 6878 条为何漏过：
write 只有 ASCII，导致 UTF-8 bytes 与 UTF-16 units 恰好相等；其余测试只断言文件
副作用、substring、details flag 或 TUI 展示，没有把 executor result 作为完整字符串
快照，也没有 Unicode、截断边界和损坏图片输入。本轮专用门禁 `24/24`，其中
grep 另用 CJK/emoji 构造“Common Lisp 字符数小于 500、UTF-16 码元数大于 500”
的边界，防止同类计数口径再次被 ASCII 掩盖。

## 3.4 第五轮：timeout 噪音与时序确定性补正

`setsid: child ... did not exit normally: Success` 不是可忽略的测试噪音。旧实现把
`setsid` 自身 stderr 与命令 stdout/stderr 合并到同一 pipe，wrapper 退出竞态因此会
污染模型可见 tool result。`src/cadr-cli/tools/bash.lisp:141-163` 现把命令 stderr 在
child session 内以 `2>&1` 合并到命令 stdout，同时令 `setsid` 自身
`:error-output nil`；没有使用 regex 擦除，故用户命令真实输出中即使包含 `setsid:`
也不会被误删。

timeout 门禁改用不会自行退出的 `exec /usr/bin/tail -f /dev/null`，且 deadline 在
process-group ID 显式建立后才开始；它验证的只可能是 timeout，不再与 `sleep 1` 的
自然结束争抢 50 ms 窗口。永久门禁为
`GOAL9-B3-BASH-RESULT-STATUS-AND-TRUNCATION-COPY-MATCH-BASELINE` 与
`GOAL9-B3-BASH-TIMEOUT-NEVER-LEAKS-WRAPPER-DIAGNOSTICS`
（`test/cadr-cli/tool-result-parity-test.lisp:159-219`），后者单独断言 result 不含
`setsid:` 或 `cadr-bash-wrapper`。

原 6203 checks 没捕获的原因是：bash 用例只在一次 50 ms 竞速中精确比较最终文案，
既未隔离 wrapper fd，也未单独断言 wrapper 词汇永不出现；preflight 用例又把
“50 ms 内 shutdown thread 没结束”当成 shutdown 已开始的替代证据，scheduler
稍慢就会在 release 前尚未写入 shutdown flag。其余并发门禁也多只验最终状态，
没有证明中间态确实已到达。新增检查锁的是显式状态转移，不再靠运行得够快取胜。

时序审计不是只修两条已知红灯。以下自动化面已全部从“等一小段时间然后猜状态”
改成可观察状态握手：

| 范围 | 旧竞态 | 当前确定性同步 |
|---|---|---|
| agent shutdown/preflight/compaction/tree | `sleep 1ms` 轮询或 50 ms 反向 semaphore timeout | 在 agent lock 下等待 shutdown flag 的 condition broadcast，并断言 active operation/mutation count；见 `test/cadr-agent/shutdown-test.lisp:24-365`。 |
| parallel tools、file mutation | 用 10–80 ms 延迟制造先后顺序 | entered/release semaphore；realpath alias 另断言共享同一 mutex；见 `tool-loop-test.lisp:102`、`part-b-tools-test.lisp:76`。 |
| execution-env/bash subprocess | 短 timeout 与有限 `sleep` 进程竞速；后台输出靠延迟 | 不自行退出的 `tail -f /dev/null`；FIFO 明确握手后台 writer ready/release，并以 `/proc/<pid>` 证明清理；见 `execution-env-test.lisp:182`、`bash-test.lisp:80`。 |
| SSE/真实 HTTP socket | delayed stream 与第二帧靠 wall-clock sleep | stream entered/release semaphore；首个 SSE callback 释放 server 第二帧；见 `test/cadr-ai/http-test.lisp:47-177`。 |
| RPC prompt/UI/bash | 10 ms 轮询 thread、pending hash 与输出 | join 已捕获 worker；newline-notifying Gray stream 驱动 JSON record handshake；bash worker 同步 join/abort；见 `test/cadr-cli/helpers.lisp:46-95`、`rpc-test.lisp:5-380`。 |
| footer debounce/render | 10–50 ms sleep/poll | 注入 monotonic clock，跨越 debounce 边界前后逐次调用并断言；见 `interactive-services.lisp:2113-2290`、`part-b-interactive-test.lisp:668-883`。 |
| extension/TUI overlay | worker polling再固定等 20 ms | overlay 安装完成 callback 发 semaphore；git daemon 读取 `Ready to rumble`；见 `goal9-b3-overlay-contract-test.lisp:650-742`、`extensions-test.lisp:614-686`。 |
| TUI command/event | 轮询 footer/model/theme/progress flags | command callback 在返回前完成状态更新；busy abort 用 semaphore；RPC workflow join worker；见 `tui-test.lisp`、`goal9-a2-interactive-test.lisp:115`、`goal9-a2-workflows-test.lisp:187`。 |
| PTY smoke | 发键/resize 后固定 sleep 再截图；等待已删除的 `sessions` 文案和旧 prompt glyph | 每个动作轮询其确切可见状态或 terminal-restored marker；当前 slash surface、无 glyph editor 与 `/quit` 路径逐项校正；见 `scripts/{goal5-manual-tui-smoke,live-tui-smoke}.sh`。 |

全仓 `sleep`/timeout 审计的剩余项分三类，均不以时间流逝决定断言真假：

- `test/cadr-tui/manual-acceptance-test.lisp:250` 只给人工交互 event loop 限速，自动
  FiveAM 测试不会调用该 runner。
- `test/cadr-cli/tui-test.lisp:1178-1207` 的 `"sleep 1"` 是不执行的标题 fixture；
  extension/RPC/sdk 的 `timeout-ms` 是 payload/立即取消语义，retry 测试注入假的
  sleep function。
- process/PTY smoke 中保留的 `sleep` 只是在有界循环中降低 polling 频率；成功条件
  是 port file、Unix socket、request marker、精确 screen state 或恢复 marker，
  不再有固定延迟后直接断言的路径。

此前报告把 `SHUTDOWN-DURING-PREFLIGHT-PREVENTS-PROVIDER-START` 的首跑失败写成
“立即复跑全绿”，该收尾判定是错的，现明确撤回。今后任何测试若需复跑才绿，本轮
即未完成：必须保留首次红灯、定位不确定性并改为显式同步，不能用第二次结果覆盖它。

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

## 5. 第五轮最终机械证据

代码冻结在 `be243c0ab` 与 `baaf6dd75` 后，使用当前用户 settings/auth 状态连续执行
同一条 `./scripts/test-cl.sh` 五次；没有失败后重跑、没有丢弃任何一轮：

| run | checks | pass | skip | fail | 完整日志 |
|---:|---:|---:|---:|---:|---|
| 1 | 6919 | 6918 | 1 | 0 | `/tmp/cadr-goal9-flake-run-1.log` |
| 2 | 6919 | 6918 | 1 | 0 | `/tmp/cadr-goal9-flake-run-2.log` |
| 3 | 6919 | 6918 | 1 | 0 | `/tmp/cadr-goal9-flake-run-3.log` |
| 4 | 6919 | 6918 | 1 | 0 | `/tmp/cadr-goal9-flake-run-4.log` |
| 5 | 6919 | 6918 | 1 | 0 | `/tmp/cadr-goal9-flake-run-5.log` |

每轮唯一 skip 都是本机没有 `ANTHROPIC_API_KEY` 的
`LIVE-ANTHROPIC-STREAM-PRESERVES-TWO-TURN-CONTEXT`；DeepSeek 与 Codex OAuth live
门禁均实际执行。分层复核为 `cadr-agent 623/623`、`cadr-cli 2508/2508`、
`cadr-ai 1911 checks / 1910 pass / 1 skip / 0 fail`。

外挂 PTY smoke 同样改为状态同步后真实执行：

- `./scripts/goal5-manual-tui-smoke.sh`：overlay focus、CJK、image fallback、resize、
  terminal restore 全部通过。
- `./scripts/live-tui-smoke.sh`：当前 slash surface、autocomplete/undo/kill-ring、
  DeepSeek 两轮 write/edit、resize、CJK、`/quit` terminal restore 全部通过；日志
  `/tmp/cadr-goal9-live-tui-smoke.log`。

残留 grep 命令与原始输出：

```text
$ rg -n 'strip-setsid-timeout-noise|:error-output :output' src/cadr-cli/tools/bash.lisp
(no output; exit 1)

$ rg -n '2>&1|:error-output nil' src/cadr-cli/tools/bash.lisp
153:             "printf '%s' \"$$\" > \"$1\"; exec /bin/bash -lc \"$2\" 2>&1"
163:            :error-output nil

$ rg -n '\(sleep\s' test
test/cadr-tui/manual-acceptance-test.lisp:250:                  (sleep 0.02d0))

$ rg -n 'setsid:|cadr-bash-wrapper' test/cadr-cli/tool-result-parity-test.lisp
218:      (is (null (search "setsid:" message)))
219:      (is (null (search "cadr-bash-wrapper" message))))))
```

模型可见 executor result 与 TUI preview 仍分别有门禁；write 的 UTF-16 receipt
语义没有被本轮时序补正改动。

## 6. 第四轮隔离构建产物（历史证据）

以下 hash 是第四轮产物，不冒充第五轮源码构建证据；本轮用户指定的验收门槛是
连续 5 次全量与保留 smoke，未要求重建发布二进制：

```text
compression branch: SBCL lacks sb-core-compression; both builds used the documented uncompressed fallback
build exit: build.sh=0; build-server.sh=0
cadr mode/size/version: -rwxr-xr-x 66462720 bytes; cadr 0.1.0
cadr-server mode/size/version: -rwxr-xr-x 57220840 bytes; cadr-server 0.1.0
cadr SHA-256: 53c3adf8ca0f7af0dba166e6668be23f01ce96762e99c10b7f94a5c1193a99d6
cadr-server SHA-256: a973aaa04f1d0f85ee6a59fbe767209fb45b0269e89df48790af05c0a606da61
logs: /tmp/cadr-goal9-build.log; /tmp/cadr-goal9-build-server.log
```

## 7. 第三至第五轮提交

| commit | 内容 |
|---|---|
| `3b41becd3` | provider thinking 能力矩阵与字节级模式门禁 |
| `94c1b0822` | tool preview、Markdown 与 editor autocomplete |
| `7d89b096b` | overlay 完整合约、settings/auth/extension glue 与运行时门禁 |
| `d77321774` | docs/README 收口与最终证据 |
| `034f69e0f` | 明确完成态 Markdown fence 为已核实非差异 |
| `21ae81f13` | 补齐 `/logout` 独立整屏 SHA，并刷新第三轮全量数字 |
| `1c442d271` | 第四轮模型可见 tool result 与永久回归门禁 |
| `be243c0ab` | 隔离 `setsid` wrapper stderr、确定性 timeout target 与无噪音回归 |
| `baaf6dd75` | 全套时序测试改用 semaphore/condition/join/FIFO/injected clock |
| `29e9bade9` | PTY smoke 改为观察实际 screen/marker 状态，不再固定延迟断言 |

提交后须再次确认本轮路径无未提交变更；用户预存的
`docs/acceptance/goal-v8-final.md`、`.obsidian/`、`goal9.md`、`goal10.md` 与
`scripts/__pycache__/` 不属于本轮且保持原样。

## 8. B3 人工门禁

精确启动命令、环境约束和 11 个逐场景检查项见
[`visual-parity.md`](../visual-parity.md#b3-双终端-ab-门禁)。

当前处置：`第五轮 timeout/时序补正、连续五轮全量与提交已落账；按要求暂停`。
收到确认前不开始 Part C。
