# Goal 8 终局验收包

固定基线：
`earendil-works/pi@71efc6f0c1909874ec8c944637a9ae7fc0e2d508`。
机械验收已完成；下列真实终端人工项必须由用户逐项确认后，项目才能进入
维护态。

## 机械验收

- [x] parity-map：`351 C / 0 U / 0 M / 1 N/A`；唯一 N/A 为用户逐文件批准的
  `packages/coding-agent/test/config.test.ts`。
- [x] `./scripts/test-cl.sh`：`2987/2987`。
- [x] `./build.sh`：缺少 `sb-core-compression` 时降级成功；
  `cadr 0.1.0`，65,381,272 bytes，mode 0755。
- [x] `./build-server.sh`：同样降级成功；
  `cadr-server 0.1.0`，57,220,848 bytes，mode 0755。
- [x] `./scripts/acceptance-smoke.sh`：延迟持久化、`--continue`、精确
  `--resume`。
- [x] `./scripts/test-wave2-process-modes.sh`：text、自动 stdin、JSONL、
  RPC intervention/UI/EOF、SIGTERM cleanup。
- [x] `./scripts/migration-smoke.sh`：非交互 fail-closed、完整目录移动、
  auth mode 0600、迁移后 continuation。
- [x] `./scripts/server-smoke.sh`：真实 Unix socket 上
  spawn/list/status/RPC/stop。
- [x] `./scripts/goal5-manual-tui-smoke.sh`：overlay focus、CJK frame、
  image fallback、resize、terminal restore。
- [x] `./scripts/live-deepseek-smoke.sh`：DeepSeek streaming。
- [x] `./scripts/live-print-smoke.sh`：DeepSeek one-shot print。
- [x] `./scripts/live-extension-smoke.sh`：DeepSeek write/reload/invoke。
- [x] `CADR_ALLOW_LIVE_TOOL_SMOKE=1 ./scripts/live-repo-smoke.sh`：
  DeepSeek read/edit/fail/fix/pass。
- [x] `./scripts/live-tui-smoke.sh`：DeepSeek 两轮真实 TUI 编辑、resize、
  CJK、autocomplete、undo、kill-ring、terminal restore。
- [x] `./scripts/live-openai-oauth-smoke.sh`：OpenAI Codex Responses。
- [x] `./scripts/live-evals-smoke.sh`：DeepSeek 与 Codex OAuth 两条 eval。
- [x] 无 Anthropic 凭据；对应 live block 按与基线相同的 credential gate
  跳过，没有用 fixture 冒充 live。
- [x] dependency audit：Wave 5/Part F 无新第三方依赖。
- [x] extension export SHA：
  `e0bcbf8c5f170efb99579fe6065579a8c2e93c7f1bd590b7502b08180ba54046`。
- [x] 相对 Goal 8 开工提交，`src/cadr-tui` production diff 为空。

## 用户真实终端人工验收

在真实终端、真实仓库副本或容器内执行；不要对重要工作区直接做工具写入测试。

- [ ] 启动与退出：启动 full-screen TUI；正常退出、Ctrl-C、挂起/恢复后
  shell 回显、光标、粘贴与 termios 均恢复。
- [ ] 输入编辑：多行、CJK、emoji、宽字符换行；按词移动；history；
  kill/yank/yank-pop；undo。
- [ ] 补全：slash command、文件路径、`@`；键盘选择、取消、应用后 undo。
- [ ] Overlay：session、tree、model、scoped-model、settings、trust 选择器；
  双 overlay 焦点、CJK 边框、窄宽 resize 均正确。
- [ ] 渲染：流式 text/thinking/tool、Markdown 列表/表格/代码/链接；
  长内容折叠展开与状态栏 token/cache/cost。
- [ ] 图片：真实 Kitty/iTerm2 协议终端显示；不支持协议时 fallback；resize 后
  旧 image placement 清理。
- [ ] 工具：read/write/edit/bash/find/grep/ls 在隔离仓库默认直接执行，
  无核心审批弹窗；错误、超时、截断与后续恢复可见。
- [ ] 会话：新建、命名、switch、branch、compact、export、退出后
  `--continue` 与 `--resume`；两个分支内容不串线。
- [ ] 扩展：加载、命令、tool、hook、reload；旧扩展兼容；custom UI/renderer；
  reload 后旧 generation 正确 stale。
- [ ] 模式：`--print` 只输出最终文本；`--mode json` 每行合法 JSON；
  `--mode rpc` request/response/event 与 extension UI 往返。
- [ ] Server：一个终端运行 `cadr-server serve`，另一终端完成
  spawn/list/status/rpc/rpc-stream/stop；服务重启后旧 online instance
  收敛为 stopped。
- [ ] 安全立场：README 的默认 YOLO、容器隔离责任与可选审批 hook 示例符合
  用户预期。

所有未勾选项由用户确认后，Goal 8 才能最终验收；在此之前不得宣告项目进入
维护态。
