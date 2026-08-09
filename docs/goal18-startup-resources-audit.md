# Goal 18 Part H 复核报告：启动资源区块与空环境盲区清查

复核日期 2026-08-09。两部分：(H1) 启动资源区块的基线对齐修复；
(H3.3) 仅在特定状态下渲染的界面的系统清查。

## 1. H1 修复清单（以基线 interactive-mode.ts:1451-1650 为准）

| 项 | 修复前 | 修复后（=基线） |
|---|---|---|
| 区块顺序 | Skills → Prompt Templates → Themes → Context | Context → Skills → Prompts → Extensions → Themes → [Skill conflicts] → [Prompt conflicts] → [Extension issues] |
| Prompts 标签 | `Prompt Templates` | `Prompts` |
| [Extensions] | 缺失 | 区块在（mdHeading 标题，compact 最小唯一后缀标签，expanded 按 scope 分组） |
| [Skill conflicts] | 缺失（skill 损坏时静默） | warning 色块：collision 组（✓ winner / ✗ loser (skipped)）在前、载入警告在后 |
| [Prompt conflicts] | 缺失 | 同构（基线 :1618-1625 区块） |
| [Extension issues] | 缺失（扩展载入失败仅有瞬时通知） | 同构（基线 :1627-1645 区块，error/warning 双色） |
| 排序 | 全部 string<，Context 也被排序 | compact 列表按 baseline localeCompare 语义排序，Context 保持插入序（sort:false） |
| 冲突裁决 | project 覆盖且静默 | 保留 project 胜出（基线 resolve() 先 project 后 user、first-wins），并记录 collision——此前 loser 被静默丢弃，与基线的 collision diagnostic 不符 |
| 布局 | 单组件 padding-x 1、比基线少一空行 | banner（padding-x 1）与资源区块（padding-x 0，独立容器）分离渲染；分隔空行为真空行（基线 Spacer 语义） |

基线消费点证据：`ShowImagesSelectorComponent` 等三个组件在基线零调用
（见 Part E 报告）；`[Extension issues]` 是顾问清单之外、本 Part 读基线
源码时发现的第三个警告块——顾问的 H1 清单（仅 [Skill conflicts]）不完整。

## 2. 差分场景

`startup-resources`（新）：预置 AGENTS.md、两个正常 skill、一个缺
description 的损坏 skill、一个 prompt、一个目录式扩展
（pi `demo/index.ts` ↔ cadr `demo/extension.lisp`，双侧显示同为 `demo`）、
一个自定义 theme；compact 与 ctrl+o expanded 双检查点、宽窄双尺寸，
含 process-exit。空环境场景 `startup-first`/`startup-existing`/
`startup-untrusted` 保持不变且继续通过——两种状态都在门禁内。

不可对拍项及其替代覆盖：

- [Prompt conflicts] 与 [Extension issues] 的真实载入错误文本在两侧
  必然不同（JS Error.message 对 Lisp condition 文本），无法用夹具逐字节
  对拍；区块结构由 `test/cadr-cli/goal18-startup-resources-test.lisp`
  以合成诊断锁定（header、路径行、消息行、error/warning 双色、块序）。

## 3. H3.3 状态依赖界面清查

方法：以 reachable-interfaces.json 的 28 界面 × 场景 setup 状态逐一对照，
找出"仅在特定状态下渲染"的分支，确认每个状态有提供它的差分场景。

| 状态依赖面 | 空/缺省状态场景 | 非空/激活状态场景 | 结论 |
|---|---|---|---|
| 启动资源区块（Context/Skills/Prompts/Extensions/Themes） | startup-first/existing/untrusted | startup-resources（本 Part 新增） | 已闭合 |
| Skill 载入警告（[Skill conflicts]） | 全部既有场景 | startup-resources（损坏 skill 夹具） | 已闭合 |
| [Prompt conflicts] / [Extension issues] 真实错误文本 | — | 不可对拍（实现相关文本），FiveAM 锁定结构 | 已闭合（结构性覆盖） |
| 登录八形态（A5） | overlays-auth-* | overlays-auth-manual-code-complete / browser-callback(+/-complete) | 已闭合（goal 18 A5） |
| 会话列表非空/相对时间桶 | — | selector-state-sweep（全桶遍历） | 已闭合 |
| 模型列表（长列表滚动） | — | selector-state-sweep | 已闭合 |
| 项目信任（未信/继承/已存决定） | startup-untrusted | selector-trust-inherited、startup-untrusted 保存路径 | 已闭合 |
| 更新提示（含无超链接变体） | — | update-notifications、update-notifications-no-hyperlinks | 已闭合 |
| 设置行条件分支（图像行） | 常规 | settings-state-sweep（Part E 起 supportsImages=true） | 已闭合 |
| 工具显著状态（截断/超时/非零退出/空输出/并发） | — | tools-significant-states、tools-failure、tool-bash-abort | 已闭合 |
| Provider 错误/降级 | — | provider-error | 已闭合 |
| 压缩三态（manual/threshold/overflow） | — | compaction-status-manual/threshold/overflow | 已闭合 |
| 崩溃（非正常终止输出） | — | fatal-crash | 已闭合 |
| autocomplete（slash/path/空前缀） | — | autocomplete-surfaces | 已闭合 |
| 扩展 UI（selector/input/editor） | — | extension-surfaces | 已闭合 |
| 首次运行设置（FirstTimeSetup，无 settings.json 时） | — | 差分 harness 不可达：双侧驱动均以内存 settings 运行，该状态按构造不触发；cadr 侧由 sdk-services 的 should-run-first-time-setup-p 与既有套件覆盖 | 登记为不可达（构造性） |

结论：除 FirstTimeSetup（harness 构造性不可达，已登记并说明覆盖位置）外，
每个状态依赖面都有提供该状态的差分场景。本表即今后新增界面的审查清单：
新增带状态分支的界面时，须在本表登记其空/非空场景对。
