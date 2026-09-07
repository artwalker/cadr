# List packages

List packages lets a user see which extension sources are installed in user or project settings, without opening the config TUI.

## Sub-features

- `list-empty` prints that no packages are installed when settings list none.
- `list-help` prints the `list` command usage.

## How to get to it (user POV)

- Run `cadr list` in a terminal.
- Run `cadr list --help` or `cadr list -h` for command help.

## Driving it with control-cadr

Preconditions:

- Isolated HOME has no user settings packages.
- The repository checkout is not treated as a project with extra packages, or pass `--no-approve` on the `list` argv if `cwd/.cadr/settings.json` appears. Package commands are `argv[0]`; `control-cadr` does **not** prepend `--approve` / `--offline` / `--session-dir` for `list` (see SKILL.md).
- `control-cadr doctor` passed.

- **Empty list.** Ask which packages are installed. Run `CADR_VERIFY_FEATURE=list-packages .cursor/skills/verify-cadr/bin/control-cadr cli -- list`. Exit code `0`. `stdout.txt` is `No packages installed.` plus a newline.
- **Command help.** Run `CADR_VERIFY_FEATURE=list-packages .cursor/skills/verify-cadr/bin/control-cadr cli -- list --help`. Exit code `0`. Stdout includes `list [--approve|--no-approve]` and `List installed packages from user and project settings.`
- **Proof.** Keep both evidence directories' files if you overwrite the same feature folder; prefer running help last only after saving empty-list stdout, or use two feature IDs. Default: run empty list last so `artifacts/list-packages/stdout.txt` holds `No packages installed.`

## Gotchas

- `list` is a command, not `--list`. `--list-models` is a different feature.
- Do not put global flags before `list`. `cadr --approve list` is not the list command.
- Project-local settings under `.cadr/` in the repo can add packages even with an empty HOME. If stdout is not the empty sentence, report the extra sources; do not rewrite the map to match a contaminated checkout.
