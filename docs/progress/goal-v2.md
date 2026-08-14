# GOAL v2: full functional alignment of pi-cl and a pure-Lisp ecosystem

## 0. Relationship to v1

This goal continues on top of the v1 deliverables (the three systems pi-ai / pi-agent / pi-cli, 249 tests all green) and does not overturn the existing architecture. Every discipline of v1 remains in force: tests first, phase gates, a runnable product at every phase, cross-implementation comparison verification, honest reporting. docs/architecture.md is updated in step with every phase.

## 1. Overall goal

Ultimately deliver a Common Lisp implementation whose **functional semantics are fully aligned with the baseline pi** (earendil-works/pi, reusing the audit commit fixed in v1), and establish one ecosystem principle:

> **The extension ecosystem is entirely Lisp's.** Extensions, skills, and prompt templates are all written and loaded in Common Lisp. Loading the baseline's TS extensions is not pursued, and no JS runtime is embedded. The "capability" of the baseline extension ecosystem must be aligned (it can do exactly as many things), the "format" is incompatible (this is a settled decision of the language migration, written into the README differences chapter).

## 2. In-house implementation and dependency principles (important)

1. **In-house by default**: for everything that belongs to protocol parsing, algorithms, rendering, or data structures, implement it in pure Lisp first, replacing the third-party libraries introduced in v1 step by step. For each library replaced, the in-house implementation must first pass all the tests corresponding to that library's original responsibilities, then the switch is made, and finally it is removed from the .asd dependencies.
2. **The only exception — TLS**: the encryption layer of HTTPS may bind the system OpenSSL through FFI (cl+ssl or a self-written thin binding). Implementing cryptography in-house is forbidden. The HTTP client itself (connection management, writing requests out, response parsing, chunked encoding, streaming reads) is to be built in-house, so that dexador can be removed.
3. Every in-house module is given a separate test suite, without exception, and must pass all the regression tests already present in v1 (especially the SSE UTF-8 splitting fixture).
4. The replacement order runs from lower to higher risk: JSON → CLI argument parsing → the subset used in glob/regex → HTTP client. Implementing cl-ppcre's complete regular-expression engine in-house is extremely costly, so it may be kept until last, as a separate optional phase.
5. SBCL's own facilities (sb-thread, sb-bsd-sockets, uiop/asdf) do not count as third-party dependencies and are encouraged.

## 3. Functional scope: the full list for aligning with the baseline

The following is arranged by phase. Every item takes the corresponding baseline source as its behavioral reference, and differences must be recorded in the README's difference list.

### Phase 5: provider completeness
- Add an **OpenAI Chat Completions protocol adapter** (/v1/chat/completions, including streaming); this is the common protocol for connecting to DeepSeek, open-source inference services (vLLM, Ollama), and most other vendors.
- Establish a **provider registry**: each provider = protocol + base-url + authentication method + default model + key environment variable. Built in: anthropic, openai, google, deepseek (over the Anthropic-compatible path or Chat Completions, whichever proves better after testing at implementation time), ollama (local).
- Support `--base-url` / configuration-file override of any provider's address.
- Static model catalog: a built-in model metadata table (context window, whether tools / chain of thought are supported), with an update script provided to refresh it from each vendor's public data; includes price data and usage cost computation (aligned with the baseline's usage display).
- Image input: the message model gains image content (base64), and each of the three protocols encodes it correctly; a provider that does not support images reports an explicit error instead of silently dropping it.
- **OAuth authentication support**:
  - Provider authentication is abstracted into the two methods `api-key | oauth`; the protocol adapter is unchanged, only the construction of the authentication header differs.
  - Implement the standard PKCE authorization flow: a local one-shot callback HTTP service (built in-house in pure Lisp, conforming to the in-house principle of section 2), opening the browser to authorize, exchanging the code for a token. Delivered as the `/login <provider>` and `/logout <provider>` commands.
  - Tokens are stored in `~/.pi-cl/auth.json`, with file permissions forced to 0600; when the access token expires it is silently renewed with the refresh token, and the renewal takes a lock to prevent concurrent requests from refreshing repeatedly; tokens are subject to exactly the same redaction red line as API keys (not into logs, not into condition reports, not into session files).
  - The first priority is **OpenAI Codex OAuth** (reusing the Responses API protocol path already implemented in v1); the authorization endpoint, client ID, and request-header construction are governed by the actual behavior of the baseline pi implementation at the fixed reference commit, not invented here.
  - Anthropic OAuth (Claude subscription) implements the same interface structure but is marked **unverified** (no subscription account available to test with), noted truthfully in the README.
  - Note in the README difference list: subscription OAuth channels are usually restricted to official clients by each vendor's terms, and the terms risk of a third-party tool using such a channel is borne by the user.

### Phase 6: session-system alignment
- Sessions are upgraded from linear to a **tree**: every message carries an id and a parent-id, and forking from any historical node to continue is supported (aligned with the baseline branch semantics). The JSONL format is upgraded to v2, a v1 → v2 migration is provided, and old sessions can be read without loss.
- **Session compaction**: when the context approaches the model window's upper limit, earlier messages are summarized and compacted (the summary is produced by calling the current model), and the reference relationship between the compacted summary node and the original nodes is retained, so it remains traceable.
- Session listing, switching, `--resume <id>`, HTML export (in-house minimal HTML generation, no template library needed).

### Phase 7: the Lisp extension system (the core of this goal)
- An extension = one `.lisp` file or one directory containing `extension.lisp`, entering a separate package through a controlled `load`.
- The extension API (exported from pi-agent, kept stable):
  - `define-tool`: register a new tool (name, description, JSON Schema, execution function, execution mode)
  - `define-command`: register a REPL slash command (such as /compact, /model)
  - `define-event-hook`: subscribe to agent lifecycle events (turn start/end, before and after a tool call); a hook may intercept, rewrite, or append messages — aligned with the baseline extensions' ability to intervene in agent behavior
  - `define-prompt-template`: a named prompt template, expanded inside the REPL as /name
- Load sources and priority: `~/.pi-cl/extensions/` (global), `./.pi-cl/extensions/` (project level, overriding a global item of the same name), `--extension <path>` (one-off).
- **Hot reload**: the `/reload` command re-loads all extensions; any condition during extension loading or execution is caught, the error is reported and the agent is kept alive; an extension error must never be allowed to break through the main loop.
- **Self-extension capability acceptance**: within a single session, the agent must be able to write out a new extension file with its own write tool, /reload, and then successfully invoke this new tool within the same session. This is the core semantics of "self-extensible" and is a hard acceptance item.
- Security: an extension is arbitrary code, and loading it executes it. The first time an extension at a given path is loaded, show the user the path and require confirmation (--yolo skips it); this applies to the project-level extension directory in particular (so that cloning a malicious repository is not itself enough to be compromised).
- Skills / package installation (pulling an extension directory from a git URL into the global extension directory) is built on the same mechanism, and `/install <git-url>` is implemented as a built-in command.

### Phase 8: TUI (in-house, aligned with pi-tui)
- A differentially rendered terminal UI implemented in pure Lisp: ANSI escape sequence output, terminal size detection and resize handling, wide characters (CJK/emoji measured by Unicode East Asian Width), a per-line diff that repaints only the changed regions.
- Components: a multi-line editor input box (cursor movement, history, paste), a streaming markdown rendering text area, collapsible tool-call blocks, a status bar (model, token usage, cost), a selection list (model/session selection).
- Entering/leaving raw terminal mode must be exception-safe: the terminal state must be restored under any condition (unwind-protect covering everything), and a crash must not leave a broken terminal behind.
- REPL mode is kept as the `--no-tui` fallback path; the two frontends share the same agent event stream, and a frontend is only a different renderer of the events — this is an architectural constraint, and the TUI branch is forbidden to carry business logic of its own.
- The TUI test strategy: the rendering layer is snapshot-tested with a "virtual terminal buffer" (input event sequence → assert the buffer contents), without depending on a real TTY; real terminal behavior is covered and recorded by a manual acceptance checklist.

### Phase 9: library replacement and wrap-up
- Execute the in-house replacements in the order of section 2; for each replacement produce a short report (library replaced, in-house module, test evidence, performance comparison).
- Final dependency audit: state the reason for keeping each remaining third-party dependency in the .asd one by one (expected to be only the TLS binding, or explicitly listed deferred items such as cl-ppcre).
- Full regression + all live smokes (using the DeepSeek endpoint) + updating the README and the difference list + the final report.

## 4. Acceptance criteria (new in v2; the v1 criteria remain in force)

1. `--provider deepseek` works out of the box (setting DEEPSEEK_API_KEY is enough); of the two paths, Chat Completions and Anthropic-compatible, at least one has a record-replay E2E.
1a. OAuth: after completing `/login openai` with a real ChatGPT account, the live smoke runs through over the OAuth channel (Responses API) from end to end; the token refresh logic has a record-replay test (expiry → silent renewal → successful request); the check that auth.json's permissions are 0600 is included in the tests; the redaction tests for logs and error output cover the OAuth token.
2. Sessions can be forked: continuing from some historical node produces a new branch, the two branches do not contaminate each other, and both can be restored after a restart.
3. When the context exceeds the limit, automatic compaction happens and the session can continue, and the complete history before compaction is still traceable from the session file.
4. Self-extension acceptance: complete the loop "agent writes an extension → /reload → invokes the new tool" within a single session (once as a faux provider deterministic test and once as a live smoke).
5. When an extension throws any error (tested at load time and at execution time separately) the agent survives and gives a readable error report.
6. Complete one real multi-turn coding task under the TUI; terminal resize and CJK input render correctly; the terminal state is normal after an abnormal exit. Snapshot tests cover the core components.
7. The dependency audit report exists, and dexador, com.inuoe.jzon, and clingon, introduced in v1, have been replaced by in-house implementations and removed.
8. The README difference list completely lists all known differences from the baseline pi (containing at least: the extension language is Lisp, TS extensions are incompatible, and any other behavioral difference).

## 5. Risks and principles

- Once published the extension API is a stable interface; the Phase 7 design must be confirmed by a human before it is implemented (the same as v1's architecture gate).
- The TUI is the largest engineering effort; Phase 8 may be split into sub-phases internally, but every sub-phase must still be runnable.
- If an in-house replacement meets higher-than-expected cost on some item, an application may be made to move that item into the "deferred list" with the reason stated, adjudicated by a human — silently keeping the dependency is not allowed.
- Wherever the baseline behavior is unclear, the actual behavior of the source at the fixed audit commit governs; when uncertain, record it in docs/open-questions.md and pause to ask.
