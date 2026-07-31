# Goal 9 Part B 阶段报告

> 状态：首轮 B3 双终端 A/B 已由用户退回。P0→P2 运行时补正已实施；
> 本报告更新机械证据并等待用户重新验收。Part C 尚未开始。

## 1. 基线与机械账本

- 规范基线：`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`。
- 基线 checkout：`/tmp/cadr-parity-74caa2649`，`git rev-parse HEAD` 与规范
  hash 逐字节一致。
- `npm run build:offline` 成功；基线 source runner `--version` 为 `0.83.0`。
- 基线 TUI 已在 100×32 `tmux` PTY 中冷启动并以 `/quit` 正常退出。
- [`visual-parity.md`](../visual-parity.md) 共 33 个机械编号项：
  `一致` 2 项，`不一致（已改齐）` 31 项，`有意差异` 0 项，`pending` 0 项。

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
  与窄屏裁剪。

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
| P1-4 exit 7 显示成功 | `GOAL9-B-BASH-NONZERO-EXIT-IS-A-TOOL-ERROR`、`GOAL9-B-NONZERO-BASH-TOOL-RENDERS-ERROR-STATE` | 非零退出从普通 result 改为 error tool result；运行时 block 为 `:error`、`× $`、error background。 | 组件测试手工构造 `:error`，bash 测试只找 exit footer；没有跑真实 agent tool loop 验证 result `is-error` 到 TUI 状态。 |
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

## 5. 测试证据

### 5.1 隔离、确定性全量与构建

为避免个人配置和外部账户额度污染构建，使用空临时 `HOME`，并显式移除
`DEEPSEEK_API_KEY`：

```bash
env -u DEEPSEEK_API_KEY \
  HOME=/tmp/cadr-goal9-b-return-home.wJ0Ly4 \
  QUICKLISP_SETUP=/root/quicklisp/setup.lisp \
  ./build.sh
```

结果为 `5376 checks / 5368 pass / 8 credential-gated skip / 0 fail`：

| suite | checks | pass | skip | fail |
|---|---:|---:|---:|---:|
| cadr-ai | 728 | 726 | 2 | 0 |
| cadr-agent | 621 | 621 | 0 | 0 |
| cadr-tui | 1162 | 1162 | 0 | 0 |
| cadr-cli | 2181 | 2179 | 2 | 0 |
| cadr-storage | 23 | 23 | 0 | 0 |
| cadr-server | 43 | 43 | 0 | 0 |
| cadr-evals | 121 | 117 | 4 | 0 |
| cadr-protocol | 497 | 497 | 0 | 0 |

完整日志：`/tmp/cadr-goal9-b-return-build.log`。

### 5.2 真实凭据门禁

真实用户环境执行 `./scripts/test-cl.sh`，结果为
`5399 checks / 5398 pass / 1 credential-gated skip / 0 fail`：

- AI：`732 / 731 pass / 1 skip / 0 fail`。
- agent：`621 / 621 pass`。
- TUI：`1162 / 1162 pass`。
- CLI：`2185 / 2185 pass`。
- storage：`23 / 23 pass`。
- server：`43 / 43 pass`。
- evals：`136 / 136 pass`。
- protocol：`497 / 497 pass`。

DeepSeek chat、DeepSeek eval/repository loop、Codex OAuth CLI/eval 均在套件内
真实执行并全绿；唯一 skip 是本机无 Anthropic 凭据，与既定 live 门控同构。
完整日志：`/tmp/cadr-goal9-b-return-full-final.log`。

## 6. 隔离构建产物

本机 SBCL 不提供 `sb-core-compression`，`build.sh` 按既定合约降级为无压缩
镜像并成功退出：

```text
cadr build: SBCL lacks sb-core-compression; building an uncompressed image.
cadr         66233320 bytes mode=755  cadr 0.1.0
cadr-server  57155288 bytes mode=755  cadr-server 0.1.0
```

SHA-256：

```text
4e4146b4c125ea2b811951867d57840b4e079a906e7fd528b20da561af6d4c6f  cadr
678f80a3f1429dd6174dc93ed4ab21464dbc857ceea0cb7cde2613a5c362d6a0  cadr-server
```

## 7. 实现提交

| commit | 内容 |
|---|---|
| `81c45c35e` | footer model state 同步 |
| `67fb5661a` | semantic terminal themes |
| `c94577f60` | editor 与 cursor 视觉 |
| `b2c1d2aee` | themed terminal components |
| `c9a730337` | terminal visual primitives |
| `77b7440dc` | interactive visual behavior |

本阶段开发用量快照：`4,210,661 tokens / 19,459 seconds`。

## 8. B3 人工门禁

精确启动命令、环境约束和 11 个逐场景检查项见
[`visual-parity.md`](../visual-parity.md#b3-双终端-ab-门禁)。

当前处置：`等待用户重新逐项确认`。收到确认前不开始 Part C。
