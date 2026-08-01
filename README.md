# cadr

`cadr` is a native Common Lisp coding agent for SBCL, behaviorally aligned
with the original pi while remaining idiomatic Lisp.

The name has two meanings: `cadr` selects the second element of a list, and
this project is a second implementation of pi; it also pays tribute to the MIT
CADR Lisp Machine.

## Relationship to pi

Behavior is pinned to
[`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`](https://github.com/earendil-works/pi/tree/74caa2649f10ed71b4378ce69f5d9fbfd2466ca5).
That implementation and its tests are the behavioral reference for provider
payloads, streaming events, agent-loop semantics, tools, sessions, extensions,
and terminal interaction.

The former
`71efc6f0c1909874ec8c944637a9ae7fc0e2d508` baseline is retained only as a
historical audit anchor.

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
- system SQLite development/runtime libraries

```bash
QUICKLISP_SETUP="$HOME/quicklisp/setup.lisp" ./build.sh
./cadr --version

QUICKLISP_SETUP="$HOME/quicklisp/setup.lisp" ./build-server.sh
./cadr-server --version
```

The builds produce `./cadr` and the optional Unix-socket supervisor
`./cadr-server`. If SBCL lacks `sb-core-compression`, either build emits an
uncompressed image instead of failing.

## Dependency policy

The registered self-build exceptions are:

- `cl+ssl`, solely as the FFI binding to system OpenSSL;
- `cl-sqlite` (ASDF system `sqlite`), as the FFI binding to system
  `libsqlite3`.

The latter directly loads `iterate` and CFFI; the audited CFFI closure on
Linux/SBCL is Alexandria, Babel, and trivial-features. `cl-ppcre` remains an
explicitly authorized deferral for a complete regex engine, not a third
self-build exception.

The separately authorized **pure-Lisp replaceable** category contains
`cl-jpeg` and `png-read` for baseline JPEG/PNG pixel decoding and encoding.
`png-read` loads Babel, Chipz, and Iterate; Babel and Iterate were already in
the `cl-sqlite` closure, while Chipz is the only newly admitted transitive
system. These libraries add no system ABI or security boundary and may be
replaced by an in-tree implementation without changing public contracts.

The exact production and transitive audit is in
[`docs/dependency-audit.md`](docs/dependency-audit.md).

Any new third-party dependency must be declared during goal pre-review. The
goal remains blocked until explicit user authorization; retrospective approval
is not valid.

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
./cadr --fork <session-id-prefix>
./cadr --print "Explain this repository"
./cadr --mode json "Explain this repository"
./cadr --mode rpc
./cadr --no-tui
```

Interactive terminals use the full-screen TUI. `--no-tui` explicitly selects
the line REPL. `--print`/`--mode text` prints only the final answer,
`--mode json` emits agent events as JSONL, and `--mode rpc` exposes the
original pi command/response/event JSONL protocol. Without an explicit mode,
non-TTY input or output selects one-shot text mode.

Sessions are parent-linked JSONL trees under `~/.cadr/sessions/`. Interactive
session navigation uses `/resume`, `/fork`, and `/tree`; the remaining slash
command surface follows the original pi command list.

`--fork` accepts a session file path or a full/partial session ID, preferring
the current project's sessions before the global session set. It creates a new
session containing the source conversation. It does not accept a message entry
ID; use interactive `/fork` to select a user-message entry.

### Server

`cadr-server` supervises independent RPC-mode agents over a Unix socket:

```bash
./cadr-server serve
./cadr-server spawn --cwd "$PWD" --label worker
./cadr-server list
./cadr-server status <instance-id>
./cadr-server rpc <instance-id> '{"type":"get_state"}'
./cadr-server stop <instance-id>
```

State and `server.sock` live under `~/.cadr/server/` by default. Radius
presence is dormant unless a stored Radius OAuth credential or
`RADIUS_API_KEY` exists.

### Evals

The eval harness requires an explicit provider and model:

```bash
./scripts/run-evals.sh \
  --provider deepseek \
  --model deepseek-v4-flash
```

Credential-gated live blocks run through `./scripts/test-live.sh`, separately
from the deterministic `./scripts/test-cl.sh` gate. With the locally available
credentials, `test/cadr-evals/live-evals-test.lisp` runs the DeepSeek and Codex
OAuth evals; absent credentials are listed as skips with their reason.

### OAuth

Start `./cadr`, then enter:

```text
/login openai
```

The PKCE callback listens once on `127.0.0.1:1455`. Credentials are stored in
`~/.cadr/auth.json` under the baseline `openai-codex` provider identity with
mode `0600`. A successful login selects and persists that provider's default
model when the previous route had no usable auth or belonged to another
provider, so the same session and the next plain `./cadr` invocation can
converse without provider/model flags. Refresh is locked per provider and token
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

The stable extension interface is frozen in `CADR-AGENT`. Its registration
macros are:

- `define-tool`
- `define-command`
- `define-event-hook`
- `define-prompt-template`
- `define-provider`

It also exposes the original pi lifecycle events, runtime tool/provider
registration, message/session actions, and RPC-capable extension UI context.
The exact frozen surface and reference locations are recorded in
[`docs/proposals/goal-v7-extension-api.md`](docs/proposals/goal-v7-extension-api.md).

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
- By explicit user decision, every selector wraps in both directions, including
  the few original pi selectors that clamp at a boundary.
- By explicit user decision, bash tool titles omit the explicit-timeout suffix
  and always render as `$ <command>`.
- By explicit user decision, OpenAI OAuth authorization requests and Codex
  Responses requests identify this client with `originator=cadr`, rather than
  attributing Cadr traffic to the reference client's `originator=pi`.
- Deterministic and live FiveAM tests have separate entry points. This is an
  explicit organizational difference with the same CI effect as the reference:
  its credential-gated live blocks remain in Vitest but all skip in official CI
  because that workflow injects no provider credentials; `test-cl.sh` instead
  excludes those blocks and `test-live.sh` runs them explicitly.
- By explicit user decision, `scripts/verify.sh` is a local-only release gate
  that composes the deterministic, isolated-build, process/PTY, and available
  live stages; Cadr does not add a remote CI workflow for it.
- External shell harnesses remain only where a unit test cannot faithfully
  observe the real boundary:
  `acceptance-smoke.sh` (native image and cross-process sessions),
  `goal5-manual-tui-smoke.sh`/`live-tui-smoke.sh` (PTY, terminal rendering and
  termios), `migration-smoke.sh` (interactive data migration),
  `server-smoke.sh` (native multiprocess Unix socket), and
  `test-wave2-process-modes.sh` (native modes, signals and RPC EOF).

No additional core safety, approval, orchestration, or policy mechanism is
introduced. Proposed mechanisms beyond original pi belong in
[`docs/open-questions.md`](docs/open-questions.md) until manually approved.

## Verification

| Level | Current evidence |
|---|---|
| Deterministic ASDF gate | Current Goal 9 Part D run: 6952 checks / 6952 pass / 0 skip / 0 fail; isolated `cadr` and `cadr-server` public builds repeat the same gate |
| Deterministic | Fixture/request/response parity for all baseline protocols, including temporary-store `/login openai` → `openai-codex` → default resolver → stubbed Codex transport |
| Live-proven | Part D `verify.sh`: `test-live.sh` produced 32 checks / 31 pass / one unavailable-Anthropic skip / 0 fail, then the real DeepSeek PTY/TUI two-turn edit passed |
| Credential-gated | The live report lists every run, skip reason, and failure output/classification; fixtures are not presented as live evidence |
| Human acceptance | Goal 5 TUI checklist and Goal 9 Part B three-round dual-terminal A/B acceptance passed |

```bash
./scripts/verify.sh
```

That release-local entry runs deterministic FiveAM, isolated builds of both
native images, every retained process/PTY harness, credential-gated live
FiveAM, and the DeepSeek live TUI when its key is available. It prints separate
deterministic and live tables and exits nonzero for any executed failure; absent
credentials are reported as explicit skips. It does not create or invoke a
remote CI workflow. Individual stages remain available for diagnosis:

```bash
./scripts/test-cl.sh
./scripts/test-live.sh
./build.sh
./build-server.sh
./scripts/acceptance-smoke.sh
./scripts/test-wave2-process-modes.sh
./scripts/migration-smoke.sh
./scripts/server-smoke.sh
./scripts/live-tui-smoke.sh
```

`test-live.sh` runs every live item before returning. Any failure makes the
command fail and is reported as a suspected product defect, suspected model
output variation, or undetermined, with the basis and captured failure output.
Goal 9 Part D's release verifier must run all locally available live items;
overriding a red live stage requires explicit user approval of that report.

Detailed coverage is in [docs/test-matrix.md](docs/test-matrix.md).
The script-by-script evidence audit is in
[docs/acceptance/goal-v8-smoke-audit.md](docs/acceptance/goal-v8-smoke-audit.md).
Migration evidence and the exact residual-name exemptions are in
[docs/progress/migration.md](docs/progress/migration.md).
The final mechanical evidence and pending human checklist are in
[docs/acceptance/goal-v8-final.md](docs/acceptance/goal-v8-final.md).
Goal 9 visual-parity evidence and the pending B3 human checklist are in
[docs/acceptance/goal-v9-part-b.md](docs/acceptance/goal-v9-part-b.md).

## License

MIT. See [LICENSE](LICENSE).
