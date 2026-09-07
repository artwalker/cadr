# Print one-shot

Print mode lets a user send one prompt, get the model reply on stdout, and exit, without the interactive TUI.

## Sub-features

- `print-no-credentials` refuses to start a run when no provider or model is selected and no API key exists.
- `print-flag-help` still appears on the global `--help` listing as `--print, -p`.

## How to get to it (user POV)

- Run `cadr --print <message>` or `cadr -p <message>` in a terminal.
- Run `cadr --help` and read the `--print, -p` option line (covered in version-and-help; do not skip the no-credentials path here).

## Driving it with control-cadr

Preconditions:

- Isolated HOME has no `auth.json`.
- `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `DEEPSEEK_API_KEY`, and `CADR_API_KEY` are unset.
- No `--provider` or `--model` on the command line.
- `control-cadr doctor` passed.

- **Unauthenticated print.** Send a dummy prompt. Run `CADR_VERIFY_FEATURE=print-oneshot .cursor/skills/verify-cadr/bin/control-cadr cli -- --print ping`. Exit code `1`. `stderr.txt` contains `No API key found for the selected model.` and `Use /login to log into a provider via OAuth or API key.` Stdout is empty.
- **Proof.** `exit.txt` is `1`. This is the user-visible failure for a disposable machine with no keys. A live completion with real credentials is a different path (`verified-unreachable` here unless keys are present and the feature file is extended).

## Gotchas

- The copy is `No API key found for the selected model`, not `No models available`. `--list-models` uses the latter; `--print` uses the former when no provider/model was given.
- Baseline prints this guidance on stderr, not through the red `Error:` CLI wrapper. Assert the plain paragraph.
- Passing `--provider google` changes the failure to that provider's missing-key text. Stay on the no-`--provider` command in this recipe.
- `--offline` does not skip this check. Observing the stderr paragraph is the proof that the run did not reach a provider HTTP call.
- Parent-shell API keys make `--print` succeed. `control-cadr` scrubs them unless `CADR_VERIFY_KEEP_CREDENTIALS=1`.
