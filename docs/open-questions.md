# Open Questions

本文件只记录相对固定 TS 基线拟新增的机制。未获人工明确裁决前，条目不得
进入实现。

当前无待裁决项。

已裁决、尚受执行顺序门禁：

- `OQ-G10-D1-TOOL-RESTARTS`：2026-08-01 已批准工具失败现场的
  condition/restart 与第 34 个扩展事件 `:tool-call-error`；实现后以
  34 个事件重新冻结，今后新增仍须重新提案并逐项裁决；
- `OQ-G10-D2-SLYNK-REPL`：2026-08-01 已分别批准默认关闭、
  loopback-only 的 Slynk 运行时 REPL 及精确锁定的第三方依赖闭包；
- 两项实现均须等待 Goal 10 Part B 完成 `v0.84.0` 对齐，不得提前开工。

完整边界、依赖锁与裁决记录见
[`docs/proposals/goal-v10-part-d-lisp-native-capabilities.md`](proposals/goal-v10-part-d-lisp-native-capabilities.md)。

`OQ-G9-LIVE-GATE` 已由用户逐项批准并实施，裁决与证据归档于
[`docs/proposals/goal-v9-live-test-gating.md`](proposals/goal-v9-live-test-gating.md)。
