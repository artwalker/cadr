# Goal 9 Part B 阶段报告

> 状态：B1/B2 的基线复现、机械差异账本、实现、永久门禁和提交均已完成；
> B3 双终端 A/B 等待用户逐项确认。Part C 尚未开始。

## 1. 基线与机械账本

- 规范基线：`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`。
- 基线 checkout：`/tmp/cadr-parity-74caa2649`，`git rev-parse HEAD` 与规范
  hash 逐字节一致。
- `npm run build:offline` 成功；基线 source runner `--version` 为 `0.83.0`。
- 基线 TUI 已在 100×32 `tmux` PTY 中冷启动并以 `/quit` 正常退出。
- [`visual-parity.md`](../visual-parity.md) 共 32 个机械编号项：
  `一致` 2 项，`不一致（已改齐）` 30 项，`有意差异` 0 项，`pending` 0 项。

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

## 3. 色彩字节证据

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

## 4. 测试证据

### 4.1 隔离、确定性全量与构建

为避免个人配置和外部账户额度污染构建，使用空临时 `HOME`，并显式移除
`DEEPSEEK_API_KEY`：

```bash
env -u DEEPSEEK_API_KEY \
  HOME=/tmp/cadr-goal9-build-home.7HdeYJ \
  QUICKLISP_SETUP=/root/quicklisp/setup.lisp \
  ./build.sh
```

结果为 `4736 checks / 4728 pass / 8 credential-gated skip / 0 fail`：

| suite | checks | pass | skip | fail |
|---|---:|---:|---:|---:|
| cadr-ai | 728 | 726 | 2 | 0 |
| cadr-agent | 621 | 621 | 0 | 0 |
| cadr-tui | 1104 | 1104 | 0 | 0 |
| cadr-cli | 1599 | 1597 | 2 | 0 |
| cadr-storage | 23 | 23 | 0 | 0 |
| cadr-server | 43 | 43 | 0 | 0 |
| cadr-evals | 121 | 117 | 4 | 0 |
| cadr-protocol | 497 | 497 | 0 | 0 |

完整日志：`/tmp/cadr-goal9-part-b-isolated-build.log`。

### 4.2 真实凭据门禁

真实用户环境的全量尝试与被中断套件补跑合计：

- AI：`732 / 731 pass / 1 skip / 0 fail`。
- agent：`621 / 621 pass`。
- TUI：`1104 / 1104 pass`。
- CLI：`1603 / 1600 pass / 3 fail`；三个 assertion 属同一真实 Codex OAuth
  请求，服务端返回 `The usage limit has been reached`。
- storage：`23 / 23 pass`。
- server：`43 / 43 pass`。
- evals：`129 / 127 pass / 2 fail`；Codex OAuth 同样受账户额度限制；
  DeepSeek repository loop 首次达到 100-turn 上限。
- protocol：`497 / 497 pass`。

DeepSeek repository loop 随后按原断言单独复跑：
`5 checks / 5 pass / 0 skip / 0 fail`。没有改写输入、跳过门禁或弱化断言。

日志：

- `/tmp/cadr-goal9-part-b-full-test.log`
- `/tmp/cadr-goal9-part-b-tail-test.log`
- `/tmp/cadr-goal9-part-b-deepseek-retry.log`
- `/tmp/cadr-goal9-part-b-protocol-test.log`

因此确定性回归面全绿，DeepSeek live 门禁真跑且复跑全绿；当前唯一未通过的
live 外部态是 Codex OAuth 账户额度。它不被伪装成产品通过，也没有成为视觉
实现的特殊分支。

## 5. 隔离构建产物

本机 SBCL 不提供 `sb-core-compression`，`build.sh` 按既定合约降级为无压缩
镜像并成功退出：

```text
cadr build: SBCL lacks sb-core-compression; building an uncompressed image.
cadr         66167784 bytes mode=755  cadr 0.1.0
cadr-server  57155288 bytes mode=755  cadr-server 0.1.0
```

SHA-256：

```text
ba96f5ad365b5d4502d3ba5ceceb927a8183da4c734a3af449014ea4fcd1da55  cadr
678f80a3f1429dd6174dc93ed4ab21464dbc857ceea0cb7cde2613a5c362d6a0  cadr-server
```

## 6. 实现提交

| commit | 内容 |
|---|---|
| `81c45c35e` | footer model state 同步 |
| `67fb5661a` | semantic terminal themes |
| `c94577f60` | editor 与 cursor 视觉 |
| `b2c1d2aee` | themed terminal components |
| `c9a730337` | terminal visual primitives |
| `77b7440dc` | interactive visual behavior |

本阶段开发用量快照：`4,210,661 tokens / 19,459 seconds`。

## 7. B3 人工门禁

精确启动命令、环境约束和 11 个逐场景检查项见
[`visual-parity.md`](../visual-parity.md#b3-双终端-ab-门禁)。

当前处置：`等待用户逐项确认`。收到确认前不开始 Part C。
