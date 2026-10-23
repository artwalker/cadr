# GAP-08 上游用例对应

范围是 v1.4.0 的 ChatGPT 订阅登录和下一轮启动怎么用已保存的凭证。断言对着 `git show v1.4.0:<path>`。`packages/ai/src/auth/oauth/openai-chatgpt.ts`、`packages/ai/src/auth/resolve.ts` 的 `resolveStoredOAuth`、`packages/ai/src/providers/openai.ts` 的 `toAuth` 与分类器过滤、`packages/ai/src/api/openai-responses.ts` 对订阅令牌省略的字段。

## 源码行为（第三次返修点名的，没有单独的 `it`）

`resolve.ts` 的 `resolveStoredOAuth`。已有 oauth 时不再读环境变量。剩余不足 5 分钟才刷新。`openai-chatgpt.ts` 的 `toAuth` 返回 `{ apiKey: credential.access }`。

| 行为 | FiveAM | 状态 |
|---|---|---|
| auth.json 里 `clientId` 为 `oaiapp_issued`、`expires` 为 0、scopes 含 `chatgpt.tokens.use.direct` 时，`resolve-stored-credential` 向 `https://auth.openai.com/api/accounts/oauth/token` POST `client_id=oaiapp_issued`，返回的 access 成为 `gpt-5.5` 的 apiKey，auth-source 为 `:oauth`，可用模型含 openai。认证状态仍是 `(:type :oauth :source "stored")`，且检查状态本身不发 HTTP | `stored-chatgpt-oauth-becomes-the-request-token-on-the-next-start` | 新增 |
| 同一份过期凭证旁边再设 `OPENAI_API_KEY=sk-proj-test`，仍刷新并用 access，不用这把 key | 同上 | 新增 |
| 同时存着 openai-codex 凭证时，`gpt-5.5` 仍走 openai，不改去 Codex | 同上 | 新增 |
| 剩余 10 分钟不发 HTTP，apiKey 是已保存的 access。剩余 60 秒发一次刷新 | 同上 | 新增 |
| 过期且没有 `clientId` 时刷新失败，错误含 `issued client ID`，已保存的 access 不动，不改用 `OPENAI_API_KEY` | 同上 | 新增 |
| 剩余超过 5 分钟、没有 `clientId` 的 openai oauth，apiKey 就是这份 access，HTTP 为 0，`OPENAI_API_KEY` 不覆盖 | `stored-openai-oauth-with-time-remaining-is-the-access-token` | 新增 |
| `/login` 把签发的 `clientId` 和 scopes 写入 auth.json 之后，把 `expires` 写成 0，再经 `resolve-stored-credential` 用这份 `clientId` 刷新 | `chatgpt-login-writes-issued-client-and-scopes-into-auth-json` | 已覆盖写盘。刷新路径改为走 `resolve-stored-credential` |

## `packages/ai/test/openai-chatgpt-oauth.test.ts`

7 条 `it`。

| 用例 | FiveAM | 状态 |
|---|---|---|
| `registers a user-owned client and stores its issued ID and granted scopes` | `openai-chatgpt-login-stores-the-issued-client-and-scopes`、`chatgpt-login-writes-issued-client-and-scopes-into-auth-json` | 已覆盖 |
| `uses the app's agent name as the name hint` | `openai-chatgpt-login-uses-the-caller-agent-name`。缺省名是 Cadr，锁在 `login-openai-chatgpt-uses-the-subscription-flow` 的 `agent_name_hint=Cadr` | 已覆盖 |
| `rejects registration without an issued client ID` | `openai-chatgpt-login-rejects-a-callback-without-an-issued-client-id` | 已覆盖 |
| `rejects a token response that did not grant direct token use` | `openai-chatgpt-login-rejects-a-grant-without-direct-token-use` | 已覆盖 |
| `requires a device ID before starting authorization` | `openai-chatgpt-login-requires-a-device-id-before-authorization` | 已覆盖 |
| `requires refresh responses to rotate the refresh token` | `openai-chatgpt-refresh-requires-a-new-refresh-token` | 已覆盖 |
| `refreshes with the credential's issued client ID and stores replacement scopes` | `openai-chatgpt-refresh-uses-the-issued-client-id`，以及上面的 `resolve-stored-credential` 路径 | 已覆盖 |

同文件没有更多 `it`。源码里的浏览器回调、粘贴地址、端口占用、安装级 UUID 由 `openai-chatgpt-browser-callback-completes-login`、`openai-chatgpt-browser-error-rejects-login`、`openai-chatgpt-manual-callback-errors-match-the-upstream-messages`、`openai-chatgpt-login-fails-when-the-callback-port-is-taken`、`openai-chatgpt-login-requires-a-device-id-before-authorization` 锁住。这些没有对应的上游 `it` 标题，行为在 `openai-chatgpt.ts`。

## `packages/ai/test/openai-responses-chatgpt-sign-in.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `omits request fields that token sharing rejects` | `openai-chatgpt-sign-in-omits-fields-token-sharing-rejects` | 已覆盖。订阅令牌不写 `max_output_tokens`、`temperature`、`prompt_cache_retention`、`prompt_cache_options` |
| `omits prompt_cache_options on models with explicit prompt cache mode` | `openai-chatgpt-sign-in-omits-explicit-prompt-cache-options` | 已覆盖 |

## `packages/ai/src/providers/openai.ts`

`toAuth` 把 access 放进 apiKey。`filterAllModels` 在 oauth 时去掉分类器，同名聊天模型留下。没有单独的 `it`。

| 行为 | FiveAM | 状态 |
|---|---|---|
| oauth 隐藏 `gpt-6-luna` 分类器，同名聊天模型仍在 | `openai-oauth-hides-classifier-models-and-keeps-the-chat-model` | 已覆盖 |
| OpenAI 同时有 API key 和 ChatGPT oauth | `openai-provider-offers-chatgpt-subscription-login`，对应 `oauth-auth.test.ts` 的 `OpenAI exposes ChatGPT OAuth alongside API-key auth` | 已覆盖 |

## `packages/ai/test/oauth-auth.test.ts` 其余 `it`

13 条里上面那 1 条是这一行的。其余 12 条是扩展桶、订阅标记，以及 anthropic、openai-codex、openrouter、xai、github-copilot 的 `toAuth` 和 refresh。范围外。理由相同。它们不决定 ChatGPT 的 `clientId` 刷新。对应行为在 `test/cadr-ai/goal12-auth-test.lisp`、`test/cadr-ai/auth-test.lisp`、`test/cadr-ai/oauth-callback-host-test.lisp`。

## `packages/ai/test/models-runtime.test.ts`

42 条 `it`。和这次返修同一条规则的是存储凭证优先、过期才刷新、检查认证不刷新。ChatGPT 的 `clientId` 与 `OPENAI_API_KEY` 由上面的新增测试锁在 CLI 的 `resolve-stored-credential`。通用运行时的过期刷新锁在 `models-runtime-auth-priority-refresh-and-availability`。

| 用例 | FiveAM | 状态 |
|---|---|---|
| `resolves auth: stored credential owns the provider, ambient only when nothing stored` | `stored-chatgpt-oauth-becomes-the-request-token-on-the-next-start`、`stored-openai-oauth-with-time-remaining-is-the-access-token` | 新增。锁的是 openai 的 CLI 路径。样例提供方不是 `p1` |
| `checks provider auth without refreshing OAuth and filters available models` | `stored-chatgpt-oauth-becomes-the-request-token-on-the-next-start` 在发 HTTP 前断言认证状态，刷新后 `gpt-5.5` 进入可用模型。通用过期刷新不在 check 时发生，锁在 `models-runtime-auth-priority-refresh-and-availability` | 已覆盖这条规则。样例提供方不是 `ambient` / `oauth` |
| `refreshes expired oauth credentials and persists the rotated credential` | 同上，刷新后的 access 写回 auth.json，下一次 `resolve-stored-credential` 读到 `access-token` | 已覆盖 |
| `refreshes oauth credentials with less than five minutes remaining` | 同上，剩余 60 秒刷新，剩余 10 分钟不刷新 | 新增 |
| `valid oauth tokens resolve without touching modify` | 剩余 10 分钟时 HTTP 为 0，文件里的 access 仍是 `stale-access` | 新增 |
| `a stored credential without a matching handler blocks ambient fallback` | 无同名锁 | 范围外。openai 有 oauth 处理器。这条测的是只有 apiKey 处理器时存了 oauth |
| `rejects with code oauth when refresh fails, preserving the stored credential` | 没有 `clientId` 的过期凭证失败后 access 仍是 `stale-access`，错误含 `OAuth refresh failed` | 已覆盖失败后保留凭证。错误类型是 `authentication-error`，不是 Models 的 `oauth` 代码 |
| `honors a caller's longer OAuth minimum validity` | 无 | 范围外。CLI 这条路径的下限是 5 分钟，没有调用方把窗口拉到 30 分钟 |
| `serializes concurrent OAuth refreshes through store.modify (no double refresh)` | 无同名锁 | 范围外。这次返修的探针是单次启动，不是两个并发 `getAuth` |
| `uses explicit request api key and env during provider auth resolution` | 显式 `--api-key` 仍优先，原有 `provider-config-resolves-registry-config-and-cli-precedence` 锁 CLI key。环境变量在已有 oauth 时不优先，由新增测试锁 | 已覆盖环境变量让位。显式请求 key 不是这次的失败记录 |

其余 32 条是目录枚举、动态模型、取消、流和错误包装。范围外。理由相同。它们不决定 ChatGPT 凭证在下次启动时怎么变成访问令牌。`test/cadr-ai/models-runtime-test.lisp` 已锁通用运行时的注册、刷新和显式 key。

## 已记录的 review-fail

| 记录 | 结果 |
|---|---|
| `/login` 写入 auth.json 时丢掉签发的 client id 和 scopes | `credential-with-provider` 复制 metadata。`chatgpt-login-writes-issued-client-and-scopes-into-auth-json` 读回 `clientId` 和 `chatgpt.tokens.use.direct` |
| 该测试读回文件后直接调用 `refresh-openai-chatgpt-oauth-credential` | 现在先把 `expires` 写成 0，再调用 `resolve-stored-credential` |
