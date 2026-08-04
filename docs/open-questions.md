# Open Questions

本文件只记录相对固定 TS 基线拟新增的机制。未获人工明确裁决前，条目不得
进入实现。

当前无待裁决项。

已裁决并实施：

- `OQ-G15-I02-FATAL-REDACTION`：2026-08-04 已确认维持 Goal 13 实施的
  崩溃脱敏机制。固定基线在终端直接 dump 栈
  （`packages/coding-agent/src/modes/interactive/interactive-mode.ts:3671-3721`），
  会泄漏系统提示词与会话内容；Cadr 改为用户可见的脱敏摘要与仅所有者可读的
  `0600` 私有崩溃日志。该项是相对基线的有意新增，而非语言迁移的必然差异；
- `OQ-G10-D1-TOOL-RESTARTS`：2026-08-01 已批准工具失败现场的
  condition/restart 与第 34 个扩展事件 `:tool-call-error`；实现后以
  34 个事件重新冻结，今后新增仍须重新提案并逐项裁决；
- `OQ-G10-D2-SLYNK-REPL`：2026-08-01 已分别批准默认关闭、
  loopback-only 的 Slynk 运行时 REPL 及精确锁定的第三方依赖闭包；
- Goal 10 Part B 已由用户裁定为 no-op 后，两项按批准提案实施并重新冻结。

完整边界、依赖锁与裁决记录见
[`docs/proposals/goal-v10-part-d-lisp-native-capabilities.md`](proposals/goal-v10-part-d-lisp-native-capabilities.md)。

`OQ-G9-LIVE-GATE` 已由用户逐项批准并实施，裁决与证据归档于
[`docs/proposals/goal-v9-live-test-gating.md`](proposals/goal-v9-live-test-gating.md)。

- `OQ-G16-SHARE-VIEWER-TRANSITION`：2026-08-05 已裁决。`/share` 保持默认
  启用，默认 viewer 统一为 `https://cadr.dev/session/`，并仅允许
  `CADR_SHARE_VIEWER_URL` 覆盖。用户已知情接受：在 cadr.dev 页面上线前，
  `/share` 会成功创建 Gist，但生成的 viewer 链接暂不可达；页面上线后无需修改
  Cadr 代码。该过渡状态不得作为禁用 `/share`、回退上游 viewer 或引入其他
  fallback 机制的理由。

- `OQ-CANONICAL-REPOSITORY-URL`：2026-08-05 已裁决并实施。
  `src/cadr-cli/support/changelog-share.lisp:144,152-160` 将 `/share` 的
  changelog 链接改写并钉向 `https://github.com/earendil-works/pi`。但
  `CHANGELOG.md` 记录的是 **Cadr 自身**的变更（如"Added the fourth parity
  ledger"、"Replaced the OAuth callback page's interim block-C mark with Cadr's
  cons-cell identity"），链向上游仓库属对外冒用上游身份，与已修正的
  `originator=pi`、pi logo 同族。
  用户已确认规范仓库为 `https://github.com/artwalker/cadr`；仓库私有不改变其
  canonical URL。C4 已让 `/changelog` 的运行时链接重写从 release identity 的
  单一来源读取该 URL，不改 `origin`。`src/cadr-evals/suites.lisp` 的 legacy TS
  扩展检测与 generated catalog 的 `pi-ai` 来源注释经全树审计确认是基线证据，
  继续进入精确 allowlist，不随产品身份替换。
