# Goal 26 queue coverage audit

Auditor did not write `docs/acceptance/goal26-pi-140-alignment.md`.
Measurement date 2026-10-23. Range `71023aec1546d6d677a65669c5665c0927ce0dd0`
(v1.3.0) to `4a080252f06caf63a525d7873c5d94d3c23887e0` (v1.4.0), read with
`git -C /root/projects/cadr`. `/root/projects/pi-mono` was not checked out
and not modified.

Scope is the method section of the alignment doc. User-visible behavior in
`packages/coding-agent`, `packages/tui`, and `packages/ai`. Do not chase
`main`. Codemode execution, worker admission, and `PI_CODEMODE_MAX_WORKERS`
stay out. Files outside the three packages stay out.

Command, 50 commits:

```sh
git log --no-merges --format='%H %s' \
  71023aec1546d6d677a65669c5665c0927ce0dd0..4a080252f06caf63a525d7873c5d94d3c23887e0 \
  -- packages/coding-agent packages/tui packages/ai
```

The same range has 81 non-merge commits. The other 31 do not touch the
three packages. They are Durable, Chord, env tests, and a publish-time
catalog check. Out of scope. They are not rows below.

Changelogs read at `4a080252` from `packages/ai/CHANGELOG.md`,
`packages/tui/CHANGELOG.md`, and `packages/coding-agent/CHANGELOG.md`,
section `## [1.4.0]`.

A queue row that says done or N/A counts as covered. A commit is a gap
when some user-visible, in-scope effect has no row. Counts: covered 37,
out of scope 9, gaps 4.

## Commit table

| Commit | Title | Class | Row or reason |
|---|---|---|---|
| `4a080252f06c` | Release v1.4.0 | out of scope | Release. Version bumps in package.json, changelogs, and example lockfiles. No behavior. |
| `18e56a069a88` | fix(ai): expect compat on OpenRouter decision models in catalog test | out of scope | Test only. One line in `packages/ai/test/image-model-data.test.ts`. The compat behavior is `7f225f25d8a9`, classifier row. |
| `f76b248caeca` | docs(ai,tui,coding-agent): audit changelogs since v1.3.0 | out of scope | Docs. Moves the Vertex retry note and the NVIDIA default note into the 1.4.0 section. Those behaviors are `0fbdbd3f8ab1` and `95364a54efb8`. |
| `7f225f25d8a9` | feat(ai,coding-agent): image input for System One classifiers | covered | Classifier row. Clef and Jev prices, Clef Omni, Jev 1.14, `imageInput`, and models.json compat overlay. The same row already excludes codemode `models.classify()`. |
| `02726086d11c` | fix(coding-agent): recovery omits tool results with the truncated tool call | covered | Output-limit row. `#11227`. |
| `8c4e873899b9` | fix(coding-agent): grep tool ignores ripgrep config via --no-config | covered | grep row. `#11203`. `src/cadr-cli/tools/grep.lisp` passes `--no-config`. |
| `bd3c9b823762` | fix(coding-agent): activate extension tools registered after the branch recorded its loadout | covered | Session-restore row. `#11062` `#11075`. |
| `04a93bad8f15` | fix(ai,agent,coding-agent,durable): client identity follow-ups | covered | Identity row. NVIDIA capitalizes the first letter (`capitalize-invoke-origin` in `src/cadr-ai/support/identity.lisp`). OpenCode session headers match host `opencode.ai`, including a custom base URL (`opencode-target-p`). Codex `originator` stays the product name and does not follow attribution. Upstream hardcodes `pi`. cadr hardcodes `cadr` in `src/cadr-ai/providers/codex.lisp`. Login `agentName` is not filled from attribution. `models-runtime-login` only forwards an explicit name, and the CLI does not pass one. Durable wrapper edits in this commit are outside the three packages. |
| `adc5fa9f800b` | feat(ai,agent,coding-agent): move client identity and provider attribution into pi-ai | covered | Identity row. User-Agent shape, OpenRouter, NVIDIA NIM, OpenCode attribution, Bedrock short agent, classifier User-Agent, GitHub tool-download User-Agent. `build-request :around` in `src/cadr-ai/provider.lisp` covers pi-messages. `src/cadr-ai/images.lisp` applies the same headers to OpenRouter image generation. |
| `adfc14461aa1` | fix(coding-agent): apply /compact instructions to split-turn prefix summary | covered | Summary row. `#11058`. |
| `612a172e6e39` | fix(tui): escape regex metacharacters in single-segment fd queries | covered | `@` completion row. Changelog cites `#10972`. This commit cites `#11212`. Same query escaping. |
| `6e491cfa95b5` | fix(ai): match retryable status codes only as standalone numbers | covered | Retry row. `#11057`. |
| `29057ece3ef9` | fix(ai): retry Codex CLI stream disconnect errors relayed by proxies | covered | Retry row. `#11057`. |
| `cedefc53264f` | fix(ai): handle ChatGPT Business workspace usage limit errors | covered | ChatGPT Business row. |
| `e5fe9777b965` | fix(ai,coding-agent): drop models retired upstream | gap | The Copilot default `gpt-5.4` to `gpt-6.1-sol` is the default-model row. The same commit drops catalog ids the generator could no longer name. See Gaps. |
| `bdd9f0399d78` | fix(coding-agent): accept mcp.json files with a UTF-8 BOM | covered | mcp.json BOM row. `#11191`. |
| `22dc6c26f3c5` | fix(coding-agent): expose @earendil-works/pi-ai/models in the extension loader | covered | Windows and N/A bundle. Adjudicated N/A. JS jiti alias for the pi-ai `/models` subpath. |
| `885a564b3b22` | fix(coding-agent): queue codemode scripts at the worker limit | out of scope | Codemode worker queue and `PI_CODEMODE_MAX_WORKERS`. `#11184`. The method excludes this. |
| `f8ab362cca0f` | fix(coding-agent): keep clipboard helpers out of pi's process group | covered | Ctrl+Z row. `#11179`. `src/cadr-cli/interactive/clipboard.lisp` uses `setsid --wait`. |
| `38847563f4b0` | fix(coding-agent): stack concurrent extension dialogs instead of replacing them | covered | Extension dialog row. `#11166` `#9909`. |
| `9df819de392d` | fix(tui): restore terminal modes when the process exits without stop() | covered | Terminal restore row. `#11170`. |
| `2ed3118b00cc` | fix(tui): stop unclosed display math from swallowing Markdown tables | covered | Math and CJK row. `#11159`. |
| `396ecd7b8f3a` | feat(tui): enable Kitty images for Rex | covered | Rex row. Turns images on after `0ed1b0431444` left them off. |
| `fdce48eb404e` | fix(ai): drop Codex models rejected for ChatGPT accounts | covered | openai-codex catalog row. `#11173`. Drops `gpt-5.5` and `gpt-5.3-codex-spark` from `openai-codex` only. |
| `26293e74f664` | fix(coding-agent): render CJK emphasis in HTML export | gap | The CJK cases are the HTML CJK row. The same commit replaces vendored marked 18.0.5 with 18.0.11. No row describes that parser change. See Gaps. |
| `fbc456d827d7` | fix(ai): expect xhigh thinking for Grok 4.3 and Grok 4.5 | covered | xAI xhigh row. Test plus changelog. Generated `xai` rows in `src/cadr-ai/models.generated.lisp` map `:XHIGH` to `"xhigh"`. `grok-4.3` still has `:OFF . "none"`. `grok-4.5` has `:OFF` with no `"none"`. |
| `a731ba8b80ac` | docs(tui): add changelog entry for CJK emphasis fix | out of scope | Docs. The render change is `b2d0da6fe3de`. |
| `b2d0da6fe3de` | fix(tui): render CJK emphasis next to punctuation | covered | Math and CJK row. `#10730`. Lockfile churn in the same commit is build metadata. |
| `1d01b3b1f8de` | Break single Mermaid diagram into two | out of scope | Docs. Only `packages/coding-agent/docs/extensions.md`. |
| `ea25697e91db` | fix(coding-agent): accept managed install markers with a UTF-8 BOM | covered | Windows and N/A bundle. Adjudicated N/A for `pi update` BOM. |
| `530015d93a40` | fix(ai): only list announced removals as still unavailable | covered | Responses prefix row. `#10940` follow-up. Same-message removals are recorded after the incremental tools notice. `responses-system-input-items` in `src/cadr-ai/providers/openai.lisp` emits the incremental notice, then appends the removal notice, then adds those names to `unavailable`. |
| `caa6967b6212` | fix(ai): keep the prompt cache across tool changes on Responses | covered | Responses prefix row. `#10940` `#11142`. |
| `73f8de80bc87` | fix(ai): recover from Copilot request-size overflow | covered | HTTP 413 row. `#11016`. |
| `0ed1b0431444` | feat(tui): detect Rex terminal for OSC 8 hyperlinks | covered | Rex row. `#11131`. Hyperlinks and truecolor. Images land in `396ecd7b8f3a`. |
| `61060ddf8c17` | fix(coding-agent): resolve Windows shells from installation directories | covered | Windows and N/A bundle, the ported half. `#9501`. `src/cadr-cli/support/shell-process.lisp` checks `ProgramFiles`, `SystemRoot`, and `WindowsPowerShell`. Empty `SystemRoot` still points taskkill at `C:\Windows`. `src/cadr-cli/tool-manager.lisp` does not read `WINDIR`. |
| `28bea006be4a` | fix(coding-agent): accept Windows Store shell aliases | covered | Windows and N/A bundle. Adjudicated N/A. `#9504`. |
| `e86b054753b5` | fix(ai): OpenRouter reasoning test uses deepseek-r1-0528, deepseek-r1 left the catalog | gap | Test-only witness. OpenRouter `deepseek/deepseek-r1` left the generated catalog. No queue row. See Gaps. |
| `d2e7d8b7c1d3` | feat(ai): add MiniMax-M3.1-Flash and hide only old MiniMax models | covered | MiniMax row. `#11121`. |
| `2ec55d808d45` | feat: Durable and pi-ai telemetry; Context.telemetry is always a span | covered | Windows and N/A bundle. Adjudicated N/A for the telemetry span. Includes the `telemetryContext` to `telemetry` rename in `packages/ai`. Durable and Chord files in the same commit are outside the three packages. |
| `482c1381a00d` | fix(ai): update GLM-4.6V Coding Plan cache read price in test | gap | Test-only witness. China Coding Plan `glm-4.6v` cache read moves from 0 to 0.05. No changelog bullet and no queue row. See Gaps. |
| `0b102787cd62` | docs(coding-agent): restore extension guide details | out of scope | Docs. `#11039`. |
| `8efd314fa3d3` | docs(ai,coding-agent): generate models.json reference from schemas | covered | Windows and N/A bundle. Adjudicated N/A for the generated models reference. `#10790`. Schema `description` and `default` annotations document editor hints. `Compile` still checks. It does not fill defaults, so request behavior is unchanged. Adding `azure-openai-responses` and `openai-codex-responses` to `CompatSchemasByApi` reuses the existing Responses compat object. |
| `95364a54efb8` | feat(coding-agent): default NVIDIA to Nemotron 3.5 Super VL | covered | Default-model row. `#10910`. |
| `698a2d23b86a` | fix(ai): retry more gateway upstream failure errors | covered | Retry row. `#10920`. |
| `4dd2b149d155` | fix(ai): treat whitespace-only tool output as empty | covered | Whitespace tool-output row. `#8720`. |
| `6fcb48670fc0` | fix(coding-agent): remove fixed output limits from summary requests | covered | Summary row. `#9512` `#9075` `#11036`. `reserveTokens` only decides when compaction starts. |
| `90d863f7c118` | fix(coding-agent): use mimo-v2.6-pro as Xiaomi default model | covered | Default-model row. |
| `99fe1489707f` | fix(ai): use mimo-v2.6 models in Xiaomi tests | out of scope | Test ids following the catalog swap. The user-visible swap is the default-model row. |
| `0fbdbd3f8ab1` | fix(ai): retry node-fetch 'request to ... failed' errors | covered | Retry row. `#10996`. Vertex token refresh. |
| `ae7b16d43b7c` | Add [Unreleased] section for next cycle | out of scope | Docs. Empty changelog headings. |

## Changelog entries

Every `## [1.4.0]` bullet in the three changelogs maps to a commit above.
coding-agent repeats the ai and tui bullets. Those repeats use the same class.

| Changelog bullet | Commit | Class |
|---|---|---|
| Rename `telemetryContext` to `telemetry` | `2ec55d808d45` | covered, N/A telemetry span |
| New User-Agent shape, remove `getPiUserAgent()` | `adc5fa9f800b` | covered, identity |
| `resolveTranscriptTools` takes a support mode | `caa6967b6212` | covered, Responses prefix |
| Client identity option and attribution headers | `adc5fa9f800b`, `04a93bad8f15` | covered, identity |
| Bedrock, OpenRouter images, pi-messages, and classifier User-Agent | `adc5fa9f800b` | covered, identity |
| `x-opencode-session` for custom providers aimed at `opencode.ai` | `04a93bad8f15` | covered, identity |
| `pi.ai.request` / `pi.ai.poll` spans and metrics | `2ec55d808d45` | covered, N/A telemetry span |
| MiniMax-M3.1-Flash, denylist of old M2 models | `d2e7d8b7c1d3` | covered, MiniMax |
| ChatGPT Business usage limit is not retried | `cedefc53264f` | covered, ChatGPT Business |
| Classifier image input, `SystemOneCompat`, Clef Omni, Jev 1.14 | `7f225f25d8a9` | covered, classifier |
| Grok 4.3 and 4.5 offer `xhigh` | `fbc456d827d7` | covered, xAI xhigh |
| Clef Flash and Jev catalog prices | `7f225f25d8a9` | covered, classifier |
| Whitespace-only tool output | `4dd2b149d155` | covered, whitespace |
| Retry gateway upstream failures | `698a2d23b86a` | covered, retry |
| Retry Vertex token refresh `request to ... failed` | `0fbdbd3f8ab1` | covered, retry |
| Retry `stream disconnected before completion` | `29057ece3ef9` | covered, retry |
| Do not treat digits inside request ids as HTTP status | `6e491cfa95b5` | covered, retry |
| Responses deferred loads keep the prefix after a removal | `caa6967b6212`, `530015d93a40` | covered, Responses prefix |
| Any HTTP 413 is context overflow | `73f8de80bc87` | covered, HTTP 413 |
| Drop `openai-codex` `gpt-5.5` and `gpt-5.3-codex-spark` | `fdce48eb404e` | covered, openai-codex catalog |
| Rex OSC 8, truecolor, Kitty images | `0ed1b0431444`, `396ecd7b8f3a` | covered, Rex |
| Unclosed `$$` no longer swallows a GFM table | `2ed3118b00cc` | covered, math and CJK |
| CJK bold and italic in the TUI | `b2d0da6fe3de` | covered, math and CJK |
| Restore terminal modes on exit without `stop()` | `9df819de392d` | covered, terminal restore |
| `@` autocomplete escapes regex metacharacters | `612a172e6e39` | covered, `@` completion |
| codemode `models.classify()` images | `7f225f25d8a9` | covered as the exclusion already written on the classifier row |
| Models Configuration reference and schema descriptions | `8efd314fa3d3` | covered, N/A models reference |
| Summaries use the model output limit. `reserveTokens` only starts compaction | `6fcb48670fc0` | covered, summary |
| Codemode waits for a free worker, `PI_CODEMODE_MAX_WORKERS` | `885a564b3b22` | out of scope |
| models.json provider compat applies to classifier models | `7f225f25d8a9` | covered, classifier |
| Extension hooks do not see default attribution. GitHub release checks use the detailed User-Agent | `adc5fa9f800b` | covered, identity |
| Copilot default becomes `gpt-6.1-sol` because `gpt-5.4` was retired | `e5fe9777b965` | the bullet is the default-model row. The same commit's other retired ids are a gap |
| NVIDIA default `nvidia/nemotron-3.5-super-vl-120b-a12b` | `95364a54efb8` | covered, default model |
| Xiaomi default `mimo-v2.6-pro` | `90d863f7c118` | covered, default model |
| `pi update` BOM on `managed-install.json` | `ea25697e91db` | covered, N/A |
| HTML export CJK emphasis | `26293e74f664` | the bullet is the HTML CJK row. The marked 18.0.11 bump in that commit is a gap |
| Stack extension dialogs | `38847563f4b0` | covered, dialogs |
| Clipboard helpers leave the process group | `f8ab362cca0f` | covered, Ctrl+Z |
| Extension loader exposes `@earendil-works/pi-ai/models` | `22dc6c26f3c5` | covered, N/A |
| `mcp.json` UTF-8 BOM | `bdd9f0399d78` | covered, mcp.json BOM |
| `/compact` instructions on a split-turn prefix | `adfc14461aa1` | covered, summary |
| Extension tools missing from the branch loadout stay active | `bd3c9b823762` | covered, session restore |
| Drop tool results that belong to a truncated tool call | `02726086d11c` | covered, output limit |
| `rg --no-config` | `8c4e873899b9` | covered, grep |
| Windows Store shell aliases | `28bea006be4a` | covered, N/A |
| PowerShell install dirs, SystemRoot, legacy WSL bash | `61060ddf8c17` | covered, Windows ported half |

The first queue row, the gate going green for 41 extension events and the HTML export summary, has no new upstream event or HTML structure in this range. `packages/coding-agent/src/core/extensions/types.ts` does not change. The HTML diff in range is the CJK export. That row repairs cadr against behavior already at the v1.4.0 pin. It is not a missing upstream delta.

No changelog bullet is itself a gap. Four commits are gaps. `e5fe9777b965` also carries the Copilot default sentence, which the default-model row covers. `26293e74f664` also carries the HTML CJK sentence, which that row covers.

## Gaps

Generated model shards are gitignored upstream (`82432219a` notes that). These three commits are the witnesses that the published v1.4.0 catalog changed. cadr's `src/cadr-ai/models.generated.lisp` is still the snapshot stamped `2026-09-05T11:58:56.761Z`. Ids that this range dropped, and that cadr does not list, are not gaps. Together `deepseek-ai/DeepSeek-R1` and Copilot `claude-opus-4.6` are already absent.

### Retired models still listed

Upstream. `e5fe9777b965` deletes generator entries and tests because models.dev no longer produces them. The type union stopped including them, so the published catalog does too.

- `baseten` / `moonshotai/Kimi-K2.6`. The Baseten test that read its thinking map was deleted.
- `together` / `MiniMaxAI/MiniMax-M2.7`. The Together test that expected a fixed reasoning map was deleted.
- `github-copilot` / `claude-opus-4.7`. The Copilot Anthropic test that read this id was deleted.
- `github-copilot` / `gpt-5.4` and `github-copilot` / `gpt-5.5`. Both left `GITHUB_COPILOT_EXTENDED_CONTEXT_MODELS` because those ids no longer typecheck. The changelog only mentions `gpt-5.4` as the retired default.

cadr now. `src/cadr-ai/models.generated.lisp` still registers all five. Copilot `claude-opus-4.7` is the 1_000_000-context row near line 2336. Copilot `gpt-5.4` is near line 2493. Copilot `gpt-5.5` is near line 2529. Baseten `moonshotai/Kimi-K2.6` is near line 1207. Together `MiniMaxAI/MiniMax-M2.7` is near line 8302.

Suggestion. Port. Drop these five ids from the generated catalog. The queue already did this kind of edit for `openai-codex` `gpt-5.5` and `gpt-5.3-codex-spark`, and for the Xiaomi v2.5 replacement. Leaving retired ids selectable is the user-visible difference. The Copilot default change itself stays covered by the default-model row.

### OpenRouter deepseek/deepseek-r1

Upstream. `e86b054753b5` changes `packages/ai/test/openai-completions-tool-choice.test.ts` from `openrouter` / `deepseek/deepseek-r1` to `deepseek/deepseek-r1-0528` because `deepseek-r1` left the catalog.

cadr now. `src/cadr-ai/models.generated.lisp` still has `:PROVIDER :OPENROUTER :ID "deepseek/deepseek-r1"` near line 5453. `deepseek/deepseek-r1-0528` is also present.

Suggestion. Port. Remove the OpenRouter `deepseek/deepseek-r1` row. This commit does not say the Vercel copy left, so leave `:PROVIDER :VERCEL-AI-GATEWAY :ID "deepseek/deepseek-r1"` alone.

### GLM-4.6V Coding Plan cache read price

Upstream. `482c1381a00d` changes `packages/ai/test/zai-coding-plan-models.test.ts`. China Coding Plan `glm-4.6v` cache read moves from `0` to `0.05`. Input stays `0.3`, output stays `0.9`. The commit message says Coding Plan entries copy that models.dev `cache_read`.

cadr now. `:PROVIDER :ZAI-CODING-CN :ID "glm-4.6v"` near line 9902 still has `:CACHE-READ-PRICE 0.0d0`, `:INPUT-PRICE 0.3d0`, `:OUTPUT-PRICE 0.9d0`. No other provider in this file has id `glm-4.6v`.

Suggestion. Port. Set that cache read price to `0.05`. Cost estimates for this model are what the user sees. A later full regeneration of `models.generated.lisp` would absorb this and the retired ids together. These catalog commits are the v1.3.0 to v1.4.0 slice, so a full regeneration is not required to close them.

### HTML export marked 18.0.11

Upstream. `26293e74f664` vendors `packages/coding-agent/src/core/export-html/vendor/marked.min.js` from marked 18.0.5 to 18.0.11. The changelog line is only the CJK emphasis fix. In the link tokenizer, a non-image link whose label already emitted an inner link returns no token. The outer link is dropped. v1.3.0's `be()` always returned the outer link after `inlineTokens`.

cadr now. `src/cadr-agent/export-html/vendor/marked.min.js` is marked 18.0.11. Its sha256 is `438eedfcf932a414d0d0bfeea32dc365c063563b8ca713b4687fc8f8b501e5e4`, the same as v1.4.0 `packages/coding-agent/src/core/export-html/vendor/marked.min.js`. The `linkEmitted` early return is in that file. `test/cadr-agent/session-v2-test.lisp` locks the version string `marked v18.0.11`.

Suggestion. N/A. The HTML CJK row ported the vendor file and never named the tokenizer change, so the queue does not cover it. The bytes already match v1.4.0, so there is nothing left to port.
