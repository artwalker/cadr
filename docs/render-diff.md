# Fixed-baseline render differential

## Contract

The render differential drives fixed pi baseline
`74caa2649f10ed71b4378ce69f5d9fbfd2466ca5` and Cadr with the same scenario
manifest and their native faux providers.  Each side runs under a real PTY.
The collector fixes terminal size, dark theme, `C.UTF-8`, `TERM=xterm-256color`,
`COLORTERM=truecolor`, isolated home/config/cwd directories, offline mode, faux
response timestamps, response IDs, token boundaries, and response order.  It
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
  --scenario plain-text --dimension wide \
  --output .tmp/render-diff
```

Run the Part A mechanical gate:

```sh
./scripts/test-render-diff.sh
```

Every capture produces immutable `.raw` bytes and a sibling SHA-256 file.  A
`.normalized.raw` derivative is for adjudication only; raw evidence is always
retained.

## Fixed dimensions and initial scenarios

| Dimension | Columns x rows | Reason |
|---|---:|---|
| `wide` | 100 x 32 | Normal development terminal with room to expose spacing and footer placement. |
| `narrow` | 48 x 20 | Forces wrapping, compact help, overlay clipping, and wide-character accounting. |

Part A proves the transport with a fresh startup and a one-turn plain-text
conversation.  Part B expands the same manifest to the complete scenario
matrix required by Goal 15; it does not introduce another harness.

## Normalization candidates

Normalization does not define correctness.  These substitutions are narrowly
scoped candidates submitted for the Part B user ruling, and raw streams remain
the authority.

| Candidate | Exact substitution | Reason |
|---|---|---|
| Isolated home | Per-side temporary home prefix to `<HOME>` | The harness necessarily gives the programs distinct isolated homes; only the concrete prefix is replaced. |
| Isolated cwd | Per-side temporary workspace prefix to `<CWD>` | Same reason; path punctuation, suffixes, line breaks, and styling remain checked. |
| Product/version header | Exact `pi v0.83.0` or `cadr v0.2.0` to `<PRODUCT> v<VERSION>` | Product rename and release version are already approved differences; only the two literal values are replaced. |
| Product prose/command tokens | Exact onboarding phrases and exact ` pi --session `/` cadr --session ` command tokens to product placeholders | The product rename is approved. Arbitrary `pi`/`cadr` substrings are deliberately not replaced. |

No rule removes or folds whitespace, ANSI sequences, colors, cursor positions,
line endings, punctuation, ordering, whole lines, elapsed-time fields, or UUIDs.
Dynamic values not yet proven unavoidable remain visible differences until Part
B gives each one a disposition.

## Determinism boundary and blind spots

The harness fixes model output and terminal inputs, not scheduler write
boundaries.  A self-replay check is therefore required before any raw byte
difference is attributed to Cadr.  Genuine cross-run variation must be reduced
to its exact dynamic value or recorded as a harness defect; it cannot be hidden
with a layout/color normalization.

This gate intentionally does not replace real-user testing.  Faux replay cannot
cover real-provider chunk timing, mouse interaction, resize transitions, host
terminal bugs, or state accumulated during long-running sessions.
