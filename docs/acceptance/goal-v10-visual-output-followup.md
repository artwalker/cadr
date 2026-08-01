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

The 15 accepted overlay SHA snapshots are unchanged. Eleven additional full
base-screen SHA snapshots cover cold start, single turn, multiple turns,
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
| Model catalog refresh | parse/network errors remain registry errors; benign implementation signals are not promoted to the model selector/user channel | `MODEL-REGISTRY-REFRESH-DOES-NOT-PROMOTE-BENIGN-SIGNALS-TO-USER-ERRORS` |
| OAuth browser launch | authorization URL and explicit fallback message visible; `xdg-open` diagnostics discarded, matching baseline `open-browser.ts:18-23` | `OAUTH-BROWSER-LAUNCH-ISOLATES-BROWSER-DIAGNOSTICS` |
| Generic URL launch | selected URL remains the product action; desktop launcher diagnostics discarded | `TUI-URL-LAUNCH-ISOLATES-DESKTOP-LAUNCHER-DIAGNOSTICS` |
| Clipboard helpers | stdout is captured only when it is the requested clipboard payload; helper stderr is already null | `CLIPBOARD-TEXT-AND-IMAGE-FALLBACKS-PRESERVE-PLATFORM-ORDER` |
| Config command values | stdout is captured as the requested value; stderr is captured and discarded, never routed to the TUI | `CONFIG-VALUES-RESOLVE-TEMPLATES-COMMANDS-AND-CACHE` |
| Git footer probe | stdout is captured as branch data; stderr is null | `FOOTER-DATA-PROVIDER-RESOLVES-AND-REFRESHES-GIT-BRANCHES` |
| Package manager CLI | deliberate foreground command, not a TUI/session channel; raw install/update progress remains visible, matching baseline `package-manager.ts:2530-2536` and `package-manager-cli.ts:503-510` | `PACKAGE-PATHS-COMMANDS-AND-CROSS-SCOPE-DEDUPE-ARE-SAFE` |
| Build/test/catalog scripts | developer-only process channel; diagnostics remain visible and never enter a running agent's user channel | isolated build and `verify.sh` stages below |

This is the same failure family as the earlier `setsid: child …` leak: an
implementation layer was sharing an observable product channel. The new tests
assert the boundary itself, not merely that one historical diagnostic string
is absent.

Post-follow-up production object IDs:

```text
827c3edd901b5193d4dad3d06dc0827f585839a8  cadr-cli.asd
9b60e5aa5c07e33be46b866d5d1b9fb186e29279  src/cadr-agent/execution-env.lisp
8d4f40d4eb253f35c0b912432d1130a6f58074ae  src/cadr-ai/oauth.lisp
6b6acfc13bf0ed416b508f9cffa850891a539b94  src/cadr-cli/extensions.lisp
308f6f168273fcf55c75eae5eac74039a8b0a567  src/cadr-cli/main.lisp
71122121ffdf1a82ec2a5a7abc88a33a39167042  src/cadr-cli/model-services.lisp
9fefb518cc7a2712805d4570ed7b5276a942081c  src/cadr-cli/tui.lisp
5649eb933f20637da4d3b951e9615ad192c76b4d  src/cadr-tui/editor.lisp
```

## Mechanical verification

Old-path source scan:

```text
$ rg -n 'system cadr-cli is out of date|:output :interactive|:error-output :interactive|setsid: child' src
(no matches; exit 1)

$ rg -n -U '\(\(eq kind :text\)\n[[:space:]]+\(editor-refresh-autocomplete' src/cadr-tui/editor.lisp
(no matches; exit 1)
```

Native 100×24 PTY after a fresh `./build.sh`, then `/reload`:

```text
 Reloaded keybindings, extensions, skills, prompts, themes, and context files
```

The capture contains neither `session>` nor `system cadr-cli is out of date`.

Deterministic suite:

```text
$ ./scripts/test-cl.sh
checks: 7273
pass:   7273
skip:   0
fail:   0
```

Full verification entry point:

```text
$ ./scripts/verify.sh
exit: 0
deterministic stages: 10/10 PASS
terminal lifecycle PTY: 6/6 PASS
live stages: 2/2 PASS
live FiveAM items: 7 PASS, 1 SKIP (ANTHROPIC_API_KEY is not set), 0 FAIL
live FiveAM checks: 31 PASS, 1 SKIP, 0 FAIL
```
