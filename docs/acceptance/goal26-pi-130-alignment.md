# Goal 26：pi 基线推进至 v1.3.0

> **状态：** 进行中（钉点改靶）。用户 2026-10-20 明确要求从已发布的
> v0.87.0 改钉到已发布的 **v1.3.0**（major leap）。不宣布 Goal 20、24 或 25
> 完成。G.17 保持 `missing`。`version.sexp` 仍是 `0.2.0`，直到这一版对齐被接受。
> Goal 20 invent 的 `paused` 置为 `true`，直至机械钉点与门禁可跑。
>
> **自：** `16787ad5b2dc748047f314ca1bfe7708f30f54f3` · `v0.87.0` +0
> **目标锚点：** `71023aec1546d6d677a65669c5665c0927ce0dd0` · `v1.3.0` +0
> （pi tag `v1.3.0`，提交说明 `Release v1.3.0`，2026-10-15 20:57:27 +0200）
>
> **作废：** 原 `docs/acceptance/goal26-pi-0870-alignment.md` 与 leftover-PR
> 逐条落地法。分支 `goal26-pin-v0870` / PR 855 保留为历史，不 merge、不继续追。

## 差量

测量 2026-10-20：

```sh
git rev-list --count \
  16787ad5b2dc748047f314ca1bfe7708f30f54f3..71023aec1546d6d677a65669c5665c0927ce0dd0
git diff --stat \
  16787ad5b2dc748047f314ca1bfe7708f30f54f3..71023aec1546d6d677a65669c5665c0927ce0dd0 \
  -- packages/coding-agent packages/tui packages/ai
```

482 个提交。上述三包约 722 个文件，+54420 / −39668 行。中间含 v0.87.1、
v0.99.x、v1.0.0–v1.2.0。发布说明入口：
[v1.3.0](https://github.com/earendil-works/pi/releases/tag/v1.3.0)、
[v1.0.0](https://github.com/earendil-works/pi/releases/tag/v1.0.0)。

## 方法（major-leap，取代 leftover-PR）

v0.87.0 时代的「按 leftover PR 逐条 cherry-pick」对 ~482 commits / 1.x 太慢，
且 PR 队列相对 v1.3.0 tip 已过时。本目标改用：

1. **机械钉点**：`BASELINE` → `71023aec…` / `v1.3.0` +0；
   `PI_AI_MODEL_DATA_*` → `@earendil-works/pi-ai@1.3.0`；
   fixture `baselineCommit` 与身份行跟 `set-baseline.sh`。
2. **机械枚举**：`enumerate-baseline-diff.py` +
   `check-source-parity-drift.sh` 处置写在
   `docs/acceptance/goal26-evidence-v130/`。
3. **按面落地**：以枚举类与发布说明里的用户可见面为队列
   （agent loop / providers / TUI / settings schema / MCP / session），
   每面一个可验证单元；不把未合并 leftover PR 当权威顺序。
4. **保留仍有效的 WIP**：Cerebras bodyless 400/413 overflow 与 v1.3.0
   `overflow.ts` 的 `CEREBRAS_BODYLESS_OVERFLOW_PATTERN` 一致，保留在钉上。
5. **不新造 intentional-difference 类**；不追 `main`；CADR_* only。

### 源文件处置摘要

`source-dispositions.tsv` 共 586 行 A/D/R：

| 桶 | 约数 | 处置 |
|---|---|---|
| 范围外包（durable/chord/mcp/codemode/…） | 437 | 本钉不 port |
| coding-agent/tui/ai 新增 | 75 | open；对齐前必须 port 或裁决 |
| coding-agent/tui/ai 删除 | 73 | open；对齐时 drop/rewrite |
| ai oauth-page 重命名 | 1 | open；改映射 |

### 枚举注意

`settingsKeys` / `themeTokens` 的大规模「removed」在 v1.3.0 上很可能是
枚举器仍按旧 interface 形状抽取、而上游已迁到 TypeBox
`settings-schema.ts` 导致的假阳性。落地前须重解析；不得把整表当真实删除。

真实新增命名集（摘录）：CLI `--no-mcp`；扩展事件
`mcp_servers_change`、`provider_stream_event`（移除 `before_agent_start`）；
`PI_PROGRAM_STATUS`；`publicApiExportCount` 36→44；错误类
`McpSignInCancelledError`。

## 必须跟进的用户可见面（首批；完整以枚举为准）

| 面 | 来源 | 处置方向 |
|---|---|---|
| Fullscreen 默认 TUI；`tuiMode` / `--tui-mode regular` | v1.0.0 | done on tip：unset/`*` → fullscreen；仅 `"regular"` → regular；help + settings 文案对齐 |
| `--no-mcp` | 枚举 | done：CLI 标志 + `disabled-builtin-extensions ("mcp")`；MCP builtin 仍薄 |
| `mcp_servers_change` / `provider_stream_event`；去掉 `before_agent_start` | 枚举 | done：两事件入 hook 表 + emit；保留 `before_agent_start` |
| `sessionShareDestination`（`/share` → auto/gist/radius） | v1.3.0 | done：settings + `/share` destination auto/gist/radius |
| 换模型时丢弃他模型 thinking，不改写成可见文本 | v1.3.0 | done：`copy-history-content-block` 跨模型 drop；同模型保留 signed/redacted/非空 |
| Resume 保留会话激活工具；`--tools +/-` 叠加上去 | v1.3.0 | done：usesDefaultTools restore + modifiers；session toolsAdded persist/parse |
| Kimi Coding → Chat Completions + `/v1` base URL | v1.3.0 | done：openai-completions + `/v1`；catalog mid-convo flags |
| OpenAI GPT-6 中途改 thinking 保 cache | v1.3.0 | done：`configuration_update` + 固定 `reasoning.effort`；catalog `supportsMidConvoEffort` |
| Cerebras bodyless 400/413 overflow | v1.3.0 overflow.ts | 已在 tip WIP |
| settings / theme schema 变形 | 枚举假阳性 | 重解析后再列缺口 |

v0.87.0 钉上尚未关闭的缺口与 leftover 行为，在 v1.3.0 上重新对照 tip；
不以旧 PR 是否合并为完成条件。

## 执行顺序

1. 冻结 Goal 20：`goal20-queue.json` `paused=true`。
2. `git fetch upstream --tags`；确认
   `71023aec1546d6d677a65669c5665c0927ce0dd0` 可 `cat-file`。
3. `scripts/set-baseline.sh 71023aec1546d6d677a65669c5665c0927ce0dd0`
4. `scripts/render-diff.py` 中 `PI_AI_MODEL_DATA_PACKAGE` /
   `PI_AI_MODEL_DATA_SHA256` → `@earendil-works/pi-ai@1.3.0` /
   `5343e1639bf343bdc3344df3ad6c31c05a50b68bad07ac6bce10890d4b6b8a61`
5. 删旧 render-diff 缓存：`rm -rf /tmp/cadr-render-diff-pi-16787ad5b`
6. 证据目录：`docs/acceptance/goal26-evidence-v130/`
7. 按面落地；每面 FiveAM / 确定性门禁绿后再推。
8. 全门禁可跑后再把 Goal 20 `paused=false`（不宣布 Goal 20 完成）。

## 硬约束

- `version.sexp` = `"0.2.0"` 直到对齐被接受
- 不标 Goals 20/24/25/26 完成；G.17 保持 `missing`
- 不 merge PR 855；leftover PR 用「已改钉 v1.3.0，勿合」关闭或搁置
- 不 force-push；显式 path staging
- Live probes：仅 xAI；OpenCode 计费失败不是产品缺陷
