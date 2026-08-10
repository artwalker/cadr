# Goal 18 Part L 执行手册（裁决到齐后的有序步骤）

前置裁决（全部获批前不动手）：

1. `docs/proposals/goal18-i7-tail-exemptions.md` 的 10 分支豁免 + 新
   `unreachable-in-harness` kind。
2. `docs/proposals/goal18-l1a-mermaid.md` 的路线选择。
3. 9 项既有挂起 + I05 退出残影类（`docs/goal18-l5-attribution.md` 末节）。

## 步骤

1. **豁免入册**：按裁决把 10 分支写入
   `test/fixtures/render-diff/visible-string-exemptions.json`（含分配的
   `userDecisionId`）；A/B 类 9 条若获批需先把新 kind 加进
   `scripts/render-diff.py` 的 `load_visible_string_exemptions` 枚举。
   全量门禁此时必须在 74caa2649 下转绿——这是升级前的基线绿点。

2. **锚点重写**：`scripts/set-baseline.sh 53fa77ccd8a279eb87e92294ef3687b03ff80112`
   （已预演）。随后 `python3 scripts/baseline-anchor.py check` 必须绿。

3. **模型数据钉**：`scripts/render-diff.py` 的
   `PI_AI_MODEL_DATA_PACKAGE`/`PI_AI_MODEL_DATA_SHA256` 手工更新到
   v0.84.1 对应制品（`npm pack` 新包取 SHA-256）。

4. **冻结新基线检出**：删除 `/tmp/cadr-render-diff-pi-74caa2649` 缓存目录，
   让 `ensure_baseline` 按新锚点重建（I5 的内容校验随 marker 换新）。
   **G5 工具链切换在这一步同做**（WSL 侧 node/npm，见 goal18.md Part G5；
   切换后必须重建缓存，两事同一时间点最干净）。

5. **文件分流**：`./scripts/check-source-parity-drift.sh --from 74caa2649...
   --to 53fa77ccd... ` 列出新增/删除/重命名，逐个给出处置结论；
   248 个改动文件按 `docs/source-parity.md` §1a 规则路由。
   `enumerate-baseline-diff.py` 的 17 类差集逐项处置（结果已录于
   `docs/source-parity-upgrade.md`）。

6. **新能力落地**（枚举差集驱动，全部配测试/场景）：LaTeX 渲染、
   半页滚动与 prompt 历史 6 键位动作、`--tui-mode`、3 个新设置项、
   baseten/qwen-token-plan-individual 两 provider、`AGENTS.override.md`、
   AI_AGENT/STY/ZELLIJ 环境变量、`scrollbarThumb` 主题 token、
   `AuthCommandError` 改名跟进、`terminate`/`isSubscription`/
   `trackEventBusSubscription` 扩展字段。Mermaid 按裁决路线执行。

7. **四本账重闭合**：源码账 670 行全处置（缺失 0）；行为/呈现/非功能账
   数字由 I4 机器对账核验。

8. **L4 不留死角核验**：I2 派生差集为空或全有裁决；I7.3 反向扫描在
   v0.84.1 上重跑（`mermaid.ts` 等新组件可能引入新 sink）；J 的引用完整性
   覆盖新文档面。

9. **L5 核验**：L5.1 归因表重跑确认每条仍由门禁先抓；I05 按裁决落地后
   L5.2 探针补丁重新应用（工作记录在本文件与 L5.1 文档）。

10. **L6 组织复盘**：248 改动文件按 §1a 路由的命中率、人工判断量、热点
    文件表现，写入 `docs/code-organization.md`（允许"不如预期"）。

11. **收尾**：全量门禁 + `test-cl.sh` + `verify.sh` +
    `verify-release.sh` 全绿；G4（`.tmp/` 清理 + gitignore）；二进制新鲜度；
    版本串四处一致（L3：--version/README/CHANGELOG/Release 由 BASELINE
    派生即为证）。
