# Changelog

All notable changes to Cadr are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project has not
yet cut a Cadr release tag. The `0.2.0` entry is frozen for the user-approved
tag/Release step.

## [Unreleased]

### Changed

- Aligned the user-level layout with the baseline: agent data (settings,
  auth, models, sessions, themes, prompts, tools, bin, extensions, and
  crash logs) now lives in `~/.cadr/agent/` instead of flat `~/.cadr/`,
  with `CADR_CODING_AGENT_DIR` as the override; `~/.cadr/server/` stays at
  the home root.  Startup automatically migrates a pre-agent-layer flat
  layout by renaming the residents (preserving the `0600` auth mode),
  refuses to choose when both layouts hold data, and skips when the
  override is set.  All path decisions now derive from a single owner in
  `cadr-core`, enforced by the code-organization gate.

### Fixed

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
