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
