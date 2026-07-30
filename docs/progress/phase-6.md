# Phase 6 progress: tree sessions and compaction

## Completed

- Append-only JSONL v2 session tree with unique entry IDs, parent links,
  arbitrary historical branch points, and active context rebuilt from the
  selected root-to-leaf path.
- Automatic v1-to-v2 migration using a same-directory temporary file and
  atomic replacement while preserving unknown header/envelope fields.
- Strict duplicate, dangling/forward-parent, compaction-reference, and
  corruption validation; incomplete final writes remain recoverable.
- Threshold compaction through the current provider/model, explicit source
  references, retained full history, and context projection to summary plus
  recent suffix.
- One-shot recovery from provider-reported context overflow. The error remains
  a historical branch; the retry uses the compacted branch and cannot loop.
- Session list, in-process switch, arbitrary branch, exact `--resume`, manual
  `/compact`, and escaped full-tree HTML export.
- Session persistence for Phase 5 image content.

## Verification

```bash
./scripts/test-cl.sh
```

Result: 427 checks passed (`pi-ai` 223, `pi-agent` 98, `pi-cli` 106).

```bash
./build.sh
./pi-cl --help
./scripts/acceptance-smoke.sh
./scripts/live-deepseek-smoke.sh
npm run check
```

Result: SBCL 2.6.7 used the documented uncompressed fallback and produced the
native executable; help exposes `--resume`; separate native processes reused
one file through `--continue` and exact `--resume`; DeepSeek V4 Flash streaming
passed; the repository check completed without warnings.

## Acceptance mapping

- Two branches are independently reconstructed after reload and can each
  receive new descendants.
- Threshold and explicit provider-overflow paths both compact and continue.
- Every compaction retains `sourceIds` and `firstKeptEntryId`; original nodes
  remain byte-visible in JSONL and full-tree HTML.
- v1 semantic data plus unknown envelope fields survive migration.

## External gate and next phase

The Phase 5 real ChatGPT OAuth account smoke remains pending because no
account-owned `~/.pi-cl/auth.json` is available. It is not counted as passed.

Phase 7 is deliberately not implemented. Its stable Lisp extension API must be
reviewed and confirmed by a human before coding begins.
