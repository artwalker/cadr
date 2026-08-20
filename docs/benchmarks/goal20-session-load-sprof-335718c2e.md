# Goal 20 — `session_load` sb-sprof @ `335718c2e`

Diagnostic. Driver: `scripts/goal20-profile.sh --seconds 4`.
Friend-MachineD, SBCL 2.6.7, 2026-08-20T11:32:33Z. Not G.17.

## Verdict

Leftover is the octet walker, not EQUAL hash / `PARSE-JSON-SOURCE`.
Top self on `session_load`: **`OCTET-U32-LE` 12.2%**. Callers:
`OCTET-FIND-QUOTE-OR-BACKSLASH` 10.9% self / 27.1% total,
`SWAR-EQ-MSB` 7.1%, `OCTET-FIND-LF` 4.4%, `OCTET-SKIP-JSON-SPACE`
4.4%. `SCAN-KEY` 1.6% self / 16.7% total (mostly the quote scan).

V8 reads `SeqOneByteString` as packed bytes. Lisp encoding:
inline the 4-byte load at the scanners (`%octet-u32-le` +
`octet-u32-le` compiler-macro). Not empty SWAR. Not intern.
Not FFI. Not another object container.

Copy intern (`COPY-UNESCAPED` 2.0%) and `pthread_sigmask` /
foreign `read` stay leftover.

## `session_pipeline.session_load`

```
           Self        Total        Cumul
  Nr  Count     %  Count     %  Count     %    Calls  Function
------------------------------------------------------------------------
   1    120  12.2    120  12.2    120  12.2        -  CADR-AI::OCTET-U32-LE
   2    107  10.9    267  27.1    227  23.0        -  CADR-AGENT::OCTET-FIND-QUOTE-OR-BACKSLASH
   3     70   7.1     70   7.1    297  30.1        -  CADR-AGENT::SWAR-EQ-MSB
   4     66   6.7     89   9.0    363  36.8        -  CADR-AGENT::SWAR-QUOTE-OR-BS-MASK
   5     43   4.4    115  11.7    406  41.2        -  CADR-AGENT::OCTET-FIND-LF
   6     43   4.4    107  10.9    449  45.5        -  CADR-AGENT::OCTET-SKIP-JSON-SPACE
   7     42   4.3    756  76.7    491  49.8        -  CADR-AGENT::PARSE-SESSION-RECORD-OCTETS
  16     16   1.6    165  16.7    721  73.1        -  (LABELS CADR-AGENT::SCAN-KEY :IN CADR-AGENT::PARSE-SESSION-RECORD-OCTETS)
```

## `storage_journal.journal_read`

Same family: `OCTET-U32-LE` 12.2% self; quote-scan 9.9% / 25.3%
total; `SCAN-KEY` 2.1% / 16.3% total.
