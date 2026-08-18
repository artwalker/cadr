# Goal 20 Part P — journal_append harness tax vs product path

Diagnostic, not a pairing metric. The paired
`storage_journal.journal_append` thunk still calls
`append-journal-once` (mkdir a fresh session directory, write the
header, then append 128 messages). That matches the pi side.

Recorded 2026-08-18 on this host, HEAD `d4da3cb65`, 128 fixture
messages:

| slice | ms |
|---|---:|
| `create-session` (mkdir + header) | 0.40 |
| 128× `session-append-message` | 3.00 |
| combined (create then 128 appends) | 4.00 |

Create is ~10% of the combined sample here. The Part O sprof ~40%
`mkdir`/`open`/`write`/`access`/`close` self includes product
open-append, not only the harness mkdir.

Further append work should time `session-append-message` on an
existing file. Do not lower `RATIO_CEILINGS` in the same commit as a
speedup. 7c (fd cache) is in range only if the product path benefits.
