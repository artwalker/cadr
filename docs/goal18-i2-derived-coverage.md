# Goal 18 I2/I7 派生覆盖差集报告（2026-08-10）

本报告是 goal18.md I2 第 3 条要求的「派生要求 − 现有场景」机器答案。
每个类别的**集合**都从固定基线（53fa77ccd）机械派生；门禁 fail-closed：
派生集合漂移、映射缺失、注册表陈旧任一发生即失败。

## 已机械派生并对账闭合的类别

| 类别 | 派生源 | 规模 | 对账方式 | 差集 |
|---|---|---|---:|---|
| slash 命令 | `core/slash-commands.ts` 注册表（git 提取） | 22 | `reachable-interfaces.json` 注册表逐条有 capture，门禁核对顺序与成员 | 空 |
| 界面构造器与构造点 | `new *Component(` 全量扫描（git 提取） | 15 构造器 / 22 站点 | `baseline-interface-inventory.json` 字段与 git 重提取比对 | 空 |
| 登录对话框形态 | `login-dialog.ts` 的 `show*` 公开方法（git 提取，I2 新增） | 8 | `loginDialogCoverage` 映射：5 个经差分场景检查点，3 个（showDetails/showInfo/showPrompt，无登录流在 harness 可达）经 construction 逐字节驱动 | 空 |
| 扩展事件 | `types.ts` `ExtensionEvent` 联合展开（git 提取，I2 新增） | 33 叶子事件 | FiveAM 断言 cadr 集合 = 派生集合 + 已裁决拆分（`tool_call`/`tool_result` → before/after/error） | 空 |
| 可见字符串分支 | 246 源文件 × 已建模 sink 提取（既有，71 个产出条目） | 508 sites / 1117 分支条目；其中 printable 义务 479 sites / 787 分支 | 逐分支捕获或结构化豁免 | 空（10 分支已裁决豁免，见下） |
| 未建模 sink 候选 | 反向清点：全部 console/process-write/show*/print* 调用中带固定文本且不落任何清单站点者（I7.3 新增） | 14 | `visible-string-unmodeled-review.json` 逐条 verdict + reason，门禁对账 | 空 |

## 差集的豁免闭合：10 分支已裁决（USER-2026-08-10-001）

A 类防御性回退 5（`main.ts:150/211/633`、`package-manager-cli.ts:733/870`）、
B 类权限依赖失败臂 4（`migrations.ts:148`、`file-processor.ts:80`）、C 类
Android 1（`tools-manager.ts:349`），逐条审计依据见
`docs/proposals/goal18-i7-tail-exemptions.md`。2026-08-10 用户已裁决
（`userDecisionId: USER-2026-08-10-001`，落账提交 `b435ef522`）：A 类 5 分支
以 `unreachable-in-baseline`、B 类 4 分支以新增的 `unreachable-in-harness`
、C 类 1 分支以既有 `unavailable-operating-system` 全部入豁免注册表
（`test/fixtures/render-diff/visible-string-exemptions.json` schema 3，每条
附 `baselineEvidence` 与 probe）。注册表 fail-closed 语义不变：未知、陈旧、
重复或已有真实捕获的豁免条目仍会使门禁失败；该 10 分支不再属于未闭合项。

## 选择不机械派生的类别及理由（交裁决）

1. **状态条件渲染点**（`addLoadedSection(...)`、`if (xs.length)` 一类）：
   派生可得站点清单，但"每站点须有空/非空双态场景"的义务无法机械绑定到
   具体场景状态——某状态可否在 harness 构造、由哪个场景提供，需要语义
   判断。现行机制：I3 双态规则写入 `docs/render-diff.md`（新增场景的强制
   规则）+ 启动资源六区块的空/非空双场景已在位。**若裁决要求更严，需
   为每个渲染条件点维护人工映射表（又回到手工清单），或接受现状。**
2. **状态迁移检查点**：I1 已把遍历型场景的滚动位/选中态/切换前后列入
   显式检查点；"每个动作后是否应设检查点"无机械判据（动作数 × 检查点
   会爆炸性放大捕获量而无线性收益）。现行规则：遍历型场景必须在被遍历
   的关键状态上设点（写入 render-diff 文档）。

## 手工清单的现状

`REQUIRED_COVERAGE` 仍是手工集合，但已改为**当前声明全集**（138 个覆盖
标签）：任何场景或标签被删除即失败，覆盖不可回退。它与派生集合的关系：
派生集合管"基线有什么"，手工全集管"场景声称覆盖什么"，两者都由门禁
对账。

## 已知覆盖形态说明：启动弃用警告块

`migrations.ts` 的弃用目录警告（hooks//tools/ 提示 + 文档 URL + "Press any
key to continue..." 暂停）只在基线 `main.ts` 的交互路径发出；render-diff
的 TUI 场景经 driver 直接构造 InteractiveMode，不经 main()，因此该块目前
由 construction 驱动（基线侧逐字节）+ cadr 侧 FiveAM
（`goal18-deprecation-warnings-match-the-baseline-text`，含按键等待与完整
文案）覆盖，无双侧场景。要补双侧对拍需一个"注册 faux 后走完整 main()"
的新 driver 入口——收益与驱动复杂度不称，记录在案。
