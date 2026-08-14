# Glossary

This project's documentation was originally written in Chinese and is being
translated to English (user adjudication, 2026-08-14). This table fixes one
English term per concept so that a term does not acquire three renderings
across the tree. **Translate against this table; extend it rather than
improvising a synonym.**

Terms are listed in the order a new reader meets them.

## Governance

| 中文 | English | Notes |
|---|---|---|
| 常设开发政策 | standing development policy | The cross-goal constraints in `docs/development-policy.md`. "Standing" = survives any goal closeout. |
| 裁定 / 裁决 | adjudication (noun), adjudicate (verb) | A binding decision. **"User adjudication" always means the human decided**, never the agent. |
| 交裁决 | escalate for adjudication | Not "ask" — the work stops until the decision lands. |
| 关账 | close out (verb), closeout (noun) | Finishing a goal and freezing its evidence. |
| 欠账 | outstanding debt | Known-but-unpaid work. Not "technical debt" — this project means it literally. |
| 提案 | proposal | A written document under `docs/proposals/`, adjudicated before it takes effect. |
| 立项理由 | grounds for undertaking | Why a change may be started at all. |

## Verification

| 中文 | English | Notes |
|---|---|---|
| 门禁 | gate | An automated check that blocks. Reserve this word for machinery. |
| 闸门 | admission test | **Distinct from 门禁.** The set of legitimate reasons that admit a change. Human-facing, not machinery. |
| 差分 | differential | The byte-level comparison harness (`render-diff`, `event-diff`, `tool-result-diff`). |
| 对拍 | cross-implementation comparison | Running pi and cadr on the same input and comparing. "Differential comparison" where the pairing is the point. |
| 配对 | paired | Two measurements of the same operation, one per implementation, same host, back to back. |
| 不可配对 | unpairable | No same-path implementation exists on the pi side. |
| 账本 | ledger | The five books: behavior / source / non-functional / presentation / organization. |
| 处置 | disposition | A recorded human judgement that admits a difference. |
| 判定 | verdict | A ledger cell's conclusion (`已实现` / `有意差异` / `缺失`). **Vocabulary itself stays Chinese for now** — see the state board. |
| 义务单位 | obligation unit | What a coverage figure counts. Changing it changes what the gate promises. |
| 分母 | denominator | What a gate declares itself to be checking. |
| 判据 | criterion (pl. criteria) | The rule a gate applies. Changing criteria requires adjudication. |
| 人工判断出口 | human-judgement exit | Any mechanism where recording a reason lets a difference through. |
| 样板 | boilerplate | A reason text reused instead of judged per row. |
| 广度告警 | breadth warning | Disclosing what fraction of exits a single class covers. |
| 越层吸收 | cross-layer absorption | A byte-level class admitting a visible-text difference. |
| 驱动完整度 | drive completeness | How much of the baseline the scenario set exercises. |
| 一致性 | conformance | Whether cadr matches. **Never conflate with drive completeness.** |
| 取证 | capture evidence | Runtime forensics with `trace` / slynk, as opposed to guessing. |
| 反证 / gate-validity proof | gate-validity proof | Showing the gate goes red without the fix. |

## Porting

| 中文 | English | Notes |
|---|---|---|
| 基线 | baseline | The pinned upstream commit. Never "the original". |
| 对齐 | alignment | Observable-behavior equivalence with the baseline. |
| 全量对齐、不做阉割 | full parity, no crippling | The project's founding constraint. Keep "crippling" — it is deliberate. |
| 分岔 | divergence | Structural difference from the baseline. Not a defect by itself. |
| 转写 | transcription | Rendering pi's structure in Lisp syntax. The thing this project rejects. |
| 直译 | literal translation | Same idea, at statement level. |
| Lisp 本位 | Lisp-native | Using Lisp's actual advantages, not Lisp syntax. |
| 苟且 | expedient | Taking the cheap path. Carries disapproval; keep that force. |
| 等强度行为断言 | equal-strength behavioral assertion | An assertion as strong as the structure it replaces. |
| 锁死 | lock (to the baseline) | Assertions derived from the baseline, never from the current implementation. |
| 反推 | reverse-engineer (from) | Deriving an assertion from the implementation it is supposed to check. Always pejorative here. |
| 定点修正 | point fix | A change whose edits can be enumerated one by one. |
| 成规模重写 | at-scale rewrite | Structural reorganisation of a whole module. |
| 硬条件 | hard condition | A precondition that cannot be waived. |
| 举证 | discharge the evidence burden | The changer proves it, not the gate. |
| 夹带 | smuggling in | Mixing unrelated style rewrites into a functional change. |
| 运动式重写 | campaign rewrite | A sweeping tree-wide rewrite. Rejected. |

## Engineering

| 中文 | English | Notes |
|---|---|---|
| 原语 | primitive | A reusable building block, e.g. the failure-safety primitives in `cadr-core`. |
| 归属 | ownership | Which file new code belongs in. |
| 重复决策 | repeated decision | The same judgement re-made by hand in N places. |
| 手工不变量 | hand-maintained invariant | An invariant a human must remember, rather than one the machine enforces. |
| 失败安全 | failure-safety | Atomic replacement, durability, crash safety. |
| 凭据纪律 | credential discipline | Keys and tokens never reach transcripts, logs, or session files. |
| 脱敏 | redact | Replace secret material with `[REDACTED]`. |
| 剖面 | profile | `sb-sprof` output. A diagnostic, never a criterion. |
| 热路径 | hot path | Where type declarations are allowed, with before/after numbers. |
| 冷启动 | cold start | New process to first real TUI frame. |
| 回归门禁 | regression gate | Compares against this machine's own history, not just an absolute ceiling. |
| 天花板 | ceiling | An absolute upper bound. Catches disasters, not drift. |
| 带宽 | band | The tolerance a drift check allows. |

## Register

- **Imperatives keep their force.** 须／必须 → "must"; 不得／禁止 → "must not";
  可 → "may"; 应 → "should" only where the Chinese is genuinely advisory.
- **Rules that record a past accident keep the accident.** The policy's authority
  comes from "this already happened to us", so never compress an incident into
  a general warning.
- **Do not soften.** 一律不予采纳 → "is not accepted, without exception", not
  "is generally discouraged".
