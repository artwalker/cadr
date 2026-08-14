# GOAL v4: full alignment audit (parity map)

> Historical report: the `71efc6f0…` in this document records the audit anchor
> as it stood for Goal 4; from Goal 9 onward the current canonical baseline is
> `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.

## 0. Preconditions and positioning

- goal 3 has passed mechanical acceptance; this goal may run in parallel with the wrap-up of the TUI manual acceptance.
- **The north star has been confirmed by the user (2026-07-30): cadr takes the entire content of pi-mono at the audit commit `71efc6f0c1909874ec8c944637a9ae7fc0e2d508` as its complete alignment target** — including every provider, every run mode, `server`, `evals` and `storage`. A missing API credential only lowers the verifiable level of an individual item; it is not a reason to narrow the implementation scope.
- This goal is a **pure audit task**: inventory, classify and record only; implement no feature, fix no bug, change no production code. Every problem found is recorded, without exception, and implementing beyond the boundary is treated as a violation.

## 1. Task

Read the audit commit via `git show`/worktree (**taking the 2026-04 state of the pi-mono-legacy worktree as the audit reference is forbidden** — it contains features that postdate the baseline; using it as a reading convenience is the only thing allowed, with the content of `71efc6f0` authoritative item by item), and produce one complete map `docs/parity-map.md`:

### 1. Feature gap inventory
- Package by package (`ai`, `agent`, `coding-agent`, `tui`, `storage`, `server`, `evals`), enumerate its external behavior surface (provider list, run modes, CLI options, public API, tool set, session/storage format, service endpoints).
- Label each item with a status: `implemented` (linking to the corresponding cadr module and tests) / `missing` / `intentional difference` (linking to an entry of the existing divergence list, such as the all-Lisp extension ecosystem).
- List the providers one by one (about 35), each labeled with: protocol category (openai-completions compatible / standalone protocol), authentication method, implementation difficulty (such as Bedrock SigV4, Vertex GCP authentication, Copilot device flow), and the **attainable verification level** (fixture cross-implementation comparison / live smoke, based on the credentials on hand: DeepSeek key, ChatGPT OAuth, local Ollama).

### 2. Three-way test classification audit
- Enumerate every `*.test.ts` file in the audit commit (including the tests of `evals`, `server` and `storage`), and classify file by file:
  - `covered`: link to the existing CL test name (cross-check with docs/test-matrix.md, and record any error or omission found in the matrix along the way);
  - `applicable but not covered`: belongs to an implemented feature but CL lacks the corresponding test — this is the current outstanding debt, and gets its own table;
  - `corresponds to a missing feature`: folded into the matching entry of the feature gap inventory, to be filled in together with that feature's implementation wave.
- The classification must be exhaustive: every test file in the audit commit appears exactly once in the map, and the totals add up.

### 3. Wave proposal (for user adjudication; do not start work on one's own)
- Propose a batching by dependency relationship and cost-effectiveness (for example: the batch of OpenAI-compatible providers → RPC/JSON modes → standalone-protocol providers → storage/server/evals), with an estimated size and a verification plan per wave. This is a proposal only; the implementation order gets its own goal after the user has settled it.

## 2. Acceptance criteria

1. `docs/parity-map.md` exists, the feature surface is fully covered package by package, and the number of entries in the provider list matches the actual files in the audit commit's `packages/ai/src/providers/`.
2. The total number of enumerated test files matches the `git show` count, and the three-way classification has no omission and no duplicate; the "applicable but not covered" table can serve directly as the work list for filling in tests.
3. The errors and omissions in test-matrix.md (if any) have been recorded (the matrix itself is not modified; the correction follows in a later goal).
4. Throughout, zero tracked files and zero production code are changed; the only content added this time is `docs/parity-map.md` and this report. The full test count is the same as at the goal 3 acceptance (690), all green.
5. The audit report states the exact git commands used, so a spot check is reproducible.

## 3. Principles

- Record only, do not fix; do not reopen entries of the existing divergence list (the all-Lisp extension, the REPL fallback, etc.), only link to them.
- The "attainable verification level" of every provider must be labeled honestly; a fixture cross-implementation comparison must not be claimed as live verification.
- Pause on completion and wait for the user to adjudicate the waves; implementation must not be started on one's own.

## 4. Completion record (2026-07-30)

- Audit baseline: `71efc6f0c1909874ec8c944637a9ae7fc0e2d508`, read through a detached worktree.
- Providers: 82 files at the top level of `packages/ai/src/providers/`; the 38 text providers of `builtinProviders()` have been recorded item by item and mechanically reconciled; 1 image provider and 1 faux provider are recorded in addition.
- Tests: 352 `*.test.ts`, distributed as ai 120, agent 18, coding-agent 187, tui 27, and 0 each for storage/server/evals; the manifest reconciles path by path with no omission and no duplicate.
- Strict whole-file classification: covered 1, applicable but not covered 2, corresponds to a missing feature 349. A file that is partially covered but contains any unimplemented case stays in "corresponds to a missing feature".
- The errors and omissions found in `docs/test-matrix.md` are recorded only in the parity map; the original file was not modified.
- Full Common Lisp regression: cadr-ai 256, cadr-agent 156, cadr-tui 59, cadr-cli 219, 690 checks in total, all passing.
- The delivered changes are only `docs/parity-map.md` and this report; production code, tests and the existing matrix were not modified.
