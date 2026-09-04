# Auth help

Auth commands let a user print a provider API key or OAuth bearer token, or check whether a provider is ready, without opening the login TUI. This feature covers the help path only so a verification run never writes secrets into artifacts.

## Sub-features

- `auth-bare` prints auth usage when the user runs `cadr auth` with no subcommand.
- `auth-help-flag` prints the same usage for `cadr auth --help`.

## How to get to it (user POV)

- Run `cadr auth` in a terminal.
- Run `cadr auth --help`, `cadr auth -h`, or `cadr auth help`.
- Global `--help` lists `cadr auth <command>` (see version-and-help).

## Driving it with control-cadr

Preconditions:

- Isolated HOME may be empty. Do not seed `auth.json`.
- `control-cadr doctor` passed.

- **Bare auth.** Ask how to use auth. Run `CADR_VERIFY_FEATURE=auth-help .cursor/skills/verify-cadr/bin/control-cadr cli -- auth`. Exit code `0`. `stdout.txt` starts with `Usage:` and includes `cadr auth print-api-key`, `cadr auth print-bearer-token`, and `cadr auth check`.
- **Help flag.** Run `CADR_VERIFY_FEATURE=auth-help .cursor/skills/verify-cadr/bin/control-cadr cli -- auth --help`. Same copy, exit `0`.
- **Proof.** Artifacts must not contain API keys or bearer tokens. Do not run `print-api-key` or `print-bearer-token` in this feature.

## Gotchas

- `cadr auth check --provider <name>` is a live credential probe. It is not this feature. If you need it, record `verified-unreachable` unless a disposable key is seeded, and never copy the credential into `artifacts/`.
- The default `control-cadr` wrapper does not prepend `--offline` or `--session-dir` before `auth`, because that would not be the auth command.
