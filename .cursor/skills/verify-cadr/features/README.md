# cadr verification map

This directory is the maintained source for verifying user-facing cadr behavior. Read this index before driving the app, then use the matching feature file as the recipe.

## Baseline preconditions

- Work from the repository root that contains `./cadr` (or set `CADR_VERIFY_BIN`).
- Run `.cursor/skills/verify-cadr/bin/control-cadr init` so HOME is `.cursor/skills/verify-cadr/.run/home` and sessions are `.cursor/skills/verify-cadr/.run/sessions`.
- Run `control-cadr doctor` and require the identity string from `control-cadr expected-identity`.
- Leave provider environment variables unset unless a feature file seeds them. Runtime is `CADR_*` only. `control-cadr` scrubs common `*_API_KEY` values from the parent shell unless `CADR_VERIFY_KEEP_CREDENTIALS=1`.
- Never drive a cadr that was already running under the login HOME.
- Put `control-cadr` on `PATH` or invoke the repo-relative path shown in each recipe.

## Driving conventions

- Start every recipe from the isolated HOME created by `init` unless the feature lists extra seed files.
- Treat every command as literal. Keep flags and slash commands unchanged.
- Run flag and package commands through `control-cadr cli --`.
- Run the interactive TUI through `control-cadr tui start|capture|send|stop`.
- Do not use `scripts/render-diff.py` as a stand-in for these recipes.
- Cleanup may delete `.run/`; it must not delete `artifacts/`.

## Proof and skip reporting

- CLI proof includes command, stdout, stderr, and exit code files under `artifacts/<feature>/`.
- TUI proof includes tmux pane captures from before and after the user action.
- Record the feature ID in `CADR_VERIFY_FEATURE` so artifacts are not mixed.
- Report an unreachable path with the attempted command and the unmet precondition (credentials, TTY, tmux).
- Do not report a skipped entry point as verified through a different path.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then uses exactly four H2 sections in this order.

1. `Sub-features` lists short IDs with one line for each behavior.
2. `How to get to it (user POV)` lists every user entry point.
3. `Driving it with control-cadr` starts with `Preconditions:` and uses labeled bullets that pair each user action with an exact command and observable result.
4. `Gotchas` lists traps that can waste or invalidate a verification run.

Keep implementation details out of the map. Name only user paths, stable handles, required state, commands, and observable proof.

## Features

- [Version and help](./version-and-help.md) covers `--version` / `-v` and `--help` / `-h` copy.
- [List models](./list-models.md) covers `--list-models` with an empty credential store.
- [List packages](./list-packages.md) covers `cadr list` with no extensions installed.
- [Print one-shot](./print-oneshot.md) covers `--print` without provider credentials.
- [Auth help](./auth-help.md) covers `cadr auth` usage without printing secrets.
- [Interactive TUI](./interactive-tui.md) covers launching the default TUI in tmux and leaving with `/quit`.
