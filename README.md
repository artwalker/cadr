<p align="center">
  <a href="https://shittycodingagent.ai">
    <img src="https://shittycodingagent.ai/logo.svg" alt="pi logo" width="128">
  </a>
</p>
<p align="center">
  <a href="https://discord.com/invite/3cU7Bz4UPx"><img alt="Discord" src="https://img.shields.io/badge/discord-community-5865F2?style=flat-square&logo=discord&logoColor=white" /></a>
  <a href="https://github.com/badlogic/pi-mono/actions/workflows/ci.yml"><img alt="Build status" src="https://img.shields.io/github/actions/workflow/status/badlogic/pi-mono/ci.yml?style=flat-square&branch=main" /></a>
</p>
<p align="center">
  <a href="https://pi.dev">pi.dev</a> domain graciously donated by
  <br /><br />
  <a href="https://exe.dev"><img src="packages/coding-agent/docs/images/exy.png" alt="Exy mascot" width="48" /><br />exe.dev</a>
</p>

> New issues and PRs from new contributors are auto-closed by default. Maintainers review auto-closed issues daily. See [CONTRIBUTING.md](CONTRIBUTING.md).

---

# Pi Monorepo

> **Looking for the pi coding agent?** See **[packages/coding-agent](packages/coding-agent)** for installation and usage.

Tools for building AI agents and managing LLM deployments.

## Share your OSS coding agent sessions

If you use pi or other coding agents for open source work, please share your sessions.

Public OSS session data helps improve coding agents with real-world tasks, tool use, failures, and fixes instead of toy benchmarks.

For the full explanation, see [this post on X](https://x.com/badlogicgames/status/2037811643774652911).

To publish sessions, use [`badlogic/pi-share-hf`](https://github.com/badlogic/pi-share-hf). Read its README.md for setup instructions. All you need is a Hugging Face account, the Hugging Face CLI, and `pi-share-hf`.

You can also watch [this video](https://x.com/badlogicgames/status/2041151967695634619), where I show how I publish my `pi-mono` sessions.

I regularly publish my own `pi-mono` work sessions here:

- [badlogicgames/pi-mono on Hugging Face](https://huggingface.co/datasets/badlogicgames/pi-mono)

## Packages

| Package | Description |
|---------|-------------|
| **[@mariozechner/pi-ai](packages/ai)** | Unified multi-provider LLM API (OpenAI, Anthropic, Google, etc.) |
| **[@mariozechner/pi-agent-core](packages/agent)** | Agent runtime with tool calling and state management |
| **[@mariozechner/pi-coding-agent](packages/coding-agent)** | Interactive coding agent CLI |
| **[@mariozechner/pi-mom](packages/mom)** | Slack bot that delegates messages to the pi coding agent |
| **[@mariozechner/pi-tui](packages/tui)** | Terminal UI library with differential rendering |
| **[@mariozechner/pi-web-ui](packages/web-ui)** | Web components for AI chat interfaces |
| **[@mariozechner/pi-pods](packages/pods)** | CLI for managing vLLM deployments on GPU pods |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines and [AGENTS.md](AGENTS.md) for project-specific rules (for both humans and agents).

## Development

```bash
npm install          # Install all dependencies
npm run build        # Build all packages
npm run check        # Lint, format, and type check
./test.sh            # Run tests (skips LLM-dependent tests without API keys)
./pi-test.sh         # Run pi from sources (can be run from any directory)
```

> **Note:** `npm run check` requires `npm run build` to be run first. The web-ui package uses `tsc` which needs compiled `.d.ts` files from dependencies.

## License

MIT

## Common Lisp port: `pi-cl`

This repository also contains the SBCL reimplementation specified in
[`goal.md`](goal.md) and [`goal2.md`](goal2.md). Phases 5–9 add a provider
registry, OpenAI Chat Completions, DeepSeek/Ollama, images, model pricing,
OAuth, parent-linked sessions with automatic compaction, Lisp extensions, and
a pure Common Lisp terminal UI.

### Build

Requirements: Linux x64, SBCL 2.4 or newer, and Quicklisp. The build runs all
Common Lisp tests before producing the native executable:

```bash
./build.sh
./pi-cl --help
```

Quicklisp defaults to `~/quicklisp/setup.lisp`; override it when needed:

```bash
QUICKLISP_SETUP=/opt/quicklisp/setup.lisp ./build.sh
```

SBCL builds without core compression are supported. `build.sh` prints a
degradation notice and emits an uncompressed `pi-cl` instead of failing.

### Configure and run

Set one provider key, then start the TUI:

```bash
export ANTHROPIC_API_KEY=...
./pi-cl
```

Interactive stdin/stdout use the TUI by default. `--no-tui` forces the
line-oriented REPL, and non-TTY pipes fall back to it automatically. In the
TUI, Enter submits, Shift+Enter inserts a newline, Ctrl+O expands or collapses
the latest tool result, Ctrl+C aborts the active request, and Ctrl+D exits.
`/model` and `/sessions` open searchable selectors.

After building, the credential-gated two-turn streaming smoke is:

```bash
./scripts/live-anthropic-smoke.sh
```

The live repository repair smoke runs only inside a temporary fixture
repository and requires a second explicit opt-in:

```bash
PI_CL_ALLOW_LIVE_TOOL_SMOKE=1 ./scripts/live-repo-smoke.sh
```

It uses DeepSeek and verifies an observed test failure, a code edit, and a
passing rerun.

Supported keys and default models:

| Provider | Environment variable | Default model |
|---|---|---|
| Anthropic | `ANTHROPIC_API_KEY` | `claude-opus-4-8` |
| OpenAI | `OPENAI_API_KEY` | `gpt-5.5` |
| Google | `GEMINI_API_KEY` | `gemini-3.6-flash` |
| DeepSeek | `DEEPSEEK_API_KEY` | `deepseek-v4-flash` |
| Ollama | none | `gpt-oss:20b` |

DeepSeek uses `/v1/chat/completions`; Ollama defaults to
`http://localhost:11434/v1/chat/completions`. Use `--provider`, `--model`,
`--base-url`, or `--system-prompt` to override selection. Provider inference
prefers Anthropic, OpenAI, Google, then DeepSeek. Per-provider configuration is
also accepted in `~/.pi-cl/config.json`:

```json
{
  "providers": {
    "deepseek": {
      "model": "deepseek-v4-pro",
      "base-url": "https://api.deepseek.com"
    }
  }
}
```

CLI values override environment/config values, which override registry
defaults. Sessions are stored as append-only JSONL v2 trees under
`~/.pi-cl/sessions/`; `./pi-cl --continue` restores the newest session for the
current canonical working directory, while `./pi-cl --resume <id>` restores an
exact session.

Each message has an id and parentId. These REPL commands operate on the tree:

```text
/sessions
/switch <session-id>
/branch <entry-id>
/compact
/export [path]
```

Branching moves the active leaf without deleting the abandoned path. Near the
model context limit, pi-cl uses the current model to summarize older context,
stores a compaction node with references to every summarized node, and keeps
the original history in the JSONL file. A provider-reported context overflow
gets one compact-and-retry attempt.

The static catalog includes context/output limits, capabilities, and
per-million-token prices. Refresh it from the public model catalog with:

```bash
sbcl --script scripts/refresh-model-catalog.lisp
```

Programmatic `pi-ai` callers may use `image-content`; Anthropic, OpenAI
Responses, OpenAI Chat Completions, and Google receive their native base64
formats. Text-only models reject images explicitly.

### OAuth

Start `./pi-cl --provider openai`, then enter:

```text
/login openai
```

The browser PKCE flow listens once on `127.0.0.1:1455`, stores tokens in
`~/.pi-cl/auth.json` with mode `0600`, and uses the OpenAI Codex Responses
endpoint and headers from the fixed reference implementation. `/logout openai`
removes it. Stored credentials take precedence over environment keys; expiring
tokens refresh under a provider lock.

`/login anthropic` implements the same abstraction but is **not live
verified**, because no Claude subscription account was available. Subscription
OAuth channels are commonly restricted by provider terms to official clients;
using either subscription channel from this third-party client is at the
user's risk.

Credential-gated Phase 5 smoke tests are:

```bash
./scripts/live-deepseek-smoke.sh
./scripts/live-openai-oauth-smoke.sh
```

### Lisp extensions

Extensions are a `.lisp` file or a directory containing `extension.lisp`.
They load from the following sources, in descending precedence:

1. repeatable `--extension <path>` options, with the last option winning;
2. `./.pi-cl/extensions/`;
3. `~/.pi-cl/extensions/`.

Each extension loads in an isolated Common Lisp package and may register tools,
commands, lifecycle hooks, and prompt templates:

```lisp
(define-tool "echo"
  :description "Return text."
  :parameters
  (pi-ai::json-object
   "type" "object"
   "properties"
   (pi-ai::json-object
    "text" (pi-ai::json-object "type" "string"))
   "required" (vector "text")
   "additionalProperties" nil)
  :handler
  (lambda (call-id arguments context)
    (declare (ignore call-id context))
    (values
     (list
      (pi-ai:make-text-content
       :text (pi-ai::json-get arguments "text")))
     nil)))
```

The stable API is `define-tool`, `define-command`, `define-event-hook`,
`define-prompt-template`, the documented extension context/event accessors,
and `make-extension-hook-result`. Prompt templates support `$1`, `$@`,
`$ARGUMENTS`, defaults, and argument slices; names beginning with `skill:`
are Lisp skills.

Use `/reload` after editing extensions. A failed reload keeps that extension's
last-known-good generation while allowing unrelated extensions to update.
`/install <git-url>` clones a package into the global extension directory;
only explicit network Git URLs are accepted and existing destinations are
never overwritten. The deterministic and live self-extension checks are:

```bash
./scripts/test-cl.sh
./scripts/live-extension-smoke.sh
```

### Security model

pi-cl follows original pi's default YOLO execution model. Built-in and
extension tools execute immediately after schema validation. There is no core
approval dialog, trust ledger, or `--yolo` switch: an approval prompt is not a
security boundary.

Project extensions are arbitrary in-process Common Lisp. Running pi-cl in an
untrusted repository is equivalent to executing that repository's extension
code. Use a container, virtual machine, or restricted OS user when strong
isolation matters.

Users who want per-tool approval can implement it as an extension policy:

```lisp
(define-event-hook :tool-call-before
  :priority -100
  :handler
  (lambda (event context)
    (declare (ignore context))
    (let* ((call (extension-event-tool-call event))
           (name (pi-ai:tool-call-name call)))
      (format *query-io* "~&Allow tool ~A? [y/N] " name)
      (finish-output *query-io*)
      (let ((answer (read-line *query-io* nil "")))
        (unless (member answer '("y" "yes")
                        :test #'string-equal)
          (make-extension-hook-result
           :block-p t
           :reason "Denied by approval extension")))))))
```

The built-in tools are `read`, `write`, `edit`, `bash`, `glob`, and `grep`.
All six execute directly by default, matching original pi.

### Differences from TypeScript Pi

- The implementation language and extension ecosystem are Common Lisp;
  TypeScript/JavaScript extensions, npm packages, and Markdown skill files are
  intentionally incompatible.
- The build uses ASDF, Quicklisp, and an SBCL native image instead of the
  TypeScript/Bun toolchain.
- Lisp extension packages and generation packages replace JavaScript module
  loading; this is the unavoidable namespace/loading difference of the
  language migration.

### Native infrastructure and dependencies

Phase 9 replaced the production JSON parser, CLI parser, HTTP client, tool
schema validator, and thread portability layer with project or SBCL code.
Production dependencies are now only `cl+ssl` for system OpenSSL TLS and
`cl-ppcre`, whose full regex engine is the explicit `goal2.md` deferral.

The final regression run is 632/632 checks. Native-image acceptance, all four
DeepSeek paths, and the real OpenAI Codex OAuth Responses path pass:

```bash
./scripts/acceptance-smoke.sh
./scripts/live-deepseek-smoke.sh
./scripts/live-extension-smoke.sh
PI_CL_ALLOW_LIVE_TOOL_SMOKE=1 ./scripts/live-repo-smoke.sh
./scripts/live-tui-smoke.sh
./scripts/live-openai-oauth-smoke.sh
```

See [`docs/progress/phase-9.md`](docs/progress/phase-9.md) for replacement and
performance evidence, and
[`docs/dependency-audit.md`](docs/dependency-audit.md) for the exact inventory.

See [`docs/architecture.md`](docs/architecture.md) for the exact behavioral
contract and [`docs/test-matrix.md`](docs/test-matrix.md) for verification
coverage.
