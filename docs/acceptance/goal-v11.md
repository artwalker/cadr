# Goal 11 acceptance ledger

## Part A — deterministic measurement infrastructure

状态：完成。基准实现提交 `6ee7d84f3`；生产性能路径未改动。

新增一键 JSON 基准 `scripts/bench.sh`，实现位于
`scripts/goal11-bench.lisp`，真实 TUI 冷启动由
`scripts/goal11-cold-start.py` 测量。覆盖固定混合会话的单帧耗时/分配、
按键到帧、流式 delta 到帧、追加成本、SBCL heap、RSS 与首帧冷启动；默认
N 梯度、样本数、median/MAD 和原始样本均写入 JSON。

机械验证：

```text
bash -n scripts/bench.sh
python3 -m py_compile scripts/goal11-cold-start.py
python3 scripts/goal11-cold-start.py /root/projects/cadr/cadr
  251420.906
./scripts/bench.sh --quick --samples 1 --warmups 1 \
  --output /tmp/cadr-goal11-quick.json
  exit 0; N=0/50/200 全部四条路径完成
./scripts/bench.sh --label before-optimization \
  --output /tmp/cadr-goal11-before.json
  exit 0; N=0/50/200/1000/5000 全部四条路径完成
jq . /tmp/cadr-goal11-before.json
  exit 0
```

归档基线为
[`docs/benchmarks/goal-v11-before.json`](../benchmarks/goal-v11-before.json)，
摘要与方法见 [`docs/performance.md`](../performance.md)。决定性结果：5000
条目下 frame 488.0ms、key→frame 480.0ms、stream 466.0ms / 2.15 delta/s，
三者均为线性；append 从 N=0 的 0.024µs 增至 N=5000 的 5.200µs，斜率
0.910，确认累计 O(N²)；真实 PTY 首帧 median 163.5ms、MAD 4.5ms。

Part A 没有使用真实 LLM、凭据、随机 fixture、输入改写或弱断言。完整 JSON
记录 HEAD 与 TUI object ID，后续优化结果必须由同一脚本、同一机器、同一
参数生成。

## Part B — fixed-baseline long-session strategy

状态：完成。审计对象固定为 `74caa2649f10…`。

逐项结论与源码证据已写入
[`docs/performance.md`](../performance.md#fixed-ts-baseline-strategy)：pi 没有
viewport-before-render、虚拟滚动或增量历史前缀帧；每帧仍遍历完整 component
tree，main/alt screen 都是在全量 render 之后才做 diff 或 viewport slice。
pi 的已验证策略是：稳定 `Markdown`/`Text`/bash preview 按内容与宽度缓存、
chat child 以数组 `push` O(1) 追加、只重建当前 streaming component、16ms
render request 合并、只写变化行。

由此冻结 Part C 实现边界：只移植 per-entry width/content cache 与 O(1) tail
append；不新增 transcript memoization、viewport pruning 或 virtual scrolling。
这是 component-level memoization + differential rendering，不是新的 UI 架构。

同机结构对照由 `scripts/goal11-pi-baseline-bench.mjs` 直接加载 fixed worktree 的
production dist 执行，JSON 归档于
[`docs/benchmarks/goal-v11-pi-baseline.json`](../benchmarks/goal-v11-pi-baseline.json)。
N=5000 时 pi frame/key/stream 分别为 14.46/15.06/17.94ms，均保持线性；append
为 0.0136µs 且判定 constant。cadr 优化前对应值为 488.0/480.0/466.0ms 与
5.200µs linear。绝对倍率受 cadr virtual terminal 与 pi mock terminal 的末端
差异影响，报告未把它伪装成 runtime-identical 对拍；策略/复杂度证据不受该
限制。

机械验证：

```text
node --check scripts/goal11-pi-baseline-bench.mjs
  exit 0
node --expose-gc scripts/goal11-pi-baseline-bench.mjs \
  /tmp/cadr-parity-74caa2649 \
  > /tmp/cadr-goal11-pi-baseline.json
  exit 0; N=0/50/200/1000/5000 全部四条路径完成
sha256sum /tmp/cadr-goal11-pi-baseline.json \
  docs/benchmarks/goal-v11-pi-baseline.json
  f2240d4d56aba32582a33d0a055713649622e572861958808d51f8c1eb16a906（两者一致）
```

Part B 未修改 production code。
