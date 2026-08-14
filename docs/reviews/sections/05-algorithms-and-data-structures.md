# 05 — Algorithms and Data Structures

Scope: the algorithmic hot spots of the cadr codebase, ordered by relevance to goal20 (Part O paired-performance deficits first, then per-frame/per-keystroke complexity, then discipline items). Evidence basis: direct code reads of the cited files plus `docs/performance.md` and `docs/development-policy.md`; every claim carries a file:line, cited with full repository paths per `AGENTS.md`. Classic citations were re-verified against primary sources.

## 1. Streaming accumulation is O(n²) — chunk lists, not ropes

**Rope/chunked text accumulation — Boehm, Atkinson & Plass, "Ropes: an Alternative to Strings", Software—Practice & Experience 25(12):1315–1330 (1995).** Repeated concatenation onto an immutable string copies the whole prefix per append, so accumulating n bytes in d deltas costs Θ(n·d); keeping chunks and flattening once is Θ(n). The full rope machinery (balanced trees, deferred concat, shared substrings) buys random access during accumulation — which a streaming provider never needs.

cadr evidence — all four providers copy the entire accumulated text on every delta:

- Anthropic (`reduce-provider-sse-event`, `src/cadr-ai/providers/anthropic.lisp:459`): text `:527-530`, thinking `:536-540`, signature `:545-549`, tool args `:556-559`.
- OpenAI (`reduce-provider-sse-event`, `src/cadr-ai/providers/openai.lisp:554`): text `:580-583`, thinking `:594-598`, tool args `:624-627`.
- Google (`google-text-delta`, `src/cadr-ai/providers/google.lisp:306`): thinking `:328-332`, text `:338-341`.
- Bedrock (dispatch at `src/cadr-ai/providers/bedrock.lisp:733`; `append-text-delta` `:692`, `append-thinking-delta` `:711`): text `:703-706`, thinking `:722-725`, signature `:807-814`, tool args `:825-833`.

Two second-order quadratics ride on top. Anthropic/OpenAI/Bedrock re-run a full parse over the whole accumulated partial JSON on every tool-argument delta (`src/cadr-ai/providers/anthropic.lisp:560-564`, `src/cadr-ai/providers/openai.lisp:628-632`, `src/cadr-ai/providers/bedrock.lisp:840-841`) — parse work itself is Θ(n) per delta, so tool-call turns pay Θ(n·d) twice. Bedrock additionally copies the content-block list per block (`src/cadr-ai/providers/bedrock.lisp:678-681`, `(append ... (list block))`) and walks it with `(nth index ...)` per delta (`src/cadr-ai/providers/bedrock.lisp:697`, `:822`); the other providers already use the `nconc`-based `append-content-block` (`src/cadr-ai/provider.lisp:438-442`).

Actionable:

- Accumulate deltas in a chunk list (or an adjustable string with fill-pointer / `with-output-to-string`, precedent at `src/cadr-ai/json.lisp:196-251`), flatten once at content-block close — O(n²)→O(n) with CL-idiomatic code, no rope library.
- Defer partial-JSON re-parsing to block completion (or throttle to one parse per N deltas).
- Bedrock: switch to `append-content-block` and keep blocks in a vector indexed by block index, eliminating the per-delta `nth` walk.
- Validation: add a long-generation streaming case to the Part O paired paths (e.g. a 64k-token completion replay) and assert superlinear-flat scaling (2× tokens ⇒ ~2× time, not 4×) [needs adjudication — new paired-benchmark row]. Maps to Part O.

## 2. Journal/session persistence — profile first, optimize second

**Measure-before-optimize — Knuth, "Structured Programming with go to Statements", ACM Computing Surveys 6(4) (1974).** cadr already has the canonical proof: a per-entry `make-random-state` reopening the OS RNG "dominated journal_append (~70% of the 8.45× paired-path gap)" (`src/cadr-agent/session/journal.lisp:14-18`); seeding once per image dropped the enforced ratio 8.45×→1.93× (`docs/performance.md:529`, history `:534-535`). One profiler-driven line beat any amount of hypothesizing.

Numbers discipline first: the 7.67×/4.29×/3.70× figures are a 2026-08-14 informational quick run (`docs/performance.md:533`); the current enforced rows are journal_append 1.93×, journal_read 5.48×, session_load 6.39× (`docs/performance.md:526-529`, note the differing column orders `:519-520` vs `:531-532`). Part O planning must quote the enforced rows.

Path anatomy, so the hypotheses below are concrete. Append: `append-session-entry` (`src/cadr-agent/session/journal.lisp:261`) under a mutex, serializing via `session-entry-to-json` (`:37`) and `write-jsonl-object` (`src/cadr-agent/session/codec.lisp:568`). Read: `read-session-objects` (`src/cadr-agent/session/migration.lisp:30-58`) loops `read-line` + `parse-session-line` → `parse-json` per line. Load: `load-session` (`:459`) validates the header (`:463`), builds the by-id hash and entries list (`:479-527`), and reduces max over all activity timestamps (`:533-543`); `resume-session`/`continue-session` go through `list-sessions` → `load-session` per file (`src/cadr-agent/session/discovery.lisp:133`, `:146`). The Part O benchmark measures exactly these functions (`scripts/goal20-paired-paths.lisp:613`, `:638`, `:665-680`, `:705-708`).

Hypothesis list for the remaining read/load gap, with verdicts from code reading — confirm the live ones with `sb-sprof` before touching anything:

- H1 "per-event fsync": refuted. No fsync exists on the journal path; durability is one `finish-output` per line (`src/cadr-agent/session/codec.lisp:568-571`). Pi's advantage is not durability-related.
- H2 "whole-file re-encode per append": refuted for steady state; a full rewrite happens only on session creation (`src/cadr-agent/session/journal.lisp:279-302`) and v1/v2 migration (`src/cadr-agent/session/migration.lisp:466-478`).
- H3 "no batch commit": confirmed in JSONL form — every append opens, writes, closes the file (`src/cadr-agent/session/journal.lisp:267-274`); the benchmark replays 128 such entries (`scripts/goal20-paired-paths.lisp:678-679`). The alternate storage layer has the same shape: `session-storage-append-entry` (`src/cadr-agent/storage/jsonl.lisp:260`) → `execution-env-append-file` (`src/cadr-agent/execution-env.lisp:308-314`) → one `with-open-file` per call (`src/cadr-agent/execution-env.lisp:273-286`), so the fix must cover both layers. Cheap fix: cache the append stream per session (still line-flushed), or group N entries per open.
- H4 "JSONL↔SQLite dual write": refuted — JSONL is the only production store; `src/cadr-cli/` contains zero sqlite references. `src/cadr-agent/sqlite-storage.lisp` is an alternate backend exercised only by tests.
- H5 (new, likely dominant): per-line `parse-json` cost including exact-rational number parsing (`src/cadr-agent/session/migration.lisp:30-58` → `src/cadr-ai/json.lisp:102-156`, see §3), and on the write side per-object hash-key sorting in the serializer (`src/cadr-ai/json.lisp:471-476`).

SQLite assessment, for when that backend is adopted:

- WAL is already on (`src/cadr-agent/sqlite-storage.lisp:99-103`); under WAL, `synchronous=FULL` can drop to `NORMAL` — WAL's documented durability model allows it, but this changes durability semantics, so flag before doing it.
- Every append is its own transaction of 5–6 statements (`src/cadr-agent/sqlite-storage.lisp:524-612`); group commit (one transaction per N appends) is the classic 10–100× lever.
- No persistent prepared statements exist anywhere in the file, so cl-sqlite re-parses SQL per call — prepare once per connection.

Method (policy-conformant): `sb-sprof` statistical profiles of `load-session` / `read-session-objects` on the 10 MiB fixture (latency rows at `docs/performance.md:229`), attached to the Part O entry — policy already requires a profile for a path that misses its bar (`docs/development-policy.md:310`). Maps to Part O.

## 3. JSON codec — exact rationals: real benefit, measurable cost

**Exact decimal parsing.** Parsing `1.1` to the rational `11/10` (`src/cadr-ai/json.lisp:132`, `:139-140`, `:152-156`; shift bounded by `+maximum-json-decimal-shift+` at `:13`, `:141-145`) eliminates float-representation drift, which is what makes byte-stable session round-trips — and thus source-parity claims — cheap to verify. The cost: every decimal literal in every journal line allocates a bignum-powered rational, and session files are decimal-heavy (timestamps, costs, token rates).

Parser core, for the profile reader:

- Hand-rolled recursive descent with integer-index `peek`/`take` closures (`src/cadr-ai/json.lisp:158-362`, esp. `:166-170`); no displaced arrays.
- Strings via `with-output-to-string` (`:196-251`) — no per-char concatenate; surrogate pairs handled at `:220-248`.
- Numbers: one `subseq` per token (`:261-262`) plus up to two more `subseq` and one `concatenate` inside decimal conversion (`:123-131`).
- Arrays accumulate then `coerce (nreverse ...)` (`:302-304`); objects are `equal` hash tables (`:310-311`).
- Nesting depth guard 256 (`:12`, enforced at `:336-347`).

Serializer side:

- Integers take the cheap `princ` path (`src/cadr-ai/json.lisp:451`); rationals go through `terminating-rational-json-text` (`:409-443`, called via `write-string` at `:452-455`), which builds two intermediate concatenated strings per rational (`:426`, `:431-436`, `:438-443`) instead of writing digits to the stream.
- Non-terminating rationals (denominator ≠ 2^a·5^b) signal an error (`:417-420`) — any float-path proposal must keep this contract visible.
- `write-json-value` (`:445-495`) sorts hash keys per object (`:471-476`) and re-coerces sequences per array (`:488`).

Actionable: (a) benchmark a 10 MiB session parse/serialize against pi's `JSON.parse`/`stringify` before changing anything (this is the session_load 6.39× / journal_read 5.48× hot path, §2 H5) — Part O; (b) stream digits in `terminating-rational-json-text` and drop the two intermediate strings — pure allocation fix, no semantics change; (c) only if the profile shows rational conversion dominating, consider a double-float read path with exact rationals retained where byte-parity demands — this changes number semantics and touches the behavior-parity ledger [needs adjudication].

## 4. Unicode width — linear range chains, no table at all

**Interval table + binary search (standard wcwidth construction, per Unicode Annex #11 data).** The premise to check was "sorted intervals + binary search vs linear scan"; the reality is a third thing: hand-written literal range chains walked sequentially per character — `combining-character-p` is a flat `or` of ~40 clauses (`src/cadr-tui/unicode.lisp:14-57`), `wide-codepoint-p` 11 ranges (`:106-119`), with `emoji-codepoint-p` (`:98-104`) and `terminal-spacing-mark-p` (`:76-93`) in the same shape, plus `sb-unicode:general-category` calls (`:18-20`, `:60-63`, `:71-74`, `:80-82`). The width entry points `grapheme-width` (`:295-344`) and `grapheme-span-width` (`:346`) call these per cluster, so the linear walk is paid once per grapheme per reflow. An ASCII fast path already exists (`visible-width` `:492-542`, `printable-ascii-run-end` `:483-490`). Worst case ~40 comparisons per non-ASCII char, on the per-char per-wrapped-line per-frame hot path. There is also a correctness dimension: the hand-written ranges have no generator and no provenance comment, so tracking new Unicode versions is manual (contrast the in-repo precedent of a precomputed width dataset, `src/cadr-tui/mermaid/width-data.lisp`).

Actionable: generate a sorted interval vector from pinned-version `EastAsianWidth.txt` + derived combining-mark data, binary search (~6 comparisons worst case), keep the ASCII fast path. Before swapping, run an equivalence property test over all codepoints `0..#x10FFFF` against the current predicates — this is exactly the policy's "land baseline-locking equal-strength assertions before diverging". Maps to Part K (Lisp-ification checklist candidate) and protects the Part O frame budget. Generator script placement [needs adjudication].

## 5. Terminal renderer — damage-tracked writes, but O(transcript) frame builds

**Damage tracking / minimal update.** The write side is already correct: `render-main-frame` diffs against `previous-lines`, computes `changed-line-range` (`src/cadr-tui/renderer/main-screen.lisp:235-251`), rewrites only that range inside synchronized output `?2026` (`:479-480`, `:532-563`, `:587-588`), and emits only cursor moves on idle frames (`:351-361`); full repaints happen only on invalidate/resize/shrink (`:309-325`, `:438-443`). Frame allocation has 23.3× headroom (0.72 MB vs 16 MiB ceiling; `docs/development-policy.md:138`, `docs/performance.md:200`), so nothing is on fire.

The complexity concern the brief raised is real but located elsewhere: the *input* to the diff is the whole transcript, rebuilt and re-scanned every frame.

- Flatten: `render-tui-entries` loops over all entries and `append`s their line lists per frame (`src/cadr-cli/interactive/transcript.lisp:1062-1087`, called from `src/cadr-cli/interactive/frame.lisp:52-238`); per-entry markdown caches exist (`src/cadr-cli/interactive/transcript.lisp:1009-1060`) but the walk + concatenation is O(entries + total lines).
- Diff: `changed-line-range` is O(total document lines) of `string=` per frame (`src/cadr-tui/renderer/main-screen.lisp:235-251`).
- Store: `main-renderer-store-frame` does a `copy-list` plus a per-line Kitty-escape `search` (`src/cadr-tui/renderer/main-screen.lisp:156-169`, `:41-45`), with the 2-char pattern re-allocated via `format` per line (`:29-32`).
- Alt-screen: `(nth row current)` per visible row (`src/cadr-tui/renderer/alt-screen.lisp:361-374`).
- The tradeoff is known in-tree (`src/cadr-tui/renderer/main-screen.lisp:3-8` comment). Frame entry is `render-now` (`src/cadr-cli/interactive/controller.lisp:475-509`) → `render-frame` (`src/cadr-tui/renderer/alt-screen.lisp:409-424`), rate-capped at ~60 fps with a coalescing coordinator (`src/cadr-cli/interactive/status.lisp:157-158`, `:165-252`).

During agent streaming, per-frame cost therefore grows with conversation length — precisely the time-dimension defect class that goal20's static checkpoints keep missing (P0-4 lesson).

Actionable: cache the flattened line list with per-entry invalidation (snapshots already carry width/theme keys); hoist the Kitty pattern to a constant; replace the alt-screen `nth` walk with pointer iteration. Add a paired "scroll/render a 10k-entry transcript" benchmark to Part O to lock the complexity [needs adjudication — new ledger row].

## 6. Editor buffer — flat string; gap buffer vs piece table is the wrong question yet

**Gap buffer — Finseth, "The Craft of Text Editing" (1991); piece table — Crowley, "Data Structures for Text Sequences" (1998).** Gap buffers make edits at the point O(1) with one contiguous move; piece tables make inserts O(1) without moving text and give cheap snapshots, at the cost of indirection. Both target large documents edited for hours — not a KB-scale prompt editor.

Current state:

- Storage: a single flat string plus integer point (`src/cadr-tui/editor.lisp:19-22`); no gap, no line array, no piece table.
- Mutation: whole-string rebuild via `concatenate` (`editor-replace-range` `:380-392`; insert `:394-399`, delete `:478-484`, kill/yank `:680-702`, `:759-775`).
- Undo: unbounded full-text snapshots (`:156-159`; `src/cadr-tui/undo-stack.lisp:7-10`, `copy-tree` per keystroke, no depth cap) — one typed character costs at least two full buffer copies.
- Line ops: newline scans (`:113-146`); `split-editor-lines` allocates a fresh line list per call (`:97-106`); `render-editor` re-splits the whole text per frame (`:1816`) before slicing the visible window (`:1913-1920`).
- Paste markers: whole-text `search` per entry on every delete (`:309-329`, invoked via `:331-340`).
- True quadratics: word-wrap does `(nth (1+ index) segments)` in a loop (`:1596` — O(k²) for one long line), and cursor motion re-clusters the whole buffer (`:361-378` → `grapheme-clusters`, `src/cadr-tui/unicode.lisp:256-293`).

Actionable: build the edit microbenchmark first (typing/paste at 1 KB / 64 KB / 1 MB; wrap of a 100 KB single line) — Part O microbench, no gate change. Regardless of its outcome, three cheap wins: kill the `nth`-in-loop wrap (vector or single list walk), cap undo depth, and cache cluster boundaries with edit invalidation. Adopt a gap buffer only if the microbenchmark shows real latency at 64 KB+; a piece table is speculative generality here.

## 7. Selectors and completion — the scorer is fine; the rescans are not

**fzf-style subsequence scoring.** The matcher already implements the right scoring (subsequence with gap/consecutive/boundary penalties, `src/cadr-tui/fuzzy.lisp:9-49`); at cadr's candidate counts (hundreds of models, thousands of sessions) no trie or prefix index is warranted. The defects are repeated work per keystroke — and per frame:

- `string-downcase` of query *and* every candidate text per filter call (`src/cadr-tui/fuzzy.lisp:10-11`); normalized forms should be cached per item. The matcher is duplicated CLI-side (`selector-fuzzy-filter`, `src/cadr-cli/interactive/selectors/common.lisp:207-234`) — fix both copies or converge them.
- Model selector re-filters the full list on every render frame, not just on query change (`src/cadr-cli/interactive/selectors/models.lisp:96-105`, via `:313-325`; also `:107-118`).
- Session selector rebuilds each record's haystack per keystroke: `format` + `cl-ppcre:regex-replace-all` + `string-downcase` over `all-messages-text`, which is the concatenation of all user+assistant message texts (`src/cadr-cli/interactive/selectors/sessions.lisp:27-43`, built at `:347-390`, esp. `:388-389`; filter loop `:81-126`); `re:` mode re-creates the regex scanner per record (`:52-55`).
- Tree selector rebuilds per entry per keystroke (`src/cadr-cli/interactive/selectors/tree.lisp:265-294`, `:365-428`) and rebuilds parent/children maps on each filter (`:316-363`).
- Candidate volume for sessions is unbounded: `list-sessions` globs `*.jsonl` in the session dir (`src/cadr-agent/session/discovery.lisp:80-131`) with header-only reads (`:28-78`).
- The exception proves the pattern: the settings selector caches its filtered list and refilters only on query change (`src/cadr-cli/interactive/selectors/settings.lisp:103-113`).
- File completion spawns `fd` per request with a 1/50 s debounce (`src/cadr-tui/autocomplete.lisp:291-328`, `src/cadr-tui/editor.lisp:56`) — process spawn is the latency floor; acceptable, keep.

Actionable: build normalized haystacks once at record creation (invalidate on session/entry change), filter only on query change, downcase once. That is a cache-invalidation change, not a new data structure. Verify with a 10k-synthetic-sessions keystroke-latency benchmark [needs adjudication if added as a ledger row].

## 8. Diff — replay-based line diff beats Myers here; word LCS is guarded O(n·m)

**Myers O(ND) — "An O(ND) Difference Algorithm and Its Variations", Algorithmica 1(1–4):251–266 (1986).** The line-level "diff" in the edit tool never compares file contents at all: it replays the recorded replacement ranges, mapping byte offsets to lines by binary search (`src/cadr-cli/tools/edit.lisp:298`, `:340`), groups hunks within 9 lines (`:428`, `:435-436`), and emits bounded context (`:455`, `:539`). That is O(replacements × log lines + context) — strictly better than recomputing an O(ND) diff, and correct by construction. Keep it; do not "upgrade" to Myers.

The word-level intra-line diff is a naive full-matrix LCS — O(n·m) in time *and* space (`src/cadr-tui/components/tool-block.lisp:165-187`, backtrack `:189-223`) — but only invoked for exactly one-removed/one-added line pairs (`:294-301`) and guarded by `+word-diff-max-matrix-cells+` 65536 with graceful fallback (`:162-163`, `:195-197`, `:245-256`). Given the guard, a full Myers word diff is optional complexity. Two cheap fixes instead: trim common prefix/suffix before the DP (typical edits share both, shrinking the matrix to the changed middle), and replace the per-cluster `concatenate` in `word-diff-tokens` (`src/cadr-tui/components/tool-block.lisp:158`) with chunk accumulation — the same O(k²) pattern as §1, in miniature.

## 9. Allocation discipline — write it into the Part K checklist

**Escape-friendly / `dynamic-extent` idioms (SBCL).** Frame allocation currently sits 23.3× under ceiling (`docs/development-policy.md:138`); the risk is that the remaining Part K Lisp-ification burn-down lands idiomatic-but-allocating code and silently erodes the margin, since the ledger catches only the frame path. Checklist candidates, each grounded in evidence above: chunk accumulation over repeated `concatenate` (§1, §8); stream writes over intermediate strings (§3); hoist loop-invariant allocation (the per-line `format` Kitty pattern, `src/cadr-tui/renderer/main-screen.lisp:29-32`); `declare dynamic-extent` for transient lists/closures; bound copy-based structures (`src/cadr-tui/undo-stack.lisp:7-10`); prefer `nconc`/`vector-push-extend` over `append`/`nth` on growing sequences (`src/cadr-ai/providers/bedrock.lisp:678-681`, `:697`). Writing these into the Part K checklist changes a gate-adjacent artifact [needs adjudication]. Maps to Part K.

## 10. Profiling runbook — make §2's method repeatable

**Standard SBCL tooling: `sb-sprof` / `time` / `room` / `disassemble`.** Policy already names `sb-sprof` as the zero-dependency diagnostic and requires profiles on missed bars (`docs/development-policy.md:271`, `:310`), and the goal20 Part A proposal scopes it as "diagnosis only, not a gate" (`docs/proposals/goal20-part-a-regression-thresholds.md:87`) — but no profiling helper exists in the repo: zero `sb-sprof` references in `scripts/` or `src/`. Every investigation re-derives the incantations. The goal20 Part N acceptance doc already deferred exactly this (`docs/acceptance/goal-v20-part-n.md:14`, "N2.9 sb-sprof — deferred to H"); the runbook is its natural landing spot.

Proposal: `docs/profiling.md` runbook plus one thin driver `scripts/goal20-profile.lisp` (loaded with the same isolated-`HOME`/`ASDF_OUTPUT_TRANSLATIONS` style as `scripts/test-cl.sh`, per `docs/development-policy.md:287`), reusing the paired-path fixtures (`scripts/goal20-paired-paths.lisp`). Standard flows:

- `sb-sprof` statistical profile of a named path (session load, render loop, selector keystroke) — diagnosis, never pass/fail.
- `time` for quick wall/allocation; `(room t)` post-`gc` for space breakdown; `disassemble` on the final hot function to catch boxing/closure allocation.
- Output to a gitignored directory; profiles attach to Part O entries as diagnostics.

Adding a script and doc, and deciding whether profiles become mandatory attachments for ratio changes, is a policy/process change [needs adjudication]. Enables §1–§7.

## Section Top 3 (impact × cost)

1. **§1 streaming chunk accumulation** — 12 confirmed O(n²) concatenate sites plus a second O(n²) re-parse per tool-arg delta, on the single hottest interactive path (agent streaming); the fix is CL-idiomatic chunk lists, ~a day of work, verifiable by a scaling assertion in Part O. Highest impact, lowest cost.
2. **§2+§3 profile-driven journal_read/session_load attack** — the largest remaining enforced Part O deficits (5.48×/6.39×); the `make-random-state` episode proves the profiler finds the one line that matters. Cost: days, mostly measurement.
3. **§5+§7 rescan elimination (frame flatten cache, selector haystack cache)** — both are O(work-you-already-did) bugs on the time-dimension path that goal20's gates demonstrably cannot see (five escapes, latest P0-4); both are cache invalidation, not rewrites, and each ships with its own complexity-locking benchmark.
