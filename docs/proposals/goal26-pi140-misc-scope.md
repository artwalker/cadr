# Goal 26：杂项队列的可见面裁决提案

状态：待裁决。本文只提案，不改实现。

范围是 `docs/acceptance/goal26-pi-140-alignment.md` 队列里这一行：

Windows 外壳探测、`pi update` 的 BOM、扩展加载 `@earendil-works/pi-ai/models`、生成的 models 参考文档、遥测 span。

对照区间是 pi `71023aec1546d6d677a65669c5665c0927ce0dd0`（v1.3.0）到 `4a080252f06caf63a525d7873c5d94d3c23887e0`（v1.4.0）。查阅用 `git log` / `git show` / `git diff`，没有切换 pi 工作树。

Goal 26 只移植 coding-agent、tui、ai 里用户能观察到的行为。`packages/durable`、`packages/chord`、`packages/telemetry` 不在移植范围内。

建议总表：

| 子项 | 建议 |
|---|---|
| Windows 安装目录里的 PowerShell、按 `SystemRoot` 识别旧 WSL `bash.exe`、空 `SystemRoot` 的 `taskkill`、工具包解压不再用 `WINDIR` | port |
| Windows Store 外壳别名（Node `existsSync`） | N/A |
| `pi update` 读取带 BOM 的 `managed-install.json` | N/A |
| 扩展加载 `@earendil-works/pi-ai/models` | N/A |
| 生成的 models 参考文档和 `models.schema.json` 字段说明 | N/A |
| 遥测 span | N/A |

## Windows 外壳探测

两笔提交。

`61060ddf8c17b1755a4d4208613e1e36f2a632be`（2026-09-11，`fix(coding-agent): resolve Windows shells from installation directories`）改了这些文件。

- `packages/coding-agent/src/utils/shell.ts`。`getPowerShellConfig` 在 `PATH` 上的 `pwsh.exe` 之后再找 `%ProgramFiles%\PowerShell\7\pwsh.exe`，在 `PATH` 上的 `powershell.exe` 之后再找 `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`。`isLegacyWslBashPath` 在 `SystemRoot` 是盘符路径时，只认该目录下的 `System32\bash.exe` 和 `Sysnative\bash.exe`。`SystemRoot` 缺失时才退回 `C:\Windows` 的正则。`killProcessTree` 把 `SystemRoot ?? "C:\\Windows"` 改成 `SystemRoot || "C:\\Windows"`，空字符串也改走 `C:\Windows`。
- `packages/coding-agent/src/utils/tools-manager.ts` 的 `getWindowsTarCommand` 不再读 `WINDIR`。只有 `SystemRoot\System32\tar.exe` 存在时才用它，否则用 `PATH` 上的 `tar.exe`。
- `packages/coding-agent/docs/windows.md` 写下上述查找顺序，并说明旧 WSL `bash.exe` 走 stdin。
- 同一提交还改了 `packages/durable/src/env/node.ts` 里的一份拷贝。该包不在 Goal 26 的三包里。

`28bea006be4adb950dcb4f86f9ee5be857bf74ff`（2026-10-19，`fix(coding-agent): accept Windows Store shell aliases`，changelog 记为 #9504）只改 `packages/coding-agent/src/utils/shell.ts`。Node 的 `existsSync` 在 Windows 上多做一次 stat，Microsoft Store 的可执行别名会以 `EACCES` 失败（nodejs/node#36790）。上游改成 `accessSync(path, F_OK)`。提交说明写明，Unix 上这与 `existsSync` 相同，查找顺序不变。

发布说明在 v1.4.0 的 `packages/coding-agent/CHANGELOG.md`。安装目录那条对应 #9501。

cadr 现在的外壳在 `src/cadr-cli/support/shell-process.lisp`。

- `get-powershell-config` 只在 `PATH` 上找 `pwsh.exe`，再找 `powershell.exe`。找不到就报 `No PowerShell executable found. Install PowerShell or add powershell.exe/pwsh.exe to PATH.`
- `bash-shell-config` 只用正则 `^[a-z]:\\windows\\(?:system32|sysnative)\\bash.exe$` 判断旧 WSL 启动器。Windows 不在 `C:\Windows` 时，pi 把命令从 stdin 送进 bash，cadr 仍用 `-c`。
- `get-shell-config` 在 Windows 上已经先找 `%ProgramFiles%\Git\bin\bash.exe` 和 `%ProgramFiles(x86)%\Git\bin\bash.exe`，再找 `PATH` 上的 `bash.exe`。这与 v1.4.0 的 Git Bash 顺序一致，不是这区间的新缺口。
- `kill-process-tree` 用 `(or (uiop:getenv "SystemRoot") "C:\\Windows")`。Common Lisp 里空字符串为真，所以 `SystemRoot` 被设成空时路径会变成 `\System32\taskkill.exe`。
- 存在性检查是 `probe-file`，不调用 Node，也不调用 `where`。

工具包解压在 `src/cadr-cli/tool-manager.lisp` 的 `windows-tar-command`。它仍在 `SystemRoot` 缺失时使用 `WINDIR\System32\tar.exe`。

用户能观察到的部分：

- 能。Windows 上 PowerShell 7 只装在 `Program Files\PowerShell\7`、不在 `PATH` 时，pi 的 `powershell` 工具能启动，cadr 报找不到可执行文件。Windows PowerShell 只在 `%SystemRoot%\System32\WindowsPowerShell\v1.0`、不在 `PATH` 时同样。
- 能。旧 WSL `bash.exe` 不在 `C:\Windows` 时，命令走 argv 还是 stdin，用户能从变量展开和引号结果看出来。
- 能，但是窄。`SystemRoot` 为空字符串时，结束进程树的 `taskkill` 路径不同。`SystemRoot` 未设置而 `WINDIR` 有值时，工具包解压用的 `tar.exe` 不同。
- Store 别名那条，pi 用户能观察到，因为 `where` 返回的路径被 `existsSync` 拒绝。cadr 没有这条 Node 路径。本环境没有 Windows，不能证明 `probe-file` 会拒绝同一个别名。

建议：

- port `61060ddf8` 在 coding-agent 里的四处行为。PowerShell 的两个安装目录，按 `SystemRoot` 识别旧 WSL `bash.exe`，空 `SystemRoot` 时 `taskkill` 使用 `C:\Windows`，`windows-tar-command` 不再读 `WINDIR`。Unix 上 `get-shell-config` 的 `/bin/bash`、`PATH`、`sh` 顺序不要动。`test/cadr-cli/goal28-shell-settings-test.lisp` 锁的是设置里的 `shellPath`，不覆盖这些 Windows 分支。落地时用构造的环境变量锁查找结果，不要从当前 cadr 输出反推。
- 不 port `packages/durable/src/env/node.ts`。cadr 的 bash 和 powershell 工具读的是 `shell-process.lisp`。
- 不 port `packages/coding-agent/docs/windows.md`。cadr 没有对应的 Windows 手册页。行为对齐之后，错误字符串已经会告诉用户结果。
- N/A：`28bea006b`。要修的是 Node `existsSync` 的额外 stat。cadr 用 `probe-file`。把 `access(F_OK)` 再抄一层，修不到 cadr 的检查。若以后在 Windows 上量到 `probe-file` 对可运行的 Store 别名返回空，再单独立项。

## `pi update` 的 BOM

`ea25697e91db9112bbf2bdc4c2ae8a7d5d2f0dd3`（2026-10-20，`fix(coding-agent): accept managed install markers with a UTF-8 BOM`）。

上游在 `packages/coding-agent/src/package-manager-cli.ts` 的 `getActiveManagedInstallRoot` 里，对 `managed-install.json` 先 `stripBom` 再 `JSON.parse`。Windows PowerShell 5.1 重写该文件时会加上 UTF-8 BOM，`pi update` 原先失败，错误文本是 `Managed install marker is missing or invalid`。回归测试在 `packages/coding-agent/test/package-command-paths.test.ts`，用例名是 `accepts a managed install marker with a UTF-8 BOM`。changelog 写的是 `pi update`。

这和已经单独排队的 `mcp.json` BOM（`bdd9f0399`，#11191）不是同一个文件。

cadr 的 `update self` 在 `src/cadr-cli/packages/commands.lisp` 里打印 `Update cadr through the Common Lisp build/install method.`，然后成功返回。全树 `src/**/*.lisp` 没有 `managed-install`。`strip-utf8-bom` 只用于编辑工具（`src/cadr-cli/tools/edit.lisp`）和 `mcp.json`（`src/cadr-agent/extensions/mcp-config.lisp`）。

用户能观察到的部分：不能。cadr 没有托管安装标记，也没有会读这个文件的 `update`。带 BOM 的 `managed-install.json` 放在旁边，`cadr update self` 的输出不变。

建议：N/A。这是 npm 托管安装布局上的读取修复。cadr 的自更新边界已经是 SBCL 构建安装，见 `docs/proposals/goal-v8-part-b.md` 对 `config.test.ts` 的 N/A 理由。不要为了这个标记去实现一套托管安装。

## 扩展加载 `@earendil-works/pi-ai/models`

`22dc6c26f3c530e11b8cc40443ecdce2b3c84116`（2026-10-20，`fix(coding-agent): expose @earendil-works/pi-ai/models in the extension loader`，#11156）。

上游扩展加载器原先只给 `@earendil-works/pi-ai`、`/compat`、`/oauth`、`/providers/all` 做了 jiti 别名和内嵌虚拟模块。TypeScript 扩展写 `import { clampThinkingLevel } from "@earendil-works/pi-ai/models"` 时，报 `Cannot find module`。这次把 `/models` 加进 `packages/coding-agent/src/core/extensions/loader.ts` 的别名表，以及 `packages/coding-agent/src/core/extensions/virtual-modules.ts` 的 `VIRTUAL_MODULES`。旧的 `@mariozechner/pi-ai/models` 名字一并补上。

cadr 的扩展入口是 `src/cadr-cli/extensions/loader.lisp` 的 `load-extension-source`。它 `LOAD` 一个 Lisp 文件，包继承 `CADR-AGENT`，不跑 jiti，也没有 npm 虚拟模块表。思考档位函数已经是 Lisp 导出：`src/cadr-ai/models.lisp` 的 `clamp-thinking-level`，由 `src/cadr-ai/package.lisp` 导出。扩展作者直接调用这个符号。

用户能观察到的部分：对 cadr 扩展作者，不能。他们写的是 Lisp，不解析 `@earendil-works/pi-ai/models`。把一个 pi 的 TypeScript 扩展丢进 cadr，失败发生在更早的地方，加载器不会把它当 Lisp 读完再去解析那条 import。补一个永远不会被查的别名，不改变任何一条错误。

建议：N/A。可见的能力是 `clamp-thinking-level`，cadr 已经有。不要把 jiti 别名表移植进来。

## 生成的 models 参考文档

`8efd314fa3d3232ce197d8d7a6a5660530b9d83e`（2026-10-16，`docs(ai,coding-agent): generate models.json reference from schemas`，#11038，关闭 #10790）。

上游加了 `packages/coding-agent/scripts/generate-references.ts` 和 npm 脚本 `generate:references`。它从 TypeBox schema 生成 `packages/coding-agent/docs/models-configuration.md`，并在 `packages/coding-agent/docs/docs.json` 里挂上文档站导航。`packages/coding-agent/schemas/models.schema.json` 给 provider 和 model 字段补了 `description`，并给 `authHeader`、`reasoning`、`input`、`contextWindow`、`maxTokens` 写了 JSON Schema 的 `default`。changelog 写的用户现象是编辑器里这些字段没有提示。

同一提交还改了 schema 源文件，但运行时校验的形状没有变。

- `packages/coding-agent/src/core/model-config.ts` 把说明文字和 `default` 放进 TypeBox。`Compile(ModelsConfigSchema)` 仍是原来的校验器。没有新增把 `default` 填进用户文件的调用。
- `packages/ai/src/providers/compat-schema.ts` 导出 `CompatSchemasByApi`，并给 `azure-openai-responses` 和 `openai-codex-responses` 挂上已有的 OpenAI Responses compat schema。全库只有 `generate-references.ts` 读取这个表。`Set` 去重之后，合并进 provider compat 的属性与原来相同。
- `packages/ai/src/providers/model-schema.ts` 只改了 `thinkingLevelMap` 和 `promptCache` 的说明文字。
- `packages/coding-agent/docs/models.md` 补了三句已有行为的说明。`$$` 和 `$!` 写出字面量 `$` 和 `!`，只改内置 provider 的 `baseUrl` 可以走代理，以及指向新参考页的链接。这些句子不在 `model-config.ts` 的逻辑 diff 里。

cadr 不发布 `models.schema.json`。仓库里没有该文件。用户读的是 `docs/models.md` 和 `docs/custom-provider.md`。`models.json` 的读取在 `src/cadr-cli/models/registry.lisp` 的 `refresh-model-registry`。解析失败时的警告文案已经与基线对齐，不依赖这份生成页。

用户能观察到的部分：pi 文档站和拿着 `models.schema.json` 的编辑器能看到新说明。cadr 用户看不到这两样。这次提交没有改变 `models.json` 接受或拒绝哪些字段。

建议：N/A。不要移植生成脚本、文档站页面或 JSON Schema 文件。`docs/custom-provider.md` 比新参考页短，那是 cadr 自己的手册，不是 v1.4.0 新出现的行为差。若以后要补字段说明，单独改 cadr 文档，不要把 pi 的生成器搬过来。

## 遥测 span

`2ec55d808d455b1a64a2bf7888198207a096120a`（2026-10-19，`feat: Durable and pi-ai telemetry; Context.telemetry is always a span`）。

`packages/ai` 里新增 `packages/ai/src/telemetry.ts`。`AI_TELEMETRY_SCHEMA` 定义 span `pi.ai.request` 和 `pi.ai.poll`，事件 `pi.ai.first_chunk` 和 `pi.ai.block`，以及 duration、token、cost 指标。默认父 span 是 NOOP。没有改各 provider 的请求体。`packages/ai/src/types.ts` 把 `ProviderRequestOptions.telemetryContext` 改名为 `telemetry`，类型从 `TelemetryContext` 换成 `TelemetrySpan`，没有兼容别名。`packages/ai/CHANGELOG.md` 写明这是 opt-in。

同一提交的其余部分在三包之外。`packages/telemetry` 让每个 span 带上 metrics。`packages/chord` 让 `Context.telemetry` 总是一个 span。`packages/durable` 增加 `pi.durable.submit` 和 `pi.durable.phase`。Goal 26 不移植这些包。

cadr 的 `src/cadr-ai` 没有 telemetry 符号，也没有 `telemetryContext` 参数。设置里的 Install telemetry 是另一件事。`src/cadr-cli/bootstrap/settings.lisp` 仍显示 `enableInstallTelemetry`，`src/cadr-cli/arguments.lisp` 仍说明 `CADR_TELEMETRY`。那是启动时的安装上报开关。`docs/open-questions.md` 的 `OQ-G18-INSTALL-TELEMETRY` 已裁决为有意差异。界面保留，没有任何上报出口。断言是 `goal18-install-telemetry-has-no-egress`。`docs/source-parity.md` 把 `packages/telemetry` 整包标成 intentional difference，理由同样是 goal 16 不允许遥测出口。

用户能观察到的部分：不能。默认 NOOP，不打印、不改请求、不写会话。cadr 也没有调用方在传 `telemetryContext`，所以改名不会打断现有用法。durable 的 span 属于不移植的包。

建议：N/A。不要加 span、指标或父 span 参数。安装遥测开关维持已裁决的样子，不要把它和这批 span 混成一次移植。
