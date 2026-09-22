# Goal 26：pi 基线推进至 v0.87.0

> **状态：** 进行中。用户 2026-09-22 要求把钉点从已发布的 v0.86.1 推到已发布的 v0.87.0。不宣布 Goal 20、24 或 25 完成。G.17 保持 `missing`。`version.sexp` 仍是 `0.2.0`，直到这一版对齐被接受。Goal 20 invent 保持 `paused=true`。
>
> **自：** `13cbf77df2396303013a41646bcfa77b4271ae56` · `v0.86.1` +0
> **目标锚点：** `16787ad5b2dc748047f314ca1bfe7708f30f54f3` · `v0.87.0` +0（pi tag `v0.87.0`，提交说明 `Release v0.87.0`，2026-09-21 18:31:52 +0200）

## 差量

测量 2026-09-22：

```sh
git rev-list --count \
  13cbf77df2396303013a41646bcfa77b4271ae56..16787ad5b2dc748047f314ca1bfe7708f30f54f3
git diff --stat \
  13cbf77df2396303013a41646bcfa77b4271ae56..16787ad5b2dc748047f314ca1bfe7708f30f54f3 \
  -- packages/coding-agent packages/tui packages/ai
```

18 个提交。上述三包 83 个文件，+4210 / −453 行。

## 范围

机械钉点先落地。用户可见增量与枚举仍待跟进。v0.86.0 与 v0.86.1 上尚未落地的缺口仍然有效。本钉点不把它们勾掉。不新造 intentional-difference 类。不追 `main`。

发布说明是 [v0.87.0](https://github.com/earendil-works/pi/releases/tag/v0.87.0)。
