# Goal 20 Part N — live `--slynk` proof of the xAI no-models trigger

Not load-and-probe. Not a restatement of
`docs/acceptance/goal-v20-part-n.md` N2.5. The queries below ran
inside a running `./cadr --slynk` process.

## Vehicle

tmux session `g3-cadr`, 100×40. Isolated HOME and cwd
(`/tmp/grok-goal-4cbb600f2c5d/implementer/g3-isolate`) so the
repo-root trust prompt does not hide the TUI. Image was a copy of
the existing `./cadr` (no rebuild). API-key env vars unset.
`--no-session`. Port **47005**.

```
./cadr --slynk 47005 --no-session
;; Slynk started at port: 47005.
```

`ss` showed `127.0.0.1:47005`. The TUI printed
`Warning: No models available`. Session torn down after the
eval; isolate discarded.

Client: scratch SBCL + `slynk-rpc` (`EVAL-AND-GRAB-OUTPUT`), the
same RPC the FiveAM remote-repl suite uses. Eval happens in the
cadr image. Credentials did not appear (agent print used
`[REDACTED]`).

## Chain, as returned

| form | live result |
|---|---|
| `(cadr-cli:active-agent)` | `:OK` — non-nil `#S(CADR-AGENT:AGENT …)` bound in that process |
| `(cadr-ai:provider-definition-default-model (cadr-ai:find-provider-definition :xai))` | `"grok-4.5"` |
| `(multiple-value-list (cadr-cli:classify-post-login-model :xai '()))` | `(NIL :NO-MODELS-AVAILABLE NIL)` |
| `(cadr-cli:post-login-selection-error "Logged in to" "xAI" :xai :no-models-available nil)` | `Logged in to xAI, but no models are available for that provider. Use /model to select a model.` |

Empty available-models is the post-login snapshot, not a missing
default: xAI still has `grok-4.5`, so the kind is
`:no-models-available`, not `:no-default-model`.

This is the L0 trigger. It is not a Slynk-guidance policy note
and it does not claim Goal 20 or Part G passed.
