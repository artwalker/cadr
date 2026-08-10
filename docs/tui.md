# TUI

The interactive TUI runs in the alternate screen and is composed of the
transcript, the editor, and the footer. Everything below is reachable
from the default startup state.

## Layout

- Startup banner: version, key hints, and the loaded-resources summary
  (`[Context]`, `[Skills]`, `[Prompts]`, `[Extensions]`, `[Themes]`,
  plus conflict blocks). `ctrl+o` expands the full help; `quietStartup`
  in settings keeps it compact.
- Transcript: user/assistant messages, tool calls with collapsible
  output (`ctrl+o` toggles expansion), thinking blocks.
- Editor: multiline, kill-ring, undo, path completion on `@`, slash
  completion on `/`, `!`/`!!` for shell commands.
- Footer: working directory, context usage, model, thinking level.

## Selectors and dialogs

`/model`, `/session`, `/tree`, `/settings`, `/theme`, `/trust`,
`/login`, `/logout`, `/fork`, `/export`, `/share`, `/name`, `/hotkeys`
open selectors or dialogs. Selectors share one frame: title, optional
filter input, scrollable list, and a footer hint line. `escape` or
`ctrl+c` cancels; cancelling a login flow aborts the underlying OAuth
work and returns to a ready prompt.

## Mouse and scrolling

Mouse wheel scrolls the transcript; text selection works while the
alternate screen is active. `shift+pageup`/`shift+pagedown` scroll by
page.

## Non-interactive modes

`-p/--print` runs one prompt and prints the reply; `--mode json` emits
JSONL events; `--mode rpc` speaks the JSON-RPC protocol on stdio. See
`docs/sdk.md` for embedding.
