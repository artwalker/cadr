# Goal 23 开发执行 brief

> **Process (live):** Cursor-only on `artwalker/cadr` `cadr-migration`
> (`docs/adjudications.md` 2026-09-05 Cursor executor). No separate
> advisor session. User veto retained.

**读者：** Cursor executor。**规格：**
[`goal23-pi-0851-alignment.md`](goal23-pi-0851-alignment.md)。

**禁止：** G23 完成前新开 Goal 20 invent/pair；宣布 Goal 20 完成；
标 G.17 `met`；为过关抬 pairing ceiling。

## 目标

跟踪基线：`d981de122` · v0.85.1 +0（自 `b79e4cc83` · v0.84.4）。

## 退出谓词（autonomous）

全部为真才算 Goal 23 完成：

1. `BASELINE` = `d981de1229ef899957bbe968bc8dcda02a21f477 v0.85.1 0`
2. `python3 scripts/baseline-anchor.py check` exit 0
3. `0.84.4→0.85.1` 枚举类均有 disposition（实现或 ledger 裁决）
4. `./scripts/verify.sh` 与 `./scripts/test-cl.sh` 绿
5. CHANGELOG 含 `aligned with pi v0.85.1 (+0, d981de122)`
6. `goal20-queue.json` `paused=false`；`goal20-unpaired-paths.py --check` 绿
7. G.17 仍为 `missing`

## 执行顺序（单会话）

1. Pause Goal 20 queues + 本 brief / acceptance 立项提交
2. `set-baseline.sh` + model-data pin + anchor check
3. enumerate + source-parity drift → disposition TSV
4. 按 disposition 分提交落地（实现 / 豁免）
5. full gate；失败则修到绿
6. 恢复 Goal 20 pause 标志；trail 记恢复

## Trail

本地：`.audit/goal23-decision-trail.tsv`（默认不入库，除非需要可审计
合入记录）。
