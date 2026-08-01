# Goal 10 Part A 阶段报告

> 用户于 2026-08-01 完成人工验收：独立核实 remote、全历史凭据扫描，并从
> GitHub 临时 clone 后从零构建；Part A 正式关闭。

> 状态：私有异地备份已建立，全部本地分支与 tag 已推送；从远程默认分支
> 独立 clone 后完成真实构建。

## 1. 远程与分支

- 仓库：`https://github.com/artwalker/cadr`；GitHub API 返回
  `visibility=PRIVATE`。
- 本地远程名固定为 `backup`；既有 `origin` 未修改，仍为
  `git@github.com:badlogic/pi-mono.git`。
- 远程默认分支为 `cadr-migration`，使普通 clone 直接得到 Cadr 主线，而非
  上游 TypeScript 跟踪树。
- `git push backup --all` 推送三条本地分支：
  `cadr-migration@13a8c9472c7c82b54716a0286492d9a4888c3bd9`、
  `main@0d43c5804b57f5fb19e67f62051103a85d38fb42`、
  `pi-mono-legacy@48b9a05f2cfc3f34f749ac4a2d8d17aec0f843a1`。
- `git push backup --tags` 推送全部 308 个 distinct 本地 tag；远程的 312 条
  tag ref 行还包含四个 annotated-tag dereference，不把它们误计成额外 tag；
  没有创建发布 Release。

远程复核：

```text
13a8c9472c7c82b54716a0286492d9a4888c3bd9 refs/heads/cadr-migration
0d43c5804b57f5fb19e67f62051103a85d38fb42 refs/heads/main
48b9a05f2cfc3f34f749ac4a2d8d17aec0f843a1 refs/heads/pi-mono-legacy
```

## 2. 推送前凭据与产物审计

当前跟踪树与两条必须备份的分支均不包含 `auth.json`、`.env*`、`.tmp-home/`、
`.codex/`、根 `cadr` 或 `cadr-server` 二进制。全历史路径审计没有发现这些本地
状态；全 refs 另按 OpenAI/Anthropic/GitHub/Google/AWS token 与 PEM 格式扫描，
零真实凭据命中。唯一两个高置信材料是 Cadr 的
`test/fixtures/auth/service-account-private-key.pem`（身份固定为
`fixture@example.invalid`）和上游历史的 proxy-agent 测试证书，均为合成测试
fixture，不是可登录或部署的用户凭据。初次宽松 `sk-` 扫描只命中测试名中的
`task-...`/`markdown-...` 子串和上游已删除的网页抓取产物；收紧为 token 边界后
零 token 命中，没有把误报伪装成泄漏或反过来忽略。

`.gitignore` 已在推送前覆盖：

```text
/cadr
/cadr-server
*.core
*.fasl
.cadr/
.env
/.codex
/.tmp-home/
__pycache__/
*.py[cod]
```

因此没有触发“凭据曾进入历史则禁止改写历史”的阻塞条件。

## 3. 独立 clone 与构建

将私有仓库普通 clone 到
`/tmp/cadr-backup-clone.2mZyvH/repository`，自动 checkout
`cadr-migration@13a8c9472`。在 clone 内执行 `./build.sh`，exit `0`：

- 八套确定性测试合计 `7040 checks / 7040 pass / 0 skip / 0 fail`；
- 本机 SBCL 不带 `sb-core-compression`，按既定回退构建无压缩 image；
- 产物 `cadr` 为 66,429,936 bytes、mode `0755`；
- `./cadr --version` 输出 `cadr 0.1.0`。

原始构建日志：`/tmp/cadr-goal10-part-a-clone-build.log`。

## 4. 边界与落账

- 对外动作严格限于用户预授权的私有建仓、分支/tag 推送和默认分支配置；没有
  改为 public、创建 Release 或改写任何历史。
- 新增第三方依赖：`0`。
- Part 耗时约 25 分钟，含历史敏感信息审计、远程传输与独立构建；产品未提供
  可按 Part 审计的 token 数，未伪造估值。
- 本报告与远程配置作为 Part A 独立提交落账；提交后再次推送
  `cadr-migration`。
