# Open Questions

本文件只记录相对固定 TS 基线拟新增的机制。未获人工明确裁决前，条目不得
进入实现。

当前待裁决：

- `OQ-G10-D1-TOOL-RESTARTS`：工具失败现场的 condition/restart 与
  `:tool-call-error` 扩展 hook；
- `OQ-G10-D2-SLYNK-REPL`：默认关闭、loopback-only 的 Slynk 运行时
  REPL，包含新第三方依赖的独立授权。

完整边界与裁决项见
[`docs/proposals/goal-v10-part-d-lisp-native-capabilities.md`](proposals/goal-v10-part-d-lisp-native-capabilities.md)。

`OQ-G9-LIVE-GATE` 已由用户逐项批准并实施，裁决与证据归档于
[`docs/proposals/goal-v9-live-test-gating.md`](proposals/goal-v9-live-test-gating.md)。
