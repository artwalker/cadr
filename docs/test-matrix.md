# Gate denominators (Goal 20 Part M)

<!-- GOAL20_TEST_CHECKS systems=9 checks=19371 pass=19371 skip=0 fail=0 -->

Date: 2026-08-13. Recount: read this file against `scripts/verify.sh`.
`scripts/test-cl.sh` rewrites the `GOAL20_TEST_CHECKS` comment after a green
nine-system run and fails when the committed count drifted. Do not edit it
by hand.

Each deterministic `verify.sh` stage must answer three questions. "N/N"
without that answer is an undeclared denominator.

| Gate | Checks | Does not check | A pass means | Rest covered by |
|---|---|---|---|---|
| `test-cl.sh` (Nine-system FiveAM) | Isolated HOME, all packaged FiveAM files | Live provider I/O; render-diff screens; compile WARNING count | Every assertion in those suites held this run | render-diff, live stages, cadr-compile-warnings |
| `write-test-check-anchor.py` | `GOAL20_TEST_CHECKS` equals this run's systems/checks/pass/skip/fail | Whether those assertions are the *right* assertions | The committed FiveAM total is this run's total | Adding tests without re-recording via `test-cl.sh --record` |
| `check-code-organization.py` | File placement vs exemptions | Behaviour; Lisp-ification status | Listed files sit where the manifest says | source-parity, Part I |
| `check-product-identity.py` | Token allowlist | Runtime strings not in the allowlist scan | No unallowlisted product-token in scanned files | baseline-string-reachability |
| `render-diff.py gate --tier core` | Semantic-screen SHA pairs + I01/I04 adjudications for core scenarios | Full-tier scenarios; whether a green pair is the *right* picture | Every core checkpoint is aligned or has a live disposition | full-tier gate; Part L reverse scan |
| `tool-result-diff.py` | Tool-result byte contract vs baseline | TUI chrome around those results | Listed tool results match after normalize | render-diff |
| `event-diff.py` | Session event stream vs baseline | TUI | Listed events match | render-diff |
| `goal11-performance-gate.py` | Absolute ceilings + 3 pi ratios; ledger-vs-history consistency via `write-performance-ledger.py --check` | Self-history (Part A, not enabled); non-TUI packages | No ceiling breach; ratios hold on same-machine; committed ledger matches its history | Part A/H once enabled |
| `derive-source-parity-mappings.lisp --gate` | Every symbol cited in the source ledger resolves in the live image (paths and positions derive from sb-introspect) | Line-number drift between regenerations (healed by `--write`, not gate-red) | A renamed or deleted implementation fails the gate | Part F mapping repairs |
| `check-source-parity-cadr-paths.py` | Every cadr-side mapping path in `source-parity.md` exists on disk; the rotten set equals `docs/source-parity-rotten-mappings.json` exactly | Line-number freshness of surviving mappings | No new rot enters, and every heal shrinks the record in the same commit | Part F mapping repairs |
| `baseline-string-reachability.py` | Named baseline literals have a cadr producer | cadr-only leaks; "is this the right picture" | Each listed literal is live in the named file | cadr-visible-output-origin |
| `cadr-visible-output-origin.py` | Unformatted Lisp tokens on cadr screens | Baseline-string presence | No NIL / `#<` / `#S(` on scanned cadr screens | FiveAM goal20-l-custom-entry-* |
| `cadr-compile-warnings.py` | cadr-owned compile WARNING == 0; unallowlisted muffle | STYLE-WARNING fail-closed; notes; third-party | No new cadr WARNING | STYLE-WARNING ledger (count only) |
| provider slot enum (FiveAM) | Every `provider-definition` slot compared or uniquely excluded; `default-model` compared; xAI is `grok-4.5` | Login *control flow* | Table fields are complete | `classify-post-login-model` FiveAM |

provider-matrix after N1: compared slots come from `sb-mop:class-slots`. Exclusion count is 1 (`baseline-source`). Compared count is the rest. Exclusion count is not allowed to exceed compared count.

`baseline-visible-strings` 672/672 remains **drive completeness of the pi construction suite**, not cadr consistency. Declared here so that number cannot be cited as cadr parity.

## Human stage: exploratory testing charter (goal 20, item 12E-2)

Adjudicated 2026-08-15 (advisor; user holds veto): structured exploratory
testing is a required stage before every Part close. It is a human stage,
not a script — nothing here runs in `verify.sh`. Every goal-20 P0 was
found by a person playing with the product, not by a gate; this section
reclassifies that channel from accident to expected yield and makes it
checkable.

The acceptance report of a Part is incomplete without a charter record
containing all of:

| Field | Why it is required |
|---|---|
| Charter text — the boundary of this round | Otherwise "explored" is unfalsifiable |
| What this round deliberately does **not** cover | One round cannot cover everything; the exclusion is what makes the next round's choice evidence-based |
| Duration | 45 minutes and 5 minutes are not the same claim |
| Findings, **including "nothing found"** | An empty result is data; several empty rounds mean the charter is stale |
| Disposition of each finding | Exactly two exits: converted to a scripted assertion, or registered as a no-oracle area (standing gaps go to `docs/open-questions.md`). "Noted" is not a disposition |

Time-box guide: ~45 minutes per round. Example charters: run one full
agent session in each bundled game; resize the terminal mid-turn;
interrupt a stream mid-flight.

## Theme index

Maps every `test/**/*.lisp` and `test/**/*.py` file to a theme.
Goal-numbered names stay as they are (they lock a goal acceptance
baseline); the theme column is their subject. Existing sections
above are unchanged. Recount: 199 files.

### cadr-core

| Theme | File |
|---|---|
| core | `test/cadr-core/core-test.lisp` |
| support (package) | `test/cadr-core/package.lisp` |

### cadr-ai

| Theme | File |
|---|---|
| auth | `test/cadr-ai/auth-test.lisp` |
| bedrock error metadata | `test/cadr-ai/bedrock-error-metadata-test.lisp` |
| faux provider | `test/cadr-ai/faux-provider-test.lisp` |
| auth lock | `test/cadr-ai/goal12-auth-test.lisp` |
| provider capabilities lock | `test/cadr-ai/goal12-capabilities-test.lisp` |
| codex websocket lock | `test/cadr-ai/goal12-codex-websocket-test.lisp` |
| model-data lock | `test/cadr-ai/goal12-model-data-test.lisp` |
| provider capabilities lock | `test/cadr-ai/goal12-provider-capabilities-test.lisp` |
| provider organization | `test/cadr-ai/goal14-provider-organization-test.lisp` |
| auth lock | `test/cadr-ai/goal18-auth-test.lisp` |
| json parse windows | `test/cadr-ai/goal20-json-parse-windows-test.lisp` |
| stream accumulation | `test/cadr-ai/goal20-stream-accumulation-test.lisp` |
| websocket | `test/cadr-ai/goal20-websocket-test.lisp` |
| support | `test/cadr-ai/helpers.lisp` |
| http | `test/cadr-ai/http-test.lisp` |
| image generation | `test/cadr-ai/image-generation-test.lisp` |
| image model | `test/cadr-ai/image-model-test.lisp` |
| json | `test/cadr-ai/json-test.lisp` |
| support | `test/cadr-ai/live-package.lisp` |
| live provider | `test/cadr-ai/live-provider-test.lisp` |
| opencode-go live | `test/cadr-ai/opencode-go-live-test.lisp` |
| models runtime | `test/cadr-ai/models-runtime-test.lisp` |
| openai completions | `test/cadr-ai/openai-completions-test.lisp` |
| support (package) | `test/cadr-ai/package.lisp` |
| provider compat | `test/cadr-ai/provider-compat-test.lisp` |
| provider history | `test/cadr-ai/provider-history-test.lisp` |
| provider payloads | `test/cadr-ai/provider-payloads-test.lisp` |
| provider registry | `test/cadr-ai/provider-registry-test.lisp` |
| provider responses | `test/cadr-ai/provider-responses-test.lisp` |
| provider streams | `test/cadr-ai/provider-streams-test.lisp` |
| provider wave1 | `test/cadr-ai/provider-wave1-test.lisp` |
| provider wave3 | `test/cadr-ai/provider-wave3-test.lisp` |
| retry | `test/cadr-ai/retry-test.lisp` |
| sse | `test/cadr-ai/sse-test.lisp` |
| types | `test/cadr-ai/types-test.lisp` |
| utilities | `test/cadr-ai/utilities-test.lisp` |

### cadr-agent

| Theme | File |
|---|---|
| compaction | `test/cadr-agent/compaction-test.lisp` |
| execution env | `test/cadr-agent/execution-env-test.lisp` |
| extensions | `test/cadr-agent/extensions-test.lisp` |
| extensions wave2 | `test/cadr-agent/extensions-wave2-test.lisp` |
| extensions wave3 | `test/cadr-agent/extensions-wave3-test.lisp` |
| core capabilities lock | `test/cadr-agent/goal12-core-capabilities-test.lisp` |
| extension API lock | `test/cadr-agent/goal12-extension-api-test.lisp` |
| harness events | `test/cadr-agent/harness-events-test.lisp` |
| support | `test/cadr-agent/helpers.lisp` |
| loop | `test/cadr-agent/loop-test.lisp` |
| support (package) | `test/cadr-agent/package.lisp` |
| queue | `test/cadr-agent/queue-test.lisp` |
| resources | `test/cadr-agent/resources-test.lisp` |
| retry | `test/cadr-agent/retry-test.lisp` |
| schema | `test/cadr-agent/schema-test.lisp` |
| session | `test/cadr-agent/session-test.lisp` |
| session v2 | `test/cadr-agent/session-v2-test.lisp` |
| session v3 | `test/cadr-agent/session-v3-test.lisp` |
| shutdown | `test/cadr-agent/shutdown-test.lisp` |
| sqlite storage | `test/cadr-agent/sqlite-storage-test.lisp` |
| storage | `test/cadr-agent/storage-test.lisp` |
| tool loop | `test/cadr-agent/tool-loop-test.lisp` |
| truncate | `test/cadr-agent/truncate-test.lisp` |

### cadr-tui

| Theme | File |
|---|---|
| alt screen | `test/cadr-tui/alt-screen-test.lisp` |
| autocomplete | `test/cadr-tui/autocomplete-test.lisp` |
| component parity | `test/cadr-tui/component-parity-test.lisp` |
| components | `test/cadr-tui/components-test.lisp` |
| composition | `test/cadr-tui/composition-test.lisp` |
| editor parity | `test/cadr-tui/editor-parity-test.lisp` |
| fuzzy | `test/cadr-tui/fuzzy-test.lisp` |
| fuzzy normalized match | `test/cadr-tui/goal20-fuzzy-normalized-test.lisp` |
| support | `test/cadr-tui/helpers.lisp` |
| input component | `test/cadr-tui/input-component-test.lisp` |
| input editor | `test/cadr-tui/input-editor-test.lisp` |
| keybindings | `test/cadr-tui/keybindings-test.lisp` |
| keys | `test/cadr-tui/keys-test.lisp` |
| fixture data | `test/cadr-tui/latex-reference-cases.lisp` |
| latex | `test/cadr-tui/latex-test.lisp` |
| manual acceptance | `test/cadr-tui/manual-acceptance-test.lisp` |
| fixture data | `test/cadr-tui/mermaid-golden-data.lisp` |
| mermaid golden | `test/cadr-tui/mermaid-golden-test.lisp` |
| fixture data | `test/cadr-tui/mermaid-reference-cases.lisp` |
| fixture data | `test/cadr-tui/mermaid-transform-data.lisp` |
| mermaid transform | `test/cadr-tui/mermaid-transform-test.lisp` |
| overlay | `test/cadr-tui/overlay-test.lisp` |
| support (package) | `test/cadr-tui/package.lisp` |
| renderer | `test/cadr-tui/renderer-test.lisp` |
| stdin buffer | `test/cadr-tui/stdin-buffer-test.lisp` |
| terminal colors | `test/cadr-tui/terminal-colors-test.lisp` |
| terminal image | `test/cadr-tui/terminal-image-test.lisp` |
| terminal parity | `test/cadr-tui/terminal-parity-test.lisp` |
| terminal | `test/cadr-tui/terminal-test.lisp` |
| theme | `test/cadr-tui/theme-test.lisp` |
| truncate to width | `test/cadr-tui/truncate-to-width-test.lisp` |
| unicode | `test/cadr-tui/unicode-test.lisp` |
| word navigation | `test/cadr-tui/word-navigation-test.lisp` |
| wrap ansi | `test/cadr-tui/wrap-ansi-test.lisp` |

### cadr-cli

| Theme | File |
|---|---|
| bash | `test/cadr-cli/bash-test.lisp` |
| build | `test/cadr-cli/build-test.lisp` |
| config auth | `test/cadr-cli/config-auth-test.lisp` |
| data migration | `test/cadr-cli/data-migration-test.lisp` |
| execution policy | `test/cadr-cli/execution-policy-test.lisp` |
| extensions | `test/cadr-cli/extensions-test.lisp` |
| file tools | `test/cadr-cli/file-tools-test.lisp` |
| core capabilities lock | `test/cadr-cli/goal12-core-capabilities-test.lisp` |
| bundled examples lock | `test/cadr-cli/goal12-examples-test.lisp` |
| SDK lock | `test/cadr-cli/goal12-sdk-test.lisp` |
| TUI composition lock | `test/cadr-cli/goal12-tui-composition-test.lisp` |
| presentation lock | `test/cadr-cli/goal13-presentation-test.lisp` |
| code-organization A0 | `test/cadr-cli/goal14-a0-test.lisp` |
| code organization | `test/cadr-cli/goal14-organization-test.lisp` |
| render-diff A0 | `test/cadr-cli/goal15-a0-test.lisp` |
| render-diff part C | `test/cadr-cli/goal15-part-c-test.lisp` |
| compaction lock | `test/cadr-cli/goal17-compaction-test.lisp` |
| login dialog lock | `test/cadr-cli/goal17-login-dialog-test.lisp` |
| content migration lock | `test/cadr-cli/goal18-content-migration-test.lisp` |
| debug command lock | `test/cadr-cli/goal18-debug-command-test.lisp` |
| docs lock | `test/cadr-cli/goal18-docs-test.lisp` |
| login cancel lock | `test/cadr-cli/goal18-login-cancel-test.lisp` |
| login forms lock | `test/cadr-cli/goal18-login-forms-test.lisp` |
| migration lock | `test/cadr-cli/goal18-migration-test.lisp` |
| presentation numbers lock | `test/cadr-cli/goal18-presentation-numbers-test.lisp` |
| startup resources lock | `test/cadr-cli/goal18-startup-resources-test.lisp` |
| example games | `test/cadr-cli/goal20-example-games-test.lisp` |
| tic-tac-toe steer | `test/cadr-cli/tic-tac-toe-steer-test.lisp` |
| part B ledger | `test/cadr-cli/goal20-part-b-ledger-test.lisp` |
| part I file verdicts | `test/cadr-cli/goal20-part-i-test.lisp` |
| part L visible strings | `test/cadr-cli/goal20-part-l-test.lisp` |
| selector cache | `test/cadr-cli/goal20-selector-cache-test.lisp` |
| interactive PTY | `test/cadr-cli/goal9-a2-interactive-test.lisp` |
| process modes (faux) | `test/cadr-cli/goal9-a2-process-faux-test.lisp` |
| interactive PTY harness | `test/cadr-cli/goal9-a2-pty-harness.lisp` |
| process-mode workflows | `test/cadr-cli/goal9-a2-workflows-test.lisp` |
| runtime parity | `test/cadr-cli/goal9-b-runtime-parity-test.lisp` |
| base-screen contract | `test/cadr-cli/goal9-b3-base-screen-contract-test.lisp` |
| overlay contract | `test/cadr-cli/goal9-b3-overlay-contract-test.lisp` |
| overlay regressions | `test/cadr-cli/goal9-b3-p2-regressions-test.lisp` |
| support | `test/cadr-cli/helpers.lisp` |
| live auth | `test/cadr-cli/live-auth-test.lisp` |
| live gate | `test/cadr-cli/live-gate-test.lisp` |
| support | `test/cadr-cli/live-package.lisp` |
| live | `test/cadr-cli/live-test.lisp` |
| llama extension | `test/cadr-cli/llama-extension-test.lisp` |
| migration | `test/cadr-cli/migration-test.lisp` |
| modes | `test/cadr-cli/modes-test.lisp` |
| support (package) | `test/cadr-cli/package.lisp` |
| part b cli | `test/cadr-cli/part-b-cli-test.lisp` |
| part b config | `test/cadr-cli/part-b-config-test.lisp` |
| part b interactive | `test/cadr-cli/part-b-interactive-test.lisp` |
| part b models | `test/cadr-cli/part-b-models-test.lisp` |
| part b package | `test/cadr-cli/part-b-package-test.lisp` |
| part b sdk | `test/cadr-cli/part-b-sdk-test.lisp` |
| part b tools | `test/cadr-cli/part-b-tools-test.lisp` |
| part b utilities | `test/cadr-cli/part-b-utilities-test.lisp` |
| remote repl | `test/cadr-cli/remote-repl-test.lisp` |
| repl | `test/cadr-cli/repl-test.lisp` |
| rpc | `test/cadr-cli/rpc-test.lisp` |
| search tools | `test/cadr-cli/search-tools-test.lisp` |
| session command | `test/cadr-cli/session-command-test.lisp` |
| tool result parity | `test/cadr-cli/tool-result-parity-test.lisp` |
| tui | `test/cadr-cli/tui-test.lisp` |

### cadr-storage

| Theme | File |
|---|---|
| support (package) | `test/cadr-storage/package.lisp` |
| storage | `test/cadr-storage/storage-test.lisp` |

### cadr-server

| Theme | File |
|---|---|
| support (package) | `test/cadr-server/package.lisp` |
| server | `test/cadr-server/server-test.lisp` |

### cadr-protocol

| Theme | File |
|---|---|
| cbor | `test/cadr-protocol/cbor-test.lisp` |
| framing | `test/cadr-protocol/framing-test.lisp` |
| support (package) | `test/cadr-protocol/package.lisp` |
| protocol | `test/cadr-protocol/protocol-test.lisp` |

### cadr-evals

| Theme | File |
|---|---|
| artifacts | `test/cadr-evals/artifacts-test.lisp` |
| evals | `test/cadr-evals/evals-test.lisp` |
| extension authoring | `test/cadr-evals/extension-authoring-test.lisp` |
| harness table | `test/cadr-evals/harness-table-test.lisp` |
| live evals | `test/cadr-evals/live-evals-test.lisp` |
| support | `test/cadr-evals/live-package.lisp` |
| support (package) | `test/cadr-evals/package.lisp` |
| pi harness | `test/cadr-evals/pi-harness-test.lisp` |
| reporter | `test/cadr-evals/reporter-test.lisp` |
| summary | `test/cadr-evals/summary-test.lisp` |

### Live runner (not one of the nine FiveAM systems)

| Theme | File |
|---|---|
| support (package) | `test/cadr-live/package.lisp` |
| live runner | `test/cadr-live/runner.lisp` |
| cadr live support | `test/cadr-live-support.lisp` |

### Python gates

| Theme | File |
|---|---|
| baseline visible strings extractor | `test/baseline-visible-strings-extractor-test.py` |
| code organization gate | `test/code-organization-gate-test.py` |
| event diff gate | `test/event-diff-gate-test.py` |
| goal11 performance gate | `test/goal11-performance-gate-test.py` |
| goal20 liveness check | `test/goal20-liveness-check-test.py` |
| part B ledger | `test/goal20-part-b-ledger-test.py` |
| goal20 unpaired paths | `test/goal20-unpaired-paths-test.py` |
| product identity gate | `test/product-identity-gate-test.py` |
| render diff gate | `test/render-diff-gate-test.py` |
| tool result diff gate | `test/tool-result-diff-gate-test.py` |

### Fixtures and drivers

| Theme | File |
|---|---|
| cadr driver | `test/fixtures/event-diff/cadr-driver.lisp` |
| legacy wave2 api | `test/fixtures/extensions/legacy-wave2-api.lisp` |
| rpc ui | `test/fixtures/extensions/rpc-ui.lisp` |
| shutdown marker | `test/fixtures/extensions/shutdown-marker.lisp` |
| goal9 a2 faux mode child | `test/fixtures/goal9-a2-faux-mode-child.lisp` |
| openai sse server | `test/fixtures/openai-sse-server.py` |
| cadr driver | `test/fixtures/render-diff/cadr-driver.lisp` |
| rpc process client | `test/fixtures/rpc-process-client.py` |
| cadr driver | `test/fixtures/tool-result-diff/cadr-driver.lisp` |
