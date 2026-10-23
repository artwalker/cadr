# GAP-45 上游用例对应

范围是 v1.4.0 的提供方重试字段和代理重试字段：`packages/coding-agent/src/core/settings-manager.ts` 的 `getRetrySettings` 与 `getProviderRetrySettings`，`packages/ai/src/utils/provider-retry.ts` 的 `retryProviderRequest`，`packages/coding-agent/src/core/sdk.ts` 的 `buildRequestOptions`，`packages/coding-agent/docs/settings.md` 第 129–136 行，以及回归测试 7572。断言对着 `git show v1.4.0:<path>`。

`getRetrySettings` 只读顶层 `retry.maxRetries`，缺省 3（`settings-defaults.ts`）。`getProviderRetrySettings` 只读 `retry.provider.maxRetries`，没写就是 `undefined`。`retryProviderRequest` 第 111 行用 `options.maxRetries ?? 0`，只发一次。`settings.md` 第 133 行写提供方缺省 0，第 136 行写提供方重试会拖住额度错误的处理。`buildRequestOptions` 是 `options.maxRetries ?? providerRetrySettings.maxRetries`，请求里的同名字段优先。`httpIdleTimeoutMs === 0` 才换成 2147483647。显式 `timeoutMs` 0 原样进入请求。

## 源码和文档（没有单独的 `it`）

| 行为 | FiveAM | 状态 |
|---|---|---|
| 没写 `retry.provider.maxRetries` 时请求次数是 1。顶层 `retry.maxRetries` 缺省 3，不进入这次请求 | `goal28-provider-retry-settings-reach-existing-policy`、`goal45-provider-max-retries-does-not-change-agent-retries`、`goal45-timeout-zero-sends-one-request-to-a-blackhole` | 新增 |
| 显式 `timeoutMs` 0 以 0 毫秒进入请求，黑孔监听不 accept 时只连一次，错误含 `timed out` | `goal45-provider-retry-timeout-ms-and-max-retry-delay-ms`、`goal45-timeout-zero-sends-one-request-to-a-blackhole`、`zero-connect-timeout-fails-before-the-socket-waits` | 新增 / 已覆盖 |
| `httpIdleTimeoutMs` 为 0 时超时是 2147483647。未设置提供方超时时用空闲超时。写成 0 保持 0。请求里的同名字段优先 | `goal45-provider-retry-timeout-ms-and-max-retry-delay-ms`、`goal28-http-idle-timeout-reaches-existing-request` | 已覆盖 |
| `maxRetryDelayMs` 缺省 60000，写成 0 保持 0。旧键 `retry.maxDelayMs` 迁进 `provider.maxRetryDelayMs`，provider 里已有的延迟保留 | `goal45-provider-retry-timeout-ms-and-max-retry-delay-ms`、`goal23-max-agent-delay-ms-reaches-the-agent` | 已覆盖 |
| 项目只写 `provider.maxRetries` 时，全局超时和延迟仍在，代理次数仍是顶层缺省 3 | `goal45-provider-retry-timeout-ms-and-max-retry-delay-ms`、`goal28-provider-retry-settings-reach-existing-policy` | 新增 |
| 顶层 `maxRetries` 和 `provider.maxRetries` 同时存在时各走各的。请求里的 `maxRetries` 优先，包括 0 | `goal45-provider-max-retries-does-not-change-agent-retries` | 新增 |
| JSON null 的提供方 `timeoutMs`、`maxRetryDelayMs` 按缺省。0 是写上的值 | `goal45-provider-retry-timeout-ms-and-max-retry-delay-ms` | 已覆盖 |

## `packages/coding-agent/test/suite/regressions/7572-provider-retry-settings-merge.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `preserves global provider settings not overridden by the project` | `goal45-provider-retry-timeout-ms-and-max-retry-delay-ms` 锁全局 `timeoutMs` 30000、`maxRetryDelayMs` 45000，项目 `maxRetries` 2。代理 `:max-retries` 仍是 3 | 已覆盖 |

## `packages/coding-agent/test/sdk-stream-options.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `forwards provider retry settings` | `goal28-provider-retry-settings-reach-existing-policy` 在 `provider.maxRetries` 2 时请求 `:max-retries` 是 2，延迟 60000。`goal45-provider-retry-timeout-ms-and-max-retry-delay-ms` 锁 45000 | 已覆盖 |
| `forwards httpIdleTimeoutMs as timeoutMs for OpenAI Codex` | `goal45-provider-retry-timeout-ms-and-max-retry-delay-ms` 把空闲 1234 写成 `:timeout-ms` 1234 | 已覆盖 |
| `defaults timeoutMs from httpIdleTimeoutMs for all providers` | 同上，以及 `goal28-http-idle-timeout-reaches-existing-request` 的缺省 300000 | 已覆盖 |
| `lets request timeoutMs override httpIdleTimeoutMs for OpenAI Codex` | 同文件请求 `:timeout-ms` 0 盖过设置里的 30000，`:read-timeout` 是 0 | 已覆盖 |
| `forwards websocketConnectTimeoutMs from settings` | `goal28-websocket-timeout-settings-test.lisp` | 范围外：不是 `retry.provider` |
| `lets request websocketConnectTimeoutMs override settings` | 同上 | 范围外：同上 |
| `schedules cache warming after a completed session request` | `goal24-cache-warmer-test.lisp` | 范围外：缓存加温，不读重试字段 |
| `waits for the next request instead of restoring cache warming` | 同上 | 范围外：同上 |
| `forwards provider stream events to extensions` | 无同名锁 | 范围外：扩展事件，不读重试字段 |
| `runs before_provider_headers on assembled headers without forwarding the transform` | 无同名锁 | 范围外：请求头钩子 |

## `packages/ai/test/provider-retry.test.ts`

这六条锁的是 `retryProviderRequest` 在已经拿到 `maxRetries` 之后的退避。设置把次数交给请求的部分在上一节。循环内部的头和句子不在这一行的两次验收里。

| 用例 | FiveAM | 状态 |
|---|---|---|
| `retries retryable provider errors` | `goal45-provider-max-retries-does-not-change-agent-retries` 在 `provider.maxRetries` 1 时发 2 次，2 时发 3 次。`retryable-complete-requests-respect-cap-and-retry-after` 锁可重试错误会再发 | 已覆盖次数。`retry-after-ms` 的 1000 毫秒时钟是范围外：主循环读的是 `retry-after` 秒数 |
| `does not retry errors the provider marks as non-retryable` | `terminal-go-usage-limit-429-is-not-retried`、`nonretryable-complete-request-is-not-retried` | 已覆盖 400 和终端 429 不重试。`x-should-retry: false` 这一头是范围外：两次验收没有列它，分类器循环才读这个头 |
| `does not retry statuses listed in noRetryStatuses` | 无 | 范围外：`noRetryStatuses` 在分类器的 `call-with-classifier-retries`。主提供方循环没有这个参数。两次验收没有列它 |
| `rejects a provider-requested retry delay above the limit` | 无同名句子 | 范围外：`Server requested …s retry delay` 在分类器的 `validate-retry-delay-ms`。主循环超过上限时抛原来的错误。两次验收写明延迟缺省 60000、写成 0 保持 0，没有列这句 |
| `allows disabling the provider-requested retry delay cap` | `goal45-provider-retry-timeout-ms-and-max-retry-delay-ms` 锁 `maxRetryDelayMs` 0 留在请求里 | 已覆盖设置值 0。2 秒 `retry-after` 的假时钟是范围外，理由同上 |
| `aborts a provider-requested retry delay` | 无 | 范围外：等待中的 `AbortSignal`。两次验收没有列它 |

## `packages/ai/test/openai-completions-retry.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `disables SDK retries by default` | `goal45-timeout-zero-sends-one-request-to-a-blackhole` | 已覆盖可观察结果：没写提供方次数时只发一次。cadr 没有第二层 OpenAI SDK 客户端，请求上不会再带一份 `maxRetries: 0` |
| `honors provider retries while keeping SDK retries disabled` | `goal45-provider-max-retries-does-not-change-agent-retries` 在次数 2 时发 3 次 | 已覆盖次数。每次内层客户端仍是 `maxRetries: 0` 是范围外，理由同上 |
| `fails immediately when a provider-requested retry delay exceeds the limit` | 无同名句子 | 范围外：句子在分类器。见 `provider-retry.test.ts` 同名条 |

## `packages/coding-agent/test/settings-manager.test.ts`

`retry settings` 里的 `defaults and overrides agent retry delay cap` 由 `goal23-max-agent-delay-ms-reaches-the-agent` 锁住：缺省 60000，写成 5000 就用 5000，顶层 `maxRetries` 10 留在代理次数上。旧键只迁进 `provider.maxRetryDelayMs`。

`httpIdleTimeoutMs` 的三条（缺省 5 分钟、全局和项目合并、非法值拒绝）由 `goal28-http-idle-timeout-reaches-existing-request` 和 `part-b-config-test.lisp` 锁住。

其余 47 条不读 `retry.provider`，也不读顶层 `retry.maxRetries`。状态是范围外。

| 用例 |
|---|
| `should preserve enabledModels when changing thinking level` |
| `should preserve custom settings when changing theme` |
| `should let in-memory changes override file changes for same key` |
| `creates one global device ID and reuses it in later processes` |
| `should keep local-only extensions in extensions array` |
| `should handle packages with filtering objects` |
| `should reload global settings from disk` |
| `should keep previous settings and report the file path when the file is invalid` |
| `stores slash-separated automatic theme settings separately from fixed theme names` |
| `should collect and clear load errors via drainErrors` |
| `should skip project settings when project is not trusted` |
| `should reload project settings after trust changes to true` |
| `should fail project settings writes when project is not trusted` |
| `should read default project trust from global settings only` |
| `should default invalid project trust settings to ask` |
| `should not create .pi folder when only reading project settings` |
| `should create .pi folder when writing project settings` |
| `maps explicit values and omits auto values` |
| `defaults to streaming and ignores project settings` |
| `persists the mode globally` |
| `should resolve editor commands by precedence` |
| `should fall back to platform defaults` |
| `defaults to fullscreen and persists regular mode` |
| `falls back to fullscreen for unsupported values` |
| `does not recognize the old uiMode setting` |
| `validates and persists fullscreen settings` |
| `persists fullscreen wheel scroll lines` |
| `should default to 1 and persist binary values` |
| `should treat unsupported outputPad values as default padding` |
| `defaults to streaming and persists rendering modes` |
| `falls back to streaming for unsupported values` |
| `should load shellCommandPrefix from settings` |
| `should return undefined when shellCommandPrefix is not set` |
| `should preserve shellCommandPrefix when saving unrelated settings` |
| `loads global defaults and lets project settings replace them` |
| `preserves an empty tool list` |
| `applies +name and -name to the default selection` |
| `layers project modifiers on top of the global selection` |
| `applies project modifiers to the built-in defaults without a global setting` |
| `should return undefined when not set`（`getSessionDir`） |
| `should return global sessionDir` |
| `should return project sessionDir, overriding global` |
| `should expand ~ in sessionDir` |
| `should return undefined when not set`（`getShellPath`） |
| `should return an absolute shellPath unchanged` |
| `should expand ~ in shellPath` |
| `should expand a bare ~ in shellPath` |

`git show v1.4.0:packages/coding-agent/test/settings-manager.test.ts` 里 `it("` 共 51 条。上面 47 条加 `defaults and overrides agent retry delay cap` 和 `httpIdleTimeoutMs` 的 3 条。

## 已记录的 review-fail

| 记录 | 结果 |
|---|---|
| `timeoutMs` 0 把 `:read-timeout` 写成 nil，套接字一直等 | `stream-function-with-http-idle-timeout` 在数值 0 时保留 `:timeout-ms` 0，`:read-timeout` 是 0。`connect-http-stream` 对 `connect-timeout` 0 报 `native-http-timeout`。`zero-connect-timeout-fails-before-the-socket-waits` 与 `goal45-provider-retry-timeout-ms-and-max-retry-delay-ms` |
| 显式 `timeoutMs` 0 仍按提供方重试 3 次，黑孔上 4 次连接 | 没写 `provider.maxRetries` 时请求 `:max-retries` 是 0。黑孔测试断言 1 次且不睡眠。顶层 `maxRetries` 3 留在代理次数上 |
| 项目只写 `provider.maxRetries` 2 时代理次数也变成 2 | 代理 `:max-retries` 仍是 3。请求次数是 2 |
