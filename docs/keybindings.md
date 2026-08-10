# Keybindings

Keybindings map keys to named actions. The defaults match the pi baseline;
overrides live in `~/.cadr/agent/settings.json` under the `"keybindings"`
key:

```json
{
  "keybindings": {
    "app.thinking.cycle": "ctrl+t",
    "app.session.fork": ["ctrl+shift+f"]
  }
}
```

Each action accepts a single key string or an array of keys. Keys use the
`ctrl+x` / `shift+tab` / `alt+enter` naming; `/hotkeys` prints the
effective bindings grouped by area.

## Action names

Actions are namespaced: `tui.editor.*` (cursor and text editing),
`tui.input.*` (submit, newline, copy), `tui.select.*` (selector
navigation), `app.*` (interrupt, clear, exit, suspend, model and thinking
cycling, tool expansion, session operations), and `app.tree.*` (session
tree). Session actions include `app.session.new`, `app.session.tree`,
`app.session.fork`, `app.session.resume`, `app.session.rename`,
`app.session.delete`, `app.session.deleteNoninvasive`,
`app.session.toggleNamedFilter`, `app.session.togglePath`, and
`app.session.toggleSort` — these four navigation/session actions have no
default key and only fire when bound.

## Legacy names

Flat camelCase names from older configs (`cursorUp`, `selectConfirm`,
`interrupt`, ...) are migrated to their `tui.*`/`app.*` equivalents when
settings load; an explicit modern binding always wins over a migrated
legacy one.

## Extension shortcuts

Extensions register shortcuts with `cadr-agent:define-shortcut`. Keys
reserved for core actions (interrupt, exit, select confirm/cancel, ...)
cannot be taken over — the binding is skipped with a startup warning;
other collisions resolve in the extension's favor with a warning in the
startup `[Extension issues]` block.
