# GAP-48 上游用例对应

范围是 v1.4.0 的工具批次调度和共享 `toolChoice`（`auto` / `none`）。源码：`packages/agent/src/agent-loop.ts` 的 `executeToolCalls`、`executeToolCallsSequential`、`executeToolCallsParallel`，`packages/agent/README.md` 的 `toolExecution` / `executionMode`，`packages/coding-agent/src/core/extensions/runner.ts` 的 `emitToolCall`，`packages/coding-agent/src/core/nested-tool-calls.ts` 的 `isSequential`，`packages/ai/src/types.ts` 的 `ToolChoice`。断言对着 `git show v1.4.0:<path>`。

与 GAP-20（`d08ed0931`）的关系：`prepareToolCall` 仍是未知工具和参数校验在 `beforeToolCall` 之前；钩子抛错收成 is-error，不跑执行体，也不跑 `tool_result`。`emitToolCall` 只在返回值的 `block` 为真时拦住。列表没有 `block`，不是拦住。cadr 把非 `extension-hook-result` 的返回值当成错误抛出时，GAP-20 的拦住路径会误伤这个列表。`:tool-call-before` 上忽略这种返回值，其它事件仍报错。

## 源码和 README（没有单独的 `it`）

| 行为 | FiveAM | 状态 |
|---|---|---|
| 全局 `toolExecution: "sequential"` 让整批逐个调用跑完再开始下一个 | `sequential-batch-finishes-each-call-before-the-next` 的第三组（两个未写 mode 的工具，agent `tool-execution` 为 `:sequential`） | 新增 |
| 缺省是 `parallel`。一个 `executionMode: "sequential"` 的工具（含同一工具连调两次）让整批改走顺序 | `one-sequential-tool-forces-the-whole-batch-sequential`、`sequential-tool-called-twice-stays-sequential-under-the-default`、`sequential-tool-holds-every-other-call-in-the-batch` | 已覆盖 |
| 顺序：每个调用 `tool_execution_start`、prepare（含 before）、执行、`tool_execution_end`、立刻该条工具结果，然后才是下一个。中止后不再开始后面的调用 | `sequential-batch-finishes-each-call-before-the-next`、`sequential-batch-stops-after-the-current-result-when-aborted` | 新增 |
| 并行：逐个 preflight（start，然后 prepare；立刻结束的调用在下一个 start 之前发出 `tool_execution_end`）。执行体并发。`tool_execution_end` 按完成先后，工具结果按助手原文顺序 | `parallel-preflight-prepares-one-call-before-the-next-start`、`omitted-execution-mode-runs-the-batch-in-parallel` | 新增 / 已覆盖 |
| `beforeToolCall` 返回没有 `block` 的值（测试里是 `push` 得到的列表）不拦住，执行体仍跑 | `sequential-batch-finishes-each-call-before-the-next` | 新增 |
| 嵌套 `executeTool`：agent 的 `toolExecution === "sequential"` 或该工具 `executionMode === "sequential"` 时，三条并发里同时进入执行体的最多一条；都不是 sequential 时三条重叠 | `global-tool-execution-serializes-nested-calls` | 新增 |
| `ToolChoice` 是 `"auto"` 或 `"none"`。各 API 的写入见状态格 | `shared-tool-choice-auto-and-none-reach-every-api`、`google-strict-tool-turns-auto-into-validated-and-keeps-none` | 已覆盖 |

## `packages/agent/test/agent-loop.test.ts`

| 行 | 用例 | FiveAM | 状态 |
|---|---|---|---|
| 668 | `should emit tool_execution_end in completion order but persist tool results in source order` | `omitted-execution-mode-runs-the-batch-in-parallel` | 已覆盖 |
| 867 | `should force sequential execution when a tool has executionMode=sequential even with default parallel config` | `sequential-tool-called-twice-stays-sequential-under-the-default`、`sequential-batch-finishes-each-call-before-the-next` | 已覆盖 / 新增 |
| 949 | `should force sequential execution when one of multiple tools has executionMode=sequential` | `one-sequential-tool-forces-the-whole-batch-sequential`、`sequential-tool-holds-every-other-call-in-the-batch` | 已覆盖 |
| 1035 | `should allow parallel execution when all tools have executionMode=parallel` | `omitted-execution-mode-runs-the-batch-in-parallel` | 已覆盖 |
| 2167 | `validates, runs the hooks, and reports failures as error outcomes` | `goal27-tool-call-handler-error-blocks-execution` | 已覆盖。GAP-20。这次只确认抛错仍拦住 |
| 2214 | `lets afterToolCall replace structured content and drops it when only content is replaced` | `goal27-tool-call-mutation-skips-revalidation`、`goal27-tool-call-alias-rewrites-executed-arguments` | 已覆盖。GAP-20。这次没有改 after 替换 |
| 528 | `should execute mutated beforeToolCall args without revalidation` | 同上 | 已覆盖。GAP-20 |

其余 `it` 不测批次顺序或 `toolChoice`，范围外：`uses the configured default when a legacy caller omits streamFn`、`should emit events with AgentMessage types`、`should build provider context exclusively from transcript messages`、`should handle custom message types via convertToLlm`、`should apply transformContext before convertToLlm`、`should handle tool calls and results`、`records how long execute() took on the tool result, excluding hooks`、`should not execute tool calls from a length-truncated assistant message`、`should prepare tool arguments for validation`、`should inject queued messages after all tool calls complete`、`runs finishTurn after tool-result messages and before turn_end`、`action:end skips queue polling and next-turn preparation`、`makes exactly one context-only request when no natural request satisfies continuation`、`lets a natural tool-result request satisfy continuation`、`prepares the initial request after pending messages and can replace request state`、`does not poll steering after prepareRequest`、`should use prepareNextTurn snapshot before continuing`、`picks up steering queued during prepareNextTurn before the next request`、`action:end receives finalized turn context and stops before queue polling`、`should stop after a tool batch when every tool result sets terminate=true`、`should stop after a blocked tool call when beforeToolCall sets terminate=true`、`should continue after a mixed batch with one terminating blocked call`、`should continue after parallel tool calls when not all tool results terminate`、`should allow afterToolCall to mark a tool batch as terminating`、`should throw when context has no messages`、`should continue from existing context without emitting user message events`、`should allow custom message types as last message (caller responsibility)`。

## `packages/coding-agent/test/nested-tool-calls.test.ts`

| 行 | 用例 | FiveAM | 状态 |
|---|---|---|---|
| 164 | `serializes concurrent calls to sequential tools` | `global-tool-execution-serializes-nested-calls` | 新增。三条并发，sequential 时同时进入执行体的是 1，parallel 时是 3 |

范围外：`assigns ids below the caller, emits events with the parent id, and records the calls`、`records calls of nested tools on the model-issued call`、`sums the usage of nested results at every depth`、`omits oversized arguments and drops calls beyond the limit`、`caps the total argument size and marks unfinished calls incomplete`。编号、用量和参数上限不是这一行的调度锁。

## `packages/agent/test/e2e.test.ts`

全部范围外。`executes tools and tracks pending tool calls` 只确认工具跑完并清掉 pending，不锁批次顺序。其余：`handles a basic text prompt`、`handles abort during streaming`、`emits lifecycle updates while streaming`、`maintains context across multiple turns`、`preserves thinking content blocks`、`throws when no messages in context`、`throws when last message is assistant`、`continues and gets a response when last message is user`、`continues and processes tool results`。

## toolChoice

| 文件 | 用例 | FiveAM | 状态 |
|---|---|---|---|
| `packages/ai/test/openai-completions-tool-choice.test.ts` | `forwards toolChoice from simple options to payload` | `shared-tool-choice-auto-and-none-reach-every-api` 锁 `auto` 与 `none` 原文字符串。该 `it` 的取值是 `required`，同一转发路径 | 已覆盖 `auto`/`none`。`required` 不在这一行 |
| 同上 | `includes toolChoice when no tools are provided` | 同上，Completions 没有工具也带 `tool_choice` | 已覆盖 |
| `packages/ai/test/azure-openai-tool-choice.test.ts` | `forwards provider-specific tool choice while preserving tool definitions` | 范围外：取值是 `required`，测的是工具定义还在 | 范围外 |
| 同上 | `forwards provider-neutral tool choice from simple options` | `shared-tool-choice-auto-and-none-reach-every-api` 锁 Azure 的 `none` | 已覆盖 `none`。该 `it` 没有单独断言 `auto` |
| `packages/ai/test/openai-responses-compat.test.ts` | `forwards required tool choice` | 同上，Responses 保留原文字符串 | 已覆盖 `auto`/`none`。该 `it` 的取值是 `required` |
| `packages/ai/test/openai-codex-stream.test.ts` | `forwards required tool choice` | 同上，Codex 缺省 `auto`，显式 `none` 盖过它 | 已覆盖。该 `it` 的取值是 `required` |
| `packages/ai/test/pi-messages.test.ts` | `streams text and tool calls and resolves the terminal message` | 同上，`options.toolChoice` 为 `auto` | 已覆盖。该 `it` 的其余断言是流本身 |
| `packages/ai/test/mistral-http-transport.test.ts` | `serializes SDK-style payloads to the Mistral wire format` | 同上，Mistral 保留原文字符串 | 已覆盖 `auto`/`none`。该 `it` 的取值是 `{type:function}` |
| `packages/ai/test/google-shared-convert-tools.test.ts` | `uses validated function calling for strict tools on Gemini 3` | `google-strict-tool-turns-auto-into-validated-and-keeps-none` | 已覆盖 |

`openai-completions-tool-choice.test.ts` 里其余 `it`（strict、reasoning、tool_stream、finish_reason、流增量、OpenRouter、Kimi、DeepSeek、z.ai、Ant Ling、usage）不写 `toolChoice`，范围外。`azure-openai-tool-choice.test.ts` 只有上面两条。`openai-responses-compat.test.ts`、`openai-codex-stream.test.ts`、`pi-messages.test.ts`、`mistral-http-transport.test.ts`、`google-shared-convert-tools.test.ts` 里其余 `it` 是传输、缓存、推理或 schema 剥离，范围外。
