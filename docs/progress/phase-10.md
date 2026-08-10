# Phase 10 progress — goal 18 验收汇总（2026-08-10）

Goal 18 对齐 pi v0.84.1 的前置部分（Part A–K）已完成；Part L（基线升级）
按规约排在最后，其执行所需的三组裁决见文末「待裁决」。

## 完成面

| Part | 状态 | 关键证据 |
|---|---|---|
| A 登录取消死锁 | 完成 | `cda918e56` 取消链贯通；`ab50abf48` 八形态；`goal18-login-cancel-test.lisp` 状态机回归；归属结论（早于 74fe2c0b8，非 goal 17 回归）入 CHANGELOG |
| B agent 层与迁移 | 完成 | `~/.cadr/agent/` 九住户 + crash/；`CADR_CODING_AGENT_DIR`；迁移四项测试 |
| C 路径 owner 收敛 | 完成 | `".cadr/"` 字面量 grep 检查已并入组织门禁 |
| D tools/ 与 debug.log | 完成 | config.ts 行记录：getToolsDir 为死代码不实现；debug log 由 `/debug` 实现 |
| E 有意差异复核 | 完成 | `docs/goal18-part-e-audit.md`（77 行） |
| F 包边界映射 | 完成 | §1a 逐行抽查与代码一致 |
| G 卫生项 | 大部完成 | `.tmp/` 清理与工具链切换按 G4/G5 留到 goal 收尾（须与用户协调时机） |
| H 启动资源区块 | 完成 | `startup-resources` 场景双态对拍 |
| I 门禁结构缺口 | 完成（除 10 豁免待裁决） | I1 sweep 中间态、I2 派生（登录形态/扩展事件/标签地板）、I4 账本数字机器对账、I5 缓存内容校验、I6 发版门禁、I7 键位+sink 拓宽、I7.3 反向扫描、I8 llama UI |
| J 用户文档 | 完成 | 12 份文档 + 引用完整性 FiveAM 门禁；`/usr/local` 假路径缺陷修复 |
| K 工具定义对拍 | 完成 | 七工具描述+schema+snippet 由基线机械派生 fixture 锁定 |

本轮新增的真实能力补齐（I7 尾巴）：启动内容迁移全量移植、
`--list-models` 基线表格、扩展加载失败致命化（reportDiagnostics +
`-ne` 提示）、快捷键冲突语义、提示词/@file 错误归一化、62 条键位
legacy 名迁移。

## 门禁证据

- `./scripts/test-cl.sh`：**15699/15699**（9 系统）。
- `./scripts/verify.sh`：20 个确定性阶段 + live 阶段全 PASS
  （verify14，含新增的 baseline anchor consistency 阶段）。
- 全量 render 门禁（干净检出复跑）：90/90 捕获、466 条裁定全部吻合；
  仅在 10 个待裁决豁免分支上红灯。
- `./scripts/verify-release.sh`：按 I6 设计在 live 未验证/全量红灯时
  不给成功退出码——当前因 10 豁免待裁决而失败，属待裁决状态。
- 二进制新鲜度：PASS。

## 待裁决（Part L 执行的前置）

1. **10 个豁免分支** + 新 `unreachable-in-harness` obstacleKind：
   `docs/proposals/goal18-i7-tail-exemptions.md`。
2. **Mermaid 路线**：`docs/proposals/goal18-l1a-mermaid.md`
   （建议路线 1：纯 Lisp 移植 grok-mermaid + 逐字节差分金样）。
3. **9 项既有挂起**（--resume 扩展、npm 包、update --models、telemetry、
   -r 选择器、sentinel 模型、帮助开关、pi-mono URL、keybindings.json）。
4. **I05 退出残影类**（或修 cadr 拆除路径）：
   `docs/goal18-l5-attribution.md` 末节，L5.2 探针补丁已验证可重现并
   回退待裁。

## Part L 已就位的前置

- L2.1 锚点单一化：`BASELINE` 文件唯一 owner；一致性门禁在 verify.sh；
  `set-baseline.sh` 已向 v0.84.1 端到端预演通过（含精确打 tag 的 +0）。
- L1 机械枚举：`scripts/enumerate-baseline-diff.py`；v0.84.1 差集结果与
  完备性论证在 `docs/source-parity-upgrade.md`（含对手工清单四处遗漏的
  纠正：`--alt` 移除、四个 PI_*/RADIUS 环境变量移除、STY/ZELLIJ、
  CredentialPrintError 改名）。
- L5.1 归因表：`docs/goal18-l5-attribution.md`。
