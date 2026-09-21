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
| Meta Muse：`/login meta` 与 `META_API_KEY` | 未做 |
| `/bug` 保留粘贴诊断里的换行 | 未做 |
| 用户取消和可重试的 provider 失败不提示 `/bug` | 未做 |
| 无显示环境的剪贴板回退到 OSC 52 | 未做 |
| 继承的 z.ai `Prompt too long` 视为上下文溢出 | 未做 |
| Cerebras 不再宣称 `supportsStrictMode` | 未做 |
| Node compile cache | 不移植。没有对应的 Lisp 行为 |

Goal 24 在 v0.86.0 上还没勾完的用户可见缺口仍然有效。本钉点不把它们勾掉。

## 速度

一刀一个 PR。聚焦测试加上这刀碰到的门禁。完整 `./scripts/verify.sh` 只在钉点提交和一轮刀收束时跑，不在每一刀上跑。性能证据文件的 `source_revision` 随钉点改戳，数字没有按 v0.86.1 重测。

模型数据包 `@earendil-works/pi-ai@0.86.1`，tarball SHA-256 `f3c35bf3c606b09f62ba92d2c7c89e63e0ca18075470102d5565684c524b7efd`。
