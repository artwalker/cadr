# External Review — 2026-08-14

Reviewer: Kimi Code CLI (external, read-only pass over HEAD `4c8e31416`).
Scope: development process, code, documentation. This file is a record, not an
adjudication. Items that change a gate's obligation unit, an
intentional-difference class, or policy text are marked **[needs
adjudication]** and belong in `docs/proposals/` or `docs/open-questions.md`
before adoption.

All file:line evidence was measured on 2026-08-14; recount with the commands
in `AGENTS.md` before quoting these numbers elsewhere.

## 1. Process

1. **CI has not run since 2026-08-01.** `.github/workflows/ci.yml` invokes
   `scripts/verify.sh`, but the last CI run predates goals 11–20, and the CI
   environment runs with all credentials empty (live stages SKIP) and without
   `CADR_RELEASE_GATE=1`. The final backstop of the five-ledger system is
   currently disconnected.
2. **`scripts/verify.sh` is not read-only.** `run_goal11_gate` rewrites
   `docs/performance.md` and `docs/benchmarks/performance-history.json`,
   producing trailing "append gate run" commits (e.g. `b31473ba2`,
   `7558184c5`, `b81a049f7` on 2026-08-14). Suggest a read-only verify plus a
   separate `record` subcommand; also record verify's own wall-clock time —
   the last recorded figures (2m46s–3m29s) are from goal 9/10, when the
   pipeline had far fewer stages.
3. **Ledger rot: the cure is written but not built.** 108/1,052 cadr-side
   mappings in `docs/source-parity.md` §0 remain rotten because
   `scripts/check-source-parity-drift.sh` only checks the pi side. Promoting
   the existence check to a verify stage is a few lines of shell. A second
   rot class — line-number drift (e.g. `models.generated.lisp` regeneration
   moved 37 referenced lines) — is invisible to existence checks and needs
   its own accounting. The `sb-introspect`-derived mechanism in
   development-policy §6.3 covers part of this; it is not yet scheduled.
   **[needs adjudication for gate changes]**
4. **Advisor adjudication with user veto is de facto practice but not written
   into `docs/development-policy.md`** (§5.5 still requires user
   adjudication; goal20-part-a and I04 were advisor-ruled). Rulings must also
   be written back to the proposal file's Status line:
   `docs/proposals/goal20-i04-scoped-covering.md` still says "awaiting
   adjudication" though the ruling landed 2026-08-14, and
   `docs/proposals/goal-v13-session-export-assets.md` still says "blocked
   pending authorization" though the assets were approved and goal 13 closed
   2026-08-03. **[needs adjudication — policy text]**
5. **Persistent rulings live in gitignored files.** `.gitignore:28` excludes
   `/goal*.md`; `goal20-state.md` (89KB) holds rulings with lasting force
   (e.g. the three I04 tightening amendments). Loss of that file is loss of
   the decision chain. Suggest splitting the state file into a live queue
   (root, untracked) and an archived review log (under `docs/`, tracked).

## 2. Code

1. **Two "TS module as one defun" monoliths** are the highest-value targets
   for the goal 20 Part K burn-down:
   - `src/cadr-cli/interactive/controller.lisp:217` — `run-tui`, a single
     2,659-line defun with ~90 keyword parameters, ~70 `labels` functions,
     30+ shared mutable lexical variables.
   - `src/cadr-cli/bootstrap/commands.lisp:291` — `cli-handler`, a single
     2,261-line defun; sequential `let*` with `declare ignore` bindings used
     as imperative statements.
   - Same-file proof of the pattern: the 12-branch type-dispatch chain
     appears twice, verbatim (`controller.lisp:2441-2499` and `2726-2775`).
     A shared selector base class with `defmethod handle-event` deletes both.
2. **O(n²) streaming accumulation across providers** —
   `anthropic.lisp:528,559`, `openai.lisp:581,627`, `google.lisp:339`,
   `bedrock.lisp:705,726` all do `(concatenate 'string whole delta)` per
   token; `bedrock.lisp:679-682` appends per block. Use adjustable strings
   or chunk lists joined once. Likely below the pi baseline; belongs in the
   Part O paired-path set.
3. **Real bug: codex websocket statistics race** — `websocket.lisp:218-226`
   and `394-419` mutate a shared plist/hash outside the lock that readers
   (`:229-235`) and reset (`:237-246`) hold. Also `read-websocket-frame`
   (`:165-191`) ignores the FIN bit (no fragmentation support), and
   `websocket-url-as-http-url` (`:279-285`) is a transcription leftover: both
   branches are identity mappings.
4. **Error-type consistency.** 188 untyped `(error "...")` sites (101 in
   cadr-cli) bypass the `cadr-error` hierarchy; `json.lisp:364-373` rethrows
   every `json-parse-error` as `sse-protocol-error` (mislabeled and hides the
   real type); 117 `ignore-errors` sites; only 7 `restart-case` sites in the
   whole tree — the condition system is used as exception classes only.
   Also `cadr-core/time.lisp:5-7` `unix-milliseconds` is built on
   1-second-granularity `get-universal-time` — milliseconds in name, seconds
   in fact; audit call sites before it feeds ordering or ID generation.
5. **Systemic plist culture and package leaks.** `getf` appears on ~1,364
   lines; event payloads use plists with `(list :missing)` sentinels
   (`agent-loop.lisp:187-204, 364-371`). `cadr-ai::` internal symbols are
   referenced from outside the package on 796 lines / 63 distinct symbols;
   `cadr-agent::` on 231 lines. Export lists are not the real API boundary;
   suggest a ratchet gate (count may only decrease). **[needs adjudication]**
6. **Always-true assertion residue.** goal 20 P0-3 purged three instances,
   but `test/cadr-cli/goal20-part-l-test.lisp:62-65` still asserts
   `(null (find "NIL" lines))` immediately after `(null lines)` (dead), and
   source-grep assertions (symbol-name appears in source text) remain in the
   same file's `:37-50`. Sweep to the standard P0-3 set.
7. Minor mechanical duplication: the trim character literal
   `'(#\Space #\Tab #\Newline #\Return)` is repeated 79 times tree-wide;
   `(not (null x))` boolean coercion appears 16 times in the four sampled
   files; the "editor mutation epilogue triple" is scattered across
   `editor.lisp` (412-414, 500-503, 520-523, 699-701, 1426-1430) without a
   `with-editor-mutation` guard.

Strengths worth keeping (from the same pass): `cadr-core` is genuinely
Lispy; `define-redacted-print-object` (`cadr-core/redacted-print.lisp:13-20`)
is the model of a checkable benefit; cbor.lisp is rigorous (limits, cycle
detection, duplicate-key rejection); the provider generic-function layer
(255 defmethods) is the right design; sampled FiveAM tests have concrete,
byte-exact assertions.

## 3. Documentation

1. `CHANGELOG.md` [Unreleased] has `### Changed` twice (:10, :191) and
   `### Fixed` twice (:56, :202); one entry runs 25 lines and mixes release
   notes with goal bookkeeping.
2. `docs/README.md` still indexes "Current Goal 10" (closed 2026-08-01);
   goal-v11–v20 acceptance reports are unindexed; `docs/benchmarks/` and
   `docs/third-party/` are missing from the index.
3. `docs/source-parity.md` contains four lines over 5KB (longest 36,624
   bytes, :624); one-line diffs cover dozens of symbols, defeating line-based
   review and blame. Split by symbol.
4. Embedded scale figures drift: policy says "1,038 mappings" (measured
   1,052 the next day) and has both "680 rows" (:141) and "670 rows" (:152).
   Generate all such counts by script (the `write-test-check-anchor.py`
   pattern already works for test counts).
5. `docs/development-policy.md` tells the "thirteen full-screen SHAs" story
   three times (:33, :131, `AGENTS.md:151`); `AGENTS.md` is a hand-synced
   duplicate of policy. Make `AGENTS.md` a pointer; keep one source.
6. `docs/open-questions.md`'s only "pending" item (`OQ-G20-AGENT-EVAL-TOOL`)
   was adjudicated the same day — misfiled; and there is no single queue for
   the 38 `PENDING ADJUDICATION` rows in `docs/source-parity.md` (blocked on
   the `goal18-l1b` proposal since 2026-08-12).
7. Hygiene: `.tmp/` holds ~897MB of local render artifacts (untracked, but
   worth a periodic cleanup script).

## 4. Meta-observation

The recurring goal-20 lesson — gates green while the user finds defects in a
real terminal (five times; latest is P0-4, "cadr shows nothing during an
agent turn") — shows the differential gates cover static checkpoints, not
the time dimension of interaction. A new detection class (e.g. timestamped
PTY assertions: "some output within every N-second window") would cover
liveness defects that no static checkpoint count can.
