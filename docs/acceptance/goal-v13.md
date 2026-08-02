# Goal 13 acceptance ledger

## Part A — Goal 12 carry-over defects

### Result

Part A is implemented and committed before the presentation audit begins.  The
fixes are deliberately split at the transport/presentation boundary: the
provider reducer owns authoritative tool-call JSON, while the TUI only changes
how already-parsed arguments are displayed.  Tool result text, session content,
payloads, and wire events are unchanged.

| Item | Baseline evidence | Cadr implementation | Regression |
|---|---|---|---|
| OpenAI Responses tool arguments | `packages/ai/src/api/openai-responses-shared.ts:629-645` replaces the scratch JSON with `response.function_call_arguments.done.arguments` and emits only a missing suffix when it is a prefix extension | `src/cadr-ai/providers/openai.lisp:615-661` now performs the same authoritative replacement; a correction never appends the bad scratch value | `GOAL13-STREAMED-TOOL-ARGUMENTS-ARE-EXACT-AT-EVERY-DELTA-BOUNDARY`; `GOAL13-OPENAI-AUTHORITATIVE-TOOL-ARGUMENTS-REPLACE-CORRUPT-DELTAS` (`test/cadr-ai/goal12-provider-capabilities-test.lisp:292-356`) |
| Bash command and explicit timeout | `packages/coding-agent/src/core/tools/bash.ts:226-231` applies `toolTitle` + bold to the command and `muted` only to an explicitly supplied timeout | `src/cadr-cli/tui.lisp:1389-1397`; `src/cadr-tui/components.lisp:1593-1634` | `GOAL13-EXPLICIT-BASH-TIMEOUT-APPEARS-ONLY-WHEN-MODEL-SUPPLIES-IT`; `GOAL13-TOOL-TITLE-COLORS-PATH-SHORTENING-AND-READ-RANGE-MATCH-BASELINE` (`test/cadr-cli/tui-test.lisp:1358-1442`) |
| Read range color | `packages/coding-agent/src/core/tools/read.ts:67-76` renders the `:start-end` suffix with `warning` | `src/cadr-tui/components.lisp:1626-1630` separates the suffix from the accent-colored path | `GOAL13-TOOL-TITLE-COLORS-PATH-SHORTENING-AND-READ-RANGE-MATCH-BASELINE` |
| Home-shortened paths | `packages/coding-agent/src/core/tools/render-utils.ts:10-17,75-84`; find/grep call the same helper | `src/cadr-cli/tui.lisp:1398-1454` reuses `cadr-tui:shortened-home-path` for read/write/edit/grep/find/ls | `GOAL13-TOOL-TITLE-COLORS-PATH-SHORTENING-AND-READ-RANGE-MATCH-BASELINE` |
| Concurrent Slynk/FASL isolation | build and test already promised a fresh HOME, but inherited ASDF/XDG configuration could still redirect both SBCL processes into one cache | `scripts/test-cl.sh:16-24` and `build.sh:34-40` bind both `XDG_CACHE_HOME` and `ASDF_OUTPUT_TRANSLATIONS` below their unique `mktemp` roots | `GOAL10-SLYNK-INIT-IS-ISOLATED-FROM-THE-BUILD-USERS-HOME` (`test/cadr-cli/remote-repl-test.lisp:285-372`) |

The Slynk choice is isolation, not locking.  Compiler artifacts are disposable
per invocation, so a shared-cache lock would add failure and cleanup states for
no benefit.  Unique ASDF output trees make concurrent compilation structurally
disjoint, including when a caller has exported a global
`ASDF_OUTPUT_TRANSLATIONS` or `XDG_CACHE_HOME`.

### Why the old gates missed these defects

- The old streamed-argument test sent one incomplete prefix and asserted only
  that repaired JSON was temporarily usable.  It never sent the authoritative
  `function_call_arguments.done` event, never finalized the call, never tried
  every split boundary, and never compared the assembled raw JSON or parsed
  values character-for-character.
- Tool-title snapshots stripped ANSI, used relative paths, and therefore could
  not distinguish accent from `toolTitle`/`warning` or `/root/...` from `~/...`.
- The explicit-timeout regression encoded an earlier incorrect ruling that the
  suffix must always be absent.  Goal 13 supersedes that assertion with the
  fixed-baseline contract: absent by default, present only when the model
  supplies `timeout`.
- The Slynk test isolated `HOME` but not the two variables ASDF actually honors
  for output placement.  A clean single process passed; two processes could
  still be redirected to one externally configured cache.

### Mechanical verification

`./scripts/test-cl.sh` after the Part A changes:

```text
cadr test summary: systems=8 checks=11498 pass=11498 skip=0 fail=0
```

Part B begins from this committed state and is audit-only: no presentation code
will change until the complete presentation ledger is committed.

## Part B — complete presentation audit

Part B audited the fixed baseline against Cadr without changing presentation
code.  The fourth ledger is `docs/presentation-parity.md`; it contains all 55
semantic theme tokens, 52 visible-element contracts, 10 path/number formats,
and 6 non-terminal surfaces, each with baseline and Cadr `file:line` evidence.

The result is `123 = 82 一致 + 39 不一致 + 2 有意差异`.  The 39 row-level
differences reduce to 11 implementation clusters: tool subsegment colors,
tool path shortening/links, invalid-argument copy, read/write highlighting,
tool-specific result colors, edit preview, compact-read titles,
skill/branch/compaction transcript components, tree timestamps, OAuth HTML,
and session-export presentation.

The audit found two important false positives in the older ledgers.  First,
having all syntax tokens and a Markdown highlighter did not prove that read and
write tool previews used them.  Second, parsing `pageBg/cardBg/infoBg` did not
prove that the real exporter consumed those values: the parser had no
production caller.  These are exactly the class of defects this fourth axis is
meant to expose.

Part B source-diff boundary from `e04d9230f`:

```text
docs/presentation-parity.md
docs/acceptance/goal-v13.md
```

No `src/`, `test/`, build, script, or fixture file changed during Part B.
