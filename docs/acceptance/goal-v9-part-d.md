# Goal 9 Part D 阶段报告

> 状态：本地单一验证入口已实现；有凭据与零凭据两种条件均实跑通过。

## 1. 入口与隔离边界

`./scripts/verify.sh` 固定执行：

1. deterministic FiveAM；
2. `mktemp` 工作树内的 `build.sh` 与 `build-server.sh`；
3. native image、process modes、migration PTY、Unix socket server、terminal
   lifecycle、deterministic TUI 六个保留 harness；
4. `test-live.sh` 的八项 availability-gated FiveAM；
5. `DEEPSEEK_API_KEY` 可用时的真实 TUI 两轮文件编辑。

隔离复制显式排除 `.git`、已有二进制、`.cadr`、`.pi-cl`、`.tmp-home`、
`.env*`、Obsidian 与 Python cache。脚本打印独立 deterministic/live 表；任一
已运行项失败最终 exit `1`，但 live FiveAM 失败不会阻止后续可运行的 live TUI。
本 Part 未创建或修改任何远端 CI 配置。

测试先行门禁
`GOAL9-PART-D-VERIFY-ENTRYPOINT-HAS-APPROVED-STAGE-CONTRACT` 在入口不存在时红
`1 check / 0 pass / 1 fail`；实现并锁定阶段顺序、隔离、摘要与无远端 workflow
后绿 `29/29`。

## 2. 有凭据实跑

命令：`./scripts/verify.sh`。耗时 `3m29s`。确定性阶段：

| 阶段 | 结果 |
|---|---|
| deterministic FiveAM | PASS，6952/6952，0 skip，0 fail |
| isolated cadr build | PASS；公共 build 入口重复同一 6952/6952 门禁 |
| isolated cadr-server build | PASS；公共 build 入口重复同一 6952/6952 门禁 |
| native acceptance | PASS |
| text/JSON/RPC/SIGTERM process modes | PASS |
| migration PTY | PASS |
| Unix socket server | PASS |
| terminal lifecycle PTY | PASS，3/3 |
| deterministic TUI | PASS |

live FiveAM 完整报告：

| 项 | 结果 | 检查/原因 |
|---|---|---|
| DeepSeek completions stream | PASS | 5 |
| Anthropic two-turn stream | SKIP | `ANTHROPIC_API_KEY is not set` |
| DeepSeek print | PASS | 3 |
| OpenAI Codex explicit OAuth model | PASS | 4 |
| DeepSeek eval | PASS | 4 |
| OpenAI Codex OAuth eval | PASS | 4 |
| DeepSeek self-extension | PASS | 6 |
| DeepSeek repository fail/fix/pass | PASS | 5 |

条目汇总：`8 items / 7 run / 7 pass / 1 skip / 0 fail`；检查汇总：
`32 checks / 31 pass / 1 skip / 0 fail`。随后 DeepSeek 真实 TUI 的 autocomplete、
undo、kill-ring、两轮 write/edit、resize、CJK 与 terminal restore 全部 PASS。

## 3. 零凭据实跑

使用全新临时 HOME、显式外部 Quicklisp 路径，并 unset
`DEEPSEEK_API_KEY`、`ANTHROPIC_API_KEY`、`OPENAI_API_KEY`。耗时 `2m11s`。
九个 deterministic/build/harness 阶段与有凭据条件相同，均 PASS；三个
deterministic FiveAM 执行仍各为 `6952/6952/0/0`。

live FiveAM 的八项全部按能力门控 SKIP：五项 DeepSeek 因缺 key，一项
Anthropic 因缺 key，两项 Codex 因临时 HOME 没有 OAuth。汇总为
`8 items / 0 run / 0 pass / 8 skip / 0 fail`、
`8 checks / 0 pass / 8 skip / 0 fail`。DeepSeek live TUI 明确显示
`SKIP (DEEPSEEK_API_KEY is not set)`。临时 HOME 随后删除；真实用户 auth 未被读取。

## 4. 证据纪律

- 有凭据原始日志：`/tmp/cadr-goal9-part-d-with-credentials.log`。
- 零凭据原始日志：`/tmp/cadr-goal9-part-d-without-credentials.log`。
- 两次组合入口只报告分阶段结果；不把含 live 的运行称为“确定性全绿”。
- 新增第三方依赖：`0`。
- Part 总耗时：约 1 小时，含设计、红绿测试及两次完整入口。
- token：产品未提供可审计的精确 Part token 计数，未伪造估值。
- 提交：本 Part 独立提交。
