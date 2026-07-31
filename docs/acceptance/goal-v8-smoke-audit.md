# Goal 8 smoke 与 live 证据审计

审计日期：2026-07-31。

审计判据：若验证在运行产品前改写/规范化真实输入、增加用户路径没有的
特判，或断言弱于所宣称的真实用户路径，则原“通过”证据无效。能以
`skipIf(!KEY)` 同构凭据门控表达的 provider/eval 行为必须进入 FiveAM；
只有必须观察原生进程、PTY/termios、Unix socket 或跨进程数据迁移的行为
保留为 shell harness。

## 结论

原 `live-openai-oauth-smoke.sh` 和 `live-evals-smoke.sh` 都把真实
`auth.json` 中的 `openai` 键用 `jq` 改名为 `openai-codex` 后才运行；
前者还显式传入 provider/model。它们只证明“改名并覆盖默认参数后可以
调用”，没有证明 `/login openai` 的产物或默认用户路径可用。此前两条
OAuth “live passed” 证据撤回。

七个可内置脚本已删除，其覆盖进入以下凭据门控测试：

- `test/cadr-ai/live-provider-test.lisp`
- `test/cadr-cli/live-test.lisp`
- `test/cadr-evals/live-evals-test.lisp`

第一次补正把 OpenAI live 门禁反向耦合到真实
`~/.cadr/settings.json`，并把可变的 `defaultModel` 钉死为 provider 内置
默认值。用户合法切换到 catalog 模型 `gpt-5.6-luna` 后，顾问独立复跑即
失败；该证据再次撤回。

最终机制按基线拆为两层：

- 确定性层使用临时 auth/config、登录桩和 HTTP 桩，覆盖
  `/login openai` 把凭据写到 `openai-codex`、默认模型解析取得该凭据并
  进入 Codex Responses 请求；它不读取 homedir。
- live 层只以凭据可用性门控，并在测试代码中显式指定 provider/model。
  CLI live 为隔离 settings/session/extension，逐字节复制真实 auth 文件到
  临时 HOME；不改键、不迁移、不规范化。eval live 直接从正确身份取得真实
  OAuth，再把显式 resolver 注入隔离 harness。

## 逐脚本审计

| 脚本 | 处置 | 绕过/弱断言审计 | 现在的实际覆盖边界 |
|---|---|---|---|
| `scripts/acceptance-smoke.sh` | 保留 | 隔离 HOME、种子 JSONL 和假 API key 是跨进程 session fixture；脚本不宣称 provider live，因此不是凭据绕过 | 原生 image 启动、延迟持久化、另两个进程的 `--continue` 与精确 `--resume`；不覆盖真实 provider |
| `scripts/goal5-manual-tui-smoke.sh` | 保留 | 使用专用 TUI harness，不是完整应用/provider 路径；此前文档将其限定为组件验收，断言与边界一致 | 真实 tmux PTY 下 overlay focus、CJK、图片 fallback、resize、termios 恢复 |
| `scripts/live-anthropic-smoke.sh` | 删除并内置 | 无输入改写，但只 grep 两个子串，弱于完整响应、事件终态和 usage | FiveAM 在 `ANTHROPIC_API_KEY` 存在时运行两轮精确上下文；本机无凭据则按基线跳过 |
| `scripts/live-deepseek-smoke.sh` | 删除并内置 | 无输入改写，但只 grep 子串 | FiveAM 精确断言响应、start/done 事件与正 usage |
| `scripts/live-evals-smoke.sh` | 删除并内置 | 用 `jq` 把 `openai` 改名为 `openai-codex`，构成绕过 | FiveAM 分别门控 DeepSeek/Codex eval；两者均在测试内显式指定 provider/model，并注入不读用户配置的 resolver |
| `scripts/live-extension-smoke.sh` | 删除并内置 | 无凭据改写；只靠输出/session grep，工具面边界未写明 | FiveAM 使用原精确扩展源码，限制为任务所需工具，断言路径、注册、tool result、最终响应和 tool usage |
| `scripts/live-openai-oauth-smoke.sh` | 删除并内置 | 用 `jq` 改 OAuth 键；原通过无效。显式 provider/model 本身符合基线 live 机制，但不能证明默认路由 | 确定性门禁证明 login/store/default resolver/Codex transport；live 门禁在隔离 HOME 中显式使用 `openai-codex/gpt-5.5`，只证明真实 OAuth 可用 |
| `scripts/live-print-smoke.sh` | 删除并内置 | 无输入改写；脚本只覆盖 stdout | FiveAM 在临时 HOME/workspace 通过真实 CLI handler 显式使用 DeepSeek，精确断言退出码、stdout 和 stderr |
| `scripts/live-repo-smoke.sh` | 删除并内置 | 额外 `CADR_ALLOW_LIVE_TOOL_SMOKE=1` 是原版没有的授权机制；session grep 只做间接断言 | FiveAM 仅按 `DEEPSEEK_API_KEY` 门控；fixture 让未修复代码的首跑必为 code 1 并留痕，要求 `test.sh` 逐字节未改、磁盘修复、最终测试和 code 0；允许最多三次完整隔离尝试，但只接受同一次尝试内证据全部成立 |
| `scripts/live-tui-smoke.sh` | 保留 | 显式 DeepSeek provider/model，所以不证明默认选择或 OAuth；其声明一直是终端交互而非默认配置 | 真实二进制、tmux PTY、autocomplete/undo/kill-ring、两轮工具编辑、CJK/resize/termios；FiveAM 无法忠实模拟终端驱动 |
| `scripts/migration-smoke.sh` | 保留 | 假 key 与 loopback SSE 是迁移后的可控 continuation fixture，不宣称 provider live | 非交互 fail-closed、PTY 确认、目录原子移动、权限与跨进程 continuation |
| `scripts/server-smoke.sh` | 保留 | 无 provider 输入改写；断言真实 socket 返回结构 | 两个原生二进制、Unix socket、supervisor/child 多进程及 spawn/list/status/RPC/stop |
| `scripts/test-wave2-process-modes.sh` | 保留 | loopback SSE 是协议 fixture；脚本不宣称 live provider。审计重跑发现旧版固定 sleep 50ms 可能在进程已自然退出后才发信号，实际得到 exit 0；已改为等待服务端 request marker 证明请求在途 | 原生进程的 text/stdin/JSONL/RPC UI/EOF、真实在途请求上的 SIGTERM 143 与 shutdown hook |

## 补正后的实跑结果

全量 `./scripts/test-cl.sh`：

```text
3043 checks
3042 pass
1 skip: LIVE-ANTHROPIC-STREAM-PRESERVES-TWO-TURN-CONTEXT
0 fail
```

本地可用凭据两条均真跑：DeepSeek provider/print/eval/self-extension/
repo repair 全绿；Codex OAuth 显式 CLI 与显式 eval 全绿。正式全量运行前后，
用户 settings 均为 `openai-codex/gpt-5.6-luna`，证明 live 测试既不钉死也
不改写个人模型选择。测试重构提交：
`c73f27dffce029cefd29393015b0fc212ed47eca`。

此前真实 TUI 登录后，`auth.json` mode 0600 且含旧 `openai` 与新
`openai-codex` 两个键，settings 当时为 `openai-codex/gpt-5.5`；不重启、
不传 provider/model 的同一 session 精确回复 `OAUTH_TUI_DIRECT_OK`。这是
产品路径的人工证据，不再混入自动 live 门禁。

## 用户可变状态自查

| FiveAM live 面 | 自查结果 | 处置 |
|---|---|---|
| `test/cadr-ai/live-provider-test.lisp` 两条 provider stream | 只读环境凭据，显式 provider/model，消息历史由测试构造 | 无需修改 |
| `LIVE-DEEPSEEK-PRINT-MODE-EMITS-ONLY-FINAL-TEXT` | 原来虽显式选型和 `--no-session/--no-extensions`，仍会加载真实 HOME 的 config/settings/model store | 改为临时 HOME/workspace；不复制任何个人文件 |
| 原 `LIVE-OPENAI-OAUTH-LOGIN-DEFAULT-ROUTE-IS-DIRECTLY-USABLE` | 读取真实 settings 并断言用户模型等于内置默认；失败即源于此 | 删除该 live 契约；改为确定性 login/default-route 门禁 + 隔离 HOME 中显式 Codex live 门禁 |
| `LIVE-DEEPSEEK-EVAL-SMOKE` | eval 选择显式，但默认 resolver 仍会读取真实 config/auth | 注入只含测试 key 与显式模型的 DeepSeek resolver |
| Codex eval smoke | 默认 resolver 读取真实 config/auth，且把错误身份存在视为失败 | 只用正确身份作为 gate，取得真实 OAuth 后注入显式 Codex resolver |
| DeepSeek self-extension 与 repository repair | harness 已隔离 project/session/extension，但 resolver 仍读真实 config | 复用显式 DeepSeek resolver；原有隔离目录与空扩展启动断言保留 |

结论：实际 provider live 共八个测试；除两条 `cadr-ai` provider stream
原本合规外，其余六条均已消除对用户 settings、已选模型、会话历史和已装
扩展的隐式读取。

两套 build 均在当前 SBCL 缺少 `sb-core-compression` 时明确降级并成功：

```text
cadr         65,348,488 bytes  mode 0755  version cadr 0.1.0
cadr-server  57,155,288 bytes  mode 0755  version cadr-server 0.1.0
```

六个保留脚本全部在最终 build 后运行通过；其中 process-modes 修正同步后
连续通过两次：

```text
acceptance smoke: delayed persistence, --continue, and exact --resume passed
wave2 process modes: text, auto-stdin, JSONL, RPC intervention/UI/EOF, and SIGTERM cleanup passed
migration smoke: refusal, full move, auth mode, and --continue passed
server smoke: spawn/list/status/RPC/stop over Unix socket passed
goal5 manual TUI smoke: overlay focus, CJK frame, image fallback, resize, and terminal restore passed
live TUI smoke: autocomplete, undo, kill-ring, DeepSeek two-turn edit, resize, CJK, and terminal restore passed
```

绕过残留检查：

```text
rg -n 'jq.*(openai|openai-codex)|CADR_ALLOW_LIVE_TOOL_SMOKE|has\("openai"\)' scripts test cadr-ai.asd cadr-cli.asd cadr-evals.asd
# no output
rg -n 'live-(anthropic|deepseek|evals|extension|openai-oauth|print|repo)-smoke\.sh' scripts cadr-*.asd
# no output
```

## 顺手发现但不在本次修复范围

自扩展 live 测试若开放全部默认工具，模型可能在隔离目录外执行宽范围
`find`。这与项目已裁决的原版默认 YOLO/由用户容器隔离的安全模型一致，
不是本次产品缺陷；测试现以所声明的扩展任务工具面限定证据范围，不向核心
添加审批或沙箱机制。

历史进度文档中引用已删除脚本的命令输出只保留为当时记录；其中 OAuth
“通过”由本审计明确撤回，当前验收只能引用新的 FiveAM 门禁结果。

真实 `/login openai` 后的同一 session 请求确实使用
`openai-codex/gpt-5.5` 并成功，但 footer 仍显示启动时的
`deepseek-v4-flash`。这不影响实际路由或持久化；当前实现把启动瞬间的
`(cadr-agent:agent-model agent)` 作为值传给 TUI（
`src/cadr-cli/main.lisp:3337`），疑似未随模型切换刷新。按本次范围要求只
记录并排入 Goal 9，不修改 TUI。
