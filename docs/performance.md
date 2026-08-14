# Performance and stability

<!-- GOAL12_LEDGER baseline=53fa77ccd8a279eb87e92294ef3687b03ff80112 source=595/518/77/0 examples=99/99/0 -->

本文是四根独立验收轴中的**非功能账**：行为门禁回答“产出了什么”，源码账
回答固定基线的能力落在何处，呈现账回答用户看到了什么，本文回答“产出它花了
多少时间、分配和常驻资源”。所有优化仍须通过既有 payload、会话、完整文案和
虚拟终端逐字门禁。

行为覆盖见 `docs/parity-map.md`，逐源文件处置见 `docs/source-parity.md`，非功能
预算由本文 `docs/performance.md` 维护，呈现语义见
`docs/presentation-parity.md`。`examples/manifest.sexp` 是 99 个可运行
扩展示例的辅助 inventory，不是第五本账。上方 `GOAL12_LEDGER` 身份继续锁定
source/example 分母；呈现账另以 `GOAL13_PRESENTATION_LEDGER` 锁定自己的
B1-B4 分母与处置总数。

## Measurement contract

一键入口：

```sh
./scripts/bench.sh --label local --output /tmp/cadr-performance.json
```

默认参数固定为 100×40 终端、`N ∈ {0, 50, 200, 1000, 5000}`、1 次
warm-up 与 5 次正式样本；输出是 schema version 1 的 JSON。正式样本报告
median 与 MAD，并保留全部原始样本。`--quick` 只供开发期冒烟，不能作为
验收数字。

会话条目按固定五项循环生成：用户 Markdown+CJK/emoji、助手 Markdown、
折叠 read tool block、展开 bash tool block、图片 Markdown 占位+CJK/emoji。
没有真实 LLM、网络或随机输入。热路径分别测量：

- `frame_render`：production `render-tui-state → render-frame → virtual-terminal`；
- `key_to_frame`：原始输入字节经 input decoder/editor 后写出一帧；
- `stream_delta_to_frame`：固定 text delta 经 agent event 组装后写出一帧，
  同时报告 delta/s；
- `mouse_drag_to_frame`：alternate screen 中真实 SGR press/drag 字节经 selection
  更新后写出一帧；
- `wheel_to_frame`：alternate screen 中真实 SGR wheel-up/down 字节在长 transcript
  中段滚动并写出一帧；
- `continuous_alt_input`：在 5000-entry transcript 上混合 1024 个拖拽与滚轮
  事件，逐事件保留 wall latency、分配量、p95/p99/max 与 GC-affected event
  latency；
- `common_continuous_input`：以匿名真实会话 profile 的 p95 entry 数为 common
  tier，将 mouse drag、wheel 与 editor key 拆成三条互不稀释的 1024-event
  trace，各自保留原始 latency/allocation samples 并执行 p99 ≤16ms 绝对门禁；
- `append_entry`：在固定长度历史尾部追加一个条目并 O(1) 恢复 fixture。

分配量来自 `sb-ext:get-bytes-consed`；堆占用来自
`sb-kernel:dynamic-usage`；Linux RSS 来自 `/proc/self/statm`。冷启动由独立
Python stdlib PTY harness 在全新临时 `HOME`、无 provider 凭据环境中启动
native `./cadr`，从 `Popen` 到首帧出现 `cadr v` 为止计时，再用 `/quit`
验证干净退出。它是“新进程到首个真实 TUI 帧”，不是较弱的 `--version`
路径，也不通过 drop caches 取得不可移植的伪冷磁盘数字。

连续输入测量在 `unwind-protect` 内临时把 SBCL nursery 固定为 8MiB，退出时
恢复原值。它故意让 1024-event run 穿过多次 GC；报告中的
`gc_affected_max_us` 是用户实际承受的整次 event→frame wall latency，
`gc_cpu_us` 只作诊断，绝不冒充精确 stop-the-world wall pause。

复杂度标签由正 N 点的 log-log 斜率生成：`<0.35` 为 constant，
`<1.5` 为 linear，其余为 quadratic-or-worse。标签是回归线索；门禁阈值
将在 Goal 11 Part E 依据优化后数据与机器留白确定。

## Before-optimization baseline

锚点：HEAD `0895199805b3905c8e803f95d0d48ad3329a6b8f`，
`src/cadr-cli/tui.lisp` object
`8457a98cd96959293a173d941702c97b55e6e7bc`；SBCL 2.6.7，x86-64，
机器 `Friend-MachineD`。完整逐样本 JSON：
[`benchmarks/goal-v11-before.json`](benchmarks/goal-v11-before.json)。

时间单位为 µs/op；分配单位为 bytes/op。

| metric | N=0 | N=50 | N=200 | N=1000 | N=5000 | classification |
|---|---:|---:|---:|---:|---:|---|
| frame time | 800.1 | 8,400.1 | 25,600.5 | 108,002.0 | 488,010.0 | linear (0.884) |
| frame allocation | 134,156.8 | 1,927,867.2 | 6,022,476.8 | 28,295,472 | 139,581,776 | linear growth |
| key→frame time | 2,000.0 | 9,200.2 | 25,600.4 | 102,668.7 | 480,010.0 | linear (0.861) |
| key→frame allocation | 723,761.6 | 2,393,868.8 | 6,490,976.0 | 28,392,656 | 138,620,320 | linear growth |
| stream delta→frame time | 1,000.1 | 8,400.2 | 22,200.4 | 95,201.6 | 466,009.0 | linear (0.878) |
| stream throughput (delta/s) | 999.95 | 119.05 | 45.04 | 10.50 | 2.15 | inverse-linear |
| append time | 0.024 | 0.080 | 0.240 | 1.067 | 5.200 | linear (0.910) |

5000 条目时，一个不改变历史的普通按键仍耗时约 480ms、分配约 132MiB；
流式路径只能处理约 2.15 delta/s。这解释了用户实际感受到的卡顿，不是观感
猜测。追加单次绝对时间虽小，但斜率确认其为 O(N)，连续建会话累计为
O(N²)。

| N | SBCL heap total | heap delta vs N=0 | RSS total | RSS delta vs N=0 |
|---:|---:|---:|---:|---:|
| 0 | 35,900,704 | 0 | 64,978,944 | 0 |
| 50 | 35,890,864 | -9,840 | 64,839,680 | -139,264 |
| 200 | 36,010,816 | 110,112 | 65,032,192 | 53,248 |
| 1000 | 36,517,056 | 616,352 | 65,658,880 | 679,936 |
| 5000 | 38,855,280 | 2,954,576 | 67,850,240 | 2,871,296 |

小 N 的负 delta 是 full GC 与页驻留噪声；5000 条目的 heap/RSS 增量均约
2.8MiB，整体曲线为线性。新进程到首个真实 TUI 帧为 163,502µs，
MAD 4,518µs（五个样本 156–175ms）。

## Fixed TS baseline strategy

审计对象固定为 `53fa77ccd`，不是持续移动的上游 `main`。结论很明确：pi
同样每帧遍历完整组件树，并没有 viewport-before-render、虚拟滚动或持久化的
历史前缀帧；它的优势来自组件级缓存、O(1) 追加、render request 合并，以及
只向终端写变化行。

### Process-start lower bound

2026-08-04 同机 `--version` 实测补齐如下。稳定态是在文件缓存与运行时产物均已
就绪后重复启动；“首次”是该轮首次进程启动。该命令在打印版本后立即退出，**不含
TUI 初始化、首帧渲染、配置发现或交互组件构造**，只能作为进程启动成本的下限
对照，不能替代本文其余真实 PTY 冷启动数字。

| `--version` process time | cadr | pi `53fa77ccd` |
|---|---:|---:|
| stable | 0.01s | 0.83s |
| first | 0.05s | 1.72s |

| dimension | baseline behavior and evidence |
|---|---|
| history append | `Container.children` 是数组，`addChild()` 直接 `push`，即 O(1)；`packages/tui/src/tui.ts:211-216`。interactive mode 只把新 message/tool component 加到 `chatContainer`；`packages/coding-agent/src/modes/interactive/interactive-mode.ts:2942-2962, 3318-3369`。 |
| per-component cache | `Markdown` 以 source text + width 缓存完整 rendered lines，变更时显式失效；`packages/tui/src/components/markdown.ts:121-169, 239-244`。`Text` 使用同一策略；`packages/tui/src/components/text.ts:13-57, 99-104`。bash 折叠预览另有 width-aware cache；`packages/coding-agent/src/modes/interactive/components/bash-execution.ts:148-166`。 |
| streaming invalidation | 每个 delta 只重建当前 `AssistantMessageComponent`，稳定历史 component 不变，然后请求一帧；`packages/coding-agent/src/modes/interactive/interactive-mode.ts:2966-2998`。component 本身在内容变化时重建子树；`packages/coding-agent/src/modes/interactive/components/assistant-message.ts:89-170`。 |
| full traversal | `Container.render()` 每帧遍历每个 child 并拼接其 lines；`packages/tui/src/tui.ts:235-244`。main-screen 明确先 `render(width)` 全部 component；`packages/tui/src/TuiMainScreen.ts:146-173`。因此稳定帧仍是 O(N)，缓存只压低每项常数。 |
| viewport/virtual scroll | alt-screen 先渲染完整 document，之后才以 `scrollTop` slice viewport；`packages/tui/src/TuiAltScreen.ts:350-371`。没有 render 前裁剪或虚拟滚动。 |
| differential write | main-screen 扫描新旧全部 lines 找变化区间，再只写变化 lines；`packages/tui/src/TuiMainScreen.ts:260-287, 354-386`。alt-screen 同样只写变化 row；`packages/tui/src/TuiAltScreen.ts:398-425`。这减少终端 I/O，不消除前面的 O(N) render traversal。 |
| render coalescing | 重复 request 合并，并以 16ms 最小间隔调度；`packages/tui/src/tui.ts:321, 730-770`。 |
| alternate-screen input | mouse drag 与 wheel 只更新 selection/scroll state 并请求 render；下一帧仍完整 render document，再 slice viewport 和 differential-write changed rows；`packages/tui/src/TuiAltScreen.ts:147-167, 350-425`。 |

所以 Part C 只采用基线已有的两种机制：给稳定条目加入 width/content-sensitive
rendered-line cache，并把 Lisp list 尾插改为维护尾指针的 O(1) 追加。不会加入
整段 transcript memoization、viewport pruning 或虚拟滚动；这些都超出基线，
按全局原则必须另交提案。

### Same-machine structural comparison

对照入口：

```sh
node --expose-gc scripts/goal11-pi-baseline-bench.mjs \
  /tmp/cadr-parity-53fa77ccd \
  > /tmp/cadr-goal11-pi-baseline.json
```

脚本拒绝任何不是 `53fa77ccdf10…` 的 worktree。归档对象先以空构建缓存执行
`tui`、`ai build:offline`、`agent`、`coding-agent` 的 clean build，再加载 production
`TuiMainScreen`、`TuiAltScreen`、`Editor`、user/assistant、read tool 与 bash tool
component。归档同时锁定 source object ID、四棵 loaded `dist/` tree SHA-256、
`package-lock.json` object ID 与完整 installed dependency tree SHA-256；整个 JSON
另由 SHA-256 `56e09adc50af1c9433111cc018b095c059f99bf7ada366f5d437f64d64b46ad9`
锁定。每条历史都是独立 production component；100×40、同样 N 梯度、1 次
warm-up、5 次样本，fixture 构建不计时。完整数据见
[`benchmarks/goal-v11-pi-baseline.json`](benchmarks/goal-v11-pi-baseline.json)。

| metric at N=5000 | cadr before | pi `53fa77ccd` | ratio |
|---|---:|---:|---:|
| frame | 488.0ms | 16.43ms | 29.7× |
| key→frame | 480.0ms | 16.61ms | 28.9× |
| stream delta→frame | 466.0ms | 17.31ms | 26.9× |
| append | 5.200µs, linear | 0.00683µs, constant | 761× at N=5000 |

pi 的三条 frame path 仍为线性（log-log exponent 1.050/0.962/0.996），append
为常数（-0.092）。这不是逐字相同 runtime 的绝对吞吐对拍：cadr 还驱动其
virtual-terminal state，而 pi 写入无 I/O mock terminal；因此绝对倍率只作
同机客观标尺，算法判定与 `file:line` 才是实现约束。即使按该限制解释，cadr
5000 条目下 466–488ms 仍远超 pi 的 14–18ms，问题是实质性的高常数与 O(N)
追加，不是“Lisp 天生慢”的借口。

## Optimized results and gates

### Part C — baseline mechanisms restored

实现只使用 Part B 已确认的基线机制：

- `tui-entry` 缓存稳定条目的完整 rendered lines，key 为 width、theme object
  与 extension snapshot；streaming、running tool 和 custom tool renderer 不缓存。
  tool 完成、折叠切换、theme 变更与 extension reload 都会失效。实现位于
  Goal 14 B6 后分别位于 `src/cadr-cli/interactive/state.lisp:3-34`、
  `entries.lisp:88-95` 与 `transcript.lisp:812-874`。
- `tui-state` 保存 list tail 与其所属 head；正常追加直接接到 tail。集中替换
  入口同步重建 tail，历史测试/fixture 若直接 `setf entries`，下一次追加只做
  一次自修复且不会污染旧链。实现位于
  Goal 14 B6 后字段位于 `src/cadr-cli/interactive/state.lisp:36-47`，
  集中追加/替换入口位于 `entries.lisp:47-86`；production reset 仍只走该入口。

基准的 `frame_render` 在 Part C 起显式预热一次 fixture，测量稳定帧；这是缓存
存在后才有意义的方法校正。优化前没有 rendered-line cache，预热后仍会完整
重算，因此归档的 before 数字仍是等价比较锚点。追加 repetitions 同时提高，
避免 O(1) 操作落到 SBCL timer 分辨率以下。

完整 after JSON：
[`benchmarks/goal-v11-after-part-c.json`](benchmarks/goal-v11-after-part-c.json)，
HEAD `56a50ca9cc03…`，TUI object `5b0b4790cd0e…`。

| metric at N=5000 | before | after | improvement | scaling |
|---|---:|---:|---:|---|
| steady frame | 488.01ms / 139.58MB | 4.00ms / 0.72MB | 122× time / 194× allocation | linear 0.884 → constant 0.131 |
| key→frame | 480.01ms / 138.62MB | 4.00ms / 1.38MB | 120× / 101× | linear 0.861 → constant 0.050 |
| stream delta→frame | 466.01ms / 138.63MB | 4.00ms / 1.40MB | 116× / 99× | linear 0.878 → constant 0.066 |
| stream throughput | 2.15 delta/s | 250 delta/s | 116× | — |
| append | 5.200µs | 0.020µs | 260× | linear 0.910 → constant -0.021 |

冷启动为 159.1ms（MAD 3.0ms），与 before 163.5ms 同一量级；未用缓存伪造
启动收益。未渲染的 5000-entry fixture heap/RSS 增量从约 2.95/2.87MiB 增为
3.18/3.17MiB，来自每条 entry 的 cache metadata 槽位；渲染后 cache 的长期
驻留成本与回收行为由 Part D 单独测量。

### Part D — ten-hour deterministic stability run

入口 `scripts/goal11-stability.sh` 用 production faux provider、真实 agent/session
持久化路径、TUI event projection 与虚拟终端逐事件渲染，按每分钟两轮把 1200
轮解释为 10 小时交互量。它在 0/300/600/900/1200 轮强制 full GC，记录
heap/RSS、GC pause、FD 与 Lisp/OS thread；另生成至少 10MiB 的真实 v3 JSONL，
对 `load-session`、`resume-session`、`continue-session` 各自以 1ms sampler 记录
heap/RSS 峰值。完整 committed 数据见
[`benchmarks/goal-v11-stability.json`](benchmarks/goal-v11-stability.json)。

| stability metric | result |
|---|---:|
| faux turns / rendered agent events | 1200 / 14,400 |
| retained heap, turn 0 → 1200 | 35.86MiB → 78.17MiB; exponent 0.966 |
| full-GC pause, turn 0 → max | 52.0ms → 80.0ms |
| FD / Lisp threads / OS threads | 5 / 1 / 2 at every checkpoint and after cleanup |
| post-cleanup heap vs pre-run | -0.09MiB |
| JSONL size / entries | 10,507,435 bytes / 2400 |
| load / resume / continue latency | 328 / 268 / 276ms |
| sampled peak RSS above operation baseline | 99.8 / 98.7 / 98.5MiB |

增长来自仍被 agent、session、TUI cache 与 faux prompt cache 正常引用的 2400 条
message/entry，曲线为线性而非泄漏；释放整个场景后 heap、FD 与线程均回到基线。
GC pause 没有随 checkpoint 单调恶化。10MiB session 三条加载路径均低于 0.33s，
保留 heap 约 73.1MiB，未发现需改变可观察行为的稳定性缺陷。

场景审计反而发现 agent message 与 session entry 的内存 append 仍用 list `nconc`，
与 Part C 已修的 TUI 同属累计 O(N²)。固定 TS 基线分别用
`Agent.state.messages.push()`（`packages/agent/src/agent.ts:541`）和
`SessionManager.fileEntries.push()`（`packages/coding-agent/src/core/session-manager.ts:1044-1048`）。
因此沿用同一基线机制，为二者维护 private tail；公开 list 被整体替换后下一次
append 做一次安全修复。旧 object 上 agent append 的 exponent 为 0.994，N=20000
为 21.593µs；新实现 exponent -0.035，N=20000 为 0.110µs（196×）。session
append 受每条随机 ID 生成的约 0.1ms 固定成本主导，但 N=20000 仍从 135.394µs
降为 109.678µs；结构门禁直接锁定 cons tail 连接，避免计时噪声掩盖回归。

## Performance gates

`scripts/goal11-performance-gate.py` 对完整 performance/stability JSON 执行硬门禁。
阈值故意给 CI/机器差异留出数量级余量，但仍会击穿本 goal 的旧缺陷：N=5000
frame/key/stream/mouse/wheel 各不超过 50ms，frame/mouse/wheel allocation
不超过 16MiB，stream 至少 20 delta/s；连续 alternate-screen run 必须恰好
记录 1024 events、p99 不超过 150ms、GC-affected max 不超过 500ms，分配跨过
nursery 时必须实际观察到 GC；TUI/agent/session append exponent 小于 0.35、
冷启动不超过 750ms；
1200-turn heap 不超过 128MiB 且 exponent 不超过 1.30、full GC 不超过 500ms、
FD/thread 必须逐点恒定；10MiB load/resume/continue 各不超过 5s，sampled
heap/RSS 峰值各不超过 baseline 512MiB。

同机还对 mouse、wheel 与默认 GC 的五轮 1024-event trace 执行固定基线门禁：
对 median/p95/p99 的上限为
`max(2 × pi_q, pi_q + max(5ms, 6 × pi_run_MAD_q))`，max 只作诊断。
候选机名不是归档机 `Friend-MachineD` 时，该相对门禁明确报告
`informational-host-mismatch`；它不会拿另一台机器的绝对微秒数冒充可比数据。
原有 50/150/500ms 绝对预算仍跨机器运行，但同样受主机性能影响，不能称为
host-independent。

### Fifth A/B — continuous alternate-screen input

旧基准只测普通 frame、键盘和 stream delta；alt-screen 测试只断言滚动与选择
语义，没有连续鼠标事件的 wall latency、allocation 或 GC tail。因而所有功能
检查都能全绿，真实拖拽和滚轮仍可每帧重复扫描长 document 中每个 ANSI line，
这是门禁维度缺失，不是已有断言偶然漏了一个常量。

先量化得到的 pre-optimization 诊断在 N=5000、固定 8MiB nursery 下仅运行
8 events 就已足够明确：median 896.041ms、p99/max 932.060ms、median allocation
202,858,216 bytes/event，8/8 events 均跨 GC；默认 1024-event run 超过两分钟仍
未完成，主动中止，不能伪装成完整结果。

固定基线仍是 full document render + viewport slice + changed-row write，不允许
借机引入 virtual scrolling 或 transcript memoization。本次只消除 Lisp 热路径的
等价常数成本：稳定行不重复构造 reset/copy，scroll/selection 不强制 full clear，
`visible-width` 直接扫描原字符串且以性质测试对拍旧 grapheme 语义，image prefix
检测从每行两次通用 substring search 改为从 ESC 位置做同语义前缀判断。后者与
基线 `isImageLine` 的 fast/slow prefix 语义相同，但避免 SBCL generic `search`
在普通 ANSI line 上占掉大半帧。

最终 committed 1024-event run（HEAD `15bc6ae084d3…`）已完成：N=5000
mouse/wheel median 均为 36.001ms，allocation 2,832,352/3,668,816 bytes；
continuous median 36.001ms、p95 48.001ms、p99 52.001ms、max 68.002ms，
447 个 GC-affected events 的 max 为 68.002ms。相对 8-event 诊断，median
latency 降约 24.9×、
median allocation 降约 54×；默认规模现在能完整跑完并保留全部 1024 个原始
样本。cold start median 157.428ms（MAD 3.222ms），TUI append exponent
0.029。完整 JSON 为
[`benchmarks/goal-v11-final.json`](benchmarks/goal-v11-final.json)，SHA-256
`1d2d3d1faac43006e56b08a505487035c0d8a6dffdc0b52ab069a45c0d0d8f1e`。

### Goal 12 A0 — paired continuous-input baseline

旧 `14–18ms` 对照只驱动 `TuiMainScreen`，不能作为 alt-screen mouse/wheel
标尺。A0 改为两边都走 production raw-input handler 和 production render request，
并立即 flush 被请求的一帧；只排除共同的 16ms scheduler wait。固定条件为
100×40、N=5000、五个全新 fixture、每轮 1024 个完全相同的事件（342 drag、
341 wheel-up、341 wheel-down），trace SHA-256 为
`2dfea100e8e8825a96ea55795c39e6cea2f265c6aa1a4b98f4edba8b4e5edb61`。
基线路径证据为 `packages/tui/src/TuiAltScreen.ts:73-84,147-180,234-277,350-425`
与 `packages/tui/src/tui.ts:730-770`；cadr 路径为
`src/cadr-cli/interactive/controller.lisp:2050-2160` 和
`src/cadr-tui/renderer/lifecycle-input.lisp:619-642`。

Goal 14 B6 只移动 interactive forms；性能 harness 的兼容字段
`tui_object_id` 现在记录 `interactive/controller.lisp` 的 Git object，完整
呈现行为仍由 controller、frame、transcript 与 renderer 的确定性门禁共同锁定。

| paired N=5000 metric | pi `53fa77ccd` | cadr `82db71b8c` | cadr / pi |
|---|---:|---:|---:|
| mouse event→frame median | 276.150ms | 32.000ms | 0.12× |
| wheel event→frame median | 297.999ms | 36.000ms | 0.12× |
| continuous median | 315.576ms | 32.001ms | 0.10× |
| continuous p95 | 347.536ms | 40.001ms | 0.12× |
| continuous p99 | 365.552ms | 48.001ms | 0.13× |
| continuous max | 427.549ms | 68.002ms | 0.16× |

分配量不伪装成同一种 byte：cadr 的 SBCL `get-bytes-consed` 是精确分配计数，
continuous median 为 2,865,296 bytes/event；pi 的 V8 inspector sampled
allocation estimate 为 112,307,351 bytes/event，另测得 retained-heap delta
47,290 bytes/event、high-water delta 73,522 bytes/event。它们只证明两边都实际
采样分配，不用于 byte-for-byte 门禁。

结论：固定基线同样是 O(N) full document render → viewport slice → changed-row
write，而且此 synthetic N=5000 trace 比 cadr 慢 6.3–9.9×。cadr 的 32–48ms
主体延迟仍可被人感知，但不是相对基线新增的机制或数量级退化；继续加入 baseline
没有的 virtual scrolling/transcript memoization 反而违反项目原则。因此 A0 关闭，
保留既有 absolute stress gate，并新增上述同机 baseline-derived gate。候选完整数据为
[`benchmarks/goal-v12-a0-cadr.json`](benchmarks/goal-v12-a0-cadr.json)，SHA-256
`8f85b41714f142f721218009bf40524e0ff842c4c6c3d76dda486595ca05d414`。

## Goal 13 C3 — absolute interaction latency

### Real-session tiers

`scripts/goal13-session-scale-profile.py` reads the active branch of every local
JSONL session and emits aggregate counts only. It deliberately excludes file
names, session/entry IDs, cwd, timestamps, provider/model, and message content;
its fixture includes a secret marker and rejects any leak. Historical
`parentId:false` is handled as the production null/root representation instead
of silently discarding old sessions.

The 2026-08-02 profile contains 45/45 valid sessions and zero rejected files:

| percentile | min | p50 | p90 | p95 | p99 | max |
|---|---:|---:|---:|---:|---:|---:|
| projected TUI entries | 0 | 5 | 48 | 58 | 96 | 96 |

The tiers are therefore `typical=5`, `common=58`, `heavy=96`, and the retained
synthetic stress tier `5000`. The checked aggregate is
[`benchmarks/goal-v13-session-scale.json`](benchmarks/goal-v13-session-scale.json),
SHA-256 `95ce7f4a215e5d5e30f9cc8231958d522e912154fd8ffcbfba74f5316867a7b1`.
The release gate uses the checked aggregate, not the build machine's mutable
home directory.

### Bottleneck and optimization

Before C3, `render-tui-state` already reused stable entry render results, but
alternate-screen `prepare-alt-document` still stripped OSC-133 prefixes,
measured ANSI/grapheme width, and clipped every line on every mouse or wheel
event. The fresh pre-change run at `cd94d0b01` measured N=5000 continuous
median/p95/p99 `36.000/48.001/52.001ms` and 2,847,360 bytes/event. Its complete
samples are archived in
[`benchmarks/goal-v13-c3-before.json`](benchmarks/goal-v13-c3-before.json),
SHA-256 `06d7faeb91ad7164b1d4258d6c18d3b6f1469b9bcfc09d22989a413d88583066`.
Its five real-PTY cold-start samples were measured from an isolated image
built at that exact source revision; median 158.00ms, MAD 0.39ms.

The renderer now retains the immediately preceding raw line list, prepared
document, and width. A new frame reuses prepared strings for the maximal
identity-stable prefix and only performs OSC stripping, width measurement, and
clipping from the first dirty line onward
(`src/cadr-tui/renderer/lifecycle-input.lisp:13-16`;
`src/cadr-tui/renderer/alt-screen.lisp:3-57,123-124`). Width changes force
a full rebuild. The cache is one generation only, so it is bounded; the full
logical document remains available to viewport cropping, selection/copy, and
alternate-screen exit. This is memoized layout, not a presentation change.

The regression `GOAL13-ALT-SCREEN-REUSES-ONLY-THE-UNCHANGED-PREPARED-PREFIX`
proves exact equality with a forced full preparation, suffix invalidation, and
width invalidation. `GOAL13-ALT-SCREEN-PREPARED-CACHE-KEEPS-THE-FULL-DOCUMENT-CONTRACT`
proves exit restoration contains the updated complete document. Every existing
base-screen, overlay, payload, wire, and event gate remains byte-identical.

### Final measurements and gates

The committed implementation is `7da79c376`; renderer object
`6b56fa43686cd04e44fb84b5d1a2ccfb0f8495b8`. Each common trace contains 1024
separately timed production input→requested frame operations under the forced
8MiB nursery:

| tier / input | median | p95 | p99 | max | median allocation |
|---|---:|---:|---:|---:|---:|
| common N=58 mouse drag | <4ms timer quantum | 4.000ms | 4.001ms | 4.001ms | 180,552 B |
| common N=58 wheel | <4ms timer quantum | 4.000ms | 4.000ms | 4.001ms | 69,888 B |
| common N=58 editor key | <4ms timer quantum | 4.000ms | 4.001ms | 8.000ms | 1,124,488 B |
| stress N=5000 mixed | <4ms timer quantum | 4.000ms | 8.000ms | 12.000ms | 887,248 B |

The synthetic N=5000 p99 improved `52.001ms → 8.000ms` (6.5×) and median
allocation improved `2,847,360 → 887,248` bytes (3.2×). It now clears the 16ms
target even at 86× the real common tier; further virtual scrolling is not
needed to close this bottleneck. Cold start is 154.57ms (five real-PTY
samples, MAD 2.16ms) and the existing
1200-turn/10MiB stability budgets remain unchanged.

`scripts/goal11-performance-gate.py` now emits distinct failures:

- `absolute interaction target: common <kind> p99 exceeds 16ms` for any of the
  three common traces;
- `fixed baseline regression: ...` for the same-machine pi comparison.

It also requires `renderer_object_id`, exact 1024-sample traces, recomputed
quantiles/allocation/GC summaries, final selection/viewport/editor state, and
the privacy-safe scale profile contract. The final full artifact is
[`benchmarks/goal-v13-c3-final.json`](benchmarks/goal-v13-c3-final.json),
SHA-256 `96350ee3588e0143d745b1af2f0c295f542b5c6c0c31693b65710dcea0ed11f6`.
The checked artifact is replayed by the synthetic gate regression and by
`verify.sh`; a missing or null cold-start block now fails before release.

### Sustained mixed interaction tail

The original C3 gate timed isolated events and 1024-event bursts. That proves
ordinary event-to-frame latency, but it cannot detect a pause that appears only
after repeated drag selection, wheel input, and editing. The release benchmark
now adds a real-time 180-second trace at 60 events/second over the checked
`common=58` session tier: exactly 10,800 production input-to-requested-frame
operations, split evenly among drag, wheel-up, wheel-down, and editor
insert/backspace. The gate recomputes every tail statistic from the complete
sample vector and rejects a trace shorter than three minutes.

The 2026-08-03 run measured:

| measurement | result | gate |
|---|---:|---:|
| event-to-frame p99.9 | 8.000ms | ≤100ms |
| maximum event-to-frame pause | 20.001ms | ≤500ms |
| GC-affected events | 91 / 10,800 | reported |
| maximum GC-affected event latency | 20.001ms | reported |
| GC runtime-counter p99.9 / max | 15.491 / 15.491ms | recomputed |
| GC frequency | 30.33/min | recomputed |
| total GC runtime | 167.196ms | reported |
| retained heap after final full GC | +241,520 B | ≤8MiB |
| post-GC RSS | +581,632 B | ≤8MiB |

`sb-ext:*gc-run-time*` supplies the GC runtime-counter deltas; it is not
misrepresented as an independently sampled stop-the-world wall clock. The
corresponding user-observed wall latency is the complete
`gc_affected_samples_us` event-to-frame vector. Raw heap samples show the
normal nursery sawtooth: the last 30 seconds ended 19,924,288 bytes above their
first heap sample while RSS grew 2,097,152 bytes. A final full collection then
left only 241,520 retained heap bytes and 581,632 RSS bytes over the pre-trace
baseline, so the curve converges rather than accumulating per event.

`ContinuousInputGateTest.test_sustained_mixed_interaction_is_required_and_gated`
rejects a missing trace, a forged tail summary, short duration, threshold
breach, inconsistent GC accounting, or a claimed convergence that disagrees
with post-GC retained state. `verify.sh` runs this three-minute trace inside
its isolated Goal 11 performance stage on every release verification.

<!-- GOAL20_PERF_HISTORY_START -->

## Goal 20 self-history (script-written)

Produced by `scripts/write-performance-ledger.py` from
`docs/benchmarks/performance-history.json`. Do not edit the table
by hand.

Part A drift bands (adjudicated 2026-08-14, shape `max(floor, 6*MAD)`,
written by `scripts/goal20-part-a-noise-bands.py` to
`docs/benchmarks/goal20-part-a-noise-bands.json`, enforced by
`scripts/goal11-performance-gate.py` on machine `Friend-MachineD`):

- `cold_start.median_us`: informational — between-run 6*MAD (118794us) is 43% of the between-run median, above the 20% fail-close noise cap; the adjudication forbids widening the floor to keep it fail-closed
- `frame_render.5000.median_bytes`: fail-closed, band 4,096B (n=5, MAD=0.0)
- `frame_render.5000.median_us`: informational — reading is quantized at the 4000us timer step (observed sample set {0.0, 4000.0, 4001.0}); no band can be expressed until the measurement gains resolution

| recordedAt (UTC) | label | machine | git | cold start µs | N=5000 frame µs | N=5000 frame bytes |
|---|---|---|---|---:|---:|---:|
| 2026-08-13T13:40:38Z | verify-isolated | Friend-MachineD | `isolated-copy` | 267,505.9 | 3,987.0 | 360,272 |
| 2026-08-14T01:50:56Z | verify-isolated | Friend-MachineD | `isolated-copy` | 307,103.7 | 0.0 | 360,272 |
| 2026-08-14T04:11:37Z | verify-isolated | Friend-MachineD | `isolated-copy` | 291,287.2 | 0.0 | 360,272 |
| 2026-08-14T05:23:44Z | verify-isolated | Friend-MachineD | `isolated-copy` | 251,607.9 | 0.0 | 360,272 |
| 2026-08-14T06:39:45Z | verify-isolated | Friend-MachineD | `isolated-copy` | 257,222.4 | 0.0 | 360,272 |

Latest vs previous: `verify-isolated` (2026-08-14T06:39:45Z) versus `verify-isolated` (2026-08-14T05:23:44Z).

<!-- GOAL20_PERF_HISTORY_END -->
