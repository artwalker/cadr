# GOAL v10: 备份、追新、CI、Lisp 原生能力与首个发布

## 〇、定位与总规则

> **2026-08-01 执行顺序裁决**：Part A 验收通过后，顺序调整为
> `C → B（等待 v0.84.0）→ D → E`。Part C 对 Part B 零依赖。用户随后
> 明确：Part D 的书面提案可在等待 `v0.84.0` 时先行；“B 必须先于 D”
> 只约束 Part D 实现，避免 parity 账本混入旧基线。Part C 完成时若
> `v0.84.0` 尚未发布，Part B 保持暂挂，不得改锁 HEAD。
> Part B 的 bearer-token SHA-256、定长比较与 socket suffix 最小实现面已按
> `docs/proposals/goal-v10-part-b-baseline.md` 第 0 节预授权；新增密码学依赖或
> 超出批准文件面仍须 blocked。
>
> **2026-08-01 Part D 裁决**：D1 condition/restart、D2 Slynk capability
> 与 D2 精确依赖闭包均已逐项批准，但实现仍须等待 Part B 完成。D1 获准新增
> 第 34 个扩展事件 `:tool-call-error`，仅为本次完整提案解除 Goal 8 的
> “33 个封顶”；实现后按 34 个事件重新冻结，今后任何新增仍须重新提案并
> 逐项裁决。D2 必须默认关闭、只由显式 CLI 开启、固定监听
> `127.0.0.1`；构建与确定性测试必须用全新空临时 `HOME` 防止构建机
> `.slynkrc` 副作用进入 image。完整裁决见
> `docs/proposals/goal-v10-part-d-lisp-native-capabilities.md`。
>
> **2026-08-01 Part B 最终裁决**：Part B 结为 no-op。`v0.83.0`
> (`845d6ff1f`) 比当前 `74caa2649` 基线落后 38 个提交，且少
> `packages/protocol` 与 11 个测试文件；不存在领先当前基线的发布 tag，
> 因而没有可用升级点。tag 策略补充为“有领先发布 tag 则锁定；否则保持
> 当前基线并如实标注版本关系”。不得继续轮询上游。执行顺序改为
> `Goal 11 → D → B(no-op 落账) → E`，其中 Goal 11 与 D 已完成。

- **goal 9 全部 Part（A/A2/B/C/D/E）验收通过后**方可开始。
- 本 goal 收拢 goal 9 之后的全部待办，**不接受范围缩减**：工作量大的拆成更多 Part 顺序推进，不得移出范围或推给后续 goal。唯一合法的缩范围形式是标记 blocked、说明理由、交用户裁决。
- Part 间自动推进，不等用户指令。**仅三类情况 blocked**：(a) 新第三方依赖；(b) 密码学路径超出既有裁决；(c) 新增能力提案未获裁决（Part D 专有）。
- **完成 = 已提交落账**，未提交的完成宣告无效。凭据纪律不变：任何 key/token 不进代码、fixture、日志、报告与远程仓库。

## 一、Part A：远程仓库与异地备份（最高优先，先做）

**背景**：v1 至今全部工作仅存在于本机磁盘，无异地副本，属单点故障。`gh` 已认证为 `artwalker`（scopes: repo, workflow）。

1. **用户已于 2026-08-01 明确授权 Codex 自行执行建仓库、推代码与配置 CI**（对外动作；授权范围严格限于本节与 Part C，不扩展到任何其他对外操作，尤其不含公开仓库或发布 Release）：
   - `gh repo create cadr --private --source=/root/projects/cadr --remote=backup`
   - 推送全部分支与 tag：至少 `cadr-migration`（主线）与 `pi-mono-legacy`（历史锚点）。
   - **远程名必须为 `backup`，不得改动或覆盖现有 `origin`**（origin 仍指上游 earendil-works/pi，用户的 `git pull` 习惯不能被破坏）。
2. **仓库必须是 private。** 公开与否是用户的独立决定，本 goal 不得改为 public。
3. 推送前自查：确认 `~/.cadr/auth.json`、任何 key/token、`.tmp-home/`、`.codex`、构建产物均不在跟踪树内；`.gitignore` 完善后再推。**若发现任何凭据曾进入历史提交，立即 blocked 并报告，不得自行改写历史。**
4. 推送后验证：`git -C /root/projects/cadr ls-remote backup` 能列出预期分支；在临时目录 `git clone` 一份并跑通 `./build.sh`，证明备份可用而非仅可达。
5. 报告记录仓库 URL、已推送的分支与 tag、验证命令与结果。

## 二、Part B：基线追新到最新上游

**最终状态：no-op，已关闭。** 原要求由上述 2026-08-01 用户裁决取代；
完整计数、判定依据与既有 `362 C / 0 U / 0 M / 1 N/A / 363` 结论见
`docs/acceptance/goal-v10-part-b.md`。本 Part 未改变 baseline、fixture、源码或
parity 分类。

**必须在 Part D 之前完成**：先与上游对齐到底，再叠加自研能力，这样 parity 账本上剩余的差异全部是"我们有意为之"，而不会与"上游又动了"混在一起。

1. **基线必须锁定在上游的发布 tag，不再锁开发分支 tip**（用户 2026-08-01 裁定）。取执行时刻 `earendil-works/pi` 的最新稳定 tag（如 `v0.84.0`），记录其 tag 名与对应 commit hash，二者一并写入报告与全部文档；旧基线 `74caa2649` 降为历史锚点（`71efc6f0` 仍保留为最初锚点）。

   **背景与理由**：此前两次基线均为 tag 之后的开发中提交——`71efc6f0` 是 `v0.83.0-1`，`74caa2649` 是 `v0.83.0-38`，而当时的 HEAD 已是 `v0.83.0-130` 且正处于会话存储层重构中途（`jsonl-repo`+`jsonl-storage` → `jsonl-store`、`memory-repo`+`memory-storage` → `memory-store`、新增 `repository.ts`/`fork.ts`/`keyed-operation-queue.ts`、`storage.test.ts` → `session-backends.test.ts`）。锁发布 tag 的好处：发布点不再移动且通常已收敛，不会撞上半完成的架构位移；"cadr 对齐 pi v0.84.0"可交流可复现；上游每发一版即为一次天然的升级决策点。

   若执行时最新 tag 与上游 HEAD 差距过大（例如 tag 已落后数百提交且用户明确想要某个仅存在于 HEAD 的功能），标记 blocked 交用户裁决，不得自行改锁 HEAD。
2. 新建审计 checkout（如 `/tmp/cadr-parity-<新hash>`），沿用既有增量升级流程：
   - 全量重新生成 payload 对拍 fixture，逐条列出与旧基线的差异并对应到实现修改或确认无影响；
   - `git diff <旧基线>..<新基线>` 全量过一遍，产出增量清单；
   - parity-map 按新基线重建，新增测试文件入账为 `M`，**受上游变更影响的既有 `C` 必须重新验证**，不得沿用旧结论。
3. 已知增量（截至 2026-08-01，清单不完整，以实际 diff 为准）：**新包 `packages/client`**（Unix socket 传输）；`feat(server): composable protocol server`；`feat(tui): fullscreen transcript navigation`；`feat(tui): draggable transient scrollbars`；`feat(coding-agent): ui mode setting`；`fix(tui): preserve spaces in settings searches`；Fireworks Kimi K3 路由；Codex socket 按账户隔离等。
4. 补齐至新基线全部测试文件 `C` 或经用户裁决 `N/A`。
5. 视觉与运行时对齐：新增 TUI 功能（fullscreen transcript、scrollbars、ui mode）必须纳入 `docs/visual-parity.md` 的机械对齐表，并追加到 B3 双终端 A/B 清单供用户复验。

## 三、Part C：CI

1. 基于 goal 9 Part D 的 `./scripts/verify.sh` 建立 GitHub Actions 工作流，推送到 Part A 的私有仓库。**用户已于 2026-08-01 授权 Codex 自行配置并启用 CI**（`gh` token 具备 `workflow` scope）。
2. 内容：SBCL 环境准备、依赖安装、`build.sh`、**离线全量测试**（凭据门控的 live 部分在 CI 中按缺凭据正常跳过，不得失败也不得伪装通过）。
3. 工作流必须在 CI 上真实跑绿一次，报告附运行链接与结论；**不得只提交 yml 就宣告完成**。
4. 明确记录 CI 与本地 `verify.sh` 的覆盖差异（哪些 live 项只能本地跑）。

## 四、Part D：Lisp 原生能力（提案先行，需用户逐项裁决）

**性质**：这是"新增能力"层，属基线没有的机制，按项目既定三层界线，**必须先交书面提案、经用户逐项批准后方可实现**，标准对齐 `docs/proposals/goal-v7-extension-api.md`（每项含确切需求、最小实现面、替代方案及否决理由、对既有冻结面的影响、回滚方式）。

候选（用户 2026-07-31 提出方向，具体设计由本 Part 提案确定）：

1. **condition/restart 用于工具失败**：当前 `restart-case`/`invoke-restart` 用量为 0，错误处理全部是 `handler-case`（等价 try/catch）。目标是在工具失败的**出错现场**（栈未展开）提供"改参重试 / 跳过 / 中止"等重启点，供 hook 扩展或交互式前端选择——这是 TypeScript 实现物理上做不到的能力。提案须明确：重启点集合、与既有 `:tool-call-after` hook 的关系、非交互模式（print/json/rpc）下的默认行为、以及不改变既有可观察行为的保证。
2. **slynk 远程 REPL 接入运行中的 agent**：目标是从编辑器连入正在运行的 cadr，检查 agent 状态、重定义工具函数，下一轮即生效且不丢会话。提案须明确：**默认关闭**、显式开关与仅监听 loopback、与"默认 YOLO + 容器隔离"安全立场的关系、以及 slynk 作为新第三方依赖需单独授权（受 (a) 类 blocked 约束）。

**约束**：无论批准与否，此二者均**不得改变任何既有可观察行为**（发给服务端的 payload、喂给模型的提示与工具描述、终端呈现）。实现后须在 README 差异清单与 parity-map 中显式登记为"相对基线的有意新增"，并说明其不影响 parity 判定。

**裁决状态（2026-08-01）**：两项能力及 Slynk 依赖均已批准；批准不授权
提前施工。Part B 完成 `v0.84.0` 对齐并复审本文 object ID 后，方可按提案
实现。`:tool-call-error` 是获批的第 34 个扩展事件，收尾须重算 export SHA、
同步 architecture/README 并重新冻结事件全集。Slynk 依赖须登记为独立的
“显式启用的调试服务”类目，并落实空临时 `HOME` 构建/测试回归。

## 五、Part E：首个正式发布

1. 依据 goal 9 Part E 的 CHANGELOG 与单一版本号来源，产出首个正式版本（建议 `0.2.0`，理由写入报告）。
2. **版本标识必须写明所对齐的上游发布版本**，形式为 `cadr 0.2.0 · aligned with pi vX.Y.Z`（Part B 所锁 tag）。该标识出现在 `--version` 输出、README 头部、CHANGELOG 条目与 Release 说明中，四处一致且来源单一。
3. `git tag` 与 GitHub Release：**tag 名、版本号与是否发布由用户确认后执行**，不得自行发布。
4. Release 附：构建说明、验证等级总表（哪些 provider 是 live 验证、哪些是 fixture 对拍）、差异清单、对齐的上游 tag 与 commit hash、致谢与免责。
4. 文档终稿检查：README、architecture、parity-map、visual-parity、dependency-audit、open-questions 全部与实现同步。

## 六、验收标准

1. Part A：私有仓库存在、分支与 tag 齐全、clone 后能构建；无凭据泄漏。
2. Part B：新基线**为上游发布 tag**（tag 名与 hash 均已记录）；全量 `C` 或经裁决 `N/A`；fixture 重生成差异逐条有交代；新 TUI 功能已入视觉对齐表与 A/B 清单。
3. Part C：CI 在远程真实跑绿，链接与差异说明齐备。
4. Part D：提案经用户逐项裁决；获批项实现后既有可观察行为零变更（以 payload 对拍与运行时快照证明），差异清单已登记。
5. Part E：版本号单一来源、CHANGELOG 完整、Release 内容齐备且经用户确认后发布。
6. 全量测试只增不减、全绿；每 Part 独立提交序列与报告章节（含 token 与耗时）。

## 七、原则

- 测试先行；冻结纪律与 object ID 对照贯穿全程。
- **验证脚本不得以规范化、改写输入或弱化断言的方式取得通过**（goal 8 补正的教训）。
- **断言必须覆盖内容本身而非仅结构**：流式文本须有"组装后逐字符等于原文"的等价断言；provider × 能力矩阵须逐项覆盖；工具与 overlay 的完整文案须逐字快照（goal 9 Part B 三轮教训）。
- 完成 Part E 后暂停，等待用户终局验收。
