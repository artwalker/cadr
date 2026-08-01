# Goal 10 Part C 阶段报告

> 状态：CI 已在私有备份仓库真实跑绿；Part C 实现与测试均已提交落账。

## 1. 远端门禁

- 工作流：`.github/workflows/ci.yml`，触发于 push 与 pull request。
- 成功运行：<https://github.com/artwalker/cadr/actions/runs/30685704883>
- head：`1691bc643efe112ee8770b8fd390a9bbf35fe6a4`
- job：`verify`，结论 `success`，耗时 `2m37s`。
- 工作流只调用一次 `./scripts/verify.sh`；没有平行复制 build/test 逻辑。
- 权限只有 `contents: read`；checkout 固定为
  `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd` 且关闭
  credential persistence。没有 cache、artifact、`pull_request_target` 或 secret
  引用。

供应链输入固定为：

| 输入 | 固定值 |
|---|---|
| runner | `ubuntu-24.04` |
| SBCL | `2.6.7` |
| SBCL tarball SHA-256 | `4ed82aa7d5b1d87cbafb41ab9abc87d942d18eeac2485ee5a6c46b95aa694d19` |
| Quicklisp bootstrap SHA-256 | `4a7a5c2aebe0716417047854267397e24a44d0cce096127411e9ce9ccfeb2c17` |
| Quicklisp dist | `2026-01-01/distinfo.txt` |

SBCL 与 Quicklisp 安装在 runner 临时目录；`HOME`、`QUICKLISP_SETUP`、`SBCL`
均在 job 开始后从 `RUNNER_TEMP` 建立，避免读取 runner 或用户状态。Quicklisp
只下载 dependency audit 已在册的系统。CI 显式清空 Anthropic、DeepSeek、OpenAI
环境凭据，fresh HOME 中也没有 OAuth auth store。

## 2. 机械验收数字

`verify.sh` 的确定性套件在同一远端 job 中实际运行三次：入口一次、隔离
`cadr` 构建一次、隔离 `cadr-server` 构建一次；三次逐项一致：

| suite | checks | pass | skip | fail |
|---|---:|---:|---:|---:|
| cadr-ai | 1907 | 1907 | 0 | 0 |
| cadr-agent | 623 | 623 | 0 | 0 |
| cadr-tui | 1178 | 1178 | 0 | 0 |
| cadr-cli | 2700 | 2700 | 0 | 0 |
| cadr-storage | 23 | 23 | 0 | 0 |
| cadr-server | 45 | 45 | 0 | 0 |
| cadr-evals | 117 | 117 | 0 | 0 |
| cadr-protocol | 497 | 497 | 0 | 0 |
| **合计（每次）** | **7090** | **7090** | **0** | **0** |

隔离构建在该 SBCL 上不具备 `sb-core-compression`，两份 image 均按既定契约
降级为无压缩构建并成功。以下进程/终端级门禁全部为 `PASS`：

- native acceptance smoke；
- native process modes；
- migration PTY smoke；
- Unix socket server smoke；
- terminal lifecycle PTY；
- deterministic TUI harness。

终端生命周期日志另逐项确认 normal、ctrl-c、suspend-resume、input-editor、
completion、overlay 均恢复终端；人工 TUI harness 覆盖 overlay focus、CJK、图片
fallback、resize 与 terminal restore。

## 3. 无凭据 live 语义与本地覆盖差异

CI 没有注入 provider 凭据，因此 credential-gated FiveAM 正常完成并逐项报告：

| 项目 | CI 结果与原因 |
|---|---|
| DeepSeek chat stream | skip：`DEEPSEEK_API_KEY is not set` |
| Anthropic two-turn stream | skip：`ANTHROPIC_API_KEY is not set` |
| DeepSeek print mode | skip：`DEEPSEEK_API_KEY is not set` |
| OpenAI Codex explicit model | skip：OAuth 未配置 |
| DeepSeek eval smoke | skip：`DEEPSEEK_API_KEY is not set` |
| OpenAI Codex eval smoke | skip：OAuth 未配置 |
| DeepSeek self-extension eval | skip：`DEEPSEEK_API_KEY is not set` |
| DeepSeek fail/fix/pass eval | skip：`DEEPSEEK_API_KEY is not set` |

远端断言锁定 `Items: 8, run: 0, pass: 0, skip: 8, fail: 0` 与
`Checks: 8, pass: 0, skip: 8, fail: 0`；独立 DeepSeek live TUI 同样以缺 key
明确 skip。它没有把 skip 改写成 pass。具有 DeepSeek key 与 Codex OAuth 的本地
`verify.sh` 仍负责真实 live 调用；Anthropic 仅在具备相应凭据时运行。这与上游
官方 CI 不注入 provider 凭据、live 块自然 skip 的实际效果一致。

## 4. 首次 clean-run 揭示的问题

远端失败没有以“重跑”掩盖，而是逐项修正后才重新提交：

1. run `30685462833` 在建 job 前失败：`runner.temp` 不能用于 job-level `env`
   求值。改为 job 开始后的 `GITHUB_ENV`，并由合同测试禁止该无效写法。
2. run `30685517244` 暴露 TUI autocomplete 测试硬编码
   `/root/.local/bin/fd`。改为测试自行创建确定性 fake fd。
3. run `30685606013` 继续暴露两条 CLI autocomplete 测试依赖开发机 PATH 中的
   fd。新增共享 test helper，显式注入 fake fd 与临时 PATH；未修改产品代码。

本地此前未捕获后两项，是因为开发机同时存在 `/root/.local/bin/fd` 与
`/usr/bin/fdfind`；clean runner 没有。修复后全测试树搜索不再含真实 fd 的主机
路径。CI 合同测试
`GOAL10-PART-C-CI-WORKFLOW-IS-PINNED-MINIMAL-AND-CREDENTIAL-FREE`
现有 50 checks，锁定 action SHA、供应链 checksum、fresh HOME、既有依赖闭包、
唯一 verify 入口、无 secrets/cache/artifact 与无凭据报告全文。

## 5. 提交与边界

| commit | 内容 |
|---|---|
| `dc8052ee6` | pinned credential-free workflow 与合同测试 |
| `0797a7472` | 将 runner 路径延迟到 job 执行期 |
| `a1f23d8a2` | TUI autocomplete fixture 去主机耦合 |
| `1691bc643` | CLI autocomplete fixture 去主机耦合 |

- 新增第三方项目依赖：`0`；CI 安装的是既有运行/测试闭包。
- `origin` 未修改，工作流只推送至 private `backup`。
- 用户既有的 `docs/acceptance/goal-v8-final.md` 修改未暂存、未提交。
- Part C 实施与远端迭代约 20 分钟；系统未提供可按 Part 审计的 token 数，未
  伪造估值。
