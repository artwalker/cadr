# Goal 20 — session_load / journal_read passes + DS

Diagnostic. Not G.17 `met`. Not Part P `[done]`.

HEAD at booking: `e2a4dfad6`. Friend-MachineD non-quick n=5:
`session_load` **2.09×** (2957 / 1417 µs), `journal_read` **1.97×**
(2718 / 1382 µs). Ceilings 9.0 / 8.0 unchanged. No `src/`.

## Pi (`packages/coding-agent/src/core/session-manager.ts`)

`SESSION_READ_BUFFER_SIZE` = 1MiB.

`loadEntriesFromFile` (paired `journal_read`):
1. `readSync` into a 1MiB `Buffer`.
2. `StringDecoder("utf8")` → JS string `pending`.
3. `indexOf("\n")` + `slice`.
4. `JSON.parse` per line; skip blank / malformed.
5. `FileEntry[]`. Header: first entry `type === "session"` and `id` string.

`SessionManager.open` (paired `session_load`): optional bounded
header scan, then `loadEntriesFromFile`, migrate, `_buildIndex`
(`FileEntry[]` + `Map`).

## Cadr (`src/cadr-agent/session/migration.lisp`)

Default paired path. **Not** `storage/jsonl.lisp` (`uiop:split-string`).

`read-session-objects`: 1MiB ub8 `read-sequence` (exact-size when
`file-length` ≤ cap), `octet-find-lf`, `parse-session-record-octets`
on the line window, skip blank / parse errors, cons list.

`load-session`: that read, header validate, v1/v2 migrate, then
`record-to-session-entry` into an EQUAL hash + cons entries.

## Aligned?

Passes match (1MiB chunked read, LF split, skip bad lines, header,
migrate + index on load). Parse encoding is already the Lisp schema
FSM on octet windows, not V8 `JSON.parse` on strings.

sprof leftover is that walker (`OCTET-U32-LE`, quote/backslash scan,
`PARSE-SESSION-RECORD-OCTETS`). Class C in
`docs/acceptance/goal-v20-ds-audit.md`: copying V8's parser. Empty
SWAR / intern growth / FFI / mmap are not legal knives. No third
algorithm.
