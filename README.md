# cadr

`cadr` is a native Common Lisp coding agent for SBCL, behaviorally aligned
with the original pi while remaining idiomatic Lisp.

The name has two meanings: `cadr` selects the second element of a list, and
this project is a second implementation of pi; it also pays tribute to the MIT
CADR Lisp Machine.

## Relationship to pi

Behavior is pinned to
[`earendil-works/pi@71efc6f0c1909874ec8c944637a9ae7fc0e2d508`](https://github.com/earendil-works/pi/tree/71efc6f0c1909874ec8c944637a9ae7fc0e2d508).
That implementation and its tests are the behavioral reference for provider
payloads, streaming events, agent-loop semantics, tools, sessions, extensions,
and terminal interaction.

Thanks to the pi authors and contributors for the design and reference
implementation. `cadr` is an independent project and has no affiliation with
the original pi project or its maintainers. Both projects use the MIT License;
see [LICENSE](LICENSE).

## Build

Requirements:

- Linux x64
- SBCL 2.4 or newer
- Quicklisp
- system OpenSSL development/runtime libraries

```bash
QUICKLISP_SETUP="$HOME/quicklisp/setup.lisp" ./build.sh
./cadr --version
```

The build produces the native executable `./cadr`. If SBCL lacks
`sb-core-compression`, the build emits an uncompressed image instead of
failing.

## Configuration

Provider credentials:

| Provider | Environment variable | Default model |
|---|---|---|
| Anthropic | `ANTHROPIC_API_KEY` | `claude-opus-4-8` |
| OpenAI | `OPENAI_API_KEY` | `gpt-5.5` |
| Google | `GEMINI_API_KEY` | `gemini-3.6-flash` |
| DeepSeek | `DEEPSEEK_API_KEY` | `deepseek-v4-flash` |
| Ollama | none | `gpt-oss:20b` |

Selection overrides:

```bash
CADR_PROVIDER=deepseek
CADR_MODEL=deepseek-v4-flash
CADR_BASE_URL=https://api.deepseek.com
```

Equivalent command-line options are `--provider`, `--model`, and
`--base-url`. Per-provider settings may also be stored in
`~/.cadr/config.json`:

```json
{
  "providers": {
    "deepseek": {
      "model": "deepseek-v4-flash",
      "base-url": "https://api.deepseek.com"
    }
  }
}
```

## Usage

```bash
./cadr
./cadr --provider deepseek
./cadr --continue
./cadr --resume <session-id>
./cadr --no-tui
```

Interactive terminals use the full-screen TUI; pipes and non-TTY input fall
back to the line REPL. Both frontends share one command, session, extension,
and agent-event path.

Sessions are parent-linked JSONL trees under `~/.cadr/sessions/`. Commands
include `/sessions`, `/switch`, `/branch`, `/compact`, `/export`, `/login`,
`/logout`, `/reload`, and `/install`.

### OAuth

Start `./cadr --provider openai`, then enter:

```text
/login openai
```

The PKCE callback listens once on `127.0.0.1:1455`. Credentials are stored in
`~/.cadr/auth.json` with mode `0600`; refresh is locked per provider and token
values are redacted from transport, API, assistant, and condition output.
`/login anthropic` implements the same abstraction but has not been live
verified because no Claude subscription account was available. Subscription
OAuth channels may be restricted by provider terms to official clients; use
from this third-party client is at the user's risk.

## Migration from the old namespace

This is the single allowed namespace break:

| Old | New |
|---|---|
| `pi-ai` | `cadr-ai` |
| `pi-agent` | `cadr-agent` |
| `pi-cli` | `cadr-cli` |
| `pi-tui` | `cadr-tui` |
| `pi-cl` | `cadr` |
| `~/.pi-cl/` | `~/.cadr/` |
| `PI_CL_*` | `CADR_*` |

At startup, when `~/.pi-cl/` exists and `~/.cadr/` does not, an interactive
terminal offers to move the complete directory. The operation is a rename,
not a copy, and enforces mode `0600` on the migrated `auth.json`.
Non-interactive startup refuses automatic migration and prints an exact
manual `mv` command. `--yolo` never authorizes migration and remains
unsupported by the core CLI.

Legacy `PI_CL_PROVIDER`, `PI_CL_MODEL`, and `PI_CL_BASE_URL` remain readable
through the `0.1.x` transition release with a deprecation warning. Support is
removed in `0.2.0`; new configuration must use `CADR_PROVIDER`, `CADR_MODEL`,
and `CADR_BASE_URL`.

## Lisp extensions

Extensions are an `extension.lisp` file or a directory containing one.
Discovery order is:

1. repeatable `--extension <path>` entries, last entry winning;
2. `./.cadr/extensions/`;
3. `~/.cadr/extensions/`.

The stable extension interface is now frozen in `CADR-AGENT`. These exported
macros will not be renamed again:

- `define-tool`
- `define-command`
- `define-event-hook`
- `define-prompt-template`

Example:

```lisp
(define-tool "echo"
  :description "Return text"
  :parameters
  (cadr-ai::json-object
   "type" "object"
   "properties"
   (cadr-ai::json-object
    "text"
    (cadr-ai::json-object "type" "string"))
   "required" (vector "text")
   "additionalProperties" nil)
  :handler
  (lambda (call-id arguments context)
    (declare (ignore call-id context))
    (values
     (list
      (cadr-ai:make-text-content
       :text (cadr-ai::json-get arguments "text")))
     nil)))
```

## Security model

Like original pi, `cadr` executes validated tool calls directly by default.
There is no built-in approval dialog and no core `--yolo` mode. Strong
isolation is the user's responsibility; run untrusted repositories and
extensions inside a container or equivalent sandbox.

Users who want approval can implement it without changing the core through a
`:tool-call-before` hook:

```lisp
(define-event-hook :tool-call-before
  :handler
  (lambda (event context)
    (declare (ignore context))
    (let* ((call (cadr-agent:extension-event-tool-call event))
           (name (cadr-ai:tool-call-name call)))
      (format *query-io* "~&Run tool ~A? [y/N] " name)
      (finish-output *query-io*)
      (unless
          (member
           (string-downcase (or (read-line *query-io* nil) ""))
           '("y" "yes")
           :test #'string=)
        (cadr-agent:make-extension-hook-result
         :block-p t
         :reason "Rejected by user")))))
```

Extensions are arbitrary in-process Common Lisp. Package isolation prevents
accidental name collisions; it is not a security boundary.

## Differences from TypeScript pi

- The implementation language and runtime are Common Lisp and SBCL.
- The build produces an SBCL native image through ASDF and Quicklisp instead
  of using the TypeScript/Bun toolchain.
- Extensions are Lisp packages and forms rather than JavaScript modules and
  npm packages.

No additional core safety, approval, orchestration, or policy mechanism is
introduced. Proposed mechanisms beyond original pi belong in
[`docs/open-questions.md`](docs/open-questions.md) until manually approved.

## Verification

```bash
./scripts/test-cl.sh
./build.sh
./scripts/acceptance-smoke.sh
./scripts/migration-smoke.sh
./scripts/live-deepseek-smoke.sh
./scripts/live-extension-smoke.sh
CADR_ALLOW_LIVE_TOOL_SMOKE=1 ./scripts/live-repo-smoke.sh
./scripts/live-tui-smoke.sh
./scripts/live-openai-oauth-smoke.sh
npm run check
```

Detailed coverage is in [docs/test-matrix.md](docs/test-matrix.md).
Migration evidence and the exact residual-name exemptions are in
[docs/progress/migration.md](docs/progress/migration.md).

## License

MIT. See [LICENSE](LICENSE).
