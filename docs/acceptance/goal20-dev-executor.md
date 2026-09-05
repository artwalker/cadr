# Goal 20 开发执行 brief（顾问维护）

> **Process (live):** [`team-dev-platform.md`](team-dev-platform.md) — Cursor
> cloud agents on GitHub `artwalker/cadr` (总控 / 实现 / 审 / 合入). Grok Bot
> is retired. The tmux / worktree / `goal20-director-merge.sh` crew below is
> the Goal 20 pairing record; it is not how cadr is developed now. **Live
> merge** of READY leftover pairing PRs is a Cursor cloud-agent duty (serial
> onto `cadr-migration`), not a local director pane.

**读者：** Cursor cloud agent（执行方）。**审 run：** 只审阅 digest、回答问题，不写 `src/`。

**规格：** `goal20-draft.md`。**验收：** `docs/acceptance/goal-v20-part-*.md`，Part H 配对台账 `docs/acceptance/goal-v20-part-h.md`。

**禁止：** 宣布 Goal 20 完成；标 G.17 `met`；**同一提交**里既测量又改 `src/` 优化；把顾问稿混进 pairing 提交。

**Live cloud-agent merge (Goal 20 leftover PRs):** after a trio is READY
(freeze recorded on the PR), the Cursor cloud agent merges that PR into
`cadr-migration` itself — GitHub merge, **one PR at a time**, rebase the
next leftover onto the new tip first. Harness files conflict if two
leftover PRs land in parallel. Post-merge: ledger test; when that source
file's leftover slugs are on tip, `goal20-unpaired-paths.py --write &&
--check`. Tags / force-push / spend stay with Ethan.

## G21 前置

- [x] Goal 21 完成（pi `v0.84.3` / `4e58f324f`）。队列在 **0843 基线**。Ethan restored pairing on 2026-08-27（`docs/benchmarks/goal21-queue.json` `goal20Paused` = false；`docs/benchmarks/goal20-queue.json` `paused` = false）。This cut does not announce Goal 20 complete, does not mark G.17 `met`, and does not start a new pair.

## G23 前置（进行中）

- [ ] Goal 23：基线推进至 pi `v0.85.1` / `d981de122`（自 `v0.84.4` / `b79e4cc83`）。规格 [`goal23-pi-0851-alignment.md`](goal23-pi-0851-alignment.md)。**G23 完成前** `goal20-queue.json` `paused=true`；不新开 invent/pair。Does not mark G.17 `met`.

---

## 开发模式（dev/test）

本实例允许 **pair + perf/fix**，但必须拆提交、拆职责：

| 提交类型 | 改什么 | 消息前缀 | bench |
|---|---|---|---|
| **配对** | harness 三件套 + record + ledger test + Part H | `feat(cadr-cli): pair …` | freeze（Friend-MachineD n=5） |
| **优化** | 仅 `src/` | `perf(cadr-cli): …` | 受影响 metric 的 `--quick` + ratio 注记 |
| **冻结记录** | `docs/performance.md`、ledger json | `docs(cadr-cli): record … freeze` | 已在 pair 提交跑过 |

**Pair ≠ 代码映射。** 配对 = 同一 fixtures + observed exact key + Friend-MachineD n=5 ratio + Part H 节 + over-1× 台账（若 >1×）。

---

## 推荐节奏：按子系统，不要逐 metric 横跳

**问题：** 每条 metric 都跑全量 ~260 metric gate ≈ 35 min；横跳文件会反复冲突 `goal20-paired-paths.*`。

**做法：** 选一个 **子系统/源文件**，在该范围内走完「配对 → 优化热点 → 验证」，再换下一个。

```
子系统 X（例 models.lisp / settings / auth）
  ├─ 1. 批量配对 3–5 条 needs-pair（worktree 并行，总监串行 merge）
  ├─ 2. 看 over-1× 台账 + quick ratio，挑最热 1–3 条做 perf 提交
  ├─ 3. 增量 gate：--only-enforce 刚配的 metric；每 5 条或每日一次全量 freeze
  ├─ 4. 该文件 needs-pair 清零后：goal20-unpaired-paths.py --write && --check
  └─ 5. 换下一子系统
```

**硬案例后置**（先配对、优化可延后）：`ai_support.auth_guidance`、`websocket` 栈、`skill_prompt_load`、整页 selector render 类。先把 inventory `--check` 和 harness 冲突清掉。

---

## 三队 + 总监（并行配对、串行合入）

| 角色 | 谁 | 改什么 | 工具 |
|---|---|---|---|
| **Pairing** | Dev-A/B/C 并行 | 仅 worktree 内 harness + 文档；**主目录 harness 只读** | `scripts/goal20-pair-worktree.sh <n> <metric>` |
| **Optimization** | 独立 agent | 仅 `src/`；**never harness** | `scripts/goal20-opt-worktree.sh <slug>` |
| **Testing** | 每 merge 后 | ledger + unpaired `--check` + 可选增量 gate | `scripts/goal20-team-qa.sh [--only-enforce …]` |
| **总监** | 单线程 | **一次 cherry-pick 一条 pair 分支** → QA → 下一支 | `scripts/goal20-director-merge.sh <branch> [--only-enforce …]` |

**Harness 锁：** 仅总监 merge 时 `scripts/goal20-team-lock.sh acquire director`。

**节奏：** 干完一对 → 总监 merge + QA → 下一对。**不用 30 分钟 tick。**

**冲突纪律：**

- Pairing **永不** touch 主 checkout 的 `scripts/goal20-paired-paths.*`
- 禁止 `git restore` 覆盖他队 worktree 成果
- lisp 行数 merge 后不得比 merge 前少 50 行（`goal20-director-merge.sh` 自动 abort）
- 同一 `measure-*` 函数上不要并行两 lane

---

## Bench 策略

| 场景 | 命令 |
|---|---|
| 冒烟（秒级） | `scripts/goal20-paired-paths.sh --quick` |
| 单条/批量新 metric 验收 | `scripts/goal20-paired-paths.sh --only-enforce GROUP.NAME …` |
| 冻结 ratio（pair 提交必跑） | `scripts/goal20-paired-paths.sh`（全量 Friend-MachineD n=5） |
| merge 后 QA（默认） | `scripts/goal20-team-qa.sh` |
| merge 后 QA（增量） | `scripts/goal20-team-qa.sh --only-enforce new.metric …` |
| 每 5 条 pair 或每日 | 全量 `goal20-paired-paths.sh` 一次，更新 freeze 文档 |

`--quick` 会改 ledger 文件；`goal20-team-qa.sh` 跑完 quick 后会 `git restore` 已提交的 ledger，勿手滑提交污染。

**Ceiling：** 仅首次 freeze 失败时 bump；不要为过关而抬 ceiling。

---

## 单条 metric 技术清单

1. **接线（三件套缺一不可）：** `scripts/goal20-paired-paths.{lisp,mjs,py}`、`record-paired-paths.py`、`write-performance-ledger.py`、`test/goal20-part-b-ledger-test.py`
2. **py `METRICS` 元组** 必须含新 slug（Pair 216 教训）
3. **Fixtures + observed keys** 与 pi mjs 行为 exact 对齐；mjs 只复刻被测入口，不走整组件 render
4. **文档：** Part H 新 `### Pair N` 节 + `CHANGELOG.md` + Part H §6 库存行（若新源文件）
5. **测试：** `python3 test/goal20-part-b-ledger-test.py`
6. **ratio > 1×：** 记入 `docs/benchmarks/goal20-paired-over-1x.md`（配对提交仍要合入，优化另开 perf 提交）

### Pairing worktree 流程

```bash
scripts/goal20-pair-worktree.sh 253 my_metric_slug
cd /tmp/pair253-wt
# … 改 harness + 文档 …
scripts/goal20-paired-paths.sh --quick --only-enforce my_group.my_metric
scripts/goal20-paired-paths.sh --only-enforce my_group.my_metric   # 或全量 freeze
git commit -m "feat(cadr-cli): pair my_group.my_metric (253)"
# 通知总监：
scripts/goal20-director-merge.sh pair-253-my-metric-slug --only-enforce my_group.my_metric
```

### Optimization worktree 流程

```bash
scripts/goal20-opt-worktree.sh my-hotspot-slug
cd /tmp/opt-my-hotspot-slug-wt
# … 仅改 src/ …
scripts/goal20-paired-paths.sh --quick --only-enforce affected.metric
python3 test/goal20-part-b-ledger-test.py
git commit -m "perf(cadr-cli): cache X for my_group.my_metric (goal 20)"
# 总监在对应 pair harness 稳定后 merge opt 分支
```

---

## 库存刷新（P.13 前置）

每清完一个源文件的 needs-pair：

```bash
python3 scripts/goal20-unpaired-paths.py --write
python3 scripts/goal20-unpaired-paths.py --check
```

`--check` 失败常见原因：**denominator drift**（磁盘行数 vs `goal20-unpaired-paths.json` 不一致）— 用 `--write` 重簿，勿手改 json。

关账线：`needs-pair` 清零 + `--check` 无 `pairable-uncovered`。之后 Part O/K/G — G.17 须**顾问书面**允许才可 `met`。

---

## 当前快照（2026-08-25）

| 项 | 值 |
|---|---|
| 分支 | `cadr-migration` |
| HEAD | `a38293d17` — Pair 249 `settings_load.stored_auth_secrets` freeze |
| 已配对 metric | **~261** |
| Part H Pair 节 | **~240+** |
| over-1× 台账行 | **~217**（`docs/benchmarks/goal20-paired-over-1x.md`） |
| unpaired `--check` | **失败** — denominator drift（disk 127,795 lines vs inventory 127,515）；需 `--write` |
| 活跃 worktree | 见 `git worktree list`；lane 表随 Pair 推进变化，以分支名为准 |

### 近期已合入（参考顺序）

`agent_tool_loop` → `storage_journal` → `settings_load` → `package_manager` → `cli_extensions_install` …

### 建议下一批子系统

按 needs-pair 密度和 harness 区域互斥选 lane，优先 **同一源文件内连续 metric**：

- `settings` / `settings_load` 残余 helper
- `package_manager` 后续
- `session_compact` / `evals_harness` / `tui_latex`（若 lane 241–243 未 merge）
- `models.lisp` scoped/model selector 热点 perf（over-1× 台账：`oauth_selector_ui_state`、`sorted_ids`、`enable_all` 等）

`common.lisp` **已全部配对**，勿回头。

---

## 提交消息模板

```
feat(cadr-cli): pair <group>.<metric> (<N>)
# body: ratio, ceiling, G.17 missing if any, fixtures summary

docs(cadr-cli): record <group>.<metric> freeze on main (<N>)

perf(cadr-cli): <what changed> for <group>.<metric> (goal 20)
# body: before/after ratio from --quick or freeze
```

---

## 编排器（自动化开队）

```bash
# 看队列状态
scripts/goal20-orchestrator.sh status

# 清 stale worktree
scripts/goal20-cleanup-worktrees.sh

# 单次总监 merge
scripts/goal20-orchestrator.sh director-once

# 单次派发（cursor-agent --model auto）
scripts/goal20-orchestrator.sh dispatch a

# 一键 tmux 四 pane（director + lane-a + lane-b + opt）
scripts/goal20-team-tmux.sh
tmux attach -t goal20-team
```

队列文件：`docs/benchmarks/goal20-queue.json`（pair 号、lane、子系统、merge 队列）。

---

开发实例每完成 pairing commit，顾问 monitor（`scripts/cadr-advisor-monitor.sh`）在 digest 批次审阅。也可主动贴 SHA。
