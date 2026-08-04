# Goal 16 验收记录

状态：Part A0、A、B、Part C1-C5 与 Part D 已完成并提交；等待用户验收。

## Part A0：压缩降级行为

独立提交：`3dbb58b895a1f732d6354233e91d6981b0a35c09`
（`fix(agent): align compaction degradation with baseline`）。

### 基线合同与实现

- 固定基线 `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5` 的
  `packages/coding-agent/src/core/compaction/compaction.ts:679-685` 只在
  `stopReason === "error"` 时失败；空串、空白、`length`、`toolUse`、
  `aborted` 的已生成文本均原样返回。
- `packages/coding-agent/src/core/branch-summarization.ts:353-375` 将 abort
  作为取消返回，error 使用 provider 文案，空摘要最终降级为
  `No summary generated`。
- Cadr 复用现有 `agent-stream-function`、extension cancellation signal、
  session journal/migration 与 overflow 临时分支恢复；没有新建重试器或新机制。

变更归属：

| 合同 | 实现位置 |
|---|---|
| summary 失败/降级矩阵、abort 后不持久化 | `src/cadr-agent/compaction.lisp` |
| branch abort/error/empty fallback | `src/cadr-agent/branch-summarization.lisp`、`src/cadr-agent/loop/agent-loop.lisp` |
| 空/空白 summary 持久化与重载 | `src/cadr-agent/session/journal.lisp`、`src/cadr-agent/session/migration.lisp` |

链路审计还发现并移除了三处同源严格化：extension compaction 拒绝空摘要、
journal 拒绝空摘要、migration 无法重载已持久化空摘要。未保留任何基线没有的
空值失败分支。

### 恢复与自救

- threshold auto-compaction 失败时保留原上下文并继续当前 prompt；agent 的 busy
  状态由既有 unwind-protect 清除。用户可继续对话或再次执行 `/compact`。
- context overflow compaction 成功时沿既有路径重试；失败时恢复原 error leaf，
  返回 provider error，但 agent 回到 idle，下一条 prompt 仍可执行。
- 用户在 summary response 后取消时不写 compaction entry；branch summary abort
  不移动 session leaf。

### 红绿证据

新增/更新门禁：

- `COMPACTION-SUMMARY-FAILURE-CONTRACT-MATCHES-BASELINE`
- `EMPTY-AND-WHITESPACE-COMPACTION-SUMMARIES-PERSIST-AND-CONTINUE`
- `EXTENSION-COMPACTION-ALLOWS-EMPTY-AND-WHITESPACE-SUMMARIES`
- `USER-ABORT-AFTER-SUMMARY-RESPONSE-DOES-NOT-PERSIST-COMPACTION`
- `FAILED-OVERFLOW-COMPACTION-LEAVES-SESSION-USABLE`
- `BRANCH-SUMMARY-USES-BASELINE-EMPTY-FALLBACK`
- `ABORTED-BRANCH-SUMMARY-CANCELS-WITHOUT-MOVING-THE-SESSION`
- `SESSION-COMPACTION-EMPTY-HOOK-IS-USED-FAILING-HOOK-FALLS-BACK-AND-ABORT-STOPS`

测试先行的旧实现运行：998 checks / 990 pass / 0 skip / **8 fail**，失败逐项
命中空摘要、空白摘要、extension summary、overflow error copy 与 branch
fallback。修复后 `CADR-AGENT-SUITE` 为 1024/1024/0/0。

## Part A：身份审计

提交：`dcba371ff`（`docs: audit product identity across the full tree`）。产物：
`docs/identity-audit.md`。Part A 的 staged diff 仅包含该审计和本报告，生产代码
零变更。结果：

- 全量枚举得到 14 个不同的生产 `PI_*` 环境变量；
- 六组第三方归因值（含 xAI referrer）均为 `须替换`，已有用户预裁；
- Radius `pi-gateway` 有 live discovery 的注册合同证据，`radius.pi.dev` 是真实
  provider/API endpoint，二者不是推测性保留；
- `/share`、版本检查、HTML viewer meta 合同和环境变量迁移已分离为 Part B
  决策；
- 额外发现 export localStorage、notify 示例、synthetic tool call ID、Radius
  自由日志文案与导出 Lisp API 名残留；
- catalog 注释、固定基线 harness、版本对齐声明、扩展 manifest `"pi"` schema
  与 Radius wire dialect 已给出逐条保留理由。

## Part B：已裁决提案

提案：`docs/proposals/goal-v16-identity.md`。它把实现决策拆成六项：

1. `/share` 默认 viewer 最终裁决为 `https://cadr.dev/session/`，保持启用并仅由
   `CADR_SHARE_VIEWER_URL` 或显式参数覆盖；用户已知情接受页面上线前链接暂不可达；
2. 版本检查未配置 Cadr endpoint 时默认禁用；
3. 14 个 `PI_*` 环境变量硬切为 `CADR_*`，不保留 alias 或 warning 兼容期；
4. 仓库链接、临时文件、HTML localStorage、synthetic call ID、Radius 自由文案和
   example 标题等非合同身份值整组替换；
5. Radius 注册/API/wire、扩展 manifest、catalog/基线溯源等精确 allowlist；
6. 复用既有 release identity 作为私有单一来源，按 C1→C5 后进入 D 门禁。

用户在 Goal 16 规格中预裁的 User-Agent、OpenRouter、NVIDIA、Cloudflare、
OpenCode 与 xAI referrer 值不重复请求裁决。Part B 只写文档，未修改生产代码。

Radius 外部核验（2026-08-04）：

```text
GET https://radius.pi.dev/             -> HTTP 200
GET https://radius.pi.dev/v1/oauth     -> HTTP 200
discovery.clientId                     -> pi-gateway
discovery.scope                        -> gateway offline_access
```

## Part C：身份收敛实施

### C1：单一身份源与第三方 attribution

提交 `cc4f1f0e0`。`src/cadr-ai/support/release.lisp` 统一拥有产品 slug、显示名、
规范仓库 URL 与默认 share viewer；版本 User-Agent、OpenRouter、NVIDIA、
Cloudflare、OpenCode 和 xAI device-code referrer 均从 Cadr 身份派生。xAI 以相同
client ID/scope、`referrer=cadr` 发起真实 device authorization 请求并得到 HTTP
200，故无需回退功能约束。

合同门禁包括 `GOAL16-PRODUCT-IDENTITY-HAS-ONE-PRIVATE-OWNER`、
`GOAL16-THIRD-PARTY-ATTRIBUTION-USES-CADR-IDENTITY` 与现有 xAI OAuth payload
测试；provider payload 其余字段不变。

### C2：服务端点

提交 `ac23e11bb`。`/share` 使用 `https://cadr.dev/session/` 默认 viewer，非空
`CADR_SHARE_VIEWER_URL` 和显式参数保持覆盖优先级；成功状态同时呈现生成链接和
viewer 地址。render-diff 的 `slash-share` 只新增获批的 I03 URL 差异，完整
40/40 capture 与 fail-closed disposition 均通过。

版本检查不再查询 pi.dev；未配置 `CADR_VERSION_CHECK_URL` 时不发网络请求，配置
后复用原 timeout、JSON、比较与静默网络失败合同，`CADR_OFFLINE` 和
`CADR_SKIP_VERSION_CHECK` 仍可关闭。该项在 CHANGELOG 记为修复，因为比较两个
不同产品的版本号本身无语义。

### C3：环境变量硬切

提交 `af8612d95`。14 个生产旧名按批准表一次硬切为 `CADR_*`，其中
`PI_MODEL -> CADR_EVAL_MODEL`、`PI_PROVIDER -> CADR_EVAL_PROVIDER` 是明确重命名，
不是简单换前缀。生产 `src/` 的旧名扫描为零；固定 TypeScript 基线 driver 中的
`PI_OFFLINE` 不属于 Cadr runtime，继续保留。

门禁 `GOAL16-C3-PRODUCTION-ENVIRONMENT-NAMES-ARE-CADR-ONLY` 同时证明新名生效、
旧名不再读取；Bedrock/eval/server/tool/version 的行为回归全部通过。

### C4：自由身份值

提交 `5eb36c930`。`/changelog` 规范仓库、WSL 临时文件、notify 示例、导出 HTML
localStorage、synthetic tool-call ID 与 Radius 自由日志/线程文案完成替换。Radius
client/API/wire、扩展 manifest、generated provenance 和固定基线输入未改。

门禁 `GOAL16-C4-FREE-IDENTITY-VALUES-ARE-CADR-OWNED` 逐文件断言旧字符串消失；
HTML template SHA 同步更新，session entries、payload 与 wire 未变化。

### C5：文档收敛

commit `481033fe1`。

README 记录 14 项迁移表、share 过渡期、版本检查开关与外部合同边界；CHANGELOG
把版本检查列为修复；architecture、审计、提案和 open-questions 均同步最终裁决。
Part C 没有新增依赖、兼容层、telemetry 或未裁决机制。

## Part D：产品身份漂移门禁

commit `44f8dd8a7`。

- `scripts/check-product-identity.py` 只扫描 production 范围：`src/`、
  `examples/`、`scripts/`、`.github/`、根 README/CHANGELOG、ASDF 与构建入口。
- `docs/product-identity-allowlist.json` 共记录 274 次真实命中、251 条精确
  disposition 与 1 个 SHA-256 锁定的 opaque 资产。每条 disposition 同时绑定
  path、kind、token、完整行内容、出现次数与非空理由；目录、glob、正则或
  空理由豁免均非法。
- 门禁 fail-closed 拒绝新命中、移动后的同 token、重复/过期 disposition、
  次数漂移、总数漂移与 opaque digest 漂移。`test/product-identity-gate-test.py`
  的 9 个独立回归覆盖这些反例，并直接驱动当前真实仓库。
- 测试先行证据：无 checker 时合成用例整批失败；checker 落地但无真实
  manifest 时真实仓库用例失败；`verify.sh` 未接入时顺序合同回归失败。
  实现后 9/9 通过，真实扫描数与 manifest 逐项相等。
- `scripts/verify.sh` 在 code organization 后、source parity/FiveAM/构建前依次运行
  合成回归与真实树扫描；任一失败会阻断后续确定性阶段。
- 常设政策落入 `docs/development-policy.md`：改动 identity allowlist 等同改动
  产品身份边界，须先书面提案并经用户逐项裁决。

## Goal 16 完整验证（2026-08-05）

`./scripts/test-cl.sh`：

```text
cadr test summary: systems=9 checks=14827 pass=14827 skip=0 fail=0
```

`./scripts/verify.sh`：

| 阶段 | 结果 |
|---|---|
| root cadr binary freshness | PASS |
| code organization gate | PASS |
| product identity gate | PASS（9 个合成/真实回归；274 命中 / 251 disposition / 1 opaque） |
| real source parity ledger | PASS（595） |
| source parity drift self-test | PASS |
| deterministic FiveAM | PASS（14,827/14,827） |
| isolated cadr build | PASS（无 core compression 时无压缩降级） |
| isolated cadr-server build | PASS（无 core compression 时无压缩降级） |
| Goal 11 performance and stability gate | PASS |
| native acceptance smoke | PASS |
| native process modes | PASS |
| migration PTY smoke | PASS |
| Unix socket server smoke | PASS |
| terminal lifecycle PTY | PASS（6/6） |
| deterministic TUI harness | PASS |
| fixed-baseline render differential | PASS（40/40；160/160 dispositions） |
| credential-gated FiveAM | PASS（7 pass / 1 Anthropic credential skip / 0 fail） |
| DeepSeek live TUI | PASS |

live 项目级统计为 8 项、7 run/pass、1 个 `ANTHROPIC_API_KEY is not set` skip；
检查级统计为 32 checks / 31 pass / 1 skip / 0 fail。该结果不冒充确定性证据。

根二进制新鲜度：

```text
binary build time: 2026-08-05 02:07:50.103011288 +0800
latest src commit: 5eb36c930 2026-08-05T01:28:46+08:00
latest source mtime: 2026-08-05 01:23:24 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

## 本阶段完整门禁

`./scripts/test-cl.sh`：

```text
cadr test summary: systems=9 checks=14730 pass=14730 skip=0 fail=0
```

`./scripts/verify.sh` 阶段汇总：

| 阶段 | 结果 |
|---|---|
| root cadr binary freshness | PASS |
| code organization gate | PASS |
| real source parity ledger | PASS（595） |
| source parity drift self-test | PASS |
| deterministic FiveAM | PASS（14,730/14,730） |
| isolated cadr build | PASS（无 core compression 时无压缩降级） |
| isolated cadr-server build | PASS（无 core compression 时无压缩降级） |
| Goal 11 performance and stability gate | PASS |
| native acceptance smoke | PASS |
| native process modes | PASS |
| migration PTY smoke | PASS |
| Unix socket server smoke | PASS |
| terminal lifecycle PTY | PASS（6/6） |
| deterministic TUI harness | PASS |
| fixed-baseline render differential | PASS（40/40；160/160 dispositions） |
| credential-gated FiveAM | PASS（7 pass / 1 Anthropic credential skip / 0 fail） |
| DeepSeek live TUI | PASS |

根二进制新鲜度：

```text
binary build time: 2026-08-04 23:09:05.548771652 +0800
latest src commit: 3dbb58b895a1f732d6354233e91d6981b0a35c09 2026-08-04T23:06:27+08:00
latest source mtime: 2026-08-04 23:02:37.363650132 +0800
binary version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```
