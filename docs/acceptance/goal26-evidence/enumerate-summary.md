# Goal 26 enumeration

Measured 2026-09-22.

```sh
python3 scripts/enumerate-baseline-diff.py \
  13cbf77df2396303013a41646bcfa77b4271ae56 \
  16787ad5b2dc748047f314ca1bfe7708f30f54f3
```

Named sets with an empty added and removed list are omitted.

| Class | Delta | Disposition |
|---|---|---|
| extensionEvents | added `agent_before_settle`, `context_with_system` | Implemented. `turn-end-boundary-entries-request-another-provider-turn`, `agent-before-settle-entries-request-another-provider-turn`, `context-handler-omits-system-messages-and-restores-the-request`, `context-with-system-replaces-the-request-prompt` |
| publicApiExportCount | 36 to 36 | No export-count change |
| files | 12 added paths | Three chord source files are in `source-dispositions.tsv`. The other nine are `*.test.ts` and the drift checker excludes them |

```sh
./scripts/check-source-parity-drift.sh --repo . \
  --from 13cbf77df2396303013a41646bcfa77b4271ae56 \
  --to 16787ad5b2dc748047f314ca1bfe7708f30f54f3 \
  --dispositions docs/acceptance/goal26-evidence/source-dispositions.tsv
```
