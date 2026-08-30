# Goal 22：pi 基线推进至 v0.84.4

> **状态：** 完成（合入 `cadr-migration`，#221，`0755cfd62`）。基线落到 **v0.84.4**。Does not announce Goal 20 complete.
>
> **当前：** `BASELINE` = `b79e4cc83` · `v0.84.4` +0（pi-mono tag `v0.84.4`）  
> **自：** `4e58f324f` · `v0.84.3` +0

## 范围

机械锚点、`enumerate-baseline-diff`、用户可见增量（settings / env / RPC /
extension events / catalog / agent loop），以及全门禁。Goal 20 leftover
pairing 不在本 goal 内恢复燃尽。

## v0.84.3 → v0.84.4 用户可见增量

| 上游能力 | cadr 动作 |
|---|---|
| `Terminal.hyperlinks/images/trueColor` + `CADR_*` env | `settings-terminal-capability-overrides` + `detect-terminal-capabilities` |
| `fullscreenCopyOnSelect` + Ctrl+X | renderer `copy-on-select-p`；settings selector option |
| Word selection `-` `/` | `selection-word-range` joiners |
| RPC `clear_queue` | `rpc-handle-command` |
| `ui_prompt_start` / `ui_prompt_end` | `call-with-extension-ui-prompt` |
| DeepSeek V4 Flash Vision Exp | generated catalog + fixture shard |
| OpenRouter reasoning mapper | `openrouter-thinking-level-map` |
| Compact before post-tool request | `maybe-compact-agent` when `turn > 1` |
| Custom messages during a run | pending queue flushed at `turn_end` / settle |
| Persist default into non-empty scope | `add-persisted-default-to-non-empty-scope` |
| llama.cpp autoload presets | `llama-model-selectable-p` |
| JSONL trailing newline | `repair-unterminated-session-file` |
| Omit `tool_choice` without tools | openai-completions `build-request` |
| Windows `taskkill` System32 path | `kill-process-tree` |
| Node V8 1MiB main-screen chunking | N/A on SBCL (no V8 string-length crash) |
| `https-proxy-agent` bundle export | N/A (Node bundle) |

## 验收

- [x] `BASELINE` 第三列为 `0`，release 为 `v0.84.4`，commit 为 `b79e4cc83…`
- [x] `python3 scripts/baseline-anchor.py check` 绿
- [x] `./scripts/verify.sh` 与 `./scripts/test-cl.sh` 绿
- [x] `CHANGELOG.md` 记录 aligned with pi v0.84.4
- [x] 合入 `cadr-migration`：GitHub #221 → `0755cfd62`

## 源码账本上仍标 missing 的 v0.84.4 文件（不挡 Goal 22 合入）

Goal 22 对齐的是基线锚点与上表用户可见增量。`docs/source-parity.md` 仍有两行 `missing`，不是本合入的验收项：

| 基线文件 | 现状 |
|---|---|
| `packages/coding-agent/src/modes/interactive/components/settings-submenu.ts` | cadr 已有 `/thinking` 选择器（`src/cadr-cli/interactive/selectors/thinking.lisp`），未抽出通用 `SelectSubmenu` 容器 |
| `packages/coding-agent/src/modes/interactive/session-share.ts` | `/share` 已走 gist（`share-session-as-gist`）；Radius `/v1/artifacts` 上传未移植 |
