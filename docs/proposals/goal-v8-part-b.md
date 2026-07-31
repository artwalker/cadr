# GOAL v8 Part B 四项裁决提案

状态：**四项均已获用户逐项批准并按第 5 节完成；本文保留为授权与基线证据。**

固定行为基线：
`71efc6f0c1909874ec8c944637a9ae7fc0e2d508`，checkout
`/tmp/cadr-parity-71efc6f0`。本文所有 TypeScript `file:line` 均指该提交。

## 0. 程序边界与已落账增量

预授权范围内的 Part B 增量已经按逻辑分为五个提交：

| 提交 | 内容 | 预裁边界 |
|---|---|---|
| `724494fd562d34097c225072ace81771311c58f4` | 测试与 fixtures | Goal 8 Part B；六个 lifecycle event 对应预裁第 0.5(3) |
| `36310bfb040674ef43dff421e4e537eb7471ebaa` | agent/session/resource/tool/input runtime | provider request hooks 只按预裁第 0.5(3) |
| `267b215aa45e488053dd85330d8a9c1106553369` | CLI service primitives | provider lifecycle bridge 只按预裁第 0.5(3) |
| `81b441aec12669ef368670f494a1b28697bb8193` | CLI-owned interactive controllers | 未修改 `src/cadr-tui` 生产代码 |
| `d0a90f9e009aadcca4f3fb482596c21e4314308b` | REPL/RPC/TUI glue | startup lifecycle wiring 只按预裁第 0.5(3) |

预裁第 0.5(3) 的 provider request replacement 新增三个公开导出，所以
“extension export SHA 仍为 Goal 7 冻结值”的说法错误。用 Goal 7 相同取样
范围重算：

```text
sed -n '/#:define-tool/,/#:make-extension-hook-result/p' \
  src/cadr-agent/package.lisp | sha256sum
e89a7f84962c539bfab1645df4867a8f3b587ae46201865abcf9d2b503dc068a  -
```

Goal 7 原值
`cc8e7d180b5007cbf4daa66ff904f8c0714992df646211c232135500efd936e7`
只保留为历史锚点；当前锚点是
`e89a7f84962c539bfab1645df4867a8f3b587ae46201865abcf9d2b503dc068a`。
本次 SHA 修正不扩大后续四项权限。

共同硬约束：

1. 四项均保持 `M`/blocked，用户必须逐项批准；不得以批准其中一项推定批准
   其他项；
2. 只实现固定基线已有机制，不增加基线没有的安全、审批、缓存或抽象；
3. 现有扩展宏签名、既有事件语义与 stale-context 规则零变更；
4. 新增第三方依赖必须先获用户授权，并同步
   `docs/dependency-audit.md` 与 README；不得先添加后追认；
5. 若批准项的最小实现超出本文列出的解冻面，立即再次 blocked；
6. 实现顺序固定为测试先行、最小生产实现、全量门禁、逻辑提交、重冻。

## 1. 裁决项一：真实图片像素解码、转换与缩放

### 1.1 确切需求

补齐 `packages/coding-agent/test/image-processing.test.ts` 的整文件语义：

1. PNG 在限制内保持原 bytes；
2. JPEG 可转换为 PNG；
3. PNG/JPEG 必须读取真实像素并执行 EXIF orientation；
4. 超出宽高时保持比例缩放，基线采样器为 Lanczos3；
5. 超出编码大小时比较 PNG/JPEG，并按 JPEG quality
   `requested, 85, 70, 55, 40` 与 0.75 倍尺寸阶梯压缩；
6. 直至 `1x1` 仍超限则返回 `nil`；
7. worker 是 Node/Bun 的并发实现细节；Lisp 可同步执行，但输出语义必须一致。

### 1.2 基线是否真的解码像素

**是，基线真实解码并重采样像素，绝非仅读取尺寸头。**

| 事实 | 固定基线 |
|---|---|
| `PhotonImage.new_from_byteslice(bytes)` 解码输入，应用 EXIF orientation，再用 `get_bytes()` 重编码 PNG | `packages/coding-agent/src/utils/image-convert.ts:4-23` |
| resize 同样先调用 `new_from_byteslice`，随后从已解码 image 读取宽高 | `packages/coding-agent/src/utils/image-resize-core.ts:59-80` |
| 使用 `photon.resize(..., SamplingFilter.Lanczos3)` 对像素重采样，并从 resized image 编码 PNG/JPEG | `packages/coding-agent/src/utils/image-resize-core.ts:95-120` |
| 依次尝试 JPEG quality 与 0.75 尺寸递减，直到 `1x1` 或满足 byte limit | `packages/coding-agent/src/utils/image-resize-core.ts:122-163` |
| worker 失败时回退到同一 in-process 像素实现 | `packages/coding-agent/src/utils/image-resize.ts:78-109` |
| 测试要求 JPEG→PNG，而非只认 MIME/尺寸 | `packages/coding-agent/test/image-processing.test.ts:29-49` |
| 测试要求 `100x100` 真正缩到不超过 `50x50` | `packages/coding-agent/test/image-processing.test.ts:85-98` |
| 测试要求编码后 bytes 变小、无法降到 1 byte 时返回 null，并接受 JPEG 输入 | `packages/coding-agent/test/image-processing.test.ts:100-139` |

当前 cadr 仅对 BMP 做了像素解码：

- `src/cadr-cli/media.lisp:31-47` 只识别 magic；
- `src/cadr-cli/media.lisp:191-231` 只有 RGBA→PNG encoder；
- `src/cadr-cli/media.lisp:233-293` 解码 BMP pixels；
- `src/cadr-cli/media.lisp:295-302` 对非 BMP 原样返回；
- `src/cadr-cli/interactive-services.lisp:2566-2654` 对 PNG/JPEG 只读尺寸头；
- `src/cadr-cli/interactive-services.lisp:2656-2701` 只有测试可注入的
  `resize-function`，没有生产 PNG/JPEG decoder/resampler。

所以“当前代码已经通过尺寸头覆盖图片处理”是假的；它只覆盖 metadata 与
BMP conversion，没有覆盖基线的 PNG/JPEG pixel pipeline。

### 1.3 最小依赖与解冻范围

建议批准两个直接 Quicklisp production dependencies：

| 系统 | 固定 Quicklisp release | 用途 | 新传递闭包 |
|---|---|---|---|
| `cl-jpeg` | `cl-jpeg-20230214-git` | JPEG decode/encode | 只有 ASDF；ASDF 为实现提供 |
| `png-read` | `png-read-20170830-git` | PNG scanline/filter/color decode | `babel`, `chipz`, `iterate` |

`babel` 与 `iterate` 已存在于登记过的 `cl-sqlite` 传递闭包，但通过
`png-read` 进入图片路径后必须重新在依赖审计中明确登记；`chipz` 是新的
传递系统。两个 direct dependencies 与 `chipz` 都必须先获用户批准。

最小生产实现：

1. `cl-jpeg`/`png-read` 把 JPEG/PNG 统一解码为 RGBA；
2. cadr 内实现确定性的 Lanczos3 RGBA resampler；
3. 复用现有 `encode-rgba-png`，JPEG 候选用 `cl-jpeg`；
4. JPEG decode 前按基线应用 EXIF orientation；
5. 保留输入未超限时的原 bytes fast path；
6. 不新增 subprocess，不调用外部 ImageMagick。

最小解冻文件：

```text
cadr-cli.asd
src/cadr-cli/media.lisp
src/cadr-cli/interactive-services.lisp
test/cadr-cli/part-b-interactive-test.lisp
docs/dependency-audit.md
README.md
docs/parity-map.md
docs/progress/goal-v8.md
```

`src/cadr-tui`、`src/cadr-ai`、`src/cadr-agent` 保持冻结。若库 API 不能在该
边界内覆盖 PNG/JPEG pixel pipeline，重新 blocked。

### 1.4 已考虑但否决的替代方案

| 方案 | 否决理由 |
|---|---|
| 继续只读尺寸头 | 直接违反 JPEG→PNG、真实 resize 和 byte reduction 基线 |
| ImageMagick/ffmpeg subprocess | 新增外部运行时依赖，构建与部署不再 hermetic |
| `opticl` | closure 明显更大：`cl-jpeg`, `cl-tga`, `opticl-core`, `pngload`, `retrospectiff`, `skippy`, `zpng` 等 |
| 自写完整 PNG/JPEG codec | 重复成熟 codec，维护面和恶意输入风险都远高于两个窄库 |
| 只用 `cl-jpeg`、自行实现 PNG inflate/filter | 仍需重写 DEFLATE、filter、CRC 与 color-type 边界，收益不足 |
| 将 worker 语义逐字移植为 Lisp 线程 | worker 是防 Node event loop 阻塞的实现手段，不是可观察合约 |

**建议裁决：批准 `cl-jpeg` + `png-read` 及上述闭包和最小解冻面。**

## 2. 裁决项二：Part B 所需扩展 API 与 CLI UI glue

### 2.1 确切需求

只补齐下列固定基线 extension surface：

1. `ctx.isIdle()` 与 command-only `ctx.waitForIdle()`；
2. shortcut、flag、message renderer、entry renderer 注册；
3. tool call/result custom renderer；
4. load-scope extension API 的 `sendMessage`、`sendUserMessage`、`exec`、
   `getFlag`、`getActiveTools`、`setActiveTools`；
5. bare/named/hidden inline extension factories；
6. CLI-owned UI bridge 的 custom overlay、autocomplete wrapper、theme
   get/set/list/load 与 tool-output expansion get/set。

不新增事件名，不改既有宏签名，不放宽现有 handler context 的生命周期，也不
解冻 `src/cadr-tui` 生产代码。

### 2.2 固定基线证据

| Surface | 固定基线 |
|---|---|
| `ExtensionContext.isIdle` | `packages/coding-agent/src/core/extensions/types.ts:307-347`，方法在 `:329-330` |
| command-only `waitForIdle` | `packages/coding-agent/src/core/extensions/types.ts:353-365`，方法在 `:357-358` |
| shortcut、flag、`getFlag` | `packages/coding-agent/src/core/extensions/types.ts:1243-1269` |
| message/entry renderer | `packages/coding-agent/src/core/extensions/types.ts:1271-1279` |
| `exec`、active tools get/set | `packages/coding-agent/src/core/extensions/types.ts:1313-1326` |
| tool renderer context、`renderCall`、`renderResult` | `packages/coding-agent/src/core/extensions/types.ts:410-497` |
| custom UI、autocomplete | `packages/coding-agent/src/core/extensions/types.ts:195-225` |
| theme 与 tool expansion | `packages/coding-agent/src/core/extensions/types.ts:265-281` |
| 注册与 action delegation | `packages/coding-agent/src/core/extensions/loader.ts:230-352` |
| inline factory 构造与命名 | `packages/coding-agent/src/core/extensions/loader.ts:483-497`; `packages/coding-agent/src/core/resource-loader.ts:158-175,945-967` |
| runtime 绑定与动态 context | `packages/coding-agent/src/core/extensions/runner.ts:278-293,313-430,659-763` |

直接约束行为的 tests：

| 行为 | 固定基线 |
|---|---|
| renderer/shortcut/flag discovery | `packages/coding-agent/test/extensions-discovery.test.ts:374-393,463-497` |
| shortcut 冲突与 reserved key 语义 | `packages/coding-agent/test/extensions-runner.test.ts:161-365` |
| renderer 与 flag resolution | `packages/coding-agent/test/extensions-runner.test.ts:596-699` |
| plan mode 使用 flags 和 active tools | `packages/coding-agent/test/plan-mode-extension.test.ts:35-128` |
| tool renderer state、fallback、inheritance | `packages/coding-agent/test/tool-execution-component.test.ts:38-365` |
| expansion、theme、custom focus、autocomplete | `packages/coding-agent/test/interactive-mode-status.test.ts:120-376` |
| inline factories 进入 harness | `packages/coding-agent/test/test-harness.test.ts:271-322` |
| `pi` 对象可在 handler 外、同一有效 runtime 内异步使用 | `packages/coding-agent/test/suite/regressions/2023-queued-slash-command-followup.test.ts:17-79` |
| active tools 同一 run 生效并写入 tool-result delta | `packages/coding-agent/test/suite/regressions/6162-extension-active-tools-next-turn.test.ts:8-123` |
| inline factory bare/named/hidden/mixed 命名 | `packages/coding-agent/test/suite/regressions/6260-inline-extension-naming.test.ts:36-118` |
| settled 后 `isIdle=true`，command `waitForIdle` 等到 session settled | `packages/coding-agent/test/suite/regressions/6363-agent-settled-event.test.ts:29-120` |
| module cache 与每次 factory rerun 的边界 | `packages/coding-agent/test/suite/regressions/extension-factory-cache.test.ts:69-129` |

### 2.3 最小 Lisp 公共合约

现有 `extension-context` 继续只在 handler 内有效；其 stale error、现有
accessor 和现有宏签名全部不变。新增一个与 TS factory 参数 `pi` 对应的
load-scope opaque handle：

```lisp
(current-extension-api) ; 仅扩展加载期可取，=> extension-api

(extension-api-send-message
 api message &key trigger-turn-p deliver-as)
(extension-api-send-user-message
 api content &key deliver-as)
(extension-api-exec
 api command arguments &key cwd environment timeout-ms)
(extension-api-get-flag api name)
(extension-api-get-active-tools api)
(extension-api-set-active-tools api tool-names)
```

该 handle 可由扩展捕获并在同一有效 generation 的 command/tool/async
continuation 中使用，满足 regression #2023；reload、session replacement 或
bundle retirement 后仍必须 stale。它不是永生 global，也不放宽
`extension-context`。

只向 context 增加：

```lisp
(extension-context-idle-p context)
(extension-command-context-wait-for-idle context)
```

第二个函数只接受 command context；普通 event/tool context 调用必须报类型
错误。settled 定义沿用现有 agent 的 retry/follow-up drain 边界。

注册面只增新宏，不改现有 `define-tool`、`define-command`、
`define-event-hook`、`define-provider` lambda list：

```lisp
(define-shortcut key &key description handler)
(define-flag name &key description type default)
(define-message-renderer custom-type &key renderer)
(define-entry-renderer custom-type &key renderer)
(define-tool-renderer tool-name &key call result)
```

`define-tool-renderer` 独立存在，避免给已冻结的 `define-tool` 加 keyword。
renderer 返回现有 cadr-tui component/line protocol，缺失 call/result slot 时
按基线回退或继承，不创建第二套组件类型。

inline factory 输入只允许：

```lisp
function
(:name string :factory function :hidden-p boolean)
```

bare factory 显示 `<inline:N>`，named factory 显示 `<inline:name>`；module/source
parse cache 仍按 cwd/generation，factory 每次 load 都运行。

UI bridge 只增加：

```lisp
(extension-context-custom context factory &key overlay-p overlay-options)
(extension-context-add-autocomplete-provider context factory)
(extension-context-theme context)
(extension-context-all-themes context)
(extension-context-get-theme context name)
(extension-context-set-theme context theme)
(extension-context-tools-expanded-p context)
(extension-context-set-tools-expanded context expanded-p)
```

实现必须位于 `cadr-cli`，复用现有 overlay/editor/theme/autocomplete/tool row
组件；`src/cadr-tui` 继续冻结。若任何一项确需修改 `src/cadr-tui` 生产 object
ID，立即 blocked。

### 2.4 最小解冻范围

```text
src/cadr-agent/extensions.lisp
src/cadr-agent/package.lisp
src/cadr-agent/loop.lisp
src/cadr-agent/tool.lisp
test/cadr-agent/extensions-wave3-test.lisp
src/cadr-cli/extensions.lisp
src/cadr-cli/resource-loader.lisp
src/cadr-cli/interactive-services.lisp
src/cadr-cli/tui.lisp
src/cadr-cli/main.lisp
test/cadr-cli/extensions-test.lisp
test/cadr-cli/part-b-*.lisp
cadr-agent.asd
cadr-cli.asd
docs/parity-map.md
docs/architecture.md
docs/progress/goal-v8.md
```

只允许按测试证明实际需要的文件进入提交；该清单不是整目录授权。
`src/cadr-ai` 与 `src/cadr-tui` 保持冻结。

### 2.5 向后兼容与重冻门禁

1. `LEGACY-EXTENSION-SOURCE-REMAINS-COMPATIBLE-AFTER-WAVE-2-API-EXPANSION`
   必须继续全绿；
2. 现有四个旧 event、33 个已冻结 event 与所有旧宏签名逐项回归；
3. 捕获旧 `extension-context` 离开 handler 后仍抛
   `stale-extension-context`；
4. 新 load-scope API 在 reload/retirement 后也 stale；
5. `src/cadr-tui` production object ID 零变化；
6. 实现提交后重算 extension export SHA 与全部 extension object ID，更新
   architecture，再恢复“发布即稳定”。

### 2.6 已考虑但否决的替代方案

| 方案 | 否决理由 |
|---|---|
| 直接让 `extension-context` 永久有效 | 破坏 Goal 7 stale-context 冻结与 reload/session replacement 隔离 |
| 给现有宏加 keywords | 改变冻结 lambda list，旧扩展兼容门禁失真 |
| 新增 event 传递 UI/active-tools | 基线已有 action/context surface，无需发明事件 |
| 只做 test fixture wrapper | 无法覆盖真实 resource loader、TUI focus、active-tool next request |
| 在 `cadr-agent` 复制 TUI component | 破坏依赖方向并产生第二套 UI 类型 |
| 修改 `src/cadr-tui` | 当前证据显示 CLI glue 可复用现有组件；若事实相反必须另行裁决 |
| 将这些行判 N/A | 它们不是语言/构建必然差异，而是原版公开扩展机制 |

**建议裁决：批准本节列出的 additive API 与 CLI glue；禁止解冻
`src/cadr-ai`、`src/cadr-tui`。**

## 3. 裁决项三：llama.cpp bundled extension 与最小 `cadr-ai` 合约

### 3.1 确切需求

整文件覆盖 `packages/coding-agent/test/llama-extension.test.ts`：

1. bundled extension 注册 native runtime provider 与 `/llama`；
2. management URL 与 `/v1` inference URL 规范化；
3. 只暴露 `loaded` models，并映射 context window、image modality 等 metadata；
4. provider-scoped model store 支持 online refresh 与 cache-only restore；
5. 未配置时 dormant；交互登录保存 server URL 与 optional key；
6. auth check/resolve 产生请求期 base URL/key；
7. Hugging Face 搜索、GGUF quantization 分组与 gated metadata；
8. `/models/sse` 的 load/download progress 与最终 catalog refresh；
9. inference 复用已有 OpenAI Chat Completions stream，不新增 wire protocol。

### 3.2 固定基线证据

| 合约 | 固定基线 |
|---|---|
| runtime provider 的 auth/models/refresh/filter/stream 面 | `packages/ai/src/models.ts:34-120` |
| runtime login/check 的公共语义 | `packages/ai/src/models.ts:127-171,364-445` |
| provider mutation、provider-scoped store、credential-aware refresh 与 cache fallback | `packages/ai/src/models.ts:218-328` |
| store entry 与 provider-scoped read/write/delete | `packages/ai/src/models-store.ts:3-28` |
| API-key login/check/resolve | `packages/ai/src/auth/types.ts:150-182,212-220` |
| llama provider URL/key login、check、resolve | `packages/coding-agent/src/extensions/llama/provider.ts:58-110` |
| loaded catalog、cache restore、OpenAI completions stream | `packages/coding-agent/src/extensions/llama/provider.ts:111-133` |
| extension 注册与 URL normalization | `packages/coding-agent/test/llama-extension.test.ts:42-60` |
| loaded-only model mapping | `packages/coding-agent/test/llama-extension.test.ts:62-87` |
| cache-only restore | `packages/coding-agent/test/llama-extension.test.ts:89-131` |
| dormant/login/check/resolve | `packages/coding-agent/test/llama-extension.test.ts:133-162` |
| Hugging Face search/details | `packages/coding-agent/test/llama-extension.test.ts:164-202` |
| 本地 loopback SSE load/download | `packages/coding-agent/test/llama-extension.test.ts:204-291` |

`llama-extension.test.ts` 不是 Ollama/llama.cpp live smoke。它启动本地 loopback
HTTP/SSE server，所有断言均 deterministic，固定基线没有 `skipIf(!KEY)`。
因此不能按 live 凭据门控原则跳过；本机没部署 llama.cpp 也不是 N/A 理由。

### 3.3 `cadr-ai` 已有能力

当前 `cadr-ai` 并非缺少整个 provider runtime：

- `src/cadr-ai/models-runtime.lisp:66-79` 已有 models/model-function、
  auth resolver、OAuth、refresh/filter、complete/stream slots；
- `src/cadr-ai/models-runtime.lisp:100-154` 已有 provider mutation 与同步
  current models；
- `src/cadr-ai/models-runtime.lisp:293-341` 已有 auth check 与 availability；
- `src/cadr-ai/models-runtime.lisp:343-418` 已有 provider-scoped model store 与
  refresh/cache fallback；
- `src/cadr-ai/models-runtime.lisp:538-543` 已有 complete/stream dispatch。

所以不允许重写 registry，也不允许把 llama management 塞进 `cadr-ai`。

### 3.4 `cadr-ai` 需要的最小新增合约面

只对 `runtime-provider` 做 additive slots：

```lisp
api-key-login-function
auth-check-function
refresh-context-function
```

API-key login 使用与基线 `AuthInteraction` 等价的 opaque interaction：

```lisp
(make-runtime-auth-interaction
 :prompt-function function
 :notify-function function
 :abort-p function)
(runtime-auth-interaction-prompt interaction prompt)
(runtime-auth-interaction-notify interaction event)
(runtime-auth-interaction-aborted-p interaction)
```

`prompt` 是严格 plist，至少支持 llama 所需的
`(:type :text/:secret :message string :placeholder optional-string)`；
`event` 是 `(:type keyword :message string)`。这不是新 UI 框架，CLI 只把它
桥接到现有 input/secret/notification。

新增 opaque refresh context：

```lisp
(runtime-refresh-context-credential context)
(runtime-refresh-context-store context)
(runtime-refresh-context-allow-network-p context)
(runtime-refresh-context-force-p context)
(runtime-refresh-context-aborted-p context)
```

新增 runtime entry point：

```lisp
(models-runtime-login-api-key runtime provider-id interaction)
```

精确语义：

1. `models-runtime-login-api-key` 只调用 provider 的
   `api-key-login-function`，返回并由既有 credential store 保存
   `api-key-credential`；不解冻 OAuth login；
2. `models-runtime-check-auth` 若有 `auth-check-function` 则优先调用，否则保持
   现有 resolver fallback；
3. `models-runtime-refresh` 若有 `refresh-context-function`，传入 provider-scoped
   store、credential、allow-network、force、abort view；否则继续调用现有
   `refresh-function credential store allow-network force`；
4. **现有 `refresh-function` 参数表不改**，现有 provider 零迁移；
5. 只导出上述新增类型/accessor/entry point 和构造器需要的 additive slot
   accessor；静态 provider registry、模型类型、HTTP/SSE 与 wire protocol
   不改。

agent/CLI glue 另行最小增加：

```lisp
(define-native-provider runtime-provider)
```

它与现有 `define-provider` 并存，后者签名和静态 overlay 语义不变。
`cadr-cli` 把 native runtime provider 接入现有 model selector、auth/store 和
agent dispatch；llama client、Hugging Face client、SSE progress 与 `/llama`
command 放在 bundled CLI extension 目录，不进入 `cadr-ai`。inference 复用现有
`:openai-completions` adapter。

### 3.5 最小解冻范围与保险丝

```text
src/cadr-ai/models-runtime.lisp
src/cadr-ai/package.lisp
test/cadr-ai/models-runtime-test.lisp
cadr-ai.asd
src/cadr-agent/extensions.lisp
src/cadr-agent/package.lisp
test/cadr-agent/extensions-wave3-test.lisp
src/cadr-cli/extensions.lisp
src/cadr-cli/model-services.lisp
src/cadr-cli/extensions/llama/*.lisp
test/cadr-cli/llama-extension-test.lisp
cadr-agent.asd
cadr-cli.asd
docs/parity-map.md
docs/architecture.md
docs/progress/goal-v8.md
```

这里是对 Goal 7 “若需修改 `src/cadr-ai` 则 blocked”的**限定 override
提案**，尚未获批。只允许修改下列冻结对象：

```text
src/cadr-ai/models-runtime.lisp
src/cadr-ai/package.lisp
test/cadr-ai/models-runtime-test.lisp
cadr-ai.asd
```

若实现需要触碰其他 `src/cadr-ai` production object ID，立即 blocked；不得
顺手修改。该项不新增第三方依赖。

### 3.6 已考虑但否决的替代方案

| 方案 | 否决理由 |
|---|---|
| 因本机未部署 llama.cpp 而 skip | 测试是本地 loopback deterministic contract，不是 live block |
| 用现有静态 `define-provider` 冒充 | 无法覆盖动态 catalog、cache-only restore、custom login/check |
| 把 llama/Hugging Face management 放进 `cadr-ai` | 破坏 extension boundary，扩大核心职责 |
| 在 CLI 重写一套 provider runtime | 重复 `models-runtime` 已有 store/auth/dispatch |
| 改现有 `refresh-function` 参数表 | 破坏现有 runtime provider；additive context slot 已足够 |
| 新增 llama wire adapter | inference 已是标准 OpenAI Chat Completions |

**建议裁决：批准上述四个 `cadr-ai` 文件的限定解冻与 additive contract，
其余 `cadr-ai` 继续冻结。**

## 4. 裁决项四：`config.test.ts` 整文件判 N/A

### 4.1 文件内容摘要

固定基线文件共 437 行，只包含 Node/Bun 安装来源与 JS package-manager
self-update contract：

| 内容 | 固定基线 |
|---|---|
| 临时 npm/pnpm/yarn/bun global install layout 与 fake CLI helpers | `packages/coding-agent/test/config.test.ts:1-147` |
| 从 Windows `.pnpm` path 检测 pnpm；unknown wrapper 不自更新 | `packages/coding-agent/test/config.test.ts:148-168` |
| npm custom prefix、exact version、package rename、configured/empty `npmCommand`、display quoting、Windows prefix | `packages/coding-agent/test/config.test.ts:170-293` |
| bun global install | `packages/coding-agent/test/config.test.ts:295-306` |
| pnpm rename 与 pnpm v11 store resolution | `packages/coding-agent/test/config.test.ts:308-375` |
| yarn/bun rename 时先卸载旧 package | `packages/coding-agent/test/config.test.ts:377-426` |
| install path 不可写时禁止 self-update 并给出说明 | `packages/coding-agent/test/config.test.ts:428-436` |

对应 production contract 明确枚举
`"bun-binary" | "npm" | "pnpm" | "yarn" | "bun" | "unknown"`，出处
`packages/coding-agent/src/config.ts:25-94`；package-manager command 构造在
`:115-186`，global ownership/writability/self-update gate 在
`:304-355`。

### 4.2 N/A 理由

cadr 是由 SBCL `build.sh` 生成的单一 native executable，不由 npm、pnpm、
yarn、bun 或 Bun embedded filesystem 安装。让 Lisp binary 检测
`node_modules`、`.pnpm`、`PNPM_HOME`、`bun pm bin -g` 或执行 JS package
uninstall/install，不是语义移植，而是把原版仅因 JavaScript 发布方式存在的
机制硬塞进另一构建生态。

这正是全局原则允许保留的“构建方式必然差异”。当前 cadr 的 self-update
边界是明确提示用户使用 Common Lisp build/install method：
`src/cadr-cli/package-manager.lisp:849-877,1187-1197`。

N/A 只适用于 `config.test.ts` 这一个 package-manager/self-update 文件，不
扩张到版本检查：

- `packages/coding-agent/test/version-check.test.ts` 仍须逐文件对齐；
- 当前 `src/cadr-cli/sdk-services.lisp:240-398` 与
  `test/cadr-cli/part-b-sdk-test.lisp:152-323` 的 remote version-check 属于
  applicable behavior；
- extension/resource Git package update 也不因本裁决变成 N/A。

批准后的账本动作仅为把
`packages/coding-agent/test/config.test.ts` 从 `M` 改为经用户裁决的 `N/A`，
并在 parity-map 差异说明中登记“SBCL binary build/install method”。不新增
production code，不伪造 C。

### 4.3 已考虑但否决的替代方案

| 方案 | 否决理由 |
|---|---|
| 在 cadr 模拟 npm/pnpm/yarn/bun 检测 | 引入不适用于 SBCL binary 的新机制与 Node package coupling |
| 把 `build.sh` 更新命令解释为同一 contract 并标 C | install ownership、rename、global root、writability 语义完全不同 |
| 用已实现 remote version-check 代替并标 C | 违反整文件从严原则；version notification 不是 self-update |
| 保持永久 M | 已有明确且仅由构建生态导致的 N/A 边界，人工裁决后应如实入账 |

**建议裁决：批准该文件整文件 N/A；不影响 `version-check.test.ts` 或资源包
update 行。**

## 5. 实现与验收顺序

用户已逐项批准第 1–4 项；以下顺序作为已执行的授权约束保留。

若有批准，顺序固定：

1. 只把获批项移入“本 goal 允许变更”清单；
2. 第 1 项先更新 dependency audit/README 并单独提交授权记录，再加依赖；
3. 每项测试先行，保留可归因的红门禁；
4. 第 2/3 项先跑 legacy extension compatibility，再做生产实现；
5. specific tests 全绿后跑 `./scripts/test-cl.sh`；
6. 按逻辑分组提交，工作区必须干净；
7. 重算 extension export SHA/object IDs，更新 architecture；
8. 只有全部获批项完成、提交且全量复验后，才允许更新 parity 计数。

建议裁决格式：

```text
第 1 项：批准 / 否决
第 2 项：批准 / 否决
第 3 项：批准 / 否决
第 4 项：批准 / 否决
```
