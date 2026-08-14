# 06 — Algorithm Hotspots Addendum (externally supplied, verified)

Origin: a per-call-site algorithmic review supplied by the user on
2026-08-15 (authored outside this review effort). Every claim was
re-verified line-by-line against HEAD on 2026-08-15. Verdict: **accurate** —
all four main findings and all five "strengths" claims are substantiated.
Deviations found during verification are annotated inline as
*[verified: …]*. Coverage relationship with
[05-algorithms-and-data-structures.md](05-algorithms-and-data-structures.md):
complementary — section 05 covers architecture-level issues; this addendum
covers allocation churn at specific call sites. Only the fuzzy-downcase
finding (§F6) overlaps.

## Confirmed strengths (re-verified)

- Alt-screen incremental reuse by `eq` prefix comparison
  (`src/cadr-tui/renderer/alt-screen.lisp:15`, `:32`); per-entry transcript
  render cache (`render-tui-entry`, `src/cadr-tui/interactive/` —
  `transcript.lisp:1009-1060`, keyed by width/theme/extension-snapshot/
  mermaid-mode). *[verified: the frame-to-frame line diff lives in
  `main-screen.lisp:235` (`changed-line-range`), not alt-screen.]*
- `visible-width` printable-ASCII fast path
  (`src/cadr-tui/unicode.lisp:483-490,492`).
- Session journal O(1) append via tail pointer
  (`src/cadr-agent/session/journal.lisp:255,297-305`), by-id hash index
  (`codec.lisp:47`, `journal.lisp:306-308`), cycle-checked path walkback
  (`journal.lisp:553-577`).
- `edit-line-index-at-offset` binary search
  (`src/cadr-cli/tools/edit.lisp:298-311`).
- JSON parser: linear recursive descent with a 256-deep nesting cap
  (`src/cadr-ai/json.lisp:12,337-347`).
- Token estimation: real usage data preferred, linear trailing estimate
  (`src/cadr-ai/support/token-estimation.lisp:76-119`).

## F1. truncate UTF-8 length via full encode — confirmed, medium

`harness-utf8-length` (`src/cadr-agent/truncate.lisp:64-65`) is
`(length (cadr-ai::utf8-octets text))` — a full UTF-8 encode plus octet-vector
allocation per call. `truncate-harness-head/tail` encode the content ~3× in
total (`:106`, `:134`, `:153`). `utf8-tail-bytes` (`:157`) walks backwards
per character, encoding a 1-char string each time (`:166-167`) — a 50KB
single line costs ~100k small allocations.

Fix: accumulate by `char-code` range (1/2/3/4 bytes), O(n) and zero
allocation. *[verified caveat: "behavior-identical" is not exact —
`sb-ext:string-to-octets` **signals** on surrogate code points
(#xD800–#xDFFF) while the range formula would silently return 3. Decoded
text never contains surrogates, so the change is equivalent in practice;
but note `src/cadr-agent/compaction.lisp:166-170` deliberately constructs
surrogate characters, so the class exists in-tree. Ship with a test.]*

## F2. slice-with-width pending-ansi accumulation — confirmed, medium

`src/cadr-tui/unicode.lisp:592-594`: every ANSI code before `start-column`
is accumulated via `(concatenate 'string pending-ansi code)` — O(k²) in the
number of escape sequences; syntax-highlighted lines carry many. Also
`slice-with-width` uses the allocating `grapheme-clusters` (per-cluster
`subseq`, `:600-602`, `:264`) while the non-allocating `grapheme-span-width`
(`:346-416`) already exists in the same file and is what `visible-width`
uses. Fix: collect into a list, join once; iterate spans instead of
clusters. *[verified scope correction: the accumulation only runs when
`start-column > 0`, i.e. horizontal clipping; alt-screen clips only
overwide lines and main-screen re-slices only changed lines
(`main-screen.lisp:10-16`) — "every frame, every line" overstates the
trigger, but streaming code blocks hit it constantly.]*

## F3. compaction-cut-point nth walk — confirmed, low-medium

`src/cadr-agent/compaction.lisp:125-142`: `(nth index entries)` in a
`downfrom` loop over a list — O(n·k), worst O(n²). `reverse` + forward
walk is strictly linear and semantically identical (map indices back via
`(- (1- n) rev-index)`). Zero-risk change.

## F4. parse-resource-frontmatter nth loops — confirmed, low

`src/cadr-agent/resources.lisp:81-82`, `:116-119`, `:128-129`: per-line
`(nth index lines)`, O(n²) over frontmatter lines. Frontmatter is tens of
lines, so no practical impact; same bad habit class as F3. Fix with
`dolist` when touching the file anyway.

## F5. Small-n accumulate-in-loop — confirmed with one correction

- `src/cadr-ai/capabilities/grammar-tools.lisp:14,41` — `append` inside
  `dolist`; confirmed.
- `src/cadr-tui/composition/settings-list.lisp:249,263,269-276` —
  confirmed (the third site is per-description-line).
- `src/cadr-cli/packages/config-selector.lisp:891,1103` — *[verified:
  **not** loop-internal; one `append` per toggle action, O(n) per user
  keystroke at worst. Leave it.]*
- `src/cadr-tui/mermaid/parse.lisp:111-126` — per-character `concatenate`
  **and** per-character `(nth i chars)` over a list: a double quadratic;
  confirmed (worst of this group).
- `src/cadr-tui/mermaid/labels.lisp:296,318,332` per-character, `:302`
  per-word — confirmed; graphs are small, acceptable, but
  `with-output-to-string` is the idiomatic shape.

## F6. fuzzy-match-core repeated downcase — confirmed; already in section 05

`src/cadr-tui/fuzzy.lisp:10-11` downcases query and text per call;
`fuzzy-filter` (`:100-111`) calls it per item per token, so the query is
downcased items×tokens times (twice more on the swapped-alphanumeric retry
path, `:76-81`). Section 05 §7 covers this plus two further findings the
addendum's source missed: the duplicated CLI-side matcher
(`src/cadr-cli/interactive/selectors/common.lisp:207-234`) and the session
selector rebuilding each record's full-message haystack per keystroke
(`src/cadr-cli/interactive/selectors/sessions.lisp:27-43,81-126,347-390`).

## F7. glob-files double relative path — confirmed, minor

`src/cadr-cli/tools/glob.lisp:173-178`: every scanned file gets
`relative-posix-path file base` for matching (`:176`); matched files get a
second `relative-posix-path file cwd` at collect time (`:178`). Pure waste,
negligible magnitude.

## F8. edit all-occurrences — "keep as-is" is defensible, not forced

`src/cadr-cli/tools/edit.lisp:71-76`: `search` + advance-by-one collecting
all positions, worst O(k·n·m). *[verified nuance: uniqueness checking only
needs the second occurrence, but the count is **user-visible** in the
duplicate-error message ("Found ~D occurrences", `:191,194` via
`:214-216`), so early exit would change user-visible text — keeping it is
the correct parity call. A count cap (stop at N, print "N+") would
preserve semantics with bounded cost; optional, low value.]*

## Not in the source analysis

- Alt-screen frame diff itself walks `(nth row current)` per visible row —
  O(rows²) per frame (`src/cadr-tui/renderer/alt-screen.lisp:361-374`).
  Covered in section 05 §5.
- Per-delta full re-parse of accumulated partial JSON on tool-argument
  deltas (anthropic/openai/bedrock) — Θ(n·d) twice over. Section 05 §1.

## Suggested landing order (from the source, endorsed)

1. F1 (truncate UTF-8 length) — every tool call pays it; most certain win.
2. F2 (slice-with-width) — streaming hot path.
3. F3/F4 — zero-risk cleanups.
4. F5 (mermaid parse first), F6, F7 — opportunistic.

Per policy, each change needs before/after measurement (e.g. `(time …)`
loops) and `./scripts/test-cl.sh`; F1/F2 belong in the Part O paired-path
set so the pi baseline comparison is recorded. [needs adjudication for any
new ledger rows]
