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

## Part C — long-session rendering and append complexity

状态：完成。实现提交 `56a50ca9c`。

测试先行证据：新增 cache 测试在实现前稳定失败为 4 pass / 1 fail，失败点是
相同 width/theme 的第二次 render 未复用首个 line list；实现后本 Part 四项
回归为 20/20。源码位置与测试名：

| requirement | production source | regression test |
|---|---|---|
| stable per-entry rendered-line cache; width/theme invalidation | `src/cadr-cli/tui.lisp:3-24, 1806-1975` | `GOAL11-STABLE-ENTRY-RENDER-CACHE-MATCHES-BASELINE-INVALIDATION` |
| streaming bypass; completed tool cache; expand invalidation | `src/cadr-cli/tui.lisp:506-514, 1519-1529, 1920-1975, 2323-2333` | `GOAL11-STREAMING-AND-TOOL-MUTATIONS-INVALIDATE-ENTRY-RENDER-CACHE` |
| O(1) tail append and safe direct-SETF recovery | `src/cadr-cli/tui.lisp:21-39, 470-504, 1119, 3980` | `GOAL11-TUI-ENTRY-APPEND-MAINTAINS-O1-TAIL-INVARIANT` |
| mixed user/assistant/tool/notice transcript bytes unchanged | `src/cadr-cli/tui.lisp:1806-2000` | `GOAL11-CACHED-MIXED-TRANSCRIPT-IS-BYTE-IDENTICAL` |

完整性能归档：
[`docs/benchmarks/goal-v11-after-part-c.json`](../benchmarks/goal-v11-after-part-c.json)，
SHA-256 `4d6accbe834b5b6a8aa198b6a8aab178deae21b4c443dd480062276285b93f9a`。
N=5000 的 frame/key/stream 从 488.01/480.01/466.01ms 降至全部 4.00ms；
frame allocation 从 139.58MB 降至 0.72MB；stream throughput 从 2.15 升至
250 delta/s。append 从 5.200µs linear 降为 0.020µs constant。详细方法、
倍率与内存代价见 [`docs/performance.md`](../performance.md#part-c--baseline-mechanisms-restored)。

机械验证：

```text
四项 Goal 11 targeted regressions
  20 checks / 20 pass / 0 skip / 0 fail
./scripts/test-cl.sh
  7110 checks / 7110 pass / 0 skip / 0 fail
./build.sh
  exit 0; SBCL 2.6.7 无 sb-core-compression，按既定契约降级为无压缩 image
./scripts/bench.sh --label after-part-c \
  --output /tmp/cadr-goal11-after-part-c-committed.json
  exit 0; N=0/50/200/1000/5000 全部四条路径与真实 PTY 冷启动完成
sha256sum /tmp/cadr-goal11-after-part-c-committed.json \
  docs/benchmarks/goal-v11-after-part-c.json
  4d6accbe834b5b6a8aa198b6a8aab178deae21b4c443dd480062276285b93f9a（两者一致）
```

未加入 transcript memoization、viewport pruning 或 virtual scrolling；输出
语义无变更。

## Part D — long-run stability and large sessions

状态：完成。实现提交 `ec5834ec2`。

新增 `scripts/goal11-stability.sh` / `scripts/goal11-stability.lisp`，以 production
faux provider 驱动 1200 轮真实 agent/session/TUI event path 并渲染 14,400 帧，
相当于每分钟两轮下 10 小时交互。五个 checkpoint 的 FD/Lisp thread/OS thread
始终为 5/1/2；retained heap 从 35.86MiB 线性增长到 78.17MiB（exponent
0.966），full GC 最大 80.0ms；释放场景后 heap 回到 35.77MiB，未发现泄漏或
资源残留。

真实 10,507,435-byte / 2400-entry JSONL 的 load/resume/continue 分别为
328/268/276ms，1ms sampler 记录的 RSS 峰值约 168MiB，三次操作后保留 heap
约 73MiB。报告没有把 retained conversation state 误报为 leak，也没有把 sampled
peak 冒充精确瞬时上界。

场景发现 agent messages 与 session entries 的 append 仍线性遍历。固定基线
分别用 array `push`，故以同一 private-tail 机制修复；不改变 public list、session
bytes、事件或 TUI 输出。源码位置与回归测试：

| requirement | production source | regression test |
|---|---|---|
| agent message O(1) append and whole-list replacement recovery | `src/cadr-agent/runtime.lisp:23-31`, `src/cadr-agent/tool.lisp:74-116`, `src/cadr-agent/loop.lisp:127-166` | `GOAL11-AGENT-MESSAGE-APPEND-MAINTAINS-O1-TAIL-INVARIANT` |
| session entry O(1) append and loaded-session tail restoration | `src/cadr-agent/session.lisp:34-50, 802-890, 1860-1880` | `GOAL11-SESSION-APPEND-MAINTAINS-O1-TAIL-INVARIANT` |

测试先行红证据为 cadr-agent suite 625 checks / 623 pass / 2 fail，两个失败均为
新增 tail accessor 尚不存在；实现后该 suite 635/635。旧 object 的 agent append
在 N=20000 为 21.593µs、exponent 0.994；新 object 为 0.110µs、exponent
-0.035。session 的随机 ID 固定成本掩盖 slope，但 N=20000 从 135.394µs 降至
109.678µs，cons-tail identity 测试直接锁定复杂度机制。

完整机器可读结果：
[`docs/benchmarks/goal-v11-stability.json`](../benchmarks/goal-v11-stability.json)。
门禁脚本对 committed performance/stability JSON 输出 `goal11 gate: PASS`。

机械验证：

```text
./scripts/test-cl.sh
  exit 0; all deterministic systems green
./build.sh
  exit 0; unsupported sb-core-compression correctly falls back to uncompressed image
./scripts/goal11-stability.sh --label after-goal11 \
  --output /tmp/cadr-goal11-stability-final.json
  exit 0; 1200 turns, 10.0 simulated hours, 10,507,435-byte JSONL
python3 scripts/goal11-performance-gate.py \
  --bench /tmp/cadr-goal11-bench-final.json \
  --stability /tmp/cadr-goal11-stability-final.json
  PASS: frame/key/stream 4.00ms; heap exponent 0.966; GC max 80.0ms
```
