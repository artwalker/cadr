# GAP-42a 上游用例对应

范围是 v1.4.0 的 pi-env 守护进程和本地环境。`packages/env/src/ssh.ts`、`packages/env/src/remote-env.ts` 以及 `ssh.test.ts`、`remote.test.ts`、`ssh-external.test.ts` 属于 GAP-42b，下表标成范围外。断言对着 `git show v1.4.0:<path>` 和本机 `git check-ignore -v --no-index`。

FiveAM 都在 `test/cadr-env/env-test.lisp`。

## 守护进程 Rust 测试

| 上游 | FiveAM | 状态 |
|---|---|---|
| `decode.rs` `keeps_a_feff_that_does_not_start_the_stream` | `utf8-and-window-and-scan` | 已覆盖 |
| `decode.rs` `drops_only_a_leading_mark_and_never_sniffs_utf16` | 同上 | 已覆盖 |
| `decode.rs` `replaces_an_incomplete_sequence_once` | 同上 | 已覆盖 |
| `frame.rs` `round_trips_json_and_payload` | 各 `request` 往返 | 已覆盖 |
| `list.rs` `lists_files_and_directories_depth_first_in_name_order` | `daemon-filesystem-and-listing` | 已覆盖 |
| `list.rs` `skips_what_git_ignores_only_in_work_trees` | `gitignore-and-bounds-and-symlinks` | 已覆盖 |
| `list.rs` `lists_symbolic_links_without_following_them` | 同上 | 已覆盖 |
| `list.rs` `stops_at_bounds_with_truncated` | 同上 | 已覆盖 |
| `list.rs` `fails_on_missing_roots_files_and_aborts` | `daemon-filesystem-and-listing` 的 ENOENT/ENOTDIR；取消见下行 | 已覆盖 |
| `scan.rs` `locates_and_measures_lines_like_whole_file_decoding` | `utf8-and-window-and-scan` | 已覆盖 |
| `window.rs` `counts_everything_and_keeps_more_than_the_window_after_a_skip` | `output-window-keeps-the-tail-after-a-skip` | 新增 |
| `window.rs` `delivers_streams_apart_without_skips` | `utf8-and-window-and-scan` | 已覆盖 |
| `sys/windows.rs` `quotes_arguments_like_libuv` | 无 | 范围外：只在 Windows 的 CreateProcess 引号。Linux 守护进程不走这条。Windows 上 pty 的 `ENOTSUP` 与 `Terminals are not supported on this system yet` 由 `exec-and-pty-and-watch` 锁住 |

## 协议文档（`packages/env/docs/protocol.md`）

| 行为 | FiveAM | 状态 |
|---|---|---|
| 首行 `PI-ENV <token>`，之后才是帧 | `make-pipe-connection` 的 `read-banner` | 已覆盖 |
| 取消先登记再执行，紧跟的取消不会丢 | `list-files-cancel-star-and-symlink-root` 把请求帧和取消帧一次写完 | 新增 |
| `listFiles` 在条目之间以 `aborted` 结束 | 同上，`code` 与 `message` 都是 `aborted`；随后同一连接仍能列出 1240 条 | 新增 |
| `scanLines` 在块之间以 `aborted` 结束 | 同上，128 万字节的文件 | 新增 |
| `exec` / `pty` 的取消以 `aborted` 结束；`mode: kill` 以 137 结束 | `exec-and-pty-and-watch`：`sleep 30` 的 kill 是 137；`sleep 100` 的 pty 取消是 `aborted` | 已覆盖 / 新增 |
| `ptyWrite`、`ptyResize`、`ptyForeground` 在读帧线程按到达顺序回答 | 未知 `target` 999 的 `ptyWrite` 是 `EBADF` | 已覆盖。resize 与前台作业名见终端表 |
| 5 秒 ping，30 秒无字节则停 | `silence-constants` | 已覆盖 |
| `hello` 带 `features` 含 `listFiles` | `daemon-filesystem-and-listing` | 已覆盖 |
| `listFiles` 深度优先、名字按字节序；`.git` 与 `exclude` 整棵跳过 | `daemon-filesystem-and-listing`、`gitignore-and-bounds-and-symlinks` | 已覆盖 |
| gitignore 用 ignore crate：`*` 与 `?` 不跨 `/`，`**` 跨目录 | `list-files-cancel-star-and-symlink-root` 的 `glob-segment`。本机 `git check-ignore --no-index`：`sub/*.log` 只中 `sub/y.log`，不中 `sub/a/x.log`；`sub/**/x.log` 中 `sub/x.log`、`sub/a/x.log`、`sub/a/b/x.log` | 新增 |
| 列目录根用 `metadata`（跟随符号链接）；树内链接不跟随 | 根 `link` → `dir` 得到 `f inner.txt`、`l loop`；指向文件是 `ENOTDIR` 且消息含 `scandir` | 新增 |
| 缺路径 `ENOENT`，文件根 `ENOTDIR` | `daemon-filesystem-and-listing` | 已覆盖 |
| Windows pty `ENOTSUP` | `exec-and-pty-and-watch` | 已覆盖 |

## `packages/env/test/terminal.test.ts`

| 用例 | FiveAM | 状态 |
|---|---|---|
| `runs a program in a terminal with input, resizing and its exit code` | 退出码 3 在 `exec-and-pty-and-watch` | 已覆盖退出码。`IS-A-TTY`、`stty size`、改成 100×30 需要交互 shell，本行没有再锁 |
| `reports the job in the foreground, not the shell at its prompt` | 无 | 范围外：要 `/bin/sh -i` 把 `sleep` 放到前台并读 `comm`。`ptyForeground` 已在守护进程里，这次返修没有这条交互锁 |
| `delivers raw bytes, not decoded text` | `exec-and-pty-and-watch` 载荷 `#(97 255 98)` | 已覆盖 |
| `keeps input in order` | 无 | 范围外：四万字节要在 pty 请求进行中连续 `ptyWrite`。本次没有这条锁 |
| `kills the program on close` | `sleep 100` 取消后 `aborted` | 新增 |
| `fails to open in a missing directory` | 消息含 `Working directory does not exist` | 新增 |
| `rejects writes to a terminal that does not exist` | `ptyWrite` target 999 为 `EBADF` | 新增 |

## `packages/env/test/conformance.test.ts`

文件本身没有 `it`。它调用 durable 的 `registerEnvConformance`，对 `RemoteExecutionEnv` 和 `LocalExecutionEnv` 各跑一遍。`RemoteExecutionEnv` 属于 GAP-42b。`LocalExecutionEnv` 只把 `listFiles` 交给守护进程，其余方法是 durable 的 `NodeExecutionEnv`。

| 用例 | FiveAM | 状态 |
|---|---|---|
| `listFiles lists files and directories depth first in name order` | `daemon-filesystem-and-listing` | 已覆盖 |
| `listFiles skips what git ignores in work trees, .git, and excluded names` | `gitignore-and-bounds-and-symlinks` | 已覆盖 |
| `listFiles stops at its bounds and reports truncated` | 同上的 maxEntries、maxBytes、timeoutMs 0。`maxEntries` 0 截成空且 truncated。`-1` 与 `1.5` 在客户端 | 已覆盖 / 新增 |
| `listFiles fails on missing directories, files, and aborts` | ENOENT、ENOTDIR，以及已经取消的请求以 `aborted` 结束 | 已覆盖 / 新增 |
| `listFiles lists symbolic links without following them` | 树内链接不跟随；根是链接时列出 `f inner.txt`、`l loop` | 已覆盖 / 新增 |
| `listFilesOver` 对 `maxEntries`、`maxBytes`、`timeoutMs` 要求非负安全整数，句子是 `<key> must be a non-negative safe integer`；非法值先于 `not_supported` | `list-files-cancel-star-and-symlink-root`：`-1`、`3/2`、`9007199254740992` | 新增 |
| 其余 conformance（binary reader、directory reader、watch、argv exec、windowed exec、symlink reader） | 无 | 范围外：`LocalExecutionEnv` 这些方法不进守护进程；远程那一半是 GAP-42b |

## 明确划给 GAP-42b 的测试

| 文件 | 状态 |
|---|---|
| `packages/env/test/ssh.test.ts` 全部 8 个 `it` | 范围外：GAP-42b |
| `packages/env/test/ssh-external.test.ts` `reaches the remote system through its default shell` | 范围外：GAP-42b |
| `packages/env/test/remote.test.ts` 全部 8 个 `it` | 范围外：走 `RemoteExecutionEnv`。其中 `cancels a listing in the daemon` 的守护进程一半由上面的取消测试锁住，客户端的 `AbortSignal` 仍是 GAP-42b |
| `packages/env/test/differential.test.ts` 两个 `it` | 范围外：比较 `RemoteExecutionEnv` 与 `NodeExecutionEnv`，属于 GAP-42b |

## 父行 review-fail

| 记录 | 结果 |
|---|---|
| listFiles 取消被读帧线程吃掉 | `listFiles` 与 `scanLines` 离开读帧线程，控制块在线程启动前登记 |
| 锚定 `*` 跨斜杠 | 按路径段匹配，`*` 与 `?` 留在一段里 |
| 符号链接根报 ENOTDIR | 根用 `stat` |
| `sb-thread:join-thread` | `production-env-joins-go-through-cadr-core`；`src/cadr-env` 没有这个调用 |
| SSH 部署 | 留在 GAP-42b |
