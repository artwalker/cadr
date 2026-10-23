# GAP-11 上游用例对应

范围是 v1.4.0 的 Anthropic workload identity federation。断言对着 `git show v1.4.0:<path>`，以及本机 `@anthropic-ai/sdk@0.129.0`（`/tmp/cadr-render-diff-pi-4a080252f/node_modules/@anthropic-ai/sdk`）。pi 把联邦配置交给这个 SDK，自己不实现令牌缓存。

## 源码行为（没有单独的 `it`）

`packages/coding-agent/docs/providers.md` 第 69 行。三个变量都在就换短期访问令牌，SDK 自己刷新并重读身份令牌文件。`ANTHROPIC_SERVICE_ACCOUNT_ID` 和 `ANTHROPIC_WORKSPACE_ID` 有值才带上。

SDK `src/lib/credentials/token-cache.ts`。剩余超过 120 秒不交换。剩余大于 30 秒且不超过 120 秒时返回旧令牌，后台再交换。剩余不超过 30 秒阻塞交换并重读文件。`invalidate` 把 `nextForce` 设为真并清掉缓存。`doRefresh` 成功只写入新令牌，不改 `nextForce`。顾问交换失败后 `ADVISORY_REFRESH_BACKOFF_IN_SECONDS`（5）内不再调用 provider。

SDK `src/client.ts` 的 `prepareRequest`。token cache 且没有 apiKey 时，把 `oauth-2025-04-20` 追加到 `/v1/messages` 的 `anthropic-beta`。`shouldRetry` 在 401 时调用 `invalidate`。pi 的 `packages/ai/src/api/anthropic-messages.ts` 把 `maxRetries` 设为 0，所以当前请求失败，下一次 `getToken` 仍强制再交换。

SDK `src/lib/credentials/credential-chain.ts`。只有环境变量、没有 profile 文件时不写磁盘凭证缓存。profile 文件上的 `credentials_path` 不在这一行。

本机 Node 对 `lib/credentials/token-cache.js`。第一次 `tok-1`。顾问窗口内第二次仍是 `tok-1`，后台交换不带 `forceRefresh`。`invalidate` 之后，后台写回的令牌剩余 3600 秒，第三次仍是 `tok-3`，这次调用带 `forceRefresh: true`。交换次数是 3。

| 行为 | FiveAM | 状态 |
|---|---|---|
| 三个变量都在才配置；缺一个就不配置 | `anthropic-federation-is-absent-when-a-required-variable-is-missing` | 已覆盖 |
| 服务账号可缺；workspace 有值才放进交换体 | `anthropic-federation-treats-service-account-as-optional`、`anthropic-federation-sends-optional-service-account-and-workspace`、`anthropic-federation-passes-workspace-id-when-set` | 已覆盖 |
| 剩余超过 120 秒，三次消息只交换一次 | `anthropic-federation-exchanges-the-identity-token-once` | 已覆盖 |
| 剩余大于 30 秒且不超过 120 秒：当次仍用旧令牌，后台重读身份令牌文件再交换；写回后下一次用新令牌 | `anthropic-federation-refreshes-in-the-background-inside-the-advisory-window` | 已覆盖 |
| 剩余不超过 30 秒（含拨过整个 `expires_in`）阻塞交换并重读文件 | `anthropic-federation-rereads-the-identity-token-after-expiry` | 已覆盖 |
| 消息 401 清缓存。当前请求失败。剩余仍超过 120 秒时，下一次强制再交换并重读文件 | `anthropic-federation-exchanges-again-after-a-401` | 已覆盖 |
| 顾问窗口的后台交换在 401 清缓存之后才写回。`nextForce` 仍为真。下一次是第三把令牌，并重读当时的身份令牌文件。写回的第二把令牌剩余超过 120 秒，也不能拿来应付这次请求 | `anthropic-federation-exchanges-again-when-advisory-writeback-follows-a-401` | 新增 |
| 顾问交换失败后 5 秒内不再打令牌端点，继续用旧 Bearer。满 5 秒后再后台交换。成功后下一次用新令牌 | `anthropic-federation-backs-off-after-an-advisory-exchange-failure` | 新增 |
| `/v1/messages` 的 `anthropic-beta` 带 `oauth-2025-04-20`。pi 的 mock 测试锁的是 `createParams.betas` 不含这个值；真实 SDK 在 `prepareRequest` 里追加 | `anthropic-federation-exchanges-the-identity-token-once`，重叠用例也检查第三次消息 | 已覆盖。对着 SDK `prepareRequest`，不是 mock 的 `createParams.betas` |
| 明文且非 loopback 的令牌端点拒绝发送断言 | `anthropic-federation-refuses-a-cleartext-token-endpoint` | 已覆盖。SDK `requireSecureTokenEndpoint` |
| 环境变量这条链不写磁盘凭证文件 | 无同名锁 | 范围外。SDK 写明 env-only 跳过磁盘缓存。上游两个 federation 测试都只设环境变量，没有 profile 文件 |

## `packages/ai/test/anthropic-federation.test.ts`

9 条 `it`。

| 用例 | FiveAM | 状态 |
|---|---|---|
| `resolves the federation variables as provider env with no request auth` | `anthropic-federation-resolves-provider-env-without-request-auth` | 已覆盖。`auth` 为空，source 是 `workload identity federation`，三个变量都在 env 里 |
| `passes ANTHROPIC_WORKSPACE_ID through when set` | `anthropic-federation-passes-workspace-id-when-set` | 已覆盖 |
| `is not configured when a federation variable is missing` | `anthropic-federation-is-absent-when-a-required-variable-is-missing` | 已覆盖 |
| `treats ANTHROPIC_SERVICE_ACCOUNT_ID as optional, like the SDK` | `anthropic-federation-treats-service-account-as-optional` | 已覆盖。缺服务账号仍配置，交换体不带 `service_account_id` |
| `keeps API key and auth token precedence over federation` | `anthropic-federation-keeps-key-and-auth-token-precedence` | 已覆盖。`ANTHROPIC_API_KEY` 走 apiKey。`ANTHROPIC_AUTH_TOKEN` 走 `Authorization: Bearer`。同测试还锁已保存的 key、显式 key、`ANTHROPIC_OAUTH_TOKEN` |
| `hands the SDK a federation config instead of a key` | `anthropic-federation-exchanges-the-identity-token-once` | 已覆盖交换和 Bearer。`createParams.betas` 不含 `oauth-2025-04-20` 是 mock SDK 的入参；cadr 锁的是真实 HTTP 头会带上这个值 |
| `threads authContext federation variables through Models` | `anthropic-federation-threads-auth-context-through-the-models-runtime` | 已覆盖 |
| `lets an explicit API key win over federation env` | `anthropic-federation-lets-an-explicit-api-key-win` | 已覆盖。不发令牌请求，消息用 `x-api-key` |
| `does not federate other anthropic-messages providers` | `anthropic-federation-does-not-federate-other-anthropic-messages-providers` | 已覆盖 |

同文件没有更多 `it`。

## `packages/ai/test/anthropic-federation-sdk.test.ts`

2 条 `it`。真实 SDK，`expires_in` 3600。

| 用例 | FiveAM | 状态 |
|---|---|---|
| `exchanges the identity token once across requests` | `anthropic-federation-exchanges-the-identity-token-once` | 已覆盖。三次消息，一次 `/v1/oauth/token`，`Authorization` 是 `Bearer federated-token` |
| `does not run the SDK credential chain for header-owned auth` | `anthropic-federation-skips-exchange-for-header-owned-auth` | 已覆盖。请求头已有 `Authorization: Bearer auth-token` 时不交换，消息仍用这把 |

## 已记录的 review-fail

| 记录 | 结果 |
|---|---|
| 消息头没有 `oauth-2025-04-20` | `build-request` 在联邦 Bearer 上追加这个值。`anthropic-federation-exchanges-the-identity-token-once` 断言消息头含它 |
| 只在剩余不大于 30 秒时再交换 | 120 秒顾问窗口由 `anthropic-federation-refreshes-in-the-background-inside-the-advisory-window` 锁住。30 秒内的阻塞重读由 `anthropic-federation-rereads-the-identity-token-after-expiry` 锁住 |
| 顾问窗口的后台写回盖掉 401 之后的强制再交换 | `anthropic-federation-run-advisory-refresh` 写回时保留当时的 `force-refresh-p`。`anthropic-federation-exchanges-again-when-advisory-writeback-follows-a-401` 锁住第三次交换 |
