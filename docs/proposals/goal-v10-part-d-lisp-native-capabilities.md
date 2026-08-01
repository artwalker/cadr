# Goal 10 Part D Lisp 原生能力提案

状态：**2026-08-01 已逐项批准；实现仍由 Part B 完成门禁。未修改生产代码、ASDF 或依赖审计。**

当前 cadr 实现基点：
`7fb06d093d5eebd7163e3271fdc3451c31aa213a`。当前行为基线仍为
`74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`；Part B 只会在上游稳定
`v0.84.0` 发布后重锁。本文已完成裁决，但任何实现必须同时满足：

1. Part B 已完成，且本文的源码位置与 object ID 已对新基线复审；
2. 实现严格留在本文获批的能力、依赖与文件面内；若最小实现面扩大，
   重新 blocked 交用户裁决。

## 1. 总边界

两项都是固定 TypeScript pi 没有的有意新增，不计入 parity 的
`C` 判定。获批实现后必须登记 README 差异清单与 parity-map，并遵守：

- 缺省路径完全不启用，既有 CLI、provider payload、system prompt、
  tool schema/description/result、session bytes、agent/JSON/RPC event 与 TUI 快照
  逐字节不变；
- 不引入审批、信任账本或新安全边界；仍是默认 YOLO，强隔离
  由容器、虚拟机或受限用户提供；
- 现有扩展宏签名、旧四事件、stale/snapshot/reload 语义零变更；
- 只能解冻本文列出的文件和符号。若 Part B 后的最小实现面扩大，
  立即 blocked，不得顺手跨越新冻结面。

开工冻结审计另发现：用 Goal 7/8 的相同取样命令，当前 HEAD 的
extension export SHA-256 实测为
`bb4665245ef9df19b274535071fcc5f6e56c79ab29db2152cd41afaa4df3b1e0`，
不是 `docs/architecture.md` 仍称“继续”的 Goal 8 历史值
`e0bcbf8c5f170efb99579fe6065579a8c2e93c7f1bd590b7502b08180ba54046`。
差异来自 Goal 9 已批准的 `define-markdown-transformer` 导出，不是本提案造成。
本次不冒充重冻；Part B 重建基线文档时先校正当前锚点，Part D
实现后再重算。

## 2. D1：工具失败现场的 condition/restart

### 2.1 确切需求与现状

目标是在 schema 校验或 tool executor 报错的原始栈仍存在时发出
`tool-execution-error`，同时建立“改参重试 / 跳过 / 中止 agent run”三个
restart。Common Lisp host 可用 `handler-bind`/`invoke-restart` 直接选择；
扩展可用一个新 hook 选择，并可通过已冻结的 extension UI 在
TUI/RPC 前端显示选择器。核心 TUI 不内置自动弹窗。

当前路径的决定性证据：

- `src/cadr-agent/tool.lisp:141-189`：`:tool-call-before` 及重校验后，
  schema condition 被 `handler-case` 直接转为 error tool result；
- `src/cadr-agent/tool.lisp:191-217`：executor 的任意 `error` 在解栈后仅保留
  `princ-to-string`，无可用 restart；
- `src/cadr-agent/loop.lisp:148-189,215-285`：`:tool-call-after` 与
  `:tool-execution-end` 只处理终态 outcome，批次可并行且结果按源顺序提交；
- `src/cadr-agent/extensions.lisp:949-982,3380-3462`：当前扩展事件不包含
  失败现场的决策点。

未知工具、`:length` 截断和 `:tool-call-before` 主动 block 不是
executor 失败，继续按旧路径生成结果，不建立这组 restart。

### 2.2 公开 condition 与 restart 契约

复用已导出的 `cadr-agent:tool-execution-error`；不修改其已有 reader。
condition 的 `message` 必须等于现有 tool result 文本，`cause` 保留原始
condition，`tool` 和 `tool-call-id` 保持已有含义。只新增并导出三个
restart name symbol：

| restart | 参数 | 精确语义 |
|---|---|---|
| `cadr-agent:retry-tool-call` | `(replacement-arguments)` | 保留 call id/name，用新 JSON object 从 `:tool-call-before` 开始重走，再次解析工具并做 schema 校验；每次重试都不绕过 hook 或校验 |
| `cadr-agent:skip-tool-call` | `(&optional reason)` | 不再执行，生成 `is-error=t` 的终态 tool result；缺省 `reason` 时逐字使用原失败文本 |
| `cadr-agent:abort-agent-run` | `(&optional reason)` | 先为当前逻辑 tool call 产生同上 error result，再进入既有 `agent-abort` 路径；当前批次完成收敛后不发新 provider payload |

restart 只在对应 condition 的动态范围内存在，不保存到 session，
也不把栈或 condition 序列化到 JSON/RPC。并行工具的 restart 按 call
隔离，一个 worker 不能查找或调用另一个 call 的 restart。

### 2.3 与 extension hook 的关系

新增事件 `:tool-call-error`，仍使用现有签名：

```lisp
(define-event-hook :tool-call-error
  :priority 0
  :handler (lambda (event context) ...))
```

`(extension-event-payload event)` 为严格只读 plist：

```lisp
(:condition <tool-execution-error>
 :tool-call <cadr-ai:tool-call>
 :arguments <hash-table>
 :attempt <positive-integer>
 :restart-names
 (cadr-agent:retry-tool-call
 cadr-agent:skip-tool-call
 cadr-agent:abort-agent-run))
```

`:arguments` 是 defensive deep copy，修改它不影响当前 attempt；改变行为的
唯一方式是返回经验证的 `:retry` result。

handler 返回 `nil` 表示不选择；非 `nil` 只允许：

```lisp
(:action :retry :arguments <hash-table>)
(:action :skip  :reason <optional-string>)
(:action :abort :reason <optional-string>)
```

第一个返回非 `nil` 且通过类型校验的 hook 短路后续 hook，核心在
condition 仍活跃时代为调用对应 restart。非法返回值只记录该扩展
失败并继续下一 hook，不改变工具结果。

时序冻结为：

1. 逻辑 call 只发一次 `:tool-execution-start`；
2. 每个实际 attempt 先跑 `:tool-call-before` 并重校验；
3. 失败时在现场跑 `:tool-call-error`；retry 回到第 2 步；
4. 只对最终成功、skip、abort 或无人处理的失败跑一次
   `:tool-call-after`；
5. 只发一次终态 `:tool-execution-end`。

因此 `:tool-call-after` 不会看到中间失败 attempt，旧扩展的“一个 call 对应
一个 after”不变。交互式审批仍不进核心；需要选择的用户由此
hook 调用 `extension-context-select` 并返回上述 action。

### 2.4 非交互模式与零变更保证

print、JSON 和 RPC 都不安装隐式 condition handler，也不自动选择
restart。无 `:tool-call-error` 扩展，或所有 hook 返回 `nil` 时：

- condition 沿现有边界转成同一个 `is-error=t` tool result；
- 文本仍是原 condition 的既有脱敏字符串；
- agent event 类型、数量和顺序不变；`:tool-call-error` 只是扩展内部
  lifecycle event，不加入 `agent-event` 或 JSON/RPC wire；
- `:tool-call-after`、会话持久化和下一轮喂给模型的 tool result 逐字节
  不变。

门禁将用同一 faux provider/tool condition 同时跑“开工 object”与“新实现缺省
路径”，递归比较 session JSON、model-visible result、agent events 及 text/JSON/RPC
完整输出，不用规范化或弱断言取得通过。

### 2.5 最小解冻面

以当前 HEAD 为提案审计点：

| 路径 | 当前 object ID | 仅允许变更 |
|---|---|---|
| `src/cadr-agent/tool.lisp` | `08beda50203d7af790d1690a06090ca7df82da23` | 原栈信号、restart cluster、重试/skip outcome |
| `src/cadr-agent/loop.lisp` | `118b99b97488a8640f9e825c50b6b7e1423f0769` | attempt 编排、abort 收敛、事件不变门禁 |
| `src/cadr-agent/extensions.lisp` | `39924113baa1928cb521dcf257e4afe9509bb0ca` | 仅新事件 payload/result 校验与调度 |
| `src/cadr-agent/package.lisp` | `05357d1575581916098191e14c1821f39a7a42e2` | 仅新增三个 restart name export |
| `test/cadr-agent/tool-loop-test.lisp` | `0e32eed1d92d96bb023f2e6f214687028993e53a` | condition/restart、并行隔离、旧路径快照 |
| `test/cadr-agent/extensions-wave2-test.lisp` | `cf16c937b667eb2252a45ec93585edc8d0a4d60a` | 新 hook 与旧扩展兼容门禁 |

`src/cadr-ai`、`src/cadr-cli`、`src/cadr-tui`、全部 `src/cadr-cli/tools/`、
ASDF 与 provider 实现继续冻结。实现前测试先红，至少锁定：

1. handler 观察 condition 时 executor 的 `unwind-protect` cleanup 尚未发生；
2. schema 失败和 executor 失败均可改参重试；新参数必须重跑 before hook 与 schema；
3. retry 多次时 before/error 按 attempt 发生，after/start/end 仍各一次；
4. skip 的缺省文本与旧 error result 逐字相同；abort 不发新 provider request；
5. 两个并行失败 call 的 condition/restart/arguments 互不泄漏；
6. `LEGACY-EXTENSION-SOURCE-REMAINS-COMPATIBLE-AFTER-WAVE-2-API-EXPANSION`
   无修改全绿，旧宏签名和旧四事件零变更；
7. 缺省路径的 session/model-visible bytes 与 text/JSON/RPC 输出完整对拍。

### 2.6 已考虑的替代方案

| 方案 | 否决理由 |
|---|---|
| 保留 `handler-case`，在解栈后普通循环重试 | 丢失原始栈和动态 restart，没有利用 Lisp 的核心能力 |
| 为 TUI 内置工具失败弹窗 | 把审批/策略重新塞进核心，违反默认 YOLO 和扩展边界 |
| 只暴露 condition，不给扩展 event | 外部 Lisp host 可用，但既有扩展无法在动态现场可移植地选择 |
| 自动按旧参数重试 N 次 | 引入基线没有的策略且对非幂等工具危险；retry 只能被 handler/hook 显式选择 |
| 序列化 condition/backtrace 到 JSON/RPC | 泄漏栈、扩张 wire 并破坏零观测变更；不做 |

### 2.7 冻结影响与回滚

此项限定解冻 tool/loop 内部执行边界和扩展事件集；不改工具
domain type、六/八个内置工具、旧 hook 结果或 wire。收尾时重算全部解冻
object ID、扩展事件集 hash 与现有 extension export SHA，然后重冻。

回滚只需移除 restart cluster、`:tool-call-error` 验证/调度及三个 export，
恢复现有 `handler-case → make-error-tool-result` 路径。无配置、session 或数据迁移。

## 3. D2：Slynk 远程 REPL

### 3.1 确切需求和公开界面

只在用户显式传入端口时，为当前 `cadr` 进程启动 Slynk：

```text
./cadr --slynk 4005
```

精确 CLI 契约：

- `--slynk <port>` 是需值选项；缺省不存在 listener，不读取配置或环境
  变量，也不记住上次值；
- port 必须是 `1..65535` 的十进制整数；不接受 `0`，避免为报告
  ephemeral port 污染 text/JSON/RPC stdout；
- 调用 `slynk:create-server :port port :interface "127.0.0.1"
  :style :spawn :dont-close t`；不提供 host/interface 选项，不解析
  `localhost`，不允许 `0.0.0.0`/`::`；
- bind 失败是启动 fatal configuration error，不降级为“无 REPL 继续”；
- 正常退出用 `slynk:stop-server` 关闭 listener，然后清空活动 agent
  引用。不写入 session/config，不修改工具或扩展发现。

新增一个只读公开入口：

```lisp
(cadr-cli:active-agent) ; => cadr-agent:agent | nil
```

它只返回当前 CLI 运行的 agent，不复制第二份状态，不提供写操作。
稳定检查流程是先调用已有 `cadr-agent:agent-wait-for-idle`，再读现有
agent/session accessor。在 SLY MREPL 中重新编译/定义具名工具辅助函数后，
SBCL 的全局 function binding 从下一次调用起生效；agent 和 session
对象不重建，session id、leaf 和历史不丢失。不承诺对已进入栈的
当前函数追溯替换。

当前接入证据：

- `src/cadr-cli/arguments.lisp:7-54,56-113,311-454`：参数对象、需值选项、
  flag 和未知参数已有唯一 parser；
- `src/cadr-cli/main.lisp:2700-2733`：agent 只在 CLI handler 内建立；
- `src/cadr-cli/main.lisp:3523-3935`：TUI/REPL/text/JSON/RPC 共用同一
  agent 和终端生命周期，适合在模式分发外层统一启停。

### 3.2 依赖预审与传递闭包

Slynk 是新第三方依赖，必须与能力本身分开授权。审计对象为当前
Quicklisp `2026-01-01` 的 `sly-20260101-git`，上游 commit
`e01c7b4b66876073b07edbc797188435eb098698`，archive MD5
`129945ec9a674a1efe353e2d3742fb00`。依赖闭包是：

```text
cadr-cli
└─ slynk/mrepl
   └─ slynk
      └─ ASDF
```

- Quicklisp `systems.txt:5548-5552` 只列 `slynk → asdf` 及各 contrib
  `→ slynk`；
- `slynk/slynk.asd:20-82,99-101` 的 core system 没有其他
  `depends-on`，`slynk/mrepl` 只依赖 `slynk`；
- SBCL backend `slynk/backend/sbcl.lisp:21-25` 运行时 `require`
  `sb-bsd-sockets`、`sb-introspect`、`sb-posix`、`sb-cltl2`；四者均为
  SBCL contrib，不是第三方闭包；
- 不引入 `slynk/fancy-inspector`、`arglists`、`profiler`、`stickers`、
  `trace-dialog`、`macrostep` 或 `named-readtables`。

Slynk 是纯 Common Lisp 编辑器协议服务器，无新 C ABI、动态库、密码学
或数据库依赖；但它开放任意进程内求值通道，因此不归入图片 codec
的“纯 Lisp 可替换”类目。若获批，`docs/dependency-audit.md` 和 README
将新增独立的“显式启用的调试服务”类目，按上述 snapshot 和闭包登记。

Slynk 上游绑定语义的审计证据：
`slynk/slynk.lisp:923-949` 的默认值是 `localhost`且 `create-server`
接受显式 `interface`；本提案不信任默认解析，始终传入
`127.0.0.1`。`Slynk` 可选读取 `~/.sly-secret`
(`slynk/slynk.lisp:1020-1035`)，但 cadr 不把该可选文件当作安全边界。

还有一个不能忽略的加载副作用：`slynk/slynk.asd:80-82`
在 ASDF load 后调用 `slynk::init`，而
`slynk/slynk.lisp:4217-4232` 会加载构建用户的 `.slynk.lisp` 或
`.slynkrc`。不能把个人配置、副作用甚至 secret 烘进发布 image。
因此正式构建和确定性测试必须先把已解析为绝对路径的
`QUICKLISP_SETUP` 保留下来，再以新建的空临时 `HOME` 启动 SBCL；退出时
删除临时目录。不修补 Slynk 源码，不信任构建机的点文件。

### 3.3 安全立场

`--slynk` 是对“这个进程允许本机同网络 namespace 的客户执行任意
Lisp”的显式启用，不是审批弹窗或权限沙箱。即使只监听 loopback，同一
host/container/network namespace 中的其他进程仍可能连接，并能读取
agent 状态、凭据和文件，或执行系统调用。

因此 README 必须明确：

- 默认关闭；不允许配置或环境变量静默开启；
- 只在可信机器上启用，需要跨机时由用户自行建立 SSH tunnel，cadr
  永不监听非 loopback 地址；
- 需要强隔离时，将 cadr 和 Slynk 一起放入容器/虚拟机/受限用户；
- 默认 YOLO 与该能力不矛盾：两者都不把核心弹窗当安全边界，
  但 Slynk 的任意求值风险必须由显式 CLI 开关告知。

### 3.4 最小解冻面

| 路径 | 当前 object ID | 仅允许变更 |
|---|---|---|
| `cadr-cli.asd` | `4c45e1ba78e10f6c499b1aab6e565305dcdecd94` | 新增 `slynk/mrepl`、一个 runtime 模块及测试装配 |
| `src/cadr-cli/package.lisp` | `143e4997bee670c28edbb03bd5f84c3a59288e88` | 仅导出 `active-agent` |
| `src/cadr-cli/arguments.lisp` | `39adf3ff684ac296b2f8af9ce6a1576dc1c798ac` | `--slynk <port>` 解析、校验与 help |
| `src/cadr-cli/remote-repl.lisp` | 新文件 | active-agent 锁、Slynk 启停和 loopback 固定参数 |
| `src/cadr-cli/main.lisp` | `a5b04bbee254c4b2b90519e5763b1269909efe34` | 只在 agent 建立后、mode 分发前安装/清理 runtime REPL |
| `test/cadr-cli/remote-repl-test.lisp` | 新文件 | parser、socket、eval/redefine/session 连续性与 stdout 快照 |
| `scripts/test-cl.sh` | `a2eb0f544a67b0ec868b70c86e7a40b2d1518510` | 仅为 Slynk ASDF init 提供空临时 HOME，保留绝对 `QUICKLISP_SETUP` |
| `build.sh` | `43826965957004c3b13c49d5ddd77c29b62d35b3` | 同样隔离会被保存到 native image 的 Slynk init |

`src/cadr-agent`、`src/cadr-ai`、`src/cadr-tui`、provider/tool 源码、
`build.lisp`/server/evals 继续冻结。`build.lisp` 只需 quickload `cadr-cli`，
不修改；Slynk
由 ASDF 进入 native image，不在运行时依赖 Quicklisp 源码。

测试先行，至少包含：

1. 无 `--slynk` 时端口不监听，help/version/text/JSON/RPC/TUI 的旧快照零变更；
2. 非整数、0、超界、缺值和端口冲突确定性失败；
3. 真实 socket 只 bind `127.0.0.1`，不出现 `0.0.0.0`/`::`；退出后端口可重用；
4. 通过真实 Slynk 协议连接 native image，求值
   `(cadr-cli:active-agent)` 取得当前 session id；
5. agent idle 时从 SLY 重定义一个测试工具辅助函数，下一轮返回新值；
   前后 agent identity、session id、leaf/history 连续；
6. 完整进程测试在不存在 Quicklisp 源码的隔离 HOME 下运行，证明
   native image 不做运行时加载；
7. 在构建用户 HOME 放置会创建 sentinel 的 `.slynkrc`，构建后断言
   sentinel 不存在且 image 中无该字符串；
8. 启用 Slynk 也不往 stdout、session、错误或日志写 credential，不破坏
   JSON/RPC framing。

### 3.5 已考虑的替代方案

| 方案 | 否决理由 |
|---|---|
| 自研 socket REPL | 重复编辑器协议、debugger、编译与线程集成，安全敏感且没有必要 |
| 只启动进程外 `sbcl --load` | 得到另一个 Lisp world，看不到活动 agent/session，重定义也不会影响运行进程 |
| 默认开启固定端口 | 不经用户选择即开放任意求值，不可接受 |
| 支持 `--slynk-host`/`0.0.0.0` | 把远程暴露、认证和防火墙策略带入 cadr；用户需跨机时应用 SSH tunnel |
| 用配置/环境变量静默开启 | 开关难以在命令行审计，且可被项目环境意外激活 |
| 只依赖 core `slynk`，不预载 MREPL | 能连接但不保证可用的编辑器 REPL，未满足本项要求 |
| 预载全部 Slynk contrib | 扩大代码面与功能面；本项只需 core + MREPL |

### 3.6 冻结影响与回滚

此项只解冻 CLI 参数/生命周期、一个只读 agent 入口、`cadr-cli`
ASDF 依赖面与构建/测试 HOME 隔离。获批实现后，收尾必须记录 Slynk
版本/闭包、重算八个
解冻 object ID，并重冻 `active-agent` 签名和 `--slynk` 行为。

回滚移除 `--slynk`、`remote-repl.lisp`、`active-agent` export 及 ASDF
`slynk/mrepl` 依赖，同步删除差异/依赖登记。无 session/config 迁移，旧二进制
与新二进制读取的数据格式完全相同。

## 4. 用户裁决与实现门禁

用户于 2026-08-01 逐项裁决：

1. `D1` **批准**：按第 2 节实现 condition/restart 与
   `:tool-call-error`。该事件是扩展事件全集第 34 个；Goal 8 的“33 个封顶”
   只为本次经完整提案、逐项裁决的新增解除。实现收尾时以 34 个事件的
   全集重新冻结；今后任何新增仍须重新提交书面提案并逐项裁决，不得从本次
   授权类推。届时重算 extension export SHA，同步 `docs/architecture.md`
   与 README，并把 `:tool-call-error` 标为相对基线的有意新增；
2. `D2-capability` **批准**：严格按第 3 节实现默认关闭、仅显式
   `--slynk <port>`、固定 `127.0.0.1`、跨机由用户自建 SSH tunnel 的
   `active-agent` 契约。README 必须如实说明这是任意求值通道，loopback
   不是沙箱，强隔离应使用容器、虚拟机或受限用户；
3. `D2-dependency` **批准**：依赖精确锁定 Quicklisp 2026-01-01
   `slynk/mrepl → slynk → ASDF`、上游 commit
   `e01c7b4b66876073b07edbc797188435eb098698`、archive MD5
   `129945ec9a674a1efe353e2d3742fb00`，且不得引入第 3.2 节排除的 contrib。
   `docs/dependency-audit.md` 与 README 实现时新增独立的“显式启用的调试
   服务”类目，不归入“纯 Lisp 可替换”；
4. `.slynkrc` 防烘入措施是强制门禁：构建与确定性测试均须在全新空临时
   `HOME` 中启动 SBCL，保留预先解析的绝对 `QUICKLISP_SETUP`，退出清理；
   不补丁第三方源码，不信任构建机点文件，并以回归证明发布 image 不含其
   任何副作用。

批准不解除执行顺序：Part B 必须先锁定并完成 `v0.84.0` 对齐，之后才能
复审 object ID 并开始 Part D 实现。当前不得提前修改生产代码、ASDF、依赖
清单、README 冻结值或 architecture 冻结值。

裁决落账复核（2026-08-01）：上游 GitHub Latest 仍为 `v0.83.0`
（发布于 2026-07-29），`v0.84.0` tag ref 仍返回 404；Part B 继续暂挂，
未改锁 HEAD。
