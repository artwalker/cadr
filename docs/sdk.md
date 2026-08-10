# SDK

cadr can be embedded as a library. The SDK surface lives in the
`cadr-cli` system under `src/cadr-cli/sdk/` and mirrors the baseline's
agent-session architecture: a session wraps an agent loop with a model
provider, tools, resources, and an extension host.

## Pieces

- `agent-session` / `agent-session-services`: construct a session from a
  provider config, model, tools, and settings.
- `session-manager`: create, fork, resume, and navigate sessions on disk
  (`~/.cadr/agent/sessions/`).
- `sdk-model-runtime`: model catalog and availability (built-in catalog
  plus `models.json`).
- `sdk-resource-loader` / `sdk-settings-manager`: resources (skills,
  prompts, themes, context files) and layered settings.
- `cache-version`: session cache compatibility checks.

## Headless modes

For process integration prefer the stable wire surfaces over library
internals:

- `cadr -p "prompt"` — print mode, final text on stdout.
- `cadr --mode json` — one JSON event per line.
- `cadr --mode rpc` — JSON-RPC over stdio (`new_session`, `prompt`,
  `command`, tree navigation, ...).

`examples/sdk/` contains a minimal embedding.

## Extensions vs SDK

To extend an interactive cadr, write an extension (see
`docs/extensions.md`). To drive cadr from another program, use print,
json, or rpc mode. The SDK classes are for embedding the agent loop
inside another Lisp process.
