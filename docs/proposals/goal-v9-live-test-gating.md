# Goal 9 live 测试门禁定位提案

状态：**blocked，等待用户逐项裁决；获批前不调整任何 live 测试、ASDF system、
`test-cl.sh` 或后续 `verify.sh` 的门禁位置。**

固定基线：`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`，
checkout `/tmp/cadr-parity-74caa2649`。本文基线 `file:line` 均指该提交。

## 1. 问题与边界

OAuth 顺序依赖修复后，顾问连续三次复跑的 OAuth live 门禁均通过，但全量结果为：

| run | 已知 checks | 已知 fail | 结论 |
|---:|---:|---:|---|
| 1 | 6436 | 5 | DeepSeek self-extension live 失败；ASDF 未继续 protocol suite |
| 2 | 6933 | 0 | 通过 |
| 3 | 6933 | 0 | 通过 |

顾问没有在裁决输入中给出三轮各自的 pass/skip 数，本文不反推并冒充原始输出。
这组三轮只能证明真实模型行为有波动，不能作为确定性重复性证据。

本提案只裁决 live 测试的组织、退出语义与验收位置，不修改：

1. provider、agent、extension 或工具的生产实现；
2. live 测试的 prompt、断言、模型、temperature、retry 或工具面；
3. 凭据存储、刷新与隔离机制；
4. 无凭据时的 availability gate 语义；
5. 任何第三方依赖。

## 2. 基线 pi 的实际做法

### 2.1 live 块位于普通 Vitest 套件

基线 root `test` 执行所有 workspace 的 `test`：
`package.json:33-34`。`packages/ai` 的入口是普通 `vitest --run`：
`packages/ai/package.json:59`。

真实 provider 块使用 `describe.skipIf(!KEY)`。例如 DeepSeek 在
`packages/ai/test/stream.test.ts:448-472`；凭据存在时五个真实调用进入普通 suite，
其中单项声明 `{ retry: 3 }`。coding-agent 的真实 session 分支测试同样位于普通
suite，并以 `describe.skipIf(!API_KEY)` 门控：
`packages/coding-agent/test/agent-session-branching.test.ts:27-55`。

因此基线运行语义是：

- 无凭据：对应 live block skip；
- 有凭据且最终断言失败：Vitest 返回非零，所在 `npm test` 失败；
- `skipIf` 只解决 availability，不把真实 LLM 变成确定性测试。

### 2.2 官方 CI 实际不运行 provider live

基线 PR/push CI 在 `.github/workflows/ci.yml:32-42` 执行 install、build、check、
`npm test`，但 workflow 没有注入任何 provider key 或 `auth.json`。发布 workflow
也在 `.github/workflows/build-binaries.yml:253-263` 执行 `npm test`，同样没有
provider 凭据。

查证命令：

```text
rg -n 'ANTHROPIC_API_KEY|OPENAI_API_KEY|DEEPSEEK_API_KEY|OPENAI_CODEX|PI_AUTH_JSON' \
  .github/workflows/ci.yml .github/workflows/build-binaries.yml
(no output; exit 1)
```

结论必须分两层说：基线的 live 失败在**有凭据的本地 `npm test`** 中会阻断；但在
固定提交的**官方 CI/发布 test job** 中没有凭据，live 块全部 skip，因此不会阻断
官方 CI。不能用“它们写在普通 suite”推导“官方 CI 已实际验证 live”。

## 3. 当前 Cadr 的问题

当前 `scripts/test-cl.sh:19-26` 顺序执行八个 ASDF test systems。网络 live 文件混在
普通 systems 中：

| system | live 文件 | 当前后果 |
|---|---|---|
| `cadr-ai/tests` | `test/cadr-ai/live-provider-test.lisp` | provider 波动可在第一个 system 终止全量 |
| `cadr-cli/tests` | `test/cadr-cli/live-test.lisp` | CLI/OAuth 波动会阻止 storage/server/evals/protocol |
| `cadr-evals/tests` | `test/cadr-evals/live-evals-test.lisp` | agent 行为波动会阻止 protocol |

`test/cadr-cli/live-auth-test.lisp` 虽然名称含 `live`，但只使用临时 auth store 与
网络桩，是确定性回归，必须继续留在普通 suite。

该组织方式比基线官方 CI 更严格：本机固定存在 DeepSeek 与 Codex OAuth 凭据，所以
`test-cl.sh` 每次都会执行 live；一个行为型 LLM smoke 失败便让后续确定性 suite 没有
结果。于是“全量 checks”本身随模型输出变化，不能作为稳定工程门禁。

## 4. 建议裁决

### 4.1 裁决一：分离确定性与 live 入口

建议批准：

1. `./scripts/test-cl.sh` 只运行离线确定性 FiveAM suites；网络 provider live 文件从
   三个普通 ASDF test systems 移入独立 live systems；
2. 新增单一入口 `./scripts/test-live.sh`，只编排 credential-gated FiveAM live
   systems，不在 shell 中复制断言或解析模型文本；
3. `live-auth-test.lisp` 保留在确定性 CLI suite；
4. 无凭据仍逐项 skip 并打印原因，语义与基线 `skipIf(!KEY)` 同构。

这是相对固定基线新增的测试入口机制，故在本提案获批前保持 blocked。

**建议：批准。** 理由是官方基线 CI 本就通过“不提供凭据”把确定性 CI 与 live
事实分开；Cadr 只是把这一隐式边界变成可审计的显式入口。

### 4.2 裁决二：live 失败的阻断范围

建议批准以下双层语义：

- live 失败不得改变 `test-cl.sh` 的结果，也不得阻止尚未运行的确定性 suite；
- `test-live.sh` 必须运行完所有已启用 provider/surface 后汇总，任一已启用项失败则
  最终 exit `1`；不得在第一个 package 失败时丢失其余 live 结果；
- 不把失败自动改成 skip/warning，不自动反复运行直到转绿；
- 某次 live 失败只能由用户明确裁决为“接受外部波动”或“产品 blocker”，不得由后续
  一次绿色覆盖。

**建议：批准。** live 不应污染确定性门禁，但 dedicated live 命令必须保留真实
非零信号，否则分离会退化成藏红灯。

### 4.3 裁决三：Goal 9 Part D 与发布前门禁

建议批准：Part D 的 `scripts/verify.sh` 固定按以下阶段执行并分别报告：

```text
deterministic FiveAM -> isolated build -> deterministic process/PTY smoke
                     -> credential-gated live FiveAM -> live TUI smoke
```

规则：

1. 前三阶段为可重复的硬门禁；
2. 本机已登记可用的 DeepSeek 与 Codex OAuth 必须实际执行，不得被 skip；其他 provider
   继续 availability skip；
3. live 阶段失败时 `verify.sh` 最终 exit `1`，但必须先收集全部 live 结果；发布默认
   blocked，除非用户针对该次完整报告明确接受；
4. 发布报告同时列出 deterministic 与 live 两张表，禁止合并成一个“全绿”数字；
5. CI 无凭据时只证明 deterministic gate，与基线官方 CI 同构；README/报告必须列明
   本地 `verify.sh` 比 CI 多出的 live 覆盖。

**建议：批准。** 这使 live 不再决定工程套件是否可重复，同时仍是本地验收和发布前
必须面对的真实信号。

### 4.4 已确立规则：证据语言与数字纪律

用户本轮已直接确立以下永久规则，不等待本提案批准：

1. “连续 N 次全绿”只允许描述不含任何真实网络/LLM 调用的确定性入口；
2. 必须逐次列出 `checks / pass / skip / fail`，缺任一数字只能标为“不完整记录”，
   不得补算后冒充原始输出；
3. live 多轮结果写成“共 N 次：X pass / Y fail / Z skip”，并逐轮列完整数字；任何
   fail 都必须保留，后续 pass 不得覆盖；
4. 含 live 的组合 `verify.sh` 只能宣告“各阶段结果”，不得作为确定性证据；
5. provider/model、凭据门控状态、运行时间、失败面必须记录，但禁止写入 credential、
   token、完整敏感响应或用户 auth 内容。

这直接撤销此前把含 live 的五连跑称为确定性全绿的错误口径。

## 5. 最小实现与解冻范围（仅在批准后）

预计只修改测试与文档：

```text
cadr-ai.asd
cadr-cli.asd
cadr-evals.asd
cadr-live-test-support.asd
scripts/test-cl.sh
scripts/test-live.sh                 # new
test/cadr-ai/live-provider-test.lisp
test/cadr-cli/live-test.lisp
test/cadr-evals/live-evals-test.lisp
test/*/live-package.lisp             # 按需要新增专用 FiveAM suite
docs/architecture.md
docs/test-matrix.md
docs/parity-map.md
README.md
docs/acceptance/goal-v9-part-b.md
scripts/verify.sh                    # 仅在既定 Part D 实现
```

`src/` 全部冻结；不新增第三方依赖。若实现需要修改任何生产文件、改变 live 断言或
引入自动容错/retry，立即重新 blocked。

## 6. 已考虑但否决的方案

| 方案 | 否决理由 |
|---|---|
| 保持现状并把偶发失败记为 flaky | LLM 行为波动不是时序 bug；后续确定性 suite 仍被截断 |
| retry 到绿再算通过 | 隐藏失败率，继续制造“全绿”假象 |
| 放宽 self-extension 断言 | 会把 live 覆盖弱化，且本提案无权改变测试语义 |
| live 失败只 warning、永远 exit 0 | 红灯被边缘化，发布前无法形成真实约束 |
| 从仓库删除行为型 live 测试 | 丢失真实 agent/tool/extension 闭环证据 |
| 仅在 CI 注入真实凭据 | 基线 CI 没这样做；token 轮换、成本、外部波动会污染确定性 CI |
| 将 live 与 deterministic 数字继续合并 | checks 会因中止位置变化，无法比较覆盖回归 |

## 7. 请求用户裁决

请逐项裁决：

1. 分离 `test-cl.sh` 与 `test-live.sh`；
2. live 全面执行后汇总，失败只阻断 live/verify，不截断确定性 suite；
3. Part D `verify.sh` 与发布前必须实际运行本机可用 live，失败需用户明确裁决；

前三项获批前，本提案保持 blocked，不开始实现；第 4.4 节从本轮起已经生效。
