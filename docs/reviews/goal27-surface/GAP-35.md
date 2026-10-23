# GAP-35 上游用例对应

范围是 v1.4.0 的 TUI 写日志：`packages/tui/src/terminal.ts` 的 `writeLogPath` 和 `write()`，以及哪些字节走 `terminal.write`、哪些走 `process.stdout.write`。相关控制流在 `packages/tui/src/tui.ts`（`start`、`stop`、`setTerminalColorSchemeNotifications`、`queryCellSize`、`queryTerminalColors`）和 `packages/tui/src/tui-main-screen.ts` 的 `positionHardwareCursor`。断言对着 `git show v1.4.0:<path>`。配色通知的 start 前写入用本机 Node 22.22.0 对 v1.4.0 `TuiBase` 的探针复核（2026-10-23，`/tmp/gap35-probe.mts`）：`stopped` 初值是 false，`set(true)` 之后 `write` 序列已是 `ESC[?2031h`，`start` 再追加 `ESC[?2031h` 和 `ESC[16t]`（图像能力为 kitty）。`stop` 在开关仍开着时追加 `ESC[?2031l`。`stop` 之后再 `set(true)` / `set(false)` 不写；下一次 `start` 按当时的开关再写 `ESC[?2031h` 和 `ESC[16t]`。

v1.4.0 没有单独的 `PI_TUI_WRITE_LOG` 测试文件。下面先列源码和文档里的行为，再列这一行会碰到的测试文件里的每一个 `it`。

## 源码和文档（没有单独的 `it`）

| 行为 | FiveAM | 状态 |
|---|---|---|
| `PI_TUI_WRITE_LOG` 未设置或空串时不记日志。cadr 读 `CADR_TUI_WRITE_LOG`，不读 `PI_TUI_WRITE_LOG` | `tui-write-log-path-follows-cadr-env-file-or-directory` | 已覆盖 |
| 已有目录里新建 `tui-<本地 YYYY-MM-DD_HH-MM-SS>-<pid>.log`。`path.join` 收掉 `..` 和多余斜杠，符号链接留在路径里。其它字符串当文件路径原样追加 | `tui-write-log-join-matches-node-path-join`、`tui-write-log-path-follows-cadr-env-file-or-directory` | 已覆盖。`path.join` 期望串与 Node 22.22.0 的 `path.posix.join` 和 `path.win32.join` 一致 |
| `write()` 先写 stdout，再把同一段 UTF-8 追加进日志。写日志失败被忽略。stdout 失败则不记。进度序列不进日志 | `tui-write-log-appends-writes-and-ignores-log-errors` | 已覆盖 |
| `setTitle` 用 `process.stdout.write` 发 OSC 0，不进日志 | `tui-write-log-splits-stdout-writes-from-terminal-write` | 已覆盖 |
| `queryTerminalColors` 经 `terminal.write` 写 OSC 10、OSC 11、OSC 4 和 DA1，进日志 | 同上，以及 `terminal-color-query-assembles-foreground-and-palette`、`process-terminal-theme-color-query-keeps-typed-input` | 已覆盖 |
| 单独的背景色 OSC 11 进日志 | `tui-write-log-splits-stdout-writes-from-terminal-write` | 已覆盖 |
| `setTerminalColorSchemeNotifications`：值没变不写。`stopped` 为 false 时（含 start 之前）值变了就 `terminal.write` `ESC[?2031h` 或 `ESC[?2031l`。`stop()` 把 `stopped` 设为 true 之后再改开关不写 | `tui-write-log-splits-stdout-writes-from-terminal-write`、`tui-write-log-records-cell-size-and-color-scheme-startup`、`process-terminal-color-scheme-notification-lifecycle` | 已覆盖。第三次返修把 start 前的 `set(true)` 从「文件不存在」改成锁住 `ESC[?2031h` |
| `start` 在开关开着时再 `terminal.write` 一次 `ESC[?2031h`，图像能力打开时再写 `ESC[16t]`。`stop` 在开关仍开着时写 `ESC[?2031l`。括号粘贴、光标隐藏、键盘 DA 查询走 stdout，不进日志 | `tui-write-log-records-cell-size-and-color-scheme-startup` | 已覆盖。start 前已经有一次 `ESC[?2031h`，start 之后日志是两次 `?2031h` 加 `ESC[16t]`，stop 再加 `?2031l`。stop 之后把开关关掉再打开，日志不变；再 start 追加 `ESC[?2031h` 和 `ESC[16t]` |
| `hideCursor` / `showCursor` 走 stdout，不进日志。`positionHardwareCursor` 的列移动和行移动走 `write()`，进日志 | `tui-write-log-splits-stdout-writes-from-terminal-write` | 已覆盖 |
| `packages/tui/README.md` 的 Debug logging：`PI_TUI_WRITE_LOG=/tmp/tui-ansi.log` 抓原始 ANSI。cadr 的环境名是 `CADR_TUI_WRITE_LOG` | `tui-write-log-path-follows-cadr-env-file-or-directory` | 已覆盖文件路径。文档里的 demo 命令 `node test/chat-simple.ts` 是范围外 |
| `packages/coding-agent/docs/tui.md` 第 182 行：用 `PI_TUI_WRITE_LOG` 抓原始 ANSI，并建议测窄宽、宽字符、resize、主题、焦点和全屏 | 写日志路径同上 | 已覆盖环境变量本身。窄宽、宽字符、resize、主题、焦点和全屏是渲染诊断建议，不是写日志的字节合同，范围外 |
| CHANGELOG 里 `PI_TUI_WRITE_LOG` 的目录路径和 `tui-<timestamp>-<pid>.log` | `tui-write-log-path-follows-cadr-env-file-or-directory` | 已覆盖 |

## `packages/tui/test/terminal.test.ts`

27 条 `it`。没有一条断言 `PI_TUI_WRITE_LOG`。它们测的是超时、Shift+Enter、Kitty、OSC 7501、进度清序列和行列回退，属于 GAP-36、GAP-46 和终端输入，不是这一行的写日志分叉。

| 用例 | FiveAM | 状态 |
|---|---|---|
| `uses PI_TUI_ESC_TIMEOUT when configured` | `escape-timeout-follows-cadr-tui-esc-timeout-and-ssh` | 范围外：GAP-46。cadr 读 `CADR_TUI_ESC_TIMEOUT` |
| `ignores invalid PI_TUI_ESC_TIMEOUT values` | 同上 | 范围外 |
| `defaults to 100ms over SSH` | 同上 | 范围外 |
| `defaults to 10ms otherwise` | 同上 | 范围外 |
| `rewrites Return to CSI-u Shift+Enter when native Shift detection is enabled and Shift is pressed` | 无同名锁 | 范围外：本机 Shift 检测，不进写日志 |
| `leaves Return unchanged when native Shift detection is disabled` | 无同名锁 | 范围外 |
| `leaves Return unchanged when Shift is not pressed` | 无同名锁 | 范围外 |
| `leaves non-Return input unchanged` | 无同名锁 | 范围外 |
| `rewrites Apple Terminal Return to CSI-u Shift+Enter when Shift is pressed` | 无同名锁 | 范围外 |
| `leaves Apple Terminal Return unchanged when Shift is not pressed` | 无同名锁 | 范围外 |
| `leaves non-Apple Terminal Return unchanged when Shift is pressed` | 无同名锁 | 范围外 |
| `leaves non-Return input unchanged`（Apple 那组） | 无同名锁 | 范围外 |
| `queries Kitty mode before enabling modifyOtherKeys fallback` | `program-status-restart-does-not-let-an-old-da-end-the-query` 锁的是重启后的 DA，不是这条 Kitty 查询顺序 | 范围外：键盘协议协商 |
| `activates Kitty mode for non-zero negotiated flags` | 无同名锁 | 范围外 |
| `falls back to modifyOtherKeys for zero Kitty flags` | 无同名锁 | 范围外 |
| `falls back to modifyOtherKeys for device attributes without Kitty flags` | 无同名锁 | 范围外 |
| `forwards device attributes replies that answer other queries` | `terminal-response-filter-consumes-only-control-replies` | 范围外：DA 转发，不是写日志 |
| `forwards normal input while waiting for Kitty response` | 无同名锁 | 范围外 |
| `tracks split Kitty confirmation` | 无同名锁 | 范围外 |
| `reports the latest status once the terminal answers the query before DA` | `program-status-reports-after-the-terminal-answers-before-da` | 范围外：GAP-36 |
| `reports nothing when DA arrives first and swallows late replies` | `program-status-da-first-swallows-a-late-reply` | 范围外：GAP-36 |
| `skips the query when PI_PROGRAM_STATUS is set` | `program-status-one-reports-without-asking`、`program-status-zero-never-reports`、`program-status-ignores-the-legacy-name` | 范围外：GAP-36。cadr 读 `CADR_PROGRAM_STATUS` |
| `does not let a DA reply from before a restart end the new query` | `program-status-restart-does-not-let-an-old-da-end-the-query` | 范围外：GAP-36 |
| `clears the status on stop and reports it again after restart` | `program-status-stop-clears-and-asks-again` | 范围外：GAP-36 |
| `replays buffered CSI-prefix input when it is not a Kitty response` | 无同名锁 | 范围外 |
| `writes a valid OSC 9;4 clear sequence` | `process-terminal-progress-repeats-and-clears`、`tui-write-log-appends-writes-and-ignores-log-errors` | 进度清序列本身范围外。进度不进写日志已覆盖 |
| `falls back to COLUMNS and LINES before default dimensions` | 无同名锁 | 范围外：行列回退 |

## `packages/tui/test/terminal-colors.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `parses color scheme reports` | `terminal-color-reports-are-strictly-parsed`、`terminal-response-filter-consumes-color-scheme-reports` | 范围外：解析，不是写日志 |
| `parses OSC 10, 11, and 4 replies` | `terminal-color-query-assembles-foreground-and-palette` | 范围外：解析 |
| `queries all colors in one write and consumes the replies` | `process-terminal-theme-color-query-keeps-typed-input`、`tui-write-log-splits-stdout-writes-from-terminal-write` | 已覆盖一次写出整段查询，并且这段进日志 |
| `consumes delayed Ghostty color fragments without typing their tail or opening the editor` | `terminal-response-filter-consumes-only-control-replies` | 范围外：分片消费 |
| `resolves on DA1 with the replies that arrived, in query order` | `terminal-color-query-assembles-foreground-and-palette` | 范围外：回答顺序 |
| `reports late replies after a timeout and consumes them until DA1` | `process-terminal-theme-color-query-keeps-typed-input` | 范围外：迟到回答。查询字节进日志已由写日志测试锁住 |

## `packages/tui/test/tui-cell-size-input.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `forwards bare escape even when a cell size query was sent at startup` | 无同名锁 | 范围外：单元格尺寸回答的转发。发出 `ESC[16t]` 并记入日志由 `tui-write-log-records-cell-size-and-color-scheme-startup` 锁住 |
| `consumes cell size responses and still forwards later user input` | 无同名锁 | 范围外：同上 |

## `packages/tui/test/exit-restore.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `restores terminal modes when the process exits without stop()` | `exit-without-stop-restores-terminal-modes`、`exit-restore-adds-progress-clear-and-modify-other-keys-when-active` | 已覆盖退出前缀。通知开着时前缀以 `ESC[?2031l` 开头。`set(true)` 在 start 之前先写出 `ESC[?2031h`，这条测试把这段算进同一条输出 |
| `does not restore twice after a normal stop()` | `stop-does-not-restore-terminal-modes-twice` | 已覆盖 |

外层 `describe("terminal restore on process exit")` 自己没有 `it`。

## `packages/coding-agent/test/theme-controller.test.ts`

九条 `it` 都是范围外。主题控制器用 mock 断言 `setTerminalColorSchemeNotifications(true/false)`，不看 stdout，也不看写日志。`re-queries the colors on appearance changes and lets them decide` 和 `disables terminal appearance updates when disposed` 是这两次调用。字节分叉在 `tui-write-log-splits-stdout-writes-from-terminal-write`。

## 已记录的 review-fail 和第三次返修

| 记录 | 结果 |
|---|---|
| 窗口标题进了日志 | `terminal-set-title` 走 stdout。`tui-write-log-splits-stdout-writes-from-terminal-write` 锁日志只有 `frame`，stdout 是 OSC 0 加 `frame` |
| 主题色查询不进日志 | `terminal-query-theme-colors` 和 `terminal-query-background-color` 走 `terminal-write`。同一条测试锁 OSC 10/11/4/DA1 和单独的 OSC 11 |
| 单元格尺寸和配色通知不进日志 | `terminal-start` 的 `ESC[?2031h` 与 `ESC[16t]`、`terminal-stop` 的 `ESC[?2031l`、`terminal-set-color-scheme-notifications` 都走 `terminal-write`。`tui-write-log-records-cell-size-and-color-scheme-startup` 锁整段日志 |
| 主屏硬件光标显隐进了日志 | `main-renderer-position-cursor` 把移动交给 `terminal-write`，显隐交给 stdout。同一条拆分测试锁日志里有列移动、没有 `ESC[?25h` / `ESC[?25l` |
| start 之前打开配色通知不写 `ESC[?2031h` | `stopped` 初值是 false。`terminal-set-color-scheme-notifications` 在还没 stop 时就 `terminal-write`。两条写日志测试改成锁 start 前的 `ESC[?2031h`，以及 start 再追加一次 |
