# Goal 18 Part L：38 条 "new-server alignment" PENDING ADJUDICATION 一次性裁决提案（待裁决）

状态：**待用户裁决。** re-anchor 至 v0.84.1 后，
`docs/source-parity.md` 工作区出现 38 行 `有意差异` 与
`PENDING ADJUDICATION` 并存（HEAD 51aed63d1 中为 0，均为本次升级新增），
git 历史与既有提案中无对应裁决记录（I7 提案的 9 项既有挂起不含本组；
goal18-l-runbook 前置裁决三项亦不含）。按"每行有裁决"的账本口径，
本提案请用户一次性裁决这 38 行。

## 分组与范围

五组共 38 行，全部属于 pi v0.84.1 的 **client/server 架构重写 +
experimental CLI 脚手架**，cadr 侧均登记为 `有意差异`：

| # | 组 | 行数 | source-parity.md 行 | 基线文件 |
|---|---|---|---|---|
| 1 | experimental CLI scaffolding | 8 | 459–466 | `packages/coding-agent/src/cli/experimental/{auth,cli,command-options,command,commands/client,commands/pi,commands/server,transport-address}.ts` |
| 2 | coding-agent client 面 | 3 | 473–475 | `packages/coding-agent/src/client/{index,remote-session,transcript}.ts` |
| 3 | server harness / management HTTP | 2 | 615, 636 | `packages/coding-agent/src/server/create-harness.ts`、`packages/coding-agent/src/utils/management-http.ts` |
| 4 | packages/server v0.84.1 rewrite | 15 | 773–788（775 行为 `已实现` 的 barrel 除外） | `connection,errors,listener,protocol,server,sessions,snapshots`、`testing/{client,index,server,service}`、`transports/unix/{index,listener,preset,types}.ts` |
| 5 | packages/client v0.84.1 rewrite | 10 | 850–859 | `{client,connection,errors,index,promise,session-handle,state,transport,types,unix}.ts` |

## 证据

- 全部 38 行的判定列均为 `有意差异`，映射列为
  `no cadr experimental CLI` / `no cadr remote-session client` /
  `src/cadr-server/* (v0.83 architecture port)`，即 **cadr 维持 v0.83
  session-server 架构，未移植 v0.84.1 的 client/server 重写**。
- 验收标准 12 只要求"248 个改动文件已按第 1a 节分流"与四本账闭合，
  未要求移植 client/server 重写；该重写是架构决策，非 Part L 的默认义务。
- 既有裁决先例：goal 18 I7 提案的 9 项既有挂起（--resume、npm 源、
  update --models、telemetry、-r 无参选择器、sentinel、--slynk/--no-tui
  移除、废弃 URL、keybindings.json）已随 `USER-2026-08-10-001` 落账，
  不覆盖本组；本组是新 re-anchor 暴露的类别，须单独裁决。

## 请求裁决

- 路线 A（推荐）：**维持 cadr 现有 v0.83 server 架构与无 experimental
  CLI 的现状**，38 行全部记为 `有意差异`；证据列删除
  `PENDING ADJUDICATION` 字样，改写为"用户 2026-08-12 裁决：
  v0.84.1 client/server 重写与 experimental CLI 属架构级新增，cadr
  维持 v0.83 server 架构；基线能力面差异已登记（new-server alignment
  item）"，并保留基线 file:line 与映射说明。
- 路线 B：部分或全部转入未实现/缺口清单并分期移植（需另行提案评估
  v0.84.1 server 协议重写的工程量与验收面，本 goal 不默认承担）。

裁决后按既有流程落账：改 `docs/source-parity.md` 证据列、重跑
`check-source-parity-drift.sh --ledger-only`（670 条、SHA-256 必须不变
或随账本同步）、在 open-questions 登记本裁决，随后继续收尾批次。

