# Performance and stability

非功能属性是与行为 parity 并列的第二根验收轴：行为门禁回答“产出了什么”，
本文回答“产出它花了多少时间、分配和常驻资源”。所有优化仍须通过既有
payload、会话、完整文案和虚拟终端逐字门禁。

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
没有真实 LLM、网络或随机输入。四条热路径分别测量：

- `frame_render`：production `render-tui-state → render-frame → virtual-terminal`；
- `key_to_frame`：原始输入字节经 input decoder/editor 后写出一帧；
- `stream_delta_to_frame`：固定 text delta 经 agent event 组装后写出一帧，
  同时报告 delta/s；
- `append_entry`：在固定长度历史尾部追加一个条目并 O(1) 恢复 fixture。

分配量来自 `sb-ext:get-bytes-consed`；堆占用来自
`sb-kernel:dynamic-usage`；Linux RSS 来自 `/proc/self/statm`。冷启动由独立
Python stdlib PTY harness 在全新临时 `HOME`、无 provider 凭据环境中启动
native `./cadr`，从 `Popen` 到首帧出现 `cadr v` 为止计时，再用 `/quit`
验证干净退出。它是“新进程到首个真实 TUI 帧”，不是较弱的 `--version`
路径，也不通过 drop caches 取得不可移植的伪冷磁盘数字。

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

审计对象固定为 `74caa2649`，不是持续移动的上游 `main`。结论很明确：pi
同样每帧遍历完整组件树，并没有 viewport-before-render、虚拟滚动或持久化的
历史前缀帧；它的优势来自组件级缓存、O(1) 追加、render request 合并，以及
只向终端写变化行。

| dimension | baseline behavior and evidence |
|---|---|
| history append | `Container.children` 是数组，`addChild()` 直接 `push`，即 O(1)；`packages/tui/src/tui.ts:211-216`。interactive mode 只把新 message/tool component 加到 `chatContainer`；`packages/coding-agent/src/modes/interactive/interactive-mode.ts:2942-2962, 3318-3369`。 |
| per-component cache | `Markdown` 以 source text + width 缓存完整 rendered lines，变更时显式失效；`packages/tui/src/components/markdown.ts:121-169, 239-244`。`Text` 使用同一策略；`packages/tui/src/components/text.ts:13-57, 99-104`。bash 折叠预览另有 width-aware cache；`packages/coding-agent/src/modes/interactive/components/bash-execution.ts:148-166`。 |
| streaming invalidation | 每个 delta 只重建当前 `AssistantMessageComponent`，稳定历史 component 不变，然后请求一帧；`packages/coding-agent/src/modes/interactive/interactive-mode.ts:2966-2998`。component 本身在内容变化时重建子树；`packages/coding-agent/src/modes/interactive/components/assistant-message.ts:89-170`。 |
| full traversal | `Container.render()` 每帧遍历每个 child 并拼接其 lines；`packages/tui/src/tui.ts:235-244`。main-screen 明确先 `render(width)` 全部 component；`packages/tui/src/TuiMainScreen.ts:146-173`。因此稳定帧仍是 O(N)，缓存只压低每项常数。 |
| viewport/virtual scroll | alt-screen 先渲染完整 document，之后才以 `scrollTop` slice viewport；`packages/tui/src/TuiAltScreen.ts:350-371`。没有 render 前裁剪或虚拟滚动。 |
| differential write | main-screen 扫描新旧全部 lines 找变化区间，再只写变化 lines；`packages/tui/src/TuiMainScreen.ts:260-287, 354-386`。alt-screen 同样只写变化 row；`packages/tui/src/TuiAltScreen.ts:398-425`。这减少终端 I/O，不消除前面的 O(N) render traversal。 |
| render coalescing | 重复 request 合并，并以 16ms 最小间隔调度；`packages/tui/src/tui.ts:321, 730-770`。 |

所以 Part C 只采用基线已有的两种机制：给稳定条目加入 width/content-sensitive
rendered-line cache，并把 Lisp list 尾插改为维护尾指针的 O(1) 追加。不会加入
整段 transcript memoization、viewport pruning 或虚拟滚动；这些都超出基线，
按全局原则必须另交提案。

### Same-machine structural comparison

对照入口：

```sh
node --expose-gc scripts/goal11-pi-baseline-bench.mjs \
  /tmp/cadr-parity-74caa2649 \
  > /tmp/cadr-goal11-pi-baseline.json
```

脚本拒绝任何不是 `74caa2649f10…` 的 worktree，直接加载该 object 已构建的
production `TuiMainScreen`、`Editor`、user/assistant、read tool 与 bash tool
component。每条历史都是独立 production component；100×40、同样 N 梯度、
固定五项混合、1 次 warm-up、5 次样本，fixture 构建不计时。完整数据见
[`benchmarks/goal-v11-pi-baseline.json`](benchmarks/goal-v11-pi-baseline.json)。

| metric at N=5000 | cadr before | pi `74caa2649` | ratio |
|---|---:|---:|---:|
| frame | 488.0ms | 14.46ms | 33.7× |
| key→frame | 480.0ms | 15.06ms | 31.9× |
| stream delta→frame | 466.0ms | 17.94ms | 26.0× |
| append | 5.200µs, linear | 0.0136µs, constant | 382× at N=5000 |

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
  `src/cadr-cli/tui.lisp:3-24, 506-514, 1806-1975`。
- `tui-state` 保存 list tail 与其所属 head；正常追加直接接到 tail。集中替换
  入口同步重建 tail，历史测试/fixture 若直接 `setf entries`，下一次追加只做
  一次自修复且不会污染旧链。实现位于
  `src/cadr-cli/tui.lisp:21-39, 470-504`，两个 production reset 已改走集中入口
  （`:1119, :3980`）。

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
frame/key/stream 各不超过 50ms、frame allocation 不超过 16MiB、stream 至少
20 delta/s、TUI/agent/session append exponent 小于 0.35、冷启动不超过 750ms；
1200-turn heap 不超过 128MiB 且 exponent 不超过 1.30、full GC 不超过 500ms、
FD/thread 必须逐点恒定；10MiB load/resume/continue 各不超过 5s，sampled
heap/RSS 峰值各不超过 baseline 512MiB。

当前最终 performance JSON 见
[`benchmarks/goal-v11-final.json`](benchmarks/goal-v11-final.json)：N=5000
frame/key/stream 均为 4.00ms，TUI append exponent -0.047，冷启动 165.2ms。
这些阈值分别约为当前时延的 12.5×、吞吐下限的 12.5×反向留白，以及加载时延
的 15×以上；它们容纳常规主机差异，但旧 466–488ms frame、2.15 delta/s 与
linear append 会确定性失败。
