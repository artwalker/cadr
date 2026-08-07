# Goal 8 终局验收包

Goal 8 的历史固定基线为
`earendil-works/pi@71efc6f0c1909874ec8c944637a9ae7fc0e2d508`；
Goal 9 起当前规范基线已升级为
`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`。
此前机械验收因 OAuth smoke 改写真实凭据身份而退回。2026-07-31 补正后
必须重新完成本节；下列真实终端人工项仍须由用户逐项确认，项目才能进入
维护态。

## 机械验收

- [x] parity-map：`351 C / 0 U / 0 M / 1 N/A`；唯一 N/A 为用户逐文件批准的
  `packages/coding-agent/test/config.test.ts`。
- [x] `./scripts/test-cl.sh`：`3043 checks / 3042 pass / 1 skip / 0 fail`；
  唯一 skip 为本机无 `ANTHROPIC_API_KEY`。
- [x] `./build.sh`：缺少 `sb-core-compression` 时降级成功；
  `cadr 0.1.0`，65,348,488 bytes，mode 0755。
- [x] `./build-server.sh`：同样降级成功；
  `cadr-server 0.1.0`，57,155,288 bytes，mode 0755。
- [x] `./scripts/acceptance-smoke.sh`：延迟持久化、`--continue`、精确
  `--resume`。
- [x] `./scripts/test-wave2-process-modes.sh`：text、自动 stdin、JSONL、
  RPC intervention/UI/EOF、在服务端确认请求在途后执行 SIGTERM cleanup。
- [x] `./scripts/migration-smoke.sh`：非交互 fail-closed、完整目录移动、
  auth mode 0600、迁移后 continuation。
- [x] `./scripts/server-smoke.sh`：真实 Unix socket 上
  spawn/list/status/RPC/stop。
- [x] `./scripts/goal5-manual-tui-smoke.sh`：overlay focus、CJK frame、
  image fallback、resize、terminal restore。
- [x] `test/cadr-ai/live-provider-test.lisp`：凭据门控 DeepSeek 精确响应、
  stream 终态与 usage；无 Anthropic 凭据时按基线 skip。
- [x] `LOGIN-OPENAI-TEMP-STORE-DEFAULT-RESOLVER-ROUTES-CODEX-REQUEST`：
  临时 auth/config、登录桩与 HTTP 桩确定性覆盖
  `/login openai` → `openai-codex` 存储 → 默认模型解析 → Codex Responses；
  同时断言未写入错误的 `openai` 身份。
- [x] `test/cadr-cli/live-test.lisp`：DeepSeek 与 Codex 都在隔离 HOME 中
  显式指定 provider/model；Codex 只逐字节复制真实 auth 文件作为凭据输入，
  不读取用户 settings、session 或扩展。
- [x] `test/cadr-evals/live-evals-test.lisp`：DeepSeek 与 Codex eval、
  self-extension、repo read/edit/fail/fix/pass 均在 FiveAM 内凭据门控。
- [x] `./scripts/live-tui-smoke.sh`：DeepSeek 两轮真实 TUI 编辑、resize、
  CJK、autocomplete、undo、kill-ring、terminal restore。
- [x] 无 Anthropic 凭据；对应 live block 按与基线相同的 credential gate
  跳过，没有用 fixture 冒充 live。
- [x] shell smoke 机制收敛：逐脚本审计、删除七个可内置 live 脚本、仅保留
  五类边界的六个进程/终端 harness，且全部重新运行通过，见
  [`goal-v8-smoke-audit.md`](goal-v8-smoke-audit.md)。
- [x] 产品人工证据：真实 TUI `/login openai` 后不重启、不加参数直接发送提示；
  `auth.json` 同时保留旧 `openai` 记录并新增 `openai-codex`，settings 为
  `openai-codex/gpt-5.5`，同一 session 的 assistant 回复精确为
  `OAUTH_TUI_DIRECT_OK`。该证据不作为自动 live 测试的输入。
- [x] dependency audit：Wave 5/Part F 无新第三方依赖。
- [x] extension export SHA：
  `e0bcbf8c5f170efb99579fe6065579a8c2e93c7f1bd590b7502b08180ba54046`。
- [x] 相对 Goal 8 开工提交，`src/cadr-tui` production diff 为空。

### 与此前“通过”的区别

此前 `live-openai-oauth-smoke.sh` 和 `live-evals-smoke.sh` 先复制
`auth.json`，再用 `jq` 将 `openai` 键改名为 `openai-codex`；前者还显式
传入 provider/model。该路径证明的只是“改名并覆盖默认值后能用”，不能证明
`/login openai` 的产物或普通启动路径。两条旧 OAuth 通过结论现已撤回。

本轮有效证据必须同时满足：

1. 确定性层使用临时 auth/config 和网络桩覆盖 login change → 正确身份存储
   → 默认模型解析 → Codex Responses，不读 homedir；
2. live 层只以可用凭据门控，测试内显式指定 provider/model；CLI 的隔离
   HOME 仅逐字节复制 auth 输入，不改键、不规范化；
3. eval live 层注入显式 provider/model resolver；其 project、session 与
   extension 继续使用 harness 自建的隔离目录；
4. `cadr-ai` 两条 provider live 本来就只读环境凭据并显式构造 provider/model，
   无需修改；
5. 在用户当前 `openai-codex/gpt-5.6-luna` settings 下运行全量仍全绿，
   且测试前后 settings 逐字段不变。

## 用户真实终端人工验收

在真实终端、真实仓库副本或容器内执行；不要对重要工作区直接做工具写入测试。

- [x] 启动与退出：启动 full-screen TUI；正常退出、Ctrl-C、挂起/恢复后
  shell 回显、光标、粘贴与 termios 均恢复。
  *永久门禁：`scripts/goal9-a2-pty.sh` 的 `normal`、`ctrl-c`、
  `suspend-resume` 三个真实 PTY 场景。*
- [x] 输入编辑：多行、CJK、emoji、宽字符换行；按词移动；history；
  kill/yank/yank-pop；undo。
  *永久门禁：
  `GOAL9-A2-INPUT-EDITOR-PTY-EVENTS-AND-VIRTUAL-SCREEN-COVER-FULL-CONTRACT`。*
- [x] 补全：slash command、文件路径、`@`；键盘选择、取消、应用后 undo。
  *永久门禁：
  `GOAL9-A2-COMPLETION-PTY-EVENTS-SNAPSHOT-SELECTION-CANCEL-AND-UNDO`。*
- [x] Overlay：session、tree、model、scoped-model、settings、trust 选择器；
  双 overlay 焦点、CJK 边框、窄宽 resize 均正确。
  *永久门禁：
  `GOAL9-A2-OVERLAY-SELECTORS-FOCUS-CJK-AND-RESIZE-SNAPSHOTS`。*
- [x] 渲染：流式 text/thinking/tool、Markdown 列表/表格/代码/链接；
  长内容折叠展开与状态栏 token/cache/cost。
  *结构永久门禁：
  `GOAL9-A2-FAUX-STREAM-RENDERING-STRUCTURE-AND-STATUS-SNAPSHOTS`；纯观感留给
  Goal 9 Part B 的基线 A/B。*
- [x] 图片：真实 Kitty/iTerm2 协议终端显示；不支持协议时 fallback；resize 后
  旧 image placement 清理。
  *（顾问代验，2026-07-31，PTY + 环境能力伪造）：无能力终端出 `[Image:` 占位且
  零协议字节；`KITTY_WINDOW_ID=1` 下检出 `ESC _Ga=T,f=100,...,i=505` 传输序列；
  `TERM_PROGRAM=iTerm.app` 下检出 `ESC ]1337;File=inline=1;width=12;...`；
  重绘/退出检出 `a=d,d=I,i=505` 与 `a=d,d=A` 清理序列。*
- [x] 工具：read/write/edit/bash/find/grep/ls 在隔离仓库默认直接执行，
  无核心审批弹窗；错误、超时、截断与后续恢复可见。
  *（顾问代验，2026-07-31，隔离 git 仓库 + 真实 DeepSeek 五场景）：ls/find/grep
  定位 TODO；edit 将 `return a - b` 真实改写为 `return a + b`（磁盘核实）；
  write 创建 test_calc.py 且 bash 运行 python3 通过；不存在文件的错误清晰回传；
  500 行文件读取无异常。全程无 `[y/N]`/审批提示。*
- [x] 会话：新建、命名、switch、branch、compact、export、退出后
  `--continue` 与 `--resume`；两个分支内容不串线。
  *永久门禁：
  `GOAL9-A2-SESSION-WORKFLOWS-ARE-DETERMINISTIC-AND-BRANCHES-STAY-ISOLATED`。*
- [x] 扩展：加载、命令、tool、hook、reload；旧扩展兼容；custom UI/renderer；
  reload 后旧 generation 正确 stale。
  *永久门禁：
  `GOAL9-A2-EXTENSION-WORKFLOW-COVERS-LEGACY-UI-RENDERERS-AND-STALE-RELOAD`。*
- [x] 模式：`--print` 只输出最终文本；`--mode json` 每行合法 JSON；
  `--mode rpc` request/response/event 与 extension UI 往返。
  *永久门禁：
  `GOAL9-A2-PRINT-JSON-AND-RPC-MODES-COVER-THE-REAL-CONTRACT`。*
- [x] Server：一个终端运行 `cadr-server serve`，另一终端完成
  spawn/list/status/rpc/rpc-stream/stop；服务重启后旧 online instance
  收敛为 stopped。
  *（顾问代验，2026-07-31，隔离 `CADR_SERVER_DIR` + 双进程）：serve 建立
  Unix socket；spawn 返回 `status:"online"`（id 019fb654-…90cc）；`kill -9`
  模拟崩溃后重启 serve，`list` 与 `status` 均收敛为 `status:"stopped"`。
  spawn/list/status/rpc/stop 的常规路径另由 `./scripts/server-smoke.sh` 覆盖。*
- [x] 安全立场：README 的默认 YOLO、容器隔离责任与可选审批 hook 示例符合
  用户预期。
  *（顾问核实，2026-07-31，机制对齐判定）：用户裁定此项属"机制与 pi 一致即可"，
  无需主观判断。基线 `packages/coding-agent/README.md:499` 为 "**No permission
  popups.** Run in a container, or build your own confirmation flow with
  extensions"；cadr README 为"无内置审批对话框、无核心 `--yolo` 模式，隔离靠容器
  或等效沙箱，需要审批者通过 hook 扩展实现"，语义一致；`--approve`/`--no-approve`
  的项目信任语义亦与基线对齐。*

## 人工验收项的处置（用户裁决，2026-07-31）

- 标注"顾问代验"的三项（图片、工具、Server）由用户授权顾问以自动化方式执行，
  证据见上。
- 安全立场一项由用户裁定为"机制与 pi 一致即可"，已核实一致。
- **其余八项（启动与退出、输入编辑、补全、Overlay、渲染、会话、扩展、模式）
  转入 Goal 9 Part A2，以 faux provider 与 PTY 驱动的确定性自动化测试覆盖，
  进套件永久防退化**；机制与基线一致（基线 pi 的端到端验证同样使用 faux
  provider，见 `packages/agent/test/e2e.test.ts`），禁止用真实 LLM 驱动。
  其中无法自动化的纯观感判断并入 Goal 9 Part B 的 A/B 清单，由用户与基线 pi
  并排比对时一次性确认。

因此 Goal 8 的关账条件为：本文机械验收全部通过 + 上述处置生效。八项行为验收
的保障不因此减弱，而是升级为永久自动化；观感验收改由 Goal 9 Part B 承担。
