# Goal 16 产品身份全树审计

状态：Part A 审计完成，Part C 已按用户裁决实施；固定审计代码基线为
`3dbb58b895a1f732d6354233e91d6981b0a35c09`。本文件只记录事实与判定，
不授权 Part C 实现。

## 1. 范围与方法

审计覆盖所有会进入发行镜像、运行时请求、用户产物或开发/验收入口的受跟踪
文件：`src/`、`examples/`、`scripts/`、根 ASDF/构建文件、README、CHANGELOG
与 CI。`docs/`、测试和 fixture 另作溯源/对拍保留项核查，不把基线字样误判为
产品自我标识。

机械枚举使用下列集合，不靠手挑文件：

```sh
rg -n --hidden -i '(\bpi\b|\bPI_[A-Z]|pi\.dev|badlogic|earendil-works|pi-mono|pi-ai|pi-coding|pi-gateway|pi-wsl)' \
  .github examples src scripts *.asd README.md CHANGELOG.md
rg -o --no-filename '\bPI_[A-Z0-9_]+' src | sort -u
rg -n 'https://github\.com/(badlogic|earendil-works|artwalker)' \
  README.md CHANGELOG.md src examples scripts .github
git remote -v
```

第二条实际得到 **14 个**不同的生产环境变量，不是规格初查中含重复项的 15
个。数学常量 `pi`、`API_KEY` 中的子串、vendor 语法表中的语言内建符号均已
排除。判定含义：

- `须替换`：自由可改的 Cadr 自我标识或命名空间；
- `功能约束保留`：值属于外部协议/注册客户端，改动会直接破坏已核实合同；
- `正当保留`：基线溯源、对齐声明、迁移或固定对拍输入；
- `低优先`：仅实现内部可见，但仍应在同批重命名以消除半改状态；
- `已合规`：已经是 Cadr 身份，作为门禁正例。

## 2. 已合规的身份锚点

| 位置 | 当前值与可见对象 | 判定 | 依据 |
|---|---|---|---|
| `src/cadr-ai/support/release.lisp:3-21` | `cadr 0.2.0 · aligned with pi ...`；用户、`--version`、Radius | `已合规` | 产品名为 Cadr；后半是有意的基线对齐声明。版本单一来源已经存在。 |
| `src/cadr-cli/system-prompt.lisp:4` | `You are cadr`；模型 | `已合规` | 模型侧身份正确。 |
| `src/cadr-ai/oauth/pkce.lisp:52,303` | OpenAI `originator=cadr`；OpenAI | `已合规` | Goal 9 已裁决并经真实 OAuth 验证。 |
| `src/cadr-ai/oauth/page.lisp:3-4` | Cadr 自有 cons-cell SVG；用户浏览器 | `已合规` | 不再使用 pi 品牌资产。 |
| `src/cadr-cli/bootstrap/sessions.lisp:1341` | `cadr-session-<ISO>_<uuid>.html`；用户文件 | `已合规` | 产品前缀正确。 |
| `src/cadr-cli/support/resume-version-git.lisp:4-47` | `cadr --session ...`；退出后 stdout | `已合规` | CLI 名正确。 |
| `src/cadr-core/paths.lisp`（owner）、`src/cadr-cli/migration.lisp`（迁移） | `~/.cadr/agent/`；用户磁盘 | `已合规` | Goal 18 起布局对齐基线 `~/.pi/agent/`；全部路径经 cadr-core owner 单一派生。 |
| Git remote `backup` | `https://github.com/artwalker/cadr.git`；维护者 | `已合规` | 规范仓库。`origin=git@github.com:badlogic/pi-mono.git` 是上游同步 remote，按规格不改。 |

这些锚点目前仍散在多个包中；Part C 必须让可复用的产品 slug、显示名和规范
仓库 URL 从既有 release identity 单一来源派生，不能再复制字符串。

## 3. 发往第三方服务的标识

| 位置 | 当前值 | 可见对象 | 判定 | 依据与目标值 |
|---|---|---|---|---|
| `src/cadr-cli/support/resume-version-git.lisp:80-85` | `pi/<version> (...; sbcl/...)` | 版本检查服务 | `须替换`（已裁决） | 纯 User-Agent，自由可改；目标 `cadr/<version> (...)`。函数名 `pi-user-agent` 同批重命名。 |
| `src/cadr-cli/support/headers.lisp:29` | `HTTP-Referer: https://pi.dev` | OpenRouter | `须替换`（已裁决） | 用量归因，不鉴权；在 `cadr.dev` 未上线前目标为规范仓库 `https://github.com/artwalker/cadr`。 |
| `src/cadr-cli/support/headers.lisp:30` | `X-OpenRouter-Title: pi` | OpenRouter | `须替换`（已裁决） | 目标 `cadr`。 |
| `src/cadr-cli/support/headers.lisp:35` | `X-BILLING-INVOKE-ORIGIN: Pi` | NVIDIA | `须替换`（已裁决） | 计费归因，不鉴权；目标 `cadr`。 |
| `src/cadr-cli/support/headers.lisp:44` | `User-Agent: pi-coding-agent` | Cloudflare | `须替换`（已裁决） | 目标 `cadr-coding-agent`。 |
| `src/cadr-cli/support/headers.lisp:53-54` | `x-opencode-client: pi` | OpenCode | `须替换`（已裁决） | session ID 头不变；client 目标 `cadr`。 |
| `src/cadr-ai/oauth/providers/xai.lisp:132-140` | 设备码 `referrer=pi` | xAI | `须替换`（已裁决） | client ID 与 scope 不变，referrer 目标 `cadr`；Part C 须真实发起一次设备码请求。 |
| `src/cadr-ai/auth/radius-cloudflare.lisp:4-16`、`src/cadr-ai/oauth/providers/radius.lisp:8-10,24-31,48-55,87-115` | OAuth `client_id=pi-gateway` | Radius | `功能约束保留` | 2026-08-04 实测 `GET https://radius.pi.dev/v1/oauth` 为 HTTP 200，discovery 明确返回 `clientId:"pi-gateway"`、对应 token/device endpoints 与 `gateway offline_access` scope；这是注册客户端 ID，不是自由归因字段。 |

User-Agent、OpenRouter、NVIDIA、Cloudflare、OpenCode 五组归因值和 xAI
referrer 已由用户在 Goal 16 规格中预裁，不再等待值级裁决。Radius 是本审计
唯一需要以注册合同为由保留的第三方 client 标识。

## 4. 上游服务端点与数据流

| 位置 | 当前值与数据流 | 判定 | 依据 |
|---|---|---|---|
| `src/cadr-cli/support/changelog-share.lisp:252-260,262-323` | `/share` 先把完整会话 HTML 以 `gh gist create --public=false` 上传到 GitHub Gist，再生成 `https://pi.dev/session/#<gist-id>`。URL fragment 不随首个 HTTP 请求发送，但上游 viewer 的浏览器代码可取得 gist ID 并读取会话。 | `须裁决` | 已有 `CADR_SHARE_VIEWER_URL`，但仍读取旧 `PI_SHARE_VIEWER_URL` 且默认指向上游。涉及会话外发与上游页面代码，不能自行选默认值。 |
| `src/cadr-cli/sdk/cache-version.lisp:272-359,388-413` | GET `https://pi.dev/api/latest-version`，发送当前版本及 OS/SBCL/架构 User-Agent，读取上游 package release，并与 Cadr `0.2.0` 比较。 | `须裁决` | 无会话数据，但语义错误：上游 `0.83.x` 不是 Cadr 更新。当前 URL 硬编码且无 Cadr URL 配置。 |
| `src/cadr-ai/providers/definitions.lisp:647-664` | Radius provider 默认 `https://radius.pi.dev`，协议 `:pi-messages`。 | `功能约束保留` | 这是名为 Radius 的真实 provider endpoint，不是 Cadr 官网。2026-08-04 实测根路径和 `/v1/oauth` 均 HTTP 200。`RADIUS_GATEWAY_URL` 可覆盖模型网关。 |
| `src/cadr-server/radius.lisp:151-166` | cadr-server presence 默认 `https://radius.pi.dev/v1/`，可由 `CADR_RADIUS_SERVER_URL` 或 `CADR_RADIUS_URL` 覆盖。 | `功能约束保留` | 同一 Radius API；代码实际调用 `machines/*`、`pis/*` 注册/心跳/断开。旧 `PI_RADIUS_*` fallback 另按环境变量案删除。 |

`/share` 并非直接 POST 到 pi.dev；真正存储是 GitHub Gist。但把会话交给上游
viewer 代码处理仍是外部信任边界，不能用“fragment 不上服务器”淡化。

## 5. 生产环境变量：14 个完整清单

| 旧变量 | 位置 | 当前优先级 | 目标名 | 判定与影响 |
|---|---|---|---|---|
| `PI_CACHE_RETENTION` | `src/cadr-ai/providers/bedrock.lisp:338-348` | 唯一名称 | `CADR_CACHE_RETENTION` | `须替换`；Bedrock long cache 配置。 |
| `PI_CONFIG_DIR` | `src/cadr-server/config.lisp:16-24` | `CADR_CONFIG_DIR` 后备 | `CADR_CONFIG_DIR` | `须替换`；旧名仅兼容。 |
| `PI_EVAL_ARTIFACT_DIR` | `src/cadr-evals/reporter.lisp:23-31` | `CADR_EVAL_ARTIFACT_DIR` 后备 | `CADR_EVAL_ARTIFACT_DIR` | `须替换`；旧名仅兼容。 |
| `PI_EXPERIMENTAL` | `src/cadr-cli/support/html.lisp:46-51` | `CADR_EXPERIMENTAL` 后备 | `CADR_EXPERIMENTAL` | `须替换`；旧名仅兼容。 |
| `PI_MODEL` | `src/cadr-evals/harness.lisp:92-100` | `CADR_EVAL_MODEL` 后备 | `CADR_EVAL_MODEL` | `须替换`；仅 eval selection。 |
| `PI_OFFLINE` | `src/cadr-cli/tool-manager.lisp:26-28`、`src/cadr-cli/sdk/cache-version.lisp:323-331,388-399` | 唯一名称 | `CADR_OFFLINE` | `须替换`；控制工具下载与版本检查。 |
| `PI_PROVIDER` | `src/cadr-evals/harness.lisp:83-91` | `CADR_EVAL_PROVIDER` 后备 | `CADR_EVAL_PROVIDER` | `须替换`；仅 eval selection。 |
| `PI_RADIUS_SERVER_URL` | `src/cadr-server/radius.lisp:153-158` | `CADR_RADIUS_SERVER_URL` 后备 | `CADR_RADIUS_SERVER_URL` | `须替换`；旧名仅兼容。 |
| `PI_RADIUS_URL` | `src/cadr-server/radius.lisp:159-164` | `CADR_RADIUS_URL` 后备 | `CADR_RADIUS_URL` | `须替换`；旧名仅兼容。 |
| `PI_SERVER_CADR_PATH` | `src/cadr-server/rpc-process.lisp:259-264` | `CADR_SERVER_CADR_PATH` 后备 | `CADR_SERVER_CADR_PATH` | `须替换`；旧名仅兼容。 |
| `PI_SERVER_DIR` | `src/cadr-server/config.lisp:10-15` | `CADR_SERVER_DIR` 后备 | `CADR_SERVER_DIR` | `须替换`；旧名仅兼容。 |
| `PI_SHARE_VIEWER_URL` | `src/cadr-cli/support/changelog-share.lisp:252-260` | `CADR_SHARE_VIEWER_URL` 之前，旧名反而优先 | `CADR_SHARE_VIEWER_URL` | `须替换`；还存在优先级倒置。 |
| `PI_SKIP_VERSION_CHECK` | `src/cadr-cli/sdk/cache-version.lisp:388-399` | 唯一名称 | `CADR_SKIP_VERSION_CHECK` | `须替换`；取决于版本检查默认裁决。 |
| `PI_TIMING` | `src/cadr-cli/support/timings.lisp:3-4` | 唯一名称 | `CADR_TIMING` | `须替换`；启动计时。 |

`scripts/goal11-cold-start.py` 的 `PI_CODING_AGENT_DIR` 和
`scripts/render-diff.py` 的 `PI_OFFLINE` 只用于清理/驱动固定 TypeScript 基线环境，
不是 Cadr 生产变量，判 `正当保留`。

## 6. 仓库链接与其余残留

| 位置 | 当前值 | 可见对象 | 判定 | 依据与目标 |
|---|---|---|---|---|
| `src/cadr-cli/support/changelog-share.lisp:135-161` | `/changelog` 将相对链接及 badlogic/earendil 链接改写到 `https://github.com/earendil-works/pi` | 用户浏览器 | `须替换` | 目标统一为 `https://github.com/artwalker/cadr`；私有仓库当前可能要求登录，但公开后 URL 不变。不得改 `origin`。 |
| `src/cadr-cli/interactive/clipboard.lisp:323-329` | `pi-wsl-clip-<uuid>.png` | 临时目录/诊断 | `须替换` | 目标 `cadr-wsl-clip-<uuid>.png`。 |
| `examples/extensions/notify.lisp:28` | 通知标题 `Pi` | 用户桌面 | `须替换` | 目标 `Cadr`。示例也属于发行用户面，不能漏扫。 |
| `src/cadr-agent/export-html/template.js:1666` | localStorage `pi-share:v1:sidebar-width` | 导出 HTML/浏览器 | `须替换` | 目标 `cadr-share:v1:sidebar-width`；只会重置既有浏览器侧宽度偏好。 |
| `src/cadr-agent/export-html/template.js:23,1098` | meta `pi-url-params`、`pi-share-base-url` | 导出 HTML/上游 viewer iframe | `功能约束保留（条件式）` | Cadr exporter 不生成这些 meta；注释及全树唯一消费者表明它们由当前上游 viewer 注入。若保留 pi.dev viewer，名字必须保留；若禁用/改指 viewer，应与新 viewer 一并改为 `cadr-*`。 |
| `src/cadr-ai/providers/openai.lisp:201-207` | synthetic call ID `pi_tool_load_<hash>` | provider、会话 | `须替换` | 不参与鉴权；目标 `cadr_tool_load_<hash>`。 |
| `src/cadr-server/radius.lisp:468,553,568,579` | 用户/日志文案 `Radius Pi` | stderr/日志 | `须替换` | 这是自由文案，不是 wire；目标 `Radius instance`。 |
| `src/cadr-server/radius.lisp:627` | thread `cadr-radius-pi-<id>` | debugger/线程列表 | `低优先` | 半改状态；目标 `cadr-radius-instance-<id>`。 |
| `src/cadr-cli/sdk/cache-version.lisp:299-403`、`src/cadr-cli/package.lisp:118-121` | `get/check-latest-pi-*` 等导出符号 | Lisp API/内部 | `须替换` | 功能将查询 Cadr release；目标 `*-cadr-*`，不保留上游名 alias，除非用户在 Part B 另行要求。 |
| `src/cadr-cli/support/resume-version-git.lisp:80` | `pi-user-agent` 函数名 | 内部 | `低优先` | 与 UA 值同批改为 `cadr-user-agent`。 |

## 7. 必须保留的上游/外部合同

| 位置 | 保留内容 | 判定 | 具体理由 |
|---|---|---|---|
| `src/cadr-ai/auth/radius-cloudflare.lisp:13`、`src/cadr-ai/oauth/providers/radius.lisp:9` | `pi-gateway` | `功能约束保留` | Radius live discovery 明确声明注册 client ID；改名会使授权码、device-code、refresh 三条 token 流使用未注册 client。 |
| `src/cadr-server/radius.lisp:535,639,698` | `pis/*` API path | `功能约束保留` | 远端 Radius API 的资源路径；不是本地产品名。 |
| `src/cadr-server/protocol.lisp:44`、`src/cadr-server/storage.lisp:83-114` | `radiusPiId` | `功能约束保留` | Radius 返回对象 ID 的本地 wire/持久化字段；改名会破坏现存 `instances.json` 与 server RPC。 |
| `src/cadr-ai/provider.lisp:38,117-118`、`src/cadr-ai/providers/pi-messages.lisp`、`src/cadr-ai/providers/definitions.lisp:650-651` | `pi-messages` protocol 名 | `正当保留` | 指 Radius 所使用的上游 wire dialect，类似 `openai-responses`，不是 Cadr 自称 pi。 |
| `src/cadr-cli/packages/manifest.lisp:9-29,128` | package.json 的 `"pi"` manifest key | `功能约束保留` | 基线扩展生态的外部 manifest schema；改名会让现有 package 的 extensions/skills/prompts/themes 全部不可发现。函数名 `read-package-pi-manifest` 准确描述该外部 schema。 |
| `src/cadr-evals/suites.lisp:239-246` | `@earendil-works/pi-coding-agent` | `正当保留` | 只用于检测生成扩展是否仍引用 legacy TypeScript API；是审计输入，不是身份。 |
| `src/cadr-ai/models.generated.lisp:1`、`src/cadr-ai/image-models.generated.lisp:1` 及对应 refresh scripts | `pi-ai 0.83.0` 来源注释 | `正当保留` | 固定 catalog 的可审计溯源。 |
| `src/cadr-ai/support/release.lisp:10-21` | `aligned with pi v0.84.1 (+0, 53fa77ccd)` | `正当保留` | 版本关系声明，规格明确要求保留。 |
| `src/cadr-cli/interactive/components/announcement.lisp:3-40` | `pi has joined Earendil` 与原博客 URL | `正当保留` | 这是移植的历史 announcement 组件，描述 2026-04-08 已发生的上游事件；改成 Cadr 会制造假历史，且默认界面不启用。 |
| `src/cadr-cli/interactive/selectors/common.lisp:118,128` | `Pi Text component` docstring | `正当保留` | 仅内部说明其对拍来源和布局语义。 |
| `scripts/render-diff.py`、`scripts/goal11-pi-baseline-bench.mjs`、`scripts/export-ts-payloads.ts`、`cadr-evals.asd:30` | pi baseline 名、固定 commit/package | `正当保留` | 对拍与溯源输入；替换会让门禁失去对象。 |
| README、CHANGELOG、`docs/`、tests/fixtures 中明确写作“original/aligned/baseline/migration”的 pi 引用 | 上游说明 | `正当保留` | 对外身份与来源致谢必须区分；身份门禁需逐条 allowlist，不可全局删除。 |

## 8. 结论

审计没有发现第二个具备注册白名单证据的归因字段；除 Radius client/API 合同
外，所有对外自称 pi 的值均应替换。问题不止规格列出的五处：环境变量有 14
个，另发现导出 HTML storage/meta、通知示例、provider synthetic call ID、Radius
自由文案与导出 Lisp API 名。

Part C 的门禁必须 fail-closed：产品源码中新出现 `pi`/上游域名/仓库名时，只有
本文件第 7 节对应的逐条 allowlist 才可通过；不能用目录级或正则级大豁免把
未来残留一起吞掉。

## 9. Part C 实施处置（2026-08-05）

| 批次 | 处置 | 提交 |
|---|---|---|
| C1 | 产品 slug、显示名、规范仓库、默认 viewer 的身份常量组进入 `release.lisp`；第三方 UA/header 与 xAI referrer 统一为 Cadr。xAI 真实 device-code 请求返回 HTTP 200。 | `cc4f1f0e0` |
| C2 | `/share` 默认 viewer 改为 `https://cadr.dev/session/`，支持 `CADR_SHARE_VIEWER_URL` 覆盖并在输出中明示 viewer；版本检查改为仅在 `CADR_VERSION_CHECK_URL` 非空时启用。 | `ac23e11bb` |
| C3 | 14 个生产 `PI_*` 名称按批准映射硬切为 `CADR_*`，无 alias、warning 或旧名 fallback。 | `af8612d95` |
| C4 | changelog 仓库、WSL 临时文件、通知标题、导出 storage key、synthetic tool ID 与 Radius 自由文案全部改为 Cadr；外部协议与基线溯源不动。 | `5eb36c930` |

当前生产源中的旧环境变量已清零；Radius client/API/wire、扩展 manifest、catalog
来源、固定基线工具与 `aligned with pi` 声明继续按第 7 节精确保留。Part D 将该
边界固化为受跟踪 allowlist、合成自测和真实树扫描，不把本审计文本当运行时豁免。

## 10. Goal 17 固定基线门禁扩展复核（2026-08-05）

Goal 17 将呈现、tool result 与 event 对拍扩展为三个真实固定基线驱动器，并把
它们纳入 `verify.sh`。这些驱动器必须在代码中精确区分 `pi` 与 `cadr` 两侧、启动
上游进程、识别上游路径/身份字符串，并仅向上游子进程注入 `PI_OFFLINE`；这些
字样是对拍输入，不是 Cadr 自我标识或运行时兼容入口。

组织拆分同时移动了 config selector、direct user bash 与 package update 的基线
出处注释，但没有改变产品身份。Goal 17 收尾删除了已失效的 Pi 侧调度启发式
注释及对应 disposition；Goal 17 新增固定基线 construction 驱动后，真实树为
**353 个命中、316 条精确
disposition、1 个 digest 锁定 opaque 文件**。allowlist 仍逐行锁定完整文本与出现
次数；任何新增、删除、移动或数量变化都会 fail-closed，不存在目录级豁免。
