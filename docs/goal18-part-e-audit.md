# Goal 18 Part E 复核报告：有意差异行的能力保全

复核日期 2026-08-09；复核对象为 `docs/source-parity.md` 当前全部 **77** 行
`有意差异`（72 行既有 + 本 Part E3 改判的 5 行组件导出）。方法：机械抽出全部
判定为 `有意差异` 的行，逐行核查三件——(a) 分岔理由是否具体且合法，
(b) 等强度行为断言的指向是否具体、可跑，(c) 断言锁定的是基线行为还是
从 cadr 现实现反推。凡指针均以文件/门禁名给出，可由读者直接运行验证。

## 1. 结论先行

- 77 行全部具备具体分岔理由；无一行仅以"更 Lisp"为由。
- 51 行（CL-1～CL-4）为语言/构建生态必然差异，**本身不产生可观察行为差**；
  其能力面由差分类门禁在基线驱动下锁定（见 §2 各簇指针）。
- 26 行（CL-5）为真实行为面分岔，逐行配了可运行的断言指向；其中 5 行
  组件导出行由本 Part 改判并补齐断言（§4）。
- 复核发现并已修复 1 处断言缺口：settings-state-sweep 此前未开启终端图像
  支持，`Show images`/`Image width` 两行从未进入对拍（§4.3）。
- 未记账分岔清点（§3）未发现新的未登记分岔。

## 2. E1：七十七行逐行复核

### 簇定义

- **CL-1 声明文件/桶文件/模块拓扑**（9 行）：TypeScript `.d.ts`、桶导出与
  运行时分裂声明在 Common Lisp 无对应构件；不携带可观察行为。能力面由
  package 导出冻结门禁（goal 14 B10）与各能力测试锁定。
- **CL-2 动态 import 构建机制**（12 行）：`*.lazy.ts` 的延迟加载是 JS 构建
  优化，无行为语义；所交付的 provider 适配行为由 `test/cadr-ai/
  provider-payloads-test.lisp`、`provider-streams-test.lisp`、
  `provider-responses-test.lisp` 及固定基线 payload 对拍门禁锁定——期望
  值来自基线 checkout 的 fixture，非 cadr 现实现。
- **CL-3 Bun 运行时分裂**（4 行）：Bun 条件注册/bootstrap/sandbox-env 恢复
  在 SBCL 单镜像下无对应物；行为由 isolated build 与 native acceptance
  smoke 两个 verify.sh 阶段锁定。
- **CL-4 测试基建与开发杂物**（26 行）：8 个 vitest.config、16 个测试辅助
  模块、2 个 scratch 文件。Vitest helper 的可导出性是 JS 测试生态构件；
  对应行为保障由 `./scripts/test-cl.sh`（FiveAM 套件，15493 检查）与
  credential-gated live 套件承载，live/离线分离由 ASDF 系统划分保证。
- **CL-5 行为面分岔**（26 行）：见下表逐行指针。

### CL-5 逐行指针（26 行）

| 基线文件 | 分岔内容与合法理由 | 等强度断言指向 |
|---|---|---|
| `ai/src/cli.ts` | 独立 npm 登录 CLI 并入 cadr CLI（显著减少代码/产品形态） | `test/cadr-cli/config-auth-test.lisp`、`live-auth-test.lisp`、verify.sh native process modes |
| `ai/src/compat.ts` | JS 兼容桶/registry → CADR-AI package + 泛函数（去掉手工不变量） | `test/cadr-ai/provider-registry-test.lisp`、`provider-compat-test.lisp` |
| `ai/src/compat/extension-oauth-types.ts` | TS 结构回调类型 → 可调用槽（语言必然） | `test/cadr-agent/goal12-extension-api-test.lisp`、extensions-wave2/3 |
| `ai/src/legacy-api-aliases.ts` | cadr 从未发布旧 JS 符号名，无兼容对象；稳定面即 Lisp API | `test/cadr-ai/provider-compat-test.lisp` 锁定现行 API 面 |
| `ai/src/model-catalog.ts` | 嵌套 TS 组 → 哈希表目录，查找/枚举保持（显著减少代码） | `test/cadr-ai/goal12-model-data-test.lisp`、`models-runtime-test.lisp` |
| `ai/src/utils/abort-signals.ts` | AbortSignal 对象 → 谓词/condition + unwind 清理（消除 bug 类别：goal 13 退出死锁/取消不断链家族） | `test/cadr-cli/goal18-login-cancel-test.lisp`、`test/cadr-ai/retry-test.lisp`、`http-test.lisp` |
| `ai/src/utils/typebox-helpers.ts` | TypeBox 构造辅助 → 直接 JSON Schema（语言必然） | `test/cadr-ai/provider-payloads-test.lisp`、tool-result 对拍门禁 |
| `coding-agent/src/config.ts` | 路径 owner 收敛、install-method 按 SBCL 镜像表达、getToolsDir 死代码登记、getDebugLogPath 由 /debug 实现（Part B/C/D） | verify.sh migration PTY smoke、`test/cadr-cli/part-b-config-test.lisp`、`goal18-debug-command-test.lisp` |
| `coding-agent/src/core/extensions/index.ts` 等 5 行 | JS module loader/types/runner → Lisp package/form registry + immutable snapshot + host（已裁决结构分岔：解锁 Lisp 扩展能力） | `test/cadr-agent/goal12-extension-api-test.lisp`（含 declared-but-disconnected 派发审计）、`extensions-test.lisp`、wave2/3、live `LIVE-DEEPSEEK-SELF-EXTENSION-WRITE-RELOAD-AND-INVOKE` |
| `coding-agent/src/core/output-guard.ts` | monkey-patch Node stdout → 显式 output/error 流（消除 bug 类别：协议输出污染） | `test/cadr-cli/rpc-test.lisp`、`goal9-a2-process-faux-test.lisp`、live `LIVE-DEEPSEEK-PRINT-MODE-EMITS-ONLY-FINAL-TEXT` |
| `coding-agent/src/core/prompt-templates.ts` | 资源 discovery 结构按 Lisp 生态（语言必然，能力等价） | `test/cadr-agent/resources-test.lisp`、启动资源区块 fixture（Part H 强化） |
| `coding-agent/src/core/skills.ts` | 同上 | `test/cadr-agent/resources-test.lisp`、`test/cadr-agent/session-v2-test.lisp` |
| `coding-agent/src/utils/clipboard-native.ts` | Node native module → 注入式平台命令桥（语言必然） | `test/cadr-cli/part-b-interactive-test.lisp`、`goal13-presentation-test.lisp` |
| `coding-agent/src/utils/image-resize-worker.ts` | Node worker 入口 → 原生同步管线（显著减少代码） | `test/cadr-cli/part-b-interactive-test.lisp` 的 resize 覆盖 |
| `coding-agent/src/utils/photon.ts` | 已批准的纯 Lisp PNG/JPEG codec 替代 native binding（消除依赖类别） | `test/cadr-cli/part-b-interactive-test.lisp`、图像 fixture 测试 |
| `coding-agent/src/utils/sleep.ts` | Promise wrapper → CL:SLEEP + 可动态绑定注入（语言必然） | `test/cadr-cli/goal18-login-cancel-test.lisp`、`test/cadr-ai/retry-test.lisp` |
| `agent/src/stream-fn.ts` | 进程级全局默认 stream → per-agent 注入（去掉手工不变量；防多 session 污染） | `test/cadr-ai/faux-provider-test.lisp`，且全部套件均经注入运行（无全局默认可依赖） |
| 5 行组件导出（extension-selector / show-images-selector / skill-invocation-message / theme-selector / thinking-selector） | 见 §4：组件类有意不导出，等效能力经宿主代渲染/原生设置行提供 | 见 §4 各行账本注记与 §4.3 覆盖修复 |

### 关于核查项 (c)（断言锁基线而非反推）

差分类指针（render-diff、tool-result、event、payload 对拍）的期望值全部
由固定基线 checkout `74caa2649` 驱动生成，cadr 实现不参与期望值构造；
FiveAM 指针中锁定文案/行为的断言均在注记或测试注释中给出基线
file:line 出处。本 Part 改判的 5 行均先查基线调用点再下结论（§4）。

## 3. E2：未记账分岔清点

方法：以"可观察行为不一致但不在 77 行内"为对象，沿四条已有机动车道的
覆盖边界做结构性排查，并清点 cadr 侧相对基线的新增：

1. **布局分岔**（`~/.cadr/agent/` 层）——goal 18 Part B/C 已对齐基线并
   入账（config.ts 行注记），不再是未记账分岔。
2. **cadr 侧新增能力**逐项核对登记状态：崩溃脱敏（I02，
   `docs/open-questions.md` OQ-G15-I02-FATAL-REDACTION 已裁决登记）、
   `/share` viewer `https://cadr.dev/session/`（I03，open-questions 与
   README 差异清单已登记）、产品身份（I04，README 差异清单）、
   `:tool-call-error` 第 34 个扩展事件与 `originator=cadr`（README:387、
   :480、:490 均已登记）。**全部在账。**
3. **呈现层已知差异**全部由 render-diff dispositions 逐 checkpoint 登记
   （268 条，每条具体 note + 精确 screenSha256），无账外项。
4. 本轮新发现的覆盖缺口（settings 图像行未对拍）属"断言不在位"而非
   行为分岔；已在 §4.3 修复。

结论：除已由 Part B 处理并入账的布局分岔外，未发现新的未记账分岔。

## 4. E3：扩展 API 导出面集合比对（23 个 `*Component`）

### 4.1 集合比对方法

基线 `packages/coding-agent/src/index.ts` 导出 23 个 `*Component`。
逐一核查其在基线中的**真实消费点**（产品内调用 / 扩展或示例 import /
仅 barrel 再导出），再对照 cadr 的功能落点。

### 4.2 关键事实（全部可在基线 checkout 复核）

- `ShowImagesSelectorComponent`、`ThemeSelectorComponent`、
  `ThinkingSelectorComponent` 在基线**全仓库零产品调用、零扩展/示例
  import**——仅 `components/index.ts` 与 `src/index.ts` 两个 barrel 再
  导出。即基线用户可见界面里根本不存在这三块组件；goal18.md 顾问表中
  "基线是两选项选择器"的前提是**把导出清单当成了实景**。基线的实景是
  `settings-selector.ts:627-632` 的布尔设置行（label `Show images`、
  description `Render images inline in terminal`），与 cadr 逐字一致。
- `ExtensionSelectorComponent`（startup-ui.ts:152、
  interactive-mode.ts:2261/5018）与 `SkillInvocationMessageComponent`
  （interactive-mode.ts:3327）是**宿主内部渲染器**：扩展经
  `ctx.ui.select`/`ui.custom`/会话内容触发，宿主代为实例化；基线
  examples/extensions 无一 import 这两个类。
- 其余 18 个组件在 cadr 均有同名功能落点（transcript/selector/component
  渲染族），由 render-diff 逐屏对拍锁定。

### 4.3 判定与处置

**判定：五个组件类有意不导出，属分岔，入账并配等强度断言。**
理由：基线扩展生态从不消费这些类（消费面是 `ctx.ui` 回调与宿主代渲染），
cadr 的扩展 API 已经裁决为宿主中介的 Lisp 形态（goal 13）；为无人消费的
类导出 Lisp 等价物不提供任何能力，只会制造第二套 UI 构造入口。
用户可见行为（设置行、skill 调用消息、扩展 selector）由下列断言锁定：

- 5 行账本判语由 `已实现` 改为 `有意差异`，注记写明基线消费点证据、
  cadr 等效落点与断言指向（docs/source-parity.md 4.2 节对应行；
  汇总表与头部计数同步为 595 = 518 + 77 + 0）。
- **覆盖修复**：`settings-state-sweep` 现以 `setup.supportsImages=true`
  驱动，34 个 row checkpoint 遍历含 `Show images`、`Image width` 在内的
  全部设置行（此前未开图像支持，这两行从未被对拍——本 Part 发现并
  修复的断言缺口）；双侧 72 个 checkpoint 全部逐屏锁定，可见文本与
  基线一致（narrow 屏逐字节相等；wide 仅产品名占位符的尾垫差异，I04）。
- skill 调用消息由 `test/cadr-agent/resources-test.lisp`、
  `session-v2-test.lisp` 锁定，基线侧构造在 baseline-visible-strings
  清单内由 construction suite 驱动。
- 扩展 selector 由 `test/fixtures/extensions/rpc-ui.lisp` 套件与
  render-diff `extension-surfaces` 场景锁定。

## 5. 整改清单

| 项 | 状态 |
|---|---|
| 5 行组件导出改判 `有意差异` + 具体注记 + 断言指向 | 已完成（本 Part） |
| settings-state-sweep 图像行覆盖缺口 | 已完成（场景开图像支持，72 checkpoint 重对拍） |
| 汇总表/头部计数/goal12-examples-test 同步（523/72 → 518/77） | 已完成 |
| 其余 72 行的理由与断言指向复核 | 已完成（§2 表，无整改项） |
| 未记账分岔清点 | 已完成（§3，无新增） |
