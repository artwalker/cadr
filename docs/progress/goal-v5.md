# GOAL v5: Wave 0 回归清偿 + TUI 全量对齐

## 〇、前置条件与定位

- goal 4 已验收。全程以 `docs/parity-map.md` 为工作清单，行为基线仍为 `71efc6f0c1909874ec8c944637a9ae7fc0e2d508`（审计用 detached worktree，禁止以 pi-mono-legacy 的 2026-04 状态为基准）。
- **总序已由用户拍板（2026-07-30）**：Wave 0 → TUI（原 Wave 4 提前，理由：无依赖链且用户价值最高）→ Wave 1 → 2 → 3 → 5。本 goal 只含前两段；后续波次在本 goal 验收后另立 goal，不得预先开工。
- 本 goal 冻结范围之外的一切：provider、agent 循环、会话格式、扩展 API（已冻结）、REPL 行为均不得改动。TUI 之外发现的问题只记录进 docs/open-questions.md。

## 一、Part A：收尾提交 + Wave 0

1. docs-only 提交 goal 4 产出：`docs/parity-map.md`、`docs/progress/goal-v4.md`，不含任何其他文件。
2. 补齐两条 `U` 级回归测试：
   - `U-SEARCH-GITIGNORE`（对应 `3303-find-nested-gitignore.test.ts`：嵌套 .gitignore 语义）
   - `U-TUI-RI`（对应 `regression-regional-indicator-width.test.ts`：区域指示符（旗帜 emoji）宽度）
3. 零生产代码变更。若新测试证明存在真实 bug：记录现象与最小复现，标记 blocked 等用户确认修复方案，不得静默修改生产代码。

## 二、Part B：TUI 全量对齐（原 Wave 4）

### 目标

以审计提交的 `packages/tui` 与 coding-agent 的 TUI 侧行为为标准答案，将 cadr-tui 补齐到组件级对等。parity-map 中 `tui` 包的 25 个 `M` 测试文件即工作清单——完成时每个文件必须重新分类为 `C`，或在报告中逐文件注明 N/A 及理由（N/A 仅限测试的是 TS 运行时特有机制，且需链接差异清单）。

### 明确要求

1. **组件清单**（对照审计提交 `packages/tui/src/`）：autocomplete、fuzzy、kill-ring、undo-stack、word-navigation、keybindings（含 native-modifiers）、stdin-buffer、terminal-colors、terminal-image（iTerm2/kitty/sixel 按原版支持范围）、overlay 全家（含 CJK 边界行为）、select-list 与 markdown 的存量缺口。行为以原版逐项为准，**不得加入原版没有的机制**——任何"顺手改进"的想法记 open-questions.md 交用户裁决。
2. **架构约束不变**：REPL 与 TUI 仍是同一 `CADR-AGENT` 事件流的两个渲染器；`--no-tui` 永远可用；TUI 层不得侵入 provider/session/扩展逻辑。
3. **测试规格**：每个组件配虚拟终端快照测试；原版 25+1 个测试文件的断言逐文件移植语义（不是逐行翻译）；CJK/emoji/区域指示符宽度回归必须包含。测试先行。
4. **不改既有通过行为**：goal 3 验收时的 690 条断言必须全数保持绿色；只增不删（既有测试如需调整须在报告中逐条说明理由）。

### 验收标准

1. parity-map 的 `tui` 行更新后 C/U/M 重新计数，`M` 中不属于 N/A 的清零；汇总表同步更新，更新以独立 docs 提交落账。
2. 全量测试绿，总数严格大于 690，新增数与新组件清单对得上。
3. `./scripts/live-tui-smoke.sh` 扩展覆盖新组件后通过。
4. **用户人工验收清单**（由顾问在验收时出具，覆盖：补全弹出与选择、undo、kill-ring 粘贴、按词跳转、终端内图片显示、overlay 中文边界、resize 下的以上全部）——固定基线只有 undo、没有 redo，按全局对齐原则不新增 redo；用户逐项确认前不得宣告完成，自行宣布无效。
5. 阶段报告 `docs/progress/goal-v5.md`：组件映射表、逐测试文件分类变更、精确命令与结果。

## 三、原则

- 测试先行、阶段门禁、发现的非 TUI 问题只记录不修复。
- 人工确认门禁不变：扩展 API 不动；如 TUI 对齐过程中发现必须触碰冻结接口，标记 blocked 等用户裁决。
- 完成后暂停，等待 Wave 1 指令。

## 四、执行记录

### 2026-07-30：Part A 门禁

- Goal 4 产出已作为纯文档提交 `f9cefa43d` 落账，提交只含
  `docs/parity-map.md` 与 `docs/progress/goal-v4.md`。
- `U-SEARCH-GITIGNORE` 已测试先行补入
  `test/cadr-cli/search-tools-test.lisp`；`cadr-cli` 220 checks 全绿，且未改
  生产代码。
- `U-TUI-RI` 已测试先行补入 `test/cadr-tui/unicode-test.lisp`。区域指示符
  单体、完整旗帜与常见流式 emoji 宽度断言通过，但基线换行断言暴露真实差异：
  `wrap-text("      - 🇨", 9)` 当前返回首行 `"      - "`（可见宽度 8），固定
  TS 基线返回首行 `"      -"`（可见宽度 7）。最小复现即该输入、宽度 9。
- 根因是 `wrap-logical-line` 仅按 grapheme 硬切且保留断点尾空格；固定基线
  `wrapTextWithAnsi` 在溢出时 `trimEnd()`，不让续行从空白开始。
- Part A 当时按硬门禁未修改生产代码。用户随后明确授权在 Part B 中测试
  先行移植完整 `wrapTextWithAnsi` 语义，不打孤立补丁；该差异已随
  ANSI/OSC 8、词/CJK 边界和尾空白语义一起修复。

### Part B 最终映射

下表固定测试语义和实现模块。原 25 个 `M` 文件全部适用于 cadr，均已转为
`C`；没有 N/A。

| 固定基线测试文件 | 必须移植的行为 | cadr 目标模块 |
|---|---|---|
| `autocomplete.test.ts` | slash、路径、`@` 文件模糊补全，引用、隐藏项、符号链接与稳定排序 | `autocomplete.lisp`、`fuzzy.lisp` |
| `bug-regression-isimageline-startswith-bug.test.ts` | 任意位置识别 iTerm2/Kitty 图片转义且无长行崩溃或文本误报 | `terminal-image.lisp` |
| `editor.test.ts` | 历史、Unicode/CJK、词换行、kill-ring、undo、autocomplete、字符跳转、粘贴原子段与 sticky column | `editor.lisp`、`kill-ring.lisp`、`undo-stack.lisp`、`word-navigation.lisp` |
| `fuzzy.test.ts` | 顺序匹配、边界/连续得分、字母数字互换、多 token 排序 | `fuzzy.lisp` |
| `input.test.ts` | 单行输入、横向滚动、Unicode 词删除、kill/yank/undo 与可配置按键 | `input-component.lisp` |
| `keybindings.test.ts` | 默认值、用户覆盖、去重、禁用、冲突和防御性副本 | `keybindings.lisp` |
| `keys.test.ts` | legacy/CSI/CSI-u/Kitty/modifyOtherKeys 解析、修饰键、press/repeat/release | `keys.lisp` |
| `markdown.test.ts` | 流式 Markdown、ANSI 主题、列表/引用/代码/表格/链接/图片与宽度快照 | `components.lisp`、`terminal-image.lisp` |
| `overlay-non-capturing.test.ts` | 非捕获 overlay 输入分派、焦点恢复、嵌套与动态可见性 | `overlay.lisp`、`renderer.lisp` |
| `overlay-options.test.ts` | anchor、行列、百分比尺寸、边距、最大高度和裁剪 | `overlay.lisp` |
| `overlay-short-content.test.ts` | overlay 高于主内容时仍正确合成和清理 | `overlay.lisp`、`renderer.lisp` |
| `regression-overlay-cjk-boundary.test.ts` | overlay 起点落在宽字符内部或边界时不残留半个 grapheme | `unicode.lisp`、`overlay.lisp` |
| `select-list.test.ts` | 描述单行化、主列最小/最大宽度、截断回调与对齐 | `components.lisp` |
| `stdin-buffer.test.ts` | 分块 ESC/CSI/SS3/mouse/Kitty、超时、去重、paste、flush/clear/destroy | `stdin-buffer.lisp`、`keys.lisp` |
| `tab-width.test.ts` | tab 与 ANSI/overlay 切片统一按 3 cells 计宽 | `unicode.lisp`、`overlay.lisp` |
| `terminal-colors.test.ts` | OSC 11 与颜色方案报告解析、查询消费和超时后迟到回复 | `terminal-colors.lisp`、`renderer.lisp` |
| `terminal-image.test.ts` | 能力探测、iTerm2/Kitty 编码、尺寸解析、行数、删除、fallback 与 OSC 8 | `terminal-image.lisp`、`components.lisp` |
| `terminal.test.ts` | Apple Return、Kitty 协商/fallback、普通输入回放和环境尺寸 | `terminal.lisp`、`keys.lisp` |
| `truncate-to-width.test.ts` | ANSI 安全连续前缀截断、ellipsis、padding、畸形转义、Thai/Lao 输出归一化 | `unicode.lisp` |
| `truncated-text.test.ts` | 首行截断、精确宽度和垂直 padding，样式 reset 不泄漏 | `components.lisp` |
| `tui-cell-size-input.test.ts` | cell-size 查询回复被消费，裸 Escape 与后续用户输入仍转发 | `terminal-image.lisp`、`renderer.lisp` |
| `tui-overlay-style-leak.test.ts` | overlay 切片丢弃尾 SGR 时仍补 reset，不污染后续 cell | `unicode.lisp`、`overlay.lisp` |
| `tui-render.test.ts` | 差分/全量重绘、resize、内容收缩、样式 reset、Kitty 图片预清理与删除 | `renderer.lisp`、`terminal-image.lisp` |
| `word-navigation.test.ts` | ASCII 标点、路径、CJK、空白和粘贴原子段的前后移动 | `word-navigation.lisp` |
| `wrap-ansi.test.ts` | ANSI/OSC 8 状态跨行、词/CJK 换行、尾空白和孤立区域指示符 | `unicode.lisp` |

另外两条状态变化为：

- `regression-regional-indicator-width.test.ts`：`U → C`，证据在
  `unicode-test.lisp` 与 `wrap-ansi-test.lisp`。
- `tui-shrink.test.ts`：保持 `C`，旧行为由新增 renderer 回归继续覆盖。

Part A 的 `3303-find-nested-gitignore.test.ts` 同时由 `U → C`。因此严格
manifest 的 TUI 行从 `C/U/M = 1/1/25` 变为 `27/0/0`，全仓从
`1/2/349` 变为 `28/0/324`。

### Part B 实现

| 组件域 | 实现 |
|---|---|
| ANSI/Unicode 布局 | 完整词边界、ANSI/OSC 8 跨行状态、尾空白、CJK、emoji、区域指示符、tab=3、ANSI 安全截断 |
| 输入协议 | legacy、CSI/SS3、CSI-u、Kitty、modifyOtherKeys、native modifiers、press/repeat/release |
| 输入 buffering | 分块 ESC/CSI/paste、超时、Kitty 去重、终端能力回复过滤和同批用户输入顺序 |
| 编辑 | multiline 与 single-line、历史、sticky column、按词移动、字符跳转、原子 paste、kill/yank/yank-pop、undo |
| 补全 | slash、路径、引号、隐藏文件、符号链接、递归 `@` 文件和稳定 fuzzy 排序 |
| overlay | anchor、百分比尺寸、边距、裁剪、focus/capture、非捕获输入、嵌套和 CJK/ANSI 安全合成 |
| 终端能力 | OSC 11/颜色方案、cell size、Kitty/iTerm2 能力与图片、删除、尺寸和文本 fallback |
| 组件/渲染 | Markdown、select list、truncated text、image component、差分/全量重绘、resize、style 隔离 |

固定基线没有 redo；实现只包含原版 undo，没有引入额外核心机制。真实
`process-terminal` 复用了 `stdin-buffer`，并修复了两项实机才暴露的问题：
终端 DA 回复与用户输入粘连，以及 Return 被错误识别为 `Ctrl+-`。两者都先
加入回归测试，再按固定基线语义修复。

### 自动验收证据

```text
./scripts/test-cl.sh
  cadr-ai:    256/256
  cadr-agent: 156/156
  cadr-tui:   582/582
  cadr-cli:   225/225
  total:     1219/1219

./build.sh
  cadr build: SBCL lacks sb-core-compression; building an uncompressed image.
  exit 0; ./cadr regenerated

./cadr --version
  cadr 0.1.0

./scripts/live-tui-smoke.sh
  goal5 manual TUI smoke: overlay focus, CJK frame, image fallback,
  resize, and terminal restore passed
  live TUI smoke: autocomplete, undo, kill-ring, DeepSeek two-turn edit,
  resize, CJK, and terminal restore passed

bash -n scripts/goal5-manual-tui.sh \
  scripts/goal5-manual-tui-smoke.sh scripts/live-tui-smoke.sh
  exit 0
```

既有测试文件只增加断言，没有删除或放宽断言。最终 `git diff --check`
通过。`U-TUI-RI`、完整 `wrapTextWithAnsi` 语义和真实 Return/终端回复路径
均留在 Goal 5 门禁中。`goal5-manual-tui.sh` 只加载 test system，不进入
生产镜像或核心 API；它把图片与 CJK overlay 的人工验收变成真实终端中的
可重复操作。

### 待用户人工验收

Goal 5 尚未完成。先在 Kitty/iTerm2 原生窗口（不要经 tmux）运行：

```bash
./scripts/goal5-manual-tui.sh
```

再运行正常程序完成编辑器检查。需用户逐项确认：

1. 输入 `/` 后弹出补全，并可用方向键、Tab、Enter 选择。
2. `Ctrl+-` / `Ctrl-_` 可 undo；无需验收 redo，因为固定基线没有 redo。
3. `Ctrl+W`、`Ctrl+U`、`Ctrl+K` 后可用 `Ctrl+Y` 粘贴，并可用 `Alt+Y`
   轮换 kill ring。
4. Ctrl/Alt + Left/Right 按词移动，对 ASCII 路径、标点和 CJK 边界正确。
5. harness 显示终端内图片；按 `i` 后显示有界 fallback，再按 `i` 恢复图片。
6. harness 的 overlay 在中文宽字符边界不残留半字；按 `f` 时 capturing
   overlay 隐藏/恢复，input target 在 `EDITOR` / `PICKER` 间切换，
   non-capturing help 始终可见。
7. 分别 resize harness 与正常程序，以上交互无残留、错位或样式泄漏。
8. `--no-tui` 仍进入 line REPL。

用户逐项确认前不宣告 Goal 5 完成；Wave 1 未开始。
