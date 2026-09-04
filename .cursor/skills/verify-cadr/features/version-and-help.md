# Version and help

Version and help let a user print cadr's release identity and the CLI usage block without starting a session or contacting a provider.

## Sub-features

- `version-long` prints the release identity on `--version`.
- `version-short` prints the same identity on `-v`.
- `help-long` prints the usage prefix on `--help`.
- `help-short` prints the same usage on `-h`.

## How to get to it (user POV)

- Run `cadr --version` or `cadr -v` in a terminal.
- Run `cadr --help` or `cadr -h` in a terminal.

## Driving it with control-cadr

Preconditions:

- `control-cadr doctor` reports the expected identity.
- Isolated HOME is empty; no `auth.json` is required.

- **Long version.** Ask for the version string. Run `CADR_VERIFY_FEATURE=version-and-help/version .cursor/skills/verify-cadr/bin/control-cadr cli -- --version`. Exit code `0`. `artifacts/version-and-help/version/stdout.txt` is exactly the line from `control-cadr expected-identity` plus a newline. Stderr is empty.
- **Short version.** Run the same helper with `-v` into `CADR_VERIFY_FEATURE=version-and-help/version-short`. Exit code `0` and the same stdout line.
- **Long help.** Run `CADR_VERIFY_FEATURE=version-and-help/help .cursor/skills/verify-cadr/bin/control-cadr cli -- --help`. Exit code `0`. Stdout starts with `cadr - AI coding assistant with read, bash, edit, write tools` and includes the lines `  --help, -h                     Show this help` and `  --version, -v                  Show version number`.
- **Short help.** Run the helper with `-h` into `CADR_VERIFY_FEATURE=version-and-help/help-short`. Exit code `0` and the same usage prefix.
- **Proof.** Keep `command.txt`, `stdout.txt`, `stderr.txt`, and `exit.txt` under both `artifacts/version-and-help/version/` and `artifacts/version-and-help/help/`.

## Gotchas

- `--version` is the identity string, not the contents of `version.sexp` alone. Assert the full `cadr … · aligned with pi …` line.
- Help is written to stdout, not stderr. A pager is not involved.
- Extra wrapper flags from `control-cadr` (`--offline`, `--session-dir`, …) must not change the printed help prefix. If they appear as unknown-option errors, the parse order has drifted.
- Do not treat a matching render-diff banner SHA as this feature.
