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

**Tip inventory (denom 297 / 133658; `goal20-unpaired-paths.py --check`):** `needs-pair=0`, `pairable-uncovered=0`. Classes below that still say `pending H pair` / `pairable-uncovered` are historical at the K booking; current class is `paired` / `covered-as-callee` / `unpairable` per `docs/benchmarks/goal20-unpaired-paths.json`. Not 148 new benches.

Booked class from `docs/benchmarks/goal20-unpaired-paths.json`
via `classify` (longest prefix). No new unpairable.

28 `done` files:

- `paired` (1): `providers/openai-completions.lisp`
  (`provider_stream.stream_roundtrip`). Dual-ref: H cell vs
  pi, FiveAM vs previous cadr.
- `unpairable` (2): `oauth/page.lisp` (`oauth_success_page_mark`);
  `crash.lisp` (`fatal_condition_summary`). Single-ref vs
  previous cadr; H already marked the path.
- `pairable-uncovered` (25): the other `done` files. Single-ref
  vs previous cadr (FiveAM), pending H pair. Not 「不劣于 pi」.
