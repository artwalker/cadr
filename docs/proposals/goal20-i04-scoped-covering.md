# Proposal: Goal 20 — scope I04 covering to approved identity pairs

Status: **accepted** (advisor, 2026-08-14; subject to user veto). The
scoped-hunk rule and the v1 screen-pair table below are adopted, with the
three corrections in "Adjudication" at the end of this file. No gate
criteria changed in the commit that landed this file; the criteria change
lands with the matcher, in its own commit, per "Enablement".

This is a change of the render-diff obligation unit (development-policy
§5.5). The hole it closes is the P0-1 root cause: 119 stray `m` glyphs
passed the official core gate because I04 was attached.

## Why

`scripts/render-diff.py:3323-3329` admits every visible-text / geometry
diff (`textGeometryEqual` false) as soon as the entry's class set
intersects **any** `textCovering: true` class. I01 is `textCovering:
false` and never participates. I04 is `textCovering: true` and is
attached to a majority of disposition entries because almost every
screen shows a product name.

So I04's actual covering today is "any remaining visible text", not
"the Goal 16 product-identity rename". The human note is the only
scope limit, and notes are not checked against the pixels.

That is the same shape as the goal 17 `login-dialog` incident
(development-policy §5.1): the gate captured two SHAs, I01+I04 closed
them, and the missing chrome was not in either class. `login-dialog`
is `textGeometryEqual: true` on the 2026-08-14 snapshot — the missing
chrome was fixed — but the mechanism that hid it is unchanged.

## Measure (do this before any design argument)

Two populations. Do not mix them.

### Current ledger (`test/fixtures/render-diff/dispositions.json` at HEAD)

| Quantity | N |
|---|---:|
| Disposition entries | 432 |
| Entries that attach I04 | **283 (65.5%)** |
| Expanded I04 keys (entry × listed dimensions) | 425 |
| I04-only entries | 1 |
| I01+I04 and nothing else | 268 |
| I04 plus another text-covering class (I02/I03/I05) | 14 |

I04 covers a majority of exit entries. Development-policy §5.4.3
already requires that proportion to be stated; the gate's strength
equals I04's rigour, and that rigour is currently a boolean.

### Analyze snapshot (2026-08-14 20:23, after P0-1)

Source: `render-diff.py analyze --tier core` written to
`/tmp/p0-analysis6/summary.json` (497 results; log line
`aligned=16 intentional-terminal-protocol=127 requires-disposition=354
adjudicated=481`).

| Quantity | N |
|---|---:|
| Results with I04 attached | 354 |
| Of those, `textGeometryEqual` true (identity already collapsed by `normalized_screen`; remaining SHA diff is ANSI) | 160 |
| Of those, `textGeometryEqual` false (visible text still differs; currently umbrellaeed by I04) | **194** |
| I04 entry-groups (scenario+checkpoint) with any dimension `textGeometryEqual` false | 112 / 217 |
| `textGeometryEqual` false results **without** I04, **within the requires-disposition population** | **0** |

Within the requires-disposition population, every unmatched visible-text
checkpoint in that snapshot is I04-covered. I02/I03/I05 never carry a text
diff on their own.

**The population qualifier is load-bearing** — see Correction 1 in the
adjudication. Counting the whole snapshot instead gives 8, not 0; those 8
are `aligned` (raw byte-identical) and never reach a verdict. Do not quote
the `0` without the qualifier.

Current-ledger I04 keys that are not in the snapshot (settings /
cli-help / local-status sweeps, …) are **unmeasured**. They must be
run through the same matcher before enablement; they are not assumed
green.

## Objection: do not use `docs/product-identity-allowlist.json`

The advisor lean was to match remaining diffs against that file. That
file is the **source-scan** allowlist (`scripts/check-product-identity.py`:
exact path, line, token, occurrence count). It is the wrong instrument
for a TUI screen:

- Most of its 634 findings never appear on a captured screen.
- Its records are source-context lines, not rendered cells.
- Screen identity is already owned by `src/cadr-ai/support/release.lisp`
  plus the identity substitutions in
  `scripts/render-diff.py` `normalize_fixed_values`.

Using it as the I04 matcher would both miss on-screen rename forms the
allowlist does not list (tilde paths, `Run cadr update`, wrapped
changelog URLs) and admit tokens that are not on the screen. The
proposed table is the **screen-pair** table below, closed and derived
from the identity owner, not mined from today's diffs.

## Proposed covering rule

Keep the I04 class. Change what attaching it is allowed to explain.

After the existing `normalized_screen` placeholders:

1. Strip OSC hyperlink wrappers (they are not visible cells; CSI is
   already stripped by `screen_text_and_geometry`).
2. Apply a **closed I04 screen-pair table** (longest match first). Both
   sides of each pair map to the same token. The v1 table is exactly
   the identity substitutions `normalize_fixed_values` does not already
   collapse, taken from `release.lisp` and the documented I04 rules:

   | pi-visible | cadr-visible | Owner |
   |---|---|---|
   | `https://pi.dev/changelog` | `https://github.com/artwalker/cadr/blob/main/CHANGELOG.md` | `cadr-changelog-url` |
   | `https://github.com/earendil-works/pi` | `https://github.com/artwalker/cadr` | `+cadr-canonical-repository-url+` |
   | `https://pi.dev/session/` | `https://cadr.dev/session/` | `+cadr-default-share-viewer-url+` (overlaps I03) |
   | `https://pi.dev` | `https://cadr.dev` | share/docs host |
   | `~/.pi/agent/` | `~/.cadr/agent/` | config dir (tilde form; `<HOME>/…` is already placeholdered) |
   | `.pi/settings.json` | `.cadr/settings.json` | project settings |
   | `PI_` | `CADR_` | env prefix |
   | `pi-debug.log` / `pi-crash-` | `cadr-debug.log` / `cadr-crash-` | log names |
   | word-bounded `pi` / `Pi` | `cadr` / `Cadr` | slug / display name |

3. Fold terminal wrap: after pair application, delete whitespace
   (hard wrap is either a mid-word break or a space replaced by a
   newline; both become the same). Cursor coordinates that shift when
   a wrap adds a row are not text. Missing words and extra glyphs do
   **not** survive this fold.
4. If the folded texts are equal, I04 covers the visible-text diff.
5. If they are not equal, I04 does **not** cover the remainder.
   Another `textCovering` class (I02/I03/I05) may cover it only if that
   class's summary explains the remainder word for word; otherwise the
   gate fails.

I04 remains `textCovering: true` in `dispositions.json` (it does cover
identity text). The boolean OR at `render-diff.py:3323` is replaced by
the matcher above. Attaching I04 without a matcher pass is not covering.

### What is deliberately not I04

These are the loosenings that would re-hide P0-1 and goal 17:

- Viewport-slice alignment (one screen is a shifted window of the
  other). Banner-height from `Cadr` vs `Pi` currently pushes
  `[Extensions]` off cadr's frame and a different changelog slice
  onto `/changelog`. That is a real visible-text difference. It needs
  its own class, a capture that holds the same slice, or a product
  fix. It is not an identity pair.
- Extension entry filenames (`snake.ts` vs a missing block or a
  `.lisp` name). The broken-extension fixture already maps
  `index.ts` / `extension.lisp` to `<ENTRY>`. Games and examples are
  not that fixture. Do not smuggle them into I04.
- Sprite / HUD / help-line rewrites. See invaders below.

### Same rule for I02 / I03 / I05

The boolean OR is the defect class, not I04 uniquely. I02 (1 entry),
I03 (1), I05 (12) are rare and currently always co-attached with I04,
so they have never been the umbrella. The scoped-hunk rule must apply
to every `textCovering` class so the next majority class cannot repeat
this. No new class is proposed here; I05's admitted remainder stays
the login-cancel `Error:` line named in its summary.

Adding a pair to the I04 screen-pair table is changing I04 covering
and needs its own proposal. Mining pairs from today's unmatched diffs
is forbidden — that is how a defect becomes a rename.

## How many existing entries would go red?

On the 2026-08-14 20:23 snapshot, applying the v1 matcher to the 194
I04 + `textGeometryEqual` false keys:

| Bucket | Keys |
|---|---:|
| Residual identity pair (table hits, no wrap) | 2 |
| Identity plus wrap (table + whitespace fold) | 55 |
| Unmatched remainder, but I02/I05 also attached (stay green) | 16 |
| **Would go red** (unmatched, I01+I04 only) | **121 keys / 52 entry-stems / 31 scenarios** |

The 160 I04 keys with `textGeometryEqual` true stay green on the text
check (I04 is not umbrelling a text diff there).

Would-red by scenario (snapshot):

| Keys | Scenario | What the remainder actually is |
|---:|---|---|
| 8 | `example-tic-tac-toe` | pi `[Extensions] tic-tac-toe.ts` absent on cadr; narrow cwd ellipsis |
| 6 each | `example-commands`, `custom-header`, `custom-footer`, `event-bus`, `send-user-message`, `dynamic-tools`, `todo` | same `[Extensions] *.ts` family |
| 5 | `example-snake` | same, plus cadr extra `<PRODUCT> v<VERSION>` banner row |
| 4 each | twelve other `example-*` scenarios | same extensions-block family |
| 4 | `config-selector-state-sweep` | tilde / `.pi` path forms the current placeholders miss; some wrap |
| 2+2 | `update-notifications` (± hyperlinks) | changelog URL wrap + `Run pi update` |
| 1 | `commands-informational/slash-changelog` | viewport slice (`-fullscreen` vs `llscreen`) |
| 1 | **`example-space-invaders/wide/invaders-initial`** | **not identity**: HUD punctuation, alien glyphs (`◄☆►`/`╲▼╱` vs `╱◆╲`), lives wording, help line |
| 1 each | several auth / slash-reload narrow keys | extra/missing banner lines (viewport) |

Invaders is the exhibit that I04 is currently covering a product
difference the class summary cannot explain. The extensions-block
family is the volume. Neither is folded into I04 to shrink the red
count.

Unmeasured current-ledger I04 keys (not in the snapshot) are additional
risk, not assumed covered.

## Enablement, not this commit

Per §5.5: this commit is the proposal only. After adjudication:

1. Land the matcher and two self-tests in `render-diff.py self-test`
   **in their own commit**. Expected: official core analyze goes red
   on the 121 keys. That red is the gate-validity proof.
   - Self-test A: an I04 checkpoint with one extra visible glyph (the
     P0-1 shape) fails even though I04 is attached.
   - Self-test B: an identity-only rename from the v1 table still
     passes.
2. Batch the 121 without loosening the matcher.
   - Batch 1: invaders HUD/sprites/help — product fix or a **new**
     class with a specific summary. Not I04.
   - Batch 2: `[Extensions] *.ts` — product fix (show the lisp
     equivalent), capture change that keeps the block in frame, or a
     new class for example-extension filenames. Not I04.
   - Batch 3: changelog / update-notification URL wrap — add a
     wrap-tolerant form of an **already listed** pair if the bytes
     are the changelog URL; viewport slice stays out of I04.
   - Batch 4: remaining one-offs.
3. Re-analyze any current-ledger I04 key the snapshot missed before
   calling the tree green under the new rule.

Do not enable the matcher and declare the tree green in the same
commit.

## Self-check

1. **Other instances of this defect.** Yes. The boolean OR at
   `:3323` is the defect; I04 is the class that made it load-bearing.
   I02/I03/I05 share the mechanism. The scoped-hunk rule applies to
   all `textCovering` classes. Source-parity "reason classes" and
   the identity allowlist are different exits and are not this hole.
2. **What catches the same class in three months.** The matcher inside
   `validate_result_adjudications`, plus self-test A (extra glyph on
   an I04 screen must fail). A note that says "identity only" will no
   longer be enough.

Adjudicate: accept the scoped-hunk rule and v1 table / change the
table / reject in favor of a different covering test. Do not accept
"keep the boolean OR and tighten the notes".

## Adjudication (advisor, 2026-08-14; subject to user veto)

**Accepted**: the scoped-hunk rule and the v1 screen-pair table, on the
enablement order written above. Three corrections.

Every ledger figure in this proposal was recounted independently before the
ruling: entries 432, I04 283 (65.5%), expanded I04 keys 425, I04-only 1,
I01+I04-only 268, I04 with another text-covering class 14; and on the
snapshot, results 497, I04 354, of those textGeometryEqual false 194 and
true 160, entry-groups 112/217. All match.

### Correction 1 — "every unmatched visible-text key is I04-covered" is false as written

Measured: **8** results have `textGeometryEqual` false without I04, not 0:
`startup-existing`, `commands-and-exit` and `fatal-crash` at
`process-exit` in both dimensions, plus `example-space-invaders/wide`
`invaders-left` and `invaders-right`.

The substantive conclusion survives, because all 8 are
`automaticDisposition: aligned`, whose criterion is **raw byte equality**
(`render-diff.py:3480`), and aligned keys never enter the disposition path
at all (`:3508` excludes them from `required_keys`). Within the
requires-disposition population, I04 really is the only umbrella.

Reword the claim to name that population. This is not pedantry: the figure
`0` will be quoted later to argue that the other classes need no scoping,
and `0` only holds inside one population.

### Correction 2 — the normalizer is side-asymmetric, and the proposed table sits on top of that

`invaders-left` and `invaders-right` have **raw byte-identical** streams
(`raw.equal` true) yet `screenEqual` false **and** `textGeometryEqual`
false. Byte-identical implementations cannot differ in product behaviour,
so `normalized_screen()` is producing different output from identical input
depending on which side it is told it is normalizing.

Harmless today — those keys are `aligned` and never reach a verdict. But
the proposed screen-pair table is side-dependent by construction, so it
adds a layer on top of an asymmetry that already exists.

**Add self-test C before enabling**: apply the v1 table to a set of
`raw.equal == true` keys and require the folded texts to still be equal. A
and B prove the matcher goes red when it should. C proves it does *not* go
red when it should not. C is the one that matters more here, because a
false red creates pressure to loosen the matcher, and loosening it is
exactly how this hole comes back.

### Correction 3 — step 3 must disclose what deleting all whitespace admits

Folding a hard wrap is legitimate: a wrap either breaks mid-word or turns a
space into a newline, and both collapse the same way. But deleting *all*
whitespace also admits differing indentation, padding, column alignment and
blank-line counts. In a TUI those are not incidental — geometry is exactly
what `docs/presentation-parity.md` records item by item.

The rule stands; the proposal must state what it lets through and why that
is acceptable (for instance: geometry is independently held by the
presentation ledger, so this exit does not need to hold it a second time).
Under development-policy §5, a human-judgement exit must disclose its own
scope, and a newly written exit is not exempt from that.

### Endorsed without change

- Rejecting `docs/product-identity-allowlist.json` as the matcher. It is a
  source-scan allowlist — exact path, line, token, occurrence count — and
  most of its 634 findings never reach a screen. This overturned the
  advisor's own initial lean, with the correct reason.
- Disclosing the red count (121 keys / 52 stems / 31 scenarios) **before**
  asking for approval.
- Pre-committing the three things that must not be folded into I04:
  viewport-slice alignment, example-extension entry filenames, and the
  invaders HUD/sprite/help-line rewrites.
- "Mining pairs from today's unmatched diffs is forbidden — that is how a
  defect becomes a rename." This is the standing rule against deriving an
  assertion from the implementation it is meant to check, correctly applied
  here. Keep the sentence in the file: it is the ready-made counterexample
  for the next person who wants to widen the table.
- Enabling the matcher and declaring the tree green must not be the same
  commit. The 121 reds are the gate-validity proof.
