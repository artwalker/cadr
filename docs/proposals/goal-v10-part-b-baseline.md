# Goal 10 Part B 基线裁决提案

状态：**用户已裁决：Part B 暂挂等待 `v0.84.0`；先执行零依赖的 Part C。**

## 0. 用户裁决（2026-08-01）

本文保留最初 blocked 时的事实与选项，以下裁决取代第 4、5 节的执行建议：

1. 不锁 `v0.83.0`：它比当前基线倒退 38 commits，不符合追新目标。
2. 不例外锁 `origin/main@4488ad55c`：上游正连续重构会话存储层与 server
   协议，开发中提交不作为新基线。
3. 顺序调整为 `Part C → Part B（等待 v0.84.0）→ Part D → Part E`。
   Part C 只依赖已验收的 Part A 仓库与 Goal 9 Part D `verify.sh`；原有
   “Part B 必须在 Part D 之前”约束保持不变。
4. Part C 完成后若 `v0.84.0` 仍未发布，暂停并报告，不得自行改锁 HEAD。
5. 第 3 节所列最小密码学面已获预授权：bearer-token digest 必须复用
   `src/cadr-ai/oauth.lisp:63` 的纯 Lisp `sha256-bytes`；定长字节比较用不提前
   退出的循环，不引入新算法或依赖。测试须覆盖正确 token、错误 token、不同
   长度、并发 handshake、日志/错误不泄露 token、socket suffix 固定向量。
   若需新密码学依赖或超出提案列出的文件范围，重新 blocked。

## 1. 确切冲突

Goal 10 同时要求：

1. 基线锁执行时最新稳定 release tag，不锁开发分支 tip；
2. 从 Goal 9 基线 `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`
   继续追新；
3. 补齐 client、composable server、fullscreen transcript、scrollbar、UI mode
   等点名增量。

2026-08-01 的权威远程状态使三者无法同时成立。GitHub Latest release 仍是
`v0.83.0`，tag commit 为
`845d6ff1f6643aba440341cce877ce1c43ebbc39`，发布于
`2026-07-29T22:30:33Z`。当前规范基线已在该 tag 之后 38 commits；上游
`origin/main` 为 `4488ad55c18f07ae89a489096c90de8667b3adfb`，又在当前
基线之后 99 commits、在 tag 之后 137 commits。

所以锁 `v0.83.0` 不是“追新”，而是把已验收基线倒退 38 commits；Goal 10
点名能力也不在该 release。goal-v10 第 1.1 节已经预裁：tag 与 HEAD 差距过大且
目标能力只在 HEAD 时必须 blocked，不得自行改锁 HEAD。

权威复核：

```text
GitHub Latest: v0.83.0
tag hash:       845d6ff1f6643aba440341cce877ce1c43ebbc39
current base:   74caa2649f10ed71b4378ce69f5d9fbfd2466ca5
upstream HEAD:  4488ad55c18f07ae89a489096c90de8667b3adfb
v0.83.0..current: 38 commits
current..HEAD:    99 commits
v0.83.0..HEAD:   137 commits
```

GitHub Release：`https://github.com/earendil-works/pi/releases/tag/v0.83.0`。

## 2. HEAD 增量规模与行为面

| 范围 | commits | files | diff |
|---|---:|---:|---:|
| `v0.83.0..74caa2649` | 38 | 122 | `+7042/-1089` |
| `74caa2649..origin/main` | 99 | 200 | `+15724/-2627` |
| `v0.83.0..origin/main` | 137 | 287 | `+22556/-3506` |

测试分母从当前基线 363 个 package `*.test.ts` 增至 HEAD 的 385 个；
`74caa2649..HEAD` 有 51 个受影响测试文件（23 新增、27 修改、1 删除）。新增项
分布为 agent 1、AI 1、client 6、coding-agent 6、server 7、TUI 2。顶层 package
从 8 个增至 9 个，新增 `packages/client`。

经实际 diff 审计，主要行为面为：

- transport-neutral client、Unix socket、请求关联、session lease、背压；
- composable protocol server、token handshake、snapshot/progress、session
  attachment、socket 权限与 stale inode 安全清理；
- protocol v2 字段/判别联合收紧；
- repository/store/search、reader/fork、per-session queue、JSONL/SQLite/FTS5
  会话存储重构；
- fullscreen transcript、嵌套 ScrollView、临时/可拖动 scrollbar、滚轮路由、
  Kitty crop、settings 搜索空格；
- coding-agent UI mode、远程 session controller、auth reload lock、Wayland
  clipboard；
- Fireworks Kimi K3 reasoning、Codex WebSocket 按 account 隔离、Google/
  Anthropic stream 修正。

没有新增外部 direct npm dependency；新增 manifest 边仅为内部 client/protocol，
`brace-expansion` 是已有依赖 patch 升级。`wl-paste` 是可选运行时命令，不构成
新包依赖，但实施时须进入差异/运行环境说明。

## 3. 独立密码学裁决

若用户裁定追 HEAD，仍不能直接施工 composable server：

- `origin/main:packages/server/src/server.ts:34-35` 对 bearer token 做 SHA-256
  digest；
- 同文件 `:257-258` 用 `timingSafeEqual` 比较客户端 token digest；
- `packages/server/src/transports/unix/listener.ts:307-309` 另用 SHA-256 生成
  owned socket path 的 8-hex 后缀。

现有授权覆盖 PKCE、AWS HMAC-SHA256 与 RS256/OpenSSL 路径，不自动授权新的
server bearer-token digest/constant-time compare。按 Goal 10 blocked 类别 `(b)`，
必须单独裁决。最小 Lisp 路径是不加依赖，复用现有 SHA-256 primitive 并新增
固定长度 byte-vector constant-time compare；测试必须锁定正确 token、错误 token、
不同长度输入、并发 handshake、日志/错误不泄露 token，以及 socket suffix 固定
向量。若实现需要扩大到新密码学依赖或其他文件，再次 blocked。

## 4. 路线与取舍

### 路线 1：等待 `v0.84.0`（建议批准）

保持“只锁稳定 release tag”的裁决和 Goal 10 点名范围不变。上游发布后重新查询
GitHub Latest，记录实际 tag/hash，再从 `74caa2649` 做完整增量审计。优点是基线
稳定、可交流且不倒退；代价是 Part B/C/D/E 在 release 出现前不能继续。

密码学仍须在新 release 实际包含 composable server 时逐项批准，不能因等待 release
而自动获得授权。

### 路线 2：本次例外锁 `origin/main@4488ad55c`，并授权最小密码学面

立即获得 Goal 10 点名能力，但明确撤销本 goal 的“只锁发布 tag”规则一次；HEAD
是开发快照，99-commit 移植期间上游仍可能继续变化。若批准，基线固定在上述 commit
hash 而非浮动 `main`，且必须同时明确批准第 3 节 token digest/constant-time compare
与 socket suffix SHA-256；否则仍 blocked。

### 路线 3：锁 `v0.83.0`（否决）

形式上满足“最新稳定 tag”，实质倒退 38 commits，丢失已验收的 11 个测试文件与
Goal 9 增量，也无法实现本 goal 点名能力。它违反“不缩范围”和“追新”目标，不应
选择。

## 5. 请求用户逐项裁决

1. 基线：批准路线 1 等待 `v0.84.0`，还是路线 2 例外锁当前 HEAD？
2. 若批准路线 2：是否批准第 3 节最小密码学实现面？
3. 若选择等待：`v0.84.0` 发布后必须重新解析实际 tag/hash/依赖/密码学 diff，本文
   数字只作本次阻塞证据，不预授权未来 release 的未知变化。

在以上裁决前，Part B 不创建旧 tag checkout、不重写 fixture/parity；因 Part 顺序
固定，Part C 也不得提前实施。
