# Open Questions

本文件只记录相对固定 TS 基线拟新增的机制。未获人工明确裁决前，条目不得
进入实现。

待裁决项：

（当前无待裁决项。）

已裁决待办 goal：

（当前无待办 goal。）

已裁决并实施：

- `OQ-G18-L1A-MERMAID`：2026-08-12 已裁决路线 1；goal 19 Part C 落地。
  `docs/source-parity.md` 中 `mermaid.ts` 行记 `已实现`
  （`src/cadr-tui/mermaid/transform.lisp:transform-mermaid-markdown`）。


- `OQ-G18-AUTH-CANCEL-14`：2026-08-12 已裁决路线 A 并落地。v0.84.1 起
  基线 pi 在 14 个 auth-cancel 整屏键上渲染红色
  `Error: ... This operation was aborted`（回归：abort.ts:3 抛
  `"The operation was aborted"`，interactive-mode.ts:5666 仅压制
  `"Login cancelled"`）；cadr 按 goal 13 既定裁决继续压制，14 键记为
  intentional-difference `I05`（textCovering，仅限登录取消，note 如实
  描述）。上游修复该回归后 I05 退役，14 键转回逐字对齐。处置记录见
  `docs/proposals/goal18-auth-cancel-regression.md`。

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

- `OQ-G18-NPM-PACKAGE-SOURCE`：2026-08-10 已裁决为有意差异。基线
  `install`/`update` 经 npm 安装 `npm:` 包源；Common Lisp 构建无 npm
  出口，以固定文案拒绝（"npm packages are unavailable in the Common Lisp
  build; install a Lisp local or Git package"）。等强度断言：
  `goal18-npm-package-source-is-a-fixed-intentional-difference`
  （part-b-package-test.lisp）锁定该固定形状。

- `OQ-G18-UPDATE-MODELS`：2026-08-10 已裁决为有意差异。基线
  `update --models` 联网刷新模型目录；cadr 模型目录随二进制内置，该命令
  输出固定离线提示（"Model catalogs are bundled with this cadr build."）。
  等强度断言：`goal18-update-models-is-a-fixed-intentional-difference`
  （part-b-package-test.lisp，以 `:offline-p t` 证明无网络参与）。

- `OQ-G18-INSTALL-TELEMETRY`：2026-08-10 已裁决为有意差异。基线在
  交互启动时向 pi.dev 的 report-install 端点发安装上报
  （interactive-mode.ts:1045-1062，受 enableInstallTelemetry 与 PI_OFFLINE
  门控）；cadr 保留 settings 中的 `enableInstallTelemetry` 展示面，但不存在
  任何上报出口。等强度断言：`goal18-install-telemetry-has-no-egress`
  （goal14-organization-test.lisp）对全部 src/**/*.lisp 做端点字符串
  缺席扫描。
