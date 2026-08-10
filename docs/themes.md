# Themes

Themes are JSON files that restyle the TUI. cadr ships the baseline dark
and light themes; custom themes load from `~/.cadr/agent/themes/*.json`.

## Selecting a theme

`/theme` opens the theme selector. Choices: the automatic mode (follows
the terminal's reported background), the built-in dark and light themes,
and every custom theme found in the themes directory. The choice persists
in `~/.cadr/agent/settings.json`.

## Theme file format

A theme file is one JSON object with a `name`, a `vars` palette, and a
`colors` mapping that assigns semantic roles (`accent`, `border`,
`success`, `error`, `warning`, `muted`, `dim`, `text`, `selectedBg`,
`userMessageBg`, `toolSuccessBg`, `toolErrorBg`, `mdHeading`, `mdCode`,
...) to hex colors or palette variables. The authoritative shape is the
`vars`/`colors` object used by the bundled themes; a minimal example:

```json
{
  "name": "acme",
  "vars": { "cyan": "#00d7ff", "gray": "#808080" },
  "colors": { "accent": "cyan", "muted": "gray" }
}
```

Unassigned roles fall back to the built-in defaults, so a custom theme
only needs to override what it changes.

## Startup display

Loaded custom themes are listed in the startup resources block under
`[Themes]`. A malformed theme file is reported there as a diagnostic
instead of aborting startup.
