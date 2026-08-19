# Goal 20 — pi algorithm / data-structure audit

Advisor read-only pass, 2026-08-19. Trigger: user asked to
fix the development rule, then re-check cadr for the same
code defect as `truncate-harness-tail`.

Rule: `docs/development-policy.md` section 1 item 6.
Product alignment = observable behavior. Speed design = pi's
passes and data structure, Lisp encoding. sprof of a worse
algorithm is not a design source.

This is not 148 file benches (G.12). Only paths where pi's
production function was opened, or the cadr encoding is the
same family as the confirmed truncate miss. `uiop:split-string`
on a short config line is not in this table.

Do not treat this file as G.17 `met` or Part P `[done]`.

## Class A — pi's structure was deleted (scan replaced split/array)

| cadr | pi | What is wrong | Next knife |
|---|---|---|---|
| `src/cadr-agent/truncate.lisp` `truncate-harness-tail` / `truncate-harness-head` | `packages/agent/src/harness/utils/truncate.ts` `truncateTail` / `truncateHead`: `Buffer.byteLength` + `split("\n")` + index | One walk fills totals + fixnum start/width table; ASCII runs add 1×run; index from the end; one `subseq`. Pairing tail **0.85×**. | Leftover is remaining mixed `utf8-char-length` / selection, not another array swap. Not FFI `Buffer`. Not another reverse scan. |
| `src/cadr-cli/truncation.lisp` `utf8-length` | Same files: `Buffer.byteLength` | Still `(length (cadr-ai::utf8-octets text))`. Agent already has `harness-utf8-length`. Callers: `output-accumulator`, `tools/read`, `tools/bash`. | Delegate to `harness-utf8-length`. Do not encode to count. |

## Class B — pi's structure kept, Lisp encoding is a list (mermaid `nth`)

Policy 4.1 already named `coerce`+`nth` for JS `[...s]`. Same
complexity miss: `length` / `nth` / `subseq` on a cons list
where pi has `string[]`.

| cadr | pi | What is wrong | Next knife |
|---|---|---|---|
| `src/cadr-cli/truncation.lisp` `text-lines` / `split-all-lines` | `split("\n")` → array | Both use the fixnum start table. `text-lines` drops the trailing empty part and trims CR. | Edit still collects strings. |
| `src/cadr-cli/tools/read.lisp` | `packages/coding-agent/src/core/tools/read.ts`: `allLines = textContent.split("\n")`; `allLines.length`; `allLines[startLine]`; `slice` | ub8 one-pass `0x0A` starts then `utf8-string` of the window. Remesure 0.41×. | Leftover still names `SPLIT-OCTET-LINE-STARTS`. Not empty SWAR. |
| `src/cadr-cli/tools/grep.lisp` `ripgrep-file-lines` | `grep.ts` `content.split("\n")` | Cache is the line-start table; octet `read-sequence` + `utf8-string`. Remesure 0.92×. | Read window-decode leftover (`COPY-UTF8-OCTETS`). |
| `src/cadr-cli/tools/bash.lisp` `bash-truncation-notice` | `truncateTail` + `Buffer.byteLength` on the last line | `harness-text-lines` + `car`/`last` + CLI `utf8-length`. | Use the tail result's last line / harness count; no second full split. |
| `src/cadr-agent/storage/jsonl.lisp` `open-jsonl-session-storage` | JSONL = split lines then `JSON.parse` each | Whole-file `uiop:split-string` then `parse-json` per line. Default paired `session_load` is the octet walker in `session/migration.lisp`, not this function. Still the same encoding if this backend is used. | After a pair exists: line offsets + octet FSM, not cons split + EQUAL JSON. |

## Class C — not this defect (do not open a scan-order knife)

| path | why it is a different question |
|---|---|
| `session_load` / `session_read` octet walker vs `JSON.parse` | Copying V8's parser in Lisp (already the standing rule). Empty SWAR / intern growth remain forbidden. Floor still ~2×. |
| `argv_parse` `cli-token-tail=` schar | Same algorithm, cheaper encoding. Remesure after truncate. |
| `3caf85074` alt-screen last-document vector, `fe1a4d944` editor-lines vector | Already the mermaid fix. `alt-screen.lisp` scrollbar still `(nth row lines)` on a list viewport — leftover encoding, not a new algorithm. |
| Markdown table `split-string` + `nth` on cells | pi splits a short row. Not a pairing-floor path. Do not campaign-rewrite. |

## Method for every later leftover

1. Open the pi production function.
2. Name passes and data structure.
3. Name cadr's. If they differ, the knife is the copy (Lisp encoding).
4. If they match, sprof that implementation — not a third algorithm.
