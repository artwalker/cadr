# GAP-43b 上游用例对应

范围是 v1.4.0 `packages/durable/src/harness/telemetry.ts`、`harness.ts`、`submissions.ts`，以及 durable 遥测测试里 cadr 的 checkpoint harness 能观察到的行为。断言对着 `git show v1.4.0:packages/durable/test/harness-telemetry.test.ts`、`harness-telemetry-options.test.ts` 和同 tag 的 `scheduler.ts` `#phase` / `#step`、`submissions.ts` `submit` / `admitSubmission`。

FiveAM 在 `test/cadr-core/durable-test.lisp`。cadr 的 harness 同步跑完一次提交，没有 GenerationTask、CompactionTask、inbox 跟进或 steer。

## `packages/durable/test/harness-telemetry.test.ts`

| 上游 `it` | FiveAM | 状态 |
|---|---|---|
| `records content-free submit and phase spans, nested parents, checkpoints, entry events, and metrics` | `durable-submit-emits-a-root-span-and-keeps-content-out`：根 span，`result` `placed`，事件是用户 `pi.user`、助手 `pi.assistant`、`pi.durable.submission`（`status` `done`，带 `answer.entry_id`），link 的 context 是 caller；重复 request 的 span 没有事件，记录上的 trace 仍是第一次的 span context。拒绝只把 status 设成 error，error message 是空。`private-input`、`visible-answer`、`nested-private` 不出现在 span 里。phase 的 `next=finish`、一次 `pi.durable.checkpoint`、`task_faulted`、时钟只报告一次、`pi.durable.tasks.active` 在 close 后合计为 0，由 `durable-phase-report-clock-and-replay-follow-the-v140-vocabulary` 锁住 | 新增可观察的提交和 phase 部分。`pi.ai.request` 的 parent、`tool.name` 的 outer/inner、`waiting` 范围外：要 GenerationTask 和 faux 模型 |
| `returns admission results without re-reading records or probing root link targets` | `durable-busy-input-results-are-placed-then-queued`：三次 `result` 是 `placed`、`queued`、`queued`。后两次没有事件。`queued` 的 trace 等于第二条 span 的 context，不等于第三条 | 新增。上游还 spy 了 `storage.submission` 以及不对根 telemetry `inject`、不对 `undefined` `extract`。cadr 的内存存储没有这些探针；重复 requestId 在命中已有记录时返回，不再 `inject` |
| `inherits omitted or undefined task traces and stores no carrier for an explicit root` | `durable-phase-inherits-the-creator-and-drops-an-explicit-root`：省略和 `:trace nil` 的 trace 与 phase parent 都是 creator；`:trace "root"` 的 trace 是 nil，parent-id 和 parent-context 都是 nil | 新增 |
| `records checkpoints only when the running phase changes` | `durable-phase-report-clock-and-replay-follow-the-v140-vocabulary` 对 call、call、finish 只发 `finish`。`durable-checkpoint-fires-again-after-leaving-and-returning` 对 call、other、call 发 `other` 然后 `call` | 新增 |
| `starts each queued input's run in its admission trace and links input roots to their caller` | `durable-submit-emits-a-root-span-and-keeps-content-out` 锁住 input 根 span 和 caller link | 部分。排队之后各自的 prepare phase 以该次 submit 的 context 为 parent，范围外：cadr 不启动 generation |
| `links the other queued inputs to the first invocation of their shared run` | 无 | 范围外：`followUpMode` `all` 和共享 `pi.generation` 的 links |
| `links a steer admission to the current run without moving its work into the steer's trace` | 无 | 范围外：`whenBusy` `steer` 要当前 generation 的 trace。cadr 的忙对话只拒绝或排队 |
| `keeps a public write admission open through commit as a child of its caller` | `durable-public-write-stays-open-as-a-child-of-its-caller`：parent 是 caller，links 为空，`result` `done`，`submission.type` `write`，事件是 `pi.durable.entry`（`app.note`）然后 `pi.durable.submission`（`status` `done`，没有 `answer.entry_id`），trace 等于该 span。`private-note` 不在 span 里 | 新增。内存存储没有 `holdCommits`，测不到提交途中 `settled` 为 false 且 events 为空；提交发生在 span 回调里，返回时事件已经在这个 span 上 |
| `links an input submitted inside a turn to the calling phase without parenting it` | 无 | 范围外：工具执行里再提交子对话，要 delegate 工具和子 generation |
| `parents background compaction to the prepare phase that creates it` | 无 | 范围外：CompactionTask 和 `backgroundTokens` |
| `marks only the first invocation after reopen resumed, retaining its stored parent` | `durable-loaded-task-is-resumed-once-and-commits-emit-after-success` 锁住第一次 `resumed` 为真、`attempt` 为 3。`durable-reopened-phase-keeps-the-stored-parent`：JSONL 关掉再打开后，下一次 phase 的 `resumed` 为真，parent-context 和任务 trace 都等于关闭前 creator 的 inject 结果 | 新增 parent 与 resumed。上游那三次 phase 是 abort 打断 hold 再完成（`resumed` false、true、false，且三次 parent 都是关闭前的 trace，`tasks.active` 是 1、-1、1、-1）。cadr 的 phase 没有 abort signal 上的挂起，不跑这三次 |
| `emits entry and settlement events only after successful storage commits` | `durable-loaded-task-is-resumed-once-and-commits-emit-after-success`：回滚的 session commit 不发事件；成功的 `storage-commit` 发 `pi.durable.entry` 然后 `pi.durable.submission`。`durable-submit-emits-a-root-span-and-keeps-content-out` 的拒绝路径没有 `submission.id` | 新增。上游用 `holdCommits` 看提交前事件为空；cadr 在 `storage-commit` 成功返回后才 `note-durable-commit` |
| `records internal compaction admissions as phase events without a submit span` | 无 | 范围外：内部 compaction 提交 |
| `records a fixed faulted category and a bounded diagnostic` | `durable-failed-and-orphaned-outcomes-collapse-to-faulted` | 新增。`faulted`、`failed`、`orphaned` 的记录状态名不变，span 的 `outcome` 都是 `faulted`，error name 分别是 `task_faulted`、`task_failed`、`task_orphaned`，message 是 500 个字符且以 `diagnostic` 开头。attributes 和 events 里没有 `diagnostic`。span 里没有 `private-error-detail` 和 `private-exception-name`。抛错那条的 `pi.durable.report` 是 `task_faulted` / `threw`。未知 carrier 的 parent-id 是 nil。上游这条还带 extension `task:test.fault`；cadr 的 `define-task` 没有安装器名字，事件不写 extension |
| `records a fixed failed category and a bounded diagnostic` | 同上 | 新增 |
| `records a fixed orphaned category and a bounded diagnostic` | 同上 | 新增 |
| `keeps both interrupted runs and explicit abort handlers at status ok` | `durable-phase-report-clock-and-replay-follow-the-v140-vocabulary` 的 abort span：`outcome` `aborted`，status `ok`，`private-abort-reason` 不在 span 里 | 部分。上游还有一条被 abort signal 打断的 run，outcome 也是 `aborted` 且 status `ok`。cadr 的 phase 函数没有这条 signal |
| `mirrors runtime reports as fixed-field phase events and type-only counters` | 无 | 范围外：`runtime.report` 的 task_error、extension_error、host_error 三连。cadr 的 runtime 没有这组报告入口。时钟失败的 `host_error` 计数由 `durable-phase-report-clock-and-replay-follow-the-v140-vocabulary` 锁住，且不把 `private-clock-error` 放进 span |
| `reports hook failures on the phase and clock failures without a phase context` | 时钟一半见上一行 | 范围外：`beforeRequest` 钩子抛错要 GenerationTask。时钟一半已锁 |
| `counts an outside-span session failure without starting a span` | `durable-session-failure-counts-without-starting-a-span`：没有 span，metric 只有 `{type: session_failed}`，宿主报告带 `Unknown conversation`，测量值里没有这句，也没有 `app.failed` | 新增 |
| `counts reports raised with a NOOP span without creating a root` | 无 | 范围外：`subscribeCommits` 在没有 span 时抛错并计 `listener_error`。cadr 没有 commit 订阅 |
| `attaches synchronous commit-listener reports to the active submission span` | 无 | 范围外：同上，同步 listener 要把 `pi.durable.report` 记在 submit span 上 |
| `preserves async listener error containment and report counting` | 无 | 范围外：异步 listener 拒绝后只计 `listener_error`，正文不进 span |
| `emits replay for a codemode journal result without rerunning its nested tool` | `durable-loaded-task-is-resumed-once-and-commits-emit-after-success`：journal 里的 `once` 发 `pi.durable.replay`，invoke 抛错也不再跑 | 部分。上游还把 replay 放在重开后的 generation phase 上，并断言工具只跑了一次。cadr 直接对 sandbox 重放 journal |

## `packages/durable/test/harness-telemetry-options.test.ts`

| 上游 `it` | FiveAM | 状态 |
|---|---|---|
| `accepts one adapter with optional propagation and metrics capabilities` | `durable-submit-emits-a-root-span-and-keeps-content-out` 开头：不传 telemetry 时 harness 的 telemetry 是 `*noop-telemetry-context*`。传入的 in-memory telemetry 能打开 span、link、counter 和 histogram | 部分。上游其余是 TypeScript 类型：`telemetry` 可省略、可以是 `NOOP_TELEMETRY_CONTEXT`、只有 `counter` 的对象不能赋给 `HarnessOptions`。cadr 没有这层类型检查 |

## 打回里点名、上面的 `it` 没有单独成行的行为

| 行为 | FiveAM | 状态 |
|---|---|---|
| 没有进展，以及 abort 没有终态，reason 是 `threw` | `durable-no-progress-and-bare-abort-report-threw`：两条 `pi.durable.report` 的 reason 都是 `threw`，outcome 是 `faulted`。reason 里没有 `no_progress`，也不是 `abort` | 新增。`restart_limit` 仍是 `restart_limit` |
