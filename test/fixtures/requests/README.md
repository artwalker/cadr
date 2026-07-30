# Request payload provenance

The six JSON files are generated from
[`earendil-works/pi`](https://github.com/earendil-works/pi) commit
`71efc6f0c1909874ec8c944637a9ae7fc0e2d508` with the same system prompt,
user message, tool, model IDs, and 4096-token limit used by the Common Lisp
test.

From this repository, with dependencies installed in the pinned reference
checkout:

```bash
npx tsx scripts/export-ts-payloads.ts \
  --reference /path/to/earendil-works-pi \
  --output test/fixtures/requests
```

The exporter uses each provider's public payload hook before transport. Google
SDK parameters are deterministically converted to their equivalent REST body.
The `*-complete.json` files differ only where the non-streaming REST protocol
requires `stream: false`; the fixed TS reference exposes its unified complete
operation by collecting the streaming implementation.
