# Goal 23：pi 基线推进至 v0.85.1（Goal 20 invent 前置）

> **状态：** 进行中（用户 2026-09-05 采纳推荐 B）。Goal 20 invent/pair
> 冻结至本 goal 完成。Does not announce Goal 20 complete. G.17 stays
> `missing`.
>
> **自：** `b79e4cc83` · `v0.84.4` +0  
> **当前锚点：** `d981de122` · `v0.85.1` +0（pi tag `v0.85.1`）  
> G23 gates green on v0.85.1; invent unpaused. G.17 stays `missing`.

## 已落地上游增量（tip `eb9b9590a`）

| 项 | 状态 |
|---|---|
| `BASELINE` / model-data pin | done |
| GPT-6 Astra catalog (1354 models) | done |
| `scrollbarTrack` theme + JSON | done |
| Alt+wheel 5× | done（FiveAM） |
| Jump to latest overlay | done（FiveAM） |
| Working indicator in default editor border | done（`974c80866`；FiveAM） |
| `app.thinking.save` | already present |
| Anthropic mid-convo thinking effort | done（`8dedb33bb` + session `providerThinkingLevel`；FiveAM） |
| `CADR_TUI_DEBUG_REDRAW` | done（FiveAM getenv helper + first-render log） |
| inMemory entries | done（FiveAM `session-manager-in-memory` entries） |
| Experimental error / MouseRegion / tool renderers barrel | ledger-defer |
| `verify.sh` / `test-cl.sh` | not yet green for G23 close |
| Goal 20 invent unpause | blocked on G23 close |

## 为什么单独开 goal

Goal 21 把基线推到 `v0.84.3`；仓上现已钉在 **`v0.84.4`**。
上游已发 **`v0.85.0`**（2026-09-04）与 **`v0.85.1`**（2026-09-05）。
相对 0.84.4 约 460 commits，含用户可见 TUI / session / thinking /
provider 增量。在旧基线上继续 invent，ratio 与 render-diff 对照的是
过时的 pi 半。

钉点取 **v0.85.1**，不取已过时的 0.85.0（SDK 发包事故已在 0.85.1 修）。

## 范围

| 在范围内 | 不在范围内 |
|---|---|
| 机械锚点：`BASELINE`、`set-baseline.sh`、fixture `baselineCommit` | Goal 20 invent / pair / G.17 `met` |
| `render-diff` 基线 checkout 重建 + `PI_AI_MODEL_DATA_*` pin | 抬 pairing ceiling 以求过关 |
| `enumerate-baseline-diff.py` + `check-source-parity-drift.sh` 处置 | 与本 bump 无关的重构 |
| 用户可见增量落地或 ledger 裁决 + 全门禁绿 | |

## v0.84.4 → v0.85.1 用户可见增量（须跟进或裁决）

| 上游能力 | cadr 动作 |
|---|---|
| Persistent Claude thinking effort | done（`8dedb33bb`；session field follows） |
| Fullscreen「Jump to latest」+ `tui.altScreen.bottom` | 交互 + keybinding |
| Working indicator 嵌进 default editor border | done（`974c80866`） |
| Restorable in-memory sessions (`SessionManager.inMemory`) | done（`eb9b9590a`） |
| Fullscreen search 缓存与可见高亮 | 行为对齐或回归 |
| Alt 滚轮加速（0.85.1） | keybinding / TUI |
| GPT-6 Astra（0.85.1） | provider / model 表 |
| Selector save keybindings 可配置（0.85.1） | settings + selectors |
| Provider / tool / session 修复面 | 枚举后按 disposition |

完整增量以机械枚举为准，不得只靠本表。

## 执行顺序

1. **冻结 Goal 20：** `goal20-queue.json` `paused=true`；
   `goal21-queue.json` `goal20Paused=true`。不新开 invent/pair。
2. **确保 pi 对象可解析：**
   ```bash
   git fetch upstream --tags
   git cat-file -e d981de1229ef899957bbe968bc8dcda02a21f477^{commit}
   ```
3. **机械锚点：**
   ```bash
   scripts/set-baseline.sh d981de1229ef899957bbe968bc8dcda02a21f477
   python3 scripts/baseline-anchor.py check
   ```
4. **模型数据 pin：** `scripts/render-diff.py` 中
   `PI_AI_MODEL_DATA_PACKAGE` / `PI_AI_MODEL_DATA_SHA256`
   → `@earendil-works/pi-ai@0.85.1` /
   `af7d11986179445ce6fe88b37d57de22f823c0ffd3a65cae31c555b7f5e99253`。
5. **删旧 render-diff 缓存：** `rm -rf /tmp/cadr-render-diff-pi-b79e4cc83`。
6. **源与命名集枚举：**
   ```bash
   ./scripts/check-source-parity-drift.sh --repo ../pi-mono \
     --from b79e4cc834970cca69daebffab7df1da7d1e52c4 \
     --to d981de1229ef899957bbe968bc8dcda02a21f477 \
     --dispositions /tmp/g23-source-dispositions.tsv
   python3 scripts/enumerate-baseline-diff.py \
     b79e4cc834970cca69daebffab7df1da7d1e52c4 \
     d981de1229ef899957bbe968bc8dcda02a21f477
   ```
7. **按 disposition 落地**（实现 / 豁免 / 行为对齐）。
8. **全门禁：**
   ```bash
   python3 scripts/baseline-anchor.py check
   ./scripts/verify.sh
   ./scripts/test-cl.sh
   ```
9. **Goal 20 恢复：** `paused=false`；受影响 metric 重跑
   `--only-enforce` 或子集 freeze；`goal20-unpaired-paths.py --check` 绿。

## 验收

- [x] `BASELINE` 第三列为 `0`，release 为 `v0.85.1`，commit 为 `d981de122…`
- [x] `python3 scripts/baseline-anchor.py check` 绿
- [x] `enumerate-baseline-diff` 各类 delta 均有 disposition
- [x] `./scripts/verify.sh` 与 `./scripts/test-cl.sh` 绿
- [x] `CHANGELOG.md` 记录：`cadr … · aligned with pi v0.85.1 (+0, d981de122)`
- [x] Goal 20 `paused=false`；invent 仅在 0851 基线上恢复
- [x] Does not mark G.17 `met` / Goal 20 complete

## 与 Goal 20 的关系

- **G23 完成前：** 不新开 Goal 20 invent/pair（避免双次 freeze）。
- **G23 完成后：** 恢复 invent；G.17 仍 `missing` 直至 Part P 证据足够。
