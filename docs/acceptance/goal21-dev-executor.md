# Goal 21 开发执行 brief（顾问维护）

> **Process (live):** [`team-dev-platform.md`](team-dev-platform.md) — three
> Grok Bot agents (总控 / 实现 / 审) plus a Cursor cloud agent on GitHub
> `artwalker/cadr`. The `scripts/cadr-team.sh` / tmux / worktree /
> `cursor-agent --resume` crew below is **retired** (scripts kept). This file
> is a Goal 21 execution record, not the current development process.

**平台哲学（现行）：** [`team-dev-platform.md`](team-dev-platform.md)

**读者：** 开发 Cursor 实例。**规格：** [`goal21-pi-0843-alignment.md`](goal21-pi-0843-alignment.md)。

**禁止：** 在 G21 完成前新开 Goal 20 pair/perf；宣布 G21 完成前须 `verify.sh` 与 `test-cl.sh` 两套都绿（`verify.sh` 的 deterministic FiveAM 即 `test-cl.sh`；full `goal21-gate-run.sh` 在该 stage 已 PASS 时不再跑第二次）。

---

## 目标

跟踪基线：`4e58f324f` · v0.84.3 +0（自 `914cf1472` · v0.84.2；机械枚举已确认：+`/thinking`、`modelThinkingLevels`、`session_compact_failed`、`powershell.ts` 等）。

## 三队 + 总监

| 角色 | Lane | 职责 |
|---|---|---|
| **Anchor** | `anchor` | `set-baseline.sh`、model-data pin、删 render-diff 缓存、`baseline-anchor.py check` |
| **Parity** | `parity` | `enumerate-baseline-diff` + `check-source-parity-drift` → disposition TSV → `docs/source-parity.md` |
| **Impl A** | `a` | `/thinking` selector、`modelThinkingLevels`、session 级 model/thinking（Ctrl+S 全局） |
| **Impl B** | `b` | `session_compact_failed`、compaction summary 不入库（#7048） |
| **Impl C** | `c` | `GoogleApiThinkingLevel` 重命名、provider 表增量 |
| **Gate** | `gate` | 脚本 `goal21-gate-run.sh` 跑 `verify.sh`（含 FiveAM）；仅当摘要里 `deterministic FiveAM` 未 timed-PASS 时才再跑 `test-cl.sh`；失败才短会话 fix agent（勿让单 agent 扛全量长跑） |
| **Infra** | `infra` | 验证/提交 gate 结构性改进（disposition audit、fast gate、capture cache、anchor-guard 隔离） |
| **总监** | director | **机械合入**（`goal21-director-merge.sh`：rebase+ff+fast gate）；**冲突时**才派 Director agent（`goal21-director-conflict-dispatch.sh`） |

## Lane 记忆（模块负责人）

Impl lane（`a`/`b`/`c`/`parity`）不是每次失忆：

| 机制 | 路径 / 脚本 |
|---|---|
| **Session resume** | `cadr-team-dispatch.sh` + `cursor-agent --resume`；chatId 存 `docs/benchmarks/cadr-team-agent-sessions.json`（key: `goal21-lane-<lane>`） |
| **Handoff 文件** | `docs/goal21-handoff/lane-<lane>.md`（每轮结束打印 `GOAL21_HANDOFF`） |
| **代码记忆** | worktree 分支 + git commit（不变） |

**仍无状态（故意）：** gate fix specialist、`anchor`、`infra`（`CADR_AGENT_RESUME=0`）。

## 总监：脚本 vs agent

| 步骤 | 谁做 | 原因 |
|---|---|---|
| rebase + ff-merge + fast gate | **脚本** | 确定性、可审计、不能「凭感觉 merge」 |
| merge 冲突 / rebase 失败 | **Director agent** | 需要读冲突、做判断；脚本只负责重试 `director-once` |

平时 99% 合入是空分支 ff-merge，不需要 agent。agent 总监只在机械路径失败时介入（像真实团队里总监处理冲突，CM 不做日常 merge bot）。

## Worktree 纪律

1. `scripts/goal21-pair-worktree.sh <task-id> <slug>` 创建分支 `g21-<id>-<slug>`
2. **永不**在主 checkout 上改 `src/`（operator 除外做 anchor 机械步）
3. 完成打印：`GOAL21_COMPLETE task=<id> branch=g21-<id>-<slug>`
4. 总监：`scripts/goal21-director-merge.sh <branch>`（premerge + post-merge 均 `GOAL21_GATE_MODE=fast`）

## 机械枚举（0.84.2→0.84.3）

已跑 `enumerate-baseline-diff`（29 added / 1 removed file）。优先落地：

- `slashCommands.thinking`
- `settingsKeys.modelThinkingLevels`
- `extensionEvents.session_compact_failed`
- `toolFiles.powershell.ts`（非 Windows 可书面 defer，须在 ledger 裁决）
- `GoogleThinkingLevel` → `GoogleApiThinkingLevel`

## 验收

见 `goal21-pi-0843-alignment.md` 验收清单。`goal20Paused` 仍为 true；规格最后一项（G20 在 0843 上继续）保持空，本 closeout 不恢复 Goal 20 pairing。

## Operator 自愈（anchor guard）

每 tick / director merge 前，`scripts/goal21-anchor-guard.sh ensure`：

- `BASELINE` 已指向目标 commit 但未 commit → 自动 `chore: bump baseline to pi v0.84.3 (g21)`（排除 queue/acceptance 运维文件）
- 无法安全提交 → 将 task 1  reopen 为 `pending`，重 dispatch anchor lane
- anchor agent 未 commit 就打印 `GOAL21_COMPLETE` → dispatch 拒绝标 done
- impl 分支已有 commit 但 agent 未打完成行 → `reconcile-in-progress` 入 mergeQueue

## Gate 防卡死

- **Preflight：** `scripts/goal21-gate-preflight.sh` 在 `verify.sh` 前直接跑 `derive-source-parity-mappings.lisp --check`（默认 ~1 min）；设 `GOAL21_PREFLIGHT_RENDER_DIFF=1` 可再加 render-diff core；**上一轮失败为 render-diff 时 gate-run 自动启用**；跳过设 `GOAL21_SKIP_PREFLIGHT=1`。
- **Postfix（fix 后、全量 gate 前）：** orchestrator 在每次 fix 后自动跑 `scripts/goal21-gate-postfix-check.sh`。**render-diff postfix 默认对已有 capture 跑 `analyze`（~90s），无缓存时才跑完整 `gate`（~15min）**；fix agent **无新 commit 则跳过 postfix**。postfix 未通过则继续 fix，不启动全量 verify；postfix 5 次仍失败则 reset pending。
- **Render-diff brief：** 失败时 `goal21-gate-render-diff-brief.sh` 写入 `/tmp/goal21-render-diff-brief.txt`（含 validation 错误 key、missing/stale、summary 统计）。
- **Disposition 自动同步：** 失败时先 `goal21-gate-refresh-disposition-hashes.py`（从 analysis capture 刷新过期 SHA），再 `goal21-gate-auto-fix-render-diff.sh` 从 `summary.json` 合并安全 disposition（I01、I01+I04）；`render-diff.py analyze` 在 validation 失败前写入 summary/pending 供 auto-sync 使用。
- **Fix 超时：** render-diff 审核 `CADR_GATE_RENDER_DIFF_FIX_TIMEOUT_SEC`（默认 600s）；其它 `CADR_GATE_FIX_TIMEOUT_SEC`（1800s）。
- **拆分：** `scripts/goal21-gate-run.sh` 跑验收；agent 只读 `/tmp/goal21-gate-fail.txt` 修失败（`GOAL21_FIX_DONE`），**禁止 agent 跑 verify.sh/test-cl.sh**；定向验证由脚本承担。
- **进度 stale：** `scripts/cadr-team-stale-agents.sh` — 闲置 ≥`CADR_STALE_IDLE_SEC`（默认 1200s）且无 verify/test-cl/新 commit → kill 僵尸并 reset gate pending。
- **6 轮用尽：** orchestrator reset task `pending` 后自动 tick `goal21-team-operator.sh once` 重调度。
- **编译门禁：** gate 前先 `scripts/ensure-root-binary.sh`（stale 则 `rebuild-root-binary.sh`）；fix agent 改 `src/` 后须 `scripts/cadr-compile-check.sh` + `derive-source-parity-mappings.lisp --check`；本地可选 `scripts/install-git-hooks.sh` 装 pre-commit。
- **Fix commit：** `fix(g21-gate): <stage-slug> (rN)`，勿再用泛化 chore 信息。
- **Fix agent 纪律：** 短会话只改代码 + commit；长跑（render-diff core、verify）一律交给 orchestrator 脚本，避免 30 min 超时后仍烧全量 gate 轮次。
- **Specialist dispatch：** `goal21-gate-fix-dispatch.sh` 按 failure kind 派 specialist（`task-key=gate-specialist-<kind>-<task>-rN-pM`，`--goal gate-<kind>`），不再用万能 `gate-fix-*`。机械修复先跑 `goal21-gate-mechanical-fix.sh`（render-diff auto-sync、goal20-ledger `--write`、product-identity 已 PASS 则跳过）。

## Gate 结构性改进（infra lane）

**问题：** 实现 lane 快、验收慢；`dispositions.json` 难维护主因是 hash 过期与 anchor-guard 覆盖 disposition commit，而非文件体积。

| 改进 | 脚本 | 作用 |
|---|---|---|
| Disposition audit | `goal21-render-diff-audit-dispositions.py` | manifest 校验、stale 检测、`--prune-stale`；proactive heal 每轮 audit |
| Anchor 隔离 | `goal21-anchor-guard.sh` ANCHOR_EXCLUDE | `dispositions.json` 不再被 baseline chore commit 打包 |
| Fast gate | `GOAL21_GATE_MODE=fast` + `goal21-gate-fast.sh` | 开发迭代 ~2–5 min（preflight + cached analyze + compile）；**验收仍用 full**；`goal21-gate-run.sh` 在 `GOAL21_GATE_MODE=fast` 时委托 fast 脚本 |
| Capture cache | `goal21-render-diff-capture-cache.sh` | 按 BASELINE commit 存/取 capture，gate-run 无本地缓存时自动 restore |
| CI capture cache | `.github/workflows/ci.yml` + `verify.sh` | Actions `cache/restore`+`save` keyed on `BASELINE`；`verify.sh` 读 `GOAL21_RENDER_DIFF_*`，有 capture 时用 `analyze` 而非全量 `gate` |
| Class rules | `disposition-class-rules.json` + `goal21-render-diff-prune-class-rules.py` | 常见 I01/I04 模式由 class rule 裁决；ledger 可 `--apply`  prune；`goal21-class-rules-verify.sh` 跑 cached analyze |
| Test-cl shard | `CADR_TEST_CL_SHARD` + `test-cl-fiveam.sh` / `test-cl-goal20.sh` | gate 可拆跑 FiveAM 与 goal20 ledger；FiveAM 默认 summary-only（`CADR_TEST_CL_VERBOSE=1` / `--verbose`）；`goal21-test-cl-shard-verify.sh` 校验别名、quiet、以及 full gate-run 跳过第二次 `test-cl.sh` |
| Manifest skeletons | `goal21-render-diff-ensure-skeletons.py` + `goal21-render-diff-on-manifest-change.sh` | manifest 变更后 audit + 缺省 disposition 骨架；gate auto-fix 用 `--apply`；`goal21-manifest-skeletons-verify.sh` 机械校验 |

**调度：** `scripts/goal21-team-operator.sh once` 在 impl 完成后、gate 之前 dispatch `infra` lane（tasks 8–12）；core infra batch 全 `done` 后才 dispatch gate task 7。tasks 13+ 为 gate 后 follow-up，不阻塞 gate。
