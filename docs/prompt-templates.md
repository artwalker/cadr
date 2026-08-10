# Prompt Templates

Prompt templates are reusable markdown prompts invoked as slash commands.

## Locations

- Global: `~/.cadr/agent/prompts/<name>.md`
- Project: `.cadr/prompts/<name>.md` (requires a trusted project)
- Extra paths can be passed with `--prompt-templates <path>`.

`commands/` directories from older layouts are renamed to `prompts/`
automatically at startup.

## Use

A file `review.md` becomes `/review`. The file body is expanded as the
prompt; command arguments are appended to the expanded text. Loaded
templates are listed in the startup resources block under `[Prompts]`.

When a project template and a global template share a name, the project
one wins and the collision is reported in the startup conflicts block.

Extensions can register templates programmatically with
`cadr-agent:define-prompt-template`; see `docs/extensions.md`.
