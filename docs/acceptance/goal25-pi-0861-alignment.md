# Goal 25：pi 基线推进至 v0.86.1

> **状态：** 进行中。用户 2026-09-21 裁决把钉点从 v0.86.0 推到已发布的 v0.86.1。不宣布 Goal 24 或 Goal 20 完成。G.17 保持 `missing`。`version.sexp` 仍是 `0.2.0`，直到这一版对齐被接受。
>
> **自：** `ecac0a9c4edad3dac5d9f8b40e0c7db7a56471fc` · `v0.86.0` +0
> **目标锚点：** `13cbf77df2396303013a41646bcfa77b4271ae56` · `v0.86.1` +0

## 差量

测量 2026-09-21：

```sh
git rev-list --count \
  ecac0a9c4edad3dac5d9f8b40e0c7db7a56471fc..13cbf77df2396303013a41646bcfa77b4271ae56
git diff --stat \
  ecac0a9c4edad3dac5d9f8b40e0c7db7a56471fc..13cbf77df2396303013a41646bcfa77b4271ae56 \
  -- packages/coding-agent packages/tui packages/ai
```

12 个提交。上述三包 50 个文件，+1008 / −126 行。`packages/ai` 21 个文件，+561 / −10 行。

## 必须跟进的用户可见面

发布说明是 [v0.86.1](https://github.com/earendil-works/pi/releases/tag/v0.86.1)。

| 面 | 处置 |
|---|---|
| Meta Muse：`/login meta` 与 `META_API_KEY` | https://github.com/artwalker/cadr/pull/754 |
| `/bug` 保留粘贴诊断里的换行 | https://github.com/artwalker/cadr/pull/755 。交互界面还没有调用 `bug-report-hint`，取消和可重试失败的提示抑制还不会出现在屏幕上 |
| 用户取消和可重试的 provider 失败不提示 `/bug` | 决策在 https://github.com/artwalker/cadr/pull/755 。调用点未接 |
| 无显示环境的剪贴板回退到 OSC 52 | https://github.com/artwalker/cadr/pull/753 |
| 继承的 z.ai `Prompt too long` 视为上下文溢出 | https://github.com/artwalker/cadr/pull/751 |
| Cerebras 不再宣称 `supportsStrictMode` | https://github.com/artwalker/cadr/pull/752 |
| Node compile cache | 不移植。没有对应的 Lisp 行为 |

Goal 24 在 v0.86.0 上还没勾完的用户可见缺口仍然有效。本钉点不把它们勾掉。

## 速度

一刀一个 PR。聚焦测试加上这刀碰到的门禁。完整 `./scripts/verify.sh` 只在钉点提交和一轮刀收束时跑，不在每一刀上跑。性能证据文件的 `source_revision` 随钉点改戳，数字没有按 v0.86.1 重测。

2026-09-21 用户要求按团队并行。编排手册对这几个单位的仪式比直接做更慢，所以不建 orch 仓库。五个写者，各一块工作树，从钉点提交切出。`CHANGELOG.md`、`BASELINE`、账本、`version.sexp` 只由主执行者改。不合并 PR。

| 单位 | 分支 | 可写 | 不可写 |
|---|---|---|---|
| Cerebras 不宣称 strict | `goal25-cerebras-strict` | `src/cadr-ai/providers/openai-completions.lisp` 与对应测试 | 其他生产文件，账本 |
| z.ai `Prompt too long` | `goal25-zai-overflow` | `src/cadr-ai/support/overflow.lisp` 与对应测试 | 其他生产文件，账本 |
| `/bug` 换行和提示抑制 | `goal25-bug-report` | `src/cadr-cli/support/bug-report.lisp`，`src/cadr-cli/bootstrap/sessions.lisp`，对应测试 | `clipboard.lisp`，账本 |
| 无显示环境 OSC 52 | `goal25-clipboard-osc52` | `src/cadr-cli/interactive/clipboard.lisp` 与对应测试 | `sessions.lisp`，账本 |
| Meta Muse | `goal25-meta-muse` | 新的 meta provider / oauth 文件，`definitions.lisp`，环境键，对应测试 | `openai-completions.lisp`，`overflow.lisp`，账本 |

Node compile cache 不设写者。没有对应的 Lisp 行为。

模型数据包 `@earendil-works/pi-ai@0.86.1`，tarball SHA-256 `f3c35bf3c606b09f62ba92d2c7c89e63e0ca18075470102d5565684c524b7efd`。
