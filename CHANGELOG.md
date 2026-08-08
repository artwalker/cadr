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

### Added

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
