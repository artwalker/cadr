# Goal 20 — already-paired paths still >1.0× (docs only)

Friend-MachineD ledger in `docs/performance.md` (not a remesure).
**No optimize in this file.** Invent remains paused (十B.17–18).
G.17 stays `missing`. Not Goal 20 complete.

| metric | cadr µs | pi µs | ratio | ceiling | leftover | disposition |
|---|---:|---:|---:|---:|---|---|
| `session_pipeline.session_load` | 1762.6 | 1595.0 | 1.11× | 9.00× | `PARSE-SESSION-RECORD-OCTETS` vs V8 `JSON.parse` (compact-prefix + u32 entry + message first-byte kept) | invent pause; 待本质提案（分配/表示） |
| `storage_journal.journal_read` | 1577.6 | 1305.4 | 1.21× | 8.00× | `SCAN-BUFFER` / line consume; inline consume-line withdrawn | invent pause; 待本质提案 |
| `provider_pi_messages.stream_roundtrip` | 1080.8 | 830.4 | 1.30× | 1.50× | character `PARSE-JSON-SOURCE` on SSE; `WRITE-JSON-STRING`; EQUAL hash grow. parse-json-octets / unescaped stringify / pairs / pre-size withdrawn | invent pause; 待本质提案 |
| `provider_mistral.stream_roundtrip` | 2045.6 | 1644.0 | 1.24× | 3.00× | character `PARSE-JSON-SOURCE` on Conversations SSE; `data-octets` withdrawn | invent pause; 待本质提案 |
| `session_compact.compact` | 36.7 | 35.3 | 1.04× | 20.00× | near 1.0; uuid-v7 entropy pool already kept | 待 MAD/本质；不开现象刀 |

Ceilings not lowered. Do not redo withdrawn phenomenon knives.
