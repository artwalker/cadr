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

Run the Part A mechanical gate:

```sh
./scripts/test-render-diff.sh
```

That command is the harness self-test. The permanent release gate captures the
complete 20-scenario by 2-dimension matrix and then invokes the fail-closed
analyzer on those fresh artifacts:

```sh
python3 ./scripts/render-diff.py gate \
  --pi-repo . \
  --output /tmp/cadr-render-gate \
  --analysis-output /tmp/cadr-render-gate-analysis
```

`scripts/verify.sh` runs this exact real-input path as
`fixed-baseline render differential`; it does not substitute a synthetic
fixture or a previously captured matrix. The fixed baseline is archived from
the Cadr repository's retained baseline commit object. The immutable hydrated
cache is reused only when its marker matches that commit.

Every capture produces immutable `.raw` bytes and a sibling SHA-256 file.  A
`.normalized.raw` derivative is for adjudication only; raw evidence is always
retained.

Analyze a complete Part B capture and require a disposition for every
difference:

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
constructors at 22 source construction sites, and all 13 Cadr overlay kinds.
The gate extracts the command list and construction sites directly from the
fixed baseline and cross-checks the tracked
`baseline-interface-inventory.json`; source archives without `.git` validate
against that already-audited inventory, while a real repository must prove the
inventory still matches the fixed commit object. Overlay kinds are always
extracted from current Cadr source. A new command, constructor, construction
site, overlay kind, or registry row without a real manifest checkpoint fails
before capture. This includes secondary and tertiary states such as auth type
-> provider -> OAuth/API-key dialogs, session rename/delete, tree label,
settings submenus, and extension custom UI.

## Fixed dimensions and scenarios

| Dimension | Columns x rows | Reason |
|---|---:|---|
| `wide` | 100 x 32 | Normal development terminal with room to expose spacing and footer placement. |
| `narrow` | 48 x 20 | Forces wrapping, compact help, overlay clipping, and wide-character accounting. |

The manifest contains 20 scripted scenarios, 83 checkpoints, and all 34 Goal 15
coverage labels:
fresh/existing/untrusted startup; plain/Markdown/code/CJK/emoji conversation;
all seven tools; missing-read/nonzero/timeout errors; every required core and
authentication overlay; streaming abort and both busy queues; provider and
fatal errors; all 22 slash commands; generic and provider-specific auth layers;
settings secondary/tertiary layers; extension select/input/editor;
autocomplete; and post-TUI resume output. Every scenario runs in both
dimensions, producing 40 fresh captures. Checkpoints preserve intermediate
frames instead of judging only the final screen.

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
| Working spinner frame | One UTF-8 braille code point only between the exact accent SGR and exact dim `Working...` suffix to `⠋` | Frame phase is scheduler-dependent; color and surrounding text remain checked. |
| Crash-log ID | Digits only between exact `cadr-crash-` and `.log` delimiters to `<CRASH_ID>` | PID/time/counter identity is intentionally unique; directory, filename grammar, and mode are tested elsewhere. |

No rule removes or folds whitespace, ANSI sequences, colors, cursor positions,
line endings, punctuation, ordering, whole lines, UUID-shaped arbitrary text, or
unscoped numbers.  The raw `.raw` and SHA-256 files remain the authority.

## Determinism boundary and blind spots

The harness fixes model output and terminal inputs, not scheduler write
boundaries. Even a non-stream faux response crosses worker and TUI render
threads, so an intermediate editor/spinner frame may be coalesced differently.
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

## Relationship to the parity ledgers

This is the only permanent gate whose oracle is actual rendered output from the
fixed pi baseline. The four parity ledgers and their tests inspect Cadr-side
behavior, source dispositions, non-functional measurements, and presentation
contracts; none independently executes pi's renderer. The differential is not
a fifth ledger: it is a cross-implementation oracle that catches a wrong or
incomplete Cadr-side assertion. Conversely, it cannot replace the four ledgers
because its scripted scenarios do not cover every payload, source capability,
performance workload, or real-user interaction.
