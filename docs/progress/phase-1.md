# Phase 1 progress: pi-ai

## Completed

- Unified message/content/tool/usage/stream-event data model and condition
  hierarchy.
- Anthropic Messages, OpenAI Responses, and Google Generative Language request
  conversion.
- True JSON non-streaming HTTP and incremental SSE streaming HTTP.
- Provider SSE reducers, response parsing, token usage, stop reasons, errors,
  cross-provider history cleanup, orphaned tool results, and abort termination.
- Exact request payload fixtures exported from the pinned TypeScript baseline.
- Raw live SSE replay for Anthropic, OpenAI, and Gemini 3.6 Flash.
- SSE transport explicitly sends `read-timeout = NIL`; its delayed-stream
  regression test passes.

## Verification

```bash
npx tsx scripts/export-ts-payloads.ts \
  --reference /tmp/pi-earendil-ref-019fb0b2 \
  --output /tmp/pi-cl-payloads-wrapper
diff -ru test/fixtures/requests /tmp/pi-cl-payloads-wrapper
```

Result: no diff.

```bash
/root/.local/bin/sbcl --noinform --non-interactive \
  --load /root/quicklisp/setup.lisp \
  --eval '(asdf:load-asd (truename "pi-ai.asd"))' \
  --eval '(asdf:test-system "pi-ai" :force t)'
```

Result before this report: 117 checks, 117 passed after implementation. The
final all-system run supersedes this intermediate count.

## Intentional differences from the fixed TypeScript baseline

- The Common Lisp `complete-chat` sends a real non-streaming REST request;
  upstream `complete()` collects a streaming response. This is required by
  `goal.md`.
- Google defaults to the now-current stable `gemini-3.6-flash`. Its deprecated
  `temperature`, `top_p`, and `top_k` fields are omitted for that model even
  though the older fixed reference can still construct `temperature`.
- First-version content is text, thinking, and function tools only. Image,
  OAuth, provider proxy, and model-catalog behavior remains out of scope.

## Next

Phase 2 implements the agent event lifecycle, schema validation, controlled
tool batches, and the complete model-tool-model loop using a faux provider.
