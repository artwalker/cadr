# GOAL: rewrite the Pi Agent Harness as a Common Lisp implementation

## 1. Overall goal

Completely reimplement the pi coding agent in the https://github.com/earendil-works/pi repository in Common Lisp (SBCL), and ultimately deliver **a coding agent executable that runs in a terminal and whose functionality is aligned with the baseline's core capabilities**.

The baseline TypeScript project is the reference implementation. This is not a line-by-line translation; it is a redesign in idiomatic Lisp style, while guaranteeing that the external behavior (API request construction, agent loop semantics, tool-call protocol) is consistent with the baseline.

## 2. Scope

### To implement (in dependency order)

1. **The pi-ai counterpart layer** (`packages/ai`): a unified multi-vendor LLM API wrapper
   - support the three providers Anthropic, OpenAI and Google (the remaining providers may be deferred)
   - request construction, streaming SSE response parsing, token usage accounting, error normalization
2. **The pi-agent-core counterpart layer** (`packages/agent`): the agent runtime
   - the agent main loop (user input → LLM call → tool call → result returned → loop)
   - the tool definition and registration mechanism (including JSON Schema argument validation)
   - session state management and persistence (sessions can be saved/restored)
3. **The coding-agent CLI counterpart layer** (`packages/coding-agent`):
   - built-in tools: read / write / edit / bash / glob / grep (aligned with the behavioral semantics of the baseline's built-in tools)
   - configuration system: API key reading (environment variables), model selection, system prompt
   - the first version's interactive interface is built as a **REPL-style command line**: readline input, streaming plain-text output, multi-turn conversation supported
   - **before every execution of a side-effecting tool such as bash / write / edit, ask the user for confirmation** (the baseline has no permission system; this is a safety improvement that this rewrite requires be added; a --yolo flag is provided to skip the confirmation)

### Explicitly excluded (do not do)

- pi-tui's differential-rendering full-screen TUI — not in the first version; REPL-style interaction is enough
- pi-chat (Slack integration), any Web UI, anything related to vLLM pods
- the baseline's extension/skill/package install system — not in scope for the first version

## 3. Technical constraints

- Language and runtime: **Common Lisp, with SBCL as the target implementation** (>= 2.4), ultimately producing a single native executable via `sb-ext:save-lisp-and-die` or an equivalent
- Build system: ASDF, with dependencies managed by Quicklisp; provide a one-command `build.sh` build script
- Recommended libraries (they may be replaced according to the actual situation, but the reason must be explained in the design document):
  - HTTP/streaming: dexador (note that SSE requires stream-based chunked reading and must not wait for the complete response)
  - JSON: com.inuoe.jzon
  - concurrency: bordeaux-threads
  - CLI arguments: clingon or adopt
- Error handling uses the CL condition system to design layered error types (network errors / API errors / tool-execution errors can be distinguished and retried)
- Code style: each baseline TS package corresponds to one CL system (such as `pi-ai`, `pi-agent`, `pi-cli`), with a clear package structure and explicit exported symbols

## 4. Execution requirements (important)

1. **Produce the design document before writing code**: the first deliverable is `docs/architecture.md`, containing the TS module → CL system/package mapping table, the plan for handling the asynchronous model (how TS Promise/async maps onto threads or synchronous streams), and the error-handling design. Pause when it is finished and wait for human confirmation before continuing.
2. **Tests first**: for each module, first port the semantics of the corresponding test cases from the baseline repository into CL tests (with fiveam or rove), then implement the functionality to make the tests pass. The baseline's tests are the behavior specification, not an option.
3. **Advance in stages, with a runnable artifact at every stage**; skipping a stage is not allowed:
   - Phase 1: the pi-ai layer — deliver a library that can issue non-streaming and streaming conversation requests to the three providers, plus tests
   - Phase 2: the agent core — deliver a library that can run the complete "LLM decides to call a tool → execute → return the result → continue" loop, plus tests (the tools may use mocks at first)
   - Phase 3: built-in tools + CLI — deliver a runnable REPL agent that can carry out "read a file, change code, run a command" style tasks in a real project directory
   - Phase 4: polish — session persistence, the confirmation mechanism, error retry, the build script, README
4. **Cross-implementation comparison verification**: for API request construction, generate the request body from the same input in the baseline TS implementation and in the CL implementation separately, and compare field by field (a cross-implementation comparison script may be written). SSE parsing is tested by replaying recorded real response streams, without depending on an online API.
5. At the end of each Phase, emit a short progress report: what was completed, known differences from the baseline's behavior, and the plan for the next step.

## 5. Acceptance criteria (the final delivery must satisfy all of them)

1. `./build.sh` can produce the executable `pi-cl` with one command in a clean Linux x64 environment (with SBCL and Quicklisp installed)
2. after setting `ANTHROPIC_API_KEY`, running `./pi-cl` allows multi-turn streaming conversation
3. in a real small code repository, natural-language instructions can accomplish: reading a specified file and summarizing it, modifying some function, running a test command and continuing to fix based on the output — the complete agent loop without human intervention (except tool confirmation)
4. each of the three providers (Anthropic / OpenAI / Google) has at least one end-to-end test that passes (recorded replay may substitute for the real API)
5. all ported tests pass; `docs/architecture.md` is consistent with the final implementation
6. side-effecting tools require user confirmation by default, and `--yolo` may skip it
7. a session can be restored with `--continue` to the previous conversation
8. README contains: how to build, how to configure, and the list of functional differences from the baseline pi

## 6. Known risks and handling principles

- SSE stream parsing is the part most prone to error: each provider's event format differs, so recorded real responses must serve as the test benchmark
- where the baseline's behavior is unclear, the actual behavior of the baseline source is authoritative; do not invent semantics on your own; when it cannot be determined, record it in `docs/open-questions.md`, pause and ask
- do not pile up unverified code for the sake of "completeness"; a small scope that all runs is preferable
