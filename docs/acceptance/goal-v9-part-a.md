# Goal 9 Part A / A2 阶段报告

> 状态：Part A / A2 实现、账本与永久门禁已完成。本文记录提交态机械证据；Codex OAuth live 请求另受账户额度限制，不以弱断言或 fixture 冒充真实通过。

## 1. 基线、审计窗口与工作树

- 规范基线：`74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`，审计 checkout 为 `/tmp/cadr-parity-74caa2649`。
- 历史锚点：`71efc6f0c1909874ec8c944637a9ae7fc0e2d508`，历史 checkout 保留在 `/tmp/cadr-parity-71efc6f0`；它不再是 parity 判定依据。
- Cadr 实现树：`/root/projects/cadr`，分支 `cadr-migration`。
- 规范 diff：119 个文件，`+7030/-1089`；端点净结果没有删除整个既有包，新增包为 `packages/protocol`。

复核命令：

```bash
git -C /tmp/cadr-parity-74caa2649 rev-parse HEAD
git -C /tmp/cadr-parity-71efc6f0 rev-parse HEAD
git -C /tmp/cadr-parity-74caa2649 \
  diff --stat \
  71efc6f0c1909874ec8c944637a9ae7fc0e2d508..74caa2649f10ed71b4378ce69f5d9fbfd2466ca5
git -C /tmp/cadr-parity-74caa2649 \
  diff --name-status \
  71efc6f0c1909874ec8c944637a9ae7fc0e2d508..74caa2649f10ed71b4378ce69f5d9fbfd2466ca5
```

Goal 文本所称“38 个提交”是包含历史锚点自身的闭区间计数：

```bash
git -C /tmp/cadr-parity-74caa2649 \
  rev-list --count 71efc6f0c1909874ec8c944637a9ae7fc0e2d508^..74caa2649f10ed71b4378ce69f5d9fbfd2466ca5
# 38

git -C /tmp/cadr-parity-74caa2649 \
  rev-list --count 71efc6f0c1909874ec8c944637a9ae7fc0e2d508..74caa2649f10ed71b4378ce69f5d9fbfd2466ca5
# 37
```

因此真正的增量是 37 个提交；下面列出闭区间 38 个对象，编号 00 是历史锚点，01–37 才是新基线增量。

## 2. 38 个提交的全量行为面

### 2.1 历史锚点

| # | commit | 行为面与审计结论 |
|---:|---|---|
| 00 | `71efc6f0c` | 历史锚点，`Add [Unreleased] section for next cycle`；仅用于界定旧端点，不计入 37 个增量。 |

### 2.2 Comparative eval（15 个增量对象）

| # | commit | 行为面与受影响路径 |
|---:|---|---|
| 01 | `32f3a9728` | 新增 comparative Pi eval harness、artifact、harness table、reporter、summary 与四个测试文件；主要位于 `packages/evals/`，并调整 extension loader。 |
| 02 | `af00848d6` | artifact 显式绑定 task，涉及 eval extension、Pi harness、smoke 与 reporter。 |
| 03 | `2eed6d219` | 删除中间演进中的 `artifact-names` 模块，把命名职责收回 artifact/reporter；端点不存在该冗余模块。 |
| 04 | `eb08aa8fa` | attachment 类型专门化，强化 artifact 输入合约。 |
| 05 | `3631e82d0` | source artifact 泛化，不再只绑定单一源类型。 |
| 06 | `2a2e677be` | source artifact 改为语言中立表示；这是 Lisp 移植必须保留的语义。 |
| 07 | `56e6a8a3f` | 每个测试后记录 eval session，新增 setup 生命周期钩子。 |
| 08 | `6a3eae8e4` | hash 前规范化 eval 输入，影响 harness table 分组稳定性。 |
| 09 | `d9ae6e2b0` | 简化 comparative 内部结构，但保留 artifact/table/summary 对外语义。 |
| 12 | `29f97c20f` | 简化 harness table 测试，不改变生产行为。 |
| 13 | `ac033d186` | 对齐 comparison report 输出和 summary 断言。 |
| 15 | `fce7445b1` | 比较方向改为显式声明，避免 candidate/baseline 反转。 |
| 16 | `ca11823f7` | 收敛 comparative ergonomics，影响声明与汇总入口。 |
| 17 | `743e1595c` | 删除自定义 shuffle；比较顺序回到固定、可复现语义。 |
| 18 | `7659e1c98` | evals-baseline 合并提交；无独立端点文件增量，以上 eval 演进的汇合点。 |

对应 Cadr 实现已落在 `src/cadr-evals/{harness,artifacts,harness-table,summary}.lisp` 以及同名测试中；提交见第 8 节。

### 2.3 仓库管理元数据（2 个增量对象）

| # | commit | 行为面与审计结论 |
|---:|---|---|
| 10 | `fe1f7230f` | 仅 `.github/APPROVED_CONTRIBUTORS`，没有运行时行为，Lisp 迁移仓无需移植。 |
| 14 | `6bcc29a06` | 同上，仅 contributor gate 数据。 |

### 2.4 AI provider 与 model metadata（4 个增量对象）

| # | commit | 行为面与受影响路径 |
|---:|---|---|
| 11 | `05558a792` | `opencode-go` 展示名由 `OpenCode Zen Go` 修正为 `OpenCode Go`。 |
| 25 | `b889a0ce3` | GPT-5.6 定价更新，来源为 `packages/ai/scripts/generate-models.ts`。 |
| 33 | `2c3041242` | OpenAI Completions 流允许没有 finish reason；同步 types、四个既有流测试与文档。 |
| 35 | `70bbe47a9` | Bedrock HTTP/流内错误保留结构化 metadata，新测试为 `packages/ai/test/bedrock-error-metadata.test.ts`。 |

对应 Cadr 行为位于 `src/cadr-ai/{http,models,provider,registry,types}.lisp`、`src/cadr-ai/providers/openai-completions.lisp` 和 Bedrock 错误门禁中。

### 2.5 Coding-agent core / extensions（4 个增量对象）

| # | commit | 行为面与受影响路径 |
|---:|---|---|
| 19 | `bb226f9c1` | 删除 `setToolsExpanded` 冗余状态写入，避免重复更新。 |
| 32 | `393c34422` | SDK 示例从已弃用 `getModel` 切换到新模型入口；示例/API 使用面。 |
| 36 | `714978bf5` | Markdown API 重做：extension 注册 markdown transformer；user/assistant/thinking/streaming 渲染传入 message type 与可用宽度；transform 链、错误隔离和缓存语义同步。 |
| 37 | `74caa2649` | `pi` manifest 字段逐项类型校验；无效字段丢弃、有效字段保留，不让畸形 manifest 拖垮 package discovery。 |

Cadr 对应门禁包括 `test/cadr-agent/extensions-wave3-test.lisp`、`test/cadr-cli/extensions-test.lisp`、`test/cadr-cli/tui-test.lisp`、`test/cadr-tui/components-test.lisp` 以及 `GOAL9-MALFORMED-PACKAGE-MANIFEST-IGNORES-INVALID-FIELDS-WITHOUT-DROPPING-VALID-FIELDS`。

### 2.6 Agent harness（6 个增量对象）

| # | commit | 行为面与受影响路径 |
|---:|---|---|
| 20 | `96eda8b47` | `packages/agent/docs/harness-v2.md` 补齐 agent-loop building blocks；文档合约。 |
| 22 | `82c485983` | harness shutdown 成为永久、幂等生命周期；关闭后 prompt/nextTurn/append/compact 均拒绝。 |
| 23 | `7d86e6233` | shutdown 功能合并提交，无独立端点文件增量。 |
| 26 | `bc031ae45` | shutdown 等待已经开始的 mutation，不留下后台写入。 |
| 28 | `871a99047` | prompt、mutation 等异步工作统一进入 task tracking。 |
| 29 | `9cde1725d` | `waitForIdle` 保持原有语义，不被 shutdown/task tracking 改写。 |

Cadr 对应实现在 `src/cadr-agent/{runtime,loop,compaction,conditions}.lisp`；`test/cadr-agent/shutdown-test.lisp` 覆盖活跃任务等待、永久关闭、关闭后 append/compact 拒绝和空闲 session 字节不变。

### 2.7 TUI（2 个增量对象）

| # | commit | 行为面与受影响路径 |
|---:|---|---|
| 21 | `c13ffe187` | 新增 alternate-screen renderer、main-screen 拆分、viewport/scroll、mouse selection、OSC 8/52、Kitty crop、iTerm stale 清理、退出时恢复完整文档；联动 coding-agent `--alt` 与 `interactive-tui.test.ts`。 |
| 34 | `dfe47d3fb` | grapheme width 与终端 cell 对齐，重点是 CJK、emoji、combining、区域旗帜与截断边界（#6987）。 |

Cadr 的结构门禁在 `test/cadr-tui/{alt-screen,unicode,terminal-image,components,component-parity}-test.lisp`；真实 PTY 生命周期另见第 6 节。

### 2.8 Remote protocol（4 个增量对象）

| # | commit | 行为面与受影响路径 |
|---:|---|---|
| 24 | `56eb685b6` | 新增 `packages/protocol`：CBOR、4-byte framing、codec、v2 schemas、客户端/服务端消息与 3 个测试文件。 |
| 27 | `bd2cfabc5` | CBOR 拒绝 cyclic values，源码重组至 `src/cbor/`；严格 map key、深度、长度和 JSON 值边界。 |
| 30 | `b2a1a0655` | protocol changelog，并收敛 CBOR public files；文档/发布面。 |
| 31 | `c066d01a4` | protocol package 合并提交，无独立端点文件增量。 |

Cadr 使用纯 Lisp 实现，没有因此引入第三方依赖；对应系统为 `cadr-protocol.asd`，门禁为 `test/cadr-protocol/{cbor,framing,protocol}-test.lisp`。

## 3. 包与测试文件计数

计数口径只统计规范基线中 Git 跟踪的 `packages/<name>/test/**/*.test.ts`：

```bash
git -C /tmp/cadr-parity-74caa2649 ls-tree -r --name-only 74caa2649 -- packages \
  | awk '/\/test\/.*\.test\.ts$/ {n++} END {print n+0}'
```

| package | 旧基线测试 | 新基线测试 | 增量 | 新基线包内跟踪文件 |
|---|---:|---:|---:|---:|
| `packages/ai` | 120 | 121 | +1 | 310 |
| `packages/agent` | 18 | 18 | 0 | 71 |
| `packages/coding-agent` | 187 | 189 | +2 | 590 |
| `packages/tui` | 27 | 28 | +1 | 75 |
| `packages/evals` | 0 | 4 | +4 | 19 |
| `packages/protocol` | 0 | 3 | +3 | 17 |
| `packages/storage` | 0 | 0 | 0 | 18 |
| `packages/server` | 0 | 0 | 0 | 17 |
| **总计** | **352** | **363** | **+11** | **1117** |

当前 Cadr 树有 99 个 `*test.lisp` 文件：AI 22、agent 18、CLI 26、evals 6、protocol 3、server 1、storage 1、TUI 22。该数字不是 parity 分母；parity 分母始终是基线 363 个 TS 测试文件。

初次按新基线重建账本得到 `347 C / 9 U / 6 M / 1 N/A = 363`。完成实现、提交和受影响既有 `C` 复验后，最终账本为
`362 C / 0 U / 0 M / 1 N/A = 363`；唯一 `N/A` 仍严格限定为
`packages/coding-agent/test/config.test.ts` 整文件。

## 4. 新增 11 个测试文件逐项状态

`git diff --diff-filter=A --name-only 71efc6f0..74caa2649 -- packages | awk '/\/test\/.*\.test\.ts$/'` 给出以下 11 项。

| # | 新基线测试文件 | Cadr 对应门禁 | 当前状态 |
|---:|---|---|---|
| 1 | `packages/ai/test/bedrock-error-metadata.test.ts` | `test/cadr-ai/bedrock-error-metadata-test.lisp`，9 个 Bedrock HTTP/流内错误 metadata 用例 | 已实现、提交并复验 |
| 2 | `packages/coding-agent/test/interactive-tui.test.ts` | `test/cadr-tui/alt-screen-test.lisp`、`test/cadr-cli/part-b-cli-test.lisp` 的 `--alt`/factory 门禁 | 已实现、提交并复验 |
| 3 | `packages/coding-agent/test/suite/regressions/7187-malformed-package-manifest.test.ts` | `GOAL9-MALFORMED-PACKAGE-MANIFEST-IGNORES-INVALID-FIELDS-WITHOUT-DROPPING-VALID-FIELDS` | 已实现、提交并复验 |
| 4 | `packages/evals/test/pi-harness.test.ts` | `test/cadr-evals/pi-harness-test.lisp` | 已实现并提交；确定性 eval 套件通过 |
| 5 | `packages/evals/test/vitest-evals/artifacts.test.ts` | `test/cadr-evals/artifacts-test.lisp` | 已实现并提交；确定性 eval 套件通过 |
| 6 | `packages/evals/test/vitest-evals/harness-table.test.ts` | `test/cadr-evals/harness-table-test.lisp` | 已实现并提交；确定性 eval 套件通过 |
| 7 | `packages/evals/test/vitest-evals/summary.test.ts` | `test/cadr-evals/summary-test.lisp` | 已实现并提交；确定性 eval 套件通过 |
| 8 | `packages/protocol/test/cbor/cbor.test.ts` | `test/cadr-protocol/cbor-test.lisp` | 已实现并提交；protocol 41 tests / 497 checks 全绿 |
| 9 | `packages/protocol/test/framing.test.ts` | `test/cadr-protocol/framing-test.lisp` | 已实现并提交；protocol 41 tests / 497 checks 全绿 |
| 10 | `packages/protocol/test/protocol.test.ts` | `test/cadr-protocol/protocol-test.lisp` | 已实现并提交；protocol 41 tests / 497 checks 全绿 |
| 11 | `packages/tui/test/tui-alt-screen.test.ts` | `test/cadr-tui/alt-screen-test.lisp` 的 10 个 viewport/input/image/link/selection/restore 用例 | 已实现、提交并复验；TUI 套件 691/691 |

`C` 的落账条件是：实现已提交、受影响整套全绿、parity-map 已用新基线重分类。上表 11 项均满足三个条件，没有用“有测试文件”替代行为等价证据。

## 5. Payload fixture 重生成证据

使用规范 checkout 的 public payload hook 重生成：

```bash
/tmp/cadr-parity-74caa2649/node_modules/.bin/tsx \
  scripts/export-ts-payloads.ts \
  --reference /tmp/cadr-parity-74caa2649 \
  --output /tmp/cadr-fixtures-74caa2649
```

exporter 产生 24 个 request JSON，并把第 25 项 Wave 1 catalog 写到输出目录的 sibling `catalogs/`。24 个请求 payload 与仓库当前 fixture 逐字节一致：

| request fixture | 新基线输出与仓库共同 SHA-256 | `cmp` |
|---|---|---|
| `ant-ling-default.json` | `22c6a61e29248b1e9612835f84f08c3b0c3ddc910afaab65fa6ae4baa3c948ab` | identical |
| `anthropic-adaptive-long-cache.json` | `acc4ee7758511bcd4f7edd05d77d84aad8516f8d8a765e79bd8d7251832a6546` | identical |
| `anthropic-complete.json` | `3b42fae877ed63ebd93832dfb9ac151daa1a7b5ea2b8a6897978da80b651afa8` | identical |
| `anthropic-stream.json` | `fe7a12b58ff250efd6a9b96c93f9d59e5135109f7860c118d79d3a4530052414` | identical |
| `anthropic-thinking-disabled.json` | `da9249390658ec09c53aa3202642d0935af9e4c531f19494d146be7ec38310ef` | identical |
| `cerebras-default.json` | `b1c2d0a5db73a9d44a642d7648b7ecdb3f0c6f0c162f4ce7ca4813cdbced6499` | identical |
| `google-complete.json` | `a0bbe63bba6d88cda63b52766f404b54b6a9e08c0356a85c7e57f3817d2ad513` | identical |
| `google-stream.json` | `a0bbe63bba6d88cda63b52766f404b54b6a9e08c0356a85c7e57f3817d2ad513` | identical |
| `google-thinking-disabled.json` | `42aa3f265a15c77f77b3eaff36e7fc540b8c89a1718cf73babd94ca7b02f90a6` | identical |
| `google-thinking-high.json` | `9885c922d7f509b2eee720d514c7e2868055023509cb685ea02a7629e0d80b8e` | identical |
| `groq-default.json` | `4c4f1a6fde5b34a2c699f212c6db8d8a58c61d48bdad762f3d4436c2d262cde7` | identical |
| `huggingface-default.json` | `be3229bb1bddde361a7db4560dfc17c01afb51b2d119d751a4d2911e9f6d780f` | identical |
| `minimax-cn-default.json` | `7cd7b3527247160db6f7611b2b8cb1f7e4aafc9f6d6a47bcb68764d70b8ae4bd` | identical |
| `minimax-default.json` | `7cd7b3527247160db6f7611b2b8cb1f7e4aafc9f6d6a47bcb68764d70b8ae4bd` | identical |
| `moonshotai-cn-default.json` | `762fbecb1549d81bc26c6c857192bdf7b135882623fb7531d6b3302c30038cdb` | identical |
| `moonshotai-default.json` | `762fbecb1549d81bc26c6c857192bdf7b135882623fb7531d6b3302c30038cdb` | identical |
| `openai-complete.json` | `d543870278d29833c4507829d96b5ca3bbb199ff39cb839526df87e8f278c272` | identical |
| `openai-completions-qwen-reasoning.json` | `bfb3e1ebd14499e47f6142302cb6d234d4d19d20bbb50c5cf64316d296a0dcff` | identical |
| `openai-responses-reasoning-cache.json` | `c8127b30cbeeaf8aea9ae4638de905e5198c4f061dc7a5ca3afe47b142e22f17` | identical |
| `openai-stream.json` | `c01ae21090c411c76440b44b3f44c371a741ee7b8bad87a22d4bb45033b019a0` | identical |
| `qwen-token-plan-cn-default.json` | `d1b65609c307a6e79475b50491ac6d5dd37d2d14e973655e2db88b65c6b791d5` | identical |
| `qwen-token-plan-default.json` | `d1b65609c307a6e79475b50491ac6d5dd37d2d14e973655e2db88b65c6b791d5` | identical |
| `together-default.json` | `49842b21c51c0849a1818623cf32bc8da8a83705baad978dd8f31da82537053d` | identical |
| `xiaomi-default.json` | `98c6dc1afd37b940e004d75652682807e8c1821a7087351467f2b70dafee24ba` | identical |

逐项复核命令：

```bash
find /tmp/cadr-fixtures-74caa2649 -maxdepth 1 -type f -name '*.json' -print0 \
  | sort -z \
  | while IFS= read -r -d '' fixture; do
      name=${fixture##*/}
      sha256sum "$fixture" "test/fixtures/requests/$name"
      cmp "$fixture" "test/fixtures/requests/$name"
    done
```

第 25 项 `wave1-provider-models.json` **不是** byte-identical，不能把 live catalog 漂移伪装成全同：

| 产物 | SHA-256 | providers / models | 差异 |
|---|---|---:|---|
| 仓库 `test/fixtures/catalogs/wave1-provider-models.json` | `3e1f8e1ee9831ac61a4809d14a61006d48c4c47d3b010d2c1f72cd34c7a543bc` | 12 / 143 | 固定审计 fixture |
| 新基线 live generator 输出 `/tmp/catalogs/wave1-provider-models.json` | `49ff4ac4e05f2cd2b1b7ac5f326d170a92bf766cf388a7a58e5d698e04de43b9` | 12 / 145 | HuggingFace 51 → 53，合计 143 → 145 |

这是 exporter 运行时读取的外部 catalog 数据漂移，不是 `71efc6f0..74caa2649` 内 payload 编码行为变化。24 个实际 wire request 仍逐字节一致，因此现有请求 fixture 和 Lisp provider 构造不受影响；Wave 1 固定 catalog 不因一次 live 抓取静默刷新。

另用与基线版本相同的固定 `@earendil-works/pi-ai@0.83.0` 产物读取静态 catalog 为 37 providers / 1153 models；同次 live generator 目录 `/tmp/cadr-model-catalog.HW3Yur.json/models.json` 为 37 / 1154。复核命令：

```bash
node --input-type=module -e '
  import("file:///tmp/cadr-pi-ai-0.83.0.FdAaCT/package/dist/models.generated.js")
    .then(({MODELS}) => console.log(
      Object.keys(MODELS).length,
      Object.values(MODELS).reduce((n, value) => n + Object.keys(value).length, 0)))'

python3 -c '
import json
data=json.load(open("/tmp/cadr-model-catalog.HW3Yur.json/models.json"))
print(len(data), sum(len(value) for value in data.values()))'
```

## 6. Part A2 八项永久自动化门禁

| Goal 8 人工项 | 永久门禁名 / 入口 | 覆盖证据 | 当前结果 |
|---|---|---|---|
| 会话 | `GOAL9-A2-SESSION-WORKFLOWS-ARE-DETERMINISTIC-AND-BRANCHES-STAY-ISOLATED` | faux provider；new/name/switch/branch/compact/export/continue/resume；A/B 两分支双向无串线 | 与 workflow 组共同 3 tests / 67 checks 全绿 |
| 模式 | `GOAL9-A2-PRINT-JSON-AND-RPC-MODES-COVER-THE-REAL-CONTRACT` | faux provider；print 只有最终文本，JSONL 每行可解析且事件顺序精确，RPC request/response/event 单次往返 | 与 workflow 组共同 3 tests / 67 checks 全绿 |
| 扩展 | `GOAL9-A2-EXTENSION-WORKFLOW-COVERS-LEGACY-UI-RENDERERS-AND-STALE-RELOAD` | 源文件真实 discovery/load；command/tool/hook/custom UI/message+tool renderer；`/reload` 后旧 generation stale；旧 API source 不改 | 与 workflow 组共同 3 tests / 67 checks 全绿 |
| 启动与退出 | `scripts/goal9-a2-pty.sh`，场景 `normal`、`ctrl-c`、`suspend-resume` | 真 PTY；raw/ICANON/ECHO、cursor、bracketed paste；SIGTSTP 前还原、SIGCONT 后重入、最终还原；严格检查序列次数与顺序 | 3 个场景连续三轮均为 3/3；最终集成入口待提交 |
| 输入编辑 | `GOAL9-A2-INPUT-EDITOR-PTY-EVENTS-AND-VIRTUAL-SCREEN-COVER-FULL-CONTRACT` | PTY 解码事件 + 虚拟终端快照；多行/CJK/emoji/宽字符换行、按词移动、history、kill/yank/yank-pop、undo | 与交互组共同 4 tests / 86 checks 全绿 |
| 补全 | `GOAL9-A2-COMPLETION-PTY-EVENTS-SNAPSHOT-SELECTION-CANCEL-AND-UNDO` | slash/path/`@`；键盘选择、取消、应用、undo | 与交互组共同 4 tests / 86 checks 全绿 |
| Overlay | `GOAL9-A2-OVERLAY-SELECTORS-FOCUS-CJK-AND-RESIZE-SNAPSHOTS` | session/tree/model/scoped-model/settings/trust 六类 selector；双 overlay focus；CJK 边框；72→14 列 resize | 与交互组共同 4 tests / 86 checks 全绿 |
| 渲染（结构） | `GOAL9-A2-FAUX-STREAM-RENDERING-STRUCTURE-AND-STATUS-SNAPSHOTS` | faux stream；thinking/text/tool delta；Markdown 标题/列表/表格/code/link；工具展开折叠；token/cache/cost/session 状态栏 | 与交互组共同 4 tests / 86 checks 全绿 |

上述行为测试没有调用真实 LLM。真实 PTY 门禁调用本地 SBCL 进程，faux/快照门禁进入 `cadr-cli/tests`；纯观感判断仍留给 Part B 的 A/B，不混入结构断言。

PTY 门禁输出格式：

```text
normal: PASS stty-restored echo-restored cursor-cycles=1 bracketed-paste-cycles=1
ctrl-c: PASS stty-restored echo-restored cursor-cycles=1 bracketed-paste-cycles=1
suspend-resume: PASS stty-restored echo-restored cursor-cycles=2 bracketed-paste-cycles=2
goal9 A2 PTY lifecycle: 3/3 passed
```

## 7. `--fork` 精确语义

命令行 `--fork` 的参数是**源 session 定位符**，不是 entry ID：

1. 含 `/`、`\` 或以 `.jsonl` 结尾时按 session 文件路径解析；相对路径相对于当前工作目录。
2. 否则先在当前项目 session 集合中按完整 ID、再按 ID prefix 匹配。
3. 当前项目没有匹配时，再在全局 session 集合中按完整 ID、再按 ID prefix 匹配。
4. 找到后创建新 session，`parentSession` 指向源 session，并复制源 conversation。
5. entry ID 不合法；按 user-message entry 分叉必须使用交互命令 `/fork` 的 selector。

实现证据：`src/cadr-cli/main.lisp` 的 `SESSION-ARGUMENT-PATH-P`、`FIND-SESSION-BY-ID-OR-PREFIX`、`RESOLVE-FORK-SOURCE-SESSION`、`RESOLVE-CLI-SESSION`。回归门禁：`FORK-ACCEPTS-SESSION-ID-PREFIX-AND-PREFERS-CURRENT-PROJECT`。README 已在 Usage 段明确上述边界。

基线证据为 `/tmp/cadr-parity-74caa2649/packages/coding-agent/src/main.ts` 的 `resolveSessionPath`：路径优先，随后 local exact/prefix，再 global exact/prefix。顾问曾把 entry ID 传给 `--fork` 得到 `Session not found`，属于参数类型误用，不是允许 entry ID 后实现失败。

## 8. 已落账的实现提交

以下提交已经进入 `cadr-migration`；未提交工作不列作完成：

| commit | 内容 |
|---|---|
| `7d52f919aec631627b9b1cfc4d3d1ccaa6610e55` | remote session protocol v2 核心实现 |
| `0f47f41438f698ab74c595a2f7752f31c7161e71` | provider stream metadata、无 finish reason、GPT-5.6 定价与 OpenCode Go 命名 |
| `995196c1bb60e3ab0f27e4c193b0588ce625c19b` | 永久 harness shutdown 生命周期与 task tracking |
| `bb925fdb117beaf43f584c44c06004b3488b932c` | grapheme/terminal cell 宽度对齐 |
| `e13b3458631b5c2a84bf5c5a00c93e6fa33f65e9` | Bedrock 结构化错误 metadata |
| `90a66b797e1f24214b1dc602bde99d4ee24df652` | protocol 三个基线测试文件完整语义门禁 |
| `f902d97f17e581d90a81c9f07dc7dad1e40b0c04` | shutdown 后 append/compact 拒绝与空闲 session 不变门禁 |
| `ec8962c659573624d2a7acdbc4a6a40cdce9d341` | comparative eval harness、artifact/table/summary 与四个测试文件 |
| `032269bd9fc758dbe12a093ab30359baa8135b5b` | Markdown transformer 扩展 API |
| `709907adbdf60e773ffdade40f9c69e936eb0060` | 实际组件宽度下的 Markdown transform/parse/cache 语义 |
| `eeef16dba710713850b4c80c69a23f91a5cac6f0` | 畸形 package manifest 字段容错 |
| `51ca77ce0b4c33b336f862d98c178a654c7c8f8b` | alternate-screen、main-screen scrollback、终端输入和图片裁剪语义 |
| `511a62323000918f475623bcf18713cea9ae9a88` | `--alt`、`--fork` 与交互 CLI 语义 |
| `bfde1c70118bb10c6331d48e051e7e6cbe6da463` | Part A2 faux/快照/真实 PTY 永久门禁 |
| `c6b3a4c18a3c0ed6a17d3185469fcb9916d9563e` | 终端图片 fallback 测试解除对调用者 HOME 的耦合 |

## 9. 测试证据与外部 live 状态

提交态独立证据：

- `cadr-protocol/tests`：41 tests / 497 checks，全绿。
- Part A2 workflow 定向组：3 tests / 67 checks，全绿。
- Part A2 interactive 定向组：4 tests / 86 checks，全绿。
- Part A2 PTY lifecycle：normal、Ctrl-C、suspend/resume，3/3 全绿。
- `cadr-tui/tests`：691/691，全绿；另以隔离 HOME 重跑，同为 691/691。
- 隔离 HOME 的全量 `./scripts/test-cl.sh`：4009 checks，4006 pass、3 个
  Codex OAuth 凭据门控 skip、0 fail。分套件为 AI 732、agent 621、TUI 691、
  CLI 1269、storage 23、server 43、evals 133、protocol 497。
- 其中 `cadr-cli/tests` 为 1269 checks，1268 pass、1 skip、0 fail；
  `cadr-evals/tests` 为 133 checks，132 pass、1 skip、0 fail。DeepSeek live
  块在测试内显式指定 provider/model 并真实运行；隔离 HOME 只移除用户
  settings、session、extension 与 OAuth auth store 耦合。

真实凭据状态必须与确定性门禁分开记录：

- DeepSeek key 可用；当前 eval/live 块真实运行全绿。
- Codex OAuth 凭据可被读取并已真实发起请求，但账户返回 `The usage limit has been reached.`。live-inclusive eval 运行共有 133 checks，其中 Codex OAuth 功能断言因此失败；真实 HOME 的 CLI live 块同因该上游额度状态出现 3 个失败断言。不能把它改成 fixture 或弱断言来伪装通过。
- 没有 AWS 等其他 provider 凭据；相应 live 块按基线凭据门控跳过，Bedrock 当前验证等级为 deterministic fixture。

Part A / A2 关账事实：

1. 当前规范基线引用已统一为 `74caa2649…`，旧 `71efc6f0…` 只保留历史锚说明。
2. `docs/parity-map.md` 的 363 项 manifest 与新基线测试路径集合精确相等；11 个新增文件及 26 个受影响既有 `C` 已复验。
3. 实现和测试均按逻辑分组提交；本报告与账本文档由 Part A 文档提交落账。
4. A2 八项行为已转为 faux/快照/真实 PTY 永久门禁；Part B 只保留无法机械判定的观感 A/B。
5. 工作区剩余修改仅包括用户在 Goal 8 验收文档中的既有证据，以及用户提供的 `goal9.md`；生成的 `scripts/__pycache__/` 因当前执行环境拒绝清理而单独列明，不属于产品产物或提交内容。

```text
parity-map: 362 C / 0 U / 0 M / 1 N/A = 363
full isolated-HOME suite: 4009 checks / 4006 pass / 3 OAuth skips / 0 fail
credential-gated live: DeepSeek pass / Codex OAuth usage-limit
A2 PTY: 3/3 pass
Part A/A2 implementation commits: 15
```
