# Packages

cadr packages are resource bundles (extensions, skills, prompt
templates, themes) installed from git URLs or local paths.

## Commands

```
cadr install <source> [-l] [--approve|--no-approve]
cadr remove <source> [-l] [--approve|--no-approve]
cadr list [-l]
cadr update [--self|--extensions|--models|--all] [--extension <source>] [--force]
cadr config [-l] [--approve|--no-approve]
```

- `<source>` is a git URL or a local directory containing the package
  resources.
- `-l` / `--local` writes the project config (`.cadr/settings.json`)
  instead of the global one; project config changes require a trusted
  project or `--approve`.
- `cadr update --self` updates the cadr installation itself;
  `--extensions` updates installed packages; `--models` refreshes model
  catalogs (cadr's catalog is bundled with the binary, so this reports
  that state).
- `--offline` (or `CADR_OFFLINE=1`) skips all network access.

Installed packages are recorded in `settings.json` under `"packages"`.
Background update checks run at startup when online; their findings
appear as a dim notice.

## Trust

Project-level package and resource config is gated by project trust:
untrusted projects print
`Project is not trusted. Use --approve to modify local resource config.`
See `/trust` in the TUI.
