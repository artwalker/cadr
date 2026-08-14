# Goal 9 Part A / A2 stage report

> Status: the Part A / A2 implementation, ledger and permanent gates are complete. This document records the mechanical evidence in the committed state; the Codex OAuth live request is separately constrained by the account quota, and neither a weak assertion nor a fixture is used to masquerade as a real pass.

## 1. Baseline, audit window and work tree

- Canonical baseline: `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`, with audit checkout `/tmp/cadr-parity-74caa2649`.
- Historical anchor: `71efc6f0c1909874ec8c944637a9ae7fc0e2d508`, with the historical checkout kept at `/tmp/cadr-parity-71efc6f0`; it is no longer the basis for parity verdicts.
- Cadr implementation tree: `/root/projects/cadr`, branch `cadr-migration`.
- Canonical diff: 119 files, `+7030/-1089`; the net result at the endpoint deletes no entire existing package, and the new package is `packages/protocol`.

Re-check commands:

```bash
git -C /tmp/cadr-parity-74caa2649 rev-parse HEAD
git -C /tmp/cadr-parity-71efc6f0 rev-parse HEAD
git -C /tmp/cadr-parity-74caa2649 \
  diff --stat \
  71efc6f0c1909874ec8c944637a9ae7fc0e2d508..74caa2649f10ed71b4378ce69f5d9fbfd2466ca5
git -C /tmp/cadr-parity-74caa2649 \
  diff --name-status \
  71efc6f0c1909874ec8c944637a9ae7fc0e2d508..74caa2649f10ed71b4378ce69f5d9fbfd2466ca5
```

The "38 commits" the goal text speaks of is a closed-interval count that includes the historical anchor itself:

```bash
git -C /tmp/cadr-parity-74caa2649 \
  rev-list --count 71efc6f0c1909874ec8c944637a9ae7fc0e2d508^..74caa2649f10ed71b4378ce69f5d9fbfd2466ca5
# 38

git -C /tmp/cadr-parity-74caa2649 \
  rev-list --count 71efc6f0c1909874ec8c944637a9ae7fc0e2d508..74caa2649f10ed71b4378ce69f5d9fbfd2466ca5
# 37
```

The real increment is therefore 37 commits; below, the 38 objects of the closed interval are listed, where number 00 is the historical anchor and only 01–37 are the new baseline's increment.

## 2. The full behavior surface of the 38 commits

### 2.1 Historical anchor

| # | commit | Behavior surface and audit conclusion |
|---:|---|---|
| 00 | `71efc6f0c` | Historical anchor, `Add [Unreleased] section for next cycle`; used only to delimit the old endpoint, not counted in the 37 increments. |

### 2.2 Comparative eval (15 incremental objects)

| # | commit | Behavior surface and affected paths |
|---:|---|---|
| 01 | `32f3a9728` | Adds the comparative Pi eval harness, artifact, harness table, reporter, summary and four test files; mainly under `packages/evals/`, and adjusts the extension loader. |
| 02 | `af00848d6` | Artifacts are explicitly bound to a task; touches the eval extension, Pi harness, smoke and reporter. |
| 03 | `2eed6d219` | Deletes the `artifact-names` module from the intermediate evolution and takes naming responsibility back into artifact/reporter; that redundant module does not exist at the endpoint. |
| 04 | `eb08aa8fa` | Attachment types are specialized, strengthening the artifact input contract. |
| 05 | `3631e82d0` | Source artifacts are generalized and no longer bound to a single source type. |
| 06 | `2a2e677be` | Source artifacts move to a language-neutral representation; this is a semantic the Lisp port must preserve. |
| 07 | `56e6a8a3f` | Records an eval session after each test, and adds a setup lifecycle hook. |
| 08 | `6a3eae8e4` | Normalizes eval input before hashing, which affects the grouping stability of the harness table. |
| 09 | `d9ae6e2b0` | Simplifies the internal structure of comparative, but preserves the external artifact/table/summary semantics. |
| 12 | `29f97c20f` | Simplifies the harness table tests; production behavior is unchanged. |
| 13 | `ac033d186` | Aligns the comparison report output and the summary assertions. |
| 15 | `fce7445b1` | The comparison direction becomes explicitly declared, avoiding a candidate/baseline inversion. |
| 16 | `ca11823f7` | Converges the comparative ergonomics; affects the declaration and summary entry points. |
| 17 | `743e1595c` | Deletes the custom shuffle; comparison order returns to fixed, reproducible semantics. |
| 18 | `7659e1c98` | The evals-baseline merge commit; no independent endpoint file increment, the confluence point of the eval evolution above. |

The corresponding Cadr implementation has landed in `src/cadr-evals/{harness,artifacts,harness-table,summary}.lisp` and in the tests of the same names; for the commits see §8.

### 2.3 Repository management metadata (2 incremental objects)

| # | commit | Behavior surface and audit conclusion |
|---:|---|---|
| 10 | `fe1f7230f` | Only `.github/APPROVED_CONTRIBUTORS`; no runtime behavior, so the Lisp migration repository need not port it. |
| 14 | `6bcc29a06` | Same as above; contributor gate data only. |

### 2.4 AI provider and model metadata (4 incremental objects)

| # | commit | Behavior surface and affected paths |
|---:|---|---|
| 11 | `05558a792` | The display name of `opencode-go` is corrected from `OpenCode Zen Go` to `OpenCode Go`. |
| 25 | `b889a0ce3` | GPT-5.6 pricing update, sourced from `packages/ai/scripts/generate-models.ts`. |
| 33 | `2c3041242` | The OpenAI Completions stream allows there to be no finish reason; the types, four existing stream tests and the documentation are synced. |
| 35 | `70bbe47a9` | Bedrock HTTP and in-stream errors retain structured metadata; the new test is `packages/ai/test/bedrock-error-metadata.test.ts`. |

The corresponding Cadr behavior lives in `src/cadr-ai/{http,models,provider,registry,types}.lisp`, `src/cadr-ai/providers/openai-completions.lisp` and the Bedrock error gate.

### 2.5 Coding-agent core / extensions (4 incremental objects)

| # | commit | Behavior surface and affected paths |
|---:|---|---|
| 19 | `bb226f9c1` | Deletes the redundant `setToolsExpanded` state write, avoiding a duplicate update. |
| 32 | `393c34422` | The SDK examples switch from the deprecated `getModel` to the new model entry point; examples / API usage surface. |
| 36 | `714978bf5` | Markdown API rework: extensions register a markdown transformer; user/assistant/thinking/streaming rendering is passed the message type and the available width; the transform chain, error isolation and cache semantics are synced. |
| 37 | `74caa2649` | Field-by-field type validation of the `pi` manifest; invalid fields are discarded and valid fields kept, so a malformed manifest does not drag down package discovery. |

The corresponding Cadr gates include `test/cadr-agent/extensions-wave3-test.lisp`, `test/cadr-cli/extensions-test.lisp`, `test/cadr-cli/tui-test.lisp`, `test/cadr-tui/components-test.lisp` and `GOAL9-MALFORMED-PACKAGE-MANIFEST-IGNORES-INVALID-FIELDS-WITHOUT-DROPPING-VALID-FIELDS`.

### 2.6 Agent harness (6 incremental objects)

| # | commit | Behavior surface and affected paths |
|---:|---|---|
| 20 | `96eda8b47` | `packages/agent/docs/harness-v2.md` fills in the agent-loop building blocks; documentation contract. |
| 22 | `82c485983` | Harness shutdown becomes a permanent, idempotent lifecycle; after shutdown, prompt/nextTurn/append/compact are all rejected. |
| 23 | `7d86e6233` | The shutdown feature merge commit; no independent endpoint file increment. |
| 26 | `bc031ae45` | Shutdown waits for mutations that have already started, leaving no background write behind. |
| 28 | `871a99047` | Asynchronous work such as prompt and mutation all enters task tracking. |
| 29 | `9cde1725d` | `waitForIdle` keeps its original semantics and is not rewritten by shutdown/task tracking. |

The corresponding Cadr implementation is in `src/cadr-agent/{runtime,loop,compaction,conditions}.lisp`; `test/cadr-agent/shutdown-test.lisp` covers waiting on active tasks, permanent shutdown, rejection of append/compact after shutdown, and byte-invariance of an idle session.

### 2.7 TUI (2 incremental objects)

| # | commit | Behavior surface and affected paths |
|---:|---|---|
| 21 | `c13ffe187` | Adds the alternate-screen renderer, the main-screen split, viewport/scroll, mouse selection, OSC 8/52, Kitty crop, iTerm stale cleanup, and restoring the complete document on exit; wired together with the coding-agent's `--alt` and `interactive-tui.test.ts`. |
| 34 | `dfe47d3fb` | Grapheme width is aligned with terminal cells, with the emphasis on CJK, emoji, combining marks, regional flags and truncation boundaries (#6987). |

Cadr's structural gates are in `test/cadr-tui/{alt-screen,unicode,terminal-image,components,component-parity}-test.lisp`; for the real PTY lifecycle see §6.

### 2.8 Remote protocol (4 incremental objects)

| # | commit | Behavior surface and affected paths |
|---:|---|---|
| 24 | `56eb685b6` | Adds `packages/protocol`: CBOR, 4-byte framing, codec, v2 schemas, client/server messages and 3 test files. |
| 27 | `bd2cfabc5` | CBOR rejects cyclic values and the source is reorganized into `src/cbor/`; strict map key, depth, length and JSON value boundaries. |
| 30 | `b2a1a0655` | The protocol changelog, and convergence of the CBOR public files; documentation/release surface. |
| 31 | `c066d01a4` | The protocol package merge commit; no independent endpoint file increment. |

Cadr uses a pure Lisp implementation and introduced no third-party dependency because of this; the corresponding system is `cadr-protocol.asd` and the gates are `test/cadr-protocol/{cbor,framing,protocol}-test.lisp`.

## 3. Package and test-file counts

The counting basis counts only the Git-tracked `packages/<name>/test/**/*.test.ts` in the canonical baseline:

```bash
git -C /tmp/cadr-parity-74caa2649 ls-tree -r --name-only 74caa2649 -- packages \
  | awk '/\/test\/.*\.test\.ts$/ {n++} END {print n+0}'
```

| package | old baseline tests | new baseline tests | increment | tracked files in the new baseline package |
|---|---:|---:|---:|---:|
| `packages/ai` | 120 | 121 | +1 | 310 |
| `packages/agent` | 18 | 18 | 0 | 71 |
| `packages/coding-agent` | 187 | 189 | +2 | 590 |
| `packages/tui` | 27 | 28 | +1 | 75 |
| `packages/evals` | 0 | 4 | +4 | 19 |
| `packages/protocol` | 0 | 3 | +3 | 17 |
| `packages/storage` | 0 | 0 | 0 | 18 |
| `packages/server` | 0 | 0 | 0 | 17 |
| **Total** | **352** | **363** | **+11** | **1117** |

The current Cadr tree has 99 `*test.lisp` files: AI 22, agent 18, CLI 26, evals 6, protocol 3, server 1, storage 1, TUI 22. That number is not the parity denominator; the parity denominator is always the baseline's 363 TS test files.

Rebuilding the ledger against the new baseline for the first time gave `347 C / 9 U / 6 M / 1 N/A = 363`. After the implementation, the commits and the re-verification of the affected existing `C` entries, the final ledger is
`362 C / 0 U / 0 M / 1 N/A = 363`; the only `N/A` is still strictly confined to the whole file
`packages/coding-agent/test/config.test.ts`.

## 4. Item-by-item status of the 11 new test files

`git diff --diff-filter=A --name-only 71efc6f0..74caa2649 -- packages | awk '/\/test\/.*\.test\.ts$/'` yields the following 11 items.

| # | new baseline test file | corresponding Cadr gate | current status |
|---:|---|---|---|
| 1 | `packages/ai/test/bedrock-error-metadata.test.ts` | `test/cadr-ai/bedrock-error-metadata-test.lisp`, 9 cases of Bedrock HTTP and in-stream error metadata | implemented, committed and re-verified |
| 2 | `packages/coding-agent/test/interactive-tui.test.ts` | the `--alt`/factory gates in `test/cadr-tui/alt-screen-test.lisp` and `test/cadr-cli/part-b-cli-test.lisp` | implemented, committed and re-verified |
| 3 | `packages/coding-agent/test/suite/regressions/7187-malformed-package-manifest.test.ts` | `GOAL9-MALFORMED-PACKAGE-MANIFEST-IGNORES-INVALID-FIELDS-WITHOUT-DROPPING-VALID-FIELDS` | implemented, committed and re-verified |
| 4 | `packages/evals/test/pi-harness.test.ts` | `test/cadr-evals/pi-harness-test.lisp` | implemented and committed; the deterministic eval suite passes |
| 5 | `packages/evals/test/vitest-evals/artifacts.test.ts` | `test/cadr-evals/artifacts-test.lisp` | implemented and committed; the deterministic eval suite passes |
| 6 | `packages/evals/test/vitest-evals/harness-table.test.ts` | `test/cadr-evals/harness-table-test.lisp` | implemented and committed; the deterministic eval suite passes |
| 7 | `packages/evals/test/vitest-evals/summary.test.ts` | `test/cadr-evals/summary-test.lisp` | implemented and committed; the deterministic eval suite passes |
| 8 | `packages/protocol/test/cbor/cbor.test.ts` | `test/cadr-protocol/cbor-test.lisp` | implemented and committed; protocol 41 tests / 497 checks fully green |
| 9 | `packages/protocol/test/framing.test.ts` | `test/cadr-protocol/framing-test.lisp` | implemented and committed; protocol 41 tests / 497 checks fully green |
| 10 | `packages/protocol/test/protocol.test.ts` | `test/cadr-protocol/protocol-test.lisp` | implemented and committed; protocol 41 tests / 497 checks fully green |
| 11 | `packages/tui/test/tui-alt-screen.test.ts` | the 10 viewport/input/image/link/selection/restore cases in `test/cadr-tui/alt-screen-test.lisp` | implemented, committed and re-verified; TUI suite 691/691 |

The conditions for recording `C` are: the implementation is committed, the whole affected suite is green, and parity-map has been reclassified against the new baseline. All 11 items in the table above satisfy the three conditions; "a test file exists" was not used in place of behavioral-equivalence evidence.

## 5. Payload fixture regeneration evidence

Regenerated using the canonical checkout's public payload hook:

```bash
/tmp/cadr-parity-74caa2649/node_modules/.bin/tsx \
  scripts/export-ts-payloads.ts \
  --reference /tmp/cadr-parity-74caa2649 \
  --output /tmp/cadr-fixtures-74caa2649
```

The exporter produces 24 request JSONs and writes the 25th item, the Wave 1 catalog, to the `catalogs/` sibling of the output directory. The 24 request payloads are byte-for-byte identical to the repository's current fixtures:

| request fixture | SHA-256 shared by the new baseline output and the repository | `cmp` |
|---|---|---|
| `ant-ling-default.json` | `22c6a61e29248b1e9612835f84f08c3b0c3ddc910afaab65fa6ae4baa3c948ab` | identical |
| `anthropic-adaptive-long-cache.json` | `acc4ee7758511bcd4f7edd05d77d84aad8516f8d8a765e79bd8d7251832a6546` | identical |
| `anthropic-complete.json` | `3b42fae877ed63ebd93832dfb9ac151daa1a7b5ea2b8a6897978da80b651afa8` | identical |
| `anthropic-stream.json` | `fe7a12b58ff250efd6a9b96c93f9d59e5135109f7860c118d79d3a4530052414` | identical |
| `anthropic-thinking-disabled.json` | `da9249390658ec09c53aa3202642d0935af9e4c531f19494d146be7ec38310ef` | identical |
| `cerebras-default.json` | `b1c2d0a5db73a9d44a642d7648b7ecdb3f0c6f0c162f4ce7ca4813cdbced6499` | identical |
| `google-complete.json` | `a0bbe63bba6d88cda63b52766f404b54b6a9e08c0356a85c7e57f3817d2ad513` | identical |
| `google-stream.json` | `a0bbe63bba6d88cda63b52766f404b54b6a9e08c0356a85c7e57f3817d2ad513` | identical |
| `google-thinking-disabled.json` | `42aa3f265a15c77f77b3eaff36e7fc540b8c89a1718cf73babd94ca7b02f90a6` | identical |
| `google-thinking-high.json` | `9885c922d7f509b2eee720d514c7e2868055023509cb685ea02a7629e0d80b8e` | identical |
| `groq-default.json` | `4c4f1a6fde5b34a2c699f212c6db8d8a58c61d48bdad762f3d4436c2d262cde7` | identical |
| `huggingface-default.json` | `be3229bb1bddde361a7db4560dfc17c01afb51b2d119d751a4d2911e9f6d780f` | identical |
| `minimax-cn-default.json` | `7cd7b3527247160db6f7611b2b8cb1f7e4aafc9f6d6a47bcb68764d70b8ae4bd` | identical |
| `minimax-default.json` | `7cd7b3527247160db6f7611b2b8cb1f7e4aafc9f6d6a47bcb68764d70b8ae4bd` | identical |
| `moonshotai-cn-default.json` | `762fbecb1549d81bc26c6c857192bdf7b135882623fb7531d6b3302c30038cdb` | identical |
| `moonshotai-default.json` | `762fbecb1549d81bc26c6c857192bdf7b135882623fb7531d6b3302c30038cdb` | identical |
| `openai-complete.json` | `d543870278d29833c4507829d96b5ca3bbb199ff39cb839526df87e8f278c272` | identical |
| `openai-completions-qwen-reasoning.json` | `bfb3e1ebd14499e47f6142302cb6d234d4d19d20bbb50c5cf64316d296a0dcff` | identical |
| `openai-responses-reasoning-cache.json` | `c8127b30cbeeaf8aea9ae4638de905e5198c4f061dc7a5ca3afe47b142e22f17` | identical |
| `openai-stream.json` | `c01ae21090c411c76440b44b3f44c371a741ee7b8bad87a22d4bb45033b019a0` | identical |
| `qwen-token-plan-cn-default.json` | `d1b65609c307a6e79475b50491ac6d5dd37d2d14e973655e2db88b65c6b791d5` | identical |
| `qwen-token-plan-default.json` | `d1b65609c307a6e79475b50491ac6d5dd37d2d14e973655e2db88b65c6b791d5` | identical |
| `together-default.json` | `49842b21c51c0849a1818623cf32bc8da8a83705baad978dd8f31da82537053d` | identical |
| `xiaomi-default.json` | `98c6dc1afd37b940e004d75652682807e8c1821a7087351467f2b70dafee24ba` | identical |

Item-by-item re-check command:

```bash
find /tmp/cadr-fixtures-74caa2649 -maxdepth 1 -type f -name '*.json' -print0 \
  | sort -z \
  | while IFS= read -r -d '' fixture; do
      name=${fixture##*/}
      sha256sum "$fixture" "test/fixtures/requests/$name"
      cmp "$fixture" "test/fixtures/requests/$name"
    done
```

The 25th item, `wave1-provider-models.json`, is **not** byte-identical; live catalog drift must not be passed off as complete sameness:

| artifact | SHA-256 | providers / models | difference |
|---|---|---:|---|
| repository `test/fixtures/catalogs/wave1-provider-models.json` | `3e1f8e1ee9831ac61a4809d14a61006d48c4c47d3b010d2c1f72cd34c7a543bc` | 12 / 143 | pinned audit fixture |
| new baseline live generator output `/tmp/catalogs/wave1-provider-models.json` | `49ff4ac4e05f2cd2b1b7ac5f326d170a92bf766cf388a7a58e5d698e04de43b9` | 12 / 145 | HuggingFace 51 → 53, total 143 → 145 |

This is drift in the external catalog data the exporter reads at runtime, not a change of payload encoding behavior within `71efc6f0..74caa2649`. The 24 actual wire requests are still byte-for-byte identical, so the existing request fixtures and the Lisp provider construction are unaffected; the pinned Wave 1 catalog is not silently refreshed because of one live fetch.

Separately, reading the static catalog with the pinned `@earendil-works/pi-ai@0.83.0` artifact — the same version as the baseline's — gives 37 providers / 1153 models; the live generator directory from the same run, `/tmp/cadr-model-catalog.HW3Yur.json/models.json`, gives 37 / 1154. Re-check commands:

```bash
node --input-type=module -e '
  import("file:///tmp/cadr-pi-ai-0.83.0.FdAaCT/package/dist/models.generated.js")
    .then(({MODELS}) => console.log(
      Object.keys(MODELS).length,
      Object.values(MODELS).reduce((n, value) => n + Object.keys(value).length, 0)))'

python3 -c '
import json
data=json.load(open("/tmp/cadr-model-catalog.HW3Yur.json/models.json"))
print(len(data), sum(len(value) for value in data.values()))'
```

## 6. Part A2's eight permanent automated gates

| Goal 8 manual item | permanent gate name / entry point | coverage evidence | current result |
|---|---|---|---|
| Sessions | `GOAL9-A2-SESSION-WORKFLOWS-ARE-DETERMINISTIC-AND-BRANCHES-STAY-ISOLATED` | faux provider; new/name/switch/branch/compact/export/continue/resume; two branches A and B with no crosstalk in either direction | fully green together with the workflow group at 3 tests / 67 checks |
| Modes | `GOAL9-A2-PRINT-JSON-AND-RPC-MODES-COVER-THE-REAL-CONTRACT` + the three `GOAL9-A2-PROCESS-FAUX-*` gates | the in-process semantic layer plus the intersection of a separate SBCL process × the actual faux provider; real argv/parser, stdout/stderr/exit, JSONL with exactly 12 events and `text_start/delta/end`, RPC double response/event/EOF round trip | workflow group 67 checks + process-faux 21/21, fully green |
| Extensions | `GOAL9-A2-EXTENSION-WORKFLOW-COVERS-LEGACY-UI-RENDERERS-AND-STALE-RELOAD` | real discovery/load from source files; command/tool/hook/custom UI/message+tool renderer; the old generation is stale after `/reload`; the old API source is not modified | fully green together with the workflow group at 3 tests / 67 checks |
| Startup and exit | `normal`, `ctrl-c` and `suspend-resume` from `scripts/goal9-a2-pty.sh` | a real PTY; raw/ICANON/ECHO, cursor, bracketed paste; restore before SIGTSTP, re-enter after SIGCONT, final restore; strict checking of sequence counts and order | 6/6 in total together with the interactive scenarios below; permanently invoked by `scripts/verify.sh` |
| Input editing | `GOAL9-A2-INPUT-EDITOR-PTY-EVENTS-AND-VIRTUAL-SCREEN-COVER-FULL-CONTRACT` + PTY `input-editor` | the semantic layer covers multiline/CJK/emoji/wide-character wrapping, word-wise movement, history, kill/yank/yank-pop, undo; after real `openpty` input, the same production `render-frame` path writes to the PTY and to a virtual terminal respectively, with 6 frames snapshotted cell by cell | interactive group 86 checks + PTY 6 snapshots, fully green |
| Completion | `GOAL9-A2-COMPLETION-PTY-EVENTS-SNAPSHOT-SELECTION-CANCEL-AND-UNDO` + PTY `completion` | the semantic layer covers slash/path/`@`, selection/cancel/apply/undo; a real PTY pins path and slash selection, undo, cancel and 5 frame snapshots | interactive group 86 checks + PTY 5 snapshots, fully green |
| Overlay | `GOAL9-A2-OVERLAY-SELECTORS-FOCUS-CJK-AND-RESIZE-SNAPSHOTS` + PTY `overlay` | the semantic layer covers the six selector kinds, dual-overlay focus, CJK borders and resize; a real PTY pins the settings first/last wraparound, search, backspace, cancel and 5 frame snapshots | interactive group 86 checks + PTY 5 snapshots, fully green |
| Rendering (structure) | `GOAL9-A2-FAUX-STREAM-RENDERING-STRUCTURE-AND-STATUS-SNAPSHOTS` | faux stream; thinking/text/tool deltas; Markdown headings/lists/tables/code/links; tool expand and collapse; token/cache/cost/session status bar | fully green together with the interactive group at 4 tests / 86 checks |

The behavior tests above do not call a real LLM. The interactive layer uses a layered intersection: FiveAM pins every semantic branch, a real `openpty` pins raw process-terminal → input decoder/selector → production `render-frame`, and the same path writes the virtual-terminal snapshots; the mode layer, in turn, uses the actual faux provider directly in a separate SBCL process. Purely perceptual judgement is still the responsibility of Part B's A/B alone.

PTY gate output format:

```text
normal: PASS stty-restored echo-restored cursor-cycles=1 bracketed-paste-cycles=1
ctrl-c: PASS stty-restored echo-restored cursor-cycles=1 bracketed-paste-cycles=1
suspend-resume: PASS stty-restored echo-restored cursor-cycles=2 bracketed-paste-cycles=2
input-editor: PASS real-pty raw-input snapshots=6 terminal-restored
completion: PASS real-pty raw-input snapshots=5 terminal-restored
overlay: PASS real-pty raw-input snapshots=5 terminal-restored
goal9 A2 PTY deterministic gates: 6/6 passed
```

## 7. The precise semantics of `--fork`

The argument to the command-line `--fork` is a **source session locator**, not an entry ID:

1. When it contains `/` or `\`, or ends with `.jsonl`, it is resolved as a session file path; a relative path is relative to the current working directory.
2. Otherwise it is matched within the current project's session set, first by full ID and then by ID prefix.
3. When the current project has no match, it is then matched within the global session set, first by full ID and then by ID prefix.
4. Once found, a new session is created with `parentSession` pointing at the source session, and the source conversation is copied.
5. An entry ID is not valid; forking at a user-message entry must use the selector of the interactive `/fork` command.

Implementation evidence: `SESSION-ARGUMENT-PATH-P`, `FIND-SESSION-BY-ID-OR-PREFIX`, `RESOLVE-FORK-SOURCE-SESSION` and `RESOLVE-CLI-SESSION` in `src/cadr-cli/main.lisp`. Regression gate: `FORK-ACCEPTS-SESSION-ID-PREFIX-AND-PREFERS-CURRENT-PROJECT`. The README states the boundaries above explicitly in the Usage section.

The baseline evidence is `resolveSessionPath` in `/tmp/cadr-parity-74caa2649/packages/coding-agent/src/main.ts`: path first, then local exact/prefix, then global exact/prefix. The advisor once passed an entry ID to `--fork` and got `Session not found`; that is a misuse of the argument type, not an implementation failure after entry IDs were allowed.

## 8. Implementation commits already recorded

The following commits have already entered `cadr-migration`; uncommitted work is not listed as complete:

| commit | content |
|---|---|
| `7d52f919aec631627b9b1cfc4d3d1ccaa6610e55` | core implementation of remote session protocol v2 |
| `0f47f41438f698ab74c595a2f7752f31c7161e71` | provider stream metadata, no finish reason, GPT-5.6 pricing and the OpenCode Go naming |
| `995196c1bb60e3ab0f27e4c193b0588ce625c19b` | permanent harness shutdown lifecycle and task tracking |
| `bb925fdb117beaf43f584c44c06004b3488b932c` | grapheme / terminal cell width alignment |
| `e13b3458631b5c2a84bf5c5a00c93e6fa33f65e9` | Bedrock structured error metadata |
| `90a66b797e1f24214b1dc602bde99d4ee24df652` | complete semantic gates for the protocol's three baseline test files |
| `f902d97f17e581d90a81c9f07dc7dad1e40b0c04` | gates for rejecting append/compact after shutdown and for idle-session invariance |
| `ec8962c659573624d2a7acdbc4a6a40cdce9d341` | comparative eval harness, artifact/table/summary and four test files |
| `032269bd9fc758dbe12a093ab30359baa8135b5b` | Markdown transformer extension API |
| `709907adbdf60e773ffdade40f9c69e936eb0060` | Markdown transform/parse/cache semantics at the actual component width |
| `eeef16dba710713850b4c80c69a23f91a5cac6f0` | field tolerance for malformed package manifests |
| `51ca77ce0b4c33b336f862d98c178a654c7c8f8b` | alternate-screen, main-screen scrollback, terminal input and image cropping semantics |
| `511a62323000918f475623bcf18713cea9ae9a88` | `--alt`, `--fork` and interactive CLI semantics |
| `bfde1c70118bb10c6331d48e051e7e6cbe6da463` | Part A2 faux / snapshot / real-PTY permanent gates |
| `c6b3a4c18a3c0ed6a17d3185469fcb9916d9563e` | the terminal image fallback test is decoupled from the caller's HOME |

## 9. Test evidence and external live status

Independent evidence in the committed state:

- `cadr-protocol/tests`: 41 tests / 497 checks, fully green.
- Part A2 workflow targeted group: 3 tests / 67 checks, fully green.
- Part A2 interactive targeted group: 4 tests / 86 checks, fully green.
- Part A2 PTY deterministic gates: 3 lifecycle + editor/completion/overlay, 6/6 fully green.
- `cadr-tui/tests`: 691/691, fully green; also re-run with an isolated HOME, likewise 691/691.
- The full `./scripts/test-cl.sh` with an isolated HOME: 4009 checks, 4006 pass, 3
  Codex OAuth credential-gated skips, 0 fail. By suite: AI 732, agent 621, TUI 691,
  CLI 1269, storage 23, server 43, evals 133, protocol 497.
- Of these, `cadr-cli/tests` is 1269 checks, 1268 pass, 1 skip, 0 fail;
  `cadr-evals/tests` is 133 checks, 132 pass, 1 skip, 0 fail. The DeepSeek live
  block specifies provider/model explicitly inside the test and really runs; the
  isolated HOME removes only the coupling to the user's settings, sessions, extensions and OAuth auth store.

The real credential status must be recorded separately from the deterministic gates:

- The DeepSeek key is available; the current eval/live blocks really run and are fully green.
- The Codex OAuth credential can be read and a real request has been issued, but the account returns `The usage limit has been reached.` The live-inclusive eval run has 133 checks in total, and the Codex OAuth functional assertions therefore fail; the CLI live block under the real HOME likewise has 3 failing assertions because of that upstream quota state. It must not be changed into a fixture or a weak assertion to fake a pass.
- There is no credential for AWS or any other provider; the corresponding live blocks are skipped per the baseline credential gating, and Bedrock's current verification level is deterministic fixture.

Part A / A2 closeout facts:

1. All current canonical baseline references are unified to `74caa2649…`; the old `71efc6f0…` is kept only as the historical-anchor note.
2. The 363-item manifest in `docs/parity-map.md` is exactly equal to the new baseline's set of test paths; the 11 new files and the 26 affected existing `C` entries have been re-verified.
3. Implementation and tests were both committed in logical groups; this report and the ledger document are recorded by the Part A documentation commit.
4. The eight A2 behaviors have been converted into faux / snapshot / real-PTY permanent gates; Part B retains only the perceptual A/B that cannot be judged mechanically.
5. The remaining modifications in the working tree are only the user's existing evidence in the Goal 8 acceptance document and the user-provided `goal9.md`; the generated `scripts/__pycache__/` is listed separately because the current execution environment refuses to clean it, and it is neither a product artifact nor commit content.

```text
parity-map: 362 C / 0 U / 0 M / 1 N/A = 363
full isolated-HOME suite: 4009 checks / 4006 pass / 3 OAuth skips / 0 fail
credential-gated live: DeepSeek pass / Codex OAuth usage-limit
A2 PTY: 6/6 pass
Part A/A2 implementation commits: 15
```

## 10. Goal 9 closeout truthfulness correction

The independent closeout audit found two places where the original report claimed more than the facts: the existing tests for editing/completion/overlay hand bytes straight to the decoder and are not a real PTY; the mode tests proved the process boundary and the faux semantics separately, but did not prove the intersection of the two. The old lifecycle had only 3/3, and when a new driver expectation was added before the harness had been extended it was stably red with `timed out waiting for GOAL9_A2_INPUT_EDITOR_READY`, proving that the gap really existed.

The correction commit `a2298ac4d` adds three separate real-PTY interactive scenarios, plus the three actual-faux text/JSON/RPC gates in a separate SBCL child process. The PTY gate was a fixed `6/6` four times in a row; process-faux is `21/21`; the final deterministic suite is `7040 checks / 7040 pass / 0 skip / 0 fail`. No production code was modified, no test-only provider was registered, no network was called and no dependency was added.
