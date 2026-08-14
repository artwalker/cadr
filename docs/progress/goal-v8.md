# GOAL v8: endgame roadmap progress

> Historical report: the `71efc6f0…` in this document records the audit anchor
> as it stood for Goal 8; from Goal 9 onward the current canonical baseline is
> `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.

Pinned baseline:

- Audit commit: `71efc6f0c1909874ec8c944637a9ae7fc0e2d508`
- Audit checkout: `/tmp/cadr-parity-71efc6f0`
- Goal 8 start-of-work commit: `664e6b80ae1dc0d67711dc83e92e5e39f7518174`
- Start-of-work ledger: `104 C / 0 U / 248 M`

> Evidence correction (2026-07-31): the old `live-*-smoke.sh` command output
> retained later in this document only records the execution history at that
> time and is no longer current acceptance evidence.
> `live-openai-oauth-smoke.sh` and `live-evals-smoke.sh` once used `jq` to
> rename the `openai` credential to `openai-codex`; their OAuth "pass"
> conclusion has been withdrawn. The current evidence is governed by the
> correction record at the end of this document and by
> [`goal-v8-smoke-audit.md`](../acceptance/goal-v8-smoke-audit.md).

## Part A: Wave 3 provider and the complete AI surface

Status: complete and committed.

### Recorded commits

1. `28ddcf68e97ab553b1184434f51e4a82e7d886f2` — tests and pinned
   fixtures first;
2. `c8b418aa65f223490f0313532807ec7b6b2028b6` — standalone protocols,
   authentication, the complete catalog, model/image/faux runtime and shared
   utilities;
3. `e1cce7056e3aefb1602fe19f25642c45c1d353c1` — the CLI resolves OAuth under
   the baseline `openai-codex` identity, RPC provider construction is synced to
   the new signature, and the live smoke uses an isolated credential copy.

### Implementation evidence

- 38/38 baseline text provider IDs; the non-baseline built-in `ollama` was
  removed;
- the npm package `@earendil-works/pi-ai@0.83.0` is pinned, tarball SHA-256
  `f983c28a21209305ed9c274977e29130fa4d8848df6cdf37e9094d95cc7bc6d4`;
- 37 static provider JSONs, 1153 models; manifest SHA-256
  `68fddb01b38c7abc7c579103da455475593fd788b3dbbf79c04b95bb5a4bb3a7`,
  structure hash
  `5d82f5b1946bdf6d01733aa2a4e4410849c6d44a2ad3038171078c17aed367ce`;
- the pinned OpenRouter image catalog has 40 models, fixture SHA-256
  `7a783225dfa4faea2fa53175b5df4af704630b9d54b50b5bcf5560e62d1726bb`;
- Azure Responses, Bedrock Converse EventStream/SigV4, Vertex
  ADC/service-account RS256, Mistral Conversations, OpenAI Codex Responses
  and `pi-messages` each have separate request/response/error/auth tests;
- the model runtime covers provider mutation, credential priority/refresh,
  availability/filter/dispatch; there are also faux provider, complete image
  generation, and context/overflow/retry/schema/UUID behavior;
- SSE requests continue to explicitly disable the read timeout, gated by
  `SSE-REQUEST-EXPLICITLY-DISABLES-READ-TIMEOUT`.

### Live gating equivalence and reclassification

Per user adjudication, offline deterministic behavior is still held strictly
file by file; the baseline's live blocks are gated isomorphically by credential
availability. Actually run on this machine and passed:

```text
./scripts/live-deepseek-smoke.sh
live smoke: DeepSeek Chat Completions streaming passed

./scripts/live-openai-oauth-smoke.sh
OAuth live smoke: OpenAI Codex Responses streaming passed
```

No other provider credential is available, so the related live blocks are
skipped per the baseline gating; Ollama, LM Studio and llama.cpp, which are not
deployed locally, are skipped in the same way, and fixtures do not masquerade as
live.

That adjudication lets the following files containing live-gated blocks move
from `M` to `C` once their offline behavior is complete:

`abort.test.ts`, `anthropic-eager-tool-input-e2e.test.ts`,
`anthropic-long-cache-retention-e2e.test.ts`,
`anthropic-opus-4-8-smoke.test.ts`, `anthropic-thinking-disable.test.ts`,
`anthropic-tool-name-normalization.test.ts`, `bedrock-thinking-payload.test.ts`,
`cache-retention.test.ts`, `context-overflow.test.ts`,
`cross-provider-handoff.test.ts`, `empty.test.ts`,
`google-thinking-disable.test.ts`, `image-tool-result.test.ts`,
`images.test.ts`, `interleaved-thinking.test.ts`,
`openai-codex-cache-affinity-e2e.test.ts`,
`openai-responses-cache-affinity-e2e.test.ts`,
`openai-responses-reasoning-replay-e2e.test.ts`,
`openai-responses-tool-result-images.test.ts`,
`openrouter-cache-write-repro.test.ts`, `responseid.test.ts`,
`stream.test.ts`, `tokens.test.ts`, `tool-call-id-normalization.test.ts`,
`tool-call-without-result.test.ts`, `total-tokens.test.ts`,
`unicode-surrogate.test.ts`, `xhigh.test.ts`,
`xiaomi-token-plan-ams-anthropic-empty-signature-smoke.test.ts`,
`zen.test.ts`.

The verification level is still labeled separately: only DeepSeek and Codex
OAuth are `live-proven`; the rest are `fixture`. After Part A, AI is
`120 C / 0 U / 0 M` and the whole repository is `224 C / 0 U / 128 M`.

### Mechanical verification

```text
./scripts/test-cl.sh
cadr-ai     641/641
cadr-agent  488/488
cadr-tui    582/582
cadr-cli    277/277
total       1988/1988

./build.sh
cadr build: SBCL lacks sb-core-compression; building an uncompressed image.

./cadr --version
cadr 0.1.0
```

Build artifact: `cadr`, 61,710,696 bytes, mode `0755`.

### Freeze and dependency cross-check

Part A unfroze only `src/cadr-ai`, `test/cadr-ai`, `cadr-ai.asd` and the
required CLI provider glue points. The frozen paths for TUI, extension, agent
tool and CLI tool have item-by-item identical object IDs relative to the
start-of-work commit; `git diff 664e6b80...HEAD -- <frozen-path>` is empty.
No new third-party dependency was added: HMAC-SHA256 is a pre-adjudicated pure
Lisp implementation, and RS256 uses the existing `cl+ssl`/OpenSSL exception.

Goal meter closing snapshot: `1,526,490` tokens, `4,609` seconds (cumulative).

## Part B: the complete coding-agent behavior surface

Status: complete and committed. The user has approved item by item the four
adjudications in
[`docs/proposals/goal-v8-part-b.md`](../proposals/goal-v8-part-b.md); the
implementation followed the order of §5 of the proposal strictly.

### Pre-authorized commits

1. `724494fd562d34097c225072ace81771311c58f4` — pin the Part B tests and
   fixtures; the commit message notes pre-adjudicated item 0.5(3);
2. `36310bfb040674ef43dff421e4e537eb7471ebaa` — agent/session/resource/
   tool/input runtime; the six lifecycle events and the provider request hook
   are limited to pre-adjudicated item 0.5(3);
3. `267b215aa45e488053dd85330d8a9c1106553369` — CLI service primitives;
4. `81b441aec12669ef368670f494a1b28697bb8193` — CLI-owned interactive
   controllers; `src/cadr-tui` production code was not modified;
5. `d0a90f9e009aadcca4f3fb482596c21e4314308b` — REPL/RPC/TUI glue and
   startup lifecycle wiring.

### Approved-item commits

1. `1b0350d37` — register `cl-jpeg`, `png-read` and their transitive closure up
   front, classified as pure Lisp replaceable dependencies;
2. `68b07c010` — real pixel decoding for JPEG/PNG, EXIF orientation, Lanczos3
   scaling and encoded-size downgrade;
3. `602e03902`, `0f7836754` — additive extension API, load-scope handle,
   renderer/flag/shortcut, inline factory and CLI-owned UI bridge;
4. `158bc3128` — the minimal runtime contract for `cadr-ai` native providers;
   only `models-runtime.lisp`, `package.lisp` and the corresponding tests were
   modified; `cadr-ai.asd` needed no change;
5. `cbd50a040`, `ee981f6a8` — `define-native-provider`, the llama.cpp bundled
   extension, Hugging Face GGUF queries and `/models/sse` with no read timeout;
6. `config.test.ts` is recorded as `N/A` for the whole file per user
   adjudication; the boundary does not expand to `version-check.test.ts` or to
   resource-bundle updates.

### Extension re-freeze

Recomputed with the same sampling command as Goal 7:

```text
sed -n '/#:define-tool/,/#:make-extension-hook-result/p' \
  src/cadr-agent/package.lisp | sha256sum
e0bcbf8c5f170efb99579fe6065579a8c2e93c7f1bd590b7502b08180ba54046  -
```

Re-frozen object IDs:

```text
e94a3f1c1c80ffb784a94e8bbef9c8645e8504da  cadr-ai.asd
7d657fa28a05a98b7ea673ac73ff26e0bff5d923  cadr-agent.asd
aebccdb3796edc419d916403b2af3c52e378b3db  cadr-cli.asd
77a0a261ee2ab365875924878d803f10be72bb9f  src/cadr-ai/models-runtime.lisp
a9cdcddc18d4acacc28bf7e04814d4f61fe6f002  src/cadr-ai/package.lisp
f9779b379a9374f39f4647a89a07181fc4206feb  test/cadr-ai/models-runtime-test.lisp
54366ea418de090192b9320469caae497d255b01  src/cadr-agent/extensions.lisp
bd78aa73d5f75fc8a21366fc747188c1ee35023c  src/cadr-agent/package.lisp
12f9de30da61bceec9a51e186e577d64b12367d6  src/cadr-agent/loop.lisp
08beda50203d7af790d1690a06090ca7df82da23  src/cadr-agent/tool.lisp
c097b312567386421da5cdae0f1c13d039b21bde  test/cadr-agent/extensions-test.lisp
cf16c937b667eb2252a45ec93585edc8d0a4d60a  test/cadr-agent/extensions-wave2-test.lisp
5cb7dbafbffb7b82c408312b13795c3116f2da63  test/cadr-agent/extensions-wave3-test.lisp
9e598d9aad1f93ee1b17d7bff8fae36a91c2b4f9  src/cadr-cli/extensions.lisp
b4e190b5b24e6479570829767f8c6df7360d5449  src/cadr-cli/resource-loader.lisp
1c76c8990bd3e34a934bf8d966001441561d0f0a  src/cadr-cli/interactive-services.lisp
656dc50d5e3616d54bbcb150ddfedabe4b2a785b  src/cadr-cli/tui.lisp
ecfd5a50a395628bc5e424aedb72d087c14fb137  src/cadr-cli/main.lisp
a2a35209e968becd791c9ce336bf47328aba5ec5  src/cadr-cli/modes/rpc/mode.lisp
ab8de4c1a4a5434dce31c0392fd51ae67ea61872  src/cadr-cli/model-services.lisp
cdc2cfbb966620d7b6f0a8c90e7ea37d5fb05c40  test/cadr-cli/extensions-test.lisp
762385be59337bbf131e23f07062645edbd12633  test/cadr-cli/part-b-interactive-test.lisp
8f13570644842cc8780ce0c3cc955589a339ccda  test/cadr-cli/llama-extension-test.lisp
7ac5d70c2c12af9ef4a3c748c24e7d24474cb959  src/cadr-cli/extensions/llama/client.lisp
3bfbdf66495fd864119a76eb9cba0db2f2e63c4a  src/cadr-cli/extensions/llama/huggingface.lisp
d845e5e14fd9c9b864e65297e58728ae1f1e7c2f  src/cadr-cli/extensions/llama/provider.lisp
5838bab8cf028e1632897989c92365521fe97087  src/cadr-cli/extensions/llama/extension.lisp
```

The three Goal 7 fixture SHAs are unchanged:

```text
e2548662d773edfa21ecfa3b126b2209404a2b27385e6cd48e1f145a41747442  test/fixtures/extensions/legacy-wave2-api.lisp
6dc3a25271080a59c3380704044c435a0a20a972c5ba19f32cae2acee2649b10  test/fixtures/rpc-process-client.py
c1148870a539dd4a24001da74d17f668b6092bf55d41d845319d5439e3df9486  test/fixtures/extensions/rpc-ui.lisp
```

`LEGACY-EXTENSION-SOURCE-REMAINS-COMPATIBLE-AFTER-WAVE-2-API-EXPANSION`
remains fully green; run against the Goal 8 start-of-work commit,
`git diff 664e6b80...HEAD -- src/cadr-tui` is empty, and the TUI production
freeze red line was not touched. The expanded surface above is restored to
"stable on release" from now on.

### Full gate run and ledger

```text
./scripts/test-cl.sh
cadr-ai      668/668
cadr-agent   588/588
cadr-tui     593/593
cadr-cli    1056/1056
total       2905/2905
```

Part B reclassified the coding-agent's 128 `M` entries at start of work into
127 `C` and one user-adjudicated `N/A`; the file-by-file change list is exactly
all the `CL-PART-B` rows in the parity-map manifest plus the `config.test.ts`
row. Closing ledger:
`351 C / 0 U / 0 M / 1 N/A`.

## Wave 5: storage, server and evals

Status: complete and committed. This wave only filled in the three standalone
packages that already exist in the pinned baseline; it did not modify the
already re-frozen extension/TUI surface, and it did not introduce a third-party
dependency.

### Recorded commits

1. `d7b81ce16`, `098362696` — tests first; establish a standalone
   `cadr-storage` facade reusing the single SQLite repository/storage
   implementation;
2. `ee9a18640`, `c2f463ffb` — tests first; implement the Unix-socket JSONL
   supervisor, RPC child, persistence, Radius credential gate and UI/event
   bridge;
3. `11d9f9685`, `a99048395` — tests first; implement the isolated eval harness,
   smoke and self-extension suites;
4. `c11278b07` — native server build, real socket smoke, the baseline's spawn
   flags, process-exit/accept-loop fixes, and Radius backoff / re-registration
   after three consecutive 404s;
5. `370aeafce` — eval CLI runner and DeepSeek/Codex OAuth live gate;
6. `088f3c639` — bring the three packages into the full test entry point;
7. `7be14f292` — explicitly declare the SBCL process contrib the server uses;
   no new third-party dependency.

### Gate evidence

```text
./scripts/test-cl.sh
cadr-ai       668/668
cadr-agent    588/588
cadr-tui      593/593
cadr-cli     1056/1056
cadr-storage   23/23
cadr-server    43/43
cadr-evals     16/16
total        2987/2987

./scripts/server-smoke.sh
server smoke: spawn/list/status/RPC/stop over Unix socket passed

./scripts/live-evals-smoke.sh
live evals: DeepSeek and OpenAI Codex smoke suites passed
```

Both `build.sh` and `build-server.sh` explicitly downgrade to an uncompressed
image when the current SBCL lacks `sb-core-compression`; the artifacts are
`cadr` and `cadr-server` respectively, and `--version` shows the new cadr
naming for both. The final artifacts are:

```text
cadr         65,381,272 bytes  mode 0755
cadr-server  57,220,848 bytes  mode 0755
```

### Freeze and ledger

Relative to the Goal 8 start-of-work commit,
`git diff 664e6b80...HEAD -- src/cadr-tui` is still empty; Part B's extension
export SHA is still
`e0bcbf8c5f170efb99579fe6065579a8c2e93c7f1bd590b7502b08180ba54046`.
Wave 5 does not change the `*.test.ts` classification, so the endgame ledger
stays `351 C / 0 U / 0 M / 1 N/A`; the 82 new assertions cover the
storage/server/evals package surface that has no `*.test.ts` in the baseline.

## Part F: endgame mechanical wrap-up

Status: the old mechanical evidence was rejected because of the OAuth bypass;
after the 2026-07-31 evidence correction it must be accepted again. The user
must still complete the manual acceptance item by item per
[`docs/acceptance/goal-v8-final.md`](../acceptance/goal-v8-final.md);
entry into maintenance mode has not been declared.

### Wrap-up commits

1. `33575aa3e` — correct the end-to-end smoke's stale assumptions about the new
   `agent_settled` and about deferred session persistence;
2. `3e78b1962` — the TUI live smoke uses a unique slash-command prefix and no
   longer depends on a command ordering that changes once commands are added;
3. `03383d127` — final ledger, dependency audit, frozen object IDs, README
   verification levels, and the endgame acceptance package.

### Mechanical conclusions

- endgame ledger: `351 C / 0 U / 0 M / 1 N/A`;
- full suite: `2987/2987`;
- `build.sh` and `build-server.sh` both downgraded to uncompressed successfully
  and produced the new naming;
- the acceptance, process modes, migration, server and TUI deterministic
  smokes are all green;
- DeepSeek's old live records were re-verified by credential-gated FiveAM;
  Codex OAuth's old stream/eval records were withdrawn because they rewrote the
  credential identity; the default route is verified deterministically with a
  temporary directory and a network stub, and live only verifies the credential
  explicitly;
- Anthropic has no credential and is skipped per the baseline credential gate;
- the dependency audit found no new third-party dependency;
- the final code, ASDF/build and extension SHAs have been written into §24 of
  architecture.

Goal 8's endgame grand acceptance still takes the user's manual checklist as the
last gate; declaring completion on one's own is invalid.

## 2026-07-31 evidence-truthfulness correction

This round is not patching the old smokes; it converges the verification
mechanism:

- the exchange, refresh, storage and read of `/login openai` are unified onto
  the baseline `openai-codex` identity; the default model selection after login
  overrides an existing route that has no credential or belongs to another
  provider;
- the OAuth URL uses the baseline OSC 8 raw link and click hint in the TUI, and
  no longer goes through the `session>` notice;
- seven provider/CLI/eval shell live scripts were deleted, and their coverage
  moved into ASDF/FiveAM credential gating;
- only process-level harnesses of the kind that use a real binary,
  PTY/termios, Unix sockets, migration, and signal/RPC EOF are kept; the
  per-script conclusions are in
  [`goal-v8-smoke-audit.md`](../acceptance/goal-v8-smoke-audit.md);
- the OpenAI login/default-route regression uses a temporary auth/config and a
  network stub; the live gate is enabled only by credential availability,
  specifies provider/model explicitly inside the test, and does not read the
  user's settings. To isolate other personal state, the CLI only copies the auth
  file byte for byte; it does not rename or normalize it.

### Correction commits and final mechanical results

1. `cd5f7ba16dc30fa0bc5c1d7e7723a9f0553bd764` — unify the OpenAI Codex
   login/storage/read identity, the default model selection and the URL
   display, landing the regression first;
2. `42ef9d74dff0aac7b1c52ed7402e8206e103fb66` — delete the seven live shell
   scripts that can be built in, merging their coverage into three ASDF/FiveAM
   credential gates;
3. `03aca58dc0c17c227436cc0e3373c01da30f0312` — the repo live gate forces a
   real code 1 to be observed first, with the test fixture left unchanged,
   before the post-fix code 0 is accepted;
4. `a85b0ad321969b5fcfbda58d279d9b9c3a96209e` — the process smoke synchronizes
   SIGTERM on a server-side request marker and no longer relies on a fixed 50ms
   guess;
5. `c73f27dffce029cefd29393015b0fc212ed47eca` — split the OAuth regression into
   a deterministic layer using a temporary directory / network stub and a live
   layer with explicit provider/model, and isolate every CLI/eval live read of
   the user's settings, sessions and extensions.

Final mechanical evidence:

- full ASDF gate: `3043 checks / 3042 pass / 1 skip / 0 fail`; the only skip
  is the absent Anthropic key; the DeepSeek and Codex OAuth live blocks both
  really ran;
- `build.sh` and `build-server.sh` both downgraded successfully on an SBCL
  without `sb-core-compression`, producing `cadr` at 65,348,488 bytes and
  `cadr-server` at 57,155,288 bytes, mode 0755, and `--version` for both is
  `0.1.0` under the new name;
- all six retained scripts were re-run and passed: acceptance, process modes,
  migration, server, Goal 5 PTY and live DeepSeek TUI;
- the product-level manual evidence still holds: after a real TUI
  `/login openai`, conversing directly in the same process without
  provider/model arguments, settings persisted as `openai-codex/gpt-5.5` and
  the assistant replied exactly
  `OAUTH_TUI_DIRECT_OK`; the automatic live gate no longer reads or asserts on
  those settings;
- the official full run used the user's current `openai-codex/gpt-5.6-luna`
  settings, unchanged before and after the run;
- the extension export SHA is still
  `e0bcbf8c5f170efb99579fe6065579a8c2e93c7f1bd590b7502b08180ba54046`,
  and the `src/cadr-tui` production diff relative to the Goal 8 start-of-work
  commit is still empty.

The earlier `2987/2987` and the old script results are retained only as a
historical record; they cannot substitute for the correction evidence above.
