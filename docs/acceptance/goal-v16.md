# Goal 16 验收记录

状态：Part A0 与 Part A 已完成；Part B 提案待提交，Part C/D 未获授权。

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

产物：`docs/identity-audit.md`。Part A 的 staged diff 仅包含该审计和本报告，
生产代码零变更。结果：

- 全量枚举得到 14 个不同的生产 `PI_*` 环境变量；
- 六组第三方归因字段及 xAI referrer 均为 `须替换`，已有用户预裁；
- Radius `pi-gateway` 有 live discovery 的注册合同证据，`radius.pi.dev` 是真实
  provider/API endpoint，二者不是推测性保留；
- `/share`、版本检查、HTML viewer meta 合同和环境变量迁移已分离为 Part B
  决策；
- 额外发现 export localStorage、notify 示例、synthetic tool call ID、Radius
  自由日志文案与导出 Lisp API 名残留；
- catalog 注释、固定基线 harness、版本对齐声明、扩展 manifest `"pi"` schema
  与 Radius wire dialect 已给出逐条保留理由。

Radius 外部核验（2026-08-04）：

```text
GET https://radius.pi.dev/             -> HTTP 200
GET https://radius.pi.dev/v1/oauth     -> HTTP 200
discovery.clientId                     -> pi-gateway
discovery.scope                        -> gateway offline_access
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
