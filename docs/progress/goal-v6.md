# GOAL v6: Wave 1 — shared adapters and compatible providers

> Historical report: the `71efc6f0…` in this document records the audit anchor as
> of Goal 6; from Goal 9 on, the current normative baseline is
> `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.

## Baseline and boundary

- Fixed behavior baseline:
  `71efc6f0c1909874ec8c944637a9ae7fc0e2d508`.
- Fixed audit checkout: `/tmp/cadr-parity-71efc6f0`; at both the start and the
  wrap-up, `git rev-parse HEAD` was the hash above and `git status --short`
  produced no output.
- This round modified only the `cadr-ai` provider/catalog layer, the
  corresponding tests and fixtures, plus this report and
  `docs/parity-map.md`. The TUI, extensions, the agent, sessions, tool semantics
  and the CLI are all frozen.

The Git tree/blob IDs of the frozen area are exactly identical in the start and
wrap-up commit states:

| Path | Git object ID |
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

## Part B read-only pre-review

The selection criteria are fixed as: reuses `openai-completions` or
`anthropic-messages`, uses only an environment-variable API key, has no device
flow, cloud signing or provider-specific authentication, and is low in
implementation difficulty. This batch takes a full 12:

| provider | Protocol | Fixed catalog source | Default model |
|---|---|---|---|
| `ant-ling` | `openai-completions` | generator static definition `ant-ling` | `Ring-2.6-1T` |
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

Exclusions:

- The existing `anthropic`, `openai`, `google` and `deepseek` belong to Part A
  and do not occupy a slot in this batch.
- `azure-openai-responses`, `amazon-bedrock`, `google-vertex` and
  `github-copilot` need a deployment URL, cloud signing, a service account or a
  device flow, and are fixed as belonging to Wave 3.
- `cloudflare-ai-gateway`, `fireworks`, `opencode`, `opencode-go` and `xai`
  involve multi-protocol routing, placeholder materialization or separate
  authentication, and do not meet this batch's low-difficulty criterion.
- Bedrock, Vertex, Mistral Conversations, Azure Responses and
  `pi-messages` are separate wire protocols and do not reuse this batch's shared
  adapters.

The verification level of every newly added provider is fixed as **fixture
cross-implementation comparison**; this round did not write up any newly added
provider as "live verification".

## Part A evidence

Running the payload exporter in the fixed checkout added the following
field-by-field reference fixtures:

| Adapter behavior | fixture | Independent test |
|---|---|---|
| Anthropic adaptive thinking, long cache, strict tool | `anthropic-adaptive-long-cache.json` | `ANTHROPIC-ADAPTIVE-THINKING-AND-LONG-CACHE-MATCH-REFERENCE` |
| Anthropic thinking disabled | `anthropic-thinking-disabled.json` | `ANTHROPIC-THINKING-DISABLE-MATCHES-REFERENCE` |
| OpenAI Completions Qwen reasoning/tool choice | `openai-completions-qwen-reasoning.json` | `OPENAI-COMPLETIONS-QWEN-REASONING-MATCHES-REFERENCE` |
| OpenAI Responses reasoning/long cache | `openai-responses-reasoning-cache.json` | `OPENAI-RESPONSES-REASONING-CACHE-MATCHES-REFERENCE` |
| Google high thinking | `google-thinking-high.json` | `GOOGLE-THINKING-HIGH-MATCHES-REFERENCE` |
| Google disabled thinking | `google-thinking-disabled.json` | `GOOGLE-THINKING-DISABLE-MATCHES-REFERENCE` |

The same test file also covers eager tool input, temperature, empty thinking
signature, strict tools, the token fields, store, session affinity, the
64-character cache key, `cacheRetention=none` disabling affinity, and Google's
thinking/tool mode for non-Gemini 3.

Tests-first gates:

- The first batch of adapter fixtures: `256 pass / 6 fail`, fully green after
  implementation.
- When the cache boundaries were checked additionally after Part B was complete,
  the new tests first gave `365 pass / 4 fail`; after Completions'
  `prompt_cache_key`/`prompt_cache_retention` and Responses'
  `cacheRetention=none` affinity were fixed it was `369/369`.

## Part B item-by-item evidence

Each test independently verifies the protocol, the base URL, the environment
variable, the default model, the exact catalog entry count, the default request
fixture and the missing-key error:

| provider | Catalog entries | fixture | Test |
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

Part B's tests-first gate was `279 pass / 12 fail`, all 12 red because the
providers were not yet registered; they turned green after implementation.
`BUILT-IN-PROVIDER-REGISTRY-IS-COMPLETE` fixes 17
cadr registry IDs in step.

### Catalog extraction

The fixed checkout first runs:

```bash
cd /tmp/cadr-parity-71efc6f0
npm install --ignore-scripts
node packages/ai/scripts/generate-models.ts \
  --strict --json-only \
  --json-output /tmp/cadr-model-catalog.HW3Yur.json
```

At `2026-07-30 19:48:00 +08:00` the fixed generator produced 39 catalog
artifacts, 1153 models in total. `export-ts-payloads.ts` exports from that
result only the 12 providers that passed the pre-review, yielding 143 catalog
records; the aggregate fixture is
`test/fixtures/catalogs/wave1-provider-models.json`, SHA-256:

```text
3e1f8e1ee9831ac61a4809d14a61006d48c4c47d3b010d2c1f72cd34c7a543bc
```

The remote `models.dev` changes, so this represents only a snapshot of "what the
fixed generator extracted during this run", and does not pass itself off as
static data as of the audit commit. `refresh-model-catalog.lisp` reads only the
repository fixture and generates, offline and deterministically, 143 Wave 1
models and 6 existing models, 149 runtime catalog records in total.

Commands to reproduce the reference payloads/catalog:

```bash
node scripts/export-ts-payloads.ts \
  --reference /tmp/cadr-parity-71efc6f0 \
  --catalog /tmp/cadr-model-catalog.HW3Yur.json
QUICKLISP_SETUP=/root/quicklisp/setup.lisp \
  sbcl --noinform --disable-debugger \
  --script scripts/refresh-model-catalog.lisp
```

## Final acceptance

Full test run:

```text
./scripts/test-cl.sh
  cadr-ai:    369/369
  cadr-agent: 156/156
  cadr-tui:   582/582
  cadr-cli:   225/225
  total:     1332/1332
```

Commit state `8fd157d45` was built in a separate detached worktree:

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

Result:

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

DeepSeek and OpenAI OAuth are real calls through existing adapters; the 12 newly
added providers are still strictly marked as fixture cross-implementation
comparison.

Implementation commits:

1. `132e8bfbe` — `feat(ai): complete shared provider compatibility`
2. `8fd157d45` — `feat(ai): add Wave 1 compatible providers`

`git diff --check` passes. The fixed audit checkout is clean, and the frozen
area's object IDs are unchanged. `ollama` is still pre-existing registry drift
outside the baseline's 38 providers; to avoid crossing the frozen CLI tests and
the Wave 1 scope, this round did not delete or extend that mechanism. The
remaining separate protocols, authentication flows, the full provider catalog
and the complete protocol boundary stay `M`, and have not entered Wave 2/3/5
early.
