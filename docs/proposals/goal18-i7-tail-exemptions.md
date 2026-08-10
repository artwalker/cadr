# Goal 18 I7 收尾：十个基线分支的覆盖豁免提案（待裁决）

状态：**待用户裁决。** 本提案只申请豁免判定，不改任何产品行为。

## 背景

goal18.md I7 要求基线可见字符串清单的每个 printable 分支被捕获或显式豁免。
本轮把未捕获分支从 59 个降到 10 个：49 个经真实修复加差分场景或构造驱动
落账（迁移输出、`--list-models` 表格与 models.json 告警、扩展加载失败的
`-ne` 提示、快捷键冲突诊断、提示词文件告警、pnpm 与 Update note 等），其余
10 个分支经逐个源码核查确认在本项目门禁环境下**不可确定性驱动**，申请
豁免。

豁免机制：`test/fixtures/render-diff/visible-string-exemptions.json`（schema
3，fail-closed：未知、陈旧、重复或已有真实捕获的豁免条目都会使门禁失败）。
现有 `obstacleKind` 枚举不含"防御性回退/权限依赖失败臂"，**需新增一个
kind**（建议 `unreachable-in-harness`），这本身也在本次裁决范围内。

## A 类：防御性回退分支（非 Error 抛值才触达，用户输入不可达）——5 分支

逐处审计结论：这些 `error.message || "<fallback>"` 分支只在抛出**非 Error
对象**时触达；基线自身所有抛点均为带 message 的 Error。

| 分支 | 位置 | 审计依据 |
|---|---|---|
| `B-fd13d93a29bf` | `main.ts:141` "Failed to parse auth command" | `credential-print.ts` 全部 12 个抛点均为 `CredentialPrintError`（:38,51,56,68,71,74,99,111,140,143,145,149）；`parseArgs` 只记录 diagnostics 不抛 |
| `B-3f0215f4a9d2` | `main.ts:163` "Failed to resolve credential" | `resolveCredentialForPrint` 只抛 `CredentialPrintError`；`ModelRuntime.create({allowModelNetwork:false})` 的 models.json 加载错误经 `model-config.ts:251,261,271` 以返回值传达而非抛出 |
| `B-fa0be7fade22` | `main.ts:585` "Failed to export session" | `exportFromFile` 全部抛点带 message（`export-html/index.ts:245,248,293`） |
| `B-85d3c79ec77b` | `package-manager-cli.ts:731` "Unknown model catalog refresh error" | `refreshModelCatalogs` 的网络与解析失败均带 message |
| `B-c5a60ab5ff3b` | `package-manager-cli.ts:868` "Unknown package command error" | 两处 catch-all 包裹的操作失败均带 message |

cadr 侧对应路径已实现同形回退文案（非凭据错误走各自 fallback 消息）。

## B 类：权限依赖失败臂（root 下不可确定性触达）——4 分支

| 分支 | 位置 | 说明 |
|---|---|---|
| `B-d987d23f73bb` `B-4b479e0533e6` | `migrations.ts:148` "Warning: Could not migrate … to prompts/: " | 需 `rename(2)` 失败（EACCES）；门禁以 root 运行，权限位不生效；tsx 经 ESM 链接加载基线，`fs` 打补丁不可达（已实测）；setuid 子进程方案因插桩树为 0700 临时目录而不可读 |
| `B-a329842f84c5` `B-c1b8a22b174c` | `file-processor.ts:80` "Error: Could not read file " | 同上（需 `readFile` EACCES）；目录情形在基线先于 mime 检测崩溃（未捕获异常），cadr 按 P0-1 既定规则归一化为该文案并配 FiveAM |

cadr 侧：迁移失败臂经 `*migration-rename-function*` 注入缝配 FiveAM
（`goal18-commands-directories-migrate-to-prompts` 的失败断言）；@file 目录
情形有 FiveAM 锁定
（`goal18-file-argument-directory-is-a-normalized-error`）。

## C 类：操作系统不可用——1 分支

| 分支 | 位置 | 说明 |
|---|---|---|
| `B-6e91fc06717b` | `tools-manager.ts:347` "not found. Install with: pkg install " | 仅 `platform() === "android"`（Termux）触达；适用既有 `unavailable-operating-system` kind |

## 随本案一并请求裁决的既有挂起项

以下条目在此前批次已标记待裁决，现一并列出（详见验收报告）：

1. `--resume <id>`（cadr 扩展：基线仅有选择器形态）。
2. npm 包安装源在 cadr 不可用，而 `--help` 按基线展示 npm 包示例。
3. `update --models`：基线联网刷新模型目录；cadr 模型目录随二进制内置。
4. Telemetry：基线向 pi.dev 发安装上报；cadr 无此出口。
5. `-r` 无参时的 pre-TUI 会话选择器（startup-ui.ts）；cadr 直接恢复最新。
6. 裸环境 TUI 的 sentinel 模型态 vs cadr 的 openai 兜底。
7. cadr 自有开关（`--slynk`、`--no-tui`）从 --help 移除以逐字对齐基线。
8. （新）弃用目录警告中的两个基线文档 URL（github.com/earendil-works/
   pi-mono）：保留逐字（输出对齐）还是替换（cadr 尚无等价页面）。
9. （新）键位存储：基线读 `keybindings.json` 文件；cadr 读 settings.json
   的 `keybindings` 键。是否补 keybindings.json 支持或记为有意差异。

## 裁决后的落账动作

用户批准后：A/B 类 9 分支以新 kind（`unreachable-in-harness`）入豁免注册表，
C 类 1 分支以 `unavailable-operating-system` 入册，每条附
`userDecisionId`、`baselineEvidence` 与 probe；全量门禁转绿。
