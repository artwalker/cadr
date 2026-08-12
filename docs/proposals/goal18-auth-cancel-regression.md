# Goal 18：认证取消屏 pi v0.84.1 回归差异裁决提案（已裁决）

状态：**已裁决（2026-08-12）：路线 A 批准，I05 已落地。** 14 个
auth-cancel 整屏对的 pi 侧在 v0.84.1（`53fa77ccd`）中开始渲染红色
`Error:` 行，cadr 侧继续压制（符合 goal 13 用户既定裁决）。按常设约束
（新增 intentional-difference 类别不得自行决定），本提案给出证据、根因
与两条路线并交用户裁决。

> 落账记录（2026-08-12，用户裁决路线 A 后）：`dispositions.json` 新增
> `I05` 类别（`textCovering=true`，摘要收窄至登录取消路径，点名 pi 侧
> 根因：`packages/coding-agent/src/utils/abort.ts:3` 抛
> `Error("The operation was aborted")`，而
> `interactive-mode.ts:5666` 仅压制 `"Login cancelled"`）；14 键
> （12 条 entries）改挂 `I01/I04/I05` 并配如实 note（删除原先
> "visible text is identical to pi" 之类不实描述）。上游修复该回归后
> I05 退役，这 14 键转回逐字对齐。

## 门禁现状

未打补丁的 `scripts/render-diff.py analyze --tier core` 在干净 fresh
captures 上于第一个漂移键即失败：

```
render-diff: semantic screen pair drifted outside the exact I04 disposition:
overlays-auth-oauth/wide/login-cancelled
```

枚举（临时补丁使 validator 空转）显示除以下 14 个键外全部
`aligned`/`intentional-terminal-protocol`，`missing=[] stale=[]`：

| 键 | 新 pi SHA 前缀 | cadr SHA 前缀 |
|---|---|---|
| overlays-auth-oauth/wide/login-cancelled | `be73e7bc` | `052398f3` |
| overlays-auth-oauth/wide/login-post-cancel | `e5d88edf` | `5a3bca22` |
| overlays-auth-oauth/wide/process-exit | `66c45651` | `819b4c55` |
| overlays-auth-oauth/narrow/login-cancelled | `e13a9f49` | `6c0dd094` |
| overlays-auth-device-code/wide/login-device-cancelled | `c16a148b` | `052398f3` |
| overlays-auth-device-code/wide/login-device-post-cancel | `ae49d51d` | `5a3bca22` |
| overlays-auth-device-code/wide/process-exit | `a5ee1a0f` | `819b4c55` |
| overlays-auth-device-code/narrow/login-device-cancelled | `1dd0f8ad` | `9052a4c6` |
| overlays-auth-browser-callback/wide/login-loopback-cancelled | `eff8c927` | `052398f3` |
| overlays-auth-browser-callback/wide/login-loopback-post-cancel | `627691c0` | `5a3bca22` |
| overlays-auth-browser-callback/wide/process-exit | `118bd255` | `819b4c55` |
| overlays-auth-browser-callback/narrow/login-loopback-cancelled | `acff9fd7` | `9052a4c6` |
| overlays-auth-api-key/wide/api-key-post-cancel | `6cab2b5e` | `5a3bca22` |
| overlays-auth-api-key/wide/process-exit | `02129459` | `819b4c55` |

## 证据

新 pi（`53fa77ccd`）fresh captures 中的可见文本：

```
Error: Failed to login to Render Auth: This operation was aborted
Error: Failed to login to Render Device: This operation was aborted
Error: Failed to login to Render Loopback: This operation was aborted
Error: Failed to save API key for Render Auth: This operation was aborted
```

该错误行在 cancel 屏、post-cancel 屏与 process-exit 屏中持续可见
（wide 与 narrow 均出现）。旧基线 pi（`74caa2649`）同一键无错误行，
直接回到输入框；cadr 侧同样无 `Error:` 行。old-baseline pi 屏与 cadr
屏证据均存在本地 fresh captures 中（`/tmp/g18-gate6/analysis/` 与
`/tmp/rd-core-analysis-enum/`）。

## 根因（pi 侧代码，当前 worktree）

- `packages/coding-agent/src/core/model-runtime.ts:494-511`
  `enqueueCredentialOperation` + `raceWithAbortSignal`：取消经
  `signal.throwIfAborted()`/abort 竞速抛出。
- `packages/coding-agent/src/utils/abort.ts:1-8` `abortReason()` 返回
  `Error("The operation was aborted")`（message 不再是 `"Login cancelled"`）。
- `packages/coding-agent/src/modes/interactive/interactive-mode.ts:5660-5667`
  仅压制 `errorMsg === "Login cancelled"`，新 abort message 落入
  `showError("Failed to login to ...")` 分支。
- 旧基线 `interactive-mode.ts:5246-5248/:5356-5358` 压制
  `"Login cancelled"`（旧代码在各 provider 取消点抛出该字符串）。
- `git log 74caa2649..53fa77ccd` 对 model-runtime/abort 共 7 个提交
  （如 `fed6009cc fix(coding-agent): make model refresh cancellation
  caller-owned`、`a261366bd feat(coding-agent): add auth preflight`）。

## 冲突

这是 pi v0.84.1 的**回归行为**，与 goal 13 用户既定裁决直接冲突：
取消是正常用户操作，不应产生错误级输出；此前 cadr 已按裁决压制
（goal 13 P1-B：取消后直接回输入框、无任何输出）。盲目刷新 disposition
会把 pi 回归烤进门禁；不经裁决新增 intentional-difference 类别则违反
goal 18 目标文本（"新增 intentional-difference 类别须先报 blocked
交裁决，不得自行决定"）。

## 裁决结果（2026-08-12）

- 路线 A 批准：cadr 维持压制取消输出；上述 14 键记为新增
  intentional-difference 类别 `I05`（`textCovering=true`，摘要收窄、
  仅限登录取消），cadr SHA 保持不变。
- 14 条 note 全部改为如实描述，删除任何 "visible text is identical to
  pi" 类表述（对 14 键而言该表述为假——pi 侧有 `Error:` 行，cadr 无）。
- 退役条件：上游修复该回归后，I05 随退役，14 键转回逐字对齐并重抓。

落账已完成（dispositions.json I05 + 12 entries note 改写），full tier
门禁与交付序列继续进行。
