# render-diff core 分诊

日期：2026-10-23。对照钉在上游 v1.4.0，检出 `/root/projects/pi-v1.4.0`。cadr 侧是 `origin/goal27-parity`。
没有改 `/root/projects/pi-mono`，也没有改 cadr 的产品行为。

## 版本号规范化

版本号和产品名同一类。cadr 显示自己的版本是对的。`scripts/render-diff.py` 的 `normalize_product_versions` 在两边都把产品自己的发行号换成 `v<VERSION>`。
上游令牌是 `v1.4.0`。cadr 令牌从 `version.sexp` 读，当前是 `v0.2.0`。令牌必须是 `v` 加上这一整段点分版本，后面不能再跟数字或点。
`v0.84.3`、`v1.4.1`、`v1.4.00`、`v0.2.1`、不带 `v` 的 `1.4.0` 和 `0.2.0`、`128k`、`fd-v10.2.0` 都保持原样。
替换发生在 tmux 回放之后，和产品名替换同一阶段。logo 行是 `▀▀█ v1.4.0`，旁边没有产品名，所以这条规则不要求产品名挨着版本号。
规则写在 `scripts/render-diff.py` 和 `docs/render-diff.md`。`test/render-diff-gate-test.py` 的 `test_product_version_tokens_normalize_on_both_sides_only` 锁住两边都会替换，其他数字不动。

## 重跑

规范化在回放之后，所以用已经录下的 core 原始流再做语义比较，没有重新开 PTY。原始流目录是 `/tmp/cadr-render-gate-g27b`，上游仓库是 `/root/projects/pi-v1.4.0`。
比较过的屏是 399。`screenEqual` 通过 0。去掉行尾空白后可见文字相同的是 7。这 7 屏的字节仍不同，差在产品名长度带来的行尾补空。
399 屏的可见文字里已经没有 `v1.4.0` 或 `v0.2.0`。
另有 22 个场景维度没有成对原始流，没有进入这 399。名单在下面。

## 对照脚本改了什么

`normalize_fixed_values` 先调用 `normalize_product_versions`。原先只认贴在产品名旁边的 `v0.84.3` 和 `v0.2.0`，logo 上的 `v1.4.0` 漏掉。
产品名标题的样式替换改成匹配 `v<VERSION>`，这样版本替换之后标题仍能收成 `<PRODUCT> v<VERSION>`。
没有放宽别的替换。`~/.pi` 与 `~/.cadr`、调试日志文件名、changelog 地址仍交给已有的 I04 记录，不在脚本里抹掉。

## (b) 对照工具

版本号这一项已经按上面的规则改完。
下面几项是等待文本在上游自己的最终画面里不出现，所以两边都没有原始流。这次没有改等待字符串。改等待字符串要重新录屏才能知道检查点变了没有。

- `commands-informational/wide` 与 `commands-informational/narrow`。上游等待 `What's New` 超时。超时尾部是 changelog 正文，标题已经滚出视口。
- `selector-scoped-state-sweep/narrow`。上游等待 `Model catalogs refreshed.` 超时。同场景宽屏有原始流，归在选择器状态标记那一组。
- `example-snake/narrow`。上游等待 `GAME OVER` 超时。同场景宽屏有原始流。

## (c) 已经记过的差异

这些不进入 GAP 表。出处是现有记录，不是新的差异类。

### 可见文字相同，只剩产品名长度带来的行尾空白

`test/fixtures/render-diff/disposition-class-rules.json` 的 `I01-I04-text-geometry-equal`。`screenEqual` 仍是假，因为 `Pi` 与 `Cadr` 换进同一个 `<PRODUCT>` 之后行尾补空不同。

共 7 屏。

- `autocomplete-surfaces/narrow/autocomplete-slash`
- `commands-empty-lifecycle/wide/process-exit`
- `overlays-logout/narrow/logout-provider`
- `startup-existing/narrow/existing-session`
- `startup-first/narrow/process-exit`
- `startup-first/wide/process-exit`
- `stream-interrupt-queue/narrow/busy-queue`

### 配置路径 ~/.pi 与 ~/.cadr

`test/fixtures/render-diff/dispositions.json` 里 startup-resources 与 config-selector 的记录，写明 `~/.pi/agent` 到 `~/.cadr/agent` 是 I04。`startup-untrusted` 的 `Project .pi` 与 `Project .cadr` 是同一替换。

共 27 屏。

- `config-selector-empty/narrow/config-empty`
- `config-selector-empty/narrow/process-exit`
- `config-selector-empty/wide/config-empty`
- `config-selector-empty/wide/process-exit`
- `config-selector-state-sweep/narrow/config-global-initial`
- `config-selector-state-sweep/narrow/config-global-rechecked`
- `config-selector-state-sweep/narrow/config-global-unchecked`
- `config-selector-state-sweep/narrow/config-project-initial`
- `config-selector-state-sweep/narrow/config-project-load`
- `config-selector-state-sweep/narrow/config-project-unload`
- `config-selector-state-sweep/narrow/process-exit`
- `config-selector-state-sweep/wide/config-global-initial`
- `config-selector-state-sweep/wide/config-global-rechecked`
- `config-selector-state-sweep/wide/config-global-unchecked`
- `config-selector-state-sweep/wide/config-project-initial`
- `config-selector-state-sweep/wide/config-project-load`
- `config-selector-state-sweep/wide/config-project-unload`
- `config-selector-state-sweep/wide/process-exit`
- `startup-resources/narrow/process-exit`
- `startup-resources/narrow/startup-resources-compact`
- `startup-resources/narrow/startup-resources-expanded`
- `startup-resources/wide/process-exit`
- `startup-resources/wide/startup-resources-compact`
- `startup-resources/wide/startup-resources-expanded`
- `startup-untrusted/narrow/process-exit`
- `startup-untrusted/narrow/trust-untrusted-saved`
- `startup-untrusted/narrow/untrusted-startup`

### 调试日志文件名 pi-debug.log 与 cadr-debug.log

`dispositions.json` 的 slash-debug 记录写明文件名是 I04，窄屏换行也由这个更长的路径引起。

共 4 屏。

- `slash-debug/narrow/debug-written`
- `slash-debug/narrow/process-exit`
- `slash-debug/wide/debug-written`
- `slash-debug/wide/process-exit`

### 更新卡片的产品名和 changelog 地址

`dispositions.json` 的 update-notifications 记录写明 `Run cadr update` 和 `github.com/artwalker/cadr` 的 changelog 地址是 I04。窄屏 `update-notifications` 与 `update-notifications-no-hyperlinks` 没有原始流，是因为上游等待 `Update Available` 超时，卡片被这条更长的地址挤出画面。同一条记录已经写了这件事。

共 4 屏。

- `update-notifications-no-hyperlinks/wide/process-exit`
- `update-notifications-no-hyperlinks/wide/version-and-package-updates-no-hyperlinks`
- `update-notifications/wide/process-exit`
- `update-notifications/wide/version-and-package-updates`

### 恢复命令按产品名长度换行

句子是 `To resume this session`。产品名从 `pi` 换成 `cadr` 之后，`--session` 在不同的列断开。这和 update-notifications 记录里更长的产品身份把行挤开是同一件事，不另开 GAP。

共 12 屏。

- `commands-and-exit/narrow/post-exit-resume`
- `commands-and-exit/narrow/process-exit`
- `commands-and-exit/wide/post-exit-resume`
- `commands-and-exit/wide/process-exit`
- `overlays-core/narrow/process-exit`
- `overlays-core/wide/process-exit`
- `selector-state-sweep/narrow/process-exit`
- `selector-state-sweep/wide/process-exit`
- `startup-existing/narrow/post-exit-resume`
- `startup-existing/narrow/process-exit`
- `startup-existing/wide/post-exit-resume`
- `startup-existing/wide/process-exit`

### 信任结果句里的产品名

画面是 `Restart pi` 与 `Restart cadr`。产品名是 I04。`startup-untrusted/narrow/untrusted-startup` 同时有 `Project .pi` 与 `Project .cadr`，归在配置路径那一组。

共 4 屏。

- `startup-untrusted/narrow/process-exit`
- `startup-untrusted/narrow/trust-untrusted-saved`
- `startup-untrusted/wide/process-exit`
- `startup-untrusted/wide/trust-untrusted-saved`

## (a) 根因

一屏可以落在多组里。GAP 编号从 65 起，一组一行。

### GAP-65 视口顶对齐，页脚不钉在最后一行

类别 (a)。上游出处 `packages/coding-agent/src/modes/interactive/interactive-mode.ts` `createChatViewport`。

上游把对话文档放进滚动视口，页脚挂在最后一行（`interactive-mode.ts` 970-981 行）。cadr `src/cadr-cli/interactive/frame.lisp` 296-302 行把页脚 `nconc` 在编辑器后面。内容不满一屏时，分隔线、工作目录和 token 行停在中部，下面是空行。内容超过一屏时，窄屏从 logo 第二行画起，首行 `▀▀█ v<VERSION>` 不在画面里。示例场景里上游视口底部的 `[Extensions]` 文件名，cadr 换成了开头的 `Press ctrl+o` 帮助。抽样屏 `commands-empty-lifecycle/wide/slash-compact` 与 `autocomplete-surfaces/narrow/autocomplete-path`。

共 194 屏。

- `autocomplete-surfaces/narrow/autocomplete-path`
- `autocomplete-surfaces/wide/autocomplete-path`
- `autocomplete-surfaces/wide/autocomplete-slash`
- `commands-and-exit/narrow/slash-export`
- `commands-and-exit/narrow/slash-reload`
- `commands-and-exit/wide/slash-export`
- `commands-and-exit/wide/slash-reload`
- `commands-empty-lifecycle/narrow/process-exit`
- `commands-empty-lifecycle/narrow/slash-compact`
- `commands-empty-lifecycle/narrow/slash-copy`
- `commands-empty-lifecycle/narrow/slash-import`
- `commands-empty-lifecycle/narrow/slash-new`
- `commands-empty-lifecycle/wide/slash-compact`
- `commands-empty-lifecycle/wide/slash-copy`
- `commands-empty-lifecycle/wide/slash-import`
- `commands-empty-lifecycle/wide/slash-new`
- `compaction-status-manual/narrow/compaction-manual`
- `compaction-status-manual/wide/compaction-manual`
- `compaction-status-overflow/narrow/compaction-overflow`
- `compaction-status-overflow/wide/compaction-overflow`
- `compaction-status-threshold/narrow/compaction-threshold`
- `compaction-status-threshold/wide/compaction-threshold`
- `conversation-content/wide/plain`
- `conversation-mermaid/wide/mermaid-absent`
- `conversation-mermaid/wide/mermaid-rendered`
- `example-bookmark/narrow/bookmark-labeled`
- `example-bookmark/narrow/process-exit`
- `example-bookmark/wide/bookmark-labeled`
- `example-bookmark/wide/process-exit`
- `example-commands/narrow/commands-list`
- `example-commands/narrow/commands-path`
- `example-commands/narrow/process-exit`
- `example-commands/wide/commands-list`
- `example-commands/wide/commands-path`
- `example-commands/wide/process-exit`
- `example-custom-footer/narrow/footer-off`
- `example-custom-footer/narrow/footer-on`
- `example-custom-footer/narrow/process-exit`
- `example-custom-footer/wide/footer-off`
- `example-custom-footer/wide/footer-on`
- `example-custom-footer/wide/process-exit`
- `example-custom-header/narrow/header-off`
- `example-custom-header/narrow/header-on`
- `example-custom-header/narrow/process-exit`
- `example-custom-header/wide/header-off`
- `example-custom-header/wide/header-on`
- `example-custom-header/wide/process-exit`
- `example-dynamic-tools/narrow/add-echo`
- `example-dynamic-tools/narrow/echo-session`
- `example-dynamic-tools/narrow/process-exit`
- `example-dynamic-tools/wide/add-echo`
- `example-dynamic-tools/wide/echo-session`
- `example-dynamic-tools/wide/process-exit`
- `example-entry-renderer/narrow/process-exit`
- `example-entry-renderer/narrow/status-card`
- `example-entry-renderer/wide/process-exit`
- `example-entry-renderer/wide/status-card`
- `example-event-bus/narrow/event-bus-emit`
- `example-event-bus/narrow/event-bus-startup`
- `example-event-bus/narrow/process-exit`
- `example-event-bus/wide/event-bus-emit`
- `example-event-bus/wide/event-bus-startup`
- `example-event-bus/wide/process-exit`
- `example-hello/narrow/hello-result`
- `example-hello/narrow/process-exit`
- `example-hello/wide/hello-result`
- `example-hello/wide/process-exit`
- `example-message-renderer/narrow/process-exit`
- `example-message-renderer/narrow/status-message`
- `example-message-renderer/wide/process-exit`
- `example-message-renderer/wide/status-message`
- `example-notify/narrow/notify-ready`
- `example-notify/narrow/process-exit`
- `example-notify/wide/notify-ready`
- `example-notify/wide/process-exit`
- `example-overlay-test/wide/overlay-open`
- `example-overlay-test/wide/overlay-search`
- `example-overlay-test/wide/process-exit`
- `example-pirate/narrow/pirate-on`
- `example-pirate/narrow/process-exit`
- `example-pirate/wide/pirate-on`
- `example-pirate/wide/process-exit`
- `example-qna/narrow/process-exit`
- `example-qna/narrow/qna-empty`
- `example-qna/wide/process-exit`
- `example-qna/wide/qna-empty`
- `example-reload-runtime/wide/process-exit`
- `example-reload-runtime/wide/reload-queued`
- `example-send-user-message/narrow/ask-turn`
- `example-send-user-message/narrow/ask-usage`
- `example-send-user-message/narrow/process-exit`
- `example-send-user-message/wide/ask-turn`
- `example-send-user-message/wide/ask-usage`
- `example-send-user-message/wide/process-exit`
- `example-session-name/narrow/process-exit`
- `example-session-name/narrow/session-named`
- `example-session-name/wide/process-exit`
- `example-session-name/wide/session-named`
- `example-snake/wide/process-exit`
- `example-snake/wide/snake-initial`
- `example-snake/wide/snake-moved`
- `example-snake/wide/snake-over`
- `example-space-invaders/wide/process-exit`
- `example-thinking-label/narrow/process-exit`
- `example-thinking-label/narrow/thinking-label-set`
- `example-thinking-label/wide/process-exit`
- `example-thinking-label/wide/thinking-label-set`
- `example-tic-tac-toe/narrow/process-exit`
- `example-tic-tac-toe/wide/process-exit`
- `example-tic-tac-toe/wide/ttt-cursor`
- `example-tic-tac-toe/wide/ttt-initial`
- `example-todo/narrow/process-exit`
- `example-todo/narrow/todo-added`
- `example-todo/narrow/todos-empty`
- `example-todo/wide/process-exit`
- `example-todo/wide/todo-added`
- `example-todo/wide/todos-empty`
- `example-tools/narrow/process-exit`
- `example-tools/narrow/tools-selector`
- `example-tools/wide/process-exit`
- `example-tools/wide/tools-selector`
- `example-trigger-compact/narrow/compact-started`
- `example-trigger-compact/narrow/process-exit`
- `example-trigger-compact/wide/compact-started`
- `example-trigger-compact/wide/process-exit`
- `extension-surfaces/narrow/extension-editor`
- `extension-surfaces/narrow/extension-input`
- `extension-surfaces/narrow/extension-select`
- `extension-surfaces/wide/extension-editor`
- `extension-surfaces/wide/extension-input`
- `extension-surfaces/wide/extension-select`
- `overlays-auth/wide/auth-method-generic`
- `overlays-auth/wide/login-provider`
- `overlays-core/narrow/overlay-fork`
- `overlays-core/narrow/overlay-session`
- `overlays-core/narrow/overlay-session-delete`
- `overlays-core/narrow/overlay-session-rename`
- `overlays-core/narrow/overlay-thinking`
- `overlays-core/narrow/overlay-tree`
- `overlays-core/narrow/overlay-tree-label`
- `overlays-core/wide/overlay-fork`
- `overlays-core/wide/overlay-model`
- `overlays-core/wide/overlay-scoped-models`
- `overlays-core/wide/overlay-session`
- `overlays-core/wide/overlay-session-delete`
- `overlays-core/wide/overlay-session-rename`
- `overlays-core/wide/overlay-thinking`
- `overlays-core/wide/overlay-tree`
- `overlays-core/wide/overlay-tree-initial`
- `overlays-core/wide/overlay-tree-label`
- `overlays-core/wide/overlay-trust`
- `overlays-core/wide/process-exit`
- `overlays-logout/wide/logout-provider`
- `provider-error/wide/provider-error`
- `selector-state-sweep/narrow/model-closed`
- `selector-state-sweep/narrow/settings-image-width-row`
- `selector-state-sweep/wide/model-closed`
- `selector-state-sweep/wide/model-first-screen`
- `selector-state-sweep/wide/process-exit`
- `selector-state-sweep/wide/resume-first-screen`
- `selector-state-sweep/wide/resume-row-01`
- `selector-state-sweep/wide/resume-row-02`
- `selector-state-sweep/wide/resume-row-03`
- `selector-state-sweep/wide/resume-row-04`
- `selector-state-sweep/wide/resume-row-05`
- `selector-state-sweep/wide/resume-row-06`
- `selector-state-sweep/wide/resume-row-07`
- `selector-state-sweep/wide/resume-scrolled`
- `selector-state-sweep/wide/settings-auto-resize-row`
- `selector-state-sweep/wide/settings-image-rows`
- `selector-state-sweep/wide/settings-image-width-row`
- `selector-state-sweep/wide/trust-trusted`
- `selector-trust-inherited/wide/trust-inherited-from-parent`
- `slash-debug/wide/debug-written`
- `startup-existing/wide/existing-session`
- `startup-first/narrow/startup`
- `startup-first/wide/startup`
- `startup-resources/narrow/process-exit`
- `startup-resources/narrow/startup-resources-compact`
- `startup-resources/narrow/startup-resources-expanded`
- `startup-resources/wide/process-exit`
- `startup-resources/wide/startup-resources-compact`
- `startup-resources/wide/startup-resources-expanded`
- `startup-untrusted/narrow/trust-untrusted-saved`
- `startup-untrusted/wide/trust-untrusted`
- `startup-untrusted/wide/trust-untrusted-saved`
- `startup-untrusted/wide/untrusted-startup`
- `stream-interrupt-queue/wide/busy-queue`
- `stream-interrupt-queue/wide/stream-aborted`
- `tools-failure/wide/tool-failure`
- `tools-success/narrow/tree-rich-tools`
- `tools-success/wide/bash-multiline`
- `update-notifications-no-hyperlinks/wide/version-and-package-updates-no-hyperlinks`
- `update-notifications/wide/version-and-package-updates`

### GAP-66 faux 用量估算使页脚 token 数字不同

类别 (a)。上游出处 `packages/ai/src/providers/faux.ts` `estimateTokens`。

两边页脚格式相同。`footer.ts` 的 `formatTokens`（25-31 行）和 `src/cadr-tui/components/status.lisp` 的 `format-footer-tokens`（12-28 行）都是小于 1000 写原数、小于 10000 写一位小数 k。数字不同是因为估算不同。上游 `faux.ts` `estimateTokens`（158-160 行）用 `Math.ceil(text.length / 4)`。cadr `src/cadr-ai/support/token-estimation.lisp` 16-19 行用 `ceiling(chars * 2 / 7)`，`src/cadr-ai/runtime/faux-provider.lisp` 的 `faux-with-usage`（317-320 行）先把上下文序列化再估算。场景本身不带 usage 对象。抽样屏 `tools-success/wide/grep`，上游 `↑1.5k ↓87`，cadr `↑234 ↓100`。

共 105 屏。

- `autocomplete-surfaces/narrow/process-exit`
- `autocomplete-surfaces/wide/process-exit`
- `conversation-content/narrow/cjk-emoji`
- `conversation-content/narrow/markdown-code-thinking`
- `conversation-content/narrow/plain`
- `conversation-content/narrow/process-exit`
- `conversation-content/wide/cjk-emoji`
- `conversation-content/wide/markdown-code-thinking`
- `conversation-content/wide/process-exit`
- `conversation-mermaid/narrow/mermaid-absent`
- `conversation-mermaid/narrow/mermaid-fallback`
- `conversation-mermaid/narrow/mermaid-rendered`
- `conversation-mermaid/narrow/process-exit`
- `conversation-mermaid/wide/mermaid-fallback`
- `conversation-mermaid/wide/process-exit`
- `example-bookmark/narrow/bookmark-labeled`
- `example-bookmark/narrow/process-exit`
- `example-bookmark/wide/process-exit`
- `example-hello/narrow/hello-result`
- `example-hello/narrow/process-exit`
- `example-hello/wide/process-exit`
- `example-notify/narrow/notify-ready`
- `example-notify/narrow/process-exit`
- `example-notify/wide/process-exit`
- `example-reload-runtime/narrow/process-exit`
- `example-reload-runtime/narrow/reload-queued`
- `example-reload-runtime/wide/process-exit`
- `example-reload-runtime/wide/reload-queued`
- `example-send-user-message/narrow/ask-turn`
- `example-send-user-message/narrow/process-exit`
- `example-send-user-message/wide/process-exit`
- `example-tic-tac-toe/narrow/process-exit`
- `example-tic-tac-toe/wide/process-exit`
- `example-tic-tac-toe/wide/ttt-played`
- `example-todo/narrow/process-exit`
- `example-todo/narrow/todo-added`
- `example-todo/wide/process-exit`
- `extension-surfaces/narrow/process-exit`
- `extension-surfaces/wide/process-exit`
- `overlays-auth/narrow/process-exit`
- `overlays-auth/wide/process-exit`
- `overlays-core/narrow/process-exit`
- `overlays-core/wide/process-exit`
- `overlays-logout/narrow/process-exit`
- `overlays-logout/wide/process-exit`
- `provider-error/narrow/process-exit`
- `provider-error/narrow/provider-error`
- `provider-error/wide/process-exit`
- `selector-scoped-state-sweep/wide/process-exit`
- `selector-state-sweep/narrow/process-exit`
- `selector-state-sweep/wide/process-exit`
- `selector-trust-inherited/narrow/process-exit`
- `selector-trust-inherited/wide/process-exit`
- `stream-interrupt-queue/narrow/process-exit`
- `stream-interrupt-queue/narrow/stream-aborted`
- `stream-interrupt-queue/wide/process-exit`
- `tools-failure/narrow/bash-nonzero`
- `tools-failure/narrow/bash-timeout`
- `tools-failure/narrow/process-exit`
- `tools-failure/narrow/tool-failure`
- `tools-failure/wide/bash-nonzero`
- `tools-failure/wide/bash-timeout`
- `tools-failure/wide/process-exit`
- `tools-significant-states/narrow/bash-byte-limit`
- `tools-significant-states/narrow/bash-empty`
- `tools-significant-states/narrow/bash-line-limit`
- `tools-significant-states/narrow/bash-overlong-line`
- `tools-significant-states/narrow/find-invalid-arguments`
- `tools-significant-states/narrow/grep-invalid-arguments`
- `tools-significant-states/narrow/parallel-tool-calls`
- `tools-significant-states/narrow/process-exit`
- `tools-significant-states/narrow/tool-invalid-arguments`
- `tools-significant-states/wide/bash-byte-limit`
- `tools-significant-states/wide/bash-empty`
- `tools-significant-states/wide/bash-line-limit`
- `tools-significant-states/wide/bash-overlong-line`
- `tools-significant-states/wide/find-invalid-arguments`
- `tools-significant-states/wide/grep-invalid-arguments`
- `tools-significant-states/wide/parallel-tool-calls`
- `tools-significant-states/wide/process-exit`
- `tools-significant-states/wide/tool-invalid-arguments`
- `tools-success/narrow/bash-long-command`
- `tools-success/narrow/bash-multiline`
- `tools-success/narrow/edit`
- `tools-success/narrow/find`
- `tools-success/narrow/find-default-path`
- `tools-success/narrow/grep`
- `tools-success/narrow/grep-default-path`
- `tools-success/narrow/ls`
- `tools-success/narrow/process-exit`
- `tools-success/narrow/read-offset-without-limit`
- `tools-success/narrow/read-range`
- `tools-success/narrow/write`
- `tools-success/wide/bash-long-command`
- `tools-success/wide/edit`
- `tools-success/wide/find`
- `tools-success/wide/find-default-path`
- `tools-success/wide/grep`
- `tools-success/wide/grep-default-path`
- `tools-success/wide/ls`
- `tools-success/wide/process-exit`
- `tools-success/wide/read-offset-without-limit`
- `tools-success/wide/read-range`
- `tools-success/wide/tree-rich-tools`
- `tools-success/wide/write`

### GAP-67 选择器状态标记写在标签后面

类别 (a)。上游出处 `packages/coding-agent/src/modes/interactive/components/scoped-models-selector.ts` `updateList`。

上游在模型 id 前面放 `✓ ` 或两个空格（`scoped-models-selector.ts` 256 行），信任菜单同样在标签前放 `✓ ` 或两个空格（`trust-selector.ts` 110-113 行）。cadr `src/cadr-cli/interactive/selectors/models.lisp` 536-538 行把 ` ✓` 接在 id 后面，`scoped-models-check-success`（1397-1400 行）是后缀，未启用画 ` ✗`（1402 行起）。`src/cadr-cli/interactive/selectors/trust.lisp` 337-345 行只在已保存时把勾接在标签后面，未保存不留那两格，所以 `→   Trust` 变成 `→ Trust`。模型行因此少两格缩进。抽样屏 `overlays-core/wide/overlay-scoped-models` 与 `overlays-core/narrow/overlay-trust`。

共 43 屏。

- `overlays-core/narrow/overlay-model`
- `overlays-core/narrow/overlay-scoped-models`
- `overlays-core/narrow/overlay-trust`
- `overlays-core/wide/overlay-model`
- `overlays-core/wide/overlay-scoped-models`
- `overlays-core/wide/overlay-trust`
- `selector-scoped-state-sweep/wide/scoped-after-head`
- `selector-scoped-state-sweep/wide/scoped-first-screen`
- `selector-scoped-state-sweep/wide/scoped-head-01`
- `selector-scoped-state-sweep/wide/scoped-head-02`
- `selector-scoped-state-sweep/wide/scoped-last-screen`
- `selector-scoped-state-sweep/wide/scoped-tail-01`
- `selector-scoped-state-sweep/wide/scoped-tail-02`
- `selector-scoped-state-sweep/wide/scoped-tail-03`
- `selector-scoped-state-sweep/wide/scoped-tail-04`
- `selector-scoped-state-sweep/wide/scoped-tail-05`
- `selector-scoped-state-sweep/wide/scoped-tail-06`
- `selector-scoped-state-sweep/wide/scoped-tail-07`
- `selector-scoped-state-sweep/wide/scoped-tail-08`
- `selector-scoped-state-sweep/wide/scoped-tail-09`
- `selector-scoped-state-sweep/wide/scoped-tail-10`
- `selector-state-sweep/narrow/model-first-screen`
- `selector-state-sweep/narrow/model-row-01`
- `selector-state-sweep/narrow/model-row-02`
- `selector-state-sweep/narrow/model-row-03`
- `selector-state-sweep/narrow/model-row-04`
- `selector-state-sweep/narrow/model-row-05`
- `selector-state-sweep/wide/model-first-screen`
- `selector-state-sweep/wide/model-row-01`
- `selector-state-sweep/wide/model-row-02`
- `selector-state-sweep/wide/model-row-03`
- `selector-state-sweep/wide/model-row-04`
- `selector-state-sweep/wide/model-row-05`
- `selector-state-sweep/wide/model-row-06`
- `selector-state-sweep/wide/model-row-07`
- `selector-state-sweep/wide/model-row-08`
- `selector-state-sweep/wide/model-row-09`
- `selector-state-sweep/wide/model-row-10`
- `selector-state-sweep/wide/model-row-11`
- `selector-state-sweep/wide/model-row-12`
- `selector-state-sweep/wide/model-scrolled`
- `startup-untrusted/narrow/trust-untrusted`
- `startup-untrusted/wide/trust-untrusted`

### GAP-68 模型选择器热键提示保持小写

类别 (a)。上游出处 `packages/coding-agent/src/modes/interactive/components/keybinding-hints.ts` `keyDisplayText`。

上游 `keyDisplayText`（38-39 行）把热键首字母大写，画面是 `Ctrl+S`。cadr `src/cadr-cli/interactive/selectors/models.lisp` 的 `scoped-models-session-line`（1421-1430 行）直接写入 `save-label`，画面是 `ctrl+s`。抽样屏 `overlays-core/wide/overlay-scoped-models`。

共 18 屏。

- `overlays-core/narrow/overlay-scoped-models`
- `overlays-core/wide/overlay-scoped-models`
- `selector-scoped-state-sweep/wide/scoped-after-head`
- `selector-scoped-state-sweep/wide/scoped-first-screen`
- `selector-scoped-state-sweep/wide/scoped-head-01`
- `selector-scoped-state-sweep/wide/scoped-head-02`
- `selector-scoped-state-sweep/wide/scoped-last-screen`
- `selector-scoped-state-sweep/wide/scoped-tail-01`
- `selector-scoped-state-sweep/wide/scoped-tail-02`
- `selector-scoped-state-sweep/wide/scoped-tail-03`
- `selector-scoped-state-sweep/wide/scoped-tail-04`
- `selector-scoped-state-sweep/wide/scoped-tail-05`
- `selector-scoped-state-sweep/wide/scoped-tail-06`
- `selector-scoped-state-sweep/wide/scoped-tail-07`
- `selector-scoped-state-sweep/wide/scoped-tail-08`
- `selector-scoped-state-sweep/wide/scoped-tail-09`
- `selector-scoped-state-sweep/wide/scoped-tail-10`
- `selector-state-sweep/wide/process-exit`

### GAP-69 todo 确认行不是成功勾号

类别 (a)。上游出处 `packages/coding-agent/examples/extensions/todo.ts`。

上游 `todo.ts` 262 行把添加结果画成 `✓ Added #1 first`。cadr `examples/extensions/todo.lisp` 86 行把工具返回画成 `Added todo #1: first`。抽样屏 `example-todo/wide/todo-added`。

共 4 屏。

- `example-todo/narrow/process-exit`
- `example-todo/narrow/todo-added`
- `example-todo/wide/process-exit`
- `example-todo/wide/todo-added`

### GAP-70 压缩状态行在结束帧仍留在画面上

类别 (a)。上游出处 `packages/coding-agent/src/modes/interactive/components/status-indicator.ts`。

上游结束帧是一条普通分隔线。cadr 仍画 `── ⠋ Compacting context... (escape to cancel) ──`。上游文案在 `status-indicator.ts` 90 行，cadr 在 `src/cadr-cli/interactive/tool-rendering.lisp` 508 行。抽样屏 `compaction-status-manual/wide/process-exit`。

共 7 屏。

- `compaction-status-manual/narrow/process-exit`
- `compaction-status-manual/wide/process-exit`
- `compaction-status-overflow/narrow/compaction-overflow`
- `compaction-status-overflow/narrow/process-exit`
- `compaction-status-overflow/wide/process-exit`
- `compaction-status-threshold/narrow/process-exit`
- `compaction-status-threshold/wide/process-exit`

### GAP-71 设置项标签和数值之间的空格比上游少

类别 (a)。上游出处 `packages/coding-agent/src/modes/interactive/components/settings-selector.ts`。

设置名和 true、false、数字相同，cadr 数值前的空格更少。`src/cadr-cli/interactive/selectors/settings.lisp` 1105-1124 行把标签列宽限制在 12 到 32，再用这个宽度补空格。抽样屏 `overlays-core/wide/overlay-settings`。

共 8 屏。

- `overlays-core/narrow/overlay-settings`
- `overlays-core/wide/overlay-settings`
- `selector-state-sweep/narrow/settings-auto-resize-row`
- `selector-state-sweep/narrow/settings-image-rows`
- `selector-state-sweep/narrow/settings-image-width-row`
- `selector-state-sweep/wide/settings-auto-resize-row`
- `selector-state-sweep/wide/settings-image-rows`
- `selector-state-sweep/wide/settings-image-width-row`

### GAP-72 崩溃页文案

类别 (a)。上游出处 `packages/coding-agent/src/modes/interactive/interactive-mode.ts` `uncaughtCrash`。

上游 `interactive-mode.ts` 4339 行打印 `<PRODUCT> exiting due to uncaughtException:`，后面是驱动栈。cadr `src/cadr-ai/crash.lisp` 194-198 行打印 `cadr exiting due to uncaught SIMPLE-ERROR`，并写出 crash log 路径。抽样屏 `fatal-crash/wide/fatal-crash`。

共 4 屏。

- `fatal-crash/narrow/fatal-crash`
- `fatal-crash/narrow/process-exit`
- `fatal-crash/wide/fatal-crash`
- `fatal-crash/wide/process-exit`

### GAP-73 space invaders 敌机字形

类别 (a)。上游出处 `packages/coding-agent/examples/extensions/space-invaders.ts`。

上游三种敌机是 `▼`、`◆`、`☆`，左右翼是 `╲╱`、`╱╲`、`◄►`（`space-invaders.ts` 432-435 行）。cadr `examples/extensions/space-invaders.lisp` 328 行把中心画成 `◆`，左右画成 `╱` 和 `╲`。标题行的标点也不同。抽样屏 `example-space-invaders/wide/invaders-initial`。

共 4 屏。

- `example-space-invaders/wide/invaders-initial`
- `example-space-invaders/wide/invaders-left`
- `example-space-invaders/wide/invaders-right`
- `example-space-invaders/wide/process-exit`

### GAP-74 tic-tac-toe 棋盘上方的标题和帮助行

类别 (a)。上游出处 `packages/coding-agent/examples/extensions/tic-tac-toe.ts`。

上游轮次行在 `tic-tac-toe.ts` 473-475 行，窄屏把标题、轮次和帮助分开，页脚在最后一行。cadr `examples/extensions/tic-tac-toe.lisp` 403-407 行拼轮次，窄屏上帮助行和页脚挤在棋盘中部。抽样屏 `example-tic-tac-toe/narrow/ttt-initial`。

共 8 屏。

- `example-tic-tac-toe/narrow/process-exit`
- `example-tic-tac-toe/narrow/ttt-cursor`
- `example-tic-tac-toe/narrow/ttt-initial`
- `example-tic-tac-toe/narrow/ttt-played`
- `example-tic-tac-toe/wide/process-exit`
- `example-tic-tac-toe/wide/ttt-cursor`
- `example-tic-tac-toe/wide/ttt-initial`
- `example-tic-tac-toe/wide/ttt-played`

### GAP-75 登录名单状态写成 unconfigured

类别 (a)。上游出处 `packages/coding-agent/src/modes/interactive/components/oauth-selector.ts`。

上游 `oauth-selector.ts` 37 行写 `• not configured`。cadr `src/cadr-cli/interactive/selectors/auth.lisp` 570 行写 `• unconfigured`。提供方名字相同。抽样屏 `overlays-auth/narrow/login-provider`。

共 4 屏。

- `overlays-auth/narrow/auth-method-generic`
- `overlays-auth/narrow/login-provider`
- `overlays-auth/wide/auth-method-generic`
- `overlays-auth/wide/login-provider`

### GAP-76 会话树多出预览为 [nil] 的一行

类别 (a)。上游出处 `packages/coding-agent/src/modes/interactive/components/tree-selector.ts`。

上游选中行是助手回复，计数 `(2/2)`。cadr `src/cadr-cli/interactive/selectors/tree.lisp` 在路径标记 `• `（1564-1568 行）后面多一行，预览文本是 `[nil]`，计数变成 `(3/3)`。抽样屏 `overlays-core/narrow/overlay-tree-initial`。

共 4 屏。

- `overlays-core/narrow/overlay-tree`
- `overlays-core/narrow/overlay-tree-initial`
- `overlays-core/wide/overlay-tree`
- `overlays-core/wide/overlay-tree-initial`

### GAP-77 恢复会话列表把空会话的消息数写成 1

类别 (a)。上游出处 `packages/coding-agent/src/core/session-manager.ts` `messageCount`。

两边都显示 `(no messages)`。上游 `session-manager.ts` 833-834 行只给 `type === message` 的行加一。cadr `src/cadr-cli/interactive/selectors/sessions.lisp` 414 行用 `(length messages)`，同一行显示 `1` 而不是 `0`。抽样屏 `selector-state-sweep/narrow/resume-first-screen`。

共 18 屏。

- `selector-state-sweep/narrow/resume-first-screen`
- `selector-state-sweep/narrow/resume-row-01`
- `selector-state-sweep/narrow/resume-row-02`
- `selector-state-sweep/narrow/resume-row-03`
- `selector-state-sweep/narrow/resume-row-04`
- `selector-state-sweep/narrow/resume-row-05`
- `selector-state-sweep/narrow/resume-row-06`
- `selector-state-sweep/narrow/resume-row-07`
- `selector-state-sweep/narrow/resume-scrolled`
- `selector-state-sweep/wide/resume-first-screen`
- `selector-state-sweep/wide/resume-row-01`
- `selector-state-sweep/wide/resume-row-02`
- `selector-state-sweep/wide/resume-row-03`
- `selector-state-sweep/wide/resume-row-04`
- `selector-state-sweep/wide/resume-row-05`
- `selector-state-sweep/wide/resume-row-06`
- `selector-state-sweep/wide/resume-row-07`
- `selector-state-sweep/wide/resume-scrolled`

### GAP-78 确认登录提供方后没有停在认证方式选择器

类别 (a)。上游出处 `packages/coding-agent/src/modes/interactive/interactive-mode.ts` `handleLoginCommand`。

这 12 个场景维度没有 cadr 原始流。`/tmp/cadr-render-gate-g27-failures.txt` 里 cadr 第 6 步等待 `Select authentication method for Render Auth:` 超时。超时画面停在提供方列表，`render-auth` 高亮后回到页脚。cadr `src/cadr-cli/interactive/selectors/auth.lisp` 108 行有这句标题，但确认提供方后没有把它留在画面上。上游 `handleLoginCommand`（5824 行起）在同一提供方有多种方式时打开方式选择器。

共 12 屏。

- `overlays-auth-api-key/narrow`
- `overlays-auth-api-key/wide`
- `overlays-auth-browser-callback/narrow`
- `overlays-auth-browser-callback/wide`
- `overlays-auth-browser-callback-complete/narrow`
- `overlays-auth-browser-callback-complete/wide`
- `overlays-auth-device-code/narrow`
- `overlays-auth-device-code/wide`
- `overlays-auth-manual-code-complete/narrow`
- `overlays-auth-manual-code-complete/wide`
- `overlays-auth-oauth/narrow`
- `overlays-auth-oauth/wide`

### GAP-79 主题流程没有停在 Automatic Theme 子页

类别 (a)。上游出处 `packages/coding-agent/src/modes/interactive/components/settings-selector.ts` `showAutomaticMenu`。

这两个维度没有 cadr 原始流。失败记录里等待 `Automatic Theme` 超时。超时画面是主题列表，第一项是 `Automatic`，随后选中 `system` 并回到设置。上游 `settings-selector.ts` 340 行把子页标题画成 `Automatic Theme`。cadr `src/cadr-cli/interactive/selectors/settings.lisp` 1174 行有同一标题，453 行的列表标签只有 `Automatic`。捕获结束时画面上没有子页标题。

共 2 屏。

- `overlays-secondary/narrow`
- `overlays-secondary/wide`

### GAP-80 tic-tac-toe-agent 没有写出 Placed O

类别 (a)。上游出处 `packages/coding-agent/examples/extensions/tic-tac-toe.ts` `Placed O`。

宽屏 cadr 等待 `Placed O at (0,0)` 超时。失败尾部先是类型错误 `Wanted one of (CADR-AI:SYSTEM-MESSAGE ...)`，然后棋盘中心是 `╳`，下面是 `Agent is thinking...`。上游 `tic-tac-toe.ts` 925 行在落子后返回 `Placed O at ...`。窄屏是上游等待同一句超时，两边都没有原始流。

共 2 屏。

- `example-tic-tac-toe-agent/narrow`
- `example-tic-tac-toe-agent/wide`

## 没有成对原始流的 22 个场景维度

- `commands-informational/narrow/MISSING`
- `commands-informational/wide/MISSING`
- `example-snake/narrow/MISSING`
- `example-tic-tac-toe-agent/narrow/MISSING`
- `example-tic-tac-toe-agent/wide/MISSING`
- `overlays-auth-api-key/narrow/MISSING`
- `overlays-auth-api-key/wide/MISSING`
- `overlays-auth-browser-callback-complete/narrow/MISSING`
- `overlays-auth-browser-callback-complete/wide/MISSING`
- `overlays-auth-browser-callback/narrow/MISSING`
- `overlays-auth-browser-callback/wide/MISSING`
- `overlays-auth-device-code/narrow/MISSING`
- `overlays-auth-device-code/wide/MISSING`
- `overlays-auth-manual-code-complete/narrow/MISSING`
- `overlays-auth-manual-code-complete/wide/MISSING`
- `overlays-auth-oauth/narrow/MISSING`
- `overlays-auth-oauth/wide/MISSING`
- `overlays-secondary/narrow/MISSING`
- `overlays-secondary/wide/MISSING`
- `selector-scoped-state-sweep/narrow/MISSING`
- `update-notifications-no-hyperlinks/narrow/MISSING`
- `update-notifications/narrow/MISSING`

其中登录 12 个、主题 2 个、tic-tac-toe-agent 2 个写在上面的 (a) 组。更新通知窄屏 2 个写在 (c)。其余 4 个写在 (b)。
## 2026-10-24 复查

干净检出先停在 `dfec3b192`，按 `docs/render-diff.md` 跑 core。`commands-informational` 等场景在上游等待超时后官方 gate 退出，其余场景用同一条 `render-diff.py capture` 补完。设置子菜单的提交 `126d8c244` 在录屏期间进入 `origin/goal27-parity`，`overlays-secondary` 与 `selector-state-sweep` 在这个提交上重录。这两次之间只动了设置选择器，重录后的可见文字差别和第一次相同。

成对检查点 465。`screenEqual` 通过 43。通过屏是：

- `example-space-invaders/wide/invaders-initial`
- `example-space-invaders/wide/invaders-left`
- `example-space-invaders/wide/invaders-right`
- `tools-success/narrow/tree-rich-tools`
- `selector-state-sweep/narrow/model-row-01`
- `selector-state-sweep/narrow/model-row-02`
- `selector-state-sweep/narrow/model-row-03`
- `selector-state-sweep/narrow/model-row-04`
- `selector-state-sweep/narrow/model-row-05`
- `selector-state-sweep/narrow/model-row-06`
- `selector-state-sweep/narrow/model-row-07`
- `selector-state-sweep/narrow/model-row-08`
- `selector-state-sweep/narrow/model-row-09`
- `selector-state-sweep/narrow/model-row-10`
- `selector-state-sweep/narrow/model-row-11`
- `selector-state-sweep/narrow/model-row-12`
- `selector-state-sweep/narrow/model-scrolled`
- `selector-state-sweep/narrow/resume-first-screen`
- `selector-state-sweep/narrow/resume-row-01`
- `selector-state-sweep/narrow/resume-row-02`
- `selector-state-sweep/narrow/resume-row-03`
- `selector-state-sweep/narrow/resume-row-04`
- `selector-state-sweep/narrow/resume-row-05`
- `selector-state-sweep/narrow/resume-row-06`
- `selector-state-sweep/narrow/resume-row-07`
- `selector-state-sweep/narrow/resume-scrolled`
- `selector-state-sweep/narrow/settings-image-rows`
- `selector-state-sweep/narrow/settings-image-width-row`
- `selector-state-sweep/narrow/settings-auto-resize-row`
- `selector-state-sweep/narrow/trust-trusted`
- `overlays-core/narrow/overlay-tree-initial`
- `overlays-core/narrow/overlay-scoped-models`
- `overlays-core/narrow/overlay-session-delete`
- `overlays-core/narrow/overlay-fork`
- `overlays-core/narrow/overlay-tree`
- `overlays-core/narrow/overlay-tree-label`
- `overlays-core/narrow/overlay-settings`
- `overlays-core/narrow/overlay-trust`
- `overlays-auth/narrow/login-provider`
- `overlays-secondary/narrow/settings-theme-automatic`
- `overlays-secondary/narrow/settings-theme-light`
- `overlays-secondary/narrow/settings-theme-dark`
- `example-tic-tac-toe/narrow/ttt-played`

没有成对原始流的维度 7 个。失败都在上游一侧。

- `commands-informational/wide`、`commands-informational/narrow`。上游等待 `What's New` 超时。和上次的 (b) 相同。
- `update-notifications/narrow`、`update-notifications-no-hyperlinks/narrow`。上游等待 `Update Available` 超时。和上次 (c) 里更长的 changelog 地址把卡片挤出窄屏相同。
- `selector-scoped-state-sweep/narrow`。上游等待 `Model catalogs refreshed.` 超时。和上次的 (b) 相同。
- `example-snake/narrow`。上游等待 `GAME OVER` 超时。和上次的 (b) 相同。
- `example-tic-tac-toe-agent/narrow`。上游等待 `Placed O at (0,0)` 超时。GAP-80 已写明窄屏这句在视口外，上游同样等不到。

### GAP-71

设置项间距没有剩余屏。主列表、主题页和思考级别子页的可见文字与上游一致。这一行保持 `done`，不改。

### 已通过的行仍不完整

GAP-65 改回 `open`。共 129 屏。页脚和正文仍不在上游的行上。

- `startup-resources/wide/startup-resources-compact`
- `startup-resources/wide/startup-resources-expanded`
- `startup-resources/wide/process-exit`
- `overlays-auth-oauth/wide/login-post-cancel`
- `overlays-auth-oauth/wide/process-exit`
- `overlays-auth-device-code/wide/login-device-post-cancel`
- `overlays-auth-device-code/wide/process-exit`
- `overlays-auth-api-key/wide/api-key-post-cancel`
- `overlays-auth-api-key/wide/process-exit`
- `overlays-auth-browser-callback/wide/login-loopback-post-cancel`
- `overlays-auth-browser-callback/wide/process-exit`
- `extension-surfaces/wide/extension-select`
- `provider-error/wide/process-exit`
- `fatal-crash/wide/fatal-crash`
- `fatal-crash/wide/process-exit`
- `example-snake/wide/snake-initial`
- `example-snake/wide/snake-moved`
- `example-snake/wide/snake-over`
- `example-snake/wide/process-exit`
- `example-tic-tac-toe/wide/ttt-initial`
- `example-tic-tac-toe/wide/ttt-cursor`
- `example-tic-tac-toe/wide/process-exit`
- `example-tic-tac-toe-agent/wide/process-exit`
- `example-space-invaders/wide/process-exit`
- `example-hello/wide/hello-result`
- `example-hello/wide/process-exit`
- `example-notify/wide/notify-ready`
- `example-notify/wide/process-exit`
- `example-session-name/wide/session-named`
- `example-session-name/wide/process-exit`
- `example-pirate/wide/pirate-on`
- `example-pirate/wide/process-exit`
- `example-bookmark/wide/bookmark-labeled`
- `example-bookmark/wide/process-exit`
- `example-commands/wide/commands-list`
- `example-commands/wide/commands-path`
- `example-commands/wide/process-exit`
- `example-custom-header/wide/header-on`
- `example-custom-header/wide/header-off`
- `example-custom-header/wide/process-exit`
- `example-custom-footer/wide/footer-on`
- `example-custom-footer/wide/footer-off`
- `example-custom-footer/wide/process-exit`
- `example-overlay-test/wide/overlay-open`
- `example-overlay-test/wide/overlay-search`
- `example-overlay-test/wide/process-exit`
- `example-event-bus/wide/event-bus-startup`
- `example-event-bus/wide/event-bus-emit`
- `example-event-bus/wide/process-exit`
- `example-send-user-message/wide/ask-usage`
- `example-send-user-message/wide/ask-turn`
- `example-send-user-message/wide/process-exit`
- `example-trigger-compact/wide/compact-started`
- `example-trigger-compact/wide/process-exit`
- `example-reload-runtime/wide/reload-queued`
- `example-reload-runtime/wide/process-exit`
- `example-thinking-label/wide/thinking-label-set`
- `example-thinking-label/wide/process-exit`
- `example-message-renderer/wide/status-message`
- `example-message-renderer/wide/process-exit`
- `example-entry-renderer/wide/status-card`
- `example-entry-renderer/wide/process-exit`
- `example-dynamic-tools/wide/echo-session`
- `example-dynamic-tools/wide/add-echo`
- `example-dynamic-tools/wide/process-exit`
- `example-tools/wide/tools-selector`
- `example-tools/wide/process-exit`
- `example-todo/wide/todos-empty`
- `example-todo/wide/todo-added`
- `example-todo/wide/process-exit`
- `example-qna/wide/qna-empty`
- `example-qna/wide/process-exit`
- `startup-untrusted/narrow/trust-untrusted-saved`
- `startup-untrusted/narrow/process-exit`
- `startup-resources/narrow/startup-resources-compact`
- `startup-resources/narrow/startup-resources-expanded`
- `startup-resources/narrow/process-exit`
- `selector-state-sweep/narrow/model-first-screen`
- `overlays-core/narrow/overlay-model`
- `overlays-core/narrow/overlay-thinking`
- `extension-surfaces/narrow/extension-select`
- `provider-error/narrow/provider-error`
- `provider-error/narrow/process-exit`
- `fatal-crash/narrow/fatal-crash`
- `fatal-crash/narrow/process-exit`
- `example-tic-tac-toe/narrow/process-exit`
- `example-hello/narrow/hello-result`
- `example-hello/narrow/process-exit`
- `example-notify/narrow/notify-ready`
- `example-notify/narrow/process-exit`
- `example-session-name/narrow/session-named`
- `example-session-name/narrow/process-exit`
- `example-pirate/narrow/pirate-on`
- `example-pirate/narrow/process-exit`
- `example-bookmark/narrow/bookmark-labeled`
- `example-bookmark/narrow/process-exit`
- `example-commands/narrow/commands-list`
- `example-commands/narrow/commands-path`
- `example-commands/narrow/process-exit`
- `example-custom-header/narrow/header-on`
- `example-custom-header/narrow/header-off`
- `example-custom-header/narrow/process-exit`
- `example-custom-footer/narrow/footer-on`
- `example-custom-footer/narrow/footer-off`
- `example-custom-footer/narrow/process-exit`
- `example-event-bus/narrow/event-bus-startup`
- `example-event-bus/narrow/event-bus-emit`
- `example-event-bus/narrow/process-exit`
- `example-send-user-message/narrow/ask-usage`
- `example-send-user-message/narrow/ask-turn`
- `example-send-user-message/narrow/process-exit`
- `example-trigger-compact/narrow/compact-started`
- `example-trigger-compact/narrow/process-exit`
- `example-thinking-label/narrow/thinking-label-set`
- `example-thinking-label/narrow/process-exit`
- `example-message-renderer/narrow/status-message`
- `example-message-renderer/narrow/process-exit`
- `example-entry-renderer/narrow/status-card`
- `example-entry-renderer/narrow/process-exit`
- `example-dynamic-tools/narrow/echo-session`
- `example-dynamic-tools/narrow/add-echo`
- `example-dynamic-tools/narrow/process-exit`
- `example-tools/narrow/tools-selector`
- `example-tools/narrow/process-exit`
- `example-todo/narrow/todos-empty`
- `example-todo/narrow/todo-added`
- `example-todo/narrow/process-exit`
- `example-qna/narrow/qna-empty`
- `example-qna/narrow/process-exit`

GAP-66 改回 `open`。共 127 屏。页脚 token 数字仍偏小。

- `conversation-content/wide/plain`
- `conversation-content/wide/markdown-code-thinking`
- `conversation-content/wide/cjk-emoji`
- `conversation-content/wide/process-exit`
- `conversation-mermaid/wide/mermaid-absent`
- `conversation-mermaid/wide/mermaid-rendered`
- `conversation-mermaid/wide/mermaid-fallback`
- `conversation-mermaid/wide/process-exit`
- `tools-success/wide/bash-multiline`
- `tools-success/wide/read-range`
- `tools-success/wide/write`
- `tools-success/wide/edit`
- `tools-success/wide/grep`
- `tools-success/wide/find`
- `tools-success/wide/ls`
- `tools-success/wide/read-offset-without-limit`
- `tools-success/wide/grep-default-path`
- `tools-success/wide/find-default-path`
- `tools-success/wide/bash-long-command`
- `tools-success/wide/tree-rich-tools`
- `tools-success/wide/process-exit`
- `tools-failure/wide/tool-failure`
- `tools-failure/wide/bash-nonzero`
- `tools-failure/wide/bash-timeout`
- `tools-failure/wide/process-exit`
- `tools-significant-states/wide/bash-line-limit`
- `tools-significant-states/wide/bash-byte-limit`
- `tools-significant-states/wide/bash-overlong-line`
- `tools-significant-states/wide/bash-empty`
- `tools-significant-states/wide/tool-invalid-arguments`
- `tools-significant-states/wide/grep-invalid-arguments`
- `tools-significant-states/wide/find-invalid-arguments`
- `tools-significant-states/wide/parallel-tool-calls`
- `tools-significant-states/wide/process-exit`
- `selector-state-sweep/wide/process-exit`
- `selector-scoped-state-sweep/wide/process-exit`
- `selector-trust-inherited/wide/process-exit`
- `overlays-core/wide/process-exit`
- `overlays-auth/wide/process-exit`
- `overlays-auth-manual-code-complete/wide/login-manual-post-complete`
- `overlays-auth-manual-code-complete/wide/process-exit`
- `overlays-auth-browser-callback-complete/wide/login-loopback-post-complete`
- `overlays-auth-browser-callback-complete/wide/process-exit`
- `overlays-logout/wide/process-exit`
- `overlays-secondary/wide/process-exit`
- `stream-interrupt-queue/wide/stream-aborted`
- `stream-interrupt-queue/wide/process-exit`
- `extension-surfaces/wide/process-exit`
- `autocomplete-surfaces/wide/process-exit`
- `provider-error/wide/provider-error`
- `example-tic-tac-toe/wide/ttt-played`
- `example-tic-tac-toe-agent/wide/ttt-agent-repaint`
- `example-hello/wide/hello-result`
- `example-notify/wide/notify-ready`
- `example-bookmark/wide/bookmark-labeled`
- `example-send-user-message/wide/ask-turn`
- `example-todo/wide/todo-added`
- `conversation-content/narrow/plain`
- `conversation-content/narrow/markdown-code-thinking`
- `conversation-content/narrow/cjk-emoji`
- `conversation-content/narrow/process-exit`
- `conversation-mermaid/narrow/mermaid-absent`
- `conversation-mermaid/narrow/mermaid-rendered`
- `conversation-mermaid/narrow/mermaid-fallback`
- `conversation-mermaid/narrow/process-exit`
- `tools-success/narrow/bash-multiline`
- `tools-success/narrow/read-range`
- `tools-success/narrow/write`
- `tools-success/narrow/edit`
- `tools-success/narrow/grep`
- `tools-success/narrow/find`
- `tools-success/narrow/ls`
- `tools-success/narrow/read-offset-without-limit`
- `tools-success/narrow/grep-default-path`
- `tools-success/narrow/find-default-path`
- `tools-success/narrow/bash-long-command`
- `tools-success/narrow/process-exit`
- `tools-failure/narrow/tool-failure`
- `tools-failure/narrow/bash-nonzero`
- `tools-failure/narrow/bash-timeout`
- `tools-failure/narrow/process-exit`
- `tools-significant-states/narrow/bash-line-limit`
- `tools-significant-states/narrow/bash-byte-limit`
- `tools-significant-states/narrow/bash-overlong-line`
- `tools-significant-states/narrow/bash-empty`
- `tools-significant-states/narrow/tool-invalid-arguments`
- `tools-significant-states/narrow/grep-invalid-arguments`
- `tools-significant-states/narrow/find-invalid-arguments`
- `tools-significant-states/narrow/parallel-tool-calls`
- `tools-significant-states/narrow/process-exit`
- `selector-state-sweep/narrow/process-exit`
- `selector-trust-inherited/narrow/process-exit`
- `overlays-core/narrow/process-exit`
- `overlays-auth/narrow/process-exit`
- `overlays-auth-oauth/narrow/login-post-cancel`
- `overlays-auth-oauth/narrow/process-exit`
- `overlays-auth-device-code/narrow/login-device-post-cancel`
- `overlays-auth-device-code/narrow/process-exit`
- `overlays-auth-api-key/narrow/api-key-post-cancel`
- `overlays-auth-api-key/narrow/process-exit`
- `overlays-auth-browser-callback/narrow/login-loopback-post-cancel`
- `overlays-auth-browser-callback/narrow/process-exit`
- `overlays-auth-manual-code-complete/narrow/login-manual-post-complete`
- `overlays-auth-manual-code-complete/narrow/process-exit`
- `overlays-auth-browser-callback-complete/narrow/login-loopback-post-complete`
- `overlays-auth-browser-callback-complete/narrow/process-exit`
- `overlays-logout/narrow/process-exit`
- `overlays-secondary/narrow/process-exit`
- `stream-interrupt-queue/narrow/stream-aborted`
- `stream-interrupt-queue/narrow/process-exit`
- `extension-surfaces/narrow/process-exit`
- `autocomplete-surfaces/narrow/process-exit`
- `provider-error/narrow/provider-error`
- `provider-error/narrow/process-exit`
- `example-tic-tac-toe/narrow/process-exit`
- `example-hello/narrow/hello-result`
- `example-hello/narrow/process-exit`
- `example-notify/narrow/notify-ready`
- `example-notify/narrow/process-exit`
- `example-bookmark/narrow/bookmark-labeled`
- `example-bookmark/narrow/process-exit`
- `example-send-user-message/narrow/ask-turn`
- `example-send-user-message/narrow/process-exit`
- `example-reload-runtime/narrow/reload-queued`
- `example-reload-runtime/narrow/process-exit`
- `example-todo/narrow/todo-added`
- `example-todo/narrow/process-exit`

### 新根因

GAP-81 扩展输入框把 placeholder 写进初始值。共 2 屏。

- `extension-surfaces/wide/extension-input`
- `extension-surfaces/narrow/extension-input`

GAP-82 登录中止没有显示 `Failed to login`。共 14 屏。

- `overlays-auth-oauth/wide/login-cancelled`
- `overlays-auth-oauth/wide/login-post-cancel`
- `overlays-auth-oauth/wide/process-exit`
- `overlays-auth-device-code/wide/login-device-cancelled`
- `overlays-auth-device-code/wide/login-device-post-cancel`
- `overlays-auth-device-code/wide/process-exit`
- `overlays-auth-api-key/wide/api-key-post-cancel`
- `overlays-auth-api-key/wide/process-exit`
- `overlays-auth-browser-callback/wide/login-loopback-cancelled`
- `overlays-auth-browser-callback/wide/login-loopback-post-cancel`
- `overlays-auth-browser-callback/wide/process-exit`
- `overlays-auth-oauth/narrow/login-cancelled`
- `overlays-auth-device-code/narrow/login-device-cancelled`
- `overlays-auth-browser-callback/narrow/login-loopback-cancelled`

GAP-83 思考级别选择器的勾和循环热键。共 2 屏。窄屏 `overlays-core/narrow/overlay-thinking` 同时有 GAP-65 的一行错位。

- `overlays-core/wide/overlay-thinking`
- `overlays-core/narrow/overlay-thinking`

### 已经记过的差异

这些不改队列。

产品名换成占位符之后的行尾空白，可见文字去掉行尾空格后相同。共 124 屏。

- `startup-first/wide/startup`
- `startup-first/wide/process-exit`
- `startup-existing/wide/existing-session`
- `selector-state-sweep/wide/model-first-screen`
- `selector-state-sweep/wide/model-row-01`
- `selector-state-sweep/wide/model-row-02`
- `selector-state-sweep/wide/model-row-03`
- `selector-state-sweep/wide/model-row-04`
- `selector-state-sweep/wide/model-row-05`
- `selector-state-sweep/wide/model-row-06`
- `selector-state-sweep/wide/model-row-07`
- `selector-state-sweep/wide/model-row-08`
- `selector-state-sweep/wide/model-row-09`
- `selector-state-sweep/wide/model-row-10`
- `selector-state-sweep/wide/model-row-11`
- `selector-state-sweep/wide/model-row-12`
- `selector-state-sweep/wide/model-scrolled`
- `selector-state-sweep/wide/model-closed`
- `selector-state-sweep/wide/resume-first-screen`
- `selector-state-sweep/wide/resume-row-01`
- `selector-state-sweep/wide/resume-row-02`
- `selector-state-sweep/wide/resume-row-03`
- `selector-state-sweep/wide/resume-row-04`
- `selector-state-sweep/wide/resume-row-05`
- `selector-state-sweep/wide/resume-row-06`
- `selector-state-sweep/wide/resume-row-07`
- `selector-state-sweep/wide/resume-scrolled`
- `selector-state-sweep/wide/settings-image-rows`
- `selector-state-sweep/wide/settings-image-width-row`
- `selector-state-sweep/wide/settings-auto-resize-row`
- `selector-state-sweep/wide/trust-trusted`
- `selector-scoped-state-sweep/wide/scoped-first-screen`
- `selector-scoped-state-sweep/wide/scoped-head-01`
- `selector-scoped-state-sweep/wide/scoped-head-02`
- `selector-scoped-state-sweep/wide/scoped-after-head`
- `selector-scoped-state-sweep/wide/scoped-tail-01`
- `selector-scoped-state-sweep/wide/scoped-tail-02`
- `selector-scoped-state-sweep/wide/scoped-tail-03`
- `selector-scoped-state-sweep/wide/scoped-tail-04`
- `selector-scoped-state-sweep/wide/scoped-tail-05`
- `selector-scoped-state-sweep/wide/scoped-tail-06`
- `selector-scoped-state-sweep/wide/scoped-tail-07`
- `selector-scoped-state-sweep/wide/scoped-tail-08`
- `selector-scoped-state-sweep/wide/scoped-tail-09`
- `selector-scoped-state-sweep/wide/scoped-tail-10`
- `selector-scoped-state-sweep/wide/scoped-last-screen`
- `selector-trust-inherited/wide/trust-inherited-from-parent`
- `overlays-core/wide/overlay-model`
- `overlays-core/wide/overlay-tree-initial`
- `overlays-core/wide/overlay-scoped-models`
- `overlays-core/wide/overlay-session-rename`
- `overlays-core/wide/overlay-session-delete`
- `overlays-core/wide/overlay-fork`
- `overlays-core/wide/overlay-tree`
- `overlays-core/wide/overlay-tree-label`
- `overlays-core/wide/overlay-settings`
- `overlays-core/wide/overlay-trust`
- `overlays-auth/wide/auth-method-generic`
- `overlays-auth/wide/login-provider`
- `overlays-auth-oauth/wide/auth-method-provider`
- `overlays-auth-oauth/wide/login-dialog`
- `overlays-auth-device-code/wide/login-device-code`
- `overlays-auth-api-key/wide/api-key-input`
- `overlays-auth-browser-callback/wide/login-loopback-dialog`
- `overlays-auth-manual-code-complete/wide/login-manual-dialog`
- `overlays-auth-manual-code-complete/wide/login-manual-completed`
- `overlays-auth-browser-callback-complete/wide/login-loopback-dialog`
- `overlays-auth-browser-callback-complete/wide/login-loopback-completed`
- `overlays-logout/wide/logout-provider`
- `overlays-secondary/wide/settings-warnings`
- `overlays-secondary/wide/settings-thinking`
- `overlays-secondary/wide/settings-theme`
- `overlays-secondary/wide/settings-theme-automatic`
- `overlays-secondary/wide/settings-theme-light`
- `overlays-secondary/wide/settings-theme-dark`
- `overlays-secondary/wide/import-confirmation`
- `stream-interrupt-queue/wide/busy-queue`
- `extension-surfaces/wide/extension-editor`
- `autocomplete-surfaces/wide/autocomplete-slash`
- `autocomplete-surfaces/wide/autocomplete-path`
- `commands-and-exit/wide/slash-export`
- `commands-and-exit/wide/slash-reload`
- `commands-empty-lifecycle/wide/slash-copy`
- `commands-empty-lifecycle/wide/slash-compact`
- `commands-empty-lifecycle/wide/slash-import`
- `commands-empty-lifecycle/wide/slash-new`
- `commands-empty-lifecycle/wide/process-exit`
- `compaction-status-manual/wide/process-exit`
- `compaction-status-threshold/wide/process-exit`
- `compaction-status-overflow/wide/process-exit`
- `startup-first/narrow/startup`
- `startup-first/narrow/process-exit`
- `startup-existing/narrow/existing-session`
- `startup-untrusted/narrow/trust-untrusted`
- `selector-state-sweep/narrow/model-closed`
- `selector-trust-inherited/narrow/trust-inherited-from-parent`
- `overlays-core/narrow/overlay-session-rename`
- `overlays-auth/narrow/auth-method-generic`
- `overlays-auth-oauth/narrow/auth-method-provider`
- `overlays-auth-oauth/narrow/login-dialog`
- `overlays-auth-device-code/narrow/login-device-code`
- `overlays-auth-api-key/narrow/api-key-input`
- `overlays-auth-browser-callback/narrow/login-loopback-dialog`
- `overlays-auth-manual-code-complete/narrow/login-manual-dialog`
- `overlays-auth-browser-callback-complete/narrow/login-loopback-dialog`
- `overlays-logout/narrow/logout-provider`
- `overlays-secondary/narrow/settings-warnings`
- `overlays-secondary/narrow/settings-thinking`
- `overlays-secondary/narrow/settings-theme`
- `overlays-secondary/narrow/import-confirmation`
- `stream-interrupt-queue/narrow/busy-queue`
- `extension-surfaces/narrow/extension-editor`
- `autocomplete-surfaces/narrow/autocomplete-slash`
- `autocomplete-surfaces/narrow/autocomplete-path`
- `commands-and-exit/narrow/slash-reload`
- `commands-empty-lifecycle/narrow/slash-copy`
- `commands-empty-lifecycle/narrow/slash-compact`
- `commands-empty-lifecycle/narrow/slash-import`
- `commands-empty-lifecycle/narrow/slash-new`
- `commands-empty-lifecycle/narrow/process-exit`
- `compaction-status-manual/narrow/process-exit`
- `compaction-status-threshold/narrow/compaction-threshold`
- `compaction-status-threshold/narrow/process-exit`
- `compaction-status-overflow/narrow/process-exit`

配置路径、调试日志文件名、更新卡片、恢复命令换行、导出会话文件名、信任句里的 `Restart pi`，以及 `pi bug` 与 `cadr bug`。共 44 屏。

- `startup-existing/wide/post-exit-resume`
- `startup-existing/wide/process-exit`
- `startup-untrusted/wide/untrusted-startup`
- `startup-untrusted/wide/trust-untrusted`
- `startup-untrusted/wide/trust-untrusted-saved`
- `startup-untrusted/wide/process-exit`
- `config-selector-state-sweep/wide/config-global-initial`
- `config-selector-state-sweep/wide/config-global-unchecked`
- `config-selector-state-sweep/wide/config-global-rechecked`
- `config-selector-state-sweep/wide/config-project-initial`
- `config-selector-state-sweep/wide/config-project-unload`
- `config-selector-state-sweep/wide/config-project-load`
- `config-selector-state-sweep/wide/process-exit`
- `update-notifications/wide/version-and-package-updates`
- `update-notifications/wide/process-exit`
- `update-notifications-no-hyperlinks/wide/version-and-package-updates-no-hyperlinks`
- `update-notifications-no-hyperlinks/wide/process-exit`
- `config-selector-empty/wide/config-empty`
- `config-selector-empty/wide/process-exit`
- `commands-and-exit/wide/post-exit-resume`
- `commands-and-exit/wide/process-exit`
- `slash-debug/wide/debug-written`
- `slash-debug/wide/process-exit`
- `startup-existing/narrow/post-exit-resume`
- `startup-existing/narrow/process-exit`
- `startup-untrusted/narrow/untrusted-startup`
- `config-selector-state-sweep/narrow/config-global-initial`
- `config-selector-state-sweep/narrow/config-global-unchecked`
- `config-selector-state-sweep/narrow/config-global-rechecked`
- `config-selector-state-sweep/narrow/config-project-initial`
- `config-selector-state-sweep/narrow/config-project-unload`
- `config-selector-state-sweep/narrow/config-project-load`
- `config-selector-state-sweep/narrow/process-exit`
- `config-selector-empty/narrow/config-empty`
- `config-selector-empty/narrow/process-exit`
- `overlays-auth-manual-code-complete/narrow/login-manual-completed`
- `overlays-auth-browser-callback-complete/narrow/login-loopback-completed`
- `commands-and-exit/narrow/slash-export`
- `commands-and-exit/narrow/post-exit-resume`
- `commands-and-exit/narrow/process-exit`
- `slash-debug/narrow/debug-written`
- `slash-debug/narrow/process-exit`
- `example-tic-tac-toe/narrow/ttt-initial`
- `example-tic-tac-toe/narrow/ttt-cursor`

压缩进行中只差旋转字符 `⠙` 与 `⠋`。结束帧不再留下 Compacting。共 5 屏。

- `compaction-status-manual/wide/compaction-manual`
- `compaction-status-threshold/wide/compaction-threshold`
- `compaction-status-overflow/wide/compaction-overflow`
- `compaction-status-manual/narrow/compaction-manual`
- `compaction-status-overflow/narrow/compaction-overflow`

会话列表把 `other session question` 放在 `overlay question` 上面。窄屏已有 disposition 记录了这个次序。宽屏是同一件事。共 2 屏。

- `overlays-core/wide/overlay-session`
- `overlays-core/narrow/overlay-session`

## 2026-10-24 规范化之后

干净检出重跑 core（`scripts/render-diff.py capture`，上游 `/root/projects/pi-v1.4.0`，再跑同一脚本的 `analyze`）。成对检查点 465。`screenEqual` 171。相等或已被账本 / 类规则承认的是 203。缺 disposition、门禁算失败的是 262。203/465。

没有成对原始流的仍是复查一节那 7 个维度，不计入 465：`commands-informational` 宽窄、`update-notifications` 窄、`update-notifications-no-hyperlinks` 窄、`selector-scoped-state-sweep` 窄、`example-snake` 窄、`example-tic-tac-toe-agent` 窄。上游等待的句子没有出现在画面上。

规范化做了三件事。比较前两边都去掉每行行尾空白，包括落在收尾 SGR 前面的空格。状态指示行 `──` 后面、已知状态短语前面的旋转字符收成 `<SPIN>`。`docs/adjudications.md` 2026-08-14 已经接受的身份对（配置目录、`pi-debug.log`、changelog 地址、`Run pi update`、固定时钟的导出会话文件名、`Restart pi`、恢复命令）按场景写进 `lineRules`，只替换那一个字面量。

失败屏归属：

- GAP-65：127 屏。复查清单 129 里，`fatal-crash/wide/process-exit` 与 `fatal-crash/narrow/process-exit` 这一档的原始增量相等，门禁不要求 disposition。
- GAP-66：127 屏。
- GAP-81：2 屏。
- GAP-82：14 屏。
- GAP-83：2 屏。

上面几组有屏同时算进 GAP-65 和 GAP-66。去掉交集之后，GAP 失败是 245 屏。

交顾问裁决的有 4 种，17 屏。`docs/parity-map.md` 和 `docs/adjudications.md` 里没有对应记录，所以没有加 disposition。

会话列表次序，2 屏。`other session question` 在 `overlay question` 上面。

- `overlays-core/wide/overlay-session`
- `overlays-core/narrow/overlay-session`

窄屏工作目录省略号，2 屏。一边是 `<CWD>...`，另一边是 `<CWD>`。已接受的身份对不包括省略号。

- `example-tic-tac-toe/narrow/ttt-initial`
- `example-tic-tac-toe/narrow/ttt-cursor`

窄屏项目设置行丢掉字形，4 屏。路径换成占位符之后，一边停在 `resources a`，另一边停在 `resources`。已接受的身份对不覆盖被截掉的字。

- `config-selector-state-sweep/narrow/config-project-initial`
- `config-selector-state-sweep/narrow/config-project-unload`
- `config-selector-state-sweep/narrow/config-project-load`
- `config-selector-state-sweep/narrow/process-exit`

退出时光标行号差 1，9 屏。行尾空白去掉之后，可见文字相同，只剩 `<CURSOR>` 的行号。光标坐标不在这次规范化里。

- `startup-first/wide/process-exit`
- `startup-first/narrow/process-exit`
- `commands-empty-lifecycle/wide/process-exit`
- `compaction-status-manual/wide/process-exit`
- `compaction-status-manual/narrow/process-exit`
- `compaction-status-threshold/wide/process-exit`
- `compaction-status-threshold/narrow/process-exit`
- `compaction-status-overflow/wide/process-exit`
- `compaction-status-overflow/narrow/process-exit`
