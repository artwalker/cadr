# Providers

cadr ships the baseline provider set. Each provider authenticates with an
environment variable, a stored credential from `/login`, or a
`models.json` entry — see `docs/custom-provider.md` for the resolution
order.

## Built-in providers

OpenAI (`openai`), Anthropic (`anthropic`), DeepSeek (`deepseek`),
OpenRouter (`openrouter`), xAI (`xai`), GitHub Copilot
(`github-copilot`), Google (`google` / `google-gemini-cli`), Amazon
Bedrock (`amazon-bedrock`), Azure OpenAI, Vertex AI, Cloudflare Workers
AI, Baseten, and the Radius gateway, among others — `cadr --list-models`
shows every model whose provider currently has credentials.

Kimi (`kimi-coding`) remains in the built-in provider registry (OAuth and
catalog aligned with the baseline) but is **not offered** by `/login`.
Stored Kimi credentials still refresh and `/logout`.

## Logging in

`/login` opens the provider selector. Providers with more than one auth
method (subscription OAuth, device code, API key) show a method selector
first; providers with one method go straight to it. OAuth flows render
in the login dialog: browser callback flows show the authorization URL
and accept a pasted redirect URL; device-code flows show the code to
enter. `escape` cancels the flow and aborts the underlying work.
Credentials are stored in `~/.cadr/agent/auth.json` with mode 0600 and
refreshed through the shared auth store. `/logout` removes a stored
credential; environment variables and `models.json` entries are not
modified.

`cadr auth print-api-key` / `cadr auth print-bearer-token` print a
credential on stdout for scripts (`--provider`, `--model`,
`--min-expiry`).

## Errors

A missing credential produces the baseline guidance:
`No API key found for <provider>.` followed by the `/login` pointer and
the docs paths. Provider request failures surface the provider's own
error text; cadr never dumps raw Lisp conditions into the transcript.
