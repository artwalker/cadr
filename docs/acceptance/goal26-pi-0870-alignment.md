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

发布说明是 [v0.87.0](https://github.com/earendil-works/pi/releases/tag/v0.87.0)。下表是必须跟进的面。完整增量以机械枚举为准。

| 面 | 处置 |
|---|---|
| 追加式 context edit，省略或替换单条消息而不改写历史 | `context-edit-omits-a-message-without-rewriting-history`。`session-append-context-edit` 追加编辑；nil 从后续 `session-messages` 省略，字符串替换内容；原条目仍在 |
| `turn_end` 与 `agent_before_settle` 可返回 entries 并要求下一轮请求 | 未开始 |
| `context_with_system` 在完整转录上变换 system 消息 | 未开始 |
| 按模型配置图片输入缩放 | https://github.com/artwalker/cadr/pull/864 。`model-image-input-limits-shrink-tool-result-images`。`input-limits` 的 resize 覆盖 2000x2000 默认，并用于进入历史的工具图片 |
| 去掉 `shouldStopAfterTurn`，改用 `finishTurn` | `finish-turn-end-stops-the-run` 与 `finish-turn-continue-requests-another-provider-turn`。`:end` 停住；`:continue` 在没有工具和 steering 时再请求一轮；错误和中止仍直接结束 |
| `context` 处理器不再看见 system 消息，请求仍恢复 prompt 与工具声明 | 未开始。与 v0.86.1 上未落地的 system-message 栈一起做 |
| 未知 OpenAI 兼容 Chat Completions 端点默认不发 strict 工具 schema | https://github.com/artwalker/cadr/pull/856 。`unknown-openai-completions-endpoint-is-not-strict`。未知 provider 默认不发 strict；内置厂商保持原默认；显式 `:supports-strict-mode` 仍优先 |
| `/bug` 离线只写本地 zip，不上传 | 未开始 |
| 过期的 prompt-cache warming 不再补刷新 | 未开始 |
| 崩溃栈里标出已加载扩展 | `crash-stack-names-the-loaded-extension`。致命错误的用户消息附上 `cadr -ne` 提示 |
| 以 `GIF` 开头但不是 `GIF87a`/`GIF89a` 的文本不当成图片 | `gif-image-detection-requires-a-complete-signature`。`detect-image-mime-type` 只认完整签名 |
| 坏掉的 prompt template frontmatter 要报资源警告 | `malformed-prompt-frontmatter-is-a-resource-warning`。缺冒号的 frontmatter 不加载模板，并给出 `:parse-failed` |
| compaction 可用 `null` keep 边界 | `compaction-null-keep-boundary-uses-its-own-id`。`first-kept-id` 为 nil 时记下本条 compaction 的 id |
| 滚动条隐藏时 jump-to-end 标签不移位 | `alt-screen-jump-label-column-ignores-scrollbar-visibility`。标签按整行居中，滚动条只裁切末列 |

v0.86.0 与 v0.86.1 上尚未落地的缺口仍然有效。
