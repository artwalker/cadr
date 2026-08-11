# Goal 18 L5.1：人肉 A/B 发现的逐条归因（2026-08-10）

每条回答"现在哪道门禁会先于用户抓到它"。归因到具体门禁/测试名；
"已修复"不算归因。

| # | 用户发现 | 现在谁先抓到 |
|---:|---|---|
| 1 | TUI 各处间距不一致（多轮反复） | render-diff 全量门禁：45 场景 × 2 终端尺寸逐字节对拍 + 762 条可见字符串分支覆盖（C1–C5 的 TUI composition 收敛即由此驱动） |
| 2 | 退出时缺 `To resume this session:` | `commands-and-exit` 场景的 `post-exit-resume` 检查点；通道账 C-02/C-03（`docs/presentation-parity.md`）把 alt-screen 拆除后的 stdout 列为独立通道 |
| 3 | heredoc 多行命令渲染损坏 | `tools-success` 场景的 `bash-multiline`/`bash-long-command` 检查点（narrow 维度覆盖换行重排） |
| 4 | bash 截断提示重复两遍 | `tools-significant-states` 场景的 `bash-byte-limit`/`bash-line-limit`/`bash-overlong-line` 检查点（goal 16 P1-B 把截断状态补进场景矩阵） |
| 5 | 压缩状态文案与基线不一致 | `compaction-status-manual`/`compaction-status-threshold`/`compaction-status-overflow` 三场景 |
| 6 | `/export` 提示效果不同 | `commands-and-exit` 的 `slash-export` 检查点 + 裸文件名文案对齐 |
| 7 | bash 命令文本/read 行号颜色 | 可见字符串清单的 `stylePath`（颜色在分支模型内逐条对拍）+ `tools-success` 的 read/bash 检查点 |
| 8 | 路径未做 `~` 缩写 | 启动与选择器场景的 `<HOME>` 归一化 + 整屏对拍（路径显示行在多场景出现） |
| 9 | OAuth 回调页面简陋 | 通道账 C-06（cadr 自身服务返回内容）+ FiveAM 的 OAuth 页面测试（cons-cell 标识后为 cadr 自有资产） |
| 10 | 工具参数被 JSON 片段污染 | 流式组装的 grammar-coercion 测试（`test/cadr-ai/utilities-test.lisp`）+ tool-result/event 差分门禁 |
| 11 | 数字前空格被吞 | 同上（流式组装的空白处理回归）+ 事件差分 |
| 12 | 用一会儿特别卡（渲染 O(N²)） | Goal 11 性能与稳定性门禁（`scripts/bench.sh` + `goal11-stability.sh`，verify.sh 必经阶段） |
| 13 | 滚动+选文本后周期卡顿 | 持续交互基准 `sustained_mixed_interaction`（p99.9/最大停顿/GC 分布，`test/cadr-cli/live-gate-test.lisp` 引用锁定） |
| 14 | 登录对话框整体缺失 | `overlays-auth-*` 系列场景 + I2 派生的 `loginDialogCoverage`（八形态机械提取，缺映射即红灯） |
| 15 | Radius 浏览器流平文本 | `overlays-auth-browser-callback`(+`-complete`) 场景（showAuth/showProgress 双形态） |
| 16 | 启动资源区块四差异 | `startup-resources`（非空）与 `startup-first/existing/untrusted`（空）双态场景 + I3 双态规则 |
| 17 | 登录 ESC 取消死锁 | `goal18-login-cancel-test.lisp`（FiveAM 状态机回归）+ 每条取消路径场景以取消后交互收尾（A4.3 规则，写入 render-diff 文档） |
| 18 | 产品身份残留 | 产品身份门禁（`check-product-identity.py`，373 项逐条登记） |

## 残余人工面（显式清单，L5.3）

仍只能靠人工验证的面：真实终端的图片协议渲染（sixel/kitty 在宿主终端的
实际像素效果）、终端仿真器实现差异（conhost/Windows Terminal/tmux 外层的
转发行为）、macOS-only 平台路径（Apple Terminal modifier、sandbox-exec）、
真实 OAuth 浏览器往返（重定向到本机回环之外的运营商页面）、以及长会话
累积状态（小时级真实使用的内存与渲染老化）。各自原因：需要物理终端或
平台/凭据，harness 的 PTY 与 faux provider 无法替代。

## L5.2 退出后交互补探针——发现并报告的阻断（待裁决）

按 L5.2 给 15 个以 escape 收尾的场景补"退出后探针"（发送一条消息并等待
正常回复）时，探针交互本身全部通过（状态机健全——这正是否决此缺陷类
的证据），但**探针暴露了一个此前未覆盖的退出残影差异类**：

- 现象：`tools-success` 等场景的 process-exit 屏中，pi 的残留是紧凑的
  尾部（13 行、光标 0,15），cadr 残留整幅最终帧（32 行、光标 0,31）。
  内容文本一致，垂直布局不同。
- 边界：短会话两侧残影逐字节相等（既有 45 场景全绿即证）；内容超过视口
  的会话也相等（`tools-render-branch-sweep` 的 1.6MB 流式会话）；只有
  "超过启动区、未超视口"的中等高度带分歧。既有五个 auth 场景（含三条
  探针消息）两侧残影一致，说明这不是探针本身引起的。
- 判定：无现有裁定类可承载——I01 不覆盖文本几何差异，I02/I03/I04 语义
  均不符。按规则须新类别（建议 I05：退出残影范围差异，alt-frame vs
  scrollback 模型的拆除残留）或按缺陷修 cadr 的退出拆除（向基线的紧凑
  尾部对齐）。**两者都须用户裁决；探针补丁验证可重现后已**回退**，裁决前不落地。

## L5.2 裁决落地与收尾（2026-08-11）

用户裁决：I05 按缺陷修 cadr 的退出拆除路径，不新开裁定类（"只有'超过
启动区、未超视口'的中等高度带分歧"说明这是可修的实现差异而非语义分岔）。
落地与连带发现：

1. **原地重绘（bbbfed52a）**：harness ack 不再整屏 wipe，改为基线语义内
   的原地 canonical repaint（pi 的 viewportTop 只增不减、缩小留空行），
   退出残影与 pi 逐字节一致（tools-success 等）。
2. **settle 窗口竞态（本轮修复）**：重绘暴露瞬时帧高差——cadr 的主循环
   按墙钟轮询渲染，可能在 [最后 text-delta/message-end .. agent-end] 窗口
   拍到"完整正文 + Working 指示器"的帧（比 settle 帧高 2 行），视口只增
   不减，过冲以尾部空行残留，基线从不如此（其 message_end→agent_end 是
   一条同步事件链，定时器渲染器观测不到）。修复：settle-window-p 标志
   在块结束/message-end 置位、turn 解决事件清除，窗口内渲染帧省略工作
   指示器（tool-rendering.lisp / controller.lisp render-now）。竞态窗口
   从毫秒级（持久化 I/O）收窄到亚微秒级（流尾簿记）。证据：首版
   （message-end 置位）经四次窄屏×九检查点复跑全对 pin；加入块结束置位
   后全量门禁 gate11/gate12 连绿，verify.sh 21 确定性 + 2 live 阶段全绿。
3. **provider 上下文转换缺失（真缺陷，PIN 曾掩盖）**：排查
   user-bash-state-sweep/process-exit 的 I01-only 条目时发现其 pin 两侧
   SHA 本就不同（页脚 ↑14k vs ↑1.3k）却登记为"文本一致"——真实原因是
   cadr 构建 provider 上下文时从未做 convertToLlm 转换（基线
   agent-loop.ts:295），bash-execution/custom/branch-summary/
   compaction-summary 消息被静默丢弃，模型看不到 `!` 命令输出，真实
   provider 同受影响。修复：stream-assistant 构建请求上下文前经
   convert-agent-messages-to-llm 转换（turns.lisp）。修复后该检查点窄屏
   与 pi 完全一致。

被掩盖条目的机制教训：stream-interrupt-queue/process-exit 窄屏 pin 两侧
相等却挂 I04（stale）、user-bash-state-sweep/process-exit 窄屏 pin 两侧
不等却挂 I01-only（漏类）——两者均在 L5.2 探针提交中引入，且因全量门禁
在更早的漂移处先行失败而从未被绿色全量运行检验过。本轮已拆分/更正并
补足断言：stale 检查（屏等值不得挂语义类）与反向检查（I01-only 不得
收容屏差异）均为 fail-closed。
