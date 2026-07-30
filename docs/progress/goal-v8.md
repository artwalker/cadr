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

## Part B：预授权增量已落账，四项待裁

状态：**blocked**。以下只记录预授权范围内已经完成的增量；四项越界事项均未
实现，逐项提案见
[`docs/proposals/goal-v8-part-b.md`](../proposals/goal-v8-part-b.md)。

### 预授权提交

1. `724494fd562d34097c225072ace81771311c58f4` — 固定 Part B 测试与
   fixtures，提交信息注明预裁第 0.5(3)；
2. `36310bfb040674ef43dff421e4e537eb7471ebaa` — agent/session/resource/
   tool/input runtime；六个 lifecycle event 与 provider request hook 限于
   预裁第 0.5(3)；
3. `267b215aa45e488053dd85330d8a9c1106553369` — CLI service primitives；
4. `81b441aec12669ef368670f494a1b28697bb8193` — CLI-owned interactive
   controllers，未修改 `src/cadr-tui` 生产代码；
5. `d0a90f9e009aadcca4f3fb482596c21e4314308b` — REPL/RPC/TUI glue 与
   startup lifecycle wiring。

### 扩展导出锚点修正

预裁第 0.5(3) 的 `before_provider_request` replacement 合约新增公开导出：

```lisp
provider-request-replacement
make-provider-request-replacement
provider-request-replacement-payload
```

因此不能继续宣称 Goal 7 的 export SHA 保持不变。按 Goal 7 的相同取样命令：

```text
sed -n '/#:define-tool/,/#:make-extension-hook-result/p' \
  src/cadr-agent/package.lisp | sha256sum
e89a7f84962c539bfab1645df4867a8f3b587ae46201865abcf9d2b503dc068a  -
```

当前 extension 相关 Git object ID：

```text
89f22526fae6d1395e7af6475e2f78df2a70f86d  src/cadr-agent/extensions.lisp
0d5ff60edf348d23f98bd30a352d0dccafd8877f  src/cadr-agent/package.lisp
dd137c9957abf4b184313206c63182ccbb7bc1c6  test/cadr-agent/extensions-wave3-test.lisp
3f903689bd0f8ac59c4412e8b3d332a26df24cca  src/cadr-cli/extensions.lisp
4c439bf877d1f82d4ca4628ac52ec20ba2c458e4  src/cadr-cli/sdk-services.lisp
28b02f016dea4b235d8ef235fa3c2dbb07c42a26  test/cadr-cli/extensions-test.lisp
```

Goal 7 的三个兼容 fixture SHA 保持不变：

```text
e2548662d773edfa21ecfa3b126b2209404a2b27385e6cd48e1f145a41747442  test/fixtures/extensions/legacy-wave2-api.lisp
6dc3a25271080a59c3380704044c435a0a20a972c5ba19f32cae2acee2649b10  test/fixtures/rpc-process-client.py
c1148870a539dd4a24001da74d17f668b6092bf55d41d845319d5439e3df9486  test/fixtures/extensions/rpc-ui.lisp
```

上述新 export SHA 是预授权增量提交后的当前锚点，不构成对本提案四项的预先
批准。若用户批准第 2 或第 3 项并新增公共导出，关账时必须再次重算、记录和
重冻。
