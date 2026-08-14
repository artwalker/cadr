# GOAL v7: Wave 2 — completion report

> Historical report: the `71efc6f0…` inside this document records the audit
> anchor as it stood at Goal 7; from Goal 9 on, the current normative baseline is
> `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.

## Status

Parts A→B→C→D were completed in that order. The user confirmed items 1–7 of the
limited-expansion proposal one by one, and adjudicated that item 8's runtime
provider/tool registration, `sendMessage`/`sendUserMessage` and
`setSessionName` be unfrozen under the same limitation; the implementation
covers only capabilities that already exist in the audit commit, and the widened
extension API has been re-frozen.

The pre-implementation compatibility gate
`LEGACY-EXTENSION-SOURCE-REMAINS-COMPATIBLE-AFTER-WAVE-2-API-EXPANSION` landed
first; before the production implementation its result was `221/221`, and at
closeout it is still part of the all-green gate.

Fixed references:

- Audit commit: `71efc6f0c1909874ec8c944637a9ae7fc0e2d508`
- Audit checkout: `/tmp/cadr-parity-71efc6f0`
- Work-start commit: `14fc6eefeb7e9329a2743ba385cf913060240de2`
- Work-start test baseline: `1332/1332`

## Frozen-area work-start baseline

The following object IDs must be identical item by item at closeout; for the
extension API the SHA-256 of the export block text is additionally fixed.

| Frozen path | Work-start object ID |
|---|---|
| `src/cadr-ai` | `e9c5affef2e36db4cdf6f7fc37a20534cd1a661a` |
| `test/cadr-ai` | `e984d714c6e53cb34d89c495939f9d2b3d975fd8` |
| `cadr-ai.asd` | `f99e2708e9ff7e3465824c7ea04bedce9512724c` |
| `src/cadr-tui` | `1a5ba07b17cd3b0c55c8a1ec35a79d1fafda0950` |
| `test/cadr-tui` | `947e63cc73b259ea2b18bfc281b5229a13f9a5d0` |
| `cadr-tui.asd` | `c09f6172c1c186f15c726b2c04b7ea65a4f4214c` |
| `src/cadr-agent/extensions.lisp` | `5b882c26c48287f28ff31137ad9875ce28fe5f0f` |
| `test/cadr-agent/extensions-test.lisp` | `2053ef06e0bc65b03744ea024c4407eac0817468` |
| `src/cadr-cli/extensions.lisp` | `4e94df55ed27b96c43313d24069225c015b99c17` |
| `test/cadr-cli/extensions-test.lisp` | `3fa8a1f9eb8a6b519b27f3004290be7551171288` |
| `src/cadr-agent/tool.lisp` | `42093b6062ab16cde78f72cb87a878057b7dd131` |
| `test/cadr-agent/tool-loop-test.lisp` | `f44cd198c1fbfab8b7402f457d1ea2a848a9aa74` |
| `src/cadr-cli/tools` | `0ad21371b8ad2e759dacb26202383965a68d5493` |
| `test/cadr-cli/file-tools-test.lisp` | `206bb0416ff53abba10378a873eeffb698162327` |
| `test/cadr-cli/search-tools-test.lisp` | `5ca50cd12f4b1442891c12ee9fa231b24df07a6c` |
| `test/cadr-cli/bash-test.lisp` | `3475ab2a3760afa06928d8748a44e1514d1ac461` |
| `test/cadr-cli/execution-policy-test.lisp` | `19df8cfbae90aa3d2afb44eb01c81939de90a2cc` |

Extension export block SHA-256:
`65bdec58440ddfaaf1aa80b62c069f91a0713251b7601911f2ee2747d1586e6d`.

## Agent package: 18 M files

Every file has a Common Lisp counterpart surface; Part A proposes no N/A.

| Baseline test file | cadr target module | Semantics that must be ported |
|---|---|---|
| `packages/agent/test/agent-loop.test.ts` | `src/cadr-agent/agent.lisp`, `queue.lisp`, `harness.lisp` | event spine, tool batch ordering, steering injection, next-turn and termination |
| `packages/agent/test/agent.test.ts` | `src/cadr-agent/agent.lisp`, `queue.lisp` | lifecycle, asynchronous subscription, busy guard, abort, continue, the two kinds of queue |
| `packages/agent/test/e2e.test.ts` | `src/cadr-agent/harness.lisp` | the faux provider's prompt/tool/abort/context/thinking/continue closed loop |
| `packages/agent/test/harness/agent-harness-stream.test.ts` | `src/cadr-agent/harness.lisp` | stream options and provider hook snapshots |
| `packages/agent/test/harness/agent-harness.test.ts` | `src/cadr-agent/harness.lisp`, `queue.lisp`, `compaction.lisp` | queue, events, savepoint, retry, compaction, hook errors and listener ordering |
| `packages/agent/test/harness/compaction.test.ts` | `src/cadr-agent/compaction.lisp`, `session.lisp` | threshold, cut point, summary, split turn, usage and failure recovery |
| `packages/agent/test/harness/nodejs-env.test.ts` | `src/cadr-agent/execution-env.lisp` | the Lisp-equivalent implementation of the filesystem and shell execution abstraction |
| `packages/agent/test/harness/prompt-templates.test.ts` | `src/cadr-agent/prompt-templates.lisp` | template discovery, variable expansion, errors and ordering |
| `packages/agent/test/harness/repo.test.ts` | `src/cadr-agent/repo.lisp` | repo CRUD, branch/tree traversal and consistency |
| `packages/agent/test/harness/resource-formatting.test.ts` | `src/cadr-agent/resource-formatting.lisp` | resource formatting and boundaries |
| `packages/agent/test/harness/session.test.ts` | `src/cadr-agent/session.lisp` | JSONL session, tree, migration, resume and continue |
| `packages/agent/test/harness/skills.test.ts` | `src/cadr-agent/skills.lisp` | skill discovery and loading under the Lisp extension ecosystem |
| `packages/agent/test/harness/sqlite-migrations.test.ts` | `src/cadr-agent/storage/sqlite.lisp` | schema migration, idempotence and failure atomicity |
| `packages/agent/test/harness/sqlite-node.test.ts` | `src/cadr-agent/storage/sqlite.lisp` | SQLite node access and reopen consistency |
| `packages/agent/test/harness/storage.test.ts` | `src/cadr-agent/storage.lisp` | the storage contract and implementation substitution |
| `packages/agent/test/harness/system-prompt.test.ts` | `src/cadr-agent/system-prompt.lisp` | prompt assembly, resource injection and stable ordering |
| `packages/agent/test/harness/tools.test.ts` | `src/cadr-agent/harness.lisp` | the harness's tool registration/invocation orchestration; the tools' own semantics stay frozen |
| `packages/agent/test/harness/truncate.test.ts` | `src/cadr-agent/truncate.lisp` | UTF-8 byte/line truncation, boundaries and metadata |

## Coding-agent session/queue: 46 M files

| Baseline test file | cadr target module | Notes |
|---|---|---|
| `packages/coding-agent/test/agent-session-auto-compaction-queue.test.ts` | `queue.lisp`, `harness.lisp`, `compaction.lisp` | queue timing before and after compaction |
| `packages/coding-agent/test/agent-session-branching.test.ts` | `session.lisp`, `harness.lisp` | branched session |
| `packages/coding-agent/test/agent-session-compaction.test.ts` | `compaction.lisp`, `session.lisp` | compaction events and persistence |
| `packages/coding-agent/test/agent-session-concurrent.test.ts` | `queue.lisp`, `harness.lisp` | concurrent event serialization and settlement |
| `packages/coding-agent/test/agent-session-dynamic-provider.test.ts` | `harness.lisp` | provider configuration savepoint; the provider layer stays frozen; depends on the `session_start` extension event |
| `packages/coding-agent/test/agent-session-dynamic-tools.test.ts` | `harness.lisp` | tool registry snapshot; tool semantics stay frozen; depends on the `session_start` extension event |
| `packages/coding-agent/test/agent-session-retry.test.ts` | `harness.lisp`, `queue.lisp` | retry and prompt completion |
| `packages/coding-agent/test/agent-session-runtime-events.test.ts` | `harness.lisp`, `session.lisp`, extension lifecycle | **freeze conflict** |
| `packages/coding-agent/test/agent-session-stats.test.ts` | `session.lisp`, `harness.lisp` | usage/session stats |
| `packages/coding-agent/test/agent-session-tree-navigation.test.ts` | `session.lisp`, `compaction.lisp` | tree navigation and branch summary |
| `packages/coding-agent/test/branch-summary-extensions.test.ts` | `compaction.lisp`, extension lifecycle | **freeze conflict: `session_before_tree`** |
| `packages/coding-agent/test/compaction-extensions-example.test.ts` | `compaction.lisp`, extension lifecycle | **freeze conflict: compaction hook** |
| `packages/coding-agent/test/compaction-extensions.test.ts` | `compaction.lisp`, extension lifecycle | **freeze conflict: compaction hook** |
| `packages/coding-agent/test/compaction-serialization.test.ts` | `compaction.lisp`, `session.lisp` | compaction mutual exclusion under concurrency |
| `packages/coding-agent/test/compaction-summary-reasoning.test.ts` | `compaction.lisp` | reasoning summary |
| `packages/coding-agent/test/compaction.test.ts` | `compaction.lisp`, `session.lisp` | context selection and summary format |
| `packages/coding-agent/test/sdk-session-manager.test.ts` | `session.lisp`, `harness.lisp` | session manager facade |
| `packages/coding-agent/test/session-cwd.test.ts` | `session.lisp`, CLI session selection | cwd filtering |
| `packages/coding-agent/test/session-file-invalid.test.ts` | `session.lisp`, CLI errors | an explicitly given bad file must be kept and must raise an error |
| `packages/coding-agent/test/session-id-readonly.test.ts` | `session.lisp`, CLI args | readonly session id |
| `packages/coding-agent/test/session-info-modified-timestamp.test.ts` | `session.lisp` | session list timestamps |
| `packages/coding-agent/test/session-manager/build-context.test.ts` | `session.lisp` | building context from the tree |
| `packages/coding-agent/test/session-manager/custom-session-id.test.ts` | `session.lisp` | custom ID |
| `packages/coding-agent/test/session-manager/file-operations.test.ts` | `session.lisp`, `repo.lisp` | create, load, append, rewrite |
| `packages/coding-agent/test/session-manager/labels.test.ts` | `session.lisp` | label nodes |
| `packages/coding-agent/test/session-manager/migration.test.ts` | `session.lisp` | lossless v1/v2→v3 migration |
| `packages/coding-agent/test/session-manager/save-entry.test.ts` | `session.lisp` | custom entry |
| `packages/coding-agent/test/session-manager/tree-traversal.test.ts` | `session.lisp` | parent tree and leaf |
| `packages/coding-agent/test/startup-session-name.test.ts` | `session.lisp`, CLI startup | session name |
| `packages/coding-agent/test/suite/agent-session-bash-persistence.test.ts` | `harness.lisp`, `session.lisp` | bash message persistence; bash semantics stay frozen |
| `packages/coding-agent/test/suite/agent-session-compaction.test.ts` | `harness.lisp`, `compaction.lisp` | the harness compaction closed loop |
| `packages/coding-agent/test/suite/agent-session-model-extension.test.ts` | `harness.lisp`, extension lifecycle | **freeze conflict; provider/tool semantics stay frozen** |
| `packages/coding-agent/test/suite/agent-session-prompt.test.ts` | `harness.lisp`, `queue.lisp` | prompt lifecycle |
| `packages/coding-agent/test/suite/agent-session-queue.test.ts` | `queue.lisp`, `harness.lisp` | the exact steering/follow-up semantics |
| `packages/coding-agent/test/suite/agent-session-retry-events.test.ts` | `harness.lisp`, `queue.lisp`, extension events | settlement ordering; partly a **freeze conflict** |
| `packages/coding-agent/test/suite/agent-session-runtime.test.ts` | `harness.lisp`, `session.lisp` | runtime binding and shutdown |
| `packages/coding-agent/test/suite/regressions/1717-2113-agent-session-event-settlement.test.ts` | `harness.lisp`, extension events | **freeze conflict: `message_end`/`tool_call`** |
| `packages/coding-agent/test/suite/regressions/2860-replaced-session-context.test.ts` | `harness.lisp`, `session.lisp`, extension lifecycle | **freeze conflict: start/shutdown** |
| `packages/coding-agent/test/suite/regressions/3686-session-name-event.test.ts` | `session.lisp`, extension/public events | **freeze conflict: `session_info_changed`** |
| `packages/coding-agent/test/suite/regressions/5217-compaction-reason.test.ts` | `compaction.lisp` | compaction reason |
| `packages/coding-agent/test/suite/regressions/5943-session-start-notify.test.ts` | extension lifecycle | **freeze conflict: `session_start`** |
| `packages/coding-agent/test/suite/regressions/5996-session-name-newlines.test.ts` | `session.lisp`, extension/public events | name sanitization; partly a **freeze conflict** |
| `packages/coding-agent/test/suite/regressions/6324-branch-summary-ambient-auth.test.ts` | `compaction.lisp`, `harness.lisp` | ambient auth pass-through; the provider layer stays frozen |
| `packages/coding-agent/test/suite/regressions/6647-compaction-retries-transient-stream-drop.test.ts` | `compaction.lisp`, `harness.lisp` | transient stream retry |
| `packages/coding-agent/test/suite/regressions/pre-prompt-compaction-no-continue.test.ts` | `compaction.lisp`, `queue.lisp` | pre-prompt compaction does not continue by mistake |
| `packages/coding-agent/test/suite/regressions/startup-session-rebind-duplicate-subscription.test.ts` | `harness.lisp`, `session.lisp`, extension lifecycle | subscription deduplication; partly a **freeze conflict** |

## Part C: print/JSON target files

`CODING-CLI-SDK` is a large mixed category; this goal takes in only the files
directly related to mode selection, one-shot input, output cleanliness and
process shutdown:

| Baseline test file | cadr target module | Semantics that must be ported |
|---|---|---|
| `packages/coding-agent/test/args.test.ts` | `src/cadr-cli/args.lisp` | parsing of and conflicts among `--mode`, `--print`, `--no-tui` |
| `packages/coding-agent/test/initial-message.test.ts` | `src/cadr-cli/initial-message.lisp` | merging the argv prompt with stdin |
| `packages/coding-agent/test/print-mode.test.ts` | `src/cadr-cli/modes/print.lisp`, JSON mode | text/JSON output, error exit, shutdown |
| `packages/coding-agent/test/stdout-cleanliness.test.ts` | CLI entry/modes | stdout carries only the protocol or the result |
| `packages/coding-agent/test/suite/regressions/5080-signal-shutdown-extension-cleanup.test.ts` | CLI close, extension lifecycle | **freeze conflict: `session_shutdown`** |
| `packages/coding-agent/test/suite/regressions/5724-sigterm-signal-exit.test.ts` | CLI signal handling | SIGTERM exit semantics |

The remaining `CODING-CLI-SDK` M files are not unfrozen early merely because
they carry the same tag; they still belong to later Waves. JSON mode has no
separate parity-map tag, and is accepted jointly by the JSON cases of
`print-mode.test.ts` and the real-process JSONL test added by this goal.

The fixed baseline for mode priority is:

1. explicit `--mode rpc`;
2. explicit `--mode json`;
3. explicit `--print`;
4. automatic print when either stdin or stdout is not a TTY;
5. everything else enters interactive.

`--no-tui` is only the line-REPL difference that cadr deliberately keeps and
that must be requested explicitly; it does not take part in the non-TTY
automatic fallback.

## Part D: the 6 M files of RPC

| Baseline test file | cadr target module | Semantics that must be ported |
|---|---|---|
| `packages/coding-agent/test/rpc-client-clone.test.ts` | `src/cadr-cli/modes/rpc/client.lisp` | clone and client state |
| `packages/coding-agent/test/rpc-client-process-exit.test.ts` | RPC client/entry | subprocess exit and convergence of pending requests |
| `packages/coding-agent/test/rpc-jsonl.test.ts` | `src/cadr-cli/modes/rpc/jsonl.lisp` | LF/CRLF/U+2028/U+2029/no trailing LF |
| `packages/coding-agent/test/rpc-prompt-response-semantics.test.ts` | `src/cadr-cli/modes/rpc/mode.lisp` | prompt preflight, a single response, errors |
| `packages/coding-agent/test/rpc.test.ts` | `src/cadr-cli/modes/rpc/` | command, event, session and the shutdown closed loop |
| `packages/coding-agent/test/suite/regressions/5868-rpc-unknown-command-id.test.ts` | RPC dispatcher | an unknown command keeps the request id |

The reference command union is:

`prompt`, `steer`, `follow_up`, `abort`, `new_session`, `get_state`,
`set_model`, `cycle_model`, `get_available_models`, `set_thinking_level`,
`cycle_thinking_level`, `get_available_thinking_levels`,
`set_steering_mode`, `set_follow_up_mode`, `compact`,
`set_auto_compaction`, `set_auto_retry`, `abort_retry`, `bash`,
`abort_bash`, `get_session_stats`, `export_html`, `switch_session`, `fork`,
`clone`, `get_fork_messages`, `get_entries`, `get_tree`,
`get_last_assistant_text`, `set_session_name`, `get_messages`,
`get_commands`.

The response is fixed as
`{id?,type:"response",command,success,data?}` or
`{id?,type:"response",command,success:false,error}`; session events are
forwarded line by line as they are. Input EOF closes normally; the `command` of
a parse error is `parse`; an unknown command keeps its `id`. JSONL frames on LF
only, tolerates CRLF, does not treat U+2028/U+2029 as separators, and handles a
last frame with no trailing LF.

## Exact Session v3 on-disk specification

### Header

The first valid JSONL record:

```json
{
  "type": "session",
  "version": 3,
  "id": "session-id",
  "timestamp": "ISO-8601 string",
  "cwd": "/absolute/path",
  "parentSession": "optional parent session file"
}
```

`parentSession` may be omitted. When discovering sessions the reference
implementation scans at most 1 MiB in a stream, skips blank lines and bad JSON,
and filters by cwd; a non-empty bad file passed explicitly is kept as it is and
raises an error, and only an empty file may be initialized.

### Entry envelope and types

Common to all nodes:

```json
{"type":"entry-type","id":"8-hex","parentId":"optional-id","timestamp":"ISO-8601 string"}
```

The ID is an 8-digit hexadecimal string that has been collision-checked. Entries
are written in actual append order and the tree is expressed by `parentId`;
after a reload the current leaf is the physically last valid entry.

| `type` | fields outside the envelope |
|---|---|
| `message` | `message` |
| `thinking_level_change` | `thinkingLevel` |
| `model_change` | `provider`, `modelId` |
| `compaction` | `summary`, `firstKeptEntryId`, `tokensBefore`, `details?`, `usage?`, `fromHook?` |
| `branch_summary` | `fromId`, `summary`, `details?`, `usage?`, `fromHook?` |
| `custom` | `customType`, `data?` |
| `custom_message` | `customType`, `content`, `details?`, `display` |
| `label` | `targetId`, `label?` |
| `session_info` | `name?` |

The reference coding-agent manager does not create the file before the first
assistant entry appears; the first write to disk uses an exclusive create to
write the header and the buffered entries, and appends afterwards.

### Reading, crash tails and migration

- A blank or malformed JSONL record is skipped, including a bad tail left by a
  crash; the first record that parses successfully must be a session header
  containing a string `id`.
- v1→v2 fills in the `id`/`parentId` chain for existing entries and converts
  compaction's `firstKeptEntryIndex` into `firstKeptEntryId`.
- v2→v3 renames the message role `hookMessage` to `custom`.
- Migration modifies the parsed object directly, so unknown envelope fields must
  be preserved.
- The baseline's `_rewriteFile` is a truncating rewrite; this goal explicitly
  requires cadr to keep using the stronger same-directory temporary file +
  rename atomic replacement.
- For the real `~/.cadr/sessions/` only dry-run/backup paths are allowed; every
  migration test must use a temporary directory. At work start that directory
  held 10 JSONL files, and Part A neither read nor wrote their contents.

### Differences of cadr's current v2

| current cadr v2 | reference v3 |
|---|---|
| header `version:2` | `version:3` |
| header timestamp is integer milliseconds | ISO string |
| no `parentSession` | optional `parentSession` |
| supports only `message`, `compaction` | supports all 9 entry types in the table above |
| compaction uses the non-reference field `sourceIds` | `details?`, `usage?`, `fromHook?` |
| messages internally use `type` and snake_case | the baseline's AgentMessage role/camelCase |
| strictly rejects bad JSON in the middle; ignores only a bad tail with no newline | skips blank/malformed records |
| writes the header immediately on create | writes to disk only after the first assistant entry |
| v1→v2 only, and migrates messages only | v1→v2→v3 |
| rejects a duplicate or dangling parent outright | recovers with the append log + parent tree |
| already has atomic temp+rename | keeps that stronger discipline |

## Exact queue semantics

- steering and follow-up are each FIFO; the default mode of both is
  `one-at-a-time`, and there is also `all`.
- steering is polled at the start of a turn and after the end of every
  assistant/tool batch; injection happens only after every tool call of the
  current batch has finished, and does not preempt half a batch.
- follow-up is drained only when the agent would otherwise stop, and it starts
  the next inner run.
- `one-at-a-time` drains one each time; `all` atomically takes the queue snapshot
  as it is at that moment.
- while the agent is busy, `prompt`/`continue` raise an error; `steer`/`followUp`
  may be enqueued.
- harness abort captures and clears the steer/follow-up queues, terminates the
  current run, keeps the next-turn queue, and emits abort and queue-update.
- queue-update must carry the complete snapshot of both `{steer, followUp}`
  queues.
- cadr currently has only a busy guard and an abort flag, with no dual queue, no
  mode, no injection timing and no wait-for-idle.

## N/A candidates

This round proposes no N/A. The `nodejs-env`, SQLite and
prompt/resource/skill tests all have a clear Common Lisp equivalent
implementation, and are not "unique to the TS runtime". The extension
lifecycle and the RPC UI bridge are likewise the baseline's cross-platform
product semantics, and cannot honestly be marked N/A.

## The original hard blocker before entering Part B

What follows is the blocking audit record as it stood at Part A; the user
subsequently lifted the blockers one by one through items 1–8 of the
limited-unfreeze proposal, and the current conclusion is governed by the
completion status at the top of this document and the closeout evidence below.

cadr's current public hook allowlist contains only:

```lisp
(:turn-start :turn-end :tool-call-before :tool-call-after)
```

This corresponds to `src/cadr-agent/extensions.lisp:349-351`; the macro and the
public context accessors are at `src/cadr-agent/extensions.lisp:435` and
`src/cadr-agent/package.lisp:35-45`, and both are absolutely frozen by goal7.

But the target files directly require:

- `session_start`, `session_shutdown`, `session_before_switch`,
  `session_before_fork`, `session_before_tree`;
- `session_info_changed`, `message_end`, `tool_call`, `agent_settled`;
- the RPC `createExtensionUIContext` and `extension_ui_request/response`,
  covering select/confirm/input/editor/notify/status/widget/title/editor text.

The reference evidence includes:

- `packages/coding-agent/src/core/agent-session-runtime.ts:138-172`
- `packages/coding-agent/src/core/agent-session.ts:584-585,2875,2950-2953`
- `packages/coding-agent/src/core/extensions/types.ts:563-640,724-757,854`
- `packages/coding-agent/src/modes/rpc/rpc-mode.ts:128-319`
- `packages/coding-agent/src/modes/rpc/rpc-types.ts:239-273`

This is not a TS runtime difference, and it cannot be done without changing the
hook allowlist, the event payloads and the context surface. There are only two
workable routes:

1. unfreeze only the baseline extension lifecycle events and the RPC extension
   UI surface that the Wave 2 targets actually need, keeping the macro signature
   unchanged and adding only capabilities the baseline already has;
2. keep the extension API completely frozen, while the user explicitly removes
   the tests above and the RPC extension UI from the goal7 acceptance scope, as
   an approved scoped exception.

The user subsequently adjudicated that a limited-expansion plan may be proposed
first; the implementation still had to wait for that plan to be confirmed item
by item, and Parts B/C/D had not started.

### Second blocker review

After scanning the 46 `CODING-SESSION` targets file by file for `pi.on(...)`,
18 files directly register public events outside the currently frozen allowlist:

| Target file | Baseline public events directly depended on |
|---|---|
| `agent-session-concurrent.test.ts` | `input` |
| `agent-session-dynamic-provider.test.ts` | `session_start` |
| `agent-session-dynamic-tools.test.ts` | `session_start` |
| `agent-session-runtime-events.test.ts` | `session_before_fork`, `session_before_switch`, `session_shutdown`, `session_start` |
| `branch-summary-extensions.test.ts` | `session_before_tree` |
| `compaction-extensions-example.test.ts` | `session_before_compact`, `session_compact` |
| `suite/agent-session-compaction.test.ts` | `session_before_compact` |
| `suite/agent-session-model-extension.test.ts` | `before_agent_start`, `context`, `input`, `model_select`, `session_shutdown`, `session_start`, `tool_call`, `tool_result` |
| `suite/agent-session-prompt.test.ts` | `input` |
| `suite/agent-session-queue.test.ts` | `agent_end` |
| `suite/agent-session-retry-events.test.ts` | `message_start`, `message_end` |
| `suite/agent-session-runtime.test.ts` | `message_end`, `session_before_fork`, `session_before_switch`, `session_shutdown`, `session_start` |
| `suite/regressions/1717-2113-agent-session-event-settlement.test.ts` | `message_end`, `tool_call` |
| `suite/regressions/2860-replaced-session-context.test.ts` | `session_shutdown`, `session_start` |
| `suite/regressions/3686-session-name-event.test.ts` | `session_info_changed` |
| `suite/regressions/5217-compaction-reason.test.ts` | `session_before_compact`, `session_compact` |
| `suite/regressions/5943-session-start-notify.test.ts` | `session_start` |
| `suite/regressions/pre-prompt-compaction-no-continue.test.ts` | `session_before_compact` |

This does not yet count the extension runner tests that do not register through
a literal `pi.on(...)`, nor Part C's direct requirement of `session_shutdown` in
`print-mode.test.ts`.

Conclusions of the alternative-implementation review:

- adding only an internal agent/session event spine cannot let extensions
  register these events;
- quietly mapping the new events onto the existing four events would change
  payload/timing, and is not the baseline semantics;
- bypassing `register-extension-hook` to build a separate private registration
  channel would still widen the observable API;
- the RPC UI bridge must add the
  select/confirm/input/editor/status/widget/title/editor-text capabilities that
  the existing `extension-context` does not have, and it also cannot rest on a
  private implementation inside the RPC dispatcher alone;
- `docs/architecture.md:1015-1017` additionally freezes the events to the
  current four explicitly, so even leaving the macro signature and the package
  export text untouched, widening the allowlist is still touching a frozen API.

Therefore "keep every frozen object ID while turning every target file to C" is
unsatisfiable under the current specification.

## Part B: session v3, queues and the agent harness

Completed:

- new sessions write the v3 header/envelope; the write to disk is deferred until
  the first assistant entry;
- atomic v1/v2→v3 migration preserving unknown fields; bad records/crash tails
  are skipped, and session discovery reads at most 1 MiB;
- the full entry union
  thinking/model/compaction/branch/custom/custom-message/label/session-info;
  harness storage additionally covers the baseline's `active_tools_change` and
  `leaf`;
- steering/follow-up/next-turn, `one-at-a-time`/`all`, post-batch injection,
  abort cleanup and wait-for-idle;
- transient retry, retry event, abort during backoff, overflow compaction;
- memory/JSONL/SQLite storage/repository, fork, branch materialization,
  materialized stats, `001_initial.sql`, WAL/FULL/busy timeout and transaction
  rollback;
- prompt template, skill, resource/system-prompt formatting, UTF-8 byte/line
  truncation, and the timeout, abort and process-group cleanup of the
  filesystem/shell execution environment.

The SQLite adapter was implemented early because two audit tests of the Agent
package are on this Wave's mandatory list; Wave 5 keeps the standalone storage
package, the server and the eval integration, and does not repeat the adapter.
There is no N/A.

The limited extension API adds lifecycle events, the RPC UI context and four
groups of runtime actions, following the approved proposal. The runtime provider
uses an extension-host overlay and did not change `src/cadr-ai`; the TUI bridge
did not change `src/cadr-tui`. The old macro signature, the old four events and
the old result semantics are continuously verified by
`LEGACY-EXTENSION-SOURCE-REMAINS-COMPATIBLE-AFTER-WAVE-2-API-EXPANSION`.

## Part C: text/JSON modes

Mode priority is implemented as: explicit `--mode` → `--print` → explicit
`--no-tui` → automatic text when not a TTY → TUI. text writes only the final
assistant text, and JSON writes one agent event per line; the first argv prompt
is merged with stdin, and later argv messages are executed in order; provider
errors go to stderr with a non-zero exit, and shutdown/signal cleanup keeps
running.

List of changes to existing assertions/scripts:

| Location | Old behavior | New behavior | Baseline grounds |
|---|---|---|---|
| CLI mode gate | non-TTY defaulted to the line REPL | non-TTY defaults to one-shot text; only `--no-tui` is the line REPL | `packages/coding-agent/src/main.ts` mode selection and `args.test.ts` |
| `scripts/acceptance-smoke.sh` | a pipe implicitly entered the REPL for multiple turns | passes `--no-tui` explicitly to keep the multi-turn acceptance | the line REPL is a difference cadr keeps, and may only be selected explicitly |
| existing multi-turn live scripts | a pipe implicitly entered the REPL | passes `--no-tui` explicitly | same as above |

No old test was deleted; the above is this goal's only exemption that changes
the semantics of an existing test.

## Part D: RPC

Implements the audit commit's complete command union, the fixed response shape,
request id preservation, agent event JSONL forwarding,
session/model/thinking/queue/compaction control, bash/abort,
clone/fork/tree/messages/stats/HTML/commands, and EOF/close cleanup. Framing is
on LF only, tolerating CRLF, U+2028/U+2029 and no trailing LF.

The RPC extension UI bridge covers response, cancel, timeout, signal, unknown id
and EOF default completion for select/confirm/input/editor, and the
fire-and-forget wire for notify/status/widget/title/editor text. The process
test completes prompt→event→steer→normal shutdown with a local OpenAI SSE stub,
and does not implement a server.

## Parity inventory

All 76 target files of Part A moved from `M` to `C`:

- Agent: 18/18;
- coding-agent session/queue: 46/46;
- print/JSON: 6/6;
- RPC: 6/6;
- N/A: 0.

The whole-repository manifest was updated from `28 C / 0 U / 324 M` to
`104 C / 0 U / 248 M`.

## Extension API re-freeze

| Path | Closeout Git object ID |
|---|---|
| `src/cadr-agent/extensions.lisp` | `58539b2849fcf6b6756657d46f94ac09a3c639fc` |
| `src/cadr-agent/package.lisp` | `15525d7cc8bd860d66b3bbaf0f1ab56174464d39` |
| `test/cadr-agent/extensions-test.lisp` | `c097b312567386421da5cdae0f1c13d039b21bde` |
| `test/cadr-agent/extensions-wave2-test.lisp` | `c6cfa3544a3f74b44585a9c62f25af7c015d9afa` |
| `src/cadr-cli/extensions.lisp` | `4e94df55ed27b96c43313d24069225c015b99c17` |
| `test/cadr-cli/extensions-test.lisp` | `3fa8a1f9eb8a6b519b27f3004290be7551171288` |
| `src/cadr-cli/modes/rpc/jsonl.lisp` | `5839f4ae5754d91c773a2bacb5a5f61d994fd85a` |
| `src/cadr-cli/modes/rpc/ui.lisp` | `c5f676784c137dac0a5604f660acbb71415bba48` |
| `src/cadr-cli/modes/rpc/mode.lisp` | `9e0100edd769295d4a9871cfc7ac7a77f5dd3f11` |
| `test/cadr-cli/rpc-test.lisp` | `5aa90e7fa51a093a6aa6d0c8dc098d8d2d41ff7b` |
| `cadr-agent.asd` | `189df27ae5b63f6619e53e981ad7c4c77a68868b` |
| `cadr-cli.asd` | `dc112807eea502182a1518f5582f6d47348a6ad2` |

Export text SHA-256:
`cc8e7d180b5007cbf4daa66ff904f8c0714992df646211c232135500efd936e7`.
Old-source compatibility fixture SHA-256:
`e2548662d773edfa21ecfa3b126b2209404a2b27385e6cd48e1f145a41747442`.
RPC wire/process fixture SHA-256:
`6dc3a25271080a59c3380704044c435a0a20a972c5ba19f32cae2acee2649b10`.
UI extension fixture SHA-256:
`c1148870a539dd4a24001da74d17f668b6092bf55d41d845319d5439e3df9486`.

## Frozen-area closeout comparison

| Frozen path | Work-start object ID | Closeout object ID | Result |
|---|---|---|---|
| `src/cadr-ai` | `e9c5affef2e36db4cdf6f7fc37a20534cd1a661a` | `e9c5affef2e36db4cdf6f7fc37a20534cd1a661a` | identical |
| `test/cadr-ai` | `e984d714c6e53cb34d89c495939f9d2b3d975fd8` | `e984d714c6e53cb34d89c495939f9d2b3d975fd8` | identical |
| `cadr-ai.asd` | `f99e2708e9ff7e3465824c7ea04bedce9512724c` | `f99e2708e9ff7e3465824c7ea04bedce9512724c` | identical |
| `src/cadr-tui` | `1a5ba07b17cd3b0c55c8a1ec35a79d1fafda0950` | `1a5ba07b17cd3b0c55c8a1ec35a79d1fafda0950` | identical |
| `test/cadr-tui` | `947e63cc73b259ea2b18bfc281b5229a13f9a5d0` | `947e63cc73b259ea2b18bfc281b5229a13f9a5d0` | identical |
| `cadr-tui.asd` | `c09f6172c1c186f15c726b2c04b7ea65a4f4214c` | `c09f6172c1c186f15c726b2c04b7ea65a4f4214c` | identical |
| `src/cadr-agent/tool.lisp` | `42093b6062ab16cde78f72cb87a878057b7dd131` | `42093b6062ab16cde78f72cb87a878057b7dd131` | identical |
| `test/cadr-agent/tool-loop-test.lisp` | `f44cd198c1fbfab8b7402f457d1ea2a848a9aa74` | `f44cd198c1fbfab8b7402f457d1ea2a848a9aa74` | identical |
| `src/cadr-cli/tools` | `0ad21371b8ad2e759dacb26202383965a68d5493` | `0ad21371b8ad2e759dacb26202383965a68d5493` | identical |
| `test/cadr-cli/file-tools-test.lisp` | `206bb0416ff53abba10378a873eeffb698162327` | `206bb0416ff53abba10378a873eeffb698162327` | identical |
| `test/cadr-cli/search-tools-test.lisp` | `5ca50cd12f4b1442891c12ee9fa231b24df07a6c` | `5ca50cd12f4b1442891c12ee9fa231b24df07a6c` | identical |
| `test/cadr-cli/bash-test.lisp` | `3475ab2a3760afa06928d8748a44e1514d1ac461` | `3475ab2a3760afa06928d8748a44e1514d1ac461` | identical |
| `test/cadr-cli/execution-policy-test.lisp` | `19df8cfbae90aa3d2afb44eb01c81939de90a2cc` | `19df8cfbae90aa3d2afb44eb01c81939de90a2cc` | identical |

The `src/cadr-ai` fuse did not trip; `src/cadr-tui` was not changed either.

## Acceptance evidence

```text
./scripts/test-cl.sh
  cadr-ai:    369/369
  cadr-agent: 488/488
  cadr-tui:   582/582
  cadr-cli:   277/277
  total:      1716/1716

./build.sh
  cadr build: SBCL lacks sb-core-compression; building an uncompressed image.

file ./cadr
  ELF 64-bit LSB pie executable, x86-64

./cadr --version
  cadr 0.1.0

./scripts/acceptance-smoke.sh
  acceptance smoke: delayed persistence, --continue, and exact --resume passed

./scripts/test-wave2-process-modes.sh
  wave2 process modes: text, auto-stdin, JSONL, RPC intervention/UI/EOF,
  and SIGTERM cleanup passed

./scripts/live-deepseek-smoke.sh
  live smoke: DeepSeek Chat Completions streaming passed

./scripts/live-openai-oauth-smoke.sh
  OAuth live smoke: OpenAI Codex Responses streaming passed

./scripts/live-print-smoke.sh
  print live smoke: DeepSeek one-shot text mode passed

./scripts/live-extension-smoke.sh
  live extension smoke: DeepSeek write/reload/invoke loop passed
```

Every migration test uses a temporary directory; the real `~/.cadr/sessions/`
was neither read nor rewritten. `git diff --check` passed in the closeout
review. Work pauses after Goal 7 is complete; Wave 3 is not started.

## Closeout remediation

The two remediations added after the user's acceptance have already been taken
into the formal boundary:

- `cl-sqlite` (ASDF system `sqlite`) is retroactively recognized as the second
  registered self-build exception, at the same level as `cl+ssl`; its `iterate`,
  CFFI, Alexandria, Babel, trivial-features transitive closure and the ownership
  of the system `libsqlite3` are recorded in `docs/dependency-audit.md`, and the
  README carries the complete exception list in sync;
- the Part A of every subsequent goal must audit newly added third-party
  dependencies and their transitive closure, and must be `blocked` immediately
  when the user's explicit authorization has not been obtained; implementing
  first and being recognized retroactively is forbidden;
- every subsequent "complete" must include commits grouped logically, a full
  re-verification after the commits, and a clean working tree; a completion
  declaration with uncommitted changes is invalid.

The Wave 2 code was recorded in the ledger in the following order:

| Order | Commit | Contents |
|---:|---|---|
| 1 | `e627a787d` | pin the Wave 2 tests, fixtures and the process/live gates |
| 2 | `d5958bb6b` | widen and re-freeze the extension API |
| 3 | `795df7997` | session v3, queue, retry, storage and harness |
| 4 | `7f9ef7d73` | one-shot text and JSON modes |
| 5 | `83e96958f` | RPC protocol, UI bridge and ASDF wiring |
| 6 | the commit containing this report | dependency audit, architecture, parity and closeout documentation |
