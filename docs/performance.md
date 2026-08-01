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

## Baseline strategy, optimized results, and gates

Goal 11 Parts B–E 完成时在此追加 TS 基线 `file:line` 证据、优化前后同机
对比、长时稳定性结果和发布门禁阈值。Part A 期间未修改任何性能相关生产
代码。
