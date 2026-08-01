# Open Questions

本文件只记录相对固定 TS 基线拟新增的机制。未获人工明确裁决前，条目不得
进入实现。

## OQ-G9-LIVE-GATE：live 测试的门禁定位

状态：**blocked，等待用户裁决。**

Goal 9 的真实 LLM 测试目前混入确定性 FiveAM 全量入口；模型行为波动会令后续
确定性 suite 被提前截断，并使“连续全绿”失去可重复含义。是否新增独立 live 入口、
其失败如何影响 `verify.sh`/发布，以及永久证据口径，见
[`docs/proposals/goal-v9-live-test-gating.md`](proposals/goal-v9-live-test-gating.md)。

获批前不得移动任何 live 测试或改变退出语义。
