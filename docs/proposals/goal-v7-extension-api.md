# GOAL v7 extension API bounded expansion proposal

> Historical proposal: the `71efc6f0…` in this document is only Goal 7's audit
> anchor at the time; from Goal 9 onward the current canonical baseline is
> `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.

Status: **Items 1–8 are implemented and have passed acceptance; the expanded API has been re-frozen.**

Fixed behavior baseline:
`71efc6f0c1909874ec8c944637a9ae7fc0e2d508`, checkout
`/tmp/cadr-parity-71efc6f0`. Every `file:line` in this document refers to that commit.

## 1. Boundary

This proposal unfreezes only:

1. the extension lifecycle events that the Wave 2 session, the agent event
   spine and the queue tests directly need, and that already exist in the audit
   commit;
2. the extension UI request/response surface that already exists in the audit
   commit's RPC protocol;
3. the Lisp naming, payload representation, result representation and
   `cadr-cli` bridge for the surfaces added above.

It explicitly does not unfreeze providers, tool execution semantics, TUI
components, or any remaining extension capability. The existing four events,
the macro signature and the behavior stay as they are:

```lisp
(define-event-hook event &key (priority 0) handler)

:turn-start
:turn-end
:tool-call-before
:tool-call-after
```

The existing `extension-event-*` accessors, `extension-hook-result`,
`make-extension-hook-result`, handler order, priority, replacement, append,
block/error isolation, snapshot/reload and stale-context semantics are all
unchanged.

## 2. The Lisp public representation

### 2.1 Event names

TypeScript `snake_case` event names map to kebab-case Common Lisp keywords.
The four existing events are not renamed and get no alias:

| Baseline event | Lisp event | Handling |
|---|---|---|
| `turn_start` | `:turn-start` | Existing, zero change |
| `turn_end` | `:turn-end` | Existing, zero change |
| `tool_call` | `:tool-call-before` | Existing, zero change |
| `tool_result` | `:tool-call-after` | Existing, zero change |

The remaining approved events are added according to the tables below.

### 2.2 Payload

One public accessor is added:

```lisp
(extension-event-payload event) ; => read-only property list
```

The new events' fields are stored as kebab-case keywords; camelCase exists only
in the baseline TypeScript or in the RPC JSON. Nested objects likewise use
read-only plists, sequences use list/vector, and existing cadr domain objects
are reused directly. A missing optional field does not appear in the plist; an
explicit false uses `nil`, and where "missing" has to be distinguished from
`nil`, use `(getf plist key sentinel)`.

The four existing events keep using their existing dedicated accessors; this
proposal does not change their payload, and does not require old extensions to
switch to `extension-event-payload`.

TypeScript's `AbortSignal` maps to a new opaque
`extension-cancellation-signal`; only the following is exposed:

```lisp
(extension-cancellation-aborted-p signal) ; => boolean
```

This same object is used for the `:signal` of the lifecycle payload and the
`:signal` of the UI dialog.

### 2.3 Handler return values

Old events still accept only `nil` or `extension-hook-result`, and the
validation rules are entirely unchanged.

New events use the Lisp equivalent of the baseline's object-return semantics: a
handler returns `nil` or a strictly validated plist. Each event accepts only
the keys listed in the tables below; an unknown key, a wrong type, or a
non-`nil` return from an event that is not allowed to have a return value each
raise an execution error for that extension, without contaminating other
extensions. The merging, short-circuiting and chained rewriting across multiple
handlers follow the fixed reference runner implementation:
`packages/coding-agent/src/core/extensions/runner.ts:787-948`.

This way the signatures of `define-event-hook` and
`make-extension-hook-result` are not modified, and the new events' result
semantics are not stuffed into the four existing events.

## 3. New lifecycle events

### 3.1 Session lifecycle

| Baseline event → Lisp | payload field (baseline → Lisp) | handler result plist | Fixed baseline |
|---|---|---|---|
| `session_start` → `:session-start` | `reason` → `:reason` (`:startup/:reload/:new/:resume/:fork`); `previousSessionFile?` → `:previous-session-file` | none | `packages/coding-agent/src/core/extensions/types.ts:561-568` |
| `session_info_changed` → `:session-info-changed` | `name` → `:name`, `nil` when cleared | none | `packages/coding-agent/src/core/extensions/types.ts:570-575` |
| `session_before_switch` → `:session-before-switch` | `reason` → `:reason` (`:new/:resume`); `targetSessionFile?` → `:target-session-file` | `(:cancel-p boolean)` | `packages/coding-agent/src/core/extensions/types.ts:577-582,1103-1105` |
| `session_before_fork` → `:session-before-fork` | `entryId` → `:entry-id`; `position` → `:position` (`:before/:at`) | `:cancel-p`, `:skip-conversation-restore-p` | `packages/coding-agent/src/core/extensions/types.ts:584-589,1107-1110` |
| `session_before_compact` → `:session-before-compact` | `preparation` → `:preparation`; `branchEntries` → `:branch-entries`; `customInstructions?` → `:custom-instructions`; `reason` → `:reason` (`:manual/:threshold/:overflow`); `willRetry` → `:will-retry-p`; `signal` → `:signal` | `:cancel-p`; `:compaction` | `packages/coding-agent/src/core/extensions/types.ts:591-602,1112-1115` |
| `session_compact` → `:session-compact` | `compactionEntry` → `:compaction-entry`; `fromExtension` → `:from-extension-p`; `reason` → `:reason`; `willRetry` → `:will-retry-p` | none | `packages/coding-agent/src/core/extensions/types.ts:604-613` |
| `session_shutdown` → `:session-shutdown` | `reason` → `:reason` (`:quit/:reload/:new/:resume/:fork`); `targetSessionFile?` → `:target-session-file` | none | `packages/coding-agent/src/core/extensions/types.ts:615-621` |
| `session_before_tree` → `:session-before-tree` | `preparation` → `:preparation`; `signal` → `:signal` | `:cancel-p`; `:summary`; `:details`; `:usage`; `:custom-instructions`; `:replace-instructions-p`; `:label` | `packages/coding-agent/src/core/extensions/types.ts:638-643,1117-1130` |
| `session_tree` → `:session-tree` | `newLeafId` → `:new-leaf-id`; `oldLeafId` → `:old-leaf-id`; `summaryEntry?` → `:summary-entry`; `fromExtension?` → `:from-extension-p` | none | `packages/coding-agent/src/core/extensions/types.ts:645-652` |

The exact fields of `CompactionPreparation`'s nested plist:

| Baseline field | Lisp key |
|---|---|
| `firstKeptEntryId` | `:first-kept-entry-id` |
| `messagesToSummarize` | `:messages-to-summarize` |
| `turnPrefixMessages` | `:turn-prefix-messages` |
| `isSplitTurn` | `:split-turn-p` |
| `tokensBefore` | `:tokens-before` |
| `previousSummary?` | `:previous-summary` |
| `fileOps` | `:file-operations` |
| `settings` | `:settings` |

Source:
`packages/coding-agent/src/core/compaction/compaction.ts:688-708`.

The exact fields of `TreePreparation`'s nested plist:

| Baseline field | Lisp key |
|---|---|
| `targetId` | `:target-id` |
| `oldLeafId` | `:old-leaf-id` |
| `commonAncestorId` | `:common-ancestor-id` |
| `entriesToSummarize` | `:entries-to-summarize` |
| `userWantsSummary` | `:user-wants-summary-p` |
| `customInstructions?` | `:custom-instructions` |
| `replaceInstructions?` | `:replace-instructions-p` |
| `label?` | `:label` |

Source: `packages/coding-agent/src/core/extensions/types.ts:623-636`.

The `:compaction` an extension supplies must be a complete compaction result:
`:summary`, `:first-kept-entry-id`, `:tokens-before`,
`:estimated-tokens-after?`, `:usage?`, `:details?`; source
`packages/coding-agent/src/core/compaction/compaction.ts:87-97`.

### 3.2 Agent, message and input lifecycle

| Baseline event → Lisp | payload field (baseline → Lisp) | handler result plist | Fixed baseline |
|---|---|---|---|
| `context` → `:context` | `messages` → `:messages` | `(:messages list)`; chained replacement in handler order | `packages/coding-agent/src/core/extensions/types.ts:669-673,1065-1067` |
| `before_agent_start` → `:before-agent-start` | `prompt` → `:prompt`; `images?` → `:images`; `systemPrompt` → `:system-prompt`; `systemPromptOptions` → `:system-prompt-options` | `:message`; `:system-prompt`, the latter chain-replaced | `packages/coding-agent/src/core/extensions/types.ts:698-709,1097-1101` |
| `agent_start` → `:agent-start` | none | none | `packages/coding-agent/src/core/extensions/types.ts:711-714` |
| `agent_end` → `:agent-end` | `messages` → `:messages` | none | `packages/coding-agent/src/core/extensions/types.ts:716-720` |
| `agent_settled` → `:agent-settled` | none | none | `packages/coding-agent/src/core/extensions/types.ts:722-725` |
| `message_start` → `:message-start` | `message` → `:message` | none | `packages/coding-agent/src/core/extensions/types.ts:742-746` |
| `message_update` → `:message-update` | `message` → `:message`; `assistantMessageEvent` → `:assistant-message-event` | none | `packages/coding-agent/src/core/extensions/types.ts:748-753` |
| `message_end` → `:message-end` | `message` → `:message` | `(:message replacement)`; the replacement's role must not change, and it is chain-replaced in handler order | `packages/coding-agent/src/core/extensions/types.ts:755-759,1092-1095`; runner `:830-870` |
| `input` → `:input` | `text` → `:text`; `images?` → `:images`; `source` → `:source` (`:interactive/:rpc/:extension`); `streamingBehavior?` → `:streaming-behavior` (`:steer/:follow-up`) | `(:action :continue)`; `(:action :transform :text ... :images ...)`; or `(:action :handled)` | `packages/coding-agent/src/core/extensions/types.ts:824-847` |

### 3.3 Tool execution and model lifecycle

| Baseline event → Lisp | payload field (baseline → Lisp) | handler result | Fixed baseline |
|---|---|---|---|
| `tool_execution_start` → `:tool-execution-start` | `toolCallId` → `:tool-call-id`; `toolName` → `:tool-name`; `args` → `:arguments` | none | `packages/coding-agent/src/core/extensions/types.ts:761-767` |
| `tool_execution_update` → `:tool-execution-update` | as above; `partialResult` → `:partial-result` | none | `packages/coding-agent/src/core/extensions/types.ts:769-776` |
| `tool_execution_end` → `:tool-execution-end` | `toolCallId`, `toolName`; `result` → `:result`; `isError` → `:error-p` | none | `packages/coding-agent/src/core/extensions/types.ts:778-785` |
| `model_select` → `:model-select` | `model` → `:model`; `previousModel` → `:previous-model`; `source` → `:source` (`:set/:cycle/:restore`) | none | `packages/coding-agent/src/core/extensions/types.ts:791-799` |
| `thinking_level_select` → `:thinking-level-select` | `level` → `:level`; `previousLevel` → `:previous-level` | none | `packages/coding-agent/src/core/extensions/types.ts:801-806` |

These add observation events only; they do not modify provider or tool
execution semantics. Tool interception/result rewriting continues to go through
the existing `:tool-call-before` / `:tool-call-after`, whose corresponding
references are
`packages/coding-agent/src/core/extensions/types.ts:853-912,1071-1075` and
`:914-973,1085-1090` respectively.

The audit commit also has the following extension events, but this proposal
explicitly does not add them:

| Event not added | Reason | Fixed baseline |
|---|---|---|
| `project_trust` | The security model has nothing to do with this Wave | `packages/coding-agent/src/core/extensions/types.ts:519-541` |
| `resources_discover` | The resource/skill ecosystem is not in this bounded unfreeze | `packages/coding-agent/src/core/extensions/types.ts:543-555` |
| `before_provider_request`, `before_provider_headers`, `after_provider_response` | The provider layer stays frozen | `packages/coding-agent/src/core/extensions/types.ts:675-696` |
| `user_bash` | Tool semantics stay frozen | `packages/coding-agent/src/core/extensions/types.ts:808-821,1077-1083` |

## 4. RPC extension UI surface

### 4.1 Lisp context functions

The existing function signature is unchanged:

```lisp
(extension-context-notify context message &key (level :info))
```

The following public functions are added, and only these:

```lisp
(extension-context-select
 context title options &key signal timeout-ms)
  ; => string | nil

(extension-context-confirm
 context title message &key signal timeout-ms)
  ; => boolean

(extension-context-input
 context title &key placeholder signal timeout-ms)
  ; => string | nil

(extension-context-editor
 context title &key prefill)
  ; => string | nil

(extension-context-set-status context key text)
  ; text=nil clears

(extension-context-set-widget
 context key lines &key (placement :above-editor))
  ; lines is list/vector of strings or nil

(extension-context-set-title context title)

(extension-context-set-editor-text context text)
```

The baseline dialog signatures and options:
`packages/coding-agent/src/core/extensions/types.ts:95-100,131-142`; the
status/widget/title/editor surface: `:147-170,192-193,215-222`.

No `onTerminalInput`, working indicator, custom component, footer/header,
paste, autocomplete, custom editor, theme or tool-expansion API is added; they
are not inside the RPC extension UI wire union, and they would cross the TUI
freeze.

### 4.2 RPC JSONL wire

The wire field names and values keep the reference verbatim and are not
Lisp-ified:

In the table below, `rpc-types.ts` and `rpc-mode.ts` refer to
`packages/coding-agent/src/modes/rpc/rpc-types.ts` and
`packages/coding-agent/src/modes/rpc/rpc-mode.ts` respectively.

| Lisp call | stdout request | stdin response/default | Fixed baseline |
|---|---|---|---|
| `extension-context-select` | `{"type":"extension_ui_request","id", "method":"select","title","options","timeout"?}` | `{"type":"extension_ui_response","id","value"}` or `cancelled:true`→`nil` | `rpc-types.ts:238-240,280-283`; `rpc-mode.ts:135-139` |
| `extension-context-confirm` | method `confirm`, `title`, `message`, `timeout?` | `confirmed:boolean`; cancel→`nil` | `rpc-types.ts:240,280-283`; `rpc-mode.ts:141-144` |
| `extension-context-input` | method `input`, `title`, `placeholder?`, `timeout?` | `value` or cancel→`nil` | `rpc-types.ts:241-248,280-283`; `rpc-mode.ts:146-149` |
| `extension-context-editor` | method `editor`, `title`, `prefill?` | `value` or cancel→`nil` | `rpc-types.ts:249,280-283`; `rpc-mode.ts:253-269` |
| `extension-context-notify` | method `notify`, `message`, `notifyType?` | fire-and-forget | `rpc-types.ts:250-256`; `rpc-mode.ts:151-160` |
| `extension-context-set-status` | method `setStatus`, `statusKey`, `statusText` | fire-and-forget | `rpc-types.ts:257-263`; `rpc-mode.ts:167-176` |
| `extension-context-set-widget` | method `setWidget`, `widgetKey`, `widgetLines`, `widgetPlacement?` | fire-and-forget | `rpc-types.ts:264-271`; `rpc-mode.ts:194-207` |
| `extension-context-set-title` | method `setTitle`, `title` | fire-and-forget | `rpc-types.ts:272`; `rpc-mode.ts:217-225` |
| `extension-context-set-editor-text` | method `set_editor_text`, `text` | fire-and-forget | `rpc-types.ts:273`; `rpc-mode.ts:237-245` |

Every request `id` is unique. A dialog request completes exactly once after a
response, a timeout or a signal abort, and removes the pending entry; reference
state machine:
`packages/coding-agent/src/modes/rpc/rpc-mode.ts:89-130`. The source for the
RPC bind's use of that context is `:312-320` in the same file.

On EOF/close every pending dialog must complete with its own default value and
leave no hanging thread; a late or unknown `extension_ui_response.id` returns
an RPC error and does not affect other requests.

### 4.3 Layering

- `cadr-agent` holds only the UI callback protocol and does not depend on
  `cadr-cli` or `cadr-tui`.
- `cadr-cli`'s RPC bridge is responsible for the request id, the pending map,
  timeout/signal, and the JSONL request/response.
- `cadr-cli`'s TUI glue may only compose existing `cadr-tui` components and the
  overlay API. If any method cannot be implemented without changing
  `cadr-tui`, go blocked again immediately; changing a component along the way
  is not permitted.
- print/JSON has no dialog-capable UI: select/input/editor return `nil`, and
  confirm returns `nil`; the fire-and-forget methods do not write to stdout, so
  as not to contaminate the protocol.

## 5. The backward-compatibility gate

Before implementation, first add a failing test in
`test/cadr-agent/extensions-test.lisp`:

`LEGACY-EXTENSION-SOURCE-REMAINS-COMPATIBLE-AFTER-WAVE-2-API-EXPANSION`.

The test loads an unmodified old-API fixture that registers, at the same time:

- `define-tool`, `define-command`, `define-prompt-template`;
- the four old events of `define-event-hook`;
- the old context accessors and notify/compact/reload;
- replacement, append, tool block/reason, priority and handler error isolation.

It must prove:

1. the original fixture compiles/loads with no modification;
2. the payload, order, chained replacement, append and block results of the
   four old events are exactly the same as at the start-of-work commit
   `14fc6eefeb7e9329a2743ba385cf913060240de2`;
3. `define-event-hook`'s macro lambda list is still
   `(event &key (priority 0) handler)`;
4. every old export is still an external symbol; only the exports listed in
   this document may be added;
5. an old event returning a plist still raises the original error, and a new
   event returning an `extension-hook-result` likewise raises an
   event-specific type error, preventing the two contracts from silently
   crossing wires.

At the same time, cover for each newly added event at least the payload, the
legal results, illegal fields/types and handler failure isolation; the RPC UI
uses process-level JSONL tests to cover response, cancel, timeout, signal,
unknown id, EOF cleanup and stdout cleanliness.

## 6. What this goal allows to change, and what stays frozen

The extension-related entries move out of the original freeze table into what
this goal allows to change:

| Path/text allowed to change | The only change allowed |
|---|---|
| `src/cadr-agent/extensions.lisp` | This document's events, payloads, cancel signal and UI callback protocol |
| `src/cadr-agent/package.lisp` | Only the public symbols listed in this document are added; old exports are neither deleted nor changed |
| `test/cadr-agent/extensions-test.lisp` | The new events and the old-API compatibility gate |
| `src/cadr-cli/extensions.lisp` | Only the UI bridge glue |
| `test/cadr-cli/extensions-test.lisp` | Bridge unit tests |
| `src/cadr-cli/modes/rpc/` | The RPC extension UI wire and process tests |
| `cadr-agent.asd`, `cadr-cli.asd` | Only when a new module/test assembly is genuinely needed |

At closeout the expanded API above is re-frozen, recording the per-path Git
object ID, the SHA-256 of the complete export text, the
macroexpansion/signature tests and the wire fixture SHA-256, and
`docs/architecture.md` is updated. After that, "released means stable" resumes.

Stays frozen and must keep the start-of-work object ID:

| Path | object ID |
|---|---|
| `src/cadr-ai` | `e9c5affef2e36db4cdf6f7fc37a20534cd1a661a` |
| `test/cadr-ai` | `e984d714c6e53cb34d89c495939f9d2b3d975fd8` |
| `cadr-ai.asd` | `f99e2708e9ff7e3465824c7ea04bedce9512724c` |
| `src/cadr-tui` | `1a5ba07b17cd3b0c55c8a1ec35a79d1fafda0950` |
| `test/cadr-tui` | `947e63cc73b259ea2b18bfc281b5229a13f9a5d0` |
| `cadr-tui.asd` | `c09f6172c1c186f15c726b2c04b7ea65a4f4214c` |
| `src/cadr-agent/tool.lisp` | `42093b6062ab16cde78f72cb87a878057b7dd131` |
| `test/cadr-agent/tool-loop-test.lisp` | `f44cd198c1fbfab8b7402f457d1ea2a848a9aa74` |
| `src/cadr-cli/tools` | `0ad21371b8ad2e759dacb26202383965a68d5493` |
| `test/cadr-cli/file-tools-test.lisp` | `206bb0416ff53abba10378a873eeffb698162327` |
| `test/cadr-cli/search-tools-test.lisp` | `5ca50cd12f4b1442891c12ee9fa231b24df07a6c` |
| `test/cadr-cli/bash-test.lisp` | `3475ab2a3760afa06928d8748a44e1514d1ac461` |
| `test/cadr-cli/execution-policy-test.lisp` | `19df8cfbae90aa3d2afb44eb01c81939de90a2cc` |

## 7. Approved Wave 2 runtime actions

The user has granted a bounded unfreeze to the following baseline extension
actions as well; the constraints are the same as for the lifecycle/UI
expansion: only capabilities the audit commit already has are added, and the
existing macro signatures and existing event semantics are not changed.

| Approved action | Target files that depend on it directly | Fixed baseline |
|---|---|---|
| runtime `registerProvider` | `agent-session-dynamic-provider.test.ts`, `suite/agent-session-runtime.test.ts`, regressions `2860` | `packages/coding-agent/src/core/extensions/types.ts:1344-1416` |
| runtime `registerTool` | `agent-session-dynamic-tools.test.ts`, `suite/agent-session-runtime.test.ts` | `packages/coding-agent/src/core/extensions/types.ts:1233-1240` |
| `sendMessage` / `sendUserMessage` | `suite/agent-session-queue.test.ts`, regressions `5943` | `packages/coding-agent/src/core/extensions/types.ts:1281-1298` |
| `setSessionName` | regressions `3686`, `5996` | `packages/coding-agent/src/core/extensions/types.ts:1303-1311` |

The new Lisp mappings are fixed as:

```lisp
(define-provider definition &key models)

(extension-context-register-provider context definition &key models)
(extension-context-register-tool context tool)

(extension-context-send-message
 context message &key (trigger-turn-p nil) deliver-as)

(extension-context-send-user-message context content &key deliver-as)
(extension-context-set-session-name context name)
```

`definition` reuses `cadr-ai:provider-definition`, `models` reuses
`cadr-ai:model-metadata`, and `tool` reuses `cadr-ai:tool`; the provider/tool
domain types are not copied. `define-provider` covers only the baseline's
load-time `registerProvider`, and the context functions cover the registrations
that take effect immediately inside a callback. The existing `define-tool`
continues to be callable only during load, and its existing semantics are
unchanged.

`deliver-as` maps exactly to `:steer`, `:follow-up` and `:next-turn`; of these,
`sendUserMessage` accepts only the first two. When it is omitted, idle starts a
turn directly, and while streaming the delivery queue must be given explicitly.
The session name has CR/LF removed before it is written and before the event is
emitted.

Provider registration is stored in each extension host's runtime overlay, and
`cadr-ai`'s global registry is not changed. It may override the currently
active model or append a model visible to the current session; after an
extension reload, the overlay is replaced together with the bundle snapshot.
If implementing this capability requires modifying any frozen object ID under
`src/cadr-ai`, it must go blocked immediately, and that modification must not
be carried out.

## 8. User adjudication

The user has confirmed items 1–7 one by one; the adjudication of item 8 is a
bounded unfreeze of all four groups of actions in section 7.
The backward-compatibility gate must land before the production implementation,
and the Part B→C→D order is unchanged. At goal 7's closeout, the expanded
extension API is re-frozen and the new object/export/wire hashes are recorded.

## 9. Closeout re-freeze

Objects re-frozen:

| Path | Git object ID |
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

The SHA-256 of the complete export text from `#:define-tool` to
`#:make-extension-hook-result` (both ends included):
`cc8e7d180b5007cbf4daa66ff904f8c0714992df646211c232135500efd936e7`.

Compatibility fixture SHA-256:
`e2548662d773edfa21ecfa3b126b2209404a2b27385e6cd48e1f145a41747442`
(`test/fixtures/extensions/legacy-wave2-api.lisp`).

RPC wire/process fixture SHA-256:
`6dc3a25271080a59c3380704044c435a0a20a972c5ba19f32cae2acee2649b10`
(`test/fixtures/rpc-process-client.py`); UI extension fixture SHA-256:
`c1148870a539dd4a24001da74d17f668b6092bf55d41d845319d5439e3df9486`.

The macro signatures and the old event semantics are kept frozen on an ongoing
basis by
`LEGACY-EXTENSION-SOURCE-REMAINS-COMPATIBLE-AFTER-WAVE-2-API-EXPANSION`.
After this, "released means stable" resumes; any further surface expansion
first enters `docs/open-questions.md` and awaits human adjudication.
