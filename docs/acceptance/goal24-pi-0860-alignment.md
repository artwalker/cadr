# Goal 24：pi 基线推进至 v0.86.0

> **状态：** 进行中。用户 2026-09-20 裁决把钉点从 v0.85.1 推到已发布的 v0.86.0。不宣布 Goal 20 完成。G.17 保持 `missing`。
>
> **自：** `d981de122` · `v0.85.1` +0
> **目标锚点：** `ecac0a9c4edad3dac5d9f8b40e0c7db7a56471fc` · `v0.86.0` +0（pi tag `v0.86.0`，提交说明 `Release v0.86.0`，2026-09-20 01:00:41 +0200）

## 为什么单独开 goal

机械钉点已落到 **v0.86.0**（`BASELINE` 第一列 `ecac0a9c4edad3dac5d9f8b40e0c7db7a56471fc`）。上游发布于 2026-09-19。相对旧钉 `d981de122` 测得 **164** 个提交。`packages/coding-agent`、`packages/tui`、`packages/ai` 合计 **350** 个文件，**+16816 / −6195** 行。用户可见增量与枚举仍在进行。

测量命令（2026-09-20）：

```sh
git rev-list --count \
  d981de1229ef899957bbe968bc8dcda02a21f477..ecac0a9c4edad3dac5d9f8b40e0c7db7a56471fc
git diff --stat \
  d981de1229ef899957bbe968bc8dcda02a21f477..ecac0a9c4edad3dac5d9f8b40e0c7db7a56471fc \
  -- packages/coding-agent packages/tui packages/ai
```

在旧钉点上继续做用户可见对齐，render-diff 和源账本对照的是过时的 pi。钉点取已发布的 **v0.86.0**，不追 `main`。

v0.85.1 上尚未落地的用户可见缺口仍然有效。新钉点不把它们勾掉。

## 范围

| 在范围内 | 不在范围内 |
|---|---|
| 机械锚点：`BASELINE`、`scripts/set-baseline.sh`、fixture `baselineCommit` | Goal 20 invent / pair 燃尽。G.17 不标 `met` |
| `render-diff` 基线 checkout 重建，以及 `scripts/render-diff.py` 里的 `PI_AI_MODEL_DATA_PACKAGE` / `PI_AI_MODEL_DATA_SHA256` | 把 Node 原生 `.node` 二进制抄进 Lisp |
| `enumerate-baseline-diff.py` 与 `check-source-parity-drift.sh` 的处置 | 为过关而抬 pairing ceiling，或新造 intentional-difference 类 |
| 下表用户可见增量。每一项要么有可重放的行为证据，要么是用户已经裁过的例外 | 与本 bump 无关的重构 |

用户 2026-09-20 裁决本 bump。`set-baseline.sh` 已把 `docs/development-policy.md` 的钉点句改成 `v0.86.0 (+0, ecac0a9c4)`。

## v0.85.1 → v0.86.0 用户可见增量

发布说明是 [v0.86.0](https://github.com/earendil-works/pi/releases/tag/v0.86.0)。下表是必须跟进或裁决的面。完整增量以机械枚举为准，不得只靠本表。

| 上游能力 | cadr 动作 |
|---|---|
| Prompt cache warming（长工具运行，以及可选的空闲刷新） | https://github.com/artwalker/cadr/pull/771 。全局 `cacheWarming`（默认 `streaming`）。预热调度、转录提示、`cache_warming_decision` 仍 open |
| `/bug`。脱敏诊断、可选转录或 ZIP、Radius 上传或导出、`pi.bug-report` 条目、崩溃公告 | partial：注册 + 脱敏 + 本地 ZIP（FiveAM）。Consent / Radius / 崩溃公告仍 open |
| 转录保留中途 system prompt 与 tool 变更（`before_agent_start`） | https://github.com/artwalker/cadr/pull/774 、https://github.com/artwalker/cadr/pull/775 、https://github.com/artwalker/cadr/pull/776 、https://github.com/artwalker/cadr/pull/777 。replay + session JSON + turn-prep 发射 + stream 入口 TranscriptContext。各 provider 原生 mid-convo 发射仍经 coerce 投影 |
| 离线 Radius 模型目录。缓存与在线目录可叠加。默认 `balanced` | https://github.com/artwalker/cadr/pull/773 |
| 按模型的 `reserveTokens` / `keepRecentTokens`（`compaction.modelOverrides`） | https://github.com/artwalker/cadr/pull/765 |
| 分支摘要、压缩摘要、skill 调用条目的点击折叠 | https://github.com/artwalker/cadr/pull/768 |
| `ctx.modelRegistry.stream()` / `streamSimple()` | https://github.com/artwalker/cadr/pull/770 |
| `compat.allowedFallbackModels` | https://github.com/artwalker/cadr/pull/759 、https://github.com/artwalker/cadr/pull/766 。自定义模型请求名单；内置 `modelOverrides` 替换目录字段 |
| `pi.on()` 返回取消订阅。派发中增删的处理器作用于下一次派发 | https://github.com/artwalker/cadr/pull/758 |
| `user_bash` 失败即停。`undefined` 才继续传播 | https://github.com/artwalker/cadr/pull/757 |
| 自定义 provider 的流输入从 `Context` 改为 `TranscriptContext` | https://github.com/artwalker/cadr/pull/777 （structs / normalize 见 https://github.com/artwalker/cadr/pull/774）。wire 适配器暂经 `coerce-provider-request-context` 投影 |
| `ToolCall.arguments` 与 `ToolResultMessage.details` 限 JSON 值 | https://github.com/artwalker/cadr/pull/772 |
| 压缩、分支摘要、重试的 spinner 进入编辑器边框 | https://github.com/artwalker/cadr/pull/767 |
| 内置 `read` / `bash` / `powershell` / `edit` / `write` 默认 strict-prefer JSON schema。扩展可关 | https://github.com/artwalker/cadr/pull/760 |
| Bash / PowerShell 时长至少一分钟时写成「分 + 秒」 | https://github.com/artwalker/cadr/pull/756 |
| `--resume` 按 mtime 渐进列出。`--continue` 读到最新匹配头即停 | https://github.com/artwalker/cadr/pull/762 、https://github.com/artwalker/cadr/pull/763 。`--continue` mtime 早停；`--resume` / session selector 渐进 `partialSessions` |
| 剪贴板改为捆绑的异步辅助程序，保留平台命令与 OSC 52 | https://github.com/artwalker/cadr/pull/769 。本地写失败不退回 OSC 52，并写出具体后端；不移植 `.node` |
| Codex 选择里去掉 GPT-5.4 与 GPT-5.4 mini | https://github.com/artwalker/cadr/pull/761 |
| 发布说明里的 provider / session / compaction / RPC 修复 | 枚举后按条处置 |

Node 侧延迟加载 jiti 与虚拟模块、以及 Windows `.node` 二进制，不按文件抄。对应的用户可见行为仍走上表。

## 执行顺序

1. **暂停 Goal 20 invent。** `docs/benchmarks/goal20-queue.json` 的 `paused` 设为 `true`。不新开 invent / pair。
2. **确认对象可解析。** 标签已在本仓对象库。
   ```sh
   git cat-file -e ecac0a9c4edad3dac5d9f8b40e0c7db7a56471fc^{commit}
   ```
3. **机械锚点。**
   ```sh
   scripts/set-baseline.sh ecac0a9c4edad3dac5d9f8b40e0c7db7a56471fc
   python3 scripts/baseline-anchor.py check
   ```
4. **模型数据 pin。** `scripts/render-diff.py` 的 `PI_AI_MODEL_DATA_PACKAGE` 改为 `@earendil-works/pi-ai@0.86.0`。`PI_AI_MODEL_DATA_SHA256` 从该包元数据重算，不要沿用 `af7d1198…`。
5. **删旧 render-diff 缓存。** `rm -rf /tmp/cadr-render-diff-pi-d981de122`。
6. **源与命名集枚举。**
   ```sh
   ./scripts/check-source-parity-drift.sh --repo . \
     --from d981de1229ef899957bbe968bc8dcda02a21f477 \
     --to ecac0a9c4edad3dac5d9f8b40e0c7db7a56471fc \
     --dispositions /tmp/g24-source-dispositions.tsv
   python3 scripts/enumerate-baseline-diff.py \
     d981de1229ef899957bbe968bc8dcda02a21f477 \
     ecac0a9c4edad3dac5d9f8b40e0c7db7a56471fc
   ```
   `--repo` 用能解析这两个提交的 pi 对象库。本仓 `upstream` 已含 `v0.86.0`。
7. **按 disposition 落地。** 一次一个用户可见缺口。断言锁基线，不从 cadr 现状反推。
8. **全门禁。**
   ```sh
   python3 scripts/baseline-anchor.py check
   ./scripts/verify.sh
   ./scripts/test-cl.sh
   ```
9. **恢复 Goal 20。** `paused` 设回 `false`。受影响的 metric 重跑。不把 G.17 标成 `met`。

## 验收

- [x] `BASELINE` 第三列为 `0`，release 为 `v0.86.0`，commit 为 `ecac0a9c4…`
- [x] `python3 scripts/baseline-anchor.py check` 绿
- [x] `enumerate-baseline-diff` 各类 delta 均有 disposition（`docs/acceptance/goal24-evidence/source-dispositions.tsv`，82 行；drift EXIT 0）
- [ ] 上表每一行有测试名，或有用户已经裁过的例外
- [ ] `./scripts/verify.sh` 与 `./scripts/test-cl.sh` 绿
- [ ] `CHANGELOG.md` 记录 `cadr … · aligned with pi v0.86.0 (+0, ecac0a9c4)`（全量对齐后再写；钉点提交只记 pin）
- [ ] Goal 20 `paused=false` 只在钉点与枚举落地之后恢复（钉点期间 `paused=true`）
- [ ] 不标记 G.17 `met`，不宣布 Goal 20 完成

## 与 Goal 20 的关系

钉点与枚举落地之前，不新开 Goal 20 invent / pair。完成后恢复 invent。G.17 仍 `missing`。
