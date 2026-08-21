# Goal 20 — journal_read sb-sprof (walker `0084f0703`)

Diagnostic, not a gate. 4 s, sample-interval 0.001 s, pairing
fixture `test/fixtures/goal20-paired-paths/session.jsonl`.
This-host. Not G.17.

Walker `0084f0703` / Friend-MachineD load **~1763 µs**.
Load first-byte family is exhausted (usage 1996, content
generic 2470). This capture names leftover for
`storage_journal.journal_read` only.

## Verdict

`read-session-objects` / `PARSE-SESSION-RECORD-OCTETS` still
own the samples. Unused legal structure is **not** another
load first-byte / compact-prefix / intern-grow / fill-kernel
/ SCAN-KEY macrolet.

journal_read self (this-host):

| fn | self % | note |
|---|---:|---|
| `PARSE-SESSION-RECORD-OCTETS` | 11.2 | 81.7% total |
| `SCAN-BUFFER` | 10.7 | 94.6% total; wraps `consume-line` per LF |
| `SCAN-KEY` | 8.7 | macrolet redo banned |
| `PARSE-STRING-VALUE` | 6.5 | |
| `PARSE-USAGE` | 6.1 | first-byte withdrawn |
| `COPY-UNESCAPED-JSON-OCTETS` | 5.5 | fill-kernel banned |
| `JSON-INTERNED-ASCII-VALUE-OCTETS` | 3.5 | intern-grow banned |
| `OCTET-WINDOW-EQUALS` | 3.2 | |
| `UTF8->STRING-AREF` | 2.7 | 12.6% total |

Named leftover that is not a banned redo: **`SCAN-BUFFER`
labels call to `consume-line` once per JSONL line** (pairing
fixture is one exact-size read, `pending` nil). Next knife:
inline `consume-line` into `scan-buffer`. Not E `tagbody`.
Not first-byte. Must not push Friend-MachineD load past
**~1763 µs**.

session_load same capture: `SCAN-BUFFER` 9.3% self /
`PARSE-SESSION-RECORD-OCTETS` 9.2% self. Same function.
