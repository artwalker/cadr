---
name: verify-cadr
description: "Drive cadr (native SBCL CLI/TUI coding agent) like a user: isolated HOME, control-cadr, CLI flags and tmux TUI. Use when proving a cadr change, checking --help/--version/--print/list/auth, or verifying interactive chrome."
---

# Verify cadr

cadr is a Common Lisp (SBCL) reimplementation of the pi coding agent. The primary user surface is the `./cadr` process: interactive TUI by default, plus non-interactive `--print` / `--mode text|json|rpc`, package commands (`install`/`list`/`config`/`auth`), and `--list-models`. Optional `./cadr-server` is out of scope for this map unless a feature file names it.

This skill is for agents. Follow the feature map under `features/`. Do not drive the operator's real `~/.cadr`. Runtime environment is `CADR_*` only; never set `PI_*` as a fallback.

## Launch

cadr is a short-lived CLI/TUI, not a long-running HTTP server. Launch means dump `./cadr` once, then start each drive in an isolated HOME (and tmux for TUI).

1. From the repository root, ensure Quicklisp can see `slynk/mrepl` (required by `build.lisp`). If `asdf:find-system` fails, install the audited snapshot into Quicklisp `local-projects`:

```sh
QL_ROOT="$(dirname "${QUICKLISP_SETUP:-$HOME/quicklisp/setup.lisp}")"
mkdir -p "$QL_ROOT/local-projects"
curl -fL --retry 4 --retry-delay 4 \
  -o /tmp/sly-20260101-git.tgz \
  https://beta.quicklisp.org/archive/sly/2026-01-01/sly-20260101-git.tgz
tar -xzf /tmp/sly-20260101-git.tgz -C "$QL_ROOT/local-projects"
```

`.cursor/install.sh` performs the same prefetch on Cloud Agent bootstrap.

2. Build the native image. Skip `test-cl.sh` only when that suite is already known blocked in this environment (missing contribs); the binary dump itself does not need the FiveAM run:

```sh
CADR_BUILD_SKIP_TEST_CL=1 QUICKLISP_SETUP="${QUICKLISP_SETUP:-$HOME/quicklisp/setup.lisp}" ./build.sh
```

Ready means `test -x ./cadr`. There is no port and no "listening" log for CLI drives.

3. Start an isolated verification run (creates disposable HOME and session dir; does not start cadr yet):

```sh
.cursor/skills/verify-cadr/bin/control-cadr init
.cursor/skills/verify-cadr/bin/control-cadr doctor
```

Teardown is `control-cadr cleanup` (see Cleanup). Never `pkill -f cadr`.

## Doctor

Read-only check that this run is worth driving. Run it after `init`, before the first drive, after any failed drive, and on every fresh CLI/TUI session:

```sh
.cursor/skills/verify-cadr/bin/control-cadr doctor
```

Require all of:

- `./cadr` exists and is executable (or `CADR_VERIFY_BIN` points at one).
- `cadr --version` (no extra flags) prints exactly `control-cadr expected-identity`, which is `cadr <version.sexp> · aligned with pi <BASELINE tag> (+<distance>, <9-char BASELINE sha>)`.
- Isolated HOME is `.cursor/skills/verify-cadr/.run/home` (or `$CADR_VERIFY_STATE/home`), not the login home.

If doctor fails because the binary is missing, rebuild. If identity mismatches, you are driving the wrong tree or an stale image — rebuild; do not continue.

## Drive

Put `control-cadr` on `PATH` or invoke it by repo-relative path. Feature recipes set `CADR_VERIFY_FEATURE` so evidence lands under `artifacts/<feature-id>/`.

CLI: for flags such as `--version` / `--help` / `--list-models` / `--print`, the helper prepends `--session-dir`, `--offline`, `--approve`, and `--no-extensions`. Package commands (`list`, `auth`, `install`, …) must be `argv[0]`; the helper does not prepend those flags, because `cadr --offline list` is parsed as a prompt, not as `list`. Isolated `HOME` still applies. `CADR_VERIFY_RAW=1` disables prepended flags for every command.

```sh
CADR_VERIFY_FEATURE=version-and-help \
  .cursor/skills/verify-cadr/bin/control-cadr cli -- --version
```

`--version` and `--help` ignore the extra flags. For a command whose contract is "bare argv only", set `CADR_VERIFY_RAW=1` (still uses isolated `HOME`).

Stable handles are CLI flags and copy from `src/cadr-cli/arguments.lisp` (`+cli-usage-prefix+`), not pixel coordinates:

- `--help` / `-h` — usage beginning `cadr - AI coding assistant with read, bash, edit, write tools`
- `--version` / `-v` — `cadr-release-identity`
- `--list-models` — catalog table, or `No models available. Use /login...`
- `list` — installed packages, or `No packages installed.`
- `--print` / `-p` — one-shot prompt; with no credentials, stderr `No API key found for the selected model.` and exit `1`
- `auth` / `auth --help` — auth usage (`print-api-key`, `print-bearer-token`, `check`)
- Interactive TUI — default when stdin/stdout are TTYs; slash command `/quit` exits

TUI (tmux session named `cadr-verify-<run-id>`, pane pid recorded; kill that session only):

```sh
CADR_VERIFY_FEATURE=interactive-tui \
  .cursor/skills/verify-cadr/bin/control-cadr tui start
# wait until capture shows the product UI or the no-models notice
.cursor/skills/verify-cadr/bin/control-cadr tui capture --path \
  .cursor/skills/verify-cadr/artifacts/interactive-tui/pane-before.txt
.cursor/skills/verify-cadr/bin/control-cadr tui send --keys '/quit' Enter
.cursor/skills/verify-cadr/bin/control-cadr tui status
.cursor/skills/verify-cadr/bin/control-cadr tui stop
```

Do not use `scripts/render-diff.py` as the user-POV driver. That gate is baseline screen parity, not this feature map.

## Evidence

Default proof directory (survives cleanup):

`.cursor/skills/verify-cadr/artifacts/`

Override with `CADR_VERIFY_EVIDENCE`. Cloud walkthrough copies may also go under `/opt/cursor/artifacts/`; those are extra, not a substitute for the skill path.

CLI proof for every drive:

- `artifacts/<feature>/command.txt` — cwd, binary, HOME, exact argv
- `artifacts/<feature>/stdout.txt`
- `artifacts/<feature>/stderr.txt`
- `artifacts/<feature>/exit.txt` — integer status

TUI proof: `pane-before.txt` / `pane-after.txt` from `tui capture`, plus the CLI files if you also ran a flag.

Standards:

- Exercise the real `./cadr` user path. Do not call Lisp functions or FiveAM helpers as a substitute for `--help` / `--print` / TUI.
- Capture the command and the resulting streams, not only a final screenshot.
- Isolated HOME must stay empty of operator `auth.json` unless the feature file seeds credentials. Do not paste keys into evidence.
- `--offline` is startup-network suppression (`CADR_OFFLINE=1` equivalent), not a mock of providers. `--print` with no keys still talks to no network if it exits on the auth-guidance path; confirm by the stderr copy, not by the flag name.
- A green render-diff SHA is not proof of a mapped feature.

## Cleanup

```sh
.cursor/skills/verify-cadr/bin/control-cadr cleanup
```

Stops the tmux session recorded in `.run/tmux-session` (and TERM the pane pid if it survived), then deletes `.cursor/skills/verify-cadr/.run/` (HOME and sessions). It does not delete `artifacts/`. After cleanup, `ls` the feature's evidence files and confirm they still exist.

Never kill by process name. If you started extra tmux sessions besides `control-cadr tui start`, kill those sessions by the name you created.

## Helpers

`bin/control-cadr` is executable. From the repository root:

```sh
.cursor/skills/verify-cadr/bin/control-cadr root
.cursor/skills/verify-cadr/bin/control-cadr init
.cursor/skills/verify-cadr/bin/control-cadr doctor
.cursor/skills/verify-cadr/bin/control-cadr expected-identity
CADR_VERIFY_FEATURE=version-and-help/help \
  .cursor/skills/verify-cadr/bin/control-cadr cli -- --help
.cursor/skills/verify-cadr/bin/control-cadr cleanup
```

`root` prints the repository root (four path segments up from `bin/`). `cli --` always records evidence under `CADR_VERIFY_FEATURE`. `tui start|capture|send|stop` owns one tmux session per run id.

## Feature map

Read `features/README.md`, then the file for the surface you are proving. Covering `--version` alone is not coverage of `list` or `--print`.
