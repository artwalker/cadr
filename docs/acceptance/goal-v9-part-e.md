# Goal 9 Part E 阶段报告

> 状态：发布前收尾、仓库卫生与最终本地门禁均已完成；未打 tag，等待 Goal 9
> 整体验收。

## 1. 版本单一来源

根 `version.sexp` 保存当前开发版本 `0.1.0`。八个生产 ASDF system 均使用
`(:read-file-form "version.sexp")`；`cadr-ai` 内部 helper 将同一值供给：

- `cadr --version` 与 `cadr-server --version`；
- TUI 启动 banner；
- HTTP User-Agent；
- Radius machine registration。

未新增公开 export。`GOAL9-PART-E-PRODUCTION-VERSION-HAS-ONE-SOURCE` 先在文件
不存在时红 `1/0/0/1`，实现后绿 `28/28/0/0`；
`GOAL9-PART-E-VERSION-REACHES-SERVER-CLI-AND-RADIUS-REGISTRATION` 为
`2/2/0/0`，并检查真实 Radius payload。生产源码/ASD/build/scripts 中的
`0.1.0` 旧字面量 grep 为零命中。

本 goal 保持 `0.1.0` 且不打 tag。建议在 Goal 10 完成稳定上游重锁、移除既定
`PI_CL_*` 兼容窗口并通过发布门禁后使用 `0.2.0`；这正好与现有兼容契约的
移除版本一致。实际版本与 tag 仍由用户决定。

## 2. Changelog、文档与清理

- 新增根 `CHANGELOG.md`，按 Keep a Changelog 的 `Unreleased` 记录 Goal 1–9
  里程碑、关键修复与依赖/OAuth 安全约束。
- 新增 `docs/README.md`，明确 architecture、parity-map、visual-parity、
  test-matrix、dependency-audit、open-questions、progress、proposals、acceptance
  的职责。
- `goal9.md` 与 `goal10.md` 归档为 `docs/progress/goal-v9.md` 与
  `goal-v10.md`。Goal 9 原字节 SHA-256 保持
  `021f269a66c585dce0d0cbdf5815edde9e3032f229f7a8ec90c9cca730739aee`；Goal 10
  仅清除一个空白行的行尾空格以通过仓库 whitespace gate，语义文本不变，归档
  SHA-256 为
  `1dafba73f6461e94a0be2906a19cc444087e07afe13f765f94b3a99d8cba862c`。
- 清理前 `packages/` 下文件与 symlink 清单为空；仅用 `rmdir` 删除七个空目录
  `agent/ai/coding-agent/mom/pods/tui/web-ui` 及空的 `packages/` 根。
- 删除一个可再生 bytecode：
  `scripts/__pycache__/goal9-a2-pty-driver.cpython-312.pyc`，随后删除空 cache
  目录；源码与用户数据均未删除。
- `.gitignore` 新增本地 goal 草稿、`.codex`、Obsidian、`.tmp-home` 与 Python
  bytecode。根 `.obsidian/`、`docs/.obsidian/`、`.tmp-home/` 及 goal 6–8 草稿
  原地保留。

`GOAL9-PART-E-REPOSITORY-HYGIENE-AND-NAVIGATION-CONTRACT` 先红，暴露缺失的
changelog/index/ignore/archive 与残留目录；收敛后为 `35/35/0/0`。

## 3. 完整验证

有凭据执行 `./scripts/verify.sh`，耗时 `3m21s`：

| 阶段 | 结果 |
|---|---|
| deterministic FiveAM | PASS，7019/7019，0 skip，0 fail |
| isolated cadr build | PASS，重复 7019/7019/0/0 |
| isolated cadr-server build | PASS，重复 7019/7019/0/0 |
| 六个 native/process/PTY/socket harness | 全部 PASS；terminal lifecycle 3/3 |
| credential-gated FiveAM | 8 items / 7 run / 7 pass / 1 Anthropic skip / 0 fail；32 checks / 31 pass / 1 skip / 0 fail |
| DeepSeek live TUI | PASS |

随后在根工作树分别运行 `./build.sh` 与 `./build-server.sh`，两者各自重复
`7019/7019/0/0`，并因本机 SBCL 不带 `sb-core-compression` 正常降级为无压缩
image。最终证据：

```text
cadr 0.1.0
cadr-server 0.1.0
cadr        66462712 bytes mode=755
cadr-server 57122504 bytes mode=755
```

原始日志：

- `/tmp/cadr-goal9-part-e-verify.log`
- `/tmp/cadr-goal9-part-e-build.log`
- `/tmp/cadr-goal9-part-e-build-server.log`

新增第三方依赖：`0`。Part 总耗时约 1 小时，含审计、红绿测试、清理与五次
完整确定性门禁；产品未提供可审计的精确 Part token 计数，未伪造估值。
本 Part 独立提交落账。
