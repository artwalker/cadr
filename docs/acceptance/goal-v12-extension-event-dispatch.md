# Goal 12 extension event dispatch audit

The public event set contains 35 events. Declaration and result validation do
not count as implementation: every row below names the production dispatch
site and a test that installs a handler, drives that production path, and
asserts that the handler was called.

| Event | Production dispatch | Handler-called regression |
|---|---|---|
| `:turn-start` | `src/cadr-agent/loop.lisp:714` | `TURN-HOOKS-REWRITE-AND-APPEND-BEFORE-SESSION-PERSISTENCE`, `test/cadr-agent/extensions-test.lisp:881` |
| `:turn-end` | `src/cadr-agent/loop.lisp:744` | `TURN-HOOKS-REWRITE-AND-APPEND-BEFORE-SESSION-PERSISTENCE`, `test/cadr-agent/extensions-test.lisp:881` |
| `:tool-call-before` | `src/cadr-agent/tool.lisp:201` | `TOOL-HOOKS-AFFECT-REAL-EXECUTION-AND-REVALIDATE-REWRITTEN-ARGUMENTS`, `test/cadr-agent/extensions-test.lisp:606` |
| `:tool-call-after` | `src/cadr-agent/loop.lisp:213` | `TOOL-HOOKS-AFFECT-REAL-EXECUTION-AND-REVALIDATE-REWRITTEN-ARGUMENTS`, `test/cadr-agent/extensions-test.lisp:606` |
| `:tool-call-error` | `src/cadr-agent/loop.lisp:324` | `GOAL10-TOOL-CALL-ERROR-HOOK-RETRIES-AT-THE-LIVE-CONDITION-SITE`, `test/cadr-agent/extensions-wave2-test.lisp:1329` |
| `:session-start` | `src/cadr-agent/loop.lisp:69` | `WAVE2-LIFECYCLE-AND-RUNTIME-ACTIONS-DRIVE-THE-REAL-AGENT-LOOP`, `test/cadr-agent/extensions-wave2-test.lisp:930` |
| `:session-info-changed` | `src/cadr-agent/extensions.lisp:2851` | `WAVE2-SEND-MESSAGE-AND-SESSION-NAME-ACTIONS-PERSIST`, `test/cadr-agent/extensions-wave2-test.lisp:1078` |
| `:session-before-switch` | `src/cadr-cli/main.lisp:972` | `NAME-SESSION-NEW-AND-FORK-COMMANDS-MATCH-INTERACTIVE-SEMANTICS`, `test/cadr-cli/session-command-test.lisp:282` |
| `:session-before-fork` | `src/cadr-cli/main.lisp:882` | `NAME-SESSION-NEW-AND-FORK-COMMANDS-MATCH-INTERACTIVE-SEMANTICS`, `test/cadr-cli/session-command-test.lisp:282` |
| `:session-before-compact` | `src/cadr-agent/compaction.lisp:384` | `SESSION-COMPACTION-LIFECYCLE-DISPATCHES-THROUGH-PRODUCTION-PATH`, `test/cadr-agent/extensions-wave2-test.lisp:76` |
| `:session-compact` | `src/cadr-agent/compaction.lisp:851` | `SESSION-COMPACTION-LIFECYCLE-DISPATCHES-THROUGH-PRODUCTION-PATH`, `test/cadr-agent/extensions-wave2-test.lisp:76` |
| `:session-compact-failed` | `src/cadr-agent/compaction.lisp:613` | `G21-SESSION-COMPACT-FAILED-NOTIFIES-EXTENSIONS-ON-AUTO-COMPACTION-FAILURE`, `test/cadr-agent/compaction-test.lisp:355` |
| `:session-shutdown` | `src/cadr-cli/main.lisp:906` | `NAME-SESSION-NEW-AND-FORK-COMMANDS-MATCH-INTERACTIVE-SEMANTICS`, `test/cadr-cli/session-command-test.lisp:282` |
| `:session-before-tree` | `src/cadr-agent/loop.lisp:1111` | `TREE-NAVIGATION-LIFECYCLE-AND-BUSY-GUARD-USE-THE-PRODUCTION-PATH`, `test/cadr-agent/extensions-wave2-test.lisp:1146` |
| `:session-tree` | `src/cadr-agent/loop.lisp:1176` | `TREE-NAVIGATION-LIFECYCLE-AND-BUSY-GUARD-USE-THE-PRODUCTION-PATH`, `test/cadr-agent/extensions-wave2-test.lisp:1146` |
| `:context` | `src/cadr-agent/loop.lisp:626` | `WAVE2-LIFECYCLE-AND-RUNTIME-ACTIONS-DRIVE-THE-REAL-AGENT-LOOP`, `test/cadr-agent/extensions-wave2-test.lisp:930` |
| `:before-agent-start` | `src/cadr-agent/loop.lisp:1273` | `WAVE2-LIFECYCLE-AND-RUNTIME-ACTIONS-DRIVE-THE-REAL-AGENT-LOOP`, `test/cadr-agent/extensions-wave2-test.lisp:930` |
| `:agent-start` | `src/cadr-agent/loop.lisp:898` | `WAVE2-LIFECYCLE-AND-RUNTIME-ACTIONS-DRIVE-THE-REAL-AGENT-LOOP`, `test/cadr-agent/extensions-wave2-test.lisp:930` |
| `:agent-end` | `src/cadr-agent/loop.lisp:767` | `WAVE2-LIFECYCLE-AND-RUNTIME-ACTIONS-DRIVE-THE-REAL-AGENT-LOOP`, `test/cadr-agent/extensions-wave2-test.lisp:930` |
| `:agent-settled` | `src/cadr-agent/loop.lisp:1053` | `WAVE2-LIFECYCLE-AND-RUNTIME-ACTIONS-DRIVE-THE-REAL-AGENT-LOOP`, `test/cadr-agent/extensions-wave2-test.lisp:930` |
| `:message-start` | `src/cadr-agent/loop.lisp:87` | `WAVE2-LIFECYCLE-AND-RUNTIME-ACTIONS-DRIVE-THE-REAL-AGENT-LOOP`, `test/cadr-agent/extensions-wave2-test.lisp:930` |
| `:message-update` | `src/cadr-agent/loop.lisp:95` | `WAVE2-LIFECYCLE-AND-RUNTIME-ACTIONS-DRIVE-THE-REAL-AGENT-LOOP`, `test/cadr-agent/extensions-wave2-test.lisp:930` |
| `:message-end` | `src/cadr-agent/loop.lisp:81` | `WAVE2-LIFECYCLE-AND-RUNTIME-ACTIONS-DRIVE-THE-REAL-AGENT-LOOP`, `test/cadr-agent/extensions-wave2-test.lisp:930` |
| `:input` | `src/cadr-agent/loop.lisp:1233` | `WAVE2-LIFECYCLE-AND-RUNTIME-ACTIONS-DRIVE-THE-REAL-AGENT-LOOP`, `test/cadr-agent/extensions-wave2-test.lisp:930` |
| `:tool-execution-start` | `src/cadr-agent/loop.lisp:504,603` | `GOAL12-TOOL-PARTIAL-UPDATES-ARE-SCOPED-ORDERED-AND-NOT-PERSISTED`, `test/cadr-agent/tool-loop-test.lisp:652` |
| `:tool-execution-update` | `src/cadr-agent/loop.lisp:195` | `GOAL12-TOOL-PARTIAL-UPDATES-ARE-SCOPED-ORDERED-AND-NOT-PERSISTED`, `test/cadr-agent/tool-loop-test.lisp:652` |
| `:tool-execution-end` | `src/cadr-agent/loop.lisp:178` | `GOAL12-TOOL-PARTIAL-UPDATES-ARE-SCOPED-ORDERED-AND-NOT-PERSISTED`, `test/cadr-agent/tool-loop-test.lisp:652` |
| `:model-select` | `src/cadr-cli/main.lisp:770` | `REGISTRY-MODEL-CONFIG-AND-SELECTION-UPDATE-THE-COMPLETE-RUNTIME-SURFACE`, `test/cadr-cli/part-b-models-test.lisp:529` |
| `:thinking-level-select` | `src/cadr-cli/main.lisp:1719` | `REGISTRY-MODEL-CONFIG-AND-SELECTION-UPDATE-THE-COMPLETE-RUNTIME-SURFACE`, `test/cadr-cli/part-b-models-test.lisp:529` |
| `:project-trust` | `src/cadr-cli/settings.lisp:734` | `WAVE3-STARTUP-RESOURCE-TRUST-AND-USER-BASH-HOOKS-ARE-WIRED`, `test/cadr-cli/extensions-test.lisp:592` |
| `:resources-discover` | `src/cadr-cli/resource-loader.lisp:161` | `WAVE3-STARTUP-RESOURCE-TRUST-AND-USER-BASH-HOOKS-ARE-WIRED`, `test/cadr-cli/extensions-test.lisp:592` |
| `:before-provider-request` | `src/cadr-cli/sdk-services.lisp:600` | `PROVIDER-LIFECYCLE-EXTENSION-HOOKS-RUN-ON-THE-REAL-STREAM-SURFACE`, `test/cadr-cli/part-b-sdk-test.lisp:397` |
| `:before-provider-headers` | `src/cadr-cli/sdk-services.lisp:623` | `PROVIDER-LIFECYCLE-EXTENSION-HOOKS-RUN-ON-THE-REAL-STREAM-SURFACE`, `test/cadr-cli/part-b-sdk-test.lisp:397` |
| `:after-provider-response` | `src/cadr-cli/sdk-services.lisp:633` | `PROVIDER-LIFECYCLE-EXTENSION-HOOKS-RUN-ON-THE-REAL-STREAM-SURFACE`, `test/cadr-cli/part-b-sdk-test.lisp:397` |
| `:user-bash` | `src/cadr-cli/tools/bash.lisp:384` | `WAVE3-STARTUP-RESOURCE-TRUST-AND-USER-BASH-HOOKS-ARE-WIRED`, `test/cadr-cli/extensions-test.lisp:592` |

The audit found one declared-but-disconnected event:
`:session-before-compact`. Its result validator and merge path existed, but the
production compaction path never emitted it. F connects both before/after events
for manual, threshold, and overflow compaction. No other disconnected event was
found. The grouped tests use one explicit membership assertion per event, so a
declared event without a production dispatch now fails instead of passing on
return-value validation alone.
