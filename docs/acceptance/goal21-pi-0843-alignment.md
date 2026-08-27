# Goal 21：pi 基线推进至 v0.84.3（Goal 20 前置）

> **状态：** 已立项（用户 2026-08-25）。基线已落到 **v0.84.3**。Goal 20 pairing / perf 仍暂停（`goal20Paused`）。不宣布 Goal 21 完成：「G20 在 0843 上继续」仍空。
>
> **当前：** `BASELINE` = `4e58f324f` · `v0.84.3` +0（pi-mono tag `v0.84.3`）  
> **自：** `914cf1472` · `v0.84.2` +0

## 为什么单独开 goal

Goal 18 Part L 把基线从 `v0.83.0` 推到 `v0.84.1`；此后 cadr 已落在 **`v0.84.2`**（全屏 TUI、Mermaid/LaTeX、harness v4 等大面已在该线对齐）。

`v0.84.3` 是 **0.84 线上的补丁发布**（相对 `v0.84.2` 约 100+ commits），但仍有用户可见与契约变化：

- Windows **PowerShell tool**、`/thinking` 选择器、session 级 model/thinking（Ctrl+S 才写全局默认）
- Managed install **原地更新**、启动路径减负（延迟 jiti/Babel、bundled runtime）
- RPC/`message_update`、compaction、provider 层多处修复
- `GoogleThinkingLevel` → `GoogleApiThinkingLevel`（pi-ai breaking）

在旧基线上继续做 Goal 20 pairing，ratio 与 render-diff 对照的是 **过时的 pi 半**，合入后还要重跑 freeze。

## 范围

| 在范围内 | 不在范围内（仍属 Goal 18 L 尾巴 / 其他） |
|---|---|
| 机械锚点：`BASELINE`、`set-baseline.sh`、fixture `baselineCommit` | Goal 18 L 未关的 Part A–K 历史项（不以此 goal 重开） |
| `render-diff` 基线 checkout 重建 + `PI_AI_MODEL_DATA_*` pin | cadr-server ↔ pi `packages/server` v0.84 契约（Goal 18 L1b，单独裁决） |
| `enumerate-baseline-diff.py` + `check-source-parity-drift.sh` 处置 | Goal 20 needs-pair 燃尽（本 goal 完成后继续） |
| 用户可见增量落地（见下表）+ 全门禁绿 | 为过关而抬 pairing ceiling |

## v0.84.2 → v0.84.3 用户可见增量（cadr 须跟进或裁决）

| 上游能力 | cadr 动作 |
|---|---|
| PowerShell tool（Windows） | 移植或书面豁免（非 Windows 可 defer 实现但须在 ledger 裁决） |
| `/thinking` + 可搜索 selector；model/thinking **session 默认** | 交互 + settings；对齐 Ctrl+S 全局保存语义 |
| `defaultTools` 设置（0.84.2 已有）与 extension 工具共存 | 核对 `goal20` 相关路径未回归 |
| Fullscreen transcript search（0.84.2）+ 退出输出选项 | 已有则回归；缺则补 |
| `session_compact_failed` 扩展事件 | 扩展面 parity |
| Compaction summary 截断不得入库（#7048） | **行为对齐 + 回归** |
| Managed `pi update` 原地激活 | 若 cadr 发行链镜像该行为则跟进，否则文档豁免 |
| `GoogleApiThinkingLevel` 重命名 | `cadr-ai` 类型与适配器同步 |
| xAI Grok 4.6 / Responses API 默认 | provider 表与默认模型 |
| Windows/WSL 默认快捷键调整 | keybinding 表与 render-diff 场景 |

完整增量以机械枚举为准，不得只靠本表。

## 执行顺序

1. **冻结当前 Goal 20 队列为只读**（operator 可 finish in-flight pair，不新开 pair/perf）。
2. **确保 pi 对象在 cadr 仓可解析：**
   ```bash
   git -C /path/to/pi-mono fetch --tags
   git -C /path/to/cadr cat-file -e 4e58f324f^{commit}  # 缺则 git fetch <pi-remote> 4e58f324f
   ```
3. **机械锚点：**
   ```bash
   scripts/set-baseline.sh 4e58f324fae8ebfa98a3d45181fb248072a2afac
   python3 scripts/baseline-anchor.py check
   ```
4. **模型数据 pin：** 更新 `scripts/render-diff.py` 中 `PI_AI_MODEL_DATA_PACKAGE` / `PI_AI_MODEL_DATA_SHA256`（`@earendil-works/pi-ai@0.84.3` 对应 tarball SHA）。
5. **删掉旧 render-diff 缓存：** `rm -rf /tmp/cadr-render-diff-pi-914cf1472`（及文档中一切旧 short 路径）。
6. **源与命名集枚举：**
   ```bash
   ./scripts/check-source-parity-drift.sh --repo ../pi-mono \
     --from 914cf1472e715297caa30db4b9535d534a9eb718 \
     --to 4e58f324fae8ebfa98a3d45181fb248072a2afac \
     --dispositions /tmp/g21-source-dispositions.tsv
   python3 scripts/enumerate-baseline-diff.py \
     914cf1472e715297caa30db4b9535d534a9eb718 \
     4e58f324fae8ebfa98a3d45181fb248072a2afac
   ```
7. **按 disposition 落地**（实现 / 豁免 / 行为对齐），更新 `docs/source-parity.md` 与 render-diff fixtures。
8. **全门禁：**
   ```bash
   python3 scripts/baseline-anchor.py check
   ./scripts/verify.sh
   ./scripts/test-cl.sh
   ```
9. **Goal 20 恢复：** 对受基线影响的 metric **重跑** `--only-enforce` 或子集 freeze；`goal20-unpaired-paths.py --check` 保持绿。

## 验收

- [x] `BASELINE` 第三列为 `0`，release 为 `v0.84.3`，commit 为 `4e58f324f…`
- [x] `python3 scripts/baseline-anchor.py check` 绿
- [x] `enumerate-baseline-diff` 各类 delta 均有 disposition（无 hand-wavy「同上」）
- [x] `./scripts/verify.sh` 与 `./scripts/test-cl.sh` 两套都绿（`verify.sh` 已跑 deterministic FiveAM；full `goal21-gate-run.sh` 不因验收而再执行一次完整 `test-cl.sh`）
- [x] `CHANGELOG.md` 记录：`cadr x.y.z · aligned with pi v0.84.3 (+0, 4e58f324f)`
- [ ] Goal 20 executor brief 中「G21 前置」勾选完成，队列为 **0843 基线** 上继续

## 与 Goal 20 的关系

- **G21 完成前：** 不新开 Goal 20 pair/perf 提交（避免双次 freeze）。
- **G21 完成后：** pairing 与 perf 在 `v0.84.3` 基线上继续；已有 paired metric 若 harness 未变可只跑增量 gate，若 0.84.3 改了被测入口则须重 freeze 该 metric。
