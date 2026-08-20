# Bug — OpenCode Go usage-limit 429: slow UI + different error text vs pi

**Status**: open (user-reported 2026-08-21 screenshot). Not G.17.

> **EXECUTOR: do this first.** Board `[ready · P0 · 现在就做]`.
> Fix `signal-api-error` terminal quota → no retry; align error text with pi.
> Do not start load knife 2 or bash-format until this is `[done]`.


## Symptom

Same model `(opencode-go) mimo-v2.5`, weekly usage limit hit:

| | pi (`~/projects/test`) | cadr (`cadr-migration`) |
|---|---|---|
| Speed | Fails **immediately** | Stays on `Working...` for a long time |
| Text | `Error: 429: {"type":"GoUsageLimitError",...}` | `Error: Weekly usage limit reached. …` (message only, no `429:` / raw JSON) |

## Root cause (advisor)

1. **Slow path** — `src/cadr-ai/transport/http.lisp` `signal-api-error`:
   ```lisp
   (retryable-p (or (= status 429) (member status '(500 502 503 504))))
   ```
   Marks **every** HTTP 429 retryable. Pi checks terminal quota text first
   (`isTerminalRateLimitError` / `GoUsageLimitError` in
   `packages/ai/src/api/openai-codex-responses.ts` and
   `packages/ai/src/utils/retry.ts`) and does **not** retry.
   Cadr then `call-with-provider-retries` sleeps
   `retry-after` (capped 60s) or exponential backoff
   (`*retry-base-delay*` / `*max-provider-retries*` in
   `provider.lisp`). A `Retry-After` of days → up to ~60s × retries of
   silent wait while the TUI shows Working.

2. **Text shape** — `response-error-message` only pulls
   `error.message`. Pi surfaces `429: <raw body>` (see
   `packages/ai/src/utils/error-body.ts`). Assistant-level
   `+non-retryable-assistant-error-fragments+` already lists
   `gousagelimiterror` but that runs **after** HTTP retries if the
   error is raised as `api-error` with `:retryable-p t`.

## Required fix (executor)

1. In `signal-api-error` (and any parallel HTTP 429 classifiers): if
   body/code matches terminal quota
   (`GoUsageLimitError` / `FreeUsageLimitError` / monthly /
   available balance / insufficient_quota / … — same set as
   `retry.lisp` + pi), set `:retryable-p nil`.
2. Align user-visible error with pi where cheap: include status and
   enough body that `GoUsageLimitError` is visible (at least
   `429: <message or compact JSON>`), without dumping secrets.
3. Tests: 429 + GoUsageLimitError body → **zero** sleep/retry;
   transient 429 without those markers still retries.
4. `scripts/test-cl.sh` green. Not G.17. Not load knife work.

## Pointers

- pi: `packages/ai/src/utils/retry.ts`,
  `packages/ai/src/api/openai-codex-responses.ts` `isTerminalRateLimitError`
- cadr: `src/cadr-ai/transport/http.lisp` `signal-api-error`,
  `src/cadr-ai/support/retry.lisp`, `src/cadr-ai/provider.lisp`
  `call-with-provider-retries` / `retry-after-seconds`
- Board `[ready · P0]` for this bug (prefer over load knife 2;
  can run beside bash-format P0 if both open — this one is
  clearer product parity).
