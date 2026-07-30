# GOAL v8：终局路线图进度

固定基线：

- 审计提交：`71efc6f0c1909874ec8c944637a9ae7fc0e2d508`
- 审计 checkout：`/tmp/cadr-parity-71efc6f0`
- Goal 8 开工提交：`664e6b80ae1dc0d67711dc83e92e5e39f7518174`
- 开工账本：`104 C / 0 U / 248 M`

## Part A：Wave 3 provider 与完整 AI 面

状态：完成并提交。

### 落账提交

1. `28ddcf68e97ab553b1184434f51e4a82e7d886f2` — 测试与固定
   fixtures 先行；
2. `c8b418aa65f223490f0313532807ec7b6b2028b6` — 独立协议、认证、
   完整目录、model/image/faux runtime 与公共工具；
3. `e1cce7056e3aefb1602fe19f25642c45c1d353c1` — CLI 按基线
   `openai-codex` 身份解析 OAuth，RPC provider 构造同步新签名，live
   smoke 使用隔离凭据副本。

### 实现证据

- 38/38 baseline text provider IDs，移除非基线内置 `ollama`；
- 固定 npm 包 `@earendil-works/pi-ai@0.83.0`，tarball SHA-256
  `f983c28a21209305ed9c274977e29130fa4d8848df6cdf37e9094d95cc7bc6d4`；
- 37 个静态 provider JSON、1153 个 model；manifest SHA-256
  `68fddb01b38c7abc7c579103da455475593fd788b3dbbf79c04b95bb5a4bb3a7`，
  structure hash
  `5d82f5b1946bdf6d01733aa2a4e4410849c6d44a2ad3038171078c17aed367ce`；
- OpenRouter image 固定目录 40 个 model，fixture SHA-256
  `7a783225dfa4faea2fa53175b5df4af704630b9d54b50b5bcf5560e62d1726bb`；
- Azure Responses、Bedrock Converse EventStream/SigV4、Vertex
  ADC/service-account RS256、Mistral Conversations、OpenAI Codex Responses
  和 `pi-messages` 均有独立 request/response/error/auth 测试；
- model runtime 覆盖 provider mutation、credential priority/refresh、
  availability/filter/dispatch；另有 faux provider、完整 image generation、
  context/overflow/retry/schema/UUID 行为；
- SSE 请求继续显式禁用 read timeout，并由
  `SSE-REQUEST-EXPLICITLY-DISABLES-READ-TIMEOUT` 门禁。

### Live 门控等价及重分类

按用户裁决，离线确定性行为仍逐文件从严；基线 live block 按凭据可用性
同构门控。本机实际运行并通过：

```text
./scripts/live-deepseek-smoke.sh
live smoke: DeepSeek Chat Completions streaming passed

./scripts/live-openai-oauth-smoke.sh
OAuth live smoke: OpenAI Codex Responses streaming passed
```

其他 provider 凭据均不可用，相关 live block 依基线门控跳过；本地未部署的
Ollama、LM Studio 和 llama.cpp 同样跳过，fixture 不冒充 live。

该裁决使以下含 live-gated block 的文件可在离线行为完整后由 `M` 转 `C`：

`abort.test.ts`, `anthropic-eager-tool-input-e2e.test.ts`,
`anthropic-long-cache-retention-e2e.test.ts`,
`anthropic-opus-4-8-smoke.test.ts`, `anthropic-thinking-disable.test.ts`,
`anthropic-tool-name-normalization.test.ts`, `bedrock-thinking-payload.test.ts`,
`cache-retention.test.ts`, `context-overflow.test.ts`,
`cross-provider-handoff.test.ts`, `empty.test.ts`,
`google-thinking-disable.test.ts`, `image-tool-result.test.ts`,
`images.test.ts`, `interleaved-thinking.test.ts`,
`openai-codex-cache-affinity-e2e.test.ts`,
`openai-responses-cache-affinity-e2e.test.ts`,
`openai-responses-reasoning-replay-e2e.test.ts`,
`openai-responses-tool-result-images.test.ts`,
`openrouter-cache-write-repro.test.ts`, `responseid.test.ts`,
`stream.test.ts`, `tokens.test.ts`, `tool-call-id-normalization.test.ts`,
`tool-call-without-result.test.ts`, `total-tokens.test.ts`,
`unicode-surrogate.test.ts`, `xhigh.test.ts`,
`xiaomi-token-plan-ams-anthropic-empty-signature-smoke.test.ts`,
`zen.test.ts`.

验证等级仍独立标注：只有 DeepSeek 与 Codex OAuth 为 `live-proven`，其余为
`fixture`。Part A 后 AI 为 `120 C / 0 U / 0 M`，全仓为
`224 C / 0 U / 128 M`。

### 机械验证

```text
./scripts/test-cl.sh
cadr-ai     641/641
cadr-agent  488/488
cadr-tui    582/582
cadr-cli    277/277
total       1988/1988

./build.sh
cadr build: SBCL lacks sb-core-compression; building an uncompressed image.

./cadr --version
cadr 0.1.0
```

构建产物：`cadr`，61,710,696 bytes，mode `0755`。

### 冻结与依赖对照

Part A 仅解冻 `src/cadr-ai`、`test/cadr-ai`、`cadr-ai.asd` 及所需 CLI
provider 粘合点。TUI、extension、agent tool 与 CLI tool 冻结路径相对开工
提交逐项 object ID 一致；`git diff 664e6b80...HEAD -- <冻结路径>` 为空。
没有新增第三方依赖：HMAC-SHA256 为预裁的纯 Lisp 实现，RS256 使用既有
`cl+ssl`/OpenSSL 例外。

Goal meter 收尾快照：`1,526,490` tokens，`4,609` 秒（累计值）。
