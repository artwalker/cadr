# Extensions

cadr extensions are Common Lisp files loaded at startup. They register
commands, tools, event hooks, shortcuts, providers, renderers, and prompt
templates through the `cadr-agent` extension API.

## Locations

- Global: `~/.cadr/agent/extensions/` — every `.lisp` file directly in the
  directory, plus any subdirectory containing an `extension.lisp`.
- Project: `.cadr/extensions/` inside the project root — loaded only when
  the project is trusted (see `/trust`).
- Packages: extensions installed with `cadr install` are listed in
  `settings.json` under `"packages"`; see `docs/packages.md`.

Loading order is deterministic: project entries rank before global ones,
sorted by path within each scope.

## Writing an extension

An extension file is evaluated once at load. Registrations use macros from
the `cadr-agent` package:

```lisp
(cadr-agent:define-command
 "hello"
 :description "Greet from the extension"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   ;; context carries the session/UI bridge
   "ok"))

(cadr-agent:define-event-hook :session-start
  :handler (lambda (event) ...))
```

Registration forms:

| Macro | Purpose |
|---|---|
| `define-command` | `/name` slash command |
| `define-event-hook` | one of the 34 extension events (`:session-start`, `:tool-call-before`, ...) |
| `define-tool` / `define-rich-tool` | model-callable tool |
| `define-shortcut` | key shortcut (`ctrl+...`) |
| `define-flag` | `--flag` CLI flag |
| `define-prompt-template` | reusable prompt template |
| `define-provider` / `define-native-provider` | model provider |
| `define-message-renderer` / `define-entry-renderer` / `define-tool-renderer` | custom rendering |
| `define-markdown-transformer` | markdown preprocessing |

Shortcut keys compete with the built-in keybindings: keys reserved for
core actions are skipped with a warning, other collisions resolve to the
extension, and two extensions bound to the same key resolve to the later
registration. Conflicts are listed in the startup `[Extension issues]`
block.

## Failure behavior

An extension that fails to load is fatal at startup: cadr prints
`Error: Failed to load extension "<path>": ...` and
`Hint: Start without extensions using "cadr -ne".`, then exits 1. Use
`cadr -ne` (or `--no-extensions`) to start without any extensions.

## Reloading

`/reload` re-reads settings, keybindings, extensions, skills, prompt
templates, themes, and context files without restarting. A load failure
on reload keeps the last good extension set.

## Examples

`examples/extensions/` contains runnable fixtures (commands, hooks,
custom tools, renderers, providers). The index is
`examples/manifest.sexp`.
