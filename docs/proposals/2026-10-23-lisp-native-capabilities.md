# Lisp 原生能力提案

状态：未裁决。本文只提出设计，不授权写实现。新机制按 `docs/development-policy.md` 第 3 节，要等用户逐项裁决之后才能进 `docs/open-questions.md` 并开工。

2026-10-23 更正。上一版把 `get_state` 的字段写少了，把帮助文本的锁写成了不存在的排除名单，并把「换掉下一次工具调用」说成 Node 做不到。这三处下面已改。方向 4 补上了同用户子进程仍能读到父进程文件和环境，读入过滤挡不住 `#,` 和 `in-package`，以及 `--self-extend` 在没有 bash 时也是父进程里的代码执行。

日期：2026-10-23。cadr 侧行号对着 `cadr-migration` 的 `7f6db4d72`。上游行号用 `git show v1.4.0:<路径>`，提交 `4a080252f06caf63a525d7873c5d94d3c23887e0`。Goal 27 在 `goal27-parity` 上并行，实现时不要进那条分支，也不要把本文和任何对齐补丁打在同一个提交里。

这篇要回答的是对齐完成之后，哪些事只有 Lisp 做得成，而且默认跑起来仍和 pi v1.4.0 一样。判断标准用政策第 1 节：Lisp 原生要拿出可核对的好处。换一种拼写不算。政策第 6.6 节已经把「用条件系统改写 agent 自己的失败行为」排除在开发工具之外，因为它会改可观察行为。下面凡是碰到失败路径的，都按这条写，不靠「用了 Lisp」过关。

工作量用四档。S 是已有入口上的一个默认关闭函数，测试只锁「没人调用时行为不变」。M 是几个新文件，不改回合循环。L 是要碰到加载器或回合，并且把已有事件序列锁住。XL 是子进程、模型能调用的工具、凭证边界，单独裁决。

## 现状

发布用的二进制是一个 SBCL 镜像。`build.sh` 在空的 `HOME` 里跑 `build.lisp`，后者加载 `slynk/mrepl` 然后 `sb-ext:save-lisp-and-die` 写成 `cadr`。正在跑的进程就是这个镜像，不是每次请求拉起来的新运行时。

人连进这个进程的入口已经有了，而且只此一个。`src/cadr-cli/remote-repl.lisp` 的 `start-remote-repl` 调用 `slynk:create-server`，接口固定 `"127.0.0.1"`。`docs/architecture.md` 第 28 节写明：`--slynk <port>` 是唯一开关，配置和环境变量不能悄悄打开，回环不是沙箱。`docs/parity-map.md` 把它记成默认关闭的有意差异，不进基线帮助文本。帮助文本的字节锁是 `test/cadr-cli/part-b-cli-test.lisp` 的 `print-cli-usage-plain-bytes-match-shipped-literal`，对照 `test/fixtures/cli-usage-plain.txt`。`cli-help-matches-the-baseline-printhelp-contract` 只查几段子串，包括没有 `--alt` 和 `--yolo`。`--slynk` 只出现在那个测试的注释里。没有一份排除名单可以往上加新旗标。

工具失败上的重启也已经有了。`src/cadr-agent/loop/tool-execution.lisp` 的 `call-tool-operation-with-restarts` 在栈还在的时候建立 `retry-tool-call`、`skip-tool-call`、`abort-agent-run`。没人做选择时，它仍交出原来的错误工具结果。`:tool-call-error` 只在扩展生命周期里出现，不进 agent 事件、会话、JSON 或 RPC。`docs/architecture.md` 第 28 节把合法返回值冻成 retry、skip、abort 三个，并写明以后加事件或改重启语义要重新提案。这是 `OQ-G10-D1-TOOL-RESTARTS` 的已落地边界。

扩展是 Lisp，加载进镜像。`src/cadr-cli/extensions/loader.lisp` 的 `load-extension-source` 为每个扩展建包 `CADR-EXTENSION/<id>/<代>`，`:use` 只有 `:cl` 和 `:cadr-agent`。加载失败就 `delete-package`。`reload-cli-extensions` 在失败且路径没变时留着上一份成功的 bundle。交互里的 `/reload` 走 `src/cadr-cli/bootstrap/commands.lisp`，和 pi 一样重载扩展、资源和设置。`OQ-G20-EXTENSION-ISOLATION` 已裁过：不再加 `sb-ext:lock-package`。pi 的扩展没有沙箱，cadr 现在的包隔离并不比它弱。

provider 失败的默认路径是自动重试，不是给人挑。`src/cadr-agent/loop/turns.lisp` 在预算内发出和 pi 对应的 auto-retry 事件，预算用尽就把错误消息留下来。`turns.lisp` 在这次测量时是 1024 行，已经落在组织门禁的 `>=1000` 档里。`commands.lisp` 是 3067 行。`registration.lisp` 是 900 行。`loader.lisp` 是 716 行。`tool-execution.lisp` 是 546 行。新逻辑不进这些文件。Goal 14 的 `goal14-b9-extension-host-has-exact-owners` 把八个扩展属主文件的顶层定义数钉死，在 `7f6db4d72` 上是 270。Goal 27 那条分支正在改这个数字。实现时以落地当天的钉为准，办法是新文件，而不是往这八个文件里加定义。

`OQ-G20-AGENT-EVAL-TOOL` 在 2026-08-13 裁过：不把求值交给模型。理由是活镜像里的修改对不上任何提交，而且模型和被测对象是同一个。重启条件是先证明有一类缺陷只有活镜像调试找得到。本文不推翻这裁。方向 4 把问题收窄成另一件事。

## 不立项：宏层面的扩展 DSL

pi 的 `defineTool` 是恒等函数。`git show v1.4.0:packages/coding-agent/src/core/extensions/types.ts` 第 690 到 693 行把传入的工具对象原样返回，用来保住 TypeScript 的参数推断。它短，也没有在加载时多做检查。

cadr 已经有一层宏。`src/cadr-agent/extensions/registration.lisp` 第 809 到 811 行写着 Goal 12 冻住了这些公开 lambda list，`register-*` 是实现属主，宏只拼这层表面。`define-tool` 展开成 `register-extension-tool`。再做一个更短的 `define-tool*`，只是第二种拼写。政策第 1 节不把这个算成 Lisp 原生。它也让同一个决定有两个属主，正是 `docs/code-organization.md` 要挡住的事。

宏真正用得上的地方，已经折进方向 2 和方向 3：处理函数按符号登记，这样 `load` 能换掉函数槽；处理函数体内的 `restart-case` 能把扩展自己的恢复动作放进 `compute-restarts`。这两件事不需要一套新的公开 DSL，也不改 Goal 12 冻住的 lambda list。

TypeScript 做不到「更短所以更安全」这一跳。pi 的短已经在 `defineTool` 里了。安全来自编译进同一镜像和重启还挂在栈上，不来自少写几个关键字。

## 方向 1：活镜像

### 用户得到什么

能力本身已经在镜像里。开发时这样用：

```sh
cadr --slynk 4005
```

另一边用 SLY 连 `127.0.0.1:4005`，求值 `(cadr-cli:active-agent)`。返回的是 TUI 正在用的那个 agent 对象。可以看槽、看队列、看当前条件，也可以重定义函数，然后让下一次调用走进新函数。会话文件还是原来那个，进程不重启。

建议新增的只有一个给这个 REPL 用的只读快照，避免每个人临时扒槽位：

```lisp
(cadr-cli::agent-live-snapshot (cadr-cli:active-agent))
```

返回一个 plist：会话 id、模型、是否在流式输出、自动重试的 attempt 和上限、当前工具名、工具重启次数、扩展包名列表。没有求值，没有 `load`。

不建议再做第二个监听。不听 TCP，不听 Unix socket，不加 `CADR_*` 开关。`remote-repl.lisp` 继续是这一决定的唯一属主。

### pi 里对应的做法和限制

pi 没有进程内 REPL。交互模式的 TUI 不提供第二终端来看正在跑的 agent。RPC 的 `get_state` 在 `git show v1.4.0:packages/coding-agent/src/modes/rpc/rpc-types.ts` 第 96 到 109 行。`RpcSessionState` 有模型、thinking level、是否在流、是否在压缩、steering 和 follow-up 的模式、会话文件、会话 id、会话名、自动压缩开关、消息数和待处理消息数。没有自动重试的 attempt，没有工具重启次数，也没有扩展实例。而且只有 `--mode rpc` 才有这条命令。正在跑的 TUI 会话对不上它。

Node 的 `--inspect` 可以连上进程求值，也可以改对象上的属性。那是调试器协议，不是产品命令。已经抓住旧函数对象的调用方不会跟着变。pi 自己的重载会把旧扩展上下文标成失效，见方向 2。

Lisp 这边函数槽是语言的一部分。`defun` 更新符号的函数，下一次通过符号的调用走进新定义。CLOS 重定义类时，已有实例走 `update-instance-for-redefined-class`。这两件事 pi 的模块系统和调试器都没有对应物。它们已经由 `--slynk` 交给人用，不需要再造一个监听来「获得」它们。

### cadr 的设计

系统是 `cadr-cli`。新文件 `src/cadr-cli/live-snapshot.lisp`，在 `cadr-cli.asd` 里放在 `remote-repl` 旁边。它只读 agent 的公开访问器，不改槽，所以不是 `runtime.lisp` 的第二个属主。函数不放进 `cadr-agent` 的导出列表。扩展的包 `:use` 了 `cadr-agent`，导出会变成扩展里的一个普通名字。

REPL 里调用的是 `cadr-cli::agent-live-snapshot`。不导出。参数是 agent。返回上面的 plist。不导出求值器，不导出 `load`。扩展仍可以写出 `cadr-cli::` 这个前缀，这和今天任何内部符号一样。函数不返回凭证，所以这条路漏出去的是会话 id、模型 id 和计数。

`src/cadr-cli/remote-repl.lisp` 不动。`--slynk` 的绑定、端口检查、退出时 `stop-server` 和清掉 `*active-agent*` 保持现在的合同。

### 和对齐的关系

默认进程不传 `--slynk`，不监听。`print-cli-usage` 的输出字节与 `test/fixtures/cli-usage-plain.txt` 一致。`agent-live-snapshot` 没有命令行入口，没有事件，没有会话字节。没人从 REPL 调用它时，回合路径碰不到它。

不把快照接进 RPC 的 `get_state`。那会改变基线的状态字段。

### 安全风险和对策

Slynk 能在进程里求值任意 Lisp。`docs/architecture.md` 已经写明它不是安全边界。对策保持现状：默认关，唯一入口是显式 `--slynk`，只绑 `127.0.0.1`，没有配置项，没有环境变量后门。跨机器由用户自己做 SSH 隧道。强隔离仍然是容器、虚拟机或单独的用户。

新的快照函数只读。它不接受字符串当代码。实现时不要在快照里放系统提示、工具参数原文、`auth.json` 的内容或请求头。那些会进 REPL 回显，而政策第 3 节不许凭证进日志和会话。会话 id、模型 id、计数和包名够用。

不监听网络端口。如果裁决要一个不用 Emacs 的查看器，唯一还能接受的加法是：人已经连上现有的 Slynk 之后调用这个函数。不要新开端口。

### 怎么测试

已有的 `test/cadr-cli/remote-repl-test.lisp` 继续锁 `--slynk` 的端口合同和回环。新的 FiveAM 在 `test/cadr-cli/` 里对一个构造出来的 agent 调用 `cadr-cli::agent-live-snapshot`，锁字段集合和「不包含授权头、不包含系统提示」这两条。符号不在 `cadr-agent` 的导出列表里。再锁一条：不传 `--slynk` 时 `start-remote-repl` 不被调用。这是现有启动路径，新测试不要放宽它。

FiveAM 锁不住「人在 SLY 里重定义了函数」。那是现场诊断，政策第 6.1 节要求事后用 FiveAM 把触发条件钉住，而不是把 REPL 抄本当成门禁。

### 工作量

S。没有依赖。若裁决连快照函数也不要，工作量是零，方向 1 到 `--slynk` 为止。

## 方向 2：用 Lisp 写扩展，并在不拆会话的情况下换掉函数

### 用户得到什么

默认的 `/reload` 保持现在的行为，和 pi 一样。新能力是另一个命令，只有显式旗标打开时才存在。

```sh
cadr --redef
```

在 TUI 里改完 `~/.cadr/extensions/tools.lisp`，输入 `/redef`。同一个会话文件还在，屏幕上的对话还在，扩展上下文不失效。下一轮工具调用走进新函数。正在栈上跑的那一次调用走完旧函数，不中途换掉。编译失败时，已经登记的函数留在原地，TUI 打出编译器诊断。

没有旗标时，输入 `/redef` 和输入一个不存在的斜杠命令是同一条路径。

### pi 里对应的做法和限制

pi 可以重载扩展而不丢掉会话文件。`git show v1.4.0:packages/coding-agent/src/core/agent-session.ts` 第 3720 到 3755 行的 `reload` 先对旧 runner 发 `session_shutdown`，原因是 `reload`，然后 `invalidate`，再重建运行时，成功后发 `session_start`，原因仍是 `reload`。会话管理器还在，所以 JSONL 还在。

`invalidate` 的默认消息在 `git show v1.4.0:packages/coding-agent/src/core/extensions/runner.ts` 第 729 到 730 行。旧的 `ctx` 在 `reload` 之后再被用，会抛「stale after session replacement or reload」。捕获了旧工具对象的调用方不会看见新函数。加载器用 jiti，`git show v1.4.0:packages/coding-agent/src/core/extensions/loader.ts` 第 579 到 584 行把 `moduleCache` 设为 false 再 `import`。这会读到新文件，但新工厂要等 runner 重建之后才接上。

所以「重载而不丢会话文件」pi 已经做到了。pi 选择在重载时拆掉 runner。换掉下一次调用并不需要拆 runner。`executePreparedToolCall` 每次都读 `prepared.tool.execute`，`git show v1.4.0:packages/agent/src/agent-loop.ts` 第 842 行。把这个属性换成新函数，下一次调用就走新函数，不必发 `session_shutdown`。jiti 把 `moduleCache` 设成 false 不会改已经放在工具对象上的函数。cadr 把处理函数存成函数对象时，是同一件事。符号的函数槽是 Lisp 里现成的间接层。一个可变的格子，TypeScript 写一个属性就有。

方向 2 还值得做的是这个产品行为，不是一门语言独占的能力。`/redef` 在不发 `session_shutdown`、不把旧 ctx 标失效的前提下装进新定义。pi 今天不这么做。Lisp 仍然多一件事。通过符号或 CLOS 方法调用的代码，`load` 之后全部看见新定义，不用把每个已经存下来的函数对象找出来改掉。扩展处理函数若继续存成函数对象，就要改那一格，Lisp 和 TypeScript 一样。所以 `/redef` 成功之后把那一格换成符号，下一次 `load` 才能碰到所有经由这个符号的调用，而不只是工具表里的那一个槽。

### cadr 的设计

今天的加载器做的是 pi 那种换代，不是换函数槽。`load-extension-source` 每次 `make-package` 一个新代，`register-extension-tool` 把处理函数存成函数对象。`/reload` 必须继续走这条路，这样 `session_shutdown` 和 `session_start` 的原因字符串保持和 pi 一致。

新命令走新文件，不进 `loader.lisp`。

| 文件 | 系统 | 职责 |
|---|---|---|
| `src/cadr-agent/extensions/redef.lisp` | `cadr-agent` | 把同一包里的新 fasl 装进已有 bundle。处理函数按符号调用。 |
| `src/cadr-cli/extensions/redef.lisp` | `cadr-cli` | `/redef` 的属主。先走方向 4 的子进程编译，成功才把 fasl 交给上一行。 |

`cadr-agent.asd` 的 `extensions` 模块在 `lifecycle` 之后加 `redef`。不要把它算进 B9 那八个属主，`goal14-b9-extension-host-has-exact-owners` 数的就是那八个文件。`cadr-cli.asd` 的 `extensions` 模块在 `loader` 之后加 `redef`。

`src/cadr-cli/bootstrap/commands.lisp` 只加一次条件调用：旗标开着且整行是 `/redef` 时，交给 `cadr-cli:redef-loaded-extensions`。旗标关着时不看这个命令。不要把重载逻辑写进 `commands.lisp`。

对外接口：

```lisp
(cadr-cli:redef-loaded-extensions manager)
```

返回 `:loaded` 或一个条件。成功时不调用现有的 `reload-cli-extensions`。失败时不 `delete-package` 那个已经在服务的包。

处理函数的存储：默认注册仍保存函数对象，这是现有扩展的合同。`/redef` 成功之后，bundle 里对应工具的处理函数换成符号，之后 `funcall` 符号就会看见新的函数槽。第一次 `/redef` 之前的行为与现在一致。

顶层有副作用的文件不能在父进程里 `load` 到一半。所以 `/redef` 依赖方向 4 的子进程：子进程 `compile-file` 失败就不产生给父进程的 fasl。父进程只 `load` 这个 fasl。子进程的做法见方向 4，这里不重复。

### 和对齐的关系

`/reload` 的实现函数不变，事件顺序不变。新测试要锁：不论 `--redef` 开没开，`/reload` 仍然发出 `session_shutdown` 和 `session_start`，原因都是 `reload`。

`--redef` 按 `--slynk` 的先例处理。不写进 `print-cli-usage`，所以 `test/fixtures/cli-usage-plain.txt` 的字节不变。旗标写进 README。`docs/parity-map.md` 在实现那个提交里追加一条，和 `--slynk` 一样记成默认关闭。不新造一个有意差异类别。没有排除名单。新旗标一旦出现在 `print-cli-usage` 的输出里，`print-cli-usage-plain-bytes-match-shipped-literal` 就会红。

没有这个旗标时，斜杠命令表就是 `docs/parity-map.md` 里从 `/settings` 到 `/quit` 的那一份，其中包含 `/reload`，不包含 `/redef`。

不改设置 schema。pi 的 `settings` 里没有这个键，加键会让设置差分测试失败。开关只做旗标。

### 安全风险和对策

`/redef` 会在正在跑的进程里执行新文件的顶层形式。这和今天 `/reload` 会 `load` 扩展一样，权限就是用户自己的扩展。对策是子进程先编译，父进程只接收 fasl，而且只在用户传了 `--redef` 时存在这条命令。

不要让 `/redef` 加载扩展目录以外的路径。路径先规范化，必须落在已经发现的扩展源上。这能挡住把 `/redef` 当成通用 `load` 用。

子进程的环境和凭证见方向 4。父进程的 `load` 仍然在扩展自己的包里，`:use` 列表不扩大。`OQ-G20-EXTENSION-ISOLATION` 的结论不变。

### 怎么测试

FiveAM 能锁的是构造出来的 bundle，不必开 TUI。

- 旗标关闭时，`/redef` 的分发函数不被调用，未知斜杠命令的返回值和一个随机命令相同。
- 旗标打开时，先登记一个工具，处理函数返回 `"old"`。对同一包编译一个返回 `"new"` 的定义并装入。下一次调用返回 `"new"`。会话路径字符串不变。不发出 `session_shutdown`。
- 子进程编译失败时，下一次调用仍返回 `"old"`，包没有被删掉。
- `/reload` 在两种旗标下都发出原来的 shutdown 和 start。已有的重载测试继续当这条的锁，新测试只补「开着 `--redef` 时 `/reload` 没有改道」。

FiveAM 锁不住「人在 TUI 里看着同一屏对话」。那是人工看一次就够的部分。事件和会话路径可以锁。

### 工作量

L。依赖方向 4 的子进程编译，不依赖模型能调用的那个工具。子进程那一片可以先落地，见文末顺序。

## 方向 3：条件与重启驱动的恢复

### 用户得到什么

自动重试的预算、退避和打断键保持 pi 的样子。`git show v1.4.0:packages/coding-agent/src/modes/interactive/components/status-indicator.ts` 第 56 行是 `Retrying (attempt/max) in Ns...`，打断键取消。cadr 的默认路径继续这么做。

旗标打开并且当前是交互 TUI 时，预算用尽、错误还没写进最终助手消息之前，TUI 列出当时栈上的重启。内建三个：

```text
rate limit. restarts:
  retry-now
  switch-model
  abort-turn
```

选 `switch-model` 再给一个模型 id，同一次回合用新模型再请求一次。选 `abort-turn` 的结果和现在预算用尽时留下的错误消息相同。打断键走现有的中止路径，不另做一套。

工具失败时，同一个旗标让 TUI 通过已经批准的 `:tool-call-error` 钩子做选择。三个旧动作仍是 retry、skip、abort。扩展可以在自己的处理函数里再绑一个重启：

```lisp
(restart-case
    (read-source args)
  (use-cached-file ()
    :report "Read the last cached copy."
    (read-cache args)))
```

旗标开着时，这个名字出现在菜单里。选中之后 `invoke-restart` 在原来的动态环境下跑 `read-cache`。旗标关着时，没人调用它，工具结果仍是原来的错误结果。

print 和 rpc 拒绝这个旗标，进程起不来并写明原因。不在没人看的模式里把回合挂起。

### pi 里对应的做法和限制

工具抛错之后栈没了。`git show v1.4.0:packages/agent/src/agent-loop.ts` 第 855 到 863 行，`executePreparedToolCall` 的 `catch` 把异常收成 `isError: true` 的工具结果，然后回合继续。扩展若想补救，只能在结果已经产生之后改 `tool_result`。那个结果类型是闭合的，不能把一个还活着的栈帧重新跑进去。

provider 侧是 `git show v1.4.0:packages/ai/src/utils/retry.ts` 的 `retryAssistantCall`，第 205 到 233 行。可重试的错误按 `maxRetries` 退避，不可重试或预算用尽就把带 `stopReason: "error"` 的助手消息返回。分类在同文件第 266 行的 `isRetryableAssistantError`。这里没有「换模型」这个选择，也没有把选择交回给还包围着这次请求的动态环境。

TypeScript 可以在 `retryAssistantCall` 返回之后弹一个菜单，再手动再调用一次。那是回调，不是重启。它做不到两件 cadr 要的事。一是扩展在不修改 `turns.lisp` 的前提下，往菜单里加一个调用方事先不知道的动作。二是选中之后，原来的特殊变量、打开的输出和这次工具的参数绑定还在。pi 的钩子要加动作，就得改钩子的结果类型，而那个类型在 cadr 里已经被第 28 节冻住。

所以菜单本身不是 Lisp 才有的。开放的重启集合，加上选中后栈还在，才是。若实现退化成写死的三个字符串、扩展加不了动作，这个方向就不该做，因为那只是在 pi 的返回值后面补一个对话框。

### cadr 的设计

工具侧尽量不改 `tool-execution.lisp`。三个旧重启已经在 `call-tool-operation-with-restarts` 里。交互选择做成 CLI 在旗标打开时临时装上的 `:tool-call-error` 处理函数，返回值仍是 `:retry`、`:skip`、`:abort`。这是 `OQ-G10-D1` 已经允许的路径。

扩展自己的重启要多一个返回值，这是在改第 28 节冻住的语义，所以写在这里等裁决，而不是当成已批准的推论：

```lisp
(:invoke-restart "use-cached-file")
```

只在 `cadr-agent:*interactive-recovery*` 为真时，生命周期校验接受这个返回值，并 `invoke-restart`。变量为 nil 时，这个返回值和今天任何非法返回值一样被拒绝。默认测试看到的合法返回值仍是三个。

provider 侧不把逻辑写进 `turns.lisp`。新文件 `src/cadr-agent/loop/recovery.lisp`，`cadr-agent.asd` 的 `loop` 模块放在 `turns` 之前，这样 `turns` 可以调用它。`turns.lisp` 只加一次调用：

```lisp
(cadr-agent:call-with-provider-recovery
 agent
 (lambda ()
   ;; 现有的自动重试和最终消息
   ))
```

`*interactive-recovery*` 为 nil 时，这个函数就是 `funcall`，不建立重启，不读菜单。为真时，它在现有重试函数返回错误消息、消息还没当成最终结果提交之前，建立 `retry-now`、`switch-model`、`abort-turn`，并带上当时 `compute-restarts` 里扩展另绑的名字。`switch-model` 接收一个模型 id，在同一次动态环境下再进入现有的请求函数一次。不写新的退避实现。自动重试的次数和延迟仍由现在的函数算。

TUI 菜单放在 `src/cadr-cli/interactive/recovery-picker.lisp`，由 `cadr-cli.asd` 的 interactive 组件挂上。`commands.lisp` 不画这个菜单。旗标解析放在 `arguments.lisp` 旁边的新文件 `src/cadr-cli/recovery-flag.lisp`，避免把 `--slynk` 的解析函数再写长。旗标名 `--recover`。print 或 rpc 同时出现就信号 `configuration-error`。

不新增第 35 个扩展事件。不改 `:tool-call-error` 的载荷字段。那个载荷仍是 condition、tool-call、arguments、attempt、restart-names。

### 和对齐的关系

`*interactive-recovery*` 的默认值是 nil。nil 时：

- provider 路径调用的是现有重试函数，事件名和「预算用尽后的错误消息」与现在的测试一致。
- 工具路径不安装交互钩子。`compute-restarts` 在错误处理期间的名字集合与现在一致，就是那三个。
- 扩展若返回 `:invoke-restart`，校验失败的方式和今天返回未知动作一样。
- 帮助文本不含 `--recover`，处理方式和 `--slynk`、`--redef` 相同。

渲染差分的 core 档在旗标关闭时跑，碰不到这个菜单。菜单的文案由单独的 FiveAM 锁成字符串，不进官方 `render-diff.py gate --tier core`。

`switch-model` 多出来的那一次请求只发生在用户选了它之后。这是有意差异，而且只在旗标打开时出现。默认的请求次数不变。

### 安全风险和对策

菜单挂起的是一次回合。对策是只在 TUI 挂起，print 和 rpc 直接拒绝旗标，所以脚本和 RPC 客户端不会停在一个没有人看的提示上。打断键使用现有的中止，不新增「等 30 秒就自动选某个重启」。自动选择会让默认定时行为和 pi 分叉。

`switch-model` 只接受当前模型目录里已有的 id。不接受一段 Lisp，不接受 URL。选错 id 就报配置错误并回到菜单，不发请求。

扩展写在处理函数里的 `restart-case` 只在那次调用的动态范围内存在。权限和今天的工具处理函数相同。旗标关闭时交互钩子不安装，默认路径不 `invoke-restart`，所以即使用户按键也选不到它们。扩展若自己调用 `invoke-restart`，那是扩展的代码，和今天扩展直接调用函数没有区别。provider 路径在旗标关闭时连 `restart-case` 都不要加，见下一段。

不要在旗标关闭时往 provider 路径加 `restart-case`。政策第 6.6 节禁止为了「用上 Lisp」在可配对的失败路径上额外加重启。关闭时的路径必须是一次 `funcall`，FiveAM 可以用 `compute-restarts` 证明没有 `retry-now` 这些名字。

### 怎么测试

- 绑定 `*interactive-recovery*` 为 nil，跑现有的自动重试夹具。事件序列和最终错误消息与夹具一致。`compute-restarts` 不含 `retry-now`、`switch-model`、`abort-turn`。
- 绑定为真，用一个函数代替 TUI，让它选择 `abort-turn`。最终错误消息与 nil 时的预算用尽相同，且 provider 函数的调用次数不多出一次。
- 选择 `switch-model` 且 id 合法。provider 函数被再调用一次，这次看到的模型 id 是新的。
- 选择 `switch-model` 且 id 不在目录里。provider 函数不被再调用。
- 工具错误、旗标为 nil、扩展处理函数里有 `use-cached-file`。工具结果是错误结果，`use-cached-file` 的函数体没有跑。
- 旗标为真，钩子返回 `(:invoke-restart "use-cached-file")`。函数体跑了，而且是在 `restart-case` 建立的动态环境里跑的。可以用一个特殊变量在两侧设成不同的值来锁。
- 旗标为 nil 时，钩子返回 `(:invoke-restart "use-cached-file")` 被拒绝，工具结果仍是错误结果。
- `--recover` 加 `--mode rpc`，以及 `--recover` 加 `--print`，都在参数解析处失败，agent 循环不启动。
- 帮助文本测试仍然通过。

### 工作量

L。不依赖方向 1 和方向 2。`:invoke-restart` 这一返回值要单独点头，内建的 TUI 菜单和 provider 的三个重启可以先做，扩展的开放集合后做。若 `:invoke-restart` 被否决，剩下的菜单仍然值得做，但实现时要在提案的实现说明里写明它是闭合集合，避免以后有人把它说成「扩展也能加重启」。

## 方向 4：模型改 cadr 之前，先在隔离环境里编译和测试

### 用户得到什么

这不是把 REPL 交给模型。模型没有 `eval`，也连不上 Slynk。

用户这样启动：

```sh
cadr --self-extend
```

模型使用工具 `self-extend`，参数是两个路径：要加载的扩展源文件，以及要跑的测试文件。父进程起一个新的 SBCL，空 `HOME`，只把这两个文件复制进去。子进程编译并跑测试。失败时，父进程的工具列表不变，模型只看到编译器或测试的诊断。成功时，父进程 `load` fasl，工具出现在当前会话里。下一次失败不会卸掉上一次成功的版本。

没有旗标时，工具表里没有 `self-extend`。模型看不见它，`--tools` 的基线名字也不会多出一个 pi 没有的工具。

### pi 里对应的做法和限制

pi 没有这种工具。扩展是在 agent 进程里由 jiti 导入的，`loader.ts` 第 584 行的 `jiti.import` 发生在宿主进程。语法错误和顶层抛错都发生在正在跑的会话里。pi 可以另起一个 `node` 做检查，但那个检查不产生宿主下一步 `load` 的同一份编译产物。jiti 是在导入时编译进宿主的。

`OQ-G20-AGENT-EVAL-TOOL` 拒绝的是模型在活镜像里求值。那个否决还在。这里的差别是：模型只写文件，编译和测试在子进程，父进程只在成功之后 `load` fasl。活镜像里没有一段模型写的字符串被 `read` 然后 `eval`。

TypeScript 也能先起一个子进程，失败就不把产物交给宿主。拒绝写出文件不是 Lisp 才有的。Lisp 多出来的是这份 fasl 就是父进程这个 SBCL 的编译结果。`load` 要么接上，要么子进程在 `compile-file` 时已经失败。Node 的语法检查和 jiti 的导入不是同一份产物。加载单位是包。失败时 `delete-package` 已经在 `load-extension-source` 里，成功之后的回滚是不替换上一份 bundle。`reload-cli-extensions` 已经按路径保留上一份成功结果。方向 4 复用这个行为，不另写一套回滚。

这不是沙箱。模型今天就有 `bash`，`src/cadr-cli/tools/bash.lisp` 能跑用户能跑的命令。`--self-extend` 在工具表里没有 bash 时也是父进程里的代码执行。关掉 bash 不会让它变安全。`self-extend` 若被说成安全边界，就是错的。它只保证一份编译失败或测试失败的扩展不会装进这次会话。模型自己写的 FiveAM 可以是一条永远通过的断言。门禁证明的是声明的测试跑过了，而且编译成功了。它不证明扩展做了该做的事。

### cadr 的设计

分两片，以免模型工具和编译门绑死。

| 文件 | 系统 | 职责 |
|---|---|---|
| `src/cadr-cli/extensions/compile-gate.lisp` | `cadr-cli` | 起子进程，收集诊断，成功时把 fasl 路径交给调用方。方向 2 用这一片。 |
| `src/cadr-cli/tools/self-extend.lisp` | `cadr-cli` | 模型可见的工具。只在 `--self-extend` 时登记。 |

`cadr-cli.asd` 把 `compile-gate` 放在 extensions 模块、`loader` 之后，把 `self-extend` 放在 `tools` 模块。不要放进 `bootstrap/tools.lisp`。那个文件是内建工具的属主，pi 的 read、bash、edit、write 在那里。

子进程合同：

- 可执行文件用父进程的 `sb-ext:*runtime-pathname*`，不用 `PATH` 里先找到的 `sbcl`。父进程里的 `compile-file` 仍然会执行顶层形式，所以编译发生在子进程。
- `HOME` 指向空的临时目录。环境只保留区域设置。不继承 `PATH`，不继承父进程的 `CADR_*`，不继承 `OPENAI_API_KEY` 一类的变量。子进程不加载 Quicklisp。
- 工作目录是模式 `0700` 的临时目录，里面只有待编译的源和测试。扩展源里的 `asdf:load-system` 若指向允许名单以外的系统，直接失败。允许的系统只有子进程为了加载 `cadr-agent` 而需要的那一组，名单写在 `compile-gate.lisp` 里，测试锁这份名单。`ql:quickload` 在没有 Quicklisp 的子进程里不可用。`in-package` 进已经存在的包挡不住，和 `find-symbol` 是同一类洞。
- 读时拒绝 `#.` 和 `#,`，并且绑住 `*read-eval*` 为 nil。读到包的内部双冒号，且包不是这次扩展自己的包，就失败。这挡的是随手写的 `cadr-cli::`。挡不住 `(funcall (find-symbol ...))`，也挡不住文件前半段把读表改掉。真要挡住求值，就得把 CL 从 `:use` 里拿掉，扩展就写不成了。不走那条路。读入过滤是减速带，不是沙箱。
- 测试用 FiveAM，入口是子进程里一个固定的函数名，由测试文件提供。没有测试文件就拒绝加载，不接受「只编译不测试」。子进程墙钟超过 30 秒就杀掉，父进程不 `load`。30 秒是初值，改它要单独写进实现说明。
- 子进程退出码非零，父进程不 `load`。标准输出和错误输出作为工具结果还给模型，先过现有的崩溃日志脱敏。凭证形状的字符串打成已有的红acted 标记。

父进程装载复用 `load-extension-source` 的包和 `reload-cli-extensions` 的上一份成功结果。不写第二套包生命周期。

`--self-extend` 的解析与 `--recover` 一样放在新的旗标文件里，或者并进 `recovery-flag.lisp` 若那时已经存在。两个旗标互不隐含。它们都不出现在 `print-cli-usage` 里，`test/fixtures/cli-usage-plain.txt` 的字节不变。

### 和对齐的关系

旗标关闭时，工具登记函数不被调用。`--tools` 的默认集合、帮助文本、系统提示里的工具名单都不变。有测试锁「默认工具名列表等于基线」的，继续以那份列表为准，不把 `self-extend` 加进去再标记豁免。

旗标打开时，工具名单多一个名字。这是有意差异，只在旗标打开时出现，记在 `docs/parity-map.md` 的 `--slynk` 那一类下面。系统提示会因此多一段工具说明。实现那个提交要附上旗标关闭时系统提示的摘要仍与现有夹具一致，旗标打开时的提示不进 core 渲染差分。

方向 2 的 `/redef` 使用 `compile-gate`，但不登记 `self-extend`。所以可以先有编译门，而模型仍看不见工具。

### 安全风险和对策

最大的风险是把这件事理解成沙箱。对策写进工具的描述文本：它不限制模型。描述文本还要写明，工具表里没有 bash 时，这条工具仍然会在父进程里执行通过了门禁的代码。描述文本只在旗标打开时进入提示，避免默认提示变长。

第二是子进程继承凭证。白名单环境和空 `HOME` 挡的是继承进来的环境变量。挡不住同一个用户打开真实路径上的 `auth.json`，也挡不住读 `/proc/<父进程>/environ`。这道门不是凭证边界。同一个用户本来就可以用 bash 或调试器读这些。测试在父环境放一个金丝雀变量，断言子进程拿到的环境里没有它。不要在测试里放真的密钥。测试不声称子进程读不到父进程的文件。

第三是 fasl 被掉包。子进程把 fasl 写进这次调用创建的 `0700` 目录，父进程在同一次工具调用里、把控制权交回模型之前 `load`。先核对路径再 `load` 另一个路径，中间可以被换掉。同一个用户的其他进程仍然可以在核对和 `load` 之间换文件。这个洞和 bash 的权限一样，不在这里声称关掉。用完删除临时目录。

第四是模型通过扩展在父进程里拿到和 `bash` 相同的能力。这是真的，而且可以接受，因为旗标是用户显式打开的，和用户自己写一个扩展再 `/reload` 是同一权限。不允许的是模型连上 Slynk 或在父进程 `eval` 字符串。实现时不要给 `self-extend` 加一个「也在父进程求值」的参数。`OQ-G20-AGENT-EVAL-TOOL` 的重启条件仍然不满足，那条保持原判。

第五是扩展读父进程里已经打开的会话和凭证对象。包的 `:use` 不含 `cadr-cli` 和 `cadr-ai` 的内部。这和今天的扩展一样，挡不住故意写出的包前缀。不在这个方向里重开 `OQ-G20-EXTENSION-ISOLATION`。

### 怎么测试

- 父环境设置金丝雀变量。子进程打印环境。工具结果和子进程输出都不含金丝雀。临时 `HOME` 里没有父进程的 `auth.json`。
- 源文件含 `cadr-cli::` 内部符号。子进程失败，父进程的包列表和工具名单不变。
- 源文件含 `#.` 或 `#,`。子进程在读入时失败，父进程不 `load`。
- 子进程睡眠超过 30 秒。父进程不 `load`，工具名单不变。
- 测试 FiveAM 失败。父进程工具名单不变。上一次成功装入的工具仍返回旧值。
- 编译和测试都通过。新工具可以被调用。会话路径不变。
- 旗标关闭时，默认工具名列表与现有夹具一致，其中没有 `self-extend`。
- 子进程允许加载的系统名单与测试里的字面列表一致。名单变了测试就红。

FiveAM 锁不住「模型会不会写出恶意扩展」，也锁不住同一个用户去读 `auth.json` 或 `/proc/<父进程>/environ`。断言能证明的是失败不会装进父进程，继承的环境里没有金丝雀，以及墙钟超时不会 `load`。

### 工作量

编译门是 M，给方向 2 用。模型可见的工具是 XL，依赖方向 2 的装载和回滚。XL 的部分在 `:invoke-restart` 和 `--redef` 都稳定之前不动工。

## 顺序

先做不改默认字节的，再做要碰会话装载的，最后才把工具交给模型。

| 顺序 | 方向 | 工作量 | 为什么在这个位置 |
|---|---|---|---|
| 1 | 活镜像的快照函数，不新开端口 | S | `--slynk` 已经能重定义。快照只是把槽位收成稳定的 plist。后面的失败路径用它来看现场。 |
| 2 | 交互恢复，先做闭合的三个 provider 重启和已有的工具三动作 | L | 用户碰到的是限流和工具报错。工具重启已经在栈上，缺的是默认关闭的选择。不依赖热重载。 |
| 3 | 子进程编译门 | M | 方向 2 不能在父进程里把一份写坏的文件 `load` 到一半。 |
| 4 | `/redef` | L | 用编译门换函数槽，并且证明 `/reload` 的事件没变。 |
| 5 | `:invoke-restart`，若第 3 项的闭合菜单已获准 | L 里的后半 | 这是在改冻住的钩子返回值，单独点头。 |
| 6 | `self-extend` | XL | 依赖 3 和 4 的装载。`OQ-G20-AGENT-EVAL-TOOL` 不因此翻案。 |

方向 5 的宏 DSL 不在表里。

若快照函数被否决，顺序从交互恢复开始，现场查看继续用 `(cadr-cli:active-agent)`。若交互恢复被否决，热重载和 `self-extend` 仍然成立，它们不靠重启。若编译门被否决，`/redef` 和 `self-extend` 一起不做，因为父进程直接 `load` 就是今天的 `/reload`，没有新的 Lisp 能力。

## 要拍板的问题

1. 活镜像是否允许再监听一个端口，包括只绑回环的 TCP，或一个 Unix socket。建议否。`--slynk` 继续是唯一监听，继续只绑 `127.0.0.1`，继续没有 `CADR_*` 后门。不加端口的前提下，是否要 `agent-live-snapshot` 这一个函数。建议要。

2. `--recover` 是否只允许交互 TUI。建议是。和 `--print` 或 `--mode rpc` 同时出现就启动失败。不在 RPC 线上增加恢复事件。

3. 钩子是否可以多返回一个 `(:invoke-restart name)`。建议可以，但只在 `--recover` 打开时校验通过。这是在改 `docs/architecture.md` 第 28 节冻住的三个返回值，需要单独的一句裁决，不能从「已经有重启」推出来。

4. 是否允许模型在 `--self-extend` 打开时，把子进程编译并测试通过的 fasl 装进正在跑的镜像。建议允许。同时确认 `OQ-G20-AGENT-EVAL-TOOL` 仍然禁止模型在父进程求值，本提案不重启那条。

5. `/reload` 是否保持 pi 的 `session_shutdown` 加 `session_start`。建议保持。换函数槽只给 `/redef`，并且没有 `--redef` 时这个命令不存在。

6. 这些旗标的有意差异是否沿用 `--slynk` 的记法，而不是新的差异类别。建议沿用。实现那个提交再改 `docs/parity-map.md` 和 README，本文不改账本。
