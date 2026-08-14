# Goal 8 smoke and live evidence audit

Audit date: 2026-07-31.

Audit criterion: if a verification rewrites/normalizes the real input before
running the product, adds a special case that the user path does not have, or
asserts something weaker than the real user path it claims, then the original
"pass" evidence is invalid. Provider/eval behavior that can be expressed with a
credential gate isomorphic to `skipIf(!KEY)` must move into FiveAM; only
behavior that must observe a native process, PTY/termios, a Unix socket or
cross-process data migration stays as a shell harness.

## Conclusion

The old `live-openai-oauth-smoke.sh` and `live-evals-smoke.sh` both used
`jq` to rename the `openai` key in the real `auth.json` to `openai-codex`
before running; the former also passed provider/model explicitly. They only
prove "it can be called after renaming and overriding the default parameters";
they do not prove that the product of `/login openai`, or the default user
path, works. The two earlier OAuth "live passed" pieces of evidence are
withdrawn.

Seven scripts that could be internalized have been deleted, and their coverage
moves into the following credential-gated tests:

- `test/cadr-ai/live-provider-test.lisp`
- `test/cadr-cli/live-test.lisp`
- `test/cadr-evals/live-evals-test.lisp`

The first remediation coupled the OpenAI live gate backwards onto the real
`~/.cadr/settings.json`, and pinned the mutable `defaultModel` to the
provider's built-in default value. After the user legitimately switched to the
catalog model `gpt-5.6-luna`, the advisor's independent re-run failed; that
evidence is withdrawn again.

The final mechanism is split into two layers, following the baseline:

- The deterministic layer uses a temporary auth/config, a login stub and an
  HTTP stub, and covers `/login openai` writing the credential to
  `openai-codex`, default model resolution obtaining that credential and
  entering a Codex Responses request; it does not read the homedir.
- The live layer is gated on credential availability alone, and specifies
  provider/model explicitly in the test code. To isolate
  settings/session/extensions, the CLI live copies the real auth file byte by
  byte into a temporary HOME; it does not change keys, migrate, or normalize.
  The eval live obtains the real OAuth directly from the correct identity, then
  injects an explicit resolver into the isolated harness.

## Script-by-script audit

| Script | Disposition | Bypass / weak-assertion audit | The actual coverage boundary now |
|---|---|---|---|
| `scripts/acceptance-smoke.sh` | Kept | The isolated HOME, the seeded JSONL and the fake API key are a cross-process session fixture; the script does not claim provider live, so this is not a credential bypass | Native image startup, delayed persistence, `--continue` and exact `--resume` from two other processes; does not cover a real provider |
| `scripts/goal5-manual-tui-smoke.sh` | Kept | Uses a dedicated TUI harness, not the full application/provider path; earlier documentation limited it to component acceptance, and its assertions match that boundary | overlay focus, CJK, image fallback, resize and termios restoration under a real tmux PTY |
| `scripts/live-anthropic-smoke.sh` | Deleted and internalized | No input rewriting, but greps only two substrings, which is weaker than the full response, the terminal event state and usage | FiveAM runs two rounds of exact context when `ANTHROPIC_API_KEY` is present; with no credential on this machine it skips as the baseline does |
| `scripts/live-deepseek-smoke.sh` | Deleted and internalized | No input rewriting, but greps only substrings | FiveAM asserts the response, the start/done events and positive usage exactly |
| `scripts/live-evals-smoke.sh` | Deleted and internalized | Uses `jq` to rename `openai` to `openai-codex`, which constitutes a bypass | FiveAM gates the DeepSeek and Codex evals separately; both specify provider/model explicitly inside the test and inject a resolver that does not read the user configuration |
| `scripts/live-extension-smoke.sh` | Deleted and internalized | No credential rewriting; relies only on grepping output/session, and the tool-surface boundary is not written down | FiveAM uses the original exact extension source, restricted to the tools the task needs, and asserts the path, the registration, the tool result, the final response and tool usage |
| `scripts/live-openai-oauth-smoke.sh` | Deleted and internalized | Uses `jq` to change the OAuth key; the original pass is invalid. Explicit provider/model is itself consistent with the baseline live mechanism, but cannot prove the default routing | The deterministic gate proves login/store/default resolver/Codex transport; the live gate explicitly uses `openai-codex/gpt-5.5` in an isolated HOME, and proves only that the real OAuth works |
| `scripts/live-print-smoke.sh` | Deleted and internalized | No input rewriting; the script covers stdout only | FiveAM explicitly uses DeepSeek through the real CLI handler in a temporary HOME/workspace, and asserts the exit code, stdout and stderr exactly |
| `scripts/live-repo-smoke.sh` | Deleted and internalized | The extra `CADR_ALLOW_LIVE_TOOL_SMOKE=1` is an authorization mechanism the baseline does not have; the session grep asserts only indirectly | FiveAM gates on `DEEPSEEK_API_KEY` alone; the fixture makes the first run of unfixed code necessarily code 1 and leave a trace, and requires `test.sh` to be byte-for-byte unchanged, the fix to be on disk, a final test, and code 0; up to three complete isolated attempts are allowed, but only evidence that all holds within one and the same attempt is accepted |
| `scripts/live-tui-smoke.sh` | Kept | Explicit DeepSeek provider/model, so it does not prove the default selection or OAuth; what it claims has always been terminal interaction, not the default configuration | The real binary, a tmux PTY, autocomplete/undo/kill-ring, two rounds of tool edits, CJK/resize/termios; FiveAM cannot faithfully simulate a terminal driver |
| `scripts/migration-smoke.sh` | Kept | The fake key and the loopback SSE are a controllable post-migration continuation fixture, and it does not claim provider live | Non-interactive fail-closed, PTY confirmation, atomic directory move, permissions and cross-process continuation |
| `scripts/server-smoke.sh` | Kept | No provider input rewriting; asserts the structure a real socket returns | Two native binaries, a Unix socket, the supervisor/child multi-process arrangement, and spawn/list/status/RPC/stop |
| `scripts/test-wave2-process-modes.sh` | Kept | The loopback SSE is a protocol fixture; the script does not claim a live provider. The audit re-run found that the old version's fixed 50 ms sleep could send the signal only after the process had already exited on its own, actually yielding exit 0; it has been changed to wait for the server-side request marker to prove the request is in flight | text/stdin/JSONL/RPC UI/EOF on a native process, SIGTERM 143 on a genuinely in-flight request, and the shutdown hook |

## Actual run results after the remediation

The full `./scripts/test-cl.sh`:

```text
3043 checks
3042 pass
1 skip: LIVE-ANTHROPIC-STREAM-PRESERVES-TWO-TURN-CONTEXT
0 fail
```

Both credentials available locally were genuinely run: DeepSeek
provider/print/eval/self-extension/repo repair all green; Codex OAuth explicit
CLI and explicit eval all green. Both before and after the official full run,
the user's settings were `openai-codex/gpt-5.6-luna`, which proves the live
tests neither pin down nor rewrite the personal model selection. Test
refactoring commit:
`c73f27dffce029cefd29393015b0fc212ed47eca`.

After the earlier real TUI login, `auth.json` was mode 0600 and held both the
old `openai` key and the new `openai-codex` key, and settings were
`openai-codex/gpt-5.5` at the time; the same session, without a restart and
without being passed provider/model, replied exactly `OAUTH_TUI_DIRECT_OK`.
This is manual evidence from the product path, and it is no longer mixed into
the automatic live gate.

## Self-check on user-mutable state

| FiveAM live surface | Self-check result | Disposition |
|---|---|---|
| The two provider streams in `test/cadr-ai/live-provider-test.lisp` | Reads only the environment credential, explicit provider/model, message history constructed by the test | No change needed |
| `LIVE-DEEPSEEK-PRINT-MODE-EMITS-ONLY-FINAL-TEXT` | Although it did select the model explicitly and pass `--no-session/--no-extensions`, it still loaded the config/settings/model store of the real HOME | Changed to a temporary HOME/workspace; no personal file is copied |
| The former `LIVE-OPENAI-OAUTH-LOGIN-DEFAULT-ROUTE-IS-DIRECTLY-USABLE` | Read the real settings and asserted that the user's model equals the built-in default; the failure originated exactly here | Deleted that live contract; replaced by a deterministic login/default-route gate plus an explicit Codex live gate in an isolated HOME |
| `LIVE-DEEPSEEK-EVAL-SMOKE` | The eval selection is explicit, but the default resolver still reads the real config/auth | Injects a DeepSeek resolver holding only the test key and the explicit model |
| Codex eval smoke | The default resolver reads the real config/auth, and treats the presence of the wrong identity as a failure | Uses only the correct identity as the gate, and injects an explicit Codex resolver after obtaining the real OAuth |
| DeepSeek self-extension and repository repair | The harness already isolates project/session/extensions, but the resolver still reads the real config | Reuses the explicit DeepSeek resolver; the existing isolated directory and empty-extension startup assertions are kept |

Conclusion: there are eight actual provider live tests; apart from the two
`cadr-ai` provider streams, which were already compliant, the other six have
all had their implicit reads of the user's settings, selected model, session
history and installed extensions eliminated.

Both builds explicitly degraded and succeeded where the current SBCL lacks
`sb-core-compression`:

```text
cadr         65,348,488 bytes  mode 0755  version cadr 0.1.0
cadr-server  57,155,288 bytes  mode 0755  version cadr-server 0.1.0
```

All six kept scripts ran and passed after the final build; among them,
process-modes passed twice in a row once its fix was in place:

```text
acceptance smoke: delayed persistence, --continue, and exact --resume passed
wave2 process modes: text, auto-stdin, JSONL, RPC intervention/UI/EOF, and SIGTERM cleanup passed
migration smoke: refusal, full move, auth mode, and --continue passed
server smoke: spawn/list/status/RPC/stop over Unix socket passed
goal5 manual TUI smoke: overlay focus, CJK frame, image fallback, resize, and terminal restore passed
live TUI smoke: autocomplete, undo, kill-ring, DeepSeek two-turn edit, resize, CJK, and terminal restore passed
```

Residual-bypass check:

```text
rg -n 'jq.*(openai|openai-codex)|CADR_ALLOW_LIVE_TOOL_SMOKE|has\("openai"\)' scripts test cadr-ai.asd cadr-cli.asd cadr-evals.asd
# no output
rg -n 'live-(anthropic|deepseek|evals|extension|openai-oauth|print|repo)-smoke\.sh' scripts cadr-*.asd
# no output
```

## Found along the way but out of scope for this fix

If the self-extension live test opened up all the default tools, the model
could run a wide-ranging `find` outside the isolated directory. This is
consistent with the security model the project has already adjudicated — the
baseline's default YOLO, with isolation done by the user's container — and is
not a product defect of this round; the test now bounds the scope of its
evidence by the tool surface of the extension task it declares, and adds no
approval or sandbox mechanism to the core.

In the historical progress documents, the command output citing the deleted
scripts is kept only as a record of the time; within it, the OAuth "pass" is
explicitly withdrawn by this audit, and current acceptance may cite only the
new FiveAM gate results.

After a real `/login openai`, the request in the same session did use
`openai-codex/gpt-5.5` and succeeded, but the footer still showed
`deepseek-v4-flash` from startup. This affects neither the actual routing nor
persistence; the current implementation passes `(cadr-agent:agent-model agent)`
as of the instant of startup to the TUI as a value
(`src/cadr-cli/main.lisp:3337`), which apparently is not refreshed when the
model is switched. As this round's scope requires, it is only recorded and
queued into Goal 9; the TUI is not modified.
