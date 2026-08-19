# Changelog

All notable changes to Cadr are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project has not
yet cut a Cadr release tag. The `0.2.0` entry is frozen for the user-approved
tag/Release step.

## [Unreleased]

### Added

- Goal 20 Part P: `utf8-string` copies ASCII runs into a
  pre-sized `simple-base-string` via `copy-unescaped-json-octets`
  (ub32 schar). Mixed buffers pre-size a character string and
  decode only non-ASCII scalars. this-host ~5512→3103 µs.
  Identity 126691→126856. Not FFI. Not intern. sprof:
  `docs/benchmarks/goal20-part-p-tool-read-sprof-utf8-ascii-run.md`.
  G.17 still `missing`.
- Goal 20 Part P: grep `text-lines` / `ripgrep-file-lines`
  use the shared fixnum line-start table (drop trailing
  empty, trim CR). Not `uiop:split-string` on the hot path.
  this-host pairing fixture ~20939 µs. Identity
  126666→126691. Not intern. Not FFI. G.17 still
  `missing`.
- Goal 20 Part P: this-host sb-sprof of `tool_read.text_file`
  on `ab4a52ea4`. Leftover is `octets-to-string`
  (`UTF8->STRING-AREF` 58.3% total). Line-table
  `vector-push-extend` is gone. Capture:
  `docs/benchmarks/goal20-part-p-tool-read-sprof-ab4a52ea4.md`.
  G.17 still `missing`.
- Goal 20 Part H: Friend-MachineD remesure of `ab4a52ea4`
  `tool_read.text_file` 2.39×→2.42× (10299→11131 µs). Same
  ratio band; pi also slower. Ceiling 8.0 unchanged. No
  `src/`. G.17 still `missing`.
- Goal 20 Part P: `split-line-starts` exact-sizes the fixnum
  vector (count newlines, then fill). Kills
  `vector-push-extend` named by sprof at `39b3707bf`. Same
  JS split encoding. this-host ~6505→5512 µs. Identity
  126659→126666. Not intern. Not FFI. G.17 still
  `missing`.
- Goal 20 Part P: this-host sb-sprof of `tool_read.text_file`
  on `39b3707bf`. Leftover is `octets-to-string`
  (`UTF8->STRING-AREF` 17.3%) plus
  `PREPARE-VECTOR-PUSH-EXTEND` on `split-line-starts` (12.7%).
  Capture: `docs/benchmarks/goal20-part-p-tool-read-sprof-39b3707bf.md`.
  G.17 still `missing`.
- Goal 20 Part H: Friend-MachineD remesure of `39b3707bf`
  `tool_read.text_file` 2.88×→2.39× (12786→10299 µs).
  Ceiling 8.0 unchanged. No `src/`. G.17 still `missing`.
- Goal 20 Part P: `read-tool-file` reads `(unsigned-byte 8)`
  then `utf8-string` once, matching pi `readFile` +
  `toString("utf-8")`. this-host ~9763→6505 µs. Identity
  126643→126659. Not mmap. Not FFI. G.17 still `missing`.
- Goal 20 Part H: `tool_grep.context_file` pair. Same 4000-line
  fixture; timed work is production `grep-lines` vs pi
  `createGrepToolDefinition.execute` with `context=2`. First
  Friend-MachineD freeze 1.77× (28357 / 16053 µs), ceiling
  3.0. No product optimize. G.17 still `missing`.
- Goal 20 Part P: this-host sb-sprof of `tool_read.text_file`
  on `c2828e831`. Leftover is SBCL `INPUT-CHAR/UTF-8/LF` on
  `read-file-string` (47.3% self), not the line table (2.0%).
  Capture: `docs/benchmarks/goal20-part-p-tool-read-sprof-c2828e831.md`.
  G.17 still `missing`.
- Goal 20 Part H: Friend-MachineD remesure of `c2828e831`
  `tool_read.text_file` 5.32×→2.88× (21747→12786 µs).
  Ceiling 8.0 unchanged. No `src/`. G.17 still `missing`.
- Goal 20 Part P: `read-tool-file` fills a fixnum line-start
  table then one `subseq` for the selected range. Matches JS
  `split("\n")` / `slice` / `join`. Not `uiop:split-string`
  on the hot path. this-host ~21747→9763 µs. Identity
  126591→126643. Not intern. Not FFI. G.17 still `missing`.
- Goal 20 Part H: `tool_read.text_file` pair. Same 4000-line
  fixture ingested as a text file; timed work is production
  `read-tool-file` vs pi `createReadToolDefinition.execute`.
  First Friend-MachineD freeze 5.32× (21747 / 4087 µs),
  ceiling 8.0. No product optimize. G.17 still `missing`.
- Goal 20 Part P: `truncate-harness-tail` pre-sizes the
  fixnum line table (hint cap 8192) so 4000 lines do not
  realloc from 64. Same algorithm. this-host ~749→635 µs.
  Identity 126589→126591. Not intern. Not FFI. G.17 still
  `missing`.
- Goal 20 Part P: CLI `utf8-length` delegates to
  `harness-utf8-length`. Does not encode the whole string
  to count. this-host pairing fixture ~1111→477 µs.
  Identity 126583→126589. Not intern. Not FFI. G.17 still
  `missing`.
- Goal 20 Part P: `truncate-harness-tail` builds a fixnum
  line-start/width table in one walk, then indexes from the
  end like pi `truncateTail`. Not `uiop:split-string`. Not
  FFI Buffer. this-host ~819→749 µs. Identity 126546→126583.
  FiveAM 19359→19361. Not intern. G.17 still `missing`.
- Goal 20 Part P: `cli-token-tail=` compares with `schar`
  on `simple-string`. sprof named it 14.2% self on
  `argv_parse`. this-host 3.0→1.96 µs. Identity
  126542→126546. Not intern. Not FFI. G.17 still
  `missing`.
- Goal 20 Part P: `truncate-harness-head` counts remainder
  totals after the selected prefix. Friend-MachineD head
  was 4.27× (2277 µs). this-host 2040→549 µs. Identity
  126512→126542. FiveAM 19357→19359. Not intern. Not FFI.
  G.17 still `missing`.
- Goal 20 Part P: `truncate-harness-tail` counts lines and
  UTF-8 bytes in one walk. Friend-MachineD remesure still
  4.57× / 3.09× (head/tail) before this knife. Not intern.
  Not FFI. G.17 still `missing`.
- Goal 20 Part P: `sqlite-row-to-entry` decodes payload
  TEXT with `parse-session-record-octets` instead of
  `parse-json`. Identity 126497→126502. Not intern. Not
  FFI. G.17 still `missing`.
- Goal 20 Part P: this-host sb-sprof of
  `sqlite_session.open_walk` on `e3eb0d956`. Leftover is
  `PARSE-JSON-SOURCE` on SQLite payload TEXT (49.8% total)
  plus CFFI/Babel string conversion. Capture:
  `docs/benchmarks/goal20-part-p-sqlite-sprof.md`. G.17 still
  `missing`.
- Goal 20 Part H: `sqlite_session.open_walk` pair. Same
  `session.jsonl` ingested into cadr SQLite and pi
  `sqlite-node`; timed work is open + read-all + leaf walk.
  First Friend-MachineD non-quick freeze. No product optimize
  in this commit. G.17 still `missing`.
- Goal 20 Part P.13: after a pair lands, keep refining.
  Beating pi is not a stop. Floor = not slower than pi;
  ceiling = CL leftover. Empty SWAR is not refining.
  Ruling: `docs/adjudications.md` 2026-08-19 19:21. G.17
  still `missing`.

- Goal 20 Part P.13 inventory: every `src/**/*.lisp` is
  `paired`, `unpairable`, `covered-as-callee`, or
  `needs-pair`. 219 files still need an H pair (SQLite,
  tool loop, compact, remaining providers, settings /
  package / skill / prompt, and the rest). H JSON schema
  unchanged. No new pairs. No `src/`. G.17 still
  `missing`.
- Goal 20 Part P.13: every pairable path must be measured,
  then optimized. Path unit, not per-file benches.
  `pairable-uncovered` is not a terminal state. Ruling:
  `docs/adjudications.md` 2026-08-19 P.13. G.17 still
  `missing`.

- Goal 20 Part P: this-host sb-sprof of `session_load` and
  `journal_read` on `5cc895b84`. `ALLOC-UNSIGNED-BIGNUM`
  gone. Leftover is walker / `OCTET-U32-LE` / runtime /
  foreign `read`. No unused legal named structure. Capture:
  `docs/benchmarks/goal20-part-p-load-read-sprof-5cc895b84.md`.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: this-host sb-sprof of `session_load` and
  `journal_read` on `2a3aa47ba`. Leftover is walker / SWAR
  helpers / runtime / foreign `read`. `COPY-UNESCAPED`
  3.1%→2.4% self. No unused legal named structure. Capture:
  `docs/benchmarks/goal20-part-p-load-read-sprof-2a3aa47ba.md`.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: this-host sb-sprof of `context_walk`,
  `argv_parse`, and `help_render`. Walk leftover is EQUAL
  hash in `session-path-entries`. argv is `assoc`/`string=`.
  help is `format` (not guessed). Capture:
  `docs/benchmarks/goal20-part-p-walk-argv-help-sprof.md`.
  G.17 still `missing`.

- Goal 20 Part P: this-host sb-sprof of `session_load` and
  `journal_read` on `67a2d43fb`. Leftover is the session
  JSONL octet walker / runtime / foreign `read`. No EQUAL
  hash, no `parse-json-octets` re-entry. Capture:
  `docs/benchmarks/goal20-part-p-load-read-sprof.md`. No
  `src/`. G.17 still `missing`.

### Changed

- Goal 20 Part P: Friend-MachineD remesure of `208838a39`
  (n=5, enforced). truncate_head 1.17× (667 / 570 µs).
  truncate_tail 1.47× (856 / 581 µs). Same ratios as
  `c074a85ec`. Ceiling unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: this-host sb-sprof of truncate line table
  at `c074a85ec`. Tail leftover encoding is
  `PREPARE-VECTOR-PUSH-EXTEND` 7.9% total. Capture:
  `docs/benchmarks/goal20-part-p-truncate-sprof-c074a85ec.md`.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of `c074a85ec`
  (n=5, enforced). truncate_head 0.97×→1.17× (cadr
  618→592 µs). truncate_tail 1.30×→1.47× (819→790 µs).
  Absolute cadr improved; ratio up is pi faster. Ceiling
  unchanged. No `src/`. G.17 still `missing`.

- Goal 20: standing policy section 1 item 6 — speed
  design copies pi's algorithm and data structure, encoded
  in Lisp. Product alignment stays observable behavior.
  sprof of a worse scan is not a design source. Audit:
  `docs/acceptance/goal-v20-ds-audit.md`. G.17 still
  `missing`.

- Goal 20 Part P.13: read pi first. Copy its passes and
  data structure in Lisp; sprof of a worse scan is not the
  design source. truncate_tail leftover is a line-start
  vector, not another character-loop direction. Ruling:
  `docs/adjudications.md` 2026-08-19 22:18 / 22:27. G.17
  still `missing`.

- Goal 20 Part P: revert one-reverse-walk `truncate-harness-tail`.
  Friend-MachineD n=5: tail 1.30×→1.59× (cadr 819→870 µs).
  Full reverse scan lost to forward totals plus short reverse
  select. Identity back to 126546. G.17 still `missing`.

- Goal 20 Part P: this-host sb-sprof of `truncate_tail` at
  `19ca40947`. Leftover is `HARNESS-LINE-AND-UTF8-LENGTH`
  67.5% then reverse `HARNESS-UTF8-LENGTH-RANGE` 13.2%.
  Capture: `docs/benchmarks/goal20-part-p-truncate-tail-sprof-19ca40947.md`.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of `19ca40947`
  (n=5, enforced; booked at `c688da095`). truncate_head
  4.27×→0.97× (cadr 2277→618 µs). truncate_tail
  1.38×→1.30× (763→819 µs). Ceiling unchanged. No `src/`
  in the remesure booking. G.17 still `missing`.

- Goal 20 Part P: this-host sb-sprof of load/read at
  `19ca40947`. Leftover is the octet walker
  (`OCTET-U32-LE` 11%, quote/LF/space SWAR, `SCAN-KEY`)
  plus pthread / foreign `read`. No unused legal named
  structure. No `src/`. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of `17df52451`
  (n=5, enforced). truncate_head 4.57×→4.27× (cadr
  2566→2277 µs). truncate_tail 3.09×→1.38× (1783→763 µs).
  Ceiling unchanged. No `src/` in the remesure booking.
  G.17 still `missing`.

- Goal 20 Part P: `SCAN-KEY` / `PARSE-STRING-VALUE` /
  `skip-string` find `"` and `\\` with two ub32 haszero.
  Backslash falls back to a byte walk of that escape.
  Not intern. Not FFI. Session JSONL bytes unchanged.
  Identity 126439→126497. FiveAM 19338→19346. this-host
  wall did not drop hundreds of µs. G.17 still `missing`.

- Goal 20 Part P: `SWAR-EQ-MSB` is two ub32 haszero
  operations. Result stays a fixnum. Not intern. Not FFI.
  Session JSONL bytes unchanged. Identity 126415→126439.
  FiveAM 19331→19338. G.17 still `missing`.

- Goal 20 Part P: `copy-unescaped-json-octets` writes
  ASCII windows as ub32 `schar` stores. High bytes stay
  UTF-8. Not intern. Not FFI. Session JSONL bytes
  unchanged. Identity 126391→126415. FiveAM
  19320→19331. G.17 still `missing`.

- Goal 20 Part P: `octet-window-equals` compares short
  ASCII keys as ub32 chunks (constant literals fold).
  Not intern. Not FFI. Session JSONL bytes unchanged.
  Identity 126304→126391. FiveAM 19304→19320. Not
  `sb-simd`. G.17 still `missing`.

- Goal 20 Part P: `SCAN-BUFFER` / `SKIP-SPACE` scan 8
  bytes at a time (SWAR haszero after splat). Not FFI.
  Not `sb-simd`. Session JSONL bytes unchanged. Identity
  126223→126304. FiveAM 19291→19304. Not intern. G.17
  still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of `e908ebad9`
  (n=5, enforced). help_render 5.59×→0.07× (cadr 4.7→0.0 µs).
  context_walk 1.05×→0.03× (113.3→3.2 µs). argv 1.69×→1.54×.
  Ceiling unchanged. No `src/` in the remesure booking.

- Goal 20 Part P: `print-cli-usage` writes literal blocks
  with `write-string`. No per-line `format`. Help bytes
  match the previous non-color output. Identity
  126116→126223. FiveAM 19289→19291. Not intern. Not FFI.
  G.17 still `missing`.

- Goal 20 Part P: `parse-cli-arguments` looks up known CLI
  flags in a closed length/octet table. No per-flag
  `assoc` `string=`. Output/behavior aligned. Help
  unchanged. Identity 125935→126116. FiveAM 19275→19289.
  Not intern. Not FFI. G.17 still `missing`.

- Goal 20 Part P: `session-messages` reuses the derived
  message list until append or branch. Pairing
  `context_walk` is that function. Not intern. Not FFI.
  Identity 125921→125935. FiveAM 19267→19275. G.17 still
  `missing`.

- Goal 20 Part P: Friend-MachineD remesure of `8d7917472`
  (n=5, enforced). list_models_render 1.57×→0.06× (cadr
  2088→97 µs). Ceiling unchanged. No `src/` in the remesure
  booking.

- Goal 20 Part P: `model-registry-available-models` caches
  the configured list on the registry. Invalidate with the
  same models.json / auth.json write-dates as the CLI
  registry cache. Callers get a copy so SORT/FILTER cannot
  mutate the cache. this-host list_models_render 2189 µs /
  1,691,418 B → 199 µs / 45,485 B. Table bytes stay the
  baseline. Not intern. Not FFI. Not session. Identity
  125894→125921. FiveAM 19259→19267. G.17 still
  `missing`.

- Goal 20 Part P: session JSONL first line fills
  `session-file-header` from the octet window. Not EQUAL
  hash. this-host load 2387 µs / 920,544 B → 1586 µs /
  920,512 B; journal_read 1591 µs / 862,611 B → 1586 µs /
  862,774 B. Wall is timer alias; no Friend-MachineD
  remesure of this knife. Not intern. Not FFI. Identity
  125811→125894. FiveAM 19250→19259. G.17 still
  `missing`.

- Goal 20 Part P: Friend-MachineD remesure of `98f27fdd8`
  (n=5, enforced). load 1.19×→1.06× (cadr 2007→1905 µs),
  read 1.09×→1.10× (cadr 1898→1627 µs), append 0.81×→0.89×
  (cadr 1698→1624 µs). Ceiling unchanged. No `src/` in the
  remesure booking.

- Goal 20 Part P: session JSONL `PARSE-STRING-VALUE` decodes
  escaped strings from the octet window. It no longer
  `octets-to-string` the quoted span and re-enters
  `parse-json-source`. this-host load-session 1593 µs /
  993,056 B → 2387 µs / 920,544 B; journal_read 1593 µs /
  928,429 B → 1591 µs / 862,611 B. Wall is the 800 µs timer
  alias; bytes dropped. No Friend-MachineD remesure. Not
  intern. Not FFI. Identity 125692→125811. FiveAM
  19240→19250. G.17 still `missing`.

- Goal 20 Part P: `print-cli-models` writes token counts and
  provider names from model slots. No per-model
  `format-list-models-token-count` / `string-downcase` /
  six-cell list. Table bytes stay the baseline. this-host
  2178 µs / 1,717,788 B → 2197 µs / 1,691,678 B. Wall did
  not move hundreds of µs; no Friend-MachineD remesure.
  Not intern. Not FFI. Identity 125610→125692. FiveAM
  19232→19240. G.17 still `missing`.

- Goal 20 Part P: this-host `list_models_render` of
  `9065ffe30` (pairing fixture pattern `goal20`, broadcast
  sink) 2178 µs / 1,717,788 B. Pairing cadr last booked
  2182 µs. Wall did not move hundreds of µs; no
  Friend-MachineD remesure. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: `print-cli-models` writes the six-column
  table into one string buffer. No per-cell `format nil`
  pad and no per-row `format ~{~A~^  ~}`. Table bytes
  stay the baseline. Not intern. Not FFI. G.17 still
  `missing`.

- Goal 20 Part P: remaining session JSONL generic values
  fill scalars / `(:json-object . pairs)` / vectors in the
  octet walker. They no longer re-enter parse-json-octets
  (EQUAL hash). this-host load-session 2361 µs / 992,000 B
  → 1579 µs / 993,056 B; journal_read 2361 µs / 928,557 B
  → 1578 µs / 928,429 B. Wall is the 800 µs timer step;
  no Friend-MachineD remesure. Not intern. Not FFI.
  Identity 125554→125602. FiveAM 19226→19232. G.17 still
  `missing`.

- Goal 20 Part P: journal_append fills a schema-specific
  octet buffer. ASCII keys/numbers are written in place;
  UTF-8 is only used on string payloads. Journal fd is
  `(unsigned-byte 8)`. Session JSONL bytes match
  stringify of session-entry-to-json. this-host
  create+128 append 1314 µs / 163,621 B → 1311 µs /
  185,013 B. Wall did not move hundreds of µs; no
  Friend-MachineD remesure. Not intern. Not FFI.
  Identity 125336→125554. FiveAM 19223→19226. G.17
  still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `1f4322c51` (non-quick, samples=5, enforced).
  journal_append 1.11×→0.81×. cadr append 2800 µs
  → 1698 µs. RATIO_CEILINGS unchanged. No `src/`.
  G.17 still `missing`.

- Goal 20 Part P: journal_append keeps the session
  file open after first persist. Same
  write-session-entry-jsonl bytes. this-host
  create+128 append 2627 µs / 338,139 B → 1314 µs
  / 163,621 B. Not intern. Not FFI. Identity
  125313→125336. FiveAM 19217→19223. G.17 still
  `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `feb2d5450` (non-quick, samples=5, enforced).
  journal_append 1.93×→1.11×. cadr append 3676 µs
  → 2800 µs. load 1.03×→1.01×, read 1.04×→1.18×.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: journal_append emits message
  entries from typed structs. No EQUAL hash then
  stringify. Key order stays string< so JSONL
  bytes match the old path. this-host create+128
  append 4069 µs / 1,273,115 B → 2627 µs /
  338,139 B. Not intern. Not FFI. Identity
  125064→125313. FiveAM 19214→19217. G.17 still
  `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `2155a80e5` (non-quick, samples=5, enforced).
  session_load 1.85×→1.03×, journal_read 1.58×→1.04×.
  cadr load 3026 µs → 2005 µs, read 2659 µs → 1745 µs.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: session JSONL v3 records use a
  schema-specific octet walker. Known keys fill
  session-entry / message / usage / content slots;
  unknown values are skipped; integers and
  `YYYY-MM-DDTHH:MM:SS.sssZ` timestamps are read
  in place. Public parse-json is unchanged.
  Session file bytes unchanged. this-host
  load-session 3243 µs / 1,215,670 B → 1584 µs /
  991,987 B; journal_read 3243 µs / 1,138,106 B →
  1584 µs / 928,557 B. Not intern. Not :size.
  Not FFI. Identity 124280→125064.
  FiveAM 19200→19214. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `d89b76cc9` (non-quick, samples=5, enforced).
  session_load 1.62×→1.85×, journal_read 1.62×→1.58×.
  cadr load 3033 µs → 3026 µs. Ratio up is pi drift
  (1870→1638 µs). RATIO_CEILINGS unchanged. No `src/`.
  G.17 still `missing`.

- Goal 20 Part P: load-session sizes the by-id EQUAL
  table to the record count so GROW-HASH-TABLE does
  not recopy on the pairing fixture. Session file
  bytes unchanged. load-session 1,260,915 B →
  1,215,670 B. Wall unchanged. Not intern. Not 7b.
  Identity 124277→124280. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `857270409` (non-quick, samples=5, enforced).
  session_load 1.74×→1.62×, journal_read 1.72×→1.62×.
  cadr load 3037 µs → 3033 µs, read 2562 µs → 2647 µs.
  Ratio drop is mostly pi drift. RATIO_CEILINGS
  unchanged. No `src/`. G.17 still `missing`.

- Goal 20 Part P: load-session maps closed record types
  and message vocab to keywords without SUBSTITUTE /
  STRING-UPCASE / INTERN. Already-typed content blocks
  skip the EQUAL-hash rewalk. Session file bytes
  unchanged. Pairing fixture load-session 3173 µs →
  2379 µs / 1,346,195 B → 1,260,915 B. journal_read
  unchanged. Not intern expand. Not 7b. Identity
  124236→124277. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `a7013eb1a` (non-quick, samples=5, enforced).
  session_load 2.02×→1.74×, journal_read 1.46×→1.72×.
  cadr load 3127 µs → 3037 µs, read 2589 µs → 2562 µs.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: session ISO-8601 timestamps of the
  form `YYYY-MM-DDTHH:MM:SS.sssZ` parse digits in place.
  No SUBSEQ/CONCATENATE per entry. Pairing fixture
  load-session 3156 µs → 2383 µs / 1,385,181 B →
  1,346,195 B. journal_read unchanged. Not intern.
  Not 7b. Identity 124174→124236. G.17 still
  `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `c78cef0a9` (non-quick, samples=5, enforced).
  session_load 2.52×→2.02×, journal_read 2.17×→1.46×.
  cadr load 3866 µs → 3127 µs, read 3357 µs → 2589 µs.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: session JSONL parse walks the octet
  window. UTF-8 decode only unescaped string values
  with high bytes. Public parse-json unchanged.
  Pairing fixture journal_read 1,571,942 B → 1,138,106 B
  / 3136 µs → 2367 µs; load-session 1,816,608 B →
  1,385,181 B / 3920 µs → 3156 µs. Not intern. Not 7b.
  Identity 123687→124174. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `bc5d70b08` (non-quick, samples=5, enforced).
  session_load 2.15×→2.52×, journal_read 2.22×→2.17×.
  cadr load 3807 µs → 3866 µs, read 3316 µs → 3357 µs.
  Ratio up on load is pi drift (1773→1532 µs).
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: session JSONL is one exact-size octet
  `READ-SEQUENCE` (1MiB cap) then LF split. ASCII lines
  reuse a simple-base-string and parse a START/END window.
  Session file bytes unchanged. Pairing fixture
  journal_read 1,942,410 B → 1,571,942 B; load-session
  2,182,371 B → 1,816,608 B. Wall unchanged. Not intern.
  Not 7b. Identity 123579→123687. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `67cdb71fa` (non-quick, samples=5, enforced).
  session_load 2.48×→2.15×, journal_read 2.41×→2.22×.
  cadr load 4128 µs → 3807 µs, read 3508 µs → 3316 µs.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: tool-call `arguments` decode into
  tagged string-key pairs, not an EQUAL hash.
  `json-get` / stringify treat the tag as an object.
  Session file bytes unchanged. Pairing fixture
  journal_read 1,975,830 B → 1,942,410 B; load-session
  2,214,272 B → 2,182,371 B. Wall unchanged. Not intern.
  Not 7b. Identity 123521→123579. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `b655bbb11` (non-quick, samples=5, enforced).
  session_load 2.37×→2.48×, journal_read 2.00×→2.41×.
  cadr load 4356 µs → 4128 µs, read 3616 µs → 3508 µs.
  Ratio up is pi drift. RATIO_CEILINGS unchanged.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: v3 `content` array elements walk
  into typed text/thinking/image/tool-call. No EQUAL
  hash per block. `arguments` stay hashes. Session
  file bytes unchanged. Pairing fixture journal_read
  2,134,624 B → 1,975,830 B; load-session
  2,399,405 B → 2,214,272 B / 4756 µs → 3943 µs.
  Not intern. Not 7b. Identity 123365→123521. G.17
  still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `eee817672` (non-quick, samples=5, enforced).
  session_load 3.02×→2.37×, journal_read 2.07×→2.00×.
  cadr load 4781 µs → 4356 µs. RATIO_CEILINGS unchanged.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: v3 nested `message` / `usage` /
  `cost` walk into `session-json-message` + typed
  usage/cost. No EQUAL hash for those envelopes.
  Content blocks stay hashes until load. Session file
  bytes unchanged. Pairing fixture journal_read
  2,375,210 B → 2,134,624 B; wall unchanged.
  load-session 2,694,035 B → 2,399,405 B. Not intern.
  Not 7b. Identity 123071→123365. G.17 still
  `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `5161d512f` (non-quick, samples=5, enforced).
  session_load 2.96×→3.02×, journal_read 2.14×→2.07×.
  cadr load 5196 µs → 4781 µs. RATIO_CEILINGS unchanged.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: v3 session JSONL body lines decode
  into `session-entry` (visitor, no top-level EQUAL
  hash). Nested message/usage stay hashes. Header and
  v1/v2 stay hashes for migrate. Session file bytes
  unchanged. Pairing fixture journal_read
  2,463,475 B → 2,375,210 B; wall 3168 µs → 3176 µs.
  parse-json-lines bytes unchanged. Not intern. Not 7b.
  Identity 122900→123071. FiveAM 19150→19164. G.17
  still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `882b49595` (non-quick, samples=5, enforced).
  session_load 2.83×→2.96×, journal_read 2.24×→2.14×.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: PARSE-STRING scan no longer tracks
  ASCII/unicode per character; `base-p` is decided only
  when COPY-UNESCAPED runs. Pairing fixture parse
  2440 µs → 2376 µs; journal_read 4067 µs → 3961 µs;
  bytes unchanged. Not intern. Not 7b. Identity
  122898→122900. FiveAM 19147→19150. G.17 still
  `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `30bd91cf6` (non-quick, samples=5, enforced).
  session_load 2.89×→2.83×, journal_read 2.34×→2.24×.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: object keys that already live in the
  closed JSON value intern set (`thinking`, …) skip
  `COPY-UNESCAPED-JSON-STRING`. No new intern entries.
  Pairing fixture parse 1,235,971 B → 1,229,597 B;
  journal_read 2,477,290 B → 2,463,475 B. Not 7b.
  Identity 122892→122898. FiveAM 19145→19147.
  G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `6cd292ab9` (non-quick, samples=5, enforced).
  session_load 2.66×→2.89×, journal_read 2.22×→2.34×.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: `parse-object` stacks ≤8 pairs, then
  `MAKE-HASH-TABLE :size` count (spill past 8). Pairing
  fixture parse 1,328,669 B → 1,235,971 B; journal_read
  2,559,514 B → 2,477,290 B. Wall unchanged. Not 7b. No
  intern-table expand. Identity 122851→122892. FiveAM
  19070→19145. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `fef648a60` (non-quick, samples=5, enforced).
  session_load 3.32×→2.66×, journal_read 2.23×→2.22×.
  RATIO_CEILINGS unchanged. No `src/`. G.17 still
  `missing`.

- Goal 20 Part P: interned JSON object-key lookup
  dispatches on the first character (same closed set,
  no new keys). Pairing fixture journal_read 4634 µs →
  3096 µs; bytes unchanged (2,559,514). Not 7b. Identity
  122842→122851. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `a882dfe96` (non-quick, samples=5, enforced).
  session_load 2.91×→3.32×, journal_read 2.45×→2.23×,
  journal_append 1.75×→1.38×. RATIO_CEILINGS unchanged.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: `copy-unescaped-json-string` is one
  typed window copy (`REPLACE` into a declared
  `SIMPLE-BASE-STRING`; same-type source uses `SUBSEQ`).
  Pairing fixture parse-json-lines 3200 µs → 2400 µs;
  bytes unchanged (1,328,669). Not 7b. No intern-table
  expand. Identity 122836→122842. FiveAM 19062→19070.
  G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `64c367dfc` (non-quick, samples=5, enforced).
  session_load 3.27×→2.91×, journal_read 3.16×→2.45×,
  journal_append 1.76×→1.75×. RATIO_CEILINGS unchanged.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: intern repeated ASCII JSON *values*
  (`message`, `assistant`, `user`, `text`, …) so they
  skip `COPY-UNESCAPED-JSON-STRING`. Keys unchanged.
  Pairing fixture parse 1,400,749 B → 1,328,669 B;
  journal_read 2,638,423 B → 2,559,514 B. Not 7b.
  Identity 122802→122836. FiveAM 19057→19062.
  G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure of
  `c949668cd` (non-quick, samples=5, enforced).
  session_load 3.80×→3.27×, journal_read 3.38×→3.16×,
  journal_append 1.95×→1.76×, truncate_head 13.86×→3.77×,
  truncate_tail 13.08×→3.00×. RATIO_CEILINGS unchanged.
  No `src/`. G.17 still `missing`.

- Goal 20 Part P: intern session JSONL object keys
  (`parentId`, `timestamp`, `message`, …) so they skip
  `COPY-UNESCAPED-JSON-STRING`. Same-machine pairing
  fixture: parse-json-lines 1,564,496 B → 1,400,749 B;
  journal_read 2,805,066 B → 2,638,423 B / 5596 µs →
  4803 µs. Identity 122785→122802. FiveAM
  19051→19057. Not 7b. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD sprof of
  session_load / journal_read after remesure. Heat is
  PARSE-VALUE / COPY-UNESCAPED / hash / REPLACE (already
  shipped JSON). Not a lever. Not 7b. G.17 still
  `missing`.

- Goal 20 Part P: `truncate-harness-head` / `truncate-harness-tail`
  scan the source string once instead of
  `uiop:split-string` + `format` join. Pairing fixture
  (4000 lines) same-machine 7.276 ms / 2,561,572 B →
  2.319 ms / 197,488 B (head); 7.446 ms / 2,749,241 B →
  1.679 ms / 197,568 B (tail). Observed pairing fields
  unchanged. Identity 122701→122785. FiveAM
  19042→19051. G.17 still `missing`.

- Goal 20 Part P: Friend-MachineD remesure after
  P.1–P.12/P0 (non-quick, samples=5, enforced).
  stream_roundtrip 1.29×→0.67×, list_models_render
  3.18×→1.70×, journal_read 3.93×→3.38×, session_load
  4.28×→3.80×, journal_append 2.21×→1.95×. Truncate
  still 13.86×/13.08×. RATIO_CEILINGS unchanged. No
  `src/`. G.17 still `missing`.

- Goal 20 P.8: user 2026-08-18 18:09 deferred
  three-game hand-play; leftover recorded as pass
  until a new defect is opened. Overlay SHAs
  unchanged. G.17 still `missing`.

- Goal 20 P0: tic-tac-toe `move_*` no longer `sleep`s
  0.3s. `:execution-mode :sequential` kept. FiveAM locks
  20-call median < 50ms and no `sleep` in source.
  FiveAM 19037→19042. G.17 still `missing`.

- Goal 20 P.12: alt-screen `last-document` is a
  simple-vector. Per-row selection uses `AREF`. Isolated
  400-row × 80 walk 0.100 ms (`NTH` list) → 0.000 ms
  (`AREF`). Identity 122685→122701. G.17 still `missing`.

- Goal 20 P.12: mermaid `gm-read-shape` writes the label
  to a stream instead of per-char `concatenate`.
  Same-machine 200× 800-char label 1,342,124 B → 24,717 B
  / call; 0.340 ms → 0.040 ms. Identity 122678→122685.
  G.17 still `missing`.

- Goal 20 P.12: `editor-lines` is a simple-vector.
  Per-line lookup is `AREF`, not list `NTH`. Same-machine
  80× 200-line editor-lines+render 183,349 B → 177,188 B
  / call. 0.300 ms (timer step). Identity 122644→122678.
  FiveAM 19036→19037. G.17 still `missing`.

- Goal 20 P0: FiveAM locks a registered move renderer
  that errors does not dump `Player X played at`.

- Goal 20 P0: tic-tac-toe overlay visual board writes
  each row to a stream instead of repeated `concatenate`.
  Same-machine 80× render 54,372 B → 47,819 B / frame;
  0.150 ms (timer step). `sleep 0.3` kept. No spinner.
  FiveAM 19025→19032. G.17 still `missing`.

- Goal 20 P0: custom-message fallback does not dump
  `:content` when a message renderer is registered.
  Move banners start collapsed.

- Goal 20 P0: tic-tac-toe `board-ascii` matches baseline
  `boardToAscii` (`<>`, 9-wide cells). Expanded move banner
  paints the visual board snapshot, not the LLM ascii.
  FiveAM 19008→19025. G.17 still `missing`.

- Goal 20 Part P.1: one-element JSON arrays allocate
  `(vector first)` instead of list + `nreverse` +
  `coerce`. Stream-chat 2,357,254 B → 2,350,697 B.
  FiveAM 18999→19008. Identity 122626→122637. G.17 still
  `missing`.

- Goal 20 Part P.1: JSON integers parse from the source
  window (no SUBSEQ token). Decimals and exponents stay on
  the existing token path. Same-machine session.jsonl
  8727 ns → 6794 ns / line; 1.83 MB → 1.58 MB / pass.
  Stream-chat 2,432,214 B → 2,357,254 B. FiveAM
  18987→18999. Identity 122584→122626. G.17 still
  `missing`.

- Goal 20 Part P.4: file-stream SSE scans newlines in the
  8192 `read-sequence` chunk and decodes complete lines
  from that simple array. Sockets stay on `read-byte`.
  Same-machine stream-chat 5.604 ms → 4.995 ms; SSE-only
  2.199 ms → 1.698 ms. Bytes unchanged (2.43 MB /
  1.23 MB). FiveAM 18977→18987. Identity 122563→122584.
  G.17 still `missing`.

- Goal 20 P0: tic-tac-toe `render-call` takes
  `(arguments theme context)` and paints tool-title + muted
  action. Expanded `render-result` is the banner. Tool
  description matches the baseline no-batched-form contract.
  Host passes `:theme` into rich tool renderers. FiveAM
  18949→18977. Identity 122561→122563.

- Goal 20 G.17 stays `missing` (advisor vetoed `blocked` on
  `7e4ec5201`). P.8 leftover. Not a Goal 20 pass.

- Goal 20 Part G.17 is `blocked`, not `met`: P.8 hand-play
  is unavailable and the advisor has not written G.17 may
  be `met`. Not a Goal 20 pass.

- Goal 20 Part P draft: P.8 is `blocked` (user has not
  played; FiveAM is not hand-play). P.10 this-host
  key→overlay 0.050 ms, spinner=NIL. P.11 14/14. G.17
  still `missing`. Not a Goal 20 pass.

- Goal 20 Part P.8: snake and invaders overlays read the
  live global when bound (`*snake-state*`,
  `*space-invaders-state*`), matching tic-tac-toe. User
  hand-play still leftover. G.17 still `missing`.

- Goal 20 Part P.4: object keys on the OpenAI completions
  chunk set reuse string literals instead of a fresh
  SIMPLE-BASE-STRING each time. Same-machine stream-chat
  4.797 ms / 2,545,901 B → 4.797 ms / 2,432,299 B. G.17
  still `missing`.

- Goal 20 Part P.4: `parse-json-source` allocates the escape
  scratch only when a string has escapes. Same-machine
  stream-chat 5.402 ms / 2,677,288 B → 4.797 ms / 2,545,901 B.
  G.17 still `missing`.

- Goal 20 Part P.4: binary SSE `data`/`event`/`id` lines
  decode only the payload octets (specialized copy, not
  coerce of the adjustable line). Same-machine stream-chat
  5.397 ms / 3,108,022 B → 5.402 ms / 2,677,288 B; SSE-only
  1,659,406 B → 1,229,201 B. G.17 still `missing`.

- Goal 20 Part P.4: `split-sse-field` keeps `data`/`event`/`id`
  literals and takes one payload `subseq`. Same-machine
  stream-chat 6.004 ms / 3,415,114 B → 5.397 ms / 3,108,022 B;
  SSE-only 2.500 ms / 1,970,208 B → 2.199 ms / 1,659,406 B.
  G.17 still `missing`.

- Goal 20 Part P.4: `read-sse-stream` joins a single data line
  without `format`. File-stream binary bodies use specialized
  `read-sequence`; sockets stay on `read-byte` so incremental
  SSE can flush (NATIVE-HTTP). Same-machine stream-chat
  6.398 ms / 3,750,979 B → 6.004 ms / 3,415,114 B; SSE-only
  2.899 ms / 2,327,510 B → 2.500 ms / 1,970,208 B. G.17
  still `missing`.

- Goal 20 Part P draft: this-host stream 5.400 ms / 3.75 MB;
  key-to-overlay 0.100 ms; restart FiveAM 14/14. Advisor
  vetoed G.17 `met` (`c53e13c47`). G.17 is `missing`. P.4
  stream leftover until an `sse.lisp` lever. Not a Goal 20 pass.

- Goal 20 Part P.3: `--list-models` reuses a refreshed registry while
  `models.json` / `auth.json` write-dates stay the same. Same-machine
  `print-cli-models` median 4.30 ms → 2.45 ms (80 calls). Not
  Friend-MachineD pairing. Probe 7d (table format) not repeated.

- Goal 20 Part P.2: journal_append harness mkdir/create is reported
  separately from product `session-append-message`
  (`docs/benchmarks/goal20-part-p-append-tax.md`). Same-machine
  create-session 0.40ms vs 128 appends 3.00ms. Paired metric unchanged.

- Goal 20 Part P.2: `terminating-rational-json-text` writes digits
  once instead of a padded copy plus four concatenate/subseq results.
  Same-machine median 210 ns → 170 ns / call. Own commit.

- Goal 20 Part P.2: `write-json-string` emits unescaped spans with
  one `write-string` instead of per-character `write-char`. Same-machine
  session-object stringify median 6596 ns → 5636 ns (40×515;
  HEAD 6209/6596/6791 vs 5625/5636/6012). Not Friend-MachineD pairing.

- Goal 20 Part P.1: `parse-json-source` coerces to `simple-string`,
  scans with `schar`/`fixnum`, and copies unescaped ASCII windows as
  `simple-base-string`. Same-machine `session.jsonl` parse median
  6489 ns → 5663 ns (300×515 lines; HEAD 6411/6489/6851 vs
  5562/5663/6080). Not Friend-MachineD pairing. Probe 7b not repeated.

- Goal 20 Part K9: `cadr-cli` 54 rewrite files share one
  owner each (flag table, hotkeys rows, OSC splice, gutter
  walk, `:component` input, llama `:manual`, installer
  `GIT:` case, optional-integer JSON null). Selectors not
  merged. FiveAM 18841 → 18880.

- Goal 20 Part K8: `cadr-tui` 29 rewrite files share one
  owner each (char/string walks, rebuild key dispatch,
  layout vectors, compiled scanners). Generated
  `mermaid/width-data.lisp` untouched. FiveAM 18768 → 18841.

- Goal 20 Part K7: `cadr-ai` 28 rewrite files share one
  owner each (device parse, reserved keys, PKCE login,
  stream blocks, runtime error wrap). Generated catalogs
  untouched. FiveAM 18748 → 18768.

- Docs: live Slynk is first on a running cadr, not a last resort after
  guessing (`development-policy` §6.1, `AGENTS.md`). Load-and-probe is
  not a substitute. Do not add restarts on pairable user-visible paths
  to look native. Performance floor is pi; beating pi is not a stop —
  the target is this SBCL image's limit for cost and interactivity
  (Goal 20 Part P). Concurrent agents: disjoint worktrees and an
  ownership table; never two writers in one checkout.

- Goal 20 Part K6 follow-up: `with-present` owns every schema
  present-p bind; `call-signaled-operation` owns abort/classify
  for remove and temps. FiveAM 18738 → 18748.

- Goal 20 Part K6: `cadr-agent` 23 rewrite files share one
  owner each (queue slots, when-present, authoring macros,
  message generic, tail pointer). FiveAM 18725 → 18738.

- CI runs only on `workflow_dispatch`. Push and pull-request
  triggers are gone. Daily path is local `test-cl.sh` / `verify.sh`.
  FiveAM 18722 → 18725.

- Goal 20 Part K5: `cadr-evals` flag prefix, harness merge,
  message tail, reporter push, JSON string accessor, and
  one-argument signed format each have one owner.
  FiveAM 18699 → 18722.

- Goal 20 Part K4: `cadr-server` instance lookup, IPC client
  wrap, instance upsert, and Radius heartbeat share one owner
  each. FiveAM 18691 → 18699.

- Goal 20 Part K3: `cadr-protocol` encoder limits live on
  `cbor-writer`, frame decode uses a cursor, optional schema
  fields share `optional-field-p`. FiveAM 18683 → 18691.

- Goal 20 Part K2: `cadr-storage` stays `no-rewrite` (I verdicts
  undrifted). Theme index recount 197 → 198.

- Default live vehicle is OpenCode Go `mimo-v2.5`. `prepare-opencode-go-credential`
  accepts `auth.json` or `OPENCODE_API_KEY`. A default live item locks a
  nonempty thinking stream. Native DeepSeek FiveAM items still skip
  without `DEEPSEEK_API_KEY`.

- `unix-milliseconds` reads real milliseconds from
  `sb-ext:get-time-of-day`. The old `get-universal-time * 1000` path
  quantized every timestamp and ID to a whole second. Matches
  baseline `Date.now()`. FiveAM 18670 → 18673.

- Statistical liveness default path is documented as the P0-4 silence
  lock only (`liveness-ttt-agent-turn`). The booked table is a local
  `--all` instrument and does not enter CI (board 2026-08-17 A).

- Healed two source-parity mapping positions after the unused-helper
  deletions (`credential-for-print` 192→183,
  `render-truncated-text` 1524→1514). Verdicts and key set unchanged.

- Goal 20: model and session selectors cache filter and haystack
  work across frames. Fuzzy matching downcases each candidate once
  per filter instead of once per token.

- Provider SSE reducers append stream text, thinking, signatures, and
  partial tool JSON with an amortized-linear buffer instead of
  concatenating the whole prefix on every delta. Tool-argument JSON is
  parsed when the block ends, not on each fragment.

- Goal 20 Part O: `parse-json-source` copies unescaped strings from the
  source window and inlines peek/take. Escaped strings still decode
  into a fill-pointer buffer. Enforced paired-path `journal_read`
  5.42× → 3.92× and `session_load` 6.71× → 4.48×.

- Goal 20 Part O: `make-session-entry-id` seeds one random state per
  image instead of calling `make-random-state` on every attempt, which
  dominated `journal_append`.

- Goal 18 Part L: re-anchored the fixed pi baseline to v0.84.1.
  cadr 0.2.0 · aligned with pi v0.84.2 (+0, 914cf1472).  `--alt` is replaced
  by `--tui-mode regular|fullscreen` with the baseline diagnostics; the
  `tuiMode`, `fullscreenScrollbar`, and `markdown.mermaid` settings are
  honored; alt-screen navigation defaults moved to the baseline's
  unshifted keys with new half-page and prompt-jump actions plus
  editor prompt-history actions; `scrollbarThumb` joins the theme
  tokens; baseten and qwen-token-plan-individual providers registered
  with the regenerated 0.84.1 model catalog; child processes learn
  `CADR_CODING_AGENT=true` and `AI_AGENT=cadr`.

- Aligned `--resume` with the baseline (goal 18 adjudication): the flag
  no longer consumes a session id (`--session <id>` remains the exact-id
  path); a following token is a prompt message, matching baseline
  args.ts.  Bare `--resume`/`-r` now opens the baseline pre-TUI session
  picker (cli/session-picker.ts) instead of silently resuming the latest
  session: current-folder scope with Tab to all sessions, lazy all-scope
  load, search/sort/name/path toggles, delete confirmation, and the
  baseline cancel (dim "No session selected", exit 0) and interrupt
  (silent exit 0) paths.

- User keybindings now load from `~/.cadr/agent/keybindings.json`
  (baseline KeybindingsManager.create), coexisting with the settings.json
  `keybindings` key with the file taking precedence; legacy names
  migrate identically, and a malformed file falls back to the settings
  value like the baseline loadRawConfig.

- Bare-environment startup now keeps the baseline no-model sentinel
  instead of an openai default: the footer reads "no-model" with a
  0-token context window, sending fails with the baseline
  NoModelSelected guidance before any append, manual /compact fails with
  the baseline compaction event pair, and non-interactive modes exit 1
  with the red NoModelsAvailable text (baseline main.ts:852-854).

- Aligned the user-level layout with the baseline: agent data (settings,
  auth, models, sessions, themes, prompts, tools, bin, extensions, and
  crash logs) now lives in `~/.cadr/agent/` instead of flat `~/.cadr/`,
  with `CADR_CODING_AGENT_DIR` as the override; `~/.cadr/server/` stays at
  the home root.  Startup automatically migrates a pre-agent-layer flat
  layout by renaming the residents (preserving the `0600` auth mode),
  refuses to choose when both layouts hold data, and skips when the
  override is set.  All path decisions now derive from a single owner in
  `cadr-core`, enforced by the code-organization gate.

### Added

- P0-2 / P0-3 request-render pairing: timer ticks share
  `snake-component-advance` / `space-invaders-advance` (baseline
  snake.ts:90-97, space-invaders.ts:144-151). User-input sites stay
  on `tui-dispatch-event` (root.lisp:207-208). Behavior tests now
  assert the timer requested a frame. Gate-validity in
  `docs/acceptance/goal-v20-p0-2-request-render.md`.
  FiveAM 18668 → 18670.

- Theme index in `docs/test-matrix.md`: every `test/**/*.lisp` and
  `test/**/*.py` file (197) under the nine FiveAM systems plus live
  runner, Python gates, and fixtures. Anchor unchanged.

- Statistical liveness stage (goal 20 12E-1): booked per-scenario
  `N_i` from the 2026-08-15 measurement, `verify.sh` checks the
  silence-injection scenario n=3, and a failure prints the full
  gap list. Outside `render-diff.py gate --tier core`.
  FiveAM anchor 18633 → 18636.

### Removed

- Goal 20 sb-cover third-tier: deleted six unused helpers
  (`auth-credential-value`, `content-text-blocks`, `gm-to-ansi`,
  `markdown-ordered-prefix-end`, `package-source-with-ref`,
  `trailing-lines`). Each had no caller; live paths already own
  the work. Denominator 122640 → 122575.

### Fixed

- Tic-tac-toe overlay follows the live global after reconstruct
  replaces the state object (baseline `updateState`). Thinking
  footer only when it is O's turn.
  FiveAM 18925 → 18932.

- Busy `send-message` with `trigger-turn` steers the running agent
  (baseline `isStreaming` + `triggerTurn`). Tic-tac-toe no longer
  throws DELIVER-AS or leaves a half-played board; tool lines
  render `move_down` / `play` instead of raw JSON.
  FiveAM 18880 → 18925.

- Statistical liveness runs from the git checkout, not the isolated
  tar copy. render-diff capture needs `git -C <repo>`; the isolated
  tree has no `.git` and CI died in 1s with "fatal: not a git
  repository". Thresholds unchanged. FiveAM 18665 → 18668.

- Completions streams read the first nonempty of
  `reasoning_content`, `reasoning`, and `reasoning_text`
  (baseline openai-completions.ts:489-509). Dual emit does not
  double the thinking block. OpenCode Go `reasoning` uses the
  `reasoning_content` signature so history replay matches.
  FiveAM 18657 → 18665.

- Settings-list space matches the baseline: activate only when
  search is off or the query is empty; otherwise space and paste
  keep spaces in the search box (baseline settings-list.ts:187).
  FiveAM 18652 → 18657.

- `write-websocket-frame` now calls `write-websocket-length` for
  the 16-bit and 64-bit extended fields. The helper no longer
  writes the first length byte, so a masked 16-bit frame cannot
  be mistaken for a 64-bit form. Not a write-side pair of the
  64-bit read bug. FiveAM 18640 → 18652.

- Wire `oauth-selector-handle-raw-input` into the overlay
  raw-input dispatch, matching the other selectors. Paste and
  custom keybindings now reach the OAuth selector. FiveAM
  18636 → 18640.

- Re-pin `example-commands/narrow/commands-path` cadr
  `screenSha256` after wrapped `<CADR_ROOT>` path join. Baseline-side
  and wide SHAs unchanged. Local official core gate EXIT:0
  (120/122). Does not declare the CI differential green.

- Render-diff `<CADR_ROOT>` paths absorb a hard wrap and the
  continuation-line pad so CI and local wrap points converge.
  Does not re-pin I04 pairs in this change.

- RPC `steer` / `follow_up` and busy `prompt` +
  `streamingBehavior` run `:input` hooks off the JSONL reader,
  matching a new prompt. A second hook invocation can no longer
  block confirm/editor answers. Unconditional `rpc-ui-diag`
  prints removed from the RPC UI product path.

- Booked the unpaired-path denominator at 122613 after completions
  reasoning-field coverage.

- Booked the unpaired-path denominator at 122586 after aligning
  settings-list space with the baseline.

- Booked the unpaired-path denominator at 122575 after deleting
  six unused sb-cover A-class helpers.

- Booked the unpaired-path denominator at 122640 after wiring
  the WebSocket extended-length helper.

- Booked the unpaired-path denominator at 122638 after wiring
  OAuth selector raw-input.

- Booked the unpaired-path denominator at 122632 after moving
  RPC steer/follow-up input hooks off the JSONL reader.

- RPC process-modes UI path prints hook/dispatch/client
  diagnostics for confirm and editor so a missing pair can be
  located on the next CI run. Required method set unchanged.

- Re-pin `fatal-crash/narrow/fatal-crash` baseline-side
  `screenSha256` after the wrapped `node:internal` module collapse.
  cadr and wide SHAs unchanged. Does not declare the render
  differential green.

- Render-diff `node:internal/<module>:N:M` collapse now allows a
  hard wrap inside the module name (narrow `processTimers` splits
  `timers` so `521:7` / `523:7` no longer leak). Does not re-pin
  I04 pairs in this change.

- Re-pin `example-commands/{wide,narrow}/commands-path` cadr
  `screenSha256` after checkout root collapsed to `<CADR_ROOT>`.
  Baseline-side SHAs unchanged. Does not declare the render
  differential green.

- Recorded the 2026-08-17 role rulings in the adjudication log and
  advisor playbook (executor never writes a ruling; advisor is
  read-only on shared CI state; differential pins are local truth).

- After a bash tool completes, the settle window stays open through the
  following assistant message and its text deltas (user messages and
  the next tool still lift it), so a wall-clock tick during persist or
  the short "observed" text cannot paint Took+loader and ratchet the
  previous Took line off the render-diff viewport.

- RPC `get_state` now emits JSON `null` for a missing model instead of
  raising on the no-model sentinel. cadr-server spawn retries
  `get_state` until the child reports a non-empty `sessionId` before
  marking the instance online.

- RPC `get_state` omits the `model` key when no model is selected,
  matching baseline `JSON.stringify` of an undefined optional field.

- Render-diff semantic screens collapse `node:internal/<module>:N:M`
  line numbers to `<NODE_LINE>:<NODE_COLUMN>` so Node patch releases
  do not move fatal-crash I04 pairs.

- Re-pin `fatal-crash/{wide,narrow}/fatal-crash` baseline-side
  `screenSha256` after the node:internal collapse. cadr SHAs
  unchanged.

- Goal 20 P0-4: extension `send-message` with trigger-turn no longer
  runs the agent turn on the TUI input thread, so streaming text, tool
  blocks, and the working indicator can paint during the turn. The
  tic-tac-toe move custom message uses the compact banner renderer
  instead of the raw board content.

- WebSocket frames with payload length 65536 or more now read all eight
  length octets (the 64-bit branch used to skip the first), and
  fragmented messages are assembled until FIN. Codex WebSocket debug
  stats take the cache mutex on write as well as read.
  `wss://`/`ws://` URLs convert to `https://`/`http://` for the HTTP
  upgrade.

- `parse-json` signals `json-parse-error` instead of relabeling every
  JSON failure as `sse-protocol-error`. HTTP `request-json` maps a
  damaged body to `transport-error`; streaming JSON repair catches
  `json-parse-error`.

- Startup loaded-resource blocks now follow the baseline (goal 18 Part H):
  section order Context -> Skills -> Prompts -> Extensions -> Themes with
  the baseline labels, locale-compare sorting (Context keeps insertion
  order), banner/sections split at the baseline padding boundary, and the
  three warning blocks ([Skill conflicts], [Prompt conflicts],
  [Extension issues]) with collision groups and severity colors.  Resource
  name collisions keep the baseline winner (project scope) but now record
  the collision diagnostic instead of dropping the loser silently.  A new
  `startup-resources` render-diff scenario captures the populated startup
  in compact and ctrl+o-expanded form on both terminal sizes while the
  empty startup scenarios stay pinned, and the state-coverage sweep is
  documented in `docs/goal18-startup-resources-audit.md`.

- Render-diff harness hygiene (goal 18 Part G): a single-owned sweeper now
  removes tmux `cadr-rd-*` servers whose owning run died and stale
  `/tmp/cadr-render-screen-*` replay dirs at every CLI start, and the
  tmux_screen failure branch is regression-tested to kill its server.
  The two stray `/export` HTML artifacts at the repository root are covered
  by the existing `cadr-*.html` gitignore rule (mirroring the
  baseline's export-artifact ignore rule).

### Added

- Goal 20: `docs/profiling.md` is the standing `sb-sprof` runbook.
  `scripts/goal20-profile.sh` is the driver; neither is a gate.

- Goal 20 Part H: `scripts/goal20-unpaired-paths.py` books which
  `src/**/*.lisp` files are paired, unpairable, or still uncovered.
  The report is section 6 of `docs/acceptance/goal-v20-part-h.md`.

- Goal 20 Part O: `scripts/goal20-profile.sh` captures `sb-sprof` for
  paired paths that still miss 1.0×; the report is
  `docs/benchmarks/goal20-part-o-remaining-sprof.md`.

- Goal 20 Part B: paired-path ratios and FiveAM check counts are written by
  scripts into `docs/performance.md` and the `GOAL20_TEST_CHECKS` comment in
  `docs/test-matrix.md`. `scripts/record-paired-paths.py` books a run from
  the paired-path summary; `scripts/write-test-check-anchor.py` fails
  `test-cl.sh` when the committed check count drifted.

- Goal 18 L2.1: the fixed pi baseline anchor now has a single owner — the
  `BASELINE` file at the repository root (commit, release tag, distance).
  The product release identity derives from it at load time, the diff and
  verify scripts read it instead of embedded literals, a new
  `baseline anchor consistency` stage in `verify.sh` fails when any
  operational reference disagrees, and `scripts/set-baseline.sh` performs
  the mechanical rewrite on upgrade.

- Goal 18 Part L preparation: `scripts/enumerate-baseline-diff.py`
  mechanically enumerates every named user-observable or contract set
  between two baseline commits (flags, settings keys, events, providers,
  env vars, theme tokens, error classes, RPC methods, exit codes, session
  format, ...).  Its first run caught four classes the hand-maintained
  list missed; the v0.84.1 enumeration result is recorded in
  `docs/source-parity-upgrade.md`.

- Goal 18 I7 tail and Part J/K: the startup content migrations are ported
  (oauth.json/settings apiKeys into auth.json with 0600 preserved,
  agent-root sessions into sessions/, managed binaries tools/ -> bin/,
  commands/ -> prompts/ for the global and project roots, and the
  deprecated hooks//tools/ warnings with the interactive any-key pause,
  in the baseline startup order); `--list-models` prints the baseline
  auth-filtered six-column table with fuzzy filtering and the corrupt
  models.json warning envelope; a broken extension is now a fatal
  startup error with the baseline reportDiagnostics lines and the
  `cadr -ne` hint; extension shortcut conflicts follow the baseline
  getShortcuts semantics (reserved keys skip, later registration wins,
  warnings land in the [Extension issues] block); unreadable
  --system-prompt/@file paths produce the baseline Node-style error
  wording instead of raw conditions; the legacy keybinding-name
  migration covers the full 62-name baseline table; the system prompt's
  documentation paths now resolve to the real repository docs instead of
  a hardcoded /usr/local prefix; the twelve user docs the product text
  references (the eleven system-prompt documents plus providers.md) now
  exist and every docs//examples/ reference in product text is
  gate-enforced to resolve (Part J); and the seven coding tools'
  model-visible contract (description, full parameter schema with
  per-property descriptions, prompt snippets) is locked against a
  fixture the gate regenerates from the fixed baseline at capture time
  (Part K — this also renamed grep's `ignore_case` to the baseline
  `ignoreCase` and dropped a non-baseline `minItems` from edit).

- Goal 18 I2 mechanically derived coverage: the login dialog's eight
  `show*` forms and the 33-leaf ExtensionEvent union are extracted from
  the baseline commit's git objects at analysis time and drift-checked
  against the interface inventory, with each dialog form mapped to a
  scenario checkpoint or the construction suite; the unmodeled-sink
  reverse scan (I7.3) fails the gate on any output call with fixed text
  that no inventory site covers, with the 14 current candidates under
  per-site reviewed verdicts; and REQUIRED_COVERAGE now locks the full
  declared tag set so no scenario or tag can silently disappear.  The
  diff report is `docs/goal18-i2-derived-coverage.md`; ten defensive or
  privilege-dependent branches await exemption adjudication in
  `docs/proposals/goal18-i7-tail-exemptions.md`.

- Goal 18 Part I gate hardening and capability completion: the reused
  pi baseline checkout is now verified blob-for-blob against the
  repository's immutable object store before any differential run (I5);
  `verify-release.sh` can no longer exit 0 with live stages skipped —
  `CADR_RELEASE_GATE=1` turns a live SKIP into a named failure while
  everyday `verify.sh` keeps the skip behavior (I6); the presentation
  ledger's scale numbers are machine-reconciled by a FiveAM gate that
  recomputes them from the real artifacts (I4); the four baseline
  session keybinding actions `app.session.{new,tree,fork,resume}` are
  registered unbound, bindable via settings.json, and dispatch to the
  same handlers as their slash commands (I7); and the bundled llama
  extension gained the full baseline `ui.ts` surface — context-size
  labels, model descriptions, compact counts, the framed model selector,
  live Hugging Face search with debounce, and the cancellable progress
  view over a persistent custom component with a render channel (I8).

- Goal 18 Part E/F audit deliverables: the intentional-difference ledger grew
  from 72 to 77 rows after recasting five component-export rows
  (extension/show-images/skill-invocation/theme/thinking selectors) with
  baseline-consumption evidence, and the `settings-state-sweep` render-diff
  scenario now enables terminal image support so the `Show images` and
  `Image width` rows are captured and pinned on both sides.  The full audit
  report lives in `docs/goal18-part-e-audit.md`, and the package-boundary map
  in `docs/source-parity.md` §1a now records the `cadr-core` path-owner and
  the `agent/src/harness/tools/` routing refinement.

- Implemented the baseline `/debug` command and its `shift+ctrl+d` binding:
  the terminal's rendered lines (with visible widths) and the agent messages
  (JSONL) are written to `~/.cadr/agent/cadr-debug.log` (I04 filename), and
  the chat confirms with the baseline accent "✓ Debug log written" + muted
  path block.  Recorded that the baseline's `getToolsDir` is dead code (zero
  callers) and is deliberately not implemented.

- Completed the login dialog's baseline surface: auth selects now borrow the
  screen and restore the dialog (the Radius/OpenAI method choice no longer
  strands later auth events into the transcript), text/secret prompts render
  through the dialog's prompt form, and the info (message + links) and
  details forms exist.  Bedrock and Vertex API key logins run their baseline
  structured flows (method select, per-method prompts, info notice with
  links) through the dialog, and the login completion messages follow the
  baseline "Logged in to … Credentials saved to …" text.  New render-diff
  scenarios cover the manual-code and browser-callback flows end to end —
  cancel with post-cancel probes and a completion path each.

- Added the fourth parity ledger for visible presentation semantics, including
  production probes for all 55 theme tokens and machine-checked ledger totals.
- Added a self-contained baseline-compatible session HTML exporter with the
  approved vendored Marked and Highlight.js browser assets.

### Changed

- Reduced alternate-screen continuous-input p99 from 52ms to 8ms at the
  5,000-entry stress tier while preserving the complete logical document.
- Replaced the OAuth callback page's interim block-C mark with Cadr's
  single-path square-grid cons-cell identity.
- Changed `/share` to use `https://cadr.dev/session/` by default, with
  `CADR_SHARE_VIEWER_URL` as the sole environment override.
- Replaced the remaining 14 production `PI_*` environment names with their
  `CADR_*` equivalents without legacy aliases.

### Fixed

- Fixed ESC-cancelling an xAI, Kimi, GitHub Copilot, or Radius device-code
  login never reaching the shared device poller's cancellation flag, so the
  login worker ran until token expiry and every later message stalled in the
  Steering queue; the flows now poll through `poll-device-authorization`'s
  `cancelled-p` like the OpenAI Codex route, and each cancel-path render-diff
  scenario ends with a post-cancel message exchange.
  Attribution (goal 18 A4.5): the mechanism — `busy-p` cleared only when the
  login worker ends, with ESC setting flags but never guaranteeing that end —
  predates the goal 17 login-dialog rework (74fe2c0b8); the rework exposed it
  by giving ESC a dialog-closing path that made "cancelled UI, living worker"
  reachable.  It is not a goal 17 regression.
- Cancelling OpenAI or Anthropic login now stops the loopback/manual workers,
  releases the listener, clears the working state, and returns to the editor.
- Interactive cleanup now bounds every background-thread join and forcibly
  stops an unresponsive worker instead of deadlocking exit.
- `/export` now reports the baseline-aligned bare output filename.
- Fixed automatic version checks comparing upstream pi `0.83.x` releases with
  Cadr `0.2.x`; checks are now disabled unless `CADR_VERSION_CHECK_URL` names a
  Cadr-compatible endpoint.
- Fixed outbound provider attribution, changelog links, browser storage,
  temporary files, synthetic tool IDs, examples, and Radius diagnostics that
  still presented Cadr as pi.

### Security

- Unhandled conditions now use a sanitized fatal boundary: terminal output
  contains no backtrace or object dump, diagnostics are exact/pattern redacted
  into mode-0600 crash logs, and credential-bearing objects print redacted.

## [0.2.0] - 2026-08-01

**cadr 0.2.0 · aligned with pi v0.83.0 (+38, 74caa2649)**

### Added

- Goal 1: established the Common Lisp/ASDF architecture and the provider,
  streaming, message, tool, usage, and error foundations.
- Goal 2: implemented the agent loop, lifecycle event spine, tool execution,
  retry/abort handling, and session state.
- Goal 3: added the native CLI, REPL, built-in coding tools, provider/model
  configuration, system prompt, and recorded provider parity fixtures.
- Goal 4: added JSONL persistence, continuation, retry policy, native image
  builds, migration acceptance, and executable smoke coverage.
- Goal 5: delivered the pure Common Lisp TUI, Unicode/grapheme-safe editor,
  overlays, images, resize handling, differential rendering, and terminal
  lifecycle recovery.
- Goal 6: expanded provider/catalog, OAuth, image, model-runtime, extension,
  package, session-tree, compaction, and RPC compatibility with original pi.
- Goal 7: completed the audited extension lifecycle/UI/runtime API, session and
  queue surfaces, print/JSON/RPC modes, SQLite storage, Unix-socket server, and
  eval harnesses.
- Goal 8: closed the exhaustive TypeScript test parity ledger, added the CBOR
  protocol package, completed the dependency audit, and separated deterministic
  and credential-gated live FiveAM entry points.
- Goal 9: upgraded the behavioral baseline to
  `earendil-works/pi@74caa2649f10ed71b4378ce69f5d9fbfd2466ca5`, automated the
  former manual acceptance paths, completed mechanical/runtime TUI parity,
  identified OpenAI traffic as `originator=cadr`, and added the local
  deterministic/build/process/PTY/live verification gate.
- Goal 10: established the private backup and real CI gate, retained the
  newer-than-tag baseline by explicit no-op adjudication, and added the
  approved Lisp-native tool restarts plus opt-in loopback Slynk REPL.
- Goal 11: added deterministic performance, allocation, cold-start, long-run
  memory/resource, and large-session latency release gates.

### Changed

- Renamed the implementation, packages, executable, configuration directory,
  and environment namespace from the migration-era `pi-cl` names to Cadr while
  preserving the historical reference and migration path.
- Aligned the security model with original pi: tools execute directly by
  default, optional approval is an extension hook, and containerization remains
  the strong isolation boundary.
- Released version `0.2.0` from the single `version.sexp` production source;
  the CLI identity also records alignment with pi `v0.83.0` plus 38 commits at
  `74caa2649`.
- Removed the completed `0.1.x` fallback for `PI_CL_PROVIDER`, `PI_CL_MODEL`,
  and `PI_CL_BASE_URL`; use the `CADR_*` names.

### Fixed

- Corrected provider stream text preservation, OpenAI Responses reasoning
  summaries, unknown-model thinking capabilities, OAuth provider identity, and
  model-facing tool result text/counting semantics.
- Corrected selector empty/wrap boundaries, CJK/emoji editing, streamed TUI
  output, tool error states, Markdown/code rendering, overlay copy/layout,
  footer model refresh, terminal positioning, and PTY restoration.
- Removed test timing races, OAuth refresh-token copy pollution, shell-smoke
  credential rewriting, wrapper stderr leakage, and user-settings coupling from
  deterministic/live evidence.

### Security

- OAuth credentials use a single `~/.cadr/auth.json` store with atomic writes,
  mode `0600`, refresh locking, provider-consistent identities, and redaction
  from errors, sessions, transport logs, and reports.
- Third-party dependencies are frozen by the audited allowlist; any new direct
  or transitive dependency blocks implementation until explicit pre-approval.
- Slynk is default-off, loopback-only, explicitly enabled, and documented as
  an arbitrary-evaluation debugging service rather than a sandbox.
