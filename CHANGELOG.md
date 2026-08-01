# Changelog

All notable changes to Cadr are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project has not
yet cut a Cadr release tag, so completed work remains under `Unreleased`.

## [Unreleased]

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

### Changed

- Renamed the implementation, packages, executable, configuration directory,
  and environment namespace from the migration-era `pi-cl` names to Cadr while
  preserving the historical reference and migration path.
- Aligned the security model with original pi: tools execute directly by
  default, optional approval is an extension hook, and containerization remains
  the strong isolation boundary.
- Centralized the current `0.1.0` development version in `version.sexp`; all
  production version displays and protocol metadata derive from it.

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
