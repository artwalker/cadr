# Open Questions

本文件只记录相对固定 TS 基线拟新增的机制。未获人工明确裁决前，条目不得
进入实现。

待裁决项：

- `OQ-G20-AGENT-EVAL-TOOL`：**给 agent（而非人）的 Lisp 求值工具**。
  用户 2026-08-13 提出「cadr 是 Lisp 写的，能不能利用 REPL 边跑边改来提高
  开发质量与效率、并更早发现 bug」。顾问就此的调查与保留意见：

  **与既有 `OQ-G10-D2-SLYNK-REPL` 是两件事。** 后者已于 2026-08-01 批准并实施，
  是**给人用的**：默认关闭、须显式 `--slynk`、loopback-only，人用 SLY 连上去
  对着运行中的 agent 重定义函数、看 restart、continue。
  本条问的是**把求值能力开给模型**——基线 pi 没有任何等价工具
  （其工具面为 read/write/edit/bash），故属"相对原版新增的机制"。

  **先说不需要裁决就能拿到的部分**（建议先用满这一层再谈新工具）：
  执行方用现有 bash 即可加载子系统并直接调用函数探测行为，无需重建
  20 MB 核。实测冷缓存下加载 `cadr-ai`（61 文件 / 25,818 行）**11.9 秒**
  （`sbcl --load ~/quicklisp/setup.lisp` + 逐个 `asdf:load-asd` +
  `asdf:load-system`，隔离 `HOME` 与 `ASDF_OUTPUT_TRANSLATIONS`，
  见 `scripts/test-cl.sh:15-40` 的既有写法）；热缓存更快。
  **「改一行要等整核重建」这个前提并不成立。**

  **新工具真正多出来的能力**只有一项：接进**正在运行的那个 cadr 进程**，
  在不丢失会话状态的前提下修复并 continue。这是 slynk 给人的能力。

  **顾问的保留意见（供裁决参考，非反对）**：
  1. **设计问题未解**。人做交互式调试靠的是把状态记在脑子里连续试探；
     agent 要用它得管理一个长命会话（何时开、何时关、上下文如何携带、
     崩了怎么恢复）。**这不是加个工具就有的能力。**
  2. **工具与被测物同一**。cadr 的正确性由对 pi 的差分定义；
     让模型在活镜像里改自己，产出的状态**不对应任何 commit**，
     render-diff 与账本都无从校验。
  3. **凭据面**。求值工具等价于任意代码执行，须与
     `development-policy` 第三节的凭据纪律逐条对照（`auth.json` 0600、
     token 不进日志/会话）后再谈边界。

  **裁决（用户 2026-08-13 授权顾问代为裁定）：暂缓实现，附条件重启。**

  理由三条，前两条是实测：
  1. **主要收益已可无成本获得。** 实测冷缓存加载 `cadr-ai`（61 文件 /
     25,818 行）**11.9 秒**，无需重建 20 MB 核；"改一行等整核重建"的前提不成立。
     新工具真正多出来的只有"接进正在运行的那个进程、不丢会话状态地修完继续"。
  2. **更高价值的 Lisp 能力尚未用起来，且已验证可行。**
     `sb-introspect:find-definition-sources-by-name` 可从镜像派生账本映射
     （现有 1,038 处手工映射已烂 108 处）；
     `sb-mop:class-slots` 逐槽比对实测能自动定位 `default-model` 差异
     （provider 门禁现仅比 6/21 字段）。**这两项收益更大、风险更低、
     不新增任何机制**，已列为 goal 20 Part N。
  3. **设计问题未解**：agent 如何管理长命 REPL 会话（何时开关、上下文携带、
     崩溃恢复）尚无答案；且工具与被测物同一，活镜像里的改动不对应任何 commit。

  **重启条件**：goal 20 Part N2 要求记录"哪些缺陷是靠加载探测回路先发现的"。
  **若该记录显示存在只能靠活镜像调试才能发现的一类缺陷**，据此重新提案并
  逐项裁决边界（含凭据面）。**在此之前不得实现。**

已裁决待办 goal：

（当前无待办 goal。）

已裁决不做：

- `OQ-G20-EXTENSION-ISOLATION`：**顾问 2026-08-13 调查后决定不做，本条关闭。**
  提出时的担心是"cadr 扩展加载进同一镜像，可触及任意内部符号"。**调查推翻了它**：
  - cadr 每个扩展获得独立包，`(make-package name :use '(:cl :cadr-agent))`
    （`src/cadr-cli/extensions/loader.lisp:476-478`），**不 use `cadr-cli`／
    `cadr-tui`／`cadr-ai` 的内部**；加载失败即 `delete-package` 清理。
  - **基线 pi 的隔离更弱**：`jiti.import(extensionPath)` 普通动态 import
    （`core/extensions/loader.ts:455`），**无 vm 沙箱、无 worker 隔离**；
    pi 扩展是 Node 模块，可 `require('fs')`、读 `process.env`，拥有全进程权限。
  - 残留面是 CL 的 `pkg::symbol` 可达内部，但那需要刻意写出限定名，
    **且 pi 扩展拥有的权限严格更大**。加包锁属相对基线的行为分岔，
    **换不来 pi 也不具备的安全性**。

  **结论：cadr 现状的隔离不弱于基线，不做改动。** 若将来扩展改为可从
  不受信来源自动安装，此结论须重新评估——**届时是分发模型变了，不是本条判断错了**。

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
