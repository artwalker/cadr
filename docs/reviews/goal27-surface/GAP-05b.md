# GAP-05b 上游用例对应

范围是 v1.4.0（`4a080252`）`packages/codemode` 的每一个测试文件和每一个 `it` / `test` / `it.each` 案例，加上这一行点名的 coding-agent codemode 测试。断言对着 `git show v1.4.0:<path>`。cadr 在进程里跑同一份 quickjs-wasi，没有 Node/Bun worker 进程，也没有远程 sandbox。

## `packages/codemode/test/declarations.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `renders primitives, literals, and unions` | `codemode-declarations-match-v140` | 新增 |
| `renders objects on one line with sorted properties` | 同上 | 新增 |
| `puts property descriptions on comment lines` | 同上 | 新增 |
| `puts constraints the type cannot express on property comment lines` | 同上 | 新增 |
| `reads constraints of optional fields from the non-null branch` | 同上 | 新增 |
| `reads draft-04 boolean exclusive bounds` | 同上 | 新增 |
| `leaves out long tags and escapes line terminators` | 同上 | 新增 |
| `drops constraint tags before rendering a type over the budget as unknown` | 同上 | 新增 |
| `resolves local references and stops at recursive ones` | 同上 | 新增 |
| `renders arrays and tuples` | 同上 | 新增 |
| `renders types over the budget as unknown` | 同上 | 新增 |
| `renders signatures with normalized identifiers` | 同上 | 新增 |
| `renders output schemas shaped like an MCP CallToolResult as plain types` | 同上 | 新增 |
| `renders the per-tool sample` | 同上 | 新增 |
| `renders tools and globals` | 同上 | 新增 |
| `renders namespaced globals and explicit signatures` | 同上 | 新增 |
| `escapes comment terminators in descriptions` | 同上 | 新增 |

## `packages/codemode/test/source.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `returns plain code unchanged` | `codemode-source-options-match-upstream` | 新增 |
| `parses the options line and keeps line numbers` | 同上 | 新增。`max_output_tokens: 0` 与 `timeout_ms: 1500`、空 options 对象、以及原来的 2000/30000 |
| `only treats the first line as an options line` | 同上 | 新增。`// @optionsx` 和字符串里的 `@options` 都不当成选项 |
| `rejects an options line that is not the first line` | 同上 | 新增。四条输入的行号是 2、2、2、3 |
| `rejects empty input and invalid options` | 同上 | 新增。空输入、非法 JSON、数组、未知字段 `yield`、`max_output_tokens` 1.5、`timeout_ms` 0、选项行后面没有脚本 |

## `packages/codemode/test/deterministic.test.ts`

这些 `it` 驱动上游的确定性回放器：注入起始时间、种子，并按序号灌入结果。cadr 没有这个回放器。`execute()` 那一条自己写明真实时钟和真实随机，cadr 的 `execute-codemode` 用 `get-internal-real-time`，QuickJS 用 wasm 的随机。

| 用例 | FiveAM | 状态 |
|---|---|---|
| `makes the same calls and output for the same start, seed, and results` | 无 | 范围外：确定性回放器，不是 host `execute` |
| `runs in UTC whatever the host's timezone, and without WeakRef or FinalizationRegistry` | 无 | 范围外：回放器里的时钟和宿主全局 |
| `applies results in seq order, whatever order they are delivered in` | 无 | 范围外：回放器乱序投递 |
| `reports the fingerprint before any call and the calls issued after each result` | 无 | 范围外：回放器指纹 |
| `numbers calls to globals with tools, and answers errors as rejections` | 无 | 范围外：回放器的调用编号。脚本里工具失败变成 `error.message` 由 `codemode-quickjs-runs-the-upstream-contract` 锁 |
| `keeps the clock monotonic and rejects a clock value that is not finite` | 无 | 范围外：回放器注入的时钟 |
| `reports the result the VM was processing when the script ended` | 无 | 范围外：回放器的进行中结果 |
| `leaves a call waiting when its answer cannot be serialized` | 无 | 范围外：回放器拒绝不可序列化的答案 |
| `rejects with an Error carrying the answer's properties` | 无 | 范围外：回放器把答案属性挂到 Error 上 |
| `rejects rejection properties that are not an object, and tools sharing a script name` | 无 | 范围外：回放器的拒绝形状 |
| `uses the script names the run passes` | 无 | 范围外：回放器改脚本里的工具名 |
| `ends with an error the script cannot catch when the caller aborts` | 无 | 范围外：回放器的中止。脚本超时由 QuickJS 合约锁 |
| `is finished once it has its outcome` | 无 | 范围外：回放器结束后不再接受结果 |
| `rejects a call that is not waiting and a result number used twice` | 无 | 范围外：回放器的序号校验 |
| `applies results in seq order when the transport reorders replies sent in order` | 无 | 范围外：远程传输把答复重排 |
| `reads the real clock and real randomness` | 无同名锁 | 范围外：上游只证明 `execute()` 不走回放器。cadr 没有回放入口 |

## `packages/codemode/test/portable.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `fails a script that computes past its interrupt budget as a timeout` | `codemode-quickjs-runs-the-upstream-contract` 的 `timeout_ms: 500` 空转 | 已覆盖同步空转超时。预算数字是脚本选项，不是另一套 interrupt budget API |
| `counts the budget across waits on tools` | 无 | 范围外：这条量的是工具等待也计入 interrupt budget。cadr 的超时从脚本开始算墙上时间，不单列工具等待预算 |
| `runs tools in the caller and the script on the remote` | 无 | 范围外：没有远程 sandbox |
| `batches output instead of making one exchange per line` | 无 | 范围外：远程传输合批 |
| `caps the interrupt budget and memory at the remote's limits` | 无 | 范围外：远程上限 |
| `tells the remote to stop when the caller aborts` | 无 | 范围外：远程中止 |
| `reports a failing or vanishing remote as a sandbox error` | 无 | 范围外：远程进程消失 |

## `packages/codemode/test/sandbox.test.ts`

进程内 QuickJS 能观察到的行为用现有合约锁。prelude 和 wasm 内部的隔离、以及 Node worker 通道，不在 host Lisp 里重写。

| 用例 | FiveAM | 状态 |
|---|---|---|
| `parse as JavaScript` | 无 | 范围外：嵌入的 prelude / worker 源码能被 TypeScript 解析。cadr 的 prelude 是 `src/cadr-cli/extensions/codemode-prelude.js`，不经过 tsc |
| `returns the script's return value after a JSON round trip` | `codemode-quickjs-runs-the-upstream-contract` 的 `return 1 + 1` | 已覆盖返回值。没有另锁一次完整 JSON 往返样本 |
| `supports top-level await` | 同上，`await tools.echo` | 已覆盖 |
| `collects text(), image(), and console output in order` | 同上的 `image()` 保存路径 | 已覆盖 `image()` 的保存标签。`text()` / `console` 的顺序标记没有单独的样本 |
| `rejects invalid text() and image() arguments` | 无 | 范围外：prelude 对参数形状的拒绝，不在这次 host 返修的探针里 |
| `accepts wrapped and large base64 image data` | 无 | 范围外：prelude 对折行 base64 的接受 |
| `ends the script successfully on exit(), keeping output and store writes` | 无 | 范围外：`exit()` 的提前成功结束 |
| `keeps output produced before a failure` | 无 | 范围外：失败前的部分输出 |
| `reports syntax errors with the script's line number` | 无 | 范围外：QuickJS 语法错误的行号格式 |
| `reports thrown errors with the script's line number` | 无 | 范围外：抛错栈的行号 |
| `formats stacks like V8 without prelude frames` | 无 | 范围外：栈帧格式 |
| `reports non-Error throws` | 无 | 范围外：抛出非 Error 的文本 |
| `reports a non-serializable return value as a script error` | 无 | 范围外：返回值不能 JSON 化 |
| `exposes tools as async functions and records calls` | QuickJS 合约记录 `calls`，并锁 `models.classify` 的 `test/c` | 已覆盖调用记录。普通工具的参数回放没有按这条的样本重锁 |
| `runs concurrent calls and lists tool names` | 无 | 范围外：并发工具名列表 |
| `exposes tools under normalized identifiers and lists them in ALL_TOOLS` | `codemode-identifiers-replace-non-js-characters` | 已覆盖标识符。`ALL_TOOLS` 列表没有进 QuickJS 合约 |
| `passes undefined arguments and results through` | 无 | 范围外：`undefined` 往返 |
| `turns tool errors into catchable Errors in the script` | QuickJS 合约：无文本是 `Tool "nope" failed`，有文本是 `disk full`，不是 `Tool "bash" failed` 再换行 | 新增 |
| `rejects calls to unknown tools` | 无 | 范围外：未知工具名 |
| `aborts unawaited calls when the script returns` | 无 | 范围外：脚本返回时取消未 await 的调用 |
| `names close matches when a script reads a tool that does not exist` | 无 | 范围外：prelude 的相近名字提示 |
| `supports register and unregister between executions` | 无 | 范围外：sandbox 对象上的 register/unregister。cadr 每次执行用当次工具表 |
| `reads the snapshot and reports writes` | QuickJS 合约的 `store` / `load` | 已覆盖同一次脚本里的 store/load |
| `returns copies, so mutating a loaded value does not change the store` | 无 | 范围外：load 返回副本 |
| `rejects invalid keys, values, and oversized writes inside the script` | 无 | 范围外：store 的键和体积限制 |
| `explains oversized writes` | 无 | 范围外：超限说明 |
| `reserves the store and load names` | 无 | 范围外：这两个名字不能当工具 |
| `exposes globals as top-level functions without recording them as calls` | 无 | 范围外：自定义 global 不进 calls。`models.*` 会进调用行，由分类测试锁 |
| `groups namespaced globals and spreads arguments on request` | QuickJS 合约调用 `models.classify({provider,id}, context)` | 已覆盖 `models.*` 的展开参数 |
| `names the members of a namespace when a script reads one that does not exist` | 无 | 范围外：prelude 的成员提示 |
| `rejects invalid and reserved global names` | 无 | 范围外：sandbox 构造时拒绝非法 global 名 |
| `terminates a synchronous infinite loop on timeout` | QuickJS 合约 `while (true) {}` 加 `timeout_ms: 500` | 已覆盖 |
| `runs without a deadline when timeoutMs is Infinity` | 无 | 范围外：`Infinity` 期限。cadr 选项只接受到 2147483647 的正整数 |
| `fails a script that waits on a promise nothing can settle` | 无 | 范围外：永远等不到的 Promise |
| `terminates a microtask-spinning loop on timeout` | 无 | 范围外：`while (true) await null` |
| `aborts via signal and cancels in-flight calls` | 无同名样本 | 范围外：AbortSignal 取消正在跑的工具。等待 worker 名额时的中止由 `codemode-worker-wait-is-arrival-order-and-does-not-start` 锁 |
| `fails a script whose output passes the limits, even if it catches the error` | `codemode-models-discovery-images-and-schema-match-v140` 的 `codemode-truncate` | 已覆盖按 token 截断并写出溢出文件。没有锁「抓住错误后继续打印仍失败」 |
| `rejects execute after close` | 无 | 范围外：sandbox.close() 之后再 execute |
| `runs executions in parallel without sharing state` | 无 | 范围外：同一 sandbox 上并行 execute |
| `turns deep recursion into a catchable RangeError` | 无 | 范围外：QuickJS 栈深度 |
| `has no host globals` | 无 | 范围外：prelude 去掉 process/require/fetch |
| `keeps eval and Function inside the VM` | 无 | 范围外：eval 仍在 wasm 里 |
| `rejects dynamic import` | 无 | 范围外：动态 import |
| `ignores patches to built-ins and built-in globals` | 无 | 范围外：改 Array.prototype 不影响 host |
| `freezes intrinsics that are only reachable from instances` | 无 | 范围外：冻结生成器等原型 |
| `still lets instances override properties of frozen prototypes` | 无 | 范围外：实例仍可覆盖 |
| `reports errors whose name or message is not a string` | 无 | 范围外：message 不是字符串时的报告 |
| `keeps tools and console frozen` | 无 | 范围外：tools 对象被冻结 |
| `accepts a worker path string` | 无 | 范围外：Node worker 文件路径 |
| `reports a missing worker file as a sandbox error` | 无 | 范围外：缺少 worker 文件 |
| `reports a failing wasm module as a sandbox error` | 无 | 范围外：worker 加载 wasm 失败。进程内加载失败走 `execute-codemode` 的 sandbox 错误句，没有这条 worker URL |
| `ignores Node --watch notifications from the worker` | 无 | 范围外：Node `--watch` 消息 |
| `reports a broken bridge`: `store writes are not an array` | 无 | 范围外：worker 通道注入坏消息。进程内 VM 不走这条桥 |
| `reports a broken bridge`: `store writes contain a malformed entry` | 无 | 范围外：同上 |
| `reports a broken bridge`: `store value for "k" is not valid JSON` | 无 | 范围外：同上 |
| `reports a broken bridge`: `return value is not valid JSON` | 无 | 范围外：同上 |
| `reports a broken bridge`: `script error is not an object` | 无 | 范围外：同上 |
| `reports a broken bridge`: `script error is malformed` | 无 | 范围外：同上 |
| `reports a broken bridge`: `unknown message from the worker` | 无 | 范围外：同上 |

## `packages/codemode/test/worker-lifetime.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `does not start a worker when admission is denied` | `codemode-worker-wait-is-arrival-order-and-does-not-start` | 已覆盖。名额满时后来的脚本排队，不开始 |
| `releases admission when worker construction fails` | 无 | 范围外：Node Worker 构造函数抛错 |
| `does not acquire admission when wasm loading fails` | 无 | 范围外：worker 在拿到名额前 wasm 失败 |
| `settles abort without waiting for worker exit` | 无 | 范围外：等 worker 进程退出 |
| `settles timeout without waiting for worker exit` | 无 | 范围外：同上 |
| `settles close without waiting for worker exit` | 无 | 范围外：同上 |
| `reports the actual exit of execute() and start() workers` | 无 | 范围外：worker 进程退出码 |
| `requests termination when onWorkerStarted throws` | 无 | 范围外：`onWorkerStarted` 回调 |
| Node `exits promptly after abort with a real worker` | 无 | 范围外：Node 子进程 |
| Node `exits promptly after timeout with a real worker` | 无 | 范围外：Node 子进程 |
| Node `exits promptly after close with a real worker` | 无 | 范围外：Node 子进程 |
| Bun `settles abort promptly with a real worker` | 无 | 范围外：Bun 子进程 |
| Bun `settles timeout promptly with a real worker` | 无 | 范围外：Bun 子进程 |
| Bun `settles close promptly with a real worker` | 无 | 范围外：Bun 子进程 |

## coding-agent

`packages/coding-agent/test/codemode-worker-config.test.ts` 的三条都是 Node/Bun 模块路径。

| 用例 | FiveAM | 状态 |
|---|---|---|
| `uses a relative source entrypoint in Bun binaries` | 无 | 范围外：Bun 可执行文件里的 worker 路径 |
| `uses the emitted worker beside the bundled Node module` | 无 | 范围外：打包后的 worker 文件 |
| `uses the pi-codemode worker when unbundled` | 无 | 范围外：未打包时的 `pi-codemode` worker |

`packages/coding-agent/test/codemode-worker-admission.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `bounds surviving workers after timeout` | `codemode-worker-cap-defaults-to-two-and-reads-cadr-env` | 已覆盖默认 2 和 `CADR_CODEMODE_MAX_WORKERS`。没有另测超时后存活 worker 数 |
| `bounds surviving workers after abort` | 同上 | 已覆盖名额。没有另测中止后的存活数 |
| `bounds surviving workers after success` | 同上 | 已覆盖名额 |
| `starts no worker for a launch that resumes after its result timed out` | `codemode-worker-wait-is-arrival-order-and-does-not-start` | 已覆盖排队期间不算开始 |
| `queues a concurrent burst behind two workers` | 同上 | 已覆盖 |
| `reads the limit from PI_CODEMODE_MAX_WORKERS` | `codemode-worker-cap-defaults-to-two-and-reads-cadr-env` | 已覆盖对应的 `CADR_CODEMODE_MAX_WORKERS`。不读 `PI_*` |
| `ignores an invalid PI_CODEMODE_MAX_WORKERS` | 同上 | 已覆盖非法值回到 2 |

`packages/coding-agent/test/codemode-renderer.test.ts` 是 ink 渲染。cadr 把脚本结果打成文本，没有这块组件。

| 用例 | FiveAM | 状态 |
|---|---|---|
| `hides the script header and shows the output` | 无 | 范围外：ink 渲染 |
| `shows the cost of model calls and their total` | 无 | 范围外：ink 把 cost 画出来。调用行上的 cost 由 `codemode-classify-usage-and-per-script-limiter-match-v140` 和 QuickJS 合约锁 |
| `shows results without a header, such as rejected options` | 无 | 范围外：ink 渲染 |
| `limits collapsed output to wrapped lines, not logical lines` | 无 | 范围外：ink 折行 |
| `shows the elapsed time while the script runs and the total once it finished` | QuickJS 合约要求输出里有 `Script completed` 或 `Script failed` | 已覆盖结束句。没有锁运行中的计时 |

`packages/coding-agent/test/suite/agent-session-codemode.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `presents callable tools per codemode.mode` | `codemode-settings-mode-and-inline-budget` | 已覆盖 mode 和预算设置。没有整段会话里按 mode 过滤工具的样本 |
| `shows the guidelines of tools that do not fit the inline budget through describeTool()` | `codemode-description-lists-within-budget-and-skips-deferred` | 已覆盖超预算的工具不进描述 |
| `runs nested calls in parallel and returns only the script result` | QuickJS 合约只返回脚本输出 | 已覆盖结果是脚本输出。没有锁嵌套调用并行 |
| `routes nested calls through extension hooks` | 无 | 范围外：扩展 `tool_call` 钩子。那是别的行的会话循环 |
| `adds the usage of nested results to the codemode result` | `codemode-classify-usage-and-per-script-limiter-match-v140` 里 6 路 `Promise.all` 的脚本结果 `input` 1800、`cost.total` 0.006；QuickJS 合约的单次 usage 第五返回值 `input` 300、`cost.total` 0.001 | 新增。锁的是模型调用的 usage，不是普通工具结果上的 usage |
| `keeps structured content that tool_result handlers replace along with the content` | QuickJS 合约：带 schema 的失败仍返回 `{code:full}`，无 schema 的成功只返回文本 | 已覆盖 schema 决定交回的值。没有锁扩展替换 tool_result |
| `attaches only the images the script passes to image()` | QuickJS 合约的 `image()` | 已覆盖 |
| `marks where each text item starts and puts console lines last in one text block` | 无 | 范围外：`==> text N/M <==` 和 `<console_output>` 的样本没有进这次的合约 |
| `reports script failures as results that keep partial output and the calls that ran` | QuickJS 合约的超时是 is-error 结果 | 已覆盖失败仍是工具结果。没有锁失败前的部分输出 |
| `applies the timeout_ms option and rejects invalid options` | `codemode-source-options-match-upstream` 和 QuickJS 超时 | 新增 / 已覆盖 |
| `limits script memory so runaway allocations fail inside the script` | QuickJS 合约 `InternalError: out of memory` | 已覆盖 |
| `truncates output to the token budget and spills the full text` | `codemode-truncate` 断言溢出文件名含 `pi-codemode` | 已覆盖 |
| `formats output at the item limit in linear time` | 无 | 范围外：条目上限的耗时 |
| `resolves bash calls to structured results, also for non-zero exit codes` | 无 | 范围外：内置 bash 的结构化结果。这次锁的是无 schema 时失败文本就是工具文本 |
| `resolves read calls to text for text files and to image blocks that image() shows` | 无 | 范围外：内置 read |
| `persists store() writes as custom entries for later calls` | QuickJS 合约只在同一次脚本里 store/load | 已覆盖同一次。没有锁跨调用的会话条目 |
| `appends nothing for failed scripts or scripts without writes` | 无 | 范围外：失败脚本不追加 store 条目 |
| `runs without a session, starting from an empty store` | QuickJS 合约在没有 context 时 store/load | 已覆盖 |
| `loads the values written on the current branch` | 无 | 范围外：会话分支上的 store |
| `folds store entries from the root, ignoring malformed data` | 无 | 范围外：从根折叠 store |
| `declares models only for the session's own codemode tool` | 无 | 范围外：覆盖 codemode 工具后的描述不再提到 models |
| `lists models and classifies with catalog auth, ignoring script-supplied fields` | `codemode-models-discovery-images-and-schema-match-v140` 锁 `jev-latest` 的 `type`、`cost`、`compat` 和没有 `headers`；`codemode-classify-usage-and-per-script-limiter-match-v140` 经 `execute-codemode` 跑 6 路 `Promise.all` 的 `models.classify`，锁最多 4 个在飞、调用行 `scorer/judge`、`ok`、`0.001`，以及脚本结果 `input` 1800、`cost.total` 0.006；QuickJS 合约锁 `test/c` 和 `cost=0.001` | 新增 |
| `generates images with catalog auth and attaches them through image()` | QuickJS 合约的 `generateImages` 未展示图片时的 Note | 已覆盖未展示图片的提示。目录鉴权忽略脚本里的 baseUrl 没有另锁 |
| `notes generated images that the script did not show` | 同上 | 已覆盖 |
| `reports provider errors as results and invalid arguments as exceptions` | `codemode-models-discovery-images-and-schema-match-v140` 锁未知模型、错误类型和缺 `state` / `input` 的异常文本 | 已覆盖 |
