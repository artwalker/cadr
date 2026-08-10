# Custom Providers

Custom OpenAI/Anthropic-compatible endpoints are declared in
`~/.cadr/agent/models.json` under `"providers"`:

```json
{
  "providers": {
    "my-provider": {
      "baseUrl": "https://api.example.com/v1",
      "apiKey": "sk-...",
      "api": "openai-completions",
      "models": [
        {
          "id": "my-model",
          "name": "My Model",
          "contextWindow": 128000,
          "maxTokens": 8192,
          "reasoning": false,
          "input": ["text"]
        }
      ]
    }
  }
}
```

Fields per provider:

- `baseUrl` — endpoint root.
- `apiKey` — static key (prefer the environment or `/login` for real
  secrets; see below).
- `api` — wire dialect, e.g. `openai-completions`, `anthropic-messages`.
- `headers` — optional extra request headers.
- `models` — model entries with `id`, optional `name`, `contextWindow`,
  `maxTokens`, `reasoning`, and `input` (`["text"]` or
  `["text","image"]`).

## Auth precedence

A request credential resolves in order: `--api-key`, `models.json`
`apiKey`, a stored OAuth credential, then a stored API key. Environment
variables such as `OPENAI_API_KEY` are honored for the built-in
providers. `/login` stores credentials in `~/.cadr/agent/auth.json`
(mode 0600); `/logout` removes them.

## Errors

A malformed `models.json` does not abort startup: commands that need the
model list print
`Warning: errors loading models.json:` with the parse detail and file
path, then continue with the built-in catalog.

Extensions can register full providers (custom auth flows, native
implementations) with `cadr-agent:define-provider`; see
`docs/extensions.md`.
