# Goal 10 visual and user-output follow-up

Date: 2026-08-01. Status: implemented; final verification recorded below.
Baseline: `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`.

## Base-screen vertical composition

The gap reported between the last transcript row and the editor is not an
`Output padding` or `Editor padding` setting. The baseline root order is
`chat → pending → status → aboveEditor → editor → belowEditor → footer`
(`interactive-mode.ts:734-746`). Its above-editor widget container is created
with `spacerWhenEmpty: true` and `leadingSpacer: true`
(`interactive-mode.ts:2044-2072`), so it owns exactly one row both when empty
and when populated. The below-editor container owns neither spacer.

`render-tui-widgets` now implements the same asymmetric container contract.
The surrounding audit found no other mismatch:

| Region | Baseline composition | Cadr result |
|---|---|---|
| Transcript top | header owns its leading/trailing spacers; otherwise no fixed top margin (`interactive-mode.ts:758-817`) | aligned |
| Message blocks | later user message gets one leading spacer; assistant visible content owns its leading spacer (`interactive-mode.ts:3318-3369`, `assistant-message.ts:100-114`) | aligned |
| Active/idle status | loader has one leading empty row; idle status reserves two rows (`loader.ts:43-45`, `status-indicator.ts:105-113`) | aligned |
| Above-editor widgets | empty and nonempty containers both contribute one leading row (`interactive-mode.ts:2044-2072`) | fixed |
| Below-editor widgets | no implicit spacer (`interactive-mode.ts:2044-2072`) | aligned |
| Editor/footer | editor padding and output padding are horizontal only; editor, below widgets, footer are adjacent (`interactive-mode.ts:497-505,743-746`) | aligned |

Eleven additional full base-screen SHA snapshots cover cold start, single turn, multiple turns,
thinking, collapsed and expanded tools, active status, above/below widgets,
overflow scrolling, and narrow width. The exact hashes are in
`docs/visual-parity.md` and are enforced by
`GOAL9-B3-EVERY-BASE-SCREEN-STATE-HAS-AN-EXACT-FULL-VIRTUAL-TERMINAL-SNAPSHOT`.

The previous 7192 checks missed this because full-screen SHA coverage existed
for overlays only. Base-screen checks asserted component fragments, ordering,
or row counts, none of which proved that an empty host widget container must
still contribute one row.

## Autocomplete trigger parity

Baseline `editor.ts:2085-2100,2140-2163,2219-2229,2347-2350` establishes:

- empty input, Space, and repeated Space never start natural completion;
- `/` starts slash completion only at message start, including leading space;
- `@` and other registered trigger characters start only at a token boundary;
- plain path fragments such as `./` require explicit Tab/force completion;
- while a picker is open, text, backspace, and delete re-query in its existing
  natural or force mode; Space closes a slash picker when it no longer matches,
  while a force file picker remains force-mode;
- deleting a natural trigger back to empty re-queries once and closes it;
  later empty deletes remain quiet.

The defect was the unconditional `:text` refresh in
`src/cadr-tui/editor.lisp`; `:backspace` and `:delete` already consulted the
natural-context predicate. All three paths now use one gate. Regressions:

- `EDITOR-TEXT-AUTOCOMPLETE-MATCHES-BASELINE-TRIGGER-GATE`
- `EDITOR-DELETE-TO-EMPTY-AND-SYMBOL-TRIGGERS-MATCH-BASELINE`
- `EDITOR-DELETE-DOES-NOT-INVENT-FILE-AUTOCOMPLETE-AT-PLAIN-TRAILING-SPACE`
- `EDITOR-AUTOCOMPLETE-DEBOUNCE-IS-POLLABLE-AND-LATEST-REQUEST-WINS`
- `GOAL9-A2-COMPLETION-PTY-EVENTS-SNAPSHOT-SELECTION-CANCEL-AND-UNDO`

Earlier coverage exercised deletion after an already valid completion prefix;
it never asserted provider-call count for empty `:text`, Space, repeated Space,
or a closed plain path fragment. Consequently a root directory listing could
open without violating any old assertion.

## Fourth A/B: transport abort and terminal bytes

### TLS transport normalization

The leak came from two coupled gaps in `src/cadr-ai/http.lisp`. Native socket,
cl+ssl handshake, and stream-read errors were allowed to retain their raw
condition text, and abort cleanup called ordinary `close`, whose
`SSL_shutdown` condition could replace the intended request-aborted condition.
Closing the file descriptor also did not reliably wake SBCL while cl+ssl was
blocked in `SSL_connect`.

The transport boundary now preserves structured HTTP/API/timeout errors but
normalizes every other native failure to exactly `fetch failed`. Abort closes
the body with `:abort t`, ignores cleanup-only TLS failures, and interrupts the
blocked Lisp operation after socket shutdown. This matches the baseline split:
the provider path turns abort into `Request was aborted`, while
`assistant-message.ts:190-200` renders that as `Operation aborted`; a generic
fetch failure remains `fetch failed`.

Permanent regressions cover all three real phases and forbidden fragments:

- `TLS-HANDSHAKE-ABORT-CLOSES-SOCKET-WITHOUT-NATIVE-DIAGNOSTIC`
- `ESTABLISHED-CONNECTION-BEFORE-HEADERS-ABORTS-WITHOUT-NATIVE-DIAGNOSTIC`
- `SILENT-SSE-REQUEST-ABORTS-WITHOUT-WAITING-FOR-THE-SERVER`
- `ABORT-INTERRUPTS-BLOCKING-HTTP-OPERATION-WHEN-CLOSE-CANNOT-WAKE-IT`
- `STREAMING-ABORT-IS-NOT-OVERRIDDEN-BY-CLOSE-TIME-SSL-DIAGNOSTIC`
- `TRANSPORT-ERRORS-HIDE-NATIVE-SSL-DIAGNOSTICS-FROM-USER-TEXT`

Every visible error assertion rejects `SB-SYS`, `SSL_`, and `../ssl/`.

### Real Alt key decoding

Baseline `packages/tui/src/keys.ts:587-650` parses modified CSI arrows,
functional keys, and Home/End in the same key parser as Kitty CSI-u. Cadr had
the modifier-bit decoder but never admitted `ESC[1;3A` to it; the byte framer
instead consumed only `ESC[` and let `[1;3A` reach the editor as text.

The shared terminal sequence framer now treats CSI, SS3, OSC, DCS, and APC as
atomic input. It decodes Windows Terminal/xterm modified arrows, xterm
modifyOtherKeys `ESC[27;3;13~`, Kitty `ESC[13;3u`, and legacy `ESC CR` when the
Kitty protocol is inactive. Complete unknown sequences are discarded atomically.
The busy TUI regression sends real bytes and proves Enter queues steering while
Alt+Enter queues follow-up, and `ESC[1;3A` dequeues both for editing.

Regressions:

- `MODIFIED-CSI-ARROWS-AND-ALT-ENTER-MATCH-REAL-TERMINAL-SEQUENCES`
- `INPUT-DECODER-HANDLES-REAL-XTERM-AND-WINDOWS-ALT-SEQUENCES`
- `GOAL10-BUSY-TUI-ENTER-AND-ALT-ENTER-USE-DISTINCT-QUEUES`
- `GOAL10-BUSY-TUI-DEQUEUE-RESTORES-BOTH-QUEUES-TO-THE-EDITOR`
- `GOAL10-PENDING-HINT-USES-THE-CONFIGURED-DEQUEUE-KEY`

The older `INPUT-DECODER-PRESERVES-CONFIGURABLE-ALT-KEY-ACTIONS` used only the
synthetic legacy `ESC p` alias. It proved action lookup, not the terminal byte
contract, so it could not catch the real decoder failure.

### Abort spacing and selector placement

Baseline `assistant-message.ts:195` adds exactly one `Spacer(1)` before
`Operation aborted`. Cadr's assistant wrapper and error fragment both added a
spacer, producing two. The wrapper now adds its generic leading spacer only
when ordinary assistant content exists; the abort fragment remains horizontally
padded by one cell and vertically preceded by exactly one blank row. Regression:
`GOAL10-OPERATION-ABORTED-HAS-EXACTLY-ONE-BASELINE-SPACER`.

Baseline root order permanently retains chat above the editor
(`interactive-mode.ts:734-746`); `showSelector` replaces only the editor
container (`:4161-4175`). Cadr previously treated overlay lines as transcript
content and therefore erased history. All selectors now occupy the editor slot,
with transcript cropped only by the remaining viewport. The 15 full-screen SHA
fixtures were regenerated with fixed nonempty user/assistant history and an
editor sentinel that must disappear. In addition to the SHA gate,
`GOAL10-EVERY-OVERLAY-SNAPSHOT-PRESERVES-NONEMPTY-TRANSCRIPT` checks all 15
surfaces.

The old overlay SHA fixtures used empty transcript state. Clearing an empty
transcript was observationally identical to retaining it, so their hashes could
not detect the architecture error. This is why the gate itself—not merely the
expected hash—had to change.

## `/reload` root cause and baseline result

The leaked text was not present in Cadr source. It is the report for
`ASDF/PLAN:SYSTEM-OUT-OF-DATE`. Every command called `handle-session-command`,
whose eager `changelog-path` default called `asdf:system-relative-pathname`.
When an ASD file was newer than the saved image, ASDF signalled the condition;
the TUI worker caught all `condition` values and converted it to a session
notice before the real `/reload` branch ran.

The fix is structural:

1. changelog path resolution is lazy and runs only for `/changelog`;
2. the optional ASDF lookup consumes its own non-error signal locally;
3. the TUI command boundary reports only `error`, not arbitrary conditions;
4. extension source and inline factories share a load boundary: explicit
   extension stdout/stderr stays visible, while ASDF/compiler/loader verbose
   streams and warnings are isolated;
5. successful reload emits the baseline completion text exactly:
   `Reloaded keybindings, extensions, skills, prompts, themes, and context files`.

The success entry uses the baseline `showStatus` shape: one leading blank row,
one-cell horizontal padding, dim text, no `session>` prefix, and consecutive
status entries coalesce. This is locked by
`TUI-STATUS-ENTRIES-MATCH-BASELINE-COPY-SPACING-AND-COALESCING`.

The baseline transient loading box text is at
`interactive-mode.ts:5379-5391`; its successful status text is at
`interactive-mode.ts:5456-5460`. Cadr's existing busy editor border remains the
transient progress surface; no persistent fake transcript line was added.

Regressions:

- `NON-CHANGELOG-COMMANDS-NEVER-RESOLVE-THE-CHANGELOG-PATH`
- `TUI-COMMAND-BOUNDARY-IGNORES-BENIGN-INFRASTRUCTURE-SIGNALS`
- `RELOAD-CLEARS-COMMAND-CACHE-AND-REFRESHES-RUNTIME-SURFACES-IN-ORDER`
- `EXTENSION-RELOAD-KEEPS-EXTENSION-OUTPUT-AND-ISOLATES-ASDF-DIAGNOSTICS`
- `INLINE-EXTENSION-OUTPUT-USES-THE-SAME-DIAGNOSTIC-BOUNDARY`

## Infrastructure-output audit

The rule is that subprocess/compiler/loader diagnostics do not become TUI
notices, tool results, model text, or OAuth transcript. Explicit product status,
extension-authored output, tool child output, and foreground package-manager
output remain visible.

| Boundary | Decision and implementation | Regression evidence |
|---|---|---|
| Extension source load | extension `*standard-output*`/`*error-output*` visible; ASDF/compiler/trace streams and warnings isolated; only errors enter the structured extension error notice | `EXTENSION-RELOAD-KEEPS-EXTENSION-OUTPUT-AND-ISOLATES-ASDF-DIAGNOSTICS` |
| Inline extension factory | identical boundary to source extensions | `INLINE-EXTENSION-OUTPUT-USES-THE-SAME-DIAGNOSTIC-BOUNDARY` |
| Legacy extension Git install | raw Git/wrapper output isolated; explicit redacted `Installed …` result visible | `INSTALL-VALIDATES-URL-USES-ARGV-AND-NEVER-OVERWRITES` |
| Extension `exec` | real child stdout and stderr remain separate and streamable; outer `setsid` stderr is discarded through a dedicated FD boundary | `NODE-EXECUTION-ENVIRONMENT-KEEPS-CHILD-STDERR-AND-ISOLATES-SETSID-STDERR` |
| Built-in bash tool | command stdout/stderr is the tool contract; `setsid` stderr stays on the null wrapper channel | `GOAL9-B3-BASH-TIMEOUT-NEVER-LEAKS-WRAPPER-DIAGNOSTICS` |
| Provider HTTP/TLS transport | ordinary native failure is exactly `fetch failed`; abort is `Request was aborted` and cleanup is silent; SAP/OpenSSL/C source diagnostics are forbidden at handshake, connected-before-headers, and streaming phases | `TRANSPORT-ERRORS-HIDE-NATIVE-SSL-DIAGNOSTICS-FROM-USER-TEXT`; `TLS-HANDSHAKE-ABORT-CLOSES-SOCKET-WITHOUT-NATIVE-DIAGNOSTIC`; `ESTABLISHED-CONNECTION-BEFORE-HEADERS-ABORTS-WITHOUT-NATIVE-DIAGNOSTIC`; `SILENT-SSE-REQUEST-ABORTS-WITHOUT-WAITING-FOR-THE-SERVER` |
| Model catalog refresh | parse/network errors remain registry errors; benign implementation signals are not promoted to the model selector/user channel | `MODEL-REGISTRY-REFRESH-DOES-NOT-PROMOTE-BENIGN-SIGNALS-TO-USER-ERRORS` |
| OAuth browser launch | authorization URL and explicit fallback message visible; `xdg-open` diagnostics discarded, matching baseline `open-browser.ts:18-23` | `OAUTH-BROWSER-LAUNCH-ISOLATES-BROWSER-DIAGNOSTICS` |
| Generic URL launch | selected URL remains the product action; desktop launcher diagnostics discarded | `TUI-URL-LAUNCH-ISOLATES-DESKTOP-LAUNCHER-DIAGNOSTICS` |
| Clipboard helpers | stdout is captured only when it is the requested clipboard payload; helper stderr is already null | `CLIPBOARD-TEXT-AND-IMAGE-FALLBACKS-PRESERVE-PLATFORM-ORDER` |
| Config command values | stdout is captured as the requested value; stderr is captured and discarded, never routed to the TUI | `CONFIG-VALUES-RESOLVE-TEMPLATES-COMMANDS-AND-CACHE` |
| Git footer probe | stdout is captured as branch data; stderr is null | `FOOTER-DATA-PROVIDER-RESOLVES-AND-REFRESHES-GIT-BRANCHES` |
| Package manager CLI | deliberate foreground command, not a TUI/session channel; raw install/update progress remains visible, matching baseline `package-manager.ts:2530-2536` and `package-manager-cli.ts:503-510` | `PACKAGE-PATHS-COMMANDS-AND-CROSS-SCOPE-DEDUPE-ARE-SAFE` |
| Build/test/catalog scripts | developer-only process channel; diagnostics remain visible and never enter a running agent's user channel | isolated build and `verify.sh` stages below |

This is the same failure family as the earlier `setsid: child …` leak: an
implementation layer was sharing an observable product channel. The previous
audit missed TLS because it enumerated process/loader/browser channels but no
provider transport boundary; its only network-abort gate used cleartext HTTP
and asserted the final stop reason, not cleanup output. The new tests assert the
boundary itself, not merely that one historical diagnostic string is absent.

Post-follow-up production object IDs:

```text
172a745fcd43c92586c51d215a7bff12c4696adb  cadr-cli.asd
ad84c128f9e6fa7fc273b2106d34d8154326d436  src/cadr-agent/execution-env.lisp
9a3a5a1b1d04d7942c09a345544106eac083e454  src/cadr-ai/http.lisp
c028d2407fd01d1e8a1cb6c037c8f0f0da71ae0e  src/cadr-ai/oauth.lisp
ac875cbea570d672c568b03471852f43ff4107cd  src/cadr-cli/extensions.lisp
ec89d42a881df90e33c89730d43d68a603a9cee7  src/cadr-cli/main.lisp
8a523cf7552330743a3bef23a28f326ac6d46ed9  src/cadr-cli/model-services.lisp
6478c1b8fb1553d025319b214135378f7f5c856e  src/cadr-cli/tui.lisp
7797f9eeb3f98906ae48307053ec01b3bed66760  src/cadr-tui/editor.lisp
23ec88ad788612cd1d6efaa97613e53ef96df0e3  src/cadr-tui/input.lisp
aaf9b37635b8bf1af94075c8126b32b3ab8336bc  src/cadr-tui/keys.lisp
18f3f502d9014e2bedc9436139616a2559b1e7a0  src/cadr-tui/stdin-buffer.lisp
```

## Mechanical verification

Old-path source scan:

```text
$ rg -n 'system cadr-cli is out of date|:output :interactive|:error-output :interactive|setsid: child' src
(no matches; exit 1)

$ rg -n -U '\(\(eq kind :text\)\n[[:space:]]+\(editor-refresh-autocomplete' src/cadr-tui/editor.lisp
(no matches; exit 1)

$ rg -n 'SSL_shutdown:shutdown while in init|SB-SYS:INT-SAP|ERR_print_errors|\.\./ssl/ssllib\.c' src
(no matches; exit 1)
```

Native 100×24 PTY after a fresh `./build.sh`, then `/reload`:

```text
 Reloaded keybindings, extensions, skills, prompts, themes, and context files
```

The capture contains neither `session>` nor `system cadr-cli is out of date`.

Root binary freshness after the final source commit:

```text
binary build time: 2026-08-01 22:14:56.047611847 +0800
latest src commit: a0a5ec1828d1eb4e8c445f77b6ae2802b9870b52
latest src commit time: 2026-08-01T22:12:30+08:00
freshness gate: PASS
version: cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)
```

Deterministic suite:

```text
$ ./scripts/test-cl.sh
checks: 7475
pass:   7475
skip:   0
fail:   0
```

Full verification entry point:

```text
$ ./scripts/verify.sh
exit: 0
deterministic stages: 11/11 PASS
terminal lifecycle PTY: 6/6 PASS
live stages: 2/2 PASS
live FiveAM items: 7 PASS, 1 SKIP (ANTHROPIC_API_KEY is not set), 0 FAIL
live FiveAM checks: 31 PASS, 1 SKIP, 0 FAIL
```

## Fifth A/B — notice channels and folded tool geometry

### Notice-channel audit

`session>` is the REPL protocol label, not a TUI decoration.  The leak came
from treating every frontend notification as the historical `:notice` row and
rendering that row as `session> <text>`.  The fixed boundary separates
arbitrary multi-line frontend output (non-coalescing `:notice`) from baseline
`showStatus` outcomes (coalescing `:status`) and gives error, warning, and the
special `/new` success row their own render types.  All five render without the
REPL label (`src/cadr-cli/tui.lisp:524-570,1958-2021`); the TUI wires distinct
consumers at `:3600-3619,4675-4686`.

Fixed-baseline evidence is
`interactive-mode.ts:3232-3240,3803-3806,3916-3928,5916`: ordinary status is a
dim `Text` row, errors and warnings have explicit product prefixes, dequeue is
status text, and `/new` alone uses `✓ New session started`.  No `session>`
string exists in the fixed coding-agent TUI sources.

| Producer / message family | TUI channel after audit | Prefix and copy |
|---|---|---|
| queued-message empty/restored; model/trust/settings/login/fork empty states; logout/API-key/import/fork completion; model scope/trust persistence; suspend unsupported | status | no label; exact product text; consecutive status replaces the prior transient status |
| reload and extension-command completion | status | no label; multi-line text remains one status value |
| command/selector/compaction failure | error | `Error: `, one-cell horizontal padding, no protocol label |
| startup and dynamic Anthropic subscription guidance | warning | `Warning: `, no protocol label |
| extension `notify` | info→status, warning→warning, error→error | preserves the requested severity; no protocol label |
| `/new` | success | exact `✓ New session started` shape |
| extension-authored or command-returned arbitrary frontend text | notice | status visual shape, but adjacent lines are not coalesced and never gain `session>` |
| compaction running/end | transient status indicator / status or structured summary | no invented transcript notice at start; errors use the error channel |

The regression pair
`GOAL10-NOTICE-CHANNEL-MATCHES-BASELINE-STATUS-WITHOUT-SESSION-PREFIX` and
`GOAL10-USER-MESSAGE-CHANNELS-MATCH-BASELINE-PREFIX-COPY-AND-SPACING` locks
non-coalescing frontend lines, every channel's exact rows, and the absence of
`session>` across the complete channel set.  Existing tests covered the output
source boundaries (setsid, ASDF, TLS) and one status message, but never rendered
the generic notice type itself; therefore a product-authored notice could still
leak the protocol label after all infrastructure diagnostics were clean.

### Folded tool block disposition

The reported successful collapsed `read` height is a verified non-difference.
Fixed baseline `read.ts:164-187` returns no result rows when collapsed and not
in error; `tool-execution.ts:63-75` contributes one outer spacer plus a
`Box(1,1)`, so a title-only read occupies exactly four rows.  Cadr has the same
four-row composition and a zero-line successful-read preview budget
(`src/cadr-tui/components.lisp:1530-1539,1567-1660`).  Error read shows at most
10 rows; the other fixed budgets remain bash 5 (tail), write 10, grep 15, and
find/ls 20.

The requested height/preview comparison did find a separate real difference:
expanded result content lacked the renderer's leading newline, and bash timing
lacked its separating blank row.  `render-tool-block` now inserts exactly one
blank row before output and before `Elapsed`/`Took`, locked by
`GOAL10-TOOL-BLOCK-INTERNAL-SPACERS-MATCH-BASELINE`.  No preview budget or
collapsed successful-read height was changed to fake the screenshot.
