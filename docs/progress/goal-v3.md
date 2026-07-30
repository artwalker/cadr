# GOAL v3: 项目更名与仓库迁移（pi-cl → cadr）

## 〇、前置条件与定位

本 goal 在 goal-v2 全部验收通过后执行。这是一个**纯迁移任务**：不新增功能、不修复非阻塞 bug、不重构逻辑。任何"顺手改进"都视为越界。若迁移中发现功能性 bug，记入 docs/open-questions.md，不在本 goal 内修。

新名称：**cadr**。命名含义（写入 README）：cadr 取列表第二个元素，本项目为 pi 的第二个实现；同时致敬 MIT CADR Lisp Machine。

## 一、迁移步骤

### 1. 仓库迁移
- 将现有仓库完整迁移至新目录/仓库 `cadr`，**保留完整 git 历史**（整仓库移动后在新仓库中完成改名提交；禁止复制文件重开历史——阶段报告与 test-matrix 的演进记录是项目可审计性的一部分）。
- 改名相关变更拆分为清晰的提交序列（如：目录与 system 改名 → 符号与包改名 → 文档改名 → 迁移逻辑），不要一个巨型提交。

### 2. 代码层全局改名
- ASDF systems：pi-ai → cadr-ai，pi-agent → cadr-agent，pi-cli → cadr-cli（含 /tests 变体），.asd 文件名与内容同步。
- CL package 名与 nickname 全部改为 cadr-* 前缀；导出符号中含 pi 字样者一并更名。
- **扩展 API 的包名此刻必须定稿**：扩展系统的稳定接口（define-tool、define-command、define-event-hook、define-prompt-template）迁移后从 cadr-agent（或其指定的接口 package）导出。goal-v2 中"发布即稳定"的承诺从更名后的名字起算——此次是唯一一次允许的接口命名空间变更，之后冻结。
- 可执行文件：pi-cl → cadr；build.sh、build.lisp、test.sh 同步。
- REPL 提示符、--version、--help、错误信息中的产品名全部更新。

### 3. 用户侧路径与环境变量（含数据迁移）
- 配置目录：~/.pi-cl/ → ~/.cadr/（sessions、extensions、auth.json 全部随迁）。
- 启动时若检测到旧目录存在且新目录不存在：提示用户并在确认后自动迁移（移动而非复制；auth.json 迁移后保持 0600）。--yolo 或非交互环境下拒绝自动迁移并给出手动迁移指令，fail closed。
- 环境变量前缀：PI_CL_* → CADR_*。旧变量在一个过渡版本内仍被读取但打印弃用警告；README 记录弃用时间线。
- 会话文件内部若含产品名字段，新写入用新名，读取兼容旧值。

### 4. 文档
- README 重写头部：项目名 cadr、命名含义、一句话定位。
- **必须保留**：对 earendil-works/pi 固定参考提交的行为参照声明、致谢、MIT 许可信息、差异清单（含"本项目与原版 pi 无隶属关系"的免责声明）。
- 除上述参照与致谢外，全仓库（代码、注释、文档、脚本、fixture 命名）不得残留旧名。docs/progress/ 历史报告属于历史记录，不改写。

## 二、验收标准

1. `grep -ri "pi-cl\|pi-ai\|pi-agent\b" --exclude-dir=.git --exclude-dir=docs/progress` 在新仓库中除 README 参照章节与 CHANGELOG/迁移说明外零命中（grep 命令与豁免清单写入迁移报告）。
2. 全量测试（v1+v2 全部套件）在新仓库全绿，数量不少于迁移前。
3. 隔离环境一键构建产出可执行文件 `cadr`；--version 显示新名。
4. 数据迁移测试：预置旧 ~/.pi-cl/（含 sessions、extensions、auth.json）→ 交互确认后完整迁移，权限保持，--continue 能恢复旧会话；非交互场景 fail closed 测试。
5. 旧环境变量过渡兼容 + 弃用警告有测试覆盖。
6. git 历史完整（迁移前最后一个 commit 的 hash 在新仓库历史中可达）。
7. 迁移报告 docs/progress/migration.md：改名映射表、数据迁移策略、豁免残留清单、测试与构建证据。

## 三、原则

- 本 goal 期间冻结功能开发；发现的功能问题只记录不修复。
- 扩展 API 命名空间自本次更名后冻结，后续任何 goal 不得再改。
- 迁移报告必须诚实列出所有豁免的旧名残留及理由，不允许静默保留。
