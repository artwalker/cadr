# Goal 16 Part B：产品身份收敛提案

状态：**blocked，等待用户逐项裁决。** 固定实现基线为
`3dbb58b895a1f732d6354233e91d6981b0a35c09`，Part A 审计提交为
`dcba371ff`。本提案不授权 Part C；事实清单见
`docs/identity-audit.md`。

## 1. 边界与不变量

本提案只处理产品身份、上游端点默认值和旧环境变量命名空间。以下不变量在
全部实现批次中保持：

1. 不改 `origin=git@github.com:badlogic/pi-mono.git`；规范 Cadr remote 仍为
   `backup=https://github.com/artwalker/cadr.git`。
2. 不改 provider payload、会话 entry、tool result、JSON/RPC wire、默认模型、
   默认工具、安全模型或扩展 API。
3. 不新增第三方依赖、网络服务、兼容层或 telemetry。
4. Radius 的注册 client、API path、wire/storage 字段和 protocol 名不因字符串中
   含 `pi` 而改名。
5. 所有值先由独立合同测试锁定，再修改生产实现；每批独立提交、独立全量
   验证、可独立回滚。

## 2. 已预裁的第三方归因值

这六组值已由用户在 Goal 16 规格中批准，Part C 直接实施，不再要求重复裁决：

| 合同 | 当前值 | 目标值 | 基线位置 | 最小 Cadr 文件面 |
|---|---|---|---|---|
| 版本检查 User-Agent | `pi/<version> (...)` | `cadr/<version> (...)` | Cadr 残留，无须保留 | `src/cadr-cli/support/resume-version-git.lisp`、对应测试 |
| OpenRouter attribution | `https://pi.dev` / `pi` | `https://github.com/artwalker/cadr` / `cadr` | `packages/ai/src/providers/openrouter.ts` 的客户端归因语义 | `src/cadr-cli/support/headers.lisp`、对应测试 |
| NVIDIA billing origin | `Pi` | `cadr` | provider 专属归因字段 | 同上 |
| Cloudflare User-Agent | `pi-coding-agent` | `cadr-coding-agent` | provider 专属客户端标识 | 同上 |
| OpenCode client | `pi` | `cadr` | provider 专属客户端标识 | 同上 |
| xAI device-code referrer | `pi` | `cadr` | `packages/ai/src/auth/oauth/xai.ts` 的 device-code 请求 | `src/cadr-ai/oauth/providers/xai.lisp`、`test/cadr-ai/goal12-auth-test.lisp`、live OAuth 门禁 |

xAI 的 `client_id`、scope、token endpoint 均不改。Part C 必须真实发起一次 device
authorization 请求；若服务端因 referrer 拒绝，立即停止该批、回滚单值并把
`referrer=pi` 改判为有证据的 `功能约束保留`，不得靠 fixture 宣告成功。

## 3. 决策 B1：`/share` 默认禁用，显式配置后才外发

### 3.1 确切需求与事实

`src/cadr-cli/support/changelog-share.lisp:262-323` 先把完整会话 HTML 交给
`gh gist create --public=false`，再把 gist ID 拼入 viewer URL。当前默认 viewer
为 `https://pi.dev/session/`；也就是说存储在 GitHub Gist，但会话的读取和呈现
依赖上游 viewer 代码。这是用户数据外发边界，不是普通品牌字符串。

### 3.2 建议裁决

**默认禁用。** 只有显式设置非空 `CADR_SHARE_VIEWER_URL`，或测试/调用方显式
传入 `viewer-base-url` 时才允许分享。必须在运行 `gh auth status` 和创建 Gist
之前解析 viewer；未配置时返回精确错误：

```text
Session sharing is not configured. Set CADR_SHARE_VIEWER_URL to a trusted viewer URL.
```

这样不会生成无 viewer 可用的孤儿 Gist，也不会把会话默认交给上游代码。
`share-viewer-url` 的显式参数调用保持有效。

### 3.3 最小实现面

- `src/cadr-cli/support/changelog-share.lisp`
- `test/cadr-cli/goal9-a2-workflows-test.lisp` 及现有 share 合同所在测试
- `README.md`、`CHANGELOG.md`

不引入 Cadr 托管服务；`cadr.dev` 上线后只需配置默认 deployment，不重写分享
流程。

### 3.4 替代方案及否决理由

- **保留 pi.dev 默认值**：功能连续，但继续把 Cadr 会话交给未受本项目控制的
  上游 viewer，身份和信任边界均未收口，否决。
- **现在写死 `https://cadr.dev/session/`**：服务尚不存在，会把可解释的禁用变成
  隐蔽的坏链接，否决。
- **只改成 GitHub Gist URL**：改变基线交互，且 raw Gist 不是 session viewer，
  否决。

### 3.5 回滚

该批只需回滚 share 默认策略提交；显式 `CADR_SHARE_VIEWER_URL` 路径和生成的
HTML 均不受影响。

## 4. 决策 B2：版本检查默认禁用，显式配置 Cadr endpoint

### 4.1 确切需求与事实

`src/cadr-cli/sdk/cache-version.lisp:272-413` 固定 GET
`https://pi.dev/api/latest-version`，再把上游 `0.83.x` 与 Cadr `0.2.0` 比较。
网络请求本身不含会话数据，但比较对象不是同一产品，结果在语义上必错。

### 4.2 建议裁决

新增唯一配置 `CADR_VERSION_CHECK_URL`：

- 未设置或空值：自动版本检查关闭，不发网络请求；
- 非空：以该 URL 查询，继续复用现有 timeout、JSON normalization、版本比较和
  静默网络失败语义；
- `CADR_OFFLINE` 或 `CADR_SKIP_VERSION_CHECK` 非空时，即使配置 URL 也不请求；
- Lisp 内部函数重命名为 `get-latest-cadr-release`、
  `get-latest-cadr-version`、`check-for-new-cadr-version`、
  `normalize-latest-cadr-release`；不保留旧符号 alias。

`version.sexp` 仍是当前版本单一来源。未来 `cadr.dev` 上线时只需提供合同兼容
endpoint 并决定是否赋默认值。

### 4.3 最小实现面

- `src/cadr-cli/sdk/cache-version.lisp`
- `src/cadr-cli/support/resume-version-git.lisp`
- `src/cadr-cli/package.lisp`
- 现有 version/cache 测试、`README.md`、`CHANGELOG.md`

### 4.4 替代方案及否决理由

- **继续查询 pi.dev**：会把上游发布误报为 Cadr 更新，否决。
- **立即写死 cadr.dev**：目标尚不可用，冷启动将产生无意义请求，否决。
- **删除版本检查**：基线能力未来仍需恢复，删除会把暂时无服务变成永久阉割，
  否决。
- **保留 `*-pi-*` alias**：这是 0.2 阶段的内部/Lisp API 身份错误，且项目规则
  不默认保留兼容；alias 会让身份门禁永久豁免旧名，否决。

### 4.5 回滚

回滚本批即可恢复旧 endpoint；不改变本地配置文件或会话格式。

## 5. 决策 B3：14 个 `PI_*` 环境变量硬切为 `CADR_*`

### 5.1 建议裁决

**不设兼容期，不读取旧名，不打印弃用警告。** 精确映射如下：

| 旧名 | 新名 |
|---|---|
| `PI_CACHE_RETENTION` | `CADR_CACHE_RETENTION` |
| `PI_CONFIG_DIR` | `CADR_CONFIG_DIR` |
| `PI_EVAL_ARTIFACT_DIR` | `CADR_EVAL_ARTIFACT_DIR` |
| `PI_EXPERIMENTAL` | `CADR_EXPERIMENTAL` |
| `PI_MODEL` | `CADR_EVAL_MODEL` |
| `PI_OFFLINE` | `CADR_OFFLINE` |
| `PI_PROVIDER` | `CADR_EVAL_PROVIDER` |
| `PI_RADIUS_SERVER_URL` | `CADR_RADIUS_SERVER_URL` |
| `PI_RADIUS_URL` | `CADR_RADIUS_URL` |
| `PI_SERVER_CADR_PATH` | `CADR_SERVER_CADR_PATH` |
| `PI_SERVER_DIR` | `CADR_SERVER_DIR` |
| `PI_SHARE_VIEWER_URL` | `CADR_SHARE_VIEWER_URL` |
| `PI_SKIP_VERSION_CHECK` | `CADR_SKIP_VERSION_CHECK` |
| `PI_TIMING` | `CADR_TIMING` |

影响是使用这些旧名的本地 shell/service 配置必须一次迁移。理由：项目已在
0.2.0 移除 `PI_CL_*` 过渡兼容，README 明确把该迁移称为唯一 namespace break；
再增加静默 alias 会恢复双重决策源，违背本 goal 的单一来源目标。弃用警告也是
基线没有的新机制，既制造额外输出通道又不能消除旧名，故不引入。

### 5.2 最小实现面

- `src/cadr-ai/providers/bedrock.lisp`
- `src/cadr-cli/tool-manager.lisp`、`src/cadr-cli/support/html.lisp`、
  `src/cadr-cli/support/timings.lisp`、`src/cadr-cli/sdk/cache-version.lisp`
- `src/cadr-evals/harness.lisp`、`src/cadr-evals/reporter.lisp`
- `src/cadr-server/config.lisp`、`src/cadr-server/radius.lisp`、
  `src/cadr-server/rpc-process.lisp`
- 对应测试、构建/进程 harness、`README.md`、`CHANGELOG.md`

`scripts/render-diff.py` 为固定 TypeScript 基线设置/清理的 `PI_OFFLINE`，
`scripts/goal11-cold-start.py` 的 `PI_CODING_AGENT_DIR` 指基线 checkout；二者不在
迁移面，保留。

### 5.3 替代方案及否决理由

- **Cadr 优先、PI 后备**：继续允许旧身份左右运行时行为，身份门禁无法
  fail-closed，否决。
- **一个 release 的 warning 期**：项目没有已承诺的 `PI_*` Cadr 公共合同，且
  会增加基线不存在的 warning 机制，否决。
- **自动改写 shell/service 配置**：跨出仓库控制面并可能改坏用户环境，否决。

### 5.4 回滚

各 system 按批可独立回滚；迁移只读环境，不写用户文件，因此无数据回滚。

## 6. 决策 B4：其余自由身份值一并替换

建议把 Part A 新发现和规格点名的自由值作为一组批准；这些不涉及鉴权或外部
schema：

| 当前值 | 目标值 | 位置/影响 |
|---|---|---|
| `/changelog` 的 `earendil-works/pi` | `https://github.com/artwalker/cadr` | `src/cadr-cli/support/changelog-share.lisp:135-161`；用户浏览器链接，`origin` 不动 |
| `pi-wsl-clip-` | `cadr-wsl-clip-` | `src/cadr-cli/interactive/clipboard.lisp:323-329`；临时文件名 |
| notify 示例标题 `Pi` | `Cadr` | `examples/extensions/notify.lisp:28`；桌面通知 |
| localStorage `pi-share:v1:sidebar-width` | `cadr-share:v1:sidebar-width` | `src/cadr-agent/export-html/template.js:1666`；浏览器偏好会重置一次 |
| synthetic tool call ID `pi_tool_load_` | `cadr_tool_load_` | `src/cadr-ai/providers/openai.lisp:201-207`；provider/session ID，算法与 payload 不变 |
| `Radius Pi` / `cadr-radius-pi-` | `Radius instance` / `cadr-radius-instance-` | `src/cadr-server/radius.lisp:468,553,568,579,627`；日志与线程名，远端字段不变 |

导出 HTML 的 `pi-url-params`、`pi-share-base-url` 不在本组直接替换：若 B1
批准为默认禁用，它们作为现有上游 viewer 注入合同留在 allowlist；未来自建
viewer 时与 viewer 一起原子迁移，避免只改一端造成静默失效。

最小文件面限于 Part A 表格指向的生产文件、对应现有测试、README/CHANGELOG。
任何新的第三方资产、endpoint 或协议字段都不在授权内。

替代方案“只改用户看得见的值”被否决：session ID、临时文件和线程名虽不常见，
仍会进入日志/持久化/调试面；保留会继续制造半改状态。整组可由一个自由身份
批次提交回滚，不迁移已有 session ID。

## 7. 决策 B5：功能合同与溯源 allowlist

建议逐条确认以下保留；它们不是“漏改”：

| 保留值 | 依据 | 未来解除条件 |
|---|---|---|
| Radius `pi-gateway` | 2026-08-04 live discovery 返回相同 `clientId` 与 scope | Radius 注册 Cadr client |
| `radius.pi.dev` | 真实 Radius provider/presence endpoint，根与 discovery 均 HTTP 200 | Radius 正式迁域 |
| Radius `/pis/*`、`radiusPiId` | 远端 API、现有 storage/RPC schema | 服务端与迁移方案同步升级 |
| `pi-messages` | Radius wire dialect 名 | 协议正式改名并有兼容迁移 |
| package.json manifest key `pi` | 基线扩展生态 schema | 生态发布新 schema 并迁移 |
| `@earendil-works/pi-coding-agent` detector | eval 专门识别 legacy TS 扩展输出 | 该 eval 目标取消 |
| generated `pi-ai` provenance | 固定 catalog 来源 | 重新生成且来源改变 |
| `aligned with pi ...` | 发布对齐声明 | 项目不再以该基线发布 |
| 历史 announcement、selector 来源 docstring | 真实历史/内部溯源 | 删除对应历史组件或溯源需求 |
| render diff、payload export、基线脚本中的 pi | 固定参考输入 | 更换基线项目 |
| docs/tests/fixtures 中明确标为 baseline/migration 的 pi | 审计与对拍证据 | 对应证据退役 |

allowlist 必须以精确路径、行合同或固定字符串登记，禁止目录级放行。

## 8. 决策 B6：单一来源与实施批次

### 8.1 单一来源

复用 `src/cadr-ai/support/release.lisp`，不新建 `cadr-core` 产品策略层。后者已在
architecture 中明确只承载无产品语义的失败安全原语。release 模块新增私有的
产品 slug、显示名、规范仓库 URL，以及由它们派生的 attribution 值；
`cadr-cli`/server 继续像当前读取 `cadr-release-identity` 一样从 `cadr-ai`
读取。**不新增 public export**，避免把内部品牌常量扩成稳定 Lisp API。

环境变量名和可配置 endpoint 由各 feature owner 保存，但测试须断言它们以
`CADR_` 开头且上游 fallback 不存在；这些是配置合同，不复制产品显示文本。

### 8.2 Part C 批次

1. **C1：身份源与预裁 attribution**——release identity、UA/header、xAI；真实
   xAI device-code 请求后提交。
2. **C2：端点策略**——按 B1/B2 实施 share 与版本检查；不与环境迁移混杂。
3. **C3：环境变量硬切**——按 system 分组更新 14 个变量及进程 harness。
4. **C4：其余自由值**——仓库链接、临时文件、HTML storage、synthetic ID、
   Radius 文案、example。
5. **C5：文档收尾**——README、CHANGELOG、architecture 与验收报告；逐项记录
   已批准差异和迁移表。

每批先红后绿，运行 `./scripts/test-cl.sh` 与相关 live/harness；涉及 source 后
重建根二进制并跑 `./scripts/verify.sh`，二进制时间必须新于最后一次 source
改动。

### 8.3 Part D 门禁

新增一个机械扫描器和受跟踪的精确 allowlist，覆盖 `src/`、`examples/`、发行
脚本、README/CHANGELOG 中对外值；新 `pi`、`pi.dev`、上游仓库或 `PI_*` 命中
没有精确 disposition 即失败。`verify.sh` 同时跑合成自测与真实全树，真实命中
数必须等于 allowlist 汇总数。`docs/development-policy.md` 增加“产品身份单一
来源”常设规则。

## 9. 请求逐项裁决

1. **B1**：`/share` 无 `CADR_SHARE_VIEWER_URL` 时默认禁用，且在创建 Gist 前
   fail closed。
2. **B2**：版本检查无 `CADR_VERSION_CHECK_URL` 时默认禁用；配置后才请求。
3. **B3**：14 个 `PI_*` 硬切，不设 alias 或 warning 兼容期。
4. **B4**：第 6 节自由身份值整组替换；viewer meta 依 B1 暂留精确合同。
5. **B5**：第 7 节功能/溯源 allowlist 逐项确认。
6. **B6**：复用 release identity 作为私有单一来源，并按 C1→C5、D 的批次和
   文件边界实施。

上述裁决前不修改任何生产代码。
