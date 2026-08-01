# Goal 9 Part C 阶段报告

> 状态：客户端身份差异已按用户批准实施；确定性与真实 OAuth 硬门禁均通过。

## 1. 已批准差异

OpenAI authorize query 与 Codex Responses header 的 `originator` 从基线
`pi` 改为 `cadr`。该字段用于第三方客户端归因，不改变 provider 身份
`openai-codex`、OAuth 参数、凭据存储、Responses payload 或事件语义。

生产值集中于 `src/cadr-ai/oauth.lisp` 的 `+openai-originator+`，authorize URL
与 Responses transport 共同引用，避免两条身份路径再次分叉。

## 2. 测试先行与确定性门禁

先修改断言、保持生产值为 `pi` 的红相：

- `OPENAI-AUTHORIZATION-URL-USES-APPROVED-CADR-ORIGINATOR-DIFFERENCE`：
  `9 checks / 7 pass / 2 fail`，实际 URL 仍为 `originator=pi`。
- `OPENAI-OAUTH-USES-CODEX-URL-AND-APPROVED-CADR-ORIGINATOR-HEADER`：
  `5 checks / 4 pass / 1 fail`，实际 header 为 `pi`。

实现后两项分别为 `9/9` 与 `5/5`。端到端确定性门禁
`LOGIN-OPENAI-TEMP-STORE-DEFAULT-RESOLVER-ROUTES-CODEX-REQUEST` 使用临时 auth、
临时配置及 HTTP stub，证明 `/login openai` 落库为 `openai-codex`，默认路由
不带 provider/model 参数进入 Codex transport，且 header 为 `originator=cadr`；
结果 `12/12`。

对 `test/fixtures/` 与 `scripts/export-ts-payloads.ts` 的审计没有找到
`originator`：现有对拍 fixtures 只序列化请求 body，不包含 authorize URL 或
HTTP headers。因此受影响 fixture 数为 `0`，没有静默改写或漏更 fixture。

## 3. 真实 OAuth 硬门禁

2026-08-01 使用本 Part 新构建的 `./cadr --no-tui` 在同一进程执行：

1. `/login openai` 展示的真实 authorize URL 含 `originator=cadr`；
2. callback 成功，输出 `openai-codex login stored in /root/.cadr/auth.json`；
3. 不传 `--provider` 或 `--model`，发送
   `Reply with exactly CADR_ORIGINATOR_OK and nothing else.`；
4. 实际响应逐字为 `assistant> CADR_ORIGINATOR_OK`；
5. `~/.cadr/auth.json` mode 为 `0600`。

未发生 originator 拒绝，也未回退为 `pi`。

## 4. 收尾证据

- 新增第三方依赖：`0`。
- Part 耗时：约 1 小时，包含等待人工浏览器授权。
- token：产品未提供可审计的精确本 Part token 计数，未伪造估值。
- 提交：本 Part 独立提交。
