# Goal 26 v1.3.0 enumeration

Measured 2026-10-20.

```sh
python3 scripts/enumerate-baseline-diff.py \
  16787ad5b2dc748047f314ca1bfe7708f30f54f3 \
  71023aec1546d6d677a65669c5665c0927ce0dd0
```

Named sets with empty added and removed lists are omitted.

| Class | Delta | Notes |
|---|---|---|
| cliFlags | added 1; removed 0 | added: `--no-mcp`; removed: — |
| settingsKeys | added 0; removed 82 | enumerator false-positive likely: settings moved to TypeBox schema (`settings-schema.ts`); re-parse before treating as removals |
| extensionEvents | added 2; removed 1 | added: `mcp_servers_change`, `provider_stream_event`; removed: `before_agent_start` |
| providers | added 5; removed 2 | added: `azure.ts`, `compat-schema.ts`, `model-schema.ts`, `openrouter-api.ts`, `typesafe.ts`; removed: `azure-openai-responses.ts`, `openrouter-images.ts` |
| environmentVariables | added 1; removed 0 | added: `PI_PROGRAM_STATUS`; removed: — |
| themeTokens | added 0; removed 56 | re-parsed 2026-10-21: `THEME_TOKENS` in `theme-tokens.ts` has the same 56 names. The union left `theme.ts`, so the extractor saw removals. cadr `theme.lisp` already has all 56. `pageBg`/`cardBg`/`infoBg` are export colors, not palette tokens |
| extensionTypeFields | added 10; removed 0 | added: `Extension.replaceable`, `Extension.toolRenderers`, `ExtensionActions.getSettings`, `ExtensionContextActions.executeTool`, `ExtensionContextActions.getCallableTools`, `ExtensionRuntimeState.createContext`, `ExtensionRuntimeState.mcpServers`, `ExtensionRuntimeState.pendingVirtualModelRegistrations`, `ExtensionRuntimeState.registerVirtualModel`, `ExtensionRuntimeState.unregisterVirtualModel`; removed: — |
| errorClasses | added 1; removed 1 | added: `McpSignInCancelledError`; removed: `SessionPluginSelectionConflictError` |
| publicApiExportCount | 36 to 44 | |
| files | +464 / -402 / R12 | catch-all path drift; dispositions in `source-dispositions.tsv` |
