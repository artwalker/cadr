# cadr architecture

Status: **v1 Phase 1–4 and v2 Phase 5–9 are implemented; the north-star Wave 2
agent harness, session v3, print/JSON and RPC are complete; the widened stable
extension API has been re-frozen; the baseline's default execution security
model is aligned; the Phase 8 TUI, the Phase 9 dependency closeout and the cadr
naming migration are complete; Goal 8 Wave 5 storage/server/evals are complete
and frozen; Goal 9 re-locked the behavior baseline to `16787ad5b` and completed
Parts A–E; Goal 11 established the second, non-functional acceptance axis and
completed the performance, memory and long-run stability gates; Goal 10 Part D's
approved conditions/restarts and opt-in Slynk are implemented and re-frozen;
Goal 14 completed the tree-wide responsibility split and the duplication-policy
convergence, and established a standing organization gate**

Goal 9 explicitly separated the deterministic and the provider-live FiveAM
gates: ordinary ASDF test systems contain repeatable tests only, and the
separate live systems are reported in full by `scripts/test-live.sh`.

This document is the first deliverable required by `docs/progress/goal-v1.md`,
and was confirmed by a human on 2026-07-30.
If a later implementation changes a public interface, data format or behavioral
constraint stated here, this document must be updated first, and the change must
be explained in the corresponding phase report.

A global constraint was added on 2026-07-30: cadr aligns with the fixed TS
baseline's design philosophy and does not add mechanisms to the core that the
baseline does not have. The default execution model is YOLO; approval is not a
core security boundary, and strong isolation is provided by the user through a
container. Any proposed new mechanism must first be written into
`docs/open-questions.md` and await human adjudication; it must not be
implemented by default. The v1 tool confirmation was removed as a separate task
after Phase 7 completed; the core no longer exports a confirmation callback, and
there is no `--yolo` branch.

## 1. Reference baseline and boundaries

### 1.1 Reference source

- Behavior reference repository: `https://github.com/earendil-works/pi`
- Fixed audit commit: `16787ad5b2dc748047f314ca1bfe7708f30f54f3`
  (`pi v0.87.0 + 38 commits`, 2026-07-30)
- Historical audit anchor:
  `71efc6f0c1909874ec8c944637a9ae7fc0e2d508`; used only for the Goal 4–8
  historical comparison, and no longer participates in current parity verdicts
- Upstream TypeScript HEAD before the migration:
  `e3f6912d49d14b6e6ffe96bb053644922004ecf3`
- The legacy state is preserved in the `pi-mono-legacy` branch reference and in
  archived patches, base point
  `48b9a05f2cfc3f34f749ac4a2d8d17aec0f843a1`; the `/root/projects/pi-mono`
  directory now tracks upstream `main`
- The current cadr tracked tree no longer contains the upstream TypeScript
  implementation; every reference path below means a path inside the fixed audit
  commit. Regenerating a cross-implementation fixture must check out
  `16787ad5b2dc748047f314ca1bfe7708f30f54f3` and pass its path as
  `scripts/export-ts-payloads.ts --reference`; a moving upstream or the tip of
  the legacy branch must not be used instead.

Within the scope of the fixed commit, the primary references are:

- `packages/ai/src/types.ts`
- `packages/ai/src/api/anthropic-messages.ts`
- `packages/ai/src/api/openai-responses.ts`
- `packages/ai/src/api/openai-responses-shared.ts`
- `packages/ai/src/api/google-generative-ai.ts`
- `packages/ai/src/api/google-shared.ts`
- `packages/agent/src/agent-loop.ts`
- `packages/agent/src/agent.ts`
- `packages/agent/src/harness/`
- `packages/coding-agent/src/core/tools/`
- `packages/coding-agent/src/core/session-manager.ts`
- `packages/coding-agent/src/cli/args.ts`
- `packages/coding-agent/src/main.ts`

### 1.2 In scope for v1

- The Anthropic Messages API
- The OpenAI Responses API
- The Google Gemini Generative Language API, with v1 default model
  `gemini-3.6-flash`
- Real non-streaming requests and real SSE streaming requests for all three
- A unified message, tool, usage, stop-reason and error model
- The complete "model response → tool call → tool result → call the model again"
  loop
- JSON Schema tool-argument validation
- `read`, `write`, `edit`, `bash`, `glob`, `grep`
- REPL, multi-turn sessions, JSONL persistence and `--continue`
- As in the baseline, every tool executes directly once schema validation passes
- A Linux x64 / SBCL 2.4+ single-file executable

### 1.3 Out of scope for v1

- A full-screen TUI, image input and image tool results
- An OpenAI Chat Completions compatibility layer; v1 implements the Responses
  API only for OpenAI
- Providers other than Anthropic/OpenAI/Google
- OAuth, cloud-platform proxies, Bedrock, Vertex, WebSocket
- The extension, skill, prompt-template and package installation systems
- Session branching, compaction, HTML export, RPC, Web UI, Slack, pods
- A dynamic model catalog and price computation; only the token usage the
  provider returns is counted

These are explicit product boundaries. Empty shells and fake "to be implemented
later" interfaces must not be passed off as supported features.

### 1.4 Two explicit adjudications

1. `docs/progress/goal-v1.md` requires the tool to be named `glob`, while the
   equivalent tool in the reference commit is named `find`.
   v1 takes `glob` as the public name and aligns the argument and result
   semantics with the reference implementation's `find`:
   `pattern`, optional `path`, optional `limit`, relative-path output and a
   stable truncation notice.
2. The reference implementation's `complete()` can obtain the final message by
   collecting stream events, but `docs/progress/goal-v1.md` explicitly requires
   "non-streaming and streaming requests". The CL layer therefore sends a real
   `stream=false` request, rather than substituting "still streaming internally,
   only the increments are not displayed" for the requirement.

## 2. System layering

The dependency direction is fixed as follows. `cadr-core`, added by Goal 14 B3,
is an internal leaf that every existing system only depends downward on; it
carries no product or provider semantics:

```text
cadr-cli -> cadr-agent -> cadr-ai -> cadr-core
    |             |            |
    +-> cadr-tui -+------------+
    +--------------------------+

cadr-server -> cadr-ai -> cadr-core
cadr-evals  -> cadr-cli -> ... -> cadr-core
```

| TypeScript responsibility | Common Lisp system / package / module | v1 responsibility |
|---|---|---|
| `packages/ai/src/types.ts`, model/provider registry | `cadr-ai` / `cadr-ai` / `types.lisp`, `provider.lisp` | Unified model, message, content block, tool, usage, event |
| Cross-system failure-safety infrastructure | `cadr-core` / `cadr-core` / `threads.lisp`, `cancellation.lisp`, `atomic-file.lisp`, `redacted-print.lisp`, `time.lisp` | Bounded cleanup, cancellation state, atomic replacement, redacted printing and UTC time; no product policy |
| `packages/ai/src/api/*`, the three implementations | `cadr-ai` / `cadr-ai` / `providers/*.lisp` | Request construction, message conversion, non-streaming responses and the SSE reducer |
| `packages/ai/src/utils/event-stream.ts` | `cadr-ai` / `cadr-ai` / `types.lisp`, `provider.lisp` | The synchronous event-callback protocol and final-message collection |
| The provider SDK / fetch boundary | `cadr-ai` / `cadr-ai` / `http.lisp`, `sse.lisp` | In-house HTTP/1.1, OpenSSL TLS, UTF-8 stream reading, generic SSE framing |
| `packages/agent/src/agent-loop.ts` | `cadr-agent` / `cadr-agent` / `loop.lisp` | Turn loop, tool batches, event order, stop conditions |
| `packages/agent/src/agent.ts` | `cadr-agent` / `cadr-agent` / `runtime.lisp` | Mutable state, subscription, busy state, cancellation, prompt entry point |
| `packages/agent/src/harness/types.ts` | `cadr-agent` / `cadr-agent` / `conditions.lisp`, `tool.lisp` | Stable error classification, the tool protocol and execution modes |
| harness / coding-agent session | `cadr-agent` / `cadr-agent` / `session.lisp` | v1 linear JSONL save, load and most-recent-session lookup |
| harness and coding-agent built-in tools | `cadr-cli` / `cadr-cli` / `tools/*.lisp` | The six local coding tools and unified truncation |
| `coding-agent` args/main/system prompt | `cadr-cli` / `cadr-cli` / `config.lisp`, `main.lisp`, `repl.lisp` | Configuration, model selection and the REPL |

Each system exports stable entry points only; provider-private payload types,
transient SSE state and file-tool internal helpers are not exported.

## 3. Directories and ASDF

Implementation directories:

```text
cadr-ai.asd
cadr-core.asd
cadr-agent.asd
cadr-cli.asd
cadr-live-tests.asd
build.lisp
build.sh
src/
  cadr-core/
    package.lisp
    threads.lisp
    cancellation.lisp
    atomic-file.lisp
    redacted-print.lisp
    time.lisp
  cadr-ai/
    package.lisp
    conditions.lisp
    types.lisp
    json.lisp
    http.lisp
    sse.lisp
    provider.lisp
    providers/
      anthropic.lisp
      openai.lisp
      google.lisp
  cadr-agent/
    package.lisp
    conditions.lisp
    schema.lisp
    tool.lisp
    loop.lisp
    runtime.lisp
    session.lisp
  cadr-cli/
    package.lisp
    arguments.lisp
    build-support.lisp
    config.lisp
    truncation.lisp
    extensions.lisp
    interactive/
      transcript.lisp
      status.lisp
      footer.lisp
      theme.lisp
      images.lisp
      clipboard.lisp
      syntax.lisp
      tool-render-session.lisp
    interactive-services.lisp
    tools/
      path.lisp
      read.lisp
      write.lisp
      edit.lisp
      bash.lisp
      glob.lisp
      grep.lisp
    system-prompt.lisp
    repl.lisp
    tui.lisp
    main.lisp
  cadr-tui/
    package.lisp
    unicode.lisp
    fuzzy.lisp
    word-navigation.lisp
    keys.lisp
    keybindings.lisp
    kill-ring.lisp
    undo-stack.lisp
    input.lisp
    stdin-buffer.lisp
    terminal-colors.lisp
    terminal-image.lisp
    overlay.lisp
    autocomplete.lisp
    editor.lisp
    input-component.lisp
    components/
      markdown.lisp
      image.lisp
      tool-block.lisp
      status.lisp
      select-list.lisp
    renderer/
      terminal-protocol.lisp
      virtual-terminal.lisp
      lifecycle-input.lisp
      main-screen.lisp
      alt-screen.lisp
    composition/
      protocol.lisp
      text-box.lisp
      rich-content.lisp
      settings-list.lisp
      loaders.lisp
      root.lisp
    terminal.lisp
test/
  fixtures/
    requests/
    responses/
    sse/
  cadr-ai/
  cadr-agent/
  cadr-cli/
  cadr-tui/
  cadr-live/
scripts/
  export-ts-payloads.ts
  acceptance-smoke.sh
  goal5-manual-tui-smoke.sh
  live-tui-smoke.sh
  migration-smoke.sh
  server-smoke.sh
  test-cl.sh
  test-live.sh
  test-wave2-process-modes.sh
docs/
  architecture.md
  test-matrix.md
  progress/
```

ASDF systems:

- `cadr-core`, `cadr-core/tests`
- `cadr-ai`, `cadr-ai/tests`
- `cadr-agent`, `cadr-agent/tests`
- `cadr-cli`, `cadr-cli/tests`
- `cadr-tui`, `cadr-tui/tests`
- `cadr-ai/live-tests`, `cadr-cli/live-tests`, `cadr-evals/live-tests`
- `cadr-live-tests` (only orchestrates and reports on the live systems above)

`cadr-core`'s exports are for in-repository systems only; they are not part of
Cadr's published extension API. Existing package-local names retain only
policy-free compatibility delegates; the policy for atomic replacement,
credential-safe printing, cancellation and thread cleanup may be defined in that
leaf and nowhere else. `cadr-tui` still does not depend on `cadr-ai`, so Goal 14
reversed no existing system edge.

Production dependencies after Phase 9:

| Library | Purpose | Reason for the choice |
|---|---|---|
| `cl+ssl` | HTTPS TLS | The first registered in-house exception; binds the system OpenSSL rather than writing cryptography |
| `cl-sqlite` (ASDF `sqlite`) | The session storage SQLite adapter | The second registered in-house exception; binds the system `libsqlite3` through CFFI, so the project writes its own storage/repository contract instead of rewriting a database engine |
| `cl-ppcre` | `grep`, glob and the JSON Schema `pattern` | A full regular-expression engine is explicitly deferred by `docs/progress/goal-v2.md`; user patterns are not handed to a shell |
| `cl-jpeg`, `png-read` | The JPEG/PNG pixel codecs | A pure-Lisp, replaceable category the user approved before the Goal 8 Part B implementation; adds no system ABI and no security boundary |
| `slynk/mrepl` | The explicit `--slynk` runtime REPL | The "explicitly enabled debugging service" separately approved in Goal 10 Part D; off by default, bound to loopback only, allows arbitrary in-process evaluation, and is emphatically not a security boundary |
| `uiop` / ASDF, `sb-thread`, `sb-bsd-sockets`, `sb-posix` | Paths, processes, threads, sockets, terminal and build | Facilities shipped with SBCL/ASDF; not counted as third-party production dependencies |

`fiveam` exists only in test systems. `babel`, `bordeaux-threads`,
`flexi-streams`, `usocket` and `trivial-gray-streams` are not depended on
directly by production source or by a production system; some of them still
enter the image as Quicklisp transitive dependencies of `cl+ssl` or
`cl-sqlite`. `cl-sqlite` depends directly on `iterate` and CFFI; the CFFI
closure under Linux/SBCL is Alexandria, Babel and trivial-features. The full
attribution is in `docs/dependency-audit.md`, and these transitive items do not
constitute new independent exceptions.
`png-read`'s closure is Babel, Chipz, Iterate; Babel/Iterate already enter the
image through the `cl-sqlite` closure, and Chipz is the only new transitive
system this time. `cl-jpeg` has ASDF dependencies only.
Slynk's exact closure is `slynk/mrepl → slynk → ASDF`; the release build
preloads `slynk/mrepl` only and includes no other contrib. Its load happens in a
fresh, empty temporary `HOME`, so that a build user's `.slynkrc` or
`.slynk.lisp` side effects cannot enter the native image.

Node/Bun are not used, and no provider JavaScript SDK is called. The
implementation uses the official HTTP protocols directly, which makes payload
cross-implementation comparison and raw SSE replay hard requirements.

## 4. Unified data model

`defstruct` represents pure data; CLOS generic functions represent the
polymorphic behavior of providers and tools.

Core objects:

- `model`: `id`, `provider`, `api`, `base-url`, `max-tokens`
- `text-content`, `thinking-content`, `tool-call`
- `user-message`, `assistant-message`, `tool-result-message`
- `usage`: `input`, `output`, `cache-read`, `cache-write`, `total`
- `tool`: `name`, `description`, `parameters`, `execution-mode`, `executor`
- `context`: `system-prompt`, `messages`, `tools`

Unified stop reasons:

- `:stop`
- `:length`
- `:tool-use`
- `:error`
- `:aborted`

Unified stream events:

- `:start`
- `:text-start`, `:text-delta`, `:text-end`
- `:thinking-start`, `:thinking-delta`, `:thinking-end`
- `:tool-call-start`, `:tool-call-delta`, `:tool-call-end`
- `:done`
- `:error`

Every successful stream must have exactly one `:start` and exactly one
terminating event. A failure must not leave the caller waiting for a
terminating event; network, API and parse failures must be normalized into a
final `assistant-message` whose `stop-reason` is `:error` or `:aborted`.

## 5. HTTP, non-streaming and SSE

### 5.1 The HTTP abstraction

`cadr-ai.http` provides two replaceable entry points:

- `request-json`: returns status, headers and parsed JSON
- `request-sse`: returns status and headers, and hands the response body stream
  to an SSE consumer

The default implementation writes the HTTP/1.1 request through
`sb-bsd-sockets` and parses status, headers, content-length, connection-close
and chunked bodies; HTTPS only wraps a layer of `cl+ssl` around the socket.
Tests can either inject recorded fixtures or verify streaming reads over a real
loopback socket. Tests may capture the request object before it is sent, but no
log and no condition report may contain an API key or an Authorization header.

`request-json` uses bounded connect/read timeouts. `request-sse` keeps a bounded
connect timeout, but must pass an explicitly unbounded read timeout
(`read-timeout = NIL`) on the native HTTP request, and must not inherit the
client's short default. A long stretch with no SSE bytes may simply mean the
model is in an extended thinking period; it is not the same as a lost
connection. Cancellation is driven by a user abort, process exit, or a deadline
in the provider/agent layer above. This difference must live in the HTTP
abstraction layer; the three providers must not each override the timeout and
hope for the best.

### 5.2 Generic SSE framing

`cadr-ai.sse` is responsible for the protocol only and understands no provider:

1. Receive chunks as a binary stream, and keep an incomplete character across
   chunks in the UTF-8 decoder.
2. Accept both LF and CRLF.
3. A blank line commits an event.
4. Ignore `:` comments; support `event:`, `data:`, `id:`.
5. Join multiple `data:` lines with newlines, per the specification.
6. Handle correctly the last complete event when no final blank line precedes
   EOF.
7. Do not treat `[DONE]` as JSON; the provider reducer decides whether it is a
   terminating marker.
8. Corrupt JSON, unexpected EOF and HTTP body errors each produce a
   distinguishable condition.

### 5.3 Provider adapters

Every adapter implements four things:

- `build-request`
- `parse-complete-response`
- `reduce-sse-event`
- `map-provider-error`

#### Anthropic

- `POST {base-url}/v1/messages`
- `x-api-key`, `anthropic-version`, `content-type`
- The system prompt is separate from messages
- An assistant tool call maps to `tool_use`
- Consecutive tool results are merged into one user turn
- Handles `message_start`, `content_block_start/delta/stop`,
  `message_delta`, `message_stop`
- Aggregates input/output/cache tokens from start/delta usage

#### OpenAI

- `POST {base-url}/v1/responses`
- Bearer auth
- The system prompt enters `input` as a system/developer message
- Tool definitions use the Responses function-tool structure
- A tool call ID keeps both `call_id` and the item ID, so that a later
  `function_call_output` can be paired
- Handles `response.created`, output items, text deltas, function-argument
  deltas, `response.completed/failed`
- Cached input is deducted from input tokens and counted as `cache-read`

#### Google

- Non-streaming:
  `POST .../models/{model}:generateContent`
- Streaming:
  `POST .../models/{model}:streamGenerateContent?alt=sse`
- The API key is sent through the header/query the provider requires, and does
  not enter logs
- The system prompt maps to `systemInstruction`
- The assistant role maps to `model`
- Tool calls/results map to `functionCall` / `functionResponse`
- Text/thinking/tool-call events are produced from candidate parts
- If the response contains a tool call, the final stop reason is forced to
  `:tool-use`
- The current baseline and default model are fixed to the stable ID Google lists
  officially,
  [`gemini-3.6-flash`](https://ai.google.dev/gemini-api/docs/models/gemini-3.6-flash).
  Google's
  [2026-07-21 release note](https://ai.google.dev/gemini-api/docs/changelog)
  simultaneously deprecates `temperature`, `top_p` and `top_k`; requests to this
  model must not send those fields, even when the caller supplies a generic
  temperature option. Older models keep the existing temperature mapping.

All three adapters must preserve the order in which text and tool calls appear,
and must parse tool arguments incrementally in the stream; only JSON arguments
after `tool-call-end` may enter the execution phase.

## 6. Mapping TS async/Promise onto CL

The network layer and the agent main loop use **synchronous calls plus
incremental callbacks**, rather than creating a background thread per request:

```lisp
(stream-chat provider context
             :on-event #'handle-event)
;; Blocks until :done / :error, but calls back as each delta arrives
```

This is a deliberate structured-synchronous design:

- the REPL must wait for the final result of an agent run anyway;
- same-thread callbacks make message state and terminal output order
  deterministic;
- it is still real streaming, and does not wait for a complete HTTP body;
- there is no need to simulate a JavaScript event loop, and no runaway
  promise/thread is left behind.

`sb-thread` is used only for an independent read-only tool batch within one
assistant message:

- the `:tool-call-before` extension hook and argument validation run in a fixed
  order;
- concurrency happens only when every tool is marked `:parallel`;
- `tool-execution-end` may be emitted in actual completion order;
- tool-result messages must be written back to the context in the call order of
  the assistant message;
- when any tool is marked `:sequential`, the whole batch executes sequentially.

`bash`, `write` and `edit` are always marked `:sequential`, which avoids
file-modification races. The event sink is serialized by a mutex; every thread
must be joined before the run ends, and detached workers are not allowed.

## 7. Condition system and retries

Condition hierarchy:

```text
cadr-error
├── configuration-error
├── transport-error
│   ├── network-error
│   ├── timeout-error
│   ├── request-aborted
│   └── sse-protocol-error
├── api-error
├── schema-validation-error
├── tool-execution-error
├── agent-busy-error
├── agent-turn-limit-error
└── session-error
```

Shared slots:

- a human-readable message
- the original cause, if any
- `retryable-p`

Additional structure:

- `api-error`: provider, HTTP status, provider code, retry-after
- `schema-validation-error`: tool, JSON pointer, validation reason
- `tool-execution-error`: tool, tool-call-id; the specific error category stays
  in the message/cause
- `session-error`: file path, corrupt line number

Handling boundaries:

- Corrupt configuration and corrupt session headers are CLI fatal errors with a
  non-zero exit code.
- A provider failure becomes a final assistant error message.
- An unknown tool, an argument-validation failure, an extension-hook block and a
  tool's own failure all become a `tool-result-message` with `is-error = true`;
  the agent can read the error and correct itself.
- Logs and condition printers redact keys, Authorization and raw sensitive
  headers uniformly.

Phase 4 implements bounded retries:

- network disconnects, 429, and 500/502/503/504 are retryable;
- other 4xx, schema errors and tool errors are not retried;
- at most 2 retries by default (3 requests in total), with 0.25s and 0.5s
  backoff;
- a `Retry-After` in plain numeric-seconds form takes priority over exponential
  backoff, and is capped at 60s;
- SSE may only be retried before the first provider event arrives, and does not
  re-emit the unified `:start`; a failure after events have begun terminates
  directly, which avoids duplicate deltas;
- once the limit is reached, an explicit error message must be produced; the
  loop must not run forever.

## 8. The agent loop

The deterministic flow of a single `prompt`:

1. Reject a concurrent second prompt (`busy`).
2. Append the user message and emit the agent/turn/message lifecycle events.
3. Perform provider message conversion on the context.
4. Call the model in streaming mode and keep updating the current assistant
   message.
5. Persist the final assistant message once the terminating event arrives.
6. If it is `:error` / `:aborted`, end the run.
7. If there are tool calls:
   - never execute on `:length`, because the arguments may be truncated;
   - look up the tool;
   - validate against the JSON Schema;
   - run the `:tool-call-before` extension hooks;
   - re-resolve the tool by its final name and re-validate the final arguments;
   - execute the tool and produce a tool result;
   - run the `:tool-call-after` extension hooks;
   - append all tool results in call order;
   - go back to step 3.
8. With no tool calls, end the turn and the agent run.

The model is allowed to call tools over several consecutive turns by default. A
high but finite internal turn limit (100 by default) prevents a malicious or
runaway provider from looping forever; hitting it returns an explicit error.

## 9. Tool registration, validation and security

### 9.1 Registration and validation

The registry is keyed uniquely by tool name, and a duplicate registration fails
outright. Tool arguments are hash tables produced by the native JSON parser, and
are validated before execution by the native validator in `schema.lisp`. The
validator covers the object/array/scalar constraints, local `$ref`, combination
keywords, dependencies and `pattern` used by the fixed baseline's tool schemas;
an error result contains at least:

- a JSON pointer
- the violated constraint
- the tool name

It does not "guess a field", "auto-correct a type", or pass invalid arguments to
the shell or the filesystem.

### 9.2 Default execution and the isolation boundary

Aligned with baseline pi: a tool executes directly once its final arguments pass
schema validation. The core provides no confirmation dialog, no trust ledger, no
approval callback and no `--yolo` switch, and it does not disguise a cwd path
check as a security sandbox. A user who needs strong isolation should run cadr
in a container, a virtual machine or a restricted user account.

Per-tool approval is implemented with the Phase 7 `:tool-call-before` hook. That
policy belongs to a user extension and does not enter the agent or the CLI core;
the README provides a minimal example.

### 9.3 Tool behavior

| Tool | Key behavior |
|---|---|
| `read` | Relative to cwd or an absolute path; UTF-8; 1-based offset/limit; head truncation at 2000 lines or 50 KiB by default; an out-of-range request is an explicit error |
| `write` | Creates parent directories; UTF-8; full overwrite; writes to the same path are serialized |
| `edit` | One or more exact replacements within one file; every old text must be unique in the original file; all matches are against the original file; overlaps are rejected; a single write-back |
| `bash` | `/bin/bash -lc`; fixed cwd; merges and streams stdout/stderr; returns the exit code; tail truncation at 2000 lines or 50 KiB; on timeout/termination the process group is cleaned up |
| `glob` | Glob pattern, path, limit; recursive; ignores `.git`/`node_modules` by default and honours a parseable `.gitignore`; relative POSIX paths |
| `grep` | Regex or literal, path, glob filter, ignore-case, context, limit; paths and line numbers; long lines, match count and total bytes all have caps |

glob/grep are done by CL traversal and `cl-ppcre` rather than by assembling
shell commands, so a user pattern never has to be handed to `/bin/bash`. Path
resolution is relative to cwd, but a user may give an explicit absolute path;
v1 does not treat cwd as a security sandbox.

On Linux, `bash` uses a separate process group; on cancellation it sends TERM
first and KILL after a short wait, which avoids leaking a pipeline or a
grandchild process. The complete output is written to a temporary file as it is
read, and that path is exposed in the tool result only when truncation actually
occurs.

## 10. Sessions

v1 uses a linear append-only JSONL file, which satisfies save/restore and does
not implement the reference project's branch tree.

Header:

```json
{"type":"session","version":1,"id":"...","timestamp":"...","cwd":"..."}
```

Every subsequent line:

```json
{"type":"message","timestamp":"...","message":{...}}
```

Constraints:

- Default directory: `~/.cadr/agent/sessions/`
- API keys, Authorization and environment variables are never written to a
  session
- Every final user/assistant/tool-result message is flushed immediately after it
  is appended
- A crash may leave one incomplete final line; only that trailing line is
  ignored
- A corrupt intermediate line or an invalid header must raise `session-error`
- `--continue` selects the most recent valid session whose header.cwd equals the
  current canonical cwd
- When no historical session is found, it reports a diagnostic and starts a new
  session
- After a restore, the full message context is rebuilt before entering the REPL;
  a missing tool result is never fabricated

## 11. CLI and REPL

Current arguments:

- `--provider anthropic|openai|google|deepseek|ollama`
- `--model <id>`
- `--base-url <url>`
- `--system-prompt <text-or-file>`
- `--continue`
- `--resume` (opens the pre-start session picker)
- `--extension <path>` (repeatable)
- `--help`
- `--version`

Environment variables:

- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `GEMINI_API_KEY`
- Optional `CADR_PROVIDER`, `CADR_MODEL`

When no provider is specified, it is inferred from the keys present, in the
order Anthropic → OpenAI → Google; this guarantees that running `./cadr` works
directly with only `ANTHROPIC_API_KEY` set. Every provider has a fixed default
model: Anthropic `claude-opus-4-8`, OpenAI `gpt-5.5`,
Google `gemini-3.6-flash`; CLI/env overrides are still allowed. All three are
recorded in the README, which avoids pulling a dynamic network model catalog
into v1.

The REPL reads standard input line by line:

```text
cadr> user input
assistant> streaming text
```

- Blank lines are ignored
- EOF saves normally and exits
- The next line is read only after each input has completed a full agent loop
- A provider/tool error prints once and leaves the session continuable
- Ctrl-C aborts the current HTTP request/process on a best-effort basis; when
  idle it exits

## 12. Tests first, and cross-implementation comparison

Every module follows a fixed rhythm:

1. Port/add the FiveAM tests first.
2. Run the target suite and save the evidence of the expected failure.
3. Implement the minimal complete behavior.
4. Re-run the target suite until it passes.
5. Run the regression tests of every completed phase.

The ordinary `cadr-*/tests` and `scripts/test-cl.sh` run offline deterministic
tests only. Real-provider, OAuth and model-behavior tests live in
`cadr-*/live-tests` and are run uniformly by `scripts/test-live.sh`; that script
must run every live item first, then report per item the pass, the skip reason
or the failure output, an initial judgement of the nature of the failure and the
grounds for it, and must finally exit `1` if any item failed. This explicit
entry-point difference is isomorphic to the actual effect of the fixed
baseline's official CI: baseline CI injects no provider credentials, so every
live block in an ordinary `npm test` is skipped.
Before a release the Part D verifier must run the live items available on this
machine; the red light may be cleared only by the user, as an explicit
adjudication made from the full report.

`docs/test-matrix.md` records, item by item:

- the original TS test file and test name
- the corresponding CL suite/test
- whether it is in scope for v1
- the fixture or verification evidence

"All ported tests pass" is audited through this matrix; a test count must not
stand in for behavioral coverage.

### Phase 1: cadr-ai

Ported first:

- Unified stream-event order and final result
- abort/error termination
- token usage/total tokens
- empty response
- tool call without result
- The text/tool subset of cross-provider history conversion
- SSE transport explicitly using an unbounded read timeout; after a silence
  longer than an ordinary JSON read timeout is simulated, events are sent and
  the connection can still consume them and terminate normally
- Anthropic SSE parsing
- OpenAI Responses tool call/result
- The v1-relevant subset of Gemini 3.6 Flash tool call/signature; the replay
  fixture must come from a real `gemini-3.6-flash` streaming response

New fixtures:

- `test/fixtures/requests/{anthropic,openai,google}-*.json`
- `test/fixtures/responses/{anthropic,openai,google}-complete.json`
- `test/fixtures/sse/{anthropic,openai,google}-*.sse`

An SSE fixture must be a redacted recording of a real response; tests replay the
raw byte stream directly and cover chunk boundaries deliberately cut in the
middle of a UTF-8 character and of a JSON token. Tests do not access an online
API.

### Phase 2: cadr-agent

Port the in-scope semantics of `packages/agent/test/agent-loop.test.ts` first:

- lifecycle event order
- tool call → result → next turn
- unknown tools and schema errors
- tools in a `:length` response are never executed
- sequential/parallel batch rules
- completion-order events with source-order results
- normal termination after abort/error

Uses a faux provider and mock tools, with no real key.

### Phase 3: tools + CLI

Ported first:

- read offset/limit/UTF-8/truncation/out-of-range
- write creating parent directories and overwriting
- edit not-found/non-unique/overlap/multiple-replacement/atomic write-back
- bash stdout+stderr/nonzero/timeout/large output/process cleanup
- glob/grep limit, ignore rules, paths and no results
- side-effecting tools executing directly by default (the v1 confirmation
  regression has been replaced by the alignment tests)
- multi-turn REPL and a real tool loop (faux provider)

### Phase 4: persistence, retries, build and acceptance

- JSONL round-trip, corrupt file, trailing-line recovery, cwd isolation,
  `--continue`
- retryable/non-retryable/limit
- the full test-op
- clean build
- end-to-end recorded replay for all three providers
- "read → modify → test fails → fix → test passes" on a small fixture repo

### Payload cross-implementation comparison

`scripts/export-ts-payloads.ts` exports the three request bodies at the fixed
reference commit through the public stream API's payload hook and a fake
transport. The CL tests generate a payload from the same context/model/tool
input and compare field by field, recursively:

- key sets are equal
- array order is equal
- number/string/bool/null types and values are equal
- no field may be ignored except those the test lists explicitly as dynamic

The dynamic-field allowlist admits request/session IDs and timestamps only;
`model`, messages, tools, stream, max tokens and the like must not be compared
loosely.

## 13. Build

`build.sh`:

1. Check that `sbcl` exists and that its version is >= 2.4.
2. Load the file named by `QUICKLISP_SETUP`, or
   `~/quicklisp/setup.lisp`.
3. Quickload `cadr-cli`.
4. Run every ASDF test-op; if the tests fail, no binary is produced.
5. Check whether `*features*` contains `:sb-core-compression`. When supported,
   call:

```lisp
(sb-ext:save-lisp-and-die
 "cadr"
 :toplevel #'cadr-cli:executable-main
 :executable t
 :save-runtime-options t
 :compression t)
```

When it is not supported, print an explicit degradation notice and call
`save-lisp-and-die` without the `:compression` keyword. Passing
`:compression nil` is not sufficient, because an SBCL built without
`sb-core-compression` may not even accept the keyword; an uncompressed build
must still succeed in producing `cadr`. The build tests cover argument
construction both with and without the feature, so that it does not merely
happen to work on this machine's SBCL variant.

The artifact is `./cadr` in the repository root. Running it requires neither the
source nor Quicklisp, but it still depends on Linux/glibc and the system dynamic
libraries HTTPS needs; "a single executable" is not a false promise of full
static linking.

The current audit environment uses SBCL 2.6.7 and Quicklisp 2026-01-01. That
SBCL does not include `:sb-core-compression`; a real build in an isolated HOME
verified the degradation notice, the uncompressed `cadr` artifact, `--help` /
`--version` with saved runtime options, and `--continue` across two processes.

## 14. Acceptance evidence map

| `docs/progress/goal-v1.md` acceptance item | Final evidence |
|---|---|
| One command produces `cadr` on a clean Linux | Clean-build log in an isolated HOME, `file` output for the binary |
| Multi-turn streaming conversation with Anthropic | The credential gate in `test/cadr-ai/live-provider-test.lisp`; with no key in this environment, it skips exactly as the baseline does |
| Read/modify/test/fix on a real repo | Deterministic faux-provider E2E plus the DeepSeek credential gate in `test/cadr-evals/live-evals-test.lisp` |
| One E2E per provider | Three raw SSE replays, request capture and final unified-message assertions |
| All ported tests pass, documentation consistent | `docs/test-matrix.md` fully green, full ASDF test-op, documentation diff audit |
| Default execution, no approval in the core | Side-effecting tools execute directly, `--yolo` is rejected, an approval-hook example exists |
| `--continue` | Two-process session restore E2E |
| README complete | Build, configuration, provider, tools, security and differences sections checked |

## 15. Phase reports

Each phase ends by adding `docs/progress/phase-N.md`, which always contains:

- what was completed
- the exact test/build commands run and their results
- known differences from the fixed TS baseline
- remaining risks and the next phase

### 15.1 Pre-review and closeout gates for later goals

Starting from the goal after this remediation, every goal specification must
contain the following two global gates verbatim:

1. Part A must list new third-party dependencies and their transitive closure;
   if any dependency not registered in `docs/dependency-audit.md` is found, mark
   it `blocked` immediately, and implement it only after obtaining explicit user
   authorization and updating both the audit and the README. Adding first and
   ratifying afterwards is a violation.
2. "Complete" requires all of: implementation and test acceptance, commits
   ledgered in logical groups, a full gate re-run after the commit, and a clean
   working tree. Uncommitted changes must not be declared complete; an
   explicitly protected local file may be kept only through a repository-local
   ignore, and must not be mixed into a commit or deleted.

No question requiring clarification from the source author arose during
implementation. The design confirmation froze:

- OpenAI implements the Responses API only in v1;
- `glob` takes the semantics of the reference implementation's `find`;
- v1 sessions are linear JSONL, with no branching/compaction;
- the network main loop streams synchronously, with controlled parallelism only
  for safe read-only tools.

Additional items frozen after human confirmation:

- when SBCL lacks `sb-core-compression`, degrade to an uncompressed native image
  rather than failing the build;
- an SSE request explicitly uses an unbounded read timeout, and that behavior is
  protected by a long-silence regression test.

## 16. v2 Phase 5: provider completeness

Phase 5 keeps v1's unified messages, unified event stream and protocol-adapter
boundary, but separates "provider name" from "wire protocol". Providers such as
DeepSeek and Ollama reuse the OpenAI Chat Completions adapter and do not
duplicate transport or stream-parsing logic.

### 16.1 The provider registry and resolution priority

`cadr-ai` adds `provider-definition` and an explicit registry. Each entry
declares:

- a stable provider id
- the wire protocol: `anthropic-messages`, `openai-responses`,
  `openai-completions` or `google-generative-ai`
- the default base URL, default model and API-key environment variable
- the supported authentication methods: `api-key`, `oauth`
- image, tool and chain-of-thought capabilities

The built-in definitions are Anthropic, OpenAI, Google, DeepSeek and Ollama. The
request object is still built by the protocol adapter; the registry only selects
the adapter, the authentication and the defaults.
Base-URL resolution order is fixed as:

1. CLI `--base-url`
2. That provider's `base-url` in `~/.cadr/agent/config.json`
3. The registry default

Model resolution is analogous: CLI `--model`, environment/configuration
override, registry default. Ollama is a local provider with no API key; every
other API-key provider must report a configuration condition immediately when
its credential is missing. DeepSeek uses the OpenAI Chat Completions path at
`https://api.deepseek.com`.

### 16.2 The OpenAI Chat Completions adapter

A separate `openai-completions-provider` is added, responsible for
`/v1/chat/completions` requests and SSE:

- history conversion for the four roles system/user/assistant/tool
- tool schemas, assistant `tool_calls` and tool-result association
- streaming `delta.content`, `delta.reasoning_content` and aggregation of
  fragmented `tool_calls[].function.arguments`
- `finish_reason` mapping: `stop`, `length`, `tool_calls`; an unknown value is
  an error
- `stream_options.include_usage = true`, with cache/reasoning tokens in usage
  mapped into the unified usage
- non-streaming responses reuse the same content, tool-call, usage and
  stop-reason semantics

Model/provider compatibility differences may be controlled only by registry
capability fields, and must not be scattered into CLI branches. DeepSeek's
recorded replay must go through this adapter.

### 16.3 Images and the model catalog

Unified content gains `image-content`, which stores only the MIME type and the
base64 data, and never writes binary data or tokens to a log. The three
protocols encode it as:

- Anthropic: `source.type=base64`
- OpenAI Responses: `input_image.image_url=data:<mime>;base64,<data>`
- OpenAI Chat Completions: `image_url.url=data:<mime>;base64,<data>`
- Google: `inlineData.mimeType` and `inlineData.data`

When a provider/model does not declare an image capability, an explicit
`unsupported-content-error` is raised before the request is sent; silently
dropping the content is forbidden.

The static model catalog consists of `model-metadata` entries recording the
context window, maximum output, image/tool/chain-of-thought capabilities and the
input/output/cache unit prices per million tokens. Usage cost is computed from
the model catalog and stored in the unified usage. The update script produces
only a deterministic Lisp data file; the runtime does not depend on the network.

### 16.4 Authentication and OAuth

Request authentication for a provider resolves uniformly to either
`api-key-credential` or `oauth-credential`. The adapter receives only the final
request headers and takes no part in login or refresh.
`~/.cadr/agent/auth.json` is the only persistent credential file; it is written
through a temporary file plus atomic replacement, and is forced to `0600` on
creation. Every condition, session and diagnostic output passes through secret
redaction first.

OAuth resolution uses double-checked locking: when an access token has less than
five minutes of validity left, it acquires the provider-level lock first and
then re-reads the auth file; only a request that would still expire performs the
refresh, and the rotated credential is persisted before the lock is released.

Apart from the client identity, OpenAI Codex OAuth uses strictly the parameters
of the fixed TS audit commit:

- authorize: `https://auth.openai.com/oauth/authorize`
- token: `https://auth.openai.com/oauth/token`
- client id: `app_EMoamEEZ73f0CkXaXp7hrann`
- redirect URI: `http://localhost:1455/auth/callback`
- scope: `openid profile email offline_access`
- PKCE: S256, with a random state that is verified
- authorize additionally carries
  `id_token_add_organizations=true`,
  `codex_cli_simplified_flow=true`, `originator=cadr`
- The Responses request headers contain the bearer token, the
  `chatgpt-account-id` extracted from the JWT, `originator: cadr` and
  `OpenAI-Beta: responses=experimental`

`originator=cadr` is the client-identity difference approved by the user in Goal
9 Part C: it changes third-party attribution only, and changes neither OAuth,
provider identity, the Responses payload nor event semantics. The baseline's
`originator=pi` must not be used for Cadr traffic.

The local one-shot callback server listens on `127.0.0.1:1455` only, accepts
`/auth/callback` only, and closes immediately after verifying the state. The
user command `/login openai` maps to the baseline provider identity
`openai-codex`; the exchange, the refresh, auth.json storage and Codex Responses
reads always use that same identity. After login, if the previous route had no
usable credential, or if the current model belongs to another provider, the
`openai-codex` default model is selected and persisted, so that conversation
works with no provider/model argument afterwards. Following the baseline, the
TUI shows the raw URL as an OSC 8 clickable link together with
`Ctrl+click to open`, with no session-notice prefix; only the non-TUI fallback
prints `Open this URL in your browser:` followed by the raw URL on the next
line. `/logout openai` atomically deletes the `openai-codex` credential.
Anthropic OAuth reuses the same credential interface, but is explicitly marked
as unverified in the implementation, the test report and the README.

Every release entry point (`cadr`, `cadr-server`, `cadr-evals`) is additionally
wrapped in a fatal condition boundary that takes no part in business recovery.
It catches an unhandled `serious-condition` before the stack unwinds; the user
channel receives only the condition type, restricted copy and the local log
path, while the full backtrace, with known secrets exactly substituted, is
written to a `0600` file under `~/.cadr/agent/crash/`, after which the CLI
applies a second pattern-based redaction pass over Authorization, Bearer and
token/key/secret shapes. Secret-bearing objects such as provider, credential,
request, config, auth input and external-service client all define a
`print-object` that does not recursively display secret slots, as defense in
depth for a path that bypasses the fatal boundary. That boundary handles only
invariant/runtime failures that ought to terminate the process; recoverable
provider, tool, extension and input errors must still be normalized at their own
product boundaries, and must not fall back on the crash handler.

### 16.5 Phase 5 test gates

Implementation is test-first:

1. registry/default/override/no-key behavior
2. Chat Completions non-streaming payload and recorded SSE E2E
3. the four image encodings and the unsupported-content error
4. model lookup and cost arithmetic
5. PKCE, callback state, 0600, logout, redaction
6. recorded replay of a single concurrent refresh of an expired token
7. OpenAI Codex OAuth Responses request headers
8. the full existing v1 regression, `npm run check`, and the Phase 5
   credential-gated live tests

The Phase 7 stable extension API was subsequently confirmed by a human
separately and implemented.

## 17. v2 Phase 6: session trees, compaction and export

Phase 6 defines the session file as an append-only event tree. At runtime a
single root-to-leaf path is selected as the model context; branching does not
copy, modify or delete an old node. This is a parent-linked tree, not several
linear message arrays that are easy to let drift apart.

### 17.1 JSONL v2 and the tree invariants (historical format, superseded by Wave 2 v3)

The first line is still the session header, but `version` is raised to `2`. The
remaining records are:

- `message`: contains a unique `id`, `parentId`, `timestamp` and the complete
  `message`;
- `compaction`: the Phase 6 v2 node once contained `summary`, `sourceIds`,
  `firstKeptEntryId` and `tokensBefore`; Wave 2 v3 no longer writes the
  non-reference `sourceIds`.

The `parentId` of every ordinary appended node is the current leaf; branching
from a historical node only moves the in-memory leaf, and the next append
naturally forms a second child. The file never deletes or edits a node in place,
so after a restart both branches can still be recovered along their parent
chains. The loader rejects duplicate ids, missing/forward parents and
non-existent compaction references, so that a corrupt file is not disguised as a
recoverable session.

Loading v1 performs a one-shot in-place migration:

1. keep every existing field of the header and of each message envelope;
2. add unique ids and linear parentIds in the original order, and change the
   header to v2;
3. write a temporary file in the same directory and rename it atomically;
4. then load under the v2 invariants.

Consequently an old message's content, usage, tool calls/results, timestamps and
unknown extension fields cannot be lost to a deserialize-reserialize round trip.
Only an incomplete final JSONL record is ignored, following the v1 behavior;
corruption in the middle is still a hard error.

### 17.2 The active branch and session operations

`session-branch` can move the leaf to any existing node; `session-messages`
rebuilds the active context from the leaf along the parent chain every time, and
keeps no second, driftable copy of message truth.
`list-sessions`, `resume-session` and the CLI provide:

- `--resume`: opens the session picker before startup (baseline
  cli/session-picker.ts) and opens the selection by path; an exact-id restore
  goes through `--session <id>`;
- `/sessions`: lists resumable sessions and marks the current one;
- `/switch <id>`: switches session within the same process, replacing the agent
  context at the same time;
- `/branch <node-id>`: attaches the next message to the specified historical
  node;
- `/export [path]`: exports the complete tree, not merely the current branch.

HTML export uses only in-house escaping and string generation. Every message,
tool argument, summary, id and parentId is escaped as text and the file contains
no script, so session content cannot inject HTML.

### 17.3 Compaction nodes and traceability

Automatic compaction belongs to the agent runtime, not to a provider adapter.
Before each model request, the runtime uses the most recent valid assistant
usage plus a tail estimate; with no usage it uses a conservative
characters-over-4 estimate. When the context exceeds
`model.context-window - reserve-tokens`:

1. accumulate `keep-recent-tokens` backwards from the newest message, cutting
   only at a user or assistant boundary, and never starting from an orphaned
   tool result;
2. summarize the older portion using the current agent's provider, model and
   stream function;
3. append a compaction node whose `firstKeptEntryId` points at the retained
   suffix; the complete old nodes remain traceable through the append log and
   the parent chain;
4. replace the model context with "summary message + retained suffix", and
   continue the original request.

A later compaction may summarize the previous compaction node together with the
newly-old messages, forming a traceable chain of summaries. The original nodes
always remain in the JSONL; compaction changes the context projection only, not
history. When compaction fails, no half-finished node is written; the agent
reports an event and keeps the original context.

If the provider still returns an explicit context-overflow error, the runtime
keeps that error node as a traceable side branch, returns to the pre-request
leaf, forces a compaction and retries exactly once. A second overflow is not
retried in a loop and is returned directly as a terminal error.

The default thresholds follow the intent of the fixed TS baseline: reserve
16,384 tokens and keep the most recent 20,000 tokens; for small-window models
they scale down in proportion to the window, so that the defaults do not
themselves make compaction fire permanently. Tests may override both values
explicitly to construct deterministic boundaries.

### 17.4 Phase 6 test gates

Phase 6 adds the following regressions before the feature implementation:

1. a new session writes v2 id/parentId node by node, and after branching the two
   paths do not contaminate each other;
2. after the file is reloaded, both leaves can be restored and appended to;
3. v1 migrates automatically to v2, preserving all message semantics and the
   extra fields of the original envelope;
4. duplicate id, dangling parent and a corrupt intermediate line fail, while an
   incomplete trailing line remains recoverable;
5. near the window, the current model is called to produce a summary, after
   which the original request continues;
6. the compacted context contains only the summary and the retained suffix,
   while the JSONL still contains every original node; at the time Phase 6 also
   asserted the `sourceIds` that Wave 2 v3 later removed;
7. exact resume, listing, in-process switch, CLI argument exclusivity;
8. HTML export contains the complete branch and escapes malicious text
   correctly;
9. the full existing Phase 1–5 regression, the native build and `npm run check`
   continue to pass.

The Phase 7 extension API was submitted for separate human confirmation and
implemented after every Phase 6 gate passed.

## 18. v2 Phase 7: the Lisp extension system (implemented)

The stable API in this section was confirmed by a human and frozen on
2026-07-30.

The extension system uses a **registry builder plus immutable snapshot**: the
load phase only registers definitions into a staging registry, and on success
atomically replaces the read-only snapshot the agent uses. An extension package
provides namespace isolation and the snapshot provides reload isolation; neither
is a security sandbox. A Common Lisp extension has arbitrary in-process code
capability, and strong isolation is provided by the user through a container.

### 18.1 Extension shapes, discovery and priority

There are exactly two legal entry points:

- a single `*.lisp` file, whose extension id is the filename without the
  suffix;
- a directory containing `extension.lisp`, whose extension id is the directory
  name.

Each entry point is loaded into a unique
`CADR-EXTENSION/<id>/<generation>` package whose initial package `:use`s only
`CL` and `CADR-AGENT`; an explicit package prefix is used when `CADR-AI` is
needed. The loader dynamically binds `*package*`, `*load-pathname*` and the
registration context. An extension neither needs nor should write
`in-package`. This prevents ordinary symbols of different extensions from
polluting one another, but claims no restriction on a trusted extension
deliberately reaching another package or a system capability.

Discovery order is fixed by scope first and filename lexicographic order
second:

1. `--extension <path>`, the highest priority; the argument is repeatable and a
   later occurrence wins;
2. `./.cadr/extensions/`, project scope;
3. `~/.cadr/agent/extensions/`, global scope.

A lower-priority entry point with the same id is shadowed before loading, so a
project entry explicitly overrides a global entry of the same name and a CLI
entry overrides both. When the same id appears within the same scope, the
conflict is reported and the deterministic first entry is kept; only a repeated
CLI argument is resolved as "later wins". A shadowed entry point is never
executed, which avoids a seemingly-overridden global extension still producing
load-time side effects.

When different extension ids register a resource of the same name, the first is
taken by the priority above and the conflict is reported:

- an extension tool may override a built-in tool, matching the capability of the
  fixed TS baseline;
- built-in slash commands always win; an extension cannot hijack `/reload`,
  `/install`, or the authentication or session commands;
- other commands take priority over a prompt template of the same name;
- prompt-template and skill names likewise resolve by extension priority.

### 18.2 The frozen registration API

The following four macros and their argument protocols are exported from
`CADR-AGENT` and stay compatible after release:

```lisp
(define-tool "echo"
  :description "Return text."
  :parameters <JSON-Schema hash-table>
  :execution-mode :parallel
  :handler (lambda (call-id arguments context)
             (declare (ignore call-id context))
             (values
              (list (cadr-ai:make-text-content
                     :text (gethash "text" arguments)))
              nil)))

(define-command "hello"
  :description "Print a greeting."
  :argument-hint "[name]"
  :handler (lambda (arguments context) ...))

(define-event-hook :tool-call-before
  :priority 0
  :handler (lambda (event context) ...))

(define-prompt-template "review"
  :description "Review a file."
  :argument-hint "<path>"
  :template "Review $1 carefully.")
```

The specific contracts are:

- `define-tool`
  - required: a string name, description, a JSON Schema hash table, and a
    handler;
  - `:execution-mode` may only be `:parallel` or `:sequential`, defaulting to
    `:parallel`;
  - the handler is fixed at `(call-id arguments context)` and returns
    `(values content details)`; content is a list of `CADR-AI` content;
  - the schema is validated structurally at registration, and the final
    arguments are validated on every call.
- `define-command`
  - the handler is fixed at `(arguments context)`; arguments is the unsplit
    string after the command name;
  - the return value takes no part in sending a message; the extension notifies
    the frontend or calls the agent through the context;
  - the name carries no leading `/`, and may use only lowercase ASCII letters,
    digits, `-`, `_` and `:`.
- `define-event-hook`
  - the payload and result semantics of the four existing events
    `:turn-start`, `:turn-end`, `:tool-call-before` and `:tool-call-after` are
    unchanged;
  - Wave 2 adds only the baseline lifecycle events listed in section 3 of the
    proposal; the handler is still fixed at `(event context)`, and new events
    use their own strict plist result;
  - priority is an integer and the smaller one runs first; equal priorities run
    in a fixed order determined by extension priority and definition order.
- `define-prompt-template`
  - `:template` may be a string or `(lambda (argv context) string)`;
  - a static string supports the fixed TS baseline's `$1`, `$2`, `$@`,
    `$ARGUMENTS`, `${N:-default}`, `${@:-default}`, `${@:N}` and `${@:N:L}`;
  - argv is produced by a deterministic tokenizer supporting single and double
    quotes, and substitution is not recursive;
  - a name of the form `skill:<name>` is a Lisp skill. A skill is not a second
    file format, but a named template using the same registration, priority and
    reload machinery.
- `define-provider`
  - registers only a `cadr-ai:provider-definition` and optional model metadata;
  - the registration lands in the current extension host overlay and does not
    change the global provider registry.

These macros may be called only inside a valid load-registration context;
calling one directly in the REPL or in ordinary application code produces an
explicit condition, so that a definition cannot land in an invisible global
implicit registry.

### 18.3 The stable handler data protocol

`extension-context` is an opaque object with the following stably exported
reader and action interfaces:

- `extension-context-cwd`
- `extension-context-agent`
- `extension-context-session`
- `extension-context-source-path`
- `extension-context-mode`
- `extension-context-notify`
- `extension-context-compact`
- `extension-context-reload`
- `extension-context-select`, `extension-context-confirm`
- `extension-context-input`, `extension-context-editor`
- `extension-context-set-status`, `extension-context-set-widget`
- `extension-context-set-title`, `extension-context-set-editor-text`
- `extension-context-register-provider`, `extension-context-register-tool`
- `extension-context-send-message`, `extension-context-send-user-message`
- `extension-context-set-session-name`

A context is valid only within the dynamic extent of the current handler; saving
it and using it in another handler or after a reload raises
`stale-extension-context`. `extension-context-agent` returns the current
`CADR-AGENT:AGENT`, which lets a Lisp extension use the already-public agent
API, but does not bring the CLI or a future TUI object into the stable
interface. The action function signatures are fixed as:

- `(extension-context-notify context message &key (level :info))`, where level
  may only be `:info`, `:warning` or `:error`, rendered by the current
  frontend;
- `(extension-context-compact context &key (force-p t))`, which returns whether
  compaction happened;
- `(extension-context-reload context)`, which returns the reload report and
  immediately makes the old context stale;
- `extension-context-mode` returns the current mode as `:repl`, `:tui`,
  `:text`, `:json` or `:rpc`;
- the exact signatures of the dialog/UI and runtime actions are fixed in
  sections 4 and 7 of the approved proposal.

`extension-event` stably exports the following read-only accessors:

- `extension-event-type`
- `extension-event-turn-index`
- `extension-event-message`
- `extension-event-tool-call`
- `extension-event-tool-result`
- `extension-event-tool-results`
- `extension-event-payload`
- `extension-cancellation-aborted-p`

The four old events keep their dedicated accessors; the payload of a new event
is a read-only kebab-case plist.
`extension-cancellation-signal` is an opaque object exposing only the aborted
state.

A hook's only mutating return value is constructed by
`make-extension-hook-result`, whose stable keywords are:

- `:replacement`: replaces that event's main payload;
- `:append-messages`: a list of valid `CADR-AI` messages appended at that
  event's commit point;
- `:block-p` and `:reason`: permitted only for `:tool-call-before`.

The type of `replacement` is determined by the event:

| event | replacement |
|---|---|
| `:turn-start` | the user message about to be persisted and sent |
| `:turn-end` | this turn's final assistant message |
| `:tool-call-before` | `CADR-AI:TOOL-CALL` |
| `:tool-call-after` | `CADR-AI:TOOL-RESULT-MESSAGE` |

Multiple hooks compose serially: a later one sees the earlier one's replacement
and the accumulated appended messages. A wrong return type, a replacement
message with the wrong role, and an inconsistent tool call/result id each fail
only the current hook; the last valid state is kept and the next hook continues.

The tool-call order is fixed as:

1. `:tool-call-before` chained rewrite or block;
2. re-resolve the tool by its final name, and schema-validate the final
   arguments;
3. execute the tool;
4. `:tool-call-after` chained result rewrite;
5. persist the final result and the appended messages.

A hook therefore cannot bypass the schema by "changing the arguments after
validation". Turn replacement and appended messages likewise complete before the
JSONL is written, so the session file remains the single source of truth for
runtime semantics. A user who needs tool approval can implement it with a
`:tool-call-before` hook; the core has no built-in approval policy.

### 18.4 Hot reload and condition containment

`/reload` rediscovers every entry point and loads each into a new generation
package. The extensions that load successfully form the staging snapshot; when a
single extension fails to load:

- on the first load: skip that extension and continue with the others;
- on hot reload: keep that id's last-known-good definition, and update the other
  successful ones as usual;
- when a higher-priority override fails, a shadowed lower-priority extension is
  not quietly enabled.

After all entry points are processed, exactly one locked pointer swap happens.
A handler/tool already executing captures the old snapshot and will not change
implementation mid-call; the old package is reclaimed only after the last old
call finishes. The registry swap can be rolled back, but arbitrary external side
effects an extension deliberately produced at load time cannot be, and the
README security section must say so explicitly.

Every boundary catches `condition`:

- a load error carries the extension id, the absolute path and the load stage;
- a command/hook/tool/template error carries the resource name and the execution
  stage;
- a tool error is converted into an `is-error` tool result;
- a command/template error is written to the current frontend's error output;
- a hook error skips the current hook, and the agent main loop continues.

User-visible text passes through the existing secret redaction first. An
extension error never terminates the agent; only damage to cadr's own invariants
is still handled as a core error, and must not be swallowed by the extension
exception handler.

### 18.5 Security model

Aligned with the fixed TS baseline: an extension is loaded directly once
discovered, a tool executes directly by default, and there is no trust ledger,
no first-load confirmation, no content-fingerprint approval and no `--yolo`
branch. An extension is arbitrary in-process code; package isolation and
condition containment solve naming conflicts and reliability only, and provide
no privilege isolation.

The README must state explicitly:

- running cadr in an untrusted repository is equivalent to letting the project
  extensions in that repository execute arbitrary code on the local machine;
- a user who needs strong isolation should run it in a container, a virtual
  machine or a restricted user account;
- a user who needs per-tool approval can load the minimal
  `:tool-call-before` Lisp hook extension the documentation provides; the
  approval policy does not enter the core.

### 18.6 `/install` and Lisp packages/skills

`/install <git-url>` aligns with the fixed TS baseline's URL rules: without a
`git:` prefix, only an explicit `http://`, `https://`, `ssh://` or `git://` is
accepted; with a `git:` prefix, the historical shorthand (including
`git@host:path`) remains compatible. Local paths, `file://`, values starting
with `-`, NUL, backslashes and repository paths containing `..` are rejected.
The implementation calls `git clone -- <url> <staging>` through an argv list,
and never assembles a shell string.

The clone target first lands in
`~/.cadr/agent/extensions/.staging-<random>/`. On success it verifies that:

1. `extension.lisp` exists at the top level;
2. the derived directory name contains only safe characters;
3. the canonical entry point and every loaded file stay inside the clone root;
4. the final target does not exist, so that an existing extension cannot be
   silently overwritten.

Once verification passes, it is atomically renamed into the global extension
directory and goes through a normal `/reload`.
A failed extension load does not break the REPL; the install directory is kept,
so the user can audit or repair it.
A git package's tools, commands, skills and prompt templates are all registered
by its Common Lisp `extension.lisp`; no npm, JavaScript or Markdown skill
runtime is introduced.

### 18.7 Phase 7 test gates

The following regressions are added before the implementation:

1. the happy path, argument errors and out-of-registration-context calls for the
   four registration macros;
2. separate packages, deterministic discovery, global/project/CLI overriding and
   conflict diagnostics;
3. chained rewrite, append, block, priority and post-rewrite revalidation for
   the four hook kinds;
4. any condition during load and during tool/command/hook/template execution
   fails to kill the agent;
5. atomic reload swap, last-known-good on failure, an in-flight call keeping the
   old snapshot;
6. approval-free loading by default, no trust ledger, path constraints and error
   isolation;
7. the full set of prompt placeholders, and command/template/built-in resolution
   priority;
8. `/install`, argv-injection protection and no overwriting on target conflict,
   verified against a local temporary git repository;
9. a faux provider completing "write a new extension → `/reload` → call the new
   tool" within a single process;
10. a DeepSeek credential-gated FiveAM test completing the same self-extension
    loop;
11. the full Phase 1–6 regression, the native build, the acceptance smoke and
    `npm run check` continue to pass.

If an implementation needs to change the exported symbols, handler arity or hook
composition semantics above, it must go through human confirmation again, and
must not drift silently during coding.

### 18.8 The Goal 8 Part B bounded expansion and re-freeze

The user approved only the additive surface that already exists in the fixed
audit commit:

- `define-shortcut`, `define-flag`, the message/entry/tool renderers;
- idle/wait, custom UI, autocomplete, theme and tool expansion on the handler
  context;
- a load-scope `extension-api` that can be captured across the same generation
  and goes stale after a reload/retirement, providing send/exec/flag/
  active-tools;
- bare/named/hidden inline factories;
- `define-native-provider` and the `cadr-ai` additive
  login/check/refresh-context contract;
- the bundled llama.cpp provider and `/llama`, whose management SSE explicitly
  disables the read timeout and whose inference reuses OpenAI Chat Completions.

The lambda lists of the existing macros, the old event payloads/results and the
handler-scope stale semantics are all unchanged. The TUI glue only reuses
existing components inside `cadr-cli`; relative to the Goal 8 start commit,
`src/cadr-tui` production object IDs changed by zero. The full API baseline
evidence and the unfreezing boundary are in
[`docs/proposals/goal-v8-part-b.md`](proposals/goal-v8-part-b.md).

## 19. Phase 8: TUI architecture

Phase 8 adds a separate ASDF system, `cadr-tui`. The dependency direction
extends to:

```text
cadr-cli -> cadr-agent -> cadr-ai
   |
   +----> cadr-tui
```

`cadr-tui` is a terminal component library with no agent semantics; it handles
only input decoding, Unicode cell layout, component rendering, ANSI differential
output and terminal lifecycle. `cadr-cli/tui.lisp` is the sole adapter: it
projects exactly the same `CADR-AGENT:AGENT-EVENT` the REPL uses into interface
state, and hands editor submissions to the existing prompt/command/template
dispatch. Provider, session, extension, tool-execution and compaction logic must
not be copied into `cadr-tui`.

### 19.1 The rendering model

The shared component protocol is `(render component width) -> lines`;
no line's visible width may exceed width. The root view produces an array of
plain string lines each frame, and `terminal-renderer` compares it with the
previous frame:

- a full redraw on the first frame, on a width change, or on an explicit
  invalidate;
- other frames locate and redraw only the changed lines;
- when the content shortens, the stale trailing lines are cleared;
- one frame of ANSI output is wrapped in a synchronized-output sequence, which
  avoids a half-frame flicker;
- the cursor position is determined by the logical row/column the editor
  returns; invisible markers are not written into business text.

Tests consume the same ANSI output with `virtual-terminal` and assert screen
lines and a cursor snapshot; a real terminal is not a prerequisite for unit
tests.

Unicode layout takes the grapheme cluster as the smallest unit of editing and
clipping. A combining mark has width 0; CJK wide/fullwidth characters, emoji,
regional indicators and ZWJ emoji clusters have width 2; every other printable
character has width 1. ANSI/OSC/APC sequences have no width, and a tab expands
to exactly three spaces at the rendering boundary. Editor movement, deletion,
line breaking and wrap clipping must never split a cluster.

### 19.2 Input and components

The input path supports legacy, CSI/SS3, CSI-u, Kitty and modifyOtherKeys,
parsing press/repeat/release and native modifiers; `stdin-buffer` preserves an
incomplete ESC/CSI/paste sequence across reads, and separates terminal
capability replies from user input within the same batch while keeping the
original order. Ordinary UTF-8, arrow keys, Home/End, Delete/Backspace, Enter,
Shift+Enter, Ctrl+C, Ctrl+D, PageUp/PageDown, Escape and bracketed paste all
enter the same configurable keybinding matcher.

`multiline-editor` stores plain text, a grapheme cursor index and at most 100
history entries; Enter submits, Shift+Enter inserts a newline, and a paste is
inserted verbatim with CRLF normalized to LF. The editor and the single-line
input share word-wise movement, the kill ring, yank/yank-pop and undo semantics.
The fixed baseline provides undo only, not redo, so the core adds no redo stack
and no redo binding.

Phase 8 includes the following components, fixed:

- slash, path and `@` file autocomplete, with deterministic fuzzy ranking;
- overlay-stack anchor/size/margin/clipping, focus/capture, non-capturing input
  dispatch and CJK/ANSI-safe composition;
- OSC 11 / colour-scheme and cell-size replies, plus Kitty/iTerm2 image
  encoding, capability detection, deletion and a text fallback on unsupported
  terminals;
- a streaming Markdown text area: incremental text re-runs deterministic
  block/inline rendering each frame, supporting headings, lists, quotes, fenced
  code and inline code, without waiting for message-end;
- the tool block: shows the tool name, an argument summary and the execution
  status, collapses by default on completion, and can be expanded or collapsed
  with Enter;
- the status bar: a read-only display of the current model, cumulative
  input/output/cache tokens, cumulative cost and the session id; when a price is
  missing, the cost shows `—`, and a price must not be guessed;
- a generic select-list: filtering, wrapping up/down movement, PageUp/PageDown,
  Enter to confirm, Escape to cancel; the model and session pickers reuse it.

Model selection uses only `CADR-AI`'s current model catalog, and after selection
updates the agent through the existing provider instantiation path; session
selection calls only the existing session list/switch path. Both are interactive
capabilities the baseline already has, and neither creates a second state
source.

### 19.3 Terminal lifecycle and frontend selection

`process-terminal` supports only this project's target platform, Linux x64 /
SBCL 2.4+:

1. save the stdin termios;
2. enter raw mode, enable bracketed paste, install the SIGWINCH handler;
3. run the TUI;
4. restore termios, the handler, bracketed paste and the hardware cursor in an
   `unwind-protect` cleanup that covers the entire run.

If entering raw mode fails, it reports the error before entering the main loop,
and must not leave a partially-enabled state behind. Exit, Ctrl-C, EOF, a
provider condition and an extension condition all go through the same cleanup.

An interactive stdin/stdout starts the TUI by default; `--no-tui` forces the
existing line REPL. If either stream is not a TTY, the one-shot text print mode
is used automatically; `--mode json` and `--mode rpc` output event JSONL and RPC
JSONL respectively. The TUI and the REPL continue to call the same
`dispatch-user-input` and to subscribe to the same agent event stream; mode
selection does not duplicate agent state.

### 19.4 Phase 8 verification gates

- `cadr-tui/tests` covers Unicode width/cluster, wrap clipping, the editor,
  paste, history, select-list, Markdown, differential output, resize, trailing
  line clearing and virtual-terminal snapshots;
- `cadr-cli/tests` covers `--no-tui`, non-TTY degradation, the shared dispatch,
  the projection from agent events to tool block/stream/status, and terminal
  cleanup under a condition;
- manual terminal acceptance covers a real multi-turn coding task, streaming
  output, tool collapsing, model/session selection, resize, CJK/emoji input, and
  the shell state after an abnormal exit.

## 20. Phase 9: native infrastructure and the final dependency boundary

Phase 9 keeps the public provider, agent, extension, session and frontend
protocols unchanged, and replaces the implementation underneath them only. The
switch order is fixed by risk as JSON, CLI arguments, regular-expression
evaluation, HTTP:

1. `json.lisp` is an in-house RFC JSON parser/stringifier handling UTF-8,
   Unicode surrogates, arbitrary-precision decimal numbers, escapes, objects and
   arrays uniformly; the parser bounds container nesting depth so that malicious
   input is rejected with an ordinary condition, and the stringifier rejects
   NaN/Infinity; `com.inuoe.jzon` is removed.
2. `arguments.lisp` is this project's own fixed option syntax, supporting
   `--name value`, `--name=value`, repeated `--extension`, flags and structured
   errors; `clingon` is removed.
3. A full regular-expression engine is not reinvented; it is explicitly deferred
   by `docs/progress/goal-v2.md` and `cl-ppcre` is kept.
   Glob traversal, `.gitignore` interpretation and literal grep are still
   implemented in project code.
4. `http.lisp` implements connection, request writing, response parsing,
   content-length, connection-close, chunked and streaming bodies in-house; TLS
   is provided by `cl+ssl`; `dexador` is removed. Content-Length must be a
   non-negative decimal integer, and a truncated body is an explicit error;
   authentication header values are redacted uniformly before a transport/API
   condition is produced.

Two behavior-preserving dependency closures were completed at the same time: the
production thread API uses `sb-thread` directly, and tool JSON Schemas are
validated natively by `schema.lisp`, which removes `bordeaux-threads` and
`cl-jschema`. Production UTF-8 conversion uses SBCL's native facilities, which
removes the direct dependencies on `babel`, `flexi-streams` and `usocket`.

The invariants of the final production dependency audit are:

- the two registered in-house exceptions are exactly `cl+ssl` and `cl-sqlite`;
- `cl+ssl` is the only cryptographic dependency; `cl-sqlite` only binds the
  system `libsqlite3`;
- the only explicitly deferred dependency is the full regular-expression engine
  `cl-ppcre`;
- Goal 10 adds a separately approved, explicitly-enabled-only Slynk debugging
  service category, which is not folded into the in-house exceptions or the
  pure-Lisp replaceable category;
- every other `.asd` production system dependency is either a system of this
  project or a facility shipped with SBCL/ASDF;
- test systems may keep historical libraries in order to construct independent
  fixtures and comparisons, but production source must not reference them.

Phase 9's regression gates include native JSON, CLI, schema, real loopback HTTP,
chunked bodies, unbounded SSE read timeout, every old test, the native image,
ordinary DeepSeek streaming, self-extension and a real TUI smoke. The
implementation and performance evidence are recorded in
`docs/progress/phase-9.md`.

## 21. The cadr naming and data migration boundary

The naming migration changes identity, paths and a one-shot compatibility entry
point only; it changes no provider, agent, session, extension or TUI semantics.
The pre-migration accepted baseline is
`c07b5a668`, and that commit and all of its ancestors are reachable on the
current branch.

The public naming is fixed as:

```text
cadr-cli -> cadr-agent -> cadr-ai
    |
    +----> cadr-tui
```

The ASDF production/test systems, the directories, the CL packages and the
native image all use that naming. The stable extension interfaces
`DEFINE-TOOL`, `DEFINE-COMMAND`,
`DEFINE-EVENT-HOOK`, `DEFINE-PROMPT-TEMPLATE` and `DEFINE-PROVIDER`, together
with the Wave 2 approved context/event accessors, are exported from
`CADR-AGENT`; after this migration the namespace is frozen, and no old nickname
or alias is provided.

The user data root is `~/.cadr/`, with agent data under `~/.cadr/agent/`
(settings, auth, models, sessions, themes, prompts, tools, bin,
extensions, crash logs), isomorphic to the baseline's `~/.pi/agent/` layout;
`~/.cadr/server/` stays at the root. `CADR_CODING_AGENT_DIR` overrides the agent
directory; for a flat installation from before goal 18, a second migration at
startup automatically renames the residents at the root into `agent/`
(preserving `0600` auth permissions; when both layouts coexist it refuses to
choose between them and reports an error; it is skipped when the override
variable is set). At startup the migration gate is entered only when the old
directory exists and the new one does not:

1. stdin must be a TTY, and the original argv must not contain `--yolo`;
2. after the user explicitly answers `y` or `yes`, the entire directory is moved
   by a same-filesystem rename;
3. the migrated `auth.json` is forced to `0600`;
4. a refusal, EOF, a non-interactive run or `--yolo` all return a configuration
   condition together with a directly executable, correctly shell-quoted manual
   `mv` command;
5. if the move or the permission fix fails, it attempts to rename the directory
   back to its original location and fails closed.

`--yolo` is still not a CLI option and does not reintroduce a tool confirmation
mechanism; the migration gate inspects the original argv only when the old
directory really is awaiting migration, which ensures it can never become an
authorization to move data.

The new configuration reads `CADR_PROVIDER`, `CADR_MODEL` and `CADR_BASE_URL`.
The old prefixes are read only in `0.1.x` as a default fallback, and every time
an old value is actually adopted a deprecation warning is printed to stderr; the
new value always wins. The compatibility entry point is deleted in `0.2.0`.
Session v1/v2 headers carry no product-name field, so reading the format needs
no alias and no rewrite logic.

## 22. North star Wave 2: harness, session v3 and process modes

Wave 2 follows the baseline's storage/repository layering: `harness-session`
depends only on the unified storage contract; memory, strict JSONL and SQLite
are replaceable adapters, and no second agent state is built. SQLite uses the
baseline's tables, indexes, `001_initial.sql` migration, WAL, FULL synchronous,
busy timeout, transactional append, branch materialization and materialized
stats. Wave 5 is still responsible only for the standalone storage package, the
server and the eval integration, and does not reimplement this adapter layer.

The new write version for coding-agent sessions is v3. The header uses an
ISO-8601 timestamp and an optional `parentSession`; the entry envelope uses
`id`, `parentId` and a timestamp, and supports message, thinking/model change,
compaction, branch summary, custom, custom message, label and session info.
Agent harness storage additionally uses the baseline's existing
`active_tools_change` and `leaf` records. The v1/v2 migration preserves unknown
fields and replaces atomically through a temporary file in the same directory;
the discovery phase scans at most 1 MiB per candidate, and skips a bad JSONL
record and a crash tail. The coding-agent manager only buffers before the first
assistant entry and does not create a file.
Compaction no longer writes the non-reference `sourceIds`; the complete original
nodes still remain in the append log, and `firstKeptEntryId` plus the parent
tree provide traceability.

The agent runtime has the baseline's steering, follow-up and next-turn queues.
Steering is injected at the start of a turn and after a complete tool batch;
follow-up drains only when the agent would otherwise stop; an abort clears the
first two but preserves next-turn. Each queue kind supports `one-at-a-time` and
`all`, and a queue event always carries a complete snapshot of both live queues.
Retry, compaction and the extension lifecycle all travel the same event spine.

Mode priority is fixed as explicit `--mode`, `--print`, explicit `--no-tui`,
automatic text for a non-TTY, and finally the TUI. Text outputs the final text
only; JSON outputs agent events line by line; RPC uses LF framing and is
compatible with CRLF, U+2028/U+2029 and a missing trailing LF. The RPC
implementation fixes the command union, the single response, event forwarding,
session control, bash/abort, EOF cleanup and the extension UI
request/response; it is the reuse boundary for the Wave 5 server, and this Wave
does not implement a server.

The bounded widening of the extension API contains only the lifecycle events,
the RPC UI surface and the runtime provider/tool/message/session actions that
already exist in the audit commit. `define-event-hook`'s original signature, the
four old events and the old result semantics are unchanged; the compatibility
gate
`LEGACY-EXTENSION-SOURCE-REMAINS-COMPATIBLE-AFTER-WAVE-2-API-EXPANSION`
freezes that. The runtime provider overlay belongs to the extension host and
does not modify the `cadr-ai` registry; the TUI component layer is likewise
unchanged. The complete events, payloads, Lisp mapping and per-item `file:line`
baseline are in
[`docs/proposals/goal-v7-extension-api.md`](proposals/goal-v7-extension-api.md).

At the Goal 7 closeout the extension export text SHA-256 was
`cc8e7d180b5007cbf4daa66ff904f8c0714992df646211c232135500efd936e7`.
Goal 8 Part B pre-adjudication 0.5(3) added the three public
`provider-request-replacement` exports along with the provider request
lifecycle, and the additive extension/native-provider API was then added with
user approval, so neither historical SHA is the current anchor any more. The
Goal 8 Part B closeout re-freeze anchor is
`e0bcbf8c5f170efb99579fe6065579a8c2e93c7f1bd590b7502b08180ba54046`,
the old-source compatibility fixture SHA-256 is
`e2548662d773edfa21ecfa3b126b2209404a2b27385e6cd48e1f145a41747442`,
the RPC wire/process fixture SHA-256 is
`6dc3a25271080a59c3380704044c435a0a20a972c5ba19f32cae2acee2649b10`,
and the UI extension fixture SHA-256 is
`c1148870a539dd4a24001da74d17f668b6092bf55d41d845319d5439e3df9486`.
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

From that point the widened surface returns to "stable on release"; a later goal
must not modify the objects above without going through human adjudication
again.

## 23. Goal 8 Wave 5: storage, server and evals

Wave 5 implements only the three separate packages that already exist in the
fixed audit commit, and does not expand the agent/extension machinery:

```text
cadr-storage -> cadr-agent -> cadr-ai
cadr-server  -> cadr-ai + external cadr --mode rpc child
cadr-evals   -> cadr-cli -> cadr-agent -> cadr-ai
```

`cadr-storage` is a standalone ASDF/package facade over the already-completed
SQLite adapter, publishing migration, the named-statement adapter, the
repository and the storage types; there is still exactly one implementation of
the data and transaction layer, and agent session state is not duplicated. It
reuses only the already-approved `cl-sqlite`/CFFI closure and adds no
dependency.

`cadr-server` aligns with the baseline's Unix-domain-socket JSONL supervisor
rather than an HTTP server. Each instance owns its own `cadr --mode rpc` child
process; the supervisor persists machine/instance records, bridges ordinary RPC,
stream events and extension UI request/response, and converges state on stop,
abnormal exit and server restart. Radius is enabled only when an existing OAuth
credential or `RADIUS_API_KEY` is available, following the credential gate; with
no credential it is entirely dormant; once enabled it backs off exponentially on
a transient failure as the baseline does, and re-registers the machine/Pi after
three consecutive 404s.

`cadr-evals` creates a real agent runtime with isolated project/agent/session
directories, requires an explicit provider/model and does not fall back
implicitly; the input admits only a prompt/reload sequence, and the output is
uniformly a transcript, usage and an optional selector. The smoke and
self-extension evals reuse that common harness; tests may use a faux provider,
and the DeepSeek/Codex credentials available in the environment go through a
FiveAM credential gate inside the separate `cadr-*/live-tests` systems with an
explicit provider/model resolver injected, reading no user settings, session or
extension. This is isomorphic to the baseline's `describe.skipIf(!KEY)`
mechanism. Provider/CLI/eval live behavior no longer has a separate shell smoke
layer; `scripts/test-live.sh` is merely a unified FiveAM entry point and
reporter, and does not duplicate test semantics.
The shell harnesses that observe only the native image, PTY/termios, Unix
sockets, cross-process migration, signals or RPC EOF are kept; their per-item
boundaries are in
`docs/acceptance/goal-v8-smoke-audit.md`.

The Wave 5 gates are fixed as:

1. schema, transactions and fork/materialized state of the standalone storage
   system;
2. single request, errors, a stale socket and RPC stream framing over a real
   Unix socket;
3. supervisor spawn/list/status/RPC/UI/stop/restart recovery;
4. explicit eval model selection, isolated cleanup, transcript/usage and
   self-extension;
5. the full CL tests, a standalone server build/smoke, and the existing `cadr`
   build/version.

Wave 5 is complete and frozen. The three packages introduce no third-party
dependency. The standalone `cadr-server` build likewise detects
`sb-core-compression` and produces an uncompressed image when it is missing;
a real Unix socket passed spawn/list/status/RPC/stop. The old
`live-evals-smoke.sh` Codex conclusion was withdrawn because it rewrote the
credential identity; the corrected real credentials are verified by the FiveAM
live gate with an explicit provider/model, while login/store/default
resolver/Codex transport are verified deterministically with a temporary
auth/config and network stubs. The final ASDF gate is
`3043 checks / 3042 pass / 1 Anthropic credential skip /
0 fail`. From this point the public surface of the three packages follows
"stable on release".

## 24. The Goal 8 Part F final freeze anchor

After the evidence correction, the production and test systems are anchored at
commit `a85b0ad321969b5fcfbda58d279d9b9c3a96209e`. Directory tree object IDs:

```text
7c6e82c496d1fead28ab0dbc2da6d5baf9d3a3c5  src/cadr-ai
4cc11551025c0d8fa61372b26653f362fd3bb81b  src/cadr-agent
1a5ba07b17cd3b0c55c8a1ec35a79d1fafda0950  src/cadr-tui
7e9377516002bd8d47f6e87a64dad08ff73eb880  src/cadr-cli
00f906f794cab3265ee9c211cb130106f2ef8d96  src/cadr-storage
b1c26416d7f496a0e807c80d0ea9578cbbdd12b2  src/cadr-server
f5b51e94a7d93680cd081d3fd259d1d4536b9009  src/cadr-evals
```

ASDF/build blob object IDs:

```text
e31b0c8d4fa963905cb5b806da53b23a9502cd0d  cadr-ai.asd
7d657fa28a05a98b7ea673ac73ff26e0bff5d923  cadr-agent.asd
c09f6172c1c186f15c726b2c04b7ea65a4f4214c  cadr-tui.asd
9798d81c340091e25e13c3149652951310962369  cadr-cli.asd
bf24fcc2be42f862c0369436fadb17c575aee430  cadr-storage.asd
2ff62e91d0ec40503544ba04380b21db0fe6ad53  cadr-server.asd
d09bb77c6c45dd4c7fc3a0d354cf589f066effd8  cadr-evals.asd
43826965957004c3b13c49d5ddd77c29b62d35b3  build.sh
892a4d77b6a38cc5b8d1bd5fb5731fb7fd9a8d2e  build.lisp
25c0804937c42b2c5170e453fe976ef318f98056  build-server.sh
3514e9f825d0d64b6e2c0663cdcf79ee94129b1c  build-server.lisp
593c7d773b13107f2f3758ccc49abc66005f941d  scripts/test-cl.sh
```

The extension export SHA that Goal 8 declared at the time,
`e0bcbf8c5f170efb99579fe6065579a8c2e93c7f1bd590b7502b08180ba54046`,
is a historical value that has since drifted, and can no longer serve as the
current freeze anchor. Goal 10 Part D's current re-frozen value is in
section 28. A change to the public surface must enter a new goal and go
through human
adjudication first; the dependency gate and the "complete means committed"
gate continue to apply globally.

## 25. The Goal 9 Part D local verification entry point

`scripts/verify.sh` is the single local entry point before a release, in a fixed
order: deterministic FiveAM, the shared `cadr`/`cadr-server` build entry points
inside a temporary work tree, the Goal 11 non-functional gates, the retained
native/process/PTY harnesses, the complete fixed-baseline render differential,
the credential-availability-gated live FiveAM, and, when available, a real
DeepSeek TUI. The isolated copy excludes Git metadata, existing binaries,
credential/test HOMEs, environment files and editor caches; a real OAuth refresh
is still handled by the existing lock and atomic write path of the canonical
`~/.cadr/agent/auth.json`.

The script reports deterministic and live results separately, and does not pass
off a real LLM result as deterministic evidence. Any item that ran and failed
makes the final exit code non-zero, but the per-item live FiveAM report and the
subsequent runnable live harnesses still complete; a missing credential merely
produces a skip with a reason. This entry point is purely local and creates no
remote CI configuration.

## 26. Goal 9 Part E versioning and repository hygiene

The root `version.sexp` is the single production version source. The eight
production ASDF systems read it through
`(:read-file-form "version.sexp")`; `cadr-ai`'s internal version helper then
distributes the same value to the CLI, the server CLI, the TUI banner, the HTTP
User-Agent and Radius registration. No new public export is added, and no
version constant is duplicated. The current release candidate is `0.2.0`;
`cadr-release-identity` composes the frozen upstream relationship from that
version source, and the CLI prints
`cadr 0.2.0 · aligned with pi v0.87.0 (+0, 16787ad5b)`. The README, the CHANGELOG
and the Release draft lock the same identity verbatim. The tag and the GitHub
Release still await user confirmation.

The repository root keeps only the current build and user entry points; the
empty TypeScript-era `packages/` directory has been deleted. The accepted Goal
9/10 texts are archived under `docs/progress/`, and local goal drafts,
Codex/Obsidian/test-home state and Python bytecode are isolated by `.gitignore`.
Documentation responsibilities are navigated from `docs/README.md`, and
milestones are maintained in the root `CHANGELOG.md`; historical reports are
still evidence and cannot override the current architecture/parity/test
contracts.

The responsibilities of the four current ledgers do not substitute for one
another: the behavior ledger `docs/parity-map.md` records observable behavior
and test evidence; the source ledger `docs/source-parity.md` gives a disposition
verdict for every source file of the fixed baseline; the non-functional ledger
`docs/performance.md` records performance, allocation, memory and stability
budgets together with same-machine baselines; the presentation ledger
`docs/presentation-parity.md` records user-visible copy, semantic styling,
geometry, formatting and truncation item by item. `examples/manifest.sexp` is
merely a machine-readable auxiliary inventory of 99 runnable examples, not a
fifth ledger. Goal 12's source/example completeness is still cross-checked by
the existing `GOAL12_LEDGER` identity; the presentation ledger additionally
locks the B1-B4 denominator and disposition totals under the
`GOAL13_PRESENTATION_LEDGER` identity.
A future upgrade must first run `scripts/check-source-parity-drift.sh`; adding,
deleting or renaming any source file requires an explicit human disposition in
the TSV, and a missing or stale entry fails closed; the complete process is in
`docs/source-parity-upgrade.md`.

## 27. The Goal 11 non-functional acceptance axis

Behavior parity and non-functional properties are two independent gates. The
former requires byte-for-byte equivalence of payload, session, events, tool
results, JSON/RPC and terminal snapshots; the latter requires that the same
output show no order-of-magnitude regression in time, allocation, resident
memory and resource lifetime under a fixed load. Passing either axis cannot
offset a failure on the other.

The measurement entry points are two-layered:

1. `scripts/bench.sh` measures steady frame, key→frame, stream delta, append,
   heap/RSS and native-image cold start on a fixed 100×40 virtual terminal, with
   five fixed mixed entry kinds and N ∈ {0,50,200,1000,5000};
2. `scripts/goal11-stability.sh` drives a real agent, a v3 session, TUI event
   projection and per-event rendering with a production faux provider, and
   simulates 1200 turns / 10 hours; it additionally measures load/resume/continue
   latency and sampled heap/RSS peak on a real ≥10MiB JSONL file.

Part C adopts only the component cache and the array-style O(1) append that
already exist in the fixed TS baseline; Part D further restores the same
strategy for appending agent messages and session entries.
No viewport pruning, virtual scrolling, transcript memoization or
behaviorally-visible truncation was introduced. When a public list is replaced
wholesale, the private tail is repaired exactly once on the next append; the
session wire and the agent events are unchanged.

`scripts/goal11-performance-gate.py` is the single threshold judge for the
machine-readable report, and is invoked by `scripts/verify.sh` after the
isolated build and before the process/PTY harnesses. The 50ms frame,
20 delta/s, append exponent 0.35, 750ms cold start, 1200-turn heap exponent
1.30, 500ms full GC and 10MiB session 5s thresholds all leave more than 12× of
headroom on the dominant latencies relative to the current measurements, yet
they reliably fail the pre-optimization 466–488ms frame, 2.15 delta/s and
linear append. The method, the complete data and the reasoning behind each
threshold are maintained in `docs/performance.md`.

## 28. Goal 10 Part D Lisp-native capabilities

This section is an explicit human-adjudicated exception to the global "no
mechanism may be added by default" principle, and covers only the two
capabilities in the approved proposal; it does not authorize any other mechanism
by analogy.

When a tool executor or schema validation fails, the core establishes a
`tool-execution-error` and three dynamic restarts while the original stack is
still alive: `retry-tool-call` re-runs from `:tool-call-before` with a new JSON
object and revalidates, `skip-tool-call` produces an error result with the old
copy, and `abort-agent-run` commits the error result first and then goes through
the existing abort. Each logical call produces start/after/end exactly once;
`:tool-call-error` appears only inside the extension lifecycle of each failed
attempt, and does not enter the agent events, the session, the JSON or the RPC
wire. When no hook makes a choice, the original error result is kept, and the
default print/JSON/RPC/TUI behavior is unchanged.

`:tool-call-error` is the 34th member of the complete extension event set. Its
payload is fixed as
`condition/tool-call/arguments/attempt/restart-names`; arguments is deep-copied,
and the only legal returns are the three actions retry/skip/abort. After the
additive runtime/OAuth bridges approved in Goal 12 were ledgered, the current
extension export SHA-256 is
`61eb1b623f784b3a8f0f6fe6791c65ebe991ff314ed1d969b82f3edd57646f18`; the
34-event source block SHA-256 is
`12f79b21e0e25495cb023baaf21b26f6cf9a891881b26602f6553f80af54887a`.
Adding an event or changing restart semantics in the future still requires a
written proposal and per-item user approval.

`--slynk <port>` is the only enabling entry point, the port must be decimal
`1..65535`, and the call is fixed as
`slynk:create-server :interface "127.0.0.1" :style :spawn :dont-close t`.
Configuration and environment variables cannot enable it silently, and a bind
failure is fatal; on exit the listener is closed and
`cadr-cli:active-agent` is cleared. Loopback is not a sandbox; cross-machine
access is up to the user to establish through an SSH tunnel, and strong
isolation is still the responsibility of a container, a virtual machine or a
restricted user account.

The re-frozen implementation object IDs and the test evidence are listed in full
in
[`docs/acceptance/goal-v10-part-d.md`](acceptance/goal-v10-part-d.md).

## 29. Goal 12 extension baseline completion

Goal 12 F/G/H fills in capabilities the baseline already has, and adds no
Cadr-specific mechanism. The production compaction path constructs a preparation
after selecting the source/kept entries, and emits `:session-before-compact`
with a manual, threshold or overflow reason; a valid extension result and its
metadata enter the session verbatim, a cancel/abort writes no compaction, and an
invalid or failing handler falls back to the original summarizer. Exactly one
`:session-compact` is emitted after a successful persist. The real emission
points of the 34 extension events and their called-regressions are frozen item
by item by
[`docs/acceptance/goal-v12-extension-event-dispatch.md`](acceptance/goal-v12-extension-event-dispatch.md);
exactly one existing declaration was found to be unwired, and it was fixed.

The agent stores the real system prompt and the eight-field options that
construct it. The CLI and the SDK share the same options shape, and every
`:before-agent-start` handler receives an independent deep copy; a reload
atomically replaces both the prompt and the options. Extension HTTP is a
session-local callback on the host and is not written into the `cadr-ai` global
registry: the public layer validates and copies the request/response, and the
CLI adapter reuses the existing native HTTP transport and converges timeout,
abort and transport failure into secret-free extension errors.
With no callback, the API is explicitly unavailable; the default provider,
OAuth, session, event, JSON/RPC wire and TUI contracts are unchanged.

All 99 runnable examples of the fixed baseline now have a functionally
equivalent Lisp port. The source ledger finally reads
`595/523/72/0`: all 595 baseline source files have a disposition, with no
deferred and no missing item. The current extension export
SHA-256 is re-frozen at
`61eb1b623f784b3a8f0f6fe6791c65ebe991ff314ed1d969b82f3edd57646f18`; the 34-event
block SHA-256 is still
`12f79b21e0e25495cb023baaf21b26f6cf9a891881b26602f6553f80af54887a`.

The Apple Terminal path aligns directly with the baseline's system API: only on
macOS, with `TERM_PROGRAM=Apple_Terminal`, and only on receiving Return, it
reads the Shift mask of CoreGraphics `CGEventSourceFlagsState` through SBCL FFI,
and then normalizes Shift+Enter into the CSI-u `ESC[13;2u`. A framework load, a
query, or a failure on an unsupported architecture all fail
closed; the non-Apple-Terminal and non-Return paths do not query the native
state, and the input bytes are unchanged.
This implementation uses only the CoreGraphics that ships with macOS, and adds
no ASDF dependency, third-party library or external binary. This machine has no
macOS/Apple Terminal, so the verification level is fixture
cross-implementation comparison, and no live verification is claimed.

## 30. The Goal 12 source drift gate

A baseline upgrade runs `scripts/check-source-parity-drift.sh` first. It uses
the same source predicate as Part A to compare two commits, enumerates
additions, deletions and renames, and requires a non-empty human disposition for
each in a four-column TSV; a missing, stale or malformed disposition, or an
unknown revision, always fails. A modified file must still go through behavior
and source review, and cannot be waved through by the path gate.

`scripts/test-source-parity-drift.sh` locks A/D/R, test-file exclusion,
undispositioned failure and full-disposition success against a temporary Git
repository; it also feeds the real `docs/source-parity.md` into the same parser
and requires exactly the 595 rows the Summary declares, a path-set SHA-256
consistent with the ledger manifest, and it fails closed on prose ignores, a bad
separator/row, a duplicate path and a wrong total. The path digest contains only
the UTF-8 path plus a single LF, and forces `LC_ALL=C` byte ordering, so that
the host locale's collation cannot be inherited.
`--ledger-only` is the explicit mode for a shallow clone that does not contain
the detached baseline objects; the ordinary revision mode continues to compare
each ledger path against the `--from` tree. `scripts/verify.sh` runs the real
ledger gate before the build, and then the synthetic drift self-test, which must
not prevent the real input from being driven. After an upgrade, the behavior
ledger `docs/parity-map.md`, the source ledger `docs/source-parity.md`, the
non-functional ledger `docs/performance.md` and the presentation ledger
`docs/presentation-parity.md` must each be re-reviewed; the auxiliary inventory
`examples/manifest.sexp` must be updated in step as well. The deterministic gate
recomputes the example count from the manifest, cross-checks the existing
`GOAL12_LEDGER` source/example identity, and independently cross-checks the
presentation ledger's
`GOAL13_PRESENTATION_LEDGER` denominator and disposition totals; any drift
fails.

## 31. The Goal 14 code organization contract

The four parity axes answer "is the implementation correct": behavior, source
disposition, non-functional properties and presentation, none of which may be
substituted by another. `docs/code-organization.md` answers a different
question — whether the current responsibility boundaries are clear enough, and
whether a developer can keep adding features without writing the same policy by
hand a second time. It is not a fifth parity ledger, and it cannot change any
fixed-baseline conclusion.

Goal 14 converged the cross-system policies that carry no product semantics into
the leaf system `cadr-core`: bounded thread cleanup, component-local
cancellation, atomic file replacement, redacted object printing and UTC time.
Domain policies such as the selector frame, infrastructure output, provider
identity/auth metadata and the JavaScript UTF-16 count are still held by their
own domain owners. Production package exports, the extension export/event SHAs,
the session/payload/wire and every user-observable behavior are unchanged by the
organizational refactor.

`scripts/check-code-organization.py` scans the real `src/` before the
`verify.sh` build. Part A's 277-file histogram places 15 files in the audited
`>=1000`-line outlier band, which makes that band the human-review boundary;
every hit must carry a per-path reason in
`docs/code-organization-exemptions.json`. The gate simultaneously rejects
unregistered large files, duplicate/empty reasons and stale exemptions, and
verifies its fail-closed behavior with synthetic fixtures.

This line-count check detects a surface symptom only: passing does not mean the
organization is good, and failing means only that the responsibility must be
explained — files must not be split mechanically just to pass the gate. The
stronger gate is the behavior and source anti-bypass test of each converged
primitive. From now on, every goal that adds production code must state, before
work starts, where the new code belongs and which existing primitive it reuses,
or explain why a genuinely new independent decision is required; being under
1000 lines does not exempt a file from that judgement.

## 32. Goal 15: the fixed-baseline render differential

`scripts/render-diff.py gate` archives pi from the fixed-baseline commit object
kept in this repository, uses the hydrated cache corresponding to the immutable
marker, and takes a fresh capture of each of the manifest's 21 scenarios in both
the wide and the narrow size. Each side drives the real composition root through
a real PTY and a native faux provider; the complete raw bytes, the SHA-256, the
checkpoints and the normalized derivative are each stored separately. Only
user-approved value substitutions confined to exact delimiters enter
normalization; whitespace, ANSI, colour, cursor, order, whole lines and
unbounded numbers are not normalized, and the raw bytes and the SHA remain the
authoritative evidence.

The scenario domain itself also fails closed: `reachable-interfaces.json`
registers the fixed baseline's 22 slash commands, 28 reachable interface states,
22 source construction sites across 15 constructor kinds, and Cadr's 13 overlay
kinds; the fixed-baseline set is first cross-validated against
`baseline-interface-inventory.json`; a source archive without `.git` uses that
audited snapshot, while a real repository must additionally agree with the fixed
commit object; Cadr overlay kinds are always extracted from the current source.
Outside the interface closure, the checker independently fixes seven salient
states of bash: line/byte/single-line truncation, empty output, non-zero exit,
timeout and a parallel tool batch; each must register a baseline token, a
deterministic trigger and a real capture, or register a non-empty reason for not
capturing, and there are currently zero exemptions. These sets are cross-checked
in both directions against the 89 checkpoints.
Adding a command, constructor, construction site or overlay kind, leaving any
second- or third-level interface without a real capture, and deleting a required
salient state or invalidating its capture all fail before analyze, and can no
longer be quietly missed by hand-picking scenarios.

The analyzer replays the unmodified raw stream through tmux, compares the
terminal-semantic screen at each checkpoint, and fail-closed validates
`test/fixtures/render-diff/dispositions.json`: a new difference with no
disposition, a stale disposition, a duplicate, or a baseline-commit mismatch all
fail. I01 preserves the original scheduling bytes and distinguishes scheduler
segmentation by self-replay; I02 is a formally adjudicated fatal-output safety
difference. The `fixed-baseline render differential` stage of `scripts/verify.sh`
runs the complete capture plus analyze directly, and does not read a historical
capture and pass it off as current evidence.

This is the only standing gate whose oracle is the actual rendered output of the
fixed pi. The behavior, source, non-functional and presentation ledgers all
maintain the contract from the Cadr implementation side, and on their own cannot
discover a "test reverse-engineered from a wrong implementation" problem; the
render differential is a cross-implementation oracle, is not a fifth ledger, and
cannot substitute for the four axes' audit of payloads, source capabilities,
long-run performance and interactions no script covers. A future baseline
upgrade must update the commit in both the manifest and the dispositions, re-run
the complete matrix and adjudicate every new difference item by item; the
process is in `docs/source-parity-upgrade.md`.

## 33. Goal 16: the product identity boundary

Product identity is owned at a single point by the private constant group in
`src/cadr-ai/support/release.lisp`: the slug, the display name, the canonical
repository URL and the default share viewer. The CLI, the server, provider
attribution and the export path may only derive from that owner, and must not
duplicate a product string; environment variables and configurable endpoints
stay with their own feature owners, but accept only the `CADR_*` contract.

`/share` produces `https://cadr.dev/session/#<gist-id>` by default, a non-empty
`CADR_SHARE_VIEWER_URL` and an explicit argument can override it, and a success
states the viewer address explicitly. The link being unreachable before the page
is deployed is a transitional state the user knowingly accepted, and it triggers
neither a rollback nor an extra fallback. The version check has no default
network endpoint: only when `CADR_VERSION_CHECK_URL` is non-empty does it
request a Cadr-compatible release; this fixes the product-semantics error of
comparing pi `0.83.x` with Cadr `0.2.x`.

The 14 production `PI_*` environment names have been hard-switched to exact
`CADR_*` mappings, with no alias, no warning and no old-name fallback. Radius's
`pi-gateway`, `radius.pi.dev`, `pis/*`,
`radiusPiId` and `pi-messages`, the extension manifest's `"pi"` key, and the
catalog, the fixed baseline, historical announcements and the `aligned with pi`
statement are external contracts or provenance, not Cadr calling itself pi. The
Goal 16 Part D identity gate protects that boundary with a per-path, per-fixed-
text, per-reason allowlist; a directory-level exemption is illegal, and the
number of hits in the real tree must agree with the manifest.
