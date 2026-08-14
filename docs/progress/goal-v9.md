# GOAL v9: baseline upgrade, experience alignment, and productization wrap-up

## 0. Preconditions and positioning

- May begin **only after the goal 8 corrective acceptance passes**.
- **This goal does not accept any scope reduction.** The user has been explicit: cadr is the complete pi, not a crippled version. Where a part carries a large workload, the method is to split it into more Parts and advance them in order, not to move it out of scope. Any proposal of the form "we will not do X this time" has only one legitimate form: mark it blocked, state the reason, escalate it for user adjudication.
- **The baseline upgrade is the first thing in this goal**: the new baseline is `74caa2649f10ed71b4378ce69f5d9fbfd2466ca5` (`earendil-works/pi`, 2026-07-30). The old baseline `71efc6f0c1909874ec8c944637a9ae7fc0e2d508` serves only as a historical anchor from now on.
- Advance automatically between Parts, without waiting for user instruction; only three classes of situation are blocked: a new third-party dependency, a cryptography path beyond the existing adjudication, and baseline behavior conflicting with a settled adjudication with no prior ruling.

## 1. Part A: baseline upgrade and incremental alignment

### A1. Re-lock the baseline
1. Create a new audit checkout (such as `/tmp/cadr-parity-74caa2649`); the old checkout is kept as a historical comparison.
2. Baseline references throughout the repository's documentation are updated uniformly to the new hash, and the old hash is explicitly marked as a historical anchor.
3. **Regenerate every payload cross-implementation comparison fixture** (`export-ts-payloads` with the new checkout as `--reference`); compare old against new fixture by fixture and list the differences in the report — a difference is an upstream behavior change, and each one must correspond to an implementation change or be confirmed to have no effect.

### A2. Incremental audit
1. Go through `git diff 71efc6f0..74caa2649` in full and produce the incremental list: added/modified/deleted behavioral surfaces, added test files (352 → 363), added packages.
2. The parity-map is rebuilt on the new baseline: added test files are entered as `M`; existing `C` entries affected by upstream changes must be re-verified and must not be carried over just because "it was C before".
3. Known key increments (the list is incomplete; the actual diff governs):
   - **the new package `packages/protocol`** (remote session wire protocol) — completely missing in cadr;
   - `feat(agent)`: the harness shutdown lifecycle, unification of harness task tracking, correction of the waitForIdle semantics;
   - `feat(tui)`: alternate-screen renderer; `fix(tui)`: grapheme width aligned with terminal cells (#6987);
   - the Markdown API rework (#7231);
   - the comparative eval harness and the series of eval changes that followed it;
   - `packages/ai`: Bedrock structured error metadata, streams with no finish reason, GPT-5.6 pricing, the OpenCode Go naming.

### A3. Fill in the gaps
Implement the incremental list item by item, until all 363 test files of the new baseline are `C` or `N/A` by user adjudication. New packages and new features are treated exactly the same, and are not downgraded for having "newly appeared".

## 1.5. Part A2: converting goal 8's manual acceptance items to automation

Of goal 8's 12 real-terminal manual acceptance items, item 9 (security posture) has been verified by the advisor as consistent with the baseline mechanism; the three items image, tools, and server have been verified on the advisor's behalf by automation. **The remaining eight are converted in this Part into deterministic automated tests and enter the suite as permanent protection against regression**; the purely perceptual judgements among them that cannot be automated are folded into Part B's A/B checklist.

**The mechanism must be consistent with the baseline**: the baseline pi's end-to-end behavioral verification uses a **faux provider** (`packages/agent/test/e2e.test.ts` covers the prompt/tool/abort/context/thinking/continue loop) and does not hit a real API. cadr already has a faux provider. **Driving these deterministic tests with a real LLM is forbidden** — jitter in an external service makes the results irreproducible (the advisor's real run on 2026-07-31 failed precisely because of DeepSeek "Service is too busy" and the nondeterminism inherent in live driving).

| goal 8 manual item | Automation method | Must cover |
|---|---|---|
| session | faux provider | create, name, switch, branch, compact, export, `--continue`, `--resume`; **the two branches do not bleed into each other (assert both forwards and backwards)** |
| modes | process level + faux provider | `--print` gives only the final text with no noise; `--mode json` every line is valid JSON and the event sequence is correct; `--mode rpc` request/response/event round trip |
| extensions | faux provider | loading, commands, tool, hook, `/reload`; legacy extension compatibility; custom UI/renderer; the old generation is correctly stale after reload |
| startup and exit | PTY harness | normal exit, Ctrl-C, and after suspend/resume termios, cursor, echo, and bracketed paste are all restored |
| input editing | PTY + virtual terminal snapshot | multi-line, CJK, emoji, wide-character wrapping, word-wise movement, history, kill/yank/yank-pop, undo |
| completion | PTY + snapshot | slash, path, `@`; keyboard selection, cancel, undo after applying |
| Overlay | PTY + snapshot | each selector, dual-overlay focus, CJK borders, narrow/wide resize |
| rendering (the structural part) | faux provider + snapshot | streaming text/thinking/tool, each Markdown element, collapse and expand, status-bar fields |

**Additional requirement**: the usage of `--fork` (whether it accepts an entry id or a session id, and what the format is) is made explicit in the tests and the README; the advisor misused it in a real run for this reason (`Session not found: <entry-id>`) — if the documentation is unclear, add documentation; if the implementation does not match the baseline, correct it to the baseline.

When done, update `docs/acceptance/goal-v8-final.md`: these eight items change from "awaiting manual user confirmation" to "covered by automation", with the corresponding test names noted.

## 2. Part B: visual and interaction experience alignment

**Goal: cadr's TUI is consistent with the baseline pi in visual and interaction feel, not merely consistent in behavioral semantics.** This was the ledger's vacuum until now — the 352 tests assert characters and structure, and never assert color scheme, spacing, or rhythm.

### B1. Establish a runnable comparison environment
Install the dependencies inside the new audit checkout and get the baseline pi's interactive TUI running, as the sole reference (comparing against a non-baseline version is forbidden). The startup procedure is written into the report so the user can A/B it themselves at any time.

### B2. Mechanical alignment (the verifiable part)
Extract item by item from the baseline and compare against cadr, producing the difference table `docs/visual-parity.md`:
1. Theme and palette: all color values of the default theme, semantic colors (user/assistant/thinking/tool/error/status), truecolor and the 256-color degradation strategy;
2. Layout and spacing: padding/margin of each region, indentation levels, the separator and border character set, width-adaptive breakpoints;
3. Element styling: each Markdown element (heading/list/quote/code block/table/link), the expanded and collapsed forms of the tool block, status-bar field order and format, selector highlighting and scroll indication, autocomplete popup styling;
4. Animation parameters: the streaming repaint rhythm, cursor behavior, the form and frequency of the loading indicator.
Every item is labeled "一致 / 不一致（已改齐）/ 有意差异 (with the reason attached and registered in the README)".

### B3. Dynamic alignment (the user-confirmed part)
Produce a per-scenario A/B checklist for the user to compare side by side in two terminals: cold start, streaming answer, long-output scrolling, tool call and expansion, each overlay selector, mixed CJK and emoji, narrow/wide resize, error display, exit. Item-by-item user confirmation is this Part's acceptance gate. **This is the only step in the whole project that still requires human eyes** — Part A2 has already converted every manual item at the behavioral level to automation, and only the perceptual judgement is made here.

### B4. Known items to fix
- **The footer display lags**: after a successful login or model switch, the footer still shows the model from startup time (recorded during the goal 8 correction, not fixed out of scope). This is a state-presentation problem; fix it in this Part and add a regression test.

### B5. Definition of done
The `docs/visual-parity.md` difference table is driven to zero item by item or recorded as an approved 有意差异 + item-by-item user confirmation of the A/B checklist. **The criterion is not "it looks comfortable", the criterion is item-by-item comparison.**

## 3. Part C: changing the client identity to cadr

1. The `originator` sent to OpenAI changes from `pi` to `cadr` (`src/cadr-ai/oauth.lisp:264`, `src/cadr-ai/providers/openai.lisp:260`, and every site of the same origin).
2. Nature: it declares the client identity to a third party and is not a protocol behavior requirement; keeping `pi` would attribute cadr's traffic and errors to the upstream author. **A user-approved intentional deviation from the baseline.**
3. Affected cross-implementation comparison fixtures are updated to the new value and **explicitly marked as an approved difference** in the tests and the parity-map; changing the fixture silently is forbidden.
4. **Hard real-run gate**: after the change, authorization must be completed through a real `/login openai` and one real conversation must be completed. If it is rejected by originator validation, become blocked immediately and report; **reverting to `pi` on your own initiative is forbidden**.
5. Register it in the README difference list.

## 4. Part D: local verification entry point

1. A single entry point `./scripts/verify.sh`: full tests → isolated builds (cadr and cadr-server) → all the smokes that were retained.
2. Credential gating is isomorphic to the baseline: if DeepSeek/Codex OAuth is present, run the corresponding live parts; if not, skip and print the reason; failing because of missing credentials, or faking a pass, is forbidden.
3. Output a summary at the end that can be read at a glance; the exit code strictly reflects the result.
4. **Do not create GitHub Actions or any remote CI configuration** (the user requires getting it running locally first).

## 5. Part E: version, changelog, and repository hygiene

1. `CHANGELOG.md`: Keep a Changelog style, backfilling the milestones from v1 until now at goal-level granularity, including this baseline upgrade.
2. A single source for the version number, with `cadr --version` and `cadr-server --version` agreeing; the report gives a suggested version number and its grounds, **the user decides the actual tagging**.
3. Clean up the untracked build residue of the TypeScript era under `packages/` (list it before deleting, and delete only untracked content confirmed to be a build product).
4. `goal*.md` drafts are filed by convention; `.gitignore` is completed, reducing the reliance on `.git/info/exclude`.
5. Index `docs/`: state the responsibility of each document (architecture / parity-map / visual-parity / test-matrix / dependency-audit / open-questions / progress / proposals / acceptance), so that later maintainers and agents can navigate it.

## 6. Acceptance criteria

1. Part A: all 363 test files of the new baseline are `C` or `N/A` by adjudication; every difference from the fixture regeneration is accounted for; `packages/protocol` is implemented.
1.5. Part A2: all eight of goal 8's manual acceptance items have corresponding automated tests and are all green; all are driven by a faux provider or a PTY, none depends on a real LLM; `goal-v8-final.md` has been updated accordingly.
2. Part B: the `docs/visual-parity.md` difference table is driven to zero or every entry is recorded as an approved difference; the user's A/B checklist is confirmed item by item.
3. Part C: `originator=cadr` is verified in a real `/login` and a real conversation.
4. Part D: `verify.sh` behaves correctly under both conditions, with and without credentials.
5. Part E: CHANGELOG, single version source, cleanup list, and documentation index are all in place.
6. The full test set only grows, never shrinks, and is all green; each Part is committed to the ledger separately and has its own report section (including tokens and elapsed time).

## 7. Principles

- Tests first; the freeze discipline and object ID comparison run through the whole thing; credential discipline is unchanged.
- **Done = committed to the ledger**; a declaration of completion that is not committed is invalid.
- A new third-party dependency must go blocked for pre-review and wait for authorization; acting first and reporting afterwards counts as a violation.
- **A smoke/verification script must not obtain a pass by normalizing, by rewriting the input, or by weakening assertions** (the lesson of the goal 8 correction).
- Creating the remote repository requires the user's account and is not in this goal's scope; the report may give the suggested commands.
- Pause when done and wait for user acceptance.
