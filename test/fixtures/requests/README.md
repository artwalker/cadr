# Request payload provenance

The 24 JSON request fixtures are generated from
[`earendil-works/pi`](https://github.com/earendil-works/pi) commit
`914cf1472e715297caa30db4b9535d534a9eb718` with the same system prompt,
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

The exporter also writes the Wave 1 catalog fixture to the sibling
`test/fixtures/catalogs/` directory. Catalog generation reads live upstream
metadata and therefore requires an explicit diff review; it must not silently
replace the pinned catalog when only external metadata has drifted.
