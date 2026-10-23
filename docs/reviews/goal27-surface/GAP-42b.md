# GAP-42b 上游用例对应

范围是 v1.4.0 的 SSH 部署和 `RemoteExecutionEnv`。只调用系统 `ssh`、`ssh-keygen`、`sha256sum`，没有新的原生库。需要一台真实远端的用例在本机 `sshd` 上锁住；本机没有 Windows sshd，也没有 `PI_ENV_SSH_HOST` 指向的预配置主机。断言对着 `git show v1.4.0:packages/env/src/ssh.ts`、`remote-env.ts` 和同 tag 的测试。

FiveAM 在 `test/cadr-env/ssh-remote-test.lisp`。守护进程是本仓库的 Lisp 实现，测试把它包成可执行脚本再按上游的 sha256 路径部署。

## `packages/env/test/ssh.test.ts`

| 上游 `it` | FiveAM | 状态 |
|---|---|---|
| `refuses an untrusted host, then deploys and runs the daemon once its key is accepted` | `ssh-deploy-and-remote-env-match-v140` | 新增 |
| `reuses a verified daemon and replaces a tampered one` | 同上：未改内容时 mtime 不变；改掉后按新哈希换上 | 新增 |
| `verifies the daemon again before starting it after a lost connection` | 同上：`SIGKILL` 后下一次启动仍是同一份脚本 | 新增 |
| `lists files over SSH as the local environment lists them` | 同上：`.gitignore` 的 `out/`、`.hidden`、`a/b.txt`、`a/skip` | 新增 |
| `starts the daemon through the login shell only when asked` | 同上：默认读不到 `PI_ENV_LOGIN`，`login-shell` 为真时读到 `yes` | 新增 |
| `connects lazily and reports a failed start as the error of the operation` | 同上：第一次操作前没有平台信息；未信任主机的读是 `unknown` 且消息含 `not trusted`；命令函数抛出的错误是 `spawn_error` | 新增 |
| `accepts only host keys for the alias and never replaces a trusted key silently` | 同上：别名不对和 `@cert-authority` 拒绝；两次并行 accept 只留下一行；同类型新密钥要先 forget | 新增 |
| `refuses a changed host key` | 同上：`connect-ssh` 抛 `host-key-changed-error` | 新增 |

`UserKnownHostsFile` 里的 `%` 写成 `%%`，由 `ssh-percent-in-a-config-path-is-literal` 锁住。

## `packages/env/test/remote.test.ts`

九个 `it`。客户端对着本机 Lisp 守护进程，不经过 ssh。

| 上游 `it` | FiveAM | 状态 |
|---|---|---|
| `transfers only about a window of output a caller keeps, with exact counts` | `remote-env-matches-v140-over-the-lisp-daemon`：5_000_000 字节，`maxBytes` 1000，`maxLines` 20，`minIntervalMs` 20，`bytesPerSecond` 1e6；交付加跳过等于总量，跳过大于 0，交付小于总量的十分之一，尾巴是后缀且长于窗口 | 新增 |
| `aborts commands cancelled right after they are sent` | 同上：20 次 `sleep 5` 都是 `aborted`，合计不到 10 秒 | 新增 |
| `reports the remote system in Node's names` | `remote-node-platform-names-match-v140`：`windows`/`aarch64` → `win32`/`arm64`，`macos`/`x86_64` → `darwin`/`x64`；活的 Linux 探测在 `remote-env-matches-v140-over-the-lisp-daemon` | 新增 |
| `reports listFiles as not supported by daemons released before it` | 同上：hello 的 `features` 为空时，`listFiles` 是 `not_supported`，消息是 `The pi-env daemon does not list files; update it` | 新增 |
| `cancels a listing in the daemon` | 同上：100 个目录各 100 个文件，请求发出时已经取消则 `code` 与 `message` 都是 `aborted`；随后完整列出 10100 条且不截断，`maxEntries` 5000 截断 | 新增 |
| `times out a command that produces no output` | 同上：`sleep 5` 超时 0.3 秒，`code` 是 `timeout`，墙钟不到 3 秒 | 新增 |
| `fails requests on handles of a lost connection instead of reaching the new daemon` | 同上：`SIGKILL` 后旧句柄是 `unknown`，新句柄读到 `BBB` | 新增 |
| `computes the command at each start and retries a start that failed` | 同上：第一次读是 `unknown`，消息是 `ssh gpu-box failed: Network is unreachable`；随后 `exit 0`，启动次数是 2 | 新增 |
| `writes and reads files larger than one transfer chunk in order` | 同上：3_500_017 字节 `(index * 7919) % 251`，追加后再读；读者从偏移 1000003 读 2000000 字节 | 新增 |

## `packages/env/test/ssh-external.test.ts`

| 上游 | FiveAM | 状态 |
|---|---|---|
| `reaches the remote system through its default shell` | `ssh-deploy-and-remote-env-match-v140` 在本机 sshd 上看到 Linux、`HOME` 和一次成功的 exec | 新增。上游整段 `describe` 由 `PI_ENV_SSH_HOST` 打开，本仓库没有这台预配置主机 |
| `registerEnvConformance`（`RemoteExecutionEnv over SSH`） | 无 | 范围外：要 `PI_ENV_SSH_HOST` 和 durable 的 Node 环境夹具。本行的文件、exec、listFiles 已由上面两张表锁住 |

## `packages/env/test/differential.test.ts`

GAP-42a 把这个文件划到本行。它比较 `RemoteExecutionEnv` 和 `NodeExecutionEnv`，还调用 durable 的 read/bash 工具。这三样都不在本行列出的源文件里。

| 上游 | FiveAM | 状态 |
|---|---|---|
| `gives the same results for random file operation sequences` | 无 | 范围外：60 组随机操作要对着 Node 的本地环境 |
| `reads devices, FIFOs and directories like Node`（非 Windows 才跑） | 无 | 范围外：同上，还要 FIFO 和 `/dev/null` 的 Node 读法 |
| `lists names that are not UTF-8 like Node`（只在 Linux 和 Android 跑） | 无 | 范围外：目录项名字的字节序要对着 Node |
| `gives the same read and bash tool results` | 无 | 范围外：durable 的 read/bash 工具不是本行的源文件 |

## 文档里的行为，测试文件没有单独的 `it`

| 行为 | FiveAM | 状态 |
|---|---|---|
| 主机密钥扫描用 `StrictHostKeyChecking=accept-new`，再 `ssh-keygen -lf` | `ssh-deploy-and-remote-env-match-v140` 的指纹 | 新增 |
| 已知主机文件改写串行且原子，模式 0600 | 并行 accept 只留下一行 | 新增 |
| POSIX 探测 `PI-ENV-PROBE`、`uname`、`HOME` | 部署后的 `home` 等于 sshd `SetEnv` 的目录 | 新增 |
| Windows / Git Bash 改走 PowerShell；`windows-probe`、DefaultShell、PowerShell 上传 | 无 | 范围外：这台机器没有 Windows sshd。`check-daemon` 在平台为 windows 时直接说明只跑 POSIX 路径 |
