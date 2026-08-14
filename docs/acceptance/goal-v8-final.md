# Goal 8 final acceptance package

Goal 8's historical fixed baseline is
`earendil-works/pi@71efc6f0c1909874ec8c944637a9ae7fc0e2d508`;
from Goal 9 on, the current normative baseline has been upgraded to
`earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.
The earlier mechanical acceptance was sent back because the OAuth smoke rewrote
the identity of the real credential. After the 2026-07-31 correction this
section must be completed again; the real-terminal manual items below must still
be confirmed by the user item by item before the project can enter maintenance
state.

## Mechanical acceptance

- [x] parity-map: `351 C / 0 U / 0 M / 1 N/A`; the only N/A is
  `packages/coding-agent/test/config.test.ts`, approved by the user file by file.
- [x] `./scripts/test-cl.sh`: `3043 checks / 3042 pass / 1 skip / 0 fail`;
  the only skip is that this machine has no `ANTHROPIC_API_KEY`.
- [x] `./build.sh`: degrades successfully when `sb-core-compression` is missing;
  `cadr 0.1.0`, 65,348,488 bytes, mode 0755.
- [x] `./build-server.sh`: degrades successfully in the same way;
  `cadr-server 0.1.0`, 57,155,288 bytes, mode 0755.
- [x] `./scripts/acceptance-smoke.sh`: deferred persistence, `--continue`, exact
  `--resume`.
- [x] `./scripts/test-wave2-process-modes.sh`: text, automatic stdin, JSONL,
  RPC intervention/UI/EOF, SIGTERM cleanup executed after the server side confirms the request is in flight.
- [x] `./scripts/migration-smoke.sh`: non-interactive fail-closed, full directory
  move, auth mode 0600, continuation after migration.
- [x] `./scripts/server-smoke.sh`: spawn/list/status/RPC/stop over a real Unix
  socket.
- [x] `./scripts/goal5-manual-tui-smoke.sh`: overlay focus, CJK frame,
  image fallback, resize, terminal restore.
- [x] `test/cadr-ai/live-provider-test.lisp`: credential-gated exact DeepSeek
  response, stream final state and usage; skipped per the baseline when there is no Anthropic credential.
- [x] `LOGIN-OPENAI-TEMP-STORE-DEFAULT-RESOLVER-ROUTES-CODEX-REQUEST`:
  temporary auth/config, and a login stub plus an HTTP stub deterministically cover
  `/login openai` → `openai-codex` storage → default model resolution → Codex Responses;
  it also asserts that the wrong `openai` identity was not written.
- [x] `test/cadr-cli/live-test.lisp`: both DeepSeek and Codex specify
  provider/model explicitly inside an isolated HOME; Codex only copies the real auth file byte for byte as the credential input,
  and does not read the user's settings, sessions, or extensions.
- [x] `test/cadr-evals/live-evals-test.lisp`: the DeepSeek and Codex evals,
  self-extension, and repo read/edit/fail/fix/pass are all credential-gated inside FiveAM.
- [x] `./scripts/live-tui-smoke.sh`: two rounds of real TUI editing against
  DeepSeek, resize, CJK, autocomplete, undo, kill-ring, terminal restore.
- [x] No Anthropic credential; the corresponding live block is skipped by the
  same credential gate as the baseline, and no fixture was passed off as live.
- [x] The shell smoke mechanism converged: a script-by-script audit, deletion of
  seven live scripts that could be brought in-process, and keeping only the six process/terminal harnesses for
  five classes of boundary, all of which were rerun and passed, see
  [`goal-v8-smoke-audit.md`](goal-v8-smoke-audit.md).
- [x] Product manual evidence: in a real TUI, after `/login openai`, a prompt was sent directly, without restarting and without adding arguments;
  `auth.json` keeps the old `openai` record and adds `openai-codex`, settings are
  `openai-codex/gpt-5.5`, and the assistant reply in the same session is exactly
  `OAUTH_TUI_DIRECT_OK`. This evidence is not used as input to any automated live test.
- [x] dependency audit: Wave 5/Part F has no new third-party dependency.
- [x] extension export SHA:
  `e0bcbf8c5f170efb99579fe6065579a8c2e93c7f1bd590b7502b08180ba54046`.
- [x] Relative to the Goal 8 start commit, the `src/cadr-tui` production diff is empty.

### Difference from the earlier "pass"

Previously `live-openai-oauth-smoke.sh` and `live-evals-smoke.sh` first copied
`auth.json`, then used `jq` to rename the `openai` key to `openai-codex`; the
former also passed provider/model explicitly. That path proves only "it works
after renaming and overriding the default value", and cannot prove the product of
`/login openai` or the ordinary startup path. Both old OAuth pass conclusions are
now withdrawn.

This round's valid evidence must satisfy all of the following:

1. the deterministic layer uses temporary auth/config and network stubs to cover
   login change → correct identity storage → default model resolution → Codex
   Responses, without reading the homedir;
2. the live layer is gated only on credential availability, and the test
   specifies provider/model explicitly; the CLI's isolated HOME only copies the
   auth input byte for byte, without renaming keys and without normalizing;
3. the eval live layer injects an explicit provider/model resolver; its project,
   session, and extension continue to use the isolated directories the harness
   builds itself;
4. the two `cadr-ai` provider live tests already read only the environment
   credential and construct provider/model explicitly, and need no change;
5. running the full set under the user's current `openai-codex/gpt-5.6-luna`
   settings is still all green, and settings are unchanged field by field before and after the tests.

## User real-terminal manual acceptance

Execute in a real terminal, in a real repository copy or in a container; do not run tool write tests directly against an important working tree.

- [x] Startup and exit: start the full-screen TUI; on normal exit, on Ctrl-C, and
  after suspend/resume, shell echo, cursor, paste, and termios are all restored.
  *Permanent gate: the three real PTY scenarios `normal`, `ctrl-c`, and
  `suspend-resume` of `scripts/goal9-a2-pty.sh`.*
- [x] Input editing: multi-line, CJK, emoji, wide-character wrapping; word-wise
  movement; history; kill/yank/yank-pop; undo.
  *Permanent gate:
  `GOAL9-A2-INPUT-EDITOR-PTY-EVENTS-AND-VIRTUAL-SCREEN-COVER-FULL-CONTRACT`.*
- [x] Completion: slash command, file path, `@`; keyboard selection, cancel, undo after applying.
  *Permanent gate:
  `GOAL9-A2-COMPLETION-PTY-EVENTS-SNAPSHOT-SELECTION-CANCEL-AND-UNDO`.*
- [x] Overlay: the session, tree, model, scoped-model, settings, and trust selectors;
  dual-overlay focus, CJK borders, and narrow/wide resize are all correct.
  *Permanent gate:
  `GOAL9-A2-OVERLAY-SELECTORS-FOCUS-CJK-AND-RESIZE-SNAPSHOTS`.*
- [x] Rendering: streaming text/thinking/tool, Markdown lists/tables/code/links;
  collapse and expand of long content, and status-bar token/cache/cost.
  *Permanent structural gate:
  `GOAL9-A2-FAUX-STREAM-RENDERING-STRUCTURE-AND-STATUS-SNAPSHOTS`; the purely perceptual part is left to
  the baseline A/B of Goal 9 Part B.*
- [x] Images: display in a real Kitty/iTerm2 protocol terminal; fallback when the protocol is unsupported; the old
  image placement is cleaned up after a resize.
  *(Verified by the advisor on the user's behalf, 2026-07-31, PTY + faked environment capabilities): a terminal without the capability emits the `[Image:` placeholder and
  zero protocol bytes; under `KITTY_WINDOW_ID=1` the transmission sequence `ESC _Ga=T,f=100,...,i=505` was detected;
  under `TERM_PROGRAM=iTerm.app` `ESC ]1337;File=inline=1;width=12;...` was detected;
  on repaint/exit the cleanup sequences `a=d,d=I,i=505` and `a=d,d=A` were detected.*
- [x] Tools: read/write/edit/bash/find/grep/ls execute directly by default in an isolated repository,
  with no core approval popup; errors, timeouts, truncation, and the subsequent recovery are visible.
  *(Verified by the advisor on the user's behalf, 2026-07-31, isolated git repository + five real DeepSeek scenarios): ls/find/grep
  located the TODO; edit really rewrote `return a - b` into `return a + b` (verified on disk);
  write created test_calc.py and bash ran python3 successfully; the error for a nonexistent file was returned clearly;
  reading a 500-line file raised nothing. No `[y/N]`/approval prompt at any point.*
- [x] Sessions: create, name, switch, branch, compact, export, and after exiting
  `--continue` and `--resume`; the contents of the two branches do not bleed into each other.
  *Permanent gate:
  `GOAL9-A2-SESSION-WORKFLOWS-ARE-DETERMINISTIC-AND-BRANCHES-STAY-ISOLATED`.*
- [x] Extensions: loading, commands, tool, hook, reload; legacy extension compatibility; custom UI/renderer;
  the old generation is correctly stale after reload.
  *Permanent gate:
  `GOAL9-A2-EXTENSION-WORKFLOW-COVERS-LEGACY-UI-RENDERERS-AND-STALE-RELOAD`.*
- [x] Modes: `--print` outputs only the final text; `--mode json` every line is valid JSON;
  `--mode rpc` request/response/event and the extension UI round trip.
  *Permanent gate:
  `GOAL9-A2-PRINT-JSON-AND-RPC-MODES-COVER-THE-REAL-CONTRACT`.*
- [x] Server: run `cadr-server serve` in one terminal and complete
  spawn/list/status/rpc/rpc-stream/stop in another; after the service restarts the old online instance
  converges to stopped.
  *(Verified by the advisor on the user's behalf, 2026-07-31, isolated `CADR_SERVER_DIR` + two processes): serve established
  the Unix socket; spawn returned `status:"online"` (id 019fb654-…90cc); after simulating a crash with `kill -9`
  and restarting serve, both `list` and `status` converged to `status:"stopped"`.
  The ordinary spawn/list/status/rpc/stop path is covered separately by `./scripts/server-smoke.sh`.*
- [x] Security posture: the README's default YOLO, the container-isolation responsibility, and the optional approval-hook example meet
  the user's expectations.
  *(Verified by the advisor, 2026-07-31, mechanism-alignment verdict): the user adjudicated that this item is a matter of "the mechanism only needs to be consistent with pi",
  requiring no subjective judgement. The baseline `packages/coding-agent/README.md:499` reads "**No permission
  popups.** Run in a container, or build your own confirmation flow with
  extensions"; the cadr README reads "no built-in approval dialog, no core `--yolo` mode, isolation relies on a container
  or an equivalent sandbox, and anyone who needs approval implements it through a hook extension" — semantically consistent; the project-trust semantics of
  `--approve`/`--no-approve` are likewise aligned with the baseline.*

## Disposition of the manual acceptance items (user adjudication, 2026-07-31)

- The three items marked "verified by the advisor on the user's behalf" (images, tools, Server) were executed by the advisor in an automated way with the user's authorization,
  the evidence being above.
- The security-posture item was adjudicated by the user as "the mechanism only needs to be consistent with pi", and consistency has been verified.
- **The remaining eight (startup and exit, input editing, completion, Overlay, rendering, sessions, extensions, modes)
  move into Goal 9 Part A2, covered by deterministic automated tests driven by a faux provider and a PTY,
  entering the suite as permanent protection against regression**; the mechanism is consistent with the baseline (the baseline pi's end-to-end verification likewise uses a faux
  provider, see `packages/agent/test/e2e.test.ts`), and driving them with a real LLM is forbidden.
  The purely perceptual judgements among them that cannot be automated are folded into Goal 9 Part B's A/B checklist, confirmed in one pass by the user
  while comparing side by side with the baseline pi.

Goal 8's closeout condition is therefore: this document's mechanical acceptance passes in full + the disposition above takes effect. The guarantee behind the eight behavioral acceptance items
is not weakened by this but upgraded to permanent automation; perceptual acceptance is instead borne by Goal 9 Part B.
