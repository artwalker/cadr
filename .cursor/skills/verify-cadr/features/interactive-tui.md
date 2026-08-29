# Interactive TUI

The default cadr UI is a terminal full-screen (or inline) session: a prompt, transcript, and slash commands. A user starts it by running `cadr` with a TTY and leaves with `/quit`.

## Sub-features

- `tui-start` shows the interactive chrome in a real TTY (tmux pane).
- `tui-no-models-notice` surfaces the no-models guidance when nothing is authenticated.
- `tui-quit` exits when the user submits `/quit`.

## How to get to it (user POV)

- Run `cadr` in an interactive terminal (stdin and stdout are TTYs).
- Run `cadr --offline --approve --no-extensions` to skip startup network, trust project files for the run, and skip extension discovery.
- Type `/quit` on the prompt and submit it to leave.

## Driving it with control-cadr

Preconditions:

- `tmux` is on `PATH`.
- Isolated HOME has no credentials.
- `control-cadr doctor` passed.
- No leftover `cadr-verify-*` tmux session from a crashed run (`control-cadr cleanup` first).

- **Start TUI.** Open cadr as a user would, under tmux. Run `CADR_VERIFY_FEATURE=interactive-tui .cursor/skills/verify-cadr/bin/control-cadr tui start`. The helper adds `--session-dir`, `--offline`, `--approve`, `--no-extensions`, and `--no-session`.
- **Observe chrome.** Wait until the pane shows the footer path and model column (startup may print `fd not found. Downloading...` then `fd installed to ...` under isolated HOME). Run `.cursor/skills/verify-cadr/bin/control-cadr tui capture --path .cursor/skills/verify-cadr/artifacts/interactive-tui/pane-before.txt`. The capture contains the banner `cadr v0.2.0` (or the current `version.sexp`), ` / commands `, and, with an empty store, `Warning: No models available` plus `Use /login`.
- **Quit.** Type the quit command. Run `.cursor/skills/verify-cadr/bin/control-cadr tui send --keys '/quit' Enter`. Wait until `.cursor/skills/verify-cadr/bin/control-cadr tui status` reports `dead=1` and `status=0` (cadr accepted `/quit`). Capture `pane-after.txt` if the pane still exists (`remain-on-exit`), then `.cursor/skills/verify-cadr/bin/control-cadr tui stop`.
- **Proof.** `pane-before.txt` exists after cleanup of `.run/` (copy captures under `artifacts/interactive-tui/` before `cleanup`). The session must have been a TTY cadr, not `--print`.

## Gotchas

- Startup in an empty HOME may download `fd` into `$HOME/.cadr/agent/bin/fd`. Wait for that to finish before asserting the prompt; do not treat the download lines as a failed launch.
- The no-models text in the TUI is prefixed with `Warning: `. `--list-models` is not.
- Without a TTY, cadr may take `--mode text` / REPL instead of the TUI. Always start through `control-cadr tui start`, not a raw pipe.
- A trust or login overlay can appear before the prompt. `--approve` skips the project-trust prompt for the run. Login is not required to prove `/quit`.
- `ctrl+c` is `app.clear` / input copy in this product, not a guaranteed process exit. Use `/quit`.
- `scripts/render-diff.py` is a paired-pi screen gate. Passing it does not prove this tmux recipe.
- Do not attach `--slynk` unless you are diagnosing a live image; it is off for users by default.
