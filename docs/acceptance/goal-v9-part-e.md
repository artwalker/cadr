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

## 4. 关账独立复核补正

关账时两个独立 `test-cl.sh` 进程并发运行，其中一次在
`ALL-PARALLEL-TOOLS-FINISH-BY-COMPLETION-BUT-RESULTS-STAY-IN-SOURCE-ORDER`
稳定暴露 `623 checks / 622 pass / 0 skip / 1 fail`：测试在 fast executor 内先
释放 slow executor，fast 的 `:tool-execution-end` 尚未发射，负载下 slow 可能抢先
发射 end event。产品并行逻辑没有失败，测试握手却只同步 executor body，没有同步
它实际断言的事件边界。

门禁改为由 agent 的真实 fast `:tool-execution-end` callback 释放 slow executor；
因此 fast event 已被观察后 slow 才能完成，不依赖调度速度或 sleep。修正后：

- 定向 `cadr-agent`：`623/623/0/0`；
- 四个 `cadr-agent` 套件使用独立临时根并发压力复核：四次均 `623/623/0/0`；
- 最终 `test-cl.sh`：`7040/7040/0/0`。

同一关账审计还修正了 parity-map 中两个已改名的 OAuth 测试引用，并将已经发生的
Part B 用户关闭裁决同步到 acceptance、visual-parity 与 README。没有修改生产
代码或引入依赖。

审计随后发现 A2 证据的两个交集缺口：既有 editor/completion/overlay 门禁使用
虚拟输入而非真实 PTY；既有 process modes 与 faux provider 分属两套测试。补正后
`scripts/goal9-a2-pty.sh` 在独立 `openpty` 进程中新增 editor 6 帧、completion
5 帧、settings overlay 5 帧完整快照，连同 lifecycle 汇总为 6/6；三个
`GOAL9-A2-PROCESS-FAUX-*` 门禁在独立 SBCL 子进程中锁定 actual faux 的 text、
JSONL 精确事件序列与 RPC 往返，共 21/21。两项均为测试/证据修正，生产源码 diff
为零，最终套件增至 `7040/7040/0/0`。

提交测试补正后重新执行完整 `./scripts/verify.sh`，最终 exit `0`：根确定性门禁、
隔离 `cadr` build、隔离 `cadr-server` build 三次均为 `7040/7040/0/0`；六个保留
native/process/PTY/socket/TUI harness 全绿，其中 A2 PTY 为 6/6；live 为
`8 items / 7 run / 7 pass / 1 Anthropic skip / 0 fail`、`32 checks / 31 pass /
1 skip / 0 fail`，DeepSeek live TUI 亦通过。原始日志：
`/tmp/cadr-goal9-closeout-verify.log`。
