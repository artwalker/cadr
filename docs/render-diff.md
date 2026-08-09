# Fixed-baseline render differential

## Contract

The render differential drives fixed pi baseline
`74caa2649f10ed71b4378ce69f5d9fbfd2466ca5` and Cadr with the same scenario
manifest and their native faux providers.  Each side runs under a real PTY.
The collector fixes terminal size, dark theme, `C.UTF-8`, `TERM=xterm-256color`,
`COLORTERM=truecolor`, isolated home/config/cwd directories, offline mode, faux
response timestamps, response IDs, token boundaries, and response order.  It
installs an isolated fake `gh` executable so `/share` deterministically reaches
its successful user-visible URL path on both sides without external writes. It
captures with `RIPGREP_CONFIG_PATH` pinned to a fixture config containing
`--threads=1`: both products invoke `rg` without `--sort`, so result order
otherwise follows rg's parallel walker and flips under gate load; the pinned
single-threaded walker is deterministic and applies equally to pi and Cadr. It
captures the complete PTY byte stream, including ANSI SGR, cursor movement,
erase operations, terminal-mode setup/teardown, and post-TUI stdout.

The pi driver is copied into an archive materialized from the fixed commit.
The cache is hydrated with `npm ci --ignore-scripts`; generated provider data,
which git intentionally omits, is restored from the published fixed-version
`@earendil-works/pi-ai@0.83.0` artifact after verifying SHA-256
`f983c28a21209305ed9c274977e29130fa4d8848df6cdf37e9094d95cc7bc6d4`.
That build input is used only by the baseline process and never enters Cadr's
ASDF or release closure.
It constructs `AgentSessionRuntime` and `InteractiveMode` around pi's faux
provider.  The Cadr driver loads the five local ASDF systems, constructs a Cadr
agent around `make-faux-provider`, and runs the real `run-tui` composition root.
Neither driver calls a real provider.

Run one pair:

```sh
./scripts/render-diff.py capture \
  --scenario conversation-content --dimension wide \
  --output .tmp/render-diff
```

Run the harness self-test:

```sh
./scripts/test-render-diff.sh
```

The permanent gate has two explicit tiers. `scripts/verify.sh` runs the core
tier: 31 scenarios in both dimensions, producing 62 fresh captures before the
fail-closed analyzer runs:

```sh
python3 ./scripts/render-diff.py gate \
  --tier core \
  --pi-repo . \
  --output /tmp/cadr-render-gate \
  --analysis-output /tmp/cadr-render-gate-analysis
```

The full tier adds six branch-sweep scenarios, for 37 scenarios and 74 fresh
captures. Upstream baseline upgrades invoke it directly:

```sh
./scripts/test-render-diff-full.sh
```

Before a release tag, the executable aggregate first runs the ordinary verifier
and then this full tier on the same HEAD:

```sh
./scripts/verify-release.sh
```

Either stage failing blocks the tag; the wrapper does not create or push one.

Both tiers drive the same real-input path; neither substitutes a synthetic
fixture or a previously captured matrix. The fixed baseline is archived from
the Cadr repository's retained baseline commit object. The immutable hydrated
cache is reused only when its marker matches that commit.

Every capture produces immutable `.raw` bytes and a sibling SHA-256 file.  A
`.normalized.raw` derivative is for adjudication only; raw evidence is always
retained.

Analyze a complete capture and require a disposition for every difference:

```sh
./scripts/render-diff.py analyze \
  --output .tmp/render-matrix \
  --analysis-output .tmp/render-analysis
```

The analyzer first replays the unmodified PTY bytes through tmux.  It applies
value normalization only to the resulting semantic screen.  Replaying a
longer placeholder would change cursor columns and create fake stale cells, so
normalized streams are used only for per-checkpoint raw-byte segmentation.
`test/fixtures/render-diff/dispositions.json` is fail-closed: missing, stale,
duplicate, or unknown dispositions make analysis fail.

The scenario domain is fail-closed too. `reachable-interfaces.json` records all
22 fixed-baseline slash commands, 28 reachable interface states, 15 component
constructors at 22 source construction sites, all 13 Cadr overlay kinds, and
the required interface-significant-state domains. The latter currently lock 11
source-backed states: bash line-limit, byte-limit, overlong-line, empty-output,
nonzero-exit and timeout; a parallel tool batch; invalid tool arguments; and
manual, threshold and overflow compaction.
The gate extracts the command list and construction sites directly from the
fixed baseline and cross-checks the tracked
`baseline-interface-inventory.json`; source archives without `.git` validate
against that already-audited inventory, while a real repository must prove the
inventory still matches the fixed commit object. Overlay kinds are always
extracted from current Cadr source. A new command, constructor, construction
site, overlay kind, required significant state, or registry row without a real
manifest checkpoint fails before capture. A state may be uncaptured only when
its row has an explicit non-empty `notCapturedReason`; the current registry has
zero such exclusions. This includes secondary and tertiary states such as auth type
-> provider -> OAuth/API-key dialogs, session rename/delete, tree label,
settings submenus, and extension custom UI.

Every scenario that exercises a cancel path must end with one post-cancel
interaction: after the cancel checkpoint, send a message and assert the faux
provider's response renders (both sides). A screen checkpoint alone cannot see
a corrupted state machine — the goal 18 login deadlock left the screen exact
while the agent never consumed input again; only the follow-up message exposed
it. The three authentication cancel scenarios (`overlays-auth-oauth`,
`overlays-auth-device-code`, `overlays-auth-api-key`) set the pattern.

The complete tier also has a source-derived presentation-branch gate. The
checked fixed-baseline inventory contains 707 sink sites and 1,228 reachable
branches from 210 parsed TypeScript files plus nine terminal assets. It
classifies 682 sites/1,200 branches as printable terminal content and 25
sites/28 branches as terminal-protocol output. Typed in-root producer returns,
render-array pushes, slash-command metadata, authentication metadata, and
terminal assets are followed to their terminal sink; unresolved in-root
dataflow is a hard failure and is currently zero. Every printable branch must
be observed by a full-tier checkpoint or named in
`visible-string-exemptions.json` with an exact physical obstruction. The
exemption registry is currently empty. The core tier may defer this expensive
whole-branch proof, but it cannot change or waive its inventory.

## Fixed dimensions and scenarios

| Dimension | Columns x rows | Reason |
|---|---:|---|
| `wide` | 100 x 32 | Normal development terminal with room to expose spacing and footer placement. |
| `narrow` | 48 x 20 | Forces wrapping, compact help, overlay clipping, and wide-character accounting. |

The manifest contains 42 scripted scenarios. The 35-scenario core tier has 97
named checkpoints and 110 coverage labels; the seven full-only branch sweeps
raise the full tier to 109 checkpoints and 136 coverage labels:
fresh/existing/untrusted startup; plain/Markdown/code/CJK/emoji conversation;
all seven tools; missing-read/nonzero/timeout errors; every required core and
authentication overlay; streaming abort and both busy queues; provider and
fatal errors; all 22 slash commands; bash truncation by lines, bytes and within
a single line; empty/nonzero/timeout bash results; parallel tool calls; generic and provider-specific auth layers;
settings secondary/tertiary layers; extension select/input/editor;
autocomplete; and post-TUI resume output. Every selected scenario runs in both
dimensions, producing 70 core captures or 84 full captures. Checkpoints
preserve intermediate frames instead of judging only the final screen.

| Significant state | Deterministic trigger | Capture point |
|---|---|---|
| bash line limit | 2,001 newline-terminated short lines; below 50KB | `tools-significant-states/bash-line-limit` |
| bash byte limit | 400 complete 200-character lines; above 50KB and below 2,000 lines | `tools-significant-states/bash-byte-limit` |
| bash overlong line | one 60KB line | `tools-significant-states/bash-overlong-line` |
| bash empty output | `true` | `tools-significant-states/bash-empty` |
| bash nonzero exit | print one line, then exit 7 | `tools-failure/bash-nonzero` |
| bash timeout | two-second command with a one-second timeout | `tools-failure/bash-timeout` |
| parallel tool calls | one faux response containing two independent `read` calls | `tools-significant-states/parallel-tool-calls` |
| invalid tool arguments | numeric `read` path rejected by schema validation | `tools-significant-states/tool-invalid-arguments` |
| manual compaction | deterministic manual compaction event through the production interactive consumer | `compaction-status-manual/compaction-manual` |
| threshold compaction | deterministic threshold compaction event through the production interactive consumer | `compaction-status-threshold/compaction-threshold` |
| overflow compaction | deterministic overflow compaction event through the production interactive consumer | `compaction-status-overflow/compaction-overflow` |

Agent-backed significant-state checkpoints wait on an out-of-band
`agent_settled` marker published by both real drivers after their interactive
event consumer has handled the event, then wait for the synchronized frame
requested by that event to end. The marker alone is insufficient because render
ownership is asynchronous. No millisecond pause stands in for a completed frame.

The `/share` checkpoint is an approved intentional product-identity difference:
the fixed baseline displays `https://pi.dev/session/#...`, while Cadr displays
`https://cadr.dev/session/#...`. The fake `gh` returns the same fixed Gist URL to
both programs, so the disposition covers only the viewer boundary; the analyzer
still fails closed for every other byte and semantic-screen difference.

## Normalization candidates

Normalization does not define correctness.  These substitutions are narrowly
scoped candidates submitted for the Part B user ruling, and raw streams remain
the authority.

| Candidate | Exact substitution | Reason |
|---|---|---|
| Isolated home | Exact per-side temporary home prefix to `<HOME>` | The programs must use different isolated homes; punctuation and suffixes remain checked. |
| Isolated cwd | Exact per-side temporary workspace prefix to `<CWD>` | The programs must use different workspaces; punctuation and suffixes remain checked. |
| Isolated sandbox | Exact per-side temporary sandbox prefix to `<SANDBOX>` | Parent-directory text otherwise contains the random `mkdtemp` name. |
| Isolated session directory | Exact per-side temporary session directory to `<SESSION_DIR>` | Both drivers persist the same fixture state outside their product-specific config roots; suffixes and command syntax remain checked. |
| Fixed baseline cache | Exact `/tmp/cadr-render-diff-pi-74caa2649` to `<PI_BASELINE>` | The pi crash stack necessarily names the materialized immutable baseline. |
| Product/version header | Exact plain and observed styled `pi v0.83.0` / `cadr v0.2.0` forms to `<PRODUCT> v<VERSION>` | Product rename and release version are approved; surrounding SGR remains checked. |
| Terminal-title product | Exact OSC title prefix `π - ` to `<PRODUCT> - ` | Only the brand glyph is replaced; title existence, workspace suffix, framing, and BEL remain checked. |
| Product prose/config/commands | Exact onboarding sentences, `.pi/agent` / `.cadr`, untrusted-resource tokens, restart tokens, and styled/plain resume-command product tokens | These are direct consequences of the approved product rename; arbitrary substrings are not replaced. |
| Export filename | Exact fixed-clock `pi-session-2023-11-14T22-13-20-000Z_render-session.html` / Cadr counterpart to `<PRODUCT>-session-<FIXED_TIME>_<SESSION_ID>.html` | Prefix and ID spellings differ only by the approved brand and fixed driver identity. |
| Tool elapsed time | Digits only between the exact `Took ` and `s` delimiters to `<ELAPSED>` | Process scheduling makes wall time nondeterministic; wording, unit, placement, styling, and all other numbers remain checked. |
| Agent status spinner frame | One UTF-8 braille code point only between the exact accent SGR and the exact dim `Working...`, `Compacting context...`, `Auto-compacting... (escape to cancel)`, or `Context overflow detected, Auto-compacting... (escape to cancel)` suffix to `⠋` | Frame phase is scheduler-dependent; color and surrounding text remain checked. |
| Hidden hardware cursor | Exact tmux cursor record `<CURSOR X,Y,0>` to `<CURSOR hidden>` | Both products hide the hardware cursor and draw the editor cursor as a screen cell. Its retained internal coordinates are not observable; coordinates remain exact whenever `cursor_flag=1`. |
| Crash-log ID | Digits only between exact `cadr-crash-` and `.log` delimiters to `<CRASH_ID>` | PID/time/counter identity is intentionally unique; directory, filename grammar, and mode are tested elsewhere. |
| Bash full-output file | Exact `/tmp/pi-bash-<hex>.log` or `/tmp/cadr-bash-<decimal>-<decimal>.log` grammar to `/tmp/<PRODUCT>-bash-<OUTPUT_ID>.log` | The suffix is process-generated; the full warning copy, punctuation, color and replay geometry remain checked. |

No rule removes or folds whitespace, ANSI sequences, colors, visible cursor positions,
line endings, punctuation, ordering, whole lines, UUID-shaped arbitrary text, or
unscoped numbers.  The raw `.raw` and SHA-256 files remain the authority.

## Determinism boundary and blind spots

The harness fixes model output and terminal inputs, not scheduler write
boundaries. Even a non-stream faux response crosses worker and TUI render
threads, so an intermediate editor/spinner frame may be coalesced differently.
A checkpoint first drains the PTY and waits for any open synchronized-output
frame (`CSI ? 2026 h` through `CSI ? 2026 l`) to close; it never records a
half-written frame merely because the awaited text arrived first.
Semantic replay writes the finite raw stream, sends a cursor-position query,
and waits for the terminal reply before capturing the pane, so two temporarily
identical pre-replay panes cannot be mistaken for a completed replay.
An aborted stream additionally waits for the driver-side `agent_settled`
handshake; seeing `Operation aborted` alone is not proof that the worker has
removed its final `Working...` frame.
Replacing the old partial replay with that completion protocol changed stored
semantic SHA values without changing a product frame. The disposition ledger
was regenerated only from the now-complete screens: protocol-only rows lost
stale semantic classes, semantic rows retained their already-approved classes,
and every remaining pair stays exact and fail-closed.
A self-replay check is therefore required before any raw byte difference is
attributed to Cadr. `replay-check` requires every checkpoint's
terminal-emulated screen (including cursor) to be identical and reports
normalized raw identity separately for every scenario. Such raw scheduling
bytes remain retained and classified; they are not hidden by layout/color
normalization.

```sh
./scripts/render-diff.py replay-check \
  --scenario stream-interrupt-queue --dimension wide \
  --output .tmp/render-stream-replay
```

This gate intentionally does not replace real-user testing.  Faux replay cannot
cover real-provider chunk timing, mouse interaction, resize transitions, host
terminal bugs, or state accumulated during long-running sessions.

The pre-Goal-17 matrix failed for a simpler reason: byte-exact comparison can
only judge a state that a scenario actually creates. Its hand-picked screens
never entered the line-limit, byte-limit, overlong-line, or three compaction
branches, so those branches had no obligation and no failure signal. The
source-derived branch inventory closes that omission class for printable
baseline branches; it does not claim to cover non-string subprocess semantics,
provider payloads, model-visible tool results, or agent-event ordering. Those
remain separate gates.

The Goal 18 login-form (A5) and startup-resource (H2) defects exposed the same
law from another angle: **the gate's strength is bounded by the states the
scenarios create, not by the completeness of the interface inventory.** The
672/672 branch-coverage number measures whether inventoried branches are
driven; when no scenario ever creates a state, every branch behind that state
is neither in the denominator nor failing. The rule for every future scenario
is therefore: any interface whose rendering branches on the presence of a
resource or state must have both an empty-state and a populated-state capture
— one of the two is never enough. The populated startup-resource capture
(`startup-resources`) and the empty startup captures (`startup-first`,
`startup-existing`, `startup-untrusted`) are the reference pair.

## Relationship to the parity ledgers

This is the only permanent gate whose oracle is actual rendered output from the
fixed pi baseline. The four parity ledgers and their tests inspect Cadr-side
behavior, source dispositions, non-functional measurements, and presentation
contracts; none independently executes pi's renderer. The differential is not
a fifth ledger: it is a cross-implementation oracle that catches a wrong or
incomplete Cadr-side assertion. Conversely, it cannot replace the four ledgers
because its scripted scenarios do not cover every payload, source capability,
performance workload, or real-user interaction.
