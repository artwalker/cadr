# Phase 5 progress: provider completion and OAuth

## Completed

- Provider registry for Anthropic, OpenAI, Google, DeepSeek, and Ollama with
  protocol reuse, key policy, defaults, capabilities, and base URL overrides.
- OpenAI Chat Completions adapter with non-streaming and SSE reasoning/text/tool
  aggregation, usage, cost, and recorded DeepSeek E2E.
- Native image content conversion for all four wire protocols and explicit
  rejection by unsupported models.
- Generated static model catalog with Gemini 3.6 Flash and current DeepSeek V4
  defaults; deterministic public-data refresh script.
- Pure Lisp PKCE SHA-256/base64url, one-shot loopback callback server, exact
  fixed-reference OpenAI Codex OAuth URL/token/request contract, atomic 0600
  auth storage, locked refresh, redaction, `/login`, and `/logout`.
- Anthropic subscription OAuth mirrors the fixed reference API but is marked
  unverified in code output and README.

## Verification

```bash
./scripts/test-cl.sh
```

Result: 355 checks passed (`pi-ai` 223, `pi-agent` 40, `pi-cli` 92).

```bash
./build.sh
./pi-cl --help
./scripts/live-deepseek-smoke.sh
npm run check
```

Result: the SBCL 2.6.7 no-compression fallback produced a native image;
`--base-url` is present; real DeepSeek V4 Flash Chat Completions streaming
returned the exact smoke token; the repository check completed without
warnings.

## External gate

`~/.pi-cl/auth.json` is absent in the audit environment. The real ChatGPT
`/login openai` and `scripts/live-openai-oauth-smoke.sh` therefore remain an
account-owner verification, not a claimed pass. The recorded refresh-to-request
test, RFC PKCE vector, loopback parser, 0600 check, concurrency test, and exact
Codex header test are green. Anthropic OAuth remains explicitly unverified.

## Differences and next phase

- Subscription OAuth terms risk is documented in README.
- The line REPL has no image attachment picker even though the message/protocol
  layer supports images.
- Phase 6 upgrades linear sessions to a traceable tree with migration,
  compaction, resume, switching, and HTML export.
