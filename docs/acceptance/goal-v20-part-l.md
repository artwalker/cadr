# Goal 20 Part L — reverse visible strings

Date: 2026-08-13.

## Gate-validity proof

| Defect | How the new gate catches it without the fix | Lock |
|---|---|---|
| xAI login prints "no default model is configured" | `classify-post-login-model` on `:xai` + empty snapshot must be `:no-models-available`. The literal `no models are available for that provider` must be live in `login-selection.lisp`. | FiveAM `goal20-l-xai-*`; `baseline-string-reachability.py` |
| Bare `NIL` after `/snake` Q | `extension-render-value-lines` of `NIL` / a plist must not yield the token `NIL`. | FiveAM `goal20-l-custom-entry-*`; `cadr-visible-output-origin.py` |

Parking the missing sentence in a `defparameter` fails reachability (comment-stripped search). Filtering `NIL` in the PTY harness is not this gate.

## Fixes

- `src/cadr-cli/models/login-selection.lisp` — four baseline branches.
- `src/cadr-cli/interactive/extension-ui.lisp` — no renderer ⇒ invisible (pi `interactive-mode.ts:3432`), no `princ-to-string` of Lisp values.

## Runtime evidence (N2 / N2.5)

Load-and-probe, no credentials, no token print:

```
(cadr-ai:provider-definition-default-model (cadr-ai:find-provider-definition :xai))
→ "grok-4.5"
(cadr-cli:classify-post-login-model :xai '())
→ NIL, :NO-MODELS-AVAILABLE
```

That is why login walked the unconfigured string: the snapshot after login had zero xAI models, and cadr collapsed that into `:no-default-model`. slynk is the same query against a live agent; the classifier is the lock.

## Anti-arbitrage

- Producer is `post-login-selection-error` called from the classifier, not a constant pool.
- NIL fix is in the transcript renderer, not the capture filter.
- No batch "cadr-only" dump.
