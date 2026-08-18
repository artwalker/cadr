# Changelog

All notable changes to Cadr are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project has not
yet cut a Cadr release tag. The `0.2.0` entry is frozen for the user-approved
tag/Release step.

## [Unreleased]

### Changed

- Goal 20 Part K9: `cadr-cli` 54 rewrite files share one
  owner each (flag table, hotkeys rows, OSC splice, gutter
  walk, `:component` input, llama `:manual`, installer
  `GIT:` case, optional-integer JSON null). Selectors not
  merged. FiveAM 18841 → 18880.

- Goal 20 Part K8: `cadr-tui` 29 rewrite files share one
  owner each (char/string walks, rebuild key dispatch,
  layout vectors, compiled scanners). Generated
  `mermaid/width-data.lisp` untouched. FiveAM 18768 → 18841.

- Goal 20 Part K7: `cadr-ai` 28 rewrite files share one
  owner each (device parse, reserved keys, PKCE login,
  stream blocks, runtime error wrap). Generated catalogs
  untouched. FiveAM 18748 → 18768.

- Docs: live Slynk is first on a running cadr, not a last resort after
  guessing (`development-policy` §6.1, `AGENTS.md`). Load-and-probe is
  not a substitute. Do not add restarts on pairable user-visible paths
  to look native.

- Goal 20 Part K6 follow-up: `with-present` owns every schema
  present-p bind; `call-signaled-operation` owns abort/classify
  for remove and temps. FiveAM 18738 → 18748.

- Goal 20 Part K6: `cadr-agent` 23 rewrite files share one
  owner each (queue slots, when-present, authoring macros,
  message generic, tail pointer). FiveAM 18725 → 18738.

- CI runs only on `workflow_dispatch`. Push and pull-request
  triggers are gone. Daily path is local `test-cl.sh` / `verify.sh`.
  FiveAM 18722 → 18725.

- Goal 20 Part K5: `cadr-evals` flag prefix, harness merge,
  message tail, reporter push, JSON string accessor, and
  one-argument signed format each have one owner.
  FiveAM 18699 → 18722.

- Goal 20 Part K4: `cadr-server` instance lookup, IPC client
  wrap, instance upsert, and Radius heartbeat share one owner
  each. FiveAM 18691 → 18699.

- Goal 20 Part K3: `cadr-protocol` encoder limits live on
  `cbor-writer`, frame decode uses a cursor, optional schema
  fields share `optional-field-p`. FiveAM 18683 → 18691.

- Goal 20 Part K2: `cadr-storage` stays `no-rewrite` (I verdicts
  undrifted). Theme index recount 197 → 198.

- Default live vehicle is OpenCode Go `mimo-v2.5`. `prepare-opencode-go-credential`
  accepts `auth.json` or `OPENCODE_API_KEY`. A default live item locks a
  nonempty thinking stream. Native DeepSeek FiveAM items still skip
  without `DEEPSEEK_API_KEY`.

- `unix-milliseconds` reads real milliseconds from
  `sb-ext:get-time-of-day`. The old `get-universal-time * 1000` path
  quantized every timestamp and ID to a whole second. Matches
  baseline `Date.now()`. FiveAM 18670 → 18673.

- Statistical liveness default path is documented as the P0-4 silence
  lock only (`liveness-ttt-agent-turn`). The booked table is a local
  `--all` instrument and does not enter CI (board 2026-08-17 A).

- Healed two source-parity mapping positions after the unused-helper
  deletions (`credential-for-print` 192→183,
  `render-truncated-text` 1524→1514). Verdicts and key set unchanged.

- Goal 20: model and session selectors cache filter and haystack
  work across frames. Fuzzy matching downcases each candidate once
  per filter instead of once per token.

- Provider SSE reducers append stream text, thinking, signatures, and
  partial tool JSON with an amortized-linear buffer instead of
  concatenating the whole prefix on every delta. Tool-argument JSON is
  parsed when the block ends, not on each fragment.

- Goal 20 Part O: `parse-json-source` copies unescaped strings from the
  source window and inlines peek/take. Escaped strings still decode
  into a fill-pointer buffer. Enforced paired-path `journal_read`
  5.42× → 3.92× and `session_load` 6.71× → 4.48×.

- Goal 20 Part O: `make-session-entry-id` seeds one random state per
  image instead of calling `make-random-state` on every attempt, which
  dominated `journal_append`.

- Goal 18 Part L: re-anchored the fixed pi baseline to v0.84.1.
  cadr 0.2.0 · aligned with pi v0.84.2 (+0, 914cf1472).  `--alt` is replaced
  by `--tui-mode regular|fullscreen` with the baseline diagnostics; the
  `tuiMode`, `fullscreenScrollbar`, and `markdown.mermaid` settings are
  honored; alt-screen navigation defaults moved to the baseline's
  unshifted keys with new half-page and prompt-jump actions plus
  editor prompt-history actions; `scrollbarThumb` joins the theme
  tokens; baseten and qwen-token-plan-individual providers registered
  with the regenerated 0.84.1 model catalog; child processes learn
  `CADR_CODING_AGENT=true` and `AI_AGENT=cadr`.

- Aligned `--resume` with the baseline (goal 18 adjudication): the flag
  no longer consumes a session id (`--session <id>` remains the exact-id
  path); a following token is a prompt message, matching baseline
  args.ts.  Bare `--resume`/`-r` now opens the baseline pre-TUI session
  picker (cli/session-picker.ts) instead of silently resuming the latest
  session: current-folder scope with Tab to all sessions, lazy all-scope
  load, search/sort/name/path toggles, delete confirmation, and the
  baseline cancel (dim "No session selected", exit 0) and interrupt
  (silent exit 0) paths.

- User keybindings now load from `~/.cadr/agent/keybindings.json`
  (baseline KeybindingsManager.create), coexisting with the settings.json
  `keybindings` key with the file taking precedence; legacy names
  migrate identically, and a malformed file falls back to the settings
  value like the baseline loadRawConfig.

- Bare-environment startup now keeps the baseline no-model sentinel
  instead of an openai default: the footer reads "no-model" with a
  0-token context window, sending fails with the baseline
  NoModelSelected guidance before any append, manual /compact fails with
  the baseline compaction event pair, and non-interactive modes exit 1
  with the red NoModelsAvailable text (baseline main.ts:852-854).

- Aligned the user-level layout with the baseline: agent data (settings,
  auth, models, sessions, themes, prompts, tools, bin, extensions, and
  crash logs) now lives in `~/.cadr/agent/` instead of flat `~/.cadr/`,
  with `CADR_CODING_AGENT_DIR` as the override; `~/.cadr/server/` stays at
  the home root.  Startup automatically migrates a pre-agent-layer flat
  layout by renaming the residents (preserving the `0600` auth mode),
  refuses to choose when both layouts hold data, and skips when the
  override is set.  All path decisions now derive from a single owner in
  `cadr-core`, enforced by the code-organization gate.

### Added

- P0-2 / P0-3 request-render pairing: timer ticks share
  `snake-component-advance` / `space-invaders-advance` (baseline
  snake.ts:90-97, space-invaders.ts:144-151). User-input sites stay
  on `tui-dispatch-event` (root.lisp:207-208). Behavior tests now
  assert the timer requested a frame. Gate-validity in
  `docs/acceptance/goal-v20-p0-2-request-render.md`.
  FiveAM 18668 → 18670.

- Theme index in `docs/test-matrix.md`: every `test/**/*.lisp` and
  `test/**/*.py` file (197) under the nine FiveAM systems plus live
  runner, Python gates, and fixtures. Anchor unchanged.

- Statistical liveness stage (goal 20 12E-1): booked per-scenario
  `N_i` from the 2026-08-15 measurement, `verify.sh` checks the
  silence-injection scenario n=3, and a failure prints the full
  gap list. Outside `render-diff.py gate --tier core`.
  FiveAM anchor 18633 → 18636.

### Removed

- Goal 20 sb-cover third-tier: deleted six unused helpers
  (`auth-credential-value`, `content-text-blocks`, `gm-to-ansi`,
  `markdown-ordered-prefix-end`, `package-source-with-ref`,
  `trailing-lines`). Each had no caller; live paths already own
  the work. Denominator 122640 → 122575.

### Fixed

- Busy `send-message` with `trigger-turn` steers the running agent
  (baseline `isStreaming` + `triggerTurn`). Tic-tac-toe no longer
  throws DELIVER-AS or leaves a half-played board; tool lines
  render `move_down` / `play` instead of raw JSON.
  FiveAM 18880 → 18925.

- Statistical liveness runs from the git checkout, not the isolated
  tar copy. render-diff capture needs `git -C <repo>`; the isolated
  tree has no `.git` and CI died in 1s with "fatal: not a git
  repository". Thresholds unchanged. FiveAM 18665 → 18668.

- Completions streams read the first nonempty of
  `reasoning_content`, `reasoning`, and `reasoning_text`
  (baseline openai-completions.ts:489-509). Dual emit does not
  double the thinking block. OpenCode Go `reasoning` uses the
  `reasoning_content` signature so history replay matches.
  FiveAM 18657 → 18665.

- Settings-list space matches the baseline: activate only when
  search is off or the query is empty; otherwise space and paste
  keep spaces in the search box (baseline settings-list.ts:187).
  FiveAM 18652 → 18657.

- `write-websocket-frame` now calls `write-websocket-length` for
  the 16-bit and 64-bit extended fields. The helper no longer
  writes the first length byte, so a masked 16-bit frame cannot
  be mistaken for a 64-bit form. Not a write-side pair of the
  64-bit read bug. FiveAM 18640 → 18652.

- Wire `oauth-selector-handle-raw-input` into the overlay
  raw-input dispatch, matching the other selectors. Paste and
  custom keybindings now reach the OAuth selector. FiveAM
  18636 → 18640.

- Re-pin `example-commands/narrow/commands-path` cadr
  `screenSha256` after wrapped `<CADR_ROOT>` path join. Baseline-side
  and wide SHAs unchanged. Local official core gate EXIT:0
  (120/122). Does not declare the CI differential green.

- Render-diff `<CADR_ROOT>` paths absorb a hard wrap and the
  continuation-line pad so CI and local wrap points converge.
  Does not re-pin I04 pairs in this change.

- RPC `steer` / `follow_up` and busy `prompt` +
  `streamingBehavior` run `:input` hooks off the JSONL reader,
  matching a new prompt. A second hook invocation can no longer
  block confirm/editor answers. Unconditional `rpc-ui-diag`
  prints removed from the RPC UI product path.

- Booked the unpaired-path denominator at 122613 after completions
  reasoning-field coverage.

- Booked the unpaired-path denominator at 122586 after aligning
  settings-list space with the baseline.

- Booked the unpaired-path denominator at 122575 after deleting
  six unused sb-cover A-class helpers.

- Booked the unpaired-path denominator at 122640 after wiring
  the WebSocket extended-length helper.

- Booked the unpaired-path denominator at 122638 after wiring
  OAuth selector raw-input.

- Booked the unpaired-path denominator at 122632 after moving
  RPC steer/follow-up input hooks off the JSONL reader.

- RPC process-modes UI path prints hook/dispatch/client
  diagnostics for confirm and editor so a missing pair can be
  located on the next CI run. Required method set unchanged.

- Re-pin `fatal-crash/narrow/fatal-crash` baseline-side
  `screenSha256` after the wrapped `node:internal` module collapse.
  cadr and wide SHAs unchanged. Does not declare the render
  differential green.

- Render-diff `node:internal/<module>:N:M` collapse now allows a
  hard wrap inside the module name (narrow `processTimers` splits
  `timers` so `521:7` / `523:7` no longer leak). Does not re-pin
  I04 pairs in this change.

- Re-pin `example-commands/{wide,narrow}/commands-path` cadr
  `screenSha256` after checkout root collapsed to `<CADR_ROOT>`.
  Baseline-side SHAs unchanged. Does not declare the render
  differential green.

- Recorded the 2026-08-17 role rulings in the adjudication log and
  advisor playbook (executor never writes a ruling; advisor is
  read-only on shared CI state; differential pins are local truth).

- After a bash tool completes, the settle window stays open through the
  following assistant message and its text deltas (user messages and
  the next tool still lift it), so a wall-clock tick during persist or
  the short "observed" text cannot paint Took+loader and ratchet the
  previous Took line off the render-diff viewport.

- RPC `get_state` now emits JSON `null` for a missing model instead of
  raising on the no-model sentinel. cadr-server spawn retries
  `get_state` until the child reports a non-empty `sessionId` before
  marking the instance online.

- RPC `get_state` omits the `model` key when no model is selected,
  matching baseline `JSON.stringify` of an undefined optional field.

- Render-diff semantic screens collapse `node:internal/<module>:N:M`
  line numbers to `<NODE_LINE>:<NODE_COLUMN>` so Node patch releases
  do not move fatal-crash I04 pairs.

- Re-pin `fatal-crash/{wide,narrow}/fatal-crash` baseline-side
  `screenSha256` after the node:internal collapse. cadr SHAs
  unchanged.

- Goal 20 P0-4: extension `send-message` with trigger-turn no longer
  runs the agent turn on the TUI input thread, so streaming text, tool
  blocks, and the working indicator can paint during the turn. The
  tic-tac-toe move custom message uses the compact banner renderer
  instead of the raw board content.

- WebSocket frames with payload length 65536 or more now read all eight
  length octets (the 64-bit branch used to skip the first), and
  fragmented messages are assembled until FIN. Codex WebSocket debug
  stats take the cache mutex on write as well as read.
  `wss://`/`ws://` URLs convert to `https://`/`http://` for the HTTP
  upgrade.

- `parse-json` signals `json-parse-error` instead of relabeling every
  JSON failure as `sse-protocol-error`. HTTP `request-json` maps a
  damaged body to `transport-error`; streaming JSON repair catches
  `json-parse-error`.

- Startup loaded-resource blocks now follow the baseline (goal 18 Part H):
  section order Context -> Skills -> Prompts -> Extensions -> Themes with
  the baseline labels, locale-compare sorting (Context keeps insertion
  order), banner/sections split at the baseline padding boundary, and the
  three warning blocks ([Skill conflicts], [Prompt conflicts],
  [Extension issues]) with collision groups and severity colors.  Resource
  name collisions keep the baseline winner (project scope) but now record
  the collision diagnostic instead of dropping the loser silently.  A new
  `startup-resources` render-diff scenario captures the populated startup
  in compact and ctrl+o-expanded form on both terminal sizes while the
  empty startup scenarios stay pinned, and the state-coverage sweep is
  documented in `docs/goal18-startup-resources-audit.md`.

- Render-diff harness hygiene (goal 18 Part G): a single-owned sweeper now
  removes tmux `cadr-rd-*` servers whose owning run died and stale
  `/tmp/cadr-render-screen-*` replay dirs at every CLI start, and the
  tmux_screen failure branch is regression-tested to kill its server.
  The two stray `/export` HTML artifacts at the repository root are covered
  by the existing `cadr-*.html` gitignore rule (mirroring the
  baseline's export-artifact ignore rule).

### Added

- Goal 20: `docs/profiling.md` is the standing `sb-sprof` runbook.
  `scripts/goal20-profile.sh` is the driver; neither is a gate.

- Goal 20 Part H: `scripts/goal20-unpaired-paths.py` books which
  `src/**/*.lisp` files are paired, unpairable, or still uncovered.
  The report is section 6 of `docs/acceptance/goal-v20-part-h.md`.

- Goal 20 Part O: `scripts/goal20-profile.sh` captures `sb-sprof` for
  paired paths that still miss 1.0×; the report is
  `docs/benchmarks/goal20-part-o-remaining-sprof.md`.

- Goal 20 Part B: paired-path ratios and FiveAM check counts are written by
  scripts into `docs/performance.md` and the `GOAL20_TEST_CHECKS` comment in
  `docs/test-matrix.md`. `scripts/record-paired-paths.py` books a run from
  the paired-path summary; `scripts/write-test-check-anchor.py` fails
  `test-cl.sh` when the committed check count drifted.

- Goal 18 L2.1: the fixed pi baseline anchor now has a single owner — the
  `BASELINE` file at the repository root (commit, release tag, distance).
  The product release identity derives from it at load time, the diff and
  verify scripts read it instead of embedded literals, a new
  `baseline anchor consistency` stage in `verify.sh` fails when any
  operational reference disagrees, and `scripts/set-baseline.sh` performs
  the mechanical rewrite on upgrade.

- Goal 18 Part L preparation: `scripts/enumerate-baseline-diff.py`
  mechanically enumerates every named user-observable or contract set
  between two baseline commits (flags, settings keys, events, providers,
  env vars, theme tokens, error classes, RPC methods, exit codes, session
  format, ...).  Its first run caught four classes the hand-maintained
  list missed; the v0.84.1 enumeration result is recorded in
  `docs/source-parity-upgrade.md`.

- Goal 18 I7 tail and Part J/K: the startup content migrations are ported
  (oauth.json/settings apiKeys into auth.json with 0600 preserved,
  agent-root sessions into sessions/, managed binaries tools/ -> bin/,
  commands/ -> prompts/ for the global and project roots, and the
  deprecated hooks//tools/ warnings with the interactive any-key pause,
  in the baseline startup order); `--list-models` prints the baseline
  auth-filtered six-column table with fuzzy filtering and the corrupt
  models.json warning envelope; a broken extension is now a fatal
  startup error with the baseline reportDiagnostics lines and the
  `cadr -ne` hint; extension shortcut conflicts follow the baseline
  getShortcuts semantics (reserved keys skip, later registration wins,
  warnings land in the [Extension issues] block); unreadable
  --system-prompt/@file paths produce the baseline Node-style error
  wording instead of raw conditions; the legacy keybinding-name
  migration covers the full 62-name baseline table; the system prompt's
  documentation paths now resolve to the real repository docs instead of
  a hardcoded /usr/local prefix; the twelve user docs the product text
  references (the eleven system-prompt documents plus providers.md) now
  exist and every docs//examples/ reference in product text is
  gate-enforced to resolve (Part J); and the seven coding tools'
  model-visible contract (description, full parameter schema with
  per-property descriptions, prompt snippets) is locked against a
  fixture the gate regenerates from the fixed baseline at capture time
  (Part K — this also renamed grep's `ignore_case` to the baseline
  `ignoreCase` and dropped a non-baseline `minItems` from edit).

- Goal 18 I2 mechanically derived coverage: the login dialog's eight
  `show*` forms and the 33-leaf ExtensionEvent union are extracted from
  the baseline commit's git objects at analysis time and drift-checked
  against the interface inventory, with each dialog form mapped to a
  scenario checkpoint or the construction suite; the unmodeled-sink
  reverse scan (I7.3) fails the gate on any output call with fixed text
  that no inventory site covers, with the 14 current candidates under
  per-site reviewed verdicts; and REQUIRED_COVERAGE now locks the full
  declared tag set so no scenario or tag can silently disappear.  The
  diff report is `docs/goal18-i2-derived-coverage.md`; ten defensive or
  privilege-dependent branches await exemption adjudication in
  `docs/proposals/goal18-i7-tail-exemptions.md`.

- Goal 18 Part I gate hardening and capability completion: the reused
  pi baseline checkout is now verified blob-for-blob against the
  repository's immutable object store before any differential run (I5);
  `verify-release.sh` can no longer exit 0 with live stages skipped —
  `CADR_RELEASE_GATE=1` turns a live SKIP into a named failure while
  everyday `verify.sh` keeps the skip behavior (I6); the presentation
  ledger's scale numbers are machine-reconciled by a FiveAM gate that
  recomputes them from the real artifacts (I4); the four baseline
  session keybinding actions `app.session.{new,tree,fork,resume}` are
  registered unbound, bindable via settings.json, and dispatch to the
  same handlers as their slash commands (I7); and the bundled llama
  extension gained the full baseline `ui.ts` surface — context-size
  labels, model descriptions, compact counts, the framed model selector,
  live Hugging Face search with debounce, and the cancellable progress
  view over a persistent custom component with a render channel (I8).

- Goal 18 Part E/F audit deliverables: the intentional-difference ledger grew
  from 72 to 77 rows after recasting five component-export rows
  (extension/show-images/skill-invocation/theme/thinking selectors) with
  baseline-consumption evidence, and the `settings-state-sweep` render-diff
  scenario now enables terminal image support so the `Show images` and
  `Image width` rows are captured and pinned on both sides.  The full audit
  report lives in `docs/goal18-part-e-audit.md`, and the package-boundary map
  in `docs/source-parity.md` §1a now records the `cadr-core` path-owner and
  the `agent/src/harness/tools/` routing refinement.

- Implemented the baseline `/debug` command and its `shift+ctrl+d` binding:
  the terminal's rendered lines (with visible widths) and the agent messages
  (JSONL) are written to `~/.cadr/agent/cadr-debug.log` (I04 filename), and
  the chat confirms with the baseline accent "✓ Debug log written" + muted
  path block.  Recorded that the baseline's `getToolsDir` is dead code (zero
  callers) and is deliberately not implemented.

- Completed the login dialog's baseline surface: auth selects now borrow the
  screen and restore the dialog (the Radius/OpenAI method choice no longer
  strands later auth events into the transcript), text/secret prompts render
  through the dialog's prompt form, and the info (message + links) and
  details forms exist.  Bedrock and Vertex API key logins run their baseline
  structured flows (method select, per-method prompts, info notice with
  links) through the dialog, and the login completion messages follow the
  baseline "Logged in to … Credentials saved to …" text.  New render-diff
  scenarios cover the manual-code and browser-callback flows end to end —
  cancel with post-cancel probes and a completion path each.

- Added the fourth parity ledger for visible presentation semantics, including
  production probes for all 55 theme tokens and machine-checked ledger totals.
- Added a self-contained baseline-compatible session HTML exporter with the
  approved vendored Marked and Highlight.js browser assets.

### Changed

- Reduced alternate-screen continuous-input p99 from 52ms to 8ms at the
  5,000-entry stress tier while preserving the complete logical document.
- Replaced the OAuth callback page's interim block-C mark with Cadr's
  single-path square-grid cons-cell identity.
- Changed `/share` to use `https://cadr.dev/session/` by default, with
  `CADR_SHARE_VIEWER_URL` as the sole environment override.
- Replaced the remaining 14 production `PI_*` environment names with their
  `CADR_*` equivalents without legacy aliases.

### Fixed

- Fixed ESC-cancelling an xAI, Kimi, GitHub Copilot, or Radius device-code
  login never reaching the shared device poller's cancellation flag, so the
  login worker ran until token expiry and every later message stalled in the
  Steering queue; the flows now poll through `poll-device-authorization`'s
  `cancelled-p` like the OpenAI Codex route, and each cancel-path render-diff
  scenario ends with a post-cancel message exchange.
  Attribution (goal 18 A4.5): the mechanism — `busy-p` cleared only when the
  login worker ends, with ESC setting flags but never guaranteeing that end —
  predates the goal 17 login-dialog rework (74fe2c0b8); the rework exposed it
  by giving ESC a dialog-closing path that made "cancelled UI, living worker"
  reachable.  It is not a goal 17 regression.
- Cancelling OpenAI or Anthropic login now stops the loopback/manual workers,
  releases the listener, clears the working state, and returns to the editor.
- Interactive cleanup now bounds every background-thread join and forcibly
  stops an unresponsive worker instead of deadlocking exit.
- `/export` now reports the baseline-aligned bare output filename.
- Fixed automatic version checks comparing upstream pi `0.83.x` releases with
  Cadr `0.2.x`; checks are now disabled unless `CADR_VERSION_CHECK_URL` names a
  Cadr-compatible endpoint.
- Fixed outbound provider attribution, changelog links, browser storage,
  temporary files, synthetic tool IDs, examples, and Radius diagnostics that
  still presented Cadr as pi.

### Security

- Unhandled conditions now use a sanitized fatal boundary: terminal output
  contains no backtrace or object dump, diagnostics are exact/pattern redacted
  into mode-0600 crash logs, and credential-bearing objects print redacted.

## [0.2.0] - 2026-08-01

**cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)**

### Added

- Goal 1: established the Common Lisp/ASDF architecture and the provider,
  streaming, message, tool, usage, and error foundations.
- Goal 2: implemented the agent loop, lifecycle event spine, tool execution,
  retry/abort handling, and session state.
- Goal 3: added the native CLI, REPL, built-in coding tools, provider/model
  configuration, system prompt, and recorded provider parity fixtures.
- Goal 4: added JSONL persistence, continuation, retry policy, native image
  builds, migration acceptance, and executable smoke coverage.
- Goal 5: delivered the pure Common Lisp TUI, Unicode/grapheme-safe editor,
  overlays, images, resize handling, differential rendering, and terminal
  lifecycle recovery.
- Goal 6: expanded provider/catalog, OAuth, image, model-runtime, extension,
  package, session-tree, compaction, and RPC compatibility with original pi.
- Goal 7: completed the audited extension lifecycle/UI/runtime API, session and
  queue surfaces, print/JSON/RPC modes, SQLite storage, Unix-socket server, and
  eval harnesses.
- Goal 8: closed the exhaustive TypeScript test parity ledger, added the CBOR
  protocol package, completed the dependency audit, and separated deterministic
  and credential-gated live FiveAM entry points.
- Goal 9: upgraded the behavioral baseline to
  `earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`, automated the
  former manual acceptance paths, completed mechanical/runtime TUI parity,
  identified OpenAI traffic as `originator=cadr`, and added the local
  deterministic/build/process/PTY/live verification gate.
- Goal 10: established the private backup and real CI gate, retained the
  newer-than-tag baseline by explicit no-op adjudication, and added the
  approved Lisp-native tool restarts plus opt-in loopback Slynk REPL.
- Goal 11: added deterministic performance, allocation, cold-start, long-run
  memory/resource, and large-session latency release gates.

### Changed

- Renamed the implementation, packages, executable, configuration directory,
  and environment namespace from the migration-era `pi-cl` names to Cadr while
  preserving the historical reference and migration path.
- Aligned the security model with original pi: tools execute directly by
  default, optional approval is an extension hook, and containerization remains
  the strong isolation boundary.
- Released version `0.2.0` from the single `version.sexp` production source;
  the CLI identity also records alignment with pi `v0.83.0` plus 38 commits at
  `74caa2649`.
- Removed the completed `0.1.x` fallback for `PI_CL_PROVIDER`, `PI_CL_MODEL`,
  and `PI_CL_BASE_URL`; use the `CADR_*` names.

### Fixed

- Corrected provider stream text preservation, OpenAI Responses reasoning
  summaries, unknown-model thinking capabilities, OAuth provider identity, and
  model-facing tool result text/counting semantics.
- Corrected selector empty/wrap boundaries, CJK/emoji editing, streamed TUI
  output, tool error states, Markdown/code rendering, overlay copy/layout,
  footer model refresh, terminal positioning, and PTY restoration.
- Removed test timing races, OAuth refresh-token copy pollution, shell-smoke
  credential rewriting, wrapper stderr leakage, and user-settings coupling from
  deterministic/live evidence.

### Security

- OAuth credentials use a single `~/.cadr/auth.json` store with atomic writes,
  mode `0600`, refresh locking, provider-consistent identities, and redaction
  from errors, sessions, transport logs, and reports.
- Third-party dependencies are frozen by the audited allowlist; any new direct
  or transitive dependency blocks implementation until explicit pre-approval.
- Slynk is default-off, loopback-only, explicitly enabled, and documented as
  an arbitrary-evaluation debugging service rather than a sandbox.
