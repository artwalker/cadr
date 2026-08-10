# cadr

**cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)**

`cadr` is a native Common Lisp coding agent for SBCL, behaviorally aligned
with the original pi while remaining idiomatic Lisp.

The name has two meanings: `cadr` selects the second element of a list, and
this project is a second implementation of pi; it also pays tribute to the MIT
CADR Lisp Machine.

## Relationship to pi

Behavior is pinned to
[`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`](https://github.com/earendil-works/pi/tree/74caa2649f10ed71b4378ce69f5d9fbfd2466ca5).
That commit is `v0.83.0-38-g74caa2649`: it is 38 commits ahead of the latest
published `v0.83.0` tag, so Goal 10 correctly retained it instead of
downgrading to the tag.
That implementation and its tests are the behavioral reference for provider
payloads, streaming events, agent-loop semantics, tools, sessions, extensions,
and terminal interaction.

Alignment is tracked on four independent axes:

- the **behavior** ledger, [`docs/parity-map.md`](docs/parity-map.md), maps
  externally observable behavior to deterministic and live test evidence;
- the **source** ledger, [`docs/source-parity.md`](docs/source-parity.md), gives
  every fixed-baseline source file an explicit disposition;
- the **non-functional** ledger, [`docs/performance.md`](docs/performance.md),
  locks performance, allocation, memory, and long-run stability budgets;
- the **presentation** ledger,
  [`docs/presentation-parity.md`](docs/presentation-parity.md), audits visible
  copy, semantic styling, geometry, formatting, truncation, and every external
  output channel, including bytes written outside the TUI lifecycle.

Passing one axis never excuses failure on another. `examples/manifest.sexp` is
an auxiliary inventory for the fixed-baseline runnable examples, not a fifth
ledger. [`docs/source-parity-upgrade.md`](docs/source-parity-upgrade.md) defines
the fail-closed source drift gate for a future baseline upgrade.

Goal 17's fixed-baseline differentials execute both implementations. The
render differential compares PTY bytes and terminal
geometry, the tool-result differential compares the exact text and error bit
returned to the model, and the event differential compares JSON and RPC event
records and ordering. They are cross-implementation oracles, not additional
ledgers: the four ledgers remain the implementation-side records, while the
differentials catch an assertion or fixture that encoded the wrong behavior.
`scripts/verify.sh` runs the core render matrix and both non-visual
differentials on every delivery. `scripts/verify-release.sh` composes that
verifier with the complete baseline-visible branch inventory and is the
mandatory pre-tag entrypoint; `scripts/test-render-diff-full.sh` is mandatory
after every upstream baseline upgrade. Every non-aligned result requires an
explicit, non-stale disposition.

Those four axes answer whether Cadr is correct. The permanent
[`docs/code-organization.md`](docs/code-organization.md) contract answers
whether the implementation remains navigable and safe to extend: it records
directory ownership, converged policy primitives, their anti-bypass tests, and
the reviewed large-file symptom gate. Passing that gate is not a fifth parity
claim and does not prove good design.

The former
`71efc6f0c1909874ec8c944637a9ae7fc0e2d508` baseline is retained only as a
historical audit anchor.

Thanks to the pi authors and contributors for the design and reference
implementation. `cadr` is an independent project and has no affiliation with
the original pi project or its maintainers. Both projects use the MIT License;
see [LICENSE](LICENSE).

Documentation responsibilities and maintenance entry points are indexed in
[`docs/README.md`](docs/README.md). Project milestones are recorded in
[`CHANGELOG.md`](CHANGELOG.md).

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
uncompressed image instead of failing. `version.sexp` is the single production
version source for every ASDF system, both binaries, the TUI banner, HTTP user
agent, Radius registration, and the release identity printed by `--version`.

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

The separately authorized **explicitly enabled debugging service** category
contains `slynk/mrepl` at Quicklisp snapshot `sly-20260101-git` (upstream
commit `e01c7b4b`, archive MD5 `129945ec9a674a1efe353e2d3742fb00`). Its full
closure is `slynk/mrepl → slynk → ASDF`; no other Slynk contrib is included.

The separately authorized **browser-executed export assets** are Marked
18.0.5 (MIT) and Highlight.js 11.9.0 (BSD-3-Clause). `/export` embeds their
exact vendored bytes, complete license headers, renderer, styles, and Base64
session data in one offline, self-contained HTML file. The export contains no
external resource load and initiates no network request; the scripts execute
only in the browser that opens the file and never enter Cadr's ASDF runtime
closure.

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

Service behavior is explicit:

- `/share` uses `https://cadr.dev/session/` by default and
  `CADR_SHARE_VIEWER_URL` as its sole environment override. The success output
  prints the viewer URL. Until that static viewer is deployed, sharing still
  creates the private Gist but the returned viewer link is knowingly
  unavailable; deployment requires no Cadr code change.
- automatic version checks are disabled unless `CADR_VERSION_CHECK_URL` is a
  non-empty Cadr-compatible endpoint. `CADR_OFFLINE` or
  `CADR_SKIP_VERSION_CHECK` disables even a configured endpoint.

Equivalent command-line options are `--provider`, `--model`, and
`--base-url`. Per-provider settings may also be stored in
`~/.cadr/agent/config.json`:

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

Interactive keybindings can be overridden in the `keybindings` object of
`~/.cadr/agent/settings.json`; a trusted project's `.cadr/settings.json` can override
the same action ids. A value may be one key or an array of keys, and `/reload`
applies edits without restarting the session. For example, when Windows
Terminal owns `Alt+Enter`, move follow-up queueing to `Ctrl+G` while retaining
the default dequeue action:

```json
{
  "keybindings": {
    "app.message.followUp": "ctrl+g",
    "app.message.dequeue": "alt+up"
  }
}
```

The configurable surface includes every Cadr application, editor, selector,
and fullscreen action id; defaults remain `alt+enter` for follow-up and
`alt+up` for restoring all queued messages to the editor.

## Usage

```bash
./cadr
./cadr --provider deepseek
./cadr --continue
./cadr --resume
./cadr --session <path-or-id>
./cadr --fork <session-id-prefix>
./cadr --print "Explain this repository"
./cadr --mode json "Explain this repository"
./cadr --mode rpc
./cadr --no-tui
./cadr --slynk 4005
```

Interactive terminals use the full-screen TUI. `--no-tui` explicitly selects
the line REPL. `--print`/`--mode text` prints only the final answer,
`--mode json` emits agent events as JSONL, and `--mode rpc` exposes the
original pi command/response/event JSONL protocol. Without an explicit mode,
non-TTY input or output selects one-shot text mode.

Sessions are parent-linked JSONL trees under `~/.cadr/agent/sessions/`. Interactive
session navigation uses `/resume`, `/fork`, and `/tree`; the remaining slash
command surface follows the original pi command list. `--session` accepts a
session file or full/partial ID. After a normal interactive exit, Cadr prints
the exact `cadr --session <id>` command after restoring the terminal; a custom
session directory is included as `--session-dir`. Signal and emergency exits
do not print a resume hint.

`--fork` accepts a session file path or a full/partial session ID, preferring
the current project's sessions before the global session set. It creates a new
session containing the source conversation. It does not accept a message entry
ID; use interactive `/fork` to select a user-message entry.

`--slynk <port>` explicitly starts a runtime REPL on `127.0.0.1` and exposes
the current agent as `(cadr-cli:active-agent)`. It is always off by default,
cannot be enabled by config or environment variables, and never listens on a
non-loopback address. Slynk permits arbitrary evaluation inside the cadr
process; loopback is not a sandbox. Use an SSH tunnel for remote access and a
container, VM, or restricted user when inspecting untrusted code.

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

`/login` first chooses account vs API-key authentication, then a provider.
`/login <provider>` skips that outer selector when the provider exposes one
method and shows `Select authentication method for <provider>:` only when it
actually exposes two. OpenAI Codex then offers its baseline browser and
headless device-code methods; the device flow displays the verification URL
and code while polling.

The PKCE callback listens once on `127.0.0.1:1455`. Credentials are stored in
`~/.cadr/agent/auth.json` under the baseline `openai-codex` provider identity with
mode `0600`. A successful login selects and persists that provider's default
model when the previous route had no usable auth or belonged to another
provider, so the same session and the next plain `./cadr` invocation can
converse without provider/model flags. Refresh is locked per provider and token
values are redacted from transport, API, assistant, and condition output.
While the callback listener is active, the login dialog also accepts either an
authorization code or the complete redirect URL. Browser callback and manual
input race; the first valid result cancels the other path. The callback page
uses Cadr's own single-path cons-cell grid mark rather than pi's brand asset.
Its two adjacent cells and rightward notch express the Lisp operation behind
the project name while the 800×800 monochrome square-grid construction keeps
the baseline's visual language without reusing its identity.
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

Agent data lives one level down in `~/.cadr/agent/` (settings, auth,
models, sessions, themes, prompts, tools, bin, extensions, crash logs),
matching the baseline `~/.pi/agent/` layout; `~/.cadr/server/` stays at
the home root. `CADR_CODING_AGENT_DIR` overrides the agent directory.
Installations from before the `agent/` layer are migrated automatically:
startup moves the flat `~/.cadr/` residents into `~/.cadr/agent/` (a
rename, preserving the `0600` auth mode), refuses to choose when both
layouts hold data, and skips entirely when the override is set.

Legacy `PI_CL_PROVIDER`, `PI_CL_MODEL`, and `PI_CL_BASE_URL` were readable only
through the `0.1.x` transition release. Support is removed in `0.2.0`; new
configuration must use `CADR_PROVIDER`, `CADR_MODEL`, and `CADR_BASE_URL`.

Goal 16 completed the remaining runtime namespace hard cut. No old name is
read, and no compatibility warning or alias is retained:

| Old | New |
|---|---|
| `PI_CACHE_RETENTION` | `CADR_CACHE_RETENTION` |
| `PI_CONFIG_DIR` | `CADR_CONFIG_DIR` |
| `PI_EVAL_ARTIFACT_DIR` | `CADR_EVAL_ARTIFACT_DIR` |
| `PI_EXPERIMENTAL` | `CADR_EXPERIMENTAL` |
| `PI_MODEL` | `CADR_EVAL_MODEL` |
| `PI_OFFLINE` | `CADR_OFFLINE` |
| `PI_PROVIDER` | `CADR_EVAL_PROVIDER` |
| `PI_RADIUS_SERVER_URL` | `CADR_RADIUS_SERVER_URL` |
| `PI_RADIUS_URL` | `CADR_RADIUS_URL` |
| `PI_SERVER_CADR_PATH` | `CADR_SERVER_CADR_PATH` |
| `PI_SERVER_DIR` | `CADR_SERVER_DIR` |
| `PI_SHARE_VIEWER_URL` | `CADR_SHARE_VIEWER_URL` |
| `PI_SKIP_VERSION_CHECK` | `CADR_SKIP_VERSION_CHECK` |
| `PI_TIMING` | `CADR_TIMING` |

## Lisp extensions

Extensions are an `extension.lisp` file or a directory containing one.
Discovery order is:

1. repeatable `--extension <path>` entries, last entry winning;
2. `./.cadr/extensions/`;
3. `~/.cadr/agent/extensions/`.

The stable extension interface is frozen in `CADR-AGENT`. Its registration
macros are:

- `define-tool`
- `define-command`
- `define-event-hook`
- `define-prompt-template`
- `define-provider`

It also exposes the original pi lifecycle events, runtime tool/provider
registration, message/session actions, and RPC-capable extension UI context.
The user-approved Lisp-native `:tool-call-error` event is the sole additional
lifecycle event. At the live failure site it exposes `retry-tool-call`,
`skip-tool-call`, and `abort-agent-run` restarts; one logical call still emits
one start/after/end sequence, and the default path remains byte-identical.
The exact frozen surface and reference locations are recorded in
[`docs/proposals/goal-v7-extension-api.md`](docs/proposals/goal-v7-extension-api.md).

The fixed baseline's 99 runnable extension/SDK example source files are tracked
one-for-one in [`examples/manifest.sexp`](examples/manifest.sexp), and all 99 have
functionally equivalent Lisp ports under [`examples/extensions/`](examples/extensions/)
and [`examples/sdk/`](examples/sdk/). The final five use the approved production
compaction lifecycle, structured system-prompt options, and session-local buffered
HTTP seam recorded in
[`docs/proposals/goal-v12-api-scope-amendment-3.md`](docs/proposals/goal-v12-api-scope-amendment-3.md).
These are baseline capability completions, not additional Cadr mechanisms.
The currently re-frozen extension export text SHA-256 is
`61eb1b623f784b3a8f0f6fe6791c65ebe991ff314ed1d969b82f3edd57646f18`;
the 34-event set remains unchanged.

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

An otherwise unhandled runtime condition is caught before stack unwinding.
The terminal receives only the condition type, a bounded message, and the path
to a diagnostic under `~/.cadr/agent/crash/`; it never receives a Lisp backtrace or
an object dump. Crash logs are created with mode `0600` and redact API keys,
OAuth access/refresh tokens, authorization headers, and other recognized
credential fields. Credential-bearing runtime objects also have redacted
printers as a second line of defense. Crash logs can still contain non-secret
conversation and tool context needed for diagnosis, so treat them as private
and inspect them before sharing.

## Differences from TypeScript pi

- The implementation language and runtime are Common Lisp and SBCL.
- The build produces an SBCL native image through ASDF and Quicklisp instead
  of using the TypeScript/Bun toolchain.
- Extensions are Lisp packages and forms rather than JavaScript modules and
  npm packages.
- Tool failures expose Common Lisp restarts plus the opt-in
  `:tool-call-error` extension event; this is an explicitly approved
  Lisp-native addition and is not placed on agent-event, JSON, or RPC wires.
- `--slynk <port>` is an explicitly approved, default-off, loopback-only
  runtime debugging service. Original pi has no equivalent in-process Lisp
  REPL.
- By explicit user decision, every selector wraps in both directions, including
  the few original pi selectors that clamp at a boundary.
- By explicit user decision, bash tool titles omit the explicit-timeout suffix
  and always render as `$ <command>`.
- By explicit user decision, OpenAI OAuth authorization requests and Codex
  Responses requests identify this client with `originator=cadr`, rather than
  attributing Cadr traffic to the reference client's `originator=pi`.
- Third-party attribution headers, xAI device authorization, `/share`, and
  Cadr-owned repository/browser/runtime identifiers use the single Cadr
  product identity source. Radius registration/API/wire names and fixed
  baseline provenance remain exact external contracts, not product branding.
- OAuth success and failure pages use Cadr's own cons-cell grid mark instead of
  pi's logo. This is a branding difference only; the page shell, copy, styling,
  escaping, and HTTP framing remain aligned.
- SBCL and the TypeScript terminal renderer emit different raw ANSI update
  segmentation and teardown sequences. The Goal 15 differential therefore
  requires equal terminal-state semantics while retaining and classifying the
  original byte streams; visible text, styling, geometry, and cursor state are
  not exempted.
- By the approved Goal 13 security hardening, fatal conditions show a bounded,
  redacted summary and private `0600` crash-log path instead of pi's terminal
  stack dump (`interactive-mode.ts:3671-3721`). The baseline behavior can leak
  the system prompt and session contents; Cadr deliberately keeps those out of
  both the terminal summary and the redacted log. Terminal teardown and layout
  remain subject to baseline parity.
- Deterministic and live FiveAM tests have separate entry points. This is an
  explicit organizational difference with the same CI effect as the reference:
  its credential-gated live blocks remain in Vitest but all skip in official CI
  because that workflow injects no provider credentials; `test-cl.sh` instead
  excludes those blocks and `test-live.sh` runs them explicitly.
- By explicit user decision, `scripts/verify.sh` is a local-only release gate
  that composes deterministic tests, isolated builds, performance/stability,
  process/PTY, the core fixed-baseline render differential, exact tool-result
  and event-stream differentials, and available live stages; Cadr does not add
  a remote CI workflow for it. The complete render inventory remains a separate
  mandatory pre-tag and post-upstream-upgrade gate.
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
| Deterministic ASDF gate | Goal 16 closeout: 14,827 checks / 14,827 pass / 0 skip / 0 fail; isolated `cadr`/`cadr-server` builds repeat the same gate; the real product-identity scan records 274/274 exact findings |
| Deterministic | Fixture/request/response parity for all baseline protocols, including temporary-store `/login openai` → `openai-codex` → default resolver → stubbed Codex transport |
| Non-functional | N=5000 frame/key/stream each 4.00ms; 1200-turn/10-hour faux run has linear retained state, stable FD/thread counts, and 10MiB load/resume/continue below 0.33s |
| Live-proven | Goal 10 closeout `verify.sh`: `test-live.sh` produced 32 checks / 31 pass / one unavailable-Anthropic skip / 0 fail, then the real DeepSeek PTY/TUI two-turn edit passed |
| Credential-gated | The live report lists every run, skip reason, and failure output/classification; fixtures are not presented as live evidence |
| Human acceptance | Goal 5 TUI checklist and Goal 9 Part B three-round dual-terminal A/B acceptance passed |

Goal 17's exact closeout totals, gate artifacts, commit sequence, and binary
freshness proof are recorded in
[`docs/acceptance/goal-v17.md`](docs/acceptance/goal-v17.md); the report does not
promote an intermediate run to final evidence.

```bash
./build.sh
./scripts/check-root-binary.sh
python3 ./scripts/check-code-organization.py \
  --root . --manifest docs/code-organization-exemptions.json
python3 ./scripts/check-product-identity.py \
  --root . --manifest docs/product-identity-allowlist.json
python3 ./scripts/render-diff.py gate \
  --tier core --pi-repo . --output /tmp/cadr-render-gate \
  --analysis-output /tmp/cadr-render-gate-analysis
./scripts/test-render-diff-full.sh
python3 ./scripts/tool-result-diff.py
python3 ./scripts/event-diff.py
./scripts/verify.sh
./scripts/verify-release.sh  # mandatory pre-tag aggregate
```

Before user-facing delivery, the root image must be rebuilt and the freshness
check must show that its build time is later than both the newest `src/` commit
and working-source mtime. The delivery report must include that time and the
exact `--version` output. `verify.sh` repeats this check when a root image is
present; a stale image fails before the expensive stages. A clean CI checkout
has no root image, so that stage is N/A there and the isolated build remains the
CI artifact gate. See the [delivery checklist](docs/delivery-checklist.md).

The local verifier runs deterministic FiveAM, isolated builds of both native
images, the Goal 11 performance/stability gate, every retained process/PTY
harness, the fresh core render matrix, exact tool-result and JSON/RPC event
differentials, credential-gated live FiveAM, and the DeepSeek live TUI when its
key is available. The complete render inventory is intentionally separate;
`verify-release.sh` makes it fail-closed before a tag, while baseline upgrades
run `test-render-diff-full.sh` directly. The
verifier prints separate deterministic and live tables and exits nonzero for
any executed failure; absent credentials are reported as explicit skips. It
does not create or invoke a remote CI workflow. Individual stages remain
available for diagnosis:

```bash
./scripts/test-cl.sh
./scripts/test-live.sh
./build.sh
./scripts/check-root-binary.sh
./build-server.sh
./scripts/bench.sh --output /tmp/cadr-performance.json
./scripts/goal11-stability.sh --output /tmp/cadr-stability.json
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
The final mechanical evidence and accepted human disposition are in
[docs/acceptance/goal-v8-final.md](docs/acceptance/goal-v8-final.md).
Goal 9 visual-parity evidence and completed B3 human acceptance are in
[docs/acceptance/goal-v9-part-b.md](docs/acceptance/goal-v9-part-b.md).
Goal 9 release-preparation, repository-hygiene, and final local verification
evidence is in
[docs/acceptance/goal-v9-part-e.md](docs/acceptance/goal-v9-part-e.md).
Goal 11 methodology, before/after data, stability evidence, and threshold
rationale are in [docs/performance.md](docs/performance.md) and
[docs/acceptance/goal-v11.md](docs/acceptance/goal-v11.md).

## License

MIT. See [LICENSE](LICENSE).
