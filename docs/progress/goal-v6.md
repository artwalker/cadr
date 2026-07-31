# GOAL v6: Wave 1 — 共享适配器与兼容 provider

> 历史报告：文内 `71efc6f0…` 记录 Goal 6 当时的审计锚点；Goal 9 起当前
> 规范基线为 `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`。

## 基线与边界

- 固定行为基线：
  `71efc6f0c1909874ec8c944637a9ae7fc0e2d508`。
- 固定审计 checkout：`/tmp/cadr-parity-71efc6f0`；开工与收尾时
  `git rev-parse HEAD` 均为上述 hash，`git status --short` 均无输出。
- 本轮只修改 `cadr-ai` provider/目录层、对应测试与 fixture，以及本报告和
  `docs/parity-map.md`。TUI、扩展、agent、会话、工具语义与 CLI 全部冻结。

冻结区在开工和收尾提交态的 Git tree/blob ID 完全一致：

| 路径 | Git object ID |
|---|---|
| `src/cadr-tui` | `1a5ba07b17cd3b0c55c8a1ec35a79d1fafda0950` |
| `test/cadr-tui` | `947e63cc73b259ea2b18bfc281b5229a13f9a5d0` |
| `src/cadr-agent` | `bc4db82f36205cac8ac9917ab3ce14227370b6df` |
| `test/cadr-agent` | `bb0ae0cdd80106071ce212a65538bf9eb2c29f69` |
| `src/cadr-cli` | `b61514c3f6def658dfe9d457de2317801018aff8` |
| `test/cadr-cli` | `6bc3ffd00919dc673b02d55276544f20db0b84e8` |
| `cadr-tui.asd` | `c09f6172c1c186f15c726b2c04b7ea65a4f4214c` |
| `cadr-agent.asd` | `0eac1701379bb98e17141ecc7d8ab12f553466b0` |
| `cadr-cli.asd` | `e28c83b6694e48734702d5a06b5b303356048d93` |

## Part B 只读预审

选择标准固定为：复用 `openai-completions` 或 `anthropic-messages`，仅使用
环境变量 API key，无设备流、云签名或 provider 独立认证，实现难度低。本批
取满 12 个：

| provider | 协议 | 固定目录来源 | 默认模型 |
|---|---|---|---|
| `ant-ling` | `openai-completions` | generator 静态定义 `ant-ling` | `Ring-2.6-1T` |
| `cerebras` | `openai-completions` | generator `models.dev:cerebras` | `zai-glm-4.7` |
| `groq` | `openai-completions` | generator `models.dev:groq` | `openai/gpt-oss-120b` |
| `huggingface` | `openai-completions` | generator `models.dev:huggingface` | `moonshotai/Kimi-K2.6` |
| `minimax` | `anthropic-messages` | generator `models.dev:minimax` | `MiniMax-M2.7` |
| `minimax-cn` | `anthropic-messages` | generator `models.dev:minimax` | `MiniMax-M2.7` |
| `moonshotai` | `openai-completions` | generator `models.dev:moonshotai` | `kimi-k2.6` |
| `moonshotai-cn` | `openai-completions` | generator `models.dev:moonshotai` | `kimi-k2.6` |
| `qwen-token-plan` | `openai-completions` | generator `models.dev:qwen-token-plan` | `qwen3.7-max` |
| `qwen-token-plan-cn` | `openai-completions` | generator `models.dev:qwen-token-plan-cn` | `qwen3.7-max` |
| `together` | `openai-completions` | generator `models.dev:togetherai` | `moonshotai/Kimi-K2.6` |
| `xiaomi` | `openai-completions` | generator `models.dev:xiaomi` | `mimo-v2.5-pro` |

排除项：

- 已有的 `anthropic`、`openai`、`google`、`deepseek` 属 Part A，不占本批。
- `azure-openai-responses`、`amazon-bedrock`、`google-vertex`、
  `github-copilot` 需要部署 URL、云签名、服务账号或设备流，固定属于 Wave 3。
- `cloudflare-ai-gateway`、`fireworks`、`opencode`、`opencode-go`、`xai`
  涉及多协议路由、占位符物化或独立认证，不满足本批低难度标准。
- Bedrock、Vertex、Mistral Conversations、Azure Responses 与
  `pi-messages` 是独立 wire protocol，不复用本批共享适配器。

所有新增 provider 的验证等级固定为 **fixture 对拍**；本轮没有把任何新增
provider 写成“live 验证”。

## Part A 证据

固定 checkout 中运行 payload exporter，新增以下逐字段参考 fixture：

| 适配器行为 | fixture | 独立测试 |
|---|---|---|
| Anthropic adaptive thinking、long cache、strict tool | `anthropic-adaptive-long-cache.json` | `ANTHROPIC-ADAPTIVE-THINKING-AND-LONG-CACHE-MATCH-REFERENCE` |
| Anthropic thinking disabled | `anthropic-thinking-disabled.json` | `ANTHROPIC-THINKING-DISABLE-MATCHES-REFERENCE` |
| OpenAI Completions Qwen reasoning/tool choice | `openai-completions-qwen-reasoning.json` | `OPENAI-COMPLETIONS-QWEN-REASONING-MATCHES-REFERENCE` |
| OpenAI Responses reasoning/long cache | `openai-responses-reasoning-cache.json` | `OPENAI-RESPONSES-REASONING-CACHE-MATCHES-REFERENCE` |
| Google high thinking | `google-thinking-high.json` | `GOOGLE-THINKING-HIGH-MATCHES-REFERENCE` |
| Google disabled thinking | `google-thinking-disabled.json` | `GOOGLE-THINKING-DISABLE-MATCHES-REFERENCE` |

同一测试文件还覆盖 eager tool input、temperature、empty thinking
signature、严格工具、token 字段、store、session affinity、64 字符 cache
key、`cacheRetention=none` 禁用 affinity，以及 Google 非 Gemini 3 的
thinking/tool mode。

测试先行门禁：

- 第一批适配器 fixture：`256 pass / 6 fail`，实现后全绿。
- Part B 完成后补查 cache 边界时，新增测试先得到 `365 pass / 4 fail`；
  Completions 的 `prompt_cache_key`/`prompt_cache_retention` 与 Responses
  的 `cacheRetention=none` affinity 修复后为 `369/369`。

## Part B 逐项证据

每条测试独立校验协议、base URL、环境变量、默认模型、精确目录条目数、默认
请求 fixture 与缺 key 错误：

| provider | 目录条目 | fixture | 测试 |
|---|---:|---|---|
| `ant-ling` | 3 | `ant-ling-default.json` | `ANT-LING-PROVIDER-MATCHES-FIXED-CATALOG` |
| `cerebras` | 3 | `cerebras-default.json` | `CEREBRAS-PROVIDER-MATCHES-FIXED-CATALOG` |
| `groq` | 7 | `groq-default.json` | `GROQ-PROVIDER-MATCHES-FIXED-CATALOG` |
| `huggingface` | 51 | `huggingface-default.json` | `HUGGINGFACE-PROVIDER-MATCHES-FIXED-CATALOG` |
| `minimax` | 3 | `minimax-default.json` | `MINIMAX-PROVIDER-MATCHES-FIXED-CATALOG` |
| `minimax-cn` | 3 | `minimax-cn-default.json` | `MINIMAX-CN-PROVIDER-MATCHES-FIXED-CATALOG` |
| `moonshotai` | 10 | `moonshotai-default.json` | `MOONSHOTAI-PROVIDER-MATCHES-FIXED-CATALOG` |
| `moonshotai-cn` | 10 | `moonshotai-cn-default.json` | `MOONSHOTAI-CN-PROVIDER-MATCHES-FIXED-CATALOG` |
| `qwen-token-plan` | 15 | `qwen-token-plan-default.json` | `QWEN-TOKEN-PLAN-PROVIDER-MATCHES-FIXED-CATALOG` |
| `qwen-token-plan-cn` | 15 | `qwen-token-plan-cn-default.json` | `QWEN-TOKEN-PLAN-CN-PROVIDER-MATCHES-FIXED-CATALOG` |
| `together` | 17 | `together-default.json` | `TOGETHER-PROVIDER-MATCHES-FIXED-CATALOG` |
| `xiaomi` | 6 | `xiaomi-default.json` | `XIAOMI-PROVIDER-MATCHES-FIXED-CATALOG` |

Part B 的测试先行门禁为 `279 pass / 12 fail`，12 条均因 provider 未注册
而红；实现后转绿。`BUILT-IN-PROVIDER-REGISTRY-IS-COMPLETE` 同步固定 17
个 cadr registry ID。

### 目录提取

固定 checkout 先执行：

```bash
cd /tmp/cadr-parity-71efc6f0
npm install --ignore-scripts
node packages/ai/scripts/generate-models.ts \
  --strict --json-only \
  --json-output /tmp/cadr-model-catalog.HW3Yur.json
```

固定 generator 于 `2026-07-30 19:48:00 +08:00` 生成 39 个目录 artifact、
共 1153 个模型。`export-ts-payloads.ts` 从该结果只导出预审通过的 12 个
provider，得到 143 条目录记录；聚合 fixture 为
`test/fixtures/catalogs/wave1-provider-models.json`，SHA-256：

```text
3e1f8e1ee9831ac61a4809d14a61006d48c4c47d3b010d2c1f72cd34c7a543bc
```

远端 `models.dev` 会变化，因此这只表示“固定 generator 在本次执行时提取”
的快照，不冒充审计提交时的静态数据。`refresh-model-catalog.lisp` 只读取
仓库 fixture，离线确定性生成 143 条 Wave 1 模型和 6 条既有模型，共 149
条运行时目录记录。

参考 payload/目录复现命令：

```bash
node scripts/export-ts-payloads.ts \
  --reference /tmp/cadr-parity-71efc6f0 \
  --catalog /tmp/cadr-model-catalog.HW3Yur.json
QUICKLISP_SETUP=/root/quicklisp/setup.lisp \
  sbcl --noinform --disable-debugger \
  --script scripts/refresh-model-catalog.lisp
```

## 最终验收

全量测试：

```text
./scripts/test-cl.sh
  cadr-ai:    369/369
  cadr-agent: 156/156
  cadr-tui:   582/582
  cadr-cli:   225/225
  total:     1332/1332
```

提交态 `8fd157d45` 在独立 detached worktree 中构建：

```bash
build_tree="$(mktemp -d /tmp/cadr-goal6-build.XXXXXX)"
git worktree add --detach "$build_tree" 8fd157d45
(
  cd "$build_tree"
  XDG_CACHE_HOME="$build_tree/.cache" \
  QUICKLISP_SETUP=/root/quicklisp/setup.lisp \
    ./build.sh
)
```

结果：

```text
cadr build: SBCL lacks sb-core-compression; building an uncompressed image.
cadr: ELF 64-bit LSB pie executable, x86-64
./cadr --version
  cadr 0.1.0
./scripts/acceptance-smoke.sh
  acceptance smoke: executable help, --continue, and exact --resume passed
./scripts/live-deepseek-smoke.sh
  live smoke: DeepSeek Chat Completions streaming passed
./scripts/live-openai-oauth-smoke.sh
  OAuth live smoke: OpenAI Codex Responses streaming passed
```

DeepSeek 与 OpenAI OAuth 是既有 adapter 的真实调用；12 个新增 provider
仍严格标为 fixture 对拍。

实现提交：

1. `132e8bfbe` — `feat(ai): complete shared provider compatibility`
2. `8fd157d45` — `feat(ai): add Wave 1 compatible providers`

`git diff --check` 通过。固定审计 checkout 干净，冻结区 object ID 未变。
`ollama` 仍是基线 38 provider 之外的既有 registry drift；本轮为避免越过
冻结 CLI 测试与 Wave 1 范围，没有删除或扩张该机制。剩余独立协议、认证流、
全 provider 目录与完整协议边界继续保持 `M`，未提前进入 Wave 2/3/5。
