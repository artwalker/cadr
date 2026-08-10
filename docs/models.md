# Models

The model catalog combines the built-in catalog (compiled into the
binary) with custom entries from `~/.cadr/agent/models.json`.

## Listing and selecting

- `cadr --list-models [pattern]` prints the auth-available models as a
  table (provider, model, context, max-out, thinking, images). The
  optional pattern is a fuzzy filter over `provider id`.
- `/model` opens the interactive selector; `ctrl+p`/`ctrl+n` cycle the
  scoped models.
- `--model <id>` and `--provider <name>` pin the startup model.

Only models whose provider has a configured credential are "available".
With no credentials at all, `--list-models` prints the login guidance
and interactive startup shows the first-time setup.

## models.json

See `docs/custom-provider.md` for the provider schema. Top-level shape:

```json
{
  "providers": {
    "deepseek": { "apiKey": "sk-..." },
    "my-provider": { "baseUrl": "...", "models": [ ... ] }
  }
}
```

A parse or schema failure is non-fatal: consumers print
`Warning: errors loading models.json:` followed by the detail and the
file path, and continue with the built-in catalog.

## Thinking levels

Reasoning-capable models expose thinking levels; `ctrl+t` cycles them
and `/settings` shows the current default (`defaultThinkingLevel` in
settings).
