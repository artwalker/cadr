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

## Part B：完整 coding-agent 行为面

状态：完成并提交。用户已逐项批准
[`docs/proposals/goal-v8-part-b.md`](../proposals/goal-v8-part-b.md) 的四项
裁决；实现严格按提案第 5 节顺序执行。

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

### 获批项提交

1. `1b0350d37` — 先行登记 `cl-jpeg`、`png-read` 及传递闭包，分类为
   纯 Lisp 可替换依赖；
2. `68b07c010` — JPEG/PNG 真像素解码、EXIF orientation、Lanczos3 缩放与
   编码大小降级；
3. `602e03902`、`0f7836754` — additive extension API、load-scope handle、
   renderer/flag/shortcut、inline factory 与 CLI-owned UI bridge；
4. `158bc3128` — `cadr-ai` native provider 最小 runtime 合约，仅修改
   `models-runtime.lisp`、`package.lisp` 与对应 test；`cadr-ai.asd` 无需改动；
5. `cbd50a040`、`ee981f6a8` — `define-native-provider`、llama.cpp bundled
   extension、Hugging Face GGUF 查询与无 read-timeout 的 `/models/sse`；
6. `config.test.ts` 按用户裁决整文件记为 `N/A`，边界不扩张到
   `version-check.test.ts` 或资源包更新。

### 扩展重冻

按 Goal 7 相同取样命令重算：

```text
sed -n '/#:define-tool/,/#:make-extension-hook-result/p' \
  src/cadr-agent/package.lisp | sha256sum
e0bcbf8c5f170efb99579fe6065579a8c2e93c7f1bd590b7502b08180ba54046  -
```

重冻 object ID：

```text
e94a3f1c1c80ffb784a94e8bbef9c8645e8504da  cadr-ai.asd
7d657fa28a05a98b7ea673ac73ff26e0bff5d923  cadr-agent.asd
aebccdb3796edc419d916403b2af3c52e378b3db  cadr-cli.asd
77a0a261ee2ab365875924878d803f10be72bb9f  src/cadr-ai/models-runtime.lisp
a9cdcddc18d4acacc28bf7e04814d4f61fe6f002  src/cadr-ai/package.lisp
f9779b379a9374f39f4647a89a07181fc4206feb  test/cadr-ai/models-runtime-test.lisp
54366ea418de090192b9320469caae497d255b01  src/cadr-agent/extensions.lisp
bd78aa73d5f75fc8a21366fc747188c1ee35023c  src/cadr-agent/package.lisp
12f9de30da61bceec9a51e186e577d64b12367d6  src/cadr-agent/loop.lisp
08beda50203d7af790d1690a06090ca7df82da23  src/cadr-agent/tool.lisp
c097b312567386421da5cdae0f1c13d039b21bde  test/cadr-agent/extensions-test.lisp
cf16c937b667eb2252a45ec93585edc8d0a4d60a  test/cadr-agent/extensions-wave2-test.lisp
5cb7dbafbffb7b82c408312b13795c3116f2da63  test/cadr-agent/extensions-wave3-test.lisp
9e598d9aad1f93ee1b17d7bff8fae36a91c2b4f9  src/cadr-cli/extensions.lisp
b4e190b5b24e6479570829767f8c6df7360d5449  src/cadr-cli/resource-loader.lisp
1c76c8990bd3e34a934bf8d966001441561d0f0a  src/cadr-cli/interactive-services.lisp
656dc50d5e3616d54bbcb150ddfedabe4b2a785b  src/cadr-cli/tui.lisp
ecfd5a50a395628bc5e424aedb72d087c14fb137  src/cadr-cli/main.lisp
a2a35209e968becd791c9ce336bf47328aba5ec5  src/cadr-cli/modes/rpc/mode.lisp
ab8de4c1a4a5434dce31c0392fd51ae67ea61872  src/cadr-cli/model-services.lisp
cdc2cfbb966620d7b6f0a8c90e7ea37d5fb05c40  test/cadr-cli/extensions-test.lisp
762385be59337bbf131e23f07062645edbd12633  test/cadr-cli/part-b-interactive-test.lisp
8f13570644842cc8780ce0c3cc955589a339ccda  test/cadr-cli/llama-extension-test.lisp
7ac5d70c2c12af9ef4a3c748c24e7d24474cb959  src/cadr-cli/extensions/llama/client.lisp
3bfbdf66495fd864119a76eb9cba0db2f2e63c4a  src/cadr-cli/extensions/llama/huggingface.lisp
d845e5e14fd9c9b864e65297e58728ae1f1e7c2f  src/cadr-cli/extensions/llama/provider.lisp
5838bab8cf028e1632897989c92365521fe97087  src/cadr-cli/extensions/llama/extension.lisp
```

Goal 7 三个 fixture SHA 保持不变：

```text
e2548662d773edfa21ecfa3b126b2209404a2b27385e6cd48e1f145a41747442  test/fixtures/extensions/legacy-wave2-api.lisp
6dc3a25271080a59c3380704044c435a0a20a972c5ba19f32cae2acee2649b10  test/fixtures/rpc-process-client.py
c1148870a539dd4a24001da74d17f668b6092bf55d41d845319d5439e3df9486  test/fixtures/extensions/rpc-ui.lisp
```

`LEGACY-EXTENSION-SOURCE-REMAINS-COMPATIBLE-AFTER-WAVE-2-API-EXPANSION`
继续全绿；相对 Goal 8 开工提交执行
`git diff 664e6b80...HEAD -- src/cadr-tui` 为空，TUI production 冻结红线
未触碰。上述扩大面从此恢复“发布即稳定”。

### 全量门禁与账本

```text
./scripts/test-cl.sh
cadr-ai      668/668
cadr-agent   588/588
cadr-tui     593/593
cadr-cli    1056/1056
total       2905/2905
```

Part B 把开工时 coding-agent 的 128 个 `M` 重分类为 127 个 `C` 和一个经
用户裁决的 `N/A`；逐文件变更清单就是 parity-map manifest 中所有
`CL-PART-B` 行及 `config.test.ts` 行。收尾账本：
`351 C / 0 U / 0 M / 1 N/A`。

## Wave 5：storage、server 与 evals

状态：完成并提交。该 Wave 只补齐固定基线已有的三个独立 package，没有
修改已重冻的 extension/TUI surface，也没有引入第三方依赖。

### 落账提交

1. `d7b81ce16`、`098362696` — 测试先行，建立独立 `cadr-storage`
   facade，复用唯一 SQLite repository/storage 实现；
2. `ee9a18640`、`c2f463ffb` — 测试先行，实现 Unix-socket JSONL
   supervisor、RPC child、持久化、Radius credential gate 与 UI/event bridge；
3. `11d9f9685`、`a99048395` — 测试先行，实现隔离 eval harness、smoke 与
   self-extension suites；
4. `c11278b07` — native server 构建、真实 socket smoke、原版 spawn flags、
   进程退出/accept-loop 修复，以及 Radius backoff/连续三次 404 重注册；
5. `370aeafce` — eval CLI runner 与 DeepSeek/Codex OAuth live gate；
6. `088f3c639` — 将三个 package 纳入全量测试入口；
7. `7be14f292` — 显式声明 server 使用的 SBCL process contrib，不新增
   第三方依赖。

### 门禁证据

```text
./scripts/test-cl.sh
cadr-ai       668/668
cadr-agent    588/588
cadr-tui      593/593
cadr-cli     1056/1056
cadr-storage   23/23
cadr-server    43/43
cadr-evals     16/16
total        2987/2987

./scripts/server-smoke.sh
server smoke: spawn/list/status/RPC/stop over Unix socket passed

./scripts/live-evals-smoke.sh
live evals: DeepSeek and OpenAI Codex smoke suites passed
```

`build.sh` 与 `build-server.sh` 均在当前 SBCL 缺少
`sb-core-compression` 时明确降级为无压缩 image；产物分别为 `cadr` 与
`cadr-server`，二者 `--version` 均显示 cadr 新命名。最终产物为：

```text
cadr         65,381,272 bytes  mode 0755
cadr-server  57,220,848 bytes  mode 0755
```

### 冻结与账本

相对 Goal 8 开工提交，`git diff 664e6b80...HEAD -- src/cadr-tui` 仍为空；
Part B 的 extension export SHA 仍为
`e0bcbf8c5f170efb99579fe6065579a8c2e93c7f1bd590b7502b08180ba54046`。
Wave 5 不改变 `*.test.ts` 分类，因此终局账本保持
`351 C / 0 U / 0 M / 1 N/A`；新增的 82 个断言覆盖基线中没有
`*.test.ts` 的 storage/server/evals package surface。

## Part F：终局机械收官

状态：机械部分完成并落账；等待用户按
[`docs/acceptance/goal-v8-final.md`](../acceptance/goal-v8-final.md)
逐项完成人工验收，尚未宣告进入维护态。

### 收官提交

1. `33575aa3e` — 修正全链路 smoke 对新增 `agent_settled` 与延迟 session
   持久化的陈旧假设；
2. `3e78b1962` — TUI live smoke 使用唯一 slash command 前缀，不再依赖
   扩充后会变化的命令排序；
3. Part F docs 提交 — 最终账本、依赖审计、冻结 object ID、README 验证
   等级与终局验收包。

### 机械结论

- 终局账本：`351 C / 0 U / 0 M / 1 N/A`；
- 全量：`2987/2987`；
- `build.sh`、`build-server.sh` 均成功无压缩降级并产出新命名；
- acceptance、process modes、migration、server 与 TUI deterministic
  smokes 全绿；
- DeepSeek 的 stream/print/extension/repo/TUI/eval 与 Codex OAuth 的
  stream/eval 全部实际运行通过；
- Anthropic 无凭据，按基线 credential gate 跳过；
- 依赖审计无新增第三方依赖；
- 最终代码、ASDF/build 与 extension SHA 已写入 architecture 第 24 节。

Goal 8 的终局大验收仍以用户人工清单为最后一道门；自行宣布完成无效。
