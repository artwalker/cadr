# Goal 20 Part K7 — cadr-ai

61 Lisp files / 26,357 lines at start. Generated
`models.generated.lisp` / `image-models.generated.lisp` untouched.

## keep

All §2.2 no-rewrite files kept. I reasons still match:
wire tokens, generated catalogs, RFC/byte-locked loops,
`define-provider-constructor` as the existing compile-time DSL.

agy Flash flagged `oauth/providers/github-copilot.lisp` and
`websocket.lisp` as drifted. Independent check: Copilot still
delegates poll to `oauth-poll-token`; websocket still owns
`json-value-equal-p` at :405. Discarded.

## 28 needs-rewrite

| File | I0 |
|---|---|
| auth | `+oauth-reserved-credential-keys+` |
| oauth/callback | `oauth-callback-provider-key` |
| oauth/openai-anthropic | `login-pkce-browser-oauth` |
| oauth/page | same provider key |
| oauth/providers/radius | `parse-device-authorization` |
| auth/bedrock | destructuring-bind ARN |
| auth/device-code | `parse-device-authorization` |
| auth/github-copilot | same parser |
| auth/radius-cloudflare | `+radius-oauth-client-id+` / scope |
| providers/anthropic | pop, not nth |
| providers/google | `google-gemini-3-model-p` |
| providers/azure-openai | `&rest` / `apply` |
| providers/bedrock | `bedrock-sigv4-headers` |
| providers/mistral | `affinity-p` |
| providers/pi-messages | block in `block-indices` |
| providers/openai-completions | `(index . block)` |
| providers/openai | `(index . block)` |
| providers/definitions | MOP row keys |
| providers/runtime-projection | strategy table |
| runtime/faux-provider | `faux-stream-block` |
| runtime/models | `call-with-models-runtime-error` |
| support/retry | `aborted-message` |
| transport/http | `parsed-url-authority` + `signal-http-timeout` |
| types | defstruct constructor |
| capabilities/event-stream | queue tail |
| capabilities/grammar-tools | `keyed-collection-value` |
| crash | SBCL-only boundary |
| model-data | `walk-model-data-groups` |

## K0.2 macros

One macro in `src/cadr-ai/`: `define-provider-constructor` in
`provider.lisp`. It is a constructor DSL with compile-time class
binding. Expressiveness stops there because the rest of the package
is protocol methods and wire parsers, not an authoring surface.

`definitions.lisp` stayed needs-rewrite for the 22 hand-copied slot
names. K7 derives those from MOP. That is not a second constructor
macro; it is the existing class owning its own keys.

A new `with-models-runtime-error` macro was not added. The wrap is a
function: the body is a thunk, not a new defining form.

## Pairing

Several AI files have H cells. Req 8 Date.now() is not used.
Existing cadr-ai FiveAM is the before/after.

Blocked: 0. FiveAM 18748 → 18768. derive 680/680 expected.
N_i untouched.

## H class

Booked class from tip `docs/benchmarks/goal20-unpaired-paths.json` via
`scripts/goal20-unpaired-paths.py` (longest prefix). Refreshed 2026-09-07
against denom 297 / 133658 (`needs-pair=0`, `pairable-uncovered=0`).
Not 148 wall-clock pairs. Historical K-booking `pairable-uncovered` /
`pending H pair` sentences are superseded by this list.

- `paired` (52): `auth.lisp`, `auth/bedrock.lisp`, `auth/device-code.lisp`, `auth/github-copilot.lisp`, `auth/radius-cloudflare.lisp`, `auth/vertex.lisp`, `capabilities/event-stream.lisp`, `capabilities/grammar-tools.lisp`, `capabilities/image-runtime.lisp`, `capabilities/proxy-config.lisp`, `capabilities/session-resources.lisp`, `capabilities/streaming-json.lisp`, `crypto.lisp`, `image-models.generated.lisp`, `images.lisp`, `json.lisp`, `model-data.lisp`, `oauth/callback.lisp`, `oauth/openai-anthropic.lisp`, `oauth/pkce.lisp`, `oauth/providers/anthropic.lisp`, `oauth/providers/github-copilot.lisp`, `oauth/providers/kimi.lisp`, `oauth/providers/openai-device.lisp`, `oauth/providers/openrouter.lisp`, `oauth/providers/radius.lisp`, `oauth/providers/xai.lisp`, `provider.lisp`, `providers/anthropic.lisp`, `providers/azure-openai.lisp`, `providers/bedrock.lisp`, `providers/codex.lisp`, `providers/definitions.lisp`, `providers/google.lisp`, `providers/mistral.lisp`, `providers/openai-completions.lisp`, `providers/openai.lisp`, `providers/pi-messages.lisp`, `providers/registry.lisp`, `providers/runtime-projection.lisp`, `providers/vertex.lisp`, `runtime/faux-provider.lisp`, `sse.lisp`, `support/grammar-coercion.lisp`, `support/overflow.lisp`, `support/release.lisp`, `support/threads.lisp`, `support/token-estimation.lisp`, `support/uuid.lisp`, `transport/aws-event-stream.lisp`, `transport/http.lisp`, `websocket.lisp`.
  Dual-ref: H cell vs pi + K FiveAM/render-diff vs previous cadr.
- `covered-as-callee` (7): `conditions.lisp`, `models.generated.lisp`, `models.lisp`, `package.lisp`, `runtime/models.lisp`, `support/retry.lisp`, `types.lisp`.
  On a named paired thunk; no own bench.
- `unpairable` (2): `crash.lisp`, `oauth/page.lisp`.
  Single-ref vs previous cadr; do not invent a pi pair.

