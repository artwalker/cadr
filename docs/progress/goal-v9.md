# GOAL v9: 基线升级、体验对齐与产品化收尾

## 〇、前置条件与定位

- **goal 8 补正验收通过后**方可开始。
- **本 goal 不接受任何范围缩减。** 用户已明确：cadr 是完整的 pi，不是阉割版。遇到工作量大的部分，做法是拆成更多 Part 顺序推进，不是移出范围。任何"本次不做 X"的提议只有一种合法形式：标记 blocked、说明理由、交用户裁决。
- **基线升级为本 goal 的第一件事**：新基线 `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`（`earendil-works/pi`，2026-07-30）。旧基线 `71efc6f0c1909874ec8c944637a9ae7fc0e2d508` 自此仅作历史锚点。
- Part 间自动推进，不等用户指令；仅三类情况 blocked：新第三方依赖、密码学路径超出既有裁决、基线行为与既定裁决冲突且无预裁。

## 一、Part A：基线升级与增量对齐

### A1. 重锁基线
1. 新建审计 checkout（如 `/tmp/cadr-parity-74caa2649`），旧 checkout 保留为历史对照。
2. 全仓文档中的基线引用统一更新到新 hash，旧 hash 明确标注为历史锚点。
3. **重新生成全部 payload 对拍 fixture**（`export-ts-payloads` 以新 checkout 为 `--reference`）；逐个 fixture 比对新旧差异并在报告中列出——差异即上游行为变更，必须逐条对应到实现修改或确认无影响。

### A2. 增量审计
1. `git diff 71efc6f0..74caa2649` 全量过一遍，产出增量清单：新增/修改/删除的行为面、新增测试文件（352 → 363）、新增包。
2. parity-map 按新基线重建：新增测试文件入账为 `M`；受上游变更影响的既有 `C` 必须重新验证，不得因"之前是 C"就沿用。
3. 已知重点增量（清单不完整，以实际 diff 为准）：
   - **`packages/protocol` 新包**（remote session wire protocol）——cadr 完全缺失；
   - `feat(agent)`: harness shutdown 生命周期、harness task tracking 统一、waitForIdle 语义修正；
   - `feat(tui)`: alternate-screen renderer；`fix(tui)`: grapheme 宽度与终端 cell 对齐（#6987）；
   - Markdown API 重做（#7231）；
   - comparative eval harness 及其后续一系列 eval 改动；
   - `packages/ai`: Bedrock 结构化错误元数据、无 finish reason 的流、GPT-5.6 定价、OpenCode Go 命名。

### A3. 补齐
增量清单逐项实现，直至新基线的 363 个测试文件全部 `C` 或经用户裁决 `N/A`。新包与新功能一视同仁，不因"新出现"而降级处理。

## 一点五、Part A2：goal 8 人工验收项转自动化

goal 8 的 12 项真实终端人工验收中，第 9 项（安全立场）已由顾问核实与基线机制一致；图片、工具、server 三项已由顾问自动化代验。**其余八项本 Part 转为确定性自动化测试，进套件永久防退化**；其中无法自动化的纯观感判断并入 Part B 的 A/B 清单。

**机制必须与基线一致**：基线 pi 的端到端行为验证使用 **faux provider**（`packages/agent/test/e2e.test.ts` 覆盖 prompt/tool/abort/context/thinking/continue 闭环），不打真实 API。cadr 已有 faux provider。**禁止用真实 LLM 驱动这些确定性测试**——外部服务抖动会让结果不可复现（顾问 2026-07-31 的实测即因 DeepSeek "Service is too busy" 与 live 驱动的固有不确定性而失败）。

| goal 8 人工项 | 自动化方式 | 必须覆盖 |
|---|---|---|
| 会话 | faux provider | 新建、命名、switch、branch、compact、export、`--continue`、`--resume`；**两个分支互不串线（正向与反向都要断言）** |
| 模式 | 进程级 + faux provider | `--print` 仅最终文本无杂音；`--mode json` 每行合法 JSON 且事件序列正确；`--mode rpc` 请求/响应/事件往返 |
| 扩展 | faux provider | 加载、命令、tool、hook、`/reload`；旧扩展兼容；custom UI/renderer；reload 后旧 generation 正确 stale |
| 启动与退出 | PTY harness | 正常退出、Ctrl-C、挂起/恢复后 termios、光标、回显、bracketed paste 均还原 |
| 输入编辑 | PTY + 虚拟终端快照 | 多行、CJK、emoji、宽字符换行、按词移动、history、kill/yank/yank-pop、undo |
| 补全 | PTY + 快照 | slash、路径、`@`；键盘选择、取消、应用后 undo |
| Overlay | PTY + 快照 | 各选择器、双 overlay 焦点、CJK 边框、窄宽 resize |
| 渲染（结构部分） | faux provider + 快照 | 流式 text/thinking/tool、Markdown 各元素、折叠展开、状态栏字段 |

**补充要求**：`--fork` 的用法（接受 entry id 还是 session id、格式为何）在测试与 README 中明确，顾问实测时曾因此误用（`Session not found: <entry-id>`）——若属文档不清则补文档，若属实现与基线不符则按基线修正。

完成后更新 `docs/acceptance/goal-v8-final.md`：这八项由"待用户人工确认"改为"已自动化覆盖"，并注明对应测试名。

## 二、Part B：视觉与交互体验对齐

**目标：cadr 的 TUI 在视觉与交互观感上与基线 pi 一致，而不仅是行为语义一致。** 这是账本此前的真空区——352 个测试断言的是字符与结构，从不断言配色、间距、节奏。

### B1. 建立可运行的对照环境
在新审计 checkout 内安装依赖并跑通原版 pi 的交互式 TUI，作为唯一参照物（禁止用非基线版本对照）。启动方式写入报告，供用户随时自行 A/B。

### B2. 机械对齐（可验证部分）
从基线逐项提取并与 cadr 对照，产出差异表 `docs/visual-parity.md`：
1. 主题与色板：默认主题全部色值、语义色（用户/助手/思考/工具/错误/状态）、真彩与 256 色降级策略；
2. 布局与间距：各区域 padding/margin、缩进级数、分隔线与边框字符集、宽度自适应断点；
3. 元素样式：Markdown 各元素（标题/列表/引用/代码块/表格/链接）、工具块的展开与折叠形态、状态栏字段顺序与格式、选择器高亮与滚动指示、autocomplete 弹层样式；
4. 动效参数：流式重绘节奏、光标行为、加载指示器形态与频率。
每一项标注"一致 / 不一致（已改齐）/ 有意差异（附理由并登记 README）"。

### B3. 动态对齐（用户确认部分）
产出逐场景 A/B 清单供用户在两个终端并排比对：冷启动、流式回答、长输出滚动、工具调用与展开、overlay 各选择器、CJK 与 emoji 混排、窄宽 resize、错误展示、退出。用户逐项确认为本 Part 的验收门禁。**这是全项目唯一仍需人眼的环节**——Part A2 已把行为层面的人工项全部转为自动化，此处只判观感。

### B4. 已知待修
- **footer 显示滞后**：登录或切换模型成功后，footer 仍显示启动时的模型（goal 8 补正期间记录，未越界修复）。属状态呈现问题，在本 Part 修复并补回归测试。

### B5. 完成的定义
`docs/visual-parity.md` 差异表逐项清零或记为已批准的有意差异 + 用户 A/B 清单逐项确认。**不以"看着舒服"为标准，以逐项对照为标准。**

## 三、Part C：客户端身份改为 cadr

1. 向 OpenAI 发送的 `originator` 由 `pi` 改为 `cadr`（`src/cadr-ai/oauth.lisp:264`、`src/cadr-ai/providers/openai.lisp:260` 及一切同源位置）。
2. 性质：向第三方声明客户端身份，非协议行为要求；沿用 `pi` 会把 cadr 的流量与错误归因到上游作者名下。**用户已批准的有意偏离基线。**
3. 受影响的对拍 fixture 按新值更新，并在测试与 parity-map 中**显式标注为已批准差异**，不得静默改 fixture。
4. **实测硬门禁**：改后必须用真实 `/login openai` 走通授权并完成一次真实对话。若因 originator 校验被拒，立即 blocked 并报告，**不得擅自回退为 `pi`**。
5. README 差异清单登记。

## 四、Part D：本地验证入口

1. 单一入口 `./scripts/verify.sh`：全量测试 → 隔离构建（cadr 与 cadr-server）→ 全部保留下来的 smoke。
2. 凭据门控与基线同构：有 DeepSeek/Codex OAuth 则跑对应 live 部分，无则跳过并打印原因，不得因缺凭据失败或伪装通过。
3. 末尾输出可一眼判读的汇总；退出码严格反映结果。
4. **不创建 GitHub Actions 或任何远端 CI 配置**（用户要求先本地跑通）。

## 五、Part E：版本、变更记录与仓库卫生

1. `CHANGELOG.md`：Keep a Changelog 风格，按 goal 级别粒度补记 v1 至今里程碑，含本次基线升级。
2. 版本号单一来源，`cadr --version` 与 `cadr-server --version` 一致；报告给出建议版本号与依据，**实际打 tag 由用户决定**。
3. 清理 `packages/` 下 TypeScript 时代的未跟踪构建残渣（删除前列清单，只删确认为构建产物的未跟踪内容）。
4. `goal*.md` 草稿按惯例归置；`.gitignore` 补齐，减少对 `.git/info/exclude` 的依赖。
5. `docs/` 索引化：列明各文档职责（architecture / parity-map / visual-parity / test-matrix / dependency-audit / open-questions / progress / proposals / acceptance），便于后续维护者与 agent 导航。

## 六、验收标准

1. Part A：新基线 363 个测试文件全 `C` 或经裁决 `N/A`；fixture 重生成差异逐条有交代；`packages/protocol` 已实现。
1.5. Part A2：goal 8 的八项人工验收全部有对应自动化测试且全绿；均以 faux provider 或 PTY 驱动，无一依赖真实 LLM；`goal-v8-final.md` 已相应更新。
2. Part B：`docs/visual-parity.md` 差异表清零或全部记为已批准差异；用户 A/B 清单逐项确认。
3. Part C：`originator=cadr` 在真实 `/login` 与真实对话中验证通过。
4. Part D：`verify.sh` 在有/无凭据两种条件下行为正确。
5. Part E：CHANGELOG、版本单一来源、清理清单、文档索引齐备。
6. 全量测试只增不减、全绿；每 Part 独立提交落账、独立报告章节（含 token 与耗时）。

## 七、原则

- 测试先行；冻结纪律与 object ID 对照贯穿全程；凭据纪律不变。
- **完成 = 已提交落账**，未提交的完成宣告无效。
- 新第三方依赖必须预审 blocked 等授权，先斩后奏视为违规。
- **smoke/验证脚本不得以规范化、改写输入或弱化断言的方式取得通过**（goal 8 补正的教训）。
- 远程仓库创建需用户账号，不在本 goal 范围；报告中可给出建议命令。
- 完成后暂停，等待用户验收。
